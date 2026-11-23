jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Powertrain = Drivetrain.Powertrain or {}

Drivetrain.Powertrain = Powertrain
Powertrain.__index    = Powertrain

Drivetrain.MaxPhysImpulse = 500000 -- deg·kg·m²/s, the most physics is handed in one tick

local ENTITY         = FindMetaTable("Entity")
local PHYSOBJ        = FindMetaTable("PhysObj")
local VECTOR         = FindMetaTable("Vector")
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid
local Clock          = ACF.Utilities.Clock
local TickInterval   = engine.TickInterval
local TickCount      = engine.TickCount
local min            = math.min

local MAX_STEP = 0.2 -- s, a longer hitch is not integrated in one go
local huge     = math.huge

--- Adapters step engines, each gearbox's wheels and effectors, wheels an engine drives with their direct
--- adapters, then the gearboxes, so gearboxes see their wheels before setting clutches.
--- @param System table
--- @param Adapters table
--- @param Engines table
function Powertrain.New(System, Adapters, Engines)
	return setmetatable({
		System      = System,
		Adapters    = Adapters,
		Engines     = Engines,
		Stale       = false,
		Resting     = false,
		MassRatio   = 1,
		Steps       = 0,
		Shafts      = {}, -- Engine shaft bodies, whose speeds carry over between ticks
		SpinChassis = false,
		SpinStep    = -1,
		ChassisSpin = false,
		PhysChassis = false,
		ChassisPhys = false,
		PhysStep    = -1,
		LastStep     = false,
		LastTick     = false,
		-- Set up on the first look for adapters that may skip, for finding what the running engines reach
		Links        = false,
		Sources      = false,
		Wheels       = false,
		Boxes        = false,
		Reached      = false,
		Queue        = false,
		Quiet        = false,
		Engaged      = false,
		Running      = false,
		QuietAny     = false,
		QuietKnown   = false,
		-- What the gearboxes put on ReactionPhys this step, applied once they all have
		Reaction     = Vector(),
		ReactionPhys = false,
	}, Powertrain)
end

local function Clear(Table)
	for Key in pairs(Table) do Table[Key] = nil end
end

-- A drivetrain with no engine, braking only, takes its contraption's count; without one it is a test stand,
-- as a lone engine is, and its wheels move only themselves
local function GetLooseMassRatio(Root)
	if not IsValid(Root) or not ENTITY.CFW_GetContraption(Root) then return 1 end

	return ACF.Contraption.UpdateMassRatio(Root).ACF_MassRatio or 1
end

-- Once per drivetrain: per body the clutches on it, the engines that may drive, and the wheels and gearboxes
-- that may skip
local function Survey(self)
	local Links, Sources, Wheels, Boxes = {}, {}, {}, {}

	for _, Clutch in ipairs(self.System.Clutches) do
		for Terminal = 1, Clutch.Terminals do
			local Body = Clutch:GetBody(Terminal)
			local List = Links[Body] or {}

			List[#List + 1] = Clutch
			Links[Body]     = List
		end
	end

	for _, Adapter in ipairs(self.Adapters) do Adapter:Enroll(Sources, Wheels, Boxes) end

	self.Links, self.Sources, self.Wheels, self.Boxes = Links, Sources, Wheels, Boxes
	self.Reached, self.Queue, self.Quiet  = {}, {}, {}
	self.Engaged, self.Running            = {}, {}
	self.QuietAny, self.QuietKnown        = false, false
end

-- Whether a clutch engaged or let go, or an engine started or stopped, since the reach was last found; notes
-- it as it is
local function HasChanged(self)
	local Clutches = self.System.Clutches
	local Sources  = self.Sources
	local Engaged  = self.Engaged
	local Running  = self.Running
	local Changed  = not self.QuietKnown

	for I = 1, #Clutches do
		local On = Clutches[I].MaxImpulse > 0

		if Engaged[I] ~= On then
			Engaged[I] = On
			Changed    = true
		end
	end

	for I = 1, #Sources do
		local On = not Sources[I]:IsResting()

		if Running[I] ~= On then
			Running[I] = On
			Changed    = true
		end
	end

	return Changed
end

-- Physics sleeps a body only together with everything constrained to it, so only a wheel in its chassis'
-- contraption is sure to be still while the chassis sleeps; one hung off something else, as a test stand's
-- flywheel, may be spinning
local function SleepsWithChassis(Wheel, Chassis)
	local Entity = Wheel.Entity

	if not IsValid(Entity) or not IsValid(Chassis) then return false end

	local Contraption = ENTITY.CFW_GetContraption(Entity)

	return Contraption ~= nil and Contraption == ENTITY.CFW_GetContraption(Chassis)
end

-- A gearbox brakes its wheels as it steps, so it can't skip while a wheel it drives doesn't
local function DrivesAwake(Box, Quiet)
	local Records = Box.Links

	for I = 1, #Records do
		local Target = Records[I].Target

		if Target:HoldsAwake(Quiet) then return true end
	end

	return false
end

-- Every body a running engine reaches through an engaged clutch, and the wheels and gearboxes left out of it
local function Reach(self, Chassis)
	local Links   = self.Links
	local Sources = self.Sources
	local Wheels  = self.Wheels
	local Boxes   = self.Boxes
	local Reached = self.Reached
	local Queue   = self.Queue
	local Quiet   = self.Quiet
	local Tail    = 0
	local Head    = 1

	Clear(Reached)
	Clear(Quiet)

	for I = 1, #Sources do
		local Shaft = Sources[I].Shaft

		if self.Running[I] and not Reached[Shaft] then
			Tail           = Tail + 1
			Queue[Tail]    = Shaft
			Reached[Shaft] = true
		end
	end

	while Head <= Tail do
		local List = Links[Queue[Head]]

		Head = Head + 1

		for I = 1, List and #List or 0 do
			local Clutch = List[I]

			for Terminal = 1, Clutch.MaxImpulse > 0 and Clutch.Terminals or 0 do
				local Other = Clutch:GetBody(Terminal)

				if not Reached[Other] then
					Reached[Other] = true
					Tail           = Tail + 1
					Queue[Tail]    = Other
				end
			end
		end
	end

	local Any, Pending = false, false

	for I = 1, #Wheels do
		local Wheel = Wheels[I]

		if not Reached[Wheel.Body] then
			-- Read at least once, so a clutch engaging later still pushes it the right way
			if not Wheel.AxisWorld then
				Pending = true
			elseif SleepsWithChassis(Wheel, Chassis) then
				Quiet[Wheel] = true
				Any          = true
			end
		end
	end

	for I = 1, #Boxes do
		local Box = Boxes[I]

		if not Box:IsReached(Reached) and not DrivesAwake(Box, Quiet) then
			-- Set up at least once, so its clutches hold what it last set them to
			if Box.Operational ~= nil then
				Quiet[Box] = true
				Any        = true
			else
				Pending = true
			end
		end
	end

	self.QuietAny   = Any
	self.QuietKnown = not Pending
end

--- Wheels and gearboxes no running engine reaches through a clutch engaged last tick, while their chassis
--- sleeps, have nothing to read or pass on, so they skip the step until something reaches or wakes them.
--- Physics sleeps a chassis together with everything constrained to it, so its sleep is the one check a tick;
--- what the engines reach is only found again when an engine or clutch changes.
--- @return table? # Adapter to true, or nil when none can skip
function Powertrain:FindQuiet()
	if not self.Boxes then Survey(self) end

	local First = self.Wheels[1]

	if not First or not IsValid(First.Reference) then return end

	local Chassis = ENTITY.GetAncestor(First.Reference)
	local Phys    = self:GetChassisPhys(Chassis)

	if not Phys or not PHYSOBJ.IsAsleep(Phys) then return end

	if HasChanged(self) then Reach(self, Chassis) end

	return self.QuietAny and self.Quiet or nil
end

--- A chassis' physics object, kept between steps as every fetch makes a new one, and checked once a step as
--- that check costs more than most physics calls.
--- @return physobj? # nil without a valid one
function Powertrain:GetChassisPhys(Chassis)
	if self.PhysChassis == Chassis and self.PhysStep == self.Steps then return self.ChassisPhys or nil end

	local Phys = self.PhysChassis == Chassis and self.ChassisPhys or nil

	if not IsPhysObjValid(Phys) then
		Phys = ENTITY.GetPhysicsObject(Chassis)
		Phys = IsPhysObjValid(Phys) and Phys or false
	end

	self.PhysChassis = Chassis
	self.ChassisPhys = Phys
	self.PhysStep    = self.Steps

	return Phys or nil
end

--- World angular velocity of a chassis, read once per step however many outputs measure against it.
--- @return vector? # nil without a physics object
function Powertrain:GetChassisSpin(Chassis)
	if self.SpinChassis == Chassis and self.SpinStep == self.Steps then return self.ChassisSpin or nil end

	local Phys = self:GetChassisPhys(Chassis)

	local Spin = Phys and PHYSOBJ.GetAngleVelocity(Phys) or false

	-- Physics keeps them in step, and asking it costs far more
	if Spin then VECTOR.Rotate(Spin, ENTITY.GetAngles(Chassis)) end

	self.SpinChassis = Chassis
	self.SpinStep    = self.Steps
	self.ChassisSpin = Spin

	return Spin or nil
end

--- Every gearbox's reaction on one chassis goes in as one push, as each push costs more than the sum it
--- saves.
--- @param Phys physobj
--- @param Torque vector # deg·kg·m²/s, world
function Powertrain:AddReaction(Phys, Torque)
	if self.ReactionPhys ~= Phys then self:ApplyReaction() end

	self.ReactionPhys = Phys

	VECTOR.Add(self.Reaction, Torque)
end

function Powertrain:ApplyReaction()
	local Phys = self.ReactionPhys

	if not Phys then return end

	local Reaction = self.Reaction

	self.ReactionPhys = false

	PHYSOBJ.ApplyTorqueCenter(Phys, Reaction)
	VECTOR.Zero(Reaction)
end

--- With every engine off and still and every wheel asleep, there's nothing to step until something wakes a
--- wheel.
function Powertrain:IsResting()
	local Adapters = self.Adapters

	for I = 1, #Adapters do
		if not Adapters[I]:IsResting() then return false end
	end

	return true
end

function Powertrain:Step(Now)
	local Tick      = TickCount()
	-- Not stepped for ticks, as a train that only brakes isn't
	local Resumed   = self.LastTick and Tick - self.LastTick > 1
	local DeltaTime = self.LastStep and not Resumed and min(Now - self.LastStep, MAX_STEP) or TickInterval()
	local Engines   = self.Engines
	local Adapters  = self.Adapters
	local MassRatio = 0

	self.LastStep = Now
	self.LastTick = Tick

	if self:IsResting() then
		if not self.Resting then
			for I = 1, #Adapters do
				local Adapter = Adapters[I]

				if Adapter.Rest then Adapter:Rest() end
			end

			self.Resting = true
		end

		return
	end

	-- Nothing was integrated over the gap, so it is one tick on from where it stopped, and no reading is
	-- compared with a prediction from before it
	if self.Resting or Resumed then
		local Bodies = self.System.Bodies

		for I = 1, #Bodies do Bodies[I]:Wake() end

		self.Resting = false
	end

	self.Steps = self.Steps + 1

	if Engines[1] then
		for I = 1, #Engines do MassRatio = MassRatio + Engines[I].MassRatio end

		self.MassRatio = MassRatio / #Engines
	else
		self.MassRatio = GetLooseMassRatio(self.Root)
	end

	local Quiet = self:FindQuiet()

	for I = 1, #Adapters do
		local Adapter = Adapters[I]

		if Quiet and Quiet[Adapter] then Adapter:StepAsleep(DeltaTime) else Adapter:PreStep(DeltaTime) end
	end

	local Finite = self.System:Step(DeltaTime)
	local Shafts = self.Shafts

	for I = 1, #Shafts do
		local Omega = Shafts[I].Omega

		if Omega ~= Omega or Omega == huge or Omega == -huge then Finite = false end
	end

	-- Nothing of a tick gone non-finite reaches physics or the entities, and the rebuild starts from their
	-- last speeds
	if not Finite then
		self.Stale = true

		return
	end

	for I = 1, #Adapters do
		local Adapter = Adapters[I]

		if not (Quiet and Quiet[Adapter] and Adapter.QuietPost) then Adapter:PostStep(DeltaTime) end
	end

	self:ApplyReaction()
end

--- A build marks every engine and gearbox it reaches, so a change on either end of a link rebuilds whatever
--- spans it.
--- @param Entity entity
--- @param Other entity?
function Drivetrain.Invalidate(Entity, Other)
	local Train = Entity.ACF_Powertrain
	local Con   = Entity:CFW_GetContraption()

	if Train then Train.Stale = true end
	-- A link changes which wheels, and so what around them, count as physical
	if Con then Con.ACF_MassTime = nil end
	if Other then Drivetrain.Invalidate(Other) end
end

--- Once per tick, however many of its engines think; a braking gearbox with no engine runs its own.
--- @param Engine entity # Or a gearbox
--- @param EngineTbl table
function Drivetrain.Run(Engine, EngineTbl)
	local Current = EngineTbl.ACF_Powertrain

	if not Current or Current.Stale then Current = Drivetrain.Build(Engine) end

	local Now = Clock.CurTime

	if Current.LastStep == Now then return end

	Current:Step(Now)
end

-- Only engines that work are built in, and damage stops or starts them without a link or their state changing
hook.Add("ACF_OnEntityDestroyed", "ACF Drivetrain", Drivetrain.Invalidate)
hook.Add("ACF_OnEntityRestored", "ACF Drivetrain", Drivetrain.Invalidate)

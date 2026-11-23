jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Adapters   = Drivetrain.Adapters
local Gearbox    = Adapters.Gearbox or {} -- Its subtypes load first and may have made it already

Adapters.Gearbox     = Gearbox
Gearbox.__index      = Gearbox
-- A plain gearbox is fed solidly, so dropping its clutch at idle can stall the engine
Gearbox.LaunchClutch = false

local ENTITY         = FindMetaTable("Entity")
local VECTOR         = FindMetaTable("Vector")
local abs            = math.abs

local RPM_TO_RADS = ACF.RPMToRadS
local Reaction    = Vector() -- Each gearbox sums into it in turn

--- Its rating caps the clutches feeding it, so at its rating it slips at its input while its outputs stay
--- locked together.
--- @param Entity entity
--- @param Input table
--- @param Train table
function Gearbox.New(Entity, Input, Train)
	return setmetatable({
		Entity     = Entity,
		EntTbl     = Entity:GetTable(),
		Input      = Input,
		Train      = Train,
		Links      = {},
		Feeds      = {},
		ShaftFeeds = {},
		Efficiency = 1,
		EffHealth  = false, -- What the efficiency was worked out from, as it only changes with damage
		EffMax     = false,
	}, Gearbox)
end

--- @param Clutch table
--- @param Link table
--- @param Target table
--- @param Sign number?
function Gearbox:AddLink(Clutch, Link, Target, Sign)
	local Links = self.Links

	Links[#Links + 1] = { Clutch = Clutch, Link = Link, Target = Target, Sign = Sign or 1 }
end

--- @param Clutch table
--- @param FromShaft boolean
function Gearbox:AddFeed(Clutch, FromShaft)
	local Feeds = self.Feeds

	Feeds[#Feeds + 1] = Clutch

	if FromShaft then
		local ShaftFeeds = self.ShaftFeeds

		ShaftFeeds[#ShaftFeeds + 1] = Clutch
	end
end

do -- MARK: As an output
	--- Fed by another gearbox, no more than this one's rating can reach it.
	function Gearbox:AdjustClutch(Clutch)
		Clutch.OutputCapacity = self.EntTbl.MaxTorque
	end

	--- Only what turns the wheels pushes back on the chassis, so a gearbox down the line takes none of it.
	function Gearbox:AddReaction() end

	function Gearbox:HoldsSpeed()
		return true
	end
end

--- In a plain gearbox both sides (0 left, 1 right) hang off its input.
function Gearbox:GetSideBody()
	return self.Input
end

--- Only finishing a shift moves a manual gearbox's gearing by itself.
function Gearbox:UpdateGearing(Entity, EntTbl)
	if EntTbl.InGear then return end

	EntTbl.UpdateGearing(Entity, self.Input.Omega / RPM_TO_RADS, nil, EntTbl)
end

function Gearbox:SetLink(Record, Operational, Rating, Efficiency)
	local EntTbl     = self.EntTbl
	local Clutch     = Record.Clutch
	local Side       = Record.Link.Side
	local Engagement = Side == 0 and EntTbl.LClutch or EntTbl.RClutch

	Clutch.Ratio      = (Side == 0 and self.LeftRatio or self.RightRatio) * Record.Sign
	Clutch.Multiplier = 1
	Clutch.Efficiency = Efficiency
	Clutch.Capacity   = Operational and Engagement * Rating or 0
end

-- Its gearing, rating and clutch engagement, set on its links as they stand
local function Recalculate(self, Entity, EntTbl, Operational)
	local Rating = EntTbl.MaxTorque

	self:UpdateGearing(Entity, EntTbl)

	self.Operational = Operational
	self.Rating      = Rating
	self.GearRatio   = EntTbl.GearRatio -- After the gearing update, as finishing a shift sets it
	self.LeftRatio   = EntTbl.GetSideRatio(Entity, 0, EntTbl)
	self.RightRatio  = EntTbl.GetSideRatio(Entity, 1, EntTbl)

	for _, Clutch in ipairs(self.ShaftFeeds) do
		Clutch.Ratio      = 1
		Clutch.Multiplier = 1
		Clutch.Capacity   = Rating
	end

	for _, Record in ipairs(self.Links) do
		self:SetLink(Record, Operational, Rating, self.Efficiency)

		Record.Capacity = Record.Clutch.Capacity
	end
end

--- Its gearing and clutches change only through its inputs, a shift, damage, its legality or a reconfigure,
--- so they are worked out again only then; every tick each link is just set back to them and handed to what
--- it drives, as a wheel's share changes as it goes.
--- @return boolean # Whether they were worked out again
function Gearbox:PreStep()
	local Entity      = self.Entity
	local EntTbl      = self.EntTbl
	local Operational = ACF.IsOperational(Entity, EntTbl)
	local Health      = EntTbl.ACF
	local Changed     = self.Always or EntTbl.ACF_GearingDirty or not EntTbl.InGear
		or Operational ~= self.Operational
		or EntTbl.GearRatio ~= self.GearRatio or EntTbl.MaxTorque ~= self.Rating

	if Health.Health ~= self.EffHealth or Health.MaxHealth ~= self.EffMax then
		self.Efficiency = EntTbl.GetEfficiency(Entity, EntTbl)
		self.EffHealth  = Health.Health
		self.EffMax     = Health.MaxHealth
		Changed         = true
	end

	if Changed then
		EntTbl.ACF_GearingDirty = false

		Recalculate(self, Entity, EntTbl, Operational)
	end

	for _, Record in ipairs(self.Links) do
		local Clutch = Record.Clutch

		Clutch.Multiplier = 1
		Clutch.Capacity   = Record.Capacity

		Record.Target:AdjustClutch(Clutch, EntTbl, Record.Link)
	end

	return Changed
end

--- Out of every running engine's reach on a sleeping chassis, its clutches hold what it last set them to and
--- nothing turns it, so there's nothing to pass on either. A driver's input or a shift still goes in when it
--- comes, so a clutch that engages finds it ready; anything else that changed meanwhile is caught when it
--- steps again, as it compares against what it last worked out.
Gearbox.QuietPost = true -- Its torque, slip and reaction stay as they were, all of it nothing at rest

function Gearbox:StepAsleep(DeltaTime)
	local EntTbl = self.EntTbl

	if EntTbl.ACF_GearingDirty or not EntTbl.InGear then self:PreStep(DeltaTime) end
end

--- Its body is too light to matter, so whatever it last turned at is picked up again on waking. Sorts itself
--- for the powertrain: a gearbox may skip its step while nothing reaches it, unless its gearing is worked out
--- every tick, as it then follows its speed even at rest.
function Gearbox:Enroll(_, _, Boxes)
	if not self.Always then Boxes[#Boxes + 1] = self end
end

--- @param Reached table # Bodies a running engine reaches
function Gearbox:IsReached(Reached)
	return Reached[self.Input] == true
end

--- Fed by another gearbox, it brakes nothing of that one's, so it never keeps it stepping.
function Gearbox:HoldsAwake()
	return false
end

function Gearbox:IsResting()
	return true
end

--- Impulse drawn from the input this tick, in the input's frame.
function Gearbox:GetDraw()
	local Draw = 0

	for _, Record in ipairs(self.Links) do Draw = Draw + Record.Clutch:GetDraw() end

	return Draw
end

-- The chassis takes exactly the opposite of what the gearbox puts into its wheels, so a vehicle can't turn
-- itself
local function ApplyReaction(Entity, Torque, Train)
	local Length = VECTOR.Length(Torque)

	if Length == 0 then return end

	local BoxPhys = Train:GetChassisPhys(ENTITY.GetAncestor(Entity))

	if not BoxPhys then return end

	-- Each wheel's push is capped already, and this mirrors what they were handed
	Train:AddReaction(BoxPhys, Torque)
end

Gearbox.ApplyReaction = ApplyReaction -- Engines turning wheels themselves react the same way

function Gearbox:PostStep(DeltaTime)
	local Entity    = self.Entity
	local EntTbl    = self.EntTbl
	local Capped    = false
	local LeftSlip  = false
	local RightSlip = false

	VECTOR.Zero(Reaction)

	for _, Record in ipairs(self.Links) do
		local Clutch = Record.Clutch

		Record.Target:AddReaction(Clutch, Reaction)

		if Clutch.Saturated and Clutch:IsActive() then
			if Record.Link.Side == 0 then LeftSlip = true else RightSlip = true end
		end
	end

	for _, Clutch in ipairs(self.Feeds) do
		if Clutch.Saturated then Capped = true end
	end

	ApplyReaction(Entity, Reaction, self.Train)

	EntTbl.ACF_InputOmega = self.Input.Omega -- Carried over when the drivetrain is rebuilt

	EntTbl.RecordTorque(Entity, abs(self:GetDraw()) / DeltaTime, Capped, LeftSlip, RightSlip, EntTbl)
end

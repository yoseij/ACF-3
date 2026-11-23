jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Adapters   = Drivetrain.Adapters
local Rolling    = Drivetrain.Rolling
local Wheel      = Adapters.Wheel or {}

Adapters.Wheel = Wheel
Wheel.__index  = Wheel

local ENTITY          = FindMetaTable("Entity")
local PHYSOBJ         = FindMetaTable("PhysObj")
local VECTOR          = FindMetaTable("Vector")
local IsPhysObjValid  = ACF.Optimizations.IsPhysObjValid
local IsMotionEnabled = PHYSOBJ.IsMotionEnabled
local Clock           = ACF.Utilities.Clock
local Clamp           = math.Clamp
local rad             = math.rad
local deg             = math.deg
local max             = math.max
local min             = math.min
local abs             = math.abs
local sqrt            = math.sqrt
local huge            = math.huge

local MAX_IMPULSE     = Drivetrain.MaxPhysImpulse
local IMMOVABLE       = Drivetrain.ImmovableInertia
local MIN_INERTIA     = 1e-3   -- kg·m², keeps a degenerate physics object solvable
-- Steps between inertia reads; a prop's mass rarely changes, and the observer covers the gap
local INERTIA_TICKS   = 66
-- rad/s; a wheel's tyre slips and grips faster than this, so the engine stops following it
local SHAFT_FREQUENCY = 2 * math.pi * 4
local SHAFT_DAMPING   = 1      -- Critical, so the shaft gives without ringing
-- rad/s; any push wakes a prop, so one this small is left out to let a parked vehicle sleep
local MIN_PUSH        = 1e-3
-- Of physics' angular velocity limit; past the limit it knocks the prop's whole spin back to this
local SPIN_SHARE      = 0.9
local CAP_REFRESH     = 1      -- s between reads of the limit, which an addon may change at any time
-- rad/s; slower than this a parked tyre only jitters on its contact, which stopping it dead each tick would
-- keep going
local ROLL_STILL      = 0.2
local ROLL_FULL       = 0.4    -- rad/s; rolling resistance fades in up to here, so there is no step
-- deg; under this on every axis an AdvBallsocket keeps two props turning together (0/0 still swings ~6)
local LOCKED_RANGE    = 1
-- Props locked to one wheel, so a contraption locked together some other way isn't walked whole
local MAX_GROUP       = 64
-- s a wheel's claim on a locked prop holds without it walking again, which it does every INERTIA_TICKS
local CLAIM_LIFE      = 3
local EMPTY           = {}
-- Locked prop to the wheel that pushes it, across every drivetrain
local OwnerOf         = setmetatable({}, { __mode = "kv" })
local ClaimedAt       = setmetatable({}, { __mode = "k" })
local Push            = Vector()
local SpinCap         = huge
local CapRead         = -huge
local Found           = {} -- Scratch for RefreshGroup, which never runs inside itself
local Queue           = {}

local function GetAxialInertia(Phys, Axis)
	local Inertia = PHYSOBJ.GetInertia(Phys)

	return max(Inertia.x * Axis.x * Axis.x + Inertia.y * Axis.y * Axis.y + Inertia.z * Axis.z * Axis.z,
		MIN_INERTIA)
end

-- m, half the widest the prop's box spans across its axle
local function GetRadius(Entity, Axis)
	local Size = ENTITY.OBBMaxs(Entity) - ENTITY.OBBMins(Entity)
	local Span = max(Size.x * (1 - abs(Axis.x)), Size.y * (1 - abs(Axis.y)), Size.z * (1 - abs(Axis.z)))

	return 0.5 * Span * ACF.InchToMeter
end

-- deg/s, the most a prop may spin about anything, read only now and then as it makes a new table every time
local function GetSpinCap()
	local Now = Clock.CurTime

	if Now - CapRead >= CAP_REFRESH or Now < CapRead then
		SpinCap = SPIN_SHARE * physenv.GetPerformanceSettings().MaxAngularVelocity
		CapRead = Now
	end

	return SpinCap
end

local function IsLocked(Constraint)
	return Constraint.Type == "AdvBallsocket"
		and abs((tonumber(Constraint.xmax) or 0) - (tonumber(Constraint.xmin) or 0)) < LOCKED_RANGE
		and abs((tonumber(Constraint.ymax) or 0) - (tonumber(Constraint.ymin) or 0)) < LOCKED_RANGE
		and abs((tonumber(Constraint.zmax) or 0) - (tonumber(Constraint.zmin) or 0)) < LOCKED_RANGE
end

-- One wheel pushes a locked prop, whichever drivetrain it is on; a claim lapses once its wheel's drivetrain
-- is rebuilt or it stops walking, so a removed or relinked wheel hands its props on
local function ClaimedByOther(Prop, Wheel)
	local Owner = OwnerOf[Prop]

	return Owner ~= nil and Owner ~= Wheel and not Owner.Train.Stale
		and Clock.CurTime - ClaimedAt[Prop] < CLAIM_LIFE
end

-- Unlinked props locked to the wheel through AdvBallsockets, in a chain or all to it, turn with it as one
-- body, as a track's road wheels do with its sprocket: pushed alone, the wheel leaves them to follow through
-- the constraints a tick late, and a braked track rolls down a slope. A wheel something drives has its own
-- adapter, and the chassis and ACF parts aren't wheels.
local function RefreshGroup(self)
	local Reference = self.Reference
	local Chassis   = IsValid(Reference) and ENTITY.GetAncestor(Reference)
	local AxisWorld = PHYSOBJ.LocalToWorldVector(self.Phys, self.Axis)
	local Group     = {}
	local Sum       = 0
	local Head      = 1
	local Now       = Clock.CurTime

	for _, Member in ipairs(self.Group) do
		if OwnerOf[Member.Entity] == self then OwnerOf[Member.Entity] = nil end
	end

	for Key in pairs(Found) do Found[Key] = nil end
	for I = #Queue, 1, -1 do Queue[I] = nil end

	Found[self.Entity] = true
	Queue[1]           = self.Entity

	while Queue[Head] and #Group < MAX_GROUP do
		local Entity = Queue[Head]

		Head = Head + 1

		for _, Constraint in pairs(Entity.Constraints or EMPTY) do
			local Other = IsValid(Constraint) and IsLocked(Constraint)
				and (Constraint.Ent1 == Entity and Constraint.Ent2 or Constraint.Ent1)

			if Other and IsValid(Other) and not Found[Other] and not ClaimedByOther(Other, self)
				and Other ~= Chassis and not Other.IsACFEntity and not IsValid(ENTITY.GetParent(Other))
				and not next(Other.ACF_Gearboxes or EMPTY) and not next(Other.ACF_Engines or EMPTY) then
				local Phys = ENTITY.GetPhysicsObject(Other)

				Found[Other] = true

				if IsPhysObjValid(Phys) then
					local Inertia = GetAxialInertia(Phys, PHYSOBJ.WorldToLocalVector(Phys, AxisWorld))

					Queue[#Queue + 1] = Other
					Group[#Group + 1] = { Entity = Other, Phys = Phys, Inertia = Inertia }
					OwnerOf[Other]    = self
					ClaimedAt[Other]  = Now
					Sum               = Sum + Inertia
				end
			end
		end
	end

	self.Group        = Group
	self.GroupInertia = Sum
end

-- Making the prop spherical or editing a Primitive gives it a new physics object, which takes over from the
-- old one
local function Rebind(self)
	local Entity = self.Entity
	local Phys   = IsValid(Entity) and ENTITY.GetPhysicsObject(Entity)

	if not Phys or not IsPhysObjValid(Phys) then return self.Phys, false, false end

	self.Phys       = Phys
	self.InertiaAge = 0 -- Its inertia, radius and what is locked to it are read again on its next step

	return Phys, true, PHYSOBJ.IsMotionEnabled(Phys)
end

--- @param Entity entity
--- @param Axis vector
--- @param Reference entity
--- @param Train table
--- @return table? # nil without a physics object
function Wheel.New(Entity, Axis, Reference, Train)
	local Phys = Entity:GetPhysicsObject()

	if not IsPhysObjValid(Phys) then return end

	local Inertia = GetAxialInertia(Phys, Axis)
	local Body    = Drivetrain.Output.New(Inertia)

	return setmetatable({
		Entity      = Entity,
		Phys        = Phys,
		Axis        = Vector(Axis), -- Local to the prop, from the first gearbox linked to it
		Reference   = Reference, -- Gearbox whose ancestor the spin is measured against
		Radius      = GetRadius(Entity, Axis),
		Train       = Train,
		Body        = Body,
		SpinCap     = Drivetrain.Limits.SpinCap.New(Body), -- For the builder to add to the system
		Inertia     = Inertia,
		InertiaAge  = 0, -- Read again on the first step, which also finds what is locked to it
		AxisWorld   = false,
		Usable      = false,
		Held        = false,
		Pushed      = false,
		-- Of the push it was asked for, what physics was handed, which its chassis then takes back
		PushShare   = 1,
		-- Clutch from a block that never turns, so braking pushes nothing back on the chassis
		Brake       = false,
		Group       = {}, -- Props locked to it, as { Entity, Phys, Inertia }
		GroupInertia = 0,
		Roles        = {}, -- Per link: whether its side was engaged, braked, both or neither last tick
	}, Wheel)
end

--- @param Clutch table # From a sink body to this wheel's body
function Wheel:AttachBrake(Clutch)
	self.Brake = Clutch
end

-- Every gearbox linked to the wheel may brake it, so each tick starts from none and the strongest wins
local function ReleaseBrake(self)
	local Brake = self.Brake

	if not Brake then return end

	Brake.Capacity    = 0
	Brake.Input.Omega = 0 -- The block never turns; the solver's nudges to it only round
end

--- @param Torque number # N·m at the wheel, already scaled by the mass ratio
function Wheel:ApplyBrake(Torque)
	local Brake = self.Brake

	if Brake and self.Usable and Torque > Brake.Capacity then Brake.Capacity = Torque end
end

--- The halfshaft and tyre between a gearbox and its wheel give a little, which keeps tyre stick-slip out of
--- the engine.
function Wheel:Couple(Clutch)
	local Clutches = self.SpinCap.Clutches

	Clutches[#Clutches + 1] = Clutch

	Clutch:SetCompliance(SHAFT_FREQUENCY, SHAFT_DAMPING)
end

--- Each gearbox signs the wheel's axis its own way, so its clutch counts the turning with this sign.
function Wheel:GetAxisSign(Axis)
	return VECTOR.Dot(Axis, self.Axis) < 0 and -1 or 1
end

-- Spin about the drive axis relative to the chassis, positive the way positive torque turns it, and the most
-- and least that spin may become, with the axis turned into the world on the way. The prop's own spin dots
-- with the axis in its own frame, so only the chassis' needs the axis in the world. Physics limits the prop's
-- whole spin, so its spin about other axes, as when the chassis turns, takes from what is left about this
-- one. Physics sets the prop's angles from its object after every step, so turning the axis by them gives
-- what asking the object would, for a fraction of what that costs.
local function GetSpin(Entity, Phys, Axis, AxisWorld, ChassisSpin)
	VECTOR.Set(AxisWorld, Axis)
	VECTOR.Rotate(AxisWorld, ENTITY.GetAngles(Entity))

	local Angular = PHYSOBJ.GetAngleVelocity(Phys)
	local Own     = VECTOR.Dot(Angular, Axis)
	local Carried = ChassisSpin and VECTOR.Dot(ChassisSpin, AxisWorld) or 0
	local Cap     = GetSpinCap()
	local Room    = sqrt(max(Cap * Cap - (VECTOR.LengthSqr(Angular) - Own * Own), 0))

	return -rad(Own - Carried), rad(Room + Carried), -rad(Room - Carried)
end

function Wheel:PreStep(DeltaTime)
	local Entity = self.Entity
	local Phys   = self.Phys
	local Body   = self.Body

	-- A physics object rebuilt or removed under it errors here, which is caught for nothing, where checking
	-- it first costs twice what reading it does
	local Live, Moving = pcall(IsMotionEnabled, Phys)

	if not Live then Phys, Live, Moving = Rebind(self) end

	ReleaseBrake(self)

	self.Usable = Live and Moving and IsValid(Entity) and not IsValid(ENTITY.GetParent(Entity))

	if not self.Usable then
		Body:Reset(Body.Omega) -- No prediction was made, so the next reading teaches nothing

		return
	end

	local Chassis   = ENTITY.GetAncestor(self.Reference)
	-- The prop hasn't moved by the time the push goes in, so PostStep reuses it
	local AxisWorld = self.AxisWorld or Vector()
	local SpinCap   = self.SpinCap

	local Spin, Most, Least = GetSpin(Entity, Phys, self.Axis, AxisWorld, self.Train:GetChassisSpin(Chassis))

	self.AxisWorld   = AxisWorld
	self.Held        = ENTITY.IsPlayerHolding(Entity)
	SpinCap.MaxOmega = Most
	SpinCap.MinOmega = Least

	-- A player's grip sets its spin and outmatches the drivetrain, so it holds like a weld and teaches no
	-- load
	if self.Held then
		Body.Inertia = IMMOVABLE
		Body:Reset(Spin)

		return
	end

	if self.InertiaAge <= 0 then
		self.Inertia    = GetAxialInertia(Phys, self.Axis)
		self.Radius     = GetRadius(Entity, self.Axis) -- Making it spherical after linking changes it too
		self.InertiaAge = INERTIA_TICKS

		RefreshGroup(self) -- Constraints change without telling anyone, and rarely
	end

	self.InertiaAge = self.InertiaAge - 1
	Body.Inertia    = self.Inertia + self.GroupInertia

	Body:Observe(Spin, DeltaTime)
end

--- Asleep and out of every running engine's reach, there's nothing to read: it holds still where it lies, and
--- the next real reading learns nothing from the gap. A clutch that engages this tick still finds it at rest.
function Wheel:StepAsleep()
	local Body    = self.Body
	local SpinCap = self.SpinCap
	local Cap     = rad(GetSpinCap())

	ReleaseBrake(self)
	Body:Reset(0)

	Body.Inertia     = self.Inertia + self.GroupInertia
	SpinCap.MaxOmega = Cap
	SpinCap.MinOmega = -Cap
	self.Held        = false
end

-- Engaged, braked, both or neither, from what the link's side is set to this tick
local function GetRole(Clutch, SourceTbl, Link)
	local Brake = Link.Side == 0 and SourceTbl.LBrake or SourceTbl.RBrake

	return (Clutch.Capacity > 0 and 1 or 0) + (Brake and Brake > 0 and not SourceTbl.Disabled and 2 or 0)
end

--- A braked wheel stays in gear, as only a clutch takes it out; the driver and the vehicle's mass ratio scale
--- its push and its engine braking alike. The gearbox's brake on the link's side is a torque, scaled by the
--- mass ratio as a push is, so it stops the vehicle as it would one of its full mass; an illegal gearbox
--- brakes nothing, a wrecked one still does.
function Wheel:AdjustClutch(Clutch, GearboxTbl, Link)
	local MassRatio = self.Train.MassRatio

	if not self.Usable then Clutch.Capacity = 0 end

	-- When the side swaps between driving and being held, as brake steering does with every change of
	-- direction, the ground's answer flips with it: the load learned before is about the new one's size the
	-- other way round, so it starts again from none rather than being unlearned first
	local Roles = self.Roles

	local Role = GetRole(Clutch, GearboxTbl, Link)
	local Last = Roles[Link]

	Roles[Link] = Role

	if Last and Last ~= Role then self.Body.Load = 0 end

	Clutch.Multiplier = Clutch.Multiplier * GearboxTbl.DriverCrewMod * MassRatio

	self:AdjustBrake(GearboxTbl, Link)
end

--- The brake on the link's side of what drives it, also from something that no longer drives it, such as a
--- wreck.
--- @param SourceTbl table # The gearbox's or engine's table
--- @param Link table
function Wheel:AdjustBrake(SourceTbl, Link)
	local Brake = Link.Side == 0 and SourceTbl.LBrake or SourceTbl.RBrake

	if Brake and Brake > 0 and not SourceTbl.Disabled then self:ApplyBrake(Brake * self.Train.MassRatio) end
end

--- What turns a wheel pushes back on the chassis that carries its gearbox, about the same world axis.
--- @param Clutch table
--- @param Sum vector # deg·kg·m²/s
function Wheel:AddReaction(Clutch, Sum)
	if not self.Pushed then return end

	local Impulse = deg(Clutch.Gain * Clutch.Impulse) * self.PushShare

	if Impulse == 0 then return end

	local Axis = self.AxisWorld

	Sum.x = Sum.x + Axis.x * Impulse
	Sum.y = Sum.y + Axis.y * Impulse
	Sum.z = Sum.z + Axis.z * Impulse
end

--- Asleep, physics found it still, and frozen or parented, the drivetrain can't turn it.
function Wheel:IsResting()
	local Phys = self.Phys

	if not IsPhysObjValid(Phys) then Phys = Rebind(self) end

	return not IsValid(self.Entity) or not IsPhysObjValid(Phys) or PHYSOBJ.IsAsleep(Phys)
		or not PHYSOBJ.IsMotionEnabled(Phys)
end

function Wheel:Enroll(_, Wheels)
	Wheels[#Wheels + 1] = self
end

--- A gearbox brakes its wheels as it steps, so it can't skip while one of them doesn't.
--- @param Quiet table # Adapters skipping this step
function Wheel:HoldsAwake(Quiet)
	return not Quiet[self]
end

function Wheel:HoldsSpeed()
	return true
end

-- The ground's own moment against a rolling tyre or track, so the chassis takes no reaction; it stops the
-- wheel at most. Only a tyre that rolls has any, so a parked wheel is left alone and physics can put it to
-- sleep. It opposes how the wheel turns now with what the drivetrain put in, not the turning its learned load
-- is expected to add: a braked wheel held still on a slope is predicted to roll down, and resisting that
-- would push it up the slope.
local function GetRollingImpulse(self, Body, DeltaTime)
	local Coefficient = ACF.RollingResistance

	if Coefficient <= 0 then return 0 end

	local Omega = Body.Omega - Body.Load * DeltaTime / Body.Inertia
	local Speed = abs(Omega)

	if Speed <= ROLL_STILL then return 0 end

	local Fade = min(1, (Speed - ROLL_STILL) / (ROLL_FULL - ROLL_STILL))
	local Most = Coefficient * Rolling.GetWheelLoad(self.Entity) * self.Radius * DeltaTime * Fade

	return Omega > 0 and -min(Most, Body.Inertia * Omega) or min(Most, -Body.Inertia * Omega)
end

function Wheel:PostStep(DeltaTime)
	local Body    = self.Body
	local Usable  = self.Usable and not self.Held
	local Impulse = Usable and Body.AppliedImpulse + GetRollingImpulse(self, Body, DeltaTime) or 0

	-- Its chassis takes the same push or none of it
	self.Pushed = Usable and abs(Impulse) >= MIN_PUSH * Body.Inertia

	if not self.Pushed then return end

	local AxisWorld = self.AxisWorld -- Gearboxes read the axis after this for their reaction
	local Turn      = -deg(Impulse)
	local Group     = self.Group

	if not Group[1] then
		local Applied = Clamp(Turn, -MAX_IMPULSE, MAX_IMPULSE)

		VECTOR.Set(Push, AxisWorld)
		VECTOR.Mul(Push, Applied)
		PHYSOBJ.ApplyTorqueCenter(self.Phys, Push)

		self.PushShare = Applied / Turn

		return
	end

	-- Locked together, each takes its share of the push about the same axle, so all of them change speed
	-- alike at once
	local Share   = Turn / (self.Inertia + self.GroupInertia)
	local Applied = Clamp(Share * self.Inertia, -MAX_IMPULSE, MAX_IMPULSE)

	VECTOR.Set(Push, AxisWorld)
	VECTOR.Mul(Push, Applied)
	PHYSOBJ.ApplyTorqueCenter(self.Phys, Push)

	for I = 1, #Group do
		local Member = Group[I]

		-- Taken by another wheel while this one slept, or removed since the last look, it misses its share
		-- until the next
		if OwnerOf[Member.Entity] == self then
			local Part = Clamp(Share * Member.Inertia, -MAX_IMPULSE, MAX_IMPULSE)

			VECTOR.Set(Push, AxisWorld)
			VECTOR.Mul(Push, Part)

			if pcall(PHYSOBJ.ApplyTorqueCenter, Member.Phys, Push) then Applied = Applied + Part end
		end
	end

	self.PushShare = Applied / Turn
end

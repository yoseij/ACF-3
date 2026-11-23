jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF      = ACF
local Adapters = ACF.Mobility.Drivetrain.Adapters
local Effector = Adapters.Effector or {}

Adapters.Effector = Effector
Effector.__index  = Effector

local abs = math.abs
local min = math.min

local RPM_TO_RADS = ACF.RPMToRadS

--- Its clutch drains the load it asks for into a still sink.
--- @param Entity entity
--- @param Clutch table
--- @param Train table
--- @param Feed table? # Body of the engine shaft that drives its gearbox; none on a gearbox that only brakes
function Effector.New(Entity, Clutch, Train, Feed)
	return setmetatable({
		Entity = Entity,
		Clutch = Clutch,
		Train  = Train,
		Feed   = Feed,
	}, Effector)
end

function Effector:PreStep()
	self.Clutch.Output.Omega = 0
end

function Effector:AdjustClutch(Clutch)
	local Entity = self.Entity

	if not IsValid(Entity) or Entity.Disabled then
		Clutch.Capacity = 0

		return
	end

	local Ratio = abs(Clutch.Ratio)
	local Load  = Entity:Calc(Ratio * abs(Clutch.Input.Omega) / RPM_TO_RADS) -- N·m at the effector

	Clutch.Capacity = min(Clutch.Capacity, Load * Ratio)
end

--- It pushes the vehicle through its own Act, so the chassis takes no reaction from the gearbox.
function Effector:AddReaction() end

--- Driven only, it has nothing to sort itself into, and nothing to brake.
function Effector:Enroll() end

function Effector:HoldsAwake()
	return false
end

--- It only pushes while its gearbox turns.
function Effector:IsResting()
	return true
end

--- Its sink never turns, so it can't hold its gearbox at any speed.
function Effector:HoldsSpeed()
	return false
end

function Effector:PostStep(DeltaTime)
	local Clutch = self.Clutch
	local Entity = self.Entity

	if Clutch.Impulse == 0 or not IsValid(Entity) then return end

	local Feed = self.Feed

	-- Its thrust follows the engine's speed, rather than its own shaft's
	Entity:Act(Clutch.Gain * Clutch.Impulse / DeltaTime, DeltaTime, self.Train.MassRatio,
		Feed and Feed.Omega / RPM_TO_RADS or 0)
end

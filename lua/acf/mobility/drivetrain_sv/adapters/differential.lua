jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF          = ACF
local Drivetrain   = ACF.Mobility.Drivetrain
local Adapters     = Drivetrain.Adapters
local Gearbox      = Adapters.Gearbox or {} -- Filled in by gearbox.lua, which loads after this
local Differential = Adapters.Differential or setmetatable({}, { __index = Gearbox })

Adapters.Gearbox      = Gearbox
Adapters.Differential = Differential
Differential.__index  = Differential

local abs  = math.abs
local huge = math.huge

-- kg·m², as light as a gearbox's own shaft, so neither side carries a flywheel of its own
local SIDE_INERTIA = 1e-4
local MIN_RATIO    = Drivetrain.MinRatio

--- Each side's outputs hang off its own side shaft, so with an open differential a side left disengaged takes
--- the drive from both. A clutch between the sides limits their slip in proportion to the torque passing
--- through, or locks them.
--- @param Entity entity
--- @param Input table
--- @param Train table
--- @param System table
function Differential.New(Entity, Input, Train, System)
	local Object = Gearbox.New(Entity, Input, Train)
	local Left   = System:AddBody(Drivetrain.Body.New(SIDE_INERTIA))
	local Right  = System:AddBody(Drivetrain.Body.New(SIDE_INERTIA))
	local Omega  = Input.Omega * Object.EntTbl.GearRatio

	Left.Omega  = Omega
	Right.Omega = Omega

	Object.Left     = Left
	Object.Right    = Right
	Object.Carrier  = System:AddClutch(Drivetrain.Differential.New(Input, Left, Right, 0, 0))
	Object.Locker   = System:AddClutch(Drivetrain.Clutch.New(Left, Right, 1, 1, 0))

	return setmetatable(Object, Differential)
end

function Differential:GetSideBody(Side)
	return Side == 0 and self.Left or self.Right
end

--- Its sides already turn at the carrier's speed, so an output only takes its direction; its clutch holds the
--- same torque.
function Differential:SetLink(Record, Operational, Rating, Efficiency)
	local EntTbl     = self.EntTbl
	local Clutch     = Record.Clutch
	local Engagement = Record.Link.Side == 0 and EntTbl.LClutch or EntTbl.RClutch
	local Ratio      = abs(EntTbl.GearRatio)

	Clutch.Ratio      = Record.Sign
	Clutch.Multiplier = 1
	Clutch.Efficiency = Efficiency
	Clutch.Capacity   = Operational and Ratio > MIN_RATIO and Engagement * Rating / Ratio or 0
end

function Differential:PreStep(DeltaTime)
	local Changed  = Gearbox.PreStep(self, DeltaTime)
	local EntTbl   = self.EntTbl
	local Carrier  = self.Carrier

	if Changed then
		Carrier.Ratio    = EntTbl.GearRatio
		Carrier.Capacity = self.Operational and huge or 0 -- The rating already holds back what feeds it
	end

	local Slip = EntTbl.DiffSlip

	if EntTbl.DiffLocked or Slip <= 0 then
		self.Locker.Capacity = huge
	else
		-- Torque sensing, as a real limited slip is: it may move (1 - slip) of each side's half of what the
		-- carrier passed last tick, a fixed torque bias of (2 - slip) / slip whatever the engine's size next
		-- to the rating
		self.Locker.Capacity = (1 - Slip) * 0.5 * abs(Carrier.Impulse) / DeltaTime
	end

	return Changed
end

--- Its sides count too, as a wheel linked to another gearbox as well may reach them.
function Differential:IsReached(Reached)
	return Reached[self.Input] or Reached[self.Left] or Reached[self.Right] or false
end

function Differential:GetDraw()
	return self.Carrier:GetDraw()
end

function Differential:PostStep(DeltaTime)
	local Locker = self.Locker

	self.EntTbl.DiffSlipping = Locker:IsActive() and Locker.Saturated

	Gearbox.PostStep(self, DeltaTime)
end

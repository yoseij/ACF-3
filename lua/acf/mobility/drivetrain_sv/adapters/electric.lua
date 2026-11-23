jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF      = ACF
local Adapters = ACF.Mobility.Drivetrain.Adapters
local Engine   = Adapters.Engine or {} -- Filled in by engine.lua, which loads after this
local Electric = Adapters.Electric or setmetatable({}, { __index = Engine })

Adapters.Engine   = Engine
Adapters.Electric = Electric
Electric.__index  = Electric
Electric.CanStall = false -- Full torque from standstill

local IsValid     = IsValid
local abs         = math.abs
local min         = math.min
local RPM_TO_RADS = ACF.RPMToRadS

function Electric.New(Entity, Shaft, Friction)
	local Object = setmetatable(Engine.New(Entity, Shaft, Friction), Electric)

	Object.ChargeShare = 0
	Object.ChargeTank  = false

	return Object
end

--- An electric motor: its throttle is signed, so it drives either way, and its friction clutch is its
--- regenerative brake.
function Electric:UpdateState()
	local Active = self.EntTbl.Active

	self:SetState(Active, false)
end

--- A flat battery leaves it switched on but powerless, so it can still charge.
function Electric:GetThrottle()
	local EntTbl = self.EntTbl

	EntTbl.RevLimited = false

	return EntTbl.Active and not EntTbl.Discharged and EntTbl.Throttle or 0
end

function Electric:GetStarter()
	return 0
end

-- Its windings and inverter lose with the square of the current, so of the torque, whatever its speed
local function GetCopper(EntTbl, Torque)
	local Type  = EntTbl.TypeData
	local Rated = EntTbl.PeakTorqueHeld

	return (Type and Type.CopperLoss or 0) * EntTbl.PeakPower * 1e3 * (Torque / Rated) ^ 2
end

--- What it draws is the work its torque does, plus the losses it pays to do it: holding torque at a
--- standstill still costs its copper loss, and torque against the way it turns comes back as charge, as an
--- inverter regenerates.
--- @param EntTbl table
--- @param Throttle number
--- @param Omega number
--- @return number # kWh per second before the fuel rate, negative while charging
function Electric.GetFuelRate(EntTbl, Throttle, Omega)
	local Drive = Engine.GetDrive(EntTbl, Throttle, Omega)
	local Power = Drive * Omega + abs(Throttle) * Engine.GetLosses(EntTbl, Omega) * abs(Omega)
		+ GetCopper(EntTbl, Drive)

	return EntTbl.FuelUse * Power * 1e-3
end

--- Its draw is worked out from the losses it has, so it needs no scaling.
function Electric.GetFuelScale()
	return 1
end

local function CanCharge(Tank)
	return IsValid(Tank) and Tank:CanCharge()
end

-- The battery it last charged, or the one it draws from, or any other linked one with room left
local function FindChargeTank(self, EntTbl)
	local Tank = self.ChargeTank

	-- Unless that battery is no longer one of its tanks
	if CanCharge(Tank) and EntTbl.FuelTanks[Tank] then return Tank end

	Tank = EntTbl.FuelTank

	if CanCharge(Tank) then return Tank end

	for Other in pairs(EntTbl.FuelTanks) do
		if CanCharge(Other) then return Other end
	end

	return false
end

--- Regenerating, it brakes as hard as it could drive at that speed, down to where its copper loss would eat
--- what it recovers, so it fades out towards a standstill; with nowhere to put the charge, it coasts.
function Electric:GetHold(Omega, Throttle)
	local EntTbl = self.EntTbl
	local Hold   = Engine.GetHold(self, Omega, Throttle)
	local Regen  = EntTbl.Regen
	local Charge = 0
	local Tank   = false

	if Regen ~= 0 and EntTbl.Active then Tank = FindChargeTank(self, EntTbl) end

	if Tank then
		local Rated  = EntTbl.PeakTorqueHeld
		local Copper = GetCopper(EntTbl, Rated)
		local Speed  = abs(Omega)

		Charge = Regen * EntTbl.PeakTorque
			* ACF.GetTorque(EntTbl.TorqueCurve, Speed / (EntTbl.LimitRPM * RPM_TO_RADS))

		-- Recovers its copper loss and no more
		if Copper > 0 then Charge = min(Charge, Speed * Rated * Rated / Copper) end
	end

	self.ChargeTank  = Tank
	-- Its bearings brake it too, but charge nothing
	self.ChargeShare = Charge > 0 and Charge / (Hold + Charge) or 0

	return Hold + Charge
end

--- Heard by the current through it, which goes with its torque, driving or regenerating, and not with the
--- throttle, so a flat battery falls quiet. Switched off it is silent, as nothing drives its windings.
--- @param EntTbl table
--- @return number # rpm
--- @return number # Load
--- @return number # Level
function Electric.GetSound(EntTbl)
	local Torque = abs(EntTbl.Torque) + EntTbl.RegenTorque

	return abs(EntTbl.FlyRPM), min(Torque / EntTbl.PeakTorqueHeld, 1), EntTbl.Active and 1 or 0
end

function Electric:PostStep(DeltaTime)
	Engine.PostStep(self, DeltaTime)

	local Tank   = self.ChargeTank
	local Brake  = abs(self.Friction.Impulse * self.ChargeShare) / DeltaTime
	local EntTbl = self.EntTbl

	EntTbl.RegenTorque = Brake

	if Brake == 0 or not IsValid(Tank) then return end

	-- What it brakes with adds to the current its drive already draws, so the copper it costs is the
	-- difference
	local Omega  = self.Shaft.Omega
	local Drive  = self.Combustion
	local Total  = Drive - (Omega < 0 and -Brake or Brake)
	local Copper = GetCopper(EntTbl, Total) - GetCopper(EntTbl, Drive)
	local Charge = EntTbl.FuelUse * (Brake * abs(Omega) - Copper) * DeltaTime * 1e-3

	Tank:Consume(-Charge)

	EntTbl.FuelUsage = EntTbl.FuelUsage - 60 * Charge / DeltaTime
end

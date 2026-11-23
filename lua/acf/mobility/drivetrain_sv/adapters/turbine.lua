jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF      = ACF
local Adapters = ACF.Mobility.Drivetrain.Adapters
local Engine   = Adapters.Engine or {} -- Filled in by engine.lua, which loads after this
local Turbine  = Adapters.Turbine or setmetatable({}, { __index = Engine })

Adapters.Engine  = Engine
Adapters.Turbine = Turbine
Turbine.__index  = Turbine
Turbine.CanStall = false -- A load can hold its output still but never stall it

local Clamp = math.Clamp
local abs   = math.abs
local max   = math.max
local min   = math.min

-- s from cold to lit and idling; real ones take tens of seconds, shortened so it is still a choice in a fight
local SPOOL_UP    = 12
local SPOOL_DOWN  = 10 -- s its gas generator takes to run down once switched off
local ACCEL_TIME  = 2 -- s, the time constant its gas generator follows a throttle step up with
local DECEL_TIME  = 1 -- s, down; fuel is cut at once but the gas generator still has to slow
-- Throttle its idle fuel flow amounts to at the power turbine, so it creeps in gear without stalling
local IDLE_FLOW   = 0.1
-- Share of its rated fuel flow it burns just keeping its gas generator turning, as an AGT1500's ~11 of ~110
-- gal/h
local IDLE_FUEL   = 0.1
local SETTLED     = 1e-3 -- Below which a gas generator with no fuel counts as stopped
local REST_OMEGA  = 0.1 -- rad/s below which a switched off turbine counts as stopped
local RPM_PER_KW  = 9548.8 -- N·m·rpm per kW

function Turbine.New(Entity, Shaft, Friction)
	return setmetatable(Engine.New(Entity, Shaft, Friction), Turbine)
end

--- A gas turbine with a free power turbine: its gas generator keeps itself running at any output speed, so a
--- load can hold the output still but never stall it, and it follows the fuel control with a lag, which is
--- the throttle lag turbines are known for. Switched back on before it ran down, it picks up from where it
--- was.
function Turbine:UpdateState(Omega, DeltaTime)
	local EntTbl  = self.EntTbl
	local Active  = EntTbl.Active
	local Spool   = Clamp(EntTbl.Spool + (Active and DeltaTime / SPOOL_UP or -DeltaTime / SPOOL_DOWN), 0, 1)
	local Command = Active and Spool * max(EntTbl.Throttle, min(self:GetGovernor(Omega), IDLE_FLOW)) or 0
	local GasGen  = EntTbl.GasGenerator

	GasGen = GasGen + (Command - GasGen) * min(DeltaTime / (Command > GasGen and ACCEL_TIME or DECEL_TIME), 1)

	if Command == 0 and GasGen < SETTLED then GasGen = 0 end

	EntTbl.Spool        = Spool
	EntTbl.GasGenerator = GasGen

	self:SetState(Active and Spool == 1, Active and Spool < 1)
end

function Turbine:GetThrottle()
	local EntTbl = self.EntTbl

	EntTbl.RevLimited = false

	return EntTbl.GasGenerator
end

function Turbine:GetStarter()
	return 0
end

--- Its fuel feeds the gas generator, whatever the power turbine turns at, so held still by its load at full
--- throttle it burns as much as flat out; idling, it burns its idle share just to keep itself turning.
--- @param EntTbl table
--- @param GasGenerator number
--- @return number # Fuel mass per second, before the fuel's density
function Turbine.GetFuelRate(EntTbl, GasGenerator)
	local Share = IDLE_FUEL + (1 - IDLE_FUEL) * max(GasGenerator - IDLE_FLOW, 0) / (1 - IDLE_FLOW)

	return EntTbl.FuelUse * EntTbl.PeakPower * RPM_PER_KW * Share
end

--- Rated at full power already.
function Turbine.GetFuelScale()
	return 1
end

--- Heard from its gas generator rather than its output, so it whines up as it spools and down as it runs
--- down, and screams at full throttle even with its output held still.
--- @param EntTbl table
--- @return number # rpm, the gas generator's speed mapped onto the output's idle-redline band
--- @return number # Load
--- @return number # Level
function Turbine.GetSound(EntTbl)
	local Spool = EntTbl.Spool
	local Load  = max(EntTbl.GasGenerator - IDLE_FLOW, 0) / (1 - IDLE_FLOW)
	local Idle  = EntTbl.IdleRPM

	return Spool * (Idle + (EntTbl.LimitRPM - Idle) * Load), Load, Spool
end

function Turbine:IsBurning()
	return self.EntTbl.Active
end

function Turbine:IsResting()
	local EntTbl = self.EntTbl

	return not EntTbl.Active and EntTbl.Spool == 0 and EntTbl.GasGenerator == 0
		and abs(self.Shaft.Omega) < REST_OMEGA
end

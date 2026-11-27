jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF      = ACF
local Adapters = ACF.Mobility.Drivetrain.Adapters
local Engine   = Adapters.Engine or {}

Adapters.Engine = Engine
Engine.__index  = Engine
Engine.CanStall = true -- So its shaft gets a launch clutch

local Remap    = math.Remap
local Clamp    = math.Clamp
local abs      = math.abs
local max      = math.max
local min      = math.min

local REV_LIMIT     = 0.99 -- Share of the redline where the rev limiter cuts the throttle
-- Share of the redline where, with the rev limiter off, its torque has fallen away to nothing
local OVERREV       = 1.25
local GOVERNOR_BAND = 0.2  -- Share of idle below it where the idle governor is at full authority
-- The idle governor opens to this many times the throttle the engine idles on with nothing to turn, so it holds
-- idle against small loads but lugs and stalls in a high gear, as a real idle control does
local IDLE_RESERVE  = 2
local STALL_SHARE   = 0.5  -- Share of idle below which a piston engine stops firing
-- Share of idle a piston engine must be turned at to fire, by its starter or its wheels
local CATCH_SHARE   = 0.6
local STARTER_SHARE = 0.3  -- Starter torque, as a share of peak torque
local CRANK_TIME    = 2    -- s a starter cranks before giving up
local RESTART_DELAY = 1    -- s a stalled engine waits before cranking again while still switched on
local REST_OMEGA    = 0.1  -- rad/s below which a switched off engine counts as stopped
local CRANK_LEVEL   = 0.6  -- Loudness of an engine being turned over by its starter, against one firing
local RPM_TO_RADS   = ACF.RPMToRadS

--- A piston engine. Its friction clutch holds the shaft to the engine block by the losses that don't grow
--- with speed, so the vehicle can roll against it or be held by it. Other engine kinds inherit from it and
--- override what differs.
--- @param Entity entity
--- @param Shaft table
--- @param Friction table
function Engine.New(Entity, Shaft, Friction)
	local Object = setmetatable({
		Entity     = Entity,
		EntTbl     = Entity:GetTable(),
		Shaft      = Shaft,
		Friction   = Friction,
		Throttle   = 0,
		Combustion = 0,
	}, Engine)

	Shaft:AddSource(Object)

	Object.IdleAuthority = Engine.GetIdleAuthority(Object.EntTbl)

	return Object
end

function Engine:SetState(Firing, Cranking)
	local EntTbl = self.EntTbl

	if Firing == EntTbl.Firing and Cranking == EntTbl.Cranking then return end

	EntTbl.Firing   = Firing
	EntTbl.Cranking = Cranking

	-- Past the overlay's cooldown, which would keep showing the state it just left
	self.Entity:UpdateOverlay(true)
end

--- Firing, cranking or stalled, from the speed the shaft starts the tick at. A stalled engine left switched
--- on cranks again by itself, and turning it past its catch speed, as rolling the vehicle in gear does, makes
--- it fire without the starter.
function Engine:UpdateState(Omega, DeltaTime)
	local EntTbl    = self.EntTbl
	local Firing    = EntTbl.Firing
	local Cranking  = EntTbl.Cranking
	local IdleOmega = EntTbl.IdleRPM * RPM_TO_RADS

	if not EntTbl.Active then
		Firing   = false
		Cranking = false
	elseif Firing then
		if Omega < STALL_SHARE * IdleOmega then
			Firing = false

			EntTbl.StarterClock = 0
		end
	elseif Omega >= CATCH_SHARE * IdleOmega then
		Firing   = true
		Cranking = false
	else
		local Clock = EntTbl.StarterClock + DeltaTime

		if Clock >= (Cranking and CRANK_TIME or RESTART_DELAY) then
			Cranking = not Cranking
			Clock    = 0
		end

		EntTbl.StarterClock = Clock
	end

	self:SetState(Firing, Cranking)
end

--- Share of throttle the idle governor opens at this speed.
function Engine:GetGovernor(Omega)
	local IdleRPM = self.EntTbl.IdleRPM

	return Clamp((IdleRPM - Omega / RPM_TO_RADS) / (GOVERNOR_BAND * IdleRPM), 0, 1)
end

--- The idle governor's opening, held to what idle control can give.
function Engine:GetIdleThrottle(Omega)
	return min(self:GetGovernor(Omega), self.IdleAuthority or 1)
end

--- The driver's throttle, opened by the idle governor and cut by the rev limiter. A governed engine isn't
--- cut: its governor fades the torque past the limit instead, in GetDrive.
function Engine:GetThrottle(Omega)
	local EntTbl     = self.EntTbl
	local RevLimited = false
	local Throttle   = 0

	if EntTbl.GovernorDroop then
		EntTbl.RevLimited = Omega > EntTbl.LimitRPM * RPM_TO_RADS

		return EntTbl.Firing and max(EntTbl.Throttle, self:GetIdleThrottle(Omega)) or 0
	end

	if EntTbl.Firing then
		RevLimited = EntTbl.revLimiterEnabled and Omega > REV_LIMIT * EntTbl.LimitRPM * RPM_TO_RADS
		Throttle   = RevLimited and 0 or max(EntTbl.Throttle, self:GetIdleThrottle(Omega))
	end

	EntTbl.RevLimited = RevLimited

	return Throttle
end

function Engine:GetStarter()
	return self.EntTbl.Cranking and STARTER_SHARE * self.EntTbl.PeakTorqueHeld or 0
end

--- Torque its friction clutch holds against the block. Full throttle leaves none, as the torque curve is net
--- of friction.
function Engine:GetHold(_, Throttle)
	return (1 - abs(Throttle)) * self.EntTbl.LossConstant
end

function Engine:IsBurning()
	return self.EntTbl.Firing
end

--- What the throttle makes it turn the shaft with, net of its losses as the curve is.
--- @param EntTbl table
--- @param Throttle number
--- @param Omega number
--- @return number # N·m
local function GetDrive(EntTbl, Throttle, Omega)
	local Limit = EntTbl.LimitRPM * RPM_TO_RADS
	local Over  = abs(Omega) / Limit - 1
	local Share = 1

	-- Past its redline it can only brake, unless the rev limiter is off: then it runs out of breath instead,
	-- as at full throttle its losses are already in the curve and nothing else would stop it revving without
	-- bound. A governor fades it out over its droop, so a governed engine settles above its limit rather than
	-- bouncing off a cut.
	if Over >= 0 and Throttle * Omega >= 0 then
		local Droop = EntTbl.GovernorDroop

		if EntTbl.revLimiterEnabled and not Droop then
			Share = 0
		else
			Share = max(1 - Over / (EntTbl.revLimiterEnabled and Droop or OVERREV - 1), 0)
		end
	end

	if Throttle == 0 or Share == 0 then return 0 end

	local Position = Remap(abs(Omega), EntTbl.IdleRPM * RPM_TO_RADS, Limit, 0, 1)

	return Share * Throttle * EntTbl.PeakTorque * ACF.GetTorque(EntTbl.TorqueCurve, Position)
end

Engine.GetDrive = GetDrive

--- Its losses at a speed, all of them, as it would have to overcome them turning itself over.
--- @param EntTbl table
--- @param Omega number
--- @return number # N·m
function Engine.GetLosses(EntTbl, Omega)
	local Speed = abs(Omega) / (EntTbl.LimitRPM * RPM_TO_RADS)

	return EntTbl.LossConstant + EntTbl.LossLinear * Speed + EntTbl.LossQuadratic * Speed * Speed
end

--- Most of the throttle the idle governor may open: the reserve times the throttle it idles on unloaded, where
--- its drive at idle meets the losses the closed throttle leaves.
--- @param EntTbl table
--- @return number
function Engine.GetIdleAuthority(EntTbl)
	local Omega  = EntTbl.IdleRPM * RPM_TO_RADS
	local Drive  = GetDrive(EntTbl, 1, Omega)
	local Losses = Engine.GetLosses(EntTbl, Omega)

	if Drive + Losses <= 0 then return 1 end

	return min(1, IDLE_RESERVE * Losses / (Drive + Losses))
end

--- Fuel goes on the work the burning does, which is what reaches the shaft plus the losses it pays on the
--- way, so it is linear in throttle and an idling engine burns just what its own friction takes.
--- @param EntTbl table
--- @param Throttle number
--- @param Omega number
--- @return number # Fuel mass per second, before the fuel's density
function Engine.GetFuelRate(EntTbl, Throttle, Omega)
	local Indicated = abs(GetDrive(EntTbl, Throttle, Omega)) + abs(Throttle) * Engine.GetLosses(EntTbl, Omega)

	return EntTbl.FuelUse * Indicated * abs(Omega) / RPM_TO_RADS
end

--- Its rated consumption is a brake-specific one at peak power, so the indicated work it is charged on is
--- scaled back by the losses it pays there.
--- @param EntTbl table
--- @return number
function Engine.GetFuelScale(EntTbl)
	local Omega = (EntTbl.PeakPowerRPM or EntTbl.LimitRPM) * RPM_TO_RADS
	local Drive = GetDrive(EntTbl, 1, Omega)

	if Drive <= 0 then return 1 end

	return Drive / (Drive + Engine.GetLosses(EntTbl, Omega))
end

--- How it sounds. A piston engine is heard firing, or chugging as its starter turns it over; stalled it is
--- silent.
--- @param EntTbl table
--- @return number # rpm its note follows
--- @return number # Load, 0 to 1, what it adds to the loudness
--- @return number # Level, 0 to 1, how loud it is overall
function Engine.GetSound(EntTbl)
	local Firing = EntTbl.Firing

	return abs(EntTbl.FlyRPM), Firing and abs(EntTbl.Throttle) or 0,
		Firing and 1 or EntTbl.Cranking and CRANK_LEVEL or 0
end

function Engine:GetTorque(Omega)
	local EntTbl   = self.EntTbl
	local Throttle = self.Throttle
	local Speed    = Omega / (EntTbl.LimitRPM * RPM_TO_RADS)
	local Drive    = GetDrive(EntTbl, Throttle, Omega)

	self.Combustion = Drive

	return Drive + self:GetStarter()
		- (1 - abs(Throttle)) * (EntTbl.LossLinear * Speed + EntTbl.LossQuadratic * Speed * abs(Speed))
end

function Engine:PreStep(DeltaTime)
	local Entity   = self.Entity
	local EntTbl   = self.EntTbl
	local Friction = self.Friction
	local Omega    = self.Shaft.Omega

	self:UpdateState(Omega, DeltaTime)

	local Throttle = self:GetThrottle(Omega)

	self.Throttle         = Throttle
	EntTbl.FuelThrottle   = Throttle -- What it burns on, governed and cut, rather than the driver's
	Friction.Output.Omega = 0
	Friction.Capacity     = self:GetHold(Omega, Throttle)

	if self:IsBurning() then
		EntTbl.ConsumeFuel(Entity, DeltaTime, EntTbl) -- Can switch the engine off
	else
		EntTbl.FuelUsage = 0
	end
end

function Engine:PostStep()
	local EntTbl = self.EntTbl

	EntTbl.FlyRPM = self.Shaft.Omega / RPM_TO_RADS
	EntTbl.Torque = self.Combustion
end

--- Switched off and stopped, so nothing it drives moves unless something else wakes it.
--- Sorts itself for the powertrain: an engine may drive, so what it reaches can't skip.
function Engine:Enroll(Sources)
	Sources[#Sources + 1] = self
end

function Engine:IsResting()
	return not self.EntTbl.Active and abs(self.Shaft.Omega) < REST_OMEGA
end

--- Settles the creep left under the rest threshold, which losses that fade with speed would never take out.
function Engine:Rest()
	self.Shaft.Omega   = 0
	self.EntTbl.FlyRPM = 0
end

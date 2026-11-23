jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF          = ACF
local Limits       = ACF.Mobility.Drivetrain.Limits
local Base         = Limits.Base
local LaunchClutch = Limits.LaunchClutch or setmetatable({}, { __index = Base })

Limits.LaunchClutch  = LaunchClutch
LaunchClutch.__index = LaunchClutch

local huge = math.huge
local max  = math.max
local min  = math.min

-- Share of idle a launch clutch bites at, so the engine pulls away on more than its idle torque
local BITE_SHARE  = 1.5
local RPM_TO_RADS = ACF.RPMToRadS
local IMMOVABLE   = ACF.Mobility.Drivetrain.ImmovableInertia

--- A centrifugal clutch, as automatics have: what it feeds takes only what the engine spins above its bite
--- speed, so it slips to hold the engine there instead of stalling it. Limited by the speed itself, it would
--- make torque from nothing.
--- @param Shaft table
--- @param Clutches table
--- @param BiteOmega number
function LaunchClutch.New(Shaft, Clutches, BiteOmega)
	local Object = Base.New(Shaft, Clutches)

	Object.BiteOmega = BiteOmega
	Object.Touching  = {} -- Per body, the clutches on it, from Attach
	Object.Pinned    = false
	Object.Sign      = 0

	return setmetatable(Object, LaunchClutch)
end

--- Bites above the idle of the engines switched on: only an engine that can stall needs one, so a motor
--- driving on its own, as a hybrid's does with its engine off, pulls away from standstill.
--- @param Shaft table
--- @param Clutches table
--- @param Engines table # Entity tables of the engines on the shaft
function LaunchClutch.ForEngines(Shaft, Clutches, Engines)
	local Object = LaunchClutch.New(Shaft, Clutches, 0)

	Object.Engines = Engines

	return Object
end

--- The clutches on each body its feeds touch, to tell where a solve leaves those bodies before it is
--- committed.
--- @param Clutches table # Every clutch in the system
function LaunchClutch:Attach(Clutches)
	local Touching = {}

	for _, Clutch in ipairs(Clutches) do
		for Terminal = 1, Clutch.Terminals do
			local Body = Clutch:GetBody(Terminal)
			local List = Touching[Body] or {}

			List[#List + 1] = Clutch
			Touching[Body]  = List
		end
	end

	self.Touching = Touching
end

-- A body's speed once the impulses just solved are in, as committing them will set it
local function Settled(self, Body)
	if Body.Inertia >= IMMOVABLE then return Body.Omega end

	local List  = self.Touching[Body]
	local Delta = 0

	for I = 1, List and #List or 0 do
		local Clutch = List[I]

		for Terminal = 1, Clutch.Terminals do
			if Clutch:GetBody(Terminal) == Body then
				Delta = Delta + Clutch:GetEffect(Terminal) * Clutch.Impulse
			end
		end
	end

	return Body.Omega + Delta / Body.Inertia
end

-- Below the bite speed it lets nothing through that drives the way the shaft turns. With a single feed that
-- would, the feed is held at nothing before the solve rather than solved, found pulling and solved again:
-- holding it is what the limit would end up doing, which the check after the solve confirms.
local function Pin(self, Omega)
	local Sign = Omega >= 0 and self.Upper == 0 and 1 or Omega < 0 and self.Lower == 0 and -1

	if not Sign then return end

	local Clutches = self.Clutches
	local Feed

	for I = 1, #Clutches do
		local Clutch = Clutches[I]

		if Clutch.MaxImpulse > 0 then
			-- Several share what the limit allows, so they are solved and then scaled to it
			if Feed then return end

			Feed = Clutch
		end
	end

	-- The engine side ahead of the feed is what makes it pull; behind, it is driven and stays free
	if not Feed or Sign * (Feed:GetSlip() + Feed.Bias) <= 0 then return end

	Feed.Fixed   = true
	Feed.Impulse = 0

	self.Pinned = Feed
	self.Sign   = Sign
end

function LaunchClutch:Prepare()
	local Engines = self.Engines

	if Engines then
		local Idle = 0

		for I = 1, #Engines do
			local EntTbl = Engines[I]

			if EntTbl.Active and EntTbl.IdleRPM > Idle then Idle = EntTbl.IdleRPM end
		end

		self.BiteOmega = BITE_SHARE * Idle * RPM_TO_RADS
	end

	local Shaft = self.Body
	local Bite  = self.BiteOmega
	local Omega = Shaft.Omega

	-- Either way round, it holds back only what drives the way the shaft turns; the wheels may always spin it
	-- faster
	if Bite <= 0 then
		self.Upper = huge
		self.Lower = -huge
	elseif Omega >= 0 then
		self.Upper = max(Shaft.Inertia * (Omega - Bite), 0)
		self.Lower = -huge
	else
		self.Upper = huge
		self.Lower = min(Shaft.Inertia * (Omega + Bite), 0)
	end

	self.Pinned = false

	if Bite > 0 then Pin(self, Omega) end
end

--- After the first solve, a pinned feed stays held only if it would still have pulled with everything else
--- solved: its own impulse, added back, has the sign of the slip the rest leaves it. Otherwise it is let go
--- and solved again.
--- @return boolean # Whether it held any clutch back
function LaunchClutch:Restrict()
	local Feed = self.Pinned

	if not Feed then return Base.Restrict(self) end

	self.Pinned = false

	local Slip = Feed.Ratio * Settled(self, Feed.Input) - Settled(self, Feed.Output) + Feed.Bias

	if self.Sign * Slip >= 0 then return false end

	Feed.Fixed = false

	return true
end

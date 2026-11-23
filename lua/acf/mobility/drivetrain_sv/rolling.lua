jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF         = ACF
local Drivetrain  = ACF.Mobility.Drivetrain
local Rolling     = Drivetrain.Rolling or {}
local Contraption = ACF.Contraption
local Clock       = ACF.Utilities.Clock

Drivetrain.Rolling = Rolling

-- m/s², so a coefficient means what published tables of them mean, whatever sv_gravity is
local STANDARD_GRAVITY = 9.81
local REFRESH          = 2    -- s between counts of a contraption's driven wheels, which rarely change
local Counts           = setmetatable({}, { __mode = "k" }) -- Contraption to { Next, Count }

-- Parented parts press on the ground through nothing physics simulates, and the mass ratio already shrinks
-- the push to match, so only the mass the vehicle carries weighs on its wheels; something dragged far behind
-- bears on its own. Every mass ratio recount stores it, as sorting a contraption's parts takes far longer
-- than a tick should; only a vehicle nothing has counted yet is counted here, once.
local function GetPhysicalMass(Con, Wheel)
	if not Con.ACF_PhysicalMass then Contraption.CalcMassRatio(Wheel) end

	return Con.ACF_PhysicalMass
end

local EMPTY   = {}
local DRIVERS = { "acf_gearbox", "acf_engine" } -- Engines too, as a wheel can hang straight off a crank

local function CountDrivenWheels(Con)
	local Seen  = {}
	local Count = 0

	for _, Class in ipairs(DRIVERS) do
		for Source in pairs(Con.entsbyclass[Class] or EMPTY) do
			for Wheel in pairs(Source.ACF_LiveData.Wheels) do
				if not Seen[Wheel] then
					Seen[Wheel] = true
					Count       = Count + 1
				end
			end
		end
	end

	return Count
end

--- N each driven wheel of a vehicle bears: undriven road wheels and the track between them carry part of the
--- weight, so splitting all of it over the driven ones puts the vehicle's whole rolling resistance where the
--- drivetrain feels it. Aircraft get none: their driven "wheels" are propellers turning in air, not tyres on
--- the ground.
--- @param Wheel entity
--- @return number
function Rolling.GetWheelLoad(Wheel)
	local Con = Wheel:CFW_GetContraption()

	if not Con then return 0 end

	local Now   = Clock.CurTime
	local Entry = Counts[Con]

	if not Entry then
		Entry       = { Next = -math.huge }
		Counts[Con] = Entry
	end

	if Now >= Entry.Next then
		Entry.Count = Con:ACF_IsAircraft() and 0 or CountDrivenWheels(Con)
		Entry.Next  = Now + REFRESH
	end

	local Count = Entry.Count

	return Count > 0 and GetPhysicalMass(Con, Wheel) * STANDARD_GRAVITY / Count or 0
end

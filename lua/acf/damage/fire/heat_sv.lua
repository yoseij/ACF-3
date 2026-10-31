local ACF     = ACF
local Damage  = ACF.Damage
local Fire    = Damage.Fire
local Classes = ACF.Classes
local min     = math.min
local max     = math.max
local pi      = math.pi

local SIGMA            = 5.67e-8 -- Stefan-Boltzmann constant, W/m²/K⁴
local AMBIENT          = 293 -- K
local RADIANT_FRACTION = 0.3 -- Share of a fire's heat radiated, as for a sooty fuel fire treated as a point source
local MIN_FLUX         = 1000 -- W/m², heat below this is ignored, which bounds how far a fire reaches
local MAX_FLUX         = 100e3 -- W/m², about what an engulfing fuel fire puts on a surface
local TRACES           = 2 -- Randomized lines from each fire to each entity it heats, per fire tick
local WALL_EMISSIVITY  = 0.8 -- Oxidized steel; how well a heated wall radiates from its far side
local DOSE_HALF_LIFE   = 300 -- Seconds for a component to cool off; caps the dose at flux x 433 s, so it must reach the ignition doses

Fire.MaxFlux = MAX_FLUX

-- Kept across reloads so hot walls survive a refresh of this file
Fire.HotWalls = Fire.HotWalls or {} -- HotWalls[Convex] = Entity, for convexes warmer than ambient

do -- MARK: Heat dose and damage
	--- Adds heat to an entity's dose, letting whatever it built up before cool off first.
	--- @return number # The entity's accumulated dose in J/m².
	function Fire.AddHeatDose(Entity, Flux, DeltaTime)
		local Now  = CurTime()
		local Dose = (Entity.ACF_HeatDose or 0) * 0.5 ^ ((Now - (Entity.ACF_HeatDoseTime or Now)) / DOSE_HALF_LIFE)

		Dose = Dose + Flux * DeltaTime

		Entity.ACF_HeatDose     = Dose
		Entity.ACF_HeatDoseTime = Now

		return Dose
	end

	--- Slowly wears down a component sitting in more heat than it can take.
	function Fire.DamageComponent(Entity, Flux, DeltaTime)
		local Excess = Flux - ACF.FireContactFlux
		local EntACF = Entity.ACF

		if Excess <= 0 or not EntACF or not EntACF.MaxHealth or EntACF.Health <= 0 then return end

		EntACF.Health = max(EntACF.Health - EntACF.MaxHealth * ACF.FireDamageRate * Excess * 1e-5 * DeltaTime, 0)

		if Entity.ACF_OnHeatDamage then Entity:ACF_OnHeatDamage() end

		ACF.RefreshCondition(Entity)
	end
end

do -- MARK: Hot walls
	local HeatCapacities = {} -- J/m³/K per material

	local function GetHeatCapacity(Material)
		local Capacity = HeatCapacities[Material]

		if Capacity then return Capacity end

		local ArmorType = Classes.GetSubtypeByName("ACF.ArmorTypes.BaseArmorType", "ACF.ArmorTypes." .. tostring(Material))

		Capacity = ArmorType and ArmorType.Density * 1000 * ArmorType.SpecificHeat or 3.9e6

		HeatCapacities[Material] = Capacity

		return Capacity
	end

	--- @return number # W/m² a heated wall radiates from its far side.
	function Fire.GetWallEmission(Convex)
		local Temp = Convex.FireTemp or AMBIENT

		return WALL_EMISSIVITY * SIGMA * (Temp ^ 4 - AMBIENT ^ 4)
	end

	--- Lumped heating of each wall a fire reached, across its thickness, losing heat by radiating it back out.
	function Fire.UpdateWalls(DeltaTime)
		local HotWalls = Fire.HotWalls

		for Convex, Entity in pairs(HotWalls) do
			if not IsValid(Entity) then
				HotWalls[Convex] = nil
			else
				local Incident = Convex.FireIncident or 0
				local Temp     = Convex.FireTemp or AMBIENT
				local Capacity = GetHeatCapacity(Convex.Material) * max(Convex.MinWidth * ACF.InchToMeter, 0.001) -- J/m²/K
				local Balance  = (Incident / SIGMA + AMBIENT ^ 4) ^ 0.25
				local Absorbed = WALL_EMISSIVITY * (Incident - SIGMA * (Temp ^ 4 - AMBIENT ^ 4))
				local NewTemp  = Temp + Absorbed * DeltaTime / Capacity

				-- Thin walls would overshoot within a tick, never pass the temperature they settle at
				NewTemp = Temp < Balance and min(NewTemp, Balance) or max(NewTemp, Balance)

				Convex.FireIncident = nil

				if Incident <= 0 and NewTemp - AMBIENT < 1 then -- Slow-heating walls gain less than this per tick
					Convex.FireTemp = nil

					HotWalls[Convex] = nil
				else
					Convex.FireTemp = NewTemp
				end
			end
		end
	end
end

do -- MARK: Heat transport
	local Unheated = { -- Structure rather than components
		acf_baseplate      = true,
		acf_turret         = true,
		acf_turret_rotator = true,
	}

	local Ignore = {}
	local Ray    = {} -- The line being traced, kept here so its visitors aren't rebuilt for every line

	local function FluxAt(Origin, HeatRelease, Position)
		local Distance = max(Origin:Distance(Position) * ACF.InchToMeter, 0.25)

		return min(RADIANT_FRACTION * HeatRelease / (4 * pi * Distance * Distance), MAX_FLUX)
	end

	local function RandomPoint(Entity)
		local Mins, Maxs = Entity:OBBMins(), Entity:OBBMaxs()
		local Center     = (Mins + Maxs) * 0.5
		local Point      = Vector(math.Rand(Mins.x, Maxs.x), math.Rand(Mins.y, Maxs.y), math.Rand(Mins.z, Maxs.z))

		return Entity:LocalToWorld(Center + (Point - Center) * 0.8)
	end

	-- A wall in the way heats up and only passes on what it radiates from its far side
	local function VisitWall(Layer, Convex)
		if Ray.Cap <= 0 then return end

		local Incident = min(Ray.Cap, FluxAt(Ray.Origin, Ray.HeatRelease, Layer.EntryPos))

		if Incident > (Convex.FireIncident or 0) then Convex.FireIncident = Incident end

		Fire.HotWalls[Convex] = Ray.Wall

		Ray.Cap = min(Ray.Cap, Fire.GetWallEmission(Convex))
	end

	local function VisitHit(Result)
		if Result.HitWorld then
			Ray.Cap = 0

			return true
		end

		local Hit = Result.Entity

		if Hit == Ray.Target then return true end

		Ray.Wall = Hit

		Damage.ForEachSolidLayer(Hit, Result.HitPos, Ray.Direction, VisitWall)

		return Ray.Cap <= 0
	end

	-- Heat reaching Target along one random line from the fire, through the holes and walls in between
	local function RayFlux(Source, Target, Origin, HeatRelease)
		local Start  = RandomPoint(Source)
		local Finish = RandomPoint(Target)

		Ray.Origin      = Origin
		Ray.HeatRelease = HeatRelease
		Ray.Target      = Target
		Ray.Direction   = (Finish - Start):GetNormalized()
		Ray.Cap         = math.huge
		Ignore[1]       = Source

		Damage.PierceLine(Start, Finish, Ignore, VisitHit)

		return min(Ray.Cap, FluxAt(Origin, HeatRelease, Finish))
	end

	local function IsHeated(Entity)
		return Entity.ACF_OnHeat ~= nil or (Entity.IsACFEntity and not Unheated[Entity:GetClass()])
	end

	--- Adds the heat a fire radiates onto everything within its reach.
	--- @param Exposure table Exposure[Entity] = W/m², summed over every fire this tick.
	function Fire.SpreadHeat(Entity, HeatRelease, Exposure)
		local Origin = Entity:WorldSpaceCenter()
		local Range  = math.sqrt(RADIANT_FRACTION * HeatRelease / (4 * pi * MIN_FLUX)) / ACF.InchToMeter

		for _, Target in ipairs(ents.FindInSphere(Origin, Range)) do
			if Target ~= Entity and not Fire.Burning[Target] and IsHeated(Target) then
				local Flux = 0

				for _ = 1, TRACES do
					Flux = Flux + RayFlux(Entity, Target, Origin, HeatRelease)
				end

				Exposure[Target] = (Exposure[Target] or 0) + Flux / TRACES
			end
		end
	end

	local function Heat(Target, Flux, DeltaTime)
		if Target.ACF_OnHeat then
			Target:ACF_OnHeat(Flux, DeltaTime)
		else
			Fire.DamageComponent(Target, Flux, DeltaTime)
		end
	end

	--- Hands every heated entity what it received this tick.
	function Fire.ApplyHeat(Exposure, DeltaTime)
		for Target, Flux in pairs(Exposure) do
			Flux = min(Flux, MAX_FLUX)

			-- Runs in the fire timer, which an error would remove
			if Flux > 0 and IsValid(Target) then xpcall(Heat, ErrorNoHaltWithStack, Target, Flux, DeltaTime) end
		end
	end
end

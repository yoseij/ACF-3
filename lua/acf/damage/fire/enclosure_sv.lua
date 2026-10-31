local ACF    = ACF
local Damage = ACF.Damage
local Fire   = Damage.Fire

local VENT_WALL_RHA = 10 -- mm RHA, thinner walls give way to a cookoff and count as openings
local VENT_RAYS     = 256 -- Directions surveyed around an entity
local VENT_RANGE    = 600 -- gmu, how far to look for walls; past it the gas is out

local Directions = {}

do -- Evenly spread over the sphere (golden spiral)
	local Golden = math.pi * (3 - math.sqrt(5))

	for I = 0, VENT_RAYS - 1 do
		local Z = 1 - I / (VENT_RAYS - 1) * 2
		local R = math.sqrt(1 - Z * Z)

		Directions[I + 1] = Vector(math.cos(Golden * I) * R, math.sin(Golden * I) * R, Z)
	end
end

-- The vehicle's own bounding box, as no enclosure in it can be bigger
local function GetBoundingVolume(Contraption)
	local MinX, MinY, MinZ = math.huge, math.huge, math.huge
	local MaxX, MaxY, MaxZ = -math.huge, -math.huge, -math.huge

	for Ent in pairs(Contraption.ents) do
		if IsValid(Ent) then
			local Mins, Maxs = Ent:WorldSpaceAABB()

			MinX, MinY, MinZ = math.min(MinX, Mins.x), math.min(MinY, Mins.y), math.min(MinZ, Mins.z)
			MaxX, MaxY, MaxZ = math.max(MaxX, Maxs.x), math.max(MaxY, Maxs.y), math.max(MaxZ, Maxs.z)
		end
	end

	return (MaxX - MinX) * (MaxY - MinY) * (MaxZ - MinZ) * ACF.InchToMeter ^ 3
end

--- Surveys the walls around an entity: what its gas can escape through, and how much room it has.
--- Only intact armor, the ground, and the edge of the vehicle's own volume count as walls. Holes, thin plates
--- and the vehicle's other parts don't hold gas, so a crate in a hull has the whole hull around it.
--- @param Entity entity The entity to survey around.
--- @return number # Area in m² of the openings to the outside.
--- @return number # Volume in m³ of the space around the entity, capped at its vehicle's bounding box.
function Fire.SurveyEnclosure(Entity)
	local Center      = Entity:WorldSpaceCenter()
	local Contraption = Entity:CFW_GetContraption()
	local Ignore      = { Entity }
	local Share       = 4 * math.pi / VENT_RAYS -- Steradians each direction stands for
	local Vent, Volume = 0, 0
	local Walls, WallSum, Free = 0, 0, 0 -- Rays that hit a wall and how far, and rays that met nothing at all
	local Direction, Armor, Walled, Last

	local function Visit(Result)
		local Distance = Result.HitPos:Distance(Center) * ACF.InchToMeter

		if Result.HitWorld then
			Walled, Last = true, Distance

			return true
		end

		local Hit = Result.Entity

		-- Other vehicles and loose props are no part of this one's walls, and a loose entity has none but the ground
		if not Contraption or Hit:CFW_GetContraption() ~= Contraption then return end

		Armor = Armor + Damage.GetSolidArmor(Hit, Result.HitPos, Direction)
		Last  = Distance

		if Armor >= VENT_WALL_RHA then
			Walled = true

			return true
		end
	end

	for _, Dir in ipairs(Directions) do
		Direction, Armor, Walled, Last = Dir, 0, false, nil

		Damage.PierceLine(Center, Center + Dir * VENT_RANGE, Ignore, Visit)

		if Walled then
			Walls   = Walls + 1
			WallSum = WallSum + Last
			Volume  = Volume + Share * Last ^ 3 / 3
		elseif Last then
			Vent = Vent + Share * Last ^ 2 -- Cone of the opening where the gas leaves
		else
			Free = Free + 1
		end
	end

	-- More than half of all directions open means no enclosure to speak of, the gas just expands into the air.
	-- Fewer are gaps in a wall, which are only as big as the enclosure's walls are far away.
	local Range = VENT_RANGE * ACF.InchToMeter
	local Reach = (Free * 2 > VENT_RAYS or Walls == 0) and Range or WallSum / Walls

	Vent = Vent + Free * Share * Reach ^ 2

	if Contraption then Volume = math.min(Volume, GetBoundingVolume(Contraption)) end

	return Vent, Volume
end

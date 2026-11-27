local ACF         = ACF
local Contraption = ACF.Contraption

local IsEntityValid  = ACF.Optimizations.IsEntityValid
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid
local ENTITY         = FindMetaTable("Entity")
local PHYSOBJ        = FindMetaTable("PhysObj")
local VECTOR         = FindMetaTable("Vector")
local TickInterval   = engine.TickInterval
local abs, max, min  = math.abs, math.max, math.min

local AIR_DENSITY  = 1.225 -- kg/m³, sea level, so a coefficient means what published tables of them mean
local MIN_SPEED    = 40    -- u/s, below which drag is a few newtons at most
local SQUARE_METER = ACF.InchToMeter * ACF.InchToMeter

do -- MARK: Frontal area
	local HUGE         = math.huge
	local GlobalFilter = ACF.GlobalFilter
	local ceil, floor  = math.ceil, math.floor
	local CELL         = 4   -- u, about 10 cm
	local MAX_CELLS    = 256 -- a side, so a huge contraption costs no more to measure than a big one
	local Parts        = {}  -- Centre and half extents of each part in the baseplate's frame, six numbers a part
	local Grid         = {}  -- Cell index to the stamp of the last silhouette that covered it, so it is never cleared
	local Stamp        = 0

	--- m² covered by the parts seen along one of the baseplate's axes. A silhouette rather than the box around
	--- them, so a gun turned sideways adds its barrel and not the whole width it reaches across.
	--- @param Count number
	--- @param U number # Which of a part's axes runs across the view: 1, 2 or 3
	--- @param V number
	--- @return number
	local function Silhouette(Count, U, V, MinU, SpanU, MinV, SpanV)
		local Cell    = max(CELL, SpanU / MAX_CELLS, SpanV / MAX_CELLS)
		local Width   = floor(SpanU / Cell) + 1
		local Covered = 0

		Stamp = Stamp + 1

		for I = 0, Count - 1 do
			local Base   = I * 6
			local CU, EU = Parts[Base + U], Parts[Base + U + 3]
			local CV, EV = Parts[Base + V], Parts[Base + V + 3]

			-- Cells whose centres it covers, so a part thinner than a cell counts about its own width
			for J = ceil((CV - EV - MinV) / Cell - 0.5), floor((CV + EV - MinV) / Cell - 0.5) do
				local Row = J * Width

				for K = ceil((CU - EU - MinU) / Cell - 0.5), floor((CU + EU - MinU) / Cell - 0.5) do
					local Index = Row + K

					if Grid[Index] ~= Stamp then
						Grid[Index] = Stamp
						Covered     = Covered + 1
					end
				end
			end
		end

		return Covered * Cell * Cell * SQUARE_METER
	end

	--- Only what shells hit, as visual meshes and holograms are often larger than what they dress or stowed
	--- off to one side.
	--- @param Con table
	--- @param Baseplate entity
	local function Measure(Con, Baseplate)
		local MinX, MinY, MinZ = HUGE, HUGE, HUGE
		local MaxX, MaxY, MaxZ = -HUGE, -HUGE, -HUGE
		local Count = 0

		for Ent in pairs(Con.ents) do
			if IsEntityValid(Ent) and ENTITY.IsSolid(Ent) and not GlobalFilter[ENTITY.GetClass(Ent)] then
				local Lo, Hi = ENTITY.GetCollisionBounds(Ent)
				local Center = ENTITY.LocalToWorld(Ent, (Lo + Hi) * 0.5)
				local Pos    = ENTITY.WorldToLocal(Baseplate, Center)
				local Ang    = ENTITY.WorldToLocalAngles(Baseplate, ENTITY.GetAngles(Ent))
				local Fwd, Right, Up = Ang:Forward(), Ang:Right(), Ang:Up()
				local HX, HY, HZ = (Hi.x - Lo.x) * 0.5, (Hi.y - Lo.y) * 0.5, (Hi.z - Lo.z) * 0.5

				-- Half extents of the rotated box along the baseplate's axes
				local EX = abs(Fwd.x) * HX + abs(Right.x) * HY + abs(Up.x) * HZ
				local EY = abs(Fwd.y) * HX + abs(Right.y) * HY + abs(Up.y) * HZ
				local EZ = abs(Fwd.z) * HX + abs(Right.z) * HY + abs(Up.z) * HZ
				local Base = Count * 6

				Parts[Base + 1], Parts[Base + 2], Parts[Base + 3] = Pos.x, Pos.y, Pos.z
				Parts[Base + 4], Parts[Base + 5], Parts[Base + 6] = EX, EY, EZ
				Count = Count + 1

				MinX, MaxX = min(MinX, Pos.x - EX), max(MaxX, Pos.x + EX)
				MinY, MaxY = min(MinY, Pos.y - EY), max(MaxY, Pos.y + EY)
				MinZ, MaxZ = min(MinZ, Pos.z - EZ), max(MaxZ, Pos.z + EZ)
			end
		end

		if Count == 0 then
			Con.ACF_DragAreaX, Con.ACF_DragAreaY, Con.ACF_DragAreaZ = 0, 0, 0

			return
		end

		local SpanX, SpanY, SpanZ = MaxX - MinX, MaxY - MinY, MaxZ - MinZ

		Con.ACF_DragAreaX = Silhouette(Count, 2, 3, MinY, SpanY, MinZ, SpanZ)
		Con.ACF_DragAreaY = Silhouette(Count, 1, 3, MinX, SpanX, MinZ, SpanZ)
		Con.ACF_DragAreaZ = Silhouette(Count, 1, 2, MinX, SpanX, MinY, SpanY)
	end

	--- Aircraft builders set their own drag, so theirs is left to physics.
	--- @param Con table
	--- @param Baseplate entity
	function Contraption.UpdateDragArea(Con, Baseplate)
		if Con:ACF_IsAircraft() then
			Con.ACF_DragAreaX, Con.ACF_DragAreaY, Con.ACF_DragAreaZ = 0, 0, 0
		else
			Measure(Con, Baseplate)
		end
	end

	-- Measured again only once it is built differently, not as its turret turns or parts are shot off
	local function Stale(Con)
		if Con then Con.ACF_DragAreaX = nil end
	end

	hook.Add("cfw.contraption.entityAdded", "ACF Air Drag", Stale)
	hook.Add("cfw.contraption.merged", "ACF Air Drag", function(_, Into) Stale(Into) end)
	hook.Add("cfw.contraption.split", "ACF Air Drag", function(Parent, Child) Stale(Parent) Stale(Child) end)

	-- Its baseplate type or a part's size may have changed
	hook.Add("ACF_OnUpdateEntity", "ACF Air Drag", function(_, Entity)
		if IsValid(Entity) then Stale(Entity:CFW_GetContraption()) end
	end)
end

do -- MARK: Drag
	local MeterToInch = ACF.MeterToInch
	local InchToMeter = ACF.InchToMeter

	--- Grows with the square of speed and not with mass, so it is what holds back a light vehicle with a lot of
	--- power, where rolling resistance holds back a heavy one.
	--- @param Baseplate entity
	--- @param Coefficient number
	--- @param DeltaTime number
	local function ApplyDrag(Baseplate, Coefficient, DeltaTime)
		if not IsEntityValid(Baseplate) then return end

		local Phys = ENTITY.GetPhysicsObject(Baseplate)

		if not IsPhysObjValid(Phys) or PHYSOBJ.IsAsleep(Phys) or not PHYSOBJ.IsMotionEnabled(Phys) then return end

		local Velocity = PHYSOBJ.GetVelocity(Phys)
		local Speed    = VECTOR.Length(Velocity)

		if Speed < MIN_SPEED then return end

		local Con = ENTITY.CFW_GetContraption(Baseplate)

		if not Con then return end
		if not Con.ACF_DragAreaX then Contraption.UpdateDragArea(Con, Baseplate) end

		local Local = PHYSOBJ.WorldToLocalVector(Phys, Velocity)
		local Area  = (abs(Local.x) * Con.ACF_DragAreaX + abs(Local.y) * Con.ACF_DragAreaY
			+ abs(Local.z) * Con.ACF_DragAreaZ) / Speed

		if Area <= 0 then return end

		local Count  = Contraption.UpdateMassRatio(Baseplate)
		local Meters = Speed * InchToMeter
		local Force  = 0.5 * AIR_DENSITY * Coefficient * Area * Meters * Meters

		-- Scaled by the mass ratio like the drivetrain's push, so parented mass slows down as if it were physical;
		-- never more than stops the vehicle
		local Impulse = min(Force * DeltaTime * MeterToInch * (Count.ACF_MassRatio or 1), Count.ACF_PhysicalMass * Speed)

		VECTOR.Mul(Velocity, -Impulse / Speed)
		PHYSOBJ.ApplyForceCenter(Phys, Velocity)
	end

	hook.Add("Tick", "ACF Air Drag", function()
		local Coefficient = ACF.DragCoefficient

		if Coefficient <= 0 then return end

		local Baseplates = ACF.ActiveBaseplatesArray
		local DeltaTime  = TickInterval()

		for I = 1, #Baseplates do
			ApplyDrag(Baseplates[I], Coefficient, DeltaTime)
		end
	end)
end

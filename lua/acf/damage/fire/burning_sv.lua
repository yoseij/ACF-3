local ACF     = ACF
local Fire    = ACF.Damage.Fire
local HookRun = hook.Run

-- Kept across reloads so lit fires survive a refresh of this file
Fire.Burning = Fire.Burning or {} -- Burning[Entity] = true

do -- MARK: Ignition
	local SourceNames = {
		Hit        = "hit",
		Jet        = "HEAT jet",
		Fire       = "flames",
		HotSurface = "hot engine",
		Heat       = "heat",
	}

	--- Works out what could have lit fuel from a damage event.
	--- Explosions light whatever their fireball reaches as flames would.
	--- @param Entity entity The entity that was hit.
	--- @param DmgInfo table The DamageInfo object of the hit.
	--- @return string|nil # "Hit", "Jet" or "Fire", or nil if it can't ignite anything.
	function Fire.GetIgnitionSource(Entity, DmgInfo)
		if DmgInfo:GetType() == DMG_PLASMA then return "Fire" end -- The torch

		local Source = DmgInfo:GetIgnition()
		local Radius = DmgInfo:GetFireballRadius()

		if Radius and (Source == "Blast" or Source == "Hit") then
			local Origin = DmgInfo:GetOrigin()

			if Entity:NearestPoint(Origin):DistToSqr(Origin) <= Radius * Radius then return "Fire" end
		end

		if Source == "Blast" then return end -- Overpressure alone doesn't light fuel

		return Source
	end

	--- Sets an entity on fire. The entity decides if it has anything to burn through ENT:ACF_OnIgnite.
	--- @param Entity entity The entity to ignite.
	--- @param Source string What lit it, see Fire.GetIgnitionSource, or "HotSurface"/"Heat".
	--- @return boolean # True if the entity is burning afterwards.
	function Fire.Ignite(Entity, Source)
		if Fire.Burning[Entity] then return true end
		if not ACF.FireEnabled then return false end
		if not Entity.ACF_FireTick then return false end
		if not HookRun("ACF_PreIgnite", Entity, Source) then return false end
		if Entity.ACF_OnIgnite and Entity:ACF_OnIgnite(Source) == false then return false end

		Fire.Burning[Entity] = true

		Entity.ACF_IgnitionSource = Source
		Entity:SetNW2Bool("ACF_Burning", true)

		if Entity.UpdateOverlay then Entity:UpdateOverlay() end

		return true
	end

	--- Puts out a burning entity.
	--- @param Entity entity The entity to extinguish.
	function Fire.Extinguish(Entity)
		if not Fire.Burning[Entity] then return end

		Fire.Burning[Entity] = nil

		if not IsValid(Entity) then return end

		Entity.ACF_IgnitionSource = nil
		Entity:SetNW2Bool("ACF_Burning", false)

		if Entity.ACF_OnExtinguish then Entity:ACF_OnExtinguish() end
		if Entity.UpdateOverlay then Entity:UpdateOverlay() end
	end

	--- @param Entity entity
	--- @return boolean # Whether the entity is currently burning.
	function Fire.IsBurning(Entity)
		return Fire.Burning[Entity] == true
	end

	--- Adds the entity's fire state, and what lit it, to its overlay.
	function Fire.AddOverlay(Entity, State)
		if not Fire.Burning[Entity] then return end

		State:AddWarning(("Burning (%s)"):format(SourceNames[Entity.ACF_IgnitionSource] or "unknown"))
	end
end

do -- MARK: Fire tick
	local Exposure = {} -- Exposure[Entity] = W/m² it receives this tick, from every fire around it
	local Ticking  = {} -- This tick's fires; a fire can light others, which mustn't join Burning mid-traversal

	-- Burns one fire's fuel and sends its heat out, or puts it out once there's nothing left
	local function TickFire(Entity, DeltaTime, TickCount)
		if not Fire.Burning[Entity] then return end -- Put out earlier this tick
		if not IsValid(Entity) then
			Fire.Burning[Entity] = nil

			return
		end

		local HeatRelease = ACF.FireEnabled and Entity:ACF_FireTick(DeltaTime) -- Watts, nil once burnt out

		if not HeatRelease then return Fire.Extinguish(Entity) end

		local Contraption = Entity:CFW_GetContraption()

		if Contraption then Contraption.InCombat = TickCount end -- Crew don't recover while their vehicle burns
		if HeatRelease > 0 then Fire.SpreadHeat(Entity, HeatRelease, Exposure) end
	end

	timer.Create("ACF_FireTick", ACF.FireTickRate, 0, function()
		local DeltaTime = ACF.FireTickRate
		local TickCount = engine.TickCount()

		local Count = 0

		for Entity in pairs(Fire.Burning) do
			Count = Count + 1

			Ticking[Count] = Entity
		end

		for I = 1, Count do
			local Entity = Ticking[I]

			Ticking[I] = nil

			-- An error would remove the timer and stop every fire, so only the broken one goes out.
			-- It goes out through Extinguish so its own cleanup runs (a crate's cookoff detonates instead of sticking).
			if not xpcall(TickFire, ErrorNoHaltWithStack, Entity, DeltaTime, TickCount) then
				xpcall(Fire.Extinguish, ErrorNoHaltWithStack, Entity)
			end
		end

		Fire.ApplyHeat(Exposure, DeltaTime)
		Fire.UpdateWalls(DeltaTime)

		table.Empty(Exposure)
	end)
end

local ACF     = ACF
local Damage  = ACF.Damage
local Objects = Damage.Objects
local Fire    = Damage.Fire
local Clock   = ACF.Utilities.Clock
local HookRun = hook.Run

local GRAVITY          = 9.81 -- m/s²
local LEAK_COEF        = 0.6 -- Discharge coefficient of a sharp-edged hole
local POOL_MIN_MASS    = 0.5 -- kg, a spill thinner than this can't sustain a fire and is gone
local SEAL_MAX_CALIBER = 20 -- mm, MIL-T-5578 cells seal .50 cal and 20 mm; bigger holes tear the liner
local SEAL_MAX_AREA    = (SEAL_MAX_CALIBER * 0.05) ^ 2 * math.pi / ACF.InchToCmSq -- in², the hole that caliber leaves
local SEAL_TIME        = 5 -- Seconds for the liner to swell shut
local BOIL_OFF         = 0.1 -- Fraction of the fuel a tank vents once heat makes it boil

ENT.Spilled = 0 -- kg of fuel spilled around the tank, which is what actually burns

-- Rolls a per-second chance over a tick
local function RollPerSecond(Chance, DeltaTime)
	return math.random() < 1 - (1 - Chance) ^ DeltaTime
end

do -- MARK: Damage and leaks
	local function UpdateLeakState(Entity)
		local Leaking = Entity.Leaking > 0

		WireLib.TriggerOutput(Entity, "Leaking", Leaking and 1 or 0)
		ACF.Hints.Set(Entity, "fueltank_leaking", Leaking)
	end

	--- @return number # Open area of the tank in in²: holes through its shell, plus a rupture while it's destroyed.
	function ENT:GetLeakArea()
		local MeshData = self.ACF_Volumetric_Mesh
		local Area     = 0

		if MeshData then
			for _, Convex in ipairs(MeshData.Convexes) do
				Area = Area + (Convex.HoleArea or 0)
			end
		end

		if ACF.IsDestroyed(self) then
			local Size = self:OBBMaxs() - self:OBBMins()

			Area = Area + 2 * (Size.x * Size.y + Size.y * Size.z + Size.z * Size.x) * ACF.FuelRuptureAreaRatio
		end

		return Area
	end

	--- @return number # Liters per second a liquid would pour out of the tank's holes, by orifice flow under its own weight.
	function ENT:GetOrificeFlow()
		if self.Amount <= 0 then return 0 end

		local Area = self:GetLeakArea()

		if Area <= 0 then return 0 end

		local Size   = self:OBBMaxs() - self:OBBMins()
		local Up     = self:WorldToLocal(self:GetPos() + vector_up) - self:WorldToLocal(self:GetPos())
		local Height = (math.abs(Up.x) * Size.x + math.abs(Up.y) * Size.y + math.abs(Up.z) * Size.z) * ACF.InchToMeter
		local Head   = self.Amount / self.Capacity * Height * 0.5 -- Holes sit halfway down the fuel on average
		local Flow   = LEAK_COEF * ACF.FuelLeakMult * Area * ACF.InchToCmSq * 1e-4 * math.sqrt(2 * GRAVITY * Head) -- m³/s

		return Flow * 1000
	end

	--- Moves fuel out of the tank into the spill around it.
	--- @param Amount number Liters of fuel to spill.
	function ENT:Spill(Amount)
		Amount = math.min(Amount, self.Amount)

		if Amount <= 0 then return end

		self:Consume(Amount)

		self.Spilled = self.Spilled + Amount * self.UnitMass

		self:NextThink(Clock.CurTime) -- Start draining it
	end

	-- The convexes a hit reaches, with the hole area each had before it
	local function GetHitConvexes(Entity, DmgInfo)
		local MeshData   = Entity.ACF_Volumetric_Mesh
		local ConvexHits = MeshData and DmgInfo:GetConvexHits()
		local Before     = {}

		if not ConvexHits then return Before end

		for _, Hit in ipairs(ConvexHits) do
			local Convex = MeshData.Convexes[Hit.ConvexID]

			if Convex then Before[Hit] = { Convex = Convex, Area = Convex.HoleArea or 0 } end
		end

		return Before
	end

	-- The thin shell around the fuel opens wherever a round goes in, not just where one comes out.
	-- A liner only closes what the hit opened, so a capped convex's earlier tear stays open.
	local function PunchHoles(Entity, HitConvexes)
		for Hit, Entry in pairs(HitConvexes) do
			local Convex = Entry.Convex

			if Hit.HitArea and (Hit.Frac or 1) > 0 then Damage.AddConvexHole(Convex, Hit.HitArea) end

			local Opened = (Convex.HoleArea or 0) - Entry.Area

			if Opened > 0 and Entity.SelfSealing and (Hit.HitArea or 0) / (Hit.Holes or 1) <= SEAL_MAX_AREA then
				local Seals = Entity.Seals or {}

				Seals[#Seals + 1] = { Convex = Convex, Area = Opened, Time = Clock.CurTime + SEAL_TIME }

				Entity.Seals = Seals
			end
		end
	end

	local function UpdateSeals(Entity, Now)
		local Seals = Entity.Seals

		if not Seals then return end

		for I = #Seals, 1, -1 do
			local Seal = Seals[I]

			if Now >= Seal.Time then
				Seal.Convex.HoleArea = math.max((Seal.Convex.HoleArea or 0) - Seal.Area, 0)

				table.remove(Seals, I)
			end
		end

		if not Seals[1] then Entity.Seals = nil end
	end

	-- Running engines' hot surfaces can light a spill, even diesel
	local function IsNearRunningEngine(Entity)
		local Contraption = Entity:CFW_GetContraption()
		local Engines     = Contraption and Contraption.entsbyclass.acf_engine

		if not Engines then return false end

		local Center   = Entity:WorldSpaceCenter()
		local RangeSqr = ACF.FuelHotSurfaceRange * ACF.FuelHotSurfaceRange

		for Engine in pairs(Engines) do
			if IsValid(Engine) and Engine.Active then
				local EnginePoint = Engine:NearestPoint(Center)

				if Entity:NearestPoint(EnginePoint):DistToSqr(EnginePoint) <= RangeSqr then return true end
			end
		end

		return false
	end

	-- Spilled fuel runs off through the hull whether or not it's alight, and hot engines can light it
	local function UpdateSpill(Entity, FuelType, Feeding, DeltaTime)
		if Entity.Spilled <= 0 then return end

		local Chance = FuelType and FuelType:GetIgnitionChance("HotSurface", 0) or 0

		if Chance > 0 and not Fire.IsBurning(Entity) and IsNearRunningEngine(Entity) and RollPerSecond(Chance, DeltaTime) then
			Fire.Ignite(Entity, "HotSurface")
		end

		Entity.Spilled = Entity.Spilled * 0.5 ^ (DeltaTime / ACF.FuelPoolHalfLife)

		if Entity.Spilled < POOL_MIN_MASS and not Feeding then Entity.Spilled = 0 end -- Too thin to keep burning
	end

	--- Moves leaking fuel into the spill, closes sealed holes and drains the spill away
	function ENT:Think()
		local Now       = Clock.CurTime
		local DeltaTime = math.min(Now - (self.LastThink or Now), 0.5)
		local FuelType  = self:ACF_GetUserVar("FuelType")
		local Leaking   = FuelType and FuelType:GetLeakRate(self) or 0 -- L/s
		local WasLeaking = self.Leaking > 0

		UpdateSeals(self, Now)

		if Leaking > 0 then FuelType:Release(self, Leaking * DeltaTime) end

		self.Leaking = Leaking

		if (Leaking > 0) ~= WasLeaking then UpdateLeakState(self) end

		UpdateSpill(self, FuelType, Leaking > 0, DeltaTime)

		self.LastThink = Now

		if Leaking > 0 or self.Seals or self.Spilled > 0 then
			self:NextThink(Now + 0.25)

			return true
		end

		return false
	end

	--- Handles damage to fuel tanks
	--- Damage spills fuel, which can then be lit depending on what hit the tank and the fuel type
	function ENT:ACF_OnDamage(DmgResult, DmgInfo)
		local OldHealth   = self.ACF.Health
		local HitConvexes = GetHitConvexes(self, DmgInfo) -- Before the hit's exit holes go in
		local HitRes      = Damage.doPropDamage(self, DmgResult, DmgInfo)
		local FuelType    = self:ACF_GetUserVar("FuelType")

		if not FuelType then return HitRes end

		local Attacker = DmgInfo:GetAttacker()

		if IsValid(Attacker) and Attacker:IsPlayer() then self.Attacker = Attacker end

		self.Inflictor = DmgInfo:GetInflictor()

		PunchHoles(self, HitConvexes)

		self.Leaking = FuelType:GetLeakRate(self)

		UpdateLeakState(self)

		self:NextThink(Clock.CurTime)

		local Source = Fire.GetIgnitionSource(self, DmgInfo)

		if not Source or Fire.IsBurning(self) then return HitRes end

		local Destroyed = ACF.IsDestroyed(self)
		local Damaged   = Destroyed and 1 or (OldHealth - self.ACF.Health) / self.ACF.MaxHealth

		if math.random() < FuelType:GetIgnitionChance(Source, Damaged) and Fire.Ignite(self, Source) and Destroyed then
			self:Fireball(FuelType:GetFlashAmount(self))
		end

		return HitRes
	end
end

do -- MARK: Fire
	--- Flashes over fuel a rupture sprays out of the tank, creating an explosion
	--- @param Sprayed number Liters taken from the tank, see FuelType:GetFlashAmount.
	function ENT:Fireball(Sprayed)
		Sprayed = math.min(Sprayed, self.Amount)

		if Sprayed <= 0 then return end
		if not HookRun("ACF_PreExplodeFuel", self) then return end

		self:Consume(Sprayed)

		local Position  = self:WorldSpaceCenter()
		local Explosive = Sprayed * self.UnitMass * ACF.FuelFireballYield
		local DmgInfo   = Objects.DamageInfo(self.Attacker or self, self.Inflictor)

		Damage.createExplosion(Position, Explosive, Explosive * 0.5, { self }, DmgInfo)
		Damage.explosionEffect(Position, nil, Explosive)
	end

	--- Ruptures the tank, as when what it's mounted on is destroyed, and lets flames light what comes out
	function ENT:Detonate()
		local FuelType = self:ACF_GetUserVar("FuelType")

		if not FuelType then return end

		local Sprayed = FuelType:GetFlashAmount(self) -- Held back so the spill doesn't take it

		FuelType:Release(self, self.Amount - Sprayed)

		if math.random() < FuelType:GetIgnitionChance("Fire", 1) and Fire.Ignite(self, "Fire") then
			self:Fireball(Sprayed)
		end

		FuelType:Release(self, self.Amount) -- Whatever didn't flash over
	end

	function ENT:ACF_OnIgnite()
		local FuelType = self:ACF_GetUserVar("FuelType")

		return FuelType ~= nil and FuelType:CanBurn(self)
	end

	--- @return number|nil # Heat released in watts, nil once there's nothing left to burn
	function ENT:ACF_FireTick(DeltaTime)
		local FuelType = self:ACF_GetUserVar("FuelType")

		if not FuelType then return end

		return FuelType:Burn(self, DeltaTime)
	end

	--- Flames reaching spilled fuel light it, and enough heat makes an intact tank vent and catch fire
	function ENT:ACF_OnHeat(Flux, DeltaTime)
		if Fire.IsBurning(self) then return end

		local FuelType = self:ACF_GetUserVar("FuelType")

		if not FuelType then return end

		if Flux >= ACF.FireContactFlux and FuelType:IsExposed(self) then
			if RollPerSecond(FuelType:GetIgnitionChance("Fire", 1), DeltaTime) then Fire.Ignite(self, "Fire") end

			return
		end

		if Fire.AddHeatDose(self, Flux, DeltaTime) < ACF.FuelTankHeatDose then return end

		FuelType:Release(self, self.Amount * BOIL_OFF)

		Fire.Ignite(self, "Heat")
	end
end

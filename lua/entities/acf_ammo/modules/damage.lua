local ACF     = ACF
local Damage  = ACF.Damage
local Objects = Damage.Objects
local Fire    = Damage.Fire
local Clock   = ACF.Utilities.Clock

local PROPELLANT_HEAT = 4e6 -- J/kg, heat of explosion of gun propellant
local MIN_VOLUME      = 0.05 -- m³, no crate's gas has less room than this
local BURST_GROWTH    = math.log(100) -- A contained burn grows from 1% of the propellant to all of it

local SURVEYS_PER_TICK = 2 -- Containment surveys are hundreds of traces, so crates lit together take turns

-- Fire turned off, or vetoed, makes a cookoff just a detonation
local function StartCookoff(Entity, Source)
	if not Fire.Ignite(Entity, Source) then Entity:Detonate() end
end

-- Leaves the crate empty and destroyed once its contents have gone off
local function Spend(Entity)
	Entity.ACF.Health = 0

	Entity:SetAmount(0)
	Entity:Disable()
	Entity:UpdateOverlay(true)
end

do -- MARK: Damage and heat
	function ENT:ACF_OnDamage(DmgResult, DmgInfo)
		local HitRes = Damage.doPropDamage(self, DmgResult, DmgInfo) -- Calling the standard damage prop function

		if self.Exploding or self.Cookoff or self.Amount <= 0 then return HitRes end

		local Source    = Fire.GetIgnitionSource(self, DmgInfo) or "Hit"
		local Destroyed = ACF.IsDestroyed(self)

		-- Destroyed outright guarantees a cookoff, otherwise roll for it
		if not Destroyed and (HitRes.Damage / self.BulletData.RoundVolume) ^ 0.1 * self.Capacity / self.Amount <= math.random() then
			return HitRes
		end

		self.Attacker  = DmgInfo.Attacker
		self.Inflictor = DmgInfo.Inflictor

		StartCookoff(self, Source)

		return HitRes
	end

	function ENT:ACF_OnHeat(Flux, DeltaTime)
		if self.Exploding or self.Cookoff or self.Amount <= 0 then return end

		if Fire.AddHeatDose(self, Flux, DeltaTime) >= ACF.AmmoHeatDose then
			StartCookoff(self, "Heat")
		end
	end
end

do -- MARK: Cookoff
	--- Works out how a cookoff would play out, without starting one.
	--- Gas that can't get out of a sealed space at the pressure the structure holds bursts it, and more
	--- opening is needed the more propellant there is, since confined propellant burns faster with pressure.
	--- @return table # Burst, the pressure it would reach sealed, the opening it has and the opening it would need.
	function ENT:GetCookoffPlan()
		local Vent, Volume = Fire.SurveyEnclosure(self)
		local Propellant   = self.Amount * (self.BulletData.PropMass or 0)
		local Pressure     = Propellant * ACF.PropImpetus * 1000 / math.max(Volume, MIN_VOLUME) -- Pa, closed-vessel pressure
		local Required     = Propellant * ACF.AmmoVentAreaPerKg

		return {
			Burst    = Pressure >= ACF.AmmoBurstPressure and Vent < Required,
			Pressure = Pressure,
			Volume   = Volume,
			VentArea = Vent,
			Required = Required,
		}
	end

	--- Starts the cookoff; how it plays out is worked out on the fire tick, outside whatever lit it
	function ENT:ACF_OnIgnite()
		if self.Exploding or self.Amount <= 0 then return false end

		if not hook.Run("ACF_PreBurnAmmo", self) then
			self:Detonate()

			return false
		end

		self.Cookoff = { Planned = false }

		return true
	end

	-- A crate put out mid-cookoff (fire turned off) can't hold its burning propellant
	function ENT:ACF_OnExtinguish()
		if not self.Cookoff then return end

		self.Cookoff = nil

		self:Detonate()
	end

	local SurveyTick, Surveys = 0, 0

	-- @return boolean # False if this tick's surveys are used up and the crate has to wait for the next.
	local function PlanCookoff(Entity)
		local Tick = engine.TickCount()

		if Tick ~= SurveyTick then SurveyTick, Surveys = Tick, 0 end
		if Surveys >= SURVEYS_PER_TICK then return false end

		Surveys = Surveys + 1

		local Plan = Entity:GetCookoffPlan()

		Plan.Planned = true
		Plan.Start   = Clock.CurTime
		Plan.Rate    = Entity.Amount / ACF.AmmoBurnTime -- Rounds per second
		Plan.Partial = 0
		Plan.Burnt   = 0

		Entity.Cookoff = Plan

		Entity:UpdateOverlay()

		return true
	end

	-- The burnt rounds' HE filler goes off once their propellant is gone
	local function FinishCookoff(Entity)
		local BulletData = Entity.BulletData
		local Filler     = (BulletData.FillerMass or 0) * Entity.Cookoff.Burnt

		Entity.Cookoff   = nil
		Entity.Exploding = true

		if Filler > 0 and hook.Run("ACF_PreExplodeAmmo", Entity) then
			local Position = Entity:WorldSpaceCenter()
			local DmgInfo  = Objects.DamageInfo(Entity.Attacker or Entity, Entity.Inflictor)

			Damage.createExplosion(Position, Filler, BulletData.ProjMass or Filler * 0.5, { Entity }, DmgInfo)
			Damage.explosionEffect(Position, nil, Filler)
		end

		Spend(Entity)
	end

	-- Sealed in, the burn speeds up with the pressure it builds until the structure gives way
	local function BuildPressure(Entity, Cookoff, PropMass)
		local Elapsed = Clock.CurTime - Cookoff.Start

		if Elapsed >= ACF.AmmoBurstDelay then
			Entity.Cookoff = nil

			Entity:Detonate(false, true)

			return
		end

		local Rate = BURST_GROWTH / ACF.AmmoBurstDelay

		return Entity.Amount * PropMass * PROPELLANT_HEAT * 0.01 * Rate * math.exp(Elapsed * Rate)
	end

	-- Venting, the rounds burn through one after another
	local function BurnPropellant(Entity, Cookoff, PropMass, DeltaTime)
		local Rounds = math.min(Entity.Amount - Cookoff.Partial, Cookoff.Rate * DeltaTime)

		Cookoff.Partial = Cookoff.Partial + Rounds

		local Whole = math.floor(Cookoff.Partial)

		if Whole > 0 then
			Cookoff.Partial = Cookoff.Partial - Whole
			Cookoff.Burnt   = Cookoff.Burnt + Whole

			Entity:Consume(Whole)
		end

		if Entity.Amount - Cookoff.Partial <= 0 then return FinishCookoff(Entity) end

		return Rounds * PropMass * PROPELLANT_HEAT / DeltaTime
	end

	--- @return number|nil # Heat released in watts, nil once the cookoff is over
	function ENT:ACF_FireTick(DeltaTime)
		local Cookoff = self.Cookoff

		if not Cookoff then return end
		if not Cookoff.Planned and not PlanCookoff(self) then return 0 end

		Cookoff = self.Cookoff

		local PropMass = math.max(self.BulletData.PropMass or 0, 1e-6)

		if Cookoff.Burst then return BuildPressure(self, Cookoff, PropMass) end

		return BurnPropellant(self, Cookoff, PropMass, DeltaTime)
	end

	--- Sets off the crate's contents
	--- @param VisualOnly boolean Only show the explosion.
	--- @param Full boolean Use everything in the crate, as a contained cookoff bursting does, rather than the damped legacy amount.
	function ENT:Detonate(VisualOnly, Full)
		if self.Exploding then return end

		local CanExplode = hook.Run("ACF_PreExplodeAmmo", self)

		if not CanExplode then return end

		self.Exploding = true

		local Position   = self:LocalToWorld(self:OBBCenter() + VectorRand() * self:GetSize() * 0.5) -- Random position within the crate
		local BulletData = self.BulletData
		local Filler     = BulletData.FillerMass or 0
		local Propellant = BulletData.PropMass or 0
		local AmmoPower  = Full and self.Amount or self.Amount ^ 0.7 -- Arbitrary exponent to reduce ammo-based explosive power
		local Explosive  = (Filler + Propellant * (ACF.PropImpetus / ACF.HEPower)) * AmmoPower
		local FragMass   = BulletData.ProjMass or Explosive * 0.5
		local DmgInfo    = Objects.DamageInfo(self.Attacker or self, self.Inflictor)

		ACF.KillChildProps(self, Position, Explosive)

		if not VisualOnly then
			Damage.createExplosion(Position, Explosive, FragMass, { self }, DmgInfo, Full and self:CFW_GetContraption() or nil)
		end

		Damage.explosionEffect(Position, nil, Explosive)

		Spend(self)
	end
end

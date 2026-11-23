jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local ACF = ACF
local Mobility    = ACF.Mobility
local MobilityObj = Mobility.Objects
local Drivetrain  = Mobility.Drivetrain
local MaxDistance = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance

local ENTITY 			= FindMetaTable("Entity")

local IsEntityValid		= ACF.Optimizations.IsEntityValid

--===============================================================================================--
-- Engine class setup
--===============================================================================================--
do -- MARK: Linking
	local function TooFar(Engine, Target)
		if Engine:GetPos():DistToSqr(Target:GetPos()) <= MaxDistance then return false end

		Mobility.LinkFailure.Distance(Engine, Target)

		return true
	end

	-- Plane is where the shaft meets the target, nil for a wheel's hub
	local function IsBent(Engine, Target, Plane)
		local Excessive, Angle = ACF.IsDriveshaftAngleExcessive(Target, Plane, Engine, Engine.Out)

		if not Excessive then return false end

		Mobility.LinkFailure.Angle(Engine, Engine.Out, Target, Plane, Angle)

		return true, "Cannot link due to excessive driveshaft angle! (" .. math.Round(Angle) .. " deg)"
	end

	local function NewLink(Engine, Target, TargetPos)
		local Link = MobilityObj.Link(Engine, Target)

		Link:SetOrigin(Engine.Out.Pos)
		Link:SetTargetPos(TargetPos)

		Link.RopeLen = Engine:LocalToWorld(Engine.Out.Pos):Distance(Target:LocalToWorld(TargetPos))

		return Link
	end

	local function Refresh(Engine, Target)
		Drivetrain.Invalidate(Engine, Target)

		Engine:UpdateLinkHints()
		Engine:UpdateOverlay()
		Engine:InvalidateClientInfo()

		if Target.IsACFEntity then
			Target:UpdateLinkHints()
			Target:UpdateOverlay()
			Target:InvalidateClientInfo()
		end
	end

	-- Always into its input, whichever was picked first
	local function LinkGearbox(Engine, Gearbox)
		local Gearboxes = Engine:ACF_GetUserVar("Gearboxes")

		if Gearboxes[Gearbox] then return false, "This engine is already linked to this gearbox." end
		if TooFar(Engine, Gearbox) then return false, "This gearbox is too far away from this engine!" end

		local Bent, Message = IsBent(Engine, Gearbox, Gearbox.In)

		if Bent then return false, Message end

		Gearboxes[Gearbox]      = NewLink(Engine, Gearbox, Gearbox.In.Pos)
		Gearbox.Engines[Engine] = true

		Mobility.BrokenLinks.Clear(Engine, Gearbox)
		Refresh(Engine, Gearbox)

		return true, "Engine linked successfully!"
	end

	-- Two cranks joined end to end turn as one shaft, without a gearbox between them
	local function LinkCrank(Engine, Other)
		local Cranks = Engine:ACF_GetUserVar("Cranks")

		if Cranks[Other] then return false, "These engines are already linked to each other." end
		if TooFar(Engine, Other) then return false, "These engines are too far away from each other!" end

		local Bent, Message = IsBent(Engine, Other, Other.Out)

		if Bent then return false, Message end

		local Link = NewLink(Engine, Other, Other.Out.Pos)

		Cranks[Other] = Link
		Other:ACF_GetUserVar("Cranks")[Engine] = Link

		Mobility.BrokenLinks.Clear(Engine, Other)
		Mobility.BrokenLinks.Clear(Other, Engine) -- Either engine's check may have broken it before
		Refresh(Engine, Other)

		return true, "Engines linked, their cranks turn as one."
	end

	-- A wheel on its crank turns with it, as a hub motor's does
	local function LinkWheel(Engine, Wheel)
		local Wheels = Engine:ACF_GetUserVar("Wheels")

		if Wheels[Wheel] then return false, "This wheel is already linked to this engine!" end
		if TooFar(Engine, Wheel) then return false, "This wheel is too far away from this engine!" end

		local Bent, Message = IsBent(Engine, Wheel)

		if Bent then return false, Message end

		local Link = NewLink(Engine, Wheel, Vector())

		Link.Side = 0

		Wheels[Wheel] = Link

		if not Wheel.ACF_Engines then Wheel.ACF_Engines = {} end
		Wheel.ACF_Engines[Engine] = Link

		Wheel:CallOnRemove("ACF_EngineUnlink" .. Engine:EntIndex(), function()
			if IsEntityValid(Engine) then Engine:Unlink(Wheel) end
		end)

		Mobility.BrokenLinks.Clear(Engine, Wheel)
		ACF.UpdateWheelAxes(Wheel)
		Refresh(Engine, Wheel)

		return true, "Wheel linked successfully!"
	end

	ACF.RegisterClassLink("acf_engine", "acf_gearbox", LinkGearbox)

	ACF.RegisterClassLink("acf_engine", "acf_engine", LinkCrank)
	ACF.RegisterClassLink("acf_engine", "prop_physics", LinkWheel)
	ACF.RegisterClassLink("acf_engine", "tire", LinkWheel)

	ACF.RegisterClassUnlink("acf_engine", "acf_gearbox", function(Engine, Gearbox)
		local Gearboxes = Engine:ACF_GetUserVar("Gearboxes")
		local Link      = Gearboxes[Gearbox]

		if not Link then return false, "This engine is not linked to this gearbox." end

		Gearboxes[Gearbox]      = nil
		Gearbox.Engines[Engine] = nil

		Refresh(Engine, Gearbox)

		return true, "Engine unlinked successfully!"
	end)

	ACF.RegisterClassUnlink("acf_engine", "acf_engine", function(Engine, Other)
		local Cranks = Engine:ACF_GetUserVar("Cranks")
		local Link   = Cranks[Other]

		if not Link then return false, "These engines are not linked to each other." end

		Cranks[Other] = nil
		Other:ACF_GetUserVar("Cranks")[Engine] = nil

		Refresh(Engine, Other)

		return true, "Engines unlinked successfully!"
	end)

	local function UnlinkWheel(Engine, Wheel)
		local Wheels = Engine:ACF_GetUserVar("Wheels")
		local Link   = Wheels[Wheel]

		if Wheel.ACF_Engines then Wheel.ACF_Engines[Engine] = nil end
		if not Link then return false, "This wheel is not linked to this engine!" end

		Wheels[Wheel] = nil

		Wheel:RemoveCallOnRemove("ACF_EngineUnlink" .. Engine:EntIndex())

		ACF.UpdateWheelAxes(Wheel)
		Refresh(Engine, Wheel)

		return true, "Wheel unlinked successfully!"
	end

	ACF.RegisterClassUnlink("acf_engine", "prop_physics", UnlinkWheel)
	ACF.RegisterClassUnlink("acf_engine", "tire", UnlinkWheel)
end

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--

local Damage       = ACF.Damage
local Utilities    = ACF.Utilities
local Clock        = Utilities.Clock
local Sounds       = Utilities.Sounds
local Contraption  = ACF.Contraption
local Fuel         = Mobility.Fuel
local BrokenLinks  = Mobility.BrokenLinks
local Notify       = Utilities.Notify
local Clamp        = math.Clamp
local Round        = math.Round
local abs          = math.abs
local max          = math.max
local min          = math.min
local TimerCreate  = timer.Create
local TimerRemove  = timer.Remove
local TickInterval = engine.TickInterval

local MAX_BRAKE    = 1e6 -- N·m on each wheel, as on a gearbox
-- s it takes to fall silent, as a stalled or switched off engine runs down rather than cutting out
local SOUND_FADE   = 0.4
-- Volume change worth sending on its own, as at a steady speed only the load changes it
local VOLUME_DELTA = 0.02

-- Only called when the cached tank is unusable, so a linear scan over the (small) sibling set is fine
local function FindFuelTank(EngineTbl)
	local MinPriority = ACF.FuelPriorityMin
	local Best, BestPriority

	for Tank in pairs(EngineTbl.FuelTanks) do
		local TankTbl  = ENTITY.GetTable(Tank)
		local Priority = TankTbl.FuelPriority

		if (not Best or Priority < BestPriority) and TankTbl.CanConsume(Tank, TankTbl) then
			Best, BestPriority = Tank, Priority

			if Priority <= MinPriority then break end
		end
	end

	return Best
end

local function BreakLink(Engine, Target, Reason, TargetPos)
	Engine:Unlink(Target)
	BrokenLinks.Add(Engine, Target, Reason, Engine.Out.Pos, TargetPos)
	Notify.EntityWarning(Engine, "Engine connection broken", Reason .. "!",
		ACF.Diagnostics.Get("link_broken").Ponder)
end

-- Plane is where the shaft meets the target, nil for a wheel's hub; TargetPos is local to the target
local function CheckLink(Engine, Target, Link, Plane, TargetPos)
	local OutPos = Engine:LocalToWorld(Engine.Out.Pos)
	local InPos  = Target:LocalToWorld(TargetPos)

	if OutPos:Distance(InPos) > Link.RopeLen * 1.5 then
		return BreakLink(Engine, Target, "Excessive distance", TargetPos)
	end

	local Excessive, Angle = ACF.IsDriveshaftAngleExcessive(Target, Plane, Engine, Engine.Out)

	if Excessive then
		local Reason = "Excessive driveshaft angle (" .. Round(Angle) .. " of " .. ACF.MaxDriveshaftAngle .. " deg)"

		BreakLink(Engine, Target, Reason, TargetPos)
	end
end

local function CheckLinks(Engine)
	local Live = Engine.ACF_LiveData

	for Ent, Link in pairs(Live.Gearboxes) do CheckLink(Engine, Ent, Link, Ent.In, Link:GetTargetPos()) end
	-- Both engines share the link, which points at one crank only
	for Ent, Link in pairs(Live.Cranks) do CheckLink(Engine, Ent, Link, Ent.Out, Ent.Out.Pos) end
	for Ent, Link in pairs(Live.Wheels) do CheckLink(Engine, Ent, Link, nil, Link:GetTargetPos()) end
end


local function SetActive(Entity, Value, EntTbl)
	EntTbl = EntTbl or Entity:GetTable()

	local ActBool = tobool(Value)

	if EntTbl.Active == ActBool then return end -- Already in the desired state
	if ActBool and EntTbl.Disabled then return end -- Can't activate a disabled engine

	if ActBool then -- Was off, turn on
		EntTbl.Active       = true
		EntTbl.Cranking     = true -- Its drivetrain turns it over until it fires
		EntTbl.StarterClock = 0

		Entity:CalcMassRatio()
		Mobility.Driver.Update(Entity, next(EntTbl.ACF_LiveData.Wheels))

		Entity:NextThink(Clock.CurTime + TickInterval())

		TimerCreate("ACF Engine Clock " .. Entity:EntIndex(), 3, 0, function()
			if not IsEntityValid(Entity) then return end

			CheckLinks(Entity)
			Mobility.Driver.Update(Entity, next(Entity.ACF_LiveData.Wheels))

			Contraption.UpdateMassRatio(Entity)
		end)
	else -- Was on, turn off
		EntTbl.Active   = false
		EntTbl.Firing   = false
		EntTbl.Cranking = false
		EntTbl.Torque   = 0

		TimerRemove("ACF Engine Clock " .. Entity:EntIndex())
	end

	Entity:UpdateOverlay(true) -- Past the overlay's cooldown, which would keep showing the state it just left
	Entity:UpdateOutputs(EntTbl)
end

--===============================================================================================--

do -- Spawn and Update functions
	local Classes = ACF.Classes

	-- kg·m² per unit of FlywheelMass, revs as fast as the old per-tick flywheel did at 66.67 tick
	local FLYWHEEL_INERTIA = 0.45 * math.pi

	--- @param Engine table The stats of a sized engine instance
	local function UpdateEngine(Entity, Engine)
		local Layout = Classes.GetTypeByName(Engine.Layout)
		local Family = Classes.GetBaseClass(Layout)
		local Type   = Engine.EngineType
		local Mass   = Engine.Mass

		Entity.ACF = Entity.ACF or {}
		Entity.ACF.Model = Engine.Model

		Entity:SetScaledModel(Engine.Model)
		Entity:SetScale(Engine.Scale)

		Entity.Name             = Engine.Name
		Entity.ShortName        = Engine.Name
		Entity.EntType          = Family.Name
		Entity.ClassData        = Family
		Entity.Layout           = Engine.Layout
		Entity.Displacement     = Engine.Displacement
		Entity.Power            = Engine.Power
		Entity.Geared           = Engine.Geared
		Entity.DefaultSound     = Engine.Sound
		Entity.SoundPitch       = Engine.Pitch or 1
		Entity.SoundVolume      = Engine.SoundVolume or 1
		Entity.TorqueCurve      = Engine.TorqueCurve
		Entity.PeakTorque       = Engine.Torque
		Entity.PeakPower		= Engine.PeakPower
		Entity.PeakPowerRPM		= Engine.PeakPowerRPM
		Entity.EngineVolume     = Engine.Volume
		Entity.PeakTorqueHeld   = Engine.Torque
		Entity.IdleRPM          = Engine.RPM.Idle
		Entity.PeakMinRPM       = Engine.RPM.PeakMin
		Entity.PeakMaxRPM       = Engine.RPM.PeakMax
		Entity.LimitRPM         = Engine.RPM.Limit
		Entity.GovernorDroop    = Engine.EngineType.GovernorDroop
		Entity.PeakTqRPM        = Engine.PeakTqRPM
		Entity.RevLimited       = false
		Entity.FlywheelMass     = Engine.FlywheelMass
		Entity.Inertia          = Engine.FlywheelMass * FLYWHEEL_INERTIA
		Entity.IsElectric       = Engine.IsElectric
		Entity.IsTrans          = Engine.IsTrans -- driveshaft outputs to the side
		Entity.FuelTypes        = Engine.Fuel
		Entity.FuelType         = next(Engine.Fuel)
		Entity.EngineType       = Classes.FullyQualifiedNameToUnqualifiedName(Engine.Type)
		Entity.Efficiency       = Type.Efficiency
		Entity.TorqueScale      = Type.TorqueScale
		Entity.HealthMult       = Type.HealthMult
		Entity.TypeData         = Type
		Entity.DrivetrainAdapter = Type.DrivetrainAdapter
		Entity.StartingLabel    = Type.StartingLabel
		Entity.MinThrottle      = Type.MinThrottle
		-- A motor swapped for an engine can't keep running backwards
		Entity.Throttle         = math.max(Entity.Throttle, Type.MinThrottle * 0.01)
		Entity.LossConstant, Entity.LossLinear, Entity.LossQuadratic = Type:GetLosses(Engine)
		Entity.HitBoxes         = ACF.GetHitboxes(Engine.Model, Engine.Scale)

		-- A model's own attachments don't scale with it
		local Attachment = Entity:GetAttachment(Entity:LookupAttachment("driveshaft"))
		local Driveshaft  = Entity:WorldToLocal(Attachment.Pos) * Engine.Scale

		Entity.Out              = ACF.LocalPlane(Driveshaft,
			Engine.IsTrans and Vector(0, 1, 0) or Vector(1, 0, 0))

		if Engine.IsTrans then
			Entity.Out = ACF.LocalPlane(vector_origin, Vector(0, 1, 0))
		end
		Entity.SoundPath        = Entity.SoundPath or Engine.Sound

		Entity:ACF_SetEntityName("ACF " .. Entity.Name)

		--calculate base fuel usage
		if Type.CalculateFuelUsage then
			Entity.FuelUse = Type.CalculateFuelUsage(Entity)
		else
			Entity.FuelUse = ACF.FuelRate * Entity.Efficiency * 3e-8
		end

		Entity.FuelUse = Entity.FuelUse * Drivetrain.Adapters[Entity.DrivetrainAdapter].GetFuelScale(Entity)

		ACF.Activate(Entity, true)

		Contraption.SetMass(Entity, Mass)
	end

	-- Spawn-only init (runs before Entity:Spawn(), so the model is ready for physics).
	function ENT:ACF_PreSpawn(_, _, _, ClientData)
		self.ACF               = {}
		self.Active            = false
		self.Firing            = false
		self.Cranking          = false
		self.StarterClock      = 0
		self.Spool             = 0
		self.GasGenerator      = 0
		self.Regen             = 0
		self.LBrake            = 0 -- Read by its wheels as a gearbox's is, on the side they're linked to
		self.RBrake            = 0
		self.RegenTorque       = 0
		self.FuelTanks         = {}
		self.DriverCrewMod     = ACF.CrewFallbackCoef
		self.MassRatio         = 1
		self.FuelUsage         = 0
		self.Throttle          = 0
		self.FlyRPM            = 0
		self.Torque            = 0 -- Read by its outputs while it is off and its drivetrain rests
		self.LastPitch         = 0
		self.LastVolume        = 0
		self.SoundLevel        = 0
		self.LastTorque        = 0
		self.LastFuelUsage     = 0
		self.LastPower         = 0
		self.LastRPM           = 0
		self.LastTotalMass     = 0
		self.LastPhysMass      = 0
		self.revLimiterEnabled = true

		-- ClientData isn't verified yet here; the layout's model unscaled does for the pre-spawn physics,
		-- PostUpdate sizes it.
		local Raw    = ClientData.Engine
		local Layout = Classes.GetSubtypeByName("ACF.Engines.BaseEngine", istable(Raw) and Raw.Type or Raw)
		local Entry  = Layout and Layout.Model or Classes.GetTypeByName("ACF.Engines.V8").Model

		Contraption.SetModel(self, Entry.Model)

		duplicator.ClearEntityModifier(self, "mass")
	end

	function ENT.ACF_CheckSpawnLimit(Player)
		return Player:CheckLimit("_acf_engine")
	end

	function ENT:ACF_PreUpdateEntityData()
		-- Don't reconfigure a running engine; shut it down first (no-op on a fresh spawn).
		if self.Active then self:Disable() end
	end

	function ENT:ACF_PostUpdateEntityData()
		local Engine = self:GetEngine()

		Engine:VerifyData()
		UpdateEngine(self, Engine:GetStats())

		-- A reconfigure can invalidate existing links (no-op on a fresh spawn).
		local Live = self.ACF_LiveData

		for _, Gearbox in ipairs(table.GetKeys(Live.Gearboxes)) do self:Unlink(Gearbox) self:Link(Gearbox) end
		for _, Other in ipairs(table.GetKeys(Live.Cranks)) do self:Unlink(Other) self:Link(Other) end
		for _, Wheel in ipairs(table.GetKeys(Live.Wheels)) do self:Unlink(Wheel) self:Link(Wheel) end

		-- Supported fuel types may have changed (no-op on a fresh spawn, which isn't parented yet)
		if self.ACF_FuelParent then Fuel.Join(self) end

		Fuel.Refresh(self)
		self:UpdateLinkHints()
	end

	function ENT:ACF_SetupWireIO(Inputs)
		-- Unset on the first call of a fresh spawn, which comes before its engine is
		local Type = self.TypeData

		if Type and Type.SetupInputs then Type.SetupInputs(self, Inputs) end
	end

	ACF.RegisterLinkSource("acf_engine", "FuelTanks")
	ACF.RegisterLinkSource("acf_engine", "Gearboxes", nil, true)
	ACF.RegisterLinkSource("acf_engine", "Cranks", nil, true)
	ACF.RegisterLinkSource("acf_engine", "Wheels", nil, true)

end

--===============================================================================================--
-- Meta Funcs
--===============================================================================================--

function ENT:Enable()
	local Active

	if self.Inputs.Active.Path then
		Active = tobool(self.Inputs.Active.Value)
	else
		Active = true
	end

	SetActive(self, Active, self:GetTable())
	Drivetrain.Invalidate(self) -- Only working engines are part of a drivetrain

	self:UpdateOverlay()
	ACF.CheckLegal(self) -- MARCH: Check parent chain on enabled
end

function ENT:Disable()
	SetActive(self, false, self:GetTable()) -- Turn off the engine
	Drivetrain.Invalidate(self)

	self:UpdateOverlay()
end

--- Whether anything takes its torque, through a gearbox or not.
function ENT:HasDrive(SelfTbl)
	SelfTbl = SelfTbl or self:GetTable()

	local Live = SelfTbl.ACF_LiveData

	return next(Live.Gearboxes) or next(Live.Cranks) or next(Live.Wheels) or false
end

function ENT:UpdateLinkHints()
	ACF.Hints.Set(self, "engine_no_gearbox", not self:HasDrive())
end

function ENT:UpdateOutputs(SelfTbl)
	SelfTbl = SelfTbl or self:GetTable()
	local FuelUsage = Round(SelfTbl.FuelUsage)
	local Torque    = SelfTbl.Torque
	local FlyRPM    = SelfTbl.FlyRPM
	local Power     = Round(Torque * FlyRPM / 9548.8)

	Torque = Round(Torque)
	FlyRPM = Round(FlyRPM)

	if SelfTbl.LastFuelUsage ~= FuelUsage then
		SelfTbl.LastFuelUsage = FuelUsage
		WireLib.TriggerOutput(self, "Fuel Use", FuelUsage)
	end
	if SelfTbl.LastTorque ~= Torque then
		SelfTbl.LastTorque = Torque
		WireLib.TriggerOutput(self, "Torque", Torque)
	end
	if SelfTbl.LastPower ~= Power then
		SelfTbl.LastPower = Power
		WireLib.TriggerOutput(self, "Power", Power)
	end
	if SelfTbl.LastRPM ~= FlyRPM then
		SelfTbl.LastRPM = FlyRPM
		WireLib.TriggerOutput(self, "RPM", FlyRPM)
	end
	if SelfTbl.LastFiring ~= SelfTbl.Firing then
		SelfTbl.LastFiring = SelfTbl.Firing
		WireLib.TriggerOutput(self, "Running", SelfTbl.Firing and 1 or 0)
	end
end

function ENT:ACF_UpdateOverlayState(State)
	if self.Firing then
		State:AddSuccess("Running")
	elseif self.Cranking then
		State:AddLabel(self.StartingLabel)
	elseif self.Active then
		State:AddWarning("Stalled")
	else
		State:AddLabel("Off") -- Not a warning, being switched off is normal and warnings are for things to fix
	end

	State:AddKeyValue("Type", self.Name)
	State:AddEnginePower("Power", self.PeakPower)
	State:AddEngineTorque("Torque", self.PeakTorque)
	State:AddKeyValue("Powerband", ("%s - %s RPM"):format(self.PeakMinRPM, self.PeakMaxRPM))
	State:AddKeyValue("Redline", ("%s RPM"):format(self.LimitRPM))
end

ACF.AddInputAction("acf_engine", "Throttle", function(Entity, Value)
	Entity.Throttle = Clamp(Value, Entity.MinThrottle, 100) * 0.01
end)

ACF.AddInputAction("acf_engine", "Regen", function(Entity, Value)
	Entity.Regen = Clamp(Value, 0, 100) * 0.01
end)

ACF.AddInputAction("acf_engine", "Brake", function(Entity, Value)
	local Brake = Clamp(Value, 0, MAX_BRAKE)

	Entity.LBrake = Brake
	Entity.RBrake = Brake
end)

ACF.AddInputAction("acf_engine", "Active", function(Entity, Value)
	SetActive(Entity, tobool(Value), Entity:GetTable())
end)


--This function needs to return HitRes
function ENT:ACF_OnDamage(DmgResult, DmgInfo)
	local HitRes = Damage.doPropDamage(self, DmgResult, DmgInfo)

	-- Adjusting performance based on damage
	local TorqueMult = Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, self.TorqueScale, 1)

	if ACF.IsDestroyed(self) then TorqueMult = 0 end -- Destroyed engines produce no power

	self.PeakTorque = self.PeakTorqueHeld * TorqueMult
	return HitRes
end

function ENT:ACF_OnRepaired()
	self.PeakTorque = self.PeakTorqueHeld
end

function ENT:UpdateSound(SelfTbl)
	SelfTbl = SelfTbl or self:GetTable()

	local Path      = SelfTbl.SoundPath
	local LastSound = SelfTbl.LastSound

	if Path ~= LastSound and LastSound ~= nil then
		self:DestroySound()

		SelfTbl.LastSound = Path
	end

	if Path == "" then return end

	local RPM, Load, Target = Drivetrain.Adapters[SelfTbl.DrivetrainAdapter].GetSound(SelfTbl)
	local Level = max(Target, SelfTbl.SoundLevel - TickInterval() / SOUND_FADE)

	SelfTbl.SoundLevel = Level

	if Level <= 0 then
		if SelfTbl.Sound then self:DestroySound() end

		return
	end

	local Pitch  = Clamp(20 + RPM * SelfTbl.SoundPitch * 0.02, 1, 255)
	local Rev    = 0.1 + 0.9 * (RPM / SelfTbl.LimitRPM) ^ 1.5
	local Volume = Level * (0.25 + Rev * Load * 0.666) * SelfTbl.SoundVolume

	-- Sent as a byte of hundredths; overrun past redline, it would wrap to near silence
	Volume = min(Volume, 2.55)

	if SelfTbl.Sound then
		if abs(Pitch - SelfTbl.LastPitch) < 1 and abs(Volume - SelfTbl.LastVolume) < VOLUME_DELTA then
			return
		end

		-- Held back by the rate limit, it is tried again next tick rather than counted as heard
		if not Sounds.SendAdjustableSound(self, false, Pitch, Volume) then return end
	else
		Sounds.CreateAdjustableSound(self, Path, Pitch, Volume)
		SelfTbl.Sound = true
	end

	SelfTbl.LastPitch  = Pitch
	SelfTbl.LastVolume = Volume
end

function ENT:DestroySound()
	Sounds.SendAdjustableSound(self, true)

	self.LastSound  = nil
	self.LastPitch  = 0
	self.LastVolume = 0
	self.SoundLevel = 0
	self.Sound      = nil
end

function ENT:CFW_PreParentedTo(_, NewParent)
	local ParentValid = IsValid(NewParent) and NewParent:GetClass() == "acf_baseplate"
	self.ACF_EngineParentValid = ParentValid
end

function ENT:CFW_OnParentedTo()
	Fuel.Join(self)
	self:UpdateOverlay()
end

hook.Add("cfw.contraption.entityAdded", "ACF_Engine_ContraptionChecks", function(Contraption, Ent)
	if Ent:GetClass() == "acf_engine" then
		if Contraption.Engines then
			Contraption.Engines[Ent] = true
		else
			Contraption.Engines = {[Ent] = true}
		end

		Contraption.HasEngines   = true
		Contraption.TotalEngines = (Contraption.TotalEngines or 0) + 1
	end
end)

hook.Add("cfw.contraption.entityRemoved", "ACF_Engine_ContraptionChecks", function(Contraption, Ent)
	if Ent:GetClass() == "acf_engine" then
		if Contraption.Engines then
			Contraption.Engines[Ent] = nil
		end

		Contraption.HasEngines   = next(Contraption.Engines) and true or nil
		Contraption.TotalEngines = Contraption.HasEngines and 0 or table.Count(Contraption.Engines)
	end
end)

--- Takes a count of its contraption's mass, which every engine on it shares.
--- @param PhysMass number # kg the vehicle moves itself
--- @param TotalMass number # kg
--- @param Ratio number? # Overrides PhysMass / TotalMass
function ENT:SetMassRatio(PhysMass, TotalMass, Ratio)
	local SelfTbl = ENTITY.GetTable(self)

	SelfTbl.MassRatio = Ratio or PhysMass / TotalMass

	TotalMass = Round(TotalMass, 2)
	PhysMass  = Round(PhysMass, 2)

	if SelfTbl.LastTotalMass ~= TotalMass then
		SelfTbl.LastTotalMass = TotalMass
		WireLib.TriggerOutput(self, "Mass", TotalMass)
	end
	if SelfTbl.LastPhysMass ~= PhysMass then
		SelfTbl.LastPhysMass = PhysMass
		WireLib.TriggerOutput(self, "Physical Mass", PhysMass)
	end
end

--- Counts its contraption's mass now, for every engine on it.
function ENT:CalcMassRatio()
	Contraption.CalcMassRatio(self)
end

--- Fuel per second at a throttle and speed, each engine kind reckoning it its own way: Throttle is what it
--- burns on, the governed throttle of a piston engine or the gas generator of a turbine. TankTbl, the tank's
--- table, comes from a caller that already checked the tank this tick.
function ENT:GetConsumption(Throttle, RPM, FuelTank, SelfTbl, TankTbl)
	SelfTbl = SelfTbl or ENTITY.GetTable(self)

	if not TankTbl then
		FuelTank = FuelTank or SelfTbl.FuelTank
		if not IsEntityValid(FuelTank) then return 0 end

		TankTbl = ENTITY.GetTable(FuelTank)
	end

	local Rate = Drivetrain.Adapters[SelfTbl.DrivetrainAdapter].GetFuelRate(SelfTbl, Throttle,
		RPM * ACF.RPMToRadS)

	return TankTbl.IsElectric and Rate or Rate / TankTbl.FuelDensity
end

--- Fuel per second flat out at peak power, as the menu quotes it.
function ENT:GetPeakConsumption(FuelTank, SelfTbl)
	SelfTbl = SelfTbl or ENTITY.GetTable(self)
	FuelTank = FuelTank or SelfTbl.FuelTank
	if not IsEntityValid(FuelTank) then return 0 end

	if FuelTank.IsElectric then return SelfTbl.FuelUse * SelfTbl.PeakPower end

	return self:GetConsumption(1, SelfTbl.PeakPowerRPM or SelfTbl.LimitRPM, FuelTank, SelfTbl)
end


function ENT:Think()
	local SelfTbl = ENTITY.GetTable(self)

	if not ACF.IsOperational(self, SelfTbl) then
		if SelfTbl.FlyRPM ~= 0 then -- Built out of its drivetrain, nothing turns it any more
			SelfTbl.FlyRPM = 0

			SelfTbl.UpdateOutputs(self, SelfTbl)
		end

		if SelfTbl.Sound then SelfTbl.DestroySound(self) end

		-- Wrecked, it still brakes the wheels on its crank, and nothing else may be stepping them
		if SelfTbl.LBrake > 0 and not SelfTbl.Disabled and next(SelfTbl.ACF_LiveData.Wheels) then
			Drivetrain.Run(self, SelfTbl)

			self:NextThink(CurTime() + TickInterval())

			return true
		end

		return
	end

	-- Switched off and unlinked, it spins down by its losses, and once stopped only switching it on can turn
	-- it again
	if not SelfTbl.Active and not SelfTbl.HasDrive(self, SelfTbl) then
		local Train = SelfTbl.ACF_Powertrain

		if not Train or Train.Resting then
			if SelfTbl.Sound then SelfTbl.DestroySound(self) end

			return
		end
	end

	Drivetrain.Run(self, SelfTbl)

	-- Its drivetrain can disable the engine (e.g. legality issues)
	if SelfTbl.Disabled then
		if SelfTbl.Sound then SelfTbl.DestroySound(self) end

		return
	end

	-- Every tick, as stalling, spooling and switching off fade it rather than cut it
	SelfTbl.UpdateSound(self, SelfTbl)

	SelfTbl.UpdateOutputs(self, SelfTbl)

	self:NextThink(CurTime() + TickInterval())

	return true
end

--- @return boolean # Whether the engine still runs
function ENT:ConsumeFuel(DeltaTime, SelfTbl)
	SelfTbl = SelfTbl or ENTITY.GetTable(self)

	local FuelTank = SelfTbl.FuelTank
	local TankTbl  = FuelTank and IsEntityValid(FuelTank) and ENTITY.GetTable(FuelTank)

	-- Re-searching in the same tick means a tank drained by another engine never stalls this one
	if not (TankTbl and TankTbl.CanConsume(FuelTank, TankTbl)) then
		FuelTank = FindFuelTank(SelfTbl)
		TankTbl  = FuelTank and ENTITY.GetTable(FuelTank)
		SelfTbl.FuelTank = FuelTank

		if FuelTank then SelfTbl.FuelType = TankTbl.FuelType end
	end

	SelfTbl.Discharged = false

	if FuelTank then
		local Throttle    = SelfTbl.FuelThrottle or 0
		local Consumption = SelfTbl.GetConsumption(self, Throttle, SelfTbl.FlyRPM, FuelTank, SelfTbl, TankTbl) * DeltaTime

		SelfTbl.FuelUsage = 60 * Consumption / DeltaTime
		TankTbl.Consume(FuelTank, Consumption, TankTbl)

		return true
	end

	if not ACF.RequireFuel then return true end -- Stay active if fuel consumption is disabled

	SelfTbl.FuelUsage = 0

	-- A motor on a flat battery stays switched on without power, so regenerating can charge it again
	if SelfTbl.IsElectric then
		SelfTbl.Discharged = true

		return true
	end

	SetActive(self, false, SelfTbl)

	return false
end

function ENT:GetCost()
	local selftbl = self:GetTable()

	return ACF.GetEngineCost(selftbl.PeakPower, selftbl.EngineVolume)
end

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still runs
-- ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
	if IsFullUpdate then return end

	local Class = self.ClassData

	if Class and Class.OnLast then
		Class.OnLast(self, Class)
	end

	self:DestroySound()

	Fuel.Leave(self)

	-- Here rather than in the generic unlink after this, so its wheels no longer count it as driving them
	for _, Wheel in ipairs(table.GetKeys(self.ACF_LiveData.Wheels or {})) do
		self:Unlink(Wheel)

		ACF.ReleaseWheelTorqueAxis(Wheel)
	end

	TimerRemove("ACF Engine Clock " .. self:EntIndex())
end

do	-- NET SURFER 2.0
	util.AddNetworkString("ACF_RequestEngineInfo")
	util.AddNetworkString("ACF_InvalidateEngineInfo")

	function ENT:InvalidateClientInfo()
		net.Start("ACF_InvalidateEngineInfo")
			ACF.WriteEntity(self)
		net.Broadcast()
	end

	net.Receive("ACF_RequestEngineInfo", function(_, Ply)
		local Entity = ACF.ReadEntity()

		if IsEntityValid(Entity) and Entity:GetClass() == "acf_engine" then
			local Outputs    = {} -- Each as its index and where the shaft meets it, local to it
			local FuelTanks  = {}
			local Driveshaft = Entity.Out.Pos

			local Live = Entity.ACF_LiveData

			for _, Links in ipairs({ Live.Gearboxes, Live.Wheels }) do
				for E, Link in pairs(Links) do
					Outputs[#Outputs + 1] = { E:EntIndex(), Link:GetTargetPos() }
				end
			end

			-- A shared link points at one end only
			for E in pairs(Live.Cranks) do Outputs[#Outputs + 1] = { E:EntIndex(), E.Out.Pos } end

			for E in pairs(Entity.FuelTanks) do FuelTanks[#FuelTanks + 1] = E:EntIndex() end

			net.Start("ACF_RequestEngineInfo")
				ACF.WriteEntity(Entity)
				net.WriteVector(Driveshaft)
				net.WriteUInt(#Outputs, 8) -- Wheels and cranks count as outputs too
				net.WriteUInt(#FuelTanks, 6)

				for _, Output in ipairs(Outputs) do
					net.WriteUInt(Output[1], MAX_EDICT_BITS)
					net.WriteVector(Output[2])
				end

				if next(FuelTanks) then
					for _, E in ipairs(FuelTanks) do
						net.WriteUInt(E, MAX_EDICT_BITS)
					end
				end
			net.Send(Ply)
		end
	end)
end
	-- Contraption-aware functionality

local ACF = ACF
local Contraption = ACF.Contraption

function Contraption.GetAncestor(Ent)
	if not IsValid(Ent) then return nil end

	local Parent = Ent
	local Last

	while IsValid(Parent:GetParent()) do
		Last   = Parent
		Parent = Parent:GetParent()
	end

	return Parent, Last
end

function Contraption.GetAncestors(Ent)
	local Ancestors = {}
	local Parent    = Ent:GetParent()
	local Count     = 0

	while IsValid(Parent) do
		Count            = Count + 1
		Ancestors[Count] = Parent

		Parent = Parent:GetParent()
	end

	return Ancestors
end

function Contraption.HasAncestor(Ent, Ancestor)
	if not IsValid(Ent) then return false end
	if not IsValid(Ancestor) then return false end

	local Parent = Ent:GetParent()

	while IsValid(Parent) do
		if Parent == Ancestor then
			return true
		end

		Parent = Parent:GetParent()
	end

	return false
end

function Contraption.GetAllPhysicalEntities(Ent, Tab)
	local Res = Tab or {}

	if IsValid(Ent) and not Res[Ent] then
		Res[Ent] = true

		if Ent.Constraints then
			for K, V in pairs(Ent.Constraints) do
				if not IsValid(V) then -- Constraints don't clean up after themselves
					Ent.Constraints[K] = nil -- But we will do Garry a favor and clean up after him
					continue
				end

				if V.Type ~= "NoCollide" then -- NoCollides aren't a real constraint
					Contraption.GetAllPhysicalEntities(V.Ent1, Res)
					Contraption.GetAllPhysicalEntities(V.Ent2, Res)
				end
			end
		end
	end

	return Res
end

function Contraption.GetAllChildren(Ent, Tab)
	local Res = Tab or {}

	for _, V in pairs(Ent:GetChildren()) do
		if Res[V] or not IsValid(V) then continue end

		Res[V] = true
		Contraption.GetAllChildren(V, Res)
	end

	return Res
end

local AddPhysicalWithinReach

do -- MARK: Physical mass reach
	local min = math.min
	local max = math.max

	-- A box's eight corners, as its mins (0) or maxs (1) on each axis; turned into the vehicle's frame, they
	-- bound the box there
	local CORNERS = {
		{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 },
		{ 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
	}

	local function GetCorner(Lo, Hi, Pick)
		return Vector(Pick[1] == 0 and Lo.x or Hi.x, Pick[2] == 0 and Lo.y or Hi.y,
			Pick[3] == 0 and Lo.z or Hi.z)
	end

	local function GetFrame(Core)
		for Ent in pairs(Core) do
			if Ent:GetClass() == "acf_baseplate" then return Ent end
		end
	end

	-- u, about a truck wheel: an unpowered trailer's wheels hang off its bed with none of them linked
	local MIN_REACH = 40

	--- The box, in the baseplate's frame, around the baseplate and the linked wheels on it, grown on every
	--- side by the widest wheel: road wheels, idlers and wheels slaved to a sprocket sit within it, while
	--- mass dragged on a long chain doesn't, as it would add to the mass ratio without the vehicle having to
	--- move it.
	--- @return Entity?, Vector, Vector # No baseplate, no box: a world-aligned one would grow and shrink as the vehicle turns
	local function GetReach(Core)
		local Frame = GetFrame(Core)

		if not Frame then return end

		local Lo, Hi  = Frame:OBBMins(), Frame:OBBMaxs()
		local Longest = max(Hi.x - Lo.x, Hi.y - Lo.y, Hi.z - Lo.z)
		local Margin  = 0

		for Ent in pairs(Core) do
			if Ent ~= Frame then
				local Size = Ent:OBBMaxs() - Ent:OBBMins()

				Margin = max(Margin, Size.x, Size.y, Size.z)
			end
		end

		-- Capped by the vehicle's own size, or a huge prop linked as a wheel would reach over everything
		-- around it
		Margin = max(min(Margin, Longest * 0.5), MIN_REACH)

		local Grow     = Vector(Margin, Margin, Margin)
		local NearMins = Lo - Grow
		local NearMaxs = Hi + Grow
		local Mins     = Vector(Lo)
		local Maxs     = Vector(Hi)

		for Ent in pairs(Core) do
			-- Only wheels on the vehicle widen it, not a linked prop dragged on a rope far behind
			if Ent ~= Frame and Frame:WorldToLocal(Ent:GetPos()):WithinAABox(NearMins, NearMaxs) then
				local ELo, EHi = Ent:OBBMins(), Ent:OBBMaxs()

				for _, Pick in ipairs(CORNERS) do
					local Pos = Frame:WorldToLocal(Ent:LocalToWorld(GetCorner(ELo, EHi, Pick)))

					Mins.x, Mins.y, Mins.z = min(Mins.x, Pos.x), min(Mins.y, Pos.y), min(Mins.z, Pos.z)
					Maxs.x, Maxs.y, Maxs.z = max(Maxs.x, Pos.x), max(Maxs.y, Pos.y), max(Maxs.z, Pos.z)
				end
			end
		end

		return Frame, Mins - Grow, Maxs + Grow
	end

	-- Constrained rather than merely in the set, as a set handed in directly needn't be a contraption; never
	-- parented, as a parented prop has no physics of its own
	local function IsWithinReach(Ent, Frame, Mins, Maxs)
		if IsValid(Ent:GetParent()) or not Contraption.HasConstraints(Ent) then return false end

		local Phys = Ent:GetPhysicsObject()

		if not IsValid(Phys) then return false end

		return Frame:WorldToLocal(Phys:LocalToWorld(Phys:GetMassCenter())):WithinAABox(Mins, Maxs)
	end

	--- Moves what is constrained close enough to the vehicle's core from Detached into Physical. Recounted
	--- whenever the mass ratio is, so something that leaves the contraption or drifts away stops counting;
	--- moving it back with a chip is already a legality violation for the whole contraption.
	function AddPhysicalWithinReach(Physical, Detached)
		if not next(Physical) or not next(Detached) then return end

		local Frame, Mins, Maxs = GetReach(Physical)

		if not Frame then return end

		for Ent in pairs(Detached) do
			if IsWithinReach(Ent, Frame, Mins, Maxs) then
				Detached[Ent] = nil
				Physical[Ent] = true
			end
		end
	end
end

--- Categorizes entities into Physical, Parented, and Detached sets: Physical is what the vehicle has to move itself,
--- its baseplate and linked wheels and whatever unparented is constrained close around them.
--- Accepts either an entity (resolves its CFW contraption) or a pre-built ents set directly.
--- @param CoreOnly boolean? # Only the baseplate and its linked wheels count as Physical, nothing within reach of them
function Contraption.GetEnts(EntOrSet, CoreOnly)
	local EntsSet

	if IsValid(EntOrSet) then
		-- If the caller passed an entity, use its contraption
		local Con = EntOrSet:CFW_GetContraption()
		EntsSet   = Con and Con.ents or {[EntOrSet] = true}
	else
		-- Otherwise, use the set of entities directly
		EntsSet = EntOrSet
	end

	local AllFamilyChildren = {}
	local SeenFamilies      = {}

	-- Every member of a family returns the same set of its children, so each family is walked once
	for K in pairs(EntsSet) do
		local Family = K:GetFamily()

		if not Family or not SeenFamilies[Family] then
			if Family then SeenFamilies[Family] = true end

			for Child in pairs(K:GetFamilyChildren()) do
				AllFamilyChildren[Child] = true
			end
		end
	end

	local Phys = {}
	local Pare = {}
	local Dtch = {}

	for K in pairs(EntsSet) do
		if AllFamilyChildren[K] then
			Pare[K] = true
		else
			local CurFamily = K:GetFamily()

			if CurFamily and CurFamily:GetRoot() ~= K then
				Pare[K] = true
			elseif ACF.IsEntityEligiblePhysmass(K) then
				Phys[K] = true
			else
				Dtch[K] = true
			end
		end
	end

	if not CoreOnly then AddPhysicalWithinReach(Phys, Dtch) end

	return Phys, Pare, Dtch
end

--- Builds a contraption-shaped table from a sequential entity list so entity-list callers can share the contraption pipeline.
function ACF.EntitiesToPseudoContraption(Ents)
	local PseudoCon = {
		ents        = {},
		entsbyclass = {},
		totalMass   = 0,
		count       = 0,
	}

	for _, Ent in pairs(Ents) do
		if not IsValid(Ent) then continue end

		PseudoCon.ents[Ent] = true
		PseudoCon.count     = PseudoCon.count + 1

		local Class = Ent:GetClass()
		if not PseudoCon.entsbyclass[Class] then
			PseudoCon.entsbyclass[Class] = {}
		end
		PseudoCon.entsbyclass[Class][Ent] = true

		local Phys = Ent:GetPhysicsObject()
		if IsValid(Phys) then
			PseudoCon.totalMass = PseudoCon.totalMass + Phys:GetMass()
		end
	end

	return PseudoCon
end

--- Core mass ratio implementation shared by CalcMassRatio and ProcessList; accepts any contraption-shaped table (real or pseudo).
--- When Tally is true, returns Power, Fuel, PhysN, ParN, ConN, OthN, TotMass, PhysMass. Owner name is the caller's responsibility.
function Contraption.CalcMassRatioFromContraption(Con, Tally)
	local PhysMass    = 0
	local Time        = CurTime()
	local Power       = 0
	local Fuel        = 0
	local PhysN       = 0
	local ParN        = 0
	local OthN        = 0
	local ConN        = 0

	local Physical, Parented, Detached = Contraption.GetEnts(Con.ents)
	local Constraints                  = {}

	for K in pairs(Physical) do
		local Phys = K:GetPhysicsObject()

		if not IsValid(Phys) then
			Physical[K] = nil
			OthN        = OthN + 1
		else
			if Tally then
				local Class = K:GetClass()

				if Class == "acf_engine" then
					Power = Power + K.PeakPower * ACF.KwToHp
				elseif Class == "acf_fueltank" then
					Fuel = Fuel + K.Capacity
				end

				if K.Constraints then
					for _, Constraint in pairs(K.Constraints) do
						if IsValid(Constraint) and Constraint.Type ~= "NoCollide" and not Constraints[Constraint] then
							Constraints[Constraint] = true
							ConN                    = ConN + 1
						end
					end
				end

				PhysN = PhysN + 1
			end

			PhysMass = PhysMass + Phys:GetMass()
		end
	end

	-- Parented and detached parts weigh nothing in the ratio, so only a tally needs to look at them
	if Tally then
		for K in pairs(Parented) do
			local Phys = K:GetPhysicsObject()

			if not IsValid(Phys) then
				OthN = OthN + 1
			else
				local Class = K:GetClass()

				if Class == "acf_engine" then
					Power = Power + K.PeakPower * ACF.KwToHp
				elseif Class == "acf_fueltank" then
					Fuel = Fuel + K.Capacity
				end

				ParN = ParN + 1
			end
		end

		for _ in pairs(Detached) do
			OthN = OthN + 1
		end
	end

	local TotMass = Con.totalMass or PhysMass

	-- Kept on the contraption, where KE shoves and rolling resistance read them, rather than on each of its
	-- parts
	Con.ACF_PhysicalMass = PhysMass
	Con.ACF_TotalMass    = TotMass
	Con.ACF_MassTime     = Time

	if Tally then
		return Power, Fuel, PhysN, ParN, ConN, OthN, TotMass, PhysMass
	end
end

function Contraption.HasConstraints(Ent)
	if Ent.Constraints then
		for _, V in pairs(Ent.Constraints) do
			if V.Type ~= "NoCollide" then
				return true
			end
		end
	end

	return false
end

-- s a count stays fresh, as sorting a contraption's parts is slow and its mass rarely changes
local MASS_PERIOD = 10

do -- MARK: Recount on change
	-- Fresh for MASS_PERIOD only while nothing is welded on, parented, merged or split off
	local function Stale(Con)
		if Con then Con.ACF_MassTime = nil end
	end

	local function FamilyChanged(_, Ent)
		if IsValid(Ent) then Stale(Ent:CFW_GetContraption()) end
	end

	hook.Add("cfw.contraption.entityAdded", "ACF_MassRecount", Stale)
	hook.Add("cfw.contraption.entityRemoved", "ACF_MassRecount", Stale)
	hook.Add("cfw.contraption.merged", "ACF_MassRecount", function(_, Into) Stale(Into) end)
	hook.Add("cfw.contraption.split", "ACF_MassRecount",
		function(Parent, Child) Stale(Parent) Stale(Child) end)
	hook.Add("cfw.family.added", "ACF_MassRecount", FamilyChanged)
	hook.Add("cfw.family.subbed", "ACF_MassRecount", FamilyChanged)
end

--- Recounts the entity's contraption unless it was counted recently: running engines and KE shoves both ask,
--- and one count serves them all.
--- @return table # What holds the count (ACF_PhysicalMass, ACF_TotalMass): the contraption, or the entity without one
function Contraption.UpdateMassRatio(Ent)
	local Holder = Ent:CFW_GetContraption() or Ent
	local Last   = Holder.ACF_MassTime

	if Last and CurTime() < Last + MASS_PERIOD then return Holder end

	Contraption.CalcMassRatio(Ent)

	return Holder
end

--- Delegates to CalcMassRatioFromContraption using the entity's CFW contraption, or a single-entity pseudo-contraption as fallback.
function Contraption.CalcMassRatio(Ent, Tally)
	local Con      = Ent:CFW_GetContraption()
	local PseudoCon = Con or ACF.EntitiesToPseudoContraption({Ent})

	local Power, Fuel, PhysN, ParN, ConN, OthN, TotMass, PhysMass = Contraption.CalcMassRatioFromContraption(PseudoCon, Tally)

	if not Con then -- Its own count, as there's no contraption to keep it
		Ent.ACF_PhysicalMass = PseudoCon.ACF_PhysicalMass
		Ent.ACF_TotalMass    = PseudoCon.ACF_TotalMass
		Ent.ACF_MassTime     = PseudoCon.ACF_MassTime

		-- An engine constrained to nothing rides on no vehicle (a test stand), so its wheels move only
		-- themselves
		if Ent.SetMassRatio then Ent:SetMassRatio(Ent.ACF_PhysicalMass, Ent.ACF_TotalMass, 1) end
	end

	if Tally then
		local Owner = Ent:CPPIGetOwner()

		return Power, Fuel, PhysN, ParN, ConN, IsValid(Owner) and Owner:Name() or "Unknown", OthN, TotMass, PhysMass
	end
end

function Contraption.GetMiscInfo(Ent)
	local Contraption = Ent:CFW_GetContraption()
	if not Contraption then return "N/A", "N/A", {} end

	local Name = Contraption.ACF_Baseplate and Contraption.ACF_Baseplate:GetNWString("WireName") or "N/A"
	local BaseplateType = Contraption.ACF_Baseplate and Contraption.ACF_Baseplate:ACF_GetUserVar("BaseplateType").Name or "N/A"
	local AmmoTypes = table.GetKeys(Contraption.AmmoTypes or {}) or {}
	return Name, BaseplateType, AmmoTypes
end

do -- ASSUMING DIRECT CONTROL

	local BlockedTools = {
		proper_clipping		= true,
		improved_clipping	= true,
		makespherical		= true
	}

	local BlockedGroups = {
		[COLLISION_GROUP_DEBRIS]		= true,
		[COLLISION_GROUP_IN_VEHICLE]	= true,
		[COLLISION_GROUP_VEHICLE_CLIP]	= true,
		[COLLISION_GROUP_DOOR_BLOCKER]	= true
	}

	-- If allowed, will remove existing makespherical dupe modifiers on ACF entities
	hook.Add("OnEntityCreated", "ACF Exploitables Stubbing", function(Entity)
		if not ACF.LegalChecks then return end
		if not IsValid(Entity) then return end
		if not Entity.IsACFEntity then return end

		duplicator.ClearEntityModifier(Entity, "sphere")
		duplicator.ClearEntityModifier(Entity, "MakeSphericalCollisions")
	end)

	-- This, if allowed, will prevent physical clips from happening on ACF entities, except for procedural armor
	hook.Add("ProperClippingCanPhysicsClip", "ACF Block PhysicsClip", function(Entity)
		if not ACF.LegalChecks then return true end
		if Entity.IsACFArmor then return true end
		if Entity.IsACFEntity then return false end
	end)

	-- This, if allowed, will prevent ImprovedClipping (e.g. via its E2 functions) from putting clips on any ACF entities, except for procedural armor
	hook.Add("ImprovedClipping_CanClip", "ACF Block ImprovedClipping", function(Entity)
		if not ACF.LegalChecks then return end
		if Entity.IsACFArmor then return end
		if Entity.IsACFEntity then return false end
	end)


	-- This, if allowed, will block ProperClipping/ImprovedClipping from putting clips on any ACF entities, except for procedural armor
	hook.Add("CanTool", "ACF Block ProperClipping", function(_, Trace, Tool)
		if not ACF.LegalChecks then return end

		if not BlockedTools[Tool] then return end

		if Trace.Entity.IsACFArmor and (Tool == "proper_clipping" or Tool == "improved_clipping") then return true end

		if Trace.Entity.IsACFEntity then return false end
	end)

	hook.Add("Initialize", "ACF Meta Detour", function()
		timer.Simple(1, function()
			Contraption.Detours = Contraption.Detours or {
				ENT			= {},
				OBJ			= {},
			}

			local ENT = FindMetaTable("Entity")
			local OBJ = FindMetaTable("PhysObj")

			local EntDetours	= Contraption.Detours.ENT
			local ObjDetours	= Contraption.Detours.OBJ

			local SetMass		= OBJ.SetMass
			ObjDetours.SetMass	= SetMass

			local SetNoDraw					= ENT.SetNoDraw
			local SetModel					= ENT.SetModel
			local PhysicsInitSphere			= ENT.PhysicsInitSphere
			local SetCollisionBounds		= ENT.SetCollisionBounds
			local SetCollisionGroup			= ENT.SetCollisionGroup
			local SetNotSolid				= ENT.SetNotSolid
			local IsVehicle 				= ENT.IsVehicle
			EntDetours.SetNoDraw			= SetNoDraw
			EntDetours.SetModel				= SetModel
			EntDetours.PhysicsInitSphere	= PhysicsInitSphere
			EntDetours.SetCollisionBounds	= SetCollisionBounds
			EntDetours.SetCollisionGroup	= SetCollisionGroup
			EntDetours.SetNotSolid			= SetNotSolid
			EntDetours.IsVehicle			= IsVehicle

			-- Convenience functions that will set the Mass/Model variables in the ACF table for the entity
			function Contraption.SetMass(Entity, Mass)
				Entity.ACF.Mass	=	 Mass

				if Entity.ACF_OnMassChange then
					Entity:ACF_OnMassChange(Entity:GetPhysicsObject():GetMass(), Mass)
				end

				SetMass(Entity:GetPhysicsObject(), Mass)
			end

			function Contraption.SetModel(Entity, Model)
				Entity.ACF.Model	= Model

				SetModel(Entity, Model)
			end

			function OBJ:SetMass(Mass)
				local Ent = self:GetEntity()

				-- Required due for AD2 support, if this isn't present then entities will never get set to their required weight on dupe paste
				if Ent.IsACFEntity and not Ent.ACF_UserWeighable and Ent.ACF then Contraption.SetMass(Ent, Ent.ACF.Mass) return end

				if Ent.ACF_Volumetric_Mesh and not Ent.ACF_UserWeighable then
					local HasNonDefault = false
					for _, MaterialID in pairs(Ent.ACF_Volumetric_Materials or {}) do
						if MaterialID ~= "Default" then HasNonDefault = true break end
					end

					if HasNonDefault then
						SetMass(self, Ent.ACF_Volumetric_Mesh.TotalMass)
						return
					end
				end

				if Ent.ACF_OnMassChange then
					Ent:ACF_OnMassChange(self:GetMass(), Mass)
				end

				SetMass(self, Mass)
			end

			function ENT:SetModel(Model)
				if self.IsACFEntity and self.ACF and self.ACF.Model then
					-- Only enforce model if the entity has been initialized by ACF
					-- ents.Create("acf_ammo") doesn't set ent.ACF, for example
					Contraption.SetModel(self, self.ACF.Model)
					return
				end

				SetModel(self, Model)
			end

			function ENT:IsVehicle()
				if self.IsACFEntity and self.ACF_DetourIsVehicle then
					return self:ACF_DetourIsVehicle()
				end
				return IsVehicle(self)
			end

			-- All of these should prevent the relevant functions from occurring on ACF entities, but only if LegalChecks are enabled
			-- Will also call ACF.CheckLegal at the same time as preventing the function usage, because likely something else is amiss
			function ENT:PhysicsInitSphere(...)
				if self.IsACFEntity and ACF.LegalChecks then ACF.CheckLegal(self) return false end

				self._IsSpherical	= true

				return PhysicsInitSphere(self, ...)
			end

			function ENT:SetCollisionBounds(...)
				if self.IsACFEntity and ACF.LegalChecks then ACF.CheckLegal(self) return end

				SetCollisionBounds(self, ...)
			end

			function ENT:SetCollisionGroup(Group)
				if self.IsACFEntity and ACF.LegalChecks and (BlockedGroups[Group] == true) then ACF.CheckLegal(self) return end

				SetCollisionGroup(self, Group)
			end

			function ENT:SetNoDraw(...)
				if self.IsACFEntity and ACF.LegalChecks then ACF.CheckLegal(self) return end

				SetNoDraw(self, ...)
			end

			function ENT:SetNotSolid(...)
				-- NOTE: Slight delay added to this check in order to account for baseplate conversion otherwise failing
				if not IsValid(self) then return end
				if self.IsACFEntity and ACF.LegalChecks then
					timer.Simple(0, function() if not IsValid(self) then return end ACF.CheckLegal(self) end)
				end

				SetNotSolid(self, ...)
			end

			hook.Remove("Initialize", "ACF Meta Detour")
		end)
	end)
end
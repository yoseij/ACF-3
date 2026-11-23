local ACF         = ACF
local Contraption = ACF.Contraption

do -- MARK: Default damping
	local abs = math.abs

	-- What physics made in code starts with: baseplates, Primitive shapes, spherical wheels
	local VPHYSICS_DEFAULT = 0.1
	-- A ball socket sets both bodies' linear and angular damping to their linear, at least this
	local BALL_SOCKET_MIN  = 0.2
	local TOLERANCE        = 1e-6 -- GetDamping hands back floats
	-- Seconds a paste's entities count as on a vehicle before their constraints say so
	local PASTE_WINDOW     = 10

	-- Pasted entity -> until when. Kept off the entities, which would carry it into every later dupe of them
	local Pasted = setmetatable({}, { __mode = "k" })

	local function IsDefault(Value)
		return abs(Value - VPHYSICS_DEFAULT) < TOLERANCE
	end

	--- Only vehicles that may drive are cleared: an ACF baseplate's contraption, or its paste before the
	--- constraints that join them exist.
	local function IsOnVehicle(Entity)
		if not IsValid(Entity) then return false end

		local Until = Pasted[Entity]

		if Until and Until > CurTime() then return true end

		local Con = Entity:CFW_GetContraption()

		return Con and IsValid(Con.ACF_Baseplate) or false
	end

	--- Velocity damping slows a body at a rate that grows with its speed, so with the mass ratio it held a
	--- heavy vehicle far below its power's top speed; rolling resistance does that job instead. Damping set
	--- on purpose, such as a seat's, differs from the default and is kept.
	--- @param Entities table # Entities as values, as a paste's created entities are
	function Contraption.ClearDefaultDamping(Entities)
		for _, Entity in pairs(Entities) do
			local Phys = IsValid(Entity) and Entity:GetPhysicsObject()

			if IsValid(Phys) then
				local Linear, Angular = Phys:GetDamping()

				if IsDefault(Linear) or IsDefault(Angular) then
					Phys:SetDamping(IsDefault(Linear) and 0 or Linear, IsDefault(Angular) and 0 or Angular)
				end
			end
		end
	end

	--- AdvDupe2 applies each entity's modifiers alongside the paste hooks, so a wheel made spherical after
	--- the baseplate's hook would get the default back; by the next tick all of them have run.
	--- @param CreatedEntities table
	function Contraption.ClearPastedDamping(CreatedEntities)
		if not CreatedEntities then return end

		local Until = CurTime() + PASTE_WINDOW

		for _, Entity in pairs(CreatedEntities) do
			-- Before its welds and parents exist, for Primitive below
			if IsValid(Entity) then Pasted[Entity] = Until end
		end

		timer.Simple(0, function() Contraption.ClearDefaultDamping(CreatedEntities) end)
	end

	-- A vehicle built in place, not pasted, gets the same: each body that joins one, and all of them when the
	-- baseplate joins. A merge adds the smaller contraption's entities one by one, so this sees every join.
	hook.Add("cfw.contraption.entityAdded", "ACF Clear Default Damping", function(Con, Entity)
		if Entity:GetClass() == "acf_baseplate" then
			Contraption.ClearDefaultDamping(table.GetKeys(Con.ents))
		elseif IsValid(Con.ACF_Baseplate) then
			Contraption.ClearDefaultDamping({ Entity })
		end
	end)

	-- Resizing an ACF entity makes it a new physics object
	hook.Add("ACF_OnUpdateEntity", "ACF Clear Default Damping", function(_, Entity)
		timer.Simple(0, function() -- This runs before the update resizes it
			if IsOnVehicle(Entity) then Contraption.ClearDefaultDamping({ Entity }) end
		end)
	end)

	-- Primitive builds its physics over later frames, after a paste's clearing, and again on every edit.
	hook.Add("Primitive_PreRebuildPhysics", "ACF Clear Default Damping", function(Entity)
		-- Not on Primitive_PostRebuildPhysics: the rebuild only puts its constraints and parent back after that,
		-- so the prop wouldn't be found on its vehicle yet
		timer.Simple(0, function()
			if IsOnVehicle(Entity) then Contraption.ClearDefaultDamping({ Entity }) end
		end)
	end)

	local function ClearBallSocketDamping(Phys)
		if not IsValid(Phys) or Phys:GetEntity():IsWorld() then return end

		local Linear, Angular = Phys:GetDamping()

		if abs(Linear - BALL_SOCKET_MIN) < TOLERANCE and abs(Angular - BALL_SOCKET_MIN) < TOLERANCE then
			Phys:SetDamping(0, 0)
		end
	end

	-- A ball socket gives the damping back to the wheels it mounts, and a paste makes its constraints after
	-- the paste's clearing. Only damping at its minimum is cleared, as more than that was the body's own
	-- linear damping.
	hook.Add("OnEntityCreated", "ACF Clear Ball Socket Damping", function(Entity)
		if Entity:GetClass() ~= "phys_ballsocket" then return end

		timer.Simple(0, function() -- Once it has spawned and joined its bodies
			if not IsValid(Entity) then return end

			local Ent1, Ent2 = Entity:GetConstrainedEntities()

			if not IsOnVehicle(Ent1) and not IsOnVehicle(Ent2) then return end

			local Phys1, Phys2 = Entity:GetConstrainedPhysObjects()

			ClearBallSocketDamping(Phys1)
			ClearBallSocketDamping(Phys2)
		end)
	end)
end

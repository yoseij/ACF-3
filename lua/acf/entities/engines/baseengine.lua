local ACF     = ACF
local Classes = ACF.Classes

--- Engines come in families (inline, V, radial, ...) of layouts (a cylinder count or an orientation). An
--- instance of a layout is sized by its displacement or rated power and burns what its engine type burns, and
--- every stat players see is computed from those three, so no engine is better than another for having been
--- written up that way.
Classes.DefineClass("ACF.Engines.BaseEngine", function(CLASS)
	-- What a family may burn; the first is its default
	CLASS.EngineTypes = { "ACF.EngineTypes.GenericPetrol", "ACF.EngineTypes.GenericDiesel" }
	CLASS.Sounds      = {} -- Each recorded for an engine of its size, so the nearest one plays
	-- Footprint in m by litre, fitted to 13 real engines of 0.4 to 23 L, all within 17%
	CLASS.SizeLaw     = { 0.540, 0.270 }
	-- Of the fitted footprint, for a geared variant that carries more than the engines it was fitted to
	CLASS.SizeFactor  = 1

	MENU_FIELD("ACF.EngineTypes.BaseEngineType", "EngineType", { OnlyAllowSubtypes = true, InstantiateTypeForDefault = "ACF.EngineTypes.GenericPetrol" })

	function CLASS.__inherited(NewClass)
		if not NewClass.LimitConVar then
			NewClass.LimitConVar = {
				Name          = "_acf_engine",
				Amount        = 4,
				LegacyDefault = 16,
				Text          = "Maximum amount of ACF engines a player can create."
			}
		end

		Classes.AddSboxLimit(NewClass.LimitConVar)
	end

	local function GetTypeFQN(Instance)
		return Classes.GetTypeName(Instance:GetType())
	end

	function CLASS:IsTypeAllowed(FQN)
		for _, Allowed in ipairs(self.EngineTypes) do
			if Allowed == FQN then return true end
		end

		return false
	end

	--- The field the engine type sizes an engine by.
	function CLASS:GetSizeField()
		return self.EngineType.Scaling
	end

	function CLASS:GetSize()
		return self[self:GetSizeField()] or 0
	end

	--- A family burns only what it was built for, and a layout only comes in the sizes it has models for.
	function CLASS:VerifyData()
		local Type = self.EngineType

		if not (Type and Type.GetType and self:IsTypeAllowed(GetTypeFQN(Type))) then
			self.EngineType = Classes.GetTypeByName(self.EngineTypes[1])()
		end

		local Field = self:GetSizeField()
		local Def   = Classes.GetTypeFieldByName(self:GetType(), Field)

		if Def then
			local Options = Def.Options

			local Value = tonumber(self[Field])

			if not Value or Value ~= Value then Value = Options.Default end -- NaN clamps to NaN

			self[Field] = math.Clamp(Value, Options.Min, Options.Max)
		end
	end

	--- The layout's one model, scaled until its footprint (the geometric mean of its two largest extents)
	--- matches a real engine's of this size. Only the two largest, as the models leave out the manifolds and
	--- accessories that widen real ones.
	function CLASS:GetScale(Size)
		local Law = self.SizeLaw
		local Per = self.SizePerCylinder and Size / self.Cylinders or Size

		return Law[1] * Per ^ Law[2] * (self.Geared and self.SizeFactor or 1) / self.Model.Footprint
	end

	function CLASS:PickSound(Size)
		local Best, BestDistance

		for _, Entry in ipairs(self.Sounds) do
			local Distance = math.abs(math.log(Size / Entry.Size))

			if not Best or Distance < BestDistance then
				Best, BestDistance = Entry, Distance
			end
		end

		return Best
	end

	function CLASS:GetName(Stats)
		if Stats.Power then
			return ("%d kW %s%s"):format(Stats.Power, self.Name, Stats.Geared and " (Geared)" or "")
		end

		return ("%sL %s %s"):format(Stats.Displacement, self.Name, Stats.EngineType.ShortName)
	end

	--- Everything the entity, menu and E2 read about an engine, computed from its layout, type and size and
	--- kept until one of them changes.
	function CLASS:GetStats()
		local Type = self.EngineType
		local Size = self:GetSize()
		local Key  = GetTypeFQN(Type) .. "|" .. Size .. "|" .. tostring(self.Geared)

		if self.StatsKey == Key then return self.Stats end

		local Model        = self.Model
		local Entry        = self:PickSound(Size)
		local Redline      = math.Round(Type:GetRedline(Size, self, self), -1)
		local TypeFQN      = GetTypeFQN(Type)
		local Stats        = {
			Layout       = Classes.GetTypeName(self:GetType()),
			Type         = TypeFQN,
			EngineType   = Type,
			Geared       = self.Geared or false,
			Displacement = Type.Scaling == "Displacement" and Size or nil,
			Power        = Type.Scaling == "Power" and Size or nil,
			Cylinders    = self.Cylinders,
			Model        = Model.Model,
			Scale        = self:GetScale(Size),
			Preview      = { FOV = Model.FOV },
			Sound        = Entry.Sounds[Classes.FullyQualifiedNameToUnqualifiedName(TypeFQN)] or Entry.Sound,
			Pitch        = (Entry.Size / Size) ^ (1 / 6), -- Bigger engines of a kind sound deeper
			Torque       = math.Round(Type:GetTorque(Size, self, self)),
			Mass         = math.Round(Type:GetMass(Size, self, self)),
			FlywheelMass = Type:GetFlywheel(Size, self, self),
			TorqueCurve  = Type.TorqueCurve,
			Fuel         = Type.Fuel,
			IsElectric   = Type.IsElectric,
			IsTrans      = self.IsTrans,
			RPM          = { Idle = math.Round(Type:GetIdle(Redline, self), -1), Limit = Redline },
		}

		Stats.Name   = self:GetName(Stats)
		local Scale = Stats.Scale

		-- m^3 of its box, which its cost goes by
		Stats.Volume = Model.Volume * (isnumber(Scale) and Scale ^ 3 or Scale.x * Scale.y * Scale.z)

		ACF.AddEnginePerformanceData(Stats)

		self.Stats    = Stats
		self.StatsKey = Key

		return Stats
	end
end)

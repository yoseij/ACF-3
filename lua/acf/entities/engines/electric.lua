local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.Electric", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name        = "Electric Motor"
	CLASS.Description = "#acf.descs.engines.electric"
	CLASS.EngineTypes = { "ACF.EngineTypes.Electric" }
	-- kg per m^3 of its box, between the Danfoss EM-PMI318B's 2770 (81 kg, Ø360 x 226 mm) and EM-PMI375's
	-- 2420 (210 kg, Ø450 x 428 mm)
	CLASS.BoxDensity  = 2600
	-- Length over diameter of geared traction motors, between the Danfoss EM-PMI318B's 0.63 and EM-PMI375's
	-- 0.95
	CLASS.Aspect      = 0.8

	MENU_FIELD("ACF.EngineTypes.BaseEngineType", "EngineType", { OnlyAllowSubtypes = true, InstantiateTypeForDefault = "ACF.EngineTypes.Electric" })

	--- A motor's size goes by its mass, which its continuous torque sets, rather than straight by its rating.
	--- The mesh is twice as long for its width as a real motor, so it is shortened along its shaft to a real
	--- motor's proportions.
	function CLASS:GetScale(Size)
		local Model   = self.Model
		local Stretch = self.Aspect / Model.Aspect
		local Scale   = (self.EngineType:GetMass(Size, self, self) / self.BoxDensity / Model.Volume / Stretch) ^ (1 / 3)

		return Vector(Scale * Stretch, Scale, Scale)
	end
end)

do -- Electric Motor
	-- One layout, as every motor needs a battery
	Classes.DefineClass("ACF.Engines.EL", "ACF.Engines.Electric", function(CLASS)
		CLASS.Name      = "Electric Motor"
		CLASS.Order     = 1
		CLASS.Model     = { Model = "models/engines/emotor-standalone-mid.mdl", Footprint = 0.702, Volume = 0.2679, Aspect = 1.63, FOV = 112 } -- Shaft along X, 35.2 in long and 21.5 across
		CLASS.Sounds    = {
			{ Size = 8, Sound = "acf_base/engines/electric_small.wav", Sounds = { Electric = "acf_base/engines/electric_small.wav" } },
			{ Size = 84, Sound = "acf_base/engines/electric_small.wav", Sounds = { Electric = "acf_base/engines/electric_small.wav" } },
			{ Size = 202, Sound = "acf_base/engines/electric_medium.wav", Sounds = { Electric = "acf_base/engines/electric_medium.wav" } },
			{ Size = 396, Sound = "acf_base/engines/electric_large.wav", Sounds = { Electric = "acf_base/engines/electric_large.wav" } },
		}

		MENU_FIELD("Number", "Power", { Min = 8, Max = 495, Default = 261, Decimals = 0 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/emotor-standalone-mid.mdl", {
	Main = { Pos = Vector(11.97), Scale = Vector(26.6, 21.28, 21.28), Sensitive = true },
})

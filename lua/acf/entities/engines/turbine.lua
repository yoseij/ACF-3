local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.Turbine", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name        = "Gas Turbine"
	CLASS.Description = "#acf.descs.engines.turbine"
	CLASS.EngineTypes = { "ACF.EngineTypes.Turbine" }
	-- Footprint in m by kW, fitted to 12 APUs and turboshafts of 75 to 1210 kW, rms 11%
	CLASS.SizeLaw     = { 0.362, 0.134 }
	-- Geared, with the recuperator and reduction gearbox of the AGT1500, 1.4 times the fitted footprint at
	-- its power
	CLASS.SizeFactor  = 1.4

	MENU_FIELD("ACF.EngineTypes.BaseEngineType", "EngineType", { OnlyAllowSubtypes = true, InstantiateTypeForDefault = "ACF.EngineTypes.Turbine" })
	MENU_FIELD("Boolean", "Geared", { Default = false })
end)

do -- Gas Turbine
	Classes.DefineClass("ACF.Engines.GT", "ACF.Engines.Turbine", function(CLASS)
		CLASS.Name      = "Gas Turbine"
		CLASS.Order     = 1
		CLASS.Model     = { Model = "models/engines/gasturbine_m.mdl", Footprint = 1.276, Volume = 1.1781, FOV = 100 }
		CLASS.Sounds    = {
			{ Size = 228, Sound = "acf_base/engines/turbine_small.wav", Sounds = { Turbine = "acf_base/engines/turbine_small.wav" } },
			{ Size = 485, Sound = "acf_base/engines/turbine_medium.wav", Sounds = { Turbine = "acf_base/engines/turbine_medium.wav" } },
			{ Size = 1083, Sound = "acf_base/engines/turbine_large.wav", Sounds = { Turbine = "acf_base/engines/turbine_large.wav" } },
		}

		-- Up to the Abrams' AGT1500
		MENU_FIELD("Number", "Power", { Min = 128, Max = 1120, Default = 485, Decimals = 0 })
	end)
end

do -- Transaxial Gas Turbine
	Classes.DefineClass("ACF.Engines.GT-T", "ACF.Engines.Turbine", function(CLASS)
		CLASS.Name      = "Transaxial Gas Turbine"
		CLASS.Order     = 2
		CLASS.IsTrans   = true -- Driveshaft out of the side
		CLASS.Model     = { Model = "models/engines/turbine_m.mdl", Footprint = 0.982, Volume = 0.5118, FOV = 75 }
		CLASS.Sounds    = {
			{ Size = 128, Sound = "acf_base/engines/turbine_small.wav", Sounds = { Turbine = "acf_base/engines/turbine_small.wav" } },
			{ Size = 272, Sound = "acf_base/engines/turbine_medium.wav", Sounds = { Turbine = "acf_base/engines/turbine_medium.wav" } },
			{ Size = 591, Sound = "acf_base/engines/turbine_large.wav", Sounds = { Turbine = "acf_base/engines/turbine_large.wav" } },
		}

		-- Down to the old small geared one, up to the Abrams' AGT1500
		MENU_FIELD("Number", "Power", { Min = 116, Max = 1120, Default = 272, Decimals = 0 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/gasturbine_m.mdl", {
	Main   = { Pos = Vector(3), Scale = Vector(39, 16.5, 16.5), Sensitive = true },
	Intake = { Pos = Vector(30), Scale = Vector(15, 22.5, 22.5) },
	Output = { Pos = Vector(-24, 0, 6), Scale = Vector(15, 22.5, 36) },
})

ACF.AddHitboxes("models/engines/turbine_m.mdl", {
	Main    = { Pos = Vector(9), Scale = Vector(33, 15, 15), Sensitive = true },
	Chamber = { Pos = Vector(-14.25), Scale = Vector(13.5, 19.5, 19.5) },
	Exhaust = { Pos = Vector(-28.5), Scale = Vector(15, 15, 15) },
	Intake  = { Pos = Vector(29.25), Scale = Vector(7.5, 18, 18) },
})

local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.Rotary", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name            = "Rotary Engine"
	CLASS.Description     = "#acf.descs.engines.rotary"
	CLASS.EngineTypes     = { "ACF.EngineTypes.Wankel" }
	-- Rotor housing across the shaft in m, by litre per rotor; the Curtiss-Wright RC2-75 and Wankel AG
	-- LCR-407 within 6%
	CLASS.SizeLaw         = { 0.567, 1 / 3 }
	CLASS.SizePerCylinder = true -- More rotors only make it longer

	MENU_FIELD("ACF.EngineTypes.BaseEngineType", "EngineType", { OnlyAllowSubtypes = true, InstantiateTypeForDefault = "ACF.EngineTypes.Wankel" })
end)

do -- 2-Rotor
	Classes.DefineClass("ACF.Engines.R2", "ACF.Engines.Rotary", function(CLASS)
		CLASS.Name      = "2-Rotor"
		CLASS.Order     = 1
		CLASS.Cylinders = 2
		CLASS.Model     = { Model = "models/engines/wankel_2_med.mdl", Footprint = 0.447, Volume = 0.0908, FOV = 105 }
		CLASS.Sounds    = {
			{ Size = 0.90, Sound = "acf_base/engines/wankel_small.wav", Sounds = { Wankel = "acf_base/engines/wankel_small.wav" } },
			{ Size = 1.30, Sound = "acf_base/engines/wankel_medium.wav", Sounds = { Wankel = "acf_base/engines/wankel_medium.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 0.90, Max = 1.34, Default = 1.10, Decimals = 2 })
	end)
end

do -- 3-Rotor
	Classes.DefineClass("ACF.Engines.R3", "ACF.Engines.Rotary", function(CLASS)
		CLASS.Name      = "3-Rotor"
		CLASS.Order     = 2
		CLASS.Cylinders = 3
		CLASS.Model     = { Model = "models/engines/wankel_3_med.mdl", Footprint = 0.447, Volume = 0.1177, FOV = 105 }
		CLASS.Sounds    = {
			{ Size = 2.00, Sound = "acf_base/engines/wankel_large.wav", Sounds = { Wankel = "acf_base/engines/wankel_large.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 1.35, Max = 2.01, Default = 2.00, Decimals = 2 })
	end)
end

do -- 4-Rotor
	Classes.DefineClass("ACF.Engines.R4", "ACF.Engines.Rotary", function(CLASS)
		CLASS.Name      = "4-Rotor"
		CLASS.Order     = 3
		CLASS.Cylinders = 4
		CLASS.Model     = { Model = "models/engines/wankel_4_med.mdl", Footprint = 0.447, Volume = 0.1446, FOV = 100 }
		CLASS.Sounds    = {
			{ Size = 2.60, Sound = "acf_base/engines/wankel_large.wav", Sounds = { Wankel = "acf_base/engines/wankel_large.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 1.80, Max = 2.68, Default = 2.60, Decimals = 2 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/wankel_2_med.mdl", {
	Main = { Pos = Vector(7.5), Scale = Vector(16, 13, 17), Sensitive = true },
})

ACF.AddHitboxes("models/engines/wankel_3_med.mdl", {
	Main = { Pos = Vector(10.25), Scale = Vector(22, 13, 17), Sensitive = true },
})

ACF.AddHitboxes("models/engines/wankel_4_med.mdl", {
	Main = { Pos = Vector(13), Scale = Vector(26.5, 13, 17), Sensitive = true },
})

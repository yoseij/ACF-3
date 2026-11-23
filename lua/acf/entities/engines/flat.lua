local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.Flat", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name        = "Flat Engine"
	CLASS.Description = "#acf.descs.engines.flat"
end)

do -- Flat 4
	Classes.DefineClass("ACF.Engines.B4", "ACF.Engines.Flat", function(CLASS)
		CLASS.Name      = "Flat 4"
		CLASS.Order     = 1
		CLASS.Cylinders = 4
		CLASS.Model     = { Model = "models/engines/b4med.mdl", Footprint = 0.681, Volume = 0.1860, FOV = 85 }
		CLASS.Sounds    = {
			{ Size = 1.92, Sound = "acf_base/engines/b4_petrolsmall.wav", Sounds = { GenericDiesel = "acf_extra/vehiclefx/engines/coh/ba11.wav", GenericPetrol = "acf_base/engines/b4_petrolsmall.wav" } },
			{ Size = 3.20, Sound = "acf_base/engines/b4_petrollarge.wav", Sounds = { GenericDiesel = "acf_extra/vehiclefx/engines/coh/ba11.wav", GenericPetrol = "acf_base/engines/b4_petrollarge.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 1.40, Max = 3.20, Default = 2.25, Decimals = 2 })
	end)
end

do -- Flat 6
	Classes.DefineClass("ACF.Engines.B6", "ACF.Engines.Flat", function(CLASS)
		CLASS.Name      = "Flat 6"
		CLASS.Order     = 2
		CLASS.Cylinders = 6
		CLASS.Model     = { Model = "models/engines/b6med.mdl", Footprint = 0.904, Volume = 0.3920, FOV = 83 }
		CLASS.Sounds    = {
			{ Size = 2.80, Sound = "acf_base/engines/b6_petrolsmall.wav", Sounds = { GenericDiesel = "acf_base/engines/v8_diesel.wav", GenericPetrol = "acf_base/engines/b6_petrolsmall.wav" } },
			{ Size = 6.44, Sound = "acf_base/engines/b6_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/v8_diesel.wav", GenericPetrol = "acf_base/engines/b6_petrolmedium.wav" } },
			{ Size = 15.14, Sound = "acf_base/engines/b6_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/l6_diesellarge2.wav", GenericPetrol = "acf_base/engines/b6_petrollarge.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 2.80, Max = 15.80, Default = 8.30, Decimals = 2 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/b4med.mdl", {
	Main         = { Pos = Vector(10.625, 0, 0.625), Scale = Vector(22.5, 20, 11.25), Sensitive = true },
	LeftBank     = { Pos = Vector(11.25, -12.5, 2.5), Scale = Vector(20, 5, 7.5) },
	RightBank    = { Pos = Vector(11.25, 12.5, 2.5), Scale = Vector(20, 5, 7.5) },
	UpperSection = { Pos = Vector(8.75, 0, 8.75), Scale = Vector(13.75, 28.75, 5) },
})

ACF.AddHitboxes("models/engines/b6med.mdl", {
	Main         = { Pos = Vector(16.5, 0, 0.75), Scale = Vector(33, 24, 13.5), Sensitive = true },
	LeftBank     = { Pos = Vector(18, -15, 3), Scale = Vector(30, 6, 9) },
	RightBank    = { Pos = Vector(18, 15, 3), Scale = Vector(30, 6, 9) },
	UpperSection = { Pos = Vector(13.5, 0, 10.5), Scale = Vector(22.5, 34.5, 6) },
})

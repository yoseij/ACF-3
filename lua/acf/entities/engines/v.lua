local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.V", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name        = "V Engine"
	CLASS.Description = "#acf.descs.engines.v"
end)

do -- V-Twin
	Classes.DefineClass("ACF.Engines.V2", "ACF.Engines.V", function(CLASS)
		CLASS.Name      = "V-Twin"
		CLASS.Order     = 1
		CLASS.Cylinders = 2
		CLASS.Model     = { Model = "models/engines/v-twinm2.mdl", Footprint = 0.676, Volume = 0.1719, FOV = 115 }
		CLASS.Sounds    = {
			{ Size = 0.60, Sound = "acf_base/engines/vtwin_small.wav", Sounds = { GenericPetrol = "acf_base/engines/vtwin_small.wav" } },
			{ Size = 1.20, Sound = "acf_base/engines/vtwin_medium.wav", Sounds = { GenericPetrol = "acf_base/engines/vtwin_medium.wav" } },
			{ Size = 2.40, Sound = "acf_base/engines/vtwin_large.wav", Sounds = { GenericPetrol = "acf_base/engines/vtwin_large.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 0.60, Max = 2.40, Default = 1.20, Decimals = 2 })
	end)
end

do -- V4
	Classes.DefineClass("ACF.Engines.V4", "ACF.Engines.V", function(CLASS)
		CLASS.Name      = "V4"
		CLASS.Order     = 2
		CLASS.Cylinders = 4
		CLASS.Model     = { Model = "models/engines/v4m.mdl", Footprint = 0.753, Volume = 0.3615, FOV = 110 }
		CLASS.Sounds    = {
			{ Size = 1.85, Sound = "acf_extra/vehiclefx/engines/l4/elan_onlow.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_diesel2.wav", GenericPetrol = "acf_extra/vehiclefx/engines/l4/elan_onlow.wav" } },
			{ Size = 3.30, Sound = "acf_base/engines/i4_dieselmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_dieselmedium.wav", GenericPetrol = "acf_extra/vehiclefx/engines/l4/elan_onlow.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 1.80, Max = 3.30, Default = 1.90, Decimals = 2 })
	end)
end

do -- V6
	Classes.DefineClass("ACF.Engines.V6", "ACF.Engines.V", function(CLASS)
		CLASS.Name      = "V6"
		CLASS.Order     = 3
		CLASS.Cylinders = 6
		CLASS.Model     = { Model = "models/engines/v6med.mdl", Footprint = 0.744, Volume = 0.4094, FOV = 105 }
		CLASS.Sounds    = {
			{ Size = 2.94, Sound = "acf_extra/vehiclefx/engines/l6/capri_onmid.wav", Sounds = { GenericDiesel = "acf_base/engines/i5_dieselmedium.wav", GenericPetrol = "acf_extra/vehiclefx/engines/l6/capri_onmid.wav" } },
			{ Size = 5.68, Sound = "acf_base/engines/v6_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/i5_dieselmedium.wav", GenericPetrol = "acf_base/engines/v6_petrolmedium.wav" } },
			{ Size = 13.42, Sound = "acf_base/engines/v6_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/v6_diesellarge.wav", GenericPetrol = "acf_base/engines/v6_petrollarge.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 2.40, Max = 15.00, Default = 5.70, Decimals = 2 })
	end)
end

do -- V8
	Classes.DefineClass("ACF.Engines.V8", "ACF.Engines.V", function(CLASS)
		CLASS.Name      = "V8"
		CLASS.Order     = 4
		CLASS.Cylinders = 8
		CLASS.Model     = { Model = "models/engines/v8m.mdl", Footprint = 0.837, Volume = 0.5199, FOV = 100 }
		CLASS.Sounds    = {
			{ Size = 4.21, Sound = "acf_base/engines/v8_special.wav", Sounds = { GenericDiesel = "acf_base/engines/v8_dieselsmall.wav", GenericPetrol = "acf_base/engines/v8_special.wav" } },
			{ Size = 7.97, Sound = "acf_base/engines/v8_special2.wav", Sounds = { GenericDiesel = "acf_base/engines/v8_dieselmedium2.wav", GenericPetrol = "acf_base/engines/v8_special2.wav" } },
			{ Size = 18.49, Sound = "acf_base/engines/v8_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/v8_diesellarge.wav", GenericPetrol = "acf_base/engines/v8_petrollarge.wav" } },
		}

		-- Up to the K1's 31.8 L MB 871
		MENU_FIELD("Number", "Displacement", { Min = 2.90, Max = 32.00, Default = 7.50, Decimals = 2 })
	end)
end

do -- V10
	Classes.DefineClass("ACF.Engines.V10", "ACF.Engines.V", function(CLASS)
		CLASS.Name      = "V10"
		CLASS.Order     = 5
		CLASS.Cylinders = 10
		CLASS.Model     = { Model = "models/engines/v10med.mdl", Footprint = 0.881, Volume = 0.5641, FOV = 100 }
		CLASS.Sounds    = {
			{ Size = 4.77, Sound = "acf_base/engines/v10_special.wav", Sounds = { GenericDiesel = "acf_base/engines/v10_diesellarge.wav", GenericPetrol = "acf_base/engines/v10_special.wav" } },
			{ Size = 8.00, Sound = "acf_base/engines/v10_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/v10_diesellarge.wav", GenericPetrol = "acf_base/engines/v10_petrolmedium.wav" } },
			{ Size = 22.00, Sound = "acf_base/engines/v10_diesellarge.wav", Sounds = { GenericDiesel = "acf_base/engines/v10_diesellarge.wav", GenericPetrol = "acf_base/engines/v10_petrolmedium.wav" } },
		}

		-- Up to the Arjun's 39.7 L MB 838
		MENU_FIELD("Number", "Displacement", { Min = 4.30, Max = 40.00, Default = 6.65, Decimals = 2 })
	end)
end

do -- V12
	Classes.DefineClass("ACF.Engines.V12", "ACF.Engines.V", function(CLASS)
		CLASS.Name      = "V12"
		CLASS.Order     = 6
		CLASS.Cylinders = 12
		CLASS.Model     = { Model = "models/engines/v12m.mdl", Footprint = 0.956, Volume = 0.6784, FOV = 95 }
		CLASS.Sounds    = {
			{ Size = 3.81, Sound = "acf_extra/vehiclefx/engines/v12/gtb4_onmid.wav", Sounds = { GenericDiesel = "acf_base/engines/v12_dieselsmall.wav", GenericPetrol = "acf_extra/vehiclefx/engines/v12/gtb4_onmid.wav" } },
			{ Size = 9.42, Sound = "acf_base/engines/v12_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/v12_dieselmedium.wav", GenericPetrol = "acf_base/engines/v12_petrolmedium.wav" } },
			{ Size = 21.98, Sound = "acf_base/engines/v12_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/v12_diesellarge.wav", GenericPetrol = "acf_base/engines/v12_petrollarge.wav" } },
		}

		-- Up to the Leopard 2's 47.6 L MB 873
		MENU_FIELD("Number", "Displacement", { Min = 3.00, Max = 48.00, Default = 8.10, Decimals = 2 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/v-twinm2.mdl", {
	Shaft   = { Pos = Vector(5.653), Scale = Vector(11.97, 10.64, 10.64), Sensitive = true },
	Piston1 = { Pos = Vector(6.65, -5.32, 11.305), Scale = Vector(7.98, 7.98, 15.96), Angle = Angle(0, 0, 25) },
	Piston2 = { Pos = Vector(6.65, 5.32, 11.305), Scale = Vector(7.98, 7.98, 15.96), Angle = Angle(0, 0, -25) },
})

ACF.AddHitboxes("models/engines/v4m.mdl", {
	Main      = { Pos = Vector(4.063, 0, 9.688), Scale = Vector(22.5, 14.375, 20), Sensitive = true },
	LeftBank  = { Pos = Vector(5.313, -8.437, 14.063), Scale = Vector(19.688, 8.125, 12.5), Angle = Angle(0, 0, 45) },
	RightBank = { Pos = Vector(5.313, 8.438, 14.063), Scale = Vector(19.688, 8.125, 12.5), Angle = Angle(0, 0, -45) },
})

ACF.AddHitboxes("models/engines/v6med.mdl", {
	Main      = { Pos = Vector(13.125, 0, 4.688), Scale = Vector(27.5, 14.375, 20.313), Sensitive = true },
	LeftBank  = { Pos = Vector(14.375, -8.125, 8.75), Scale = Vector(25, 10, 13.75), Angle = Angle(0, 0, 45) },
	RightBank = { Pos = Vector(14.375, 8.125, 8.75), Scale = Vector(25, 10, 13.75), Angle = Angle(0, 0, -45) },
})

ACF.AddHitboxes("models/engines/v8m.mdl", {
	Main      = { Pos = Vector(-1.562, 0, 9.375), Scale = Vector(34.375, 14.375, 20.625), Sensitive = true },
	LeftBank  = { Pos = Vector(0, -8.125, 13.75), Scale = Vector(31.25, 10, 14.063), Angle = Angle(0, 0, 45) },
	RightBank = { Pos = Vector(0, 8.125, 13.75), Scale = Vector(31.25, 10, 14.063), Angle = Angle(0, 0, -45) },
})

ACF.AddHitboxes("models/engines/v10med.mdl", {
	Main      = { Pos = Vector(-4.375, 0, 9.375), Scale = Vector(38.75, 14.375, 20.625), Sensitive = true },
	LeftBank  = { Pos = Vector(-3.125, -8.125, 13.75), Scale = Vector(35, 10, 14.063), Angle = Angle(0, 0, 45) },
	RightBank = { Pos = Vector(-3.125, 8.125, 13.75), Scale = Vector(35, 10, 14.063), Angle = Angle(0, 0, -45) },
})

ACF.AddHitboxes("models/engines/v12m.mdl", {
	Main      = { Pos = Vector(-1.562, 0, 9.375), Scale = Vector(45, 14.375, 20.625), Sensitive = true },
	LeftBank  = { Pos = Vector(-0.312, -8.125, 13.75), Scale = Vector(42.5, 10, 14.063), Angle = Angle(0, 0, 45) },
	RightBank = { Pos = Vector(-0.312, 8.125, 13.75), Scale = Vector(42.5, 10, 14.063), Angle = Angle(0, 0, -45) },
})

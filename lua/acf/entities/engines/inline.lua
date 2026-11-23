local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.Inline", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name        = "Inline Engine"
	CLASS.Description = "#acf.descs.engines.inline"
end)

do -- Single Cylinder
	Classes.DefineClass("ACF.Engines.I1", "ACF.Engines.Inline", function(CLASS)
		CLASS.Name      = "Single Cylinder"
		CLASS.Order     = 1
		CLASS.Cylinders = 1
		CLASS.Model     = { Model = "models/engines/1cylmed.mdl", Footprint = 0.621, Volume = 0.1517, FOV = 125 }
		CLASS.Sounds    = {
			{ Size = 0.25, Sound = "acf_base/engines/i1_small.wav", Sounds = { GenericPetrol = "acf_base/engines/i1_small.wav" } },
			{ Size = 0.50, Sound = "acf_base/engines/i1_medium.wav", Sounds = { GenericPetrol = "acf_base/engines/i1_medium.wav" } },
			{ Size = 1.30, Sound = "acf_base/engines/i1_large.wav", Sounds = { GenericPetrol = "acf_base/engines/i1_large.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 0.25, Max = 1.30, Default = 0.50, Decimals = 2 })
	end)
end

do -- Inline 2
	Classes.DefineClass("ACF.Engines.I2", "ACF.Engines.Inline", function(CLASS)
		CLASS.Name      = "Inline 2"
		CLASS.Order     = 2
		CLASS.Cylinders = 2
		CLASS.Model     = { Model = "models/engines/inline2s.mdl", Footprint = 0.471, Volume = 0.0540, FOV = 125 }
		CLASS.Sounds    = {
			{ Size = 0.85, Sound = "acf_base/engines/i4_diesel2.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_diesel2.wav", GenericPetrol = "acf_extra/vehiclefx/engines/ponyengine.wav" } },
			{ Size = 10.00, Sound = "acf_base/engines/vtwin_large.wav", Sounds = { GenericDiesel = "acf_base/engines/vtwin_large.wav", GenericPetrol = "acf_extra/vehiclefx/engines/ponyengine.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 0.80, Max = 10.00, Default = 0.90, Decimals = 2 })
	end)
end

do -- Inline 3
	Classes.DefineClass("ACF.Engines.I3", "ACF.Engines.Inline", function(CLASS)
		CLASS.Name      = "Inline 3"
		CLASS.Order     = 3
		CLASS.Cylinders = 3
		CLASS.Model     = { Model = "models/engines/inline3m.mdl", Footprint = 0.744, Volume = 0.2026, FOV = 125 }
		CLASS.Sounds    = {
			{ Size = 1.15, Sound = "acf_base/engines/i4_petrolsmall2.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_diesel2.wav", GenericPetrol = "acf_base/engines/i4_petrolsmall2.wav" } },
			{ Size = 3.09, Sound = "acf_base/engines/i4_petrolmedium2.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_dieselmedium.wav", GenericPetrol = "acf_base/engines/i4_petrolmedium2.wav" } },
			{ Size = 12.19, Sound = "acf_base/engines/i4_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_diesellarge.wav", GenericPetrol = "acf_base/engines/i4_petrollarge.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 1.10, Max = 13.50, Default = 3.10, Decimals = 2 })
	end)
end

do -- Inline 4
	Classes.DefineClass("ACF.Engines.I4", "ACF.Engines.Inline", function(CLASS)
		CLASS.Name      = "Inline 4"
		CLASS.Order     = 4
		CLASS.Cylinders = 4
		CLASS.Model     = { Model = "models/engines/inline4m.mdl", Footprint = 0.854, Volume = 0.2611, FOV = 120 }
		CLASS.Sounds    = {
			{ Size = 1.46, Sound = "acf_base/engines/i4_petrolsmall2.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_diesel2.wav", GenericPetrol = "acf_base/engines/i4_petrolsmall2.wav" } },
			{ Size = 3.39, Sound = "acf_base/engines/i4_petrolmedium2.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_dieselmedium.wav", GenericPetrol = "acf_base/engines/i4_petrolmedium2.wav" } },
			{ Size = 15.49, Sound = "acf_base/engines/i4_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/i4_diesellarge.wav", GenericPetrol = "acf_base/engines/i4_petrollarge.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 1.00, Max = 16.00, Default = 2.50, Decimals = 2 })
	end)
end

do -- Inline 5
	Classes.DefineClass("ACF.Engines.I5", "ACF.Engines.Inline", function(CLASS)
		CLASS.Name      = "Inline 5"
		CLASS.Order     = 5
		CLASS.Cylinders = 5
		CLASS.Model     = { Model = "models/engines/inline5m.mdl", Footprint = 0.899, Volume = 0.2959, FOV = 117 }
		CLASS.Sounds    = {
			{ Size = 2.58, Sound = "acf_base/engines/i5_petrolsmall.wav", Sounds = { GenericDiesel = "acf_base/engines/i5_dieselsmall2.wav", GenericPetrol = "acf_base/engines/i5_petrolsmall.wav" } },
			{ Size = 4.00, Sound = "acf_base/engines/i5_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/i5_dieselmedium.wav", GenericPetrol = "acf_base/engines/i5_petrolmedium.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 2.30, Max = 4.10, Default = 3.40, Decimals = 2 })
	end)
end

do -- Inline 6
	Classes.DefineClass("ACF.Engines.I6", "ACF.Engines.Inline", function(CLASS)
		CLASS.Name      = "Inline 6"
		CLASS.Order     = 6
		CLASS.Cylinders = 6
		CLASS.Model     = { Model = "models/engines/inline6m.mdl", Footprint = 0.951, Volume = 0.3236, FOV = 112 }
		CLASS.Sounds    = {
			{ Size = 2.57, Sound = "acf_base/engines/l6_petrolsmall2.wav", Sounds = { GenericDiesel = "acf_base/engines/l6_dieselsmall.wav", GenericPetrol = "acf_base/engines/l6_petrolsmall2.wav" } },
			{ Size = 4.91, Sound = "acf_base/engines/l6_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/l6_dieselmedium4.wav", GenericPetrol = "acf_base/engines/l6_petrolmedium.wav" } },
			{ Size = 18.55, Sound = "acf_base/engines/l6_petrollarge2.wav", Sounds = { GenericDiesel = "acf_base/engines/l6_diesellarge2.wav", GenericPetrol = "acf_base/engines/l6_petrollarge2.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 2.20, Max = 20.00, Default = 4.80, Decimals = 2 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/1cylmed.mdl", {
	Shaft  = { Pos = Vector(5.4), Scale = Vector(21.6, 10.8, 10.8), Sensitive = true },
	Piston = { Pos = Vector(10.125, 0, 12.825), Scale = Vector(12.15, 10.8, 14.85) },
})

ACF.AddHitboxes("models/engines/inline2s.mdl", {
	Shaft   = { Pos = Vector(-1.25, 0, 4.75), Scale = Vector(15.5, 8, 9), Sensitive = true },
	Pistons = { Pos = Vector(-0.5, 0, 13.25), Scale = Vector(10, 5, 8) },
})

ACF.AddHitboxes("models/engines/inline3m.mdl", {
	Shaft   = { Pos = Vector(0.75, 0, 7.125), Scale = Vector(27.75, 12, 13.5), Sensitive = true },
	Pistons = { Pos = Vector(1.5, 0.375, 19.875), Scale = Vector(21, 8.25, 12) },
})

ACF.AddHitboxes("models/engines/inline4m.mdl", {
	Shaft   = { Pos = Vector(0.75, 0, 7.125), Scale = Vector(34.5, 11.25, 13.5), Sensitive = true },
	Pistons = { Pos = Vector(1.875, 0, 19.875), Scale = Vector(27.375, 7.875, 12) },
})

ACF.AddHitboxes("models/engines/inline5m.mdl", {
	Shaft   = { Pos = Vector(-1.125, 0, 7.125), Scale = Vector(42, 11.25, 13.5), Sensitive = true },
	Pistons = { Pos = Vector(0.375, 0, 20.25), Scale = Vector(34.5, 7.875, 12.75) },
})

ACF.AddHitboxes("models/engines/inline6m.mdl", {
	Shaft   = { Pos = Vector(0.75, 0, 7.125), Scale = Vector(48, 11.25, 13.5), Sensitive = true },
	Pistons = { Pos = Vector(1.875, 0, 20.25), Scale = Vector(40.5, 7.875, 12.75) },
})

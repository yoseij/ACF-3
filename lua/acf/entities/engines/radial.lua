local ACF     = ACF
local Classes = ACF.Classes

Classes.DefineClass("ACF.Engines.Radial", "ACF.Engines.BaseEngine", function(CLASS)
	CLASS.Name        = "Radial Engine"
	CLASS.Description = "#acf.descs.engines.radial"
	CLASS.EngineTypes = { "ACF.EngineTypes.Radial", "ACF.EngineTypes.GenericDiesel" }
	-- Diameter in m by litre, fitted to the Warner Scarab, Continental R-670 and Jacobs R-755 within 1%
	CLASS.SizeLaw     = { 0.515, 0.306 }

	MENU_FIELD("ACF.EngineTypes.BaseEngineType", "EngineType", { OnlyAllowSubtypes = true, InstantiateTypeForDefault = "ACF.EngineTypes.Radial" })
end)

do -- Radial 7
	Classes.DefineClass("ACF.Engines.R7", "ACF.Engines.Radial", function(CLASS)
		CLASS.Name       = "Radial 7"
		CLASS.Order      = 1
		CLASS.Cylinders  = 7
		CLASS.MassFactor = 0.6 -- For a type not built as one of these, a diesel radial stays an aero engine
		CLASS.Model      = { Model = "models/engines/radial7m.mdl", Footprint = 0.963, Volume = 0.3295, FOV = 105 }
		CLASS.Sounds     = {
			{ Size = 3.80, Sound = "acf_base/engines/r7_petrolsmall.wav", Sounds = { GenericDiesel = "acf_base/engines/r7_petrolmedium.wav", Radial = "acf_base/engines/r7_petrolsmall.wav" } },
			{ Size = 9.38, Sound = "acf_base/engines/r7_petrolmedium.wav", Sounds = { GenericDiesel = "acf_base/engines/r7_petrolmedium.wav", Radial = "acf_base/engines/r7_petrolmedium.wav" } },
			{ Size = 24.00, Sound = "acf_base/engines/r7_petrollarge.wav", Sounds = { GenericDiesel = "acf_base/engines/r7_petrolmedium.wav", Radial = "acf_base/engines/r7_petrollarge.wav" } },
		}

		MENU_FIELD("Number", "Displacement", { Min = 3.80, Max = 24.00, Default = 9.50, Decimals = 2 })
	end)
end

-- The toolgun's outline of each layout's model at scale 1; engines scale them with themselves
ACF.AddHitboxes("models/engines/radial7m.mdl", {
	Shaft   = { Pos = Vector(-0.665), Scale = Vector(13.3, 11.305, 11.305), Sensitive = true },
	Piston1 = { Pos = Vector(0, 0, -11.97), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 0) },
	Piston2 = { Pos = Vector(0, 9.359, -7.463), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 51.429) },
	Piston3 = { Pos = Vector(0, 11.67, 2.664), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 102.857) },
	Piston4 = { Pos = Vector(0, 5.194, 10.785), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 154.286) },
	Piston5 = { Pos = Vector(0, -5.194, 10.785), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 205.714) },
	Piston6 = { Pos = Vector(0, -11.67, 2.664), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 257.143) },
	Piston7 = { Pos = Vector(0, -9.359, -7.463), Scale = Vector(7.98, 7.98, 13.3), Angle = Angle(0, 0, 308.571) },
})

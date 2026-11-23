local ACF       = ACF
local Classes   = ACF.Classes

-- Weight
local Gear4SW = 50 -- About 15 N·m per kg, as the six-speed T56 (15.5)

-- Torque Rating
local Gear4ST = 735

Classes.DefineClass("ACF.Gearboxes.Manual", "ACF.Gearboxes.BaseGearbox", function(CLASS)
	CLASS.Name			= "Manual"
	CLASS.Cost			= { Base = 0.5, PerGear = 0.1, PerKNm = 0.4, Exponent = 0.5 }
	CLASS.CreateMenu	= ACF.ManualGearboxMenu
	CLASS.CanSetGears	= true
	CLASS.Gears = {
		Min	= 0,
		Max	= 10,
	}
end)

do -- Scalable Gearboxes
	Classes.DefineClass("ACF.Gearboxes.Manual-L", "ACF.Gearboxes.Manual", function(CLASS)
		CLASS.Name			= "Manual, Inline"
		CLASS.ModelName		= "Inline"
		CLASS.Description	= "A standard inline gearbox that requires manual gear shifting."
		CLASS.ID			= "Manual-L"
		CLASS.Model			= "models/engines/linear_s.mdl"
		CLASS.Mass			= Gear4SW
		CLASS.Switch		= 0.15
		CLASS.MaxTorque		= Gear4ST
		CLASS.CanDualClutch	= true
		CLASS.Preview = {
			FOV = 125,
		}
	end)

	Classes.DefineClass("ACF.Gearboxes.Manual-T", "ACF.Gearboxes.Manual", function(CLASS)
		CLASS.Name			= "Manual, Transaxial"
		CLASS.ModelName		= "Transaxial"
		CLASS.Description	= "A standard transaxial gearbox that requires manual gear shifting."
		CLASS.ID			= "Manual-T"
		CLASS.Model			= "models/engines/transaxial_s.mdl"
		CLASS.Mass			= Gear4SW
		CLASS.Switch		= 0.15
		CLASS.MaxTorque		= Gear4ST
		CLASS.CanDualClutch	= true
		CLASS.Preview = {
			FOV = 85,
		}
	end)

	Classes.DefineClass("ACF.Gearboxes.Manual-ST", "ACF.Gearboxes.Manual", function(CLASS)
		CLASS.Name			= "Manual, Straight"
		CLASS.ModelName		= "Straight"
		CLASS.Description	= "A standard straight-through gearbox that requires manual gear shifting."
		CLASS.ID			= "Manual-ST"
		CLASS.Model			= "models/engines/t5small.mdl"
		CLASS.Mass			= Gear4SW
		CLASS.Switch		= 0.15
		CLASS.MaxTorque		= Gear4ST
		CLASS.Preview = {
			FOV = 105,
		}
	end)
end
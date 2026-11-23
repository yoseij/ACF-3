local ACF       = ACF
local Classes   = ACF.Classes

local Gear2SW = 45 -- About 130 N·m per kg, near the Fabco TC-170 transfer case's 120
-- In the standalone clutch's housing and slipping like one, so at its torque per kg rather than a transfer
-- case's
local Gear2StSW = 105

Classes.DefineClass("ACF.Gearboxes.Transfer", "ACF.Gearboxes.BaseGearbox", function(CLASS)
	CLASS.Name			= "Transfer Case"
	-- Simple enough to stay cheap at any size
	CLASS.Cost          = ACF.GearSetCost
	CLASS.CreateMenu	= ACF.ManualGearboxMenu
	CLASS.Gears = {
		Min	= 0,
		Max	= 2,
	}
end)

do -- Scalable gearboxes
	Classes.DefineClass("ACF.Gearboxes.2Gear-L", "ACF.Gearboxes.Transfer", function(CLASS)
		CLASS.Name			= "Transfer Case, Inline"
		CLASS.ModelName		= "Inline"
		CLASS.Description	= "2 speed gearbox. Useful for low/high range and tank turning."
		CLASS.ID			= "2Gear-L"
		CLASS.Model			= "models/engines/linear_s.mdl"
		CLASS.Mass			= Gear2SW
		CLASS.Switch		= 0.3
		CLASS.MaxTorque		= 6000
		CLASS.DualClutch	= true
		CLASS.Preview = {
			FOV = 125,
		}
	end)

	Classes.DefineClass("ACF.Gearboxes.2Gear-T", "ACF.Gearboxes.Transfer", function(CLASS)
		CLASS.Name			= "Transfer Case, Transaxial"
		CLASS.ModelName		= "Transaxial"
		CLASS.Description	= "2 speed gearbox. Useful for low/high range and tank turning."
		CLASS.ID			= "2Gear-T"
		CLASS.Model			= "models/engines/transaxial_s.mdl"
		CLASS.Mass			= Gear2SW
		CLASS.Switch		= 0.3
		CLASS.MaxTorque		= 6000
		CLASS.DualClutch	= true
		CLASS.Preview = {
			FOV = 85,
		}
	end)

	Classes.DefineClass("ACF.Gearboxes.2Gear-ST", "ACF.Gearboxes.Transfer", function(CLASS)
		CLASS.Name			= "Transfer Case, Straight"
		CLASS.ModelName		= "Straight"
		CLASS.Description	= "2 speed straight-through unit, such as a reverser ahead of a final drive. One output, so it can't steer."
		CLASS.ID			= "2Gear-ST"
		CLASS.Model			= "models/engines/flywheelclutchs.mdl"
		CLASS.Mass			= Gear2StSW
		CLASS.Switch		= 0.3
		CLASS.MaxTorque		= 6000
		CLASS.Preview = {
			FOV = 115,
		}
	end)
end
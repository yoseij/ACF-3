local ACF         = ACF
local Classes     = ACF.Classes
Classes.DefineClass("ACF.EngineTypes.Wankel", "ACF.EngineTypes.BaseEngineType", function(CLASS)
	CLASS.Name        = "Generic Wankel Engine"
	CLASS.ShortName   = "Petrol"
	CLASS.Efficiency  = 0.335
	CLASS.TorqueScale = 0.2
	CLASS.TorqueCurve = { 0.35, 0.7, 0.85, 0.95, 1, 0.9, 0.7 }
	CLASS.HealthMult  = 0.125
	CLASS.Pumping     = 0.8
	CLASS.CycleRevs   = 1 -- Each rotor sweeps its rated displacement once per eccentric shaft turn

	-- Mazda's 10A to Renesis; the redline goes by the chamber volume of one rotor, as a cylinder's does for
	-- pistons. Only two of them have published dry weights, so the mass law is a judgement at a road engine's
	-- slope
	CLASS.TorqueLaw   = { 136.3, 1.223 }
	CLASS.MassLaw     = { 100, 0.6 }
	CLASS.RedlineLaw  = { 8943, 0.266 }
	CLASS.FlywheelLaw = { 0.0591, 0.652 }
	CLASS.IdleShare   = 0.10
end)

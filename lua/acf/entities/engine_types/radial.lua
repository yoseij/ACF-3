local ACF         = ACF
local Classes     = ACF.Classes
Classes.DefineClass("ACF.EngineTypes.Radial", "ACF.EngineTypes.BaseEngineType", function(CLASS)
	CLASS.Name        = "Generic Radial Engine"
	CLASS.ShortName   = "Petrol"
	CLASS.Efficiency  = 0.4 -- 0.38 to 0.53
	CLASS.TorqueScale = 0.3
	CLASS.TorqueCurve = { 0.7, 0.96, 1, 0.97, 0.93, 0.82, 0.7, 0.5 }
	CLASS.HealthMult  = 0.3
	CLASS.Pumping     = 0.8
	CLASS.PistonSpeed = 14 -- Long-stroke and slow-revving

	-- Supercharged aero radials from the 7 L Warner Scarab to the 55 L R-3350: boost grows with size, and the
	-- light air-cooled construction is why they weigh a third of a road engine per litre
	CLASS.TorqueLaw   = { 48.0, 1.211 }
	CLASS.MassLaw     = { 19.9, 0.986 }
	CLASS.RedlineLaw  = { 2168, 0.158 }
	CLASS.FlywheelLaw = { 0.0253, 1.438 }
	CLASS.IdleShare   = 0.22

	-- Already an aero engine, so the layout's factor for other types doesn't apply
	function CLASS:GetMass(Size)
		return self.MassLaw[1] * Size ^ self.MassLaw[2]
	end
end)

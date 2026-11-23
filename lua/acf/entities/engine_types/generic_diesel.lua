local ACF         = ACF
local Classes     = ACF.Classes
Classes.DefineClass("ACF.EngineTypes.GenericDiesel", "ACF.EngineTypes.BaseEngineType", function(CLASS)
	CLASS.Name        = "Generic Diesel Engine"
	CLASS.ShortName   = "Diesel"
	CLASS.Efficiency  = 0.243 --up to 0.274
	CLASS.TorqueScale = 0.35
	-- Governed: full power at the limit, still holding 82-94% of peak torque there, as the MB 873, MT 883,
	-- CV12 and AVDS-1790 do
	CLASS.TorqueCurve = { 0.70, 0.82, 0.91, 0.97, 1.00, 0.97, 0.92, 0.87 }
	CLASS.HealthMult  = 0.5
	CLASS.Fuel        = { ["ACF.FuelTypes.Diesel"] = true }
	CLASS.Rubbing     = 0.54 -- Twice the compression pressure of a petrol engine
	CLASS.Pumping     = 0.15 -- No throttle plate to pump against
	CLASS.PistonSpeed = 12
	-- Rated at the limit, so it needs room above it; high idle about 10% over rated, as the AVDS-1790 (2,400
	-- / 2,640)
	CLASS.GovernorDroop = 0.1

	CLASS.MassLaw     = { 90.3, 0.915 }
	-- Rated speed of vehicle diesels, tank engines included; heavy trucks left out, as they are rated for
	-- life, not power
	CLASS.RedlineLaw  = { 2983, -0.209 }
	CLASS.FlywheelLaw = { 0.154, 1.223 }
	CLASS.IdleShare   = 0.27

	-- ln T = A + B·lnD + C·lnD²: naturally aspirated at under a litre (8 bar), turbocharged truck engines
	-- around 12 L (20 bar), easing back towards the big military blocks (17 bar at 27 L, 13.5 at 48 L)
	local A, B, C = 4.274, 1.738, -0.164

	-- Below its smallest engine (0.72 L) the fit falls away, so no less than 7 bar, as small industrial
	-- singles make; the two meet at about that size
	local MIN_BMEP = 7e5 / (4 * math.pi * 1000) -- N·m per litre

	function CLASS:GetTorque(Size)
		local U = math.log(Size)

		return math.max(math.exp(A + B * U + C * U * U), MIN_BMEP * Size)
	end
end)

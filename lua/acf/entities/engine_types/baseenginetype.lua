local ACF         = ACF
local Classes     = ACF.Classes
Classes.DefineClass("ACF.EngineTypes.BaseEngineType", function(CLASS)
	CLASS.ShortName         = "Engine"
	CLASS.DrivetrainAdapter = "Engine"
	CLASS.StartingLabel     = "Cranking"
	CLASS.MinThrottle       = 0
	CLASS.IsElectric        = false
	-- The engine field that sizes it; turbines and motors go by Power
	CLASS.Scaling           = "Displacement"
	CLASS.Fuel              = { ["ACF.FuelTypes.Petrol"] = true }
	CLASS.MaxRedline        = 12000

	-- Stats follow y = k·x^b fits to real engines, x in L; the redline goes by the volume of one cylinder,
	-- which is what sets the piston speed, so more cylinders at a size rev higher
	CLASS.TorqueLaw   = { 86.3, 1.018 } -- N·m
	CLASS.MassLaw     = { 102, 0.60 } -- kg
	CLASS.RedlineLaw  = { 5150, -0.558 } -- rpm
	CLASS.FlywheelLaw = { 0.0258, 1.51 } -- FlywheelMass, as the engine entity has always scaled its inertia
	CLASS.IdleShare   = 0.12 -- Of the redline

	-- Motored friction after Chen-Flynn, FMEP = A + B·p_max + C·Sf + D·Sf², with the compression pressure as
	-- p_max
	CLASS.Rubbing     = 0.42 -- bar, A + B·p_max
	CLASS.Pumping     = 0 -- bar, against a closed throttle
	-- m/s, mean, at the limiter; engines are built to reach about the same whatever their size
	CLASS.PistonSpeed = 18
	CLASS.CycleRevs   = 2 -- Crank turns per cycle of the displacement
	-- Share past the limit over which a governor fades its torque away; without one the rev limiter cuts the
	-- throttle
	CLASS.GovernorDroop = false

	local SPEED_LINEAR    = 0.05 -- bar·s/m, C
	local SPEED_QUADRATIC = 85e-5 -- bar·s²/m², D
	local BAR             = 1e5

	local function Law(Pair, X)
		return Pair[1] * X ^ Pair[2]
	end

	-- Each stat gets (Size, Layout, Engine): the engine instance carries options such as gearing, for
	-- subtypes that need them
	function CLASS:GetTorque(Size)
		return Law(self.TorqueLaw, Size)
	end

	function CLASS:GetMass(Size, Layout)
		return Law(self.MassLaw, Size) * (Layout.MassFactor or 1)
	end

	function CLASS:GetRedline(Size, Layout)
		return math.min(Law(self.RedlineLaw, Size / Layout.Cylinders), self.MaxRedline)
	end

	function CLASS:GetIdle(Redline)
		return Redline * self.IdleShare
	end

	function CLASS:GetFlywheel(Size)
		return Law(self.FlywheelLaw, Size)
	end

	--- Losses turning it over: the constant part, and the parts linear and quadratic in speed at the limiter,
	--- in N·m.
	--- @param Engine table The engine's stats
	--- @return number, number, number
	function CLASS:GetLosses(Engine)
		local PerBar     = BAR * (Engine.Displacement or 0) * 1e-3 / (2 * math.pi * self.CycleRevs)
		local SpeedAtMax = 0.5 * math.pi * self.PistonSpeed -- Sf = ω·S/2

		return (self.Rubbing + self.Pumping) * PerBar, SPEED_LINEAR * SpeedAtMax * PerBar,
			SPEED_QUADRATIC * SpeedAtMax * SpeedAtMax * PerBar
	end
end)

local ACF         = ACF
local Classes     = ACF.Classes
Classes.DefineClass("ACF.EngineTypes.Electric", "ACF.EngineTypes.BaseEngineType", function(CLASS)
	CLASS.Name        = "Generic Electric Engine"
	CLASS.ShortName   = "Electric Motor"
	CLASS.TorqueScale = 0.5
	CLASS.HealthMult  = 0.75
	CLASS.IsElectric  = true
	CLASS.Scaling     = "Power" -- Continuous rating, as ACF has no heat to limit a peak rating by
	CLASS.Fuel        = { ["ACF.FuelTypes.Electric"] = true }

	CLASS.DrivetrainAdapter = "Electric"
	CLASS.MinThrottle       = -100 -- Reverses its current to run backwards

	-- Fitted to liquid-cooled traction motors with published continuous ratings, from car motors to bus and
	-- truck direct drives. Their size, and so their mass, goes by the torque they hold; their speed is no
	-- free choice, as a bigger rotor bursts at a lower speed, so the rating sets both
	CLASS.TopSpeed   = 12000 -- rpm a small motor's bearings allow; production ones run 9,200 to 18,000
	-- rpm·(N·m)^(1/3), the rotor's rim speed limit, through 1700 N·m at 6000 rpm and a Leaf's 250 at 10,500
	CLASS.TipSpeed   = 71580
	-- Top speed over base speed, its constant power range, as a Leaf's flat 320 N·m to 3283 of 10,500 rpm
	CLASS.PowerRange = 3.2
	-- kg by N·m continuous, at the exponent industrial motors scale with size by
	CLASS.MassLaw    = { 0.913, 0.78 }
	-- Rotor kg·m² by motor kg, within 30% for radial motors of 85 to 1780 kg
	CLASS.InertiaLaw = { 2.89e-5, 5 / 3 }
	-- Share of its rating its windings and inverter lose at its rated torque, growing with its square
	CLASS.CopperLoss = 0.05

	local BEARINGS = 0.005 -- Of its continuous torque
	-- Of its rating, lost turning unpowered at top speed, as its magnets drag through the iron
	local IRON     = 0.03
	local FLYWHEEL = 0.45 * math.pi -- kg·m² per unit of FlywheelMass, as the engine entity scales its inertia

	-- Flat torque to its base speed, then constant power to its top speed; the corner lands on a knot
	do
		local Base  = 1 / CLASS.PowerRange
		local Count = 16
		local Curve = {}

		for I = 0, Count do Curve[I + 1] = math.min(1, Base * Count / math.max(I, 1e-9)) end

		CLASS.TorqueCurve = Curve
	end

	-- Its losses at its rated point over its rating, so the menu's consumption reads as the draw it makes
	-- there
	CLASS.Efficiency = 1 / (1 + CLASS.CopperLoss + BEARINGS + IRON / CLASS.PowerRange ^ 2)

	--- Continuous torque and top speed for a continuous rating in kW.
	--- @param Size number
	--- @return number, number
	function CLASS:GetRating(Size)
		local Torque = Size * 1e3 * self.PowerRange / (self.TopSpeed * ACF.RPMToRadS)

		if Torque <= (self.TipSpeed / self.TopSpeed) ^ 3 then return Torque, self.TopSpeed end

		Torque = (Size * 1e3 * self.PowerRange * 30 / (math.pi * self.TipSpeed)) ^ 1.5

		return Torque, self.TipSpeed / Torque ^ (1 / 3)
	end

	function CLASS.CalculateFuelUsage()
		return ACF.FuelRate / 3600 -- kWh per kJ; its losses are reckoned as it draws
	end

	function CLASS:GetTorque(Size, Layout, Engine)
		local Redline = self:GetRedline(Size, Layout, Engine)
		local Probe   = { Torque = 1, TorqueCurve = self.TorqueCurve, RPM = { Idle = 0, Limit = Redline } }

		ACF.AddEnginePerformanceData(Probe)

		return Size / Probe.PeakPower
	end

	function CLASS:GetMass(Size)
		local Torque = self:GetRating(Size)

		return self.MassLaw[1] * Torque ^ self.MassLaw[2]
	end

	function CLASS:GetRedline(Size)
		local _, Redline = self:GetRating(Size)

		return Redline
	end

	function CLASS:GetIdle()
		return 0
	end

	function CLASS:GetFlywheel(Size)
		return self.InertiaLaw[1] * self:GetMass(Size) ^ self.InertiaLaw[2] / FLYWHEEL
	end

	function CLASS:GetLosses(Engine)
		return BEARINGS * Engine.Torque, IRON * Engine.Torque / self.PowerRange, 0
	end

	function CLASS.SetupInputs(_, Inputs)
		Inputs[#Inputs + 1] = "Regen (On a range from 0 to 100, how hard the motor brakes by charging its battery.)"
	end
end)

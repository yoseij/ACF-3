local ACF         = ACF
local Classes     = ACF.Classes
Classes.DefineClass("ACF.EngineTypes.Turbine", "ACF.EngineTypes.BaseEngineType", function(CLASS)
	CLASS.Name        = "Generic Turbine"
	CLASS.ShortName   = "Gas Turbine"
	CLASS.Efficiency  = 0.375 -- previously 0.231
	CLASS.TorqueScale = 0.2
	CLASS.TorqueCurve = { 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1 }
	CLASS.HealthMult  = 0.125
	CLASS.Scaling     = "Power"
	CLASS.Fuel        = { ["ACF.FuelTypes.Petrol"] = true, ["ACF.FuelTypes.Diesel"] = true }

	CLASS.DrivetrainAdapter = "Turbine"
	CLASS.StartingLabel     = "Spooling up"

	-- Sized by rated power in kW. Mass follows free-turbine turboshafts from the Allison 250 to the T64, with
	-- half again for the intake, exhaust and mounts of a vehicle install; a geared output adds the reduction
	-- gearbox and recuperator that bring the AGT1500 to a kilogram per kilowatt
	CLASS.MassLaw     = { 5.06, 0.567 }
	CLASS.FlywheelLaw = { 0.00148, 0.83 } -- The free power turbine's own rotor, light and fast
	CLASS.Limit       = 13000 -- rpm, the power turbine's governed maximum, which its rev limiter holds
	CLASS.Idle        = 1800
	CLASS.GearedMass  = 0.8 -- kg per kW
	CLASS.GearRatio   = 3.25 -- Of a geared output, so it turns like the ground turbines always have

	local BEARINGS = 0.003 -- Of peak torque, so a switched off rotor comes to a stop
	-- Of peak torque at the limiter; rotor drag grows with the square of speed, so little of it is felt in
	-- gear
	local WINDAGE  = 0.02

	local function Ratio(Engine)
		return Engine.Geared and CLASS.GearRatio or 1
	end

	--- Torque is whatever the curve needs to peak at the rated power between idle and the limiter.
	function CLASS:GetTorque(Size, Layout, Engine)
		local Redline = self:GetRedline(Size, Layout, Engine)
		local Probe   = {
			Torque      = 1,
			TorqueCurve = self.TorqueCurve,
			RPM         = { Idle = self:GetIdle(Redline, Engine), Limit = Redline },
		}

		ACF.AddEnginePerformanceData(Probe)

		return Size / Probe.PeakPower
	end

	function CLASS:GetMass(Size, _, Engine)
		return self.MassLaw[1] * Size ^ self.MassLaw[2] + (Engine.Geared and self.GearedMass * Size or 0)
	end

	function CLASS:GetRedline(_, _, Engine)
		return self.Limit / Ratio(Engine)
	end

	function CLASS:GetIdle(_, Engine)
		return self.Idle / Ratio(Engine)
	end

	function CLASS:GetFlywheel(Size, _, Engine)
		-- Seen through the reduction
		return self.FlywheelLaw[1] * Size ^ self.FlywheelLaw[2] * Ratio(Engine) ^ 2
	end

	function CLASS:GetLosses(Engine)
		return BEARINGS * Engine.Torque, 0, WINDAGE * Engine.Torque
	end
end)

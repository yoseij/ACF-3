local ACF      = ACF
local Mobility = ACF.Mobility
local Driver   = Mobility.Driver or {}

Mobility.Driver = Driver

local Clamp         = math.Clamp
local IsEntityValid = ACF.Optimizations.IsEntityValid

--- The baseplate's driver modifier, which scales the torque reaching wheels and effectors. Whatever turns
--- them shows the requirement while it is cut; anything else, such as a gearbox feeding another, is left
--- alone.
--- @param Entity entity # A gearbox, or an engine turning wheels without one
--- @param TurnsWheels boolean # Whether it turns wheels or effectors itself
--- @return number
function Driver.Update(Entity, TurnsWheels)
	local Contraption  = Entity:CFW_GetContraption()
	local Baseplate    = Contraption and Contraption.ACF_Baseplate
	local HasBaseplate = IsEntityValid(Baseplate)
	local Value        = Clamp(HasBaseplate and Baseplate.DriverCrewMod or ACF.CrewFallbackCoef,
		ACF.CrewFallbackCoef, 1)

	Entity.DriverCrewMod = Value

	if Value < 1 and TurnsWheels then
		local Penalty = HasBaseplate and Baseplate.DriverPenalty

		Entity:SetRequirement("gearbox_driver", false, {
			Percent    = math.Round(Value * 100),
			Reason     = Penalty and Penalty.Reason or "not part of a baseplate's contraption",
			Baseplate  = HasBaseplate and Baseplate or nil,
			Drivers    = Penalty and Penalty.Drivers,
			Misaligned = Penalty and Penalty.Misaligned,
		})
	else
		Entity:SetRequirement("gearbox_driver", true)
	end

	return Value
end

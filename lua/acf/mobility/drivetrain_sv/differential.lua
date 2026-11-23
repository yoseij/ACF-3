jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF          = ACF
local Drivetrain   = ACF.Mobility.Drivetrain
local Clutch       = Drivetrain.Clutch
local Differential = Drivetrain.Differential or setmetatable({}, { __index = Clutch })

Drivetrain.Differential = Differential
Differential.__index    = Differential

--- Open on its own, its sides turning apart at equal torque; a clutch between them limits or locks them.
--- @param Input table
--- @param Left table
--- @param Right table
--- @param Ratio number
--- @param Capacity number
function Differential.New(Input, Left, Right, Ratio, Capacity)
	local Object = Clutch.New(Input, Left, Ratio, 1, Capacity)

	Object.Right = Right -- Output is the left side

	return setmetatable(Object, Differential)
end

--- Slip left between the carrier and the average of its sides.
function Differential:GetSlip()
	return self.Ratio * self.Input.Omega - 0.5 * (self.Output.Omega + self.Right.Omega)
end

function Differential:Commit()
	local Impulse = self.Impulse

	if Impulse == 0 then return end

	local Input = self.Input
	local Left  = self.Output
	local Right = self.Right
	local Half  = 0.5 * self.Gain * Impulse

	Input.Omega = Input.Omega - self.Ratio * Impulse / Input.Inertia
	Left.Omega  = Left.Omega + Half / Left.Inertia
	Right.Omega = Right.Omega + Half / Right.Inertia

	Left:OnImpulse(Half)
	Right:OnImpulse(Half)
end

-- MARK: Terminals
Differential.Terminals = 3

function Differential:GetBody(Terminal)
	if Terminal == 1 then return self.Input end
	if Terminal == 2 then return self.Output end

	return self.Right
end

function Differential:GetSense(Terminal)
	return Terminal == 1 and self.Ratio or -0.5
end

function Differential:GetEffect(Terminal)
	return Terminal == 1 and -self.Ratio or 0.5 * self.Gain
end

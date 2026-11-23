jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Body       = Drivetrain.Body
local Output     = Drivetrain.Output or setmetatable({}, { __index = Body })

Drivetrain.Output = Output
Output.__index    = Output

-- Share of a missed prediction blamed on the load each tick; all of it chases tyre stick-slip
local OBSERVER_GAIN = 0.5

--- Whatever the ground, a weld or a brake did to it shows up as a miss against the last prediction, learned
--- as a load so the clutch holds against it the next tick instead of being surprised again. Speeds are
--- relative to the chassis.
--- @param Inertia number
function Output.New(Inertia)
	local Object = Body.New(Inertia)

	Object.Load           = 0
	Object.AppliedImpulse = 0
	Object.Predicted      = false

	return setmetatable(Object, Output)
end

function Output:OnImpulse(Gained)
	self.AppliedImpulse = self.AppliedImpulse + Gained
end

function Output:Integrate(DeltaTime)
	self.Omega = self.Omega + self.Load * DeltaTime / self.Inertia
end

--- @param Omega number
--- @param DeltaTime number
function Output:Observe(Omega, DeltaTime)
	if self.Predicted then
		self.Load = self.Load + OBSERVER_GAIN * self.Inertia * (Omega - self.Omega) / DeltaTime
	end

	self.Omega          = Omega
	self.Predicted      = true
	self.AppliedImpulse = 0
end

--- Skipped steps made no prediction, so the next reading teaches nothing, while the load it held still holds.
function Output:Wake()
	self.Predicted = false
end

--- For when the output's situation changed past what a load explains.
--- @param Omega number
function Output:Reset(Omega)
	self.Omega          = Omega
	self.Load           = 0
	self.Predicted      = false
	self.AppliedImpulse = 0
end

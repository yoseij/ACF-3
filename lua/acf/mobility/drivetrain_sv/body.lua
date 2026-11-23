jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Body       = Drivetrain.Body or {}

Drivetrain.Body = Body
Body.__index    = Body

-- Units throughout the drivetrain: rad/s, N·m (nominal, as players see it), kg·m², N·m·s.
-- Below this the gear is neutral, a zero ratio would otherwise act as a brake
Drivetrain.MinRatio         = 1e-9
-- kg·m², sinks and props set that heavy; solved as not moving, as their speed change only rounds
Drivetrain.ImmovableInertia = 1e9

--- @param Inertia number
function Body.New(Inertia)
	return setmetatable({
		Inertia = Inertia,
		Omega   = 0,
		Sources = {},
	}, Body)
end

--- @param Source table
function Body:AddSource(Source)
	self.Sources[#self.Sources + 1] = Source
end

function Body:OnImpulse() end

--- After steps were skipped at rest.
function Body:Wake() end

function Body:Integrate(DeltaTime)
	local Sources = self.Sources
	local Torque  = 0

	for I = 1, #Sources do
		-- Summed first, so every source sees the same start-of-tick speed
		Torque = Torque + Sources[I]:GetTorque(self.Omega)
	end

	self.Omega = self.Omega + Torque * DeltaTime / self.Inertia
end

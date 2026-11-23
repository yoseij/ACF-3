jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Limits     = Drivetrain.Limits
local Base       = Limits.Base
local SpinCap    = Limits.SpinCap or setmetatable({}, { __index = Base })

Limits.SpinCap  = SpinCap
SpinCap.__index = SpinCap

local huge = math.huge
local max  = math.max
local min  = math.min

--- Physics throws away spin past its angular velocity limit, so a push past it would vanish while its
--- reaction on the chassis stays; what turns an output only takes it as far as its owner's range allows, and
--- the drivetrain slips instead.
--- @param Body table
function SpinCap.New(Body)
	local Object = Base.New(Body, {})

	-- rad/s, relative to the chassis like the body's own speed, set by the output every tick
	Object.MaxOmega = huge
	Object.MinOmega = -huge

	return setmetatable(Object, SpinCap)
end

function SpinCap:Measure(Clutch)
	return Clutch.Gain * Clutch.Impulse
end

function SpinCap:Prepare()
	local Body    = self.Body
	local Inertia = Body.Inertia

	if Inertia >= Drivetrain.ImmovableInertia then
		self.Upper = huge
		self.Lower = -huge

		return
	end

	-- Never past zero, so an output already over its range is only held from going further, not braked
	self.Upper = max(Inertia * (self.MaxOmega - Body.Omega), 0)
	self.Lower = min(Inertia * (self.MinOmega - Body.Omega), 0)
end

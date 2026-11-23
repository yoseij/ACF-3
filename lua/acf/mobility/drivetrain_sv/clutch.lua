jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Clutch     = Drivetrain.Clutch or {}

Drivetrain.Clutch = Clutch
Clutch.__index    = Clutch

local abs  = math.abs
local min  = math.min
local huge = math.huge

local MIN_RATIO = Drivetrain.MinRatio
local IMMOVABLE = Drivetrain.ImmovableInertia

-- Rigid unless made compliant
Clutch.Frequency = 0
Clutch.Damping   = 1
Clutch.Windup    = 0
Clutch.Softness  = 0
Clutch.Bias      = 0

-- Lossless unless given an efficiency, and driving its output until found driven by it
Clutch.Multiplier = 1
Clutch.Efficiency = 1
Clutch.Backdriven = false

--- Impulses are kept in the output's frame: the input pays Ratio times them, the output receives Gain times
--- them. Gain is the Multiplier times the Efficiency, or divided by it when the output drives the input, so
--- losses cost either way.
--- @param Input table
--- @param Output table
--- @param Ratio number
--- @param Multiplier number
--- @param Capacity number
function Clutch.New(Input, Output, Ratio, Multiplier, Capacity)
	return setmetatable({
		Input          = Input,
		Output         = Output,
		Ratio          = Ratio, -- Output speed over input speed, signed, as legacy gear ratios are
		-- Torque multiplier at the output either way, such as a wheel's mass ratio
		Multiplier     = Multiplier,
		Gain           = Multiplier,
		Capacity       = Capacity, -- At the input, already scaled by engagement
		OutputCapacity = huge, -- N·m reaching the output, such as the rating of a gearbox it feeds
		Impulse        = 0,
		MaxImpulse     = 0,
		Saturated      = false,
		Fixed          = false,
	}, Clutch)
end

--- Locked, the output hangs off a damped spring, as on a halfshaft and tyre, so the input doesn't follow its
--- every jolt. The rate comes from the output's own inertia, so any wheel rings at the same frequency, and an
--- immovable one stays rigid.
--- @param Frequency number
--- @param Damping number
function Clutch:SetCompliance(Frequency, Damping)
	self.Frequency = Frequency
	self.Damping   = Damping

	-- Made rigid again: Prepare no longer sets these, so nothing it wound up may linger
	if Frequency == 0 then
		self.Softness = 0
		self.Bias     = 0
		self.Windup   = 0
	end
end

-- How far the output's speed moves per unit of impulse; zero when it can't move
local function GetMobility(self)
	local Inertia = self.Output.Inertia

	return Inertia < IMMOVABLE and self.Gain / Inertia or 0
end

function Clutch:Prepare(DeltaTime)
	local Ratio      = abs(self.Ratio)
	local Efficiency = self.Efficiency
	local Passed     = Efficiency == 1 and 1 or self.Backdriven and 1 / Efficiency or Efficiency

	self.Gain      = self.Multiplier * Passed
	self.Impulse   = 0
	self.Saturated = false
	self.Fixed     = false

	local Most = min(self.Capacity / Ratio, self.OutputCapacity / self.Gain) * DeltaTime

	self.MaxImpulse = Ratio > MIN_RATIO and Most or 0

	local Frequency = self.Frequency

	if Frequency == 0 then return end

	-- Solved implicitly, so stable at any rate: locked, slip and impulse trade off by Softness, and the
	-- windup biases it
	local Step     = DeltaTime * Frequency
	local Damping2 = 2 * self.Damping

	self.Softness = GetMobility(self) / (Step * (Step + Damping2))
	self.Bias     = Frequency * self.Windup / (Step + Damping2)
end

--- Once the impulses are in: a locked clutch winds up by its slip, and one slipping carries its torque in the
--- spring.
function Clutch:Wind(DeltaTime)
	local Frequency = self.Frequency

	if Frequency == 0 then return end

	if self.MaxImpulse == 0 then
		self.Windup = 0
	elseif self.Saturated then
		self.Windup = self.Impulse * GetMobility(self) / (DeltaTime * Frequency * Frequency)
	else
		self.Windup = self.Windup + DeltaTime * self:GetSlip()
	end
end

function Clutch:IsActive()
	return self.MaxImpulse > 0
end

--- Once solved, a lossy clutch learns which way the power went through its gears, from the input side, where
--- they mesh.
--- @return boolean # Whether that differs from what it was solved as, so the tick has to be solved again
function Clutch:Orient()
	if self.Efficiency == 1 then return false end

	local Impulse = self.Impulse
	local Power   = self.Ratio * Impulse * self.Input.Omega

	if Power == 0 then Power = Impulse * self.Output.Omega end
	if Power == 0 then return false end

	local Backdriven = Power < 0

	if Backdriven == self.Backdriven then return false end

	self.Backdriven = Backdriven

	return true
end

--- Impulse drawn from the input, in the input's frame.
function Clutch:GetDraw()
	return self.Ratio * self.Impulse
end

--- Slip left between input and output, in the output's frame.
function Clutch:GetSlip()
	return self.Ratio * self.Input.Omega - self.Output.Omega
end

-- MARK: Terminals
-- The bodies a clutch touches, as the solver sees them: how each one's speed moves the slip, and how its
-- speed moves per unit of impulse, times its inertia. Clutches touching more bodies, as a differential's
-- carrier, override these.
Clutch.Terminals = 2

function Clutch:GetBody(Terminal)
	return Terminal == 1 and self.Input or self.Output
end

function Clutch:GetSense(Terminal)
	return Terminal == 1 and self.Ratio or -1
end

function Clutch:GetEffect(Terminal)
	return Terminal == 1 and -self.Ratio or self.Gain
end

function Clutch:Commit()
	local Impulse = self.Impulse

	if Impulse == 0 then return end

	local Input  = self.Input
	local Output = self.Output
	local Gained = self.Gain * Impulse

	Input.Omega  = Input.Omega - self.Ratio * Impulse / Input.Inertia
	Output.Omega = Output.Omega + Gained / Output.Inertia

	Output:OnImpulse(Gained)
end

-- MARK: Brake
-- A brake from a block that never turns into a wheel. It stops what the wheel turns with and what the
-- drivetrain puts into it, but not the load it learned from the ground: with nothing on the chassis taking
-- the reaction, countering that ahead of time drives the vehicle the other way. What the ground does is still
-- stopped once the wheel turns with it.
local Brake = Drivetrain.Brake or setmetatable({}, { __index = Clutch })

Drivetrain.Brake = Brake
Brake.__index    = Brake

--- @param Block table # A sink body
--- @param Wheel table # The wheel's output body
--- @return table
function Brake.New(Block, Wheel)
	return setmetatable(Clutch.New(Block, Wheel, 1, 1, 0), Brake)
end

function Brake:Prepare(DeltaTime)
	Clutch.Prepare(self, DeltaTime)

	local Output = self.Output

	-- Locks the wheel to where its learned load alone takes it
	self.Bias = (Output.Load or 0) * DeltaTime / Output.Inertia
end

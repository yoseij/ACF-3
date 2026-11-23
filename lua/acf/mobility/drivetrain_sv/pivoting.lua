jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Pivoting   = Drivetrain.Pivoting or {}

Drivetrain.Pivoting = Pivoting

local abs = math.abs

-- Relative, how far past its capacity an impulse may land before the clutch saturates
local TOLERANCE  = 1e-12
-- Relative to the clutch's speeds, a reversal this small is rounding, not a push too hard
local NOISE      = 1e-12
-- Rounds flipping everything may fail to shrink the violations before only one flips at a time
local MAX_STALLS = 3

--- @param State table
function Pivoting.Begin(State)
	State.Best   = math.huge
	State.Stalls = 0
	State.Single = false
end

--- Flips every clutch that has to while that keeps cutting their number, then only the first, which cannot go
--- round in circles when the answer is unique.
--- @param State table
--- @param Clutches table
--- @param Free table
--- @param Bound table
--- @param After table
--- @param Wants table
--- @return boolean # Whether another round is needed
function Pivoting.Settle(State, Clutches, Free, Bound, After, Wants)
	local Count      = #Clutches
	local Violations = 0
	local First      = 0

	for C = 1, Count do
		local Clutch = Clutches[C]
		local Flip   = false

		if Free[C] then
			Flip = abs(Clutch.Impulse) > Clutch.MaxImpulse * (1 + TOLERANCE)
		elseif Bound[C] then
			-- Positive impulse lowers the slip, so a held clutch that leaves it reversed is pushing too hard
			local Slip  = After[C]
			local Noise = 0

			for Terminal = 1, Clutch.Terminals do
				Noise = Noise + abs(Clutch:GetSense(Terminal) * Clutch:GetBody(Terminal).Omega)
			end

			Noise = NOISE * Noise

			Flip = Clutch.Impulse > 0 and Slip < -Noise or Clutch.Impulse < 0 and Slip > Noise
		end

		Wants[C] = Flip

		if Flip then
			Violations = Violations + 1

			if First == 0 then First = C end
		end
	end

	if Violations == 0 then return false end

	if Violations < State.Best then
		State.Best   = Violations
		State.Stalls = 0
	else
		State.Stalls = State.Stalls + 1

		if State.Stalls >= MAX_STALLS then State.Single = true end
	end

	for C = State.Single and First or 1, State.Single and First or Count do
		if Wants[C] then
			local Clutch = Clutches[C]

			if Bound[C] then
				Bound[C] = false
			else
				local Max = Clutch.MaxImpulse

				Clutch.Impulse = Clutch.Impulse > 0 and Max or -Max
				Bound[C]       = true
			end
		end
	end

	return true
end

--- For when the rounds run out before the flips settle: what was solved last is kept within every clutch's
--- capacity, and each one left at it is held there, so nothing past its capacity is committed or taken for a
--- lock.
--- @param Clutches table
--- @param Bound table
function Pivoting.Project(Clutches, Bound)
	for C = 1, #Clutches do
		local Clutch = Clutches[C]
		local Max    = Clutch.MaxImpulse

		if Max > 0 and not Clutch.Fixed and abs(Clutch.Impulse) >= Max * (1 - TOLERANCE) then
			Clutch.Impulse = Clutch.Impulse > 0 and Max or -Max
			Bound[C]       = true
		end
	end
end

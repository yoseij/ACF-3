jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local System     = Drivetrain.System or {}

Drivetrain.System = System
System.__index    = System

local huge = math.huge

--- Solved together, so every engine, gearbox and wheel on one drivetrain sees the same tick.
function System.New()
	return setmetatable({
		Bodies   = {},
		Clutches = {},
		Limits   = {},
	}, System)
end

function System:AddBody(Body)
	self.Bodies[#self.Bodies + 1] = Body

	return Body
end

function System:AddClutch(Clutch)
	self.Clutches[#self.Clutches + 1] = Clutch

	return Clutch
end

function System:AddLimit(Limit)
	self.Limits[#self.Limits + 1] = Limit

	return Limit
end

--- Called once everything is added, before the first step.
function System:Finalize()
	self.Solver    = Drivetrain.TreeSolver.New(self.Bodies, self.Clutches)
		or Drivetrain.Solver.New(self.Bodies, self.Clutches)
	self.LoadShare = Drivetrain.LoadShare.New(self.Bodies, self.Clutches)

	for _, Limit in ipairs(self.Limits) do
		if Limit.Attach then Limit:Attach(self.Clutches) end
	end
end

-- Solves a tick may take; a lossy clutch's push rarely changes sign with its gain, so one more is the norm
local MAX_ORIENTS   = 3
local MAX_RESTRICTS = 3 -- Rounds of limits per solve; whatever still overshoots is left to physics' own clamp

function System:Solve(DeltaTime)
	local Clutches = self.Clutches
	local Limits   = self.Limits
	local Solver   = self.Solver

	for I = 1, #Clutches do Clutches[I]:Prepare(DeltaTime) end
	for I = 1, #Limits do Limits[I]:Prepare(DeltaTime) end

	Solver:Prepare()
	Solver:Solve()

	-- Whatever the limits fixed, the rest of the drivetrain locks against; that can hand what one wheel was
	-- held back from to another through a differential, so they are checked again
	for _ = 1, MAX_RESTRICTS do
		local Restricted = false

		for I = 1, #Limits do
			if Limits[I]:Restrict() then Restricted = true end
		end

		if not Restricted then break end

		Solver:Solve()
	end
end

--- @return boolean # Whether every impulse it solved is finite
function System:Step(DeltaTime)
	local Bodies   = self.Bodies
	local Clutches = self.Clutches
	local Sum      = 0

	-- Before the clutches are prepared, while they still tell which held locked last tick
	self.LoadShare:Apply()

	for I = 1, #Bodies do Bodies[I]:Integrate(DeltaTime) end

	-- Losses scale what crosses a clutch the way the power flows, which is only known once solved; a clutch
	-- solved the wrong way round would hand back what its losses took, so the tick is solved again with it
	-- turned
	for _ = 1, MAX_ORIENTS do
		self:Solve(DeltaTime)

		local Turned = false

		for I = 1, #Clutches do
			if Clutches[I]:Orient() then Turned = true end
		end

		if not Turned then break end
	end

	-- Summed on the way, as one that isn't finite leaves the sum not finite either
	for I = 1, #Clutches do
		local Clutch = Clutches[I]

		Sum = Sum + Clutch.Impulse

		Clutch:Commit()
	end

	for I = 1, #Clutches do Clutches[I]:Wind(DeltaTime) end

	return Sum == Sum and Sum ~= huge and Sum ~= -huge
end

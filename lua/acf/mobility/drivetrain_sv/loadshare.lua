jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local LoadShare  = Drivetrain.LoadShare or {}

Drivetrain.LoadShare = LoadShare
LoadShare.__index    = LoadShare

--- Outputs locked together and held by the ground turn at one speed however the torque is split, so only the
--- group's total load shows; a split among them is one the drivetrain made itself, which the observer
--- relearns, so it grows: the axles fight, and a split across the sides steers the vehicle. Each takes the
--- share of the total that turns it with the rest; a real difference in grip shows as slip, which the windup
--- of its compliant clutch carries.
--- @param Bodies table
--- @param Clutches table
function LoadShare.New(Bodies, Clutches)
	local Index  = {}
	local Joins  = {}
	local Joined = {}

	for I, Body in ipairs(Bodies) do Index[Body] = I end

	-- Which bodies each clutch joins, input first, found once rather than looked up every tick. One touching
	-- a body outside these has no group to join it to.
	for _, Clutch in ipairs(Clutches) do
		local Terms = {}

		for Terminal = 1, Clutch.Terminals do
			local I = Index[Clutch:GetBody(Terminal)]

			if not I then Terms = nil break end

			Terms[Terminal] = I
		end

		if Terms then
			Joins[#Joins + 1]   = Clutch
			Joined[#Joined + 1] = Terms
		end
	end

	return setmetatable({
		Bodies        = Bodies,
		Joins         = Joins,
		Joined        = Joined,
		Parent        = {},
		Ratio         = {}, -- Speed relative to the parent's
		Gain          = {}, -- Torque gain from the parent's frame
		RootOf        = {}, -- Per output this tick: its group's root, and its speed relative to it
		RatioOf       = {},
		Total         = {}, -- Per root, in its frame: load the outputs put on it
		Weight        = {}, -- Per root, in its frame: the outputs' inertia
		Members       = {},
	}, LoadShare)
end

-- Root of a body's locked group, with the body's speed and torque gain relative to it
local function Find(Parent, Ratio, Gain, I)
	local R, G = 1, 1

	while Parent[I] ~= I do
		R = R * Ratio[I]
		G = G * Gain[I]
		I = Parent[I]
	end

	return I, R, G
end

-- Joins B's group to A's, Ratio and Gain as on a clutch from A to B; whether they were apart
local function Join(Parent, Ratios, Gains, A, B, Ratio, Gain)
	local RootA, RatioA, GainA = Find(Parent, Ratios, Gains, A)
	local RootB, RatioB, GainB = Find(Parent, Ratios, Gains, B)

	if RootA == RootB then return false end

	Parent[RootB] = RootA
	Ratios[RootB] = Ratio * RatioA / RatioB
	Gains[RootB]  = Gain * GainA / GainB

	return true
end

-- Clutches that held locked on the last tick join their bodies; this runs before they are prepared for the
-- next one
local function HeldLocked(Clutch)
	return Clutch.MaxImpulse > 0 and not Clutch.Saturated and Clutch.Gain > 0
end

function LoadShare:Group()
	local Joins  = self.Joins
	local Joined = self.Joined
	local Parent = self.Parent
	local Ratio  = self.Ratio
	local Gain   = self.Gain

	for I = 1, #self.Bodies do
		Parent[I] = I
		Ratio[I]  = 1
		Gain[I]   = 1
	end

	-- A differential joins both sides to its carrier whether or not they turn together: its locker splits the
	-- torque between them by its own slip, which loads split between them by the observer would fight
	for I = 1, #Joins do
		local Clutch = Joins[I]

		if HeldLocked(Clutch) then
			local Terms = Joined[I]

			for Terminal = 2, #Terms do
				Join(Parent, Ratio, Gain, Terms[1], Terms[Terminal], Clutch.Ratio, Clutch.Gain)
			end
		end
	end
end

function LoadShare:Apply()
	local Bodies  = self.Bodies
	local Parent  = self.Parent
	local Ratio   = self.Ratio
	local Gain    = self.Gain
	local RootOf  = self.RootOf
	local RatioOf = self.RatioOf
	local Total   = self.Total
	local Weight  = self.Weight
	local Members = self.Members
	local Count   = #Bodies
	local Learned = 0

	-- Only outputs that made a prediction have learned anything; a reset one has no load to share
	for I = 1, Count do
		if Bodies[I].Predicted then Learned = Learned + 1 end
	end

	if Learned < 2 then return end

	self:Group()

	for I = 1, Count do
		Total[I]   = 0
		Weight[I]  = 0
		Members[I] = 0
	end

	for I = 1, Count do
		local Body = Bodies[I]

		if Body.Predicted then
			local Root, R, G = Find(Parent, Ratio, Gain, I)

			RootOf[I], RatioOf[I] = Root, R

			Total[Root]   = Total[Root] + Body.Load * R / G
			Weight[Root]  = Weight[Root] + Body.Inertia * R * R / G
			Members[Root] = Members[Root] + 1
		end
	end

	-- In proportion to its inertia and speed, its load turns it exactly as the rest turn, so the loads alone
	-- move no torque between them, and together they still put the whole total on the root
	for I = 1, Count do
		local Body = Bodies[I]

		if Body.Predicted then
			local Root = RootOf[I]

			if Members[Root] > 1 and Weight[Root] > 0 then
				Body.Load = Total[Root] * Body.Inertia * RatioOf[I] / Weight[Root]
			end
		end
	end
end

jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF    = ACF
local Limits = ACF.Mobility.Drivetrain.Limits
local Base   = Limits.Base or {}

Limits.Base  = Base
Base.__index = Base

local huge = math.huge
local max  = math.max

local SLACK = 1e-9 -- Relative to what the clutches draw, how far past a limit counts as rounding

--- Overdrawn, every clutch pulling the offending way is scaled by the same factor and fixed there, so none of
--- them is starved first and the rest of the drivetrain is solved again against them.
--- @param Body table
--- @param Clutches table
function Base.New(Body, Clutches)
	return setmetatable({
		Body     = Body,
		Clutches = Clutches,
		Upper    = huge,
		Lower    = -huge,
	}, Base)
end

--- Sets Upper and Lower for this tick, overridden by every limit.
function Base:Prepare() end

--- What a clutch counts toward the limit: the draw on its input, unless the limit is on its output.
function Base:Measure(Clutch)
	return Clutch:GetDraw()
end

local function Sum(self, Clutches)
	local Positive, Negative = 0, 0

	for I = 1, #Clutches do
		local Draw = self:Measure(Clutches[I])

		if Draw > 0 then
			Positive = Positive + Draw
		else
			Negative = Negative + Draw
		end
	end

	return Positive, Negative
end

local function ScaleSide(self, Clutches, Sign, Factor)
	for I = 1, #Clutches do
		local Clutch = Clutches[I]

		if self:Measure(Clutch) * Sign > 0 then
			Clutch.Impulse = Clutch.Impulse * Factor
			Clutch.Fixed   = true
		end
	end
end

--- @return boolean # Whether it held any clutch back
function Base:Restrict()
	local Clutches           = self.Clutches
	local Positive, Negative = Sum(self, Clutches)
	local Draw               = Positive + Negative
	-- So clutches already scaled to the limit don't count again by rounding
	local Slack              = SLACK * (Positive - Negative)

	if Draw <= self.Upper + Slack and Draw >= self.Lower - Slack then return false end

	if Draw > self.Upper then
		ScaleSide(self, Clutches, 1, max((self.Upper - Negative) / Positive, 0))
	elseif Draw < self.Lower then
		ScaleSide(self, Clutches, -1, max((self.Lower - Positive) / Negative, 0))
	end

	return true
end

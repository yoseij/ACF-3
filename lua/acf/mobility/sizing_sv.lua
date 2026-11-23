local ACF      = ACF
local Mobility = ACF.Mobility
local Sizing   = Mobility.Sizing or {}

Mobility.Sizing = Sizing

-- A gearbox's rating caps the torque at its input, so its size is right when everything that can reach it
-- fits under it

local min   = math.min
local floor = math.floor
local Round = math.Round
local Clamp = math.Clamp
local Seen  = {}
local Stack = {}
local Path  = {}

-- Engines driving a common gearbox or joined crank to crank turn as one shaft, so any of them can push its
-- torque into anything on it. Sums the shafts of the engines already stacked.
local function SumShafts()
	local Total = 0

	while Stack[1] do
		local Engine = table.remove(Stack)

		if IsValid(Engine) and not Seen[Engine] then
			Seen[Engine] = true
			Total        = Total + (Engine.PeakTorqueHeld or Engine.PeakTorque or 0)

			local Live = Engine.ACF_LiveData

			for Other in pairs(Live.Cranks) do Stack[#Stack + 1] = Other end

			for Box in pairs(Live.Gearboxes) do
				if IsValid(Box) then
					for Other in pairs(Box.Engines) do Stack[#Stack + 1] = Other end
				end
			end
		end
	end

	table.Empty(Seen)

	return Total
end

local function GetShaftTorque(Gearbox)
	for Engine in pairs(Gearbox.Engines) do Stack[#Stack + 1] = Engine end

	return SumShafts()
end

--- Most torque that can reach a gearbox's input: every engine at its peak and every gearbox ahead in its
--- lowest gear, all of it landing here as when the other side of a split is declutched to steer. A gearbox
--- reached by two paths counts on both, which errs large, as a rating should. A flywheel's kick as a clutch
--- bites is left out, being a moment's worth.
--- @param Gearbox entity
--- @return number # N·m
function Sizing.GetMostInput(Gearbox)
	if Path[Gearbox] then return 0 end -- A loop of links brings nothing new

	Path[Gearbox] = true

	local Total = next(Gearbox.Engines) and GetShaftTorque(Gearbox) or 0

	for Source in pairs(Gearbox.GearboxIn) do
		local Ratio = IsValid(Source) and Source:GetLowestRatio() or 0

		if Ratio > Mobility.Drivetrain.MinRatio then
			Total = Total + min(Sizing.GetMostInput(Source), Source.MaxTorque)
				* Source:GetRatedEfficiency() / Ratio
		end
	end

	Path[Gearbox] = nil

	return Total
end

--- Smallest scale, to the menu's two decimals, whose rating takes the torque; the largest allowed if none
--- does.
--- @param Gearbox entity
--- @param Torque number N·m
--- @return number # Scale
--- @return number # Its rating, N·m
function Sizing.GetScaleFor(Gearbox, Torque)
	local Exponent = ACF.GearboxTorqueScale
	local MaxSize  = ACF.GearboxMaxSize
	local Base     = Gearbox.BaseTorque or Gearbox.MaxTorque / Gearbox.ScaleMult ^ Exponent
	local Scale    = Clamp(floor((Torque / Base) ^ (1 / Exponent) * 100) / 100, ACF.GearboxMinSize, MaxSize)
	local _, _, Rating = ACF.GetGearboxStats(0, Scale, Base)

	-- The rating rounds down to tens, so the root alone can fall just short
	while Rating < Torque and Scale < MaxSize do
		Scale = Round(Scale + 0.01, 2)

		_, _, Rating = ACF.GetGearboxStats(0, Scale, Base)
	end

	return Scale, Rating
end

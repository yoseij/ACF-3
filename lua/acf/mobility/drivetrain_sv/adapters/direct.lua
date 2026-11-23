jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF      = ACF
local Adapters = ACF.Mobility.Drivetrain.Adapters
local Gearbox  = Adapters.Gearbox or {} -- Filled in by gearbox.lua, which loads after this
local Direct   = Adapters.Direct or {}

Adapters.Gearbox = Gearbox
Adapters.Direct  = Direct
Direct.__index   = Direct

local VECTOR   = FindMetaTable("Vector")
local huge     = math.huge
local Reaction = Vector() -- Each engine sums into it in turn

--- An engine's crank coupled to the wheels on it with no gears or clutch between, as a solid shaft. A wrecked
--- engine turns nothing, but still brakes them.
--- @param Entity entity
--- @param Train table
function Direct.New(Entity, Train)
	return setmetatable({
		Entity = Entity,
		EntTbl = Entity:GetTable(),
		Train  = Train,
		Shafts = {},
		Brakes = {},
	}, Direct)
end

--- A wheel it only brakes.
--- @param Link table
--- @param Target table
function Direct:AddBrake(Link, Target)
	local Brakes = self.Brakes

	Brakes[#Brakes + 1] = { Link = Link, Target = Target }
end

--- @param Clutch table
--- @param Link table
--- @param Target table
--- @param Sign number
function Direct:AddLink(Clutch, Link, Target, Sign)
	local Shafts = self.Shafts

	Clutch.Ratio = Sign

	Shafts[#Shafts + 1] = { Clutch = Clutch, Link = Link, Target = Target }
end

--- What it turns sets each shaft as it does a gearbox's, so wheels take the driver and the mass ratio from
--- the engine.
function Direct:PreStep()
	local EntTbl = self.EntTbl

	for _, Shaft in ipairs(self.Shafts) do
		local Clutch = Shaft.Clutch

		Clutch.Multiplier = 1
		Clutch.Capacity   = huge

		Shaft.Target:AdjustClutch(Clutch, EntTbl, Shaft.Link)
	end

	for _, Brake in ipairs(self.Brakes) do
		Brake.Target:AdjustBrake(EntTbl, Brake.Link)
	end
end

--- Its engine sorts itself; the coupling has nothing to skip.
function Direct:Enroll() end

function Direct:IsResting()
	return true
end

function Direct:PostStep()
	VECTOR.Zero(Reaction)

	for _, Shaft in ipairs(self.Shafts) do
		Shaft.Target:AddReaction(Shaft.Clutch, Reaction)
	end

	Gearbox.ApplyReaction(self.Entity, Reaction, self.Train)
end

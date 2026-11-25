jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF      = ACF
local Adapters = ACF.Mobility.Drivetrain.Adapters
local Gearbox  = Adapters.Gearbox or {} -- Filled in by gearbox.lua, which loads after this
local CVT      = Adapters.CVT or setmetatable({}, { __index = Gearbox })

Adapters.Gearbox = Gearbox
Adapters.CVT     = CVT
CVT.__index      = CVT
CVT.LaunchClutch = true -- As on a scooter's, so it pulls away and stops without stalling
CVT.Always       = true -- Its ratio follows its speed, so its gearing is worked out every tick

local RPM_TO_RADS = ACF.RPMToRadS

function CVT.New(Entity, Input, Train)
	local Object = Gearbox.New(Entity, Input, Train)

	Object.HeldOutput = false -- rpm at the output its engaged outputs last set

	return setmetatable(Object, CVT)
end

--- An output that held locked last tick pins its shaft, so while any does only those count: one that slips
--- beside it would set a ratio the shaft doesn't turn at, running the engine past its band. When all of them
--- slip they count: overloaded they turn as slowly as the vehicle does, so the ratio comes down to where they
--- can pull; left out, the engine's speed would keep the ratio too tall to stop the slip.
--- @return number? # nil with no output engaged
function CVT:GetLockedRPM()
	local Sum, Count         = 0, 0
	local SlipSum, SlipCount = 0, 0

	for _, Record in ipairs(self.Links) do
		local Clutch = Record.Clutch

		if Clutch:IsActive() and Record.Target:HoldsSpeed() then
			local Speed = Clutch.Output.Omega / Clutch.Ratio

			if Clutch.Saturated then
				SlipSum   = SlipSum + Speed
				SlipCount = SlipCount + 1
			else
				Sum   = Sum + Speed
				Count = Count + 1
			end
		end
	end

	if Count == 0 then Sum, Count = SlipSum, SlipCount end
	if Count == 0 then return end

	return Sum / Count / RPM_TO_RADS
end

--- Its ratio follows the speed it turns at, which its engaged outputs set rather than the engine. With none
--- engaged it keeps the output speed they last set, as a free engine revving up would otherwise shift it tall
--- within a tick or two and leave it there when they engage again.
function CVT:UpdateGearing(Entity, EntTbl)
	local LockedRPM = self:GetLockedRPM()
	local Gear      = EntTbl.Gears[1]

	if LockedRPM then
		self.HeldOutput = LockedRPM * Gear
	elseif self.HeldOutput and Gear > 0 then
		LockedRPM = self.HeldOutput / Gear
	end

	EntTbl.UpdateGearing(Entity, self.Input.Omega / RPM_TO_RADS, LockedRPM, EntTbl)
end

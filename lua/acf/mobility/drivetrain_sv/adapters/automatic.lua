jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF       = ACF
local Adapters  = ACF.Mobility.Drivetrain.Adapters
local Gearbox   = Adapters.Gearbox or {} -- Filled in by gearbox.lua, which loads after this
local Automatic = Adapters.Automatic or setmetatable({}, { __index = Gearbox })

Adapters.Gearbox       = Gearbox
Adapters.Automatic     = Automatic
Automatic.__index      = Automatic
Automatic.LaunchClutch = true -- As a torque converter would, so it pulls away and stops without stalling
-- It shifts by itself from the vehicle's speed, so its gearing is worked out every tick
Automatic.Always       = true

local RPM_TO_RADS = ACF.RPMToRadS

function Automatic.New(Entity, Input, Train)
	return setmetatable(Gearbox.New(Entity, Input, Train), Automatic)
end

--- It shifts by itself from the vehicle's speed, so its gearing can move on any tick.
function Automatic:UpdateGearing(Entity, EntTbl)
	EntTbl.UpdateGearing(Entity, self.Input.Omega / RPM_TO_RADS, nil, EntTbl)
end

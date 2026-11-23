local Drivetrain = ACF.Mobility.Drivetrain

local DT        = 1 / 66
local IDLE      = 800 * ACF.RPMToRadS
local LIMIT     = 6000 * ACF.RPMToRadS
local IMMOVABLE = 1e12 -- An output too heavy to move, such as a vehicle far heavier than its engine

local function Constant( Torque )
    return { GetTorque = function() return Torque end }
end

local PISTON = {
    IdleRPM = 800, LimitRPM = 6000, PeakTorque = 300, PeakTorqueHeld = 300, TorqueCurve = { 0.6, 0.8, 1, 0.9, 0.7 },
    LossConstant = 30, LossLinear = 0, LossQuadratic = 0,
}

local TURBINE = {
    Adapter = "Turbine", IdleRPM = 1800, LimitRPM = 12000, PeakTorque = 300, PeakTorqueHeld = 300,
    TorqueCurve = { 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1 }, LossConstant = 1, LossLinear = 0, LossQuadratic = 6, Spool = 1, GasGenerator = 1,
}

local ELECTRIC = {
    Adapter = "Electric", IdleRPM = 0, LimitRPM = 10000, PeakTorque = 300, PeakTorqueHeld = 300, TorqueCurve = { 1, 0.5, 0 },
    LossConstant = 0, LossLinear = 0, LossQuadratic = 0, FuelUse = 1e-3, PeakPower = 120, TypeData = { CopperLoss = 0.05 },
}

-- One engine on its own shaft, held to its block by its friction clutch; Load adds whatever it drives
local function Rig( Kind, Fields, Load )
    local EntTbl = {
        Adapter = "Engine", Active = true, Firing = true, Cranking = false, StarterClock = 0, Spool = 0, GasGenerator = 0, Regen = 0,
        revLimiterEnabled = true, Throttle = 0, FuelUsage = 0, FuelTanks = {},
        ConsumeFuel = function() return true end,
    }

    for Key, Value in pairs( Kind ) do EntTbl[Key] = Value end
    for Key, Value in pairs( Fields or {} ) do EntTbl[Key] = Value end

    local Entity   = { GetTable = function() return EntTbl end, UpdateOverlay = function() end }
    local System   = Drivetrain.System.New()
    local Shaft    = System:AddBody( Drivetrain.Body.New( 0.35 ) )
    local Block    = System:AddBody( Drivetrain.Body.New( 1e15 ) )
    local Friction = System:AddClutch( Drivetrain.Clutch.New( Shaft, Block, 1, 1, 0 ) )
    local Engine   = Drivetrain.Adapters[EntTbl.Adapter].New( Entity, Shaft, Friction )
    local Output   = Load and Load( System, Shaft )

    System:Finalize()

    local function Step( Ticks )
        for _ = 1, Ticks or 1 do
            Engine:PreStep( DT )
            System:Step( DT )
            Engine:PostStep( DT )
        end
    end

    return Step, EntTbl, Shaft, Output, Engine, Friction
end

-- A wheel geared down tenfold that the engine can't budge
local function Stuck( Omega )
    return function( System, Shaft )
        local Wheel = System:AddBody( Drivetrain.Output.New( IMMOVABLE ) )

        Wheel.Omega = Omega or 0

        System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 0.1, 1, 1e5 ) )

        return Wheel
    end
end

-- A wheel geared down tenfold with a steady torque on it, as a slope would put there
local function Pushed( Torque )
    return function( System, Shaft )
        local Wheel = System:AddBody( Drivetrain.Output.New( 20 ) )

        Wheel.Load = Torque

        System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 0.1, 1, 1e5 ) )

        return Wheel
    end
end

local function Battery( Amount )
    return {
        Amount = Amount, Capacity = 1,
        IsValid   = function() return true end,
        Consume   = function( self, Used ) self.Amount = math.Clamp( self.Amount - Used, 0, self.Capacity ) end,
        CanCharge = function( self ) return self.Amount < self.Capacity end,
    }
end

-- A free flywheel on the shaft, as a vehicle rolling on the motor would be
local function Flywheel( System, Shaft )
    local Wheel = System:AddBody( Drivetrain.Output.New( 5 ) )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 1e5 ) )

    return Wheel
end

-- Drains its battery by what it draws, as the engine entity does
local function DrawsFrom( _, _, EntTbl )
    EntTbl.FuelTank:Consume( Drivetrain.Adapters.Electric.GetFuelRate( EntTbl, EntTbl.FuelThrottle, ( EntTbl.FlyRPM or 0 ) * ACF.RPMToRadS ) * DT )

    return true
end

return {
    groupName = "ACF.Mobility.Drivetrain engine",

    cases = {
        {
            name = "A load dragging a running engine below half its idle stalls it",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON, nil, Stuck() )

                Shaft.Omega = IDLE

                Step( 2 )

                expect( EntTbl.Firing ).to.beFalse()
                expect( EntTbl.Cranking ).to.beFalse()
            end
        },

        {
            name = "The idle governor holds a light load just under idle",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON )

                Shaft.Omega = IDLE
                Shaft:AddSource( Constant( -60 ) ) -- A third of what full throttle makes at idle

                Step( 198 )

                expect( EntTbl.Firing ).to.beTrue()
                expect( Shaft.Omega ).to.beGreaterThan( 0.8 * IDLE )
                expect( Shaft.Omega ).to.beLessThan( IDLE )
            end
        },

        {
            name = "A load heavier than the engine makes at idle stalls it",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON )

                Shaft.Omega = IDLE
                Shaft:AddSource( Constant( -250 ) )

                Step( 132 )

                expect( EntTbl.Firing ).to.beFalse()
            end
        },

        {
            name = "The starter cranks a free engine until it fires, then its governor holds it just under idle against its own losses",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON, { Firing = false, Cranking = true } )

                Step( 66 )

                expect( EntTbl.Firing ).to.beTrue()
                expect( EntTbl.Cranking ).to.beFalse()

                Step( 198 )

                expect( Shaft.Omega ).to.beGreaterThan( 0.95 * IDLE )
                expect( Shaft.Omega ).to.beLessThan( IDLE )
            end
        },

        {
            name = "Left switched on, a stalled engine cranks again after a delay and gives up after a while",
            func = function()
                local Step, EntTbl = Rig( PISTON, { Firing = false }, Stuck() )

                Step( 64 )
                expect( EntTbl.Cranking ).to.beFalse()

                Step( 4 )
                expect( EntTbl.Cranking ).to.beTrue()

                Step( 128 )
                expect( EntTbl.Cranking ).to.beTrue()

                Step( 6 )
                expect( EntTbl.Cranking ).to.beFalse()
                expect( EntTbl.Firing ).to.beFalse()
            end
        },

        {
            name = "Rolling the vehicle in gear fast enough starts it without the starter",
            func = function()
                local Step, EntTbl = Rig( PISTON, { Firing = false }, Stuck( 0.1 * 0.7 * IDLE ) )

                Step( 2 )

                expect( EntTbl.Firing ).to.beTrue()
            end
        },

        {
            name = "Rolling it too slowly turns the engine over without starting it",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON, { Firing = false }, Stuck( 0.1 * 0.4 * IDLE ) )

                Step( 10 )

                expect( EntTbl.Firing ).to.beFalse()
                expect( Shaft.Omega ).to.aboutEqual( 0.4 * IDLE, 1e-6 )
            end
        },

        {
            name = "Switched off and in gear, its friction holds a light push on the wheels",
            func = function()
                local Step, EntTbl, Shaft, Wheel = Rig( PISTON, { Active = false, Firing = false }, Pushed( 200 ) ) -- 20 at the engine, its friction is 30

                Step( 66 )

                expect( EntTbl.Firing ).to.beFalse()
                expect( Wheel.Omega ).to.aboutEqual( 0, 1e-9 )
                expect( Shaft.Omega ).to.aboutEqual( 0, 1e-9 )
            end
        },

        {
            name = "Switched off and in gear, a harder push turns the wheels and the engine with them",
            func = function()
                local Step, EntTbl, Shaft, Wheel = Rig( PISTON, { Active = false, Firing = false }, Pushed( 600 ) )

                Step( 66 )

                expect( EntTbl.Firing ).to.beFalse()
                expect( Wheel.Omega ).to.beGreaterThan( 0 )
                expect( Shaft.Omega ).to.aboutEqual( Wheel.Omega / 0.1, 1e-6 )
            end
        },

        {
            name = "At full throttle it hands over its whole torque curve, as the curve is already net of its losses",
            func = function()
                local Step, _, Shaft, _, Engine, Friction = Rig( PISTON, { Throttle = 1, LossLinear = 50, LossQuadratic = 50 } )

                Shaft.Omega = 0.5 * LIMIT

                Step()

                local Omega = Shaft.Omega
                local Curve = ACF.GetTorque( PISTON.TorqueCurve, math.Remap( Omega, IDLE, LIMIT, 0, 1 ) )

                expect( Engine:GetTorque( Omega ) ).to.aboutEqual( 300 * Curve, 1e-9 )
                expect( Friction.Capacity ).to.equal( 0 )
            end
        },

        {
            name = "With its rev limiter on, a free engine at full throttle holds at its redline",
            func = function()
                local Step, _, Shaft = Rig( PISTON, { Throttle = 1 } )

                Shaft.Omega = 0.9 * LIMIT

                Step( 132 )

                expect( Shaft.Omega ).to.beGreaterThan( 0.97 * LIMIT )
                expect( Shaft.Omega ).to.beLessThan( 1.02 * LIMIT )
            end
        },

        {
            name = "With its rev limiter off, it revs past its redline until its torque runs out",
            func = function()
                local Step, _, Shaft = Rig( PISTON, { Throttle = 1, revLimiterEnabled = false } )

                Shaft.Omega = 0.9 * LIMIT

                Step( 660 )

                expect( Shaft.Omega ).to.beGreaterThan( 1.2 * LIMIT )
                expect( Shaft.Omega ).to.beLessThan( 1.25 * LIMIT + 1e-6 )
            end
        },

        {
            name = "With its rev limiter off, the idle governor still holds a light load just under idle",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON, { revLimiterEnabled = false } )

                Shaft.Omega = IDLE
                Shaft:AddSource( Constant( -60 ) )

                Step( 198 )

                expect( EntTbl.Firing ).to.beTrue()
                expect( Shaft.Omega ).to.beGreaterThan( 0.8 * IDLE )
                expect( Shaft.Omega ).to.beLessThan( IDLE )
            end
        },

        {
            name = "Off the throttle it brakes by its losses, growing with speed and against either direction",
            func = function()
                local Step, _, _, _, Engine, Friction = Rig( PISTON, { Active = false, Firing = false, LossLinear = 40, LossQuadratic = 20 } )

                Step()

                expect( Friction.Capacity ).to.equal( 30 )
                expect( Engine:GetTorque( 0.5 * LIMIT ) ).to.aboutEqual( -( 40 * 0.5 + 20 * 0.25 ), 1e-9 )
                expect( Engine:GetTorque( -0.5 * LIMIT ) ).to.aboutEqual( 40 * 0.5 + 20 * 0.25, 1e-9 )
            end
        },

        {
            name = "A turbine held still by its load never stalls, and creeps on its idle fuel flow",
            func = function()
                local Step, EntTbl, Shaft, _, Engine = Rig( TURBINE, { GasGenerator = 0.1 }, Stuck() )

                Step( 660 )

                expect( EntTbl.Firing ).to.beTrue()
                expect( Shaft.Omega ).to.aboutEqual( 0, 1e-6 )
                expect( Engine.Combustion ).to.aboutEqual( 0.1 * 300, 0.5 )
            end
        },

        {
            name = "Its gas generator lags a throttle step, reaching two thirds of it after its time constant",
            func = function()
                local Step, _, _, _, Engine = Rig( TURBINE, { Throttle = 1, GasGenerator = 0 }, Stuck() )

                Step( 132 )

                expect( Engine.Combustion ).to.aboutEqual( 0.633 * 300, 3 )
            end
        },

        {
            name = "Switched on cold, a turbine spools up for twelve seconds before it runs",
            func = function()
                local Step, EntTbl = Rig( TURBINE, { Spool = 0, Firing = false, Cranking = true, Throttle = 1 }, Stuck() )

                Step( 396 )

                expect( EntTbl.Spool ).to.aboutEqual( 0.5, 1e-9 )
                expect( EntTbl.Cranking ).to.beTrue()
                expect( EntTbl.Firing ).to.beFalse()

                Step( 397 ) -- One more, as the summed steps land a rounding short of whole

                expect( EntTbl.Firing ).to.beTrue()
                expect( EntTbl.Cranking ).to.beFalse()
            end
        },

        {
            name = "Switched off, a turbine's torque fades within seconds while its spool runs down slowly",
            func = function()
                local Step, EntTbl, _, _, Engine = Rig( TURBINE, { Active = false, Throttle = 1 }, Stuck() )

                Step()

                expect( Engine.Combustion ).to.beGreaterThan( 0.9 * 300 )

                Step( 197 )

                expect( Engine.Combustion ).to.beLessThan( 0.06 * 300 )
                expect( EntTbl.Spool ).to.aboutEqual( 0.7, 0.01 )
            end
        },

        {
            name = "An electric motor fires at once and never stalls",
            func = function()
                local Step, EntTbl, Shaft = Rig( ELECTRIC, { Firing = false }, Stuck() )

                Shaft.Omega = 50

                Step( 66 )

                expect( EntTbl.Firing ).to.beTrue()
                expect( EntTbl.Cranking ).to.beFalse()
            end
        },

        {
            name = "Negative throttle drives an electric motor backwards",
            func = function()
                local Step, _, Shaft = Rig( ELECTRIC, { Throttle = -1 } )

                Step( 33 )

                expect( Shaft.Omega ).to.beLessThan( 0 )
            end
        },

        {
            name = "Off the throttle an electric motor coasts",
            func = function()
                local Step, _, Shaft = Rig( ELECTRIC )

                Shaft.Omega = 300

                Step( 66 )

                expect( Shaft.Omega ).to.aboutEqual( 300, 1e-9 )
            end
        },

        {
            name = "Regen brakes an electric motor and charges its battery",
            func = function()
                local Tank           = Battery( 0.5 )
                local Step, _, Shaft = Rig( ELECTRIC, { Regen = 1, FuelTank = Tank } )

                Shaft.Omega = 300

                Step( 5 )

                expect( Shaft.Omega ).to.beLessThan( 300 )
                expect( Tank.Amount ).to.beGreaterThan( 0.5 )
            end
        },

        {
            name = "Its bearings slow a coasting motor but charge nothing",
            func = function()
                local Tank           = Battery( 0.5 )
                local Step, _, Shaft = Rig( ELECTRIC, { LossConstant = 5, FuelTank = Tank } )

                Shaft.Omega = 300

                Step( 5 )

                expect( Shaft.Omega ).to.beLessThan( 300 )
                expect( Tank.Amount ).to.equal( 0.5 )
            end
        },

        {
            name = "A full battery takes nothing back, so the motor coasts",
            func = function()
                local Tank           = Battery( 1 )
                local Step, _, Shaft = Rig( ELECTRIC, { Regen = 1, FuelTank = Tank } )

                Shaft.Omega = 300

                Step( 5 )

                expect( Shaft.Omega ).to.aboutEqual( 300, 1e-9 )
            end
        },

        {
            name = "A piston engine burns in proportion to its throttle, and nothing with it cut",
            func = function()
                local Adapter = Drivetrain.Adapters.Engine
                local EntTbl  = table.Copy( PISTON )
                local Omega   = 3000 * ACF.RPMToRadS

                EntTbl.FuelUse = 1

                expect( Adapter.GetFuelRate( EntTbl, 0.5, Omega ) ).to.aboutEqual( 0.5 * Adapter.GetFuelRate( EntTbl, 1, Omega ), 1e-9 )
                expect( Adapter.GetFuelRate( EntTbl, 0, Omega ) ).to.equal( 0 )
            end
        },

        {
            name = "Flat out at peak power, a piston engine burns its rated consumption on what reaches the shaft",
            func = function()
                local Adapter = Drivetrain.Adapters.Engine
                local EntTbl  = table.Copy( PISTON )
                local RPM     = 4500
                local Brake   = 300 * ACF.GetTorque( PISTON.TorqueCurve, ( RPM - 800 ) / ( 6000 - 800 ) )

                EntTbl.PeakPowerRPM = RPM
                EntTbl.LossLinear   = 20
                EntTbl.FuelUse      = 1
                EntTbl.FuelUse      = Adapter.GetFuelScale( EntTbl )

                expect( Adapter.GetFuelRate( EntTbl, 1, RPM * ACF.RPMToRadS ) ).to.aboutEqual( Brake * RPM, 1e-6 )
            end
        },

        {
            name = "Idling, a piston engine burns just what its own friction takes",
            func = function()
                local Step, EntTbl, Shaft = Rig( PISTON, { FuelUse = 1 } )

                Shaft.Omega = IDLE

                Step( 330 )

                local RPM = Shaft.Omega / ACF.RPMToRadS

                expect( Drivetrain.Adapters.Engine.GetFuelRate( EntTbl, EntTbl.FuelThrottle, Shaft.Omega ) ).to.aboutEqual( 30 * RPM, 0.02 * 30 * RPM )
            end
        },

        {
            name = "A turbine burns on its gas generator, whatever its output turns at",
            func = function()
                local Adapter = Drivetrain.Adapters.Turbine
                local EntTbl  = table.Copy( TURBINE )

                EntTbl.FuelUse   = 1
                EntTbl.PeakPower = 100

                local Full = 100 * 9548.8

                -- Held still by its load
                expect( Adapter.GetFuelRate( EntTbl, 1, 0 ) ).to.aboutEqual( Full, 1e-6 )
                expect( Adapter.GetFuelRate( EntTbl, 1, 12000 * ACF.RPMToRadS ) ).to.aboutEqual( Full, 1e-6 )
                expect( Adapter.GetFuelRate( EntTbl, 0.1, 0 ) ).to.aboutEqual( 0.1 * Full, 1e-6 ) -- Idling
                -- Its gas generator still has to turn
                expect( Adapter.GetFuelRate( EntTbl, 0, 0 ) ).to.aboutEqual( 0.1 * Full, 1e-6 )
            end
        },

        {
            name = "Regen fades out towards a standstill, so it is no parking brake",
            func = function()
                local Step, _, Shaft, _, _, Friction = Rig( ELECTRIC, { Regen = 1, FuelTank = Battery( 0.5 ) } )

                Shaft.Omega = 2

                Step()

                -- Just what recovers its copper loss
                expect( Friction.Capacity ).to.aboutEqual( 2 * 300 * 300 / ( 0.05 * 120e3 ), 1e-9 )

                Shaft.Omega = 0

                Step()

                expect( Friction.Capacity ).to.equal( 0 )
            end
        },

        {
            name = "Holding full torque at a standstill costs a motor its copper loss",
            func = function()
                local EntTbl = table.Copy( ELECTRIC )

                expect( Drivetrain.Adapters.Electric.GetFuelRate( EntTbl, 1, 0 ) ).to.aboutEqual( 1e-3 * 0.05 * 120, 1e-12 )
            end
        },

        {
            name = "Torque against the way a motor turns charges its battery, as an inverter regenerates",
            func = function()
                local EntTbl = table.Copy( ELECTRIC )

                expect( Drivetrain.Adapters.Electric.GetFuelRate( EntTbl, -1, 300 ) ).to.beLessThan( 0 )
            end
        },

        {
            name = "Driving up and regenerating back to a stop leaves the battery lower than it started",
            func = function()
                local Tank                = Battery( 0.5 )
                local Step, EntTbl, Shaft = Rig( ELECTRIC, { FuelTank = Tank, Throttle = 0.5, ConsumeFuel = DrawsFrom }, Flywheel )

                Step( 132 )

                local Driven = Tank.Amount

                EntTbl.Throttle = 0
                EntTbl.Regen    = 1

                Step( 1320 )

                expect( Shaft.Omega ).to.beLessThan( 0.5 )
                expect( Tank.Amount ).to.beGreaterThan( Driven )
                expect( Tank.Amount ).to.beLessThan( 0.5 )
            end
        },

        {
            name = "On a flat battery a motor has no power, but regenerating charges it again",
            func = function()
                local Tank                    = Battery( 0 )
                local Step, _, Shaft, _, Motor = Rig( ELECTRIC, { Discharged = true, Throttle = 1, Regen = 1, FuelTank = Tank } )

                Shaft.Omega = 300

                Step( 5 )

                expect( Motor.Combustion ).to.equal( 0 )
                expect( Shaft.Omega ).to.beLessThan( 300 )
                expect( Tank.Amount ).to.beGreaterThan( 0 )
            end
        },

        {
            name = "Once its battery is full, regen charges another one linked to it",
            func = function()
                local Full, Empty    = Battery( 1 ), Battery( 0 )
                local Step, _, Shaft = Rig( ELECTRIC, { Regen = 1, FuelTank = Full, FuelTanks = { [Full] = true, [Empty] = true } } )

                Shaft.Omega = 300

                Step( 5 )

                expect( Full.Amount ).to.equal( 1 )
                expect( Empty.Amount ).to.beGreaterThan( 0 )
            end
        },
    }
}

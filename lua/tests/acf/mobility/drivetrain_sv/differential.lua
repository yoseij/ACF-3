local Drivetrain = ACF.Mobility.Drivetrain

local DT = 1 / 66

-- An engine shaft through a gearbox into a differential, each side shaft driving one heavy wheel behind its
-- own clutch
local function Axle( LockerCapacity, RightCapacity )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 7.1 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local Left   = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local Right  = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local A      = System:AddBody( Drivetrain.Output.New( 2000 ) )
    local B      = System:AddBody( Drivetrain.Output.New( 2000 ) )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 1, 1, 1e9 ) )
    System:AddClutch( Drivetrain.Differential.New( Box, Left, Right, 0.25, math.huge ) )

    local Locker = System:AddClutch( Drivetrain.Clutch.New( Left, Right, 1, 1, LockerCapacity or 0 ) )

    System:AddClutch( Drivetrain.Clutch.New( Left, A, 1, 0.3, 1e9 ) )
    System:AddClutch( Drivetrain.Clutch.New( Right, B, 1, 0.3, RightCapacity or 1e9 ) )

    Shaft.Omega = 200
    Box.Omega   = 200
    Left.Omega  = 40
    Right.Omega = 40
    A.Omega     = 40
    B.Omega     = 40
    A.Load      = -20000 -- Held back hard, as by a steep slope or deep mud; B rolls free

    System:Finalize()

    return System, A, B, Locker
end

local function Torque( Wheel ) return Wheel.AppliedImpulse / DT end

-- A differential feeding two immovable props, one clutch engaged four times harder than the other
local function Effectors( LockerCapacity )
    local System  = Drivetrain.System.New()
    local Shaft   = System:AddBody( Drivetrain.Body.New( 2.5 ) )
    local Carrier = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Left    = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Right   = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local A       = System:AddBody( Drivetrain.Output.New( 1e12 ) )
    local B       = System:AddBody( Drivetrain.Output.New( 1e12 ) )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Carrier, 0.01, 1, 4920 ) )
    System:AddClutch( Drivetrain.Differential.New( Carrier, Left, Right, 0.01, math.huge ) )
    System:AddClutch( Drivetrain.Clutch.New( Left, Right, 1, 1, LockerCapacity ) )

    local Strong = System:AddClutch( Drivetrain.Clutch.New( Left, A, 1, 0.09, 2000 ) )
    local Weak   = System:AddClutch( Drivetrain.Clutch.New( Right, B, -1, 0.09, 500 ) )

    Shaft.Omega = 800

    System:Finalize()
    System:Step( DT )

    return Strong, Weak
end

return {
    groupName = "ACF.Mobility.Drivetrain differential",

    cases = {
        {
            name = "An open differential pushes both sides equally and lets them turn apart",
            func = function()
                local System, A, B = Axle()

                System:Step( DT )

                expect( Torque( A ) ).to.beGreaterThan( 0 )
                expect( Torque( A ) ).to.aboutEqual( Torque( B ), Torque( A ) * 1e-3 )
                expect( B.Omega - A.Omega ).to.beGreaterThan( 0.1 ) -- What A's load takes off it in one tick
            end
        },

        {
            name = "With one side disengaged, an open differential drives neither",
            func = function()
                local Engaged, Driven = Axle()
                local System, A       = Axle( 0, 0 )

                Engaged:Step( DT )
                System:Step( DT )

                -- All that is left is what spins up the free side's light shaft
                expect( math.abs( Torque( A ) ) ).to.beLessThan( Torque( Driven ) * 0.01 )
            end
        },

        {
            name = "A limited slip moves no more than its limit to the slower side",
            func = function()
                local System, A, B, Locker = Axle( 500 )

                System:Step( DT )

                expect( Locker.Saturated ).to.beTrue()
                expect( Torque( A ) - Torque( B ) ).to.aboutEqual( 0.6 * 500, 0.6 * 500 * 0.01 )
            end
        },

        {
            name = "Locked, both sides turn together",
            func = function()
                local System, A, B = Axle( math.huge )

                System:Step( DT )

                expect( A.Omega - B.Omega ).to.aboutEqual( 0, 1e-6 )
            end
        },

        {
            name = "Locked while its limited slip slips, it locks the sides together the next tick, with either solver",
            func = function()
                for _, Dense in ipairs( { false, true } ) do
                    local System, A, B, Locker = Axle( 500 )

                    if Dense then System.Solver = Drivetrain.Solver.New( System.Bodies, System.Clutches ) end

                    System:Step( DT )

                    expect( Locker.Saturated ).to.beTrue()

                    Locker.Capacity = math.huge

                    System:Step( DT )

                    expect( A.Omega - B.Omega ).to.aboutEqual( 0, 1e-6 ) -- Fails on NaN too
                end
            end
        },

        {
            name = "Open, slipping or locked, a differential's sides share their loads, as only its locker splits their torque",
            func = function()
                local Open, OpenA, OpenB = Axle()
                local Slipping, SlippingA, SlippingB, Locker = Axle( 500 )
                local Locked, LockedA, LockedB = Axle( math.huge )

                Open:Step( DT )
                Slipping:Step( DT )
                Locked:Step( DT )

                expect( Locker.Saturated ).to.beTrue()

                for _, Wheel in ipairs( { OpenA, OpenB, SlippingA, SlippingB, LockedA, LockedB } ) do Wheel.Predicted = true end

                OpenA.Load, OpenB.Load         = 500, -500
                SlippingA.Load, SlippingB.Load = -900, 300
                LockedA.Load, LockedB.Load     = 500, -500

                Open.LoadShare:Apply()
                Slipping.LoadShare:Apply()
                Locked.LoadShare:Apply()

                expect( OpenA.Load ).to.aboutEqual( 0, 1e-3 )
                expect( OpenB.Load ).to.aboutEqual( 0, 1e-3 )
                expect( SlippingA.Load ).to.aboutEqual( -300, 1e-3 )
                expect( SlippingB.Load ).to.aboutEqual( -300, 1e-3 )
                expect( LockedA.Load ).to.aboutEqual( 0, 1e-3 )
                expect( LockedB.Load ).to.aboutEqual( 0, 1e-3 )
            end
        },


        {
            name = "Immovable props behind a locked differential each take their full engaged capacity",
            func = function()
                local Strong, Weak = Effectors( math.huge )

                expect( math.abs( Strong.Impulse ) ).to.aboutEqual( Strong.MaxImpulse, Strong.MaxImpulse * 1e-9 )
                expect( math.abs( Weak.Impulse ) ).to.aboutEqual( Weak.MaxImpulse, Weak.MaxImpulse * 1e-9 )
            end
        },

        {
            name = "Behind an open differential, the weaker immovable prop sets what both take",
            func = function()
                local Strong, Weak = Effectors( 0 )

                expect( math.abs( Weak.Impulse ) ).to.aboutEqual( Weak.MaxImpulse, Weak.MaxImpulse * 1e-9 )
                expect( math.abs( Strong.Impulse ) ).to.aboutEqual( math.abs( Weak.Impulse ), math.abs( Weak.Impulse ) * 1e-4 ) -- Less what the slipping side shaft's own inertia takes
            end
        },

        {
            name = "Locked between props that disagree, a side slips and the locker is never left to",
            func = function()
                local System  = Drivetrain.System.New()
                local Shaft   = System:AddBody( Drivetrain.Body.New( 2.5 ) )
                local Carrier = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local Left    = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local Right   = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local A       = System:AddBody( Drivetrain.Output.New( 1e12 ) )
                local B       = System:AddBody( Drivetrain.Output.New( 1e12 ) )

                -- Sides first, so only the solver's own ordering keeps the locker from being the clutch left
                -- to slip
                System:AddClutch( Drivetrain.Clutch.New( Left, A, 1, 0.09, 2000 ) )
                System:AddClutch( Drivetrain.Clutch.New( Right, B, -1, 0.09, 2000 ) )
                System:AddClutch( Drivetrain.Clutch.New( Shaft, Carrier, 0.01, 1, 4920 ) )
                System:AddClutch( Drivetrain.Differential.New( Carrier, Left, Right, 0.01, math.huge ) )

                local Locker = System:AddClutch( Drivetrain.Clutch.New( Left, Right, 1, 1, math.huge ) )

                Shaft.Omega = 800
                B.Omega     = 1e-3

                System:Finalize()
                System:Step( DT )

                expect( Locker.Saturated ).to.beFalse()

                for _, Body in ipairs( System.Bodies ) do
                    expect( Body.Omega == Body.Omega and math.abs( Body.Omega ) < math.huge ).to.beTrue()
                end
            end
        },
    }
}

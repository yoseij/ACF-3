local Drivetrain = ACF.Mobility.Drivetrain

local DT = 1 / 66

-- One light gearbox driving two heavy wheels, locked on a first step so the next one knows they held together
local function Axle( RatioB, CapacityA )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 7.1 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local A      = System:AddBody( Drivetrain.Output.New( 2000 ) )
    local B      = System:AddBody( Drivetrain.Output.New( 2000 ) )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 1, 1, 1e9 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, A, 0.25, 0.3, CapacityA or 1e9 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, B, RatioB or 0.25, 0.3, 1e9 ) )

    Shaft.Omega = 200
    Box.Omega   = 200
    A.Omega     = CapacityA and 0 or 50 -- Stopped, so a weak clutch has to slip to catch it up
    B.Omega     = 50 * ( RatioB or 0.25 ) / 0.25

    System:Finalize()
    System:Step( DT )

    A.Predicted = true
    B.Predicted = true

    return System, A, B
end

local function Share( System, Ticks )
    for _ = 1, Ticks do System.LoadShare:Apply() end
end

return {
    groupName = "ACF.Mobility.Drivetrain load sharing",

    cases = {
        {
            name = "Wheels locked together stop pushing against each other",
            func = function()
                local System, A, B = Axle()

                A.Load = 500
                B.Load = -500

                Share( System, 60 )

                expect( A.Load ).to.aboutEqual( 0, 1e-3 )
                expect( B.Load ).to.aboutEqual( 0, 1e-3 )
            end
        },

        {
            name = "A wheel pushing against the rest gives it up, and the group keeps its total",
            func = function()
                local System, A, B = Axle()

                A.Load = -900
                B.Load = 300

                Share( System, 60 )

                expect( A.Load ).to.aboutEqual( -300, 1e-3 )
                expect( B.Load ).to.aboutEqual( -300, 1e-3 )
            end
        },

        {
            name = "Wheels resisting by different amounts share the total, as only the total shows while they turn together",
            func = function()
                local System, A, B = Axle()

                A.Load = -2460
                B.Load = -840

                Share( System, 1 )

                expect( A.Load ).to.aboutEqual( -1650, 1e-3 )
                expect( B.Load ).to.aboutEqual( -1650, 1e-3 )
            end
        },

        {
            name = "A wheel geared to turn faster takes more of the load, so the loads alone turn them together",
            func = function()
                local System, A, B = Axle( 0.5 )

                A.Load = -1000
                B.Load = 0

                Share( System, 60 )

                -- The total on the box is kept, and each load over its inertia follows its ratio
                expect( A.Load ).to.aboutEqual( -200, 1e-3 )
                expect( B.Load ).to.aboutEqual( -400, 1e-3 )
            end
        },

        {
            name = "A wheel turning the other way round is shared in its own frame",
            func = function()
                local System, A, B = Axle( -0.25 )

                A.Load = 500
                B.Load = 500 -- Backwards for B, so the two fight

                Share( System, 60 )

                expect( A.Load ).to.aboutEqual( 0, 1e-3 )
                expect( B.Load ).to.aboutEqual( 0, 1e-3 )

                A.Load = 300
                B.Load = -300 -- Both pushing the same way

                Share( System, 60 )

                expect( A.Load ).to.aboutEqual( 300, 1e-3 )
                expect( B.Load ).to.aboutEqual( -300, 1e-3 )
            end
        },

        {
            name = "A slipping wheel keeps the load it learned",
            func = function()
                local System, A, B = Axle( nil, 1 )

                expect( System.Clutches[2].Saturated ).to.beTrue()

                A.Load = 500
                B.Load = -500

                Share( System, 60 )

                expect( A.Load ).to.equal( 500 )
                expect( B.Load ).to.equal( -500 )
            end
        },
        {
            name = "A clutch to a body outside the shared ones is left out instead of failing",
            func = function()
                local A, B   = Drivetrain.Output.New( 10 ), Drivetrain.Output.New( 10 )
                local Locked = Drivetrain.Clutch.New( A, B, 1, 1, 1e9 )
                local Stray  = Drivetrain.Clutch.New( A, Drivetrain.Body.New( 1 ), 1, 1, 1e9 )

                Locked.MaxImpulse = 1
                Stray.MaxImpulse  = 1

                local Shared = Drivetrain.LoadShare.New( { A, B }, { Locked, Stray } )

                A.Predicted, B.Predicted = true, true
                A.Load, B.Load           = 30, -10

                Shared:Apply()

                expect( A.Load ).to.aboutEqual( 10, 1e-9 )
                expect( B.Load ).to.aboutEqual( 10, 1e-9 )
            end
        },
    }
}

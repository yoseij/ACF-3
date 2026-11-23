local Drivetrain = ACF.Mobility.Drivetrain

local DT = 1 / 66

-- A shaft through a light gearbox to two wheels that flipping every clutch at once each round goes round in
-- circles on
local function Cycler( Dense )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 0.91 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local A      = System:AddBody( Drivetrain.Body.New( 228.4 ) )
    local B      = System:AddBody( Drivetrain.Body.New( 118.2 ) )

    Shaft.Omega = 311.45
    Box.Omega   = 154.39
    A.Omega     = 165.2
    B.Omega     = 55.4

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, -0.0654, 0.396, 7.83 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, A, 0.5756, 1.114, 4.18 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, B, 0.2913, 0.355, 1984 ) )
    System:Finalize()

    if Dense then System.Solver = Drivetrain.Solver.New( System.Bodies, System.Clutches ) end

    for _, Clutch in ipairs( System.Clutches ) do Clutch:Prepare( DT ) end

    System.Solver:Prepare()
    System.Solver:Solve()

    return System
end

-- Slip each clutch is left with once every impulse is in
local function SlipsAfter( System )
    local Speed = {}

    for _, Body in ipairs( System.Bodies ) do Speed[Body] = Body.Omega end

    for _, Clutch in ipairs( System.Clutches ) do
        Speed[Clutch.Input]  = Speed[Clutch.Input] - Clutch.Ratio * Clutch.Impulse / Clutch.Input.Inertia
        Speed[Clutch.Output] = Speed[Clutch.Output] + Clutch.Gain * Clutch.Impulse / Clutch.Output.Inertia
    end

    local Slips = {}

    for I, Clutch in ipairs( System.Clutches ) do Slips[I] = Clutch.Ratio * Speed[Clutch.Input] - Speed[Clutch.Output] end

    return Slips
end

return {
    groupName = "ACF.Mobility.Drivetrain pivoting",

    cases = {
        {
            name = "Clutches that flipping all at once cycles on still settle, with either solver",
            func = function()
                for _, Dense in ipairs( { false, true } ) do
                    local System  = Cycler( Dense )
                    local Slips   = SlipsAfter( System )
                    local Clutch1 = System.Clutches[1]
                    local Clutch2 = System.Clutches[2]
                    local Clutch3 = System.Clutches[3]

                    -- The two held clutches sit at capacity and still slip the way their impulse pushes
                    -- against
                    expect( Clutch1.Saturated ).to.beTrue()
                    expect( Clutch1.Impulse ).to.aboutEqual( -Clutch1.MaxImpulse, 1e-9 )
                    expect( Slips[1] ).to.beLessThan( 0 )
                    expect( Clutch2.Saturated ).to.beTrue()
                    expect( Clutch2.Impulse ).to.aboutEqual( -Clutch2.MaxImpulse, 1e-9 )
                    expect( Slips[2] ).to.beLessThan( 0 )

                    -- The third locks within its capacity
                    expect( Clutch3.Saturated ).to.beFalse()
                    expect( math.abs( Clutch3.Impulse ) ).to.beLessThan( Clutch3.MaxImpulse )
                    expect( Slips[3] ).to.aboutEqual( 0, 1e-9 )
                end
            end
        },

        {
            name = "Out of rounds, nothing past its capacity is committed and what sits at it is held",
            func = function()
                local Shaft = Drivetrain.Body.New( 1 )
                local Wheel = Drivetrain.Output.New( 20 )

                local Over     = Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 0 )
                local Released = Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 0 )
                local Within   = Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 0 )
                local Fixed    = Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 0 )
                local Clutches = { Over, Released, Within, Fixed }
                local Bound    = { false, false, false, false }

                for _, Clutch in ipairs( Clutches ) do Clutch.MaxImpulse = 2 end

                Over.Impulse     = -5 -- Solved past its capacity in the last round
                Released.Impulse = 2  -- Let go by the last flip, which no round solved again
                Within.Impulse   = 1
                Fixed.Impulse    = 5  -- A limit's, kept as it was fixed
                Fixed.Fixed      = true

                Drivetrain.Pivoting.Project( Clutches, Bound )

                expect( Over.Impulse ).to.equal( -2 )
                expect( Bound[1] ).to.beTrue()
                expect( Released.Impulse ).to.equal( 2 )
                expect( Bound[2] ).to.beTrue()
                expect( Within.Impulse ).to.equal( 1 )
                expect( Bound[3] ).to.beFalse()
                expect( Fixed.Impulse ).to.equal( 5 )
                expect( Bound[4] ).to.beFalse()
            end
        },
    }
}

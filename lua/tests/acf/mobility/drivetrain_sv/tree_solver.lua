local Drivetrain = ACF.Mobility.Drivetrain

local DT     = 1 / 66
local IMMOVABLE = 1e12 -- An output too heavy to move, such as a prop set to a huge inertia

-- Steps one copy with the solver it chose and an identical copy with the dense solver
local function StepBoth( Build )
    local Tree  = Build()
    local Dense = Build()

    Dense.Solver = Drivetrain.Solver.New( Dense.Bodies, Dense.Clutches )

    Tree:Step( DT )
    Dense:Step( DT )

    return Tree, Dense
end

-- Engine shaft -> light gearbox -> two light side boxes -> a heavy wheel each, plus an effector chain to an
-- immovable prop
local function Vehicle( FeedRating )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Left   = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Right  = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local A      = System:AddBody( Drivetrain.Output.New( 15 ) )
    local B      = System:AddBody( Drivetrain.Output.New( 15 ) )
    local Feed   = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Prop   = System:AddBody( Drivetrain.Output.New( IMMOVABLE ) )

    Shaft:AddSource( { GetTorque = function() return 3000 end } )

    local ToBox  = System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 0.2, 1, FeedRating or 6000 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, Left, 0.5, 1, 1e9 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, Right, 0.5, 1, 1e9 ) )
    System:AddClutch( Drivetrain.Clutch.New( Left, A, 0.1, 0.8, 20000 ) )
    System:AddClutch( Drivetrain.Clutch.New( Right, B, 0.1, 0.8, 20000 ) )
    local ToFeed = System:AddClutch( Drivetrain.Clutch.New( Shaft, Feed, 0.01, 1, 4920 ) )
    System:AddClutch( Drivetrain.Clutch.New( Feed, Prop, 0.01, 0.09, 500 ) )
    System:AddLimit( Drivetrain.Limits.LaunchClutch.New( Shaft, { ToBox, ToFeed }, 70 ) )

    Shaft.Omega = 300
    Box.Omega   = 60
    Left.Omega  = 30
    Right.Omega = 30
    A.Omega     = 1
    B.Omega     = 4

    System:Finalize()

    return System, { A = A, B = B, Prop = Prop }
end

-- Engine shaft -> gearbox -> differential with its locker -> a wheel per side shaft; Options: Locker capacity
-- (0 open, huge locked), Heavy for an immovable prop on each side, Soft for compliant wheels, Load to hold
-- the left wheel back
local function Axle( Options )
    local System  = Drivetrain.System.New()
    local Shaft   = System:AddBody( Drivetrain.Body.New( 7.1 ) )
    local Box     = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Left    = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Right   = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local A       = System:AddBody( Drivetrain.Output.New( Options.Heavy and IMMOVABLE or 2000 ) )
    local B       = System:AddBody( Drivetrain.Output.New( Options.Heavy and IMMOVABLE or 1500 ) )

    Shaft:AddSource( { GetTorque = function() return 3000 end } )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 0.5, 1, 6000 ) )
    System:AddClutch( Drivetrain.Differential.New( Box, Left, Right, 0.25, math.huge ) )
    System:AddClutch( Drivetrain.Clutch.New( Left, Right, 1, 1, Options.Locker ) )

    local WheelA = System:AddClutch( Drivetrain.Clutch.New( Left, A, 1, 0.3, Options.Heavy and 2000 or 1e9 ) )
    local WheelB = System:AddClutch( Drivetrain.Clutch.New( Right, B, -1, 0.3, Options.Heavy and 500 or 1e9 ) )

    if Options.Soft then
        WheelA:SetCompliance( 2 * math.pi * 4, 1 )
        WheelB:SetCompliance( 2 * math.pi * 4, 1 )
    end

    Shaft.Omega = 200
    Box.Omega   = 100
    Left.Omega  = 25
    Right.Omega = -25
    A.Omega     = 20
    B.Omega     = -30
    A.Load      = Options.Load or 0

    System:Finalize()

    return System
end

-- Engine shaft -> light gearbox -> wheel, with a brake from a block that never turns; the brake is the
-- block's clutch to the wheel, so its block hangs below the wheel as an input. Options: Brake (N·m), Load on
-- the wheel, Soft for a compliant wheel
local function Braked( Options )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
    local Wheel  = System:AddBody( Drivetrain.Output.New( 20 ) )
    local Block  = System:AddBody( Drivetrain.Body.New( 1e15 ) )

    Shaft:AddSource( { GetTorque = function() return 300 end } )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 0.5, 1, 6000 ) )

    local Drive = System:AddClutch( Drivetrain.Clutch.New( Box, Wheel, 0.2, 1, 1e9 ) )
    local Brake = System:AddClutch( Drivetrain.Brake.New( Block, Wheel ) )

    if Options.Soft then Drive:SetCompliance( 2 * math.pi * 4, 1 ) end

    Brake.Capacity = Options.Brake or 0
    Shaft.Omega    = 100
    Box.Omega      = 50
    Wheel.Omega    = 10
    Wheel.Load     = Options.Load or 0

    System:Finalize()

    return System, Brake, Wheel
end

-- A wheel first, so it is the root and every clutch above it hangs off it by its input
local function Upside( Soft )
    local System = Drivetrain.System.New()
    local Wheel  = System:AddBody( Drivetrain.Output.New( 20 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )

    Shaft:AddSource( { GetTorque = function() return 300 end } )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 0.5, 1, 6000 ) )

    local Drive = System:AddClutch( Drivetrain.Clutch.New( Box, Wheel, -0.2, 0.8, 1e9 ) )

    if Soft then Drive:SetCompliance( 2 * math.pi * 4, 1 ) end

    Shaft.Omega = 100
    Box.Omega   = 50
    Wheel.Omega = -5
    Wheel.Load  = -400

    System:Finalize()

    return System
end

-- Two copies stepped apart, one with the dense solver, compared every tick
local function MatchesDense( Build, Ticks )
    local Tree, Dense = Build(), Build()

    Dense.Solver = Drivetrain.Solver.New( Dense.Bodies, Dense.Clutches )

    expect( getmetatable( Tree.Solver ) ).to.equal( Drivetrain.TreeSolver )

    for _ = 1, Ticks do
        Tree:Step( DT )
        Dense:Step( DT )

        expect( Tree.Solver.UseFallback ).to.beFalse()

        for I, Clutch in ipairs( Dense.Clutches ) do
            local Max   = Clutch.MaxImpulse
            local Scale = math.max( math.abs( Clutch.Impulse ), Max == math.huge and 0 or Max * 1e-6, 1e-9 )

            expect( math.abs( Tree.Clutches[I].Impulse - Clutch.Impulse ) / Scale ).to.beLessThan( 1e-6 )
        end
    end

    return Tree
end

return {
    groupName = "ACF.Mobility.Drivetrain tree solver",

    cases = {
        {
            name = "A drivetrain without loops is solved as a tree",
            func = function()
                local System = Vehicle()

                expect( getmetatable( System.Solver ) ).to.equal( Drivetrain.TreeSolver )
            end
        },

        {
            name = "Two paths to one wheel, or a differential without its locker, are left to the dense solver",
            func = function()
                local Bodies = {
                    Drivetrain.Body.New( 1 ),
                    Drivetrain.Body.New( 1e-4 ),
                    Drivetrain.Body.New( 1e-4 ),
                    Drivetrain.Output.New( 20 ),
                }

                local Loop = {
                    Drivetrain.Clutch.New( Bodies[1], Bodies[2], 1, 1, 100 ),
                    Drivetrain.Clutch.New( Bodies[1], Bodies[3], 1, 1, 100 ),
                    Drivetrain.Clutch.New( Bodies[2], Bodies[4], 1, 1, 100 ),
                    Drivetrain.Clutch.New( Bodies[3], Bodies[4], 1, 1, 100 ),
                }

                expect( Drivetrain.TreeSolver.New( Bodies, Loop ) ).to.equal( nil )

                local Carrier = { Drivetrain.Differential.New( Bodies[1], Bodies[2], Bodies[3], 1, 100 ) }

                expect( Drivetrain.TreeSolver.New( Bodies, Carrier ) ).to.equal( nil )
            end
        },

        {
            name = "A differential with its locker is solved as a tree",
            func = function()
                expect( getmetatable( Axle( { Locker = 0 } ).Solver ) ).to.equal( Drivetrain.TreeSolver )
            end
        },

        {
            name = "Behind a differential it gives the dense solver's impulses, open, limited, locked, immovable or compliant",
            func = function()
                local Cases = {
                    { Locker = 0 }, { Locker = 300 }, { Locker = math.huge },
                    { Locker = 0, Load = -20000 }, { Locker = 300, Load = -20000 }, { Locker = math.huge, Load = -20000 },
                    { Locker = 0, Heavy = true }, { Locker = 300, Heavy = true }, { Locker = math.huge, Heavy = true },
                    { Locker = 300, Soft = true }, { Locker = math.huge, Soft = true, Load = -20000 },
                }

                -- Each solve is replayed through the dense solver from the very same state, as two copies
                -- stepped apart drift by their rounding once a locked differential ties everything together
                for _, Options in ipairs( Cases ) do
                    local System   = Axle( Options )
                    local Tree     = System.Solver
                    local Dense    = Drivetrain.Solver.New( System.Bodies, System.Clutches )
                    local Clutches = System.Clutches
                    local Solve    = Tree.Solve
                    local Start, Held, Ours = {}, {}, {}

                    Dense.BoundSign = Tree.BoundSign

                    Tree.Solve = function( Self )
                        for I, Clutch in ipairs( Clutches ) do Start[I], Held[I] = Clutch.Impulse, Self.Bound[I] end

                        Solve( Self )

                        expect( Self.UseFallback ).to.beFalse()

                        for I, Clutch in ipairs( Clutches ) do
                            Ours[I]         = Clutch.Impulse
                            Clutch.Impulse  = Start[I]
                            Dense.Bound[I]  = Held[I]
                        end

                        Dense:Prepare()

                        for I, Clutch in ipairs( Clutches ) do Clutch.Impulse, Dense.Bound[I] = Start[I], Held[I] end

                        Drivetrain.Solver.Solve( Dense )

                        for I, Clutch in ipairs( Clutches ) do
                            local Max   = Clutch.MaxImpulse
                            local Scale = math.max( math.abs( Clutch.Impulse ), math.abs( Ours[I] ), Max == math.huge and 0 or Max * 1e-6, 1e-9 )

                            expect( math.abs( Ours[I] - Clutch.Impulse ) / Scale ).to.beLessThan( 1e-6 )

                            Clutch.Impulse   = Ours[I]
                            Clutch.Saturated = Self.Bound[I] or Clutch.Fixed
                        end
                    end

                    for _ = 1, 30 do System:Step( DT ) end
                end
            end
        },

        {
            name = "Its impulses are the dense solver's, immovable prop and launch clutch included",
            func = function()
                -- Free, held at its rating, and held by the idle floor
                for _, Rating in ipairs( { 6000, 50, 1e9 } ) do
                    local Tree, Dense = StepBoth( function() return Vehicle( Rating ) end )

                    for I, Clutch in ipairs( Dense.Clutches ) do
                        local Scale = math.max( math.abs( Clutch.Impulse ), Clutch.MaxImpulse * 1e-6, 1e-9 )

                        expect( math.abs( Tree.Clutches[I].Impulse - Clutch.Impulse ) / Scale ).to.beLessThan( 1e-6 )
                    end
                end
            end
        },

        {
            name = "An immovable prop behind light gearboxes slips at its capacity",
            func = function()
                local System = Vehicle()

                System:Step( DT )

                local Clutch = System.Clutches[7]

                expect( Clutch.Saturated ).to.beTrue()
                expect( math.abs( Clutch.Impulse ) ).to.aboutEqual( Clutch.MaxImpulse, Clutch.MaxImpulse * 1e-9 )
            end
        },

        {
            name = "With compliant wheels it still gives the dense solver's impulses, tick after tick",
            func = function()
                for _, Rating in ipairs( { 6000, 50, 1e9 } ) do
                    local function Build()
                        local System = Vehicle( Rating )

                        System.Clutches[4]:SetCompliance( 2 * math.pi * 4, 1 )
                        System.Clutches[5]:SetCompliance( 2 * math.pi * 4, 1 )

                        return System
                    end

                    local Tree, Dense = Build(), Build()

                    Dense.Solver = Drivetrain.Solver.New( Dense.Bodies, Dense.Clutches )

                    for _ = 1, 30 do -- Long enough for the windup to build and bias each lock
                        Tree:Step( DT )
                        Dense:Step( DT )

                        expect( Tree.Solver.UseFallback ).to.beFalse()

                        for I, Clutch in ipairs( Dense.Clutches ) do
                            local Scale = math.max( math.abs( Clutch.Impulse ), Clutch.MaxImpulse * 1e-6, 1e-9 )

                            expect( math.abs( Tree.Clutches[I].Impulse - Clutch.Impulse ) / Scale ).to.beLessThan( 1e-6 )
                        end
                    end
                end
            end
        },

        {
            name = "A brake gives the dense solver's impulses, released, slipping or holding, loaded or compliant",
            func = function()
                local Cases = {
                    { Brake = 0 }, { Brake = 50 }, { Brake = 1e6 },
                    { Brake = 50, Load = -2000 }, { Brake = 1e6, Load = -2000 }, { Brake = 1e6, Soft = true },
                }

                for _, Options in ipairs( Cases ) do
                    MatchesDense( function() return Braked( Options ) end, 30 )
                end
            end
        },

        {
            name = "A brake short of what the drivetrain pushes slips at its capacity, a strong one stops the wheel",
            func = function()
                local Weak, WeakBrake = Braked( { Brake = 50 } )

                Weak:Step( DT )

                expect( WeakBrake.Saturated ).to.beTrue()
                expect( math.abs( WeakBrake.Impulse ) ).to.aboutEqual( WeakBrake.MaxImpulse, WeakBrake.MaxImpulse * 1e-9 )

                local Strong, StrongBrake, Wheel = Braked( { Brake = 1e6 } )

                Strong:Step( DT )

                expect( StrongBrake.Saturated ).to.beFalse()
                expect( Wheel.Omega ).to.aboutEqual( 0, 1e-6 )
            end
        },

        {
            name = "Clutches reached from their output, with a reversing ratio, losses and compliance, give the dense solver's impulses",
            func = function()
                for _, Soft in ipairs( { false, true } ) do
                    MatchesDense( function() return Upside( Soft ) end, 30 )
                end
            end
        },
        {
            name = "A clutch that barely moves its output leaves the tick to the dense solver, which solves it the same",
            func = function()
                local function Faint()
                    local System = Drivetrain.System.New()
                    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
                    local Wheel  = System:AddBody( Drivetrain.Output.New( 20 ) )

                    Shaft:AddSource( { GetTorque = function() return 300 end } )
                    System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 0.5, 1e-12, 1e9 ) )

                    Shaft.Omega = 100

                    System:Finalize()

                    return System
                end

                local Tree, Dense = StepBoth( Faint )

                expect( Tree.Solver.UseFallback ).to.beTrue()
                expect( Tree.Clutches[1].Impulse ).to.aboutEqual( Dense.Clutches[1].Impulse, 1e-12 )
            end
        },
    }
}

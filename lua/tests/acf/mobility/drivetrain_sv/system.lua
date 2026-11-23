local Drivetrain = ACF.Mobility.Drivetrain

local DT     = 1 / 66
local IMMOVABLE = 1e12 -- An output too heavy to move, such as a prop set to a huge inertia

local function Constant( Torque )
    return { GetTorque = function() return Torque end }
end

local function TwoStages( DownstreamCapacity, WheelInertia )
    local System  = Drivetrain.System.New()
    local Shaft   = System:AddBody( Drivetrain.Body.New( 1.4 ) )
    local Gearbox = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local Wheel   = System:AddBody( Drivetrain.Output.New( 20 ) )

    -- Out of order on purpose
    System:AddClutch( Drivetrain.Clutch.New( Gearbox, Wheel, 0.2, 1, DownstreamCapacity ) )
    System:AddClutch( Drivetrain.Clutch.New( Shaft, Gearbox, 0.5, 1, 1e9 ) )

    Shaft.Omega = 100

    if WheelInertia then Wheel.Inertia = WheelInertia end

    System:Finalize()

    return System, Shaft, Gearbox, Wheel
end

-- A transfer case: one light shaft driving two heavy wheels, one of them carrying a load the other does not
local function TransferCase( Rating )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 7.1 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local A      = System:AddBody( Drivetrain.Output.New( 2000 ) )
    local B      = System:AddBody( Drivetrain.Output.New( 2000 ) )
    local Feed   = System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 1, 1, Rating ) )

    System:AddClutch( Drivetrain.Clutch.New( Box, A, 0.25, 0.3, 1e9 ) )
    System:AddClutch( Drivetrain.Clutch.New( Box, B, 0.25, 0.3, 1e9 ) )

    Shaft.Omega   = 200
    Box.Omega     = 200
    A.Omega       = 20
    B.Omega       = 35
    A.Load        = -3000
    System:Finalize()

    return System, Feed, Box, A, B
end

return {
    groupName = "ACF.Mobility.Drivetrain system",

    cases = {
        {
            name = "An engine revs the same at any tick rate",
            func = function()
                local function Rev( Ticks )
                    local System = Drivetrain.System.New()
                    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )

                    Shaft:AddSource( Constant( 100 ) )
                    System:Finalize()

                    for _ = 1, Ticks do System:Step( 1 / Ticks ) end

                    return Shaft.Omega
                end

                expect( Rev( 33 ) ).to.aboutEqual( 100 / 1.4, 1e-9 )
                expect( Rev( 66 ) ).to.aboutEqual( 100 / 1.4, 1e-9 )
            end
        },

        {
            name = "A light gearbox between engine and wheel still locks in one step",
            func = function()
                local System, Shaft, Gearbox, Wheel = TwoStages( 1e9 )

                System:Step( DT )

                expect( 0.5 * Shaft.Omega - Gearbox.Omega ).to.aboutEqual( 0, 1e-6 )
                expect( 0.2 * Gearbox.Omega - Wheel.Omega ).to.aboutEqual( 0, 1e-6 )
            end
        },

        {
            name = "A saturated clutch downstream never throws the engine forward",
            func = function()
                local System, Shaft, Gearbox = TwoStages( 50, IMMOVABLE )

                System:Step( DT )

                expect( Shaft.Omega ).to.beLessThan( 100 )
                expect( 0.5 * Shaft.Omega - Gearbox.Omega ).to.aboutEqual( 0, 1e-6 )
            end
        },

        {
            name = "Two heavy wheels on one light gearbox are locked together in one step",
            func = function()
                local System, _, Box, A, B = TransferCase( 1e9 )

                System:Step( DT )

                expect( A.Omega - B.Omega ).to.aboutEqual( 0, 1e-6 )
                expect( 0.25 * Box.Omega - A.Omega ).to.aboutEqual( 0, 1e-6 )
            end
        },

        {
            name = "An immovable output behind light gearboxes and a big reduction still slips at its capacity",
            func = function()
                local System = Drivetrain.System.New()
                local Shaft  = System:AddBody( Drivetrain.Body.New( 8.2 ) )
                local A      = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local B      = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local Heavy = System:AddBody( Drivetrain.Output.New( IMMOVABLE ) )

                System:AddClutch( Drivetrain.Clutch.New( Shaft, A, 1, 1, 4920 ) )
                System:AddClutch( Drivetrain.Clutch.New( A, B, 0.01, 1, 4920 ) )

                local Clutch = System:AddClutch( Drivetrain.Clutch.New( B, Heavy, 0.01, 0.1, 20 ) )

                Shaft.Omega = 800
                A.Omega     = 800
                B.Omega     = 8
                System:Finalize()
                System:Step( DT )

                expect( Clutch.Saturated ).to.beTrue()
                expect( Clutch.Gain * Clutch.Impulse / DT ).to.aboutEqual( 0.1 * 20 / 0.01, 1e-6 )
            end
        },

        {
            name = "Two paths to one wheel lock it together without either blowing up",
            func = function()
                local System = Drivetrain.System.New()
                local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
                local A      = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local B      = System:AddBody( Drivetrain.Body.New( 1e-4 ) )
                local Wheel  = System:AddBody( Drivetrain.Output.New( 20 ) )

                System:AddClutch( Drivetrain.Clutch.New( Shaft, A, 0.5, 1, 1e9 ) )
                System:AddClutch( Drivetrain.Clutch.New( Shaft, B, 0.5, 1, 1e9 ) )
                System:AddClutch( Drivetrain.Clutch.New( A, Wheel, 0.2, 1, 1e9 ) )
                System:AddClutch( Drivetrain.Clutch.New( B, Wheel, 0.2, 1, 1e9 ) )

                Shaft.Omega = 100
                A.Omega     = 50
                B.Omega     = 50
                System:Finalize()
                System:Step( DT )

                for _, Clutch in ipairs( System.Clutches ) do
                    expect( math.abs( Clutch.Impulse ) ).to.beLessThan( 1e6 )
                    expect( Clutch:GetSlip() ).to.aboutEqual( 0, 1e-6 )
                end
            end
        },

        {
            name = "Locked rigidly to two immovable props turning apart, the shaft takes one's speed instead of blowing up",
            func = function()
                local System = Drivetrain.System.New()
                local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
                local A      = System:AddBody( Drivetrain.Output.New( IMMOVABLE ) )
                local B      = System:AddBody( Drivetrain.Output.New( IMMOVABLE ) )

                System:AddClutch( Drivetrain.Clutch.New( Shaft, A, 1, 1, math.huge ) )
                System:AddClutch( Drivetrain.Clutch.New( Shaft, B, 1, 1, math.huge ) )

                Shaft.Omega = 100
                B.Omega     = 10
                System:Finalize()

                -- A tree, which hands this tick over
                expect( getmetatable( System.Solver ) ).to.equal( Drivetrain.TreeSolver )

                System:Step( DT )

                expect( System.Solver.UseFallback ).to.beTrue()
                expect( math.min( math.abs( Shaft.Omega - A.Omega ), math.abs( Shaft.Omega - B.Omega ) ) ).to.beLessThan( 1e-6 )

                for _, Clutch in ipairs( System.Clutches ) do
                    expect( math.abs( Clutch.Impulse ) ).to.beLessThan( 1e6 )
                end
            end
        },

        {
            name = "A gearbox held back by its rating slips at its input and keeps its outputs locked",
            func = function()
                local System, Feed, Box, A, B = TransferCase( 500 )

                System:Step( DT )

                expect( Feed.Saturated ).to.beTrue()
                expect( Feed:GetDraw() / DT ).to.aboutEqual( 500, 1e-6 )
                expect( A.Omega - B.Omega ).to.aboutEqual( 0, 1e-6 )
                expect( 0.25 * Box.Omega - A.Omega ).to.aboutEqual( 0, 1e-6 )
            end
        },
    }
}

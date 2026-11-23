local Drivetrain = ACF.Mobility.Drivetrain

local DT     = 1 / 66
local IMMOVABLE = 1e12 -- An output too heavy to move, such as a prop set to a huge inertia

local function Pair( EngineOmega, Ratio, Capacity, OutputInertia )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
    local Wheel  = System:AddBody( Drivetrain.Output.New( 20 ) )
    local Clutch = System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, Ratio, 1, Capacity ) )

    Shaft.Omega = EngineOmega

    if OutputInertia then Wheel.Inertia = OutputInertia end

    System:Finalize()

    return System, Shaft, Wheel, Clutch
end

-- A shaft held by friction to a still block, driving a wheel through a lossy clutch; returns the work its
-- friction did
local function Lossy( Efficiency, Torque, Hold, Steps )
    local System   = Drivetrain.System.New()
    local Shaft    = System:AddBody( Drivetrain.Body.New( 1 ) )
    local Wheel    = System:AddBody( Drivetrain.Output.New( 10 ) )
    local Block    = System:AddBody( Drivetrain.Body.New( 1e15 ) )
    local Friction = System:AddClutch( Drivetrain.Clutch.New( Shaft, Block, 1, 1, Hold ) )
    local Clutch   = System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 1e6 ) )
    local Work     = 0

    Clutch.Efficiency = Efficiency
    Shaft.Omega       = 100
    Wheel.Omega       = 100

    Shaft:AddSource( { GetTorque = function() return Torque end } )
    System:Finalize()

    for _ = 1, Steps do
        local Before = Shaft.Omega

        System:Step( DT )

        Work = Work + math.abs( Friction.Impulse ) * 0.5 * ( Before + Shaft.Omega )
    end

    return Shaft, Wheel, Clutch, Work
end

return {
    groupName = "ACF.Mobility.Drivetrain clutch",

    cases = {
        {
            name = "A clutch with capacity to spare locks a free output in one step",
            func = function()
                local System, Shaft, Wheel = Pair( 100, 0.1, 1e9 )

                System:Step( DT )

                expect( 0.1 * Shaft.Omega - Wheel.Omega ).to.aboutEqual( 0, 1e-9 )
                -- Input pays Ratio times what the output gets
                expect( 1.4 * ( 100 - Shaft.Omega ) ).to.aboutEqual( 0.1 * 20 * Wheel.Omega, 1e-9 )
            end
        },

        {
            name = "An immovable output takes exactly the engaged share of the capacity",
            func = function()
                for _, Engagement in ipairs( { 0.25, 0.5, 1 } ) do
                    local System, _, _, Clutch = Pair( 700, 1e-4, Engagement * 119, IMMOVABLE )

                    System:Step( DT )

                    expect( Clutch:GetDraw() / DT ).to.aboutEqual( Engagement * 119, 1e-6 )
                    expect( Clutch.Saturated ).to.beTrue()
                end
            end
        },

        {
            name = "Neutral passes nothing",
            func = function()
                local System, Shaft, Wheel = Pair( 100, 0, 1e9 )

                System:Step( DT )

                expect( Shaft.Omega ).to.equal( 100 )
                expect( Wheel.Omega ).to.equal( 0 )
            end
        },

        {
            name = "A clutch passes no more than may reach its output",
            func = function()
                local System, _, _, Clutch = Pair( 700, 0.5, 1e9, IMMOVABLE )

                Clutch.OutputCapacity = 300

                System:Step( DT )

                expect( Clutch.Gain * Clutch.Impulse / DT ).to.aboutEqual( 300, 1e-6 )
                expect( Clutch.Saturated ).to.beTrue()
            end
        },

        {
            name = "Faster wheels drive the engine up, with no ceiling",
            func = function()
                local System, Shaft, Wheel = Pair( 100, 0.1, 1e9, 5000 )

                Wheel.Omega = 20

                System:Step( DT )

                expect( Shaft.Omega ).to.beGreaterThan( 190 )
                expect( 0.1 * Shaft.Omega - Wheel.Omega ).to.aboutEqual( 0, 1e-9 )
            end
        },

        {
            name = "A compliant clutch winds up and settles back without overshoot",
            func = function()
                local System, Shaft, Wheel, Clutch = Pair( 100, 0.1, 1e9 )

                Clutch:SetCompliance( 2 * math.pi * 4, 1 )

                local First = Clutch:GetSlip()

                System:Step( DT )

                expect( System.Solver.UseFallback ).to.beFalse() -- The tree solver takes compliance itself
                -- Not closed at once, as a rigid lock would
                expect( Clutch:GetSlip() ).to.beGreaterThan( 0.05 * First )

                for _ = 2, 60 do
                    System:Step( DT )

                    -- Critically damped: the slip briefly reverses as it unwinds
                    expect( Clutch.Windup ).to.beGreaterThan( -1e-9 )
                end

                expect( math.abs( Clutch:GetSlip() ) ).to.beLessThan( 0.01 * First )
                expect( Clutch.Windup ).to.aboutEqual( 0, 1e-3 )
                -- Still only moves momentum across
                expect( 1.4 * ( 100 - Shaft.Omega ) ).to.aboutEqual( 0.1 * 20 * Wheel.Omega, 1e-6 )
            end
        },

        {
            name = "A compliant clutch carries a steady load in its windup",
            func = function()
                local System, Shaft, Wheel, Clutch = Pair( 100, 0.1, 1e9 )

                Clutch:SetCompliance( 2 * math.pi * 4, 1 )

                Shaft.Inertia = 1e6 -- Held at speed, so only the spring decides what the wheel gets
                Wheel.Omega   = 10
                Wheel.Load    = -200

                for _ = 1, 200 do System:Step( DT ) end

                expect( Clutch.Gain * Clutch.Impulse / DT ).to.aboutEqual( 200, 0.5 )
                expect( Clutch:GetSlip() ).to.aboutEqual( 0, 1e-3 )
                expect( Clutch.Saturated ).to.beFalse()
            end
        },

        {
            name = "An immovable output stays rigid however compliant its clutch",
            func = function()
                local System, _, _, Clutch = Pair( 700, 1e-4, 119, IMMOVABLE )

                Clutch:SetCompliance( 2 * math.pi * 4, 1 )

                System:Step( DT )

                expect( Clutch.Softness ).to.equal( 0 )
                expect( Clutch:GetDraw() / DT ).to.aboutEqual( 119, 1e-6 )
                expect( Clutch.Saturated ).to.beTrue()
            end
        },

        {
            name = "Driving through its losses, the output gets the efficiency's share of the torque",
            func = function()
                local Shaft, Wheel, Clutch = Lossy( 0.87, 200, 0, 1 )

                expect( Clutch.Backdriven ).to.beFalse()
                expect( Clutch.Gain ).to.aboutEqual( 0.87, 1e-12 )
                expect( 0.87 * 1 * ( 100 + 200 * DT - Shaft.Omega ) ).to.aboutEqual( 10 * ( Wheel.Omega - 100 ), 1e-9 )
            end
        },

        {
            name = "Back-driven, its losses still cost energy instead of handing it back",
            func = function()
                local Shaft, Wheel, Clutch, Work = Lossy( 0.87, 0, 100, 20 )
                local Lost = 0.5 * 1 * ( 100 ^ 2 - Shaft.Omega ^ 2 ) + 0.5 * 10 * ( 100 ^ 2 - Wheel.Omega ^ 2 )

                expect( Clutch.Backdriven ).to.beTrue()
                expect( Clutch.Gain ).to.aboutEqual( 1 / 0.87, 1e-12 )
                expect( Lost ).to.beGreaterThan( Work ) -- The engine's friction plus the gearbox's own losses
            end
        },
        {
            name = "Made rigid again, a clutch keeps none of what its compliance wound up",
            func = function()
                local System, _, _, Clutch = Pair( 100, 0.1, 1e9 )

                Clutch:SetCompliance( 2 * math.pi * 4, 1 )

                for _ = 1, 5 do System:Step( DT ) end

                expect( Clutch.Windup ~= 0 ).to.beTrue()

                Clutch:SetCompliance( 0, 1 )

                expect( Clutch.Softness ).to.equal( 0 )
                expect( Clutch.Bias ).to.equal( 0 )
                expect( Clutch.Windup ).to.equal( 0 )

                System:Step( DT )

                expect( Clutch:GetSlip() ).to.aboutEqual( 0, 1e-6 )
            end
        },
    }
}

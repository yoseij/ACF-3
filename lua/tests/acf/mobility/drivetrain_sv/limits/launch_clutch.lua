local Drivetrain = ACF.Mobility.Drivetrain

local DT     = 1 / 66
local BITE   = 78
local IMMOVABLE = 1e12 -- An output too heavy to move, such as a prop set to a huge inertia

local function Loaded( EngineOmega, Torque, LoadOmega, Engines )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
    local Load   = System:AddBody( Drivetrain.Output.New( 10 ) )
    local Clutch = System:AddClutch( Drivetrain.Clutch.New( Shaft, Load, 0.1, 1, 1e5 ) )
    local Limits = Drivetrain.Limits.LaunchClutch

    Shaft:AddSource( { GetTorque = function() return Torque end } )

    Shaft.Omega  = EngineOmega
    Load.Inertia = IMMOVABLE
    Load.Omega   = LoadOmega

    System:AddLimit( Engines and Limits.ForEngines( Shaft, { Clutch }, Engines ) or Limits.New( Shaft, { Clutch }, BITE ) )
    System:Finalize()

    return System, Shaft, Clutch
end

return {
    groupName = "ACF.Mobility.Drivetrain launch clutch",

    cases = {
        {
            name = "A stuck load cannot pull a running engine below the bite speed",
            func = function()
                local System, Shaft, Clutch = Loaded( 80, 50, 0 )

                System:Step( DT )

                expect( Shaft.Omega ).to.aboutEqual( BITE, 1e-9 )
                -- Only what spun above the bite speed
                expect( Clutch:GetDraw() ).to.aboutEqual( 1.4 * ( 80 - BITE ) + 50 * DT, 1e-9 )
            end
        },

        {
            name = "The wheels may still spin the engine up",
            func = function()
                local System, Shaft = Loaded( 80, 0, 20 )

                System:Step( DT )

                expect( Shaft.Omega ).to.beGreaterThan( 80 )
            end
        },

        {
            name = "Turning backwards, a stuck load cannot pull it below the bite speed either",
            func = function()
                local System, Shaft, Clutch = Loaded( -80, -50, 0 )

                System:Step( DT )

                expect( Shaft.Omega ).to.aboutEqual( -BITE, 1e-9 )
                expect( Clutch:GetDraw() ).to.aboutEqual( -1.4 * ( 80 - BITE ) - 50 * DT, 1e-9 )
            end
        },

        {
            name = "Turning backwards, the wheels may still spin it faster, which is how it brakes them",
            func = function()
                local System, Shaft = Loaded( -100, 0, -20 )

                System:Step( DT )

                -- Locked to the load, as the wheels may always spin it up
                expect( Shaft.Omega ).to.aboutEqual( -200, 1e-6 )
            end
        },

        {
            name = "With no engine switched on that can stall, it holds nothing back",
            func = function()
                local System, Shaft = Loaded( 50, 50, 0, { { Active = false, IdleRPM = 800 }, { Active = true, IdleRPM = 0 } } )

                System:Step( DT )

                expect( Shaft.Omega ).to.aboutEqual( 0, 1e-6 ) -- Locked to the stuck load
            end
        },

        {
            name = "An engine switched on bites above its idle",
            func = function()
                local System, Shaft = Loaded( 200, 0, 0, { { Active = true, IdleRPM = 800 }, { Active = true, IdleRPM = 0 } } )

                System:Step( DT )

                expect( Shaft.Omega ).to.aboutEqual( 1.5 * 800 * ACF.RPMToRadS, 1e-9 )
            end
        },

        {
            name = "Below the bite speed, a stuck load gets nothing, solved in one go",
            func = function()
                local System, Shaft, Clutch = Loaded( 50, 50, 0 )
                local Solver = System.Solver
                local Solve  = Solver.Solve
                local Solves = 0

                Solver.Solve = function( Self ) Solves = Solves + 1 return Solve( Self ) end

                System:Step( DT )

                expect( Solves ).to.equal( 1 )
                expect( Clutch.Impulse ).to.equal( 0 )
                expect( Clutch.Saturated ).to.beTrue()
                expect( Shaft.Omega ).to.aboutEqual( 50 + 50 * DT / 1.4, 1e-9 ) -- Only its own torque
            end
        },

        {
            name = "Below the bite speed, the wheels may still spin it up",
            func = function()
                local System, Shaft = Loaded( 50, 0, 20 )

                System:Step( DT )

                -- Locked to the load, as the wheels may always spin it up
                expect( Shaft.Omega ).to.aboutEqual( 200, 1e-6 )
            end
        },
    }
}

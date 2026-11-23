local Drivetrain = ACF.Mobility.Drivetrain
local Limits     = Drivetrain.Limits

local DT = 1 / 66

-- A limit on one body whose clutches have already drawn these impulses
local function Drawing( ... )
    local Body     = Drivetrain.Body.New( 1 )
    local Clutches = {}

    for I, Impulse in ipairs( { ... } ) do
        local Clutch = Drivetrain.Clutch.New( Body, Drivetrain.Body.New( 1 ), 1, 1, 1e9 )

        Clutch.Impulse = Impulse
        Clutches[I]    = Clutch
    end

    return Limits.Base.New( Body, Clutches ), Clutches
end

-- A still shaft back-driven through a lossy clutch by a fast heavy wheel, what it draws held by a negative limit;
-- Preset solves the clutch the right way round from the start, rather than turning it after the first solve
local function BackDriven( Preset )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1 ) )
    local Wheel  = System:AddBody( Drivetrain.Output.New( 50 ) )
    local Clutch = System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 1, 1, 1e6 ) )
    local Limit  = Limits.Base.New( Shaft, { Clutch } )

    Clutch.Efficiency = 0.8
    Clutch.Backdriven = Preset
    Wheel.Omega       = 100
    Limit.Lower       = -0.3

    System:AddLimit( Limit )
    System:Finalize()
    System:Step( DT )

    return Clutch, Wheel
end

return {
    groupName = "ACF.Mobility.Drivetrain limits",

    cases = {
        {
            name = "Drawn past a negative limit, every clutch drawing that way is scaled back alike and held there",
            func = function()
                local Limit, Clutches = Drawing( -6, -4, 2 )

                Limit.Lower = -5

                expect( Limit:Restrict() ).to.beTrue()
                expect( Clutches[1].Impulse ).to.aboutEqual( -4.2, 1e-12 )
                expect( Clutches[2].Impulse ).to.aboutEqual( -2.8, 1e-12 )
                expect( Clutches[3].Impulse ).to.equal( 2 )
                expect( Clutches[1].Fixed ).to.beTrue()
                expect( Clutches[3].Fixed ).to.beFalse()
            end
        },

        {
            name = "Within its limits it holds nothing back",
            func = function()
                local Limit, Clutches = Drawing( -3, 1 )

                Limit.Lower = -5

                expect( Limit:Restrict() ).to.beFalse()
                expect( Clutches[1].Impulse ).to.equal( -3 )
                expect( Clutches[1].Fixed ).to.beFalse()
            end
        },

        {
            name = "Turned after its first solve, a lossy clutch held by a limit lands where solving it the right way round does",
            func = function()
                local Turned, TurnedWheel = BackDriven( false )
                local Right, RightWheel   = BackDriven( true )

                expect( Turned.Backdriven ).to.beTrue()
                expect( Turned:GetDraw() ).to.aboutEqual( -0.3, 1e-9 )
                expect( Turned.Impulse ).to.aboutEqual( Right.Impulse, 1e-12 )
                expect( TurnedWheel.Omega ).to.aboutEqual( RightWheel.Omega, 1e-9 )
            end
        },
    }
}

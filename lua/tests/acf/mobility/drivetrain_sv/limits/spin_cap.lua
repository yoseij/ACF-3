local Drivetrain = ACF.Mobility.Drivetrain

local DT = 1 / 66

-- An engine driving one wheel through a 10:1 reduction, the wheel allowed up to Most
local function Driven( EngineOmega, Torque, WheelOmega, Most )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 1.4 ) )
    local Wheel  = System:AddBody( Drivetrain.Output.New( 10 ) )
    local Clutch = System:AddClutch( Drivetrain.Clutch.New( Shaft, Wheel, 0.1, 1, 1e5 ) )
    local Cap    = System:AddLimit( Drivetrain.Limits.SpinCap.New( Wheel ) )

    Shaft:AddSource( { GetTorque = function() return Torque end } )

    Shaft.Omega  = EngineOmega
    Wheel.Omega  = WheelOmega
    Cap.MaxOmega = Most
    Cap.MinOmega = -Most

    Cap.Clutches[1] = Clutch

    System:Finalize()

    return System, Shaft, Wheel, Clutch
end

-- An engine through a locked differential into two wheels; with Caps, each wheel is allowed only that far
local function Axle( Caps )
    local System = Drivetrain.System.New()
    local Shaft  = System:AddBody( Drivetrain.Body.New( 7.1 ) )
    local Box    = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local Left   = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local Right  = System:AddBody( Drivetrain.Body.New( 0.05 ) )
    local A      = System:AddBody( Drivetrain.Output.New( 200 ) )
    local B      = System:AddBody( Drivetrain.Output.New( 200 ) )

    Shaft:AddSource( { GetTorque = function() return 20000 end } )

    System:AddClutch( Drivetrain.Clutch.New( Shaft, Box, 1, 1, 1e9 ) )
    System:AddClutch( Drivetrain.Differential.New( Box, Left, Right, 0.25, math.huge ) )
    System:AddClutch( Drivetrain.Clutch.New( Left, Right, 1, 1, 1e9 ) )

    local ToA = System:AddClutch( Drivetrain.Clutch.New( Left, A, 1, 1, 1e9 ) )
    local ToB = System:AddClutch( Drivetrain.Clutch.New( Right, B, 1, 1, 1e9 ) )

    Shaft.Omega = 200
    Box.Omega   = 200
    Left.Omega  = 50
    Right.Omega = 50
    A.Omega     = 50
    B.Omega     = 50

    if Caps then
        for Wheel, Most in pairs( { [A] = Caps[1], [B] = Caps[2] } ) do
            local Cap = System:AddLimit( Drivetrain.Limits.SpinCap.New( Wheel ) )

            Cap.MaxOmega    = Most
            Cap.Clutches[1] = Wheel == A and ToA or ToB
        end
    end

    System:Finalize()

    return System, A, B
end

return {
    groupName = "ACF.Mobility.Drivetrain spin cap",

    cases = {
        {
            name = "A wheel reaching its cap is pushed no further, and the engine slips ahead of it",
            func = function()
                local System, Shaft, Wheel = Driven( 100, 300, 9.9, 10 )

                System:Step( DT )

                expect( Wheel.Omega ).to.aboutEqual( 10, 1e-9 )
                -- Paid only for the push to the cap
                expect( Shaft.Omega ).to.aboutEqual( 100 + 300 * DT / 1.4 - 0.1 * 10 * 0.1 / 1.4, 1e-9 )
            end
        },

        {
            name = "Below its cap, the wheel locks to the engine as before",
            func = function()
                local System, _, _, Clutch = Driven( 100, 300, 9.9, math.huge )

                System:Step( DT )

                expect( Clutch:GetSlip() ).to.aboutEqual( 0, 1e-9 )
            end
        },

        {
            name = "A wheel already past its cap may still be slowed by the engine",
            func = function()
                local System, _, Wheel, Clutch = Driven( 100, 0, 12, 10 )

                System:Step( DT )

                expect( Wheel.Omega ).to.beLessThan( 12 )
                expect( Clutch:GetSlip() ).to.aboutEqual( 0, 1e-9 )
            end
        },

        {
            name = "Backwards, the cap holds the same way",
            func = function()
                local System, Shaft, Wheel = Driven( -100, -300, -9.9, 10 )

                System:Step( DT )

                expect( Wheel.Omega ).to.aboutEqual( -10, 1e-9 )
                expect( Shaft.Omega ).to.beLessThan( -103 )
            end
        },

        {
            name = "What one wheel is held back from, a locked differential hands the other only up to its own cap",
            func = function()
                local Free, FreeA = Axle()

                Free:Step( DT )

                local Gain    = FreeA.Omega - 50 -- What each wheel gains uncapped
                local CapA    = 50 + 0.1 * Gain
                local CapB    = 50 + 1.5 * Gain -- Clear of the first solve, not of the torque A gives up
                local System, A, B = Axle( { CapA, CapB } )

                System:Step( DT )

                expect( A.Omega ).to.aboutEqual( CapA, 1e-9 )
                expect( B.Omega ).to.aboutEqual( CapB, 1e-9 )
            end
        },
    }
}

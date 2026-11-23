local Drivetrain = ACF.Mobility.Drivetrain

local DT = 1 / 66

-- Steps an output against a torque it does not know about, as the ground or a brake would act on it
local function RunAgainst( Output, Torque, Ticks )
    local Truth = Output.Omega

    for _ = 1, Ticks do
        Output:Integrate( DT )

        Truth = Truth + Torque * DT / Output.Inertia

        Output:Observe( Truth, DT )
    end
end

return {
    groupName = "ACF.Mobility.Drivetrain output load",

    cases = {
        {
            name = "A steady load is learned from the predictions it spoils",
            func = function()
                local Output = Drivetrain.Output.New( 10 )

                Output:Observe( 0, DT )

                RunAgainst( Output, -100, 30 )

                expect( Output.Load ).to.aboutEqual( -100, 1e-3 )
            end
        },

        {
            name = "An output that moves as predicted learns no load",
            func = function()
                local Output = Drivetrain.Output.New( 10 )

                Output:Observe( 5, DT )

                RunAgainst( Output, 0, 10 )

                expect( Output.Load ).to.equal( 0 )
                expect( Output.Omega ).to.equal( 5 )
            end
        },

        {
            name = "A push the ground cancels reads as a load against it",
            func = function()
                local Output = Drivetrain.Output.New( 10 )

                Output:Observe( 0, DT )

                Output.Omega = 10 -- Predicted after a push

                Output:Observe( 0, DT )

                expect( Output.Load ).to.beLessThan( 0 )
            end
        },

        {
            name = "Nothing is learned from the first reading after a reset",
            func = function()
                local Output = Drivetrain.Output.New( 10 )

                Output:Observe( 0, DT )
                RunAgainst( Output, -100, 30 )
                Output:Reset( 0 )
                Output:Observe( 50, DT )

                expect( Output.Load ).to.equal( 0 )
                expect( Output.Omega ).to.equal( 50 )
            end
        },
    }
}

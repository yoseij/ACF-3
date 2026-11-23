local Drivetrain = ACF.Mobility.Drivetrain

local DT = 1 / 66

return {
    groupName = "ACF.Mobility.Drivetrain dense solver",

    cases = {
        {
            name = "A row left without a pivot still pivots a later column, so a consistent loop blocks nothing",
            func = function()
                local Box    = Drivetrain.Body.New( 1e-4 )
                local Shaft  = Drivetrain.Body.New( 1.4 )
                local Wheel  = Drivetrain.Output.New( 20 )
                local Bodies = { Box, Shaft, Wheel }

                -- The second column's only pivot sits in the first one's row, which had none of its own
                local Clutches = {
                    Drivetrain.Clutch.New( Box, Wheel, 0.2, 1, 1e9 ),
                    Drivetrain.Clutch.New( Box, Shaft, 0.5, 1, 1e9 ),
                    Drivetrain.Clutch.New( Shaft, Box, 2, 1, 1e9 ),
                    Drivetrain.Clutch.New( Shaft, Box, 0.5, 1, 1e9 ),
                }

                local Solver = Drivetrain.Solver.New( Bodies, Clutches )

                for _, Clutch in ipairs( Clutches ) do Clutch:Prepare( DT ) end

                Solver:Prepare()

                local Size, Want = #Clutches, { 1, 2, 3, 4 }
                local Matrix, Rhs, Original, Target, Limit, Blocked = {}, {}, {}, {}, {}, {}

                for I = 1, Size * Size do
                    Matrix[I]   = Solver.Influence[I]
                    Original[I] = Solver.Influence[I]
                end

                for Row = 1, Size do
                    local Value = 0

                    for K = 1, Size do Value = Value + Original[( Row - 1 ) * Size + K] * Want[K] end

                    Rhs[Row], Target[Row], Limit[Row] = Value, Value, math.huge
                end

                Drivetrain.Solver.Eliminate( Matrix, Rhs, Size, Limit, Blocked )

                for Row = 1, Size do
                    local Value = 0

                    expect( Blocked[Row] ).to.beFalse()

                    for K = 1, Size do Value = Value + Original[( Row - 1 ) * Size + K] * Rhs[K] end

                    expect( Value ).to.aboutEqual( Target[Row], math.abs( Target[Row] ) * 1e-9 )
                end
            end
        },
    }
}

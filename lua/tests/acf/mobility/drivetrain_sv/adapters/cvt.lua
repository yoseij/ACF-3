local Drivetrain = ACF.Mobility.Drivetrain

local RPM_TO_RADS = ACF.RPMToRadS

-- A link from the CVT to an output turning at Speed (rad/s, already through its ratio), engaged, and slipping or not
local function Link( Speed, Slipping, Engaged )
    local Input  = Drivetrain.Body.New( 1 )
    local Output = Drivetrain.Body.New( 1 )
    local Clutch = Drivetrain.Clutch.New( Input, Output, 2, 1, 1e9 )

    Output.Omega      = Speed * 2
    Clutch.MaxImpulse = Engaged == false and 0 or 1
    Clutch.Saturated  = Slipping or false

    return { Clutch = Clutch, Target = { HoldsSpeed = function() return true end } }
end

local function LockedRPM( ... )
    return Drivetrain.Adapters.CVT.GetLockedRPM( { Links = { ... } } )
end

return {
    groupName = "ACF.Mobility.Drivetrain CVT",

    cases = {
        {
            name = "With one output locked and another slipping, its ratio follows the locked one, which pins its shaft",
            func = function()
                expect( LockedRPM( Link( 50 ), Link( 30, true ) ) ).to.aboutEqual( 50 / RPM_TO_RADS, 1e-6 )
            end
        },

        {
            name = "With every output slipping, it follows their average, so an overloaded one brings the ratio down",
            func = function()
                expect( LockedRPM( Link( 50, true ), Link( 30, true ) ) ).to.aboutEqual( 40 / RPM_TO_RADS, 1e-6 )
            end
        },

        {
            name = "A disengaged output sets nothing, and with none engaged there is no speed to follow",
            func = function()
                expect( LockedRPM( Link( 50 ), Link( 30, false, false ) ) ).to.aboutEqual( 50 / RPM_TO_RADS, 1e-6 )
                expect( LockedRPM( Link( 50, false, false ) ) ).to.equal( nil )
            end
        },
    }
}

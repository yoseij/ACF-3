local Classes = ACF.Classes

-- kW per m^3 of an engine's box at a power, growing with it as P ^ Growth, as turbines do
local function Volume( Power, Growth )
    return Power / ( ACF.EngineDensityRef * ( Power / ACF.EnginePowerRef ) ^ Growth )
end

return {
    groupName = "ACF cost",

    cases = {
        {
            name = "An engine split in two costs more than one of the same total, even if bigger ones pack more power",
            func = function()
                for _, Growth in ipairs( { 0, 0.5, 1 } ) do
                    for _, Power in ipairs( { 50, 300, 1500 } ) do
                        local Whole = ACF.GetEngineCost( Power, Volume( Power, Growth ) )
                        local Split = 2 * ACF.GetEngineCost( Power / 2, Volume( Power / 2, Growth ) )

                        expect( Split ).to.beGreaterThan( Whole )
                    end
                end
            end
        },

        {
            name = "A gearbox's rating split over two costs more than one gearbox carrying it",
            func = function()
                for _, Class in pairs( Classes.GetChildren( Classes.GetTypeByName( "ACF.Gearboxes.BaseGearbox" ) ) ) do
                    if Class.Cost then
                        for _, Rating in ipairs( { 1000, 10000, 100000 } ) do
                            local Whole = ACF.GetGearboxCost( Class, Rating, 3 )
                            local Split = 2 * ACF.GetGearboxCost( Class, Rating / 2, 3 )

                            expect( Split ).to.beGreaterThan( Whole )
                        end
                    end
                end
            end
        },

        {
            name = "With no power an engine costs nothing, and a gearbox with no rating or gears costs its base",
            func = function()
                expect( ACF.GetEngineCost( 0, 1 ) ).to.equal( 0 )

                for _, Class in pairs( Classes.GetChildren( Classes.GetTypeByName( "ACF.Gearboxes.BaseGearbox" ) ) ) do
                    if Class.Cost then expect( ACF.GetGearboxCost( Class, 0, 0 ) ).to.equal( Class.Cost.Base ) end
                end
            end
        },
    }
}

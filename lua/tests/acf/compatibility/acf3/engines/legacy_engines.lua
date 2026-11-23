local function Patch( Data )
    ACF.Entities.RunCompatPatches( Data.Class, Data )

    return Data.ACF_UserData, Data
end

local function Holds( List, Value )
    for _, V in ipairs( List ) do
        if V == Value then return true end
    end

    return false
end

return {
    groupName = "Legacy engine compat patches",

    cases = {
        {
            name = "An old dupe's fuel links move into the engine's fuel tanks",
            func = function()
                local UserData, Data = Patch( { Class = "acf_engine", Engine = "5.7-V8", EntityMods = { FuelLink = { entities = { 12, 15 } } } } )

                expect( #UserData.FuelTanks ).to.equal( 2 )
                expect( Holds( UserData.FuelTanks, 12 ) ).to.beTrue()
                expect( Holds( UserData.FuelTanks, 15 ) ).to.beTrue()
                expect( Data.EntityMods.FuelLink ).to.equal( nil )
            end
        },

        {
            name = "Both old fuel link modifiers merge without listing a tank twice",
            func = function()
                local Mods     = { FuelLink = { entities = { 12 } }, ACFFuelTanks = { 12, 20 } }
                local UserData = Patch( { Class = "acf_engine", Engine = "5.7-V8", EntityMods = Mods } )

                expect( #UserData.FuelTanks ).to.equal( 2 )
                expect( Holds( UserData.FuelTanks, 20 ) ).to.beTrue()
            end
        },

        {
            name = "An old dupe's gearbox links move into the engine's gearboxes",
            func = function()
                local UserData = Patch( { Class = "acf_engine", Engine = "5.7-V8", EntityMods = { GearLink = { entities = { 30 } } } } )

                expect( UserData.Gearboxes[1] ).to.equal( 30 )
            end
        },

        {
            name = "A legacy Multifuel engine becomes the diesel one of its layout and size",
            func = function()
                local UserData = Patch( { Class = "acf_engine", Engine = "2.4-B4" } )

                expect( UserData.Engine.Type ).to.equal( "ACF.Engines.B4" )
                expect( UserData.Engine.Data.EngineType ).to.equal( "ACF.EngineTypes.GenericDiesel" )
                expect( UserData.Engine.Data.Displacement ).to.equal( 2.4 )
            end
        },
    }
}

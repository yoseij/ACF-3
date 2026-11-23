local function Patch( Data )
    ACF.Entities.RunCompatPatches( Data.Class, Data )

    return Data.ACF_UserData, Data
end

return {
    groupName = "Legacy engine compat patches",

    cases = {
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

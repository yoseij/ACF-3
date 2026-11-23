local Classes = ACF.Classes

local function Layouts()
    local Result = {}

    for _, Family in pairs( Classes.GetChildren( Classes.GetTypeByName( "ACF.Engines.BaseEngine" ) ) ) do
        for _, Layout in pairs( Classes.GetChildren( Family ) ) do
            Result[#Result + 1] = Layout
        end
    end

    return Result
end

local function SizeField( Layout )
    return Classes.GetTypeFieldByName( Layout, "Displacement" ) or Classes.GetTypeFieldByName( Layout, "Power" )
end

-- Smallest and largest axis of a model scale; an electric motor's is stretched along its shaft, a Vector
local function Extents( Scale )
    if isnumber( Scale ) then return Scale, Scale end

    return math.min( Scale.x, Scale.y, Scale.z ), math.max( Scale.x, Scale.y, Scale.z )
end

local function Volume( Scale )
    if isnumber( Scale ) then return Scale ^ 3 end

    return Scale.x * Scale.y * Scale.z
end

-- A sized instance of a layout burning the given type
local function Make( Layout, TypeFQN, Size, Geared )
    local Instance = Layout()

    Instance.EngineType = Classes.GetTypeByName( TypeFQN )()
    Instance[SizeField( Layout ).Name] = Size
    Instance.Geared = Geared or false
    Instance:VerifyData()

    return Instance
end

return {
    groupName = "ACF.Engines stats",

    cases = {
        {
            name = "Every layout has one model, sounds in ascending size and bounds that hold its default",
            func = function()
                for _, Layout in ipairs( Layouts() ) do
                    local Field = SizeField( Layout )

                    expect( Field ).to.exist()
                    expect( Field.Options.Min ).to.beLessThan( Field.Options.Max )
                    expect( Field.Options.Default ).to.beGreaterThan( Field.Options.Min - 1e-9 )
                    expect( Field.Options.Default ).to.beLessThan( Field.Options.Max + 1e-9 )
                    expect( type( Layout.Model.Model ) ).to.equal( "string" )
                    expect( Layout.Model.Footprint ).to.beGreaterThan( 0 )
                    expect( #Layout.Sounds ).to.beGreaterThan( 0 )

                    for I = 2, #Layout.Sounds do
                        expect( Layout.Sounds[I].Size ).to.beGreaterThan( Layout.Sounds[I - 1].Size )
                    end
                end
            end
        },

        {
            name = "Every layout and type it allows gives sane stats across its size range",
            func = function()
                for _, Layout in ipairs( Layouts() ) do
                    local Options = SizeField( Layout ).Options

                    for _, TypeFQN in ipairs( Layout.EngineTypes ) do
                        for _, Size in ipairs( { Options.Min, Options.Default, Options.Max } ) do
                            local Stats = Make( Layout, TypeFQN, Size ):GetStats()

                            expect( Stats.Torque ).to.beGreaterThan( 0 )
                            expect( Stats.Mass ).to.beGreaterThan( 0 )
                            expect( Stats.PeakPower ).to.beGreaterThan( 0 )
                            expect( Stats.RPM.Limit ).to.beGreaterThan( Stats.RPM.Idle )
                            expect( Stats.RPM.Idle ).to.beGreaterThan( -1 )
                            local Smallest, Largest = Extents( Stats.Scale )

                            -- A small motor is short along its shaft, a seventh of its model
                            expect( Smallest ).to.beGreaterThan( 0.1 )
                            expect( Largest ).to.beLessThan( 2.5 )
                            expect( type( Stats.Model ) ).to.equal( "string" )
                            expect( type( Stats.Sound ) ).to.equal( "string" )
                            expect( type( Stats.Name ) ).to.equal( "string" )
                            expect( type( next( Stats.Fuel ) ) ).to.equal( "string" )
                        end
                    end
                end
            end
        },

        {
            name = "Torque, mass and model size grow with size for every layout and type",
            func = function()
                for _, Layout in ipairs( Layouts() ) do
                    local Options = SizeField( Layout ).Options

                    for _, TypeFQN in ipairs( Layout.EngineTypes ) do
                        local Small = Make( Layout, TypeFQN, Options.Min ):GetStats()
                        local Big   = Make( Layout, TypeFQN, Options.Max ):GetStats()

                        expect( Big.Torque ).to.beGreaterThan( Small.Torque )
                        expect( Big.Mass ).to.beGreaterThan( Small.Mass )
                        expect( Volume( Big.Scale ) ).to.beGreaterThan( Volume( Small.Scale ) )
                    end
                end
            end
        },

        {
            name = "Scaled models are about as big as the real engines their size law was fitted to",
            func = function()
                -- Geometric mean of the two largest extents, m: GM LS3, Maybach HL230, Continental R-670
                -- (diameter), Allison 250-C18
                local Real = {
                    { "ACF.Engines.V8",  "ACF.EngineTypes.GenericPetrol", 6.2,  0.730 },
                    { "ACF.Engines.V12", "ACF.EngineTypes.GenericPetrol", 23.1, 1.249 },
                    { "ACF.Engines.R7",  "ACF.EngineTypes.Radial",        10.95, 1.079 },
                    { "ACF.Engines.GT",  "ACF.EngineTypes.Turbine",       236,  0.767 },
                }

                for _, Want in ipairs( Real ) do
                    local Layout = Classes.GetTypeByName( Want[1] )
                    local Stats  = Make( Layout, Want[2], Want[3] ):GetStats()

                    -- The LS3 is the fit's worst, 21% under it
                    expect( Stats.Scale * Layout.Model.Footprint ).to.aboutEqual( Want[4], 0.25 * Want[4] )
                end
            end
        },

        {
            name = "A type a family doesn't burn and a size out of bounds are put back",
            func = function()
                local Rotary = Classes.GetTypeByName( "ACF.Engines.R2" )
                local Inst   = Rotary()

                Inst.EngineType   = Classes.GetTypeByName( "ACF.EngineTypes.GenericDiesel" )()
                Inst.Displacement = 50
                Inst:VerifyData()

                expect( Classes.GetTypeName( Inst.EngineType:GetType() ) ).to.equal( "ACF.EngineTypes.Wankel" )
                expect( Inst.Displacement ).to.equal( SizeField( Rotary ).Options.Max )
            end
        },

        {
            name = "A geared turbine turns slower, pulls harder and weighs more than a direct one of the same power",
            func = function()
                local GT     = Classes.GetTypeByName( "ACF.Engines.GT" )
                local Direct = Make( GT, "ACF.EngineTypes.Turbine", 500, false ):GetStats()
                local Geared = Make( GT, "ACF.EngineTypes.Turbine", 500, true ):GetStats()

                expect( Geared.RPM.Limit ).to.beLessThan( Direct.RPM.Limit )
                expect( Geared.Torque ).to.beGreaterThan( Direct.Torque * 2 )
                expect( Geared.Mass ).to.beGreaterThan( Direct.Mass )
                expect( Geared.Scale ).to.beGreaterThan( Direct.Scale )
                expect( Geared.PeakPower ).to.aboutEqual( Direct.PeakPower, 0.02 * Direct.PeakPower )
            end
        },

        {
            name = "A diesel of the same displacement pulls harder, revs lower and weighs more than the petrol",
            func = function()
                local V8     = Classes.GetTypeByName( "ACF.Engines.V8" )
                local Petrol = Make( V8, "ACF.EngineTypes.GenericPetrol", 6 ):GetStats()
                local Diesel = Make( V8, "ACF.EngineTypes.GenericDiesel", 6 ):GetStats()

                expect( Diesel.Torque ).to.beGreaterThan( Petrol.Torque )
                expect( Diesel.RPM.Limit ).to.beLessThan( Petrol.RPM.Limit )
                expect( Diesel.Mass ).to.beGreaterThan( Petrol.Mass )
            end
        },

        {
            name = "The largest V12 diesel makes about the Leopard 2's MB 873 power (47.6 L, 1,103 kW)",
            func = function()
                local Stats = Make( Classes.GetTypeByName( "ACF.Engines.V12" ), "ACF.EngineTypes.GenericDiesel", 47.6 ):GetStats()

                expect( Stats.PeakPower ).to.aboutEqual( 1103, 110 )
            end
        },

        {
            name = "Stats are reused until the size, type or gearing changes",
            func = function()
                local Inst  = Make( Classes.GetTypeByName( "ACF.Engines.I4" ), "ACF.EngineTypes.GenericPetrol", 2 )
                local First = Inst:GetStats()

                expect( Inst:GetStats() == First ).to.beTrue()

                Inst.Displacement = 3

                local Sized = Inst:GetStats()

                expect( Sized == First ).to.beFalse()

                Inst.EngineType = Classes.GetTypeByName( "ACF.EngineTypes.GenericDiesel" )()

                expect( Inst:GetStats() == Sized ).to.beFalse()

                local Turbine = Make( Classes.GetTypeByName( "ACF.Engines.GT" ), "ACF.EngineTypes.Turbine", 500 )
                local Direct  = Turbine:GetStats()

                Turbine.Geared = true

                expect( Turbine:GetStats() == Direct ).to.beFalse()
            end
        },

        {
            name = "Old hand-written engine ids are patched into a layout of the same size and type",
            func = function()
                local Expected = {
                    ["ACF.Engines.5.7-V8"]                     = { "ACF.Engines.V8",   "Displacement", 5.7,  "ACF.EngineTypes.GenericPetrol" },
                    ["ACF.Engines.15.0-I4"]                    = { "ACF.Engines.I4",   "Displacement", 15,   "ACF.EngineTypes.GenericDiesel" },
                    ["ACF.Engines.8.3-B6"]                     = { "ACF.Engines.B6",   "Displacement", 8.3,  "ACF.EngineTypes.GenericDiesel" },
                    ["ACF.Engines.5.3-V10"]                    = { "ACF.Engines.V10",  "Displacement", 5.3,  "ACF.EngineTypes.GenericPetrol" },
                    ["ACF.Engines.2.6L-Wankel"]                = { "ACF.Engines.R4",   "Displacement", 2.6,  "ACF.EngineTypes.Wankel" },
                    ["ACF.Engines.Turbine-Medium-Ground-Trans"] = { "ACF.Engines.GT-T", "Power",        141,  "ACF.EngineTypes.Turbine", true },
                    ["ACF.Engines.Electric-Tiny-NoBatt"]       = { "ACF.Engines.EL",   "Power",        8,    "ACF.EngineTypes.Electric" },
                }

                for Old, Want in pairs( Expected ) do
                    local Data = { Class = "acf_engine", ACF_UserData = { Engine = { Type = Old, Data = {} } } }

                    ACF.Entities.RunCompatPatches( "acf_engine", Data )

                    local Engine = Data.ACF_UserData.Engine

                    expect( Engine.Type ).to.equal( Want[1] )
                    expect( Engine.Data[Want[2]] ).to.aboutEqual( Want[3], 0.02 * Want[3] )
                    expect( Engine.Data.EngineType ).to.equal( Want[4] )
                    expect( Engine.Data.Geared == true ).to.equal( Want[5] == true )

                    -- And what it maps to is a real, allowed engine
                    local Layout = Classes.GetTypeByName( Engine.Type )
                    local Inst   = Make( Layout, Engine.Data.EngineType, Engine.Data[Want[2]], Engine.Data.Geared )

                    expect( Classes.GetTypeName( Inst.EngineType:GetType() ) ).to.equal( Want[4] )
                    expect( Inst:GetStats().Torque ).to.beGreaterThan( 0 )
                end
            end
        },
    }
}

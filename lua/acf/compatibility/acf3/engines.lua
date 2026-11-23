-- Engines are families of layouts sized by displacement or rated power: every hand-written engine class
-- maps to the layout, size and engine type it was, so old dupes spawn the same engine with the fitted stats.
local LEGACY = {
	["ACF.Engines.0.25-I1"] = { Layout = "ACF.Engines.I1", Displacement = 0.25, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 250cc Single Cylinder
	["ACF.Engines.0.5-I1"] = { Layout = "ACF.Engines.I1", Displacement = 0.50, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 500cc Single Cylinder
	["ACF.Engines.0.6-V2"] = { Layout = "ACF.Engines.V2", Displacement = 0.60, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 600cc V-Twin
	["ACF.Engines.0.8L-I2"] = { Layout = "ACF.Engines.I2", Displacement = 0.80, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 0.8L I2 Diesel
	["ACF.Engines.0.9L-I2"] = { Layout = "ACF.Engines.I2", Displacement = 0.90, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 0.9L I2 Petrol
	["ACF.Engines.1.0L-I4"] = { Layout = "ACF.Engines.I4", Displacement = 1.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1.0L I4 Petrol
	["ACF.Engines.1.1-I3"] = { Layout = "ACF.Engines.I3", Displacement = 1.10, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 1.1L I3 Diesel
	["ACF.Engines.1.2-I3"] = { Layout = "ACF.Engines.I3", Displacement = 1.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1.2L I3 Petrol
	["ACF.Engines.1.2-V2"] = { Layout = "ACF.Engines.V2", Displacement = 1.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1200cc V-Twin
	["ACF.Engines.1.3-I1"] = { Layout = "ACF.Engines.I1", Displacement = 1.30, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1300cc Single Cylinder
	["ACF.Engines.1.3L-R"] = { Layout = "ACF.Engines.R2", Displacement = 1.30, EngineType = "ACF.EngineTypes.Wankel" }, -- 1.3L Rotary
	["ACF.Engines.1.4-B4"] = { Layout = "ACF.Engines.B4", Displacement = 1.40, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1.4L Flat 4 Petrol
	["ACF.Engines.1.5-I4"] = { Layout = "ACF.Engines.I4", Displacement = 1.50, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1.5L I4 Petrol
	["ACF.Engines.1.6-I4"] = { Layout = "ACF.Engines.I4", Displacement = 1.60, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 1.6L I4 Diesel
	["ACF.Engines.1.8L-V4"] = { Layout = "ACF.Engines.V4", Displacement = 1.80, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1.8L V4 Petrol
	["ACF.Engines.1.9L-I4"] = { Layout = "ACF.Engines.I4", Displacement = 1.90, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 1.9L I4 Petrol
	["ACF.Engines.1.9L-V4"] = { Layout = "ACF.Engines.V4", Displacement = 1.90, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 1.9L V4 Diesel
	["ACF.Engines.10.0-I2"] = { Layout = "ACF.Engines.I2", Displacement = 10.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 10.0L I2 Diesel
	["ACF.Engines.11.0-I3"] = { Layout = "ACF.Engines.I3", Displacement = 11.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 11.0L I3 Diesel
	["ACF.Engines.11.0-R7"] = { Layout = "ACF.Engines.R7", Displacement = 11.00, EngineType = "ACF.EngineTypes.Radial" }, -- 11.0L R7 Petrol
	["ACF.Engines.12.0-V6"] = { Layout = "ACF.Engines.V6", Displacement = 12.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 12.0L V6 Petrol
	["ACF.Engines.13.0-V12"] = { Layout = "ACF.Engines.V12", Displacement = 13.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 13.0L V12 Petrol
	["ACF.Engines.13.5-I3"] = { Layout = "ACF.Engines.I3", Displacement = 13.50, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 13.5L I3 Petrol
	["ACF.Engines.14.5-B6"] = { Layout = "ACF.Engines.B6", Displacement = 14.50, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 14.5L Flat 6 Diesel
	["ACF.Engines.15.0-I4"] = { Layout = "ACF.Engines.I4", Displacement = 15.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 15.0L I4 Diesel
	["ACF.Engines.15.0-V6"] = { Layout = "ACF.Engines.V6", Displacement = 15.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 15.0L V6 Diesel
	["ACF.Engines.15.8-B6"] = { Layout = "ACF.Engines.B6", Displacement = 15.80, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 15.8L Flat 6 Petrol
	["ACF.Engines.16.0-I4"] = { Layout = "ACF.Engines.I4", Displacement = 16.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 16.0L I4 Petrol
	["ACF.Engines.17.2-I6"] = { Layout = "ACF.Engines.I6", Displacement = 17.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 17.2L I6 Petrol
	["ACF.Engines.18.0-V8"] = { Layout = "ACF.Engines.V8", Displacement = 18.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 18.0L V8 Petrol
	["ACF.Engines.19.0-V8"] = { Layout = "ACF.Engines.V8", Displacement = 19.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 19.0L V8 Diesel
	["ACF.Engines.2.0L-R"] = { Layout = "ACF.Engines.R3", Displacement = 2.00, EngineType = "ACF.EngineTypes.Wankel" }, -- 2.0L Rotary
	["ACF.Engines.2.1-B4"] = { Layout = "ACF.Engines.B4", Displacement = 2.10, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2.1L Flat 4 Petrol
	["ACF.Engines.2.2-I6"] = { Layout = "ACF.Engines.I6", Displacement = 2.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2.2L I6 Petrol
	["ACF.Engines.2.3-I5"] = { Layout = "ACF.Engines.I5", Displacement = 2.30, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2.3L I5 Petrol
	["ACF.Engines.2.4-B4"] = { Layout = "ACF.Engines.B4", Displacement = 2.40, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 2.4L Flat 4 Multifuel
	["ACF.Engines.2.4-V2"] = { Layout = "ACF.Engines.V2", Displacement = 2.40, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2400cc V-Twin
	["ACF.Engines.2.4L-V6"] = { Layout = "ACF.Engines.V6", Displacement = 2.40, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2.4L V6 Petrol
	["ACF.Engines.2.6L-Wankel"] = { Layout = "ACF.Engines.R4", Displacement = 2.60, EngineType = "ACF.EngineTypes.Wankel" }, -- 2.6L Rotary
	["ACF.Engines.2.8-B6"] = { Layout = "ACF.Engines.B6", Displacement = 2.80, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2.8L Flat 6 Petrol
	["ACF.Engines.2.8-I3"] = { Layout = "ACF.Engines.I3", Displacement = 2.80, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 2.8L I3 Diesel
	["ACF.Engines.2.9-I5"] = { Layout = "ACF.Engines.I5", Displacement = 2.90, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 2.9L I5 Diesel
	["ACF.Engines.2.9-V8"] = { Layout = "ACF.Engines.V8", Displacement = 2.90, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 2.9L V8 Petrol
	["ACF.Engines.20.0-I6"] = { Layout = "ACF.Engines.I6", Displacement = 20.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 20.0L I6 Diesel
	["ACF.Engines.21.0-V12"] = { Layout = "ACF.Engines.V12", Displacement = 21.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 21.0L V12 Diesel
	["ACF.Engines.22.0-V10"] = { Layout = "ACF.Engines.V10", Displacement = 22.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 22.0L V10 Multifuel
	["ACF.Engines.23.0-V12"] = { Layout = "ACF.Engines.V12", Displacement = 23.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 23.0L V12 Petrol
	["ACF.Engines.24.0-R7"] = { Layout = "ACF.Engines.R7", Displacement = 24.00, EngineType = "ACF.EngineTypes.Radial" }, -- 24.0L R7 Petrol
	["ACF.Engines.3.0-I6"] = { Layout = "ACF.Engines.I6", Displacement = 3.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 3.0L I6 Diesel
	["ACF.Engines.3.0-V12"] = { Layout = "ACF.Engines.V12", Displacement = 3.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.0L V12 Petrol
	["ACF.Engines.3.1-I4"] = { Layout = "ACF.Engines.I4", Displacement = 3.10, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 3.1L I4 Diesel
	["ACF.Engines.3.2-B4"] = { Layout = "ACF.Engines.B4", Displacement = 3.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.2L Flat 4 Petrol
	["ACF.Engines.3.3L-V4"] = { Layout = "ACF.Engines.V4", Displacement = 3.30, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 3.3L V4 Diesel
	["ACF.Engines.3.4-I3"] = { Layout = "ACF.Engines.I3", Displacement = 3.40, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.4L I3 Petrol
	["ACF.Engines.3.6-V6"] = { Layout = "ACF.Engines.V6", Displacement = 3.60, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.6L V6 Petrol
	["ACF.Engines.3.7-I4"] = { Layout = "ACF.Engines.I4", Displacement = 3.70, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.7L I4 Petrol
	["ACF.Engines.3.8-I6"] = { Layout = "ACF.Engines.I6", Displacement = 3.80, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.8L I6 Petrol
	["ACF.Engines.3.8-R7"] = { Layout = "ACF.Engines.R7", Displacement = 3.80, EngineType = "ACF.EngineTypes.Radial" }, -- 3.8L R7 Petrol
	["ACF.Engines.3.9-I5"] = { Layout = "ACF.Engines.I5", Displacement = 3.90, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 3.9L I5 Petrol
	["ACF.Engines.4.0-V12"] = { Layout = "ACF.Engines.V12", Displacement = 4.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 4.0L V12 Diesel
	["ACF.Engines.4.1-I5"] = { Layout = "ACF.Engines.I5", Displacement = 4.10, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 4.1L I5 Diesel
	["ACF.Engines.4.3-V10"] = { Layout = "ACF.Engines.V10", Displacement = 4.30, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 4.3L V10 Petrol
	["ACF.Engines.4.5-V8"] = { Layout = "ACF.Engines.V8", Displacement = 4.50, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 4.5L V8 Diesel
	["ACF.Engines.4.6-V12"] = { Layout = "ACF.Engines.V12", Displacement = 4.60, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 4.6L V12 Petrol
	["ACF.Engines.4.8-I6"] = { Layout = "ACF.Engines.I6", Displacement = 4.80, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 4.8L I6 Petrol
	["ACF.Engines.5.0-B6"] = { Layout = "ACF.Engines.B6", Displacement = 5.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 5.0L Flat 6 Petrol
	["ACF.Engines.5.2-V6"] = { Layout = "ACF.Engines.V6", Displacement = 5.20, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 5.2L V6 Diesel
	["ACF.Engines.5.3-V10"] = { Layout = "ACF.Engines.V10", Displacement = 5.30, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 5.3L V10 Special
	["ACF.Engines.5.7-V8"] = { Layout = "ACF.Engines.V8", Displacement = 5.70, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 5.7L V8 Petrol
	["ACF.Engines.6.2-V6"] = { Layout = "ACF.Engines.V6", Displacement = 6.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 6.2L V6 Petrol
	["ACF.Engines.6.5-I6"] = { Layout = "ACF.Engines.I6", Displacement = 6.50, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 6.5L I6 Diesel
	["ACF.Engines.7.0-V12"] = { Layout = "ACF.Engines.V12", Displacement = 7.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 7.0L V12 Petrol
	["ACF.Engines.7.2-V8"] = { Layout = "ACF.Engines.V8", Displacement = 7.20, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 7.2L V8 Petrol
	["ACF.Engines.7.8-V8"] = { Layout = "ACF.Engines.V8", Displacement = 7.80, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 7.8L V8 Diesel
	["ACF.Engines.8.0-R7"] = { Layout = "ACF.Engines.R7", Displacement = 8.00, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 8.0L R7 Diesel
	["ACF.Engines.8.0-V10"] = { Layout = "ACF.Engines.V10", Displacement = 8.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 8.0L V10 Petrol
	["ACF.Engines.8.3-B6"] = { Layout = "ACF.Engines.B6", Displacement = 8.30, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 8.3L Flat 6 Multifuel
	["ACF.Engines.9.0-V8"] = { Layout = "ACF.Engines.V8", Displacement = 9.00, EngineType = "ACF.EngineTypes.GenericPetrol" }, -- 9.0L V8 Petrol
	["ACF.Engines.9.2-V12"] = { Layout = "ACF.Engines.V12", Displacement = 9.20, EngineType = "ACF.EngineTypes.GenericDiesel" }, -- 9.2L V12 Diesel
	["ACF.Engines.900cc-R"] = { Layout = "ACF.Engines.R2", Displacement = 0.90, EngineType = "ACF.EngineTypes.Wankel" }, -- 0.9L Rotary
	["ACF.Engines.Electric-Large"] = { Layout = "ACF.Engines.EL", Power = 495, EngineType = "ACF.EngineTypes.Electric" }, -- Large Electric Motor
	["ACF.Engines.Electric-Large-NoBatt"] = { Layout = "ACF.Engines.EL", Power = 396, EngineType = "ACF.EngineTypes.Electric" }, -- Large Electric Standalone Motor
	["ACF.Engines.Electric-Medium"] = { Layout = "ACF.Engines.EL", Power = 261, EngineType = "ACF.EngineTypes.Electric" }, -- Medium Electric Motor
	["ACF.Engines.Electric-Medium-NoBatt"] = { Layout = "ACF.Engines.EL", Power = 202, EngineType = "ACF.EngineTypes.Electric" }, -- Medium Electric Standalone Motor
	["ACF.Engines.Electric-Small"] = { Layout = "ACF.Engines.EL", Power = 112, EngineType = "ACF.EngineTypes.Electric" }, -- Small Electric Motor
	["ACF.Engines.Electric-Small-NoBatt"] = { Layout = "ACF.Engines.EL", Power = 84, EngineType = "ACF.EngineTypes.Electric" }, -- Small Electric Standalone Motor
	["ACF.Engines.Electric-Tiny-NoBatt"] = { Layout = "ACF.Engines.EL", Power = 8, EngineType = "ACF.EngineTypes.Electric" }, -- Tiny Electric Standalone Motor
	["ACF.Engines.Turbine-Ground-Large"] = { Layout = "ACF.Engines.GT", Power = 1021, EngineType = "ACF.EngineTypes.Turbine", Geared = true }, -- Large Ground Gas Turbine
	["ACF.Engines.Turbine-Ground-Medium"] = { Layout = "ACF.Engines.GT", Power = 440, EngineType = "ACF.EngineTypes.Turbine", Geared = true }, -- Medium Ground Gas Turbine
	["ACF.Engines.Turbine-Ground-Small"] = { Layout = "ACF.Engines.GT", Power = 210, EngineType = "ACF.EngineTypes.Turbine", Geared = true }, -- Small Ground Gas Turbine
	["ACF.Engines.Turbine-Large"] = { Layout = "ACF.Engines.GT", Power = 1083, EngineType = "ACF.EngineTypes.Turbine" }, -- Large Gas Turbine
	["ACF.Engines.Turbine-Large-Ground-Trans"] = { Layout = "ACF.Engines.GT-T", Power = 522, EngineType = "ACF.EngineTypes.Turbine", Geared = true }, -- Large Transaxial Ground Gas Turbine
	["ACF.Engines.Turbine-Large-Trans"] = { Layout = "ACF.Engines.GT-T", Power = 591, EngineType = "ACF.EngineTypes.Turbine" }, -- Large Transaxial Gas Turbine
	["ACF.Engines.Turbine-Medium"] = { Layout = "ACF.Engines.GT", Power = 485, EngineType = "ACF.EngineTypes.Turbine" }, -- Medium Gas Turbine
	["ACF.Engines.Turbine-Medium-Ground-Trans"] = { Layout = "ACF.Engines.GT-T", Power = 141, EngineType = "ACF.EngineTypes.Turbine", Geared = true }, -- Medium Transaxial Ground Gas Turbine
	["ACF.Engines.Turbine-Medium-Trans"] = { Layout = "ACF.Engines.GT-T", Power = 272, EngineType = "ACF.EngineTypes.Turbine" }, -- Medium Transaxial Gas Turbine
	["ACF.Engines.Turbine-Small"] = { Layout = "ACF.Engines.GT", Power = 228, EngineType = "ACF.EngineTypes.Turbine" }, -- Small Gas Turbine
	["ACF.Engines.Turbine-Small-Ground-Trans"] = { Layout = "ACF.Engines.GT-T", Power = 116, EngineType = "ACF.EngineTypes.Turbine", Geared = true }, -- Small Transaxial Ground Gas Turbine
	["ACF.Engines.Turbine-Small-Trans"] = { Layout = "ACF.Engines.GT-T", Power = 128, EngineType = "ACF.EngineTypes.Turbine" }, -- Small Transaxial Gas Turbine
}

-- This was for the autoregisterv2 conversion: migrate legacy flat engine dupe data (a top-level Engine
-- short id, e.g. "5.7-V8") into the nested ACF_UserData field set keyed by FQN.
ACF.Entities.RegisterCompatPatch("acf_engine", 2026062801, function(Data)
	if Data.ACF_UserData then return end

	local Engine = Data.Engine or Data.Id or "5.7-V8"

	Data.ACF_UserData = {
		Engine = {Type = "ACF.Engines." .. tostring(Engine), Data = {}},
	}
end)

ACF.Entities.RegisterCompatPatch("acf_engine", 2026111101, function(Data)
	local UserData = Data.ACF_UserData
	local Engine   = UserData and UserData.Engine
	local FQN      = istable(Engine) and Engine.Type or Engine
	local Old      = LEGACY[FQN]

	if not Old then return end -- Already a layout, or nothing we know; the field's default takes over

	UserData.Engine = {
		Type = Old.Layout,
		Data = { Displacement = Old.Displacement, Power = Old.Power, EngineType = Old.EngineType, Geared = Old.Geared },
	}
end)

ACF.Entities.RegisterCompatPatch("acf_engine", 2026111801, function(Data)
	local Move = ACF.Entities.MoveLinkModToUserData

	Move(Data, "GearLink", "Gearboxes", false, "entities")
	Move(Data, "ACFGearboxes", "Gearboxes")

	-- Fuel tanks are found through shared parents now
	if istable(Data.EntityMods) then
		Data.EntityMods.FuelLink     = nil
		Data.EntityMods.ACFFuelTanks = nil
	end
end)

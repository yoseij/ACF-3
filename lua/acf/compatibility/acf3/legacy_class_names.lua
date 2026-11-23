-- These are new class names -> pre-autoregister + class rework names.
-- They exist for some parts of user-land (mostly Starfall/E2 bindings, but also some AIO HUD elements)

local ACF = ACF

local LegacyClassNames = {
    -- Ammunition (ammo types)
    ["ACF.Ammunition.AP"]     = "AP",
    ["ACF.Ammunition.APCR"]   = "APCR",
    ["ACF.Ammunition.APDS"]   = "APDS",
    ["ACF.Ammunition.APFSDS"] = "APFSDS",
    ["ACF.Ammunition.APHE"]   = "APHE",
    ["ACF.Ammunition.FL"]     = "FL",
    ["ACF.Ammunition.FLR"]    = "FLR",
    ["ACF.Ammunition.GLATGM"] = "GLATGM",
    ["ACF.Ammunition.HE"]     = "HE",
    ["ACF.Ammunition.HEAT"]   = "HEAT",
    ["ACF.Ammunition.HEATFS"] = "HEATFS",
    ["ACF.Ammunition.HP"]     = "HP",
    ["ACF.Ammunition.SM"]     = "SM",

    -- Guns (weapons)
    ["ACF.Guns.40mmFlareLauncher"]    = "40mmFGL",
    ["ACF.Guns.Autocannon"]           = "AC",
    ["ACF.Guns.Cannon"]               = "C",
    ["ACF.Guns.FlareLauncher"]        = "FGL",
    ["ACF.Guns.GrenadeLauncher"]      = "GL",
    ["ACF.Guns.Howitzer"]             = "HW",
    ["ACF.Guns.LightAutocannon"]      = "LAC",
    ["ACF.Guns.Machinegun"]           = "MG",
    ["ACF.Guns.Mortar"]               = "MO",
    ["ACF.Guns.RotaryAutocannon"]     = "RAC",
    ["ACF.Guns.SemiautomaticCannon"]  = "SA",
    ["ACF.Guns.ShortBarrelledCannon"] = "SC",
    ["ACF.Guns.SmokeLauncher"]        = "SL",

    -- Engine types
    ["ACF.EngineTypes.Electric"]      = "Electric",
    ["ACF.EngineTypes.GenericDiesel"] = "GenericDiesel",
    ["ACF.EngineTypes.GenericPetrol"] = "GenericPetrol",
    ["ACF.EngineTypes.Radial"]        = "Radial",
    ["ACF.EngineTypes.Turbine"]       = "Turbine",
    ["ACF.EngineTypes.Wankel"]        = "Wankel",

    -- Fuel types
    ["ACF.FuelTypes.Diesel"]   = "Diesel",
    ["ACF.FuelTypes.Electric"] = "Electric",
    ["ACF.FuelTypes.Petrol"]   = "Petrol",

    -- Gearboxes
    ["ACF.Gearboxes.1Gear-L"]      = "1Gear-L",
    ["ACF.Gearboxes.1Gear-T"]      = "1Gear-T",
    ["ACF.Gearboxes.2Gear-L"]      = "2Gear-L",
    ["ACF.Gearboxes.2Gear-T"]      = "2Gear-T",
    ["ACF.Gearboxes.Auto"]         = "Auto",
    ["ACF.Gearboxes.Auto-L"]       = "Auto-L",
    ["ACF.Gearboxes.Auto-ST"]      = "Auto-ST",
    ["ACF.Gearboxes.Auto-T"]       = "Auto-T",
    ["ACF.Gearboxes.Clutch"]       = "Clutch",
    ["ACF.Gearboxes.Clutch-S"]     = "Clutch-S",
    ["ACF.Gearboxes.CVT"]          = "CVT",
    ["ACF.Gearboxes.CVT-L"]        = "CVT-L",
    ["ACF.Gearboxes.CVT-ST"]       = "CVT-ST",
    ["ACF.Gearboxes.CVT-T"]        = "CVT-T",
    ["ACF.Gearboxes.Differential"] = "Differential",
    ["ACF.Gearboxes.DoubleDiff"]   = "DoubleDiff",
    ["ACF.Gearboxes.DoubleDiff-T"] = "DoubleDiff-T",
    ["ACF.Gearboxes.Manual"]       = "Manual",
    ["ACF.Gearboxes.Manual-L"]     = "Manual-L",
    ["ACF.Gearboxes.Manual-ST"]    = "Manual-ST",
    ["ACF.Gearboxes.Manual-T"]     = "Manual-T",
    ["ACF.Gearboxes.Transfer"]     = "Transfer",

    -- Fuel/ammo container shapes
    ["ACF.ContainerShapes.Box"]      = "Box",
    ["ACF.ContainerShapes.Cylinder"] = "Cylinder",
    ["ACF.ContainerShapes.Sphere"]   = "Sphere",

    -- Baseplates
    ["ACF.Baseplates.Aircraft"]      = "Aircraft",
    ["ACF.Baseplates.GroundVehicle"] = "GroundVehicle",
    ["ACF.Baseplates.Recreational"]  = "Recreational",

    -- Components
    ["ACF.Components.Autoloader"]              = "AL",
    ["ACF.Components.GPSTransmitter"]          = "CPR-GPS",
    ["ACF.Components.GroundLoader"]            = "GND-LDR",
    ["ACF.Components.GuidanceComputer"]        = "GD-CPR",
    ["ACF.Components.Joystick"]                = "CPR-Joystick",
    ["ACF.Components.LaserGuidanceComputer"]   = "CPR-LSR",
    ["ACF.Components.OpticalGuidanceComputer"] = "CPR-OPT",
    ["ACF.Components.SupplyCrate"]             = "SP-RFL",
    ["ACF.Components.Waterjet"]                = "WTJ",

    -- Crew types
    ["ACF.CrewTypes.Commander"] = "Commander",
    ["ACF.CrewTypes.Driver"]    = "Driver",
    ["ACF.CrewTypes.Gunner"]    = "Gunner",
    ["ACF.CrewTypes.Loader"]    = "Loader",
    ["ACF.CrewTypes.Pilot"]     = "Pilot",

    -- Crew models
    ["ACF.CrewModels.Sitting"]        = "Sitting",
    ["ACF.CrewModels.SittingLarge"]   = "Sitting_Large",
    ["ACF.CrewModels.SittingMedium"]  = "Sitting_Medium",
    ["ACF.CrewModels.SittingSmall"]   = "Sitting_Small",
    ["ACF.CrewModels.Standing"]       = "Standing",
    ["ACF.CrewModels.StandingLarge"]  = "Standing_Large",
    ["ACF.CrewModels.StandingMedium"] = "Standing_Medium",
    ["ACF.CrewModels.StandingSmall"]  = "Standing_Small",

    -- Crew poses
    ["ACF.CrewPoses.SitCamera"]        = "sit_camera",
    ["ACF.CrewPoses.SitRollercoaster"] = "sit_rollercoaster",
    ["ACF.CrewPoses.WalkAll"]          = "walk_all",
    ["ACF.CrewPoses.WalkCamera"]       = "walk_camera",
    ["ACF.CrewPoses.WalkDual"]         = "walk_dual",

    -- Turrets
    ["ACF.Turrets.Computer"]          = "4-Computer",
    ["ACF.Turrets.Computer.Direct"]   = "DIR-BalComp",
    ["ACF.Turrets.Computer.Indirect"] = "IND-BalComp",
    ["ACF.Turrets.Drive"]             = "1-Turret",
    ["ACF.Turrets.Drive.Horizontal"]  = "Turret-H",
    ["ACF.Turrets.Drive.Vertical"]    = "Turret-V",
    ["ACF.Turrets.Gyro"]              = "3-Gyro",
    ["ACF.Turrets.Gyro.Dual"]         = "2-Gyro",
    ["ACF.Turrets.Gyro.Single"]       = "1-Gyro",
    ["ACF.Turrets.Motor"]             = "2-Motor",
    ["ACF.Turrets.Motor.Electric"]    = "Motor-ELC",
    ["ACF.Turrets.Motor.Hydraulic"]   = "Motor-HYD",

    -- Sensors
    -- Missile and targeting radars are one class set now, so each merged class reports its merged ID
    ["ACF.Sensors.Radar.Standard"]                   = "Radar",
    ["ACF.Sensors.Radar.Standard.LargeDirectional"]  = "LargeDIR",
    ["ACF.Sensors.Radar.Standard.LargeSpherical"]    = "LargeOMNI",
    ["ACF.Sensors.Radar.Standard.MediumDirectional"] = "MediumDIR",
    ["ACF.Sensors.Radar.Standard.MediumSpherical"]   = "MediumOMNI",
    ["ACF.Sensors.Radar.Standard.SmallDirectional"]  = "SmallDIR",
    ["ACF.Sensors.Radar.Standard.SmallSpherical"]    = "SmallOMNI",
    ["ACF.Sensors.Receiver.Warning"]                  = "WARN-Receiver",
    ["ACF.Sensors.Receiver.Warning.Laser"]            = "LAS-Receiver",
    ["ACF.Sensors.Receiver.Warning.Radar"]            = "RAD-Receiver",

    -- Countermeasures
    ["ACF.Countermeasures.Flare"] = "Flare",

    -- Piledrivers
    ["ACF.Piledrivers.Piledriver"] = "PD",

    -- Missile racks
    ["ACF.Racks.127mm4xPOD"] = "127mm4xPOD",
    ["ACF.Racks.1xAT3RK"]    = "1xAT3RK",
    ["ACF.Racks.1xAT3RKS"]   = "1xAT3RKS",
    ["ACF.Racks.1xAtaka"]    = "1x Ataka",
    ["ACF.Racks.1xBGM-71E"]  = "1x BGM-71E",
    ["ACF.Racks.1xFIM-92"]   = "1x FIM-92",
    ["ACF.Racks.1xKornet"]   = "1x Kornet",
    ["ACF.Racks.1xRK"]       = "1xRK",
    ["ACF.Racks.1xRK_small"] = "1xRK_small",
    ["ACF.Racks.1xSPG9"]     = "1x SPG9",
    ["ACF.Racks.1xStrela-1"] = "1x Strela-1",
    ["ACF.Racks.2x AGM-114"] = "2x AGM-114",
    ["ACF.Racks.2xBGM-71E"]  = "2x BGM-71E",
    ["ACF.Racks.2xFIM-92"]   = "2x FIM-92",
    ["ACF.Racks.2xRK"]       = "2xRK",
    ["ACF.Racks.2xStrela-1"] = "2x Strela-1",
    ["ACF.Racks.380mmRW61"]  = "380mmRW61",
    ["ACF.Racks.3xRK"]       = "3xRK",
    ["ACF.Racks.3xUARRK"]    = "3xUARRK",
    ["ACF.Racks.40mm7xPOD"]  = "40mm7xPOD",
    ["ACF.Racks.4x AGM-114"] = "4x AGM-114",
    ["ACF.Racks.4xBGM-71E"]  = "4x BGM-71E",
    ["ACF.Racks.4xFIM-92"]   = "4x FIM-92",
    ["ACF.Racks.4xRK"]       = "4xRK",
    ["ACF.Racks.4xStrela-1"] = "4x Strela-1",
    ["ACF.Racks.57mm16xPOD"] = "57mm16xPOD",
    ["ACF.Racks.57mm32xPOD"] = "57mm32xPOD",
    ["ACF.Racks.6xUARRK"]    = "6xUARRK",
    ["ACF.Racks.70mm19xPOD"] = "70mm19xPOD",
    ["ACF.Racks.70mm7xPOD"]  = "70mm7xPOD",
    ["ACF.Racks.80mm20xPOD"] = "80mm20xPOD",

    -- Missiles - launcher groups
    ["ACF.Missiles.AirToAir"]         = "AAM",
    ["ACF.Missiles.AntiRadiation"]    = "ARM",
    ["ACF.Missiles.AntiTankGuided"]   = "ATGM",
    ["ACF.Missiles.Artillery"]        = "ARTY",
    ["ACF.Missiles.FoldingFinRocket"] = "FFAR",
    ["ACF.Missiles.FreeFallingBomb"]  = "BOMB",
    ["ACF.Missiles.GlidingBomb"]      = "GBOMB",
    ["ACF.Missiles.GuidedBomb"]       = "GBU",
    ["ACF.Missiles.SurfaceToAir"]     = "SAM",
    ["ACF.Missiles.UnguidedRocket"]   = "UAR",

    -- Missiles - guidance types
    ["ACF.Missiles.Guidance.ActiveRadar"]     = "Active Radar",
    ["ACF.Missiles.Guidance.AntiMissile"]     = "Anti-missile",
    ["ACF.Missiles.Guidance.AntiRadiation"]   = "Anti-radiation",
    ["ACF.Missiles.Guidance.Dumb"]            = "Dumb",
    ["ACF.Missiles.Guidance.GPSGuided"]       = "GPS Guided",
    ["ACF.Missiles.Guidance.Infrared"]        = "Infrared",
    ["ACF.Missiles.Guidance.Laser"]           = "Laser",
    ["ACF.Missiles.Guidance.RadioMCLOS"]      = "Radio (MCLOS)",
    ["ACF.Missiles.Guidance.RadioSACLOS"]     = "Radio (SACLOS)",
    ["ACF.Missiles.Guidance.SemiActiveRadar"] = "Semi-Active Radar",
    ["ACF.Missiles.Guidance.WireMCLOS"]       = "Wire (MCLOS)",
    ["ACF.Missiles.Guidance.WireSACLOS"]      = "Wire (SACLOS)",

    -- Missiles - fuze types
    ["ACF.Missiles.Fuze.Altitude"] = "Altitude",
    ["ACF.Missiles.Fuze.Contact"]  = "Contact",
    ["ACF.Missiles.Fuze.Optical"]  = "Optical",
    ["ACF.Missiles.Fuze.Radio"]    = "Radio",
    ["ACF.Missiles.Fuze.Timed"]    = "Timed",

    -- Missiles - munitions
    ["ACF.Missiles.AirToAir.AIM-120"]       = "AIM-120 AAM",
    ["ACF.Missiles.AirToAir.AIM-54"]        = "AIM-54 AAM",
    ["ACF.Missiles.AirToAir.AIM-7"]         = "AIM-7 AAM",
    ["ACF.Missiles.AirToAir.AIM-9"]         = "AIM-9 AAM",
    ["ACF.Missiles.AntiRadiation.AGM-122"]  = "AGM-122 ASM",
    ["ACF.Missiles.AntiRadiation.AGM-45"]   = "AGM-45 ASM",
    ["ACF.Missiles.AntiTankGuided.9M133"]   = "9M133 ASM",
    ["ACF.Missiles.AntiTankGuided.AGM-114"] = "AGM-114 ASM",
    ["ACF.Missiles.AntiTankGuided.AT-2"]    = "AT-2 ASM",
    ["ACF.Missiles.AntiTankGuided.AT-3"]    = "AT-3 ASM",
    ["ACF.Missiles.AntiTankGuided.Ataka"]   = "Ataka ASM",
    ["ACF.Missiles.AntiTankGuided.BGM-71E"] = "BGM-71E ASM",
    ["ACF.Missiles.Artillery.SAKR-10"]      = "SAKR-10 RA",
    ["ACF.Missiles.Artillery.SS-40"]        = "SS-40 RA",
    ["ACF.Missiles.Artillery.Type63"]       = "Type 63 RA",
    ["ACF.Missiles.FoldingFinRocket.40mm"]  = "40mmFFAR",
    ["ACF.Missiles.FoldingFinRocket.57mm"]  = "57mmFFAR",
    ["ACF.Missiles.FoldingFinRocket.70mm"]  = "70mmFFAR",
    ["ACF.Missiles.FoldingFinRocket.80mm"]  = "80mmFFAR",
    ["ACF.Missiles.FoldingFinRocket.Zuni"]  = "Zuni ASR",
    ["ACF.Missiles.FreeFallingBomb.1000kg"] = "1000kgBOMB",
    ["ACF.Missiles.FreeFallingBomb.100kg"]  = "100kgBOMB",
    ["ACF.Missiles.FreeFallingBomb.250kg"]  = "250kgBOMB",
    ["ACF.Missiles.FreeFallingBomb.500kg"]  = "500kgBOMB",
    ["ACF.Missiles.FreeFallingBomb.50kg"]   = "50kgBOMB",
    ["ACF.Missiles.GlidingBomb.100kg"]      = "100kgGBOMB",
    ["ACF.Missiles.GlidingBomb.250kg"]      = "250kgGBOMB",
    ["ACF.Missiles.GuidedBomb.227kg"]       = "227kgGBU",
    ["ACF.Missiles.GuidedBomb.454kg"]       = "454kgGBU",
    ["ACF.Missiles.GuidedBomb.909kg"]       = "909kgGBU",
    ["ACF.Missiles.GuidedBomb.Walleye"]     = "WalleyeGBU",
    ["ACF.Missiles.SurfaceToAir.FIM-92"]    = "FIM-92 SAM",
    ["ACF.Missiles.SurfaceToAir.Strela-1"]  = "Strela-1 SAM",
    ["ACF.Missiles.UnguidedRocket.HVAR"]    = "HVAR ASR",
    ["ACF.Missiles.UnguidedRocket.RS82"]    = "RS82 ASR",
    ["ACF.Missiles.UnguidedRocket.RW61"]    = "RW61 ASR",
    ["ACF.Missiles.UnguidedRocket.S-24"]    = "S-24 ASR",
    ["ACF.Missiles.UnguidedRocket.SPG-9"]   = "SPG-9 ASR",
}

-- This will return one of the following:
-- 1. If the FQN was previously available as a different type in legacy, then the previous name is given.
-- 2. If the FQN is new before the class rework, it passes it to FullyQualifiedNameToUnqualifiedName, which
--    will return a legacy-style class name.
-- This should only be used in places like API functions for user code (starfall, E2) where we don't want
-- to break really old E2's. It can also be used (conservatively) in some HUD functions like AIO.
function ACF.GetLegacyStyleClassName(FQN)
    return LegacyClassNames[FQN] or ACF.Classes.FullyQualifiedNameToUnqualifiedName(FQN) or ""
end

function ACF.GetSubtypeByLegacyStyleName(BaseFQN, Name)
    local Classes = ACF.Classes
    local Class   = Classes.GetSubtypeByName(BaseFQN, Name)
    if Class then return Class end

    for _, FQN in ipairs(Classes.GetSubtypeFQNs(BaseFQN)) do
        if ACF.GetLegacyStyleClassName(FQN) == Name then
            return Classes.GetTypeByName(FQN)
        end
    end
end

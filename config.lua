Config = {}

Config.GeneralSettings = {
    -- Lower values react faster; higher values use less client CPU.
    IdleScanInterval = 900,
    ArmedScanInterval = 650,
    AimingScanInterval = 350,

    MaxPedsPerScan = 9,
    ReactWhenPlayerInVehicle = true,   -- If set to false, NPCs will not react while the player is inside a vehicle and holding a weapon.

    Speech = {
        enabled = true,
        chance = 90,
        vehicleChance = 90
    },

    -- Keep enabled unless you intentionally want job/mission peds to react.
    IgnoreMissionPeds = true,
    IgnoreCops = true
}

Config.PedSettings = {
    Radius = 15.0,
    AimingRadius = 10.0,
    ClosePanicRadius = 7.0,

    -- Some NPCs hesitate for a short moment before running.
    HesitationChance = 10,

    ReactionCooldown = 25000,
    ServerSync = true,

    PanicSpread = {
        Enabled = true,
        Radius = 10.0,
        MaxPeds = 5
    },

    GangRetaliation = true
}

Config.VehicleSettings = {
    Enabled = true,
    Radius = 15.0,
    AimingRadius = 10.0,
    ClosePanicRadius = 7.0,
    ReactionCooldown = 25000,
    ServerSync = true
}

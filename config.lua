local Config = {}

Config.Seconds = function(Seconds) return Seconds * 1000 end

Config.Minutes = function(Minutes) return Minutes * 1000 * 60 end

Config.Debug = false

Config.Windows = {
    Side = { [0] = 0, [1] = 1, [2] = 2, [3] = 3 },
    Windscreen = 6,
    RearWindscreen = 7,
}

Config.Impact = {
    SampleIntervalMs = 50,
    IdleIntervalMs = 100,
    IdleSpeedMs = 1.0,
    PeakWindowMs = 150,
    CooldownMs = 1200,
    MinDeltaVelocityMs = 4.5,
    MaxDeltaVelocityMs = 30.0,
    VerticalWeight = 0.35,
    DamageWeight = 0.25,
    IgnoreAirborne = true,
    FrontArcDegrees = 45.0,
    RearArcDegrees = 135.0,
    SideWeights = { Front = 1.0, Left = 1.15, Right = 1.15, Rear = 0.85 },
    ExcludedClasses = { [14] = true, [15] = true, [16] = true, [21] = true },
    NoDoorClasses = { [8] = true, [13] = true },
}

Config.Severity = {
    { Name = 'Minor', MinScore = 12 },
    { Name = 'Moderate', MinScore = 30 },
    { Name = 'Severe', MinScore = 55 },
    { Name = 'Critical', MinScore = 80 },
}

Config.Seatbelt = {
    Enabled = true,
    Key = 'B',
    StateKey = 'seatbelt',
    BlockExit = true,
    ToggleDelayMs = 1200,
}

Config.Ejection = {
    Enabled = true,
    MinSpeedMs = 13.0,
    Chance = { [3] = 0.25, [4] = 0.7 },
    OpenChance = { [2] = 0.35, [3] = 0.7, [4] = 0.95 },
    VelocityFactor = 0.8,
    RagdollMs = 4500,
    HealthLossPercent = { 15, 35 },
}

Config.Doors = {
    Enabled = true,
    MinLevel = 2,
    LevelChance = { [2] = 0.35, [3] = 0.7, [4] = 0.95 },
    JamStrength = { [2] = { 20, 40 }, [3] = { 45, 70 }, [4] = { 75, 100 } },
    TearOffChance = { [3] = 0.1, [4] = 0.35 },
    HoodPopChance = { [3] = 0.5, [4] = 0.9 },
    HoodTearChance = { [4] = 0.4 },
    ClassMultiplier = { [18] = 0.7, [19] = 0.3, [20] = 0.8 },
    Zones = {
        Front = { { Door = 0, Weight = 0.4 }, { Door = 1, Weight = 0.4 } },
        Right = { { Door = 1, Weight = 1.0 }, { Door = 3, Weight = 0.9 } },
        Left = { { Door = 0, Weight = 1.0 }, { Door = 2, Weight = 0.9 } },
        Rear = { { Door = 2, Weight = 0.3 }, { Door = 3, Weight = 0.3 }, { Door = 5, Weight = 1.0 } },
    },
    EnforceIntervalMs = 250,
    TrackRange = 60.0,
    TrackScanMs = 2000,
    IdleScanMs = 10000,
}

Config.Trapped = {
    Enabled = true,
    MenuKey = 'G',
    ForceDoor = {
        CooldownMs = 2500,
        SkillCheck = { 'easy', 'easy' },
        StrengthRemoved = { 8, 16 },
        SelfDamage = { 2, 6 },
        AnimationMs = 1800,
    },
    BreakWindow = {
        Enabled = true,
        DurationMs = 3500,
        SelfDamage = { 3, 8 },
        OutsideDurationMs = 4500,
    },
    ClimbOutMs = 1800,
    CheckDurationMs = 2200,
    CallForHelpCooldownMs = Config.Seconds(60),
    OpenRoofStates = { [2] = true },
}

Config.Rescue = {
    PullDurationMs = 4000,
    JobDurationMultiplier = { police = 0.7, ambulance = 0.6, mechanic = 0.6, fire = 0.5 },
}

Config.Effects = {
    Enabled = true,
    BeltMultiplier = 0.5,
    BlurFadeOutMs = 3500.0,
    NearSideMultiplier = 1.25,
    FarSideMultiplier = 0.9,
    Levels = {
        [1] = { BlurMs = 600, ShakeAmplitude = 0.04, RingingMs = 0, DisorientMs = 0, StunMs = 0, BlackoutMs = 0 },
        [2] = { BlurMs = 2500, ShakeAmplitude = 0.12, RingingMs = 3000, DisorientMs = 0, StunMs = 350, BlackoutMs = 0 },
        [3] = { BlurMs = 6000, ShakeAmplitude = 0.3, RingingMs = 9000, DisorientMs = 8000, StunMs = 900, BlackoutMs = 700 },
        [4] = { BlurMs = 11000, ShakeAmplitude = 0.55, RingingMs = 16000, DisorientMs = 15000, StunMs = 1600, BlackoutMs = 1800 },
    },
    Ringing = {
        MuffleScene = 'DEATH_SCENE',
        Tone = { Name = 'Beep_Red', Set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS', IntervalMs = 2600 },
    },
    Disorient = {
        ShakeName = 'DRUNK_SHAKE',
        ShakeAmplitude = 0.9,
        WalkClipset = 'move_m@drunk@slightlydrunk',
        Timecycle = 'drug_drive_blend01',
        Strength = 0.6,
        EaseOutMs = 6000,
        WalkBlendOutSeconds = 3.0,
    },
    Blackout = { FadeOutMs = 120, FadeInMs = 1400 },
}

Config.Injuries = {
    Enabled = true,
    CanKill = false,
    BeltMultiplier = 0.4,
    HealthLossPercent = { [2] = { 2, 6 }, [3] = { 10, 22 }, [4] = { 25, 45 } },
}

Config.Deformation = {
    Enabled = true,
    DelayMs = 120,
    Points = { [2] = 1, [3] = 2, [4] = 3 },
    Damage = { [2] = 90.0, [3] = 220.0, [4] = 420.0 },
    Radius = { [2] = 0.9, [3] = 1.1, [4] = 1.4 },
    Jitter = 0.35,
    Height = 0.35,
}

Config.Vehicle = {
    Enabled = true,
    MinLevel = 2,
    Levels = {
        [2] = {
            EngineLoss = { 50, 150 },
            TireBurstChance = 0.1,
            Alarm = true,
        },
        [3] = {
            EngineLoss = { 150, 400 },
            TireBurstChance = 0.35,
            SteerBias = { 0.03, 0.08 },
            FuelLeakChance = 0.25,
            RadiatorLeakChance = 0.3,
            WindowSmashChance = 0.5,
            HornStuckChance = 0.15,
            StallEngine = true,
            Hazards = true,
            Alarm = true,
        },
        [4] = {
            EngineLoss = { 400, 700 },
            TireBurstChance = 0.6,
            SteerBias = { 0.06, 0.14 },
            FuelLeakChance = 0.5,
            RadiatorLeakChance = 0.6,
            WindowSmashChance = 0.85,
            HornStuckChance = 0.3,
            StallEngine = true,
            DisableEngineChance = 0.5,
            Hazards = true,
            Alarm = true,
        },
    },
    FuelLeak = { IntervalMs = Config.Seconds(5), PercentPerTick = { 0.6, 1.4 } },
    RadiatorLeak = { EngineHealthPerSecond = 4.0, MinEngineHealth = 120.0 },
    ExplosionGuard = { Enabled = true, MinTankHealth = 600.0, MinEngineHealth = 120.0 },
    HornDurationMs = Config.Seconds(25),
    AlarmDurationMs = Config.Seconds(30),
    HazardsDurationMs = Config.Minutes(5),
    MaintenanceIntervalMs = 1000,
    RepairBodyGain = 250.0,
}

Config.Debris = {
    Enabled = true,
    MinLevel = 2,
    MaxScenes = 20,
    MaxPiecesPerScene = 12,
    MergeDistance = 6.0,
    LifetimeMs = Config.Minutes(10),
    StreamDistance = 80.0,
    StreamIntervalMs = 1500,
    CreatesPerCycle = 4,
    PiecesPerLevel = { [2] = { 1, 2 }, [3] = { 2, 4 }, [4] = { 4, 6 } },
    Radius = { [2] = 3.0, [3] = 4.5, [4] = 6.0 },
    ScatterBias = 0.65,
    Kinds = {
        Part = {
            Weight = 5,
            Hazard = true,
            MinLevel = 2,
            Models = { 'prop_rub_carpart_02', 'prop_rub_carpart_03', 'prop_rub_carpart_04', 'prop_rub_carpart_05' },
        },
        Battery = { Weight = 1, Hazard = false, MinLevel = 3, Models = { 'prop_car_battery_01' } },
        Exhaust = { Weight = 1, Hazard = true, MinLevel = 3, Models = { 'prop_car_exhaust_01' } },
        Tyre = { Weight = 1, Hazard = false, MinLevel = 3, Models = { 'prop_rub_wheel_01', 'prop_rub_wheel_02' } },
        Panel = { Weight = 1, Hazard = false, MinLevel = 4, Models = { 'prop_car_bonnet_02', 'prop_car_seat' } },
    },
    DoorModels = { 'prop_car_door_01', 'prop_car_door_02', 'prop_car_door_03', 'prop_car_door_04' },
    HoodModels = { 'prop_car_bonnet_01', 'prop_car_bonnet_02' },
    Hazard = {
        Enabled = true,
        Radius = 1.8,
        TireBurstChance = 0.35,
        CheckIntervalMs = 400,
        CooldownMs = Config.Seconds(6),
        MinSpeedMs = 3.0,
    },
}

Config.Cleanup = {
    Enabled = true,
    ReachDistance = 3.0,
    TimePerPieceMs = 3500,
    ClaimTimeoutMs = Config.Seconds(25),
    Jobs = {},
    Animation = { Dict = 'anim@amb@drug_field_workers@rake@male_a@base', Clip = 'base', Flag = 1 },
    Broom = {
        Model = 'prop_tool_broom',
        Bone = 28422,
        Position = vec3(0.0, 0.0, 0.0),
        Rotation = vec3(0.0, 0.0, 0.0),
    },
    Payout = {
        Enabled = false,
        Account = 'money',
        Amount = { 4, 9 },
        MinSceneAgeMs = Config.Minutes(2),
        PiecesPerHour = 30,
        IgnoreOwnCrashes = true,
    },
}

Config.Dispatch = {
    Enabled = true,
    MinLevel = 3,
    Chance = { [3] = 0.5, [4] = 0.9 },
    DelayMs = { 4000, 12000 },
    Cooldown = Config.Seconds(45),
    MergeDistance = 40.0,
}

Config.Interactions = {
    VehicleDistance = 2.4,
    ZoneRadiusPadding = 1.0,
    ZoneDistance = 1.0,
    CheckAnimation = { Dict = 'mini@repair', Clip = 'fixing_a_ped', Flag = 1 },
    BreakAnimation = { Dict = 'melee@large_wpn@streamed_core', Clip = 'ground_attack_on_spot', Flag = 0 },
    DoorBones = {
        [0] = 'door_dside_f',
        [1] = 'door_pside_f',
        [2] = 'door_dside_r',
        [3] = 'door_pside_r',
        [5] = 'boot',
    },
}

Config.Server = {
    MaxImpactsPerMinute = 25,
    VehicleCooldownMs = 800,
    MaxDeltaVelocityMs = 80.0,
    MaxVehicleDistance = 12.0,
    ActionDistance = 6.0,
    ForceDoorMinIntervalMs = 1500,
    MinProgressFraction = 0.8,
    RepairClearDistance = 20.0,
}

Config.Commands = {
    Simulate = 'crashsim',
    Clear = 'crashclear',
    ClearDebris = 'crashdebris',
    Inspect = 'crashinfo',
}

return Config

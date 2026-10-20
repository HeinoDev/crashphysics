local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local Settings = Config.Vehicle

local RepairReported = {}
local HazardsStopped = {}

local function Resolve(NetId)
    if not NetworkDoesNetworkIdExist(NetId) then return nil end

    local Vehicle = NetworkGetEntityFromNetworkId(NetId)

    if Vehicle == 0 or not DoesEntityExist(Vehicle) then return nil end

    return Vehicle
end

local function SetHazards(Vehicle, On)
    SetVehicleIndicatorLights(Vehicle, 0, On)
    SetVehicleIndicatorLights(Vehicle, 1, On)
end

local function ApplyDoors(Vehicle, Doors)
    for _, Door in ipairs(Doors.Jammed or {}) do SetVehicleDoorShut(Vehicle, Door, true) end
    for _, Door in ipairs(Doors.Torn or {}) do SetVehicleDoorBroken(Vehicle, Door, true) end

    if Doors.HoodTorn then
        SetVehicleDoorBroken(Vehicle, Crash.HoodDoor, true)
    elseif Doors.HoodPopped then
        SetVehicleDoorOpen(Vehicle, Crash.HoodDoor, false, false)
    end
end

local function ApplyWindows(Vehicle, Windows)
    for _, Window in ipairs(Windows or {}) do
        local Index = CrashClient.WindowIndex(Window)

        if Index then SmashVehicleWindow(Vehicle, Index) end
    end
end

local function ApplyTires(Vehicle, Tires)
    for _, Tire in ipairs(Tires or {}) do SetVehicleTyreBurst(Vehicle, Tire, true, 1000.0) end
end

local function ApplyBodyLoss(Vehicle, Apply)
    if not Apply.BodyLoss then return end

    SetVehicleBodyHealth(Vehicle, math.max(0.0, GetVehicleBodyHealth(Vehicle) - Apply.BodyLoss))
end

local function ContactPoint(Vehicle, Angle)
    local Minimum, Maximum = GetModelDimensions(GetEntityModel(Vehicle))
    local Radians = math.rad(Angle or 0.0)
    local HalfWidth = (Maximum.x - Minimum.x) / 2.0
    local HalfLength = (Maximum.y - Minimum.y) / 2.0

    return vec3(math.sin(Radians) * HalfWidth, math.cos(Radians) * HalfLength, Config.Deformation.Height), HalfWidth
end

local function ApplyDeformation(Vehicle, Apply)
    local Deformation = Config.Deformation
    local Points = Deformation.Points[Apply.Level or 0]

    if not Deformation.Enabled or not Points then return end

    local Contact, HalfWidth = ContactPoint(Vehicle, Apply.Angle)
    local Sideways = math.abs(Contact.x) > math.abs(Contact.y)

    for _ = 1, Points do
        local Spread = (math.random() - 0.5) * 2.0 * Deformation.Jitter * HalfWidth
        local X = Contact.x + (Sideways and 0.0 or Spread)
        local Y = Contact.y + (Sideways and Spread or 0.0)
        local Damage = Deformation.Damage[Apply.Level] * (0.7 + math.random() * 0.6)

        SetVehicleDamage(Vehicle, X, Y, Contact.z, Damage, Deformation.Radius[Apply.Level], true)
    end
end

local function GuardExplosion(Vehicle)
    local Guard = Settings.ExplosionGuard

    if not Guard.Enabled then return end

    if GetVehiclePetrolTankHealth(Vehicle) < Guard.MinTankHealth then SetVehiclePetrolTankHealth(Vehicle, Guard.MinTankHealth) end
    if GetVehicleEngineHealth(Vehicle) < Guard.MinEngineHealth then SetVehicleEngineHealth(Vehicle, Guard.MinEngineHealth) end
end

local function ApplyVehicle(Vehicle, Apply, Doors)
    if Apply.EngineLoss and Apply.EngineLoss > 0 then
        SetVehicleEngineHealth(Vehicle, math.max(0.0, GetVehicleEngineHealth(Vehicle) - Apply.EngineLoss))
    end

    ApplyDoors(Vehicle, Doors)
    ApplyWindows(Vehicle, Apply.Windows)
    ApplyTires(Vehicle, Apply.Tires)

    if Apply.StallEngine then SetVehicleEngineOn(Vehicle, false, true, true) end
    if Apply.DisableEngine then SetVehicleUndriveable(Vehicle, true) end

    if Apply.Alarm then
        SetVehicleAlarm(Vehicle, true)
        SetVehicleAlarmTimeLeft(Vehicle, Settings.AlarmDurationMs)
        StartVehicleAlarm(Vehicle)
    end

    if Apply.HornStuck then StartVehicleHorn(Vehicle, Settings.HornDurationMs, joaat('HELDDOWN'), false) end

    if Apply.Hazards then
        HazardsStopped[CrashClient.NetId(Vehicle)] = nil
        SetHazards(Vehicle, true)
    end

    GuardExplosion(Vehicle)
end

RegisterNetEvent('crashphysics:client:vehicle', function(NetId, Apply, Doors)
    local Vehicle = Resolve(NetId)

    if not Vehicle or type(Apply) ~= 'table' or type(Doors) ~= 'table' then return end

    ApplyVehicle(Vehicle, Apply, Doors)
    ApplyBodyLoss(Vehicle, Apply)

    SetTimeout(Config.Deformation.DelayMs, function()
        if DoesEntityExist(Vehicle) then
            ApplyDeformation(Vehicle, Apply)
            GuardExplosion(Vehicle)
        end
    end)

    SetTimeout(600, function()
        if DoesEntityExist(Vehicle) then
            TriggerServerEvent('crashphysics:server:baseline', NetId, GetVehicleBodyHealth(Vehicle))
        end
    end)
end)

RegisterNetEvent('crashphysics:client:smashWindow', function(NetId, Window)
    local Vehicle = Resolve(NetId)
    local Index = Vehicle and CrashClient.WindowIndex(Window)

    if Index then SmashVehicleWindow(Vehicle, Index) end
end)

RegisterNetEvent('crashphysics:client:cleared', function(NetId)
    local Vehicle = Resolve(NetId)

    RepairReported[NetId] = nil
    HazardsStopped[NetId] = nil

    if not Vehicle then return end

    SetVehicleSteerBias(Vehicle, 0.0)
    SetVehicleDeformationFixed(Vehicle)
    SetVehicleUndriveable(Vehicle, false)
    SetHazards(Vehicle, false)
    SetVehicleAlarm(Vehicle, false)
end)

local function LeakRadiator(Vehicle, State)
    if State.Radiator ~= 1 or not GetIsVehicleEngineRunning(Vehicle) then return end

    local Leak = Settings.RadiatorLeak
    local Health = GetVehicleEngineHealth(Vehicle)

    if Health <= Leak.MinEngineHealth then return end

    local Loss = Leak.EngineHealthPerSecond * (Settings.MaintenanceIntervalMs / 1000.0)

    SetVehicleEngineHealth(Vehicle, math.max(Leak.MinEngineHealth, Health - Loss))
end

local function ExpireHazards(Vehicle, State, NetId)
    if State.Hazards ~= 1 or HazardsStopped[NetId] then return end

    local Age = GetCloudTimeAsInt() - (State.Time or 0)

    if Age * 1000 < Settings.HazardsDurationMs then return end

    HazardsStopped[NetId] = true
    SetHazards(Vehicle, false)
end

local function DetectRepair(Vehicle, State, NetId)
    if RepairReported[NetId] then return end
    if GetVehicleBodyHealth(Vehicle) < (State.Body or 1000.0) + Settings.RepairBodyGain then return end

    RepairReported[NetId] = true
    TriggerServerEvent('crashphysics:server:repaired', NetId)
end

local function Maintain(Vehicle)
    if not CrashClient.HasControl(Vehicle) then return end

    local State = CrashClient.State(Vehicle)

    if not State then return end

    local NetId = CrashClient.NetId(Vehicle)

    GuardExplosion(Vehicle)
    LeakRadiator(Vehicle, State)
    ExpireHazards(Vehicle, State, NetId)
    DetectRepair(Vehicle, State, NetId)
end

CreateThread(function()
    while true do
        local Tracked = CrashClient.Tracked()

        for _, Vehicle in ipairs(Tracked) do
            if DoesEntityExist(Vehicle) then Maintain(Vehicle) end
        end

        Wait(Settings.MaintenanceIntervalMs)
    end
end)

CreateThread(function()
    local Steer, Checked, Last = 0.0, 0, nil

    while true do
        local Vehicle = cache.vehicle

        if Vehicle and cache.seat == -1 then
            local Now = GetGameTimer()

            if Vehicle ~= Last or Now - Checked > 1000 then
                local State = CrashClient.State(Vehicle)

                Steer = State and State.Steer or 0.0
                Checked = Now
                Last = Vehicle
            end

            if Steer ~= 0 then
                SetVehicleSteerBias(Vehicle, Steer)
                Wait(0)
            else
                Wait(500)
            end
        else
            Steer, Last = 0.0, nil
            Wait(1000)
        end
    end
end)

local Config = lib.load('config')
local Crash = lib.load('shared.crash')

CrashVehicle = {}

local Leaking = {}
local LeakRunning = false

local TireZones = {
    Front = { 0, 1 },
    Left = { 0, 4 },
    Right = { 1, 5 },
    Rear = { 4, 5 },
}

local WindowZones = {
    Front = { 'Windscreen' },
    Left = { 0, 2 },
    Right = { 1, 3 },
    Rear = { 'RearWindscreen' },
}

local function RollList(List, Chance)
    local Picked = {}

    for _, Entry in ipairs(List or {}) do
        if math.random() < Chance then Picked[#Picked + 1] = Entry end
    end

    return Picked
end

local function RandomSign()
    return math.random() < 0.5 and -1.0 or 1.0
end

local function LeakTick()
    local Settings = Config.Vehicle.FuelLeak

    for NetId in pairs(Leaking) do
        local Vehicle = CrashState.GetVehicle(NetId)
        local State = Vehicle and CrashState.Read(Vehicle)

        if not State or State.Fuel ~= 1 then
            Leaking[NetId] = nil
        else
            local Fuel = Entity(Vehicle).state.fuel

            if type(Fuel) == 'number' and Fuel > 0 then
                Entity(Vehicle).state:set('fuel', math.max(0.0, Fuel - Crash.RandomBetween(Settings.PercentPerTick)), true)
            end
        end
    end
end

local function StartLeakThread()
    if LeakRunning then return end

    LeakRunning = true

    CreateThread(function()
        while next(Leaking) do
            Wait(Config.Vehicle.FuelLeak.IntervalMs)
            LeakTick()
        end

        LeakRunning = false
    end)
end

function CrashVehicle.TrackLeak(Vehicle)
    Leaking[NetworkGetNetworkIdFromEntity(Vehicle)] = true
    StartLeakThread()
end

function CrashVehicle.Resume(Vehicle)
    local State = CrashState.Read(Vehicle)

    if State and State.Fuel == 1 then CrashVehicle.TrackLeak(Vehicle) end
end

function CrashVehicle.Roll(State, Evaluation, Context)
    local Level = Evaluation.Level
    local Profile = Config.Vehicle.Levels[Level]
    local Apply = { Tires = {}, Windows = {}, Level = Level, Side = Evaluation.Side, Angle = Evaluation.Angle, BodyLoss = Context.BodyLoss }

    if not Config.Vehicle.Enabled or not Profile or Level < Config.Vehicle.MinLevel then return Apply end

    Apply.EngineLoss = Crash.RandomBetween(Profile.EngineLoss or { 0, 0 })
    Apply.Tires = RollList(TireZones[Evaluation.Side], Profile.TireBurstChance or 0.0)
    Apply.Alarm = Profile.Alarm == true
    Apply.StallEngine = Profile.StallEngine == true
    Apply.DisableEngine = math.random() < (Profile.DisableEngineChance or 0.0)

    if Context.HasWindows then
        Apply.Windows = RollList(WindowZones[Evaluation.Side], Profile.WindowSmashChance or 0.0)

        for _, Window in ipairs(Apply.Windows) do
            if type(Window) == 'number' then State.Window[Window + 1] = 1 end
        end
    end

    if Profile.SteerBias then
        State.Steer = RandomSign() * Crash.RandomBetween(Profile.SteerBias)
    end

    if math.random() < (Profile.FuelLeakChance or 0.0) then State.Fuel = 1 end
    if math.random() < (Profile.RadiatorLeakChance or 0.0) then State.Radiator = 1 end

    if Profile.Hazards then
        State.Hazards = 1
        Apply.Hazards = true
    end

    if math.random() < (Profile.HornStuckChance or 0.0) and Evaluation.Side == 'Front' then
        Apply.HornStuck = true
    end

    return Apply
end

function CrashVehicle.Describe(State)
    local Flags = {}

    if State.Fuel == 1 then Flags[#Flags + 1] = 'fuel' end
    if State.Radiator == 1 then Flags[#Flags + 1] = 'radiator' end
    if State.Steer ~= 0 then Flags[#Flags + 1] = 'steering' end

    return #Flags > 0 and table.concat(Flags, ',') or 'none'
end

AddEventHandler('onResourceStart', function(Resource)
    if Resource ~= GetCurrentResourceName() then return end

    for _, Vehicle in ipairs(GetAllVehicles()) do
        CrashVehicle.Resume(Vehicle)
    end
end)

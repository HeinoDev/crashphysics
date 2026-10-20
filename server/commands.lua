local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local Sides = { front = 'Front', rear = 'Rear', left = 'Left', right = 'Right' }

local function NearestVehicle(Source)
    local Ped = GetPlayerPed(Source)
    local Current = GetVehiclePedIsIn(Ped, false)

    if Current ~= 0 then return Current end

    local Coords = GetEntityCoords(Ped)
    local Best, BestDistance = nil, Config.Server.ActionDistance

    for _, Vehicle in ipairs(GetAllVehicles()) do
        local Distance = #(GetEntityCoords(Vehicle) - Coords)

        if Distance < BestDistance then Best, BestDistance = Vehicle, Distance end
    end

    return Best
end

local function Describe(State)
    local Doors = table.concat(CrashDoors.JammedList(State), ',')

    return ('Level %d | Jam: %s | Fuel leak: %s | Radiator: %s | Steer: %.2f'):format(
        State.Level, Doors ~= '' and Doors or '-', State.Fuel == 1 and 'yes' or 'no', State.Radiator == 1 and 'yes' or 'no', State.Steer)
end

lib.addCommand(Config.Commands.Simulate, {
    help = 'Simulate a crash on the nearest vehicle',
    restricted = 'group.admin',
    params = {
        { name = 'level', type = 'number', help = '1 Minor, 2 Moderate, 3 Severe, 4 Critical', optional = true },
        { name = 'side', type = 'string', help = 'front, rear, left or right', optional = true },
    },
}, function(Source, Args)
    local Vehicle = NearestVehicle(Source)

    if not Vehicle then return CrashState.Notify(Source, locale('Command.NoVehicle'), 'error') end

    local Level = math.floor(Crash.Clamp(Args.level or 3, 1, #Config.Severity))
    local Side = Sides[(Args.side or 'front'):lower()] or 'Front'

    CrashImpact.Simulate(Vehicle, Level, Side, Source)
    CrashState.Notify(Source, locale('Command.Simulated', Crash.LevelName(Level), Side), 'success')
end)

lib.addCommand(Config.Commands.Clear, {
    help = 'Clear crash state and nearby debris of the nearest vehicle',
    restricted = 'group.admin',
}, function(Source)
    local Vehicle = NearestVehicle(Source)

    if Vehicle then CrashState.Reset(Vehicle) end

    local Removed = CrashDebris.ClearNear(GetEntityCoords(GetPlayerPed(Source)), 30.0)

    CrashState.Notify(Source, locale('Command.Cleared', Removed), 'success')
end)

lib.addCommand(Config.Commands.ClearDebris, {
    help = 'Remove all crash debris',
    restricted = 'group.admin',
}, function(Source)
    CrashState.Notify(Source, locale('Command.Cleared', CrashDebris.ClearAll()), 'success')
end)

lib.addCommand(Config.Commands.Inspect, {
    help = 'Show the crash state of the nearest vehicle',
    restricted = 'group.admin',
}, function(Source)
    local Vehicle = NearestVehicle(Source)
    local State = Vehicle and CrashState.Read(Vehicle)

    if not State then return CrashState.Notify(Source, locale('Command.NoState'), 'inform') end

    CrashState.Notify(Source, Describe(State), 'inform', 10000)
end)

exports('ApplyCrash', function(NetId, Level, Side)
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle then return false end

    return CrashImpact.Simulate(Vehicle, math.floor(Crash.Clamp(Level or 3, 1, #Config.Severity)), Side or 'Front') ~= nil
end)

exports('GetCrashState', function(NetId)
    local Vehicle = CrashState.GetVehicle(NetId)

    return Vehicle and CrashState.Read(Vehicle) or nil
end)

exports('ClearVehicle', function(NetId)
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle then return false end

    CrashState.Reset(Vehicle)

    return true
end)

exports('JamDoor', function(NetId, Door, Strength)
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not Crash.IsFinite(Door) or Door < 0 or Door >= Crash.DoorCount then return false end

    local State = CrashState.ReadOrEmpty(Vehicle)

    State.Jam[Door + 1] = math.floor(Crash.Clamp(Strength or 60, 1, 100))
    State.Level = math.max(State.Level, 1)
    CrashState.Write(Vehicle, State)

    return true
end)

exports('FreeDoor', function(NetId, Door)
    local Vehicle = CrashState.GetVehicle(NetId)
    local State = Vehicle and CrashState.Read(Vehicle)

    if not State or not Crash.IsFinite(Door) or Door < 0 or Door >= Crash.DoorCount then return false end

    State.Jam[Door + 1] = 0
    CrashState.Write(Vehicle, State)

    return true
end)

exports('ClearDebris', function()
    return CrashDebris.ClearAll()
end)

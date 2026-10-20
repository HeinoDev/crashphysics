local Config = lib.load('config')
local Crash = lib.load('shared.crash')

lib.locale()

CrashState = {}

local ActionLog = {}

function CrashState.GetVehicle(NetId)
    if not Crash.IsFinite(NetId) then return nil end

    local Vehicle = NetworkGetEntityFromNetworkId(NetId)

    if not Vehicle or Vehicle == 0 or not DoesEntityExist(Vehicle) then return nil end
    if GetEntityType(Vehicle) ~= 2 then return nil end

    return Vehicle
end

function CrashState.Read(Vehicle)
    return Entity(Vehicle).state[Crash.StateKey]
end

function CrashState.ReadOrEmpty(Vehicle)
    return CrashState.Read(Vehicle) or Crash.EmptyState()
end

function CrashState.Write(Vehicle, State)
    Entity(Vehicle).state:set(Crash.StateKey, State, true)
end

function CrashState.Clear(Vehicle)
    Entity(Vehicle).state:set(Crash.StateKey, nil, true)
end

function CrashState.Plate(Vehicle)
    return (GetVehicleNumberPlateText(Vehicle) or ''):gsub('%s+$', '')
end

function CrashState.SeatOf(Vehicle, Ped)
    for Seat = -1, 8 do
        if GetPedInVehicleSeat(Vehicle, Seat) == Ped then return Seat end
    end

    return nil
end

function CrashState.Occupants(Vehicle)
    local List = {}

    for _, Player in ipairs(GetPlayers()) do
        local Source = tonumber(Player)
        local Ped = GetPlayerPed(Source)

        if Ped ~= 0 and GetVehiclePedIsIn(Ped, false) == Vehicle then
            local Seat = CrashState.SeatOf(Vehicle, Ped)

            if Seat then List[#List + 1] = { Source = Source, Ped = Ped, Seat = Seat } end
        end
    end

    return List
end

function CrashState.Distance(Source, Coords)
    local Ped = GetPlayerPed(Source)

    if Ped == 0 then return math.huge end

    return #(GetEntityCoords(Ped) - Coords)
end

function CrashState.NearVehicle(Source, Vehicle, Distance)
    return CrashState.Distance(Source, GetEntityCoords(Vehicle)) <= (Distance or Config.Server.ActionDistance)
end

function CrashState.IsOccupant(Source, Vehicle)
    local Ped = GetPlayerPed(Source)

    return Ped ~= 0 and GetVehiclePedIsIn(Ped, false) == Vehicle
end

function CrashState.Job(Source)
    local Player = ESX.GetPlayerFromId(Source)

    return Player and Player.job and Player.job.name or nil
end

function CrashState.Notify(Source, Message, Type, Duration)
    exports['heino_bridge']:Notify(Source, locale('Title'), Message, Type or 'inform', Duration or 6000)
end

function CrashState.IsBelted(Source)
    if not Config.Seatbelt.Enabled then return false end

    return Player(Source).state[Config.Seatbelt.StateKey] == true
end

function CrashState.BeginAction(Source, Action)
    Action.Start = GetGameTimer()
    ActionLog[Source] = Action
end

function CrashState.EndAction(Source, Kind)
    local Action = ActionLog[Source]

    ActionLog[Source] = nil

    if not Action or Action.Kind ~= Kind then return nil end

    local Needed = Action.Duration * Config.Server.MinProgressFraction

    if GetGameTimer() - Action.Start < Needed then return nil end

    return Action
end

function CrashState.CancelAction(Source)
    ActionLog[Source] = nil
end

AddEventHandler('playerDropped', function()
    ActionLog[source] = nil
end)

function CrashState.Reset(Vehicle)
    local Owner = NetworkGetEntityOwner(Vehicle)

    CrashState.Clear(Vehicle)

    if Owner and Owner > 0 then
        TriggerClientEvent('crashphysics:client:cleared', Owner, NetworkGetNetworkIdFromEntity(Vehicle))
    end
end

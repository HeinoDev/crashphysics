local Config = lib.load('config')
local Crash = lib.load('shared.crash')

lib.locale()

CrashClient = {}

local Tracked = {}
local Dirty = true

function CrashClient.Notify(Message, Type, Duration)
    exports['heino_bridge']:Notify(locale('Title'), Message, Type or 'inform', Duration or 6000)
end

function CrashClient.Debug(Message, ...)
    if not Config.Debug then return end

    print(('^3[crashphysics]^7 ' .. Message):format(...))
end

function CrashClient.State(Vehicle)
    if not Vehicle or Vehicle == 0 or not DoesEntityExist(Vehicle) then return nil end

    return Entity(Vehicle).state[Crash.StateKey]
end

function CrashClient.IsDead()
    return IsEntityDead(cache.ped) or LocalPlayer.state.dead == true or LocalPlayer.state.isDead == true
end

function CrashClient.Tracked()
    return Tracked
end

function CrashClient.HasControl(Vehicle)
    return NetworkHasControlOfEntity(Vehicle)
end

function CrashClient.NetId(Vehicle)
    return NetworkGetNetworkIdFromEntity(Vehicle)
end

function CrashClient.Hurt(Points)
    local Health = GetEntityHealth(cache.ped)
    local Floor = Config.Injuries.CanKill and 0 or 101

    SetEntityHealth(cache.ped, math.max(Floor, Health - math.floor(Points)))
end

function CrashClient.HurtPercent(Percent)
    local Life = math.max(0, GetEntityHealth(cache.ped) - 100)

    CrashClient.Hurt(Life * Percent / 100.0)
end

function CrashClient.SafeAnimation(Animation)
    if not Animation or not DoesAnimDictExist(Animation.Dict) then return nil end

    return { dict = Animation.Dict, clip = Animation.Clip, flag = Animation.Flag }
end

function CrashClient.Progress(Label, Duration, Animation, Prop)
    return lib.progressBar({
        duration = Duration,
        label = Label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = CrashClient.SafeAnimation(Animation),
        prop = Prop,
    })
end

function CrashClient.WindowIndex(Window)
    if Window == 'Windscreen' then return Config.Windows.Windscreen end
    if Window == 'RearWindscreen' then return Config.Windows.RearWindscreen end

    return Config.Windows.Side[Window]
end

function CrashClient.IsWindowIntact(Vehicle, Door)
    local Index = CrashClient.WindowIndex(Door)

    return Index == nil or IsVehicleWindowIntact(Vehicle, Index)
end

function CrashClient.OpenTop(Vehicle)
    if not IsVehicleAConvertible(Vehicle, false) then return false end

    return Config.Trapped.OpenRoofStates[GetConvertibleRoofState(Vehicle)] == true
end

function CrashClient.SeatName(Seat)
    if Seat == -1 then return locale('Seat.Driver') end
    if Seat == 0 then return locale('Seat.Front') end
    if Seat == 1 then return locale('Seat.RearLeft') end
    if Seat == 2 then return locale('Seat.RearRight') end

    return locale('Seat.Other', Seat + 1)
end

function CrashClient.JamLabel(Strength)
    if Strength >= 70 then return locale('Door.Mangled') end
    if Strength >= 35 then return locale('Door.Jammed') end

    return locale('Door.Stiff')
end

RegisterNetEvent('crashphysics:client:hurt', function(Points)
    if type(Points) == 'number' then CrashClient.Hurt(Points) end
end)

local function Scan()
    local Coords = GetEntityCoords(cache.ped)
    local Range = Config.Doors.TrackRange * Config.Doors.TrackRange
    local List = {}

    for _, Vehicle in ipairs(GetGamePool('CVehicle')) do
        local Delta = GetEntityCoords(Vehicle) - Coords
        local Near = Delta.x * Delta.x + Delta.y * Delta.y + Delta.z * Delta.z <= Range

        if Near and CrashClient.State(Vehicle) then List[#List + 1] = Vehicle end
    end

    Tracked = List
end

AddStateBagChangeHandler(Crash.StateKey, nil, function()
    Dirty = true
end)

CreateThread(function()
    local LastScan = 0

    while true do
        local Now = GetGameTimer()
        local Interval = #Tracked > 0 and Config.Doors.TrackScanMs or Config.Doors.IdleScanMs

        if Dirty or Now - LastScan >= Interval then
            Dirty = false
            LastScan = Now
            Scan()
        end

        Wait(500)
    end
end)

local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local Settings = Config.Interactions

local Busy = false

local function HasState(Vehicle)
    return not cache.vehicle and not Busy and not CrashClient.IsDead() and CrashClient.State(Vehicle) ~= nil
end

local function NearestJammedDoor(Vehicle)
    local State = CrashClient.State(Vehicle)

    if not State then return nil end

    local Coords = GetEntityCoords(cache.ped)
    local Best, BestDistance = nil, Settings.VehicleDistance

    for Door, Bone in pairs(Settings.DoorBones) do
        local Index = GetEntityBoneIndexByName(Vehicle, Bone)

        if Index ~= -1 and Crash.IsJammed(State, Door) then
            local Distance = #(GetWorldPositionOfEntityBone(Vehicle, Index) - Coords)

            if Distance <= BestDistance then Best, BestDistance = Door, Distance end
        end
    end

    return Best
end

local function OccupiedSeats(Vehicle)
    local Seats = {}

    for Seat = -1, 8 do
        local Ped = GetPedInVehicleSeat(Vehicle, Seat)

        if Ped ~= 0 and IsPedAPlayer(Ped) then Seats[#Seats + 1] = Seat end
    end

    return Seats
end

local function DoorLines(State, Vehicle)
    local Lines = {}

    for Door = 0, 3 do
        if GetIsDoorValid(Vehicle, Door) then
            local Label
            local Strength = Crash.JamOf(State, Door)

            if Crash.IsTorn(State, Door) or IsVehicleDoorDamaged(Vehicle, Door) then
                Label = locale('Door.Torn')
            elseif Strength > 0 then
                Label = CrashClient.JamLabel(Strength)
            else
                Label = locale('Door.Fine')
            end

            Lines[#Lines + 1] = ('- %s: **%s**'):format(locale('Door.Name' .. Door), Label)
        end
    end

    return Lines
end

local function ConditionLines(State, Vehicle)
    local Lines = {}

    if State.Fuel == 1 then Lines[#Lines + 1] = ('- %s'):format(locale('Check.FuelLeak')) end
    if State.Radiator == 1 then Lines[#Lines + 1] = ('- %s'):format(locale('Check.Radiator')) end
    if State.Steer and State.Steer ~= 0 then Lines[#Lines + 1] = ('- %s'):format(locale('Check.Steering')) end
    if #OccupiedSeats(Vehicle) > 0 then Lines[#Lines + 1] = ('- %s'):format(locale('Check.Occupied')) end

    return Lines
end

local function Inspect(Vehicle)
    Busy = true

    local Done = CrashClient.Progress(locale('Progress.Check'), Config.Trapped.CheckDurationMs, Settings.CheckAnimation)

    Busy = false

    if not Done or not DoesEntityExist(Vehicle) then return end

    local State = CrashClient.State(Vehicle)

    if not State then return CrashClient.Notify(locale('Check.Clean'), 'inform') end

    local Lines = DoorLines(State, Vehicle)

    for _, Line in ipairs(ConditionLines(State, Vehicle)) do Lines[#Lines + 1] = Line end

    lib.alertDialog({
        header = locale('Check.Header'),
        content = table.concat(Lines, '\n'),
        centered = true,
        cancel = false,
    })
end

local function SmashOutside(Vehicle)
    local Door = NearestJammedDoor(Vehicle)

    if not Door or Door > 3 then return end

    local Begin = lib.callback.await('crashphysics:server:windowBegin', false, CrashClient.NetId(Vehicle), Door, false)

    if not Begin or not Begin.Ok then
        return CrashClient.Notify(locale('Window.Cannot'), 'error')
    end

    Busy = true

    local Done = CrashClient.Progress(locale('Progress.BreakWindow'), Begin.Duration, Settings.BreakAnimation)

    Busy = false

    if Done then
        lib.callback.await('crashphysics:server:windowEnd', false)
    else
        TriggerServerEvent('crashphysics:server:cancelAction')
    end
end

local function Pull(Vehicle, Target)
    local Begin = lib.callback.await('crashphysics:server:pullBegin', false, CrashClient.NetId(Vehicle), Target)

    if not Begin or not Begin.Ok then
        return CrashClient.Notify(Begin and Begin.Reason == 'Trapped' and locale('Rescue.StillTrapped') or locale('Rescue.Cannot'), 'error')
    end

    Busy = true

    local Done = CrashClient.Progress(locale('Progress.Pull'), Begin.Duration, Settings.CheckAnimation)

    Busy = false

    if not Done then return TriggerServerEvent('crashphysics:server:cancelAction') end

    if lib.callback.await('crashphysics:server:pullEnd', false) then
        CrashClient.Notify(locale('Rescue.Pulled'), 'success')
    end
end

local function OpenOccupants(Vehicle)
    local List = lib.callback.await('crashphysics:server:occupants', false, CrashClient.NetId(Vehicle))

    if not List or #List == 0 then return CrashClient.Notify(locale('Rescue.Empty'), 'inform') end

    local Options = {}

    for _, Entry in ipairs(List) do
        local Description = Entry.CanPull and locale('Rescue.Ready') or locale('Rescue.StillTrapped')

        if Entry.Dead then Description = Description .. ' | ' .. locale('Rescue.Unresponsive') end

        Options[#Options + 1] = {
            title = CrashClient.SeatName(Entry.Seat),
            description = Description,
            icon = Entry.Dead and 'fa-solid fa-user-injured' or 'fa-solid fa-user',
            disabled = not Entry.CanPull,
            onSelect = function() Pull(Vehicle, Entry.Target) end,
        }
    end

    lib.registerContext({ id = 'crashphysics_occupants', title = locale('Rescue.Title'), options = Options })
    lib.showContext('crashphysics_occupants')
end

local function HasOccupants(Vehicle)
    return HasState(Vehicle) and #OccupiedSeats(Vehicle) > 0
end

local function HasJammedWindow(Vehicle)
    if not HasState(Vehicle) or not Config.Trapped.BreakWindow.Enabled then return false end

    local Door = NearestJammedDoor(Vehicle)

    return Door ~= nil and Door <= 3 and CrashClient.IsWindowIntact(Vehicle, Door)
end

exports['ox_target']:addGlobalVehicle({
    {
        name = 'crashphysics:inspect',
        icon = 'fa-solid fa-magnifying-glass',
        label = locale('Target.Inspect'),
        distance = Settings.VehicleDistance,
        canInteract = function(Vehicle) return HasState(Vehicle) end,
        onSelect = function(Data) Inspect(Data.entity) end,
    },
    {
        name = 'crashphysics:smash',
        icon = 'fa-solid fa-burst',
        label = locale('Target.Smash'),
        distance = Settings.VehicleDistance,
        canInteract = function(Vehicle) return HasJammedWindow(Vehicle) end,
        onSelect = function(Data) SmashOutside(Data.entity) end,
    },
    {
        name = 'crashphysics:occupants',
        icon = 'fa-solid fa-truck-medical',
        label = locale('Target.Occupants'),
        distance = Settings.VehicleDistance,
        canInteract = function(Vehicle) return HasOccupants(Vehicle) end,
        onSelect = function(Data) OpenOccupants(Data.entity) end,
    },
})

AddEventHandler('onResourceStop', function(Resource)
    if Resource ~= GetCurrentResourceName() then return end

    exports['ox_target']:removeGlobalVehicle({
        'crashphysics:inspect',
        'crashphysics:smash',
        'crashphysics:occupants',
    })
end)

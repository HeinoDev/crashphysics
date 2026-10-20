local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local LastDeniedHint = 0

local function EnforceVehicle(Vehicle)
    if not CrashClient.HasControl(Vehicle) then return end

    local State = CrashClient.State(Vehicle)

    if not State then return end

    for Door = 0, Crash.DoorCount - 1 do
        if Crash.IsJammed(State, Door) and GetVehicleDoorAngleRatio(Vehicle, Door) > 0.05 then
            SetVehicleDoorShut(Vehicle, Door, true)
        end
    end
end

local function DenyEntry(Vehicle, Seat)
    local State = CrashClient.State(Vehicle)

    if not State or not Crash.IsJammed(State, Crash.DoorForSeat(Seat)) then return end

    ClearPedTasks(cache.ped)

    if GetGameTimer() - LastDeniedHint < 3000 then return end

    LastDeniedHint = GetGameTimer()
    CrashClient.Notify(locale('Door.EntryJammed'), 'error', 3500)
end

CreateThread(function()
    while true do
        local Tracked = CrashClient.Tracked()

        for _, Vehicle in ipairs(Tracked) do
            if DoesEntityExist(Vehicle) then EnforceVehicle(Vehicle) end
        end

        Wait(#Tracked > 0 and Config.Doors.EnforceIntervalMs or 1000)
    end
end)

CreateThread(function()
    while true do
        local Sleep = 1000

        if #CrashClient.Tracked() > 0 and not cache.vehicle then
            Sleep = 100

            local Vehicle = GetVehiclePedIsTryingToEnter(cache.ped)

            if Vehicle ~= 0 then DenyEntry(Vehicle, GetSeatPedIsTryingToEnter(cache.ped)) end
        end

        Wait(Sleep)
    end
end)

local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local Settings = Config.Trapped

local Trapped = false
local HintShown = false
local Busy = false
local LastForce = 0
local LastExitHint = 0

local function CurrentDoor()
    return cache.seat and Crash.DoorForSeat(cache.seat) or nil
end

local function WindowRoute(Vehicle, Door)
    return Door ~= nil and Door <= 3 and not CrashClient.IsWindowIntact(Vehicle, Door)
end

local function ComputeTrapped()
    local Vehicle = cache.vehicle

    if not Settings.Enabled or not Vehicle then return false end
    if CrashClient.OpenTop(Vehicle) then return false end

    local State = CrashClient.State(Vehicle)
    local Door = CurrentDoor()

    if not State or not Door then return false end

    return Crash.IsJammed(State, Door)
end

local function SetHint(Visible)
    if Visible == HintShown then return end

    HintShown = Visible

    if Visible then
        lib.showTextUI(locale('Trapped.Hint', Settings.MenuKey), { icon = 'fa-solid fa-car-burst' })
    else
        lib.hideTextUI()
    end
end

local function Refresh()
    Trapped = ComputeTrapped()
    SetHint(Trapped and not CrashClient.IsDead())
end

local function EndBusy()
    Busy = false
end

local function ClimbOut()
    local Vehicle = cache.vehicle

    if not Vehicle or Busy then return end

    Busy = true

    local Done = CrashClient.Progress(locale('Progress.ClimbOut'), Settings.ClimbOutMs)

    if Done and cache.vehicle == Vehicle then
        CrashClient.Unbelt()
        TaskLeaveVehicle(cache.ped, Vehicle, 4160)
    end

    EndBusy()
end

local function ForceDoor()
    local Vehicle = cache.vehicle
    local Force = Settings.ForceDoor

    if not Vehicle or Busy or GetGameTimer() - LastForce < Force.CooldownMs then return end

    Busy = true
    LastForce = GetGameTimer()

    CrashClient.Unbelt()

    local Done = CrashClient.Progress(locale('Progress.Force'), Force.AnimationMs)
    local Success = Done and lib.skillCheck(Force.SkillCheck, { 'w', 'a', 's', 'd' })

    if Done then TriggerServerEvent('crashphysics:server:forceDoor', CrashClient.NetId(Vehicle), Success == true) end

    EndBusy()
end

local function BreakWindow()
    local Vehicle = cache.vehicle
    local Door = CurrentDoor()

    if not Vehicle or not Door or Door > 3 or Busy then return end

    local Begin = lib.callback.await('crashphysics:server:windowBegin', false, CrashClient.NetId(Vehicle), Door, true)

    if not Begin or not Begin.Ok then return CrashClient.Notify(locale('Window.Cannot'), 'error') end

    Busy = true

    CrashClient.Unbelt()

    local Done = CrashClient.Progress(locale('Progress.BreakWindow'), Begin.Duration)

    if Done then
        lib.callback.await('crashphysics:server:windowEnd', false)
    else
        TriggerServerEvent('crashphysics:server:cancelAction')
    end

    EndBusy()
end

local function CallForHelp()
    if cache.vehicle then TriggerServerEvent('crashphysics:server:callHelp', CrashClient.NetId(cache.vehicle)) end
end

local function OpenMenu()
    local Vehicle = cache.vehicle

    if not Trapped or not Vehicle or Busy or CrashClient.IsDead() then return end

    local Door = CurrentDoor()
    local CanBreak = Settings.BreakWindow.Enabled and Door <= 3 and CrashClient.IsWindowIntact(Vehicle, Door)
    local CanClimb = WindowRoute(Vehicle, Door)

    lib.registerContext({
        id = 'crashphysics_trapped',
        title = locale('Trapped.Title'),
        options = {
            { title = locale('Menu.Force'), description = locale('Menu.ForceDescription'), icon = 'fa-solid fa-hand-fist', onSelect = ForceDoor },
            { title = locale('Menu.BreakWindow'), description = locale('Menu.BreakWindowDescription'), icon = 'fa-solid fa-burst', disabled = not CanBreak, onSelect = BreakWindow },
            { title = locale('Menu.ClimbOut'), description = locale('Menu.ClimbOutDescription'), icon = 'fa-solid fa-person-walking-arrow-right', disabled = not CanClimb, onSelect = ClimbOut },
            { title = locale('Menu.Help'), description = locale('Menu.HelpDescription'), icon = 'fa-solid fa-phone', onSelect = CallForHelp },
        },
    })

    lib.showContext('crashphysics_trapped')
end

local function IsExitBlocked()
    local Vehicle = cache.vehicle

    if not Vehicle then return false end
    if Config.Seatbelt.BlockExit and CrashClient.IsBelted() then return true end

    return Trapped
end

local function OnExitDenied()
    local Now = GetGameTimer()

    if CrashClient.IsBelted() then
        if Now - LastExitHint > 1500 then
            LastExitHint = Now
            CrashClient.Notify(locale('Seatbelt.StillOn', Config.Seatbelt.Key), 'inform', 3000)
        end

        return
    end

    if WindowRoute(cache.vehicle, CurrentDoor()) then return ClimbOut() end

    if Now - LastExitHint > 2500 then
        LastExitHint = Now
        CrashClient.Notify(locale('Trapped.Jammed', Settings.MenuKey), 'error', 4000)
    end
end

lib.addKeybind({
    name = 'crashphysics_trapped_menu',
    description = locale('Trapped.Keybind'),
    defaultKey = Settings.MenuKey,
    onPressed = OpenMenu,
})

CreateThread(function()
    while true do
        local Sleep = cache.vehicle and 250 or 1000

        if cache.vehicle and IsExitBlocked() then
            Sleep = 0
            DisableControlAction(0, 75, true)

            if IsDisabledControlJustPressed(0, 75) and not Busy then OnExitDenied() end
        end

        Wait(Sleep)
    end
end)

CreateThread(function()
    while true do
        Refresh()
        Wait(cache.vehicle and 750 or 2000)
    end
end)

lib.onCache('vehicle', function()
    Trapped = false
    Busy = false
    SetHint(false)
    Refresh()
end)

lib.onCache('seat', function()
    Refresh()
end)

AddStateBagChangeHandler(Crash.StateKey, nil, function(BagName)
    local Vehicle = GetEntityFromStateBagName(BagName)

    if Vehicle ~= 0 and Vehicle == cache.vehicle then Refresh() end
end)

AddEventHandler('onResourceStop', function(Resource)
    if Resource == GetCurrentResourceName() then SetHint(false) end
end)

exports('IsTrapped', function() return Trapped end)

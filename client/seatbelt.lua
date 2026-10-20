local Config = lib.load('config')

local Belted = false
local LastToggle = 0

local FlyThroughWindscreenFlag = 32

local function Apply(State)
    Belted = State

    SetPedConfigFlag(cache.ped, FlyThroughWindscreenFlag, not State)
    TriggerServerEvent('crashphysics:server:belt', State)
    TriggerEvent('crashphysics:client:seatbelt', State)
end

local function Toggle()
    local Vehicle = cache.vehicle

    if not Vehicle or Config.Impact.NoDoorClasses[GetVehicleClass(Vehicle)] then return end
    if CrashClient.IsDead() then return end
    if GetGameTimer() - LastToggle < Config.Seatbelt.ToggleDelayMs then return end

    LastToggle = GetGameTimer()

    Apply(not Belted)
    PlaySoundFrontend(-1, Belted and 'NAV_UP_DOWN' or 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    CrashClient.Notify(Belted and locale('Seatbelt.On') or locale('Seatbelt.Off'), Belted and 'success' or 'inform', 2500)
end

function CrashClient.IsBelted()
    return Belted
end

function CrashClient.Unbelt()
    if Belted then Apply(false) end
end

if Config.Seatbelt.Enabled then
    lib.addKeybind({
        name = 'crashphysics_seatbelt',
        description = locale('Seatbelt.Keybind'),
        defaultKey = Config.Seatbelt.Key,
        onPressed = Toggle,
    })

    lib.onCache('vehicle', function(Vehicle)
        if not Vehicle and Belted then Apply(false) end
    end)
end

exports('IsBelted', function() return Belted end)

local Config = lib.load('config')

local Settings = Config.Effects

local Until = { Blur = 0, Ringing = 0, Disorient = 0, Stun = 0 }
local Active = { Blur = false, Ringing = false, Disorient = false }
local Running = false
local DisorientAmplitude = 0.0
local Easing = false
local NextTone = 0

local StunControls = { 71, 72, 59, 63, 64, 76, 30, 31, 21, 22, 24, 25 }

local function Extend(Key, Duration)
    if Duration <= 0 then return end

    Until[Key] = math.max(Until[Key], GetGameTimer() + Duration)
end

local function StartBlur()
    if Active.Blur then return end

    Active.Blur = true
    TriggerScreenblurFadeIn(400.0)
end

local function StopBlur()
    Active.Blur = false
    TriggerScreenblurFadeOut(Settings.BlurFadeOutMs)
end

local function StartRinging()
    if Active.Ringing then return end

    Active.Ringing = true
    StartAudioScene(Settings.Ringing.MuffleScene)
end

local function StopRinging()
    Active.Ringing = false
    StopAudioScene(Settings.Ringing.MuffleScene)
end

local function PlayTone(Now)
    local Tone = Settings.Ringing.Tone

    if not Tone or Now < NextTone then return end

    NextTone = Now + Tone.IntervalMs
    PlaySoundFrontend(-1, Tone.Name, Tone.Set, true)
end

local function StartDisorient(Scale)
    if Active.Disorient then return end

    local Disorient = Settings.Disorient

    Active.Disorient = true
    DisorientAmplitude = Disorient.ShakeAmplitude * math.min(Scale, 1.0)
    ShakeGameplayCam(Disorient.ShakeName, DisorientAmplitude)
    SetTimecycleModifier(Disorient.Timecycle)
    SetTimecycleModifierStrength(Disorient.Strength)

    if Disorient.WalkClipset and Disorient.WalkClipset ~= '' then
        lib.requestAnimSet(Disorient.WalkClipset, 1000)
        SetPedMovementClipset(cache.ped, Disorient.WalkClipset, 0.5)
    end
end

local function StopDisorient()
    Active.Disorient = false
    StopGameplayCamShaking(true)
    ClearTimecycleModifier()
    ResetPedMovementClipset(cache.ped, Settings.Disorient.WalkBlendOutSeconds)
end

local function StopAll()
    if Active.Blur then StopBlur() end
    if Active.Ringing then StopRinging() end
    if Active.Disorient then StopDisorient() end

    for Key in pairs(Until) do Until[Key] = 0 end
end

local function DisableStunControls()
    for _, Control in ipairs(StunControls) do DisableControlAction(0, Control, true) end
end

local function EaseDisorient(Now)
    local Disorient = Settings.Disorient
    local Factor = math.min(1.0, math.max(0.0, (Until.Disorient - Now) / Disorient.EaseOutMs))

    if Factor >= 1.0 then return false end

    SetTimecycleModifierStrength(Disorient.Strength * Factor)
    SetGameplayCamShakeAmplitude(DisorientAmplitude * Factor)

    return true
end

local function Tick()
    local Now = GetGameTimer()

    if CrashClient.IsDead() then return StopAll() end

    if Active.Blur and Now >= Until.Blur then StopBlur() end
    if Active.Ringing and Now >= Until.Ringing then StopRinging() end
    if Active.Disorient and Now >= Until.Disorient then StopDisorient() end
    if Active.Ringing then PlayTone(Now) end

    Easing = Active.Disorient and EaseDisorient(Now)

    return Now < Until.Stun
end

local function RunManager()
    if Running then return end

    Running = true

    CreateThread(function()
        while Active.Blur or Active.Ringing or Active.Disorient or GetGameTimer() < Until.Stun do
            local Stunned = Tick()

            if Stunned then
                DisableStunControls()
                Wait(0)
            else
                Wait(Easing and 100 or 200)
            end
        end

        Running = false
    end)
end

local function Blackout(Duration)
    if Duration <= 0 then return end

    CreateThread(function()
        DoScreenFadeOut(Settings.Blackout.FadeOutMs)
        Wait(Settings.Blackout.FadeOutMs + Duration)
        DoScreenFadeIn(Settings.Blackout.FadeInMs)
    end)
end

local function Jolt(Amplitude)
    ShakeGameplayCam('JOLT_SHAKE', Amplitude)

    SetTimeout(500, function()
        if not Active.Disorient then StopGameplayCamShaking(true) end
    end)
end

local function ApplyProfile(Level, Scale)
    local Profile = Settings.Levels[Level]

    if not Settings.Enabled or not Profile then return end

    Jolt(Profile.ShakeAmplitude * Scale)

    if Profile.BlurMs > 0 then
        StartBlur()
        Extend('Blur', Profile.BlurMs * Scale)
    end

    if Profile.RingingMs > 0 then
        StartRinging()
        Extend('Ringing', Profile.RingingMs * Scale)
    end

    if Profile.DisorientMs > 0 then
        StartDisorient(Scale)
        Extend('Disorient', Profile.DisorientMs * Scale + Settings.Disorient.EaseOutMs)
    end

    Extend('Stun', Profile.StunMs * Scale)
    Blackout(Profile.BlackoutMs * Scale)
    RunManager()
end

local function ExitThroughWindscreen(Payload)
    local Ped = cache.ped
    local Vehicle = cache.vehicle

    if not Vehicle then return end

    local Velocity = Payload.Velocity or { x = 0.0, y = 0.0, z = 0.0 }
    local Left = Payload.Seat % 2 == 1 and -0.4 or 0.4
    local Offset = GetOffsetFromEntityInWorldCoords(Vehicle, Left, 1.6, 0.6)

    TaskLeaveVehicle(Ped, Vehicle, 4160)

    local Attempts = 0

    while IsPedInAnyVehicle(Ped, false) and Attempts < 15 do
        Attempts = Attempts + 1
        Wait(20)
    end

    SetEntityCoords(Ped, Offset.x, Offset.y, Offset.z, false, false, false, false)
    SetPedToRagdoll(Ped, Config.Ejection.RagdollMs, Config.Ejection.RagdollMs, 0, false, false, false)
    SetEntityVelocity(Ped, Velocity.x * Config.Ejection.VelocityFactor, Velocity.y * Config.Ejection.VelocityFactor, Velocity.z + 2.0)
end

RegisterNetEvent('crashphysics:client:occupant', function(Payload)
    if type(Payload) ~= 'table' or not cache.vehicle then return end
    if CrashClient.NetId(cache.vehicle) ~= Payload.NetId then return end

    if Payload.Damage and Payload.Damage > 0 then CrashClient.HurtPercent(Payload.Damage) end

    if Payload.Eject then
        CreateThread(function() ExitThroughWindscreen(Payload) end)
    end

    ApplyProfile(Payload.Level, Payload.Intensity or 1.0)

    if Payload.Trapped then CrashClient.Notify(locale('Trapped.Notify'), 'error', 9000) end

    TriggerEvent('crashphysics:client:impactFelt', Payload.Level, Payload.Score)
end)

RegisterNetEvent('crashphysics:client:pulled', function(NetId)
    local Vehicle = cache.vehicle

    if not Vehicle or CrashClient.NetId(Vehicle) ~= NetId then return end

    TaskLeaveVehicle(cache.ped, Vehicle, 4160)
    Wait(300)
    SetPedToRagdoll(cache.ped, 1500, 1500, 0, false, false, false)
    CrashClient.Notify(locale('Rescue.PulledOut'), 'success')
end)

AddEventHandler('onResourceStop', function(Resource)
    if Resource ~= GetCurrentResourceName() then return end

    StopAll()
    DoScreenFadeIn(0)
end)

exports('ClearEffects', StopAll)

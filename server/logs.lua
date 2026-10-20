CrashLogs = {}

local Webhook = ''

local function Send(Source, Message, Color)
    if Webhook == '' then return end

    exports['heino_bridge']:DiscordWebhook(Source, {
        Webhook = Webhook,
        Resource = 'Heino-CrashPhysics',
        Message = Message,
        Color = Color
    })
end

function CrashLogs.Impact(Source, Plate, Evaluation, JammedDoors)
    Send(Source, ('Kollision: **%s** (%s) | Plade: %s | Delta-V: %.1f m/s | Score: %.0f | Fastklemte døre: %s'):format(
        Evaluation.LevelName, Evaluation.Side, Plate, Evaluation.DeltaV, Evaluation.Score, JammedDoors))
end

function CrashLogs.Trapped(Source, Plate)
    Send(Source, ('Passagerer er fanget i køretøj %s'):format(Plate), 15105570)
end

function CrashLogs.DoorFreed(Source, Plate, Door, Method)
    Send(Source, ('Dør %s på %s blev frigjort med %s'):format(Door, Plate, Method), 3066993)
end

function CrashLogs.Pulled(Source, TargetName, Plate)
    Send(Source, ('%s blev trukket ud af %s'):format(TargetName, Plate), 3066993)
end

function CrashLogs.Cleanup(Source, Pieces)
    Send(Source, ('Fjernede %s vragdele'):format(Pieces))
end

function CrashLogs.AntiCheat(Source, Message)
    print(('^3[crashphysics]^7 Suspicious (%s): %s'):format(Source, Message))
    Send(Source, Message, 15548997)
end

local Config = lib.load('config')
local Crash = lib.load('shared.crash')

CrashDispatch = {}

local Recent = {}
local HelpCalls = {}

local function IsAvailable()
    return Config.Dispatch.Enabled
end

local function IsDuplicate(Coords)
    local Now = GetGameTimer()

    for Index = #Recent, 1, -1 do
        local Entry = Recent[Index]

        if Now - Entry.Time >= Config.Dispatch.Cooldown then
            table.remove(Recent, Index)
        elseif #(Entry.Coords - Coords) <= Config.Dispatch.MergeDistance then
            return true
        end
    end

    return false
end

local function Send(Coords, Text)
end

function CrashDispatch.Crash(Coords, Level, Trapped)
    if not IsAvailable() or Level < Config.Dispatch.MinLevel then return end
    if math.random() >= (Config.Dispatch.Chance[Level] or 0.0) then return end
    if IsDuplicate(Coords) then return end

    Recent[#Recent + 1] = { Coords = Coords, Time = GetGameTimer() }

    local Text = Trapped and locale('Dispatch.Trapped') or locale('Dispatch.Crash')

    SetTimeout(Crash.RandomInt(Config.Dispatch.DelayMs), function() Send(Coords, Text) end)
end

function CrashDispatch.Help(Source, Coords)
    local Now = GetGameTimer()

    if HelpCalls[Source] and Now - HelpCalls[Source] < Config.Trapped.CallForHelpCooldownMs then return false end

    HelpCalls[Source] = Now

    Send(Coords, locale('Dispatch.Help'))

    return true
end

AddEventHandler('playerDropped', function()
    HelpCalls[source] = nil
end)

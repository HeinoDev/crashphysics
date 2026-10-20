local Config = lib.load('config')
local Crash = lib.load('shared.crash')

CrashDoors = {}

function CrashDoors.Roll(State, Evaluation, Context)
    local Result = { Jammed = {}, Torn = {}, HoodPopped = false, HoodTorn = false }
    local Level = Evaluation.Level

    if not Config.Doors.Enabled or Level < Config.Doors.MinLevel then return Result end
    if Config.Impact.NoDoorClasses[Context.Class] then return Result end

    local Multiplier = Config.Doors.ClassMultiplier[Context.Class] or 1.0
    local Chance = (Config.Doors.LevelChance[Level] or 0.0) * Multiplier
    local Zones = Config.Doors.Zones[Evaluation.Side] or {}

    for _, Zone in ipairs(Zones) do
        local Door = Zone.Door
        local Eligible = Context.Doors[Door] and not Crash.IsTorn(State, Door)

        if Eligible and math.random() < Chance * Zone.Weight then
            local Added = Crash.RandomInt(Config.Doors.JamStrength[Level])

            State.Jam[Door + 1] = math.min(100, State.Jam[Door + 1] + Added)

            if math.random() < (Config.Doors.TearOffChance[Level] or 0.0) then
                State.Torn[Door + 1] = 1
                State.Jam[Door + 1] = 0
                Result.Torn[#Result.Torn + 1] = Door
            else
                Result.Jammed[#Result.Jammed + 1] = Door
            end
        end
    end

    local HoodEligible = Evaluation.Side == 'Front' and Context.Doors[Crash.HoodDoor] and not Crash.IsTorn(State, Crash.HoodDoor)

    if HoodEligible and math.random() < (Config.Doors.HoodPopChance[Level] or 0.0) then
        Result.HoodPopped = true

        if math.random() < (Config.Doors.HoodTearChance[Level] or 0.0) then
            State.Torn[Crash.HoodDoor + 1] = 1
            Result.HoodTorn = true
        end
    end

    return Result
end

function CrashDoors.JammedList(State)
    local List = {}

    for Door = 0, Crash.DoorCount - 1 do
        if Crash.IsJammed(State, Door) then List[#List + 1] = Door end
    end

    return List
end

function CrashDoors.ReduceJam(State, Door, Amount)
    State.Jam[Door + 1] = math.max(0, State.Jam[Door + 1] - math.floor(Amount))

    return State.Jam[Door + 1] == 0
end

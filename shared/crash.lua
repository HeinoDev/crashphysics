local Config = lib.load('config')

local Crash = {}

Crash.StateKey = 'crashphysics'
Crash.DoorCount = 6
Crash.HoodDoor = 4
Crash.TrunkDoor = 5

function Crash.Clamp(Value, Min, Max)
    return math.min(math.max(Value, Min), Max)
end

function Crash.IsFinite(Value)
    return type(Value) == 'number' and Value == Value and Value > -1e9 and Value < 1e9
end

function Crash.RandomBetween(Range)
    if type(Range) ~= 'table' then return Range end

    return Range[1] + (Range[2] - Range[1]) * math.random()
end

function Crash.RandomInt(Range)
    return math.random(math.floor(Range[1]), math.floor(Range[2]))
end

function Crash.DoorForSeat(Seat)
    if Seat == -1 then return 0 end
    if Seat == 0 then return 1 end

    return Seat % 2 == 1 and 2 or 3
end

function Crash.SeatIsLeft(Seat)
    return Seat % 2 == 1
end

function Crash.SeatIsFront(Seat)
    return Seat <= 0
end

function Crash.SideFromAngle(Angle)
    local Absolute = math.abs(Angle)

    if Absolute <= Config.Impact.FrontArcDegrees then return 'Front' end
    if Absolute >= Config.Impact.RearArcDegrees then return 'Rear' end

    return Angle > 0 and 'Right' or 'Left'
end

function Crash.LevelFromScore(Score)
    for Level = #Config.Severity, 1, -1 do
        if Score >= Config.Severity[Level].MinScore then return Level end
    end

    return 0
end

function Crash.LevelName(Level)
    local Entry = Config.Severity[Level]

    return Entry and Entry.Name or 'None'
end

function Crash.Evaluate(Report)
    local Side = Crash.SideFromAngle(Report.Angle)
    local Weight = Config.Impact.SideWeights[Side] or 1.0
    local Base = Report.DeltaV / Config.Impact.MaxDeltaVelocityMs * 100.0 * Weight
    local Damage = Report.HealthLost * Config.Impact.DamageWeight * 100.0
    local Score = Crash.Clamp(Base + Damage, 0.0, 100.0)

    return {
        Score = Score,
        Level = Crash.LevelFromScore(Score),
        Side = Side,
        Angle = Report.Angle,
        DeltaV = Report.DeltaV,
        Speed = Report.Speed,
    }
end

function Crash.EmptyState()
    return {
        Jam = { 0, 0, 0, 0, 0, 0 },
        Torn = { 0, 0, 0, 0, 0, 0 },
        Window = { 0, 0, 0, 0, 0, 0 },
        Level = 0,
        Body = 1000.0,
        Fuel = 0,
        Radiator = 0,
        Steer = 0.0,
        Hazards = 0,
        Time = 0,
    }
end

function Crash.JamOf(State, Door)
    if not State or not State.Jam then return 0 end

    return State.Jam[Door + 1] or 0
end

function Crash.IsTorn(State, Door)
    return State ~= nil and State.Torn ~= nil and (State.Torn[Door + 1] or 0) == 1
end

function Crash.IsJammed(State, Door)
    return Crash.JamOf(State, Door) > 0 and not Crash.IsTorn(State, Door)
end

function Crash.IsWindowBroken(State, Window)
    return State ~= nil and State.Window ~= nil and (State.Window[Window + 1] or 0) == 1
end

function Crash.CanLeaveSeat(State, Seat)
    local Door = Crash.DoorForSeat(Seat)

    if not Crash.IsJammed(State, Door) then return true end

    return Crash.IsWindowBroken(State, Door)
end

function Crash.AnyJam(State)
    if not State or not State.Jam then return false end

    for Door = 0, Crash.DoorCount - 1 do
        if Crash.IsJammed(State, Door) then return true end
    end

    return false
end

function Crash.ToTable(Vector)
    return { x = Vector.x, y = Vector.y, z = Vector.z }
end

function Crash.ToVector(Table)
    return vec3(Table.x, Table.y, Table.z)
end

return Crash

local Config = lib.load('config')
local Crash = lib.load('shared.crash')

CrashImpact = {}

local PlayerImpacts = {}
local VehicleLast = {}

local SideAngles = { Front = 0.0, Right = 90.0, Rear = 180.0, Left = -90.0 }

local function ProximityMultiplier(Seat, Side)
    local Left = Crash.SeatIsLeft(Seat)
    local Front = Crash.SeatIsFront(Seat)

    if Side == 'Left' then return Left and Config.Effects.NearSideMultiplier or Config.Effects.FarSideMultiplier end
    if Side == 'Right' then return Left and Config.Effects.FarSideMultiplier or Config.Effects.NearSideMultiplier end
    if Side == 'Front' then return Front and Config.Effects.NearSideMultiplier or Config.Effects.FarSideMultiplier end

    return Front and Config.Effects.FarSideMultiplier or Config.Effects.NearSideMultiplier
end

local function RollDamage(Level, Belted, Near)
    if not Config.Injuries.Enabled then return 0.0 end

    local Range = Config.Injuries.HealthLossPercent[Level]

    if not Range then return 0.0 end

    local Multiplier = Near * (Belted and Config.Injuries.BeltMultiplier or 1.0)

    return Crash.RandomBetween(Range) * Multiplier
end

local function RollEjection(Level, Belted, Speed, IsOpenVehicle)
    if not Config.Ejection.Enabled or Belted or Speed < Config.Ejection.MinSpeedMs then return false end

    local Chances = IsOpenVehicle and Config.Ejection.OpenChance or Config.Ejection.Chance

    return math.random() < (Chances[Level] or 0.0)
end

local function BuildOccupant(Occupant, Evaluation, State, Context, NetId, Velocity)
    local Belted = Context.IsOpenVehicle and false or CrashState.IsBelted(Occupant.Source)
    local Near = ProximityMultiplier(Occupant.Seat, Evaluation.Side)
    local Ejected = RollEjection(Evaluation.Level, Belted, Evaluation.Speed, Context.IsOpenVehicle)
    local Damage = RollDamage(Evaluation.Level, Belted, Near)

    if Ejected then Damage = Damage + Crash.RandomBetween(Config.Ejection.HealthLossPercent) end

    return {
        NetId = NetId,
        Level = Evaluation.Level,
        Score = Evaluation.Score,
        Side = Evaluation.Side,
        Seat = Occupant.Seat,
        Intensity = Near * (Belted and Config.Effects.BeltMultiplier or 1.0),
        Belted = Belted,
        Damage = Damage,
        Eject = Ejected,
        Velocity = Velocity,
        Trapped = not Ejected and not Crash.CanLeaveSeat(State, Occupant.Seat),
    }
end

function CrashImpact.Resolve(Vehicle, Evaluation, Context)
    local NetId = NetworkGetNetworkIdFromEntity(Vehicle)
    local State = CrashState.ReadOrEmpty(Vehicle)

    State.Level = math.max(State.Level, Evaluation.Level)
    State.Time = os.time()
    State.Body = Context.Body or State.Body

    local Doors = CrashDoors.Roll(State, Evaluation, Context)
    local Apply = CrashVehicle.Roll(State, Evaluation, Context)

    CrashState.Write(Vehicle, State)

    if State.Fuel == 1 then CrashVehicle.TrackLeak(Vehicle) end

    CrashDebris.Spawn(Vehicle, Evaluation, Doors, Context.Source)

    local AnyTrapped = false
    local Occupants = CrashState.Occupants(Vehicle)

    for _, Occupant in ipairs(Occupants) do
        local Payload = BuildOccupant(Occupant, Evaluation, State, Context, NetId, Context.Velocity)

        AnyTrapped = AnyTrapped or Payload.Trapped

        TriggerClientEvent('crashphysics:client:occupant', Occupant.Source, Payload)
    end

    local Owner = NetworkGetEntityOwner(Vehicle)

    if Owner and Owner > 0 then
        TriggerClientEvent('crashphysics:client:vehicle', Owner, NetId, Apply, Doors, State)
    end

    local Reporter = Context.Source or (Occupants[1] and Occupants[1].Source) or 0

    if Reporter > 0 then
        local Jammed = #Doors.Jammed > 0 and table.concat(Doors.Jammed, ',') or 'none'

        CrashLogs.Impact(Reporter, CrashState.Plate(Vehicle), Evaluation, Jammed)

        if AnyTrapped then CrashLogs.Trapped(Reporter, CrashState.Plate(Vehicle)) end
    end

    CrashDispatch.Crash(GetEntityCoords(Vehicle), Evaluation.Level, AnyTrapped)

    return { Doors = Doors, Apply = Apply, Trapped = AnyTrapped, State = State }
end

local function SanitizeDoors(List)
    local Set = {}

    if type(List) ~= 'table' then return Set end

    for _, Door in ipairs(List) do
        if Crash.IsFinite(Door) and Door >= 0 and Door < Crash.DoorCount then Set[math.floor(Door)] = true end
    end

    return Set
end

local function SanitizeVelocity(Velocity)
    if type(Velocity) ~= 'table' then return { x = 0.0, y = 0.0, z = 0.0 } end

    local Max = Config.Server.MaxDeltaVelocityMs * 2.0
    local function Axis(Value) return Crash.IsFinite(Value) and Crash.Clamp(Value, -Max, Max) or 0.0 end

    return { x = Axis(Velocity.x), y = Axis(Velocity.y), z = Axis(Velocity.z) }
end

local function SanitizeReport(Report)
    if type(Report) ~= 'table' then return nil end

    local Fields = { Report.DeltaV, Report.Speed, Report.Angle, Report.HealthLost, Report.Body, Report.Class }

    for _, Value in ipairs(Fields) do
        if not Crash.IsFinite(Value) then return nil end
    end

    return {
        DeltaV = Crash.Clamp(Report.DeltaV, 0.0, Config.Server.MaxDeltaVelocityMs),
        Speed = Crash.Clamp(Report.Speed, 0.0, Config.Server.MaxDeltaVelocityMs * 2.0),
        Angle = Crash.Clamp(Report.Angle, -180.0, 180.0),
        HealthLost = Crash.Clamp(Report.HealthLost, 0.0, 1.0),
        Body = Crash.Clamp(Report.Body, 0.0, 1000.0),
        Class = math.floor(Crash.Clamp(Report.Class, 0, 22)),
        Doors = SanitizeDoors(Report.Doors),
        Velocity = SanitizeVelocity(Report.Velocity),
    }
end

local function IsRateLimited(Source)
    local Now = GetGameTimer()
    local List = PlayerImpacts[Source] or {}

    for Index = #List, 1, -1 do
        if Now - List[Index] > 60000 then table.remove(List, Index) end
    end

    List[#List + 1] = Now
    PlayerImpacts[Source] = List

    return #List > Config.Server.MaxImpactsPerMinute
end

local function IsVehicleCoolingDown(NetId)
    local Now = GetGameTimer()
    local Last = VehicleLast[NetId]

    VehicleLast[NetId] = Now

    return Last ~= nil and Now - Last < Config.Server.VehicleCooldownMs
end

local function IsPlausible(Source, Vehicle)
    if not CrashState.IsOccupant(Source, Vehicle) then return false end
    if NetworkGetEntityOwner(Vehicle) ~= Source then return false end

    return CrashState.NearVehicle(Source, Vehicle, Config.Server.MaxVehicleDistance)
end

RegisterNetEvent('crashphysics:server:impact', function(NetId, RawReport)
    local Source = source
    local Vehicle = CrashState.GetVehicle(NetId)
    local Report = SanitizeReport(RawReport)

    if not Vehicle or not Report then return end
    if not IsPlausible(Source, Vehicle) then return end

    if IsRateLimited(Source) then
        CrashLogs.AntiCheat(Source, 'Too many impact reports per minute')

        return
    end

    if IsVehicleCoolingDown(NetId) then return end

    if RawReport.DeltaV > Config.Server.MaxDeltaVelocityMs then
        CrashLogs.AntiCheat(Source, ('Impossible delta-v reported: %.1f'):format(RawReport.DeltaV))
    end

    local Evaluation = Crash.Evaluate(Report)

    if Evaluation.Level == 0 then return end

    Evaluation.LevelName = Crash.LevelName(Evaluation.Level)

    CrashImpact.Resolve(Vehicle, Evaluation, {
        Source = Source,
        Class = Report.Class,
        Doors = Report.Doors,
        Body = Report.Body,
        Velocity = Report.Velocity,
        HasWindows = not Config.Impact.NoDoorClasses[Report.Class],
        IsOpenVehicle = Config.Impact.NoDoorClasses[Report.Class] == true,
    })
end)

function CrashImpact.Simulate(Vehicle, Level, Side, Source)
    local Entry = Config.Severity[Level]

    if not Entry then return nil end

    local Doors = {}

    for Door = 0, Crash.DoorCount - 1 do Doors[Door] = true end

    local Weight = Config.Impact.SideWeights[Side] or 1.0
    local DeltaV = (Entry.MinScore + 2.0) / (100.0 * Weight) * Config.Impact.MaxDeltaVelocityMs
    local Evaluation = {
        Score = Entry.MinScore + 2.0,
        Level = Level,
        LevelName = Entry.Name,
        Side = Side,
        Angle = SideAngles[Side] or 0.0,
        DeltaV = DeltaV,
        Speed = DeltaV * 1.3,
    }

    local Heading = math.rad(GetEntityHeading(Vehicle))
    local Speed = Evaluation.Speed

    return CrashImpact.Resolve(Vehicle, Evaluation, {
        Source = Source,
        Class = 1,
        Doors = Doors,
        HasWindows = true,
        IsOpenVehicle = false,
        BodyLoss = Level * 120.0,
        Velocity = { x = -math.sin(Heading) * Speed, y = math.cos(Heading) * Speed, z = 0.0 },
    })
end

CreateThread(function()
    while true do
        Wait(Config.Seconds(60))

        local Now = GetGameTimer()

        for NetId, Time in pairs(VehicleLast) do
            if Now - Time > 60000 then VehicleLast[NetId] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    PlayerImpacts[source] = nil
end)

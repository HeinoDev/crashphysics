local Config = lib.load('config')
local Crash = lib.load('shared.crash')

CrashDebris = {}

local Scenes = {}
local NextSceneId = 0
local NextPieceId = 0
local Claims = {}
local Sweeping = {}
local Swept = {}

local function ClaimKey(SceneId, PieceId)
    return ('%s:%s'):format(SceneId, PieceId)
end

local function SceneCount()
    local Count = 0

    for _ in pairs(Scenes) do Count = Count + 1 end

    return Count
end

local function OldestScene()
    local Oldest

    for _, Scene in pairs(Scenes) do
        if not Oldest or Scene.Created < Oldest.Created then Oldest = Scene end
    end

    return Oldest
end

local function Snapshot(Scene, Pieces, IsNew)
    return {
        Id = Scene.Id,
        Coords = Crash.ToTable(Scene.Coords),
        Radius = Scene.Radius,
        Pieces = Pieces,
        New = IsNew,
    }
end

local function PickKind(Level)
    local Candidates, Total = {}, 0

    for Name, Kind in pairs(Config.Debris.Kinds) do
        if Level >= Kind.MinLevel then
            Candidates[#Candidates + 1] = { Name = Name, Kind = Kind }
            Total = Total + Kind.Weight
        end
    end

    local Roll = math.random() * Total

    for _, Entry in ipairs(Candidates) do
        Roll = Roll - Entry.Kind.Weight

        if Roll <= 0 then return Entry.Name, Entry.Kind end
    end

    local Last = Candidates[#Candidates]

    return Last.Name, Last.Kind
end

local function NewPiece(Kind, Model, Offset, Hazard)
    NextPieceId = NextPieceId + 1

    return {
        Id = NextPieceId,
        Kind = Kind,
        Model = Model,
        Offset = Crash.ToTable(Offset),
        Heading = math.random() * 360.0,
        Hazard = Hazard,
    }
end

local function DirectionFromBearing(Bearing)
    local Radians = math.rad(Bearing)

    return vec3(-math.sin(Radians), math.cos(Radians), 0.0)
end

local function ScatterOffset(Bearing, Radius)
    local Spread = math.random() < Config.Debris.ScatterBias and (math.random() - 0.5) * 100.0 or math.random() * 360.0
    local Direction = DirectionFromBearing(Bearing + Spread)
    local Distance = 1.0 + math.random() * (Radius - 1.0)

    return Direction * Distance
end

local function DoorOffset(Door, Heading)
    local Lateral = (Door == 0 or Door == 2) and -1.1 or 1.1
    local Longitudinal = (Door == 0 or Door == 1) and 0.5 or -0.5
    local Right = DirectionFromBearing(Heading - 90.0)
    local Forward = DirectionFromBearing(Heading)

    return Right * Lateral + Forward * Longitudinal
end

local function RandomModel(List)
    return List[math.random(#List)]
end

local function BuildPieces(Heading, Evaluation, Doors)
    local Level = Evaluation.Level
    local Count = Crash.RandomInt(Config.Debris.PiecesPerLevel[Level])
    local Radius = Config.Debris.Radius[Level]
    local Bearing = Heading - (Evaluation.Angle or 0.0)
    local Pieces = {}

    for _ = 1, Count do
        local Name, Kind = PickKind(Level)

        Pieces[#Pieces + 1] = NewPiece(Name, RandomModel(Kind.Models), ScatterOffset(Bearing, Radius), Kind.Hazard)
    end

    for _, Door in ipairs(Doors.Torn or {}) do
        local Offset = DoorOffset(Door, Heading) * 2.0 + ScatterOffset(Bearing, 2.0) * 0.3

        Pieces[#Pieces + 1] = NewPiece('Door', RandomModel(Config.Debris.DoorModels), Offset, true)
    end

    if Doors.HoodTorn then
        Pieces[#Pieces + 1] = NewPiece('Hood', RandomModel(Config.Debris.HoodModels), ScatterOffset(Bearing, Radius), true)
    end

    return Pieces, Radius
end

local function FindMergeTarget(Coords, Incoming)
    for _, Scene in pairs(Scenes) do
        local Close = #(Scene.Coords - Coords) <= Config.Debris.MergeDistance
        local Fits = Scene.Count + Incoming <= Config.Debris.MaxPiecesPerScene

        if Close and Fits then return Scene end
    end

    return nil
end

local function Farthest(Pieces)
    local Distance = 0.0

    for _, Piece in ipairs(Pieces) do
        Distance = math.max(Distance, #Crash.ToVector(Piece.Offset))
    end

    return Distance
end

function CrashDebris.RemoveScene(SceneId)
    local Scene = Scenes[SceneId]

    if not Scene then return end

    for PieceId in pairs(Scene.Pieces) do Claims[ClaimKey(SceneId, PieceId)] = nil end

    Scenes[SceneId] = nil
    TriggerClientEvent('crashphysics:client:debrisRemoveScene', -1, SceneId)
end

local function TrimScenes()
    while SceneCount() > Config.Debris.MaxScenes do
        local Oldest = OldestScene()

        if not Oldest then return end

        CrashDebris.RemoveScene(Oldest.Id)
    end
end

function CrashDebris.Spawn(Vehicle, Evaluation, Doors, Creator)
    if not Config.Debris.Enabled or Evaluation.Level < Config.Debris.MinLevel then return nil end

    local Coords = GetEntityCoords(Vehicle)
    local Pieces, Radius = BuildPieces(GetEntityHeading(Vehicle), Evaluation, Doors)
    local Scene = FindMergeTarget(Coords, #Pieces)
    local IsNew = Scene == nil

    if IsNew then
        NextSceneId = NextSceneId + 1
        Scene = { Id = NextSceneId, Coords = Coords, Radius = Radius, Pieces = {}, Count = 0, Created = GetGameTimer(), Creator = Creator }
        Scenes[Scene.Id] = Scene
    else
        local Shift = Coords - Scene.Coords

        for _, Piece in ipairs(Pieces) do
            Piece.Offset = Crash.ToTable(Crash.ToVector(Piece.Offset) + Shift)
        end
    end

    for _, Piece in ipairs(Pieces) do
        Scene.Pieces[Piece.Id] = Piece
        Scene.Count = Scene.Count + 1
    end

    Scene.Radius = math.max(Scene.Radius, Radius, Farthest(Pieces) + 1.0)

    TriggerClientEvent('crashphysics:client:debrisAdd', -1, Snapshot(Scene, Pieces, IsNew))
    TrimScenes()

    return Scene.Id
end

function CrashDebris.RemovePiece(SceneId, PieceId)
    local Scene = Scenes[SceneId]

    if not Scene or not Scene.Pieces[PieceId] then return false end

    Scene.Pieces[PieceId] = nil
    Scene.Count = Scene.Count - 1
    Claims[ClaimKey(SceneId, PieceId)] = nil

    TriggerClientEvent('crashphysics:client:debrisRemovePiece', -1, SceneId, PieceId)

    if Scene.Count <= 0 then CrashDebris.RemoveScene(SceneId) end

    return true
end

function CrashDebris.ClearAll()
    local Total = 0

    for SceneId, Scene in pairs(Scenes) do
        Total = Total + Scene.Count
        CrashDebris.RemoveScene(SceneId)
    end

    return Total
end

function CrashDebris.ClearNear(Coords, Radius)
    local Total = 0

    for SceneId, Scene in pairs(Scenes) do
        if #(Scene.Coords - Coords) <= Radius + Scene.Radius then
            Total = Total + Scene.Count
            CrashDebris.RemoveScene(SceneId)
        end
    end

    return Total
end

local function PieceWorld(Scene, Piece)
    return Scene.Coords + Crash.ToVector(Piece.Offset)
end

local function IsJobAllowed(Source)
    if #Config.Cleanup.Jobs == 0 then return true end

    local Job = CrashState.Job(Source)

    for _, Allowed in ipairs(Config.Cleanup.Jobs) do
        if Allowed == Job then return true end
    end

    return false
end

local function IsClaimedByOther(SceneId, PieceId, Source)
    local Claim = Claims[ClaimKey(SceneId, PieceId)]

    if not Claim or Claim.Source == Source then return false end

    return GetGameTimer() - Claim.Time < Config.Cleanup.ClaimTimeoutMs
end

local function ReleaseSweep(Source)
    local Active = Sweeping[Source]

    if not Active then return end

    Claims[ClaimKey(Active.SceneId, Active.PieceId)] = nil
    Sweeping[Source] = nil
end

local function HourlyRecord(Source)
    local License = GetPlayerIdentifierByType(Source, 'license') or tostring(Source)
    local Record = Swept[License]

    if not Record or os.time() - Record.Start >= 3600 then
        Record = { Start = os.time(), Count = 0 }
        Swept[License] = Record
    end

    return Record
end

local function Payout(Source, Scene)
    local Settings = Config.Cleanup.Payout

    if not Settings.Enabled then return 0 end
    if GetGameTimer() - Scene.Created < Settings.MinSceneAgeMs then return 0 end
    if Settings.IgnoreOwnCrashes and Scene.Creator == Source then return 0 end

    local Record = HourlyRecord(Source)

    if Record.Count >= Settings.PiecesPerHour then return 0 end

    Record.Count = Record.Count + 1

    local Amount = Crash.RandomInt(Settings.Amount)

    exports['heino_bridge']:AddMoney(Source, Settings.Account, Amount, 'crashphysics:cleanup')

    return Amount
end

lib.callback.register('crashphysics:server:sweepStart', function(Source, SceneId, PieceId)
    if not Config.Cleanup.Enabled or not IsJobAllowed(Source) then return { Ok = false } end

    local Scene = Scenes[SceneId]
    local Piece = Scene and Scene.Pieces[PieceId]

    if not Piece then return { Ok = false, Reason = 'Gone' } end
    if IsClaimedByOther(SceneId, PieceId, Source) then return { Ok = false, Reason = 'Claimed' } end

    local Reach = Config.Cleanup.ReachDistance + 1.5

    if CrashState.Distance(Source, PieceWorld(Scene, Piece)) > Reach then return { Ok = false, Reason = 'Far' } end

    ReleaseSweep(Source)

    Claims[ClaimKey(SceneId, PieceId)] = { Source = Source, Time = GetGameTimer() }
    Sweeping[Source] = { SceneId = SceneId, PieceId = PieceId, Start = GetGameTimer() }

    return { Ok = true, Duration = Config.Cleanup.TimePerPieceMs }
end)

lib.callback.register('crashphysics:server:sweepFinish', function(Source, SceneId, PieceId)
    local Active = Sweeping[Source]

    if not Active or Active.SceneId ~= SceneId or Active.PieceId ~= PieceId then return { Ok = false } end

    local Elapsed = GetGameTimer() - Active.Start
    local Scene = Scenes[SceneId]
    local Piece = Scene and Scene.Pieces[PieceId]

    Sweeping[Source] = nil

    if Elapsed < Config.Cleanup.TimePerPieceMs * Config.Server.MinProgressFraction then
        CrashLogs.AntiCheat(Source, ('Finished sweeping too fast (%d ms)'):format(Elapsed))
        Claims[ClaimKey(SceneId, PieceId)] = nil

        return { Ok = false }
    end

    if not Piece then return { Ok = false } end
    if CrashState.Distance(Source, PieceWorld(Scene, Piece)) > Config.Cleanup.ReachDistance + 2.5 then return { Ok = false } end

    local Paid = Payout(Source, Scene)

    CrashDebris.RemovePiece(SceneId, PieceId)
    CrashLogs.Cleanup(Source, 1)

    return { Ok = true, Paid = Paid }
end)

RegisterNetEvent('crashphysics:server:sweepCancel', function()
    ReleaseSweep(source)
end)

lib.callback.register('crashphysics:server:getDebris', function()
    local List = {}

    for _, Scene in pairs(Scenes) do
        local Pieces = {}

        for _, Piece in pairs(Scene.Pieces) do Pieces[#Pieces + 1] = Piece end

        List[#List + 1] = Snapshot(Scene, Pieces, true)
    end

    return List
end)

CreateThread(function()
    while true do
        Wait(Config.Seconds(30))

        local Now = GetGameTimer()

        for SceneId, Scene in pairs(Scenes) do
            if Now - Scene.Created >= Config.Debris.LifetimeMs then CrashDebris.RemoveScene(SceneId) end
        end

        for License, Record in pairs(Swept) do
            if os.time() - Record.Start >= 3600 then Swept[License] = nil end
        end

        for Key, Claim in pairs(Claims) do
            if Now - Claim.Time >= Config.Cleanup.ClaimTimeoutMs * 2 then Claims[Key] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    ReleaseSweep(source)
end)

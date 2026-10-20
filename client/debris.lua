local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local Settings = Config.Debris
local Cleanup = Config.Cleanup

local Scenes = {}
local Sweeping = false
local SweepScene
local LastHazard = 0

local TyreIndexes = { 0, 1, 4, 5 }
local BikeTyreIndexes = { 0, 4 }

local function PieceCoords(Scene, Piece)
    return Scene.Coords + Piece.Offset
end

local function BuildPiece(Data)
    return {
        Id = Data.Id,
        Kind = Data.Kind,
        Model = Data.Model,
        Offset = Crash.ToVector(Data.Offset),
        Heading = Data.Heading,
        Hazard = Data.Hazard,
    }
end

local function DeleteObject(Piece)
    if Piece.Object and DoesEntityExist(Piece.Object) then DeleteEntity(Piece.Object) end

    Piece.Object = nil
end

local function ReleaseObjects(Scene)
    for _, Piece in pairs(Scene.Pieces) do DeleteObject(Piece) end
end

local function NearestPiece(Scene)
    local Coords = GetEntityCoords(cache.ped)
    local Best, BestDistance, Excluded = nil, Cleanup.ReachDistance, Scene.Skipped

    for _, Piece in pairs(Scene.Pieces) do
        local Distance = #(PieceCoords(Scene, Piece) - Coords)

        if Distance <= BestDistance and not (Excluded and Excluded[Piece.Id]) then
            Best, BestDistance = Piece, Distance
        end
    end

    return Best
end

local function CreateObjectFor(Scene, Piece)
    local Hash = joaat(Piece.Model)

    if not IsModelInCdimage(Hash) then
        Piece.Missing = true

        return
    end

    local Loaded = pcall(lib.requestModel, Hash, 1500)

    if not Loaded then return end

    local Coords = PieceCoords(Scene, Piece)
    local Object = CreateObjectNoOffset(Hash, Coords.x, Coords.y, Coords.z + 1.0, false, false, false)

    SetModelAsNoLongerNeeded(Hash)

    if not DoesEntityExist(Object) then return end

    SetEntityHeading(Object, Piece.Heading)
    PlaceObjectOnGroundProperly(Object)
    FreezeEntityPosition(Object, true)
    SetEntityCollision(Object, false, false)

    Piece.Object = Object
end

local function SweepOption(SceneId)
    return {
        name = 'crashphysics:sweep',
        icon = 'fa-solid fa-broom',
        label = locale('Target.Sweep'),
        distance = Config.Interactions.ZoneDistance,
        canInteract = function()
            local Scene = Scenes[SceneId]

            return Scene ~= nil and not cache.vehicle and not Sweeping and NearestPiece(Scene) ~= nil
        end,
        onSelect = function()
            SweepScene(SceneId)
        end,
    }
end

local function RemoveZone(Scene)
    if not Scene.Zone then return end

    pcall(function() exports['ox_target']:removeZone(Scene.Zone) end)

    Scene.Zone = nil
end

local function AddZone(SceneId, Scene)
    RemoveZone(Scene)

    Scene.Zone = exports['ox_target']:addSphereZone({
        coords = Scene.Coords,
        radius = Scene.Radius + Config.Interactions.ZoneRadiusPadding,
        debug = Config.Debug,
        options = { SweepOption(SceneId) },
    })
end

local function RemoveScene(SceneId)
    local Scene = Scenes[SceneId]

    if not Scene then return end

    ReleaseObjects(Scene)
    RemoveZone(Scene)
    Scenes[SceneId] = nil
end

local function UpsertScene(Data)
    local Scene = Scenes[Data.Id]

    if not Scene then
        Scene = { Id = Data.Id, Pieces = {} }
        Scenes[Data.Id] = Scene
    end

    Scene.Coords = Crash.ToVector(Data.Coords)
    Scene.Radius = Data.Radius

    for _, PieceData in ipairs(Data.Pieces) do
        Scene.Pieces[PieceData.Id] = BuildPiece(PieceData)
    end

    AddZone(Data.Id, Scene)
end

local function RemovePiece(SceneId, PieceId)
    local Scene = Scenes[SceneId]
    local Piece = Scene and Scene.Pieces[PieceId]

    if not Piece then return end

    DeleteObject(Piece)
    Scene.Pieces[PieceId] = nil

    if next(Scene.Pieces) == nil then RemoveScene(SceneId) end
end

RegisterNetEvent('crashphysics:client:debrisAdd', function(Data)
    if type(Data) == 'table' then UpsertScene(Data) end
end)

RegisterNetEvent('crashphysics:client:debrisRemoveScene', RemoveScene)
RegisterNetEvent('crashphysics:client:debrisRemovePiece', RemovePiece)

local function SyncAll()
    local List = lib.callback.await('crashphysics:server:getDebris', false)

    for SceneId in pairs(Scenes) do RemoveScene(SceneId) end

    for _, Data in ipairs(List or {}) do UpsertScene(Data) end
end

local function StreamScene(Scene, Coords, Budget)
    local Distance = #(Scene.Coords - Coords)

    if Distance > Settings.StreamDistance + Scene.Radius then
        ReleaseObjects(Scene)

        return Budget
    end

    for _, Piece in pairs(Scene.Pieces) do
        if not Piece.Object and not Piece.Missing and Budget > 0 then
            CreateObjectFor(Scene, Piece)
            Budget = Budget - 1
        end
    end

    return Budget
end

local function Notify(Key, Type)
    CrashClient.Notify(locale(Key), Type)
end

local function SweepPiece(Scene, Piece)
    local Begin = lib.callback.await('crashphysics:server:sweepStart', false, Scene.Id, Piece.Id)

    if not Begin or not Begin.Ok then
        Scene.Skipped = Scene.Skipped or {}
        Scene.Skipped[Piece.Id] = true

        return 'Skipped'
    end

    local Target = PieceCoords(Scene, Piece)

    TaskTurnPedToFaceCoord(cache.ped, Target.x, Target.y, Target.z, 600)
    Wait(600)

    local Done = CrashClient.Progress(locale('Progress.Sweep'), Begin.Duration, Cleanup.Animation, {
        model = Cleanup.Broom.Model,
        bone = Cleanup.Broom.Bone,
        pos = Cleanup.Broom.Position,
        rot = Cleanup.Broom.Rotation,
    })

    if not Done then
        TriggerServerEvent('crashphysics:server:sweepCancel')

        return 'Cancelled'
    end

    local Result = lib.callback.await('crashphysics:server:sweepFinish', false, Scene.Id, Piece.Id)

    if not Result or not Result.Ok then
        Scene.Skipped = Scene.Skipped or {}
        Scene.Skipped[Piece.Id] = true

        return 'Skipped'
    end

    if Result.Paid and Result.Paid > 0 then CrashClient.Notify(locale('Sweep.Paid', Result.Paid), 'success', 3000) end

    return 'Done'
end

SweepScene = function(SceneId)
    if Sweeping or CrashClient.IsDead() then return end

    local Scene = Scenes[SceneId]

    if not Scene then return end

    Sweeping = true
    Scene.Skipped = nil

    local Swept = 0

    while Scenes[SceneId] and not CrashClient.IsDead() and not cache.vehicle do
        local Piece = NearestPiece(Scene)

        if not Piece then break end

        local Outcome = SweepPiece(Scene, Piece)

        if Outcome == 'Cancelled' then break end
        if Outcome == 'Done' then Swept = Swept + 1 end
    end

    Sweeping = false

    Scene.Skipped = nil

    if Swept > 0 then
        CrashClient.Notify(locale('Sweep.Done', Swept), 'success', 4000)
    else
        Notify('Sweep.Nothing', 'inform')
    end
end

local function HazardTyres(Vehicle)
    return GetVehicleClass(Vehicle) == 8 and BikeTyreIndexes or TyreIndexes
end

local function IsOverHazard(Coords)
    local Radius = Settings.Hazard.Radius

    for _, Scene in pairs(Scenes) do
        if #(Scene.Coords - Coords) <= Scene.Radius + Radius then
            for _, Piece in pairs(Scene.Pieces) do
                if Piece.Hazard and #(PieceCoords(Scene, Piece) - Coords) <= Radius then return true end
            end
        end
    end

    return false
end

local function RollPuncture(Vehicle)
    if math.random() >= Settings.Hazard.TireBurstChance then return end

    local Tyres = HazardTyres(Vehicle)

    SetVehicleTyreBurst(Vehicle, Tyres[math.random(#Tyres)], false, 1000.0)
    CrashClient.Notify(locale('Debris.Puncture'), 'error', 4000)
end

CreateThread(function()
    while true do
        Wait(Settings.StreamIntervalMs)

        if next(Scenes) then
            local Coords = GetEntityCoords(cache.ped)
            local Budget = Settings.CreatesPerCycle

            for _, Scene in pairs(Scenes) do
                Budget = StreamScene(Scene, Coords, Budget)
            end
        end
    end
end)

CreateThread(function()
    local Hazard = Settings.Hazard

    while true do
        local Sleep = 1000
        local Vehicle = cache.vehicle

        if Hazard.Enabled and Vehicle and cache.seat == -1 and next(Scenes) then
            Sleep = Hazard.CheckIntervalMs

            local Now = GetGameTimer()

            if Now - LastHazard >= Hazard.CooldownMs and GetEntitySpeed(Vehicle) >= Hazard.MinSpeedMs then
                if IsOverHazard(GetEntityCoords(Vehicle)) then
                    LastHazard = Now
                    RollPuncture(Vehicle)
                end
            end
        end

        Wait(Sleep)
    end
end)

CreateThread(function()
    Wait(1500)
    SyncAll()
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(1500)
    SyncAll()
end)

AddEventHandler('onResourceStop', function(Resource)
    if Resource ~= GetCurrentResourceName() then return end

    for SceneId in pairs(Scenes) do RemoveScene(SceneId) end
end)

local Harness = {}

local Root = arg and arg[0] and arg[0]:match('^(.*)[/\\]tests[/\\][^/\\]*$') or '.'

local Vector = {}
Vector.__index = Vector

local function NewVector(X, Y, Z)
    return setmetatable({ x = X + 0.0, y = Y + 0.0, z = Z + 0.0 }, Vector)
end

Vector.__add = function(A, B) return NewVector(A.x + B.x, A.y + B.y, A.z + B.z) end
Vector.__sub = function(A, B) return NewVector(A.x - B.x, A.y - B.y, A.z - B.z) end
Vector.__unm = function(A) return NewVector(-A.x, -A.y, -A.z) end
Vector.__len = function(A) return math.sqrt(A.x * A.x + A.y * A.y + A.z * A.z) end
Vector.__div = function(A, B) return NewVector(A.x / B, A.y / B, A.z / B) end
Vector.__mul = function(A, B)
    if type(A) == 'number' then A, B = B, A end

    return NewVector(A.x * B, A.y * B, A.z * B)
end

function Harness.Reset()
    Harness.Clock = 100000
    Harness.Events = {}
    Harness.Net = {}
    Harness.Callbacks = {}
    Harness.Handlers = {}
    Harness.Commands = {}
    Harness.Exports = {}
    Harness.Calls = {}
    Harness.Entities = {}
    Harness.Players = {}
    Harness.Items = {}
    Harness.Owner = {}
    Harness.Timeouts = {}
end

function Harness.Record(Name, ...)
    Harness.Calls[#Harness.Calls + 1] = { Name = Name, Args = { ... } }
end

function Harness.CountCalls(Name)
    local Count = 0

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == Name then Count = Count + 1 end
    end

    return Count
end

function Harness.LastEvent(Name, Target)
    for Index = #Harness.Net, 1, -1 do
        local Event = Harness.Net[Index]

        if Event.Name == Name and (Target == nil or Event.Target == Target) then return Event end
    end

    return nil
end

function Harness.CountEvents(Name)
    local Count = 0

    for _, Event in ipairs(Harness.Net) do
        if Event.Name == Name then Count = Count + 1 end
    end

    return Count
end

local function MakeState()
    return setmetatable({}, { __index = { set = function(Self, Key, Value) rawset(Self, Key, Value) end } })
end

function Harness.AddVehicle(Id, Coords, Heading)
    Harness.Entities[Id] = { Type = 2, Coords = Coords, Heading = Heading or 0.0, State = MakeState(), Plate = 'TEST' .. Id, Seats = {} }
end

function Harness.AddPlayer(Source, Ped, Coords)
    Harness.Players[Source] = { Ped = Ped, State = MakeState(), Job = 'unemployed' }
    Harness.Entities[Ped] = { Type = 1, Coords = Coords, State = MakeState(), Vehicle = 0 }
end

function Harness.Seat(Source, Vehicle, Seat)
    local Player = Harness.Players[Source]

    Harness.Entities[Player.Ped].Vehicle = Vehicle
    Harness.Entities[Vehicle].Seats[Seat] = Player.Ped
end

local Loaded = {}

local function Loader(Path)
    if Loaded[Path] then return Loaded[Path] end

    local Name = Root .. '/' .. Path:gsub('%.', '/') .. '.lua'
    local Chunk = assert(loadfile(Name))

    Loaded[Path] = Chunk()

    return Loaded[Path]
end

local function InstallCommon(Env)
    Env.vec3 = NewVector
    Env.joaat = function(Text) return #Text end
    Env.lib = {
        load = Loader,
        locale = function() Env.locale = function(Key, ...) return select('#', ...) > 0 and (Key .. ':' .. table.concat({ ... }, ',')) or Key end end,
        callback = {
            register = function(Name, Handler) Harness.Callbacks[Name] = Handler end,
            await = function() return nil end,
        },
        addCommand = function(Name, Options, Handler) Harness.Commands[Name] = { Options = Options, Handler = Handler } end,
        addKeybind = function(Options)
            Harness.Keybinds = Harness.Keybinds or {}
            Harness.Keybinds[Options.name] = Options
            Harness.Record('addKeybind', Options.name)
        end,
        onCache = function() end,
    }
    Env.locale = function(Key) return Key end
    Env.CreateThread = function() end
    Env.Wait = function() end
    Env.GetGameTimer = function() return Harness.Clock end
    Env.SetTimeout = function(_, Callback)
        Harness.Record('SetTimeout')
        Harness.Timeouts[#Harness.Timeouts + 1] = Callback
    end
    Env.RegisterNetEvent = function(Name, Handler) if Handler then Harness.Handlers[Name] = Handler end end
    Env.AddEventHandler = function(Name, Handler) Harness.Handlers[Name] = Harness.Handlers[Name] or Handler end
    Env.GetCurrentResourceName = function() return 'crashphysics' end
    Env.exports = setmetatable({}, {
        __call = function(_, Name, Handler) Harness.Exports[Name] = Handler end,
        __index = function(_, Resource)
            return setmetatable({}, {
                __index = function(_, Function)
                    return function(_, ...)
                        local Handler = Harness.Exports[Resource .. ':' .. Function]

                        if Handler then return Handler(...) end

                        Harness.Record(Resource .. ':' .. Function, ...)
                    end
                end,
            })
        end,
    })
end

function Harness.ServerEnv()
    Harness.Reset()

    local Env = _G

    InstallCommon(Env)

    Env.TriggerClientEvent = function(Name, Target, ...) Harness.Net[#Harness.Net + 1] = { Name = Name, Target = Target, Args = { ... } } end
    Env.GetPlayers = function()
        local List = {}

        for Source in pairs(Harness.Players) do List[#List + 1] = tostring(Source) end

        return List
    end
    Env.GetPlayerPed = function(Source) return Harness.Players[Source] and Harness.Players[Source].Ped or 0 end
    Env.GetPlayerName = function(Source) return 'Player' .. Source end
    Env.GetPlayerIdentifierByType = function(Source) return 'license:' .. Source end
    Env.GetVehiclePedIsIn = function(Ped) return Harness.Entities[Ped] and Harness.Entities[Ped].Vehicle or 0 end
    Env.GetPedInVehicleSeat = function(Vehicle, Seat) return Harness.Entities[Vehicle].Seats[Seat] or 0 end
    Env.NetworkGetEntityFromNetworkId = function(NetId) return Harness.Entities[NetId] and NetId or 0 end
    Env.NetworkGetNetworkIdFromEntity = function(Entity) return Entity end
    Env.NetworkGetEntityOwner = function(Entity) return Harness.Owner[Entity] or 0 end
    Env.DoesEntityExist = function(Entity) return Harness.Entities[Entity] ~= nil end
    Env.GetEntityType = function(Entity) return Harness.Entities[Entity].Type end
    Env.GetEntityCoords = function(Entity) return Harness.Entities[Entity].Coords end
    Env.GetEntityHeading = function(Entity) return Harness.Entities[Entity].Heading end
    Env.GetVehicleNumberPlateText = function(Entity) return Harness.Entities[Entity].Plate end
    Env.GetResourceState = function() return 'started' end
    Env.GetAllVehicles = function()
        local List = {}

        for Id, Entity in pairs(Harness.Entities) do
            if Entity.Type == 2 then List[#List + 1] = Id end
        end

        return List
    end
    Env.Entity = function(Id) return { state = Harness.Entities[Id].State } end
    Env.Player = function(Source) return { state = Harness.Players[Source].State } end
    Env.ESX = {
        GetPlayerFromId = function(Source)
            local Player = Harness.Players[Source]

            return Player and { job = { name = Player.Job } } or nil
        end,
    }

    Harness.Exports['ox_inventory:Search'] = function(Source, _, Item)
        return (Harness.Items[Source] or {})[Item] or 0
    end
end

function Harness.LoadServer()
    local Files = {
        'server/logs', 'server/state', 'server/doors', 'server/vehicle', 'server/debris',
        'server/dispatch', 'server/impact', 'server/actions', 'server/commands',
    }

    for _, File in ipairs(Files) do
        assert(loadfile(Root .. '/' .. File .. '.lua'))()
    end
end

function Harness.ClientEnv()
    Harness.Reset()

    local Env = _G

    InstallCommon(Env)

    Env.TriggerServerEvent = function(Name, ...) Harness.Record('server:' .. Name, ...) end
    Env.cache = { ped = 1, vehicle = false, seat = false, playerId = 0 }
    Env.LocalPlayer = { state = {} }
    Env.Entity = function() return { state = {} } end
    Env.GetGamePool = function() return {} end
    Env.GetEntityCoords = function() return NewVector(0, 0, 0) end
    Env.DoesEntityExist = function() return false end
    Env.AddStateBagChangeHandler = function() end
    Env.DoesAnimDictExist = function() return true end

    Env.lib.requestAnimSet = function() end
    Env.lib.requestModel = function() end
    Env.lib.progressBar = function(Options) Harness.Record('progressBar', Options.label) return Harness.ProgressResult ~= false end
    Env.lib.skillCheck = function() return true end
    Env.lib.showTextUI = function() Harness.Record('showTextUI') end
    Env.lib.hideTextUI = function() Harness.Record('hideTextUI') end
    Env.lib.registerContext = function(Data) Harness.Context = Data end
    Env.lib.showContext = function() Harness.Record('showContext') end
    Env.lib.alertDialog = function(Data) Harness.Dialog = Data end

    setmetatable(Env, { __index = function(_, Key)
        if type(Key) == 'string' and Key:match('^%u') and Key ~= 'Config' then
            return function(...)
                Harness.Record(Key, ...)

                return 0
            end
        end
    end })
end

function Harness.LoadClient()
    local Files = {
        'client/core', 'client/detection', 'client/effects', 'client/seatbelt', 'client/trapped',
        'client/doors', 'client/vehicle', 'client/debris', 'client/interactions',
    }

    for _, File in ipairs(Files) do
        assert(loadfile(Root .. '/' .. File .. '.lua'))()
    end
end

Harness.Root = Root
Harness.Vector = NewVector

return Harness

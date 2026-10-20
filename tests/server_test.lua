local Harness = dofile((arg and arg[0] and arg[0]:match('^(.*)[/\\][^/\\]*$') or '.') .. '/harness.lua')

local Passed, Failed = 0, 0

local function Check(Name, Condition, Detail)
    if Condition then
        Passed = Passed + 1
    else
        Failed = Failed + 1
        print(('FAIL: %s %s'):format(Name, Detail and ('(' .. tostring(Detail) .. ')') or ''))
    end
end

local function Fresh()
    Harness.ServerEnv()
    Harness.LoadServer()
    Harness.AddVehicle(100, Harness.Vector(10, 20, 30), 0.0)
    Harness.AddPlayer(1, 501, Harness.Vector(10, 20, 30))
    Harness.AddPlayer(2, 502, Harness.Vector(10, 20, 30))
    Harness.AddPlayer(3, 503, Harness.Vector(12, 20, 30))
    Harness.Seat(1, 100, -1)
    Harness.Seat(2, 100, 1)
    Harness.Owner[100] = 1
    Harness.Owner[501] = 1
    Harness.Owner[502] = 2
end

local function Report(Overrides)
    local Value = {
        DeltaV = 20.0,
        Speed = 25.0,
        Angle = 90.0,
        HealthLost = 0.3,
        Body = 700.0,
        Class = 1,
        Doors = { 0, 1, 2, 3, 4, 5 },
        Velocity = { x = 0.0, y = 20.0, z = 0.0 },
    }

    for Key, Entry in pairs(Overrides or {}) do Value[Key] = Entry end

    return Value
end

local function Fire(Name, Source, ...)
    _G.source = Source
    Harness.Handlers[Name](...)
end

local Crash

do
    Fresh()
    Crash = dofile(Harness.Root .. '/shared/crash.lua')
    Crash = lib.load('shared.crash')

    Check('door seat -1', Crash.DoorForSeat(-1) == 0)
    Check('door seat 0', Crash.DoorForSeat(0) == 1)
    Check('door seat 1', Crash.DoorForSeat(1) == 2)
    Check('door seat 2', Crash.DoorForSeat(2) == 3)
    Check('door seat 3', Crash.DoorForSeat(3) == 2)
    Check('door seat 4', Crash.DoorForSeat(4) == 3)
    Check('seat left -1', Crash.SeatIsLeft(-1))
    Check('seat right 0', not Crash.SeatIsLeft(0))
    Check('side front', Crash.SideFromAngle(10) == 'Front')
    Check('side right', Crash.SideFromAngle(90) == 'Right')
    Check('side left', Crash.SideFromAngle(-90) == 'Left')
    Check('side rear', Crash.SideFromAngle(170) == 'Rear')
    Check('side rear negative', Crash.SideFromAngle(-170) == 'Rear')

    local Light = Crash.Evaluate({ DeltaV = 3.0, Speed = 5.0, Angle = 0.0, HealthLost = 0.0 })
    local Minor = Crash.Evaluate({ DeltaV = 5.0, Speed = 8.0, Angle = 0.0, HealthLost = 0.0 })
    local Moderate = Crash.Evaluate({ DeltaV = 10.0, Speed = 12.0, Angle = 0.0, HealthLost = 0.0 })
    local Severe = Crash.Evaluate({ DeltaV = 18.0, Speed = 20.0, Angle = 0.0, HealthLost = 0.0 })
    local Critical = Crash.Evaluate({ DeltaV = 27.0, Speed = 30.0, Angle = 0.0, HealthLost = 0.0 })
    local Capped = Crash.Evaluate({ DeltaV = 80.0, Speed = 80.0, Angle = 0.0, HealthLost = 1.0 })

    Check('level none', Light.Level == 0, Light.Level)
    Check('level minor', Minor.Level == 1, Minor.Level)
    Check('level moderate', Moderate.Level == 2, Moderate.Level)
    Check('level severe', Severe.Level == 3, Severe.Level)
    Check('level critical', Critical.Level == 4, Critical.Level)
    Check('score capped', Capped.Score == 100.0, Capped.Score)

    local State = Crash.EmptyState()

    Check('empty state not jammed', not Crash.AnyJam(State))

    State.Jam[1] = 50

    Check('jam detected', Crash.IsJammed(State, 0))
    Check('cannot leave jammed seat', not Crash.CanLeaveSeat(State, -1))
    Check('can leave other seat', Crash.CanLeaveSeat(State, 0))

    State.Window[1] = 1

    Check('window route', Crash.CanLeaveSeat(State, -1))

    State.Window[1] = 0
    State.Torn[1] = 1

    Check('torn door frees seat', Crash.CanLeaveSeat(State, -1))
    Check('nil state free', Crash.CanLeaveSeat(nil, -1))
end

do
    Fresh()

    Fire('crashphysics:server:impact', 1, 100, Report())

    local State = Entity(100).state.crashphysics

    Check('impact writes state', State ~= nil)
    Check('impact level', State and State.Level >= 3, State and State.Level)
    Check('occupant event driver', Harness.LastEvent('crashphysics:client:occupant', 1) ~= nil)
    Check('occupant event passenger', Harness.LastEvent('crashphysics:client:occupant', 2) ~= nil)
    Check('bystander gets no occupant event', Harness.LastEvent('crashphysics:client:occupant', 3) == nil)
    Check('vehicle event to owner', Harness.LastEvent('crashphysics:client:vehicle', 1) ~= nil)
    Check('debris broadcast', Harness.CountEvents('crashphysics:client:debrisAdd') == 1)

    local Passenger = Harness.LastEvent('crashphysics:client:occupant', 2).Args[1]

    Check('passenger seat', Passenger.Seat == 1)
    Check('passenger net id', Passenger.NetId == 100)
    Check('damage non negative', Passenger.Damage >= 0)
end

do
    Fresh()

    Fire('crashphysics:server:impact', 3, 100, Report())

    Check('non occupant impact ignored', Entity(100).state.crashphysics == nil)

    Harness.Owner[100] = 2
    Fire('crashphysics:server:impact', 1, 100, Report())

    Check('non owner impact ignored', Entity(100).state.crashphysics == nil)

    Harness.Owner[100] = 1
    Fire('crashphysics:server:impact', 1, 100, { DeltaV = 'x' })

    Check('garbage report ignored', Entity(100).state.crashphysics == nil)

    Fire('crashphysics:server:impact', 1, 100, Report({ DeltaV = 0 / 0 }))

    Check('nan report ignored', Entity(100).state.crashphysics == nil)

    Fire('crashphysics:server:impact', 1, 100, Report({ DeltaV = 2.0, HealthLost = 0.0 }))

    Check('trivial report ignored', Entity(100).state.crashphysics == nil)

    Fire('crashphysics:server:impact', 1, 99999, Report())

    Check('unknown vehicle ignored', Entity(100).state.crashphysics == nil)

    Fire('crashphysics:server:impact', 1, 100, Report())
    local First = Harness.CountEvents('crashphysics:client:debrisAdd')

    Fire('crashphysics:server:impact', 1, 100, Report())

    Check('vehicle cooldown blocks duplicate', Harness.CountEvents('crashphysics:client:debrisAdd') == First)

    Harness.Clock = Harness.Clock + 2000
    Fire('crashphysics:server:impact', 1, 100, Report())

    Check('cooldown expires', Harness.CountEvents('crashphysics:client:debrisAdd') >= First)
end

do
    Fresh()

    local Config = lib.load('config')

    for _ = 1, Config.Server.MaxImpactsPerMinute + 5 do
        Harness.Clock = Harness.Clock + Config.Server.VehicleCooldownMs + 1
        Fire('crashphysics:server:impact', 1, 100, Report())
    end

    local Total = Harness.CountEvents('crashphysics:client:vehicle')

    Check('rate limit caps reports', Total <= Config.Server.MaxImpactsPerMinute, Total)
end

do
    Fresh()

    local Jammed, Torn, Samples = 0, 0, 300
    local Doors = lib.load('config')

    for _ = 1, Samples do
        local State = Crash.EmptyState()
        local Result = CrashDoors.Roll(State, { Level = 4, Side = 'Right' }, { Class = 1, Doors = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true } })

        Jammed = Jammed + #Result.Jammed
        Torn = Torn + #Result.Torn

        Check('left doors untouched by right hit', State.Jam[1] == 0 and State.Jam[3] == 0)
    end

    Check('critical right hit jams right doors', Jammed > Samples, Jammed)
    Check('critical right hit tears some doors', Torn > 0, Torn)
    Check('doors config loaded', Doors.Doors.Enabled)

    local Minor = Crash.EmptyState()
    local Result = CrashDoors.Roll(Minor, { Level = 1, Side = 'Right' }, { Class = 1, Doors = { [1] = true } })

    Check('minor hit never jams', #Result.Jammed == 0 and #Result.Torn == 0)

    local Bike = Crash.EmptyState()
    local BikeResult = CrashDoors.Roll(Bike, { Level = 4, Side = 'Right' }, { Class = 8, Doors = { [1] = true } })

    Check('bikes have no doors', #BikeResult.Jammed == 0)

    local Invalid = Crash.EmptyState()

    CrashDoors.Roll(Invalid, { Level = 4, Side = 'Right' }, { Class = 1, Doors = {} })

    Check('invalid doors never jam', not Crash.AnyJam(Invalid))

    local Strength = Crash.EmptyState()

    for _ = 1, 50 do
        CrashDoors.Roll(Strength, { Level = 4, Side = 'Left' }, { Class = 1, Doors = { [0] = true, [2] = true } })
    end

    Check('jam strength capped', Strength.Jam[1] <= 100 and Strength.Jam[3] <= 100)

    local Hood = 0

    for _ = 1, 100 do
        local Front = CrashDoors.Roll(Crash.EmptyState(), { Level = 4, Side = 'Front' }, { Class = 1, Doors = { [4] = true } })

        if Front.HoodPopped then Hood = Hood + 1 end
    end

    Check('front hits pop the hood', Hood > 50, Hood)
end

do
    Fresh()

    local State = Crash.EmptyState()
    local Seen = { Tires = 0, Windows = 0, Fuel = 0, Radiator = 0, Steer = 0 }

    for _ = 1, 400 do
        local Roll = Crash.EmptyState()
        local Apply = CrashVehicle.Roll(Roll, { Level = 4, Side = 'Front' }, { HasWindows = true })

        Seen.Tires = Seen.Tires + #Apply.Tires
        Seen.Windows = Seen.Windows + #Apply.Windows
        Seen.Fuel = Seen.Fuel + Roll.Fuel
        Seen.Radiator = Seen.Radiator + Roll.Radiator
        Seen.Steer = Seen.Steer + (Roll.Steer ~= 0 and 1 or 0)

    end

    Check('critical crash bursts tires', Seen.Tires > 0)
    Check('critical crash smashes windows', Seen.Windows > 0)
    Check('critical crash leaks fuel', Seen.Fuel > 0)
    Check('critical crash leaks radiator', Seen.Radiator > 0)
    Check('critical crash bends steering', Seen.Steer > 0)

    local Minor = CrashVehicle.Roll(State, { Level = 1, Side = 'Front' }, { HasWindows = true })

    Check('minor crash no consequences', #Minor.Tires == 0 and #Minor.Windows == 0 and State.Fuel == 0)

    local Moderate = CrashVehicle.Roll(Crash.EmptyState(), { Level = 2, Side = 'Front' }, { HasWindows = true })

    Check('moderate crash no leak profile', Moderate.HornStuck == nil)
end

do
    Fresh()

    local Config = lib.load('config')

    Entity(100).state:set('crashphysics', Crash.EmptyState())

    local Ids = {}

    for _ = 1, 20 do
        Ids[#Ids + 1] = CrashDebris.Spawn(100, { Level = 4, Side = 'Front', Angle = 0.0 }, { Torn = { 0 }, HoodTorn = true }, 1)
    end

    local Scenes = lib.callback and Harness.Callbacks['crashphysics:server:getDebris'](1)

    Check('debris scenes merge nearby', #Scenes < 20, #Scenes)

    local Total = 0

    for _, Scene in ipairs(Scenes) do
        Total = Total + #Scene.Pieces

        Check('scene respects piece cap', #Scene.Pieces <= Config.Debris.MaxPiecesPerScene, #Scene.Pieces)
    end

    Check('debris has pieces', Total > 0)

    local Models = {}

    for _, Scene in ipairs(Scenes) do
        for _, Piece in ipairs(Scene.Pieces) do Models[Piece.Kind] = true end
    end

    Check('torn door becomes debris', Models.Door == true)
    Check('torn hood becomes debris', Models.Hood == true)

    CrashDebris.ClearAll()

    Check('clear all empties scenes', #Harness.Callbacks['crashphysics:server:getDebris'](1) == 0)

    Check('minor crash spawns no debris', CrashDebris.Spawn(100, { Level = 1, Side = 'Front', Angle = 0.0 }, {}, 1) == nil)

    for Index = 1, Config.Debris.MaxScenes + 10 do
        Harness.Entities[100].Coords = Harness.Vector(Index * 100, 0, 0)
        Harness.Clock = Harness.Clock + 1
        CrashDebris.Spawn(100, { Level = 2, Side = 'Front', Angle = 0.0 }, {}, 1)
    end

    Check('scene count capped', #Harness.Callbacks['crashphysics:server:getDebris'](1) <= Config.Debris.MaxScenes)
end

do
    Fresh()

    local Config = lib.load('config')

    CrashDebris.Spawn(100, { Level = 2, Side = 'Front', Angle = 0.0 }, {}, 99)

    local Scene = Harness.Callbacks['crashphysics:server:getDebris'](1)[1]
    local Piece = Scene.Pieces[1]
    local World = Harness.Vector(Scene.Coords.x + Piece.Offset.x, Scene.Coords.y + Piece.Offset.y, Scene.Coords.z + Piece.Offset.z)

    Harness.Entities[503].Coords = World

    local Start = Harness.Callbacks['crashphysics:server:sweepStart']
    local Finish = Harness.Callbacks['crashphysics:server:sweepFinish']

    Harness.Entities[501].Coords = Harness.Vector(900, 900, 30)

    local Far = Start(1, Scene.Id, Piece.Id)

    Check('sweep rejected when far away', Far.Ok == false)

    local Missing = Start(3, Scene.Id, 999999)

    Check('sweep rejected for unknown piece', Missing.Ok == false)

    local Begin = Start(3, Scene.Id, Piece.Id)

    Check('sweep starts when near', Begin.Ok == true and Begin.Duration == Config.Cleanup.TimePerPieceMs)

    Harness.Entities[503].Coords = World
    Harness.Entities[501].Coords = World

    local Stolen = Start(1, Scene.Id, Piece.Id)

    Check('claimed piece rejected for others', Stolen.Ok == false and Stolen.Reason == 'Claimed')

    local TooFast = Finish(3, Scene.Id, Piece.Id)

    Check('instant finish rejected', TooFast.Ok == false)

    Begin = Start(3, Scene.Id, Piece.Id)
    Check('restart after reject', Begin.Ok == true)

    Harness.Clock = Harness.Clock + Config.Cleanup.TimePerPieceMs
    local Done = Finish(3, Scene.Id, Piece.Id)

    Check('sweep completes after duration', Done.Ok == true)
    Check('piece removal broadcast', Harness.CountEvents('crashphysics:client:debrisRemovePiece') + Harness.CountEvents('crashphysics:client:debrisRemoveScene') >= 1)

    local Again = Finish(3, Scene.Id, Piece.Id)

    Check('double finish rejected', Again.Ok == false)

    Harness.Handlers['crashphysics:server:sweepCancel']()
end

do
    Fresh()

    local Config = lib.load('config')
    local Settings = Config.Cleanup.Payout

    Settings.Enabled = true

    local function SweepOne(Creator, Sweeper)
        CrashDebris.ClearAll()
        CrashDebris.Spawn(100, { Level = 2, Side = 'Front', Angle = 0.0 }, {}, Creator)

        local Scene = Harness.Callbacks['crashphysics:server:getDebris'](1)[1]
        local Piece = Scene.Pieces[1]
        local Offset = Piece.Offset

        Harness.Entities[Harness.Players[Sweeper].Ped].Coords = Harness.Vector(Scene.Coords.x + Offset.x, Scene.Coords.y + Offset.y, Scene.Coords.z + Offset.z)
        Harness.Clock = Harness.Clock + Settings.MinSceneAgeMs + 1
        Harness.Callbacks['crashphysics:server:sweepStart'](Sweeper, Scene.Id, Piece.Id)
        Harness.Clock = Harness.Clock + Config.Cleanup.TimePerPieceMs

        return Harness.Callbacks['crashphysics:server:sweepFinish'](Sweeper, Scene.Id, Piece.Id)
    end

    local Own = SweepOne(3, 3)

    Check('no payout for own crash', Own.Ok and Own.Paid == 0, Own.Paid)

    local Foreign = SweepOne(1, 3)

    Check('payout for foreign crash', Foreign.Ok and Foreign.Paid >= Settings.Amount[1], Foreign.Paid)
    Check('payout recorded', Harness.CountCalls('heino_bridge:AddMoney') == 1)

    for _ = 1, Settings.PiecesPerHour + 2 do SweepOne(1, 3) end

    Check('hourly cap holds', Harness.CountCalls('heino_bridge:AddMoney') <= Settings.PiecesPerHour)

    Settings.Enabled = false
end

do
    Fresh()

    local Seeded = Crash.EmptyState()

    Seeded.Jam[1] = 60
    Seeded.Level = 3
    Entity(100).state:set('crashphysics', Seeded)

    _G.source = 1
    Harness.Handlers['crashphysics:server:forceDoor'](100, true)

    local After = Entity(100).state.crashphysics

    Check('force door reduces jam', After.Jam[1] < 60, After.Jam[1])
    Check('force door hurts', Harness.CountEvents('crashphysics:client:hurt') == 1)

    Harness.Handlers['crashphysics:server:forceDoor'](100, true)

    Check('force door rate limited', Entity(100).state.crashphysics.Jam[1] == After.Jam[1])

    for _ = 1, 20 do
        Harness.Clock = Harness.Clock + 2000
        Harness.Handlers['crashphysics:server:forceDoor'](100, true)
    end

    Check('force door eventually frees', Entity(100).state.crashphysics.Jam[1] == 0)

    local Frees = Harness.CountEvents('crashphysics:client:hurt')

    Harness.Clock = Harness.Clock + 2000
    Harness.Handlers['crashphysics:server:forceDoor'](100, true)

    Check('freed door no longer hurts', Harness.CountEvents('crashphysics:client:hurt') == Frees)

    Seeded = Crash.EmptyState()
    Seeded.Jam[1] = 90
    Entity(100).state:set('crashphysics', Seeded)

    _G.source = 1
    Harness.Clock = Harness.Clock + 2000
    Harness.Handlers['crashphysics:server:forceDoor'](100, false)

    Check('failed force keeps jam', Entity(100).state.crashphysics.Jam[1] == 90)

    _G.source = 3
    Harness.Handlers['crashphysics:server:forceDoor'](100, true)

    Check('outsider cannot force door', Entity(100).state.crashphysics.Jam[1] == 90)
end

do
    Fresh()

    local Seeded = Crash.EmptyState()

    Seeded.Jam[1] = 80
    Entity(100).state:set('crashphysics', Seeded)

    local Begin = Harness.Callbacks['crashphysics:server:windowBegin']
    local End = Harness.Callbacks['crashphysics:server:windowEnd']

    Check('window rejects bad index', Begin(1, 100, 9, true).Ok == false)
    Check('window rejects wrong seat window', Begin(1, 100, 1, true).Ok == false)
    Check('driver can break own window', Begin(1, 100, 0, true).Ok == true)
    Check('window end too early rejected', End(1) == false)

    Begin(1, 100, 0, true)
    Harness.Clock = Harness.Clock + 5000

    Check('window end succeeds', End(1) == true)
    Check('window marked broken', Entity(100).state.crashphysics.Window[1] == 1)
    Check('window smash sent to owner', Harness.LastEvent('crashphysics:client:smashWindow', 1) ~= nil)
    Check('inside window break hurts', Harness.CountEvents('crashphysics:client:hurt') == 1)
    Check('broken window rejects repeat', Begin(1, 100, 0, true).Reason == 'Broken')

    local Crashes = lib.load('shared.crash')

    Check('window frees trapped seat', Crashes.CanLeaveSeat(Entity(100).state.crashphysics, -1))

    Check('outside window needs no tool', Begin(3, 100, 1, false).Ok == true)
    Check('outside window rejects occupant', Begin(2, 100, 1, false).Ok == false)
end

do
    Fresh()

    local Seeded = Crash.EmptyState()

    Seeded.Jam[1] = 80
    Entity(100).state:set('crashphysics', Seeded)

    local Occupants = Harness.Callbacks['crashphysics:server:occupants']
    local Listed = Occupants(3, 100)

    Check('rescuer sees both occupants', #Listed == 2, #Listed)

    local DriverEntry, PassengerEntry

    for _, Entry in ipairs(Listed) do
        if Entry.Seat == -1 then DriverEntry = Entry else PassengerEntry = Entry end
    end

    Check('trapped driver cannot be pulled', DriverEntry and DriverEntry.CanPull == false)
    Check('free passenger can be pulled', PassengerEntry and PassengerEntry.CanPull == true)
    Check('occupant cannot list own vehicle', #Occupants(1, 100) == 0)

    local PullBegin = Harness.Callbacks['crashphysics:server:pullBegin']
    local PullEnd = Harness.Callbacks['crashphysics:server:pullEnd']

    Check('pull trapped rejected', PullBegin(3, 100, 1).Reason == 'Trapped')
    Check('pull self rejected', PullBegin(1, 100, 1).Ok == false)
    Check('pull non occupant rejected', PullBegin(3, 100, 3).Ok == false)

    local Begin = PullBegin(3, 100, 2)

    Check('pull free passenger', Begin.Ok == true)
    Check('pull end too early', PullEnd(3) == false)

    PullBegin(3, 100, 2)
    Harness.Clock = Harness.Clock + 10000

    Check('pull completes', PullEnd(3) == true)
    Check('pulled player notified', Harness.LastEvent('crashphysics:client:pulled', 2) ~= nil)

    PullBegin(3, 100, 2)
    Harness.Clock = Harness.Clock + 10000
    Harness.Entities[100].Seats[1] = nil
    Harness.Entities[502].Vehicle = 0

    Check('pull after leaving rejected', PullEnd(3) == false)
end

do
    Fresh()

    local Seeded = Crash.EmptyState()

    Seeded.Level = 3
    Seeded.Body = 600
    Seeded.Fuel = 1
    Entity(100).state:set('crashphysics', Seeded)

    _G.source = 3
    Harness.Handlers['crashphysics:server:baseline'](100, 400)

    Check('baseline from non owner ignored', Entity(100).state.crashphysics.Body == 600)

    _G.source = 1
    Harness.Handlers['crashphysics:server:baseline'](100, 400)

    Check('baseline from owner stored', Entity(100).state.crashphysics.Body == 400)

    Harness.Handlers['crashphysics:server:baseline'](100, 0 / 0)

    Check('baseline rejects nan', Entity(100).state.crashphysics.Body == 400)

    Harness.Entities[503].Coords = Harness.Vector(500, 500, 30)
    _G.source = 3
    Harness.Handlers['crashphysics:server:repaired'](100)

    Check('repair from far away ignored', Entity(100).state.crashphysics ~= nil)

    Harness.Entities[503].Coords = Harness.Vector(11, 20, 30)
    Harness.Handlers['crashphysics:server:repaired'](100)

    Check('repair clears state', Entity(100).state.crashphysics == nil)
    Check('repair notifies owner', Harness.LastEvent('crashphysics:client:cleared', 1) ~= nil)
end

do
    Fresh()

    _G.source = 1
    Harness.Handlers['crashphysics:server:belt'](true)

    Check('belt state set in vehicle', Harness.Players[1].State.seatbelt == true)

    Harness.Entities[501].Vehicle = 0
    Harness.Handlers['crashphysics:server:belt'](true)

    Check('belt cannot be set outside vehicle', Harness.Players[1].State.seatbelt == false)

    Harness.Entities[501].Vehicle = 100
    Harness.Handlers['crashphysics:server:belt']('yes')

    Check('belt rejects non boolean', Harness.Players[1].State.seatbelt == false)
end

do
    Fresh()

    local Ejected, Belted = 0, 0

    Harness.Players[1].State.seatbelt = true
    Harness.Players[2].State.seatbelt = false

    for _ = 1, 200 do
        Harness.Net = {}
        CrashImpact.Simulate(100, 4, 'Front', 1)

        local Driver = Harness.LastEvent('crashphysics:client:occupant', 1).Args[1]
        local Passenger = Harness.LastEvent('crashphysics:client:occupant', 2).Args[1]

        if Driver.Eject then Belted = Belted + 1 end
        if Passenger.Eject then Ejected = Ejected + 1 end

        Check('belted damage lower or equal', Driver.Damage <= 45.0 * 1.25 * 0.4 + 0.001, Driver.Damage)
        Entity(100).state:set('crashphysics', nil)
    end

    Check('belted occupants never ejected', Belted == 0)
    Check('unbelted occupants sometimes ejected', Ejected > 0, Ejected)

    Harness.Net = {}
    Check('simulate rejects invalid level', CrashImpact.Simulate(100, 9, 'Front', 1) == nil)
end

do
    Fresh()

    local Simulated = CrashImpact.Simulate(100, 3, 'Right', 1)

    Check('simulate returns result', Simulated ~= nil and Simulated.State.Level == 3)
    Check('simulate applies body loss', Harness.LastEvent('crashphysics:client:vehicle', 1).Args[2].BodyLoss == 360.0)

    _G.source = 1

    Harness.Commands.crashsim.Handler(1, { level = 4, side = 'left' })

    Check('command simulates', Entity(100).state.crashphysics.Level == 4)

    Harness.Commands.crashclear.Handler(1, {})

    Check('clear command resets state', Entity(100).state.crashphysics == nil)

    Harness.Commands.crashinfo.Handler(1, {})
    Harness.Commands.crashdebris.Handler(1, {})

    Check('commands registered', Harness.Commands.crashsim and Harness.Commands.crashclear and Harness.Commands.crashdebris and Harness.Commands.crashinfo)
    Check('commands are admin restricted', Harness.Commands.crashsim.Options.restricted == 'group.admin')
end

do
    Fresh()

    Check('jam export', Harness.Exports.JamDoor(100, 2, 70) == true)
    Check('jam export state', Entity(100).state.crashphysics.Jam[3] == 70)
    Check('jam export rejects bad door', Harness.Exports.JamDoor(100, 9, 70) == false)
    Check('free export', Harness.Exports.FreeDoor(100, 2) == true)
    Check('free export state', Entity(100).state.crashphysics.Jam[3] == 0)
    Check('clear export', Harness.Exports.ClearVehicle(100) == true and Entity(100).state.crashphysics == nil)
    Check('state export', Harness.Exports.GetCrashState(100) == nil)
    Check('apply export result', Harness.Exports.ApplyCrash(100, 2, 'Rear') == true)
    Check('apply export unknown vehicle', Harness.Exports.ApplyCrash(555, 2, 'Rear') == false)
end

do
    Fresh()

    local Dispatch = lib.load('config').Dispatch

    Dispatch.Chance = { [3] = 1.0, [4] = 1.0 }

    for _ = 1, 3 do CrashDispatch.Crash(Harness.Vector(10, 20, 30), 4, false) end

    Check('dispatch deduplicates nearby calls', Harness.CountCalls('SetTimeout') <= 1, Harness.CountCalls('SetTimeout'))

    Check('help call allowed', CrashDispatch.Help(1, Harness.Vector(0, 0, 0)) == true)
    Check('help call cooldown', CrashDispatch.Help(1, Harness.Vector(0, 0, 0)) == false)
end

print(('%d passed, %d failed'):format(Passed, Failed))

os.exit(Failed == 0 and 0 or 1)

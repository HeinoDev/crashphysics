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

local V = Harness.Vector

local function Steady(Velocity, Count, Extra)
    local List = {}

    for _ = 1, Count do
        local Frame = { Velocity = Velocity }

        for Key, Value in pairs(Extra or {}) do Frame[Key] = Value end

        List[#List + 1] = Frame
    end

    return List
end

local function Append(List, Other)
    for _, Frame in ipairs(Other) do List[#List + 1] = Frame end

    return List
end

local function RunDetection(Frames, Overrides)
    Overrides = Overrides or {}

    Harness.ClientEnv()

    local Threads = {}
    local Index = 1

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    cache.vehicle = 7
    NetworkHasControlOfEntity = function() return Overrides.Control ~= false end
    GetVehicleClass = function() return Overrides.Class or 1 end
    GetIsDoorValid = function() return true end
    GetEntityMatrix = function() return V(1, 0, 0), V(0, 1, 0), V(0, 0, 1), V(0, 0, 0) end
    NetworkGetNetworkIdFromEntity = function() return 7 end
    GetEntityVelocity = function() return Frames[math.min(Index, #Frames)].Velocity end
    GetVehicleBodyHealth = function() return Frames[math.min(Index, #Frames)].Body or 1000.0 end
    GetVehicleEngineHealth = function() return Frames[math.min(Index, #Frames)].Engine or 1000.0 end
    IsEntityInAir = function() return Frames[math.min(Index, #Frames)].Air == true end
    HasEntityCollidedWithAnything = function() return Frames[math.min(Index, #Frames)].Collided == true end
    Wait = function(Milliseconds)
        Harness.Clock = Harness.Clock + Milliseconds
        Index = Index + 1

        if Index > #Frames then error('frames exhausted') end
    end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/detection.lua'))()

    pcall(Threads[2])

    local Reports = {}

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'server:crashphysics:server:impact' then Reports[#Reports + 1] = Call.Args end
    end

    return Reports
end

do
    local Frames = Steady(V(0, 25, 0), 6)

    Append(Frames, Steady(V(0, 0, 0), 8, { Body = 600, Engine = 800, Collided = true }))

    local Reports = RunDetection(Frames)

    Check('head on crash reported once', #Reports == 1, #Reports)

    local Report = Reports[1] and Reports[1][2]

    Check('head on net id', Reports[1] and Reports[1][1] == 7)
    Check('head on delta v', Report and math.abs(Report.DeltaV - 25.0) < 0.5, Report and Report.DeltaV)
    Check('head on angle is front', Report and math.abs(Report.Angle) < 5, Report and Report.Angle)
    Check('head on speed', Report and math.abs(Report.Speed - 25.0) < 0.5)
    Check('head on damage fraction', Report and Report.HealthLost > 0.15 and Report.HealthLost <= 1.0, Report and Report.HealthLost)
    Check('head on doors listed', Report and #Report.Doors == 6)
    Check('head on velocity captured', Report and Report.Velocity.y == 25.0)
end

do
    local Frames = Steady(V(0, 20, 0), 6)

    Append(Frames, Steady(V(-9, 20, 0), 8, { Body = 800, Collided = true }))

    local Report = (RunDetection(Frames)[1] or {})[2]

    Check('side impact reported', Report ~= nil)
    Check('right side impact angle', Report and Report.Angle > 70 and Report.Angle < 110, Report and Report.Angle)
end

do
    local Frames = Steady(V(0, 20, 0), 6)

    Append(Frames, Steady(V(9, 20, 0), 8, { Body = 800, Collided = true }))

    local Report = (RunDetection(Frames)[1] or {})[2]

    Check('left side impact angle', Report and Report.Angle < -70 and Report.Angle > -110, Report and Report.Angle)
end

do
    local Frames = Steady(V(0, -20, 0), 6)

    Append(Frames, Steady(V(0, 0, 0), 8, { Body = 800, Collided = true }))

    local Report = (RunDetection(Frames)[1] or {})[2]

    Check('rear impact angle', Report and math.abs(Report.Angle) > 170, Report and Report.Angle)
end

do
    local Frames = {}

    for Step = 0, 40 do Frames[#Frames + 1] = { Velocity = V(0, math.max(0, 25 - Step * 0.6), 0) } end

    Check('hard braking is not a crash', #RunDetection(Frames) == 0)
end

do
    local Frames = Steady(V(0, 15, -12), 6, { Air = true })

    Append(Frames, Steady(V(0, 15, 0), 8, { Air = false }))

    Check('landing without damage ignored', #RunDetection(Frames) == 0)
end

do
    local Frames = Steady(V(0, 25, 0), 6)

    Append(Frames, Steady(V(0, 0, 0), 8, { Body = 600 }))

    Check('crash without flag but with damage counts', #RunDetection(Frames) == 1)
end

do
    local Frames = Steady(V(0, 25, 0), 6)

    Append(Frames, Steady(V(0, 0, 0), 8))

    Check('violent stop without damage or flag counts', #RunDetection(Frames) == 1)
end

do
    local Frames = Steady(V(0, 4, 0), 6)

    Append(Frames, Steady(V(0, 0.5, 0), 8, { Collided = true }))

    Check('bump below threshold not reported', #RunDetection(Frames) == 0)

    Frames = Steady(V(0, 6, 0), 6)

    Append(Frames, Steady(V(0, 0.5, 0), 8, { Collided = true }))

    Check('minor bump reported as minor', #RunDetection(Frames) == 1)
end

do
    local Frames = Steady(V(0, 25, 0), 6)

    Append(Frames, Steady(V(0, 0, 0), 4, { Body = 600, Collided = true }))
    Append(Frames, Steady(V(0, 20, 0), 1))
    Append(Frames, Steady(V(0, 0, 0), 8, { Body = 300, Collided = true }))

    Check('bounce inside cooldown reported once', #RunDetection(Frames) == 1)
end

do
    local Frames = Steady(V(0, 25, 0), 6)

    Append(Frames, Steady(V(0, 0, 0), 8, { Body = 600, Collided = true }))

    Check('uncontrolled vehicle never reports', #RunDetection(Frames, { Control = false }) == 0)
    Check('excluded class never reports', #RunDetection(Frames, { Class = 16 }) == 0)
    Check('boat class never reports', #RunDetection(Frames, { Class = 14 }) == 0)
end

do
    Harness.ClientEnv()

    local Threads = {}

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    cache.vehicle = 7
    NetworkGetNetworkIdFromEntity = function() return 7 end
    IsPedDead = function() return false end
    IsEntityDead = function() return false end
    GetEntityHealth = function() return 200 end
    IsPedInAnyVehicle = function() return false end
    GetOffsetFromEntityInWorldCoords = function() return V(1, 1, 1) end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/effects.lua'))()

    local Occupant = Harness.Handlers['crashphysics:client:occupant']

    Occupant({ NetId = 99, Level = 4, Intensity = 1.0, Seat = -1 })

    Check('other vehicle payload ignored', Harness.CountCalls('TriggerScreenblurFadeIn') == 0)

    Occupant({ NetId = 7, Level = 4, Score = 90, Intensity = 1.0, Seat = -1, Damage = 30, Eject = false, Trapped = true, Velocity = { x = 0, y = 20, z = 0 } })

    Check('critical blurs vision', Harness.CountCalls('TriggerScreenblurFadeIn') == 1)
    Check('critical muffles hearing', Harness.CountCalls('StartAudioScene') == 1)
    Check('critical shakes camera', Harness.CountCalls('ShakeGameplayCam') >= 2)
    Check('critical blacks out', Harness.CountCalls('DoScreenFadeOut') == 0)
    Check('critical damages health', Harness.CountCalls('SetEntityHealth') == 1)

    local Health = nil

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'SetEntityHealth' then Health = Call.Args[2] end
    end

    Check('damage keeps player alive', Health and Health >= 101, Health)
    Check('damage percent applied', Health and Health < 200, Health)

    Occupant({ NetId = 7, Level = 1, Intensity = 0.5, Seat = 0, Damage = 0, Eject = false, Trapped = false })

    Check('minor crash does not muffle again', Harness.CountCalls('StartAudioScene') == 1)

    Occupant({ NetId = 7, Level = 3, Intensity = 1.0, Seat = 1, Damage = 0, Eject = true, Velocity = { x = 0, y = 20, z = 0 } })

    Check('ejection leaves vehicle', Harness.CountCalls('TaskLeaveVehicle') == 1 or #Threads > 0)

    local Stop = Harness.Handlers['onResourceStop']

    if Stop then Stop('crashphysics') end

    Check('stop clears blur', Harness.CountCalls('TriggerScreenblurFadeOut') >= 1)
end

do
    Harness.ClientEnv()

    local Threads = {}

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    cache.vehicle = 7
    NetworkGetNetworkIdFromEntity = function() return 7 end
    IsEntityDead = function() return false end
    GetEntityHealth = function() return 130 end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/effects.lua'))()

    Harness.Handlers['crashphysics:client:hurt'](500)

    local Health = nil

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'SetEntityHealth' then Health = Call.Args[2] end
    end

    Check('server hurt cannot kill', Health == 101, Health)

    Harness.Handlers['crashphysics:client:hurt']('bad')

    Check('server hurt ignores garbage', Harness.CountCalls('SetEntityHealth') == 1)
end

do
    Harness.ClientEnv()

    local Threads = {}
    local Objects = 0
    local Existing = {}

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    IsModelInCdimage = function() return true end
    CreateObjectNoOffset = function()
        Objects = Objects + 1
        Existing[1000 + Objects] = true

        return 1000 + Objects
    end
    DoesEntityExist = function(Entity) return Existing[Entity] == true end
    DeleteEntity = function(Entity)
        Harness.Record('DeleteEntity', Entity)
        Existing[Entity] = nil
    end
    GetEntityCoords = function() return V(0, 0, 0) end
    exports.ox_target = nil

    Harness.Exports['ox_target:addSphereZone'] = function(Data)
        Harness.Record('addSphereZone', Data.radius)
        Harness.Zone = Data

        return 55
    end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/debris.lua'))()

    local Pieces = {}

    for Id = 1, 8 do
        Pieces[#Pieces + 1] = { Id = Id, Kind = 'Part', Model = 'prop_rub_carpart_02', Offset = { x = Id * 0.5, y = 0.0, z = 0.0 }, Heading = 10.0, Hazard = Id <= 4 }
    end

    Harness.Handlers['crashphysics:client:debrisAdd']({ Id = 1, Coords = { x = 5.0, y = 0.0, z = 0.0 }, Radius = 6.0, Pieces = Pieces, New = true })

    Check('scene zone created', Harness.CountCalls('addSphereZone') == 1)
    Check('zone covers scene radius', Harness.Zone.radius >= 6.0)

    Threads[#Threads] = nil

    local function RunStreamCycle()
        local Cycles = 0

        Wait = function()
            Cycles = Cycles + 1

            if Cycles > 1 then error('stop') end
        end

        for _, Thread in ipairs(Threads) do
            Cycles = 0
            pcall(Thread)
        end
    end

    RunStreamCycle()

    Check('stream budget respected', Objects <= lib.load('config').Debris.CreatesPerCycle and Objects > 0, Objects)

    RunStreamCycle()
    RunStreamCycle()

    Check('all pieces eventually created', Objects == 8, Objects)

    Harness.Handlers['crashphysics:client:debrisRemovePiece'](1, 3)

    Check('removed piece object deleted', Harness.CountCalls('DeleteEntity') == 1)

    Harness.Handlers['crashphysics:client:debrisRemovePiece'](1, 3)
    Harness.Handlers['crashphysics:client:debrisRemovePiece'](9, 1)

    Check('unknown removals are harmless', Harness.CountCalls('DeleteEntity') == 1)

    Harness.Handlers['crashphysics:client:debrisRemoveScene'](1)

    Check('scene removal deletes the rest', Harness.CountCalls('DeleteEntity') == 8, Harness.CountCalls('DeleteEntity'))
end

do
    Harness.ClientEnv()

    local Threads = {}
    local Strengths = {}
    local Amplitudes = {}
    local Cleared = nil

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    cache.vehicle = 7
    NetworkGetNetworkIdFromEntity = function() return 7 end
    IsEntityDead = function() return false end
    GetEntityHealth = function() return 200 end
    SetTimecycleModifierStrength = function(Value) Strengths[#Strengths + 1] = Value end
    SetGameplayCamShakeAmplitude = function(Value) Amplitudes[#Amplitudes + 1] = Value end
    ClearTimecycleModifier = function() Cleared = #Strengths end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/effects.lua'))()

    Harness.Handlers['crashphysics:client:occupant']({ NetId = 7, Level = 3, Score = 60, Intensity = 1.0, Seat = -1, Damage = 0, Eject = false })

    local Iterations = 0

    Wait = function(Milliseconds)
        Harness.Clock = Harness.Clock + math.max(Milliseconds, 16)
        Iterations = Iterations + 1

        if Iterations > 2000 then error('runaway') end
    end

    pcall(Threads[#Threads])

    local Disorient = lib.load('config').Effects.Disorient

    Check('disorientation runs to completion', Cleared ~= nil and Iterations < 2000, Iterations)
    Check('disorientation eases out in steps', #Strengths >= 10, #Strengths)

    local Descending = true

    for Index = 2, #Strengths do
        if Strengths[Index] > Strengths[Index - 1] then Descending = false end
    end

    Check('strength only ever decreases', Descending)
    Check('strength starts near full', Strengths[1] > Disorient.Strength * 0.8, Strengths[1])
    Check('strength ends near zero', Strengths[#Strengths] < Disorient.Strength * 0.2, Strengths[#Strengths])
    Check('camera shake eases too', #Amplitudes >= 10 and Amplitudes[#Amplitudes] < Amplitudes[1])
    Check('effect is only cleared after easing', Cleared == #Strengths)
    Check('walk clipset reset after easing', Harness.CountCalls('ResetPedMovementClipset') == 1)
end

do
    Harness.ClientEnv()

    local Notified = {}
    local Existing = {}
    local Objects = 0
    local Mode = 'ok'

    CreateThread = function() end
    IsModelInCdimage = function() return true end
    CreateObjectNoOffset = function()
        Objects = Objects + 1
        Existing[Objects] = true

        return Objects
    end
    DoesEntityExist = function(Entity) return Existing[Entity] == true end
    GetEntityCoords = function() return V(0, 0, 0) end
    Harness.Exports['ox_target:addSphereZone'] = function(Data)
        Harness.Zone = Data

        return 1
    end
    Harness.Exports['heino_bridge:Notify'] = function(_, Message) Notified[#Notified + 1] = Message end

    lib.callback.await = function(Name, _, SceneId, PieceId)
        if Name == 'crashphysics:server:getDebris' then return {} end
        if Name == 'crashphysics:server:sweepStart' then
            if Mode == 'claimed' and PieceId == 1 then return { Ok = false, Reason = 'Claimed' } end

            return { Ok = true, Duration = 3500 }
        end

        Harness.Handlers['crashphysics:client:debrisRemovePiece'](SceneId, PieceId)

        return { Ok = true, Paid = 0 }
    end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/debris.lua'))()

    local function AddScene()
        local Pieces = {}

        for Id = 1, 3 do
            Pieces[#Pieces + 1] = { Id = Id, Kind = 'Part', Model = 'prop_rub_carpart_02', Offset = { x = Id * 0.5, y = 0.0, z = 0.0 }, Heading = 0.0, Hazard = true }
        end

        Harness.Handlers['crashphysics:client:debrisAdd']({ Id = 1, Coords = { x = 0.0, y = 0.0, z = 0.0 }, Radius = 3.0, Pieces = Pieces, New = true })
    end

    AddScene()

    local Option = Harness.Zone.options[1]

    Check('sweep option available near debris', Option.canInteract() == true)

    Option.onSelect()

    Check('sweep removes every piece', Harness.CountCalls('progressBar') == 3, Harness.CountCalls('progressBar'))
    Check('sweep reports total', Notified[#Notified] == 'Sweep.Done:3', Notified[#Notified])
    Check('sweep option gone when scene empty', Option.canInteract() == false)

    Mode = 'claimed'
    AddScene()
    Harness.Calls = {}
    Notified = {}

    Harness.Zone.options[1].onSelect()

    Check('claimed piece skipped but others swept', Harness.CountCalls('progressBar') == 2, Harness.CountCalls('progressBar'))
    Check('partial sweep reports two', Notified[#Notified] == 'Sweep.Done:2', Notified[#Notified])

    Harness.Calls = {}
    Notified = {}
    Harness.ProgressResult = false
    AddScene()

    Harness.Zone.options[1].onSelect()

    Check('cancelled sweep notifies nothing swept', Notified[#Notified] == 'Sweep.Nothing', Notified[#Notified])
    Check('cancelled sweep tells the server', Harness.CountCalls('server:crashphysics:server:sweepCancel') == 1)

    Harness.ProgressResult = true

    cache.vehicle = 7

    Check('sweep hidden while driving', Harness.Zone.options[1].canInteract() == false)
end

do
    Harness.ClientEnv()

    local Threads = {}
    local State = { Jam = { 60, 0, 0, 0, 0, 0 }, Torn = { 0, 0, 0, 0, 0, 0 }, Window = { 0, 0, 0, 0, 0, 0 }, Level = 3 }
    local Notified = {}

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    cache.vehicle = 7
    cache.seat = -1
    DoesEntityExist = function() return true end
    Entity = function() return { state = { crashphysics = State } } end
    NetworkGetNetworkIdFromEntity = function() return 7 end
    IsEntityDead = function() return false end
    IsVehicleAConvertible = function() return false end
    IsVehicleWindowIntact = function() return true end
    Harness.Exports['heino_bridge:Notify'] = function(_, Message) Notified[#Notified + 1] = Message end

    lib.callback.await = function(Name)
        if Name == 'crashphysics:server:windowBegin' then return { Ok = true, Duration = 3500 } end

        return true
    end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/seatbelt.lua'))()
    assert(loadfile(Harness.Root .. '/client/trapped.lua'))()

    local function RunOnce(Thread)
        local Calls = 0

        Wait = function()
            Calls = Calls + 1

            if Calls > 1 then error('stop') end
        end

        pcall(Thread)
    end

    for _ = 1, 2 do
        for _, Thread in ipairs(Threads) do RunOnce(Thread) end
    end

    Check('jammed seat is trapped', Harness.Exports.IsTrapped() == true)
    Check('trapped hint shown', Harness.CountCalls('showTextUI') == 1)
    Check('exit key denied while trapped', Harness.CountCalls('DisableControlAction') >= 1)
    Check('denied exit explains why', Notified[#Notified] == 'Trapped.Jammed:G', Notified[#Notified])

    Harness.Keybinds.crashphysics_trapped_menu.onPressed()

    Check('trapped menu opens', Harness.Context and #Harness.Context.options == 4)
    Check('window option enabled with intact window', Harness.Context.options[2].disabled == false)
    Check('climb option disabled with intact window', Harness.Context.options[3].disabled == true)

    Harness.Context.options[1].onSelect()

    Check('forcing the door informs the server', Harness.CountCalls('server:crashphysics:server:forceDoor') == 1)

    local Forced = nil

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'server:crashphysics:server:forceDoor' then Forced = Call.Args end
    end

    Check('forcing sends success flag', Forced and Forced[2] == true)

    Harness.Context.options[2].onSelect()

    Check('breaking window uses server duration', Harness.CountCalls('progressBar') == 2)

    Harness.Context.options[4].onSelect()

    Check('help call goes to server', Harness.CountCalls('server:crashphysics:server:callHelp') == 1)

    State.Jam[1] = 0

    for _, Thread in ipairs(Threads) do RunOnce(Thread) end

    Check('freed door ends trapped state', Harness.Exports.IsTrapped() == false)

    State.Jam[1] = 60
    cache.seat = 0

    for _, Thread in ipairs(Threads) do RunOnce(Thread) end

    Check('other seat is not trapped', Harness.Exports.IsTrapped() == false)
    Check('hint hidden when free', Harness.CountCalls('hideTextUI') >= 1)
end

do
    Harness.ClientEnv()

    local Threads = {}
    local State = { Jam = { 0, 70, 0, 0, 0, 0 }, Torn = { 0, 0, 0, 0, 0, 0 }, Window = { 0, 0, 0, 0, 0, 0 }, Level = 3, Body = 500.0, Radiator = 1, Steer = 0.1, Hazards = 1, Time = 0 }
    local Notified = {}
    local Body = 500.0
    local Engine = 800.0

    CreateThread = function(Handler) Threads[#Threads + 1] = Handler end
    cache.vehicle = false
    cache.ped = 1
    DoesEntityExist = function() return true end
    Entity = function() return { state = { crashphysics = State } } end
    GetGamePool = function() return { 7 } end
    GetEntityCoords = function() return V(0, 0, 0) end
    NetworkGetNetworkIdFromEntity = function() return 7 end
    NetworkDoesNetworkIdExist = function() return true end
    NetworkGetEntityFromNetworkId = function() return 7 end
    NetworkHasControlOfEntity = function() return true end
    GetVehicleDoorAngleRatio = function(_, Door) return Door == 1 and 0.6 or 0.0 end
    GetVehiclePedIsTryingToEnter = function() return 7 end
    GetSeatPedIsTryingToEnter = function() return 0 end
    GetVehicleBodyHealth = function() return Body end
    GetVehicleEngineHealth = function() return Engine end
    GetIsVehicleEngineRunning = function() return true end
    GetCloudTimeAsInt = function() return 100000 end
    GetModelDimensions = function() return V(-1, -2.2, 0), V(1, 2.2, 1.5) end
    GetEntityModel = function() return 1 end
    Harness.Exports['heino_bridge:Notify'] = function(_, Message) Notified[#Notified + 1] = Message end

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/doors.lua'))()
    assert(loadfile(Harness.Root .. '/client/vehicle.lua'))()

    local function RunOnce(Thread)
        local Calls = 0

        Wait = function()
            Calls = Calls + 1

            if Calls > 1 then error('stop') end
        end

        pcall(Thread)
    end

    for _ = 1, 2 do
        for _, Thread in ipairs(Threads) do RunOnce(Thread) end
    end

    local Shut = {}

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'SetVehicleDoorShut' then Shut[Call.Args[2]] = true end
    end

    Check('jammed open door is shut again', Shut[1] == true)
    Check('free doors are left alone', Shut[0] == nil and Shut[2] == nil)
    Check('entering through jammed door denied', Harness.CountCalls('ClearPedTasks') >= 1)
    Check('denied entry explains why', Notified[#Notified] == 'Door.EntryJammed', Notified[#Notified])
    Check('radiator leak damages engine', Harness.CountCalls('SetVehicleEngineHealth') >= 1)
    Check('expired hazards switch off', Harness.CountCalls('SetVehicleIndicatorLights') >= 2)

    Harness.Calls = {}

    Harness.Handlers['crashphysics:client:vehicle'](7, {
        EngineLoss = 300.0,
        Tires = { 0, 1 },
        Windows = { 0, 'Windscreen', 5 },
        StallEngine = true,
        DisableEngine = true,
        Alarm = true,
        HornStuck = true,
        Hazards = true,
        Side = 'Front',
        Level = 3,
        Angle = 0.0,
        BodyLoss = 100.0,
    }, { Jammed = { 1 }, Torn = { 2 }, HoodPopped = true, HoodTorn = false })

    local Guard = lib.load('config').Vehicle.ExplosionGuard
    local Floors = {}

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'SetVehiclePetrolTankHealth' or Call.Name == 'SetVehicleEngineHealth' then Floors[Call.Name] = Call.Args[2] end
    end

    Check('tank is kept above the explosion floor', Floors.SetVehiclePetrolTankHealth == nil or Floors.SetVehiclePetrolTankHealth >= Guard.MinTankHealth)
    Check('no fire is scheduled', Harness.CountCalls('StartScriptFire') == 0 and Harness.CountCalls('StartEntityFire') == 0)
    Check('engine damaged', Harness.CountCalls('SetVehicleEngineHealth') >= 1)
    Check('tires burst', Harness.CountCalls('SetVehicleTyreBurst') == 2)
    Check('windows smashed', Harness.CountCalls('SmashVehicleWindow') == 2)

    local Smashed = {}

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'SmashVehicleWindow' then Smashed[Call.Args[2]] = true end
    end

    Check('windscreen index mapped', Smashed[6] == true and Smashed[0] == true and Smashed[nil] == nil)
    Check('door 5 window index missing is skipped', Smashed[5] == nil)
    Check('torn door removed', Harness.CountCalls('SetVehicleDoorBroken') == 1)
    Check('hood popped open', Harness.CountCalls('SetVehicleDoorOpen') == 1)
    Check('engine stalled', Harness.CountCalls('SetVehicleEngineOn') == 1)
    Check('engine disabled', Harness.CountCalls('SetVehicleUndriveable') == 1)
    Check('alarm started', Harness.CountCalls('StartVehicleAlarm') == 1)
    Check('horn stuck', Harness.CountCalls('StartVehicleHorn') == 1)
    Check('hazards switched on', Harness.CountCalls('SetVehicleIndicatorLights') == 2)
    Check('simulated body damage applied', Harness.CountCalls('SetVehicleBodyHealth') == 1)
    Check('baseline scheduled', Harness.CountCalls('SetTimeout') >= 2)

    for _, Callback in ipairs(Harness.Timeouts) do Callback() end

    local Points = lib.load('config').Deformation.Points[3]

    Check('deformation hits the front', Harness.CountCalls('SetVehicleDamage') == Points, Harness.CountCalls('SetVehicleDamage'))

    local Ahead = true

    for _, Call in ipairs(Harness.Calls) do
        if Call.Name == 'SetVehicleDamage' then Ahead = Ahead and Call.Args[3] > 1.0 and math.abs(Call.Args[2]) < 1.0 end
    end

    Check('front deformation sits at the nose', Ahead)

    Harness.Calls = {}
    Body = 900.0

    for _, Thread in ipairs(Threads) do RunOnce(Thread) end

    Check('repair detected after big body gain', Harness.CountCalls('server:crashphysics:server:repaired') == 1)

    for _, Thread in ipairs(Threads) do RunOnce(Thread) end

    Check('repair reported only once', Harness.CountCalls('server:crashphysics:server:repaired') == 1)

    Harness.Handlers['crashphysics:client:cleared'](7)

    Check('clearing resets handling', Harness.CountCalls('SetVehicleSteerBias') >= 1 and Harness.CountCalls('SetVehicleAlarm') >= 1)

    Harness.Calls = {}
    Harness.Handlers['crashphysics:client:vehicle'](7, 'garbage', {})

    Check('garbage vehicle payload ignored', Harness.CountCalls('SetVehicleEngineHealth') == 0)
end

do
    Harness.ClientEnv()

    assert(loadfile(Harness.Root .. '/client/core.lua'))()
    assert(loadfile(Harness.Root .. '/client/detection.lua'))()
    assert(loadfile(Harness.Root .. '/client/effects.lua'))()
    assert(loadfile(Harness.Root .. '/client/seatbelt.lua'))()
    assert(loadfile(Harness.Root .. '/client/trapped.lua'))()
    assert(loadfile(Harness.Root .. '/client/doors.lua'))()
    assert(loadfile(Harness.Root .. '/client/vehicle.lua'))()
    assert(loadfile(Harness.Root .. '/client/debris.lua'))()
    assert(loadfile(Harness.Root .. '/client/interactions.lua'))()

    Check('all client scripts load', true)
    Check('seatbelt keybind registered', Harness.CountCalls('addKeybind') == 2)
    Check('vehicle targets registered', Harness.CountCalls('ox_target:addGlobalVehicle') == 1)
end

print(('%d passed, %d failed'):format(Passed, Failed))

os.exit(Failed == 0 and 0 or 1)

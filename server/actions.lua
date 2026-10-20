local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local LastForce = {}

local function JobMultiplier(Source)
    return Config.Rescue.JobDurationMultiplier[CrashState.Job(Source)] or 1.0
end

local function Hurt(Source, Range)
    TriggerClientEvent('crashphysics:client:hurt', Source, Crash.RandomInt(Range))
end

local function SeatOfPlayer(Source, Vehicle)
    return CrashState.SeatOf(Vehicle, GetPlayerPed(Source))
end

local function ReduceAndSave(Vehicle, State, Door, Range)
    local Freed = CrashDoors.ReduceJam(State, Door, Crash.RandomBetween(Range))

    CrashState.Write(Vehicle, State)

    return Freed
end

RegisterNetEvent('crashphysics:server:forceDoor', function(NetId, Success)
    local Source = source
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not CrashState.IsOccupant(Source, Vehicle) then return end

    local Now = GetGameTimer()

    if LastForce[Source] and Now - LastForce[Source] < Config.Server.ForceDoorMinIntervalMs then return end

    LastForce[Source] = Now

    local Seat = SeatOfPlayer(Source, Vehicle)
    local State = CrashState.Read(Vehicle)
    local Door = Seat and Crash.DoorForSeat(Seat)

    if not Door or not Crash.IsJammed(State, Door) then return end

    Hurt(Source, Config.Trapped.ForceDoor.SelfDamage)

    if Success ~= true then
        CrashState.Notify(Source, locale('Force.Failed'), 'error')

        return
    end

    if ReduceAndSave(Vehicle, State, Door, Config.Trapped.ForceDoor.StrengthRemoved) then
        CrashState.Notify(Source, locale('Force.Freed'), 'success')
        CrashLogs.DoorFreed(Source, CrashState.Plate(Vehicle), Door, 'force')
    else
        CrashState.Notify(Source, locale('Force.Progress'), 'inform')
    end
end)

lib.callback.register('crashphysics:server:windowBegin', function(Source, NetId, Window, Inside)
    if not Config.Trapped.BreakWindow.Enabled then return { Ok = false } end

    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not Crash.IsFinite(Window) or Window < 0 or Window > 3 then return { Ok = false } end

    local State = CrashState.ReadOrEmpty(Vehicle)

    if Crash.IsWindowBroken(State, Window) then return { Ok = false, Reason = 'Broken' } end

    local Settings = Config.Trapped.BreakWindow

    if Inside == true then
        local Seat = CrashState.IsOccupant(Source, Vehicle) and SeatOfPlayer(Source, Vehicle)

        if not Seat or Crash.DoorForSeat(Seat) ~= Window then return { Ok = false } end

        CrashState.BeginAction(Source, { Kind = 'window', Duration = Settings.DurationMs, NetId = NetId, Window = Window, Inside = true })

        return { Ok = true, Duration = Settings.DurationMs }
    end

    if CrashState.IsOccupant(Source, Vehicle) or not CrashState.NearVehicle(Source, Vehicle) then return { Ok = false } end

    CrashState.BeginAction(Source, { Kind = 'window', Duration = Settings.OutsideDurationMs, NetId = NetId, Window = Window, Inside = false })

    return { Ok = true, Duration = Settings.OutsideDurationMs }
end)

lib.callback.register('crashphysics:server:windowEnd', function(Source)
    local Action = CrashState.EndAction(Source, 'window')

    if not Action then return false end

    local Vehicle = CrashState.GetVehicle(Action.NetId)

    if not Vehicle then return false end

    local State = CrashState.ReadOrEmpty(Vehicle)

    State.Window[Action.Window + 1] = 1

    CrashState.Write(Vehicle, State)

    local Owner = NetworkGetEntityOwner(Vehicle)

    if Owner and Owner > 0 then
        TriggerClientEvent('crashphysics:client:smashWindow', Owner, Action.NetId, Action.Window)
    end

    if Action.Inside then Hurt(Source, Config.Trapped.BreakWindow.SelfDamage) end

    return true
end)

lib.callback.register('crashphysics:server:occupants', function(Source, NetId)
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or CrashState.IsOccupant(Source, Vehicle) or not CrashState.NearVehicle(Source, Vehicle) then return {} end

    local State = CrashState.ReadOrEmpty(Vehicle)
    local List = {}

    for _, Occupant in ipairs(CrashState.Occupants(Vehicle)) do
        List[#List + 1] = {
            Target = Occupant.Source,
            Seat = Occupant.Seat,
            CanPull = Crash.CanLeaveSeat(State, Occupant.Seat),
            Dead = Player(Occupant.Source).state.dead == true or Player(Occupant.Source).state.isDead == true,
        }
    end

    return List
end)

lib.callback.register('crashphysics:server:pullBegin', function(Source, NetId, Target)
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not Crash.IsFinite(Target) or Target == Source then return { Ok = false } end
    if CrashState.IsOccupant(Source, Vehicle) or not CrashState.NearVehicle(Source, Vehicle) then return { Ok = false } end
    if not CrashState.IsOccupant(Target, Vehicle) then return { Ok = false } end

    local Seat = SeatOfPlayer(Target, Vehicle)

    if not Seat or not Crash.CanLeaveSeat(CrashState.ReadOrEmpty(Vehicle), Seat) then return { Ok = false, Reason = 'Trapped' } end

    local Duration = math.floor(Config.Rescue.PullDurationMs * JobMultiplier(Source))

    CrashState.BeginAction(Source, { Kind = 'pull', Duration = Duration, NetId = NetId, Target = Target })

    return { Ok = true, Duration = Duration }
end)

lib.callback.register('crashphysics:server:pullEnd', function(Source)
    local Action = CrashState.EndAction(Source, 'pull')

    if not Action then return false end

    local Vehicle = CrashState.GetVehicle(Action.NetId)

    if not Vehicle or not CrashState.NearVehicle(Source, Vehicle) then return false end
    if not CrashState.IsOccupant(Action.Target, Vehicle) then return false end

    TriggerClientEvent('crashphysics:client:pulled', Action.Target, Action.NetId)
    CrashLogs.Pulled(Source, GetPlayerName(Action.Target) or tostring(Action.Target), CrashState.Plate(Vehicle))

    return true
end)

RegisterNetEvent('crashphysics:server:cancelAction', function()
    CrashState.CancelAction(source)
end)

RegisterNetEvent('crashphysics:server:callHelp', function(NetId)
    local Source = source
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not CrashState.IsOccupant(Source, Vehicle) then return end

    if CrashDispatch.Help(Source, GetEntityCoords(Vehicle)) then
        CrashState.Notify(Source, locale('Help.Called'), 'success')
    else
        CrashState.Notify(Source, locale('Help.Cooldown'), 'error')
    end
end)

RegisterNetEvent('crashphysics:server:baseline', function(NetId, Body)
    local Source = source
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not Crash.IsFinite(Body) or NetworkGetEntityOwner(Vehicle) ~= Source then return end

    local State = CrashState.Read(Vehicle)

    if not State then return end

    State.Body = Crash.Clamp(Body, 0.0, 1000.0)

    CrashState.Write(Vehicle, State)
end)

RegisterNetEvent('crashphysics:server:repaired', function(NetId)
    local Source = source
    local Vehicle = CrashState.GetVehicle(NetId)

    if not Vehicle or not CrashState.Read(Vehicle) then return end
    if not CrashState.NearVehicle(Source, Vehicle, Config.Server.RepairClearDistance) then return end

    CrashState.Reset(Vehicle)
end)

RegisterNetEvent('crashphysics:server:belt', function(Belted)
    local Source = source
    local Vehicle = GetVehiclePedIsIn(GetPlayerPed(Source), false)
    local Value = Belted == true and Vehicle ~= 0

    Player(Source).state:set(Config.Seatbelt.StateKey, Value, true)
end)

AddEventHandler('playerDropped', function()
    LastForce[source] = nil
end)

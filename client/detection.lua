local Config = lib.load('config')
local Crash = lib.load('shared.crash')

local Settings = Config.Impact

local Previous
local Window
local CooldownUntil = 0
local TrackedVehicle = 0

local function Reset()
    Previous = nil
    Window = nil
end

local function ValidDoors(Vehicle)
    local List = {}

    for Door = 0, Crash.DoorCount - 1 do
        if GetIsDoorValid(Vehicle, Door) then List[#List + 1] = Door end
    end

    return List
end

local function Snapshot(Vehicle, Now)
    return {
        Time = Now,
        Velocity = GetEntityVelocity(Vehicle),
        Body = GetVehicleBodyHealth(Vehicle),
        Engine = GetVehicleEngineHealth(Vehicle),
        Airborne = IsEntityInAir(Vehicle),
    }
end

local function WeightedMagnitude(Delta)
    local Planar = #vec3(Delta.x, Delta.y, 0.0)
    local Vertical = Delta.z * Settings.VerticalWeight

    return math.sqrt(Planar * Planar + Vertical * Vertical)
end

local function HealthDrop(From, To)
    return math.max(0.0, From.Body - To.Body) + math.max(0.0, From.Engine - To.Engine)
end

local function IsImpactSample(Vehicle, Before, Now, Magnitude)
    if Magnitude < Settings.MinDeltaVelocityMs then return false end

    local Damaged = HealthDrop(Before, Now) > 1.0
    local Violent = Magnitude >= Settings.MinDeltaVelocityMs * 1.8

    if Damaged or HasEntityCollidedWithAnything(Vehicle) then return true end

    return Violent and not (Settings.IgnoreAirborne and Before.Airborne)
end

local function AngleOf(Direction, Window)
    local Forward = Direction.x * Window.Forward.x + Direction.y * Window.Forward.y + Direction.z * Window.Forward.z
    local Right = Direction.x * Window.Right.x + Direction.y * Window.Right.y + Direction.z * Window.Right.z

    return math.deg(math.atan(Right, Forward))
end

local function BeginWindow(Vehicle, Before, Now)
    local Right, Forward = GetEntityMatrix(Vehicle)

    Window = {
        Start = Now.Time,
        PreSnapshot = Before,
        Forward = Forward,
        Right = Right,
        PeakMagnitude = 0.0,
        PeakDirection = vec3(0.0, 0.0, 0.0),
    }
end

local function UpdateWindow(Now)
    local Delta = Window.PreSnapshot.Velocity - Now.Velocity
    local Magnitude = WeightedMagnitude(Delta)

    if Magnitude > Window.PeakMagnitude then
        Window.PeakMagnitude = Magnitude
        Window.PeakDirection = Delta
    end
end

local function BuildReport(Vehicle, Now)
    local Pre = Window.PreSnapshot
    local Lost = HealthDrop(Pre, Now) / 2000.0

    return {
        DeltaV = Window.PeakMagnitude,
        Speed = #Pre.Velocity,
        Angle = AngleOf(Window.PeakDirection, Window),
        HealthLost = Crash.Clamp(Lost, 0.0, 1.0),
        Body = Now.Body,
        Class = GetVehicleClass(Vehicle),
        Doors = ValidDoors(Vehicle),
        Velocity = { x = Pre.Velocity.x, y = Pre.Velocity.y, z = Pre.Velocity.z },
    }
end

local function FinishWindow(Vehicle, Now)
    local Report = BuildReport(Vehicle, Now)
    local Evaluation = Crash.Evaluate(Report)

    Window = nil
    CooldownUntil = Now.Time + Settings.CooldownMs

    CrashClient.Debug('Impact dv=%.1f speed=%.1f angle=%.0f side=%s score=%.0f level=%d',
        Report.DeltaV, Report.Speed, Report.Angle, Evaluation.Side, Evaluation.Score, Evaluation.Level)

    if Evaluation.Level == 0 then return end

    TriggerServerEvent('crashphysics:server:impact', CrashClient.NetId(Vehicle), Report)
end

local function IsMonitored(Vehicle)
    if Settings.ExcludedClasses[GetVehicleClass(Vehicle)] then return false end

    return CrashClient.HasControl(Vehicle)
end

local function Sample(Vehicle)
    local Now = Snapshot(Vehicle, GetGameTimer())

    if Previous then
        if Window then
            UpdateWindow(Now)

            if Now.Time - Window.Start >= Settings.PeakWindowMs then FinishWindow(Vehicle, Now) end
        elseif Now.Time >= CooldownUntil then
            local Magnitude = WeightedMagnitude(Previous.Velocity - Now.Velocity)

            if IsImpactSample(Vehicle, Previous, Now, Magnitude) then
                BeginWindow(Vehicle, Previous, Now)
                UpdateWindow(Now)
            end
        end
    end

    Previous = Now

    if Window or #Now.Velocity >= Settings.IdleSpeedMs then return Settings.SampleIntervalMs end

    return Settings.IdleIntervalMs
end

CreateThread(function()
    while true do
        local Vehicle = cache.vehicle

        if Vehicle and IsMonitored(Vehicle) then
            if Vehicle ~= TrackedVehicle then
                Reset()
                TrackedVehicle = Vehicle
            end

            Wait(Sample(Vehicle))
        else
            Reset()
            TrackedVehicle = 0
            Wait(1000)
        end
    end
end)

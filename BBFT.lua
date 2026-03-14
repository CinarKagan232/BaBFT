-- Build A Boat For Treasure - AutoFarm + UI
-- Not: Oyun update alirsa stage/chest isimleri degisebilir.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local unpackArgs = table.unpack or unpack

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

task.defer(function()
    local missing = {}
    if typeof(fireproximityprompt) ~= "function" then
        table.insert(missing, "fireproximityprompt")
    end
    if typeof(fireclickdetector) ~= "function" then
        table.insert(missing, "fireclickdetector")
    end
    if typeof(firetouchinterest) ~= "function" then
        table.insert(missing, "firetouchinterest")
    end
    if #missing > 0 then
        warn("[BBFT] Executor missing functions: " .. table.concat(missing, ", "))
    end
end)

local autoFarm = false
local running = false
local teamAutoSwitch = false
local teamSwitchInProgress = false
local boatAutoUpright = false
local boatNoDamage = false
local boatEngineMode = "normal"
local boatCustomSpeed = 100
local selectedTeamColorName = "Red"
local isTouchDevice = UserInputService.TouchEnabled
local localPlayerNoclip = false
local localPlayerFly = false
local localPlayerFlySpeed = 80
local farmResumeAfterRespawnAt = os.clock()
local pendingTeamResyncUntil = 0
local farmSessionStartTime = nil
local farmSessionElapsedBase = 0
local farmSessionStartGold = nil
local cachedGoldStat = nil
local lastGoldResolveTry = 0
local STAGE_CENTER_Y_OFFSET = -1.1
local ROOT_ON_GROUND_OFFSET = 2.6
local GROUND_CAST_HEIGHT = 350
local GROUND_CAST_DEPTH = 700
local MAX_STAGE_COUNT = 10
local TP_DELAY = 1.5
local RESPAWN_START_DELAY = 5
local MIN_SAFETY_PART_DROP = 1
local MAX_SAFETY_PART_DROP = 900 -- Clamp limiti dusuk kalirsa guvenli bolge ayni yerde takili kalir.
local SAFETY_PART_EXTRA_DROP = 120 -- Guvenli bolgeyi (ve TP noktasini) birlikte yukariya tasir.
local SAFETY_ROOT_EXTRA_Y_OFFSET = 0 -- Ayaklar guvenli parcanin ustune gelsin.
local SAFETY_PART_FORWARD_Z_OFFSET = 500 -- Guvenli bolgeyi ileri almak icin +, geri almak icin -.
local TEAM_CHECK_INTERVAL = 1
local TEAM_COLOR_OPTIONS = {"Black", "Blue", "Green", "Magenta", "Red", "White", "Yellow"}
local BLACK_BRIGHTNESS_THRESHOLD = 0.12
local BOAT_UPRIGHT_COOLDOWN = 1.2
local BOAT_UPRIGHT_TRIGGER_Y = -0.35
local BOAT_UPRIGHT_LIFT = 3
local BOAT_ENGINE_UPDATE_INTERVAL = 0.05
local BOAT_DAMAGE_GUARD_INTERVAL = 0.05
local BOAT_ENGINE_MIN_SPEED = 1
local BOAT_ENGINE_MAX_SPEED = 500
local BOAT_ENGINE_MIN_THROTTLE = 0.05
local BOAT_GUARD_HEALTH_VALUE = 1000000000
local BOAT_NO_DAMAGE_KEEP_SEAT_TOUCH = true
local BOAT_RAM_PART_NAME = "AF_BoatRam"
local BOAT_RAM_FORWARD_OFFSET = 8
local BOAT_RAM_SIZE = Vector3.new(6, 4, 2)
local BOAT_SHIELD_HEALTH_VALUE = 250000000
local BOAT_SHIELD_TOUCH_DAMAGE = 125000
local BOAT_SHIELD_HIT_COOLDOWN = 0.12
local BOAT_SHIELD_SELF_DAMAGE_PER_HIT = 6000
local BOAT_RECOIL_DELTA_THRESHOLD = 60
local BOAT_RECOIL_KEEP_RATIO = 0.35
local BOAT_RECOIL_MAX_UP_SPEED = 22
local BOAT_RECOIL_MAX_DOWN_SPEED = 110
local BOAT_RECOIL_ANGULAR_THRESHOLD = 8
local BOAT_RECOIL_ANGULAR_DAMPING = 0.22
local LOCAL_PLAYER_FLY_MIN_SPEED = 20
local LOCAL_PLAYER_FLY_MAX_SPEED = 250
local LOCAL_PLAYER_FLY_BODY_POWER = 1000000
local LOCAL_PLAYER_FLY_BODY_GYRO_POWER = 1000000
local LOCAL_PLAYER_FLY_ACCELERATION = 12
local LOCAL_PLAYER_FLY_IDLE_DECEL = 10
local LOCAL_PLAYER_FLY_BOOST_MULTIPLIER = 1.75
local PANEL_TOGGLE_KEY = Enum.KeyCode.G
local currentSafetyPart = nil
local characterVersion = character and 1 or 0
local lastBoatUprightAt = 0
local lastBoatDamageGuardAt = 0
local boatRecoilLastRootPart = nil
local boatRecoilLastLinearVelocity = Vector3.new(0, 0, 0)
local activeCustomVehicleSeat = nil
local currentBoatRamPart = nil
local currentBoatRamTouchConnection = nil
local currentBoatRamOwnerModel = nil
local localFlyBodyVelocity = nil
local localFlyBodyGyro = nil
local localFlyInput = {forward = 0, back = 0, left = 0, right = 0, up = 0, down = 0, boost = 0}
local localFlyCurrentVelocity = Vector3.new(0, 0, 0)
local lastLocalFlyUpdateAt = 0
local panelVisible = true
local scriptClosedPermanently = false
local windUiLoaded = false
local windUiWindow = nil
local windUiToggleKeyName = "H"
local WINDUI_PROFILE_ICON = "https://tr.rbxcdn.com/180DAY-5cc07c05652006d448479ae66212782d/768/432/Image/Webp/noFilter"
local WINDUI_PROFILE_BACKGROUND = "rbxassetid://82503368188240"
local windUiFarmStatParagraph = nil
local windUiToggleKeyButton = nil
local windUiToggleKeyCaptureConnection = nil
local windUiToggleKeyCaptureActive = false
local vehicleSeatDefaults = setmetatable({}, {__mode = "k"})
local boatDamageValueDefaults = setmetatable({}, {__mode = "k"})
local boatDamageAttributeDefaults = setmetatable({}, {__mode = "k"})
local boatPartDefaults = setmetatable({}, {__mode = "k"})
local noclipPartDefaults = setmetatable({}, {__mode = "k"})
local boatShieldTouchCooldowns = setmetatable({}, {__mode = "k"})
local SETTINGS_FILE_NAME = "BBFT_Settings.json"
local supportsSettingsPersistence = (typeof(isfile) == "function" and typeof(readfile) == "function" and typeof(writefile) == "function")
local applyingLoadedSettings = false
local ZERO_VECTOR = Vector3.new(0, 0, 0)
pcall(function()
    if Vector3.zero then
        ZERO_VECTOR = Vector3.zero
    end
end)
localFlyCurrentVelocity = ZERO_VECTOR
boatRecoilLastLinearVelocity = ZERO_VECTOR

function isValidTeamColorOption(value)
    local target = tostring(value or "")
    for _, option in ipairs(TEAM_COLOR_OPTIONS) do
        if option == target then
            return true
        end
    end
    return false
end

function normalizeKeyCodeName(value, fallback)
    local keyName = tostring(value or "")
    keyName = keyName:gsub("^Enum%.KeyCode%.", "")
    keyName = keyName:gsub("%s+", "")
    if keyName == "" then
        return fallback
    end
    if Enum.KeyCode[keyName] then
        return keyName
    end
    return fallback
end

function clampPersistedInteger(value, minValue, maxValue, fallback)
    local numeric = tonumber(value)
    if not numeric then
        return fallback
    end
    return math.clamp(math.floor(numeric + 0.5), minValue, maxValue)
end

function normalizeBoatEngineMode(value)
    local mode = tostring(value or ""):lower()
    if mode == "custom" then
        return "custom"
    end
    return "normal"
end

function buildPersistedSettingsPayload()
    return {
        panelToggleKey = windUiToggleKeyName,
        selectedTeamColorName = selectedTeamColorName,
        teamAutoSwitch = teamAutoSwitch and true or false,
        boatAutoUpright = boatAutoUpright and true or false,
        boatNoDamage = boatNoDamage and true or false,
        boatEngineMode = normalizeBoatEngineMode(boatEngineMode),
        boatCustomSpeed = clampPersistedInteger(boatCustomSpeed, BOAT_ENGINE_MIN_SPEED, BOAT_ENGINE_MAX_SPEED, 100),
        localPlayerNoclip = localPlayerNoclip and true or false,
        localPlayerFly = localPlayerFly and true or false,
        localPlayerFlySpeed = clampPersistedInteger(localPlayerFlySpeed, LOCAL_PLAYER_FLY_MIN_SPEED, LOCAL_PLAYER_FLY_MAX_SPEED, 80)
    }
end

function savePersistedSettings()
    if applyingLoadedSettings or not supportsSettingsPersistence then
        return false
    end

    local payload = buildPersistedSettingsPayload()
    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okEncode or type(encoded) ~= "string" then
        return false
    end

    local okWrite = pcall(function()
        writefile(SETTINGS_FILE_NAME, encoded)
    end)
    return okWrite and true or false
end

function loadPersistedSettings()
    if not supportsSettingsPersistence then
        return
    end

    local okIsFile, exists = pcall(function()
        return isfile(SETTINGS_FILE_NAME)
    end)
    if not okIsFile or not exists then
        return
    end

    local okRead, content = pcall(function()
        return readfile(SETTINGS_FILE_NAME)
    end)
    if not okRead or type(content) ~= "string" or content == "" then
        return
    end

    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not okDecode or type(decoded) ~= "table" then
        return
    end

    applyingLoadedSettings = true

    windUiToggleKeyName = normalizeKeyCodeName(decoded.panelToggleKey, windUiToggleKeyName)
    if isValidTeamColorOption(decoded.selectedTeamColorName) then
        selectedTeamColorName = tostring(decoded.selectedTeamColorName)
    end

    if type(decoded.teamAutoSwitch) == "boolean" then
        teamAutoSwitch = decoded.teamAutoSwitch
    end
    if type(decoded.boatAutoUpright) == "boolean" then
        boatAutoUpright = decoded.boatAutoUpright
    end
    if type(decoded.boatNoDamage) == "boolean" then
        boatNoDamage = decoded.boatNoDamage
    end
    if type(decoded.localPlayerNoclip) == "boolean" then
        localPlayerNoclip = decoded.localPlayerNoclip
    end
    if type(decoded.localPlayerFly) == "boolean" then
        localPlayerFly = decoded.localPlayerFly
    end

    boatEngineMode = normalizeBoatEngineMode(decoded.boatEngineMode)
    boatCustomSpeed = clampPersistedInteger(decoded.boatCustomSpeed, BOAT_ENGINE_MIN_SPEED, BOAT_ENGINE_MAX_SPEED, boatCustomSpeed)
    localPlayerFlySpeed = clampPersistedInteger(decoded.localPlayerFlySpeed, LOCAL_PLAYER_FLY_MIN_SPEED, LOCAL_PLAYER_FLY_MAX_SPEED, localPlayerFlySpeed)

    applyingLoadedSettings = false
end

loadPersistedSettings()

function getPartLinearVelocity(part)
    if not (part and part.Parent and part:IsA("BasePart")) then
        return ZERO_VECTOR
    end

    local velocity = ZERO_VECTOR
    local ok = pcall(function()
        velocity = part.AssemblyLinearVelocity
    end)
    if ok and typeof(velocity) == "Vector3" then
        return velocity
    end

    pcall(function()
        velocity = part.Velocity
    end)
    if typeof(velocity) == "Vector3" then
        return velocity
    end

    return ZERO_VECTOR
end

function getPartAngularVelocity(part)
    if not (part and part.Parent and part:IsA("BasePart")) then
        return ZERO_VECTOR
    end

    local velocity = ZERO_VECTOR
    local ok = pcall(function()
        velocity = part.AssemblyAngularVelocity
    end)
    if ok and typeof(velocity) == "Vector3" then
        return velocity
    end

    pcall(function()
        velocity = part.RotVelocity
    end)
    if typeof(velocity) == "Vector3" then
        return velocity
    end

    return ZERO_VECTOR
end

function setPartLinearVelocity(part, velocity)
    if not (part and part.Parent and part:IsA("BasePart")) then
        return false
    end

    local targetVelocity = (typeof(velocity) == "Vector3") and velocity or ZERO_VECTOR
    local ok = pcall(function()
        part.AssemblyLinearVelocity = targetVelocity
    end)
    if ok then
        return true
    end

    ok = pcall(function()
        part.Velocity = targetVelocity
    end)
    return ok
end

function setPartAngularVelocity(part, velocity)
    if not (part and part.Parent and part:IsA("BasePart")) then
        return false
    end

    local targetVelocity = (typeof(velocity) == "Vector3") and velocity or ZERO_VECTOR
    local ok = pcall(function()
        part.AssemblyAngularVelocity = targetVelocity
    end)
    if ok then
        return true
    end

    ok = pcall(function()
        part.RotVelocity = targetVelocity
    end)
    return ok
end

function stopPartMotion(part)
    setPartLinearVelocity(part, ZERO_VECTOR)
    setPartAngularVelocity(part, ZERO_VECTOR)
end

function clampPositionToBounds(targetPos, boundsCF, boundsSize)
    if not boundsCF or not boundsSize then
        return targetPos
    end

    local localPos = boundsCF:PointToObjectSpace(targetPos)
    local halfX = math.max((boundsSize.X * 0.5) - 1, 0)
    local halfZ = math.max((boundsSize.Z * 0.5) - 1, 0)
    local clampedLocal = Vector3.new(
        math.clamp(localPos.X, -halfX, halfX),
        localPos.Y,
        math.clamp(localPos.Z, -halfZ, halfZ)
    )
    local clampedWorld = boundsCF:PointToWorldSpace(clampedLocal)
    return Vector3.new(clampedWorld.X, targetPos.Y, clampedWorld.Z)
end

function getRoot()
    character = LocalPlayer.Character or character
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

function getHumanoid()
    character = LocalPlayer.Character or character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

function clampLocalPlayerFlySpeed(value)
    return math.clamp(
        math.floor((tonumber(value) or LOCAL_PLAYER_FLY_MIN_SPEED) + 0.5),
        LOCAL_PLAYER_FLY_MIN_SPEED,
        LOCAL_PLAYER_FLY_MAX_SPEED
    )
end

function resetLocalFlyInput()
    localFlyInput.forward = 0
    localFlyInput.back = 0
    localFlyInput.left = 0
    localFlyInput.right = 0
    localFlyInput.up = 0
    localFlyInput.down = 0
    localFlyInput.boost = 0
end

function setLocalFlyInputForKey(keyCode, isDown)
    local value = isDown and 1 or 0
    if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
        localFlyInput.forward = value
    elseif keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
        localFlyInput.back = value
    elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
        localFlyInput.left = value
    elseif keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
        localFlyInput.right = value
    elseif keyCode == Enum.KeyCode.Space then
        localFlyInput.up = value
    elseif keyCode == Enum.KeyCode.LeftControl
        or keyCode == Enum.KeyCode.RightControl
        or keyCode == Enum.KeyCode.Q then
        localFlyInput.down = value
    elseif keyCode == Enum.KeyCode.E then
        localFlyInput.up = value
    elseif keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift then
        localFlyInput.boost = value
    end
end

function getFlyRootPart(char)
    if not char then
        return nil
    end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("UpperTorso")
end

function applyCharacterNoclip()
    local currentCharacter = LocalPlayer.Character or character
    if not currentCharacter then
        return false
    end

    for _, obj in ipairs(currentCharacter:GetDescendants()) do
        if obj:IsA("BasePart") then
            if noclipPartDefaults[obj] == nil then
                noclipPartDefaults[obj] = obj.CanCollide
            end
            pcall(function()
                obj.CanCollide = false
            end)
        end
    end
    return true
end

function restoreCharacterNoclip()
    for part, originalCanCollide in pairs(noclipPartDefaults) do
        if part and part.Parent and part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = originalCanCollide
            end)
        end
        noclipPartDefaults[part] = nil
    end
end

local flyRuntimeActive = false
local flyRuntimeConnections = {}
local flyRuntimeObjects = {}
local flyGamepadAxis = Vector2.new(0, 0)
local flyControl = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}

function clearFlyRuntimeConnections()
    for key, conn in pairs(flyRuntimeConnections) do
        if conn and typeof(conn.Disconnect) == "function" then
            pcall(function()
                conn:Disconnect()
            end)
        end
        flyRuntimeConnections[key] = nil
    end
end

function clearLocalFlyBodyMovers()
    flyRuntimeActive = false
    clearFlyRuntimeConnections()

    pcall(function()
        if flyRuntimeObjects.bv then
            flyRuntimeObjects.bv:Destroy()
        end
        if flyRuntimeObjects.bg then
            flyRuntimeObjects.bg:Destroy()
        end
    end)
    flyRuntimeObjects = {}
    flyGamepadAxis = Vector2.new(0, 0)
    flyControl = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}

    if localFlyBodyVelocity and localFlyBodyVelocity.Parent then
        localFlyBodyVelocity:Destroy()
    end
    if localFlyBodyGyro and localFlyBodyGyro.Parent then
        localFlyBodyGyro:Destroy()
    end
    localFlyBodyVelocity = nil
    localFlyBodyGyro = nil
end

function ensureLocalFlyBodyMovers()
    if flyRuntimeActive then
        return true
    end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local root = getFlyRootPart(char)
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not root then
        return false
    end

    flyRuntimeActive = true
    flyControl = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}

    if humanoid then
        pcall(function()
            humanoid.PlatformStand = true
        end)
    end

    local bg = Instance.new("BodyGyro")
    local bv = Instance.new("BodyVelocity")
    bg.Name = "FlyBodyGyro"
    bg.P = 9e4
    bg.D = 1e3
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.CFrame = root.CFrame
    bg.Parent = root

    bv.Name = "FlyBodyVelocity"
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = ZERO_VECTOR
    bv.Parent = root

    flyRuntimeObjects.bg = bg
    flyRuntimeObjects.bv = bv

    flyRuntimeConnections.inputBegan = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        local keyCode = input.KeyCode
        if keyCode == Enum.KeyCode.W then flyControl.F = 1 end
        if keyCode == Enum.KeyCode.S then flyControl.B = 1 end
        if keyCode == Enum.KeyCode.A then flyControl.L = -1 end
        if keyCode == Enum.KeyCode.D then flyControl.R = 1 end
        if keyCode == Enum.KeyCode.E then flyControl.E = 1 end
        if keyCode == Enum.KeyCode.Q then flyControl.Q = -1 end
    end)

    flyRuntimeConnections.inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        local keyCode = input.KeyCode
        if keyCode == Enum.KeyCode.W then flyControl.F = 0 end
        if keyCode == Enum.KeyCode.S then flyControl.B = 0 end
        if keyCode == Enum.KeyCode.A then flyControl.L = 0 end
        if keyCode == Enum.KeyCode.D then flyControl.R = 0 end
        if keyCode == Enum.KeyCode.E then flyControl.E = 0 end
        if keyCode == Enum.KeyCode.Q then flyControl.Q = 0 end
    end)

    flyRuntimeConnections.inputChanged = UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
            flyGamepadAxis = input.Position or Vector2.new(0, 0)
        end
    end)

    flyRuntimeConnections.heartbeat = RunService.Heartbeat:Connect(function()
        if not flyRuntimeActive then
            return
        end

        if not (root and root.Parent and bv and bg and bv.Parent and bg.Parent) then
            clearLocalFlyBodyMovers()
            return
        end

        local speed = tonumber(localPlayerFlySpeed) or 50
        local cam = workspace.CurrentCamera
        local camLook = (cam and cam.CFrame.LookVector) or root.CFrame.LookVector

        local camYawForward = Vector3.new(camLook.X, 0, camLook.Z)
        if camYawForward.Magnitude <= 0.001 then
            camYawForward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        end
        camYawForward = camYawForward.Unit
        local right = Vector3.new(-camYawForward.Z, 0, camYawForward.X)

        local moveVec = ZERO_VECTOR
        if humanoid and humanoid.MoveDirection and humanoid.MoveDirection.Magnitude > 0.001 then
            moveVec = humanoid.MoveDirection.Unit * speed
        elseif flyGamepadAxis.Magnitude > 0.01 then
            moveVec = (camYawForward * (-flyGamepadAxis.Y) + right * (flyGamepadAxis.X)) * speed
        else
            local keyboardVec = (camYawForward * (flyControl.F - flyControl.B)) + (right * (flyControl.R + flyControl.L))
            if keyboardVec.Magnitude > 0 then
                moveVec = keyboardVec.Unit * (speed * 0.6)
            end
        end

        local verticalFromLook = 0
        if moveVec.Magnitude > 0.05 then
            local horizontalMove = Vector3.new(moveVec.X, 0, moveVec.Z)
            local forwardDot = 0
            if horizontalMove.Magnitude > 0.001 then
                forwardDot = horizontalMove.Unit:Dot(camYawForward)
            end
            verticalFromLook = camLook.Y * speed * forwardDot
        end

        local verticalManual = 0
        if moveVec.Magnitude > 0.05 then
            verticalManual = (flyControl.E + flyControl.Q) * (speed * 0.5)
        end

        local finalVelocity = Vector3.new(moveVec.X, verticalFromLook + verticalManual, moveVec.Z)
        local maxVertical = math.max(speed * 1.2, 50)
        if finalVelocity.Y > maxVertical then
            finalVelocity = Vector3.new(finalVelocity.X, maxVertical, finalVelocity.Z)
        end
        if finalVelocity.Y < -maxVertical then
            finalVelocity = Vector3.new(finalVelocity.X, -maxVertical, finalVelocity.Z)
        end

        bv.Velocity = finalVelocity

        if cam then
            local targetPos = root.Position + camLook
            bg.CFrame = CFrame.new(root.Position, targetPos)
        else
            bg.CFrame = root.CFrame
        end
    end)

    return true
end

function disableLocalFly()
    resetLocalFlyInput()
    clearLocalFlyBodyMovers()
    localFlyCurrentVelocity = ZERO_VECTOR
    lastLocalFlyUpdateAt = 0
    local humanoid = getHumanoid()
    if humanoid then
        pcall(function()
            humanoid.PlatformStand = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
end

function updateLocalFlyMotion()
    if not localPlayerFly then
        return false
    end
    return ensureLocalFlyBodyMovers()
end

function getCurrentSeatPart()
    local humanoid = getHumanoid()
    if not humanoid then
        return nil
    end
    local seatPart = humanoid.SeatPart
    if seatPart and seatPart:IsA("BasePart") and seatPart.Parent then
        return seatPart
    end
    return nil
end

function getCurrentVehicleSeat()
    local seatPart = getCurrentSeatPart()
    if seatPart and seatPart:IsA("VehicleSeat") then
        return seatPart
    end
    return nil
end

function rememberVehicleSeatDefaults(seat)
    if not seat or not seat:IsA("VehicleSeat") then
        return nil
    end
    local defaults = vehicleSeatDefaults[seat]
    if defaults then
        return defaults
    end
    defaults = {
        maxSpeed = seat.MaxSpeed,
        torque = seat.Torque,
        turnSpeed = seat.TurnSpeed
    }
    vehicleSeatDefaults[seat] = defaults
    return defaults
end

function clampBoatSpeedValue(value)
    return math.clamp(
        math.floor((tonumber(value) or BOAT_ENGINE_MIN_SPEED) + 0.5),
        BOAT_ENGINE_MIN_SPEED,
        BOAT_ENGINE_MAX_SPEED
    )
end

function restoreVehicleSeatDefaults(seat)
    if not seat or not seat.Parent or not seat:IsA("VehicleSeat") then
        return
    end
    local defaults = vehicleSeatDefaults[seat]
    if not defaults then
        return
    end
    pcall(function()
        seat.MaxSpeed = defaults.maxSpeed
        seat.Torque = defaults.torque
        seat.TurnSpeed = defaults.turnSpeed
    end)
end

function applyCustomSpeedToVehicleSeat(seat)
    if not seat or not seat.Parent or not seat:IsA("VehicleSeat") then
        return
    end

    local defaults = rememberVehicleSeatDefaults(seat)
    if not defaults then
        return
    end

    local clampedSpeed = clampBoatSpeedValue(boatCustomSpeed)
    boatCustomSpeed = clampedSpeed
    local baseSpeed = math.max(defaults.maxSpeed or BOAT_ENGINE_MIN_SPEED, BOAT_ENGINE_MIN_SPEED)
    local ratio = clampedSpeed / baseSpeed
    local baseTorque = defaults.torque or seat.Torque
    local baseTurnSpeed = defaults.turnSpeed or seat.TurnSpeed

    pcall(function()
        seat.MaxSpeed = clampedSpeed
        seat.Torque = math.max(baseTorque, baseTorque * ratio)
        seat.TurnSpeed = math.max(baseTurnSpeed, baseTurnSpeed * math.sqrt(math.max(1, ratio)))
    end)
end

function applyCustomVelocityBoostToVehicleSeat(seat)
    if not seat or not seat.Parent or not seat:IsA("VehicleSeat") then
        return
    end

    local throttle = 0
    pcall(function()
        throttle = tonumber(seat.ThrottleFloat) or 0
    end)
    if math.abs(throttle) < BOAT_ENGINE_MIN_THROTTLE then
        pcall(function()
            throttle = tonumber(seat.Throttle) or throttle
        end)
    end
    if math.abs(throttle) < BOAT_ENGINE_MIN_THROTTLE then
        return
    end

    local rootPart = seat.AssemblyRootPart
    if not (rootPart and rootPart:IsA("BasePart") and rootPart.Parent and not rootPart.Anchored) then
        rootPart = seat
    end
    if not rootPart then
        return
    end

    local look = seat.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.001 then
        return
    end
    flatLook = flatLook.Unit

    local targetSpeed = clampBoatSpeedValue(boatCustomSpeed) * throttle
    local currentVel = getPartLinearVelocity(rootPart)
    local targetHorizontal = flatLook * targetSpeed

    setPartLinearVelocity(rootPart, Vector3.new(targetHorizontal.X, currentVel.Y, targetHorizontal.Z))
end

function updateBoatEnginePowerForSeat()
    local vehicleSeat = getCurrentVehicleSeat()

    if activeCustomVehicleSeat and activeCustomVehicleSeat ~= vehicleSeat then
        restoreVehicleSeatDefaults(activeCustomVehicleSeat)
        activeCustomVehicleSeat = nil
    end

    if not vehicleSeat then
        return
    end

    if boatEngineMode == "custom" then
        applyCustomSpeedToVehicleSeat(vehicleSeat)
        applyCustomVelocityBoostToVehicleSeat(vehicleSeat)
        activeCustomVehicleSeat = vehicleSeat
    else
        restoreVehicleSeatDefaults(vehicleSeat)
        if activeCustomVehicleSeat == vehicleSeat then
            activeCustomVehicleSeat = nil
        end
    end
end

function getSeatAssemblyRootPart(seatPart)
    if not seatPart or not seatPart.Parent then
        return nil
    end
    local rootPart = seatPart.AssemblyRootPart
    if rootPart and rootPart:IsA("BasePart") and rootPart.Parent and not rootPart.Anchored then
        return rootPart
    end
    if seatPart:IsA("BasePart") and not seatPart.Anchored then
        return seatPart
    end
    return nil
end

function clearBoatRamPart()
    if currentBoatRamTouchConnection then
        pcall(function()
            currentBoatRamTouchConnection:Disconnect()
        end)
        currentBoatRamTouchConnection = nil
    end
    currentBoatRamOwnerModel = nil
    for hitPart, _ in pairs(boatShieldTouchCooldowns) do
        boatShieldTouchCooldowns[hitPart] = nil
    end

    if currentBoatRamPart and currentBoatRamPart.Parent then
        currentBoatRamPart:Destroy()
    end
    currentBoatRamPart = nil
end

function ensureBoatRamPart(rootPart)
    if not (rootPart and rootPart.Parent and rootPart:IsA("BasePart")) then
        clearBoatRamPart()
        return nil
    end

    local parentTarget = rootPart:FindFirstAncestorOfClass("Model") or rootPart.Parent or workspace
    local ramPart = currentBoatRamPart
    if not (ramPart and ramPart.Parent and ramPart:IsA("BasePart")) then
        ramPart = Instance.new("Part")
        ramPart.Name = BOAT_RAM_PART_NAME
        ramPart.Size = BOAT_RAM_SIZE
        ramPart.Transparency = 1
        ramPart.Massless = true
        ramPart.CanCollide = false
        ramPart.CanTouch = true
        ramPart.CanQuery = true
        ramPart.CastShadow = false
        ramPart.Material = Enum.Material.SmoothPlastic
        ramPart.Color = Color3.fromRGB(255, 255, 255)
        ramPart.Parent = parentTarget
        currentBoatRamPart = ramPart
    elseif ramPart.Parent ~= parentTarget then
        ramPart.Parent = parentTarget
    end

    local function ensureShieldValueObject(valueName)
        local valueObj = ramPart:FindFirstChild(valueName)
        if not (valueObj and valueObj:IsA("NumberValue")) then
            if valueObj and valueObj.Parent then
                pcall(function()
                    valueObj:Destroy()
                end)
            end
            valueObj = Instance.new("NumberValue")
            valueObj.Name = valueName
            valueObj.Value = BOAT_SHIELD_HEALTH_VALUE
            valueObj.Parent = ramPart
            return
        end
        if tonumber(valueObj.Value) == nil then
            pcall(function()
                valueObj.Value = BOAT_SHIELD_HEALTH_VALUE
            end)
        end
    end

    ensureShieldValueObject("Health")
    ensureShieldValueObject("Durability")
    if type(ramPart:GetAttribute("Health")) ~= "number" then
        pcall(function()
            ramPart:SetAttribute("Health", BOAT_SHIELD_HEALTH_VALUE)
        end)
    end
    if type(ramPart:GetAttribute("Durability")) ~= "number" then
        pcall(function()
            ramPart:SetAttribute("Durability", BOAT_SHIELD_HEALTH_VALUE)
        end)
    end

    local desiredCF = rootPart.CFrame * CFrame.new(0, 0, -((rootPart.Size.Z * 0.5) + BOAT_RAM_FORWARD_OFFSET))
    ramPart.CFrame = desiredCF
    setPartLinearVelocity(ramPart, getPartLinearVelocity(rootPart))
    setPartAngularVelocity(ramPart, getPartAngularVelocity(rootPart))

    local weld = ramPart:FindFirstChild("AF_RamWeld")
    if not (weld and weld:IsA("WeldConstraint")) then
        for _, obj in ipairs(ramPart:GetChildren()) do
            if obj:IsA("WeldConstraint") then
                obj:Destroy()
            end
        end
        weld = Instance.new("WeldConstraint")
        weld.Name = "AF_RamWeld"
        weld.Part0 = ramPart
        weld.Part1 = rootPart
        weld.Parent = ramPart
    elseif weld.Part1 ~= rootPart or weld.Part0 ~= ramPart then
        weld.Part0 = ramPart
        weld.Part1 = rootPart
    end

    local ownerModel = rootPart:FindFirstAncestorOfClass("Model")
    if not currentBoatRamTouchConnection or currentBoatRamOwnerModel ~= ownerModel then
        if currentBoatRamTouchConnection then
            pcall(function()
                currentBoatRamTouchConnection:Disconnect()
            end)
            currentBoatRamTouchConnection = nil
        end
        currentBoatRamOwnerModel = ownerModel
        currentBoatRamTouchConnection = ramPart.Touched:Connect(function(hitPart)
            if not (hitPart and hitPart.Parent and hitPart:IsA("BasePart")) then
                return
            end
            if hitPart == ramPart then
                return
            end
            if ownerModel and hitPart:IsDescendantOf(ownerModel) then
                return
            end
            if hitPart.Name == "AF_SafetyPart" then
                return
            end

            local now = os.clock()
            local lastHitAt = boatShieldTouchCooldowns[hitPart]
            if lastHitAt and (now - lastHitAt) < BOAT_SHIELD_HIT_COOLDOWN then
                return
            end
            boatShieldTouchCooldowns[hitPart] = now

            local shieldHealthValueObj = ramPart:FindFirstChild("Health")
            local shieldHealth = nil
            if shieldHealthValueObj and (shieldHealthValueObj:IsA("IntValue") or shieldHealthValueObj:IsA("NumberValue")) then
                shieldHealth = tonumber(shieldHealthValueObj.Value)
            end
            if shieldHealth == nil then
                local attrHealth = ramPart:GetAttribute("Health")
                if type(attrHealth) == "number" then
                    shieldHealth = attrHealth
                end
            end
            if shieldHealth ~= nil and shieldHealth <= 0 then
                return
            end

            local function applyDamageToHealthLike(instance, damageAmount)
                if not (instance and instance.Parent) then
                    return 0
                end

                local changed = 0
                local attrs = instance:GetAttributes()
                for attrName, attrValue in pairs(attrs) do
                    if type(attrValue) == "number" and isHealthLikeKey(attrName) then
                        local nextValue = math.max(0, attrValue - damageAmount)
                        if nextValue ~= attrValue then
                            pcall(function()
                                instance:SetAttribute(attrName, nextValue)
                            end)
                            changed = changed + 1
                        end
                    end
                end

                for _, child in ipairs(instance:GetChildren()) do
                    if (child:IsA("IntValue") or child:IsA("NumberValue")) and isHealthLikeKey(child.Name) then
                        local current = tonumber(child.Value)
                        if current then
                            local nextValue = math.max(0, current - damageAmount)
                            if child:IsA("IntValue") then
                                nextValue = math.floor(nextValue + 0.5)
                            end
                            if nextValue ~= current then
                                pcall(function()
                                    child.Value = nextValue
                                end)
                                changed = changed + 1
                            end
                        end
                    end
                end

                return changed
            end

            applyDamageToHealthLike(ramPart, BOAT_SHIELD_SELF_DAMAGE_PER_HIT)

            local changedCount = applyDamageToHealthLike(hitPart, BOAT_SHIELD_TOUCH_DAMAGE)
            local hitModel = hitPart:FindFirstAncestorOfClass("Model")
            if hitModel and (not ownerModel or not hitModel:IsDescendantOf(ownerModel)) then
                changedCount = changedCount + applyDamageToHealthLike(hitModel, BOAT_SHIELD_TOUCH_DAMAGE)
            end

            if changedCount == 0 then
                local assemblyRoot = hitPart.AssemblyRootPart
                if assemblyRoot and assemblyRoot:IsA("BasePart") and assemblyRoot ~= ramPart then
                    local push = ramPart.CFrame.LookVector * BOAT_SHIELD_TOUCH_DAMAGE * 0.0004
                    local currentVel = getPartLinearVelocity(assemblyRoot)
                    setPartLinearVelocity(assemblyRoot, currentVel + push)
                end
            end
        end)
    end

    return ramPart
end

function isHealthLikeKey(name)
    local key = tostring(name or ""):lower()
    if key == "" then
        return false
    end

    return key:find("health", 1, true)
        or key:find("durability", 1, true)
        or key:find("hitpoint", 1, true)
        or key:find("hitpoints", 1, true)
        or key:find("integrity", 1, true)
        or key:find("strength", 1, true)
        or key == "hp"
end

function rememberAndProtectNumericValue(valueObj)
    if not (valueObj and valueObj.Parent and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue"))) then
        return false
    end
    if not isHealthLikeKey(valueObj.Name) then
        return false
    end

    if boatDamageValueDefaults[valueObj] == nil then
        boatDamageValueDefaults[valueObj] = valueObj.Value
    end

    local current = tonumber(valueObj.Value) or 0
    local target = BOAT_GUARD_HEALTH_VALUE
    if valueObj:IsA("IntValue") then
        target = math.floor(target + 0.5)
    end

    if current < target then
        pcall(function()
            valueObj.Value = target
        end)
    end

    return true
end

function rememberAndProtectNumericAttributes(instance)
    if not (instance and instance.Parent and (instance:IsA("BasePart") or instance:IsA("Model"))) then
        return 0
    end

    local protectedCount = 0
    local attrs = instance:GetAttributes()
    for attrName, attrValue in pairs(attrs) do
        if type(attrValue) == "number" and isHealthLikeKey(attrName) then
            local defaults = boatDamageAttributeDefaults[instance]
            if not defaults then
                defaults = {}
                boatDamageAttributeDefaults[instance] = defaults
            end
            if defaults[attrName] == nil then
                defaults[attrName] = attrValue
            end

            if attrValue < BOAT_GUARD_HEALTH_VALUE then
                pcall(function()
                    instance:SetAttribute(attrName, BOAT_GUARD_HEALTH_VALUE)
                end)
            end
            protectedCount = protectedCount + 1
        end
    end

    return protectedCount
end

function rememberAndProtectBoatPart(part, seatPart)
    if not (part and part.Parent and part:IsA("BasePart")) then
        return false
    end

    if currentBoatRamPart and part == currentBoatRamPart then
        return false
    end

    local isSeatPart = (seatPart and part == seatPart) and true or false

    local defaults = boatPartDefaults[part]
    if not defaults then
        defaults = {
            canTouch = part.CanTouch,
            canQuery = part.CanQuery
        }
        boatPartDefaults[part] = defaults
    end

    if not (BOAT_NO_DAMAGE_KEEP_SEAT_TOUCH and isSeatPart) then
        pcall(function()
            part.CanTouch = false
        end)
        pcall(function()
            part.CanQuery = false
        end)
    end

    return true
end

function getBoatAssemblyRootAndModel()
    local seatPart = getCurrentSeatPart()
    if not seatPart then
        return nil, nil
    end

    local rootPart = getSeatAssemblyRootPart(seatPart)
    if not rootPart then
        return nil, nil
    end

    local boatModel = rootPart:FindFirstAncestorOfClass("Model")
    return rootPart, boatModel
end

function resetBoatRecoilGuard()
    boatRecoilLastRootPart = nil
    boatRecoilLastLinearVelocity = ZERO_VECTOR
end

function mitigateBoatRecoil(rootPart)
    if not (rootPart and rootPart.Parent and rootPart:IsA("BasePart")) then
        resetBoatRecoilGuard()
        return
    end

    local currentLinear = getPartLinearVelocity(rootPart)
    local adjustedLinear = currentLinear

    if boatRecoilLastRootPart ~= rootPart then
        boatRecoilLastRootPart = rootPart
        boatRecoilLastLinearVelocity = currentLinear
    else
        local delta = currentLinear - boatRecoilLastLinearVelocity
        if delta.Magnitude >= BOAT_RECOIL_DELTA_THRESHOLD then
            adjustedLinear = boatRecoilLastLinearVelocity + (delta * BOAT_RECOIL_KEEP_RATIO)
        end
    end

    local clampedY = math.clamp(adjustedLinear.Y, -BOAT_RECOIL_MAX_DOWN_SPEED, BOAT_RECOIL_MAX_UP_SPEED)
    if clampedY ~= adjustedLinear.Y then
        adjustedLinear = Vector3.new(adjustedLinear.X, clampedY, adjustedLinear.Z)
    end

    if (adjustedLinear - currentLinear).Magnitude > 0.05 then
        setPartLinearVelocity(rootPart, adjustedLinear)
    end

    local currentAngular = getPartAngularVelocity(rootPart)
    if currentAngular.Magnitude >= BOAT_RECOIL_ANGULAR_THRESHOLD then
        local dampedAngular = currentAngular * BOAT_RECOIL_ANGULAR_DAMPING
        setPartAngularVelocity(rootPart, dampedAngular)
    end

    boatRecoilLastRootPart = rootPart
    boatRecoilLastLinearVelocity = adjustedLinear
end

function guardCurrentBoatAgainstDamage()
    local rootPart, boatModel = getBoatAssemblyRootAndModel()
    if not rootPart then
        clearBoatRamPart()
        resetBoatRecoilGuard()
        return false, 0
    end

    local ramPart = ensureBoatRamPart(rootPart)
    if ramPart then
        local defaults = boatPartDefaults[ramPart]
        if not defaults then
            defaults = {
                canTouch = ramPart.CanTouch,
                canQuery = ramPart.CanQuery
            }
            boatPartDefaults[ramPart] = defaults
        end
        pcall(function()
            ramPart.CanTouch = true
            ramPart.CanQuery = true
        end)
    end

    mitigateBoatRecoil(rootPart)

    local protectedCount = 0
    local protectedPartCount = 0
    local seen = {}
    local seatPart = getCurrentSeatPart()

    local function processInstance(instance)
        if not instance or seen[instance] then
            return
        end
        seen[instance] = true

        if currentBoatRamPart and (instance == currentBoatRamPart or instance:IsDescendantOf(currentBoatRamPart)) then
            return
        end

        if instance:IsA("IntValue") or instance:IsA("NumberValue") then
            if rememberAndProtectNumericValue(instance) then
                protectedCount = protectedCount + 1
            end
            return
        end

        if instance:IsA("BasePart") then
            if rememberAndProtectBoatPart(instance, seatPart) then
                protectedPartCount = protectedPartCount + 1
            end
            protectedCount = protectedCount + rememberAndProtectNumericAttributes(instance)
        elseif instance:IsA("Model") then
            protectedCount = protectedCount + rememberAndProtectNumericAttributes(instance)
        end

        for _, desc in ipairs(instance:GetDescendants()) do
            if not seen[desc] then
                seen[desc] = true
                if currentBoatRamPart and (desc == currentBoatRamPart or desc:IsDescendantOf(currentBoatRamPart)) then
                    continue
                end
                if desc:IsA("IntValue") or desc:IsA("NumberValue") then
                    if rememberAndProtectNumericValue(desc) then
                        protectedCount = protectedCount + 1
                    end
                elseif desc:IsA("BasePart") then
                    if rememberAndProtectBoatPart(desc, seatPart) then
                        protectedPartCount = protectedPartCount + 1
                    end
                    protectedCount = protectedCount + rememberAndProtectNumericAttributes(desc)
                elseif desc:IsA("Model") then
                    protectedCount = protectedCount + rememberAndProtectNumericAttributes(desc)
                end
            end
        end
    end

    processInstance(rootPart)
    for _, part in ipairs(rootPart:GetConnectedParts(true)) do
        processInstance(part)
    end
    if boatModel then
        processInstance(boatModel)
    end

    return true, (protectedCount + protectedPartCount)
end

function restoreBoatDamageDefaults()
    for valueObj, originalValue in pairs(boatDamageValueDefaults) do
        if valueObj and valueObj.Parent and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue")) then
            pcall(function()
                valueObj.Value = originalValue
            end)
        end
        boatDamageValueDefaults[valueObj] = nil
    end

    for instance, defaults in pairs(boatDamageAttributeDefaults) do
        if instance and instance.Parent and defaults then
            for attrName, originalValue in pairs(defaults) do
                pcall(function()
                    instance:SetAttribute(attrName, originalValue)
                end)
            end
        end
        boatDamageAttributeDefaults[instance] = nil
    end

    for part, defaults in pairs(boatPartDefaults) do
        if part and part.Parent and part:IsA("BasePart") and defaults then
            pcall(function()
                part.CanTouch = defaults.canTouch
            end)
            pcall(function()
                part.CanQuery = defaults.canQuery
            end)
        end
        boatPartDefaults[part] = nil
    end

    clearBoatRamPart()
    resetBoatRecoilGuard()
end

function tryAutoUprightBoat()
    if not boatAutoUpright then
        return
    end

    local seatPart = getCurrentSeatPart()
    if not seatPart then
        return
    end

    local rootPart = getSeatAssemblyRootPart(seatPart)
    if not rootPart then
        return
    end

    if rootPart.CFrame.UpVector.Y > BOAT_UPRIGHT_TRIGGER_Y then
        return
    end

    local now = os.clock()
    if (now - lastBoatUprightAt) < BOAT_UPRIGHT_COOLDOWN then
        return
    end
    lastBoatUprightAt = now

    local look = rootPart.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.001 then
        flatLook = Vector3.new(0, 0, -1)
    else
        flatLook = flatLook.Unit
    end

    local targetPos = rootPart.Position + Vector3.new(0, BOAT_UPRIGHT_LIFT, 0)
    local uprightCF = CFrame.lookAt(targetPos, targetPos + flatLook, Vector3.new(0, 1, 0))

    pcall(function()
        stopPartMotion(rootPart)
        rootPart.CFrame = uprightCF
    end)
end

function clearSafetyPart()
    if currentSafetyPart and currentSafetyPart.Parent then
        currentSafetyPart:Destroy()
    end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("BasePart") and obj.Name == "AF_SafetyPart" then
            obj:Destroy()
        end
    end
    currentSafetyPart = nil
end

function isDoorLikeSurface(part)
    local name = part.Name:lower()
    if name:find("door") or name:find("gate") or name:find("portal") or name:find("entrance") or name:find("entry") or name:find("wall") then
        return true
    end

    local width = math.max(part.Size.X, part.Size.Z)
    local depth = math.min(part.Size.X, part.Size.Z)
    if part.Size.Y >= 8 and depth <= 8 then
        return true
    end
    if part.Size.Y >= 12 and width <= 14 then
        return true
    end

    return false
end

function getDynamicSafetyDrop(position)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if character then
        table.insert(ignore, character)
    end
    if currentSafetyPart and currentSafetyPart.Parent then
        table.insert(ignore, currentSafetyPart)
    end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true

    local originY = position.Y + 32
    local minY = position.Y - 160
    local rayOriginY = originY
    local bestY = nil
    local bestScore = -math.huge

    for _ = 1, 16 do
        local castDepth = rayOriginY - minY
        if castDepth <= 0 then break end

        local result = workspace:Raycast(
            Vector3.new(position.X, rayOriginY, position.Z),
            Vector3.new(0, -castDepth, 0),
            params
        )
        if not result then break end

        local hitPart = result.Instance
        if hitPart and hitPart:IsA("BasePart") and hitPart.CanCollide and hitPart.Name ~= "AF_SafetyPart" then
            local name = hitPart.Name:lower()
            local score = (hitPart.Size.X * hitPart.Size.Z) - (hitPart.Size.Y * 6)
            if isDoorLikeSurface(hitPart) then score = score - 280 end
            if name:find("black") or name:find("void") or name:find("kill") or name:find("lava") then
                score = score - 500
            end
            local brightness = (hitPart.Color.R + hitPart.Color.G + hitPart.Color.B) / 3
            if brightness < BLACK_BRIGHTNESS_THRESHOLD then
                score = score - 320
            end
            if hitPart.Transparency > 0.75 then score = score - 120 end
            if hitPart.Anchored then score = score + 15 end

            if score > bestScore then
                bestScore = score
                bestY = result.Position.Y
            end
        end

        rayOriginY = result.Position.Y - 0.25
    end

    if bestY then
        local desiredTopY = bestY - 58
        local dynamicDrop = position.Y - (desiredTopY - 0.5)
        return math.clamp(dynamicDrop, MIN_SAFETY_PART_DROP, MAX_SAFETY_PART_DROP)
    end

    return MIN_SAFETY_PART_DROP
end

function createSafetyPart(position, boundsCF, boundsSize)
    local part = currentSafetyPart
    if not (part and part.Parent) then
        part = Instance.new("Part")
        part.Name = "AF_SafetyPart"
        part.Size = Vector3.new(14, 1, 14)
        part.Anchored = true
        part.CanCollide = true
        part.Transparency = 0.2
        part.Material = Enum.Material.ForceField
        part.Color = Color3.fromRGB(70, 160, 255)
        part.Parent = workspace
        currentSafetyPart = part
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj ~= part and obj:IsA("BasePart") and obj.Name == "AF_SafetyPart" then
            obj:Destroy()
        end
    end

    local safetyDrop = getDynamicSafetyDrop(position)
    local finalDrop = math.clamp(safetyDrop + SAFETY_PART_EXTRA_DROP, MIN_SAFETY_PART_DROP, MAX_SAFETY_PART_DROP)
    local safetyBasePos = position + Vector3.new(0, 0, SAFETY_PART_FORWARD_Z_OFFSET)
    safetyBasePos = clampPositionToBounds(safetyBasePos, boundsCF, boundsSize)
    part.CFrame = CFrame.new(safetyBasePos - Vector3.new(0, finalDrop, 0))
    return part
end

LocalPlayer.CharacterAdded:Connect(function(c)
    character = c
    characterVersion = characterVersion + 1
    lastCharacterAddedAt = os.clock()
    farmResumeAfterRespawnAt = os.clock() + RESPAWN_START_DELAY
    clearLocalFlyBodyMovers()
    resetLocalFlyInput()
    localFlyCurrentVelocity = ZERO_VECTOR
    lastLocalFlyUpdateAt = 0
    if localPlayerFly then
        task.defer(function()
            if localPlayerFly and not scriptClosedPermanently then
                ensureLocalFlyBodyMovers()
            end
        end)
    end
    if teamAutoSwitch then
        pendingTeamResyncUntil = os.clock() + 8
    end
    clearSafetyPart()
end)

function tp(position, useSafetyPart, boundsCF, boundsSize)
    local root = getRoot()
    if not root then return end
    if useSafetyPart == nil then
        useSafetyPart = true
    end

    local targetPosition = position

    if useSafetyPart then
        local safetyPart = createSafetyPart(position, boundsCF, boundsSize)
        if safetyPart then
            local safetyTopY = safetyPart.Position.Y + (safetyPart.Size.Y * 0.5)
            local rootHalfY = root.Size.Y * 0.5
            targetPosition = Vector3.new(safetyPart.Position.X, safetyTopY + rootHalfY + SAFETY_ROOT_EXTRA_Y_OFFSET, safetyPart.Position.Z)
        end
    else
        clearSafetyPart()
    end

    root.CFrame = CFrame.new(targetPosition)
    stopPartMotion(root)
end

function getStageContainer()
    local bs = workspace:FindFirstChild("BoatStages")
    if bs and bs:FindFirstChild("NormalStages") then
        return bs.NormalStages
    end
    return workspace:FindFirstChild("NormalStages")
end

function getStageBounds(stageObj)
    if stageObj:IsA("Model") then
        return stageObj:GetBoundingBox()
    elseif stageObj:IsA("BasePart") then
        return stageObj.CFrame, stageObj.Size
    end
    return nil, nil
end

function clampTargetToBounds(targetPos, boundsCF, boundsSize)
    if not boundsCF or not boundsSize then
        return targetPos
    end

    local localPos = boundsCF:PointToObjectSpace(targetPos)
    local halfX = math.max((boundsSize.X * 0.5) - 1, 0)
    local halfZ = math.max((boundsSize.Z * 0.5) - 1, 0)
    local clampedLocal = Vector3.new(
        math.clamp(localPos.X, -halfX, halfX),
        localPos.Y,
        math.clamp(localPos.Z, -halfZ, halfZ)
    )
    local clampedWorld = boundsCF:PointToWorldSpace(clampedLocal)
    return Vector3.new(clampedWorld.X, targetPos.Y, clampedWorld.Z)
end

function isBlackHazardPart(part)
    local name = part.Name:lower()
    if name:find("void") or name:find("kill") or name:find("lava") then
        return true
    end

    local brightness = (part.Color.R + part.Color.G + part.Color.B) / 3
    local isBlackByColor = brightness <= BLACK_BRIGHTNESS_THRESHOLD
    local isBlackByName = name:find("black") ~= nil
    if not isBlackByColor and not isBlackByName then
        return false
    end

    local footprint = part.Size.X * part.Size.Z
    return footprint >= 6
end

function getBlackHazardParts(stageObj)
    local hazards = {}
    if stageObj:IsA("Model") then
        for _, obj in ipairs(stageObj:GetDescendants()) do
            if obj:IsA("BasePart") and isBlackHazardPart(obj) then
                table.insert(hazards, obj)
            end
        end
    elseif stageObj:IsA("BasePart") then
        if isBlackHazardPart(stageObj) then
            table.insert(hazards, stageObj)
        end
    end
    return hazards
end

function getHorizontalDistanceAndAwayDir(point, part)
    local localPoint = part.CFrame:PointToObjectSpace(point)
    local halfX = part.Size.X * 0.5
    local halfZ = part.Size.Z * 0.5

    local nearestLocal = Vector3.new(
        math.clamp(localPoint.X, -halfX, halfX),
        0,
        math.clamp(localPoint.Z, -halfZ, halfZ)
    )
    local nearestWorld = part.CFrame:PointToWorldSpace(nearestLocal)
    local away = Vector3.new(point.X - nearestWorld.X, 0, point.Z - nearestWorld.Z)
    local dist = away.Magnitude

    if dist < 0.001 then
        away = Vector3.new(point.X - part.Position.X, 0, point.Z - part.Position.Z)
        dist = away.Magnitude
    end
    if dist < 0.001 then
        away = Vector3.new(1, 0, 0)
    end

    return dist, away.Unit
end

function offsetTargetFromBlackParts(stageObj, targetPos, boundsCF, boundsSize)
    local hazards = getBlackHazardParts(stageObj)
    if #hazards == 0 then
        return clampTargetToBounds(targetPos, boundsCF, boundsSize)
    end

    local adjusted = clampTargetToBounds(targetPos, boundsCF, boundsSize)
    for _ = 1, 4 do
        local moved = false
        for _, hazardPart in ipairs(hazards) do
            if hazardPart and hazardPart.Parent then
                local dist, awayDir = getHorizontalDistanceAndAwayDir(adjusted, hazardPart)
                if dist < BLACK_AVOID_DISTANCE then
                    local push = (BLACK_AVOID_DISTANCE - dist) + 0.5
                    adjusted = adjusted + (awayDir * push)
                    adjusted = clampTargetToBounds(adjusted, boundsCF, boundsSize)
                    moved = true
                end
            end
        end
        if not moved then
            break
        end
    end

    return adjusted
end

function getStageFloorPart(stageModel)
    local modelCF = stageModel:GetBoundingBox()
    local centerY = modelCF.Position.Y
    local bestPart = nil
    local bestScore = -math.huge

    for _, obj in ipairs(stageModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            if obj.Size.X >= 4 and obj.Size.Z >= 4 and obj.Size.Y <= 12 then
                local score = (obj.Size.X * obj.Size.Z) - (obj.Size.Y * 8)
                local name = obj.Name:lower()

                if name:find("floor") or name:find("ground") or name:find("stage") or name:find("base") then
                    score = score + 180
                end
                if name:find("black") or name:find("void") or name:find("kill") or name:find("lava") then
                    score = score - 420
                end
                if obj.CanCollide then
                    score = score + 20
                end
                if obj.Anchored then
                    score = score + 10
                end
                local brightness = (obj.Color.R + obj.Color.G + obj.Color.B) / 3
                if brightness < BLACK_BRIGHTNESS_THRESHOLD then
                    score = score - 320
                end

                if obj.Position.Y > (centerY + 2) then
                    score = score * 0.35
                end

                if score > bestScore then
                    bestScore = score
                    bestPart = obj
                end
            end
        end
    end

    return bestPart
end

function getGroundYAt(stageObj, x, z, fallbackY)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {stageObj}
    params.IgnoreWater = true

    local originY = math.max((fallbackY or 0) + GROUND_CAST_HEIGHT, 300)
    local minY = originY - GROUND_CAST_DEPTH
    local rayOriginY = originY
    local bestY = nil
    local bestScore = -math.huge

    for _ = 1, 16 do
        local castDepth = rayOriginY - minY
        if castDepth <= 0 then break end

        local result = workspace:Raycast(
            Vector3.new(x, rayOriginY, z),
            Vector3.new(0, -castDepth, 0),
            params
        )

        if not result then break end

        local hitPart = result.Instance
        if hitPart and hitPart:IsA("BasePart") then
            local name = hitPart.Name:lower()
            local score = (hitPart.Size.X * hitPart.Size.Z) - (hitPart.Size.Y * 6)

            if isDoorLikeSurface(hitPart) then score = score - 280 end
            if name:find("black") or name:find("void") or name:find("kill") or name:find("lava") then
                score = score - 500
            end

            local brightness = (hitPart.Color.R + hitPart.Color.G + hitPart.Color.B) / 3
            if brightness < BLACK_BRIGHTNESS_THRESHOLD then
                score = score - 320
            end

            if not hitPart.CanCollide then score = score - 120 end
            if hitPart.Transparency > 0.75 then score = score - 80 end
            if hitPart.Anchored then score = score + 15 end

            if score > bestScore then
                bestScore = score
                bestY = result.Position.Y
            end
        end

        rayOriginY = result.Position.Y - 0.25
    end

    if bestY then
        return bestY
    end

    return fallbackY or 0
end

function getStableGroundY(stageObj, x, z, fallbackY)
    local rayGroundY = getGroundYAt(stageObj, x, z, fallbackY)
    local floorTopY = nil
    local safeFallbackY = fallbackY or 0

    if stageObj:IsA("Model") then
        local floorPart = getStageFloorPart(stageObj)
        if floorPart then
            floorTopY = floorPart.Position.Y + (floorPart.Size.Y * 0.5)
        end
    elseif stageObj:IsA("BasePart") then
        floorTopY = stageObj.Position.Y + (stageObj.Size.Y * 0.5)
    end

    if floorTopY then
        -- Bazi stage'lerde raycast yanlis yuzeyi secip asiri asagi dusurebiliyor.
        if rayGroundY < (floorTopY - 10) or rayGroundY > (floorTopY + 16) then
            return floorTopY
        end
    end

    if rayGroundY < (safeFallbackY - 40) or rayGroundY > (safeFallbackY + 80) then
        return floorTopY or safeFallbackY
    end

    return rayGroundY
end

function getStageDoorPart(stageModel, referencePos)
    local bestPart = nil
    local bestScore = -math.huge

    local function scorePart(obj, nameBonus)
        local width = math.max(obj.Size.X, obj.Size.Z)
        local depth = math.min(obj.Size.X, obj.Size.Z)
        local score = (obj.Size.Y * 4) + (width * 2) - depth + nameBonus

        if obj.CanCollide then score = score + 15 end
        if obj.Anchored then score = score + 10 end
        if obj.Transparency > 0.75 then score = score - 30 end

        if referencePos then
            -- Bir onceki bolumden uzak olani secerek cikis kapisini tercih et.
            score = score + ((obj.Position - referencePos).Magnitude * 0.12)
        end

        return score
    end

    for _, obj in ipairs(stageModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            local name = obj.Name:lower()
            local nameBonus = 0

            if name:find("door") then nameBonus = nameBonus + 220 end
            if name:find("gate") then nameBonus = nameBonus + 200 end
            if name:find("entrance") or name:find("entry") then nameBonus = nameBonus + 190 end
            if name:find("portal") then nameBonus = nameBonus + 180 end

            if nameBonus > 0 then
                local score = scorePart(obj, nameBonus)
                if score > bestScore then
                    bestScore = score
                    bestPart = obj
                end
            end
        end
    end

    if bestPart then
        return bestPart
    end

    -- Isim tutmazsa: uzun ve ince dikey parcalardan kapiyi tahmin et.
    for _, obj in ipairs(stageModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            local width = math.max(obj.Size.X, obj.Size.Z)
            local depth = math.min(obj.Size.X, obj.Size.Z)
            if obj.Size.Y >= 8 and width >= 8 and depth <= 6 then
                local score = scorePart(obj, 0)
                if score > bestScore then
                    bestScore = score
                    bestPart = obj
                end
            end
        end
    end

    return bestPart
end

function getStageApproachTarget(stageObj, boundsCF, boundsSize, referencePos)
    return boundsCF.Position
end

function clampGroundYToStage(groundY, boundsCF, boundsSize)
    local boundsCenterY = boundsCF.Position.Y
    local boundsBottomY = boundsCenterY - (boundsSize.Y * 0.5)
    local boundsTopY = boundsCenterY + (boundsSize.Y * 0.5)

    local minAllowedY = math.max(boundsCenterY - 8, boundsBottomY + 2)
    local maxAllowedY = boundsTopY + 8
    return math.clamp(groundY, minAllowedY, maxAllowedY)
end

function getStagePosition(stageObj, referencePos)
    local boundsCF, boundsSize = getStageBounds(stageObj)
    if not boundsCF or not boundsSize then
        return nil, nil, nil
    end

    if stageObj:IsA("Model") then
        local target = getStageApproachTarget(stageObj, boundsCF, boundsSize, referencePos)
        local fallbackY = boundsCF.Position.Y + (boundsSize.Y * 0.5)
        local groundY = getStableGroundY(stageObj, target.X, target.Z, fallbackY)
        groundY = clampGroundYToStage(groundY, boundsCF, boundsSize)
        local y = groundY + ROOT_ON_GROUND_OFFSET + STAGE_CENTER_Y_OFFSET
        return Vector3.new(target.X, y, target.Z), boundsCF, boundsSize
    elseif stageObj:IsA("BasePart") then
        local target = boundsCF.Position
        local fallbackY = boundsCF.Position.Y + (boundsSize.Y * 0.5)
        local groundY = getStableGroundY(stageObj, target.X, target.Z, fallbackY)
        groundY = clampGroundYToStage(groundY, boundsCF, boundsSize)
        local y = groundY + ROOT_ON_GROUND_OFFSET + STAGE_CENTER_Y_OFFSET
        return Vector3.new(target.X, y, target.Z), boundsCF, boundsSize
    end
    return nil, nil, nil
end

function getOrderedStages()
    local container = getStageContainer()
    local stages = {}
    if not container then return stages end

    for _, obj in ipairs(container:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            table.insert(stages, obj)
        end
    end

    table.sort(stages, function(a, b)
        local na = tonumber(a.Name:match("%d+")) or 9999
        local nb = tonumber(b.Name:match("%d+")) or 9999
        if na == nb then
            return a.Name < b.Name
        end
        return na < nb
    end)

    return stages
end

function getModelAnchorPart(model)
    local primary = model.PrimaryPart
    if primary and primary:IsA("BasePart") then
        return primary
    end

    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("BasePart") then
            return obj
        end
    end

    return nil
end

function getChestInteractionTargets(chestPart)
    local chestModel = chestPart and chestPart:FindFirstAncestorOfClass("Model") or nil
    local searchRoot = chestModel or chestPart
    local prompts = {}
    local clickers = {}
    local touchParts = {}

    if searchRoot then
        for _, obj in ipairs(searchRoot:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                table.insert(prompts, obj)
            elseif obj:IsA("ClickDetector") then
                table.insert(clickers, obj)
            elseif obj:IsA("BasePart") and obj:FindFirstChildOfClass("TouchTransmitter") then
                table.insert(touchParts, obj)
            end
        end
    end

    if chestPart and #touchParts == 0 then
        table.insert(touchParts, chestPart)
    end

    return chestModel, prompts, clickers, touchParts
end

function findChestPart()
    local best, bestScore = nil, -math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local name = obj.Name:lower()
            local model = obj:FindFirstAncestorOfClass("Model")
            local modelName = model and model.Name:lower() or ""
            local chestLike = (name:find("chest") ~= nil) or (modelName:find("chest") ~= nil) or (modelName:find("treasure") ~= nil) or (modelName:find("reward") ~= nil)
            local hasPrompt = model and (model:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil)
            local hasClick = model and (model:FindFirstChildWhichIsA("ClickDetector", true) ~= nil)
            local hasTouch = obj:FindFirstChildOfClass("TouchTransmitter") ~= nil

            if chestLike then
                local score = obj.Position.Magnitude
                if chestLike then score = score + 300 end
                if hasPrompt then score = score + 160 end
                if hasClick then score = score + 120 end
                if hasTouch then score = score + 80 end

                if score > bestScore then
                    bestScore = score
                    best = obj
                end
            end
        end
    end
    return best
end

function moveRootNearPart(root, part)
    if not root or not part or not part.Parent then return end
    local lift = (part.Size.Y * 0.5) + (root.Size.Y * 0.5) + 1.2
    local target = part.Position + (part.CFrame.UpVector * lift)
    root.CFrame = CFrame.new(target)
    stopPartMotion(root)
end

function openChest(chestPart)
    if not chestPart or not chestPart.Parent then return false end

    local root = getRoot()
    if not root then return false end

    local chestModel, prompts, clickers, touchParts = getChestInteractionTargets(chestPart)
    local anchorPart = chestPart
    if chestModel then
        local modelAnchor = getModelAnchorPart(chestModel)
        if modelAnchor then
            anchorPart = modelAnchor
        end
    end

    for _ = 1, 6 do
        if not autoFarm then break end
        if not chestPart.Parent then return true end

        tp(anchorPart.Position + Vector3.new(0, 3, 0), true)
        task.wait(0.2)

        root = getRoot()
        if not root then return false end

        for _, prompt in ipairs(prompts) do
            if prompt and prompt.Parent then
                local holder = prompt.Parent
                if holder:IsA("BasePart") then
                    moveRootNearPart(root, holder)
                end

                pcall(function()
                    if fireproximityprompt then
                        fireproximityprompt(prompt, 1, true)
                    else
                        prompt:InputHoldBegin()
                        task.wait((prompt.HoldDuration or 0) + 0.1)
                        prompt:InputHoldEnd()
                    end
                end)
                task.wait(0.08)
            end
        end

        for _, clicker in ipairs(clickers) do
            if clicker and clicker.Parent and fireclickdetector then
                local holder = clicker.Parent
                if holder:IsA("BasePart") then
                    moveRootNearPart(root, holder)
                end
                pcall(function()
                    fireclickdetector(clicker, 1)
                end)
                task.wait(0.08)
            end
        end

        if firetouchinterest then
            for _, touchPart in ipairs(touchParts) do
                if touchPart and touchPart.Parent then
                    moveRootNearPart(root, touchPart)
                    pcall(function()
                        firetouchinterest(root, touchPart, 0)
                        task.wait()
                        firetouchinterest(root, touchPart, 1)
                    end)
                    task.wait(0.05)
                end
            end
        else
            for _, touchPart in ipairs(touchParts) do
                if touchPart and touchPart.Parent then
                    moveRootNearPart(root, touchPart)
                    task.wait(0.08)
                end
            end
        end

        task.wait(0.35)
    end

    return chestPart.Parent == nil
end

local TEAM_SWATCH = {
    Black = Color3.fromRGB(35, 35, 35),
    Blue = Color3.fromRGB(57, 112, 255),
    Green = Color3.fromRGB(64, 178, 97),
    Magenta = Color3.fromRGB(210, 78, 218),
    Red = Color3.fromRGB(220, 64, 84),
    White = Color3.fromRGB(230, 230, 230),
    Yellow = Color3.fromRGB(232, 198, 77)
}

local LIGHT_TEAM_TEXT = {
    White = true,
    Yellow = true
}

local cachedTeamRemotes = nil
local lastTeamRemoteScanAt = 0

function normalizeKey(value)
    local s = tostring(value or ""):lower()
    s = s:gsub("%s+", "")
    s = s:gsub("_", "")
    s = s:gsub("%-", "")
    return s
end

function findTeamByColorName(colorName)
    local target = normalizeKey(colorName)
    local bestTeam = nil
    local bestScore = -math.huge

    for _, team in ipairs(Teams:GetTeams()) do
        local teamName = normalizeKey(team.Name)
        local teamColorName = normalizeKey(team.TeamColor and team.TeamColor.Name or "")
        local score = 0

        if teamColorName == target then score = score + 220 end
        if teamName == target then score = score + 180 end
        if teamColorName:find(target, 1, true) then score = score + 100 end
        if teamName:find(target, 1, true) then score = score + 80 end

        if score > bestScore then
            bestScore = score
            bestTeam = team
        end
    end

    return bestTeam
end

function getOccupiedCount(team)
    if not team then return 0 end
    local count = 0
    for _, player in ipairs(team:GetPlayers()) do
        if player ~= LocalPlayer then
            count = count + 1
        end
    end
    return count
end

function getTeamRemotes()
    if cachedTeamRemotes and #cachedTeamRemotes > 0 then
        return cachedTeamRemotes
    end
    if cachedTeamRemotes and (os.clock() - lastTeamRemoteScanAt) < 2 then
        return cachedTeamRemotes
    end

    lastTeamRemoteScanAt = os.clock()
    cachedTeamRemotes = {}

    local function scoreTextForTeamRemote(text)
        local s = 0
        local t = normalizeKey(text)
        if t == "" then return s end

        if t:find("team", 1, true) then s = s + 10 end
        if t:find("color", 1, true) then s = s + 6 end
        if t:find("change", 1, true) then s = s + 7 end
        if t:find("switch", 1, true) then s = s + 7 end
        if t:find("select", 1, true) then s = s + 7 end
        if t:find("join", 1, true) then s = s + 6 end
        if t:find("choose", 1, true) then s = s + 6 end
        if t:find("set", 1, true) then s = s + 4 end
        if t:find("pick", 1, true) then s = s + 4 end
        if t:find("spawn", 1, true) then s = s + 3 end
        if t:find("lobby", 1, true) then s = s + 2 end
        if t:find("remote", 1, true) then s = s + 2 end

        for _, colorName in ipairs(TEAM_COLOR_OPTIONS) do
            if t:find(normalizeKey(colorName), 1, true) then
                s = s + 5
            end
        end

        return s
    end

    local scored = {}
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local score = 0
            score = score + scoreTextForTeamRemote(obj.Name)
            if obj.Parent then
                score = score + scoreTextForTeamRemote(obj.Parent.Name)
                if obj.Parent.Parent then
                    score = score + scoreTextForTeamRemote(obj.Parent.Parent.Name)
                end
            end
            if obj:IsDescendantOf(ReplicatedStorage) then
                score = score + 3
            end

            if score >= 13 then
                table.insert(scored, {remote = obj, score = score})
            end
        end
    end

    table.sort(scored, function(a, b)
        if a.score == b.score then
            return a.remote:GetFullName() < b.remote:GetFullName()
        end
        return a.score > b.score
    end)

    for _, item in ipairs(scored) do
        table.insert(cachedTeamRemotes, item.remote)
    end

    return cachedTeamRemotes
end

function trySwitchTeamWithRemotes(targetTeam, colorName, remotes)
    remotes = remotes or getTeamRemotes()
    if #remotes == 0 then
        return false
    end

    local argSets = {
        {targetTeam},
        {targetTeam and targetTeam.Name or colorName},
        {targetTeam and targetTeam.TeamColor or nil},
        {targetTeam and targetTeam.TeamColor and targetTeam.TeamColor.Name or colorName},
        {targetTeam and targetTeam.TeamColor and targetTeam.TeamColor.Number or nil},
        {{Team = targetTeam, TeamColor = targetTeam and targetTeam.TeamColor or nil}},
        {colorName},
        {string.lower(colorName or "")},
        {string.upper(colorName or "")}
    }
    local brickColorArg = nil
    pcall(function()
        brickColorArg = BrickColor.new(colorName)
    end)
    if brickColorArg then
        table.insert(argSets, {brickColorArg})
        table.insert(argSets, {brickColorArg.Number})
        table.insert(argSets, {brickColorArg.Name})
    end

    for _, remote in ipairs(remotes) do
        for _, args in ipairs(argSets) do
            pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer(unpackArgs(args))
                else
                    remote:InvokeServer(unpackArgs(args))
                end
            end)
            task.wait(0.1)
            if LocalPlayer.Team == targetTeam then
                return true
            end
        end
    end

    return LocalPlayer.Team == targetTeam
end

function attemptSwitchToSelectedTeam()
    local targetTeam = findTeamByColorName(selectedTeamColorName)
    if not targetTeam then
        return false, "Selected team not found"
    end

    if LocalPlayer.Team == targetTeam then
        return true, "On " .. targetTeam.Name
    end

    local occupiedCount = getOccupiedCount(targetTeam)
    if occupiedCount > 0 then
        return false, string.format("Waiting: %s (%d)", targetTeam.Name, occupiedCount)
    end

    local remotes = getTeamRemotes()
    if trySwitchTeamWithRemotes(targetTeam, selectedTeamColorName, remotes) then
        return true, "Switched to " .. targetTeam.Name
    end

    if #remotes == 0 then
        return false, "No team-change remote candidate found"
    end
    return false, string.format("Switch request sent (%d candidates)", #remotes)
end

-- WindUI only (legacy custom panel removed)
local farmStatText = "00.00.00 = 0 gold"
local teamStatusText = "Idle"
local boatEngineStatusText = "Status: Waiting for a VehicleSeat."
local boatNoDamageHintText = "Seat required"
local localPlayerFlyStatusText = "Fly V3: Off"

function getWindUiToggleKeyCode(value)
    local keyName = normalizeKeyCodeName(value, nil)
    if not keyName then
        return nil, nil
    end

    local keyCode = Enum.KeyCode[keyName]
    if not keyCode then
        return nil, nil
    end
    return keyName, keyCode
end

function updateWindUiToggleKeyButtonText()
    if not windUiToggleKeyButton then
        return
    end

    local titleText = windUiToggleKeyCaptureActive and "Panel Toggle Key: NONE" or ("Panel Toggle Key: " .. windUiToggleKeyName)
    pcall(function()
        windUiToggleKeyButton:SetTitle(titleText)
    end)
end

function applyWindUiToggleKey(value, targetWindow)
    local keyName, keyCode = getWindUiToggleKeyCode(value)
    if not keyName or not keyCode then
        return false
    end

    windUiToggleKeyName = keyName
    local window = targetWindow or windUiWindow
    if window then
        pcall(function()
            window:SetToggleKey(keyCode)
        end)
    end
    updateWindUiToggleKeyButtonText()
    savePersistedSettings()
    return true
end

function stopWindUiToggleKeyCapture()
    windUiToggleKeyCaptureActive = false
    if windUiToggleKeyCaptureConnection then
        pcall(function()
            windUiToggleKeyCaptureConnection:Disconnect()
        end)
        windUiToggleKeyCaptureConnection = nil
    end
    updateWindUiToggleKeyButtonText()
end

function syncWindUiFarmStatText()
    if not windUiFarmStatParagraph then
        return
    end
    pcall(function()
        windUiFarmStatParagraph:SetDesc(farmStatText)
    end)
end

function setPanelVisibleState(_visible)
    panelVisible = _visible and true or false
end

function refreshTeamColorButtons()
end

function setTeamToggleState(_enabled)
end

function getBoatSeatStatusText()
    local seatPart = getCurrentSeatPart()
    if not seatPart then
        return "Seat: Not seated"
    end
    if seatPart:IsA("VehicleSeat") then
        return "Seat: VehicleSeat (" .. seatPart.Name .. ")"
    end
    return "Seat: Seat (" .. seatPart.Name .. ")"
end

function setBoatUprightToggleState(_enabled)
end

function setBoatNoDamageToggleState(enabled, hintText)
    if hintText then
        boatNoDamageHintText = hintText
    elseif enabled then
        if getCurrentSeatPart() then
            boatNoDamageHintText = "Guarding current boat"
        else
            boatNoDamageHintText = "Enabled (sit on boat)"
        end
    else
        boatNoDamageHintText = "Seat required"
    end
end

function setLocalPlayerNoclipToggleState(_enabled)
end

function setLocalPlayerFlyToggleState(enabled, statusText)
    if enabled then
        localPlayerFlyStatusText = statusText or "Fly V3: On"
    else
        localPlayerFlyStatusText = statusText or "Fly V3: Off"
    end
end

function getLocalPlayerFlySpeedRatioFromValue(speedValue)
    local range = LOCAL_PLAYER_FLY_MAX_SPEED - LOCAL_PLAYER_FLY_MIN_SPEED
    if range <= 0 then
        return 0
    end
    local clamped = clampLocalPlayerFlySpeed(speedValue)
    return (clamped - LOCAL_PLAYER_FLY_MIN_SPEED) / range
end

function updateLocalPlayerFlySpeedSliderVisual()
    localPlayerFlySpeed = clampLocalPlayerFlySpeed(localPlayerFlySpeed)
end

function setLocalPlayerFlySpeedFromRatio(ratio)
    ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
    local range = LOCAL_PLAYER_FLY_MAX_SPEED - LOCAL_PLAYER_FLY_MIN_SPEED
    local speed = LOCAL_PLAYER_FLY_MIN_SPEED + (range * ratio)
    localPlayerFlySpeed = clampLocalPlayerFlySpeed(speed)
    updateLocalPlayerFlySpeedSliderVisual()
    savePersistedSettings()
end

function getBoatSpeedRatioFromValue(speedValue)
    local range = BOAT_ENGINE_MAX_SPEED - BOAT_ENGINE_MIN_SPEED
    if range <= 0 then
        return 0
    end
    local clamped = clampBoatSpeedValue(speedValue)
    return (clamped - BOAT_ENGINE_MIN_SPEED) / range
end

function updateBoatSpeedSliderVisual()
    boatCustomSpeed = clampBoatSpeedValue(boatCustomSpeed)
end

function setBoatSpeedFromRatio(ratio)
    ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
    local range = BOAT_ENGINE_MAX_SPEED - BOAT_ENGINE_MIN_SPEED
    local speed = BOAT_ENGINE_MIN_SPEED + (range * ratio)
    boatCustomSpeed = clampBoatSpeedValue(speed)
    updateBoatSpeedSliderVisual()
    savePersistedSettings()

    if boatEngineMode == "custom" then
        updateBoatEnginePowerForSeat()
    end
end

function refreshBoatEngineUi(statusText)
    updateBoatSpeedSliderVisual()
    if statusText then
        boatEngineStatusText = statusText
    end
end

function applyCurrentCustomBoatSpeed()
    boatCustomSpeed = clampBoatSpeedValue(boatCustomSpeed)
    boatEngineMode = "custom"
    updateBoatEnginePowerForSeat()
    savePersistedSettings()

    local vehicleSeat = getCurrentVehicleSeat()
    if vehicleSeat then
        refreshBoatEngineUi(string.format("Status: Custom speed %d applied to %s.", boatCustomSpeed, vehicleSeat.Name))
    else
        refreshBoatEngineUi(string.format("Status: Custom speed %d ready. Sit on a VehicleSeat to apply.", boatCustomSpeed))
    end
end

task.spawn(function()
    while not scriptClosedPermanently do
        local waitTime = TEAM_CHECK_INTERVAL
        if teamAutoSwitch and not teamSwitchInProgress then
            teamSwitchInProgress = true
            local ok, message = attemptSwitchToSelectedTeam()
            teamStatusText = message
            if ok then
                pendingTeamResyncUntil = 0
            end
            teamSwitchInProgress = false
            if os.clock() < pendingTeamResyncUntil then
                waitTime = 0.35
            end
        end
        task.wait(waitTime)
    end
end)

task.spawn(function()
    while not scriptClosedPermanently do
        local now = os.clock()
        updateBoatEnginePowerForSeat()
        tryAutoUprightBoat()

        if localPlayerNoclip then
            applyCharacterNoclip()
        end

        if localPlayerFly then
            local canFlyNow = updateLocalFlyMotion()
            if canFlyNow then
                localPlayerFlyStatusText = string.format("Fly V3: On (%d)", clampLocalPlayerFlySpeed(localPlayerFlySpeed))
            else
                localPlayerFlyStatusText = string.format("Fly V3: On (%d) - waiting character", clampLocalPlayerFlySpeed(localPlayerFlySpeed))
            end
        end

        if boatNoDamage and (now - lastBoatDamageGuardAt) >= BOAT_DAMAGE_GUARD_INTERVAL then
            local hasBoat, protectedCount = guardCurrentBoatAgainstDamage()
            if hasBoat then
                boatNoDamageHintText = string.format("Guarding current boat (%d)", protectedCount)
            else
                boatNoDamageHintText = "Enabled (sit on boat)"
            end
            lastBoatDamageGuardAt = now
        end

        task.wait(BOAT_ENGINE_UPDATE_INTERVAL)
    end

    if activeCustomVehicleSeat then
        restoreVehicleSeatDefaults(activeCustomVehicleSeat)
        activeCustomVehicleSeat = nil
    end
    disableLocalFly()
    restoreCharacterNoclip()
    restoreBoatDamageDefaults()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end
    if gameProcessed or UserInputService:GetFocusedTextBox() then
        return
    end
    if scriptClosedPermanently then
        return
    end

    if localPlayerFly then
        setLocalFlyInputForKey(input.KeyCode, true)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        setLocalFlyInputForKey(input.KeyCode, false)
    end
end)

function formatSessionClock(secondsElapsed)
    local total = math.max(0, math.floor(secondsElapsed or 0))
    local h = math.floor(total / 3600)
    local m = math.floor((total % 3600) / 60)
    local s = total % 60
    return string.format("%02d.%02d.%02d", h, m, s)
end

function resolveGoldStat()
    if cachedGoldStat and cachedGoldStat.Parent and (cachedGoldStat:IsA("IntValue") or cachedGoldStat:IsA("NumberValue")) then
        return cachedGoldStat
    end
    if (os.clock() - lastGoldResolveTry) < 3 then
        return nil
    end
    lastGoldResolveTry = os.clock()

    local function hasGoldLikeName(valueObj)
        local name = valueObj.Name:lower()
        return name:find("gold") or name:find("coin") or name:find("cash") or name:find("money") or name:find("altin")
    end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _, obj in ipairs(leaderstats:GetChildren()) do
            if (obj:IsA("IntValue") or obj:IsA("NumberValue")) and hasGoldLikeName(obj) then
                cachedGoldStat = obj
                return cachedGoldStat
            end
        end
    end

    for _, obj in ipairs(LocalPlayer:GetDescendants()) do
        if (obj:IsA("IntValue") or obj:IsA("NumberValue")) and hasGoldLikeName(obj) then
            cachedGoldStat = obj
            return cachedGoldStat
        end
    end

    return nil
end

function getCurrentGold()
    local goldStat = resolveGoldStat()
    if not goldStat then
        return nil
    end
    local value = tonumber(goldStat.Value)
    if not value then
        return nil
    end
    return math.floor(value + 0.5)
end

function refreshFarmStatLabel()
    local elapsedSeconds = farmSessionElapsedBase
    if farmSessionStartTime then
        elapsedSeconds = elapsedSeconds + (os.clock() - farmSessionStartTime)
    end

    if autoFarm and farmSessionStartGold == nil then
        farmSessionStartGold = getCurrentGold()
    end

    local gainedGold = 0
    if farmSessionStartGold ~= nil then
        local currentGold = getCurrentGold()
        if currentGold ~= nil then
            gainedGold = math.max(0, currentGold - farmSessionStartGold)
        end
    end

    farmStatText = string.format("%s = %d gold", formatSessionClock(elapsedSeconds), gainedGold)
    syncWindUiFarmStatText()
end

task.spawn(function()
    while not scriptClosedPermanently do
        refreshFarmStatLabel()
        task.wait(1)
    end
end)

function setButtonState(enabled)
    return enabled and true or false
end

function closeScriptPermanently()
    if scriptClosedPermanently then
        return
    end
    scriptClosedPermanently = true

    autoFarm = false
    running = false
    teamAutoSwitch = false
    teamSwitchInProgress = false
    boatAutoUpright = false
    boatNoDamage = false
    boatEngineMode = "normal"
    localPlayerNoclip = false
    localPlayerFly = false
    panelVisible = false

    if farmSessionStartTime then
        farmSessionElapsedBase = farmSessionElapsedBase + (os.clock() - farmSessionStartTime)
        farmSessionStartTime = nil
    end

    clearSafetyPart()
    disableLocalFly()
    restoreCharacterNoclip()
    restoreBoatDamageDefaults()

    if activeCustomVehicleSeat then
        restoreVehicleSeatDefaults(activeCustomVehicleSeat)
        activeCustomVehicleSeat = nil
    end

    setButtonState(false)
    setTeamToggleState(false)
    setBoatUprightToggleState(false)
    setBoatNoDamageToggleState(false, "Disabled")
    setLocalPlayerNoclipToggleState(false)
    setLocalPlayerFlyToggleState(false, "Fly V3: Off")
    refreshBoatEngineUi("Status: Disabled")
    teamStatusText = "Disabled"
    boatEngineStatusText = "Status: Disabled"
    farmStatText = "00.00.00 = 0 gold"
    stopWindUiToggleKeyCapture()
    windUiToggleKeyButton = nil
    windUiFarmStatParagraph = nil

    if windUiWindow then
        pcall(function()
            windUiWindow:Destroy()
        end)
        windUiWindow = nil
    end
end

setButtonState(false)
refreshFarmStatLabel()
function runAutoFarm()
    if running then return end
    running = true

    while autoFarm do
        local waitLeft = (farmResumeAfterRespawnAt or 0) - os.clock()
        if waitLeft > 0 then
            task.wait(waitLeft)
        end
        local routeStartCharacterVersion = characterVersion
        local stages = getOrderedStages()
        local stageCount = math.min(#stages, MAX_STAGE_COUNT)
        local reachedStageTen = false
        local routeInterrupted = false
        local root = getRoot()
        while autoFarm and not root do
            task.wait(0.1)
            root = getRoot()
        end
        if not autoFarm then break end
        if stageCount == 0 then
            task.wait(1)
            continue
        end
        local lastTargetPos = root and root.Position or nil

        for i = 1, stageCount do
            if not autoFarm then break end
            if characterVersion ~= routeStartCharacterVersion then
                routeInterrupted = true
                break
            end
            local stage = stages[i]
            local pos, boundsCF, boundsSize = getStagePosition(stage, lastTargetPos)
            if pos then
                local isStageTen = (i == MAX_STAGE_COUNT)
                if isStageTen then
                    reachedStageTen = true
                end
                tp(pos, true, boundsCF, boundsSize)
                lastTargetPos = pos
            end
            task.wait(TP_DELAY)
        end

        if not autoFarm then break end
        if routeInterrupted then
            task.wait(0.25)
            continue
        end

        if reachedStageTen then
            local chest = nil
            for _ = 1, 20 do
                chest = findChestPart()
                if chest then
                    break
                end
                task.wait(0.15)
            end

            if chest then
                openChest(chest)
            end
        end

        if not reachedStageTen then
            clearSafetyPart()
        end
        local completedCharacterVersion = characterVersion
        while autoFarm and characterVersion == completedCharacterVersion do
            task.wait(0.25)
        end
    end

    clearSafetyPart()
    running = false
end

function setAutoFarmEnabled(enabled)
    if scriptClosedPermanently then
        return
    end

    local desired = enabled and true or false
    if autoFarm == desired then
        return
    end

    autoFarm = desired
    setButtonState(autoFarm)
    if autoFarm then
        farmSessionElapsedBase = 0
        farmSessionStartTime = os.clock()
        farmSessionStartGold = getCurrentGold()
        refreshFarmStatLabel()
        task.spawn(runAutoFarm)
    else
        if farmSessionStartTime then
            farmSessionElapsedBase = farmSessionElapsedBase + (os.clock() - farmSessionStartTime)
            farmSessionStartTime = nil
        end
        refreshFarmStatLabel()
        clearSafetyPart()
    end
end

function initWindUIPanel()
    if scriptClosedPermanently or windUiLoaded then
        return
    end

    if scriptClosedPermanently then
        return
    end

    local okLoader, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
    end)
    if not okLoader or not WindUI then
        warn("[BBFT] WindUI load failed.")
        return
    end

    pcall(function()
        WindUI:AddTheme({
            Name = "Lunar Abyss",
            Accent = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(13, 13, 26), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(26, 26, 51), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(46, 46, 92), Transparency = 0}
            }, {Rotation = 90}),
            Dialog = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(16, 16, 38), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(26, 26, 61), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(51, 51, 102), Transparency = 0}
            }, {Rotation = 90}),
            Outline = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(46, 46, 92), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(64, 64, 128), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(80, 80, 160), Transparency = 0}
            }, {Rotation = 90}),
            Text = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(160, 160, 255), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(192, 192, 255), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(224, 224, 255), Transparency = 0}
            }, {Rotation = 90}),
            Placeholder = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(96, 96, 160), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(128, 128, 192), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(160, 160, 224), Transparency = 0}
            }, {Rotation = 90}),
            Background = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(10, 10, 26), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(26, 26, 51), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(46, 46, 92), Transparency = 0}
            }, {Rotation = 90}),
            Button = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(64, 64, 128), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(80, 80, 160), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(96, 96, 192), Transparency = 0}
            }, {Rotation = 90}),
            Icon = WindUI:Gradient({
                ["0"] = {Color = Color3.fromRGB(96, 96, 192), Transparency = 0},
                ["50"] = {Color = Color3.fromRGB(128, 128, 224), Transparency = 0},
                ["100"] = {Color = Color3.fromRGB(160, 160, 255), Transparency = 0}
            }, {Rotation = 90})
        })
    end)

    local function gradientText(text, c1, c2)
        local len = #text
        if len <= 1 then
            return string.format(
                '<font color="rgb(%d,%d,%d)">%s</font>',
                math.floor(c1.R * 255),
                math.floor(c1.G * 255),
                math.floor(c1.B * 255),
                text
            )
        end
        local result = ""
        local denom = len - 1
        for i = 1, len do
            local t = (i - 1) / denom
            local r = math.floor(c1.R * 255 + ((c2.R * 255 - c1.R * 255) * t))
            local g = math.floor(c1.G * 255 + ((c2.G * 255 - c1.G * 255) * t))
            local b = math.floor(c1.B * 255 + ((c2.B * 255 - c1.B * 255) * t))
            result = result .. string.format('<font color="rgb(%d,%d,%d)">%s</font>', r, g, b, text:sub(i, i))
        end
        return result
    end

    local okWindow, window = pcall(function()
        return WindUI:CreateWindow({
            Title = gradientText("Foxname - Build A Boat For Treasure", Color3.fromRGB(255, 30, 0), Color3.fromRGB(0, 175, 255)),
            Author = "discord.gg/v8ZPq4y2nD",
            Theme = "Rose",
            Size = UDim2.fromOffset(520, 420),
            Folder = "Foxname_BBFT",
            SideBarWidth = 200,
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            ScrollBarEnabled = true,
            Icon = WINDUI_PROFILE_ICON,
            Background = WINDUI_PROFILE_BACKGROUND,
            BackgroundImageTransparency = 0.6,
            OpenButton = {
                Title = "Open Script",
                CornerRadius = UDim.new(1, 0),
                StrokeThickness = 2,
                Enabled = true,
                Draggable = true,
                OnlyMobile = false
            }
        })
    end)
    if not okWindow or not window then
        warn("[BBFT] WindUI window creation failed.")
        return
    end

    windUiLoaded = true
    windUiWindow = window
    setPanelVisibleState(false)

    if not applyWindUiToggleKey(windUiToggleKeyName, window) then
        applyWindUiToggleKey("H", window)
    end

    local infoWindTab = nil
    local okInfoSection, infoSection = pcall(function()
        return window:Section({
            Title = "Info",
            Opened = false,
            Icon = "info",
            Box = true,
            BoxBorder = true,
            IconColor = Color3.fromRGB(100, 100, 255)
        })
    end)
    if okInfoSection and infoSection and infoSection.Tab then
        local okInfoTab, sectionInfoTab = pcall(function()
            return infoSection:Tab({Title = "Changelog", Icon = "list", Locked = false})
        end)
        if okInfoTab and sectionInfoTab then
            infoWindTab = sectionInfoTab
        end
    end
    if not infoWindTab then
        infoWindTab = window:Tab({Title = "Info", Icon = "info"})
    end
    pcall(function()
        window:Tag({
            Title = "v1.2",
            Icon = "rocket",
            Color = Color3.fromRGB(255, 13, 49)
        })
    end)

    local farmWindTab = window:Tab({Title = "Farm", Icon = "coins"})
    local teamWindTab = window:Tab({Title = "Team Shift", Icon = "users"})
    local boatWindTab = window:Tab({Title = "Boat", Icon = "ship"})
    local localWindTab = window:Tab({Title = "Local Player", Icon = "user"})
    local settingsWindTab = window:Tab({Title = "Settings", Icon = "settings"})

    farmWindTab:Toggle({
        Title = "Enable AutoFarm",
        Default = autoFarm,
        Callback = function(v)
            setAutoFarmEnabled(v)
        end
    })
    farmWindTab:Button({
        Title = "Reset Session Stats",
        Callback = function()
            farmSessionElapsedBase = 0
            farmSessionStartTime = autoFarm and os.clock() or nil
            farmSessionStartGold = getCurrentGold()
            refreshFarmStatLabel()
        end
    })
    windUiFarmStatParagraph = farmWindTab:Paragraph({
        Title = "Session Stats",
        Desc = farmStatText
    })
    syncWindUiFarmStatText()

    teamWindTab:Dropdown({
        Title = "Target Team Color",
        Values = TEAM_COLOR_OPTIONS,
        Value = selectedTeamColorName,
        Callback = function(option)
            selectedTeamColorName = tostring(option)
            teamStatusText = "Selected: " .. selectedTeamColorName
            refreshTeamColorButtons()
            savePersistedSettings()
        end
    })
    teamWindTab:Toggle({
        Title = "Auto Team Switch",
        Default = teamAutoSwitch,
        Callback = function(v)
            teamAutoSwitch = v and true or false
            setTeamToggleState(teamAutoSwitch)
            if teamAutoSwitch then
                pendingTeamResyncUntil = os.clock() + 8
                teamStatusText = "Watching " .. selectedTeamColorName .. "..."
            else
                pendingTeamResyncUntil = 0
                teamStatusText = "Idle"
            end
            savePersistedSettings()
        end
    })
    teamWindTab:Button({
        Title = "Try Switch Now",
        Callback = function()
            local ok, message = attemptSwitchToSelectedTeam()
            teamStatusText = message
        end
    })

    boatWindTab:Toggle({
        Title = "Auto Upright",
        Default = boatAutoUpright,
        Callback = function(v)
            boatAutoUpright = v and true or false
            setBoatUprightToggleState(boatAutoUpright)
            savePersistedSettings()
        end
    })
    boatWindTab:Toggle({
        Title = "No Boat Damage",
        Default = boatNoDamage,
        Callback = function(v)
            boatNoDamage = v and true or false
            if boatNoDamage then
                lastBoatDamageGuardAt = 0
                local hasBoat, protectedCount = guardCurrentBoatAgainstDamage()
                if hasBoat then
                    setBoatNoDamageToggleState(true, string.format("Guarding current boat (%d)", protectedCount))
                else
                    setBoatNoDamageToggleState(true, "Enabled (sit on boat)")
                end
            else
                restoreBoatDamageDefaults()
                setBoatNoDamageToggleState(false, "Seat required")
            end
            savePersistedSettings()
        end
    })
    boatWindTab:Dropdown({
        Title = "Engine Mode",
        Values = {"Normal", "Custom"},
        Value = (boatEngineMode == "custom" and "Custom" or "Normal"),
        Callback = function(mode)
            if tostring(mode) == "Custom" then
                applyCurrentCustomBoatSpeed()
            else
                boatEngineMode = "normal"
                updateBoatEnginePowerForSeat()
                refreshBoatEngineUi("Status: Normal seat speed restored.")
                savePersistedSettings()
            end
        end
    })
    boatWindTab:Slider({
        Title = "Custom Boat Speed",
        Value = {Min = BOAT_ENGINE_MIN_SPEED, Max = BOAT_ENGINE_MAX_SPEED, Default = boatCustomSpeed},
        Step = 1,
        Callback = function(v)
            boatCustomSpeed = clampBoatSpeedValue(v)
            updateBoatSpeedSliderVisual()
            if boatEngineMode == "custom" then
                updateBoatEnginePowerForSeat()
            end
            savePersistedSettings()
        end
    })
    boatWindTab:Button({
        Title = "Apply Custom Speed",
        Callback = function()
            applyCurrentCustomBoatSpeed()
        end
    })

    localWindTab:Toggle({
        Title = "Noclip",
        Default = localPlayerNoclip,
        Callback = function(v)
            localPlayerNoclip = v and true or false
            if localPlayerNoclip then
                applyCharacterNoclip()
            else
                restoreCharacterNoclip()
            end
            setLocalPlayerNoclipToggleState(localPlayerNoclip)
            savePersistedSettings()
        end
    })
    localWindTab:Toggle({
        Title = "Fly V3",
        Default = localPlayerFly,
        Callback = function(v)
            localPlayerFly = v and true or false
            if localPlayerFly then
                localPlayerFlySpeed = clampLocalPlayerFlySpeed(localPlayerFlySpeed)
                if ensureLocalFlyBodyMovers() then
                    setLocalPlayerFlyToggleState(true, string.format("Fly V3: On (%d)", localPlayerFlySpeed))
                else
                    setLocalPlayerFlyToggleState(true, string.format("Fly V3: On (%d) - waiting character", localPlayerFlySpeed))
                end
            else
                disableLocalFly()
                setLocalPlayerFlyToggleState(false, "Fly V3: Off")
            end
            savePersistedSettings()
        end
    })
    localWindTab:Slider({
        Title = "Fly Speed",
        Value = {Min = LOCAL_PLAYER_FLY_MIN_SPEED, Max = LOCAL_PLAYER_FLY_MAX_SPEED, Default = localPlayerFlySpeed},
        Step = 1,
        Callback = function(v)
            localPlayerFlySpeed = clampLocalPlayerFlySpeed(v)
            updateLocalPlayerFlySpeedSliderVisual()
            savePersistedSettings()
        end
    })

    infoWindTab:Paragraph({Title = "v1.2 Update Notes", Desc = "Click this Changelog tab to view the latest v1.2 changes."})
    infoWindTab:Paragraph({Title = "v1.2", Desc = "+ Replaced legacy UI with WindUI-only flow."})
    infoWindTab:Paragraph({Title = "v1.2", Desc = "+ Added panel toggle key capture in Settings (NONE -> press key)." })
    infoWindTab:Paragraph({Title = "v1.2", Desc = "+ Restored live session stats (time and gained gold) in Farm tab."})
    infoWindTab:Paragraph({Title = "v1.2", Desc = "+ Improved startup so panel opens without extra wait delay."})

    windUiToggleKeyButton = settingsWindTab:Button({
        Title = "Panel Toggle Key: " .. windUiToggleKeyName,
        Callback = function()
            windUiToggleKeyCaptureActive = true
            updateWindUiToggleKeyButtonText()
            pcall(function()
                WindUI:Notify({
                    Title = "Toggle Key",
                    Content = "Press any keyboard key...",
                    Duration = 1.5
                })
            end)
        end
    })
    settingsWindTab:Paragraph({
        Title = "Toggle Key Help",
        Desc = "Click button above, text becomes NONE, then press your key."
    })
    updateWindUiToggleKeyButtonText()

    stopWindUiToggleKeyCapture()
    windUiToggleKeyCaptureConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not windUiToggleKeyCaptureActive then
            return
        end
        if gameProcessed or UserInputService:GetFocusedTextBox() then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        if not input.KeyCode or input.KeyCode == Enum.KeyCode.Unknown then
            return
        end

        windUiToggleKeyCaptureActive = false
        applyWindUiToggleKey(input.KeyCode.Name, window)
        pcall(function()
            WindUI:Notify({
                Title = "Toggle Key",
                Content = "Panel key set to " .. windUiToggleKeyName,
                Duration = 1.5
            })
        end)
    end)

    settingsWindTab:Button({
        Title = "Close Script (Permanent)",
        Callback = function()
            closeScriptPermanently()
        end
    })
end

initWindUIPanel()



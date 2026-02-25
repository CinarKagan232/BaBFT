-- Build A Boat For Treasure - AutoFarm + UI
-- Not: Oyun update alirsa stage/chest isimleri degisebilir.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local autoFarm = false
local running = false
local teamAutoSwitch = false
local teamSwitchInProgress = false
local boatAutoUpright = false
local boatNoDamage = false
local boatEngineMode = "normal"
local boatCustomSpeed = 100
local selectedTeamColorName = "Red"
local panelVisible = true
local isTouchDevice = UserInputService.TouchEnabled
local localPlayerNoclip = false
local localPlayerFly = false
local localPlayerFlySpeed = 80
local lastCharacterAddedAt = os.clock()
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
local BLACK_AVOID_DISTANCE = 20
local BLACK_BRIGHTNESS_THRESHOLD = 0.12
local BOAT_UPRIGHT_CHECK_INTERVAL = 0.15
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
local LOCAL_PLAYER_FLY_MIN_SPEED = 20
local LOCAL_PLAYER_FLY_MAX_SPEED = 250
local LOCAL_PLAYER_FLY_BODY_POWER = 1000000
local LOCAL_PLAYER_FLY_BODY_GYRO_POWER = 1000000
local currentSafetyPart = nil
local characterVersion = character and 1 or 0
local lastBoatUprightAt = 0
local lastBoatDamageGuardAt = 0
local activeCustomVehicleSeat = nil
local currentBoatRamPart = nil
local localFlyBodyVelocity = nil
local localFlyBodyGyro = nil
local localFlyInput = {forward = 0, back = 0, left = 0, right = 0, up = 0, down = 0}
local vehicleSeatDefaults = setmetatable({}, {__mode = "k"})
local boatDamageValueDefaults = setmetatable({}, {__mode = "k"})
local boatDamageAttributeDefaults = setmetatable({}, {__mode = "k"})
local boatPartDefaults = setmetatable({}, {__mode = "k"})
local noclipPartDefaults = setmetatable({}, {__mode = "k"})

local function clampPositionToBounds(targetPos, boundsCF, boundsSize)
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

local function getRoot()
    character = LocalPlayer.Character or character
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    character = LocalPlayer.Character or character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

local function clampLocalPlayerFlySpeed(value)
    return math.clamp(
        math.floor((tonumber(value) or LOCAL_PLAYER_FLY_MIN_SPEED) + 0.5),
        LOCAL_PLAYER_FLY_MIN_SPEED,
        LOCAL_PLAYER_FLY_MAX_SPEED
    )
end

local function resetLocalFlyInput()
    localFlyInput.forward = 0
    localFlyInput.back = 0
    localFlyInput.left = 0
    localFlyInput.right = 0
    localFlyInput.up = 0
    localFlyInput.down = 0
end

local function setLocalFlyInputForKey(keyCode, isDown)
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
    end
end

local function applyCharacterNoclip()
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

local function restoreCharacterNoclip()
    for part, originalCanCollide in pairs(noclipPartDefaults) do
        if part and part.Parent and part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = originalCanCollide
            end)
        end
        noclipPartDefaults[part] = nil
    end
end

local function clearLocalFlyBodyMovers()
    if localFlyBodyVelocity and localFlyBodyVelocity.Parent then
        localFlyBodyVelocity:Destroy()
    end
    if localFlyBodyGyro and localFlyBodyGyro.Parent then
        localFlyBodyGyro:Destroy()
    end
    localFlyBodyVelocity = nil
    localFlyBodyGyro = nil
end

local function ensureLocalFlyBodyMovers()
    local root = getRoot()
    local humanoid = getHumanoid()
    if not root or not humanoid then
        return false
    end

    if not (localFlyBodyVelocity and localFlyBodyVelocity.Parent == root) then
        if localFlyBodyVelocity and localFlyBodyVelocity.Parent then
            localFlyBodyVelocity:Destroy()
        end
        localFlyBodyVelocity = Instance.new("BodyVelocity")
        localFlyBodyVelocity.Name = "AF_LocalFlyVelocity"
        localFlyBodyVelocity.MaxForce = Vector3.new(LOCAL_PLAYER_FLY_BODY_POWER, LOCAL_PLAYER_FLY_BODY_POWER, LOCAL_PLAYER_FLY_BODY_POWER)
        localFlyBodyVelocity.P = LOCAL_PLAYER_FLY_BODY_POWER
        localFlyBodyVelocity.Velocity = Vector3.zero
        localFlyBodyVelocity.Parent = root
    end

    if not (localFlyBodyGyro and localFlyBodyGyro.Parent == root) then
        if localFlyBodyGyro and localFlyBodyGyro.Parent then
            localFlyBodyGyro:Destroy()
        end
        localFlyBodyGyro = Instance.new("BodyGyro")
        localFlyBodyGyro.Name = "AF_LocalFlyGyro"
        localFlyBodyGyro.MaxTorque = Vector3.new(LOCAL_PLAYER_FLY_BODY_GYRO_POWER, LOCAL_PLAYER_FLY_BODY_GYRO_POWER, LOCAL_PLAYER_FLY_BODY_GYRO_POWER)
        localFlyBodyGyro.P = LOCAL_PLAYER_FLY_BODY_GYRO_POWER
        localFlyBodyGyro.CFrame = root.CFrame
        localFlyBodyGyro.Parent = root
    end

    pcall(function()
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end)

    return true
end

local function disableLocalFly()
    resetLocalFlyInput()
    clearLocalFlyBodyMovers()
    local humanoid = getHumanoid()
    if humanoid then
        pcall(function()
            humanoid.PlatformStand = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
end

local function updateLocalFlyMotion()
    if not localPlayerFly then
        return false
    end

    if not ensureLocalFlyBodyMovers() then
        return false
    end

    local root = getRoot()
    local humanoid = getHumanoid()
    local camera = workspace.CurrentCamera
    if not (root and camera and localFlyBodyVelocity and localFlyBodyGyro) then
        return false
    end

    local cameraLook = camera.CFrame.LookVector
    local cameraRight = camera.CFrame.RightVector

    local flatForward = Vector3.new(cameraLook.X, 0, cameraLook.Z)
    if flatForward.Magnitude < 0.001 then
        flatForward = Vector3.new(0, 0, -1)
    else
        flatForward = flatForward.Unit
    end

    local flatRight = Vector3.new(cameraRight.X, 0, cameraRight.Z)
    if flatRight.Magnitude < 0.001 then
        flatRight = Vector3.new(1, 0, 0)
    else
        flatRight = flatRight.Unit
    end

    local horizontalMove = (flatForward * (localFlyInput.forward - localFlyInput.back))
        + (flatRight * (localFlyInput.right - localFlyInput.left))

    if horizontalMove.Magnitude < 0.01 and humanoid and humanoid.MoveDirection.Magnitude > 0.01 then
        horizontalMove = humanoid.MoveDirection
    end
    if horizontalMove.Magnitude > 1 then
        horizontalMove = horizontalMove.Unit
    end

    local verticalMove = localFlyInput.up - localFlyInput.down
    if verticalMove == 0 and humanoid and humanoid.Jump then
        verticalMove = 1
    end

    local moveDir = horizontalMove + Vector3.new(0, verticalMove, 0)
    if moveDir.Magnitude > 1 then
        moveDir = moveDir.Unit
    end

    localPlayerFlySpeed = clampLocalPlayerFlySpeed(localPlayerFlySpeed)
    localFlyBodyVelocity.Velocity = moveDir * localPlayerFlySpeed
    localFlyBodyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + flatForward, Vector3.new(0, 1, 0))

    return true
end

local function getCurrentSeatPart()
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

local function getCurrentVehicleSeat()
    local seatPart = getCurrentSeatPart()
    if seatPart and seatPart:IsA("VehicleSeat") then
        return seatPart
    end
    return nil
end

local function rememberVehicleSeatDefaults(seat)
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

local function clampBoatSpeedValue(value)
    return math.clamp(
        math.floor((tonumber(value) or BOAT_ENGINE_MIN_SPEED) + 0.5),
        BOAT_ENGINE_MIN_SPEED,
        BOAT_ENGINE_MAX_SPEED
    )
end

local function restoreVehicleSeatDefaults(seat)
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

local function applyCustomSpeedToVehicleSeat(seat)
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

local function applyCustomVelocityBoostToVehicleSeat(seat)
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
    local currentVel = rootPart.AssemblyLinearVelocity
    local targetHorizontal = flatLook * targetSpeed

    pcall(function()
        rootPart.AssemblyLinearVelocity = Vector3.new(targetHorizontal.X, currentVel.Y, targetHorizontal.Z)
    end)
end

local function updateBoatEnginePowerForSeat()
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

local function getSeatAssemblyRootPart(seatPart)
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

local function clearBoatRamPart()
    if currentBoatRamPart and currentBoatRamPart.Parent then
        currentBoatRamPart:Destroy()
    end
    currentBoatRamPart = nil
end

local function ensureBoatRamPart(rootPart)
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
        ramPart.CanCollide = true
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

    local desiredCF = rootPart.CFrame * CFrame.new(0, 0, -((rootPart.Size.Z * 0.5) + BOAT_RAM_FORWARD_OFFSET))
    ramPart.CFrame = desiredCF
    ramPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity
    ramPart.AssemblyAngularVelocity = rootPart.AssemblyAngularVelocity

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

    return ramPart
end

local function isHealthLikeKey(name)
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

local function rememberAndProtectNumericValue(valueObj)
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

local function rememberAndProtectNumericAttributes(instance)
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

local function rememberAndProtectBoatPart(part, seatPart)
    if not (part and part.Parent and part:IsA("BasePart")) then
        return false
    end

    if currentBoatRamPart and part == currentBoatRamPart then
        return false
    end

    if BOAT_NO_DAMAGE_KEEP_SEAT_TOUCH and seatPart and part == seatPart then
        return false
    end

    local defaults = boatPartDefaults[part]
    if not defaults then
        defaults = {
            canTouch = part.CanTouch,
            canQuery = part.CanQuery
        }
        boatPartDefaults[part] = defaults
    end

    pcall(function()
        part.CanTouch = false
    end)
    pcall(function()
        part.CanQuery = false
    end)

    return true
end

local function getBoatAssemblyRootAndModel()
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

local function guardCurrentBoatAgainstDamage()
    local rootPart, boatModel = getBoatAssemblyRootAndModel()
    if not rootPart then
        clearBoatRamPart()
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

    local protectedCount = 0
    local protectedPartCount = 0
    local seen = {}
    local seatPart = getCurrentSeatPart()

    local function processInstance(instance)
        if not instance or seen[instance] then
            return
        end
        seen[instance] = true

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

local function restoreBoatDamageDefaults()
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
end

local function tryAutoUprightBoat()
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
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        rootPart.CFrame = uprightCF
    end)
end

local function clearSafetyPart()
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

local function isDoorLikeSurface(part)
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

local function getDynamicSafetyDrop(position)
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

local function createSafetyPart(position, boundsCF, boundsSize)
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
    if teamAutoSwitch then
        pendingTeamResyncUntil = os.clock() + 8
    end
    clearSafetyPart()
end)

local function tp(position, useSafetyPart, boundsCF, boundsSize)
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
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function getStageContainer()
    local bs = workspace:FindFirstChild("BoatStages")
    if bs and bs:FindFirstChild("NormalStages") then
        return bs.NormalStages
    end
    return workspace:FindFirstChild("NormalStages")
end

local function getStageBounds(stageObj)
    if stageObj:IsA("Model") then
        return stageObj:GetBoundingBox()
    elseif stageObj:IsA("BasePart") then
        return stageObj.CFrame, stageObj.Size
    end
    return nil, nil
end

local function clampTargetToBounds(targetPos, boundsCF, boundsSize)
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

local function isBlackHazardPart(part)
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

local function getBlackHazardParts(stageObj)
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

local function getHorizontalDistanceAndAwayDir(point, part)
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

local function offsetTargetFromBlackParts(stageObj, targetPos, boundsCF, boundsSize)
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

local function getStageFloorPart(stageModel)
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

local function getGroundYAt(stageObj, x, z, fallbackY)
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

local function getStableGroundY(stageObj, x, z, fallbackY)
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

local function getStageDoorPart(stageModel, referencePos)
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

local function getStageApproachTarget(stageObj, boundsCF, boundsSize, referencePos)
    return boundsCF.Position
end

local function clampGroundYToStage(groundY, boundsCF, boundsSize)
    local boundsCenterY = boundsCF.Position.Y
    local boundsBottomY = boundsCenterY - (boundsSize.Y * 0.5)
    local boundsTopY = boundsCenterY + (boundsSize.Y * 0.5)

    local minAllowedY = math.max(boundsCenterY - 8, boundsBottomY + 2)
    local maxAllowedY = boundsTopY + 8
    return math.clamp(groundY, minAllowedY, maxAllowedY)
end

local function getStagePosition(stageObj, referencePos)
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

local function getOrderedStages()
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

local function getModelAnchorPart(model)
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

local function getChestInteractionTargets(chestPart)
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

local function findChestPart()
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

local function moveRootNearPart(root, part)
    if not root or not part or not part.Parent then return end
    local lift = (part.Size.Y * 0.5) + (root.Size.Y * 0.5) + 1.2
    local target = part.Position + (part.CFrame.UpVector * lift)
    root.CFrame = CFrame.new(target)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function openChest(chestPart)
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

local function normalizeKey(value)
    local s = tostring(value or ""):lower()
    s = s:gsub("%s+", "")
    s = s:gsub("_", "")
    s = s:gsub("%-", "")
    return s
end

local function findTeamByColorName(colorName)
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

local function getOccupiedCount(team)
    if not team then return 0 end
    local count = 0
    for _, player in ipairs(team:GetPlayers()) do
        if player ~= LocalPlayer then
            count = count + 1
        end
    end
    return count
end

local function getTeamRemotes()
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

local function trySwitchTeamWithRemotes(targetTeam, colorName, remotes)
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
                    remote:FireServer(unpack(args))
                else
                    remote:InvokeServer(unpack(args))
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

local function attemptSwitchToSelectedTeam()
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

-- UI
local gui = Instance.new("ScreenGui")
gui.Name = "BBFT_AutoFarm_UI"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local THEME = {
    bg = Color3.fromRGB(14, 7, 13),
    panel = Color3.fromRGB(28, 10, 22),
    panelSoft = Color3.fromRGB(48, 21, 37),
    accent = Color3.fromRGB(230, 54, 92),
    accentSoft = Color3.fromRGB(168, 42, 72),
    text = Color3.fromRGB(247, 241, 244),
    textMuted = Color3.fromRGB(200, 173, 182),
    ok = Color3.fromRGB(56, 162, 112),
    idle = Color3.fromRGB(96, 41, 60)
}

local BACKGROUND_IMAGE = "rbxassetid://0" -- Kendi image id'ni buraya yazabilirsin.

local function mk(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        obj[k] = v
    end
    if parent then obj.Parent = parent end
    return obj
end

local function round(obj, radius)
    return mk("UICorner", {CornerRadius = UDim.new(0, radius)}, obj)
end

local function line(obj, color, tr)
    return mk("UIStroke", {Thickness = 1, Color = color, Transparency = tr or 0.5}, obj)
end

local main = mk("Frame", {
    Size = UDim2.new(0, 760, 0, 430),
    Position = UDim2.new(0.5, -380, 0.5, -215),
    BackgroundColor3 = THEME.bg,
    BackgroundTransparency = 0.06,
    BorderSizePixel = 0
}, gui)
round(main, 16)
line(main, THEME.accent, 0.4)

mk("Frame", {
    Size = UDim2.new(1, 10, 1, 10),
    Position = UDim2.new(0, -5, 0, -5),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.72,
    BorderSizePixel = 0,
    ZIndex = -1
}, main)

local scale = mk("UIScale", {}, main)

local function getViewport()
    local cam = workspace.CurrentCamera
    if cam then return cam.ViewportSize end
    return Vector2.new(1366, 768)
end

local function applyScale()
    local viewport = getViewport()
    local ratioX = viewport.X / 1080
    local ratioY = viewport.Y / 620
    scale.Scale = math.clamp(math.min(ratioX, ratioY), 0.52, 0.88)
end

applyScale()
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    applyScale()
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
    end
end)

local bgImage = mk("ImageLabel", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Image = BACKGROUND_IMAGE,
    ImageTransparency = 0.6,
    ScaleType = Enum.ScaleType.Crop,
    ZIndex = 0
}, main)
round(bgImage, 16)

local overlay = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(9, 5, 10),
    BackgroundTransparency = 0.36,
    BorderSizePixel = 0,
    ZIndex = 1
}, main)
round(overlay, 16)

mk("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(47, 10, 27)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(25, 11, 29)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 8, 21))
    }),
    Rotation = 35
}, overlay)

local moon = mk("Frame", {
    Size = UDim2.new(0, 430, 0, 430),
    Position = UDim2.new(0.62, -215, 0.42, -215),
    BackgroundColor3 = Color3.fromRGB(225, 71, 104),
    BackgroundTransparency = 0.85,
    BorderSizePixel = 0,
    ZIndex = 1
}, main)
mk("UICorner", {CornerRadius = UDim.new(1, 0)}, moon)

local topBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 52),
    BackgroundColor3 = THEME.panel,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    ZIndex = 3
}, main)

mk("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = THEME.accentSoft,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    ZIndex = 4
}, topBar)

local logo = mk("Frame", {
    Size = UDim2.new(0, 30, 0, 30),
    Position = UDim2.new(0, 12, 0, 11),
    BackgroundColor3 = THEME.accent,
    BorderSizePixel = 0,
    ZIndex = 4
}, topBar)
round(logo, 8)

mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "BB",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBlack,
    TextSize = 11,
    ZIndex = 5
}, logo)

mk("TextLabel", {
    Size = UDim2.new(1, -360, 0, 23),
    Position = UDim2.new(0, 50, 0, 6),
    BackgroundTransparency = 1,
    Text = "Foxname - Build A Boat For Treasure",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, topBar)

mk("TextLabel", {
    Size = UDim2.new(1, -360, 0, 18),
    Position = UDim2.new(0, 50, 0, 29),
    BackgroundTransparency = 1,
    Text = "discord.gg/bbftfarm",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, topBar)

local versionBadge = mk("TextButton", {
    Size = UDim2.new(0, 84, 0, 32),
    Position = UDim2.new(1, -186, 0, 10),
    BackgroundColor3 = THEME.accent,
    Text = "v1.0",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    AutoButtonColor = false,
    ZIndex = 4
}, topBar)
round(versionBadge, 999)

local minimizeButton = mk("TextButton", {
    Size = UDim2.new(0, 30, 0, 30),
    Position = UDim2.new(1, -92, 0, 11),
    BackgroundColor3 = Color3.fromRGB(67, 24, 40),
    Text = "-",
    TextColor3 = Color3.fromRGB(242, 206, 218),
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    AutoButtonColor = false,
    ZIndex = 4
}, topBar)
round(minimizeButton, 8)

local mobileCloseLine = mk("TextButton", {
    Size = UDim2.new(0, 66, 0, 5),
    Position = UDim2.new(0.5, -33, 1, -8),
    BackgroundColor3 = Color3.fromRGB(255, 198, 214),
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    Visible = isTouchDevice,
    ZIndex = 5
}, topBar)
round(mobileCloseLine, 999)

local closeButton = mk("TextButton", {
    Size = UDim2.new(0, 30, 0, 30),
    Position = UDim2.new(1, -50, 0, 11),
    BackgroundColor3 = Color3.fromRGB(67, 24, 40),
    Text = "X",
    TextColor3 = Color3.fromRGB(242, 206, 218),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, topBar)
round(closeButton, 8)

closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local mobileOpenButton = mk("TextButton", {
    Size = UDim2.new(0, 126, 0, 34),
    Position = UDim2.new(0.5, -63, 0, 10),
    BackgroundColor3 = THEME.accent,
    Text = "Open Panel",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 20
}, gui)
round(mobileOpenButton, 999)
line(mobileOpenButton, THEME.accentSoft, 0.25)

local sidebar = mk("Frame", {
    Size = UDim2.new(0, 188, 1, -64),
    Position = UDim2.new(0, 10, 0, 56),
    BackgroundColor3 = THEME.panel,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    ZIndex = 3
}, main)
round(sidebar, 12)
line(sidebar, THEME.accentSoft, 0.7)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 20),
    Position = UDim2.new(0, 10, 0, 8),
    BackgroundTransparency = 1,
    Text = "Menu",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, sidebar)

local navList = mk("Frame", {
    Size = UDim2.new(1, -12, 0, 238),
    Position = UDim2.new(0, 6, 0, 32),
    BackgroundTransparency = 1,
    ZIndex = 4
}, sidebar)

mk("UIListLayout", {
    Padding = UDim.new(0, 6),
    HorizontalAlignment = Enum.HorizontalAlignment.Center
}, navList)

local function makeNavButton(iconText, buttonText)
    local row = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Color3.fromRGB(46, 19, 33),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4
    }, navList)
    round(row, 10)

    local icon = mk("TextLabel", {
        Size = UDim2.new(0, 24, 1, 0),
        Position = UDim2.new(0, 9, 0, 0),
        BackgroundTransparency = 1,
        Text = iconText,
        TextColor3 = Color3.fromRGB(206, 151, 166),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        ZIndex = 5
    }, row)

    local label = mk("TextLabel", {
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 34, 0, 0),
        BackgroundTransparency = 1,
        Text = buttonText,
        TextColor3 = Color3.fromRGB(222, 195, 203),
        Font = Enum.Font.GothamSemibold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5
    }, row)

    return row, icon, label
end

local infoTab, infoIcon, infoLabel = makeNavButton("i", "Info")
local farmTab, farmIcon, farmLabel = makeNavButton("F", "Farm")
local teamTab, teamIcon, teamLabel = makeNavButton("T", "Team Shift")
local boatTab, boatIcon, boatLabel = makeNavButton("B", "Boat")
local localPlayerTab, localPlayerIcon, localPlayerLabel = makeNavButton("L", "Local Player")

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 10, 1, -44),
    BackgroundTransparency = 1,
    Text = "Version",
    TextColor3 = Color3.fromRGB(255, 170, 190),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, sidebar)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 15),
    Position = UDim2.new(0, 10, 1, -29),
    BackgroundTransparency = 1,
    Text = "v1.0",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, sidebar)

local content = mk("Frame", {
    Size = UDim2.new(1, -214, 1, -64),
    Position = UDim2.new(0, 204, 0, 56),
    BackgroundTransparency = 1,
    ZIndex = 3
}, main)

local farmPage = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3
}, content)

mk("TextLabel", {
    Size = UDim2.new(1, -10, 0, 36),
    Position = UDim2.new(0, 4, 0, 0),
    BackgroundTransparency = 1,
    Text = "Farm",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, farmPage)

local moduleCard = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 102),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ZIndex = 3
}, farmPage)
round(moduleCard, 13)
line(moduleCard, THEME.accentSoft, 0.66)

mk("TextLabel", {
    Size = UDim2.new(1, -280, 0, 26),
    Position = UDim2.new(0, 14, 0, 10),
    BackgroundTransparency = 1,
    Text = "AutoFarm Module",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, moduleCard)

mk("TextLabel", {
    Size = UDim2.new(1, -280, 0, 18),
    Position = UDim2.new(0, 14, 0, 37),
    BackgroundTransparency = 1,
    Text = "Teleport all stages, open chest, then loop",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, moduleCard)

local status = mk("TextLabel", {
    Size = UDim2.new(0, 92, 0, 28),
    Position = UDim2.new(1, -106, 0, 11),
    BackgroundColor3 = THEME.idle,
    BackgroundTransparency = 0.08,
    Text = "IDLE",
    TextColor3 = Color3.fromRGB(255, 214, 224),
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    ZIndex = 4
}, moduleCard)
round(status, 999)

local toggle = mk("TextButton", {
    Size = UDim2.new(0, 230, 0, 36),
    Position = UDim2.new(0, 14, 0, 56),
    Text = "Enable AutoFarm",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = false,
    ZIndex = 4
}, moduleCard)
round(toggle, 10)

local farmStatLabel = mk("TextLabel", {
    Size = UDim2.new(1, -256, 0, 18),
    Position = UDim2.new(0, 246, 0, 65),
    BackgroundTransparency = 1,
    Text = "00.00.00 = 0 gold",
    TextColor3 = Color3.fromRGB(232, 208, 216),
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, moduleCard)

local teamPage = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Visible = false
}, content)

mk("TextLabel", {
    Size = UDim2.new(1, -10, 0, 36),
    Position = UDim2.new(0, 4, 0, 0),
    BackgroundTransparency = 1,
    Text = "Team Shift",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, teamPage)

local teamCard = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 188),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ZIndex = 3
}, teamPage)
round(teamCard, 13)
line(teamCard, THEME.accentSoft, 0.66)

local selectedTeamLabel = mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 22),
    Position = UDim2.new(0, 12, 0, 10),
    BackgroundTransparency = 1,
    Text = "Selected Team: Red",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, teamCard)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 32),
    Position = UDim2.new(0, 12, 0, 31),
    BackgroundTransparency = 1,
    Text = "Auto switch when selected team is empty.\nWarning: Your builds will not be transferred.",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, teamCard)

local teamColorPanel = mk("Frame", {
    Size = UDim2.new(1, -20, 0, 66),
    Position = UDim2.new(0, 10, 0, 72),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 4
}, teamCard)

local teamGrid = mk("UIGridLayout", {
    CellSize = UDim2.new(0, 95, 0, 24),
    CellPadding = UDim2.new(0, 6, 0, 6),
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    SortOrder = Enum.SortOrder.LayoutOrder
}, teamColorPanel)

local teamColorButtons = {}
local teamColorStrokes = {}
for index, colorName in ipairs(TEAM_COLOR_OPTIONS) do
    local swatch = TEAM_SWATCH[colorName] or THEME.panel
    local btn = mk("TextButton", {
        Size = UDim2.new(0, 95, 0, 24),
        LayoutOrder = index,
        BackgroundColor3 = swatch,
        BorderSizePixel = 0,
        Text = colorName,
        TextColor3 = LIGHT_TEAM_TEXT[colorName] and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        AutoButtonColor = false,
        ZIndex = 5
    }, teamColorPanel)
    round(btn, 8)
    local stroke = line(btn, Color3.fromRGB(255, 255, 255), 0.8)
    teamColorButtons[colorName] = btn
    teamColorStrokes[colorName] = stroke
end

local teamAutoToggle = mk("TextButton", {
    Size = UDim2.new(0, 170, 0, 32),
    Position = UDim2.new(0, 12, 1, -40),
    Text = "Enable Auto Switch",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, teamCard)
round(teamAutoToggle, 10)

local teamStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -196, 0, 28),
    Position = UDim2.new(0, 186, 1, -40),
    BackgroundTransparency = 1,
    Text = "Idle",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Center,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, teamCard)

local boatPage = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Visible = false
}, content)

mk("TextLabel", {
    Size = UDim2.new(1, -10, 0, 36),
    Position = UDim2.new(0, 4, 0, 0),
    BackgroundTransparency = 1,
    Text = "Boat Utility",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, boatPage)

local uprightCard = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 146),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ZIndex = 3
}, boatPage)
round(uprightCard, 13)
line(uprightCard, THEME.accentSoft, 0.66)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 22),
    Position = UDim2.new(0, 12, 0, 10),
    BackgroundTransparency = 1,
    Text = "Auto Upright",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, uprightCard)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 12, 0, 31),
    BackgroundTransparency = 1,
    Text = "Automatically flips your boat upright when it turns upside down.",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, uprightCard)

local boatUprightToggle = mk("TextButton", {
    Size = UDim2.new(0, 200, 0, 32),
    Position = UDim2.new(0, 12, 0, 58),
    Text = "Enable Auto Upright",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, uprightCard)
round(boatUprightToggle, 10)

local boatUprightStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 60),
    BackgroundTransparency = 1,
    Text = "Status: Off",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, uprightCard)

local boatSeatStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 76),
    BackgroundTransparency = 1,
    Text = "Seat: Not seated",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, uprightCard)

local boatNoDamageToggle = mk("TextButton", {
    Size = UDim2.new(0, 200, 0, 32),
    Position = UDim2.new(0, 12, 0, 98),
    Text = "Enable No Boat Damage",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, uprightCard)
round(boatNoDamageToggle, 10)

local boatNoDamageStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 100),
    BackgroundTransparency = 1,
    Text = "No Damage: Off",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, uprightCard)

local boatNoDamageHintLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 116),
    BackgroundTransparency = 1,
    Text = "Seat required",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, uprightCard)

local engineCard = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 170),
    Position = UDim2.new(0, 0, 0, 192),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ZIndex = 3
}, boatPage)
round(engineCard, 13)
line(engineCard, THEME.accentSoft, 0.66)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 22),
    Position = UDim2.new(0, 12, 0, 10),
    BackgroundTransparency = 1,
    Text = "Boat Engine Power",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, engineCard)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 12, 0, 31),
    BackgroundTransparency = 1,
    Text = "Use Normal Speed or drag the slider (1-500).",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, engineCard)

local normalSpeedButton = mk("TextButton", {
    Size = UDim2.new(0, 146, 0, 34),
    Position = UDim2.new(0, 12, 0, 56),
    Text = "Normal Speed",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, engineCard)
round(normalSpeedButton, 10)

local applyCustomSpeedButton = mk("TextButton", {
    Size = UDim2.new(0, 146, 0, 34),
    Position = UDim2.new(0, 166, 0, 56),
    Text = "Use Custom",
    BackgroundColor3 = THEME.ok,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 4
}, engineCard)
round(applyCustomSpeedButton, 10)

local boatSpeedValueLabel = mk("TextLabel", {
    Size = UDim2.new(1, -324, 0, 16),
    Position = UDim2.new(0, 324, 0, 65),
    BackgroundTransparency = 1,
    Text = "Custom Speed: 100",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, engineCard)

local boatSpeedSliderTrack = mk("Frame", {
    Size = UDim2.new(1, -24, 0, 10),
    Position = UDim2.new(0, 12, 0, 97),
    BackgroundColor3 = Color3.fromRGB(52, 23, 37),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 4
}, engineCard)
round(boatSpeedSliderTrack, 999)
line(boatSpeedSliderTrack, THEME.accentSoft, 0.5)

local boatSpeedSliderFill = mk("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = THEME.accent,
    BorderSizePixel = 0,
    ZIndex = 5
}, boatSpeedSliderTrack)
round(boatSpeedSliderFill, 999)

local boatSpeedSliderKnob = mk("Frame", {
    Size = UDim2.new(0, 14, 0, 14),
    Position = UDim2.new(0, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(255, 235, 241),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 6
}, boatSpeedSliderTrack)
round(boatSpeedSliderKnob, 999)
line(boatSpeedSliderKnob, THEME.accentSoft, 0.35)

local boatEngineModeLabel = mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 12, 0, 118),
    BackgroundTransparency = 1,
    Text = "Mode: Normal Speed",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, engineCard)

local boatEngineStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 32),
    Position = UDim2.new(0, 12, 0, 136),
    BackgroundTransparency = 1,
    Text = "Status: Waiting for a VehicleSeat.",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, engineCard)

local boatSpeedSliderDragging = false
local localPlayerFlySliderDragging = false

local localPlayerPage = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Visible = false
}, content)

mk("TextLabel", {
    Size = UDim2.new(1, -10, 0, 36),
    Position = UDim2.new(0, 4, 0, 0),
    BackgroundTransparency = 1,
    Text = "Local Player",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localPlayerPage)

local localMovementCard = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 228),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ZIndex = 3
}, localPlayerPage)
round(localMovementCard, 13)
line(localMovementCard, THEME.accentSoft, 0.66)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 22),
    Position = UDim2.new(0, 12, 0, 10),
    BackgroundTransparency = 1,
    Text = "Movement Utility",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localMovementCard)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 12, 0, 31),
    BackgroundTransparency = 1,
    Text = "Toggle character noclip/fly and tune fly speed.",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localMovementCard)

local localPlayerNoclipToggle = mk("TextButton", {
    Size = UDim2.new(0, 200, 0, 32),
    Position = UDim2.new(0, 12, 0, 58),
    Text = "Enable Noclip",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, localMovementCard)
round(localPlayerNoclipToggle, 10)

local localPlayerNoclipStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 66),
    BackgroundTransparency = 1,
    Text = "Noclip: Off",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localMovementCard)

local localPlayerFlyToggle = mk("TextButton", {
    Size = UDim2.new(0, 200, 0, 32),
    Position = UDim2.new(0, 12, 0, 98),
    Text = "Enable Fly",
    BackgroundColor3 = THEME.accent,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    ZIndex = 4
}, localMovementCard)
round(localPlayerFlyToggle, 10)

local localPlayerFlyStatusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 100),
    BackgroundTransparency = 1,
    Text = "Fly: Off",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localMovementCard)

local localPlayerFlyHintLabel = mk("TextLabel", {
    Size = UDim2.new(1, -224, 0, 15),
    Position = UDim2.new(0, 220, 0, 116),
    BackgroundTransparency = 1,
    Text = "Keys: WASD + Space/Ctrl",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localMovementCard)

local localPlayerFlySpeedValueLabel = mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 12, 0, 140),
    BackgroundTransparency = 1,
    Text = "Fly Speed: 80",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localMovementCard)

local localPlayerFlySpeedSliderTrack = mk("Frame", {
    Size = UDim2.new(1, -24, 0, 10),
    Position = UDim2.new(0, 12, 0, 164),
    BackgroundColor3 = Color3.fromRGB(52, 23, 37),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 4
}, localMovementCard)
round(localPlayerFlySpeedSliderTrack, 999)
line(localPlayerFlySpeedSliderTrack, THEME.accentSoft, 0.5)

local localPlayerFlySpeedSliderFill = mk("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = THEME.accent,
    BorderSizePixel = 0,
    ZIndex = 5
}, localPlayerFlySpeedSliderTrack)
round(localPlayerFlySpeedSliderFill, 999)

local localPlayerFlySpeedSliderKnob = mk("Frame", {
    Size = UDim2.new(0, 14, 0, 14),
    Position = UDim2.new(0, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(255, 235, 241),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 6
}, localPlayerFlySpeedSliderTrack)
round(localPlayerFlySpeedSliderKnob, 999)
line(localPlayerFlySpeedSliderKnob, THEME.accentSoft, 0.35)

local localPlayerKeybindCard = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 90),
    Position = UDim2.new(0, 0, 0, 274),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ZIndex = 3
}, localPlayerPage)
round(localPlayerKeybindCard, 13)
line(localPlayerKeybindCard, THEME.accentSoft, 0.66)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 22),
    Position = UDim2.new(0, 12, 0, 8),
    BackgroundTransparency = 1,
    Text = "Keybinds",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localPlayerKeybindCard)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 18),
    Position = UDim2.new(0, 12, 0, 32),
    BackgroundTransparency = 1,
    Text = "G -> Toggle panel (hide/show)",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localPlayerKeybindCard)

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 18),
    Position = UDim2.new(0, 12, 0, 52),
    BackgroundTransparency = 1,
    Text = "Fly -> WASD + Space/E up, Ctrl/Q down",
    TextColor3 = THEME.textMuted,
    Font = Enum.Font.GothamSemibold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, localPlayerKeybindCard)

local infoPage = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Visible = false
}, content)

mk("TextLabel", {
    Size = UDim2.new(1, -10, 0, 36),
    Position = UDim2.new(0, 4, 0, 0),
    BackgroundTransparency = 1,
    Text = "Info - v1.0 Updates",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4
}, infoPage)

local infoCard = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -46),
    Position = UDim2.new(0, 0, 0, 42),
    BackgroundColor3 = THEME.panelSoft,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    ZIndex = 3
}, infoPage)
round(infoCard, 13)
line(infoCard, THEME.accentSoft, 0.68)

local infoScroll = mk("ScrollingFrame", {
    Size = UDim2.new(1, -16, 1, -16),
    Position = UDim2.new(0, 8, 0, 8),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 5,
    ScrollBarImageColor3 = Color3.fromRGB(129, 71, 88),
    ZIndex = 4
}, infoCard)

local infoLayout = mk("UIListLayout", {
    Padding = UDim.new(0, 7),
    HorizontalAlignment = Enum.HorizontalAlignment.Left
}, infoScroll)

local function addInfo(text)
    mk("TextLabel", {
        Size = UDim2.new(1, -6, 0, 26),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = THEME.textMuted,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 5
    }, infoScroll)
end

addInfo("v1.0 + Added AutoFarm toggle in Farm tab.")
addInfo("v1.0 + Teleport now lands closer to each stage center.")
addInfo("v1.0 + Teleport height is adjusted lower and closer to ground.")
addInfo("v1.0 + Added safety platform support for early stages.")
addInfo("v1.0 + On Stage 10, safety platform is removed.")
addInfo("v1.0 + Instant death on water/damage is disabled.")
addInfo("v1.0 + Added simple Info/Farm tab interface.")
addInfo("v1.1 + Keybind: G now toggles full panel visibility.")
addInfo("v1.1 + Added Local Player tab (noclip, fly, fly speed).")

local function refreshInfoCanvas()
    infoScroll.CanvasSize = UDim2.new(0, 0, 0, infoLayout.AbsoluteContentSize.Y + 6)
end
infoLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshInfoCanvas)
refreshInfoCanvas()

local function setNavActive(button, icon, label)
    button.BackgroundColor3 = Color3.fromRGB(95, 32, 53)
    button.BackgroundTransparency = 0.15
    icon.TextColor3 = Color3.fromRGB(255, 232, 239)
    label.TextColor3 = Color3.fromRGB(255, 241, 246)
end

local function setNavPassive(button, icon, label)
    button.BackgroundColor3 = Color3.fromRGB(46, 19, 33)
    button.BackgroundTransparency = 0.3
    icon.TextColor3 = Color3.fromRGB(206, 151, 166)
    label.TextColor3 = Color3.fromRGB(222, 195, 203)
end

local function showPage(pageName)
    farmPage.Visible = (pageName == "farm")
    teamPage.Visible = (pageName == "team")
    boatPage.Visible = (pageName == "boat")
    localPlayerPage.Visible = (pageName == "localplayer")
    infoPage.Visible = (pageName == "info")

    setNavPassive(farmTab, farmIcon, farmLabel)
    setNavPassive(teamTab, teamIcon, teamLabel)
    setNavPassive(boatTab, boatIcon, boatLabel)
    setNavPassive(localPlayerTab, localPlayerIcon, localPlayerLabel)
    setNavPassive(infoTab, infoIcon, infoLabel)

    if pageName == "farm" then
        setNavActive(farmTab, farmIcon, farmLabel)
    elseif pageName == "team" then
        setNavActive(teamTab, teamIcon, teamLabel)
    elseif pageName == "boat" then
        setNavActive(boatTab, boatIcon, boatLabel)
    elseif pageName == "localplayer" then
        setNavActive(localPlayerTab, localPlayerIcon, localPlayerLabel)
    else
        setNavActive(infoTab, infoIcon, infoLabel)
    end
end

local function setPanelVisibleState(visible)
    panelVisible = visible and true or false
    main.Visible = panelVisible
    if not panelVisible then
        boatSpeedSliderDragging = false
        localPlayerFlySliderDragging = false
    end
    if isTouchDevice then
        mobileOpenButton.Visible = not panelVisible
    end
end

local function refreshTeamColorButtons()
    for colorName, button in pairs(teamColorButtons) do
        local isActive = (colorName == selectedTeamColorName)
        local stroke = teamColorStrokes[colorName]
        if isActive then
            button.BackgroundTransparency = 0
            button.TextSize = 12
            if stroke then
                stroke.Transparency = 0.35
                stroke.Thickness = 2
            end
        else
            button.BackgroundTransparency = 0.2
            button.TextSize = 11
            if stroke then
                stroke.Transparency = 0.8
                stroke.Thickness = 1
            end
        end
    end
    selectedTeamLabel.Text = "Selected Team: " .. selectedTeamColorName
end

local function setTeamToggleState(enabled)
    if enabled then
        teamAutoToggle.Text = "Disable Auto Switch"
        teamAutoToggle.BackgroundColor3 = THEME.ok
    else
        teamAutoToggle.Text = "Enable Auto Switch"
        teamAutoToggle.BackgroundColor3 = THEME.accent
    end
end

local function getBoatSeatStatusText()
    local seatPart = getCurrentSeatPart()
    if not seatPart then
        return "Seat: Not seated"
    end
    if seatPart:IsA("VehicleSeat") then
        return "Seat: VehicleSeat (" .. seatPart.Name .. ")"
    end
    return "Seat: Seat (" .. seatPart.Name .. ")"
end

local function setBoatUprightToggleState(enabled)
    if enabled then
        boatUprightToggle.Text = "Disable Auto Upright"
        boatUprightToggle.BackgroundColor3 = THEME.ok
        boatUprightStatusLabel.Text = "Status: On"
        boatUprightStatusLabel.TextColor3 = Color3.fromRGB(153, 232, 194)
    else
        boatUprightToggle.Text = "Enable Auto Upright"
        boatUprightToggle.BackgroundColor3 = THEME.accent
        boatUprightStatusLabel.Text = "Status: Off"
        boatUprightStatusLabel.TextColor3 = THEME.textMuted
    end
end

local function setBoatNoDamageToggleState(enabled, hintText)
    if enabled then
        boatNoDamageToggle.Text = "Disable No Boat Damage"
        boatNoDamageToggle.BackgroundColor3 = THEME.ok
        boatNoDamageStatusLabel.Text = "No Damage: On"
        boatNoDamageStatusLabel.TextColor3 = Color3.fromRGB(153, 232, 194)
    else
        boatNoDamageToggle.Text = "Enable No Boat Damage"
        boatNoDamageToggle.BackgroundColor3 = THEME.accent
        boatNoDamageStatusLabel.Text = "No Damage: Off"
        boatNoDamageStatusLabel.TextColor3 = THEME.textMuted
    end

    if hintText then
        boatNoDamageHintLabel.Text = hintText
    elseif enabled then
        if getCurrentSeatPart() then
            boatNoDamageHintLabel.Text = "Guarding current boat"
        else
            boatNoDamageHintLabel.Text = "Enabled (sit on boat)"
        end
    else
        boatNoDamageHintLabel.Text = "Seat required"
    end
end

local function setLocalPlayerNoclipToggleState(enabled)
    if enabled then
        localPlayerNoclipToggle.Text = "Disable Noclip"
        localPlayerNoclipToggle.BackgroundColor3 = THEME.ok
        localPlayerNoclipStatusLabel.Text = "Noclip: On"
        localPlayerNoclipStatusLabel.TextColor3 = Color3.fromRGB(153, 232, 194)
    else
        localPlayerNoclipToggle.Text = "Enable Noclip"
        localPlayerNoclipToggle.BackgroundColor3 = THEME.accent
        localPlayerNoclipStatusLabel.Text = "Noclip: Off"
        localPlayerNoclipStatusLabel.TextColor3 = THEME.textMuted
    end
end

local function setLocalPlayerFlyToggleState(enabled, statusText)
    if enabled then
        localPlayerFlyToggle.Text = "Disable Fly"
        localPlayerFlyToggle.BackgroundColor3 = THEME.ok
        localPlayerFlyStatusLabel.Text = statusText or "Fly: On"
        localPlayerFlyStatusLabel.TextColor3 = Color3.fromRGB(153, 232, 194)
    else
        localPlayerFlyToggle.Text = "Enable Fly"
        localPlayerFlyToggle.BackgroundColor3 = THEME.accent
        localPlayerFlyStatusLabel.Text = statusText or "Fly: Off"
        localPlayerFlyStatusLabel.TextColor3 = THEME.textMuted
    end
end

local function getLocalPlayerFlySpeedRatioFromValue(speedValue)
    local range = LOCAL_PLAYER_FLY_MAX_SPEED - LOCAL_PLAYER_FLY_MIN_SPEED
    if range <= 0 then
        return 0
    end
    local clamped = clampLocalPlayerFlySpeed(speedValue)
    return (clamped - LOCAL_PLAYER_FLY_MIN_SPEED) / range
end

local function updateLocalPlayerFlySpeedSliderVisual()
    localPlayerFlySpeed = clampLocalPlayerFlySpeed(localPlayerFlySpeed)
    local ratio = getLocalPlayerFlySpeedRatioFromValue(localPlayerFlySpeed)
    localPlayerFlySpeedSliderFill.Size = UDim2.new(ratio, 0, 1, 0)
    localPlayerFlySpeedSliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
    localPlayerFlySpeedValueLabel.Text = string.format("Fly Speed: %d", localPlayerFlySpeed)
end

local function setLocalPlayerFlySpeedFromRatio(ratio)
    ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
    local range = LOCAL_PLAYER_FLY_MAX_SPEED - LOCAL_PLAYER_FLY_MIN_SPEED
    local speed = LOCAL_PLAYER_FLY_MIN_SPEED + (range * ratio)
    localPlayerFlySpeed = clampLocalPlayerFlySpeed(speed)
    updateLocalPlayerFlySpeedSliderVisual()
    if localPlayerFly then
        localPlayerFlyStatusLabel.Text = string.format("Fly: On (%d)", localPlayerFlySpeed)
    end
end

local function setLocalPlayerFlySpeedFromScreenX(screenX)
    local trackWidth = localPlayerFlySpeedSliderTrack.AbsoluteSize.X
    if trackWidth <= 0 then
        return
    end
    local localX = screenX - localPlayerFlySpeedSliderTrack.AbsolutePosition.X
    setLocalPlayerFlySpeedFromRatio(localX / trackWidth)
end

local function getBoatSpeedRatioFromValue(speedValue)
    local range = BOAT_ENGINE_MAX_SPEED - BOAT_ENGINE_MIN_SPEED
    if range <= 0 then
        return 0
    end
    local clamped = clampBoatSpeedValue(speedValue)
    return (clamped - BOAT_ENGINE_MIN_SPEED) / range
end

local function updateBoatSpeedSliderVisual()
    boatCustomSpeed = clampBoatSpeedValue(boatCustomSpeed)
    local ratio = getBoatSpeedRatioFromValue(boatCustomSpeed)
    boatSpeedSliderFill.Size = UDim2.new(ratio, 0, 1, 0)
    boatSpeedSliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
    boatSpeedValueLabel.Text = string.format("Custom Speed: %d", boatCustomSpeed)
end

local function setBoatSpeedFromRatio(ratio)
    ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
    local range = BOAT_ENGINE_MAX_SPEED - BOAT_ENGINE_MIN_SPEED
    local speed = BOAT_ENGINE_MIN_SPEED + (range * ratio)
    boatCustomSpeed = clampBoatSpeedValue(speed)
    updateBoatSpeedSliderVisual()

    if boatEngineMode == "custom" then
        boatEngineModeLabel.Text = string.format("Mode: Custom Speed (%d)", boatCustomSpeed)
        updateBoatEnginePowerForSeat()
    end
end

local function setBoatSpeedFromScreenX(screenX)
    local trackWidth = boatSpeedSliderTrack.AbsoluteSize.X
    if trackWidth <= 0 then
        return
    end
    local localX = screenX - boatSpeedSliderTrack.AbsolutePosition.X
    setBoatSpeedFromRatio(localX / trackWidth)
end

local function refreshBoatEngineUi(statusText)
    if boatEngineMode == "custom" then
        boatEngineModeLabel.Text = string.format("Mode: Custom Speed (%d)", boatCustomSpeed)
        applyCustomSpeedButton.BackgroundColor3 = THEME.ok
        normalSpeedButton.BackgroundColor3 = Color3.fromRGB(128, 58, 81)
    else
        boatEngineModeLabel.Text = "Mode: Normal Speed"
        applyCustomSpeedButton.BackgroundColor3 = Color3.fromRGB(128, 58, 81)
        normalSpeedButton.BackgroundColor3 = THEME.accent
    end
    updateBoatSpeedSliderVisual()
    if statusText then
        boatEngineStatusLabel.Text = statusText
    end
end

local function applyCurrentCustomBoatSpeed()
    boatCustomSpeed = clampBoatSpeedValue(boatCustomSpeed)
    boatEngineMode = "custom"
    updateBoatEnginePowerForSeat()

    local vehicleSeat = getCurrentVehicleSeat()
    if vehicleSeat then
        refreshBoatEngineUi(string.format("Status: Custom speed %d applied to %s.", boatCustomSpeed, vehicleSeat.Name))
    else
        refreshBoatEngineUi(string.format("Status: Custom speed %d ready. Sit on a VehicleSeat to apply.", boatCustomSpeed))
    end
end

for colorName, button in pairs(teamColorButtons) do
    button.MouseButton1Click:Connect(function()
        selectedTeamColorName = colorName
        teamStatusLabel.Text = "Selected: " .. colorName
        teamStatusLabel.TextColor3 = THEME.textMuted
        refreshTeamColorButtons()
    end)
end

teamAutoToggle.MouseButton1Click:Connect(function()
    teamAutoSwitch = not teamAutoSwitch
    setTeamToggleState(teamAutoSwitch)
    if teamAutoSwitch then
        pendingTeamResyncUntil = os.clock() + 8
        teamStatusLabel.Text = "Watching " .. selectedTeamColorName .. "..."
        teamStatusLabel.TextColor3 = THEME.textMuted
    else
        pendingTeamResyncUntil = 0
        teamStatusLabel.Text = "Idle"
        teamStatusLabel.TextColor3 = THEME.textMuted
    end
end)

task.spawn(function()
    while gui and gui.Parent do
        local waitTime = TEAM_CHECK_INTERVAL
        if teamAutoSwitch and not teamSwitchInProgress then
            teamSwitchInProgress = true
            local ok, message = attemptSwitchToSelectedTeam()
            teamStatusLabel.Text = message
            teamStatusLabel.TextColor3 = ok and Color3.fromRGB(153, 232, 194) or THEME.textMuted
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

boatUprightToggle.MouseButton1Click:Connect(function()
    boatAutoUpright = not boatAutoUpright
    setBoatUprightToggleState(boatAutoUpright)
end)

boatNoDamageToggle.MouseButton1Click:Connect(function()
    boatNoDamage = not boatNoDamage
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
end)

normalSpeedButton.MouseButton1Click:Connect(function()
    boatEngineMode = "normal"
    updateBoatEnginePowerForSeat()
    refreshBoatEngineUi("Status: Normal seat speed restored.")
end)

applyCustomSpeedButton.MouseButton1Click:Connect(function()
    applyCurrentCustomBoatSpeed()
end)

localPlayerNoclipToggle.MouseButton1Click:Connect(function()
    localPlayerNoclip = not localPlayerNoclip
    if localPlayerNoclip then
        applyCharacterNoclip()
    else
        restoreCharacterNoclip()
    end
    setLocalPlayerNoclipToggleState(localPlayerNoclip)
end)

localPlayerFlyToggle.MouseButton1Click:Connect(function()
    localPlayerFly = not localPlayerFly
    if localPlayerFly then
        localPlayerFlySpeed = clampLocalPlayerFlySpeed(localPlayerFlySpeed)
        if ensureLocalFlyBodyMovers() then
            setLocalPlayerFlyToggleState(true, string.format("Fly: On (%d)", localPlayerFlySpeed))
        else
            setLocalPlayerFlyToggleState(true, string.format("Fly: On (%d) - waiting character", localPlayerFlySpeed))
        end
    else
        disableLocalFly()
        setLocalPlayerFlyToggleState(false, "Fly: Off")
    end
end)

local function beginLocalPlayerFlySpeedSliderDrag(input)
    local inputType = input.UserInputType
    if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
        return
    end
    localPlayerFlySliderDragging = true
    setLocalPlayerFlySpeedFromScreenX(input.Position.X)
end

local function beginBoatSpeedSliderDrag(input)
    local inputType = input.UserInputType
    if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
        return
    end
    boatSpeedSliderDragging = true
    boatEngineMode = "custom"
    setBoatSpeedFromScreenX(input.Position.X)

    local vehicleSeat = getCurrentVehicleSeat()
    if vehicleSeat then
        refreshBoatEngineUi(string.format("Status: Custom speed %d applied to %s.", boatCustomSpeed, vehicleSeat.Name))
    else
        refreshBoatEngineUi(string.format("Status: Custom speed %d ready. Sit on a VehicleSeat to apply.", boatCustomSpeed))
    end
end

boatSpeedSliderTrack.InputBegan:Connect(beginBoatSpeedSliderDrag)
boatSpeedSliderKnob.InputBegan:Connect(beginBoatSpeedSliderDrag)
localPlayerFlySpeedSliderTrack.InputBegan:Connect(beginLocalPlayerFlySpeedSliderDrag)
localPlayerFlySpeedSliderKnob.InputBegan:Connect(beginLocalPlayerFlySpeedSliderDrag)

task.spawn(function()
    while gui and gui.Parent do
        local now = os.clock()
        updateBoatEnginePowerForSeat()
        tryAutoUprightBoat()

        if localPlayerNoclip then
            applyCharacterNoclip()
        end

        if localPlayerFly then
            local canFlyNow = updateLocalFlyMotion()
            if canFlyNow then
                localPlayerFlyStatusLabel.Text = string.format("Fly: On (%d)", localPlayerFlySpeed)
                localPlayerFlyStatusLabel.TextColor3 = Color3.fromRGB(153, 232, 194)
            else
                localPlayerFlyStatusLabel.Text = string.format("Fly: On (%d) - waiting character", localPlayerFlySpeed)
                localPlayerFlyStatusLabel.TextColor3 = THEME.textMuted
            end
        end

        if boatNoDamage and (now - lastBoatDamageGuardAt) >= BOAT_DAMAGE_GUARD_INTERVAL then
            local hasBoat, protectedCount = guardCurrentBoatAgainstDamage()
            if hasBoat then
                boatNoDamageStatusLabel.Text = "No Damage: On"
                boatNoDamageStatusLabel.TextColor3 = Color3.fromRGB(153, 232, 194)
                boatNoDamageHintLabel.Text = string.format("Guarding current boat (%d)", protectedCount)
            else
                boatNoDamageHintLabel.Text = "Enabled (sit on boat)"
            end
            lastBoatDamageGuardAt = now
        end

        boatSeatStatusLabel.Text = getBoatSeatStatusText()
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

farmTab.MouseButton1Click:Connect(function()
    showPage("farm")
end)
teamTab.MouseButton1Click:Connect(function()
    showPage("team")
end)
boatTab.MouseButton1Click:Connect(function()
    showPage("boat")
end)
localPlayerTab.MouseButton1Click:Connect(function()
    showPage("localplayer")
end)
infoTab.MouseButton1Click:Connect(function()
    showPage("info")
end)

setTeamToggleState(false)
setBoatUprightToggleState(false)
setBoatNoDamageToggleState(false, "Seat required")
refreshBoatEngineUi("Status: Waiting for a VehicleSeat.")
boatSeatStatusLabel.Text = getBoatSeatStatusText()
refreshTeamColorButtons()
showPage("farm")
setLocalPlayerNoclipToggleState(false)
setLocalPlayerFlyToggleState(false, "Fly: Off")
updateLocalPlayerFlySpeedSliderVisual()
setPanelVisibleState(true)

minimizeButton.MouseButton1Click:Connect(function()
    setPanelVisibleState(false)
end)

mobileCloseLine.MouseButton1Click:Connect(function()
    setPanelVisibleState(false)
end)

mobileOpenButton.MouseButton1Click:Connect(function()
    setPanelVisibleState(true)
end)

local dragging = false
local dragStart
local startPos

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end
    if gameProcessed or UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == Enum.KeyCode.G then
        setPanelVisibleState(not panelVisible)
        return
    end

    if localPlayerFly then
        setLocalFlyInputForKey(input.KeyCode, true)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    if boatSpeedSliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        setBoatSpeedFromScreenX(input.Position.X)
        if boatEngineMode == "custom" then
            local vehicleSeat = getCurrentVehicleSeat()
            if vehicleSeat then
                boatEngineStatusLabel.Text = string.format("Status: Custom speed %d applied to %s.", boatCustomSpeed, vehicleSeat.Name)
            else
                boatEngineStatusLabel.Text = string.format("Status: Custom speed %d ready. Sit on a VehicleSeat to apply.", boatCustomSpeed)
            end
        end
    end

    if localPlayerFlySliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        setLocalPlayerFlySpeedFromScreenX(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        setLocalFlyInputForKey(input.KeyCode, false)
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        boatSpeedSliderDragging = false
        localPlayerFlySliderDragging = false
    end
end)

local function formatSessionClock(secondsElapsed)
    local total = math.max(0, math.floor(secondsElapsed or 0))
    local h = math.floor(total / 3600)
    local m = math.floor((total % 3600) / 60)
    local s = total % 60
    return string.format("%02d.%02d.%02d", h, m, s)
end

local function resolveGoldStat()
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

local function getCurrentGold()
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

local function refreshFarmStatLabel()
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

    farmStatLabel.Text = string.format("%s = %d gold", formatSessionClock(elapsedSeconds), gainedGold)
end

task.spawn(function()
    while gui and gui.Parent do
        refreshFarmStatLabel()
        task.wait(1)
    end
end)

local function setButtonState(enabled)
    if enabled then
        toggle.Text = "Disable AutoFarm"
        toggle.BackgroundColor3 = THEME.ok
        status.Text = "ACTIVE"
        status.BackgroundColor3 = Color3.fromRGB(34, 121, 84)
    else
        toggle.Text = "Enable AutoFarm"
        toggle.BackgroundColor3 = THEME.accent
        status.Text = "IDLE"
        status.BackgroundColor3 = THEME.idle
    end
end

setButtonState(false)
refreshFarmStatLabel()
local function runAutoFarm()
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

toggle.MouseButton1Click:Connect(function()
    autoFarm = not autoFarm
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
end)

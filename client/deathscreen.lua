-- ============================================================
--  plt_ambulance  –  client/deathscreen.lua  (deobfuscated)
--  Manages the player death / downed state:
--    • death-screen NUI overlay with countdown timer
--    • input lockout while downed (camera look still allowed)
--    • vehicle immobilisation on death
--    • "Call EMS" button with cooldown
--    • "Go to Hospital" button with transport delay
--    • auto bleed-out when the timer reaches zero
--    • revive handling
-- ============================================================

-- ----------------------------------------------------------------
--  Module-level state
-- ----------------------------------------------------------------

local isPlayerDead          = false   -- whether the local player is currently downed
local deathTimerSeconds     = 0       -- seconds remaining on the death countdown
local emsHasBeenCalled      = false   -- true once the player has called EMS this death
local currentDeathMode      = "dead"  -- NUI mode string ("dead", "dead_a", …)
local deathStartTime        = 0       -- GetGameTimer() value when the player went down
local transportDelaySeconds = 120     -- seconds to wait before "Go to Hospital" is available
local bleedOutTriggered     = false   -- true once the bleed-out server event has fired

-- Deathscreen feature toggle – disabled when Config.Deathscreen is falsy
local deathscreenDisabled = not Config.Deathscreen

-- Animation dict / name constants used to detect the downed pose
local ANIM_DEAD_DICT    = "dead"
local ANIM_DEAD_NAME    = "dead_a"
local ANIM_VEHICLE_DICT = "veh@low@front_ps@idle_duck"
local ANIM_VEHICLE_NAME = "sit"

-- Throttle timer: prevents the vehicle-immobilise logic from firing too often
local vehicleImmobiliseNextTime = 0

-- ----------------------------------------------------------------
--  IsPedDowned(ped)
--  Returns true if the given ped is considered dead / downed.
--  Checks player state bag flags, native dead/ragdoll states,
--  and whether the ped is playing a known death animation.
-- ----------------------------------------------------------------
local function IsPedDowned(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end

    -- Check state bag flags set by the server / other scripts
    local state = LocalPlayer and LocalPlayer.state
    if state then
        if state.dead == true
        or state.isDead == true
        or state.inlaststand == true then
            return true
        end
    end

    -- Native GTA death / ragdoll checks
    if IsPedDeadOrDying(ped, true) then return true end
    if IsPedRagdoll(ped) then return true end

    -- Known death animations
    if IsEntityPlayingAnim(ped, ANIM_DEAD_DICT,    ANIM_DEAD_NAME,    3) then return true end
    if IsEntityPlayingAnim(ped, ANIM_VEHICLE_DICT, ANIM_VEHICLE_NAME, 3) then return true end

    return false
end

-- ----------------------------------------------------------------
--  LockDeadControls()
--  Called every tick while the player is downed.
--  Disables almost all inputs but re-enables camera look and
--  the specific keys used by the death screen UI.
-- ----------------------------------------------------------------
local function LockDeadControls()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    DisableAllControlActions(0)

    -- Keep these inputs active while downed:
    --   1   = Look Left/Right (camera yaw)
    --   2   = Look Up/Down   (camera pitch)
    --   47  = INPUT_PHONE (opens the death-screen call button)
    --   199 = INPUT_FRONTEND_PAUSE
    --   200 = INPUT_FRONTEND_PAUSE_ALTERNATE
    --   245 = INPUT_CURSOR_SCROLL_UP
    --   246 = INPUT_CURSOR_SCROLL_DOWN
    DisableControlAction(0, 73, true)  -- make sure Enter stays suppressed

    EnableControlAction(0, 1,   true)
    EnableControlAction(0, 2,   true)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 246, true)
    EnableControlAction(0, 47,  true)
    EnableControlAction(0, 199, true)
    EnableControlAction(0, 200, true)

    -- Immobilise any vehicle the dead player is in, throttled to ~400 ms
    local now = GetGameTimer()
    if now >= vehicleImmobiliseNextTime then
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleUndriveable(vehicle, true)
                SetVehicleEngineOn(vehicle, false, true, true)
                SetVehicleForwardSpeed(vehicle, 0.0)
                SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
            end
            vehicleImmobiliseNextTime = now + 400
        end
    end
end

-- ----------------------------------------------------------------
--  SetDeathScreen(show, timerSeconds, mode)
--  Send a NUI message to show or hide the death overlay.
--  Guards against firing when the feature is disabled in Config.
-- ----------------------------------------------------------------
local function SetDeathScreen(show, timerSeconds, mode)
    if deathscreenDisabled then return end

    SendNUIMessage({
        action          = "amb_toggleDeathScreen",
        show            = show,
        time            = timerSeconds or 0,
        mode            = mode or currentDeathMode,
        transportDelay  = transportDelaySeconds,
    })
    SetNuiFocus(false, false)
end

-- ----------------------------------------------------------------
--  FindNearestCheckInBed()
--  Scans DepartmentData nodes for "check_in" entries and returns
--  the bed coords table (with x/y/z/h) closest to the local player.
--  Returns nil if none found.
-- ----------------------------------------------------------------
local function FindNearestCheckInBed()
    if not DepartmentData or not DepartmentData.nodes then return nil end

    local ped        = PlayerPedId()
    local playerPos  = GetEntityCoords(ped)
    local nearest    = nil
    local nearestDist = 999999.0

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "check_in" then
            local bed = node.coordsList and node.coordsList.bed
            if bed and bed.x then
                local bedPos = vector3(bed.x, bed.y, bed.z)
                local dist   = #(playerPos - bedPos)
                if dist < nearestDist then
                    nearestDist = dist
                    nearest     = bed
                end
            end
        end
    end

    return nearest
end

-- ================================================================
--  Event: player goes down  (server → client)
-- ================================================================
RegisterNetEvent("amb_client:onPlayerDeath")
AddEventHandler("amb_client:onPlayerDeath", function(deathData)
    if deathscreenDisabled then return end
    if isPlayerDead then return end  -- already handling a death

    -- Enter downed state
    isPlayerDead      = true
    currentDeathMode  = "dead"
    emsHasBeenCalled  = false
    bleedOutTriggered = false

    -- Read timer lengths from config (with sensible defaults)
    deathTimerSeconds     = tonumber(Config.Health.DeathTimer)             or 300
    deathStartTime        = GetGameTimer()
    transportDelaySeconds = tonumber(Config.Health.HospitalTransportDelay) or 120

    -- Show the NUI death screen
    SetDeathScreen(true, deathTimerSeconds, currentDeathMode)

    -- ---- Thread 1: countdown ticker ----
    -- Decrements deathTimerSeconds every second and pushes updates to NUI.
    -- When it reaches zero, fires the bleed-out server event once.
    CreateThread(function()
        while isPlayerDead do
            Wait(1000)

            if deathTimerSeconds > 0 then
                deathTimerSeconds = deathTimerSeconds - 1
                SendNUIMessage({ action = "amb_updateDeathTimer", time = deathTimerSeconds })
            else
                -- Timer expired – trigger bleed-out once
                if not bleedOutTriggered then
                    bleedOutTriggered = true
                    TriggerServerEvent("amb_server:bleedOut")
                end
                SendNUIMessage({ action = "amb_updateDeathTimer", time = 0 })
            end
        end
    end)

    -- ---- Thread 2: input lock + key polling ----
    -- Runs every 20 ms to:
    --   • lock controls
    --   • check if the player has stood back up (auto-clear)
    --   • INPUT_PHONE (47)  → call EMS
    --   • INPUT_SCROLL_DOWN (246) → go to hospital
    CreateThread(function()
        local callEMSTimerSeconds = Config.Health.CallEMSTimer or 60
        local nextAliveCheck      = 0          -- next GetGameTimer() value to check alive
        local callEMSKeyHeld      = false      -- debounce for phone key
        local goHospKeyHeld       = false      -- debounce for scroll-down key

        while isPlayerDead do
            Wait(20)
            LockDeadControls()

            local now = GetGameTimer()

            -- Periodically verify the player is still actually downed
            if now >= nextAliveCheck then
                local ped = PlayerPedId()
                if not IsPedDowned(ped) then
                    -- Player recovered without a formal revive event – clean up
                    isPlayerDead      = false
                    emsHasBeenCalled  = false
                    bleedOutTriggered = false
                    currentDeathMode  = "dead"
                    SetDeathScreen(false)
                    break
                end
                nextAliveCheck = now + 1000
            end

            -- ---- INPUT_PHONE (47) – Call EMS ----
            if IsDisabledControlPressed(0, 47) then
                if not callEMSKeyHeld then
                    callEMSKeyHeld = true

                    if not emsHasBeenCalled then
                        local elapsedSeconds = (GetGameTimer() - deathStartTime) / 1000

                        if elapsedSeconds >= callEMSTimerSeconds then
                            -- Cooldown passed – call EMS
                            emsHasBeenCalled = true
                            if type(SendDeathDispatch) == "function" then
                                SendDeathDispatch()
                            end
                            Framework.Notify(_L("ems_notified"), "success")
                            SendNUIMessage({ action = "amb_emsCalled" })
                        else
                            -- Still in cooldown
                            local remaining = math.ceil(callEMSTimerSeconds - elapsedSeconds)
                            Framework.Notify(_L("wait_before_calling", { seconds = remaining }), "error")
                        end
                    end
                end
            else
                callEMSKeyHeld = false
            end

            -- ---- INPUT_CURSOR_SCROLL_DOWN (246) – Go to Hospital ----
            if IsDisabledControlPressed(0, 246) then
                if not goHospKeyHeld then
                    goHospKeyHeld = true

                    local elapsedSeconds = (GetGameTimer() - deathStartTime) / 1000

                    if elapsedSeconds >= transportDelaySeconds then
                        -- Transport delay has passed – find a bed and warp
                        local bed = FindNearestCheckInBed()
                        if bed then
                            local ped = PlayerPedId()
                            SetEntityCoords(ped, bed.x, bed.y, bed.z, false, false, false, false)
                            SetEntityHeading(ped, bed.h or 0.0)
                            exports.plt_ambulance_job:RevivePlayer()

                            isPlayerDead      = false
                            emsHasBeenCalled  = false
                            bleedOutTriggered = false
                            currentDeathMode  = "dead"
                            SetDeathScreen(false)
                            Framework.Notify(_L("transported_to_hospital"), "success")
                        else
                            Framework.Notify(_L("no_checkin_bed"), "error")
                        end
                    else
                        -- Transport delay still active
                        local remaining = math.ceil(transportDelaySeconds - elapsedSeconds)
                        Framework.Notify(_L("transport_available_in", { seconds = remaining }), "error")
                    end
                end
            else
                goHospKeyHeld = false
            end
        end
    end)
end)

-- ================================================================
--  Event: player is revived  (server → client)
-- ================================================================
RegisterNetEvent("amb_client:onPlayerRevive")
AddEventHandler("amb_client:onPlayerRevive", function()
    if deathscreenDisabled then return end

    -- Clear all downed flags
    isPlayerDead      = false
    emsHasBeenCalled  = false
    bleedOutTriggered = false
    currentDeathMode  = "dead"

    -- Re-enable the vehicle if the player was in one while downed
    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleUndriveable(vehicle, false)
            end
        end
    end

    -- Hide the death screen overlay
    SetDeathScreen(false)
end)

-- ================================================================
--  NUI Callback: player pressed "Call EMS" button in the UI
-- ================================================================
RegisterNUICallback("amb_callEMS", function(data, cb)
    if deathscreenDisabled or not isPlayerDead then
        return cb("ok")
    end

    -- Prevent double-calling
    if emsHasBeenCalled then return cb("ok") end

    local callEMSTimerSeconds = Config.Health.CallEMSTimer or 60
    local elapsedSeconds      = (GetGameTimer() - deathStartTime) / 1000

    if callEMSTimerSeconds > elapsedSeconds then
        -- Still in cooldown
        local remaining = math.ceil(callEMSTimerSeconds - elapsedSeconds)
        Framework.Notify(_L("wait_before_calling", { seconds = remaining }), "error")
        return cb("ok")
    end

    -- Call EMS
    emsHasBeenCalled = true
    if type(SendDeathDispatch) == "function" then
        SendDeathDispatch()
    end
    Framework.Notify(_L("ems_notified"), "success")
    SendNUIMessage({ action = "amb_emsCalled" })
    cb("ok")
end)

-- ================================================================
--  NUI Callback: player pressed "Go to Hospital" button in the UI
-- ================================================================
RegisterNUICallback("amb_goHospital", function(data, cb)
    if deathscreenDisabled or not isPlayerDead then
        return cb("ok")
    end

    local elapsedSeconds = (GetGameTimer() - deathStartTime) / 1000
    local remaining      = math.ceil(math.max(0, transportDelaySeconds - elapsedSeconds))

    if remaining > 0 then
        -- Transport delay not yet elapsed
        SendNUIMessage({ action = "amb_transportState", available = false, remaining = remaining })
        Framework.Notify(_L("transport_available_in", { seconds = remaining }), "error")
        return cb("ok")
    end

    -- Find the nearest check-in bed
    local bed = FindNearestCheckInBed()
    if not bed then
        Framework.Notify(_L("no_checkin_bed"), "error")
        return cb("ok")
    end

    -- Teleport and revive
    local ped = PlayerPedId()
    SetEntityCoords(ped, bed.x, bed.y, bed.z, false, false, false, false)
    SetEntityHeading(ped, bed.h or 0.0)
    exports.plt_ambulance_job:RevivePlayer()

    isPlayerDead      = false
    emsHasBeenCalled  = false
    bleedOutTriggered = false
    currentDeathMode  = "dead"
    SetDeathScreen(false)
    Framework.Notify(_L("transported_to_hospital"), "success")
    cb("ok")
end)

-- ================================================================
--  Background thread: keep the NUI transport-button state in sync
--  Runs every second while the player is downed, pushing the
--  current transport availability and countdown to the NUI.
-- ================================================================
CreateThread(function()
    while true do
        Wait(1000)

        if not deathscreenDisabled and isPlayerDead then
            local elapsedSeconds = (GetGameTimer() - deathStartTime) / 1000
            local remaining      = math.ceil(math.max(0, transportDelaySeconds - elapsedSeconds))

            SendNUIMessage({
                action    = "amb_transportState",
                available = remaining <= 0,
                remaining = remaining,
            })
        end
    end
end)

-- ================================================================
--  Internal event: toggle downed state from other client scripts
--  (e.g. the health / injury system)
-- ================================================================
AddEventHandler("amb_client:SetDownedState", function(isDown)
    if deathscreenDisabled then return end

    if isDown then
        TriggerEvent("amb_client:onPlayerDeath")
    else
        TriggerEvent("amb_client:onPlayerRevive")
    end
end)
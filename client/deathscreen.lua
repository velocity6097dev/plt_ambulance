local isDead = false
local deathTimer = 0
local hasCalledEms = false
local deathStatus = "dead"
local timeOfDeath = 0
local hospitalTransportDelay = 120
local isBleedingOut = false

local animDeadDict = "dead"
local animDeadName = "dead_a"
local animVehDict = "veh@low@front_ps@idle_duck"
local animVehName = "sit"
local vehBlockTimer = 0

-- ==========================================
-- Utility Functions
-- ==========================================

local function IsPlayerDeadLocal(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.dead or LocalPlayer.state.isDead or LocalPlayer.state.inlaststand then
            return true
        end
    end

    if IsPedDeadOrDying(ped, true) then return true end
    if IsPedRagdoll(ped) then return true end
    if IsEntityPlayingAnim(ped, animDeadDict, animDeadName, 3) then return true end
    if IsEntityPlayingAnim(ped, animVehDict, animVehName, 3) then return true end

    return false
end

local function DisableKeysLoop()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    DisableAllControlActions(0)
    DisableControlAction(0, 73, true) -- X
    
    -- Enable Chat, Esc, Map, and Action Keys (T, Y, G, P)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 245, true) 
    EnableControlAction(0, 246, true) 
    EnableControlAction(0, 47, true)  
    EnableControlAction(0, 199, true) 
    EnableControlAction(0, 200, true) 

    if GetGameTimer() >= vehBlockTimer then
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh and veh ~= 0 and DoesEntityExist(veh) then
                SetVehicleUndriveable(veh, true)
                SetVehicleEngineOn(veh, false, true, true)
                SetVehicleForwardSpeed(veh, 0.0)
                SetEntityVelocity(veh, 0.0, 0.0, 0.0)
            end
            vehBlockTimer = GetGameTimer() + 400
        end
    end
end

local function ToggleDeathScreen(show, time, mode)
    if not Config.Deathscreen then return end

    SendNUIMessage({
        action = "amb_toggleDeathScreen",
        show = show,
        time = time or 0,
        mode = mode or deathStatus,
        transportDelay = hospitalTransportDelay
    })
    SetNuiFocus(false, false)
end

local function GetClosestHospitalBed()
    if not DepartmentData or not DepartmentData.nodes then return nil end

    local pedCoords = GetEntityCoords(PlayerPedId())
    local closestBed = nil
    local closestDist = 999999.0

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "check_in" and node.coordsList and node.coordsList.bed then
            local bed = node.coordsList.bed
            if bed.x then
                local bedCoords = vector3(bed.x, bed.y, bed.z)
                local dist = #(pedCoords - bedCoords)
                if dist < closestDist then
                    closestDist = dist
                    closestBed = bed
                end
            end
        end
    end
    return closestBed
end

-- ==========================================
-- Core Death/Revive Events
-- ==========================================

RegisterNetEvent("amb_client:onPlayerDeath", function()
    if not Config.Deathscreen then return end
    if isDead then return end

    isDead = true
    deathStatus = "dead"
    hasCalledEms = false
    isBleedingOut = false

    deathTimer = (Config.Health and Config.Health.DeathTimer) or 300
    timeOfDeath = GetGameTimer()
    hospitalTransportDelay = (Config.Health and Config.Health.HospitalTransportDelay) or 120

    ToggleDeathScreen(true, deathTimer, deathStatus)

    -- Death Timer Loop
    CreateThread(function()
        while isDead do
            Wait(1000)
            if deathTimer > 0 then
                deathTimer = deathTimer - 1
                SendNUIMessage({ action = "amb_updateDeathTimer", time = deathTimer })
            else
                if not isBleedingOut then
                    isBleedingOut = true
                    TriggerServerEvent("amb_server:bleedOut")
                end
                SendNUIMessage({ action = "amb_updateDeathTimer", time = 0 })
            end
        end
    end)

    -- Control Loop
    CreateThread(function()
        local callEmsTimer = (Config.Health and Config.Health.CallEMSTimer) or 60
        local checkTimer = 0
        local ePressed = false
        local hPressed = false

        while isDead do
            Wait(20)
            DisableKeysLoop()
            
            local gameTimer = GetGameTimer()

            -- Verify if the player actually revived externally
            if checkTimer <= gameTimer then
                local ped = PlayerPedId()
                if not IsPlayerDeadLocal(ped) then
                    isDead = false
                    hasCalledEms = false
                    isBleedingOut = false
                    deathStatus = "dead"
                    ToggleDeathScreen(false)
                    break
                end
                checkTimer = gameTimer + 1000
            end

            -- Press G to Call EMS
            if IsDisabledControlPressed(0, 47) and not ePressed then
                ePressed = true
                if not hasCalledEms then
                    local passedTime = (GetGameTimer() - timeOfDeath) / 1000
                    if passedTime >= callEmsTimer then
                        hasCalledEms = true
                        if SendDeathDispatch then SendDeathDispatch() end
                        Framework.Notify(_L("ems_notified"), "success")
                        SendNUIMessage({ action = "amb_emsCalled" })
                    else
                        local remaining = math.ceil(callEmsTimer - passedTime)
                        Framework.Notify(_L("wait_before_calling", { seconds = remaining }), "error")
                    end
                end
            elseif not IsDisabledControlPressed(0, 47) then
                ePressed = false
            end

            -- Press Y to Transport to Hospital
            if IsDisabledControlPressed(0, 246) and not hPressed then
                hPressed = true
                local passedTime = (GetGameTimer() - timeOfDeath) / 1000
                if passedTime >= hospitalTransportDelay then
                    local bed = GetClosestHospitalBed()
                    if bed then
                        local ped = PlayerPedId()
                        SetEntityCoords(ped, bed.x, bed.y, bed.z, false, false, false, false)
                        SetEntityHeading(ped, bed.h or 0.0)
                        
                        exports.plt_ambulance_job:RevivePlayer()
                        isDead = false
                        hasCalledEms = false
                        isBleedingOut = false
                        deathStatus = "dead"
                        ToggleDeathScreen(false)
                        Framework.Notify(_L("transported_to_hospital"), "success")
                    else
                        Framework.Notify(_L("no_checkin_bed"), "error")
                    end
                else
                    local remaining = math.ceil(hospitalTransportDelay - passedTime)
                    Framework.Notify(_L("transport_available_in", { seconds = remaining }), "error")
                end
            elseif not IsDisabledControlPressed(0, 246) then
                hPressed = false
            end
        end
    end)
end)

RegisterNetEvent("amb_client:onPlayerRevive", function()
    if not Config.Deathscreen then return end

    isDead = false
    hasCalledEms = false
    isBleedingOut = false
    deathStatus = "dead"

    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh and veh ~= 0 and DoesEntityExist(veh) then
                SetVehicleUndriveable(veh, false)
            end
        end
    end

    ToggleDeathScreen(false)
end)

-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback("amb_callEMS", function(data, cb)
    if not Config.Deathscreen or not isDead or hasCalledEms then
        return cb("ok")
    end

    local callEmsTimer = (Config.Health and Config.Health.CallEMSTimer) or 60
    local passedTime = (GetGameTimer() - timeOfDeath) / 1000

    if passedTime < callEmsTimer then
        local remaining = math.ceil(callEmsTimer - passedTime)
        Framework.Notify(_L("wait_before_calling", { seconds = remaining }), "error")
        return cb("ok")
    end

    hasCalledEms = true
    if SendDeathDispatch then SendDeathDispatch() end
    Framework.Notify(_L("ems_notified"), "success")
    SendNUIMessage({ action = "amb_emsCalled" })
    
    cb("ok")
end)

RegisterNUICallback("amb_goHospital", function(data, cb)
    if not Config.Deathscreen or not isDead then
        return cb("ok")
    end

    local passedTime = (GetGameTimer() - timeOfDeath) / 1000
    local remaining = math.ceil(math.max(0, hospitalTransportDelay - passedTime))

    if remaining > 0 then
        SendNUIMessage({
            action = "amb_transportState",
            available = false,
            remaining = remaining
        })
        Framework.Notify(_L("transport_available_in", { seconds = remaining }), "error")
        return cb("ok")
    end

    local bed = GetClosestHospitalBed()
    if not bed then
        Framework.Notify(_L("no_checkin_bed"), "error")
        return cb("ok")
    end

    local ped = PlayerPedId()
    SetEntityCoords(ped, bed.x, bed.y, bed.z, false, false, false, false)
    SetEntityHeading(ped, bed.h or 0.0)

    exports.plt_ambulance_job:RevivePlayer()
    isDead = false
    hasCalledEms = false
    isBleedingOut = false
    deathStatus = "dead"
    ToggleDeathScreen(false)
    Framework.Notify(_L("transported_to_hospital"), "success")
    
    cb("ok")
end)

-- ==========================================
-- Status Update Thread
-- ==========================================

CreateThread(function()
    while true do
        Wait(1000)
        if Config.Deathscreen and isDead then
            local passedTime = (GetGameTimer() - timeOfDeath) / 1000
            local remaining = math.ceil(math.max(0, hospitalTransportDelay - passedTime))
            
            SendNUIMessage({
                action = "amb_transportState",
                available = (remaining <= 0),
                remaining = remaining
            })
        end
    end
end)

RegisterNetEvent("amb_client:SetDownedState", function(state)
    if not Config.Deathscreen then return end
    if state then
        TriggerEvent("amb_client:onPlayerDeath")
    else
        TriggerEvent("amb_client:onPlayerRevive")
    end
end)
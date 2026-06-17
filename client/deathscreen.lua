local isDead = false
local deathTimer = 0
local emsCalled = false
local deathMode = "dead"
local timeOfDeath = 0
local transportDelay = 120
local isBleedingOut = false
local useDeathscreen = not Config.Deathscreen

local deadAnimDict = "dead"
local deadAnimName = "dead_a"
local lastStandAnimDict = "veh@low@front_ps@idle_duck"
local lastStandAnimName = "sit"
local lastVehicleCheck = 0

local function checkPlayerDeathState(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        -- continue
    else
        return false
    end

    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.dead == true or LocalPlayer.state.isDead == true or LocalPlayer.state.inlaststand == true then
            return true
        end
    end

    if IsPedDeadOrDying(ped, true) then
        return true
    end

    if IsPedRagdoll(ped) then
        return true
    end

    if IsEntityPlayingAnim(ped, deadAnimDict, deadAnimName, 3) then
        return true
    end

    if IsEntityPlayingAnim(ped, lastStandAnimDict, lastStandAnimName, 3) then
        return true
    end

    return false
end

local function handleDeathControls()
    local ped = PlayerPedId()
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then
        return
    end

    DisableAllControlActions(0)
    DisableControlAction(0, 73, true) -- X
    EnableControlAction(0, 1, true)   -- Look Left/Right
    EnableControlAction(0, 2, true)   -- Look Up/Down
    EnableControlAction(0, 245, true) -- T
    EnableControlAction(0, 246, true) -- Y (Transport)
    EnableControlAction(0, 47, true)  -- G (Call EMS)
    EnableControlAction(0, 199, true) -- P
    EnableControlAction(0, 200, true) -- ESC

    local currentTime = GetGameTimer()
    if currentTime >= lastVehicleCheck then
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleUndriveable(vehicle, true)
                SetVehicleEngineOn(vehicle, false, true, true)
                SetVehicleForwardSpeed(vehicle, 0.0)
                SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
            end
        end
        lastVehicleCheck = currentTime + 400
    end
end

local function toggleDeathScreen(show, time, mode)
    if not useDeathscreen then
        return
    end

    SendNUIMessage({
        action = "amb_toggleDeathScreen",
        show = show,
        time = time or 0,
        mode = mode or deathMode,
        transportDelay = transportDelay
    })
    
    SetNuiFocus(false, false)
end

local function getNearestHospitalBed()
    if not (DepartmentData and DepartmentData.nodes) then
        return nil
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    local closestBed = nil
    local minDistance = 999999.0

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "check_in" and node.coordsList and node.coordsList.bed and node.coordsList.bed.x then
            local bedCoords = vector3(node.coordsList.bed.x, node.coordsList.bed.y, node.coordsList.bed.z)
            local distance = #(pedCoords - bedCoords)
            if minDistance > distance then
                minDistance = distance
                closestBed = node.coordsList.bed
            end
        end
    end

    return closestBed
end

RegisterNetEvent("amb_client:onPlayerDeath", function()
    if not useDeathscreen then
        return
    end

    if isDead then
        return
    end

    isDead = true
    deathMode = "dead"
    emsCalled = false
    isBleedingOut = false

    deathTimer = tonumber(Config.Health.DeathTimer) or 300
    timeOfDeath = GetGameTimer()
    transportDelay = tonumber(Config.Health.HospitalTransportDelay) or 120

    toggleDeathScreen(true, deathTimer, deathMode)

    CreateThread(function()
        while isDead do
            Wait(1000)
            if deathTimer > 0 then
                deathTimer = deathTimer - 1
                SendNUIMessage({
                    action = "amb_updateDeathTimer",
                    time = deathTimer
                })
            else
                if not isBleedingOut then
                    isBleedingOut = true
                    TriggerServerEvent("amb_server:bleedOut")
                end
                SendNUIMessage({
                    action = "amb_updateDeathTimer",
                    time = 0
                })
            end
        end
    end)

    CreateThread(function()
        local callEMSTimer = Config.Health.CallEMSTimer or 60
        local checkStateTimer = 0
        local isGPressed = false
        local isYPressed = false

        while isDead do
            Wait(20)
            handleDeathControls()

            local currentTime = GetGameTimer()
            if checkStateTimer <= currentTime then
                if not checkPlayerDeathState(PlayerPedId()) then
                    isDead = false
                    emsCalled = false
                    isBleedingOut = false
                    deathMode = "dead"
                    toggleDeathScreen(false)
                    break
                end
                checkStateTimer = currentTime + 1000
            end

            local pressedG = IsDisabledControlPressed(0, 47)
            if pressedG and not isGPressed then
                isGPressed = true
                if not emsCalled then
                    local timeSinceDeath = (GetGameTimer() - timeOfDeath) / 1000
                    if callEMSTimer <= timeSinceDeath then
                        emsCalled = true
                        if SendDeathDispatch then
                            SendDeathDispatch()
                        end
                        Framework.Notify(_L("ems_notified"), "success")
                        SendNUIMessage({
                            action = "amb_emsCalled"
                        })
                    else
                        Framework.Notify(_L("wait_before_calling", { seconds = math.ceil(callEMSTimer - timeSinceDeath) }), "error")
                    end
                end
            elseif not pressedG then
                isGPressed = false
            end

            local pressedY = IsDisabledControlPressed(0, 246)
            if pressedY and not isYPressed then
                isYPressed = true
                local timeSinceDeath = (GetGameTimer() - timeOfDeath) / 1000
                if timeSinceDeath >= transportDelay then
                    local hospitalBed = getNearestHospitalBed()
                    if hospitalBed then
                        local ped = PlayerPedId()
                        SetEntityCoords(ped, hospitalBed.x, hospitalBed.y, hospitalBed.z, false, false, false, false)
                        SetEntityHeading(ped, hospitalBed.h or 0.0)
                        
                        exports.plt_ambulance_job:RevivePlayer()
                        
                        isDead = false
                        emsCalled = false
                        isBleedingOut = false
                        deathMode = "dead"
                        toggleDeathScreen(false)
                        
                        Framework.Notify(_L("transported_to_hospital"), "success")
                    else
                        Framework.Notify(_L("no_checkin_bed"), "error")
                    end
                else
                    local remainingTime = math.ceil(transportDelay - timeSinceDeath)
                    Framework.Notify(_L("transport_available_in", { seconds = remainingTime }), "error")
                end
            elseif not pressedY then
                isYPressed = false
            end
        end
    end)
end)

RegisterNetEvent("amb_client:onPlayerRevive", function()
    if not useDeathscreen then
        return
    end

    isDead = false
    emsCalled = false
    isBleedingOut = false
    deathMode = "dead"

    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleUndriveable(vehicle, false)
            end
        end
    end

    toggleDeathScreen(false)
end)

RegisterNUICallback("amb_callEMS", function(data, cb)
    if not useDeathscreen or not isDead or emsCalled then
        cb("ok")
        return
    end

    local callEMSTimer = Config.Health.CallEMSTimer or 60
    local timeSinceDeath = (GetGameTimer() - timeOfDeath) / 1000

    if callEMSTimer > timeSinceDeath then
        Framework.Notify(_L("wait_before_calling", { seconds = math.ceil(callEMSTimer - timeSinceDeath) }), "error")
        cb("ok")
        return
    end

    emsCalled = true
    if SendDeathDispatch then
        SendDeathDispatch()
    end
    Framework.Notify(_L("ems_notified"), "success")
    SendNUIMessage({
        action = "amb_emsCalled"
    })
    cb("ok")
end)

RegisterNUICallback("amb_goHospital", function(data, cb)
    if not useDeathscreen or not isDead then
        cb("ok")
        return
    end

    local timeSinceDeath = (GetGameTimer() - timeOfDeath) / 1000
    local remainingTime = math.ceil(math.max(0, transportDelay - timeSinceDeath))

    if remainingTime > 0 then
        SendNUIMessage({
            action = "amb_transportState",
            available = false,
            remaining = remainingTime
        })
        Framework.Notify(_L("transport_available_in", { seconds = remainingTime }), "error")
        cb("ok")
        return
    end

    local hospitalBed = getNearestHospitalBed()
    if not hospitalBed then
        Framework.Notify(_L("no_checkin_bed"), "error")
        cb("ok")
        return
    end

    local ped = PlayerPedId()
    SetEntityCoords(ped, hospitalBed.x, hospitalBed.y, hospitalBed.z, false, false, false, false)
    SetEntityHeading(ped, hospitalBed.h or 0.0)
    
    exports.plt_ambulance_job:RevivePlayer()
    
    isDead = false
    emsCalled = false
    isBleedingOut = false
    deathMode = "dead"
    toggleDeathScreen(false)
    
    Framework.Notify(_L("transported_to_hospital"), "success")
    cb("ok")
end)

CreateThread(function()
    while true do
        Wait(1000)
        if useDeathscreen and isDead then
            local timeSinceDeath = (GetGameTimer() - timeOfDeath) / 1000
            local remainingTime = math.ceil(math.max(0, transportDelay - timeSinceDeath))
            
            SendNUIMessage({
                action = "amb_transportState",
                available = (remainingTime <= 0),
                remaining = remainingTime
            })
        end
    end
end)

AddEventHandler("amb_client:SetDownedState", function(state)
    if not useDeathscreen then
        return
    end

    if state then
        TriggerEvent("amb_client:onPlayerDeath")
    else
        TriggerEvent("amb_client:onPlayerRevive")
    end
end)
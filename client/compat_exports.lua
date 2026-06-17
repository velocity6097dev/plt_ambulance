local isKnockoutDisabled = false
local isKnockoutLoopRunning = false
local currentDiagnosisData = nil
local isRadioMuted = false

local function GetClosestPlayer(maxRadius)
    local players = GetActivePlayers()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closestPlayer = nil
    local closestServerId = nil
    maxRadius = maxRadius or 3.0

    for _, player in ipairs(players) do
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            if DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                local distance = #(targetCoords - coords)
                if maxRadius >= distance then
                    maxRadius = distance
                    closestPlayer = targetPed
                    closestServerId = GetPlayerServerId(player)
                end
            end
        end
    end
    
    return closestPlayer, closestServerId, maxRadius
end

local function AwaitServerCallback(eventName, ...)
    local p = promise.new()
    Framework.TriggerCallback(eventName, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

local function RequestPlayerDiagnosis(targetSrc, timeout)
    targetSrc = tonumber(targetSrc)
    if not targetSrc then 
        return nil 
    end
    
    if currentDiagnosisData then 
        return nil 
    end

    local p = promise.new()
    currentDiagnosisData = { targetSrc = targetSrc, promise = p }

    TriggerServerEvent("amb_server:requestInjuries", targetSrc)

    CreateThread(function()
        Wait(timeout or 2500)
        if currentDiagnosisData and currentDiagnosisData.promise == p then
            currentDiagnosisData = nil
            p:resolve(nil)
        end
    end)

    local result = Citizen.Await(p)
    TriggerServerEvent("amb_server:stopDiagnosisSync", targetSrc)
    return result
end

local function GetClosestVehicleEx(radius)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    radius = radius or 6.0
    return GetClosestVehicle(coords.x, coords.y, coords.z, radius, 0, 71)
end

local function GetVehicleFreeSeat(vehicle)
    if not DoesEntityExist(vehicle) then 
        return nil 
    end
    
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for i = 0, maxSeats - 2, 1 do
        if IsVehicleSeatFree(vehicle, i) then
            return i
        end
    end
    
    return nil
end

RegisterNetEvent("amb_client:receiveDiagnosisData", function(data)
    if currentDiagnosisData then
        local p = currentDiagnosisData.promise
        currentDiagnosisData = nil
        p:resolve(data)
    end
end)

RegisterNetEvent("amb_client:compat:setKnockoutDisabled", function(isDisabled)
    isKnockoutDisabled = (true == isDisabled)
end)

RegisterNetEvent("amb_client:compat:manualKnockout", function(shouldKnockout)
    if shouldKnockout then
        if Framework and Framework.Type == "qb" then
            TriggerEvent("amb_client:SetDeathStatus", true)
        else
            TriggerEvent("hospital:client:SetDeathStatus", true)
        end
    else
        exports.plt_ambulance_job:RevivePlayer()
        TriggerServerEvent("amb_server:SetDowned", false)
    end
end)

RegisterNetEvent("amb_client:compat:applySedative", function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then 
        return 
    end
    SetPedToRagdoll(ped, 12000, 12000, 0, false, false, false)
end)

RegisterNetEvent("amb_client:compat:warpIntoVehicle", function(netId, seat)
    local vehicle = NetToVeh(netId)
    if DoesEntityExist(vehicle) and seat then
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seat)
    end
end)

RegisterNetEvent("amb_client:compat:loadOnStretcher", function(netId)
    local obj = NetToObj(netId)
    if not DoesEntityExist(obj) then 
        return 
    end
    
    local offset = Config.FernocotLieOffset or { x = 0.0, y = 0.0, z = 1.2 }
    local heading = Config.FernocotLieHeading or 0.0
    local anim = Config.FernocotLieAnim or { dict = "amb@world_human_sunbathe@male@back@base", name = "base" }

    Framework.RequestAnimDict(anim.dict)
    AttachEntityToEntity(PlayerPedId(), obj, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 180.0 + heading, false, false, false, false, 0, true)
    TaskPlayAnim(PlayerPedId(), anim.dict, anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
end)

exports("isPlayerDead", function(targetSrc)
    if not targetSrc then
        local ped = PlayerPedId()
        local isDead = IsPedDeadOrDying(ped, true)
        if not isDead then
            isDead = GetEntityHealth(ped) <= 120
        end
        return isDead
    end

    targetSrc = tonumber(targetSrc)
    if not targetSrc then 
        return false 
    end

    if targetSrc == GetPlayerServerId(PlayerId()) then
        local ped = PlayerPedId()
        local isDead = IsPedDeadOrDying(ped, true)
        if not isDead then
            isDead = GetEntityHealth(ped) <= 120
        end
        return isDead
    end

    return true == AwaitServerCallback("amb_server:isPlayerDowned", targetSrc)
end)

exports("diagnosePlayer", function(targetSrc)
    if targetSrc == nil then
        local closestPlayer, closestServerId, dist = GetClosestPlayer(3.0)
        if not closestPlayer then 
            return nil 
        end
        if StartDiagnosis then
            StartDiagnosis(closestPlayer)
            return true
        end
        return nil
    end

    if targetSrc == true then
        return RequestPlayerDiagnosis(GetPlayerServerId(PlayerId()))
    end

    targetSrc = tonumber(targetSrc)
    if not targetSrc then 
        return nil 
    end
    
    return RequestPlayerDiagnosis(targetSrc)
end)

exports("treatPatient", function(bodyPart)
    if not exports.plt_ambulance_job:IsEMS() then 
        return false 
    end

    local closestPlayer, closestServerId = GetClosestPlayer(3.0)
    if not closestPlayer or not closestServerId then 
        return false 
    end

    local injuries = {
        shot = "chest",
        stabbed = "left_arm",
        beat = "right_arm",
        burned = "chest"
    }

    bodyPart = tostring(bodyPart or ""):lower()
    local treatmentPart = injuries[bodyPart] or "chest"

    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    local success = Framework.ProgressBar(_L("progress_apply_treatment"), 5000)
    ClearPedTasks(PlayerPedId())

    if not success then 
        return false 
    end

    TriggerServerEvent("amb_server:HealPlayer", closestServerId, treatmentPart, 1)
    return true
end)

exports("reviveTarget", function()
    if not exports.plt_ambulance_job:IsEMS() then 
        return false 
    end

    local closestPlayer = GetClosestPlayer(3.0)
    if not closestPlayer then 
        return false 
    end

    if not RevivePlayerAction then 
        return false 
    end
    
    RevivePlayerAction(closestPlayer)
    return true
end)

exports("healTarget", function()
    local closestPlayer = nil
    if exports.plt_ambulance_job:IsEMS() then
        closestPlayer = GetClosestPlayer(3.0)
    end

    if closestPlayer then
        if OpenTreatmentMenu then
            OpenTreatmentMenu(closestPlayer)
            return true
        end
    end

    TriggerEvent("amb_client:useMedication", "plt_medkit")
    return true
end)

exports("useSedative", function()
    local closestPlayer, closestServerId = GetClosestPlayer(3.0)
    if not closestServerId then 
        return false 
    end

    TriggerServerEvent("amb_server:compat:sedateTarget", closestServerId)
    return true
end)

exports("placeInVehicle", function()
    local closestPlayer, closestServerId = GetClosestPlayer(4.0)
    if not closestServerId then 
        return false 
    end

    local vehicle = GetClosestVehicleEx(6.0)
    if not DoesEntityExist(vehicle) then 
        return false 
    end

    local freeSeat = GetVehicleFreeSeat(vehicle)
    if freeSeat == nil then 
        return false 
    end

    TriggerServerEvent("amb_server:compat:placeInVehicle", closestServerId, VehToNet(vehicle), freeSeat)
    return true
end)

exports("loadStretcher", function()
    local closestPlayer, closestServerId = GetClosestPlayer(3.0)
    if not closestServerId then 
        return false 
    end

    local model = GetHashKey(Config.FernocotModel or "fernocot")
    local coords = GetEntityCoords(PlayerPedId())
    local stretcher = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, model, false, false, false)

    if not stretcher or stretcher == 0 then 
        return false 
    end

    TriggerServerEvent("amb_server:compat:loadOnStretcher", closestServerId, ObjToNet(stretcher))
    return true
end)

exports("openOutfits", function()
    if GetResourceState("qb-clothing") == "started" then
        TriggerEvent("qb-clothing:client:openOutfitMenu")
        return true
    end
    if GetResourceState("illenium-appearance") == "started" then
        TriggerEvent("illenium-appearance:client:openOutfitMenu")
        return true
    end
    if GetResourceState("esx_skin") == "started" then
        TriggerEvent("esx_skin:openSaveableMenu")
        return true
    end
    if GetResourceState("origen_clothing") == "started" then
        TriggerEvent("origen_clothing:client:openOutfitMenu")
        TriggerEvent("origen_clothing:openOutfits")
        return true
    end
    if GetResourceState("rclothing") == "started" then
        TriggerEvent("rclothing:client:openOutfitMenu")
        TriggerEvent("rclothing:openOutfits")
        return true
    end
    return false
end)

exports("deleteStretcherFromVehicle", function(vehicle)
    if not (vehicle and DoesEntityExist(vehicle)) then
        vehicle = GetClosestVehicleEx(6.0)
    end

    if not vehicle or not DoesEntityExist(vehicle) then 
        return false 
    end

    local coords = GetEntityCoords(vehicle)
    local model = GetHashKey(Config.FernocotModel or "fernocot")
    local stretcher = GetClosestObjectOfType(coords.x, coords.y, coords.z, 7.0, model, false, false, false)

    if not stretcher or stretcher == 0 then 
        return false 
    end

    DeleteEntity(stretcher)
    return true
end)

exports("isPlayerUsingStretcher", function(playerId)
    playerId = tonumber(playerId)
    if playerId == nil then
        playerId = PlayerId()
    end

    local ped = GetPlayerPed(playerId)
    if DoesEntityExist(ped) and IsEntityAttached(ped) then
        local attachedEntity = GetEntityAttachedTo(ped)
        if DoesEntityExist(attachedEntity) then
            local model = GetHashKey(Config.FernocotModel or "fernocot")
            return GetEntityModel(attachedEntity) == model
        end
    end
    
    return false
end)

exports("clearPlayerInjury", function(resetVitals)
    exports.plt_ambulance_job:RevivePlayer()
    if resetVitals then
        TriggerServerEvent("amb_server:compat:resetVitals")
    end
    return true
end)

exports("disableKnockoutLoop", function(disable)
    isKnockoutDisabled = (true == disable)
    
    if isKnockoutLoopRunning then
        return isKnockoutDisabled
    end

    isKnockoutLoopRunning = true
    
    CreateThread(function()
        while true do
            if isKnockoutDisabled then
                local ped = PlayerPedId()
                local isDead = IsPedDeadOrDying(ped, true)
                if not isDead then
                    if GetEntityHealth(ped) <= 110 then
                        isDead = true
                    end
                end
                
                if isDead then
                    exports.plt_ambulance_job:RevivePlayer()
                    TriggerServerEvent("amb_server:SetDowned", false)
                    Wait(1500)
                end
                Wait(300)
            else
                Wait(1200)
            end
        end
    end)
    
    return isKnockoutDisabled
end)

exports("manuallyKnockout", function(shouldKnockout)
    if shouldKnockout then
        if Framework and Framework.Type == "qb" then
            TriggerEvent("amb_client:SetDeathStatus", true)
        else
            TriggerEvent("hospital:client:SetDeathStatus", true)
        end
        return true
    end

    exports.plt_ambulance_job:RevivePlayer()
    TriggerServerEvent("amb_server:SetDowned", false)
    return true
end)

local function isLocalPlayerDead()
    local ped = PlayerPedId()
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then 
        return false 
    end

    if LocalPlayer and LocalPlayer.state then
        local state = LocalPlayer.state
        if state.isDead == true or state.inlaststand == true or state.dead == true then
            return true
        end
    end

    local isDead = IsPedDeadOrDying(ped, true)
    if not isDead then
        return GetEntityHealth(ped) <= 120
    end
    
    return isDead
end

local function CheckAndMuteRadio()
    if not isLocalPlayerDead() then
        if LocalPlayer and LocalPlayer.state then
            LocalPlayer.state:set("radioMutedByDeath", false, true)
        end

        if isRadioMuted then
            pcall(function()
                MumbleSetPlayerMuted(PlayerId(), false)
            end)
            if GetResourceState("pma-voice") == "started" then
                pcall(function()
                    exports["pma-voice"]:setVoiceProperty("radioEnabled", true)
                end)
            end
            isRadioMuted = false
        end
        return false
    end

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("radioMutedByDeath", true, true)
    end

    pcall(function()
        MumbleSetPlayerMuted(PlayerId(), true)
    end)

    if GetResourceState("pma-voice") == "started" then
        pcall(function()
            exports["pma-voice"]:setRadioChannel(0)
        end)
        pcall(function()
            exports["pma-voice"]:setVoiceProperty("radioEnabled", false)
        end)
    end

    TriggerEvent("qb-radio:client:LeaveChannel")
    TriggerEvent("qb-radio:client:disconnect")
    TriggerEvent("qbx_radio:client:leaveChannel")
    TriggerEvent("esx_radio:leaveRadio")
    TriggerEvent("gcphone:removeRadio")
    TriggerEvent("tgiann-radio:client:CloseRadio")

    isRadioMuted = true
    return true
end

exports("ShouldForceRadioMute", function()
    return isLocalPlayerDead()
end)

exports("ForceMuteRadioIfDead", function()
    return CheckAndMuteRadio()
end)

CreateThread(function()
    while true do
        if CheckAndMuteRadio() then
            Wait(1000)
        else
            Wait(2000)
        end
    end
end)
local knockoutDisabled = false
local manualKnockoutActive = false
local diagnosisPromiseData = nil
local isRadioMuted = false

-- ==========================================
-- Utility Functions
-- ==========================================

function GetClosestPlayer(maxDistance)
    local players = GetActivePlayers()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closestDistance = maxDistance or 3.0
    local closestPlayerPed = nil
    local closestPlayerServerId = nil

    for _, playerId in ipairs(players) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            if DoesEntityExist(targetPed) then
                local dist = #(GetEntityCoords(targetPed) - coords)
                if dist <= closestDistance then
                    closestDistance = dist
                    closestPlayerPed = targetPed
                    closestPlayerServerId = GetPlayerServerId(playerId)
                end
            end
        end
    end
    return closestPlayerPed, closestPlayerServerId, closestDistance
end

function TriggerCallbackPromise(name, ...)
    local p = promise.new()
    Framework.TriggerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

function RequestInjuriesSync(targetSrc, timeout)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or diagnosisPromiseData then return nil end

    local p = promise.new()
    diagnosisPromiseData = { targetSrc = targetSrc, promise = p }
    TriggerServerEvent("amb_server:requestInjuries", targetSrc)

    CreateThread(function()
        Wait(timeout or 2500)
        if diagnosisPromiseData and diagnosisPromiseData.promise == p then
            diagnosisPromiseData = nil
            p:resolve(nil)
        end
    end)

    local result = Citizen.Await(p)
    TriggerServerEvent("amb_server:stopDiagnosisSync", targetSrc)
    return result
end

function GetClosestVehicleToPlayer(radius)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    return GetClosestVehicle(coords.x, coords.y, coords.z, radius or 6.0, 0, 71)
end

function GetVehicleFreeSeat(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for i = 0, maxSeats - 2 do
        if IsVehicleSeatFree(vehicle, i) then
            return i
        end
    end
    return nil
end

local function IsPlayerDeadLocal()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    
    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.isDead or LocalPlayer.state.inlaststand or LocalPlayer.state.dead then
            return true
        end
    end
    
    if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 120 then
        return true
    end
    return false
end

-- ==========================================
-- Net Events
-- ==========================================

RegisterNetEvent("amb_client:receiveDiagnosisData", function(data)
    if diagnosisPromiseData then
        local p = diagnosisPromiseData.promise
        diagnosisPromiseData = nil
        p:resolve(data)
    end
end)

RegisterNetEvent("amb_client:compat:setKnockoutDisabled", function(state)
    knockoutDisabled = (state == true)
end)

RegisterNetEvent("amb_client:compat:manualKnockout", function(state)
    if state then
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
    if IsPedInAnyVehicle(ped, false) then return end
    SetPedToRagdoll(ped, 12000, 12000, 0, false, false, false)
end)

RegisterNetEvent("amb_client:compat:warpIntoVehicle", function(netId, seat)
    local vehicle = NetToVeh(netId)
    if DoesEntityExist(vehicle) and seat then
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seat)
    end
end)

RegisterNetEvent("amb_client:compat:loadOnStretcher", function(netId)
    local stretcher = NetToObj(netId)
    if not DoesEntityExist(stretcher) then return end

    local lieOffset = Config.FernocotLieOffset or {x = 0.0, y = 0.0, z = 1.2}
    local lieHeading = Config.FernocotLieHeading or 0.0
    local lieAnim = Config.FernocotLieAnim or {dict = "amb@world_human_sunbathe@male@back@base", name = "base"}

    Framework.RequestAnimDict(lieAnim.dict)
    AttachEntityToEntity(PlayerPedId(), stretcher, 0, lieOffset.x, lieOffset.y, lieOffset.z, 0.0, 0.0, 180.0 + lieHeading, false, false, false, false, 0, true)
    TaskPlayAnim(PlayerPedId(), lieAnim.dict, lieAnim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
end)

-- ==========================================
-- Exports
-- ==========================================

exports("isPlayerDead", function(targetSrc)
    if not targetSrc then return IsPlayerDeadLocal() end
    targetSrc = tonumber(targetSrc)
    if not targetSrc then return false end

    if targetSrc == GetPlayerServerId(PlayerId()) then
        return IsPlayerDeadLocal()
    end
    return TriggerCallbackPromise("amb_server:isPlayerDowned", targetSrc) == true
end)

exports("diagnosePlayer", function(targetId)
    if targetId == nil then
        local targetPed, targetSrc = GetClosestPlayer(3.0)
        if targetPed then
            StartDiagnosis(targetPed)
            return true
        end
        return nil
    elseif targetId == true then
        return RequestInjuriesSync(GetPlayerServerId(PlayerId()))
    end
    
    local parsedId = tonumber(targetId)
    if not parsedId then return nil end
    return RequestInjuriesSync(parsedId)
end)

exports("treatPatient", function(injuryType)
    if not exports.plt_ambulance_job:IsEMS() then return false end

    local targetPed, targetSrc = GetClosestPlayer(3.0)
    if not targetPed or not targetSrc then return false end

    local injuryMap = {shot = "chest", stabbed = "left_arm", beat = "right_arm", burned = "chest"}
    local defaultInjury = injuryMap[tostring(injuryType or ""):lower()] or "chest"

    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    local success = Framework.ProgressBar(_L("progress_apply_treatment"), 5000)
    ClearPedTasks(PlayerPedId())

    if success then
        TriggerServerEvent("amb_server:HealPlayer", targetSrc, defaultInjury, 1)
        return true
    end
    return false
end)

exports("reviveTarget", function()
    if not exports.plt_ambulance_job:IsEMS() then return false end
    local targetPed, targetSrc = GetClosestPlayer(3.0)
    if not targetPed then return false end

    if RevivePlayerAction then
        RevivePlayerAction(targetPed)
        return true
    end
    return false
end)

exports("healTarget", function()
    local targetPed = nil
    if exports.plt_ambulance_job:IsEMS() then
        targetPed, _ = GetClosestPlayer(3.0)
    end
    if targetPed and OpenTreatmentMenu then
        OpenTreatmentMenu(targetPed)
        return true
    end
    TriggerEvent("amb_client:useMedication", "plt_medkit")
    return true
end)

exports("useSedative", function()
    local targetPed, targetSrc = GetClosestPlayer(3.0)
    if not targetSrc then return false end
    TriggerServerEvent("amb_server:compat:sedateTarget", targetSrc)
    return true
end)

exports("placeInVehicle", function()
    local targetPed, targetSrc = GetClosestPlayer(4.0)
    if not targetSrc then return false end

    local vehicle = GetClosestVehicleToPlayer(6.0)
    if not DoesEntityExist(vehicle) then return false end

    local seat = GetVehicleFreeSeat(vehicle)
    if seat == nil then return false end

    TriggerServerEvent("amb_server:compat:placeInVehicle", targetSrc, VehToNet(vehicle), seat)
    return true
end)

exports("loadStretcher", function()
    local targetPed, targetSrc = GetClosestPlayer(3.0)
    if not targetSrc then return false end

    local stretcherModel = GetHashKey(Config.FernocotModel or "fernocot")
    local coords = GetEntityCoords(PlayerPedId())
    local stretcher = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, stretcherModel, false, false, false)

    if not stretcher or stretcher == 0 then return false end

    TriggerServerEvent("amb_server:compat:loadOnStretcher", targetSrc, ObjToNet(stretcher))
    return true
end)

exports("openOutfits", function()
    local systems = {
        {"qb-clothing", "qb-clothing:client:openOutfitMenu"},
        {"illenium-appearance", "illenium-appearance:client:openOutfitMenu"},
        {"esx_skin", "esx_skin:openSaveableMenu"},
        {"origen_clothing", "origen_clothing:client:openOutfitMenu", "origen_clothing:openOutfits"},
        {"rclothing", "rclothing:client:openOutfitMenu", "rclothing:openOutfits"}
    }
    
    for _, sys in ipairs(systems) do
        if GetResourceState(sys[1]) == "started" then
            TriggerEvent(sys[2])
            if sys[3] then TriggerEvent(sys[3]) end
            return true
        end
    end
    return false
end)

-- Extra exports like `disableKnockoutLoop` and Radio handling
exports("disableKnockoutLoop", function(state)
    knockoutDisabled = (state == true)
    if manualKnockoutActive then return knockoutDisabled end
    
    manualKnockoutActive = true
    CreateThread(function()
        while true do
            if knockoutDisabled then
                local ped = PlayerPedId()
                if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 110 then
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
    return knockoutDisabled
end)

local function ForceMuteRadioIfDead()
    local isDead = IsPlayerDeadLocal()
    if not isDead then
        if LocalPlayer and LocalPlayer.state then
            LocalPlayer.state:set("radioMutedByDeath", false, true)
        end
        if isRadioMuted then
            pcall(function() MumbleSetPlayerMuted(PlayerId(), false) end)
            if GetResourceState("pma-voice") == "started" then
                pcall(function() exports["pma-voice"]:setVoiceProperty("radioEnabled", true) end)
            end
            isRadioMuted = false
        end
        return false
    end

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("radioMutedByDeath", true, true)
    end
    
    pcall(function() MumbleSetPlayerMuted(PlayerId(), true) end)
    if GetResourceState("pma-voice") == "started" then
        pcall(function() exports["pma-voice"]:setRadioChannel(0) end)
        pcall(function() exports["pma-voice"]:setVoiceProperty("radioEnabled", false) end)
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

exports("ShouldForceRadioMute", IsPlayerDeadLocal)
exports("ForceMuteRadioIfDead", ForceMuteRadioIfDead)

CreateThread(function()
    while true do
        if ForceMuteRadioIfDead() then Wait(1000) else Wait(2000) end
    end
end)
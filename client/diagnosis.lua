local isDiagnosing = false
local diagnosisCam = nil
local patientPed = nil
local patientServerId = nil
local patientInjuries = {}
local patientClothing = { top = true, bottom = true }
local _lastPart = nil
local _autoRefreshPart = nil

local bodyParts = {
    { name = "head", label = _L("body_head"), bone = 31086, ox = 0.0, oy = 0.0, oz = 0.03 },
    { name = "chest", label = _L("body_chest"), bone = 24817, ox = 0.0, oy = 0.0, oz = 0.0 },
    { name = "left_arm", label = _L("body_left_arm"), bone = 18905, ox = 0.0, oy = 0.0, oz = 0.0 },
    { name = "right_arm", label = _L("body_right_arm"), bone = 57005, ox = 0.0, oy = 0.0, oz = 0.0 },
    { name = "left_leg", label = _L("body_left_leg"), bone = 14201, ox = 0.0, oy = 0.0, oz = 0.02 },
    { name = "right_leg", label = _L("body_right_leg"), bone = 52301, ox = 0.0, oy = 0.0, oz = 0.02 }
}

local validParts = {
    head = true,
    chest = true,
    left_arm = true,
    right_arm = true,
    left_leg = true,
    right_leg = true
}

local function normalizePartName(part)
    if type(part) ~= "string" then return "chest" end
    local normalized = string.lower(part):gsub("%s+", "_")
    if validParts[normalized] then
        return normalized
    end
    return "chest"
end

local function ReopenDiagnosis(part)
    if not isDiagnosing or not patientPed then return end
    
    _autoRefreshPart = part
    
    Citizen.SetTimeout(500, function()
        if not isDiagnosing or not patientPed then return end
        
        TriggerServerEvent("amb_server:requestInjuries", patientServerId)
        
        local ped = PlayerPedId()
        Framework.RequestAnimDict("amb@medic@standing@kneel@base")
        if not IsEntityPlayingAnim(ped, "amb@medic@standing@kneel@base", "base", 3) then
            TaskPlayAnim(ped, "amb@medic@standing@kneel@base", "base", 8.0, -8.0, -1, 1, 1.0, false, false, false)
        end
        
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "amb_showDiagnosis"
        })
    end)
end

function StartDiagnosis(targetPed)
    if isDiagnosing then return end
    
    patientPed = targetPed
    patientServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(patientPed))
    
    if patientServerId == 0 then
        Framework.Notify(_L("diagnosis_no_patient_id"), "error")
        return
    end
    
    local ped = PlayerPedId()
    SetPedConfigFlag(ped, 184, true)
    
    Framework.RequestAnimDict("amb@medic@standing@kneel@base")
    TaskPlayAnim(ped, "amb@medic@standing@kneel@base", "base", 8.0, -8.0, -1, 1, 1.0, false, false, false)
    
    local topDrawable = GetPedDrawableVariation(patientPed, 11)
    local bottomDrawable = GetPedDrawableVariation(patientPed, 4)
    patientClothing.top = (topDrawable ~= 15)
    patientClothing.bottom = (bottomDrawable ~= 21)
    
    TriggerServerEvent("amb_server:requestInjuries", patientServerId)
    Framework.Notify(_L("diagnosis_preparing"), "info")
    
    local coords = GetEntityCoords(patientPed)
    diagnosisCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    
    local isDowned = IsPedDeadOrDying(patientPed, true) or IsPedRagdoll(patientPed) or GetEntityHealth(patientPed) <= 120 or IsEntityPlayingAnim(patientPed, "dead", "dead_a", 3) or IsEntityPlayingAnim(patientPed, "veh@low@front_ps@idle_duck", "sit", 3)
    
    if isDowned then
        SetCamCoord(diagnosisCam, coords.x, coords.y, coords.z + 0.85)
        SetCamRot(diagnosisCam, -90.0, 0.0, GetEntityHeading(patientPed) + 120.0)
    else
        local offset = GetOffsetFromEntityInWorldCoords(patientPed, 0.0, 1.5, 0.4)
        SetCamCoord(diagnosisCam, offset.x, offset.y, offset.z)
        PointCamAtEntity(diagnosisCam, patientPed, 0.0, 0.0, 0.2, true)
    end
    
    SetCamActive(diagnosisCam, true)
    RenderScriptCams(true, true, 1000, true, true)
    
    isDiagnosing = true
    SetNuiFocus(true, true)
    Wait(1000)
    
    if not next(patientInjuries) then
        print("^3[EMS DEBUG] No injury data received yet. Retrying request...^7")
        TriggerServerEvent("amb_server:requestInjuries", patientServerId)
    end
    
    CreateThread(function()
        while isDiagnosing do
            local dots = {}
            for _, part in ipairs(bodyParts) do
                local boneCoords = GetPedBoneCoords(patientPed, part.bone, part.ox or 0.0, part.oy or 0.0, part.oz or 0.0)
                local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(boneCoords.x, boneCoords.y, boneCoords.z)
                
                if onScreen then
                    local safeZone = GetSafeZoneSize()
                    local safeOffset = (1.0 - safeZone) * 0.5
                    
                    screenX = (screenX - safeOffset) / safeZone
                    screenY = (screenY - safeOffset) / safeZone
                    
                    if screenX < 0.0 then screenX = 0.0 elseif screenX > 1.0 then screenX = 1.0 end
                    if screenY < 0.0 then screenY = 0.0 elseif screenY > 1.0 then screenY = 1.0 end
                    
                    local partData = patientInjuries[part.name] or { level = 0, bullet = false, isFractured = false }
                    
                    table.insert(dots, {
                        name = part.name,
                        label = part.label,
                        x = screenX * 100,
                        y = screenY * 100,
                        hasHits = partData.level > 0,
                        hasBullet = partData.bullet == true,
                        isFractured = partData.isFractured == true
                    })
                end
            end
            
            SendNUIMessage({
                action = "amb_updateDiagnosisDots",
                dots = dots
            })
            
            Wait(33)
        end
    end)
end

RegisterNetEvent("amb_client:receiveDiagnosisData", function(data)
    if not isDiagnosing then return end
    
    print("^2[EMS DEBUG] Received Injury Data Sync for target^7")
    if data and data.head then
        print("^2[EMS DEBUG] Head level: " .. tostring(data.head.level) .. " Bullet: " .. tostring(data.head.bullet) .. "^7")
    end
    
    patientInjuries = data
    
    local isDowned = IsPedDeadOrDying(patientPed, true) or IsPedRagdoll(patientPed) or GetEntityHealth(patientPed) <= 120 or IsEntityPlayingAnim(patientPed, "dead", "dead_a", 3) or IsEntityPlayingAnim(patientPed, "veh@low@front_ps@idle_duck", "sit", 3)
    
    SendNUIMessage({
        action = "amb_openDiagnosisUI",
        injuries = data,
        isEMS = exports.plt_ambulance_job:IsEMS(),
        isDowned = isDowned
    })
    
    if _autoRefreshPart then
        print("^3[DEBUG] Auto-refreshing part: " .. tostring(_autoRefreshPart) .. "^7")
        SendNUIMessage({
            action = "amb_refreshDiagnosisPart",
            part = _autoRefreshPart
        })
        _autoRefreshPart = nil
    end
end)

RegisterNUICallback("closeDiagnosis", function(data, cb)
    isDiagnosing = false
    TriggerServerEvent("amb_server:stopDiagnosisSync")
    SetNuiFocus(false, false)
    RenderScriptCams(false, true, 1000, true, true)
    DestroyCam(diagnosisCam, false)
    
    diagnosisCam = nil
    patientPed = nil
    patientServerId = nil
    patientInjuries = {}
    _lastPart = nil
    _autoRefreshPart = nil
    
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetPedConfigFlag(ped, 184, false)
    ClearPedTasks(ped)
    
    cb("ok")
end)

exports("GetDiagnosisTarget", function()
    return patientServerId
end)

local function isPatientNeedsTreatment(data)
    local hasInjuries = false
    local validPartsCount = 0
    
    for k, v in pairs(data) do
        if type(v) == "table" and k ~= "bleeding" then
            validPartsCount = validPartsCount + 1
            if v.level > 0 or v.bullet or v.isFractured or v.hunger or v.needsFludro then
                hasInjuries = true
                break
            end
        end
    end
    
    return hasInjuries and validPartsCount > 0
end

local function getPrimaryTreatmentPart(data)
    if type(data) ~= "table" then return nil end
    
    local primaryPart = nil
    local highestSeverity = 0
    local bleedingSeverity = tonumber(data.bleeding) or 0
    
    local parts = {"head", "chest", "left_arm", "right_arm", "left_leg", "right_leg"}
    
    for _, part in ipairs(parts) do
        local partData = data[part]
        if type(partData) == "table" then
            local severity = (tonumber(partData.level) or 0) * 10
            
            if partData.bullet then severity = severity + 25 end
            if partData.isFractured then severity = severity + 20 end
            if partData.needsFludro then severity = severity + 15 end
            if partData.hunger then severity = severity + 12 end
            
            if bleedingSeverity > 0 then severity = severity + 5 end
            
            if part == "chest" and not partData.bullet and not partData.isFractured then
                if (tonumber(partData.level) or 0) <= 2 then
                    severity = severity - 8
                end
            end
            
            if severity > highestSeverity then
                highestSeverity = severity
                primaryPart = part
            end
        end
    end
    
    if highestSeverity <= 0 then return nil end
    return primaryPart
end

local function isTargetDowned(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        return IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or GetEntityHealth(ped) <= 120 or IsEntityPlayingAnim(ped, "dead", "dead_a", 3) or IsEntityPlayingAnim(ped, "veh@low@front_ps@idle_duck", "sit", 3)
    end
    return false
end

RegisterNUICallback("getPartDetail", function(data, cb)
    local part = data.part
    local partData = patientInjuries[part] or {
        level = 0, bullet = false, bandaged = false, hunger = false, needsFludro = false, isFractured = false, fractureTime = 0
    }
    
    local infoText = _L("diagnosis_no_significant")
    local needsClothingRemoval = false
    local clothingType = ""
    
    if part == "chest" or part == "left_arm" or part == "right_arm" then
        if patientClothing.top then
            needsClothingRemoval = true
            clothingType = _L("clothing_top")
        end
    elseif part == "left_leg" or part == "right_leg" then
        if patientClothing.bottom then
            needsClothingRemoval = true
            clothingType = _L("clothing_bottom")
        end
    end
    
    if partData.isFractured then
        local mins = math.floor(partData.fractureTime / 60)
        local secs = partData.fractureTime % 60
        infoText = _L("diagnosis_info_fracture", { mins = string.format("%02d", mins), secs = string.format("%02d", secs) })
    elseif partData.bullet then
        infoText = _L("diagnosis_info_bullet")
    elseif partData.needsFludro then
        infoText = _L("diagnosis_info_fludro")
    elseif partData.hunger then
        infoText = _L("diagnosis_info_hunger")
    elseif partData.level >= 5 then
        infoText = _L("diagnosis_info_level5")
    elseif partData.level >= 3 then
        infoText = _L("diagnosis_info_level3")
    elseif partData.level >= 1 then
        infoText = _L("diagnosis_info_level1")
    end
    
    if partData.bandaged then
        infoText = infoText .. " " .. _L("diagnosis_part_bandaged")
    end
    
    local targetDowned = isTargetDowned(patientPed)
    local primaryTreatmentPart = getPrimaryTreatmentPart(patientInjuries)
    local isPrimaryTreatmentPart = (primaryTreatmentPart == nil or primaryTreatmentPart == part)
    
    cb({
        label = part:gsub("_", " "):upper(),
        level = partData.level or 0,
        info = infoText,
        needsClothingRemoval = needsClothingRemoval,
        clothingType = clothingType,
        hasBullet = partData.bullet == true,
        isBandaged = partData.bandaged == true,
        isPatientBandaged = patientInjuries.isPatientBandaged == true,
        isHunger = partData.hunger == true,
        needsFludro = partData.needsFludro == true,
        isBleeding = (patientInjuries.bleeding or 0) > 0,
        isFractured = partData.isFractured == true,
        primaryTreatmentPart = primaryTreatmentPart,
        isPrimaryTreatmentPart = isPrimaryTreatmentPart,
        targetDowned = targetDowned,
        canRevive = targetDowned
    })
end)

RegisterNUICallback("startTreatment", function(data, cb)
    local part = data.part
    local treatType = data.type
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(patientPed))
    
    if treatType == "bullet" or treatType == "heal" then
        local needsRemoval = false
        local cType = ""
        
        if part == "chest" or part == "left_arm" or part == "right_arm" then
            if patientClothing.top then
                needsRemoval = true
                cType = "TOP"
            end
        elseif part == "left_leg" or part == "right_leg" then
            if patientClothing.bottom then
                needsRemoval = true
                cType = "BOTTOM"
            end
        end
        
        if needsRemoval then
            local actionText = treatType == "bullet" and _L("diagnosis_action_surgery") or _L("diagnosis_action_treatment")
            Framework.Notify(_L("diagnosis_remove_clothing", { clothingType = cType, action = actionText }), "error")
            cb("ok")
            return
        end
    end
    
    local reqItem = "plt_medkit"
    if treatType == "bullet" or treatType == "clamp" then
        reqItem = "plt_surgical_kit"
    elseif treatType == "bp" then
        reqItem = "plt_bp_monitor"
    end
    
    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if not hasItem then
            local itemName = _L("diagnosis_item_supplies")
            if reqItem == "plt_medkit" then itemName = _L("item_medkit")
            elseif reqItem == "plt_surgical_kit" then itemName = _L("item_surgical_kit")
            elseif reqItem == "plt_bp_monitor" then itemName = _L("item_bp_monitor") end
            
            Framework.Notify(_L("diagnosis_need_item", { item = itemName }), "error")
            return
        end
        
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "amb_hideDiagnosis" })
        
        if treatType == "bp" then
            TriggerEvent("amb_client:startBPMinigame", targetSrc, part)
        elseif treatType == "clamp" then
            TriggerEvent("amb_client:startClampMinigame", targetSrc, part)
        elseif treatType == "bullet" then
            TriggerEvent("amb_client:startBulletMinigame", targetSrc, part)
        elseif treatType == "fludro" then
            TriggerEvent("amb_client:giveFludroTreatment", targetSrc, part)
        else
            TriggerEvent("amb_client:startSutureMinigame", targetSrc, part)
        end
    end, reqItem)
    
    cb("ok")
end)

RegisterNetEvent("amb_client:startSutureMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({
        action = "amb_startSutureMinigame",
        targetSrc = targetSrc,
        part = part
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("sutureMinigameResult", function(data, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
    
    if data.success then
        TriggerServerEvent("amb_server:HealPlayer", data.targetSrc, data.part, 1)
        Framework.Notify(_L("diagnosis_wound_treated"), "success")
    end
    
    ReopenDiagnosis(data.part)
    cb("ok")
end)

RegisterNetEvent("amb_client:giveFludroTreatment", function(targetSrc, part)
    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    
    if Framework.ProgressBar(_L("diagnosis_progress_fludro"), 5000) then
        ClearPedTasks(ped)
        TriggerServerEvent("amb_server:giveFludro", targetSrc)
    else
        ClearPedTasks(ped)
    end
    
    ReopenDiagnosis(part)
end)

RegisterNUICallback("bpMinigameResult", function(data, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
    
    if data.success then
        Framework.Notify(_L("diagnosis_bp_stable"), "success")
        if patientInjuries.right_arm then
            patientInjuries.right_arm.level = 0
            patientInjuries.right_arm.hunger = false
        end
        if not patientInjuries.head then
            patientInjuries.head = { level = 0, bullet = false, bandaged = false }
        end
        patientInjuries.head.level = 1
        patientInjuries.head.needsFludro = true
        
        TriggerServerEvent("amb_server:updateHungerWorkflow", data.targetSrc)
    end
    
    ReopenDiagnosis(data.part)
    cb("ok")
end)

RegisterNetEvent("amb_client:startBPMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({
        action = "amb_startBPMinigame",
        targetSrc = targetSrc,
        part = part
    })
    SetNuiFocus(true, true)
end)

RegisterNetEvent("amb_client:startClampMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({
        action = "amb_startClampMinigame",
        targetSrc = targetSrc,
        part = part
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("clampMinigameResult", function(data, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
    
    if data.success then
        TriggerServerEvent("amb_server:ClampBleeding", data.targetSrc)
        Framework.Notify(_L("diagnosis_bleeding_clamped"), "success")
    end
    
    ReopenDiagnosis(data.part)
    cb("ok")
end)

RegisterNUICallback("applyBandage", function(data, cb)
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(patientPed))
    
    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if not hasItem then
            Framework.Notify(_L("diagnosis_need_bandage"), "error")
            return
        end
        
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "amb_hideDiagnosis" })
        TriggerEvent("amb_client:startBandageMinigame", targetSrc, data.part)
    end, "plt_bandage")
    
    cb("ok")
end)

RegisterNetEvent("amb_client:startBandageMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({
        action = "amb_startBandageMinigame",
        targetSrc = targetSrc,
        part = part
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("bandageMinigameResult", function(data, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
    
    local targetSrc = data and tonumber(data.targetSrc) or patientServerId
    local part = normalizePartName(data and data.part)
    
    if data.success and targetSrc then
        TriggerServerEvent("amb_server:applyBandage", targetSrc, part)
        Framework.Notify(_L("diagnosis_bandage_applied"), "success")
    end
    
    ReopenDiagnosis(part)
    cb("ok")
end)

RegisterCommand("bandageminigame", function(source, args)
    local part = normalizePartName(args and args[1])
    local targetId = tonumber(args and args[2]) or GetPlayerServerId(PlayerId())
    TriggerEvent("amb_client:startBandageMinigame", targetId, part)
    Framework.Notify(string.format("Bandage minigame started (%s).", part), "info")
end, false)

RegisterNetEvent("amb_client:startBulletMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({
        action = "amb_startBulletMinigame",
        targetSrc = targetSrc,
        part = part
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("bulletMinigameResult", function(data, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
    
    if data.success then
        TriggerServerEvent("amb_server:HealPlayer", data.targetSrc, data.part, 2)
        Framework.Notify(_L("diagnosis_bullet_extracted"), "success")
    end
    
    ReopenDiagnosis(data.part)
    cb("ok")
end)

RegisterNUICallback("performCPR", function(data, cb)
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(patientPed))
    
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "amb_hideDiagnosis" })
    
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    
    local targetHeading = GetEntityHeading(patientPed)
    local targetCoords = GetOffsetFromEntityInWorldCoords(patientPed, -0.7196, -0.2604, 0.0003)
    
    local foundGround, groundZ = GetGroundZFor_3dCoord(targetCoords.x, targetCoords.y, targetCoords.z + 1.0, false)
    if foundGround then
        targetCoords = vector3(targetCoords.x, targetCoords.y, groundZ)
    end
    
    SetEntityCoords(ped, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false, true)
    SetEntityHeading(ped, targetHeading - 90.0)
    
    TriggerServerEvent("amb_server:startCombinedCPR", targetSrc)
    
    SetPedConfigFlag(ped, 184, true)
    FreezeEntityPosition(ped, true)
    
    if Framework.ProgressBar("Performing CPR", 20000) then
        TriggerServerEvent("amb_server:finishCPR", targetSrc)
        Framework.Notify(_L("diagnosis_cpr_success"), "success")
        
        isDiagnosing = false
        SetPedConfigFlag(ped, 184, false)
        ClearPedTasks(ped)
        RenderScriptCams(false, true, 300, true, true)
        
        if diagnosisCam then
            DestroyCam(diagnosisCam, false)
            diagnosisCam = nil
        end
        
        FreezeEntityPosition(ped, false)
        patientPed = nil
        patientServerId = nil
    else
        TriggerServerEvent("amb_server:stopCombinedCPR", targetSrc)
        ClearPedTasks(ped)
        ReopenDiagnosis()
    end
    
    cb("ok")
end)

RegisterNUICallback("removePatientClothes", function(data, cb)
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(patientPed))
    
    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if not hasItem then
            Framework.Notify(_L("diagnosis_need_scissors"), "error")
            return
        end
        
        if data.type == "TOP" then
            patientClothing.top = false
            TriggerServerEvent("amb_server:removeClothes", targetSrc, "top")
        else
            patientClothing.bottom = false
            TriggerServerEvent("amb_server:removeClothes", targetSrc, "bottom")
        end
        
        ReopenDiagnosis(data.part)
    end, "plt_surgical_scissors")
    
    cb("ok")
end)
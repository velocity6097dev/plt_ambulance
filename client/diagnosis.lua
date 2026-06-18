-- ============================================================
-- diagnosis.lua  –  EMS / Ambulance Diagnosis System (Client)
-- ============================================================

-- ── Module-level state ──────────────────────────────────────
local isDiagnosisActive = false   -- true while a diagnosis session is open
local targetPed         = nil     -- the ped being examined
local targetServerId    = nil     -- server-id of the patient
local injuryData        = {}      -- injury table received from server
local clothingState     = { top = true, bottom = true }  -- whether clothing is still on
local scriptCam         = nil     -- handle for the cinematic script camera
local pendingRefreshPart = nil    -- body part that needs an auto-refresh

-- ── Body-part definitions ────────────────────────────────────
-- Each entry maps a logical part name to its ped bone and
-- a small world-space offset used when projecting to screen.
local bodyParts = {
    {
        name  = "head",
        label = _L("body_head"),
        bone  = 31086,
        ox = 0.0, oy = 0.0, oz = 0.03,
    },
    {
        name  = "chest",
        label = _L("body_chest"),
        bone  = 24817,
        ox = 0.0, oy = 0.0, oz = 0.0,
    },
    {
        name  = "left_arm",
        label = _L("body_left_arm"),
        bone  = 18905,
        ox = 0.0, oy = 0.0, oz = 0.0,
    },
    {
        name  = "right_arm",
        label = _L("body_right_arm"),
        bone  = 57005,
        ox = 0.0, oy = 0.0, oz = 0.0,
    },
    {
        name  = "left_leg",
        label = _L("body_left_leg"),
        bone  = 14201,
        ox = 0.0, oy = 0.0, oz = 0.02,
    },
    {
        name  = "right_leg",
        label = _L("body_right_leg"),
        bone  = 52301,
        ox = 0.0, oy = 0.0, oz = 0.02,
    },
}

-- Lookup set for fast "is this a valid part?" checks.
local validParts = {
    head      = true,
    chest     = true,
    left_arm  = true,
    right_arm = true,
    left_leg  = true,
    right_leg = true,
}


-- ── Helper: normalise a raw part name ───────────────────────
-- Converts any string to lowercase-with-underscores; returns
-- "chest" as a safe fallback for unknown / non-string input.
local function normalisePart(raw)
    if type(raw) ~= "string" then
        return "chest"
    end
    local normalised = string.lower(raw):gsub("%s+", "_")
    if validParts[normalised] then
        return normalised
    end
    return "chest"
end


-- ── Helper: decide whether a ped is downed ──────────────────
-- Returns true when the ped is dead, ragdolled, playing a death
-- animation, or in a low vehicle-seat duck pose (≤120 health).
local function isPedDowned(ped)
    if not ped or ped == 0 then
        return false
    end
    if not DoesEntityExist(ped) then
        return false
    end

    if IsPedDeadOrDying(ped, true) then
        return true
    end

    if IsPedRagdoll(ped) then
        return true
    end

    -- Low health while sitting in a ducked-seat animation counts as downed.
    local health = GetEntityHealth(ped)
    if IsEntityPlayingAnim(ped, "dead", "dead_a", 3) then
        return true
    end

    -- health <= 120 **or** sitting-duck anim
    return health <= 120 or IsEntityPlayingAnim(ped, "veh@low@front_ps@idle_duck", "sit", 3)
end


-- ── Helper: refresh diagnosis UI for one part ───────────────
-- Called after a treatment completes so the NUI panel updates.
local function refreshDiagnosisPart(part)
    if not isDiagnosisActive then return end
    if not targetPed     then return end

    pendingRefreshPart = part

    Citizen.SetTimeout(500, function()
        if not isDiagnosisActive then return end
        if not targetPed     then return end

        TriggerServerEvent("amb_server:requestInjuries", targetServerId)

        local myPed = PlayerPedId()
        Framework.RequestAnimDict("amb@medic@standing@kneel@base")

        if not IsEntityPlayingAnim(myPed, "amb@medic@standing@kneel@base", "base", 3) then
            TaskPlayAnim(myPed,
                "amb@medic@standing@kneel@base", "base",
                8.0, -8.0, -1, 1, 1.0,
                false, false, false)
        end

        SetNuiFocus(true, true)
        SendNUIMessage({ action = "amb_showDiagnosis" })
    end)
end


-- ── StartDiagnosis ──────────────────────────────────────────
-- Main entry point – called externally (e.g. from interaction
-- menu) with the ped the medic wants to examine.
local function StartDiagnosis(ped)
    if isDiagnosisActive then return end

    targetPed = ped

    -- Resolve server id; bail out if we can't find one.
    targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    if targetServerId == 0 then
        Framework.Notify(_L("diagnosis_no_patient_id"), "error")
        return
    end

    local myPed = PlayerPedId()

    -- Play kneeling animation on the medic.
    SetPedConfigFlag(myPed, 184, true)
    Framework.RequestAnimDict("amb@medic@standing@kneel@base")
    TaskPlayAnim(myPed,
        "amb@medic@standing@kneel@base", "base",
        8.0, -8.0, -1, 1, 1.0,
        false, false, false)

    -- Detect whether the patient is clothed (drawable 15 = no top,
    -- drawable 21 = no bottom in standard male peds).
    local topDrawable    = GetPedDrawableVariation(ped, 11)
    local bottomDrawable = GetPedDrawableVariation(ped, 4)
    clothingState.top    = (topDrawable    ~= 15)
    clothingState.bottom = (bottomDrawable ~= 21)

    -- Ask server for injury data.
    TriggerServerEvent("amb_server:requestInjuries", targetServerId)
    Framework.Notify(_L("diagnosis_preparing"), "info")

    -- Set up the cinematic camera aimed at the patient.
    local patientCoords = GetEntityCoords(ped)
    scriptCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    local downed = isPedDowned(ped)

    if downed then
        -- Top-down view for a prone / dead patient.
        SetCamCoord(scriptCam,
            patientCoords.x,
            patientCoords.y,
            patientCoords.z + 0.85)
        SetCamRot(scriptCam,
            -90.0, 0.0,
            GetEntityHeading(ped) + 120.0)
    else
        -- Slightly in front of the patient, pointed at the torso.
        local camPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.5, 0.4)
        SetCamCoord(scriptCam, camPos.x, camPos.y, camPos.z)
        PointCamAtEntity(scriptCam, ped, 0.0, 0.0, 0.2, true)
    end

    SetCamActive(scriptCam, true)
    RenderScriptCams(true, true, 1000, true, true)

    isDiagnosisActive = true
    SetNuiFocus(true, true)

    Wait(1000)

    -- If no injury data arrived yet, retry once.
    if not next(injuryData) then
        print("^3[EMS DEBUG] No injury data received yet. Retrying request...^7")
        TriggerServerEvent("amb_server:requestInjuries", targetServerId)
    end

    -- Every ~33 ms project each bone to screen space and push
    -- the dot positions to the NUI overlay.
    CreateThread(function()
        while isDiagnosisActive do
            local dots = {}

            for _, part in ipairs(bodyParts) do
                local boneCoords = GetPedBoneCoords(
                    targetPed,
                    part.bone,
                    part.ox or 0.0,
                    part.oy or 0.0,
                    part.oz or 0.0)

                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                    boneCoords.x, boneCoords.y, boneCoords.z)

                if onScreen then
                    -- Remap coords into the safe-zone-normalised 0-1 space.
                    local safeZone = GetSafeZoneSize()
                    local margin   = (1.0 - safeZone) * 0.5
                    sx = math.max(0.0, math.min(1.0, (sx - margin) / safeZone))
                    sy = math.max(0.0, math.min(1.0, (sy - margin) / safeZone))

                    local info = injuryData[part.name] or {
                        level      = 0,
                        bullet     = false,
                        isFractured = false,
                    }

                    table.insert(dots, {
                        name        = part.name,
                        label       = part.label,
                        x           = sx * 100,
                        y           = sy * 100,
                        hasHits     = info.level > 0,
                        hasBullet   = info.bullet == true,
                        isFractured = info.isFractured == true,
                    })
                end
            end

            SendNUIMessage({ action = "amb_updateDiagnosisDots", dots = dots })
            Wait(33)
        end
    end)
end

-- Expose to other client scripts.
StartDiagnosis = StartDiagnosis
exports("StartDiagnosis", function() return targetServerId end)


-- ── GetDiagnosisTarget export ────────────────────────────────
exports("GetDiagnosisTarget", function()
    return targetServerId
end)


-- ── NET: receive updated injury data from server ─────────────
RegisterNetEvent("amb_client:receiveDiagnosisData")
AddEventHandler("amb_client:receiveDiagnosisData", function(data)
    if not isDiagnosisActive then return end

    print("^2[EMS DEBUG] Received Injury Data Sync for target^7")

    if data and data.head then
        print("^2[EMS DEBUG] Head level: "
            .. tostring(data.head.level)
            .. " Bullet: "
            .. tostring(data.head.bullet)
            .. "^7")
    end

    injuryData = data

    local msg = {
        action   = "amb_openDiagnosisUI",
        injuries = data,
        isEMS    = exports.plt_ambulance_job:IsEMS(),
        isDowned = isPedDowned(targetPed),
    }
    SendNUIMessage(msg)

    -- Auto-refresh the part panel if a treatment just completed.
    if pendingRefreshPart then
        print("^3[DEBUG] Auto-refreshing part: " .. tostring(pendingRefreshPart) .. "^7")
        SendNUIMessage({ action = "amb_refreshDiagnosisPart", part = pendingRefreshPart })
        pendingRefreshPart = nil
    end
end)


-- ── NUI: close the diagnosis UI ─────────────────────────────
RegisterNUICallback("closeDiagnosis", function(_, cb)
    isDiagnosisActive = false

    TriggerServerEvent("amb_server:stopDiagnosisSync")
    SetNuiFocus(false, false)

    RenderScriptCams(false, true, 1000, true, true)
    if scriptCam then
        DestroyCam(scriptCam, false)
        scriptCam = nil
    end

    targetPed      = nil
    targetServerId = nil
    injuryData     = {}

    local myPed = PlayerPedId()
    FreezeEntityPosition(myPed, false)
    SetPedConfigFlag(myPed, 184, false)
    ClearPedTasks(myPed)

    cb("ok")
end)


-- ── Pure logic: are all injuries resolved? ──────────────────
-- Returns true when every body-part entry in the data table has
-- no active injury flags AND at least one part was present.
local function areAllInjuriesResolved(data)
    local allClear  = true
    local partCount = 0

    for key, value in pairs(data) do
        if type(value) == "table" and key ~= "bleeding" then
            partCount = partCount + 1
            if value.level > 0
                or value.bullet
                or value.isFractured
                or value.hunger
                or value.needsFludro
            then
                allClear = false
                break
            end
        end
    end

    return allClear and partCount > 0
end


-- ── Pure logic: find the highest-priority treatment part ─────
-- Scores each body part by injury severity and returns the name
-- of the part that most urgently needs treatment, or nil if
-- no injuries are present.
local function getPrimaryTreatmentPart(data)
    if type(data) ~= "table" then return nil end

    local bestPart  = nil
    local bestScore = 0

    local bleeding = tonumber(data.bleeding) or 0

    local partOrder = { "head", "chest", "left_arm", "right_arm", "left_leg", "right_leg" }

    for _, partName in ipairs(partOrder) do
        local info = data[partName]
        if type(info) == "table" then
            local score = (tonumber(info.level) or 0) * 10

            if info.bullet      then score = score + 25 end
            if info.isFractured then score = score + 20 end
            if info.needsFludro then score = score + 15 end
            if info.hunger      then score = score + 12 end
            if bleeding > 0     then score = score + 5  end

            -- Minor chest wounds are slightly de-prioritised so the
            -- player focuses on other, more critical injuries first.
            if partName == "chest"
                and not info.bullet
                and not info.isFractured
                and (tonumber(info.level) or 0) <= 2
            then
                score = score - 8
            end

            if score > bestScore then
                bestScore = score
                bestPart  = partName
            end
        end
    end

    if bestScore <= 0 then return nil end
    return bestPart
end


-- ── NUI: request detail for a single body part ──────────────
RegisterNUICallback("getPartDetail", function(data, cb)
    local partName = data.part
    local info     = injuryData[partName] or {
        level       = 0,
        bullet      = false,
        bandaged    = false,
        hunger      = false,
        needsFludro = false,
        isFractured = false,
        fractureTime = 0,
    }

    -- Build the primary info string (most severe condition wins).
    local infoText = _L("diagnosis_no_significant")

    if info.isFractured then
        local mins = math.floor(info.fractureTime / 60)
        local secs = info.fractureTime % 60
        infoText = _L("diagnosis_info_fracture", {
            mins = string.format("%02d", mins),
            secs = string.format("%02d", secs),
        })
    elseif info.bullet      then infoText = _L("diagnosis_info_bullet")
    elseif info.needsFludro then infoText = _L("diagnosis_info_fludro")
    elseif info.hunger      then infoText = _L("diagnosis_info_hunger")
    elseif info.level >= 5  then infoText = _L("diagnosis_info_level5")
    elseif info.level >= 3  then infoText = _L("diagnosis_info_level3")
    elseif info.level >= 1  then infoText = _L("diagnosis_info_level1")
    end

    if info.bandaged then
        infoText = infoText .. " " .. _L("diagnosis_part_bandaged")
    end

    -- Check whether clothing must be removed to treat this part.
    local needsClothingRemoval = false
    local clothingType         = ""

    if partName == "chest" or partName == "left_arm" or partName == "right_arm" then
        if clothingState.top then
            needsClothingRemoval = true
            clothingType         = _L("clothing_top")
        end
    elseif partName == "left_leg" or partName == "right_leg" then
        if clothingState.bottom then
            needsClothingRemoval = true
            clothingType         = _L("clothing_bottom")
        end
    end

    local downed           = isPedDowned(targetPed)
    local primaryPart      = getPrimaryTreatmentPart(injuryData)
    local isPrimaryForThis = (primaryPart == nil) or (partName == primaryPart)

    -- Produce a display label: "left_arm" → "LEFT ARM"
    local displayLabel = string.upper(partName:gsub("_", " "))

    cb({
        label                = displayLabel,
        level                = info.level or 0,
        info                 = infoText,
        needsClothingRemoval = needsClothingRemoval,
        clothingType         = clothingType,
        hasBullet            = info.bullet      == true,
        isBandaged           = info.bandaged    == true,
        isPatientBandaged    = injuryData.isPatientBandaged == true,
        isHunger             = info.hunger      == true,
        needsFludro          = info.needsFludro == true,
        isBleeding           = (injuryData.bleeding or 0) > 0,
        isFractured          = info.isFractured == true,
        primaryTreatmentPart = primaryPart,
        isPrimaryTreatmentPart = isPrimaryForThis,
        targetDowned         = downed,
        canRevive            = downed,
    })
end)


-- ── NUI: start treatment for a body part ────────────────────
RegisterNUICallback("startTreatment", function(data, cb)
    local partName         = data.part
    local treatmentType    = data.type
    local patientServerId  = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))

    -- For bullet or general heal, clothing must be removed first.
    if treatmentType == "bullet" or treatmentType == "heal" then
        local clothed, clothingCategory = false, ""

        if partName == "chest" or partName == "left_arm" or partName == "right_arm" then
            if clothingState.top then
                clothed = true
                clothingCategory = "TOP"
            end
        elseif partName == "left_leg" or partName == "right_leg" then
            if clothingState.bottom then
                clothed = true
                clothingCategory = "BOTTOM"
            end
        end

        if clothed then
            local actionLabel = (treatmentType == "bullet")
                and _L("diagnosis_action_surgery")
                or  _L("diagnosis_action_treatment")

            Framework.Notify(
                _L("diagnosis_remove_clothing", {
                    clothingType = clothingCategory,
                    action       = actionLabel,
                }),
                "error"
            )
            cb("ok")
            return
        end
    end

    -- Pick the required item for this treatment type.
    local requiredItem = "plt_medkit"
    if treatmentType == "bullet" or treatmentType == "clamp" then
        requiredItem = "plt_surgical_kit"
    elseif treatmentType == "bp" then
        requiredItem = "plt_bp_monitor"
    end

    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if not hasItem then
            -- Tell the player which item they're missing.
            local itemLabel = _L("diagnosis_item_supplies")
            if     requiredItem == "plt_medkit"       then itemLabel = _L("item_medkit")
            elseif requiredItem == "plt_surgical_kit" then itemLabel = _L("item_surgical_kit")
            elseif requiredItem == "plt_bp_monitor"   then itemLabel = _L("item_bp_monitor")
            end
            Framework.Notify(_L("diagnosis_need_item", { item = itemLabel }), "error")
            return
        end

        SetNuiFocus(false, false)
        SendNUIMessage({ action = "amb_hideDiagnosis" })

        -- Dispatch to the appropriate mini-game event.
        if     treatmentType == "bp"     then TriggerEvent("amb_client:startBPMinigame",     patientServerId, partName)
        elseif treatmentType == "clamp"  then TriggerEvent("amb_client:startClampMinigame",  patientServerId, partName)
        elseif treatmentType == "bullet" then TriggerEvent("amb_client:startBulletMinigame", patientServerId, partName)
        elseif treatmentType == "fludro" then TriggerEvent("amb_client:giveFludroTreatment", patientServerId, partName)
        else                                  TriggerEvent("amb_client:startSutureMinigame", patientServerId, partName)
        end
    end, requiredItem)

    cb("ok")
end)


-- ════════════════════════════════════════════════════════════
--  Mini-game starters and result handlers
-- ════════════════════════════════════════════════════════════

-- ── Suture mini-game ─────────────────────────────────────────
RegisterNetEvent("amb_client:startSutureMinigame")
AddEventHandler("amb_client:startSutureMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({ action = "amb_startSutureMinigame", targetSrc = targetSrc, part = part })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("sutureMinigameResult", function(result, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())

    if result.success then
        TriggerServerEvent("amb_server:HealPlayer", result.targetSrc, result.part, 1)
        Framework.Notify(_L("diagnosis_wound_treated"), "success")
    end

    refreshDiagnosisPart(result.part)
    cb("ok")
end)


-- ── Fludro treatment (progress bar, no mini-game) ────────────
RegisterNetEvent("amb_client:giveFludroTreatment")
AddEventHandler("amb_client:giveFludroTreatment", function(targetSrc, part)
    local myPed = PlayerPedId()
    TaskStartScenarioInPlace(myPed, "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)

    local completed = Framework.ProgressBar(_L("diagnosis_progress_fludro"), 5000)
    ClearPedTasks(myPed)

    if completed then
        TriggerServerEvent("amb_server:giveFludro", targetSrc)
    end

    refreshDiagnosisPart(part)
end)


-- ── Blood-pressure mini-game ─────────────────────────────────
RegisterNetEvent("amb_client:startBPMinigame")
AddEventHandler("amb_client:startBPMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({ action = "amb_startBPMinigame", targetSrc = targetSrc, part = part })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("bpMinigameResult", function(result, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())

    if result.success then
        Framework.Notify(_L("diagnosis_bp_stable"), "success")

        -- Clear hunger flag on the right arm after stabilising BP.
        if injuryData.right_arm then
            injuryData.right_arm.level  = 0
            injuryData.right_arm.hunger = false
        end

        -- Mark that the head now needs a fludro top-up.
        injuryData.head = injuryData.head or { level = 0, bullet = false, bandaged = false }
        injuryData.head.level      = 1
        injuryData.head.needsFludro = true

        TriggerServerEvent("amb_server:updateHungerWorkflow", result.targetSrc)
    end

    refreshDiagnosisPart(result.part)
    cb("ok")
end)


-- ── Clamp mini-game (bleeding) ───────────────────────────────
RegisterNetEvent("amb_client:startClampMinigame")
AddEventHandler("amb_client:startClampMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({ action = "amb_startClampMinigame", targetSrc = targetSrc, part = part })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("clampMinigameResult", function(result, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())

    if result.success then
        TriggerServerEvent("amb_server:ClampBleeding", result.targetSrc)
        Framework.Notify(_L("diagnosis_bleeding_clamped"), "success")
    end

    refreshDiagnosisPart(result.part)
    cb("ok")
end)


-- ── Bullet-extraction mini-game ──────────────────────────────
RegisterNetEvent("amb_client:startBulletMinigame")
AddEventHandler("amb_client:startBulletMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({ action = "amb_startBulletMinigame", targetSrc = targetSrc, part = part })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("bulletMinigameResult", function(result, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())

    if result.success then
        TriggerServerEvent("amb_server:HealPlayer", result.targetSrc, result.part, 2)
        Framework.Notify(_L("diagnosis_bullet_extracted"), "success")
    end

    refreshDiagnosisPart(result.part)
    cb("ok")
end)


-- ── Bandage mini-game ────────────────────────────────────────
RegisterNUICallback("applyBandage", function(data, cb)
    local patientServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))

    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if not hasItem then
            Framework.Notify(_L("diagnosis_need_bandage"), "error")
            return
        end
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "amb_hideDiagnosis" })
        TriggerEvent("amb_client:startBandageMinigame", patientServerId, data.part)
    end, "plt_bandage")

    cb("ok")
end)

RegisterNetEvent("amb_client:startBandageMinigame")
AddEventHandler("amb_client:startBandageMinigame", function(targetSrc, part)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    SendNUIMessage({ action = "amb_startBandageMinigame", targetSrc = targetSrc, part = part })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("bandageMinigameResult", function(result, cb)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())

    -- targetSrc may come from the result payload or fall back to the
    -- current diagnosis target.
    local resolvedTarget = tonumber(result and result.targetSrc) or targetServerId
    local part           = normalisePart(result and result.part)

    if result.success and resolvedTarget then
        TriggerServerEvent("amb_server:applyBandage", resolvedTarget, part)
        Framework.Notify(_L("diagnosis_bandage_applied"), "success")
    end

    refreshDiagnosisPart(part)
    cb("ok")
end)


-- ── Debug command: trigger bandage mini-game manually ────────
RegisterCommand("bandageminigame", function(_, args)
    local part     = normalisePart(args and args[1])
    local targetId = tonumber(args and args[2])
                  or GetPlayerServerId(PlayerId())

    TriggerEvent("amb_client:startBandageMinigame", targetId, part)
    Framework.Notify(("Bandage minigame started (%s)."):format(part), "info")
end, false)


-- ════════════════════════════════════════════════════════════
--  CPR
-- ════════════════════════════════════════════════════════════

RegisterNUICallback("performCPR", function(_, cb)
    local patientServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))

    -- Hide diagnosis UI and release NUI focus first.
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "amb_hideDiagnosis" })

    local myPed          = PlayerPedId()
    local patientHeading = GetEntityHeading(targetPed)

    -- Find a spot beside the patient to kneel for CPR.
    FreezeEntityPosition(myPed, false)
    local kneelOffset = GetOffsetFromEntityInWorldCoords(targetPed, -0.7196, -0.2604, 0.0003)

    -- Snap Z to ground level.
    local groundFound, groundZ = GetGroundZFor_3dCoord(
        kneelOffset.x, kneelOffset.y, kneelOffset.z + 1.0, false)

    if groundFound then
        kneelOffset = vector3(kneelOffset.x, kneelOffset.y, groundZ)
    end

    SetEntityCoords(myPed,
        kneelOffset.x, kneelOffset.y, kneelOffset.z,
        false, false, false, true)
    SetEntityHeading(myPed, patientHeading - 90.0)

    TriggerServerEvent("amb_server:startCombinedCPR", patientServerId)

    SetPedConfigFlag(myPed, 184, true)
    FreezeEntityPosition(myPed, true)

    local success = Framework.ProgressBar("Performing CPR", 20000)

    if success then
        TriggerServerEvent("amb_server:finishCPR", patientServerId)
        Framework.Notify(_L("diagnosis_cpr_success"), "success")

        isDiagnosisActive = false
        SetPedConfigFlag(myPed, 184, false)
        ClearPedTasks(myPed)

        RenderScriptCams(false, true, 300, true, true)
        if scriptCam then
            DestroyCam(scriptCam, false)
            scriptCam = nil
        end

        FreezeEntityPosition(myPed, false)

        targetPed      = nil
        targetServerId = nil
    else
        TriggerServerEvent("amb_server:stopCombinedCPR", patientServerId)
        ClearPedTasks(myPed)
        refreshDiagnosisPart(nil)
    end

    cb("ok")
end)


-- ── NUI: remove patient clothing ────────────────────────────
RegisterNUICallback("removePatientClothes", function(data, cb)
    local patientServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))

    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if not hasItem then
            Framework.Notify(_L("diagnosis_need_scissors"), "error")
            return
        end

        if data.type == "TOP" then
            clothingState.top = false
            TriggerServerEvent("amb_server:removeClothes", patientServerId, "top")
        else
            clothingState.bottom = false
            TriggerServerEvent("amb_server:removeClothes", patientServerId, "bottom")
        end

        refreshDiagnosisPart(data.part)
    end, "plt_surgical_scissors")

    cb("ok")
end)
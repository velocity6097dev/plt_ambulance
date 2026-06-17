local IsDiagnosing = false
local CurrentPatient = nil
local TargetPed = nil
local CPRActive = false
local RemovedClothes = { top = true, bottom = true }

-- ==========================================
-- Target Bones Configuration
-- ==========================================
local BoneOffsets = {
    { name = "head",      label = _L("body_head"),      bone = 31086, ox = 0.0, oy = 0.0, oz = 0.03 },
    { name = "chest",     label = _L("body_chest"),     bone = 24818, ox = 0.0, oy = 0.0, oz = 0.15 },
    { name = "stomach",   label = _L("body_stomach"),   bone = 11816, ox = 0.0, oy = 0.0, oz = 0.10 },
    { name = "right_arm", label = _L("body_right_arm"), bone = 28252, ox = 0.0, oy = 0.0, oz = 0.00 },
    { name = "left_arm",  label = _L("body_left_arm"),  bone = 61163, ox = 0.0, oy = 0.0, oz = 0.00 },
    { name = "right_leg", label = _L("body_right_leg"), bone = 51826, ox = 0.0, oy = 0.0, oz = 0.00 },
    { name = "left_leg",  label = _L("body_left_leg"),  bone = 58271, ox = 0.0, oy = 0.0, oz = 0.00 }
}

-- ==========================================
-- Core Functions
-- ==========================================

function StartDiagnosis(ped)
    local targetPed = ped
    if not targetPed then
        local closestPed, _, _ = GetClosestPlayer(3.0)
        targetPed = closestPed
    end
    
    if targetPed and DoesEntityExist(targetPed) then
        local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))
        
        -- Optional item check for tablet/diagnosis tool
        local diagnosisItem = (Config.Items and Config.Items.Diagnosis) or "med_tablet"
        
        Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
            if hasItem then
                IsDiagnosing = true
                CurrentPatient = targetSrc
                TargetPed = targetPed
                RemovedClothes = { top = true, bottom = true }
                
                SendNUIMessage({
                    action = "amb_openDiagnosis",
                    patient = targetSrc,
                    bones = BoneOffsets
                })
                
                SetNuiFocus(true, true)
                TriggerEvent("amb_client:equipTablet")
            else
                Framework.Notify(_L("no_diagnosis_tool"), "error")
            end
        end, diagnosisItem)
    else
        Framework.Notify(_L("no_player_nearby"), "error")
    end
end
exports("StartDiagnosis", StartDiagnosis)

-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback("amb_closeDiagnosis", function(data, cb)
    IsDiagnosing = false
    CurrentPatient = nil
    TargetPed = nil
    CPRActive = false
    
    SetNuiFocus(false, false)
    TriggerEvent("amb_client:unequipTablet")
    cb("ok")
end)

RegisterNUICallback("amb_getInjuries", function(data, cb)
    local injuries = exports.plt_ambulance_job:diagnosePlayer(CurrentPatient)
    cb(injuries or {})
end)

RegisterNUICallback("amb_treatInjury", function(data, cb)
    local part = data.part
    local injuryId = data.injuryId
    local treatmentItem = (Config.Items and Config.Items.Treatment) or "medkit"
    
    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if hasItem then
            TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
            local success = Framework.ProgressBar(_L("progress_apply_treatment"), 5000)
            ClearPedTasks(PlayerPedId())
            
            if success then
                TriggerServerEvent("amb_server:treatInjury", CurrentPatient, part, injuryId)
                cb({ success = true })
            else
                cb({ success = false })
            end
        else
            Framework.Notify(_L("no_treatment_item"), "error")
            cb({ success = false })
        end
    end, treatmentItem)
end)

RegisterNUICallback("amb_applyMedication", function(data, cb)
    local medType = data.medType
    
    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if hasItem then
            TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
            local success = Framework.ProgressBar(_L("progress_apply_medication"), 4000)
            ClearPedTasks(PlayerPedId())
            
            if success then
                TriggerServerEvent("amb_server:applyMedication", CurrentPatient, medType)
                cb({ success = true })
            else
                cb({ success = false })
            end
        else
            Framework.Notify(_L("no_medication_item"), "error")
            cb({ success = false })
        end
    end, medType)
end)

RegisterNUICallback("amb_performCPR", function(data, cb)
    if not TargetPed then return cb("ok") end
    
    local ped = PlayerPedId()

    if CPRActive then
        -- Stop CPR
        CPRActive = false
        ClearPedTasks(ped)
        TriggerServerEvent("amb_server:stopCombinedCPR", CurrentPatient)
    else
        -- Start CPR
        CPRActive = true
        TriggerServerEvent("amb_server:syncCombinedCPR", CurrentPatient)
        
        CreateThread(function()
            local dict = "mini@cpr@char_a@cpr_str"
            local anim = "cpr_pumpchest"
            RequestAnimDict(dict)
            while not HasAnimDictLoaded(dict) do Wait(10) end
            
            while CPRActive do
                if not IsEntityPlayingAnim(ped, dict, anim, 3) then
                    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
                end
                Wait(0)
            end
        end)
        
        local success = Framework.ProgressBar(_L("progress_cpr"), 15000)
        
        if success and CPRActive then
            TriggerServerEvent("amb_server:finishCPR", CurrentPatient)
        end
        
        CPRActive = false
        TriggerServerEvent("amb_server:stopCombinedCPR", CurrentPatient)
        ClearPedTasks(ped)
    end
    cb("ok")
end)

RegisterNUICallback("removePatientClothes", function(data, cb)
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(TargetPed))
    local scissorsItem = (Config.Items and Config.Items.Scissors) or "shears"
    
    Framework.TriggerCallback("amb_server:hasRequiredItem", function(hasItem)
        if hasItem then
            local animDict = "random@domestic"
            local animName = "pickup_low"
            
            RequestAnimDict(animDict)
            while not HasAnimDictLoaded(animDict) do Wait(10) end
            
            TaskPlayAnim(PlayerPedId(), animDict, animName, 8.0, -8.0, 1000, 0, 0, false, false, false)
            Wait(1000)
            
            TriggerServerEvent("amb_server:removePatientClothes", targetSrc, data.part)
            cb({ success = true })
        else
            Framework.Notify(_L("no_scissors"), "error")
            cb({ success = false })
        end
    end, scissorsItem)
end)

-- ==========================================
-- Net Events
-- ==========================================

RegisterNetEvent("amb_client:applyTreatmentAnim", function()
    local ped = PlayerPedId()
    local animDict = "anim@heists@narcotics@funding@gang_idle"
    local animName = "gang_chatting_idle01"
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(10) end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 3000, 49, 0, false, false, false)
end)
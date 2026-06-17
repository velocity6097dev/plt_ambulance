-- Table to keep track of which medics are currently diagnosing which patients
-- Format: ActiveDiagnoses[patientSrc] = { medicSrc1, medicSrc2, ... }
local ActiveDiagnoses = {}

-- ==========================================
-- Diagnosis Synchronization
-- ==========================================

RegisterNetEvent("amb_server:requestInjuries", function(patientSrc)
    local medicSrc = source

    if not ActiveDiagnoses[patientSrc] then
        ActiveDiagnoses[patientSrc] = {}
    end

    local alreadyDiagnosing = false
    for _, activeMedic in ipairs(ActiveDiagnoses[patientSrc]) do
        if activeMedic == medicSrc then
            alreadyDiagnosing = true
            break
        end
    end

    if not alreadyDiagnosing then
        table.insert(ActiveDiagnoses[patientSrc], medicSrc)
    end

    -- Request the injury data from the patient's client
    TriggerClientEvent("amb_client:requestInjuryData", patientSrc)
end)

RegisterNetEvent("amb_server:syncInjuryData", function(injuryData)
    local patientSrc = source

    if ActiveDiagnoses[patientSrc] then
        -- Iterate backwards to safely remove invalid entries
        for i = #ActiveDiagnoses[patientSrc], 1, -1 do
            local medicSrc = ActiveDiagnoses[patientSrc][i]
            
            if GetPlayerName(medicSrc) then
                -- Send the patient's injury data back to the examining medic
                TriggerClientEvent("amb_client:receiveDiagnosisData", medicSrc, injuryData)
            else
                -- Medic is no longer online, remove them from the list
                table.remove(ActiveDiagnoses[patientSrc], i)
            end
        end
    end
end)

RegisterNetEvent("amb_server:stopDiagnosisSync", function(patientSrc)
    local medicSrc = source

    if ActiveDiagnoses[patientSrc] then
        for i, activeMedic in ipairs(ActiveDiagnoses[patientSrc]) do
            if activeMedic == medicSrc then
                table.remove(ActiveDiagnoses[patientSrc], i)
                break
            end
        end
    end
end)

-- ==========================================
-- Treatment & Items
-- ==========================================

RegisterNetEvent("amb_server:removeClothes", function(patientSrc, clothingPart)
    TriggerClientEvent("amb_client:removeClothes", patientSrc, clothingPart)
end)

RegisterNetEvent("amb_server:applyBandage", function(patientSrc, bodyPart)
    local medicSrc = source
    local hasItem = Framework.RemoveItem(medicSrc, "plt_bandage", 1)
    
    if hasItem then
        TriggerClientEvent("amb_client:applyBandage", patientSrc, bodyPart)
    end
end)

RegisterNetEvent("amb_server:updateHungerWorkflow", function(patientSrc)
    TriggerClientEvent("amb_client:updateHungerWorkflow", patientSrc)
end)

RegisterNetEvent("amb_server:giveFludro", function(patientSrc)
    local medicSrc = source
    local hasItem = Framework.RemoveItem(medicSrc, "plt_medkit", 1)
    
    if hasItem then
        TriggerClientEvent("amb_client:giveFludro", patientSrc)
    end
end)

RegisterNetEvent("amb_server:ClampBleeding", function(patientSrc)
    local medicSrc = source
    local itemCount = Framework.GetItemCount(medicSrc, "plt_surgical_kit")
    
    if itemCount > 0 then
        TriggerClientEvent("amb_client:clampBleeding", patientSrc)
    end
end)

-- ==========================================
-- CPR Synchronization
-- ==========================================

RegisterNetEvent("amb_server:startCombinedCPR", function(patientSrc)
    local medicSrc = source
    -- Sync looping animation for both players
    TriggerClientEvent("amb_client:syncCPRAnimation", patientSrc, medicSrc, "patient", "loop")
    TriggerClientEvent("amb_client:syncCPRAnimation", medicSrc, patientSrc, "ems", "loop")
end)

RegisterNetEvent("amb_server:successCPR", function(patientSrc)
    local medicSrc = source
    -- Sync success animation for both players
    TriggerClientEvent("amb_client:syncCPRAnimation", patientSrc, medicSrc, "patient", "success")
    TriggerClientEvent("amb_client:syncCPRAnimation", medicSrc, patientSrc, "ems", "success")
end)

RegisterNetEvent("amb_server:stopCombinedCPR", function(patientSrc)
    local medicSrc = source
    -- Stop animations for both players
    TriggerClientEvent("amb_client:stopCPRAnimation", patientSrc)
    TriggerClientEvent("amb_client:stopCPRAnimation", medicSrc)
end)

RegisterNetEvent("amb_server:finishCPR", function(patientSrc)
    local medicSrc = source
    
    -- Sync final success animation
    TriggerClientEvent("amb_client:syncCPRAnimation", patientSrc, medicSrc, "patient", "success")
    TriggerClientEvent("amb_client:syncCPRAnimation", medicSrc, patientSrc, "ems", "success")
    
    -- Clear diagnosis cache
    ActiveDiagnoses[patientSrc] = nil
    
    -- Stop CPR animations
    TriggerClientEvent("amb_client:stopCPRAnimation", patientSrc)
    TriggerClientEvent("amb_client:stopCPRAnimation", medicSrc)
    
    -- Actually revive the player
    exports.plt_ambulance_job:InternalRevive(patientSrc)
end)

-- ==========================================
-- Utility Callbacks
-- ==========================================

Framework.CreateCallback("amb_server:hasRequiredItem", function(source, cb, itemName)
    local count = Framework.GetItemCount(source, itemName)
    cb(count > 0)
end)
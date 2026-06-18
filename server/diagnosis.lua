-- =============================================================================
-- plt_ambulance | Diagnosis & Treatment – Server
-- Handles injury syncing, CPR coordination, and item-gated treatments.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- diagnosisWatchers[patientSrc] = { medicSrc, ... }
-- Tracks which medics are currently watching a given patient's injury data.
-- ---------------------------------------------------------------------------
local diagnosisWatchers = {}

-- =============================================================================
-- Injury data sync
-- =============================================================================

-- Fired by a medic who wants to view a patient's injuries.
-- Registers the medic as a watcher, then asks the patient's client to send
-- its current injury data back via "amb_server:syncInjuryData".
RegisterNetEvent("amb_server:requestInjuries")
AddEventHandler("amb_server:requestInjuries", function(patientSrc)
    local medicSrc = source

    -- Initialise watcher list for this patient if needed
    if not diagnosisWatchers[patientSrc] then
        diagnosisWatchers[patientSrc] = {}
    end

    -- Add medic to the watcher list (avoid duplicates)
    local alreadyWatching = false
    for _, watcherSrc in ipairs(diagnosisWatchers[patientSrc]) do
        if watcherSrc == medicSrc then
            alreadyWatching = true
            break
        end
    end

    if not alreadyWatching then
        table.insert(diagnosisWatchers[patientSrc], medicSrc)
    end

    -- Ask the patient's client to broadcast its injury data
    TriggerClientEvent("amb_client:requestInjuryData", patientSrc)
end)

-- Fired by the patient's client in response to "amb_client:requestInjuryData".
-- Relays the injury payload to every medic currently watching this patient.
-- Stale watchers (disconnected players) are pruned on the fly.
RegisterNetEvent("amb_server:syncInjuryData")
AddEventHandler("amb_server:syncInjuryData", function(injuryData)
    local patientSrc = source
    local watchers   = diagnosisWatchers[patientSrc]
    if not watchers then return end

    -- Iterate backwards so we can safely remove stale entries
    for i = #watchers, 1, -1 do
        local medicSrc = watchers[i]
        if GetPlayerName(medicSrc) then
            -- Player is still connected – send them the data
            TriggerClientEvent("amb_client:receiveDiagnosisData", medicSrc, injuryData)
        else
            -- Player disconnected – prune from the list
            table.remove(watchers, i)
        end
    end
end)

-- Fired by a medic when they close the diagnosis UI.
-- Removes them from the patient's watcher list.
RegisterNetEvent("amb_server:stopDiagnosisSync")
AddEventHandler("amb_server:stopDiagnosisSync", function(patientSrc)
    local medicSrc = source
    local watchers  = diagnosisWatchers[patientSrc]
    if not watchers then return end

    for i, watcherSrc in ipairs(watchers) do
        if watcherSrc == medicSrc then
            table.remove(watchers, i)
            break
        end
    end
end)

-- =============================================================================
-- Clothing / appearance
-- =============================================================================

-- Fired by a medic to strip a piece of clothing from a patient.
-- Args: patientSrc, clothingSlot
RegisterNetEvent("amb_server:removeClothes")
AddEventHandler("amb_server:removeClothes", function(patientSrc, clothingSlot)
    TriggerClientEvent("amb_client:removeClothes", patientSrc, clothingSlot)
end)

-- =============================================================================
-- Item-gated treatments
-- =============================================================================

-- Apply a bandage to a patient.
-- Consumes one "plt_bandage" from the medic's inventory on success.
-- Args: patientSrc, bodyPart
RegisterNetEvent("amb_server:applyBandage")
AddEventHandler("amb_server:applyBandage", function(patientSrc, bodyPart)
    local medicSrc = source
    local removed  = Framework.RemoveItem(medicSrc, "plt_bandage", 1)
    if removed then
        TriggerClientEvent("amb_client:applyBandage", patientSrc, bodyPart)
    end
end)

-- Administer a fludro (IV fluids) to a patient.
-- Consumes one "plt_medkit" from the medic's inventory on success.
-- Args: patientSrc
RegisterNetEvent("amb_server:giveFludro")
AddEventHandler("amb_server:giveFludro", function(patientSrc)
    local medicSrc = source
    local removed  = Framework.RemoveItem(medicSrc, "plt_medkit", 1)
    if removed then
        TriggerClientEvent("amb_client:giveFludro", patientSrc)
    end
end)

-- Clamp bleeding on a patient.
-- Requires at least one "plt_surgical_kit" in the medic's inventory (not consumed).
-- Args: patientSrc
RegisterNetEvent("amb_server:ClampBleeding")
AddEventHandler("amb_server:ClampBleeding", function(patientSrc)
    local medicSrc = source
    local count    = Framework.GetItemCount(medicSrc, "plt_surgical_kit")
    if count > 0 then
        TriggerClientEvent("amb_client:clampBleeding", patientSrc)
    end
end)

-- Update the hunger/thirst workflow for a patient.
-- Args: patientSrc
RegisterNetEvent("amb_server:updateHungerWorkflow")
AddEventHandler("amb_server:updateHungerWorkflow", function(patientSrc)
    TriggerClientEvent("amb_client:updateHungerWorkflow", patientSrc)
end)

-- =============================================================================
-- CPR coordination
-- All CPR events sync animations between the medic (EMS) and the patient.
-- The pattern for syncCPRAnimation is:
--   TriggerClientEvent("amb_client:syncCPRAnimation", target, otherSrc, role, phase)
--     role  – "patient" | "ems"
--     phase – "loop" | "success"
-- =============================================================================

-- Start a two-person CPR sequence (looping animations on both sides).
-- Args: patientSrc
RegisterNetEvent("amb_server:startCombinedCPR")
AddEventHandler("amb_server:startCombinedCPR", function(patientSrc)
    local medicSrc = source
    TriggerClientEvent("amb_client:syncCPRAnimation", patientSrc, medicSrc, "patient", "loop")
    TriggerClientEvent("amb_client:syncCPRAnimation", medicSrc,   patientSrc, "ems",     "loop")
end)

-- Trigger the CPR success animation on both participants without ending the session.
-- Args: patientSrc
RegisterNetEvent("amb_server:successCPR")
AddEventHandler("amb_server:successCPR", function(patientSrc)
    local medicSrc = source
    TriggerClientEvent("amb_client:syncCPRAnimation", patientSrc, medicSrc, "patient", "success")
    TriggerClientEvent("amb_client:syncCPRAnimation", medicSrc,   patientSrc, "ems",     "success")
end)

-- Abort CPR – stop animations on both participants without reviving.
-- Args: patientSrc
RegisterNetEvent("amb_server:stopCombinedCPR")
AddEventHandler("amb_server:stopCombinedCPR", function(patientSrc)
    local medicSrc = source
    TriggerClientEvent("amb_client:stopCPRAnimation", patientSrc)
    TriggerClientEvent("amb_client:stopCPRAnimation", medicSrc)
end)

-- Successfully finish CPR: play success animations, stop CPR, clear watcher
-- list, and trigger an internal revive on the patient.
-- Args: patientSrc
RegisterNetEvent("amb_server:finishCPR")
AddEventHandler("amb_server:finishCPR", function(patientSrc)
    local medicSrc = source

    -- Play success animations on both sides
    TriggerClientEvent("amb_client:syncCPRAnimation", patientSrc, medicSrc, "patient", "success")
    TriggerClientEvent("amb_client:syncCPRAnimation", medicSrc,   patientSrc, "ems",     "success")

    -- Clear any diagnosis watchers for this patient
    diagnosisWatchers[patientSrc] = nil

    -- Stop CPR animations
    TriggerClientEvent("amb_client:stopCPRAnimation", patientSrc)
    TriggerClientEvent("amb_client:stopCPRAnimation", medicSrc)

    -- Revive the patient
    exports.plt_ambulance_job:InternalRevive(patientSrc)
end)

-- =============================================================================
-- Callback: item check
-- =============================================================================

-- Returns true if the requesting player has at least one of the given item.
-- Args (via callback data): itemName
Framework.CreateCallback("amb_server:hasRequiredItem", function(src, cb, itemName)
    local count = Framework.GetItemCount(src, itemName)
    cb(count > 0)
end)

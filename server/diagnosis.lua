local ActiveDiagnoses = {}

RegisterNetEvent("amb_server:requestInjuries", function(targetSrc)
    local src = source
    
    if not ActiveDiagnoses[targetSrc] then
        ActiveDiagnoses[targetSrc] = {}
    end
    
    local alreadyRequested = false
    for _, medicId in ipairs(ActiveDiagnoses[targetSrc]) do
        if medicId == src then
            alreadyRequested = true
            break
        end
    end
    
    if not alreadyRequested then
        table.insert(ActiveDiagnoses[targetSrc], src)
    end
    
    TriggerClientEvent("amb_client:requestInjuryData", targetSrc)
end)

RegisterNetEvent("amb_server:syncInjuryData", function(injuryData)
    local src = source
    local medicsList = ActiveDiagnoses[src]
    
    if medicsList then
        -- Iterate backwards to safely remove offline medics
        for i = #medicsList, 1, -1 do
            local medicSrc = medicsList[i]
            if GetPlayerName(medicSrc) then
                TriggerClientEvent("amb_client:receiveDiagnosisData", medicSrc, src, injuryData)
            else
                table.remove(medicsList, i)
            end
        end
    end
end)

RegisterNetEvent("amb_server:stopDiagnosisSync", function(targetSrc)
    local src = source
    if ActiveDiagnoses[targetSrc] then
        for i, medicId in ipairs(ActiveDiagnoses[targetSrc]) do
            if medicId == src then
                table.remove(ActiveDiagnoses[targetSrc], i)
                break
            end
        end
    end
end)

RegisterNetEvent("amb_server:removeClothes", function(targetSrc, clothData)
    TriggerClientEvent("amb_client:removeClothes", targetSrc, clothData)
end)

RegisterNetEvent("amb_server:applyBandage", function(targetSrc, bandageData)
    local src = source
    if Framework.RemoveItem(src, "plt_bandage", 1) then
        TriggerClientEvent("amb_client:applyBandage", targetSrc, bandageData)
    end
end)

RegisterNetEvent("amb_server:updateHungerWorkflow", function(targetSrc)
    TriggerClientEvent("amb_client:updateHungerWorkflow", targetSrc)
end)

RegisterNetEvent("amb_server:giveFludro", function(targetSrc)
    local src = source
    if Framework.RemoveItem(src, "plt_medkit", 1) then
        TriggerClientEvent("amb_client:giveFludro", targetSrc)
    end
end)

RegisterNetEvent("amb_server:ClampBleeding", function(targetSrc)
    local src = source
    if Framework.GetItemCount(src, "plt_surgical_kit") > 0 then
        TriggerClientEvent("amb_client:clampBleeding", targetSrc)
    end
end)

RegisterNetEvent("amb_server:startCombinedCPR", function(targetSrc)
    local src = source
    TriggerClientEvent("amb_client:syncCPRAnimation", targetSrc, src, "patient", "loop")
    TriggerClientEvent("amb_client:syncCPRAnimation", src, targetSrc, "ems", "loop")
end)

RegisterNetEvent("amb_server:successCPR", function(targetSrc)
    local src = source
    TriggerClientEvent("amb_client:syncCPRAnimation", targetSrc, src, "patient", "success")
    TriggerClientEvent("amb_client:syncCPRAnimation", src, targetSrc, "ems", "success")
end)

RegisterNetEvent("amb_server:stopCombinedCPR", function(targetSrc)
    local src = source
    TriggerClientEvent("amb_client:stopCPRAnimation", targetSrc)
    TriggerClientEvent("amb_client:stopCPRAnimation", src)
end)

RegisterNetEvent("amb_server:finishCPR", function(targetSrc)
    local src = source
    TriggerClientEvent("amb_client:syncCPRAnimation", targetSrc, src, "patient", "success")
    TriggerClientEvent("amb_client:syncCPRAnimation", src, targetSrc, "ems", "success")
    
    ActiveDiagnoses[targetSrc] = nil
    
    TriggerClientEvent("amb_client:stopCPRAnimation", targetSrc)
    TriggerClientEvent("amb_client:stopCPRAnimation", src)
    
    exports.plt_ambulance_job:InternalRevive(targetSrc)
end)

Framework.CreateCallback("amb_server:hasRequiredItem", function(source, cb, itemName)
    cb(Framework.GetItemCount(source, itemName) > 0)
end)
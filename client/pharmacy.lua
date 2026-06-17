local isPharmacyOpen = false

-- ==========================================
-- Utility Functions
-- ==========================================

function GetTargetPlayerId()
    return exports.plt_ambulance_job:GetDiagnosisTarget()
end

-- ==========================================
-- Client Events
-- ==========================================

RegisterNetEvent("amb_client:openPharmacy", function(data)
    if isPharmacyOpen then return end
    
    local jobName = data
    if type(data) == "table" and data.jobName then
        jobName = data.jobName
    end

    Framework.TriggerCallback("amb_server:getPharmacyData", function(pharmaData)
        if pharmaData then
            isPharmacyOpen = true
            SetNuiFocus(true, true)
            
            pharmaData.linkedJob = jobName
            
            SendNUIMessage({
                action = "amb_openPharmacy",
                data = pharmaData
            })
        end
    end)
end)

RegisterNetEvent("amb_client:updateInsuranceStatus", function(status)
    SendNUIMessage({
        action = "amb_updateInsuranceStatus",
        hasInsurance = status
    })
end)

RegisterNetEvent("amb_client:updatePharmacyCash", function(cashAmount)
    SendNUIMessage({
        action = "amb_updatePharmacyCash",
        cash = cashAmount
    })
end)

RegisterNetEvent("amb_client:refreshPharmacyData", function()
    if not isPharmacyOpen then return end
    
    Framework.TriggerCallback("amb_server:getPharmacyData", function(data)
        if data then
            SendNUIMessage({
                action = "amb_refreshPharmacyData",
                data = data
            })
        end
    end)
end)

RegisterNetEvent("amb_client:viewPrescription", function(data)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "amb_viewPrescription",
        data = data
    })
end)

-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback("closePharmacy", function(data, cb)
    isPharmacyOpen = false
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("luaLog", function(data, cb)
    if data and data.message then
        print("^5[PHARMACY UI] " .. tostring(data.message) .. "^7")
    end
    cb("ok")
end)

RegisterNUICallback("pharmacyBuyItem", function(data, cb)
    TriggerServerEvent("amb_server:purchasePharmacyItem", data)
    cb("ok")
end)

RegisterNUICallback("buyInsurance", function(data, cb)
    print("^3[PHARMACY]^7 buyInsurance callback received from NUI")
    local linkedJob = nil
    if data and data.linkedJob then
        linkedJob = data.linkedJob
    end
    
    TriggerServerEvent("amb_server:buyInsurance", nil, linkedJob)
    cb("ok")
end)

RegisterNUICallback("checkPrescription", function(data, cb)
    Framework.TriggerCallback("amb_server:checkPrescription", function(result)
        cb(result)
    end)
end)

RegisterNUICallback("closePrescriptionViewer", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("openPrescriptionWriter", function(data, cb)
    local targetSrc = GetTargetPlayerId()
    
    if targetSrc then
        Framework.TriggerCallback("amb_server:getPlayerData", function(playerData)
            if playerData then
                SendNUIMessage({
                    action = "amb_setPrescriptionWriter",
                    patientName = playerData.name,
                    targetSrc = targetSrc
                })
            end
        end, targetSrc)
    end
    
    cb("ok")
end)

RegisterNUICallback("issuePrescription", function(data, cb)
    TriggerServerEvent("amb_server:issuePrescription", data)
    cb("ok")
end)
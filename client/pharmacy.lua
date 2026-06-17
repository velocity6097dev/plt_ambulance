local isPharmacyOpen = false

RegisterNetEvent("amb_client:openPharmacy", function(eventData)
    if isPharmacyOpen then
        return
    end

    local jobName
    if type(eventData) == "table" then
        jobName = eventData.jobName
        if jobName then
            goto lbl_14
        end
    end
    
    -- Quirk preserved: If eventData is a table but jobName is missing, 
    -- the whole table is assigned to the jobName variable.
    jobName = eventData

    ::lbl_14::
    Framework.TriggerCallback("amb_server:getPharmacyData", function(pharmacyData)
        if pharmacyData then
            isPharmacyOpen = true
            SetNuiFocus(true, true)

            pharmacyData.linkedJob = jobName

            SendNUIMessage({
                action = "amb_openPharmacy",
                data = pharmacyData
            })
        end
    end)
end)

RegisterNUICallback("closePharmacy", function(data, cb)
    isPharmacyOpen = false
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("luaLog", function(data, cb)
    if data then
        if data.message then
            print("^5[PHARMACY UI] " .. tostring(data.message) .. "^7")
        end
    end
    cb("ok")
end)

RegisterNUICallback("pharmacyBuyItem", function(data, cb)
    TriggerServerEvent("amb_server:purchasePharmacyItem", data)
    cb("ok")
end)

RegisterNUICallback("buyInsurance", function(data, cb)
    print("^3[PHARMACY]^7 buyInsurance callback received from NUI")
    
    local linkedJob
    if data then
        linkedJob = data.linkedJob
        if linkedJob then
            goto lbl_10
        end
    end
    linkedJob = nil

    ::lbl_10::
    -- Quirk preserved: Explicit nil passed as the second argument.
    TriggerServerEvent("amb_server:buyInsurance", nil, linkedJob)
    cb("ok")
end)

RegisterNUICallback("checkPrescription", function(data, cb)
    Framework.TriggerCallback("amb_server:checkPrescription", function(prescriptionData)
        cb(prescriptionData)
    end)
end)

RegisterNetEvent("amb_client:updateInsuranceStatus", function(hasInsurance)
    SendNUIMessage({
        action = "amb_updateInsuranceStatus",
        hasInsurance = hasInsurance
    })
end)

RegisterNetEvent("amb_client:updatePharmacyCash", function(cashAmount)
    SendNUIMessage({
        action = "amb_updatePharmacyCash",
        cash = cashAmount
    })
end)

RegisterNetEvent("amb_client:refreshPharmacyData", function()
    if not isPharmacyOpen then
        return
    end

    Framework.TriggerCallback("amb_server:getPharmacyData", function(pharmacyData)
        if pharmacyData then
            SendNUIMessage({
                action = "amb_refreshPharmacyData",
                data = pharmacyData
            })
        end
    end)
end)

RegisterNetEvent("amb_client:viewPrescription", function(prescriptionData)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "amb_viewPrescription",
        data = prescriptionData
    })
end)

RegisterNUICallback("closePrescriptionViewer", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("openPrescriptionWriter", function(data, cb)
    local targetId = GetTargetPlayerId()
    if targetId then
        Framework.TriggerCallback("amb_server:getPlayerData", function(playerData)
            if playerData then
                SendNUIMessage({
                    action = "amb_setPrescriptionWriter",
                    patientName = playerData.name,
                    targetSrc = targetId
                })
            end
        end, targetId)
    end
    cb("ok")
end)

RegisterNUICallback("issuePrescription", function(data, cb)
    TriggerServerEvent("amb_server:issuePrescription", data)
    cb("ok")
end)

function GetTargetPlayerId()
    return exports.plt_ambulance_job:GetDiagnosisTarget()
end
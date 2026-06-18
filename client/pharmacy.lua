-- ============================================================
-- Pharmacy - Client Script
-- De-obfuscated / cleaned up from compiled Lua
-- ============================================================

local isPharmacyOpen = false

-- ------------------------------------------------------------
-- Returns the diagnosis target from the ambulance job export.
-- Declared up front since it's referenced before its original
-- (end-of-file) definition point; behavior is unchanged since
-- Lua only resolves globals at call time.
-- ------------------------------------------------------------
function GetTargetPlayerId()
  return exports.plt_ambulance_job:GetDiagnosisTarget()
end

-- ------------------------------------------------------------
-- Open the pharmacy UI
-- Accepts either a job name string, or a table like { jobName = "..." }
-- ------------------------------------------------------------
RegisterNetEvent("amb_client:openPharmacy")
AddEventHandler("amb_client:openPharmacy", function(data)
  if isPharmacyOpen then
    return
  end

  local jobName = data
  if type(data) == "table" and data.jobName then
    jobName = data.jobName
  end

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

  local jobName = nil
  if data and data.linkedJob then
    jobName = data.linkedJob
  end

  -- NOTE: first argument is intentionally nil in the original script.
  -- Worth double-checking against the amb_server:buyInsurance handler
  -- signature on the server side to confirm this is expected.
  TriggerServerEvent("amb_server:buyInsurance", nil, jobName)

  cb("ok")
end)

RegisterNUICallback("checkPrescription", function(data, cb)
  Framework.TriggerCallback("amb_server:checkPrescription", function(result)
    cb(result)
  end)
end)

-- ------------------------------------------------------------
-- Insurance / cash status pushes from the server while the UI is open
-- ------------------------------------------------------------
RegisterNetEvent("amb_client:updateInsuranceStatus")
AddEventHandler("amb_client:updateInsuranceStatus", function(hasInsurance)
  SendNUIMessage({
    action = "amb_updateInsuranceStatus",
    hasInsurance = hasInsurance
  })
end)

RegisterNetEvent("amb_client:updatePharmacyCash")
AddEventHandler("amb_client:updatePharmacyCash", function(cash)
  SendNUIMessage({
    action = "amb_updatePharmacyCash",
    cash = cash
  })
end)

RegisterNetEvent("amb_client:refreshPharmacyData")
AddEventHandler("amb_client:refreshPharmacyData", function()
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

-- ------------------------------------------------------------
-- Prescription viewing / writing
-- ------------------------------------------------------------
RegisterNetEvent("amb_client:viewPrescription")
AddEventHandler("amb_client:viewPrescription", function(data)
  SetNuiFocus(true, true)
  SendNUIMessage({
    action = "amb_viewPrescription",
    data = data
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
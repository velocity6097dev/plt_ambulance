-- ==========================================
-- Utility Functions
-- ==========================================

local function GetCoreInventoryName()
    if GetResourceState("core_inventory") == "started" then return "core_inventory" end
    if GetResourceState("core-inventory") == "started" then return "core-inventory" end
    return nil
end

local function HasPrescriptionItem(source)
    -- OX Inventory Check
    if GetResourceState("ox_inventory") == "started" then
        local items = exports.ox_inventory:Search(source, 1, "plt_prescription")
        if items and type(items) == "table" then
            for _, item in pairs(items) do
                if item and item.metadata then
                    return true, item.metadata
                end
            end
        end
    end

    -- Default Framework / QBCore / Quasar / TGiann Check
    local player = Framework.GetPlayer(source)
    if player and player.PlayerData and player.PlayerData.items then
        for _, item in pairs(player.PlayerData.items) do
            if item and item.name == "plt_prescription" then
                local meta = item.metadata or item.info
                return true, meta
            end
        end
    end

    return false, nil
end

-- ==========================================
-- Framework Callbacks
-- ==========================================

Framework.CreateCallback("amb_server:getPharmacyData", function(source, cb)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return cb(nil) end

    local cid = player.citizenid
    local profile = PatientProfiles[cid] or {}
    local hasInsurance = (profile.has_insurance == true)
    
    local items = (Config.Pharmacy and Config.Pharmacy.Items) or {}

    cb({
        hasInsurance = hasInsurance,
        items = items
    })
end)

Framework.CreateCallback("amb_server:checkPrescription", function(source, cb)
    local hasItem, metadata = HasPrescriptionItem(source)
    cb({
        hasPrescription = hasItem,
        prescriptionData = metadata
    })
end)

-- ==========================================
-- Net Events
-- ==========================================

RegisterNetEvent("amb_server:purchasePharmacyItem", function(data)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    local itemId = data.itemId
    local amount = tonumber(data.amount) or 1
    local dept = data.linkedJob or "ambulance"

    if not itemId or amount <= 0 then return end

    local itemConfig = Config.Pharmacy.Items[itemId]
    if not itemConfig then return end

    local basePrice = tonumber(itemConfig.price) or 0
    local totalPrice = basePrice * amount

    local cid = player.citizenid
    local profile = PatientProfiles[cid] or {}
    local hasInsurance = (profile.has_insurance == true)

    -- Apply insurance discount if eligible
    if hasInsurance and itemConfig.insuranceCovered then
        local discountPct = tonumber(Config.Pharmacy.InsuranceDiscount) or 50
        totalPrice = math.floor(totalPrice * (1.0 - (discountPct / 100.0)))
    end

    -- Process Payment
    if player.functions.RemoveMoney("cash", totalPrice, "pharmacy-purchase") or player.functions.RemoveMoney("bank", totalPrice, "pharmacy-purchase") then
        if Framework.AddItem(src, itemId, amount) then
            local itemName = itemConfig.label or itemId
            Framework.Notify(src, _L("purchased_item", {item = itemName, amount = amount, price = totalPrice}), "success")
            
            -- Add funds to the department balance
            if AddFinanceEntry then
                AddFinanceEntry(dept, "deposit", totalPrice, "Pharmacy Sale (" .. itemName .. ")", "System")
            end
        else
            -- Refund if the player's inventory is full
            player.functions.AddMoney("cash", totalPrice, "pharmacy-refund")
            Framework.Notify(src, _L("cannot_carry_more_item"), "error")
        end
    else
        Framework.Notify(src, _L("not_enough_money"), "error")
    end
end)

RegisterNetEvent("amb_server:buyInsurance", function(data, linkedJob)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    local price = (Config.Pharmacy and Config.Pharmacy.InsurancePrice) or 5000
    local dept = linkedJob or "ambulance"

    if player.functions.RemoveMoney("bank", price, "pharmacy-insurance") or player.functions.RemoveMoney("cash", price, "pharmacy-insurance") then
        local cid = player.citizenid
        local profile = PatientProfiles[cid] or {}
        
        -- Update Profile
        profile.has_insurance = true
        PatientProfiles[cid] = profile
        
        if SavePatientProfiles then SavePatientProfiles() end
        
        -- Deposit to department
        if AddFinanceEntry then
            AddFinanceEntry(dept, "deposit", price, "Insurance Plan Purchase", "System")
        end

        Framework.Notify(src, _L("insurance_purchased"), "success")
        TriggerClientEvent("amb_client:updateInsuranceStatus", src, true)
    else
        Framework.Notify(src, _L("not_enough_money"), "error")
    end
end)

RegisterNetEvent("amb_server:issuePrescription", function(data)
    local src = source

    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        return Framework.Notify(src, _L("not_authorized"), "error")
    end

    local targetSrc = tonumber(data.targetSrc)
    if not targetSrc then return end

    local targetPlayer = Framework.GetPlayer(targetSrc)
    local medicPlayer = Framework.GetPlayer(src)

    if not targetPlayer or not medicPlayer then return end

    local metadata = {
        patientName = data.patientName or targetPlayer.name,
        doctor = medicPlayer.name,
        doctorDept = (medicPlayer.job and medicPlayer.job.label) or "Medical Services",
        medications = data.medications or "General Medical Services",
        notes = data.notes or "",
        duration = tonumber(data.duration) or 10,
        issuedAt = os.date("%Y-%m-%d %H:%M:%S")
    }

    if Framework.AddItem(targetSrc, "plt_prescription", 1, metadata) then
        Framework.Notify(src, _L("prescription_issued_to", {name = targetPlayer.name}), "success")
        Framework.Notify(targetSrc, _L("prescription_received", {doctor = medicPlayer.name}), "info")
    else
        Framework.Notify(src, _L("patient_inventory_full"), "error")
    end
end)
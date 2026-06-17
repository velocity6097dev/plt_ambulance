local Framework = exports.plt_ambulance_job:GetFramework()

function GetCoreInventoryResource()
    if GetResourceState("core_inventory") == "started" then
        return "core_inventory"
    end
    if GetResourceState("core-inventory") == "started" then
        return "core-inventory"
    end
    return nil
end

function GetCoreInventoryItems(sourceId)
    local coreRes = GetCoreInventoryResource()
    if not coreRes then
        return {}
    end
    
    local success1, result1 = pcall(function()
        return exports[coreRes]:GetInventory(sourceId)
    end)
    
    if success1 and result1 then
        if type(result1.items) == "table" then
            return result1.items
        end
    end
    
    local success2, result2 = pcall(function()
        return exports[coreRes]:GetItems(sourceId)
    end)
    
    if success2 and type(result2) == "table" then
        return result2
    end
    
    return {}
end

function GetPlayerInventory(sourceId, playerObj)
    if Config.Inventory == "core" then
        return GetCoreInventoryItems(sourceId)
    end
    
    if Framework.Type == "qb" then
        if playerObj and playerObj.PlayerData and playerObj.PlayerData.items then
            return playerObj.PlayerData.items
        end
        return {}
    end
    
    if Framework.Type == "esx" then
        local esxPlayer = Framework.Core.GetPlayerFromId(sourceId)
        if not esxPlayer then
            return {}
        end
        if type(esxPlayer.getInventory) == "function" then
            return esxPlayer.getInventory() or {}
        end
        return esxPlayer.inventory or {}
    end
    
    return {}
end

function GetPlayerInsuranceStatus(sourceId)
    return Framework.GetMetaData(sourceId, "medical_insurance")
end

function HasMedicalInsurance(sourceId)
    local status = GetPlayerInsuranceStatus(sourceId)
    return status ~= nil and status ~= false and status ~= 0 and status ~= "0" and status ~= ""
end

Framework.CreateCallback("amb_server:getPharmacyData", function(source, cb)
    local playerObj = Framework.GetPlayer(source)
    if not playerObj then
        return cb(nil)
    end
    
    local playerCash = playerObj.functions.GetMoney("cash")
    local hasInsurance = HasMedicalInsurance(source)
    local isEms = exports.plt_ambulance_job:IsEMS(source)
    local prescriptions = {}
    
    if Config.Inventory == "ox" then
        local oxInv = exports.ox_inventory:GetInventory(source)
        local items = oxInv and oxInv.items or nil
        if items then
            for _, item in pairs(items) do
                if item.name == "plt_prescription" and item.metadata then
                    local pData = {}
                    for k, v in pairs(item.metadata) do
                        pData[k] = v
                    end
                    pData.slot = item.slot
                    table.insert(prescriptions, pData)
                end
            end
        end
    else
        local invItems = GetPlayerInventory(source, playerObj)
        for slot, item in pairs(invItems) do
            local meta = item and (item.info or item.metadata) or nil
            if item and item.name == "plt_prescription" and meta then
                local pData = {}
                for k, v in pairs(meta) do
                    pData[k] = v
                end
                pData.slot = item.slot or slot
                table.insert(prescriptions, pData)
            end
        end
    end
    
    local pharmacyData = {
        items = Config.Pharmacy.Items,
        cash = playerCash,
        hasInsurance = hasInsurance,
        insuranceCost = Config.Pharmacy.Insurance and Config.Pharmacy.Insurance.Price,
        insuranceDiscount = Config.Pharmacy.Insurance and Config.Pharmacy.Insurance.Discount,
        isEMS = isEms,
        prescriptions = prescriptions
    }
    cb(pharmacyData)
end)

Framework.CreateCallback("amb_server:getPlayerData", function(source, cb, targetId)
    local playerObj = Framework.GetPlayer(targetId)
    if playerObj then
        cb({ name = playerObj.name })
    else
        cb(nil)
    end
end)

Framework.CreateCallback("amb_server:checkPrescription", function(source, cb)
    local playerObj = Framework.GetPlayer(source)
    if not playerObj then
        return cb(nil)
    end
    
    local itemsList = {}
    if Config.Inventory == "ox" then
        local oxInv = exports.ox_inventory:GetInventory(source)
        itemsList = (oxInv and oxInv.items) or {}
    elseif Config.Inventory == "core" then
        itemsList = GetCoreInventoryItems(source)
    else
        itemsList = GetPlayerInventory(source, playerObj)
    end
    
    for _, item in pairs(itemsList) do
        if item.name == "plt_prescription" then
            local meta = nil
            if Config.Inventory == "ox" or Config.Inventory == "core" then
                meta = item.metadata
            end
            if not meta then
                meta = item.info or item.metadata
            end
            if meta then
                return cb(meta)
            end
        end
    end
    cb(nil)
end)

RegisterNetEvent("amb_server:buyInsurance", function(dummyArg, linkedJob)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then return end
    
    print(string.format("[PHARMACY] buyInsurance event from %s", tostring(src)))
    
    local function UpdateClientPharmacyData()
        TriggerClientEvent("amb_client:updateInsuranceStatus", src, HasMedicalInsurance(src))
        TriggerClientEvent("amb_client:updatePharmacyCash", src, playerObj.functions.GetMoney("cash"))
        TriggerClientEvent("amb_client:refreshPharmacyData", src)
    end
    
    if HasMedicalInsurance(src) then
        Framework.Notify(src, "You already have medical insurance.", "info")
        UpdateClientPharmacyData()
        return
    end
    
    local insPrice = tonumber(Config.Pharmacy and Config.Pharmacy.Insurance and Config.Pharmacy.Insurance.Price) or 0
    if insPrice <= 0 then
        Framework.Notify(src, "Insurance is not configured correctly.", "error")
        UpdateClientPharmacyData()
        return
    end
    
    if playerObj.functions.RemoveMoney("cash", insPrice, "medical-insurance") then
        local targetJob = linkedJob
        if type(linkedJob) == "string" and linkedJob ~= "" then
            targetJob = linkedJob
        else
            targetJob = true
        end
        
        Framework.SetMetaData(src, "medical_insurance", targetJob)
        Framework.Notify(src, _L("insurance_purchased"), "success")
        UpdateClientPharmacyData()
        
        if Framework.Type == "esx" then
            local esxTarget = (type(targetJob) == "string" and targetJob ~= "") and targetJob or 1
            local identifier = playerObj.identifier or playerObj.citizenid
            if identifier then
                pcall(function()
                    MySQL.Sync.execute("UPDATE users SET medical_insurance = ? WHERE identifier = ?", { esxTarget, identifier })
                end)
            end
        end
        
        local financeDept = (type(linkedJob) == "string" and linkedJob ~= "") and linkedJob or (Config.Medical and Config.Medical.EMSJobs and Config.Medical.EMSJobs[1] or "ambulance")
        
        if type(AddFinanceEntry) == "function" then
            AddFinanceEntry(financeDept, "deposit", insPrice, "Insurance Purchase: " .. playerObj.name, "PHARMACY")
        end
    else
        Framework.Notify(src, _L("not_enough_cash"), "error")
        UpdateClientPharmacyData()
    end
end)

function String(val)
    return tostring(val or "")
end

RegisterNetEvent("amb_server:purchasePharmacyItem", function(data)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then return end
    
    local itemName = data.item
    local itemPrice = data.price
    local quantity = tonumber(data.quantity) or 1
    local prescriptionSlots = data.prescriptionSlots or {}
    
    if quantity < 1 then quantity = 1 end
    
    local itemConfig = nil
    for _, item in ipairs(Config.Pharmacy.Items) do
        if item.name:lower() == itemName:lower() then
            itemConfig = item
            break
        end
    end
    
    if not itemConfig then
        Framework.Notify(src, _L("item_not_found"), "error")
        return
    end
    
    local finalPrice = itemConfig.price
    if HasMedicalInsurance(src) and not itemConfig.professionalOnly then
        finalPrice = math.floor(itemConfig.price * Config.Pharmacy.Insurance.Discount)
    end
    
    local totalCost = finalPrice * quantity
    
    if itemConfig.professionalOnly then
        if not exports.plt_ambulance_job:IsEMS(src) then
            Framework.Notify(src, _L("authorized_only_bang"), "error")
            return
        end
    end
    
    local isEms = exports.plt_ambulance_job:IsEMS(src)
    if itemConfig.prescriptionRequired and #prescriptionSlots > 0 and not isEms then
        if itemConfig.prescriptionRequired and quantity > #prescriptionSlots then
            Framework.Notify(src, _L("not_enough_prescriptions"), "error")
            return
        end
        
        local slotsToRemove = math.min(#prescriptionSlots, quantity)
        for i = 1, slotsToRemove do
            if prescriptionSlots[i] then
                Framework.RemoveItem(src, "plt_prescription", 1, prescriptionSlots[i])
            end
        end
    elseif data.prescription then
        if String(data.prescription.item):lower():gsub("%s+", "") == String(itemName):lower():gsub("%s+", "") then
            if data.prescription.slot then
                Framework.RemoveItem(src, "plt_prescription", 1, data.prescription.slot)
            end
        end
    end
    
    if totalCost > playerObj.functions.GetMoney("cash") then
        Framework.Notify(src, _L("not_enough_cash"), "error")
        return
    end
    
    if playerObj.functions.RemoveMoney("cash", totalCost, "pharmacy-purchase") then
        local itemMeta = {}
        if #prescriptionSlots > 0 then
            if Config.Inventory == "ox" then
                local oxInv = exports.ox_inventory:GetInventory(src)
                if oxInv and oxInv.items then
                    for _, item in pairs(oxInv.items) do
                        if item.name == "plt_prescription" and item.slot == prescriptionSlots[1] then
                            if item.metadata and item.metadata.duration then
                                itemMeta.duration = tonumber(item.metadata.duration)
                            end
                            break
                        end
                    end
                end
            else
                local pInv = GetPlayerInventory(src, playerObj)
                for slot, item in pairs(pInv) do
                    local targetSlot = item.slot or slot
                    if item.name == "plt_prescription" and targetSlot == prescriptionSlots[1] then
                        local meta = item.info or item.metadata
                        if meta and meta.duration then
                            itemMeta.duration = tonumber(meta.duration)
                        end
                        break
                    end
                end
            end
        end
        
        print(string.format("[PHARMACY] Adding %s with duration metadata: %s", itemName, tostring(itemMeta.duration)))
        
        Framework.AddItem(src, itemName, quantity, itemMeta)
        
        local qtyStr = quantity > 1 and (" x" .. quantity) or ""
        Framework.Notify(src, _L("purchase_successful", { label = itemConfig.label, qty = qtyStr }), "success")
        
        TriggerClientEvent("amb_client:updatePharmacyCash", src, playerObj.functions.GetMoney("cash"))
        TriggerClientEvent("amb_client:refreshPharmacyData", src)
        
        local deptLink = data.linkedJob or (Config.Medical and Config.Medical.EMSJobs and Config.Medical.EMSJobs[1] or "ambulance")
        local logQtyStr = quantity > 1 and (" x" .. quantity) or ""
        AddFinanceEntry(deptLink, "deposit", totalCost, "Pharmacy Sale: " .. itemConfig.label .. logQtyStr .. " (" .. playerObj.name .. ")", "PHARMACY")
    end
end)

RegisterNetEvent("amb_server:issuePrescription", function(data)
    local src = source
    local medicObj = Framework.GetPlayer(src)
    if not medicObj then return end
    
    if not exports.plt_ambulance_job:IsEMS(src) then return end
    
    local targetObj = Framework.GetPlayer(data.targetSrc)
    if not targetObj then return end
    
    local prescriptionMeta = {
        item = data.item,
        itemLabel = data.itemLabel,
        quantity = data.quantity or 1,
        patientName = targetObj.name,
        doctorName = medicObj.name,
        doctorDept = medicObj.job.label or "Medical Services",
        notes = data.notes,
        duration = tonumber(data.duration) or 10,
        issuedAt = os.date("%Y-%m-%d %H:%M:%S")
    }
    
    Framework.AddItem(data.targetSrc, "plt_prescription", 1, prescriptionMeta)
    Framework.Notify(src, _L("prescription_issued_to", { name = targetObj.name }), "success")
    Framework.Notify(data.targetSrc, _L("prescription_received"), "info")
end)

Framework.CreateUseableItem("plt_prescription", function(source, itemData)
    local meta = nil
    if Config.Inventory == "ox" or Config.Inventory == "core" then
        meta = itemData.metadata
    else
        meta = itemData.info or itemData.metadata
    end
    
    if meta then
        TriggerClientEvent("amb_client:viewPrescription", source, meta)
    end
end)
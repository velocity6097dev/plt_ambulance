local ActiveBagsMap = {}
local FallbackBagInventories = {}
local PlayerHeldBagIds = {}

function GenerateBagId(optionalSeed)
    local timestamp = os.time()
    local randomSeed = optionalSeed
    if not optionalSeed then
        randomSeed = math.random(1000, 9999)
    end
    return string.format("plt_medical_bag_%s_%s", tostring(timestamp), tostring(randomSeed))
end

function GetPlayerBagId(sourceId, targetSlot)
    local targetSlotNum = tonumber(targetSlot)
    
    if GetResourceState("ox_inventory") == "started" then
        local oxInventory = exports.ox_inventory:GetInventory(sourceId)
        if oxInventory and oxInventory.items then
            for _, item in pairs(oxInventory.items) do
                if item and item.name == "plt_medical_bag" then
                    local itemSlot = tonumber(item.slot)
                    if (targetSlotNum and itemSlot == targetSlotNum) or not targetSlotNum then
                        local meta = item.metadata or item.info
                        if meta and meta.bagId and tostring(meta.bagId) ~= "" then
                            return tostring(meta.bagId)
                        end
                        if targetSlotNum then
                            break
                        end
                    end
                end
            end
        end
    end

    local playerObj = Framework.GetPlayer(sourceId)
    if playerObj and playerObj.PlayerData and playerObj.PlayerData.items then
        for _, item in pairs(playerObj.PlayerData.items) do
            if item and item.name == "plt_medical_bag" then
                local itemSlot = tonumber(item.slot)
                if (targetSlotNum and itemSlot == targetSlotNum) or not targetSlotNum then
                    local meta = item.metadata or item.info
                    if meta and meta.bagId and tostring(meta.bagId) ~= "" then
                        return tostring(meta.bagId)
                    end
                    if targetSlotNum then
                        break
                    end
                end
            end
        end
    end
    return nil
end

function IsQuasarInventory()
    local invConfig = tostring(Config.Inventory or ""):lower()
    return invConfig == "quasar"
end

function GetFallbackBagInventory(bagId)
    if not bagId then
        return nil
    end
    if not FallbackBagInventories[bagId] then
        FallbackBagInventories[bagId] = {
            items = {},
            maxWeight = 50000,
            maxSlots = 20
        }
    end
    return FallbackBagInventories[bagId]
end

function GetItemCount(itemData)
    local count = tonumber(itemData and (itemData.amount or itemData.count or itemData.quantity))
    return count or 0
end

function GetItemWeight(itemData)
    local weight = tonumber(itemData and itemData.weight)
    return weight or 0
end

function GetFormattedPlayerInventory(sourceId)
    local inventory = {}
    local playerObj = Framework.GetPlayer(sourceId)
    
    if playerObj and playerObj.PlayerData and playerObj.PlayerData.items then
        for _, item in pairs(playerObj.PlayerData.items) do
            if item then
                local count = GetItemCount(item)
                if count > 0 then
                    table.insert(inventory, {
                        name = item.name,
                        label = item.label or item.name,
                        count = count,
                        slot = tonumber(item.slot),
                        weight = GetItemWeight(item)
                    })
                end
            end
        end
    end
    return inventory
end

function GetPlayerItemBySlot(sourceId, slotData)
    local slotNum = tonumber(slotData)
    if not slotNum then return nil end
    
    local formattedInv = GetFormattedPlayerInventory(sourceId)
    for _, item in ipairs(formattedInv) do
        if tonumber(item.slot) == slotNum then
            return item
        end
    end
    return nil
end

function RemoveBagItem(sourceId, slotData)
    local success = false
    if slotData then
        success = Framework.RemoveItem(sourceId, "plt_medical_bag", 1, slotData)
        if not success then
            success = Framework.RemoveItem(sourceId, "plt_medical_bag", 1)
        end
    else
        success = Framework.RemoveItem(sourceId, "plt_medical_bag", 1)
    end
    return success == true
end

function AddBagItem(sourceId, bagData)
    if Framework.AddItem(sourceId, "plt_medical_bag", 1, bagData) then
        return true, true
    end
    if Framework.AddItem(sourceId, "plt_medical_bag", 1) then
        return true, false
    end
    return false, false
end

function CalculateBagWeight(bagInventory)
    local totalWeight = 0
    for _, item in ipairs(bagInventory.items or {}) do
        local weight = tonumber(item.weight) or 0
        local count = tonumber(item.count) or 0
        totalWeight = totalWeight + (weight * count)
    end
    return totalWeight
end

function GetBagItemBySlot(bagInventory, slotData)
    local slotNum = tonumber(slotData)
    if not slotNum then return nil, nil end
    
    for idx, item in ipairs(bagInventory.items or {}) do
        if tonumber(item.slot) == slotNum then
            return item, idx
        end
    end
    return nil, nil
end

function GetFirstEmptyBagSlot(bagInventory)
    local usedSlots = {}
    for _, item in ipairs(bagInventory.items or {}) do
        if item.slot then
            usedSlots[tonumber(item.slot)] = true
        end
    end
    
    local maxSlots = tonumber(bagInventory.maxSlots) or 20
    for i = 1, maxSlots do
        if not usedSlots[i] then
            return i
        end
    end
    return nil
end

CreateThread(function()
    Wait(1000)
    Framework.CreateUseableItem("plt_medical_bag", function(source, itemData)
        TriggerClientEvent("amb_client:useMedicalBag", source, itemData)
    end)
end)

function FetchBagData(sourceId, netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        return nil
    end
    
    local bagId = nil
    if ActiveBagsMap[netId] and ActiveBagsMap[netId].id then
        bagId = ActiveBagsMap[netId].id
    else
        bagId = Entity(entity).state.bagId
    end
    
    if not bagId then return nil end

    local bagItems = {}
    local bagWeight = 0
    local bagMaxWeight = 50000
    local bagMaxSlots = 20
    
    print("^3[PLT_BAG] Fetching inventory for Player: " .. tostring(sourceId) .. " and Bag: " .. tostring(bagId) .. "^7")
    
    local invType = Config.Inventory
    if invType == "ox" then
        exports.ox_inventory:RegisterStash(bagId, "Medical Bag", bagMaxSlots, bagMaxWeight)
        local oxInv = exports.ox_inventory:GetInventory(bagId)
        if oxInv and oxInv.items then
            for _, item in pairs(oxInv.items) do
                local count = GetItemCount(item)
                local weight = GetItemWeight(item)
                table.insert(bagItems, {
                    name = item.name,
                    label = item.label,
                    count = count,
                    slot = tonumber(item.slot),
                    weight = weight
                })
                bagWeight = bagWeight + (weight * count)
            end
        end
    elseif IsQuasarInventory() then
        local fallbackBag = GetFallbackBagInventory(bagId)
        bagMaxWeight = tonumber(fallbackBag.maxWeight) or bagMaxWeight
        bagMaxSlots = tonumber(fallbackBag.maxSlots) or bagMaxSlots
        
        for _, item in ipairs(fallbackBag.items or {}) do
            local count = GetItemCount(item)
            local weight = GetItemWeight(item)
            table.insert(bagItems, {
                name = item.name,
                label = item.label or item.name,
                count = count,
                slot = tonumber(item.slot),
                weight = weight
            })
            bagWeight = bagWeight + (weight * count)
        end
    elseif invType == "qb" or invType == "tgiann" then
        local stashItems = exports["qb-inventory"]:GetStashItems(bagId)
        if stashItems then
            for _, item in pairs(stashItems) do
                local count = GetItemCount(item)
                local weight = GetItemWeight(item)
                table.insert(bagItems, {
                    name = item.name,
                    label = item.label,
                    count = count,
                    slot = tonumber(item.slot),
                    weight = weight
                })
                bagWeight = bagWeight + (weight * count)
            end
        end
    end
    
    local playerItems = {}
    local playerWeight = 0
    local playerMaxWeight = 30000
    local playerMaxSlots = 30
    
    if GetResourceState("ox_inventory") == "started" then
        local oxPlayerInv = exports.ox_inventory:GetInventory(sourceId)
        if oxPlayerInv and oxPlayerInv.items then
            print("^2[PLT_BAG] Ox Inventory detected. Found " .. tostring(#oxPlayerInv.items) .. " item slots occupied.^7")
            playerMaxWeight = oxPlayerInv.maxWeight
            playerMaxSlots = oxPlayerInv.slots
            
            for _, item in pairs(oxPlayerInv.items) do
                local count = GetItemCount(item)
                local weight = GetItemWeight(item)
                table.insert(playerItems, {
                    name = item.name,
                    label = item.label,
                    count = count,
                    slot = tonumber(item.slot),
                    weight = weight
                })
                playerWeight = playerWeight + (weight * count)
            end
        end
    elseif invType == "qb" or invType == "tgiann" or invType == "quasar" or invType == "origin" then
        local formattedInv = GetFormattedPlayerInventory(sourceId)
        if #formattedInv > 0 then
            print("^2[PLT_BAG] QB Inventory detected.^7")
            for _, item in ipairs(formattedInv) do
                table.insert(playerItems, item)
                local weight = tonumber(item.weight) or 0
                local count = tonumber(item.count) or 0
                playerWeight = playerWeight + (weight * count)
            end
            playerMaxSlots = 40
            playerMaxWeight = 120000
        end
    end
    
    print("^2[PLT_BAG] Total player items formatted: " .. tostring(#playerItems) .. "^7")
    
    return {
        bagId = bagId,
        netId = netId,
        items = bagItems,
        weight = bagWeight,
        maxWeight = bagMaxWeight,
        maxSlots = bagMaxSlots,
        playerItems = playerItems,
        playerWeight = playerWeight,
        playerMaxWeight = playerMaxWeight,
        playerMaxSlots = playerMaxSlots
    }
end

RegisterNetEvent("amb_server:dropMedicalBag", function(coords, heading, incomingBagId, slotData)
    local src = source
    local propHash = -1187210516
    local slotNum = tonumber(slotData)
    local activeBagId = nil
    
    if incomingBagId and tostring(incomingBagId) ~= "" then
        activeBagId = incomingBagId
    end
    
    if not activeBagId or tostring(activeBagId) == "" then
        activeBagId = GetPlayerBagId(src, slotNum)
    end
    
    if not activeBagId or tostring(activeBagId) == "" then
        activeBagId = PlayerHeldBagIds[src]
    end
    
    if not activeBagId or tostring(activeBagId) == "" then
        activeBagId = GenerateBagId(slotNum or src)
    end
    
    if RemoveBagItem(src, slotNum) then
        local bagProp = CreateObject(propHash, coords.x, coords.y, coords.z - 0.4, true, true, true)
        while not DoesEntityExist(bagProp) do
            Wait(10)
        end
        
        SetEntityHeading(bagProp, heading)
        FreezeEntityPosition(bagProp, true)
        local netId = NetworkGetNetworkIdFromEntity(bagProp)
        Entity(bagProp).state:set("bagId", activeBagId, true)
        
        ActiveBagsMap[netId] = {
            id = activeBagId,
            entity = bagProp
        }
        PlayerHeldBagIds[src] = nil
        TriggerClientEvent("amb_client:Notify", src, "Bag dropped.", "success")
    else
        PlayerHeldBagIds[src] = activeBagId
        TriggerClientEvent("amb_client:Notify", src, "Failed to drop bag from inventory.", "error")
    end
end)

RegisterNetEvent("amb_server:openBagInventory", function(netId)
    local src = source
    local bagData = FetchBagData(src, netId)
    if bagData then
        TriggerClientEvent("amb_client:openBagUI", src, bagData)
    end
end)

RegisterNetEvent("amb_server:takeBagItem", function(data)
    local src = source
    local bagId = data.bagId
    local slot = data.slot
    local requestAmount = tonumber(data.amount) or 1
    
    if IsQuasarInventory() then
        local bagInv = GetFallbackBagInventory(bagId)
        local bagItem, itemIndex = GetBagItemBySlot(bagInv, slot)
        
        if not bagItem then return end
        
        local currentCount = tonumber(bagItem.count) or 0
        if currentCount <= 0 then return end
        
        local takeAmount = math.min(requestAmount, currentCount)
        if takeAmount <= 0 then return end
        
        if not Framework.CanCarryItem(src, bagItem.name, takeAmount) then
            Framework.Notify(src, _L("cannot_carry_this_much"), "error")
            return
        end
        
        if not Framework.AddItem(src, bagItem.name, takeAmount) then
            Framework.Notify(src, _L("cannot_carry_this_much"), "error")
            return
        end
        
        bagItem.count = currentCount - takeAmount
        if (tonumber(bagItem.count) or 0) <= 0 then
            table.remove(bagInv.items, itemIndex)
        end
        
        local updatedBagData = FetchBagData(src, data.netId)
        if updatedBagData then
            TriggerClientEvent("amb_client:openBagUI", src, updatedBagData)
        end
        return
    end

    if Config.Inventory ~= "ox" then
        Framework.Notify(src, "Medical bag transfer currently supports ox/quasar inventory modes.", "error")
        return
    end
    
    local oxBagInv = exports.ox_inventory:GetInventory(bagId)
    local items = oxBagInv and oxBagInv.items or {}
    local targetItem = nil
    
    for _, item in pairs(items) do
        if item.slot == slot then
            targetItem = item
            break
        end
    end
    
    if targetItem then
        local takeAmount = requestAmount
        if requestAmount == 0 or not targetItem.count then
            takeAmount = targetItem.count
        else
            takeAmount = math.min(requestAmount, targetItem.count)
        end
        
        if exports.ox_inventory:CanCarryItem(src, targetItem.name, takeAmount) then
            exports.ox_inventory:RemoveItem(bagId, targetItem.name, takeAmount, nil, slot)
            exports.ox_inventory:AddItem(src, targetItem.name, takeAmount)
            Wait(100)
            
            local updatedBagData = FetchBagData(src, data.netId)
            if updatedBagData then
                TriggerClientEvent("amb_client:openBagUI", src, updatedBagData)
            end
        else
            Framework.Notify(src, _L("cannot_carry_this_much"), "error")
        end
    end
end)

RegisterNetEvent("amb_server:storeInBag", function(data)
    local src = source
    local bagId = data.bagId
    local slot = data.slot
    local requestAmount = tonumber(data.amount) or 1
    
    if IsQuasarInventory() then
        local playerItem = GetPlayerItemBySlot(src, slot)
        if not playerItem then return end
        if playerItem.name == "plt_medical_bag" then return end
        
        local currentCount = tonumber(playerItem.count) or 0
        if currentCount <= 0 then return end
        
        local storeAmount = math.min(requestAmount, currentCount)
        if storeAmount <= 0 then return end
        
        local bagInv = GetFallbackBagInventory(bagId)
        local playerItemWeight = tonumber(playerItem.weight) or 0
        
        local currentBagWeight = CalculateBagWeight(bagInv)
        local weightToAdd = playerItemWeight * storeAmount
        local bagMaxWeight = tonumber(bagInv.maxWeight) or 50000
        
        if (currentBagWeight + weightToAdd) > bagMaxWeight then
            Framework.Notify(src, _L("bag_is_full"), "error")
            return
        end
        
        local existingBagItem = nil
        for _, item in ipairs(bagInv.items) do
            if tostring(item.name) == tostring(playerItem.name) then
                existingBagItem = item
                break
            end
        end
        
        if not existingBagItem then
            if #bagInv.items >= (tonumber(bagInv.maxSlots) or 20) then
                Framework.Notify(src, _L("bag_is_full"), "error")
                return
            end
        end
        
        local itemRemoved = Framework.RemoveItem(src, playerItem.name, storeAmount, playerItem.slot)
        if not itemRemoved then
            itemRemoved = Framework.RemoveItem(src, playerItem.name, storeAmount)
        end
        
        if not itemRemoved then
            Framework.Notify(src, _L("cannot_carry_this_much"), "error")
            return
        end
        
        if existingBagItem then
            existingBagItem.count = (tonumber(existingBagItem.count) or 0) + storeAmount
            existingBagItem.weight = playerItemWeight
            existingBagItem.label = existingBagItem.label or playerItem.label or playerItem.name
        else
            local emptySlot = GetFirstEmptyBagSlot(bagInv)
            if not emptySlot then
                Framework.AddItem(src, playerItem.name, storeAmount)
                Framework.Notify(src, _L("bag_is_full"), "error")
                return
            end
            
            table.insert(bagInv.items, {
                name = playerItem.name,
                label = playerItem.label or playerItem.name,
                count = storeAmount,
                slot = emptySlot,
                weight = playerItemWeight
            })
        end
        
        local updatedBagData = FetchBagData(src, data.netId)
        if updatedBagData then
            TriggerClientEvent("amb_client:openBagUI", src, updatedBagData)
        end
        return
    end

    if Config.Inventory ~= "ox" then
        Framework.Notify(src, "Medical bag transfer currently supports ox/quasar inventory modes.", "error")
        return
    end
    
    local oxPlayerInv = exports.ox_inventory:GetInventory(src)
    local items = oxPlayerInv and oxPlayerInv.items or {}
    local targetItem = nil
    
    for _, item in pairs(items) do
        if item.slot == slot then
            targetItem = item
            break
        end
    end
    
    if targetItem then
        local storeAmount = requestAmount
        if requestAmount == 0 or not targetItem.count then
            storeAmount = targetItem.count
        else
            storeAmount = math.min(requestAmount, targetItem.count)
        end
        
        if exports.ox_inventory:AddItem(bagId, targetItem.name, storeAmount) then
            exports.ox_inventory:RemoveItem(src, targetItem.name, storeAmount, nil, slot)
            Wait(100)
            
            local updatedBagData = FetchBagData(src, data.netId)
            if updatedBagData then
                TriggerClientEvent("amb_client:openBagUI", src, updatedBagData)
            end
        else
            Framework.Notify(src, _L("bag_is_full"), "error")
        end
    end
end)

RegisterNetEvent("amb_server:pickupMedicalBag", function(netId)
    local src = source
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then return end
    
    local bagId = nil
    if ActiveBagsMap[netId] and ActiveBagsMap[netId].id then
        bagId = ActiveBagsMap[netId].id
    else
        bagId = Entity(entity).state.bagId
    end
    
    local coords = GetEntityCoords(entity)
    local heading = GetEntityHeading(entity)
    DeleteEntity(entity)
    ActiveBagsMap[netId] = nil
    
    local bagData = nil
    if bagId then
        bagData = { bagId = bagId }
    end
    
    local added, hadMeta = AddBagItem(src, bagData)
    if not added then
        local replacementBag = CreateObject(-1187210516, coords.x, coords.y, coords.z, true, true, true)
        if DoesEntityExist(replacementBag) then
            SetEntityHeading(replacementBag, heading)
            FreezeEntityPosition(replacementBag, true)
            local newNetId = NetworkGetNetworkIdFromEntity(replacementBag)
            Entity(replacementBag).state:set("bagId", bagId, true)
            
            ActiveBagsMap[newNetId] = {
                id = bagId,
                entity = replacementBag
            }
        end
        Framework.Notify(src, _L("cannot_carry_more_item"), "error")
        return
    end
    
    if bagId then
        PlayerHeldBagIds[src] = bagId
    end
    
    if IsQuasarInventory() and hadMeta ~= true then
        Framework.Notify(src, "Bag picked up (metadata fallback active for qs/quasar).", "info")
    end
    
    TriggerClientEvent("amb_client:Notify", src, "Bag picked up.", "success")
end)

AddEventHandler("playerDropped", function()
    local src = source
    PlayerHeldBagIds[src] = nil
end)
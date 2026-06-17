local ActiveBags = {}
local BagInventories = {}
local PlayerBagIds = {}

-- ==========================================
-- Utility Functions
-- ==========================================

local function GenerateBagId(existingId)
    local randomPart = existingId or math.random(1000, 9999)
    return string.format("plt_medical_bag_%s_%s", os.time(), randomPart)
end

local function GetBagIdFromPlayer(source, slot)
    local targetSlot = tonumber(slot)
    
    -- Check OX Inventory
    if GetResourceState("ox_inventory") == "started" then
        local inv = exports.ox_inventory:GetInventory(source)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                if item and item.name == "plt_medical_bag" then
                    local itemSlot = tonumber(item.slot)
                    if not targetSlot or itemSlot == targetSlot then
                        local metadata = item.metadata or item.info
                        if metadata and metadata.bagId and tostring(metadata.bagId) ~= "" then
                            return tostring(metadata.bagId), itemSlot
                        end
                        if targetSlot then break end
                    end
                end
            end
        end
    end

    -- Check Default/QB Inventory
    local player = Framework.GetPlayer(source)
    if player and player.PlayerData and player.PlayerData.items then
        for _, item in pairs(player.PlayerData.items) do
            if item and item.name == "plt_medical_bag" then
                local itemSlot = tonumber(item.slot)
                if not targetSlot or itemSlot == targetSlot then
                    local metadata = item.metadata or item.info
                    if metadata and metadata.bagId and tostring(metadata.bagId) ~= "" then
                        return tostring(metadata.bagId), itemSlot
                    end
                    if targetSlot then break end
                end
            end
        end
    end

    return nil, nil
end

local function IsQuasarInventory()
    local invType = string.lower(tostring(Config.Inventory or ""))
    return invType == "quasar"
end

local function GetBagInventory(bagId)
    if not bagId then return nil end
    if not BagInventories[bagId] then
        BagInventories[bagId] = {
            items = {},
            maxWeight = 50000,
            maxSlots = 20
        }
    end
    return BagInventories[bagId]
end

local function GetItemCount(itemData)
    local count = itemData and (itemData.amount or itemData.count or itemData.quantity)
    return tonumber(count) or 0
end

local function GetItemWeight(itemData)
    local weight = itemData and itemData.weight
    return tonumber(weight) or 0
end

local function GetPlayerFormattedInventory(source)
    local formatted = {}
    local player = Framework.GetPlayer(source)
    
    if player and player.PlayerData and player.PlayerData.items then
        for _, item in pairs(player.PlayerData.items) do
            if item then
                local count = GetItemCount(item)
                if count > 0 then
                    table.insert(formatted, {
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
    return formatted
end

local function GetPlayerItemBySlot(source, slot)
    local targetSlot = tonumber(slot)
    if not targetSlot then return nil end

    local inventory = GetPlayerFormattedInventory(source)
    for _, item in ipairs(inventory) do
        if tonumber(item.slot) == targetSlot then
            return item
        end
    end
    return nil
end

local function RemoveMedicalBag(source, slot)
    local removed = false
    if slot then
        removed = Framework.RemoveItem(source, "plt_medical_bag", 1, slot)
        if not removed then
            removed = Framework.RemoveItem(source, "plt_medical_bag", 1)
        end
    else
        removed = Framework.RemoveItem(source, "plt_medical_bag", 1)
    end
    return removed == true
end

local function AddMedicalBag(source, metadata)
    if Framework.AddItem(source, "plt_medical_bag", 1, metadata) then
        return true, true -- success, metadataApplied
    elseif Framework.AddItem(source, "plt_medical_bag", 1) then
        return true, false -- success, metadataFailed
    end
    return false, false
end

local function CalculateBagWeight(bagData)
    local total = 0
    if bagData and bagData.items then
        for _, item in ipairs(bagData.items) do
            local w = tonumber(item.weight) or 0
            local c = tonumber(item.count) or 0
            total = total + (w * c)
        end
    end
    return total
end

local function GetBagItemBySlot(bagData, slot)
    local targetSlot = tonumber(slot)
    if not targetSlot or not bagData or not bagData.items then return nil, nil end
    
    for idx, item in ipairs(bagData.items) do
        if tonumber(item.slot) == targetSlot then
            return item, idx
        end
    end
    return nil, nil
end

local function GetBagFreeSlot(bagData)
    local occupied = {}
    if bagData and bagData.items then
        for _, item in ipairs(bagData.items) do
            if item.slot then occupied[tonumber(item.slot)] = true end
        end
    end
    
    local maxSlots = tonumber(bagData and bagData.maxSlots) or 20
    for i = 1, maxSlots do
        if not occupied[i] then return i end
    end
    return nil
end

-- ==========================================
-- Main Logic Functions
-- ==========================================

CreateThread(function()
    Wait(1000)
    Framework.CreateUseableItem("plt_medical_bag", function(source, itemData)
        TriggerClientEvent("amb_client:useMedicalBag", source, itemData)
    end)
end)

local function FetchBagDataForUI(source, netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then return nil end

    local bagId = nil
    if ActiveBags[netId] and ActiveBags[netId].id then
        bagId = ActiveBags[netId].id
    else
        local state = Entity(entity).state
        if state and state.bagId then bagId = state.bagId end
    end

    if not bagId then return nil end

    print(string.format("^3[PLT_BAG] Fetching inventory for Player: %s and Bag: %s^7", source, bagId))

    local bagItems = {}
    local currentWeight = 0
    local maxWeight = 50000
    local maxSlots = 20

    -- OX Inventory Logic
    if Config.Inventory == "ox" then
        exports.ox_inventory:RegisterStash(bagId, "Medical Bag", maxSlots, maxWeight)
        local inv = exports.ox_inventory:GetInventory(bagId)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                local c = GetItemCount(item)
                local w = GetItemWeight(item)
                table.insert(bagItems, {
                    name = item.name,
                    label = item.label,
                    count = c,
                    slot = tonumber(item.slot),
                    weight = w
                })
                currentWeight = currentWeight + (w * c)
            end
        end

    -- Custom Fallback (Quasar, Tgiann, QB)
    else
        if IsQuasarInventory() then
            local bagData = GetBagInventory(bagId)
            maxWeight = tonumber(bagData.maxWeight) or maxWeight
            maxSlots = tonumber(bagData.maxSlots) or maxSlots
            
            for _, item in ipairs(bagData.items or {}) do
                local c = GetItemCount(item)
                local w = GetItemWeight(item)
                table.insert(bagItems, {
                    name = item.name,
                    label = item.label or item.name,
                    count = c,
                    slot = tonumber(item.slot),
                    weight = w
                })
                currentWeight = currentWeight + (w * c)
            end
        else
            if Config.Inventory == "qb" or Config.Inventory == "tgiann" then
                local items = exports["qb-inventory"]:GetStashItems(bagId)
                if items then
                    for _, item in pairs(items) do
                        local c = GetItemCount(item)
                        local w = GetItemWeight(item)
                        table.insert(bagItems, {
                            name = item.name,
                            label = item.label,
                            count = c,
                            slot = tonumber(item.slot),
                            weight = w
                        })
                        currentWeight = currentWeight + (w * c)
                    end
                end
            end
        end
    end

    -- Parse Player Inventory for UI
    local playerItemsFormatted = {}
    local playerWeight = 0
    local playerMaxWeight = 120000
    local playerMaxSlots = 40

    if GetResourceState("ox_inventory") == "started" then
        local pInv = exports.ox_inventory:GetInventory(source)
        if pInv and pInv.items then
            print("^2[PLT_BAG] Ox Inventory detected. Found " .. #pInv.items .. " item slots occupied.^7")
            playerMaxWeight = pInv.maxWeight
            playerMaxSlots = pInv.slots
            
            for _, item in pairs(pInv.items) do
                local c = GetItemCount(item)
                local w = GetItemWeight(item)
                table.insert(playerItemsFormatted, {
                    name = item.name,
                    label = item.label,
                    count = c,
                    slot = tonumber(item.slot),
                    weight = w
                })
                playerWeight = playerWeight + (w * c)
            end
        end
    else
        local pItems = GetPlayerFormattedInventory(source)
        if #pItems > 0 then
            print("^2[PLT_BAG] QB Inventory detected.^7")
            for _, item in ipairs(pItems) do
                table.insert(playerItemsFormatted, item)
                local w = tonumber(item.weight) or 0
                local c = tonumber(item.count) or 0
                playerWeight = playerWeight + (w * c)
            end
        end
    end

    print("^2[PLT_BAG] Total player items formatted: " .. #playerItemsFormatted .. "^7")

    return {
        bagId = bagId,
        netId = netId,
        items = bagItems,
        weight = currentWeight,
        maxWeight = maxWeight,
        maxSlots = maxSlots,
        playerItems = playerItemsFormatted,
        playerWeight = playerWeight,
        playerMaxWeight = playerMaxWeight,
        playerMaxSlots = playerMaxSlots
    }
end

-- ==========================================
-- Net Events
-- ==========================================

RegisterNetEvent("amb_server:dropMedicalBag", function(coords, heading, metadata, optionalBagId)
    local src = source
    local bagModel = -1187210516 -- xm_prop_x17_bag_med_01a
    
    local targetBagId = tonumber(optionalBagId)
    if not targetBagId then
        targetBagId = metadata and type(metadata) == "string" and metadata ~= "" and metadata or nil
    end

    if not targetBagId then
        targetBagId = PlayerBagIds[src]
    end
    if not targetBagId then
        targetBagId = GenerateBagId(optionalBagId or src)
    end

    if RemoveMedicalBag(src, optionalBagId) then
        local bagObj = CreateObject(bagModel, coords.x, coords.y, coords.z - 0.4, true, true, true)
        
        while not DoesEntityExist(bagObj) do Wait(10) end
        
        SetEntityHeading(bagObj, heading)
        FreezeEntityPosition(bagObj, true)
        
        local netId = NetworkGetNetworkIdFromEntity(bagObj)
        Entity(bagObj).state:set("bagId", targetBagId, true)
        
        ActiveBags[netId] = { id = targetBagId, entity = bagObj }
        PlayerBagIds[src] = nil
        
        TriggerClientEvent("amb_client:Notify", src, "Bag dropped.", "success")
    else
        PlayerBagIds[src] = targetBagId
        TriggerClientEvent("amb_client:Notify", src, "Failed to drop bag from inventory.", "error")
    end
end)

RegisterNetEvent("amb_server:openBagInventory", function(netId)
    local src = source
    local uiData = FetchBagDataForUI(src, netId)
    if uiData then
        TriggerClientEvent("amb_client:openBagUI", src, uiData)
    end
end)

RegisterNetEvent("amb_server:takeBagItem", function(data)
    local src = source
    local bagId = data.bagId
    local targetSlot = data.slot
    local amountToTake = tonumber(data.amount) or 1

    if IsQuasarInventory() then
        local bagInv = GetBagInventory(bagId)
        local bagItem, bagItemIndex = GetBagItemBySlot(bagInv, targetSlot)
        if not bagItem then return end
        
        local currentCount = tonumber(bagItem.count) or 0
        if currentCount <= 0 then return end
        
        local actualAmount = math.min(amountToTake, currentCount)
        if actualAmount <= 0 then return end

        if not Framework.CanCarryItem(src, bagItem.name, actualAmount) then
            return Framework.Notify(src, _L("cannot_carry_this_much"), "error")
        end

        if not Framework.AddItem(src, bagItem.name, actualAmount) then
            return Framework.Notify(src, _L("cannot_carry_this_much"), "error")
        end

        bagItem.count = bagItem.count - actualAmount
        if (tonumber(bagItem.count) or 0) <= 0 then
            table.remove(bagInv.items, bagItemIndex)
        end

        local updatedUIData = FetchBagDataForUI(src, data.netId)
        if updatedUIData then
            TriggerClientEvent("amb_client:openBagUI", src, updatedUIData)
        end
        return
    end

    if Config.Inventory ~= "ox" then
        return Framework.Notify(src, "Medical bag transfer currently supports ox/quasar inventory modes.", "error")
    end

    local oxInv = exports.ox_inventory:GetInventory(bagId)
    local items = oxInv and oxInv.items or {}
    local itemToTake = nil

    for _, item in pairs(items) do
        if item.slot == targetSlot then
            itemToTake = item
            break
        end
    end

    if itemToTake then
        local actualAmount = amountToTake == 0 and itemToTake.count or math.min(amountToTake, itemToTake.count)
        
        if exports.ox_inventory:CanCarryItem(src, itemToTake.name, actualAmount) then
            exports.ox_inventory:RemoveItem(bagId, itemToTake.name, actualAmount, nil, targetSlot)
            exports.ox_inventory:AddItem(src, itemToTake.name, actualAmount)
            
            Wait(100)
            local updatedUIData = FetchBagDataForUI(src, data.netId)
            if updatedUIData then
                TriggerClientEvent("amb_client:openBagUI", src, updatedUIData)
            end
        else
            Framework.Notify(src, _L("cannot_carry_this_much"), "error")
        end
    end
end)

RegisterNetEvent("amb_server:storeInBag", function(data)
    local src = source
    local bagId = data.bagId
    local targetSlot = data.slot
    local amountToStore = tonumber(data.amount) or 1

    if IsQuasarInventory() then
        local playerItem = GetPlayerItemBySlot(src, targetSlot)
        if not playerItem or playerItem.name == "plt_medical_bag" then return end

        local currentCount = tonumber(playerItem.count) or 0
        if currentCount <= 0 then return end
        
        local actualAmount = math.min(amountToStore, currentCount)
        if actualAmount <= 0 then return end

        local bagInv = GetBagInventory(bagId)
        local itemWeight = tonumber(playerItem.weight) or 0
        local newTotalWeight = CalculateBagWeight(bagInv) + (itemWeight * actualAmount)
        local maxWeight = tonumber(bagInv.maxWeight) or 50000

        if newTotalWeight > maxWeight then
            return Framework.Notify(src, _L("bag_is_full"), "error")
        end

        local existingItem = nil
        for _, item in ipairs(bagInv.items) do
            if tostring(item.name) == tostring(playerItem.name) then
                existingItem = item
                break
            end
        end

        if not existingItem then
            local maxSlots = tonumber(bagInv.maxSlots) or 20
            if #bagInv.items >= maxSlots then
                return Framework.Notify(src, _L("bag_is_full"), "error")
            end
        end

        local removed = Framework.RemoveItem(src, playerItem.name, actualAmount, playerItem.slot)
        if not removed then
            removed = Framework.RemoveItem(src, playerItem.name, actualAmount)
        end

        if not removed then
            return Framework.Notify(src, _L("cannot_carry_this_much"), "error")
        end

        if existingItem then
            existingItem.count = (tonumber(existingItem.count) or 0) + actualAmount
            existingItem.weight = itemWeight
            existingItem.label = existingItem.label or playerItem.label or playerItem.name
        else
            local freeSlot = GetBagFreeSlot(bagInv)
            if not freeSlot then
                Framework.AddItem(src, playerItem.name, actualAmount)
                return Framework.Notify(src, _L("bag_is_full"), "error")
            end
            
            table.insert(bagInv.items, {
                name = playerItem.name,
                label = playerItem.label or playerItem.name,
                count = actualAmount,
                slot = freeSlot,
                weight = itemWeight
            })
        end

        local updatedUIData = FetchBagDataForUI(src, data.netId)
        if updatedUIData then
            TriggerClientEvent("amb_client:openBagUI", src, updatedUIData)
        end
        return
    end

    if Config.Inventory ~= "ox" then
        return Framework.Notify(src, "Medical bag transfer currently supports ox/quasar inventory modes.", "error")
    end

    local oxInv = exports.ox_inventory:GetInventory(src)
    local items = oxInv and oxInv.items or {}
    local itemToStore = nil

    for _, item in pairs(items) do
        if item.slot == targetSlot then
            itemToStore = item
            break
        end
    end

    if itemToStore then
        local actualAmount = amountToStore == 0 and itemToStore.count or math.min(amountToStore, itemToStore.count)
        
        if exports.ox_inventory:AddItem(bagId, itemToStore.name, actualAmount) then
            exports.ox_inventory:RemoveItem(src, itemToStore.name, actualAmount, nil, targetSlot)
            
            Wait(100)
            local updatedUIData = FetchBagDataForUI(src, data.netId)
            if updatedUIData then
                TriggerClientEvent("amb_client:openBagUI", src, updatedUIData)
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
    if ActiveBags[netId] and ActiveBags[netId].id then
        bagId = ActiveBags[netId].id
    else
        local state = Entity(entity).state
        if state and state.bagId then bagId = state.bagId end
    end

    local coords = GetEntityCoords(entity)
    local heading = GetEntityHeading(entity)
    DeleteEntity(entity)
    
    ActiveBags[netId] = nil

    local metadata = bagId and { bagId = bagId } or nil
    local success, metadataApplied = AddMedicalBag(src, metadata)

    if not success then
        -- Inventory full, drop it back on the ground
        local fallbackBag = CreateObject(-1187210516, coords.x, coords.y, coords.z, true, true, true)
        if DoesEntityExist(fallbackBag) then
            SetEntityHeading(fallbackBag, heading)
            FreezeEntityPosition(fallbackBag, true)
            local newNetId = NetworkGetNetworkIdFromEntity(fallbackBag)
            Entity(fallbackBag).state:set("bagId", bagId, true)
            ActiveBags[newNetId] = { id = bagId, entity = fallbackBag }
        end
        return Framework.Notify(src, _L("cannot_carry_more_item"), "error")
    end

    if bagId then
        PlayerBagIds[src] = bagId
    end

    if IsQuasarInventory() and not metadataApplied then
        Framework.Notify(src, "Bag picked up (metadata fallback active for qs/quasar).", "info")
    end

    TriggerClientEvent("amb_client:Notify", src, "Bag picked up.", "success")
end)

AddEventHandler("playerDropped", function()
    local src = source
    PlayerBagIds[src] = nil
end)
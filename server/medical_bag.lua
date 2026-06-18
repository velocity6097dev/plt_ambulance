-- ============================================================
--  plt_ambulance  |  medical_bag.lua  (server-side)
--  Handles the physical medical bag item: dropping, picking up,
--  opening the bag inventory UI, transferring items in and out,
--  and managing bag state across multiple inventory systems
--  (ox_inventory, quasar/qs, qb-inventory, tgiann, origin).
-- ============================================================

-- ============================================================
--  State tables
-- ============================================================
local droppedBags   = {}  -- [netId]     = { id = bagId, entity = entityHandle }
local playerBagIds  = {}  -- [playerId]  = bagId  (bag the player most recently held)
local quasarBagData = {}  -- [bagId]     = { items, maxWeight, maxSlots }  (quasar fallback storage)

-- Bag object model hash (medical bag prop)
local BAG_MODEL_HASH = -1187210516

-- ============================================================
--  generateBagId(seed)
--  Creates a unique stash/bag identifier string.
--  Uses os.time() + an optional seed (or a random 4-digit number).
-- ============================================================
local function generateBagId(seed)
    local timestamp = tostring(os.time())
    local suffix    = tostring(seed or math.random(1000, 9999))
    return ("plt_medical_bag_%s_%s"):format(timestamp, suffix)
end

-- ============================================================
--  getBagIdFromPlayerInventory(playerId, slotNumber)
--  Searches the player's inventory for a plt_medical_bag item
--  and returns its bagId metadata string.
--  If slotNumber is provided, only matches that specific slot.
--  Tries ox_inventory first, then falls back to Framework.GetPlayer.
--  Returns: bagId string, or nil if not found.
-- ============================================================
local function getBagIdFromPlayerInventory(playerId, slotNumber)
    slotNumber = tonumber(slotNumber)

    -- Try ox_inventory first
    if GetResourceState("ox_inventory") == "started" then
        local inv = exports.ox_inventory:GetInventory(playerId)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                if item and item.name == "plt_medical_bag" then
                    local itemSlot = tonumber(item.slot)
                    if not slotNumber or itemSlot == slotNumber then
                        local meta  = item.metadata or item.info
                        local bagId = meta and meta.bagId and tostring(meta.bagId)
                        if bagId and bagId ~= "" then
                            return bagId
                        end
                        if slotNumber then break end
                    end
                end
            end
        end
    end

    -- Fallback: Framework PlayerData items
    local player = Framework.GetPlayer(playerId)
    if player and player.PlayerData and player.PlayerData.items then
        for _, item in pairs(player.PlayerData.items) do
            if item and item.name == "plt_medical_bag" then
                local itemSlot = tonumber(item.slot)
                if not slotNumber or itemSlot == slotNumber then
                    local meta  = item.metadata or item.info
                    local bagId = meta and meta.bagId and tostring(meta.bagId)
                    if bagId and bagId ~= "" then
                        return bagId
                    end
                    if slotNumber then break end
                end
            end
        end
    end

    return nil
end

-- ============================================================
--  isQuasarInventory()
--  Returns true if Config.Inventory is set to "quasar".
-- ============================================================
local function isQuasarInventory()
    return tostring(Config.Inventory or ""):lower() == "quasar"
end

-- ============================================================
--  getOrCreateQuasarBag(bagId)
--  Returns the in-memory quasar bag data table for the given
--  bagId, creating a default entry if one doesn't exist yet.
-- ============================================================
local function getOrCreateQuasarBag(bagId)
    if not bagId then return nil end
    if not quasarBagData[bagId] then
        quasarBagData[bagId] = { items = {}, maxWeight = 50000, maxSlots = 20 }
    end
    return quasarBagData[bagId]
end

-- ============================================================
--  getItemCount(item)
--  Reads the quantity from an item table, checking the common
--  field names: amount → count → quantity. Returns 0 on failure.
-- ============================================================
local function getItemCount(item)
    local count = tonumber(
        (item and (item.amount or item.count or item.quantity)) or nil
    )
    return count or 0
end

-- ============================================================
--  getItemWeight(item)
--  Reads the unit weight from an item table. Returns 0 on failure.
-- ============================================================
local function getItemWeight(item)
    return tonumber(item and item.weight) or 0
end

-- ============================================================
--  getPlayerItemList(playerId)
--  Returns a normalised array of the player's inventory items
--  (from Framework.PlayerData) with count > 0 only.
--  Each entry: { name, label, count, slot, weight }
-- ============================================================
local function getPlayerItemList(playerId)
    local result = {}
    local player = Framework.GetPlayer(playerId)
    if player and player.PlayerData and player.PlayerData.items then
        for _, item in pairs(player.PlayerData.items) do
            if item then
                local count = getItemCount(item)
                if count > 0 then
                    table.insert(result, {
                        name   = item.name,
                        label  = item.label or item.name,
                        count  = count,
                        slot   = tonumber(item.slot),
                        weight = getItemWeight(item),
                    })
                end
            end
        end
    end
    return result
end

-- ============================================================
--  getPlayerItemBySlot(playerId, slot)
--  Returns the normalised item at the given slot, or nil.
-- ============================================================
local function getPlayerItemBySlot(playerId, slot)
    slot = tonumber(slot)
    if not slot then return nil end
    for _, item in ipairs(getPlayerItemList(playerId)) do
        if tonumber(item.slot) == slot then return item end
    end
    return nil
end

-- ============================================================
--  removeBagFromInventory(playerId, slot)
--  Removes one plt_medical_bag from the player's inventory.
--  Tries with the slot id first, then without it as a fallback.
--  Returns true on success.
-- ============================================================
local function removeBagFromInventory(playerId, slot)
    local removed = false
    if slot then
        removed = Framework.RemoveItem(playerId, "plt_medical_bag", 1, slot) == true
        if not removed then
            removed = Framework.RemoveItem(playerId, "plt_medical_bag", 1) == true
        end
    else
        removed = Framework.RemoveItem(playerId, "plt_medical_bag", 1) == true
    end
    return removed
end

-- ============================================================
--  addBagToInventory(playerId, metadata)
--  Gives the player one plt_medical_bag item with the provided
--  metadata (contains bagId).
--  Returns: success (bool), metadataApplied (bool)
-- ============================================================
local function addBagToInventory(playerId, metadata)
    -- Try with metadata first (preserves bagId)
    if Framework.AddItem(playerId, "plt_medical_bag", 1, metadata) then
        return true, true
    end
    -- Fallback: add without metadata (bagId will be lost)
    if Framework.AddItem(playerId, "plt_medical_bag", 1) then
        return true, false
    end
    return false, false
end

-- ============================================================
--  calcBagTotalWeight(bagData)
--  Sums weight * count for every item in the bag.
-- ============================================================
local function calcBagTotalWeight(bagData)
    local total = 0
    for _, item in ipairs(bagData.items or {}) do
        local weight = tonumber(item.weight) or 0
        local count  = tonumber(item.count)  or 0
        total = total + (weight * count)
    end
    return total
end

-- ============================================================
--  getBagItemBySlot(bagData, slot)
--  Returns the item in bagData.items at the given slot number,
--  plus its index, or nil/nil if not found.
-- ============================================================
local function getBagItemBySlot(bagData, slot)
    slot = tonumber(slot)
    if not slot then return nil, nil end
    for i, item in ipairs(bagData.items or {}) do
        if tonumber(item.slot) == slot then
            return item, i
        end
    end
    return nil, nil
end

-- ============================================================
--  findFreeSlot(bagData)
--  Returns the lowest unused slot number within maxSlots,
--  or nil if the bag is full.
-- ============================================================
local function findFreeSlot(bagData)
    local used     = {}
    local maxSlots = tonumber(bagData.maxSlots) or 20
    for _, item in ipairs(bagData.items or {}) do
        if item.slot then
            used[tonumber(item.slot)] = true
        end
    end
    for s = 1, maxSlots do
        if not used[s] then return s end
    end
    return nil
end

-- ============================================================
--  Startup: register plt_medical_bag as a useable item.
--  Delayed by 1 second to ensure the Framework is ready.
-- ============================================================
CreateThread(function()
    Wait(1000)
    Framework.CreateUseableItem("plt_medical_bag", function(playerId, itemData)
        TriggerClientEvent("amb_client:useMedicalBag", playerId, itemData)
    end)
end)

-- ============================================================
--  getBagInventoryData(playerId, bagNetId)
--  Core function: resolves the bag entity from its network id,
--  determines the bagId, then builds a complete data payload
--  containing the bag's contents AND the player's items.
--  Supports ox_inventory, quasar, qb-inventory, tgiann, origin.
--  Returns a table or nil if the bag entity doesn't exist.
-- ============================================================
local function getBagInventoryData(playerId, bagNetId)
    local bagEntity = NetworkGetEntityFromNetworkId(bagNetId)
    if not DoesEntityExist(bagEntity) then return nil end

    -- Resolve bagId from server state or entity statebag
    local bagRecord = droppedBags[bagNetId]
    local bagId     = (bagRecord and bagRecord.id) or Entity(bagEntity).state.bagId
    if not bagId then return nil end

    -- Defaults
    local bagItems    = {}
    local bagWeight   = 0
    local maxWeight   = 50000
    local maxSlots    = 20

    print(("^3[PLT_BAG] Fetching inventory for Player: %s and Bag: %s^7"):format(playerId, bagId))

    local invType = Config.Inventory

    if invType == "ox" then
        -- ox_inventory: register the stash then pull items from it
        exports.ox_inventory:RegisterStash(bagId, "Medical Bag", maxSlots, maxWeight)
        local inv = exports.ox_inventory:GetInventory(bagId)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                local count      = getItemCount(item)
                local unitWeight = getItemWeight(item)
                table.insert(bagItems, {
                    name   = item.name,
                    label  = item.label,
                    count  = count,
                    slot   = tonumber(item.slot),
                    weight = unitWeight,
                })
                bagWeight = bagWeight + (unitWeight * count)
            end
        end

    elseif isQuasarInventory() then
        -- Quasar: use in-memory quasar bag data table
        local bagData = getOrCreateQuasarBag(bagId)
        maxWeight = tonumber(bagData.maxWeight) or maxWeight
        maxSlots  = tonumber(bagData.maxSlots)  or maxSlots
        for _, item in ipairs(bagData.items or {}) do
            local count      = getItemCount(item)
            local unitWeight = getItemWeight(item)
            table.insert(bagItems, {
                name   = item.name,
                label  = item.label or item.name,
                count  = count,
                slot   = tonumber(item.slot),
                weight = unitWeight,
            })
            bagWeight = bagWeight + (unitWeight * count)
        end

    elseif invType == "qb" or invType == "tgiann" then
        -- QBCore / tgiann: use qb-inventory GetStashItems export
        local stashItems = exports["qb-inventory"]:GetStashItems(bagId)
        if stashItems then
            for _, item in pairs(stashItems) do
                local count      = getItemCount(item)
                local unitWeight = getItemWeight(item)
                table.insert(bagItems, {
                    name   = item.name,
                    label  = item.label,
                    count  = count,
                    slot   = tonumber(item.slot),
                    weight = unitWeight,
                })
                bagWeight = bagWeight + (unitWeight * count)
            end
        end
    end

    -- Build the player's own item list (for the transfer UI)
    local playerItems     = {}
    local playerWeight    = 0
    local playerMaxWeight = 30000
    local playerMaxSlots  = 30

    -- Always try ox_inventory for the player side first
    if GetResourceState("ox_inventory") == "started" then
        local playerInv = exports.ox_inventory:GetInventory(playerId)
        if playerInv and playerInv.items then
            print(("^2[PLT_BAG] Ox Inventory detected. Found %d item slots occupied.^7"):format(#playerInv.items))
            playerMaxWeight = playerInv.maxWeight
            playerMaxSlots  = playerInv.slots
            for _, item in pairs(playerInv.items) do
                local count      = getItemCount(item)
                local unitWeight = getItemWeight(item)
                table.insert(playerItems, {
                    name   = item.name,
                    label  = item.label,
                    count  = count,
                    slot   = tonumber(item.slot),
                    weight = unitWeight,
                })
                playerWeight = playerWeight + (unitWeight * count)
            end
        end
    elseif invType == "qb" or invType == "tgiann" or invType == "quasar" or invType == "origin" then
        -- Framework fallback for qb/tgiann/quasar/origin
        local items = getPlayerItemList(playerId)
        if #items > 0 then
            print("^2[PLT_BAG] QB Inventory detected.^7")
            for _, item in ipairs(items) do
                table.insert(playerItems, item)
                playerWeight = playerWeight + ((item.weight or 0) * (item.count or 0))
            end
            playerMaxSlots  = 40
            playerMaxWeight = 120000
        end
    end

    print(("^2[PLT_BAG] Total player items formatted: %d^7"):format(#playerItems))

    return {
        bagId           = bagId,
        netId           = bagNetId,
        items           = bagItems,
        weight          = bagWeight,
        maxWeight       = maxWeight,
        maxSlots        = maxSlots,
        playerItems     = playerItems,
        playerWeight    = playerWeight,
        playerMaxWeight = playerMaxWeight,
        playerMaxSlots  = playerMaxSlots,
    }
end

-- ============================================================
--  Net event: amb_server:dropMedicalBag
--  Called when a player drops their bag at a world position.
--  Spawns the bag prop, sets its bagId statebag, and tracks it.
--  Args: coords (vector), heading, existingBagId, slotNumber
-- ============================================================
RegisterNetEvent("amb_server:dropMedicalBag", function(coords, heading, existingBagId, slotNumber)
    local caller = source
    local slot   = tonumber(slotNumber)

    -- Resolve the bag id to use for the dropped entity:
    -- 1. Use the provided existingBagId if valid
    -- 2. Look it up from the player's inventory cache
    -- 3. Fall back to the per-player session cache
    -- 4. Generate a fresh id as a last resort
    local bagId = (existingBagId and tostring(existingBagId) ~= "") and existingBagId or nil

    if not bagId then
        bagId = getBagIdFromPlayerInventory(caller, slot)
    end

    if not bagId or tostring(bagId) == "" then
        bagId = playerBagIds[caller]
    end

    if not bagId or tostring(bagId) == "" then
        bagId = generateBagId(slot or caller)
    end

    -- Remove the bag item from the player's inventory
    local removed = removeBagFromInventory(caller, slot)
    if not removed then
        TriggerClientEvent("amb_client:Notify", caller, "Failed to drop bag from inventory.", "error")
        return
    end

    -- Spawn the world object
    local entity = CreateObject(BAG_MODEL_HASH, coords.x, coords.y, coords.z - 0.4, true, true, true)
    while not DoesEntityExist(entity) do
        Wait(10)
    end

    SetEntityHeading(entity, heading)
    FreezeEntityPosition(entity, true)

    local netId      = NetworkGetNetworkIdFromEntity(entity)
    local stateBag   = Entity(entity).state

    -- Write the bagId into the entity statebag so any client can read it
    stateBag:set("bagId", bagId, true)

    -- Register in server-side tracking table
    droppedBags[netId]  = { id = bagId, entity = entity }
    playerBagIds[caller] = nil

    TriggerClientEvent("amb_client:Notify", caller, "Bag dropped.", "success")
end)

-- ============================================================
--  Net event: amb_server:openBagInventory
--  Called when a player interacts with a dropped bag to open it.
--  Builds the bag data and sends the UI open event back to the client.
-- ============================================================
RegisterNetEvent("amb_server:openBagInventory", function(bagNetId)
    local caller  = source
    local bagData = getBagInventoryData(caller, bagNetId)
    if bagData then
        TriggerClientEvent("amb_client:openBagUI", caller, bagData)
    end
end)

-- ============================================================
--  Net event: amb_server:takeBagItem
--  Transfers one or more items FROM the bag TO the player.
--  Params: { bagId, slot, amount, netId }
-- ============================================================
RegisterNetEvent("amb_server:takeBagItem", function(params)
    local caller   = source
    local bagId    = params.bagId
    local slot     = params.slot
    local amount   = tonumber(params.amount) or 1

    if isQuasarInventory() then
        -- Quasar: mutate in-memory bag data
        local bagData    = getOrCreateQuasarBag(bagId)
        local item, idx  = getBagItemBySlot(bagData, slot)
        if not item then return end

        local available = tonumber(item.count) or 0
        if available <= 0 then return end

        local qty = (amount == 0) and available or math.min(amount, available)
        if qty <= 0 then return end

        if not Framework.CanCarryItem(caller, item.name, qty) then
            Framework.Notify(caller, _L("cannot_carry_this_much"), "error")
            return
        end

        if not Framework.AddItem(caller, item.name, qty) then
            Framework.Notify(caller, _L("cannot_carry_this_much"), "error")
            return
        end

        item.count = available - qty
        if tonumber(item.count) <= 0 then
            table.remove(bagData.items, idx)
        end

        -- Refresh the UI
        local updatedData = getBagInventoryData(caller, params.netId)
        if updatedData then
            TriggerClientEvent("amb_client:openBagUI", caller, updatedData)
        end
        return
    end

    -- ox_inventory mode
    if Config.Inventory ~= "ox" then
        Framework.Notify(caller, "Medical bag transfer currently supports ox/quasar inventory modes.", "error")
        return
    end

    local inv   = exports.ox_inventory:GetInventory(bagId)
    local items = (inv and inv.items) or {}

    -- Find the item in the bag by slot
    local targetItem = nil
    for _, bagItem in pairs(items) do
        if bagItem.slot == slot then
            targetItem = bagItem
            break
        end
    end

    if not targetItem then return end

    local qty = (amount == 0) and targetItem.count or math.min(amount, targetItem.count)

    if exports.ox_inventory:CanCarryItem(caller, targetItem.name, qty) then
        exports.ox_inventory:RemoveItem(bagId, targetItem.name, qty, nil, slot)
        exports.ox_inventory:AddItem(caller, targetItem.name, qty)
        Wait(100)
        local updatedData = getBagInventoryData(caller, params.netId)
        if updatedData then
            TriggerClientEvent("amb_client:openBagUI", caller, updatedData)
        end
    else
        Framework.Notify(caller, _L("cannot_carry_this_much"), "error")
    end
end)

-- ============================================================
--  Net event: amb_server:storeInBag
--  Transfers one or more items FROM the player TO the bag.
--  Params: { bagId, slot, amount, netId }
-- ============================================================
RegisterNetEvent("amb_server:storeInBag", function(params)
    local caller = source
    local bagId  = params.bagId
    local slot   = params.slot
    local amount = tonumber(params.amount) or 1

    if isQuasarInventory() then
        -- Quasar: use in-memory bag data
        local playerItem = getPlayerItemBySlot(caller, slot)
        if not playerItem then return end
        if playerItem.name == "plt_medical_bag" then return end  -- can't bag a bag

        local available = tonumber(playerItem.count) or 0
        if available <= 0 then return end

        local qty    = (amount == 0) and available or math.min(amount, available)
        if qty <= 0 then return end

        local bagData   = getOrCreateQuasarBag(bagId)
        local unitWeight = tonumber(playerItem.weight) or 0
        local newTotal   = calcBagTotalWeight(bagData) + (unitWeight * qty)
        local bagMax     = tonumber(bagData.maxWeight) or 50000

        if newTotal > bagMax then
            Framework.Notify(caller, _L("bag_is_full"), "error")
            return
        end

        -- Find existing stack or create a new slot
        local existingEntry = nil
        for _, entry in ipairs(bagData.items) do
            if tostring(entry.name) == tostring(playerItem.name) then
                existingEntry = entry
                break
            end
        end

        -- Check slot capacity before inserting
        if not existingEntry then
            local usedSlots = #bagData.items
            local maxSlots  = tonumber(bagData.maxSlots) or 20
            if usedSlots >= maxSlots then
                Framework.Notify(caller, _L("bag_is_full"), "error")
                return
            end
        end

        -- Remove from player
        local removed = Framework.RemoveItem(caller, playerItem.name, qty, playerItem.slot)
                     or Framework.RemoveItem(caller, playerItem.name, qty)
        if not removed then
            Framework.Notify(caller, _L("cannot_carry_this_much"), "error")
            return
        end

        if existingEntry then
            existingEntry.count  = (tonumber(existingEntry.count) or 0) + qty
            existingEntry.weight = unitWeight
            existingEntry.label  = existingEntry.label or playerItem.label or playerItem.name
        else
            local newSlot = findFreeSlot(bagData)
            if not newSlot then
                -- Bag is full – give the item back and notify
                Framework.AddItem(caller, playerItem.name, qty)
                Framework.Notify(caller, _L("bag_is_full"), "error")
                return
            end
            table.insert(bagData.items, {
                name   = playerItem.name,
                label  = playerItem.label or playerItem.name,
                count  = qty,
                slot   = newSlot,
                weight = unitWeight,
            })
        end

        -- Refresh the UI
        local updatedData = getBagInventoryData(caller, params.netId)
        if updatedData then
            TriggerClientEvent("amb_client:openBagUI", caller, updatedData)
        end
        return
    end

    -- ox_inventory mode
    if Config.Inventory ~= "ox" then
        Framework.Notify(caller, "Medical bag transfer currently supports ox/quasar inventory modes.", "error")
        return
    end

    local inv        = exports.ox_inventory:GetInventory(bagId)
    local items      = (inv and inv.items) or {}

    -- Find the item in the bag slot that matches what the player is storing
    local targetItem = nil
    for _, bagItem in pairs(items) do
        if bagItem.slot == slot then
            targetItem = bagItem
            break
        end
    end

    if not targetItem then return end

    local qty = (amount == 0) and targetItem.count or math.min(amount, targetItem.count)

    local added = exports.ox_inventory:AddItem(caller, targetItem.name, qty)
    if added then
        exports.ox_inventory:RemoveItem(bagId, targetItem.name, qty, nil, slot)
        Wait(100)
        local updatedData = getBagInventoryData(caller, params.netId)
        if updatedData then
            TriggerClientEvent("amb_client:openBagUI", caller, updatedData)
        end
    else
        Framework.Notify(caller, _L("bag_is_full"), "error")
    end
end)

-- ============================================================
--  Net event: amb_server:pickupMedicalBag
--  Called when a player picks up a dropped bag entity.
--  Deletes the world entity, gives the bag item back to the
--  player, and cleans up the server tracking table.
-- ============================================================
RegisterNetEvent("amb_server:pickupMedicalBag", function(bagNetId)
    local caller    = source
    local bagEntity = NetworkGetEntityFromNetworkId(bagNetId)

    if not DoesEntityExist(bagEntity) then return end

    -- Resolve bagId from tracking table or entity statebag
    local bagRecord = droppedBags[bagNetId]
    local bagId     = (bagRecord and bagRecord.id) or Entity(bagEntity).state.bagId

    -- Capture position/heading before deleting (in case we need to re-spawn)
    local coords  = GetEntityCoords(bagEntity)
    local heading = GetEntityHeading(bagEntity)

    -- Remove the world entity
    DeleteEntity(bagEntity)
    droppedBags[bagNetId] = nil

    -- Build metadata for the item
    local metadata = bagId and { bagId = bagId } or nil

    -- Give the bag item back to the player
    local success, metadataApplied = addBagToInventory(caller, metadata)

    if not success then
        -- Re-spawn the bag at the original location since the player can't carry it
        local newEntity = CreateObject(BAG_MODEL_HASH, coords.x, coords.y, coords.z, true, true, true)
        if DoesEntityExist(newEntity) then
            SetEntityHeading(newEntity, heading)
            FreezeEntityPosition(newEntity, true)
            local newNetId = NetworkGetNetworkIdFromEntity(newEntity)
            Entity(newEntity).state:set("bagId", bagId, true)
            droppedBags[newNetId] = { id = bagId, entity = newEntity }
        end
        Framework.Notify(caller, _L("cannot_carry_more_item"), "error")
        return
    end

    -- Track the bagId on the player for later use
    if bagId then
        playerBagIds[caller] = bagId
    end

    -- Warn if the inventory system couldn't store the bagId in metadata
    if isQuasarInventory() and not metadataApplied then
        Framework.Notify(caller, "Bag picked up (metadata fallback active for qs/quasar).", "info")
    end

    TriggerClientEvent("amb_client:Notify", caller, "Bag picked up.", "success")
end)

-- ============================================================
--  playerDropped: clean up the player's bag id cache
-- ============================================================
AddEventHandler("playerDropped", function()
    playerBagIds[source] = nil
end)

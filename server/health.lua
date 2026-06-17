local DownedPlayers = {}
local SavedHealthCache = {}

-- ==========================================
-- Initialization & Compatibility Checks
-- ==========================================

CreateThread(function()
    Wait(1500)
    if Framework.Type == "qb" then
        if GetResourceState("qb-ambulancejob") == "started" then
            print("^1[plt_ambulance] QBCore mode detected while qb-ambulancejob is running. Disable one death system to prevent conflicts.^7")
        end
    end
end)

-- ==========================================
-- Utility Functions
-- ==========================================

local function IsPlayerOnline(sourceId)
    local src = tonumber(sourceId)
    if not src then return false end
    return GetPlayerName(src) ~= nil
end

local function IsPlayerDowned(sourceId)
    if DownedPlayers[sourceId] == true then return true end

    local isDead = Framework.GetMetaData(sourceId, "isdead")
    local inLastStand = Framework.GetMetaData(sourceId, "inlaststand")
    local is_dead = Framework.GetMetaData(sourceId, "is_dead")

    if isDead == true or inLastStand == true or is_dead == true then
        return true
    end

    local ped = GetPlayerPed(sourceId)
    if ped and ped > 0 then
        local health = GetEntityHealth(ped)
        if health and health <= 110 then
            return true
        end
    end

    return false
end

local function ClampHealth(health)
    local val = tonumber(health)
    if not val then return nil end
    val = math.floor(val)
    if val < 100 then val = 100 end
    if val > 200 then val = 200 end
    return val
end

local function ResetVitals(sourceId)
    pcall(function() Framework.SetMetaData(sourceId, "hunger", 100) end)
    pcall(function() Framework.SetMetaData(sourceId, "thirst", 100) end)
    pcall(function() Framework.SetMetaData(sourceId, "stress", 0) end)
end

local function SavePlayerHealth(sourceId, health)
    if not Framework.GetPlayer(sourceId) then return end

    local hpToSave = ClampHealth(health)
    if not hpToSave then
        hpToSave = ClampHealth(SavedHealthCache[sourceId])
    end

    if not hpToSave then
        local ped = GetPlayerPed(sourceId)
        if ped and ped > 0 then
            hpToSave = ClampHealth(GetEntityHealth(ped))
        end
    end

    if hpToSave then
        Framework.SetMetaData(sourceId, "amb_saved_health", hpToSave)
    end
end

-- ==========================================
-- Revive & Heal Core Logic
-- ==========================================

local function TriggerReviveClientEvents(sourceId)
    TriggerClientEvent("amb_client:AuthorizeRevive", sourceId, 12000)
    
    if Framework.Type == "qb" then
        TriggerClientEvent("amb_client:SetDeathStatus", sourceId, false)
    else
        TriggerClientEvent("hospital:client:SetDeathStatus", sourceId, false)
        TriggerClientEvent("hospital:client:Revive", sourceId)
    end
    
    TriggerClientEvent("amb_client:RevivePlayer", sourceId)
    TriggerClientEvent("amb_client:onPlayerRevive", sourceId)
end

local function InternalRevive(sourceId)
    if not sourceId or not IsPlayerOnline(sourceId) then return false end

    DownedPlayers[sourceId] = false
    pcall(function() Framework.SetDeathStatus(sourceId, false) end)

    TriggerReviveClientEvents(sourceId)
    ResetVitals(sourceId)
    
    SetTimeout(500, function()
        if IsPlayerOnline(sourceId) then TriggerReviveClientEvents(sourceId) end
    end)
    SetTimeout(1500, function()
        if IsPlayerOnline(sourceId) then TriggerReviveClientEvents(sourceId) end
    end)

    return true
end
exports("InternalRevive", InternalRevive)

local function HealPlayerAdmin(sourceId)
    if not sourceId or not IsPlayerOnline(sourceId) then return false end

    DownedPlayers[sourceId] = false
    SavedHealthCache[sourceId] = 200

    pcall(function() Framework.SetDeathStatus(sourceId, false) end)
    ResetVitals(sourceId)
    SavePlayerHealth(sourceId, 200)

    TriggerClientEvent("amb_client:AuthorizeRevive", sourceId, 12000)
    TriggerClientEvent("amb_client:HealInjuries", sourceId)

    return true
end

-- ==========================================
-- Net Events & Callbacks
-- ==========================================

RegisterNetEvent("amb_server:SetDowned", function(state)
    local src = source
    DownedPlayers[src] = state
    Framework.SetDeathStatus(src, state)
end)

RegisterNetEvent("amb_server:cacheHealth", function(health)
    local src = source
    local hp = ClampHealth(health)
    if not hp then return end

    SavedHealthCache[src] = hp
    Framework.SetMetaData(src, "amb_saved_health", hp)
end)

Framework.CreateCallback("amb_server:getSavedHealth", function(source, cb)
    local savedHp = Framework.GetMetaData(source, "amb_saved_health")
    cb(ClampHealth(savedHp))
end)

Framework.CreateCallback("amb_server:isPlayerDowned", function(source, cb, targetSrc)
    local isDowned = DownedPlayers[targetSrc] or false
    cb(isDowned)
end)

RegisterNetEvent("amb_server:RevivePlayer", function(targetId)
    local src = source
    local targetSrc = tonumber(targetId) or src

    local isAuthorized = exports.plt_ambulance_job:IsEMS(src) or Framework.HasPermission(src, Config.Permission)
    if isAuthorized then
        InternalRevive(targetSrc)
    end
end)

RegisterNetEvent("amb_server:HealPlayer", function(part, injuryId, injuryLevel)
    local src = source
    local requiredItem = (injuryLevel >= 2) and "plt_surgical_kit" or "plt_medkit"

    if Framework.RemoveItem(src, requiredItem, 1) then
        TriggerClientEvent("amb_client:HealPart", src, part, injuryId, injuryLevel)
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    SavePlayerHealth(src)
    DownedPlayers[src] = nil
    SavedHealthCache[src] = nil
end)

-- ==========================================
-- Items & Medication
-- ==========================================

-- Bandage specific registration
Framework.CreateUseableItem("plt_bandage", function(source, item)
    local player = Framework.GetPlayer(source)
    if not player then return end

    if IsPlayerDowned(source) then
        Framework.Notify(source, _L("cannot_use_incapacitated"), "error")
        return false
    end

    if Framework.RemoveItem(source, "plt_bandage", 1) then
        TriggerClientEvent("amb_client:selfBandage", source)
        return true
    end
    return false
end)

-- Other Medication Loop
local MedicationItems = {
    plt_painkillers = "amb_client:useMedication",
    plt_painkillers_adv = "amb_client:useMedication",
    plt_antibiotics = "amb_client:useMedication",
    plt_medkit = "amb_client:useMedication",
    iak_wheelchair = "amb_client:useWheelchair"
}

for itemName, clientEvent in pairs(MedicationItems) do
    Framework.CreateUseableItem(itemName, function(source, item)
        local player = Framework.GetPlayer(source)
        if not player then return end

        if IsPlayerDowned(source) and itemName ~= "iak_wheelchair" then
            Framework.Notify(source, _L("cannot_use_incapacitated"), "error")
            return false
        end

        local metadata = item and (item.info or item.metadata) or nil
        if Framework.RemoveItem(source, itemName, 1) then
            if clientEvent == "amb_client:useWheelchair" then
                local duration = metadata and metadata.duration or nil
                TriggerClientEvent(clientEvent, source, duration)
            else
                TriggerClientEvent(clientEvent, source, itemName, metadata)
            end
            return true
        end
        return false
    end)
end

-- Slot-based item consumption via UI
RegisterNetEvent("amb_server:consumeMedication", function(itemName, itemData, useOxInventory)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    if not MedicationItems[itemName] then return end

    if IsPlayerDowned(src) and itemName ~= "iak_wheelchair" then
        return Framework.Notify(src, _L("cannot_use_incapacitated"), "error")
    end

    local slot = nil
    if type(itemData) == "table" then
        slot = tonumber(itemData.slot or itemData.id or itemData.slotId)
    elseif type(itemData) == "string" then
        slot = tonumber(itemData)
    end

    local removed = Framework.RemoveItem(src, itemName, 1, slot)
    
    if not removed and useOxInventory == true and GetResourceState("ox_inventory") == "started" then
        removed = Framework.RemoveItem(src, itemName, 1)
    end

    if removed then
        if itemName ~= "iak_wheelchair" then
            TriggerClientEvent(MedicationItems[itemName], src, itemName, nil)
        end
    else
        Framework.Notify(src, "Failed to use item. Try again.", "error")
    end
end)

-- ==========================================
-- Commands
-- ==========================================

RegisterCommand("revive", function(source, args)
    if source ~= 0 and not Framework.HasPermission(source, Config.Permission) then
        return Framework.Notify(source, _L("no_command_permission"), "error")
    end

    local targetSrc = args[1] and tonumber(args[1]) or source
    if source == 0 and (not targetSrc or targetSrc == 0) then
        print("^1[plt_ambulance] Usage from console: /revive [id]^7")
        return
    end

    if not IsPlayerOnline(targetSrc) then
        if source ~= 0 then
            Framework.Notify(source, _L("player_not_found"), "error")
        else
            print(string.format("[plt_ambulance] /revive failed: player %s is not online", tostring(targetSrc)))
        end
        return
    end

    InternalRevive(targetSrc)
end, false)

RegisterCommand("reviveplayer", function(source, args)
    if source ~= 0 and not Framework.HasPermission(source, Config.Permission) then return end
    local targetSrc = args[1] and tonumber(args[1]) or source
    
    if IsPlayerOnline(targetSrc) then
        InternalRevive(targetSrc)
    end
end, false)

RegisterCommand("heal", function(source, args)
    if source ~= 0 and not Framework.HasPermission(source, Config.Permission) then
        return Framework.Notify(source, _L("no_command_permission"), "error")
    end

    local targetSrc = args[1] and tonumber(args[1]) or source
    if source == 0 and (not targetSrc or targetSrc == 0) then
        print("^1[plt_ambulance] Usage from console: /heal [id]^7")
        return
    end

    if not IsPlayerOnline(targetSrc) then
        if source ~= 0 then
            Framework.Notify(source, _L("player_not_found"), "error")
        else
            print(string.format("[plt_ambulance] /heal failed: invalid player id %s", tostring(args[1])))
        end
        return
    end

    HealPlayerAdmin(targetSrc)
end, false)

RegisterCommand("kill", function(source, args)
    if source ~= 0 and not Framework.HasPermission(source, Config.Permission) then
        return Framework.Notify(source, _L("no_command_permission"), "error")
    end

    local targetSrc = args[1] and tonumber(args[1]) or source
    if source == 0 and (not targetSrc or targetSrc == 0) then
        print("^1[plt_ambulance] Usage from console: /kill [id]^7")
        return
    end

    if not IsPlayerOnline(targetSrc) then
        if source ~= 0 then
            Framework.Notify(source, _L("player_not_found"), "error")
        else
            print(string.format("[plt_ambulance] /kill failed: invalid player id %s", tostring(args[1])))
        end
        return
    end

    DownedPlayers[targetSrc] = true
    SavedHealthCache[targetSrc] = 100
    pcall(function() Framework.SetDeathStatus(targetSrc, true) end)
    ResetVitals(targetSrc)
    SavePlayerHealth(targetSrc, 100)

    TriggerClientEvent("amb_client:KillPlayer", targetSrc)

    if source ~= 0 then
        Framework.Notify(source, string.format("Player %s killed.", targetSrc), "success")
    else
        print(string.format("[plt_ambulance] Player %s killed.", targetSrc))
    end
end, false)

-- ==========================================
-- txAdmin Integrations
-- ==========================================

AddEventHandler("txAdmin:events:healedPlayer", function(eventData)
    if GetInvokingResource() == "monitor" and type(eventData) == "table" then
        local targetId = tonumber(eventData.id)
        if not targetId then return end
        
        if targetId == -1 then
            for _, playerId in ipairs(GetPlayers()) do
                HealPlayerAdmin(tonumber(playerId))
            end
        else
            HealPlayerAdmin(targetId)
        end
    end
end)

AddEventHandler("txAdmin:events:revivedPlayer", function(eventData)
    if GetInvokingResource() == "monitor" and type(eventData) == "table" then
        local targetId = tonumber(eventData.id)
        if not targetId then return end
        
        if targetId == -1 then
            for _, playerId in ipairs(GetPlayers()) do
                InternalRevive(tonumber(playerId))
            end
        else
            InternalRevive(targetId)
        end
    end
end)
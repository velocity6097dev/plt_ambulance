-- ============================================================
--  plt_ambulance  |  health.lua  (server-side)
--  Handles player death, revive, heal, kill, downed state,
--  health caching, item usage, and txAdmin integration.
-- ============================================================

-- State tables
local downingStatus = {}   -- [playerId] = true/false  (is the player currently downed)
local cachedHealth  = {}   -- [playerId] = number       (last known health value 100-200)

-- ============================================================
--  Startup: conflict check
-- ============================================================
CreateThread(function()
    Wait(1500)
    if Framework.Type == "qb" then
        if GetResourceState("qb-ambulancejob") == "started" then
            print("^1[plt_ambulance] QBCore mode detected while qb-ambulancejob is running. Disable one death system to prevent conflicts.^7")
        end
    end
end)

-- ============================================================
--  Helper: isValidPlayer(playerId)
--  Returns true if the given id is an active, connected player.
-- ============================================================
local function isValidPlayer(playerId)
    playerId = tonumber(playerId)
    if not playerId then return false end
    return GetPlayerName(playerId) ~= nil
end

-- ============================================================
--  Helper: sendReviveEvents(playerId)
--  Fires all client events needed to complete a revive.
-- ============================================================
local function sendReviveEvents(playerId)
    TriggerClientEvent("amb_client:AuthorizeRevive", playerId, 12000)

    if Framework.Type == "qb" then
        TriggerClientEvent("amb_client:SetDeathStatus", playerId, false)
    else
        TriggerClientEvent("hospital:client:SetDeathStatus", playerId, false)
        TriggerClientEvent("hospital:client:Revive",         playerId)
    end

    TriggerClientEvent("amb_client:RevivePlayer",   playerId)
    TriggerClientEvent("amb_client:onPlayerRevive", playerId)
end

-- ============================================================
--  Helper: isPlayerDead(playerId)
--  Checks multiple metadata keys and ped health to decide
--  whether the player should be considered dead.
-- ============================================================
local function isPlayerDead(playerId)
    -- Quick lookup in local downed table
    if downingStatus[playerId] == true then return true end

    -- Framework metadata checks (supports both QBCore and ESX naming conventions)
    local isDead      = Framework.GetMetaData(playerId, "isdead")
    local inLastStand = Framework.GetMetaData(playerId, "inlaststand")
    local isDeadAlt   = Framework.GetMetaData(playerId, "is_dead")

    if isDead == true or inLastStand == true or isDeadAlt == true then
        return true
    end

    -- Fallback: check raw ped health (game health ≤ 110 = dead in GTA V)
    local ped = GetPlayerPed(playerId)
    if ped and ped > 0 then
        local health = GetEntityHealth(ped)
        if health and health <= 110 then
            return true
        end
    end

    return false
end

-- ============================================================
--  Helper: clampHealth(value)
--  Converts a value to a valid GTA health integer (100–200).
--  Returns nil if the value cannot be parsed as a number.
-- ============================================================
local function clampHealth(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 100 then value = 100 end
    if value > 200 then value = 200 end
    return value
end

-- ============================================================
--  Helper: resetNeeds(playerId)
--  Sets the player's hunger to 100, thirst to 100, stress to 0.
--  Each call is wrapped in pcall so a missing metadata key
--  won't break the whole revive flow.
-- ============================================================
local function resetNeeds(playerId)
    pcall(function() Framework.SetMetaData(playerId, "hunger",  100) end)
    pcall(function() Framework.SetMetaData(playerId, "thirst",  100) end)
    pcall(function() Framework.SetMetaData(playerId, "stress",    0) end)
end

-- ============================================================
--  Helper: saveHealthToMetaData(playerId, explicitHealth)
--  Persists the player's current health into metadata so it
--  can be restored after a revive.  Resolution order:
--    1. explicitHealth argument
--    2. cachedHealth table
--    3. live ped health
-- ============================================================
local function saveHealthToMetaData(playerId, explicitHealth)
    if not Framework.GetPlayer(playerId) then return end

    local health = clampHealth(explicitHealth)

    if not health then
        health = clampHealth(cachedHealth[playerId])
    end

    if not health then
        local ped = GetPlayerPed(playerId)
        if ped and ped > 0 then
            health = clampHealth(GetEntityHealth(ped))
        end
    end

    if health then
        Framework.SetMetaData(playerId, "amb_saved_health", health)
    end
end

-- ============================================================
--  Net event: amb_server:SetDowned
--  Called by the client when a player goes down or gets up.
-- ============================================================
RegisterNetEvent("amb_server:SetDowned", function(isDowned)
    local playerId = source
    downingStatus[playerId] = isDowned
    Framework.SetDeathStatus(playerId, isDowned)
end)

-- ============================================================
--  Net event: amb_server:cacheHealth
--  Client reports its current health so the server can store it.
-- ============================================================
RegisterNetEvent("amb_server:cacheHealth", function(health)
    local playerId = source
    health = clampHealth(health)
    if not health then return end

    cachedHealth[playerId] = health
    Framework.SetMetaData(playerId, "amb_saved_health", health)
end)

-- ============================================================
--  Callback: amb_server:getSavedHealth
--  Returns the saved health value for the calling player.
-- ============================================================
Framework.CreateCallback("amb_server:getSavedHealth", function(playerId, cb)
    local saved = Framework.GetMetaData(playerId, "amb_saved_health")
    cb(clampHealth(saved))
end)

-- ============================================================
--  Callback: amb_server:isPlayerDowned
--  Returns whether a specific player is currently downed.
-- ============================================================
Framework.CreateCallback("amb_server:isPlayerDowned", function(_playerId, cb, targetId)
    cb(downingStatus[targetId] or false)
end)

-- ============================================================
--  InternalRevive(playerId)  [exported]
--  Core revive logic used by commands, events, and exports.
--  Returns true on success, false if the player is invalid.
-- ============================================================
local function InternalRevive(playerId)
    if not isValidPlayer(playerId) then return false end

    downingStatus[playerId] = false

    pcall(function() Framework.SetDeathStatus(playerId, false) end)

    sendReviveEvents(playerId)
    resetNeeds(playerId)

    -- Fire revive events again after short delays to handle edge cases
    -- (e.g. the client wasn't fully loaded when the first event arrived)
    SetTimeout(500, function()
        if isValidPlayer(playerId) then
            sendReviveEvents(playerId)
        end
    end)

    SetTimeout(1500, function()
        if isValidPlayer(playerId) then
            sendReviveEvents(playerId)
        end
    end)

    return true
end

exports("InternalRevive", InternalRevive)

-- ============================================================
--  KillPlayer(playerId)  [internal]
--  Marks the player as downed/dead and tells the client.
--  Returns true on success, false if the player is invalid.
-- ============================================================
local function KillPlayer(playerId)
    if not (playerId and isValidPlayer(playerId)) then return false end

    downingStatus[playerId] = true
    cachedHealth[playerId]  = 100

    pcall(function() Framework.SetDeathStatus(playerId, true) end)

    saveHealthToMetaData(playerId, 100)
    TriggerClientEvent("amb_client:KillPlayer", playerId)

    return true
end

-- ============================================================
--  Net event: amb_server:RevivePlayer
--  Allows an EMS player (or admin) to revive another player.
-- ============================================================
RegisterNetEvent("amb_server:RevivePlayer", function(targetId)
    local caller   = source
    targetId       = tonumber(targetId) or caller

    local isEMS    = exports.plt_ambulance_job:IsEMS(caller)
    local hasPerms = Framework.HasPermission(caller, Config.Permission)

    if hasPerms or isEMS then
        InternalRevive(targetId)
    end
end)

-- ============================================================
--  Command: /revive [id]
--  Revives the target player (or the caller if no id given).
-- ============================================================
RegisterCommand("revive", function(caller, args)
    -- Permission check (skip for console, caller == 0)
    if caller ~= 0 then
        if not Framework.HasPermission(caller, Config.Permission) then
            Framework.Notify(caller, _L("no_command_permission"), "error")
            return
        end
    end

    -- Resolve target id
    local targetId = tonumber(args[1]) or caller

    if caller == 0 and (not targetId or targetId == 0) then
        print("^1[plt_ambulance] Usage from console: /revive [id]^7")
        return
    end

    if not (targetId and isValidPlayer(targetId)) then
        if caller ~= 0 then
            Framework.Notify(caller, _L("player_not_found"), "error")
        else
            print(("[plt_ambulance] /revive failed: invalid player id %s"):format(tostring(args[1])))
        end
        return
    end

    local ok = InternalRevive(targetId)
    if not ok then
        if caller ~= 0 then
            Framework.Notify(caller, _L("player_not_found"), "error")
        else
            print(("[plt_ambulance] /revive failed: player %s is not online"):format(tostring(targetId)))
        end
    end
end, false)

-- ============================================================
--  Command: /reviveplayer [id]
--  Silent alias for /revive, restricted to admins.
-- ============================================================
RegisterCommand("reviveplayer", function(caller, args)
    if caller ~= 0 then
        if not Framework.HasPermission(caller, Config.Permission) then
            return
        end
    end

    local targetId = tonumber(args[1]) or caller
    if targetId and isValidPlayer(targetId) then
        InternalRevive(targetId)
    end
end, false)

-- ============================================================
--  HealPlayer(playerId)  [internal]
--  Fully heals a player: clears death state, resets needs,
--  saves health, and tells the client to heal injuries.
--  Returns true on success, false if invalid.
-- ============================================================
local function HealPlayer(playerId)
    if not (playerId and isValidPlayer(playerId)) then return false end

    downingStatus[playerId] = false
    cachedHealth[playerId]  = 200

    pcall(function() Framework.SetDeathStatus(playerId, false) end)

    resetNeeds(playerId)
    saveHealthToMetaData(playerId, 200)

    TriggerClientEvent("amb_client:AuthorizeRevive", playerId, 12000)
    TriggerClientEvent("amb_client:HealInjuries",    playerId)

    return true
end

-- ============================================================
--  Command: /heal [id]
--  Fully heals the target player.
-- ============================================================
RegisterCommand("heal", function(caller, args)
    if caller ~= 0 then
        if not Framework.HasPermission(caller, Config.Permission) then
            Framework.Notify(caller, _L("no_command_permission"), "error")
            return
        end
    end

    local targetId = tonumber(args[1]) or caller

    if caller == 0 and (not targetId or targetId == 0) then
        print("^1[plt_ambulance] Usage from console: /heal [id]^7")
        return
    end

    if not (targetId and isValidPlayer(targetId)) then
        if caller ~= 0 then
            Framework.Notify(caller, _L("player_not_found"), "error")
        else
            print(("[plt_ambulance] /heal failed: invalid player id %s"):format(tostring(args[1])))
        end
        return
    end

    HealPlayer(targetId)
end, false)

-- ============================================================
--  Command: /kill [id]
--  Kills the target player.
-- ============================================================
RegisterCommand("kill", function(caller, args)
    if caller ~= 0 then
        if not Framework.HasPermission(caller, Config.Permission) then
            Framework.Notify(caller, _L("no_command_permission"), "error")
            return
        end
    end

    local targetId = tonumber(args[1]) or caller

    if caller == 0 and (not targetId or targetId == 0) then
        print("^1[plt_ambulance] Usage from console: /kill [id]^7")
        return
    end

    if not (targetId and isValidPlayer(targetId)) then
        if caller ~= 0 then
            Framework.Notify(caller, _L("player_not_found"), "error")
        else
            print(("[plt_ambulance] /kill failed: invalid player id %s"):format(tostring(args[1])))
        end
        return
    end

    local ok = KillPlayer(targetId)
    if ok then
        if caller ~= 0 then
            Framework.Notify(caller, ("Player %s killed."):format(targetId), "success")
        else
            print(("[plt_ambulance] Player %s killed."):format(targetId))
        end
    end
end, false)

-- ============================================================
--  txAdmin integration: healedPlayer
--  Triggered by txAdmin when it heals one or all players.
-- ============================================================
AddEventHandler("txAdmin:events:healedPlayer", function(data)
    if GetInvokingResource() ~= "monitor" then return end
    if type(data) ~= "table" then return end

    local targetId = tonumber(data.id)
    if not targetId then return end

    if targetId == -1 then
        -- Heal everyone on the server
        for _, playerId in ipairs(GetPlayers()) do
            HealPlayer(tonumber(playerId))
        end
    else
        HealPlayer(targetId)
    end
end)

-- ============================================================
--  txAdmin integration: revivedPlayer
--  Triggered by txAdmin when it revives one or all players.
-- ============================================================
AddEventHandler("txAdmin:events:revivedPlayer", function(data)
    if GetInvokingResource() ~= "monitor" then return end
    if type(data) ~= "table" then return end

    local targetId = tonumber(data.id)
    if not targetId then return end

    if targetId == -1 then
        -- Revive everyone on the server
        for _, playerId in ipairs(GetPlayers()) do
            InternalRevive(tonumber(playerId))
        end
    else
        InternalRevive(targetId)
    end
end)

-- ============================================================
--  Net event: amb_server:HealPlayer
--  Lets a medic heal a specific body part.
--  Requires a medkit (plt_medkit) or surgical kit (plt_surgical_kit)
--  depending on the injury severity (A2 >= 2 → surgical kit).
-- ============================================================
RegisterNetEvent("amb_server:HealPlayer", function(targetId, bodyPart, severity)
    local caller   = source
    local itemName = (severity >= 2) and "plt_surgical_kit" or "plt_medkit"

    local removed = Framework.RemoveItem(caller, itemName, 1)
    if removed then
        TriggerClientEvent("amb_client:HealPart", targetId, bodyPart, severity)
    end
end)

-- ============================================================
--  playerDropped: clean up state tables on disconnect
-- ============================================================
AddEventHandler("playerDropped", function()
    local playerId = source
    saveHealthToMetaData(playerId)   -- persist last known health before cleanup
    downingStatus[playerId] = nil
    cachedHealth[playerId]  = nil
end)

-- ============================================================
--  Useable item: plt_bandage
--  Self-bandage – cannot be used while fully downed.
-- ============================================================
Framework.CreateUseableItem("plt_bandage", function(playerId)
    if not Framework.GetPlayer(playerId) then return end

    if isPlayerDead(playerId) then
        -- Only block if this is NOT the wheelchair (wheelchair can be used while downed)
        if itemName ~= "iak_wheelchair" then
            Framework.Notify(playerId, _L("cannot_use_incapacitated"), "error")
            return false
        end
    end

    local removed = Framework.RemoveItem(playerId, "plt_bandage", 1)
    if removed then
        TriggerClientEvent("amb_client:selfBandage", playerId)
        return true
    end
    return false
end)

-- ============================================================
--  Useable items: medications and wheelchair
--  Each item maps to a specific client event.
-- ============================================================
local useableItems = {
    plt_painkillers     = "amb_client:useMedication",
    plt_painkillers_adv = "amb_client:useMedication",
    plt_antibiotics     = "amb_client:useMedication",
    plt_medkit          = "amb_client:useMedication",
    iak_wheelchair      = "amb_client:useWheelchair",
}

for itemName, clientEvent in pairs(useableItems) do
    Framework.CreateUseableItem(itemName, function(playerId, itemData)
        if not Framework.GetPlayer(playerId) then return end

        -- Block downed players from using items (wheelchair is the exception)
        if isPlayerDead(playerId) and itemName ~= "iak_wheelchair" then
            Framework.Notify(playerId, _L("cannot_use_incapacitated"), "error")
            return false
        end

        -- Extract item metadata / slot info if provided
        local meta = nil
        if itemData then
            meta = itemData.info or itemData.metadata
        end

        local removed = Framework.RemoveItem(playerId, itemName, 1)
        if removed then
            if clientEvent == "amb_client:useWheelchair" then
                -- Pass wheelchair duration from metadata if available
                local duration = meta and meta.duration or nil
                TriggerClientEvent(clientEvent, playerId, duration)
            else
                TriggerClientEvent(clientEvent, playerId, itemName, meta)
            end
            return true
        end
        return false
    end)
end

-- ============================================================
--  Net event: amb_server:consumeMedication
--  Server-side item removal validation before triggering the
--  client medication effect.  Supports slot-based inventories
--  (ox_inventory) and string/number slot ids.
-- ============================================================
RegisterNetEvent("amb_server:consumeMedication", function(itemName, slotOrId, fromServer)
    local caller = source

    if not Framework.GetPlayer(caller) then return end
    if not useableItems[itemName]      then return end

    -- Block downed players (wheelchair still allowed)
    if isPlayerDead(caller) and itemName ~= "iak_wheelchair" then
        Framework.Notify(caller, _L("cannot_use_incapacitated"), "error")
        return
    end

    -- Resolve slot id from different inventory formats
    local slot = nil
    if type(slotOrId) == "table" then
        slot = tonumber(slotOrId.slot or slotOrId.id or slotOrId.slotId)
    elseif type(slotOrId) == "string" then
        slot = tonumber(slotOrId)
    elseif type(slotOrId) == "number" then
        slot = slotOrId
    end

    local removed = Framework.RemoveItem(caller, itemName, 1, slot)

    -- Fallback: if removal failed and ox_inventory is running, try without slot
    if not removed and fromServer == true then
        if GetResourceState("ox_inventory") == "started" then
            removed = Framework.RemoveItem(caller, itemName, 1)
        end
    end

    if removed then
        if itemName ~= "iak_wheelchair" then
            local clientEvent = useableItems[itemName]
            if clientEvent == "amb_client:useMedication" then
                TriggerClientEvent(clientEvent, caller, itemName, nil)
            else
                TriggerClientEvent(clientEvent, caller)
            end
        end
    else
        Framework.Notify(caller, "Failed to use item. Try again.", "error")
    end
end)

local DownedState = {}
local CachedHealth = {}

CreateThread(function()
    Wait(1500)
    if Framework.Type == "qb" then
        if GetResourceState("qb-ambulancejob") == "started" then
            print("^1[plt_ambulance] QBCore mode detected while qb-ambulancejob is running. Disable one death system to prevent conflicts.^7")
        end
    end
end)

function IsPlayerValid(src)
    local target = tonumber(src)
    if not target then
        return false
    end
    return GetPlayerName(target) ~= nil
end

function PerformReviveTriggers(src)
    TriggerClientEvent("amb_client:AuthorizeRevive", src, 12000)
    if Framework.Type == "qb" then
        TriggerClientEvent("amb_client:SetDeathStatus", src, false)
    else
        TriggerClientEvent("hospital:client:SetDeathStatus", src, false)
        TriggerClientEvent("hospital:client:Revive", src)
    end
    TriggerClientEvent("amb_client:RevivePlayer", src)
    TriggerClientEvent("amb_client:onPlayerRevive", src)
end

function IsPlayerDowned(src)
    if DownedState[src] == true then
        return true
    end
    
    local isDead = Framework.GetMetaData(src, "isdead")
    local inLastStand = Framework.GetMetaData(src, "inlaststand")
    local is_dead = Framework.GetMetaData(src, "is_dead")
    
    if isDead == true or inLastStand == true or is_dead == true then
        return true
    end
    
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local health = GetEntityHealth(ped)
        if health and health <= 110 then
            return true
        end
    end
    return false
end

function ClampHealth(health)
    local h = tonumber(health)
    if not h then
        return nil
    end
    h = math.floor(h)
    if h < 100 then
        h = 100
    end
    if h > 200 then
        h = 200
    end
    return h
end

function ResetNeeds(src)
    pcall(function()
        Framework.SetMetaData(src, "hunger", 100)
    end)
    pcall(function()
        Framework.SetMetaData(src, "thirst", 100)
    end)
    pcall(function()
        Framework.SetMetaData(src, "stress", 0)
    end)
end

function SavePlayerHealth(src, currentHealth)
    local player = Framework.GetPlayer(src)
    if not player then
        return
    end
    
    local h = ClampHealth(currentHealth)
    if not h then
        h = ClampHealth(CachedHealth[src])
    end
    
    if not h then
        local ped = GetPlayerPed(src)
        if ped and ped > 0 then
            h = ClampHealth(GetEntityHealth(ped))
        end
    end
    
    if h then
        Framework.SetMetaData(src, "amb_saved_health", h)
    end
end

RegisterNetEvent("amb_server:SetDowned", function(state)
    local src = source
    DownedState[src] = state
    Framework.SetDeathStatus(src, state)
end)

RegisterNetEvent("amb_server:cacheHealth", function(health)
    local src = source
    local h = ClampHealth(health)
    if not h then
        return
    end
    CachedHealth[src] = h
    Framework.SetMetaData(src, "amb_saved_health", h)
end)

Framework.CreateCallback("amb_server:getSavedHealth", function(source, cb)
    local saved = Framework.GetMetaData(source, "amb_saved_health")
    cb(ClampHealth(saved))
end)

Framework.CreateCallback("amb_server:isPlayerDowned", function(source, cb, targetSrc)
    local state = DownedState[targetSrc]
    if not state then
        state = false
    end
    cb(state)
end)

function InternalRevive(src)
    if not IsPlayerValid(src) then
        return false
    end
    
    DownedState[src] = false
    pcall(function()
        Framework.SetDeathStatus(src, false)
    end)
    
    PerformReviveTriggers(src)
    ResetNeeds(src)
    
    SetTimeout(500, function()
        if IsPlayerValid(src) then
            PerformReviveTriggers(src)
        end
    end)
    
    SetTimeout(1500, function()
        if IsPlayerValid(src) then
            PerformReviveTriggers(src)
        end
    end)
    
    return true
end
exports("InternalRevive", InternalRevive)

function InternalKill(src)
    if not IsPlayerValid(src) then
        return false
    end
    
    DownedState[src] = true
    CachedHealth[src] = 100
    
    pcall(function()
        Framework.SetDeathStatus(src, true)
    end)
    
    SavePlayerHealth(src, 100)
    TriggerClientEvent("amb_client:KillPlayer", src)
    
    return true
end

RegisterNetEvent("amb_server:RevivePlayer", function(targetSrc)
    local src = source
    local target = tonumber(targetSrc) or src
    
    local isEms = exports.plt_ambulance_job:IsEMS(src)
    local hasPerm = Framework.HasPermission(src, Config.Permission)
    
    if isEms or hasPerm then
        InternalRevive(target)
    end
end)

RegisterCommand("revive", function(source, args)
    if source ~= 0 then
        if not Framework.HasPermission(source, Config.Permission) then
            Framework.Notify(source, _L("no_command_permission"), "error")
            return
        end
    end
    
    local target = args[1] and tonumber(args[1]) or source
    
    if source == 0 and (not target or target == 0) then
        print("^1[plt_ambulance] Usage from console: /revive [id]^7")
        return
    end
    
    if target and IsPlayerValid(target) then
        InternalRevive(target)
    else
        if source ~= 0 then
            Framework.Notify(source, _L("player_not_found"), "error")
        else
            print(string.format("[plt_ambulance] /revive failed: invalid player id %s", tostring(args[1])))
        end
    end
end, false)

RegisterCommand("reviveplayer", function(source, args)
    if source ~= 0 then
        if not Framework.HasPermission(source, Config.Permission) then
            return
        end
    end
    
    local target = args[1] and tonumber(args[1]) or source
    if target and IsPlayerValid(target) then
        InternalRevive(target)
    end
end, false)

function InternalHeal(src)
    if not IsPlayerValid(src) then
        return false
    end
    
    DownedState[src] = false
    CachedHealth[src] = 200
    
    pcall(function()
        Framework.SetDeathStatus(src, false)
    end)
    
    ResetNeeds(src)
    SavePlayerHealth(src, 200)
    TriggerClientEvent("amb_client:AuthorizeRevive", src, 12000)
    TriggerClientEvent("amb_client:HealInjuries", src)
    
    return true
end

RegisterCommand("heal", function(source, args)
    if source ~= 0 then
        if not Framework.HasPermission(source, Config.Permission) then
            Framework.Notify(source, _L("no_command_permission"), "error")
            return
        end
    end
    
    local target = args[1] and tonumber(args[1]) or source
    
    if source == 0 and (not target or target == 0) then
        print("^1[plt_ambulance] Usage from console: /heal [id]^7")
        return
    end
    
    if target and IsPlayerValid(target) then
        InternalHeal(target)
    else
        if source ~= 0 then
            Framework.Notify(source, _L("player_not_found"), "error")
        else
            print(string.format("[plt_ambulance] /heal failed: invalid player id %s", tostring(args[1])))
        end
    end
end, false)

RegisterCommand("kill", function(source, args)
    if source ~= 0 then
        if not Framework.HasPermission(source, Config.Permission) then
            Framework.Notify(source, _L("no_command_permission"), "error")
            return
        end
    end
    
    local target = args[1] and tonumber(args[1]) or source
    
    if source == 0 and (not target or target == 0) then
        print("^1[plt_ambulance] Usage from console: /kill [id]^7")
        return
    end
    
    if target and IsPlayerValid(target) then
        if InternalKill(target) then
            if source ~= 0 then
                Framework.Notify(source, string.format("Player %s killed.", target), "success")
            else
                print(string.format("[plt_ambulance] Player %s killed.", target))
            end
        end
    else
        if source ~= 0 then
            Framework.Notify(source, _L("player_not_found"), "error")
        else
            print(string.format("[plt_ambulance] /kill failed: invalid player id %s", tostring(args[1])))
        end
    end
end, false)

AddEventHandler("txAdmin:events:healedPlayer", function(eventData)
    if GetInvokingResource() == "monitor" and type(eventData) == "table" then
        local id = tonumber(eventData.id)
        if not id then
            return
        end
        if id == -1 then
            for _, playerSrc in ipairs(GetPlayers()) do
                InternalHeal(tonumber(playerSrc))
            end
            return
        end
        InternalHeal(id)
    end
end)

AddEventHandler("txAdmin:events:revivedPlayer", function(eventData)
    if GetInvokingResource() == "monitor" and type(eventData) == "table" then
        local id = tonumber(eventData.id)
        if not id then
            return
        end
        if id == -1 then
            for _, playerSrc in ipairs(GetPlayers()) do
                InternalRevive(tonumber(playerSrc))
            end
            return
        end
        InternalRevive(id)
    end
end)

RegisterNetEvent("amb_server:HealPlayer", function(targetSrc, part, healType)
    local src = source
    local item = healType >= 2 and "plt_surgical_kit" or "plt_medkit"
    
    if Framework.RemoveItem(src, item, 1) then
        TriggerClientEvent("amb_client:HealPart", targetSrc, part, healType)
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    SavePlayerHealth(src)
    DownedState[src] = nil
    CachedHealth[src] = nil
end)

Framework.CreateUseableItem("plt_bandage", function(source)
    if not Framework.GetPlayer(source) then
        return
    end
    
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

local usableItems = {
    plt_painkillers = "amb_client:useMedication",
    plt_painkillers_adv = "amb_client:useMedication",
    plt_antibiotics = "amb_client:useMedication",
    plt_medkit = "amb_client:useMedication",
    iak_wheelchair = "amb_client:useWheelchair"
}

for itemName, eventName in pairs(usableItems) do
    Framework.CreateUseableItem(itemName, function(source, itemData)
        if not Framework.GetPlayer(source) then
            return
        end
        
        if IsPlayerDowned(source) and itemName ~= "iak_wheelchair" then
            Framework.Notify(source, _L("cannot_use_incapacitated"), "error")
            return false
        end
        
        local info = itemData and (itemData.info or itemData.metadata) or nil
        
        if Framework.RemoveItem(source, itemName, 1) then
            if eventName == "amb_client:useWheelchair" then
                local duration = info and info.duration or nil
                TriggerClientEvent(eventName, source, duration)
            else
                TriggerClientEvent(eventName, source, itemName, info)
            end
            return true
        end
        return false
    end)
end

RegisterNetEvent("amb_server:consumeMedication", function(itemName, slotData, forceOx)
    local src = source
    if not Framework.GetPlayer(src) then
        return
    end
    
    local eventName = usableItems[itemName] or (itemName == "plt_bandage" and "amb_client:selfBandage")
    if not eventName then
        return
    end
    
    if IsPlayerDowned(src) and itemName ~= "iak_wheelchair" then
        Framework.Notify(src, _L("cannot_use_incapacitated"), "error")
        return
    end
    
    local slotInfo
    if type(slotData) == "table" then
        slotInfo = tonumber(slotData.slot or slotData.id or slotData.slotId)
    elseif type(slotData) == "string" then
        slotInfo = tonumber(slotData)
    else
        slotInfo = slotData
    end
    
    local removed = Framework.RemoveItem(src, itemName, 1, slotInfo)
    
    if not removed and forceOx == true then
        if GetResourceState("ox_inventory") == "started" then
            removed = Framework.RemoveItem(src, itemName, 1)
        end
    end
    
    if removed then
        if itemName ~= "iak_wheelchair" then
            if eventName == "amb_client:useMedication" then
                TriggerClientEvent(eventName, src, itemName, nil)
            else
                TriggerClientEvent(eventName, src)
            end
        end
    else
        Framework.Notify(src, "Failed to use item. Try again.", "error")
    end
end)
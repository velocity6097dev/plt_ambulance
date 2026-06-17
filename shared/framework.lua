Framework = {}
Config.Framework = Config.Framework or "qb" -- "auto", "qb", "esx"

local function DetectFramework()
    if Config.Framework == "qb" then return "qb" end
    if Config.Framework == "esx" then return "esx" end

    if GetResourceState('qbx-core') == 'started' or GetResourceState('qbx_core') == 'started' then
        return "qb"
    elseif GetResourceState('qb-core') == 'started' or GetResourceState('qb_core') == 'started' then
        return "qb"
    elseif GetResourceState('es_extended') == 'started' then
        return "esx"
    end
    return nil
end

Framework.Type = DetectFramework()

local function ResolveQBCore()
    if GetResourceState('qb-core') == 'started' then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and core then return core end
    end
    if GetResourceState('qb_core') == 'started' then
        local ok, core = pcall(function() return exports['qb_core']:GetCoreObject() end)
        if ok and core then return core end
    end
    if GetResourceState('qbx-core') == 'started' then
        local ok, core = pcall(function() return exports['qbx-core']:GetCoreObject() end)
        if ok and core then return core end
    end
    if GetResourceState('qbx_core') == 'started' then
        local ok, core = pcall(function() return exports['qbx_core']:GetCoreObject() end)
        if ok and core then return core end
    end
    return nil
end

local function ResolveESXCore()
    if GetResourceState('es_extended') == 'started' then
        local ok, core = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and core then return core end
    end
    if type(ESX) == "table" then return ESX end
    local core = nil
    pcall(function()
        TriggerEvent('esx:getSharedObject', function(obj) core = obj end)
    end)
    return core
end

local function EnsureFrameworkReady()
    if Framework.Type == "qb" and Framework.Core and Framework.Core.Functions then
        return true
    elseif Framework.Type == "esx" and Framework.Core then
        return true
    end

    local detected = DetectFramework()
    if not detected then return false end

    local core = nil
    if detected == "qb" then
        core = ResolveQBCore()
    elseif detected == "esx" then
        core = ResolveESXCore()
    end
    if not core then return false end

    Framework.Type = detected
    Framework.Core = core
    if Framework.Type == "qb" and Framework.Core and Framework.Core.Functions and not Framework.Core.Functions.SetJob then
        Framework.Core.Functions.SetJob = function(src, job, grade)
            local player = Framework.Core.Functions.GetPlayer(src)
            if player then
                player.Functions.SetJob(job, grade)
            end
        end
    end
    return true
end

if EnsureFrameworkReady() then
    print("^2[plt_ambulance] Detected Framework:^7 " .. tostring(Framework.Type))
else
    print("^3[plt_ambulance] Framework not ready at startup, will retry lazily.^7")
end

local function NormalizeEsxDutyJob(jobName)
    local job = tostring(jobName or "")
    if job:sub(1, 4) == "off_" then
        return job:sub(5), false
    end
    if job:sub(1, 3) == "off" and #job > 3 then
        return job:sub(4), false
    end
    if job:sub(-8) == "_offduty" then
        return job:sub(1, -9), false
    end
    if job:sub(-4) == "_off" then
        return job:sub(1, -5), false
    end
    return job, true
end

if Framework.Type == "qb" then
    -- QBox/qbx_core provides qb-core; GetCoreObject is on qb-core interface
    Framework.Core = Framework.Core or ResolveQBCore()

    -- Add SetJob to QB-Core object if it doesn't exist
    if Framework.Core and Framework.Core.Functions and not Framework.Core.Functions.SetJob then
        Framework.Core.Functions.SetJob = function(src, job, grade)
            local player = Framework.Core.Functions.GetPlayer(src)
            if player then
                player.Functions.SetJob(job, grade)
            end
        end
    end
elseif Framework.Type == "esx" then
    Framework.Core = Framework.Core or ResolveESXCore()
end

-- Shared Functions
function Framework.GetPlayerData()
    if Framework.Type == "qb" then
        local data = Framework.Core.Functions.GetPlayerData()
        if not data or not data.job then return nil end
        return {
            citizenid = data.citizenid,
            name = data.charinfo.firstname .. " " .. data.charinfo.lastname,
            charinfo = data.charinfo,
            job = {
                name = data.job.name,
                label = data.job.label,
                grade = data.job.grade.level,
                gradeLabel = data.job.grade.name,
                onduty = data.job.onduty,
                dept = data.job.dept
            },
            money = data.money
        }
    elseif Framework.Type == "esx" then
        local data = Framework.Core.GetPlayerData()
        if not data or not data.job then return nil end
        local normalizedJob, onDuty = NormalizeEsxDutyJob(data.job.name)
        
        return {
            citizenid = data.identifier,
            name = data.firstName and (data.firstName .. " " .. data.lastName) or GetPlayerName(PlayerId()),
            charinfo = {
                firstname = data.firstName,
                lastname = data.lastName
            },
            job = {
                name = normalizedJob,
                rawName = data.job.name,
                label = data.job.label,
                grade = data.job.grade,
                gradeLabel = data.job.grade_label,
                onduty = onDuty,
                dept = nil
            },
            money = data.accounts
        }
    end
end

if IsDuplicityVersion() then
    -- Server Side
    local function IsOxInventory()
        return Config.Inventory == "ox" and GetResourceState('ox_inventory') == 'started'
    end

    local function GetTgiannResource()
        if GetResourceState('tgiann-inventory') == 'started' then return 'tgiann-inventory' end
        if GetResourceState('tgiann_inventory') == 'started' then return 'tgiann_inventory' end
        return nil
    end

    local function IsTgiannInventory()
        return Config.Inventory == "tgiann" and GetTgiannResource() ~= nil
    end

    local function GetQuasarResource()
        if GetResourceState('qs-inventory') == 'started' then return 'qs-inventory' end
        if GetResourceState('qs_inventory') == 'started' then return 'qs_inventory' end
        if GetResourceState('quasar-inventory') == 'started' then return 'quasar-inventory' end
        if GetResourceState('quasar_inventory') == 'started' then return 'quasar_inventory' end
        return nil
    end

    local function IsQuasarInventory()
        return Config.Inventory == "quasar" and GetQuasarResource() ~= nil
    end

    local function GetOriginResource()
        if GetResourceState('origin_inventory') == 'started' then return 'origin_inventory' end
        if GetResourceState('origin-inventory') == 'started' then return 'origin-inventory' end
        if GetResourceState('origen_inventory') == 'started' then return 'origen_inventory' end
        if GetResourceState('origen-inventory') == 'started' then return 'origen-inventory' end
        return nil
    end

    local function IsOriginInventory()
        return Config.Inventory == "origin" and GetOriginResource() ~= nil
    end

    local function GetCoreInventoryResource()
        if GetResourceState('core_inventory') == 'started' then return 'core_inventory' end
        if GetResourceState('core-inventory') == 'started' then return 'core-inventory' end
        return nil
    end

    local function IsCoreInventory()
        return Config.Inventory == "core" and GetCoreInventoryResource() ~= nil
    end

    local function TryTgiann(methodNames, ...)
        local res = GetTgiannResource()
        if not res then return false, nil end
        local args = { ... }
        for _, methodName in ipairs(methodNames) do
            local ok, result = pcall(function()
                return exports[res][methodName](table.unpack(args))
            end)
            if ok then
                return true, result
            end
        end
        return false, nil
    end

    local function TryQuasar(methodNames, ...)
        local res = GetQuasarResource()
        if not res then return false, nil end
        local args = { ... }
        for _, methodName in ipairs(methodNames) do
            local ok, result = pcall(function()
                return exports[res][methodName](table.unpack(args))
            end)
            if ok then
                return true, result
            end
        end
        return false, nil
    end

    local function TryOrigin(methodNames, ...)
        local res = GetOriginResource()
        if not res then return false, nil end
        local args = { ... }
        for _, methodName in ipairs(methodNames) do
            local ok, result = pcall(function()
                return exports[res][methodName](table.unpack(args))
            end)
            if ok then
                return true, result
            end
        end
        return false, nil
    end

    local function TryCoreInventory(methodNames, ...)
        local res = GetCoreInventoryResource()
        if not res then return false, nil end
        local args = { ... }
        for _, methodName in ipairs(methodNames) do
            local ok, result = pcall(function()
                return exports[res][methodName](table.unpack(args))
            end)
            if ok then
                return true, result
            end
        end
        return false, nil
    end

    local function IsInventoryActionSuccessful(result)
        if result == nil then return true end
        if type(result) == "boolean" then return result end
        if type(result) == "number" then return result >= 1 end
        if type(result) == "table" then
            if result.success ~= nil then return result.success == true end
            if result.status ~= nil then return result.status == true end
            if result.ok ~= nil then return result.ok == true end
            if result[1] ~= nil then
                if type(result[1]) == "boolean" then return result[1] == true end
                if type(result[1]) == "number" then return result[1] >= 1 end
            end
        end
        return false
    end

    function Framework.GetPlayers()
        if Framework.Type == "qb" then
            return Framework.Core.Functions.GetPlayers()
        elseif Framework.Type == "esx" then
            return Framework.Core.GetPlayers()
        end
        return GetPlayers() -- Fallback to standard CFX
    end

    function Framework.GetPlayer(src)
        if Framework.Type == "qb" then
            local p = Framework.Core.Functions.GetPlayer(src)
            if not p then return nil end
            
            local data = p.PlayerData
            
            return {
                source = src,
                PlayerData = data,
                citizenid = data.citizenid,
                identifier = data.citizenid,
                name = data.charinfo.firstname .. " " .. data.charinfo.lastname,
                charinfo = data.charinfo,
                job = {
                    name = data.job.name,
                    label = data.job.label,
                    grade = data.job.grade.level,
                    gradeLabel = data.job.grade.name,
                    onduty = data.job.onduty
                },
                functions = {
                    AddMoney = function(type, amount, reason) return p.Functions.AddMoney(type, amount, reason) end,
                    RemoveMoney = function(type, amount, reason) return p.Functions.RemoveMoney(type, amount, reason) end,
                    GetMoney = function(type) return p.Functions.GetMoney(type) end,
                    AddItem = function(item, amount, slot, info) return p.Functions.AddItem(item, amount, slot, info) end,
                    RemoveItem = function(item, amount, slot) return p.Functions.RemoveItem(item, amount, slot) end,
                    SetJobDuty = function(duty) return p.Functions.SetJobDuty(duty) end
                }
            }
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromId(src)
            if not p then return nil end
            local firstName = p.get('firstName') or ""
            local lastName = p.get('lastName') or ""
            local name = (firstName ~= "" and lastName ~= "") and (firstName .. " " .. lastName) or p.getName()
            local normalizedJob, onDuty = NormalizeEsxDutyJob(p.job.name)
            
            return {
                source = src,
                citizenid = p.identifier,
                identifier = p.identifier,
                name = name,
                charinfo = {
                    firstname = firstName,
                    lastname = lastName
                },
                job = {
                    name = normalizedJob,
                    rawName = p.job.name,
                    label = p.job.label,
                    grade = p.job.grade,
                    gradeLabel = p.job.grade_label,
                    onduty = onDuty
                },
                functions = {
                    AddMoney = function(type, amount, reason) 
                        if type == "cash" then p.addAccountMoney('money', amount)
                        else p.addAccountMoney(type, amount) end
                        return true
                    end,
                    RemoveMoney = function(type, amount, reason) 
                        local acc = type == "cash" and "money" or type
                        if p.getAccount(acc).money >= amount then
                            p.removeAccountMoney(acc, amount)
                            return true
                        end
                        return false
                    end,
                    GetMoney = function(type)
                        local acc = type == "cash" and "money" or type
                        return p.getAccount(acc).money
                    end,
                    AddItem = function(item, amount, slot, info) p.addInventoryItem(item, amount); return true end,
                    RemoveItem = function(item, amount, slot) p.removeInventoryItem(item, amount); return true end
                }
            }
        end
    end

    function Framework.GetPlayerByCitizenId(cid)
        if Framework.Type == "qb" then
            local p = Framework.Core.Functions.GetPlayerByCitizenId(cid)
            if not p then return nil end
            return Framework.GetPlayer(p.PlayerData.source)
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromIdentifier(cid)
            if not p then return nil end
            return Framework.GetPlayer(p.source)
        end
    end

    function Framework.CreateCallback(name, cb)
        local attempts = 0
        while not EnsureFrameworkReady() and attempts < 100 do
            attempts = attempts + 1
            Wait(50)
        end

        if Framework.Type == "qb" then
            if Framework.Core and Framework.Core.Functions and Framework.Core.Functions.CreateCallback then
                Framework.Core.Functions.CreateCallback(name, cb)
            end
        elseif Framework.Type == "esx" then
            if Framework.Core and Framework.Core.RegisterServerCallback then
                Framework.Core.RegisterServerCallback(name, cb)
            elseif type(ESX) == "table" and ESX.RegisterServerCallback then
                ESX.RegisterServerCallback(name, cb)
            end
        end
    end

    function Framework.SetMetaData(src, key, value)
        if Framework.Type == "qb" then
            local p = Framework.Core.Functions.GetPlayer(src)
            if p then p.Functions.SetMetaData(key, value) end
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromId(src)
            if p then p.set(key, value) end
        end
    end

    function Framework.SetJob(src, job, grade)
        if Framework.Type == "qb" then
            local p = Framework.Core.Functions.GetPlayer(src)
            if p then p.Functions.SetJob(job, grade) end
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromId(src)
            if p then p.setJob(job, tonumber(grade) or 0) end
        end
    end

    function Framework.GetMetaData(src, key)
        if Framework.Type == "qb" then
            local p = Framework.Core.Functions.GetPlayer(src)
            if p then return p.PlayerData.metadata[key] end
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromId(src)
            if p then return p.get(key) end
        end
        return nil
    end

    function Framework.Notify(src, msg, type)
        TriggerClientEvent('amb_client:Notify', src, msg, type)
    end

    function Framework.HasPermission(src, perm)
        EnsureFrameworkReady()
        if Framework.Type == "qb" then
            if Framework.Core and Framework.Core.Functions then
                if Framework.Core.Functions.HasPermission then
                    local ok, hasPerm = pcall(Framework.Core.Functions.HasPermission, src, perm)
                    if ok and hasPerm then
                        return true
                    end
                end

                -- QBcore compatibility: some installs expose permissions through GetPermission
                -- as a string ("admin") or table ({ admin = true } / { "admin" }).
                if Framework.Core.Functions.GetPermission then
                    local ok, perms = pcall(Framework.Core.Functions.GetPermission, src)
                    if ok and perms then
                        if type(perms) == "string" then
                            local p = perms:lower()
                            if p == tostring(perm):lower() or p == "admin" or p == "god" then
                                return true
                            end
                        elseif type(perms) == "table" then
                            local wanted = tostring(perm):lower()
                            if perms[wanted] == true or perms["admin"] == true or perms["god"] == true then
                                return true
                            end
                            for _, entry in pairs(perms) do
                                if type(entry) == "string" then
                                    local p = entry:lower()
                                    if p == wanted or p == "admin" or p == "god" then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- Fallback to ACE permissions
            return IsPlayerAceAllowed(src, "admin")
                or IsPlayerAceAllowed(src, "command")
                or IsPlayerAceAllowed(src, "group.admin")
                or IsPlayerAceAllowed(src, "group.god")
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromId(src)
            if not p then return false end
            local group = (type(p.getGroup) == "function" and p.getGroup()) or "user"
            if group == perm or group == 'admin' or group == 'superadmin' or group == 'owner' then
                return true
            end
            -- Common fallback for ESX installs using ACE rather than ESX groups.
            return IsPlayerAceAllowed(src, "admin") or IsPlayerAceAllowed(src, "command")
        end
        return false
    end

    function Framework.HasJob(src, jobName)
        local p = Framework.GetPlayer(src)
        if not p or not p.job then return false end
        if type(jobName) == "table" then
            for _, job in ipairs(jobName) do
                if p.job.name == job then return true end
            end
        else
            return p.job.name == jobName
        end
        return false
    end

    function Framework.SetDeathStatus(src, status)
        if Framework.Type == "qb" then
            local p = Framework.Core.Functions.GetPlayer(src)
            if p then
                local qbAmbulanceRunning = GetResourceState('qb-ambulancejob') == 'started'
                -- Optimization: Use a single metadata update if possible to avoid multiple massive QBCore syncs
                local metadata = {}
                local needsUpdate = false
                
                -- Compatibility guard:
                -- If qb-ambulancejob is running, avoid driving QBCore death metadata from this
                -- resource because that can trigger qb-ambulance's own death/respawn pipeline.
                -- We still force-clear stale flags on revive so players never remain "dead".
                if not qbAmbulanceRunning then
                    if p.PlayerData.metadata["isdead"] ~= status then
                        metadata["isdead"] = status
                        needsUpdate = true
                    end

                    -- Keep inlaststand disabled for this script's custom downed system.
                    if p.PlayerData.metadata["inlaststand"] ~= false then
                        metadata["inlaststand"] = false
                        needsUpdate = true
                    end
                elseif not status then
                    if p.PlayerData.metadata["isdead"] ~= false then
                        metadata["isdead"] = false
                        needsUpdate = true
                    end
                    if p.PlayerData.metadata["inlaststand"] ~= false then
                        metadata["inlaststand"] = false
                        needsUpdate = true
                    end
                end
                
                if not status then
                    -- Force reset on revive for consistent post-revive state.
                    metadata["hunger"] = 100
                    metadata["thirst"] = 100
                    metadata["stress"] = 0
                    needsUpdate = true

                    -- Qbox/QBX HUD and consumables use player statebag values.
                    -- Keep state and metadata in sync to guarantee immediate HUD update.
                    local pState = Player(src) and Player(src).state
                    if pState then
                        pState:set('hunger', 100, true)
                        pState:set('thirst', 100, true)
                        pState:set('stress', 0, true)
                    end

                    -- QBcore HUD compatibility (non-QBox stacks often rely on these events).
                    TriggerClientEvent('hud:client:UpdateNeeds', src, 100, 100)
                    TriggerClientEvent('hud:client:UpdateStress', src, 0)
                end
                
                if needsUpdate then
                    if type(p.Functions.SetMetaData) == "function" then
                        -- Set values in the local object first to ensure consistency
                        for k, v in pairs(metadata) do
                            p.PlayerData.metadata[k] = v
                            p.Functions.SetMetaData(k, v)
                        end

                        -- Some QBCore versions require a full sync after multiple metadata updates
                        -- to ensure the client-side PlayerData is perfectly in sync.
                        if not status and type(p.Functions.UpdatePlayerData) == "function" then
                            p.Functions.UpdatePlayerData()
                        end
                    end
                end
                
                -- QBCore mode: use internal event name to avoid cross-resource
                -- death/respawn conflicts with other hospital scripts.
                if Framework.Type == "qb" then
                    TriggerClientEvent("amb_client:SetDeathStatus", src, status)
                else
                    TriggerClientEvent("hospital:client:SetDeathStatus", src, status)
                end
            end
        elseif Framework.Type == "esx" then
            local p = Framework.Core.GetPlayerFromId(src)
            if p then 
                p.set('is_dead', status) 
                if not status then
                    TriggerClientEvent('esx_status:set', src, 'hunger', 1000000)
                    TriggerClientEvent('esx_status:set', src, 'thirst', 1000000)
                    TriggerClientEvent('esx_status:set', src, 'stress', 0) -- Clear stress if using esx_status/stress
                end
            end
        end
    end

    function Framework.CreateUseableItem(name, cb)
        if Framework.Type == "qb" then
            Framework.Core.Functions.CreateUseableItem(name, function(source, item)
                cb(source, item)
            end)
        elseif Framework.Type == "esx" then
            Framework.Core.RegisterUsableItem(name, function(source)
                -- ESX doesn't always pass the item, but some versions do.
                -- We'll just pass source and let the handler fetch if needed.
                cb(source)
            end)
        end
    end

    function Framework.AddItem(src, item, amount, metadata, slot)
        if type(metadata) == "number" and slot == nil then
            slot = metadata
            metadata = nil
        end

        if IsOxInventory() then
            return exports.ox_inventory:AddItem(src, item, amount, metadata, slot)
        end

        if IsTgiannInventory() then
            local ok, result = TryTgiann({ "AddItem", "addItem", "GiveItem", "giveItem" }, src, item, amount, metadata, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end
        if IsQuasarInventory() then
            local ok, result = TryQuasar({ "AddItem", "addItem", "GiveItem", "giveItem" }, src, item, amount, metadata, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end
        if IsOriginInventory() then
            local ok, result = TryOrigin({
                "AddItem", "addItem", "GiveItem", "giveItem",
                "AddInventoryItem", "addInventoryItem"
            }, src, item, amount, metadata, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end
        if IsCoreInventory() then
            local ok, result = TryCoreInventory({
                "AddItem", "addItem",
                "AddInventoryItem", "addInventoryItem",
                "GiveItem", "giveItem"
            }, src, item, amount, metadata, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end

        local p = Framework.GetPlayer(src)
        if p and p.functions then
            return p.functions.AddItem(item, amount, slot, metadata)
        end
        return false
    end

    function Framework.RemoveItem(src, item, amount, slot)
        if IsOxInventory() then
            if slot then
                return exports.ox_inventory:RemoveItem(src, item, amount, nil, slot)
            end
            return exports.ox_inventory:RemoveItem(src, item, amount)
        end

        if IsTgiannInventory() then
            local ok, result = TryTgiann({ "RemoveItem", "removeItem", "TakeItem", "takeItem" }, src, item, amount, slot)
            if ok then return result == nil or result == true end
        end
        if IsQuasarInventory() then
            local ok, result = TryQuasar({ "RemoveItem", "removeItem", "TakeItem", "takeItem" }, src, item, amount, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end
        if IsOriginInventory() then
            local ok, result = TryOrigin({
                "RemoveItem", "removeItem", "TakeItem", "takeItem",
                "RemoveInventoryItem", "removeInventoryItem"
            }, src, item, amount, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end
        if IsCoreInventory() then
            local ok, result = TryCoreInventory({
                "RemoveItem", "removeItem",
                "TakeItem", "takeItem",
                "RemoveInventoryItem", "removeInventoryItem"
            }, src, item, amount, slot)
            if ok then return IsInventoryActionSuccessful(result) end
        end

        local p = Framework.GetPlayer(src)
        if p and p.functions then
            return p.functions.RemoveItem(item, amount, slot)
        end
        return false
    end

    function Framework.GetItemCount(src, item)
        if IsOxInventory() then
            return exports.ox_inventory:GetItemCount(src, item)
        end

        if IsTgiannInventory() then
            local ok, result = TryTgiann({ "GetItemCount", "getItemCount", "Search", "search" }, src, item)
            if ok and tonumber(result) then
                return tonumber(result)
            end
        end
        if IsQuasarInventory() then
            local ok, result = TryQuasar({ "GetItemTotalAmount", "getItemTotalAmount", "GetItemCount", "getItemCount", "Search", "search" }, src, item)
            if ok and tonumber(result) then
                return tonumber(result)
            end
        end
        if IsOriginInventory() then
            local ok, result = TryOrigin({
                "GetItemTotalAmount", "getItemTotalAmount",
                "GetItemCount", "getItemCount",
                "Search", "search"
            }, src, item)
            if ok and tonumber(result) then
                return tonumber(result)
            end
        end
        if IsCoreInventory() then
            local ok, result = TryCoreInventory({
                "GetItemCount", "getItemCount",
                "GetItemTotalAmount", "getItemTotalAmount",
                "Search", "search"
            }, src, item)
            if ok and tonumber(result) then
                return tonumber(result)
            end
        end

        local p = Framework.GetPlayer(src)
        if p and p.PlayerData and p.PlayerData.items then
            local count = 0
            for _, i in pairs(p.PlayerData.items) do
                if i and i.name == item then
                    count = count + (tonumber(i.amount or i.count or i.quantity) or 0)
                end
            end
            return count
        end
        return 0
    end

    function Framework.CanCarryItem(src, item, amount)
        if IsOxInventory() then
            return exports.ox_inventory:CanCarryItem(src, item, amount)
        end

        if IsTgiannInventory() then
            local ok, result = TryTgiann({ "CanCarryItem", "canCarryItem", "CanCarry", "canCarry" }, src, item, amount)
            if ok then
                return result == nil or result == true
            end
        end
        if IsQuasarInventory() then
            local ok, result = TryQuasar({ "CanCarryItem", "canCarryItem", "CanCarry", "canCarry" }, src, item, amount)
            if ok then
                return IsInventoryActionSuccessful(result)
            end
        end
        if IsOriginInventory() then
            local ok, result = TryOrigin({ "CanCarryItem", "canCarryItem", "CanCarry", "canCarry" }, src, item, amount)
            if ok then
                return IsInventoryActionSuccessful(result)
            end
        end
        if IsCoreInventory() then
            local ok, result = TryCoreInventory({ "CanCarryItem", "canCarryItem", "CanCarry", "canCarry" }, src, item, amount)
            if ok then
                return IsInventoryActionSuccessful(result)
            end
        end

        return true -- QB/tgiann/quasar/origin/core fallback when no explicit carry API exists
    end

else
    -- Client Side
    function Framework.Notify(msg, type)
        TriggerEvent('amb_client:Notify', msg, type)
    end

    function Framework.TriggerCallback(name, cb, ...)
        EnsureFrameworkReady()
        if Framework.Type == "qb" then
            if Framework.Core and Framework.Core.Functions and Framework.Core.Functions.TriggerCallback then
                Framework.Core.Functions.TriggerCallback(name, cb, ...)
            end
        elseif Framework.Type == "esx" then
            local args = { ... }
            if Framework.Core and Framework.Core.TriggerServerCallback then
                Framework.Core.TriggerServerCallback(name, cb, table.unpack(args))
            elseif type(ESX) == "table" and ESX.TriggerServerCallback then
                ESX.TriggerServerCallback(name, cb, table.unpack(args))
            else
                local done = false
                pcall(function()
                    TriggerEvent('esx:getSharedObject', function(obj)
                        if obj and obj.TriggerServerCallback then
                            Framework.Core = obj
                            Framework.Type = "esx"
                            obj.TriggerServerCallback(name, cb, table.unpack(args))
                            done = true
                        end
                    end)
                end)
                if not done then
                    return
                end
            end
        end
    end

    function Framework.SetVehicleProperties(veh, props)
        if Framework.Type == "qb" then
            Framework.Core.Functions.SetVehicleProperties(veh, props)
        elseif Framework.Type == "esx" then
            Framework.Core.Game.SetVehicleProperties(veh, props)
        end
    end

    function Framework.GetPlate(veh)
        if Framework.Type == "qb" then
            return Framework.Core.Functions.GetPlate(veh)
        elseif Framework.Type == "esx" then
            return GetVehicleNumberPlateText(veh)
        end
    end

    function Framework.GetClosestPlayer()
        if Framework.Type == "qb" then
            return Framework.Core.Functions.GetClosestPlayer()
        elseif Framework.Type == "esx" then
            return Framework.Core.Game.GetClosestPlayer()
        end
    end

    function Framework.GetClosestVehicle(coords)
        if Framework.Type == "qb" then
            return Framework.Core.Functions.GetClosestVehicle(coords)
        elseif Framework.Type == "esx" then
            return Framework.Core.Game.GetClosestVehicle(coords)
        end
    end

    function Framework.DeleteVehicle(veh)
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end

    function Framework.Progressbar(name, label, duration, useLib, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)
        if Framework.Type == "qb" then
            Framework.Core.Functions.Progressbar(name, label, duration, false, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)
        elseif Framework.Type == "esx" then
            CreateThread(function()
                Wait(duration)
                if onFinish then onFinish() end
            end)
        else
            -- Standalone fallback
            Wait(duration)
            if onFinish then onFinish() end
        end
    end

    function Framework.ShowTextUI(msg, type)
        if Framework.Type == "qb" then
            TriggerEvent('qb-core:client:DrawText', msg, 'right')
        elseif Framework.Type == "esx" then
            -- Common ESX TextUI (Standard help text)
            AddTextEntry('amb_helptext', msg)
            BeginTextCommandDisplayHelp('amb_helptext')
            EndTextCommandDisplayHelp(0, false, true, -1)
        end
    end

    function Framework.HideTextUI()
        if Framework.Type == "qb" then
            TriggerEvent('qb-core:client:HideText')
        end
    end

    function Framework.RequestAnimDict(dict)
        RequestAnimDict(dict)
        local timeout = 0
        while not HasAnimDictLoaded(dict) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end
    end

    function Framework.RequestAnimSet(set)
        RequestAnimSet(set)
        local timeout = 0
        while not HasAnimSetLoaded(set) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end
    end

    function Framework.RequestModel(model)
        RequestModel(model)
        local timeout = 0
        while not HasModelLoaded(model) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end
    end

    function Framework.ProgressBar(label, duration)
        local completed = false
        local finished = false
        
        if Framework.Type == "qb" then
            Framework.Core.Functions.Progressbar("amb_action", label, duration, false, true, {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            }, {}, {}, {}, function()
                completed = true
                finished = true
            end, function()
                completed = false
                finished = true
            end)
        else
            local start = GetGameTimer()
            while GetGameTimer() - start < duration do
                Wait(0)
                local progress = (GetGameTimer() - start) / duration
                DrawRect(0.5, 0.9, 0.2, 0.03, 0, 0, 0, 150)
                DrawRect(0.5 - (0.1 * (1.0 - progress)), 0.9, 0.2 * progress, 0.03, 0, 255, 204, 200)
                if IsControlJustPressed(0, 177) then finished = true; completed = false; break end
            end
            if not finished then completed = true; finished = true end
        end

        while not finished do Wait(10) end
        return completed
    end

    function Framework.HasJob(jobName)
        local data = Framework.GetPlayerData()
        if not data or not data.job then return false end
        if type(jobName) == "table" then
            for _, job in ipairs(jobName) do
                if data.job.name == job then return true end
            end
        else
            return data.job.name == jobName
        end
        return false
    end

    function Framework.GiveKeys(veh)
        local plate = Framework.GetPlate(veh)
        if not plate then return end

        -- QB-VehicleKeys
        if GetResourceState('qb-vehiclekeys') == 'started' then
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end

        -- Wasabi Carkeys
        if GetResourceState('wasabi_carkeys') == 'started' then
            exports.wasabi_carkeys:GiveKeys(plate)
        end

        -- CD Vehicle Keys
        if GetResourceState('cd_garage') == 'started' then
            TriggerEvent('cd_garage:AddKeys', plate)
        end

        -- OKOK Vehicle Keys
        if GetResourceState('okokGarage') == 'started' then
            TriggerEvent('okokGarage:GiveKeys', plate)
        end

        -- Generic fallback for other scripts that listen for this common event
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    end
end


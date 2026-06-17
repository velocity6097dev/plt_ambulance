-- ==========================================
-- Global Cache & Variables
-- ==========================================
DepartmentData = { nodes = {}, links = {}, pan = { x = 0, y = 0, zoom = 1 }, divisions = {} }
MemberData = {}
DeptDutyLogs = {}
DataLoaded = false

local ESXJobGradesCache = {}
local PreparedStashes = {}

-- ==========================================
-- Database Initialization & Migrations
-- ==========================================

local function InitializeDatabase()
    local tables = {
        [[CREATE TABLE IF NOT EXISTS `plt_ambulance_job_data` (
            `key` VARCHAR(50) PRIMARY KEY,
            `value` LONGTEXT DEFAULT NULL
        );]],
        [[CREATE TABLE IF NOT EXISTS `plt_ambulance_job_members` (
            `citizenid` varchar(50) NOT NULL PRIMARY KEY,
            `name` varchar(100) DEFAULT NULL,
            `job` varchar(50) DEFAULT NULL,
            `grade` int(11) DEFAULT 0,
            `jobLabel` varchar(100) DEFAULT NULL,
            `gradeLabel` varchar(100) DEFAULT NULL,
            `ratings` LONGTEXT DEFAULT NULL
        );]],
        [[CREATE TABLE IF NOT EXISTS `plt_ambulance_job_pcrs` (
            `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `patient` varchar(100) DEFAULT NULL,
            `condition` varchar(255) DEFAULT NULL,
            `treatment` text DEFAULT NULL,
            `author` varchar(100) DEFAULT NULL,
            `date` varchar(50) DEFAULT NULL,
            `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP
        );]],
        [[CREATE TABLE IF NOT EXISTS `plt_ambulance_job_xrays` (
            `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `citizenid` varchar(50) DEFAULT NULL,
            `injuries` text DEFAULT NULL,
            `date` varchar(50) DEFAULT NULL,
            `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP
        );]],
        [[CREATE TABLE IF NOT EXISTS `plt_ambulance_job_duty_logs` (
            `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `dept_job` varchar(50) DEFAULT NULL,
            `officer` varchar(100) DEFAULT NULL,
            `action` varchar(50) DEFAULT NULL,
            `date` varchar(50) DEFAULT NULL,
            `time` varchar(20) DEFAULT NULL,
            `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_dept_job` (`dept_job`),
            INDEX `idx_timestamp` (`timestamp`)
        );]],
        [[CREATE TABLE IF NOT EXISTS `plt_ambulance_job_mails` (
            `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `sender_dept` varchar(50) DEFAULT NULL,
            `receiver_dept` varchar(50) DEFAULT NULL,
            `sender_name` varchar(100) DEFAULT NULL,
            `subject` varchar(255) DEFAULT NULL,
            `message` longtext DEFAULT NULL,
            `image_url` varchar(500) DEFAULT NULL,
            `date` varchar(50) DEFAULT NULL,
            `time` varchar(20) DEFAULT NULL,
            `is_read` tinyint(1) DEFAULT 0,
            `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP
        );]]
    }

    for _, query in ipairs(tables) do
        local success = pcall(function() MySQL.Sync.execute(query, {}) end)
        if not success then print("^1[plt_ambulance] SQL init query failed, continuing.^7") end
    end
end

local function CheckColumnExists(tableName, columnName)
    local success, result = pcall(function()
        return MySQL.Sync.fetchAll([[
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1
        ]], {tableName, columnName})
    end)
    return (success and result and result[1] ~= nil)
end

local function RunDutyLogsMigrations()
    local tableName = "plt_ambulance_job_duty_logs"
    if not CheckColumnExists(tableName, "dept_job") then
        local added = pcall(function()
            MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD COLUMN `dept_job` varchar(50) DEFAULT NULL AFTER `id`", tableName), {})
        end)
        if not added then print("^1[plt_ambulance] Failed to add dept_job column to duty logs table.^7") end
    end

    if CheckColumnExists(tableName, "dept_job") and CheckColumnExists(tableName, "job") then
        pcall(function()
            MySQL.Sync.execute(string.format("UPDATE `%s` SET `dept_job` = `job` WHERE (`dept_job` IS NULL OR `dept_job` = '') AND `job` IS NOT NULL AND `job` != ''", tableName), {})
        end)
    end

    if CheckColumnExists(tableName, "dept_job") then
        pcall(function() MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD INDEX `idx_dept_job` (`dept_job`)", tableName), {}) end)
    end
    pcall(function() MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD INDEX `idx_timestamp` (`timestamp`)", tableName), {}) end)
end

local function RunMailsMigrations()
    local tableName = "plt_ambulance_job_mails"
    if not CheckColumnExists(tableName, "image_url") then
        local added = pcall(function()
            MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD COLUMN `image_url` varchar(500) DEFAULT NULL AFTER `message`", tableName), {})
        end)
        if not added then print("^1[plt_ambulance] Failed to add image_url column to mails table.^7") end
    end
end

-- ==========================================
-- Utility Functions
-- ==========================================

local function ValidateDepartmentData(data)
    if type(data) ~= "table" then
        return { nodes = {}, links = {}, pan = { x = 0, y = 0, zoom = 1 }, divisions = {} }
    end
    if type(data.nodes) ~= "table" then data.nodes = {} end
    if type(data.links) ~= "table" then data.links = {} end
    if type(data.pan) ~= "table" then data.pan = { x = 0, y = 0, zoom = 1 } end
    if type(data.divisions) ~= "table" then data.divisions = {} end
    return data
end

local function DecodeDepartmentData(jsonStr)
    if not jsonStr or jsonStr == "" then return nil end
    local success, decoded = pcall(json.decode, jsonStr)
    if success and type(decoded) == "table" then
        return ValidateDepartmentData(decoded)
    end
    return nil
end

local function SaveDataToDB(key, value)
    if not key or not value then return false end
    
    local success = pcall(function()
        MySQL.Sync.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)", {key, value})
    end)
    if success then return true end

    -- Fallback syntax
    success = pcall(function()
        MySQL.Sync.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
            ["@key"] = key, ["@value"] = value
        })
    end)
    return success
end

function SaveDepartments()
    DepartmentData = ValidateDepartmentData(DepartmentData)
    local encoded = json.encode(DepartmentData)
    
    if not encoded or encoded == "" or encoded == "null" then
        print("^1[plt_ambulance] SaveDepartments aborted: failed to encode department data.^7")
        return false
    end
    
    local s1 = SaveDataToDB("departments", encoded)
    local s2 = SaveDataToDB("departments_backup", encoded)
    
    if not s1 or not s2 then
        print("^1[plt_ambulance] SaveDepartments warning: SQL write failed.^7")
    end
    
    if not s1 and not s2 then return false end
    
    TriggerClientEvent("amb_client:SyncJobs", -1, DepartmentData)
    return true
end

-- ==========================================
-- Core Loading
-- ==========================================

local function LoadAllData()
    local success, dbData = pcall(function() return MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_data", {}) end)
    if not success or type(dbData) ~= "table" then
        print("^3[plt_ambulance] Department DB load failed, trying local cache fallback.^7")
        dbData = {}
    end

    local mainCache, backupCache = nil, nil
    for _, row in ipairs(dbData) do
        if row.key == "departments" then mainCache = row.value
        elseif row.key == "departments_backup" then backupCache = row.value end
    end

    local decodedMain = DecodeDepartmentData(mainCache)
    local decodedBackup = DecodeDepartmentData(backupCache)

    if decodedMain and #decodedMain.nodes > 0 then
        DepartmentData = decodedMain
    elseif decodedBackup and #decodedBackup.nodes > 0 then
        DepartmentData = decodedBackup
        print("^3[plt_ambulance] departments row was empty/invalid, restored from departments_backup.^7")
        SaveDataToDB("departments", json.encode(DepartmentData))
    else
        DepartmentData = ValidateDepartmentData(DepartmentData)
    end

    -- Load Members
    local memSuccess, memData = pcall(function() return MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_members", {}) end)
    if memSuccess and type(memData) == "table" then
        for _, row in ipairs(memData) do
            MemberData[row.citizenid] = {
                name = row.name,
                job = row.job or "none",
                grade = row.grade,
                jobLabel = row.jobLabel or "Not Hired",
                gradeLabel = row.gradeLabel or "Civilian",
                ratings = json.decode(row.ratings or "{}")
            }
        end
    else
        print("^3[plt_ambulance] Member DB load failed; continuing with empty member cache.^7")
    end

    -- Load Duty Logs
    local logsSuccess, logData = pcall(function()
        return MySQL.Sync.fetchAll("SELECT dept_job, officer, action, `date`, `time` FROM plt_ambulance_job_duty_logs ORDER BY id DESC", {})
    end)
    
    if not logsSuccess or not logData then
        logsSuccess, logData = pcall(function()
            return MySQL.Sync.fetchAll("SELECT `job` AS dept_job, officer, action, `date`, `time` FROM plt_ambulance_job_duty_logs ORDER BY id DESC", {})
        end)
    end

    if logsSuccess and logData then
        for _, row in ipairs(logData) do
            local dept = row.dept_job or "ambulance"
            if not DeptDutyLogs[dept] then DeptDutyLogs[dept] = {} end
            
            if #DeptDutyLogs[dept] < 100 then
                table.insert(DeptDutyLogs[dept], {
                    officer = row.officer, action = row.action,
                    date = row.date, time = row.time
                })
            end
        end
    end

    DataLoaded = true
end

-- Start initialization
InitializeDatabase()
RunDutyLogsMigrations()
RunMailsMigrations()
LoadAllData()

CreateThread(function()
    Wait(1500)
    TriggerClientEvent("amb_client:SyncJobs", -1, DepartmentData)
    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
end)

-- ==========================================
-- Identifiers & Permissions
-- ==========================================

function GetFrameworkJobForDepartment(deptId)
    if not DepartmentData or not DepartmentData.nodes then return deptId end
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" and node.id == deptId then
            if node.frameworkJob and node.frameworkJob ~= "" then return node.frameworkJob end
            return deptId
        end
    end
    return deptId
end
exports("GetFrameworkJobForDepartment", GetFrameworkJobForDepartment)

function GetDepartmentIdForFrameworkJob(fwJob)
    if not DepartmentData or not DepartmentData.nodes then return nil end
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            local checkJob = (node.frameworkJob and node.frameworkJob ~= "") and node.frameworkJob or node.id
            if tostring(checkJob) == tostring(fwJob) then return node.id end
        end
    end
    return nil
end
exports("GetDepartmentIdForFrameworkJob", GetDepartmentIdForFrameworkJob)

function IsEMS(source)
    if Framework.HasPermission(source, Config.Permission) or Config.AdminBypass then return true end

    local player = Framework.GetPlayer(source)
    if not player then return false end

    local fwJobName = (player.job and player.job.name) or "none"
    local citizenId = player.citizenid
    local memJobName = (MemberData[citizenId] and MemberData[citizenId].job) or "none"

    -- Check Config array
    if Config.Medical and Config.Medical.EMSJobs then
        for _, job in ipairs(Config.Medical.EMSJobs) do
            if fwJobName == job or memJobName == job then return true end
        end
    end

    -- Check Node Departments
    if DepartmentData and DepartmentData.nodes then
        for _, node in ipairs(DepartmentData.nodes) do
            if node.type == "department" then
                local deptFwJob = (node.frameworkJob and node.frameworkJob ~= "") and node.frameworkJob or node.id
                if tostring(fwJobName) == tostring(node.id) or tostring(fwJobName) == tostring(deptFwJob) or tostring(memJobName) == tostring(node.id) then
                    return true
                end
            end
        end
    end
    return false
end
exports("IsEMS", IsEMS)

-- ==========================================
-- Callbacks & Net Events
-- ==========================================

Framework.CreateCallback("amb_server:getData", function(source, cb)
    local timeout = 0
    while not DataLoaded and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    cb({ dept = DepartmentData, members = MemberData })
end)

RegisterNetEvent("amb_server:save", function(data)
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then
        return Framework.Notify(src, _L("no_command_permission"), "error")
    end

    if data then
        if type(data) ~= "table" then
            return Framework.Notify(src, "Invalid department data format.", "error")
        end
        
        data = ValidateDepartmentData(data)
        local incomingNodes = #data.nodes
        local currentNodes = #(DepartmentData.nodes or {})
        
        if currentNodes > 0 and incomingNodes == 0 then
            Framework.Notify(src, "Blocked save: received empty nodes while existing configuration is not empty.", "error")
            print(string.format("[plt_ambulance] Blocked potentially destructive save from %s (%s): existingNodes=%s incomingNodes=%s", GetPlayerName(src) or "unknown", tostring(src), tostring(currentNodes), tostring(incomingNodes)))
            return
        end
        
        DepartmentData = data
        if SaveDepartments() then
            Framework.Notify(src, _L("config_saved_synced"), "success")
        else
            Framework.Notify(src, "Failed to persist department data.", "error")
        end
    end
end)

function GetPlayersList()
    local result = {}
    local onlineTracker = {}
    
    for _, playerId in ipairs(GetPlayers()) do
        local player = Framework.GetPlayer(tonumber(playerId))
        if player then
            local cid = player.citizenid
            local memData = MemberData[cid]
            
            table.insert(result, {
                id = tonumber(playerId),
                cid = cid,
                name = player.name,
                jobName = (memData and memData.job) or "none",
                jobLabel = (memData and memData.jobLabel) or "Not Hired",
                jobGradeLabel = (memData and memData.gradeLabel) or "Civilian",
                jobGradeLevel = (memData and memData.grade) or 0,
                isOnline = true
            })
            onlineTracker[cid] = true
        end
    end

    for cid, memData in pairs(MemberData) do
        if not onlineTracker[cid] then
            table.insert(result, {
                id = 0,
                cid = cid,
                name = memData.name or "Unknown",
                jobName = memData.job or "none",
                jobLabel = memData.jobLabel or "Not Hired",
                jobGradeLabel = memData.gradeLabel or "None",
                jobGradeLevel = memData.grade or 0,
                isOnline = false
            })
        end
    end
    return result
end

Framework.CreateCallback("amb_server:getPlayers", function(source, cb)
    cb(GetPlayersList())
end)

-- ==========================================
-- Member Data Syncing
-- ==========================================

function SaveMemberToDB(cid)
    local data = MemberData[cid]
    if not data then return end

    MySQL.Async.execute([[
        INSERT INTO plt_ambulance_job_members (`citizenid`, `name`, `job`, `grade`, `jobLabel`, `gradeLabel`, `ratings`) 
        VALUES (@cid, @name, @job, @grade, @jobLabel, @gradeLabel, @ratings) 
        ON DUPLICATE KEY UPDATE `name` = @name, `job` = @job, `grade` = @grade, `jobLabel` = @jobLabel, `gradeLabel` = @gradeLabel, `ratings` = @ratings
    ]], {
        ["@cid"] = cid,
        ["@name"] = data.name,
        ["@job"] = data.job,
        ["@grade"] = data.grade,
        ["@jobLabel"] = data.jobLabel,
        ["@gradeLabel"] = data.gradeLabel,
        ["@ratings"] = json.encode(data.ratings or {})
    })
    
    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
end

function SyncPlayerJobWithMemberData(source)
    local player = Framework.GetPlayer(source)
    if not player then return end

    local jobName = player.job.name
    local gradeLevel = tonumber(player.job.grade) or 0
    local cid = player.citizenid

    local deptId = GetDepartmentIdForFrameworkJob(jobName)
    if deptId then
        local jobLabel = "Unknown"
        local gradeLabel = "Rank " .. gradeLevel
        
        -- Parse labels from department data
        if DepartmentData and DepartmentData.nodes then
            for _, node in ipairs(DepartmentData.nodes) do
                if node.type == "department" and node.id == deptId then
                    jobLabel = node.label or deptId
                    if DepartmentData.links then
                        for _, link in ipairs(DepartmentData.links) do
                            if link.from == deptId then
                                for _, nNode in ipairs(DepartmentData.nodes) do
                                    if nNode.id == link.to and nNode.type == "rank" and nNode.ranks then
                                        for _, rank in ipairs(nNode.ranks) do
                                            if tonumber(rank.level) == gradeLevel then
                                                gradeLabel = rank.name or gradeLabel
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    break
                end
            end
        end

        local ratings = (MemberData[cid] and MemberData[cid].ratings) or {}
        MemberData[cid] = {
            name = player.name,
            job = deptId,
            grade = gradeLevel,
            jobLabel = jobLabel,
            gradeLabel = gradeLabel,
            ratings = ratings
        }
        SaveMemberToDB(cid)
    else
        -- Remove member if job doesn't match a department
        if MemberData[cid] then
            MemberData[cid] = nil
            MySQL.Async.execute("DELETE FROM plt_ambulance_job_members WHERE citizenid = ?", {cid})
            TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
        end
    end
end

if Framework.Type == "qb" then
    RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function() SyncPlayerJobWithMemberData(source) end)
    RegisterNetEvent("QBCore:Server:OnJobUpdate", function(job) SyncPlayerJobWithMemberData(source) end)
elseif Framework.Type == "esx" then
    AddEventHandler("esx:playerLoaded", function(source) SyncPlayerJobWithMemberData(source) end)
    RegisterNetEvent("esx:setJob", function(job) SyncPlayerJobWithMemberData(source) end)
end

-- ==========================================
-- Stash / Inventory
-- ==========================================

local function TryRegisterStash(pluginName, id, label, slots, maxWeight)
    local funcs = {"RegisterStash", "registerStash", "CreateStash", "createStash", "AddStash", "addStash"}
    local argsVariants = {
        {id, label, slots, maxWeight},
        {id, slots, maxWeight, label},
        {id, {label = label, slots = slots, maxWeight = maxWeight, maxweight = maxWeight}}
    }

    for _, func in ipairs(funcs) do
        for _, args in ipairs(argsVariants) do
            local success, _ = pcall(function()
                return exports[pluginName][func](exports[pluginName], table.unpack(args))
            end)
            if success then return true end
        end
    end
    return false
end

Framework.CreateCallback("amb_server:prepareDepartmentStash", function(source, cb, data)
    local stashId = (data and data.stashId) or ""
    if stashId == "" then return cb({ok = false}) end

    local label = (data and data.label) or "Department Stash"
    local slots = tonumber(data and data.slots) or 80
    local maxWeight = tonumber(data and data.maxWeight) or 400000
    local invType = (Config.Inventory or ""):lower()

    if invType == "ox" or invType == "tgiann" or invType == "quasar" or invType == "origin" or invType == "core" then
        if not PreparedStashes[invType .. ":" .. stashId] then
            local success = false
            if invType == "ox" and GetResourceState("ox_inventory") == "started" then
                success = pcall(function() exports.ox_inventory:RegisterStash(stashId, label, slots, maxWeight) end)
            elseif invType == "tgiann" then
                success = TryRegisterStash("tgiann-inventory", stashId, label, slots, maxWeight) or TryRegisterStash("tgiann_inventory", stashId, label, slots, maxWeight)
            elseif invType == "quasar" then
                success = TryRegisterStash("qs-inventory", stashId, label, slots, maxWeight) or TryRegisterStash("quasar-inventory", stashId, label, slots, maxWeight)
            elseif invType == "origin" then
                success = TryRegisterStash("origin_inventory", stashId, label, slots, maxWeight) or TryRegisterStash("origen_inventory", stashId, label, slots, maxWeight)
            elseif invType == "core" then
                success = TryRegisterStash("core_inventory", stashId, label, slots, maxWeight)
            end

            if success then
                PreparedStashes[invType .. ":" .. stashId] = true
            elseif invType == "ox" then
                return cb({ok = false})
            end
        end
    else
        PreparedStashes["custom:" .. stashId] = true
    end

    cb({ok = true, stashId = stashId, inventory = invType})
end)

Framework.CreateCallback("amb_server:getEMSInventoryData", function(source, cb)
    local items = {}
    if Config.EMSItems then
        for k, v in pairs(Config.EMSItems) do items[k] = v end
    end
    cb(items)
end)

RegisterNetEvent("amb_server:takeEMSInventoryItem", function(data)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    if Framework.CanCarryItem(src, data.item, 1) then
        Framework.AddItem(src, data.item, 1)
        Framework.Notify(src, _L("received_item", {item = data.item}), "success")
    else
        Framework.Notify(src, _L("cannot_carry_more_item"), "error")
    end
end)

-- ==========================================
-- Commands & Duty
-- ==========================================

RegisterNetEvent("amb_server:ToggleDuty", function(jobForce)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    local jobName = jobForce or (player.job and player.job.name) or "ambulance"
    local newDutyState = false

    if Framework.Type == "qb" then
        newDutyState = not player.job.onduty
        player.functions.SetJobDuty(newDutyState)
    elseif Framework.Type == "esx" then
        -- Handle ESX off-duty swapping logic (simplified for space, checks off_ job variants)
        local esxPlayer = Framework.Core.GetPlayerFromId(src)
        if esxPlayer then
            local currentJob = esxPlayer.job.name
            local targetJob = currentJob
            
            if string.sub(currentJob, 1, 4) == "off_" then
                targetJob = string.sub(currentJob, 5)
                newDutyState = true
            else
                targetJob = "off_" .. currentJob
                newDutyState = false
            end
            
            esxPlayer.setJob(targetJob, esxPlayer.job.grade)
        end
    end

    -- Logging
    local officerName = player.name or (player.charinfo and player.charinfo.firstname .. " " .. player.charinfo.lastname) or "Unknown"
    local actionText = newDutyState and "Clocked On" or "Clocked Off"
    
    if not DeptDutyLogs[jobName] then DeptDutyLogs[jobName] = {} end
    table.insert(DeptDutyLogs[jobName], {
        officer = officerName, action = actionText,
        date = os.date("%B %d, %Y"), time = os.date("%H:%M")
    })
    
    if #DeptDutyLogs[jobName] > 100 then table.remove(DeptDutyLogs[jobName], 1) end

    MySQL.Async.execute("INSERT INTO plt_ambulance_job_duty_logs (dept_job, officer, action, `date`, `time`) VALUES (?, ?, ?, ?, ?)", {
        jobName, officerName, actionText, os.date("%B %d, %Y"), os.date("%H:%M")
    })

    TriggerClientEvent("amb_client:SyncData", -1, { dutyLogs = DeptDutyLogs })
    TriggerClientEvent("amb_client:RefreshCheckInZones", -1)
    
    local statusMsg = newDutyState and _L("duty_status_on") or _L("duty_status_off")
    Framework.Notify(src, _L("duty_now", {status = statusMsg}), "info")
end)

RegisterCommand("setjob", function(source, args)
    if source ~= 0 and not Framework.HasPermission(source, Config.Permission) and not exports.plt_ambulance_job:IsEMS(source) then
        return Framework.Notify(source, _L("no_command_permission"), "error")
    end

    local targetSrc = tonumber(args[1])
    local targetJob = args[2] and tostring(args[2]) or ""
    local targetGrade = tonumber(args[3]) or 0

    if not targetSrc or targetJob == "" then
        return Framework.Notify(source, _L("setjob_usage"), "error")
    end

    local player = Framework.GetPlayer(targetSrc)
    if not player then
        return Framework.Notify(source, _L("player_not_found"), "error")
    end

    local fwJob = GetFrameworkJobForDepartment(targetJob)
    Framework.SetJob(targetSrc, fwJob, targetGrade)
    Framework.Notify(source, _L("setjob_success", {name = player.name or targetSrc, job = fwJob, grade = targetGrade}), "success")
end, false)

AddEventHandler("playerDropped", function()
    -- cleanup handles
end)
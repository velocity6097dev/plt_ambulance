DepartmentData = {
    nodes = {},
    links = {},
    pan = { x = 0, y = 0, zoom = 1 },
    divisions = {}
}

MemberData = {}
DeptDutyLogs = {}
DataLoaded = false

local ESXJobGrades = {}

function GetTableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function GetNodesCount(data)
    if type(data) == "table" then
        if type(data.nodes) == "table" then
            goto lbl_13
        end
    end
    return 0

    ::lbl_13::
    if #data.nodes > 0 then
        return #data.nodes
    end
    return GetTableCount(data.nodes)
end

function EnsureDepartmentDataStructure(data)
    if type(data) ~= "table" then
        return {
            nodes = {},
            links = {},
            pan = { x = 0, y = 0, zoom = 1 },
            divisions = {}
        }
    end
    
    if type(data.nodes) ~= "table" then
        data.nodes = {}
    end
    if type(data.links) ~= "table" then
        data.links = {}
    end
    if type(data.pan) ~= "table" then
        data.pan = { x = 0, y = 0, zoom = 1 }
    end
    if type(data.divisions) ~= "table" then
        data.divisions = {}
    end
    return data
end

function IsTable(data)
    return type(data) == "table"
end

function DecodeDepartmentData(jsonString)
    if not jsonString or jsonString == "" then
        return nil
    end
    
    local success, result = pcall(json.decode, jsonString)
    if success then
        if type(result) == "table" then
            goto lbl_21
        end
    end
    return nil

    ::lbl_21::
    if not IsTable(result) then
        return nil
    end
    return EnsureDepartmentDataStructure(result)
end

function SaveToDB(key, value)
    if not key or not value then
        return false
    end
    
    local success1 = pcall(function()
        MySQL.Sync.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)", { key, value })
    end)
    
    if success1 then
        return true
    end
    
    local success2 = pcall(function()
        MySQL.Sync.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
            ["@key"] = key,
            ["@value"] = value
        })
    end)
    return success2
end

function InitDatabaseTables()
    local queries = {
        [[
        CREATE TABLE IF NOT EXISTS `plt_ambulance_job_data` (
            `key` VARCHAR(50) PRIMARY KEY,
            `value` LONGTEXT DEFAULT NULL
        );]],
        [[
        CREATE TABLE IF NOT EXISTS `plt_ambulance_job_members` (
            `citizenid` varchar(50) NOT NULL PRIMARY KEY,
            `name` varchar(100) DEFAULT NULL,
            `job` varchar(50) DEFAULT NULL,
            `grade` int(11) DEFAULT 0,
            `jobLabel` varchar(100) DEFAULT NULL,
            `gradeLabel` varchar(100) DEFAULT NULL,
            `ratings` LONGTEXT DEFAULT NULL
        );]],
        [[
        CREATE TABLE IF NOT EXISTS `plt_ambulance_job_pcrs` (
            `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `patient` varchar(100) DEFAULT NULL,
            `condition` varchar(255) DEFAULT NULL,
            `treatment` text DEFAULT NULL,
            `author` varchar(100) DEFAULT NULL,
            `date` varchar(50) DEFAULT NULL,
            `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP
        );]],
        [[
        CREATE TABLE IF NOT EXISTS `plt_ambulance_job_xrays` (
            `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `citizenid` varchar(50) DEFAULT NULL,
            `injuries` text DEFAULT NULL,
            `date` varchar(50) DEFAULT NULL,
            `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP
        );]],
        [[
        CREATE TABLE IF NOT EXISTS `plt_ambulance_job_duty_logs` (
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
        [[
        CREATE TABLE IF NOT EXISTS `plt_ambulance_job_mails` (
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
    
    for _, query in ipairs(queries) do
        local success = pcall(function()
            MySQL.Sync.execute(query, {})
        end)
        if not success then
            print("^1[plt_ambulance] SQL init query failed, continuing.^7")
        end
    end
end

function ColumnExists(tableName, columnName)
    local success, result = pcall(function()
        return MySQL.Sync.fetchAll([[
            SELECT 1
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
              AND COLUMN_NAME = ?
            LIMIT 1
        ]], { tableName, columnName })
    end)
    if success and result and result[1] ~= nil then
        return true
    end
    return false
end

function MigrateDutyLogsTable()
    local tableName = "plt_ambulance_job_duty_logs"
    if not ColumnExists(tableName, "dept_job") then
        local success = pcall(function()
            MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD COLUMN `dept_job` varchar(50) DEFAULT NULL AFTER `id`", tableName), {})
        end)
        if not success then
            print("^1[plt_ambulance] Failed to add dept_job column to duty logs table.^7")
        end
    end
    
    if ColumnExists(tableName, "dept_job") and ColumnExists(tableName, "job") then
        pcall(function()
            MySQL.Sync.execute(string.format("UPDATE `%s` SET `dept_job` = `job` WHERE (`dept_job` IS NULL OR `dept_job` = '') AND `job` IS NOT NULL AND `job` != ''", tableName), {})
        end)
    end
    
    if ColumnExists(tableName, "dept_job") then
        pcall(function()
            MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD INDEX `idx_dept_job` (`dept_job`)", tableName), {})
        end)
    end
    
    pcall(function()
        MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD INDEX `idx_timestamp` (`timestamp`)", tableName), {})
    end)
end

function MigrateMailsTable()
    local tableName = "plt_ambulance_job_mails"
    if not ColumnExists(tableName, "image_url") then
        local success = pcall(function()
            MySQL.Sync.execute(string.format("ALTER TABLE `%s` ADD COLUMN `image_url` varchar(500) DEFAULT NULL AFTER `message`", tableName), {})
        end)
        if not success then
            print("^1[plt_ambulance] Failed to add image_url column to mails table.^7")
        end
    end
end

function FetchDutyLogs()
    local success1, result1 = pcall(function()
        return MySQL.Sync.fetchAll("SELECT dept_job, officer, action, `date`, `time` FROM plt_ambulance_job_duty_logs ORDER BY id DESC", {})
    end)
    if success1 and result1 then
        return result1
    end
    
    local success2, result2 = pcall(function()
        return MySQL.Sync.fetchAll("SELECT `job` AS dept_job, officer, action, `date`, `time` FROM plt_ambulance_job_duty_logs ORDER BY id DESC", {})
    end)
    if success2 and result2 then
        return result2
    end
    return {}
end

exports("GetFramework", function()
    return Framework
end)

InitDatabaseTables()
MigrateDutyLogsTable()
MigrateMailsTable()

function InitializeMainData()
    local success, dbData = pcall(function()
        return MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_data", {})
    end)
    
    if success and type(dbData) == "table" then
        goto lbl_17
    end
    
    print("^3[plt_ambulance] Department DB load failed, trying local cache fallback.^7")
    dbData = {}

    ::lbl_17::
    local deptValue = nil
    local deptBackupValue = nil
    
    for _, row in ipairs(dbData) do
        if row.key == "departments" then
            deptValue = row.value
        elseif row.key == "departments_backup" then
            deptBackupValue = row.value
        end
    end
    
    local parsedDept = DecodeDepartmentData(deptValue)
    local parsedBackup = DecodeDepartmentData(deptBackupValue)
    local deptCount = GetNodesCount(parsedDept)
    local backupCount = GetNodesCount(parsedBackup)
    
    if parsedDept and deptCount > 0 then
        DepartmentData = parsedDept
    elseif parsedBackup and backupCount > 0 then
        DepartmentData = parsedBackup
        print("^3[plt_ambulance] departments row was empty/invalid, restored from departments_backup.^7")
        SaveToDB("departments", json.encode(DepartmentData))
    elseif parsedDept then
        DepartmentData = EnsureDepartmentDataStructure(parsedDept)
    else
        DepartmentData = EnsureDepartmentDataStructure(DepartmentData)
    end
    
    local memSuccess, memData = pcall(function()
        return MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_members", {})
    end)
    
    if memSuccess and type(memData) == "table" then
        goto lbl_96
    end
    
    print("^3[plt_ambulance] Member DB load failed; continuing with empty member cache.^7")
    memData = {}

    ::lbl_96::
    for _, row in ipairs(memData) do
        local ratingsData = json.decode(row.ratings or "{}")
        MemberData[row.citizenid] = {
            name = row.name,
            job = row.job,
            grade = row.grade,
            jobLabel = row.jobLabel,
            gradeLabel = row.gradeLabel,
            ratings = ratingsData
        }
    end
    
    local dutyLogsRes = FetchDutyLogs()
    if dutyLogsRes then
        for _, log in ipairs(dutyLogsRes) do
            local deptName = log.dept_job or "ambulance"
            if not DeptDutyLogs[deptName] then
                DeptDutyLogs[deptName] = {}
            end
            
            if #DeptDutyLogs[deptName] < 100 then
                table.insert(DeptDutyLogs[deptName], {
                    officer = log.officer,
                    action = log.action,
                    date = log.date,
                    time = log.time
                })
            end
        end
    end
    DataLoaded = true
end

InitializeMainData()

CreateThread(function()
    Wait(1500)
    TriggerClientEvent("amb_client:SyncJobs", -1, DepartmentData)
    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
end)

function SaveDepartments()
    DepartmentData = EnsureDepartmentDataStructure(DepartmentData)
    local encodedData = json.encode(DepartmentData)
    
    if not encodedData or encodedData == "" or encodedData == "null" then
        print("^1[plt_ambulance] SaveDepartments aborted: failed to encode department data.^7")
        return false
    end
    
    local savedPrimary = SaveToDB("departments", encodedData)
    local savedBackup = SaveToDB("departments_backup", encodedData)
    
    if not savedPrimary or not savedBackup then
        print("^1[plt_ambulance] SaveDepartments warning: SQL write failed.^7")
    end
    
    if not savedPrimary and not savedBackup then
        return false
    end
    
    TriggerClientEvent("amb_client:SyncJobs", -1, DepartmentData)
    return true
end

function GetFrameworkJobForDepartment(deptId)
    if DepartmentData and DepartmentData.nodes then
        goto lbl_9
    end
    return deptId

    ::lbl_9::
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" and node.id == deptId then
            if node.frameworkJob and node.frameworkJob ~= "" then
                return node.frameworkJob
            end
            return deptId
        end
    end
    return deptId
end

function GetDepartmentIdForFrameworkJob(frameworkJob)
    if DepartmentData and DepartmentData.nodes then
        goto lbl_10
    end
    return nil

    ::lbl_10::
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            if node.frameworkJob and node.frameworkJob ~= "" then
                if node.frameworkJob == frameworkJob then
                    goto lbl_28
                end
            end
            local targetId = node.id
            
            ::lbl_28::
            if tostring(targetId) == tostring(frameworkJob) then
                return node.id
            end
        end
    end
    return nil
end

function IsEMS(sourceId)
    if Framework.HasPermission(sourceId, Config.Permission) then
        if Config.AdminBypass then
            return true
        end
    end
    
    local playerObj = Framework.GetPlayer(sourceId)
    if not playerObj then
        return false
    end
    
    local fwJob = "none"
    if playerObj.job and playerObj.job.name then
        fwJob = playerObj.job.name
    end
    
    local memJob = "none"
    if MemberData[playerObj.citizenid] and MemberData[playerObj.citizenid].job then
        memJob = MemberData[playerObj.citizenid].job
    end
    
    for _, allowedJob in ipairs(Config.Medical.EMSJobs) do
        if fwJob == allowedJob or memJob == allowedJob then
            return true
        end
    end
    
    if DepartmentData and DepartmentData.nodes then
        goto lbl_66
    end
    return false

    ::lbl_66::
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            local nodeFwJob = node.id
            if node.frameworkJob and node.frameworkJob ~= "" then
                nodeFwJob = node.frameworkJob
            end
            
            if tostring(fwJob) ~= tostring(node.id) and tostring(fwJob) ~= tostring(nodeFwJob) and tostring(memJob) ~= tostring(node.id) then
                goto lbl_110
            end
            return true
        end
        ::lbl_110::
    end
    return false
end

exports("IsEMS", IsEMS)
exports("GetDepartmentIdForFrameworkJob", GetDepartmentIdForFrameworkJob)
exports("GetFrameworkJobForDepartment", GetFrameworkJobForDepartment)
exports("GetDutyLogs", function()
    return DeptDutyLogs or {}
end)

function DoesESXJobExist(jobName)
    if Framework.Type == "esx" and jobName and jobName ~= "" then
        local success, result = pcall(function()
            return MySQL.Sync.fetchAll("SELECT `name` FROM `jobs` WHERE `name` = ? LIMIT 1", { jobName })
        end)
        if success and result and result[1] ~= nil then
            return true
        end
    end
    return false
end

function ParseDutyJobName(jobName, fallback)
    local jName = tostring(jobName or "")
    local fBack = tostring(fallback or jName)
    
    if jName:sub(1, 4) == "off_" then
        return jName:sub(5), jName, false
    end
    if jName:sub(1, 3) == "off" and #jName > 3 then
        return jName:sub(4), jName, false
    end
    if jName:sub(-8) == "_offduty" then
        return jName:sub(1, -9), jName, false
    end
    if jName:sub(-4) == "_off" then
        return jName:sub(1, -5), jName, false
    end
    
    local variants = {
        "off" .. fBack,
        "off_" .. fBack,
        fBack .. "_offduty",
        fBack .. "_off"
    }
    
    for _, variant in ipairs(variants) do
        if DoesESXJobExist(variant) then
            return fBack, variant, true
        end
    end
    return fBack, variants[1], true
end

function GetESXJobGrade(jobName, gradeLevel)
    if Framework.Type == "esx" and jobName and jobName ~= "" then
        local gNum = tonumber(gradeLevel) or 0
        local success, result = pcall(function()
            return MySQL.Sync.fetchAll("SELECT `grade` FROM `job_grades` WHERE `job_name` = ? AND `grade` = ? LIMIT 1", { jobName, gNum })
        end)
        
        if success and result and result[1] then
            return gNum
        end
        
        local success2, result2 = pcall(function()
            return MySQL.Sync.fetchAll("SELECT `grade` FROM `job_grades` WHERE `job_name` = ? ORDER BY `grade` ASC LIMIT 1", { jobName })
        end)
        
        if success2 and result2 and result2[1] and result2[1].grade ~= nil then
            return tonumber(result2[1].grade) or 0
        end
    end
    return tonumber(gradeLevel) or 0
end

function CacheESXJobGrade(sourceId, jobName, gradeLevel)
    if Framework.Type ~= "esx" then
        return
    end
    
    local jName = tostring(jobName or "")
    if jName == "" then
        return
    end
    
    if type(ESXJobGrades[sourceId]) ~= "table" then
        ESXJobGrades[sourceId] = {}
    end
    
    ESXJobGrades[sourceId][jName] = tonumber(gradeLevel) or 0
end

function GetCachedESXJobGrade(sourceId, jobName)
    if type(ESXJobGrades[sourceId]) ~= "table" then
        return nil
    end
    
    local jName = tostring(jobName or "")
    if jName == "" then
        return nil
    end
    
    return tonumber(ESXJobGrades[sourceId][jName])
end

local function CheckLicenseWhitelist(source)
    if Config.UseLicenseWhitelist ~= true then
        return false
    end
    if type(Config.LicenseWhitelist) == "table" and #Config.LicenseWhitelist == 0 then
        return false
    end

    local function formatLicense(lic)
        if type(lic) ~= "string" then return nil end
        lic = lic:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if lic == "" then return nil end
        if not lic:find(":", 1, true) then
            if #lic >= 20 then
                lic = "license:" .. lic
            end
        end
        return lic
    end

    local function isWildcard(lic)
        if type(lic) ~= "string" then return true end
        lic = lic:lower():gsub("%s+", "")
        if lic == "" then return true end
        lic = lic:gsub("^license2?:", "")
        if lic == "" then return true end
        if lic:find("^x+$") then return true end
        if lic:find("^example") then return true end
        if lic:find("^changeme") then return true end
        if lic:find("^your_") then return true end
        if lic:find("^your%-") then return true end
        return false
    end

    local validLicenses = {}
    local hasValid = false
    for _, lic in ipairs(Config.LicenseWhitelist) do
        lic = formatLicense(lic)
        if lic and not isWildcard(lic) then
            validLicenses[lic] = true
            if lic:sub(1, 9) == "license2:" then
                validLicenses["license:" .. lic:sub(10)] = true
            elseif lic:sub(1, 8) == "license:" then
                validLicenses["license2:" .. lic:sub(9)] = true
            end
            hasValid = true
        end
    end

    if not hasValid then return false end

    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id then
            if id:sub(1, 8) == "license:" or id:sub(1, 9) == "license2:" then
                if validLicenses[id] then return true end
                if id:sub(1, 9) == "license2:" then
                    if validLicenses["license:" .. id:sub(10)] then return true end
                elseif id:sub(1, 8) == "license:" then
                    if validLicenses["license2:" .. id:sub(9)] then return true end
                end
            end
        end
    end
    return false
end

function HasAdminPermission(source)
    if Framework.HasPermission(source, Config.Permission) then
        return true
    end
    return CheckLicenseWhitelist(source)
end

RegisterNetEvent("amb_server:save", function(data)
    local src = source
    if not HasAdminPermission(src) then
        Framework.Notify(src, _L("no_command_permission"), "error")
        return
    end
    
    if data then
        if not IsTable(data) then
            Framework.Notify(src, "Invalid department data format.", "error")
            return
        end
        
        data = EnsureDepartmentDataStructure(data)
        local newNodesCount = GetNodesCount(data)
        local oldNodesCount = GetNodesCount(DepartmentData)
        
        if oldNodesCount > 0 and newNodesCount == 0 then
            Framework.Notify(src, "Blocked save: received empty nodes while existing configuration is not empty.", "error")
            print(string.format("[plt_ambulance] Blocked potentially destructive save from %s (%s): existingNodes=%s incomingNodes=%s", tostring(GetPlayerName(src) or "unknown"), tostring(src), tostring(oldNodesCount), tostring(newNodesCount)))
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

Framework.CreateCallback("amb_server:getData", function(source, cb)
    local waits = 0
    while not DataLoaded and waits < 100 do
        Wait(50)
        waits = waits + 1
    end
    
    cb({
        dept = DepartmentData,
        members = MemberData
    })
end)

Framework.CreateCallback("amb_server:checkPermissions", function(source, cb, permNode)
    local hasPerm = Framework.HasPermission(source, permNode)
    if not hasPerm then
        hasPerm = CheckLicenseWhitelist(source)
    end
    cb(hasPerm)
end)

RegisterNetEvent("amb_server:requestManageEMSDirect", function()
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then
        if not CheckLicenseWhitelist(src) then
            Framework.Notify(src, _L("command_no_permission"), "error")
            return
        end
    end
    
    TriggerClientEvent("amb_client:openManageEMSDirect", src, {
        dept = DepartmentData,
        members = MemberData
    })
end)

Framework.CreateCallback("amb_server:getEMSOnDutyCount", function(source, cb)
    local count = 0
    for _, pSrc in ipairs(Framework.GetPlayers()) do
        local targetSrc = tonumber(pSrc)
        if exports.plt_ambulance_job:IsEMS(targetSrc) then
            local playerObj = Framework.GetPlayer(targetSrc)
            if playerObj and playerObj.job then
                if playerObj.job.onduty == true or playerObj.job.onduty == 1 then
                    count = count + 1
                end
            end
        end
        ::lbl_38::
    end
    cb(count)
end)

Framework.CreateCallback("amb_server:isAnyEMSOnDuty", function(source, cb)
    local isOnDuty = false
    for _, pSrc in ipairs(Framework.GetPlayers()) do
        local targetSrc = tonumber(pSrc)
        if exports.plt_ambulance_job:IsEMS(targetSrc) then
            local playerObj = Framework.GetPlayer(targetSrc)
            if playerObj and playerObj.job then
                if playerObj.job.onduty == true or playerObj.job.onduty == 1 then
                    isOnDuty = true
                    break
                end
            end
        end
        ::lbl_38::
    end
    cb(isOnDuty)
end)

function GetPlayersList()
    local playerList = {}
    local addedList = {}
    
    for _, pSrc in ipairs(GetPlayers()) do
        local playerObj = Framework.GetPlayer(tonumber(pSrc))
        if playerObj then
            local cid = playerObj.citizenid
            local memData = MemberData[cid]
            
            table.insert(playerList, {
                id = tonumber(pSrc),
                cid = cid,
                name = playerObj.name,
                jobName = memData and memData.job or "none",
                jobLabel = memData and memData.jobLabel or "Not Hired",
                jobGradeLabel = memData and memData.gradeLabel or "Civilian",
                jobGradeLevel = memData and memData.grade or 0,
                isOnline = true
            })
            addedList[cid] = true
        end
    end
    
    for cid, memData in pairs(MemberData) do
        if not addedList[cid] then
            table.insert(playerList, {
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
    return playerList
end

Framework.CreateCallback("amb_server:getPlayers", function(source, cb)
    cb(GetPlayersList())
end)

function GetFirstStartedResource(resourceList)
    for _, resourceName in ipairs(resourceList or {}) do
        if GetResourceState(resourceName) == "started" then
            return resourceName
        end
    end
    return nil
end

function AttemptRegisterStash(exportName, stashId, label, slots, maxWeight)
    if not exportName then
        return false
    end
    
    local methods = {
        "RegisterStash", "registerStash", "CreateStash", "createStash", "AddStash", "addStash"
    }
    
    local paramCombos = {
        { stashId, label, slots, maxWeight },
        { stashId, slots, maxWeight, label },
        { stashId, { label = label, slots = slots, maxWeight = maxWeight, maxweight = maxWeight } }
    }
    
    for _, method in ipairs(methods) do
        for _, combo in ipairs(paramCombos) do
            local success, result = pcall(function()
                return exports[exportName][method](table.unpack(combo))
            end)
            if success and result ~= false then
                return true
            end
        end
    end
    return false
end

Framework.CreateCallback("amb_server:prepareDepartmentStash", function(source, cb, stashConfig)
    local stashId = stashConfig and tostring(stashConfig.stashId or "") or ""
    if stashId == "" then
        cb({ ok = false })
        return
    end
    
    local label = stashConfig and tostring(stashConfig.label or "Department Stash") or "Department Stash"
    local slots = tonumber(stashConfig and stashConfig.slots) or 80
    local maxWeight = tonumber(stashConfig and stashConfig.maxWeight) or 400000
    
    local invConfigStr = tostring(Config.Inventory or "")
    local invType = invConfigStr:lower()
    local registryKey = invType .. ":" .. stashId
    
    if invType == "ox" or invType == "tgiann" or invType == "quasar" or invType == "origin" or invType == "core" then
        local isRegistered = StashRegistry and StashRegistry[registryKey]
        
        if isRegistered ~= true then
            local successFlag = false
            if invType == "ox" then
                if GetResourceState("ox_inventory") == "started" then
                    successFlag = pcall(function()
                        exports.ox_inventory:RegisterStash(stashId, label, slots, maxWeight)
                    end)
                end
            elseif invType == "tgiann" then
                local resName = GetFirstStartedResource({ "tgiann-inventory", "tgiann_inventory" })
                successFlag = AttemptRegisterStash(resName, stashId, label, slots, maxWeight)
            elseif invType == "quasar" then
                local resName = GetFirstStartedResource({ "qs-inventory", "qs_inventory", "quasar-inventory", "quasar_inventory" })
                successFlag = AttemptRegisterStash(resName, stashId, label, slots, maxWeight)
            elseif invType == "origin" then
                local resName = GetFirstStartedResource({ "origin_inventory", "origin-inventory", "origen_inventory", "origen-inventory" })
                successFlag = AttemptRegisterStash(resName, stashId, label, slots, maxWeight)
            elseif invType == "core" then
                local resName = GetFirstStartedResource({ "core_inventory", "core-inventory" })
                successFlag = AttemptRegisterStash(resName, stashId, label, slots, maxWeight)
            end
            
            if invType ~= "ox" then
                if StashRegistry then StashRegistry[registryKey] = true end
            elseif successFlag then
                if StashRegistry then StashRegistry[registryKey] = true end
            else
                cb({ ok = false })
                return
            end
            
            if invType == "ox" and not successFlag then
                cb({ ok = false })
                return
            end
            
            if successFlag and StashRegistry then
                StashRegistry[registryKey] = true
            end
        end
    elseif not StashRegistry then
        -- Handle non-existent StashRegistry properly
    else
        StashRegistry[registryKey] = true
    end
    
    cb({ ok = true, stashId = stashId, inventory = invType })
end)

Framework.CreateCallback("amb_server:getEMSInventoryData", function(source, cb)
    local invData = {}
    for key, val in pairs(Config.EMSItems or {}) do
        invData[key] = val
    end
    cb(invData)
end)

RegisterNetEvent("amb_server:takeEMSInventoryItem", function(data)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then return end
    
    local itemName = data.item
    if Framework.CanCarryItem(src, itemName, 1) then
        Framework.AddItem(src, itemName, 1)
        Framework.Notify(src, _L("received_item", { item = itemName }), "success")
    else
        Framework.Notify(src, _L("cannot_carry_more_item"), "error")
    end
end)

RegisterNetEvent("amb_server:ToggleDuty", function(jobFilter)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then return end
    
    local currentJob = jobFilter or (playerObj.job and playerObj.job.name) or "ambulance"
    
    if not DeptDutyLogs[currentJob] then
        DeptDutyLogs[currentJob] = {}
    end
    
    local isGoingOnDuty = false
    if Framework.Type == "qb" then
        isGoingOnDuty = not playerObj.job.onduty
        playerObj.functions.SetJobDuty(isGoingOnDuty)
    elseif Framework.Type == "esx" then
        local esxPlayer = Framework.Core.GetPlayerFromId(src)
        if not esxPlayer or not esxPlayer.job then return end
        
        local fwJob = GetFrameworkJobForDepartment(currentJob)
        local parsedJob, offDutyVariant, hasOffDuty = ParseDutyJobName(esxPlayer.job.name, fwJob)
        
        local currentGrade = tonumber(esxPlayer.job.grade)
        if not currentGrade then
            currentGrade = tonumber(playerObj.job.grade) or 0
        end
        
        local targetJob = parsedJob
        if not hasOffDuty or not parsedJob then
            targetJob = fwJob
        end
        
        local targetGrade = currentGrade
        if hasOffDuty then
            CacheESXJobGrade(src, fwJob, currentGrade)
        else
            targetGrade = GetCachedESXJobGrade(src, fwJob) or currentGrade
        end
        
        if not DoesESXJobExist(targetJob) then
            Framework.Notify(src, string.format("Duty toggle failed: ESX job '%s' does not exist.", tostring(targetJob)), "error")
            return
        end
        
        local finalGrade = GetESXJobGrade(targetJob, targetGrade)
        esxPlayer.setJob(targetJob, finalGrade)
        Wait(100)
        
        local checkPlayer = Framework.Core.GetPlayerFromId(src)
        local updatedSuccess = false
        if checkPlayer and checkPlayer.job then
            updatedSuccess = (tostring(checkPlayer.job.name) == tostring(targetJob))
        end
        
        if not updatedSuccess then
            Framework.Notify(src, "Duty toggle failed: framework job did not update.", "error")
            return
        end
        
        isGoingOnDuty = not hasOffDuty
    end
    
    local playerName = playerObj.name
    if not playerName and playerObj.charinfo then
        playerName = (playerObj.charinfo.firstname or "") .. " " .. (playerObj.charinfo.lastname or "")
        if playerName == " " then playerName = "Unknown" end
    elseif not playerName then
        playerName = "Unknown"
    end
    
    local actionLabel = isGoingOnDuty and "Clocked On" or "Clocked Off"
    
    table.insert(DeptDutyLogs[currentJob], {
        officer = playerName,
        action = actionLabel,
        date = os.date("%B %d, %Y"),
        time = os.date("%H:%M")
    })
    
    if #DeptDutyLogs[currentJob] > 100 then
        table.remove(DeptDutyLogs[currentJob], 1)
    end
    
    local success = pcall(function()
        MySQL.Sync.execute("INSERT INTO plt_ambulance_job_duty_logs (dept_job, officer, action, `date`, `time`) VALUES (?, ?, ?, ?, ?)", {
            currentJob, playerName, actionLabel, os.date("%B %d, %Y"), os.date("%H:%M")
        })
    end)
    
    if not success then
        pcall(function()
            MySQL.Sync.execute("INSERT INTO plt_ambulance_job_duty_logs (`job`, officer, action, `date`, `time`) VALUES (?, ?, ?, ?, ?)", {
                currentJob, playerName, actionLabel, os.date("%B %d, %Y"), os.date("%H:%M")
            })
        end)
    end
    
    TriggerClientEvent("amb_client:SyncData", -1, { dutyLogs = DeptDutyLogs })
    TriggerClientEvent("amb_client:RefreshCheckInZones", -1)
    
    local statusMsg = isGoingOnDuty and _L("duty_status_on") or _L("duty_status_off")
    Framework.Notify(src, _L("duty_now", { status = statusMsg }), "info")
end)

AddEventHandler("playerDropped", function()
    local src = source
    if ESXJobGrades and ESXJobGrades[src] then
        ESXJobGrades[src] = nil
    end
end)

function SaveMemberToDB(cid)
    local memData = MemberData[cid]
    if not memData then return end
    
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_members (`citizenid`, `name`, `job`, `grade`, `jobLabel`, `gradeLabel`, `ratings`) VALUES (@cid, @name, @job, @grade, @jobLabel, @gradeLabel, @ratings) ON DUPLICATE KEY UPDATE `name` = @name, `job` = @job, `grade` = @grade, `jobLabel` = @jobLabel, `gradeLabel` = @gradeLabel, `ratings` = @ratings", {
        ["@cid"] = cid,
        ["@name"] = memData.name,
        ["@job"] = memData.job,
        ["@grade"] = memData.grade,
        ["@jobLabel"] = memData.jobLabel,
        ["@gradeLabel"] = memData.gradeLabel,
        ["@ratings"] = json.encode(memData.ratings or {})
    })
    
    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
end

function SyncPlayerJobWithMemberData(sourceId)
    local playerObj = Framework.GetPlayer(sourceId)
    if not playerObj then return end
    
    local pJobName = playerObj.job.name
    local pJobGrade = tonumber(playerObj.job.grade) or 0
    local cid = playerObj.citizenid
    local deptId = GetDepartmentIdForFrameworkJob(pJobName)
    
    if deptId then
        local pJobLabel = deptId
        local pGradeLabel = "Rank " .. pJobGrade
        
        for _, node in ipairs(DepartmentData.nodes or {}) do
            if node.type == "department" and node.id == deptId then
                pJobLabel = node.label or deptId
                for _, link in ipairs(DepartmentData.links or {}) do
                    if link.from == deptId then
                        for _, rNode in ipairs(DepartmentData.nodes) do
                            if rNode.id == link.to and rNode.type == "rank" and rNode.ranks then
                                for _, rank in ipairs(rNode.ranks) do
                                    if tonumber(rank.level) == pJobGrade then
                                        pGradeLabel = rank.name or pGradeLabel
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                break
            end
        end
        
        local existingRatings = {}
        if MemberData[cid] and MemberData[cid].ratings then
            existingRatings = MemberData[cid].ratings
        end
        
        MemberData[cid] = {
            name = playerObj.name,
            job = deptId,
            grade = pJobGrade,
            jobLabel = pJobLabel,
            gradeLabel = pGradeLabel,
            ratings = existingRatings
        }
        SaveMemberToDB(cid)
    else
        if MemberData[cid] then
            MemberData[cid] = nil
            MySQL.Async.execute("DELETE FROM plt_ambulance_job_members WHERE citizenid = ?", { cid })
            TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
        end
    end
end

if Framework.Type == "qb" then
    RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function(sourceId)
        SyncPlayerJobWithMemberData(sourceId)
    end)
    RegisterNetEvent("QBCore:Server:OnJobUpdate", function(sourceId)
        SyncPlayerJobWithMemberData(sourceId)
    end)
elseif Framework.Type == "esx" then
    AddEventHandler("esx:playerLoaded", function(sourceId)
        SyncPlayerJobWithMemberData(sourceId)
    end)
    RegisterNetEvent("esx:setJob", function(sourceId)
        SyncPlayerJobWithMemberData(sourceId)
    end)
end

RegisterCommand("setjob", function(source, args)
    local hasPerm = (source == 0) or Framework.HasPermission(source, Config.Permission)
    if not hasPerm and Framework.Type == "qb" then
        hasPerm = exports.plt_ambulance_job:IsEMS(source)
    end
    
    if not hasPerm then
        Framework.Notify(source, _L("no_command_permission"), "error")
        return
    end
    
    local targetSrc = tonumber(args[1])
    local jobName = args[2] and tostring(args[2]) or ""
    local jobGrade = tonumber(args[3]) or 0
    
    if not targetSrc or jobName == "" then
        Framework.Notify(source, _L("setjob_usage"), "error")
        return
    end
    
    local playerObj = Framework.GetPlayer(targetSrc)
    if not playerObj then
        Framework.Notify(source, _L("player_not_found"), "error")
        return
    end
    
    local fwJob = GetFrameworkJobForDepartment(jobName)
    Framework.SetJob(targetSrc, fwJob, jobGrade)
    
    Framework.Notify(source, _L("setjob_success", { name = playerObj.name or targetSrc, job = fwJob, grade = jobGrade }), "success")
end, false)
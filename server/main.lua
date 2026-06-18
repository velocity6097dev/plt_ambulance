-- ============================================================
--  plt_ambulance  |  main.lua  (server-side)
--  Core data management: departments, members, duty logs,
--  stash registration, duty toggling, and framework sync.
-- ============================================================

-- ============================================================
--  Global state
-- ============================================================
DepartmentData = {
    nodes     = {},
    links     = {},
    pan       = { x = 0, y = 0, zoom = 1 },
    divisions = {},
}

MemberData    = {}   -- [citizenid] = { name, job, grade, jobLabel, gradeLabel, ratings }
DeptDutyLogs  = {}   -- [dept_job]  = array of log entries (capped at 100)
DataLoaded    = false

-- Internal caches
local registeredStashes = {}  -- [inventoryType:stashId] = true  (prevents double-registration)
local esxGradeCache     = {}  -- [playerId][jobName] = grade      (ESX grade lookup cache)

-- ============================================================
--  Utility: tableLength(t)
--  Counts keys in a table using pairs (works for hash tables).
-- ============================================================
local function tableLength(t)
    if type(t) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- ============================================================
--  Utility: countNodes(data)
--  Returns the number of nodes in a department data structure.
--  Prefers # (array length) then falls back to tableLength.
-- ============================================================
local function countNodes(data)
    if type(data) ~= "table" or type(data.nodes) ~= "table" then
        return 0
    end
    local len = #data.nodes
    if len > 0 then return len end
    return tableLength(data.nodes)
end

-- ============================================================
--  Utility: isTable(v)
--  Simple type check helper.
-- ============================================================
local function isTable(v)
    return type(v) == "table"
end

-- ============================================================
--  Utility: ensureDepartmentSchema(data)
--  If data is not a table, returns a fresh blank structure.
--  If it is a table, fills in any missing required fields.
-- ============================================================
local function ensureDepartmentSchema(data)
    if type(data) ~= "table" then
        return { nodes = {}, links = {}, pan = { x = 0, y = 0, zoom = 1 }, divisions = {} }
    end
    if type(data.nodes)     ~= "table" then data.nodes     = {} end
    if type(data.links)     ~= "table" then data.links     = {} end
    if type(data.divisions) ~= "table" then data.divisions = {} end
    if type(data.pan)       ~= "table" then data.pan = { x = 0, y = 0, zoom = 1 } end
    return data
end

-- ============================================================
--  Utility: safeJsonDecode(str)
--  Decodes a JSON string and returns the table, or nil on error.
-- ============================================================
local function safeJsonDecode(str)
    if not str or str == "" then return nil end
    local ok, result = pcall(json.decode, str)
    if ok and type(result) == "table" and isTable(result) then
        return ensureDepartmentSchema(result)
    end
    return nil
end

-- ============================================================
--  DB: dbWrite(key, value)
--  Upserts a key/value pair into plt_ambulance_job_data.
--  Tries positional params first, then named params as fallback.
-- ============================================================
local function dbWrite(key, value)
    if not key or not value then return false end

    local ok = pcall(function()
        MySQL.Sync.execute(
            "INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)",
            { key, value }
        )
    end)
    if ok then return true end

    -- Fallback for inventory systems that require named params
    ok = pcall(function()
        MySQL.Sync.execute(
            "INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value",
            { ["@key"] = key, ["@value"] = value }
        )
    end)
    return ok
end

-- ============================================================
--  DB: initTables()
--  Creates all required tables if they don't already exist.
-- ============================================================
local function initTables()
    local schemas = {
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
        );]],
    }

    for _, sql in ipairs(schemas) do
        local ok = pcall(function()
            MySQL.Sync.execute(sql, {})
        end)
        if not ok then
            print("^1[plt_ambulance] SQL init query failed, continuing.^7")
        end
    end
end

-- ============================================================
--  DB: columnExists(tableName, columnName)
--  Queries information_schema to check if a column is present.
-- ============================================================
local function columnExists(tableName, columnName)
    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll(
            "SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1",
            { tableName, columnName }
        )
    end)
    if ok and rows then
        return rows[1] ~= nil
    end
    return false
end

-- ============================================================
--  DB: migrateDutyLogsTable()
--  Adds the dept_job column and indexes if they're missing.
--  Also backfills dept_job from the legacy `job` column.
-- ============================================================
local function migrateDutyLogsTable()
    local tableName = "plt_ambulance_job_duty_logs"

    -- Add dept_job column if missing
    if not columnExists(tableName, "dept_job") then
        local ok = pcall(function()
            MySQL.Sync.execute(
                ("ALTER TABLE `%s` ADD COLUMN `dept_job` varchar(50) DEFAULT NULL AFTER `id`"):format(tableName),
                {}
            )
        end)
        if not ok then
            print("^1[plt_ambulance] Failed to add dept_job column to duty logs table.^7")
        end
    end

    -- Backfill dept_job from old `job` column if both exist
    if columnExists(tableName, "dept_job") and columnExists(tableName, "job") then
        pcall(function()
            MySQL.Sync.execute(
                ("UPDATE `%s` SET `dept_job` = `job` WHERE (`dept_job` IS NULL OR `dept_job` = '') AND `job` IS NOT NULL AND `job` != ''"):format(tableName),
                {}
            )
        end)
    end

    -- Add dept_job index if the column now exists
    if columnExists(tableName, "dept_job") then
        pcall(function()
            MySQL.Sync.execute(
                ("ALTER TABLE `%s` ADD INDEX `idx_dept_job` (`dept_job`)"):format(tableName),
                {}
            )
        end)
    end

    -- Always try to add the timestamp index (will silently fail if already present)
    pcall(function()
        MySQL.Sync.execute(
            ("ALTER TABLE `%s` ADD INDEX `idx_timestamp` (`timestamp`)"):format(tableName),
            {}
        )
    end)
end

-- ============================================================
--  DB: migrateMailsTable()
--  Adds the image_url column to the mails table if missing.
-- ============================================================
local function migrateMailsTable()
    local tableName = "plt_ambulance_job_mails"
    if not columnExists(tableName, "image_url") then
        local ok = pcall(function()
            MySQL.Sync.execute(
                ("ALTER TABLE `%s` ADD COLUMN `image_url` varchar(500) DEFAULT NULL AFTER `message`"):format(tableName),
                {}
            )
        end)
        if not ok then
            print("^1[plt_ambulance] Failed to add image_url column to mails table.^7")
        end
    end
end

-- ============================================================
--  DB: loadDutyLogs()
--  Fetches duty logs, preferring dept_job column.
--  Falls back to aliasing the legacy `job` column as dept_job.
-- ============================================================
local function loadDutyLogs()
    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll(
            "SELECT dept_job, officer, action, `date`, `time` FROM plt_ambulance_job_duty_logs ORDER BY id DESC",
            {}
        )
    end)
    if ok and rows then return rows end

    ok, rows = pcall(function()
        return MySQL.Sync.fetchAll(
            "SELECT `job` AS dept_job, officer, action, `date`, `time` FROM plt_ambulance_job_duty_logs ORDER BY id DESC",
            {}
        )
    end)
    if ok and rows then return rows end

    return {}
end

-- ============================================================
--  Export: GetFramework
-- ============================================================
exports("GetFramework", function()
    return Framework
end)

-- ============================================================
--  Startup: run migrations and load all data from DB
-- ============================================================
initTables()
migrateDutyLogsTable()
migrateMailsTable()

local function loadAllData()
    -- Load department data
    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_data", {})
    end)

    if not (ok and type(rows) == "table") then
        print("^3[plt_ambulance] Department DB load failed, trying local cache fallback.^7")
        rows = {}
    end

    local rawDepartments, rawBackup
    for _, row in ipairs(rows) do
        if row.key == "departments" then
            rawDepartments = row.value
        elseif row.key == "departments_backup" then
            rawBackup = row.value
        end
    end

    local deptData   = safeJsonDecode(rawDepartments)
    local backupData = safeJsonDecode(rawBackup)
    local deptCount  = countNodes(deptData)
    local backCount  = countNodes(backupData)

    if deptData and deptCount > 0 then
        -- Primary row is valid
        DepartmentData = deptData
    elseif backupData and backCount > 0 then
        -- Primary was empty/invalid – restore from backup
        DepartmentData = backupData
        print("^3[plt_ambulance] departments row was empty/invalid, restored from departments_backup.^7")
        dbWrite("departments", json.encode(DepartmentData))
    elseif deptData then
        -- Primary exists but has 0 nodes – sanitise and keep
        DepartmentData = ensureDepartmentSchema(deptData)
    else
        -- No usable data at all – keep the global default
        DepartmentData = ensureDepartmentSchema(DepartmentData)
    end

    -- Load member data
    ok, rows = pcall(function()
        return MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_members", {})
    end)
    if not (ok and type(rows) == "table") then
        print("^3[plt_ambulance] Member DB load failed; continuing with empty member cache.^7")
        rows = {}
    end

    for _, row in ipairs(rows) do
        MemberData[row.citizenid] = {
            name       = row.name,
            job        = row.job,
            grade      = row.grade,
            jobLabel   = row.jobLabel,
            gradeLabel = row.gradeLabel,
            ratings    = json.decode(row.ratings or "{}"),
        }
    end

    -- Load duty logs (capped at 100 per department)
    local logs = loadDutyLogs()
    for _, entry in ipairs(logs) do
        local dept = entry.dept_job or "ambulance"
        DeptDutyLogs[dept] = DeptDutyLogs[dept] or {}
        if #DeptDutyLogs[dept] < 100 then
            table.insert(DeptDutyLogs[dept], {
                officer = entry.officer,
                action  = entry.action,
                date    = entry.date,
                time    = entry.time,
            })
        end
    end

    DataLoaded = true
end

loadAllData()

-- Broadcast initial sync to all clients after a short delay
CreateThread(function()
    Wait(1500)
    TriggerClientEvent("amb_client:SyncJobs",    -1, DepartmentData)
    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
end)

-- ============================================================
--  SaveDepartments()  [global]
--  Sanitises DepartmentData, writes both primary and backup
--  rows to the DB, then broadcasts the update to all clients.
-- ============================================================
function SaveDepartments()
    DepartmentData = ensureDepartmentSchema(DepartmentData)

    local encoded = json.encode(DepartmentData)
    if not encoded or encoded == "" or encoded == "null" then
        print("^1[plt_ambulance] SaveDepartments aborted: failed to encode department data.^7")
        return false
    end

    local ok1 = dbWrite("departments",        encoded)
    local ok2 = dbWrite("departments_backup", encoded)

    if not ok1 or not ok2 then
        print("^1[plt_ambulance] SaveDepartments warning: SQL write failed.^7")
    end
    if not ok1 and not ok2 then return false end

    TriggerClientEvent("amb_client:SyncJobs", -1, DepartmentData)
    return true
end

-- ============================================================
--  GetFrameworkJobForDepartment(deptId)  [global]
--  Returns the framework job name for a given department node id.
--  Falls back to returning deptId unchanged if none is set.
-- ============================================================
function GetFrameworkJobForDepartment(deptId)
    if not (DepartmentData and DepartmentData.nodes) then return deptId end

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

-- ============================================================
--  GetDepartmentIdForFrameworkJob(jobName)  [global]
--  Reverse lookup: returns the department node id that maps to
--  the given framework job name, or nil if not found.
-- ============================================================
function GetDepartmentIdForFrameworkJob(jobName)
    if not (DepartmentData and DepartmentData.nodes) then return nil end

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            -- Use frameworkJob if set, otherwise fall back to the node id
            local key = (node.frameworkJob and node.frameworkJob ~= "") and node.frameworkJob or node.id
            if tostring(jobName) == tostring(key) then
                return node.id
            end
        end
    end
    return nil
end

-- ============================================================
--  IsEMS(playerId)  [global + export]
--  Returns true if the player is considered EMS.
--  Checks: admin bypass → framework job → MemberData job →
--          Config.Medical.EMSJobs list → DepartmentData nodes.
-- ============================================================
function IsEMS(playerId)
    -- Admin bypass: if the player has permission and AdminBypass is enabled, always return true
    if Framework.HasPermission(playerId, Config.Permission) and Config.AdminBypass then
        return true
    end

    local player = Framework.GetPlayer(playerId)
    if not player then return false end

    local frameworkJob = (player.job and player.job.name) or "none"
    local memberJob    = (MemberData[player.citizenid] and MemberData[player.citizenid].job) or "none"

    -- Check against the configured EMS job list
    for _, emsJob in ipairs(Config.Medical.EMSJobs) do
        if frameworkJob == emsJob or memberJob == emsJob then return true end
    end

    -- Check against department nodes
    if not (DepartmentData and DepartmentData.nodes) then return false end

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            local key = (node.frameworkJob and node.frameworkJob ~= "") and node.frameworkJob or node.id
            -- Match either the framework job or the member's stored job against this department
            if tostring(frameworkJob) == tostring(node.id)
            or tostring(frameworkJob) == tostring(key)
            or tostring(memberJob)    == tostring(node.id) then
                return true
            end
        end
    end
    return false
end

exports("IsEMS",                        IsEMS)
exports("GetDepartmentIdForFrameworkJob", GetDepartmentIdForFrameworkJob)
exports("GetFrameworkJobForDepartment",   GetFrameworkJobForDepartment)
exports("GetDutyLogs", function()
    return DeptDutyLogs or {}
end)

-- ============================================================
--  ESX helpers
--  These functions are only meaningful on an ESX server and
--  assist with off-duty job name parsing and grade validation.
-- ============================================================

-- esxJobExists(jobName)
-- Returns true if the job exists in the ESX `jobs` table.
local function esxJobExists(jobName)
    if Framework.Type ~= "esx" or not jobName or jobName == "" then return false end
    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll("SELECT `name` FROM `jobs` WHERE `name` = ? LIMIT 1", { jobName })
    end)
    if ok and rows then return rows[1] ~= nil end
    return false
end

-- parseOffDutyJob(currentJob, fallbackJob)
-- Detects common off-duty job name patterns and strips the prefix/suffix.
-- Returns: baseJobName, actualJobName, isOnDuty
local function parseOffDutyJob(currentJob, fallbackJob)
    currentJob  = tostring(currentJob  or "")
    fallbackJob = tostring(fallbackJob or currentJob)

    -- Pattern: "off_<job>"
    if currentJob:sub(1, 4) == "off_" then
        return currentJob:sub(5), currentJob, false
    end
    -- Pattern: "off<job>" (prefix without underscore)
    if currentJob:sub(1, 3) == "off" and #currentJob > 3 then
        return currentJob:sub(4), currentJob, false
    end
    -- Pattern: "<job>_offduty"
    if currentJob:sub(-8) == "_offduty" then
        return currentJob:sub(1, -9), currentJob, false
    end
    -- Pattern: "<job>_off"
    if currentJob:sub(-4) == "_off" then
        return currentJob:sub(1, -5), currentJob, false
    end

    -- Not an off-duty job – build candidate off-duty names and check DB
    local candidates = {
        "off"  .. fallbackJob,
        "off_" .. fallbackJob,
        fallbackJob .. "_offduty",
        fallbackJob .. "_off",
    }
    for _, candidate in ipairs(candidates) do
        if esxJobExists(candidate) then
            return fallbackJob, candidate, true
        end
    end

    -- Default: assume on-duty, use first candidate as off-duty name
    return fallbackJob, candidates[1], true
end

-- esxValidateGrade(jobName, grade)
-- Validates a grade against the ESX job_grades table.
-- If the grade doesn't exist for the job, returns the lowest available grade.
local function esxValidateGrade(jobName, grade)
    if Framework.Type ~= "esx" or not jobName or jobName == "" then
        return tonumber(grade) or 0
    end

    grade = tonumber(grade) or 0

    -- Check if the specific grade exists
    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll(
            "SELECT `grade` FROM `job_grades` WHERE `job_name` = ? AND `grade` = ? LIMIT 1",
            { jobName, grade }
        )
    end)
    if ok and rows and rows[1] then return grade end

    -- Fall back to the lowest available grade for this job
    ok, rows = pcall(function()
        return MySQL.Sync.fetchAll(
            "SELECT `grade` FROM `job_grades` WHERE `job_name` = ? ORDER BY `grade` ASC LIMIT 1",
            { jobName }
        )
    end)
    if ok and rows and rows[1] and rows[1].grade ~= nil then
        return tonumber(rows[1].grade) or 0
    end
    return grade
end

-- setEsxGradeCache(playerId, jobName, grade)
-- Stores a player's off-duty grade in the ESX grade cache.
local function setEsxGradeCache(playerId, jobName, grade)
    if Framework.Type ~= "esx" or not jobName or jobName == "" then return end
    jobName = tostring(jobName)
    esxGradeCache[playerId] = esxGradeCache[playerId] or {}
    esxGradeCache[playerId][jobName] = tonumber(grade) or 0
end

-- getEsxGradeCache(playerId, jobName)
-- Retrieves a previously cached grade for a player's job.
local function getEsxGradeCache(playerId, jobName)
    local cache = esxGradeCache[playerId]
    if type(cache) ~= "table" then return nil end
    jobName = tostring(jobName or "")
    if jobName == "" then return nil end
    return tonumber(cache[jobName])
end

-- ============================================================
--  hasPermission(playerId)
--  Returns true if the player has admin permission OR is an EMS.
-- ============================================================
local function hasPermission(playerId)
    if Framework.HasPermission(playerId, Config.Permission) then return true end
    return IsEMS(playerId)
end

-- ============================================================
--  Net event: amb_server:save
--  Admin saves updated department configuration from the UI.
-- ============================================================
RegisterNetEvent("amb_server:save", function(newData)
    local caller = source

    if not hasPermission(caller) then
        Framework.Notify(caller, _L("no_command_permission"), "error")
        return
    end

    if not newData then return end

    if not isTable(newData) then
        Framework.Notify(caller, "Invalid department data format.", "error")
        return
    end

    newData = ensureDepartmentSchema(newData)

    -- Safety check: never overwrite a non-empty config with empty nodes
    local incomingNodes = countNodes(newData)
    local existingNodes = countNodes(DepartmentData)
    if existingNodes > 0 and incomingNodes == 0 then
        Framework.Notify(caller, "Blocked save: received empty nodes while existing configuration is not empty.", "error")
        print(("[plt_ambulance] Blocked potentially destructive save from %s (%s): existingNodes=%s incomingNodes=%s"):format(
            tostring(GetPlayerName(caller) or "unknown"),
            tostring(caller),
            tostring(existingNodes),
            tostring(incomingNodes)
        ))
        return
    end

    DepartmentData = newData
    if SaveDepartments() then
        Framework.Notify(caller, _L("config_saved_synced"), "success")
    else
        Framework.Notify(caller, "Failed to persist department data.", "error")
    end
end)

-- ============================================================
--  Callback: amb_server:getData
--  Returns all department and member data to the calling client.
--  Waits up to 5 seconds for DataLoaded to become true.
-- ============================================================
Framework.CreateCallback("amb_server:getData", function(playerId, cb)
    local attempts = 0
    while not DataLoaded and attempts < 100 do
        Wait(50)
        attempts = attempts + 1
    end
    cb({ dept = DepartmentData, members = MemberData })
end)

-- ============================================================
--  Callback: amb_server:checkPermissions
--  Returns whether the caller has admin or EMS permissions.
-- ============================================================
Framework.CreateCallback("amb_server:checkPermissions", function(playerId, cb, permission)
    local hasAdmin = Framework.HasPermission(playerId, permission)
    local isEms    = IsEMS(playerId)
    cb(hasAdmin or isEms)
end)

-- ============================================================
--  Net event: amb_server:requestManageEMSDirect
--  Opens the management UI for the caller if they have permission.
-- ============================================================
RegisterNetEvent("amb_server:requestManageEMSDirect", function()
    local caller = source

    if not Framework.HasPermission(caller, Config.Permission) and not IsEMS(caller) then
        Framework.Notify(caller, _L("command_no_permission"), "error")
        return
    end

    TriggerClientEvent("amb_client:openManageEMSDirect", caller, {
        dept    = DepartmentData,
        members = MemberData,
    })
end)

-- ============================================================
--  Callback: amb_server:getEMSOnDutyCount
--  Returns the number of EMS players currently on duty.
-- ============================================================
Framework.CreateCallback("amb_server:getEMSOnDutyCount", function(_playerId, cb)
    local count = 0
    for _, playerId in ipairs(Framework.GetPlayers()) do
        playerId = tonumber(playerId)
        if exports.plt_ambulance_job:IsEMS(playerId) then
            local player = Framework.GetPlayer(playerId)
            if player and player.job then
                local onDuty = player.job.onduty
                if onDuty == true or onDuty == 1 then
                    count = count + 1
                end
            end
        end
    end
    cb(count)
end)

-- ============================================================
--  Callback: amb_server:isAnyEMSOnDuty
--  Returns true as soon as one EMS player on duty is found.
-- ============================================================
Framework.CreateCallback("amb_server:isAnyEMSOnDuty", function(_playerId, cb)
    local found = false
    for _, playerId in ipairs(Framework.GetPlayers()) do
        playerId = tonumber(playerId)
        if exports.plt_ambulance_job:IsEMS(playerId) then
            local player = Framework.GetPlayer(playerId)
            if player and player.job then
                local onDuty = player.job.onduty
                if onDuty == true or onDuty == 1 then
                    found = true
                    break
                end
            end
        end
    end
    cb(found)
end)

-- ============================================================
--  GetPlayersList()  [global]
--  Returns a combined list of online players (with live data)
--  and offline members (from MemberData), each with EMS info.
-- ============================================================
function GetPlayersList()
    local list        = {}
    local onlineCids  = {}

    -- Online players
    for _, rawId in ipairs(GetPlayers()) do
        local player = Framework.GetPlayer(tonumber(rawId))
        if player then
            local cid    = player.citizenid
            local member = MemberData[cid]
            onlineCids[cid] = true
            table.insert(list, {
                id            = tonumber(rawId),
                cid           = cid,
                name          = player.name,
                jobName       = (member and member.job)        or "none",
                jobLabel      = (member and member.jobLabel)   or "Not Hired",
                jobGradeLabel = (member and member.gradeLabel) or "Civilian",
                jobGradeLevel = (member and member.grade)      or 0,
                isOnline      = true,
            })
        end
    end

    -- Offline members
    for cid, member in pairs(MemberData) do
        if not onlineCids[cid] then
            table.insert(list, {
                id            = 0,
                cid           = cid,
                name          = member.name       or "Unknown",
                jobName       = member.job        or "none",
                jobLabel      = member.jobLabel   or "Not Hired",
                jobGradeLabel = member.gradeLabel or "None",
                jobGradeLevel = member.grade      or 0,
                isOnline      = false,
            })
        end
    end

    return list
end

-- ============================================================
--  Callback: amb_server:getPlayers
-- ============================================================
Framework.CreateCallback("amb_server:getPlayers", function(_playerId, cb)
    cb(GetPlayersList())
end)

-- ============================================================
--  Utility: getFirstStartedResource(candidates)
--  Returns the first resource name in the list that is running,
--  or nil if none are started.
-- ============================================================
local function getFirstStartedResource(candidates)
    for _, name in ipairs(candidates or {}) do
        if GetResourceState(name) == "started" then return name end
    end
    return nil
end

-- ============================================================
--  Utility: tryRegisterStash(inventoryResource, id, label, slots, maxWeight)
--  Attempts to register a stash using several common export
--  function names (RegisterStash / createStash / AddStash etc.).
--  Returns true on first success, false if all attempts fail.
-- ============================================================
local function tryRegisterStash(inventoryResource, id, label, slots, maxWeight)
    if not inventoryResource then return false end

    local methodNames = { "RegisterStash", "registerStash", "CreateStash", "createStash", "AddStash", "addStash" }

    -- Three different argument layouts used by various inventories
    local argLayouts = {
        { id, label, slots, maxWeight },
        { id, slots, maxWeight, label },
        { id, { label = label, slots = slots, maxWeight = maxWeight, maxweight = maxWeight } },
    }

    for _, method in ipairs(methodNames) do
        for _, args in ipairs(argLayouts) do
            local ok, result = pcall(function()
                return exports[inventoryResource][method](table.unpack(args))
            end)
            if ok and result ~= false then return true end
        end
    end
    return false
end

-- ============================================================
--  Callback: amb_server:prepareDepartmentStash
--  Registers a department stash with the configured inventory
--  system (ox, tgiann, quasar, origin, core, or qb/esx default).
-- ============================================================
Framework.CreateCallback("amb_server:prepareDepartmentStash", function(_playerId, cb, params)
    -- Extract and validate stash id
    local stashId = tostring((params and params.stashId) or "")
    if stashId == "" then
        cb({ ok = false })
        return
    end

    local label     = tostring((params and params.label)     or "Department Stash")
    local slots     = tonumber((params and params.slots))    or 80
    local maxWeight = tonumber((params and params.maxWeight)) or 400000

    local inventoryType = tostring(Config.Inventory or ""):lower()
    local cacheKey      = inventoryType .. ":" .. stashId

    -- Supported inventories that need explicit stash registration
    local needsRegistration = (inventoryType == "ox" or inventoryType == "tgiann"
                             or inventoryType == "quasar" or inventoryType == "origin"
                             or inventoryType == "core")

    if needsRegistration then
        -- Already registered this session – skip
        if registeredStashes[cacheKey] == true then
            cb({ ok = true, stashId = stashId, inventory = inventoryType })
            return
        end

        local registered = false

        if inventoryType == "ox" then
            if GetResourceState("ox_inventory") == "started" then
                local ok = pcall(function()
                    exports.ox_inventory:RegisterStash(stashId, label, slots, maxWeight)
                end)
                registered = ok
            end
        elseif inventoryType == "tgiann" then
            local res = getFirstStartedResource({ "tgiann-inventory", "tgiann_inventory" })
            registered = tryRegisterStash(res, stashId, label, slots, maxWeight)
        elseif inventoryType == "quasar" then
            local res = getFirstStartedResource({ "qs-inventory", "qs_inventory", "quasar-inventory", "quasar_inventory" })
            registered = tryRegisterStash(res, stashId, label, slots, maxWeight)
        elseif inventoryType == "origin" then
            local res = getFirstStartedResource({ "origin_inventory", "origin-inventory", "origen_inventory", "origen-inventory" })
            registered = tryRegisterStash(res, stashId, label, slots, maxWeight)
        elseif inventoryType == "core" then
            local res = getFirstStartedResource({ "core_inventory", "core-inventory" })
            registered = tryRegisterStash(res, stashId, label, slots, maxWeight)
        end

        -- ox_inventory registration must succeed; others are best-effort
        if inventoryType == "ox" and not registered then
            cb({ ok = false })
            return
        end

        if registered or inventoryType ~= "ox" then
            registeredStashes[cacheKey] = true
        end
    else
        -- For QBCore / ESX and other inventories, mark as registered without any API call
        registeredStashes[cacheKey] = true
    end

    cb({ ok = true, stashId = stashId, inventory = inventoryType })
end)

-- ============================================================
--  Callback: amb_server:getEMSInventoryData
--  Returns the configured EMS item list to the client.
-- ============================================================
Framework.CreateCallback("amb_server:getEMSInventoryData", function(_playerId, cb)
    local items = {}
    for k, v in pairs(Config.EMSItems or {}) do
        items[k] = v
    end
    cb(items)
end)

-- ============================================================
--  Net event: amb_server:takeEMSInventoryItem
--  Gives the caller one unit of a requested EMS item if they
--  have inventory space.
-- ============================================================
RegisterNetEvent("amb_server:takeEMSInventoryItem", function(params)
    local caller = source
    if not Framework.GetPlayer(caller) then return end

    local itemName = params.item
    if Framework.CanCarryItem(caller, itemName, 1) then
        Framework.AddItem(caller, itemName, 1)
        Framework.Notify(caller, _L("received_item", { item = itemName }), "success")
    else
        Framework.Notify(caller, _L("cannot_carry_more_item"), "error")
    end
end)

-- ============================================================
--  Net event: amb_server:ToggleDuty
--  Toggles on/off duty for the calling player.
--  Handles both QBCore (SetJobDuty) and ESX (setJob) approaches.
-- ============================================================
RegisterNetEvent("amb_server:ToggleDuty", function(overrideDept)
    local caller = source
    local player = Framework.GetPlayer(caller)
    if not player then return end

    -- Determine the department the player belongs to
    local deptJob = overrideDept or (player.job and player.job.name) or "ambulance"

    -- Ensure this department has a duty log entry
    DeptDutyLogs[deptJob] = DeptDutyLogs[deptJob] or {}

    local newOnDuty = false

    if Framework.Type == "qb" then
        -- QBCore: toggle current duty state
        newOnDuty = not player.job.onduty
        player.functions.SetJobDuty(newOnDuty)

    elseif Framework.Type == "esx" then
        local esxPlayer = Framework.Core.GetPlayerFromId(caller)
        if not (esxPlayer and esxPlayer.job) then return end

        local frameworkJob = GetFrameworkJobForDepartment(deptJob)
        local baseJob, actualJob, isOnDuty = parseOffDutyJob(esxPlayer.job.name, frameworkJob)

        -- Resolve current grade
        local currentGrade = tonumber(esxPlayer.job.grade) or tonumber(player.job.grade) or 0

        if isOnDuty then
            -- Going off-duty: cache the current grade
            setEsxGradeCache(caller, baseJob, currentGrade)
        else
            -- Going on-duty: restore cached grade if available
            local cached = getEsxGradeCache(caller, baseJob)
            if cached then currentGrade = cached end
        end

        -- Determine the target job name
        local targetJob = (isOnDuty or not baseJob) and actualJob or baseJob
        if not isOnDuty and not baseJob then targetJob = frameworkJob end

        -- Validate the target job exists in ESX
        if not esxJobExists(targetJob) then
            Framework.Notify(caller, ("Duty toggle failed: ESX job '%s' does not exist."):format(tostring(targetJob)), "error")
            return
        end

        local validGrade = esxValidateGrade(targetJob, currentGrade)
        esxPlayer.setJob(targetJob, validGrade)

        -- Verify the job change actually applied
        Wait(100)
        local refreshed = Framework.Core.GetPlayerFromId(caller)
        local applied   = refreshed and refreshed.job and tostring(refreshed.job.name) == tostring(targetJob)
        if not applied then
            Framework.Notify(caller, "Duty toggle failed: framework job did not update.", "error")
            return
        end

        newOnDuty = not isOnDuty
    end

    -- Resolve display name
    local displayName = player.name
    if not displayName and player.charinfo then
        displayName = (player.charinfo.firstname or "") .. " " .. (player.charinfo.lastname or "")
    end
    displayName = displayName or "Unknown"

    local action  = newOnDuty and "Clocked On" or "Clocked Off"
    local dateStr = os.date("%B %d, %Y")
    local timeStr = os.date("%H:%M")

    -- Append to in-memory log (capped at 100 entries per department)
    table.insert(DeptDutyLogs[deptJob], {
        officer = displayName,
        action  = action,
        date    = dateStr,
        time    = timeStr,
    })
    if #DeptDutyLogs[deptJob] > 100 then
        table.remove(DeptDutyLogs[deptJob], 1)
    end

    -- Persist to DB (try dept_job column first, then legacy `job` column)
    local dbOk = pcall(function()
        MySQL.Sync.execute(
            "INSERT INTO plt_ambulance_job_duty_logs (dept_job, officer, action, `date`, `time`) VALUES (?, ?, ?, ?, ?)",
            { deptJob, displayName, action, dateStr, timeStr }
        )
    end)
    if not dbOk then
        pcall(function()
            MySQL.Sync.execute(
                "INSERT INTO plt_ambulance_job_duty_logs (`job`, officer, action, `date`, `time`) VALUES (?, ?, ?, ?, ?)",
                { deptJob, displayName, action, dateStr, timeStr }
            )
        end)
    end

    -- Broadcast updated duty logs and refresh check-in zones
    TriggerClientEvent("amb_client:SyncData",            -1, { dutyLogs = DeptDutyLogs })
    TriggerClientEvent("amb_client:RefreshCheckInZones", -1)

    local statusLabel = newOnDuty and _L("duty_status_on") or _L("duty_status_off")
    Framework.Notify(caller, _L("duty_now", { status = statusLabel }), "info")
end)

-- ============================================================
--  playerDropped: clean up ESX grade cache on disconnect
-- ============================================================
AddEventHandler("playerDropped", function()
    esxGradeCache[source] = nil
end)

-- ============================================================
--  SaveMemberToDB(citizenId)  [global]
--  Persists one member's data to the DB and resyncs all clients.
-- ============================================================
function SaveMemberToDB(citizenId)
    local member = MemberData[citizenId]
    if not member then return end

    MySQL.Async.execute(
        "INSERT INTO plt_ambulance_job_members (`citizenid`, `name`, `job`, `grade`, `jobLabel`, `gradeLabel`, `ratings`) "
        .. "VALUES (@cid, @name, @job, @grade, @jobLabel, @gradeLabel, @ratings) "
        .. "ON DUPLICATE KEY UPDATE `name` = @name, `job` = @job, `grade` = @grade, `jobLabel` = @jobLabel, `gradeLabel` = @gradeLabel, `ratings` = @ratings",
        {
            ["@cid"]        = citizenId,
            ["@name"]       = member.name,
            ["@job"]        = member.job,
            ["@grade"]      = member.grade,
            ["@jobLabel"]   = member.jobLabel,
            ["@gradeLabel"] = member.gradeLabel,
            ["@ratings"]    = json.encode(member.ratings or {}),
        }
    )

    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
end

-- ============================================================
--  SyncPlayerJobWithMemberData(playerId)  [global]
--  Called on player load and job change.
--  If the player's current job maps to a known department,
--  creates/updates their MemberData entry and saves to DB.
--  If not, removes them from MemberData and deletes the DB row.
-- ============================================================
function SyncPlayerJobWithMemberData(playerId)
    local player = Framework.GetPlayer(playerId)
    if not player then return end

    local jobName  = player.job.name
    local grade    = tonumber(player.job.grade) or 0
    local cid      = player.citizenid
    local deptId   = GetDepartmentIdForFrameworkJob(jobName)

    if deptId then
        -- Player is in a recognised department – find labels from DepartmentData
        local jobLabel   = "Unknown"
        local gradeLabel = "Rank " .. grade

        for _, node in ipairs(DepartmentData.nodes or {}) do
            if node.type == "department" and node.id == deptId then
                jobLabel = node.label or deptId

                -- Find the rank node linked from this department
                for _, link in ipairs(DepartmentData.links or {}) do
                    if link.from == deptId then
                        for _, rankNode in ipairs(DepartmentData.nodes or {}) do
                            if rankNode.id == link.to and rankNode.type == "rank" then
                                for _, rank in ipairs(rankNode.ranks or {}) do
                                    if tonumber(rank.level) == grade then
                                        gradeLabel = rank.name or gradeLabel
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

        MemberData[cid] = {
            name       = player.name,
            job        = deptId,
            grade      = grade,
            jobLabel   = jobLabel,
            gradeLabel = gradeLabel,
            ratings    = (MemberData[cid] and MemberData[cid].ratings) or {},
        }
        SaveMemberToDB(cid)
    else
        -- Player is no longer in a department – remove them
        if MemberData[cid] then
            MemberData[cid] = nil
            MySQL.Async.execute("DELETE FROM plt_ambulance_job_members WHERE citizenid = ?", { cid })
            TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
        end
    end
end

-- ============================================================
--  Framework-specific job sync hooks
-- ============================================================
if Framework.Type == "qb" then
    RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function(playerId)
        SyncPlayerJobWithMemberData(playerId)
    end)
    RegisterNetEvent("QBCore:Server:OnJobUpdate", function(playerId, _newJob)
        SyncPlayerJobWithMemberData(playerId)
    end)
elseif Framework.Type == "esx" then
    AddEventHandler("esx:playerLoaded", function(playerId, _esxPlayer)
        SyncPlayerJobWithMemberData(playerId)
    end)
    RegisterNetEvent("esx:setJob", function(playerId, _newJob)
        SyncPlayerJobWithMemberData(playerId)
    end)
end

-- ============================================================
--  isPlayerWhitelisted(playerId)  [internal]
--  Checks the license whitelist configured in Config.
--  Returns false if the whitelist is disabled or empty.
-- ============================================================
local function isPlayerWhitelisted(playerId)
    if Config.UseLicenseWhitelist ~= true then return false end

    local whitelist = Config.LicenseWhitelist
    if not whitelist or type(whitelist) ~= "table" or #whitelist == 0 then
        return false
    end

    -- Normalise a license string: trim whitespace, lowercase,
    -- and prepend "license:" if the string looks like a raw hash.
    local function normalizeLicense(raw)
        if type(raw) ~= "string" then return nil end
        raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if raw == "" then return nil end
        -- If the string has no colon prefix and is ≥ 20 chars, assume it's a bare hash
        if not raw:find(":", 1, true) and #raw >= 20 then
            raw = "license:" .. raw
        end
        return raw
    end

    -- Returns true for strings that are clearly placeholder/invalid licenses
    local function isPlaceholder(s)
        if type(s) ~= "string" then return true end
        s = s:lower():gsub("%s+", "")
        if s == "" then return true end
        -- Strip license prefix for further checks
        s = s:gsub("^license2?:", "")
        if s == "" then return true end
        if s:find("^x+$") then return true end   -- all x's
        if s:find("^example")   then return true end
        if s:find("^changeme")  then return true end
        if s:find("^your_")     then return true end
        if s:find("^your%-")    then return true end
        return false
    end

    -- Build a lookup set from the whitelist, including both license: and license2: variants
    local allowedLicenses = {}
    local hasAnyValid     = false
    for _, entry in ipairs(whitelist) do
        local normalized = normalizeLicense(entry)
        if normalized and not isPlaceholder(normalized) then
            allowedLicenses[normalized] = true
            hasAnyValid = true
            -- Also add the license2: ↔ license: cross-variant
            if normalized:sub(1, 9) == "license2:" then
                allowedLicenses["license:" .. normalized:sub(10)] = true
            elseif normalized:sub(1, 8) == "license:" then
                allowedLicenses["license2:" .. normalized:sub(9)] = true
            end
        end
    end
    if not hasAnyValid then return false end

    -- Check the player's identifiers against the whitelist set
    for _, identifier in ipairs(GetPlayerIdentifiers(playerId)) do
        local normalized = normalizeLicense(identifier)
        if normalized then
            local prefix = normalized:sub(1, 8)
            local prefix2 = normalized:sub(1, 9)
            if prefix == "license:" or prefix2 == "license2:" then
                if allowedLicenses[normalized] then return true end
                -- Also try the cross-variant
                if prefix2 == "license2:" then
                    if allowedLicenses["license:" .. normalized:sub(10)] then return true end
                elseif prefix == "license:" then
                    if allowedLicenses["license2:" .. normalized:sub(9)] then return true end
                end
            end
        end
    end
    return false
end

-- ============================================================
--  Command: /setjob [id] [dept] [grade]
--  Sets the job of a player to the specified department.
--  Requires admin permission or EMS status (QBCore only).
-- ============================================================
RegisterCommand("setjob", function(caller, args)
    local hasAdmin = (caller == 0) or Framework.HasPermission(caller, Config.Permission)
    if not hasAdmin and Framework.Type == "qb" then
        hasAdmin = exports.plt_ambulance_job:IsEMS(caller)
    end

    if not hasAdmin then
        Framework.Notify(caller, _L("no_command_permission"), "error")
        return
    end

    local targetId = tonumber(args[1])
    local deptName = tostring(args[2] or "")
    local grade    = tonumber(args[3]) or 0

    if not targetId or deptName == "" then
        Framework.Notify(caller, _L("setjob_usage"), "error")
        return
    end

    local target = Framework.GetPlayer(targetId)
    if not target then
        Framework.Notify(caller, _L("player_not_found"), "error")
        return
    end

    local frameworkJob = GetFrameworkJobForDepartment(deptName)
    Framework.SetJob(targetId, frameworkJob, grade)
    Framework.Notify(caller, _L("setjob_success", {
        name  = target.name or targetId,
        job   = frameworkJob,
        grade = grade,
    }), "success")
end, false)

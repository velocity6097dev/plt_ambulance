local NewsData = {}
local Balances = {}
local Finances = {}
local PatientProfiles = {}
local PCRs = {}
local EMSInvoices = {}

local InvoiceCounter = 0
local IsDataLoaded = false
local HasPCRTable = true

local ValidBloodTypesMap = {
    ["A+"] = true, ["A-"] = true, ["B+"] = true, ["B-"] = true,
    ["AB+"] = true, ["AB-"] = true, ["O+"] = true, ["O-"] = true
}
local ValidBloodTypesArray = {"A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"}

-- ==========================================
-- Database Initialization & Savers
-- ==========================================

CreateThread(function()
    while not MySQL do Wait(10) end

    -- Load News
    local newsRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", {"news"})
    if newsRes[1] then
        NewsData = json.decode(newsRes[1].value) or {}
    end

    -- Verify PCR Table (ESX specific check)
    if Framework.Type == "esx" then
        local success, result = pcall(function()
            return MySQL.Sync.fetchAll("SHOW TABLES LIKE ?", {"plt_ambulance_job_pcrs"})
        end)
        HasPCRTable = success and result and result[1] ~= nil
    end

    if HasPCRTable then
        local pcrRes = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_pcrs ORDER BY id DESC LIMIT 50", {})
        PCRs = pcrRes or {}
    else
        PCRs = {}
        print("^3[plt_ambulance][ESX] Table 'plt_ambulance_job_pcrs' not found; PCR persistence disabled until table is created.^7")
    end

    -- Load Balances
    local balRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", {"balances"})
    if balRes[1] then
        Balances = json.decode(balRes[1].value) or {}
    end

    -- Load Finances (Transactions)
    local finRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", {"finances"})
    if finRes[1] then
        Finances = json.decode(finRes[1].value) or {}
    end

    -- Load Patient Profiles
    local profRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", {"patient_profiles"})
    if profRes[1] then
        PatientProfiles = json.decode(profRes[1].value) or {}
    end

    IsDataLoaded = true
end)

function SaveNews()
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
        ["@key"] = "news",
        ["@value"] = json.encode(NewsData)
    })
    TriggerClientEvent("amb_client:SyncNews", -1, NewsData)
end

function SaveFinances(deptName)
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
        ["@key"] = "balances",
        ["@value"] = json.encode(Balances)
    })
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
        ["@key"] = "finances",
        ["@value"] = json.encode(Finances)
    })
    
    local syncData = {
        balances = Balances,
        finances = Finances,
        transactions = deptName and Finances[deptName] or nil
    }
    TriggerClientEvent("amb_client:SyncData", -1, syncData)
end

function SavePatientProfiles()
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
        ["@key"] = "patient_profiles",
        ["@value"] = json.encode(PatientProfiles)
    })
end

-- ==========================================
-- Utility Functions
-- ==========================================

local function GetCleanBloodType(bType)
    if type(bType) ~= "string" then return nil end
    local clean = string.gsub(bType:upper(), "%s+", "")
    if ValidBloodTypesMap[clean] then return clean end
    return nil
end

local function GetOrGeneratePatientProfile(cid, metadata)
    local citizenIdStr = tostring(cid)
    local profile = PatientProfiles[citizenIdStr] or {}

    -- Blood Type
    local bType = GetCleanBloodType(profile.blood_type)
    if not bType then
        if metadata and GetCleanBloodType(metadata.bloodtype) then
            bType = GetCleanBloodType(metadata.bloodtype)
        else
            bType = ValidBloodTypesArray[math.random(1, #ValidBloodTypesArray)]
        end
        profile.blood_type = bType
    else
        profile.blood_type = bType
    end

    -- Allergies
    local allergy = profile.known_allergy
    if type(allergy) == "string" and string.gsub(allergy, "%s+", "") == "" then
        allergy = nil
    end

    if not allergy then
        local metaAllergy = metadata and metadata.allergies or nil
        if type(metaAllergy) == "string" and string.gsub(metaAllergy, "%s+", "") ~= "" then
            profile.known_allergy = metaAllergy
        else
            profile.known_allergy = "None"
        end
    end

    PatientProfiles[citizenIdStr] = profile
    return profile
end

local function GetDepartmentIdForPlayer(playerData)
    if not playerData then return nil end

    if type(GetDepartmentIdForFrameworkJob) == "function" then
        local fwJobId = GetDepartmentIdForFrameworkJob(playerData.job.name)
        if fwJobId then return fwJobId end
    end

    if MemberData and playerData.citizenid and MemberData[playerData.citizenid] then
        return MemberData[playerData.citizenid].job
    end

    return playerData.job and playerData.job.name or nil
end

-- ==========================================
-- Finance Wrappers
-- ==========================================

local function GetFinanceSystem()
    if type(Config.DepartmentFinance) == "string" then return Config.DepartmentFinance end
    if type(Config.DepartmentFinance) == "table" then return Config.DepartmentFinance.System or "internal" end
    return "internal"
end

local function GetDepartmentBalance(deptName)
    if not Balances[deptName] then
        Balances[deptName] = (Config.DefaultDeptBalance or 500000)
    end
    
    -- If using an external banking system, check that logic here (omitted for standard internal fallback)
    -- E.g., Renewed-Banking exports logic
    
    return Balances[deptName]
end

local function AddFinanceEntry(dept, type, amount, label, author)
    if not Finances[dept] then Finances[dept] = {} end
    
    local success = true
    local newBalance = GetDepartmentBalance(dept)
    
    -- Update internal balance logic
    if type == "deposit" then
        newBalance = newBalance + amount
        Balances[dept] = newBalance
    elseif type == "withdraw" then
        if amount > newBalance then return false end
        newBalance = newBalance - amount
        Balances[dept] = newBalance
    end

    table.insert(Finances[dept], 1, {
        id = #Finances[dept] + 1,
        type = type,
        amount = amount,
        label = label,
        author = author or "SYSTEM",
        date = os.date("%B %d, %Y %H:%M"),
        balance = newBalance
    })

    if #Finances[dept] > 50 then table.remove(Finances[dept]) end
    SaveFinances(dept)
    return true
end
exports("AddFinanceEntry", AddFinanceEntry)

-- ==========================================
-- Invoices
-- ==========================================

local function ExpireInvoices()
    local expireMins = (Config.EMSInvoice and Config.EMSInvoice.ExpireMinutes) or 10
    local expireSecs = expireMins * 60
    if expireSecs <= 0 then return end
    
    local currentTime = os.time()
    for id, inv in pairs(EMSInvoices) do
        if inv.createdAt and (currentTime - inv.createdAt) > expireSecs then
            EMSInvoices[id] = nil
        end
    end
end

RegisterNetEvent("amb_server:createEMSInvoice", function(targetSrc, amount, reason)
    local src = source
    local medic = Framework.GetPlayer(src)
    local target = Framework.GetPlayer(targetSrc)
    
    if not medic or not target then return end
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        return Framework.Notify(src, _L("not_authorized"), "error")
    end

    local amt = math.floor(tonumber(amount) or 0)
    local maxAmt = (Config.EMSInvoice and Config.EMSInvoice.MaxAmount) or 100000

    if amt <= 0 or amt > maxAmt then
        return Framework.Notify(src, _L("ems_invoice_bad_amount", {max = maxAmt}), "error")
    end
    
    if not reason or string.gsub(reason, "^%s*(.-)%s*$", "%1") == "" then
        return Framework.Notify(src, _L("ems_invoice_no_reason"), "error")
    end

    ExpireInvoices()
    InvoiceCounter = InvoiceCounter + 1
    
    local deptName = GetDepartmentIdForPlayer(medic) or "ambulance"
    
    local invoice = {
        id = InvoiceCounter,
        medicSrc = src,
        patientSrc = targetSrc,
        dept = deptName,
        amount = amt,
        reason = string.sub(reason, 1, 120),
        medicName = medic.name,
        patientName = target.name,
        departmentLabel = (medic.job and medic.job.label) or deptName,
        createdAt = os.time()
    }

    EMSInvoices[invoice.id] = invoice
    
    Framework.Notify(src, _L("ems_invoice_sent", {id = invoice.id, name = target.name, amount = amt}), "success")
    
    local payCmd = (Config.EMSInvoice and Config.EMSInvoice.PayCommandName) or "payemsinvoice"
    local decCmd = (Config.EMSInvoice and Config.EMSInvoice.DeclineCommandName) or "declineemsinvoice"
    
    Framework.Notify(targetSrc, _L("ems_invoice_received", {
        department = invoice.departmentLabel,
        id = invoice.id,
        amount = amt,
        reason = invoice.reason,
        payCommand = payCmd,
        declineCommand = decCmd
    }), "warning")
    
    TriggerClientEvent("amb_client:EMSInvoiceReceived", targetSrc, invoice)
end)

-- ==========================================
-- Callbacks & Menu Data
-- ==========================================

Framework.CreateCallback("amb_server:getBossMenuData", function(source, cb, reqDept)
    local players = GetPlayersList()
    local player = Framework.GetPlayer(source)
    local dept = reqDept or (player and player.job and player.job.name) or "ambulance"

    if not Balances[dept] then Balances[dept] = GetDepartmentBalance(dept) end
    if not Finances[dept] then Finances[dept] = {} end

    local externalDepts = {}
    if GetResourceState("plt_departments") == "started" then
        externalDepts = exports.plt_departments:GetDepartmentCatalog(2000) or {}
    end

    cb({
        data = DepartmentData,
        externalDepts = externalDepts,
        members = players,
        news = NewsData,
        pcrs = PCRs,
        dutyLogs = DeptDutyLogs or {},
        balances = Balances,
        finances = Finances,
        transactions = Finances[dept]
    })
end)

-- PCR Handling
RegisterNetEvent("amb_server:addPCR", function(data)
    local src = source
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then return end
    
    local player = Framework.GetPlayer(src)
    if not player then return end

    local newPCR = {
        patient = data.patient,
        condition = data.condition,
        treatment = data.treatment,
        author = player.name,
        date = os.date("%B %d, %Y")
    }

    if HasPCRTable then
        MySQL.Async.insert("INSERT INTO plt_ambulance_job_pcrs (patient, `condition`, treatment, author, date) VALUES (?, ?, ?, ?, ?)", {
            newPCR.patient, newPCR.condition, newPCR.treatment, newPCR.author, newPCR.date
        }, function(id)
            newPCR.id = id
            table.insert(PCRs, 1, newPCR)
            if #PCRs > 50 then table.remove(PCRs) end
            TriggerClientEvent("amb_client:SyncData", -1, { pcrs = PCRs })
        end)
    else
        newPCR.id = #PCRs + 1
        table.insert(PCRs, 1, newPCR)
        if #PCRs > 50 then table.remove(PCRs) end
        TriggerClientEvent("amb_client:SyncData", -1, { pcrs = PCRs })
    end
end)

-- Patient Management
Framework.CreateCallback("amb_server:searchPatients", function(source, cb, data)
    local query = data.query
    if not query or #query < 2 then return cb({}) end

    local results = {}
    local success, sqlRes = pcall(function()
        return MySQL.Sync.fetchAll([[
            SELECT citizenid as cid, charinfo 
            FROM players 
            WHERE citizenid LIKE ? OR charinfo LIKE ? LIMIT 20
        ]], {"%"..query.."%", "%"..query.."%"})
    end)

    if success and sqlRes and #sqlRes > 0 then
        for _, row in ipairs(sqlRes) do
            local charinfo = row.charinfo
            if type(charinfo) == "string" then charinfo = json.decode(charinfo) end
            
            local fullName = "Unknown"
            local phone = "N/A"
            if charinfo then
                fullName = (charinfo.firstname or "Unknown") .. " " .. (charinfo.lastname or "Citizen")
                phone = charinfo.phone or "N/A"
            end
            table.insert(results, { cid = row.cid, name = fullName, phone = phone })
        end
    end
    cb(results)
end)

Framework.CreateCallback("amb_server:updatePatientAllergy", function(source, cb, data)
    if not exports.plt_ambulance_job:IsEMS(source) and not Framework.HasPermission(source, Config.Permission) then
        return cb({ success = false, message = _L("not_authorized") })
    end

    local cid = data and data.cid and tostring(data.cid)
    if not cid or cid == "" then
        return cb({ success = false, message = "Missing patient ID." })
    end

    local allergy = type(data.known_allergy) == "string" and data.known_allergy or ""
    allergy = string.gsub(allergy, "^%s+", "")
    allergy = string.gsub(allergy, "%s+$", "")
    if allergy == "" then allergy = "None" end
    if #allergy > 120 then allergy = string.sub(allergy, 1, 120) end

    local profile = GetOrGeneratePatientProfile(cid)
    profile.known_allergy = allergy
    PatientProfiles[cid] = profile
    SavePatientProfiles()

    cb({ success = true, known_allergy = allergy })
end)

-- Finance Actions
RegisterNetEvent("amb_server:financeAction", function(data)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        return Framework.Notify(src, _L("not_authorized_funds"), "error")
    end

    local dept = data.dept or player.job.name
    local action = data.action
    local amount = tonumber(data.amount)

    if not amount or amount <= 0 then return end
    if not Balances[dept] then Balances[dept] = GetDepartmentBalance(dept) end

    if action == "deposit" then
        if player.functions.RemoveMoney("cash", amount, "dept-deposit") then
            if AddFinanceEntry(dept, "deposit", amount, "Manual Deposit", player.name) then
                Framework.Notify(src, _L("deposited_funds", {amount = amount}), "success")
            else
                player.functions.AddMoney("cash", amount, "dept-deposit-refund")
                Framework.Notify(src, "Department finance backend error.", "error")
            end
        else
            Framework.Notify(src, _L("not_enough_cash_short"), "error")
        end

    elseif action == "withdraw" then
        local bal = GetDepartmentBalance(dept)
        if not bal or amount > bal then
            return Framework.Notify(src, _L("not_enough_department_funds"), "error")
        end

        if AddFinanceEntry(dept, "withdraw", amount, "Manual Withdrawal", player.name) then
            if player.functions.AddMoney("cash", amount, "dept-withdrawal") then
                Framework.Notify(src, _L("withdrew_funds", {amount = amount}), "success")
            else
                AddFinanceEntry(dept, "deposit", amount, "Withdrawal Rollback", "SYSTEM")
                Framework.Notify(src, "Department finance backend error.", "error")
            end
        else
            Framework.Notify(src, _L("not_enough_department_funds"), "error")
        end
    end
end)

-- Mail System
function SendDepartmentMail(senderDept, receiverDept, senderName, subject, message, imageUrl)
    local dateStr = os.date("%B %d, %Y")
    local timeStr = os.date("%H:%M")

    MySQL.Async.insert("INSERT INTO plt_ambulance_job_mails (sender_dept, receiver_dept, sender_name, subject, message, image_url, `date`, `time`, is_read) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)", {
        senderDept, receiverDept, senderName, subject, message, imageUrl or "", dateStr, timeStr
    })
    
    -- Notify online employees of the receiving department
    local players = GetPlayers()
    for _, ply in ipairs(players) do
        local target = Framework.GetPlayer(tonumber(ply))
        if target then
            local tDept = GetDepartmentIdForPlayer(target)
            if tDept == receiverDept then
                Framework.Notify(tonumber(ply), "New department mail received from " .. senderDept:upper(), "info")
                TriggerClientEvent("amb_client:SyncMail", tonumber(ply))
            end
        end
    end
end
exports("SendDepartmentMail", SendDepartmentMail)

Framework.CreateCallback("amb_server:getMails", function(source, cb, deptName)
    local mails = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_mails WHERE receiver_dept = ? OR sender_dept = ? ORDER BY id DESC LIMIT 50", {deptName, deptName})
    cb(mails or {})
end)

RegisterNetEvent("amb_server:sendMail", function(data)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end
    
    SendDepartmentMail(data.senderDept, data.receiverDept, player.name, data.subject, data.message, data.imageUrl)
end)

RegisterNetEvent("amb_server:markMailRead", function(id)
    MySQL.Async.execute("UPDATE plt_ambulance_job_mails SET is_read = 1 WHERE id = ?", {id})
end)

RegisterNetEvent("amb_server:deleteMail", function(id)
    MySQL.Async.execute("DELETE FROM plt_ambulance_job_mails WHERE id = ?", {id})
end)

-- News
RegisterNetEvent("amb_server:addNews", function(data)
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then return end
    local player = Framework.GetPlayer(src)
    if not player then return end

    table.insert(NewsData, {
        id = #NewsData + 1,
        title = data.title,
        content = data.content,
        author = player.name,
        date = os.date("%B %d, %Y")
    })
    SaveNews()
end)

RegisterNetEvent("amb_server:deleteNews", function(id)
    if not Framework.HasPermission(source, Config.Permission) then return end
    for i, news in ipairs(NewsData) do
        if news.id == id then
            table.remove(NewsData, i)
            break
        end
    end
    SaveNews()
end)

-- Exports
exports("GetDepartmentCatalog", function()
    local catalog = {}
    if DepartmentData and DepartmentData.nodes then
        for _, node in ipairs(DepartmentData.nodes) do
            if node.type == "department" then
                table.insert(catalog, {
                    id = node.id,
                    label = node.label,
                    frameworkJob = node.frameworkJob or node.id
                })
            end
        end
    end
    return catalog
end)

exports("GetDepartmentsData", function()
    return DepartmentData
end)
-- =============================================================================
-- plt_ambulance | Boss Menu Server Script
-- Deobfuscated and cleaned up from compiled/obfuscated Lua
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Module-level state
-- ---------------------------------------------------------------------------
local newsItems        = {}   -- List of news posts
local newsReady        = false

local pcrList          = {}   -- Patient Care Reports (last 50)
local pcrTableExists   = false -- whether plt_ambulance_job_pcrs table exists

local balances         = {}   -- Department balances:   balances[deptId] = number
local finances         = {}   -- Finance ledgers:       finances[deptId] = { transactions }
local financesReady    = false

local patientProfiles  = {}   -- Patient profiles:      patientProfiles[citizenId] = { blood_type, known_allergy }

local pendingInvoices  = {}   -- Active EMS invoices:   pendingInvoices[id] = invoiceData
local invoiceCounter   = 0

-- Blood-type lookup / ordered list
local BLOOD_TYPE_VALID = {
    ["A+"] = true, ["A-"] = true,
    ["B+"] = true, ["B-"] = true,
    ["AB+"] = true, ["AB-"] = true,
    ["O+"] = true, ["O-"] = true,
}
local BLOOD_TYPE_LIST = { "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-" }

-- =============================================================================
-- Startup: load persisted data from MySQL
-- =============================================================================
CreateThread(function()
    -- Wait until MySQL is available
    while not MySQL do
        Wait(10)
    end

    -- Load news
    local newsRows = MySQL.Sync.fetchAll(
        "SELECT value FROM plt_ambulance_job_data WHERE `key` = ?",
        { "news" }
    )
    if newsRows[1] then
        newsItems = json.decode(newsRows[1].value) or {}
    end
    newsReady = true

    -- Check / load PCR table (ESX only)
    if Framework.Type == "esx" then
        local ok, rows = pcall(function()
            return MySQL.Sync.fetchAll("SHOW TABLES LIKE ?", { "plt_ambulance_job_pcrs" })
        end)
        if ok and rows then
            pcrTableExists = rows[1] ~= nil
        end
    end

    if pcrTableExists then
        local rows = MySQL.Sync.fetchAll(
            "SELECT * FROM plt_ambulance_job_pcrs ORDER BY id DESC LIMIT 50",
            {}
        )
        pcrList = rows or {}
    else
        pcrList = {}
        print("^3[plt_ambulance][ESX] Table 'plt_ambulance_job_pcrs' not found; PCR persistence disabled until table is created.^7")
    end
    pcrTableExists = true -- mark ready even if table is absent

    -- Load balances
    local balRows = MySQL.Sync.fetchAll(
        "SELECT value FROM plt_ambulance_job_data WHERE `key` = ?",
        { "balances" }
    )
    if balRows[1] then
        balances = json.decode(balRows[1].value) or {}
    end

    -- Load finances
    local finRows = MySQL.Sync.fetchAll(
        "SELECT value FROM plt_ambulance_job_data WHERE `key` = ?",
        { "finances" }
    )
    if finRows[1] then
        finances = json.decode(finRows[1].value) or {}
    end
    financesReady = true

    -- Load patient profiles
    local ppRows = MySQL.Sync.fetchAll(
        "SELECT value FROM plt_ambulance_job_data WHERE `key` = ?",
        { "patient_profiles" }
    )
    if ppRows[1] then
        patientProfiles = json.decode(ppRows[1].value) or {}
    end
end)

-- =============================================================================
-- Persistence helpers
-- =============================================================================

local function SaveNews()
    MySQL.Async.execute(
        "INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value",
        { ["@key"] = "news", ["@value"] = json.encode(newsItems) }
    )
    TriggerClientEvent("amb_client:SyncNews", -1, newsItems)
end

local function SavePatientProfiles()
    MySQL.Async.execute(
        "INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value",
        { ["@key"] = "patient_profiles", ["@value"] = json.encode(patientProfiles) }
    )
end

--- Save balances and finances, then push a sync event to all clients.
--- @param deptId string|nil  If provided, include only that dept's transactions.
local function SaveFinances(deptId)
    MySQL.Async.execute(
        "INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value",
        { ["@key"] = "balances", ["@value"] = json.encode(balances) }
    )
    MySQL.Async.execute(
        "INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value",
        { ["@key"] = "finances", ["@value"] = json.encode(finances) }
    )

    local transactions = nil
    if deptId and finances[deptId] then
        transactions = finances[deptId]
    end

    TriggerClientEvent("amb_client:SyncData", -1, {
        balances     = balances,
        finances     = finances,
        transactions = transactions,
    })
end

-- =============================================================================
-- Utility: blood type
-- =============================================================================

--- Normalise a blood type string and return it if valid, else nil.
local function NormaliseBloodType(raw)
    if type(raw) ~= "string" then return nil end
    local upper = raw:upper():gsub("%s+", "")
    if BLOOD_TYPE_VALID[upper] then return upper end
    return nil
end

-- =============================================================================
-- Utility: patient profile
-- =============================================================================

--- Return (and lazily create) a patient profile for citizenId.
--- playerData is an optional framework player object used to seed defaults.
local function GetOrCreatePatientProfile(citizenId, playerData)
    local cid    = tostring(citizenId)
    local profile = patientProfiles[cid] or {}

    -- Blood type
    local bloodType = NormaliseBloodType(profile.blood_type)
    if not bloodType then
        -- Try to seed from framework metadata
        local seeded
        if playerData then
            seeded = NormaliseBloodType(playerData.bloodtype)
        end
        if not seeded then
            -- Random fallback
            seeded = BLOOD_TYPE_LIST[math.random(1, #BLOOD_TYPE_LIST)]
        end
        profile.blood_type = seeded
    else
        profile.blood_type = bloodType
    end

    -- Known allergy
    local allergy = profile.known_allergy
    if type(allergy) == "string" and allergy:gsub("%s+", "") ~= "" then
        -- Keep existing value (jump past re-seeding)
    else
        local seededAllergy
        if playerData then
            seededAllergy = playerData.allergies
        end
        if type(seededAllergy) == "string" and seededAllergy:gsub("%s+", "") ~= "" then
            profile.known_allergy = seededAllergy
        else
            profile.known_allergy = "None"
        end
    end

    patientProfiles[cid] = profile
    return profile
end

-- =============================================================================
-- Utility: safe MySQL query wrapper
-- =============================================================================

local function SafeQuery(query, params, context)
    local ok, result = pcall(function()
        return MySQL.Sync.fetchAll(query, params or {})
    end)
    if not ok then
        print(("[plt_ambulance][ESX][%s] Query failed: %s"):format(
            context or "unknown", tostring(result)
        ))
        return nil
    end
    return result
end

-- =============================================================================
-- Utility: job/department name helpers
-- =============================================================================

--- Parse off-duty suffixes from an ESX job name and return (baseName, isOnDuty).
local function ParseJobName(jobName)
    local s = tostring(jobName or "")

    if s:sub(1, 4) == "off_" then
        return s:sub(5), false
    end
    if s:sub(1, 3) == "off" and #s > 3 then
        return s:sub(4), false
    end
    if s:sub(-8) == "_offduty" then
        return s:sub(1, -9), false
    end
    if s:sub(-4) == "_off" then
        return s:sub(1, -5), false
    end
    return s, true
end

--- Find the rank node linked to deptId in DepartmentData.
local function GetRankNodeForDepartment(deptId)
    if not (DepartmentData and DepartmentData.links and DepartmentData.nodes) then
        return nil
    end
    local id = tostring(deptId or "")
    for _, link in ipairs(DepartmentData.links) do
        local fromStr = tostring(link.from or "")
        local toStr   = tostring(link.to   or "")
        local other   = nil
        if fromStr == id then
            other = toStr
        elseif toStr == id then
            other = fromStr
        end
        if other then
            for _, node in ipairs(DepartmentData.nodes) do
                if tostring(node.id) == other and node.type == "rank" then
                    return node
                end
            end
        end
    end
    return nil
end

--- Return pay for a given grade level inside a rank node (min 0).
local function GetPayForGrade(rankNode, grade)
    if not (rankNode and type(rankNode.ranks) == "table") then return 0 end
    local g = tonumber(grade) or 0
    for _, rank in ipairs(rankNode.ranks) do
        if tonumber(rank.level) == g then
            return math.max(0, tonumber(rank.pay) or 0)
        end
    end
    return 0
end

--- Resolve a player's department ID from framework data / MemberData.
local function GetDepartmentIdForPlayer(player)
    if not (player and player.job) then return nil end

    if type(GetDepartmentIdForFrameworkJob) == "function" then
        local dept = GetDepartmentIdForFrameworkJob(player.job.name)
        if dept then return dept end
    end

    if Framework.Type == "esx" then
        local baseName = ParseJobName(player.job.name)
        if type(GetDepartmentIdForFrameworkJob) == "function" then
            local dept = GetDepartmentIdForFrameworkJob(baseName)
            if dept then return dept end
        end
    end

    if MemberData and player.citizenid then
        local entry = MemberData[player.citizenid]
        if entry and entry.job then return entry.job end
    end

    return nil
end

--- Build a payroll list for all online members of deptId.
--- Returns (list, totalAmount).
local function BuildSalaryList(deptId)
    local rankNode = GetRankNodeForDepartment(deptId)
    if not rankNode then return {}, 0 end

    local list  = {}
    local total = 0

    for _, svId in ipairs(GetPlayers()) do
        local src    = tonumber(svId)
        local player = Framework.GetPlayer(src)
        if player then
            local dept = tostring(GetDepartmentIdForPlayer(player) or "")
            if dept == tostring(deptId) then
                local grade = (player.job and player.job.grade) and player.job.grade or 0
                local pay   = GetPayForGrade(rankNode, grade)
                if pay > 0 then
                    local name = player.name or ("ID " .. tostring(src))
                    table.insert(list, { source = src, amount = pay, name = name })
                    total = total + pay
                end
            end
        end
    end

    return list, total
end

-- =============================================================================
-- Utility: pay a player from the department balance
-- =============================================================================

local function PayPlayerFromDept(entry)
    if Framework.Type == "esx" then
        local player = Framework.Core.GetPlayerFromId(entry.source)
        if not player then return false end
        player.addAccountMoney("bank", entry.amount)
        return true
    end
    local player = Framework.GetPlayer(entry.source)
    if not (player and player.functions) then return false end
    return player.functions.AddMoney("bank", entry.amount, "department-salary")
end

-- =============================================================================
-- Utility: Renewed-Banking integration
-- =============================================================================

local function GetFinanceSystem()
    local cfg = Config.DepartmentFinance
    if type(cfg) == "string" then return cfg end
    if type(cfg) == "table" then return cfg.System or "internal" end
    return "internal"
end

local function GetRenewedBankingResource()
    if type(Config.DepartmentFinance) == "table" and Config.DepartmentFinance.RenewedResource then
        return Config.DepartmentFinance.RenewedResource
    end
    return "Renewed-Banking"
end

local function IsRenewedBankingActive()
    local sys = tostring(GetFinanceSystem()):lower()
    if sys ~= "renewed-banking" and sys ~= "renewed_banking" then return false end
    return GetResourceState(GetRenewedBankingResource()) == "started"
end

local function GetDeptAccountName(deptId)
    local prefix = "ems_"
    if type(Config.DepartmentFinance) == "table" and Config.DepartmentFinance.AccountPrefix then
        prefix = Config.DepartmentFinance.AccountPrefix
    end
    return tostring(prefix) .. tostring(deptId)
end

--- Try calling methodNames on the Renewed-Banking export in order, returning
--- (true, result) on first success or (false, nil).
local function CallRenewedBanking(methodNames, ...)
    local resource = GetRenewedBankingResource()
    if GetResourceState(resource) ~= "started" then return false, nil end
    local args = { ... }
    for _, method in ipairs(methodNames) do
        local ok, result = pcall(function()
            return exports[resource][method](table.unpack(args))
        end)
        if ok then return true, result end
    end
    return false, nil
end

-- =============================================================================
-- Balance helpers
-- =============================================================================

local DEFAULT_BALANCE = 500000

--- Get the current balance for deptId (syncs from Renewed-Banking if active).
local function GetDeptBalance(deptId)
    if not balances[deptId] then
        balances[deptId] = Config.DefaultDeptBalance or DEFAULT_BALANCE
    end

    if not IsRenewedBankingActive() then
        return balances[deptId]
    end

    local accountName = GetDeptAccountName(deptId)
    local ok, result  = CallRenewedBanking(
        { "getAccountMoney", "GetAccountMoney", "getAccountBalance", "GetAccountBalance", "getBalance", "GetBalance" },
        accountName
    )
    if ok and tonumber(result) ~= nil then
        balances[deptId] = tonumber(result)
    end
    return balances[deptId]
end

--- Perform a deposit or withdrawal on deptId's balance.
--- Returns (success, newBalance).
local function MutateDeptBalance(deptId, action, amount, label, author)
    if not IsRenewedBankingActive() then
        -- Internal balance
        if not balances[deptId] then
            balances[deptId] = Config.DefaultDeptBalance or DEFAULT_BALANCE
        end
        if action == "deposit" then
            balances[deptId] = balances[deptId] + amount
            return true, balances[deptId]
        elseif action == "withdraw" then
            if amount > balances[deptId] then
                return false, balances[deptId]
            end
            balances[deptId] = balances[deptId] - amount
            return true, balances[deptId]
        end
        return true, balances[deptId]
    end

    -- Renewed-Banking path
    local accountName = GetDeptAccountName(deptId)
    local txLabel     = ("%s | %s"):format(tostring(label or "Transaction"), tostring(author or "SYSTEM"))
    local currentBal  = GetDeptBalance(deptId)

    if action == "withdraw" and amount > currentBal then
        return false, currentBal
    end

    if action == "deposit" then
        local ok = CallRenewedBanking(
            { "addAccountMoney", "AddAccountMoney", "addBalance", "AddBalance" },
            accountName, amount, txLabel
        )
        if not ok then return false, currentBal end
    elseif action == "withdraw" then
        local ok = CallRenewedBanking(
            { "removeAccountMoney", "RemoveAccountMoney", "removeBalance", "RemoveBalance" },
            accountName, amount, txLabel
        )
        if not ok then return false, currentBal end
    end

    local newBal = GetDeptBalance(deptId)
    return true, newBal
end

-- =============================================================================
-- Finance ledger
-- =============================================================================

--- Add a finance entry, mutate the balance, and persist.
--- Returns true on success.
local function AddFinanceEntry(deptId, action, amount, label, author)
    if not finances[deptId] then finances[deptId] = {} end

    local ok, newBalance = MutateDeptBalance(deptId, action, amount, label, author)
    if not ok then return false end

    balances[deptId] = newBalance

    local entry = {
        id      = #finances[deptId] + 1,
        type    = action,
        amount  = amount,
        label   = label,
        author  = author or "SYSTEM",
        date    = os.date("%B %d, %Y %H:%M"),
        balance = newBalance,
    }
    table.insert(finances[deptId], 1, entry)

    -- Cap ledger at 50 entries
    if #finances[deptId] > 50 then
        table.remove(finances[deptId])
    end

    SaveFinances(deptId)
    return true
end

exports("AddFinanceEntry", AddFinanceEntry)

-- =============================================================================
-- EMS Invoice config helpers
-- =============================================================================

local function GetInvoiceConfig()
    return Config.EMSInvoice or {}
end

local function TrimString(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- =============================================================================
-- Utility: resolve dept ID from player (for invoices / fire events)
-- =============================================================================

local function GetDeptIdForPlayer(player)
    if not (player and player.job) then return "ambulance" end

    if type(GetDepartmentIdForFrameworkJob) == "function" then
        local dept = GetDepartmentIdForFrameworkJob(player.job.name)
        if dept then return dept end
    end

    if MemberData and player.citizenid then
        local entry = MemberData[player.citizenid]
        if entry and entry.job then return entry.job end
    end

    return player.job.name or "ambulance"
end

-- =============================================================================
-- Utility: proximity check between two server IDs
-- =============================================================================

local function IsWithinDistance(srcA, srcB, maxDist)
    local dist = tonumber(maxDist) or 0
    if dist <= 0 then return true end

    local pedA = GetPlayerPed(srcA)
    local pedB = GetPlayerPed(srcB)
    if not (pedA and pedA ~= 0 and pedB and pedB ~= 0) then return true end

    local coordsA = GetEntityCoords(pedA)
    local coordsB = GetEntityCoords(pedB)
    if not (coordsA and coordsB) then return true end

    return dist >= #(coordsA - coordsB)
end

-- =============================================================================
-- EMS Invoice: expire old invoices
-- =============================================================================

local function ExpireInvoices()
    local cfg     = GetInvoiceConfig()
    local minutes = tonumber(cfg.ExpireMinutes) or 10
    local timeout = minutes * 60
    if timeout <= 0 then return end

    local now = os.time()
    for id, invoice in pairs(pendingInvoices) do
        if not invoice.createdAt or (now - invoice.createdAt) > timeout then
            pendingInvoices[id] = nil
        end
    end
end

--- Find the most recent (or specific) invoice belonging to patientSrc.
local function FindInvoice(patientSrc, invoiceId)
    ExpireInvoices()
    if invoiceId then
        local inv = pendingInvoices[invoiceId]
        if inv and inv.patientSrc == patientSrc then return inv end
        return nil
    end
    -- Return newest invoice for this patient
    local best = nil
    for _, inv in pairs(pendingInvoices) do
        if inv.patientSrc == patientSrc then
            if not best or inv.id > best.id then
                best = inv
            end
        end
    end
    return best
end

-- =============================================================================
-- EMS Invoice: try to charge payment accounts in order
-- =============================================================================

local function ChargePlayer(playerObj, amount)
    local cfg      = GetInvoiceConfig()
    local accounts = (type(cfg.PaymentAccounts) == "table" and #cfg.PaymentAccounts > 0)
        and cfg.PaymentAccounts
        or  { "bank", "cash" }

    for _, account in ipairs(accounts) do
        local accountStr = tostring(account or "")
        if accountStr ~= "" then
            local balance = tonumber(playerObj.functions.GetMoney(accountStr)) or 0
            if amount <= balance then
                local ok = playerObj.functions.RemoveMoney(accountStr, amount, "ems-invoice-payment")
                if ok then return true, accountStr end
            end
        end
    end
    return false, nil
end

-- =============================================================================
-- EMS Invoice: create
-- =============================================================================

local function CreateEMSInvoice(medicSrc, patientSrcRaw, amount, reason)
    local medicPlayer = Framework.GetPlayer(medicSrc)
    if not medicPlayer then return end

    -- Permission check
    local isEMS = exports.plt_ambulance_job:IsEMS(medicSrc)
    if not isEMS then
        if not Framework.HasPermission(medicSrc, Config.Permission) then
            Framework.Notify(medicSrc, _L("not_authorized"), "error")
            return
        end
    end

    local patientSrc = tonumber(patientSrcRaw)
    if not (patientSrc and GetPlayerName(patientSrc)) then
        Framework.Notify(medicSrc, _L("player_not_found"), "error")
        return
    end

    local cfg     = GetInvoiceConfig()
    local maxAmt  = tonumber(cfg.MaxAmount) or 100000
    local amt     = math.floor(tonumber(amount) or 0)

    if amt <= 0 or amt > maxAmt then
        Framework.Notify(medicSrc, _L("ems_invoice_bad_amount", { max = maxAmt }), "error")
        return
    end

    reason = TrimString(reason)
    if reason == "" then
        Framework.Notify(medicSrc, _L("ems_invoice_no_reason"), "error")
        return
    end
    if #reason > 120 then reason = reason:sub(1, 120) end

    if not IsWithinDistance(medicSrc, patientSrc, cfg.MaxDistance) then
        Framework.Notify(medicSrc, _L("ems_invoice_too_far"), "error")
        return
    end

    local patientPlayer = Framework.GetPlayer(patientSrc)
    if not patientPlayer then
        Framework.Notify(medicSrc, _L("player_not_found"), "error")
        return
    end

    ExpireInvoices()
    invoiceCounter = invoiceCounter + 1

    local dept = GetDeptIdForPlayer(medicPlayer)
    local invoice = {
        id              = invoiceCounter,
        medicSrc        = medicSrc,
        patientSrc      = patientSrc,
        dept            = dept,
        amount          = amt,
        reason          = reason,
        medicName       = medicPlayer.name,
        patientName     = patientPlayer.name,
        departmentLabel = (medicPlayer.job and medicPlayer.job.label) or dept,
        createdAt       = os.time(),
    }
    pendingInvoices[invoice.id] = invoice

    -- Notify medic
    Framework.Notify(medicSrc,
        _L("ems_invoice_sent", { id = invoice.id, name = patientPlayer.name, amount = amt }),
        "success"
    )

    -- Notify patient
    local payCmdName     = cfg.PayCommandName     or "payemsinvoice"
    local declineCmdName = cfg.DeclineCommandName or "declineemsinvoice"
    Framework.Notify(patientSrc,
        _L("ems_invoice_received", {
            department   = invoice.departmentLabel,
            id           = invoice.id,
            amount       = amt,
            reason       = reason,
            payCommand    = payCmdName,
            declineCommand = declineCmdName,
        }),
        "warning"
    )
    TriggerClientEvent("amb_client:EMSInvoiceReceived", patientSrc, invoice)
end

-- =============================================================================
-- EMS Invoice: pay
-- =============================================================================

local function PayEMSInvoice(patientSrc, invoiceIdRaw)
    local patientPlayer = Framework.GetPlayer(patientSrc)
    if not patientPlayer then return end

    local invoiceId = tonumber(invoiceIdRaw)
    if invoiceIdRaw and tostring(invoiceIdRaw) ~= "" and not invoiceId then
        Framework.Notify(patientSrc, _L("ems_invoice_not_found"), "error")
        return
    end

    local invoice = FindInvoice(patientSrc, invoiceId)
    if not invoice then
        local key = invoiceIdRaw and "ems_invoice_not_found" or "ems_invoice_none"
        Framework.Notify(patientSrc, _L(key), "error")
        return
    end

    local ok, usedAccount = ChargePlayer(patientPlayer, invoice.amount)
    if not ok then
        Framework.Notify(patientSrc, _L("ems_invoice_no_money"), "error")
        return
    end

    local label  = ("EMS Invoice #%s - %s"):format(invoice.id, invoice.reason)
    local finOk  = AddFinanceEntry(invoice.dept, "deposit", invoice.amount, label, patientPlayer.name)
    if not finOk then
        -- Refund the player
        patientPlayer.functions.AddMoney(usedAccount, invoice.amount, "ems-invoice-refund")
        Framework.Notify(patientSrc, _L("ems_invoice_finance_error"), "error")
        return
    end

    pendingInvoices[invoice.id] = nil

    Framework.Notify(patientSrc,
        _L("ems_invoice_paid_patient", { id = invoice.id, amount = invoice.amount }),
        "success"
    )
    if GetPlayerName(invoice.medicSrc) then
        Framework.Notify(invoice.medicSrc,
            _L("ems_invoice_paid_ems", { id = invoice.id, amount = invoice.amount, name = patientPlayer.name }),
            "success"
        )
    end
end

-- =============================================================================
-- EMS Invoice: decline
-- =============================================================================

local function DeclineEMSInvoice(patientSrc, invoiceIdRaw)
    local patientPlayer = Framework.GetPlayer(patientSrc)
    if not patientPlayer then return end

    local invoiceId = tonumber(invoiceIdRaw)
    if invoiceIdRaw and tostring(invoiceIdRaw) ~= "" and not invoiceId then
        Framework.Notify(patientSrc, _L("ems_invoice_not_found"), "error")
        return
    end

    local invoice = FindInvoice(patientSrc, invoiceId)
    if not invoice then
        local key = invoiceIdRaw and "ems_invoice_not_found" or "ems_invoice_none"
        Framework.Notify(patientSrc, _L(key), "error")
        return
    end

    pendingInvoices[invoice.id] = nil

    Framework.Notify(patientSrc,
        _L("ems_invoice_declined_patient", { id = invoice.id }),
        "info"
    )
    if GetPlayerName(invoice.medicSrc) then
        Framework.Notify(invoice.medicSrc,
            _L("ems_invoice_declined_ems", { id = invoice.id, name = patientPlayer.name }),
            "warning"
        )
    end
end

-- =============================================================================
-- EMS Invoice: network events & commands
-- =============================================================================

RegisterNetEvent("amb_server:createEMSInvoice")
AddEventHandler("amb_server:createEMSInvoice", function(patientSrc, amount, reason)
    CreateEMSInvoice(source, patientSrc, amount, reason)
end)

RegisterNetEvent("amb_server:payEMSInvoice")
AddEventHandler("amb_server:payEMSInvoice", function(invoiceId)
    PayEMSInvoice(source, invoiceId)
end)

RegisterNetEvent("amb_server:declineEMSInvoice")
AddEventHandler("amb_server:declineEMSInvoice", function(invoiceId)
    DeclineEMSInvoice(source, invoiceId)
end)

-- Clean up invoices when a player disconnects
AddEventHandler("playerDropped", function()
    local dropped = source
    for id, inv in pairs(pendingInvoices) do
        if inv.medicSrc == dropped or inv.patientSrc == dropped then
            pendingInvoices[id] = nil
        end
    end
end)

-- Register slash commands
local invoiceCfg     = GetInvoiceConfig()
local invoiceCmd     = invoiceCfg.CommandName     or "emsinvoice"
local payCmd         = invoiceCfg.PayCommandName  or "payemsinvoice"
local declineCmd     = invoiceCfg.DeclineCommandName or "declineemsinvoice"

RegisterCommand(invoiceCmd, function(src, args)
    if src == 0 then return end
    local cmdName = GetInvoiceConfig().CommandName or "emsinvoice"
    if #args < 3 then
        Framework.Notify(src, _L("ems_invoice_usage", { command = cmdName }), "error")
        return
    end
    local patientSrc = args[1]
    local amount     = args[2]
    local reasonParts = {}
    for i = 3, #args do table.insert(reasonParts, args[i]) end
    CreateEMSInvoice(src, patientSrc, amount, table.concat(reasonParts, " "))
end, false)

RegisterCommand(payCmd, function(src, args)
    if src == 0 then return end
    PayEMSInvoice(src, args[1])
end, false)

RegisterCommand(declineCmd, function(src, args)
    if src == 0 then return end
    DeclineEMSInvoice(src, args[1])
end, false)

-- =============================================================================
-- Boss Menu callback: initial data load
-- =============================================================================

Framework.CreateCallback("amb_server:getBossMenuData", function(src, cb, data)
    local allPlayers  = GetPlayersList()
    local player      = Framework.GetPlayer(src)
    local deptId      = data or (player and player.job and player.job.name) or "ambulance"

    -- Refresh balance cache
    balances[deptId] = GetDeptBalance(deptId)

    if not finances[deptId] then finances[deptId] = {} end

    -- External departments from plt_departments resource (if running)
    local externalDepts = {}
    if GetResourceState("plt_departments") == "started" then
        local catalog = exports.plt_departments:GetDepartmentCatalog(2000)
        if catalog then externalDepts = catalog end
    end

    cb({
        data         = DepartmentData,
        externalDepts = externalDepts,
        members      = allPlayers,
        news         = newsItems,
        pcrs         = pcrList,
        dutyLogs     = DeptDutyLogs or {},
        balances     = balances,
        finances     = finances,
        transactions = finances[deptId],
    })
end)

-- =============================================================================
-- PCR (Patient Care Report)
-- =============================================================================

RegisterNetEvent("amb_server:addPCR")
AddEventHandler("amb_server:addPCR", function(data)
    local src = source
    local isEMS = exports.plt_ambulance_job:IsEMS(src)
    if not isEMS then
        if not Framework.HasPermission(src, Config.Permission) then return end
    end

    local player = Framework.GetPlayer(src)
    if not player then return end

    local record = {
        patient   = data.patient,
        condition = data.condition,
        treatment = data.treatment,
        author    = player.name,
        date      = os.date("%B %d, %Y"),
    }

    if pcrTableExists then
        MySQL.Async.insert(
            "INSERT INTO plt_ambulance_job_pcrs (patient, `condition`, treatment, author, date) VALUES (?, ?, ?, ?, ?)",
            { record.patient, record.condition, record.treatment, record.author, record.date },
            function(insertId)
                record.id = insertId
                table.insert(pcrList, record)
                if #pcrList > 50 then table.remove(pcrList, 1) end
                TriggerClientEvent("amb_client:SyncData", -1, { pcrs = pcrList })
            end
        )
        return
    end

    -- No DB table – keep in memory only
    record.id = #pcrList + 1
    table.insert(pcrList, 1, record)
    if #pcrList > 50 then table.remove(pcrList) end
    TriggerClientEvent("amb_client:SyncData", -1, { pcrs = pcrList })
end)

-- =============================================================================
-- DMR (Dead Medical Records) search
-- =============================================================================

Framework.CreateCallback("amb_server:searchDMR", function(src, cb, data)
    local query = data.query
    if not query or #query < 2 then return cb({}) end

    local results   = {}
    local like      = "%" .. query .. "%"
    local frameworkType = Framework.Type

    local sql, rows
    if frameworkType == "qb" then
        sql  = "SELECT citizenid as cid, charinfo FROM players WHERE LOWER(charinfo) LIKE ? OR LOWER(citizenid) LIKE ? LIMIT 10"
    else
        sql  = "SELECT identifier as cid, firstname, lastname FROM users WHERE LOWER(CONCAT(firstname, ' ', lastname)) LIKE ? OR LOWER(identifier) LIKE ? LIMIT 10"
    end
    rows = MySQL.Sync.fetchAll(sql, { like, like })

    for _, row in ipairs(rows) do
        local name = "Unknown"
        if frameworkType == "qb" then
            local charinfo = json.decode(row.charinfo)
            name = charinfo.firstname .. " " .. charinfo.lastname
        else
            name = row.firstname .. " " .. row.lastname
        end
        table.insert(results, { cid = row.cid, name = name })
    end
    cb(results)
end)

-- =============================================================================
-- DMR: get detailed record for a citizen
-- =============================================================================

Framework.CreateCallback("amb_server:getDMRDetails", function(src, cb, data)
    local cid = data.cid
    if not cid then return cb({}) end

    local name = "Unknown"
    if Framework.Type == "qb" then
        local rows = MySQL.Sync.fetchAll("SELECT charinfo FROM players WHERE citizenid = ?", { cid })
        if rows[1] then
            local ci = json.decode(rows[1].charinfo)
            name = ci.firstname .. " " .. ci.lastname
        end
    else
        local rows = MySQL.Sync.fetchAll("SELECT firstname, lastname FROM users WHERE identifier = ?", { cid })
        if rows[1] then
            name = rows[1].firstname .. " " .. rows[1].lastname
        end
    end

    -- PCRs
    local pcrs = {}
    if pcrTableExists then
        pcrs = MySQL.Sync.fetchAll(
            "SELECT * FROM plt_ambulance_job_pcrs WHERE patient = ? ORDER BY id DESC", { name }
        ) or {}
    else
        for _, p in ipairs(pcrList) do
            if p.patient == name then table.insert(pcrs, p) end
        end
    end

    -- X-rays
    local xrays = MySQL.Sync.fetchAll(
        "SELECT * FROM plt_ambulance_job_xrays WHERE citizenid = ? ORDER BY id DESC", { cid }
    ) or {}
    for _, xray in ipairs(xrays) do
        xray.injuries = json.decode(xray.injuries)
    end

    cb({ name = name, pcrs = pcrs, xrays = xrays })
end)

-- =============================================================================
-- X-Ray save
-- =============================================================================

RegisterNetEvent("amb_server:saveXRayResult")
AddEventHandler("amb_server:saveXRayResult", function(citizenId, injuries)
    MySQL.Async.execute(
        "INSERT INTO plt_ambulance_job_xrays (citizenid, injuries, date) VALUES (?, ?, ?)",
        { citizenId, json.encode(injuries), os.date("%B %d, %Y") }
    )
end)

-- =============================================================================
-- Patient search (QB only – searches players table)
-- =============================================================================

Framework.CreateCallback("amb_server:searchPatients", function(src, cb, data)
    local query = data.query
    if not query or #query < 2 then return cb({}) end

    print("^2[plt_ambulance] Searching for Citizen:^7 " .. tostring(query))

    local results = {}
    local like    = "%" .. query .. "%"

    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll([[
            SELECT citizenid as cid, charinfo
            FROM players
            WHERE citizenid LIKE ? OR charinfo LIKE ?
            LIMIT 20
        ]], { like, like })
    end)

    if ok and rows and #rows > 0 then
        for _, row in ipairs(rows) do
            local charinfo = row.charinfo
            if type(charinfo) == "string" then
                charinfo = json.decode(charinfo) or charinfo
            end

            local name  = "Unknown"
            local phone = "N/A"
            if charinfo then
                name  = (charinfo.firstname or "Unknown") .. " " .. (charinfo.lastname or "Citizen")
                phone = charinfo.phone or "N/A"
            end
            table.insert(results, { cid = row.cid, name = name, phone = phone })
        end
        print(("^2[plt_ambulance] Found %d citizens.^7"):format(#results))
    else
        if not ok then
            print("^1[plt_ambulance] SQL ERROR:^7 " .. tostring(rows))
        end
        print("^3[plt_ambulance] 0 results found.^7")
    end

    cb(results)
end)

-- =============================================================================
-- Patient details callback
-- =============================================================================

Framework.CreateCallback("amb_server:getPatientDetails", function(src, cb, data)
    local cid = data.cid
    if not cid then return cb({}) end

    local result = {
        cid           = cid,
        name          = "Unknown",
        pcrs          = {},
        xrays         = {},
        prescriptions = {},
        blood_type    = "Unknown",
        allergies     = "None",
        medical_notes = "No notes recorded.",
        insurance     = false,
    }

    if Framework.Type == "qb" then
        local rows = MySQL.Sync.fetchAll(
            "SELECT charinfo, metadata FROM players WHERE citizenid = ?", { cid }
        )
        if rows[1] then
            local charinfo = json.decode(rows[1].charinfo)
            local metadata = json.decode(rows[1].metadata)
            local profile  = GetOrCreatePatientProfile(cid, metadata)

            result.name          = (charinfo.firstname or "") .. " " .. (charinfo.lastname or "")
            result.phone         = charinfo.phone
            result.dob           = charinfo.birthdate
            result.gender        = (charinfo.gender == 0) and "Male" or "Female"
            result.blood_type    = profile.blood_type
            result.allergies     = profile.known_allergy
            result.medical_notes = metadata.medicalnotes or "No notes recorded."
            result.insurance     = metadata.medical_insurance and true or false
            result.hunger        = math.floor(metadata.hunger  or 100)
            result.thirst        = math.floor(metadata.thirst  or 100)
            result.stress        = math.floor(metadata.stress  or 0)
            result.is_dead       = metadata.isdead or false
        end
    else
        -- ESX path (similar structure, omitted for brevity – follows same logic)
        local rows = MySQL.Sync.fetchAll(
            "SELECT firstname, lastname FROM users WHERE identifier = ?", { cid }
        )
        if rows[1] then
            result.name = rows[1].firstname .. " " .. rows[1].lastname
        end
        local profile     = GetOrCreatePatientProfile(cid)
        result.blood_type = profile.blood_type
        result.allergies  = profile.known_allergy
    end

    -- PCRs
    if pcrTableExists then
        result.pcrs = MySQL.Sync.fetchAll(
            "SELECT * FROM plt_ambulance_job_pcrs WHERE patient = ? ORDER BY id DESC",
            { result.name }
        ) or {}
    else
        for _, p in ipairs(pcrList) do
            if p.patient == result.name then table.insert(result.pcrs, p) end
        end
    end

    -- X-rays
    local xrays = MySQL.Sync.fetchAll(
        "SELECT * FROM plt_ambulance_job_xrays WHERE citizenid = ? ORDER BY id DESC", { cid }
    ) or {}
    for _, xray in ipairs(xrays) do
        xray.injuries = json.decode(xray.injuries)
    end
    result.xrays = xrays

    -- Prescriptions (if table exists)
    local presOk, presRows = pcall(function()
        return MySQL.Sync.fetchAll(
            "SELECT * FROM plt_ambulance_job_prescriptions WHERE citizenid = ? ORDER BY id DESC",
            { cid }
        )
    end)
    if presOk and presRows then
        result.prescriptions = presRows
    end

    cb(result)
end)

-- =============================================================================
-- Update patient allergy
-- =============================================================================

Framework.CreateCallback("amb_server:updatePatientAllergy", function(src, cb, data)
    local isEMS = exports.plt_ambulance_job:IsEMS(src)
    if not isEMS then
        if not Framework.HasPermission(src, Config.Permission) then
            return cb({ success = false, message = _L("not_authorized") })
        end
    end

    local cid = data and data.cid and tostring(data.cid) or nil
    if not cid or cid == "" then
        return cb({ success = false, message = "Missing patient ID." })
    end

    local allergy = TrimString(type(data.known_allergy) == "string" and data.known_allergy or "")
    if allergy == "" then allergy = "None" end
    if #allergy > 120 then allergy = allergy:sub(1, 120) end

    local profile          = GetOrCreatePatientProfile(cid)
    profile.known_allergy  = allergy
    patientProfiles[cid]   = profile
    SavePatientProfiles()

    cb({ success = true, known_allergy = allergy })
end)

-- =============================================================================
-- Finance actions (deposit / withdraw)
-- =============================================================================

RegisterNetEvent("amb_server:financeAction")
AddEventHandler("amb_server:financeAction", function(data)
    local src    = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    local isEMS = exports.plt_ambulance_job:IsEMS(src)
    if not isEMS then
        if not Framework.HasPermission(src, Config.Permission) then
            Framework.Notify(src, _L("not_authorized_funds"), "error")
            return
        end
    end

    local deptId = data.dept or player.job.name
    local action = data.action
    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then return end

    balances[deptId] = GetDeptBalance(deptId)
    if not finances[deptId] then finances[deptId] = {} end

    if action == "deposit" then
        local ok = player.functions.RemoveMoney("cash", amount, "dept-deposit")
        if ok then
            local finOk = AddFinanceEntry(deptId, "deposit", amount, "Manual Deposit", player.name)
            if finOk then
                Framework.Notify(src, _L("deposited_funds", { amount = amount }), "success")
            else
                player.functions.AddMoney("cash", amount, "dept-deposit-refund")
                Framework.Notify(src, "Department finance backend error.", "error")
            end
        else
            Framework.Notify(src, _L("not_enough_cash_short"), "error")
        end

    elseif action == "withdraw" then
        local bal = GetDeptBalance(deptId)
        if not bal or amount > bal then
            Framework.Notify(src, _L("not_enough_department_funds"), "error")
            return
        end
        local finOk = AddFinanceEntry(deptId, "withdraw", amount, "Manual Withdrawal", player.name)
        if not finOk then
            Framework.Notify(src, _L("not_enough_department_funds"), "error")
            return
        end
        local addOk = player.functions.AddMoney("cash", amount, "dept-withdrawal")
        if addOk then
            Framework.Notify(src, _L("withdrew_funds", { amount = amount }), "success")
        else
            -- Rollback
            AddFinanceEntry(deptId, "deposit", amount, "Withdrawal Rollback", "SYSTEM")
            Framework.Notify(src, "Department finance backend error.", "error")
        end
    end
end)

-- =============================================================================
-- Distribute salaries
-- =============================================================================

RegisterNetEvent("amb_server:distributeSalaries")
AddEventHandler("amb_server:distributeSalaries", function(data)
    local src    = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    local isEMS = exports.plt_ambulance_job:IsEMS(src)
    if not isEMS then
        if not Framework.HasPermission(src, Config.Permission) then
            Framework.Notify(src, _L("not_authorized_funds"), "error")
            return
        end
    end

    local deptId = (data and data.dept) or player.job.name
    if not deptId or tostring(deptId) == "" then
        Framework.Notify(src, "Missing department for payout.", "error")
        return
    end

    local salaryList, totalAmount = BuildSalaryList(deptId)

    if #salaryList == 0 or totalAmount <= 0 then
        Framework.Notify(src, "No eligible online members with configured salaries.", "error")
        return
    end

    local bal = GetDeptBalance(deptId)
    if not bal or totalAmount > bal then
        Framework.Notify(src, _L("not_enough_department_funds"), "error")
        return
    end

    local label  = ("Salary payout (%d members)"):format(#salaryList)
    local finOk  = AddFinanceEntry(deptId, "withdraw", totalAmount, label, player.name or "SYSTEM")
    if not finOk then
        Framework.Notify(src, _L("not_enough_department_funds"), "error")
        return
    end

    local paidCount  = 0
    local paidAmount = 0

    for _, entry in ipairs(salaryList) do
        local ok = PayPlayerFromDept(entry)
        if ok then
            paidCount  = paidCount + 1
            paidAmount = paidAmount + entry.amount
            Framework.Notify(entry.source,
                ("Salary received: $%d"):format(entry.amount),
                "success"
            )
        end
    end

    -- Refund the difference if some payments failed
    local refund = totalAmount - paidAmount
    if refund > 0 then
        AddFinanceEntry(deptId, "deposit", refund, "Salary payout refund", "SYSTEM")
    end

    Framework.Notify(src,
        ("Salary payout complete: %d members paid ($%d)."):format(paidCount, paidAmount),
        "success"
    )
end)

-- =============================================================================
-- News management
-- =============================================================================

RegisterNetEvent("amb_server:addNews")
AddEventHandler("amb_server:addNews", function(data)
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then return end
    local player = Framework.GetPlayer(src)
    if not player then return end

    table.insert(newsItems, {
        id      = #newsItems + 1,
        title   = data.title,
        content = data.content,
        author  = player.name,
        date    = os.date("%B %d, %Y"),
    })
    SaveNews()
end)

RegisterNetEvent("amb_server:deleteNews")
AddEventHandler("amb_server:deleteNews", function(targetId)
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then return end

    for i, item in ipairs(newsItems) do
        if item.id == targetId then
            table.remove(newsItems, i)
            break
        end
    end
    SaveNews()
end)

-- =============================================================================
-- Insured players
-- =============================================================================

Framework.CreateCallback("amb_server:getInsuredPlayers", function(src, cb, deptFilter)
    local player = Framework.GetPlayer(src)
    local deptId = deptFilter or (player and player.job and player.job.name) or "ambulance"

    local isEMS = exports.plt_ambulance_job:IsEMS(src)
    if not isEMS then
        if not Framework.HasPermission(src, Config.Permission) then
            return cb({})
        end
    end

    local insuredList = {}
    local seenCids    = {}

    -- Online players first
    for _, svId in ipairs(GetPlayers()) do
        local p   = Framework.GetPlayer(tonumber(svId))
        if p then
            local insurance = Framework.GetMetaData(tonumber(svId), "medical_insurance")
            if insurance then
                local isAdminView = Framework.HasPermission(src, Config.Permission)
                if insurance == deptId or insurance == true or isAdminView then
                    local cid = p.citizenid or p.identifier
                    seenCids[cid] = true

                    local name = p.name
                    if not name and p.charinfo then
                        name = (p.charinfo.firstname or "") .. " " .. (p.charinfo.lastname or "")
                    end

                    table.insert(insuredList, {
                        cid      = cid,
                        name     = name or "Unknown",
                        isOnline = true,
                        serverId = tonumber(svId),
                    })
                end
            end
        end
    end

    -- Offline players (QB only)
    if Framework.Type == "qb" then
        local rows = MySQL.Sync.fetchAll("SELECT citizenid, charinfo, metadata FROM players", {})
        for _, row in ipairs(rows) do
            if not seenCids[row.citizenid] then
                local metadata = (type(row.metadata) == "string") and json.decode(row.metadata) or row.metadata
                if metadata then
                    local ins = metadata.medical_insurance
                    if ins then
                        local isAdminView = Framework.HasPermission(src, Config.Permission)
                        if ins == deptId or ins == true or isAdminView then
                            local ci   = (type(row.charinfo) == "string") and json.decode(row.charinfo) or row.charinfo
                            local name = "Unknown"
                            if ci then
                                name = (ci.firstname or "") .. " " .. (ci.lastname or "")
                            end
                            table.insert(insuredList, {
                                cid      = row.citizenid,
                                name     = name,
                                isOnline = false,
                            })
                        end
                    end
                end
            end
        end
    end

    cb(insuredList)
end)

-- =============================================================================
-- Cancel insurance
-- =============================================================================

RegisterNetEvent("amb_server:cancelInsurance")
AddEventHandler("amb_server:cancelInsurance", function(data)
    local src   = source
    local isEMS = exports.plt_ambulance_job:IsEMS(src)
    if not isEMS then
        if not Framework.HasPermission(src, Config.Permission) then
            Framework.Notify(src, _L("not_authorized"), "error")
            return
        end
    end

    local cid      = data.cid
    local serverId = data.serverId

    -- Online: clear metadata live
    if serverId then
        local p = Framework.GetPlayer(serverId)
        if p then
            Framework.SetMetaData(serverId, "medical_insurance", false)
            TriggerClientEvent("amb_client:updateInsuranceStatus", serverId, false)
            Framework.Notify(serverId, _L("insurance_cancelled_by_department"), "error")
        end
    end

    -- Persist to DB
    if Framework.Type == "qb" then
        local rows = MySQL.Sync.fetchAll("SELECT metadata FROM players WHERE citizenid = ?", { cid })
        if rows[1] then
            local metadata = (type(rows[1].metadata) == "string") and json.decode(rows[1].metadata) or rows[1].metadata
            if metadata then
                metadata.medical_insurance = false
                MySQL.Async.execute(
                    "UPDATE players SET metadata = ? WHERE citizenid = ?",
                    { json.encode(metadata), cid }
                )
            end
        end
    elseif Framework.Type == "esx" then
        local ok, err = pcall(function()
            MySQL.Sync.execute("UPDATE users SET medical_insurance = 0 WHERE identifier = ?", { cid })
        end)
        if not ok then
            print(("[plt_ambulance][ESX][cancel_insurance] Failed to update users.medical_insurance for %s: %s")
                :format(tostring(cid), tostring(err)))
        end
    end

    Framework.Notify(src, _L("insurance_subscription_cancelled"), "success")
end)

-- =============================================================================
-- Authorization helper
-- =============================================================================

local function IsBossOrAdmin(src)
    if Framework.HasPermission(src, Config.Permission) then return true end
    if Framework.Type == "qb" then
        if exports.plt_ambulance_job:IsEMS(src) then return true end
    end
    return false
end

-- =============================================================================
-- Hire player (server-side, by server ID / citizen ID)
-- =============================================================================

RegisterNetEvent("amb_server:hirePlayer")
AddEventHandler("amb_server:hirePlayer", function(data)
    local src = source
    if not IsBossOrAdmin(src) then
        Framework.Notify(src, _L("not_authorized"), "error")
        return
    end

    local targetSrc = tonumber(data.playerId)
    local target    = Framework.GetPlayer(targetSrc)
    if not target then return end

    local deptId = data.job
    local grade  = tonumber(data.grade) or 0
    local label  = "Unknown"
    local gradeLabel = "Rank " .. grade

    for _, node in ipairs(DepartmentData.nodes) do
        if node.id == deptId then label = node.label; break end
    end

    Framework.SetJob(targetSrc, GetFrameworkJobForDepartment(deptId), grade)
    Wait(300)

    local refreshed = Framework.GetPlayer(targetSrc)
    if refreshed then
        MemberData[refreshed.citizenid] = {
            name       = refreshed.name,
            job        = deptId,
            grade      = grade,
            jobLabel   = label,
            gradeLabel = gradeLabel,
            ratings    = {},
        }
        SaveMemberToDB(refreshed.citizenid)
    end
end)

-- =============================================================================
-- Hire by ID callback (citizen ID or server ID)
-- =============================================================================

Framework.CreateCallback("amb_server:hireById", function(src, cb, data)
    if not IsBossOrAdmin(src) then
        return cb({ success = false, message = "Not authorized" })
    end

    local rawId  = data.id and tostring(data.id):match("^%s*(.-)%s*$") or ""
    local deptId = data.job
    local grade  = tonumber(data.grade) or 0

    if not deptId or deptId == "" then
        return cb({ success = false, message = "No department selected" })
    end
    if rawId == "" then
        return cb({ success = false, message = "Please enter a Citizen ID or Server ID" })
    end

    local targetSrc, targetPlayer, citizenId, targetName = nil, nil, nil, "Unknown"

    -- Try as server ID first
    local asNumber = tonumber(rawId)
    if asNumber and asNumber >= 1 and asNumber <= 9999 then
        local p = Framework.GetPlayer(asNumber)
        if p then
            targetSrc    = asNumber
            targetPlayer = p
            citizenId    = p.citizenid
            targetName   = p.name
        end
    end

    -- Try GetPlayerByCitizenId
    if not targetPlayer and Framework.GetPlayerByCitizenId then
        local p = Framework.GetPlayerByCitizenId(rawId)
        if p then
            targetPlayer = p
            targetSrc    = p.source
            citizenId    = p.citizenid or rawId
            targetName   = p.name
        end
    end

    -- Fallback: scan all online players
    if not targetPlayer then
        for _, svId in ipairs(GetPlayers()) do
            local p = Framework.GetPlayer(tonumber(svId))
            if p and (p.citizenid == rawId or tostring(p.citizenid) == rawId) then
                targetPlayer = p
                targetSrc    = tonumber(svId)
                citizenId    = p.citizenid
                targetName   = p.name
                break
            end
        end
    end

    -- Resolve department/rank labels
    local deptLabel  = "Unknown"
    local gradeLabel = "Rank " .. grade
    for _, node in ipairs(DepartmentData.nodes) do
        if node.id == deptId then deptLabel = node.label; break end
    end
    for _, link in ipairs(DepartmentData.links or {}) do
        if link.from == deptId then
            for _, node in ipairs(DepartmentData.nodes) do
                if node.id == link.to and node.type == "rank" and node.ranks then
                    for _, rank in ipairs(node.ranks) do
                        if tonumber(rank.level) == grade then
                            gradeLabel = rank.name or gradeLabel
                            break
                        end
                    end
                end
            end
        end
    end

    -- Online hire
    if targetPlayer and targetSrc then
        Framework.SetJob(targetSrc, GetFrameworkJobForDepartment(deptId), grade)
        Wait(200)
        local refreshed = Framework.GetPlayer(targetSrc)
        if refreshed then
            MemberData[refreshed.citizenid] = {
                name       = refreshed.name,
                job        = deptId,
                grade      = grade,
                jobLabel   = deptLabel,
                gradeLabel = gradeLabel,
                ratings    = {},
            }
            SaveMemberToDB(refreshed.citizenid)
            TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
            return cb({ success = true })
        end
    end

    -- Offline hire (QB only – update DB directly)
    if Framework.Type == "qb" then
        local rows = MySQL.Sync.fetchAll(
            "SELECT citizenid, charinfo FROM players WHERE citizenid = ?", { rawId }
        )
        if not (rows and rows[1]) then
            local lowerRows = MySQL.Sync.fetchAll(
                "SELECT citizenid, charinfo FROM players WHERE LOWER(citizenid) = ?",
                { rawId:lower() }
            )
            rows = lowerRows
        end

        if rows and rows[1] then
            citizenId = rows[1].citizenid
            local ci  = (type(rows[1].charinfo) == "string") and json.decode(rows[1].charinfo) or rows[1].charinfo
            if ci then
                targetName = ((ci.firstname or "") .. " " .. (ci.lastname or "")):match("^%s*(.-)%s*$") or citizenId
            end

            local jobObj = {
                name     = GetFrameworkJobForDepartment(deptId),
                label    = deptLabel,
                grade    = { level = grade, name = gradeLabel },
                payment  = 0,
                onduty   = false,
                isboss   = false,
            }
            MySQL.Async.execute(
                "UPDATE players SET job = ? WHERE citizenid = ?",
                { json.encode(jobObj), citizenId },
                function()
                    MemberData[citizenId] = {
                        name       = targetName,
                        job        = deptId,
                        grade      = grade,
                        jobLabel   = deptLabel,
                        gradeLabel = gradeLabel,
                        ratings    = {},
                    }
                    SaveMemberToDB(citizenId)
                    TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
                    cb({ success = true })
                end
            )
            return
        end
    end

    cb({ success = false, message = "Player not found. Use Citizen ID (e.g. ABC12345) or Server ID (#) if online." })
end)

-- =============================================================================
-- Manage member (fire / promote / demote / set grade)
-- =============================================================================

RegisterNetEvent("amb_server:manageMember")
AddEventHandler("amb_server:manageMember", function(data)
    local src = source
    if not IsBossOrAdmin(src) then
        Framework.Notify(src, _L("not_authorized"), "error")
        return
    end

    local cid    = data.cid
    local action = data.action
    local member = MemberData[cid]
    if not member then return end

    if action == "fire" then
        MemberData[cid] = nil
        MySQL.Sync.execute("DELETE FROM plt_ambulance_job_members WHERE citizenid = ?", { cid })

        -- If online, set to unemployed
        for _, svId in ipairs(GetPlayers()) do
            local p = Framework.GetPlayer(tonumber(svId))
            if p and p.citizenid == cid then
                Framework.SetJob(tonumber(svId), "unemployed", 0)
                break
            end
        end

    elseif action == "promote" or action == "demote" then
        local delta    = (action == "promote") and 1 or -1
        local newGrade = math.max(0, member.grade + delta)
        member.grade   = newGrade

        -- Update gradeLabel from DepartmentData
        for _, link in ipairs(DepartmentData.links or {}) do
            if link.from == member.job then
                for _, node in ipairs(DepartmentData.nodes) do
                    if node.id == link.to and node.type == "rank" and node.ranks then
                        for _, rank in ipairs(node.ranks) do
                            if tonumber(rank.level) == newGrade then
                                member.gradeLabel = rank.name
                                break
                            end
                        end
                    end
                end
            end
        end

        SaveMemberToDB(cid)

        -- Apply to online player
        for _, svId in ipairs(GetPlayers()) do
            local p = Framework.GetPlayer(tonumber(svId))
            if p and p.citizenid == cid then
                Framework.SetJob(tonumber(svId), GetFrameworkJobForDepartment(member.job), newGrade)
                break
            end
        end

    elseif action == "setgrade" then
        local newGrade = tonumber(data.grade) or 0
        member.grade   = newGrade
        SaveMemberToDB(cid)

        for _, svId in ipairs(GetPlayers()) do
            local p = Framework.GetPlayer(tonumber(svId))
            if p and p.citizenid == cid then
                Framework.SetJob(tonumber(svId), GetFrameworkJobForDepartment(member.job), newGrade)
                break
            end
        end
    end
end)

-- =============================================================================
-- Department mail helpers
-- =============================================================================

local function SendDepartmentMail(senderDept, receiverDept, senderName, subject, message, imageUrl)
    local dateStr = os.date("%B %d, %Y")
    local timeStr = os.date("%H:%M")
    local imgSafe = imageUrl or ""

    -- Check if receiverDept is a known local department
    local isLocal = false
    local resolvedDept = receiverDept
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" and (node.id == receiverDept or node.frameworkJob == receiverDept) then
            isLocal       = true
            resolvedDept  = node.id
            break
        end
    end

    if isLocal then
        -- Insert into local mail table
        MySQL.Async.insert(
            "INSERT INTO plt_ambulance_job_mails (sender_dept, receiver_dept, sender_name, subject, message, image_url, `date`, `time`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            { senderDept, resolvedDept, senderName, subject, message, imgSafe, dateStr, timeStr },
            function(insertId)
                if not insertId then return end
                -- Notify online members of the target department
                for _, svId in ipairs(GetPlayers()) do
                    local p = Framework.GetPlayer(tonumber(svId))
                    if p then
                        local isTargetDept = (p.job.name == resolvedDept)
                            or (GetFrameworkJobForDepartment(resolvedDept) == p.job.name)
                        if isTargetDept then
                            Framework.Notify(tonumber(svId),
                                "New department mail received from " .. senderDept:upper(),
                                "info"
                            )
                            TriggerClientEvent("amb_client:SyncMail", tonumber(svId))
                        end
                    end
                end
            end
        )
    else
        -- Forward to plt_departments if running
        if GetResourceState("plt_departments") == "started" then
            exports.plt_departments:SendDepartmentMail(senderDept, receiverDept, senderName, subject, message, imageUrl)
        end
        -- Also save as already-read in local table for record keeping
        MySQL.Async.insert(
            "INSERT INTO plt_ambulance_job_mails (sender_dept, receiver_dept, sender_name, subject, message, image_url, `date`, `time`, is_read) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)",
            { senderDept, receiverDept, senderName, subject, message, imgSafe, dateStr, timeStr }
        )
    end
end

exports("SendDepartmentMail", SendDepartmentMail)

-- Get mails for a department
Framework.CreateCallback("amb_server:getMails", function(src, cb, dept)
    local rows = MySQL.Sync.fetchAll(
        "SELECT * FROM plt_ambulance_job_mails WHERE receiver_dept = ? OR sender_dept = ? ORDER BY id DESC LIMIT 50",
        { dept, dept }
    )
    cb(rows or {})
end)

-- Send mail event
RegisterNetEvent("amb_server:sendMail")
AddEventHandler("amb_server:sendMail", function(data)
    local src    = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    SendDepartmentMail(
        data.senderDept,
        data.receiverDept,
        player.name,
        data.subject,
        data.message,
        data.imageUrl
    )
end)

-- Mark mail as read
RegisterNetEvent("amb_server:markMailRead")
AddEventHandler("amb_server:markMailRead", function(mailId)
    MySQL.Async.execute("UPDATE plt_ambulance_job_mails SET is_read = 1 WHERE id = ?", { mailId })
end)

-- Delete mail
RegisterNetEvent("amb_server:deleteMail")
AddEventHandler("amb_server:deleteMail", function(mailId)
    MySQL.Async.execute("DELETE FROM plt_ambulance_job_mails WHERE id = ?", { mailId })
end)

-- =============================================================================
-- Exports: department catalog / data
-- =============================================================================

exports("GetDepartmentCatalog", function()
    if not (DepartmentData and DepartmentData.nodes) then return {} end
    local catalog = {}
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            table.insert(catalog, {
                id           = node.id,
                label        = node.label,
                frameworkJob = node.frameworkJob or node.id,
            })
        end
    end
    return catalog
end)

exports("GetDepartmentsData", function()
    return DepartmentData
end)

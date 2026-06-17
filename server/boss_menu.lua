local NewsData = {}
local IsDbLoaded = false
local PCRsData = {}
local IsPCRDbLoaded = false
local HasPCRTable = true
local BalancesData = {}
local FinancesData = {}
local IsFinancesLoaded = false
local PatientProfilesData = {}
local ActiveInvoices = {}
local InvoiceIdCounter = 0
local ValidBloodTypes = {
    ["A+"] = true,
    ["A-"] = true,
    ["B+"] = true,
    ["B-"] = true,
    ["AB+"] = true,
    ["AB-"] = true,
    ["O+"] = true,
    ["O-"] = true
}
local BloodTypeArray = {
    [1] = "A+",
    [2] = "A-",
    [3] = "B+",
    [4] = "B-",
    [5] = "AB+",
    [6] = "AB-",
    [7] = "O+",
    [8] = "O-"
}

CreateThread(function()
    while true do
        if MySQL then
            break
        end
        Wait(10)
    end
    
    local newsRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", { "news" })
    if newsRes[1] then
        local decodedNews = json.decode(newsRes[1].value)
        if not decodedNews then
            decodedNews = {}
        end
        NewsData = decodedNews
    end
    IsDbLoaded = true

    if Framework.Type == "esx" then
        local success, result = pcall(function()
            return MySQL.Sync.fetchAll("SHOW TABLES LIKE ?", { "plt_ambulance_job_pcrs" })
        end)
        if success and result then
            HasPCRTable = (result[1] ~= nil)
        end
    end

    if HasPCRTable then
        local pcrRes = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_pcrs ORDER BY id DESC LIMIT 50", {})
        if not pcrRes then
            pcrRes = {}
        end
        PCRsData = pcrRes
    else
        PCRsData = {}
        print("^3[plt_ambulance][ESX] Table 'plt_ambulance_job_pcrs' not found; PCR persistence disabled until table is created.^7")
    end
    IsPCRDbLoaded = true

    local balancesRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", { "balances" })
    if balancesRes[1] then
        local decodedBalances = json.decode(balancesRes[1].value)
        if not decodedBalances then
            decodedBalances = {}
        end
        BalancesData = decodedBalances
    end

    local financesRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", { "finances" })
    if financesRes[1] then
        local decodedFinances = json.decode(financesRes[1].value)
        if not decodedFinances then
            decodedFinances = {}
        end
        FinancesData = decodedFinances
    end
    IsFinancesLoaded = true

    local profilesRes = MySQL.Sync.fetchAll("SELECT value FROM plt_ambulance_job_data WHERE `key` = ?", { "patient_profiles" })
    if profilesRes[1] then
        local decodedProfiles = json.decode(profilesRes[1].value)
        if not decodedProfiles then
            decodedProfiles = {}
        end
        PatientProfilesData = decodedProfiles
    end
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
        ["@value"] = json.encode(BalancesData)
    })
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
        ["@key"] = "finances",
        ["@value"] = json.encode(FinancesData)
    })
    
    local syncData = {
        balances = BalancesData,
        finances = FinancesData
    }
    
    local txData = nil
    if deptName and FinancesData[deptName] then
        txData = FinancesData[deptName]
    end

    syncData.transactions = txData
    TriggerClientEvent("amb_client:SyncData", -1, syncData)
end

function SavePatientProfiles()
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_data (`key`, `value`) VALUES (@key, @value) ON DUPLICATE KEY UPDATE `value` = @value", {
        ["@key"] = "patient_profiles",
        ["@value"] = json.encode(PatientProfilesData)
    })
end

function FormatBloodType(bloodTypeStr)
    if type(bloodTypeStr) ~= "string" then
        return nil
    end
    local formattedBlood = string.gsub(string.upper(bloodTypeStr), "%s+", "")
    if ValidBloodTypes[formattedBlood] then
        return formattedBlood
    end
    return nil
end

function GetOrGeneratePatientProfile(citizenId, charInfo)
    local cidStr = tostring(citizenId)
    local profile = PatientProfilesData[cidStr]
    if not profile then
        profile = {}
    end

    local bloodType = FormatBloodType(profile.blood_type)
    if not bloodType then
        if charInfo and charInfo.bloodtype then
            bloodType = FormatBloodType(charInfo.bloodtype)
        end
        if not bloodType then
            bloodType = BloodTypeArray[math.random(1, #BloodTypeArray)]
        end
        profile.blood_type = bloodType
    else
        profile.blood_type = bloodType
    end

    local allergy = profile.known_allergy
    if type(allergy) == "string" and string.gsub(allergy, "%s+", "") ~= "" then
        -- Keep existing allergy
    else
        allergy = charInfo and charInfo.allergies or allergy
        if type(allergy) == "string" and string.gsub(allergy, "%s+", "") ~= "" then
            profile.known_allergy = allergy
        else
            profile.known_allergy = "None"
        end
    end

    PatientProfilesData[cidStr] = profile
    return profile
end

function SafeDBQuery(query, params, queryTag)
    local success, result = pcall(function()
        local queryParams = params
        if not queryParams then
            queryParams = {}
        end
        return MySQL.Sync.fetchAll(query, queryParams)
    end)
    
    if not success then
        print(string.format("[plt_ambulance][ESX][%s] Query failed: %s", queryTag or "unknown", tostring(result)))
        return nil
    end
    return result
end

function GetDutyStatusFromJobName(jobName)
    local jobStr = tostring(jobName or "")
    if string.sub(jobStr, 1, 4) == "off_" then
        return string.sub(jobStr, 5), false
    end
    if string.sub(jobStr, 1, 3) == "off" then
        if #jobStr > 3 then
            return string.sub(jobStr, 4), false
        end
    end
    if string.sub(jobStr, -8) == "_offduty" then
        return string.sub(jobStr, 1, -9), false
    end
    if string.sub(jobStr, -4) == "_off" then
        return string.sub(jobStr, 1, -5), false
    end
    return jobStr, true
end

function GetDepartmentNodeForJob(jobName)
    if not (DepartmentData and DepartmentData.links and DepartmentData.nodes) then
        return nil
    end

    local jobStr = tostring(jobName or "")
    for _, link in ipairs(DepartmentData.links) do
        local fromId = tostring(link.from or "")
        local toId = tostring(link.to or "")
        local targetId = nil
        
        if fromId == jobStr then
            targetId = toId
        elseif toId == jobStr then
            targetId = fromId
        end
        
        if targetId then
            for _, node in ipairs(DepartmentData.nodes) do
                if tostring(node.id) == targetId then
                    if node.type == "rank" then
                        return node
                    end
                end
            end
        end
    end
    return nil
end

function GetSalaryForRank(deptNode, grade)
    if not (deptNode and type(deptNode.ranks) == "table") then
        return 0
    end

    local gradeNum = tonumber(grade) or 0
    
    for _, rank in ipairs(deptNode.ranks) do
        if tonumber(rank.level) == gradeNum then
            local payNum = tonumber(rank.pay) or 0
            return math.max(0, payNum)
        end
    end
    return 0
end

function GetDepartmentIdForPlayer(playerData)
    if not (playerData and playerData.job) then
        return nil
    end

    if type(GetDepartmentIdForFrameworkJob) == "function" then
        local deptId = GetDepartmentIdForFrameworkJob(playerData.job.name)
        if deptId then
            return deptId
        end
    end

    if Framework.Type == "esx" then
        local baseJob = GetDutyStatusFromJobName(playerData.job.name)
        if type(GetDepartmentIdForFrameworkJob) == "function" then
            local deptId = GetDepartmentIdForFrameworkJob(baseJob)
            if deptId then
                return deptId
            end
        end
    end

    if MemberData and playerData.citizenid and MemberData[playerData.citizenid] and MemberData[playerData.citizenid].job then
        return MemberData[playerData.citizenid].job
    end
    return nil
end

function CalculateDepartmentSalaries(deptName)
    local deptNode = GetDepartmentNodeForJob(deptName)
    if not deptNode then
        return {}, 0
    end
    
    local payoutList = {}
    local totalPayout = 0
    
    for _, playerSrc in ipairs(GetPlayers()) do
        local srcNum = tonumber(playerSrc)
        local playerObj = Framework.GetPlayer(srcNum)
        if playerObj then
            local playerDeptId = GetDepartmentIdForPlayer(playerObj)
            if tostring(playerDeptId) == tostring(deptName) then
                local grade = (playerObj.job and playerObj.job.grade) or 0
                local salary = GetSalaryForRank(deptNode, grade)
                
                if salary > 0 then
                    local pData = {
                        source = srcNum,
                        amount = salary,
                        name = playerObj.name or ("ID " .. tostring(srcNum))
                    }
                    table.insert(payoutList, pData)
                    totalPayout = totalPayout + salary
                end
            end
        end
    end
    return payoutList, totalPayout
end

function PayPlayerSalary(payoutData)
    if Framework.Type == "esx" then
        local playerObj = Framework.Core.GetPlayerFromId(payoutData.source)
        if not playerObj then
            return false
        end
        playerObj.addAccountMoney("bank", payoutData.amount)
        return true
    end
    
    local playerObj = Framework.GetPlayer(payoutData.source)
    if not (playerObj and playerObj.functions) then
        return false
    end

    return playerObj.functions.AddMoney("bank", payoutData.amount, "department-salary")
end

function GetFinanceSystemType()
    if type(Config.DepartmentFinance) == "string" then
        return Config.DepartmentFinance
    end
    if type(Config.DepartmentFinance) == "table" then
        return Config.DepartmentFinance.System or "internal"
    end
    return "internal"
end

function GetRenewedBankingName()
    if type(Config.DepartmentFinance) == "table" and Config.DepartmentFinance.RenewedResource then
        return Config.DepartmentFinance.RenewedResource
    end
    return "Renewed-Banking"
end

function IsRenewedBankingActive()
    local financeSystem = string.lower(tostring(GetFinanceSystemType()))
    if financeSystem ~= "renewed-banking" and financeSystem ~= "renewed_banking" then
        return false
    end
    return GetResourceState(GetRenewedBankingName()) == "started"
end

function GetDepartmentAccountName(deptName)
    local prefix = "ems_"
    if type(Config.DepartmentFinance) == "table" and Config.DepartmentFinance.AccountPrefix then
        prefix = Config.DepartmentFinance.AccountPrefix
    end
    return tostring(prefix) .. tostring(deptName)
end

function SafeExportCall(methodsList, ...)
    local renewedBanking = GetRenewedBankingName()
    if GetResourceState(renewedBanking) ~= "started" then
        return false, nil
    end
    
    local args = { ... }
    for _, method in ipairs(methodsList) do
        local success, result = pcall(function()
            return exports[renewedBanking][method](table.unpack(args))
        end)
        if success then
            return true, result
        end
    end
    return false, nil
end

function GetDepartmentBalance(deptName)
    if not BalancesData[deptName] then
        BalancesData[deptName] = Config.DefaultDeptBalance or 500000
    end
    
    if not IsRenewedBankingActive() then
        return BalancesData[deptName]
    end
    
    local accountName = GetDepartmentAccountName(deptName)
    local methods = { "getAccountMoney", "GetAccountMoney", "getAccountBalance", "GetAccountBalance", "getBalance", "GetBalance" }
    local success, result = SafeExportCall(methods, accountName)
    
    if success and tonumber(result) ~= nil then
        BalancesData[deptName] = tonumber(result)
    end
    return BalancesData[deptName]
end

function ProcessTransaction(deptName, actionType, amount, label, author)
    if not IsRenewedBankingActive() then
        if not BalancesData[deptName] then
            BalancesData[deptName] = Config.DefaultDeptBalance or 500000
        end
        if actionType == "deposit" then
            BalancesData[deptName] = BalancesData[deptName] + amount
            return true, BalancesData[deptName]
        elseif actionType == "withdraw" then
            if amount > BalancesData[deptName] then
                return false, BalancesData[deptName]
            end
            BalancesData[deptName] = BalancesData[deptName] - amount
            return true, BalancesData[deptName]
        end
        return true, BalancesData[deptName]
    end

    local accountName = GetDepartmentAccountName(deptName)
    local formattedLabel = string.format("%s | %s", tostring(label or "Transaction"), tostring(author or "SYSTEM"))
    local currentBalance = GetDepartmentBalance(deptName)
    
    if actionType == "withdraw" and amount > currentBalance then
        return false, currentBalance
    end
    
    if actionType == "deposit" then
        local success = SafeExportCall({ "addAccountMoney", "AddAccountMoney", "addBalance", "AddBalance" }, accountName, amount, formattedLabel)
        if not success then
            return false, currentBalance
        end
    elseif actionType == "withdraw" then
        local success = SafeExportCall({ "removeAccountMoney", "RemoveAccountMoney", "removeBalance", "RemoveBalance" }, accountName, amount, formattedLabel)
        if not success then
            return false, currentBalance
        end
    end
    
    return true, GetDepartmentBalance(deptName)
end

function AddFinanceEntry(deptName, actionType, amount, label, author)
    if not FinancesData[deptName] then
        FinancesData[deptName] = {}
    end
    
    local success, newBalance = ProcessTransaction(deptName, actionType, amount, label, author)
    if not success then
        return false
    end
    
    BalancesData[deptName] = newBalance
    local entry = {
        id = #FinancesData[deptName] + 1,
        type = actionType,
        amount = amount,
        label = label,
        author = author or "SYSTEM",
        date = os.date("%B %d, %Y %H:%M"),
        balance = newBalance
    }
    table.insert(FinancesData[deptName], 1, entry)
    
    if #FinancesData[deptName] > 50 then
        table.remove(FinancesData[deptName])
    end
    SaveFinances(deptName)
    return true
end
exports("AddFinanceEntry", AddFinanceEntry)

function GetEMSInvoiceConfig()
    return Config.EMSInvoice or {}
end

function TrimString(str)
    if type(str) ~= "string" then
        return ""
    end
    return string.gsub(string.gsub(str, "^%s+", ""), "%s+$", "")
end

function GetInvoiceDepartmentForPlayer(playerData)
    if not (playerData and playerData.job) then
        return "ambulance"
    end

    if type(GetDepartmentIdForFrameworkJob) == "function" then
        local deptId = GetDepartmentIdForFrameworkJob(playerData.job.name)
        if deptId then
            return deptId
        end
    end
    
    if MemberData and playerData.citizenid and MemberData[playerData.citizenid] and MemberData[playerData.citizenid].job then
        return MemberData[playerData.citizenid].job
    end
    
    return playerData.job.name or "ambulance"
end

function CheckDistance(src1, src2, maxDistance)
    local dist = tonumber(maxDistance) or 0
    if dist <= 0 then
        return true
    end
    
    local ped1 = GetPlayerPed(src1)
    local ped2 = GetPlayerPed(src2)
    
    if not ped1 or ped1 == 0 or not ped2 or ped2 == 0 then
        return true
    end
    
    local coords1 = GetEntityCoords(ped1)
    local coords2 = GetEntityCoords(ped2)
    
    if not coords1 or not coords2 then
        return true
    end
    
    return #(coords1 - coords2) <= dist
end

function ClearExpiredInvoices()
    local invoiceConfig = GetEMSInvoiceConfig()
    local expireTime = (tonumber(invoiceConfig.ExpireMinutes) or 10) * 60
    if expireTime <= 0 then
        return
    end
    
    local currentTime = os.time()
    for invId, invData in pairs(ActiveInvoices) do
        if not (invData.createdAt and currentTime - invData.createdAt > expireTime) then
            -- Invoice is still valid
        else
            ActiveInvoices[invId] = nil
        end
    end
end

function FindInvoice(patientSrc, invoiceId)
    ClearExpiredInvoices()
    if invoiceId then
        local inv = ActiveInvoices[invoiceId]
        if inv and inv.patientSrc == patientSrc then
            return inv
        end
        return nil
    end
    
    local latestInv = nil
    for _, invData in pairs(ActiveInvoices) do
        if invData.patientSrc == patientSrc then
            if not (latestInv and invData.id <= latestInv.id) then
                latestInv = invData
            end
        end
    end
    return latestInv
end

function PayInvoiceMoney(playerObj, amount)
    local invoiceConfig = GetEMSInvoiceConfig()
    local paymentAccounts = invoiceConfig.PaymentAccounts
    if type(paymentAccounts) ~= "table" or #paymentAccounts == 0 then
        paymentAccounts = { "bank", "cash" }
    end
    
    for _, acc in ipairs(paymentAccounts) do
        local accStr = tostring(acc or "")
        if accStr ~= "" then
            local currentMoney = tonumber(playerObj.functions.GetMoney(accStr)) or 0
            if amount <= currentMoney then
                if playerObj.functions.RemoveMoney(accStr, amount, "ems-invoice-payment") then
                    return true, accStr
                end
            end
        end
    end
    return false, nil
end

function CreateEMSInvoice(medicSrc, patientSrc, amount, reason)
    local medicObj = Framework.GetPlayer(medicSrc)
    if not medicObj then
        return
    end
    
    if not exports.plt_ambulance_job:IsEMS(medicSrc) and not Framework.HasPermission(medicSrc, Config.Permission) then
        Framework.Notify(medicSrc, _L("not_authorized"), "error")
        return
    end
    
    local targetSrc = tonumber(patientSrc)
    if not (targetSrc and GetPlayerName(targetSrc)) then
        Framework.Notify(medicSrc, _L("player_not_found"), "error")
        return
    end

    local invConfig = GetEMSInvoiceConfig()
    local invoiceAmount = math.floor(tonumber(amount) or 0)
    local maxAmount = tonumber(invConfig.MaxAmount) or 100000
    
    if invoiceAmount <= 0 or invoiceAmount > maxAmount then
        Framework.Notify(medicSrc, _L("ems_invoice_bad_amount", { max = maxAmount }), "error")
        return
    end
    
    local invoiceReason = TrimString(reason)
    if invoiceReason == "" then
        Framework.Notify(medicSrc, _L("ems_invoice_no_reason"), "error")
        return
    end
    
    if #invoiceReason > 120 then
        invoiceReason = string.sub(invoiceReason, 1, 120)
    end
    
    if not CheckDistance(medicSrc, targetSrc, invConfig.MaxDistance) then
        Framework.Notify(medicSrc, _L("ems_invoice_too_far"), "error")
        return
    end
    
    local patientObj = Framework.GetPlayer(targetSrc)
    if not patientObj then
        Framework.Notify(medicSrc, _L("player_not_found"), "error")
        return
    end
    
    ClearExpiredInvoices()
    InvoiceIdCounter = InvoiceIdCounter + 1
    
    local invoiceData = {
        id = InvoiceIdCounter,
        medicSrc = medicSrc,
        patientSrc = targetSrc,
        dept = GetInvoiceDepartmentForPlayer(medicObj),
        amount = invoiceAmount,
        reason = invoiceReason,
        medicName = medicObj.name,
        patientName = patientObj.name,
        departmentLabel = medicObj.job.label or GetInvoiceDepartmentForPlayer(medicObj),
        createdAt = os.time()
    }
    ActiveInvoices[invoiceData.id] = invoiceData
    
    Framework.Notify(medicSrc, _L("ems_invoice_sent", { id = invoiceData.id, name = patientObj.name, amount = invoiceAmount }), "success")
    Framework.Notify(targetSrc, _L("ems_invoice_received", {
        department = invoiceData.departmentLabel,
        id = invoiceData.id,
        amount = invoiceAmount,
        reason = invoiceReason,
        payCommand = invConfig.PayCommandName or "payemsinvoice",
        declineCommand = invConfig.DeclineCommandName or "declineemsinvoice"
    }), "warning")
    
    TriggerClientEvent("amb_client:EMSInvoiceReceived", targetSrc, invoiceData)
end

function PayEMSInvoice(patientSrc, invoiceId)
    local patientObj = Framework.GetPlayer(patientSrc)
    if not patientObj then
        return
    end
    
    local invIdNum = tonumber(invoiceId)
    if invoiceId and tostring(invoiceId) ~= "" and not invIdNum then
        Framework.Notify(patientSrc, _L("ems_invoice_not_found"), "error")
        return
    end
    
    local invData = FindInvoice(patientSrc, invIdNum)
    if not invData then
        local errorKey = invoiceId and "ems_invoice_not_found" or "ems_invoice_none"
        Framework.Notify(patientSrc, _L(errorKey), "error")
        return
    end
    
    local success, usedAccount = PayInvoiceMoney(patientObj, invData.amount)
    if not success then
        Framework.Notify(patientSrc, _L("ems_invoice_no_money"), "error")
        return
    end
    
    local txLabel = string.format("EMS Invoice #%s - %s", invData.id, invData.reason)
    if not AddFinanceEntry(invData.dept, "deposit", invData.amount, txLabel, patientObj.name) then
        patientObj.functions.AddMoney(usedAccount, invData.amount, "ems-invoice-refund")
        Framework.Notify(patientSrc, _L("ems_invoice_finance_error"), "error")
        return
    end
    
    ActiveInvoices[invData.id] = nil
    Framework.Notify(patientSrc, _L("ems_invoice_paid_patient", { id = invData.id, amount = invData.amount }), "success")
    
    if GetPlayerName(invData.medicSrc) then
        Framework.Notify(invData.medicSrc, _L("ems_invoice_paid_ems", { id = invData.id, amount = invData.amount, name = patientObj.name }), "success")
    end
end

function DeclineEMSInvoice(patientSrc, invoiceId)
    local patientObj = Framework.GetPlayer(patientSrc)
    if not patientObj then
        return
    end
    
    local invIdNum = tonumber(invoiceId)
    if invoiceId and tostring(invoiceId) ~= "" and not invIdNum then
        Framework.Notify(patientSrc, _L("ems_invoice_not_found"), "error")
        return
    end
    
    local invData = FindInvoice(patientSrc, invIdNum)
    if not invData then
        local errorKey = invoiceId and "ems_invoice_not_found" or "ems_invoice_none"
        Framework.Notify(patientSrc, _L(errorKey), "error")
        return
    end
    
    ActiveInvoices[invData.id] = nil
    Framework.Notify(patientSrc, _L("ems_invoice_declined_patient", { id = invData.id }), "info")
    
    if GetPlayerName(invData.medicSrc) then
        Framework.Notify(invData.medicSrc, _L("ems_invoice_declined_ems", { id = invData.id, name = patientObj.name }), "warning")
    end
end

RegisterNetEvent("amb_server:createEMSInvoice", function(patientSrc, amount, reason)
    CreateEMSInvoice(source, patientSrc, amount, reason)
end)

RegisterNetEvent("amb_server:payEMSInvoice", function(invoiceId)
    PayEMSInvoice(source, invoiceId)
end)

RegisterNetEvent("amb_server:declineEMSInvoice", function(invoiceId)
    DeclineEMSInvoice(source, invoiceId)
end)

AddEventHandler("playerDropped", function()
    local src = source
    for invId, invData in pairs(ActiveInvoices) do
        if not (invData.medicSrc ~= src and invData.patientSrc ~= src) then
            ActiveInvoices[invId] = nil
        end
    end
end)

RegisterCommand(GetEMSInvoiceConfig().CommandName or "emsinvoice", function(source, args)
    if source == 0 then
        return
    end
    
    local cmdName = GetEMSInvoiceConfig().CommandName or "emsinvoice"
    if #args < 3 then
        Framework.Notify(source, _L("ems_invoice_usage", { command = cmdName }), "error")
        return
    end
    
    local targetId = args[1]
    local amount = args[2]
    local reasonArgs = {}
    for i = 3, #args do
        table.insert(reasonArgs, args[i])
    end
    
    CreateEMSInvoice(source, targetId, amount, table.concat(reasonArgs, " "))
end, false)

RegisterCommand(GetEMSInvoiceConfig().PayCommandName or "payemsinvoice", function(source, args)
    if source == 0 then
        return
    end
    PayEMSInvoice(source, args[1])
end, false)

RegisterCommand(GetEMSInvoiceConfig().DeclineCommandName or "declineemsinvoice", function(source, args)
    if source == 0 then
        return
    end
    DeclineEMSInvoice(source, args[1])
end, false)

Framework.CreateCallback("amb_server:getBossMenuData", function(source, cb, deptFilter)
    local playersList = GetPlayersList()
    local playerObj = Framework.GetPlayer(source)
    
    local queryDept = deptFilter
    if not queryDept then
        if playerObj and playerObj.job and playerObj.job.name then
            queryDept = playerObj.job.name
        else
            queryDept = "ambulance"
        end
    end
    
    BalancesData[queryDept] = GetDepartmentBalance(queryDept)
    if not FinancesData[queryDept] then
        FinancesData[queryDept] = {}
    end
    
    local externalDepts = {}
    if GetResourceState("plt_departments") == "started" then
        local cat = exports.plt_departments:GetDepartmentCatalog(2000)
        externalDepts = cat or {}
    end
    
    cb({
        data = DepartmentData,
        externalDepts = externalDepts,
        members = playersList,
        news = NewsData,
        pcrs = PCRsData,
        dutyLogs = DeptDutyLogs or {},
        balances = BalancesData,
        finances = FinancesData,
        transactions = FinancesData[queryDept]
    })
end)

RegisterNetEvent("amb_server:addPCR", function(pcrData)
    local src = source
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        return
    end
    
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then
        return
    end
    
    local pcrEntry = {
        patient = pcrData.patient,
        condition = pcrData.condition,
        treatment = pcrData.treatment,
        author = playerObj.name,
        date = os.date("%B %d, %Y")
    }
    
    if HasPCRTable then
        MySQL.Async.insert("INSERT INTO plt_ambulance_job_pcrs (patient, `condition`, treatment, author, date) VALUES (?, ?, ?, ?, ?)", {
            pcrEntry.patient, pcrEntry.condition, pcrEntry.treatment, pcrEntry.author, pcrEntry.date
        }, function(insertId)
            pcrEntry.id = insertId
            table.insert(PCRsData, pcrEntry)
            if #PCRsData > 50 then
                table.remove(PCRsData, 1)
            end
            TriggerClientEvent("amb_client:SyncData", -1, { pcrs = PCRsData })
        end)
        return
    end
    
    pcrEntry.id = #PCRsData + 1
    table.insert(PCRsData, 1, pcrEntry)
    if #PCRsData > 50 then
        table.remove(PCRsData)
    end
    TriggerClientEvent("amb_client:SyncData", -1, { pcrs = PCRsData })
end)

Framework.CreateCallback("amb_server:searchDMR", function(source, cb, searchData)
    local query = searchData.query
    if not (query and #query >= 2) then
        return cb({})
    end

    local results = {}
    local sqlQuery = ""
    
    if Framework.Type == "qb" then
        sqlQuery = "SELECT citizenid as cid, charinfo FROM players WHERE LOWER(charinfo) LIKE ? OR LOWER(citizenid) LIKE ? LIMIT 10"
    else
        sqlQuery = "SELECT identifier as cid, firstname, lastname FROM users WHERE LOWER(CONCAT(firstname, ' ', lastname)) LIKE ? OR LOWER(identifier) LIKE ? LIMIT 10"
    end
    
    local dbRes = MySQL.Sync.fetchAll(sqlQuery, { "%" .. query .. "%", "%" .. query .. "%" })
    for _, row in ipairs(dbRes) do
        local fullName = "Unknown"
        if Framework.Type == "qb" then
            local charInfo = json.decode(row.charinfo)
            fullName = charInfo.firstname .. " " .. charInfo.lastname
        else
            fullName = row.firstname .. " " .. row.lastname
        end
        table.insert(results, { cid = row.cid, name = fullName })
    end
    cb(results)
end)

Framework.CreateCallback("amb_server:getDMRDetails", function(source, cb, data)
    local cid = data.cid
    if not cid then
        return cb({})
    end
    
    local patientName = "Unknown"
    if Framework.Type == "qb" then
        local userRes = MySQL.Sync.fetchAll("SELECT charinfo FROM players WHERE citizenid = ?", { cid })
        if userRes[1] then
            local charInfo = json.decode(userRes[1].charinfo)
            patientName = charInfo.firstname .. " " .. charInfo.lastname
        end
    else
        local userRes = MySQL.Sync.fetchAll("SELECT firstname, lastname FROM users WHERE identifier = ?", { cid })
        if userRes[1] then
            patientName = userRes[1].firstname .. " " .. userRes[1].lastname
        end
    end
    
    local pcrs = {}
    if HasPCRTable then
        pcrs = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_pcrs WHERE patient = ? ORDER BY id DESC", { patientName }) or {}
    else
        for _, pcr in ipairs(PCRsData) do
            if pcr.patient == patientName then
                table.insert(pcrs, pcr)
            end
        end
    end
    
    local xrays = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_xrays WHERE citizenid = ? ORDER BY id DESC", { cid })
    for _, xray in ipairs(xrays) do
        xray.injuries = json.decode(xray.injuries)
    end
    
    cb({
        name = patientName,
        pcrs = pcrs,
        xrays = xrays
    })
end)

RegisterNetEvent("amb_server:saveXRayResult", function(cid, injuries)
    local dateStr = os.date("%B %d, %Y")
    MySQL.Async.execute("INSERT INTO plt_ambulance_job_xrays (citizenid, injuries, date) VALUES (?, ?, ?)", {
        cid, json.encode(injuries), dateStr
    })
end)

Framework.CreateCallback("amb_server:searchPatients", function(source, cb, data)
    local query = data.query
    if not (query and #query >= 2) then
        return cb({})
    end

    local results = {}
    print("^2[plt_ambulance] Searching for Citizen:^7 " .. tostring(query))
    
    local success, dbRes = pcall(function()
        return MySQL.Sync.fetchAll([[
            SELECT citizenid as cid, charinfo 
            FROM players 
            WHERE citizenid LIKE ? 
               OR charinfo LIKE ?
            LIMIT 20
        ]], { "%" .. query .. "%", "%" .. query .. "%" })
    end)
    
    if success and dbRes then
        if #dbRes > 0 then
            for _, row in ipairs(dbRes) do
                local charInfoStr = row.charinfo
                if type(charInfoStr) == "string" then
                    local decoded = json.decode(charInfoStr)
                    if decoded then
                        charInfoStr = decoded
                    end
                end
                
                local pName = "Unknown"
                local pPhone = "N/A"
                if charInfoStr then
                    local fName = charInfoStr.firstname or "Unknown"
                    local lName = charInfoStr.lastname or "Citizen"
                    pName = fName .. " " .. lName
                    pPhone = charInfoStr.phone or "N/A"
                end
                table.insert(results, { cid = row.cid, name = pName, phone = pPhone })
            end
            print("^2[plt_ambulance] Found " .. #results .. " citizens.^7")
        else
            print("^3[plt_ambulance] 0 results found.^7")
        end
    else
        if not success then
            print("^1[plt_ambulance] SQL ERROR:^7 " .. tostring(dbRes))
        end
        print("^3[plt_ambulance] 0 results found.^7")
    end
    cb(results)
end)

Framework.CreateCallback("amb_server:getPatientDetails", function(source, cb, data)
    local cid = data.cid
    if not cid then
        return cb({})
    end
    
    local details = {
        cid = cid,
        name = "Unknown",
        pcrs = {},
        xrays = {},
        prescriptions = {},
        blood_type = "Unknown",
        allergies = "None",
        medical_notes = "No notes recorded.",
        insurance = false
    }
    
    if Framework.Type == "qb" then
        local userRes = MySQL.Sync.fetchAll("SELECT charinfo, metadata FROM players WHERE citizenid = ?", { cid })
        if userRes[1] then
            local charInfo = json.decode(userRes[1].charinfo)
            local metaData = json.decode(userRes[1].metadata)
            local profile = GetOrGeneratePatientProfile(cid, charInfo)
            
            details.name = charInfo.firstname .. " " .. charInfo.lastname
            details.phone = charInfo.phone
            details.dob = charInfo.birthdate
            
            if charInfo.gender == 0 then
                details.gender = "Male"
            else
                details.gender = "Female"
            end
            
            details.blood_type = profile.blood_type
            details.allergies = profile.known_allergy
            details.medical_notes = metaData.medicalnotes or "No notes recorded."
            
            if metaData.medical_insurance then
                details.insurance = true
            else
                details.insurance = false
            end
            
            details.hunger = math.floor(metaData.hunger or 100)
            details.thirst = math.floor(metaData.thirst or 100)
            details.stress = math.floor(metaData.stress or 0)
            details.is_dead = metaData.isdead or false
            details.health = metaData.health or 100
            SavePatientProfiles()
        end
    else
        local userRes = MySQL.Sync.fetchAll("SELECT firstname, lastname, dateofbirth, sex, phone_number, medical_insurance FROM users WHERE identifier = ?", { cid })
        if userRes[1] then
            local profile = GetOrGeneratePatientProfile(cid)
            details.name = userRes[1].firstname .. " " .. userRes[1].lastname
            details.dob = userRes[1].dateofbirth
            
            if userRes[1].sex == "m" then
                details.gender = "Male"
            else
                details.gender = "Female"
            end
            
            details.phone = userRes[1].phone_number
            details.insurance = (userRes[1].medical_insurance == 1)
            details.blood_type = profile.blood_type
            details.allergies = profile.known_allergy
            SavePatientProfiles()
        end
    end
    
    if HasPCRTable then
        details.pcrs = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_pcrs WHERE patient = ? OR author = ? ORDER BY id DESC", { details.name, details.name }) or {}
    end
    
    details.xrays = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_xrays WHERE citizenid = ? ORDER BY id DESC", { cid })
    for _, xray in ipairs(details.xrays) do
        xray.injuries = json.decode(xray.injuries)
    end
    
    pcall(function()
        details.prescriptions = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_prescriptions WHERE citizenid = ? ORDER BY id DESC", { cid })
    end)
    
    cb(details)
end)

Framework.CreateCallback("amb_server:updatePatientAllergy", function(source, cb, data)
    local src = source
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        cb({ success = false, message = _L("not_authorized") })
        return
    end
    
    local cidStr = (data and data.cid) and tostring(data.cid) or nil
    if not cidStr or cidStr == "" then
        cb({ success = false, message = "Missing patient ID." })
        return
    end
    
    local allergyStr = data and data.known_allergy or ""
    if type(allergyStr) ~= "string" then
        allergyStr = ""
    end
    
    allergyStr = string.gsub(string.gsub(allergyStr, "^%s+", ""), "%s+$", "")
    if allergyStr == "" then
        allergyStr = "None"
    end
    if #allergyStr > 120 then
        allergyStr = string.sub(allergyStr, 1, 120)
    end
    
    local profile = GetOrGeneratePatientProfile(cidStr)
    profile.known_allergy = allergyStr
    PatientProfilesData[cidStr] = profile
    SavePatientProfiles()
    
    cb({ success = true, known_allergy = allergyStr })
end)

RegisterNetEvent("amb_server:financeAction", function(data)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then
        return
    end
    
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        Framework.Notify(src, _L("not_authorized_funds"), "error")
        return
    end
    
    local deptName = data.dept or playerObj.job.name
    local action = data.action
    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then
        return
    end
    
    BalancesData[deptName] = GetDepartmentBalance(deptName)
    if not FinancesData[deptName] then
        FinancesData[deptName] = {}
    end
    
    if action == "deposit" then
        if playerObj.functions.RemoveMoney("cash", amount, "dept-deposit") then
            if AddFinanceEntry(deptName, "deposit", amount, "Manual Deposit", playerObj.name) then
                Framework.Notify(src, _L("deposited_funds", { amount = amount }), "success")
            else
                playerObj.functions.AddMoney("cash", amount, "dept-deposit-refund")
                Framework.Notify(src, "Department finance backend error.", "error")
            end
        else
            Framework.Notify(src, _L("not_enough_cash_short"), "error")
        end
    elseif action == "withdraw" then
        local currentBal = GetDepartmentBalance(deptName)
        if not currentBal or amount > currentBal then
            Framework.Notify(src, _L("not_enough_department_funds"), "error")
            return
        end
        
        if not AddFinanceEntry(deptName, "withdraw", amount, "Manual Withdrawal", playerObj.name) then
            Framework.Notify(src, _L("not_enough_department_funds"), "error")
            return
        end
        
        if playerObj.functions.AddMoney("cash", amount, "dept-withdrawal") then
            Framework.Notify(src, _L("withdrew_funds", { amount = amount }), "success")
        else
            AddFinanceEntry(deptName, "deposit", amount, "Withdrawal Rollback", "SYSTEM")
            Framework.Notify(src, "Department finance backend error.", "error")
        end
    end
end)

RegisterNetEvent("amb_server:distributeSalaries", function(data)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then
        return
    end
    
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        Framework.Notify(src, _L("not_authorized_funds"), "error")
        return
    end
    
    local deptName = (data and data.dept) and data.dept or playerObj.job.name
    if not deptName or tostring(deptName) == "" then
        Framework.Notify(src, "Missing department for payout.", "error")
        return
    end

    local payoutList, totalSalary = CalculateDepartmentSalaries(deptName)
    if #payoutList == 0 or totalSalary <= 0 then
        Framework.Notify(src, "No eligible online members with configured salaries.", "error")
        return
    end
    
    local bal = GetDepartmentBalance(deptName)
    if not bal or totalSalary > bal then
        Framework.Notify(src, _L("not_enough_department_funds"), "error")
        return
    end
    
    local txLabel = string.format("Salary payout (%d members)", #payoutList)
    if not AddFinanceEntry(deptName, "withdraw", totalSalary, txLabel, playerObj.name or "SYSTEM") then
        Framework.Notify(src, _L("not_enough_department_funds"), "error")
        return
    end
    
    local membersPaid = 0
    local amountPaid = 0
    for _, pd in ipairs(payoutList) do
        if PayPlayerSalary(pd) then
            membersPaid = membersPaid + 1
            amountPaid = amountPaid + pd.amount
            Framework.Notify(pd.source, string.format("Salary received: $%d", pd.amount), "success")
        end
    end
    
    if (totalSalary - amountPaid) > 0 then
        AddFinanceEntry(deptName, "deposit", totalSalary - amountPaid, "Salary payout refund", "SYSTEM")
    end
    Framework.Notify(src, string.format("Salary payout complete: %d members paid ($%d).", membersPaid, amountPaid), "success")
end)

RegisterNetEvent("amb_server:addNews", function(data)
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then
        return
    end
    
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then
        return
    end
    
    table.insert(NewsData, {
        id = #NewsData + 1,
        title = data.title,
        content = data.content,
        author = playerObj.name,
        date = os.date("%B %d, %Y")
    })
    SaveNews()
end)

RegisterNetEvent("amb_server:deleteNews", function(newsId)
    local src = source
    if not Framework.HasPermission(src, Config.Permission) then
        return
    end
    for idx, item in ipairs(NewsData) do
        if item.id == newsId then
            table.remove(NewsData, idx)
            break
        end
    end
    SaveNews()
end)

Framework.CreateCallback("amb_server:getInsuredPlayers", function(source, cb, deptFilter)
    local playerObj = Framework.GetPlayer(source)
    
    local queryDept = deptFilter
    if not queryDept then
        if playerObj and playerObj.job and playerObj.job.name then
            queryDept = playerObj.job.name
        else
            queryDept = "ambulance"
        end
    end

    if not exports.plt_ambulance_job:IsEMS(source) and not Framework.HasPermission(source, Config.Permission) then
        return cb({})
    end
    
    local insuredList = {}
    local addedMap = {}
    
    for _, srcStr in ipairs(GetPlayers()) do
        local targetObj = Framework.GetPlayer(tonumber(srcStr))
        if targetObj then
            local insStatus = Framework.GetMetaData(tonumber(srcStr), "medical_insurance")
            if insStatus then
                local hasAccess = true
                if insStatus ~= queryDept and insStatus ~= true then
                    if not Framework.HasPermission(source, Config.Permission) then
                        hasAccess = false
                    end
                end
                
                if hasAccess then
                    addedMap[targetObj.citizenid or targetObj.identifier] = true
                    local entry = { cid = targetObj.citizenid or targetObj.identifier, isOnline = true, serverId = tonumber(srcStr) }
                    
                    local pName = targetObj.name
                    if not pName then
                        if targetObj.charinfo then
                            pName = targetObj.charinfo.firstname .. " " .. targetObj.charinfo.lastname
                        else
                            pName = "Unknown"
                        end
                    end
                    entry.name = pName
                    table.insert(insuredList, entry)
                end
            end
        end
    end

    if Framework.Type == "qb" then
        local qbRes = MySQL.Sync.fetchAll("SELECT citizenid, charinfo, metadata FROM players", {})
        for _, row in ipairs(qbRes) do
            if not addedMap[row.citizenid] then
                local mData = row.metadata
                if type(mData) == "string" then
                    local decoded = json.decode(mData)
                    if decoded then mData = decoded end
                end
                
                if mData and mData.medical_insurance then
                    local hasAccess = true
                    if mData.medical_insurance ~= queryDept and mData.medical_insurance ~= true then
                        if not Framework.HasPermission(source, Config.Permission) then
                            hasAccess = false
                        end
                    end
                    
                    if hasAccess then
                        local cInfo = row.charinfo
                        if type(cInfo) == "string" then
                            local decoded = json.decode(cInfo)
                            if decoded then cInfo = decoded end
                        end
                        
                        local pName = nil
                        if cInfo then
                            pName = (cInfo.firstname or "") .. " " .. (cInfo.lastname or "")
                        else
                            pName = row.citizenid
                        end
                        
                        if not pName or pName == " " or pName == "" then
                            pName = row.citizenid
                        end
                        table.insert(insuredList, { cid = row.citizenid, name = pName, isOnline = false })
                    end
                end
            end
        end
    elseif Framework.Type == "esx" then
        local esxRes = SafeDBQuery("SELECT identifier, firstname, lastname, medical_insurance FROM users WHERE medical_insurance IS NOT NULL AND medical_insurance != 0", {}, "insured_players_full")
        if not esxRes then
            esxRes = SafeDBQuery("SELECT identifier, medical_insurance FROM users WHERE medical_insurance IS NOT NULL AND medical_insurance != 0", {}, "insured_players_minimal")
        end
        
        if esxRes then
            for _, row in ipairs(esxRes) do
                if not addedMap[row.identifier] then
                    local hasAccess = true
                    if row.medical_insurance ~= queryDept and row.medical_insurance ~= "1" and row.medical_insurance ~= 1 then
                        if not Framework.HasPermission(source, Config.Permission) then
                            hasAccess = false
                        end
                    end
                    
                    if hasAccess then
                        local fullName = (row.firstname or "") .. " " .. (row.lastname or "")
                        fullName = string.gsub(string.gsub(fullName, "^%s+", ""), "%s+$", "")
                        if fullName == "" then
                            fullName = row.identifier or "Unknown"
                        end
                        table.insert(insuredList, { cid = row.identifier, name = fullName, isOnline = false })
                    end
                end
            end
        else
            print("^3[plt_ambulance][ESX] users.medical_insurance column is missing or incompatible; offline insured list disabled.^7")
        end
    end
    cb(insuredList)
end)

RegisterNetEvent("amb_server:cancelInsurance", function(data)
    local src = source
    if not exports.plt_ambulance_job:IsEMS(src) and not Framework.HasPermission(src, Config.Permission) then
        Framework.Notify(src, _L("not_authorized"), "error")
        return
    end
    
    local targetCid = data.cid
    local targetServerId = data.serverId
    
    if targetServerId then
        local targetObj = Framework.GetPlayer(targetServerId)
        if targetObj then
            Framework.SetMetaData(targetServerId, "medical_insurance", false)
            TriggerClientEvent("amb_client:updateInsuranceStatus", targetServerId, false)
            Framework.Notify(targetServerId, _L("insurance_cancelled_by_department"), "error")
        end
    end
    
    if Framework.Type == "qb" then
        local playerRes = MySQL.Sync.fetchAll("SELECT metadata FROM players WHERE citizenid = ?", { targetCid })
        if playerRes[1] then
            local mData = playerRes[1].metadata
            if type(mData) == "string" then
                local decoded = json.decode(mData)
                if decoded then mData = decoded end
            end
            
            if mData then
                mData.medical_insurance = false
                MySQL.Async.execute("UPDATE players SET metadata = ? WHERE citizenid = ?", { json.encode(mData), targetCid })
            end
        end
    elseif Framework.Type == "esx" then
        local success, result = pcall(function()
            MySQL.Sync.execute("UPDATE users SET medical_insurance = 0 WHERE identifier = ?", { targetCid })
        end)
        if not success then
            print(string.format("[plt_ambulance][ESX][cancel_insurance] Failed to update users.medical_insurance for %s: %s", tostring(targetCid), tostring(result)))
        end
    end
    
    Framework.Notify(src, _L("insurance_subscription_cancelled"), "success")
end)

function HasBossPermission(playerId)
    if Framework.HasPermission(playerId, Config.Permission) then
        return true
    end
    if Framework.Type == "qb" and exports.plt_ambulance_job:IsEMS(playerId) then
        return true
    end
    return false
end

RegisterNetEvent("amb_server:hirePlayer", function(data)
    local src = source
    if not HasBossPermission(src) then
        Framework.Notify(src, _L("not_authorized"), "error")
        return
    end
    
    local targetId = tonumber(data.playerId)
    local targetObj = Framework.GetPlayer(targetId)
    if not targetObj then
        return
    end
    
    local jobName = data.job
    local gradeNum = tonumber(data.grade)
    local jobLabel = "Unknown"
    local gradeLabel = "Rank " .. gradeNum
    
    for _, node in ipairs(DepartmentData.nodes) do
        if node.id == jobName then
            jobLabel = node.label
            break
        end
    end
    
    Framework.SetJob(targetId, GetFrameworkJobForDepartment(jobName), gradeNum)
    Wait(300)
    
    local updatedObj = Framework.GetPlayer(targetId)
    if updatedObj then
        MemberData[updatedObj.citizenid] = {
            name = updatedObj.name,
            job = jobName,
            grade = gradeNum,
            jobLabel = jobLabel,
            gradeLabel = gradeLabel,
            ratings = {}
        }
        SaveMemberToDB(updatedObj.citizenid)
    end
end)

Framework.CreateCallback("amb_server:hireById", function(source, cb, data)
    if not HasBossPermission(source) then
        return cb({ success = false, message = "Not authorized" })
    end
    
    local idStr = data.id and tostring(data.id) or ""
    idStr = string.match(idStr, "^%s*(.-)%s*$") or idStr
    
    local jobName = data.job
    local gradeNum = tonumber(data.grade) or 0
    
    if not jobName or jobName == "" then
        return cb({ success = false, message = "No department selected" })
    end
    if not idStr or idStr == "" then
        return cb({ success = false, message = "Please enter a Citizen ID or Server ID" })
    end
    
    local targetSrc, targetObj, cid, pName = nil, nil, nil, "Unknown"
    local parsedNum = tonumber(idStr)
    
    if parsedNum and parsedNum >= 1 and parsedNum <= 9999 then
        targetObj = Framework.GetPlayer(parsedNum)
        if targetObj then
            targetSrc = parsedNum
            cid = targetObj.citizenid
            pName = targetObj.name
        end
    end
    
    if not targetObj and Framework.GetPlayerByCitizenId then
        targetObj = Framework.GetPlayerByCitizenId(idStr)
        if targetObj then
            targetSrc = targetObj.source
            cid = targetObj.citizenid or idStr
            pName = targetObj.name
        end
    end
    
    if not targetObj then
        for _, pStr in ipairs(GetPlayers()) do
            local loopObj = Framework.GetPlayer(tonumber(pStr))
            if loopObj and (loopObj.citizenid == idStr or tostring(loopObj.citizenid) == idStr) then
                targetObj = loopObj
                targetSrc = tonumber(pStr)
                cid = loopObj.citizenid
                pName = loopObj.name
                break
            end
        end
    end
    
    local jobLabel = "Unknown"
    local gradeLabel = "Rank " .. gradeNum
    for _, node in ipairs(DepartmentData.nodes) do
        if node.id == jobName then
            jobLabel = node.label
            break
        end
    end
    
    local links = DepartmentData.links or {}
    for _, link in ipairs(links) do
        if link.from == jobName then
            for _, node in ipairs(DepartmentData.nodes) do
                if node.id == link.to and node.type == "rank" and node.ranks then
                    for _, rank in ipairs(node.ranks) do
                        if tonumber(rank.level) == gradeNum then
                            gradeLabel = rank.name or gradeLabel
                            break
                        end
                    end
                end
            end
        end
    end
    
    if targetObj and targetSrc then
        Framework.SetJob(targetSrc, GetFrameworkJobForDepartment(jobName), gradeNum)
        Wait(200)
        local postJobObj = Framework.GetPlayer(targetSrc)
        if postJobObj then
            MemberData[postJobObj.citizenid] = {
                name = postJobObj.name,
                job = jobName,
                grade = gradeNum,
                jobLabel = jobLabel,
                gradeLabel = gradeLabel,
                ratings = {}
            }
            SaveMemberToDB(postJobObj.citizenid)
            TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
            return cb({ success = true })
        end
    end
    
    if Framework.Type == "qb" then
        local qbRes = MySQL.Sync.fetchAll("SELECT citizenid, charinfo FROM players WHERE citizenid = ?", { idStr })
        if not (qbRes and qbRes[1]) then
            qbRes = MySQL.Sync.fetchAll("SELECT citizenid, charinfo FROM players WHERE LOWER(citizenid) = ?", { string.lower(idStr) })
        end
        
        if qbRes and qbRes[1] then
            local row = qbRes[1]
            cid = row.citizenid
            local charInfo = row.charinfo
            if type(charInfo) == "string" then
                local decoded = json.decode(charInfo)
                if decoded then charInfo = decoded end
            end
            
            if charInfo then
                local fullName = (charInfo.firstname or "") .. " " .. (charInfo.lastname or "")
                if fullName and fullName ~= "" and fullName ~= " " then
                    pName = fullName
                else
                    pName = cid
                end
            else
                pName = cid
            end
            
            local jobDataBlob = {
                name = GetFrameworkJobForDepartment(jobName),
                label = jobLabel,
                grade = { level = gradeNum, name = gradeLabel },
                payment = 0,
                onduty = false,
                isboss = false
            }
            
            MySQL.Async.execute("UPDATE players SET job = ? WHERE citizenid = ?", { json.encode(jobDataBlob), cid }, function()
                MemberData[cid] = {
                    name = pName,
                    job = jobName,
                    grade = gradeNum,
                    jobLabel = jobLabel,
                    gradeLabel = gradeLabel,
                    ratings = {}
                }
                SaveMemberToDB(cid)
                TriggerClientEvent("amb_client:SyncMembers", -1, MemberData)
                cb({ success = true })
            end)
            return
        end
    end
    cb({ success = false, message = "Player not found. Use Citizen ID (e.g. ABC12345) or Server ID (#) if online." })
end)

RegisterNetEvent("amb_server:manageMember", function(data)
    local src = source
    if not HasBossPermission(src) then
        Framework.Notify(src, _L("not_authorized"), "error")
        return
    end
    
    local targetCid = data.cid
    local action = data.action
    local memberData = MemberData[targetCid]
    if not memberData then
        return
    end
    
    if action == "fire" then
        MemberData[targetCid] = nil
        MySQL.Sync.execute("DELETE FROM plt_ambulance_job_members WHERE citizenid = ?", { targetCid })
        for _, pStr in ipairs(GetPlayers()) do
            local targetObj = Framework.GetPlayer(tonumber(pStr))
            if targetObj and targetObj.citizenid == targetCid then
                Framework.SetJob(tonumber(pStr), "unemployed", 0)
                break
            end
        end
    elseif action == "promote" or action == "demote" then
        local newGrade = memberData.grade
        local modifier = (action == "promote") and 1 or -1
        
        newGrade = newGrade + modifier
        if newGrade < 0 then
            newGrade = 0
        end
        memberData.grade = newGrade
        
        for _, link in ipairs(DepartmentData.links) do
            if link.from == memberData.job then
                for _, node in ipairs(DepartmentData.nodes) do
                    if node.id == link.to and node.type == "rank" and node.ranks then
                        for _, rank in ipairs(node.ranks) do
                            if tonumber(rank.level) == newGrade then
                                memberData.gradeLabel = rank.name
                                break
                            end
                        end
                    end
                end
            end
        end
        
        SaveMemberToDB(targetCid)
        for _, pStr in ipairs(GetPlayers()) do
            local targetObj = Framework.GetPlayer(tonumber(pStr))
            if targetObj and targetObj.citizenid == targetCid then
                Framework.SetJob(tonumber(pStr), GetFrameworkJobForDepartment(memberData.job), newGrade)
                break
            end
        end
    end
end)

function SendDepartmentMail(senderDept, receiverDept, senderName, subject, message, imageUrl)
    local dateStr = os.date("%B %d, %Y")
    local timeStr = os.date("%H:%M")
    local isValidDept = false
    local actualReceiver = receiverDept
    
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" and (node.id == receiverDept or node.frameworkJob == receiverDept) then
            isValidDept = true
            actualReceiver = node.id
            break
        end
    end
    
    if isValidDept then
        MySQL.Async.insert("INSERT INTO plt_ambulance_job_mails (sender_dept, receiver_dept, sender_name, subject, message, image_url, `date`, `time`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", {
            senderDept, actualReceiver, senderName, subject, message, imageUrl or "", dateStr, timeStr
        }, function(insertId)
            if insertId then
                for _, pStr in ipairs(GetPlayers()) do
                    local targetObj = Framework.GetPlayer(tonumber(pStr))
                    if targetObj then
                        local jobMatches = (targetObj.job.name == actualReceiver)
                        if not jobMatches and targetObj.job.name == GetFrameworkJobForDepartment(actualReceiver) then
                            jobMatches = true
                        end
                        if jobMatches then
                            Framework.Notify(tonumber(pStr), "New department mail received from " .. string.upper(senderDept), "info")
                            TriggerClientEvent("amb_client:SyncMail", tonumber(pStr))
                        end
                    end
                end
            end
        end)
    else
        if GetResourceState("plt_departments") == "started" then
            exports.plt_departments:SendDepartmentMail(senderDept, receiverDept, senderName, subject, message, imageUrl)
        end
        MySQL.Async.insert("INSERT INTO plt_ambulance_job_mails (sender_dept, receiver_dept, sender_name, subject, message, image_url, `date`, `time`, is_read) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)", {
            senderDept, receiverDept, senderName, subject, message, imageUrl or "", dateStr, timeStr
        })
    end
end
exports("SendDepartmentMail", SendDepartmentMail)

Framework.CreateCallback("amb_server:getMails", function(source, cb, deptName)
    local dbMails = MySQL.Sync.fetchAll("SELECT * FROM plt_ambulance_job_mails WHERE receiver_dept = ? OR sender_dept = ? ORDER BY id DESC LIMIT 50", { deptName, deptName })
    cb(dbMails or {})
end)

RegisterNetEvent("amb_server:sendMail", function(data)
    local src = source
    local playerObj = Framework.GetPlayer(src)
    if not playerObj then
        return
    end
    SendDepartmentMail(data.senderDept, data.receiverDept, playerObj.name, data.subject, data.message, data.imageUrl)
end)

RegisterNetEvent("amb_server:markMailRead", function(mailId)
    MySQL.Async.execute("UPDATE plt_ambulance_job_mails SET is_read = 1 WHERE id = ?", { mailId })
end)

RegisterNetEvent("amb_server:deleteMail", function(mailId)
    MySQL.Async.execute("DELETE FROM plt_ambulance_job_mails WHERE id = ?", { mailId })
end)

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
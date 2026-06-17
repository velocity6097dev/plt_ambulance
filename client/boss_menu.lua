-- ==========================================
-- Net Events
-- ==========================================

RegisterNetEvent("amb_client:SyncNews", function(newsData)
    SendNUIMessage({
        action = "amb_syncNews",
        news = newsData
    })
end)

RegisterNetEvent("amb_client:SyncData", function(data)
    SendNUIMessage({
        action = "amb_syncData",
        balances = data.balances,
        finances = data.finances,
        news = data.news,
        pcrs = data.pcrs,
        dutyLogs = data.dutyLogs,
        members = data.members,
        transactions = data.transactions
    })
end)

RegisterNetEvent("amb_client:SyncMail", function()
    SendNUIMessage({
        action = "amb_client:SyncMail"
    })
end)


-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback("amb_addPCR", function(data, cb)
    TriggerServerEvent("amb_server:addPCR", data)
    cb("ok")
end)

RegisterNUICallback("amb_searchDMR", function(data, cb)
    Framework.TriggerCallback("amb_server:searchDMR", function(result)
        cb(result or {})
    end, data)
end)

RegisterNUICallback("amb_getDMRDetails", function(data, cb)
    Framework.TriggerCallback("amb_server:getDMRDetails", function(result)
        cb(result or {})
    end, data)
end)

RegisterNUICallback("financeAction", function(data, cb)
    TriggerServerEvent("amb_server:financeAction", data)
    cb("ok")
end)

RegisterNUICallback("distributeSalaries", function(data, cb)
    TriggerServerEvent("amb_server:distributeSalaries", data or {})
    cb("ok")
end)

RegisterNUICallback("amb_getInsuredPlayers", function(data, cb)
    Framework.TriggerCallback("amb_server:getInsuredPlayers", function(result)
        cb(result or {})
    end, data.jobName)
end)

RegisterNUICallback("amb_cancelInsurance", function(data, cb)
    TriggerServerEvent("amb_server:cancelInsurance", data)
    cb("ok")
end)

RegisterNUICallback("amb_addNews", function(data, cb)
    TriggerServerEvent("amb_server:addNews", data)
    cb("ok")
end)

RegisterNUICallback("amb_deleteNews", function(data, cb)
    TriggerServerEvent("amb_server:deleteNews", data.id)
    cb("ok")
end)

RegisterNUICallback("amb_getPlayers", function(data, cb)
    Framework.TriggerCallback("amb_server:getPlayers", function(result)
        cb(result)
    end)
end)

RegisterNUICallback("amb_hirePlayer", function(data, cb)
    TriggerServerEvent("amb_server:hirePlayer", data)
    cb("ok")
end)

RegisterNUICallback("amb_hireById", function(data, cb)
    Framework.TriggerCallback("amb_server:hireById", function(result)
        cb(result or { success = false, message = "Unknown error" })
    end, data)
end)

RegisterNUICallback("amb_manageMember", function(data, cb)
    TriggerServerEvent("amb_server:manageMember", data)
    cb("ok")
end)

RegisterNUICallback("amb_getMails", function(data, cb)
    Framework.TriggerCallback("amb_server:getMails", function(result)
        cb(result)
    end, data.dept)
end)

RegisterNUICallback("amb_sendMail", function(data, cb)
    TriggerServerEvent("amb_server:sendMail", data)
    cb("ok")
end)

RegisterNUICallback("amb_markMailRead", function(data, cb)
    TriggerServerEvent("amb_server:markMailRead", data.id)
    cb("ok")
end)

RegisterNUICallback("amb_deleteMail", function(data, cb)
    TriggerServerEvent("amb_server:deleteMail", data.id)
    cb("ok")
end)

RegisterNUICallback("amb_searchPatients", function(data, cb)
    Framework.TriggerCallback("amb_server:searchPatients", function(result)
        cb(result)
    end, data)
end)

RegisterNUICallback("amb_getPatientDetails", function(data, cb)
    Framework.TriggerCallback("amb_server:getPatientDetails", function(result)
        cb(result)
    end, data)
end)

RegisterNUICallback("amb_updatePatientAllergy", function(data, cb)
    Framework.TriggerCallback("amb_server:updatePatientAllergy", function(result)
        cb(result or { success = false, message = "Update failed" })
    end, data)
end)


-- ==========================================
-- Core Functions
-- ==========================================

function OpenBossMenu(jobName)
    Framework.TriggerCallback("amb_server:getBossMenuData", function(response)
        if not response then
            Framework.Notify(_L("boss_menu_data_error"), "error")
            return
        end
        
        local playerData = Framework.GetPlayerData()
        
        local playerName = "MEDICAL"
        if playerData and playerData.name then
            playerName = playerData.name
        end
        
        local playerRank = "DOCTOR"
        if playerData and playerData.job and playerData.job.gradeLabel then
            playerRank = playerData.job.gradeLabel
        end

        SendNUIMessage({
            action = "amb_openBossMenu",
            data = response.data,
            externalDepts = response.externalDepts or {},
            jobName = jobName,
            playerName = playerName,
            playerRank = playerRank,
            members = response.members,
            news = response.news,
            pcrs = response.pcrs,
            dutyLogs = response.dutyLogs or {},
            balances = response.balances,
            finances = response.finances,
            transactions = response.transactions
        })
        
        SetNuiFocus(true, true)
    end, jobName)
end
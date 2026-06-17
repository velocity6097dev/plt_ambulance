print("^2[Dispatch]^7 Dispatch system loaded.")

local isDispatchVisible = false
local isDispatchLocked = false
local activeCall = nil

local function CheckDispatchAuth()
    if exports.plt_ambulance_job:IsEMS() then
        return true
    end

    local pData = Framework.GetPlayerData()
    local jobName = nil
    
    if pData and pData.job and pData.job.name then
        jobName = pData.job.name
    end

    if not jobName then
        return false
    end

    local emsJobs = {}
    if Config.Medical and Config.Medical.EMSJobs then
        emsJobs = Config.Medical.EMSJobs
    end

    for _, jName in ipairs(emsJobs) do
        if tostring(jobName) == tostring(jName) then
            return true
        end
    end
    
    return false
end

local function ToggleDispatchUI(state)
    if state ~= nil then
        isDispatchVisible = state
    else
        isDispatchVisible = not isDispatchVisible
    end

    print("^2[Dispatch]^7 Toggling dispatch UI: " .. tostring(isDispatchVisible))

    SendNUIMessage({
        action = "amb_toggleDispatch",
        show = isDispatchVisible
    })

    if isDispatchVisible then
        SetNuiFocus(true, true)
    else
        SetNuiFocus(false, false)
    end
end

RegisterNUICallback("toggleDispatch", function(data, cb)
    ToggleDispatchUI()
    cb("ok")
end)

RegisterCommand("forcedispatch", function()
    ToggleDispatchUI(true)
end, false)

RegisterCommand("dispatch", function()
    if CheckDispatchAuth() then
        ToggleDispatchUI()
    else
        Framework.Notify(_L("authorized_only"), "error")
    end
end, false)

RegisterNUICallback("lockDispatch", function(data, cb)
    local locked = nil
    if data then
        locked = (data.locked == true)
    end
    isDispatchLocked = locked

    if isDispatchLocked then
        SetNuiFocus(false, false)
        Framework.Notify(_L("dispatch_locked"), "success")
    else
        if isDispatchVisible then
            SetNuiFocus(true, true)
        end
    end
    
    cb("ok")
end)

RegisterNUICallback("setDispatchGPS", function(data, cb)
    if data.x and data.y then
        SetNewWaypoint(data.x, data.y)
        Framework.Notify(_L("gps_set"), "success")
    end
    cb("ok")
end)

RegisterNUICallback("dismissDispatchCall", function(data, cb)
    local callId = nil
    if data and data.id then
        callId = data.id
    end

    if not callId then
        activeCall = nil
        cb("ok")
        return
    end

    if activeCall then
        if tostring(activeCall.id) == tostring(callId) then
            activeCall = nil
        end
    end
    
    cb("ok")
end)

RegisterNUICallback("setActiveDispatchCall", function(data, cb)
    local call = nil
    if data and data.call then
        call = data.call
    end

    if type(call) == "table" then
        activeCall = call
    else
        activeCall = nil
    end
    
    cb("ok")
end)

function SendDeathDispatch()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local street1, street2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local locationName = GetStreetNameFromHashKey(street1)

    if street2 ~= 0 then
        locationName = locationName .. " / " .. GetStreetNameFromHashKey(street2)
    end

    print("^2[Dispatch]^7 Sending death dispatch for location: " .. locationName)

    TriggerServerEvent("amb_server:sendDispatchCall", {
        title = _L("patient_downed"),
        coords = {
            x = coords.x,
            y = coords.y
        },
        locationName = locationName
    })
end

exports("SendDeathDispatch", function(data)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local street1, street2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local locationName = GetStreetNameFromHashKey(street1)

    if street2 ~= 0 then
        locationName = locationName .. " / " .. GetStreetNameFromHashKey(street2)
    end

    if type(data) ~= "table" or not data then
        data = {}
    end

    if not data.title then
        data.title = _L("patient_downed")
    end

    if not data.coords then
        data.coords = {
            x = coords.x,
            y = coords.y
        }
    end

    if not data.locationName then
        data.locationName = locationName
    end

    TriggerServerEvent("amb_server:sendDispatchCall", data)
end)

RegisterNetEvent("amb_client:addDispatchCall", function(callData)
    activeCall = callData
    SendNUIMessage({
        action = "amb_addDispatchCall",
        call = callData
    })
end)

CreateThread(function()
    while true do
        if isDispatchVisible then
            if activeCall then
                Wait(0)
                if IsControlJustPressed(0, 38) then
                    local coords = activeCall.coords or {}
                    local x = tonumber(coords.x or coords[1])
                    local y = tonumber(coords.y or coords[2])

                    if x and y then
                        SetNewWaypoint(x, y)
                        Framework.Notify(_L("gps_set"), "success")
                    end
                elseif IsControlJustPressed(0, 246) then
                    local callId = nil
                    if activeCall and activeCall.id then
                        callId = activeCall.id
                    end
                    
                    activeCall = nil
                    SendNUIMessage({
                        action = "amb_removeDispatchCall",
                        id = callId
                    })
                end
            else
                Wait(250)
            end
        else
            Wait(250)
        end
    end
end)
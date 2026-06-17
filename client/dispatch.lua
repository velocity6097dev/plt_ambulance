print("^2[Dispatch]^7 Dispatch system loaded.")

local isDispatchOpen = false
local isDispatchLocked = false
local activeCall = nil

-- ==========================================
-- Utility Functions
-- ==========================================

local function IsAuthorized()
    -- Check if EMS using main export
    if exports.plt_ambulance_job:IsEMS() then
        return true
    end

    -- Fallback/secondary check via Framework
    local playerData = Framework.GetPlayerData()
    local jobName = (playerData and playerData.job and playerData.job.name) or nil
    
    if not jobName then return false end

    local emsJobs = (Config and Config.Medical and Config.Medical.EMSJobs) or {}
    
    for _, job in ipairs(emsJobs) do
        if tostring(jobName) == tostring(job) then
            return true
        end
    end
    
    return false
end

local function ToggleDispatch(state)
    if state ~= nil then
        isDispatchOpen = state
    else
        isDispatchOpen = not isDispatchOpen
    end

    print("^2[Dispatch]^7 Toggling dispatch UI: " .. tostring(isDispatchOpen))
    
    SendNUIMessage({
        action = "amb_toggleDispatch",
        show = isDispatchOpen
    })

    if isDispatchOpen then
        SetNuiFocus(true, true)
    else
        SetNuiFocus(false, false)
    end
end

-- ==========================================
-- Commands
-- ==========================================

RegisterCommand("forcedispatch", function()
    ToggleDispatch(true)
end, false)

RegisterCommand("dispatch", function()
    if IsAuthorized() then
        ToggleDispatch()
    else
        Framework.Notify(_L("authorized_only"), "error")
    end
end, false)

-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback("toggleDispatch", function(data, cb)
    ToggleDispatch()
    cb("ok")
end)

RegisterNUICallback("lockDispatch", function(data, cb)
    isDispatchLocked = (data and data.locked == true)

    if isDispatchLocked then
        SetNuiFocus(false, false)
        Framework.Notify(_L("dispatch_locked"), "success")
    else
        if isDispatchOpen then
            SetNuiFocus(true, true)
        end
    end
    cb("ok")
end)

RegisterNUICallback("setDispatchGPS", function(data, cb)
    if data and data.x and data.y then
        SetNewWaypoint(data.x, data.y)
        Framework.Notify(_L("gps_set"), "success")
    end
    cb("ok")
end)

RegisterNUICallback("dismissDispatchCall", function(data, cb)
    local callId = data and data.id or nil
    
    if not callId then
        activeCall = nil
        return cb("ok")
    end

    if activeCall and tostring(activeCall.id) == tostring(callId) then
        activeCall = nil
    end
    cb("ok")
end)

RegisterNUICallback("setActiveDispatchCall", function(data, cb)
    local call = data and data.call or nil
    if type(call) == "table" then
        activeCall = call
    else
        activeCall = nil
    end
    cb("ok")
end)

-- ==========================================
-- Core Dispatch Functions & Exports
-- ==========================================

function SendDeathDispatch()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local hash1, hash2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(hash1)

    if hash2 ~= 0 then
        streetName = streetName .. " / " .. GetStreetNameFromHashKey(hash2)
    end

    print("^2[Dispatch]^7 Sending death dispatch for location: " .. streetName)

    TriggerServerEvent("amb_server:sendDispatchCall", {
        title = _L("patient_downed"),
        coords = { x = coords.x, y = coords.y },
        locationName = streetName
    })
end

exports("SendDeathDispatch", function(customData)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local hash1, hash2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(hash1)

    if hash2 ~= 0 then
        streetName = streetName .. " / " .. GetStreetNameFromHashKey(hash2)
    end

    local callData = (type(customData) == "table" and customData) or {}

    callData.title = callData.title or _L("patient_downed")
    callData.coords = callData.coords or { x = coords.x, y = coords.y }
    callData.locationName = callData.locationName or streetName

    TriggerServerEvent("amb_server:sendDispatchCall", callData)
end)

-- ==========================================
-- Net Events
-- ==========================================

RegisterNetEvent("amb_client:addDispatchCall", function(callData)
    activeCall = callData
    SendNUIMessage({
        action = "amb_addDispatchCall",
        call = callData
    })
end)

-- ==========================================
-- Input Control Thread
-- ==========================================

CreateThread(function()
    while true do
        if isDispatchOpen and activeCall then
            Wait(0)
            
            -- Press 'E' (38) to Set Waypoint to Call
            if IsControlJustPressed(0, 38) then
                local callCoords = activeCall.coords or {}
                local targetX = tonumber(callCoords.x) or tonumber(callCoords[1])
                local targetY = tonumber(callCoords.y) or tonumber(callCoords[2])
                
                if targetX and targetY then
                    SetNewWaypoint(targetX, targetY)
                    Framework.Notify(_L("gps_set"), "success")
                end
            
            -- Press 'Y' (246) to Dismiss Active Call
            elseif IsControlJustPressed(0, 246) then
                local callId = activeCall and activeCall.id or nil
                activeCall = nil
                
                SendNUIMessage({
                    action = "amb_removeDispatchCall",
                    id = callId
                })
            end
        else
            Wait(250)
        end
    end
end)
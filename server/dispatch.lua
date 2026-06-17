local ActiveDispatchCalls = {}

-- ==========================================
-- Utility Functions
-- ==========================================

local function FormatDispatchCall(data)
    if type(data) ~= "table" then return nil end
    
    local call = {}
    for k, v in pairs(data) do
        call[k] = v
    end
    
    -- Set defaults for missing data
    call.id = call.id or math.random(1000, 9999)
    call.source = call.source or 0
    call.time = call.time or os.date("%H:%M")
    call.code = call.code or "10-52"
    call.title = call.title or "Medical Alert"
    call.location = call.location or call.locationName or "Unknown Location"
    call.info = call.info or call.type or ""
    
    -- Safely parse coordinates
    if type(call.coords) == "vector3" then
        call.coords = { x = call.coords.x, y = call.coords.y, z = call.coords.z }
    elseif type(call.coords) == "table" then
        call.coords = {
            x = tonumber(call.coords.x or call.coords[1]) or 0.0,
            y = tonumber(call.coords.y or call.coords[2]) or 0.0,
            z = tonumber(call.coords.z or call.coords[3]) or 0.0
        }
    else
        call.coords = { x = 0.0, y = 0.0, z = 0.0 }
    end
    
    return call
end

local function SaveDispatchCall(call)
    table.insert(ActiveDispatchCalls, 1, call)
    
    -- Limit cache to the 100 most recent calls
    if #ActiveDispatchCalls > 100 then
        table.remove(ActiveDispatchCalls)
    end
end

local function ProcessAndSendDispatch(callData, src)
    local sourceId = tonumber(src) or 0
    print("^2[Dispatch]^7 Received dispatch call from source: " .. tostring(sourceId))
    
    if type(callData) ~= "table" then
        print("^1[Dispatch Error]^7 Invalid callData received from " .. tostring(sourceId))
        return false
    end
    
    callData.source = callData.source or sourceId
    
    local formattedCall = FormatDispatchCall(callData)
    if not formattedCall then return false end
    
    SaveDispatchCall(formattedCall)
    
    local players = Framework.GetPlayers()
    local emsCount = 0
    print("^2[Dispatch]^7 Checking " .. tostring(#players) .. " online players for EMS jobs...")
    
    for _, playerId in ipairs(players) do
        local targetSrc = tonumber(playerId)
        
        -- Check if the player is EMS
        if exports.plt_ambulance_job:IsEMS(targetSrc) then
            -- Send to default ambulance UI
            TriggerClientEvent("amb_client:addDispatchCall", targetSrc, formattedCall)
            
            -- Send to external MDT if installed
            TriggerClientEvent("plt_mdt_ems:client:newDispatchCall", targetSrc, formattedCall)
            
            emsCount = emsCount + 1
        end
    end
    
    print("^2[Dispatch]^7 Result: Call distributed to " .. tostring(emsCount) .. " EMS members.")
    return true
end

-- ==========================================
-- Events & Exports
-- ==========================================

RegisterNetEvent("amb_server:sendDispatchCall", function(callData)
    local src = source
    ProcessAndSendDispatch(callData, src)
end)

exports("SendExternalDispatch", function(callData, src)
    return ProcessAndSendDispatch(callData, src or 0)
end)

exports("GetActiveDispatchCalls", function()
    return ActiveDispatchCalls
end)
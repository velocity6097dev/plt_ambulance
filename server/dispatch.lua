local ActiveDispatchCalls = {}

function FormatDispatchCall(rawData)
    if type(rawData) ~= "table" then
        return nil
    end
    
    local formattedCall = {}
    for key, value in pairs(rawData) do
        formattedCall[key] = value
    end
    
    if not formattedCall.id then
        formattedCall.id = math.random(1000, 9999)
    end
    
    if not formattedCall.source then
        formattedCall.source = 0
    end
    
    if not formattedCall.time then
        formattedCall.time = os.date("%H:%M")
    end
    
    if not formattedCall.code then
        formattedCall.code = "10-52"
    end
    
    if not formattedCall.title then
        formattedCall.title = "Medical Alert"
    end
    
    if not formattedCall.location then
        local locName = formattedCall.locationName
        if not locName then
            locName = "Unknown Location"
        end
        formattedCall.location = locName
    end
    
    if not formattedCall.info then
        local infoType = formattedCall.type
        if not infoType then
            infoType = ""
        end
        formattedCall.info = infoType
    end
    
    local coordsData = formattedCall.coords
    if type(coordsData) == "vector3" then
        formattedCall.coords = {
            x = coordsData.x,
            y = coordsData.y,
            z = coordsData.z
        }
    elseif type(coordsData) == "table" then
        local xVal = tonumber(coordsData.x or coordsData[1])
        if not xVal then
            xVal = 0.0
        end
        
        local yVal = tonumber(coordsData.y or coordsData[2])
        if not yVal then
            yVal = 0.0
        end
        
        local zVal = tonumber(coordsData.z or coordsData[3])
        if not zVal then
            zVal = 0.0
        end
        
        formattedCall.coords = {
            x = xVal,
            y = yVal,
            z = zVal
        }
    else
        formattedCall.coords = {
            x = 0.0,
            y = 0.0,
            z = 0.0
        }
    end
    
    return formattedCall
end

function AddCallToHistory(callData)
    table.insert(ActiveDispatchCalls, 1, callData)
    if #ActiveDispatchCalls > 100 then
        table.remove(ActiveDispatchCalls)
    end
end

function ProcessDispatchCall(callData, callSource)
    local sourceNum = tonumber(callSource)
    callSource = sourceNum or callSource
    if not sourceNum then
        callSource = 0
    end
    
    print("^2[Dispatch]^7 Received dispatch call from source: " .. tostring(callSource))
    
    if type(callData) ~= "table" then
        print("^1[Dispatch Error]^7 Invalid callData received from " .. tostring(callSource))
        return false
    end
    
    local overrideSource = callData.source
    if not overrideSource then
        overrideSource = callSource
    end
    callData.source = overrideSource
    
    local formattedData = FormatDispatchCall(callData)
    if not formattedData then
        return false
    end
    
    AddCallToHistory(formattedData)
    
    local playersList = Framework.GetPlayers()
    local distributedCount = 0
    
    print("^2[Dispatch]^7 Checking " .. #playersList .. " online players for EMS jobs...")
    
    for _, playerId in ipairs(playersList) do
        local targetSrc = tonumber(playerId)
        
        if exports.plt_ambulance_job:IsEMS(targetSrc) then
            TriggerClientEvent("amb_client:addDispatchCall", targetSrc, formattedData)
            TriggerClientEvent("plt_mdt_ems:client:newDispatchCall", targetSrc, formattedData)
            distributedCount = distributedCount + 1
        end
    end
    
    print("^2[Dispatch]^7 Result: Call distributed to " .. distributedCount .. " EMS members.")
    return true
end

RegisterNetEvent("amb_server:sendDispatchCall", function(callData)
    ProcessDispatchCall(callData, source)
end)

exports("SendExternalDispatch", function(callData, optionalSource)
    local src = optionalSource or 0
    return ProcessDispatchCall(callData, src)
end)

exports("GetActiveDispatchCalls", function()
    return ActiveDispatchCalls
end)
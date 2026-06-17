-- ==========================================
-- Utility Functions
-- ==========================================

local function IsAuthorized(source)
    if source == 0 then 
        return true -- Console execution
    end
    
    if Framework.HasPermission(source, Config.Permission) then 
        return true 
    end
    
    if exports.plt_ambulance_job:IsEMS(source) then 
        return true 
    end
    
    return false
end

-- ==========================================
-- Network Events
-- ==========================================

RegisterNetEvent("amb_server:compat:resetVitals", function()
    local src = source
    if not src then return end
    
    Framework.SetMetaData(src, "hunger", 100)
    Framework.SetMetaData(src, "thirst", 100)
    Framework.SetMetaData(src, "stress", 0)
end)

RegisterNetEvent("amb_server:compat:sedateTarget", function(targetId)
    local src = source
    local targetSrc = tonumber(targetId)
    
    if not targetSrc then return end
    if not IsAuthorized(src) then return end
    
    TriggerClientEvent("amb_client:compat:applySedative", targetSrc)
end)

RegisterNetEvent("amb_server:compat:placeInVehicle", function(targetId, netId, seat)
    local src = source
    local targetSrc = tonumber(targetId)
    local seatIndex = tonumber(seat)
    
    if not targetSrc or not netId or seatIndex == nil then return end
    if not IsAuthorized(src) then return end
    
    TriggerClientEvent("amb_client:compat:warpIntoVehicle", targetSrc, netId, seatIndex)
end)

RegisterNetEvent("amb_server:compat:loadOnStretcher", function(targetId, stretcherNetId)
    local src = source
    local targetSrc = tonumber(targetId)
    
    if not targetSrc or not stretcherNetId then return end
    if not IsAuthorized(src) then return end
    
    TriggerClientEvent("amb_client:compat:loadOnStretcher", targetSrc, stretcherNetId)
end)

-- ==========================================
-- Server Exports
-- ==========================================

exports("RevivePlayer", function(targetId)
    local targetSrc = tonumber(targetId)
    if not targetSrc then return false end
    
    exports.plt_ambulance_job:InternalRevive(targetSrc)
    return true
end)

exports("disableKnockoutLoop", function(targetId, state)
    local targetSrc = tonumber(targetId)
    if not targetSrc then return false end
    
    TriggerClientEvent("amb_client:compat:setKnockoutDisabled", targetSrc, state == true)
    return true
end)

exports("manuallyKnockout", function(targetId, state)
    local targetSrc = tonumber(targetId)
    if not targetSrc then return false end
    
    local isKnockedOut = (state == true)
    
    TriggerClientEvent("amb_client:compat:manualKnockout", targetSrc, isKnockedOut)
    
    -- If setting state to false (waking up), revive them
    if not isKnockedOut then
        exports.plt_ambulance_job:InternalRevive(targetSrc)
    end
    
    return true
end)
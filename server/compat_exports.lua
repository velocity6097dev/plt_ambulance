function HasCompatPermission(sourceId)
    if sourceId == 0 then
        return true
    end
    
    local hasPerm = Framework.HasPermission(sourceId, Config.Permission)
    if not hasPerm then
        hasPerm = exports.plt_ambulance_job:IsEMS(sourceId)
    end
    
    return hasPerm
end

RegisterNetEvent("amb_server:compat:resetVitals", function()
    local src = source
    if not src then
        return
    end
    
    Framework.SetMetaData(src, "hunger", 100)
    Framework.SetMetaData(src, "thirst", 100)
    Framework.SetMetaData(src, "stress", 0)
end)

RegisterNetEvent("amb_server:compat:sedateTarget", function(targetSrc)
    local src = source
    local target = tonumber(targetSrc)
    
    if not target then
        return
    end
    
    if not HasCompatPermission(src) then
        return
    end
    
    TriggerClientEvent("amb_client:compat:applySedative", target)
end)

RegisterNetEvent("amb_server:compat:placeInVehicle", function(targetSrc, vehicleId, seatIndex)
    local src = source
    local target = tonumber(targetSrc)
    local seat = tonumber(seatIndex)
    
    if not (target and vehicleId) or seat == nil then
        return
    end
    
    if not HasCompatPermission(src) then
        return
    end
    
    TriggerClientEvent("amb_client:compat:warpIntoVehicle", target, vehicleId, seat)
end)

RegisterNetEvent("amb_server:compat:loadOnStretcher", function(targetSrc, stretcherId)
    local src = source
    local target = tonumber(targetSrc)
    
    if not target or not stretcherId then
        return
    end
    
    if not HasCompatPermission(src) then
        return
    end
    
    TriggerClientEvent("amb_client:compat:loadOnStretcher", target, stretcherId)
end)

exports("RevivePlayer", function(targetSrc)
    local target = tonumber(targetSrc)
    if not target then
        return false
    end
    
    exports.plt_ambulance_job:InternalRevive(target)
    return true
end)

exports("disableKnockoutLoop", function(targetSrc, disableState)
    local target = tonumber(targetSrc)
    if not target then
        return false
    end
    
    TriggerClientEvent("amb_client:compat:setKnockoutDisabled", target, disableState == true)
    return true
end)

exports("manuallyKnockout", function(targetSrc, knockoutState)
    local target = tonumber(targetSrc)
    if not target then
        return false
    end
    
    local isKnockedOut = (knockoutState == true)
    TriggerClientEvent("amb_client:compat:manualKnockout", target, isKnockedOut)
    
    if not isKnockedOut then
        exports.plt_ambulance_job:InternalRevive(target)
    end
    
    return true
end)
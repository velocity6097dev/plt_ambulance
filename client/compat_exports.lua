-- Compatibility Exports - Ambulance Job
-- Provides backwards compatibility and utility functions for ambulance systems

local knockoutDisabled = false
local knockoutThreadRunning = false
local diagnosisRequest = nil
local radioMuteInitialized = false

-- ============ HELPER FUNCTIONS ============

--- Find the closest player to the local player
---@param maxDistance number Distance threshold (default 3.0)
---@return table|nil closestPed Ped entity of closest player
---@return number|nil serverId Server ID of closest player
---@return number distance Distance to closest player
local function GetClosestPlayer(maxDistance)
    local players = GetActivePlayers()
    local localPed = PlayerPedId()
    local localCoords = GetEntityCoords(localPed)
    
    local closestPed = nil
    local closestServerId = nil
    local closestDistance = maxDistance or 3.0
    
    for _, playerId in ipairs(players) do
        if playerId ~= PlayerId() then
            local ped = GetPlayerPed(playerId)
            if DoesEntityExist(ped) then
                local pedCoords = GetEntityCoords(ped)
                local distance = #(pedCoords - localCoords)
                
                if closestDistance >= distance then
                    closestDistance = distance
                    closestPed = ped
                    closestServerId = GetPlayerServerId(playerId)
                end
            end
        end
    end
    
    return closestPed, closestServerId, closestDistance
end

--- Trigger a server callback using promises (async/await style)
---@param callbackName string Name of server callback
---@param ... any Additional arguments to pass to callback
---@return any Response from server callback
local function PromiseCallback(callbackName, ...)
    local promise = promise.new()
    
    Framework.TriggerCallback(callbackName, function(response)
        promise:resolve(response)
    end, ...)
    
    return Citizen.Await(promise)
end

--- Request player injuries from server with timeout
---@param targetServerId number Server ID of target player
---@param timeout number Timeout in milliseconds (default 2500)
---@return table Injury data from server
local function GetDiagnosis(targetServerId, timeout)
    local serverId = tonumber(targetServerId)
    if not serverId then
        return nil
    end
    
    if diagnosisRequest then
        return nil
    end
    
    local promise = promise.new()
    diagnosisRequest = {
        targetSrc = serverId,
        promise = promise
    }
    
    TriggerServerEvent("amb_server:requestInjuries", serverId)
    
    -- Create timeout thread
    CreateThread(function()
        Wait(timeout or 2500)
        if diagnosisRequest then
            if diagnosisRequest.promise == promise then
                diagnosisRequest = nil
                promise:resolve(nil)
            end
        end
    end)
    
    local result = Citizen.Await(promise)
    TriggerServerEvent("amb_server:stopDiagnosisSync", serverId)
    return result
end

--- Find the closest vehicle within a distance
---@param maxDistance number Maximum distance to search (default 6.0)
---@return table|nil Closest vehicle entity
local function GetClosestAmbulance(maxDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local distance = maxDistance or 6.0
    
    return GetClosestVehicle(coords.x, coords.y, coords.z, distance, 0, 71)
end

--- Get the first available seat in a vehicle
---@param vehicle number Vehicle entity handle
---@return number|nil Available seat number or nil
local function GetFirstFreeSeat(vehicle)
    if not DoesEntityExist(vehicle) then
        return nil
    end
    
    local seatCount = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    
    for seat = 0, seatCount - 2 do
        if IsVehicleSeatFree(vehicle, seat) then
            return seat
        end
    end
    
    return nil
end

-- ============ NETWORK EVENTS ============

--- Receive diagnosis data from server
RegisterNetEvent("amb_client:receiveDiagnosisData", function(data)
    if diagnosisRequest then
        diagnosisRequest = nil
        diagnosisRequest.promise:resolve(data)
    end
end)

--- Disable/enable knockout system
RegisterNetEvent("amb_client:compat:setKnockoutDisabled", function(disabled)
    knockoutDisabled = (true == disabled)
end)

--- Manual knockout event
RegisterNetEvent("amb_client:compat:manualKnockout", function(knockedOut)
    if knockedOut then
        if Framework then
            if Framework.Type == "qb" then
                TriggerEvent("amb_client:SetDeathStatus", true)
            end
        else
            TriggerEvent("hospital:client:SetDeathStatus", true)
        end
    else
        exports.plt_ambulance_job:RevivePlayer()
        TriggerServerEvent("amb_server:SetDowned", false)
    end
end)

--- Apply sedative effect to player
RegisterNetEvent("amb_client:compat:applySedative", function()
    local ped = PlayerPedId()
    
    -- Don't sedate if in vehicle
    if IsPedInAnyVehicle(ped, false) then
        return
    end
    
    -- Ragdoll for 12 seconds
    SetPedToRagdoll(ped, 12000, 12000, 0, false, false, false)
end)

--- Warp player into a vehicle
RegisterNetEvent("amb_client:compat:warpIntoVehicle", function(vehicleNetId, seatIndex)
    local vehicle = NetToVeh(vehicleNetId)
    
    if DoesEntityExist(vehicle) and seatIndex then
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seatIndex)
    end
end)

--- Load player onto a stretcher (fernocot)
RegisterNetEvent("amb_client:compat:loadOnStretcher", function(stretcherNetId)
    local stretcher = NetToObj(stretcherNetId)
    
    if not DoesEntityExist(stretcher) then
        return
    end
    
    -- Get stretcher configuration with defaults
    local offset = Config.FernocotLieOffset or {x = 0.0, y = 0.0, z = 1.2}
    local heading = Config.FernocotLieHeading or 0.0
    local anim = Config.FernocotLieAnim or {
        dict = "amb@world_human_sunbathe@male@back@base",
        name = "base"
    }
    
    -- Request and play animation
    Framework.RequestAnimDict(anim.dict)
    
    local ped = PlayerPedId()
    
    -- Attach player to stretcher
    AttachEntityToEntity(
        ped, stretcher, 0,
        offset.x, offset.y, offset.z,
        0.0, 0.0, 180.0 + heading,
        false, false, false, false, 0, true
    )
    
    -- Play lying down animation
    TaskPlayAnim(
        ped, anim.dict, anim.name,
        8.0, -8.0, -1, 1, 0,
        false, false, false
    )
end)

-- ============ EXPORTS ============

--- Check if player is dead
---@param playerId number|nil Player ID (defaults to self)
---@return boolean True if player is dead
exports("isPlayerDead", function(playerId)
    if not playerId then
        local ped = PlayerPedId()
        if IsPedDeadOrDying(ped, true) then
            return true
        end
        return GetEntityHealth(ped) <= 110
    end
    
    local ped = GetPlayerPed(playerId)
    if not DoesEntityExist(ped) then
        return false
    end
    
    if IsPedDeadOrDying(ped, true) then
        return true
    end
    return GetEntityHealth(ped) <= 110
end)

--- Get injury data for a player (async)
---@param playerId number|nil Player ID (defaults to self)
---@return table Injury data
exports("GetInjuryData", function(playerId)
    if not playerId then
        playerId = PlayerId()
    end
    
    local serverId = GetPlayerServerId(playerId)
    return GetDiagnosis(serverId)
end)

--- Get injury type from local player
---@return string|nil Injury type
exports("GetInjuryType", function()
    if not exports.plt_ambulance_job:isPlayerDead() then
        return nil
    end
    
    local data = PromiseCallback("amb_server:getInjuryData")
    if data and data.injuryType then
        return data.injuryType
    end
    return nil
end)

--- Revive the player
---@return boolean Always true
exports("RevivePlayer", function()
    local ped = PlayerPedId()
    
    -- Stop all animations
    ClearPedTasks(ped)
    
    -- Restore health
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    
    -- Reset death states
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("isDead", false, true)
        LocalPlayer.state:set("inlaststand", false, true)
        LocalPlayer.state:set("dead", false, true)
    end
    
    return true
end)

--- Check if player is on a stretcher
---@param playerId number|nil Player ID (defaults to self)
---@return boolean True if on stretcher
exports("isOnStretcher", function(playerId)
    if not playerId then
        playerId = PlayerId()
    end
    
    local ped = GetPlayerPed(playerId)
    if not DoesEntityExist(ped) then
        return false
    end
    
    if not IsEntityAttached(ped) then
        return false
    end
    
    local attachedTo = GetEntityAttachedTo(ped)
    if not DoesEntityExist(attachedTo) then
        return false
    end
    
    local stretcherModel = GetHashKey(Config.FernocotModel or "fernocot")
    return GetEntityModel(attachedTo) == stretcherModel
end)

--- Clear player injuries and revive
---@param resetVitals boolean Whether to reset vitals on server
---@return boolean Always true
exports("clearPlayerInjury", function(resetVitals)
    exports.plt_ambulance_job:RevivePlayer()
    
    if resetVitals then
        TriggerServerEvent("amb_server:compat:resetVitals")
    end
    
    return true
end)

--- Disable knockout loop (prevents auto-revive)
---@param disabled boolean Whether to disable knockout
---@return boolean Current state of knockout
exports("disableKnockoutLoop", function(disabled)
    knockoutDisabled = (true == disabled)
    
    if knockoutThreadRunning then
        return knockoutDisabled
    end
    
    knockoutThreadRunning = true
    
    CreateThread(function()
        while true do
            if knockoutDisabled then
                local ped = PlayerPedId()
                
                if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 110 then
                    exports.plt_ambulance_job:RevivePlayer()
                    TriggerServerEvent("amb_server:SetDowned", false)
                    Wait(1500)
                end
            end
            
            Wait(knockoutDisabled and 300 or 1200)
        end
    end)
    
    return knockoutDisabled
end)

--- Manually knock out player
---@param knockedOut boolean Whether to knock out
---@return boolean Always true
exports("manuallyKnockout", function(knockedOut)
    if knockedOut then
        if Framework then
            if Framework.Type == "qb" then
                TriggerEvent("amb_client:SetDeathStatus", true)
            end
        else
            TriggerEvent("hospital:client:SetDeathStatus", true)
        end
        return true
    end
    
    exports.plt_ambulance_job:RevivePlayer()
    TriggerServerEvent("amb_server:SetDowned", false)
    return true
end)

-- ============ DEATH STATE CHECKING ============

--- Check if local player is in a dead state
---@return boolean True if player is dead
local function IsPlayerDead()
    local ped = PlayerPedId()
    
    if not (ped and ped ~= 0) then
        return false
    end
    
    if not DoesEntityExist(ped) then
        return false
    end
    
    -- Check state table first
    if LocalPlayer and LocalPlayer.state then
        local state = LocalPlayer.state
        if state.isDead == true or state.inlaststand == true or state.dead == true then
            return true
        end
    end
    
    -- Fall back to health/animation checks
    if IsPedDeadOrDying(ped, true) then
        return true
    end
    
    return GetEntityHealth(ped) <= 120
end

-- ============ RADIO MUTING SYSTEM ============

--- Handle radio muting when player dies/revives
local function HandleRadioMute()
    local isDead = IsPlayerDead()
    
    if not isDead then
        -- Unmute radio
        if LocalPlayer and LocalPlayer.state then
            LocalPlayer.state:set("radioMutedByDeath", false, true)
        end
        
        if radioMuteInitialized then
            -- Re-enable Mumble
            pcall(function()
                MumbleSetPlayerMuted(PlayerId(), false)
            end)
            
            -- Re-enable pma-voice radio
            if GetResourceState("pma-voice") == "started" then
                pcall(function()
                    exports["pma-voice"]:setVoiceProperty("radioEnabled", true)
                end)
            end
            
            radioMuteInitialized = false
        end
        
        return false
    end
    
    -- Mute radio when dead
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("radioMutedByDeath", true, true)
    end
    
    -- Mute Mumble
    pcall(function()
        MumbleSetPlayerMuted(PlayerId(), true)
    end)
    
    -- Disconnect from pma-voice radio
    if GetResourceState("pma-voice") == "started" then
        pcall(function()
            exports["pma-voice"]:setRadioChannel(0)
            exports["pma-voice"]:setVoiceProperty("radioEnabled", false)
        end)
    end
    
    -- Trigger various radio disconnect events for different frameworks
    TriggerEvent("qb-radio:client:LeaveChannel")
    TriggerEvent("qb-radio:client:disconnect")
    TriggerEvent("qbx_radio:client:leaveChannel")
    TriggerEvent("esx_radio:leaveRadio")
    TriggerEvent("gcphone:removeRadio")
    TriggerEvent("tgiann-radio:client:CloseRadio")
    
    radioMuteInitialized = true
    return true
end

--- Export radio mute check
exports("ShouldForceRadioMute", function()
    return IsPlayerDead()
end)

--- Export radio mute handler
exports("ForceMuteRadioIfDead", function()
    return HandleRadioMute()
end)

-- ============ RADIO MUTE LOOP ============

--- Continuously monitor and update radio mute status
CreateThread(function()
    while true do
        HandleRadioMute()
        Wait(IsPlayerDead() and 1000 or 2000)
    end
end)
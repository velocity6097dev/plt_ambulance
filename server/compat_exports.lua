-- =============================================================================
-- plt_ambulance | Compatibility Exports & Net Events
-- Provides server-side bridges so external resources can interact with the
-- ambulance job without depending on its internals directly.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Local helper: check whether a server ID is authorised to perform EMS actions.
-- Console (src == 0) is always allowed.
-- ---------------------------------------------------------------------------
local function IsAuthorised(src)
    if src == 0 then return true end

    -- Primary check: boss/admin permission from the framework
    if Framework.HasPermission(src, Config.Permission) then return true end

    -- Fallback: check if the player is an active EMS unit
    return exports.plt_ambulance_job:IsEMS(src)
end

-- =============================================================================
-- Net event: reset vitals (hunger → 100, thirst → 100, stress → 0)
-- Triggered by the client on themselves after a revive / treatment.
-- =============================================================================
RegisterNetEvent("amb_server:compat:resetVitals")
AddEventHandler("amb_server:compat:resetVitals", function()
    local src = source
    if not src then return end

    Framework.SetMetaData(src, "hunger", 100)
    Framework.SetMetaData(src, "thirst", 100)
    Framework.SetMetaData(src, "stress",   0)
end)

-- =============================================================================
-- Net event: sedate a target player
-- The requesting player must be an authorised EMS.
-- Fires "amb_client:compat:applySedative" on the target client.
-- =============================================================================
RegisterNetEvent("amb_server:compat:sedateTarget")
AddEventHandler("amb_server:compat:sedateTarget", function(targetSrcRaw)
    local src       = source
    local targetSrc = tonumber(targetSrcRaw)
    if not targetSrc then return end
    if not IsAuthorised(src) then return end

    TriggerClientEvent("amb_client:compat:applySedative", targetSrc)
end)

-- =============================================================================
-- Net event: place a player into a vehicle seat
-- Args:
--   targetSrcRaw  – server ID of the player to move
--   vehicleNetId  – network ID of the vehicle
--   seatIndex     – seat index (number, 0 = driver)
-- Fires "amb_client:compat:warpIntoVehicle" on the target client.
-- =============================================================================
RegisterNetEvent("amb_server:compat:placeInVehicle")
AddEventHandler("amb_server:compat:placeInVehicle", function(targetSrcRaw, vehicleNetId, seatIndex)
    local src       = source
    local targetSrc = tonumber(targetSrcRaw)
    local seat      = tonumber(seatIndex)

    -- All three values are required; seat 0 (driver) is valid so check for nil explicitly
    if not (targetSrc and vehicleNetId) or seat == nil then return end
    if not IsAuthorised(src) then return end

    TriggerClientEvent("amb_client:compat:warpIntoVehicle", targetSrc, vehicleNetId, seat)
end)

-- =============================================================================
-- Net event: load a player onto a stretcher
-- Args:
--   targetSrcRaw – server ID of the patient
--   stretcherNetId – network ID of the stretcher entity
-- Fires "amb_client:compat:loadOnStretcher" on the target client.
-- =============================================================================
RegisterNetEvent("amb_server:compat:loadOnStretcher")
AddEventHandler("amb_server:compat:loadOnStretcher", function(targetSrcRaw, stretcherNetId)
    local src       = source
    local targetSrc = tonumber(targetSrcRaw)

    if not (targetSrc and stretcherNetId) then return end
    if not IsAuthorised(src) then return end

    TriggerClientEvent("amb_client:compat:loadOnStretcher", targetSrc, stretcherNetId)
end)

-- =============================================================================
-- Export: RevivePlayer(serverId)
-- Revives a player by their server ID.
-- Returns true on success, false if the ID is invalid.
-- Usage (from another resource):
--   exports.plt_ambulance_job:RevivePlayer(serverId)
-- =============================================================================
exports("RevivePlayer", function(srcRaw)
    local src = tonumber(srcRaw)
    if not src then return false end

    exports.plt_ambulance_job:InternalRevive(src)
    return true
end)

-- =============================================================================
-- Export: disableKnockoutLoop(serverId, disabled)
-- Enables or disables the knockout loop for a specific player.
-- Returns true on success, false if the ID is invalid.
-- =============================================================================
exports("disableKnockoutLoop", function(srcRaw, disabled)
    local src = tonumber(srcRaw)
    if not src then return false end

    TriggerClientEvent("amb_client:compat:setKnockoutDisabled", src, disabled == true)
    return true
end)

-- =============================================================================
-- Export: manuallyKnockout(serverId, keepDown)
-- Knocks out a player manually.
--   keepDown = true  → player stays down (no auto-revive loop)
--   keepDown = false → knockout fires but InternalRevive is also called
--                      (e.g. to force-play the animation then stand them up)
-- Returns true on success, false if the ID is invalid.
-- =============================================================================
exports("manuallyKnockout", function(srcRaw, keepDown)
    local src      = tonumber(srcRaw)
    if not src then return false end

    local stay = (keepDown == true)

    TriggerClientEvent("amb_client:compat:manualKnockout", src, stay)

    -- If not keeping them down, immediately revive so they recover after the anim
    if not stay then
        exports.plt_ambulance_job:InternalRevive(src)
    end

    return true
end)

-- =============================================================================
-- plt_ambulance | Dispatch – Server
-- Manages incoming dispatch calls: normalises call data, stores a rolling
-- history, and broadcasts calls to all online EMS players.
-- =============================================================================

-- Rolling list of the last 100 dispatch calls (newest at index 1).
local activeCalls = {}

-- =============================================================================
-- Internal: normalise a raw call-data table into a clean dispatch call object.
-- Returns the normalised table, or nil if the input is not a table.
-- =============================================================================
local function NormaliseCallData(raw)
    if type(raw) ~= "table" then return nil end

    -- Shallow-copy so we never mutate the caller's table
    local call = {}
    for k, v in pairs(raw) do
        call[k] = v
    end

    -- Defaults
    call.id       = call.id       or math.random(1000, 9999)
    call.source   = call.source   or 0
    call.time     = call.time     or os.date("%H:%M")
    call.code     = call.code     or "10-52"
    call.title    = call.title    or "Medical Alert"
    call.location = call.location or call.locationName or "Unknown Location"
    call.info     = call.info     or call.type         or ""

    -- Normalise coords to a plain { x, y, z } table regardless of input type
    local coords = call.coords
    local coordType = type(coords)

    if coordType == "vector3" then
        -- Native vector3 – serialise to plain table for JSON compatibility
        call.coords = { x = coords.x, y = coords.y, z = coords.z }

    elseif coordType == "table" then
        -- Accept both named keys { x, y, z } and positional { [1], [2], [3] }
        call.coords = {
            x = tonumber(coords.x  or coords[1]) or 0.0,
            y = tonumber(coords.y  or coords[2]) or 0.0,
            z = tonumber(coords.z  or coords[3]) or 0.0,
        }

    else
        -- No coords provided – default to origin
        call.coords = { x = 0.0, y = 0.0, z = 0.0 }
    end

    return call
end

-- =============================================================================
-- Internal: prepend a call to activeCalls, capping the list at 100 entries.
-- =============================================================================
local function StoreCall(call)
    table.insert(activeCalls, 1, call)
    if #activeCalls > 100 then
        table.remove(activeCalls) -- drop the oldest entry
    end
end

-- =============================================================================
-- Internal: validate, store, and broadcast a dispatch call.
-- srcOverride is the server ID to attribute the call to (0 for system/external).
-- Returns true on success, false on invalid input.
-- =============================================================================
local function ProcessDispatchCall(callData, srcOverride)
    local src = tonumber(srcOverride) or 0

    print("^2[Dispatch]^7 Received dispatch call from source: " .. tostring(src))

    if type(callData) ~= "table" then
        print("^1[Dispatch Error]^7 Invalid callData received from " .. tostring(src))
        return false
    end

    -- Stamp the source onto the raw data before normalising
    if not callData.source then
        callData.source = src
    end

    local call = NormaliseCallData(callData)
    if not call then return false end

    StoreCall(call)

    -- Broadcast to every online EMS player
    local players    = Framework.GetPlayers()
    local sentCount  = 0

    print(("^2[Dispatch]^7 Checking %d online players for EMS jobs..."):format(#players))

    for _, svId in ipairs(players) do
        local playerSrc = tonumber(svId)
        if exports.plt_ambulance_job:IsEMS(playerSrc) then
            TriggerClientEvent("amb_client:addDispatchCall",        playerSrc, call)
            TriggerClientEvent("plt_mdt_ems:client:newDispatchCall", playerSrc, call)
            sentCount = sentCount + 1
        end
    end

    print(("^2[Dispatch]^7 Result: Call distributed to %d EMS members."):format(sentCount))
    return true
end

-- =============================================================================
-- Net event: send a dispatch call from an in-game player.
-- The caller's server ID is automatically used as the call source.
-- =============================================================================
RegisterNetEvent("amb_server:sendDispatchCall")
AddEventHandler("amb_server:sendDispatchCall", function(callData)
    ProcessDispatchCall(callData, source)
end)

-- =============================================================================
-- Export: SendExternalDispatch(callData, srcOverride)
-- Allows other resources to create dispatch calls server-side.
-- srcOverride defaults to 0 (system) if not provided.
-- Usage:
--   exports.plt_ambulance_job:SendExternalDispatch({ title = "...", coords = {...} })
-- =============================================================================
exports("SendExternalDispatch", function(callData, srcOverride)
    return ProcessDispatchCall(callData, srcOverride or 0)
end)

-- =============================================================================
-- Export: GetActiveDispatchCalls()
-- Returns the full rolling call history (newest first, max 100).
-- Usage:
--   local calls = exports.plt_ambulance_job:GetActiveDispatchCalls()
-- =============================================================================
exports("GetActiveDispatchCalls", function()
    return activeCalls
end)

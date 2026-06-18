-- ============================================================
-- dispatch.lua  –  EMS Dispatch System (Client)
-- ============================================================

print("^2[Dispatch]^7 Dispatch system loaded.")

-- ── Module-level state ──────────────────────────────────────
local isDispatchOpen  = false  -- whether the dispatch UI is currently visible
local isDispatchLocked = false -- whether the UI is in a "locked" (no NUI focus) state
local activeCall      = nil    -- the currently selected dispatch call table


-- ── Helper: is the local player authorised to use dispatch? ──
-- Returns true for EMS job members (checked via export first,
-- then by matching Config.Medical.EMSJobs against the player's job).
local function isAuthorised()
    -- Fast path: the ambulance job export knows best.
    if exports.plt_ambulance_job:IsEMS() then
        return true
    end

    -- Fallback: check the Framework player data against the config list.
    local playerData = Framework.GetPlayerData()
    local jobName    = playerData and playerData.job and playerData.job.name

    if not jobName then
        return false
    end

    local emsJobs = (Config.Medical and Config.Medical.EMSJobs) or {}

    for _, allowedJob in ipairs(emsJobs) do
        if tostring(jobName) == tostring(allowedJob) then
            return true
        end
    end

    return false
end


-- ── toggleDispatch(forceState?) ──────────────────────────────
-- Opens or closes the dispatch NUI panel.
-- Pass `true` to force-open, `false` to force-close, or omit to
-- flip the current state.
local function toggleDispatch(forceState)
    if forceState ~= nil then
        isDispatchOpen = forceState
    else
        isDispatchOpen = not isDispatchOpen
    end

    print("^2[Dispatch]^7 Toggling dispatch UI: " .. tostring(isDispatchOpen))

    SendNUIMessage({ action = "amb_toggleDispatch", show = isDispatchOpen })
    SetNuiFocus(isDispatchOpen, isDispatchOpen)
end


-- ── NUI → toggle (called from within the NUI panel itself) ───
RegisterNUICallback("toggleDispatch", function(_, cb)
    toggleDispatch()
    cb("ok")
end)


-- ── Command: /forcedispatch  (no auth check, for admins/debug) ─
RegisterCommand("forcedispatch", function()
    toggleDispatch(true)
end, false)


-- ── Command: /dispatch  (EMS-authorised players only) ────────
RegisterCommand("dispatch", function()
    if isAuthorised() then
        toggleDispatch()
    else
        Framework.Notify(_L("authorized_only"), "error")
    end
end, false)


-- ── NUI: lock / unlock the dispatch panel ────────────────────
-- When locked, NUI focus is released (so the player can move).
-- When unlocked and the panel is open, focus is restored.
RegisterNUICallback("lockDispatch", function(data, cb)
    isDispatchLocked = (data and data.locked == true) or false

    if isDispatchLocked then
        SetNuiFocus(false, false)
        Framework.Notify(_L("dispatch_locked"), "success")
    elseif isDispatchOpen then
        SetNuiFocus(true, true)
    end

    cb("ok")
end)


-- ── NUI: set a GPS waypoint from a dispatch call ─────────────
RegisterNUICallback("setDispatchGPS", function(data, cb)
    if not data.x or not data.y then return end

    SetNewWaypoint(data.x, data.y)
    Framework.Notify(_L("gps_set"), "success")
    cb("ok")
end)


-- ── NUI: dismiss (clear) a dispatch call ─────────────────────
RegisterNUICallback("dismissDispatchCall", function(data, cb)
    local callId = data and data.id

    if not callId then
        -- No id provided; just clear whatever is active.
        activeCall = nil
        cb("ok")
        return
    end

    -- Only clear activeCall if it matches the dismissed id.
    if activeCall and tostring(activeCall.id) == tostring(callId) then
        activeCall = nil
    end

    cb("ok")
end)


-- ── NUI: set the currently focused dispatch call ─────────────
RegisterNUICallback("setActiveDispatchCall", function(data, cb)
    local call = data and data.call
    activeCall = (type(call) == "table") and call or nil
    cb("ok")
end)


-- ── sendDeathDispatch() ──────────────────────────────────────
-- Resolves the local player's street address and fires a
-- "patient downed" dispatch call to the server.
local function sendDeathDispatch()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local locationName = GetStreetNameFromHashKey(streetHash)

    if crossingHash ~= 0 then
        locationName = locationName .. " / " .. GetStreetNameFromHashKey(crossingHash)
    end

    print("^2[Dispatch]^7 Sending death dispatch for location: " .. locationName)

    TriggerServerEvent("amb_server:sendDispatchCall", {
        title        = _L("patient_downed"),
        coords       = { x = coords.x, y = coords.y },
        locationName = locationName,
    })
end

-- Expose as a global and as a resource export.
SendDeathDispatch = sendDeathDispatch
exports("SendDeathDispatch", function(overrides)
    -- Allow callers to pass a partial data table to override defaults.
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local locationName = GetStreetNameFromHashKey(streetHash)

    if crossingHash ~= 0 then
        locationName = locationName .. " / " .. GetStreetNameFromHashKey(crossingHash)
    end

    local callData = (type(overrides) == "table") and overrides or {}

    callData.title        = callData.title        or _L("patient_downed")
    callData.coords       = callData.coords       or { x = coords.x, y = coords.y }
    callData.locationName = callData.locationName or locationName

    TriggerServerEvent("amb_server:sendDispatchCall", callData)
end)


-- ── NET: server pushes a new dispatch call to this client ────
RegisterNetEvent("amb_client:addDispatchCall")
AddEventHandler("amb_client:addDispatchCall", function(call)
    activeCall = call
    SendNUIMessage({ action = "amb_addDispatchCall", call = call })
end)


-- ── Input thread: hotkeys while the dispatch panel is open ───
-- Control 38  = ENTER  → set GPS waypoint from the active call
-- Control 246 = BACK   → dismiss the active call
CreateThread(function()
    while true do
        if isDispatchOpen and activeCall then
            Wait(0)

            -- ENTER: navigate to the active call's location.
            if IsControlJustPressed(0, 38) then
                local c  = activeCall.coords or {}
                local cx = tonumber(c.x or c[1])
                local cy = tonumber(c.y or c[2])

                if cx and cy then
                    SetNewWaypoint(cx, cy)
                    Framework.Notify(_L("gps_set"), "success")
                end

            -- BACK: dismiss the active call.
            elseif IsControlJustPressed(0, 246) then
                local dismissedId = activeCall and activeCall.id
                activeCall = nil
                SendNUIMessage({ action = "amb_removeDispatchCall", id = dismissedId })
            end

        else
            -- Panel is closed; poll infrequently to save frames.
            Wait(250)
        end
    end
end)
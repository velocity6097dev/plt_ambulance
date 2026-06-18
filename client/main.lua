-- ============================================================
--  plt_ambulance  –  client/main.lua  (deobfuscated)
--  FiveM ambulance / EMS resource client script.
--  Supports QBCore and ESX frameworks, ox_target / qb-target,
--  ox_inventory / qb-inventory and various clothing resources.
-- ============================================================

-- ----------------------------------------------------------------
--  Module-level state
-- ----------------------------------------------------------------

local mapBlips          = {}    -- active map blips keyed by node id
local locationZones     = {}    -- target zones for location-type nodes
local checkinZones      = {}    -- target zones for check-in nodes
local patientBlips      = {}    -- blips placed above downed patients
local savedCivilianOutfit = nil -- cached civilian clothes table
local vehicleSpawnInfo  = {}    -- vehicle / delete-point data per zone
local locationPeds      = {}    -- NPC doctor peds keyed by zone id
local xrayPeds          = {}    -- x-ray scene peds keyed by zone id
local bedsideObjects    = {}    -- interaction objects keyed by zone id
local monitorPanels     = {}    -- active vitals-monitor panels
local defaultHealRadius = 10.0  -- default radius for local-doctor nodes
local monitorPowerState = {}    -- on/off state per monitor entity id
local isPlayerOnBed     = false -- whether the local player is lying on a bed
local currentBedAnim    = nil   -- { ad, anim } table of the active bed animation
local requestCounter    = 0     -- monotonic counter used to detect stale callbacks
local checkInTargets    = {}    -- ox_target / qb-target zone ids for check-in nodes

-- ----------------------------------------------------------------
--  Utility: remove all target zones stored in a table
-- ----------------------------------------------------------------
local function ClearTargetZones(zones)
    for _, zoneId in pairs(zones) do
        if type(zoneId) == "number" then
            -- ox_target stores numeric zone IDs
            if DoesEntityExist(zoneId) then
                DeleteEntity(zoneId)
            else
                if Config.Target == "ox_target" then
                    exports.ox_target:removeZone(zoneId)
                end
            end
        else
            -- qb-target stores string zone names
            if type(zoneId) == "string" then
                if Config.Target == "qb-target" then
                    exports["qb-target"]:RemoveZone(zoneId)
                end
            end
        end
    end
    return {}
end

-- ----------------------------------------------------------------
--  Utility: get a new unique request-token
-- ----------------------------------------------------------------
local function NewRequestToken()
    requestCounter = requestCounter + 1
    return requestCounter
end

-- ----------------------------------------------------------------
--  Utility: check whether a token is still current
-- ----------------------------------------------------------------
local function IsCurrentToken(token)
    return token == requestCounter
end

-- ----------------------------------------------------------------
--  Utility: trim whitespace from both ends of a string
-- ----------------------------------------------------------------
local function Trim(value)
    local str = tostring(value or "")
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    return str
end

-- ----------------------------------------------------------------
--  Give vehicle keys to the local player for the given ped/vehicle
-- ----------------------------------------------------------------
local function GiveVehicleKeys(vehicle)
    if not vehicle or vehicle == 0 then return end
    if not DoesEntityExist(vehicle) then return end

    local plate = Trim(GetVehicleNumberPlateText(vehicle))
    if plate == "" then return end

    if GetResourceState("qb-vehiclekeys") == "started" then
        TriggerEvent("vehiclekeys:client:SetOwner", plate)
        TriggerEvent("qb-vehiclekeys:client:AddKeys", plate)
        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", plate)
    elseif GetResourceState("qbx_vehiclekeys") == "started" then
        exports.qbx_vehiclekeys:GiveKeys(plate)
    end
end

-- ----------------------------------------------------------------
--  Delete all active xray peds and their monitor panels
-- ----------------------------------------------------------------
local function ClearXrayScene()
    for _, ped in pairs(xrayPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    xrayPeds = {}

    for _, panelId in pairs(monitorPanels) do
        TriggerEvent("plt_xray:client:destroyPanel", panelId)
    end
    monitorPanels = {}

    bedsideObjects = {}
end

-- ----------------------------------------------------------------
--  Create a vitals monitor panel on the given entity (if plt_xray loaded)
-- ----------------------------------------------------------------
local function CreateMonitorPanel(entity, screenNormal, screenUp)
    if not DoesEntityExist(entity) then return end

    if GetResourceState("plt_xray") == "started" then
        TriggerEvent("plt_xray:client:createMonitorPanel", entity, screenNormal, screenUp)
    else
        print("^3[plt_ambulance] plt_xray not started yet; monitor panel queued for refresh.^7")
    end
end

-- ----------------------------------------------------------------
--  Build the KVP key used to store civilian clothes per player
-- ----------------------------------------------------------------
local function GetCivilianClothesKey()
    local playerData = Framework.GetPlayerData()
    local id
    if playerData then
        id = playerData.citizenid or playerData.identifier or playerData.license
    end
    if not id then
        id = GetPlayerServerId(PlayerId())
    end
    return ("plt_amb_civilian_clothes_%s"):format(tostring(id))
end

-- ----------------------------------------------------------------
--  Save the local player's current outfit as their civilian clothes
-- ----------------------------------------------------------------
local function SaveCivilianClothes()
    local ped = PlayerPedId()
    local outfit = {}

    for component = 0, 11 do
        outfit[component] = {
            drawable = GetPedDrawableVariation(ped, component),
            texture  = GetPedTextureVariation(ped, component),
            palette  = GetPedPaletteVariation(ped, component),
        }
    end

    outfit.props = {}
    for prop = 0, 7 do
        outfit.props[prop] = {
            drawable = GetPedPropIndex(ped, prop),
            texture  = GetPedPropTextureIndex(ped, prop),
        }
    end

    savedCivilianOutfit = outfit

    local key     = GetCivilianClothesKey()
    local encoded = json.encode(outfit)
    if key and encoded then
        pcall(function() SetResourceKvp(key, encoded) end)
    end
end

-- ----------------------------------------------------------------
--  Restore the local player's saved civilian clothes.
--  Falls back to the clothing resource if no saved outfit is found.
-- ----------------------------------------------------------------
local function RestoreCivilianClothes()
    -- Inner helper: try to reload skin via a supported clothing resource
    local function ReloadViaClothingResource()
        if GetResourceState("qb-clothing") == "started" then
            TriggerEvent("qb-clothing:client:loadPlayerSkin")
            return true
        end
        if GetResourceState("illenium-appearance") == "started" then
            TriggerEvent("illenium-appearance:client:reloadSkin")
            return true
        end
        if GetResourceState("origen_clothing") == "started" then
            TriggerEvent("origen_clothing:client:reloadSkin")
            return true
        end
        if GetResourceState("rclothing") == "started" then
            TriggerEvent("rclothing:client:reloadSkin")
            return true
        end
        if GetResourceState("esx_skin") == "started" then
            TriggerEvent("esx_skin:getPlayerSkin", function(skin)
                TriggerEvent("skinchanger:loadSkin", skin)
            end)
            return true
        end
        return false
    end

    local ped = PlayerPedId()

    if not savedCivilianOutfit then
        -- Try to load from KVP storage
        local key = GetCivilianClothesKey()
        local loaded = nil
        if key then
            local raw
            pcall(function() raw = GetResourceKvpString(key) end)
            if raw and raw ~= "" then
                local ok, decoded = pcall(json.decode, raw)
                if ok and type(decoded) == "table" then
                    loaded = decoded
                end
            end
        end
        savedCivilianOutfit = loaded

        if not savedCivilianOutfit then
            -- Nothing saved – fall back to clothing resource
            ReloadViaClothingResource()
            return
        end
    end

    -- Apply saved component variations
    for component = 0, 11 do
        local slot = savedCivilianOutfit[component]
        if slot then
            SetPedComponentVariation(ped, component, slot.drawable, slot.texture, slot.palette)
        end
    end

    -- Apply saved prop variations
    for prop = 0, 7 do
        local slot = savedCivilianOutfit.props and savedCivilianOutfit.props[prop]
        if slot then
            if slot.drawable == -1 then
                ClearPedProp(ped, prop)
            else
                SetPedPropIndex(ped, prop, slot.drawable, slot.texture, true)
            end
        end
    end

    -- Clear cache and KVP now that the outfit has been applied
    savedCivilianOutfit = nil
    local key = GetCivilianClothesKey()
    if key then
        pcall(function() DeleteResourceKvp(key) end)
    end
end

-- ----------------------------------------------------------------
--  Apply the EMS rank outfit for the local player from a wardrobe node
-- ----------------------------------------------------------------
local function WearEMSOutfit(nodeId)
    if not DepartmentData or not DepartmentData.nodes then return false end

    -- Find the matching wardrobe node
    local wardrobeNode = nil
    for _, node in ipairs(DepartmentData.nodes) do
        if tostring(node.id) == tostring(nodeId) and node.type == "wardrobe" then
            wardrobeNode = node
            break
        end
    end

    if not wardrobeNode or type(wardrobeNode.outfits) ~= "table" then return false end

    local playerData = Framework.GetPlayerData()
    if not playerData or not playerData.job then return false end

    -- Determine rank
    local gradeRaw = type(playerData.job.grade) == "table"
                     and playerData.job.grade.level or playerData.job.grade
    local grade = tonumber(gradeRaw) or 0
    local outfitKey = "rank_" .. tostring(grade)
    local outfit = wardrobeNode.outfits[outfitKey]

    if type(outfit) ~= "table" then return false end

    -- Save civilian outfit before changing
    if not savedCivilianOutfit then SaveCivilianClothes() end

    local ped = PlayerPedId()

    -- Helper to apply a single component slot
    local function ApplyComponent(component, slot)
        if type(slot) ~= "table" then return end
        local drawable = tonumber(slot.item)
        if drawable == nil then return end
        local texture = tonumber(slot.texture) or 0
        SetPedComponentVariation(ped, component, drawable, texture, 0)
    end

    ApplyComponent(4,  outfit.pants)
    ApplyComponent(11, outfit.shirt)
    ApplyComponent(9,  outfit.vest)
    ApplyComponent(6,  outfit.shoes)

    -- Hat is a prop (index 0)
    if type(outfit.hat) == "table" and outfit.hat.item ~= nil then
        local hatDrawable = tonumber(outfit.hat.item) or -1
        local hatTexture  = tonumber(outfit.hat.texture) or 0
        if hatDrawable < 0 then
            ClearPedProp(ped, 0)
        else
            SetPedPropIndex(ped, 0, hatDrawable, hatTexture, true)
        end
    end

    return true
end

-- ================================================================
--  Network events (server → client)
-- ================================================================

RegisterNetEvent("amb_client:Notify")
AddEventHandler("amb_client:Notify", function(message, notifType)
    if not Config.ShowNotifications then return end

    local title = _L("notify_title_alert")
    if     notifType == "error"   then title = _L("notify_title_error")
    elseif notifType == "success" then title = _L("notify_title_success")
    elseif notifType == "primary" then title = _L("notify_title_info")
    elseif notifType == "info"    then title = _L("notify_title_info")
    elseif notifType == "warning" then title = _L("notify_title_warning")
    end

    SendNUIMessage({ action = "amb_showNotification", title = title, message = message })
end)

RegisterNetEvent("amb_client:PushLocaleToUI")
AddEventHandler("amb_client:PushLocaleToUI", function(locale)
    SendNUIMessage({ action = "amb_setLocale", locale = locale or {} })
end)

-- ----------------------------------------------------------------
--  Push UI settings (e.g. blur effect) to the NUI
-- ----------------------------------------------------------------
local function PushUISettings()
    SendNUIMessage({
        action      = "amb_setUISettings",
        blurEnabled = Config.EnableBlurEffect ~= false,
    })
end

CreateThread(function()
    Wait(500)
    PushUISettings()
end)

-- ================================================================
--  Global state initialised once data loads
-- ================================================================

DepartmentData = { nodes = {}, links = {} }
MemberData     = {}
LocalPlayerJob = { dept = "none", grade = 0, onDuty = false }

-- ----------------------------------------------------------------
--  Given a node id, walk the department graph and return the
--  frameworkJob string of the department that owns it.
-- ----------------------------------------------------------------
local function GetFrameworkJobForNode(nodeId)
    if not DepartmentData or not DepartmentData.nodes then return nodeId end

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" and tostring(node.id) == tostring(nodeId) then
            if node.frameworkJob and node.frameworkJob ~= "" then
                return node.frameworkJob
            end
            return nodeId
        end
    end
    return nodeId
end

-- ----------------------------------------------------------------
--  Check if the local player has access to a given department/node.
--  Pass nil for departmentId to check "is the player any EMS".
-- ----------------------------------------------------------------
local function IsPlayerInDepartment(departmentId)
    if not departmentId then return true end

    local playerData = Framework.GetPlayerData()
    if not playerData then return false end

    if IsAdmin and IsAdmin() and Config.AdminBypass then return true end

    local jobName = (playerData.job and playerData.job.name) or "none"
    local memberJob = "none"
    if playerData.citizenid then
        local member = MemberData[playerData.citizenid]
        if member then memberJob = member.job or "none" end
    end

    local frameworkJob = GetFrameworkJobForNode(departmentId)

    -- Direct match against raw or resolved job name
    if tostring(jobName) == tostring(departmentId)
    or tostring(jobName) == tostring(frameworkJob)
    or tostring(memberJob) == tostring(departmentId) then
        return true
    end

    -- Check against configured EMS job list
    for _, emsJob in ipairs(Config.Medical.EMSJobs) do
        if (jobName == emsJob or memberJob == emsJob) then
            if tostring(departmentId) ~= tostring(emsJob)
            and tostring(frameworkJob) ~= tostring(emsJob) then
                -- still counts
            end
            return true
        end
    end

    return false
end

-- ----------------------------------------------------------------
--  Return true if the local player is an EMS worker (any department)
-- ----------------------------------------------------------------
local function IsEMSWorker()
    local playerData = Framework.GetPlayerData()
    if not playerData then return false end

    if IsAdmin and IsAdmin() and Config.AdminBypass then return true end

    local jobName = (playerData.job and playerData.job.name) or "none"
    local memberJob = "none"
    if playerData.citizenid then
        local member = MemberData[playerData.citizenid]
        if member then memberJob = member.job or "none" end
    end

    -- Check configured EMS job list
    for _, emsJob in ipairs(Config.Medical.EMSJobs) do
        if jobName == emsJob or memberJob == emsJob then return true end
    end

    -- Check all department nodes
    if not DepartmentData or not DepartmentData.nodes then return false end
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            local jobToMatch = (node.frameworkJob and node.frameworkJob ~= "")
                               and node.frameworkJob or node.id
            if tostring(jobName) == tostring(node.id)
            or tostring(jobName) == tostring(jobToMatch)
            or tostring(memberJob) == tostring(node.id) then
                return true
            end
        end
    end

    return false
end

IsEMS = IsEMSWorker
exports("IsEMS", IsEMS)

-- ----------------------------------------------------------------
--  Permission vars updated by server callback
-- ----------------------------------------------------------------
local isAdminPlayer      = false
local serverPermResult   = false

local function CheckServerPermissions()
    Framework.TriggerCallback("amb_server:checkPermissions", function(result)
        serverPermResult = result
    end, Config.Permission)
end

-- ================================================================
--  Vector / math helpers
-- ================================================================

--- Returns the unit forward vector for a heading (degrees).
local function HeadingToForwardVector(heading)
    local rad = math.rad(heading)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

--- Normalise a vector3; returns zero vector if length is near-zero.
local function NormaliseVector(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len <= 1e-4 then return vector3(0, 0, 0) end
    return vector3(v.x / len, v.y / len, v.z / len)
end

--- Rodrigues' rotation: rotate vector `v` around axis `axis` by `angleDeg`.
local function RotateVector(v, axis, angleDeg)
    local rad   = math.rad(angleDeg)
    local cosA  = math.cos(rad)
    local sinA  = math.sin(rad)
    local cross = vector3(
        axis.y * v.z - axis.z * v.y,
        axis.z * v.x - axis.x * v.z,
        axis.x * v.y - axis.y * v.x
    )
    local dot = axis.x * v.x + axis.y * v.y + axis.z * v.z
    return v * cosA + cross * sinA + axis * dot * (1 - cosA)
end

--- Given a coordsList entry with .h and optional .pitch, return
--- (screenNormal, screenUp) for placing a 2D panel in world space.
local function GetScreenOrientationVectors(coordsEntry)
    local forward = NormaliseVector(HeadingToForwardVector(coordsEntry.h or 0.0))
    local up      = vector3(0.0, 0.0, 1.0)
    local pitch   = tonumber(coordsEntry.pitch) or 0.0

    if math.abs(pitch) > 0.001 then
        local right = NormaliseVector(vector3(
            forward.y * up.z    - forward.z * up.y,
            forward.z * up.x    - forward.x * up.z,
            forward.x * up.y    - forward.y * up.x
        ))
        forward = NormaliseVector(RotateVector(forward, right, pitch))
        up      = NormaliseVector(RotateVector(up,      right, pitch))
    end

    return forward, up
end

-- ----------------------------------------------------------------
--  Label helpers
-- ----------------------------------------------------------------

--- Return a human-readable label for a node type.
--- If the type string looks like a "new X" admin command, return
--- the proposed label instead.
local function GetCleanLabel(typeString, proposedLabel)
    if typeString and typeString ~= "" then
        local lower = typeString:lower()
        if lower:find("new location") or lower:find("new department")
        or lower:find("new boss")     or lower:find("new vehicle")
        or lower:find("new armory")   or lower:find("new door")
        or lower:find("new rank")     or lower:find("new permission") then
            return proposedLabel
        end
    end
    if typeString and proposedLabel then
        if typeString:lower() == proposedLabel:lower() then
            return proposedLabel
        end
    end
    return typeString
end

GetCleanLabel = GetCleanLabel
exports("GetFramework", function() return Framework end)

-- ================================================================
--  Graph traversal helpers
-- ================================================================

--- BFS through the department graph starting at `startId`,
--- looking for the first node of `targetType`.
--- Returns the node table or nil.
local function GetLinkedNodeByType(startId, targetType, data)
    if not data or not data.links or not data.nodes then return nil end

    local startStr = tostring(startId)
    local visited  = { [startStr] = true }
    local queue    = { startStr }

    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, link in ipairs(data.links) do
            local neighbour = nil
            if tostring(link.to) == current then
                neighbour = tostring(link.from)
            elseif tostring(link.from) == current then
                neighbour = tostring(link.to)
            end

            if neighbour and not visited[neighbour] then
                for _, node in ipairs(data.nodes) do
                    if tostring(node.id) == neighbour then
                        if node.type == targetType then return node end
                        visited[neighbour] = true
                        table.insert(queue, neighbour)
                        break
                    end
                end
            end
        end
    end

    return nil
end

GetLinkedNodeByType = GetLinkedNodeByType

--- Walk up the graph from `nodeId` and return the id of the
--- first ancestor that is a "department" node, or nil.
local function GetDepartmentForNode(nodeId, data)
    if not data or not data.links then return nil end

    local nodeStr = tostring(nodeId)

    -- Check if this node is itself a department
    for _, node in ipairs(data.nodes) do
        if tostring(node.id) == nodeStr and node.type == "department" then
            return node.id
        end
    end

    -- BFS upward
    local visited  = { [nodeStr] = true }
    local queue    = { nodeStr }
    local frontier = { [nodeStr] = true }

    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, link in ipairs(data.links) do
            local neighbour = nil
            if tostring(link.to) == current then
                neighbour = tostring(link.from)
            elseif tostring(link.from) == current then
                neighbour = tostring(link.to)
            end

            if neighbour and not visited[neighbour] then
                for _, node in ipairs(data.nodes) do
                    if tostring(node.id) == neighbour then
                        if node.type == "department" then return node.id end
                        visited[neighbour] = true
                        table.insert(queue, neighbour)
                        break
                    end
                end
            end
        end
    end

    return nil
end

GetDepartmentForNode = GetDepartmentForNode

-- ----------------------------------------------------------------
--  Normalise a string for comparison (lowercase, strip whitespace/dashes)
-- ----------------------------------------------------------------
local function NormaliseKey(str)
    if type(str) ~= "string" then return nil end
    local result = str:lower():gsub("[%s%-%_]", "")
    return result ~= "" and result or nil
end

-- ----------------------------------------------------------------
--  Check whether a table of permission strings contains a match
--  for the current job type string.
-- ----------------------------------------------------------------
local function HasPermInTable(permTable, jobTypeStr)
    if type(permTable) ~= "table" then return false end
    local normJob = NormaliseKey(jobTypeStr)
    if not normJob then return false end
    local seen = {}

    -- Direct key lookup first
    for _, raw in ipairs(permTable) do
        local norm = NormaliseKey(raw)
        if norm then
            seen[norm] = true
            if permTable[raw] == true then return true end
        end
        if raw == true then return true end
    end

    -- Pairs scan for boolean values
    for k, v in pairs(permTable) do
        if v == true then
            local norm = NormaliseKey(k)
            if norm and seen[norm] then return true end
        end
    end

    return false
end

-- Local reference used internally
local _HasPermInTable = HasPermInTable

-- ----------------------------------------------------------------
--  Determine whether the local player can access a given node
--  with the requested interaction type.
-- ----------------------------------------------------------------
local function HasPermissionForNode(nodeId, interactionType, data)
    if serverPermResult and Config.AdminBypass then return true end

    local departmentId = GetDepartmentForNode(nodeId, data)
    if not departmentId then return true end  -- no department restriction

    local playerData = Framework.GetPlayerData()
    if not playerData then return false end

    local citizenId = playerData.citizenid
    local jobName   = (playerData.job and playerData.job.name) or "none"

    local gradeRaw = playerData.job and (
                         type(playerData.job.grade) == "table"
                         and playerData.job.grade.level or playerData.job.grade
                     ) or 0
    local grade = tonumber(gradeRaw) or 0

    -- Override with MemberData if the player's job matches this department
    local member = MemberData[citizenId]
    if member and tostring(member.job) == tostring(departmentId) then
        jobName = member.job
        grade   = tonumber(member.grade) or grade
    end

    -- Is the player in this department at all?
    if not IsPlayerInDepartment(departmentId) then return false end

    -- Look up the rank node
    local rankNode = GetLinkedNodeByType(departmentId, "rank", data)
    local isBossMenu = interactionType and interactionType:lower() == "boss_menu"

    if not rankNode then
        return not isBossMenu
    end

    -- Boss-menu access requires the rank entry to explicitly allow it
    if isBossMenu then
        if rankNode.ranks and type(rankNode.ranks) == "table" then
            for _, rankEntry in ipairs(rankNode.ranks) do
                if tonumber(rankEntry.level) == grade then
                    if rankEntry.bossMenu == true then return true end
                    break
                end
            end
        end
        return false
    end

    -- Check permission node for this rank
    local permNode = GetLinkedNodeByType(rankNode.id, "permission", data)
    if not permNode then return true end

    local rankKey  = "rank_" .. tostring(grade)
    local rankPerms = permNode.rankPerms and permNode.rankPerms[rankKey]
    if rankPerms and type(rankPerms) == "table" then
        return _HasPermInTable(rankPerms, interactionType)
    end

    return true
end

HasPermissionForNode = HasPermissionForNode

-- ================================================================
--  Target-zone management (ox_target / qb-target)
-- ================================================================

-- Remove all location-type target zones
local function ClearLocationZones()
    local target = Config.Target
    for key, zoneId in pairs(locationZones) do
        if target == "ox_target" then
            exports.ox_target:removeZone(zoneId)
        elseif target == "qb-target" then
            exports["qb-target"]:RemoveZone(key)
        end
    end
    locationZones = {}
end

-- ----------------------------------------------------------------
--  Register a target zone (sphere) around a node interaction point.
--  entityType: "ped" | "zone"
-- ----------------------------------------------------------------
local function RegisterInteractionZone(nodeId, interactionType, coords, label, departmentJob, entityType, requestToken)
    -- Abort if the data has been superseded
    if requestToken and not IsCurrentToken(requestToken) then return end

    -- Build a unique internal zone key
    local zoneKey = ("plt_amb_%s_%s"):format(tostring(nodeId), tostring(interactionType))

    -- Convert underscores to Title Case for display
    local displayLabel = interactionType:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b)
        return a:upper() .. b:lower()
    end)
    displayLabel = GetCleanLabel(label, displayLabel)

    -- canInteract closure: ensures the player is on-duty in this department
    local function CanInteract(_, _, _)
        local pd = Framework.GetPlayerData()
        if not pd then return false end
        if serverPermResult then return true end
        if not IsPlayerInDepartment(departmentJob) then return false end
        if not HasPermissionForNode(nodeId, interactionType, DepartmentData) then return false end
        if interactionType == "duty" then return true end
        return pd.job and pd.job.onduty == true
    end

    -- ---- Spawn NPC doctor ped ----
    if entityType == "ped" then
        -- Remove existing ped for this zone if present
        local existing = locationPeds[zoneKey]
        if type(existing) == "number" and DoesEntityExist(existing) then
            DeleteEntity(existing)
        end

        -- Determine ped model
        local pedModel = (Config.LocalDoctor and Config.LocalDoctor.DoctorPedModel)
                         or "s_m_m_doctor_01"
        local modelHash = GetHashKey(pedModel)
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end

        if requestToken and not IsCurrentToken(requestToken) then return end

        if HasModelLoaded(modelHash) then
            local ped = CreatePed(4, modelHash,
                coords.x, coords.y, coords.z, coords.h or 0.0,
                false, false)
            SetEntityAsMissionEntity(ped, true, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            locationPeds[zoneKey] = ped
            SetModelAsNoLongerNeeded(modelHash)
        end
    end

    if requestToken and not IsCurrentToken(requestToken) then return end

    -- ---- Register target zone ----
    local target = Config.Target

    if target == "ox_target" then
        local options
        if interactionType == "wardrobe" then
            options = {
                {
                    icon      = "fas fa-user-nurse",
                    label     = "Wear EMS Clothes",
                    canInteract = CanInteract,
                    distance  = 3.0,
                    onSelect  = function()
                        TriggerEvent("amb_client:Interact", {
                            locType       = interactionType,
                            job           = departmentJob,
                            nodeId        = nodeId,
                            coords        = coords,
                            label         = displayLabel,
                            wardrobeAction = "ems",
                        })
                    end,
                },
                {
                    icon      = "fas fa-user",
                    label     = "Wear Civilian Clothes",
                    canInteract = CanInteract,
                    distance  = 3.0,
                    onSelect  = function()
                        TriggerEvent("amb_client:Interact", {
                            locType       = interactionType,
                            job           = departmentJob,
                            nodeId        = nodeId,
                            coords        = coords,
                            label         = displayLabel,
                            wardrobeAction = "civilian",
                        })
                    end,
                },
            }
        else
            options = {
                {
                    icon      = "fas fa-hand-pointer",
                    label     = displayLabel,
                    canInteract = CanInteract,
                    distance  = 3.0,
                    onSelect  = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = interactionType,
                            job     = departmentJob,
                            nodeId  = nodeId,
                            coords  = coords,
                            label   = displayLabel,
                        })
                    end,
                },
            }
        end

        local zoneId = exports.ox_target:addSphereZone({
            coords  = vector3(coords.x, coords.y, coords.z),
            radius  = 1.2,
            debug   = false,
            options = options,
        })
        locationZones[zoneKey] = zoneId

    elseif target == "qb-target" then
        local options
        if interactionType == "wardrobe" then
            options = {
                {
                    type     = "client",
                    icon     = "fas fa-user-nurse",
                    label    = "Wear EMS Clothes",
                    canInteract = CanInteract,
                    action   = function()
                        TriggerEvent("amb_client:Interact", {
                            locType       = interactionType,
                            job           = departmentJob,
                            nodeId        = nodeId,
                            coords        = coords,
                            label         = displayLabel,
                            wardrobeAction = "ems",
                        })
                    end,
                },
                {
                    type     = "client",
                    icon     = "fas fa-user",
                    label    = "Wear Civilian Clothes",
                    canInteract = CanInteract,
                    action   = function()
                        TriggerEvent("amb_client:Interact", {
                            locType       = interactionType,
                            job           = departmentJob,
                            nodeId        = nodeId,
                            coords        = coords,
                            label         = displayLabel,
                            wardrobeAction = "civilian",
                        })
                    end,
                },
            }
        else
            options = {
                {
                    type       = "client",
                    icon       = "fas fa-hand-pointer",
                    label      = displayLabel,
                    canInteract = CanInteract,
                    action     = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = interactionType,
                            job     = departmentJob,
                            nodeId  = nodeId,
                            coords  = coords,
                            label   = displayLabel,
                        })
                    end,
                },
            }
        end

        exports["qb-target"]:AddCircleZone(
            zoneKey,
            vector3(coords.x, coords.y, coords.z),
            1.2,
            { name = zoneKey, debugPoly = false, useZ = true },
            { options = options, distance = 3.0 }
        )
        locationZones[zoneKey] = true
    end
end

-- ================================================================
--  Bed / coords list helpers
-- ================================================================

--- Flatten a coordsList entry (which may contain "bed", "beds", etc.)
--- into a flat array of { x, y, z, h } tables.
local function FlattenBedCoords(coordsList)
    local result = {}

    local function PushCoord(entry)
        if not (entry and entry.x and entry.y and entry.z) then return end
        result[#result + 1] = {
            x = tonumber(entry.x) or entry.x,
            y = tonumber(entry.y) or entry.y,
            z = tonumber(entry.z) or entry.z,
            h = tonumber(entry.h) or 0.0,
        }
    end

    if not coordsList then return result end

    -- Single bed entry
    local bed = coordsList.bed
    if type(bed) == "table" then
        if bed.x and bed.y and bed.z then
            PushCoord(bed)
        else
            for _, b in ipairs(bed) do PushCoord(b) end
        end
    end

    -- Plural beds entry
    local beds = coordsList.beds
    if type(beds) == "table" then
        if beds.x and beds.y and beds.z then
            PushCoord(beds)
        else
            for _, b in ipairs(beds) do PushCoord(b) end
        end
    end

    return result
end

-- ----------------------------------------------------------------
--  Return true if any non-self player ped is within radius of coords.
-- ----------------------------------------------------------------
local function IsPlayerNearBed(coords, selfPed)
    local pos = vector3(coords.x, coords.y, coords.z)
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped and ped ~= 0 and ped ~= selfPed then
            if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
                if #(GetEntityCoords(ped) - pos) <= 1.2 then
                    return true
                end
            end
        end
    end
    return false
end

--- From a list of bed coords, pick the first one that is not occupied
--- by another player. Falls back to the first entry.
local function PickFreeBed(bedList, selfPed)
    if not bedList or #bedList == 0 then return nil end
    for _, bed in ipairs(bedList) do
        if not IsPlayerNearBed(bed, selfPed) then return bed end
    end
    return bedList[1]
end

-- ================================================================
--  Check-in zone registration
-- ================================================================

--- Register a check-in zone for a node.
--- hasEMS: whether enough EMS are on-duty.
local function RegisterCheckInZone(nodeId, checkinCoords, bedList, locationLabel, hasEMS, minEMS, requestToken)
    if requestToken and not IsCurrentToken(requestToken) then return end

    local zoneKey = ("plt_amb_checkin_%s"):format(tostring(nodeId))

    local healTime = (Config.LocalDoctor and Config.LocalDoctor.HealTime) or 15000
    local lieAnim  = (Config.LocalDoctor and Config.LocalDoctor.LieAnim) or {
        dict = "amb@world_human_sunbathe@male@back@base",
        name = "base",
    }

    -- Determine the NPC ped model to spawn near the check-in
    local doctorPedModel = (Config.LocalDoctor and Config.LocalDoctor.DoctorPedModel)
                           or "s_m_m_doctor_01"

    -- Spawn NPC doctor ped at check-in coords
    local doctorPedHash = GetHashKey(doctorPedModel)
    RequestModel(doctorPedHash)
    local timeout = 0
    while not HasModelLoaded(doctorPedHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if requestToken and not IsCurrentToken(requestToken) then return end

    if HasModelLoaded(doctorPedHash) then
        local ped = CreatePed(4, doctorPedHash,
            checkinCoords.x, checkinCoords.y, checkinCoords.z,
            checkinCoords.h or 0.0, false, false)
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        xrayPeds[zoneKey] = ped
        SetModelAsNoLongerNeeded(doctorPedHash)
    end
end

-- ================================================================
--  Toggle vitals-monitor power (local action)
-- ================================================================
local function ToggleVitalsMonitor(entityId)
    local key = tostring(entityId)
    local newState = monitorPowerState[key] ~= true  -- toggle
    monitorPowerState[key] = newState

    TriggerServerEvent("plt_xray:server:setMonitorPower", key, newState)

    local stateLabel = newState and _L("monitor_state_on") or _L("monitor_state_off")
    Framework.Notify(_L("monitor_state", { state = stateLabel }), "success")
end

ToggleVitalsMonitor = ToggleVitalsMonitor

-- Mirror power state change coming from the server
RegisterNetEvent("plt_ambulance:client:setMonitorPowerMirror")
AddEventHandler("plt_ambulance:client:setMonitorPowerMirror", function(entityId, state)
    local key = tostring(entityId)
    monitorPowerState[key] = state == true
    TriggerEvent("plt_xray:client:setMonitorPower", key, monitorPowerState[key])
end)

-- ================================================================
--  Lie on / get off treatment bed
-- ================================================================

--- Toggle the player lying on a treatment bed.
--- coords: vector / table with x,y,z  –  heading: number
local function LieOnTreatmentBed(coords, heading)
    local ped = PlayerPedId()

    if isPlayerOnBed then
        -- Get up
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        isPlayerOnBed = false
        currentBedAnim = nil
        LocalPlayer.state:set("isLyingOnBed", false, true)
    else
        -- Lie down
        isPlayerOnBed = true
        LocalPlayer.state:set("isLyingOnBed", true, true)

        local animDict = "anim@gangops@morgue@table@"
        local animName = "ko_front"

        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do Wait(10) end

        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
        SetEntityHeading(ped, heading)
        FreezeEntityPosition(ped, true)
        TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)

        currentBedAnim = { ad = animDict, anim = animName }
        Framework.Notify(_L("lying_on_bed_exit"), "info")

        -- Loop: keep animation playing and watch for E key to exit
        CreateThread(function()
            while isPlayerOnBed do
                if not IsEntityPlayingAnim(ped, animDict, animName, 3) then
                    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)
                end
                if IsControlJustPressed(0, 73) then   -- 73 = INPUT_ENTER
                    LieOnTreatmentBed(coords, heading)
                    break
                end
                Wait(0)
            end
        end)
    end
end

LieOnTreatmentBed = LieOnTreatmentBed

-- ----------------------------------------------------------------
--  Find a nearby player who is lying on a treatment bed.
--  Returns their ped or nil.
-- ----------------------------------------------------------------
local function FindPatientOnBed(searchCoords, radius)
    radius = radius or 1.7
    local selfPed = PlayerPedId()

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped and ped ~= 0 and ped ~= selfPed then
            if DoesEntityExist(ped) then
                if #(GetEntityCoords(ped) - searchCoords) <= radius then
                    local serverId = GetPlayerServerId(player)
                    local pState   = Player(serverId) and Player(serverId).state
                    local lyingState = pState and pState.isLyingOnBed == true
                    local animPlaying = IsEntityPlayingAnim(ped,
                        "anim@gangops@morgue@table@", "ko_front", 3)
                    if lyingState or animPlaying then
                        return ped
                    end
                end
            end
        end
    end

    return nil
end

-- ----------------------------------------------------------------
--  Check if the local player (as EMS) is near a patient and on-duty
-- ----------------------------------------------------------------
local function IsNearPatientAsDutyEMS(coords)
    if not (exports.plt_ambulance_job:IsEMS() or serverPermResult) then
        return false
    end

    local pd = Framework.GetPlayerData()
    if not pd then return false end

    local onDuty = pd.job and pd.job.onduty == true
    if not onDuty and not (serverPermResult and Config.AdminBypass) then
        return false
    end

    return FindPatientOnBed(coords, 1.7) ~= nil
end

-- ----------------------------------------------------------------
--  Start a diagnosis on a nearby patient
-- ----------------------------------------------------------------
local function StartDiagnosisNearby(coords)
    local patient = FindPatientOnBed(coords, 1.7)
    if not patient then
        Framework.Notify(_L("diagnosis_no_patient_id"), "error")
        return
    end

    if type(StartDiagnosis) == "function" then
        StartDiagnosis(patient)
    else
        Framework.Notify(_L("diagnosis_no_patient_id"), "error")
    end
end

-- ================================================================
--  Vitals data export (called by plt_xray)
-- ================================================================
exports("GetVitalsData", function()
    local ped    = PlayerPedId()
    local health = GetEntityHealth(ped)

    -- Dead / downed
    if not isPlayerOnBed and health > 195 then
        return { pulse = 0, bp = "0/0", o2 = 0, stress = 0 }
    end

    local hp    = health - 100
    local maxHp = GetEntityMaxHealth(ped) - 100
    local pulse = 60 + math.floor((maxHp - hp) * 0.4)
    if hp < 10 then pulse = 0 end

    local bpSys = 110 + math.random(0, 20)
    local bpDia = 70  + math.random(0, 15)
    if hp < 50 then
        bpSys = bpSys - (50 - hp)
        bpDia = bpDia - (50 - hp) * 0.5
    end

    local o2 = 95 + math.random(0, 4)
    if hp < 40 then o2 = 80 + math.random(0, 10) end

    local stress = math.random(10, 30)

    return {
        pulse  = pulse,
        bp     = ("%d/%d"):format(bpSys, bpDia),
        o2     = o2,
        stress = stress,
    }
end)

-- ================================================================
--  Main refresh: rebuild all blips and target zones
-- ================================================================
local function RefreshBlipsAndZones(data)
    local token = NewRequestToken()
    DepartmentData = data

    -- Remove old map blips
    for _, blip in pairs(mapBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    mapBlips = {}

    -- Remove old target zones
    ClearLocationZones()
    bedsideObjects = ClearTargetZones(bedsideObjects)

    -- Clear location peds
    for _, ped in pairs(locationPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    locationPeds = {}

    ClearXrayScene()
    vehicleSpawnInfo = {}

    -- Clear check-in zones
    local target = Config.Target
    for key, zoneId in pairs(checkinZones) do
        if target == "ox_target" then
            if type(zoneId) == "number" then
                exports.ox_target:removeZone(zoneId)
            end
        elseif target == "qb-target" then
            exports["qb-target"]:RemoveZone(key)
        end
    end
    checkinZones = {}
    checkInTargets = {}

    if not data or not data.nodes then return end

    -- Iterate nodes and build blips / zones
    for _, node in ipairs(data.nodes) do
        local departmentJob = GetDepartmentForNode(node.id, data)

        -- ---- Department blip ----
        if node.type == "department" and node.coords and node.coords.x then
            local blip = AddBlipForCoord(node.coords.x, node.coords.y, node.coords.z)
            SetBlipSprite(blip, node.blipId or 61)
            SetBlipColour(blip, node.blipColor or 1)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(GetCleanLabel(node.label, "Department"))
            EndTextCommandSetBlipName(blip)
            mapBlips[tostring(node.id)] = blip
        end

        -- ---- Treatment beds (location node) ----
        if node.type == "location" and node.coordsList then
            local bedList = FlattenBedCoords(node.coordsList)
            for _, bedCoord in ipairs(bedList) do
                local bedZoneKey = ("plt_xray_bed_%s"):format(tostring(node.id))
                local bedPos     = vector3(bedCoord.x, bedCoord.y, bedCoord.z)
                local bedHeading = tonumber(bedCoord.h) or 0.0

                if target == "ox_target" then
                    local zoneId = exports.ox_target:addSphereZone({
                        coords  = bedPos,
                        radius  = 1.0,
                        options = {
                            {
                                name    = bedZoneKey,
                                label   = _L("bed_lie"),
                                icon    = "fas fa-bed",
                                onSelect = function()
                                    LieOnTreatmentBed(bedPos, bedHeading)
                                end,
                            }
                        },
                    })
                    bedsideObjects[bedZoneKey] = zoneId
                else
                    exports["qb-target"]:AddBoxZone(
                        bedZoneKey, bedPos, 1.0, 2.0,
                        {
                            name       = bedZoneKey,
                            heading    = bedHeading,
                            debugPoly  = false,
                            minZ       = bedCoord.z - 0.5,
                            maxZ       = bedCoord.z + 0.5,
                        },
                        {
                            options  = {
                                {
                                    type   = "client",
                                    icon   = "fas fa-bed",
                                    label  = _L("bed_lie"),
                                    action = function()
                                        LieOnTreatmentBed(bedPos, bedHeading)
                                    end,
                                }
                            },
                            distance = 2.0,
                        }
                    )
                    bedsideObjects[bedZoneKey] = bedZoneKey
                end
            end
        end

        -- ---- Per-coordsList interaction zones ----
        if node.coordsList then
            for interType, coord in pairs(node.coordsList) do
                if coord and coord.x
                and node.type ~= "xray"
                and node.type ~= "check_in"
                and node.type ~= "ceiling_monitor" then
                    local effectiveType = (node.interactionTypes and node.interactionTypes[interType])
                                         or "zone"
                    RegisterInteractionZone(
                        node.id, interType, coord, node.label,
                        departmentJob, effectiveType, token)
                end
            end
        end

        -- ---- Vehicle / helipad spawn-point data ----
        if node.type == "vehicle" or node.type == "helipad" then
            if node.deletePoints then
                local allowedModels = {}
                if type(node.vehicles) == "table" then
                    for _, v in ipairs(node.vehicles) do
                        if type(v) == "table" and v.model and tostring(v.model) ~= "" then
                            allowedModels[#allowedModels + 1] = tostring(v.model):lower()
                        end
                    end
                end
                for _, pt in ipairs(node.deletePoints) do
                    if pt and pt.x then
                        table.insert(vehicleSpawnInfo, {
                            coords        = pt,
                            job           = departmentJob,
                            allowedModels = allowedModels,
                        })
                    end
                end
            end
        end

        -- ---- Single-coord interaction zone (non-special types) ----
        if node.type ~= "department" and node.type ~= "pharmacy"
        and node.type ~= "ceiling_monitor"
        and node.coords and node.coords.x then
            if not (node.coordsList and node.coordsList[node.type]) then
                RegisterInteractionZone(
                    node.id, node.type, node.coords, node.label,
                    departmentJob, "zone", token)
            end
        end
    end

    -- Fetch EMS on-duty count then create check-in zones
    Framework.TriggerCallback("amb_server:getEMSOnDutyCount", function(emsCount)
        if not IsCurrentToken(token) then return end

        for _, node in ipairs(data.nodes) do
            if node.type == "check_in" then
                local checkinCoord = node.coordsList and node.coordsList.checkin
                local bedList      = FlattenBedCoords(node.coordsList)
                local minEMS       = tonumber(node.minEMS) or 1

                if checkinCoord and checkinCoord.x and #bedList > 0 then
                    local locationNode = GetLinkedNodeByType(node.id, "location", data)
                    local locationLabel = (locationNode and locationNode.label)
                                         or node.label
                                         or _L("hospital")

                    RegisterCheckInZone(
                        node.id,
                        checkinCoord,
                        bedList,
                        locationLabel,
                        emsCount >= minEMS,
                        minEMS,
                        token
                    )
                end
            end
        end
    end)
end

RefreshBlipsAndZones = RefreshBlipsAndZones

-- ================================================================
--  NUI callbacks
-- ================================================================

-- ---- Placement mode (admin tool) ----
local isPlacementActive = false

RegisterNUICallback("startPlacement", function(data, cb)
    if isPlacementActive then return cb("ok") end
    isPlacementActive = true
    SetNuiFocus(false, false)

    local isSpawnType = data.locType == "spawn"
    SendNUIMessage({
        action       = "amb_togglePlacementHelp",
        visible      = true,
        header       = _L("placement_header"),
        confirmLabel = _L("placement_confirm"),
        rotateLabel  = (isSpawnType and _L("placement_rotate")) or _L("placement_no_rotate"),
    })

    CreateThread(function()
        local heading = isSpawnType and GetEntityHeading(PlayerPedId()) or 0.0
        local offset  = 0.0
        local modelHash = nil
        local previewEntity = nil
        local usesObject    = false
        local usesPed       = false

        -- Determine preview model hash by location type
        local locType = data.locType
        if     locType == "spawn"   then modelHash = 1171614426
            if data.nodeId and data.nodeId:find("helipad") then modelHash = 353883353 end
        elseif locType == "bed"     then modelHash = 1631638868 ; usesObject = true
        elseif locType == "checkin" or locType == "ped" then modelHash = -730659924 ; usesPed = true
        elseif locType == "monitor" then modelHash = 389765485  ; usesObject = true
        end

        if modelHash then
            RequestModel(modelHash)
            local t = 0
            while not HasModelLoaded(modelHash) and t < 100 do Wait(10) ; t = t + 1 end
        end

        while isPlacementActive do
            Wait(0)

            local hit, hitCoords = RaycastFromCamera(100.0)
            if hit then
                local placementPos = hitCoords

                -- PC type: offset from player
                if locType == "pc" then
                    local pedPos = GetEntityCoords(PlayerPedId())
                    local dx = hitCoords.x - pedPos.x
                    local dy = hitCoords.y - pedPos.y
                    local dist2d = math.sqrt(dx * dx + dy * dy)
                    if dist2d > 0.001 then
                        placementPos = vector3(
                            hitCoords.x + (dx / dist2d) * offset,
                            hitCoords.y + (dy / dist2d) * offset,
                            hitCoords.z)
                    end
                end

                -- Draw bed footprint marker
                if locType == "bed" then
                    DrawMarker(1, hitCoords.x, hitCoords.y, hitCoords.z - 1.0,
                               0, 0, 0, 0, 0, 0, 2.4, 2.4, 2.0,
                               220, 240, 255, 120, false, false, 2, nil, nil, false)
                    DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z,
                               0, 0, 0, 0, 0, 0, 0.1, 0.1, 0.1,
                               255, 255, 255, 200, false, false, 2, nil, nil, false)
                end

                -- Default dot marker
                if not modelHash and locType ~= "pc" and locType ~= "bed" then
                    DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z,
                               0, 0, 0, 0, 0, 0, 0.15, 0.15, 0.15,
                               0, 255, 204, 150, false, false, 2, nil, nil, false)
                end

                -- PC type: show xray placement preview
                if locType == "pc" then
                    TriggerEvent("plt_xray:client:showPlacementPreview", placementPos, heading, offset)
                end

                -- Spawn / update preview entity
                if modelHash then
                    if not previewEntity then
                        if usesObject then
                            previewEntity = CreateObject(modelHash,
                                hitCoords.x, hitCoords.y, hitCoords.z,
                                false, false, false)
                        elseif usesPed then
                            previewEntity = CreatePed(4, modelHash,
                                hitCoords.x, hitCoords.y, hitCoords.z - 1.0,
                                heading, false, false)
                            SetEntityAlpha(previewEntity, 180, false)
                            SetEntityCollision(previewEntity, false, false)
                            SetEntityInvincible(previewEntity, true)
                        end
                    end

                    if previewEntity then
                        SetEntityCoords(previewEntity,
                            hitCoords.x, hitCoords.y, hitCoords.z,
                            false, false, false, false)
                        SetEntityHeading(previewEntity, heading)
                    end
                end

                -- Rotation control (Q/E)
                if isSpawnType then
                    if IsControlPressed(0, 44) then heading = (heading + 1.0) % 360 end -- Q
                    if IsControlPressed(0, 38) then heading = (heading - 1.0 + 360) % 360 end -- E
                end

                -- Confirm (Enter / F)
                if IsControlJustPressed(0, 73) or IsControlJustPressed(0, 38) then
                    if previewEntity and DoesEntityExist(previewEntity) then
                        DeleteEntity(previewEntity)
                        previewEntity = nil
                    end
                    TriggerEvent("amb_client:placementConfirmed", {
                        locType = locType,
                        nodeId  = data.nodeId,
                        coords  = { x = placementPos.x, y = placementPos.y, z = placementPos.z, h = heading },
                    })
                    isPlacementActive = false
                    break
                end
            end
        end

        if previewEntity and DoesEntityExist(previewEntity) then
            DeleteEntity(previewEntity)
        end
        SendNUIMessage({ action = "amb_togglePlacementHelp", visible = false })
    end)

    cb("ok")
end)

-- ---- Confirm placement coords back to NUI ----
AddEventHandler("amb_client:placementConfirmed", function(result)
    TriggerEvent("amb_client:SendPlacementToNUI", result)
    isPlacementActive = false
end)

RegisterNUICallback("confirmPlacement", function(data, cb)
    TriggerEvent("amb_client:placementConfirmed", data)
    cb("ok")
end)

RegisterNUICallback("cancelPlacement", function(_, cb)
    isPlacementActive = false
    cb("ok")
end)

-- ---- Close NUI ----
RegisterNUICallback("amb_close", function(_, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

-- ---- EMS invoicing ----
RegisterNUICallback("amb_payEMSInvoice", function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent("amb_server:payEMSInvoice", data and data.invoiceId)
    cb("ok")
end)

RegisterNUICallback("amb_declineEMSInvoice", function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent("amb_server:declineEMSInvoice", data and data.invoiceId)
    cb("ok")
end)

-- ---- Armory item take ----
RegisterNUICallback("amb_takeEMSItem", function(data, cb)
    TriggerServerEvent("amb_server:takeEMSInventoryItem", data)
    cb("ok")
end)

-- ---- Spawn vehicle from garage UI ----
RegisterNUICallback("amb_spawnVehicle", function(data, cb)
    local model       = data.model
    local spawnPoints = data.spawnPoints
    if not model or not spawnPoints or #spawnPoints == 0 then return cb("ok") end

    -- Find a spawn point with no nearby vehicle
    local spawnPoint = nil
    for _, pt in ipairs(spawnPoints) do
        if pt and pt.x and not IsAnyVehicleNearPoint(pt.x, pt.y, pt.z, 3.0) then
            spawnPoint = pt
            break
        end
    end

    if not spawnPoint then
        Framework.Notify(_L("spawn_blocked"), "error")
        return cb("ok")
    end

    local modelHash = (type(model) == "string") and GetHashKey(model) or model
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(0) end

    local vehicle = CreateVehicle(modelHash,
        spawnPoint.x, spawnPoint.y, spawnPoint.z,
        spawnPoint.h or 0.0, true, true)

    NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(vehicle), true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehRadioStation(vehicle, "OFF")
    SetModelAsNoLongerNeeded(modelHash)

    local plate = "EMS" .. tostring(math.random(100, 999))
    SetVehicleNumberPlateText(vehicle, plate)

    -- Tag vehicle state
    local eState = Entity(vehicle) and Entity(vehicle).state
    if eState then
        eState:set("amb_department_vehicle",       true,              true)
        eState:set("amb_department_vehicle_model", tostring(model or ""), true)
    end

    Wait(100)
    GiveVehicleKeys(vehicle)
    Framework.Notify(_L("vehicle_spawned"), "success")
    cb("ok")
end)

-- ================================================================
--  Vehicle store thread (detect when driver pulls up to delete point)
-- ================================================================
CreateThread(function()
    local function VehicleMatchesDeletePoint(vehicle, deleteData)
        if not vehicle or vehicle == 0 or not deleteData then return false end
        local allowed = deleteData.allowedModels
        if type(allowed) ~= "table" then return false end
        if #allowed == 0 then return false end

        local modelHash    = GetEntityModel(vehicle)
        local displayName  = tostring(GetDisplayNameFromVehicleModel(modelHash) or ""):lower()

        for _, entry in ipairs(allowed) do
            local modelStr = Trim(tostring(entry or "")):lower()
            if modelStr ~= "" then
                if displayName == modelStr then return true end
                if GetHashKey(modelStr) == modelHash then return true end
            end
        end
        return false
    end

    local promptShown = false
    while true do
        local waitMs = 1000
        local selfPed    = PlayerPedId()
        local selfVehicle = GetVehiclePedIsIn(selfPed, false)

        if selfVehicle ~= 0 and GetPedInVehicleSeat(selfVehicle, -1) == selfPed then
            local selfPos    = GetEntityCoords(selfPed)
            local nearPoint  = false

            for _, deleteInfo in ipairs(vehicleSpawnInfo) do
                local pt = vector3(deleteInfo.coords.x, deleteInfo.coords.y, deleteInfo.coords.z)
                if #(selfPos - pt) <= defaultHealRadius then
                    waitMs = 0
                    if IsPlayerInDepartment(deleteInfo.job) or serverPermResult then
                        nearPoint = true
                        if not promptShown then
                            Framework.ShowTextUI(_L("store_vehicle_prompt"))
                            promptShown = true
                        end
                        if IsControlJustPressed(0, 38) then   -- INPUT_ENTER
                            if VehicleMatchesDeletePoint(selfVehicle, deleteInfo) then
                                Framework.HideTextUI()
                                promptShown = false
                                Framework.DeleteVehicle(selfVehicle)
                                Framework.Notify(_L("vehicle_stored"), "success")
                            else
                                Framework.Notify("This vehicle is not registered in this department vehicle node.", "error")
                            end
                        end
                        break
                    end
                end
            end

            if not nearPoint and promptShown then
                Framework.HideTextUI()
                promptShown = false
            end
        elseif promptShown then
            Framework.HideTextUI()
            promptShown = false
        end

        Wait(waitMs)
    end
end)

-- ================================================================
--  Open management UI
-- ================================================================
local function OpenManageUI(serverData)
    if serverData and serverData.dept then
        DepartmentData = serverData.dept
        MemberData     = serverData.members or {}
        RefreshBlipsAndZones(DepartmentData)
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = "amb_open", data = DepartmentData })
end

RegisterNetEvent("amb_client:openManageEMSDirect")
AddEventHandler("amb_client:openManageEMSDirect", function(data)
    OpenManageUI(data)
end)

local function FetchAndOpenUI()
    Framework.TriggerCallback("amb_server:getData", function(result)
        OpenManageUI(result)
    end)
end

-- Register the chat command to open the management UI
RegisterCommand(Config.CommandName, function()
    TriggerServerEvent("amb_server:requestManageEMSDirect")
end)

-- ================================================================
--  EMS invoice chat suggestions (created once on resource start)
-- ================================================================
CreateThread(function()
    local invoice = Config.EMSInvoice or {}

    TriggerEvent("chat:addSuggestion",
        "/" .. (invoice.CommandName or "emsinvoice"),
        "Send an EMS invoice to a nearby patient",
        {
            { name = "patientId", help = "Patient server ID"  },
            { name = "amount",    help = "Invoice amount"     },
            { name = "reason",    help = "Invoice reason"     },
        }
    )

    TriggerEvent("chat:addSuggestion",
        "/" .. (invoice.PayCommandName or "payemsinvoice"),
        "Pay a pending EMS invoice",
        { { name = "invoiceId", help = "Optional invoice ID" } }
    )

    TriggerEvent("chat:addSuggestion",
        "/" .. (invoice.DeclineCommandName or "declineemsinvoice"),
        "Decline a pending EMS invoice",
        { { name = "invoiceId", help = "Optional invoice ID" } }
    )
end)

-- ================================================================
--  Receive EMS invoice from server
-- ================================================================
RegisterNetEvent("amb_client:EMSInvoiceReceived")
AddEventHandler("amb_client:EMSInvoiceReceived", function(invoice)
    if type(invoice) ~= "table" then return end

    local invoiceConfig  = Config.EMSInvoice or {}
    local expireMinutes  = invoiceConfig.ExpireMinutes or 10
    invoice.expireMinutes = expireMinutes

    SendNUIMessage({ action = "amb_openEMSInvoice", invoice = invoice })
    SetNuiFocus(true, true)

    local payCmd     = invoiceConfig.PayCommandName     or "payemsinvoice"
    local declineCmd = invoiceConfig.DeclineCommandName or "declineemsinvoice"
    local invoiceId  = tostring(invoice.id or "")
    local amount     = tostring(invoice.amount or 0)
    local reason     = tostring(invoice.reason or "Medical service")

    TriggerEvent("chat:addMessage", {
        color     = { 46, 204, 113 },
        multiline = true,
        args      = {
            "EMS Invoice",
            ("#%s | $%s | %s. Pay: /%s %s | Decline: /%s %s")
                :format(invoiceId, amount, reason, payCmd, invoiceId, declineCmd, invoiceId),
        },
    })
end)

-- ================================================================
--  Local-doctor treatment at check-in beds
-- ================================================================
RegisterNetEvent("amb_client:TreatAtCheckIn")
AddEventHandler("amb_client:TreatAtCheckIn", function(treatData)
    if not treatData then return end

    local ped         = PlayerPedId()
    local bedCoords   = treatData.bedCoords
    local healTime    = treatData.healTime
    local lieAnim     = treatData.lieAnim
    local locationLabel = treatData.locationName

    if not bedCoords then return end

    SetEntityCoords(ped, bedCoords.x, bedCoords.y, bedCoords.z,
                    false, false, false, false)
    SetEntityHeading(ped, bedCoords.h or 0.0)
    FreezeEntityPosition(ped, true)

    Framework.RequestAnimDict(lieAnim.dict)
    TaskPlayAnim(ped, lieAnim.dict, lieAnim.name, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    Framework.Notify(_L("local_doctor_treating"), "info")

    CreateThread(function()
        local startTime = GetGameTimer()
        while true do
            local elapsed = GetGameTimer() - startTime
            if elapsed >= healTime then break end
            Wait(0)
            if IsControlJustPressed(0, 73) then  -- INPUT_ENTER
                FreezeEntityPosition(PlayerPedId(), false)
                ClearPedTasks(PlayerPedId())
                Framework.Notify(_L("treatment_cancelled"), "error")
                return
            end
        end
        if DoesEntityExist(PlayerPedId()) then
            FreezeEntityPosition(PlayerPedId(), false)
            ClearPedTasks(PlayerPedId())
            TriggerEvent("amb_client:HealInjuries")
        end
    end)
end)

-- ================================================================
--  Stash helpers (multi-inventory support)
-- ================================================================

--- Build a deterministic stash id string from job + nodeId.
local function BuildStashId(job, nodeId)
    local jobStr  = tostring(job or "ems"):gsub("%s+", "_"):lower()
    local nodeStr = tostring(nodeId or "default"):gsub("%s+", "_"):lower()
    return ("plt_amb_stash_%s_%s"):format(jobStr, nodeStr)
end

--- Return the first resource name from a list that is currently running.
local function FindStartedResource(resourceList)
    for _, name in ipairs(resourceList) do
        if GetResourceState(name) == "started" then return name end
    end
    return nil
end

--- Try to open an inventory stash via exports.
--- resourceName: the resource to call on
--- methodNames:  list of export methods to try
--- argSets:      list of argument arrays to try for each method
local function TryOpenStashViaExport(resourceName, methodNames, argSets)
    if not resourceName then return false end
    for _, method in ipairs(methodNames) do
        for _, args in ipairs(argSets) do
            local ok, result = pcall(function()
                return exports[resourceName][method](table.unpack(args))
            end)
            if ok and result ~= false then return true end
        end
    end
    return false
end

--- Fallback: open stash via legacy QBCore-style events.
local function OpenStashLegacy(stashId, label, maxWeight, slots)
    local meta = { label = label, maxweight = maxWeight, maxWeight = maxWeight, slots = slots }
    TriggerEvent("inventory:client:SetCurrentStash",          stashId)
    TriggerEvent("qb-inventory:client:SetCurrentStash",       stashId)
    TriggerServerEvent("inventory:server:OpenInventory",      "stash", stashId, meta)
    TriggerServerEvent("qb-inventory:server:OpenInventory",   "stash", stashId, meta)
    TriggerEvent("inventory:client:OpenInventory",            "stash", stashId, meta)
    TriggerEvent("qb-inventory:client:OpenInventory",         "stash", stashId, meta)
    TriggerEvent("qb-inventory:client:openInventory",         "stash", stashId, meta)
end

--- Open the department stash, routing to the configured inventory resource.
local function OpenDepartmentStash(job, nodeId, label)
    local stashId   = BuildStashId(job, nodeId)
    local stashLabel = label or (tostring(job or "EMS") .. " Stash")
    local maxWeight  = 400000
    local slots      = 80
    local invType    = tostring(Config.Inventory or ""):lower()

    local meta = { label = stashLabel, maxweight = maxWeight, maxWeight = maxWeight, slots = slots }

    if invType == "ox" then
        if GetResourceState("ox_inventory") == "started" then
            Framework.TriggerCallback("amb_server:prepareDepartmentStash", function(result)
                if not result or not result.ok then
                    Framework.Notify("Unable to open stash right now.", "error")
                    return
                end
                exports.ox_inventory:openInventory("stash", result.stashId or stashId)
            end, { stashId = stashId, label = stashLabel, slots = slots, maxWeight = maxWeight })
            return
        end
    end

    if invType == "qb" then
        Framework.TriggerCallback("amb_server:prepareDepartmentStash", function(result)
            if not result or not result.ok then
                Framework.Notify("Unable to open stash right now.", "error")
                return
            end
            OpenStashLegacy(result.stashId or stashId, stashLabel, maxWeight, slots)
        end, { stashId = stashId, label = stashLabel, slots = slots, maxWeight = maxWeight })
        return
    end

    -- tgiann-inventory
    if invType == "tgiann" then
        local res = FindStartedResource({ "tgiann-inventory", "tgiann_inventory" })
        if TryOpenStashViaExport(res,
            { "OpenInventory", "openInventory", "OpenStash", "openStash" },
            { { "stash", stashId, meta }, { stashId, meta }, { stashId, stashLabel, slots, maxWeight } })
        then return end
    end

    -- quasar-inventory
    if invType == "quasar" then
        local res = FindStartedResource({ "qs-inventory", "qs_inventory", "quasar-inventory", "quasar_inventory" })
        if TryOpenStashViaExport(res,
            { "OpenInventory", "openInventory", "OpenStash", "openStash" },
            { { "stash", stashId, meta }, { stashId, meta }, { stashId, stashLabel, slots, maxWeight } })
        then return end
    end

    -- origin-inventory
    if invType == "origin" then
        local res = FindStartedResource({ "origin_inventory", "origin-inventory", "origen_inventory", "origen-inventory" })
        if TryOpenStashViaExport(res,
            { "OpenInventory", "openInventory", "OpenStash", "openStash" },
            { { "stash", stashId, meta }, { stashId, meta }, { stashId, stashLabel, slots, maxWeight } })
        then return end
    end

    -- core-inventory
    if invType == "core" then
        local res = FindStartedResource({ "core_inventory", "core-inventory" })
        if TryOpenStashViaExport(res,
            { "OpenInventory", "openInventory", "OpenStash", "openStash" },
            { { "stash", stashId, meta }, { stashId, meta }, { stashId, stashLabel, slots, maxWeight } })
        then return end
    end

    -- Legacy QBCore fallback
    if GetResourceState("qb-inventory") == "started" then
        OpenStashLegacy(stashId, stashLabel, maxWeight, slots)
        return
    end

    Framework.Notify("Stash is not configured for this inventory.", "error")
end

-- ================================================================
--  Main interaction handler (fired when a player uses a zone)
-- ================================================================
RegisterNetEvent("amb_client:Interact")
AddEventHandler("amb_client:Interact", function(data)
    if not data or not data.locType then return end

    local locType    = data.locType
    local job        = data.job
    local nodeId     = data.nodeId
    local coords     = data.coords
    local playerData = Framework.GetPlayerData()

    if not playerData then return end

    local hasAccess = IsPlayerInDepartment(job)

    if locType == "boss_menu" then
        if not hasAccess then
            Framework.Notify(_L("not_your_department"), "error") ; return
        end
        if not HasPermissionForNode(nodeId, "boss_menu", DepartmentData) then
            Framework.Notify(_L("not_authorized"), "error") ; return
        end
        OpenBossMenu(job)

    elseif locType == "garage" or locType == "helipad" then
        if not hasAccess then
            Framework.Notify(_L("no_garage_access"), "error") ; return
        end
        local nodeType = (locType == "helipad") and "helipad" or "vehicle"
        local vehicleNode = GetLinkedNodeByType(nodeId, nodeType, DepartmentData)
                         or GetLinkedNodeByType(nodeId, (locType == "helipad") and "vehicle" or "helipad", DepartmentData)

        local vehicles    = (vehicleNode and vehicleNode.vehicles)    or {}
        local spawnPoints = (vehicleNode and vehicleNode.spawnPoints) or { coords }

        local deptName = vehicleNode and vehicleNode.label
        if not deptName then
            deptName = tostring(job):upper() .. _L("garage_title_suffix")
        end

        SendNUIMessage({
            action      = "amb_openGarage",
            deptName    = deptName,
            department  = job,
            vehicles    = vehicles,
            spawnPoints = spawnPoints,
        })
        SetNuiFocus(true, true)

    elseif locType == "inventory" then
        if not hasAccess then
            Framework.Notify(_L("no_inventory_access"), "error") ; return
        end
        Framework.TriggerCallback("amb_server:getEMSInventoryData", function(items)
            SendNUIMessage({ action = "amb_openInventory", items = items })
            SetNuiFocus(true, true)
        end)

    elseif locType == "stash" then
        if not hasAccess then
            Framework.Notify(_L("no_inventory_access"), "error") ; return
        end
        OpenDepartmentStash(job, nodeId, data.label)

    elseif locType == "wardrobe" then
        if not hasAccess then
            Framework.Notify(_L("not_your_department"), "error") ; return
        end
        if data.wardrobeAction == "civilian" then
            RestoreCivilianClothes()
            Framework.Notify("Civilian clothes restored.", "success")
        else
            local equipped = WearEMSOutfit(nodeId)
            if equipped then
                Framework.Notify("EMS uniform equipped.", "success")
            else
                Framework.Notify("No EMS outfit configured for your rank.", "error")
            end
        end

    elseif locType == "duty" then
        if not hasAccess then
            Framework.Notify(_L("not_your_department"), "error") ; return
        end
        TriggerServerEvent("amb_server:ToggleDuty", job)
    end
end)

-- ================================================================
--  X-ray sync: send computer/bed config to plt_xray
-- ================================================================
RegisterNetEvent("plt_xray:requestSync")
AddEventHandler("plt_xray:requestSync", function()
    if not DepartmentData or not DepartmentData.nodes then return end

    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "xray" then
            local pcCoord  = node.coordsList and node.coordsList.pc
            local bedCoord = node.coordsList and node.coordsList.bed

            if (pcCoord and pcCoord.x) or (bedCoord and bedCoord and bedCoord.x) then
                local screenNormal, screenUp = nil, nil
                if pcCoord and pcCoord.x then
                    screenNormal, screenUp = GetScreenOrientationVectors(pcCoord)
                end

                local config = {}

                -- Computer panel config
                if pcCoord and pcCoord.x then
                    config.Computer = {
                        pos          = vector3(pcCoord.x, pcCoord.y, pcCoord.z),
                        screenNormal = screenNormal or HeadingToForwardVector(pcCoord.h or 0.0),
                        screenUp     = screenUp or vector3(0.0, 0.0, 1.0),
                        width        = 0.47,
                        height       = 0.31,
                    }
                end

                -- Scan bed config
                if bedCoord and bedCoord.x then
                    config.ScanBed = {
                        pos    = vector3(bedCoord.x, bedCoord.y, bedCoord.z),
                        radius = 2.0,
                    }
                end

                TriggerEvent("plt_xray:client:updateConfigFromNode", config)
            end
        end
    end
end)

-- ================================================================
--  Network sync events
-- ================================================================

RegisterNetEvent("amb_client:SyncJobs")
AddEventHandler("amb_client:SyncJobs", function(deptData)
    DepartmentData = deptData or { nodes = {}, links = {} }
    RefreshBlipsAndZones(DepartmentData)
end)

RegisterNetEvent("amb_client:SyncMembers")
AddEventHandler("amb_client:SyncMembers", function(members)
    MemberData = members or {}
    SendNUIMessage({ action = "amb_syncMembers", members = members })
end)

RegisterNetEvent("amb_client:RefreshCheckInZones")
AddEventHandler("amb_client:RefreshCheckInZones", function()
    local token = NewRequestToken()
    if not DepartmentData or not DepartmentData.nodes then return end

    local target = Config.Target
    for key, zoneId in pairs(checkinZones) do
        if target == "ox_target" then
            if type(zoneId) == "number" then exports.ox_target:removeZone(zoneId) end
        elseif target == "qb-target" then
            exports["qb-target"]:RemoveZone(key)
        end
    end
    checkinZones   = {}
    checkInTargets = {}

    -- Re-run check-in setup
    for _, ped in pairs(xrayPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    xrayPeds = {}

    Framework.TriggerCallback("amb_server:getEMSOnDutyCount", function(emsCount)
        if not IsCurrentToken(token) then return end

        for _, node in ipairs(DepartmentData.nodes) do
            if node.type == "check_in" then
                local checkinCoord = node.coordsList and node.coordsList.checkin
                local bedList      = FlattenBedCoords(node.coordsList)
                local minEMS       = tonumber(node.minEMS) or 1

                if checkinCoord and checkinCoord.x and #bedList > 0 then
                    local locationNode  = GetLinkedNodeByType(node.id, "location", DepartmentData)
                    local locationLabel = (locationNode and locationNode.label)
                                         or node.label
                                         or _L("hospital")

                    RegisterCheckInZone(
                        node.id, checkinCoord, bedList,
                        locationLabel, emsCount >= minEMS, minEMS, token)
                end
            end
        end
    end)
end)

-- ================================================================
--  Initial data fetch helper
-- ================================================================
local function FetchInitialData()
    Framework.TriggerCallback("amb_server:getData", function(result)
        if result and result.dept then
            DepartmentData = result.dept
            MemberData     = result.members or {}
            RefreshBlipsAndZones(DepartmentData)
            TriggerEvent("amb_client:PushLocaleToUI", Config.Locale)
        end
    end)
end

-- ================================================================
--  Framework player-loaded hooks
-- ================================================================

RegisterNetEvent("QBCore:Client:OnPlayerLoaded")
AddEventHandler("QBCore:Client:OnPlayerLoaded", function()
    CheckServerPermissions()
    FetchInitialData()
end)

RegisterNetEvent("esx:playerLoaded")
AddEventHandler("esx:playerLoaded", function()
    CheckServerPermissions()
    FetchInitialData()
end)

-- Resource start / restart
AddEventHandler("onResourceStart", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CreateThread(function()
            Wait(2000)
            CheckServerPermissions()
            FetchInitialData()
        end)
        return
    end

    if resourceName == "plt_xray" then
        CreateThread(function()
            Wait(1000)
            if DepartmentData and DepartmentData.nodes then
                print("^2[plt_ambulance] plt_xray started; refreshing monitor panels.^7")
                RefreshBlipsAndZones(DepartmentData)
            end
        end)
    end
end)

-- Job change (QBCore)
RegisterNetEvent("QBCore:Client:OnJobUpdate")
AddEventHandler("QBCore:Client:OnJobUpdate", function(newJob)
    CheckServerPermissions()

    local oldDept  = LocalPlayerJob.dept
    local oldGrade = LocalPlayerJob.grade

    local newDept = (newJob and newJob.name) or oldDept
    local newGradeRaw = newJob and (
        type(newJob.grade) == "table" and newJob.grade.level or newJob.grade
    ) or 0
    local newGrade = tonumber(newGradeRaw) or oldGrade or 0

    local newOnDuty = (newJob and newJob.onduty) or LocalPlayerJob.onDuty

    LocalPlayerJob.dept   = newDept
    LocalPlayerJob.grade  = newGrade
    LocalPlayerJob.onDuty = newOnDuty

    -- Refresh if department or rank changed
    if oldDept ~= newDept or tonumber(oldGrade or 0) ~= tonumber(newGrade or 0) then
        RefreshBlipsAndZones(DepartmentData)
    end
end)

-- Job change (ESX)
RegisterNetEvent("esx:setJob")
AddEventHandler("esx:setJob", function()
    CheckServerPermissions()
    RefreshBlipsAndZones(DepartmentData)
end)

-- Poll for framework readiness on first load
CreateThread(function()
    Wait(1000)
    local pd = Framework.GetPlayerData()
    if pd then
        CheckServerPermissions()
        FetchInitialData()
    end
end)
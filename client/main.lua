local oxTargetZones = {}
local qbTargetZones = {}
local unknownCache1 = {}
local unknownCache2 = {}
local currentPlacementPed = nil
local activeOxZones = {}
local activeQbZones = {}
local activePedsAndZones = {}
local activeCeilingMonitors = {}
local activePanels = {}
local monitorPowerState = {}
local placementDistance = 10.0
local monitorStateCache = {}
local isLyingOnBed = false
local currentBedAnim = nil
local placementCounter = 0
local checkInZones = {}

DepartmentData = { nodes = {}, links = {} }
MemberData = {}
LocalPlayerJob = { dept = "none", grade = 0, onDuty = false }

local function RemoveAllZones()
    for k, v in pairs(activePedsAndZones) do
        if type(v) == "number" then
            if DoesEntityExist(v) then
                DeleteEntity(v)
            else
                if Config.Target == "ox_target" then
                    exports.ox_target:removeZone(v)
                end
            end
        elseif type(v) == "string" then
            if Config.Target == "qb-target" then
                exports["qb-target"]:RemoveZone(v)
            end
        end
    end
    activePedsAndZones = {}
end

local function GetNextPlacementId()
    placementCounter = placementCounter + 1
    return placementCounter
end

local function IsCurrentPlacement(id)
    return id == placementCounter
end

local function TrimString(str)
    str = tostring(str or "")
    str = str:gsub("^%s+", "")
    return str:gsub("%s+$", "")
end

local function GiveVehicleKeys(vehicle)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local plate = TrimString(GetVehicleNumberPlateText(vehicle))
        if plate ~= "" then
            if GetResourceState("qb-vehiclekeys") == "started" then
                TriggerEvent("vehiclekeys:client:SetOwner", plate)
                TriggerEvent("qb-vehiclekeys:client:AddKeys", plate)
                TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", plate)
            elseif GetResourceState("qbx_vehiclekeys") == "started" then
                exports.qbx_vehiclekeys:GiveKeys(plate)
            end
        end
    end
end

local function CleanupPropsAndPanels()
    for k, v in pairs(activeCeilingMonitors) do
        if DoesEntityExist(v) then
            DeleteEntity(v)
        end
    end
    activeCeilingMonitors = {}
    
    for k, v in pairs(activePanels) do
        TriggerEvent("plt_xray:client:destroyPanel", v)
    end
    activePanels = {}
    monitorPowerState = {}
end

local function CreateMonitorPanel(prop, id, options)
    if not DoesEntityExist(prop) then return end
    
    if GetResourceState("plt_xray") == "started" then
        TriggerEvent("plt_xray:client:createMonitorPanel", prop, id, options)
    else
        print("^3[plt_ambulance] plt_xray not started yet; monitor panel queued for refresh.^7")
    end
end

local savedCivilianClothes = nil

local function SaveCivilianClothes()
    local identifier = ""
    local pData = Framework.GetPlayerData()
    if pData then
        identifier = pData.citizenid or pData.identifier or pData.license or ""
    end
    if identifier == "" then
        identifier = GetPlayerServerId(PlayerId())
    end
    
    local kvpKey = string.format("plt_amb_civilian_clothes_%s", tostring(identifier))
    local ped = PlayerPedId()
    local clothesData = {}
    
    for i = 0, 11 do
        clothesData[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
            palette = GetPedPaletteVariation(ped, i)
        }
    end
    
    clothesData.props = {}
    for i = 0, 7 do
        clothesData.props[i] = {
            drawable = GetPedPropIndex(ped, i),
            texture = GetPedPropTextureIndex(ped, i)
        }
    end
    
    local encoded = json.encode(clothesData)
    if kvpKey and encoded then
        pcall(function()
            SetResourceKvp(kvpKey, encoded)
        end)
    end
    savedCivilianClothes = clothesData
end

local function RestoreCivilianClothes()
    local function GetIdentifierKey()
        local identifier = ""
        local pData = Framework.GetPlayerData()
        if pData then
            identifier = pData.citizenid or pData.identifier or pData.license or ""
        end
        if identifier == "" then
            identifier = GetPlayerServerId(PlayerId())
        end
        return string.format("plt_amb_civilian_clothes_%s", tostring(identifier))
    end
    
    local function TryReloadSkinScripts()
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
    if not savedCivilianClothes then
        local kvpKey = GetIdentifierKey()
        local dataStr = nil
        
        if kvpKey then
            pcall(function()
                dataStr = GetResourceKvpString(kvpKey)
            end)
            if dataStr and dataStr ~= "" then
                local success, decoded = pcall(json.decode, dataStr)
                if success and type(decoded) == "table" then
                    savedCivilianClothes = decoded
                end
            end
        end
        
        if not savedCivilianClothes then
            TryReloadSkinScripts()
            return
        end
    end
    
    for i = 0, 11 do
        local comp = savedCivilianClothes[i]
        if comp then
            SetPedComponentVariation(ped, i, comp.drawable, comp.texture, comp.palette)
        end
    end
    
    for i = 0, 7 do
        local prop = savedCivilianClothes.props[i]
        if prop then
            if prop.drawable == -1 then
                ClearPedProp(ped, i)
            else
                SetPedPropIndex(ped, i, prop.drawable, prop.texture, true)
            end
        end
    end
    
    savedCivilianClothes = nil
    local kvpKey = GetIdentifierKey()
    if kvpKey then
        pcall(function()
            DeleteResourceKvp(kvpKey)
        end)
    end
end

local function GetWardrobeForNode(nodeId)
    if not (DepartmentData and DepartmentData.nodes) then return false end
    
    local wardrobeNode = nil
    for _, node in ipairs(DepartmentData.nodes) do
        if tostring(node.id) == tostring(nodeId) and node.type == "wardrobe" then
            wardrobeNode = node
            break
        end
    end
    
    if not (wardrobeNode and type(wardrobeNode.outfits) == "table") then return false end
    
    local pData = Framework.GetPlayerData()
    if not (pData and pData.job) then return false end
    
    local gradeLevel = 0
    if type(pData.job.grade) == "table" then
        gradeLevel = pData.job.grade.level or pData.job.grade
    else
        gradeLevel = pData.job.grade
    end
    gradeLevel = tonumber(gradeLevel) or 0
    
    local rankKey = "rank_" .. tostring(gradeLevel)
    local outfit = wardrobeNode.outfits[rankKey]
    
    if type(outfit) ~= "table" then return false end
    
    local ped = PlayerPedId()
    if not savedCivilianClothes then
        SaveCivilianClothes()
    end
    
    local function ApplyComponent(compId, data)
        if type(data) ~= "table" then return end
        local item = tonumber(data.item)
        if item == nil then return end
        local texture = tonumber(data.texture) or 0
        SetPedComponentVariation(ped, compId, item, texture, 0)
    end
    
    ApplyComponent(4, outfit.pants)
    ApplyComponent(11, outfit.shirt)
    ApplyComponent(9, outfit.vest)
    ApplyComponent(6, outfit.shoes)
    
    if type(outfit.hat) == "table" and outfit.hat.item ~= nil then
        local item = tonumber(outfit.hat.item) or -1
        local texture = tonumber(outfit.hat.texture) or 0
        if item < 0 then
            ClearPedProp(ped, 0)
        else
            SetPedPropIndex(ped, 0, item, texture, true)
        end
    end
    
    return true
end

RegisterNetEvent("amb_client:Notify", function(msg, type)
    if not Config.ShowNotifications then return end
    
    local title = _L("notify_title_alert")
    if type == "error" then
        title = _L("notify_title_error")
    elseif type == "success" then
        title = _L("notify_title_success")
    elseif type == "primary" or type == "info" then
        title = _L("notify_title_info")
    elseif type == "warning" then
        title = _L("notify_title_warning")
    end
    
    SendNUIMessage({
        action = "amb_showNotification",
        title = title,
        message = msg
    })
end)

RegisterNetEvent("amb_client:PushLocaleToUI", function(locale)
    SendNUIMessage({
        action = "amb_setLocale",
        locale = locale or {}
    })
end)

local function SendUISettings()
    SendNUIMessage({
        action = "amb_setUISettings",
        blurEnabled = (Config.EnableBlurEffect ~= false)
    })
end

CreateThread(function()
    Wait(500)
    SendUISettings()
end)

local function GetDepartmentForNode(nodeId, deptData)
    if not (deptData and deptData.nodes and deptData.links) then return nodeId end
    
    for _, node in ipairs(deptData.nodes) do
        if node.type == "department" and node.id == nodeId then
            if node.frameworkJob and node.frameworkJob ~= "" then
                return node.frameworkJob
            end
            return nodeId
        end
    end
    return nodeId
end

local function HasJobOrAdmin(nodeId)
    if not nodeId then return true end
    
    local pData = Framework.GetPlayerData()
    if not pData then return false end
    
    if IsAdmin and Config.AdminBypass then return true end
    
    local jobName = (pData.job and pData.job.name) and pData.job.name or "none"
    local citizenId = pData.citizenid
    
    local memberJob = "none"
    if MemberData[citizenId] and MemberData[citizenId].job then
        memberJob = MemberData[citizenId].job
    end
    
    local deptId = GetDepartmentForNode(nodeId, DepartmentData)
    
    if tostring(jobName) == tostring(nodeId) or tostring(jobName) == tostring(deptId) or tostring(memberJob) == tostring(nodeId) then
        return true
    end
    
    if Config.Medical and Config.Medical.EMSJobs then
        for _, emsJob in ipairs(Config.Medical.EMSJobs) do
            if jobName == emsJob or memberJob == emsJob then
                if tostring(nodeId) == tostring(emsJob) or tostring(deptId) == tostring(emsJob) then
                    return true
                end
            end
        end
    end
    
    return false
end

function IsEMS()
    local pData = Framework.GetPlayerData()
    if not pData then return false end
    
    if IsAdmin and Config.AdminBypass then return true end
    
    local jobName = (pData.job and pData.job.name) and pData.job.name or "none"
    local citizenId = pData.citizenid
    local memberJob = "none"
    
    if MemberData[citizenId] and MemberData[citizenId].job then
        memberJob = MemberData[citizenId].job
    end
    
    if Config.Medical and Config.Medical.EMSJobs then
        for _, emsJob in ipairs(Config.Medical.EMSJobs) do
            if jobName == emsJob or memberJob == emsJob then
                return true
            end
        end
    end
    
    if not (DepartmentData and DepartmentData.nodes) then return false end
    
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "department" then
            local checkId = node.id
            if node.frameworkJob and node.frameworkJob ~= "" then
                checkId = node.frameworkJob
            end
            
            if tostring(jobName) == tostring(checkId) or tostring(jobName) == tostring(node.id) or tostring(memberJob) == tostring(checkId) then
                return true
            end
        end
    end
    
    return false
end
exports("IsEMS", IsEMS)

local function CheckPermissions()
    Framework.TriggerCallback("amb_server:checkPermissions", function(isAdmin)
        IsAdmin = isAdmin
    end, Config.Permission)
end

local function GetDirectionFromHeading(heading)
    local rad = math.rad(heading)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

local function NormalizeVector(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length <= 1.0E-4 then
        return vector3(0.0, 0.0, 0.0)
    end
    return vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function RotateVector(vec, axis, angle)
    local rad = math.rad(angle)
    local cosA = math.cos(rad)
    local sinA = math.sin(rad)
    
    local cross = vector3(
        axis.y * vec.z - axis.z * vec.y,
        axis.z * vec.x - axis.x * vec.z,
        axis.x * vec.y - axis.y * vec.x
    )
    
    local dot = (axis.x * vec.x) + (axis.y * vec.y) + (axis.z * vec.z)
    
    return (vec * cosA) + (cross * sinA) + (axis * (dot * (1 - cosA)))
end

local function CalculateScreenVectors(nodeCoords)
    local heading = nodeCoords.h or 0.0
    local screenNormal = NormalizeVector(GetDirectionFromHeading(heading))
    local screenUp = vector3(0.0, 0.0, 1.0)
    
    local pitch = tonumber(nodeCoords.pitch) or 0.0
    if math.abs(pitch) > 0.001 then
        local rightVec = NormalizeVector(vector3(
            screenNormal.y * screenUp.z - screenNormal.z * screenUp.y,
            screenNormal.z * screenUp.x - screenNormal.x * screenUp.z,
            screenNormal.x * screenUp.y - screenNormal.y * screenUp.x
        ))
        
        screenNormal = NormalizeVector(RotateVector(screenNormal, rightVec, pitch))
        screenUp = NormalizeVector(RotateVector(screenUp, rightVec, pitch))
    end
    
    return screenNormal, screenUp
end

local function GetCleanLabel(label, fallback)
    if label and label ~= "" then
        local lowerLabel = label:lower()
        if not lowerLabel:find("new location") and not lowerLabel:find("new department") and not lowerLabel:find("new boss") and not lowerLabel:find("new vehicle") and not lowerLabel:find("new armory") and not lowerLabel:find("new door") and not lowerLabel:find("new rank") and not lowerLabel:find("new permission") then
            if label:lower() == fallback:lower() then return fallback end
            return label
        end
    end
    return fallback
end
exports("GetFramework", function() return Framework end)

function GetLinkedNodeByType(nodeId, nodeType, deptData)
    if not (deptData and deptData.links and deptData.nodes) then return nil end
    
    nodeId = tostring(nodeId)
    local visited = { [nodeId] = true }
    local queue = { nodeId }
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, link in ipairs(deptData.links) do
            local nextNode = nil
            if tostring(link.to) == current then
                nextNode = tostring(link.from)
            elseif tostring(link.from) == current then
                nextNode = tostring(link.to)
            end
            
            if nextNode and not visited[nextNode] then
                for _, node in ipairs(deptData.nodes) do
                    if tostring(node.id) == nextNode then
                        if node.type == nodeType then
                            return node
                        end
                        visited[nextNode] = true
                        table.insert(queue, nextNode)
                        break
                    end
                end
            end
        end
    end
    return nil
end

function HasPermissionForNode(nodeId, nodeType, deptData)
    if IsAdmin and Config.AdminBypass then return true end
    
    local deptId = GetDepartmentForNode(nodeId, deptData)
    if not deptId then return true end
    
    local pData = Framework.GetPlayerData()
    if not pData then return false end
    
    local citizenId = pData.citizenid
    local jobName = (pData.job and pData.job.name) and pData.job.name or "none"
    
    local gradeLevel = 0
    if pData.job then
        if type(pData.job.grade) == "table" then
            gradeLevel = pData.job.grade.level or pData.job.grade
        else
            gradeLevel = pData.job.grade
        end
    end
    gradeLevel = tonumber(gradeLevel) or 0
    
    if MemberData[citizenId] then
        if tostring(MemberData[citizenId].job) == tostring(deptId) then
            jobName = MemberData[citizenId].job
            gradeLevel = tonumber(MemberData[citizenId].grade) or gradeLevel
        end
    end
    
    if not HasJobOrAdmin(deptId) then return false end
    
    local rankNode = GetLinkedNodeByType(deptId, "rank", deptData)
    local isBossMenu = (nodeType:lower() == "boss_menu")
    
    if not rankNode then
        if isBossMenu then return false end
        return true
    end
    
    if isBossMenu then
        local isBoss = false
        if type(rankNode.ranks) == "table" then
            for _, rank in ipairs(rankNode.ranks) do
                if tonumber(rank.level) == gradeLevel then
                    if rank.bossMenu == true then
                        return true
                    end
                    break
                end
            end
        end
        return false
    end
    
    local permissionNode = GetLinkedNodeByType(rankNode.id, "permission", deptData)
    if not permissionNode then
        if isBossMenu then return false end
        return true
    end
    
    local rankKey = "rank_" .. tostring(gradeLevel)
    if type(permissionNode.rankPerms) == "table" then
        local perms = permissionNode.rankPerms[rankKey]
        if type(perms) == "table" then
            return HasSpecificPermission(perms, nodeType)
        end
    end
    
    if isBossMenu then return false end
    return true
end

function GetDepartmentForNode(nodeId, deptData)
    if not (deptData and deptData.links and deptData.nodes) then return nil end
    
    nodeId = tostring(nodeId)
    for _, node in ipairs(deptData.nodes) do
        if tostring(node.id) == nodeId then
            if node.type == "department" then
                return node.id
            end
        end
    end
    
    local visited = { [nodeId] = true }
    local queue = { nodeId }
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, link in ipairs(deptData.links) do
            local nextNode = nil
            if tostring(link.to) == current then
                nextNode = tostring(link.from)
            elseif tostring(link.from) == current then
                nextNode = tostring(link.to)
            end
            
            if nextNode and not visited[nextNode] then
                for _, node in ipairs(deptData.nodes) do
                    if tostring(node.id) == nextNode then
                        if node.type == "department" then
                            return node.id
                        end
                        visited[nextNode] = true
                        table.insert(queue, nextNode)
                        break
                    end
                end
            end
        end
    end
    return nil
end

local function GetPermissionKey(nodeType)
    if type(nodeType) ~= "string" then return nil end
    local cleaned = nodeType:lower():gsub("[%s%-%_]", "")
    if cleaned == "" then return nil end
    return cleaned
end

function HasSpecificPermission(permsTable, nodeType)
    local possibleKeys = {}
    local function AddKey(key)
        if type(key) == "string" and key ~= "" then
            table.insert(possibleKeys, key)
        end
    end
    
    local cleanNode = tostring(nodeType or ""):lower()
    AddKey(GetPermissionKey(nodeType))
    AddKey(_L("permission_" .. cleanNode))
    
    if cleanNode == "duty" then
        AddKey(_L("permission_duty"))
        AddKey("Duty")
    elseif cleanNode == "garage" or cleanNode == "helipad" or cleanNode == "vehicle" then
        AddKey(_L("permission_garage"))
        AddKey("Garage")
    elseif cleanNode == "inventory" then
        AddKey(_L("permission_inventory"))
        AddKey("Inventory")
    elseif cleanNode == "stash" or cleanNode == "wardrobe" then
        AddKey(_L("permission_stash"))
        AddKey("Stash")
    elseif cleanNode == "boss_menu" or cleanNode == "boss menu" then
        AddKey(_L("permission_boss_menu"))
        AddKey("Boss Menu")
        AddKey("BossMenu")
    elseif cleanNode == "xray" or cleanNode == "x-ray" then
        AddKey(_L("permission_xray"))
        AddKey("X-Ray")
        AddKey("Xray")
        AddKey("XRAY")
    end
    
    if type(permsTable) ~= "table" then return false end
    
    local permCache = {}
    for _, key in ipairs(possibleKeys) do
        local permKey = GetPermissionKey(key)
        if permKey then permCache[permKey] = true end
        if permsTable[key] == true then return true end
    end
    
    for k, v in pairs(permsTable) do
        if v == true then
            local checkKey = GetPermissionKey(k)
            if checkKey and permCache[checkKey] then return true end
        end
    end
    return false
end

local function RemoveAllTargetZones()
    if Config.Target == "ox_target" then
        for k, v in pairs(activeOxZones) do
            exports.ox_target:removeZone(v)
        end
    elseif Config.Target == "qb-target" then
        for k, v in pairs(activeOxZones) do
            exports["qb-target"]:RemoveZone(k)
        end
    end
    activeOxZones = {}
end

local function CreateZoneOrPed(nodeId, nodeType, coords, label, deptData, interactionType, deptId)
    if deptId and not IsCurrentPlacement(deptId) then return end
    
    local zoneId = "plt_amb_" .. nodeId .. "_" .. nodeType
    local cleanName = nodeType:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    local cleanLabel = GetCleanLabel(label, cleanName)
    
    local function CheckCanInteract(nId, nType, dData)
        local pData = Framework.GetPlayerData()
        if not pData then return false end
        if IsAdmin and Config.AdminBypass then return true end
        if not HasJobOrAdmin(deptData) then return false end
        if not HasPermissionForNode(nId, nType, dData) then return false end
        if nType == "duty" then return true end
        return pData.job.onduty == true
    end
    
    if interactionType == "ped" then
        if type(activePedsAndZones[zoneId]) == "number" then
            if DoesEntityExist(activePedsAndZones[zoneId]) then
                DeleteEntity(activePedsAndZones[zoneId])
            end
        end
        
        local doctorModel = (Config.LocalDoctor and Config.LocalDoctor.DoctorPedModel) and Config.LocalDoctor.DoctorPedModel or "s_m_m_doctor_01"
        local hash = GetHashKey(doctorModel)
        RequestModel(hash)
        
        local loops = 0
        while not HasModelLoaded(hash) and loops < 100 do
            Wait(10)
            loops = loops + 1
        end
        
        if deptId and not IsCurrentPlacement(deptId) then return end
        
        if HasModelLoaded(hash) then
            local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, coords.h or 0.0, false, false)
            SetEntityAsMissionEntity(ped, true, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            activePedsAndZones[zoneId] = ped
            SetModelAsNoLongerNeeded(hash)
        end
    end
    
    if deptId and not IsCurrentPlacement(deptId) then return end
    
    if Config.Target == "ox_target" then
        local options = nil
        if nodeType == "wardrobe" then
            options = {
                {
                    icon = "fas fa-user-nurse",
                    label = "Wear EMS Clothes",
                    onSelect = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = nodeType,
                            job = deptData,
                            nodeId = nodeId,
                            coords = coords,
                            label = cleanLabel,
                            wardrobeAction = "ems"
                        })
                    end,
                    canInteract = CheckCanInteract,
                    distance = 3.0
                },
                {
                    icon = "fas fa-user",
                    label = "Wear Civilian Clothes",
                    onSelect = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = nodeType,
                            job = deptData,
                            nodeId = nodeId,
                            coords = coords,
                            label = cleanLabel,
                            wardrobeAction = "civilian"
                        })
                    end,
                    canInteract = CheckCanInteract,
                    distance = 3.0
                }
            }
        else
            options = {
                {
                    icon = "fas fa-hand-pointer",
                    label = cleanLabel,
                    onSelect = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = nodeType,
                            job = deptData,
                            nodeId = nodeId,
                            coords = coords,
                            label = cleanLabel
                        })
                    end,
                    canInteract = CheckCanInteract,
                    distance = 3.0
                }
            }
        end
        
        local zone = exports.ox_target:addSphereZone({
            coords = vector3(coords.x, coords.y, coords.z),
            radius = 1.2,
            debug = false,
            options = options
        })
        activeQbZones[zoneId] = zone
        
    elseif Config.Target == "qb-target" then
        local options = nil
        if nodeType == "wardrobe" then
            options = {
                {
                    type = "client",
                    action = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = nodeType,
                            job = deptData,
                            nodeId = nodeId,
                            coords = coords,
                            label = cleanLabel,
                            wardrobeAction = "ems"
                        })
                    end,
                    icon = "fas fa-user-nurse",
                    label = "Wear EMS Clothes",
                    canInteract = CheckCanInteract
                },
                {
                    type = "client",
                    action = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = nodeType,
                            job = deptData,
                            nodeId = nodeId,
                            coords = coords,
                            label = cleanLabel,
                            wardrobeAction = "civilian"
                        })
                    end,
                    icon = "fas fa-user",
                    label = "Wear Civilian Clothes",
                    canInteract = CheckCanInteract
                }
            }
        else
            options = {
                {
                    type = "client",
                    action = function()
                        TriggerEvent("amb_client:Interact", {
                            locType = nodeType,
                            job = deptData,
                            nodeId = nodeId,
                            coords = coords,
                            label = cleanLabel
                        })
                    end,
                    icon = "fas fa-hand-pointer",
                    label = cleanLabel,
                    canInteract = CheckCanInteract
                }
            }
        end
        
        exports["qb-target"]:AddCircleZone(zoneId, vector3(coords.x, coords.y, coords.z), 1.2, {
            name = zoneId,
            debugPoly = false,
            useZ = true
        }, {
            options = options,
            distance = 3.0
        })
        activeQbZones[zoneId] = true
    end
end

local function ParseCoordsList(coordsList)
    local list = {}
    local function AddCoord(c)
        if c and c.x and c.y and c.z then
            table.insert(list, {
                x = tonumber(c.x) or c.x,
                y = tonumber(c.y) or c.y,
                z = tonumber(c.z) or c.z,
                h = tonumber(c.h) or 0.0
            })
        end
    end
    
    if not coordsList then return list end
    
    if type(coordsList.bed) == "table" then
        if coordsList.bed.x and coordsList.bed.y and coordsList.bed.z then
            AddCoord(coordsList.bed)
        else
            for _, c in ipairs(coordsList.bed) do AddCoord(c) end
        end
    end
    
    if type(coordsList.beds) == "table" then
        if coordsList.beds.x and coordsList.beds.y and coordsList.beds.z then
            AddCoord(coordsList.beds)
        else
            for _, c in ipairs(coordsList.beds) do AddCoord(c) end
        end
    end
    
    return list
end

local function IsBedOccupied(coords, ignorePed)
    local checkVec = vector3(coords.x, coords.y, coords.z)
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped and ped ~= 0 and ped ~= ignorePed then
            if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
                local dist = #(GetEntityCoords(ped) - checkVec)
                if dist <= 1.2 then return true end
            end
        end
    end
    return false
end

local function GetFreeBed(beds, ignorePed)
    if not beds or #beds == 0 then return nil end
    for _, bed in ipairs(beds) do
        if not IsBedOccupied(bed, ignorePed) then return bed end
    end
    return beds[1]
end

local function SetupCheckInZone(nodeId, checkinCoords, beds, locationName, deptData, minEMS, deptId)
    if deptId and not IsCurrentPlacement(deptId) then return end
    
    local zoneId = "plt_amb_checkin_" .. nodeId
    local healTime = (Config.LocalDoctor and Config.LocalDoctor.HealTime) and Config.LocalDoctor.HealTime or 15000
    local lieAnim = (Config.LocalDoctor and Config.LocalDoctor.LieAnim) and Config.LocalDoctor.LieAnim or { dict = "amb@world_human_sunbathe@male@back@base", name = "base" }
    minEMS = minEMS or 1
    
    checkInZones[nodeId] = {
        checkinCoords = checkinCoords,
        beds = beds,
        locationName = locationName,
        healTime = healTime,
        lieAnim = lieAnim,
        minEMS = minEMS
    }
    
    if activeOxZones[zoneId] and DoesEntityExist(activeOxZones[zoneId]) then
        DeleteEntity(activeOxZones[zoneId])
    end
    
    local function CheckInAction()
        Framework.TriggerCallback("amb_server:getEMSOnDutyCount", function(count)
            if count >= minEMS then
                Framework.Notify(_L("local_doctor_busy", { count = count }), "info")
                return
            end
            
            local ped = PlayerPedId()
            if exports.plt_ambulance_job:GetInjuryType() == "fatal" then return end
            
            local freeBed = GetFreeBed(beds, ped)
            if not freeBed then
                Framework.Notify(_L("no_checkin_bed"), "error")
                return
            end
            
            SetEntityCoords(ped, freeBed.x, freeBed.y, freeBed.z, false, false, false, false)
            SetEntityHeading(ped, freeBed.h or 0.0)
            FreezeEntityPosition(ped, true)
            Framework.RequestAnimDict(lieAnim.dict)
            TaskPlayAnim(ped, lieAnim.dict, lieAnim.name, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            
            Framework.Notify(_L("local_doctor_treating"), "info")
            CreateThread(function()
                local startTime = GetGameTimer()
                while GetGameTimer() - startTime < healTime do
                    Wait(0)
                    if IsControlJustPressed(0, 73) then
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
    end
    
    if Config.Target == "ox_target" then
        local zone = exports.ox_target:addSphereZone({
            coords = vector3(checkinCoords.x, checkinCoords.y, checkinCoords.z),
            radius = 1.5,
            debug = false,
            options = {
                {
                    icon = "fas fa-user-md",
                    label = _L("checkin_local_doctor"),
                    onSelect = CheckInAction,
                    distance = 3.0
                }
            }
        })
        activeQbZones[zoneId] = zone
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddCircleZone(zoneId, vector3(checkinCoords.x, checkinCoords.y, checkinCoords.z), 1.5, {
            name = zoneId,
            debugPoly = false,
            useZ = true
        }, {
            options = {
                {
                    type = "client",
                    action = function()
                        TriggerEvent("amb_client:LocalDoctorCheckIn", { nodeId = nodeId })
                    end,
                    icon = "fas fa-user-md",
                    label = _L("checkin_local_doctor")
                }
            },
            distance = 3.0
        })
        activeQbZones[zoneId] = true
    end
    
    local doctorModel = (Config.LocalDoctor and Config.LocalDoctor.DoctorPedModel) and Config.LocalDoctor.DoctorPedModel or "s_m_m_doctor_01"
    local hash = GetHashKey(doctorModel)
    RequestModel(hash)
    
    local loops = 0
    while not HasModelLoaded(hash) and loops < 100 do
        Wait(10)
        loops = loops + 1
    end
    
    if deptId and not IsCurrentPlacement(deptId) then return end
    
    if HasModelLoaded(hash) then
        local ped = CreatePed(4, hash, checkinCoords.x, checkinCoords.y, checkinCoords.z, checkinCoords.h or 0.0, false, false)
        if deptId and not IsCurrentPlacement(deptId) then
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            return
        end
        
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        activeOxZones[zoneId] = ped
        SetModelAsNoLongerNeeded(hash)
    end
end

local function RemoveAllDoctorPeds()
    for k, v in pairs(activeOxZones) do
        if DoesEntityExist(v) then
            DeleteEntity(v)
        end
    end
    activeOxZones = {}
end

local function ToggleVitalsMonitor(id)
    id = tostring(id)
    local state = monitorStateCache[id] ~= true
    monitorStateCache[id] = state
    TriggerServerEvent("plt_xray:server:setMonitorPower", id, state)
    
    Framework.Notify(_L("monitor_state", { state = state and _L("monitor_state_on") or _L("monitor_state_off") }), "success")
end

RegisterNetEvent("plt_ambulance:client:setMonitorPowerMirror", function(id, powerOn)
    id = tostring(id)
    monitorStateCache[id] = (powerOn == true)
    TriggerEvent("plt_xray:client:setMonitorPower", id, powerOn == true)
end)

local function LieOnTreatmentBed(coords, heading)
    local ped = PlayerPedId()
    if isLyingOnBed then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        isLyingOnBed = false
        currentBedAnim = nil
        LocalPlayer.state:set("isLyingOnBed", false, true)
    else
        isLyingOnBed = true
        LocalPlayer.state:set("isLyingOnBed", true, true)
        local dict = "anim@gangops@morgue@table@"
        local anim = "ko_front"
        
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do Wait(10) end
        
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
        SetEntityHeading(ped, heading)
        FreezeEntityPosition(ped, true)
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
        currentBedAnim = { ad = dict, anim = anim }
        
        Framework.Notify(_L("lying_on_bed_exit"), "info")
        CreateThread(function()
            while isLyingOnBed do
                if not IsEntityPlayingAnim(ped, dict, anim, 3) then
                    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
                end
                if IsControlJustPressed(0, 73) then
                    LieOnTreatmentBed()
                    break
                end
                Wait(0)
            end
        end)
    end
end

local function CanInteractWithBed(coords, radius)
    local ped = PlayerPedId()
    radius = radius or 1.7
    for _, player in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(player)
        if targetPed and targetPed ~= 0 and targetPed ~= ped then
            if DoesEntityExist(targetPed) then
                local dist = #(GetEntityCoords(targetPed) - coords)
                if dist <= radius then
                    local serverId = GetPlayerServerId(player)
                    local pState = Player(serverId) and Player(serverId).state or nil
                    local isLying = pState and pState.isLyingOnBed == true
                    local isAnim = IsEntityPlayingAnim(targetPed, "anim@gangops@morgue@table@", "ko_front", 3)
                    
                    if isLying or isAnim then
                        return targetPed
                    end
                end
            end
        end
    end
    return nil
end

local function DiagnosePatientOnBed(coords)
    if not IsEMS() and not HasJobOrAdmin() then return false end
    local pData = Framework.GetPlayerData()
    if not pData then return false end
    
    if not (pData.job and pData.job.onduty == true) then
        if not (IsAdmin and Config.AdminBypass) then return false end
    end
    
    local targetPed = CanInteractWithBed(coords, 1.7)
    if targetPed ~= nil then
        if type(StartDiagnosis) == "function" then
            StartDiagnosis(targetPed)
        else
            Framework.Notify(_L("diagnosis_no_patient_id"), "error")
        end
    else
        Framework.Notify(_L("diagnosis_no_patient_id"), "error")
    end
end

exports("GetVitalsData", function()
    local ped = PlayerPedId()
    if not isLyingOnBed then
        local health = GetEntityHealth(ped)
        if health > 195 then
            return { pulse = 0, bp = "0/0", o2 = 0, stress = 0 }
        end
    end
    
    local health = GetEntityHealth(ped)
    local healthLost = (GetEntityMaxHealth(ped) - 100) - (health - 100)
    
    local pulse = 60 + math.floor(healthLost * 0.4)
    if health < 10 then pulse = 0 end
    
    local sysBP = 110 + math.random(0, 20)
    local diaBP = 70 + math.random(0, 15)
    
    if health < 50 then
        sysBP = sysBP - (50 - health)
        diaBP = diaBP - ((50 - health) * 0.5)
    end
    
    local o2 = 95 + math.random(0, 4)
    if health < 40 then
        o2 = 80 + math.random(0, 10)
    end
    
    local stress = math.random(10, 30)
    return {
        pulse = pulse,
        bp = string.format("%d/%d", sysBP, diaBP),
        o2 = o2,
        stress = stress
    }
end)

local function RefreshBlipsAndZones(deptData)
    local currentId = GetNextPlacementId()
    DepartmentData = deptData
    
    for k, v in pairs(activeOxZones) do
        if DoesBlipExist(v) then RemoveBlip(v) end
    end
    activeOxZones = {}
    
    RemoveAllTargetZones()
    RemoveAllZones()
    RemoveAllDoctorPeds()
    CleanupPropsAndPanels()
    
    activeQbZones = {}
    if Config.Target == "ox_target" then
        for k, v in pairs(unknownCache1) do exports.ox_target:removeZone(v) end
    elseif Config.Target == "qb-target" then
        for k, v in pairs(unknownCache1) do exports["qb-target"]:RemoveZone(k) end
    end
    unknownCache1 = {}
    
    if Config.Target == "ox_target" then
        for k, v in pairs(unknownCache2) do
            if type(v) == "number" then exports.ox_target:removeZone(v) end
        end
    elseif Config.Target == "qb-target" then
        for k, v in pairs(unknownCache2) do exports["qb-target"]:RemoveZone(k) end
    end
    unknownCache2 = {}
    checkInCoordsCache = {}
    
    if not (deptData and deptData.nodes) then return end
    
    for _, node in ipairs(deptData.nodes) do
        local deptId = GetDepartmentForNode(node.id, deptData)
        if node.type == "department" and node.coords then
            local blip = AddBlipForCoord(node.coords.x, node.coords.y, node.coords.z)
            SetBlipSprite(blip, node.blipId or 61)
            SetBlipColour(blip, node.blipColor or 1)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(GetCleanLabel(node.label, "Department"))
            EndTextCommandSetBlipName(blip)
            activeOxZones[node.id] = blip
        end
        
        if node.type == "pharmacy" and node.coords and node.coords.x then
            local zoneName = "plt_pharmacy_dynamic_" .. node.id
            if Config.Target == "ox_target" then
                local zoneId = exports.ox_target:addSphereZone({
                    coords = vector3(node.coords.x, node.coords.y, node.coords.z),
                    radius = 1.2,
                    debug = false,
                    options = {
                        {
                            name = zoneName,
                            icon = "fas fa-prescription-bottle-medical",
                            label = _L("pharmacy_terminal"),
                            onSelect = function()
                                TriggerEvent("amb_client:openPharmacy", deptId)
                            end,
                            distance = 2.0
                        }
                    }
                })
                unknownCache1[node.id] = zoneId
            elseif Config.Target == "qb-target" then
                exports["qb-target"]:AddBoxZone(zoneName, vector3(node.coords.x, node.coords.y, node.coords.z), 1.2, 1.2, {
                    name = zoneName,
                    heading = node.coords.h or 0.0,
                    debugPoly = false,
                    minZ = node.coords.z - 1.0,
                    maxZ = node.coords.z + 1.0
                }, {
                    options = {
                        {
                            type = "client",
                            action = function()
                                TriggerEvent("amb_client:openPharmacy", { jobName = deptId })
                            end,
                            icon = "fas fa-prescription-bottle-medical",
                            label = _L("pharmacy_terminal")
                        }
                    },
                    distance = 2.0
                })
                unknownCache1[node.id] = true
            end
        end
        
        if node.type == "ceiling_monitor" and node.coordsList and node.coordsList.monitor and node.coordsList.bed then
            local monitor = node.coordsList.monitor
            if monitor.x then
                local hash = 389765485
                RequestModel(hash)
                local attempts = 0
                while not HasModelLoaded(hash) and attempts < 100 do Wait(10) attempts = attempts + 1 end
                
                if HasModelLoaded(hash) then
                    local prop = CreateObject(hash, tonumber(monitor.x), tonumber(monitor.y), tonumber(monitor.z), false, false, false)
                    if DoesEntityExist(prop) then
                        SetEntityHeading(prop, tonumber(monitor.h) or 0.0)
                        SetEntityCoords(prop, tonumber(monitor.x), tonumber(monitor.y), tonumber(monitor.z), false, false, false, true)
                        SetEntityAsMissionEntity(prop, true, true)
                        FreezeEntityPosition(prop, true)
                        table.insert(activeCeilingMonitors, prop)
                        
                        print("^2[plt_ambulance] Spawned Ceiling Monitor Prop at " .. tostring(vector3(tonumber(monitor.x), tonumber(monitor.y), tonumber(monitor.z))) .. "^7")
                        CreateMonitorPanel(prop, node.id, deptData)
                        
                        monitorStateCache[node.id] = false
                        local targetName = "plt_monitor_" .. node.id
                        
                        if Config.Target == "ox_target" then
                            local zoneId = exports.ox_target:addLocalEntity(prop, {
                                {
                                    name = targetName,
                                    label = _L("monitor_toggle"),
                                    icon = "fas fa-power-off",
                                    onSelect = function() ToggleVitalsMonitor(node.id) end,
                                    canInteract = function() return HasPermissionForNode(node.id, "ceiling_monitor", DepartmentData) end
                                }
                            })
                            activePedsAndZones[targetName] = zoneId
                        else
                            exports["qb-target"]:AddTargetEntity(prop, {
                                options = {
                                    {
                                        type = "client",
                                        action = function() ToggleVitalsMonitor(node.id) end,
                                        icon = "fas fa-power-off",
                                        label = _L("monitor_toggle"),
                                        canInteract = function() return HasPermissionForNode(node.id, "ceiling_monitor", DepartmentData) end
                                    }
                                },
                                distance = 2.0
                            })
                        end
                        
                        local bed = node.coordsList.bed
                        if bed and bed.x then
                            local bVec = vector3(tonumber(bed.x), tonumber(bed.y), tonumber(bed.z))
                            local bHeading = tonumber(bed.h) or 0.0
                            local bedTarget = "plt_bed_" .. node.id
                            
                            if Config.Target == "ox_target" then
                                local zoneId = exports.ox_target:addSphereZone({
                                    coords = bVec,
                                    radius = 1.0,
                                    options = {
                                        {
                                            name = bedTarget,
                                            label = _L("bed_lie"),
                                            icon = "fas fa-bed",
                                            onSelect = function() LieOnTreatmentBed(bVec, bHeading) end
                                        },
                                        {
                                            name = bedTarget .. "_diagnose",
                                            label = _L("diagnose_injuries"),
                                            icon = "fas fa-stethoscope",
                                            onSelect = function() DiagnosePatientOnBed(bVec) end,
                                            canInteract = function() return CanInteractWithBed(bVec) ~= nil end
                                        }
                                    }
                                })
                                activePedsAndZones[bedTarget] = zoneId
                            else
                                exports["qb-target"]:AddBoxZone(bedTarget, bVec, 1.0, 2.0, {
                                    name = bedTarget,
                                    heading = bHeading,
                                    debugPoly = false,
                                    minZ = bVec.z - 0.5,
                                    maxZ = bVec.z + 0.5
                                }, {
                                    options = {
                                        {
                                            type = "client",
                                            action = function() LieOnTreatmentBed(bVec, bHeading) end,
                                            icon = "fas fa-bed",
                                            label = _L("bed_lie")
                                        },
                                        {
                                            type = "client",
                                            action = function() DiagnosePatientOnBed(bVec) end,
                                            icon = "fas fa-stethoscope",
                                            label = _L("diagnose_injuries"),
                                            canInteract = function() return CanInteractWithBed(bVec) ~= nil end
                                        }
                                    },
                                    distance = 2.0
                                })
                                activePedsAndZones[bedTarget] = bedTarget
                            end
                        end
                    else
                        print("^1[plt_ambulance] ERROR: Failed to create Ceiling Monitor Prop!^7")
                    end
                    SetModelAsNoLongerNeeded(hash)
                else
                    print("^1[plt_ambulance] ERROR: Failed to load Ceiling Monitor Model!^7")
                end
            end
        end
        
        if node.type == "xray" and node.coordsList and node.coordsList.pc and node.coordsList.bed then
            local pc = node.coordsList.pc
            local bed = node.coordsList.bed
            
            if pc and pc.x then
                local screenNormal, screenUp = nil, nil
                if pc and pc.x then
                    screenNormal, screenUp = CalculateScreenVectors(pc)
                end
                
                TriggerEvent("plt_xray:client:updateConfigFromNode", {
                    Computer = pc and {
                        pos = vector3(pc.x, pc.y, pc.z),
                        heading = pc.h or 0.0,
                        screenNormal = screenNormal or GetDirectionFromHeading(pc.h or 0.0),
                        screenUp = screenUp or vector3(0.0, 0.0, 1.0),
                        width = 0.47,
                        height = 0.31
                    } or nil,
                    ScanBed = bed and {
                        pos = vector3(bed.x, bed.y, bed.z),
                        radius = 2.0
                    } or nil
                })
                
                local pcTarget = "plt_xray_pc_" .. node.id
                local function canUseXray()
                    if not HasPermissionForNode(node.id, "xray", DepartmentData) then return false end
                    if Framework.Type == "esx" then return true end
                    if IsAdmin and Config.AdminBypass then return true end
                    local pData = Framework.GetPlayerData()
                    if pData and pData.job then return pData.job.onduty == true end
                    return false
                end
                
                if Config.Target == "ox_target" then
                    local zoneId = exports.ox_target:addSphereZone({
                        coords = vector3(pc.x, pc.y, pc.z),
                        radius = 1.0,
                        debug = false,
                        options = {
                            {
                                icon = "fas fa-desktop",
                                label = _L("xray_terminal"),
                                onSelect = function() TriggerEvent("plt_xray:client:openFromNode") end,
                                canInteract = canUseXray,
                                distance = 2.0
                            }
                        }
                    })
                    activeQbZones[pcTarget] = zoneId
                else
                    exports["qb-target"]:AddCircleZone(pcTarget, vector3(pc.x, pc.y, pc.z), 1.0, {
                        name = pcTarget,
                        debugPoly = false,
                        useZ = true
                    }, {
                        options = {
                            {
                                type = "client",
                                action = function() TriggerEvent("plt_xray:client:openFromNode") end,
                                icon = "fas fa-desktop",
                                label = _L("xray_terminal"),
                                canInteract = canUseXray
                            }
                        },
                        distance = 2.0
                    })
                    activeQbZones[pcTarget] = true
                end
                
                local bedTarget = "plt_xray_bed_" .. node.id
                if bed and bed.x then
                    local bVec = vector3(tonumber(bed.x), tonumber(bed.y), tonumber(bed.z))
                    local bHeading = tonumber(bed.h) or 0.0
                    
                    if Config.Target == "ox_target" then
                        local zoneId = exports.ox_target:addSphereZone({
                            coords = bVec,
                            radius = 1.0,
                            options = {
                                {
                                    name = bedTarget,
                                    label = _L("bed_lie"),
                                    icon = "fas fa-bed",
                                    onSelect = function() LieOnTreatmentBed(bVec, bHeading) end
                                }
                            }
                        })
                        activePedsAndZones[bedTarget] = zoneId
                    else
                        exports["qb-target"]:AddBoxZone(bedTarget, bVec, 1.0, 2.0, {
                            name = bedTarget,
                            heading = bHeading,
                            debugPoly = false,
                            minZ = bVec.z - 0.5,
                            maxZ = bVec.z + 0.5
                        }, {
                            options = {
                                {
                                    type = "client",
                                    action = function() LieOnTreatmentBed(bVec, bHeading) end,
                                    icon = "fas fa-bed",
                                    label = _L("bed_lie")
                                }
                            },
                            distance = 2.0
                        })
                        activePedsAndZones[bedTarget] = bedTarget
                    end
                end
            end
        end
        
        if node.coordsList then
            for idx, cList in pairs(node.coordsList) do
                if cList and cList.x and node.type ~= "xray" and node.type ~= "check_in" and node.type ~= "ceiling_monitor" then
                    local interactType = (node.interactionTypes and node.interactionTypes[idx]) and node.interactionTypes[idx] or "zone"
                    CreateZoneOrPed(node.id, idx, cList, node.label, deptData, interactType, currentId)
                end
            end
        end
        
        if (node.type == "vehicle" or node.type == "helipad") and node.deletePoints then
            local allowedModels = {}
            if type(node.vehicles) == "table" then
                for _, v in ipairs(node.vehicles) do
                    if type(v) == "table" and v.model and tostring(v.model) ~= "" then
                        table.insert(allowedModels, tostring(v.model):lower())
                    end
                end
            end
            
            for _, dp in ipairs(node.deletePoints) do
                if dp and dp.x then
                    table.insert(unknownCache1, {
                        coords = dp,
                        job = deptData,
                        allowedModels = allowedModels
                    })
                end
            end
        end
        
        if node.type ~= "department" and node.type ~= "pharmacy" and node.type ~= "ceiling_monitor" then
            if node.coords and node.coords.x then
                if not (node.coordsList and node.coordsList[node.type]) then
                    CreateZoneOrPed(node.id, node.type, node.coords, node.label, deptData, "zone", currentId)
                end
            end
        end
    end
    
    Framework.TriggerCallback("amb_server:getEMSOnDutyCount", function(count)
        if not IsCurrentPlacement(currentId) then return end
        
        for _, node in ipairs(deptData.nodes) do
            if node.type == "check_in" then
                local beds = ParseCoordsList(node.coordsList)
                local checkin = (node.coordsList and node.coordsList.checkin) and node.coordsList.checkin or nil
                local minEMS = tonumber(node.minEMS) or 1
                
                if checkin and checkin.x and #beds > 0 then
                    local deptNode = GetLinkedNodeByType(node.id, "location", deptData)
                    local locName = (deptNode and deptNode.label) and deptNode.label or (node.label or _L("hospital"))
                    SetupCheckInZone(node.id, checkin, beds, locName, count >= minEMS, minEMS, currentId)
                end
            end
        end
    end)
end

RegisterNUICallback("startPlacement", function(data, cb)
    if isScreenBlurred then
        return cb("ok")
    end
    
    isScreenBlurred = true
    SetNuiFocus(false, false)
    local isSpawn = (data.locType == "spawn")
    
    SendNUIMessage({
        action = "amb_togglePlacementHelp",
        visible = true,
        header = _L("placement_header"),
        confirmLabel = _L("placement_confirm"),
        rotateLabel = isSpawn and _L("placement_rotate") or _L("placement_no_rotate")
    })
    
    CreateThread(function()
        local heading = isScreenBlurred and (GetEntityHeading(PlayerPedId()) or 0.0) or 0.0
        local pitch = 0.0
        local zOffset = 0.0
        local hash = nil
        local entity = nil
        local isBed = false
        local isPed = false
        
        if data.locType == "spawn" then
            hash = 1171614426
            if data.nodeId and data.nodeId:find("helipad") then
                hash = 353883353
            end
        elseif data.locType == "pc" then
            -- no hash
        elseif data.locType == "bed" then
            hash = 1631638868
            isBed = true
        elseif data.locType == "checkin" or data.interactionType == "ped" then
            hash = -730659924
            isPed = true
        elseif data.locType == "monitor" then
            hash = 389765485
            isBed = true
        end
        
        if hash then
            RequestModel(hash)
            local loops = 0
            while not HasModelLoaded(hash) and loops < 100 do
                Wait(10)
                loops = loops + 1
            end
        end
        
        while isScreenBlurred do
            Wait(0)
            local hit, endCoords, surfaceNormal = RaycastFromCamera(100.0)
            
            if hit then
                local drawCoords = endCoords
                
                if data.locType == "pc" then
                    local pCoords = GetEntityCoords(PlayerPedId())
                    local dirX = endCoords.x - pCoords.x
                    local dirY = endCoords.y - pCoords.y
                    local dist = math.sqrt(dirX * dirX + dirY * dirY)
                    
                    if dist > 0.001 then
                        drawCoords = vector3(
                            endCoords.x + (dirX / dist) * zOffset,
                            endCoords.y + (dirY / dist) * zOffset,
                            endCoords.z
                        )
                    end
                end
                
                if data.locType == "bed" then
                    DrawMarker(1, endCoords.x, endCoords.y, endCoords.z - 1.0, 0, 0, 0, 0, 0, 0, 2.4, 2.4, 2.0, 220, 240, 255, 120, false, false, 2, nil, nil, false)
                    DrawMarker(28, endCoords.x, endCoords.y, endCoords.z, 0, 0, 0, 0, 0, 0, 0.1, 0.1, 0.1, 255, 255, 255, 200, false, false, 2, nil, nil, false)
                end
                
                if not hash and data.locType ~= "pc" and data.locType ~= "bed" then
                    DrawMarker(28, endCoords.x, endCoords.y, endCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15, 0.15, 0.15, 0, 255, 204, 150, false, false, 2, nil, nil, false)
                end
                
                if data.locType == "pc" then
                    TriggerEvent("plt_xray:client:showPlacementPreview", drawCoords, heading, pitch)
                end
                
                if hash then
                    if not entity then
                        if isBed then
                            entity = CreateObject(hash, endCoords.x, endCoords.y, endCoords.z, false, false, false)
                        elseif isPed then
                            entity = CreatePed(4, hash, endCoords.x, endCoords.y, endCoords.z - 1.0, heading, false, false)
                            SetEntityAlpha(entity, 180, false)
                            SetEntityCollision(entity, false, false)
                            SetEntityInvincible(entity, true)
                            FreezeEntityPosition(entity, true)
                        else
                            entity = CreateVehicle(hash, endCoords.x, endCoords.y, endCoords.z, heading, false, false)
                            SetVehicleDoorsLocked(entity, 2)
                        end
                        
                        if not isPed then
                            SetEntityAlpha(entity, 180, false)
                            SetEntityCollision(entity, false, false)
                            SetEntityInvincible(entity, true)
                            FreezeEntityPosition(entity, true)
                        end
                    else
                        SetEntityCoords(entity, endCoords.x, endCoords.y, endCoords.z, false, false, false, false)
                        SetEntityHeading(entity, heading)
                    end
                end
                
                if isSpawn then
                    if IsControlPressed(0, 174) then
                        heading = heading + 2.0
                    elseif IsControlPressed(0, 175) then
                        heading = heading - 2.0
                    end
                end
                
                if data.locType == "pc" then
                    if IsControlPressed(0, 172) then
                        if IsControlPressed(0, 21) then
                            zOffset = math.min(3.0, zOffset + 0.01)
                        else
                            pitch = math.min(45.0, pitch + 0.5)
                        end
                    elseif IsControlPressed(0, 173) then
                        if IsControlPressed(0, 21) then
                            zOffset = math.max(-3.0, zOffset - 0.01)
                        else
                            pitch = math.max(-45.0, pitch - 0.5)
                        end
                    end
                end
                
                if IsControlJustPressed(0, 38) then
                    isScreenBlurred = false
                    if data.locType == "pc" then
                        TriggerEvent("plt_xray:client:hidePlacementPreview")
                    end
                    
                    SendNUIMessage({
                        action = "amb_placementDone",
                        nodeId = data.nodeId,
                        locType = data.locType,
                        pointIndex = data.pointIndex,
                        interactionType = data.interactionType,
                        coords = {
                            x = drawCoords.x,
                            y = drawCoords.y,
                            z = drawCoords.z,
                            h = heading or nil,
                            pitch = (data.locType == "pc" and pitch) and pitch or nil
                        }
                    })
                    
                    SendNUIMessage({ action = "amb_togglePlacementHelp", visible = false })
                    SetNuiFocus(true, true)
                    break
                end
            end
            
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) or IsControlJustPressed(0, 47) then
                isScreenBlurred = false
                if data.locType == "pc" then
                    TriggerEvent("plt_xray:client:hidePlacementPreview")
                end
                SendNUIMessage({ action = "amb_placementCancelled" })
                SendNUIMessage({ action = "amb_togglePlacementHelp", visible = false })
                SetNuiFocus(true, true)
                break
            end
        end
        
        if entity then
            if isBed then DeleteObject(entity)
            elseif isPed then DeleteEntity(entity)
            else DeleteVehicle(entity) end
        end
        if hash then SetModelAsNoLongerNeeded(hash) end
    end)
    cb("ok")
end)

function RotationToDirection(rot)
    local radRot = vector3(math.rad(rot.x), math.rad(rot.y), math.rad(rot.z))
    return vector3(-math.sin(radRot.z) * math.abs(math.cos(radRot.x)), math.cos(radRot.z) * math.abs(math.cos(radRot.x)), math.sin(radRot.x))
end

function RaycastFromCamera(distance)
    local rot = GetGameplayCamRot(2)
    local coord = GetGameplayCamCoord()
    local dir = RotationToDirection(rot)
    local dest = vector3(coord.x + (dir.x * distance), coord.y + (dir.y * distance), coord.z + (dir.z * distance))
    
    local handle = StartShapeTestRay(coord.x, coord.y, coord.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(handle)
    return hit, endCoords, entityHit
end

RegisterNUICallback("amb_localRefresh", function(data, cb)
    if data and data.nodes then
        RefreshBlipsAndZones(data)
    end
    cb("ok")
end)

RegisterNUICallback("amb_save", function(data, cb)
    TriggerServerEvent("amb_server:save", data)
    cb("ok")
end)

RegisterNUICallback("amb_close", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("amb_payEMSInvoice", function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent("amb_server:payEMSInvoice", data and data.invoiceId or data)
    cb("ok")
end)

RegisterNUICallback("amb_declineEMSInvoice", function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent("amb_server:declineEMSInvoice", data and data.invoiceId or data)
    cb("ok")
end)

RegisterNUICallback("amb_takeEMSItem", function(data, cb)
    TriggerServerEvent("amb_server:takeEMSInventoryItem", data)
    cb("ok")
end)

RegisterNUICallback("amb_spawnVehicle", function(data, cb)
    local model = data.model
    local spawnPoints = data.spawnPoints
    
    if not (model and spawnPoints and #spawnPoints ~= 0) then return cb("ok") end
    
    local freePoint = nil
    for _, point in ipairs(spawnPoints) do
        if point and point.x then
            if not IsAnyVehicleNearPoint(point.x, point.y, point.z, 3.0) then
                freePoint = point
                break
            end
        end
    end
    
    if not freePoint then
        Framework.Notify(_L("spawn_blocked"), "error")
        return cb("ok")
    end
    
    local hash = (type(model) == "string") and GetHashKey(model) or model
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
    
    local vehicle = CreateVehicle(hash, freePoint.x, freePoint.y, freePoint.z, freePoint.h or 0.0, true, true)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(netId, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehRadioStation(vehicle, "OFF")
    SetModelAsNoLongerNeeded(hash)
    
    SetVehicleNumberPlateText(vehicle, "EMS" .. tostring(math.random(100, 999)))
    
    if Entity(vehicle) and Entity(vehicle).state then
        Entity(vehicle).state:set("amb_department_vehicle", true, true)
        Entity(vehicle).state:set("amb_department_vehicle_model", tostring(model or ""), true)
    end
    
    Wait(100)
    GiveVehicleKeys(vehicle)
    Framework.Notify(_L("vehicle_spawned"), "success")
    cb("ok")
end)

CreateThread(function()
    local checkingStore = false
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local pCoords = GetEntityCoords(ped)
            local nearPoint = false
            
            for _, pointData in ipairs(unknownCache1) do
                local dist = #(pCoords - vector3(pointData.coords.x, pointData.coords.y, pointData.coords.z))
                if dist <= placementDistance then
                    local hasPerm = HasJobOrAdmin(pointData.job) or (Config.AdminBypass and IsAdmin)
                    if hasPerm then
                        nearPoint = true
                        if not checkingStore then
                            Framework.ShowTextUI(_L("store_vehicle_prompt"))
                            checkingStore = true
                        end
                        
                        if IsControlJustPressed(0, 38) then
                            local function ValidateModel()
                                if vehicle and vehicle ~= 0 and pointData then
                                    if type(pointData.allowedModels) ~= "table" or #pointData.allowedModels == 0 then return false end
                                    local vModelName = tostring(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) or ""):lower()
                                    
                                    for _, allowed in ipairs(pointData.allowedModels) do
                                        local cleanAllowed = tostring(allowed or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
                                        if cleanAllowed ~= "" then
                                            if vModelName ~= cleanAllowed then
                                                if GetHashKey(cleanAllowed) == GetEntityModel(vehicle) then return true end
                                            else
                                                return true
                                            end
                                        end
                                    end
                                end
                                return false
                            end
                            
                            if not ValidateModel() then
                                Framework.Notify("This vehicle is not registered in this department vehicle node.", "error")
                                break
                            end
                            
                            Framework.HideTextUI()
                            checkingStore = false
                            Framework.DeleteVehicle(vehicle)
                            Framework.Notify(_L("vehicle_stored"), "success")
                        end
                    end
                end
            end
            
            if not nearPoint and checkingStore then
                Framework.HideTextUI()
                checkingStore = false
            end
        else
            if checkingStore then
                Framework.HideTextUI()
                checkingStore = false
            end
        end
        Wait(1000)
    end
end)

local function OpenManageEMSDirect(data)
    if data and data.dept then
        DepartmentData = data.dept
        MemberData = data.members or {}
        RefreshBlipsAndZones(DepartmentData)
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "amb_open",
        data = DepartmentData
    })
end

RegisterNetEvent("amb_client:openManageEMSDirect", OpenManageEMSDirect)

RegisterCommand(Config.CommandName, function()
    TriggerServerEvent("amb_server:requestManageEMSDirect")
end)

CreateThread(function()
    local emsCfg = Config.EMSInvoice or {}
    TriggerEvent("chat:addSuggestion", "/" .. (emsCfg.CommandName or "emsinvoice"), "Send an EMS invoice to a nearby patient", {
        { name = "patientId", help = "Patient server ID" },
        { name = "amount", help = "Invoice amount" },
        { name = "reason", help = "Invoice reason" }
    })
    
    TriggerEvent("chat:addSuggestion", "/" .. (emsCfg.PayCommandName or "payemsinvoice"), "Pay a pending EMS invoice", {
        { name = "invoiceId", help = "Optional invoice ID" }
    })
    
    TriggerEvent("chat:addSuggestion", "/" .. (emsCfg.DeclineCommandName or "declineemsinvoice"), "Decline a pending EMS invoice", {
        { name = "invoiceId", help = "Optional invoice ID" }
    })
end)

RegisterNetEvent("amb_client:EMSInvoiceReceived", function(invoiceData)
    if type(invoiceData) ~= "table" then return end
    
    local emsCfg = Config.EMSInvoice or {}
    invoiceData.expireMinutes = emsCfg.ExpireMinutes or 10
    
    SendNUIMessage({
        action = "amb_openEMSInvoice",
        invoice = invoiceData
    })
    SetNuiFocus(true, true)
    
    TriggerEvent("chat:addMessage", {
        color = {46, 204, 113},
        multiline = true,
        args = {
            "EMS Invoice",
            string.format("#%s | $%s | %s. Pay: /%s %s | Decline: /%s %s",
                tostring(invoiceData.id or ""),
                tostring(invoiceData.amount or 0),
                tostring(invoiceData.reason or "Medical service"),
                (emsCfg.PayCommandName or "payemsinvoice"),
                tostring(invoiceData.id or ""),
                (emsCfg.DeclineCommandName or "declineemsinvoice"),
                tostring(invoiceData.id or "")
            )
        }
    })
end)

RegisterNetEvent("amb_client:LocalDoctorCheckIn", function(data, fallbackData)
    local argData = type(data) == "table" and data or (type(fallbackData) == "table" and fallbackData or nil)
    local nodeId = argData and argData.nodeId or nil
    
    if not nodeId then
        local pCoords = GetEntityCoords(PlayerPedId())
        local closestNode = nil
        local minDist = 999999.0
        
        for k, v in pairs(checkInZones) do
            if v.checkinCoords and v.checkinCoords.x then
                local dist = #(pCoords - vector3(v.checkinCoords.x, v.checkinCoords.y, v.checkinCoords.z))
                if dist < minDist then
                    minDist = dist
                    closestNode = k
                end
            end
        end
        nodeId = closestNode
    end
    
    if not nodeId or not checkInZones[nodeId] then return end
    
    local zoneData = checkInZones[nodeId]
    local minEMS = zoneData.minEMS or 1
    
    Framework.TriggerCallback("amb_server:getEMSOnDutyCount", function(count)
        if count >= minEMS then
            Framework.Notify(_L("local_doctor_busy", { count = count }), "info")
            return
        end
        
        local ped = PlayerPedId()
        if exports.plt_ambulance_job:GetInjuryType() == "fatal" then return end
        
        local freeBed = GetFreeBed(zoneData.beds, ped)
        if not freeBed then
            Framework.Notify(_L("no_checkin_bed"), "error")
            return
        end
        
        SetEntityCoords(ped, freeBed.x, freeBed.y, freeBed.z, false, false, false, false)
        SetEntityHeading(ped, freeBed.h or 0.0)
        FreezeEntityPosition(ped, true)
        
        Framework.RequestAnimDict(zoneData.lieAnim.dict)
        TaskPlayAnim(ped, zoneData.lieAnim.dict, zoneData.lieAnim.name, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        Framework.Notify(_L("local_doctor_treating"), "info")
        
        CreateThread(function()
            local startTime = GetGameTimer()
            while GetGameTimer() - startTime < zoneData.healTime do
                Wait(0)
                if IsControlJustPressed(0, 73) then
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
end)

local function GetStashName(typeStr, suffix)
    typeStr = tostring(typeStr or "ems"):gsub("%s+", "_"):lower()
    suffix = tostring(suffix or "default"):gsub("%s+", "_"):lower()
    return string.format("plt_amb_stash_%s_%s", typeStr, suffix)
end

local function GetSupportedInventory(invList)
    for _, resName in ipairs(invList or {}) do
        if GetResourceState(resName) == "started" then
            return resName
        end
    end
    return nil
end

local function OpenInventoryFallback(resourceName, events, args)
    if not resourceName then return false end
    for _, res in ipairs(events or {}) do
        for _, ev in ipairs(args or {}) do
            local success, result = pcall(function()
                return exports[resourceName][ev](table.unpack(res))
            end)
            if success and result ~= false then return true end
        end
    end
    return false
end

local function OpenStash(stashId, label, maxWeight, slots)
    local data = {
        label = label,
        maxweight = maxWeight,
        maxWeight = maxWeight,
        slots = slots
    }
    
    TriggerEvent("inventory:client:SetCurrentStash", stashId)
    TriggerEvent("qb-inventory:client:SetCurrentStash", stashId)
    
    TriggerServerEvent("inventory:server:OpenInventory", "stash", stashId, data)
    TriggerServerEvent("qb-inventory:server:OpenInventory", "stash", stashId, data)
    
    TriggerEvent("inventory:client:OpenInventory", "stash", stashId, data)
    TriggerEvent("qb-inventory:client:OpenInventory", "stash", stashId, data)
    TriggerEvent("qb-inventory:client:openInventory", "stash", stashId, data)
end

local function OpenDepartmentStash(typeStr, suffix, label)
    local stashId = GetStashName(typeStr, suffix)
    local stashLabel = label or (tostring(typeStr or "EMS") .. " Stash")
    local maxWeight = 400000
    local slots = 80
    
    local invType = tostring(Config.Inventory or ""):lower()
    
    if invType == "ox" then
        if GetResourceState("ox_inventory") == "started" then
            Framework.TriggerCallback("amb_server:prepareDepartmentStash", function(res)
                if not (res and res.ok) then
                    Framework.Notify("Unable to open stash right now.", "error")
                    return
                end
                exports.ox_inventory:openInventory("stash", res.stashId or stashId)
            end, { stashId = stashId, label = stashLabel, slots = slots, maxWeight = maxWeight })
            return
        end
    elseif invType == "qb" then
        Framework.TriggerCallback("amb_server:prepareDepartmentStash", function(res)
            if not (res and res.ok) then
                Framework.Notify("Unable to open stash right now.", "error")
                return
            end
            OpenStash(res.stashId or stashId, stashLabel, maxWeight, slots)
        end, { stashId = stashId, label = stashLabel, slots = slots, maxWeight = maxWeight })
        return
    elseif invType == "tgiann" then
        if OpenInventoryFallback(GetSupportedInventory({"tgiann-inventory", "tgiann_inventory"}), {{"stash", stashId, stashLabel}, {stashId, stashLabel}, {stashId, stashLabel, slots, maxWeight}}, {"OpenInventory", "openInventory", "OpenStash", "openStash"}) then return end
    elseif invType == "quasar" then
        if OpenInventoryFallback(GetSupportedInventory({"qs-inventory", "qs_inventory", "quasar-inventory", "quasar_inventory"}), {{"stash", stashId, stashLabel}, {stashId, stashLabel}, {stashId, stashLabel, slots, maxWeight}}, {"OpenInventory", "openInventory", "OpenStash", "openStash"}) then return end
    elseif invType == "origin" then
        if OpenInventoryFallback(GetSupportedInventory({"origin_inventory", "origin-inventory", "origen_inventory", "origen-inventory"}), {{"stash", stashId, stashLabel}, {stashId, stashLabel}, {stashId, stashLabel, slots, maxWeight}}, {"OpenInventory", "openInventory", "OpenStash", "openStash"}) then return end
    elseif invType == "core" then
        if OpenInventoryFallback(GetSupportedInventory({"core_inventory", "core-inventory"}), {{"stash", stashId, stashLabel}, {stashId, stashLabel}, {stashId, stashLabel, slots, maxWeight}}, {"OpenInventory", "openInventory", "OpenStash", "openStash"}) then return end
    end
    
    if GetResourceState("qb-inventory") == "started" then
        OpenStash(stashId, stashLabel, maxWeight, slots)
        return
    end
    
    Framework.Notify("Stash is not configured for this inventory.", "error")
end

RegisterNetEvent("amb_client:Interact", function(data)
    if not (data and data.locType) then return end
    
    local locType = data.locType
    local jobData = data.job
    local nodeId = data.nodeId
    local coords = data.coords
    
    local pData = Framework.GetPlayerData()
    if not pData then return end
    
    local hasJob = HasJobOrAdmin(jobData)
    
    if locType == "boss_menu" then
        if not hasJob then
            Framework.Notify(_L("not_your_department"), "error")
            return
        end
        if not HasPermissionForNode(nodeId, "boss_menu", DepartmentData) then
            Framework.Notify(_L("not_authorized"), "error")
            return
        end
        OpenBossMenu(jobData)
        
    elseif locType == "garage" or locType == "helipad" then
        if not hasJob then
            Framework.Notify(_L("no_garage_access"), "error")
            return
        end
        
        local typeToCheck = (locType == "helipad") and "helipad" or "vehicle"
        local linkedNode = GetLinkedNodeByType(nodeId, typeToCheck, DepartmentData)
        
        if not linkedNode then
            linkedNode = GetLinkedNodeByType(nodeId, (locType == "helipad") and "vehicle" or "helipad", DepartmentData)
        end
        
        local vehicles = linkedNode and linkedNode.vehicles or {}
        local spawnPoints = linkedNode and linkedNode.spawnPoints or { coords }
        
        local deptName = (linkedNode and linkedNode.label) and linkedNode.label or jobData:upper()
        deptName = deptName .. _L("garage_title_suffix")
        
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "amb_openGarage",
            deptName = deptName,
            department = jobData,
            vehicles = vehicles,
            spawnPoints = spawnPoints
        })
        
    elseif locType == "inventory" then
        if not hasJob then
            Framework.Notify(_L("no_inventory_access"), "error")
            return
        end
        Framework.TriggerCallback("amb_server:getEMSInventoryData", function(items)
            SendNUIMessage({
                action = "amb_openInventory",
                items = items
            })
            SetNuiFocus(true, true)
        end)
        
    elseif locType == "stash" then
        if not hasJob then
            Framework.Notify(_L("no_inventory_access"), "error")
            return
        end
        OpenDepartmentStash(jobData, nodeId, data.label)
        
    elseif locType == "wardrobe" then
        if not hasJob then
            Framework.Notify(_L("not_your_department"), "error")
            return
        end
        
        if data.wardrobeAction == "civilian" then
            RestoreCivilianClothes()
            Framework.Notify("Civilian clothes restored.", "success")
            return
        end
        
        if GetWardrobeForNode(nodeId) then
            Framework.Notify("EMS uniform equipped.", "success")
        else
            Framework.Notify("No EMS outfit configured for your rank.", "error")
        end
        
    elseif locType == "duty" then
        if not hasJob then
            Framework.Notify(_L("not_your_department"), "error")
            return
        end
        TriggerServerEvent("amb_server:ToggleDuty", jobData)
    end
end)

RegisterNetEvent("plt_xray:requestSync", function()
    if not (DepartmentData and DepartmentData.nodes) then return end
    
    for _, node in ipairs(DepartmentData.nodes) do
        if node.type == "xray" then
            local pc = node.coordsList and node.coordsList.pc or nil
            local bed = node.coordsList and node.coordsList.bed or nil
            
            if (pc and pc.x) or (bed and bed.x) then
                local screenNormal, screenUp = nil, nil
                if pc and pc.x then
                    screenNormal, screenUp = CalculateScreenVectors(pc)
                end
                
                TriggerEvent("plt_xray:client:updateConfigFromNode", {
                    Computer = pc and {
                        pos = vector3(pc.x, pc.y, pc.z),
                        heading = pc.h or 0.0,
                        screenNormal = screenNormal or GetDirectionFromHeading(pc.h or 0.0),
                        screenUp = screenUp or vector3(0.0, 0.0, 1.0),
                        width = 0.47,
                        height = 0.31
                    } or nil,
                    ScanBed = bed and {
                        pos = vector3(bed.x, bed.y, bed.z),
                        radius = 2.0
                    } or nil
                })
            end
        end
    end
end)

RegisterNetEvent("amb_client:SyncJobs", function(data)
    DepartmentData = data or { nodes = {}, links = {} }
    RefreshBlipsAndZones(DepartmentData)
end)

RegisterNetEvent("amb_client:RefreshCheckInZones", function()
    local currentId = GetNextPlacementId()
    if not (DepartmentData and DepartmentData.nodes) then return end
    
    if Config.Target == "ox_target" then
        for k, v in pairs(activeQbZones) do
            if type(v) == "number" then exports.ox_target:removeZone(v) end
        end
    elseif Config.Target == "qb-target" then
        for k, v in pairs(activeQbZones) do exports["qb-target"]:RemoveZone(k) end
    end
    
    activeQbZones = {}
    checkInCoordsCache = {}
    RemoveAllDoctorPeds()
    
    Framework.TriggerCallback("amb_server:getEMSOnDutyCount", function(count)
        if not IsCurrentPlacement(currentId) then return end
        
        for _, node in ipairs(DepartmentData.nodes) do
            if node.type == "check_in" then
                local beds = ParseCoordsList(node.coordsList)
                local checkin = (node.coordsList and node.coordsList.checkin) and node.coordsList.checkin or nil
                local minEMS = tonumber(node.minEMS) or 1
                
                if checkin and checkin.x and #beds > 0 then
                    local deptNode = GetLinkedNodeByType(node.id, "location", DepartmentData)
                    local locName = (deptNode and deptNode.label) and deptNode.label or (node.label or _L("hospital"))
                    SetupCheckInZone(node.id, checkin, beds, locName, count >= minEMS, minEMS, currentId)
                end
            end
        end
    end)
end)

RegisterNetEvent("amb_client:SyncMembers", function(data)
    MemberData = data or {}
    SendNUIMessage({
        action = "amb_syncMembers",
        members = data
    })
end)

local function InitDataSync()
    Framework.TriggerCallback("amb_server:getData", function(data)
        if data and data.dept then
            DepartmentData = data.dept
            MemberData = data.members or {}
            RefreshBlipsAndZones(DepartmentData)
            TriggerEvent("amb_client:PushLocaleToUI", Config.Locale)
        end
    end)
end

RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
    CheckPermissions()
    InitDataSync()
end)

RegisterNetEvent("esx:playerLoaded", function()
    CheckPermissions()
    InitDataSync()
end)

AddEventHandler("onResourceStart", function(resName)
    if GetCurrentResourceName() == resName then
        CreateThread(function()
            Wait(2000)
            CheckPermissions()
            InitDataSync()
        end)
        return
    end
    if resName == "plt_xray" then
        CreateThread(function()
            Wait(1000)
            if DepartmentData and DepartmentData.nodes then
                print("^2[plt_ambulance] plt_xray started; refreshing monitor panels.^7")
                RefreshBlipsAndZones(DepartmentData)
            end
        end)
    end
end)

RegisterNetEvent("QBCore:Client:OnJobUpdate", function(jobData)
    CheckPermissions()
    local oldDept = LocalPlayerJob.dept
    local oldGrade = LocalPlayerJob.grade
    
    local newDept = (jobData and jobData.name) and jobData.name or oldDept
    local newGrade = 0
    if jobData then
        if type(jobData.grade) == "table" then
            newGrade = jobData.grade.level or jobData.grade
        else
            newGrade = jobData.grade
        end
    end
    newGrade = tonumber(newGrade) or (oldGrade or 0)
    
    local newDuty = (jobData and jobData.onduty ~= nil) and jobData.onduty or LocalPlayerJob.onDuty
    
    LocalPlayerJob.dept = newDept
    LocalPlayerJob.grade = newGrade
    LocalPlayerJob.onDuty = newDuty
    
    if oldDept == newDept then
        local oldG = tonumber(oldGrade) or 0
        local newG = tonumber(newGrade) or 0
        if oldG == newG then return end
    end
    RefreshBlipsAndZones(DepartmentData)
end)

RegisterNetEvent("esx:setJob", function(jobData)
    CheckPermissions()
    RefreshBlipsAndZones(DepartmentData)
end)

CreateThread(function()
    Wait(1000)
    if Framework.GetPlayerData() then
        CheckPermissions()
        InitDataSync()
    end
end)
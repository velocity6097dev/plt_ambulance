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

-- FIX #1: Separate storage for blips and peds
local activeBlips = {}
local activePeds = {}
local activeDoctorPeds = {}

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
                    pcall(function() exports.ox_target:removeZone(v) end)
                end
            end
        elseif type(v) == "string" then
            if Config.Target == "qb-target" then
                pcall(function() exports["qb-target"]:RemoveZone(v) end)
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
                TriggerEvent("vehiclekeys:client:AddKeys", plate)
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
    local cleaned = nodeType:lower():gsub("[%
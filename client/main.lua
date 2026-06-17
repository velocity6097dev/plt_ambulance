-- ==========================================
-- Variables & Cache
-- ==========================================
local Blips = {}
local TargetZones = {}
local PharmacyZones = {}
local CheckinZones = {}
local SpawnedEntities = {}
local SpawnedMonitors = {}
local MonitorStates = {}
local CheckinLocations = {}
local VehicleSpawnPoints = {}

local IsLyingOnBed = false
local CurrentBedAnim = nil
local IsPlacementModeActive = false
local CurrentPlacementId = 0

DepartmentData = { nodes = {}, links = {} }
MemberData = {}
LocalPlayerJob = { dept = "none", grade = 0, onDuty = false }

local CivilianOutfitCache = nil

-- ==========================================
-- Utility Functions
-- ==========================================

function CleanupEntities()
    for _, entity in pairs(SpawnedEntities) do
        if type(entity) == "number" and DoesEntityExist(entity) then
            DeleteEntity(entity)
        elseif type(entity) == "string" and Config.Target == "qb-target" then
            exports["qb-target"]:RemoveZone(entity)
        elseif Config.Target == "ox_target" then
            exports.ox_target:removeZone(entity)
        end
    end
    SpawnedEntities = {}
end

function GetCleanLabel(str, defaultStr)
    if str and str ~= "" then
        local lower = str:lower()
        if not lower:find("new location") and not lower:find("new department") and not lower:find("new boss") 
           and not lower:find("new vehicle") and not lower:find("new armory") and not lower:find("new door")
           and not lower:find("new rank") and not lower:find("new permission") then
            return str
        end
    end
    if str:lower() == defaultStr:lower() then return defaultStr end
    return str
end

function GiveVehicleKeys(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    
    local plate = string.gsub(GetVehicleNumberPlateText(vehicle), "^%s*(.-)%s*$", "%1")
    if plate == "" then return end

    if GetResourceState("qb-vehiclekeys") == "started" then
        TriggerEvent("vehiclekeys:client:SetOwner", plate)
        TriggerEvent("qb-vehiclekeys:client:AddKeys", plate)
        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", plate)
    elseif GetResourceState("qbx_vehiclekeys") == "started" then
        exports.qbx_vehiclekeys:GiveKeys(plate)
    end
end

-- ==========================================
-- Wardrobe & Clothes
-- ==========================================

function SaveCivilianClothes()
    local ped = PlayerPedId()
    local identifier = "unknown"
    local playerData = Framework.GetPlayerData()
    
    if playerData then
        identifier = playerData.citizenid or playerData.identifier or playerData.license or GetPlayerServerId(PlayerId())
    end
    
    local kvpKey = string.format("plt_amb_civilian_clothes_%s", tostring(identifier))
    
    local outfit = { props = {} }
    for i = 0, 11 do
        outfit[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
            palette = GetPedPaletteVariation(ped, i)
        }
    end
    for i = 0, 7 do
        outfit.props[i] = {
            drawable = GetPedPropIndex(ped, i),
            texture = GetPedPropTextureIndex(ped, i)
        }
    end

    local encoded = json.encode(outfit)
    if kvpKey and encoded then
        pcall(function() SetResourceKvp(kvpKey, encoded) end)
    end
end

function RestoreCivilianClothes()
    local function TryClothingScript()
        if GetResourceState("qb-clothing") == "started" then TriggerEvent("qb-clothing:client:loadPlayerSkin"); return true end
        if GetResourceState("illenium-appearance") == "started" then TriggerEvent("illenium-appearance:client:reloadSkin"); return true end
        if GetResourceState("origen_clothing") == "started" then TriggerEvent("origen_clothing:client:reloadSkin"); return true end
        if GetResourceState("rclothing") == "started" then TriggerEvent("rclothing:client:reloadSkin"); return true end
        if GetResourceState("esx_skin") == "started" then 
            TriggerEvent("esx_skin:getPlayerSkin", function(skin) TriggerEvent("skinchanger:loadSkin", skin) end)
            return true 
        end
        return false
    end

    local ped = PlayerPedId()
    local identifier = "unknown"
    local playerData = Framework.GetPlayerData()
    if playerData then identifier = playerData.citizenid or playerData.identifier or playerData.license or GetPlayerServerId(PlayerId()) end
    local kvpKey = string.format("plt_amb_civilian_clothes_%s", tostring(identifier))

    local outfitData = CivilianOutfitCache
    if not outfitData then
        local savedData = nil
        pcall(function() savedData = GetResourceKvpString(kvpKey) end)
        if savedData and savedData ~= "" then
            local success, decoded = pcall(json.decode, savedData)
            if success and type(decoded) == "table" then outfitData = decoded end
        end
        
        CivilianOutfitCache = outfitData
        if not CivilianOutfitCache then
            TryClothingScript()
            return
        end
    end

    for i = 0, 11 do
        if CivilianOutfitCache[i] then
            SetPedComponentVariation(ped, i, CivilianOutfitCache[i].drawable, CivilianOutfitCache[i].texture, CivilianOutfitCache[i].palette)
        end
    end
    for i = 0, 7 do
        if CivilianOutfitCache.props[i] then
            local prop = CivilianOutfitCache.props[i]
            if prop.drawable == -1 then
                ClearPedProp(ped, i)
            else
                SetPedPropIndex(ped, i, prop.drawable, prop.texture, true)
            end
        end
    end

    CivilianOutfitCache = nil
    if kvpKey then pcall(function() DeleteResourceKvp(kvpKey) end) end
end

function EquipEMSOutfit(nodeId)
    if not DepartmentData or not DepartmentData.nodes then return false end

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

    local grade = (type(playerData.job.grade) == "table" and playerData.job.grade.level) or playerData.job.grade or 0
    local outfitKey = "rank_" .. tostring(grade)
    local outfitData = wardrobeNode.outfits[outfitKey]

    if type(outfitData) ~= "table" then return false end

    local ped = PlayerPedId()
    if not CivilianOutfitCache then SaveCivilianClothes() end

    local function ApplyComp(compId, data)
        if type(data) == "table" and tonumber(data.item) ~= nil then
            SetPedComponentVariation(ped, compId, tonumber(data.item), tonumber(data.texture) or 0, 0)
        end
    end

    ApplyComp(4, outfitData.pants)
    ApplyComp(11, outfitData.shirt)
    ApplyComp(9, outfitData.vest)
    ApplyComp(6, outfitData.shoes)

    if type(outfitData.hat) == "table" and outfitData.hat.item ~= nil then
        local propId = tonumber(outfitData.hat.item) or -1
        local propTex = tonumber(outfitData.hat.texture) or 0
        if propId < 0 then
            ClearPedProp(ped, 0)
        else
            SetPedPropIndex(ped, 0, propId, propTex, true)
        end
    end
    return true
end

-- ==========================================
-- Permissions & Validations
-- ==========================================

function GetDepartmentForNode(nodeId, dataSet)
    if not dataSet or not dataSet.nodes then return nil end
    local searchId = tostring(nodeId)
    
    for _, node in ipairs(dataSet.nodes) do
        if tostring(node.id) == searchId and node.type == "department" then
            return node.id
        end
    end

    local visited = { [searchId] = true }
    local queue = { searchId }

    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, link in ipairs(dataSet.links) do
            local nextNode = nil
            if tostring(link.to) == current then nextNode = tostring(link.from)
            elseif tostring(link.from) == current then nextNode = tostring(link.to) end

            if nextNode and not visited[nextNode] then
                for _, node in ipairs(dataSet.nodes) do
                    if tostring(node.id) == nextNode then
                        if node.type == "department" then return node.id end
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

function GetLinkedNodeByType(nodeId, targetType, dataSet)
    if not dataSet or not dataSet.nodes then return nil end
    
    local searchId = tostring(nodeId)
    local visited = { [searchId] = true }
    local queue = { searchId }

    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, link in ipairs(dataSet.links) do
            local nextNode = nil
            if tostring(link.to) == current then nextNode = tostring(link.from)
            elseif tostring(link.from) == current then nextNode = tostring(link.to) end

            if nextNode and not visited[nextNode] then
                for _, node in ipairs(dataSet.nodes) do
                    if tostring(node.id) == nextNode then
                        if node.type == targetType then return node end
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

function HasPermissionForNode(nodeId, permissionType, dataSet)
    if Config.AdminBypass and IsAdmin then return true end

    local deptId = GetDepartmentForNode(nodeId, dataSet)
    if not deptId then return true end

    local playerData = Framework.GetPlayerData()
    if not playerData then return false end

    local identifier = playerData.citizenid
    local jobName = (playerData.job and playerData.job.name) or "none"
    local grade = (type(playerData.job.grade) == "table" and playerData.job.grade.level) or playerData.job.grade or 0

    if MemberData[identifier] and tostring(MemberData[identifier].job) == tostring(deptId) then
        jobName = MemberData[identifier].job
        grade = tonumber(MemberData[identifier].grade)
    end

    if not exports.plt_ambulance_job:IsEMS() then return false end

    -- Boss Menu Special Check
    local rankNode = GetLinkedNodeByType(deptId, "rank", dataSet)
    if permissionType:lower() == "boss_menu" then
        if not rankNode then return false end
        if type(rankNode.ranks) == "table" then
            for _, r in ipairs(rankNode.ranks) do
                if tonumber(r.level) == grade and r.bossMenu == true then return true end
            end
        end
        return false
    end

    -- Normal Permission Check
    local permNode = GetLinkedNodeByType(deptId, "permission", dataSet)
    if not permNode then return true end

    local rankKey = "rank_" .. tostring(grade)
    if type(permNode.rankPerms) == "table" and type(permNode.rankPerms[rankKey]) == "table" then
        return CheckPermissionTable(permNode.rankPerms[rankKey], permissionType)
    end

    return true
end

function CheckPermissionTable(permsTable, permType)
    if type(permsTable) ~= "table" then return false end
    if permsTable[permType] == true then return true end
    return false
end

function IsEMS()
    local playerData = Framework.GetPlayerData()
    if not playerData then return false end
    if IsAdmin and Config.AdminBypass then return true end

    local jobName = (playerData.job and playerData.job.name) or "none"
    local identifier = playerData.citizenid
    local memberJob = (MemberData[identifier] and MemberData[identifier].job) or "none"

    for _, emsJob in ipairs(Config.Medical.EMSJobs) do
        if jobName == emsJob or memberJob == emsJob then return true end
    end

    -- Department Verification
    if DepartmentData and DepartmentData.nodes then
        for _, node in ipairs(DepartmentData.nodes) do
            if node.type == "department" then
                local fwJob = (node.frameworkJob and node.frameworkJob ~= "") and node.frameworkJob or node.id
                if tostring(jobName) == tostring(fwJob) or tostring(memberJob) == tostring(node.id) then
                    return true
                end
            end
        end
    end
    return false
end
exports("IsEMS", IsEMS)

-- ==========================================
-- System Interactions
-- ==========================================

RegisterNetEvent("amb_client:Interact", function(data)
    if not data or not data.locType then return end

    local locType = data.locType
    local job = data.job
    local nodeId = data.nodeId
    local coords = data.coords
    local playerData = Framework.GetPlayerData()
    
    if not playerData then return end

    local isAuthorized = IsEMS()

    if locType == "boss_menu" then
        if not isAuthorized then return Framework.Notify(_L("not_your_department"), "error") end
        if not HasPermissionForNode(nodeId, "boss_menu", DepartmentData) then return Framework.Notify(_L("not_authorized"), "error") end
        OpenBossMenu(job)

    elseif locType == "garage" or locType == "helipad" then
        if not isAuthorized then return Framework.Notify(_L("no_garage_access"), "error") end
        
        local searchType = (locType == "helipad") and "helipad" or "vehicle"
        local vehNode = GetLinkedNodeByType(nodeId, searchType, DepartmentData)
        if not vehNode then vehNode = GetLinkedNodeByType(nodeId, (locType == "helipad" and "vehicle" or "helipad"), DepartmentData) end

        local vehicles = (vehNode and vehNode.vehicles) or {}
        local spawnPoints = (vehNode and vehNode.spawnPoints) or {coords}

        local deptName = (vehNode and vehNode.label) or string.upper(job)
        deptName = deptName .. _L("garage_title_suffix")

        SendNUIMessage({
            action = "amb_openGarage",
            deptName = deptName,
            department = job,
            vehicles = vehicles,
            spawnPoints = spawnPoints
        })
        SetNuiFocus(true, true)

    elseif locType == "inventory" then
        if not isAuthorized then return Framework.Notify(_L("no_inventory_access"), "error") end
        Framework.TriggerCallback("amb_server:getEMSInventoryData", function(items)
            SendNUIMessage({ action = "amb_openInventory", items = items })
            SetNuiFocus(true, true)
        end)

    elseif locType == "stash" then
        if not isAuthorized then return Framework.Notify(_L("no_inventory_access"), "error") end
        OpenDepartmentStash(job, nodeId, data.label)

    elseif locType == "wardrobe" then
        if not isAuthorized then return Framework.Notify(_L("not_your_department"), "error") end
        if data.wardrobeAction == "civilian" then
            RestoreCivilianClothes()
            Framework.Notify("Civilian clothes restored.", "success")
        else
            if EquipEMSOutfit(nodeId) then
                Framework.Notify("EMS uniform equipped.", "success")
            else
                Framework.Notify("No EMS outfit configured for your rank.", "error")
            end
        end

    elseif locType == "duty" then
        if not isAuthorized then return Framework.Notify(_L("not_your_department"), "error") end
        TriggerServerEvent("amb_server:ToggleDuty", job)
    end
end)

-- ==========================================
-- Map & Prop Rendering
-- ==========================================

function RefreshBlipsAndZones(data)
    DepartmentData = data
    for _, blip in pairs(Blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    Blips = {}
    CleanupEntities()

    if not data or not data.nodes then return end

    for _, node in ipairs(data.nodes) do
        local deptId = GetDepartmentForNode(node.id, data)

        if node.type == "department" and node.coords then
            local blip = AddBlipForCoord(node.coords.x, node.coords.y, node.coords.z)
            SetBlipSprite(blip, node.blipId or 61)
            SetBlipColour(blip, node.blipColor or 1)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(GetCleanLabel(node.label, "Department"))
            EndTextCommandSetBlipName(blip)
            Blips[node.id] = blip
        end

        if node.type == "pharmacy" and node.coords and node.coords.x then
            local zoneName = "plt_pharmacy_dynamic_" .. node.id
            if Config.Target == "ox_target" then
                PharmacyZones[node.id] = exports.ox_target:addSphereZone({
                    coords = vec3(node.coords.x, node.coords.y, node.coords.z),
                    radius = 1.2,
                    options = {{
                        name = zoneName, icon = "fas fa-prescription-bottle-medical",
                        label = _L("pharmacy_terminal"),
                        onSelect = function() TriggerEvent("amb_client:openPharmacy", deptId) end,
                        distance = 2.0
                    }}
                })
            elseif Config.Target == "qb-target" then
                exports["qb-target"]:AddBoxZone(zoneName, vec3(node.coords.x, node.coords.y, node.coords.z), 1.2, 1.2, {
                    name = zoneName, heading = node.coords.h or 0.0,
                    minZ = node.coords.z - 1.0, maxZ = node.coords.z + 1.0
                }, {
                    options = {{
                        type = "client", icon = "fas fa-prescription-bottle-medical",
                        label = _L("pharmacy_terminal"),
                        action = function() TriggerEvent("amb_client:openPharmacy", {jobName = deptId}) end
                    }},
                    distance = 2.0
                })
                PharmacyZones[node.id] = true
            end
        end

        if node.type == "ceiling_monitor" and node.coordsList and node.coordsList.monitor then
            local monCoords = node.coordsList.monitor
            local hash = GetHashKey(`prop_monitor_01a`) -- Replaced raw hash 389765485
            RequestModel(hash)
            while not HasModelLoaded(hash) do Wait(10) end
            
            local prop = CreateObject(hash, monCoords.x, monCoords.y, monCoords.z, false, false, false)
            SetEntityHeading(prop, monCoords.h or 0.0)
            SetEntityCoords(prop, monCoords.x, monCoords.y, monCoords.z, false, false, false, true)
            SetEntityAsMissionEntity(prop, true, true)
            FreezeEntityPosition(prop, true)
            table.insert(SpawnedMonitors, prop)
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

-- ==========================================
-- Core Loading
-- ==========================================

RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
    IsEMS()
    TriggerServerEvent("amb_server:getData")
end)

RegisterNetEvent("esx:playerLoaded", function()
    IsEMS()
    TriggerServerEvent("amb_server:getData")
end)

RegisterNetEvent("QBCore:Client:OnJobUpdate", function(job)
    IsEMS()
    LocalPlayerJob.dept = job.name or "none"
    LocalPlayerJob.grade = (type(job.grade) == "table" and job.grade.level) or job.grade or 0
    LocalPlayerJob.onDuty = job.onduty == true
    RefreshBlipsAndZones(DepartmentData)
end)

RegisterNetEvent("esx:setJob", function(job)
    IsEMS()
    RefreshBlipsAndZones(DepartmentData)
end)

CreateThread(function()
    Wait(1000)
    if Framework.GetPlayerData() then
        IsEMS()
        TriggerServerEvent("amb_server:getData")
    end
end)
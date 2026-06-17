local IsDraggingBed = false
local CurrentBedEntity = nil

-- ==========================================
-- Utility Functions
-- ==========================================

local function FormatTargetOptions(options)
    local formatted = {}
    for _, opt in ipairs(options or {}) do
        local entry = {
            icon = opt.icon,
            label = opt.label,
        }
        
        -- Map execution based on target system
        entry.action = function(entity)
            if type(opt.onSelect) == "function" then
                opt.onSelect({ entity = entity })
            elseif type(opt.action) == "function" then
                opt.action(entity)
            end
        end
        
        -- Map interaction permission
        entry.canInteract = function(entity, distance, data)
            if type(opt.canInteract) == "function" then
                local success, result = pcall(opt.canInteract, entity, distance, data)
                return success and result == true
            end
            return true
        end
        
        table.insert(formatted, entry)
    end
    return formatted
end

function SpawnBed(coords, heading)
    local model = Config.FernocotModel or "fernocot"
    local hash = GetHashKey(model)
    
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    
    local timer = 0
    while not HasModelLoaded(hash) and timer < 200 do
        Wait(10)
        timer = timer + 1
    end
    
    if not HasModelLoaded(hash) then return nil end
    
    local zPos = coords.z
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
    if found then zPos = groundZ end
    
    local bed = CreateObject(hash, coords.x, coords.y, zPos, true, true, true)
    if not DoesEntityExist(bed) then return nil end
    
    SetEntityHeading(bed, heading)
    PlaceObjectOnGroundProperly(bed)
    FreezeEntityPosition(bed, true)
    SetModelAsNoLongerNeeded(hash)
    
    return bed
end

function ReleaseBed()
    if not IsDraggingBed or not CurrentBedEntity then return end
    
    local ped = PlayerPedId()
    DetachEntity(CurrentBedEntity, true, true)
    ClearPedTasks(ped)
    FreezeEntityPosition(CurrentBedEntity, true)
    
    IsDraggingBed = false
    CurrentBedEntity = nil
    Framework.Notify(_L("bed_released"), "success")
end

-- ==========================================
-- Medic Actions
-- ==========================================

function DiagnosePlayer(ped)
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    Framework.Notify(_L("checking_vitals"), "info")
    
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    Wait(3000)
    ClearPedTasks(PlayerPedId())
    
    Framework.Notify(_L("patient_vitals_result"), "warning")
end

function RevivePlayerAction(ped)
    local targetSrc = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    
    Framework.Notify(_L("performing_cpr"), "info")
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    
    local success = Framework.ProgressBar(_L("progress_revive_player"), 10000)
    ClearPedTasks(PlayerPedId())
    
    if success then
        TriggerServerEvent("amb_server:RevivePlayer", targetSrc)
        Framework.Notify(_L("player_revived"), "success")
    end
end

-- ==========================================
-- Wheelchair System
-- ==========================================

RegisterNetEvent("amb_client:useWheelchair", function(duration)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local spawnCoords = coords + (forward * 1.5)
    local heading = GetEntityHeading(ped)
    
    local hash = -1963629913 -- Usually `iak_wheelchair`
    Framework.RequestModel(hash)
    
    local wheelchair = CreateVehicle(hash, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, true)
    
    if DoesEntityExist(wheelchair) then
        SetEntityAsMissionEntity(wheelchair, true, true)
        SetVehicleHasBeenOwnedByPlayer(wheelchair, true)
        SetModelAsNoLongerNeeded(hash)
        
        Framework.GiveKeys(wheelchair)
        Framework.Notify("Wheelchair deployed.", "success")
        
        if exports.plt_ambulance_job:GetInjuryType() == "fatal" then
            TaskWarpPedIntoVehicle(ped, wheelchair, -1)
        end
        
        local minutes = tonumber(duration) or tonumber(Config.WheelchairDuration) or 10
        local ms = math.floor(minutes * 60000)
        
        print(string.format("[WHEELCHAIR] Deployed with duration: %d minutes (%d ms)", minutes, ms))
        
        SetTimeout(ms, function()
            if DoesEntityExist(wheelchair) then
                local occupant = GetPedInVehicleSeat(wheelchair, -1)
                if occupant ~= 0 then
                    TaskLeaveVehicle(occupant, wheelchair, 0)
                    Wait(2000)
                end
                
                SetEntityAsMissionEntity(wheelchair, true, true)
                DeleteVehicle(wheelchair)
                Framework.Notify("Your rented wheelchair has expired and was returned.", "info")
            end
        end)
    else
        Framework.Notify("Failed to deploy wheelchair.", "error")
    end
end)

-- ==========================================
-- Interaction & Target Initialization
-- ==========================================

CreateThread(function()
    local bedModel = Config.FernocotModel or "fernocot"
    local bedOptions = {}
    
    -- 1. Lie on Bed
    table.insert(bedOptions, {
        name = "ems_lie_bed",
        icon = "fas fa-bed",
        label = _L("bed_lie"),
        onSelect = function(data)
            local ped = PlayerPedId()
            local bedEntity = data.entity
            if CurrentBedEntity then return end
            
            local offset = Config.FernocotLieOffset or {x = 0.0, y = 0.0, z = 1.2}
            local heading = Config.FernocotLieHeading or 0.0
            local anim = Config.FernocotLieAnim or {dict = "amb@world_human_sunbathe@male@back@base", name = "base"}
            
            Framework.RequestAnimDict(anim.dict)
            AttachEntityToEntity(ped, bedEntity, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 180.0 + heading, false, false, false, false, 0, true)
            TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
            
            CurrentBedEntity = bedEntity
            
            -- Keep Animation Playing Loop
            CreateThread(function()
                while CurrentBedEntity and DoesEntityExist(CurrentBedEntity) do
                    Wait(500)
                    if CurrentBedEntity and DoesEntityExist(CurrentBedEntity) then
                        if not IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then
                            TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
                        end
                    end
                end
                if CurrentBedEntity and not DoesEntityExist(CurrentBedEntity) then
                    DetachEntity(ped, true, true)
                    ClearPedTasks(ped)
                    CurrentBedEntity = nil
                end
            end)
        end,
        canInteract = function(entity)
            return CurrentBedEntity == nil
        end
    })
    
    -- 2. Get off Bed
    table.insert(bedOptions, {
        name = "ems_get_off_bed",
        icon = "fas fa-person-walking",
        label = _L("bed_get_off"),
        onSelect = function(data)
            local ped = PlayerPedId()
            if CurrentBedEntity ~= data.entity then return end
            
            DetachEntity(ped, true, true)
            ClearPedTasks(ped)
            CurrentBedEntity = nil
            Framework.Notify(_L("got_off_bed"), "success")
        end,
        canInteract = function(entity)
            return CurrentBedEntity == entity
        end
    })
    
    -- 3. Drag Bed
    table.insert(bedOptions, {
        name = "ems_drag_bed",
        icon = "fas fa-hand-holding",
        label = _L("bed_drag"),
        onSelect = function(data)
            if IsDraggingBed then return end
            local ped = PlayerPedId()
            local bedEntity = data.entity
            
            local offset = Config.FernocotDragOffset or {x = 0.0, y = 1.3, z = -0.35}
            local rot = Config.FernocotDragRotation or {x = 0.0, y = 0.0, z = 180.0}
            
            FreezeEntityPosition(bedEntity, false)
            AttachEntityToEntity(bedEntity, ped, GetPedBoneIndex(ped, 0), offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, true, true, false, true, 2, true)
            
            Framework.RequestAnimDict("anim@heists@box_carry@")
            TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
            
            IsDraggingBed = true
            CurrentBedEntity = bedEntity
            Framework.Notify(_L("release_bed_prompt"), "info")
            
            -- Drag Loop
            CreateThread(function()
                while IsDraggingBed and DoesEntityExist(CurrentBedEntity) do
                    Wait(0)
                    DisableControlAction(0, 37, true) -- Select Weapon
                    DisableControlAction(0, 22, true) -- Jump
                    DisableControlAction(0, 44, true) -- Cover
                    DisableControlAction(0, 24, true) -- Attack
                    DisableControlAction(0, 25, true) -- Aim
                    
                    if not IsEntityPlayingAnim(ped, "anim@heists@box_carry@", "idle", 3) then
                        TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
                    end
                    
                    if IsPedDeadOrDying(ped) or IsPedRagdoll(ped) or IsControlJustPressed(0, 38) then
                        ReleaseBed()
                        break
                    end
                end
            end)
        end,
        canInteract = function(entity)
            return not IsDraggingBed
        end
    })
    
    -- 4. Delete Bed
    table.insert(bedOptions, {
        name = "ems_delete_bed",
        icon = "fas fa-trash",
        label = _L("bed_remove"),
        onSelect = function(data)
            SetEntityAsMissionEntity(data.entity, true, true)
            DeleteEntity(data.entity)
            Framework.Notify(_L("bed_removed"), "success")
        end,
        canInteract = function()
            return exports.plt_ambulance_job:IsEMS() and not IsDraggingBed
        end
    })
    
    -- Register Bed Model Targets
    if Config.Target == "ox_target" then
        exports.ox_target:addModel(bedModel, bedOptions)
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddTargetModel(bedModel, {
            options = FormatTargetOptions(bedOptions),
            distance = 2.5
        })
    end
    
    -- Register Global Player Diagnostics
    local playerOptions = {{
        name = "ems_diagnose",
        icon = "fas fa-stethoscope",
        label = _L("diagnose_injuries"),
        onSelect = function(data)
            StartDiagnosis(data.entity)
        end,
        canInteract = function()
            return exports.plt_ambulance_job:IsEMS()
        end
    }}
    
    if Config.Target == "ox_target" then
        exports.ox_target:addGlobalPlayer(playerOptions)
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddGlobalPlayer({
            options = FormatTargetOptions(playerOptions),
            distance = 2.0
        })
    end
    
    -- Register Ambulance Vehicle Targets
    local validVehicles = Config.FernocotVehicleModels or {"ambulance", "firetruk", "ambulance2"}
    local vehHashes = {}
    for _, model in ipairs(validVehicles) do
        vehHashes[GetHashKey(model)] = true
    end
    
    local function IsValidAmbulance(entity)
        if type(entity) ~= "number" or entity <= 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
        if Entity(entity) and Entity(entity).state and Entity(entity).state.amb_department_vehicle == true then return true end
        local hash = GetEntityModel(entity)
        return vehHashes[hash] == true
    end

    local vehicleOptions = {}
    
    -- Take out bed
    table.insert(vehicleOptions, {
        name = "ems_take_bed",
        icon = "fas fa-bed",
        label = _L("bed_take_out"),
        distance = 4.0,
        onSelect = function(data)
            local veh = data.entity
            if not DoesEntityExist(veh) then return end
            
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleHasBeenOwnedByPlayer(veh, true)
            
            local offsetCoords = GetOffsetFromEntityInWorldCoords(veh, 0.0, -4.0, 0.0)
            local heading = GetEntityHeading(veh)
            
            CreateThread(function()
                Wait(150)
                local bed = SpawnBed(offsetCoords, heading)
                if not bed then
                    Framework.Notify(_L("bed_takeout_failed"), "error")
                    return
                end
                
                local ped = PlayerPedId()
                local dragOffset = Config.FernocotDragOffset or {x = 0.0, y = 1.3, z = -0.35}
                local dragRot = Config.FernocotDragRotation or {x = 0.0, y = 0.0, z = 180.0}
                
                FreezeEntityPosition(bed, false)
                AttachEntityToEntity(bed, ped, GetPedBoneIndex(ped, 0), dragOffset.x, dragOffset.y, dragOffset.z, dragRot.x, dragRot.y, dragRot.z, true, true, false, true, 2, true)
                
                Framework.RequestAnimDict("anim@heists@box_carry@")
                TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
                
                IsDraggingBed = true
                CurrentBedEntity = bed
                Framework.Notify(_L("release_bed_prompt"), "success")
                
                CreateThread(function()
                    while IsDraggingBed and DoesEntityExist(CurrentBedEntity) do
                        Wait(0)
                        DisableControlAction(0, 37, true)
                        DisableControlAction(0, 22, true)
                        DisableControlAction(0, 44, true)
                        DisableControlAction(0, 24, true)
                        DisableControlAction(0, 25, true)
                        
                        if not IsEntityPlayingAnim(ped, "anim@heists@box_carry@", "idle", 3) then
                            TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
                        end
                        
                        if IsPedDeadOrDying(ped) or IsPedRagdoll(ped) or IsControlJustPressed(0, 38) then
                            ReleaseBed()
                            break
                        end
                    end
                end)
            end)
        end,
        canInteract = function(entity)
            return IsValidAmbulance(entity) and exports.plt_ambulance_job:IsEMS() and not IsDraggingBed
        end
    })
    
    -- Put bed back
    table.insert(vehicleOptions, {
        name = "ems_put_bed",
        icon = "fas fa-box",
        label = _L("bed_put_back_in"),
        distance = 4.0,
        onSelect = function(data)
            local veh = data.entity
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local hash = GetHashKey(Config.FernocotModel or "fernocot")
            local targetBed = nil
            
            if IsDraggingBed and CurrentBedEntity then
                targetBed = CurrentBedEntity
                IsDraggingBed = false
                CurrentBedEntity = nil
                DetachEntity(targetBed, true, true)
            else
                local foundBed = GetClosestObjectOfType(coords.x, coords.y, coords.z, 4.0, hash, false, false, false)
                if foundBed ~= 0 then targetBed = foundBed end
            end
            
            if targetBed and DoesEntityExist(targetBed) then
                SetEntityAsMissionEntity(targetBed, true, true)
                DeleteEntity(targetBed)
                ClearPedTasksImmediately(ped)
                Framework.Notify(_L("bed_put_back"), "success")
                
                CreateThread(function()
                    Wait(100)
                    ClearPedTasksImmediately(PlayerPedId())
                end)
            else
                Framework.Notify(_L("no_bed_nearby"), "error")
            end
        end,
        canInteract = function(entity)
            if not IsValidAmbulance(entity) or not exports.plt_ambulance_job:IsEMS() then return false end
            
            local coords = GetEntityCoords(PlayerPedId())
            local hash = GetHashKey(Config.FernocotModel or "fernocot")
            
            if not IsDraggingBed then
                local bed = GetClosestObjectOfType(coords.x, coords.y, coords.z, 4.0, hash, false, false, false)
                return bed ~= 0
            end
            return true
        end
    })
    
    if Config.Target == "ox_target" then
        exports.ox_target:addGlobalVehicle(vehicleOptions)
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddGlobalVehicle({
            options = FormatTargetOptions(vehicleOptions),
            distance = 4.0
        })
    end
end)
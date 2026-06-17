local isBusy = false
local isDraggingBed = false
local currentBed = nil

local function MapTargetOptions(options)
    local mappedOptions = {}
    for _, opt in ipairs(options or {}) do
        local newOpt = {
            icon = opt.icon,
            label = opt.label
        }
        
        newOpt.action = function(entity)
            if type(opt.onSelect) == "function" then
                opt.onSelect({ entity = entity })
            elseif type(opt.action) == "function" then
                opt.action(entity)
            end
        end
        
        newOpt.canInteract = function(entity, distance, data)
            if type(opt.canInteract) == "function" then
                local success, result = pcall(opt.canInteract, entity, distance, data)
                return success and result == true
            end
            return true
        end
        
        table.insert(mappedOptions, newOpt)
    end
    return mappedOptions
end

local function SpawnBed(coords, heading)
    local modelName = Config.FernocotModel or "fernocot"
    local modelHash = GetHashKey(modelName)
    
    if not IsModelValid(modelHash) then
        return nil
    end
    
    RequestModel(modelHash)
    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 200 do
        Wait(10)
        attempts = attempts + 1
    end
    
    if not HasModelLoaded(modelHash) then
        return nil
    end
    
    local zCoord = coords.z
    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
    if foundGround then
        zCoord = groundZ
    end
    
    local bedObj = CreateObject(modelHash, coords.x, coords.y, zCoord, true, true, true)
    if not DoesEntityExist(bedObj) then
        return nil
    end
    
    SetEntityHeading(bedObj, heading)
    PlaceObjectOnGroundProperly(bedObj)
    FreezeEntityPosition(bedObj, true)
    SetModelAsNoLongerNeeded(modelHash)
    
    return bedObj
end

function ReleaseBed()
    if not isDraggingBed then return end
    if not currentBed then return end
    
    local ped = PlayerPedId()
    DetachEntity(currentBed, true, true)
    ClearPedTasks(ped)
    FreezeEntityPosition(currentBed, true)
    
    isDraggingBed = false
    currentBed = nil
    
    Framework.Notify(_L("bed_released"), "success")
end

CreateThread(function()
    local bedModelName = Config.FernocotModel or "fernocot"
    local bedOptions = {}
    
    -- Option 1: Lie on Bed
    local lieOpt = {
        name = "ems_lie_bed",
        icon = "fas fa-bed",
        label = _L("bed_lie"),
        onSelect = function(data)
            local ped = PlayerPedId()
            local entity = data.entity
            if currentBed then return end
            
            local offset = Config.FernocotLieOffset or { x = 0.0, y = 0.0, z = 1.2 }
            local headingOffset = Config.FernocotLieHeading or 0.0
            local anim = Config.FernocotLieAnim or { dict = "amb@world_human_sunbathe@male@back@base", name = "base" }
            
            Framework.RequestAnimDict(anim.dict)
            AttachEntityToEntity(ped, entity, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 180.0 + headingOffset, false, false, false, false, 0, true)
            TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
            
            currentBed = entity
            
            CreateThread(function()
                while currentBed do
                    if not DoesEntityExist(currentBed) then break end
                    Wait(500)
                    if currentBed and DoesEntityExist(currentBed) then
                        if not IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then
                            TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
                        end
                    end
                end
                
                if currentBed and not DoesEntityExist(currentBed) then
                    DetachEntity(ped, true, true)
                    ClearPedTasks(ped)
                    currentBed = nil
                end
            end)
        end,
        canInteract = function(entity, distance, data)
            return currentBed == nil
        end
    }
    
    -- Option 2: Get Off Bed
    local getOffOpt = {
        name = "ems_get_off_bed",
        icon = "fas fa-person-walking",
        label = _L("bed_get_off"),
        onSelect = function(data)
            local ped = PlayerPedId()
            if currentBed ~= data.entity then return end
            
            DetachEntity(ped, true, true)
            ClearPedTasks(ped)
            currentBed = nil
            Framework.Notify(_L("got_off_bed"), "success")
        end,
        canInteract = function(entity, distance, data)
            return currentBed == entity
        end
    }
    
    -- Option 3: Drag Bed
    local dragOpt = {
        name = "ems_drag_bed",
        icon = "fas fa-hand-holding",
        label = _L("bed_drag"),
        onSelect = function(data)
            if isDraggingBed then return end
            
            local ped = PlayerPedId()
            local entity = data.entity
            local offset = Config.FernocotDragOffset or { x = 0.0, y = 1.3, z = -0.35 }
            local rot = Config.FernocotDragRotation or { x = 0.0, y = 0.0, z = 180.0 }
            
            FreezeEntityPosition(entity, false)
            AttachEntityToEntity(entity, ped, GetPedBoneIndex(ped, 0), offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, true, true, false, true, 2, true)
            Framework.RequestAnimDict("anim@heists@box_carry@")
            TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
            
            isDraggingBed = true
            currentBed = entity
            Framework.Notify(_L("release_bed_prompt"), "info")
            
            CreateThread(function()
                while isDraggingBed do
                    if not DoesEntityExist(currentBed) then break end
                    Wait(0)
                    
                    DisableControlAction(0, 37, true)
                    DisableControlAction(0, 22, true)
                    DisableControlAction(0, 44, true)
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 25, true)
                    
                    if not IsEntityPlayingAnim(ped, "anim@heists@box_carry@", "idle", 3) then
                        TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
                    end
                    
                    if IsPedDeadOrDying(ped) or IsPedRagdoll(ped) then
                        ReleaseBed()
                        break
                    end
                    
                    if IsControlJustPressed(0, 38) then
                        ReleaseBed()
                        break
                    end
                end
            end)
        end,
        canInteract = function(entity, distance, data)
            return not isDraggingBed
        end
    }
    
    -- Option 4: Delete Bed
    local deleteOpt = {
        name = "ems_delete_bed",
        icon = "fas fa-trash",
        label = _L("bed_remove"),
        onSelect = function(data)
            SetEntityAsMissionEntity(data.entity, true, true)
            DeleteEntity(data.entity)
            Framework.Notify(_L("bed_removed"), "success")
        end,
        canInteract = function(entity, distance, data)
            if exports.plt_ambulance_job:IsEMS() then
                return not isDraggingBed
            end
            return false
        end
    }
    
    bedOptions[1] = lieOpt
    bedOptions[2] = getOffOpt
    bedOptions[3] = dragOpt
    bedOptions[4] = deleteOpt
    
    if Config.Target == "ox_target" then
        exports.ox_target:addModel(bedModelName, bedOptions)
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddTargetModel(bedModelName, {
            options = MapTargetOptions(bedOptions),
            distance = 2.5
        })
    end
    
    -- Global Player Options
    local playerOptions = {}
    local diagnoseOpt = {
        name = "ems_diagnose",
        icon = "fas fa-stethoscope",
        label = _L("diagnose_injuries"),
        onSelect = function(data)
            StartDiagnosis(data.entity)
        end,
        canInteract = function(entity, distance, data)
            return exports.plt_ambulance_job:IsEMS()
        end
    }
    playerOptions[1] = diagnoseOpt
    
    if Config.Target == "ox_target" then
        exports.ox_target:addGlobalPlayer(playerOptions)
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddGlobalPlayer({
            options = MapTargetOptions(playerOptions),
            distance = 2.0
        })
    end
    
    -- Global Vehicle Options
    local vehModels = Config.FernocotVehicleModels or { "ambulance", "firetruk", "ambulance2" }
    local validVehicles = {}
    for _, model in ipairs(vehModels) do
        validVehicles[GetHashKey(model)] = true
    end
    
    local function IsValidAmbulance(entity)
        if type(entity) ~= "number" or entity <= 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
            return false
        end
        
        if Entity(entity) and Entity(entity).state then
            if Entity(entity).state.amb_department_vehicle == true then
                return true
            end
        end
        
        local success, modelHash = pcall(GetEntityModel, entity)
        if not success or modelHash == 0 then
            return false
        end
        
        return validVehicles[modelHash] == true
    end
    
    local vehOptions = {}
    
    local takeBedOpt = {
        name = "ems_take_bed",
        icon = "fas fa-bed",
        label = _L("bed_take_out"),
        distance = 4.0,
        onSelect = function(data)
            local veh = data.entity
            if not DoesEntityExist(veh) then return end
            
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleHasBeenOwnedByPlayer(veh, true)
            
            local coords = GetOffsetFromEntityInWorldCoords(veh, 0.0, -4.0, 0.0)
            local heading = GetEntityHeading(veh)
            
            CreateThread(function()
                Wait(150)
                local bedObj = SpawnBed(coords, heading)
                if not bedObj then
                    Framework.Notify(_L("bed_takeout_failed"), "error")
                    return
                end
                
                local ped = PlayerPedId()
                local offset = Config.FernocotDragOffset or { x = 0.0, y = 1.3, z = -0.35 }
                local rot = Config.FernocotDragRotation or { x = 0.0, y = 0.0, z = 180.0 }
                
                FreezeEntityPosition(bedObj, false)
                AttachEntityToEntity(bedObj, ped, GetPedBoneIndex(ped, 0), offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, true, true, false, true, 2, true)
                Framework.RequestAnimDict("anim@heists@box_carry@")
                TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
                
                isDraggingBed = true
                currentBed = bedObj
                Framework.Notify(_L("release_bed_prompt"), "success")
                
                CreateThread(function()
                    while isDraggingBed do
                        if not DoesEntityExist(currentBed) then break end
                        Wait(0)
                        
                        DisableControlAction(0, 37, true)
                        DisableControlAction(0, 22, true)
                        DisableControlAction(0, 44, true)
                        DisableControlAction(0, 24, true)
                        DisableControlAction(0, 25, true)
                        
                        if not IsEntityPlayingAnim(ped, "anim@heists@box_carry@", "idle", 3) then
                            TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)
                        end
                        
                        if IsPedDeadOrDying(ped) or IsPedRagdoll(ped) then
                            ReleaseBed()
                            break
                        end
                        
                        if IsControlJustPressed(0, 38) then
                            ReleaseBed()
                            break
                        end
                    end
                end)
            end)
        end,
        canInteract = function(entity, distance, data)
            if IsValidAmbulance(entity) then
                if exports.plt_ambulance_job:IsEMS() then
                    return not isDraggingBed
                end
            end
            return false
        end
    }
    
    local putBedOpt = {
        name = "ems_put_bed",
        icon = "fas fa-box",
        label = _L("bed_put_back_in"),
        distance = 4.0,
        onSelect = function(data)
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local bedModelHash = GetHashKey(Config.FernocotModel or "fernocot")
            local bedObj = nil
            
            if isDraggingBed and currentBed then
                bedObj = currentBed
                isDraggingBed = false
                currentBed = nil
                DetachEntity(bedObj, true, true)
            else
                bedObj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 4.0, bedModelHash, false, false, false)
            end
            
            if bedObj and DoesEntityExist(bedObj) then
                SetEntityAsMissionEntity(bedObj, true, true)
                DeleteEntity(bedObj)
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
        canInteract = function(entity, distance, data)
            if IsValidAmbulance(entity) and exports.plt_ambulance_job:IsEMS() then
                if isDraggingBed then return true end
                
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local bedModelHash = GetHashKey(Config.FernocotModel or "fernocot")
                local bedObj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 4.0, bedModelHash, false, false, false)
                
                return bedObj ~= 0
            end
            return false
        end
    }
    
    vehOptions[1] = takeBedOpt
    vehOptions[2] = putBedOpt
    
    if Config.Target == "ox_target" then
        exports.ox_target:addGlobalVehicle(vehOptions)
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddGlobalVehicle({
            options = MapTargetOptions(vehOptions),
            distance = 4.0
        })
    end
end)

function DiagnosePlayer(ped)
    local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    Framework.Notify(_L("checking_vitals"), "info")
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    Wait(3000)
    ClearPedTasks(PlayerPedId())
    Framework.Notify(_L("patient_vitals_result"), "warning")
end

function RevivePlayerAction(ped)
    local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    isBusy = true
    Framework.Notify(_L("performing_cpr"), "info")
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
    
    if Framework.ProgressBar(_L("progress_revive_player"), 10000) then
        ClearPedTasks(PlayerPedId())
        TriggerServerEvent("amb_server:RevivePlayer", serverId)
        Framework.Notify(_L("player_revived"), "success")
    else
        ClearPedTasks(PlayerPedId())
    end
    
    isBusy = false
end

RegisterNetEvent("amb_client:useWheelchair", function(duration)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local spawnCoords = coords + (forward * 1.5)
    local heading = GetEntityHeading(ped)
    local modelHash = -1963629913
    
    Framework.RequestModel(modelHash)
    local vehicle = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, true)
    
    if DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleHasBeenOwnedByPlayer(vehicle, true)
        SetModelAsNoLongerNeeded(modelHash)
        Framework.GiveKeys(vehicle)
        Framework.Notify("Wheelchair deployed.", "success")
        
        if exports.plt_ambulance_job:GetInjuryType() == "fatal" then
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
        end
        
        duration = tonumber(duration)
        if not duration then
            duration = tonumber(Config.WheelchairDuration) or 10
        end
        
        local durationMs = math.floor(duration * 60000)
        print(string.format("[WHEELCHAIR] Deployed with duration: %d minutes (%d ms)", duration, durationMs))
        
        SetTimeout(durationMs, function()
            if DoesEntityExist(vehicle) then
                local occupant = GetPedInVehicleSeat(vehicle, -1)
                if occupant ~= 0 then
                    TaskLeaveVehicle(occupant, vehicle, 0)
                    Wait(2000)
                end
                SetEntityAsMissionEntity(vehicle, true, true)
                DeleteVehicle(vehicle)
                Framework.Notify("Your rented wheelchair has expired and was returned.", "info")
            end
        end)
    else
        Framework.Notify("Failed to deploy wheelchair.", "error")
    end
end)
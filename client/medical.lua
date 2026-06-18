-- ============================================================
-- Medical / EMS - Client Script
-- De-obfuscated / cleaned up from compiled Lua
-- ============================================================

local isPerformingCpr  = false  -- true while CPR/revive is in progress (set in RevivePlayerAction)
local isDraggingBed    = false  -- true while a fernocot (stretcher/bed) is being dragged
local draggedBedEntity = nil    -- the fernocot entity currently attached/dragged
local bedPlayerIsLyingOn = nil  -- the fernocot entity the player is currently lying on

-- Default offsets used when Config doesn't override them
local DEFAULT_DRAG_OFFSET   = vector3(0.0, 1.3, -0.35)
local DEFAULT_DRAG_ROTATION = vector3(0.0, 0.0, 0.0)
local DEFAULT_LIE_OFFSET    = vector3(0.0, 0.0, 1.2)
local DEFAULT_LIE_HEADING   = 0.0

-- ------------------------------------------------------------
-- Helper: build a target-system option list from a generic
-- list of {icon, label, onSelect, action, canInteract} tables.
-- Normalizes onSelect/action/canInteract into the shape the
-- target resource (ox_target / qb-target) expects.
-- ------------------------------------------------------------
local function BuildTargetOptions(optionDefs)
  local options = {}

  for _, def in ipairs(optionDefs or {}) do
    local index = #options + 1
    local option = {}

    option.icon = def.icon
    option.label = def.label

    option.action = function(entity)
      if type(def.onSelect) == "function" then
        def.onSelect({ entity = entity })
      elseif type(def.action) == "function" then
        def.action(entity)
      end
    end

    option.canInteract = function(entity, distance, coords)
      if type(def.canInteract) == "function" then
        local ok, result = pcall(def.canInteract, entity, distance, coords)
        return ok and result == true
      end
      return true
    end

    options[index] = option
  end

  return options
end

-- ------------------------------------------------------------
-- Spawn a fernocot (stretcher/bed) prop at the given coords
-- ------------------------------------------------------------
local function SpawnFernocot(coords, heading)
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

  local groundZ = coords.z
  local foundGround, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
  if foundGround then
    groundZ = z
  end

  local bed = CreateObject(modelHash, coords.x, coords.y, groundZ, true, true, true)

  if not DoesEntityExist(bed) then
    return nil
  end

  SetEntityHeading(bed, heading)
  PlaceObjectOnGroundProperly(bed)
  FreezeEntityPosition(bed, true)
  SetModelAsNoLongerNeeded(modelHash)

  return bed
end

-- ------------------------------------------------------------
-- Release a bed the player is currently lying on
-- ------------------------------------------------------------
function ReleaseBed()
  if not (isDraggingBed and draggedBedEntity) then
    return
  end

  local ped = PlayerPedId()

  DetachEntity(draggedBedEntity, true, true)
  ClearPedTasks(ped)
  FreezeEntityPosition(draggedBedEntity, true)

  isDraggingBed = false
  draggedBedEntity = nil

  Framework.Notify(_L("bed_released"), "success")
end

-- ------------------------------------------------------------
-- Target options for an already-placed fernocot: lie on it,
-- get off it, drag it, or delete it (EMS only for some).
-- ------------------------------------------------------------
CreateThread(function()
  local modelName = Config.FernocotModel or "fernocot"

  local optionDefs = {}

  -- Lie on the bed
  local lieOption = {}
  lieOption.name = "ems_lie_bed"
  lieOption.icon = "fas fa-bed"
  lieOption.label = _L("bed_lie")
  lieOption.onSelect = function(data)
    local ped = PlayerPedId()
    local entity = data.entity

    if bedPlayerIsLyingOn then
      return
    end

    local lieOffset = Config.FernocotLieOffset or DEFAULT_LIE_OFFSET
    local lieHeading = Config.FernocotLieHeading or DEFAULT_LIE_HEADING
    local lieAnim = Config.FernocotLieAnim or { dict = "amb@world_human_sunbathe@male@back@base", name = "base" }

    Framework.RequestAnimDict(lieAnim.dict)

    AttachEntityToEntity(
      ped, entity, 0,
      lieOffset.x, lieOffset.y, lieOffset.z,
      0.0, 0.0, 180.0 + lieHeading,
      false, false, false, false, 0, true
    )

    TaskPlayAnim(ped, lieAnim.dict, lieAnim.name, 8.0, -8.0, -1, 1, 0, false, false, false)

    bedPlayerIsLyingOn = entity

    -- Keep re-applying the anim in case it gets interrupted, until the
    -- bed is gone or the player gets up/dies/ragdolls.
    CreateThread(function()
      while bedPlayerIsLyingOn and DoesEntityExist(bedPlayerIsLyingOn) do
        Wait(500)

        if bedPlayerIsLyingOn and DoesEntityExist(bedPlayerIsLyingOn) then
          if not IsEntityPlayingAnim(ped, lieAnim.dict, lieAnim.name, 3) then
            TaskPlayAnim(ped, lieAnim.dict, lieAnim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
          end
        end
      end

      -- Bed despawned while the player was still lying on it
      if bedPlayerIsLyingOn and not DoesEntityExist(bedPlayerIsLyingOn) then
        DetachEntity(ped, true, true)
        ClearPedTasks(ped)
        bedPlayerIsLyingOn = nil
      end
    end)
  end

  -- Get off the bed
  local getOffOption = {}
  getOffOption.name = "ems_get_off_bed"
  getOffOption.icon = "fas fa-person-walking"
  getOffOption.label = _L("bed_get_off")
  getOffOption.onSelect = function(data)
    local ped = PlayerPedId()
    local entity = data.entity

    if bedPlayerIsLyingOn ~= entity then
      return
    end

    DetachEntity(ped, true, true)
    ClearPedTasks(ped)
    bedPlayerIsLyingOn = nil

    Framework.Notify(_L("got_off_bed"), "success")
  end
  getOffOption.canInteract = function(entity)
    return bedPlayerIsLyingOn == entity
  end

  -- Drag the bed around
  local dragOption = {}
  dragOption.name = "ems_drag_bed"
  dragOption.icon = "fas fa-hand-holding"
  dragOption.label = _L("bed_drag")
  dragOption.onSelect = function(data)
    if isDraggingBed then
      return
    end

    local ped = PlayerPedId()
    local entity = data.entity

    local dragOffset = Config.FernocotDragOffset or DEFAULT_DRAG_OFFSET
    local dragRotation = Config.FernocotDragRotation or { x = 0.0, y = 0.0, z = 180.0 }

    FreezeEntityPosition(entity, false)

    AttachEntityToEntity(
      entity, ped, GetPedBoneIndex(ped, 0),
      dragOffset.x, dragOffset.y, dragOffset.z,
      dragRotation.x, dragRotation.y, dragRotation.z,
      true, true, false, true, 2, true
    )

    Framework.RequestAnimDict("anim@heists@box_carry@")
    TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)

    isDraggingBed = true
    draggedBedEntity = entity

    Framework.Notify(_L("release_bed_prompt"), "info")

    CreateThread(function()
      while isDraggingBed and DoesEntityExist(draggedBedEntity) do
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
  end
  dragOption.canInteract = function()
    return not isDraggingBed
  end

  -- Delete the bed (EMS only)
  local deleteOption = {}
  deleteOption.name = "ems_delete_bed"
  deleteOption.icon = "fas fa-trash"
  deleteOption.label = _L("bed_remove")
  deleteOption.onSelect = function(data)
    SetEntityAsMissionEntity(data.entity, true, true)
    DeleteEntity(data.entity)
    Framework.Notify(_L("bed_removed"), "success")
  end
  deleteOption.canInteract = function()
    local isEms = exports.plt_ambulance_job:IsEMS()
    if isEms then
      return not isDraggingBed
    end
    return isEms
  end

  optionDefs[1] = lieOption
  optionDefs[2] = getOffOption
  optionDefs[3] = dragOption
  optionDefs[4] = deleteOption

  if Config.Target == "ox_target" then
    exports.ox_target:addModel(modelName, optionDefs)
  elseif Config.Target == "qb-target" then
    exports["qb-target"]:AddTargetModel(modelName, {
      options = BuildTargetOptions(optionDefs),
      distance = 2.5
    })
  end

  -- ----------------------------------------------------------
  -- Target option for diagnosing another player (EMS only)
  -- ----------------------------------------------------------
  local diagnoseDefs = {}

  local diagnoseOption = {}
  diagnoseOption.name = "ems_diagnose"
  diagnoseOption.icon = "fas fa-stethoscope"
  diagnoseOption.label = _L("diagnose_injuries")
  diagnoseOption.onSelect = function(data)
    DiagnosePlayer(data.entity)
  end
  diagnoseOption.canInteract = function()
    return not isPerformingCpr and exports.plt_ambulance_job:IsEMS()
  end

  diagnoseDefs[1] = diagnoseOption

  if Config.Target == "ox_target" then
    exports.ox_target:addGlobalPlayer(diagnoseDefs)
  elseif Config.Target == "qb-target" then
    exports["qb-target"]:AddGlobalPlayer({
      options = BuildTargetOptions(diagnoseDefs),
      distance = 2.0
    })
  end

  -- ----------------------------------------------------------
  -- Target options for vehicles: take a fernocot out of the
  -- trunk / put it back in, restricted to ambulance-type vehicles
  -- ----------------------------------------------------------
  local fernocotVehicleModels = Config.FernocotVehicleModels or { "ambulance", "firetruk", "ambulance2" }

  local fernocotVehicleHashes = {}
  for _, modelStr in ipairs(fernocotVehicleModels) do
    fernocotVehicleHashes[GetHashKey(modelStr)] = true
  end

  -- Returns true if the given entity handle is a valid vehicle that
  -- counts as a "department vehicle" (either via statebag or model list)
  local function IsDepartmentVehicle(entity)
    if type(entity) ~= "number" then
      return false
    end
    if entity <= 0 then
      return false
    end
    if not DoesEntityExist(entity) then
      return false
    end
    if GetEntityType(entity) ~= 2 then
      return false
    end

    local state = Entity(entity) and Entity(entity).state

    if state then
      if state.amb_department_vehicle == true then
        return true
      end
    end

    local ok, model = pcall(GetEntityModel, entity)
    if not (ok and model) or model == 0 then
      return false
    end

    return fernocotVehicleHashes[model] == true
  end

  local vehicleOptionDefs = {}

  -- Take a fernocot out of the vehicle
  local takeBedOption = {}
  takeBedOption.name = "ems_take_bed"
  takeBedOption.icon = "fas fa-bed"
  takeBedOption.label = _L("bed_take_out")
  takeBedOption.distance = 4.0
  takeBedOption.onSelect = function(data)
    local vehicle = data.entity

    if not DoesEntityExist(vehicle) then
      return
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)

    local spawnCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -4.0, 0.0)
    local spawnHeading = GetEntityHeading(vehicle)

    CreateThread(function()
      Wait(150)

      local bed = SpawnFernocot(spawnCoords, spawnHeading)
      if not bed then
        Framework.Notify(_L("bed_takeout_failed"), "error")
        return
      end

      local ped = PlayerPedId()

      local dragOffset = Config.FernocotDragOffset or DEFAULT_DRAG_OFFSET
      local dragRotation = Config.FernocotDragRotation or { x = 0.0, y = 0.0, z = 180.0 }

      FreezeEntityPosition(bed, false)

      AttachEntityToEntity(
        bed, ped, GetPedBoneIndex(ped, 0),
        dragOffset.x, dragOffset.y, dragOffset.z,
        dragRotation.x, dragRotation.y, dragRotation.z,
        true, true, false, true, 2, true
      )

      Framework.RequestAnimDict("anim@heists@box_carry@")
      TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 50, 0, false, false, false)

      isDraggingBed = true
      draggedBedEntity = bed

      Framework.Notify(_L("release_bed_prompt"), "success")

      CreateThread(function()
        while isDraggingBed and DoesEntityExist(draggedBedEntity) do
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
  end
  takeBedOption.canInteract = function(entity)
    if not IsDepartmentVehicle(entity) then
      return false
    end
    if exports.plt_ambulance_job:IsEMS() then
      return not isDraggingBed
    end
    return false
  end

  -- Put the fernocot back into the vehicle's trunk
  local putBedOption = {}
  putBedOption.name = "ems_put_bed"
  putBedOption.icon = "fas fa-box"
  putBedOption.label = _L("bed_put_back_in")
  putBedOption.distance = 4.0
  putBedOption.onSelect = function(data)
    local vehicle = data.entity
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local modelHash = GetHashKey(Config.FernocotModel or "fernocot")

    local bedToStore = nil

    if isDraggingBed and draggedBedEntity then
      bedToStore = draggedBedEntity
      isDraggingBed = false
      draggedBedEntity = nil
      DetachEntity(bedToStore, true, true)
    else
      bedToStore = GetClosestObjectOfType(coords.x, coords.y, coords.z, 4.0, modelHash, false, false, false)
    end

    if bedToStore and bedToStore ~= 0 and DoesEntityExist(bedToStore) then
      SetEntityAsMissionEntity(bedToStore, true, true)
      DeleteEntity(bedToStore)
      ClearPedTasksImmediately(ped)

      Framework.Notify(_L("bed_put_back"), "success")

      CreateThread(function()
        Wait(100)
        ClearPedTasksImmediately(PlayerPedId())
      end)
    else
      Framework.Notify(_L("no_bed_nearby"), "error")
    end
  end
  putBedOption.canInteract = function(entity)
    if not IsDepartmentVehicle(entity) then
      return false
    end
    return exports.plt_ambulance_job:IsEMS()
  end

  vehicleOptionDefs[1] = takeBedOption
  vehicleOptionDefs[2] = putBedOption

  if Config.Target == "ox_target" then
    exports.ox_target:addGlobalVehicle(vehicleOptionDefs)
  elseif Config.Target == "qb-target" then
    exports["qb-target"]:AddGlobalVehicle({
      options = BuildTargetOptions(vehicleOptionDefs),
      distance = 4.0
    })
  end
end)

-- ------------------------------------------------------------
-- Diagnose a player's injuries (EMS action)
-- ------------------------------------------------------------
function DiagnosePlayer(targetPed)
  local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))

  Framework.Notify(_L("checking_vitals"), "info")

  TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)
  Wait(3000)
  ClearPedTasks(PlayerPedId())

  Framework.Notify(_L("patient_vitals_result"), "warning")
end

-- ------------------------------------------------------------
-- Perform CPR / revive a downed player (EMS action)
-- ------------------------------------------------------------
function RevivePlayerAction(targetPed)
  local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetPed))

  isPerformingCpr = true

  Framework.Notify(_L("performing_cpr"), "info")

  TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_KNOT", 0, true)

  local completed = Framework.ProgressBar(_L("progress_revive_player"), 10000)

  if completed then
    ClearPedTasks(PlayerPedId())
    TriggerServerEvent("amb_server:RevivePlayer", targetServerId)
    Framework.Notify(_L("player_revived"), "success")
  else
    ClearPedTasks(PlayerPedId())
  end

  isPerformingCpr = false
end

-- ------------------------------------------------------------
-- Deploy a temporary wheelchair vehicle for the player
-- ------------------------------------------------------------
RegisterNetEvent("amb_client:useWheelchair")
AddEventHandler("amb_client:useWheelchair", function(durationMinutes)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local forward = GetEntityForwardVector(ped)
  local spawnCoords = coords + (forward * 1.5)
  local heading = GetEntityHeading(ped)

  local wheelchairModel = -1963629913 -- "wheelchair"

  Framework.RequestModel(wheelchairModel)

  local vehicle = CreateVehicle(wheelchairModel, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, true)

  if DoesEntityExist(vehicle) then
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetModelAsNoLongerNeeded(wheelchairModel)

    Framework.GiveKeys(vehicle)
    Framework.Notify("Wheelchair deployed.", "success")

    if exports.plt_ambulance_job:GetInjuryType() == "fatal" then
      TaskWarpPedIntoVehicle(ped, vehicle, -1)
    end

    local duration = tonumber(durationMinutes)
    if not duration then
      duration = tonumber(Config.WheelchairDuration) or 10
    end

    local durationMs = math.floor(duration * 60000)

    print(string.format("[WHEELCHAIR] Deployed with duration: %d minutes (%d ms)", duration, durationMs))

    SetTimeout(durationMs, function()
      if DoesEntityExist(vehicle) then
        local driver = GetPedInVehicleSeat(vehicle, -1)
        if driver ~= 0 then
          TaskLeaveVehicle(driver, vehicle, 0)
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
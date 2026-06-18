-- ============================================================
-- Medical Bag - Client Script
-- De-obfuscated / cleaned up from compiled Lua
-- ============================================================

local isHoldingBag   = false   -- true while the player has the bag attached/equipped
local bagProp         = nil    -- the spawned bag prop entity
local bagModelHash    = -1187210516
local currentBagData  = nil    -- metadata/slot info of the bag currently held
local isEditMode      = false  -- true while /bagedit positioning mode is active

-- Default attach offset/rotation (used by the live edit mode below)
local bagOffset   = vector3(0.1, 0.0, 0.0)
local bagRotation = vector3(-90.0, 0.0, 0.0)

-- ------------------------------------------------------------
-- Equip / pick up the medical bag
-- ------------------------------------------------------------
RegisterNetEvent("amb_client:useMedicalBag")
AddEventHandler("amb_client:useMedicalBag", function(data)
  if isHoldingBag then
    Framework.Notify(_L("already_holding_bag"), "error")
    return
  end

  currentBagData = data

  local ped = PlayerPedId()

  Framework.RequestModel(bagModelHash)

  bagProp = CreateObject(bagModelHash, 0, 0, 0, true, true, true)

  AttachEntityToEntity(
    bagProp,
    ped,
    GetPedBoneIndex(ped, 57005),
    0.43, -0.065, -0.005,
    -90.0, -2.5, 78.0,
    true, true, false, true, 1, true
  )

  isHoldingBag = true

  Framework.Notify(_L("drop_bag_prompt"), "info")

  -- Listen for the "drop bag" key (X / control 38) while holding the bag
  CreateThread(function()
    while isHoldingBag do
      Wait(0)
      if not isEditMode then
        if IsControlJustPressed(0, 38) then
          DropBag()
        end
      end
    end
  end)
end)

-- ------------------------------------------------------------
-- Export so other resources can trigger "use medical bag"
-- ------------------------------------------------------------
exports("plt_medical_bag", function(item, slot)
  local metadata = nil
  if item and item.metadata then
    metadata = item.metadata
  end

  TriggerEvent("amb_client:useMedicalBag", {
    slot = slot,
    metadata = metadata
  })
end)

-- ------------------------------------------------------------
-- /bagedit - live attach-offset editing tool (debug command)
-- ------------------------------------------------------------
RegisterCommand("bagedit", function()
  if not isHoldingBag then
    Framework.Notify(_L("must_hold_bag_edit"), "error")
    return
  end

  isEditMode = true
  Framework.Notify(_L("bag_edit_mode"), "info")

  CreateThread(function()
    local ped = PlayerPedId()

    while isEditMode do
      Wait(0)

      local moved = false

      -- Hold Shift (control 21) for fine vs coarse step size
      local posStep = IsControlPressed(0, 21) and 0.05 or 0.005
      local rotStep = IsControlPressed(0, 21) and 5.0 or 0.5

      -- Position: X axis (Numpad 8 / 2 -> controls 172 / 173)
      if IsControlPressed(0, 172) then
        bagOffset = bagOffset + vector3(posStep, 0, 0)
        moved = true
      end
      if IsControlPressed(0, 173) then
        bagOffset = bagOffset - vector3(posStep, 0, 0)
        moved = true
      end

      -- Position: Y axis (Numpad 4 / 6 -> controls 174 / 175)
      if IsControlPressed(0, 174) then
        bagOffset = bagOffset + vector3(0, posStep, 0)
        moved = true
      end
      if IsControlPressed(0, 175) then
        bagOffset = bagOffset - vector3(0, posStep, 0)
        moved = true
      end

      -- Position: Z axis (controls 44 / 20)
      if IsControlPressed(0, 44) then
        bagOffset = bagOffset + vector3(0, 0, posStep)
        moved = true
      end
      if IsControlPressed(0, 20) then
        bagOffset = bagOffset - vector3(0, 0, posStep)
        moved = true
      end

      -- Rotation: X axis (controls 117 / 118)
      if IsControlPressed(0, 117) then
        bagRotation = bagRotation + vector3(rotStep, 0, 0)
        moved = true
      end
      if IsControlPressed(0, 118) then
        bagRotation = bagRotation - vector3(rotStep, 0, 0)
        moved = true
      end

      -- Rotation: Y axis (controls 124 / 125)
      if IsControlPressed(0, 124) then
        bagRotation = bagRotation + vector3(0, rotStep, 0)
        moved = true
      end
      if IsControlPressed(0, 125) then
        bagRotation = bagRotation - vector3(0, rotStep, 0)
        moved = true
      end

      -- Rotation: Z axis (controls 126 / 127)
      if IsControlPressed(0, 126) then
        bagRotation = bagRotation + vector3(0, 0, rotStep)
        moved = true
      end
      if IsControlPressed(0, 127) then
        bagRotation = bagRotation - vector3(0, 0, rotStep)
        moved = true
      end

      -- Re-attach with the new offset/rotation whenever something changed
      if moved then
        DetachEntity(bagProp, true, true)
        AttachEntityToEntity(
          bagProp,
          ped,
          GetPedBoneIndex(ped, 57005),
          bagOffset.x, bagOffset.y, bagOffset.z,
          bagRotation.x, bagRotation.y, bagRotation.z,
          true, true, false, true, 1, true
        )
      end

      -- On-screen readout of current offset/rotation + instructions
      local info = string.format(
        "OFF: %.3f, %.3f, %.3f | ROT: %.1f, %.1f, %.1f",
        bagOffset.x, bagOffset.y, bagOffset.z,
        bagRotation.x, bagRotation.y, bagRotation.z
      )

      SetTextFont(0)
      SetTextProportional(1)
      SetTextScale(0.0, 0.35)
      SetTextColour(255, 255, 255, 255)
      SetTextDropshadow(0, 0, 0, 0, 255)
      SetTextEdge(1, 0, 0, 0, 255)
      SetTextDropShadow()
      SetTextOutline()
      SetTextEntry("STRING")
      AddTextComponentString(_L("bag_edit_instructions", { info = info }))
      DrawText(0.4, 0.8)

      -- Press Enter (control 18) to confirm and print the final attach code
      if IsControlJustPressed(0, 18) then
        isEditMode = false

        local finalCode = string.format(
          "AttachEntityToEntity(bagProp, ped, GetPedBoneIndex(ped, 57005), %.3f, %.3f, %.3f, %.1f, %.1f, %.1f, true, true, false, true, 1, true)",
          bagOffset.x, bagOffset.y, bagOffset.z,
          bagRotation.x, bagRotation.y, bagRotation.z
        )

        print("^2[BAG_EDIT] FINAL CODE:^7")
        print(finalCode)

        TriggerEvent("chat:addMessage", {
          color = { 0, 255, 0 },
          multiline = true,
          args = { "SYSTEM", _L("bag_position_saved") }
        })
      end
    end
  end)
end)

-- ------------------------------------------------------------
-- Drop the bag (detach prop, sync to server, clear state)
-- ------------------------------------------------------------
function DropBag()
  local ped = PlayerPedId()

  local coords  = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local forward = GetEntityForwardVector(ped)

  local dropCoords = coords + (forward * 0.5)

  -- Try to snap the drop position to the ground
  local foundGround, groundZ = GetGroundZFor_3dCoord(dropCoords.x, dropCoords.y, dropCoords.z, false)
  if not foundGround then
    foundGround, groundZ = GetGroundZFor_3dCoord(dropCoords.x, dropCoords.y, dropCoords.z + 5.0, false)
  end
  if foundGround then
    dropCoords = vector3(dropCoords.x, dropCoords.y, groundZ)
  end

  DetachEntity(bagProp, true, true)
  DeleteEntity(bagProp)
  bagProp = nil
  isHoldingBag = false

  -- Resolve the bag's unique id from whichever field it was stored under
  local bagId = nil
  local slot  = nil

  if currentBagData then
    slot = currentBagData.slot

    if currentBagData.metadata and currentBagData.metadata.bagId then
      bagId = currentBagData.metadata.bagId
    elseif currentBagData.info and currentBagData.info.bagId then
      bagId = currentBagData.info.bagId
    end
  end

  currentBagData = nil

  TriggerServerEvent("amb_server:dropMedicalBag", dropCoords, heading, bagId, slot)
end

-- ------------------------------------------------------------
-- Open the bag inventory UI (NUI)
-- ------------------------------------------------------------
RegisterNetEvent("amb_client:openBagUI")
AddEventHandler("amb_client:openBagUI", function(data)
  print("^2[PLT_BAG] Opening UI. Received " .. #data.playerItems .. " player items.^7")

  SetNuiFocus(true, true)

  SendNUIMessage({
    action          = "amb_openBagUI",
    bagId           = data.bagId,
    netId           = data.netId,
    items           = data.items,
    weight          = data.weight,
    maxWeight       = data.maxWeight,
    maxSlots        = data.maxSlots,
    playerItems     = data.playerItems,
    playerWeight    = data.playerWeight,
    playerMaxWeight = data.playerMaxWeight,
    playerMaxSlots  = data.playerMaxSlots,
    imagePath       = Config.InventoryImages or "img/"
  })
end)

RegisterNUICallback("amb_closeBag", function(data, cb)
  SetNuiFocus(false, false)
  cb("ok")
end)

RegisterNUICallback("amb_takeBagItem", function(data, cb)
  TriggerServerEvent("amb_server:takeBagItem", data)
  cb("ok")
end)

RegisterNUICallback("amb_storeInBag", function(data, cb)
  TriggerServerEvent("amb_server:storeInBag", data)
  cb("ok")
end)

-- ------------------------------------------------------------
-- Target system integration (ox_target / qb-target)
-- ------------------------------------------------------------
CreateThread(function()
  if Config.Target == "ox_target" then
    exports.ox_target:addModel(bagModelHash, {
      {
        name  = "open_medical_bag",
        icon  = "fas fa-briefcase_medical",
        label = _L("open_medical_bag"),
        onSelect = function(data)
          local netId = NetworkGetNetworkIdFromEntity(data.entity)
          if netId == 0 then
            Framework.Notify(_L("bag_netid_missing"), "error")
            return
          end
          TriggerServerEvent("amb_server:openBagInventory", netId)
        end
      },
      {
        name  = "pickup_medical_bag",
        icon  = "fas fa-hand-holding",
        label = _L("pickup_medical_bag"),
        onSelect = function(data)
          local netId = NetworkGetNetworkIdFromEntity(data.entity)
          TriggerServerEvent("amb_server:pickupMedicalBag", netId)
        end
      }
    })
  elseif Config.Target == "qb-target" then
    exports["qb-target"]:AddTargetModel(bagModelHash, {
      options = {
        {
          type  = "client",
          event = "amb_client:openBagTarget",
          icon  = "fas fa-briefcase_medical",
          label = _L("open_medical_bag")
        },
        {
          type  = "client",
          event = "amb_client:pickupBagTarget",
          icon  = "fas fa-hand-holding",
          label = _L("pickup_medical_bag")
        }
      },
      distance = 2.0
    })
  end
end)

RegisterNetEvent("amb_client:openBagTarget")
AddEventHandler("amb_client:openBagTarget", function(data)
  local netId = NetworkGetNetworkIdFromEntity(data.entity)
  TriggerServerEvent("amb_server:openBagInventory", netId)
end)

RegisterNetEvent("amb_client:pickupBagTarget")
AddEventHandler("amb_client:pickupBagTarget", function(data)
  local netId = NetworkGetNetworkIdFromEntity(data.entity)
  TriggerServerEvent("amb_server:pickupMedicalBag", netId)
end)
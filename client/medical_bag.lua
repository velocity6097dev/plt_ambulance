local isHoldingBag = false
local currentBagEntity = nil
local BAG_MODEL_HASH = -1187210516
local activeBagData = nil
local isEditingBag = false

local bagOffset = vector3(0.1, 0.0, 0.0)
local bagRotation = vector3(-90.0, 0.0, 0.0)

RegisterNetEvent("amb_client:useMedicalBag", function(bagData)
    if isHoldingBag then
        Framework.Notify(_L("already_holding_bag"), "error")
        return
    end

    activeBagData = bagData
    local ped = PlayerPedId()
    
    Framework.RequestModel(BAG_MODEL_HASH)
    local bagProp = CreateObject(BAG_MODEL_HASH, 0, 0, 0, true, true, true)
    currentBagEntity = bagProp
    
    AttachEntityToEntity(
        currentBagEntity, 
        ped, 
        GetPedBoneIndex(ped, 57005), 
        0.43, -0.065, -0.005, 
        -90.0, -2.5, 78.0, 
        true, true, false, true, 1, true
    )
    
    isHoldingBag = true
    Framework.Notify(_L("drop_bag_prompt"), "info")
    
    CreateThread(function()
        while isHoldingBag do
            Wait(0)
            if not isEditingBag then
                if IsControlJustPressed(0, 38) then -- E Key
                    DropBag()
                end
            end
        end
    end)
end)

exports("plt_medical_bag", function(data, slot)
    TriggerEvent("amb_client:useMedicalBag", {
        slot = slot,
        metadata = data and data.metadata
    })
end)

RegisterCommand("bagedit", function()
    if not isHoldingBag then
        Framework.Notify(_L("must_hold_bag_edit"), "error")
        return
    end
    
    isEditingBag = true
    Framework.Notify(_L("bag_edit_mode"), "info")
    
    CreateThread(function()
        local ped = PlayerPedId()
        while isEditingBag do
            Wait(0)
            local hasChanged = false
            local multiplier = IsControlPressed(0, 21) and 0.05 or 0.005
            local rotMultiplier = IsControlPressed(0, 21) and 5.0 or 0.5
            
            -- Offset Controls
            if IsControlPressed(0, 172) then bagOffset = bagOffset + vector3(multiplier, 0, 0) hasChanged = true end
            if IsControlPressed(0, 173) then bagOffset = bagOffset - vector3(multiplier, 0, 0) hasChanged = true end
            if IsControlPressed(0, 174) then bagOffset = bagOffset + vector3(0, multiplier, 0) hasChanged = true end
            if IsControlPressed(0, 175) then bagOffset = bagOffset - vector3(0, multiplier, 0) hasChanged = true end
            if IsControlPressed(0, 44) then bagOffset = bagOffset + vector3(0, 0, multiplier) hasChanged = true end
            if IsControlPressed(0, 20) then bagOffset = bagOffset - vector3(0, 0, multiplier) hasChanged = true end
            
            -- Rotation Controls
            if IsControlPressed(0, 117) then bagRotation = bagRotation + vector3(rotMultiplier, 0, 0) hasChanged = true end
            if IsControlPressed(0, 118) then bagRotation = bagRotation - vector3(rotMultiplier, 0, 0) hasChanged = true end
            if IsControlPressed(0, 124) then bagRotation = bagRotation + vector3(0, rotMultiplier, 0) hasChanged = true end
            if IsControlPressed(0, 125) then bagRotation = bagRotation - vector3(0, rotMultiplier, 0) hasChanged = true end
            if IsControlPressed(0, 126) then bagRotation = bagRotation + vector3(0, 0, rotMultiplier) hasChanged = true end
            if IsControlPressed(0, 127) then bagRotation = bagRotation - vector3(0, 0, rotMultiplier) hasChanged = true end
            
            if hasChanged then
                DetachEntity(currentBagEntity, true, true)
                AttachEntityToEntity(currentBagEntity, ped, GetPedBoneIndex(ped, 57005), 
                    bagOffset.x, bagOffset.y, bagOffset.z, 
                    bagRotation.x, bagRotation.y, bagRotation.z, 
                    true, true, false, true, 1, true
                )
            end
            
            local debugText = string.format("OFF: %.3f, %.3f, %.3f | ROT: %.1f, %.1f, %.1f", 
                bagOffset.x, bagOffset.y, bagOffset.z, 
                bagRotation.x, bagRotation.y, bagRotation.z)
            
            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.0, 0.35)
            SetTextColour(255, 255, 255, 255)
            SetTextEntry("STRING")
            AddTextComponentString(_L("bag_edit_instructions", { info = debugText }))
            DrawText(0.4, 0.8)
            
            if IsControlJustPressed(0, 18) then -- Enter
                isEditingBag = false
                local finalCode = string.format("AttachEntityToEntity(bagProp, ped, GetPedBoneIndex(ped, 57005), %.3f, %.3f, %.3f, %.1f, %.1f, %.1f, true, true, false, true, 1, true)", 
                    bagOffset.x, bagOffset.y, bagOffset.z, 
                    bagRotation.x, bagRotation.y, bagRotation.z)
                print("^2[BAG_EDIT] FINAL CODE:^7")
                print(finalCode)
                TriggerEvent("chat:addMessage", {
                    color = {0, 255, 0},
                    multiline = true,
                    args = {"SYSTEM", _L("bag_position_saved", { info = finalCode })}
                })
            end
        end
    end)
end, false)

function DropBag()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local forward = GetEntityForwardVector(ped)
    local dropCoords = coords + (forward * 0.5)
    
    local foundGround, groundZ = GetGroundZFor_3dCoord(dropCoords.x, dropCoords.y, dropCoords.z, false)
    if not foundGround then
        local _, newZ = GetGroundZFor_3dCoord(dropCoords.x, dropCoords.y, dropCoords.z + 5.0, false)
        groundZ = newZ
    end
    
    if foundGround then
        dropCoords = vector3(dropCoords.x, dropCoords.y, groundZ)
    end
    
    DetachEntity(currentBagEntity, true, true)
    DeleteEntity(currentBagEntity)
    currentBagEntity = nil
    isHoldingBag = false
    
    local bagId = nil
    if activeBagData then
        bagId = activeBagData.bagId or (activeBagData.metadata and activeBagData.metadata.bagId) or (activeBagData.info and activeBagData.info.bagId)
    end
    
    activeBagData = nil
    TriggerServerEvent("amb_server:dropMedicalBag", dropCoords, heading, bagId, nil)
end

RegisterNetEvent("amb_client:openBagUI", function(data)
    print("^2[PLT_BAG] Opening UI. Received " .. #data.playerItems .. " player items.^7")
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "amb_openBagUI",
        bagId = data.bagId,
        netId = data.netId,
        items = data.items,
        weight = data.weight,
        maxWeight = data.maxWeight,
        maxSlots = data.maxSlots,
        playerItems = data.playerItems,
        playerWeight = data.playerWeight,
        playerMaxWeight = data.playerMaxWeight,
        playerMaxSlots = data.playerMaxSlots,
        imagePath = Config.InventoryImages or "img/"
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

CreateThread(function()
    if Config.Target == "ox_target" then
        exports.ox_target:addModel(BAG_MODEL_HASH, {
            {
                name = "open_medical_bag",
                icon = "fas fa-briefcase-medical",
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
                name = "pickup_medical_bag",
                icon = "fas fa-hand-holding",
                label = _L("pickup_medical_bag"),
                onSelect = function(data)
                    TriggerServerEvent("amb_server:pickupMedicalBag", NetworkGetNetworkIdFromEntity(data.entity))
                end
            }
        })
    elseif Config.Target == "qb-target" then
        exports["qb-target"]:AddTargetModel(BAG_MODEL_HASH, {
            options = {
                {
                    type = "client",
                    event = "amb_client:openBagTarget",
                    icon = "fas fa-briefcase-medical",
                    label = _L("open_medical_bag")
                },
                {
                    type = "client",
                    event = "amb_client:pickupBagTarget",
                    icon = "fas fa-hand-holding",
                    label = _L("pickup_medical_bag")
                }
            },
            distance = 2.0
        })
    end
end)

RegisterNetEvent("amb_client:openBagTarget", function(data)
    TriggerServerEvent("amb_server:openBagInventory", NetworkGetNetworkIdFromEntity(data.entity))
end)

RegisterNetEvent("amb_client:pickupBagTarget", function(data)
    TriggerServerEvent("amb_server:pickupMedicalBag", NetworkGetNetworkIdFromEntity(data.entity))
end)
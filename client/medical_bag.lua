local BagModelHash = -1187210516 -- xm_prop_x17_bag_med_01a
local IsPlacingBag = false
local ActiveBagEntity = nil

-- ==========================================
-- Core Events
-- ==========================================

RegisterNetEvent("amb_client:useMedicalBag", function(itemData)
    if IsPlacingBag then return end
    IsPlacingBag = true

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local spawnCoords = coords + (forward * 0.8)
    local heading = GetEntityHeading(ped)

    -- Play placement animation
    local animDict = "random@domestic"
    local animName = "pickup_low"
    
    Framework.RequestAnimDict(animDict)
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 1000, 48, 0, false, false, false)
    Wait(500)

    -- Request and spawn the bag
    Framework.RequestModel(BagModelHash)
    
    local bagObject = CreateObject(BagModelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, true, true, true)
    if DoesEntityExist(bagObject) then
        SetEntityHeading(bagObject, heading + 90.0)
        PlaceObjectOnGroundProperly(bagObject)
        SetEntityAsMissionEntity(bagObject, true, true)
        FreezeEntityPosition(bagObject, true)
        
        SetModelAsNoLongerNeeded(BagModelHash)
        
        -- Tell server to remove the item from inventory
        TriggerServerEvent("amb_server:removeMedicalBag")
        Framework.Notify(_L("placed_medical_bag"), "success")
    else
        Framework.Notify(_L("failed_place_bag"), "error")
    end

    IsPlacingBag = false
end)

RegisterNetEvent("amb_client:pickupBagTarget", function(data)
    local entity = data.entity
    if not DoesEntityExist(entity) then return end

    local ped = PlayerPedId()
    local animDict = "random@domestic"
    local animName = "pickup_low"

    Framework.RequestAnimDict(animDict)
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 1000, 48, 0, false, false, false)
    Wait(500)

    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)

    -- Give the item back to the player
    TriggerServerEvent("amb_server:giveMedicalBag")
    Framework.Notify(_L("picked_up_medical_bag"), "success")
end)

RegisterNetEvent("amb_client:openBagTarget", function(data)
    local entity = data.entity
    if not DoesEntityExist(entity) then return end

    if not exports.plt_ambulance_job:IsEMS() then
        Framework.Notify(_L("not_authorized"), "error")
        return
    end

    local netId = 0
    if NetworkGetEntityIsNetworked(entity) then
        netId = NetworkGetNetworkIdFromEntity(entity)
    else
        -- Fallback to local handle if not networked properly
        netId = entity
    end

    local stashId = "plt_medical_bag_" .. tostring(netId)
    local stashName = _L("medical_bag_stash")
    
    local weight = (Config.Items and Config.Items.MedicalBagWeight) or 10000
    local slots = (Config.Items and Config.Items.MedicalBagSlots) or 10

    -- Open Inventory specific to the framework
    if GetResourceState("ox_inventory") == "started" then
        exports.ox_inventory:openInventory("stash", stashId)
    elseif GetResourceState("qb-inventory") == "started" or GetResourceState("ps-inventory") == "started" or GetResourceState("qs-inventory") == "started" then
        TriggerServerEvent("inventory:server:OpenInventory", "stash", stashId, {
            maxweight = weight,
            slots = slots,
        })
        TriggerEvent("inventory:client:SetCurrentStash", stashId)
    else
        -- Generic fallback
        TriggerServerEvent("amb_server:openBagStash", stashId)
    end
end)

-- ==========================================
-- Target Registration
-- ==========================================

CreateThread(function()
    local targetOptions = {
        {
            icon = "fas fa-briefcase-medical",
            label = _L("open_medical_bag"),
            action = function(entity)
                TriggerEvent("amb_client:openBagTarget", { entity = entity })
            end,
            canInteract = function(entity)
                return exports.plt_ambulance_job:IsEMS()
            end
        },
        {
            icon = "fas fa-hand-holding",
            label = _L("pickup_medical_bag"),
            action = function(entity)
                TriggerEvent("amb_client:pickupBagTarget", { entity = entity })
            end,
            canInteract = function(entity)
                return exports.plt_ambulance_job:IsEMS()
            end
        }
    }

    if Config.Target == "ox_target" then
        local oxOptions = {}
        for _, opt in ipairs(targetOptions) do
            table.insert(oxOptions, {
                name = opt.label,
                icon = opt.icon,
                label = opt.label,
                onSelect = function(data) opt.action(data.entity) end,
                canInteract = function(entity) return opt.canInteract(entity) end
            })
        end
        exports.ox_target:addModel(BagModelHash, oxOptions)

    elseif Config.Target == "qb-target" then
        local qbOptions = {}
        for _, opt in ipairs(targetOptions) do
            table.insert(qbOptions, {
                type = "client",
                icon = opt.icon,
                label = opt.label,
                action = function(entity) opt.action(entity) end,
                canInteract = function(entity) return opt.canInteract(entity) end
            })
        end
        
        exports["qb-target"]:AddTargetModel(BagModelHash, {
            options = qbOptions,
            distance = 2.0
        })
    end
end)
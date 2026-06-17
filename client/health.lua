-- ==========================================
-- Core Variables & State
-- ==========================================

local InjuryData = {
    head = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0, needsFludro = false },
    chest = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    left_arm = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    right_arm = { level = 0, bullet = false, bandaged = false, hunger = false, isFractured = false, fractureTime = 0 },
    left_leg = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    right_leg = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    bleeding = 0
}

local isPatientBandaged = false
local isDead = false
local isLimping = false
local isBlurry = false
local disableControlsTimer = 0
local savedHealthCache = nil
local timeOfLastRevive = 0

local animDeadDict = "dead"
local animDeadName = "dead_a"
local animVehDict = "veh@low@front_ps@idle_duck"
local animVehName = "sit"

local ClothesCache = { model = nil, top = nil, bottom = nil }
local isPhoneDisabled = false
local isInvDisabled = false
local isVoiceMuted = false

-- ==========================================
-- Utility & Integration Functions
-- ==========================================

local function GetConfigRestrictions()
    local res = (Config.Health and Config.Health.DeadRestrictions) or {}
    if type(res) ~= "table" then
        return { DisableVoice = false, DisableInventory = false }
    end
    return {
        DisableVoice = (res.DisableVoice == true),
        DisableInventory = (res.DisableInventory == true)
    }
end

local function ClosePhone()
    if GetResourceState("lb-phone") == "started" then
        pcall(function() exports["lb-phone"]:closePhone() end)
        pcall(function() exports["lb-phone"]:ClosePhone() end)
        pcall(function() exports["lb-phone"]:toggleOpen(false) end)
        pcall(function() exports["lb-phone"]:ToggleOpen(false) end)
        TriggerEvent("lb-phone:client:closePhone")
        TriggerEvent("lb-phone:closePhone")
    end
end

local function CloseInventory()
    TriggerEvent("inventory:client:closeInventory")
    TriggerEvent("qb-inventory:client:closeInventory")
    TriggerEvent("qs-inventory:client:closeInv")
    TriggerEvent("qs-inventory:client:closeInventory")
    TriggerEvent("origin_inventory:client:closeInventory")
    TriggerEvent("origen_inventory:client:closeInventory")
    if GetResourceState("ox_inventory") == "started" then
        pcall(function() exports.ox_inventory:closeInventory() end)
    end
end

local function DisablePhoneControls(state)
    state = (state == true)
    if isPhoneDisabled == state then return end
    isPhoneDisabled = state

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("phoneDisabled", state, true)
        LocalPlayer.state:set("canUsePhone", not state, true)
        LocalPlayer.state:set("lbPhoneDisabled", state, true)
    end

    if GetResourceState("lb-phone") == "started" then
        pcall(function() exports["lb-phone"]:setPhoneDisabled(state) end)
        pcall(function() exports["lb-phone"]:SetPhoneDisabled(state) end)
        pcall(function() exports["lb-phone"]:setDisabled(state) end)
        pcall(function() exports["lb-phone"]:SetDisabled(state) end)
        TriggerEvent("lb-phone:client:setDisabled", state)
        TriggerEvent("lb-phone:client:toggleDisabled", state)
    end

    if state then ClosePhone() end
end

local function DisableInventoryControls(state)
    local config = GetConfigRestrictions()
    if not config.DisableInventory then state = false end

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("dead", state, true)
        LocalPlayer.state:set("invBusy", state, true)
        LocalPlayer.state:set("invOpen", false, false)
        LocalPlayer.state:set("invHotkeys", not state, false)
        LocalPlayer.state:set("canUseWeapons", not state, false)
    end

    if state then CloseInventory() end
end

local function DisableVoice(state)
    local config = GetConfigRestrictions()
    if not config.DisableVoice then state = false end
    if isVoiceMuted == state then return end

    local success = pcall(function()
        MumbleSetPlayerMuted(PlayerId(), state)
    end)
    if success then isVoiceMuted = state end
end

local function ToggleDeathRestrictions(state)
    DisableVoice(state)
    DisableInventoryControls(state)
    DisablePhoneControls(state)
end

-- ==========================================
-- Core Health & Injury Functions
-- ==========================================

function DisableHealthRecharge()
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)
end

function ResetInjuries()
    for key, data in pairs(InjuryData) do
        if type(data) == "table" then
            data.level = 0
            data.bullet = false
            data.bandaged = false
            if data.hunger ~= nil then data.hunger = false end
            data.needsFludro = false
            data.isFractured = false
            data.fractureTime = 0
        else
            InjuryData[key] = 0
        end
    end
end

function SyncInjuryData()
    local syncData = {}
    for key, value in pairs(InjuryData) do
        syncData[key] = value
    end
    syncData.isPatientBandaged = isPatientBandaged
    TriggerServerEvent("amb_server:syncInjuryData", syncData)
end

function GetInjuryType()
    if isDead then return "fatal" end
    if InjuryData.bleeding > 0 then return "severe" end
    
    local totalLevel = 0
    for _, data in pairs(InjuryData) do
        if type(data) == "table" and data.level then
            totalLevel = totalLevel + data.level
        end
    end
    
    if totalLevel > 0 then return "minor" end
    return "minor" -- Default
end
exports("GetInjuryType", GetInjuryType)

-- ==========================================
-- Clothes Removal (For Surgery/Treatment)
-- ==========================================

local function GetComponentData(ped, componentId)
    return {
        drawable = GetPedDrawableVariation(ped, componentId),
        texture = GetPedTextureVariation(ped, componentId),
        palette = GetPedPaletteVariation(ped, componentId)
    }
end

function SaveClothesState(part)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end
    
    local currentModel = GetEntityModel(ped)
    if ClothesCache.model ~= currentModel then
        ClothesCache.model = currentModel
        ClothesCache.top = nil
        ClothesCache.bottom = nil
    end
    
    if part == "top" and not ClothesCache.top then
        ClothesCache.top = {
            torso = GetComponentData(ped, 3),
            undershirt = GetComponentData(ped, 8),
            top = GetComponentData(ped, 11)
        }
    elseif part == "bottom" and not ClothesCache.bottom then
        ClothesCache.bottom = GetComponentData(ped, 4)
    end
end

function RestoreClothesState()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or not ClothesCache.model then return end
    
    if GetEntityModel(ped) ~= ClothesCache.model then
        ClothesCache = { model = nil, top = nil, bottom = nil }
        return
    end
    
    if ClothesCache.top then
        local c = ClothesCache.top
        if c.torso then SetPedComponentVariation(ped, 3, c.torso.drawable, c.torso.texture or 0, c.torso.palette or 0) end
        if c.undershirt then SetPedComponentVariation(ped, 8, c.undershirt.drawable, c.undershirt.texture or 0, c.undershirt.palette or 0) end
        if c.top then SetPedComponentVariation(ped, 11, c.top.drawable, c.top.texture or 0, c.top.palette or 0) end
    end
    
    if ClothesCache.bottom then
        local c = ClothesCache.bottom
        SetPedComponentVariation(ped, 4, c.drawable, c.texture or 0, c.palette or 0)
    end
    
    ClothesCache = { model = nil, top = nil, bottom = nil }
end

RegisterNetEvent("amb_client:removeClothes", function(part)
    local ped = PlayerPedId()
    SaveClothesState(part)
    
    local isMale = (GetEntityModel(ped) == GetHashKey("mp_m_freemode_01"))
    
    if part == "top" then
        if isMale then
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            SetPedComponentVariation(ped, 8, 15, 0, 0)
            SetPedComponentVariation(ped, 3, 15, 0, 0)
        else
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            SetPedComponentVariation(ped, 8, 14, 0, 0)
            SetPedComponentVariation(ped, 3, 15, 0, 0)
        end
    elseif part == "bottom" then
        if isMale then
            SetPedComponentVariation(ped, 4, 14, 0, 0)
        else
            SetPedComponentVariation(ped, 4, 15, 0, 0)
        end
    end
    
    TriggerEvent("amb_client:requestInjuryData")
end)

-- ==========================================
-- Damage Processing (Bones & Fractures)
-- ==========================================

local BoneMap = {
    [31086] = "head", [39317] = "head", [12844] = "head", [65068] = "head",
    [24816] = "chest", [24817] = "chest", [24818] = "chest", [10706] = "chest", [11816] = "chest", [57597] = "chest", [23553] = "chest",
    [64729] = "left_arm", [45509] = "left_arm", [61163] = "left_arm", [18905] = "left_arm", [26610] = "left_arm", [26611] = "left_arm",
    [40269] = "right_arm", [28252] = "right_arm", [57005] = "right_arm", [58866] = "right_arm", [58867] = "right_arm",
    [58271] = "left_leg", [63931] = "left_leg", [63923] = "left_leg", [2108] = "left_leg", [14201] = "left_leg",
    [51826] = "right_leg", [36864] = "right_leg", [52301] = "right_leg", [20781] = "right_leg", [35502] = "right_leg"
}

local function GetBoneDamageTarget(ped)
    local found, boneId = GetPedLastDamageBone(ped)
    if not found or boneId == 0 then
        Wait(0)
        found, boneId = GetPedLastDamageBone(ped)
    end
    if found and boneId then
        return BoneMap[boneId] or "chest"
    end
    return "chest"
end

local FallHashes = {
    [-1553120962] = true, [133987706] = true, [341774354] = true,
    [-868994466] = true, [148160082] = true
}

local function CheckDamageCause(ped, causeHash, entityHit)
    local deathCause = GetPedCauseOfDeath(ped)
    local speed = GetEntitySpeed(ped) * 3.6
    
    local isVehicleCollision = (causeHash == -1438083414 or deathCause == -1438083414)
    if DoesEntityExist(entityHit) and IsEntityAVehicle(entityHit) then
        isVehicleCollision = true
    end

    local isFall = FallHashes[causeHash] or FallHashes[deathCause]
    return isVehicleCollision, isFall
end

local function ApplyFracture(part, typeReason)
    if not part or not InjuryData[part] then return false end
    if InjuryData[part].isFractured then return false end

    local chance = (Config.Health and Config.Health.FractureChance) or 80
    if math.random(1, 100) > chance then return false end

    InjuryData[part].isFractured = true
    InjuryData[part].fractureTime = (Config.Health and Config.Health.FractureTime) or 600
    print(string.format("^1[FRACTURE] %s (%s)^7", part, typeReason or "impact"))
    return true
end

-- ==========================================
-- Game Event / Damage Detector
-- ==========================================

AddEventHandler("gameEventTriggered", function(eventName, data)
    if eventName == "CEventNetworkEntityDamage" then
        local victim = data[1]
        local culprit = data[2]
        local weaponHash = data[7]
        local ped = PlayerPedId()

        if victim == ped then
            -- Check for Downed Threshold
            local threshold = (Config.Health and Config.Health.DownedThreshold) or 0
            local currentHealth = GetEntityHealth(ped)
            
            if currentHealth <= threshold and not isDead then
                -- Downed State Triggered
                isDead = true
                TriggerServerEvent("amb_server:SetDowned", true)
                ToggleDeathRestrictions(true)
                
                -- Ensure injuries exist
                local totalLevel = 0
                for k, v in pairs(InjuryData) do
                    if type(v) == "table" and v.level then totalLevel = totalLevel + v.level end
                end
                if totalLevel == 0 then InjuryData.chest.level = 2 end
                
                SendDeathDispatch()
                TriggerEvent("amb_client:onPlayerDeath", "dead")
                return
            end

            -- Apply Damage Details
            local targetBone = GetBoneDamageTarget(ped)
            if targetBone then
                local maxLevel = (Config.Health and Config.Health.MaxInjuryLevel) or 5
                InjuryData[targetBone].level = math.min(maxLevel, InjuryData[targetBone].level + 1)
                
                local isVeh, isFall = CheckDamageCause(ped, data[6], culprit)
                if isVeh or isFall then
                    local randomLeg = (math.random(1, 2) == 1) and "left_leg" or "right_leg"
                    if not ApplyFracture(randomLeg, "fall") then
                        ApplyFracture(targetBone, "impact_fallback")
                    end
                end

                -- Bullet checks
                local weaponGroup = GetWeapontypeGroup(weaponHash)
                if weaponGroup == 416676503 or weaponGroup == -95745345 or weaponGroup == 860033945 or weaponGroup == 970310034 then
                    InjuryData[targetBone].bullet = true
                    
                    local bleedChance = (Config.Health and Config.Health.BulletBleedChance) or 90
                    if math.random(1, 100) < bleedChance then
                        InjuryData.bleeding = InjuryData.bleeding + 1
                    end
                else
                    local bleedChance = (Config.Health and Config.Health.BleedChance) or 40
                    if math.random(1, 100) < bleedChance then
                        InjuryData.bleeding = InjuryData.bleeding + 1
                    end
                end
                
                SyncInjuryData()
            end
        end
    end
end)

-- ==========================================
-- Threads
-- ==========================================

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()

        -- Fracture Healing Loop
        for part, data in pairs(InjuryData) do
            if type(data) == "table" and data.isFractured then
                if data.fractureTime > 0 then
                    data.fractureTime = data.fractureTime - 1
                else
                    data.isFractured = false
                    TriggerEvent("amb_client:Notify", _L("fracture_healed", {part = part:gsub("_", " ")}), "success")
                end
            end
        end

        -- Movement Limiters (Limping / Shake)
        local legFractured = InjuryData.left_leg.isFractured or InjuryData.right_leg.isFractured
        local legInjured = InjuryData.left_leg.level > 0 or InjuryData.right_leg.level > 0
        
        if legFractured or legInjured then
            DisableControlAction(0, 21, true) -- Disable Sprint
            if not isLimping then
                Framework.RequestAnimSet("move_m@limping@a")
                SetPedMovementClipset(ped, "move_m@limping@a", 1.0)
                isLimping = true
            end
        elseif isLimping then
            ResetPedMovementClipset(ped, 0)
            isLimping = false
        end

        local armFractured = InjuryData.left_arm.isFractured or InjuryData.right_arm.isFractured
        if armFractured then
            DisableControlAction(0, 21, true)
        end
        
        if (InjuryData.left_arm.level > 0 or InjuryData.right_arm.level > 0) and IsControlPressed(0, 25) then -- Aiming
            local shakeForce = ((InjuryData.left_arm.level + InjuryData.right_arm.level) * 0.5)
            if armFractured then shakeForce = shakeForce + 1.5 end
            ShakeGameplayCam("HAND_SHAKE", shakeForce)
        end

        -- Screen Effects & Bleeding Loop
        if InjuryData.head.level > 0 and Config.EnableBlurEffect ~= false then
            if not isBlurry then TriggerScreenblurFadeIn(1000.0); isBlurry = true end
        elseif isBlurry then
            TriggerScreenblurFadeOut(1000.0)
            isBlurry = false
        end

        if InjuryData.bleeding > 0 then
            local rate = (Config.Health and Config.Health.BleedRate) or 1
            local damage = rate * InjuryData.bleeding
            SetEntityHealth(ped, GetEntityHealth(ped) - damage)
        end
    end
end)

-- ==========================================
-- Items / Medication Execution
-- ==========================================

local MedItems = {
    plt_bandage = true, plt_painkillers = true, plt_painkillers_adv = true,
    plt_antibiotics = true, plt_medkit = true, iak_wheelchair = true
}

local function HasInjuries()
    if InjuryData.bleeding > 0 then return true end
    for _, data in pairs(InjuryData) do
        if type(data) == "table" then
            if data.level > 0 or data.bullet or data.isFractured then return true end
        end
    end
    return GetEntityHealth(PlayerPedId()) < 200
end

RegisterNetEvent("amb_client:useMedication", function(item, metadata)
    local ped = PlayerPedId()
    if isDead and item ~= "iak_wheelchair" then
        Framework.Notify(_L("cannot_use_incapacitated"), "error")
        return
    end

    if item ~= "iak_wheelchair" and not HasInjuries() then
        if item == "plt_bandage" then
            Framework.Notify(_L("not_bleeding_now"), "info")
        else
            Framework.Notify(_L("no_injuries_to_treat"), "info")
        end
        return
    end

    if item == "plt_bandage" then
        TriggerEvent("amb_client:selfBandage")
        return
    end

    CreateThread(function()
        local label = _L("taking_medication")
        local time = 3000
        local dict = "mp_suicide"
        local anim = "pill"
        
        if item == "plt_medkit" then
            label = _L("applying_first_aid")
            time = 5000
            dict = "missheistprowlprepb"
            anim = "low_reach_loop"
        end

        Framework.RequestAnimDict(dict)
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, time, 49, 0, false, false, false)
        local success = Framework.ProgressBar(label, time)
        ClearPedTasks(ped)

        if not success then return end

        local healLevel = 1
        if item == "plt_painkillers_adv" then healLevel = 4
        elseif item == "plt_antibiotics" then healLevel = 2
        elseif item == "plt_medkit" then healLevel = 3 end

        local healed = false
        for _, data in pairs(InjuryData) do
            if type(data) == "table" and data.level and data.level > 0 then
                data.level = math.max(0, data.level - healLevel)
                if data.level == 0 then
                    data.bullet = false
                    data.bandaged = false
                end
                healed = true
            end
        end

        if InjuryData.bleeding > 0 then
            InjuryData.bleeding = 0
            healed = true
        end

        if GetEntityHealth(ped) < 200 then
            SetEntityHealth(ped, math.min(200, GetEntityHealth(ped) + (healLevel * 20)))
            healed = true
        end

        if healed then
            Framework.Notify(_L("injuries_feel_better"), "success")
            if item == "plt_medkit" then
                ClearPedBloodDamage(ped)
                ClearPedLastDamageBone(ped)
            end
            SyncInjuryData()
        end
    end)
end)

RegisterNetEvent("amb_client:selfBandage", function()
    local ped = PlayerPedId()
    if isDead then return end

    CreateThread(function()
        Framework.RequestAnimDict("missheistprowlprepb")
        TaskPlayAnim(ped, "missheistprowlprepb", "low_reach_loop", 8.0, -8.0, 3000, 49, 0, false, false, false)
        local success = Framework.ProgressBar(_L("applying_bandage"), 3000)
        ClearPedTasks(ped)

        if success then
            if InjuryData.bleeding > 0 then
                InjuryData.bleeding = 0
                Framework.Notify(_L("bleeding_stopped"), "success")
                SyncInjuryData()
            else
                Framework.Notify(_L("bandage_applied"), "info")
            end
        end
    end)
end)

-- ==========================================
-- Exports (Revive)
-- ==========================================

exports("RevivePlayer", function()
    if isDead then
        local ped = PlayerPedId()
        isDead = false
        timeOfLastRevive = GetGameTimer()
        
        ToggleDeathRestrictions(false)
        TriggerServerEvent("amb_server:SetDowned", false)
        TriggerEvent("amb_client:onPlayerRevive")
        TriggerEvent("amb_client:SetDownedState", false)
        SendNUIMessage({ action = "amb_toggleDeathScreen", show = false })

        ResetInjuries()
        if isBlurry then TriggerScreenblurFadeOut(500.0); isBlurry = false end
        if isLimping then ResetPedMovementClipset(ped, 0); isLimping = false end
        
        ClearPedBloodDamage(ped)
        ClearPedLastDamageBone(ped)
        ClearEntityLastDamageEntity(ped)
        
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
        
        ped = PlayerPedId()
        SetEntityHealth(ped, 200)
        RestoreClothesState()
        ClearPedTasksImmediately(ped)
    end
end)
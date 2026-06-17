local playerInjuries = {
    head = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    chest = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    left_arm = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    right_arm = { level = 0, bullet = false, bandaged = false, hunger = false, isFractured = false, fractureTime = 0 },
    left_leg = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    right_leg = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    bleeding = 0
}

local isPatientBandaged = false
local isDowned = false
local isAnimLoopRunning = false
local isLimping = false
local isScreenBlurred = false
local isRecentlyDamaged = false
local isCPRPlaying = false
local isReviving = false
local recentDamageTimer = 0
local deathAnimTimer = 0
local deathStateCount = 0
local deadAnimDict = "dead"
local deadAnimName = "dead_a"
local vehDeadAnimDict = "veh@low@front_ps@idle_duck"
local vehDeadAnimName = "sit"
local useDeathscreen = not Config.Deathscreen
local unconsciousHash = -1569615261

local savedClothing = {
    model = nil,
    top = nil,
    bottom = nil
}

local savedHealth = nil
local hasAppliedSavedHealth = false
local lastHealthCache = nil
local lastHealthCacheTime = 0
local restrictionsEnabled = false
local lastReviveTime = 0
local isVoiceMuted = false
local combatTimer = 0
local reviveRestrictTimer = 0
local isPhoneDisabled = false

local function SetReviveRestrictTimer(timeOffset)
    timeOffset = tonumber(timeOffset) or 0
    if timeOffset <= 0 then return end
    
    local newTime = GetGameTimer() + timeOffset
    if newTime > reviveRestrictTimer then
        reviveRestrictTimer = newTime
    end
end

local function IsReviveRestrictionExpired()
    if GetGameTimer() <= reviveRestrictTimer then
        reviveRestrictTimer = 0
        return true
    end
    return false
end

local function IsReviveRestricted()
    return GetGameTimer() <= reviveRestrictTimer
end

local function DisableNaturalHealthRegen()
    local playerId = PlayerId()
    SetPlayerHealthRechargeMultiplier(playerId, 0.0)
    SetPlayerHealthRechargeLimit(playerId, 0.0)
end

local function GetDeadRestrictions()
    local restrictions = Config.Health and Config.Health.DeadRestrictions
    if type(restrictions) ~= "table" then
        return { DisableVoice = false, DisableInventory = false }
    end
    
    return {
        DisableVoice = (restrictions.DisableVoice == true),
        DisableInventory = (restrictions.DisableInventory == true)
    }
end

local function ToggleVoice(disable)
    local restrictions = GetDeadRestrictions()
    if not restrictions.DisableVoice then
        disable = false
    end
    
    if disable == isVoiceMuted then return end
    
    local success = pcall(function()
        MumbleSetPlayerMuted(PlayerId(), disable)
    end)
    
    if success then
        isVoiceMuted = disable
    end
end

local function CloseInventories()
    TriggerEvent("inventory:client:closeInventory")
    TriggerEvent("qb-inventory:client:closeInventory")
    TriggerEvent("qs-inventory:client:closeInv")
    TriggerEvent("qs-inventory:client:closeInventory")
    TriggerEvent("origin_inventory:client:closeInventory")
    TriggerEvent("origen_inventory:client:closeInventory")
    
    if GetResourceState("ox_inventory") == "started" then
        pcall(function()
            exports.ox_inventory:closeInventory()
        end)
    end
end

local function ClosePhone()
    if GetResourceState("lb-phone") ~= "started" then return end
    
    pcall(function() exports["lb-phone"]:closePhone() end)
    pcall(function() exports["lb-phone"]:ClosePhone() end)
    pcall(function() exports["lb-phone"]:toggleOpen(false) end)
    pcall(function() exports["lb-phone"]:ToggleOpen(false) end)
    
    TriggerEvent("lb-phone:client:closePhone")
    TriggerEvent("lb-phone:closePhone")
end

local function TogglePhone(disable)
    disable = (disable == true)
    if disable == isPhoneDisabled then return end
    
    isPhoneDisabled = disable
    
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("phoneDisabled", disable, true)
        LocalPlayer.state:set("canUsePhone", not disable, true)
        LocalPlayer.state:set("lbPhoneDisabled", disable, true)
    end
    
    if GetResourceState("lb-phone") == "started" then
        pcall(function() exports["lb-phone"]:setPhoneDisabled(disable) end)
        pcall(function() exports["lb-phone"]:SetPhoneDisabled(disable) end)
        pcall(function() exports["lb-phone"]:setDisabled(disable) end)
        pcall(function() exports["lb-phone"]:SetDisabled(disable) end)
        TriggerEvent("lb-phone:client:setDisabled", disable)
        TriggerEvent("lb-phone:client:toggleDisabled", disable)
    end
    
    if disable then
        ClosePhone()
    end
end

local function ToggleInventory(disable)
    local restrictions = GetDeadRestrictions()
    if not restrictions.DisableInventory then
        disable = false
    end
    
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("dead", disable, true)
        LocalPlayer.state:set("invBusy", disable, true)
        LocalPlayer.state:set("invOpen", false, false)
        LocalPlayer.state:set("invHotkeys", not disable, false)
        LocalPlayer.state:set("canUseWeapons", not disable, false)
    end
    
    if disable then
        CloseInventories()
    end
end

local function ToggleDeathRestrictions(disable)
    ToggleVoice(disable)
    ToggleInventory(disable)
    TogglePhone(disable)
    restrictionsEnabled = disable
end

local function ClampHealth(health)
    health = tonumber(health)
    if not health then return nil end
    
    health = math.floor(health)
    if health < 100 then health = 100 end
    if health > 200 then health = 200 end
    return health
end

local function SetCombatTimer(duration)
    duration = tonumber(duration) or 0
    combatTimer = GetGameTimer() + math.max(0, duration)
end

local function IsCombatTimerActive()
    return GetGameTimer() < combatTimer
end

local function FetchSavedHealth()
    Framework.TriggerCallback("amb_server:getSavedHealth", function(healthData)
        local clampedHealth = ClampHealth(healthData)
        
        if Framework and Framework.Type == "qb" and clampedHealth and clampedHealth <= 110 then
            local serverId = GetPlayerServerId(PlayerId())
            Framework.TriggerCallback("amb_server:isPlayerDowned", function(isDownedServer)
                if isDownedServer == true then
                    savedHealth = clampedHealth
                else
                    savedHealth = nil
                end
                hasAppliedSavedHealth = false
            end, serverId)
            return
        end
        
        savedHealth = clampedHealth
        hasAppliedSavedHealth = false
    end)
end

local function ClearInjuries()
    isPatientBandaged = false
    for part, data in pairs(playerInjuries) do
        if type(data) == "table" then
            data.level = 0
            data.bullet = false
            data.bandaged = false
            if data.hunger ~= nil then
                data.hunger = false
            end
            data.needsFludro = false
            data.isFractured = false
            data.fractureTime = 0
        else
            playerInjuries[part] = 0
        end
    end
end

local function SyncInjuries()
    local injuryData = {}
    for part, data in pairs(playerInjuries) do
        injuryData[part] = data
    end
    injuryData.isPatientBandaged = isPatientBandaged
    TriggerServerEvent("amb_server:syncInjuryData", injuryData)
end

local function ApplySavedHealth()
    if hasAppliedSavedHealth or not savedHealth then return end
    
    local ped = PlayerPedId()
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then return end
    
    CreateThread(function()
        Wait(750)
        local ped = PlayerPedId()
        if not (ped and ped ~= 0 and DoesEntityExist(ped)) then return end
        
        SetEntityHealth(ped, savedHealth)
        hasAppliedSavedHealth = true
        lastHealthCache = savedHealth
    end)
end

local function GetClothingData(ped, componentId)
    local data = {}
    data.drawable = GetPedDrawableVariation(ped, componentId)
    data.texture = GetPedTextureVariation(ped, componentId)
    data.palette = GetPedPaletteVariation(ped, componentId)
    return data
end

local function SaveClothing(part)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end
    
    local currentModel = GetEntityModel(ped)
    if savedClothing.model ~= currentModel then
        savedClothing.model = currentModel
        savedClothing.top = nil
        savedClothing.bottom = nil
    end
    
    if part == "top" then
        if not savedClothing.top then
            local topData = {}
            topData.torso = GetClothingData(ped, 3)
            topData.undershirt = GetClothingData(ped, 8)
            topData.top = GetClothingData(ped, 11)
            savedClothing.top = topData
        end
    elseif part == "bottom" then
        if not savedClothing.bottom then
            savedClothing.bottom = GetClothingData(ped, 4)
        end
    end
end

local function RestoreClothing()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end
    
    if not savedClothing.top and not savedClothing.bottom then return end
    
    if savedClothing.model then
        if GetEntityModel(ped) ~= savedClothing.model then
            savedClothing.model = nil
            savedClothing.top = nil
            savedClothing.bottom = nil
            return
        end
    end
    
    if savedClothing.top then
        local top = savedClothing.top
        if top.torso then
            SetPedComponentVariation(ped, 3, top.torso.drawable, top.torso.texture or 0, top.torso.palette or 0)
        end
        if top.undershirt then
            SetPedComponentVariation(ped, 8, top.undershirt.drawable, top.undershirt.texture or 0, top.undershirt.palette or 0)
        end
        if top.top then
            SetPedComponentVariation(ped, 11, top.top.drawable, top.top.texture or 0, top.top.palette or 0)
        end
    end
    
    if savedClothing.bottom then
        local bottom = savedClothing.bottom
        SetPedComponentVariation(ped, 4, bottom.drawable, bottom.texture or 0, bottom.palette or 0)
    end
    
    savedClothing.model = nil
    savedClothing.top = nil
    savedClothing.bottom = nil
end

local function GetDeathType(causeHash)
    if causeHash == unconsciousHash then
        return "unconscious"
    end
    return "dead"
end

local function CheckDownedThreshold(ped, typeFlag)
    local threshold = 0
    if Config.Health and Config.Health.DownedThreshold then
        threshold = tonumber(Config.Health.DownedThreshold) or 0
    end
    
    local health = GetEntityHealth(ped)
    if threshold <= 0 then
        return typeFlag == 1
    end
    
    return typeFlag == 1 or threshold >= health
end

local function SetRecentDamageTimer(time)
    time = tonumber(time) or 0
    recentDamageTimer = GetGameTimer() + math.max(0, time)
    isRecentlyDamaged = (time > 0)
end

local function IsRecentlyDamaged()
    if isRecentlyDamaged then
        if GetGameTimer() >= recentDamageTimer then
            isRecentlyDamaged = false
        end
    end
    return isRecentlyDamaged
end

local function HealthLoopCheck(ped)
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then return end
    
    if not IsRecentlyDamaged() then return end
    
    if playerInjuries.bleeding and playerInjuries.bleeding > 0 then
        playerInjuries.bleeding = 0
    end
    
    local health = GetEntityHealth(ped)
    if health and health < 140 then
        SetEntityHealth(ped, 200)
    end
end

local FallAndImpactHashes = {
    [-1553120962] = true,
    [133987706] = true,
    [341774354] = true,
    [-868994466] = true,
    [148160082] = true
}

local function CheckFallOrImpactDamage(ped, causeHash, sourceEntity)
    local actualCause = GetPedCauseOfDeath(ped)
    local speed = GetEntitySpeed(ped) * 3.6
    local isFall = (causeHash == -1438083414 or actualCause == -1438083414)
    
    local isVeh = false
    if DoesEntityExist(sourceEntity) then
        isVeh = (sourceEntity and sourceEntity ~= 0 and IsEntityAVehicle(sourceEntity))
    end
    
    local isImpact = FallAndImpactHashes[causeHash] or FallAndImpactHashes[actualCause] or false
    
    return isFall, isImpact
end

local function ApplyFracture(part, reason)
    if not (part and playerInjuries[part]) then return false end
    if playerInjuries[part].isFractured then return false end
    
    local chance = Config.Health and Config.Health.FractureChance or 80
    if chance < math.random(1, 100) then return false end
    
    playerInjuries[part].isFractured = true
    playerInjuries[part].fractureTime = Config.Health and Config.Health.FractureTime or 600
    
    print(string.format("^1[FRACTURE] %s (%s)^7", part, tostring(reason or "impact")))
    return true
end

local BoneToPartMap = {
    [31086] = "head", [39317] = "head", [12844] = "head", [65068] = "head",
    [24816] = "chest", [24817] = "chest", [24818] = "chest", [10706] = "chest",
    [11816] = "chest", [57597] = "chest", [23553] = "chest",
    [64729] = "left_arm", [45509] = "left_arm", [61163] = "left_arm",
    [18905] = "left_arm", [26610] = "left_arm", [26611] = "left_arm",
    [40269] = "right_arm", [28252] = "right_arm", [57005] = "right_arm",
    [58866] = "right_arm", [58867] = "right_arm",
    [58271] = "left_leg", [63931] = "left_leg", [63923] = "left_leg",
    [2108] = "left_leg", [14201] = "left_leg",
    [51826] = "right_leg", [36864] = "right_leg", [52301] = "right_leg",
    [20781] = "right_leg", [35502] = "right_leg"
}

local function GetDamagedPart(ped)
    local success, bone = GetPedLastDamageBone(ped)
    if not (success and bone) or bone == 0 then
        Wait(0)
        success, bone = GetPedLastDamageBone(ped)
    end
    
    if success and bone then
        local part = BoneToPartMap[bone]
        if part then
            return part
        end
    end
    return "chest"
end

local lastInjuryCheckTime = GetGameTimer()

function GetInjuryType()
    if isDowned then return "fatal" end
    if playerInjuries.bleeding and playerInjuries.bleeding > 0 then return "severe" end
    
    local totalLevel = 0
    for _, data in pairs(playerInjuries) do
        if type(data) == "table" and data.level then
            totalLevel = totalLevel + data.level
        end
    end
    
    if totalLevel > 0 then return "minor" end
    return "minor"
end

exports("GetInjuryType", GetInjuryType)

CreateThread(function()
    while true do
        Wait(2000)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local health = ClampHealth(GetEntityHealth(ped))
            if health then
                local currentTime = GetGameTimer()
                local hasChanged = (lastHealthCache ~= health)
                local timePassed = (currentTime - lastHealthCacheTime) >= 10000
                
                if hasChanged or timePassed then
                    TriggerServerEvent("amb_server:cacheHealth", health)
                    lastHealthCache = health
                    lastHealthCacheTime = currentTime
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if isPhoneDisabled then
            if isDowned then
                if GetResourceState("lb-phone") == "started" then
                    ClosePhone()
                    Wait(750)
                end
            end
        else
            Wait(1500)
        end
    end
end)

RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
    SetCombatTimer(10000)
    DisableNaturalHealthRegen()
    FetchSavedHealth()
end)

RegisterNetEvent("amb_client:AuthorizeRevive", function(timeOffset)
    SetReviveRestrictTimer(timeOffset or 12000)
end)

RegisterNetEvent("esx:playerLoaded", function()
    SetCombatTimer(10000)
    DisableNaturalHealthRegen()
    FetchSavedHealth()
end)

AddEventHandler("playerSpawned", function()
    SetCombatTimer(10000)
    DisableNaturalHealthRegen()
    ApplySavedHealth()
end)

CreateThread(function()
    while true do
        DisableNaturalHealthRegen()
        Wait(5000)
    end
end)

local function ManageDeathControls()
    local playerId = PlayerId()
    local ped = PlayerPedId()
    
    if not IsPedInAnyVehicle(ped, false) then
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    end
    
    SetPlayerControl(playerId, true, 0)
    
    CreateThread(function()
        local count = 0
        while true do
            if not (isDowned and count < 120) then break end
            
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 73, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 44, true)
            
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 246, true)
            EnableControlAction(0, 47, true)
            
            SetPlayerControl(PlayerId(), true, 0)
            count = count + 1
            Wait(0)
        end
    end)
end

local function GetPedSeat(ped, vehicle)
    if not DoesEntityExist(vehicle) then return -1 end
    
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for i = -1, maxSeats - 2, 1 do
        if GetPedInVehicleSeat(vehicle, i) == ped then
            return i
        end
    end
    return -1
end

local function ResurrectPed(ped)
    local isDead = GetEntityHealth(ped) <= 0 or IsPedDeadOrDying(ped, true)
    
    if isDead then
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local inVeh = IsPedInAnyVehicle(ped, false)
        local vehicle = 0
        local seat = -1
        
        if inVeh then
            vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle then
                seat = GetPedSeat(ped, vehicle)
            end
        end
        
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
        Wait(0)
        ped = PlayerPedId()
        
        if inVeh and vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetPedIntoVehicle(ped, vehicle, seat)
        else
            SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(ped, heading)
        end
        
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
        
        if not inVeh then
            SetPedCanRagdoll(ped, true)
            SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
        end
    else
        if not IsPedInAnyVehicle(ped, false) then
            SetPedCanRagdoll(ped, true)
            SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
        end
    end
    
    return ped
end

local function WaitForRagdollStop()
    Wait(1000)
    local count = 0
    local ped = PlayerPedId()
    
    while count < 250 do
        if GetEntitySpeed(ped) <= 0.5 and not IsPedRagdoll(ped) then break end
        Wait(10)
        count = count + 1
        ped = PlayerPedId()
    end
end

local function IsQBCore()
    return Framework and Framework.Type == "qb"
end

local function CheckFrameworkQB()
    return Framework and Framework.Type == "qb"
end

local function CheckAndApplyBaselineTrauma()
    local totalLevel = 0
    for _, data in pairs(playerInjuries) do
        if type(data) == "table" and data.level then
            totalLevel = totalLevel + data.level
        end
    end
    
    if totalLevel == 0 then
        playerInjuries.chest.level = 2
    end
end

local function PlayDownedAnimation(ped)
    if IsPedInAnyVehicle(ped, false) then
        if not HasAnimDictLoaded(vehDeadAnimDict) then
            Framework.RequestAnimDict(vehDeadAnimDict)
        end
        if not IsEntityPlayingAnim(ped, vehDeadAnimDict, vehDeadAnimName, 3) then
            TaskPlayAnim(ped, vehDeadAnimDict, vehDeadAnimName, 1.0, 1.0, -1, 1, 0.0, false, false, false)
        end
        return
    end
    
    if not HasAnimDictLoaded(deadAnimDict) then
        Framework.RequestAnimDict(deadAnimDict)
    end
    if not IsEntityPlayingAnim(ped, deadAnimDict, deadAnimName, 3) then
        TaskPlayAnim(ped, deadAnimDict, deadAnimName, 1.0, 1.0, -1, 1, 0.0, false, false, false)
    end
end

local function SetPlayerDowned(causeHash)
    if not CheckFrameworkQB() then return false end
    if isDowned then return false end
    if not IsRecentlyDamaged() then return false end
    
    local ped = PlayerPedId()
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then return false end
    
    isDowned = true
    deathStateCount = deathStateCount + 1
    local currentDeathId = deathStateCount
    
    isAnimLoopRunning = true
    GetInjuryType()
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "demo", 0.1)
    
    CreateThread(function()
        Wait(1000)
        local ped = PlayerPedId()
        local count = 0
        
        while isDowned and currentDeathId == deathStateCount and count < 250 do
            if GetEntitySpeed(ped) <= 0.5 and not IsPedRagdoll(ped) then break end
            Wait(10)
            count = count + 1
            ped = PlayerPedId()
        end
        
        if not (isDowned and currentDeathId == deathStateCount and IsRecentlyDamaged()) then return end
        
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local inVeh = IsPedInAnyVehicle(ped, false)
        local vehicle = 0
        
        if inVeh then
            vehicle = GetVehiclePedIsIn(ped, false)
        end
        
        local seat = -1
        if inVeh and vehicle then
            seat = GetPedSeat(ped, vehicle)
        end
        
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z + 0.5, heading, true, false)
        Wait(0)
        
        ped = PlayerPedId()
        
        if inVeh and vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetPedIntoVehicle(ped, vehicle, seat)
        else
            SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(ped, heading)
        end
        
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetEntityInvincible(ped, true)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
        SetPedCanRagdoll(ped, false)
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        
        ToggleDeathRestrictions(true)
        PlayDownedAnimation(ped)
        CheckAndApplyBaselineTrauma()
        
        TriggerServerEvent("amb_server:SetDowned", true)
        TriggerEvent("amb_client:onPlayerDeath", GetDeathType(causeHash))
    end)
    
    return true
end

CreateThread(function()
    Wait(1500)
    if CheckFrameworkQB() then
        if GetResourceState("qb-ambulancejob") == "started" then
            print("^1[plt_ambulance] QBCore mode detected while qb-ambulancejob is running. Disable one death system to prevent conflicts.^7")
        end
    end
end)

CreateThread(function()
    local timerOffset = 0
    local loopCount = 0
    local animTimer = 0
    
    while true do
        local ped = PlayerPedId()
        local currentTime = GetGameTimer()
        
        HealthLoopCheck(ped)
        
        if not isDowned then
            if (GetGameTimer() - lastInjuryCheckTime) >= 1000 then
                lastInjuryCheckTime = GetGameTimer()
                
                for part, data in pairs(playerInjuries) do
                    if type(data) == "table" and data.isFractured then
                        if data.fractureTime > 0 then
                            data.fractureTime = data.fractureTime - 1
                        else
                            data.isFractured = false
                            TriggerEvent("amb_client:Notify", _L("fracture_healed", { part = part:gsub("_", " "):upper() }), "success")
                        end
                    end
                end
                
                local leftLegFrac = playerInjuries.left_leg.isFractured
                local rightLegFrac = playerInjuries.right_leg.isFractured
                local leftLegLevel = playerInjuries.left_leg.level
                local rightLegLevel = playerInjuries.right_leg.level
                
                if leftLegLevel > 0 or rightLegLevel > 0 or leftLegFrac or rightLegFrac then
                    DisableControlAction(0, 21, true)
                    if not isLimping then
                        Framework.RequestAnimSet("move_m@limping@a")
                        SetPedMovementClipset(ped, "move_m@limping@a", 1.0)
                        isLimping = true
                    end
                else
                    if isLimping then
                        ResetPedMovementClipset(ped, 0)
                        isLimping = false
                    end
                end
                
                local leftArmFrac = playerInjuries.left_arm.isFractured
                local rightArmFrac = playerInjuries.right_arm.isFractured
                
                if leftArmFrac or rightArmFrac then
                    DisableControlAction(0, 21, true)
                end
                
                local leftArmLevel = playerInjuries.left_arm.level
                local rightArmLevel = playerInjuries.right_arm.level
                
                if leftArmLevel > 0 or rightArmLevel > 0 or leftArmFrac or rightArmFrac then
                    if IsControlPressed(0, 25) then
                        local shakeLevel = (leftArmLevel + rightArmLevel) * 0.5
                        if leftArmFrac or rightArmFrac then
                            shakeLevel = shakeLevel + 1.5
                        end
                        ShakeGameplayCam("HAND_SHAKE", shakeLevel)
                    end
                end
                
                if playerInjuries.head.level > 0 then
                    if Config.EnableBlurEffect ~= false then
                        if not isScreenBlurred then
                            TriggerScreenblurFadeIn(1000.0)
                            isScreenBlurred = true
                        end
                    end
                else
                    if isScreenBlurred then
                        TriggerScreenblurFadeOut(1000.0)
                        isScreenBlurred = false
                    end
                end
                
                if playerInjuries.bleeding > 0 then
                    local interval = Config.Health and Config.Health.BleedInterval or 2000
                    local rate = Config.Health and Config.Health.BleedRate or 1
                    
                    local damage = rate * playerInjuries.bleeding
                    SetEntityHealth(ped, GetEntityHealth(ped) - damage)
                    
                    local minDecal = Config.Health and Config.Health.BleedDecalMin or 2
                    if playerInjuries.bleeding > minDecal then
                        local coords = GetEntityCoords(ped)
                        AddDecal(1010, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.2, 0.2, 255, 0, 0, 255, 60.0, false, false, false)
                    end
                end
            end
        else
            local restrictChance = useDeathscreen and 40 or 0
            if not restrictionsEnabled then
                ToggleDeathRestrictions(true)
            end
            
            if loopCount <= currentTime then
                if CheckFrameworkQB() then
                    local maxHealth = GetEntityMaxHealth(ped)
                    if GetEntityHealth(ped) ~= maxHealth then
                        SetEntityHealth(ped, maxHealth)
                    end
                else
                    if GetEntityHealth(ped) ~= 100 then
                        SetEntityHealth(ped, 100)
                    end
                end
                
                SetEntityInvincible(ped, true)
                if CheckFrameworkQB() then
                    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
                else
                    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
                end
                timerOffset = currentTime + 500
            end
            
            if animTimer <= currentTime then
                if not IsPedInAnyVehicle(ped, false) then
                    if not HasAnimDictLoaded(deadAnimDict) then
                        Framework.RequestAnimDict(deadAnimDict)
                    end
                else
                    if not HasAnimDictLoaded(vehDeadAnimDict) then
                        Framework.RequestAnimDict(vehDeadAnimDict)
                    end
                end
                animTimer = currentTime + 1500
            end
            
            if isDowned then
                if not isCPRPlaying and deathAnimTimer <= currentTime then
                    if CheckFrameworkQB() then
                        deathAnimTimer = currentTime + 500
                        SetPedCanRagdoll(ped, false)
                        SetPedCanRagdollFromPlayerImpact(ped, false)
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        PlayDownedAnimation(ped)
                    else
                        deathAnimTimer = currentTime + 200
                        if currentTime < deathAnimTimer then
                            SetPedCanRagdoll(ped, true)
                            if not IsPedRagdoll(ped) then
                                SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false)
                            end
                        else
                            if not IsPlayerControlOn(PlayerId()) then
                                SetPlayerControl(PlayerId(), true, 0)
                            end
                            SetPedCanRagdoll(ped, false)
                            SetPedCanRagdollFromPlayerImpact(ped, false)
                            SetEntityVelocity(ped, 0.0, 0.0, 0.0)
                            SetBlockingOfNonTemporaryEvents(ped, true)
                            
                            if IsPedInAnyVehicle(ped, false) then
                                if not IsEntityPlayingAnim(ped, vehDeadAnimDict, vehDeadAnimName, 3) then
                                    ClearPedTasksImmediately(ped)
                                    TaskPlayAnim(ped, vehDeadAnimDict, vehDeadAnimName, 1.0, 1.0, -1, 1, 0.0, false, false, false)
                                end
                            else
                                if not IsEntityPlayingAnim(ped, deadAnimDict, deadAnimName, 3) then
                                    if not IsPedGettingUp(ped) and not IsPedRagdoll(ped) then
                                        ClearPedTasksImmediately(ped)
                                        TaskPlayAnim(ped, deadAnimDict, deadAnimName, 8.0, 8.0, -1, 1, 0.0, false, false, false)
                                    end
                                end
                            end
                            
                            if not isAnimLoopRunning then
                                isAnimLoopRunning = true
                                SetPedConfigFlag(ped, 184, true)
                                SetPedConfigFlag(ped, 241, true)
                            end
                        end
                    end
                end
            end
            
            if not useDeathscreen then
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 73, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 23, true)
                DisableControlAction(0, 38, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 75, true)
                DisableControlAction(0, 59, true)
                DisableControlAction(0, 60, true)
                DisableControlAction(0, 61, true)
                DisableControlAction(0, 62, true)
                DisableControlAction(0, 63, true)
                DisableControlAction(0, 64, true)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
                DisableControlAction(0, 76, true)
                DisableControlAction(0, 85, true)
                DisableControlAction(0, 86, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 257, true)
                
                if GetDeadRestrictions().DisableInventory then
                    DisableControlAction(0, 37, true)
                end
                
                EnableControlAction(0, 1, true)
                EnableControlAction(0, 2, true)
                EnableControlAction(0, 3, true)
                EnableControlAction(0, 4, true)
                EnableControlAction(0, 245, true)
                EnableControlAction(0, 246, true)
                EnableControlAction(0, 47, true)
                
                if not IsPlayerControlOn(PlayerId()) then
                    SetPlayerControl(PlayerId(), true, 0)
                end
                
                if IsPedInAnyVehicle(ped, false) then
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                        SetVehicleUndriveable(vehicle, true)
                        SetVehicleEngineOn(vehicle, false, true, false)
                        SetVehicleForwardSpeed(vehicle, 0.0)
                        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
                    end
                end
            end
        end
        Wait(1000)
    end
end)

AddEventHandler("gameEventTriggered", function(eventName, args)
    if eventName == "CEventNetworkEntityDamage" then
        local victim = args[1]
        local culprit = args[6]
        local isFatal = args[2]
        local weaponHash = args[7]
        local ped = PlayerPedId()
        
        if victim == ped then
            if not IsRecentlyDamaged() then
                if IsCombatTimerActive() then return end
                
                if isDowned then
                    if CheckFrameworkQB() then
                        SetEntityHealth(victim, GetEntityMaxHealth(victim))
                    else
                        SetEntityHealth(victim, 100)
                    end
                    SetEntityInvincible(victim, true)
                    
                    if CheckFrameworkQB() then
                        PlayDownedAnimation(victim)
                        return
                    end
                    
                    if GetGameTimer() >= deathAnimTimer then
                        if not isCPRPlaying then
                            SetEntityVelocity(victim, 0.0, 0.0, 0.0)
                            if not IsPedInAnyVehicle(victim, false) then
                                if not IsEntityPlayingAnim(victim, deadAnimDict, deadAnimName, 3) then
                                    ClearPedTasksImmediately(victim)
                                    TaskPlayAnim(victim, deadAnimDict, deadAnimName, 1.0, 1.0, -1, 1, 0.0, false, false, false)
                                end
                            else
                                if not IsEntityPlayingAnim(victim, vehDeadAnimDict, vehDeadAnimName, 3) then
                                    ClearPedTasksImmediately(victim)
                                    TaskPlayAnim(victim, vehDeadAnimDict, vehDeadAnimName, 1.0, 1.0, -1, 1, 0.0, false, false, false)
                                end
                            end
                        end
                    end
                    return
                end
                
                local damagedPart = GetDamagedPart(victim)
                if damagedPart then
                    local maxInjLevel = Config.Health and Config.Health.MaxInjuryLevel or 5
                    playerInjuries[damagedPart].level = math.min(maxInjLevel, playerInjuries[damagedPart].level + 1)
                    
                    local isFall, isImpact = CheckFallOrImpactDamage(victim, weaponHash, culprit)
                    
                    if isFall or isImpact then
                        local parts = {"left_leg", "right_leg", "left_arm", "right_arm"}
                        local randPart = parts[math.random(1, #parts)]
                        
                        if isFall then
                            if math.random(1, 100) > 20 then
                                local randLeg = math.random(1, 2)
                                if randLeg == 1 then randPart = "left_leg" else randPart = "right_leg" end
                            else
                                local randArm = math.random(1, 2)
                                if randArm == 1 then randPart = "left_arm" else randPart = "right_arm" end
                            end
                            
                            local applied = ApplyFracture(randPart, isFall and "downed_fall" or "downed_vehicle")
                            if not applied then
                                ApplyFracture(damagedPart, "fall_fallback")
                            end
                        else
                            ApplyFracture(damagedPart, "vehicle")
                        end
                    end
                    
                    local wGroup = GetWeapontypeGroup(culprit)
                    local isBullet = (wGroup == 416676503 or wGroup == -95745345 or wGroup == 860033945 or wGroup == 970310034)
                    
                    if isBullet then
                        playerInjuries[damagedPart].bullet = true
                    end
                    
                    local bleedChance = 90
                    if isBullet and Config.Health and Config.Health.BulletBleedChance then
                        bleedChance = Config.Health.BulletBleedChance
                    elseif Config.Health and Config.Health.BleedChance then
                        bleedChance = Config.Health.BleedChance
                    else
                        bleedChance = 40
                    end
                    
                    if bleedChance > math.random(1, 100) then
                        playerInjuries.bleeding = playerInjuries.bleeding + 1
                    end
                    
                    local syncData = {}
                    for k, v in pairs(playerInjuries) do syncData[k] = v end
                    syncData.isPatientBandaged = isPatientBandaged
                    TriggerServerEvent("amb_server:syncInjuryData", syncData)
                end
                
                if CheckDownedThreshold(victim, isFatal) then
                    if not isDowned then
                        if SetPlayerDowned(weaponHash) then return end
                        
                        isDowned = true
                        deathStateCount = deathStateCount + 1
                        local curDeathId = deathStateCount
                        
                        deathAnimTimer = GetGameTimer() + 1000
                        GetInjuryType()
                        
                        if not IsPedInAnyVehicle(victim, false) then
                            if IsQBCore() then
                                ResurrectPed(victim)
                            else
                                WaitForRagdollStop()
                                if isDowned and curDeathId == deathStateCount and IsRecentlyDamaged() then
                                    ResurrectPed(victim)
                                end
                            end
                        end
                        
                        if not (isDowned and curDeathId == deathStateCount and IsRecentlyDamaged()) then return end
                        
                        local isFall, isImpact = CheckFallOrImpactDamage(victim, weaponHash, culprit)
                        if isFall or isImpact then
                            local parts = {"left_leg", "right_leg", "left_arm", "right_arm"}
                            local randPart = parts[math.random(1, #parts)]
                            
                            if isFall then
                                if math.random(1, 100) > 20 then
                                    local rLeg = math.random(1, 2)
                                    if rLeg == 1 then randPart = "left_leg" else randPart = "right_leg" end
                                else
                                    local rArm = math.random(1, 2)
                                    if rArm == 1 then randPart = "left_arm" else randPart = "right_arm" end
                                end
                            end
                            ApplyFracture(randPart, isFall and "fallback_fall" or "fallback_vehicle")
                        end
                        
                        SetEntityHealth(victim, 100)
                        SetEntityInvincible(victim, true)
                        TriggerServerEvent("amb_server:SetDowned", true)
                        
                        local totalLvl = 0
                        for _, v in pairs(playerInjuries) do
                            if type(v) == "table" and v.level then
                                totalLvl = totalLvl + v.level
                            end
                        end
                        
                        if totalLvl == 0 then
                            playerInjuries.chest.level = 2
                            print("^3[HEALTH FALLBACK]^7 Forced downed state from fallback detector.")
                        end
                        
                        local cause = GetPedCauseOfDeath(ped)
                        local fallFall, fallImpact = CheckFallOrImpactDamage(ped, cause, 0)
                        
                        if fallFall or fallImpact then
                            local fallbackParts = {"left_leg", "right_leg", "left_arm", "right_arm"}
                            local fPart = fallbackParts[math.random(1, #fallbackParts)]
                            
                            if fallFall then
                                if math.random(1, 100) > 20 then
                                    fPart = (math.random(1, 2) == 1) and "left_leg" or "right_leg"
                                else
                                    fPart = (math.random(1, 2) == 1) and "left_arm" or "right_arm"
                                end
                            end
                            ApplyFracture(fPart, fallFall and "fallback_fall" or "fallback_vehicle")
                        end
                        
                        local deathType = (isFatal == unconsciousHash) and "unconscious" or "dead"
                        TriggerEvent("amb_client:onPlayerDeath", deathType)
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if isRecentlyDamaged then
            if GetGameTimer() > (recentDamageTimer + 2000) then
                SetRecentDamageTimer(0)
            end
        end
        if isReviving then
            if not isDowned and not IsRecentlyDamaged() then
                isReviving = false
            end
        end
    end
end)

exports("RevivePlayer", function()
    if CheckFrameworkQB() and not IsReviveRestrictionExpired() then return end
    if isReviving then return end
    
    local ped = PlayerPedId()
    local playerId = PlayerId()
    
    if not isDowned then
        if GetEntityHealth(ped) >= 200 then
            local needsHeal = false
            for _, data in pairs(playerInjuries) do
                if type(data) == "table" and data.level > 0 then
                    needsHeal = true
                    break
                end
            end
            if not needsHeal and not isPatientBandaged then
                return
            end
        end
    end
    
    isReviving = true
    lastReviveTime = GetGameTimer()
    isDowned = false
    ToggleDeathRestrictions(false)
    deathStateCount = deathStateCount + 1
    isAnimLoopRunning = false
    deathAnimTimer = 0
    SetRecentDamageTimer(8000)
    isCPRPlaying = false
    TriggerServerEvent("amb_server:SetDowned", false)
    TriggerEvent("amb_client:onPlayerRevive")
    TriggerEvent("amb_client:SetDownedState", false)
    SendNUIMessage({ action = "amb_toggleDeathScreen", show = false })
    SetPedComponentVariation(ped, 7, 0, 0, 0)
    ClearInjuries()
    playerInjuries.bleeding = 0
    
    if isScreenBlurred then
        TriggerScreenblurFadeOut(500.0)
        isScreenBlurred = false
    end
    
    if isLimping then
        ResetPedMovementClipset(ped, 0)
        isLimping = false
    end
    
    ClearPedBloodDamage(ped)
    ClearPedLastDamageBone(ped)
    ClearEntityLastDamageEntity(ped)
    
    local inVeh = IsPedInAnyVehicle(ped, false)
    local vehicle = 0
    if inVeh then
        vehicle = GetVehiclePedIsIn(ped, false)
    end
    
    if GetEntityHealth(ped) <= 5 or IsPedDeadOrDying(ped, 1) or IsEntityPlayingAnim(ped, deadAnimDict, deadAnimName, 3) or IsEntityPlayingAnim(ped, "misslamar1dead_body", "dead_idle", 3) then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        Wait(100)
        ped = PlayerPedId()
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
    end
    
    RestoreClothing()
    DetachEntity(ped, true, true)
    SetEntityHealth(ped, 200)
    SetEntityInvincible(ped, false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetPedCanRagdoll(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetPlayerControl(playerId, true, 0)
    SetPedToRagdoll(ped, 0, 0, 0, false, false, false)
    
    if not isDowned then
        ClearPedTasksImmediately(ped)
        local c = GetEntityCoords(ped)
        SetEntityCoords(ped, c.x, c.y, c.z + 0.1, false, false, false, false)
    else
        StopAnimTask(ped, vehDeadAnimDict, vehDeadAnimName, 1.0)
        StopAnimTask(ped, deadAnimDict, deadAnimName, 1.0)
        StopAnimTask(ped, "misslamar1dead_body", "dead_idle", 1.0)
        ClearPedSecondaryTask(ped)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleUndriveable(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
        end
    end
    
    EnableAllControlActions(0)
    SetPedConfigFlag(ped, 184, false)
    SetPedConfigFlag(ped, 241, false)
    
    CreateThread(function()
        local count = 0
        while count < 120 do
            Wait(10)
            if isDowned then break end
            
            local ped = PlayerPedId()
            HealthLoopCheck(ped)
            if GetEntityHealth(ped) < 120 then
                SetEntityHealth(ped, 200)
            end
            
            EnableAllControlActions(0)
            SetPlayerControl(PlayerId(), true, 0)
            FreezeEntityPosition(ped, false)
            SetEntityInvincible(ped, false)
            count = count + 1
        end
        SetRecentDamageTimer(0)
        isReviving = false
    end)
end)

RegisterNetEvent("hospital:client:Revive", function()
    if CheckFrameworkQB() then return end
    exports.plt_ambulance_job:RevivePlayer()
end)

RegisterNetEvent("amb_client:RevivePlayer", function()
    exports.plt_ambulance_job:RevivePlayer()
end)

local function HealInjuries(isMedicAction)
    local ped = PlayerPedId()
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then return end
    
    if not isDowned then
        if not IsPedDeadOrDying(ped, true) and GetEntityHealth(ped) > 110 then
            exports.plt_ambulance_job:RevivePlayer()
            TriggerServerEvent("amb_server:cacheHealth", GetEntityHealth(PlayerPedId()))
            SyncInjuries()
            Framework.Notify(_L("healed"), "success")
            return
        end
    end
    
    isDowned = false
    ToggleDeathRestrictions(false)
    deathStateCount = deathStateCount + 1
    isAnimLoopRunning = false
    deathAnimTimer = 0
    isCPRPlaying = false
    ClearInjuries()
    
    DetachEntity(ped, true, true)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetEntityInvincible(ped, false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    EnableAllControlActions(0)
    FreezeEntityPosition(ped, false)
    ClearPedBloodDamage(ped)
    ClearPedLastDamageBone(ped)
    ClearEntityLastDamageEntity(ped)
    RestoreClothing()
    
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleUndriveable(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
        end
    end
    
    if isScreenBlurred then
        TriggerScreenblurFadeOut(500.0)
        isScreenBlurred = false
    end
    
    if isLimping then
        ResetPedMovementClipset(ped, 0)
        isLimping = false
    end
    
    TriggerServerEvent("amb_server:SetDowned", false)
    TriggerServerEvent("amb_server:cacheHealth", GetEntityHealth(ped))
    SyncInjuries()
    Framework.Notify(_L("healed"), "success")
end

RegisterNetEvent("amb_client:HealInjuries", HealInjuries)
RegisterNetEvent("hospital:client:HealInjuries", HealInjuries)

RegisterNetEvent("hospital:client:SetDeathStatus", function(status)
    if CheckFrameworkQB() then return end
    HealInjuries(status)
end)

RegisterNetEvent("amb_client:SetDeathStatus", HealInjuries)

RegisterNetEvent("amb_client:KillPlayer", function()
    if isDowned then return end
    
    local ped = PlayerPedId()
    if not (ped and ped ~= 0 and DoesEntityExist(ped)) then return end
    
    isReviving = false
    SetRecentDamageTimer(0)
    
    if CheckFrameworkQB() then
        playerInjuries.bleeding = math.max(tonumber(playerInjuries.bleeding) or 0, 1)
        CheckAndApplyBaselineTrauma()
        SetEntityHealth(ped, 0)
        SetPlayerDowned(0)
        TriggerServerEvent("amb_server:cacheHealth", 100)
        SyncInjuries()
        return
    end
    
    isDowned = true
    deathStateCount = deathStateCount + 1
    deathAnimTimer = GetGameTimer() + 1000
    GetInjuryType()
    SetEntityHealth(ped, 0)
    
    if not IsPedInAnyVehicle(ped, false) then
        if IsQBCore() then
            ResurrectPed(ped)
        else
            WaitForRagdollStop()
            if isDowned and deathStateCount == deathStateCount then
                ResurrectPed(ped)
            end
        end
    end
    
    if not (isDowned and deathStateCount == deathStateCount) then return end
    
    local totalLvl = 0
    for _, v in pairs(playerInjuries) do
        if type(v) == "table" and v.level then
            totalLvl = totalLvl + v.level
        end
    end
    
    if totalLvl == 0 then
        playerInjuries.chest.level = 2
    end
    
    playerInjuries.bleeding = math.max(tonumber(playerInjuries.bleeding) or 0, 1)
    SetEntityHealth(ped, 100)
    SetEntityInvincible(ped, true)
    TriggerServerEvent("amb_server:SetDowned", true)
    TriggerServerEvent("amb_server:cacheHealth", 100)
    SyncInjuries()
    TriggerEvent("amb_client:onPlayerDeath", "dead")
end)

RegisterNetEvent("amb_client:requestInjuryData", function()
    print("^3[VICTIM DEBUG] Sending Injury Data to EMS...^7")
    local syncData = {}
    for k, v in pairs(playerInjuries) do syncData[k] = v end
    syncData.isPatientBandaged = isPatientBandaged
    TriggerServerEvent("amb_server:syncInjuryData", syncData)
end)

local validMedications = {
    plt_bandage = true,
    plt_painkillers = true,
    plt_painkillers_adv = true,
    plt_antibiotics = true,
    plt_medkit = true,
    iak_wheelchair = true
}

local function HasTreatableInjuries()
    if playerInjuries.bleeding and playerInjuries.bleeding > 0 then return true end
    
    for _, data in pairs(playerInjuries) do
        if type(data) == "table" then
            if data.level and data.level > 0 then return true end
            if data.bullet or data.isFractured then return true end
        end
    end
    
    return GetEntityHealth(PlayerPedId()) < 200
end

local function CanUseMedication(item)
    if item == "iak_wheelchair" then return true end
    if isDowned then return false end
    return HasTreatableInjuries()
end

exports("plt_use_medication", function(itemData, slot)
    local itemName = itemData and itemData.name or nil
    if not itemName or not validMedications[itemName] then return end
    
    if isDowned and itemName ~= "iak_wheelchair" then
        Framework.Notify(_L("cannot_use_incapacitated"), "error")
        return
    end
    
    if not CanUseMedication(itemName) then
        if itemName == "plt_bandage" then
            Framework.Notify(_L("not_bleeding_now"), "info")
        else
            Framework.Notify(_L("no_injuries_to_treat"), "info")
        end
        return
    end
    
    if itemName == "iak_wheelchair" then
        local duration = itemData and itemData.metadata and itemData.metadata.duration or nil
        TriggerEvent("amb_client:useWheelchair", duration)
        TriggerServerEvent("amb_server:consumeMedication", itemName, slot, true)
        return
    end
    
    if GetResourceState("ox_inventory") ~= "started" then
        TriggerEvent("amb_client:useMedication", itemName)
        return
    end
    
    TriggerServerEvent("amb_server:consumeMedication", itemName, slot, true)
end)

RegisterNetEvent("amb_client:useMedication", function(itemName, metadata)
    local ped = PlayerPedId()
    
    if isDowned and itemName ~= "iak_wheelchair" then
        Framework.Notify(_L("cannot_use_incapacitated"), "error")
        return
    end
    
    if not CanUseMedication(itemName) then
        if itemName == "plt_bandage" then
            Framework.Notify(_L("not_bleeding_now"), "info")
        else
            Framework.Notify(_L("no_injuries_to_treat"), "info")
        end
        return
    end
    
    if itemName == "plt_bandage" then
        TriggerEvent("amb_client:selfBandage")
        return
    end
    
    CreateThread(function()
        local label = _L("taking_medication")
        local time = 3000
        local dict = "mp_suicide"
        local anim = "pill"
        
        if itemName == "plt_medkit" then
            label = _L("applying_first_aid")
            time = 5000
            dict = "missheistprowlprepb"
            anim = "low_reach_loop"
        end
        
        Framework.Notify(label, "primary")
        Framework.RequestAnimDict(dict)
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, time, 49, 0, false, false, false)
        
        local success = Framework.ProgressBar(label, time)
        ClearPedTasks(ped)
        
        if not success then
            Framework.Notify("Cancelled", "error")
            return
        end
        
        local healAmount = 1
        local injuryReduction = 5
        
        if itemName == "plt_painkillers" then
            healAmount = 1
            injuryReduction = 1
        elseif itemName == "plt_painkillers_adv" then
            healAmount = 4
            injuryReduction = 5
        elseif itemName == "plt_antibiotics" then
            healAmount = 2
            injuryReduction = 5
        elseif itemName == "plt_medkit" then
            healAmount = 3
            injuryReduction = 5
        end
        
        if itemName == "iak_wheelchair" then
            local duration = metadata and metadata.duration
            if not duration then
                local pData = Framework.GetPlayerData()
                if pData and pData.items then
                    for _, item in pairs(pData.items) do
                        if item.name == itemName then
                            local meta = item.info or item.metadata
                            if meta and meta.duration then
                                duration = meta.duration
                            end
                            break
                        end
                    end
                end
            end
            TriggerEvent("amb_client:useWheelchair", duration)
            return
        end
        
        local healedAny = false
        
        for part, data in pairs(playerInjuries) do
            if type(data) == "table" and data.level and data.level > 0 then
                if healAmount >= data.level then
                    data.level = math.max(0, data.level - injuryReduction)
                    if data.level == 0 then
                        data.bullet = false
                        data.bandaged = false
                    end
                    healedAny = true
                else
                    healedAny = true
                end
            end
        end
        
        if playerInjuries.bleeding and playerInjuries.bleeding > 0 then
            playerInjuries.bleeding = 0
            healedAny = true
        end
        
        local health = GetEntityHealth(ped)
        if health < 200 then
            SetEntityHealth(ped, math.min(200, health + (injuryReduction * 20)))
            healedAny = true
        end
        
        if healedAny then
            Framework.Notify(_L("injuries_feel_better"), "success")
            
            if itemName == "plt_medkit" then
                ClearPedBloodDamage(ped)
                ClearPedLastDamageBone(ped)
            end
            
            local syncData = {}
            for k, v in pairs(playerInjuries) do syncData[k] = v end
            syncData.isPatientBandaged = isPatientBandaged
            TriggerServerEvent("amb_server:syncInjuryData", syncData)
        else
            if itemName == "plt_painkillers" then
                Framework.Notify(_L("otc_too_weak"), "error")
            end
        end
    end)
end)

RegisterNetEvent("amb_client:HealPart", function(part, amount)
    if playerInjuries[part] then
        if type(playerInjuries[part]) == "table" then
            playerInjuries[part].level = math.max(0, playerInjuries[part].level - amount)
            if amount >= 2 then
                playerInjuries[part].bullet = false
            end
            
            if playerInjuries[part].level == 0 then
                playerInjuries[part].bullet = false
                TriggerEvent("amb_client:Notify", _L("body_part_treated", { part = part:gsub("_", " "):upper() }), "success")
            end
        else
            playerInjuries[part] = math.max(0, playerInjuries[part] - amount)
            if playerInjuries[part] == 0 then
                TriggerEvent("amb_client:Notify", _L("body_part_treated", { part = part:gsub("_", " "):upper() }), "success")
            end
        end
        
        local syncData = {}
        for k, v in pairs(playerInjuries) do syncData[k] = v end
        syncData.isPatientBandaged = isPatientBandaged
        TriggerServerEvent("amb_server:syncInjuryData", syncData)
    end
end)

RegisterNetEvent("amb_client:removeClothes", function(part)
    local ped = PlayerPedId()
    SaveClothing(part)
    
    local isMpMale = (GetEntityModel(ped) == -1667301416)
    
    if part == "top" then
        if isMpMale then
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            SetPedComponentVariation(ped, 8, 34, 0, 0)
            SetPedComponentVariation(ped, 3, 15, 0, 0)
        else
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            SetPedComponentVariation(ped, 8, 15, 0, 0)
            SetPedComponentVariation(ped, 3, 15, 0, 0)
        end
    elseif part == "bottom" then
        if isMpMale then
            SetPedComponentVariation(ped, 4, 15, 0, 0)
        else
            SetPedComponentVariation(ped, 4, 21, 0, 0)
        end
    end
    
    TriggerEvent("amb_client:requestInjuryData")
end)

RegisterNetEvent("amb_client:updateHungerWorkflow", function()
    playerInjuries.right_arm.level = 0
    playerInjuries.right_arm.hunger = false
    playerInjuries.head.level = 1
    playerInjuries.head.needsFludro = true
    TriggerEvent("amb_client:Notify", _L("vitals_stabilized_fludro"), "info")
    TriggerEvent("amb_client:requestInjuryData")
end)

RegisterNetEvent("amb_client:giveFludro", function()
    playerInjuries.head.level = 0
    playerInjuries.head.needsFludro = false
    TriggerEvent("amb_client:Notify", _L("fludro_given"), "success")
    TriggerEvent("amb_client:requestInjuryData")
    SetEntityHealth(PlayerPedId(), 140)
end)

RegisterNetEvent("amb_client:clampBleeding", function()
    playerInjuries.bleeding = 0
    TriggerEvent("amb_client:Notify", _L("arterial_bleeding_controlled"), "success")
    TriggerEvent("amb_client:requestInjuryData")
end)

local BandagePropVars = {
    chest = 192,
    right_leg = 193,
    left_leg = 194,
    head = 195,
    right_arm = 196,
    left_arm = 197
}

RegisterNetEvent("amb_client:applyBandage", function(part)
    local ped = PlayerPedId()
    if type(part) ~= "string" then part = "chest" end
    
    playerInjuries.bleeding = 0
    isPatientBandaged = true
    
    if playerInjuries[part] and type(playerInjuries[part]) == "table" then
        playerInjuries[part].bandaged = true
    end
    
    if not isDowned then
        local health = GetEntityHealth(ped)
        if health and health > 110 and health < 200 then
            SetEntityHealth(ped, 200)
        end
    end
    
    local propVar = BandagePropVars[part]
    if propVar then
        SetPedComponentVariation(ped, 7, propVar, 0, 0)
    end
    
    local syncData = {}
    for k, v in pairs(playerInjuries) do syncData[k] = v end
    syncData.isPatientBandaged = isPatientBandaged
    TriggerServerEvent("amb_server:syncInjuryData", syncData)
end)

RegisterNetEvent("amb_client:selfBandage", function()
    local ped = PlayerPedId()
    if isDowned then return end
    
    CreateThread(function()
        local label = _L("applying_bandage")
        Framework.Notify(label, "primary")
        Framework.RequestAnimDict("missheistprowlprepb")
        TaskPlayAnim(ped, "missheistprowlprepb", "low_reach_loop", 8.0, -8.0, 3000, 49, 0, false, false, false)
        
        local success = Framework.ProgressBar(label, 3000)
        ClearPedTasks(ped)
        
        if not success then
            Framework.Notify("Cancelled", "error")
            return
        end
        
        if playerInjuries.bleeding > 0 then
            playerInjuries.bleeding = 0
            Framework.Notify(_L("bleeding_stopped"), "success")
            
            local syncData = {}
            for k, v in pairs(playerInjuries) do syncData[k] = v end
            syncData.isPatientBandaged = isPatientBandaged
            TriggerServerEvent("amb_server:syncInjuryData", syncData)
        else
            Framework.Notify(_L("bandage_applied"), "info")
        end
    end)
end)

RegisterNetEvent("amb_client:syncCPRAnimation", function(source, role, phase)
    local ped = PlayerPedId()
    local dict = "mini@cpr@char_b@cpr_str"
    if role == "ems" then dict = "mini@cpr@char_a@cpr_str" end
    
    local anim = "cpr_pumpchest"
    if phase == "success" then anim = "cpr_success" end
    
    isCPRPlaying = true
    print("^3[PLT_MEDIC] CPR Animation Sync: Role=" .. tostring(role) .. " Phase=" .. tostring(phase) .. "^7")
    
    Framework.RequestAnimDict(dict)
    if not IsEntityPlayingAnim(ped, dict, anim, 3) then
        if role ~= "patient" then
            ClearPedTasks(ped)
        end
        
        local blendOut = (phase == "success") and 0 or 1
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, blendOut, 1.0, false, false, false)
    end
end)

RegisterNetEvent("amb_client:stopCPRAnimation", function()
    local ped = PlayerPedId()
    isCPRPlaying = false
    ClearPedTasks(ped)
    
    if isDowned then
        Framework.RequestAnimDict("misslamar1dead_body")
        TaskPlayAnim(ped, "misslamar1dead_body", "dead_idle", 8.0, -8.0, -1, 1, 1.0, false, false, false)
    end
end)

RegisterCommand("hungerdie", function()
    local ped = PlayerPedId()
    isDowned = true
    playerInjuries.right_arm.level = 2
    playerInjuries.right_arm.hunger = true
    SetEntityHealth(ped, 100)
    SetEntityInvincible(ped, true)
    TriggerServerEvent("amb_server:SetDowned", true)
    Framework.Notify(_L("hunger_test_triggered"), "info")
end, false)
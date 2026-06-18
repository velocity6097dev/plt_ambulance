-- ============================================================
-- health.lua  –  EMS Injury, Death & Revive System (Client)
-- ============================================================

-- ── Injury state ─────────────────────────────────────────────
-- One table entry per body part; `bleeding` is a severity int.
local injuries = {
    head      = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    chest     = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    left_arm  = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    right_arm = { level = 0, bullet = false, bandaged = false, hunger = false, isFractured = false, fractureTime = 0 },
    left_leg  = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    right_leg = { level = 0, bullet = false, bandaged = false, isFractured = false, fractureTime = 0 },
    bleeding  = 0,
}

-- ── Module-level flags & counters ────────────────────────────
local isPatientBandaged   = false  -- true once any bandage has been applied
local isDowned            = false  -- true while the player is in a downed/dead state
local isDeadRestricted    = false  -- true while dead-restriction routines are active (voice/inventory)
local isPhoneDisabled     = false  -- mirrors the lb-phone disabled flag
local isReviving          = false  -- true during the short post-revive stabilisation window
local isLimping           = false  -- true when the limp clipset is applied
local isBlurActive        = false  -- true while the head-injury screenblur is shown
local isCPRActive         = false  -- true while a CPR animation is playing

local deathCounter        = 0      -- incremented on every new death/downed event (used as a generation guard)
local ragdollGraceTimer   = 0      -- GetGameTimer deadline after which ragdoll is re-allowed
local bleedReviveDeadline = 0      -- GetGameTimer deadline for the "bleed-out revive" window
local reviveCooldownTimer = 0      -- used to prevent SetDowned spam on rapid server ticks
local reviveTimestamp     = 0      -- GetGameTimer value when the last revive began

-- ── Animation / constant strings ─────────────────────────────
local ANIM_DEAD_DICT      = "dead"
local ANIM_DEAD_CLIP      = "dead_a"
local ANIM_VEH_DUCK_DICT  = "veh@low@front_ps@idle_duck"
local ANIM_VEH_DUCK_CLIP  = "sit"

-- ── Derived config flags ──────────────────────────────────────
-- `useCustomDeathscreen` is true when Config.Deathscreen is set,
-- meaning we do NOT fall back to the GTA native deathscreen.
local useCustomDeathscreen = not Config.Deathscreen

-- ── Weapon/cause-of-death hash used to detect unconsciousness ─
local CAUSE_UNCONSCIOUS = -1569615261

-- ── Saved clothing for restoration after clothing-removal ─────
local savedClothing = { model = nil, top = nil, bottom = nil }

-- ── Pending saved health value to apply on spawn ─────────────
local pendingSavedHealth    = nil   -- raw health int fetched from server, applied on spawn
local hasSavedHealthApplied = false -- becomes true once the pending value has been set
local lastCachedHealth      = nil   -- most recently cached health (sent to server every 10 s)
local lastCacheTime         = 0     -- GetGameTimer at last cache


-- ════════════════════════════════════════════════════════════
--  Timer helpers
-- ════════════════════════════════════════════════════════════

-- Extend the bleed-out revive window by `ms` milliseconds.
-- Only extends; never shortens.
local function extendReviveWindow(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then return end
    local deadline = GetGameTimer() + ms
    if deadline > bleedReviveDeadline then
        bleedReviveDeadline = deadline
    end
end

-- Consume the revive window: clears it and returns true if it
-- was still active. Returns false if it had already expired.
local function consumeReviveWindow()
    if GetGameTimer() <= bleedReviveDeadline then
        bleedReviveDeadline = 0
        return true
    end
    return false
end

-- Returns true while the revive window is still open.
local function isReviveWindowOpen()
    return GetGameTimer() <= bleedReviveDeadline
end

-- Set a "downed ragdoll" grace-period timer.
local function setRagdollGrace(ms)
    ms = math.max(0, tonumber(ms) or 0)
    ragdollGraceTimer = GetGameTimer() + ms
end

-- Returns true while the ragdoll grace period is active.
local function isInRagdollGrace()
    if not isReviving then return false end
    if GetGameTimer() < ragdollGraceTimer then return false end
    isReviving = false
    return true
end


-- ════════════════════════════════════════════════════════════
--  Health utility helpers
-- ════════════════════════════════════════════════════════════

-- Disable natural health regeneration permanently.
local function disableHealthRegen()
    local pid = PlayerId()
    SetPlayerHealthRechargeMultiplier(pid, 0.0)
    SetPlayerHealthRechargeLimit(pid, 0.0)
end

-- Read DeadRestrictions from config, returning safe defaults.
local function getDeadRestrictions()
    local cfg = Config.Health and Config.Health.DeadRestrictions
    if type(cfg) ~= "table" then
        return { DisableVoice = false, DisableInventory = false }
    end
    return {
        DisableVoice      = cfg.DisableVoice      == true,
        DisableInventory  = cfg.DisableInventory  == true,
    }
end

-- Clamp a raw health value to the valid GTA range [100, 200].
local function clampHealth(raw)
    local n = tonumber(raw)
    if not n then return nil end
    return math.max(100, math.min(200, math.floor(n)))
end


-- ════════════════════════════════════════════════════════════
--  Dead-state restriction helpers
-- ════════════════════════════════════════════════════════════

-- Mute or unmute the local player via MumbleSetPlayerMuted.
-- Respects Config.Health.DeadRestrictions.DisableVoice.
local function setVoiceMuted(mute)
    local restrictions = getDeadRestrictions()
    if not restrictions.DisableVoice then mute = false end
    if mute == isDeadRestricted then return end

    local ok = pcall(function()
        MumbleSetPlayerMuted(PlayerId(), mute)
    end)
    if ok then
        isDeadRestricted = mute
    end
end

-- Fire all known inventory-close events so the player can't use
-- their inventory while downed.
local function closeAllInventories()
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

-- Close the lb-phone UI via every known API variant.
local function closePhone()
    if GetResourceState("lb-phone") ~= "started" then return end
    pcall(function() exports["lb-phone"]:closePhone() end)
    pcall(function() exports["lb-phone"]:ClosePhone() end)
    pcall(function() exports["lb-phone"]:toggleOpen(false) end)
    pcall(function() exports["lb-phone"]:ToggleOpen(false) end)
    TriggerEvent("lb-phone:client:closePhone")
    TriggerEvent("lb-phone:closePhone")
end

-- Enable or disable the lb-phone and update all known state flags.
local function setPhoneDisabled(disabled)
    disabled = (disabled == true)
    if disabled == isPhoneDisabled then return end
    isPhoneDisabled = disabled

    if LocalPlayer and LocalPlayer.state then
        local s = LocalPlayer.state
        s:set("phoneDisabled",  disabled,  true)
        s:set("canUsePhone",    not disabled, true)
        s:set("lbPhoneDisabled", disabled, true)
    end

    if GetResourceState("lb-phone") == "started" then
        pcall(function() exports["lb-phone"]:setPhoneDisabled(disabled) end)
        pcall(function() exports["lb-phone"]:SetPhoneDisabled(disabled) end)
        pcall(function() exports["lb-phone"]:setDisabled(disabled) end)
        pcall(function() exports["lb-phone"]:SetDisabled(disabled) end)
        TriggerEvent("lb-phone:client:setDisabled", disabled)
        TriggerEvent("lb-phone:client:toggleDisabled", disabled)
    end

    if disabled then
        closePhone()
    end
end

-- Lock inventory access and update LocalPlayer state flags.
-- Respects Config.Health.DeadRestrictions.DisableInventory.
local function setInventoryDisabled(disabled)
    local restrictions = getDeadRestrictions()
    if not restrictions.DisableInventory then disabled = false end

    if LocalPlayer and LocalPlayer.state then
        local s = LocalPlayer.state
        s:set("dead",        disabled, true)
        s:set("invBusy",     disabled, true)
        s:set("invOpen",     false,    false)
        s:set("invHotkeys",  not disabled, false)
        s:set("canUseWeapons", not disabled, false)
    end

    if disabled then
        closeAllInventories()
    end
end

-- Apply all dead-state restrictions together.
local function setDeadRestrictions(active)
    setVoiceMuted(active)
    setInventoryDisabled(active)
    setPhoneDisabled(active)
    isDeadRestricted = active
end


-- ════════════════════════════════════════════════════════════
--  Downed-state threshold helper
-- ════════════════════════════════════════════════════════════

-- Returns true if `ped` should count as downed.
-- `serverDownedFlag` is 1 when the server has explicitly flagged
-- the player as downed, which overrides the health threshold.
local function isPedConsideredDowned(ped, serverDownedFlag)
    local threshold = tonumber(Config.Health and Config.Health.DownedThreshold) or 0
    local health    = GetEntityHealth(ped)

    if threshold <= 0 then
        return serverDownedFlag == 1
    end
    return serverDownedFlag == 1 or threshold >= health
end


-- ════════════════════════════════════════════════════════════
--  Saved-health restoration
-- ════════════════════════════════════════════════════════════

-- Start the restore-saved-health sequence on spawn.
-- For QBCore, first checks whether the player is actually downed
-- before applying any stored health value; for other frameworks,
-- applies the stored value unconditionally.
local function fetchAndApplySavedHealth()
    Framework.TriggerCallback("amb_server:getSavedHealth", function(rawHealth)
        local health = clampHealth(rawHealth)

        if Framework and Framework.Type == "qb" and health and health <= 110 then
            -- QBCore: only restore if the server thinks we're NOT downed.
            local serverId = GetPlayerServerId(PlayerId())
            Framework.TriggerCallback("amb_server:isPlayerDowned", function(downed)
                pendingSavedHealth    = downed == true and health or nil
                hasSavedHealthApplied = false
            end, serverId)
            return
        end

        pendingSavedHealth    = health
        hasSavedHealthApplied = false
    end)
end

-- Apply `pendingSavedHealth` to the local ped after a short
-- stabilisation delay. Called from the playerSpawned handler.
local function applyPendingSavedHealth()
    if not (not hasSavedHealthApplied and pendingSavedHealth) then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    CreateThread(function()
        Wait(750)
        local ped2 = PlayerPedId()
        if not ped2 or ped2 == 0 or not DoesEntityExist(ped2) then return end

        SetEntityHealth(ped2, pendingSavedHealth)
        hasSavedHealthApplied = true
        lastCachedHealth = pendingSavedHealth
    end)
end


-- ════════════════════════════════════════════════════════════
--  Clothing helpers
-- ════════════════════════════════════════════════════════════

-- Read drawable/texture/palette for one component slot from `ped`.
local function getComponentVariation(ped, slot)
    return {
        drawable = GetPedDrawableVariation(ped, slot),
        texture  = GetPedTextureVariation(ped, slot),
        palette  = GetPedPaletteVariation(ped, slot),
    }
end

-- Cache the clothing that will need to be restored after medical
-- removal. `clothingType` is "top" or "bottom".
local function cacheClothing(clothingType)
    local ped   = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    local model = GetEntityModel(ped)
    if savedClothing.model ~= model then
        savedClothing.model  = model
        savedClothing.top    = nil
        savedClothing.bottom = nil
    end

    if clothingType == "top" then
        if not savedClothing.top then
            savedClothing.top = {
                torso      = getComponentVariation(ped, 3),
                undershirt = getComponentVariation(ped, 8),
                top        = getComponentVariation(ped, 11),
            }
        end
    elseif clothingType == "bottom" then
        if not savedClothing.bottom then
            savedClothing.bottom = getComponentVariation(ped, 4)
        end
    end
end

-- Restore previously cached clothing to the local ped.
local function restoreClothing()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    if not savedClothing.top and not savedClothing.bottom then return end

    -- Abort if the ped model has changed since we cached.
    if savedClothing.model and GetEntityModel(ped) ~= savedClothing.model then
        savedClothing.model  = nil
        savedClothing.top    = nil
        savedClothing.bottom = nil
        return
    end

    local top = savedClothing.top
    if top then
        if top.torso then
            SetPedComponentVariation(ped, 3,
                top.torso.drawable,
                top.torso.texture  or 0,
                top.torso.palette  or 0)
        end
        if top.undershirt then
            SetPedComponentVariation(ped, 8,
                top.undershirt.drawable,
                top.undershirt.texture  or 0,
                top.undershirt.palette  or 0)
        end
        if top.top then
            SetPedComponentVariation(ped, 11,
                top.top.drawable,
                top.top.texture  or 0,
                top.top.palette  or 0)
        end
    end

    local bottom = savedClothing.bottom
    if bottom then
        SetPedComponentVariation(ped, 4,
            bottom.drawable,
            bottom.texture  or 0,
            bottom.palette  or 0)
    end

    savedClothing.model  = nil
    savedClothing.top    = nil
    savedClothing.bottom = nil
end


-- ════════════════════════════════════════════════════════════
--  Cause-of-death helpers
-- ════════════════════════════════════════════════════════════

-- Classify a cause-of-death weapon hash as either "unconscious"
-- (caused by CAUSE_UNCONSCIOUS) or "dead".
local function classifyDeath(weaponHash)
    if weaponHash == CAUSE_UNCONSCIOUS then
        return "unconscious"
    end
    return "dead"
end

-- Weapon hashes that cause a knockdown / fall state.
local KNOCKDOWN_CAUSES = {
    [-1553120962] = true,
    [133987706]   = true,
    [341774354]   = true,
    [-868994466]  = true,
    [148160082]   = true,
}

-- Weapon type group hashes that classify as firearm (bullet).
-- Groups: pistols, SMGs, assault rifles, sniper rifles.
local FIREARM_GROUPS = {
    [416676503]  = true,  -- pistols
    [-95745345]  = true,  -- SMGs
    [860033945]  = true,  -- assault rifles
    [970310034]  = true,  -- sniper rifles
}

-- Returns (isKnockdown, isFirearm) booleans for a damage event.
-- `ped` is the damaged entity, `weaponHash` is the damage weapon,
-- `attackerEntity` is the entity that caused the damage (may be 0).
local function classifyDamage(ped, weaponHash, attackerEntity)
    local causeOfDeath = GetPedCauseOfDeath(ped)
    local speedKph     = GetEntitySpeed(ped) * 3.6

    local isKnockdown = (weaponHash == -1438083414) or (causeOfDeath == -1438083414)

    local isVehicleAttacker = false
    if attackerEntity and DoesEntityExist(attackerEntity) then
        isVehicleAttacker = attackerEntity ~= 0 and IsEntityAVehicle(attackerEntity)
    end

    local isFirearm = FIREARM_GROUPS[GetWeapontypeGroup(weaponHash)] ~= nil

    return isKnockdown, isFirearm
end


-- ════════════════════════════════════════════════════════════
--  Bone → body-part lookup table
-- ════════════════════════════════════════════════════════════

local BONE_TO_PART = {
    -- Head
    [31086] = "head",  [39317] = "head",  [12844] = "head",  [65068] = "head",
    -- Chest / torso
    [24816] = "chest", [24817] = "chest", [24818] = "chest",
    [10706] = "chest", [11816] = "chest", [57597] = "chest", [23553] = "chest",
    -- Left arm
    [64729] = "left_arm", [45509] = "left_arm", [61163] = "left_arm",
    [18905] = "left_arm", [26610] = "left_arm", [26611] = "left_arm",
    -- Right arm
    [40269] = "right_arm", [28252] = "right_arm", [57005] = "right_arm",
    [58866] = "right_arm", [58867] = "right_arm",
    -- Left leg
    [58271] = "left_leg", [63931] = "left_leg", [63923] = "left_leg",
    [2108]  = "left_leg", [14201] = "left_leg",
    -- Right leg
    [51826] = "right_leg", [36864] = "right_leg", [52301] = "right_leg",
    [20781] = "right_leg", [35502] = "right_leg",
}

-- Resolve the hit body part from the ped's last-damage-bone.
-- Falls back to a one-frame Wait then retries; returns "chest" if
-- the bone still can't be resolved.
local function getHitBodyPart(ped)
    local ok, bone = GetPedLastDamageBone(ped)
    if not (ok and bone) or bone == 0 then
        Wait(0)
        ok, bone = GetPedLastDamageBone(ped)
    end
    if ok and bone and BONE_TO_PART[bone] then
        return BONE_TO_PART[bone]
    end
    return "chest"
end


-- ════════════════════════════════════════════════════════════
--  Fracture system
-- ════════════════════════════════════════════════════════════

-- Attempt to fracture `partName` with the given cause tag.
-- Respects Config.Health.FractureChance (default 80 %).
-- Returns true if the fracture was applied.
local function tryFracturePart(partName, cause)
    if not partName or not injuries[partName] then return false end
    if injuries[partName].isFractured then return false end

    local chance = Config.Health and Config.Health.FractureChance or 80
    if chance < math.random(1, 100) then return false end

    injuries[partName].isFractured  = true
    injuries[partName].fractureTime = Config.Health and Config.Health.FractureTime or 600

    print(string.format("^1[FRACTURE] %s (%s)^7", partName, tostring(cause or "impact")))
    return true
end


-- ════════════════════════════════════════════════════════════
--  Injury summary helpers
-- ════════════════════════════════════════════════════════════

-- Returns the current injury severity as a string:
--   "fatal"  – player is downed
--   "severe" – actively bleeding
--   "minor"  – any injury level > 0
--   "none"   – completely clean
local function getInjuryType()
    if isDowned then return "fatal" end

    if injuries.bleeding and injuries.bleeding > 0 then
        return "severe"
    end

    local total = 0
    for _, info in pairs(injuries) do
        if type(info) == "table" and info.level then
            total = total + info.level
        end
    end

    return total > 0 and "minor" or "none"
end

GetInjuryType = getInjuryType
exports("GetInjuryType", GetInjuryType)

-- Ensure there is at least some injury data recorded on death.
-- If all parts show level 0, force a level-2 chest wound so the
-- EMS diagnosis panel always has something meaningful to show.
local function ensureBaselineInjury()
    local total = 0
    for _, info in pairs(injuries) do
        if type(info) == "table" and info.level then
            total = total + info.level
        end
    end
    if total == 0 then
        injuries.chest.level = 2
    end
end

-- Reset all injury data to clean defaults.
local function clearInjuries()
    isPatientBandaged = false
    for key, value in pairs(injuries) do
        if type(value) == "table" then
            value.level      = 0
            value.bullet     = false
            value.bandaged   = false
            if value.hunger  ~= nil then value.hunger = false end
            value.needsFludro = false
            value.isFractured = false
            value.fractureTime = 0
        else
            injuries[key] = 0
        end
    end
end

-- Shallow-copy injuries and sync to server.
local function syncInjuriesToServer()
    local snapshot = {}
    for k, v in pairs(injuries) do
        snapshot[k] = v
    end
    snapshot.isPatientBandaged = isPatientBandaged
    TriggerServerEvent("amb_server:syncInjuryData", snapshot)
end


-- ════════════════════════════════════════════════════════════
--  Down / Death animation helpers
-- ════════════════════════════════════════════════════════════

-- Play the appropriate downed animation on `ped` depending on
-- whether they are in a vehicle.
local function playDownedAnim(ped)
    if IsPedInAnyVehicle(ped, false) then
        if not HasAnimDictLoaded(ANIM_VEH_DUCK_DICT) then
            Framework.RequestAnimDict(ANIM_VEH_DUCK_DICT)
        end
        if not IsEntityPlayingAnim(ped, ANIM_VEH_DUCK_DICT, ANIM_VEH_DUCK_CLIP, 3) then
            TaskPlayAnim(ped,
                ANIM_VEH_DUCK_DICT, ANIM_VEH_DUCK_CLIP,
                1.0, 1.0, -1, 1, 0.0, false, false, false)
        end
        return
    end

    if not HasAnimDictLoaded(ANIM_DEAD_DICT) then
        Framework.RequestAnimDict(ANIM_DEAD_DICT)
    end
    if not IsEntityPlayingAnim(ped, ANIM_DEAD_DICT, ANIM_DEAD_CLIP, 3) then
        TaskPlayAnim(ped,
            ANIM_DEAD_DICT, ANIM_DEAD_CLIP,
            1.0, 1.0, -1, 1, 0.0, false, false, false)
    end
end

-- Resurrect a dead/invisible ped in-place, preserving their
-- vehicle seat if applicable. Returns the (possibly new) ped handle.
local function resurrectPedInPlace(ped)
    if not (IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 0) then
        -- Not dead; check for vehicle situation anyway.
        if IsPedInAnyVehicle(ped, false) then
            local veh  = GetVehiclePedIsIn(ped, false) or 0
            local seat = -1
            if veh ~= 0 then
                for s = -1, GetVehicleModelNumberOfSeats(GetEntityModel(veh)) - 2 do
                    if GetPedInVehicleSeat(veh, s) == ped then
                        seat = s
                        break
                    end
                end
            end
            if not IsPedInAnyVehicle(ped, false) then
                SetPedCanRagdoll(ped, true)
                SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
            end
        else
            SetPedCanRagdoll(ped, true)
            SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
        end
        return ped
    end

    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local inVehicle = IsPedInAnyVehicle(ped, false)
    local vehicle   = inVehicle and GetVehiclePedIsIn(ped, false) or 0
    local seat      = -1

    if inVehicle and vehicle ~= 0 then
        for s = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
            if GetPedInVehicleSeat(vehicle, s) == ped then
                seat = s
                break
            end
        end
    end

    NetworkResurrectLocalPlayer(
        coords.x, coords.y, coords.z,
        heading, true, false)
    Wait(0)

    local newPed = PlayerPedId()

    if inVehicle and DoesEntityExist(vehicle) then
        SetPedIntoVehicle(newPed, vehicle, seat)
    else
        SetEntityCoordsNoOffset(newPed,
            coords.x, coords.y, coords.z,
            false, false, false)
        SetEntityHeading(newPed, heading)
    end

    SetEntityVisible(newPed, true, false)
    ResetEntityAlpha(newPed)

    if not inVehicle then
        SetPedCanRagdoll(newPed, true)
        SetPedToRagdoll(newPed, 2000, 2000, 0, false, false, false)
    end

    return newPed
end

-- Wait out the initial movement impulse (up to 2.5 s) after a
-- ragdoll or a vehicle ejection before triggering the downed state.
local function waitForPedToSettle()
    Wait(1000)
    local ped   = PlayerPedId()
    local ticks = 0
    while ticks < 250 do
        local speed = GetEntitySpeed(ped)
        if speed > 0.5 or IsPedRagdoll(ped) then
            Wait(10)
            ticks = ticks + 1
            ped = PlayerPedId()
        else
            break
        end
    end
end

-- Returns true when Framework.Type == "qb".
local function isQBCore()
    return Framework and Framework.Type == "qb"
end

-- Put the ped into the downed state (ESX path): resurrect in-place,
-- lock, apply restrictions, play dead anim.
local function applyDownedStateESX(ped)
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local inVeh   = IsPedInAnyVehicle(ped, false)
    local vehicle = inVeh and GetVehiclePedIsIn(ped, false) or 0
    local seat    = -1

    if inVeh and vehicle ~= 0 then
        for s = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
            if GetPedInVehicleSeat(vehicle, s) == ped then seat = s break end
        end
    end

    NetworkResurrectLocalPlayer(
        coords.x, coords.y, coords.z + 0.5,
        heading, true, false)
    Wait(0)

    local newPed = PlayerPedId()
    if inVeh and vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetPedIntoVehicle(newPed, vehicle, seat)
    else
        SetEntityCoordsNoOffset(newPed,
            coords.x, coords.y, coords.z,
            false, false, false)
        SetEntityHeading(newPed, heading)
    end

    SetEntityVisible(newPed, true, false)
    ResetEntityAlpha(newPed)
    SetEntityHealth(newPed, GetEntityMaxHealth(newPed))
    SetEntityInvincible(newPed, true)
    SetEntityProofs(newPed, false, false, false, false, false, false, false, false)
    SetPedCanRagdoll(newPed, false)
    SetPedCanRagdollFromPlayerImpact(newPed, false)
    SetBlockingOfNonTemporaryEvents(newPed, true)

    setDeadRestrictions(true)
    playDownedAnim(newPed)
    ensureBaselineInjury()

    TriggerServerEvent("amb_server:SetDowned", true)
    TriggerEvent("amb_client:onPlayerDeath", classifyDeath(GetPedCauseOfDeath(newPed)))

    return true
end

-- Attempt to handle a QBCore death event. Returns false if the
-- player was not actually in a downed state (let the normal path
-- continue instead).
local function handleQBCoreDeath(weaponHash)
    if not isQBCore() then return false end
    if isDowned then return false end
    if isReviveWindowOpen() then return false end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    isDowned     = true
    deathCounter = deathCounter + 1
    local myGen  = deathCounter
    ragdollGraceTimer = GetGameTimer() + 1000

    ensureBaselineInjury()
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "demo", 0.1)

    CreateThread(function()
        Wait(1000)
        local ped2 = PlayerPedId()
        local ticks = 0

        -- Wait for the ped to settle (up to 2.5 s).
        while isDowned and deathCounter == myGen and ticks < 250 do
            local speed = GetEntitySpeed(ped2)
            if speed > 0.5 or IsPedRagdoll(ped2) then
                Wait(10)
                ticks = ticks + 1
                ped2 = PlayerPedId()
            else
                break
            end
        end

        if not isDowned or deathCounter ~= myGen then return end
        if isReviveWindowOpen() then return end

        -- Resurrect in-place.
        ped2 = resurrectPedInPlace(ped2)

        if not isDowned or deathCounter ~= myGen then return end
        if isReviveWindowOpen() then return end

        -- Apply fractures on a fall/vehicle event.
        local isKnockdown, isFirearm = classifyDamage(ped2, weaponHash, 0)
        if isKnockdown or isFirearm then
            local limbOptions = { "left_leg", "right_leg", "left_arm", "right_arm" }
            local pickedLimb  = limbOptions[math.random(1, #limbOptions)]

            if isKnockdown then
                pickedLimb = math.random(1, 100) > 20
                    and (math.random(1, 2) == 1 and "left_leg" or "right_leg")
                    or  (math.random(1, 2) == 1 and "left_arm" or "right_arm")
            end

            tryFracturePart(pickedLimb, isKnockdown and "downed_fall" or "downed_vehicle")
        end

        SetEntityHealth(ped2, 100)
        SetEntityInvincible(ped2, true)
        TriggerServerEvent("amb_server:SetDowned", true)
        ensureBaselineInjury()
        SendDeathDispatch()

        print("^1[DEBUG] Player death detected, triggering death screen...^7")
        TriggerEvent("amb_client:onPlayerDeath", classifyDeath(weaponHash))
    end)

    return true
end


-- ════════════════════════════════════════════════════════════
--  Input lock helper (used while downed)
-- ════════════════════════════════════════════════════════════

-- Disable movement/combat controls and re-enable camera/UI controls.
-- Called every frame while downed.
local DISABLED_CONTROLS = {
    24, 25, 73,                         -- attack, aim, melee
    30, 31, 32, 33, 34, 35,             -- movement
    21, 22, 23, 38, 44,                 -- sprint, jump, enter, interact
}
local DISABLED_CONTROLS_FULL = {       -- added for dead (non-custom deathscreen) state
    24, 25, 73, 30, 31, 32, 33, 34, 35,
    21, 22, 23, 38, 44, 75, 59, 60, 61,
    62, 63, 64, 71, 72, 76, 85, 86,
    140, 141, 142, 257,
}
local ENABLED_CONTROLS = { 1, 2, 3, 4, 245, 246, 47 }

local function applyDownedControls(includeInventory)
    local controls = useCustomDeathscreen and DISABLED_CONTROLS or DISABLED_CONTROLS_FULL

    for _, ctrl in ipairs(controls) do
        DisableControlAction(0, ctrl, true)
    end

    if not useCustomDeathscreen and includeInventory then
        if getDeadRestrictions().DisableInventory then
            DisableControlAction(0, 37, true)  -- open inventory
        end
    end

    for _, ctrl in ipairs(ENABLED_CONTROLS) do
        EnableControlAction(0, ctrl, true)
    end

    if not IsPlayerControlOn(PlayerId()) then
        SetPlayerControl(PlayerId(), true, 0)
    end
end

-- Briefly block attack/throw/dodge controls after spawn so the
-- player can't accidentally fire during the ragdoll settle phase.
local function blockInputTemporarily()
    local pid  = PlayerId()
    local ped  = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    end
    SetPlayerControl(pid, true, 0)

    CreateThread(function()
        local ticks = 0
        while isDowned and ticks < 120 do
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
            ticks = ticks + 1
            Wait(0)
        end
    end)
end


-- ════════════════════════════════════════════════════════════
--  RevivePlayer export
-- ════════════════════════════════════════════════════════════

local function revivePlayer()
    -- QBCore: require the revive window to be open.
    if isQBCore() and not consumeReviveWindow() then return end

    -- Don't re-run if already reviving.
    if isReviving then return end

    local ped = PlayerPedId()
    local pid = PlayerId()

    -- If player is effectively healthy with no injuries and not bandaged,
    -- nothing to revive.
    if not isDowned then
        local health = GetEntityHealth(ped)
        if health >= 200 then
            local hasInjury = false
            for _, info in pairs(injuries) do
                if type(info) == "table" and info.level > 0 then
                    hasInjury = true
                    break
                end
            end
            if not hasInjury and not isPatientBandaged then return end
        end
    end

    isReviving    = true
    reviveTimestamp = GetGameTimer()
    isDowned      = false

    setDeadRestrictions(false)
    deathCounter  = deathCounter + 1
    isDeadRestricted = false
    ragdollGraceTimer = 0
    setRagdollGrace(8000)
    isCPRActive   = false

    TriggerServerEvent("amb_server:SetDowned", false)
    TriggerEvent("amb_client:onPlayerRevive")
    TriggerEvent("amb_client:SetDownedState", false)

    SendNUIMessage({ action = "amb_toggleDeathScreen", show = false })

    -- Clear bandage component slot.
    SetPedComponentVariation(ped, 7, 0, 0, 0)
    clearInjuries()
    injuries.bleeding = 0

    -- Clear visual effects.
    if isBlurActive then
        TriggerScreenblurFadeOut(500.0)
        isBlurActive = false
    end
    if isLimping then
        ResetPedMovementClipset(ped, 0)
        isLimping = false
    end

    ClearPedBloodDamage(ped)
    ClearPedLastDamageBone(ped)
    ClearEntityLastDamageEntity(ped)

    -- Handle vehicle situation.
    local inVeh   = IsPedInAnyVehicle(ped, false)
    local vehicle = inVeh and GetVehiclePedIsIn(ped, false) or 0

    -- Resurrect if needed.
    local needsResurrect = GetEntityHealth(ped) <= 5
        or IsPedDeadOrDying(ped, 1)
        or IsEntityPlayingAnim(ped, ANIM_DEAD_DICT, ANIM_DEAD_CLIP, 3)
        or IsEntityPlayingAnim(ped, "misslamar1dead_body", "dead_idle", 3)

    if needsResurrect then
        local coords  = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(
            coords.x, coords.y, coords.z,
            GetEntityHeading(ped), true, false)
        Wait(100)
        ped = PlayerPedId()
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
    end

    restoreClothing()
    DetachEntity(ped, true, true)

    SetEntityHealth(ped, 200)
    SetEntityInvincible(ped, false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetPedCanRagdoll(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetPlayerControl(pid, true, 0)

    SetPedToRagdoll(ped, 0, 0, 0, false, false, false)

    if not inVeh then
        ClearPedTasksImmediately(ped)
        local c = GetEntityCoords(ped)
        SetEntityCoords(ped, c.x, c.y, c.z + 0.1, false, false, false, false)
    else
        StopAnimTask(ped, ANIM_VEH_DUCK_DICT, ANIM_VEH_DUCK_CLIP, 1.0)
        StopAnimTask(ped, ANIM_DEAD_DICT,     ANIM_DEAD_CLIP,     1.0)
        StopAnimTask(ped, "misslamar1dead_body", "dead_idle",      1.0)
        ClearPedSecondaryTask(ped)

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleUndriveable(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
        end
    end

    EnableAllControlActions(0)
    SetPedConfigFlag(ped, 184, false)
    SetPedConfigFlag(ped, 241, false)

    -- Short stabilisation loop: enforce full health and controls
    -- for up to 1.2 s so snaps back to a damaged state don't occur.
    CreateThread(function()
        for _ = 1, 120 do
            Wait(10)
            if isDowned then break end

            local p = PlayerPedId()
            setRagdollGrace(0)
            if GetEntityHealth(p) < 120 then
                SetEntityHealth(p, 200)
            end
            EnableAllControlActions(0)
            SetPlayerControl(PlayerId(), true, 0)
            FreezeEntityPosition(p, false)
            SetEntityInvincible(p, false)
        end
        setRagdollGrace(0)
        isReviving = false
    end)

    TriggerServerEvent("amb_server:SetDowned", false)
    TriggerServerEvent("amb_server:cacheHealth", GetEntityHealth(PlayerPedId()))
    syncInjuriesToServer()
    Framework.Notify(_L("healed"), "success")
end

exports("RevivePlayer", revivePlayer)


-- ════════════════════════════════════════════════════════════
--  Main gameplay thread
-- ════════════════════════════════════════════════════════════

-- Detect conflict with qb-ambulancejob.
CreateThread(function()
    Wait(1500)
    if isQBCore() and GetResourceState("qb-ambulancejob") == "started" then
        print("^1[plt_ambulance] QBCore mode detected while qb-ambulancejob is running. "
            .. "Disable one death system to prevent conflicts.^7")
    end
end)

-- Constantly enforce regen-disable.
CreateThread(function()
    while true do
        disableHealthRegen()
        Wait(5000)
    end
end)

-- Main health / downed-state loop (~1 Hz when healthy, 0 Hz when downed).
CreateThread(function()
    local waitMs         = 1000
    local nextAnimCheck  = 0
    local nextAnimPreload = 0
    local nextRagdollTick = 0
    local lastGenHealth  = 0

    while true do
        waitMs = 1000
        local ped   = PlayerPedId()
        local timer = GetGameTimer()

        -- Apply any pending "bleed-out heal" tick.
        setRagdollGrace(0)   -- polls the timer internally

        if not isDowned then
            -- Cache health every 10 s to the server.
            if timer - lastCacheTime >= 1000 then
                lastCacheTime = timer
                local health = clampHealth(GetEntityHealth(ped))
                if health then
                    local noCache = not lastCachedHealth
                    local stale   = timer - lastGenHealth >= 10000
                    if noCache or stale then
                        TriggerServerEvent("amb_server:cacheHealth", health)
                        lastCachedHealth = health
                        lastGenHealth    = timer
                    end
                end
            end

            -- ── Tick fracture timers ──────────────────────────────
            if timer - lastCacheTime >= 1000 then
                for partName, info in pairs(injuries) do
                    if type(info) == "table" and info.isFractured then
                        if info.fractureTime > 0 then
                            info.fractureTime = info.fractureTime - 1
                        else
                            info.isFractured = false
                            TriggerEvent("amb_client:Notify",
                                _L("fracture_healed", { part = partName:gsub("_", " ") }),
                                "success")
                        end
                    end
                end
            end

            -- ── Leg injury effects ────────────────────────────────
            local leftLegBad  = injuries.left_leg.level  > 0 or injuries.left_leg.isFractured
            local rightLegBad = injuries.right_leg.level > 0 or injuries.right_leg.isFractured

            if leftLegBad or rightLegBad then
                waitMs = 0
                DisableControlAction(0, 21, true)  -- sprint

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

            -- ── Arm injury effects ────────────────────────────────
            local leftArmBad  = injuries.left_arm.level  > 0 or injuries.left_arm.isFractured
            local rightArmBad = injuries.right_arm.level > 0 or injuries.right_arm.isFractured

            if leftArmBad or rightArmBad then
                waitMs = 0
                DisableControlAction(0, 21, true)

                -- Shake camera when aiming with injured arms.
                if IsControlPressed(0, 25) then
                    local intensity = (injuries.left_arm.level + injuries.right_arm.level) * 0.5
                    if injuries.left_arm.isFractured or injuries.right_arm.isFractured then
                        intensity = intensity + 1.5
                    end
                    ShakeGameplayCam("HAND_SHAKE", intensity)
                end
            end

            -- ── Head injury blur ──────────────────────────────────
            if injuries.head.level > 0 then
                waitMs = 0
                if Config.EnableBlurEffect ~= false and not isBlurActive then
                    TriggerScreenblurFadeIn(1000.0)
                    isBlurActive = true
                end
            elseif isBlurActive then
                TriggerScreenblurFadeOut(1000.0)
                isBlurActive = false
            end

            -- ── Active bleed tick ─────────────────────────────────
            if injuries.bleeding > 0 then
                local bleedInterval = Config.Health and Config.Health.BleedInterval or 2000
                local bleedRate     = Config.Health and Config.Health.BleedRate     or 1
                local bleedMin      = Config.Health and Config.Health.BleedDecalMin or 2

                waitMs = bleedInterval
                local newHealth = GetEntityHealth(ped) - (bleedRate * injuries.bleeding)
                SetEntityHealth(ped, newHealth)

                if injuries.bleeding > bleedMin then
                    local pos = GetEntityCoords(ped)
                    AddDecal(1010,
                        pos.x, pos.y, pos.z - 1.0,
                        0.0, 0.0, 0.0,
                        0.0, 1.0, 0.0,
                        0.2, 0.2,
                        255, 0, 0, 255,
                        60.0, false, false, false)
                end
            end

        else
            -- ── Downed state maintenance ──────────────────────────
            local pollInterval = useCustomDeathscreen and 40 or 0
            waitMs = pollInterval

            if not isDeadRestricted then
                setDeadRestrictions(true)
            end

            -- Keep health at "dead" floor and entity invincible.
            if timer >= nextAnimCheck then
                nextAnimCheck = timer + 500

                if isQBCore() then
                    if GetEntityHealth(ped) ~= GetEntityMaxHealth(ped) then
                        SetEntityHealth(ped, GetEntityMaxHealth(ped))
                    end
                else
                    if GetEntityHealth(ped) ~= 100 then
                        SetEntityHealth(ped, 100)
                    end
                end
                SetEntityInvincible(ped, true)

                if isQBCore() then
                    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
                else
                    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
                end
            end

            -- Preload anim dicts so they're ready to play.
            if timer >= nextAnimPreload then
                nextAnimPreload = timer + 1500
                if IsPedInAnyVehicle(ped, false) then
                    if not HasAnimDictLoaded(ANIM_VEH_DUCK_DICT) then
                        Framework.RequestAnimDict(ANIM_VEH_DUCK_DICT)
                    end
                else
                    if not HasAnimDictLoaded(ANIM_DEAD_DICT) then
                        Framework.RequestAnimDict(ANIM_DEAD_DICT)
                    end
                end
            end

            -- Keep playing the downed anim and block inputs.
            if not isCPRActive then
                if isQBCore() then
                    if timer >= nextRagdollTick then
                        nextRagdollTick = timer + 500
                        SetPedCanRagdoll(ped, false)
                        SetPedCanRagdollFromPlayerImpact(ped, false)
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        playDownedAnim(ped)
                    end
                else
                    nextRagdollTick = timer + 200
                    if timer < ragdollGraceTimer then
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
                        playDownedAnim(ped)
                    end

                    -- Lock the downed vehicle.
                    if IsPedInAnyVehicle(ped, false) then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh and veh ~= 0 and DoesEntityExist(veh) then
                            SetVehicleUndriveable(veh, true)
                            SetVehicleEngineOn(veh, false, true, true)
                            SetVehicleForwardSpeed(veh, 0.0)
                            SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                        end
                    end
                end
            end

            -- Apply input restrictions while downed.
            if not useCustomDeathscreen then
                applyDownedControls(true)
            end

            -- Enforce non-broken ped flags.
            if not isDeadRestricted then
                SetPedConfigFlag(ped, 184, true)
                SetPedConfigFlag(ped, 241, true)
                isDeadRestricted = true
            end
        end

        Wait(waitMs)
    end
end)

-- Fallback death detector (250 ms polling).
-- Handles cases where gameEventTriggered fires late or not at all.
CreateThread(function()
    while true do
        Wait(250)
        if not isDowned and not isReviveWindowOpen() and not isInRagdollGrace() then
            local ped = PlayerPedId()
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 100 then
                    local weaponHash = GetPedCauseOfDeath(ped)
                    if not handleQBCoreDeath(weaponHash) then
                        -- ESX fallback path.
                        isDowned     = true
                        deathCounter = deathCounter + 1
                        local myGen  = deathCounter
                        ragdollGraceTimer = GetGameTimer() + 1000

                        ensureBaselineInjury()

                        local inVeh = IsPedInAnyVehicle(ped, false)
                        if not inVeh and not isQBCore() then
                            waitForPedToSettle()
                        end

                        if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                            ped = resurrectPedInPlace(ped) or PlayerPedId()
                        else
                            goto ::continue::
                        end

                        if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                            SetEntityHealth(ped, 100)
                            SetEntityInvincible(ped, true)
                            TriggerServerEvent("amb_server:SetDowned", true)
                            ensureBaselineInjury()

                            print("^3[HEALTH FALLBACK]^7 Forced downed state from fallback detector.")

                            -- Apply fractures.
                            local isKnockdown, isFirearm = classifyDamage(ped, weaponHash, 0)
                            if isKnockdown or isFirearm then
                                local pickedLimb = isKnockdown
                                    and (math.random(1, 2) == 1 and "left_leg" or "right_leg")
                                    or  (math.random(1, 2) == 1 and "left_arm" or "right_arm")
                                tryFracturePart(pickedLimb,
                                    isKnockdown and "fallback_fall" or "fallback_vehicle")
                            end

                            TriggerEvent("amb_client:onPlayerDeath", classifyDeath(weaponHash))
                        end
                    end
                end
            end
        end
        ::continue::
    end
end)

-- Timeout monitor: auto-clear revive window / revive flag after
-- it has expired (avoids stale state on edge-case disconnects).
CreateThread(function()
    while true do
        Wait(1000)

        if isReviveWindowOpen() and GetGameTimer() > bleedReviveDeadline + 2000 then
            setRagdollGrace(0)
        end

        if isReviving and not isDowned and not isReviveWindowOpen() then
            isReviving = false
        end
    end
end)

-- Phone-close loop: while downed and lb-phone is open, close it
-- every 750 ms to prevent menu-through-death exploits.
CreateThread(function()
    while true do
        if isPhoneDisabled and isDowned then
            if GetResourceState("lb-phone") == "started" then
                closePhone()
                Wait(750)
            end
        else
            Wait(1500)
        end
    end
end)


-- ════════════════════════════════════════════════════════════
--  gameEventTriggered: primary damage handler
-- ════════════════════════════════════════════════════════════

AddEventHandler("gameEventTriggered", function(eventName, args)
    if eventName ~= "CEventNetworkEntityDamage" then return end

    local damagedEntity = args[1]
    local weaponHash    = args[7]
    local attackerEntity = args[2]
    local isFatalHit    = args[6]  -- 1 = fatal/lethal

    local myPed = PlayerPedId()
    if damagedEntity ~= myPed then return end

    if isReviveWindowOpen() then return end
    if isInRagdollGrace() then return end

    if isDowned then
        -- Already downed: just keep the health locked.
        if isQBCore() then
            SetEntityHealth(myPed, GetEntityMaxHealth(myPed))
        else
            SetEntityHealth(myPed, 100)
        end
        SetEntityInvincible(myPed, true)

        if isQBCore() then
            playDownedAnim(myPed)
        else
            -- Re-apply downed anim if out of grace.
            if GetGameTimer() >= ragdollGraceTimer then
                if not isCPRActive then
                    if not IsPedInAnyVehicle(myPed, false) then
                        if not IsEntityPlayingAnim(myPed, ANIM_DEAD_DICT, ANIM_DEAD_CLIP, 3) then
                            ClearPedTasksImmediately(myPed)
                            TaskPlayAnim(myPed,
                                ANIM_DEAD_DICT, ANIM_DEAD_CLIP,
                                1.0, 1.0, -1, 1, 0.0, false, false, false)
                        end
                    else
                        if not IsEntityPlayingAnim(myPed, ANIM_VEH_DUCK_DICT, ANIM_VEH_DUCK_CLIP, 3) then
                            ClearPedTasksImmediately(myPed)
                            TaskPlayAnim(myPed,
                                ANIM_VEH_DUCK_DICT, ANIM_VEH_DUCK_CLIP,
                                1.0, 1.0, -1, 1, 0.0, false, false, false)
                        end
                    end
                end
            end
        end
        return
    end

    -- ── Record injury for this hit ────────────────────────────
    local hitPart = getHitBodyPart(myPed)
    if hitPart then
        local maxLevel = Config.Health and Config.Health.MaxInjuryLevel or 5
        injuries[hitPart].level = math.min(maxLevel, injuries[hitPart].level + 1)

        local isKnockdown, isFirearm = classifyDamage(myPed, weaponHash, attackerEntity)

        -- Fractures on knockdown/fall.
        if isKnockdown or isFirearm then
            local fractureTarget = hitPart
            if isKnockdown then
                fractureTarget = math.random(1, 2) == 1 and "left_leg" or "right_leg"
            end
            tryFracturePart(fractureTarget, isKnockdown and "fall" or "fall_fallback")

            if not isKnockdown then
                tryFracturePart(hitPart, "vehicle")
            end
        end

        -- Bullet flag & bleed chance.
        local weaponGroup = GetWeapontypeGroup(weaponHash)
        if FIREARM_GROUPS[weaponGroup] then
            injuries[hitPart].bullet = true

            local bleedChance = Config.Health and Config.Health.BulletBleedChance or 90
            if bleedChance > math.random(1, 100) then
                injuries.bleeding = injuries.bleeding + 1
            end
        else
            local bleedChance = Config.Health and Config.Health.BleedChance or 40
            if bleedChance > math.random(1, 100) then
                injuries.bleeding = injuries.bleeding + 1
            end
        end

        syncInjuriesToServer()
    end

    -- ── Check if this hit triggered a downed state ────────────
    if isPedConsideredDowned(myPed, isFatalHit) then
        if isDowned then return end

        -- Try QBCore death handler first.
        local isKnockdown2, isFirearm2 = classifyDamage(myPed, weaponHash, attackerEntity)
        if not handleQBCoreDeath(weaponHash) then
            -- ESX / non-QBCore path.
            isDowned     = true
            deathCounter = deathCounter + 1
            local myGen  = deathCounter
            ragdollGraceTimer = GetGameTimer() + 1000

            ensureBaselineInjury()

            local inVeh = IsPedInAnyVehicle(myPed, false)

            if not inVeh and not isQBCore() then
                waitForPedToSettle()

                if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                    myPed = resurrectPedInPlace(myPed) or PlayerPedId()
                else
                    return
                end

                if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                    -- Apply downed-fall fractures.
                    if isKnockdown2 or isFirearm2 then
                        local pickedLimb = isKnockdown2
                            and (math.random(1, 2) == 1 and "left_leg" or "right_leg")
                            or  (math.random(1, 2) == 1 and "left_arm" or "right_arm")
                        tryFracturePart(pickedLimb,
                            isKnockdown2 and "downed_fall" or "downed_vehicle")
                    end

                    SetEntityHealth(myPed, 100)
                    SetEntityInvincible(myPed, true)
                    TriggerServerEvent("amb_server:SetDowned", true)
                    ensureBaselineInjury()
                    SendDeathDispatch()

                    print("^1[DEBUG] Player death detected, triggering death screen...^7")
                    TriggerEvent("amb_client:onPlayerDeath", classifyDeath(weaponHash))
                end
            else
                myPed = resurrectPedInPlace(myPed) or PlayerPedId()
                if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                    if isKnockdown2 or isFirearm2 then
                        local pickedLimb = isKnockdown2
                            and (math.random(1, 2) == 1 and "left_leg" or "right_leg")
                            or  (math.random(1, 2) == 1 and "left_arm" or "right_arm")
                        tryFracturePart(pickedLimb,
                            isKnockdown2 and "downed_fall" or "downed_vehicle")
                    end

                    SetEntityHealth(myPed, 100)
                    SetEntityInvincible(myPed, true)
                    TriggerServerEvent("amb_server:SetDowned", true)
                    ensureBaselineInjury()
                    SendDeathDispatch()

                    print("^1[DEBUG] Player death detected, triggering death screen...^7")
                    TriggerEvent("amb_client:onPlayerDeath", classifyDeath(weaponHash))
                end
            end
        end
    end
end)


-- ════════════════════════════════════════════════════════════
--  Player-load / spawn event handlers
-- ════════════════════════════════════════════════════════════

-- QBCore player loaded.
RegisterNetEvent("QBCore:Client:OnPlayerLoaded")
AddEventHandler("QBCore:Client:OnPlayerLoaded", function()
    setRagdollGrace(10000)
    disableHealthRegen()
    fetchAndApplySavedHealth()
end)

-- ESX player loaded.
RegisterNetEvent("esx:playerLoaded")
AddEventHandler("esx:playerLoaded", function()
    setRagdollGrace(10000)
    disableHealthRegen()
    fetchAndApplySavedHealth()
end)

-- Shared spawn handler.
AddEventHandler("playerSpawned", function()
    setRagdollGrace(10000)
    disableHealthRegen()
    applyPendingSavedHealth()
end)

-- Server-side authorisation to extend the revive window.
RegisterNetEvent("amb_client:AuthorizeRevive")
AddEventHandler("amb_client:AuthorizeRevive", function(ms)
    extendReviveWindow(ms or 12000)
end)


-- ════════════════════════════════════════════════════════════
--  SetDowned / death-status network events
-- ════════════════════════════════════════════════════════════

-- Central handler: server tells us to enter or leave the downed state.
local function handleSetDeathStatus(active)
    if active then
        -- Ignore if a recent revive is in its grace period.
        if reviveTimestamp > 0 then
            local elapsed = GetGameTimer() - reviveTimestamp
            if elapsed < 10000 then
                TriggerServerEvent("amb_server:SetDowned", false)
                return
            end
        end

        if isQBCore() then
            -- QBCore: only go down if flagged by the revive window or already downed.
            if not isReviving and not isReviveWindowOpen() then
                if isDowned then
                    TriggerServerEvent("amb_server:SetDowned", true)
                end
                return
            end

            if isDowned then return end

            local ped = PlayerPedId()
            if handleQBCoreDeath(GetPedCauseOfDeath(ped)) then return end

            -- QBCore forced-down.
            isDowned     = true
            deathCounter = deathCounter + 1
            local myGen  = deathCounter
            ragdollGraceTimer = GetGameTimer() + 1000

            ensureBaselineInjury()

            local inVeh = IsPedInAnyVehicle(ped, false)
            if not inVeh then
                waitForPedToSettle()
                if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                    ped = resurrectPedInPlace(ped) or PlayerPedId()
                else return end
            else
                ped = resurrectPedInPlace(ped) or PlayerPedId()
            end

            if isDowned and deathCounter == myGen and not isReviveWindowOpen() then
                SetEntityHealth(ped, 100)
                SetEntityInvincible(ped, true)
                TriggerServerEvent("amb_server:SetDowned", true)

                TriggerEvent("amb_client:onPlayerDeath",
                    classifyDeath(GetPedCauseOfDeath(ped)))
            end

        else
            -- ESX: straightforward – call revive.
            if isDowned then
                revivePlayer()
            end
        end
    else
        -- Deactivate: leave downed state.
        if isQBCore() then
            if not isReviveWindowOpen() then
                if isDowned then TriggerServerEvent("amb_server:SetDowned", true) end
                return
            end
        end

        isDowned = false
        setDeadRestrictions(false)
        deathCounter = deathCounter + 1
    end
end

-- hospital integration.
RegisterNetEvent("hospital:client:SetDeathStatus")
AddEventHandler("hospital:client:SetDeathStatus", function(active)
    if isQBCore() then return end   -- hospital events are ESX-only
    handleSetDeathStatus(active)
end)

RegisterNetEvent("amb_client:SetDeathStatus")
AddEventHandler("amb_client:SetDeathStatus", handleSetDeathStatus)

-- External revive triggers.
RegisterNetEvent("hospital:client:Revive")
AddEventHandler("hospital:client:Revive", function()
    if isQBCore() then return end
    exports.plt_ambulance_job:RevivePlayer()
end)

RegisterNetEvent("amb_client:RevivePlayer")
AddEventHandler("amb_client:RevivePlayer", function()
    exports.plt_ambulance_job:RevivePlayer()
end)

-- Auto-revive check: called by the hospital/respawn system.
local function checkAndAutoRevive()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    if isDowned
        or IsPedDeadOrDying(ped, true)
        or GetEntityHealth(ped) <= 110
    then
        exports.plt_ambulance_job:RevivePlayer()
        return
    end

    -- Full-health with no remaining injuries → also clean up.
    if GetEntityHealth(ped) >= 200 then
        local anyInjury = false
        for _, info in pairs(injuries) do
            if type(info) == "table" and info.level > 0 then
                anyInjury = true break
            end
        end
        if anyInjury or isPatientBandaged then
            -- Still has injuries; don't auto-clear.
            return
        end
    end

    -- ESX full-heal path.
    if not isDowned then
        local health = GetEntityHealth(ped)
        if health <= 110 or IsPedDeadOrDying(ped, true) then
            local ped2 = PlayerPedId()
            TriggerServerEvent("amb_server:SetDowned", false)
            TriggerServerEvent("amb_server:cacheHealth", GetEntityHealth(ped2))
            syncInjuriesToServer()
            Framework.Notify(_L("healed"), "success")
        end
    end
end

-- Server-triggered full heal.
local function healInjuries()
    local ped = PlayerPedId()
    local pid = PlayerId()

    isDowned = false
    setDeadRestrictions(false)
    deathCounter = deathCounter + 1
    isDeadRestricted = false
    ragdollGraceTimer = 0
    isCPRActive = false
    clearInjuries()

    DetachEntity(ped, true, true)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetEntityInvincible(ped, false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPlayerControl(pid, true, 0)
    EnableAllControlActions(0)
    FreezeEntityPosition(ped, false)
    ClearPedBloodDamage(ped)
    ClearPedLastDamageBone(ped)
    ClearEntityLastDamageEntity(ped)
    restoreClothing()

    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            SetVehicleUndriveable(veh, false)
            SetVehicleEngineOn(veh, true, true, false)
        end
    end

    if isBlurActive then
        TriggerScreenblurFadeOut(500.0)
        isBlurActive = false
    end

    if isLimping then
        ResetPedMovementClipset(ped, 0)
        isLimping = false
    end

    TriggerServerEvent("amb_server:SetDowned", false)
    TriggerServerEvent("amb_server:cacheHealth", GetEntityHealth(PlayerPedId()))
    syncInjuriesToServer()
    Framework.Notify(_L("healed"), "success")
end

RegisterNetEvent("amb_client:HealInjuries")
AddEventHandler("amb_client:HealInjuries", healInjuries)

RegisterNetEvent("hospital:client:HealInjuries")
AddEventHandler("hospital:client:HealInjuries", healInjuries)


-- ════════════════════════════════════════════════════════════
--  Force-kill event
-- ════════════════════════════════════════════════════════════

RegisterNetEvent("amb_client:KillPlayer")
AddEventHandler("amb_client:KillPlayer", function()
    if isDowned then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    isReviving = false
    setRagdollGrace(0)

    if isQBCore() then
        -- QBCore: just force health to 0 and let the damage event handler take over.
        injuries.bleeding = math.max(tonumber(injuries.bleeding) or 0, 1)
        ensureBaselineInjury()
        SetEntityHealth(ped, 0)
        handleQBCoreDeath(0)
        TriggerServerEvent("amb_server:cacheHealth", 100)
        syncInjuriesToServer()
        return
    end

    -- ESX path.
    isDowned     = true
    deathCounter = deathCounter + 1
    local myGen  = deathCounter
    ragdollGraceTimer = GetGameTimer() + 1000

    ensureBaselineInjury()
    injuries.bleeding = math.max(tonumber(injuries.bleeding) or 0, 1)
    SetEntityHealth(ped, 0)

    local inVeh = IsPedInAnyVehicle(ped, false)
    if not inVeh and not isQBCore() then
        waitForPedToSettle()
        if isDowned and deathCounter == myGen then
            ped = resurrectPedInPlace(ped) or PlayerPedId()
        else return end
    else
        ped = resurrectPedInPlace(ped) or PlayerPedId()
    end

    if isDowned and deathCounter == myGen then
        ensureBaselineInjury()
        injuries.bleeding = math.max(tonumber(injuries.bleeding) or 0, 1)
        SetEntityHealth(ped, 100)
        SetEntityInvincible(ped, true)
        TriggerServerEvent("amb_server:SetDowned", true)
        TriggerServerEvent("amb_server:cacheHealth", 100)
        syncInjuriesToServer()
        TriggerEvent("amb_client:onPlayerDeath", "dead")
    end
end)


-- ════════════════════════════════════════════════════════════
--  Injury data sync
-- ════════════════════════════════════════════════════════════

-- Respond to a request for the local player's injury data.
RegisterNetEvent("amb_client:requestInjuryData")
AddEventHandler("amb_client:requestInjuryData", function()
    print("^3[VICTIM DEBUG] Sending Injury Data to EMS...^7")
    syncInjuriesToServer()
end)


-- ════════════════════════════════════════════════════════════
--  Treatment events
-- ════════════════════════════════════════════════════════════

-- Bandage drawable overrides per body part (component slot 7).
local BANDAGE_DRAWABLES = {
    chest     = 192,
    right_leg = 193,
    left_leg  = 194,
    head      = 195,
    right_arm = 196,
    left_arm  = 197,
}

-- Apply a bandage to a body part, update health, and sync.
RegisterNetEvent("amb_client:applyBandage")
AddEventHandler("amb_client:applyBandage", function(partName)
    local ped = PlayerPedId()
    if type(partName) ~= "string" then partName = "chest" end

    injuries.bleeding = 0
    isPatientBandaged = true

    if injuries[partName] and type(injuries[partName]) == "table" then
        injuries[partName].bandaged = true
    end

    -- Heal to 200 if health is between 110 and 200 and not downed.
    if not isDowned then
        local health = GetEntityHealth(ped)
        if health and health > 110 and health < 200 then
            SetEntityHealth(ped, 200)
        end
    end

    -- Apply bandage visual.
    local drawable = BANDAGE_DRAWABLES[partName]
    if drawable then
        SetPedComponentVariation(ped, 7, drawable, 0, 0)
    end

    syncInjuriesToServer()
end)

-- Self-bandage (player-initiated, with progress bar).
RegisterNetEvent("amb_client:selfBandage")
AddEventHandler("amb_client:selfBandage", function()
    local ped = PlayerPedId()
    if isDowned then return end

    CreateThread(function()
        local label = _L("applying_bandage")
        Framework.Notify(label, "primary")
        Framework.RequestAnimDict("missheistprowlprepb")
        TaskPlayAnim(ped,
            "missheistprowlprepb", "low_reach_loop",
            8.0, -8.0, 3000, 49, 0, false, false, false)

        local done = Framework.ProgressBar(label, 3000)
        ClearPedTasks(ped)

        if not done then
            Framework.Notify("Cancelled", "error")
            return
        end

        if injuries.bleeding > 0 then
            injuries.bleeding = 0
            Framework.Notify(_L("bleeding_stopped"), "success")
            syncInjuriesToServer()
        else
            Framework.Notify(_L("bandage_applied"), "info")
        end
    end)
end)

-- Heal a specific body part by a given amount (server-authorised).
RegisterNetEvent("amb_client:HealPart")
AddEventHandler("amb_client:HealPart", function(partName, amount)
    local part = injuries[partName]
    if not part then return end

    if type(part) == "table" then
        part.level = math.max(0, part.level - amount)
        if amount >= 2 then part.bullet = false end
        if part.level == 0 then
            part.bullet = false
            TriggerEvent("amb_client:Notify",
                _L("body_part_treated", { part = string.upper(partName:gsub("_", " ")) }),
                "success")
        end
    else
        injuries[partName] = math.max(0, part - amount)
        if injuries[partName] == 0 then
            TriggerEvent("amb_client:Notify",
                _L("body_part_treated", { part = string.upper(partName:gsub("_", " ")) }),
                "success")
        end
    end

    syncInjuriesToServer()
end)

-- Remove patient clothing (top or bottom) for medical access.
RegisterNetEvent("amb_client:removeClothes")
AddEventHandler("amb_client:removeClothes", function(clothingType)
    local ped    = PlayerPedId()
    local isMale = GetEntityModel(ped) ~= -1667301416  -- mp_f_freemode_01 hash

    cacheClothing(clothingType)

    if clothingType == "top" then
        if isMale then
            -- Male: topless + open shirt variant
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            SetPedComponentVariation(ped, 8,  34, 0, 0)
            SetPedComponentVariation(ped, 3,  15, 0, 0)
        else
            -- Female: bare torso
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            SetPedComponentVariation(ped, 8,  15, 0, 0)
            SetPedComponentVariation(ped, 3,  15, 0, 0)
        end
    elseif clothingType == "bottom" then
        -- Slot 4: pants
        SetPedComponentVariation(ped, 4, isMale and 15 or 21, 0, 0)
    end

    TriggerEvent("amb_client:requestInjuryData")
end)

-- Update hunger workflow: right arm de-levelled, head flagged for fludro.
RegisterNetEvent("amb_client:updateHungerWorkflow")
AddEventHandler("amb_client:updateHungerWorkflow", function()
    injuries.right_arm.level      = 0
    injuries.right_arm.hunger     = false
    injuries.head.level           = 1
    injuries.head.needsFludro     = true
    TriggerEvent("amb_client:Notify", _L("vitals_stabilized_fludro"), "info")
    TriggerEvent("amb_client:requestInjuryData")
end)

-- Fludro given: clear head level and flag.
RegisterNetEvent("amb_client:giveFludro")
AddEventHandler("amb_client:giveFludro", function()
    injuries.head.level      = 0
    injuries.head.needsFludro = false
    TriggerEvent("amb_client:Notify", _L("fludro_given"), "success")
    TriggerEvent("amb_client:requestInjuryData")
    SetEntityHealth(PlayerPedId(), 140)
end)

-- Clamp bleeding.
RegisterNetEvent("amb_client:clampBleeding")
AddEventHandler("amb_client:clampBleeding", function()
    injuries.bleeding = 0
    TriggerEvent("amb_client:Notify", _L("arterial_bleeding_controlled"), "success")
    TriggerEvent("amb_client:requestInjuryData")
end)


-- ════════════════════════════════════════════════════════════
--  CPR animation sync
-- ════════════════════════════════════════════════════════════

RegisterNetEvent("amb_client:syncCPRAnimation")
AddEventHandler("amb_client:syncCPRAnimation", function(targetSrc, role, phase)
    local ped     = PlayerPedId()
    local dict    = (role == "ems")  and "mini@cpr@char_a@cpr_str" or "mini@cpr@char_b@cpr_str"
    local clip    = (phase == "success") and "cpr_success" or "cpr_pumpchest"
    local looping = (phase ~= "success") and 1 or 0

    isCPRActive = true

    print("^3[PLT_MEDIC] CPR Animation Sync: Role=" .. role .. " Phase=" .. phase .. "^7")

    Framework.RequestAnimDict(dict)

    if not IsEntityPlayingAnim(ped, dict, clip, 3) then
        if role ~= "patient" then
            ClearPedTasks(ped)
        end
        TaskPlayAnim(ped,
            dict, clip,
            8.0, -8.0, -1, looping, 1.0, false, false, false)
    end
end)

RegisterNetEvent("amb_client:stopCPRAnimation")
AddEventHandler("amb_client:stopCPRAnimation", function()
    isCPRActive = false
    local ped   = PlayerPedId()
    ClearPedTasks(ped)

    if isDowned then
        Framework.RequestAnimDict("misslamar1dead_body")
        TaskPlayAnim(ped,
            "misslamar1dead_body", "dead_idle",
            8.0, -8.0, -1, 1, 1.0, false, false, false)
    end
end)


-- ════════════════════════════════════════════════════════════
--  Medication / item use system
-- ════════════════════════════════════════════════════════════

-- Items that can be consumed from inventory.
local USABLE_ITEMS = {
    plt_bandage        = true,
    plt_painkillers    = true,
    plt_painkillers_adv = true,
    plt_antibiotics    = true,
    plt_medkit         = true,
    iak_wheelchair     = true,
}

-- Returns true when the player has active injuries worth treating.
-- The wheelchair is always usable (helps downed players).
local function hasInjuriesForItem(itemName)
    if itemName == "iak_wheelchair" then return true end
    if isDowned then return false end

    if injuries.bleeding and injuries.bleeding > 0 then return true end

    for _, info in pairs(injuries) do
        if type(info) == "table" then
            if (info.level and info.level > 0) or info.bullet or info.isFractured then
                return true
            end
        end
    end

    return GetEntityHealth(PlayerPedId()) < 200
end

-- Returns true when an item is allowed to be used right now.
local function canUseItem(itemName)
    if itemName == "iak_wheelchair" then return true end
    if isDowned then return false end
    return hasInjuriesForItem(itemName)
end

-- Shared use-medication handler (both inventory export and net event).
local function applyMedication(ped, itemName, slotData)
    -- iak_wheelchair is a special case: trigger wheelchair logic.
    if itemName == "iak_wheelchair" then
        local duration = slotData and slotData.duration
        if not duration then
            -- Try to find the item in player data.
            local pd = Framework.GetPlayerData()
            if pd and pd.items then
                for _, item in pairs(pd.items) do
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

    -- Determine healing power for this item.
    -- healLevels = how many injury levels per part are reduced
    -- healCap    = maximum injury level this item can treat
    local healLevels, healCap = 1, 5
    if     itemName == "plt_painkillers"     then healLevels = 1; healCap = 1
    elseif itemName == "plt_painkillers_adv" then healLevels = 4; healCap = 5
    elseif itemName == "plt_antibiotics"     then healLevels = 2; healCap = 5
    elseif itemName == "plt_medkit"          then healLevels = 3; healCap = 5
    end

    local healed       = false
    local tooSevere    = false

    for _, info in pairs(injuries) do
        if type(info) == "table" and info.level and info.level > 0 then
            if healCap >= info.level then
                info.level = math.max(0, info.level - healLevels)
                if info.level == 0 then
                    info.bullet   = false
                    info.bandaged = false
                end
                healed = true
            else
                tooSevere = true
            end
        end
    end

    -- Clear bleeding.
    if injuries.bleeding and injuries.bleeding > 0 then
        injuries.bleeding = 0
        healed = true
    end

    -- Restore some health.
    local health = GetEntityHealth(ped)
    if health < 200 then
        local gain = healLevels * 20
        SetEntityHealth(ped, math.min(200, health + gain))
        healed = true
    end

    if healed then
        Framework.Notify(_L("injuries_feel_better"), "success")
        if itemName == "plt_medkit" then
            ClearPedBloodDamage(ped)
            ClearPedLastDamageBone(ped)
        end
        syncInjuriesToServer()
    elseif tooSevere and itemName == "plt_painkillers" then
        Framework.Notify(_L("otc_too_weak"), "error")
    end
end

-- `plt_use_medication` export: called by ox_inventory / QS-inventory.
exports("plt_use_medication", function(itemData, slotData)
    local itemName = itemData and itemData.name
    if not itemName or not USABLE_ITEMS[itemName] then return end

    if isDowned and itemName ~= "iak_wheelchair" then
        Framework.Notify(_L("cannot_use_incapacitated"), "error")
        return
    end

    if not canUseItem(itemName) then
        if itemName == "plt_bandage" then
            Framework.Notify(_L("not_bleeding_now"), "info")
        else
            Framework.Notify(_L("no_injuries_to_treat"), "info")
        end
        return
    end

    if itemName == "iak_wheelchair" then
        local duration = itemData.metadata and itemData.metadata.duration
        TriggerEvent("amb_client:useWheelchair", duration)
        TriggerServerEvent("amb_server:consumeMedication", itemName, slotData, true)
        return
    end

    if GetResourceState("ox_inventory") == "started" then
        TriggerServerEvent("amb_server:consumeMedication", itemName, slotData, true)
    else
        TriggerEvent("amb_client:useMedication", itemName)
    end
end)

-- Net event: actually apply the medication to the ped.
RegisterNetEvent("amb_client:useMedication")
AddEventHandler("amb_client:useMedication", function(itemName, slotData)
    local ped = PlayerPedId()

    if isDowned and itemName ~= "iak_wheelchair" then
        Framework.Notify(_L("cannot_use_incapacitated"), "error")
        return
    end

    if not canUseItem(itemName) then
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

    -- Play taking-medication animation.
    CreateThread(function()
        local label    = _L("taking_medication")
        local duration = 3000
        local animDict = "mp_suicide"
        local animClip = "pill"

        if itemName == "plt_medkit" then
            label    = _L("applying_first_aid")
            duration = 5000
            animDict = "missheistprowlprepb"
            animClip = "low_reach_loop"
        end

        Framework.Notify(label, "primary")
        Framework.RequestAnimDict(animDict)
        TaskPlayAnim(ped, animDict, animClip,
            8.0, -8.0, duration, 49, 0, false, false, false)

        local done = Framework.ProgressBar(label, duration)
        ClearPedTasks(ped)

        if not done then
            Framework.Notify("Cancelled", "error")
            return
        end

        applyMedication(ped, itemName, slotData)
    end)
end)


-- ════════════════════════════════════════════════════════════
--  Debug commands
-- ════════════════════════════════════════════════════════════

-- /hungerdie – simulate a hunger-related downed event for testing.
RegisterCommand("hungerdie", function()
    local ped = PlayerPedId()
    isDowned  = true
    injuries.right_arm.level  = 2
    injuries.right_arm.hunger = true
    SetEntityHealth(ped, 100)
    SetEntityInvincible(ped, true)
    TriggerServerEvent("amb_server:SetDowned", true)
    Framework.Notify(_L("hunger_test_triggered"), "info")
end, false)
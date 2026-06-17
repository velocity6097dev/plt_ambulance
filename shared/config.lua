Config = {}

Config.UseLicenseWhitelist = false -- Optional: set true to allow access via listed licenses
Config.LicenseWhitelist = {
    "license:10c57617ce5982ee5ebf96fe806a7a96f43f4560",
}

Config.CommandName = "manageems" -- Command to open the UI
Config.Permission = "admin"        -- Permission level to use the command
Config.AdminBypass = false           -- If true, admins bypass all rank/duty restrictions for testing
Config.ShowNotifications = true    -- Set to false to disable all internal notifications
Config.EnableBlurEffect = true     -- true = enable UI/injury blur, false = disable blur effects

Config.MDT = {
    enabled = false, -- Medical usually doesn't link to police MDT BOLOs
    type = 'export', 
}

-- Target System Configuration
Config.Target = "ox_target" -- Options: "ox_target" or "qb-target"

Config.DefaultNodes = {
    departments = {
        { id = 'ambulance', label = 'Ambulance', type = 'department' },
        { id = 'fire', label = 'Fire Dept', type = 'department' },
    },
    permissions = {
        { id = 'garage', label = 'Access Garage', type = 'permission' },
        { id = 'vault', label = 'Open Safe', type = 'permission' },
    }
}

Config.Inventory = "ox" -- Options: "qb", "ox", "tgiann", "quasar", "origin", "core"
Config.InventoryImages = "nui://ox_inventory/web/images/" -- OX: "nui://ox_inventory/web/images/" | QB/Tgiann/Quasar/Origin/Core: use your inventory image path

Config.EMSItems = {
    first_kit = {
        { name = "plt_medkit", label = "Medkit", icon = "plt_medkit.png", weight = 500 },
        { name = "plt_bandage", label = "Bandage", icon = "plt_bandage.png", weight = 100 },
        { name = "plt_painkillers", label = "Painkillers", icon = "plt_painkillers.png", weight = 50 },
    },
    operations = {
        { name = "plt_surgical_kit", label = "Surgical Kit", icon = "plt_surgical_kit.png", weight = 1000 },
        { name = "plt_stretcher", label = "Stretcher", icon = "plt_stretcher.png", weight = 5000 },
        { name = "plt_oxygen_mask", label = "Oxygen Mask", icon = "plt_oxygen_mask.png", weight = 300 },
        { name = "plt_surgical_scissors", label = "Surgical Scissors", icon = "plt_surgical_scissors.png", weight = 200 },
    },
    equipments = {
        { name = "plt_radio", label = "Radio", icon = "plt_radio.png", weight = 200 },
        { name = "plt_flashlight", label = "Flashlight", icon = "plt_flashlight.png", weight = 500 },
        { name = "plt_fireextinguisher", label = "Fire Extinguisher", icon = "plt_fireextinguisher.png", weight = 2000 },
        { name = "plt_medical_bag", label = "Medical Bag", icon = "plt_medical_bag.png", weight = 2000 },
        { name = "plt_bp_monitor", label = "BP Monitor", icon = "plt_bp_monitor.png", weight = 500 },
    }
}

Config.Pharmacy = {
    Locations = {
        { coords = vector3(311.2, -594.3, 43.3), heading = 10.0, label = "Pillbox Medical Pharmacy" },
        { coords = vector3(1831.5, 3677.4, 34.3), heading = 210.0, label = "Sandy Shores Clinic" },
        { coords = vector3(-246.8, 6330.5, 32.4), heading = 315.0, label = "Paleto Bay Medical" }
    },
    Insurance = {
        Price = 5000, -- Cost to buy medical insurance
        Discount = 0.5, -- 50% off
        Duration = 7, -- Days (RP wise, we can track this or keep it permanent until reset)
    },
    Items = {
        { name = "plt_bandage", label = "Elastic Bandage", price = 50, professionalOnly = false, prescriptionRequired = false, icon = "plt_bandage.png" },
        { name = "plt_painkillers", label = "Painkillers (OTC)", price = 150, professionalOnly = false, prescriptionRequired = false, icon = "plt_painkillers.png" },
        -- { name = "plt_painkillers_adv", label = "Advanced Painkillers", price = 350, professionalOnly = false, prescriptionRequired = true, icon = "plt_painkillers_adv.png" },
        { name = "plt_antibiotics", label = "Antibiotics", price = 500, professionalOnly = false, prescriptionRequired = true, icon = "plt_antibiotics.png" },
        { name = "plt_medkit", label = "Advanced First Aid Kit", price = 1200, professionalOnly = false, prescriptionRequired = true, icon = "plt_medkit.png" },
        -- { name = "plt_surgical_kit", label = "Field Surgical Kit", price = 2500, professionalOnly = true, prescriptionRequired = false, icon = "plt_surgical_kit.png" },
        { name = "plt_surgical_scissors", label = "Surgical Scissors", price = 300, professionalOnly = true, prescriptionRequired = false, icon = "plt_surgical_scissors.png" },
        { name = "plt_bp_monitor", label = "Digital BP Monitor", price = 850, professionalOnly = true, prescriptionRequired = false, icon = "plt_bp_monitor.png" },
        { name = "plt_medical_bag", label = "EMS Field Bag", price = 1500, professionalOnly = true, prescriptionRequired = false, icon = "plt_medical_bag.png" },
        { name = "iak_wheelchair", label = "Wheelchair", price = 2500, professionalOnly = false, prescriptionRequired = true, icon = "wheelchair.png" }
    }
}

Config.WheelchairItemName = "iak_wheelchair" -- The item name in your inventory
Config.WheelchairDuration = 10 -- How many minutes the wheelchair stays before disappearing


Config.RadioCodes = {
    { label = "AVAIL", code = "10-8" },
    { label = "EN ROUTE", code = "10-97" },
    { label = "ON SCENE", code = "10-23" },
    { label = "BUSY", code = "10-6" },
    { label = "OFF DUTY", code = "10-7" },
    { label = "HOSPITAL", code = "10-15" },
    { label = "RTB", code = "10-19" },
}

Config.MoneyAsItem = true 
Config.MoneyItemName = "cash" 
Config.DefaultDeptBalance = 500000

-- Department finance: "internal" or "Renewed-Banking"
Config.DepartmentFinance = "internal"

Config.EMSInvoice = {
    CommandName = "emsinvoice",
    PayCommandName = "payemsinvoice",
    DeclineCommandName = "declineemsinvoice",
    MaxDistance = 8.0,
    ExpireMinutes = 10,
    MaxAmount = 100000,
    PaymentAccounts = { "bank", "cash" }
}

-- Health & Injury System
Config.Health = {
    DownedThreshold = 0,      -- Health at which player enters downed state (0 = standard death)
    BleedChance = 40,         -- Percentage chance to start bleeding on hit
    BleedInterval = 2000,     -- Damage interval in MS
    BleedDecalMin = 2,        -- Min bleeding level to start leaving blood on floor
    MaxInjuryLevel = 5,       -- Max level for a specific body part injury
    DeathTimer = 300,         -- Time in seconds before bleeding out (default 5 mins)
    UnconsciousTimer = 30,    -- Time in seconds before waking up from punch-only knockout
    CallEMSTimer = 0,        -- Seconds to wait before being able to call EMS (press G)
    HospitalTransportDelay = 120, -- Seconds before "Go To Hospital" is allowed on death screen
    
    -- Bleeding Settings
    BleedChance = 40,         -- Percentage chance to start bleeding on hit
    BleedInterval = 2000,     -- Damage interval in MS
    BleedRate = 1,            -- Health lost per interval (set to 0 to disable persistent bleeding damage)
    BulletBleedChance = 90,   -- Chance to start bleeding when hit by a bullet
    BleedDecalMin = 2,        -- Min bleeding level to start leaving blood on floor
    
    -- Bone Fracture Settings
    FractureChance = 80,     -- % chance to break a bone on fatal fall/car hit
    FractureTime = 600,      -- Seconds (10 mins) the fracture lasts if not treated by EMS
    LimpAnimation = "move_m@limping@a", -- Animation clip set for leg fractures

    -- Restrictions while player is dead/downed
    DeadRestrictions = {
        DisableVoice = true,     -- Mute player voice while downed; restored on revive
        DisableInventory = true  -- Blocks inventory usage while downed; restored on revive
    }
}

-- Built-in deathscreen toggle.
-- true  = use plt_ambulance_job deathscreen UI/logic
-- false = disable built-in deathscreen so you can use another deathscreen script
Config.Deathscreen = {
    UseBuiltIn = true
}

-- Local NPC Doctor (when EMS are off duty)
Config.LocalDoctor = {
    HealTime = 15000, -- Time in MS to be healed by Local Doctor
    LieAnim = { dict = "amb@world_human_sunbathe@male@back@base", name = "base" }, -- Emote while being treated
    DoctorPedModel = "s_m_m_doctor_01", -- Ped model for Local Doctor NPC
}

-- Medical Interactions
Config.Medical = {
    EMSJobs = { 'ambulance', 'fire' }, -- Jobs allowed to use medical target options
    DiagnosisTime = 3000,              -- Time to diagnose in MS
    ReviveTime = 10000,                -- Time to revive in MS
    TreatmentTime = 5000,              -- Time to apply basic treatment in MS
}

-- Fernocot / Ambulance Bed (from vehicle trunk)
Config.FernocotModel = "fernocot" -- Model name of the ambulance bed prop
-- Vehicle models that have the bed in trunk. Add the exact spawn name from your vehicle node (e.g. ambulance, ems_ambulance).
Config.FernocotVehicleModels = { 'ambulance', 'firetruk', 'ambulance2' }
-- Player position when lying on bed (offset from bed center).
Config.FernocotLieOffset = { x = 0.020, y = 0.000, z = 2.100 }
-- Lie pose: vanilla GTA5 animations. Alternatives: savecouch@/t_sleep_loop_couch, misslamar1dead_body/dead_idle
Config.FernocotLieAnim = { dict = "amb@world_human_sunbathe@male@back@base", name = "base" }
-- Heading offset when lying (degrees). 0 = feet toward bed head.
Config.FernocotLieHeading = 86.0
-- Drag offset: bed IN FRONT of player (positive Y = forward). Like pushing a stretcher.
Config.FernocotDragOffset = { x = -0.190, y = 1.520, z = -0.960 }
Config.FernocotDragRotation = { x = 0.0, y = 1.0, z = 96.0 }

-- Fake Players for Display
Config.ShowFakePlayers = true
Config.FakePlayers = {
    { cid = "FAKE_1", name = "Dr. John Doe", jobLabel = "Ambulance", jobGradeLabel = "Chief", jobName = "ambulance", jobGradeLevel = 5, isOnline = true },
    { cid = "FAKE_2", name = "Jane Smith", jobLabel = "Ambulance", jobGradeLabel = "Paramedic", jobName = "ambulance", jobGradeLevel = 2, isOnline = false },
    { cid = "FAKE_3", name = "Mike Miller", jobLabel = "Fire Dept", jobGradeLabel = "Captain", jobName = "fire", jobGradeLevel = 4, isOnline = true },
}

-- Localization (translate all values below)
Config.Locale = {
    -- Generic
    hospital = "Hospital",

    -- Notification titles
    notify_title_alert = "MEDICAL ALERT",
    notify_title_error = "MEDICAL ERROR",
    notify_title_success = "MEDICAL SUCCESS",
    notify_title_info = "MEDICAL INFO",
    notify_title_warning = "MEDICAL WARNING",

    -- Permissions / labels
    permission_duty = "Duty",
    permission_garage = "Garage",
    permission_inventory = "Inventory",
    permission_stash = "Stash",
    permission_boss_menu = "Boss Menu",
    permission_xray = "X-Ray",

    -- Target labels / prompts
    checkin_local_doctor = "Check In (Local Doctor)",
    checkin_title_default = "HOSPITAL CHECK-IN",
    checkin_title_fatal = "FATAL INJURY - Hospital Check-in",
    checkin_title_severe = "SEVERE INJURY - Hospital Check-in",
    checkin_title_minor = "MINOR INJURY - Hospital Check-in",
    pharmacy_terminal = "Access Pharmacy Terminal",
    monitor_toggle = "Toggle Vitals Monitor",
    bed_lie = "Lie on Bed",
    xray_terminal = "Access X-Ray Terminal",
    garage_title_suffix = " GARAGE",
    store_vehicle_prompt = "[E] Store Vehicle",

    -- Placement UI
    placement_header = "SET LOCATION",
    placement_confirm = "SET POSITION",
    placement_rotate = "ROTATE",
    placement_no_rotate = "NO ROTATION",

    -- Main / duty / interaction
    local_doctor_busy = "Local Doctor is busy. Please contact one of the {count} medics on duty.",
    local_doctor_treating = "Being treated by Local Doctor... Press [X] to cancel",
    treatment_cancelled = "Treatment cancelled.",
    healed = "You have been healed.",
    monitor_state = "Monitor turned {state}",
    monitor_state_on = "ON",
    monitor_state_off = "OFF",
    lying_on_bed_exit = "Lying on bed - Press [X] to stand up",
    spawn_blocked = "All spawn points are blocked!",
    vehicle_spawned = "Vehicle spawned!",
    vehicle_stored = "Vehicle stored!",
    command_no_permission = "You do not have permission to use this command!",
    not_your_department = "This is not your department!",
    no_garage_access = "You don't have access to this garage!",
    no_inventory_access = "You don't have access to the department inventory!",

    -- Dispatch / deathscreen
    authorized_only = "Authorized personnel only.",
    dispatch_locked = "Dispatch position locked.",
    gps_set = "GPS set to call location.",
    patient_downed = "PATIENT DOWNED",
    ems_notified = "EMS has been notified of your location.",
    wait_before_calling = "You must wait before calling EMS ({seconds}s)",
    transported_to_hospital = "You have been transported to hospital.",
    no_checkin_bed = "No hospital check-in bed is configured.",
    transport_available_in = "Hospital transport available in {seconds}s",

    -- Diagnosis
    diagnosis_no_patient_id = "Could not detect patient ID. Try again.",
    diagnosis_preparing = "Preparing diagnosis view...",
    diagnosis_remove_clothing = "You must remove the patient's {clothingType} before {action}!",
    diagnosis_action_surgery = "surgery",
    diagnosis_action_treatment = "treatment",
    diagnosis_need_item = "You need a {item} to do this!",
    diagnosis_item_supplies = "Medical Supplies",
    diagnosis_no_significant = "No significant injuries detected.",
    diagnosis_info_fracture = "CRITICAL: Bone fracture detected. Estimated healing time: {mins}:{secs}",
    diagnosis_info_bullet = "CRITICAL: Foreign projectile (bullet) detected deep within the muscle tissue. Immediate extraction required.",
    diagnosis_info_fludro = "Patient requires immediate Fludrocortisone administration to manage blood pressure.",
    diagnosis_info_hunger = "Patient is suffering from severe malnutrition and dehydration.",
    diagnosis_info_level5 = "CRITICAL: Multiple fractures and severe internal damage.",
    diagnosis_info_level3 = "SEVERE: Deep lacerations and potential bone cracks.",
    diagnosis_info_level1 = "MINOR: Bruising and superficial wounds.",
    diagnosis_part_bandaged = "[PART BANDAGED]",
    diagnosis_wound_treated = "Wound sutured and treated!",
    diagnosis_bp_stable = "Blood pressure stabilized.",
    diagnosis_bleeding_clamped = "Bleeding source clamped successfully!",
    diagnosis_need_bandage = "You need a Bandage!",
    diagnosis_bandage_applied = "Bandage applied securely!",
    diagnosis_bullet_extracted = "Bullet extracted!",
    diagnosis_cpr_success = "Resuscitation successful!",
    diagnosis_need_scissors = "You need Surgical Scissors!",
    diagnosis_progress_fludro = "Administering Fludrocortisone",
    body_head = "Head",
    body_chest = "Chest",
    body_left_arm = "Left Arm",
    body_right_arm = "Right Arm",
    body_left_leg = "Left Leg",
    body_right_leg = "Right Leg",
    clothing_top = "TOP",
    clothing_bottom = "BOTTOM",
    item_medkit = "Medkit",
    item_surgical_kit = "Surgical Kit",
    item_bp_monitor = "BP Monitor",

    -- Health / medication
    cannot_use_incapacitated = "You cannot use this while incapacitated!",
    not_bleeding_now = "You are not bleeding right now.",
    no_injuries_to_treat = "You don't have any injuries to treat!",
    taking_medication = "Taking medication...",
    applying_first_aid = "Applying first aid...",
    injuries_feel_better = "Your injuries feel better.",
    otc_too_weak = "These OTC painkillers are too weak for your severe trauma. You need a prescription!",
    applying_bandage = "Applying bandage...",
    bleeding_stopped = "Bleeding stopped!",
    bandage_applied = "You applied a bandage.",
    hunger_test_triggered = "TEST: Hunger Death simulated. Right arm injured.",
    fracture_healed = "Your {part} fracture has healed.",
    body_part_treated = "{part} treated.",
    vitals_stabilized_fludro = "Vitals stabilized. Administer Fludrocortisone via head.",
    fludro_given = "Fludrocortisone administered. Patient recovery starting.",
    arterial_bleeding_controlled = "Arterial bleeding controlled.",

    -- Medical interactions (fernocot)
    bed_released = "Bed released.",
    bed_get_off = "Get off Bed",
    bed_drag = "Drag Bed",
    bed_remove = "Remove Bed",
    diagnose_injuries = "Diagnose Injuries",
    bed_take_out = "Take out Bed",
    bed_put_back_in = "Put Bed back in",
    got_off_bed = "You got off the bed.",
    release_bed_prompt = "Press [E] to release the bed",
    bed_removed = "Ambulance bed removed.",
    bed_takeout_failed = "Failed to take out bed.",
    bed_put_back = "Bed put back in trunk.",
    no_bed_nearby = "No bed nearby to put back.",
    checking_vitals = "Checking patient vitals...",
    patient_vitals_result = "Patient has severe leg fractures and minor bleeding.",
    performing_cpr = "Performing CPR...",
    player_revived = "Player revived!",
    progress_revive_player = "Reviving Player",
    progress_apply_treatment = "Applying Treatment",

    -- Medical bag
    already_holding_bag = "You are already holding a bag!",
    drop_bag_prompt = "Press [E] to drop the bag",
    must_hold_bag_edit = "You must be holding a bag to edit it!",
    bag_edit_mode = "Bag Edit Mode: Use Keys to adjust. [ENTER] to save.",
    bag_edit_instructions = "ARROWS: X/Y | Q/Z: Height | NUM7/8/4/5/6/9: ROT | SHIFT: Fast\n{info}\nPRESS [ENTER] TO FINISH",
    bag_netid_missing = "Could not identify bag network ID",
    bag_position_saved = "Position saved to F8 Console!",
    open_medical_bag = "Open Medical Bag",
    pickup_medical_bag = "Pick Up Bag",

    -- Server/admin/pharmacy
    config_saved_synced = "Configuration Saved and Synced!",
    received_item = "Received {item}",
    cannot_carry_more_item = "Cannot carry more of this item!",
    duty_now = "You are now {status} duty.",
    duty_status_on = "ON",
    duty_status_off = "OFF",
    no_command_permission = "You do not have permission to use this command.",
    setjob_usage = "Usage: /setjob <playerId> <jobName> <grade>",
    player_not_found = "Player not found.",
    setjob_success = "Set {name} to job {job} grade {grade}.",
    bled_out = "You have bled out...",
    insurance_purchased = "You have purchased medical insurance!",
    not_enough_cash = "You don't have enough cash!",
    item_not_found = "Item not found.",
    authorized_only_bang = "Authorized personnel only!",
    not_enough_prescriptions = "Not enough valid prescriptions!",
    purchase_successful = "Purchase successful: {label}{qty}",
    prescription_issued_to = "Prescription issued to {name}",
    prescription_received = "A doctor has issued you a medical prescription.",
    cannot_carry_this_much = "You cannot carry this much!",
    bag_is_full = "The bag is full!",
    not_authorized_funds = "You are not authorized to manage department funds!",
    deposited_funds = "Deposited ${amount} to department funds.",
    not_enough_cash_short = "You don't have enough cash!",
    not_enough_department_funds = "Not enough funds in department account!",
    withdrew_funds = "Withdrew ${amount} from department funds.",
    not_authorized = "Not authorized!",
    insurance_cancelled_by_department = "Your medical insurance has been cancelled by the department.",
    insurance_subscription_cancelled = "Insurance subscription cancelled.",
    boss_menu_data_error = "Error: Could not retrieve boss menu data.",
    ems_invoice_usage = "Usage: /{command} <patientId> <amount> <reason>",
    ems_invoice_bad_amount = "Invoice amount must be between $1 and ${max}.",
    ems_invoice_no_reason = "Please include a reason for this invoice.",
    ems_invoice_too_far = "You must be near the patient to send an invoice.",
    ems_invoice_sent = "Invoice #{id} sent to {name} for ${amount}.",
    ems_invoice_received = "{department} invoice #{id}: ${amount} for {reason}. Pay with /{payCommand} {id} or decline with /{declineCommand} {id}.",
    ems_invoice_none = "You do not have a pending EMS invoice.",
    ems_invoice_not_found = "That EMS invoice was not found or has expired.",
    ems_invoice_paid_patient = "Paid EMS invoice #{id} for ${amount}.",
    ems_invoice_paid_ems = "{name} paid EMS invoice #{id} for ${amount}.",
    ems_invoice_declined_patient = "Declined EMS invoice #{id}.",
    ems_invoice_declined_ems = "{name} declined EMS invoice #{id}.",
    ems_invoice_no_money = "You do not have enough money to pay this EMS invoice.",
    ems_invoice_finance_error = "Payment failed because department finances could not be updated.",
    -- Web/NUI locale
    ui_type = "Type",
    ui_location = "Location",
    ui_unknown = "Unknown",
    ui_injury = "Injury",
    ui_injury_fatal = "Fatal (Downed)",
    ui_injury_severe = "Severe (Bleeding)",
    ui_injury_minor = "Minor",
    ui_incoming_call = "INCOMING CALL",
    ui_station_clear = "STATION CLEAR",
    ui_unknown_call = "Unknown Call",
    ui_location_unknown = "Location Unknown",
    ui_now = "NOW",
    ui_direction_key = "E Direction",
    ui_dismiss_key = "Y Dismiss",
    ui_you_are = "YOU ARE",
    ui_unconscious = "UNCONSCIOUS",
    ui_dead = "DEAD",
    ui_critical = "CRITICAL",
    ui_go_hospital_key = "GO TO HOSPITAL [Y]",
    ui_go_hospital_wait = "GO TO HOSPITAL ({seconds}s) [Y]",
    ui_no_pulse_flatline = "NO PULSE - FLATLINE",
    ui_stable_vitals = "STABLE VITALS",
    ui_weak_pulse = "WEAK PULSE",
    ui_notify_medics = "Notify Medics",
    ui_ems_notified = "EMS Notified",
    ui_active = "ACTIVE",
    ui_activate = "ACTIVATE",
    ui_add_to_cart = "Add to Cart",
    ui_claim_presc = "Claim Presc",
    ui_medical_dispatch = "MEDICAL DISPATCH",
    ui_dept_garage = "DEPT GARAGE",
    ui_units_count = "0 UNITS",
    ui_units_template = "{count} UNITS",
    ui_owner = "OWNER",
    ui_chassis = "CHASSIS",
    ui_reason = "REASON",
    ui_not_available = "N/A",
    ui_retrieval_fee = "RETRIEVAL FEE",
    ui_impounded = "IMPOUNDED",
    ui_ready = "READY",
    ui_export_configuration = "EXPORT CONFIGURATION",
    ui_copy_json_data = "COPY THIS JSON DATA",
    ui_config_exported = "Configuration Exported",
    ui_status = "Status",
    ui_copied_clipboard = "Copied to Clipboard!",
    ui_import_configuration = "IMPORT CONFIGURATION",
    ui_paste_json_data = "PASTE JSON DATA HERE",
    ui_config_appended = "Configuration Appended",
    ui_nodes_pasted = "Nodes and links pasted into view!",
    ui_import_failed = "Import Failed",
    ui_error = "Error",
    ui_invalid_config_format = "Invalid configuration format (no nodes found)",
    ui_invalid_json_string = "Invalid JSON string"
}

function _L(key, vars)
    local template = (Config.Locale and Config.Locale[key]) or key
    if not vars then return template end

    for varKey, varValue in pairs(vars) do
        template = template:gsub("{" .. tostring(varKey) .. "}", tostring(varValue))
    end
    return template
end



# PLT Ambulance Job Exports

## Full setup guide for creating a new Ambulance department

This section explains exactly how to create a **new medical job/department** that works with `plt_ambulance_job` (and `plt_xray`) on QB/QBox or ESX.

If something does not work, it is almost always one of these:
- Framework job name does not match the department mapping.
- Rank levels do not match framework grades.
- Nodes are not linked correctly in the manager graph.
- Permissions are not enabled for the right rank.

---

## 1) Framework requirements (job + grades must exist first)

You must create the job in your framework **before** configuring it in the manager UI.

### QB / QBox
- Add your job to framework job definitions (`qb-core/shared/jobs.lua` or your QBox jobs file).
- Example job keys: `ambulance`, `fire`, `ems_north`.
- Add all grades with numeric levels (`0`, `1`, `2`, ...).
- Those grade numbers must match the rank levels you set in the Ambulance Job manager.

### ESX
- Add job and job grades in `jobs`/`job_grades` DB tables (or your ESX job setup).
- Grade numbers must also match the manager rank levels.

Important:
- `plt_ambulance_job` applies hires/promotions with `SetJob(job, grade)`.
- If the framework job/grade does not exist, hires/promotions will fail or become inconsistent.

---

## 2) Core config values you must set

In `plt_ambulance_job/shared/config.lua`:
- `Config.Permission` = admin group allowed to open `/manageems` and edit org data.
- `Config.AdminBypass` = if `true`, admins bypass rank/duty restrictions (testing mode).
- `Config.Medical.EMSJobs` = quick allow-list for EMS logic (`IsEMS` checks this too).

For a new medical job, add its framework job name to `Config.Medical.EMSJobs` when needed.

Example:
```lua
Config.Medical = {
    EMSJobs = { 'ambulance', 'fire', 'ems_north' },
    DiagnosisTime = 3000,
    ReviveTime = 10000,
    TreatmentTime = 5000,
}
```

---

## 3) Open manager and create the department graph

Use:
- `/manageems` (command from `Config.CommandName`)

This UI stores:
- `nodes` (department/rank/location/permissions/etc.)
- `links` (how nodes are connected)

Data is saved to DB key `departments` in table `plt_ambulance_job_data`.

---

## 4) Exact node/link structure you should build

For each new department, use this minimum structure:

1. `department` node  
2. `rank` node  
3. `permission` node  
4. operational nodes (duty, garage, inventory, stash, boss_menu, xray, check_in, vehicle, helipad, etc.)

### Required links (important)

- Link `department` <-> `rank`
- Link `rank` <-> `permission`
- Link every operational node to the same department branch (directly or through linked nodes)

Recommended clean layout:
- `department` -> `rank` -> `permission`
- `department` -> `location`
- `location` -> `duty`
- `location` -> `garage` / `vehicle`
- `location` -> `inventory` / `stash`
- `location` -> `boss_menu`
- `location` -> `xray`
- `location` -> `check_in`

Why this matters:
- Department ownership is resolved by graph connectivity (`GetDepartmentForNode`).
- Permission checks read rank + permission node (`HasPermissionForNode`).
- If a node is not connected to the right department branch, access checks will fail.

---

## 5) Department ID, framework job mapping, and rank mapping

Inside the `department` node:
- `id` = internal department id used by this script.
- `frameworkJob` = real framework job name used for `SetJob`.

Rules:
- If `frameworkJob` is empty, script falls back to department `id`.
- If your framework job name is different from department id, you must set `frameworkJob`.

Example:
- Department node id: `ems_north_division`
- Framework job: `ambulance`

Then hires/promotions still work because script maps department -> framework job internally.

### Rank mapping (very important)
- In rank node, each rank needs numeric `level`.
- `level` must equal framework grade index.
- Example: Intern=0, EMT=1, Paramedic=2, Doctor=3, Chief=4.

If level mismatch happens, members get wrong grade/permissions.

---

## 6) Permission setup by rank (what to enable)

Permissions are rank-based in the `permission` node (`rankPerms`), and key labels map to:
- Duty
- Garage
- Inventory
- Stash
- Boss Menu
- X-Ray

Boss access can be controlled in two places:
- rank entry (`bossMenu = true`) in rank node
- permission node boss-menu entry

Recommended minimum:
- Low ranks: Duty, basic Garage
- Mid ranks: Inventory/Stash/X-Ray
- High ranks: Boss Menu + finance actions

---

## 7) Duty and access behavior

How access works in runtime:
- Player must belong to department (framework job or script member data).
- Player must pass rank permission for that node type.
- For most interactions, player must be on duty.
- `duty` interaction is the exception (allows toggling duty state).

So if a player sees no interactions:
- Check job/department mapping.
- Check rank permission toggles.
- Check they are on duty.
- Check AdminBypass if testing as admin.

---

## 8) Hiring and syncing members

You can hire from the UI (online/offline) or admin command:
- `/setjob <playerId> <jobName> <grade>`

Notes:
- `jobName` should be the department id used by manager (script maps it to framework job).
- Grade must be numeric and match rank levels.
- Member data is stored in `plt_ambulance_job_members`.

---

## 9) X-Ray integration: exactly what must link with what

`plt_xray` gets patient/injury data from `plt_ambulance_job` events/exports.

For X-Ray to work in your new department:

1. Keep `plt_ambulance_job` and `plt_xray` both started.
2. Create an `xray` node in manager.
3. In that xray node, set both placement points:
   - `pc` (computer)
   - `bed` (scan bed)
4. Ensure the xray node is linked into your department branch.
5. Enable X-Ray permission for ranks that should use it.
6. Ensure those ranks can go on duty.

When linked correctly:
- Ambulance manager pushes xray node coords to `plt_xray` (`updateConfigFromNode`).
- X-Ray terminal opens only for allowed on-duty ranks.
- X-Ray save writes into `plt_ambulance_job_xrays`.

---

## 10) Quick validation checklist

After setup, verify in this order:
- Framework job exists with all grades.
- Department node has correct `id` and `frameworkJob`.
- Rank levels match framework grade numbers.
- Graph links are correct (`department -> rank -> permission`).
- Operational nodes are connected to the same department branch.
- Permission toggles are enabled for expected ranks.
- Player hired to department and set to valid grade.
- Player toggles on duty and sees interaction targets.
- X-Ray node has both `pc` and `bed` points and proper permissions.

If all above are correct, the new ambulance department will function fully.

---

## Client Exports

### `isPlayerDead(serverId)`
```lua
exports[''plt_ambulance_job'']:isPlayerDead(serverId)
```

### `diagnosePlayer(targetPlayer)`
```lua
exports[''plt_ambulance_job'']:diagnosePlayer(targetPlayer)
```

### `treatPatient(injury)`
```lua
exports[''plt_ambulance_job'']:treatPatient(injury)
```

### `reviveTarget()`
```lua
exports[''plt_ambulance_job'']:reviveTarget()
```

### `healTarget()`
```lua
exports[''plt_ambulance_job'']:healTarget()
```

### `useSedative()`
```lua
exports[''plt_ambulance_job'']:useSedative()
```

### `placeInVehicle()`
```lua
exports[''plt_ambulance_job'']:placeInVehicle()
```

### `loadStretcher()`
```lua
exports[''plt_ambulance_job'']:loadStretcher()
```

### `openOutfits(hospital)`
```lua
exports[''plt_ambulance_job'']:openOutfits(hospital)
```

### `deleteStretcherFromVehicle(vehicle)`
```lua
exports[''plt_ambulance_job'']:deleteStretcherFromVehicle(vehicle)
```

### `isPlayerUsingStretcher(playerClientId)`
```lua
exports[''plt_ambulance_job'']:isPlayerUsingStretcher(playerClientId)
```

### `clearPlayerInjury(clearVitals)`
```lua
exports[''plt_ambulance_job'']:clearPlayerInjury(clearVitals)
```

### `disableKnockoutLoop(disabled)`
```lua
exports[''plt_ambulance_job'']:disableKnockoutLoop(disabled)
```

### `manuallyKnockout(enabled)`
```lua
exports[''plt_ambulance_job'']:manuallyKnockout(enabled)
```

### `IsEMS()`
```lua
exports[''plt_ambulance_job'']:IsEMS()
```

### `GetFramework()`
```lua
exports[''plt_ambulance_job'']:GetFramework()
```

### `GetVitalsData()`
```lua
exports[''plt_ambulance_job'']:GetVitalsData()
```

### `GetInjuryType()`
```lua
exports[''plt_ambulance_job'']:GetInjuryType()
```

### `RevivePlayer()`
```lua
exports[''plt_ambulance_job'']:RevivePlayer()
```

### `GetDiagnosisTarget()`
```lua
exports[''plt_ambulance_job'']:GetDiagnosisTarget()
```

### `plt_use_medication(data, slot)`
```lua
exports[''plt_ambulance_job'']:plt_use_medication(data, slot)
```

### `plt_medical_bag(data, slot)`
```lua
exports[''plt_ambulance_job'']:plt_medical_bag(data, slot)
```

## Server Exports

### `RevivePlayer(targetSrc)`
```lua
exports[''plt_ambulance_job'']:RevivePlayer(targetSrc)
```

### `disableKnockoutLoop(targetSrc, disabled)`
```lua
exports[''plt_ambulance_job'']:disableKnockoutLoop(targetSrc, disabled)
```

### `manuallyKnockout(targetSrc, enabled)`
```lua
exports[''plt_ambulance_job'']:manuallyKnockout(targetSrc, enabled)
```

### `GetFramework()`
```lua
exports[''plt_ambulance_job'']:GetFramework()
```

### `IsEMS(src)`
```lua
exports[''plt_ambulance_job'']:IsEMS(src)
```

### `InternalRevive(src)`
```lua
exports[''plt_ambulance_job'']:InternalRevive(src)
```

### `AddFinanceEntry(dept, action, amount, reason, category)`
```lua
exports[''plt_ambulance_job'']:AddFinanceEntry(dept, action, amount, reason, category)
```

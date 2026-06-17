# Inventory Items for plt_ambulance_job

Copy and paste the following item definitions into your inventory configuration files.

---

## OX Inventory (`ox_inventory/data/items.lua`)

```lua
	['plt_medkit'] = {
		label = 'Medkit',
		weight = 500,
		stack = true,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_use_medication' },
		description = 'Standard medical kit for treatment.',
	},

	['plt_bandage'] = {
		label = 'Bandage',
		weight = 100,
		stack = true,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_use_medication' },
		description = 'A basic bandage to stop bleeding.',
	},

	['plt_painkillers'] = {
		label = 'Painkillers',
		weight = 50,
		stack = true,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_use_medication' },
		description = 'Helps reduce pain and stabilize patients.',
	},

	['plt_painkillers_adv'] = {
		label = 'Advanced Painkillers',
		weight = 50,
		stack = true,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_use_medication' },
		description = 'A stronger prescription-only pain medication.',
	},

	['plt_antibiotics'] = {
		label = 'Antibiotics',
		weight = 50,
		stack = true,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_use_medication' },
		description = 'Used to treat infections and more serious trauma.',
	},

	['plt_surgical_kit'] = {
		label = 'Surgical Kit',
		weight = 1000,
		stack = true,
		close = true,
		description = 'Professional tools for extracting bullets and deep surgery.',
	},

	['plt_stretcher'] = {
		label = 'Stretcher',
		weight = 5000,
		stack = false,
		close = true,
		description = 'Used to transport patients safely.',
	},

	['plt_oxygen_mask'] = {
		label = 'Oxygen Mask',
		weight = 300,
		stack = true,
		close = true,
		description = 'Helps patients breathe in critical conditions.',
	},

	['plt_surgical_scissors'] = {
		label = 'Surgical Scissors',
		weight = 200,
		stack = true,
		close = true,
		description = 'Used to cut through clothing during emergencies.',
	},

	['plt_radio'] = {
		label = 'Radio',
		weight = 200,
		stack = false,
		close = true,
		description = 'Communication device for emergency services.',
	},

	['plt_medical_bag'] = {
		label = 'Medical Bag',
		weight = 2000,
		stack = false,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_medical_bag' },
		description = 'A portable bag containing medical supplies with its own inventory.',
	},

	['plt_bp_monitor'] = {
		label = 'BP Monitor',
		weight = 500,
		stack = true,
		close = true,
		description = 'Blood pressure monitor used for vitals check.',
	},

	['plt_flashlight'] = {
		label = 'Flashlight',
		weight = 500,
		stack = false,
		close = true,
		description = 'High-powered flashlight for low-light conditions.',
	},

	['plt_fireextinguisher'] = {
		label = 'Fire Extinguisher',
		weight = 2000,
		stack = false,
		close = true,
		description = 'Used to put out small fires.',
	},

	['plt_prescription'] = {
		label = 'Medical Prescription',
		weight = 50,
		stack = true,
		close = true,
		description = 'An official document from a doctor authorizing specific medication.',
	},

	['iak_wheelchair'] = {
		label = 'Wheelchair',
		weight = 5000,
		stack = false,
		close = true,
		consume = 0,
		client = { export = 'plt_ambulance_job.plt_use_medication' },
		description = 'A mobility assistance device for patients with leg injuries.',
	},
```

---

## QB-Core Inventory (`qb-core/shared/items.lua`)

```lua
	['plt_medkit'] 					 = {['name'] = 'plt_medkit', 			    ['label'] = 'Medkit', 				['weight'] = 500, 		['type'] = 'item', 		['image'] = 'medkit.png', 		['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Standard medical kit for treatment.'},
	['plt_bandage'] 				 = {['name'] = 'plt_bandage', 			    ['label'] = 'Bandage', 				['weight'] = 100, 		['type'] = 'item', 		['image'] = 'bandage.png', 		['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'A basic bandage to stop bleeding.'},
	['plt_painkillers'] 			 = {['name'] = 'plt_painkillers', 			['label'] = 'Painkillers', 			['weight'] = 50, 		['type'] = 'item', 		['image'] = 'pill.png', 		['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Helps reduce pain and stabilize patients.'},
	['plt_surgical_kit'] 			 = {['name'] = 'plt_surgical_kit', 			['label'] = 'Surgical Kit', 		['weight'] = 1000, 		['type'] = 'item', 		['image'] = 'surgical.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Professional tools for extracting bullets.'},
	['plt_stretcher'] 				 = {['name'] = 'plt_stretcher', 			['label'] = 'Stretcher', 			['weight'] = 5000, 		['type'] = 'item', 		['image'] = 'stretcher.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Used to transport patients safely.'},
	['plt_oxygen_mask'] 			 = {['name'] = 'plt_oxygen_mask', 			['label'] = 'Oxygen Mask', 			['weight'] = 300, 		['type'] = 'item', 		['image'] = 'mask.png', 		['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Helps patients breathe in critical conditions.'},
	['plt_surgical_scissors'] 		 = {['name'] = 'plt_surgical_scissors', 	['label'] = 'Surgical Scissors', 	['weight'] = 200, 		['type'] = 'item', 		['image'] = 'scissors.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Used to cut through clothing.'},
	['plt_radio'] 					 = {['name'] = 'plt_radio', 			    ['label'] = 'Radio', 				['weight'] = 200, 		['type'] = 'item', 		['image'] = 'radio.png', 		['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Communication device for EMS.'},
	['plt_medical_bag'] 			 = {['name'] = 'plt_medical_bag', 			['label'] = 'Medical Bag', 			['weight'] = 2000, 		['type'] = 'item', 		['image'] = 'medical_bag.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'A portable bag containing medical supplies.'},
	['plt_bp_monitor'] 				 = {['name'] = 'plt_bp_monitor', 			['label'] = 'BP Monitor', 			['weight'] = 500, 		['type'] = 'item', 		['image'] = 'bp_monitor.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Blood pressure monitor used for vitals.'},
	['plt_flashlight'] 				 = {['name'] = 'plt_flashlight', 			['label'] = 'Flashlight', 			['weight'] = 500, 		['type'] = 'item', 		['image'] = 'flashlight.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'High-powered flashlight.'},
	['plt_fireextinguisher'] 		 = {['name'] = 'plt_fireextinguisher', 		['label'] = 'Fire Extinguisher', 	['weight'] = 2000, 		['type'] = 'item', 		['image'] = 'fireextinguisher.png', ['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'Used to put out fires.'},
	['plt_prescription'] 			 = {['name'] = 'plt_prescription', 			['label'] = 'Medical Prescription', ['weight'] = 50, 		['type'] = 'item', 		['image'] = 'prescription.png', ['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'An official document authorizing medication.'},
	['iak_wheelchair'] 				 = {['name'] = 'iak_wheelchair', 			['label'] = 'Wheelchair', 			['weight'] = 5000, 		['type'] = 'item', 		['image'] = 'wheelchair.png', 	['unique'] = false, 	['useable'] = true, 	['shouldClose'] = true,	   ['combinable'] = nil,   ['description'] = 'A mobility assistance device.'},
```

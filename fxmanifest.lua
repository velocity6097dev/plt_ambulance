fx_version 'cerulean'
game 'gta5'

author 'PLUTO'
description 'Ambulance & Fire Department Creator'
version '1.0.0'

ui_page 'web/index.html'

-- Register custom models: .ytyp tells the game the model exists
data_file 'DLC_ITYP_REQUEST' 'stream/fernocot.ytyp'
data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

files {
    'data/handling.meta',
    'data/vehicles.meta',
    'data/carvariations.meta',
    'stream/**/*.ydr',
    'stream/**/*.ytd',
    'stream/**/*.ytyp',
    'stream/**/*.ymf',
    'web/index.html',
    'web/style.css',
    'web/boss_menu.css',
    'web/inventory.css',
    'web/bag_inventory.css',
    'web/diagnosis.css',
    'web/dispatch.css',
    'web/deathscreen.css',
    'web/script.js',
    'web/boss_menu.js',
    'web/inventory.js',
    'web/bag_inventory.js',
    'web/diagnosis.js',
    'web/dispatch.js',
    'web/deathscreen.js',
    'web/pharmacy.js',
    'web/pharmacy.css',
    'web/img/*.png',
    'web/img/*.webp',
    'web/img/*.jpg',
    'web/fonts/*.ttf'
}

client_scripts {
    'shared/config.lua',
    'shared/framework.lua',
    'client/main.lua',
    'client/boss_menu.lua',
    'client/health.lua',
    'client/medical.lua',
    'client/diagnosis.lua',
    'client/dispatch.lua',
    'client/deathscreen.lua',
    'client/medical_bag.lua',
    'client/pharmacy.lua',
    'client/compat_exports.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared/config.lua',
    'shared/framework.lua',
    'server/main.lua',
    'server/boss_menu.lua',
    'server/health.lua',
    'server/diagnosis.lua',
    'server/dispatch.lua',
    'server/deathscreen.lua',
    'server/medical_bag.lua',
    'server/pharmacy.lua',
    'server/compat_exports.lua'
}

escrow_ignore {
    'shared/**/*.lua'
}

-- dependency 'oxmysql' -- Recommended


dependency '/assetpacks'
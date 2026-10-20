fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'crashphysics'
author 'Heino'
description '[W.I.P] Realistic vehicle crash physics'
version '1.0.0'
repository 'https://github.com/HeinoDev/crashphysics'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/core.lua',
    'client/detection.lua',
    'client/effects.lua',
    'client/seatbelt.lua',
    'client/trapped.lua',
    'client/doors.lua',
    'client/vehicle.lua',
    'client/debris.lua',
    'client/interactions.lua',
}

server_scripts {
    '@es_extended/imports.lua',
    'server/logs.lua',
    'server/state.lua',
    'server/doors.lua',
    'server/vehicle.lua',
    'server/debris.lua',
    'server/dispatch.lua',
    'server/impact.lua',
    'server/actions.lua',
    'server/commands.lua',
}

files {
    'config.lua',
    'shared/*.lua',
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'es_extended',
    'heino_bridge',
    'heino_interactions',
    '/onesync',
}

escrow_ignore {
    'config.lua',
    'locales/*.json',
}

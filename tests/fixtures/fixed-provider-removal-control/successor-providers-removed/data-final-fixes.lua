assert(mods.base == '2.0.77' and mods['space-age'] == '2.0.77' and mods['more-infinite-research'] == '5.0.20000', 'unexpected removal-control engine/MIR closure')
assert(mods['plates-n-circuit-productivity'] == nil and mods.Science_packs_productivity == nil and mods['bioflux-productivity'] == nil and mods['fish-productivity'] == nil, 'provider removal control retained a provider')
require('data-facts').mir(false, false, false)

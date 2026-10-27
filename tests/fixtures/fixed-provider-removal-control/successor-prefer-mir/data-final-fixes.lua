assert(mods.base == '2.0.77' and mods['space-age'] == '2.0.77' and mods['more-infinite-research'] == '5.0.20000', 'unexpected removal-control engine/MIR closure')
assert(mods['plates-n-circuit-productivity'] == '0.0.2' and mods.Science_packs_productivity == '0.0.1' and mods['bioflux-productivity'] == '0.1.0' and mods['fish-productivity'] == '1.0.0', 'unexpected removal-control provider closure')
require('data-facts').mir(true, true, true)

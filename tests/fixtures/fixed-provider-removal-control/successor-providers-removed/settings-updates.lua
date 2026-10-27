assert(mods.base == '2.0.77' and mods['space-age'] == '2.0.77' and mods['more-infinite-research'] == '5.0.20000', 'unexpected removal-control engine/MIR closure')
assert(mods['plates-n-circuit-productivity'] == nil and mods.Science_packs_productivity == nil and mods['bioflux-productivity'] == nil and mods['fish-productivity'] == nil, 'provider removal control retained a provider')
local value = assert(data.raw['bool-setting']['mir-prefer-this-mod-for-competing-techs'], 'MIR preference setting is absent')
assert(type(value.default_value) == 'boolean', 'MIR preference setting is malformed')
value.default_value = false

-- Exact, finite successor facts for the protected published MIR 1.2.0 F200
-- source save.  The source fixture owns the complete 34-row archive facts;
-- this descriptor contains only the independent transition boundary.
local function gun(ammo_category, modifier)
  return {type = "gun-speed", ammo_category = ammo_category, modifier = modifier}
end

return {
  storage_key = "mir5_migration_origin_f200_120_source",
  fixture = "mir-fixture-mir5-migration-origin-f200-120-source",
  direct = "recipe-prod-research_gears-1",
  source_combined = "recipe-prod-research_rocket_shooting_speed-1",
  cannon = "recipe-prod-research_cannon_shooting_speed-1",
  gear_recipe = "iron-gear-wheel",
  save = "mir5-native-complete",
  deadline_ticks = 18000,
  lab_packs = 32,
  expected_gear_delta = .10,
  source_rows = 34,
  source_weapons = 7,
  source_labs = 1,
  source_combined_signature = "gun-speed|cannon-shell|0.10000000000000001,gun-speed|rocket|0.10000000000000001",
  source_gun_totals = {
    player = {bullet = 1.5, ["shotgun-shell"] = 1.6, rocket = .1, ["cannon-shell"] = .1, electric = .1, flamethrower = .1},
    foreign = {bullet = .1, ["shotgun-shell"] = .1, rocket = .1, ["cannon-shell"] = .1, electric = .1, flamethrower = .1},
    detached = {bullet = 0, ["shotgun-shell"] = 0, rocket = .1, ["cannon-shell"] = .1, electric = .1, flamethrower = .1},
  },
  source_finite_seed_sets = {
    player = {"weapon-shooting-speed-1", "weapon-shooting-speed-2", "weapon-shooting-speed-3", "weapon-shooting-speed-4", "weapon-shooting-speed-5", "weapon-shooting-speed-6"},
    foreign = {"weapon-shooting-speed-1"}, detached = {},
  },
  targets = {
    f210 = {base = "2.1.23", mir = "5.0.21000", fixture = "0.2.0"},
    f200 = {base = "2.0.77", mir = "5.0.20000", fixture = "0.3.0"},
  },
  source_runtime = {
    ["weapon-shooting-speed-1"] = {level = 1, maximum = 1, effects = {gun("bullet", .1), gun("shotgun-shell", .1)}},
    ["weapon-shooting-speed-2"] = {level = 2, maximum = 2, effects = {gun("bullet", .2), gun("shotgun-shell", .2)}},
    ["weapon-shooting-speed-3"] = {level = 3, maximum = 3, effects = {gun("bullet", .2), gun("shotgun-shell", .2)}},
    ["weapon-shooting-speed-4"] = {level = 4, maximum = 4, effects = {gun("bullet", .3), gun("shotgun-shell", .3)}},
    ["weapon-shooting-speed-5"] = {level = 5, maximum = 5, effects = {gun("bullet", .3), gun("shotgun-shell", .4)}},
    ["weapon-shooting-speed-6"] = {level = 6, maximum = 6, effects = {gun("bullet", .4), gun("shotgun-shell", .4)}},
    ["weapon-shooting-speed-7"] = {level = 7, maximum = 4294967295, effects = {gun("bullet", .4), gun("shotgun-shell", .4)}},
  },
  -- Installed Base 2.0.77 data/base/prototypes/technology.lua, independently
  -- pinned by spec/inventory/migration-origins.json finite_owner_caveat.
  current_runtime = {
    ["weapon-shooting-speed-1"] = {level = 1, maximum = 1, effects = {gun("bullet", .1), gun("shotgun-shell", .1)}},
    ["weapon-shooting-speed-2"] = {level = 2, maximum = 2, effects = {gun("bullet", .2), gun("shotgun-shell", .2)}},
    ["weapon-shooting-speed-3"] = {level = 3, maximum = 3, effects = {gun("bullet", .2), gun("shotgun-shell", .2), gun("rocket", .5)}},
    ["weapon-shooting-speed-4"] = {level = 4, maximum = 4, effects = {gun("bullet", .3), gun("shotgun-shell", .3), gun("rocket", .7)}},
    ["weapon-shooting-speed-5"] = {level = 5, maximum = 5, effects = {gun("bullet", .3), gun("shotgun-shell", .4), gun("cannon-shell", .8), gun("rocket", .9)}},
    ["weapon-shooting-speed-6"] = {level = 6, maximum = 6, effects = {gun("bullet", .4), gun("shotgun-shell", .4), gun("cannon-shell", 1.5), gun("rocket", 1.3)}},
    ["weapon-shooting-speed-7"] = {level = 7, maximum = 4294967295, effects = {gun("bullet", .4), gun("shotgun-shell", .4)}},
  },
  split_effects = {
    rocket = {gun("rocket", .1)},
    cannon = {gun("cannon-shell", .1)},
  },
}

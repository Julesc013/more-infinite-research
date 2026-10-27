return {
  storage_key = "mir5_migration_origin_f200_100_source",
  fixture = "mir-fixture-mir5-migration-origin-f200-100-source",
  direct = "recipe-prod-research_gears-1",
  gear_recipe = "iron-gear-wheel",
  breeding_setting = "ips-enable-research_breeding",
  source_fixture_version = "0.1.0",
  targets = {
    f200 = {base = "2.0.77", mir = "5.0.20000", fixture = "0.2.0"},
    f210 = {base = "2.1.23", mir = "5.0.21000", fixture = "0.3.0"},
  },
  save = "mir5-native-complete",
  deadline_ticks = 18000,
  lab_packs = 16,
  expected_gear_delta = .10,
}

local technology_name = "recipe-prod-research_spoilage_preservation-1"
local per_level = 1.02
local epsilon = 0.000001
local native_owner_streams = {
  {stream = "research_processing_unit", owner = "processing-unit-productivity"},
  {stream = "research_plastic", owner = "plastic-bar-productivity"},
  {stream = "research_low_density_structure", owner = "low-density-structure-productivity"},
  {stream = "research_rocket_fuel", owner = "rocket-fuel-productivity"}
}

local function fail(message)
  error("MIR 2.3.5 to 2.4.0 upgrade validation failed: " .. message)
end

local function assert_close(label, actual, expected)
  if math.abs((actual or 0) - expected) > epsilon then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected))
  end
end

local function technology()
  local value = game.forces.player.technologies[technology_name]
  if not value then fail("missing scripted spoilage technology") end
  return value
end

script.on_init(function()
  if script.active_mods["more-infinite-research"] ~= "2.3.5" then
    fail("initial save did not use MIR 2.3.5")
  end
  if settings.startup["ips-enable-research_spoilage_preservation"].value ~= true then
    fail("non-default scripted setting was not enabled")
  end
  if settings.startup["ips-effect-per-level-research_spoilage_preservation"].value ~= 2 then
    fail("non-default effect setting was not retained at save creation")
  end

  local baseline = game.difficulty_settings.spoil_time_modifier
  local tech = technology()
  tech.level = 3
  game.forces.player.reset_technology_effects()
  local expected = baseline * per_level ^ 2
  assert_close("2.3.5 scripted runtime application", game.difficulty_settings.spoil_time_modifier, expected)
  storage.mir_upgrade_fixture_2_4 = {
    baseline = baseline,
    expected = expected,
    technology_level = tech.level
  }
  storage.mir_upgrade_fixture_2_4.native_owner_levels = {}
  for _, row in ipairs(native_owner_streams) do
    local enable_setting = settings.startup["ips-enable-" .. row.stream]
    local effect_setting = settings.startup["ips-effect-per-level-" .. row.stream]
    if not enable_setting or enable_setting.value ~= true or not effect_setting then
      fail("native-owner stream settings were unavailable before upgrade for " .. row.stream)
    end
    local owner = game.forces.player.technologies[row.owner]
    if not owner then fail("native owner was unavailable before upgrade: " .. row.owner) end
    owner.level = 2
    storage.mir_upgrade_fixture_2_4.native_owner_levels[row.owner] = owner.level
  end
  log("[mir-fixture] 2.3.5 upgrade source proof complete")
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "2.4.0" then
    fail("upgraded save did not use MIR 2.4.0")
  end
  local state = storage.mir_upgrade_fixture_2_4
  if not state then fail("fixture storage did not survive upgrade") end
  if settings.startup["ips-enable-research_spoilage_preservation"].value ~= true then
    fail("scripted enable setting did not survive upgrade")
  end
  if settings.startup["ips-effect-per-level-research_spoilage_preservation"].value ~= 2 then
    fail("scripted effect setting did not survive upgrade")
  end
  if technology().level ~= state.technology_level then
    fail("scripted technology level did not survive upgrade")
  end
  assert_close("2.4.0 scripted runtime retention", game.difficulty_settings.spoil_time_modifier, state.expected)
  for _, row in ipairs(native_owner_streams) do
    for _, prefix in ipairs({"ips-enable-", "ips-cost-base-", "ips-cost-growth-", "ips-max-level-", "ips-research-time-", "ips-effect-per-level-"}) do
      if not settings.startup[prefix .. row.stream] then
        fail("native-owner setting ID did not survive upgrade: " .. prefix .. row.stream)
      end
    end
    local owner = game.forces.player.technologies[row.owner]
    if not owner or owner.level ~= state.native_owner_levels[row.owner] then
      fail("native-owner technology level did not survive upgrade: " .. row.owner)
    end
  end
  log("[mir-fixture] 2.3.5 to 2.4.0 upgrade proof complete")
end)

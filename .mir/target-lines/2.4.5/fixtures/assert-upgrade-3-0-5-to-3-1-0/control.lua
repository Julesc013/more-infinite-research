local technology_name = "recipe-prod-research_spoilage_preservation-1"
local per_level = 1.02
local epsilon = 0.000001

local function fail(message)
  error("MIR 3.0.5 to 3.1.0 upgrade validation failed: " .. message)
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
  if script.active_mods["more-infinite-research"] ~= "3.0.5" then
    fail("initial save did not use MIR 3.0.5")
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
  assert_close("3.0.5 scripted runtime application", game.difficulty_settings.spoil_time_modifier, expected)
  storage.mir_upgrade_fixture = {
    baseline = baseline,
    expected = expected,
    technology_level = tech.level
  }
  log("[mir-fixture] 3.0.5 upgrade source proof complete")
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "3.1.0" then
    fail("upgraded save did not use MIR 3.1.0")
  end
  local state = storage.mir_upgrade_fixture
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
  assert_close("3.1.0 scripted runtime retention", game.difficulty_settings.spoil_time_modifier, state.expected)
  log("[mir-fixture] 3.0.5 to 3.1.0 upgrade proof complete")
end)

-- Observe the actual optional consumer with MIR absent. No research/state
-- seeding, remote call, gameplay effect or later save qualification is claimed.
local function fail(message) error("[mir5-api-optional-absence] " .. message) end
script.on_init(function()
  local base_version = script.active_mods.base
  if base_version ~= "2.0.77" and base_version ~= "2.1.23" then
    fail("unexpected base version")
  end
  local expected = {
    base=base_version, ["mir-fixture-mir5-api-beta"]="0.1.0",
    ["mir-fixture-mir5-api-optional-absence"]="0.1.0",
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
  }
  local count = 0
  for name, version in pairs(script.active_mods) do
    if expected[name] ~= version then fail("unexpected active mod: " .. name) end
    count = count + 1
  end
  if count ~= 4 then fail("optional consumer closure is incomplete") end
  if remote.interfaces["more-infinite-research.api.v1"] ~= nil then fail("MIR runtime interface is present") end
  local force = game.forces.player
  if not force or force.valid == false then fail("player force is absent") end
  if force.technologies["mir-api-fixture-beta-cable-1"] ~= nil
      or force.technologies["recipe-prod-research_gears-1"] ~= nil then
    fail("MIR or optional API research was emitted")
  end
  local cable = force.recipes["copper-cable"]
  if not cable or cable.productivity_bonus ~= 0 then fail("fresh cable productivity differs") end
  log("[MIR5_API_OPTIONAL_ABSENCE] RESULT " .. helpers.table_to_json({
    case="api-optional-absence", stage="init", status="passed",
    qualification="optional-consumer-absence-startup-only",
    consumer="mir-fixture-mir5-api-beta", mir_present=false,
    runtime_interface_present=false, optional_technology_present=false,
    cable_productivity_bonus=cable.productivity_bonus,
  }))
end)

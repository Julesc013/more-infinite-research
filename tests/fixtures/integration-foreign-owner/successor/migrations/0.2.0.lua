-- Factorio runs migrations before configuration callbacks. This actor restores
-- only the disabled flag it stored on its exact foreign-force primary witness.
local KEY = "mir5_integration_foreign_owner"
local FOREIGN_FORCE = "mir5-integration-catalogue-upgrade-foreign"
local PRIMARY = {
  ["recipe-prod-research_armor_components-1"] = true,
  ["recipe-prod-research_material_py_log-4"] = true,
  ["recipe-prod-research_breeding-1"] = true,
}
local state = storage[KEY]

local function fail(message)
  error("[mir5-integration-foreign-owner migration 0.2.0] " .. message)
end

local function positive_integer(value)
  return type(value) == "number" and value == math.floor(value) and value >= 1
end

-- Validate the complete finite witness before looking up or writing a prototype.
if type(state) ~= "table" or state.disabled ~= true
    or not positive_integer(state.force_index) or type(state.technology) ~= "string" then
  fail("source actor witness is absent or malformed")
end
if PRIMARY[state.technology] ~= true then
  fail("stored technology is outside the integration primary set")
end

local force = game.forces[state.force_index]
if force == nil or force.valid == false or force.name ~= FOREIGN_FORCE then
  fail("stored foreign force differs")
end
local technology = force.technologies[state.technology]
if technology == nil or technology.valid == false or technology.name ~= state.technology then
  fail("stored primary technology is absent")
end

local observed_before = technology.enabled
technology.enabled = false
local observed_after = technology.enabled
if observed_after ~= false then fail("stored disabled flag did not persist") end
log("[MIR5_FOREIGN_OWNER_MIGRATION] " .. helpers.table_to_json({
  actor="mir5-integration-foreign-owner",
  force=state.force_index,
  technology=state.technology,
  expected_disabled=true,
  observed_before=observed_before,
  observed_after=observed_after,
}))

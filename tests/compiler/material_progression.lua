-- Pure declaration contract for the reviewed Bob/Angel staged continuation.
-- The runner supplies source/ on package.path and does not start Factorio.
local progression = require("prototypes.mir.families.material_progression")

local assertions = 0
local function check(value, message)
  assert(value, message)
  assertions = assertions + 1
end

local expected_keys = {
  "research_material_aluminium",
  "research_material_gold",
  "research_material_lead",
  "research_material_nickel",
  "research_material_platinum",
  "research_material_silver",
  "research_material_tin",
  "research_material_titanium",
  "research_material_copper_tungsten",
  "research_material_zinc",
  "research_material_bronze",
  "research_material_brass",
  "research_material_gunmetal",
  "research_material_invar",
  "research_material_cobalt_steel",
  "research_material_nitinol"
}

local function same_array(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do
    if value ~= right[index] then return false end
  end
  return true
end

check(same_array(progression.material_stream_keys(), expected_keys),
  "the staged material family key set remains the reviewed sixteen Bob/Angel streams")

for _, key in ipairs(expected_keys) do
  local declaration = progression.attach(key, {max_level = 3})
  local staged = declaration.staged_progression
  local valid, reason = progression.validate(key, staged)
  check(valid, "valid staged declaration for " .. key .. ": " .. tostring(reason))
  check(staged.legacy.technology_name == "recipe-prod-" .. key .. "-1"
      and staged.legacy.first_level == 1 and staged.legacy.last_level == 3,
    "legacy technology identity and finite early span remain stable for " .. key)
  check(staged.legacy.preserve_completed_levels and staged.legacy.preserve_active_research
      and staged.legacy.preserve_queue and staged.legacy.preserve_fractional_progress,
    "continuation preserves existing save and queue state for " .. key)
  check(staged.continuation.technology_name == "recipe-prod-" .. key .. "-4"
      and staged.continuation.prerequisite_technology == staged.legacy.technology_name,
    "continuation begins after the legacy stage for " .. key)
  check(staged.continuation.effect_domain == "same-qualified-recipes"
      and staged.continuation.effect_change == "same-qualified-change"
      and staged.continuation.native_owner_policy == "require-mir-generated-legacy-owner",
    "continuation cannot widen the recipe domain or replace a native owner for " .. key)
  check(staged.continuation.science_policy == "derive-qualified-route-late-frontier"
      and staged.continuation.laboratory_policy == "require-reachable-late-frontier-lab",
    "continuation science remains tied to the qualified late route frontier for " .. key)
  check(staged.continuation.maximum_level_policy == "finite-highest-useful-recipe-level"
      and staged.continuation.maximum_level_scope == "absolute-combined-stage-level"
      and staged.continuation.maximum_level_default == 0
      and staged.continuation.no_headroom_policy == "withhold-continuation",
    "continuation has an unbounded configured default but only emits while a qualified recipe has finite headroom for " .. key)
end

local malformed = progression.attach("research_material_tin", {max_level = 3}).staged_progression
malformed.continuation.maximum_level_policy = "infinite"
local malformed_valid, malformed_reason = progression.validate("research_material_tin", malformed)
check(not malformed_valid and malformed_reason == "invalid-continuation-stage",
  "an unbounded continuation claim is rejected")

local wrong_identity = progression.attach("research_material_tin", {max_level = 3}).staged_progression
wrong_identity.legacy.technology_name = "recipe-prod-research_material_tin-2"
local identity_valid, identity_reason = progression.validate("research_material_tin", wrong_identity)
check(not identity_valid and identity_reason == "invalid-legacy-stage",
  "a declaration cannot replace the released legacy technology identity")

local cap_ok = pcall(function()
  progression.attach("research_material_tin", {max_level = "infinite"})
end)
check(not cap_ok, "the shared declaration refuses to turn the released three-tier technology directly infinite")

local foreign_ok = pcall(function()
  progression.attach("research_material_rare_metals", {max_level = 3})
end)
check(not foreign_ok, "unreviewed K2 material families cannot enter the Bob/Angel continuation mechanism")

-- Load the actual source declaration with its minimal data-stage dependencies
-- stubbed. This proves each reviewed material family attaches the shared
-- contract; it does not simulate emission or Factorio runtime behavior.
package.loaded["prototypes.mir.compatibility.overlay_loader"] = {
  get = function(name)
    return {
      applies_when = {mods = {name}},
      capabilities = {
        ["recipe-productivity"] = {
          exact_recipes = {"fixture-" .. name},
          deny_risk_flags = {},
          stream = {id = "fixture/" .. name}
        }
      }
    }
  end
}
package.loaded["prototypes.mir.platform.factorio.target_profiles"] = {
  current = function() return {factorio_version = "2.1"} end
}
package.loaded["prototypes.mir.platform.factorio.prototype_lookup"] = {
  item_prototype = function() return nil end
}

local streams = require("prototypes.streams.productivity")
for _, key in ipairs(expected_keys) do
  local staged = streams[key] and streams[key].staged_progression
  local valid, reason = progression.validate(key, staged)
  check(valid, "actual material stream uses the shared valid progression declaration for "
    .. key .. ": " .. tostring(reason))
end
check(streams.research_material_rare_metals.staged_progression == nil,
  "K2 material declaration stays outside the unqualified continuation mechanism")

print("MIR-MATERIAL-PROGRESSION-PASS " .. assertions)

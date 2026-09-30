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
check(same_array(progression.k2_213_continuation_stream_keys(), {
  "research_material_imersite"
}), "the current K2 continuation set contains only the reviewed MIR powder stream")

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

local k2_generic_ok = pcall(function()
  progression.attach("research_material_imersite", {max_level = 3})
end)
check(not k2_generic_ok, "the K2 Imersite continuation cannot enter through the Bob/Angel attachment API")

local k2_unreviewed_ok = pcall(function()
  progression.attach_k2_213_continuation("research_material_rare_metals", {max_level = 3})
end)
check(not k2_unreviewed_ok, "the exact K2 continuation attachment refuses witnessed withheld routes")

local imersite = progression.attach_k2_213_continuation("research_material_imersite", {max_level = 3})
local imersite_valid, imersite_reason = progression.validate(
  "research_material_imersite", imersite.staged_progression)
check(imersite_valid, "the exact K2 Imersite continuation uses the shared valid declaration: " .. tostring(imersite_reason))
check(imersite.staged_progression.continuation.maximum_level_default == 0
    and progression.legacy_max_level("research_material_imersite", imersite, "infinite") == 3
    and progression.legacy_max_level("research_material_imersite", imersite, 2) == 2,
  "the K2 continuation keeps legacy levels finite while zero config delegates a finite effective cap to recipe headroom")

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
check(streams.research_material_imersite.staged_progression == nil,
  "Imersite stays unattached until the exact current K2 tuple guard selects its continuation")

-- Exercise the policy at the stream assembly boundary: the exact witnessed
-- K2 tuple opts into the powder continuation, while the neighboring K2
-- release stays outside it even on the same Factorio line.
local prior_mods = mods
local function load_streams_for(active_mods)
  mods = active_mods
  package.loaded["prototypes.streams.productivity"] = nil
  return require("prototypes.streams.productivity")
end

local neighboring_streams = load_streams_for({
  base = "2.1.20",
  Krastorio2 = "2.1.2",
  ["Krastorio2-spaced-out"] = "2.0.13"
})
check(neighboring_streams.research_material_imersite.staged_progression == nil,
  "a neighboring K2 tuple remains outside the admitted Imersite continuation")

local exact_streams = load_streams_for({
  base = "2.1.20",
  Krastorio2 = "2.1.3",
  ["Krastorio2-spaced-out"] = "2.0.13"
})
local exact_imersite = exact_streams.research_material_imersite.staged_progression
local exact_valid, exact_reason = progression.validate("research_material_imersite", exact_imersite)
check(exact_valid, "the exact current K2 tuple attaches valid Imersite continuation: " .. tostring(exact_reason))
check(exact_imersite.continuation.technology_name == "recipe-prod-research_material_imersite-4"
    and exact_imersite.legacy.last_level == 3,
  "the exact K2 tuple preserves the finite legacy stage and adds only the separate level-four identity")
mods = prior_mods

local function effect(recipe, change)
  return {type = "change-recipe-productivity", recipe = recipe, change = change}
end
local recipe_caps = {
  normal = {}, -- Engine default is +300% when maximum_productivity is absent.
  narrow = {maximum_productivity = 0.06},
  broad = {maximum_productivity = 5.0}
}
local function recipe(name) return recipe_caps[name] end
local normal_level = progression.highest_useful_level({effect("normal", 0.02)}, recipe, "infinite")
check(normal_level == 150, "the default recipe cap admits a finite last useful +2% level")
local broad_level = progression.highest_useful_level({effect("broad", 0.02)}, recipe, "infinite")
check(broad_level == 250, "an observed raised recipe cap permits later useful levels")
local mixed_level = progression.highest_useful_level({effect("normal", 0.02), effect("narrow", 0.02)}, recipe, "infinite")
check(mixed_level == 150, "the family continues while at least one qualified recipe benefits")
local configured_level = progression.highest_useful_level({effect("normal", 0.02)}, recipe, 8)
check(configured_level == 8, "a finite startup setting is an absolute cap across both stages")
local configured_stop, configured_reason = progression.highest_useful_level(
  {effect("normal", 0.02)}, recipe, 3)
check(configured_stop == nil and configured_reason == "configured-material-cap-before-continuation",
  "an explicit cap at the legacy boundary explains why continuation is withheld")
local no_headroom, no_headroom_reason = progression.highest_useful_level({effect("narrow", 0.02)}, recipe, "infinite")
check(no_headroom == nil and no_headroom_reason == "no-continuation-headroom",
  "a family whose recipes saturate within levels one to three gets no paid continuation")
local absent, absent_reason = progression.highest_useful_level({effect("missing", 0.02)}, recipe, "infinite")
check(absent == nil and absent_reason == "material-recipe-unavailable",
  "an unknown recipe fails closed rather than borrowing the engine default cap")
local invalid, invalid_reason = progression.highest_useful_level({effect("normal", 0)}, recipe, "infinite")
check(invalid == nil and invalid_reason == "invalid-material-effect",
  "a non-positive productivity effect cannot create continuation levels")

print("MIR-MATERIAL-PROGRESSION-PASS " .. assertions)

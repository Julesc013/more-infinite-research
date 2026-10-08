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

local expected_k2_keys = {
  "research_material_rare_metals", "research_material_silicon", "research_material_glass",
  "research_material_black_paving", "research_material_white_paving"
}
check(same_array(progression.k2_material_stream_keys(), expected_k2_keys),
  "the other five named K2 outcomes have their own continuation declarations")
local copied_k2_keys = progression.k2_material_stream_keys()
copied_k2_keys[1] = "research_material_imersite"
check(same_array(progression.k2_material_stream_keys(), expected_k2_keys),
  "a caller cannot mutate the cached K2 continuation identity set")
for _, key in ipairs(expected_k2_keys) do
  local declaration = progression.attach_k2_material_continuation(key, {max_level = 3})
  local valid, reason = progression.validate(key, declaration.staged_progression)
  check(valid, "valid shared staged declaration for " .. key .. ": " .. tostring(reason))
  check(declaration.staged_progression.legacy.technology_name == "recipe-prod-" .. key .. "-1"
      and progression.legacy_max_level(key, declaration, "infinite") == 3
      and declaration.staged_progression.continuation.technology_name == "recipe-prod-" .. key .. "-4"
      and declaration.staged_progression.continuation.maximum_level_default == 0,
    "K2 continuation preserves the finite early identity and adds the separate level-four identity for " .. key)
end
check(not pcall(function()
  progression.attach_k2_material_continuation("research_material_imersite", {max_level = 3})
end), "ordinary K2 declarations cannot bypass the retained exact Imersite attachment guard")

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
local petrochem_subjects = {
  {"research_material_nitric_acid", "angels-liquid-nitric-acid", {"angels-liquid-nitric-acid"}},
  {"research_material_hydrochloric_acid", "angels-liquid-hydrochloric-acid", {
    "angels-liquid-hydrochloric-acid", "angels-liquid-hydrochloric-acid-solid-sodium-sulfate"}},
  {"research_material_hydrofluoric_acid", "angels-liquid-hydrofluoric-acid", {
    "angels-liquid-hydrofluoric-acid", "angels-hydrogen-fluoride-dissolving"}},
  {"research_material_glycerol", "angels-liquid-glycerol", {"angels-liquid-glycerol"}}
}
local petrochem_keys = {}
for _, subject in ipairs(petrochem_subjects) do
  local key, fluid, routes = subject[1], subject[2], subject[3]
  petrochem_keys[#petrochem_keys + 1] = key
  local family = streams[key]
  local valid, reason = progression.validate(key, family.staged_progression)
  check(valid, "Angel chemical uses shared staged progression for " .. key .. ": " .. tostring(reason))
  check(family.required_items == nil and same_array(family.required_fluids, {fluid})
      and family.icon_item == nil and family.icon_fluid == fluid
      and family.localised_name[4][1] == "fluid-name." .. fluid,
    "chemical identity and presentation require the actual fluid for " .. key)
  local group = family.groups[1]
  check(family.require_acyclic_process == true and group.reject_explicit_productivity_denial == true
      and group.change == 0.02 and #group.required_productive_outputs == 1
      and group.required_productive_outputs[1].type == "fluid"
      and group.required_productive_outputs[1].name == fluid,
    "chemical routes retain process and permission gates plus a typed productive output for " .. key)
  local patterns = {}
  for _, route in ipairs(routes) do patterns[#patterns + 1] = "^" .. route:gsub("%-", "%%-") .. "$" end
  check(same_array(group.recipe_patterns, patterns) and family.reviewed_forward_routes == nil
      and family.productivity_permission_recipes == nil,
    "only the retained exact producer names are selected without a certificate or permission grant for " .. key)
  check(family.staged_progression.legacy.last_level == 3
      and family.staged_progression.continuation.technology_name == "recipe-prod-" .. key .. "-4",
    "chemical progression uses finite early levels and a separate later identity for " .. key)
end
check(same_array(progression.angel_petrochem_stream_keys(), petrochem_keys),
  "the four retained Angel chemicals have a separate identity set")
local petrochem_copy = progression.angel_petrochem_stream_keys()
petrochem_copy[1] = "research_material_tin"
check(same_array(progression.angel_petrochem_stream_keys(), petrochem_keys),
  "callers cannot mutate the chemical identity set")
check(not pcall(function()
  progression.attach_angel_petrochem_continuation("research_material_tin", {max_level = 3})
end), "chemical attachment cannot grant a different material continuation")
local py_subjects = {
  {"research_material_py_acid_gas", "acidgas", {
    "dirty-acid", "tailings-dust", "oleochemicals-distilation", "refsyngas-from-meth",
    "refsyngas-from-meth-canister", "acidgas-2", "acidgas", "coalbed-gas-to-acidgas",
    "tholin-to-acidgas", "cadaveric-acidgas-01", "cadaveric-arum-mk02-juicer",
    "cadaveric-arum-mk04-juicer", "pyrite-burn"}},
  {"research_material_py_glycerol", "glycerol", {
    "oleochemicals", "glycerol2", "tholin-to-glycerol", "collagen-glycerol"}}
}
local py_keys = {}
for _, subject in ipairs(py_subjects) do
  local key, fluid, routes = subject[1], subject[2], subject[3]
  py_keys[#py_keys + 1] = key
  local family = streams[key]
  local valid, reason = progression.validate(key, family.staged_progression)
  check(valid, "actual Py fluid has valid shared progression: " .. key .. ": " .. tostring(reason))
  check(family.required_items == nil and same_array(family.required_fluids, {fluid})
      and same_array(family.required_mods, {"pycoalprocessing"})
      and family.icon_item == nil and family.icon_fluid == fluid
      and family.localised_name[4][1] == "fluid-name." .. fluid,
    "Py discovery and presentation use its own typed fluid: " .. key)
  local group = family.groups[1]
  check(family.require_acyclic_process and group.reject_explicit_productivity_denial
      and group.change == 0.02 and #group.required_productive_outputs == 1
      and group.required_productive_outputs[1].type == "fluid"
      and group.required_productive_outputs[1].name == fluid,
    "Py declarations retain all shared admission guards: " .. key)
  local patterns = {}
  for _, route in ipairs(routes) do patterns[#patterns + 1] = "^" .. route:gsub("%-", "%%-") .. "$" end
  check(same_array(group.recipe_patterns, patterns) and family.reviewed_forward_routes == nil
      and family.productivity_permission_recipes == nil,
    "Py declaration selects exact retained producers without permission or graph exceptions: " .. key)
end
check(same_array(progression.py_chemical_stream_keys(), py_keys), "Py chemical identities stay separate")
local py_copy = progression.py_chemical_stream_keys()
py_copy[1] = "research_material_glycerol"
check(same_array(progression.py_chemical_stream_keys(), py_keys), "Py identity accessor returns a copy")
for _, key in ipairs({"research_material_glycerol", "research_material_tin", "research_material_imersite", "research_material_py_earth_sample"}) do
  check(not pcall(function() progression.attach_py_chemical_continuation(key, {max_level = 3}) end),
    "Py chemical attachment cannot acquire another request: " .. key)
end
check(not pcall(function()
  progression.attach_angel_petrochem_continuation("research_material_py_glycerol", {max_level = 3})
end), "Angel glycerol authority cannot acquire Py glycerol")
do
  local subjects = {
    {"generic", "earth-generic-sample"}, {"sunflower", "earth-sunflower-sample"},
    {"flower", "earth-flower-sample"}, {"shroom", "earth-shroom-sample"},
    {"tropical_tree", "earth-tropical-tree-sample"}, {"potato", "earth-potato-sample"},
    {"jute", "earth-jute-sample"}, {"venus_fly", "earth-venus-fly-sample"},
    {"palmtree", "earth-palmtree-sample"}
  }
  local keys = {}
  for _, subject in ipairs(subjects) do
    local key, item = "research_material_py_earth_" .. subject[1] .. "_sample", subject[2]
    keys[#keys+1] = key
    local family = streams[key]
    check(family ~= nil, "retained Py sample has an actual declaration: " .. item)
    check(same_array(family.required_items, {item}) and family.required_fluids == nil
      and family.icon_item == item and family.localised_name[4][1] == "item-name." .. item,
      "Py sample presentation and acquisition preserve the exact item: " .. item)
    local required = subject[1] == "palmtree" and {"pyalienlife", "pyhightech"} or {"pyalienlife"}
    check(same_array(family.required_mods, required), "Py sample requires its retained defining mods: " .. item)
    local group = family.groups[1]
    check(group.change == 0.02 and family.require_acyclic_process and group.reject_explicit_productivity_denial
      and #group.required_productive_outputs == 1 and group.required_productive_outputs[1].type == "item"
      and group.required_productive_outputs[1].name == item and family.productivity_permission_recipes == nil
      and family.reviewed_forward_routes == nil,
      "Py samples receive no permission or process exceptions: " .. item)
    check(same_array(group.recipe_patterns, {"^" .. item:gsub("%-", "%%-") .. "$"}),
      "Py sample selects its exact retained producer, without tree or bootstrap aliases: " .. item)
    local valid, reason = progression.validate(key, family.staged_progression)
    check(valid, "actual Py sample stages validate: " .. item .. ": " .. tostring(reason))
    local late = family.staged_progression.continuation
    check(family.max_level == 3 and late.first_level == 4 and late.effect_domain == "same-qualified-recipes"
      and late.laboratory_policy == "require-reachable-late-frontier-lab"
      and late.native_owner_policy == "require-mir-generated-legacy-owner"
      and late.maximum_level_policy == "finite-highest-useful-recipe-level",
      "Py samples retain useful science/lab/owner/cap progression: " .. item)
  end
  check(same_array(progression.py_sample_stream_keys(), keys), "nine sample identities remain distinct from Py chemicals and trees")
  local copy = progression.py_sample_stream_keys(); copy[1] = "research_material_py_glycerol"
  check(same_array(progression.py_sample_stream_keys(), keys), "sample identity accessor cannot poison the canonical set")
  for _, key in ipairs({"research_material_py_glycerol", "research_material_glycerol", "research_material_tin", "research_material_py_tree_mk01"}) do
    check(not pcall(function() progression.attach_py_sample_continuation(key, {max_level = 3}) end),
      "sample attachment cannot acquire chemical, Angel or tree requests: " .. key)
  end
end
local forestry_subjects = {
  {"research_material_py_log", "log", {"log1", "log2", "log3", "log4", "log5", "log6", "log7", "log8", "log7-2"}},
  {"research_material_py_wood", "wood", {"log-wood"}},
  {"research_material_py_treated_wood", "treated-wood", {"treated-wood"}}
}
do
  local keys = {}
  for _, subject in ipairs(forestry_subjects) do
    local key, item, routes = subject[1], subject[2], subject[3]
    keys[#keys + 1] = key
    local family = assert(streams[key])
    check(same_array(family.required_items, {item}) and family.required_fluids == nil
        and same_array(family.required_mods, {"pycoalprocessing"})
        and family.icon_item == item and family.localised_name[4][1] == "item-name." .. item,
      "forestry preserves its product identity and provider: " .. key)
    local group, patterns = family.groups[1], {}
    for _, route in ipairs(routes) do patterns[#patterns + 1] = "^" .. route:gsub("%-", "%%-") .. "$" end
    check(same_array(group.recipe_patterns, patterns)
        and #group.required_productive_outputs == 1
        and group.required_productive_outputs[1].type == "item"
        and group.required_productive_outputs[1].name == item,
      "forestry binds exact retained producers to their productive item: " .. key)
    check(group.change == 0.02 and family.require_acyclic_process and group.reject_explicit_productivity_denial
        and family.productivity_permission_recipes == nil and family.reviewed_forward_routes == nil,
      "forestry grants no process or permission exception: " .. key)
    check(progression.validate(key, family.staged_progression) and family.max_level == 3
        and family.staged_progression.continuation.first_level == 4,
      "forestry uses the validated shared staged contract: " .. key)
  end
  check(same_array(progression.py_forestry_stream_keys(), keys), "forestry has three separate product identities")
  local copy = progression.py_forestry_stream_keys(); copy[1] = "research_material_py_wood_seeds"
  check(same_array(progression.py_forestry_stream_keys(), keys), "forestry identity accessor returns a copy")
  for _, key in ipairs({"research_material_py_glycerol", "research_material_py_earth_generic_sample",
      "research_material_py_wood_seeds", "research_material_py_tree_mk01", "research_material_tin"}) do
    check(not pcall(function() progression.attach_py_forestry_continuation(key, {max_level = 3}) end),
      "forestry cannot acquire a separate subject: " .. key)
  end
end

do
  local lookup = package.loaded["prototypes.mir.platform.factorio.prototype_lookup"]
  local saved_mod_exists, saved_fluid, saved_item = lookup.mod_exists, lookup.fluid_prototype, lookup.item_prototype
  local saved_science = package.loaded["prototypes.mir.capabilities.science_integration.science_packs"]
  local saved_technology_requirements = package.loaded["prototypes.mir.planner.technology_requirements"]
  package.loaded["prototypes.mir.capabilities.science_integration.science_packs"] = {}
  package.loaded["prototypes.mir.planner.technology_requirements"] = {skip_reason = function() return nil end}
  local requirements = require("prototypes.mir.planner.requirements")
  local descriptor = require("prototypes.mir.domain.streams.descriptor")
  local actual_profiles = require("fixtures.material_progression.target_profiles")
  local saved_profiles = package.loaded["prototypes.mir.platform.factorio.target_profiles"]
  local saved_target_line = package.loaded["prototypes.mir.platform.factorio.target_line"]
  local provider_present, fluid_present = false, true
  lookup.mod_exists = function(name) return provider_present and name == "pycoalprocessing" end
  lookup.fluid_prototype = function(name)
    return fluid_present and (name == "acidgas" or name == "glycerol") and {} or nil
  end
  for _, subject in ipairs(py_subjects) do
    local key, fluid = subject[1], subject[2]
    provider_present, fluid_present = false, true
    check(requirements.missing_reason(key, streams[key]) == "missing required mod pycoalprocessing",
      "actual requirements consumer refuses an unrelated same-named fluid without Py: " .. key)
    provider_present = true
    check(requirements.missing_reason(key, streams[key]) == nil,
      "present Py provider and fluid satisfy the declared prototype requirements: " .. key)
    fluid_present = false
    check(requirements.missing_reason(key, streams[key]) == "missing required fluid " .. fluid,
      "Py presence alone cannot supply a missing fluid: " .. key)
    local normalized = descriptor.normalize(key, streams[key])
    check(same_array(normalized.descriptor.targets.required_mods, {"pycoalprocessing"}),
      "canonical descriptor preserves the Py provider requirement: " .. key)
    for _, line in ipairs({"2.1", "2.0", "1.1", "1.0"}) do
      local profile = assert(actual_profiles.profiles[line])
      package.loaded["prototypes.mir.platform.factorio.target_profiles"] = {current = function() return profile end}
      package.loaded["prototypes.mir.platform.factorio.target_line"] = nil
      local target_line = require("prototypes.mir.platform.factorio.target_line")
      local modern = line == "2.1" or line == "2.0"
      check(target_line.stream_supported(key, normalized) == modern,
        "actual target contract supports Py required-mod declarations only with recipe productivity: " .. line .. " " .. key)
      provider_present, fluid_present = false, true
      check(not (target_line.stream_supported(key, normalized) and requirements.missing_reason(key, normalized) == nil),
        "target support alone cannot admit Py without the provider: " .. line .. " " .. key)
      provider_present = true
      check((target_line.stream_supported(key, normalized) and requirements.missing_reason(key, normalized) == nil) == modern,
        "both actual target and provider gates must pass: " .. line .. " " .. key)
    end
  end
  local active_mods, available_item = {}, nil
  lookup.mod_exists = function(name) return active_mods[name] == true end
  lookup.item_prototype = function(name) return name == available_item and {} or nil end
  for _, key in ipairs(progression.py_sample_stream_keys()) do
    local family = streams[key]
    local item = family.required_items[1]
    local palm = key == "research_material_py_earth_palmtree_sample"
    local required = palm and {"pyalienlife", "pyhightech"} or {"pyalienlife"}
    active_mods, available_item = {}, item
    check(requirements.missing_reason(key, family) == "missing required mod pyalienlife",
      "an unrelated same-named sample cannot replace its defining provider: " .. key)
    active_mods.pyalienlife = true
    if palm then
      check(requirements.missing_reason(key, family) == "missing required mod pyhightech",
        "the conditional palm sample also requires Py HighTech")
      active_mods.pyhightech = true
    end
    check(requirements.missing_reason(key, family) == nil,
      "present providers and the requested item satisfy sample requirements: " .. key)
    available_item = nil
    check(requirements.missing_reason(key, family) == "missing required item " .. item,
      "provider presence does not supply an absent sample: " .. key)
    available_item = item
    local normalized = descriptor.normalize(key, family)
    check(same_array(normalized.descriptor.targets.required_mods, required),
      "descriptor preserves every defining sample provider: " .. key)
    for _, line in ipairs({"2.1", "2.0", "1.1", "1.0"}) do
      local profile = assert(actual_profiles.profiles[line])
      package.loaded["prototypes.mir.platform.factorio.target_profiles"] = {current = function() return profile end}
      package.loaded["prototypes.mir.platform.factorio.target_line"] = nil
      local target_line = require("prototypes.mir.platform.factorio.target_line")
      local modern = line == "2.1" or line == "2.0"
      check((target_line.stream_supported(key, normalized) and requirements.missing_reason(key, normalized) == nil) == modern,
        "sample admission requires both prototype requirements and recipe-productivity capability: " .. line .. " " .. key)
    end
  end
  for _, subject in ipairs(forestry_subjects) do
    local key, item = subject[1], subject[2]
    local family = streams[key]
    active_mods, available_item = {}, item
    check(requirements.missing_reason(key, family) == "missing required mod pycoalprocessing",
      "native wood or an unrelated same-named item cannot replace the Py provider: " .. key)
    active_mods.pycoalprocessing = true
    check(requirements.missing_reason(key, family) == nil, "provider and item satisfy forestry requirements: " .. key)
    available_item = nil
    check(requirements.missing_reason(key, family) == "missing required item " .. item,
      "provider presence does not supply an absent forestry item: " .. key)
    available_item = item
    local normalized = descriptor.normalize(key, family)
    check(same_array(normalized.descriptor.targets.required_mods, {"pycoalprocessing"}),
      "canonical descriptor retains the forestry provider: " .. key)
    for _, line in ipairs({"2.1", "2.0", "1.1", "1.0"}) do
      local profile = assert(actual_profiles.profiles[line])
      package.loaded["prototypes.mir.platform.factorio.target_profiles"] = {current = function() return profile end}
      package.loaded["prototypes.mir.platform.factorio.target_line"] = nil
      local target_line = require("prototypes.mir.platform.factorio.target_line")
      check(target_line.stream_supported(key, normalized) == (line == "2.1" or line == "2.0"),
        "forestry requires actual recipe-productivity capability: " .. line .. " " .. key)
    end
  end
  package.loaded["prototypes.mir.platform.factorio.target_profiles"] = saved_profiles
  package.loaded["prototypes.mir.platform.factorio.target_line"] = saved_target_line
  lookup.mod_exists, lookup.fluid_prototype, lookup.item_prototype = saved_mod_exists, saved_fluid, saved_item
  package.loaded["prototypes.mir.capabilities.science_integration.science_packs"] = saved_science
  package.loaded["prototypes.mir.planner.technology_requirements"] = saved_technology_requirements
end
for _, key in ipairs(expected_keys) do
  local staged = streams[key] and streams[key].staged_progression
  local valid, reason = progression.validate(key, staged)
  check(valid, "actual material stream uses the shared valid progression declaration for "
    .. key .. ": " .. tostring(reason))
end
for _, key in ipairs(expected_k2_keys) do
  local valid, reason = progression.validate(key, streams[key].staged_progression)
  check(valid, "actual source attaches the shared continuation declaration for " .. key .. ": " .. tostring(reason))
end
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
local current_streams = load_streams_for({
  base = "2.1.21", Krastorio2 = "2.1.3", ["Krastorio2-spaced-out"] = "2.0.13"
})
local current_imersite = current_streams.research_material_imersite.staged_progression
check(progression.validate("research_material_imersite", current_imersite),
  "the reviewed 2.1.21 engine retains the admitted powder continuation")
check(current_imersite.continuation.technology_name == exact_imersite.continuation.technology_name
    and current_imersite.legacy.last_level == exact_imersite.legacy.last_level,
  "current engine preserves the existing finite and continuation identities")
for _, tuple in ipairs({
  {base="2.1.22", Krastorio2="2.1.3", ["Krastorio2-spaced-out"]="2.0.13"},
  {base="2.1.21", Krastorio2="2.1.2", ["Krastorio2-spaced-out"]="2.0.13"},
  {base="2.1.21", Krastorio2="2.1.3", ["Krastorio2-spaced-out"]="2.0.14"}
}) do
  check(load_streams_for(tuple).research_material_imersite.staged_progression == nil,
    "neighboring engine and overhaul tuples remain outside continuation admission")
end
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
recipe_caps.very_broad = {maximum_productivity = 1000000}
local bounded_extreme, bounded_extreme_reason = progression.highest_useful_level(
  {effect("very_broad", 0.0001)}, recipe, 8)
check(bounded_extreme == 8,
  "a representable configured cap bounds oversized positive recipe headroom: " .. tostring(bounded_extreme_reason))
local unbounded_extreme, unbounded_extreme_reason = progression.highest_useful_level(
  {effect("very_broad", 0.0001)}, recipe, "infinite")
check(unbounded_extreme == nil and unbounded_extreme_reason == "material-level-domain-exceeded",
  "unbounded oversized headroom still fails the technology level domain")
local domain_edge = progression.highest_useful_level(
  {effect("very_broad", 0.0001)}, recipe, 2147483647)
check(domain_edge == 2147483647, "the exact finite level-domain boundary remains representable")
local domain_overflow, domain_overflow_reason = progression.highest_useful_level(
  {effect("very_broad", 0.0001)}, recipe, 2147483648)
check(domain_overflow == nil and domain_overflow_reason == "material-level-domain-exceeded",
  "a configured cap beyond the technology level domain cannot admit oversized headroom")
local bounded_legacy, bounded_legacy_reason = progression.highest_useful_level(
  {effect("very_broad", 0.0001)}, recipe, 3)
check(bounded_legacy == nil and bounded_legacy_reason == "configured-material-cap-before-continuation",
  "bounding oversized headroom at level three preserves the explicit legacy-only disposition")
local bounded_missing, bounded_missing_reason = progression.highest_useful_level(
  {effect("very_broad", 0.0001), effect("missing", 0.0001)}, recipe, 8)
check(bounded_missing == nil and bounded_missing_reason == "material-recipe-unavailable",
  "a finite configured cap cannot excuse an unavailable effect recipe")
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

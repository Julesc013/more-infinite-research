local techs = data.raw.technology or {}
local recipes = data.raw.recipe or {}
local is_space_age = mods and mods["space-age"] ~= nil
local use_installed_space_age_icons =
  settings
  and settings.startup
  and settings.startup["mir-use-installed-space-age-icons"]
  and settings.startup["mir-use-installed-space-age-icons"].value == true
local stream_registry = require("__more-infinite-research__.prototypes.mir.streams.registry")
local stream_descriptor = require("__more-infinite-research__.prototypes.mir.domain.streams.descriptor")
local raw_stream_catalog = require("__more-infinite-research__.prototypes.mir.domain.streams.raw_catalog")
local canonical_recipe_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_facts")
local pipeline_commands = require("__more-infinite-research__.prototypes.mir.pipeline.commands")
local capability_registry = require("__more-infinite-research__.prototypes.mir.capabilities.registry")
local stream_compiler = require("__more-infinite-research__.prototypes.mir.planner.stream_compiler")
local compilation_plan = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan")
local target_profile = require("__more-infinite-research__.prototypes.mir.platform.factorio.target_profiles").current()
local recipe_semantics = require("__more-infinite-research__.prototypes.mir.domain.facts.recipe_semantics")

local function fail(message)
  error("MIR validation failed: " .. message)
end

local blocked_pickup_effect_types = {
  ["character-item-pickup-distance"] = true,
  ["character-loot-pickup-distance"] = true
}

local function assert_no_blocked_pickup_effects()
  for tech_name, tech in pairs(techs) do
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if blocked_pickup_effect_types[effect.type] then
        fail("technology " .. tech_name .. " uses blocked pickup reach effect " .. effect.type .. ".")
      end
    end
  end
end

local function assert_generation_plan_v3()
  local plan = stream_compiler.latest_artifact()
  if not plan or plan.schema ~= 3 or not plan.validation_summary or plan.validation_summary.valid ~= true then
    fail("missing accepted GenerationPlan schema 3 artifact")
  end
  if type(plan.plan_fingerprint) ~= "string" or not plan.plan_fingerprint:match("^mir32%-") then
    fail("GenerationPlan schema 3 fingerprint is missing")
  end
  for _, source in ipairs({"facts", "rules", "compatibility_packs", "target_profile"}) do
    if type(plan.source_fingerprints[source]) ~= "string" then
      fail("GenerationPlan source fingerprint is missing: " .. source)
    end
  end
  for _, row in ipairs(plan.rows or {}) do
    for _, gate in ipairs({"target_supported", "effect_valid", "owner_conflict_free", "science_compatible", "lab_compatible", "prerequisites_acyclic", "loop_safe", "progression_safe", "migration_safe", "output_identity_safe"}) do
      local proof = row.gates and row.gates[gate]
      if type(proof) ~= "table" or type(proof.passed) ~= "boolean"
        or type(proof.status) ~= "string" or type(proof.evidence) ~= "table" then
        fail("GenerationPlan row is missing evidence gate " .. gate)
      end
    end
  end
end

local function assert_compiler_telemetry()
  local telemetry = compilation_plan.snapshot().telemetry
  if not telemetry or telemetry.schema ~= 1 or telemetry.witness_limit ~= 64 then
    fail("compiler telemetry schema or witness limit changed")
  end
  for _, counter in ipairs({
    "recipes", "technologies", "effects", "graph_edges", "graph_components", "cyclic_components",
    "recipe_index_scans", "recipe_fact_copies", "candidate_operations", "accepted_operations",
    "rejected_operations", "diagnostic_rows"
  }) do
    if type(telemetry.counters[counter]) ~= "number" then
      fail("compiler telemetry counter is missing: " .. counter)
    end
  end
  for _, phase in ipairs({"snapshot", "graph", "planning", "postconditions"}) do
    local value = telemetry.phases[phase]
    if type(value) ~= "table" or type(value.runs) ~= "number" or value.runs < 1
      or type(value.seconds) ~= "number" then
      fail("compiler telemetry phase is missing or incomplete: " .. phase)
    end
  end
end

local function assert_compiler_evidence()
  local prototype = (data.raw["mod-data"] or {})["more-infinite-research-compiler-evidence"]
  local evidence = prototype and prototype.data
  local plan = compilation_plan.snapshot()
  if not evidence or evidence.schema ~= 1
    or evidence.semantic_fingerprint ~= plan.semantic_fingerprint
    or type(evidence.telemetry_fingerprint) ~= "string"
    or type(evidence.input_sanitation_fingerprint) ~= "string"
    or type(evidence.output_sanitation_fingerprint) ~= "string"
    or type(evidence.evidence_fingerprint) ~= "string"
    or not evidence.input_sanitation_ledger or evidence.input_sanitation_ledger.pass ~= "input"
    or not evidence.output_sanitation_ledger or evidence.output_sanitation_ledger.pass ~= "output"
  then
    fail("content-addressed compiler evidence or sanitation ledgers are missing")
  end
end

local function assert_decision_record_v2()
  local decision_record = require("__more-infinite-research__.prototypes.mir.domain.decisions.decision_record")
  local confidence = decision_record.confidence({identity = 1, family = 0.95, loop_safety = 0.25, total = 0.75})
  if confidence.identity ~= "exact" or confidence.family ~= "structural"
    or confidence.loop_safety ~= "heuristic" or confidence.total ~= 0.75 then
    fail("DecisionRecordV2 typed confidence contract changed")
  end
end

local function assert_setting_target_ownership()
  local settings_catalog = require("__more-infinite-research__.prototypes.mir.settings.catalog")
  local expected = {
    ["mir-pipeline-extent-multiplier"] = "pipeline_extent",
    ["mir-prototype-productivity-cap"] = "prototype_limits",
    ["mir-settings-profile-import"] = "settings_profiles",
    ["mir-unrestricted-modules"] = "module_permissions",
    ["mir-debug-scripted-effects"] = "scripted_techs"
  }
  for setting_name, feature in pairs(expected) do
    local spec = settings_catalog.spec(setting_name)
    if not spec or not spec.targets or spec.targets.requires_features[1] ~= feature then
      fail("setting declaration does not own target requirement: " .. setting_name)
    end
  end
end

local function assert_descriptor_contracts()
  local snapshot = stream_registry.snapshot()
  local count = 0
  for key, spec in pairs(snapshot) do
    count = count + 1
    local descriptor = spec.descriptor
    if not descriptor or descriptor.schema ~= 1 or descriptor.id ~= key then
      fail("stream " .. key .. " is missing its canonical descriptor identity")
    end
    if descriptor.kind ~= "recipe-productivity" and descriptor.kind ~= "direct-effect" then
      fail("stream " .. key .. " has invalid descriptor kind")
    end
    if not descriptor.effect or not descriptor.effect.canonical_anchor
      or descriptor.effect.canonical_anchor <= 0 then
      fail("stream " .. key .. " is missing its typed positive effect contract")
    end
    if not descriptor.targets or type(descriptor.targets.requires_features) ~= "table"
      or type(descriptor.targets.required_effect_types) ~= "table" then
      fail("stream " .. key .. " is missing positive target requirements")
    end
  end
  if count ~= target_profile.expected_stream_count then
    fail("canonical descriptor catalog expected " .. tostring(target_profile.expected_stream_count) .. " streams, got " .. tostring(count))
  end

  local first = stream_registry.get("research_copper")
  first.descriptor.effect.canonical_anchor = 999
  first.items[1] = "mutated-through-copy"
  local second = stream_registry.get("research_copper")
  if second.descriptor.effect.canonical_anchor == 999 or second.items[1] == "mutated-through-copy" then
    fail("registry copies can mutate the require-cached canonical descriptor")
  end

  local productivity_a = stream_descriptor.normalize("order-productivity", {
    groups = {{change = 0.05}, {change = 0.10}}
  })
  local productivity_b = stream_descriptor.normalize("order-productivity", {
    groups = {{change = 0.10}, {change = 0.05}}
  })
  if productivity_a.descriptor.effect.canonical_anchor ~= productivity_b.descriptor.effect.canonical_anchor then
    fail("productivity effect contract depends on declaration order")
  end

  local direct_a = stream_descriptor.normalize("order-direct", {
    direct_effects = {
      {type = "gun-speed", ammo_category = "rocket", modifier = 0.1},
      {type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.2}
    }
  })
  local direct_b = stream_descriptor.normalize("order-direct", {
    direct_effects = {
      {type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.2},
      {type = "gun-speed", ammo_category = "rocket", modifier = 0.1}
    }
  })
  if direct_a.descriptor.effect.canonical_anchor ~= direct_b.descriptor.effect.canonical_anchor then
    fail("direct effect contract depends on declaration order")
  end

  local unique_ok = pcall(raw_stream_catalog.merge_unique, {
    {name = "one", streams = {duplicate = {}}},
    {name = "two", streams = {duplicate = {}}}
  })
  if unique_ok then fail("duplicate stream ids did not fail closed") end

  local overlay_ok = pcall(stream_descriptor.normalize, "overlay-injection", {
    descriptor = {},
    groups = {{change = 0.1}}
  })
  if overlay_ok then fail("overlay descriptor injection did not fail closed") end
end

assert_descriptor_contracts()

local function assert_recipe_fact_contracts()
  if canonical_recipe_facts.scan_count() ~= 1 then
    fail("canonical recipe facts scanned recipe prototypes more than once")
  end
  local first = canonical_recipe_facts.get("iron-gear-wheel")
  if not first or #first.result_names == 0 then fail("canonical iron gear recipe fact is missing") end
  first.result_names[1] = "mutated-through-copy"
  local second = canonical_recipe_facts.get("iron-gear-wheel")
  if second.result_names[1] == "mutated-through-copy" then
    fail("recipe fact consumer mutated the canonical require-cached fact")
  end
  local synthetic_names = canonical_recipe_facts.candidate_names({
    ["mir-fixture-synthetic-item-1000"] = true
  }, {}, {})
  if #synthetic_names ~= 1 or synthetic_names[1] ~= "mir-fixture-synthetic-recipe-1000" then
    fail("large synthetic recipe index did not return the exact terminal recipe")
  end
  if canonical_recipe_facts.scan_count() ~= 1 then
    fail("large synthetic recipe queries triggered a repeated full recipe scan")
  end

  local default_policy = canonical_recipe_facts.get("mir-fixture-default-productivity-policy")
  if not default_policy or default_policy.declared_allow_productivity ~= nil
    or default_policy.effective_allow_productivity ~= false then
    fail("omitted allow_productivity did not resolve to the Factorio 2.1 false default")
  end

  local complete_shape = canonical_recipe_facts.get("mir-fixture-complete-product-shape")
  local product = complete_shape and complete_shape.variants[1] and complete_shape.variants[1].results[1]
  if not product or product.independent_probability ~= 0.5 or product.extra_count_fraction ~= 0.25
    or product.percent_spoiled ~= 0.1 or product.always_fresh ~= true
    or product.reset_freshness_on_craft ~= true or product.quality_min ~= "normal"
    or product.quality_max ~= "normal" or product.quality_change ~= 0
    or product.affected_by_quality ~= false then
    fail("RecipeFactV2 did not preserve the complete Factorio 2.1 product shape")
  end

  local inherited = recipe_semantics.resolve(
    {allow_productivity = true, maximum_productivity = 2.5},
    {allow_quality = false},
    target_profile
  )
  if inherited.effective_allow_productivity ~= true or inherited.effective_allow_quality ~= false
    or inherited.effective_maximum_productivity ~= 2.5 then
    fail("recipe variant policy did not inherit root declarations")
  end

  local probability_fields = {}
  for _, field in ipairs(target_profile.prototype_shapes.product_probability_fields or {}) do
    probability_fields[field] = true
  end
  for _, field in ipairs({"independent_probability", "shared_probability", "extra_count_fraction", "quality_min", "quality_max"}) do
    if not probability_fields[field] then fail("target profile omits product field " .. field) end
  end
end

assert_recipe_fact_contracts()

local function assert_pipeline_command_contracts()
  local catalog = pipeline_commands.snapshot()
  local count = 0
  local allowed_kinds = {
    mutation = true,
    emission = true,
    plan = true,
    assertion = true,
    report = true,
    publication = true
  }
  for id, command in pairs(catalog) do
    count = count + 1
    if command.id ~= id or not allowed_kinds[command.kind] then
      fail("pipeline command " .. tostring(id) .. " has invalid identity or kind")
    end
    if type(command.requires_features) ~= "table" or type(command.implementation) ~= "string"
      or type(command.phase) ~= "number" or type(command.dependencies) ~= "table" then
      fail("pipeline command " .. id .. " is missing requirements, ordering, or implementation ownership")
    end
  end
  if count ~= 21 then fail("expected 21 governed pipeline commands, got " .. tostring(count)) end
end

assert_pipeline_command_contracts()

local function assert_capability_lifecycle_contracts()
  local resolvers = capability_registry.resolvers()
  if #resolvers ~= 3 then fail("expected three governed capability resolvers") end
  for _, resolver in ipairs(resolvers) do
    local functions = {}
    for _, stage in ipairs({"discover", "classify", "propose", "validate", "materialize", "result"}) do
      if type(resolver[stage]) ~= "function" then fail(resolver.id .. " is missing lifecycle stage " .. stage) end
      if functions[resolver[stage]] then fail(resolver.id .. " aliases lifecycle stage " .. stage) end
      functions[resolver[stage]] = true
    end
  end
end

assert_capability_lifecycle_contracts()

local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

local function has_prerequisite(tech, prerequisite)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local function startup_setting_bool(name, fallback)
  local setting = settings and settings.startup and settings.startup[name]
  if setting and setting.value ~= nil then return setting.value == true end
  return fallback == true
end

local function effective_base_extension_enabled(key, default_enabled)
  return startup_setting_bool("mir-enable-" .. key, default_enabled)
end

local function sorted_csv(values)
  table.sort(values)
  return table.concat(values, ", ")
end

local function chain_levels(key)
  local pattern = "^" .. escape_pattern(key) .. "%-(%d+)$"
  local finite = {}
  local infinite = {}

  for name, tech in pairs(techs) do
    local level = tonumber(string.match(name, pattern))
    if level then
      local row = {
        name = name,
        level = level,
        tech = tech
      }
      if tech.max_level == "infinite" then
        table.insert(infinite, row)
      else
        table.insert(finite, row)
      end
    end
  end

  table.sort(finite, function(a, b) return a.level < b.level end)
  table.sort(infinite, function(a, b) return a.level < b.level end)
  return finite, infinite
end

local function assert_chain_extended_once(key)
  local finite, infinite = chain_levels(key)
  if #finite == 0 then
    fail("expected vanilla chain " .. key .. " to have finite levels before MIR extends it.")
  end
  if #infinite ~= 1 then
    local names = {}
    for _, row in ipairs(infinite) do table.insert(names, row.name) end
    fail("expected vanilla chain " .. key .. " to have exactly one infinite continuation; got "
      .. tostring(#infinite) .. " (" .. sorted_csv(names) .. ").")
  end

  local base = finite[#finite]
  local generated = infinite[1]
  local expected_name = key .. "-" .. tostring(base.level + 1)
  if generated.name ~= expected_name then
    fail("expected vanilla chain " .. key .. " to continue as " .. expected_name .. ", got " .. generated.name .. ".")
  end

  if not generated.tech.unit or not generated.tech.unit.count_formula then
    fail("generated continuation " .. generated.name .. " does not use an infinite count formula.")
  end
  if generated.tech.upgrade ~= true then
    fail("generated continuation " .. generated.name .. " is not marked as an upgrade.")
  end
  if not has_prerequisite(generated.tech, base.name) then
    fail("generated continuation " .. generated.name .. " does not depend on prior finite level " .. base.name .. ".")
  end
  if not generated.tech.effects or #generated.tech.effects == 0 then
    fail("generated continuation " .. generated.name .. " has no effects.")
  end
end

local function assert_chain_not_extended(key)
  local _, infinite = chain_levels(key)
  if #infinite > 0 then
    local names = {}
    for _, row in ipairs(infinite) do table.insert(names, row.name) end
    fail("expected disabled vanilla chain " .. key .. " to have no MIR infinite continuation; got " .. sorted_csv(names) .. ".")
  end
end

local base_extension_defaults = {
  ["braking-force"] = true,
  ["research-speed"] = true,
  ["worker-robots-storage"] = true,
  ["inserter-capacity-bonus"] = false,
  ["weapon-shooting-speed"] = true,
  ["laser-shooting-speed"] = true
}

assert_no_blocked_pickup_effects()
assert_generation_plan_v3()
assert_compiler_telemetry()
assert_compiler_evidence()
assert_decision_record_v2()
assert_setting_target_ownership()

for key, default_enabled in pairs(base_extension_defaults) do
  if effective_base_extension_enabled(key, default_enabled) then
    assert_chain_extended_once(key)
  else
    assert_chain_not_extended(key)
  end
end

local function startup_setting_number(name)
  local setting = settings and settings.startup and settings.startup[name]
  return setting and tonumber(setting.value) or nil
end

local function assert_base_effect_value(key, effect_type, expected)
  local _, infinite = chain_levels(key)
  if #infinite ~= 1 then
    fail("cannot inspect retained effect setting for " .. key .. ": expected one infinite continuation.")
  end
  for _, effect in ipairs(infinite[1].tech.effects or {}) do
    if effect.type == effect_type then
      local actual = tonumber(effect.modifier)
      if not actual or math.abs(actual - expected) > 0.000001 then
        fail("retained effect setting for " .. key .. " emitted " .. tostring(actual)
          .. ", expected " .. tostring(expected) .. ".")
      end
      return
    end
  end
  fail("retained effect setting for " .. key .. " could not find effect " .. effect_type .. ".")
end

if startup_setting_number("mir-effect-per-level-research-speed") == 120 then
  assert_base_effect_value("research-speed", "laboratory-speed", 1.2)
end
if startup_setting_number("mir-effect-per-level-worker-robots-storage") == 2 then
  assert_base_effect_value("worker-robots-storage", "worker-robot-storage", 2)
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function recipe_productivity_change(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return effect.change
    end
  end
  return nil
end

local furnace_effect_setting = settings
  and settings.startup
  and settings.startup["ips-effect-per-level-research_furnace"]
local furnace_anchor = furnace_effect_setting and furnace_effect_setting.value or nil
if furnace_anchor ~= 20 and furnace_anchor ~= 40 then
  fail("furnace effect-per-level anchor should default to the primary 20% tier; got " .. tostring(furnace_anchor) .. ".")
end
if furnace_anchor == 40 then
  local furnace_technology = techs["recipe-prod-research_furnace-1"]
  if not furnace_technology then fail("missing furnace technology for mixed-tier effect scaling check.") end
  for recipe_name, expected in pairs({
    ["stone-furnace"] = 0.40,
    ["steel-furnace"] = 0.20,
    ["electric-furnace"] = 0.10
  }) do
    local actual = recipe_productivity_change(furnace_technology, recipe_name)
    if not actual or math.abs(actual - expected) > 0.000001 then
      fail("scaled furnace effect for " .. recipe_name .. " was " .. tostring(actual)
        .. ", expected " .. tostring(expected) .. ".")
    end
  end
end

local function recipe_productivity_owners(recipe_name)
  local owners = {}
  for tech_name, tech in pairs(techs) do
    if tech.max_level == "infinite" and has_recipe_productivity_effect(tech, recipe_name) then
      table.insert(owners, tech_name)
    end
  end
  table.sort(owners)
  return owners
end

local constant_overlay_by_kind = {
  ["recipe-productivity"] = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
  speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["movement-speed"] = "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
  mining = "__core__/graphics/icons/technology/constants/constant-mining.png",
  battery = "__core__/graphics/icons/technology/constants/constant-battery.png",
  capacity = "__core__/graphics/icons/technology/constants/constant-capacity.png",
  damage = "__core__/graphics/icons/technology/constants/constant-damage.png",
  range = "__core__/graphics/icons/technology/constants/constant-range.png",
  ["braking-force"] = "__core__/graphics/icons/technology/constants/constant-braking-force.png",
  equipment = "__core__/graphics/icons/technology/constants/constant-equipment.png",
  count = "__core__/graphics/icons/technology/constants/constant-count.png"
}

local function expected_icon_badge(tech)
  local saw_recipe_productivity = false
  for _, effect in ipairs((tech and tech.effects) or {}) do
    local effect_type = effect.type
    if effect_type == "change-recipe-productivity" then
      saw_recipe_productivity = true
    elseif effect_type == "laboratory-productivity" then
      return "recipe-productivity"
    elseif effect_type == "gun-speed" or effect_type == "character-crafting-speed" then
      return "speed"
    elseif effect_type == "character-running-speed" then
      return "movement-speed"
    elseif effect_type == "character-mining-speed" then
      return "mining"
    elseif effect_type == "character-reach-distance"
      or effect_type == "character-build-distance"
      or effect_type == "character-resource-reach-distance"
      or effect_type == "character-item-drop-distance" then
      return "range"
    elseif effect_type == "character-inventory-slots-bonus"
      or effect_type == "character-logistic-trash-slots"
    then
      return "capacity"
    elseif effect_type == "worker-robot-battery" then
      return "battery"
    elseif effect_type == "max-cargo-bay-unloading-distance" then
      return "range"
    elseif effect_type == "cargo-landing-pad-count" then
      return "count"
    elseif effect_type == "braking-force" then
      return "braking-force"
    elseif effect_type == "ammo-damage" or effect_type == "turret-attack" then
      return "damage"
    end
  end

  if saw_recipe_productivity then return "recipe-productivity" end
  return nil
end

local function icon_constant_kinds(tech)
  local kinds = {}
  for _, layer in ipairs((tech and tech.icons) or {}) do
    for kind, icon_path in pairs(constant_overlay_by_kind) do
      if layer.icon == icon_path then
        kinds[kind] = true
      end
    end
  end
  return kinds
end

local function assert_generated_icon_badge(tech_name, tech)
  local expected = expected_icon_badge(tech)
  if not expected then return end

  if not tech.icons or #tech.icons == 0 then
    fail("generated technology " .. tech_name .. " has no icon layers.")
  end

  local kinds = icon_constant_kinds(tech)
  if not kinds[expected] then
    fail("generated technology " .. tech_name .. " is missing expected " .. expected .. " icon badge.")
  end

  for kind, _ in pairs(kinds) do
    if kind ~= expected then
      fail("generated technology " .. tech_name .. " has unexpected " .. kind
        .. " icon badge; expected only " .. expected .. ".")
    end
  end
end

local function assert_no_space_age_icon_path_in_base(tech_name, tech)
  if is_space_age or use_installed_space_age_icons then return end

  for _, layer in ipairs((tech and tech.icons) or {}) do
    if type(layer.icon) == "string" and string.find(layer.icon, "__space-age__", 1, true) then
      fail("base-only generated technology " .. tech_name .. " resolved Space Age icon path " .. layer.icon .. ".")
    end
  end
end

local function prototype_icon_paths(prototype)
  local paths = {}
  if not prototype then return paths end
  if prototype.icons then
    for _, layer in ipairs(prototype.icons) do
      if layer.icon then paths[layer.icon] = true end
    end
  elseif prototype.icon then
    paths[prototype.icon] = true
  end
  return paths
end

local function assert_tech_uses_item_icon(tech_name, item_name)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated technology " .. tech_name .. " for icon assertion.")
  end

  local item = (data.raw.item or {})[item_name]
    or (data.raw.ammo or {})[item_name]
    or (data.raw["rail-planner"] or {})[item_name]
  local expected_paths = prototype_icon_paths(item)
  if not next(expected_paths) then
    fail("missing item icon source for " .. item_name .. ".")
  end

  for _, layer in ipairs(tech.icons or {}) do
    if expected_paths[layer.icon] then return end
  end

  fail("generated technology " .. tech_name .. " does not use " .. item_name .. " item art.")
end

local function assert_tech_uses_technology_icon(tech_name, source_tech_name)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated technology " .. tech_name .. " for icon assertion.")
  end

  local source = techs[source_tech_name]
  local expected_paths = prototype_icon_paths(source)
  if not next(expected_paths) then
    fail("missing technology icon source for " .. source_tech_name .. ".")
  end

  for _, layer in ipairs(tech.icons or {}) do
    if expected_paths[layer.icon] then return end
  end

  fail("generated technology " .. tech_name .. " does not use " .. source_tech_name .. " technology art.")
end

local function assert_tech_uses_icon_path(tech_name, icon_path)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated technology " .. tech_name .. " for icon path assertion.")
  end

  for _, layer in ipairs(tech.icons or {}) do
    if layer.icon == icon_path then return end
  end

  fail("generated technology " .. tech_name .. " does not use expected icon path " .. icon_path .. ".")
end

local owners_by_recipe = {}
for tech_name, tech in pairs(techs) do
  if string.match(tech_name, "^recipe%-prod%-") then
    if tech.max_level ~= "infinite" then
      fail("generated stream technology " .. tech_name .. " is not infinite.")
    end
    if not tech.unit or not tech.unit.count_formula then
      fail("generated stream technology " .. tech_name .. " does not use an infinite count formula.")
    end
    if tech.upgrade ~= true then
      fail("generated stream technology " .. tech_name .. " is not marked as an upgrade.")
    end
    if not tech.effects or #tech.effects == 0 then
      fail("generated stream technology " .. tech_name .. " has no effects.")
    end
    assert_generated_icon_badge(tech_name, tech)
    assert_no_space_age_icon_path_in_base(tech_name, tech)
  end

  if tech.max_level == "infinite" then
    local owner_recipes = {}
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe then
        owner_recipes[effect.recipe] = true
      end
    end
    for recipe_name, _ in pairs(owner_recipes) do
      owners_by_recipe[recipe_name] = owners_by_recipe[recipe_name] or {}
      table.insert(owners_by_recipe[recipe_name], tech_name)
    end
  end
end

assert_tech_uses_item_icon("recipe-prod-research_heavy_ammo-1", "cannon-shell")
assert_tech_uses_technology_icon("recipe-prod-research_cannon_shooting_speed-1", "weapon-shooting-speed-3")
if is_space_age then
  assert_tech_uses_technology_icon("recipe-prod-research_electric_shooting_speed-1", "electric-weapons-damage-1")
elseif use_installed_space_age_icons then
  assert_tech_uses_icon_path("recipe-prod-research_electric_shooting_speed-1", "__space-age__/graphics/technology/electric-weapons-damage.png")
else
  assert_tech_uses_technology_icon("recipe-prod-research_electric_shooting_speed-1", "discharge-defense-equipment")
end
if techs["recipe-prod-research_processing_unit-1"] then
  if use_installed_space_age_icons then
    assert_tech_uses_icon_path("recipe-prod-research_processing_unit-1", "__space-age__/graphics/technology/processing-unit-productivity.png")
  else
    assert_tech_uses_technology_icon("recipe-prod-research_processing_unit-1", "processing-unit")
  end
end
if techs["research-productivity"] then
  assert_tech_uses_technology_icon("recipe-prod-research_science_pack_productivity-1", "research-productivity")
elseif use_installed_space_age_icons then
  assert_tech_uses_icon_path("recipe-prod-research_science_pack_productivity-1", "__space-age__/graphics/technology/research-productivity.png")
else
  assert_tech_uses_technology_icon("recipe-prod-research_science_pack_productivity-1", "space-science-pack")
end
if mods and mods["elevated-rails"] then
  assert_tech_uses_technology_icon("recipe-prod-research_rails-1", "elevated-rail")
elseif use_installed_space_age_icons then
  assert_tech_uses_icon_path("recipe-prod-research_rails-1", "__elevated-rails__/graphics/technology/elevated-rail.png")
else
  assert_tech_uses_item_icon("recipe-prod-research_rails-1", "rail")
end
assert_tech_uses_technology_icon("recipe-prod-research_walls-1", "gate")
if techs["recipe-prod-research_lab_productivity-1"] then
  if use_installed_space_age_icons then
    assert_tech_uses_icon_path("recipe-prod-research_lab_productivity-1", "__space-age__/graphics/technology/research-productivity.png")
  else
    assert_tech_uses_technology_icon("recipe-prod-research_lab_productivity-1", "military-science-pack")
  end
end
if techs["recipe-prod-research_rocket_fuel-1"] then
  if use_installed_space_age_icons then
    assert_tech_uses_icon_path("recipe-prod-research_rocket_fuel-1", "__space-age__/graphics/technology/rocket-fuel-productivity.png")
  else
    assert_tech_uses_technology_icon("recipe-prod-research_rocket_fuel-1", "rocket-fuel")
  end
end
if use_installed_space_age_icons then
  assert_tech_uses_icon_path("recipe-prod-research_low_density_structure-1", "__space-age__/graphics/technology/low-density-structure-productivity.png")
  assert_tech_uses_icon_path("recipe-prod-research_plastic-1", "__space-age__/graphics/technology/plastics-productivity.png")
end

for recipe_name, owners in pairs(owners_by_recipe) do
  table.sort(owners)
  if #owners > 1 then
    fail("recipe " .. recipe_name .. " has multiple infinite productivity owners: " .. table.concat(owners, ", "))
  end
end

local function assert_recipe_owner(recipe_name, expected_owner)
  if not recipes[recipe_name] then return end

  local owner = techs[expected_owner]
  if not owner or owner.max_level ~= "infinite" then
    fail("missing expected infinite productivity owner " .. expected_owner .. " for recipe " .. recipe_name .. ".")
  end
  if not has_recipe_productivity_effect(owner, recipe_name) then
    fail("expected owner " .. expected_owner .. " does not cover recipe " .. recipe_name .. ".")
  end

  local owners = recipe_productivity_owners(recipe_name)
  if #owners ~= 1 or owners[1] ~= expected_owner then
    fail("recipe " .. recipe_name .. " should have exactly one infinite productivity owner. Expected "
      .. expected_owner .. ", got: " .. table.concat(owners, ", "))
  end
end

for _, expectation in ipairs({
  { recipe = "electronic-circuit", owner = "recipe-prod-research_electronic_circuit-1" },
  { recipe = "advanced-circuit", owner = "recipe-prod-research_advanced_circuit-1" },
  { recipe = "rail", owner = "recipe-prod-research_rails-1" },
  { recipe = "rail-support", owner = "recipe-prod-research_rails-1" },
  { recipe = "rail-ramp", owner = "recipe-prod-research_rails-1" }
}) do
  assert_recipe_owner(expectation.recipe, expectation.owner)
end

if is_space_age then
  if techs["recipe-prod-research_agricultural_growth_speed-1"] then
    assert_tech_uses_technology_icon("recipe-prod-research_agricultural_growth_speed-1", "agriculture")
  end

  for _, key in ipairs({"research_spoilage_preservation", "research_agricultural_growth_speed"}) do
    local technology = techs["recipe-prod-" .. key .. "-1"]
    if technology then
      local effect = technology.effects and technology.effects[1]
      local selected = settings.startup["ips-effect-per-level-" .. key]
      if not effect or effect.type ~= "nothing" or type(effect.effect_description) ~= "table" then
        fail(key .. " scripted effect description is missing")
      end
      if not selected or tonumber(effect.effect_description[2]) ~= tonumber(selected.value) then
        fail(key .. " scripted effect description does not carry selected value")
      end
    end
  end

  for _, tech_name in ipairs({
    "recipe-prod-research_lab_productivity-1",
    "recipe-prod-research_processing_unit-1",
    "recipe-prod-research_low_density_structure-1",
    "recipe-prod-research_plastic-1",
    "recipe-prod-research_rocket_fuel-1"
  }) do
    if techs[tech_name] then
      fail("Space Age should not create parallel MIR productivity technology " .. tech_name .. ".")
    end
  end

  for _, expectation in ipairs({
    { recipe = "processing-unit", owner = "processing-unit-productivity" },
    { recipe = "low-density-structure", owner = "low-density-structure-productivity" },
    { recipe = "casting-low-density-structure", owner = "low-density-structure-productivity" },
    { recipe = "plastic-bar", owner = "plastic-bar-productivity" },
    { recipe = "bioplastic", owner = "plastic-bar-productivity" },
    { recipe = "rocket-fuel", owner = "rocket-fuel-productivity" },
    { recipe = "rocket-fuel-from-jelly", owner = "rocket-fuel-productivity" },
    { recipe = "ammonia-rocket-fuel", owner = "rocket-fuel-productivity" }
  }) do
    assert_recipe_owner(expectation.recipe, expectation.owner)
  end
else
  for _, expectation in ipairs({
    { recipe = "processing-unit", owner = "recipe-prod-research_processing_unit-1" },
    { recipe = "low-density-structure", owner = "recipe-prod-research_low_density_structure-1" },
    { recipe = "plastic-bar", owner = "recipe-prod-research_plastic-1" },
    { recipe = "rocket-fuel", owner = "recipe-prod-research_rocket_fuel-1" }
  }) do
    assert_recipe_owner(expectation.recipe, expectation.owner)
  end
end

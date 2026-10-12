-- Source-bound controls for the reduced classic planner.  The fixture loads
-- the real declarations and plan while the generic science/route modules are
-- traps, so a classic result cannot silently depend on generic acquisition.

mods = {base = "2.1.21"}
settings = {startup = {}}
feature_flags = {scripted_techs = true}
log = function() end
data = {raw = {technology = {}, lab = {}, tool = {}, item = {}, ["ammo-category"] = {}}}
function data:extend(rows)
  for _, row in ipairs(rows or {}) do
    self.raw[row.type] = self.raw[row.type] or {}
    self.raw[row.type][row.name] = row
  end
end

for _, name in ipairs({
  "prototypes.mir.streams.registry",
  "prototypes.streams.init",
  "prototypes.mir.planner.stream_compiler.diagnostics",
  "prototypes.mir.capabilities.science_integration.science_packs",
  "prototypes.mir.capabilities.science_integration.science_selector",
  "prototypes.mir.capabilities.science_integration.pack_production_reachability",
  "prototypes.mir.capabilities.science_integration.recipe_route_feasibility",
  "prototypes.mir.capabilities.recipe_productivity.planner"
}) do
  package.preload[name] = function() error("classic planner imported forbidden generic module: " .. name) end
end

package.preload["prototypes.mir.platform.factorio.target_line"] = function()
  return {
    factorio_version = "2.1",
    feature_enabled = function(name) return name == "scripted_techs" end,
    effect_supported = function(effect) return type(effect) == "table" and effect.type ~= nil end
  }
end

local assertions = 0
local function check(condition, detail)
  assert(condition, detail)
  assertions = assertions + 1
end

local function generated_profile(relative_path)
  assert(type(MIR_TEST_REPO_ROOT) == "string" and MIR_TEST_REPO_ROOT ~= "",
    "runner must provide the repository root for generated profile controls")
  local path = MIR_TEST_REPO_ROOT .. "/source/adapters/" .. relative_path
  local chunk, failure = loadfile(path)
  assert(chunk, failure)
  return chunk()
end

local function supports_effect(profile, effect_type)
  for _, candidate in ipairs(profile.supported_effect_types or {}) do
    if candidate == effect_type then return true end
  end
  return false
end

local function check_native_effect_contract(profile, inserter_type, absent_inserter_type, label)
  for _, effect_type in ipairs({
    "train-braking-force-bonus", "laboratory-speed", "worker-robot-storage", inserter_type
  }) do
    check(supports_effect(profile, effect_type), label .. " generated target profile admits " .. effect_type)
  end
  check(not supports_effect(profile, absent_inserter_type),
    label .. " generated target profile rejects the other engine's inserter effect")
end

local f200_profile = generated_profile("f200/prototypes/mir/platform/factorio/target_profiles.lua").current()
local f210_profile = generated_profile("f210/prototypes/mir/platform/factorio/target_profiles.lua").current()
check_native_effect_contract(f200_profile, "bulk-inserter-capacity-bonus", "stack-inserter-capacity-bonus", "F200")
check_native_effect_contract(f210_profile, "bulk-inserter-capacity-bonus", "stack-inserter-capacity-bonus", "F210")
local original_base = mods.base
mods.base = "1.1.110"
local f1_shared_profiles = generated_profile("platform/base-version-profile/target_profiles.lua").profiles
mods.base = original_base
check_native_effect_contract(f1_shared_profiles["1.0"], "stack-inserter-capacity-bonus", "bulk-inserter-capacity-bonus", "shared F100")
check_native_effect_contract(f1_shared_profiles["1.1"], "stack-inserter-capacity-bonus", "bulk-inserter-capacity-bonus", "shared F110")

local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "military-science-pack",
  "chemical-science-pack", "production-science-pack", "utility-science-pack"
}

for _, name in ipairs(SCIENCE) do data.raw.tool[name] = {name = name} end
data.raw["ammo-category"].bullet = {name = "bullet"}
data.raw["ammo-category"].laser = {name = "laser"}

data.raw.lab.lab = {name = "lab", enabled = true, inputs = SCIENCE}
data.raw.technology["utility-science-pack"] = {name = "utility-science-pack", enabled = true, prerequisites = {}}

local base_keys = {
  "braking-force", "research-speed", "worker-robots-storage",
  "inserter-capacity-bonus", "weapon-shooting-speed", "laser-shooting-speed"
}
local BASE_EFFECTS = {
  ["braking-force"] = {{type = "train-braking-force-bonus", modifier = 0.01}},
  ["research-speed"] = {{type = "laboratory-speed", modifier = 0.01}},
  ["worker-robots-storage"] = {{type = "worker-robot-storage", modifier = 1}},
  ["inserter-capacity-bonus"] = {{type = "inserter-stack-size-bonus", modifier = 1}},
  ["weapon-shooting-speed"] = {{type = "gun-speed", ammo_category = "bullet", modifier = 0.01}},
  ["laser-shooting-speed"] = {{type = "gun-speed", ammo_category = "laser", modifier = 0.01}}
}
for _, key in ipairs(base_keys) do
  data.raw.technology[key .. "-1"] = {
    name = key .. "-1", enabled = true, max_level = 1, prerequisites = {},
    effects = BASE_EFFECTS[key],
    unit = {count = 100, time = 30, ingredients = {{"automation-science-pack", 1}}}
  }
end

local plan = require("prototypes.mir.planner.classic.plan")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local function find(rows, key)
  for _, row in ipairs(rows or {}) do
    if row.stream_key == key or row.key == key then return row end
  end
  return nil
end

local function has(list, name)
  for _, value in ipairs(list or {}) do
    if value == name or (type(value) == "table" and (value.name or value[1]) == name) then return true end
  end
  return false
end

local first = plan.compile()
check(#first.stream_plan.rows == 5, "five finite declared direct streams are planned")
check(#first.base_extension_operations == 6 and #first.base_candidates == 6,
  "all six declared native chains are considered without generic discovery")
local direct = find(first.stream_plan.rows, "research_character_mining_speed")
check(direct and direct.action == "emit" and technology_design.is_trusted(direct.technology_design),
  "declared direct row reaches the normal trusted TechnologyDesign boundary")
check(#direct.fields.ingredients == #SCIENCE and direct.diagnostics.science_evaluation == "declared",
  "direct stream uses its finite declared science vector")
check(direct.gates.owner_conflict_free.status == "not-applicable"
  and direct.gates.progression_safe.status == "not-applicable",
  "classic row does not claim generic ownership or progression proof")
local worker = find(first.base_extension_operations, "worker-robots-storage")
check(worker and worker.technology.name == "worker-robots-storage-2"
  and has(worker.technology.prerequisites, "worker-robots-storage-1"),
  "native continuation anchors its real terminal technology")
check(worker.technology.unit.ingredients[1][1] == "automation-science-pack"
  and worker.technology.unit.time == 30 and worker.technology.unit.count == 100,
  "native continuation copies the actual tail unit without science expansion")
check(worker.technology_design and technology_design.is_trusted(worker.technology_design),
  "native continuation reaches the normal trusted TechnologyDesign boundary")

data.raw.technology["inserter-capacity-bonus-1"].effects = {
  {type = "bulk-inserter-capacity-bonus", modifier = 1}
}
local modern_inserter = plan.compile()
check(find(modern_inserter.base_extension_operations, "inserter-capacity-bonus").technology.effects[1].type
  == "bulk-inserter-capacity-bonus",
  "classic declared native continuation accepts the actual modern bulk inserter effect")
data.raw.technology["inserter-capacity-bonus-1"].effects = BASE_EFFECTS["inserter-capacity-bonus"]

-- Native modifier effects are real uint32 fields.  Classic rejects malformed
-- tails and scaling results instead of emitting an invalid prototype.
data.raw.technology["worker-robots-storage-1"].effects = {{type = "worker-robot-storage"}}
local missing_native_modifier = plan.compile()
check(find(missing_native_modifier.base_candidates, "worker-robots-storage").reason
  == "classic_native_tail_invalid_effect_modifier",
  "a declared native effect without a numeric modifier is rejected")
data.raw.technology["worker-robots-storage-1"].effects = {{type = "worker-robot-storage", modifier = "1"}}
local string_native_modifier = plan.compile()
check(find(string_native_modifier.base_candidates, "worker-robots-storage").reason
  == "classic_native_tail_invalid_effect_modifier",
  "a string native modifier is not coerced into a prototype value")
data.raw.technology["worker-robots-storage-1"].effects = {{type = "worker-robot-storage", modifier = 1.5}}
local fractional_native_modifier = plan.compile()
check(find(fractional_native_modifier.base_candidates, "worker-robots-storage").reason
  == "classic_native_tail_invalid_native_modifier",
  "a fractional native modifier is rejected before continuation planning")
data.raw.technology["worker-robots-storage-1"].effects = BASE_EFFECTS["worker-robots-storage"]

data.raw.technology["inserter-capacity-bonus-1"].effects = {
  {type = "bulk-inserter-capacity-bonus", modifier = 2}
}
settings.startup["mir-effect-per-level-inserter-capacity-bonus"] = {value = 3}
local fractional_scaled_native = plan.compile()
check(find(fractional_scaled_native.base_candidates, "inserter-capacity-bonus").reason
  == "classic_native_effect_setting_invalid",
  "a native setting that would emit a fractional uint32 modifier is rejected")
settings.startup["mir-effect-per-level-inserter-capacity-bonus"] = {value = 8}
local valid_scaled_native = plan.compile()
check(find(valid_scaled_native.base_extension_operations, "inserter-capacity-bonus").technology.effects[1].modifier == 4,
  "a whole-number scaled modern bulk modifier remains valid")
settings.startup["mir-effect-per-level-inserter-capacity-bonus"] = nil
data.raw.technology["inserter-capacity-bonus-1"].effects = BASE_EFFECTS["inserter-capacity-bonus"]

data.raw.technology["worker-robots-storage-1"].effects = {
  {type = "worker-robot-storage", modifier = 4294967295}
}
settings.startup["mir-effect-per-level-worker-robots-storage"] = {value = 2}
local overflow_scaled_native = plan.compile()
check(find(overflow_scaled_native.base_candidates, "worker-robots-storage").reason
  == "classic_native_effect_setting_invalid",
  "a scaled uint32 overflow is rejected instead of emitted")
settings.startup["mir-effect-per-level-worker-robots-storage"] = nil
data.raw.technology["worker-robots-storage-1"].effects = BASE_EFFECTS["worker-robots-storage"]

settings.startup["ips-cost-base-research_character_mining_speed"] = {value = 9000}
settings.startup["ips-cost-linear-increment-research_character_mining_speed"] = {value = 50}
settings.startup["ips-cost-growth-research_character_mining_speed"] = {value = 1.5}
settings.startup["ips-research-time-research_character_mining_speed"] = {value = 77}
settings.startup["mir-effect-per-level-worker-robots-storage"] = {value = 2}
settings.startup["mir-research-time-worker-robots-storage"] = {value = 45}
data.raw.technology["worker-robots-storage-1"].effects = {{type = "worker-robot-storage", modifier = 1}}
local configured = plan.compile()
local configured_direct = find(configured.stream_plan.rows, "research_character_mining_speed")
local configured_worker = find(configured.base_extension_operations, "worker-robots-storage")
check(configured_direct.fields.cost_model.base_cost == 9000
  and configured_direct.fields.cost_model.linear_increment == 50
  and configured_direct.fields.cost_model.growth_factor == 1.5
  and configured_direct.fields.research_time == 77,
  "classic direct rows retain configured cost and research-time controls")
check(configured_worker.technology.unit.time == 45
  and configured_worker.technology.effects[1].modifier == 2,
  "classic native continuation retains configured time and effect controls")
settings.startup["ips-cost-base-research_character_mining_speed"] = nil
settings.startup["ips-cost-linear-increment-research_character_mining_speed"] = nil
settings.startup["ips-cost-growth-research_character_mining_speed"] = nil
settings.startup["ips-research-time-research_character_mining_speed"] = nil
settings.startup["mir-effect-per-level-worker-robots-storage"] = nil
settings.startup["mir-research-time-worker-robots-storage"] = nil
data.raw.technology["worker-robots-storage-1"].effects = BASE_EFFECTS["worker-robots-storage"]

data.raw.technology["braking-force-1"].effects = {{type = "recipe-productivity", modifier = 1}}
local foreign_effect = plan.compile()
check(find(foreign_effect.base_candidates, "braking-force").reason == "classic_native_tail_unsupported_effect",
  "an unrelated recipe-productivity effect is never inherited by a declared native chain")
data.raw.technology["braking-force-1"].effects = BASE_EFFECTS["braking-force"]

data.raw.technology["weapon-shooting-speed-1"].effects = {
  {type = "gun-speed", ammo_category = "classic-missing-category", modifier = 0.01}
}
local missing_ammo_category = plan.compile()
check(find(missing_ammo_category.base_candidates, "weapon-shooting-speed").reason == "classic_native_tail_missing_ammo_category",
  "a gun-speed continuation requires an actual referenced ammunition category")
data.raw.technology["weapon-shooting-speed-1"].effects = BASE_EFFECTS["weapon-shooting-speed"]

data.raw.technology["recipe-prod-research_character_mining_speed-1"] = {name = "recipe-prod-research_character_mining_speed-1"}
local output_exists = plan.compile()
local output_skip = find(output_exists.stream_plan.rows, "research_character_mining_speed")
check(output_skip.action == "skip" and output_skip.reason == "classic_output_exists"
  and output_skip.diagnostics.science_evaluation == "uncomputed",
  "existing output is an explicit unsupported classic disposition")
data.raw.technology["recipe-prod-research_character_mining_speed-1"] = nil

data.raw.technology["utility-science-pack"] = nil
local missing_gate = plan.compile()
local missing_skip = find(missing_gate.stream_plan.rows, "research_character_mining_speed")
check(missing_skip.action == "skip" and string.find(missing_skip.reason, "classic_missing_declared_gate", 1, true),
  "missing fixed prerequisite skips explicitly instead of inferring reachability")
data.raw.technology["utility-science-pack"] = {name = "utility-science-pack", enabled = true, prerequisites = {}}

data.raw.tool["utility-science-pack"] = nil
data.raw.item["utility-science-pack"] = {name = "utility-science-pack"}
local missing_tool = plan.compile()
local tool_skip = find(missing_tool.stream_plan.rows, "research_character_mining_speed")
check(tool_skip.action == "skip" and tool_skip.reason == "classic_declared_science_missing_tool"
  and tool_skip.gates.science_compatible.status == "failed",
  "a declared science name without a valid tool is not treated as a compatible laboratory input")
data.raw.tool["utility-science-pack"] = {name = "utility-science-pack"}
data.raw.item["utility-science-pack"] = nil

local ancestors = {}
for index = 1, 65 do
  local name = "classic-bound-" .. tostring(index)
  ancestors[index] = name
  data.raw.technology[name] = {
    name = name,
    enabled = true,
    prerequisites = index < 65 and {"classic-bound-" .. tostring(index + 1)} or {}
  }
end
data.raw.technology["utility-science-pack"].prerequisites = {ancestors[1]}
local bounded_gate = plan.compile()
local bound_skip = find(bounded_gate.stream_plan.rows, "research_character_mining_speed")
check(bound_skip.action == "skip" and bound_skip.reason == "classic_declared_gate_ancestor_bound"
  and bound_skip.gates.prerequisites_acyclic.status == "failed",
  "a declared prerequisite beyond the bounded native ancestor check is explicit, never inferred")
data.raw.technology["utility-science-pack"].prerequisites = {}
for _, name in ipairs(ancestors) do data.raw.technology[name] = nil end

data.raw.lab.lab.inputs = {"automation-science-pack"}
local incompatible_lab = plan.compile()
local lab_skip = find(incompatible_lab.stream_plan.rows, "research_character_mining_speed")
check(lab_skip.action == "skip" and lab_skip.reason == "classic_declared_science_not_accepted"
  and lab_skip.gates.lab_compatible.status == "failed",
  "incompatible fixed science is explicit and does not select a reduced alternative")
data.raw.lab.lab.inputs = SCIENCE

data.raw.technology["worker-robots-storage-1"].enabled = false
local disabled_tail = plan.compile()
check(find(disabled_tail.base_candidates, "worker-robots-storage").reason == "classic_native_ancestor_disabled",
  "disabled native tail is rejected by the bounded native ancestor check")
data.raw.technology["worker-robots-storage-1"].enabled = true

data.raw.technology["braking-force-1"].prerequisites = {"braking-force-1"}
local cyclic_tail = plan.compile()
check(find(cyclic_tail.base_candidates, "braking-force").reason == "classic_native_ancestor_cycle",
  "native ancestor cycle is rejected without loading the generic graph service")
data.raw.technology["braking-force-1"].prerequisites = {}

settings.startup["ips-enable-research_character_mining_speed"] = {value = false}
local disabled_direct = plan.compile()
local disabled_row = find(disabled_direct.stream_plan.rows, "research_character_mining_speed")
check(disabled_row and disabled_row.reason == "classic_disabled",
  "existing direct enable control remains a cheap declared switch: " .. tostring(disabled_row and disabled_row.reason))
check(disabled_row.gates.target_supported.status == "not-applicable"
  and disabled_row.gates.science_compatible.status == "not-applicable",
  "disabled declared stream does not fabricate a failed target or science proof")

settings.startup["ips-enable-research_character_mining_speed"] = nil

for index = 2, 65 do
  local name = "braking-force-" .. tostring(index)
  data.raw.technology[name] = {
    name = name, enabled = true, max_level = index, prerequisites = {},
    effects = {{type = "character-mining-speed", modifier = 0.01}},
    unit = {count = 100, time = 30, ingredients = {{"automation-science-pack", 1}}}
  }
end
local match_bound = plan.compile()
check(find(match_bound.base_candidates, "braking-force").reason == "classic_native_match_bound",
  "a declared native chain with more than 64 matching levels is not sorted or extended")
for index = 2, 65 do data.raw.technology["braking-force-" .. tostring(index)] = nil end

local overwide_prerequisites = {}
for index = 1, 65 do overwide_prerequisites[index] = "bounded-prerequisite-" .. tostring(index) end
data.raw.technology["classic-bounded-ancestor"] = {
  name = "classic-bounded-ancestor", enabled = true, prerequisites = overwide_prerequisites
}
data.raw.technology["braking-force-1"].prerequisites = {"classic-bounded-ancestor"}
local ancestor_shape = plan.compile()
check(find(ancestor_shape.base_candidates, "braking-force").reason == "classic_native_ancestor_shape_bound",
  "a native ancestor with too many prerequisites is rejected before its edges are pushed")
data.raw.technology["braking-force-1"].prerequisites = {}
data.raw.technology["classic-bounded-ancestor"] = nil

local overwide_effects = {}
for index = 1, 65 do overwide_effects[index] = {type = "character-mining-speed", modifier = 0.01} end
data.raw.technology["braking-force-1"].effects = overwide_effects
local effect_shape = plan.compile()
check(find(effect_shape.base_candidates, "braking-force").reason == "classic_native_tail_shape_bound",
  "an oversized native effect vector is rejected before effect copying or fingerprinting")
data.raw.technology["braking-force-1"].effects = {{type = "character-mining-speed", modifier = 0.01}}

local overwide_ingredients = {}
for index = 1, 17 do overwide_ingredients[index] = {"automation-science-pack", 1} end
data.raw.technology["braking-force-1"].unit.ingredients = overwide_ingredients
local ingredient_shape = plan.compile()
check(find(ingredient_shape.base_candidates, "braking-force").reason == "classic_native_tail_shape_bound",
  "an oversized native ingredient vector is rejected before laboratory preparation or copying")
data.raw.technology["braking-force-1"].unit.ingredients = {{"automation-science-pack", 1}}

data.raw.technology["braking-force-1"].unit.count = nil
data.raw.technology["braking-force-1"].unit.count_formula = "1000/(7-L)"
local unsafe_formula = plan.compile()
check(find(unsafe_formula.base_candidates, "braking-force").reason == "classic_native_unsupported_cost_formula",
  "a finite native formula is not inherited without a bounded continuation proof")
data.raw.technology["braking-force-1"].unit.count = 100
data.raw.technology["braking-force-1"].unit.count_formula = nil

data.raw.technology["braking-force-1"].unit.count_formula = ""
local empty_formula = plan.compile()
check(find(empty_formula.base_candidates, "braking-force").reason == "classic_native_unsupported_cost_formula",
  "an empty native formula is not copied into the fixed-cost classic continuation")
data.raw.technology["braking-force-1"].unit.count_formula = nil

data.raw.technology["braking-force-1"].unit.count = nil
data.raw.technology["braking-force-1"].unit.count_formula = string.rep("x", 4097)
local formula_shape = plan.compile()
check(find(formula_shape.base_candidates, "braking-force").reason == "classic_native_tail_shape_bound",
  "an oversized native count formula is rejected before serializing a continuation")
data.raw.technology["braking-force-1"].unit.count = 100
data.raw.technology["braking-force-1"].unit.count_formula = nil

data.raw.technology["braking-force-1"].localised_name = string.rep("x", 65537)
local localized_shape = plan.compile()
check(find(localized_shape.base_candidates, "braking-force").reason == "classic_native_tail_shape_bound",
  "an oversized localized native field is rejected before TechnologyDesign copying")
data.raw.technology["braking-force-1"].localised_name = nil

local scalar_wide_localized = {}
for index = 1, 129 do scalar_wide_localized["part-" .. tostring(index)] = index end
data.raw.technology["braking-force-1"].localised_name = scalar_wide_localized
local scalar_wide_shape = plan.compile()
check(find(scalar_wide_shape.base_candidates, "braking-force").reason == "classic_native_tail_shape_bound",
  "a shallow scalar-wide localized value exceeds the total visit bound before copying")
data.raw.technology["braking-force-1"].localised_name = nil

data.raw.technology["worker-robots-storage-1"].effects = {{type = "worker-robot-storage", modifier = 1}}
settings.startup["mir-effect-per-level-worker-robots-storage"] = {value = math.huge}
local invalid_native_bonus = plan.compile()
check(find(invalid_native_bonus.base_candidates, "worker-robots-storage").reason == "classic_native_effect_setting_invalid",
  "an invalid native bonus setting never produces an infinite continuation effect")
settings.startup["mir-effect-per-level-worker-robots-storage"] = nil
data.raw.technology["worker-robots-storage-1"].effects = {{type = "character-mining-speed", modifier = 0.01}}

for index = 1, 256 do
  data.raw.lab["classic-extra-lab-" .. tostring(index)] = {name = "classic-extra-lab-" .. tostring(index), inputs = SCIENCE}
end
local lab_catalog_bound = plan.compile()
local lab_catalog_row = find(lab_catalog_bound.stream_plan.rows, "research_character_mining_speed")
check(lab_catalog_row.reason == "classic_lab_not_evaluated:catalog_bound"
  and lab_catalog_row.gates.lab_compatible.status == "not-applicable",
  "too many labs produces an uncomputed disposition instead of a false laboratory rejection")
for index = 1, 256 do data.raw.lab["classic-extra-lab-" .. tostring(index)] = nil end

local overwide_lab_inputs = {}
for index = 1, 65 do overwide_lab_inputs[index] = "classic-lab-input-" .. tostring(index) end
data.raw.lab.lab.inputs = overwide_lab_inputs
local lab_input_bound = plan.compile()
local lab_input_row = find(lab_input_bound.stream_plan.rows, "research_character_mining_speed")
check(lab_input_row.reason == "classic_lab_not_evaluated:input_bound"
  and lab_input_row.gates.lab_compatible.status == "not-applicable",
  "a lab with too many inputs produces an uncomputed disposition instead of false incompatibility")
data.raw.lab.lab.inputs = SCIENCE

for index = 1, 16385 do
  local name = "classic-catalog-bound-" .. tostring(index)
  data.raw.technology[name] = {name = name, enabled = true, prerequisites = {}}
end
local catalog_bound = plan.compile()
check(find(catalog_bound.base_candidates, "braking-force").reason == "classic_native_catalog_bound"
  and find(catalog_bound.stream_plan.rows, "research_character_mining_speed").action == "emit",
  "an oversized native catalogue rejects every native continuation without suppressing fixed direct effects")
for index = 1, 16385 do data.raw.technology["classic-catalog-bound-" .. tostring(index)] = nil end

return {assertions = assertions}

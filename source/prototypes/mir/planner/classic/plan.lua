-- Fast, declared planning for the default classic compiler mode.
--
-- This module deliberately does not import stream discovery, science
-- acquisition, recipe matching, ownership inference, catalog construction,
-- or diagnostics.  It only emits declarations whose named prototype inputs
-- are directly present, and otherwise records an explicit unsupported row.

local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local gate = require("prototypes.mir.domain.technology.gate")
local hard_gates = require("prototypes.mir.domain.technology.hard_gate_authority")
local effect_safety = require("prototypes.mir.domain.technology.effect_safety_policy")
local effect_contracts = require("prototypes.mir.settings.effect_contracts")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local base_builder = require("prototypes.mir.planner.base_continuation_builder")
local declarations = require("prototypes.mir.domain.compiler.classic_declarations")

local M = {}

-- Classic support is deliberately finite.  These bounds apply before any
-- native prototype value is copied, canonicalized or placed in an operation.
local MAXIMUM_NATIVE_CATALOG_VISITS = 16384
local MAXIMUM_NATIVE_LEVEL_MATCHES = 64
local MAXIMUM_LABS = 256
local MAXIMUM_LAB_INPUTS = 64
local MAXIMUM_NATIVE_EFFECTS = 64
local MAXIMUM_NATIVE_PREREQUISITES = 64
local MAXIMUM_NATIVE_INGREDIENTS = 16
local MAXIMUM_NATIVE_ICONS = 64
local MAXIMUM_NATIVE_FORMULA_BYTES = 4096
local MAXIMUM_NATIVE_VALUE_NODES = 256
local MAXIMUM_NATIVE_VALUE_BYTES = 64 * 1024
local MAXIMUM_NATIVE_VALUE_DEPTH = 8
local MAXIMUM_NATIVE_EFFECT_SETTING = 1000000
local MAXIMUM_NATIVE_UINT32 = 4294967295

local function raw_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function selected_setting(name, context)
  local imported = raw_setting("mir-settings-profile-import")
  if type(imported) == "string" and imported ~= "" then
    return require("prototypes.mir.settings.effective").get(name, context)
  end
  return raw_setting(name)
end

local function enabled(setting_name, context)
  local value = selected_setting(setting_name, context)
  return value == nil or value == true
end

local function selected_max_level(setting_name, context)
  local value = selected_setting(setting_name, context)
  if type(value) ~= "number" or value <= 0 then return "infinite" end
  return math.floor(value)
end

local function positive_number_setting(name, fallback, minimum, context)
  local value = selected_setting(name, context)
  if type(value) == "number" and value == value and value >= minimum and value < math.huge then return value end
  return fallback
end

local function output_max_level(planned)
  if target_line.feature_enabled("scripted_techs") then return "infinite" end
  return planned
end

local function sorted_keys(values)
  local out = {}
  for key in pairs(values or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function bounded_array(value, maximum)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
    count = count + 1
    if count > maximum then return false end
  end
  return count == #value
end

local function bounded_value(value, limits, seen, depth)
  -- The bound is for every value that this validator visits, not merely for
  -- containers: one shallow table can otherwise hold an unbounded scalar
  -- vector that later reaches the continuation projection.
  limits.nodes = limits.nodes + 1
  if limits.nodes > MAXIMUM_NATIVE_VALUE_NODES then return false end
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then return true end
  if kind == "number" then return finite_number(value) end
  if kind == "string" then
    limits.bytes = limits.bytes + #value
    return limits.bytes <= MAXIMUM_NATIVE_VALUE_BYTES
  end
  if kind ~= "table" or depth >= MAXIMUM_NATIVE_VALUE_DEPTH or seen[value] then return false end
  seen[value] = true
  local entries = 0
  for key, child in pairs(value) do
    if type(key) ~= "string" and type(key) ~= "number" then return false end
    entries = entries + 1
    if entries > MAXIMUM_NATIVE_VALUE_NODES or not bounded_value(key, limits, seen, depth + 1)
        or not bounded_value(child, limits, seen, depth + 1) then
      return false
    end
  end
  seen[value] = nil
  return true
end

local function bounded_native_value(value)
  return bounded_value(value, {nodes = 0, bytes = 0}, {}, 0)
end

local function escaped_pattern(value)
  return value:gsub("([^%w])", "%%%1")
end

local function scan_declared_native_chains()
  local chains, patterns = {}, {}
  for _, key in ipairs(declarations.base_chains) do
    chains[key] = {levels = {}, by_level = {}, terminals = {}, starts = {}, match_count = 0}
    patterns[key] = "^" .. escaped_pattern(key) .. "%-(%d+)$"
  end
  local visits = 0
  for name, technology in pairs(data_raw.prototypes("technology")) do
    visits = visits + 1
    if visits > MAXIMUM_NATIVE_CATALOG_VISITS then
      return nil, "classic_native_catalog_bound"
    end
    if type(name) ~= "string" or #name > 1024 or type(technology) ~= "table" then
      return nil, "classic_native_catalog_shape_bound"
    end
    for _, key in ipairs(declarations.base_chains) do
      local level = tonumber(string.match(name, patterns[key]))
      if level then
        local chain = chains[key]
        if not finite_number(level) or level < 1 or level ~= math.floor(level) then
          chain.match_bound = true
        else
          chain.match_count = chain.match_count + 1
          if chain.match_count > MAXIMUM_NATIVE_LEVEL_MATCHES then
            chain.match_bound = true
          elseif technology.max_level == "infinite" then
            chain.has_infinite = true
          else
            chain.levels[#chain.levels + 1] = level
            chain.by_level[level] = technology
            local terminal = level
            if finite_number(technology.max_level) and technology.max_level >= level then
              terminal = math.floor(technology.max_level)
            end
            if not chain.starts[terminal] or level > chain.starts[terminal] then
              chain.terminals[terminal] = technology
              chain.starts[terminal] = level
            end
          end
        end
      end
    end
  end
  for _, chain in pairs(chains) do table.sort(chain.levels) end
  return chains
end

local function names_from_ingredients(ingredients)
  local out = {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = type(ingredient) == "table" and (ingredient.name or ingredient[1]) or ingredient
    if type(name) ~= "string" or name == "" then return nil end
    out[#out + 1] = name
  end
  return out
end

local function declared_ingredients(names)
  local out = {}
  for _, name in ipairs(names or {}) do out[#out + 1] = {name, 1} end
  return out
end

local function science_tool_exists(name)
  return data_raw.prototype("tool", name) ~= nil
end

local function valid_ingredients(ingredients)
  if not bounded_array(ingredients, MAXIMUM_NATIVE_INGREDIENTS) then return false, "shape_bound" end
  for _, ingredient in ipairs(ingredients or {}) do
    local name = type(ingredient) == "table" and (ingredient.name or ingredient[1]) or ingredient
    local amount = type(ingredient) == "table" and (ingredient.amount or ingredient[2]) or 1
    if type(name) ~= "string" or name == "" then return false, "missing_tool" end
    if type(amount) ~= "number" or amount <= 0 or amount == math.huge or amount ~= amount then
      return false, "invalid_amount"
    end
    if not science_tool_exists(name) then return false, "missing_tool" end
  end
  return true
end

local function prepare_labs()
  local labs, visits = {}, 0
  for name, lab in pairs(data_raw.prototypes("lab")) do
    visits = visits + 1
    if visits > MAXIMUM_LABS then return {complete = false, reason = "catalog_bound"} end
    if type(name) ~= "string" or #name > 1024 or type(lab) ~= "table" then
      return {complete = false, reason = "catalog_shape"}
    end
    if lab.enabled ~= false then
      if not bounded_array(lab.inputs or {}, MAXIMUM_LAB_INPUTS) then
        return {complete = false, reason = "input_bound"}
      end
      local inputs = {}
      for _, input in ipairs(lab.inputs or {}) do
        if type(input) ~= "string" or input == "" or #input > 1024 then
          return {complete = false, reason = "input_shape"}
        end
        inputs[input] = true
      end
      labs[#labs + 1] = {name = tostring(name), inputs = inputs}
    end
  end
  table.sort(labs, function(left, right) return left.name < right.name end)
  return {complete = true, labs = labs}
end

local function any_lab_accepts(ingredients, prepared_labs)
  if not prepared_labs.complete then return nil, prepared_labs.reason end
  local required = {}
  for _, name in ipairs(names_from_ingredients(ingredients) or {}) do required[name] = true end
  if next(required) == nil then return false end
  for _, lab in ipairs(prepared_labs.labs) do
    local accepts = true
    for name in pairs(required) do
      if not lab.inputs[name] then accepts = false; break end
    end
    if accepts then return true end
  end
  return false
end

local function chain_ancestors_are_enabled(root_name, capacity, reason_prefix)
  local colors, visited, stack = {}, 0, {{name = root_name, leaving = false}}
  while #stack > 0 do
    local frame = table.remove(stack)
    local name = frame.name
    if frame.leaving then
      colors[name] = "done"
    elseif colors[name] == "active" then
      return false, reason_prefix .. "_ancestor_cycle"
    elseif colors[name] ~= "done" then
      visited = visited + 1
      if visited > capacity then return false, reason_prefix .. "_ancestor_bound" end
      local technology = data_raw.technology(name)
      if type(technology) ~= "table" then return false, reason_prefix .. "_ancestor_missing" end
      if technology.enabled == false then return false, reason_prefix .. "_ancestor_disabled" end
      if not bounded_array(technology.prerequisites or {}, MAXIMUM_NATIVE_PREREQUISITES) then
        return false, reason_prefix .. "_ancestor_shape_bound"
      end
      colors[name] = "active"
      stack[#stack + 1] = {name = name, leaving = true}
      for _, prerequisite in ipairs(technology.prerequisites or {}) do
        if type(prerequisite) ~= "string" or prerequisite == "" or #prerequisite > 1024 then
          return false, reason_prefix .. "_ancestor_shape_bound"
        end
        stack[#stack + 1] = {name = prerequisite, leaving = false}
      end
    end
  end
  return true
end

local function technology_exists_and_enabled(name)
  local technology = data_raw.technology(name)
  return technology and technology.enabled ~= false
end

local function make_gates(kind, key, failure)
  local input = fingerprint.of({schema = declarations.schema, kind = kind, key = key, failure = failure})
  local passed = {
    target_supported = "classic-declaration:target-profile",
    effect_valid = "classic-declaration:declared-effect",
    science_compatible = "classic-declaration:declared-science-inputs",
    lab_compatible = "classic-declaration:declared-lab-inputs",
    prerequisites_acyclic = "classic-declaration:bounded-native-ancestor-check",
    migration_safe = "classic-declaration:stable-manifest-id",
    output_identity_safe = "classic-declaration:output-absent"
  }
  local not_applicable = {
    owner_conflict_free = "classic-declaration-does-not-infer-external-owners",
    loop_safe = "classic-declaration-does-not-transform-recipes",
    progression_safe = "classic-declaration-does-not-infer-progression"
  }
  local out = {}
  for _, gate_name in ipairs(hard_gates.order()) do
    local failed = failure and failure.gate == gate_name
    if failed then
      out[gate_name] = gate.failed("classic-declaration", failure.reason, {failure.reason})
    elseif kind == "skip" then
      out[gate_name] = gate.not_applicable(
        "classic-declaration", "classic-candidate-not-materialized", input,
        {"classic-candidate-not-materialized"})
    elseif passed[gate_name] then
      out[gate_name] = gate.passed("classic-declaration", {passed[gate_name]})
    else
      out[gate_name] = gate.not_applicable(
        "classic-declaration", not_applicable[gate_name], input, {not_applicable[gate_name]})
    end
  end
  return out
end

local function skip_row(key, manifest_id, reason, failure_gate)
  return {
    schema = 3,
    stream_key = key,
    manifest_id = manifest_id or key,
    action = "skip",
    reason = reason,
    source = "classic-declaration",
    diagnostics = {mode = "classic", science_evaluation = "uncomputed", reason = reason},
    gates = make_gates("skip", key, failure_gate and {gate = failure_gate, reason = reason} or nil)
  }
end

local function fixed_cost(key, declaration, context)
  local cost = declaration.cost or {}
  return research_cost_model.new({
    anchor_level = 1,
    base_cost = positive_number_setting("ips-cost-base-" .. key, cost.base_cost or 8000, 1, context),
    linear_increment = positive_number_setting("ips-cost-linear-increment-" .. key,
      cost.linear_increment or 0, 0, context),
    growth_factor = positive_number_setting("ips-cost-growth-" .. key,
      cost.growth_factor or 2, 1, context),
    provenance = {
      base_cost = "classic-declaration:" .. key,
      linear_increment = "classic-declaration:" .. key,
      growth_factor = "classic-declaration:" .. key,
      anchor_level = "classic-first-level"
    }
  })
end

local function declared_direct_row(key, declaration, context, prepared_labs)
  if not enabled("ips-enable-" .. key, context) then
    return skip_row(key, declaration.manifest_id, "classic_disabled")
  end
  if data_raw.technology(declaration.technology_name) then
    return skip_row(key, declaration.manifest_id, "classic_output_exists", "output_identity_safe")
  end
  for _, prerequisite in ipairs(declaration.prerequisites or {}) do
    if not technology_exists_and_enabled(prerequisite) then
      return skip_row(key, declaration.manifest_id,
        "classic_missing_declared_gate:" .. prerequisite, "prerequisites_acyclic")
    end
    local ancestors_ok, ancestor_reason = chain_ancestors_are_enabled(
      prerequisite, 64, "classic_declared_gate")
    if not ancestors_ok then
      return skip_row(key, declaration.manifest_id, ancestor_reason, "prerequisites_acyclic")
    end
  end
  for _, effect in ipairs(declaration.effects or {}) do
    effect_safety.assert_effect_allowed(effect, "classic declaration " .. key)
    if not target_line.effect_supported(effect) then
      return skip_row(key, declaration.manifest_id,
        "classic_unsupported_effect:" .. tostring(effect.type), "effect_valid")
    end
  end
  local ingredients = declared_ingredients(declaration.science)
  local ingredients_valid, ingredient_reason = valid_ingredients(ingredients)
  if not ingredients_valid then
    return skip_row(key, declaration.manifest_id,
      "classic_declared_science_" .. ingredient_reason, "science_compatible")
  end
  local lab_compatible, lab_reason = any_lab_accepts(ingredients, prepared_labs)
  if lab_compatible == nil then
    return skip_row(key, declaration.manifest_id,
      "classic_lab_not_evaluated:" .. tostring(lab_reason))
  end
  if not lab_compatible then
    return skip_row(key, declaration.manifest_id, "classic_declared_science_not_accepted", "lab_compatible")
  end

  local planned_max_level = selected_max_level("ips-max-level-" .. key, context)
  local cost_model = fixed_cost(key, declaration, context)
  local fields = {
    localised_name = {"technology-name.more-infinite-research." .. key},
    localised_description = {"technology-description.more-infinite-research.direct_effect"},
    icon = declaration.icon,
    icon_size = declaration.icon_size or 256,
    effects = deepcopy(declaration.effects),
    prerequisites = deepcopy(declaration.prerequisites),
    count_formula = cost_model.count_formula,
    cost_model = cost_model,
    ingredients = ingredients,
    research_time = positive_number_setting("ips-research-time-" .. key,
      (declaration.cost or {}).research_time or 60, 1, context),
    max_level = output_max_level(planned_max_level),
    level = 1,
    enabled = true,
    hidden = planned_max_level ~= "infinite" and planned_max_level < 1,
    upgrade = true
  }
  local row = {
    schema = 3,
    stream_key = key,
    manifest_id = declaration.manifest_id,
    action = "emit",
    reason = "classic_declared_direct_effect",
    source = "classic-declaration",
    technology_name = declaration.technology_name,
    planned_max_level = planned_max_level,
    direct_effects = true,
    fields = fields,
    spec = {identity_state = "released", classic_declared = true},
    diagnostics = {mode = "classic", science_evaluation = "declared", lab_status = "declared-full"},
    gates = make_gates("direct", key)
  }
  row.technology_design = technology_design.from_generation_row(row)
  return row
end

local function rejection_gate(reason)
  if string.find(reason, "lab", 1, true) then return "lab_compatible" end
  if string.find(reason, "effect", 1, true) then return "effect_valid" end
  if string.find(reason, "output", 1, true) or string.find(reason, "infinite", 1, true) then
    return "output_identity_safe"
  end
  if string.find(reason, "ancestor", 1, true) or string.find(reason, "tail", 1, true) then
    return "prerequisites_acyclic"
  end
  return nil
end

local function base_candidate(key, action, reason, operation)
  local failure_gate = rejection_gate(reason or "")
  local gates = operation and operation.gates or make_gates("skip", key,
    failure_gate and {gate = failure_gate, reason = reason} or nil)
  return {
    schema = 1,
    candidate_id = "base-continuation/" .. key,
    key = key,
    action = action,
    reason = reason,
    technology_name = operation and operation.technology_name or nil,
    design_fingerprint = operation and operation.technology_design.design_fingerprint or nil,
    gates = gates,
    candidate_fingerprint = fingerprint.of({key = key, action = action, reason = reason,
      technology_name = operation and operation.technology_name or nil})
  }
end

local function append_prerequisite(previous_name, inherited)
  local out, seen = {}, {}
  for _, name in ipairs(inherited or {}) do
    if name ~= previous_name and not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  if previous_name and not seen[previous_name] then out[#out + 1] = previous_name end
  return out
end

local function bounded_native_tail_shape(tail)
  if not bounded_array(tail.effects or {}, MAXIMUM_NATIVE_EFFECTS)
      or not bounded_array(tail.prerequisites or {}, MAXIMUM_NATIVE_PREREQUISITES)
      or (tail.icons ~= nil and not bounded_array(tail.icons, MAXIMUM_NATIVE_ICONS)) then
    return false
  end
  local unit = tail.unit
  if type(unit) ~= "table" or type(unit.ingredients) ~= "table"
      or not bounded_array(unit.ingredients, MAXIMUM_NATIVE_INGREDIENTS)
      or (type(unit.count_formula) == "string" and #unit.count_formula > MAXIMUM_NATIVE_FORMULA_BYTES) then
    return false
  end
  local limits, seen = {nodes = 0, bytes = 0}, {}
  for _, field in ipairs({"effects", "prerequisites", "icon", "icons", "icon_size",
      "localised_name", "localised_description", "order"}) do
    if not bounded_value(tail[field], limits, seen, 0) then return false end
  end
  if not bounded_value(unit.ingredients, limits, seen, 0)
      or not bounded_value(unit.count_formula, limits, seen, 0) then return false end
  for _, name in ipairs(tail.prerequisites or {}) do
    if type(name) ~= "string" or name == "" or #name > 1024 then return false end
  end
  if tail.icon ~= nil and (type(tail.icon) ~= "string" or tail.icon == "" or #tail.icon > 4096) then
    return false
  end
  if tail.icon_size ~= nil and (not finite_number(tail.icon_size) or tail.icon_size <= 0
      or tail.icon_size ~= math.floor(tail.icon_size)) then
    return false
  end
  return true
end

local function bounded_unit_projection(unit)
  local projected = {
    ingredients = deepcopy(unit.ingredients),
    time = unit.time
  }
  if unit.count ~= nil then projected.count = unit.count end
  if unit.count_formula ~= nil then projected.count_formula = unit.count_formula end
  return projected
end

local function bounded_presentation_projection(tail)
  return {
    icon = tail.icon,
    icon_size = tail.icon_size,
    icons = tail.icons,
    order = tail.order
  }
end

local function native_uint32(value)
  return finite_number(value) and value >= 0 and value <= MAXIMUM_NATIVE_UINT32
    and value == math.floor(value)
end

local function valid_native_effect_descriptor(descriptor)
  return type(descriptor) == "table" and descriptor.field == "modifier"
    and (descriptor.unit == "native" or descriptor.unit == "percent")
    and finite_number(descriptor.value)
end

local function native_effects_supported(key, effects)
  local allowed_types = declarations.base_chain_effect_types[key]
  if type(allowed_types) ~= "table" or type(effects) ~= "table" or #effects == 0 then
    return false, "classic_native_tail_unsupported_effect"
  end
  for _, effect in ipairs(effects or {}) do
    if type(effect) ~= "table" or allowed_types[effect.type] ~= true then
      return false, "classic_native_tail_unsupported_effect"
    end
    if effect.type == "gun-speed" then
      local category = effect.ammo_category
      if type(category) ~= "string" or category == "" or #category > 1024
          or data_raw.prototype("ammo-category", category) == nil then
        return false, "classic_native_tail_missing_ammo_category"
      end
    end
    effect_safety.assert_effect_allowed(effect, "classic native continuation")
    local descriptor = effect_contracts.numeric_effect_descriptor(effect)
    if not valid_native_effect_descriptor(descriptor) then
      return false, "classic_native_tail_invalid_effect_modifier"
    end
    if descriptor.unit == "native" and not native_uint32(descriptor.value) then
      return false, "classic_native_tail_invalid_native_modifier"
    end
    if not target_line.effect_supported(effect) then
      return false, "classic_native_tail_unsupported_effect"
    end
  end
  return true
end

local function scaled_native_effects(key, effects, context)
  local descriptor = effect_contracts.base_default_descriptor(key)
  if not descriptor then return deepcopy(effects or {}) end
  local selected = selected_setting(effect_contracts.base_setting_name(key), context)
  if selected == nil then return deepcopy(effects or {}) end
  if not finite_number(selected) or selected <= 0 or selected > MAXIMUM_NATIVE_EFFECT_SETTING
      or (descriptor.unit == "native" and selected ~= math.floor(selected)) then
    return nil, "classic_native_effect_setting_invalid"
  end
  local multiplier = descriptor.display_multiplier or (descriptor.unit == "percent" and 100 or 1)
  local factor = (selected / multiplier) / descriptor.canonical_anchor
  if not finite_number(factor) or factor <= 0 then return nil, "classic_native_effect_setting_invalid" end
  if factor == 1 then return deepcopy(effects or {}) end
  local out = deepcopy(effects or {})
  for _, effect in ipairs(out) do
    local numeric = effect_contracts.numeric_effect_descriptor(effect)
    if not valid_native_effect_descriptor(numeric) then return nil, "classic_native_tail_invalid_effect_modifier" end
    if numeric.unit == "native" and not native_uint32(numeric.value) then
      return nil, "classic_native_tail_invalid_native_modifier"
    end
    if numeric.field == descriptor.field and numeric.unit == descriptor.unit then
      local scaled = numeric.value * factor
      if not finite_number(scaled) then return nil, "classic_native_effect_setting_invalid" end
      if numeric.unit == "native" and not native_uint32(scaled) then
        return nil, "classic_native_effect_setting_invalid"
      end
      effect[numeric.field] = scaled
    end
  end
  return out
end

local function native_continuation(key, context, chain, prepared_labs, catalog_reason)
  if not enabled("mir-enable-" .. key, context) then return nil, base_candidate(key, "reject", "classic_disabled") end
  if not chain then return nil, base_candidate(key, "reject", catalog_reason or "classic_native_catalog_bound") end
  if chain.match_bound then return nil, base_candidate(key, "reject", "classic_native_match_bound") end
  if chain.has_infinite then return nil, base_candidate(key, "reject", "classic_native_already_infinite") end
  if #chain.levels == 0 then return nil, base_candidate(key, "reject", "classic_native_chain_missing") end
  local terminal_level = chain.levels[#chain.levels]
  for level in pairs(chain.terminals or {}) do
    if level > terminal_level then terminal_level = level end
  end
  if not native_uint32(terminal_level) or terminal_level >= MAXIMUM_NATIVE_UINT32 then
    return nil, base_candidate(key, "reject", "classic_native_continuation_level_bound")
  end
  local tail = (chain.terminals or {})[terminal_level] or chain.by_level[terminal_level]
  if not tail or type(tail.name) ~= "string" or #tail.name > 1024 or type(tail.unit) ~= "table" then
    return nil, base_candidate(key, "reject", "classic_native_tail_incomplete")
  end
  if not bounded_native_tail_shape(tail) then
    return nil, base_candidate(key, "reject", "classic_native_tail_shape_bound")
  end
  -- A native formula can be valid at its current finite level while becoming
  -- undefined at the continuation level. Classic retains only fixed numeric
  -- costs because it does not load the generic formula evaluator.
  if tail.unit.count_formula ~= nil then
    return nil, base_candidate(key, "reject", "classic_native_unsupported_cost_formula")
  end
  local ancestors_ok, ancestor_reason = chain_ancestors_are_enabled(tail.name, 64, "classic_native")
  if not ancestors_ok then return nil, base_candidate(key, "reject", ancestor_reason) end
  if (type(tail.unit.count) ~= "number" or tail.unit.count ~= tail.unit.count
      or tail.unit.count <= 0 or tail.unit.count == math.huge)
      then
    return nil, base_candidate(key, "reject", "classic_native_tail_missing_cost")
  end
  local ingredients_valid, ingredient_reason = valid_ingredients(tail.unit.ingredients)
  if type(tail.unit.time) ~= "number" or tail.unit.time ~= tail.unit.time
      or tail.unit.time <= 0 or tail.unit.time == math.huge
      or type(tail.unit.ingredients) ~= "table" or not ingredients_valid then
    return nil, base_candidate(key, "reject", "classic_native_tail_science_" .. tostring(ingredient_reason))
  end
  local lab_compatible, lab_reason = any_lab_accepts(tail.unit.ingredients, prepared_labs)
  if lab_compatible == nil then
    return nil, base_candidate(key, "reject", "classic_lab_not_evaluated:" .. tostring(lab_reason))
  end
  if not lab_compatible then
    return nil, base_candidate(key, "reject", "classic_native_tail_lab_incompatible")
  end
  local effects_supported, effects_reason = native_effects_supported(key, tail.effects)
  if not effects_supported then
    return nil, base_candidate(key, "reject", effects_reason)
  end
  local new_name = key .. "-" .. tostring(terminal_level + 1)
  if data_raw.technology(new_name) then
    return nil, base_candidate(key, "reject", "classic_output_exists")
  end
  local planned_max_level = selected_max_level("mir-max-level-" .. key, context)
  if planned_max_level ~= "infinite" and planned_max_level < terminal_level + 1
      and not target_line.feature_enabled("scripted_techs") then
    return nil, base_candidate(key, "reject", "classic_max_level_below_first_extension")
  end
  local unit = bounded_unit_projection(tail.unit)
  unit.time = positive_number_setting("mir-research-time-" .. key, tail.unit.time, 1, context)
  local effects, effect_reason = scaled_native_effects(key, tail.effects, context)
  if not effects then return nil, base_candidate(key, "reject", effect_reason) end
  local technology = base_builder.continuation(bounded_presentation_projection(tail), {
    name = new_name,
    localised_name = tail.localised_name or {"technology-name." .. key},
    localised_description = tail.localised_description or {"technology-description." .. key},
    prerequisites = append_prerequisite(tail.name, tail.prerequisites),
    effects = effects,
    unit = unit,
    max_level = output_max_level(planned_max_level),
    upgrade = true,
    level = terminal_level + 1,
    hidden = planned_max_level ~= "infinite" and planned_max_level < terminal_level + 1
  })
  local operation = {
    schema = 1,
    operation = "emit_base_extension",
    key = key,
    manifest_id = "base-continuation/" .. key,
    base_technology_name = tail.name,
    technology_name = new_name,
    technology = technology,
    planned_max_level = planned_max_level,
    diagnostics = {mode = "classic", science_evaluation = "inherited-native-tail"},
    gates = make_gates("native-continuation", key)
  }
  operation.technology_design = technology_design.from_base_extension_operation(operation)
  operation.technology = technology_design.prototype_projection(operation.technology_design, {validated = true})
  operation.technology.type = "technology"
  return operation, base_candidate(key, "create", "classic_native_continuation", operation)
end

function M.compile(context)
  local source_fingerprints = {
    classic_declarations = fingerprint.of(declarations),
    classic_target = fingerprint.of({factorio_version = target_line.factorio_version, schema = declarations.schema})
  }
  local stream_builder = generation_plan.new({source_fingerprints = source_fingerprints})
  local prepared_labs = prepare_labs()
  for _, key in ipairs(sorted_keys(declarations.direct_streams)) do
    stream_builder:add_owned_derived(
      declared_direct_row(key, declarations.direct_streams[key], context, prepared_labs))
  end
  local chains, chain_reason = scan_declared_native_chains()
  local base_extension_operations, base_candidates = {}, {}
  for _, key in ipairs(declarations.base_chains) do
    local operation, candidate = native_continuation(
      key, context, chains and chains[key], prepared_labs, chain_reason)
    if operation then base_extension_operations[#base_extension_operations + 1] = operation end
    base_candidates[#base_candidates + 1] = candidate
  end
  table.sort(base_candidates, function(left, right) return left.candidate_id < right.candidate_id end)
  local stream_plan = stream_builder:finalize():artifact_view()
  return {
    stream_plan = stream_plan,
    base_extension_operations = base_extension_operations,
    base_candidates = base_candidates,
    source_fingerprints = source_fingerprints
  }
end

return M

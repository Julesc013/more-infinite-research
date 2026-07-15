local defaults = require("prototypes.mir.settings.defaults")

local base_defaults = defaults.base_extensions or {}

local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local D = require("prototypes.mir.report.diagnostics_sink")
local settings_resolver = require("prototypes.mir.settings.resolver")
local deepcopy = require("prototypes.mir.core.deepcopy")
local table_utils = require("prototypes.mir.core.table")
local effect_safety = require("prototypes.mir.emit.effect_safety")
local planner_prerequisites = require("prototypes.mir.planner.prerequisites")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

local function format_number(value)
  if type(value) ~= "number" then return tostring(value) end
  if math.abs(value - math.floor(value)) < 1e-6 then
    return tostring(math.floor(value + 0.5))
  end
  return string.format("%.6g", value)
end

local function startup_setting(name)
  return effective_settings.get(name)
end

local function prefer_this_mod_for_competing_techs()
  local value = startup_setting("mir-prefer-this-mod-for-competing-techs")
  if value == nil then return true end
  return value ~= false
end

local function is_enabled(key, spec)
  return settings_resolver.base_enabled(key, spec)
end

local function sanitize_number(value)
  if type(value) ~= "number" then return nil end
  return value
end

local function coerce_max_level_value(value)
  if value == nil then return "infinite" end
  if value == "infinite" then return "infinite" end
  if type(value) == "number" then
    if value <= 0 then return "infinite" end
    return math.floor(value + 0.5)
  end
  if type(value) == "string" then
    local num = tonumber(value)
    if not num or num <= 0 then return "infinite" end
    return math.floor(num + 0.5)
  end
  return "infinite"
end
local function build_prerequisites(previous_name, last_prereqs)
  local out, seen = {}, {}
  if last_prereqs then
    for _, name in ipairs(last_prereqs) do
      if name ~= previous_name and not seen[name] then
        seen[name] = true
        table.insert(out, name)
      end
    end
  end
  if previous_name and not seen[previous_name] then
    table.insert(out, previous_name)
  end
  return out
end

local function effect_value_to_string(value)
  local kind = type(value)
  if kind == "string" then return value end
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "table" then
    local parts = {}
    for k, v in pairs(value) do
      table.insert(parts, tostring(k) .. "=" .. effect_value_to_string(v))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(value)
end

local function effects_signature(effects)
  local rows = {}
  for _, effect in ipairs(effects or {}) do
    local cols = {}
    for k, v in pairs(effect) do
      table.insert(cols, tostring(k) .. "=" .. effect_value_to_string(v))
    end
    table.sort(cols)
    table.insert(rows, table.concat(cols, ";"))
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

local function has_prereq(tech, prereq_name)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prereq_name then return true end
  end
  return false
end

local function find_equivalent_infinite_extension(previous_name, expected_effects)
  local expected_signature = effects_signature(expected_effects)
  for tech_name, tech in pairs(data_raw.prototypes("technology")) do
    if tech.max_level == "infinite" and tech_name ~= previous_name then
      if has_prereq(tech, previous_name) and effects_signature(tech.effects) == expected_signature then
        return tech_name
      end
    end
  end
  return nil
end

local function find_any_infinite_extension(previous_name, new_name)
  for tech_name, tech in pairs(data_raw.prototypes("technology")) do
    if tech.max_level == "infinite" and tech_name ~= new_name then
      if has_prereq(tech, previous_name) then
        return tech_name
      end
    end
  end
  return nil
end

local function compute_growth_from_prev(last_unit, prev_unit)
  if not last_unit or not prev_unit then return nil end
  if not last_unit.count or not prev_unit.count then return nil end
  if prev_unit.count <= 0 then return nil end
  local ratio = last_unit.count / prev_unit.count
  if ratio < 1 then return nil end
  return ratio
end

local function resolve_science_packs(spec, fallback_unit, key)
  local base_ingredients = deepcopy((fallback_unit or {}).ingredients or {})
  local seen_packs = {}
  for _, pair in ipairs(base_ingredients) do
    local pack_name = pair.name or pair[1]
    if pack_name then seen_packs[pack_name] = true end
  end

  local function append_pack_list(list)
    for _, pack in ipairs(list or {}) do
      if science_packs.science_pack_exists(pack) and not seen_packs[pack] then
        seen_packs[pack] = true
        table.insert(base_ingredients, {pack, 1})
      end
    end
  end

  local desired = spec and spec.science_packs or nil
  local add_list = spec and spec.add_science_packs or nil
  if add_list == nil and not (spec and spec.override_science_packs == true) then
    -- For continuation techs, default behavior is inherit + relevant extras.
    if desired ~= nil and desired ~= "inherit" then
      add_list = desired
    else
      add_list = science_packs.pack_list_for_extension(key)
    end
  end
  if type(add_list) == "string" then
    add_list = science_packs.pack_list_for_extension(key, add_list)
      or science_packs.pack_list_for_extension(add_list)
  end
  if type(add_list) == "table" then
    append_pack_list(add_list)
  end

  if desired == nil or desired == "inherit" then
    -- Keep extension levels aligned with the last vanilla level by default.
    return base_ingredients
  end
  if not (spec and spec.override_science_packs == true) then
    -- Explicit pack lists in defaults are treated as documentation unless
    -- override_science_packs is enabled for this extension.
    return base_ingredients
  end
  local list = nil
  if desired == "all" then
    list = science_packs.pack_list_all()
  elseif desired then
    if type(desired) == "table" then
      list = {}
      for _, name in ipairs(desired) do table.insert(list, name) end
    else
      list = science_packs.pack_list_for_extension(desired)
    end
  end
  if list and #list > 0 then
    local out = {}
    local out_seen = {}
    for _, pack in ipairs(list) do
      if science_packs.science_pack_exists(pack) then
        out_seen[pack] = true
        table.insert(out, {pack, 1})
      end
    end
    for _, pair in ipairs(base_ingredients) do
      local pack_name = pair.name or pair[1]
      if pack_name and not out_seen[pack_name] then
        out_seen[pack_name] = true
        table.insert(out, {pack_name, 1})
      end
    end
    if #out > 0 then return out end
  end
  return base_ingredients
end

local function append_pack_prerequisites(prereqs, ingredients)
  local seen = {}
  for _, name in ipairs(prereqs or {}) do seen[name] = true end
  for _, pair in ipairs(ingredients or {}) do
    local pack_name = pair.name or pair[1]
    local prereq = science_packs.prereq_tech_for_science_pack(pack_name)
    if prereq and not seen[prereq] then
      seen[prereq] = true
      table.insert(prereqs, prereq)
    end
  end
  return prereqs
end

local function build_inserter_effects(last, spec)
  spec = spec or {}
  local bulk_increment = spec.bulk_increment or spec.stack_increment or 4
  local non_bulk_increment = spec.non_bulk_increment or spec.non_stack_increment or 2
  local out = {}
  for _, effect in ipairs(last.effects or {}) do
    local copy = deepcopy(effect)
    if copy.type == "bulk-inserter-capacity-bonus" or copy.type == "stack-inserter-capacity-bonus" then
      copy.modifier = bulk_increment
    elseif copy.type == "inserter-stack-size-bonus" then
      copy.modifier = non_bulk_increment
    end
    table.insert(out, copy)
  end
  return out
end

local SPECIALS = {
  ["inserter-capacity-bonus"] = {
    effect_builder = build_inserter_effects
  }
}

local function extend_chain(key)
  local spec = base_defaults[key] or {}
  local chain_key = spec.chain_key or key
  local generated_key = spec.generated_key or chain_key
  local locale_key = spec.locale_key or chain_key
  if not is_enabled(key, spec) then
    D.extension(D.extension_fields(key, "skipped", "disabled"))
    return
  end

  local pattern = "^" .. escape_pattern(chain_key) .. "%-(%d+)$"
  local levels, by_level = {}, {}
  local has_infinite = false

  for name, tech in pairs(data_raw.prototypes("technology")) do
    local level = tonumber(string.match(name, pattern))
    if level then
      if tech.max_level == "infinite" then
        has_infinite = true
      end
      table.insert(levels, level)
      by_level[level] = tech
    end
  end

  if has_infinite or #levels == 0 then
    D.extension(D.extension_fields(key, "skipped", has_infinite and "already_infinite" or "no_vanilla_chain"))
    return
  end
  table.sort(levels)

  local detected_highest = levels[#levels]
  local min_level = spec.min_level or (detected_highest + 1)
  if detected_highest < min_level - 1 then
    -- Vanilla chain does not reach the expected prerequisite tier.
    D.extension(D.extension_fields(key, "skipped", "vanilla_chain_below_minimum"))
    return
  end

  local extend_from_level = math.max(detected_highest, min_level - 1)
  if extend_from_level < min_level - 1 then extend_from_level = min_level - 1 end
  local base_level = extend_from_level
  local desired_new_level = extend_from_level + 1

  if desired_new_level < min_level then
    -- Need to catch up to the minimum level; treat the next vanilla level as base.
    base_level = min_level - 1
    desired_new_level = min_level
  end

  local base_tech = by_level[base_level]
  if not base_tech or not base_tech.unit then
    D.extension(D.extension_fields(key, "skipped", "missing_base_unit"))
    return
  end
  if base_tech.max_level == "infinite" then
    D.extension(D.extension_fields(key, "skipped", "base_already_infinite"))
    return
  end
  -- Allow anchoring when the base tech exists; vanilla-derived cost inference
  -- still requires numeric unit.count values.

  local new_name = generated_key .. "-" .. desired_new_level
  -- Never replace an existing vanilla or modded continuation level.
  if data_raw.technology(new_name) then
    D.extension(D.extension_fields(key, "skipped", "target_exists"))
    return
  end

  local max_level_value = coerce_max_level_value(startup_setting("mir-max-level-" .. key))
  if max_level_value == "infinite" then
    max_level_value = coerce_max_level_value(spec.max_level)
  end
  if max_level_value ~= "infinite" and max_level_value < desired_new_level then
    D.extension(D.extension_fields(key, "skipped", "max_level_below_first_extension"))
    return
  end

  local last_count = base_tech.unit.count
  local prev_unit = nil
  if base_level > 1 then
    local prev_level = base_level - 1
    while prev_level >= 1 do
      local prev = by_level[prev_level]
      if prev and prev.unit then
        prev_unit = prev.unit
        break
      end
      prev_level = prev_level - 1
    end
  end

  local function compute_growth_fallback()
    if prev_unit and prev_unit.count and prev_unit.count > 0 and last_count and last_count > 0 then
      return last_count / prev_unit.count
    end
    if prev_unit == nil then
      -- Attempt to infer using earlier tiers if available.
      local ratios = {}
      local prev = nil
      for _, lvl in ipairs(levels) do
        if lvl < base_level then
          local tech = by_level[lvl]
          if tech and tech.unit and tech.unit.count then
            if prev and prev.count and prev.count > 0 then
              table.insert(ratios, tech.unit.count / prev.count)
            end
            prev = tech.unit
          end
        end
      end
      if #ratios > 0 then
        local first = ratios[1]
        local consistent = true
        for i = 2, #ratios do
          if math.abs(ratios[i] - first) > 1e-6 then
            consistent = false
            break
          end
        end
        if consistent then return first end
      end
    end
    return nil
  end

  local growth_setting = sanitize_number(startup_setting("mir-cost-growth-" .. key))
  local force_vanilla_growth = growth_setting == 0
  local growth = nil
  if growth_setting and growth_setting > 0 then
    growth = growth_setting
  end
  if not growth and not force_vanilla_growth then
    local default_growth = sanitize_number(spec.growth_factor)
    if default_growth and default_growth > 0 then
      growth = default_growth
    end
  end
  if not growth then
    growth = compute_growth_from_prev(base_tech.unit, prev_unit)
  end
  if not growth then
    growth = compute_growth_fallback()
  end
  if not growth or growth <= 0 then
    growth = 1
  end

  local base_setting = sanitize_number(startup_setting("mir-cost-base-" .. key))
  local force_vanilla_base = base_setting == 0
  local base_value = nil
  if base_setting and base_setting > 0 then
    base_value = base_setting
  end

  if not base_value and not force_vanilla_base then
    local spec_base = sanitize_number(spec.base_cost)
    if spec_base and spec_base > 0 then
      base_value = spec_base
    end
  end
  if not base_value then
    if last_count and growth > 0 then
      base_value = last_count / (growth ^ (base_level - 1))
    end
  end
  if not base_value or base_value <= 0 then
    base_value = 1000
  end

  local new = deepcopy(base_tech)
  new.name = new_name
  new.localised_name = spec.localised_name or base_tech.localised_name or {"technology-name." .. locale_key}
  new.localised_description = spec.localised_description or base_tech.localised_description or {"technology-description." .. locale_key}
  new.prerequisites = build_prerequisites(chain_key .. "-" .. base_level, base_tech.prerequisites)
  new.level = desired_new_level

  local special = SPECIALS[key]
  local desired_effects = nil
  if special and special.effect_builder then
    desired_effects = special.effect_builder(base_tech, spec)
  else
    desired_effects = deepcopy(base_tech.effects or {})
  end
  effect_safety.assert_effects_allowed(desired_effects, "base extension " .. key)
  if not prefer_this_mod_for_competing_techs() then
    local other_choice = find_any_infinite_extension(chain_key .. "-" .. base_level, new_name)
    if other_choice then
      log("[more-infinite-research] Skipping extension for " .. key .. ": competing infinite tech kept from other mod (" .. other_choice .. ").")
      D.extension(D.extension_fields(key, "skipped", "competing_infinite_kept"))
      return
    end
  end
  local existing = find_equivalent_infinite_extension(chain_key .. "-" .. base_level, desired_effects)
  if existing then
    log("[more-infinite-research] Skipping extension for " .. key .. ": equivalent infinite tech already exists (" .. existing .. ").")
    D.extension(D.extension_fields(key, "skipped", "equivalent_infinite_exists"))
    return
  end
  new.effects = desired_effects

  new.max_level = max_level_value
  new.upgrade = true

  local research_setting = sanitize_number(startup_setting("mir-research-time-" .. key))
  local force_vanilla_time = research_setting == 0
  local research_time = nil
  if research_setting and research_setting > 0 then
    research_time = research_setting
  end
  if not research_time and not force_vanilla_time then
    research_time = sanitize_number(spec.research_time)
  end
  if not research_time or research_time <= 0 then
    research_time = base_tech.unit.time or 60
  end

  local selected_ingredients = science_selector.apply_science_pack_ingredient_policy(resolve_science_packs(spec, base_tech.unit, key))
  local resolved_ingredients, lab_status = science_packs.best_lab_compatible_ingredients(selected_ingredients, key)
  lab_status = lab_status or "full"
  if not resolved_ingredients or #resolved_ingredients == 0 then
    log("[more-infinite-research] Skipping extension for " .. key .. ": no lab-compatible science pack set was found.")
    D.extension(D.extension_fields(key, "skipped", "no_lab_compatible_science", resolved_ingredients, new.prerequisites, desired_effects, lab_status))
    return
  end
  new.unit = {
    count_formula = format_number(base_value) .. " * " .. format_number(growth) .. "^(L-1)",
    ingredients = resolved_ingredients,
    time = research_time
  }
  new.prerequisites = planner_prerequisites.append_end_game_gate_prerequisite(append_pack_prerequisites(new.prerequisites, resolved_ingredients))

  if special and special.on_extend then
    special.on_extend(new, base_tech, spec)
  end

  data_raw.extend({ new })
  effect_safety.register_generated_technology(new.name)
  D.extension(D.extension_fields(key, "generated", "base_extension", resolved_ingredients, new.prerequisites, new.effects, lab_status))
end

function M.emit_all()
  for _, key in ipairs(table_utils.sorted_keys(base_defaults)) do
    extend_chain(key)
  end

  return M
end

return M

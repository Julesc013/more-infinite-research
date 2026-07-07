local D = require("prototypes.mir.report.diagnostics_sink")
local profiles = require("prototypes.mir.compatibility.profiles")
local productivity_owners = require("prototypes.mir.index.productivity_owners")

local M = {}

local DEFAULT_RECIPE_MAX_PRODUCTIVITY = 3.0
local EXTREME_RECIPE_MAX_PRODUCTIVITY = 1000

local ROLE_SIGNALS = {
  ["Research_Productivity"] = {
    role = "MIR_COMPAT_ADAPTER",
    action = "skip_effect_proven_native_owner",
    signal = "native_lab_productivity"
  },
  ["better-bot-battery2"] = {
    role = "MIR_COMPAT_ADAPTER",
    action = "skip_effect_proven_native_owner",
    signal = "worker_robot_battery"
  },
  ["atan-air-scrubbing"] = {
    role = "MIR_STREAM_CANDIDATE",
    action = "clean_filter_productivity_only",
    signal = "air_scrubbing_filters"
  },
  ["atan-ash"] = {
    role = "MIR_STREAM_CANDIDATE",
    action = "ash_processing_fixture_candidate",
    signal = "ash_processing_recipe_surface"
  },
  ["atan-nuclear-science"] = {
    role = "MIR_STREAM_CANDIDATE",
    action = "dynamic_science_pack_productivity_fixture_candidate",
    signal = "custom_science_pack_recipe"
  },
  ["FluidMustFlow"] = {
    role = "MIR_DOCS_ONLY",
    action = "load_and_pipeline_extent_coexistence",
    signal = "large_fluid_duct_content"
  },
  ["robot_attrition"] = {
    role = "MIR_DIAGNOSTIC_ONLY",
    action = "runtime_balance_mod_coexistence_only",
    signal = "robot_runtime_attrition"
  },
  ["jetpack"] = {
    role = "MIR_DOCS_ONLY",
    action = "equipment_content_coexistence_only",
    signal = "player_movement_equipment"
  },
  ["big-mining-drill"] = {
    role = "MIR_STREAM_CANDIDATE",
    action = "existing_mining_drill_stream_fixture_candidate",
    signal = "mining_drill_recipe"
  },
  ["equipment-gantry"] = {
    role = "MIR_DOCS_ONLY",
    action = "equipment_grid_content_coexistence_only",
    signal = "equipment_grid_automation"
  },
  ["aai-industry"] = {
    role = "MIR_STREAM_CANDIDATE",
    action = "mini_overhaul_procedural_tuning_profile",
    signal = "early_industry_recipe_and_science_changes"
  },
  ["aai-containers"] = {
    role = "MIR_DOCS_ONLY",
    action = "storage_content_coexistence_only",
    signal = "warehouse_container_content"
  },
  ["aai-loaders"] = {
    role = "MIR_STREAM_CANDIDATE",
    action = "belt_productivity_loader_recipe_candidate",
    signal = "loader_recipe_productivity"
  },

  ["finite_prod_techs"] = {
    role = "MIR_DIAGNOSTIC_ONLY",
    action = "report_caps_only",
    signal = "recipe_productivity_caps"
  },
  ["productivity-technology-limit"] = {
    role = "MIR_DIAGNOSTIC_ONLY",
    action = "report_caps_only",
    signal = "recipe_productivity_caps"
  },
  ["modified-productivity-cap"] = {
    role = "MIR_DIAGNOSTIC_ONLY",
    action = "report_caps_only",
    signal = "recipe_productivity_caps"
  },
  ["remove-productivity-cap"] = {
    role = "MIR_DIAGNOSTIC_ONLY",
    action = "report_caps_only",
    signal = "recipe_productivity_caps"
  },

  ["base-prod"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "machine_base_productivity"
  },
  ["Prod-Beacon"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "beacon_productivity"
  },
  ["prodforce"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "productivity_rule_mutator"
  },
  ["Productivity"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "productivity_rule_mutator"
  },
  ["productivity_fix"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "productivity_rule_mutator"
  },
  ["Productivity-config"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "machine_base_productivity"
  },
  ["rosnok-productivity-quality-beacon"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "beacon_productivity"
  },
  ["SchallModules"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "module_system"
  },
  ["space-exploration-spaceproductivity-2"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "space_productivity_rules"
  },
  ["UnlimitedProductivityFork"] = {
    role = "MIR_COMPANION_SCOPE",
    action = "do_not_mutate_rules",
    signal = "productivity_rule_mutator"
  },

  ["progressive-productivity"] = {
    role = "MIR_REJECT_CORE",
    action = "runtime_system_not_absorbed",
    signal = "runtime_productivity"
  },
  ["productivity-through-science"] = {
    role = "MIR_REJECT_CORE",
    action = "runtime_system_not_absorbed",
    signal = "runtime_productivity"
  },
  ["solar-productivity"] = {
    role = "MIR_REJECT_CORE",
    action = "runtime_system_not_absorbed",
    signal = "runtime_entity_replacement"
  },

  ["research-cost-curve"] = {
    role = "MIR_DOCS_ONLY",
    action = "cost_tool_coexist",
    signal = "research_cost"
  },
  ["research-multipliers"] = {
    role = "MIR_DOCS_ONLY",
    action = "cost_tool_coexist",
    signal = "research_cost"
  },
  ["zz-long-science"] = {
    role = "MIR_DOCS_ONLY",
    action = "cost_tool_coexist",
    signal = "research_cost"
  },
  ["ConfigurableResearchCost"] = {
    role = "MIR_DOCS_ONLY",
    action = "cost_tool_coexist",
    signal = "research_cost"
  },
  ["customresearchspeed"] = {
    role = "MIR_DOCS_ONLY",
    action = "lab_mutator_coexist",
    signal = "research_speed"
  }
}

local function sorted_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function mod_active(name)
  return mods and mods[name] ~= nil
end

local function format_number(value)
  if value == nil then return "" end
  return string.format("%.6g", value)
end

local function cap_state(recipe)
  local value = recipe and recipe.maximum_productivity
  if value == nil then
    return DEFAULT_RECIPE_MAX_PRODUCTIVITY, "default"
  end
  if type(value) ~= "number" then
    return nil, "unusual"
  end
  if math.abs(value - DEFAULT_RECIPE_MAX_PRODUCTIVITY) < 0.000000001 then
    return value, "default_explicit"
  end
  if value < DEFAULT_RECIPE_MAX_PRODUCTIVITY then
    return value, "lowered"
  end
  return value, "raised"
end

local function warning_class(cap, state, per_level)
  if not cap or not per_level or per_level <= 0 then return "unusual" end
  if cap <= 0 then return "capped" end
  if cap >= EXTREME_RECIPE_MAX_PRODUCTIVITY then return "uncapped_or_extreme" end

  local levels = math.floor((cap / per_level) + 0.000000001)
  if levels <= 0 then return "capped" end
  if levels <= 3 then return "near_cap" end
  if state == "lowered" then return "lowered_cap" end
  if state == "raised" then return "raised_cap" end
  return "ok"
end

local function emit_active_roles()
  local count = 0

  for _, entry in ipairs(profiles.active_known_competing_productivity_profiles()) do
    count = count + 1
    D.compatibility_role({
      key = entry.mod,
      status = "diagnostic",
      reason = "known_competing_productivity_profile_active",
      mod = entry.mod,
      role = "MIR_REPLACE_EXACT",
      action = "guarded_exact_cleanup",
      signal = "recipe_productivity_owner"
    })
  end

  for _, mod_name in ipairs(sorted_keys(ROLE_SIGNALS)) do
    if mod_active(mod_name) then
      local signal = ROLE_SIGNALS[mod_name]
      count = count + 1
      D.compatibility_role({
        key = mod_name,
        status = "diagnostic",
        reason = "known_audit_signal_active",
        mod = mod_name,
        role = signal.role,
        action = signal.action,
        signal = signal.signal
      })
    end
  end

  return count
end

local function generated_recipe_productivity_techs()
  local techs = {}
  for tech_name, tech in pairs(data.raw.technology or {}) do
    if productivity_owners.is_mir_recipe_productivity_tech(tech_name) then
      table.insert(techs, {
        name = tech_name,
        tech = tech
      })
    end
  end
  table.sort(techs, function(a, b) return a.name < b.name end)
  return techs
end

local function emit_cap_diagnostics()
  local total = 0
  local warnings = 0
  local states = {
    default = 0,
    default_explicit = 0,
    lowered = 0,
    raised = 0,
    unusual = 0
  }

  for _, entry in ipairs(generated_recipe_productivity_techs()) do
    for _, effect in ipairs(entry.tech.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe then
        total = total + 1
        local recipe = data.raw.recipe and data.raw.recipe[effect.recipe]
        local cap, state = cap_state(recipe)
        states[state] = (states[state] or 0) + 1

        local per_level = tonumber(effect.change)
        local warning = warning_class(cap, state, per_level)
        if warning ~= "ok" then
          warnings = warnings + 1
          local levels = ""
          if cap and per_level and per_level > 0 then
            levels = tostring(math.floor((cap / per_level) + 0.000000001))
          end
          D.recipe_cap({
            key = entry.name,
            status = "diagnostic",
            reason = "recipe_productivity_cap_warning",
            recipe = effect.recipe,
            warning_class = warning,
            cap_state = state,
            maximum_productivity = format_number(cap),
            per_level = format_number(per_level),
            levels_to_cap = levels,
            useful_level_estimate = levels
          })
        end
      end
    end
  end

  D.compatibility_plan({
    key = "recipe_productivity_caps",
    status = "diagnostic",
    reason = "warnings_only",
    total = tostring(total),
    warnings = tostring(warnings),
    default_cap = tostring(states.default or 0),
    explicit_default_cap = tostring(states.default_explicit or 0),
    lowered_cap = tostring(states.lowered or 0),
    raised_cap = tostring(states.raised or 0),
    unusual_cap = tostring(states.unusual or 0)
  })

  return total, warnings
end

function M.emit()
  local role_count = emit_active_roles()
  local cap_total, cap_warnings = emit_cap_diagnostics()

  D.compatibility_plan({
    key = "compatibility_planner",
    status = "diagnostic",
    reason = "planner_summary",
    total = tostring(role_count),
    warnings = tostring(cap_warnings),
    recipes = tostring(cap_total)
  })
end

return M

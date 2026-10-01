-- MIR adapter for the portable research surface. It reads Factorio and MIR
-- runtime state, then exposes only bounded, copied scalar DTOs to the core.
-- A malformed public projection is omitted rather than guessed from names.
local profile_codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local maximum_level_control = require("prototypes.mir.runtime.maximum_level_control")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {schema = 2, catalogue_limit = 30000}

local function bounded_string(value)
  return type(value) == "string" and value ~= "" and #value <= 1024
end

local function mod_data(name)
  local prototype = prototypes.mod_data and prototypes.mod_data[name]
  return prototype and prototype.data or nil
end

local function sorted_unique_strings(values)
  if type(values) ~= "table" then return nil end
  local count = 0
  for index, _ in pairs(values) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return nil end
    count = count + 1
  end
  if #values ~= count then return nil end
  local seen, out = {}, {}
  for index, value in ipairs(values) do
    if not bounded_string(value) or seen[value] then return nil end
    seen[value] = true
    out[index] = value
  end
  table.sort(out)
  for index, value in ipairs(values) do if out[index] ~= value then return nil end end
  return out
end

local function dense_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for index in pairs(value) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return false end
    count = count + 1
  end
  return #value == count
end

local function fingerprint_matches(record, field)
  if type(record) ~= "table" or not bounded_string(record[field]) then return false end
  local material = {}
  for key, value in pairs(record) do material[key] = value end
  material[field] = nil
  local ok, actual = pcall(fingerprint.of, material)
  return ok and actual == record[field]
end

local function only_fields(value, allowed)
  for key in pairs(value) do if not allowed[key] then return false end end
  return true
end

local function finite_nonnegative_integer(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value >= 0 and value == math.floor(value)
end

local function optional_bounded_string(value)
  return value == nil or bounded_string(value)
end

local function same_array(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if right[index] ~= value then return false end end
  return true
end

local function scalar_equal(left, right)
  return type(left) == type(right) and left == right
end

local function comparison(name)
  local prototype = prototypes.mod_setting and prototypes.mod_setting[name]
  local setting = settings and settings.startup and settings.startup[name]
  local catalog_spec = settings_catalog.spec(name)
  if not prototype or prototype.mod ~= "more-infinite-research"
    or prototype.setting_type ~= "startup" or not setting or prototype.default_value == nil
    or type(catalog_spec) ~= "table" or catalog_spec.name ~= name then
    return nil
  end
  local raw, source, effective = setting.value, "direct", setting.value
  local import_setting = settings.startup[profile_codec.import_setting_name]
  if import_setting and type(import_setting.value) == "string" and import_setting.value ~= "" then
    local profile = profile_codec.decode(import_setting.value)
    local imported = profile and profile.settings and profile.settings[name]
    if imported ~= nil and settings_catalog.validate_value(name, imported) then
      source, effective = "mirset1", imported
    end
  end
  -- Cross-check the ordinary package resolver. A valid MIRSET1 value that the
  -- runtime does not actually select is not safe browser evidence.
  if not scalar_equal(startup_settings.get(name), effective) then return nil end
  return {
    name = name,
    default = prototype.default_value,
    raw_direct = raw,
    effective = effective,
    source = source,
    changed = not scalar_equal(raw, effective),
    changed_from_default = not scalar_equal(prototype.default_value, effective),
    restart_required = true
  }
end

local function science_ingredients(technology)
  local out = {}
  for _, ingredient in ipairs(technology.research_unit_ingredients or {}) do
    if type(ingredient.name) ~= "string" or ingredient.name == ""
      or type(ingredient.amount) ~= "number" or ingredient.amount <= 0 then return nil end
    table.insert(out, {name = ingredient.name, amount = ingredient.amount})
  end
  table.sort(out, function(left, right)
    return left.name == right.name and left.amount < right.amount or left.name < right.name
  end)
  return out
end

local function productivity_effects(technology)
  local known, out = {}, {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and type(effect.recipe) == "string"
      and effect.recipe ~= "" and not known[effect.recipe] then
      local change = effect.change
      if change == nil then change = effect.modifier end
      if type(change) ~= "number" or change ~= change or change == math.huge
        or change == -math.huge or change <= 0 then return nil end
      known[effect.recipe] = true
      table.insert(out, {recipe_id = effect.recipe, change = change})
    end
  end
  table.sort(out, function(left, right) return left.recipe_id < right.recipe_id end)
  return out
end

local function recipe_ids(effects)
  local out = {}
  for index, effect in ipairs(effects or {}) do out[index] = effect.recipe_id end
  return out
end

local function finite_positive_integer(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value > 0 and value == math.floor(value)
end

local function technology_next_level_is_eligible(technology, selected_cap)
  if not technology or technology.enabled ~= true or technology.researched == true then return false end
  local level = tonumber(technology.level)
  if not finite_positive_integer(level) then return false end
  if finite_positive_integer(selected_cap) then return level <= selected_cap end
  local maximum = technology.prototype and technology.prototype.max_level
  return maximum == "infinite" or finite_positive_integer(maximum) and level <= maximum
end

local function recipe_has_next_level_headroom(recipe)
  return type(recipe.effect_change) == "number" and recipe.effect_change == recipe.effect_change
    and recipe.effect_change ~= math.huge and recipe.effect_change ~= -math.huge and recipe.effect_change > 0
    and type(recipe.current_productivity_bonus) == "number" and type(recipe.maximum_productivity) == "number"
    and recipe.current_productivity_bonus == recipe.current_productivity_bonus
    and recipe.maximum_productivity == recipe.maximum_productivity
    and recipe.current_productivity_bonus ~= math.huge and recipe.current_productivity_bonus ~= -math.huge
    and recipe.maximum_productivity ~= math.huge and recipe.maximum_productivity ~= -math.huge
    and recipe.current_productivity_bonus < recipe.maximum_productivity - 0.000000001
end

local function recipe_benefit_facts(force, effects, next_level_eligible)
  local out = {}
  for _, effect in ipairs(effects or {}) do
    local recipe = force and force.recipes and force.recipes[effect.recipe_id]
    local maximum = recipe and recipe.prototype and tonumber(recipe.prototype.maximum_productivity)
    local current = recipe and tonumber(recipe.productivity_bonus)
    if not recipe or not recipe.valid or not maximum or not current
      or maximum ~= maximum or current ~= current or maximum == math.huge or current == math.huge
      or maximum < 0 or current < 0 then return nil end
    table.insert(out, {
      recipe_id = effect.recipe_id,
      effect_change = effect.change,
      current_productivity_bonus = current,
      maximum_productivity = maximum,
      next_level_has_effective_benefit = next_level_eligible and recipe_has_next_level_headroom({
        effect_change = effect.change,
        current_productivity_bonus = current,
        maximum_productivity = maximum
      })
    })
  end
  return out
end

-- Kept as an internal module helper for the package-excluded fixture; it is
-- not a remote interface or a stable external API.
function M.next_level_has_effective_benefit(technology, selected_cap, recipes)
  if not technology_next_level_is_eligible(technology, selected_cap) then return false end
  for _, recipe in ipairs(recipes or {}) do
    if recipe_has_next_level_headroom(recipe) then return true end
  end
  return false
end

local INFINITE_RUNTIME_MAX_LEVEL = 4294967295
local MAXIMUM_LEVEL_FINALIZER_ADAPTER = "factorio-data-final-fixes-v1"

local function prototype_is_runtime_infinite(technology_id, prototype_table)
  local technologies = prototype_table
    or (prototypes and prototypes.technology)
  local technology = technologies and technologies[technology_id]
  local maximum = technology and technology.max_level or nil
  return maximum == "infinite"
    or (type(maximum) == "number" and maximum >= INFINITE_RUNTIME_MAX_LEVEL)
end

local function policy_caps(artifact, prototype_table)
  artifact = artifact or mod_data("more-infinite-research-maximum-level-policy")
  if type(artifact) ~= "table" or not dense_array(artifact.bindings) then
    return {}
  end
  local values, counts = {}, {}
  if artifact.schema == 3 and artifact.kind == "MIRMaximumLevelPolicyV3" then
    if artifact.finalizer_status ~= "accepted"
        or artifact.finalizer_adapter ~= MAXIMUM_LEVEL_FINALIZER_ADAPTER
        or not fingerprint_matches(artifact, "artifact_fingerprint") then return {} end
    for _, binding in ipairs(artifact.bindings) do
      if type(binding) == "table" and binding.schema == 3
          and binding.record_type == "MaximumLevelBinding"
          and bounded_string(binding.technology_id) then
        local technology_id = binding.technology_id
        counts[technology_id] = (counts[technology_id] or 0) + 1
        local setting = binding.setting
        local cap = binding.cap
        local diagnostics = binding.diagnostics
        local finalizer = binding.finalizer_observation
        local prototype_strategy = binding.prototype_strategy
        local strategy = binding.runtime_strategy
        local requirements = binding.target_requirements
        if fingerprint_matches(binding, "binding_fingerprint")
          and type(setting) == "table" and bounded_string(setting.name)
          and type(cap) == "table" and finite_positive_integer(cap.effective)
          and type(diagnostics) == "table" and diagnostics.status == "accepted"
          and type(prototype_strategy) == "table"
          and prototype_strategy.mode == "lossless-infinite-prototype"
          and prototype_strategy.max_level == "infinite"
          and type(strategy) == "table" and strategy.mode == "absolute-cap-controller"
          and type(requirements) == "table"
          and requirements.scripted_techs == true
          and requirements.scripted_techs_supported == true
          and requirements.mod_data_transport_supported == true
          and requirements.finalizer_adapter == MAXIMUM_LEVEL_FINALIZER_ADAPTER
          and type(finalizer) == "table" and finalizer.status == "accepted"
          and finalizer.adapter == MAXIMUM_LEVEL_FINALIZER_ADAPTER
          and finalizer.observed_prototype_max_level == "infinite"
          and prototype_is_runtime_infinite(technology_id, prototype_table) then
          values[technology_id] = {selected = cap.effective, setting = setting.name}
        end
      end
    end
  elseif artifact.schema == 2 and artifact.kind == "MIRMaximumLevelPolicyV2" then
    -- The V3 runtime controller deliberately cannot enforce a V2 transport,
    -- so the browser must not advertise those legacy caps as effective.
    return {}
  else
    return {}
  end
  for technology, count in pairs(counts) do
    if count ~= 1 then values[technology] = nil end
  end
  return values
end

-- Startup settings, policy transports and final prototypes change at the
-- configuration lifecycle, not per row click or completed research. Keep
-- only their validated plain outcome; recipe/level facts remain live below.
local validated_policy_caps
local validated_runtime_settings_bindings

local function current_policy_caps()
  if validated_policy_caps == nil then validated_policy_caps = policy_caps() end
  return validated_policy_caps
end

function M.policy_caps_for_test(artifact, prototype_table)
  return policy_caps(artifact, prototype_table)
end

local runtime_binding_sources = {
  ["generated-stream"] = true,
  ["base-continuation"] = true
}

local runtime_binding_transports = {
  ["transported-v3"] = true,
  ["settings-derived-v3"] = true
}

local function valid_runtime_setting(setting, expected_name)
  if type(setting) ~= "table" or not only_fields(setting, {name = true, default = true,
      raw_direct = true, effective = true, source = true, changed = true,
      changed_from_default = true, restart_required = true})
      or setting.name ~= expected_name or (setting.source ~= "direct" and setting.source ~= "mirset1")
      or not finite_nonnegative_integer(setting.default)
      or not finite_nonnegative_integer(setting.raw_direct)
      or not finite_nonnegative_integer(setting.effective)
      or type(setting.changed) ~= "boolean" or type(setting.changed_from_default) ~= "boolean"
      or setting.changed ~= (not scalar_equal(setting.raw_direct, setting.effective))
      or setting.changed_from_default ~= (not scalar_equal(setting.default, setting.effective))
      or setting.restart_required ~= true then
    return false
  end
  local spec = settings_catalog.spec(expected_name)
  return type(spec) == "table" and spec.name == expected_name and spec.type == "int-setting"
    and settings_catalog.validate_value(expected_name, setting.default)
    and settings_catalog.validate_value(expected_name, setting.raw_direct)
    and settings_catalog.validate_value(expected_name, setting.effective)
end

local function valid_controller_runtime_binding(technology_id, binding)
  if type(binding) ~= "table" or not only_fields(binding, {schema = true, source = true,
      policy_transport = true, binding = true, selected_effective = true, state = true,
      blocked_reason = true}) or binding.schema ~= 1
      or not bounded_string(technology_id) or not runtime_binding_sources[binding.source]
      or not runtime_binding_transports[binding.policy_transport]
      or type(binding.binding) ~= "table"
      or not only_fields(binding.binding, {technology_id = true, declared_key = true, setting_name = true})
      or binding.binding.technology_id ~= technology_id
      or not bounded_string(binding.binding.declared_key)
      or not bounded_string(binding.binding.setting_name) then
    return false
  end
  local selected = binding.selected_effective
  local finite, infinite = finite_nonnegative_integer(selected) and selected > 0, selected == "infinite"
  if not finite and not infinite then return false end
  if binding.state == "finite" then
    return finite and binding.blocked_reason == nil
  elseif binding.state == "infinite" then
    return infinite and binding.blocked_reason == nil
  elseif binding.state == "disabled" then
    return bounded_string(binding.blocked_reason)
  end
  return false
end

local function copy_runtime_settings_binding(binding, setting)
  return {
    schema = 1,
    source = binding.source,
    policy_transport = binding.policy_transport,
    binding = {
      technology_id = binding.binding.technology_id,
      declared_key = binding.binding.declared_key,
      setting_name = binding.binding.setting_name
    },
    setting = {
      name = setting.name,
      default = setting.default,
      raw_direct = setting.raw_direct,
      effective = setting.effective,
      source = setting.source,
      changed = setting.changed,
      changed_from_default = setting.changed_from_default,
      restart_required = setting.restart_required
    },
    selected_effective = binding.selected_effective,
    state = binding.state,
    blocked_reason = binding.blocked_reason
  }
end

-- Startup settings and validated controller bindings change at the same
-- lifecycle boundary as the existing policy-cap cache. Cache only copied
-- scalar facts here; each snapshot below still intersects the result with the
-- current Force technology table.
local function current_runtime_settings_bindings()
  if validated_runtime_settings_bindings ~= nil then
    return validated_runtime_settings_bindings
  end
  local controller_bindings = maximum_level_control.runtime_settings_bindings()
  local bindings, count = {}, 0
  if type(controller_bindings) == "table" then
    for technology_id, binding in pairs(controller_bindings) do
      count = count + 1
      if count > M.catalogue_limit then
        validated_runtime_settings_bindings = {}
        return validated_runtime_settings_bindings
      end
      if valid_controller_runtime_binding(technology_id, binding) then
        local setting = comparison(binding.binding.setting_name)
        if valid_runtime_setting(setting, binding.binding.setting_name) then
          local selected, effective = binding.selected_effective, setting.effective
          local matches = (binding.state == "finite" and selected == effective)
            or (binding.state == "infinite" and selected == "infinite" and effective == 0)
            or (binding.state == "disabled" and ((selected == "infinite" and effective == 0)
              or (type(selected) == "number" and selected == effective)))
          if matches then
            bindings[technology_id] = copy_runtime_settings_binding(binding, setting)
          end
        end
      end
    end
  end
  validated_runtime_settings_bindings = bindings
  return bindings
end

local function live_runtime_settings_bindings(force)
  local out = {}
  if not force or not force.valid then return out end
  local count = 0
  for technology_id, binding in pairs(current_runtime_settings_bindings()) do
    count = count + 1
    if count > M.catalogue_limit then return {} end
    local technology = force.technologies and force.technologies[technology_id]
    if technology and technology.valid then
      out[technology_id] = copy_runtime_settings_binding(binding, binding.setting)
    end
  end
  return out
end

local function valid_public_row(row, allow_absent_technology)
  if type(row) ~= "table" or row.schema ~= 1
    or not only_fields(row, {schema = true, stream_id = true, action = true, reason = true,
      technology_id = true, effect_count = true, effect_identities = true, affected_recipe_ids = true,
      disposition = true, subject_fingerprint = true, qualification_fingerprint = true,
      decision_fingerprint = true})
    or not bounded_string(row.stream_id)
    or (not bounded_string(row.technology_id)
      and not (allow_absent_technology and row.action == "skip" and row.technology_id == nil))
    or (row.action ~= "emit" and row.action ~= "adopt" and row.action ~= "skip")
    or not bounded_string(row.reason)
    or not finite_nonnegative_integer(row.effect_count)
    or not optional_bounded_string(row.subject_fingerprint)
    or not optional_bounded_string(row.qualification_fingerprint)
    or not optional_bounded_string(row.decision_fingerprint) then return nil end
  local identities = sorted_unique_strings(row.effect_identities)
  local recipes = sorted_unique_strings(row.affected_recipe_ids)
  local disposition = row.disposition
  if not identities or row.effect_count ~= #identities or not recipes or #recipes > row.effect_count
    or type(disposition) ~= "table"
    or not only_fields(disposition, {schema = true, inclusion = true, action = true,
      reason = true, route_exclusions = true})
    or disposition.schema ~= 1
    or disposition.action ~= row.action or disposition.reason ~= row.reason
    or disposition.inclusion ~= ((row.action == "emit" or row.action == "adopt") and "included" or "excluded")
    or type(disposition.route_exclusions) ~= "table"
    or not only_fields(disposition.route_exclusions, {state = true, recipe_ids = true})
    or disposition.route_exclusions.state ~= "no-additional-route-exclusions-published-for-current-row"
    or not sorted_unique_strings(disposition.route_exclusions.recipe_ids)
    or #disposition.route_exclusions.recipe_ids ~= 0 then
    return nil
  end
  return recipes, disposition
end

-- Omission facts are separate from force technologies: a skipped generation
-- row cannot become a research/queue action or imply removal from a save.
-- The public candidate cache also holds copied immutable facts only; force and
-- prototype observations remain live in snapshot().
local omission_rows, validated_public_candidates

function M.invalidate_omissions()
  omission_rows = nil
  validated_public_candidates = nil
  validated_policy_caps = nil
  validated_runtime_settings_bindings = nil
end

local function omitted_public_rows()
  local artifact = mod_data("more-infinite-research-generation-plan")
  if type(artifact) ~= "table" or artifact.schema ~= 1
    or artifact.kind ~= "mir-generation-plan-public" or not dense_array(artifact.rows)
    or #artifact.rows > M.catalogue_limit then return nil end
  local rows, known = {}, {}
  for _, row in ipairs(artifact.rows) do
    local recipes, disposition = valid_public_row(row, true)
    if not recipes or not bounded_string(row.decision_fingerprint) then return nil end
    local key = row.stream_id .. "\0" .. (row.technology_id or "")
    if known[key] then return nil end
    known[key] = true
    if row.action == "skip" and disposition.inclusion == "excluded" then
      rows[#rows + 1] = {
        stream_id = row.stream_id,
        technology_id = row.technology_id,
        reason = row.reason,
        decision_fingerprint = row.decision_fingerprint,
        status = "not-added"
      }
    end
  end
  if not fingerprint_matches(artifact, "public_fingerprint") then return nil end
  table.sort(rows, function(left, right)
    if left.stream_id ~= right.stream_id then return left.stream_id < right.stream_id end
    return (left.technology_id or "") < (right.technology_id or "")
  end)
  return rows
end

function M.omissions(force)
  if not force or not force.valid then return nil end
  if omission_rows == nil then omission_rows = omitted_public_rows() or false end
  if omission_rows == false then return nil end
  local rows = {}
  for _, row in ipairs(omission_rows) do
    -- A skip with an existing technology is not evidence of an absent one.
    if not row.technology_id or not force.technologies[row.technology_id] then
      rows[#rows + 1] = {
        stream_id = row.stream_id,
        technology_id = row.technology_id,
        reason = row.reason,
        decision_fingerprint = row.decision_fingerprint,
        status = row.status
      }
    end
  end
  return {schema = 1, kind = "portable-research-omissions", rows = rows}
end

local function copy_string_array(values)
  local copy = {}
  for index, value in ipairs(values) do copy[index] = value end
  return copy
end

local function detail_for_row(row, recipes, disposition, caps, force)
  local policy = caps[row.technology_id]
  local technology = force and force.technologies and force.technologies[row.technology_id]
  -- Enrichment describes live managed research. Omission rows have their own
  -- DTO and an absent or foreign technology must not create a phantom family.
  if not technology or not technology.valid then return nil end
  -- Keep the original schema-1 family/action surface for a live admitted
  -- non-recipe technology. It has no recipe-productivity benefit question,
  -- so do not turn an empty effect set into an exact false benefit claim.
  if #recipes == 0 then
    return {schema = 1, family = row.stream_id, action = row.action}
  end
  local max_setting, enable_setting = nil, nil
  if policy then
    max_setting = comparison(policy.setting)
    enable_setting = comparison("ips-enable-" .. row.stream_id)
    if not max_setting or not enable_setting or max_setting.effective ~= policy.selected then return nil end
  end
  local effects = productivity_effects(technology.prototype)
  local observed_recipes = recipe_ids(effects)
  local next_level_eligible = technology_next_level_is_eligible(technology, policy and policy.selected)
  local benefits = recipe_benefit_facts(
    force,
    effects,
    next_level_eligible
  )
  local ingredients = science_ingredients(technology.prototype)
  if not effects or not benefits or not ingredients or not same_array(observed_recipes, recipes) then return nil end
  local level = tonumber(technology.level)
  if not finite_positive_integer(level) then return nil end
  local detail = {
    schema = 1,
    family = row.stream_id,
    action = row.action,
    owner = {
      technology_id = row.technology_id,
      stream_id = row.stream_id,
      action = row.action,
      reason = row.reason,
      affected_recipe_ids = copy_string_array(recipes)
    },
    compiler_disposition = {
      inclusion = disposition.inclusion,
      action = disposition.action,
      reason = disposition.reason,
      route_exclusions = {
        state = disposition.route_exclusions.state,
        recipe_ids = {}
      }
    },
    final_science = {
      rationale = "final-technology-prototype-cross-bound-to-public-generation-plan-row",
      ingredients = ingredients
    },
    current_level = level,
    recipe_benefits = benefits,
    next_level_eligible = next_level_eligible,
    next_level_has_effective_benefit = M.next_level_has_effective_benefit(technology, policy and policy.selected, benefits)
  }
  -- A finite policy is a separate fact from a productive MIR technology. The
  -- normal zero/unbounded setting has no controller binding, but its live
  -- recipe benefits remain useful and truthful player information.
  if policy then
    detail.effective_cap = policy.selected
    detail.settings = {
      maximum_level = max_setting,
      enabled = enable_setting
    }
  end
  return detail
end

-- The catalogue needs stable ownership and recipe identifiers, but only the
-- selected entry needs live productivity values. Keep the same prototype,
-- policy and science cross-checks used by the rich detail path.
local function list_facts_for_row(row, recipes, caps, force)
  local technology = force and force.technologies and force.technologies[row.technology_id]
  if not technology or not technology.valid then return nil end
  if #recipes == 0 then return {recipe_ids = recipes} end
  local policy = caps[row.technology_id]
  if policy then
    local maximum = comparison(policy.setting)
    local enabled = comparison("ips-enable-" .. row.stream_id)
    if not maximum or not enabled or maximum.effective ~= policy.selected then return nil end
  end
  if not finite_positive_integer(tonumber(technology.level)) then return nil end
  local effects = productivity_effects(technology.prototype)
  if not effects or not science_ingredients(technology.prototype)
    or not same_array(recipe_ids(effects), recipes) then return nil end
  return {cap = policy and policy.selected or nil, recipe_ids = recipes}
end

local function copy_public_candidate(row, recipes, disposition)
  return {
    row = {
      stream_id = row.stream_id,
      technology_id = row.technology_id,
      action = row.action,
      reason = row.reason
    },
    recipes = copy_string_array(recipes),
    disposition = {
      inclusion = disposition.inclusion,
      action = disposition.action,
      reason = disposition.reason,
      route_exclusions = {
        state = disposition.route_exclusions.state,
        recipe_ids = {}
      }
    }
  }
end

-- The public generation plan is a data-stage artifact. Validate and copy its
-- admitted candidates once per init/configuration epoch; completed research
-- and player interaction must still evaluate live Force facts below.
local function current_public_candidates()
  if validated_public_candidates ~= nil then
    return validated_public_candidates ~= false and validated_public_candidates or nil
  end
  local artifact = mod_data("more-infinite-research-generation-plan")
  if type(artifact) ~= "table" or artifact.schema ~= 1
      or artifact.kind ~= "mir-generation-plan-public" or type(artifact.rows) ~= "table" then
    validated_public_candidates = false
    return nil
  end
  local row_count = 0
  for index in pairs(artifact.rows) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
      validated_public_candidates = false
      return nil
    end
    row_count = row_count + 1
    if row_count > M.catalogue_limit then
      validated_public_candidates = false
      return nil
    end
  end
  if #artifact.rows ~= row_count or not fingerprint_matches(artifact, "public_fingerprint") then
    validated_public_candidates = false
    return nil
  end
  local candidate_rows, row_counts = {}, {}
  for _, row in ipairs(artifact.rows) do
    -- Count every declared public technology identity before accepting its
    -- optional detail shape: a malformed shadow row cannot evade duplicate
    -- protection and leave a first valid row rendered.
    if type(row) == "table" and type(row.technology_id) == "string" and row.technology_id ~= "" then
      row_counts[row.technology_id] = (row_counts[row.technology_id] or 0) + 1
    end
    local recipes, disposition = valid_public_row(row)
    -- Skips are exact omission evidence, never managed research enrichment.
    -- Their named IDs still count above so a shadow duplicate fails closed.
    if recipes and (row.action == "emit" or row.action == "adopt") then
      candidate_rows[#candidate_rows + 1] = {row = row, recipes = recipes, disposition = disposition}
    end
  end
  local candidates = {}
  for _, candidate in ipairs(candidate_rows) do
    if row_counts[candidate.row.technology_id] == 1 then
      candidates[#candidates + 1] = copy_public_candidate(candidate.row, candidate.recipes, candidate.disposition)
    end
  end
  validated_public_candidates = candidates
  return candidates
end

function M.snapshot(force)
  local caps, families, details = {}, {}, {}
  local runtime_settings_bindings = live_runtime_settings_bindings(force)
  local candidates = current_public_candidates()
  if not candidates then
    return {schema = M.schema, kind = "portable-research-enrichment", caps = caps, families = families,
      details = details, runtime_settings_bindings = runtime_settings_bindings}
  end
  local policies = current_policy_caps()
  local count = 0
  for _, candidate in ipairs(candidates) do
    local row, recipes, disposition = candidate.row, candidate.recipes, candidate.disposition
    local detail = detail_for_row(row, recipes, disposition, policies, force)
    if detail then
      count = count + 1
      if count > M.catalogue_limit then break end
      if detail.effective_cap then caps[row.technology_id] = detail.effective_cap end
      families[row.technology_id] = row.stream_id
      details[row.technology_id] = detail
    end
  end
  return {schema = M.schema, kind = "portable-research-enrichment", caps = caps, families = families,
    details = details, runtime_settings_bindings = runtime_settings_bindings}
end

-- A refresh of the research list never traverses live Force recipe bonuses.
-- Rich detail is retrieved through selected_detail() only when requested.
function M.list_snapshot(force)
  local caps, families, recipe_ids_by_technology = {}, {}, {}
  local runtime_settings_bindings = live_runtime_settings_bindings(force)
  local candidates = current_public_candidates()
  if candidates then
    local policies = current_policy_caps()
    local count = 0
    for _, candidate in ipairs(candidates) do
      local row = candidate.row
      local facts = list_facts_for_row(row, candidate.recipes, policies, force)
      if facts then
        count = count + 1
        if count > M.catalogue_limit then break end
        families[row.technology_id] = row.stream_id
        if facts.cap then caps[row.technology_id] = facts.cap end
        recipe_ids_by_technology[row.technology_id] = copy_string_array(facts.recipe_ids)
      end
    end
  end
  return {schema = M.schema, kind = "portable-research-enrichment", caps = caps,
    families = families, recipe_ids = recipe_ids_by_technology, details = {},
    runtime_settings_bindings = runtime_settings_bindings}
end

function M.selected_detail(force, technology_id)
  if not bounded_string(technology_id) then return nil, "invalid-technology" end
  local candidates = current_public_candidates()
  if not candidates then return nil, "public-plan-unavailable" end
  local policies = current_policy_caps()
  for _, candidate in ipairs(candidates) do
    if candidate.row.technology_id == technology_id then
      local detail = detail_for_row(candidate.row, candidate.recipes, candidate.disposition, policies, force)
      if not detail then return nil, "live-detail-unavailable" end
      return detail
    end
  end
  return nil, "unknown-technology"
end
return M

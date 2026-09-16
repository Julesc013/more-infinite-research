-- MIR adapter for the portable research surface. It reads Factorio and MIR
-- runtime state, then exposes only bounded, copied scalar DTOs to the core.
-- A malformed public projection is omitted rather than guessed from names.
local profile_codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local startup_settings = require("prototypes.mir.runtime.startup_settings")

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
  if not prototype or prototype.mod ~= "more-infinite-research"
    or prototype.setting_type ~= "startup" or not setting or prototype.default_value == nil then
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
  if not technology or technology.enabled ~= true or technology.researched == true
    or not finite_positive_integer(selected_cap) then return false end
  local level = tonumber(technology.level)
  return finite_positive_integer(level) and level <= selected_cap
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

local function policy_caps(artifact)
  artifact = artifact or mod_data("more-infinite-research-maximum-level-policy")
  if type(artifact) ~= "table" or artifact.schema ~= 2
    or artifact.kind ~= "MIRMaximumLevelPolicyV2" or not dense_array(artifact.bindings) then
    return {}
  end
  local values, counts = {}, {}
  for _, binding in ipairs(artifact.bindings) do
    if type(binding) == "table" and type(binding.technology) == "string" then
      counts[binding.technology] = (counts[binding.technology] or 0) + 1
      if finite_positive_integer(binding.selected)
        and type(binding.setting) == "string" and binding.setting ~= "" then
        values[binding.technology] = {selected = binding.selected, setting = binding.setting}
      end
    end
  end
  for technology, count in pairs(counts) do
    if count ~= 1 then values[technology] = nil end
  end
  return values
end

function M.policy_caps_for_test(artifact)
  return policy_caps(artifact)
end

local function valid_public_row(row)
  if type(row) ~= "table" or row.schema ~= 1
    or not only_fields(row, {schema = true, stream_id = true, action = true, reason = true,
      technology_id = true, effect_count = true, effect_identities = true, affected_recipe_ids = true,
      disposition = true, subject_fingerprint = true, qualification_fingerprint = true,
      decision_fingerprint = true})
    or not bounded_string(row.stream_id) or not bounded_string(row.technology_id)
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

local function detail_for_row(row, recipes, disposition, caps, force)
  local policy = caps[row.technology_id]
  local technology = force and force.technologies and force.technologies[row.technology_id]
  -- Keep the original schema-1 family/action surface for non-recipe rows.
  -- They do not have a recipe-productivity benefit question, so do not turn
  -- an empty effect set into an exact false benefit claim.
  if #recipes == 0 then
    return {schema = 1, family = row.stream_id, action = row.action}
  end
  if not policy or not technology or not technology.valid then return nil end
  local max_setting = comparison(policy.setting)
  local enable_setting = comparison("ips-enable-" .. row.stream_id)
  if not max_setting or not enable_setting or max_setting.effective ~= policy.selected then return nil end
  local effects = productivity_effects(technology.prototype)
  local observed_recipes = recipe_ids(effects)
  local benefits = recipe_benefit_facts(
    force,
    effects,
    technology_next_level_is_eligible(technology, policy.selected)
  )
  local ingredients = science_ingredients(technology.prototype)
  if not effects or not benefits or not ingredients or not same_array(observed_recipes, recipes) then return nil end
  local level = tonumber(technology.level)
  if not level or level < 1 or level ~= math.floor(level) then return nil end
  return {
    schema = 1,
    family = row.stream_id,
    action = row.action,
    owner = {
      technology_id = row.technology_id,
      stream_id = row.stream_id,
      action = row.action,
      reason = row.reason,
      affected_recipe_ids = recipes
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
    effective_cap = policy.selected,
    current_level = level,
    recipe_benefits = benefits,
    -- Infinite technologies report the current/next level. At level three,
    -- with two completed levels and cap three, that final level remains
    -- beneficial only if a targeted recipe has not reached its own maximum.
    next_level_has_effective_benefit = M.next_level_has_effective_benefit(technology, policy.selected, benefits),
    settings = {
      maximum_level = max_setting,
      enabled = enable_setting
    }
  }
end

function M.snapshot(force)
  local caps, families, details, known = {}, {}, {}, {}
  local artifact = mod_data("more-infinite-research-generation-plan")
  if type(artifact) ~= "table" or artifact.schema ~= 1
    or artifact.kind ~= "mir-generation-plan-public" or type(artifact.rows) ~= "table" then
    return {schema = M.schema, kind = "portable-research-enrichment", caps = caps, families = families, details = details}
  end
  local row_count = 0
  for index, _ in pairs(artifact.rows) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
      return {schema = M.schema, kind = "portable-research-enrichment", caps = caps, families = families, details = details}
    end
    row_count = row_count + 1
  end
  if #artifact.rows ~= row_count then
    return {schema = M.schema, kind = "portable-research-enrichment", caps = caps, families = families, details = details}
  end
  local policies, candidates, row_counts = policy_caps(), {}, {}
  for _, row in ipairs(artifact.rows) do
    -- Count every declared public technology identity before accepting its
    -- optional detail shape: a malformed shadow row cannot evade duplicate
    -- protection and leave a first valid row rendered.
    if type(row) == "table" and type(row.technology_id) == "string" and row.technology_id ~= "" then
      row_counts[row.technology_id] = (row_counts[row.technology_id] or 0) + 1
    end
    local recipes, disposition = valid_public_row(row)
    if recipes then
      candidates[#candidates + 1] = {row = row, recipes = recipes, disposition = disposition}
    end
  end
  local count = 0
  for _, candidate in ipairs(candidates) do
    local row, recipes, disposition = candidate.row, candidate.recipes, candidate.disposition
    if row_counts[row.technology_id] == 1 and not known[row.technology_id] then
      count = count + 1
      if count > M.catalogue_limit then break end
      known[row.technology_id] = true
      local detail = detail_for_row(row, recipes, disposition, policies, force)
      if detail then
        if detail.effective_cap then caps[row.technology_id] = detail.effective_cap end
        families[row.technology_id] = row.stream_id
        details[row.technology_id] = detail
      end
    end
  end
  return {schema = M.schema, kind = "portable-research-enrichment", caps = caps, families = families, details = details}
end

return M

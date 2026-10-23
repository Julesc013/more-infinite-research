-- Construction for the explicit F210 modern catalogue. The compatibility
-- module selects its bounded definitions; this module only builds fresh native
-- tables and checks the named three-recipe Space Age patch boundary.
local catalogue = require("compatibility.modern_catalogue")
local productivity = require("research.productivity")
local cost = require("research.cost")

local M = {}

local OVERLAY_SIZE = 128

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR modern research definition contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function number_text(value)
  assert(finite(value) and value >= 0, "MIR invalid modern research number")
  if value == math.floor(value) then return tostring(math.floor(value)) end
  return string.format("%.15g", value)
end

local function append_unique(out, seen, names)
  for index = 1, #names do
    local name = names[index]
    if not seen[name] then out[#out + 1], seen[name] = name, true end
  end
end

local function generated_prerequisites(definition)
  local out, seen = {}, {}
  append_unique(out, seen, catalogue.science_names(definition.science))
  append_unique(out, seen, definition.prerequisites or {})
  return out
end

local function continuation_prerequisites(definition)
  local out, seen = {}, {}
  append_unique(out, seen, definition.prerequisites or {})
  append_unique(out, seen, catalogue.science_names(definition.science))
  return out
end

local function icons(definition)
  if definition.icons then return copy(definition.icons) end
  return {
    {icon = definition.icon, icon_size = definition.icon_size or 256},
    {icon = definition.overlay, icon_size = OVERLAY_SIZE, scale = 0.5, shift = {50, 50}, floating = true}
  }
end

local function normal_effects(definition, values, options)
  local out = {}
  local automatic = definition.automatic_recipe_targets == nil
    or require("compatibility.automatic_productivity").applies(options)
  for index = 1, #definition.effects do
    local effect = definition.effects[index]
    if automatic or not definition.automatic_recipe_targets[effect.recipe] then
      if definition.kind == "productivity" then
        out[#out + 1] = {type = "change-recipe-productivity", recipe = effect.recipe,
          change = values.effect_percent * effect.scale / 100}
      else
        local result = {type = effect.type, modifier = values.effect_percent * effect.scale}
        if effect.ammo_category then result.ammo_category = effect.ammo_category end
        if not effect.raw then result.modifier = result.modifier / 100 end
        out[#out + 1] = result
      end
    end
  end
  return out
end

local function localized(value)
  if type(value) == "string" then return {value} end
  return copy(value)
end

local function require_stream(values, family)
  local stream = values and values.streams and values.streams[family]
  if type(stream) ~= "table" then error("MIR modern research has no resolved stream values for " .. family, 3) end
  return stream
end

function M.technology(definition, values)
  local stream = require_stream(values, definition.family)
  local output = {
    type = "technology", name = "recipe-prod-" .. definition.key .. "-1",
    icons = icons(definition), localised_name = copy(definition.localised_name),
    localised_description = copy(definition.localised_description), level = 1,
    upgrade = true, max_level = "infinite", order = definition.order,
    prerequisites = generated_prerequisites(definition), effects = normal_effects(definition, stream, values.options),
    unit = {
      count_formula = productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time, ingredients = catalogue.science_ingredients(definition.science)
    }
  }
  if stream.enabled == false or definition.available == false then output.enabled = false end
  return output
end

local function imersite_effect(stream)
  return {type = "change-recipe-productivity", recipe = "kr-imersite-powder", change = stream.effect_percent / 100}
end

local function imersite_continuation_formula(stream, first_level)
  local anchor = (stream.base_cost + (first_level - 1) * stream.linear_increment) * (stream.growth_factor ^ (first_level - 1))
  local head = number_text(anchor)
  if stream.base_cost == 0 then return head end
  return head .. "+" .. number_text(stream.base_cost) .. "*(L-" .. first_level .. ")"
end

-- K2SO's published Imersite stream has a finite public stage, an independent
-- late formula, and two hidden state carriers. It is a named historical shape,
-- not a generic finite-stage engine.
local function k2_imersite_technologies(values)
  local contract = require("research.k2_imersite")
  local stream = require_stream(values, contract.stream)
  local early_science = "science_automation_logistic_chemical_production"
  local continuation_science = "science_production_space"
  local effect = imersite_effect(stream)
  local early = {
    type = "technology", name = contract.early.id, icons = {
      {icon = "__Krastorio2Assets__/icons/items/imersite-powder.png", icon_size = 64},
      {icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png", icon_size = OVERLAY_SIZE,
        scale = 0.5, shift = {50, 50}, floating = true},
    }, localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name.kr-imersite-powder"}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    level = contract.early.first_level, upgrade = true, max_level = contract.early.last_level, order = contract.early.order,
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "kr-quarry-minerals-extraction"},
    effects = {effect}, unit = {count_formula = productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time, ingredients = catalogue.science_ingredients(early_science)},
  }
  local continuation = {
    type = "technology", name = contract.continuation.id, icons = icons({icon = "__Krastorio2Assets__/icons/items/imersite-powder.png", icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"}),
    localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name.kr-imersite-powder"}},
    localised_description = {"", {"technology-description.more-infinite-research.recipe_productivity"}, "\n",
      {"mod-setting-name.ips-max-level-stream", {"", {"description.productivity-bonus"}, ": ", {"item-name.kr-imersite-powder"}}}, ": ", "150"},
    level = contract.continuation.first_level, upgrade = true, max_level = "infinite", order = contract.continuation.order,
    show_levels_info = false, visible_when_disabled = true,
    prerequisites = {"kr-quarry-minerals-extraction", "production-science-pack", contract.early.id, "space-science-pack"},
    effects = {imersite_effect(stream)}, unit = {count_formula = imersite_continuation_formula(stream, contract.continuation.first_level),
      time = stream.research_time, ingredients = catalogue.science_ingredients(continuation_science)},
  }
  if stream.enabled == false then early.enabled, continuation.enabled = false, false end
  local carriers = {}
  for index, carrier in ipairs(contract.carriers) do
    local stage, science, formula = carrier.kind == "early" and contract.early or contract.continuation,
      carrier.kind == "early" and early_science or continuation_science,
      carrier.kind == "early" and productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor)
        or imersite_continuation_formula(stream, contract.continuation.first_level)
    carriers[index] = {
      type = "technology", name = carrier.id, icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
      localised_name = {"technology-name.more-infinite-research.recipe_productivity"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      level = stage.first_level, upgrade = false, hidden = true, enabled = true, max_level = "infinite",
      order = "zz[mir-migration-state]", prerequisites = {}, effects = {imersite_effect(stream)},
      unit = {count_formula = formula, time = stream.research_time, ingredients = catalogue.science_ingredients(science)},
    }
  end
  return {early, continuation, carriers[1], carriers[2]}
end

local function continuation_formula(definition, stream)
  local inheritance = definition.inheritance
  return cost.continuation(stream, definition.level, inheritance.last_count, inheritance.previous_count)
end

local function continuation_effects(definition, stream)
  local out = {}
  for index = 1, #definition.effects do
    local authored = definition.effects[index]
    local effect = {type = authored.type, modifier = stream.effect_percent * authored.scale / 100}
    if authored.ammo_category then effect.ammo_category = authored.ammo_category end
    -- Worker storage and the two inserter capacities are absolute values;
    -- their historical startup values are measured in units, not percent.
    if authored.type == "worker-robot-storage" or authored.type == "inserter-stack-size-bonus"
      or authored.type == "bulk-inserter-capacity-bonus" then
      effect.modifier = stream.effect_percent * authored.scale
    end
    out[index] = effect
  end
  return out
end

function M.continuation(definition, values)
  local stream = require_stream(values, definition.family)
  local time = stream.research_time
  if time == 0 then time = definition.inheritance.research_time end
  local output = {
    type = "technology", name = definition.id, icons = icons(definition),
    localised_name = localized(definition.localised_name), localised_description = localized(definition.localised_description),
    level = definition.level, upgrade = true, hidden = false, max_level = "infinite",
    prerequisites = continuation_prerequisites(definition), effects = continuation_effects(definition, stream),
    unit = {count_formula = continuation_formula(definition, stream), time = time,
      ingredients = catalogue.science_ingredients(definition.science)}
  }
  if stream.enabled == false then output.enabled = false end
  return output
end

function M.technologies(selection, values)
  if type(selection) ~= "table" then error("MIR modern selection is required", 2) end
  local out = {}
  for index = 1, #selection.definitions do out[#out + 1] = M.technology(selection.definitions[index], values) end
  for index = 1, #selection.continuations do out[#out + 1] = M.continuation(selection.continuations[index], values) end
  if selection.k2_imersite then
    local staged = k2_imersite_technologies(values)
    for index = 1, #staged do out[#out + 1] = staged[index] end
  end
  return out
end

local function owner_error(definition, reason)
  error("MIR native-owner preflight " .. definition.id .. ": " .. reason, 3)
end

local function configured(stream, field)
  return type(stream.configured) == "table" and stream.configured[field] == true
end

local function planned_owner_change(stream)
  if stream.enabled ~= true then return false end
  return configured(stream, "base_cost") or configured(stream, "linear_increment")
    or configured(stream, "growth_factor") or configured(stream, "effect_percent")
    or (configured(stream, "research_time") and stream.research_time > 0)
end

local function named_owner_effects(owner, definition)
  local expected, admission = definition.expected, definition.admission
  if type(owner.effects) ~= "table" then owner_error(definition, "missing effects") end
  local found = {}
  for index = 1, #admission.recipes do found[admission.recipes[index]] = 0 end
  for _, effect in ipairs(owner.effects) do
    if effect.type == admission.effect_type and found[effect.recipe] ~= nil then
      if effect.change ~= expected.effect_change then
        owner_error(definition, "unexpected effect change for " .. effect.recipe)
      end
      found[effect.recipe] = found[effect.recipe] + 1
    end
  end
  for index = 1, #admission.recipes do
    local recipe = admission.recipes[index]
    if found[recipe] ~= 1 then owner_error(definition, "missing or duplicate effect for " .. recipe) end
  end
end

local function preflight_owner(owner, definition)
  local expected = definition.expected
  if type(owner) ~= "table" then owner_error(definition, "missing technology") end
  if owner.enabled ~= expected.enabled then owner_error(definition, "unexpected enabled state") end
  if owner.max_level ~= expected.max_level then owner_error(definition, "unexpected max level") end
  if type(owner.unit) ~= "table" then owner_error(definition, "missing unit") end
  if owner.unit.count ~= nil or owner.unit.count_formula ~= expected.count_formula then
    owner_error(definition, "unexpected count formula")
  end
  if owner.unit.time ~= expected.research_time then owner_error(definition, "unexpected research time") end
  named_owner_effects(owner, definition)
end

local function owner_unit_plan(owner, definition, stream)
  local expected = definition.expected
  local cost_changed = configured(stream, "base_cost") or configured(stream, "linear_increment")
    or configured(stream, "growth_factor")
  local time_changed = configured(stream, "research_time") and stream.research_time > 0
  if not cost_changed and not time_changed then return nil end
  local unit = copy(owner.unit)
  if cost_changed then
    -- Published native-owner binding treats the cost controls as one tuple:
    -- when any member changes, all three effective setting values take over.
    unit.count, unit.count_formula = nil,
      productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor)
  end
  if time_changed then unit.time = stream.research_time end
  return unit
end

local function owner_effect_plan(owner, definition, stream)
  if not configured(stream, "effect_percent") then return nil end
  local effects, replacement = copy(owner.effects), stream.effect_percent / 100
  local admitted = {}
  for index = 1, #definition.admission.recipes do admitted[definition.admission.recipes[index]] = true end
  for _, effect in ipairs(effects) do
    if effect.type == definition.admission.effect_type and admitted[effect.recipe] then effect.change = replacement end
  end
  return effects
end

-- Native owners are established technology prototypes. This bounded path only
-- plans changes for enabled, non-default streams, checks every owned field of
-- each named owner before the first assignment, and leaves unrelated effects
-- and unit fields in place.
function M.preflight_native_owner_patches(selection, raw, values)
  if type(selection) ~= "table" or type(raw) ~= "table" or type(raw.technology) ~= "table" then
    error("MIR native-owner preflight requires data.raw.technology", 2)
  end
  local patches = {}
  for index = 1, #selection.native_owners do
    local definition = selection.native_owners[index]
    local stream = require_stream(values, definition.family)
    if planned_owner_change(stream) then
      local owner = raw.technology[definition.id]
      preflight_owner(owner, definition)
      patches[#patches + 1] = {
        owner = owner,
        unit = owner_unit_plan(owner, definition, stream),
        effects = owner_effect_plan(owner, definition, stream),
      }
    end
  end
  return patches
end

function M.apply_native_owner_patches(patches)
  if type(patches) ~= "table" then error("MIR native-owner patches are required", 2) end
  for index = 1, #patches do
    local patch = patches[index]
    if patch.unit then patch.owner.unit = patch.unit end
    if patch.effects then patch.owner.effects = patch.effects end
  end
end

local weapon_speed_option = "mir-adjust-vanilla-weapon-speed-techs"
local weapon_overlap_families = {
  research_cannon_shooting_speed = true,
  research_electric_shooting_speed = true,
  research_flamethrower_shooting_speed = true,
  research_rocket_shooting_speed = true,
}

local function positive_weapon_categories(selection, outputs, values)
  local generated, categories = {}, {}
  for index = 1, #outputs do generated[outputs[index].name] = outputs[index] end
  for index = 1, #selection.definitions do
    local definition = selection.definitions[index]
    local stream = require_stream(values, definition.family)
    local technology = generated["recipe-prod-" .. definition.key .. "-1"]
    if weapon_overlap_families[definition.family] and stream.enabled == true and technology and technology.enabled ~= false then
      for _, effect in ipairs(technology.effects) do
        if effect.type == "gun-speed" and type(effect.ammo_category) == "string"
          and finite(effect.modifier) and effect.modifier > 0 then
          categories[effect.ammo_category] = true
        end
      end
    end
  end
  return categories
end

-- This intentionally operates only on the one authored continuation we just
-- constructed. It has no data.raw scan and never removes an existing paid
-- category unless an enabled, positive direct MIR replacement is present.
function M.apply_weapon_speed_overlap(selection, outputs, values)
  local options = values and values.options or {}
  local mode = options[weapon_speed_option]
  if mode == nil then mode = "only-when-dedicated-tech-enabled" end
  if mode == "off" then return end
  if mode ~= "only-when-dedicated-tech-enabled" and mode ~= "always" then
    error("MIR invalid weapon-speed overlap mode", 2)
  end
  local categories = positive_weapon_categories(selection, outputs, values)
  if next(categories) == nil then return end
  for index = 1, #outputs do
    local technology = outputs[index]
    if technology.name == "weapon-shooting-speed-7" then
      local retained = {}
      for effect_index = 1, #technology.effects do
        local effect = technology.effects[effect_index]
        if not (effect.type == "gun-speed" and categories[effect.ammo_category]) then
          retained[#retained + 1] = effect
        end
      end
      technology.effects = retained
      return
    end
  end
end

function M.preflight_recipe_patches(selection, raw)
  if type(selection) ~= "table" or type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR modern recipe patch preflight requires data.raw.recipe", 2)
  end
  for index = 1, #selection.recipe_patches do
    local name = selection.recipe_patches[index]
    local recipe = raw.recipe[name]
    if type(recipe) ~= "table" then error("MIR modern catalogue missing required recipe " .. name, 2) end
  end
end

function M.apply_recipe_patches(selection, raw)
  M.preflight_recipe_patches(selection, raw)
  for index = 1, #selection.recipe_patches do raw.recipe[selection.recipe_patches[index]].allow_productivity = true end
end

return M

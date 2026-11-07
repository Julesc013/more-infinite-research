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
  if definition.exact_prerequisites then return copy(definition.prerequisites or {}) end
  local out, seen = {}, {}
  append_unique(out, seen, catalogue.science_names(definition.science))
  append_unique(out, seen, definition.prerequisites or {})
  return out
end

local function continuation_prerequisites(definition)
  if definition.exact_prerequisites then return copy(definition.prerequisites or {}) end
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
  local time = stream.research_time
  -- Zero inherits a native owner's time. This separate MIR identity keeps
  -- its authored default rather than publishing that sentinel to Factorio.
  if time == 0 then time = definition.tuning and definition.tuning.research_time end
  local output = {
    type = "technology", name = "recipe-prod-" .. definition.key .. "-1",
    icons = icons(definition), localised_name = copy(definition.localised_name),
    localised_description = copy(definition.localised_description), level = 1,
    upgrade = true, max_level = "infinite", order = definition.order,
    prerequisites = generated_prerequisites(definition), effects = normal_effects(definition, stream, values.options),
    unit = {
      count_formula = productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = time, ingredients = catalogue.science_ingredients(definition.science)
    }
  }
  if stream.enabled == false or definition.available == false then output.enabled = false end
  if (stream.max_level or 0) > 0 then
    productivity.apply_cap_presentation(output, stream.max_level, "mod-setting-name.ips-max-level-stream")
  end
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
local function imersite_state_carriers(stream, legacy)
  local contract, carriers = require("research.k2_imersite"), {}
  for index, carrier in ipairs(contract.carriers) do
    local early = carrier.kind == "early"
    local stage = early and contract.early or contract.continuation
    local formula = early and productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor)
      or imersite_continuation_formula(stream, contract.continuation.first_level)
    local science = early and "science_automation_logistic_chemical_production" or "science_production_space"
    carriers[index] = {
      type = "technology", name = carrier.id,
      icon = "__base__/graphics/technology/automation-1.png",
      icon_size = 256,
      localised_name = {"technology-name.more-infinite-research.recipe_productivity"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      level = stage.first_level, upgrade = false, hidden = true, enabled = true, max_level = "infinite",
      order = "zz[mir-migration-state]", prerequisites = {}, effects = {imersite_effect(stream)},
      unit = {count_formula = formula, time = stream.research_time,
        ingredients = legacy and {{"automation-science-pack", 1}} or catalogue.science_ingredients(science)},
    }
  end
  return carriers
end

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
  local carriers = imersite_state_carriers(stream, false)
  return {early, continuation, carriers[1], carriers[2]}
end

local function continuation_formula(definition, stream)
  local inheritance = definition.inheritance
  return cost.continuation(stream, definition.level, inheritance.last_count, inheritance.previous_count)
end

local function continuation_effects(definition, stream)
  if definition.inherited_research_speed_effects then
    local effects = copy(definition.inherited_research_speed_effects)
    for _, effect in ipairs(effects) do
      if effect.type == "laboratory-speed" then
        effect.modifier = effect.modifier * (stream.effect_percent / 60)
      end
    end
    return effects
  end
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
  if definition.order ~= nil and (type(definition.order) ~= "string" or definition.order == "") then
    error("MIR continuation order is invalid", 2)
  end
  if definition.icon_size ~= nil and (not finite(definition.icon_size) or definition.icon_size <= 0
      or definition.icon_size ~= math.floor(definition.icon_size)) then
    error("MIR continuation icon size is invalid", 2)
  end
  local output = {
    type = "technology", name = definition.id, icons = icons(definition),
    localised_name = localized(definition.localised_name), localised_description = localized(definition.localised_description),
    level = definition.level, upgrade = true, hidden = false, max_level = "infinite", order = definition.order,
    prerequisites = continuation_prerequisites(definition), effects = continuation_effects(definition, stream),
    unit = {count_formula = continuation_formula(definition, stream), time = time,
      ingredients = definition.ingredients and copy(definition.ingredients)
        or catalogue.science_ingredients(definition.science, definition.science_amounts)}
  }
  if definition.icon_size ~= nil then output.icon_size = definition.icon_size end
  if stream.enabled == false then output.enabled = false end
  if (stream.max_level or 0) > 0 then
    productivity.apply_cap_presentation(output, stream.max_level, "mod-setting-name.mir-max-level")
  end
  return output
end

function M.technologies(selection, values)
  if type(selection) ~= "table" then error("MIR modern selection is required", 2) end
  local out = {}
  for index = 1, #selection.definitions do out[#out + 1] = M.technology(selection.definitions[index], values) end
  for index = 1, #selection.continuations do out[#out + 1] = M.continuation(selection.continuations[index], values) end
  for _, definition in ipairs(selection.sif_retained or {}) do
    local retained = M.technology(definition, values)
    -- Hidden only: keep native levels/effects and an existing queue entry,
    -- without a new public research route or runtime cap owner.
    retained.hidden = true
    out[#out + 1] = retained
  end
  for _, definition in ipairs(selection.native_paid or {}) do
    local retained = M.technology(definition, values)
    retained.hidden, retained.effects = true, {}
    out[#out + 1] = retained
  end
  if selection.k2_imersite then
    local staged = k2_imersite_technologies(values)
    for index = 1, #staged do out[#out + 1] = staged[index] end
  elseif selection.k2_imersite_carriers then
    local carriers = imersite_state_carriers(require_stream(values, "research_material_imersite"), true)
    for index = 1, #carriers do out[#out + 1] = carriers[index] end
  end
  local material_definitions = selection.angel_materials
  if selection.bob_angel_f210_materials and #selection.bob_angel_f210_materials > 0 then
    if material_definitions and #material_definitions > 0 then
      error("MIR combined Bob/Angel cannot compose pure Angel material stages", 2)
    end
    material_definitions = selection.bob_angel_f210_materials
  end
  if material_definitions and #material_definitions > 0 then
    local stages = require("research.material_stages")
    for _, definition in ipairs(material_definitions) do
      local stream = require_stream(values, definition.key)
      for _, stage in ipairs({definition.early, definition.continuation}) do
        local technology = stages.technology(definition, stage, stream,
          function(message) error("MIR F210 material stage " .. message, 3) end)
        if stage.first_level then technology.localised_description = stages.continuation_description(definition, stream) end
        out[#out + 1] = technology
      end
    end
  end
  return out
end

local function owner_error(definition, reason)
  error("MIR native-owner preflight " .. definition.id .. ": " .. reason, 3)
end

local function configured(stream, field)
  return type(stream.configured) == "table" and stream.configured[field] == true
end

local function planned_owner_change(stream, definition)
  if stream.enabled ~= true then return false end
  return definition.append_recipes ~= nil or configured(stream, "base_cost") or configured(stream, "linear_increment")
    or configured(stream, "growth_factor") or configured(stream, "effect_percent")
    or (configured(stream, "research_time") and stream.research_time > 0)
end

local function named_owner_effects(owner, definition, inherited_change)
  local expected, admission = definition.expected, definition.admission
  if type(owner.effects) ~= "table" then owner_error(definition, "missing effects") end
  local found = {}
  local appended = {}
  for _, recipe in ipairs(definition.append_recipes or {}) do appended[recipe] = true end
  for index = 1, #admission.recipes do found[admission.recipes[index]] = 0 end
  for _, effect in ipairs(owner.effects) do
    if effect.type == admission.effect_type and found[effect.recipe] ~= nil then
      if effect.change ~= (inherited_change or expected.effect_change) then
        owner_error(definition, "unexpected effect change for " .. effect.recipe)
      end
      found[effect.recipe] = found[effect.recipe] + 1
    end
  end
  for index = 1, #admission.recipes do
    local recipe = admission.recipes[index]
    local expected_count = appended[recipe] and 0 or 1
    if found[recipe] ~= expected_count then owner_error(definition, "missing or duplicate effect for " .. recipe) end
  end
end

local function preflight_owner(owner, definition, stream)
  local expected = definition.expected
  if type(owner) ~= "table" then owner_error(definition, "missing technology") end
  if owner.enabled ~= expected.enabled then owner_error(definition, "unexpected enabled state") end
  if owner.max_level ~= expected.max_level then owner_error(definition, "unexpected max level") end
  if type(owner.unit) ~= "table" then owner_error(definition, "missing unit") end
  local cost_changed = configured(stream, "base_cost") or configured(stream, "linear_increment")
    or configured(stream, "growth_factor")
  local cost_style
  local withheld = false
  if cost_changed then
    -- Preserve the delivered bounded family admission instead of requiring
    -- one Base balance literal. Inherited/effect/time-only paths stay lazy.
    if owner.unit.count ~= nil and (owner.unit.count_formula ~= nil or not finite(owner.unit.count)
        or owner.unit.count <= 0 or owner.unit.count % 1 ~= 0) then
      owner_error(definition, "invalid inherited count")
    end
    if owner.unit.count == nil and (type(owner.unit.count_formula) ~= "string"
        or not owner.unit.count_formula:find("%S")) then
      owner_error(definition, "missing inherited cost")
    end
    cost_style = require("compatibility.native_owner_cost").classify(owner.unit)
    if cost_style == nil then
      -- The old binding withheld the entire patch when a requested cost
      -- override could not classify this upstream expression. Preserve it;
      -- only these five authored native families have a fallback policy.
      for _, binding in ipairs(require("compatibility.product_bindings").native_owner_bindings) do
        if definition.id == binding.owner and definition.family == binding.family then withheld = true; break end
      end
      if not withheld then owner_error(definition, "unexpected count formula") end
    end
  elseif owner.unit.count ~= nil then
    if owner.unit.count_formula ~= nil or not finite(owner.unit.count)
        or owner.unit.count <= 0 or owner.unit.count % 1 ~= 0 then
      owner_error(definition, "invalid inherited count")
    end
  elseif type(owner.unit.count_formula) ~= "string" or not owner.unit.count_formula:find("%S") then
    owner_error(definition, "missing inherited cost")
  end
  if not finite(owner.unit.time) or owner.unit.time < 0 then
    owner_error(definition, "invalid inherited research time")
  end
  named_owner_effects(owner, definition)
  return cost_style, withheld
end

local function owner_unit_plan(owner, definition, stream, cost_style)
  local expected = definition.expected
  local cost_changed = configured(stream, "base_cost") or configured(stream, "linear_increment")
    or configured(stream, "growth_factor")
  local time_changed = configured(stream, "research_time") and stream.research_time > 0
  if not cost_changed and not time_changed then return nil end
  local unit = copy(owner.unit)
  if cost_changed then
    -- Published native-owner binding treats the cost controls as one tuple:
    -- when any member changes, all three effective setting values take over.
    if cost_style == "fixed-count" and stream.linear_increment == 0 and stream.growth_factor == 1 then
      unit.count, unit.count_formula = stream.base_cost, nil
    else
      unit.count, unit.count_formula = nil,
        productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor)
    end
  end
  if time_changed then unit.time = stream.research_time end
  return unit
end

local function owner_effect_plan(owner, definition, stream)
  local configured_effect = configured(stream, "effect_percent")
  if not configured_effect and definition.append_recipes == nil then return nil end
  local effects = copy(owner.effects)
  local replacement = configured_effect and stream.effect_percent / 100 or definition.expected.effect_change
  local admitted = {}
  for index = 1, #definition.admission.recipes do admitted[definition.admission.recipes[index]] = true end
  for _, effect in ipairs(effects) do
    if effect.type == definition.admission.effect_type and admitted[effect.recipe] then effect.change = replacement end
  end
  for _, recipe in ipairs(definition.append_recipes or {}) do
    effects[#effects + 1] = {type=definition.admission.effect_type, recipe=recipe, change=replacement}
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
  local patches, withheld = {}, {}
  if selection.sif_retained then
    require("compatibility.modern_catalogue.sif_retained").preflight(selection.sif_retained, raw, selection.native_owners)
  end
  for index = 1, #selection.native_owners do
    local definition = selection.native_owners[index]
    local stream = require_stream(values, definition.family)
    if planned_owner_change(stream, definition) then
      local owner = raw.technology[definition.id]
      local cost_style, unbound = preflight_owner(owner, definition, stream)
      if unbound then
        withheld[definition.id] = {family=definition.family, generated=false}
      else
        patches[#patches + 1] = {
          owner = owner,
          unit = owner_unit_plan(owner, definition, stream, cost_style),
          effects = owner_effect_plan(owner, definition, stream),
        }
      end
    end
  end
  return patches, withheld
end

-- Detached effects for only the five authored Space Age native families.
-- They share the ordinary product collector; none is submitted to creation.
function M.native_owner_product_targets(selection, raw, values, patches, active_mods, withheld)
  local out = {}
  if not (active_mods and active_mods["space-age"]) then return out end
  local definitions, existing, generated = {}, {}, {}
  for _, definition in ipairs(selection.native_owners) do definitions[definition.family] = definition end
  for _, definition in ipairs(selection.definitions) do generated[definition.family] = true end
  for _, patch in ipairs(patches) do existing[patch.owner] = patch end
  for _, binding in ipairs(require("compatibility.product_bindings").native_owner_bindings) do
    local definition = definitions[binding.family]
    -- An explicit overhaul may retain a generated owner for this family.
    -- Its authored recipe policy takes precedence over ordinary native adoption.
    if definition and definition.id == binding.owner and not generated[binding.family] then
      local stream = require_stream(values, binding.family)
      local owner = raw.technology[definition.id]
      local patch = owner and existing[owner]
      local effects = patch and patch.effects
      if effects == nil then effects = copy(type(owner) == "table" and type(owner.effects) == "table" and owner.effects or {}) end
      out[#out + 1] = {family=binding.family, definition=definition, owner=owner,
        effects=effects, patch=patch, active=stream.enabled == true and not (withheld and withheld[definition.id]),
        configured_effect=configured(stream, "effect_percent")}
    end
  end
  return out
end

function M.preflight_collected_native_owner_targets(targets, patches)
  for _, row in ipairs(targets or {}) do
    if row.extended then
      local definition, owner = row.definition, row.owner
      if type(owner) ~= "table" then owner_error(definition, "missing technology") end
      if owner.max_level ~= "infinite" then owner_error(definition, "native productivity owner is not infinite") end
      if owner.enabled == false then owner_error(definition, "native productivity owner is disabled") end
      -- Only effects are being appended here. Default inherited unit, flags,
      -- prerequisites and unrelated effects retain their upstream values.
      named_owner_effects(owner, definition, not row.patch and row.effect_change or nil)
      if row.patch then row.patch.effects = row.effects
      else patches[#patches + 1] = {owner=owner, effects=row.effects} end
    end
  end
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
    if technology.name == "weapon-shooting-speed-7" or technology.name == "weapon-shooting-speed-9" then
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

-- Only owners already admitted for the two authored shared weapon tails can
-- withhold a dedicated stream here. The sole authored electric/tesla pair
-- preserves paid categories through explicit native holders; other wholly
-- covered streams retain their complete earned vector and stop future work.
function M.retain_external_weapon_coverage(selection, outputs, science_context)
  local covered = {}
  for name, owner in pairs(selection.external_continuations or {}) do
    if (name == "weapon-shooting-speed-7" or name == "laser-shooting-speed-8")
        and require("research.science").existing_research_inputs_supported(owner, science_context) then
      local totals, valid = {}, true
      for _, effect in ipairs(owner.effects) do
        if effect.type == "gun-speed" and type(effect.ammo_category) == "string" then
          if not finite(effect.modifier) then valid = false; break end
          totals[effect.ammo_category] = (totals[effect.ammo_category] or 0) + effect.modifier
        end
      end
      if valid then
        for category, value in pairs(totals) do
          if finite(value) and value > 0 then covered[category] = true end
        end
      end
    end
  end
  local generated = {}
  for _, row in ipairs(outputs) do generated[row.name] = row end
  local electric_full
  for _, definition in ipairs(selection.definitions) do
    local row = generated["recipe-prod-" .. definition.key .. "-1"]
    if definition.family == "research_electric_shooting_speed" and row and #row.effects == 2
        and science_context.target.recipe_productivity == true
        and type(science_context.mods) == "table" and science_context.mods["space-age"] ~= nil then
      -- Keep the exact pre-selection vector and the shared resolved unit.
      -- The constructor detaches all four rows after science selection.
      electric_full = {type=row.type, name=row.name, effects=row.effects, unit=row.unit}
      local retained = {}
      for _, effect in ipairs(row.effects) do
        if not covered[effect.ammo_category] then retained[#retained + 1] = effect end
      end
      row.effects = retained
      if #retained == 0 then row.enabled = false end
    end
    if weapon_overlap_families[definition.family] and row and row.enabled ~= false then
      local fully_covered = #row.effects > 0
      for _, effect in ipairs(row.effects) do
        if effect.type ~= "gun-speed" or not finite(effect.modifier) or effect.modifier <= 0
            or not covered[effect.ammo_category] then fully_covered = false; break end
      end
      if fully_covered then row.enabled = false end
    end
  end
  return electric_full
end

local function preflight_patch_recipe_names(selection, raw)
  if type(selection) ~= "table" or type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR modern recipe patch preflight requires data.raw.recipe", 2)
  end
  for index = 1, #selection.recipe_patches do
    local name = selection.recipe_patches[index]
    if type(raw.recipe[name]) ~= "table" then error("MIR modern catalogue missing required recipe " .. name, 2) end
  end
end

function M.preflight_recipe_patches(selection, raw)
  preflight_patch_recipe_names(selection, raw)
  -- The exact Bob Core progression adds one named science route.  Keep its
  -- raw item/recipe/owner checks in this existing all-before-write preflight
  -- rather than exposing a general adapter callback mechanism.
  if selection.bob_core_progression ~= true and selection.bob_core_progression ~= false
      and selection.bob_core_progression ~= nil then
    error("MIR modern catalogue has invalid Bob Core progression selection", 2)
  end
  if selection.bob_tech_progression ~= nil then
    require("compatibility.modern_catalogue.bob_tech_progression").preflight(raw, selection.bob_tech_progression)
  elseif selection.bob_core_progression == true then
    require("compatibility.modern_catalogue.bob_core").preflight(raw)
  end
  if selection.angel_f210_profile ~= nil then
    require("compatibility.modern_catalogue.angel_f210").preflight(raw, selection.angel_f210_profile)
  end
  if selection.bob_angel_f210_profile ~= nil then
    require("compatibility.modern_catalogue.bob_angel_f210").preflight(raw, selection.bob_angel_f210_profile)
  end
  if selection.bob_angel_f200_combined ~= nil then
    require("compatibility.modern_catalogue.bob_angel_f200_combined").preflight(raw)
  end
end

function M.apply_recipe_patches(selection, raw)
  -- Owner/science admission precedes publication. At this point admitted
  -- native-owner patches may already have changed their owned fields.
  preflight_patch_recipe_names(selection, raw)
  for index = 1, #selection.recipe_patches do raw.recipe[selection.recipe_patches[index]].allow_productivity = true end
end

return M

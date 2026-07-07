
local C = require("prototypes.config")
local U = require("prototypes.util")
local D = require("prototypes.diagnostics")
local deepcopy = require("prototypes.lib.deepcopy")
local table_utils = require("prototypes.lib.table-utils")
local adoption_policy = require("prototypes.mir.policy.adoption_policy")
local owner_policy = require("prototypes.mir.policy.owner_policy")
local recipe_productivity_planner = require("prototypes.mir.capabilities.recipe_productivity.planner")
local direct_effects_planner = require("prototypes.mir.planner.direct_effects")
local native_modifiers = require("prototypes.mir.planner.native_modifiers")
local planner_requirements = require("prototypes.mir.planner.requirements")
local planner_science = require("prototypes.mir.planner.science")
local stream_emitter = require("prototypes.mir.legacy.stream_emitter")

local function lname(key, spec)
  if spec.localised_name then return spec.localised_name end
  local locale_key = "technology-name.more-infinite-research."..key
  local out = {locale_key}
  if spec.icon_item then
    table.insert(out, {"item-name."..spec.icon_item})
  elseif spec.icon_fluid then
    table.insert(out, {"fluid-name."..spec.icon_fluid})
  elseif spec.items and #spec.items == 1 then
    table.insert(out, {"item-name."..spec.items[1]})
  elseif spec.fluids and #spec.fluids == 1 then
    table.insert(out, {"fluid-name."..spec.fluids[1]})
  elseif spec.icon_tech then
    table.insert(out, {"technology-name."..spec.icon_tech})
  end
  return out
end

local function ldesc(spec)
  if spec.localised_description then return spec.localised_description end
  if spec.description_locale_key then return { spec.description_locale_key } end
  if spec.direct_effects then
    return {"technology-description.more-infinite-research.direct_effect"}
  end
  return {"technology-description.more-infinite-research.recipe_productivity"}
end

local function emit_stream_technology(key, spec, fields)
  return stream_emitter.emit(key, spec, fields)
end

local function append_unique_item(items, seen, item_name)
  if item_name and not seen[item_name] then
    seen[item_name] = true
    table.insert(items, item_name)
  end
end

local function expand_dynamic_items(spec)
  if not (spec and spec.dynamic_items_from_lab_inputs) then return spec end

  local out = deepcopy(spec)

  local base_group_items = {}
  for _, item_name in ipairs(out.items or {}) do
    table.insert(base_group_items, item_name)
  end

  if not out.groups then
    out.groups = {
      {
        change = C.shared.per_level_default,
        items = base_group_items
      }
    }
  end
  if not out.groups[1] then
    out.groups[1] = {
      change = C.shared.per_level_default,
      items = base_group_items
    }
  end
  out.groups[1].items = out.groups[1].items or {}

  local first_group_seen = {}
  for _, item_name in ipairs(out.groups[1].items) do
    first_group_seen[item_name] = true
  end
  for _, item_name in ipairs(base_group_items) do
    append_unique_item(out.groups[1].items, first_group_seen, item_name)
  end

  local seen = {}
  for _, item_name in ipairs(out.items or {}) do
    seen[item_name] = true
  end
  for _, group in ipairs(out.groups or {}) do
    for _, item_name in ipairs(group.items or {}) do
      seen[item_name] = true
    end
  end

  for _, item_name in ipairs(U.pack_list_all()) do
    append_unique_item(out.groups[1].items, seen, item_name)
  end

  return out
end

local function make_stream(key, raw_spec)
  if not U.enabled_for(key, raw_spec) then
    D.stream(D.stream_fields(key, raw_spec, "skipped", "disabled"))
    return
  end
  local missing = planner_requirements.missing_reason(key, raw_spec)
  if missing then
    log("[more-infinite-research] Skipping stream "..key.." because "..missing..".")
    D.stream(D.stream_fields(key, raw_spec, "skipped", missing))
    return
  end

  local spec = expand_dynamic_items(raw_spec)

  local base_cost = U.base_cost_for(key, spec)
  local growth_factor = U.growth_factor_for(key, spec)
  local max_level = U.max_level_for(key, spec)
  local count_formula = tostring(base_cost) .. " * " .. tostring(growth_factor) .. "^(L-1)"
  local research_time = U.research_time_for(key, spec)

  local direct_effects = nil
  if spec.direct_effects then
    direct_effects = direct_effects_planner.available_for_stream(key, spec)
    if #direct_effects == 0 then
      log("[more-infinite-research] Skipping stream "..key.." because no available direct effects remain.")
      D.stream(D.stream_fields(key, spec, "skipped", "no_available_direct_effects"))
      return
    end
  end

  local ingredients, lab_status = planner_science.ingredients_for_stream(key, spec)
  if not ingredients or #ingredients == 0 then
    log("[more-infinite-research] Skipping stream "..key.." because no valid lab-compatible science pack set was found.")
    D.stream(D.stream_fields(key, spec, "skipped", "no_lab_compatible_science", ingredients, nil, direct_effects, lab_status))
    return
  end
  if D.enabled() and spec and spec.science_packs then
    local names = {}
    for _, entry in ipairs(ingredients) do table.insert(names, entry.name or entry[1]) end
    log("[more-infinite-research] Science packs for "..key..": "..table.concat(names, ", "))
  end

  if direct_effects and #direct_effects > 0 then
    native_modifiers.record_overlaps(key, direct_effects)
    local prerequisites = U.build_prereqs_for(key, ingredients)
    local t = emit_stream_technology(key, spec, {
      localised_name = lname(key, spec),
      localised_description = ldesc(spec),
      icons = U.icons_for_stream(spec),
      effects = direct_effects,
      prerequisites = prerequisites,
      count_formula = count_formula,
      ingredients = ingredients,
      research_time = research_time,
      max_level = max_level,
    })
    D.stream(D.stream_fields(key, spec, "generated", "direct_effect", ingredients, prerequisites, direct_effects, lab_status))
    return
  end

  local buckets = recipe_productivity_planner.match_buckets(key, spec)
  local covered_by_existing
  buckets, covered_by_existing = owner_policy.filter_existing_recipe_productivity(key, spec, buckets)
  local adopted_effects, family_blocked, adoption_owner_name
  buckets, adopted_effects, family_blocked, adoption_owner_name = adoption_policy.adopt_recipe_productivity_family(key, spec, buckets)
  if adopted_effects and #adopted_effects > 0 then
    D.stream(D.stream_fields(key, spec, "adopted", "adopted_into_existing_productivity_family", ingredients, nil, adopted_effects, lab_status, {
      owners = adoption_owner_name,
      recipes = owner_policy.recipe_names_from_effects(adopted_effects)
    }))
  end
  local effects = recipe_productivity_planner.effects_from_buckets(key, buckets)
  if #effects == 0 then
    if adopted_effects and #adopted_effects > 0 then
      return
    end
    local reason = "no_matching_recipes"
    if covered_by_existing and #covered_by_existing > 0 then
      reason = "covered_by_existing_infinite_recipe_productivity"
    elseif family_blocked and #family_blocked > 0 then
      reason = family_blocked[1].reason
    end
    log("[more-infinite-research] Skipping stream "..key.." because "..reason..".")
    D.stream(D.stream_fields(key, spec, "skipped", reason, ingredients, nil, effects, lab_status))
    return
  end

  local prerequisites = U.build_prereqs_for(key, ingredients)
  local t = emit_stream_technology(key, spec, {
    localised_name = lname(key, spec),
    localised_description = ldesc(spec),
    icons = U.icons_for_stream(spec),
    effects = effects,
    prerequisites = prerequisites,
    count_formula = count_formula,
    ingredients = ingredients,
    research_time = research_time,
    max_level = max_level,
  })
  if D.enabled() then
    log("[more-infinite-research] Registered technology "..t.name)
  end
  D.stream(D.stream_fields(key, spec, "generated", "recipe_productivity", ingredients, prerequisites, effects, lab_status))
end

for _, key in ipairs(table_utils.sorted_keys(C.streams)) do
  make_stream(key, C.streams[key])
end

adoption_policy.emit_mod_data()

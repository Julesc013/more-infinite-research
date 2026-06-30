
local C = require("prototypes.config")
local U = require("prototypes.util")
local D = require("prototypes.diagnostics")
local deepcopy = require("prototypes.lib.deepcopy")
local table_utils = require("prototypes.lib.table-utils")

local function lname(key, spec)
  if spec.localised_name then return spec.localised_name end
  local locale_key = "technology-name.more-infinite-research."..key
  local out = {locale_key}
  if spec.icon_item then
    table.insert(out, {"item-name."..spec.icon_item})
  elseif spec.items and #spec.items == 1 then
    table.insert(out, {"item-name."..spec.items[1]})
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

local function missing_requirement(key, spec)
  for _, mod_name in ipairs(spec.required_mods or {}) do
    if not U.mod_exists(mod_name) then
      return "missing required mod " .. mod_name
    end
  end
  for _, item_name in ipairs(spec.required_items or {}) do
    if not U.item_prototype(item_name) then
      return "missing required item " .. item_name
    end
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    if not U.technology_exists(tech_name) then
      return "missing required technology " .. tech_name
    end
  end
  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not U.ammo_category_exists(category) then
      return "missing required ammo category " .. category
    end
  end
  return nil
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

-- Direct-effect streams can outlive the prototype families they target when
-- optional mods are disabled, so filter effect rows before creating a tech.
local function available_direct_effects(key, effects)
  local out = {}
  for _, effect in ipairs(effects or {}) do
    if effect.type == "gun-speed" and effect.ammo_category and not U.ammo_category_exists(effect.ammo_category) then
      log("[more-infinite-research] Skipping unavailable gun-speed effect for "..key..": missing ammo category "..effect.ammo_category)
    else
      table.insert(out, effect)
    end
  end
  return out
end

local function make_stream(key, raw_spec)
  if not U.enabled_for(key, raw_spec) then
    D.stream(D.stream_fields(key, raw_spec, "skipped", "disabled"))
    return
  end
  local missing = missing_requirement(key, raw_spec)
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
    direct_effects = available_direct_effects(key, deepcopy(spec.direct_effects))
    if #direct_effects == 0 then
      log("[more-infinite-research] Skipping stream "..key.." because no available direct effects remain.")
      D.stream(D.stream_fields(key, spec, "skipped", "no_available_direct_effects"))
      return
    end
  end

  local ingredients, lab_status = U.best_lab_compatible_ingredients(U.pick_science_for_stream(spec, key), key)
  lab_status = lab_status or "full"
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
    local prerequisites = U.build_prereqs_for(key, ingredients)
    local t = {
      type = "technology",
      name = "recipe-prod-"..key.."-1",
      localised_name = lname(key, spec),
      localised_description = ldesc(spec),
      icons = U.icons_for_stream(spec),
      effects = direct_effects,
      prerequisites = prerequisites,
      unit = {
        count_formula = count_formula,
        ingredients = ingredients,
        time = research_time
      },
      upgrade = true,
      max_level = max_level,
      order = "p["..key.."]",
      level = 1
    }
    data:extend({t})
    D.stream(D.stream_fields(key, spec, "generated", "direct_effect", ingredients, prerequisites, direct_effects, lab_status))
    return
  end

  local buckets = U.recipes_for_stream(spec)
  D.recipe_matches(key, buckets)
  local effects = {}
  for _,b in ipairs(buckets) do
    for _,r in ipairs(b.recipes) do
      table.insert(effects, { type="change-recipe-productivity", recipe=r, change=b.change or C.shared.per_level_default })
      D.record_recipe_match(key, r)
    end
  end
  if #effects == 0 then
    log("[more-infinite-research] Skipping stream "..key.." because no matching recipes were found.")
    D.stream(D.stream_fields(key, spec, "skipped", "no_matching_recipes", ingredients, nil, effects, lab_status))
    return
  end

  local prerequisites = U.build_prereqs_for(key, ingredients)
  local t = {
    type = "technology",
    name = "recipe-prod-"..key.."-1",
    localised_name = lname(key, spec),
    localised_description = ldesc(spec),
    icons = U.icons_for_stream(spec),
    effects = effects,
    prerequisites = prerequisites,
    unit = {
      count_formula = count_formula,
      ingredients = ingredients,
      time = research_time
    },
    upgrade = true,
    max_level = max_level,
    order = "p["..key.."]",
    level = 1
  }
  data:extend({t})
  if D.enabled() then
    log("[more-infinite-research] Registered technology "..t.name)
  end
  D.stream(D.stream_fields(key, spec, "generated", "recipe_productivity", ingredients, prerequisites, effects, lab_status))
end

for _, key in ipairs(table_utils.sorted_keys(C.streams)) do
  make_stream(key, C.streams[key])
end

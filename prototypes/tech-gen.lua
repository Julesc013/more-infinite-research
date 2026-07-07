
local C = require("prototypes.config")
local U = require("prototypes.util")
local D = require("prototypes.diagnostics")
local deepcopy = require("prototypes.lib.deepcopy")
local table_utils = require("prototypes.lib.table-utils")
local effect_safety = require("prototypes.technology-effect-safety")
local competing_productivity = require("prototypes.compat.competing-productivity")
local productivity_owners = require("prototypes.compat.productivity-owners")
local productivity_family_adoption = require("prototypes.compat.productivity-family-adoption")
local native_modifiers = require("prototypes.mir.planner.native_modifiers")
local planner_requirements = require("prototypes.mir.planner.requirements")
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

-- Direct-effect streams can outlive the prototype families they target when
-- optional mods are disabled, so filter effect rows before creating a tech.
local function available_direct_effects(key, effects)
  local out = {}
  for _, effect in ipairs(effects or {}) do
    effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)
    if effect.type == "gun-speed" and effect.ammo_category and not U.ammo_category_exists(effect.ammo_category) then
      log("[more-infinite-research] Skipping unavailable gun-speed effect for "..key..": missing ammo category "..effect.ammo_category)
    else
      table.insert(out, effect)
    end
  end
  return out
end

local function existing_infinite_recipe_productivity_owner_records(recipe_name, spec)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  return productivity_owners.blocking_recipe_productivity_owner_records(recipe_name, {
    ignore_owner = competing_productivity.ignores_existing_owner,
    adoption_tech = adoption and adoption.tech
  })
end

local function filter_existing_recipe_productivity(key, spec, buckets)
  local filtered_buckets = {}
  local skipped = {}

  for _, bucket in ipairs(buckets or {}) do
    local recipes = {}
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      local owner_records = existing_infinite_recipe_productivity_owner_records(recipe_name, spec)
      if #owner_records > 0 then
        table.insert(skipped, {
          recipe = recipe_name,
          owners = productivity_owners.owner_names(owner_records),
          owner_kinds = productivity_owners.owner_kinds(owner_records),
          owner_actions = productivity_owners.owner_actions(owner_records)
        })
      else
        table.insert(recipes, recipe_name)
      end
    end
    if #recipes > 0 then
      table.insert(filtered_buckets, {
        change = bucket.change,
        recipes = recipes
      })
    end
  end

  for _, entry in ipairs(skipped) do
    D.recipe_owner({
      key = key,
      status = "skipped",
      reason = "covered_by_existing_infinite_recipe_productivity",
      recipe = entry.recipe,
      owners = entry.owners,
      owner_kinds = entry.owner_kinds,
      owner_actions = entry.owner_actions
    })
    log("[more-infinite-research] Skipping recipe productivity effect for "
      .. key .. " recipe=" .. entry.recipe
      .. " because existing infinite technology already owns it: "
      .. entry.owners)
  end

  return filtered_buckets, skipped
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
    direct_effects = available_direct_effects(key, deepcopy(spec.direct_effects))
    if #direct_effects == 0 then
      log("[more-infinite-research] Skipping stream "..key.." because no available direct effects remain.")
      D.stream(D.stream_fields(key, spec, "skipped", "no_available_direct_effects"))
      return
    end
    for _, effect in ipairs(direct_effects) do
      if effect.type == "nothing" and not effect.icon and not effect.icons then
        effect.icons = U.effect_icons_for_stream(spec)
      end
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

  local buckets = U.recipes_for_stream(spec)
  D.recipe_matches(key, buckets)
  local covered_by_existing
  buckets, covered_by_existing = filter_existing_recipe_productivity(key, spec, buckets)
  local adopted_effects, family_blocked, adoption_owner_name
  buckets, adopted_effects, family_blocked, adoption_owner_name = productivity_family_adoption.adopt(key, spec, buckets)
  if adopted_effects and #adopted_effects > 0 then
    D.stream(D.stream_fields(key, spec, "adopted", "adopted_into_existing_productivity_family", ingredients, nil, adopted_effects, lab_status, {
      owners = adoption_owner_name,
      recipes = productivity_owners.recipe_names_from_effects(adopted_effects)
    }))
  end
  local effects = {}
  for _,b in ipairs(buckets) do
    for _,r in ipairs(b.recipes) do
      table.insert(effects, { type="change-recipe-productivity", recipe=r, change=b.change or C.shared.per_level_default })
      D.record_recipe_match(key, r)
    end
  end
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

productivity_family_adoption.emit_mod_data()

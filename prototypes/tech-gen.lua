
local C = require("prototypes.config")
local U = require("prototypes.util")
local D = require("prototypes.diagnostics")
local deepcopy = require("prototypes.lib.deepcopy")
local table_utils = require("prototypes.lib.table-utils")
local effect_safety = require("prototypes.technology-effect-safety")

local PRODUCTIVITY_FAMILY_ADOPTION_MOD_DATA_NAME = "more-infinite-research-productivity-family-adoption"
local PRODUCTIVITY_FAMILY_ADOPTION_VERSION = 1
local adopted_productivity_family_recipes = {}

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
  for _, fluid_name in ipairs(spec.required_fluids or {}) do
    if not U.fluid_prototype(fluid_name) then
      return "missing required fluid " .. fluid_name
    end
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    if not U.technology_exists(tech_name) then
      return "missing required technology " .. tech_name
    end
  end
  for _, tech_name in ipairs(spec.skip_if_technologies or {}) do
    if U.technology_exists(tech_name) then
      return "existing technology " .. tech_name
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
    effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)
    if effect.type == "gun-speed" and effect.ammo_category and not U.ammo_category_exists(effect.ammo_category) then
      log("[more-infinite-research] Skipping unavailable gun-speed effect for "..key..": missing ammo category "..effect.ammo_category)
    else
      table.insert(out, effect)
    end
  end
  return out
end

local native_modifier_ignored_fields = {
  change = true,
  effect_description = true,
  icon = true,
  icons = true,
  modifier = true,
  type = true
}

local function native_modifier_identity(effect)
  if not effect or not effect.type then return nil end
  if effect.type == "nothing" or effect.type == "change-recipe-productivity" then return nil end

  local fields = {}
  for _, field in ipairs(table_utils.sorted_keys(effect)) do
    if not native_modifier_ignored_fields[field] then
      local value = effect[field]
      local value_type = type(value)
      if value_type == "string" or value_type == "number" or value_type == "boolean" then
        table.insert(fields, field .. "=" .. tostring(value))
      end
    end
  end

  local target = "global"
  if #fields > 0 then target = table.concat(fields, ",") end
  return effect.type .. "|" .. target, target
end

local function existing_infinite_native_modifier_techs(identity)
  local owners = {}
  if not identity then return owners end

  for tech_name, tech in pairs(data.raw.technology or {}) do
    if tech.max_level == "infinite" and not string.find(tech_name, "^recipe%-prod%-") then
      for _, effect in ipairs(tech.effects or {}) do
        local existing_identity = native_modifier_identity(effect)
        if existing_identity == identity then
          table.insert(owners, tech_name)
          break
        end
      end
    end
  end

  table.sort(owners)
  return owners
end

local function record_native_modifier_overlaps(key, effects)
  local seen = {}

  for _, effect in ipairs(effects or {}) do
    local identity, target = native_modifier_identity(effect)
    if identity and not seen[identity] then
      seen[identity] = true
      local owners = existing_infinite_native_modifier_techs(identity)
      if #owners > 0 then
        D.native_modifier_overlap({
          key = key,
          status = "diagnostic",
          reason = "existing_infinite_native_modifier",
          effect = effect.type,
          target = target,
          owners = table.concat(owners, ",")
        })
      end
    end
  end
end

local function existing_infinite_recipe_productivity_techs(recipe_name)
  local owners = {}
  for tech_name, tech in pairs(data.raw.technology or {}) do
    if tech.max_level == "infinite" and not string.find(tech_name, "^recipe%-prod%-") then
      for _, effect in ipairs(tech.effects or {}) do
        if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
          table.insert(owners, tech_name)
          break
        end
      end
    end
  end
  table.sort(owners)
  return owners
end

local function filter_existing_recipe_productivity(key, buckets)
  local filtered_buckets = {}
  local skipped = {}

  for _, bucket in ipairs(buckets or {}) do
    local recipes = {}
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      local owners = existing_infinite_recipe_productivity_techs(recipe_name)
      if #owners > 0 then
        table.insert(skipped, {
          recipe = recipe_name,
          owners = owners
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
    log("[more-infinite-research] Skipping recipe productivity effect for "
      .. key .. " recipe=" .. entry.recipe
      .. " because existing infinite technology already owns it: "
      .. table.concat(entry.owners, ","))
  end

  return filtered_buckets, skipped
end

local function recipe_productivity_effects(tech)
  local effects = {}
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe then
      table.insert(effects, effect)
    end
  end
  return effects
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function recipe_allows_productivity(recipe_name)
  local recipe = (data.raw.recipe or {})[recipe_name]
  if not recipe then return false end

  local function explicit_allow(def)
    if def and def.allow_productivity ~= nil then
      return def.allow_productivity == true
    end
    return nil
  end

  local normal = explicit_allow(recipe.normal)
  local expensive = explicit_allow(recipe.expensive)
  if normal == true or expensive == true then return true end
  if normal == false or expensive == false then return false end
  return recipe.allow_productivity == true
end

local function recipe_outputs_family_product(recipe_name, products)
  if not products then return true end

  local wanted = {}
  for _, product in ipairs(products) do wanted[product] = true end
  local recipe = (data.raw.recipe or {})[recipe_name]
  if not recipe then return false end

  local function product_name(product)
    if not product then return nil end
    if type(product) == "string" then return product end
    return product.name or product[1]
  end

  local function scan(def)
    if not def then return false end
    if def.results then
      for _, product in pairs(def.results) do
        local name = product_name(product)
        if name and wanted[name] then return true end
      end
    elseif def.result and wanted[def.result] then
      return true
    end
    return false
  end

  if recipe.normal or recipe.expensive then
    return scan(recipe.normal) or scan(recipe.expensive)
  end
  return scan(recipe)
end

local function append_recipe_to_bucket(out, bucket, recipe_name)
  local target = out[#out]
  if not target or target.change ~= bucket.change then
    target = {change = bucket.change, recipes = {}}
    table.insert(out, target)
  end
  table.insert(target.recipes, recipe_name)
end

local function partition_family_adoption_candidates(key, spec, buckets)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  if not adoption then return buckets, {} end

  local eligible_buckets = {}
  local blocked = {}

  for _, bucket in ipairs(buckets or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      local reason = nil
      if not recipe_allows_productivity(recipe_name) then
        reason = "recipe_productivity_not_allowed"
      elseif not recipe_outputs_family_product(recipe_name, adoption.products) then
        reason = "recipe_not_in_configured_family_products"
      end

      if reason then
        table.insert(blocked, {
          recipe = recipe_name,
          reason = reason
        })
      else
        append_recipe_to_bucket(eligible_buckets, bucket, recipe_name)
      end
    end
  end

  for _, entry in ipairs(blocked) do
    log("[more-infinite-research] Skipping configured productivity-family candidate for "
      .. key .. " recipe=" .. entry.recipe .. " because " .. entry.reason .. ".")
  end

  return eligible_buckets, blocked
end

local function adoption_owner_for(spec)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  if not (adoption and adoption.tech) then return nil, "no_configured_owner" end

  local owner_name = adoption.tech
  local owner = data.raw.technology and data.raw.technology[owner_name]
  if not owner then return nil, "owner_missing" end
  if adoption.require_infinite ~= false and owner.max_level ~= "infinite" then
    return nil, "owner_not_infinite"
  end

  local owner_effects = recipe_productivity_effects(owner)
  if adoption.require_existing_recipe_productivity_effects ~= false and #owner_effects == 0 then
    return nil, "owner_has_no_recipe_productivity_effects"
  end

  local change_policy = adoption.change_policy or "copy-owner"
  local change = C.shared.per_level_default
  if change_policy == "copy-owner" then
    change = nil
    for _, effect in ipairs(owner_effects) do
      if effect.change == nil then
        return nil, "owner_missing_change_value"
      end
      if change == nil then
        change = effect.change
      elseif effect.change ~= change then
        return nil, "owner_mixed_change_values"
      end
    end
    if change == nil then return nil, "owner_has_no_recipe_productivity_effects" end
  end

  return {
    name = owner_name,
    tech = owner,
    change = change
  }
end

local function record_productivity_family_adoption(key, owner_name, recipe_name, change)
  table.insert(adopted_productivity_family_recipes, {
    key = key,
    owner = owner_name,
    recipe = recipe_name,
    change = change
  })
end

local function adopt_productivity_family_recipes(key, spec, buckets)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  if not adoption then return buckets, {}, {} end

  local eligible_buckets, blocked = partition_family_adoption_candidates(key, spec, buckets)
  local owner, reason = adoption_owner_for(spec)
  if not owner then
    if #eligible_buckets > 0 or #blocked > 0 then
      log("[more-infinite-research] Could not adopt productivity-family recipes for "
        .. key .. " into "
        .. tostring(adoption.tech)
        .. " because "
        .. tostring(reason)
        .. "; falling back to MIR generation for eligible recipes.")
    end
    return eligible_buckets, {}, blocked
  end

  local adopted = {}
  for _, bucket in ipairs(eligible_buckets or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      if not has_recipe_productivity_effect(owner.tech, recipe_name) then
        local effect = {
          type = "change-recipe-productivity",
          recipe = recipe_name,
          change = owner.change
        }
        owner.tech.effects = owner.tech.effects or {}
        table.insert(owner.tech.effects, effect)
        table.insert(adopted, effect)
        record_productivity_family_adoption(key, owner.name, recipe_name, owner.change)
        log("[more-infinite-research] Adopted productivity-family recipe for "
          .. key .. " recipe=" .. recipe_name .. " into " .. owner.name .. ".")
      end
    end
  end

  return {}, adopted, blocked, owner.name
end

local function recipe_names_from_effects(effects)
  local names = {}
  for _, effect in ipairs(effects or {}) do
    if effect.recipe then table.insert(names, effect.recipe) end
  end
  table.sort(names)
  return table.concat(names, ",")
end

local function productivity_family_adoption_signature()
  local entries = {}
  for _, entry in ipairs(adopted_productivity_family_recipes) do
    table.insert(entries,
      "schema=" .. tostring(PRODUCTIVITY_FAMILY_ADOPTION_VERSION)
      .. "|owner=" .. tostring(entry.owner)
      .. "|recipe=" .. tostring(entry.recipe)
      .. "|change=" .. tostring(entry.change))
  end
  table.sort(entries)
  return table.concat(entries, ";")
end

local function emit_productivity_family_adoption_mod_data()
  local signature = productivity_family_adoption_signature()
  data:extend({
    {
      type = "mod-data",
      name = PRODUCTIVITY_FAMILY_ADOPTION_MOD_DATA_NAME,
      data_type = "more-infinite-research.productivity-family-adoption",
      data = {
        version = PRODUCTIVITY_FAMILY_ADOPTION_VERSION,
        adopted = #adopted_productivity_family_recipes > 0,
        adopted_count = #adopted_productivity_family_recipes,
        signature = signature
      }
    }
  })
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
    record_native_modifier_overlaps(key, direct_effects)
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
    effect_safety.register_generated_technology(t.name)
    D.stream(D.stream_fields(key, spec, "generated", "direct_effect", ingredients, prerequisites, direct_effects, lab_status))
    return
  end

  local buckets = U.recipes_for_stream(spec)
  D.recipe_matches(key, buckets)
  local covered_by_existing
  buckets, covered_by_existing = filter_existing_recipe_productivity(key, buckets)
  local adopted_effects, family_blocked, adoption_owner_name
  buckets, adopted_effects, family_blocked, adoption_owner_name = adopt_productivity_family_recipes(key, spec, buckets)
  if adopted_effects and #adopted_effects > 0 then
    D.stream(D.stream_fields(key, spec, "adopted", "adopted_into_existing_productivity_family", ingredients, nil, adopted_effects, lab_status, {
      owners = adoption_owner_name,
      recipes = recipe_names_from_effects(adopted_effects)
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
  effect_safety.register_generated_technology(t.name)
  if D.enabled() then
    log("[more-infinite-research] Registered technology "..t.name)
  end
  D.stream(D.stream_fields(key, spec, "generated", "recipe_productivity", ingredients, prerequisites, effects, lab_status))
end

for _, key in ipairs(table_utils.sorted_keys(C.streams)) do
  make_stream(key, C.streams[key])
end

emit_productivity_family_adoption_mod_data()

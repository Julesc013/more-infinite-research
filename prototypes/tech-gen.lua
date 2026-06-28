
local C = require("prototypes.config")
local U = require("prototypes.util")

local function deepcopy(value)
  if table.deepcopy then return table.deepcopy(value) end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do
      out[copy(k)] = copy(vv)
    end
    return out
  end
  return copy(value)
end

local function lname(key, spec)
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

local function missing_requirement(key, spec)
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

local function make_stream(key, spec)
  if not U.enabled_for(key, spec) then return end
  if spec.hide_in_space_age and U.is_space_age() then return end
  if spec.requires_space_age and not U.is_space_age() then return end
  local missing = missing_requirement(key, spec)
  if missing then
    log("[more-infinite-research] Skipping stream "..key.." because "..missing..".")
    return
  end

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
      return
    end
  end

  local ingredients = U.best_lab_compatible_ingredients(U.pick_science_for_stream(spec, key), key)
  if not ingredients or #ingredients == 0 then
    log("[more-infinite-research] Skipping stream "..key.." because no valid lab-compatible science pack set was found.")
    return
  end
  if spec and spec.science_packs then
    local names = {}
    for _, entry in ipairs(ingredients) do table.insert(names, entry[1]) end
    log("[more-infinite-research] Science packs for "..key..": "..table.concat(names, ", "))
  end

  if direct_effects and #direct_effects > 0 then
    local t = {
      type = "technology",
      name = "recipe-prod-"..key.."-1",
      localised_name = lname(key, spec),
      localised_description = {""},
      icons = U.icons_for_stream(spec),
      effects = direct_effects,
      prerequisites = U.build_prereqs_for(key, ingredients),
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
    if key == "research_rails" then
      t.icons = nil
      t.icon = "__base__/graphics/icons/rail.png"
      t.icon_size = 64
    end
    data:extend({t})
    return
  end

  local buckets = U.recipes_for_stream(spec)
  local effects = {}
  for _,b in ipairs(buckets) do
    for _,r in ipairs(b.recipes) do
      table.insert(effects, { type="change-recipe-productivity", recipe=r, change=b.change or C.shared.per_level_default })
    end
  end
  if #effects == 0 then
    log("[more-infinite-research] Skipping stream "..key.." because no matching recipes were found.")
    return
  end

  local t = {
    type = "technology",
    name = "recipe-prod-"..key.."-1",
    localised_name = lname(key, spec),
    localised_description = {""},
    icons = U.icons_for_stream(spec),
    effects = effects,
    prerequisites = U.build_prereqs_for(key, ingredients),
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
  if key == "research_rails" then
    t.icons = nil
    t.icon = "__base__/graphics/icons/rail.png"
    t.icon_size = 64
  end
  data:extend({t})
  log("[more-infinite-research] Registered technology "..t.name)
end

for key, spec in pairs(require("prototypes.config").streams) do
  make_stream(key, spec)
end

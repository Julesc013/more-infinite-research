-- Retained exact-version loader repairs. This is admitted override code, not
-- research selection or discovery; only these named recipes may be changed.
local M = {}
local repairs = {
  {name = "atan-ash", version = "2.2.1", categories = {
    "atan-ash-seperation", "atan-foundation-from-ash", "atan-landfill-from-ash",
    "atan-nutrients-from-ash", "atan-stone-brick-from-ash"
  }, probabilities = {"atan-ash-seperation"}},
  {name = "atan-nuclear-science", version = "0.3.3", categories = {
    "atomic-bomb", "automation-science-pack", "atan-atom-forge", "breeder-fuel-cell",
    "chemical-science-pack", "centrifuge", "explosive-plutonium-cannon-shell",
    "explosive-uranium-cannon-shell", "fission-reactor-equipment",
    "fission-reactor-equipment-from-MOX-fuel", "fission-reactor-equipment-from-plutonium",
    "fusion-reactor-equipment", "logistic-science-pack", "military-science-pack",
    "MOX-fuel-cell", "nuclear-science-pack", "nuclear-science-pack-from-plutonium",
    "plutonium-atomic-artillery-shell", "plutonium-cannon-shell", "plutonium-fuel-cell",
    "plutonium-rounds-magazine", "production-science-pack", "uranium-cannon-shell",
    "uranium-fuel-cell", "uranium-rounds-magazine", "utility-science-pack"
  }, probabilities = {}}
}

local function categories(recipe)
  if type(recipe) ~= "table" or recipe.category == nil and recipe.additional_categories == nil then return false end
  local selected, seen = {}, {}
  local function append(value)
    if type(value) == "string" and value ~= "" and not seen[value] then
      selected[#selected + 1], seen[value] = value, true
    end
  end
  local function sequence(values)
    if type(values) == "string" then append(values)
    elseif type(values) == "table" then for _, value in ipairs(values) do append(value) end end
  end
  sequence(recipe.categories)
  append(recipe.category)
  sequence(recipe.additional_categories)
  if #selected == 0 then return false end
  recipe.categories, recipe.category, recipe.additional_categories = selected, nil, nil
  return true
end

local function products(results)
  if type(results) ~= "table" then return false end
  local changed = false
  for _, product in ipairs(results) do
    if type(product) == "table" and product.probability ~= nil then
      if product.independent_probability == nil then product.independent_probability = product.probability end
      product.probability, changed = nil, true
    end
  end
  return changed
end

local function probabilities(recipe)
  if type(recipe) ~= "table" then return false end
  local changed = products(recipe.results)
  if type(recipe.normal) == "table" and products(recipe.normal.results) then changed = true end
  if type(recipe.expensive) == "table" and products(recipe.expensive.results) then changed = true end
  return changed
end

function M.apply(raw, active_mods, report)
  active_mods = active_mods or {}
  -- The repair is for the known 2.1 schema. Older editions retain their own
  -- category/probability fields; a version string never proves future schemas.
  if type(active_mods.base) ~= "string" or not active_mods.base:match("^2%.1%.") then return 0 end
  local total = 0
  for _, repair in ipairs(repairs) do
    if active_mods[repair.name] == repair.version then
      local changed, ordered = {}, {}
      local function record(name)
        if not changed[name] then changed[name], ordered[#ordered + 1] = true, name end
      end
      for _, name in ipairs(repair.categories) do
        if categories(raw.recipe and raw.recipe[name]) then record(name) end
      end
      for _, name in ipairs(repair.probabilities) do
        if probabilities(raw.recipe and raw.recipe[name]) then record(name) end
      end
      total = total + #ordered
      if #ordered > 0 and report then
        table.sort(ordered)
        report("[more-infinite-research] Applied Factorio 2.1 recipe schema repair for "
          .. repair.name .. " " .. repair.version .. ": " .. table.concat(ordered, ","))
      end
    end
  end
  return total
end

return M

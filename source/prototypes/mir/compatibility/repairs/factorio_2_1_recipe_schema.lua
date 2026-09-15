local D = require("prototypes.mir.report.diagnostics_sink")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

local M = {}

local repairs = {
  ["atan-ash"] = {
    versions = {
      ["2.2.1"] = true
    },
    category_recipes = {
      "atan-ash-seperation",
      "atan-foundation-from-ash",
      "atan-landfill-from-ash",
      "atan-nutrients-from-ash",
      "atan-stone-brick-from-ash"
    },
    product_probability_recipes = {
      "atan-ash-seperation"
    }
  },
  ["atan-nuclear-science"] = {
    versions = {
      ["0.3.3"] = true
    },
    category_recipes = {
      "atomic-bomb",
      "automation-science-pack",
      "atan-atom-forge",
      "breeder-fuel-cell",
      "chemical-science-pack",
      "centrifuge",
      "explosive-plutonium-cannon-shell",
      "explosive-uranium-cannon-shell",
      "fission-reactor-equipment",
      "fission-reactor-equipment-from-MOX-fuel",
      "fission-reactor-equipment-from-plutonium",
      "fusion-reactor-equipment",
      "logistic-science-pack",
      "military-science-pack",
      "MOX-fuel-cell",
      "nuclear-science-pack",
      "nuclear-science-pack-from-plutonium",
      "plutonium-atomic-artillery-shell",
      "plutonium-cannon-shell",
      "plutonium-fuel-cell",
      "plutonium-rounds-magazine",
      "production-science-pack",
      "uranium-cannon-shell",
      "uranium-fuel-cell",
      "uranium-rounds-magazine",
      "utility-science-pack"
    }
  }
}

local function parse_major_minor(version)
  local major, minor = string.match(tostring(version or ""), "^(%d+)%.(%d+)")
  return tonumber(major), tonumber(minor)
end

local function supports_factorio_2_1_recipe_schema()
  local major, minor = parse_major_minor(factorio_mods.version("base"))
  if not major or not minor then return false end
  if major > 2 then return true end
  return major == 2 and minor >= 1
end

local function add_unique(out, seen, value)
  if type(value) ~= "string" or value == "" then return end
  if seen[value] then return end

  seen[value] = true
  table.insert(out, value)
end

local function append_categories(out, seen, categories)
  if type(categories) == "string" then
    add_unique(out, seen, categories)
    return
  end

  if type(categories) ~= "table" then return end
  for _, category in ipairs(categories) do
    add_unique(out, seen, category)
  end
end

local function normalize_recipe_categories(recipe)
  if not recipe then return false end
  if recipe.category == nil and recipe.additional_categories == nil then return false end

  local categories = {}
  local seen = {}

  append_categories(categories, seen, recipe.categories)
  add_unique(categories, seen, recipe.category)
  append_categories(categories, seen, recipe.additional_categories)

  if #categories == 0 then return false end

  recipe.categories = categories
  recipe.category = nil
  recipe.additional_categories = nil

  return true
end

local function normalize_products(products)
  if type(products) ~= "table" then return false end

  local changed = false
  for _, product in ipairs(products) do
    if type(product) == "table" and product.probability ~= nil then
      if product.independent_probability == nil then
        product.independent_probability = product.probability
      end
      product.probability = nil
      changed = true
    end
  end

  return changed
end

local function normalize_product_probabilities(recipe)
  if not recipe then return false end

  local changed = normalize_products(recipe.results)
  if type(recipe.normal) == "table" and normalize_products(recipe.normal.results) then
    changed = true
  end
  if type(recipe.expensive) == "table" and normalize_products(recipe.expensive.results) then
    changed = true
  end

  return changed
end

local function add_repaired_recipe(out, recipe_name)
  for _, existing in ipairs(out) do
    if existing == recipe_name then return end
  end
  table.insert(out, recipe_name)
end

local function apply_mod_repair(mod_name, spec)
  local active_version = factorio_mods.version(mod_name)
  if not active_version or not spec.versions[tostring(active_version)] then return 0 end

  local repaired = {}
  local category_repaired = {}
  local product_repaired = {}

  for _, recipe_name in ipairs(spec.category_recipes or {}) do
    local recipe = data_raw.prototype("recipe", recipe_name)
    if normalize_recipe_categories(recipe) then
      add_repaired_recipe(category_repaired, recipe_name)
      add_repaired_recipe(repaired, recipe_name)
    end
  end

  for _, recipe_name in ipairs(spec.product_probability_recipes or {}) do
    local recipe = data_raw.prototype("recipe", recipe_name)
    if normalize_product_probabilities(recipe) then
      add_repaired_recipe(product_repaired, recipe_name)
      add_repaired_recipe(repaired, recipe_name)
    end
  end

  if #repaired == 0 then return 0 end

  table.sort(repaired)
  table.sort(category_repaired)
  table.sort(product_repaired)
  local recipes = table.concat(repaired, ",")
  local fields = {}
  if #category_repaired > 0 then
    table.insert(fields, "recipe.categories")
  end
  if #product_repaired > 0 then
    table.insert(fields, "recipe.results.independent_probability")
  end

  log("[more-infinite-research] Applied Factorio 2.1 recipe schema repair for "
    .. mod_name .. " " .. tostring(active_version) .. ": " .. recipes)

  D.rule_mutation({
    key = "factorio_2_1_recipe_schema",
    status = "repaired",
    reason = "exact_mod_version_schema_repair",
    mod = mod_name,
    recipes = recipes,
    field = table.concat(fields, ","),
    observed_value = tostring(active_version),
    expected_baseline = "Factorio 2.1 recipe schema",
    likely_mutator_mod = mod_name,
    evidence = "exact-version-loader-schema-repair"
  })

  return #repaired
end

function M.apply()
  if not supports_factorio_2_1_recipe_schema() then return 0 end

  local count = 0

  for mod_name, spec in pairs(repairs) do
    count = count + apply_mod_repair(mod_name, spec)
  end

  return count
end

return M

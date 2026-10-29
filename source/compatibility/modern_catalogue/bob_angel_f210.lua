-- Literal F210 Bob+Angel delta from the independent q009/q010 upstream and
-- published 4.7.3 captures.  Selection and prototype publication belong to
-- the root-owned catalogue; this file only supplies finite data and checks
-- the named raw fields that data consumes.  It never discovers a route or
-- changes a prototype during preflight.
local angel = require("compatibility.modern_catalogue.angel_f210")
local legacy = require("compatibility.modern_catalogue.bob_angel")

local M = {}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, nested in pairs(value) do out[key] = copy(nested) end
  return out
end

local function effect(recipe, scale)
  return {recipe=recipe, scale=scale or 1}
end

local function same_list(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, value in ipairs(expected) do if actual[index] ~= value then return false end end
  return true
end

local function same_ingredients(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, expected_row in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" or row[1] ~= expected_row[1] or row[2] ~= expected_row[2] then return false end
  end
  return true
end

local function has_result(recipe, expected_type, expected_name, expected_amount)
  for _, row in ipairs(type(recipe) == "table" and recipe.results or {}) do
    if type(row) == "table" and (row.type or "item") == expected_type and row.name == expected_name
        and (expected_amount == nil or row.amount == expected_amount) then
      return true
    end
  end
  return false
end

local function positive_science_result(recipe, name)
  local found = false
  for _, row in ipairs(type(recipe) == "table" and recipe.results or {}) do
    if type(row) == "table" and (row.type or "item") == "item" and row.name == name then
      local amount = row.amount
      if amount == nil then amount = 1 end
      local probability = row.independent_probability
      if probability == nil then probability = row.probability end
      local shared = row.shared_probability
      if found or row.independent_probability ~= nil and row.probability ~= nil
          or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount >= math.huge
          or (probability ~= nil and (type(probability) ~= "number" or probability ~= probability
            or probability <= 0 or probability > 1))
          or (shared ~= nil and (type(shared) ~= "table" or type(shared.min) ~= "number"
            or type(shared.max) ~= "number" or shared.min ~= shared.min or shared.max ~= shared.max
            or shared.min < 0 or shared.max > 1 or shared.min >= shared.max)) then
        return false
      end
      found = true
    end
  end
  return found
end

local function owns_unlock(owner, recipe)
  local count = 0
  for _, effect in ipairs(type(owner) == "table" and owner.effects or {}) do
    if type(effect) == "table" and effect.type == "unlock-recipe" and effect.recipe == recipe then count = count + 1 end
  end
  return count > 0
end

local function legacy_addition(key)
  for _, definition in ipairs(legacy.additions) do
    if definition.key == key then return copy(definition) end
  end
  error("MIR F210 Bob+Angel missing retained F200 definition " .. key, 2)
end

local function angel_override(profile, key)
  local source = angel[profile].definition_overrides[key]
  if source == nil then error("MIR F210 Bob+Angel missing Angel override " .. key, 2) end
  return copy(source)
end

local function base_breeding()
  -- angel_f210 already owns the exact nine Angel recipe effects and captured
  -- presentation.  The q009 change is its F210 science vector, not a new
  -- parallel definition.
  local definition = copy(angel.base.additions[1])
  definition.science = "science_bob_angel_base_ordinary"
  definition.prerequisites = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  }
  return definition
end

local function base_lithium()
  local definition = legacy_addition("research_lithium")
  definition.science = "science_bob_angel_base_ordinary"
  definition.prerequisites = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  }
  return definition
end

local function base_tungsten()
  local definition = legacy_addition("research_tungsten")
  definition.science = "science_bob_angel_base_ordinary"
  definition.prerequisites = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  }
  return definition
end

local function angel_tungsten_override()
  local definition = legacy_addition("research_tungsten")
  return {
    effects=copy(definition.effects), icon=definition.icon, icon_size=definition.icon_size,
    overlay=definition.overlay, localised_name=copy(definition.localised_name),
    localised_description=copy(definition.localised_description), order=definition.order,
  }
end

local COPPER_TUNGSTEN_STAGE = {
  key="research_material_copper_tungsten", item="bob-copper-tungsten-alloy",
  icon="__bobplates__/graphics/icons/plate/copper-tungsten-plate.png", icon_size=32,
  effects={effect("bob-copper-tungsten-alloy", 1)},
  routes={{recipe="bob-copper-tungsten-alloy"}},
  early={id="recipe-prod-research_material_copper_tungsten-1", science="science_bob_angel_base_ordinary",
    prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "angels-tungsten-smelting-1"}, max_level=3,
    order="p[research_material_copper_tungsten]", tuning={base_cost=200, effect_percent=2, enabled=true,
      growth_factor=2, linear_increment=0, max_level=3, research_time=30}},
  continuation={id="recipe-prod-research_material_copper_tungsten-4",
    science="science_bob_angel_base_material_continuation",
    prerequisites={"angels-tungsten-smelting-1", "automation-science-pack", "chemical-science-pack",
      "logistic-science-pack", "production-science-pack", "recipe-prod-research_material_copper_tungsten-1",
      "utility-science-pack"}, max_level="infinite", first_level=4, predecessor_count=800, previous_count=400,
    order="p[research_material_copper_tungsten__continuation]", show_levels_info=false,
    visible_when_disabled=true, tuning={base_cost=1600, effect_percent=2, enabled=true,
      growth_factor=1, linear_increment=200, max_level=0, research_time=30}},
}

M.science = {
  science_bob_angel_base_ordinary = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  },
  science_bob_angel_base_research = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "utility-science-pack", "military-science-pack", "angels-token-bio", "bob-advanced-logistic-science-pack",
  },
  science_bob_angel_base_material_continuation = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "utility-science-pack",
  },
  science_bob_angel_base_braking = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack",
    "bob-advanced-logistic-science-pack",
  },
  science_bob_angel_base_laser = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack",
    "utility-science-pack",
  },
  science_bob_angel_space_breeding = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "agricultural-science-pack", "cryogenic-science-pack",
  },
  science_bob_angel_space_lithium = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "cryogenic-science-pack",
  },
  science_bob_angel_space_tungsten = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "metallurgic-science-pack",
  },
  science_bob_angel_space_research = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "utility-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack",
    "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack",
    "promethium-science-pack", "angels-token-bio", "bob-advanced-logistic-science-pack",
  },
  science_bob_angel_space_braking = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack",
    "bob-advanced-logistic-science-pack", "space-science-pack",
  },
  science_bob_angel_space_laser = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack",
    "utility-science-pack", "space-science-pack",
  },
}

M.base = {
  additions={base_breeding(), base_lithium(), base_tungsten()},
  -- Do not carry Angel aluminium into combined Bob+Angel.  q009 has the raw
  -- routes, but B6 records no MIR aluminium material identities in this tuple.
  material_stages={copy(COPPER_TUNGSTEN_STAGE)},
  definition_overrides={
    -- The F200 r03 contract retains this earned identity after Angel replaces
    -- its active routes.  Keep its two-pack progression and effects, but do
    -- not offer a new combined-profile research path.
    research_oil_cracking_productivity={available=false, science="science_automation_logistic"},
    research_lubricant_productivity=angel_override("base", "research_lubricant_productivity"),
    research_steel=angel_override("base", "research_steel"),
    research_sulfur=angel_override("base", "research_sulfur"),
    research_sulfuric_acid_productivity=angel_override("base", "research_sulfuric_acid_productivity"),
  },
  -- Keep the shared science-product collector active. This binds q009's
  -- captured ingredients and prerequisite progression without exact-binding
  -- its effects; they still come from concrete current lab inputs in the one
  -- final collection pass.
  definition_progression={
    research_science_pack_productivity={science="science_bob_angel_base_research", exact_prerequisites=true,
      prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
        "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
        "angels-gardens", "bob-advanced-logistic-science-pack"}},
  },
  continuation_overrides={
    braking_force={science="science_bob_angel_base_braking"},
    laser_shooting_speed={science="science_bob_angel_base_laser"},
    research_speed={science="science_bob_angel_base_research", exact_prerequisites=true,
      prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
        "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
        "angels-gardens", "bob-advanced-logistic-science-pack"}},
  },
}

M.space_age = {
  -- Space Age uses its admitted lithium/tungsten definitions.  The combined
  -- layer supplies only the exact Angel recipe vectors and science overlays;
  -- it must never emit q009's copper-tungsten material stages on q010.
  additions={}, material_stages={},
  definition_overrides={
    research_breeding=angel_override("space_age", "research_breeding"),
    -- q010 repurposes carbon to angels-solid-carbon. Preserve B6's exact
    -- two-route vector rather than granting the ordinary item-carbon bonus.
    research_carbon={effects={effect("burnt-spoilage", 0.5), effect("coal-synthesis", 0.2)}},
    research_lubricant_productivity=angel_override("space_age", "research_lubricant_productivity"),
    -- Preserve the F200 r03 earned identity in the combined profile rather
    -- than creating the unsupported five-pack active oil route.
    research_oil_cracking_productivity={available=false, science="science_automation_logistic"},
    research_oil_processing_productivity=angel_override("space_age", "research_oil_processing_productivity"),
    research_sulfur=angel_override("space_age", "research_sulfur"),
    research_sulfuric_acid_productivity=angel_override("space_age", "research_sulfuric_acid_productivity"),
    research_tungsten=angel_tungsten_override(),
  },
  -- Root wiring applies these only after the normal Space Age definitions are
  -- present.  The three named science keys are captured q010 facts.
  definition_science={
    research_breeding="science_bob_angel_space_breeding",
    research_lithium="science_bob_angel_space_lithium",
    research_tungsten="science_bob_angel_space_tungsten",
  },
  -- q010's combined native research-speed progression is the independent
  -- source for this vector. Effects remain collector-owned, not exact
  -- profile data, so every concrete accepted lab-input producer is kept.
  definition_progression={
    research_science_pack_productivity={science="science_bob_angel_space_research", exact_prerequisites=true,
      prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
        "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
        "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
        "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "angels-gardens",
        "bob-advanced-logistic-science-pack"}},
  },
  continuation_overrides={
    braking_force={science="science_bob_angel_space_braking"},
    laser_shooting_speed={science="science_bob_angel_space_laser"},
    research_speed={science="science_bob_angel_space_research", exact_prerequisites=true,
      prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
        "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
        "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
        "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "angels-gardens",
        "bob-advanced-logistic-science-pack"}},
  },
  native_owners=copy(angel.space_age.native_owners),
}

local function fail(message, callback)
  local full = "MIR F210 Bob+Angel preflight: " .. message
  if type(callback) == "function" then callback(full) else error(full, 3) end
end

local function require_recipe(raw, name, expected_type, expected_name, expected_amount, callback)
  local recipe = raw.recipe[name]
  if type(recipe) ~= "table" or not has_result(recipe, expected_type, expected_name, expected_amount) then
    fail("named route changed: " .. name, callback)
  end
  return recipe
end

local function require_owner(raw, name, recipes, callback)
  local owner = raw.technology[name]
  if type(owner) ~= "table" then fail("named owner changed: " .. name, callback) end
  for _, recipe in ipairs(recipes) do
    if not owns_unlock(owner, recipe) then fail(name .. " no longer owns " .. recipe, callback) end
  end
  return owner
end

local function require_item(raw, name, callback)
  if type(raw.item[name]) ~= "table" then fail("named science/input item changed: " .. name, callback) end
end

local function require_science_inputs(raw, profile, callback)
  local science = profile == "space-age" and M.science.science_bob_angel_space_research
    or M.science.science_bob_angel_base_research
  for _, name in ipairs(science) do require_item(raw, name, callback) end
  local gardens = raw.technology["angels-gardens"]
  if type(gardens) ~= "table" or gardens.enabled == false then fail("angels-gardens changed", callback) end
  local pack = "bob-advanced-logistic-science-pack"
  local recipe = require_recipe(raw, pack, "item", pack, nil, callback)
  if not positive_science_result(recipe, pack) or not owns_unlock(raw.technology[pack], pack) then
    fail("Bob advanced science route changed: " .. pack, callback)
  end
end

local function require_angel_breeding(raw, profile, callback)
  for _, expected in ipairs({
    {"angels-alien-fish-0-raw", "raw-fish"},
    {"angels-biter-big-breeding", "angels-biter-queen-big"},
    {"angels-biter-medium-breeding", "angels-biter-queen-medium"},
    {"angels-biter-small-breeding", "angels-biter-queen-small"},
    {"angels-puffer-breeding-12", "angels-bio-puffer-egg-2"},
    {"angels-puffer-breeding-13", "angels-bio-puffer-egg-3"},
    {"angels-puffer-breeding-14", "angels-bio-puffer-egg-4"},
    {"angels-puffer-breeding-15", "angels-bio-puffer-egg-5"},
    {"angels-puffer-breeding-23", "angels-bio-puffer-egg-1"},
  }) do
    require_recipe(raw, expected[1], "item", expected[2], nil, callback)
  end
  if profile == "space-age" then
    -- Both routes are legitimate productivity-denied upstream inputs.  The
    -- captured B6 technology nevertheless contains their named effects, so
    -- selection must not turn an unrelated recipe permission into a guard.
    require_recipe(raw, "fish-breeding", "item", "raw-fish", nil, callback)
    require_recipe(raw, "acid-neutralisation", "fluid", "steam", 1000, callback)
    require_recipe(raw, "biter-egg", "item", "biter-egg", nil, callback)
    require_recipe(raw, "pentapod-egg", "item", "pentapod-egg", nil, callback)
  end
end

local function require_common_angel_routes(raw, profile, callback)
  require_recipe(raw, "angels-liquid-fish-oil-refining", "fluid", "lubricant", 60, callback)
  require_recipe(raw, "angels-mineral-oil-lubricant", "fluid", "lubricant", 50, callback)
  require_recipe(raw, "angels-solid-sodium-sulfate-separation", "item", "sulfur", 2, callback)
  require_recipe(raw, "angels-solid-sulfur", "item", "sulfur", 3, callback)
  require_recipe(raw, "angels-yellow-waste-water-purification", "item", "sulfur", 1, callback)
  require_recipe(raw, "angels-liquid-sulfuric-acid", "fluid", "sulfuric-acid", 60, callback)
  if profile == "space-age" then require_recipe(raw, "biosulfur", "item", "sulfur", nil, callback) end
end

local function require_lithium(raw, profile, callback)
  if profile == "base" then
    require_recipe(raw, "lithium-plate", "item", "lithium-plate", nil, callback)
    require_owner(raw, "bob-lithium-processing", {"lithium-plate"}, callback)
  else
    require_recipe(raw, "lithium", "item", "lithium", nil, callback)
    require_recipe(raw, "lithium-plate", "item", "lithium-plate", nil, callback)
    require_owner(raw, "lithium-processing", {"lithium", "lithium-plate"}, callback)
  end
end

local function require_tungsten(raw, profile, callback)
  require_recipe(raw, "angels-plate-tungsten", "item", "tungsten-plate", 12, callback)
  require_recipe(raw, "tungsten-carbide", "item", "tungsten-carbide", 20, callback)
  local owner_recipes = {"angels-plate-tungsten", "tungsten-carbide"}
  if profile == "base" then
    require_recipe(raw, "bob-copper-tungsten-alloy", "item", "bob-copper-tungsten-alloy", 25, callback)
    owner_recipes[#owner_recipes + 1] = "bob-copper-tungsten-alloy"
  end
  require_owner(raw, "angels-tungsten-smelting-1", owner_recipes, callback)
end

local function require_native_steel(raw, callback)
  local steel = raw.technology["steel-plate-productivity"]
  local expected = M.space_age.native_owners.research_steel.expected
  if type(steel) ~= "table" or steel.max_level ~= expected.max_level or type(steel.unit) ~= "table"
      or steel.unit.count_formula ~= expected.count_formula or steel.unit.time ~= expected.research_time
      or not same_list(steel.prerequisites, expected.prerequisites)
      or not same_ingredients(steel.unit.ingredients, expected.ingredients) then
    fail("steel-plate-productivity changed", callback)
  end
  local required, seen = { ["steel-plate"]=true, ["casting-steel"]=true }, {}
  for _, effect in ipairs(type(steel.effects) == "table" and steel.effects or {}) do
    if type(effect) == "table" and effect.type == "change-recipe-productivity" and required[effect.recipe] then
      if seen[effect.recipe] or effect.change ~= expected.effect_change then
        fail("steel-plate-productivity existing effect changed: " .. effect.recipe, callback)
      end
      seen[effect.recipe] = true
    elseif type(effect) == "table" and effect.type == "change-recipe-productivity"
        and (effect.recipe == "angels-plate-steel" or effect.recipe == "angels-plate-steel-2") then
      fail("steel-plate-productivity already owns Angel steel", callback)
    end
  end
  for recipe in pairs(required) do
    if not seen[recipe] then fail("steel-plate-productivity existing effect changed: " .. recipe, callback) end
  end
  require_recipe(raw, "angels-plate-steel", "item", "steel-plate", 4, callback)
  require_recipe(raw, "angels-plate-steel-2", "item", "steel-plate", 4, callback)
end

-- All failures occur before root-owned data-final publication.  The adapter
-- checks no profile-wide version tuple, graphics, recipe reachability, or
-- candidate output.
function M.preflight(raw, profile, callback)
  if profile ~= "base" and profile ~= "space-age" then fail("unknown profile", callback) end
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table"
      or type(raw.item) ~= "table" then
    fail("named raw tables are unavailable", callback)
  end
  require_angel_breeding(raw, profile, callback)
  require_common_angel_routes(raw, profile, callback)
  require_lithium(raw, profile, callback)
  require_tungsten(raw, profile, callback)
  require_science_inputs(raw, profile, callback)
  if profile == "space-age" then require_native_steel(raw, callback) end
  return copy(profile == "space-age" and M.space_age or M.base)
end

function M.delta(profile)
  if profile ~= "base" and profile ~= "space-age" then error("MIR F210 Bob+Angel unknown profile", 2) end
  return copy(profile == "space-age" and M.space_age or M.base)
end

return M

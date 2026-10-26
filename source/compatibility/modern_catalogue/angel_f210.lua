-- Literal F210 pure-Angel data delta.  Profile selection and publication are
-- deliberately outside this module.  Every fact below is tied to q007/q008
-- upstream and published B6 captures; no foreign prototype discovery occurs.
local f200 = require("compatibility.modern_catalogue.bob_angel")

local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, nested in pairs(value) do out[key] = copy(nested) end
  return out
end

local function effects(entries)
  local out = {}
  for index = 1, #entries, 2 do out[#out + 1] = {recipe = entries[index], scale = entries[index + 1]} end
  return out
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

local function result_has(recipe, product)
  for _, row in ipairs(recipe.results or {}) do
    if (row.type or "item") == product.type and row.name == product.name and row.amount == product.amount then return true end
  end
  return false
end

local SULFUR_ICONS = {
  {icon="__angelsrefininggraphics__/graphics/icons/angels-gas/gas-tech-base.png", icon_size=604, scale=0.05298013245033113,
    tint={r=0.25, g=0.25, b=0.25, a=0.7}},
  {icon="__angelsrefininggraphics__/graphics/icons/angels-gas/gas-tech-top.png", icon_size=604, scale=0.05298013245033113,
    tint={r=1, g=1, b=0.18823529411764706, a=1}},
  {icon="__angelsrefininggraphics__/graphics/icons/angels-gas/gas-tech-mid.png", icon_size=604, scale=0.05298013245033113,
    tint={r=0.8470588235294118, g=0.7686274509803922, b=0.06666666666666667, a=1}},
  {icon="__angelsrefininggraphics__/graphics/icons/angels-gas/gas-tech-bot.png", icon_size=604, scale=0.05298013245033113,
    tint={r=0.8235294117647058, g=0.7333333333333333, b=0.11764705882352941, a=1}},
  {icon=OVERLAY, icon_size=128, scale=0.5, shift={50, 50}, floating=true},
}

local ROUTES = {
  {recipe="angels-alien-fish-0-raw", product={type="item", name="raw-fish", amount=nil}, allow_productivity=true},
  {recipe="angels-biter-big-breeding", product={type="item", name="angels-biter-queen-big", amount=1}, allow_productivity=true},
  {recipe="angels-biter-medium-breeding", product={type="item", name="angels-biter-queen-medium", amount=1}, allow_productivity=true},
  {recipe="angels-biter-small-breeding", product={type="item", name="angels-biter-queen-small", amount=1}, allow_productivity=true},
  {recipe="angels-puffer-breeding-12", product={type="item", name="angels-bio-puffer-egg-2", amount=1}, allow_productivity=true},
  {recipe="angels-puffer-breeding-13", product={type="item", name="angels-bio-puffer-egg-3", amount=1}, allow_productivity=true},
  {recipe="angels-puffer-breeding-14", product={type="item", name="angels-bio-puffer-egg-4", amount=1}, allow_productivity=true},
  {recipe="angels-puffer-breeding-15", product={type="item", name="angels-bio-puffer-egg-5", amount=1}, allow_productivity=true},
  {recipe="angels-puffer-breeding-23", product={type="item", name="angels-bio-puffer-egg-1", amount=1}, allow_productivity=true},
  {recipe="angels-liquid-fish-oil-refining", product={type="fluid", name="lubricant", amount=60}},
  {recipe="angels-mineral-oil-lubricant", product={type="fluid", name="lubricant", amount=50}},
  {recipe="angels-plate-steel", product={type="item", name="steel-plate", amount=4}, allow_productivity=true},
  {recipe="angels-plate-steel-2", product={type="item", name="steel-plate", amount=4}, allow_productivity=true},
  {recipe="angels-solid-sodium-sulfate-separation", product={type="item", name="sulfur", amount=2}},
  {recipe="angels-solid-sulfur", product={type="item", name="sulfur", amount=3}},
  {recipe="angels-yellow-waste-water-purification", product={type="item", name="sulfur", amount=1}},
  {recipe="angels-liquid-sulfuric-acid", product={type="fluid", name="sulfuric-acid", amount=60}},
  {recipe="angels-plate-aluminium", product={type="item", name="angels-plate-aluminium", amount=4}, allow_productivity=true},
  {recipe="angels-plate-aluminium-2", product={type="item", name="angels-plate-aluminium", amount=4}, allow_productivity=true},
}

local ALUMINIUM_OWNERS = {
  {name="angels-aluminium-smelting-1", recipe="angels-plate-aluminium", count=150, time=30,
    prerequisites={"angels-ore-floatation", "angels-powder-metallurgy-2", "angels-chlorine-processing-1"},
    ingredients={{"automation-science-pack", 1}, {"logistic-science-pack", 1}}},
  {name="angels-aluminium-casting-2", recipe="angels-plate-aluminium-2", count=200, time=30,
    prerequisites={"angels-strand-casting-2", "angels-aluminium-smelting-1", "angels-manganese-smelting-2"},
    ingredients={{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}}},
}

local function f200_effects(key)
  return copy(assert(f200.definition_overrides[key]).effects)
end

local function f200_addition(key)
  for _, definition in ipairs(f200.additions) do
    if definition.key == key then return definition end
  end
  error("MIR F210 Angel data requires F200 " .. key, 2)
end

local function base_breeding()
  local f200_breeding = f200_addition("research_breeding")
  return {
    key="research_breeding", family="research_breeding", kind="productivity",
    science="science_automation_logistic_chemical_production",
    prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    effects=copy(f200_breeding.effects), icon=f200_breeding.icon, icon_size=f200_breeding.icon_size,
    overlay=f200_breeding.overlay, localised_name=copy(f200_breeding.localised_name),
    localised_description=copy(f200_breeding.localised_description), order=f200_breeding.order,
    tuning=copy(f200_breeding.tuning), setting_order=f200_breeding.setting_order,
  }
end

local M = {
  -- Explicit F210 science vectors; these names are consumed by root-owned
  -- catalogue wiring, not inferred from recipe or lab data.
  science = {
    science_automation_logistic_chemical_production = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    },
    science_automation_logistic_chemical = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    },
    science_automation_logistic_chemical_utility = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack",
    },
    science_automation_logistic_chemical_production_military_utility_angel = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
      "utility-science-pack", "military-science-pack", "angels-token-bio",
    },
    science_automation_logistic_chemical_production_electromagnetic = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
      "electromagnetic-science-pack",
    },
    science_automation_logistic_chemical_production_cryogenic = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
      "cryogenic-science-pack",
    },
    science_automation_logistic_chemical_production_metallurgic = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
      "metallurgic-science-pack",
    },
    science_all_space_age_angel = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
      "military-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack",
      "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack",
      "promethium-science-pack", "angels-token-bio",
    },
    science_all_space_age_angel_research = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
      "utility-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack",
      "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack",
      "promethium-science-pack", "angels-token-bio",
    },
  },

  base = {
    additions = {base_breeding()},
    definition_overrides = {
      research_lubricant_productivity = {effects=f200_effects("research_lubricant_productivity")},
      research_steel = {effects=f200_effects("research_steel")},
      research_sulfur = {effects=f200_effects("research_sulfur"), icons=copy(SULFUR_ICONS)},
      research_sulfuric_acid_productivity = {
        effects=f200_effects("research_sulfuric_acid_productivity"),
        icons=copy(f200.definition_overrides.research_sulfuric_acid_productivity.icons),
      },
    },
    continuation_overrides = {
      research_speed = {
        science="science_automation_logistic_chemical_production_military_utility_angel",
        prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
          "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
          "angels-gardens"},
      },
    },
    material_stages = {
      {
        key="research_material_aluminium", item="angels-plate-aluminium",
        icon="__angelssmeltinggraphics__/graphics/icons/plate-aluminium.png", icon_size=32,
        effects=effects({"angels-plate-aluminium", 1, "angels-plate-aluminium-2", 1}),
        early={id="recipe-prod-research_material_aluminium-1", science="science_automation_logistic_chemical",
          prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "angels-aluminium-smelting-1", "angels-aluminium-casting-2"}, max_level=3,
          order="p[research_material_aluminium]", tuning={base_cost=200, effect_percent=2, enabled=true,
            growth_factor=2, linear_increment=0, max_level=3, research_time=30}},
        continuation={id="recipe-prod-research_material_aluminium-4", science="science_automation_logistic_chemical_utility",
          prerequisites={"angels-aluminium-casting-2", "angels-aluminium-smelting-1", "automation-science-pack",
            "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_aluminium-1",
            "utility-science-pack"}, max_level="infinite", first_level=4, predecessor_count=800,
          previous_count=400, order="p[research_material_aluminium__continuation]", tuning={base_cost=1600,
            effect_percent=2, enabled=true, growth_factor=1, linear_increment=200, max_level=0, research_time=30}},
      },
    },
  },

  space_age = {
    definition_overrides = {
      research_breeding = {effects=effects({
        "angels-alien-fish-0-raw", 1, "angels-biter-big-breeding", 1, "angels-biter-medium-breeding", 1,
        "angels-biter-small-breeding", 1, "angels-puffer-breeding-12", 1, "angels-puffer-breeding-13", 1,
        "angels-puffer-breeding-14", 1, "angels-puffer-breeding-15", 1, "angels-puffer-breeding-23", 1,
        "biter-egg", 1, "fish-breeding", 1, "pentapod-egg", 1,
      })},
      research_lubricant_productivity = {effects=effects({
        "angels-liquid-fish-oil-refining", 1, "angels-mineral-oil-lubricant", 1, "biolubricant", 1,
      })},
      research_oil_processing_productivity = {effects=effects({"simple-coal-liquefaction", 1})},
      research_science_pack_productivity = {
        science="science_all_space_age_angel",
        prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
          "military-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack",
          "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
          "angels-gardens"},
        effects=effects({
          "agricultural-science-pack", 1, "angels-desert-garden-a", 1, "angels-desert-garden-cultivating-a", 1,
          "angels-swamp-garden-a", 1, "angels-swamp-garden-cultivating-a", 1, "angels-temperate-garden-a", 1,
          "angels-temperate-garden-cultivating-a", 1, "automation-science-pack", 1, "chemical-science-pack", 1,
          "cryogenic-science-pack", 1, "electromagnetic-science-pack", 1, "logistic-science-pack", 1,
          "metallurgic-science-pack", 1, "military-science-pack", 1, "production-science-pack", 1,
          "promethium-science-pack", 1, "space-science-pack", 1, "utility-science-pack", 1,
        }),
      },
      research_sulfur = {effects=effects({
        "angels-solid-sodium-sulfate-separation", 1, "angels-solid-sulfur", 1,
        "angels-yellow-waste-water-purification", 1, "biosulfur", 1,
      }), icons=copy(SULFUR_ICONS)},
      research_sulfuric_acid_productivity = {
        effects=effects({"acid-neutralisation", 1, "angels-liquid-sulfuric-acid", 1}),
        icons=copy(f200.definition_overrides.research_sulfuric_acid_productivity.icons),
      },
    },
    continuation_overrides = {
      research_speed = {
        science="science_all_space_age_angel_research",
        prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
          "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
          "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack",
          "cryogenic-science-pack", "promethium-science-pack", "angels-gardens"},
      },
    },
    native_owners = {
      research_steel = {
        id="steel-plate-productivity", setting="ips-max-level-research_steel",
        expected={max_level="infinite", count_formula="1.5^L*1000", research_time=60,
          base_cost=1000, growth_factor=1.5, linear_increment=0, effect_change=0.1,
          prerequisites={"production-science-pack"},
          ingredients={{"automation-science-pack", 1}, {"logistic-science-pack", 1},
            {"chemical-science-pack", 1}, {"production-science-pack", 1}},
          recipes={"steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"}},
      },
    },
  },
}

local function refuse(fail, message)
  local full = "MIR F210 Angel preflight: " .. message
  if type(fail) == "function" then fail(full) else error(full, 3) end
  return nil
end

-- This consumes only the named recipe/output and aluminium owner/science
-- fields represented above. It neither changes raw nor searches it.
function M.preflight(raw, profile, fail)
  if profile ~= "base" and profile ~= "space-age" then return refuse(fail, "unknown profile") end
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
    return refuse(fail, "named raw tables are unavailable")
  end
  for _, expected in ipairs(ROUTES) do
    local recipe = raw.recipe[expected.recipe]
    if type(recipe) ~= "table" or recipe.enabled ~= false or recipe.allow_productivity ~= expected.allow_productivity
      or not result_has(recipe, expected.product) then
      return refuse(fail, expected.recipe .. " changed")
    end
  end
  for _, expected in ipairs(ALUMINIUM_OWNERS) do
    local owner = raw.technology[expected.name]
    if type(owner) ~= "table" or type(owner.unit) ~= "table" or owner.unit.count ~= expected.count
      or owner.unit.time ~= expected.time or not same_list(owner.prerequisites, expected.prerequisites)
      or not same_ingredients(owner.unit.ingredients, expected.ingredients) then
      return refuse(fail, expected.name .. " science changed")
    end
    local unlocks = 0
    for _, effect in ipairs(owner.effects or {}) do
      if effect.recipe == expected.recipe then
        if effect.type ~= "unlock-recipe" then return refuse(fail, expected.name .. " owner changed") end
        unlocks = unlocks + 1
      end
    end
    if unlocks ~= 1 then return refuse(fail, expected.name .. " no longer owns " .. expected.recipe) end
  end
  if profile == "space-age" then
    local steel = raw.technology["steel-plate-productivity"]
    local expected = M.space_age.native_owners.research_steel.expected
    if type(steel) ~= "table" or steel.max_level ~= expected.max_level or type(steel.unit) ~= "table"
      or steel.unit.count_formula ~= expected.count_formula or steel.unit.time ~= expected.research_time
      or not same_ingredients(steel.unit.ingredients, expected.ingredients) or not same_list(steel.prerequisites, expected.prerequisites) then
      return refuse(fail, "steel-plate-productivity changed")
    end
  end
  return M[profile == "space-age" and "space_age" or profile]
end

return M

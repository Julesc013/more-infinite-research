-- Exact F200 Bob Warfare armor component binding.  The historical selector
-- has two item-pattern groups: plating receives the configured 5% and armor
-- plate receives 2% (the .4 setting ratio).  The named Bob mech row proves
-- the latter path without collapsing the retained broad family to one item.
--
-- The Base collector's .5/.2 weights assume a 10% stream; applying them to
-- Bob Warfare's captured 5% stream would yield .025/.01.  The catalogue's
-- `exact_product_target_families` entry therefore suppresses only those
-- incompatible Base rules.  `product_bindings` below stays a pair of broad,
-- one-pass collector rules and preserves every matching armor/plating route.
local M = {}

M.definition = {
  key="research_armor_components", family="research_armor_components", kind="productivity",
  science="science_automation_logistic_chemical_production_military", prerequisites={},
  -- This seed makes the family eligible for the collector.  Its final vector
  -- is rebuilt from the two bounded item-pattern groups below.
  effects={{recipe="bob-mech-armor-plate", scale=0.4}},
  icon="__base__/graphics/technology/power-armor.png", icon_size=256,
  overlay="__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
  localised_name={"technology-name.more-infinite-research.research_armor_components", {"technology-name.power-armor"}},
  localised_description={"technology-description.more-infinite-research.recipe_productivity"},
  order="p[research_armor_components]",
}

function M.product_bindings()
  return {
    {family="research_armor_components", weight=1, item_patterns={
      "^.+%-armor%-plating$", "^.+%-armour%-plating$", "^armor%-plating.*$", "^armour%-plating.*$",
    }},
    {family="research_armor_components", weight=0.4, item_patterns={
      "^.+%-armor%-plate$", "^.+%-armour%-plate$", "^armor%-plate.*$", "^armour%-plate.*$",
    }},
  }
end

local function row_name(row) return type(row) == "table" and (row.name or row[1]) or nil end
local function row_amount(row) return type(row) == "table" and (row.amount or row[2]) or nil end

local function ordinary(rows, expected)
  if type(rows) ~= "table" or #rows ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local row = rows[index]
    if type(row) ~= "table" or (row.type or "item") ~= wanted.type
      or row_name(row) ~= wanted.name or row_amount(row) ~= wanted.amount
      or row.amount_min ~= nil or row.amount_max ~= nil
      or (row.probability ~= nil and row.probability ~= 1)
      or (row.independent_probability ~= nil and row.independent_probability ~= 1)
      or (row.catalyst_amount ~= nil and row.catalyst_amount ~= 0)
      or (row.ignored_by_productivity ~= nil and row.ignored_by_productivity ~= 0)
      or (row.extra_count_fraction ~= nil and row.extra_count_fraction ~= 0) then return false end
  end
  return true
end

function M.preflight(raw)
  if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table"
      or type(raw.technology) ~= "table" then
    error("MIR F200 Bob Warfare raw prototypes are unavailable", 2)
  end
  local item, recipe, owner = raw.item["bob-mech-armor-plate"], raw.recipe["bob-mech-armor-plate"],
    raw.technology["bob-tankotron"]
  -- The research uses its authored Base icon, not this item's artwork.
  -- Reskins do not change the named typed product or its recipe/owner binding.
  if type(item) ~= "table" then
    error("MIR F200 Bob Warfare armor item is unavailable", 2)
  end
  if type(recipe) ~= "table" or recipe.enabled ~= false or recipe.hidden == true
      or recipe.allow_productivity ~= true
      or recipe.maximum_productivity ~= nil
      or not ordinary(recipe.ingredients, {{type="item",name="low-density-structure",amount=5},
        {type="item",name="steel-plate",amount=2}})
      or not ordinary(recipe.results, {{type="item",name="bob-mech-armor-plate",amount=1}}) then
    error("MIR F200 Bob Warfare armor route changed", 2)
  end
  if type(owner) ~= "table" or owner.enabled == false
      or not ordinary(owner.unit and owner.unit.ingredients, {{type="item",name="automation-science-pack",amount=1},
        {type="item",name="logistic-science-pack",amount=1},{type="item",name="military-science-pack",amount=1},
        {type="item",name="chemical-science-pack",amount=1},{type="item",name="production-science-pack",amount=1}})
      or type(owner.prerequisites) ~= "table" or #owner.prerequisites ~= 2
      or owner.prerequisites[1] ~= "bob-walking-vehicle" or owner.prerequisites[2] ~= "tank" then
    error("MIR F200 Bob Warfare armor owner changed", 2)
  end
  local count = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == "bob-mech-armor-plate" then
      if effect.type ~= "unlock-recipe" then error("MIR F200 Bob Warfare armor owner changed", 2) end
      count = count + 1
    end
  end
  if count ~= 1 then error("MIR F200 Bob Warfare armor owner changed", 2) end
end

return M

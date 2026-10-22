local science_pack = "automation-science-pack"
local alternative_name = "mir-science-ambiguity-automation-science-pack"
local owner_names = {
  "mir-science-ambiguity-owner-a",
  "mir-science-ambiguity-owner-b"
}
local gear_technology = "recipe-prod-research_gears-1"

local function fail(message)
  error("[mir-science-ambiguity] " .. message)
end

local function produces(recipe, item_name)
  if recipe.result == item_name then return true end
  for _, product in ipairs(recipe.results or {}) do
    if product.name == item_name or product[1] == item_name then return true end
  end
  return false
end

local function has_unlock(technology, recipe_name)
  local matches = 0
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == recipe_name then matches = matches + 1 end
  end
  return matches == 1
end

local original = data.raw.recipe and data.raw.recipe[science_pack]
local alternative = data.raw.recipe and data.raw.recipe[alternative_name]
local seed = data.raw.technology and data.raw.technology[science_pack]
if not original or not alternative or not seed then fail("science seed, original recipe, or alternative recipe is absent") end
if original.enabled ~= false or alternative.name ~= alternative_name or alternative.enabled ~= original.enabled
    or not produces(original, science_pack) or not produces(alternative, science_pack) then
  fail("original and copied science recipes do not preserve their named product")
end
if not seed.research_trigger or not has_unlock(seed, science_pack) then
  fail("original automation science seed unlock is not preserved")
end

for _, name in ipairs(owner_names) do
  local technology = data.raw.technology[name]
  local unit = technology and technology.unit
  local ingredients = unit and unit.ingredients or nil
  local ingredient = ingredients and ingredients[1] or nil
  if not technology or technology.type ~= "technology" or technology.icon ~= "__base__/graphics/technology/automation-science-pack.png"
      or technology.icon_size ~= 256 then
    fail("fixture owner has an invalid native technology icon: " .. name)
  end
  if #technology.prerequisites ~= 1 or technology.prerequisites[1] ~= science_pack
      or not unit or unit.count ~= 1 or unit.time ~= 1 or #ingredients ~= 1
      or type(ingredient) ~= "table" or ingredient.type ~= nil or ingredient[1] ~= science_pack
      or ingredient[2] ~= 1 or not has_unlock(technology, science_pack) then
    fail("fixture owner is not an automation-science ItemID tuple unlock: " .. name)
  end
end

local version = mods["more-infinite-research"]
local major = type(version) == "string" and tonumber(version:match("^(%d+)")) or nil
if major == 5 then
  local gear = data.raw.technology[gear_technology]
  if not gear or gear.type ~= "technology" then fail("MIR 5 did not create gear research") end
  -- The original incident also named space science. A direct declaration must
  -- accept the existing native item/prerequisite without discovering its
  -- recipe-production or research-trigger dependency chain.
  local api = require("__more-infinite-research__.api.v1.data")
  local name = "mir-science-ambiguity-space-research"
  local published = api.add_technology({
    type = "technology", name = name,
    icon = "__base__/graphics/technology/space-science-pack.png", icon_size = 256,
    prerequisites = {"space-science-pack"},
    unit = {count = 1, time = 1, ingredients = {{"space-science-pack", 1}}},
    effects = {{type = "character-crafting-speed", modifier = 0.01}}
  })
  local research = data.raw.technology[name]
  if published ~= name or not research
      or research.prerequisites[1] ~= "space-science-pack"
      or research.unit.ingredients[1][1] ~= "space-science-pack" then
    fail("direct space-science declaration was not published intact")
  end
elseif major ~= 4 then
  fail("fixture requires a MIR 4.7+ or MIR 5 package")
end

log("[MIR_SCIENCE_AMBIGUITY_DATA] MIR=" .. version .. ";status=unqualified-representative")

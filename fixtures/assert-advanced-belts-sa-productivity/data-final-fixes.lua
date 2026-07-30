local technology = data.raw.technology and data.raw.technology["recipe-prod-research_belts-1"]
local expected_change = 0.005
local expected = {
  "extreme-belt",
  "extreme-lanesplitter",
  "extreme-splitter",
  "extreme-underground",
  "high-speed-belt",
  "high-speed-lanesplitter",
  "high-speed-splitter",
  "high-speed-underground",
  "ultimate-belt",
  "ultimate-lanesplitter",
  "ultimate-splitter",
  "ultimate-underground"
}

local function fail(message)
  error("MIR Advanced Belts SA validation failed: " .. message)
end

if not technology then fail("missing generated belt productivity technology.") end

local effects = {}
for _, effect in ipairs(technology.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe then
    effects[effect.recipe] = tonumber(effect.change)
  end
end

for _, recipe_name in ipairs(expected) do
  if not (data.raw.recipe and data.raw.recipe[recipe_name]) then
    fail("exact Advanced Belts SA 2.3.3 recipe is missing: " .. recipe_name)
  end
  if effects[recipe_name] == nil then
    fail("belt productivity effect is missing for " .. recipe_name)
  end
  if math.abs(effects[recipe_name] - expected_change) > 0.000000001 then
    fail(recipe_name .. " should receive +0.5% per level, got " .. tostring(effects[recipe_name]))
  end
end

for _, recipe_name in ipairs({"high-speed-belt", "high-speed-lanesplitter", "high-speed-splitter", "high-speed-underground"}) do
  local recipe = data.raw.recipe[recipe_name]
  local ignored_return = false
  for _, product in ipairs(recipe.results or {}) do
    if product.type == "fluid" and (tonumber(product.ignored_by_productivity) or 0) > 0 then
      ignored_return = true
    end
  end
  if not ignored_return then
    fail(recipe_name .. " must preserve its productivity-ignored cryogenic fluid return.")
  end
end

log("[mir-fixture-assert-advanced-belts-sa-productivity] passed: 12 structural belt recipes and 4 cryogenic return contracts")

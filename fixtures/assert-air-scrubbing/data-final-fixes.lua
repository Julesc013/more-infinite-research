local function fail(message)
  error("MIR validation failed: " .. message)
end

local function assert_single_recipe_effect(tech_name, recipe_name)
  local tech = data.raw.technology and data.raw.technology[tech_name]
  if not tech then
    fail("missing generated technology " .. tech_name)
  end
  if tech.max_level ~= "infinite" then
    fail(tech_name .. " is not infinite")
  end
  if #(tech.effects or {}) ~= 1 then
    fail(tech_name .. " should have exactly one recipe productivity effect")
  end
  local effect = tech.effects[1]
  if effect.type ~= "change-recipe-productivity" then
    fail(tech_name .. " effect is not recipe productivity")
  end
  if effect.recipe ~= recipe_name then
    fail(tech_name .. " targets " .. tostring(effect.recipe) .. " instead of " .. recipe_name)
  end
  if math.abs(tonumber(effect.change or 0) - 0.10) >= 0.000000001 then
    fail(tech_name .. " effect value is not +0.10")
  end
end

assert_single_recipe_effect("recipe-prod-research_pollution_filter_productivity-1", "atan-pollution-filter")

if data.raw.technology["recipe-prod-research_pollution_filter_productivity-1"].effects[1].recipe == "atan-pollution-filter-cleaning" then
  fail("pollution filter productivity matched the cleaning recipe")
end

if mods["space-age"] then
  assert_single_recipe_effect("recipe-prod-research_spore_filter_productivity-1", "atan-spore-filter")
  if data.raw.technology["recipe-prod-research_spore_filter_productivity-1"].effects[1].recipe == "atan-spore-filter-cleaning" then
    fail("spore filter productivity matched the cleaning recipe")
  end
elseif data.raw.technology["recipe-prod-research_spore_filter_productivity-1"] then
  fail("spore filter productivity generated without the spore filter prototype")
end

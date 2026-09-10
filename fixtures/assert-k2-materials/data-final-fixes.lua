-- Read-only final-prototype observer for the bounded A05 K2 material slice.
local material_technologies = {
  ["recipe-prod-research_material_rare_metals-1"] = {
    effects = { ["kr-rare-metals"] = 0.02, ["kr-rare-metals-from-enriched-rare-metals"] = 0.02 },
    science = "automation-science-pack,chemical-science-pack,logistic-science-pack",
    labs = "biolab,kr-advanced-lab,kr-singularity-lab,lab"
  },
  ["recipe-prod-research_material_silicon-1"] = {
    effects = { ["kr-silicon"] = 0.02 },
    science = "automation-science-pack,logistic-science-pack",
    labs = "biolab,kr-advanced-lab,kr-singularity-lab,lab"
  },
  ["recipe-prod-research_material_glass-1"] = {
    effects = { ["kr-glass"] = 0.02 },
    science = "automation-science-pack,chemical-science-pack,logistic-science-pack",
    labs = "biolab,kr-advanced-lab,kr-singularity-lab,lab"
  }
}

local function fail(message) error("MIR A05 K2 material qualification failed: " .. message) end
local function effects(technology)
  local out = {}
  for _, effect in ipairs((technology and technology.effects) or {}) do
    if effect.type == "change-recipe-productivity" then out[effect.recipe] = effect.change end
  end
  return out
end
local function effect_text(values)
  local out = {}
  for recipe, change in pairs(values) do out[#out + 1] = recipe .. "=" .. tostring(change) end
  table.sort(out)
  return table.concat(out, ",")
end
local function ingredient_text(technology)
  local out = {}
  for _, ingredient in ipairs((technology.unit and technology.unit.ingredients) or {}) do
    out[#out + 1] = ingredient.name or ingredient[1]
  end
  table.sort(out)
  return table.concat(out, ",")
end
local function labs_for(technology)
  local ingredients, out = {}, {}
  for _, ingredient in ipairs((technology.unit and technology.unit.ingredients) or {}) do ingredients[ingredient.name or ingredient[1]] = true end
  for name, lab in pairs(data.raw.lab) do
    local accepts = true
    local inputs = {}
    for _, input in ipairs(lab.inputs or {}) do inputs[input] = true end
    for ingredient in pairs(ingredients) do if not inputs[ingredient] then accepts = false end end
    if accepts then out[#out + 1] = name end
  end
  table.sort(out)
  return table.concat(out, ",")
end
local function amount(entries, type, name)
  for _, entry in ipairs(entries or {}) do
    if (entry.type or "item") == type and entry.name == name then return entry.amount end
  end
  return nil
end
local function owner_text(recipe)
  local out = {}
  for name, technology in pairs(data.raw.technology) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return table.concat(out, ",")
end
local function no_effect_for(recipe)
  for _, technology in pairs(data.raw.technology) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then return false end
    end
  end
  return true
end

for name, expected in pairs(material_technologies) do
  local technology = data.raw.technology[name]
  if not technology then fail("missing generated technology " .. name) end
  local actual = effects(technology)
  local count = 0
  for recipe, change in pairs(expected.effects) do
    count = count + 1
    if actual[recipe] ~= change or owner_text(recipe) ~= name then fail("owner or effect drift " .. name .. ":" .. recipe) end
  end
  local actual_count = 0
  for _ in pairs(actual) do actual_count = actual_count + 1 end
  if actual_count ~= count then fail("unexpected material effect " .. name) end
  if ingredient_text(technology) ~= expected.science or labs_for(technology) ~= expected.labs then fail("science or lab drift " .. name) end
  log("[MIR4_A05_K2_MATERIAL_TECH] name=" .. name .. ";effects=" .. effect_text(actual) .. ";science=" .. ingredient_text(technology) .. ";labs=" .. labs_for(technology))
end

if data.raw.technology["recipe-prod-research_material_black_paving-1"] or data.raw.technology["recipe-prod-research_material_white_paving-1"] then
  fail("paving productivity must remain withheld after final permission denial")
end
for _, name in ipairs({"kr-black-reinforced-plate", "kr-white-reinforced-plate"}) do
  local paving = assert(data.raw.recipe[name], "final paving recipe absent " .. name)
  if paving.allow_productivity == true or not no_effect_for(name) then
    fail("paving must remain final-denied and ownerless " .. name)
  end
end
local rare = assert(data.raw.recipe["kr-rare-metals"], "rare metals route absent")
local enriched = assert(data.raw.recipe["kr-rare-metals-from-enriched-rare-metals"], "enriched rare metals route absent")
local casting = assert(data.raw.recipe["kr-casting-rare-metals"], "casting route absent")
local silicon = assert(data.raw.recipe["kr-silicon"], "silicon route absent")
local glass = assert(data.raw.recipe["kr-glass"], "glass route absent")
if amount(rare.ingredients, "item", "kr-rare-metal-ore") ~= 2 or amount(rare.results, "item", "kr-rare-metals") ~= 1 then fail("rare metals final debulk shape differs") end
if amount(enriched.ingredients, "item", "kr-enriched-rare-metals") ~= 1 or amount(enriched.results, "item", "kr-rare-metals") ~= 1 then fail("enriched rare metals final debulk shape differs") end
if amount(silicon.ingredients, "item", "kr-quartz") ~= 18 or amount(silicon.results, "item", "kr-silicon") ~= 9 then fail("silicon final shape differs") end
if amount(glass.ingredients, "item", "kr-sand") ~= 16 or amount(glass.results, "item", "kr-glass") ~= 8 then fail("glass final shape differs") end
local dirty_water = nil
for _, result in ipairs(casting.results or {}) do if result.name == "kr-dirty-water" then dirty_water = result end end
if not dirty_water or dirty_water.ignored_by_productivity ~= 5 or not no_effect_for("kr-casting-rare-metals") then
  fail("casting must remain withheld for its ignored-by-productivity output")
end
for _, recipe in ipairs({rare,enriched,silicon,glass}) do
  if recipe.allow_productivity ~= true then fail("admitted final route lost effective productivity permission " .. recipe.name) end
end
local paving_targets = { ["kr-black-reinforced-plate"] = true, ["kr-white-reinforced-plate"] = true }
local function paving_entries(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    if paving_targets[entry.name] then out[#out + 1] = entry.name .. ":" .. tostring(entry.amount) end
  end
  table.sort(out)
  return table.concat(out, "+")
end
local paving_routes = {}
for name, recipe in pairs(data.raw.recipe) do
  local inputs, outputs = paving_entries(recipe.ingredients), paving_entries(recipe.results)
  if inputs ~= "" or outputs ~= "" then
    if recipe.allow_productivity == true or not no_effect_for(name) then fail("paving route must remain denied and ownerless " .. name) end
    local class = "manufacturing"
    if string.find(name, "recycl", 1, true) then class = "recycling"
    elseif string.find(name, "crush", 1, true) then class = "crushing"
    elseif inputs ~= "" and outputs ~= "" then class = "recolor-return" end
    paving_routes[#paving_routes + 1] = name .. "|class=" .. class .. "|permission=" .. tostring(recipe.allow_productivity) .. "|owner=" .. owner_text(name) .. "|in=" .. inputs .. "|out=" .. outputs
  end
end
table.sort(paving_routes)
if #paving_routes == 0 then fail("paving route set is empty") end
log("[MIR4_A05_K2_MATERIAL_PAVING_ROUTES] " .. table.concat(paving_routes, ","))
log("[MIR4_A05_K2_MATERIAL_ROUTE] rare=ore:2>rare:1;enriched:1>rare:1;silicon=quartz:18>silicon:9;glass=sand:16>glass:8;casting=dirty-water:ignored_by_productivity:5;black_paving=withheld-final-denial;white_paving=withheld-final-denial")
-- Exact F210 Bob Core progression recovered from the independent no-Angel
-- published 4.7.2 capture.  This is one finite binding: it neither collects
-- science packs nor derives another Bob profile from installed prototypes.
local M = {}

local PACK = "bob-advanced-logistic-science-pack"

local function effect(recipe)
  return {recipe=recipe, scale=1}
end

M.definition_overrides = {
  research_advanced_circuit = {
    icon = "__bobelectronics__/graphics/icons/technology/advanced-electronics.png",
    icon_size = 128,
  },
  research_science_pack_productivity = {
    science = "science_bob_core_science_pack_productivity",
    effects = {
      effect("agricultural-science-pack"),
      effect("automation-science-pack"),
      effect(PACK),
      effect("chemical-science-pack"),
      effect("cryogenic-science-pack"),
      effect("electromagnetic-science-pack"),
      effect("logistic-science-pack"),
      effect("metallurgic-science-pack"),
      effect("military-science-pack"),
      effect("production-science-pack"),
      effect("promethium-science-pack"),
      effect("space-science-pack"),
      effect("utility-science-pack"),
    },
  },
}

M.continuation_overrides = {
  braking_force = {science="science_bob_core_braking_force"},
  inserter_capacity_bonus = {science="science_bob_core_inserter_capacity"},
  research_speed = {science="science_bob_core_research_speed"},
  worker_robots_storage = {science="science_bob_core_worker_robots_storage"},
}

local function finite_positive(value)
  return type(value) == "number" and value == value and value > 0
    and value < math.huge and value > -math.huge
end

local function native_probability(result)
  if result.probability ~= nil and result.independent_probability ~= nil then return false end
  local probability = result.independent_probability
  if probability == nil then probability = result.probability end
  if probability ~= nil and (not finite_positive(probability) or probability > 1) then return false end
  local shared = result.shared_probability
  return shared == nil or (type(shared) == "table"
    and type(shared.min) == "number" and type(shared.max) == "number"
    and shared.min == shared.min and shared.max == shared.max
    and shared.min >= 0 and shared.max <= 1 and shared.min < shared.max)
end

local function positive_pack_output(recipe)
  local results = type(recipe) == "table" and recipe.results or nil
  for _, result in ipairs(type(results) == "table" and results or {}) do
    if type(result) == "table" and result.type == "item" and result.name == PACK
      and finite_positive(result.amount) and native_probability(result) then return true end
  end
  return false
end

local function owns_unlock(owner)
  local effects = type(owner) == "table" and owner.effects or nil
  local count = 0
  for _, effect in ipairs(type(effects) == "table" and effects or {}) do
    if type(effect) == "table" and effect.type == "unlock-recipe" and effect.recipe == PACK then
      count = count + 1
    end
  end
  return count == 1
end

-- Check only the named dependency that makes this profile-specific science
-- vector meaningful.  It runs through research.modern's existing preflight
-- before any MIR prototype publication.
function M.preflight(raw)
  if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table"
      or type(raw.technology) ~= "table" then
    error("MIR F210 Bob Core progression raw prototypes are unavailable", 2)
  end
  if type(raw.item[PACK]) ~= "table" then
    error("MIR F210 Bob Core progression missing named science pack " .. PACK, 2)
  end
  local recipe = raw.recipe[PACK]
  if type(recipe) ~= "table" or recipe.enabled ~= false or recipe.hidden == true
      or recipe.allow_productivity ~= true or not positive_pack_output(recipe) then
    error("MIR F210 Bob Core progression named science recipe changed: " .. PACK, 2)
  end
  local owner = raw.technology[PACK]
  if type(owner) ~= "table" or owner.enabled == false or not owns_unlock(owner) then
    error("MIR F210 Bob Core progression named science owner changed: " .. PACK, 2)
  end
end

return M

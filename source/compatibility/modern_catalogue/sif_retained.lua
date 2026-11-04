-- Published F200/SIF1.0.60 paid identities. Selection and preflight are pure;
-- research.modern alone emits the detached hidden technologies.
local M = {}
local CREDIT_CONTRACTS = require("research.native_credit_contracts")
local CONTRACTS = CREDIT_CONTRACTS.published_sif_contracts()

-- The exact published five-identity source is also the authority for its
-- first native-credit baseline. Return names only, never prototype mutations.
M.paid_recipe_sets = CREDIT_CONTRACTS.published_sif_paid_recipe_sets

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, field in pairs(value) do out[key] = copy(field) end
  return out
end

local function fail(key, reason)
  error("MIR SIF retained " .. key .. ": " .. reason, 3)
end

-- A profile that already emits an identity needs no second holder. Only the
-- missing historical identities receive the fixed published effect vector.
function M.select(base_definitions, selected_definitions)
  local base, selected, out = {}, {}, {}
  for _, definition in ipairs(base_definitions) do base[definition.key] = definition end
  for _, definition in ipairs(selected_definitions) do selected[definition.key] = true end
  for _, contract in ipairs(CONTRACTS) do
    if not selected[contract.key] then
      if not base[contract.key] then fail(contract.key, "authored base definition absent") end
      local definition = copy(base[contract.key])
      definition.effects = {}
      for _, route in ipairs(contract.recipes) do
        definition.effects[#definition.effects + 1] = {recipe=route[1], scale=1}
      end
      out[#out + 1] = definition
    end
  end
  return out
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive_product(recipe, product)
  if recipe.allow_productivity == false or type(recipe.results) ~= "table" then return false end
  for _, result in ipairs(recipe.results) do
    if type(result) == "table" and (result.type == nil or result.type == "item") and result.name == product then
      local amount = result.amount
      if amount == nil and finite(result.amount_min) and finite(result.amount_max)
          and result.amount_min >= 0 and result.amount_max >= result.amount_min then
        amount = (result.amount_min + result.amount_max) / 2
      end
      local probability = result.probability == nil and 1 or result.probability
      local ignored = result.ignored_by_productivity == nil and 0 or result.ignored_by_productivity
      if finite(amount) and finite(probability) and finite(ignored)
          and amount > ignored and ignored >= 0 and probability > 0 and probability <= 1 then return true end
    end
  end
  return false
end

-- Inspect only the eleven named recipes and six named native owners. Do not
-- discover owners, mutate their fields, or infer a wider modpack contract.
function M.preflight(definitions, raw, native_owners)
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
    fail("coverage", "recipe/technology tables absent")
  end
  local contracts = {}
  local owner_recipes, checked_owners = {}, {}
  for _, contract in ipairs(CONTRACTS) do
    contracts[contract.key] = contract
    for _, route in ipairs(contract.recipes) do
      owner_recipes[route[2]] = owner_recipes[route[2]] or {}
      owner_recipes[route[2]][route[1]] = true
    end
  end
  local bindings = {}
  for _, binding in ipairs(native_owners or {}) do
    if contracts[binding.family] then
      if bindings[binding.family] then fail(binding.family, "duplicate native binding") end
      bindings[binding.family] = binding
    end
  end
  local function owner_coverage(name, key)
    if checked_owners[name] then return checked_owners[name] end
    local owner = raw.technology[name]
    if type(owner) ~= "table" or owner.name ~= name or owner.type ~= "technology"
        or owner.enabled == false or owner.hidden == true or owner.max_level ~= "infinite"
        or type(owner.effects) ~= "table" then fail(key, "native owner " .. name) end
    local counts = {}
    for recipe in pairs(owner_recipes[name]) do counts[recipe] = 0 end
    for _, effect in ipairs(owner.effects) do
      if type(effect) == "table" and effect.type == "change-recipe-productivity"
          and counts[effect.recipe] ~= nil then
        counts[effect.recipe] = counts[effect.recipe] + 1
        if not finite(effect.change) or effect.change <= 0 then fail(key, "owner effect " .. effect.recipe) end
      end
    end
    checked_owners[name] = counts
    return counts
  end
  for _, definition in ipairs(definitions) do
    local contract = contracts[definition.key]
    if not contract then fail("identity", "unrecognized retained definition") end
    local main_owner
    for _, route in ipairs(contract.recipes) do if route[1] == contract.product then main_owner = route[2] end end
    local binding = bindings[contract.key]
    if not binding or binding.id ~= main_owner or type(binding.admission) ~= "table"
        or binding.admission.effect_type ~= "change-recipe-productivity"
        or type(binding.admission.recipes) ~= "table" then fail(contract.key, "native binding") end
    local admitted = {}
    for _, recipe in ipairs(binding.admission.recipes) do
      if admitted[recipe] or owner_recipes[main_owner][recipe] ~= true then fail(contract.key, "binding coverage") end
      admitted[recipe] = true
    end
    for recipe in pairs(owner_recipes[main_owner]) do
      if not admitted[recipe] then fail(contract.key, "binding coverage " .. recipe) end
    end
    for _, route in ipairs(contract.recipes) do
      local recipe = raw.recipe[route[1]]
      if type(recipe) ~= "table" or recipe.name ~= route[1] or recipe.type ~= "recipe"
          or not positive_product(recipe, contract.product) then fail(contract.key, "recipe coverage " .. route[1]) end
      if owner_coverage(route[2], contract.key)[route[1]] ~= 1 then
        fail(contract.key, "owner coverage " .. route[1])
      end
    end
  end
end

return M

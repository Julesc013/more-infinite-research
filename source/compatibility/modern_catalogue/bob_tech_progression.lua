-- Named F210 BobTech continuation science. Settings/runtime need identities
-- only; the data-stage caller supplies raw for the finite alien-lab variant.
local target = require("platform.target")
local M = {}
local ALIEN = {"bob-alien-science-pack", "bob-alien-science-pack-blue", "bob-alien-science-pack-green",
  "bob-alien-science-pack-orange", "bob-alien-science-pack-purple", "bob-alien-science-pack-red",
  "bob-alien-science-pack-yellow", "bob-science-pack-gold"}

function M.select(active)
  if target.id ~= "f210" or type(active) ~= "table" or active.bobtech == nil
      or active.angelssmelting ~= nil or active.Krastorio2 ~= nil or active["space-exploration"] ~= nil
      or active["Krastorio2-spaced-out"] ~= nil or active.pycoalprocessing ~= nil then return nil end
  return active["space-age"] ~= nil and "space-age" or "base"
end

local function alien_variant(raw)
  return type(raw) == "table" and type(raw.technology) == "table"
    and raw.technology["bob-alien-research"] ~= nil
end

function M.continuation_overrides(active, raw)
  local profile = M.select(active)
  if profile == nil then return {} end
  if profile == "space-age" then
    return require("compatibility.modern_catalogue.bob_core").continuation_overrides
  end
  local overrides = {
    braking_force = {science="science_bob_base_logistics"},
    inserter_capacity_bonus = {science="science_bob_base_logistics"},
    research_speed = {science="science_bob_base_research_speed"},
    worker_robots_storage = {science="science_bob_base_logistics"},
  }
  if alien_variant(raw) then
    overrides.research_speed = {science="science_bob_base_alien_research",
      prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "bob-alien-research"},
      exact_prerequisites=true}
  end
  return overrides
end

local function fail(message) error("MIR F210 BobTech progression " .. message, 3) end

function M.preflight(raw, profile)
  if profile ~= "base" and profile ~= "space-age" then fail("profile is invalid") end
  require("compatibility.modern_catalogue.bob_core").preflight(raw)
  if profile ~= "base" or not alien_variant(raw) then return end
  local owner = raw.technology["bob-alien-research"]
  local lab = type(raw.lab) == "table" and raw.lab["bob-lab-alien"] or nil
  if type(owner) ~= "table" or owner.enabled == false or type(lab) ~= "table" then
    fail("named alien research owner/lab changed")
  end
  local inputs, unlocks = {}, {}
  for _, name in ipairs(lab.inputs or {}) do inputs[name] = true end
  for _, effect in ipairs(owner.effects or {}) do
    if effect.type == "unlock-recipe" then unlocks[effect.recipe] = (unlocks[effect.recipe] or 0) + 1 end
  end
  for _, name in ipairs(ALIEN) do
    local recipe = raw.recipe[name]
    if type(raw.item[name]) ~= "table" or not inputs[name] or unlocks[name] ~= 1
        or type(recipe) ~= "table" or recipe.enabled ~= false or recipe.hidden == true then
      fail("named alien science route changed: " .. name)
    end
    local found = false
    for _, product in ipairs(recipe.results or {}) do
      if product.type == "item" and product.name == name and type(product.amount) == "number"
          and product.amount > 0 and product.amount < math.huge then found = true end
    end
    if not found then fail("named alien science output changed: " .. name) end
  end
end

return M

-- Restore the single published Marine carbonisation declaration. No recipe,
-- technology or upstream lifecycle is changed here; Generator owns publication.
local profile = require("integrations.ric.profile")
local cost = require("research.cost")
local target = require("platform.target")
local return_paths = require("integrations.ric.return_paths")
local M = {}
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function fail(message)
  error("MIR RIC Marine carbonisation: " .. message, 3)
end

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Quantities remain upstream-owned. Only this ordinary typed input/output set
-- is admitted; the separate bounded check retains the no-return condition.
local function ordinary_entries(actual, names, product)
  if type(actual) ~= "table" or #actual ~= #names then return false end
  local expected, seen = {}, {}
  for _, name in ipairs(names) do expected[name] = true end
  for _, entry in ipairs(actual) do
    if type(entry) ~= "table" then return false end
    local name, amount = entry.name or entry[1], entry.amount or entry[2]
    if (entry.type or "item") ~= "item" or expected[name] ~= true or seen[name]
        or not positive(amount) or amount ~= math.floor(amount)
        or entry.amount_min ~= nil or entry.amount_max ~= nil
        or (entry.probability ~= nil and entry.probability ~= 1)
        or (entry.independent_probability ~= nil and entry.independent_probability ~= 1)
        or entry.shared_probability ~= nil
        or (entry.catalyst_amount ~= nil and entry.catalyst_amount ~= 0)
        or (product and ((entry.ignored_by_productivity ~= nil and entry.ignored_by_productivity ~= 0)
          or (entry.ignored_by_stats ~= nil and entry.ignored_by_stats ~= 0)
          or (entry.extra_count_fraction ~= nil and entry.extra_count_fraction ~= 0))) then return false end
    seen[name] = true
  end
  return true
end

local function binding(raw)
  local recipes = type(raw) == "table" and raw.recipe
  local technologies = type(raw) == "table" and raw.technology
  local items = type(raw) == "table" and raw.item
  local recipe = type(recipes) == "table" and recipes[profile.recipe]
  if type(recipe) ~= "table" or recipe.name ~= profile.recipe or recipe.type ~= "recipe"
      or recipe.normal ~= nil or recipe.expensive ~= nil
      or recipe.hidden == true or recipe.allow_productivity ~= true
      or (recipe.maximum_productivity ~= nil and not positive(recipe.maximum_productivity))
      or not ordinary_entries(recipe.ingredients, {"ric-dried-marine-biomass"})
      or not ordinary_entries(recipe.results, {"ric-coke", "ric-ash"}, true) then
    fail("the named forward recipe is absent or has unsupported inputs/outputs")
  end
  local owner = type(technologies) == "table" and technologies[profile.owner]
  local unit = type(owner) == "table" and owner.unit
  local science = type(unit) == "table" and unit.ingredients
  local red = type(science) == "table" and science[1]
  if type(science) ~= "table" or #science ~= 1 or type(red) ~= "table"
      or (red.name or red[1]) ~= "automation-science-pack" or (red.amount or red[2]) ~= 1 then
    fail("the named coking owner no longer has the authored automation-science vector")
  end
  local unlocked = false
  for _, effect in ipairs(owner.effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == profile.recipe then unlocked = true end
  end
  if not unlocked then fail("the named coking owner no longer unlocks carbonisation") end
  -- The retained unique-owner assertion requires one optional flat pass over
  -- direct technology effects. It selects no owner, follows no graph edges,
  -- and runs only for this active Marine binding, never at runtime.
  for name, technology in pairs(technologies) do
    if name ~= profile.id then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "change-recipe-productivity" and effect.recipe == profile.recipe then
          fail("another technology already supplies carbonisation productivity: " .. name)
        end
      end
    end
  end
  local item = type(items) == "table" and items["ric-coke"]
  if type(item) ~= "table" then fail("the named coke item is unavailable") end
  -- Art is not a gameplay admission gate. A composite/missing simple icon uses
  -- the shipped core productivity glyph without changing upstream art fields.
  if type(item.icon) == "string" and item.icon ~= "" and (item.icon_size == nil
      or (positive(item.icon_size) and item.icon_size == math.floor(item.icon_size))) then
    return item.icon, item.icon_size or 64
  end
end

function M.technologies(values, raw, active_mods, startup, return_context)
  if not profile.applies(active_mods, target) then return {} end
  local mode = type(startup) == "table" and startup["ric-world-mode"]
  if type(mode) ~= "table" or (mode.value ~= "marine" and mode.value ~= "continental") then
    fail("RIC world mode is unavailable")
  end
  if mode.value == "continental" then return {} end
  local icon, icon_size = binding(raw)
  return_paths.validate(raw, return_context and return_context())
  local stream = values and values.streams and values.streams[profile.family]
  if type(stream) ~= "table" or type(stream.enabled) ~= "boolean" then fail("resolved settings are unavailable") end
  local time = stream.research_time == 0 and 30 or stream.research_time
  local icons = {{icon=OVERLAY, icon_size=128}}
  if icon then
    icons = {{icon=icon, icon_size=icon_size},
      {icon=OVERLAY, icon_size=128, scale=0.5, shift={50, 50}, floating=true}}
  end
  return {{
    type="technology", name=profile.id, level=1, upgrade=true, max_level="infinite", order=profile.order,
    icons=icons,
    localised_name={"", {"description.productivity-bonus"}, ": ", {"recipe-name." .. profile.recipe}},
    localised_description={"technology-description.more-infinite-research.recipe_productivity"},
    prerequisites={profile.owner}, effects={{type="change-recipe-productivity", recipe=profile.recipe,
      change=stream.effect_percent / 100}},
    unit={count_formula=cost.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time=time, ingredients={{"automation-science-pack", 1}}},
    enabled=stream.enabled,
  }}
end

return M

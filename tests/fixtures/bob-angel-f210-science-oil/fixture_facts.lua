-- Finite independent F210 Bob+Angel facts.  q009/q010 supply the named
-- research-speed progression; intent r01 supplies the reviewed oil identity
-- and the static-seed-plus-COMP-02 science-product effect vectors.
local M = {}

M.fixture = "mir-fixture-mir5-bob-angel-f210-science-oil"
M.mir = "more-infinite-research"
M.mir_version = "5.0.21000"
M.base_version = "2.1.23"
M.science = "recipe-prod-research_science_pack_productivity-1"
M.oil = "recipe-prod-research_oil_cracking_productivity-1"
M.oil_level = 3
M.oil_saved_progress = .27
M.foreign_oil_level = 2
M.foreign_oil_saved_progress = .42
M.foreign_queue_progress = .42
M.lab_initial = 32
M.deadline_ticks = 36000

local base_mods = {
  ["angelsaddons-mobility"]="2.1.1", ["angelsaddons-mobility-graphics-crawler"]="2.1.0",
  ["angelsaddons-mobility-graphics-petro"]="2.1.0", ["angelsaddons-mobility-graphics-smelting"]="2.1.0",
  ["angelsaddons-storage"]="2.1.1", angelsbioprocessing="2.1.2", angelsbioprocessinggraphics="2.1.0",
  angelsinfiniteores="2.1.0", angelspetrochem="2.1.3", angelspetrochemgraphics="2.1.0",
  angelsrefining="2.1.3", angelsrefininggraphics="2.1.0", angelssmelting="2.1.1",
  angelssmeltinggraphics="2.1.1", base="2.1.23", bobassembly="3.0.2", bobelectronics="3.0.1",
  bobenemies="3.0.1", bobequipment="3.0.0", bobgreenhouse="3.0.1", bobinserters="3.0.0",
  boblibrary="3.0.1", boblogistics="3.0.2", bobmining="3.0.2", bobmodules="3.0.1",
  bobores="3.0.0", bobplates="3.0.2", bobpower="3.0.1", bobrevamp="3.0.1", bobtech="3.0.0",
  bobvehicleequipment="3.0.0", bobwarfare="3.0.2",
  ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
  [M.mir]=M.mir_version, [M.fixture]="0.1.0",
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, nested in pairs(value) do out[key] = copy(nested) end
  return out
end

local function effects(names)
  local out = {}
  for _, name in ipairs(names) do out[#out + 1] = {type="change-recipe-productivity", recipe=name, change=.1} end
  return out
end

local base_science_effects = {
  "automation-science-pack", "chemical-science-pack", "logistic-science-pack", "military-science-pack",
  "production-science-pack", "utility-science-pack", "angels-desert-garden-a",
  "angels-desert-garden-cultivating-a", "angels-swamp-garden-a", "angels-swamp-garden-cultivating-a",
  "angels-temperate-garden-a", "angels-temperate-garden-cultivating-a",
  "bob-advanced-logistic-science-pack", "bob-alien-science-pack", "bob-alien-science-pack-blue",
  "bob-alien-science-pack-green", "bob-alien-science-pack-orange", "bob-alien-science-pack-purple",
  "bob-alien-science-pack-red", "bob-alien-science-pack-yellow", "bob-science-pack-gold",
}

local space_science_effects = {
  "agricultural-science-pack", "automation-science-pack", "chemical-science-pack", "cryogenic-science-pack",
  "electromagnetic-science-pack", "logistic-science-pack", "metallurgic-science-pack", "military-science-pack",
  "production-science-pack", "promethium-science-pack", "space-science-pack", "utility-science-pack",
  "angels-desert-garden-a", "angels-desert-garden-cultivating-a", "angels-swamp-garden-a",
  "angels-swamp-garden-cultivating-a", "angels-temperate-garden-a", "angels-temperate-garden-cultivating-a",
  "bob-advanced-logistic-science-pack", "bob-alien-science-pack", "bob-alien-science-pack-blue",
  "bob-alien-science-pack-green", "bob-alien-science-pack-orange", "bob-alien-science-pack-purple",
  "bob-alien-science-pack-red", "bob-alien-science-pack-yellow", "bob-science-pack-gold",
}

local base_vector = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "utility-science-pack", "military-science-pack", "angels-token-bio", "bob-advanced-logistic-science-pack",
}
local space_vector = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "utility-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack",
  "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
  "angels-token-bio", "bob-advanced-logistic-science-pack",
}
local base_prerequisites = {
  "research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
  "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
  "angels-gardens", "bob-advanced-logistic-science-pack",
}
local space_prerequisites = {
  "research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
  "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack",
  "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack", "promethium-science-pack", "angels-gardens", "bob-advanced-logistic-science-pack",
}

local function closure(space_age)
  local mods = copy(base_mods)
  if space_age then
    mods["elevated-rails"]="2.1.23"; mods.quality="2.1.23"; mods.recycler="2.1.23"; mods["space-age"]="2.1.23"
  end
  local vector, prerequisites, effect_names = base_vector, base_prerequisites, base_science_effects
  local icon = "__base__/graphics/technology/space-science-pack.png"
  if space_age then vector, prerequisites, effect_names = space_vector, space_prerequisites, space_science_effects
    icon = "__space-age__/graphics/technology/research-productivity.png" end
  return {id=space_age and "space-age" or "base", mods=mods, vector=copy(vector), prerequisites=copy(prerequisites),
    effects=effects(effect_names), science_icon=icon, science_icon_size=256}
end

M.base = closure(false)
M.space_age = closure(true)
M.oil_effects = effects({"heavy-oil-cracking", "light-oil-cracking"})
M.oil_prerequisites = {"automation-science-pack", "logistic-science-pack"}

function M.closure(active_mods)
  if active_mods["space-age"] == "2.1.23" then return M.space_age end
  return M.base
end

return M

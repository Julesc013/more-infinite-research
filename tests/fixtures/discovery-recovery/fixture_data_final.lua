-- Finite data-stage admission for the named 3.2.x discovery repair witness.
-- Source science/prerequisites remain the emitted row; the fixture changes
-- only the two lab-duration fields after identity/effect preflight.
local M = {}

local FIXTURE = "mir-fixture-discovery-recovery"
local IRON = "recipe-prod-research_iron-1"
local DISCOVERY = "planet-discovery-vulcanus"

local function fail(message) error("[mir-fixture-discovery-recovery] " .. message) end

local function source_version()
  local version = mods["more-infinite-research"]
  local fixture = mods[FIXTURE]
  if (version == "3.2.0" and fixture == "0.1.0") or (version == "3.2.1" and fixture == "0.1.1") then
    return version
  end
  return nil
end

local function exact_official_closure(stage)
  local expected = {
    base = "2.1.23", ["space-age"] = "2.1.23", quality = "2.1.23",
    ["elevated-rails"] = "2.1.23", recycler = "2.1.23",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0",
  }
  for name, version in pairs(expected) do
    if mods[name] ~= version then fail("official Space Age closure differs: " .. name) end
  end
  if stage == "source" then
    if source_version() == nil then fail("source MIR/fixture version pair differs") end
  elseif mods["more-infinite-research"] ~= "5.0.21000" or mods[FIXTURE] ~= "0.2.0" then
    fail("MIR5 successor/fixture version pair differs")
  end
  expected["more-infinite-research"], expected[FIXTURE] = mods["more-infinite-research"], mods[FIXTURE]
  for name in pairs(mods) do
    if expected[name] == nil then fail("unexpected active mod in fixture closure: " .. tostring(name)) end
  end
end

local function assert_iron(row)
  if type(row) ~= "table" or row.name ~= IRON or row.type ~= "technology" or row.level ~= 1
      or row.upgrade ~= true or row.max_level ~= "infinite" or row.enabled == false then
    fail("historical iron technology identity differs")
  end
  local expected, seen = {['iron-plate'] = true, ['casting-iron'] = true}, {}
  for _, effect in pairs(row.effects or {}) do
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or expected[effect.recipe] ~= true or effect.change ~= .1 or seen[effect.recipe] then
      fail("historical Space Age iron productivity effect differs")
    end
    seen[effect.recipe] = true
  end
  for recipe in pairs(expected) do
    if seen[recipe] ~= true then fail("historical Space Age iron productivity effect differs") end
  end
  local unit = row.unit
  if type(unit) ~= "table" or unit.count ~= nil or unit.count_formula ~= "8000*2^(L-1)" or unit.time ~= 60
      or type(unit.ingredients) ~= "table" or #unit.ingredients == 0 then
    fail("historical iron unit or emitted science differs")
  end
  return unit
end

local function assert_discovery(row, version)
  if type(row) ~= "table" or row.name ~= DISCOVERY or row.type ~= "technology" then
    fail("source Vulcanus discovery technology is absent")
  end
  local effects = row.effects
  if type(effects) ~= "table" then fail("source Vulcanus discovery effect differs") end
  if version == "3.2.0" then
    local effect = effects[1]
    if #effects ~= 1 or type(effect) ~= "table" or effect.type ~= "unlock-travel-to-space-platforms"
        or effect.modifier ~= true then
      fail("source Vulcanus discovery effect differs")
    end
  elseif version == "3.2.1" then
    local unlock, travel = effects[1], effects[2]
    if #effects ~= 2 or type(unlock) ~= "table" or unlock.type ~= "unlock-space-location"
        or unlock.space_location ~= "vulcanus"
        or type(travel) ~= "table" or travel.type ~= "unlock-travel-to-space-platforms"
        or travel.modifier ~= true then
      fail("source Vulcanus discovery effect differs")
    end
  else
    fail("source Vulcanus discovery effect differs")
  end
  local unit = row.unit
  if type(unit) ~= "table" or type(unit.time) ~= "number" or unit.time <= 0
      or (type(unit.count) ~= "number" and type(unit.count_formula) ~= "string")
      or type(unit.ingredients) ~= "table" or #unit.ingredients == 0 then
    fail("source Vulcanus discovery unit differs")
  end
  return unit
end

function M.apply(stage)
  if stage ~= "source" and stage ~= "successor" then fail("unknown fixture data stage") end
  exact_official_closure(stage)
  local iron_unit = assert_iron(data.raw.technology and data.raw.technology[IRON])
  if stage == "source" then
    local discovery_unit = assert_discovery(data.raw.technology and data.raw.technology[DISCOVERY], source_version())
    discovery_unit.count_formula, discovery_unit.count, discovery_unit.time = nil, 1, 1
  else
    -- A five-second current lab preserves a representable 42-percent queue
    -- witness without changing a source row or claiming any tool quantity.
    iron_unit.count_formula, iron_unit.count, iron_unit.time = nil, 1, 5
  end
end

return M

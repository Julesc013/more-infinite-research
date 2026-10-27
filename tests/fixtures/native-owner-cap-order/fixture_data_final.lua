-- Shared data-final preflight.  Only the permuted stage mutates the owned
-- prototype, after proving the exact canonical native-owner input.
local M = {}

local NAME = "steel-plate-productivity"
local FIXTURE = "mir-fixture-mir5-native-owner-cap-order"
local CLOSURE = {"base", "elevated-rails", "quality", "recycler", "space-age"}
local STAGES = {
  source = {version = "0.0.1", cap = 0, permuted = false},
  canonical = {version = "0.1.0", cap = 1, permuted = false},
  permuted = {version = "0.2.0", cap = 1, permuted = true},
  relaxed = {version = "0.3.0", cap = 0, permuted = false},
}
local EXPECTED = {
  {type = "change-recipe-productivity", recipe = "steel-plate", change = 0.1},
  {type = "change-recipe-productivity", recipe = "casting-steel", change = 0.1},
}

local function fail(message)
  error("[mir5-native-owner-cap-order] " .. message)
end

local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.0000001
end

local function assert_closure(expected)
  for _, name in ipairs(CLOSURE) do
    if mods[name] ~= "2.1.23" then fail("F210 Space Age closure differs: " .. name) end
  end
  if mods["more-infinite-research"] ~= "5.0.21000" or mods[FIXTURE] ~= expected.version then
    fail("fixture stage closure differs")
  end
end

local function assert_effects(row)
  if type(row.effects) ~= "table" or #row.effects ~= #EXPECTED then fail("steel native-owner effect count differs") end
  for index, expected in ipairs(EXPECTED) do
    local actual = row.effects[index]
    if type(actual) ~= "table" or actual.type ~= expected.type or actual.recipe ~= expected.recipe
        or not close(actual.change, expected.change) then
      fail("steel native-owner effect differs at " .. tostring(index))
    end
  end
end

function M.apply(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown data-final stage") end
  assert_closure(expected)
  local technology = data.raw.technology and data.raw.technology[NAME]
  -- Setting prototypes exist only during the settings stage.  At data-final
  -- use the effective startup value that the engine exposes to this stage.
  local startup = settings.startup
  local setting = startup and startup["ips-max-level-research_steel"]
  if type(technology) ~= "table" or technology.name ~= NAME or technology.max_level ~= "infinite" then
    fail("steel native owner is absent or finite")
  end
  if type(setting) ~= "table" or setting.value ~= expected.cap then
    fail("steel cap setting differs")
  end
  assert_effects(technology) -- All fixture writes are below this preflight.
  if expected.permuted then technology.effects = {technology.effects[2], technology.effects[1]} end
end

return M

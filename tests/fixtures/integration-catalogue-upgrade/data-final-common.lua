-- Shared original-field guard for the disposable integration catalogue fixture.
-- It validates recorded published rows before changing only selected lab units.
return function(stage, mir)
  local FIXTURE = "mir-fixture-mir5-integration-catalogue-upgrade"
  local PLAN = require("__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue")
  local function fail(message) error("[mir5-integration-catalogue-upgrade] " .. message) end
  local function same(actual, expected)
    if type(actual) ~= type(expected) then return false end
    if type(expected) ~= "table" then return actual == expected end
    for key, value in pairs(expected) do if not same(actual[key], value) then return false end end
    for key in pairs(actual) do if expected[key] == nil then return false end end
    return true
  end
  local function profile()
    if mods.bobwarfare ~= nil then
      if mods.bobwarfare ~= "2.1.0" or mods.boblibrary ~= "2.1.0"
          or mods.pycoalprocessing ~= nil or mods.pyalienlife ~= nil or mods.pyhightech ~= nil then
        fail("Bob Warfare profile closure differs")
      end
      return PLAN.profiles["armor-bobwarfare"]
    end
    if mods.pyhightech ~= nil or mods.pyalienlife ~= nil then
      if mods.pycoalprocessing ~= "3.0.44" or mods.pyalienlife ~= "3.0.67" or mods.pyhightech ~= "3.0.19"
          or mods.bobwarfare ~= nil then fail("Py AlienLife/HighTech profile closure differs") end
      return PLAN.profiles["py-alienlife-hightech"]
    end
    if mods.pycoalprocessing ~= nil then
      if mods.pycoalprocessing ~= "3.0.44" or mods.bobwarfare ~= nil then fail("Py Coal profile closure differs") end
      return PLAN.profiles["py-coal"]
    end
    fail("fixture has no admitted integration profile")
  end
  if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= mir or mods[FIXTURE] ~= (stage == "published-4.7" and "0.1.0" or "0.2.0") then
    fail("fixture stage closure differs")
  end
  local selected = profile()
  for _, name in ipairs(selected.preflight_names) do
    local actual = data.raw.technology and data.raw.technology[name]
    if type(actual) ~= "table" or not same(actual, selected.preflight[name]) then
      fail("published row differs before acceleration: " .. name)
    end
  end
  for _, name in ipairs({selected.primary, selected.continuation}) do
    local unit = data.raw.technology[name].unit
    unit.count, unit.count_formula, unit.time = nil, "1", 1
  end
end

-- Portable Lua 5.2 control for the pre-0.13 data-only adapter.  It models
-- the actual finite museum defaults without claiming a native engine result.
local M = {}

local expected = {
  f006 = {
    {key="inserter-capacity", levels=5, prerequisite="inserter-stack-size-bonus-4", icon="__base__/graphics/technology/inserter-stack-size-bonus.png", effect="inserter-stack-size-bonus", modifier=1, count=400, increment=200, time=45},
    {key="rocket-shooting-speed", levels=5, prerequisite="rocket-speed-5", icon="__base__/graphics/technology/rocket-speed.png", effect="gun-speed", ammo_category="rocket", modifier=.15, count=500, increment=250, time=60},
    {key="rocket-damage", levels=4, prerequisite="rocket-damage-5", icon="__base__/graphics/technology/rocket-damage.png", effect="ammo-damage", ammo_category="rocket", modifier=.2, count=500, increment=250, time=60},
  },
  f007 = {
    {key="inserter-capacity", levels=5, prerequisite="inserter-stack-size-bonus-4", icon="__base__/graphics/technology/inserter-stack-size-bonus.png", effect="inserter-stack-size-bonus", modifier=1, count=400, increment=200, time=45},
    {key="gun-turret-damage", levels=5, prerequisite="gun-turret-damage-6", icon="__base__/graphics/technology/gun-turret-damage.png", effect="turret-attack", turret_id="gun-turret", modifier=.2, count=500, increment=250, time=60},
    {key="bullet-shooting-speed", levels=5, prerequisite="bullet-speed-6", icon="__base__/graphics/technology/bullet-speed.png", effect="gun-speed", ammo_category="bullet", modifier=.15, count=500, increment=250, time=60},
    {key="bullet-damage", levels=5, prerequisite="bullet-damage-6", icon="__base__/graphics/technology/bullet-damage.png", effect="ammo-damage", ammo_category="bullet", modifier=.2, count=500, increment=250, time=60},
    {key="toolbelt", levels=2, prerequisite="toolbelt", icon="__base__/graphics/technology/toolbelt.png", effect="num-quick-bars", modifier=1, count=600, increment=300, time=45},
  },
  f012 = {
    {key="inserter-capacity", levels=5, prerequisite="inserter-stack-size-bonus-4", icon="__base__/graphics/technology/inserter-stack-size-bonus.png", effect="inserter-stack-size-bonus", modifier=1, count=400, increment=200, time=45},
    {key="gun-turret-damage", levels=5, prerequisite="gun-turret-damage-6", icon="__base__/graphics/technology/gun-turret-damage.png", effect="turret-attack", turret_id="gun-turret", modifier=.2, count=500, increment=250, time=60},
    {key="bullet-shooting-speed", levels=5, prerequisite="bullet-speed-6", icon="__base__/graphics/technology/bullet-speed.png", effect="gun-speed", ammo_category="bullet", modifier=.15, count=500, increment=250, time=60},
    {key="bullet-damage", levels=5, prerequisite="bullet-damage-6", icon="__base__/graphics/technology/bullet-damage.png", effect="ammo-damage", ammo_category="bullet", modifier=.2, count=500, increment=250, time=60},
    {key="toolbelt", levels=3, prerequisite="toolbelt", icon="__base__/graphics/technology/toolbelt.png", effect="num-quick-bars", modifier=1, count=600, increment=300, time=45},
    {key="logistic-trash-slots", levels=3, prerequisite="character-logistic-trash-slots-2", icon="__base__/graphics/technology/character-logistic-trash-slots.png", effect="character-logistic-trash-slots", modifier=5, count=600, increment=300, time=45},
  },
}
expected.f008, expected.f009, expected.f010, expected.f011 = expected.f007, expected.f007, expected.f007, expected.f007

local science = {"science-pack-1", "science-pack-2", "science-pack-3", "alien-science-pack"}

local function target(id)
  return {id=id, reduced=true, research_levels=false, recipe_productivity=false}
end

local function raw_for(id)
  local raw = {technology={}, tool={}}
  for _, family in ipairs(expected[id]) do raw.technology[family.prerequisite] = {type="technology"} end
  for _, name in ipairs(science) do raw.tool[name] = {type="tool"} end
  return raw
end

local function reset_adapter()
  package.loaded["adapters.early.data"] = nil
  package.loaded["adapters.early.definitions"] = nil
end

local function invoke(value, raw)
  reset_adapter()
  local calls, emitted = 0, nil
  _G.early_extend_calls = 0
  _G.data = {raw=raw}
  function _G.data:extend(rows)
    calls, emitted = calls + 1, rows
    _G.early_extend_calls = calls
  end
  require("adapters.early.data").apply(value)
  return calls, emitted
end

local function expect_failure(callback)
  local ok = pcall(callback)
  assert(not ok, "expected early adapter rejection")
  assert(_G.early_extend_calls == 0, "rejected early adapter input wrote prototypes")
end

local function assert_family_rows(id, rows)
  local cursor = 1
  for _, family in ipairs(expected[id]) do
    for level = 1, family.levels do
      local actual = rows[cursor]
      assert(actual.type == "technology" and actual.name == "mir-" .. family.key .. "-" .. level)
      assert(actual.icon == family.icon and actual.localised_name == nil and actual.max_level == nil)
      assert(actual.unit.count == family.count + family.increment * (level - 1) and actual.unit.count_formula == nil and actual.unit.time == family.time)
      assert(#actual.unit.ingredients == 4)
      for index, name in ipairs(science) do
        assert(actual.unit.ingredients[index][1] == name and actual.unit.ingredients[index][2] == 1)
      end
      assert(#actual.prerequisites == 1)
      assert(actual.prerequisites[1] == (level == 1 and family.prerequisite or "mir-" .. family.key .. "-" .. (level - 1)))
      local effect = actual.effects[1]
      assert(effect.type == family.effect and effect.modifier == family.modifier)
      assert(effect.ammo_category == family.ammo_category and effect.turret_id == family.turret_id)
      cursor = cursor + 1
    end
  end
  assert(cursor - 1 == #rows)
end

function M.run(player_root)
  package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
  package.cpath = ""
  _G.settings, _G.mods = nil, nil

  for _, id in ipairs({"f006", "f007", "f008", "f009", "f010", "f011", "f012"}) do
    local calls, rows = invoke(target(id), raw_for(id))
    assert(calls == 1 and rows ~= nil)
    assert_family_rows(id, rows)
  end

  local missing = raw_for("f006")
  missing.technology["rocket-speed-5"] = nil
  expect_failure(function() invoke(target("f006"), missing) end)

  local no_science = raw_for("f012")
  no_science.tool["alien-science-pack"] = nil
  expect_failure(function() invoke(target("f012"), no_science) end)

  local collision = raw_for("f007")
  collision.technology["mir-bullet-damage-1"] = {type="technology"}
  expect_failure(function() invoke(target("f007"), collision) end)

  expect_failure(function() invoke(target("f013"), raw_for("f006")) end)
  expect_failure(function() invoke({id="f006", reduced=true, research_levels=true, recipe_productivity=false}, raw_for("f006")) end)
  local saved = _G.data
  _G.data = nil
  expect_failure(function() require("adapters.early.data").apply(target("f006")) end)
  _G.data = saved
  return true
end

return M

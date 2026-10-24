-- Fixture-only acceleration for the F200 K2 Base continuation proof.  The
-- literal expectations below are the selected rows from the independently
-- captured K2 Base facts, not values read from a generated candidate.  Every
-- default semantic field is checked before any fixture-owned mutation.
local CONTINUATIONS = {
  {
    name = "braking-force-8", level = 8,
    prerequisites = {"braking-force-6", "braking-force-7", "automation-science-pack",
      "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack"},
    formula = "861.51212960553*1.33333^(L-8)", time = 60,
    effects = {{type = "train-braking-force-bonus", modifier = 0.15}},
  },
  {
    name = "inserter-capacity-bonus-8", level = 8,
    prerequisites = {"inserter-capacity-bonus-6", "utility-science-pack", "inserter-capacity-bonus-7",
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack"},
    formula = "914488.340211249*3.33333^(L-8)", time = 60,
    effects = {
      {type = "inserter-stack-size-bonus", modifier = 2},
      {type = "bulk-inserter-capacity-bonus", modifier = 4},
    },
  },
  {
    name = "laser-shooting-speed-8", level = 8,
    prerequisites = {"laser-shooting-speed-6", "laser-shooting-speed-7", "automation-science-pack",
      "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "military-science-pack", "utility-science-pack"},
    formula = "1025.15625*1.5^(L-8)", time = 120,
    effects = {
      {type = "gun-speed", ammo_category = "laser", modifier = 0.1},
      {type = "gun-speed", ammo_category = "kr-impulse-rifle", modifier = 0.1},
    },
  },
  {
    name = "research-speed-7", level = 7,
    prerequisites = {"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
      "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack", "military-science-pack"},
    formula = "683.4375*1.5^(L-7)", time = 120,
    effects = {{type = "laboratory-speed", modifier = 0.6}},
  },
  {
    name = "weapon-shooting-speed-7", level = 7,
    prerequisites = {"weapon-shooting-speed-5", "utility-science-pack", "weapon-shooting-speed-6",
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "military-science-pack", "utility-science-pack"},
    formula = "683.4375*1.5^(L-7)", time = 120,
    effects = {
      {type = "gun-speed", ammo_category = "bullet", modifier = 0.15},
      {type = "gun-speed", ammo_category = "shotgun-shell", modifier = 0.15},
      {type = "gun-speed", ammo_category = "kr-pistol", modifier = 0.15},
      {type = "gun-speed", ammo_category = "kr-anti-materiel-rifle-ammo", modifier = 0.15},
      {type = "gun-speed", ammo_category = "kr-railgun-shell", modifier = 0.2},
      {type = "gun-speed", ammo_category = "kr-turret-missile", modifier = 0.2},
      {type = "gun-speed", ammo_category = "kr-heavy-rocket", modifier = 0.2},
    },
  },
  {
    name = "worker-robots-storage-4", level = 4,
    prerequisites = {"worker-robots-storage-2", "utility-science-pack", "worker-robots-storage-3",
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack"},
    formula = "675*1.5^(L-4)", time = 60,
    effects = {{type = "worker-robot-storage", modifier = 1}},
  },
}

local GEAR = {
  name = "recipe-prod-research_gears-1", level = 1,
  prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
  science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
  formula = "8000*2^(L-1)", time = 60,
  effects = {
    {type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.1},
    {type = "change-recipe-productivity", recipe = "kr-iron-gear-wheel-from-enriched-iron", change = 0.1},
    {type = "change-recipe-productivity", recipe = "kr-iron-gear-wheel-from-iron-ore", change = 0.1},
  },
}

local function exact_names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    assert(actual[index] == name, label .. " changed at " .. tostring(index))
  end
end

local function exact_effects(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, expected_effect in ipairs(expected) do
    local effect = actual[index]
    assert(type(effect) == "table" and effect.type == expected_effect.type, label .. " type changed at " .. tostring(index))
    for key, value in pairs(expected_effect) do
      assert(effect[key] == value, label .. " changed at " .. tostring(index) .. "." .. key)
    end
  end
end

local function assert_row(expected)
  local technology = assert(data.raw.technology[expected.name], expected.name .. " is absent")
  assert(technology.type == "technology" and technology.name == expected.name, expected.name .. " identity changed")
  assert(technology.level == expected.level and technology.upgrade == true and technology.max_level == "infinite",
    expected.name .. " infinite progression changed")
  assert(technology.enabled ~= false, expected.name .. " is disabled")
  if expected.name ~= GEAR.name then assert(technology.hidden == false, expected.name .. " visibility changed") end
  exact_names(technology.prerequisites, expected.prerequisites, expected.name .. " prerequisites")

  local unit = assert(technology.unit, expected.name .. " unit is absent")
  assert(unit.count == nil and unit.count_formula == expected.formula and unit.time == expected.time,
    expected.name .. " default cost or time changed")
  assert(type(unit.ingredients) == "table" and #unit.ingredients == #expected.science,
    expected.name .. " science count changed")
  for index, science in ipairs(expected.science) do
    local ingredient = unit.ingredients[index]
    assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1,
      expected.name .. " science changed at " .. tostring(index))
  end
  exact_effects(technology.effects, expected.effects, expected.name .. " effects")
  return technology
end

assert(mods.base == "2.0.77" and mods.Krastorio2 == "2.0.19" and mods.Krastorio2Assets == "2.0.5"
  and mods["more-infinite-research"] == "5.0.20000" and mods["space-age"] == nil
  and mods["Krastorio2-spaced-out"] == nil and mods["k2so-assets"] == nil,
  "fixture loaded with an unexpected F200 K2 Base closure")

-- Validate every default first.  A later drift cannot partially accelerate an
-- earlier research row and turn a failed fixture into a faster test world.
local rows = {}
for index, expected in ipairs(CONTINUATIONS) do rows[index] = assert_row(expected) end
rows[#rows + 1] = assert_row(GEAR)

for index = 1, #rows do
  local unit = rows[index].unit
  unit.count, unit.count_formula, unit.time = nil, "1", 1
end

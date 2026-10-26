-- Explicit modern continuations retained from the captured Bob Warfare and Py
-- profiles.  This is a selection/binding adapter: it neither discovers
-- technologies nor writes to data.raw.  The modern catalogue owns the base
-- continuation declarations and merges these field maps by native tail id.
local M = {}
local target = require("platform.target")

local COAL_SCIENCE = "science_py_coal"
local HIGHTECH_SCIENCE = "science_py_hightech"
local HIGHTECH_SPACE_SCIENCE = "science_py_hightech_space"

local COAL_AMOUNTS = {
  ["utility-science-pack"] = 1,
  ["production-science-pack"] = 2,
  ["chemical-science-pack"] = 3,
  ["logistic-science-pack"] = 6,
  ["automation-science-pack"] = 10,
  ["military-science-pack"] = 3,
}

local HIGHTECH_AMOUNTS = {
  ["utility-science-pack"] = 1,
  ["py-science-pack-4"] = 2,
  ["production-science-pack"] = 3,
  ["py-science-pack-3"] = 6,
  ["chemical-science-pack"] = 10,
  ["py-science-pack-2"] = 20,
  ["logistic-science-pack"] = 30,
  ["py-science-pack-1"] = 60,
  ["automation-science-pack"] = 100,
  ["military-science-pack"] = 20,
  ["space-science-pack"] = 1,
}

local function copy_amounts(amounts)
  local out = {}
  for name, amount in pairs(amounts) do out[name] = amount end
  return out
end

local function inheritance(last_count, previous_count, research_time)
  return {last_count = last_count, previous_count = previous_count, research_time = research_time}
end

local function research_speed_icons()
  return {
    {icon = "__pycoalprocessinggraphics__/graphics/technology/energy-1.png", icon_size = 128,
      tint = {r = 0, g = 0, b = 0, a = 1}},
    {icon = "__pycoalprocessinggraphics__/graphics/technology/border.png", icon_size = 128},
    {icon = "__pycoalprocessinggraphics__/graphics/technology/lab.png", icon_size = 128, scale = 0.8},
    {icon = "__core__/graphics/icons/technology/constants/constant-speed.png", icon_size = 128,
      scale = 0.5, shift = {50, 50}},
  }
end

local function py_override(science, amounts, prerequisites, last_count, previous_count, inherited_time, order)
  return {
    science = science,
    science_amounts = copy_amounts(amounts),
    prerequisites = prerequisites,
    inheritance = inheritance(last_count, previous_count, inherited_time),
    order = order,
  }
end

local function coal_overrides()
  local out = {
    ["braking-force-8"] = py_override(COAL_SCIENCE, COAL_AMOUNTS,
      {"braking-force-6", "braking-force-7"}, 5000, 2250, 60, "autotech-[000235]-[braking-force-7]"),
    ["inserter-capacity-bonus-8"] = py_override(COAL_SCIENCE, COAL_AMOUNTS,
      {"utility-science-pack", "inserter-capacity-bonus-6", "inserter-capacity-bonus-7"},
      2250, 3600, 60, "autotech-[000213]-[inserter-capacity-bonus-7]"),
    ["laser-shooting-speed-8"] = py_override(COAL_SCIENCE, COAL_AMOUNTS,
      {"laser-shooting-speed-6", "laser-shooting-speed-7"}, 2750, 5000, 60,
      "autotech-[000239]-[laser-shooting-speed-7]"),
    ["research-speed-7"] = py_override(COAL_SCIENCE, COAL_AMOUNTS,
      {"utility-science-pack", "research-speed-5", "research-speed-6"}, 2250, 1300, 60,
      "autotech-[000217]-[research-speed-6]"),
    ["weapon-shooting-speed-7"] = py_override(COAL_SCIENCE, COAL_AMOUNTS,
      {"utility-science-pack", "weapon-shooting-speed-5", "weapon-shooting-speed-6"}, 2250, 600, 60,
      "autotech-[000210]-[weapon-shooting-speed-6]"),
    ["worker-robots-storage-4"] = py_override(COAL_SCIENCE, COAL_AMOUNTS,
      {"utility-science-pack", "worker-robots-storage-2", "worker-robots-storage-3"}, 2250, 1300, 60,
      "autotech-[000220]-[worker-robots-storage-3]"),
  }
  out["research-speed-7"].icons = research_speed_icons()
  out["research-speed-7"].icon_size = 128
  return out
end

local function hightech_overrides()
  local out = {
    ["braking-force-8"] = py_override(HIGHTECH_SPACE_SCIENCE, HIGHTECH_AMOUNTS,
      {"braking-force-6", "braking-force-7"}, 4000, 3600, 600, "autotech-[000770]-[braking-force-7]"),
    ["inserter-capacity-bonus-8"] = py_override(HIGHTECH_SCIENCE, HIGHTECH_AMOUNTS,
      {"utility-science-pack", "inserter-capacity-bonus-6", "inserter-capacity-bonus-7"},
      3600, 1750, 600, "autotech-[000719]-[inserter-capacity-bonus-7]"),
    ["laser-shooting-speed-8"] = py_override(HIGHTECH_SPACE_SCIENCE, HIGHTECH_AMOUNTS,
      {"laser-shooting-speed-6", "laser-shooting-speed-7"}, 4000, 4000, 600,
      "autotech-[000779]-[laser-shooting-speed-7]"),
    ["research-speed-7"] = py_override(HIGHTECH_SPACE_SCIENCE, HIGHTECH_AMOUNTS,
      {"utility-science-pack", "research-speed-5", "research-speed-6"}, 3600, 1300, 600,
      "autotech-[000722]-[research-speed-6]"),
    ["weapon-shooting-speed-7"] = py_override(HIGHTECH_SPACE_SCIENCE, HIGHTECH_AMOUNTS,
      {"utility-science-pack", "weapon-shooting-speed-5", "weapon-shooting-speed-6"}, 3600, 750, 600,
      "autotech-[000716]-[weapon-shooting-speed-6]"),
    ["worker-robots-storage-4"] = py_override(HIGHTECH_SCIENCE, HIGHTECH_AMOUNTS,
      {"utility-science-pack", "worker-robots-storage-2", "worker-robots-storage-3"}, 3600, 1300, 600,
      "autotech-[000724]-[worker-robots-storage-3]"),
  }
  out["research-speed-7"].icons = research_speed_icons()
  out["research-speed-7"].icon_size = 128
  return out
end

local function bob_warfare_overrides()
  return {
    ["laser-shooting-speed-8"] = {
      effects = {
        {type = "gun-speed", ammo_category = "laser", scale = 1},
        {type = "gun-speed", ammo_category = "bob-laser-rifle", scale = 1},
      },
    },
  }
end

local function py_selection(active_mods)
  return require("compatibility.py_profile").select(active_mods)
end

local function bob_warfare_active(active_mods)
  return require("compatibility.bob_warfare_profile").applies(active_mods)
end

local function merge(destination, source)
  for id, fields in pairs(source) do
    local out = destination[id] or {}
    for field, value in pairs(fields) do out[field] = value end
    destination[id] = out
  end
end

-- Each call creates output tables and nested arrays afresh.  The catalogue
-- applies these fields to the already authored base continuation by id.
function M.continuation_overrides(active_mods)
  local selected = py_selection(active_mods)
  local out = {}
  if selected.coal then merge(out, coal_overrides()) end
  if selected.hightech then merge(out, hightech_overrides()) end
  if selected.hightech and target.id == "f210" then
    for _, fact in pairs(require("compatibility.modern_catalogue.py_f210").continuation_native_facts) do
      local row = out[fact.id]
      row.inheritance, row.order = copy_amounts(fact.inheritance), fact.order
      if fact.presentation then
        row.icon_size, row.icons = fact.presentation.icon_size, {}
        for index, icon in ipairs(fact.presentation.icons) do
          local copied = {}
          for field, value in pairs(icon) do
            copied[field] = type(value) == "table" and copy_amounts(value) or value
          end
          row.icons[index] = copied
        end
      end
    end
  end
  if bob_warfare_active(active_mods) then merge(out, bob_warfare_overrides()) end
  return out
end

local COAL_INGREDIENTS = {
  {"utility-science-pack", 1}, {"production-science-pack", 2}, {"chemical-science-pack", 3},
  {"logistic-science-pack", 6}, {"automation-science-pack", 10}, {"military-science-pack", 3},
}

local HIGHTECH_INGREDIENTS = {
  {"utility-science-pack", 1}, {"py-science-pack-4", 2}, {"production-science-pack", 3},
  {"py-science-pack-3", 6}, {"chemical-science-pack", 10}, {"py-science-pack-2", 20},
  {"logistic-science-pack", 30}, {"py-science-pack-1", 60}, {"automation-science-pack", 100},
  {"military-science-pack", 20},
}

local EFFECTS = {
  braking_force = {{type = "train-braking-force-bonus", modifier = 0.15}},
  inserter_capacity_bonus = {
    {type = "inserter-stack-size-bonus", modifier = 1}, {type = "bulk-inserter-capacity-bonus", modifier = 2},
  },
  laser = {{type = "gun-speed", ammo_category = "laser", modifier = 0.5}},
  bob_laser = {
    {type = "gun-speed", ammo_category = "laser", modifier = 0.5},
    {type = "gun-speed", ammo_category = "bob-laser-rifle", modifier = 0.5},
  },
  research_speed = {{type = "laboratory-speed", modifier = 0.6}},
  weapon = {
    {type = "gun-speed", ammo_category = "bullet", modifier = 0.4},
    {type = "gun-speed", ammo_category = "shotgun-shell", modifier = 0.4},
    {type = "gun-speed", ammo_category = "cannon-shell", modifier = 1.5},
    {type = "gun-speed", ammo_category = "rocket", modifier = 1.3},
  },
  worker = {{type = "worker-robot-storage", modifier = 1}},
}

local function binding(tail, previous, previous_count, predecessor, predecessor_count, predecessor_time,
    ingredients, prerequisites, effects, order, check_icons)
  return {
    tail = tail, previous = {name = previous, count = previous_count},
    predecessor = {name = predecessor, count = predecessor_count, time = predecessor_time,
      ingredients = ingredients, prerequisites = prerequisites, effects = effects, order = order,
      check_icons = check_icons == true},
  }
end

local function py_bindings(ingredients, last_counts, previous_counts, inherited_time, orders)
  return {
    binding("braking-force-8", "braking-force-6", previous_counts[1], "braking-force-7", last_counts[1], inherited_time,
      ingredients, {"braking-force-6"}, EFFECTS.braking_force, orders[1]),
    binding("inserter-capacity-bonus-8", "inserter-capacity-bonus-6", previous_counts[2], "inserter-capacity-bonus-7",
      last_counts[2], inherited_time, ingredients, {"utility-science-pack", "inserter-capacity-bonus-6"},
      EFFECTS.inserter_capacity_bonus, orders[2]),
    binding("laser-shooting-speed-8", "laser-shooting-speed-6", previous_counts[3], "laser-shooting-speed-7",
      last_counts[3], inherited_time, ingredients, {"laser-shooting-speed-6"}, EFFECTS.laser, orders[3]),
    binding("research-speed-7", "research-speed-5", previous_counts[4], "research-speed-6", last_counts[4], inherited_time,
      ingredients, {"utility-science-pack", "research-speed-5"}, EFFECTS.research_speed, orders[4], true),
    binding("weapon-shooting-speed-7", "weapon-shooting-speed-5", previous_counts[5], "weapon-shooting-speed-6",
      last_counts[5], inherited_time, ingredients, {"utility-science-pack", "weapon-shooting-speed-5"}, EFFECTS.weapon, orders[5]),
    binding("worker-robots-storage-4", "worker-robots-storage-2", previous_counts[6], "worker-robots-storage-3",
      last_counts[6], inherited_time, ingredients, {"utility-science-pack", "worker-robots-storage-2"}, EFFECTS.worker, orders[6]),
  }
end

local COAL_BINDINGS = py_bindings(COAL_INGREDIENTS,
  {5000, 2250, 2750, 2250, 2250, 2250}, {2250, 3600, 5000, 1300, 600, 1300}, 60,
  {"autotech-[000235]-[braking-force-7]", "autotech-[000213]-[inserter-capacity-bonus-7]",
    "autotech-[000239]-[laser-shooting-speed-7]", "autotech-[000217]-[research-speed-6]",
    "autotech-[000210]-[weapon-shooting-speed-6]", "autotech-[000220]-[worker-robots-storage-3]"})

-- The published continuation adds space science to four tails.  The captured
-- native predecessors all retain this non-space vector, so preflight does not
-- claim that the additional tail policy was an upstream field.
local HIGHTECH_BINDINGS = {
  binding("braking-force-8", "braking-force-6", 3600, "braking-force-7", 4000, 600,
    HIGHTECH_INGREDIENTS, {"braking-force-6"}, EFFECTS.braking_force, "autotech-[000770]-[braking-force-7]"),
  binding("inserter-capacity-bonus-8", "inserter-capacity-bonus-6", 1750, "inserter-capacity-bonus-7", 3600, 600,
    HIGHTECH_INGREDIENTS, {"utility-science-pack", "inserter-capacity-bonus-6"}, EFFECTS.inserter_capacity_bonus,
    "autotech-[000719]-[inserter-capacity-bonus-7]"),
  binding("laser-shooting-speed-8", "laser-shooting-speed-6", 4000, "laser-shooting-speed-7", 4000, 600,
    HIGHTECH_INGREDIENTS, {"laser-shooting-speed-6"}, EFFECTS.laser, "autotech-[000779]-[laser-shooting-speed-7]"),
  binding("research-speed-7", "research-speed-5", 1300, "research-speed-6", 3600, 600,
    HIGHTECH_INGREDIENTS, {"utility-science-pack", "research-speed-5"}, EFFECTS.research_speed,
    "autotech-[000722]-[research-speed-6]", true),
  binding("weapon-shooting-speed-7", "weapon-shooting-speed-5", 750, "weapon-shooting-speed-6", 3600, 600,
    HIGHTECH_INGREDIENTS, {"utility-science-pack", "weapon-shooting-speed-5"}, EFFECTS.weapon,
    "autotech-[000716]-[weapon-shooting-speed-6]"),
  binding("worker-robots-storage-4", "worker-robots-storage-2", 1300, "worker-robots-storage-3", 3600, 600,
    HIGHTECH_INGREDIENTS, {"utility-science-pack", "worker-robots-storage-2"}, EFFECTS.worker,
    "autotech-[000724]-[worker-robots-storage-3]"),
}

local BOB_BINDINGS = {
  binding("laser-shooting-speed-8", "laser-shooting-speed-6", 350, "laser-shooting-speed-7", 450, 60,
    {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1},
      {"military-science-pack", 1}, {"utility-science-pack", 1}}, {"laser-shooting-speed-6"}, EFFECTS.bob_laser, nil),
}

local function same_names(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index = 1, #expected do if actual[index] ~= expected[index] then return false end end
  return true
end

local function same_ingredients(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index = 1, #expected do
    local found, wanted = actual[index], expected[index]
    if type(found) ~= "table" or found[1] ~= wanted[1] or found[2] ~= wanted[2] then return false end
    for field in pairs(found) do if field ~= 1 and field ~= 2 then return false end end
  end
  return true
end

local function same_effects(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index = 1, #expected do
    local found, wanted = actual[index], expected[index]
    if type(found) ~= "table" or found.type ~= wanted.type or found.modifier ~= wanted.modifier
        or found.ammo_category ~= wanted.ammo_category then return false end
    for field in pairs(found) do
      if field ~= "type" and field ~= "modifier" and field ~= "ammo_category" then return false end
    end
  end
  return true
end

local function same_research_speed_icons(actual, expected)
  if expected then
    if type(actual) ~= "table" or #actual ~= #expected then return false end
    for index, wanted in ipairs(expected) do
      local found = actual[index]
      if type(found) ~= "table" or found.icon ~= wanted.icon or found.icon_size ~= wanted.icon_size
          or found.scale ~= wanted.scale or not same_names(found.shift or {}, wanted.shift or {}) then return false end
      for field in pairs(found) do
        if field ~= "icon" and field ~= "icon_size" and field ~= "scale" and field ~= "shift" then return false end
      end
    end
    return true
  end
  if type(actual) ~= "table" or #actual ~= 4 then return false end
  local first, border, lab, overlay = actual[1], actual[2], actual[3], actual[4]
  local function only(row, allowed)
    for field in pairs(row) do if not allowed[field] then return false end end
    return true
  end
  return type(first) == "table" and first.icon == "__pycoalprocessinggraphics__/graphics/technology/energy-1.png"
    and first.icon_size == 128 and type(first.tint) == "table" and first.tint.r == 0 and first.tint.g == 0
    and first.tint.b == 0 and first.tint.a == 1 and only(first.tint, {r = true, g = true, b = true, a = true})
    and only(first, {icon = true, icon_size = true, tint = true})
    and type(border) == "table" and border.icon == "__pycoalprocessinggraphics__/graphics/technology/border.png"
    and border.icon_size == 128 and only(border, {icon = true, icon_size = true})
    and type(lab) == "table" and lab.icon == "__pycoalprocessinggraphics__/graphics/technology/lab.png"
    and lab.icon_size == 128 and lab.scale == 0.8 and only(lab, {icon = true, icon_size = true, scale = true})
    and type(overlay) == "table" and overlay.icon == "__core__/graphics/icons/technology/constants/constant-speed.png"
    and overlay.icon_size == 128 and overlay.scale == 0.5 and type(overlay.shift) == "table"
    and overlay.shift[1] == 50 and overlay.shift[2] == 50 and only(overlay.shift, {[1] = true, [2] = true})
    and only(overlay, {icon = true, icon_size = true, scale = true, shift = true})
end

local function fail(profile, tail, message)
  error("MIR native continuation " .. profile .. " " .. tail .. ": " .. message, 3)
end

local function preflight_bindings(profile, bindings, raw)
  if type(raw) ~= "table" or type(raw.technology) ~= "table" then
    error("MIR native continuation preflight requires data.raw.technology", 3)
  end
  local technologies = raw.technology
  for _, binding_row in ipairs(bindings) do
    local previous = technologies[binding_row.previous.name]
    if type(previous) ~= "table" or type(previous.unit) ~= "table"
        or previous.unit.count ~= binding_row.previous.count then
      fail(profile, binding_row.tail, "previous inherited cost changed")
    end
    local expected, predecessor = binding_row.predecessor, technologies[binding_row.predecessor.name]
    if type(predecessor) ~= "table" or type(predecessor.unit) ~= "table" then
      fail(profile, binding_row.tail, "named predecessor is unavailable")
    end
    if predecessor.unit.count ~= expected.count or predecessor.unit.time ~= expected.time then
      fail(profile, binding_row.tail, "predecessor unit changed")
    end
    if not same_ingredients(predecessor.unit.ingredients, expected.ingredients) then
      fail(profile, binding_row.tail, "predecessor science changed")
    end
    for _, ingredient in ipairs(expected.ingredients) do
      if type(technologies[ingredient[1]]) ~= "table" then fail(profile, binding_row.tail, "named science is unavailable") end
    end
    if not same_names(predecessor.prerequisites, expected.prerequisites) then
      fail(profile, binding_row.tail, "predecessor prerequisites changed")
    end
    if not same_effects(predecessor.effects, expected.effects) then
      fail(profile, binding_row.tail, "predecessor effects changed")
    end
    if predecessor.order ~= expected.order then fail(profile, binding_row.tail, "predecessor order changed") end
    if expected.check_icons and (predecessor.icon_size ~= 128 or not same_research_speed_icons(predecessor.icons)) then
      fail(profile, binding_row.tail, "predecessor icon changed")
    end
    if expected.icons and (predecessor.icon_size ~= 128
        or not same_research_speed_icons(predecessor.icons, expected.icons)) then
      fail(profile, binding_row.tail, "predecessor icon changed")
    end
  end
end

-- This checks only the named native rows consumed by the selected variants.
-- It is intentionally pure: callers perform it before any data-stage write.
function M.preflight(active_mods, raw)
  local selected = py_selection(active_mods)
  if selected.coal then preflight_bindings("py-coal", COAL_BINDINGS, raw) end
  if selected.hightech then
    local bindings = HIGHTECH_BINDINGS
    if target.id == "f210" then
      local facts = require("compatibility.modern_catalogue.py_f210").continuation_native_facts
      local keys = {}
      for key in pairs(facts) do keys[#keys + 1] = key end
      table.sort(keys)
      bindings = {}
      for _, key in ipairs(keys) do
        local fact = facts[key]
        local predecessor = copy_amounts(fact.predecessor)
        predecessor.order = fact.order
        if fact.presentation then predecessor.icons = fact.presentation.icons end
        bindings[#bindings + 1] = {tail=fact.id, previous=fact.previous, predecessor=predecessor}
      end
    end
    preflight_bindings("py-alienlife-hightech", bindings, raw)
  end
  if bob_warfare_active(active_mods) then preflight_bindings("bobwarfare", BOB_BINDINGS, raw) end
  return true
end

return M

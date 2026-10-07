-- Native-only oracle copied into the two existing modern upgrade fixtures.
-- It observes final prototypes and real force state; it creates no prototypes.
local M = {}
local names = {"weapon-shooting-speed-7", "research-speed-7"}
local reload_checked = false
local function fail(message) error("SIF-01 native upgrade: " .. message) end
local function technology(name)
  local value = game.forces.player.technologies[name]
  if not value then fail("missing " .. name) end
  return value
end
local function ingredients(value)
  local result = {}
  for _, ingredient in pairs(value.research_unit_ingredients) do result[ingredient.name] = ingredient.amount end
  if next(result) == nil then fail("empty science for " .. value.name) end
  return result
end
local function state(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled, saved_progress=value.saved_progress,
    science=ingredients(value)}
end
local function marker(stage)
  log("[mir-fixture] SIF-01 native continuations verified stage=" .. stage)
end
local function same_state(value, before)
  for _, field in ipairs({"level", "researched", "enabled", "saved_progress"}) do
    if value[field] ~= before[field] then fail(value.name .. " changed " .. field) end
  end
end
local function same_science(value, expected)
  local actual = ingredients(value)
  for pack, amount in pairs(expected) do
    if actual[pack] ~= amount then fail(value.name .. " changed inherited science " .. pack) end
  end
  for pack in pairs(actual) do
    if expected[pack] == nil then fail(value.name .. " added unexpected science " .. pack) end
  end
end
local introduced_science = {
  ["weapon-shooting-speed-7"] = {"automation", "logistic", "chemical", "military", "utility"},
  ["research-speed-7"] = {"automation", "logistic", "chemical", "production", "utility", "military",
    "agricultural", "metallurgic", "electromagnetic", "cryogenic"}
}
function M.capture()
  if not script.active_mods["space-is-fake"] or not script.active_mods["space-age"] then fail("required native mod set absent") end
  local force = game.forces.player
  local record = {technologies={}, anchors={}, predecessor_version=script.active_mods["more-infinite-research"],
    space_is_fake_version=script.active_mods["space-is-fake"]}
  for _, name in ipairs(names) do
    local value = force.technologies[name]
    local anchor = technology(name:gsub("7$", "6"))
    if value then
      value.researched = false
      value.level = 8
      if value.level ~= 8 or value.researched then fail(name .. " did not retain seeded earned level") end
      record.technologies[name] = state(value)
    else
      if record.predecessor_version ~= "4.2.20000" or record.space_is_fake_version ~= "1.0.60" then
        fail("unexpected missing predecessor " .. name)
      end
      anchor.researched = true
      if not anchor.researched then fail("finite predecessor not researched: " .. anchor.name) end
      record.technologies[name] = {absent=true}
    end
    record.anchors[name] = state(anchor)
  end
  force.reset_technology_effects()
  record.lab_bonus = force.laboratory_speed_modifier
  record.bullet_speed_bonus = force.get_gun_speed_modifier("bullet")
  storage.mir421_space_fake_upgrade = record
  log("[mir-fixture] SIF-01 native predecessor observations " .. helpers.table_to_json(record))
  marker("source")
end
function M.verify(stage)
  if stage == "reload" and reload_checked then return end
  local record = storage.mir421_space_fake_upgrade
  if not record then fail("predecessor observations absent") end
  if not script.active_mods["space-is-fake"] or not script.active_mods["space-age"] then fail("native mod set changed") end
  for _, name in ipairs(names) do
    local value, before = technology(name), record.technologies[name]
    local anchor_name = name:gsub("7$", "6")
    local anchor = technology(anchor_name)
    same_state(anchor, record.anchors[name])
    same_science(anchor, record.anchors[name].science)
    local science = ingredients(value)
    if science["space-science-pack"] then fail(name .. " retained retired space science") end
    local expected = {}
    if before.absent then
      if value.level ~= 7 or value.researched or not value.enabled or value.saved_progress ~= 0 then
        fail(name .. " introduced with unexpected research state")
      end
      for _, pack in ipairs(introduced_science[name]) do expected[pack .. "-science-pack"] = 1 end
    else
      same_state(value, before)
      for pack, amount in pairs(before.science) do
        if pack ~= "space-science-pack" then expected[pack] = amount end
      end
      -- SIF 1.0.78 replaces the old space prerequisite with production and
      -- utility prerequisites, then adds their ingredients (technology.lua
      -- lines 120 and 318-349). Removing MIR's retired space prerequisite
      -- also removes that derived production ingredient for weapon speed.
      -- It is not part of the unchanged finite level-six science contract.
      if name == "weapon-shooting-speed-7" and record.predecessor_version == "4.2.21000"
        and record.space_is_fake_version == "1.0.78" and expected["production-science-pack"] == 1
        and record.anchors[name].science["production-science-pack"] == nil then
        expected["production-science-pack"] = nil
      end
    end
    same_science(value, expected)
    if not value.prerequisites[anchor_name] or value.prerequisites["space-science-pack"] then fail(name .. " changed finite anchor or retained retired prerequisite") end
    local useful = false
    for _, effect in pairs(value.prototype.effects or {}) do if (effect.modifier or 0) > 0 then useful = true end end
    if not useful then fail(name .. " has no useful modifier") end
  end
  local force = game.forces.player
  if math.abs(force.laboratory_speed_modifier - record.lab_bonus) > 0.000001 or
    math.abs(force.get_gun_speed_modifier("bullet") - record.bullet_speed_bonus) > 0.000001 then fail("earned native reward changed") end
  marker(stage)
  if stage == "reload" then reload_checked = true end
end
return M

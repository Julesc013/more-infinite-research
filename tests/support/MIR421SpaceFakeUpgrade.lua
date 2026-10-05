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
function M.capture()
  if not script.active_mods["space-is-fake"] or not script.active_mods["space-age"] then fail("required native mod set absent") end
  local force = game.forces.player
  local record = {technologies={}, predecessor_version=script.active_mods["more-infinite-research"]}
  for _, name in ipairs(names) do
    local value = technology(name)
    value.level = 8
    value.researched = false
    record.technologies[name] = state(value)
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
    for _, field in ipairs({"level", "researched", "enabled", "saved_progress"}) do
      if value[field] ~= before[field] then fail(name .. " changed " .. field) end
    end
    local science = ingredients(value)
    if science["space-science-pack"] then fail(name .. " retained retired space science") end
    for pack, amount in pairs(before.science) do
      if pack ~= "space-science-pack" and science[pack] ~= amount then fail(name .. " changed inherited science " .. pack) end
    end
    for pack in pairs(science) do
      if before.science[pack] == nil then fail(name .. " added unexpected science " .. pack) end
    end
    local anchor = name:gsub("7$", "6")
    if not value.prerequisites[anchor] or value.prerequisites["space-science-pack"] then fail(name .. " changed finite anchor or retained retired prerequisite") end
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

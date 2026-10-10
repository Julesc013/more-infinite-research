-- Full upgrade oracle for the supported pre-2.0 engine capabilities. Test-only:
-- the player package never reads or receives these independent expectations.
local M = {}
local epsilon = 0.000001
local common_effects = {
  "manual_mining_speed_modifier", "manual_crafting_speed_modifier", "laboratory_speed_modifier",
  "worker_robots_speed_modifier", "worker_robots_storage_bonus", "inserter_stack_size_bonus",
  "stack_inserter_capacity_bonus", "character_running_speed_modifier", "character_build_distance_bonus",
  "character_item_drop_distance_bonus", "character_reach_distance_bonus", "character_resource_reach_distance_bonus",
  "character_item_pickup_distance_bonus", "character_loot_pickup_distance_bonus", "character_inventory_slots_bonus",
  "character_health_bonus"
}
local function fail(message) error("MIR complete historical upgrade state failed: " .. message) end
local function copy(value)
  if type(value) == "table" then
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
  end
  if value == nil or type(value) == "string" or type(value) == "boolean" or type(value) == "number" then return value end
  fail("non-scalar snapshot value")
end
local function equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) == "number" then return math.abs(a - b) <= epsilon end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end
local function bonuses_equal(before, after)
  for name, value in pairs(before) do if not equal(value, after[name]) then return false end end
  -- Categories are discovered from technology effects. A new unresearched
  -- technology can expose a previously uncaptured category with no earned bonus.
  for name, value in pairs(after) do
    if before[name] == nil and (type(value) ~= "number" or math.abs(value) > epsilon) then return false end
  end
  return true
end
-- Exact inherited 4.2.1 lab/science-frontier corrections. The observed
-- candidate definitions match the independently loaded published 4.2.1 source.
local reviewed_frontiers = {["0.15"]={["braking-force-8"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","braking-force-6","braking-force-7","electric-engine","engine","speed-module"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","braking-force-6","braking-force-7","electric-engine","engine","speed-module"}}},["inserter-capacity-bonus-8"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","inserter-capacity-bonus-6","inserter-capacity-bonus-7","speed-module"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","electric-engine","engine","inserter-capacity-bonus-6","inserter-capacity-bonus-7","speed-module"}}},["recipe-prod-research_character_crafting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_character_mining_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_character_reach-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_character_walking_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_electric_shooting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","discharge-defense-equipment","electric-engine","engine","military-2","turrets"},["before"]={"advanced-material-processing-2","discharge-defense-equipment","electric-engine","military-2","turrets"}}},["recipe-prod-research_flamethrower_shooting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","electric-engine","engine","flamethrower","military-2","turrets"},["before"]={"advanced-material-processing-2","electric-engine","flamethrower","military-2","turrets"}}},["recipe-prod-research_inventory_capacity-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_robot_battery-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","electric-engine","engine"},["before"]={"advanced-material-processing-2","electric-engine"}}},["recipe-prod-research_rocket_shooting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","electric-engine","engine","military-2","rocketry","turrets"},["before"]={"advanced-material-processing-2","electric-engine","military-2","rocketry","turrets"}}},["research-speed-7"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","military-2","research-speed-5","research-speed-6","speed-module","turrets"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","electric-engine","engine","military-2","research-speed-5","research-speed-6","speed-module","turrets"}}},["worker-robots-storage-4"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","speed-module","worker-robots-storage-2","worker-robots-storage-3"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","electric-engine","engine","speed-module","worker-robots-storage-2","worker-robots-storage-3"}}}},["0.16"]={["braking-force-8"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","braking-force-6","braking-force-7","electric-engine","engine","speed-module"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","braking-force-6","braking-force-7","electric-engine","engine","speed-module"}}},["inserter-capacity-bonus-8"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","inserter-capacity-bonus-6","inserter-capacity-bonus-7","speed-module"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","electric-engine","engine","inserter-capacity-bonus-6","inserter-capacity-bonus-7","speed-module"}}},["recipe-prod-research_character_crafting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_character_mining_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_character_reach-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_character_walking_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_electric_shooting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","discharge-defense-equipment","electric-engine","engine","military-2","turrets"},["before"]={"advanced-material-processing-2","discharge-defense-equipment","electric-engine","military-2","turrets"}}},["recipe-prod-research_flamethrower_shooting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","electric-engine","engine","flamethrower","military-2","turrets"},["before"]={"advanced-material-processing-2","electric-engine","flamethrower","military-2","turrets"}}},["recipe-prod-research_inventory_capacity-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"}},["before"]={{["amount"]=1,["name"]="military-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics-2","automation-2","battery","military-2","speed-module","turrets"},["before"]={"military-2","turrets"}}},["recipe-prod-research_lab_productivity-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="high-tech-science-pack"},{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","military-2","speed-module","turrets"},["before"]={"advanced-material-processing-2","electric-engine","military-2","turrets"}}},["recipe-prod-research_robot_battery-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","electric-engine","engine"},["before"]={"advanced-material-processing-2","electric-engine"}}},["recipe-prod-research_rocket_shooting_speed-1"]={["ingredients"]={["after"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"},{["amount"]=1,["name"]="science-pack-1"},{["amount"]=1,["name"]="science-pack-2"},{["amount"]=1,["name"]="science-pack-3"}},["before"]={{["amount"]=1,["name"]="military-science-pack"},{["amount"]=1,["name"]="production-science-pack"}}},["prerequisites"]={["after"]={"advanced-electronics","advanced-material-processing-2","electric-engine","engine","military-2","rocketry","turrets"},["before"]={"advanced-material-processing-2","electric-engine","military-2","rocketry","turrets"}}},["research-speed-7"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","military-2","research-speed-5","research-speed-6","speed-module","turrets"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","electric-engine","engine","military-2","research-speed-5","research-speed-6","speed-module","turrets"}}},["worker-robots-storage-4"]={["prerequisites"]={["after"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","automation-2","battery","electric-engine","engine","speed-module","worker-robots-storage-2","worker-robots-storage-3"},["before"]={"advanced-electronics","advanced-electronics-2","advanced-material-processing-2","battery","electric-engine","engine","speed-module","worker-robots-storage-2","worker-robots-storage-3"}}}}}
M.reviewed_frontiers = reviewed_frontiers
local function reviewed_frontier_equal(line, from_version, name, before, after)
  local rows = from_version:sub(-2) == "00" and reviewed_frontiers[line]
  local delta = rows and rows[name]
  if not delta then return false end
  local a, b = copy(before), copy(after)
  for field, values in pairs(delta) do
    if not equal(a.definition[field], values.before) or not equal(b.definition[field], values.after) then return false end
    a.definition[field], b.definition[field] = nil, nil
  end
  return equal(a,b)
end
local function quoted(value)
  return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
    if c == '\\' then return '\\\\' elseif c == '"' then return '\\"' end
    return string.format('\\u%04x', string.byte(c))
  end) .. '"'
end
-- 0.13--0.16 have write_file but no documented table_to_json. Export the same
-- scalar representation without introducing an engine or dependency payload.
local function json(value)
  if type(value) == "string" then return quoted(value) end
  if type(value) == "boolean" or type(value) == "number" then return tostring(value) end
  if type(value) ~= "table" then fail("invalid JSON snapshot") end
  local keys, out = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do out[#out + 1] = quoted(tostring(key)) .. ':' .. json(value[key]) end
  return '{' .. table.concat(out, ',') .. '}'
end

function M.new(line, from_version, to_version)
  local old = line == "0.13" or line == "0.14"
  local queue_supported = line == "0.17" or line == "1.0" or line == "1.1"
  local visibility_supported = queue_supported
  local mod_versions_supported = line == "1.0" or line == "1.1"
  local effects = copy(common_effects)
  if not old then
    for _, name in ipairs({"worker_robots_battery_modifier", "mining_drill_productivity_bonus", "train_braking_force_bonus"}) do
      effects[#effects + 1] = name
    end
  end
  if line ~= "0.13" and line ~= "0.14" and line ~= "0.15" then
    for _, name in ipairs({"laboratory_productivity_bonus", "following_robots_lifetime_modifier", "artillery_range_modifier"}) do
      effects[#effects + 1] = name
    end
  end
  local function state(force)
    local out = {technologies={}, recipes={}, effects={}, ammo={}, gun_speed={}, turret={}, settings={}, queue={}}
    for name, tech in pairs(force.technologies) do
      local prerequisites, ingredients = {}, {}
      for prerequisite in pairs(tech.prerequisites) do prerequisites[#prerequisites + 1] = prerequisite end
      table.sort(prerequisites)
      for _, ingredient in pairs(tech.research_unit_ingredients) do
        ingredients[#ingredients + 1] = {name=ingredient.name, amount=ingredient.amount}
      end
      table.sort(ingredients, function(a,b) return a.name < b.name end)
      local definition = {order=tech.order, prerequisites=prerequisites, ingredients=ingredients,
        effects=copy(tech.effects), unit_count=tech.research_unit_count, unit_energy=tech.research_unit_energy}
      local entry = {researched=tech.researched, enabled=tech.enabled, definition=definition}
      if not old then
        entry.level = tech.level
        entry.saved_progress = force.get_saved_technology_progress(tech)
        definition.max_level = tech.prototype.max_level
        definition.unit_count_formula = tech.research_unit_count_formula or false
      end
      if visibility_supported then
        entry.visible_when_disabled = tech.visible_when_disabled
        definition.hidden = tech.prototype.hidden
      end
      out.technologies[name] = entry
      for _, effect in pairs(tech.effects or {}) do
        if effect.type == "ammo-damage" then out.ammo[effect.ammo_category] = force.get_ammo_damage_modifier(effect.ammo_category)
        elseif effect.type == "gun-speed" then out.gun_speed[effect.ammo_category] = force.get_gun_speed_modifier(effect.ammo_category)
        elseif effect.type == "turret-attack" then out.turret[effect.turret_id] = force.get_turret_attack_modifier(effect.turret_id) end
      end
    end
    for _, name in ipairs(effects) do
      if type(force[name]) ~= "number" then fail("declared effect unavailable: " .. name) end
      out.effects[name] = force[name]
    end
    for name, recipe in pairs(force.recipes) do out.recipes[name] = recipe.enabled end
    if not old then for name, setting in pairs(settings.startup) do out.settings[name] = copy(setting.value) end end
    if queue_supported then
      out.research_queue_enabled = force.research_queue_enabled
      for _, tech in ipairs(force.research_queue or {}) do out.queue[#out.queue + 1] = tech.name end
    end
    out.current_research = force.current_research and force.current_research.name or false
    out.research_progress = force.research_progress
    return out
  end
  local function all_states()
    local out = {}; for name, force in pairs(game.forces) do out[name] = state(force) end; return out
  end
  local function export(stage, states)
    game.write_file("mir-upgrade-full-state-" .. stage .. ".json", json({stage=stage, from_version=from_version,
      to_version=to_version, engine_line=line, active_mods=mod_versions_supported and copy(script.active_mods) or false, forces=states,
      capabilities={technology_levels=not old, per_technology_saved_progress=not old,
        research_queue=queue_supported, visibility=visibility_supported, runtime_mod_versions=mod_versions_supported,
        recipe_productivity=false}}), false)
  end
  return {
    capture = function()
      if mod_versions_supported and script.active_mods["more-infinite-research"] ~= from_version then fail("wrong source package") end
      if global.mir422_complete_state then fail("source expectation already exists") end
      local observed = all_states()
      global.mir422_complete_state = {from_version=from_version, to_version=to_version, forces=observed}
      export("source", observed)
    end,
    verify = function(stage)
      if mod_versions_supported and script.active_mods["more-infinite-research"] ~= to_version then fail("wrong candidate package") end
      local expected = global.mir422_complete_state
      if not expected or expected.from_version ~= from_version or expected.to_version ~= to_version then fail("missing full source expectation") end
      local observed = all_states()
      export(stage .. "-before-check", observed)
      for force_name, before in pairs(expected.forces) do
        local after = observed[force_name]
        if not after then fail("force disappeared: " .. force_name) end
        local technologies, recipes = 0, 0
        for name, value in pairs(before.technologies) do
          if not after.technologies[name] then fail("technology disappeared: " .. name) end
          if not equal(value, after.technologies[name]) and not reviewed_frontier_equal(line, from_version, name, value, after.technologies[name]) then fail("technology state/definition changed: " .. name) end
          technologies = technologies + 1
        end
        for name, value in pairs(after.technologies) do
          if not before.technologies[name] and value.researched then fail("new research awarded: " .. name) end
        end
        for name, value in pairs(before.recipes) do
          if after.recipes[name] == nil or after.recipes[name] ~= value then fail("recipe availability changed: " .. name) end
          recipes = recipes + 1
        end
        for _, field in ipairs({"ammo", "gun_speed", "turret"}) do
          if not bonuses_equal(before[field], after[field]) then fail("earned category bonus changed: " .. force_name .. "/" .. field) end
        end
        for _, field in ipairs({"effects", "settings", "queue", "research_queue_enabled", "current_research", "research_progress"}) do
          if not equal(before[field], after[field]) then fail("saved force state changed: " .. force_name .. "/" .. field) end
        end
        log("[mir-fixture] complete research state retained technologies=" .. technologies .. " recipes=" .. recipes)
      end
      export(stage, observed)
    end
  }
end
return M

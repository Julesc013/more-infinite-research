local from_version = "4.0.21000"
local to_version = "4.1.21000"
local archetype = settings.startup["mir-upgrade-archetype"].value
local expected_progress = 0.42
local epsilon = 0.000001
local profiles = {
  ["base-default"]={technology="recipe-prod-research_iron-1",level=3},
  ["space-age-native-owner"]={technology="low-density-structure-productivity",level=4,requires_space_age=true,expected_absolute_cap=5},
  ["automatic-family-creation"]={technology="mir-auto-prod-manufacturing-assembling-machine-1",level=3,target_recipe="mir-upgrade-auto-assembler-recipe"},
  ["base-continuations"]={technology="inserter-capacity-bonus-8",level=8},
  ["mod-set-configuration-change"]={technology="recipe-prod-research_iron-1",level=3,target_recipe="mir-upgrade-removed-iron-plate",source_only_mod="mir-fixture-upgrade-modset-source"}
}
local profile=profiles[archetype]
if not profile then error("unknown MIR upgrade archetype "..tostring(archetype)) end
local function fail(message) error("MIR "..from_version.." to "..to_version.." "..archetype.." upgrade validation failed: "..message) end
local function technology() local value=game.forces.player.technologies[profile.technology];if not value then fail("missing technology "..profile.technology) end;return value end
local function science_names(value) local out={};for _,ingredient in pairs(value.research_unit_ingredients or {}) do table.insert(out,ingredient.name) end;table.sort(out);return out end
local function same_names(left,right) if #left~=#right then return false end;for index,value in ipairs(left) do if value~=right[index] then return false end end;return true end
local function has_recipe_effect(value,recipe_name) for _,effect in pairs((value.prototype and value.prototype.effects) or {}) do if effect.type=="change-recipe-productivity" and effect.recipe==recipe_name then return true end end;return false end

-- The 4.2 Space Age regression removed research outside the former one-owner
-- sample. Its specialized upgrade must preserve every existing technology's
-- state and every recipe's live research bonus, including the reported rows.
-- Escaped version patterns survive the runner's exact template substitutions.
local complete_catalogue_upgrade = archetype == "space-age-native-owner"
  and (from_version:match("^4%.1%.21000$") or from_version:match("^4%.2%.210%d%d$"))
  and to_version:match("^4%.2%.210%d%d$")
local force_effect_fields = {
  "artillery_range_modifier", "beacon_distribution_modifier", "belt_stack_size_bonus",
  "bulk_inserter_capacity_bonus", "character_build_distance_bonus", "character_health_bonus",
  "character_inventory_slots_bonus", "character_item_drop_distance_bonus",
  "character_item_pickup_distance_bonus", "character_loot_pickup_distance_bonus",
  "character_reach_distance_bonus", "character_resource_reach_distance_bonus",
  "character_running_speed_modifier", "following_robots_lifetime_modifier",
  "inserter_stack_size_bonus", "laboratory_productivity_bonus", "laboratory_speed_modifier",
  "manual_crafting_speed_modifier", "manual_mining_speed_modifier", "mining_drill_productivity_bonus",
  "train_braking_force_bonus", "worker_robots_battery_modifier",
  "worker_robots_speed_modifier", "worker_robots_storage_bonus"
}
local function scalar_copy(value)
  if type(value) == "table" then
    local out = {}
    for key, item in pairs(value) do
      if type(key) ~= "string" and type(key) ~= "number" then fail("non-scalar snapshot key") end
      out[key] = scalar_copy(item)
    end
    return out
  end
  if value == nil or type(value) == "string" or type(value) == "number" or type(value) == "boolean" then return value end
  fail("unsupported snapshot value " .. type(value))
end
local function equal_state(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) == "number" then return math.abs(left - right) <= epsilon end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal_state(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end
local function prototype_state(technology)
  local prototype = technology.prototype
  if not prototype then fail("technology prototype missing: " .. technology.name) end
  local prerequisites = {}
  for name in pairs(prototype.prerequisites) do prerequisites[#prerequisites + 1] = name end
  table.sort(prerequisites)
  local ingredients = {}
  for _, ingredient in pairs(technology.research_unit_ingredients) do
    ingredients[#ingredients + 1] = {name = ingredient.name, amount = ingredient.amount}
  end
  table.sort(ingredients, function(a, b) return a.name < b.name end)
  return {
    order = prototype.order, hidden = prototype.hidden,
    hidden_in_factoriopedia = prototype.hidden_in_factoriopedia,
    max_level = prototype.max_level, prerequisites = prerequisites,
    ingredients = ingredients, effects = scalar_copy(prototype.effects),
    unit_count = technology.research_unit_count,
    unit_count_formula = technology.research_unit_count_formula or false,
    unit_energy = technology.research_unit_energy
  }
end
local function complete_state(force)
  local state = {technologies = {}, bonuses = {}, queue = {}, effects = {}, settings = {}}
  for name, technology in pairs(force.technologies) do
    state.technologies[name] = {
      level = technology.level, researched = technology.researched,
      enabled = technology.enabled, visible_when_disabled = technology.visible_when_disabled,
      saved_progress = technology.saved_progress, prototype = prototype_state(technology)
    }
  end
  for _, name in ipairs(force_effect_fields) do
    if type(force[name]) ~= "number" then fail("force effect unavailable: " .. name) end
    state.effects[name] = force[name]
  end
  for name, setting in pairs(settings.startup) do state.settings[name] = scalar_copy(setting.value) end
  for name, recipe in pairs(force.recipes) do state.bonuses[name] = recipe.productivity_bonus end
  for _, technology in ipairs(force.research_queue or {}) do state.queue[#state.queue + 1] = technology.name end
  state.current_research = force.current_research and force.current_research.name or false
  state.research_progress = force.research_progress
  return state
end
local function verify_complete_state(force, expected)
  local observed = complete_state(force)
  local technology_count, recipe_count = 0, 0
  for name, before in pairs(expected.technologies) do
    local after = force.technologies[name]
    if not after then fail("existing technology disappeared: " .. name) end
    if after.level ~= before.level or after.researched ~= before.researched or after.enabled ~= before.enabled then
      fail("existing technology state changed: " .. name)
    end
    if math.abs(after.saved_progress - before.saved_progress) > epsilon then fail("saved research progress changed: " .. name) end
    if after.visible_when_disabled ~= before.visible_when_disabled then fail("technology visibility changed: " .. name) end
    if not equal_state(observed.technologies[name].prototype, before.prototype) then fail("technology definition changed: " .. name) end
    technology_count = technology_count + 1
  end
  for name, before in pairs(expected.bonuses) do
    local after = force.recipes[name]
    if not after or math.abs(after.productivity_bonus - before) > epsilon then fail("recipe research bonus changed: " .. name) end
    recipe_count = recipe_count + 1
  end
  local queue = {}
  for _, technology in ipairs(force.research_queue or {}) do queue[#queue + 1] = technology.name end
  if not same_names(queue, expected.queue) then fail("research queue changed") end
  if not equal_state(observed.effects, expected.effects) then fail("earned force effect changed") end
  if not equal_state(observed.settings, expected.settings) then fail("startup/imported settings changed") end
  if observed.current_research ~= expected.current_research or not equal_state(observed.research_progress, expected.research_progress) then fail("active research progress changed") end
  for _, name in ipairs({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_ice-1", "recipe-prod-research_science_pack_productivity-1"}) do
    if not force.technologies[name] then fail("reported technology absent: " .. name) end
  end
  for name, after in pairs(observed.technologies) do
    if not expected.technologies[name] and after.researched then fail("new research was awarded without earning it: " .. name) end
  end
  log("[mir-fixture] complete Space Age state retained technologies=" .. technology_count .. " recipes=" .. recipe_count)
end
local function all_force_states()
  local out = {}
  for name, force in pairs(game.forces) do out[name] = complete_state(force) end
  return out
end
local function export_state(stage)
  -- Independent evaluator output. Product code never reads this snapshot.
  helpers.write_file("mir-upgrade-full-state-" .. stage .. ".json", helpers.table_to_json({
    from_version = from_version, to_version = to_version, stage = stage,
    active_mods = scalar_copy(script.active_mods), forces = all_force_states()
  }))
end
local function verify_all_forces(expected)
  for name, state in pairs(expected) do
    local force = game.forces[name]
    if not force then fail("force disappeared: " .. name) end
    verify_complete_state(force, state)
  end
end

script.on_init(function()
  if script.active_mods["more-infinite-research"]~=from_version then fail("source save used wrong MIR version") end
  if profile.requires_space_age and not script.active_mods["space-age"] then fail("Space Age was not active") end
  if archetype=="base-default" and script.active_mods["space-age"] then fail("Space Age was unexpectedly active") end
  if profile.source_only_mod and not script.active_mods[profile.source_only_mod] then fail("source-only mod was not active") end
  local force=game.forces.player;local tech=technology()
  if profile.target_recipe and not has_recipe_effect(tech,profile.target_recipe) then fail("technology did not target source recipe") end
  force.research_all_technologies();tech.level=profile.level
  if not force.add_research(tech) then fail("could not queue research") end
  force.research_progress=expected_progress
  storage.mir_upgrade_fixture={archetype=archetype,technology=profile.technology,technology_level=tech.level,research_progress=force.research_progress,research_unit_count=tech.research_unit_count,science=science_names(tech),source_version=from_version}
  if complete_catalogue_upgrade then
    storage.mir_upgrade_fixture.complete_state = complete_state(force)
    storage.mir_upgrade_fixture.complete_forces = all_force_states()
    export_state("source")
  end
  log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"]~=to_version then fail("upgraded save used wrong MIR version") end
  local state=storage.mir_upgrade_fixture;if not state or state.source_version~=from_version then fail("fixture storage did not survive") end
  local force=game.forces.player;local tech=technology()
  if tech.level~=state.technology_level then fail("technology level did not survive") end
  if not force.current_research or force.current_research.name~=profile.technology then fail("current research did not survive") end
  local expected=math.max(0,math.min(1,state.research_progress*state.research_unit_count/tech.research_unit_count))
  if math.abs((force.research_progress or 0)-expected)>epsilon then fail("completed research work changed") end
  if not same_names(state.science,science_names(tech)) then fail("science ingredients changed") end
  if archetype=="space-age-native-owner" then
    if tech.prototype.max_level<4294967295 then fail("native owner is not losslessly infinite") end
    if settings.startup["ips-max-level-research_low_density_structure"].value~=profile.expected_absolute_cap then fail("absolute cap changed") end
  elseif archetype=="automatic-family-creation" and not has_recipe_effect(tech,profile.target_recipe) then fail("automatic-family effect disappeared")
  elseif archetype=="mod-set-configuration-change" then if script.active_mods[profile.source_only_mod] or prototypes.recipe[profile.target_recipe] or has_recipe_effect(tech,profile.target_recipe) then fail("removed subject survived sanitation") end end
  if complete_catalogue_upgrade then
    if not state.complete_state then fail("complete source state missing") end
    if not state.complete_forces then fail("complete source forces missing") end
    verify_all_forces(state.complete_forces)
    export_state("upgrade")
  end
  state.upgrade_complete=true;log("[mir-fixture] "..from_version.." to "..to_version.." upgrade proof complete archetype="..archetype)
end)
local checked_complete_reload = false
script.on_event(defines.events.on_tick,function()
  local state=storage.mir_upgrade_fixture
  if state and state.upgrade_complete then
    if complete_catalogue_upgrade and not checked_complete_reload then
      verify_all_forces(state.complete_forces)
      export_state("reload")
      checked_complete_reload = true
    end
    if not state.server_save_requested then state.server_save_requested=true;game.server_save("mir-4121000-upgraded") end
  end
end)
script.on_load(function() if storage.mir_upgrade_fixture and storage.mir_upgrade_fixture.upgrade_complete then log("[mir-fixture] "..to_version.." upgraded save reload proof complete archetype="..archetype) end end)

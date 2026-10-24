local KEY = "mir5_scripted_effects_multiplayer"
local CASE = "scripted-effects-multiplayer"
local RESTART_SAVE = "mir5-scripted-effects-multiplayer-restart"
local FINAL_SAVE = "mir5-native-complete"
local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE = "recipe-prod-research_spoilage_preservation-1"
local EXPECTED_CLIENTS = {MIR5English = "en", MIR5Deutsch = "de"}
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "space-science-pack", "agricultural-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack"
}
local SPOIL_TICKS = 600
local EXTERNAL_BASELINE = 2
local EXTERNAL_REBASE = 3
local EFFECT_PERCENT = 1
local WALL_DAMAGE = 40
local DEADLINE_TICKS = 24000

local loaded, ready_logged, completed_logged

local function fail(message)
  error("[mir5-scripted-effects-multiplayer] " .. message)
end

local function close(actual, expected, tolerance)
  return type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 0.000001)
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if not value then fail("missing generated technology " .. name) end
  return value
end

local function all_active_mods()
  local expected = {
    base = "2.0.77", ["elevated-rails"] = "2.0.77", quality = "2.0.77", ["space-age"] = "2.0.77",
    ["more-infinite-research"] = "5.0.20000",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0",
    ["mir-fixture-mir5-scripted-effects-multiplayer"] = "0.1.0"
  }
  for name, version in pairs(script.active_mods) do
    if expected[name] ~= version then fail("unexpected multiplayer closure member " .. tostring(name)) end
  end
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then fail("required multiplayer closure member is absent " .. name) end
  end
end

local function player_for_name(name)
  for _, player in pairs(game.players) do
    if player and player.valid ~= false and player.name == name then return player end
  end
  return nil
end

local function two_connected_clients(state)
  local first_index
  for name, locale in pairs(EXPECTED_CLIENTS) do
    local player = player_for_name(name)
    if not player or player.connected ~= true then return false end
    if player.locale == nil then return false end
    if player.locale ~= locale then fail("client locale differs for " .. name) end
    if first_index == player.index then fail("two clients reused one player index") end
    first_index = player.index
  end
  return true
end

local function marker(stage, state)
  log("[MIR5_SCRIPTED_EFFECTS_MULTIPLAYER] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage, status = "passed",
    witnesses = {
      actual_join_events = state.join_events,
      two_connected_clients_required = true,
      runtime_owned_state_checked = state.runtime_owned_state_checked == true,
      physical_rates_checked = state.physical_rates_checked == true,
      foreign_offsets_preserved = state.foreign_offsets_preserved == true,
      expected_client_locales = {MIR5English = "en", MIR5Deutsch = "de"},
      actual_target_completions = {
        agricultural_growth_speed = state.agriculture_finished or 0,
        spoilage_preservation = state.spoilage_finished or 0
      },
      external_spoilage = {
        initial_baseline = EXTERNAL_BASELINE,
        after_player_level = state.after_player_level,
        after_external_force = state.after_external_force,
        after_force_merge = state.after_force_merge,
        player_spoilage_level_after_merge = state.player_spoilage_level_after_merge,
        after_external_rebase = state.after_external_rebase
      },
      agriculture = {
        player_remaining_ticks = state.player_remaining,
        comparison_remaining_ticks = state.comparison_remaining,
        native_growth_ticks = state.growth_ticks
      },
      spoilage = {
        fixture_item_spoil_ticks = SPOIL_TICKS,
        expected_scaled_ticks = state.expected_spoil_ticks,
        observed_player_ticks = state.player_spoil_ticks,
        observed_comparison_ticks = state.comparison_spoil_ticks,
        spoiled_physically = state.spoiled == true
      },
      passive_repair = {
        player_repaired = state.player_repaired == true,
        comparison_repaired = state.comparison_repaired == true,
        restart_queue_seeded = state.restart_queue_seeded == true,
        restart_repaired = state.restart_repaired == true
      },
      force_lifecycle = {
        created = state.offset_force_created == true,
        reset_observed = state.offset_reset_observed == true,
        merged = state.offset_force_merged == true
      },
      host_restart_observed = state.host_restart_observed == true,
      on_load_read_only = state.on_load_read_only == true,
      rendering_qualified = false,
      performance_or_stress_qualified = false,
      gameplay_scope = "disposable-f200-space-age-scripted-effects-multiplayer-only"
    }
  }))
end

local function start_research(force, name)
  local value = technology(force, name)
  if value.enabled ~= true or force.current_research ~= nil or not force.add_research(value) then
    fail("could not start real lab research " .. name)
  end
end

local function prepare_target(force, name)
  local value = technology(force, name)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
  if value.level ~= 1 or value.researched then fail("target did not start at native level one " .. name) end
  value.enabled, value.visible_when_disabled = true, false
end

local function set_yumako_soil(surface, center)
  local tiles = {}
  for x = center.x - 5, center.x + 5 do
    for y = center.y - 5, center.y + 5 do
      tiles[#tiles + 1] = {name = "natural-yumako-soil", position = {x = x, y = y}}
    end
  end
  surface.set_tiles(tiles)
  if surface.get_tile(center).name ~= "natural-yumako-soil" then fail("could not prepare native yumako soil") end
end

local function create_tower(surface, position, force)
  local tower = surface.create_entity{name = "agricultural-tower", position = position, force = force}
  if not tower or tower.valid == false then fail("could not create native agricultural tower") end
  tower.energy = 100000000
  local inventory = tower.get_inventory(defines.inventory.agricultural_tower_input)
  if not inventory or inventory.insert{name = "yumako-seed", count = 1} ~= 1 then
    fail("could not insert native yumako seed")
  end
  return tower
end

local function create_spoilage_chest(surface, position, force)
  local chest = surface.create_entity{name = "wooden-chest", position = position, force = force}
  if not chest or chest.valid == false then fail("could not create native spoilage chest") end
  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory or inventory.insert{name = "yumako", count = 1} ~= 1 then fail("could not insert native yumako") end
  local stack = inventory[1]
  if not stack or not stack.valid_for_read or stack.name ~= "yumako" or type(stack.spoil_tick) ~= "number" then
    fail("native yumako stack has no spoil clock")
  end
  return chest, stack.spoil_tick - game.tick
end

local function create_damaged_wall(surface, position, force)
  local wall = surface.create_entity{name = "stone-wall", position = position, force = force}
  if not wall or wall.valid == false or type(wall.health) ~= "number" or type(wall.max_health) ~= "number" then
    fail("could not create native wall with health")
  end
  wall.damage(WALL_DAMAGE, game.forces.enemy, "physical")
  if wall.health >= wall.max_health then fail("native damage did not reduce wall health") end
  return wall, wall.health
end

local function assert_target_completions(state)
  local force = game.forces.player
  for _, name in ipairs({AGRICULTURE, SPOILAGE}) do
    local value = technology(force, name)
    if value.level ~= 2 or value.researched or force.current_research ~= nil then
      fail("actual target completion state differs for " .. name)
    end
  end
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input is absent after completions") end
  for _, name in ipairs(SCIENCE) do
    local expected = (name == "electromagnetic-science-pack" or name == "space-science-pack") and 1 or 2
    local consumed = state.initial_science - inventory.get_item_count(name)
    if consumed ~= expected then fail("real lab consumption differs for " .. name) end
  end
end

local function start_labs(state)
  local surface, force = game.surfaces.nauvis, game.forces.player
  if not surface then fail("Nauvis is absent") end
  surface.request_to_generate_chunks({x = 64, y = 0}, 1)
  surface.request_to_generate_chunks({x = -64, y = 0}, 1)
  surface.force_generate_chunk_requests()
  force.enable_all_prototypes()
  prepare_target(force, AGRICULTURE)
  prepare_target(force, SPOILAGE)
  game.difficulty_settings.spoil_time_modifier = EXTERNAL_BASELINE
  local lab = surface.create_entity{name = "lab", position = force.get_spawn_position(surface), force = force}
  if not lab or lab.valid == false then fail("could not create real lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name = name, count = 8} ~= 8 then fail("lab rejected " .. name) end
  end
  lab.energy = 100000000
  state.lab, state.initial_science = lab, 8
  state.phase, state.deadline = "researching", game.tick + DEADLINE_TICKS
  start_research(force, AGRICULTURE)
end

local function begin_force_lifecycle(state)
  assert_target_completions(state)
  local expected = EXTERNAL_BASELINE * (1 + EFFECT_PERCENT / 100)
  if not close(game.difficulty_settings.spoil_time_modifier, expected) then
    fail("player spoilage contribution did not retain its external baseline")
  end
  state.after_player_level = game.difficulty_settings.spoil_time_modifier
  local offset = game.create_force("mir5-scripted-effects-offset")
  offset.enable_all_prototypes()
  local foreign = technology(offset, SPOILAGE)
  if foreign.level ~= 1 or foreign.researched then fail("offset force did not start at level one") end
  foreign.level = 3 -- independently supplied force offset; not an earned fixture level.
  offset.reset_technology_effects()
  state.offset_force_name, state.offset_force_created, state.phase = offset.name, true, "awaiting-offset-reset"
end

local function begin_physical_witnesses(state)
  local surface, player = game.surfaces.nauvis, game.forces.player
  local comparison = game.create_force("mir5-scripted-effects-comparison")
  comparison.enable_all_prototypes()
  -- F200 orders LuaForce.set_friend arguments as (other, friend).
  comparison.set_friend(player, true)
  player.set_friend(comparison, true)
  if technology(comparison, AGRICULTURE).level ~= 1 or technology(comparison, SPOILAGE).level ~= 1 then
    fail("comparison force did not retain zero scripted research")
  end
  local player_center, comparison_center = {x = 64, y = 0}, {x = -64, y = 0}
  set_yumako_soil(surface, player_center)
  set_yumako_soil(surface, comparison_center)
  state.player_tower = create_tower(surface, player_center, player)
  state.comparison_tower = create_tower(surface, comparison_center, comparison)
  state.player_chest, state.player_spoil_ticks = create_spoilage_chest(surface, {x = 64, y = 12}, player)
  state.comparison_chest, state.comparison_spoil_ticks = create_spoilage_chest(surface, {x = -64, y = 12}, comparison)
  state.expected_spoil_ticks = SPOIL_TICKS * EXTERNAL_REBASE
  if math.abs(state.player_spoil_ticks - state.expected_spoil_ticks) > 1
      or math.abs(state.comparison_spoil_ticks - state.expected_spoil_ticks) > 1 then
    fail("native spoil clocks did not retain the externally rebased global modifier")
  end
  state.player_wall, state.player_wall_initial = create_damaged_wall(surface, {x = 64, y = 24}, player)
  state.comparison_wall, state.comparison_wall_initial = create_damaged_wall(surface, {x = -64, y = 24}, comparison)
  state.spoil_start_tick, state.comparison_force_index, state.phase = game.tick, comparison.index, "physical"
end

local function assert_physical_witnesses(state)
  if not state.player_plant or not state.comparison_plant then fail("native tower planting witness is absent") end
  if state.player_remaining ~= math.floor(state.growth_ticks / (1 + EFFECT_PERCENT / 100))
      or state.comparison_remaining ~= state.growth_ticks then
    fail("native agricultural event timing differs")
  end
  if not state.spoiled then fail("fixture-only native yumako spoil clock did not complete") end
  if state.player_wall.health < state.player_wall_initial + 1
      or state.comparison_wall.health < state.comparison_wall_initial + 1 then
    fail("passive repair did not restore one actual damaged wall health")
  end
  state.player_repaired, state.comparison_repaired = true, true
  state.physical_rates_checked = true
end

local function seed_restart_repair(state)
  local surface = game.surfaces.nauvis
  state.restart_wall, state.restart_wall_initial = create_damaged_wall(surface, {x = 0, y = 24}, game.forces.player)
  state.restart_hold_damage_tick = game.tick
  state.restart_wall_unit = state.restart_wall.unit_number
  state.restart_wall_pre_restart_health = state.restart_wall.health
  state.restart_queue_seeded, state.phase = true, "awaiting-host-restart"
  game.server_save(RESTART_SAVE)
  marker("restart-ready", state)
end

local function restart_wall_pending(state)
  if not state.restart_wall or state.restart_wall.valid == false then fail("restart repair wall is absent") end
  -- Keep a real damage queue pending while the external controller shuts down
  -- the first host. Damage stops after the next host's read-only load phase.
  if game.tick >= state.restart_hold_damage_tick + 60 then
    state.restart_wall.damage(1, game.forces.enemy, "physical")
    state.restart_hold_damage_tick = game.tick
  end
end

local function check_loaded_state(state)
  if not loaded then return end
  if state.phase ~= loaded.phase or state.join_events ~= loaded.join_events
      or not close(state.after_external_rebase, loaded.spoil_modifier)
      or state.restart_wall_unit ~= loaded.restart_wall_unit
      or not close(state.restart_wall_pre_restart_health, loaded.restart_wall_health)
      or not state.restart_wall or state.restart_wall.unit_number ~= loaded.restart_wall_unit
      or not close(state.restart_wall.health, loaded.restart_wall_health) then
    fail("on_load changed a durable scripted-effect multiplayer witness")
  end
  state.host_restart_observed, state.on_load_read_only = true, true
  state.phase = "awaiting-final-clients"
  loaded = nil
end

local function complete(state)
  if state.join_events ~= 6 or not two_connected_clients(state) then fail("completed without two final connected clients") end
  if state.host_restart_observed ~= true or state.on_load_read_only ~= true then
    fail("completed without a read-only host restart witness")
  end
  if state.restart_wall.health < state.restart_wall_post_load_health + 1 then
    return
  end
  if not close(game.difficulty_settings.spoil_time_modifier, EXTERNAL_REBASE) then
    fail("external rebased spoilage modifier changed after host restart")
  end
  if technology(game.forces.player, AGRICULTURE).level ~= 2 or technology(game.forces.player, SPOILAGE).level ~= 2 then
    fail("earned scripted research changed after host restart")
  end
  state.restart_repaired, state.phase = true, "complete"
  marker("completed", state)
  completed_logged = true
  game.server_save(FINAL_SAVE)
end

script.on_init(function()
  all_active_mods()
  if settings.startup["mir-enable-passive-repair"].value ~= true then fail("passive repair was not enabled") end
  for _, family in ipairs({"research_agricultural_growth_speed", "research_spoilage_preservation"}) do
    if settings.startup["ips-cost-base-" .. family].value ~= 1
        or settings.startup["ips-cost-linear-increment-" .. family].value ~= 0
        or settings.startup["ips-cost-growth-" .. family].value ~= 1
        or settings.startup["ips-max-level-" .. family].value ~= 0
        or settings.startup["ips-research-time-" .. family].value ~= 1
        or settings.startup["ips-effect-per-level-" .. family].value ~= EFFECT_PERCENT then
      fail("accelerated fixture settings differ for " .. family)
    end
  end
  storage[KEY] = {phase = "waiting-initial-clients", join_events = 0, client_joins = {}}
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.phase == "awaiting-host-restart" and {
    phase = state.phase, join_events = state.join_events,
    spoil_modifier = state.after_external_rebase,
    restart_wall_unit = state.restart_wall_unit,
    restart_wall_health = state.restart_wall_pre_restart_health
  } or nil
  ready_logged, completed_logged = false, false
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local state = storage[KEY]
  local player = event and game.get_player(event.player_index)
  if not state or not player or player.connected ~= true or EXPECTED_CLIENTS[player.name] == nil then
    fail("join did not identify an expected actually connected client")
  end
  state.client_joins[player.name] = (state.client_joins[player.name] or 0) + 1
  state.join_events = state.join_events + 1
  log("[MIR5_SCRIPTED_EFFECTS_MULTIPLAYER_JOIN] " .. player.name .. " " .. tostring(state.client_joins[player.name]))
end)

script.on_event(defines.events.on_player_locale_changed, function(event)
  local player = event and game.get_player(event.player_index)
  if player and EXPECTED_CLIENTS[player.name] and player.locale ~= nil and player.locale ~= EXPECTED_CLIENTS[player.name] then
    fail("locale event supplied the wrong client locale")
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research or event.research.force ~= game.forces.player then return end
  if event.research.name == AGRICULTURE then
    state.agriculture_finished = (state.agriculture_finished or 0) + 1
    if state.agriculture_finished ~= 1 then fail("unexpected agricultural completion count") end
    state.next_research = SPOILAGE
  elseif event.research.name == SPOILAGE then
    state.spoilage_finished = (state.spoilage_finished or 0) + 1
    if state.spoilage_finished ~= 1 then fail("unexpected spoilage completion count") end
    state.next_research = nil
    state.phase = "begin-force-lifecycle"
  end
end)

script.on_event(defines.events.on_tower_planted_seed, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "physical" or not event.tower or not event.plant then return end
  local kind
  if state.player_tower and event.tower.unit_number == state.player_tower.unit_number then kind = "player"
  elseif state.comparison_tower and event.tower.unit_number == state.comparison_tower.unit_number then kind = "comparison"
  else return end
  if event.plant.name ~= "yumako-tree" or type(event.plant.prototype.growth_ticks) ~= "number" then
    fail("native tower supplied an unexpected plant")
  end
  local remaining = event.plant.tick_grown - event.tick
  if kind == "player" then
    if state.player_plant or remaining ~= math.floor(event.plant.prototype.growth_ticks / (1 + EFFECT_PERCENT / 100)) then
      fail("trained agricultural tower timing differs")
    end
    state.player_plant, state.player_remaining = event.plant, remaining
  else
    if state.comparison_plant or remaining ~= event.plant.prototype.growth_ticks then
      fail("zero-research comparison tower timing differs")
    end
    state.comparison_plant, state.comparison_remaining = event.plant, remaining
  end
  state.growth_ticks = event.plant.prototype.growth_ticks
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end
  -- on_load records scalar witnesses only. Validate them at the first
  -- game-available tick before dispatching the saved pre-restart phase.
  if loaded then check_loaded_state(state) end
  if state.phase == "waiting-initial-clients" then
    if not ready_logged then marker("ready", state); ready_logged = true end
    if two_connected_clients(state) and state.join_events == 2 then start_labs(state) end
    return
  end
  if state.phase == "researching" then
    if game.tick > state.deadline then fail("real scripted-effect labs did not complete") end
    if state.lab and state.lab.valid then state.lab.energy = 100000000 end
    if state.next_research and game.forces.player.current_research == nil then
      local next_research = state.next_research
      state.next_research = nil
      start_research(game.forces.player, next_research)
    end
    return
  end
  if state.phase == "begin-force-lifecycle" then begin_force_lifecycle(state); return end
  if state.phase == "awaiting-offset-reset" then
    local expected = EXTERNAL_BASELINE * ((1 + EFFECT_PERCENT / 100) ^ 2)
    if not close(game.difficulty_settings.spoil_time_modifier, expected) then
      fail("highest external force did not change the global spoilage multiplier")
    end
    state.after_external_force, state.offset_reset_observed = game.difficulty_settings.spoil_time_modifier, true
    game.merge_forces(game.forces[state.offset_force_name], game.forces.player)
    state.phase = "awaiting-force-merge"
    return
  end
  if state.phase == "awaiting-force-merge" then
    if game.forces[state.offset_force_name] ~= nil then return end
    -- The F200 LuaGameScript merge contract retains technologies from the
    -- destination force. Read that destination only after the source has
    -- actually disappeared; do not infer it from the higher source level.
    local player_spoilage = technology(game.forces.player, SPOILAGE)
    if player_spoilage.level ~= 2 or player_spoilage.researched then
      fail("native force merge did not retain the player spoilage research state")
    end
    local expected = EXTERNAL_BASELINE * (1 + EFFECT_PERCENT / 100)
    if not close(game.difficulty_settings.spoil_time_modifier, expected) then
      fail("merged offset force left a stale spoilage contribution")
    end
    state.after_force_merge = game.difficulty_settings.spoil_time_modifier
    state.player_spoilage_level_after_merge, state.offset_force_merged = player_spoilage.level, true
    game.difficulty_settings.spoil_time_modifier = EXTERNAL_REBASE
    game.forces.player.reset_technology_effects()
    state.phase = "awaiting-external-rebase"
    return
  end
  if state.phase == "awaiting-external-rebase" then
    if not close(game.difficulty_settings.spoil_time_modifier, EXTERNAL_REBASE) then
      fail("external spoilage offset was not preserved through native effect reset")
    end
    state.after_external_rebase = game.difficulty_settings.spoil_time_modifier
    state.runtime_owned_state_checked = true
    state.foreign_offsets_preserved = true
    begin_physical_witnesses(state)
    return
  end
  if state.phase == "physical" then
    if game.tick > state.deadline then fail("native physical scripted-effects witnesses did not complete") end
    if state.player_tower and state.player_tower.valid then state.player_tower.energy = 100000000 end
    if state.comparison_tower and state.comparison_tower.valid then state.comparison_tower.energy = 100000000 end
    local player_inventory = state.player_chest and state.player_chest.valid and state.player_chest.get_inventory(defines.inventory.chest)
    local comparison_inventory = state.comparison_chest and state.comparison_chest.valid and state.comparison_chest.get_inventory(defines.inventory.chest)
    if player_inventory and comparison_inventory and player_inventory.get_item_count("yumako") == 0
        and comparison_inventory.get_item_count("yumako") == 0
        and player_inventory.get_item_count("spoilage") >= 1 and comparison_inventory.get_item_count("spoilage") >= 1 then
      state.spoiled = true
    end
    if game.tick > state.spoil_start_tick + state.expected_spoil_ticks + 120 and not state.spoiled then
      fail("fixture-only native spoil clocks did not complete in their bounded interval")
    end
    if state.player_wall.health >= state.player_wall_initial + 1 then state.player_repaired = true end
    if state.comparison_wall.health >= state.comparison_wall_initial + 1 then state.comparison_repaired = true end
    if state.player_plant and state.comparison_plant and state.spoiled and state.player_repaired and state.comparison_repaired then
      assert_physical_witnesses(state)
      state.phase = "awaiting-rejoin"
      marker("rejoin-ready", state)
    end
    return
  end
  if state.phase == "awaiting-rejoin" then
    if state.join_events == 4 and two_connected_clients(state) then seed_restart_repair(state) end
    return
  end
  if state.phase == "awaiting-host-restart" then restart_wall_pending(state); return end
  if state.phase == "awaiting-final-clients" then
    if state.phase == "awaiting-final-clients" and state.join_events == 6 and two_connected_clients(state) then
      state.restart_wall_post_load_health = state.restart_wall.health
      state.phase = "validating-after-restart"
    end
    return
  end
  if state.phase == "validating-after-restart" then
    complete(state)
    return
  end
  if state.phase == "complete" then return end
  fail("unknown fixture phase " .. tostring(state.phase))
end)

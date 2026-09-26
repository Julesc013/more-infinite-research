-- Exercise the materialized MIR host through real damage and saved gameplay.
-- This fixture never calls MIR's repair service or accesses its private state.
local options = require("probe_options")
local loaded = false
local function check(value, message)
  assert(value, message)
  storage.assertions = (storage.assertions or 0) + 1
end
local function close(a, b) return math.abs(a - b) < 0.001 end
local function write_result(phase)
  helpers.write_file("passive-repair-host-" .. phase .. ".json", helpers.table_to_json{
    status = "passed", phase = phase, assertions = storage.assertions,
    enabled = options.enabled, tick = game.tick,
    scope = options.enabled and "materialized-MIR-native-damage-quiet-repair-force-deletion-and-save-reload" or "materialized-MIR-default-off-native-damage-remains-unrepaired"
  }, false)
end
script.on_load(function() loaded = true end)
script.on_init(function()
  check(settings.startup["mir-enable-passive-repair"].value == options.enabled, "actual startup option matches probe")
  local surface = game.create_surface("mir-passive-repair-host", {
    width = 64, height = 64,
    autoplace_settings = {entity = {treat_missing_as_default = false}, decorative = {treat_missing_as_default = false}}
  })
  surface.request_to_generate_chunks({0, 0}, 1)
  surface.force_generate_chunk_requests()
  local force = game.create_force("mir-passive-repair-friendly")
  force.set_friend(game.forces.player, true)
  game.forces.player.set_friend(force, true)
  local hostile = game.create_force("mir-passive-repair-hostile")
  local one_way = game.create_force("mir-passive-repair-one-way")
  game.forces.player.set_friend(one_way, true)
  local function entity(name, x, owner)
    local value = surface.create_entity{name = name, position = {x, 0}, force = owner or "player"}
    assert(value and value.valid, "host fixture entity created")
    return value
  end
  storage.wall = entity("stone-wall", 0)
  storage.gate = entity("gate", 3, force)
  storage.transferred = entity("stone-wall", 6)
  storage.deleted = entity("stone-wall", 9)
  storage.chest = entity("steel-chest", 12)
  storage.hostile = entity("stone-wall", 15, hostile)
  storage.one_way = entity("stone-wall", 18, one_way)
  storage.phase = "fresh"
end)
script.on_event(defines.events.on_tick, function(event)
  if event.tick == 2 and storage.phase == "fresh" then
    for _, key in ipairs{"wall", "gate", "transferred", "deleted", "chest", "hostile", "one_way"} do
      local entity = storage[key]
      local before = entity.health
      entity.damage(20, game.forces.enemy, "physical")
      check(entity.valid and entity.health > 0 and entity.health < before, "native damage: " .. key)
    end
    storage.wall_health = storage.wall.health
    storage.gate_health = storage.gate.health
    storage.transferred_health = storage.transferred.health
    storage.chest_health = storage.chest.health
    storage.hostile_health = storage.hostile.health
    storage.one_way_health = storage.one_way.health
    storage.transferred.force = game.forces.enemy
    storage.deleted.destroy()
    storage.phase = "waiting"
  end
  if event.tick == 120 and storage.phase == "waiting" and options.enabled then
    check(close(storage.wall.health, storage.wall_health), "quiet wall unchanged before pending save")
    storage.phase = "pending-saved"
    game.auto_save("mir-passive-repair-pending")
  end
  if event.tick == 600 then
    check(close(storage.wall.health, storage.wall_health) and close(storage.gate.health, storage.gate_health), "quiet interval survives real pending save/load")
  end
  -- on_tick runs before this tick's on_nth_tick callback; observe afterward.
  if event.tick == 661 then
    local gain = options.enabled and 1 or 0
    check(close(storage.wall.health, storage.wall_health + gain), "native wall callback repairs after quiet time: " .. storage.wall.health .. "/" .. (storage.wall_health + gain))
    check(close(storage.gate.health, storage.gate_health + gain), "custom friendly force gate repairs independently")
    check(close(storage.transferred.health, storage.transferred_health), "transferred entity receives no foreign repair")
    check(close(storage.chest.health, storage.chest_health), "non-allowlisted chest receives no repair")
    check(close(storage.hostile.health, storage.hostile_health), "custom hostile force receives no repair")
    check(close(storage.one_way.health, storage.one_way_health), "one-way friendship is insufficient for repair")
    check(not storage.deleted.valid, "destroyed entity is not revived")
    if options.enabled then
      check(loaded, "pending queue was loaded from an actual saved game")
      storage.phase = "healing-saved"
      game.auto_save("mir-passive-repair-healing")
    end
  end
  if event.tick == 721 then
    local gain = options.enabled and 2 or 0
    check(close(storage.wall.health, storage.wall_health + gain), "repair rate is one health per sixty ticks")
    check(close(storage.gate.health, storage.gate_health + gain), "gate rate matches wall rate")
    write_result(options.enabled and "pending-reload" or "disabled")
  end
  if event.tick == 781 and options.enabled then
    check(loaded and storage.phase == "healing-saved", "healing queue survived a second actual save/load")
    check(close(storage.wall.health, storage.wall_health + 3) and close(storage.gate.health, storage.gate_health + 3), "repair resumes after the second reload")
    write_result("healing-reload")
    script.on_event(defines.events.on_tick, nil)
  elseif event.tick == 722 and not options.enabled then
    script.on_event(defines.events.on_tick, nil)
  end
end)

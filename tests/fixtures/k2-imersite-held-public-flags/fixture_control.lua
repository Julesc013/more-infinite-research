-- Disposable F210 K2SO state-only witness for the public-flag preservation
-- path. It does not import or call MIR internals; the fixed leg is reached by
-- Factorio's ordinary configuration-change event after the fixture version
-- changes from 0.1.0 to 0.2.0.
local M = {}

local KEY = "mir5_k2_imersite_held_public_flags"
local SAVE = "mir5-native-complete"
local CASE = "k2-imersite-held-public-flags"
local FIXTURE = "mir-fixture-mir5-k2-imersite-held-public-flags"
local EARLY = "recipe-prod-research_material_imersite-1"
local TAIL = "recipe-prod-research_material_imersite-4"
local HOLDER = "mir-k2-imersite-staged-state-1"
local CARRIER = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"
local FOREIGN = "mir5-k2-imersite-held-public-flags-foreign"

local loaded, reported = false, false

local function fail(message) error("[mir5-k2-imersite-held-public-flags] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. name) end
  return value
end

local function check_closure(stage)
  if script.active_mods.base ~= "2.1.23" or script.active_mods["elevated-rails"] ~= "2.1.23"
      or script.active_mods.quality ~= "2.1.23" or script.active_mods.recycler ~= "2.1.23"
      or script.active_mods["space-age"] ~= "2.1.23" or script.active_mods.flib ~= "0.17.2"
      or script.active_mods["k2so-assets"] ~= "1.0.7" or script.active_mods.Krastorio2 ~= "2.1.4"
      or script.active_mods["Krastorio2-spaced-out"] ~= "2.0.19" or script.active_mods.Krastorio2Assets ~= "2.1.0"
      or script.active_mods.Krastorio2MenuSimulations ~= "2.1.0"
      or script.active_mods["xy-k2so-enhancements-nulls-fork"] ~= "0.8.3"
      or script.active_mods["more-infinite-research"] ~= "5.0.21000"
      or script.active_mods[FIXTURE] ~= (stage == "source" and "0.1.0" or "0.2.0") then
    fail("F210 K2SO fixture closure differs")
  end
  local setting = settings.startup and settings.startup["ips-max-level-research_material_imersite"]
  if setting == nil or setting.value ~= 0 then fail("K2SO Imersite setting differs") end
end

local function check_effect(value, label)
  local effects = value.prototype and value.prototype.effects
  local effect = effects and effects[1]
  if type(effects) ~= "table" or #effects ~= 1 or type(effect) ~= "table"
      or effect.type ~= "change-recipe-productivity" or effect.recipe ~= POWDER
      or not close(effect.change, 0.02) then
    fail(label .. " Imersite native effect differs")
  end
end

local function queue_is_empty(force, label)
  if force.current_research ~= nil or #(force.research_queue or {}) ~= 0 or not close(force.research_progress, 0) then
    fail(label .. " unexpectedly owns a research queue")
  end
end

local function bonus(force, label)
  local recipe = force.recipes and force.recipes[POWDER]
  if recipe == nil or type(recipe.productivity_bonus) ~= "number" then fail(label .. " powder recipe is absent") end
  return recipe.productivity_bonus
end

local function flags(value, enabled, visible, label)
  if value.enabled ~= enabled or value.visible_when_disabled ~= visible then
    fail(label .. " public enabled/visibility flags differ")
  end
end

local function assert_source(force, label)
  local holder, carrier = technology(force, HOLDER), technology(force, CARRIER)
  check_effect(holder, label .. " detached carrier")
  check_effect(carrier, label .. " continuation carrier")
  if holder.level ~= 4 or holder.researched or not close(holder.saved_progress, 0.27)
      or holder.enabled ~= true or holder.visible_when_disabled ~= false then
    fail(label .. " detached source carrier differs")
  end
  if carrier.level ~= 4 or carrier.researched or carrier.enabled ~= false or carrier.visible_when_disabled ~= false
      or not close(carrier.saved_progress, 0) then
    fail(label .. " inactive source carrier differs")
  end
  if not close(bonus(force, label), 0.06) then fail(label .. " source native powder bonus differs") end
  queue_is_empty(force, label)
  return {holder_level=holder.level, holder_saved_progress=holder.saved_progress, powder_bonus=bonus(force, label)}
end

local function assert_player_fixed(force, label)
  local early, tail = technology(force, EARLY), technology(force, TAIL)
  check_effect(early, label .. " public early")
  check_effect(tail, label .. " public continuation")
  if early.level ~= 3 or early.researched ~= true or not close(early.saved_progress, 0) then
    fail(label .. " public early earned state differs")
  end
  if tail.level ~= 4 or tail.researched or not close(tail.saved_progress, 0.27) then
    fail(label .. " public continuation detached work differs")
  end
  flags(early, false, true, label .. " public early")
  flags(tail, false, false, label .. " public continuation")
  for _, item in ipairs({{HOLDER, 1}, {CARRIER, 4}}) do
    local value = technology(force, item[1])
    check_effect(value, label .. " consumed private carrier")
    if value.level ~= item[2] or value.researched or not close(value.saved_progress, 0)
        or value.enabled or value.visible_when_disabled or value.prototype.hidden ~= true
        or (value.prototype.max_level ~= "infinite" and value.prototype.max_level ~= 4294967295) then
      fail(label .. " consumed private carrier remains active: " .. item[1])
    end
  end
  if not close(bonus(force, label), 0.06) then fail(label .. " retained native powder bonus differs") end
  queue_is_empty(force, label)
  return {early_level=early.level, tail_level=tail.level, tail_saved_progress=tail.saved_progress,
    powder_bonus=bonus(force, label), early_enabled=early.enabled, tail_enabled=tail.enabled}
end

local function assert_foreign(force, label)
  local early, tail = technology(force, EARLY), technology(force, TAIL)
  if early.level ~= 1 or early.researched or not close(early.saved_progress, 0)
      or tail.level ~= 4 or tail.researched or not close(tail.saved_progress, 0) then
    fail(label .. " foreign public Imersite state differs")
  end
  -- This deliberately contrasts the player flags. Neither public row is
  -- queued, avoiding an unproven disabled-queue engine condition.
  flags(early, false, false, label .. " foreign early")
  flags(tail, false, true, label .. " foreign continuation")
  if not close(bonus(force, label), 0) then fail(label .. " foreign Imersite gained productivity") end
  queue_is_empty(force, label)
  return {early_enabled=early.enabled, early_visible=early.visible_when_disabled,
    tail_enabled=tail.enabled, tail_visible=tail.visible_when_disabled}
end

local function marker(stage, player, foreign)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage, status = "passed", qualification = "native-runner-readback-required",
    witnesses = {actual_lab_completions = 0, native_state_seeded = true, no_public_queue = true,
      player_early_level = player.early_level, player_tail_level = player.tail_level,
      player_tail_saved_progress = player.tail_saved_progress, player_powder_bonus = player.powder_bonus,
      player_early_enabled = player.early_enabled, player_tail_enabled = player.tail_enabled,
      foreign_early_enabled = foreign.early_enabled, foreign_tail_enabled = foreign.tail_enabled,
      foreign_early_visible = foreign.early_visible, foreign_tail_visible = foreign.tail_visible,
      on_load_read_only = stage == "reload"},
  }))
end

local function prepare_source()
  local player = game.forces.player
  player.enable_all_prototypes()
  local holder, carrier = technology(player, HOLDER), technology(player, CARRIER)
  -- A level assignment re-enables a LuaTechnology. Keep the detached private
  -- credit active only after the level/progress seed, without using MIR state.
  holder.level = 4
  holder.researched = false
  holder.saved_progress = 0.27
  holder.enabled = true
  holder.visible_when_disabled = false
  carrier.level = 4
  carrier.researched = false
  carrier.saved_progress = 0
  carrier.enabled = false
  carrier.visible_when_disabled = false
  local early, tail = technology(player, EARLY), technology(player, TAIL)
  early.enabled = false
  early.visible_when_disabled = true
  tail.enabled = false
  tail.visible_when_disabled = false
  -- A documented engine reset observes the native seed without calling a MIR
  -- handler. It makes the source native productivity state explicit.
  player.reset_technology_effects()
  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  local foreign_early, foreign_tail = technology(foreign, EARLY), technology(foreign, TAIL)
  foreign_early.enabled = false
  foreign_early.visible_when_disabled = false
  foreign_tail.enabled = false
  foreign_tail.visible_when_disabled = true
  return assert_source(player, "source seed"), assert_foreign(foreign, "source foreign"), foreign.index
end

function M.apply(stage)
  if stage ~= "source" and stage ~= "fixed" then fail("unknown fixture stage") end
  script.on_init(function()
    if stage ~= "source" then fail("only source stage may initialize a fresh save") end
    check_closure(stage)
    if storage[KEY] ~= nil then fail("fixture state already exists") end
    local source, foreign, foreign_index = prepare_source()
    -- --create does not produce the actual server save. The first live server
    -- tick below verifies this state and creates its input save exactly once.
    storage[KEY] = {phase = "source-prepared", source = source, foreign = foreign,
      foreign_index = foreign_index, source_mir_archive = "E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE"}
  end)

  script.on_configuration_changed(function()
    if stage ~= "fixed" then fail("source stage does not accept a successor configuration") end
    check_closure(stage)
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= "source-complete" or type(state.foreign_index) ~= "number" then
      fail("completed E3A source state is absent")
    end
    -- This runs after MIR's ordinary configuration callback. Verify every
    -- public flag and detached state before fixture-owned state is written.
    local player = assert_player_fixed(game.forces.player, "fixed configuration")
    local foreign = assert_foreign(game.forces[state.foreign_index], "fixed configuration")
    state.phase, state.player, state.foreign = "fixed-prepared", player, foreign
  end)

  script.on_load(function()
    -- `on_load` is intentionally local-only: it records no fixture state.
    loaded, reported = true, false
  end)

  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if type(state) ~= "table" then fail("fixture state is absent") end
    if stage == "source" and state.phase == "source-prepared" then
      check_closure(stage)
      local source = assert_source(game.forces.player, "source initial server")
      local foreign = assert_foreign(game.forces[state.foreign_index], "source initial server")
      state.phase, state.source, state.foreign = "source-complete", source, foreign
      marker("initial", {early_level = 0, tail_level = 0, tail_saved_progress = 0, powder_bonus = source.powder_bonus,
        early_enabled = false, tail_enabled = false}, foreign)
      game.server_save(SAVE)
      loaded, reported = false, true
      return
    end
    if stage == "fixed" and state.phase == "fixed-prepared" then
      check_closure(stage)
      local player = assert_player_fixed(game.forces.player, "fixed initial server")
      local foreign = assert_foreign(game.forces[state.foreign_index], "fixed initial server")
      state.phase, state.player, state.foreign = "fixed-complete", player, foreign
      marker("initial", player, foreign)
      game.server_save(SAVE)
      loaded, reported = false, true
      return
    end
    local complete = stage == "source" and "source-complete" or "fixed-complete"
    if state.phase ~= complete then fail("fixture phase does not match loaded stage") end
    if not loaded or reported then return end
    check_closure(stage)
    local player, foreign
    if stage == "source" then
      local source = assert_source(game.forces.player, "source cold reload")
      foreign = assert_foreign(game.forces[state.foreign_index], "source cold reload")
      player = {early_level = 0, tail_level = 0, tail_saved_progress = 0, powder_bonus = source.powder_bonus,
        early_enabled = false, tail_enabled = false}
    else
      player = assert_player_fixed(game.forces.player, "fixed cold reload")
      foreign = assert_foreign(game.forces[state.foreign_index], "fixed cold reload")
    end
    marker("reload", player, foreign)
    reported = true
  end)
end

return M

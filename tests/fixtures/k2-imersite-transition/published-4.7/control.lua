local KEY = "mir5_k2_imersite_transition"
local CASE = "k2-imersite-published-4.7"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-k2-imersite-transition"
local EARLY = "recipe-prod-research_material_imersite-1"
local TAIL = "recipe-prod-research_material_imersite-4"
local HOLDER = "mir-k2-imersite-staged-state-1"
local CARRIER = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"
local loaded, reported, pending = nil, false, false

local function fail(message) error("[mir5-k2-imersite-published] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function powder_bonus(force)
  local recipe = force.recipes[POWDER]
  if recipe == nil then fail("Imersite powder recipe is absent") end
  return recipe.productivity_bonus
end
local function holder(force, name, first, label)
  local value = technology(force, name)
  if value.level ~= first and name == HOLDER then fail(label .. " early holder level differs") end
  if name == CARRIER and value.level ~= 6 then fail(label .. " tail holder level differs") end
  if value.researched or value.enabled or value.visible_when_disabled
      or value.prototype.hidden ~= true or value.prototype.max_level ~= 4294967295 then
    fail(label .. " hidden holder state differs")
  end
  local effects = value.prototype.effects
  local effect = effects and effects[1]
  if #effects ~= 1 or effect.type ~= "change-recipe-productivity" or effect.recipe ~= POWDER
      or not close(effect.change, 0.02) then fail(label .. " hidden holder effect differs") end
  return value
end
local function assert_published(state, label)
  if type(state) ~= "table" or state.phase ~= "predecessor-ready" or state.actual_lab_completions ~= 5
      or state.source_mir ~= "4.6.21000" then fail(label .. " predecessor witness is absent") end
  local force = game.forces.player
  local early = technology(force, EARLY)
  if early.level ~= 3 or not early.researched or early.prototype.max_level ~= 3 then
    fail(label .. " finite early state differs")
  end
  if force.technologies[TAIL] ~= nil then fail(label .. " published bounded continuation was not removed") end
  local staged = holder(force, HOLDER, 1, label .. " staged")
  if staged.saved_progress ~= 0 then fail(label .. " staged holder gained progress") end
  local tail = holder(force, CARRIER, 4, label .. " continuation")
  if not close(tail.saved_progress, 0.42) or not close(powder_bonus(force), 0.10) then
    fail(label .. " published carrier bonus or partial progress differs")
  end
  if force.current_research ~= nil or #force.research_queue ~= 0 then fail(label .. " carrier retained an unexpected queue") end
  return {carrier_level=tail.level, carrier_progress=tail.saved_progress, bonus=powder_bonus(force)}
end
local function marker(stage, state)
  local value = holder(game.forces.player, CARRIER, 4, "published marker")
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=state.source_mir, published_mir=state.published_mir,
      source_actual_lab_completions=state.actual_lab_completions, hidden_tail_level=value.level,
      hidden_tail_saved_progress=value.saved_progress, powder_productivity=powder_bonus(game.forces.player),
      public_continuation_withheld=true, on_load_read_only=stage == "reload"},
  }))
end

script.on_configuration_changed(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["Krastorio2-spaced-out"] == nil
      or script.active_mods["more-infinite-research"] ~= "4.7.21002" or script.active_mods[FIXTURE] ~= "0.2.0" then
    fail("published stage requires K2SO, MIR 4.7.21002, and fixture 0.2.0")
  end
  if settings.startup["ips-max-level-research_material_imersite"].value ~= 3 then
    fail("published stage requires the exact cap that withholds continuation")
  end
  local state = storage[KEY]
  local snapshot = assert_published(state, "published initial")
  state.phase, state.published, state.published_mir = "published-ready", snapshot,
    script.active_mods["more-infinite-research"]
  pending = true
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "published-ready" and type(state.published) == "table"
    and {level=state.published.carrier_level, progress=state.published.carrier_progress, bonus=state.published.bonus} or nil
  reported, pending = false, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("published fixture state is absent") end
  if pending then
    local current = assert_published(state, "published initial tick")
    state.published = current
    marker("initial", state)
    game.server_save(SAVE)
    pending = false
    return
  end
  if loaded and not reported then
    local current = assert_published(state, "published cold reload")
    if current.carrier_level ~= loaded.level or not close(current.carrier_progress, loaded.progress)
        or not close(current.bonus, loaded.bonus) then fail("published cold reload changed the carrier witness") end
    marker("reload", state)
    reported = true
  end
end)

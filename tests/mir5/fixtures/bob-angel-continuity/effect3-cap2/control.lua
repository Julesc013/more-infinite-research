-- Saved-boundary observer for the F200 Bob/Angel useful-cap transition.
-- It observes native data/runtime work already performed by MIR; it never
-- edits a technology level, effect, queue, or foreign enabled state.
local KEY = "mir5_bob_angel_continuity"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-continuity-effect3-cap2"
local PROBE = "mir5-ba-continuity-queue-probe"
local UINT32_MAX = 4294967295
local TAIL_NEXT_LEVEL = 151
local EFFECT = 0.03
local BONUS = 4.5
local loaded, reload_logged = nil, false
local FAMILIES = {
  {early="recipe-prod-research_material_aluminium-1", tail="recipe-prod-research_material_aluminium-4", recipes={"angels-plate-aluminium", "angels-plate-aluminium-2"}},
  {early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}},
  {early="recipe-prod-research_material_gold-1", tail="recipe-prod-research_material_gold-4", recipes={"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"}},
  {early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"angels-plate-tin", "angels-plate-tin-2"}},
  {early="recipe-prod-research_material_titanium-1", tail="recipe-prod-research_material_titanium-4", recipes={"angels-plate-titanium", "angels-plate-titanium-2"}},
}

local function fail(message) error("[mir5-bob-angel-continuity-0.3.0] " .. message) end
local function close(left, right) return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001 end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value then fail("named technology is absent: " .. tostring(name)) end
  return value
end
local function check_closure()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "5.0.20000"
      or script.active_mods["mir-fixture-mir5-bob-angel-continuity"] ~= "0.3.0"
      or script.active_mods["space-age"] ~= nil or script.active_mods.bobtech ~= nil then
    fail("unexpected F200 Bob/Angel cap closure")
  end
end
local function check_settings()
  for _, family in ipairs(FAMILIES) do
    local key = family.early:match("recipe%-prod%-(research_material_.+)%-1")
    local effect_setting = settings.startup["ips-effect-per-level-" .. key]
    local cap_setting = settings.startup["ips-max-level-" .. key]
    if not effect_setting or effect_setting.value ~= 3 or not cap_setting or cap_setting.value ~= 2 then
      fail("fixture startup settings differ for " .. key)
    end
  end
  local imported = settings.startup["mir-settings-profile-import"]
  if not imported or imported.value ~= "" then fail("fixture requires a blank normal profile import") end
end
local function check_bonus(force, expected, label)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not close(recipe.productivity_bonus, expected) then fail(label .. " recipe effect changed for " .. name) end
    end
  end
end
local function check_rows(force, player, label)
  for _, family in ipairs(FAMILIES) do
    local early, tail = technology(force, family.early), technology(force, family.tail)
    local first = early.prototype.effects and early.prototype.effects[1]
    local last = tail.prototype.effects and tail.prototype.effects[1]
    if early.prototype.max_level ~= 3 or tail.prototype.max_level ~= UINT32_MAX
        or not first or not last or first.type ~= "change-recipe-productivity" or last.type ~= "change-recipe-productivity"
        or not close(first.change, EFFECT) or not close(last.change, EFFECT) then
      fail(label .. " current material prototype differs")
    end
    if early.level ~= 3 or early.researched ~= true or tail.level ~= TAIL_NEXT_LEVEL or tail.researched ~= false then
      fail(label .. " earned finite boundary changed")
    end
    if player then
      if early.enabled ~= false or early.visible_when_disabled ~= true
          or tail.enabled ~= false or tail.visible_when_disabled ~= true then
        fail(label .. " owned cap visibility differs")
      end
    else
      if early.enabled ~= false or tail.enabled ~= false
          or early.visible_when_disabled ~= true or tail.visible_when_disabled ~= true then
        fail(label .. " foreign disabled presentation differs")
      end
    end
  end
end
local function check_foreign(state)
  local force = game.forces[state.foreign_index]
  if not force or force.valid == false then fail("foreign continuity force is absent") end
  check_rows(force, false, "foreign")
  check_bonus(force, BONUS, "foreign")
  local queue = force.research_queue or {}
  if #queue ~= 1 or queue[1].name ~= PROBE or not force.current_research or force.current_research.name ~= PROBE
      or not close(force.research_progress, 0.42) then
    fail("foreign queue/progress changed")
  end
end
local function observe(state)
  check_closure(); check_settings()
  if type(state) ~= "table" or (state.phase ~= "mir5-default-transitioned" and state.phase ~= "effect3-cap2-await-save" and state.phase ~= "effect3-cap2-saved") or state.source_mir ~= "4.7.20002" then
    fail("required predecessor continuity witness is absent: phase=" .. tostring(state and state.phase) .. " source=" .. tostring(state and state.source_mir))
  end
  check_rows(game.forces.player, true, "player")
  check_bonus(game.forces.player, BONUS, "player")
  check_foreign(state)
end
local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed",
    witnesses={effect_percent=3, useful_level_headroom=100, user_cap=2, effective_cap=2,
      saved_finite_tail_level=150, preserved_infinite_next_level=TAIL_NEXT_LEVEL, native_recipe_bonus=BONUS,
      player_owned_visibility=true, foreign_disabled_effect_and_queue_preserved=true,
      on_load_read_only=stage == "reload", qualification="native-runner-readback-required"},
  }))
end
script.on_init(function() fail("saved-boundary fixture must start from its predecessor save") end)
script.on_configuration_changed(function()
  local state = storage[KEY]
  observe(state)
  state.phase = "effect3-cap2-await-save"
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "effect3-cap2-saved"
  reload_logged = false
end)
script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("continuity state is absent") end
  if state.phase == "effect3-cap2-await-save" then
    observe(state)
    state.phase = "effect3-cap2-saved"
    marker("initial", state)
    game.server_save(SAVE)
  elseif state.phase == "effect3-cap2-saved" and loaded and not reload_logged then
    observe(state)
    marker("reload", state)
    reload_logged = true
  end
end)

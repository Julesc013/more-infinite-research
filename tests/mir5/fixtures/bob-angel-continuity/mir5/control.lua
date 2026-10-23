-- MIR5 side of the F200 Bob/Angel continuity fixture. Fresh creation proves
-- twenty real lab completions (three finite early levels plus one tail level
-- for each admitted family). Published-save transition separately verifies a
-- native finite-150 boundary; it never calls that boundary lab work.
local KEY = "mir5_bob_angel_continuity"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-continuity-mir5"
local PROBE = "mir5-ba-continuity-queue-probe"
local UINT32_MAX = 4294967295
-- A finite level 150 becomes an infinite next level 151: it retains all 150
-- earned effects instead of treating level 150 as an unearned next level.
local PRESERVED_TAIL_NEXT_LEVEL = 151
local DEFAULT_EFFECT = 0.02
local INITIAL_PACKS = 64
local DEADLINE_TICKS = 36000
local loaded, reload_logged = nil, false

local REQUIRED = {
  base="2.0.77", angelsbioprocessing="2.0.3", angelsbioprocessinggraphics="2.0.0",
  angelspetrochem="2.0.3", angelspetrochemgraphics="2.0.1", angelsrefining="2.0.4",
  angelsrefininggraphics="2.0.0", angelssmelting="2.0.5", angelssmeltinggraphics="2.0.0",
  bobelectronics="2.1.1", boblibrary="2.1.0", bobores="2.1.2", bobplates="2.1.1", bobrevamp="2.1.1",
}
local FAMILIES = {
  {key="research_material_aluminium", early="recipe-prod-research_material_aluminium-1", tail="recipe-prod-research_material_aluminium-4", recipes={"angels-plate-aluminium", "angels-plate-aluminium-2"}, science={"automation-science-pack", "logistic-science-pack", "utility-science-pack"}},
  {key="research_material_copper_tungsten", early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}, science={"automation-science-pack", "logistic-science-pack", "utility-science-pack"}},
  {key="research_material_gold", early="recipe-prod-research_material_gold-1", tail="recipe-prod-research_material_gold-4", recipes={"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"}, science={"automation-science-pack", "logistic-science-pack", "utility-science-pack"}},
  {key="research_material_tin", early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"angels-plate-tin", "angels-plate-tin-2"}, science={"automation-science-pack", "utility-science-pack"}},
  {key="research_material_titanium", early="recipe-prod-research_material_titanium-1", tail="recipe-prod-research_material_titanium-4", recipes={"angels-plate-titanium", "angels-plate-titanium-2"}, science={"automation-science-pack", "logistic-science-pack", "utility-science-pack"}},
}
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "utility-science-pack"}
local CONSUMPTION = { ["automation-science-pack"]=20, ["logistic-science-pack"]=16, ["utility-science-pack"]=5 }

local function fail(message) error("[mir5-bob-angel-continuity] " .. message) end
local function close(left, right) return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001 end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value then fail("named technology is absent: " .. tostring(name)) end
  return value
end
local function status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible_when_disabled=value.visible_when_disabled, max_level=value.prototype.max_level}
end
local function same(left, right)
  return type(left) == "table" and left.level == right.level and left.researched == right.researched
    and left.enabled == right.enabled and left.visible_when_disabled == right.visible_when_disabled
    and left.max_level == right.max_level
end
local function queue_names(force)
  local out = {}
  for index, value in ipairs(force.research_queue or {}) do out[index] = value.name end
  return out
end
local function progress(force)
  return type(force.research_progress) == "number" and force.research_progress or 0
end

local function scalar(value)
  if value == nil then return "nil" end
  return tostring(value)
end

local function row_diagnostic(label, value)
  if not value then return label .. "=absent" end
  return label .. "={level=" .. scalar(value.level)
    .. ",researched=" .. scalar(value.researched)
    .. ",enabled=" .. scalar(value.enabled)
    .. ",visible_when_disabled=" .. scalar(value.visible_when_disabled)
    .. ",max_level=" .. scalar(value.prototype and value.prototype.max_level) .. "}"
end

local function ownership_diagnostic(force, family)
  local caps = type(storage) == "table" and storage.mir_caps or nil
  local owned = type(caps) == "table" and caps.owned_disabled or nil
  local rows = type(owned) == "table" and owned[force.index] or nil
  local function row(name)
    local value = type(rows) == "table" and rows[name] or nil
    if value == nil then return name .. "=none" end
    if type(value) ~= "table" then return name .. "=" .. type(value) end
    return name .. "={disabled=" .. scalar(value.disabled)
      .. ",visible_when_disabled=" .. scalar(value.visible_when_disabled) .. "}"
  end
  return "ownership={" .. row(family.early) .. ";" .. row(family.tail) .. "}"
end

local function foreign_upgrade_diagnostic(force, family)
  local early, tail = technology(force, family.early), technology(force, family.tail)
  return "actual=" .. row_diagnostic("early", early) .. ";" .. row_diagnostic("tail", tail)
    .. ";" .. ownership_diagnostic(force, family)
end

local function assert_external_seed_witness(state)
  local before, after = state and state.foreign_pre_external, state and state.foreign
  if type(before) ~= "table" or type(after) ~= "table"
      or type(before.technologies) ~= "table" or type(after.technologies) ~= "table"
      or type(before.bonuses) ~= "table" or type(after.bonuses) ~= "table"
      or type(before.queue) ~= "table" or type(after.queue) ~= "table" then
    fail("published external disable witness is absent")
  end
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs({family.early, family.tail}) do
      local old, current = before.technologies[name], after.technologies[name]
      if not old or not current or old.level ~= current.level or old.researched ~= current.researched
          or old.max_level ~= current.max_level or old.enabled ~= true
          or old.visible_when_disabled ~= false or current.enabled ~= false
          or current.visible_when_disabled ~= false then
        fail("published external disable witness differs for " .. name)
      end
    end
  end
  for name, value in pairs(before.bonuses) do
    if not close(after.bonuses[name], value) then
      fail("published external disable witness changed recipe effect for " .. name)
    end
  end
  if #before.queue ~= #after.queue or before.current ~= after.current
      or not close(before.progress, after.progress) then
    fail("published external disable witness changed queue or progress")
  end
  for index, name in ipairs(before.queue) do
    if after.queue[index] ~= name then fail("published external disable witness changed queue identity") end
  end
end

local function check_closure()
  for name, version in pairs(REQUIRED) do
    if script.active_mods[name] ~= version then fail("unexpected Bob/Angel closure member: " .. name) end
  end
  if script.active_mods["more-infinite-research"] ~= "5.0.20000"
      or script.active_mods["mir-fixture-mir5-bob-angel-continuity"] ~= "0.2.0"
      or script.active_mods["space-age"] ~= nil or script.active_mods.bobtech ~= nil then
    fail("unexpected F200 Bob/Angel MIR5 closure")
  end
end

local function assert_current_prototype(force, family)
  local early, tail = technology(force, family.early), technology(force, family.tail)
  if early.prototype.max_level ~= 3 or tail.prototype.max_level ~= UINT32_MAX then
    fail("MIR5 material progression boundary differs")
  end
  for _, value in ipairs({early, tail}) do
    local effect = value.prototype.effects and value.prototype.effects[1]
    if not effect or effect.type ~= "change-recipe-productivity" or not close(effect.change, DEFAULT_EFFECT) then
      fail("MIR5 default material effect differs for " .. value.name)
    end
  end
  return early, tail
end

local function assert_fixture_acceleration(force)
  for _, family in ipairs(FAMILIES) do
    for _, value in ipairs({assert_current_prototype(force, family)}) do
      -- Factorio exposes native research energy in ticks: one authored second
      -- is 60 here, as independently witnessed by the K2 F200 lab fixture.
      if value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
        fail("fixture did not produce one-unit, one-second research for " .. value.name)
      end
    end
  end
end

local function recipe_bonuses(force, expected)
  local out = {}
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not close(recipe.productivity_bonus, expected) then
        fail("native recipe productivity differs for " .. name)
      end
      out[name] = recipe.productivity_bonus
    end
  end
  return out
end

local function material_snapshot(force, expected_bonus)
  local technologies = {}
  for _, family in ipairs(FAMILIES) do
    technologies[family.early] = status(technology(force, family.early))
    technologies[family.tail] = status(technology(force, family.tail))
  end
  return {technologies=technologies, bonuses=recipe_bonuses(force, expected_bonus),
    queue=queue_names(force), current=force.current_research and force.current_research.name or false,
    progress=progress(force)}
end

local function assert_snapshot(force, expected, expected_bonus, label)
  for name, saved in pairs(expected.technologies) do
    if not same(status(technology(force, name)), saved) then fail(label .. " state changed for " .. name) end
  end
  local actual = recipe_bonuses(force, expected_bonus)
  for name, value in pairs(expected.bonuses) do
    if not close(actual[name], value) then fail(label .. " effect changed for " .. name) end
  end
  local queue = queue_names(force)
  if #queue ~= #expected.queue or (force.current_research and force.current_research.name or false) ~= expected.current
      or not close(progress(force), expected.progress) then
    fail(label .. " queue or progress changed")
  end
  for index, name in ipairs(expected.queue) do if queue[index] ~= name then fail(label .. " queue identity changed") end end
end

local function seed_external_prerequisites(force)
  local selected = {}
  for _, family in ipairs(FAMILIES) do selected[family.early], selected[family.tail] = true, true end
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs({family.early, family.tail}) do
      for _, prerequisite in pairs(technology(force, name).prerequisites) do
        if not selected[prerequisite.name] then prerequisite.research_recursive() end
      end
    end
  end
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_current_prototype(force, family)
    if early.level ~= 1 or early.researched or tail.level ~= 4 or tail.researched then
      fail("external prerequisite setup completed a selected material row")
    end
  end
end

local function seed_foreign(force)
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_current_prototype(force, family)
    early.level, early.researched = 3, true
    tail.level, tail.researched = 5, false
    early.enabled, early.visible_when_disabled = false, false
    tail.enabled, tail.visible_when_disabled = false, false
  end
  force.reset_technology_effects()
  for _, prerequisite in pairs(technology(force, PROBE).prerequisites) do prerequisite.research_recursive() end
  if force.add_research(PROBE) ~= true then fail("could not queue foreign probe research") end
  force.research_progress = 0.42
  local snapshot = material_snapshot(force, 0.08)
  if snapshot.current ~= PROBE or #snapshot.queue ~= 1 or snapshot.queue[1] ~= PROBE
      or not close(snapshot.progress, 0.42) then fail("foreign queue seed differs") end
  return snapshot
end

local function plan()
  local out = {}
  for _, family in ipairs(FAMILIES) do
    for _ = 1, 3 do out[#out + 1] = family.early end
    out[#out + 1] = family.tail
  end
  return out
end

local function assert_fresh_complete(state)
  local force = game.forces.player
  if state.completed ~= #state.plan or state.events ~= #state.plan or state.queue_count ~= #state.plan
      or force.current_research ~= nil or #force.research_queue ~= 0 then
    fail("real material lab queue did not complete every selected level exactly once")
  end
  for _, family in ipairs(FAMILIES) do
    local early, tail = technology(force, family.early), technology(force, family.tail)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= 5 or tail.researched ~= false then
      fail("real lab did not retain the early-three/tail-four boundary for " .. family.key)
    end
  end
  recipe_bonuses(force, 0.08)
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real material lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.get_item_count(science) ~= INITIAL_PACKS - CONSUMPTION[science] then
      fail("real lab science consumption differs for " .. science)
    end
  end
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.valid == false then fail("foreign material force is absent") end
  assert_snapshot(foreign, state.foreign, 0.08, "foreign")
end

local function assert_upgrade_transition(state)
  if state.source_mir ~= "4.7.20002" or state.phase ~= "published-boundary-saved" then
    fail("published 4.7.2 boundary witness is absent")
  end
  assert_external_seed_witness(state)
  local player = game.forces.player
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_current_prototype(player, family)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= PRESERVED_TAIL_NEXT_LEVEL or tail.researched ~= false
        or early.enabled ~= true or early.visible_when_disabled ~= false
        or tail.enabled ~= false or tail.visible_when_disabled ~= true then
      fail("MIR5 did not preserve the published finite boundary for " .. family.key)
    end
  end
  recipe_bonuses(player, 3)
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.valid == false then fail("published foreign force is absent") end
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_current_prototype(foreign, family)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= PRESERVED_TAIL_NEXT_LEVEL or tail.researched ~= false
        or early.enabled ~= false or tail.enabled ~= false or tail.visible_when_disabled ~= true then
      fail("MIR5 changed foreign finite boundary state for " .. family.key .. "; "
        .. foreign_upgrade_diagnostic(foreign, family))
    end
  end
  -- `data-final-fixes.lua` has validated the default generated rows already;
  -- only its disposable unit/count mutation is visible here.
  recipe_bonuses(foreign, 3)
  local queue = queue_names(foreign)
  if #queue ~= 1 or queue[1] ~= PROBE or (foreign.current_research and foreign.current_research.name) ~= PROBE
      or not close(foreign.research_progress, 0.42) then
    fail("MIR5 changed the foreign queue boundary")
  end
end

local function marker(stage, state)
  local witness = {
    source_mir=state.source_mir, fixture_version=script.active_mods["mir-fixture-mir5-bob-angel-continuity"],
    default_rows_preflighted_before_mutation=true, on_load_read_only=stage == "reload",
    qualification="native-runner-readback-required",
  }
  if state.phase == "fresh-lab-complete" then
    witness.real_lab_completed_levels=state.completed
    witness.early_levels_completed_by_lab=15
    witness.tail_levels_completed_by_lab=5
    witness.seeded_boundary_levels=false
    witness.science_consumed=CONSUMPTION
    witness.native_recipe_bonus=0.08
    witness.foreign_disabled_and_queued_preserved=true
  else
    witness.real_lab_completed_levels=0
    witness.seeded_boundary_levels=true
    witness.seeded_finite_tail_level=150
    witness.preserved_infinite_next_level=PRESERVED_TAIL_NEXT_LEVEL
    witness.no_fabricated_150_completion_claim=true
    witness.native_recipe_bonus=3
    witness.foreign_disabled_and_queued_preserved=true
    witness.foreign_external_disable_transition=true
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({case=CASE, stage=stage, status="passed", witnesses=witness}))
end

script.on_init(function()
  check_closure()
  if storage[KEY] ~= nil then fail("fresh lab fixture found existing continuity state") end
  game.speed = 16
  local force = game.forces.player
  force.enable_all_prototypes()
  seed_external_prerequisites(force)
  assert_fixture_acceleration(force)
  local baseline = recipe_bonuses(force, 0)

  local foreign = game.create_force("mir5-bob-angel-continuity-foreign")
  foreign.enable_all_prototypes()
  local foreign_snapshot = seed_foreign(foreign)

  local surface = game.surfaces[1]
  local lab = surface.create_entity{name="lab", position=force.get_spawn_position(surface), force=force}
  if not lab or lab.valid == false then fail("could not create a real Bob/Angel lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real Bob/Angel lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.insert{name=science, count=INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("real Bob/Angel lab did not accept " .. science)
    end
  end
  lab.energy = 100000000

  local sequence = plan()
  if force.add_research(technology(force, sequence[1])) ~= true then fail("could not start real material research") end
  if #force.research_queue ~= 1 or not force.current_research or force.current_research.name ~= sequence[1] then
    fail("native material queue did not accept the first research")
  end
  storage[KEY] = {phase="fresh-lab-running", source_mir=script.active_mods["more-infinite-research"],
    plan=sequence, completed=0, events=0, queue_count=1, deadline=game.tick + DEADLINE_TICKS,
    lab=lab, baseline=baseline, foreign_index=foreign.index, foreign=foreign_snapshot}
end)

script.on_configuration_changed(function()
  check_closure()
  local state = storage[KEY]
  assert_upgrade_transition(state)
  state.upgrade = material_snapshot(game.forces.player, 3)
  state.foreign_upgrade = material_snapshot(game.forces[state.foreign_index], 3)
  state.phase = "mir5-default-transitioned"
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "fresh-lab-complete" or state.phase == "mir5-default-transitioned") then
    loaded = {phase=state.phase, completed=state.completed, events=state.events, queue_count=state.queue_count}
  else
    loaded = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "fresh-lab-running" or not event.research or event.research.force ~= game.forces.player then return end
  local expected = state.plan[state.completed + 1]
  if expected == nil or event.research.name ~= expected then fail("real lab completed an unexpected material row") end
  state.completed, state.events = state.completed + 1, state.events + 1
  if state.completed > #state.plan then fail("real lab completed a duplicate material row") end
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("continuity state is absent") end
  if state.phase == "fresh-lab-running" then
    if game.tick > state.deadline then fail("real Bob/Angel material lab did not complete before deadline") end
    if not state.lab or state.lab.valid == false then fail("real Bob/Angel lab disappeared") end
    state.lab.energy = 100000000
    if state.completed == #state.plan then
      assert_fresh_complete(state)
      state.phase = "fresh-lab-complete"
      marker("initial", state)
      game.server_save(SAVE)
    elseif game.forces.player.current_research == nil then
      -- Native queue admission drops a tail whose finite prerequisite has
      -- not completed yet. Advance the fixed fixture sequence only after
      -- the preceding actual lab completion; never grant that prerequisite.
      local force, name = game.forces.player, state.plan[state.completed + 1]
      if #force.research_queue ~= 0 or force.add_research(technology(force, name)) ~= true
        or not force.current_research or force.current_research.name ~= name or #force.research_queue ~= 1 then
        fail("native material queue refused the next lab research")
      end
      state.queue_count = state.queue_count + 1
    end
    return
  end
  if state.phase == "mir5-default-transitioned" then
    assert_snapshot(game.forces.player, state.upgrade, 3, "player upgrade")
    if not state.default_saved then
      state.default_saved = true
      marker("initial", state)
      game.server_save(SAVE)
      return
    end
  elseif state.phase == "fresh-lab-complete" then assert_fresh_complete(state)
  else fail("unexpected continuity phase") end
  if loaded and not reload_logged then
    if loaded.phase ~= state.phase or loaded.completed ~= state.completed or loaded.events ~= state.events
        or loaded.queue_count ~= state.queue_count then fail("on_load changed durable continuity witness") end
    marker("reload", state)
    reload_logged = true
  end
end)

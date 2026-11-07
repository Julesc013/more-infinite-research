-- Retained paid-state witness; no research setters, aggregate repair or MIR storage writes.
local c = require("contract")
local KEY = "mir_private_holder_cost_transition"
local cold = false
local ids = {
  "mir-native-credit-research_electric_shooting_speed-electric-positive",
  "zz-mir-native-credit-research_electric_shooting_speed-electric-negative",
  "mir-native-credit-research_electric_shooting_speed-tesla-positive",
  "zz-mir-native-credit-research_electric_shooting_speed-tesla-negative",
  "mir-legacy-module-credit-speed-module", "mir-legacy-module-credit-productivity-module",
  "mir-legacy-module-credit-efficiency-module", "mir-legacy-cannon-credit-rocket-shooting-speed"
}

local function technology(force, name)
  local value = force.technologies[name]
  assert(value and value.valid, "missing " .. name)
  return value
end

local function status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, saved=value.saved_progress}
end

local function snapshot(force)
  local out = {name=force.name,index=force.index,main=status(technology(force,c.main)),
    owner=status(technology(force,c.owner)),detached=status(technology(force,c.detached)),
    current=force.current_research and force.current_research.name or false,
    progress=force.research_progress,queue={},bonuses={},mining=force.mining_drill_productivity_bonus,
    lab=force.laboratory_speed_modifier}
  for i, value in ipairs(force.research_queue or {}) do out.queue[i] = value.name end
  for _, category in ipairs(c.categories) do out.bonuses[category] = force.get_gun_speed_modifier(category) end
  return out
end

local function audit(expected_cost, exemption)
  c.same(c.mods(), script.active_mods, "exact selected closure")
  c.same(c.old_fixture(), storage[c.old_key], "earlier first-entry fixture preserved")
  local old = assert(storage[c.key], "retained real-lab witness absent")
  assert(old.phase == "lab-ready" and old.completions == 1 and old.completion.by_script == false,
    "actual earlier native research completion required")
  assert(#old.labs == 4, "retained lab collection differs")
  for _, lab in ipairs(old.labs) do
    assert(lab.valid and lab.name == c.lab and lab.disabled_by_script and lab.energy == 0,
      "original labs must remain stopped")
  end
  local actual, costs = {}, {}
  for i, name in ipairs(c.forces) do
    local force = assert(game.forces[name])
    actual[i] = snapshot(force)
    local holders = {}
    for category, directions in pairs(c.holders) do
      holders[category] = {}
      for direction, id in pairs(directions) do
        local t = technology(force,id)
        assert(t.prototype.hidden and not t.enabled and not t.visible_when_disabled, "private flags")
        assert(prototypes.get_history("technology",id).created == c.mir, "private owner")
        holders[category][direction] = t.level - 1 + (t.researched and 1 or 0)
      end
    end
    c.same(c.expected_holders(i < 3 and i + 1 or 0), holders, "paid Tesla rights remain category-specific")
    costs[i] = {}
    for _, id in ipairs(ids) do
      local t = technology(force,id)
      assert(t.research_unit_count == expected_cost, "wrong internal unit cost: " .. id)
      assert(t.prototype.ignore_tech_cost_multiplier == exemption, "wrong internal exemption: " .. id)
      costs[i][id] = {count=t.research_unit_count,level=t.level,researched=t.researched,
        ignore_tech_cost_multiplier=t.prototype.ignore_tech_cost_multiplier}
    end
    local public = technology(force,c.main)
    assert(public.prototype.ignore_tech_cost_multiplier == false, "public research escaped map difficulty")
    assert(public.research_unit_count_formula == "60*1.5^(L-1)", "authored public work changed")
    costs[i].public = {count=public.research_unit_count,formula=public.research_unit_count_formula}
  end
  c.same(c.post(old.post[1].progress,old.work.next_count), actual, "independent retained paid-state expectation")
  c.same(old.post, actual, "original completed/partial/queue/foreign state preserved")
  return {states=actual,costs=costs,multiplier=game.difficulty_settings.technology_price_multiplier,
    prior_real_lab_completions=old.completions,new_real_lab_completions=0}
end

local function report(stage, observation)
  local result = {stage=stage,tick=game.tick,fixture_version=c.version,mir_version=script.active_mods[c.mir],
    observation=observation,scope="paid electric/Tesla/foreign state, map cost and protected successor continuity"}
  local text = helpers.table_to_json(result)
  log("[MIR_PRIVATE_HOLDER_COST] " .. text)
  helpers.write_file("private-holder-cost-transition-" .. stage .. ".json",text,false)
end

script.on_init(function() error("protected actual paid-research source save required") end)
script.on_load(function() cold = true end)
script.on_configuration_changed(function(event)
  assert(not event.mod_startup_settings_changed, "startup settings changed")
  local change = assert(event.mod_changes[c.fixture], "fixture phase change absent")
  assert(change.new_version == c.version, "wrong fixture destination")
  if c.version == "0.6.0" then
    assert(change.old_version == "0.2.0" and storage[KEY] == nil, "wrong protected source phase")
    local mir = assert(event.mod_changes[c.mir], "published8 source adoption absent")
    assert(mir.old_version == "5.0.21004" and mir.new_version == "5.0.21008", "wrong original MIR adoption")
    assert(game.difficulty_settings.technology_price_multiplier == 1, "original map difficulty changed")
    report("source-entry",audit(1,false))
    storage[KEY] = {phase="source-pending",entry_tick=game.tick}
  else
    assert(change.old_version == "0.6.0", "successor must consume published8 source")
    local state = assert(storage[KEY])
    assert(state.phase == "source-ready" and state.multiplier == 4, "protected source not ready")
    local observation = audit(1,true)
    assert(observation.multiplier == 4, "saved map difficulty lost")
    c.same(state.expected, observation.states, "source-to-successor paid rights")
    report("successor-entry",observation)
    state.phase,state.entry_tick = "successor-pending",game.tick
  end
  cold = false
end)

script.on_event(defines.events.on_tick,function()
  local state = assert(storage[KEY])
  if cold then
    local source = c.version == "0.6.0"
    assert(state.phase == (source and "source-ready" or "successor-ready"), "cold incomplete phase")
    local observation = audit(source and 4 or 1,not source)
    assert(observation.multiplier == 4, "cold map difficulty lost")
    c.same(state.expected,observation.states,"cold paid state")
    report("cold",observation)
    cold = false
    return
  end
  if (state.phase == "source-pending" or state.phase == "successor-pending")
      and game.tick <= state.entry_tick then return end
  if state.phase == "source-pending" and game.tick > state.entry_tick then
    local before = audit(1,false)
    game.difficulty_settings.technology_price_multiplier = 4
    local observation = audit(4,false)
    c.same(before.states,observation.states,"changing difficulty cannot change earned state")
    state.phase,state.expected,state.multiplier = "source-ready",c.copy(observation.states),4
    report("source-ready",observation)
    game.server_save("private-holder-cost-published508-ready")
  elseif state.phase == "successor-pending" and game.tick > state.entry_tick then
    local observation = audit(1,true)
    assert(observation.multiplier == 4, "successor changed map difficulty")
    c.same(state.expected,observation.states,"next-tick paid state")
    state.phase = "successor-ready"
    report("successor-ready",observation)
    game.server_save("private-holder-cost-successor-ready")
  else
    assert(state.phase == "source-ready" or state.phase == "successor-ready", "unexpected phase")
  end
end)

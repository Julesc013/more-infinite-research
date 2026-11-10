-- One target-record catalogue-state upgrade scenario. Lists are recovered
-- fixture data; this control never discovers technology families.
local KEY = "mir5_full_catalogue_upgrade"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-full-catalogue-upgrade"
local SOURCE = script.active_mods[FIXTURE] == "0.1.0" or script.active_mods[FIXTURE] == "0.2.1"
local MIR = script.active_mods["more-infinite-research"]
local GEAR = "recipe-prod-research_gears-1"
local PROBE = "braking-force-1"
local DEADLINE = 36000
local UINT32_MAX = 4294967295
local loaded, reload_logged = nil, false
local PLAN = require("__mir-fixture-mir5-full-catalogue-upgrade__/catalogue")
local TARGET = PLAN.target
local CROSS_FROM_F200 = script.active_mods[FIXTURE] == "0.3.0"
local WORKER_OWNER = PLAN.worker_native_owner
local WORKER = {"worker-robots-storage-4", "mir-worker-storage-default-4",
  "mir-worker-storage-head-4", "mir-worker-storage-preservation-4"}
local KNOWN473_ORIGIN = {kind="external_literal_expectations",
  commit="67b271d2c0a1da53f9c0fe9bbf82689fb2e37916",member="source473-r02/published-state.json",
  sha256="72B02BA2A2BDD0D974A6E3C2E9124FAE24CCD21233295D128F44EECFA608B428",
  source_save_sha256="1F7DD178D9CAA6CDD47F82C3B55F19D846D70E36A995F70E858E36A0918A98AF"}

local function fail(message) error("[mir5-full-catalogue-upgrade] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end
local function literal_copy(value)
  if type(value)~="table"then return value end
  local out={};for key,item in pairs(value)do out[key]=literal_copy(item)end;return out
end
local function literal_equal(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~="table"then return a==b end
  for key,item in pairs(a)do if not literal_equal(item,b[key])then return false end end
  for key in pairs(b)do if a[key]==nil then return false end end
  return true
end
local function profile()
  local space = script.active_mods["space-age"] ~= nil
  if space then
    for _, name in ipairs(TARGET.space_age_closure) do
      if script.active_mods[name] ~= TARGET.version then fail("Space Age closure differs") end
    end
    return PLAN.space_age, "space-age"
  end
  for _, name in ipairs(TARGET.space_age_closure) do
    if script.active_mods[name] ~= nil then fail("Base closure carries Space Age companions") end
  end
  return PLAN.base, "base"
end
local function check_closure()
  local expected_mir = SOURCE and TARGET.published_mir or TARGET.mir5
  local expected_fixture = SOURCE and (TARGET.source_fixture_version or "0.1.0") or (CROSS_FROM_F200 and "0.3.0" or "0.2.0")
  if WORKER_OWNER ~= nil then
    if WORKER_OWNER ~= "published473-idle-full4" or SOURCE or TARGET.id ~= "f200"
      or TARGET.version ~= "2.0.77" or TARGET.published_mir ~= "4.7.20003"
      or TARGET.mir5 ~= "5.0.20012" or script.active_mods["space-age"] ~= nil then fail("worker owner expectation differs") end
    expected_fixture = "0.4.0"
  end
  if script.active_mods.base ~= TARGET.version or MIR ~= expected_mir
      or script.active_mods[FIXTURE] ~= expected_fixture then
    fail("fixture stage closure differs")
  end
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function copy_table(value)
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    queue=queue, progress=force.research_progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue
      or (WORKER_OWNER~=nil and actual.progress~=expected.progress or WORKER_OWNER==nil and not close(actual.progress,expected.progress)) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs") end
  end
  return actual
end
local function state_rows(plan)
  local out = {}
  for _, row in ipairs(plan.state) do out[#out + 1] = row.name end
  for _, name in ipairs(plan.native_owners) do out[#out + 1] = name end
  return out
end
local function seed_levels(force, plan, label)
  for _, name in ipairs(state_rows(plan)) do
    local value = technology(force, name)
    if value.prototype.max_level ~= UINT32_MAX then fail(label .. " maximum changed: " .. name) end
    -- This is an explicit saved-state seed.  The only real lab completions are
    -- the source and successor gear levels below.
    value.level = value.prototype.level + 1
    if value.researched then fail(label .. " seeded infinite row became researched: " .. name) end
  end
  for _, name in ipairs(plan.scripted) do
    -- Scripted runtime effects have their own qualification.  Only presence is
    -- checked here; no scripted row is level-seeded or claimed as a lab result.
    technology(force, name)
  end
  force.reset_technology_effects()
end
local function worker_owner_snapshot(force)
  local out={bonus=force.worker_robots_storage_bonus,rows={}}
  if game.difficulty_settings.technology_price_multiplier~=1 or out.bonus~=1 then fail("paid-idle worker native bonus/map price differs")end
  for index,name in ipairs(WORKER)do
    local t=technology(force,name);local p=t.prototype;local debit=index==3
    local next_level=index<=2 and 5 or 4
    if t.level~=next_level or t.researched~=debit or t.saved_progress~=0
      or type(t.enabled)~="boolean" or type(t.visible_when_disabled)~="boolean"
      or t.enabled~=(index==2) or t.visible_when_disabled~=(index==1)
      or p.hidden~=(index>=3) or p.level~=4 or p.max_level~=(debit and 4 or UINT32_MAX)
      or p.enabled~=(index<=2) or p.visible_when_disabled~=false or p.ignore_tech_cost_multiplier~=false
      or #p.effects~=1 or p.effects[1].type~="worker-robot-storage"
      or p.effects[1].modifier~=(debit and -1 or 1)then fail("paid-idle worker owner state differs: "..name)end
    if force.current_research and force.current_research.name==name then fail("paid-idle worker is current")end
    for _,queued in ipairs(force.research_queue or {})do if queued.name==name then fail("paid-idle worker is queued")end end
    local packs=debit and{"automation-science-pack"}or{"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"}
    if t.research_unit_count~=(debit and 1 or index<=2 and 1012 or 675)
      or p.research_unit_energy~=(debit and 60 or 3600) or #t.research_unit_ingredients~=#packs
      or not debit and p.research_unit_count_formula~="675*1.5^(L-4)"
      or debit and next(p.prerequisites)~=nil then fail("paid-idle worker cost differs")end
    for i,pack in ipairs(packs)do local row=t.research_unit_ingredients[i]
      if row.name~=pack or row.amount~=1 then fail("paid-idle worker science differs")end
    end
    out.rows[name]={level=t.level,researched=t.researched,enabled=t.enabled,visible=t.visible_when_disabled,
      saved=t.saved_progress,count=t.research_unit_count,first=p.level,maximum=p.max_level,hidden=p.hidden,
      effect=p.effects[1].modifier,energy=p.research_unit_energy,formula=p.research_unit_count_formula or false}
  end
  return out
end
local function worker_source_expectation(expected)
  local c=expected.technologies[WORKER[1]]
  if not c or c.level~=5 or c.researched~=false or c.enabled~=true or c.visible~=false
    or c.saved~=0 or c.maximum~=UINT32_MAX or expected.fields.worker_robots_storage_bonus~=1 then
    fail("known published473 paid-idle worker source differs")
  end
end
local function snapshot(force, plan, incoming)
  local out = {technologies={}, recipes={}, fields={}, guns={}}
  for _, name in ipairs(state_rows(plan)) do
    local value = technology(force, name)
    out.technologies[name] = {level=value.level, researched=value.researched, enabled=value.enabled,
      visible=value.visible_when_disabled, saved=value.saved_progress, maximum=value.prototype.max_level}
  end
  for _, recipe in ipairs(plan.recipes) do
    local value = force.recipes[recipe]
    if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then
      fail("recipe productivity fact is absent: " .. recipe)
    end
    out.recipes[recipe] = value.productivity_bonus
  end
  for _, field in ipairs(PLAN.force_fields) do
    local value = force[field]
    if type(value) ~= "number" then fail("native force effect field is absent: " .. field) end
    out.fields[field] = value
  end
  for _, category in ipairs(plan.guns) do
    local value = force.get_gun_speed_modifier(category)
    if type(value) ~= "number" then fail("native gun-speed fact is absent: " .. category) end
    out.guns[category] = value
  end
  if WORKER_OWNER ~= nil then
    if incoming then
      out.worker_incoming={bonus=force.worker_robots_storage_bonus,rows={},queue=queue_snapshot(force)}
      for _,name in ipairs(WORKER)do local t=technology(force,name);local p=t.prototype
        out.worker_incoming.rows[name]={level=t.level,researched=t.researched,enabled=t.enabled,
          visible=t.visible_when_disabled,saved=t.saved_progress,count=t.research_unit_count,
          first=p.level,maximum=p.max_level,hidden=p.hidden,effects=literal_copy(p.effects)}
      end
    else out.worker_owner=worker_owner_snapshot(force)end
  end
  return out
end
local function assert_same_snapshot(force, plan, expected, label)
  local actual = snapshot(force, plan)
  if WORKER_OWNER ~= nil then worker_source_expectation(expected)end
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    local head=WORKER_OWNER~=nil and name==WORKER[1]
    if now == nil or now.level ~= before.level or now.researched ~= before.researched
        or now.enabled ~= (not head and before.enabled) or now.visible ~= (head or before.visible) or now.maximum ~= before.maximum
        or (WORKER_OWNER~=nil and now.saved~=before.saved or WORKER_OWNER==nil and not close(now.saved,before.saved)) then fail(label .. " technology state changed: " .. name) end
  end
  for name, before in pairs(expected.recipes) do if not close(actual.recipes[name], before) then fail(label .. " recipe bonus changed: " .. name) end end
  for name, before in pairs(expected.fields) do if not close(actual.fields[name], before) then fail(label .. " native force effect changed: " .. name) end end
  for name, before in pairs(expected.guns) do if not close(actual.guns[name], before) then fail(label .. " native gun effect changed: " .. name) end end
  return actual
end
local function known473_expectations()
  local known=PLAN.worker_native_owner_source
  if type(known)~="table"or not literal_equal(known.origin,KNOWN473_ORIGIN)
    or type(known.frames)~="table"or type(known.queues)~="table"then fail("known473 literal source projection absent/mismatched")end
  local function exact_keys(actual,names,label)
    if type(actual)~="table"then fail(label.." is absent")end
    local want={};for _,name in ipairs(names)do want[name]=true;if actual[name]==nil then fail(label.." misses "..name)end end
    for name in pairs(actual)do if not want[name]then fail(label.." carries unexpected "..tostring(name))end end
  end
  local plan=PLAN.base;local names=state_rows(plan)
  if #names~=54 or #plan.recipes~=85 or #PLAN.force_fields~=15 or #plan.guns~=7 then fail("known473 full literal closure differs")end
  local force_names={"player","mir5-full-catalogue-upgrade-paused"}
  exact_keys(known.frames,force_names,"known473 frames");exact_keys(known.queues,force_names,"known473 queues")
  for _,name in ipairs(force_names)do
    local frame=known.frames[name];worker_source_expectation(frame)
    exact_keys(frame,{"technologies","recipes","fields","guns"},"known473 frame")
    exact_keys(frame.technologies,names,"known473 technologies");exact_keys(frame.recipes,plan.recipes,"known473 recipes")
    exact_keys(frame.fields,PLAN.force_fields,"known473 fields");exact_keys(frame.guns,plan.guns,"known473 guns")
    local queue=known.queues[name]
    if type(queue)~="table"or type(queue.queue)~="table"or type(queue.progress)~="number"
      or queue.progress<0 or queue.progress>=1 or type(queue.current)~="string"and queue.current~=false then fail("known473 queue literal differs")end
    if name=="player"then
      if queue.current~=GEAR or #queue.queue~=2 or queue.queue[1]~=GEAR or queue.queue[2]~=PROBE then fail("known473 current/queue identities differ")end
    elseif queue.current~=false or #queue.queue~=0 or queue.progress~=0 then fail("known473 paused queue differs")end
  end
  return known
end
local function known473_init()
  check_closure()
  if storage[KEY]~=nil then fail("known473 observer already existed")end
  local known=known473_expectations();local paused=game.forces["mir5-full-catalogue-upgrade-paused"]
  if not paused or paused.valid==false then fail("known473 paused force absent")end
  local plan=PLAN.base
  storage[KEY]={phase="await-known473",plan="base",source_labs=1,successor_labs=0,paused_index=paused.index,
    source_snapshot_origin=literal_copy(known.origin),source_snapshot=literal_copy(known.frames.player),
    paused_snapshot=literal_copy(known.frames[paused.name]),player_queue=literal_copy(known.queues.player),
    paused_queue=literal_copy(known.queues[paused.name]),
    incoming_candidate_observation={player=snapshot(game.forces.player,plan,true),paused=snapshot(paused,plan,true)}}
end
local function assert_successor_snapshot(force, plan, expected, label)
  local actual = snapshot(force, plan)
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    local wanted = name == GEAR and before.level + 1 or before.level
    if now == nil or now.level ~= wanted or now.researched ~= before.researched
        or now.enabled ~= before.enabled or now.visible ~= before.visible or now.maximum ~= before.maximum
        or not close(now.saved, name == GEAR and 0 or before.saved) then fail(label .. " technology state changed: " .. name) end
  end
  for name, before in pairs(expected.recipes) do
    local extra = (name == "iron-gear-wheel" or name == "casting-iron-gear-wheel") and .1 or 0
    if not close(actual.recipes[name], before + extra) then fail(label .. " recipe bonus changed: " .. name) end
  end
  for name, before in pairs(expected.fields) do if not close(actual.fields[name], before) then fail(label .. " native force effect changed: " .. name) end end
  for name, before in pairs(expected.guns) do if not close(actual.guns[name], before) then fail(label .. " native gun effect changed: " .. name) end end
  return actual
end
local function assert_credits(force, plan, label)
  for _, name in ipairs(plan.credits) do
    local value = technology(force, name)
    if value.level ~= 1 or value.researched or value.enabled ~= false or value.visible_when_disabled ~= false
        or value.prototype.hidden ~= true or value.prototype.max_level ~= UINT32_MAX then
      fail(label .. " hidden zero-credit carrier differs: " .. name)
    end
  end
end
local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("real lab is absent") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real lab input is absent") end
  return value, inventory
end
local function fill(state, value)
  local entity, inventory = lab(state)
  inventory.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if inventory.insert{name=ingredient.name, count=64} ~= 64 then fail("could not insert science: " .. ingredient.name) end
  end
  entity.energy = 1000000000
end
local function freeze(state)
  local entity, inventory = lab(state)
  entity.energy = 0
  inventory.clear()
end
local function marker(stage, state, plan, profile_name)
  local report={
    case="full-catalogue-upgrade", stage=stage, status="passed", profile=profile_name,
    qualification="native-runner-readback-required", worker_native_owner=WORKER_OWNER,
    source_snapshot_origin=state.source_snapshot_origin,incoming_candidate_observation=state.incoming_candidate_observation,
    worker_frames=WORKER_OWNER and {player=worker_owner_snapshot(game.forces.player),
      paused=worker_owner_snapshot(game.forces[state.paused_index])} or nil, witnesses={
      public_rows=#plan.public, level_backed_rows=#plan.state, native_owner_rows=#plan.native_owners,
      scripted_rows_not_seeded=#plan.scripted, zero_credit_rows=#plan.credits,
      source_gear_lab=state.source_labs, successor_gear_lab=state.successor_labs,
      queued_progress=.42, paused_progress=.27, save_name=SAVE, on_load_read_only=stage == "reload",
    },
  }
  if WORKER_OWNER~=nil then
    report.witnesses.queued_progress=state.player_queue.progress
    report.witnesses.paused_progress=state.paused_snapshot.technologies[GEAR].saved
    report.witnesses.source_gear_lab_historical=true
    report.witnesses.new_ordinary_labs=0
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json(report))
end
local function source_init()
  check_closure()
  local plan, profile_name = profile()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  seed_levels(player, plan, "source player")
  local gear = technology(player, GEAR)
  prerequisites(gear)
  local paused = game.create_force("mir5-full-catalogue-upgrade-paused")
  paused.enable_all_prototypes(); seed_levels(paused, plan, "source paused")
  local paused_gear = technology(paused, GEAR)
  paused_gear.saved_progress = .27
  if not close(paused_gear.saved_progress, .27) or paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0 then
    fail("paused saved work seed differs")
  end
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if entity == nil or entity.valid == false then fail("could not create a real gear lab") end
  local state = {phase="await-source-lab", plan=profile_name, lab=entity, paused_index=paused.index, paused_snapshot=snapshot(paused, plan),
    source_labs=0, successor_labs=0, deadline=game.tick + DEADLINE}
  storage[KEY] = state
  fill(state, gear)
  if player.add_research(gear) ~= true then fail("could not queue source gear lab") end
end
local function source_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture state is absent") end
  local plan, profile_name = profile()
  if state.phase == "completed" then
    if loaded and not reload_logged then
      assert_same_snapshot(game.forces.player, plan, state.source_snapshot, "source cold reload")
      local paused = game.forces[state.paused_index]
      if paused == nil or not close(technology(paused, GEAR).saved_progress, .27) then fail("source cold reload lost paused work") end
      assert_same_snapshot(paused, plan, state.paused_snapshot, "source paused cold reload")
      marker("reload", state, plan, profile_name); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("source gear lab did not finish") end
  if state.phase == "await-source-lab" then
    local _, inventory = lab(state); state.lab.energy = 1000000000
    if state.source_labs ~= 1 then return end
    freeze(state)
    local player, gear, probe = game.forces.player, technology(game.forces.player, GEAR), technology(game.forces.player, PROBE)
    prerequisites(probe)
    if probe.researched then fail("unrelated queue probe was researched") end
    gear.saved_progress, probe.saved_progress = .42, 0
    player.research_queue = {gear, probe}; player.research_progress = .42
    state.player_queue = assert_queue(player, {current=GEAR, queue={GEAR, PROBE}, progress=.42}, "source queued work")
    state.source_snapshot = snapshot(player, plan)
    state.phase = "completed"
    marker("initial", state, plan, profile_name); game.server_save(SAVE)
  end
end
local function successor_config(event)
  check_closure()
  if WORKER_OWNER ~= nil then
    local changes=event and event.mod_changes
    local mir=type(changes)=="table"and changes["more-infinite-research"]
    if not event or event.mod_startup_settings_changed~=false or type(mir)~="table"
      or mir.old_version~="4.7.20003" or mir.new_version~="5.0.20012" then fail("paid-idle worker source event differs")end
    for name,version in pairs(script.active_mods)do
      if name~="base"and name~="more-infinite-research"then
        local change=changes[name]
        if name~=FIXTURE and name~="mir-fixture-mir5-active-mods-observer"
          or type(change)~="table"or change.old_version~=nil or change.new_version~=version then
          fail("paid-idle worker prior selection differs")
        end
      end
    end
    for name,change in pairs(changes)do
      if name~="more-infinite-research"and(type(change)~="table"or type(change.new_version)~="string"
        or change.new_version~=script.active_mods[name]or name=="base"and change.old_version~="2.0.77"
        or name~="base"and change.old_version~=nil)then fail("paid-idle worker removed/changed prior mod")end
    end
  end
  local state = storage[KEY]
  if WORKER_OWNER~=nil then
    local known=known473_expectations()
    if type(state)~="table"or state.phase~="await-known473"
      or not literal_equal(state.source_snapshot_origin,known.origin)
      or not literal_equal(state.source_snapshot,known.frames.player)
      or not literal_equal(state.paused_snapshot,known.frames["mir5-full-catalogue-upgrade-paused"])
      or not literal_equal(state.player_queue,known.queues.player)
      or not literal_equal(state.paused_queue,known.queues["mir5-full-catalogue-upgrade-paused"])then fail("known473 observer/source literals changed")end
    local plan=PLAN.base;local paused=game.forces[state.paused_index]
    if not paused or paused.name~="mir5-full-catalogue-upgrade-paused"then fail("known473 paused identity changed")end
    assert_same_snapshot(game.forces.player,plan,state.source_snapshot,"known473 post-MIR")
    assert_same_snapshot(paused,plan,state.paused_snapshot,"known473 post-MIR paused")
    assert_queue(game.forces.player,state.player_queue,"known473 post-MIR")
    assert_queue(paused,state.paused_queue,"known473 post-MIR paused")
    assert_credits(game.forces.player,plan,"known473 post-MIR");assert_credits(paused,plan,"known473 post-MIR paused")
    state.phase="known473-observed"
    return
  end
  if type(state) ~= "table" or state.phase ~= "completed" or type(state.source_snapshot) ~= "table" or type(state.paused_snapshot) ~= "table" then
    fail("successor lacks the complete published source witness")
  end
  local plan, profile_name = profile()
  if state.plan ~= profile_name then fail("successor changed selected profile") end
  local player = game.forces.player
  assert_same_snapshot(player, plan, state.source_snapshot, "pre-successor")
  assert_credits(player, plan, "pre-successor")
  assert_queue(player, state.player_queue, "pre-successor")
  local paused = game.forces[state.paused_index]
  if paused == nil or paused.valid == false or not close(technology(paused, GEAR).saved_progress, .27)
      or paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0 then fail("successor changed paused work") end
  assert_same_snapshot(paused, plan, state.paused_snapshot, "pre-successor paused")
  state.phase, state.deadline = "await-successor-lab", game.tick + DEADLINE
  fill(state, technology(player, GEAR))
end
local function successor_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor fixture state is absent") end
  local plan, profile_name = profile()
  if WORKER_OWNER~=nil then
    local known=known473_expectations();local paused=game.forces[state.paused_index]
    if not literal_equal(state.source_snapshot_origin,known.origin)or not literal_equal(state.source_snapshot,known.frames.player)
      or not literal_equal(state.paused_snapshot,known.frames["mir5-full-catalogue-upgrade-paused"])
      or not literal_equal(state.player_queue,known.queues.player)
      or not literal_equal(state.paused_queue,known.queues["mir5-full-catalogue-upgrade-paused"])
      or not paused or paused.name~="mir5-full-catalogue-upgrade-paused"then fail("known473 saved observer provenance changed")end
    assert_same_snapshot(game.forces.player,plan,state.source_snapshot,"known473 saved/cold")
    assert_same_snapshot(paused,plan,state.paused_snapshot,"known473 saved/cold paused")
    assert_queue(game.forces.player,state.player_queue,"known473 saved/cold")
    assert_queue(paused,state.paused_queue,"known473 saved/cold paused")
    assert_credits(game.forces.player,plan,"known473 saved/cold");assert_credits(paused,plan,"known473 saved/cold paused")
    if state.phase=="known473-observed"then
      state.phase="known473-completed";marker("initial",state,plan,profile_name);game.server_save(SAVE)
    elseif state.phase=="known473-completed"then
      if loaded and not reload_logged then marker("reload",state,plan,profile_name);reload_logged=true end
    else fail("known473 save phase differs")end
    return
  end
  if state.phase == "successor-completed" then
    if loaded and not reload_logged then
      assert_successor_snapshot(game.forces.player, plan, state.source_snapshot, "successor cold reload")
      assert_credits(game.forces.player, plan, "successor cold reload")
      local paused = game.forces[state.paused_index]
      if paused == nil then fail("successor cold reload lost paused force") end
      assert_same_snapshot(paused, plan, state.paused_snapshot, "successor paused cold reload")
      marker("reload", state, plan, profile_name); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("successor gear lab did not finish") end
  if state.phase == "await-successor-lab" then
    local entity = lab(state); entity.energy = 1000000000
  elseif state.phase == "await-successor-observation" then
    freeze(state)
    assert_successor_snapshot(game.forces.player, plan, state.source_snapshot, "successor lab")
    assert_credits(game.forces.player, plan, "successor lab")
    local paused = game.forces[state.paused_index]
    if paused == nil or not close(technology(paused, GEAR).saved_progress, .27) then fail("successor lost paused progress") end
    assert_same_snapshot(paused, plan, state.paused_snapshot, "successor paused lab")
    state.phase = "successor-completed"
    marker("initial", state, plan, profile_name); game.server_save(SAVE)
  end
end

if SOURCE then
  script.on_init(source_init)
else
  if WORKER_OWNER~=nil then script.on_init(known473_init)end
  script.on_configuration_changed(function(event) successor_config(event) end)
end
script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= GEAR then return end
  if SOURCE and state.phase == "await-source-lab" then state.source_labs = state.source_labs + 1
  elseif not SOURCE and state.phase == "await-successor-lab" then
    state.successor_labs = state.successor_labs + 1; state.phase = "await-successor-observation"
  end
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and (state.phase == "completed" or state.phase == "successor-completed" or state.phase == "known473-completed")
  reload_logged = false
end)
script.on_event(defines.events.on_tick, function()
  if SOURCE then source_tick() else successor_tick() end
end)

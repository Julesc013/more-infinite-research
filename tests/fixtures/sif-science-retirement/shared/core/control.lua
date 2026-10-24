local TARGETS = {
  f200 = {base="2.0.77", sif="1.0.60", commons="1.0.27", source="4.7.20002", successor="5.0.20000"},
  f210 = {base="2.1.23", sif="1.0.78", commons="1.0.33", extras="1.0.01", source="4.7.21002", successor="5.0.21000"}
}
local POLICIES = {"configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all"}
local NAMES = {"research-speed-7", "weapon-shooting-speed-7"}
local KEY, SAVE, INITIAL, DEADLINE = "mir5_sif_science_retirement", "mir5-native-complete", 8, 18000
local PARTIAL = { ["research-speed-7"] = .42, ["weapon-shooting-speed-7"] = .27 }
local loaded, reload_logged, fresh_candidate = nil, false, false
-- Factorio permits imports only while control.lua is being parsed. The
-- staged contract is shared by callbacks without using game or saved state.
local contract = require("__" .. script.mod_name .. "__/contract")

local function fail(message) error("[mir5-sif] " .. message) end
local function close(left, right) return type(left) == "number" and math.abs(left - right) <= 0.000001 end
local function target_id()
  for id, _ in pairs(TARGETS) do
    if script.active_mods["mir-fixture-mir5-sif-science-retirement-" .. id] then return id end
  end
  fail("target core fixture is absent")
end
local function selected_policy(target)
  local found, count
  for _, policy in ipairs(POLICIES) do
    if script.active_mods["mir-fixture-mir5-sif-policy-" .. policy .. "-" .. target] then
      found, count = policy, (count or 0) + 1
    end
  end
  if count ~= 1 then fail("exactly one SIF policy selector must be active") end
  return found
end
local function mode()
  local target = target_id()
  local exact = TARGETS[target]
  local fixture = "mir-fixture-mir5-sif-science-retirement-" .. target
  local version, mir = script.active_mods[fixture], script.active_mods["more-infinite-research"]
  if version == "0.1.0" and mir == exact.source then return target, "source", fixture, exact end
  if version == "0.2.0" and mir == exact.successor then return target, "successor", fixture, exact end
  fail("fixture and MIR stages do not form an admitted SIF transition")
end
local function assert_active(target, stage, exact)
  if script.active_mods.base ~= exact.base or script.active_mods["elevated-rails"] ~= exact.base
      or script.active_mods.quality ~= exact.base or script.active_mods["space-age"] ~= exact.base
      or script.active_mods["space-is-fake"] ~= exact.sif or script.active_mods["cr-commons"] ~= exact.commons then
    fail("exact SIF archive closure differs")
  end
  if exact.extras ~= nil then
    if script.active_mods.recycler ~= exact.base or script.active_mods["cr-extras"] ~= exact.extras then fail("F210 closure differs") end
  elseif script.active_mods.recycler ~= nil or script.active_mods["cr-extras"] ~= nil then
    fail("F200 unexpectedly selects an F210-only component")
  end
  local policy = selected_policy(target)
  local setting = settings.startup["mir-science-pack-ingredient-policy"]
  if not setting or setting.value ~= policy then fail("selector effective policy differs") end
  if stage == "source" and policy ~= "configured" then fail("published transition seed is configured-only") end
  return policy
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value or value.valid == false then fail("technology is absent: " .. name) end
  return value
end
local function status(force, name)
  local value = technology(force, name)
  return {level=value.level, researched=value.researched, enabled=value.enabled, progress=value.saved_progress}
end
local function copy_status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled, progress=value.progress}
end
local function same_status(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched or actual.enabled ~= expected.enabled
      or not close(actual.progress, expected.progress) then fail(label .. " technology state differs") end
end
local function bonus(force)
  return {lab=force.laboratory_speed_modifier, bullet=force.get_gun_speed_modifier("bullet"), shotgun=force.get_gun_speed_modifier("shotgun-shell")}
end
local function same_bonus(actual, expected, label)
  if not close(actual.lab, expected.lab) or not close(actual.bullet, expected.bullet)
      or not close(actual.shotgun, expected.shotgun) then fail(label .. " native effects differ") end
end
local function expected_bonus(before, completed)
  return {lab=before.lab + .6 * completed, bullet=before.bullet + .4 * completed, shotgun=before.shotgun + .4 * completed}
end
local function assert_accelerated(value, name)
  if value.research_unit_count ~= 2 or not close(value.research_unit_energy, 60) then
    fail(name .. " fixture acceleration differs")
  end
end
local function lab(state, recharge)
  local value = state.lab
  if not value or value.valid == false then fail("real lab is absent") end
  if recharge then value.energy = 100000000 end
  local modules = value.get_module_inventory()
  if not modules or modules.is_empty() ~= true then fail("real lab modules differ") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab inventory is absent") end
  return inventory
end
local function expected_row(row, stage, policy)
  if stage == "source" then return row.published.science, row.published.prerequisites end
  return row.science[policy], row.prerequisites[policy]
end
local function configured_packs(contract, stage)
  local found, out = {}, {}
  for _, name in ipairs(NAMES) do
    local science = expected_row(contract.rows[name], stage, "configured")
    for _, row in ipairs(science) do
      if not found[row[1]] then found[row[1]] = true; out[#out + 1] = row[1] end
    end
  end
  return out
end
local function consumption(contract, stage)
  local out = {}
  for _, name in ipairs(NAMES) do
    local science = expected_row(contract.rows[name], stage, "configured")
    for _, row in ipairs(science) do out[row[1]] = (out[row[1]] or 0) + row[2] end
  end
  return out
end
local function fill(inventory, packs)
  for _, name in ipairs(packs) do
    if inventory.insert{name=name,count=INITIAL} ~= INITIAL then fail("could not insert native science " .. name) end
  end
end
local function snapshot_counts(inventory, packs)
  local out = {}; for _, name in ipairs(packs) do out[name] = inventory.get_item_count(name) end; return out
end
local function assert_consumption(inventory, before, expected, label)
  for name, amount in pairs(expected) do
    local actual = before[name] - inventory.get_item_count(name)
    if actual ~= amount then fail(label .. " real lab consumption differs for " .. name) end
  end
end
local function prerequisites(force, name)
  for _, prerequisite in pairs(technology(force, name).prerequisites) do prerequisite.research_recursive() end
end
local function queue(force, name, progress)
  local value = technology(force, name)
  if force.current_research ~= nil or force.add_research(value) ~= true then fail("could not queue " .. name) end
  if #force.research_queue ~= 1 or force.research_queue[1].name ~= name then fail("research queue differs for " .. name) end
  if progress ~= nil and not close(force.research_progress, progress) then fail(name .. " detached progress did not resume") end
end
local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="sif-science-retirement-" .. state.target, stage=stage, status="passed",
    witnesses={target=state.target, policy=state.policy, source_mir=state.source_mir,
      successor_mir=state.successor_mir, source_actual_labs=state.source_labs,
      successor_actual_labs=state.successor_labs, names=NAMES, retired_space_science=false,
      retired_space_prerequisite=false, on_load_read_only=stage=="reload",
      policy_upgrade_scope="configured-only", source_partial_progress=state.source_progress,
      successor_consumption_observation=state.successor_consumption}
  }))
end
local function fresh_marker(target, policy, exact)
  log("[MIR5_SIF_CANDIDATE] RESULT " .. helpers.table_to_json({
    case="sif-science-retirement-" .. target .. "-" .. policy,
    stage="init", status="passed",
    witnesses={target=target, policy=policy, mir_version=exact.successor,
      fresh_candidate=true, runtime_rows=true, retired_space_science=false,
      retired_space_prerequisite=false, storage_writes=false,
      native_state_writes=false}
  }))
end
local function assert_rows(force, contract, stage, policy)
  for _, name in ipairs(NAMES) do
    local value = technology(force, name)
    assert_accelerated(value, name)
    local expected_science, expected_prerequisites = expected_row(contract.rows[name], stage, policy)
    local ingredients = value.research_unit_ingredients
    if #ingredients ~= #expected_science then fail(name .. " runtime science cardinality differs") end
    local actual_science = {}
    for _, got in ipairs(ingredients) do
      if actual_science[got.name] ~= nil then fail(name .. " duplicate runtime science: " .. got.name) end
      if got.name == "space-science-pack" then fail(name .. " retained space science") end
      actual_science[got.name] = got.amount
    end
    -- Native runtime array order is not part of the research cost. The
    -- data-stage preflight separately checks authored declaration order.
    for _, wanted in ipairs(expected_science) do
      if actual_science[wanted[1]] ~= wanted[2] then
        fail(name .. " runtime science differs for " .. wanted[1] .. ": expected "
          .. tostring(wanted[2]) .. ", got " .. tostring(actual_science[wanted[1]]))
      end
    end
    local seen, count = {}, 0
    for _, prerequisite in pairs(value.prerequisites) do
      if prerequisite.name == "space-science-pack" then fail(name .. " retained space prerequisite") end
      if prerequisite.name then
        if seen[prerequisite.name] then fail(name .. " duplicate runtime prerequisite") end
        seen[prerequisite.name], count = true, count + 1
      end
    end
    if count ~= #expected_prerequisites then fail(name .. " runtime prerequisite cardinality differs") end
    for _, prerequisite in ipairs(expected_prerequisites) do
      if not seen[prerequisite] then fail(name .. " runtime prerequisite differs: " .. prerequisite) end
    end
  end
end
local function assert_fresh_candidate(force, contract, policy)
  assert_rows(force, contract, "successor", policy)
  for _, name in ipairs(NAMES) do
    local value = status(force, name)
    if value.level ~= 7 or value.researched or value.enabled ~= true or not close(value.progress, 0) then
      fail("fresh candidate " .. name .. " state differs")
    end
  end
  same_bonus(bonus(force), {lab=0, bullet=0, shotgun=0}, "fresh candidate")
end
local function assert_source_complete(state, contract)
  if state.source_labs ~= 2 then fail("published fixture did not complete two named labs") end
  for _, name in ipairs(NAMES) do
    if technology(game.forces.player, name).level ~= 8 then fail(name .. " published level differs") end
  end
  same_bonus(bonus(game.forces.player), expected_bonus(state.bonus_before, 1), "published")
  assert_consumption(lab(state), state.source_before, consumption(contract, "source"), "published")
  if state.source_rows ~= nil then
    if game.forces.player.current_research ~= nil or #(game.forces.player.research_queue or {}) ~= 0 then
      fail("published detached progress is queued")
    end
    for _, name in ipairs(NAMES) do
      if not close(status(game.forces.player, name).progress, PARTIAL[name]) then
        fail(name .. " published detached progress differs")
      end
      same_status(status(game.forces.player, name), state.source_rows[name], "published durable " .. name)
    end
  end
end
local function finish_source(state, contract)
  assert_source_complete(state, contract)
  for _, name in ipairs(NAMES) do technology(game.forces.player, name).saved_progress = PARTIAL[name] end
  state.source_rows, state.source_bonus = {}, bonus(game.forces.player)
  for _, name in ipairs(NAMES) do state.source_rows[name] = copy_status(status(game.forces.player, name)) end
  state.source_progress = { [NAMES[1]] = PARTIAL[NAMES[1]], [NAMES[2]] = PARTIAL[NAMES[2]] }
  assert_source_complete(state, contract)
  state.phase = "source-complete"; marker("initial", state); game.server_save(SAVE)
end
local function assert_successor_complete(state, contract)
  if state.successor_labs ~= 2 then fail("successor did not complete two named labs") end
  for _, name in ipairs(NAMES) do
    if technology(game.forces.player, name).level ~= 9 then fail(name .. " successor level differs") end
  end
  same_bonus(bonus(game.forces.player), expected_bonus(state.source_bonus, 1), "successor")
  if state.phase == "complete" then
    local force = game.forces.player
    if force.current_research ~= nil or #(force.research_queue or {}) ~= 0 then
      fail("successor completed research is queued")
    end
    if type(state.successor_rows) ~= "table" or type(state.successor_bonus) ~= "table"
        or type(state.successor_consumption) ~= "table" or type(state.successor_consumption.after) ~= "table" then
      fail("successor durable witness is absent")
    end
    for _, name in ipairs(NAMES) do
      same_status(status(force, name), state.successor_rows[name], "successor durable " .. name)
    end
    same_bonus(bonus(force), state.successor_bonus, "successor durable")
    local inventory = lab(state)
    for _, name in ipairs(configured_packs(contract, "successor")) do
      if inventory.get_item_count(name) ~= state.successor_consumption.after[name] then
        fail("successor durable science inventory differs: " .. name)
      end
    end
  end
end
local function finish_successor(state, contract)
  assert_successor_complete(state, contract)
  state.successor_consumption = {before=state.successor_before,
    after=snapshot_counts(lab(state), configured_packs(contract, "successor"))}
  state.successor_rows, state.successor_bonus = {}, bonus(game.forces.player)
  for _, name in ipairs(NAMES) do state.successor_rows[name] = copy_status(status(game.forces.player, name)) end
  state.phase = "complete"; marker("initial", state); game.server_save(SAVE)
end
script.on_init(function()
  local target, stage, _, exact = mode()
  local policy = assert_active(target, stage, exact)
  local player = game.forces.player
  if stage == "successor" then
    -- Candidate policy matrix runs create a fresh map. This branch is a
    -- read-only emission witness, never an upgrade substitute.
    assert_fresh_candidate(player, contract, policy)
    fresh_candidate = true
    fresh_marker(target, policy, exact)
    return
  end
  player.enable_all_prototypes(); assert_rows(player, contract, "source", policy)
  for _, name in ipairs(NAMES) do prerequisites(player, name) end
  local surface = game.surfaces[1]
  local entity = surface and surface.create_entity{name="biolab",position={0,0},force=player}
  if not entity or not entity.valid then fail("could not create real lab") end
  local state = {target=target, policy=policy, source_mir=exact.source, successor_mir=exact.successor,
    lab=entity, phase="source-first", source_labs=0, successor_labs=0, deadline=game.tick+DEADLINE,
    bonus_before=bonus(player)}
  storage[KEY] = state
  local inventory, packs = lab(state, true), configured_packs(contract, "source")
  fill(inventory, packs); state.source_before=snapshot_counts(inventory, packs); queue(player, NAMES[1])
end)
script.on_configuration_changed(function()
  local target, stage, _, exact = mode()
  if stage ~= "successor" then return end
  local policy = assert_active(target, stage, exact)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "source-complete" or state.source_mir ~= exact.source
      or state.policy ~= "configured" or policy ~= "configured" then fail("published configured source witness is absent") end
  local player = game.forces.player; assert_rows(player, contract, "successor", policy)
  for _, name in ipairs(NAMES) do same_status(status(player, name), state.source_rows[name], "successor restored " .. name) end
  if player.current_research ~= nil or #(player.research_queue or {}) ~= 0 then fail("successor restored detached progress is queued") end
  for _, name in ipairs(NAMES) do
    if not close(status(player, name).progress, PARTIAL[name]) then fail(name .. " successor detached progress differs") end
  end
  same_bonus(bonus(player), state.source_bonus, "successor restored")
  local inventory, packs = lab(state, true), configured_packs(contract, "successor")
  fill(inventory, packs); state.successor_before=snapshot_counts(inventory, packs)
  state.policy, state.successor_labs, state.phase, state.deadline = policy, 0, "successor-first", game.tick+DEADLINE
  queue(player, NAMES[1], PARTIAL[NAMES[1]])
  -- This callback replaces the completed source state with a successor
  -- workflow.  A preceding source cold load may have captured the completed
  -- source witness locally; it is obsolete only after the validated
  -- successor queue is established.  The next actual cold load captures and
  -- checks the successor witness without writing saved state.
  loaded = nil
end)
script.on_event(defines.events.on_research_finished, function(event)
  if event.by_script ~= false then return end
  local state = storage[KEY]
  if type(state) ~= "table" or not event.research or event.research.force ~= game.forces.player then return end
  local expected = state.phase == "source-first" and NAMES[1] or state.phase == "source-second" and NAMES[2]
    or state.phase == "successor-first" and NAMES[1] or state.phase == "successor-second" and NAMES[2] or nil
  if event.research.name ~= expected then return end
  if state.phase == "source-first" then state.source_labs, state.phase = 1, "source-queue-second"
  elseif state.phase == "source-second" then state.source_labs, state.phase = 2, "source-observe"
  elseif state.phase == "successor-first" then state.successor_labs, state.phase = 1, "successor-queue-second"
  elseif state.phase == "successor-second" then state.successor_labs, state.phase = 2, "successor-observe" end
end)
script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "source-complete" or state.phase == "complete") then
    loaded = {phase=state.phase, source_labs=state.source_labs, successor_labs=state.successor_labs}
  else loaded = nil end
  reload_logged = false
end)
script.on_event(defines.events.on_tick, function()
  if fresh_candidate then return end
  local state = storage[KEY]
  if type(state) ~= "table" then fail("fixture state is absent") end
  mode()
  if state.phase == "source-complete" or state.phase == "complete" then
    if loaded and not reload_logged then
      if loaded.phase ~= state.phase or loaded.source_labs ~= state.source_labs or loaded.successor_labs ~= state.successor_labs then
        fail("cold load changed durable fixture witness") end
      if state.phase == "complete" then assert_successor_complete(state, contract) else assert_source_complete(state, contract) end
      marker("reload", state); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("real named research did not meet the fixture deadline") end
  lab(state, true)
  if state.phase == "source-queue-second" then queue(game.forces.player, NAMES[2]); state.phase="source-second"
  elseif state.phase == "source-observe" then finish_source(state, contract)
  elseif state.phase == "successor-queue-second" then queue(game.forces.player, NAMES[2], PARTIAL[NAMES[2]]); state.phase="successor-second"
  elseif state.phase == "successor-observe" then finish_successor(state, contract) end
end)

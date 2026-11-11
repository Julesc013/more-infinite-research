-- Observer runs after MIR through its declared dependency. Script setup is
-- labelled; only by_script=false native-owner finishes count as ordinary work.
local M = {}
local MAIN, TAIL, GATE = "worker-robots-storage-4", "mir-worker-storage-default-4", "mir-worker-storage-head-4"
local PRIVATE = "mir-worker-storage-preservation-4"
local CURRENT, QUEUED, DETACHED = "mir-worker-default-native-current", "mir-worker-default-native-queued", "mir-worker-default-native-detached"
local LAB, FIXTURE = "mir-worker-default-native-lab", "mir-worker-storage-default-native"
local KEY = "worker_storage_default_native_fixture"
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}
local PREREQUISITES = {"worker-robots-storage-2", "worker-robots-storage-3", "automation-science-pack",
  "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}
local IDS = {MAIN, TAIL, GATE, PRIVATE, CURRENT, QUEUED, DETACHED}
local ROLES = {"player", "mir-worker-default-queued", "mir-worker-default-detached", "mir-worker-default-unpaid"}
local loaded = false
M.ids = {main=MAIN, tail=TAIL, gate=GATE, private=PRIVATE, current=CURRENT, queued=QUEUED, detached=DETACHED}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function check(ok, reason) if not ok then error("[worker-default-native] " .. reason, 2) end end
function M.same(a, b, path)
  path = path or "$"
  check(type(a) == type(b), path .. " type differs")
  if type(a) ~= "table" then check(a == b, path .. " scalar differs"); return end
  for k, v in pairs(a) do M.same(v, b[k], path .. "/" .. tostring(k)) end
  for k in pairs(b) do check(a[k] ~= nil, path .. "/" .. tostring(k) .. " unexpected") end
end
function M.next_level(t) return t.level + (t.researched and 1 or 0) end
local function price(n) return math.floor(675 * 1.5 ^ (n - 4)) end
local function row(name, n, enabled, visible, saved, researched)
  return {name=name, level=n, researched=researched or false, enabled=enabled, visible=visible,
    saved=saved or 0, count=name == GATE and 1 or price(n)}
end
function M.expected_upgrade(before)
  local expected = copy(before)
  for _, force in ipairs(expected) do
    local source = force.rows[MAIN]; local n = M.next_level(source)
    check(not source.researched, "closed source must use its native advanced representation")
    force.rows[GATE] = row(GATE, n >= 5 and 5 or 4, false, false, 0, false)
    force.rows[TAIL] = row(TAIL, n, source.enabled, source.visible, source.saved)
    source.level, source.researched, source.enabled, source.visible, source.saved = n >= 5 and 5 or 4, false, false, n >= 5, 0
    source.count = price(source.level)
    if force.current == MAIN then force.current = TAIL end
    for i, name in ipairs(force.queue) do if name == MAIN then force.queue[i] = TAIL end end
  end
  return expected
end
function M.assert_callback_safe(player)
  local head, tail, gate = player.rows[MAIN], player.rows[TAIL], player.rows[GATE]
  check(head and head.level == 5 and head.researched == false and head.saved == 0,
    "callback retained unsafe canonical head work")
  check(player.current ~= MAIN, "callback retained canonical current work")
  for _, name in ipairs(player.queue) do check(name ~= MAIN, "callback retained canonical queued work") end
  check(gate and gate.level == 5 and gate.researched == false and tail and M.next_level(tail) >= 5, "callback stable gate/tail ownership")
end
function M.assert_settled_flags(player)
  local head, tail, gate = player.rows[MAIN], player.rows[TAIL], player.rows[GATE]
  check(head and head.visible == true, "settled public head cap visibility")
  check(tail and tail.visible == false, "settled default tail visibility")
  check(gate and gate.enabled == false and gate.visible == false and gate.saved == 0, "settled bookkeeping gate flags/work")
end
local function closure(old)
  local versions = {['2.1.23']={old="5.0.21011", new="5.0.21012"}, ['2.0.77']={old="5.0.20011", new="5.0.20012"}}
  local active = script.active_mods; local v = versions[active.base]
  check(v and active[FIXTURE] == "0.1.0" and active["more-infinite-research"] == (old and v.old or v.new), "exact engine/MIR/fixture tuple")
  local count = 0; for name in pairs(active) do check(name == "base" or name == FIXTURE or name == "more-infinite-research", "unexpected active mod"); count = count + 1 end
  check(count == 3 and game.speed == 1 and game.difficulty_settings.technology_price_multiplier == 1, "selection/clock/map-price control")
end
local function native_row(t)
  return {name=t.name, level=t.level, researched=t.researched, enabled=t.enabled,
    visible=t.visible_when_disabled, saved=t.saved_progress, count=t.research_unit_count}
end
function M.frames()
  local frames = {}
  for _, name in ipairs(ROLES) do
    local force = game.forces[name]; check(force and force.valid, "missing role force " .. name)
    local frame = {name=name, bonus=force.worker_robots_storage_bonus, current=force.current_research and force.current_research.name,
      progress=force.research_progress, queue={}, rows={}, mining=force.mining_drill_productivity_bonus,
      manual_mining=force.manual_mining_speed_modifier, lab_speed=force.laboratory_speed_modifier,
      lab_productivity=force.laboratory_productivity_bonus, robot_speed=force.worker_robots_speed_modifier}
    for _, t in ipairs(force.research_queue or {}) do frame.queue[#frame.queue + 1] = t.name end
    for _, id in ipairs(IDS) do local t = force.technologies[id]; if t then frame.rows[id] = native_row(t) end end
    frames[#frames + 1] = frame
  end
  return frames
end
local function lab_frame()
  local s = storage[KEY]; local lab = s and s.lab
  if not lab then return nil end
  check(lab.valid, "owned lab invalid")
  local input, amounts = lab.get_inventory(defines.inventory.lab_input), {}
  for _, pack in ipairs(SCIENCE) do amounts[pack] = input.get_item_count(pack) end
  return {disabled=lab.disabled_by_script, unit=lab.unit_number, speed=lab.prototype.get_researching_speed("normal"),
    inventory=amounts, modules_empty=lab.get_inventory(defines.inventory.lab_modules).is_empty()}
end
local function prototype_frames()
  local out = {}
  for _, id in ipairs({MAIN, TAIL, GATE, PRIVATE}) do
    local p = prototypes and prototypes.technology and prototypes.technology[id]
    if p then
      local prerequisites = {}
      for key, value in pairs(p.prerequisites) do prerequisites[#prerequisites + 1] = type(key) == "string" and key or value.name end
      table.sort(prerequisites)
      out[id] = {name=p.name, first=p.level, maximum=p.max_level, hidden=p.hidden, enabled=p.enabled,
        visible=p.visible_when_disabled, formula=p.research_unit_count_formula, count=p.research_unit_count,
        energy=p.research_unit_energy, ingredients=p.research_unit_ingredients, effects=p.effects,
        ignore_price=p.ignore_tech_cost_multiplier, prerequisites=prerequisites}
    end
  end
  return out
end
local function emit(stage, extra)
  local s = storage[KEY]; local body = {schema=1, stage=stage, tick=game.tick, mode=s and s.mode,
    mods=script.active_mods, frames=M.frames(), lab=lab_frame(), ordinary=s and s.ordinary, administrative=s and s.administrative,
    inserted=s and s.inserted, contracts=prototype_frames(), extra=extra}
  local text = helpers.table_to_json(body); log("MIR_WORKER_DEFAULT_NATIVE " .. text)
  helpers.write_file("worker-storage-default-native/" .. stage .. ".json", text, false)
end
local function contract(id, first, maximum, modifier)
  local p = prototypes.technology[id]
  check(p and p.level == first and p.max_level == maximum, "prototype start/max " .. id)
  check(#p.effects == 1 and p.effects[1].type == "worker-robot-storage" and p.effects[1].modifier == modifier, "native worker effect " .. id)
  check(prototypes.get_history("technology", id).created == "more-infinite-research", "MIR creation custody " .. id)
  if id == GATE then
    check(p.hidden and p.enabled == false and p.visible_when_disabled == false and p.research_unit_count == 1
      and p.research_unit_count_formula == nil and p.research_unit_energy == 60 and next(p.prerequisites) == nil, "gate contract")
  else
    check(p.research_unit_count_formula == "675*1.5^(L-4)" and p.research_unit_energy == 3600
      and p.ignore_tech_cost_multiplier == false and #p.research_unit_ingredients == 5, "default full price/time/science contract")
    check(p.hidden == (id == PRIVATE) and p.enabled == (id ~= PRIVATE) and p.visible_when_disabled == false,
      "exact default prototype flags " .. id)
  end
  local actual, expected = {}, id == GATE and {} or copy(PREREQUISITES)
  for key, prerequisite in pairs(p.prerequisites) do actual[#actual + 1] = type(key) == "string" and key or prerequisite.name end
  table.sort(actual); table.sort(expected); M.same(expected, actual, "$/prototype/" .. id .. "/prerequisites")
  for i, ingredient in ipairs(p.research_unit_ingredients) do
    check(ingredient.name == SCIENCE[i] and ingredient.amount == 1, "exact science vector " .. id)
  end
end
local function contracts(old)
  contract(MAIN, 4, 4294967295, 1)
  contract(PRIVATE, 4, 4294967295, 1)
  if old then check(prototypes.technology[TAIL] == nil and prototypes.technology[GATE] == nil, "old11 has no draft identities")
  else contract(TAIL, 4, 4294967295, 1); contract(GATE, 4, 4294967295, -1) end
end
local function setup(mode)
  local old = mode == "old-source"; closure(old); contracts(old)
  local s = {mode=mode, phase="setup", setting_up=true, ordinary={}, administrative={}, inserted={}}
  storage[KEY] = s
  for i, name in ipairs(ROLES) do
    local force = game.forces[name] or game.create_force(name)
    local main = force.technologies[old and MAIN or TAIL]
    for _, prerequisite in pairs(main.prerequisites) do prerequisite.research_recursive() end
    check(main.level == 4 and not main.researched and main.enabled and main.research_unit_count == 675, "initial unpaid head4")
    for _, id in ipairs({CURRENT, QUEUED, DETACHED}) do
      local t = force.technologies[id]; check(t and t.enabled and not t.researched and t.level == 1, "unearned independent sentinel")
    end
    if old and i <= 3 then main.level = ({8,7,6})[i] end -- labelled administrative setup, no ordinary claim.
    local owner_id = old and MAIN or TAIL
    if i == 1 then force.research_queue = old and {owner_id, QUEUED} or {owner_id, owner_id, QUEUED}; if old then force.research_progress = .42 end
    elseif i == 2 then force.research_queue = {CURRENT, owner_id, QUEUED}; force.research_progress = .125; main.saved_progress = .27
    elseif i == 3 then force.research_queue = {CURRENT}; force.research_progress = .19; main.saved_progress = .23
    else force.research_queue = {owner_id}; force.research_progress = .37 end
    force.technologies[DETACHED].saved_progress = .27
    check(force.worker_robots_storage_bonus == 3 + (main.level - 4), "scripted baseline contribution")
    check(force.laboratory_speed_modifier == 0 and force.laboratory_productivity_bonus == 0, "zero force lab bonuses")
  end
  local surface = game.surfaces[1]
  local tiles = {}; for x=-2,2 do for y=-2,2 do tiles[#tiles + 1] = {name="stone-path",position={x,y}} end end
  surface.set_tiles(tiles)
  s.lab = surface.create_entity{name=LAB, position={0,0}, force=game.forces.player}
  check(s.lab and s.lab.valid and s.lab.prototype.get_researching_speed("normal") == 3600, "owned unit-per-tick lab")
  s.lab.disabled_by_script = true; s.setting_up = false; s.baseline = M.frames()
  s.phase = old and "source-ready" or "head-research"
  if not old then s.lab.disabled_by_script = false end
  emit("setup", {scripted_prerequisites=true, scripted_higher_levels=old, scripted_foreign_partials=true})
end
local function foreign_unchanged(frames)
  local baseline = storage[KEY].baseline
  for i=2,#frames do M.same(baseline[i], frames[i], "$/foreign/" .. i) end
  for _, id in ipairs({PRIVATE, CURRENT, QUEUED, DETACHED}) do
    M.same(baseline[1].rows[id], frames[1].rows[id], "$/player/" .. id)
  end
  for _, field in ipairs({"mining", "manual_mining", "lab_speed", "lab_productivity", "robot_speed"}) do
    M.same(baseline[1][field], frames[1][field], "$/player/" .. field)
  end
end
local function first_settled(final)
  local frames = M.frames(); local player = frames[1]
  foreign_unchanged(frames)
  check(player.bonus == (final and 5 or 4), "ordinary contribution")
  local head, tail, gate = player.rows[MAIN], player.rows[TAIL], player.rows[GATE]
  M.assert_settled_flags(player)
  check(head.level == 5 and not head.researched and not head.enabled and head.saved == 0, "public fulfilled head preserved")
  check(tail.level == (final and 6 or 5) and not tail.researched and tail.enabled
    and gate.level == 5 and gate.researched == false, "native tail progression")
  check(player.current == (final and QUEUED or TAIL) and player.progress == 0, "settled native current/progress")
  M.same(player.queue, final and {QUEUED} or {TAIL, QUEUED}, "$/player/queue")
  return frames
end
local function save(phase, frames)
  local s = storage[KEY]; s.lab.disabled_by_script = true
  s.phase, s.closed, s.closed_lab = phase, copy(frames), lab_frame()
  emit(phase); check(game.is_multiplayer(), "save requires owned server")
  game.server_save("worker-default-" .. phase)
end
function M.begin(mode)
  check(mode == "first" or mode == "old-source" or mode == "upgrade" or mode == "cold", "unknown mode")
  if mode == "first" or mode == "old-source" then check(storage[KEY] == nil, "fixture already initialized"); setup(mode)
  elseif mode == "upgrade" then check(storage[KEY] and (storage[KEY].phase == "upgrade-ready"
    or storage[KEY].phase == "upgrade-saved"), "upgrade callback not observed")
  else M.cold() end
end
function M.cold()
  local s = storage[KEY]; check(s and s.closed and s.phase:match("%-saved$"), "cold requires closed source")
  emit("cold-observed")
  check(s.lab and s.lab.valid and s.lab.disabled_by_script and #s.ordinary == (s.mode == "first" and 2 or 0), "cold lab/count controls")
  closure(s.phase == "old-source-saved"); contracts(s.phase == "old-source-saved")
  M.same(s.closed, M.frames()); M.same(s.closed_lab, lab_frame()); emit("cold")
end
function M.on_configuration_changed(event)
  local s = storage[KEY]; if not s then return end
  emit("configuration-observed", {event=event}) -- full actual frame before strict comparison.
  check(s.phase == "old-source-saved", "unexpected configuration phase"); closure(false); contracts(false)
  local change = event.mod_changes["more-infinite-research"]
  check(change and change.old_version == (script.active_mods.base == "2.0.77" and "5.0.20011" or "5.0.21011")
    and change.new_version == script.active_mods["more-infinite-research"] and event.mod_startup_settings_changed == false, "exact unchanged-settings old11 transition")
  for name, item in pairs(event.mod_changes) do check(name == "more-infinite-research" or item.old_version == item.new_version, "unrelated configuration change") end
  s.expected_upgrade = M.expected_upgrade(s.closed); M.same(s.expected_upgrade, M.frames())
  check(s.lab.disabled_by_script and #s.ordinary == 0, "upgrade does not invent ordinary work")
  s.mode, s.phase = "upgrade", "upgrade-ready"
end
function M.on_finished(event)
  local s = storage[KEY]; if not s then return end
  local id = event.research.name
  if event.by_script == true then
    if not s.setting_up then emit("scripted-completion-observed", {name=id, by_script=true, force=event.research.force.name}) end
    check(s.setting_up or id == MAIN or id == TAIL or id == GATE or id == PRIVATE, "unexpected scripted completion")
    check(#s.administrative < 512, "administrative marker bound")
    s.administrative[#s.administrative + 1] = {name=id, force=event.research.force.name, tick=event.tick, by_script=true}; return
  end
  emit(s.phase == "head-research" and "completion-head-observed" or "completion-tail-observed",
    {name=id, by_script=event.by_script, force=event.research.force.name})
  check(event.by_script == false and event.research.force == game.forces.player and s.mode == "first"
    and (s.phase == "head-research" and id == TAIL or s.phase == "tail-research" and id == TAIL), "exact ordinary event order")
  s.ordinary[#s.ordinary + 1] = {name=id, tick=event.tick, by_script=false}
  local frames = M.frames(); foreign_unchanged(frames)
  M.assert_callback_safe(frames[1])
  check(frames[1].bonus == (#s.ordinary == 1 and 4 or 5), "callback native contribution")
  -- Raw completed-event cursor/current/queue are retained above. No guessed
  -- transient representation is rewritten; next native tick checks exact work.
  s.phase = #s.ordinary == 1 and "head-finished" or "tail-finished"
  if #s.ordinary == 2 then s.lab.disabled_by_script = true end
end
function M.on_tick()
  local s = storage[KEY]
  if not s then
    loaded = false
    local version = script.active_mods["more-infinite-research"]
    if version == "5.0.21011" or version == "5.0.20011" then M.begin("old-source")
    elseif version == "5.0.21012" or version == "5.0.20012" then M.begin("first")
    else check(false, "automatic start requires exact published11 or candidate12") end
    return
  end
  if loaded then loaded = false; if s.phase:match("%-saved$") then M.cold(); return end end
  if s.phase == "head-research" or s.phase == "tail-research" then
    local input = s.lab.get_inventory(defines.inventory.lab_input)
    for _, pack in ipairs(SCIENCE) do
      if input.get_item_count(pack) < 64 then
        local count = input.insert{name=pack,count=200}; check(count > 0, "actual lab supplies")
        s.inserted[pack] = (s.inserted[pack] or 0) + count
      end
    end
  elseif s.phase == "head-finished" then
    emit("head-settle-observed"); first_settled(false); s.phase = "tail-research"; emit("head-settled")
  elseif s.phase == "tail-finished" then
    emit("tail-settle-observed")
    local frames = first_settled(true); local inventory = lab_frame().inventory
    for _, pack in ipairs(SCIENCE) do check(s.inserted[pack] - inventory[pack] == 675 + 1012, "ordinary science depletion " .. pack) end
    check(#s.ordinary == 2, "two actual completions"); save("first-saved", frames)
  elseif s.phase == "source-ready" then save("old-source-saved", M.frames())
  elseif s.phase == "upgrade-ready" then
    emit("upgrade-settle-observed"); M.same(s.expected_upgrade, M.frames()); save("upgrade-saved", M.frames())
  end
end
local callbacks = M
if script.active_mods.WorkerRobotCargoSizeResearch then
  callbacks = require("provider_native").bind(M)
end
script.on_init(function() end)
script.on_load(callbacks.on_load or function() loaded = true end) -- locals only; no game/storage writes.
script.on_configuration_changed(callbacks.on_configuration_changed)
script.on_event(defines.events.on_tick, callbacks.on_tick)
script.on_event(defines.events.on_research_finished, callbacks.on_finished)
remote.add_interface("mir-worker-storage-default-native", {begin=callbacks.begin or M.begin})
return M

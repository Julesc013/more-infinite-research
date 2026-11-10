-- Finite actual-provider observer. All stored data belongs to this fixture.
local P = {}
local KEY = "worker_storage_default_native_fixture"
local MAIN, TAIL, GATE = "worker-robots-storage-4", "mir-worker-storage-default-4", "mir-worker-storage-head-4"
local PRIVATE, CONTINUATION = "mir-worker-storage-preservation-4", "worker-robots-storage-8"
local QUEUED = "mir-worker-default-native-queued"
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack"}
local EXTRA = {"worker-robots-storage-5", "worker-robots-storage-6", "worker-robots-storage-7", CONTINUATION}
-- The fourteen unearned finite Base2.1.23 prerequisites of the white-science
-- direct gate in the exact protected full4 checkpoint. No graph walker or
-- blanket Base-technology permission is needed in this bounded observer.
local BASE_SETUP = {}
for _, id in ipairs({"concrete", "electric-energy-accumulators", "electric-energy-distribution-1", "flammables",
  "productivity-module-2", "productivity-module-3", "radar", "rocket-fuel", "rocket-silo", "solar-energy",
  "space-science-pack", "speed-module", "speed-module-2", "speed-module-3"}) do BASE_SETUP[id] = true end
local function check(ok, why) if not ok then error("[worker-provider-native] " .. why, 2) end end
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function row(name, level, count, researched, enabled, visible, saved)
  return {name=name, level=level, count=count, researched=researched, enabled=enabled,
    visible=visible, saved=saved}
end

-- Independent finite mapping of the qualified full4 checkpoint, not MIR state.
function P.expected_handover(before)
  check(type(before) == "table" and #before == 4, "four protected source forces required")
  local out = copy(before)
  for i, force in ipairs(out) do
    local owner = force.rows[TAIL]; local n = ({8,7,6,4})[i]
    check(owner and owner.level == n and owner.researched == false
      and owner.count == math.floor(675 * 1.5 ^ (n - 4)), "exact full4 source cursor/price")
    local gate = force.rows[GATE]
    check(gate.level == (n >= 5 and 5 or 4) and gate.researched == false and gate.count == 1
      and gate.enabled == false and gate.visible == false and gate.saved == 0, "source debit paid level/flags/work")
    for _, id in ipairs(EXTRA) do check(force.rows[id] == nil, "source already contains provider rows") end
    force.rows[PRIVATE] = copy(owner); force.rows[PRIVATE].name = PRIVATE
    force.rows[MAIN] = row(MAIN, 4, 1000, n >= 5, true, false, 0)
    force.rows[TAIL] = row(TAIL, 4, 675, false, false, false, 0)
    for level=5,8 do
      local id = "worker-robots-storage-" .. level
      force.rows[id] = row(id, level, 1000 * 2 ^ (level - 4), false, true, false, 0)
    end
    if force.current == TAIL then force.current = PRIVATE end
    for j, id in ipairs(force.queue) do if id == TAIL then force.queue[j] = PRIVATE end end
  end
  return out
end

function P.bind(M)
  local loaded = false
  local function state() return assert(storage[KEY], "protected fixture state required") end
  local function native_row(t)
    return row(t.name, t.level, t.research_unit_count, t.researched, t.enabled, t.visible_when_disabled, t.saved_progress)
  end
  local function frames()
    local out = M.frames()
    for _, frame in ipairs(out) do
      for _, id in ipairs(EXTRA) do frame.rows[id] = native_row(assert(game.forces[frame.name].technologies[id])) end
    end
    return out
  end
  local function lab_frame()
    local lab = state().lab; check(lab and lab.valid, "protected lab unavailable")
    local amounts = {}; local input = lab.get_inventory(defines.inventory.lab_input)
    for _, pack in ipairs(SCIENCE) do amounts[pack] = input.get_item_count(pack) end
    return {disabled=lab.disabled_by_script, unit=lab.unit_number,
      speed=lab.prototype.get_researching_speed("normal"), inventory=amounts,
      modules_empty=lab.get_inventory(defines.inventory.lab_modules).is_empty()}
  end
  local function contracts()
    local out = {}
    for _, id in ipairs({MAIN, TAIL, GATE, PRIVATE, EXTRA[1], EXTRA[2], EXTRA[3], CONTINUATION}) do
      local t = assert(prototypes.technology[id], "missing provider prototype " .. id)
      out[id] = {first=t.level, maximum=t.max_level, enabled=t.enabled, hidden=t.hidden,
        visible=t.visible_when_disabled, count=t.research_unit_count, formula=t.research_unit_count_formula,
        energy=t.research_unit_energy, ingredients=t.research_unit_ingredients, effects=t.effects,
        created=prototypes.get_history("technology", id).created}
    end
    return out
  end
  local function emit(stage, extra)
    local s = state()
    local body = {schema=1, stage=stage, tick=game.tick, mode=s.mode, mods=script.active_mods,
      frames=frames(), lab=lab_frame(), ordinary=s.ordinary, administrative=s.administrative,
      inserted=s.inserted, contracts=contracts(), extra=extra}
    local text = helpers.table_to_json(body); log("MIR_WORKER_DEFAULT_NATIVE " .. text)
    helpers.write_file("worker-storage-default-native/" .. stage .. ".json", text, false)
  end
  local function closure()
    local active = script.active_mods
    check(active.base == "2.1.23" and active["more-infinite-research"] == "5.0.21012"
      and active["mir-worker-storage-default-native"] == "0.1.0"
      and active.WorkerRobotCargoSizeResearch == "1.0.0", "exact provider tuple")
    local count = 0; for name in pairs(active) do
      check(name == "base" or name == "more-infinite-research" or name == "mir-worker-storage-default-native"
        or name == "WorkerRobotCargoSizeResearch", "unexpected provider mod"); count = count + 1
    end
    check(count == 4 and game.speed == 1 and game.difficulty_settings.technology_price_multiplier == 1,
      "provider selection/clock/map price")
    check(settings.startup["worker-robot-cargo-size-max-level"].value == 7
      and settings.startup["worker-robot-cargo-size-infinite"].value == false, "actual upstream defaults")
    local p = prototypes.technology[CONTINUATION]
    check(p.level == 8 and p.max_level == 4294967295 and p.research_unit_energy == 3600
      and #p.effects == 1 and p.effects[1].type == "worker-robot-storage" and p.effects[1].modifier == 1,
      "MIR8 native continuation contract")
    check(#p.research_unit_ingredients == 6, "MIR8 six sciences")
    for i, ingredient in ipairs(p.research_unit_ingredients) do
      check(ingredient.name == SCIENCE[i] and ingredient.amount == 1, "MIR8 exact science vector")
    end
    local gate = prototypes.technology[GATE]
    check(gate.level == 4 and gate.max_level == 4294967295 and gate.research_unit_count == 1
      and gate.research_unit_count_formula == nil and gate.effects[1].modifier == -1, "unchanged native debit")
    check(prototypes.technology[TAIL].hidden and not prototypes.technology[TAIL].enabled,
      "retired default prototype is disabled and hidden")
  end
  local function foreign_unchanged(actual)
    local baseline = state().provider_baseline
    for i=2,4 do M.same(baseline[i], actual[i], "$/provider-foreign/" .. i) end
  end
  local function consumed()
    local s, inventory, out = state(), lab_frame().inventory, {}
    for _, pack in ipairs(SCIENCE) do out[pack] = (s.inserted[pack] or 0) - inventory[pack] end
    return out
  end
  local function supply(count)
    local s = state(); local input = s.lab.get_inventory(defines.inventory.lab_input)
    for i=1,count do local pack = SCIENCE[i]
      if input.get_item_count(pack) < 64 then
        local inserted = input.insert{name=pack,count=200}; check(inserted > 0, "provider science supply")
        s.inserted[pack] = (s.inserted[pack] or 0) + inserted
      end
    end
  end
  local function private_retired(frame)
    local private = frame.rows[PRIVATE]
    check(M.next_level(private) == 9 and not private.enabled and private.saved == 0,
      "earned private quota must retire at next9")
    check(not private.visible and private.count == math.floor(675 * 1.5 ^ (private.level - 4)),
      "retired private exact flags/price")
    check(frame.current ~= PRIVATE, "retired private current")
    for _, id in ipairs(frame.queue) do check(id ~= PRIVATE, "retired private queue") end
  end
  local function cold()
    local s = state(); emit("cold-observed"); closure()
    check(s.phase == "provider-saved" and s.lab.disabled_by_script and #s.ordinary == 2, "closed provider cold")
    M.same(s.closed, frames()); M.same(s.closed_lab, lab_frame()); emit("cold")
  end
  local callbacks = {}
  function callbacks.on_load() loaded = true end -- locals only
  function callbacks.on_configuration_changed(event)
    local s = state()
    emit("provider-configuration-observed", {event=event, scripted_predecessor_higher_levels_and_partials=true})
    check(s.phase == "upgrade-saved" and #s.ordinary == 0, "qualified full4 source phase")
    closure()
    local change = event.mod_changes.WorkerRobotCargoSizeResearch
    check(change and change.old_version == nil and change.new_version == "1.0.0", "one actual provider addition")
    for name, item in pairs(event.mod_changes) do
      check(name == "WorkerRobotCargoSizeResearch" or item.old_version == item.new_version, "unrelated provider transition")
    end
    local expected = P.expected_handover(s.closed); M.same(expected, frames(), "$/provider-entry")
    local lab = lab_frame()
    check(lab.disabled and lab.modules_empty and lab.speed == 115200, "paused 32-unit provider lab")
    for _, pack in ipairs(SCIENCE) do check(lab.inventory[pack] == 0, "empty protected lab") end
    check(expected[1].progress == .42000000000000004 and expected[1].rows[PRIVATE].count == 3417,
      "exact partial for strict1984 science prediction")
    -- No test setup write occurs before the complete four-force check above.
    s.provider_baseline, s.provider_input = copy(expected), copy(s.closed)
    s.mode, s.phase = "provider", "provider-private-ready"
    emit("provider-entry-verified", {expected_private_science_each=1984, expected_private_white=0})
  end
  function callbacks.on_finished(event)
    local s = state(); local id = event.research.name
    if event.by_script == true then
      local setup_class
      if s.provider_setting_up then
        if id == EXTRA[1] or id == EXTRA[2] or id == EXTRA[3] then setup_class = "finite-provider-setup"
        elseif BASE_SETUP[id] then
          local p = prototypes.technology[id]; local history = prototypes.get_history("technology", id)
          if p and history and history.created == "base" and type(p.max_level) == "number"
              and p.max_level >= 1 and p.max_level < 4294967295 and p.max_level == math.floor(p.max_level) then
            setup_class = "finite-base-prerequisite-setup"
          end
        end
      elseif id == MAIN or id == TAIL or id == GATE or id == PRIVATE then setup_class = "native-handover" end
      emit("provider-scripted-completion-observed",
        {name=id,force=event.research.force.name,by_script=true,setup_class=setup_class})
      check(setup_class ~= nil, "unexpected provider scripted completion")
      check(#s.administrative < 512, "provider administrative bound")
      s.administrative[#s.administrative+1] =
        {name=id,force=event.research.force.name,tick=event.tick,by_script=true,setup_class=setup_class}
      return
    end
    s.lab.disabled_by_script = true -- pause within the actual finish callback
    emit(s.phase == "provider-private-research" and "provider-private-completion-observed"
      or "provider-continuation-completion-observed", {name=id,force=event.research.force.name,by_script=event.by_script})
    check(event.by_script == false and event.research.force == game.forces.player
      and (s.phase == "provider-private-research" and id == PRIVATE
        or s.phase == "provider-continuation-research" and id == CONTINUATION), "provider ordinary order")
    foreign_unchanged(frames())
    check(frames()[1].bonus == (id == PRIVATE and 8 or 12), "provider actual earned bonus")
    s.ordinary[#s.ordinary+1] = {name=id,tick=event.tick,by_script=false}
    s.phase = id == PRIVATE and "provider-private-finished" or "provider-continuation-finished"
  end
  function callbacks.on_tick()
    local s = state()
    if loaded then loaded = false; if s.phase == "provider-saved" then cold(); return end end
    if s.phase == "provider-private-ready" then
      supply(5); s.phase = "provider-private-research"; s.lab.disabled_by_script = false
      emit("provider-private-started")
    elseif s.phase == "provider-private-research" then supply(5)
    elseif s.phase == "provider-continuation-research" then supply(6)
    elseif s.phase == "provider-private-finished" then
      emit("provider-private-settled")
      local f = frames()[1]; private_retired(f); foreign_unchanged(frames())
      check(f.bonus == 8 and f.current == QUEUED and f.progress == 0, "private completion sentinel remainder")
      M.same(f.queue, {QUEUED}); local used = consumed()
      local expected = copy(s.provider_baseline[1])
      expected.rows[PRIVATE], expected.bonus, expected.current, expected.progress, expected.queue =
        copy(f.rows[PRIVATE]), 8, QUEUED, 0, {QUEUED}
      M.same(expected, f, "$/private-earned-player")
      for i, pack in ipairs(SCIENCE) do check(used[pack] == (i == 6 and 0 or 1984), "strict private science " .. pack) end
      s.provider_private_consumed = copy(used)
      emit("provider-administrative-setup-before", {scripted_finite5_to7=true,ordinary=false})
      local force = game.forces.player
      local direct_white_gate = false
      for _, prerequisite in pairs(force.technologies[CONTINUATION].prerequisites) do
        if prerequisite.name == "space-science-pack" then direct_white_gate = true end
      end
      check(direct_white_gate, "expected MIR8 direct white-science gate")
      s.provider_setting_up = true
      for level=5,7 do force.technologies["worker-robots-storage-" .. level].researched = true end
      for _, prerequisite in pairs(force.technologies[CONTINUATION].prerequisites) do
        if not prerequisite.researched then prerequisite.research_recursive() end
      end
      s.provider_setting_up = nil
      check(force.worker_robots_storage_bonus == 11, "three scripted finite levels only")
      check(force.technologies[CONTINUATION].research_unit_count == 16000, "MIR8 exact inherited price")
      force.research_queue = {CONTINUATION, QUEUED}; force.research_progress = 0
      s.provider_continuation_baseline = frames(); s.provider_continuation_consumed = consumed()
      private_retired(s.provider_continuation_baseline[1]); foreign_unchanged(frames())
      s.phase = "provider-continuation-research"; supply(6); s.lab.disabled_by_script = false
      emit("provider-administrative-setup-after", {scripted_finite5_to7=true,ordinary=false})
    elseif s.phase == "provider-continuation-finished" then
      emit("provider-continuation-settled")
      local actual = frames(); local f = actual[1]; private_retired(f); foreign_unchanged(actual)
      check(f.bonus == 12 and M.next_level(f.rows[CONTINUATION]) == 9 and f.current == QUEUED
        and f.progress == 0, "earned MIR8 and exact foreign sentinel current")
      M.same(f.queue, {QUEUED})
      local earned = f.rows[CONTINUATION]
      check(earned.enabled and not earned.visible and earned.saved == 0
        and earned.count == 16000 * 2 ^ (earned.level - 8), "earned MIR8 exact flags/price")
      local expected = copy(s.provider_continuation_baseline[1])
      expected.rows[CONTINUATION], expected.bonus, expected.current, expected.progress, expected.queue =
        copy(earned), 12, QUEUED, 0, {QUEUED}
      M.same(expected, f, "$/continuation-earned-player")
      local used = consumed()
      for _, pack in ipairs(SCIENCE) do check(used[pack] - s.provider_continuation_consumed[pack] == 16000,
        "MIR8 exact16000 science " .. pack) end
      check(#s.ordinary == 2, "exact two provider ordinary completions")
      s.phase, s.closed, s.closed_lab = "provider-saved", copy(actual), lab_frame()
      emit("provider-saved", {private_science=s.provider_private_consumed,continuation_science_each=16000})
      check(game.is_multiplayer(), "provider save requires owned server")
      game.server_save("worker-default-provider-saved")
    end
  end
  function callbacks.begin(mode)
    check(mode == "cold", "provider begin only permits cold observation"); cold()
  end
  return callbacks
end
return P

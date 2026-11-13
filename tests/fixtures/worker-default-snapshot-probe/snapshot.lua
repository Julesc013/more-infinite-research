-- Test-only finite observation. This is not a production snapshot mechanism.
local M = {}
M.fixture = "mir-fixture-worker-default-snapshot"
M.main, M.private = "worker-robots-storage-4", "mir-worker-storage-preservation-4"
M.sentinel, M.lab = M.fixture .. "-sentinel", M.fixture .. "-lab"
M.forces = {"player", M.fixture .. "-queued", M.fixture .. "-detached"}
M.sciences = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack"}
M.save_tick, M.save_name = 263, "mir-worker-default-snapshot"

function M.require(ok, reason)
  if not ok then error("worker default snapshot probe: " .. reason, 2) end
end

function M.same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not M.same(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end

function M.emit(stage, body)
  local encoded = helpers.table_to_json(body)
  M.require(type(encoded) == "string" and #encoded <= 131072, "bounded observation")
  log("[MIR_WORKER_DEFAULT_SNAPSHOT] " .. stage .. " " .. encoded)
end

function M.closure()
  local active = script.active_mods
  local count = 0
  for name in pairs(active) do
    count = count + 1
    M.require(name == "base" or name == "more-infinite-research" or name == M.fixture, "unexpected active mod")
  end
  M.require(count == 3 and active.base == "2.1.23" and active["more-infinite-research"] == "5.0.21012"
    and (active[M.fixture] == "0.1.0" or active[M.fixture] == "0.1.1"), "exact F210 tuple")
  M.require(game.speed == 1 and game.difficulty_settings.technology_price_multiplier == 1, "unmodified clock/price")
end

local function technology(value)
  M.require(value and value.valid ~= false, "native technology missing")
  return {name=value.name, level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, saved_progress=value.saved_progress, count=value.research_unit_count}
end

function M.capture()
  local out = {}
  for _, name in ipairs(M.forces) do
    local force = game.forces[name]
    M.require(force and force.valid ~= false, "force missing")
    local queue = {}
    for index, row in ipairs(force.research_queue or {}) do queue[index] = row.name end
    out[#out + 1] = {name=name, index=force.index, bonus=force.worker_robots_storage_bonus,
      current=force.current_research and force.current_research.name or false,
      progress=force.research_progress, queue=queue,
      main=technology(force.technologies[M.main]), sentinel=technology(force.technologies[M.sentinel]),
      private=technology(force.technologies[M.private])}
  end
  return out
end

function M.lab_witnesses()
  local out = {}
  for _, name in ipairs(M.forces) do
    local force, lab = game.forces[name], storage.labs[name]
    M.require(lab and lab.valid, "native lab missing")
    local input, modules = lab.get_inventory(defines.inventory.lab_input), lab.get_inventory(defines.inventory.lab_modules)
    M.require(input and modules, "native lab inventories missing")
    local packs = {}; for _, pack in ipairs(M.sciences) do packs[pack] = input.get_item_count(pack) end
    out[#out + 1] = {force=name, unit_number=lab.unit_number, name=lab.name,
      disabled=lab.disabled_by_script, status=lab.status,
      speed=lab.prototype.get_researching_speed("normal"), packs=packs, modules_empty=modules.is_empty(),
      force_speed=force.laboratory_speed_modifier, force_productivity=force.laboratory_productivity_bonus}
  end
  return out
end

function M.observe(stage)
  local native = M.capture()
  local saved = storage.last_tick
  local equal = saved and M.same(saved.native, native) or false
  -- This marker precedes the SAME strict equality refusal; no state is repaired.
  M.emit(stage, {schema=1, native_tick=game.tick, saved_lua=saved, native=native,
    equal_native_state=equal, active_mods=script.active_mods, game_speed=game.speed,
    labs=M.lab_witnesses(), setup=storage.setup, autosave_requested_tick=storage.autosave_requested_tick})
  M.closure()
  M.require(script.active_mods[M.fixture] == "0.1.1" and storage.setup
    and storage.setup.scripted_prerequisites and storage.setup.scripted_initial_partials,
    "target requires the original autosave")
  M.require(saved and saved.continuous_advances >= 16 and storage.autosave_requested_tick == M.save_tick,
    "serialized continuous-work witness missing")
  M.require(equal, "saved on_tick frame differs from native serialized work; no one-tick allowance")
  return true
end

return M

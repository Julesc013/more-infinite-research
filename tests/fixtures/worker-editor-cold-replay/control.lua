local ids = {"worker-robots-storage-4", "mir-worker-storage-default-4", "mir-worker-storage-head-4"}

local function observe()
  local level = script.level
  local map = game.get_surface("nauvis").map_gen_settings
  local result = {
    level = {mod_name = level.mod_name, level_name = level.level_name},
    width = map.width,
    height = map.height,
    editor_override = settings.global["ee-override-debug-world"].value,
    tick = game.tick,
    mods = {},
    forces = {}
  }
  for name, version in pairs(script.active_mods) do result.mods[name] = version end
  for _, force in pairs(game.forces) do
    local row = {
      name = force.name,
      cargo = force.worker_robots_storage_bonus,
      progress = force.research_progress,
      current = force.current_research and force.current_research.name or false,
      queue = {},
      technologies = {}
    }
    for index, technology in ipairs(force.research_queue or {}) do row.queue[index] = technology.name end
    for _, id in ipairs(ids) do
      local t, p = force.technologies[id], prototypes.technology[id]
      row.technologies[id] = t and p and {
        level = t.level,
        researched = t.researched,
        progress = t.saved_progress,
        enabled = t.enabled,
        visible = t.visible_when_disabled,
        prototype_enabled = p.enabled,
        prototype_visible = p.visible_when_disabled
      } or false
    end
    result.forces[#result.forces + 1] = row
  end
  table.sort(result.forces, function(a, b) return a.name < b.name end)
  return result
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function record(name, value)
  helpers.write_file(name .. ".json", helpers.table_to_json(value) .. "\n")
end

script.on_init(function()
  local before = observe()
  assert(before.tick == 0 and before.level.mod_name == "EditorExtensions"
    and before.level.level_name == "testing" and #before.forces == 3, "editor source scope")
  record("before-mir", before)
  storage.initial = before
end)

script.on_event(defines.events.on_tick, function()
  if script.test_arg == "cold" then
    local cold = observe()
    local saved = assert(storage.saved, "saved observation absent")
    assert(same(cold.level, saved.level) and same(cold.mods, saved.mods)
      and same(cold.forces, saved.forces), "editor cold load changed the force frame")
    record("cold", cold)
    script.finish_test(true)
    return
  end
  if storage.saved then return end

  local first = observe()
  record("first-update", first)
  local before = assert(storage.initial)
  assert(same(first.level, before.level) and same(first.mods, before.mods), "editor mod selection changed")
  for i, initial in ipairs(before.forces) do
    local current = assert(first.forces[i])
    assert(initial.name == current.name and initial.cargo == 5 and current.cargo == 4,
      "single cargo grant differs for " .. initial.name)
    local public, owner, debit = table.unpack(ids)
    local old = initial.technologies
    local new = current.technologies
    assert(old[public].level == 5 and old[owner].level == 5 and old[debit].level == 4,
      "duplicated grant frame missing")
    assert(new[public].level == 5 and not new[public].enabled and new[owner].level == 5
      and new[owner].enabled and new[debit].level == 5 and not new[debit].enabled,
      "first debit settlement differs")
    assert(initial.current == current.current and initial.progress == current.progress
      and same(initial.queue, current.queue), "research work changed")
    for _, id in ipairs(ids) do
      assert(old[id].progress == 0 and new[id].progress == 0, "worker paid progress present")
    end
  end
  storage.saved = first
  game.server_save("editor-testing")
end)

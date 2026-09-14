local technology_name = "recipe-prod-research_copper-1"
local setting_name = "ips-max-level-research_copper"
local storage_key = "mir42_v2_v3_cap_migration"
local fractional_progress = 0.42

local terminal_pending = false
local terminal_logged = false

local function fail(message)
  error("[mir42-v2-v3-cap-migration] " .. message)
end

local function quote(value)
  return "\"" .. tostring(value):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
end

local function bool(value)
  return value and "true" or "false"
end

local function selected_cap()
  local setting = settings.startup[setting_name]
  local value = setting and tonumber(setting.value) or nil
  if not value or value <= 0 then return 0 end
  return math.floor(value)
end

local function policy()
  local item = prototypes.mod_data and prototypes.mod_data[
    "more-infinite-research-maximum-level-policy"]
  return item and item.data or nil
end

local function policy_schema()
  local value = policy()
  return value and value.schema or nil
end

local function technology_for(force)
  local technology = force and force.technologies[technology_name]
  if not technology then fail("Copper technology is absent for " .. tostring(force and force.name)) end
  return technology
end

local function require_force(name)
  local force = game.forces[name]
  if not force then fail("force is absent " .. name) end
  return force
end

local function configure(force, level, enabled, visible_when_disabled)
  force.enable_all_prototypes()
  local technology = technology_for(force)
  technology.enabled = enabled
  technology.visible_when_disabled = visible_when_disabled
  technology.level = level
  return technology
end

local function queue_names(force)
  local names = {}
  for _, entry in ipairs(force.research_queue or {}) do
    names[#names + 1] = entry.name
  end
  return names
end

local function assert_research_continuity()
  local force = game.forces.player
  local technology = technology_for(force)
  if technology.level ~= 3 or technology.researched then
    fail("completed levels/current research level differ")
  end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("current research differs")
  end
  local queue = queue_names(force)
  if #queue ~= 1 or queue[1] ~= technology_name then
    fail("research queue differs")
  end
  if math.abs((force.research_progress or -1) - fractional_progress) > 0.0001 then
    fail("fractional research progress differs")
  end
end

local function assert_force(name, level, enabled, visible_when_disabled)
  local technology = technology_for(require_force(name))
  if technology.level ~= level or technology.enabled ~= enabled
      or technology.visible_when_disabled ~= visible_when_disabled then
    fail("force differs name=" .. name
      .. " level=" .. tostring(technology.level) .. "/" .. tostring(level)
      .. " enabled=" .. tostring(technology.enabled) .. "/" .. tostring(enabled)
      .. " visible=" .. tostring(technology.visible_when_disabled)
      .. "/" .. tostring(visible_when_disabled))
  end
end

local function state_json(stage, migration_outcome_observed, cap_zero_owner_only_restoration_observed)
  local research_force = game.forces.player
  local queue = queue_names(research_force)
  local rows = {}
  for _, name in ipairs({"v2-owned", "v2-foreign-disabled", "v3-owned"}) do
    local force = game.forces[name]
    if force then
      local technology = technology_for(force)
      rows[#rows + 1] = "{\"name\":" .. quote(name)
        .. ",\"index\":" .. tostring(force.index)
        .. ",\"level\":" .. tostring(technology.level)
        .. ",\"enabled\":" .. bool(technology.enabled)
        .. ",\"visible_when_disabled\":" .. bool(technology.visible_when_disabled) .. "}"
    end
  end
  return "{\"stage\":" .. quote(stage)
    .. ",\"policy_schema\":" .. tostring(policy_schema())
    .. ",\"cap\":" .. tostring(selected_cap())
    .. ",\"migration_outcome_observed\":" .. bool(migration_outcome_observed)
    .. ",\"cap_zero_owner_only_restoration_observed\":" .. bool(cap_zero_owner_only_restoration_observed)
    .. ",\"research_level\":" .. tostring(technology_for(research_force).level)
    .. ",\"current_research\":" .. quote(research_force.current_research and research_force.current_research.name or "")
    .. ",\"research_queue\":[" .. table.concat((function()
      local out = {}
      for _, name in ipairs(queue) do out[#out + 1] = quote(name) end
      return out
    end)(), ",") .. "]"
    .. ",\"fractional_progress\":" .. string.format("%.2f", research_force.research_progress or -1)
    .. ",\"forces\":[" .. table.concat(rows, ",") .. "]}"
end

local function log_state(stage, migration_outcome_observed, cap_zero_owner_only_restoration_observed)
  log("[mir42-v2-v3-cap-migration] STATE JSON "
    .. state_json(stage, migration_outcome_observed, cap_zero_owner_only_restoration_observed))
end

local function establish_research_state()
  local force = game.forces.player
  local technology = technology_for(force)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for expected_level = 1, 2 do
    if technology.level ~= expected_level or not force.add_research(technology)
        or not force.current_research or force.current_research.name ~= technology_name then
      fail("could not establish completed predecessor level " .. tostring(expected_level))
    end
    force.research_queue = nil
    force.cancel_current_research()
    technology.researched = true
  end
  if technology.level ~= 3 or not force.add_research(technology)
      or not force.current_research or force.current_research.name ~= technology_name then
    fail("could not establish level-three predecessor current research")
  end
  force.research_queue = {technology}
  force.research_progress = fractional_progress
end

local function assert_v3_migration_and_cap()
  assert_research_continuity()
  assert_force("v2-owned", 4, false, true)
  assert_force("v2-foreign-disabled", 4, false, true)
  local v3_owned = game.forces["v3-owned"] or game.create_force("v3-owned")
  configure(v3_owned, 4, true, false)
  v3_owned.reset_technology_effects()
  assert_force("v3-owned", 4, false, true)
end

local function assert_v3_relaxation()
  assert_research_continuity()
  assert_force("v2-owned", 4, true, false)
  assert_force("v2-foreign-disabled", 4, false, false)
  assert_force("v3-owned", 4, true, false)
end

local function save_successor(phase, stage, migration_outcome_observed, cap_zero_owner_only_restoration_observed, name)
  local state = storage[storage_key]
  state.phase = phase
  log_state(stage, migration_outcome_observed, cap_zero_owner_only_restoration_observed)
  game.server_save(name)
end

script.on_init(function()
  if policy_schema() ~= 2 or selected_cap() ~= 3 then
    fail("predecessor stage requires authentic V2 policy and cap=3")
  end
  if game.forces["v2-owned"] or game.forces["v2-foreign-disabled"] then
    fail("predecessor forces already exist")
  end
  establish_research_state()
  local owned = game.create_force("v2-owned")
  local foreign = game.create_force("v2-foreign-disabled")
  configure(owned, 4, true, false)
  configure(foreign, 4, false, false)
  owned.reset_technology_effects()
  foreign.reset_technology_effects()
  assert_force("v2-owned", 4, false, true)
  assert_force("v2-foreign-disabled", 4, false, true)
  assert_research_continuity()
  storage[storage_key] = {phase = "v2-seeded"}
  log_state("v2-seeded", false, false)
end)

script.on_configuration_changed(function()
  local state = storage[storage_key]
  if not state or policy_schema() ~= 3 then return end
  if state.phase == "v2-seeded" then
    if selected_cap() ~= 3 then fail("V3 cap stage requires cap=3") end
    assert_v3_migration_and_cap()
    state.phase = "v3-capped-pending-save"
  elseif state.phase == "v3-capped" then
    if selected_cap() ~= 0 then fail("V3 relaxation stage requires cap=0") end
    assert_v3_relaxation()
    state.phase = "v3-relaxed-pending-save"
  end
end)

script.on_load(function()
  local state = storage[storage_key]
  terminal_pending = state and state.phase == "v3-relaxed" or false
  terminal_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if not state then fail("fixture state is absent") end
  if state.phase == "v3-capped-pending-save" then
    assert_v3_migration_and_cap()
    save_successor("v3-capped", "v3-capped", true, false, "mir42-v2-v3-cap-migration-v3-capped")
  elseif state.phase == "v3-relaxed-pending-save" then
    assert_v3_relaxation()
    save_successor("v3-relaxed", "v3-relaxed", true, true, "mir42-v2-v3-cap-migration-v3-relaxed")
  elseif terminal_pending and state.phase == "v3-relaxed" and not terminal_logged then
    assert_v3_relaxation()
    log_state("terminal", true, true)
    terminal_logged = true
  end
end)

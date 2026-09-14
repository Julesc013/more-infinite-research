local technology_name = "recipe-prod-research_copper-1"
local setting_name = "ips-max-level-research_copper"
local blocker_name = "late-mir42-cap-binding-blocker"
local storage_key = "mir42_cap_ownership_multiforce"

local terminal_pending = false
local terminal_logged = false

local function fail(message)
  error("[mir42-cap-ownership-multiforce] " .. message)
end

local function selected_cap()
  local setting = settings.startup[setting_name]
  local value = setting and tonumber(setting.value) or nil
  if not value or value <= 0 then return 0 end
  return math.floor(value)
end

local function blocker_active()
  return script.active_mods[blocker_name] ~= nil
end

local function technology_for(force)
  local technology = force and force.technologies[technology_name]
  if not technology then fail("Copper technology is absent for force " .. tostring(force and force.name)) end
  return technology
end

local function configure_force(force, level, enabled, visible_when_disabled)
  force.enable_all_prototypes()
  local technology = technology_for(force)
  technology.level = level
  technology.enabled = enabled
  technology.visible_when_disabled = visible_when_disabled
  return technology
end

local function force_state(force_name)
  local force = game.forces[force_name]
  if not force then fail("named force is absent " .. force_name) end
  local technology = technology_for(force)
  return {
    name = force.name,
    index = force.index,
    level = technology.level,
    enabled = technology.enabled,
    visible_when_disabled = technology.visible_when_disabled
  }
end

local function quote(value)
  return "\"" .. tostring(value):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
end

local function bool(value)
  return value and "true" or "false"
end

local function state_json(stage)
  local state = storage[storage_key]
  local rows = {}
  for _, name in ipairs(state.force_names) do
    local row = force_state(name)
    rows[#rows + 1] = "{\"name\":" .. quote(row.name)
      .. ",\"index\":" .. tostring(row.index)
      .. ",\"level\":" .. tostring(row.level)
      .. ",\"enabled\":" .. bool(row.enabled)
      .. ",\"visible_when_disabled\":" .. bool(row.visible_when_disabled) .. "}"
  end
  return "{\"stage\":" .. quote(stage)
    .. ",\"cap\":" .. tostring(selected_cap())
    .. ",\"blocker\":" .. bool(blocker_active())
    .. ",\"configuration_changed_events\":" .. tostring(state.configuration_changed_events)
    .. ",\"forces\":[" .. table.concat(rows, ",") .. "]}"
end

local function log_state(stage)
  log("[mir42-cap-ownership-multiforce] STATE JSON " .. state_json(stage))
end

local function expect(name, level, enabled, visible_when_disabled)
  local row = force_state(name)
  if row.level ~= level or row.enabled ~= enabled
      or row.visible_when_disabled ~= visible_when_disabled then
    fail("force state differs name=" .. name
      .. " level=" .. tostring(row.level) .. "/" .. tostring(level)
      .. " enabled=" .. tostring(row.enabled) .. "/" .. tostring(enabled)
      .. " visible=" .. tostring(row.visible_when_disabled)
      .. "/" .. tostring(visible_when_disabled))
  end
end

local function expect_seed()
  expect("owned", 4, true, false)
  expect("foreign-disabled", 4, false, false)
  expect("below-cap", 2, true, false)
  expect("event-probe", 4, true, false)
end

local function expect_capped_base()
  expect("owned", 4, false, true)
  expect("foreign-disabled", 4, false, true)
  expect("below-cap", 2, true, false)
  expect("event-probe", 4, false, true)
end

local function expect_event_probe()
  expect_capped_base()
  expect("new-force", 4, true, false)
end

local function expect_removed()
  expect("owned", 4, true, false)
  expect("foreign-disabled", 4, false, false)
  expect("below-cap", 2, true, false)
  expect("event-probe", 4, true, false)
  expect("new-force", 4, true, false)
end

local function save_successor(phase, observation_stage, name)
  local state = storage[storage_key]
  state.phase = phase
  log_state(observation_stage)
  game.server_save(name)
end

local function advance_seed_to_capped()
  local state = storage[storage_key]
  if selected_cap() ~= 3 or blocker_active() then return end
  if state.configuration_changed_events < 1 then
    fail("Capped stage did not observe configuration change")
  end
  expect_capped_base()
  log_state("capped")

  local event_force = game.forces["event-probe"]
  configure_force(event_force, 4, true, false)
  local new_force = game.create_force("new-force")
  -- on_force_created has returned before the force is deliberately seeded
  -- above the cap. The following reset must therefore touch event-probe only.
  configure_force(new_force, 4, true, false)
  if not event_force.reset_technology_effects then
    fail("event-probe does not expose reset_technology_effects")
  end
  event_force.reset_technology_effects()

  state.force_names[#state.force_names + 1] = "new-force"
  expect_event_probe()
  save_successor("capped", "event-probe", "mir42-cap-ownership-multiforce-capped")
end

local function advance_capped_to_blocked()
  local state = storage[storage_key]
  if selected_cap() ~= 3 or not blocker_active() then return end
  if state.configuration_changed_events < 2 then
    fail("Blocked stage did not observe configuration change")
  end
  -- A late finalizer conflict must leave both MIR-owned and unowned force
  -- state untouched; it must neither retry capping nor restore eligibility.
  expect_event_probe()
  save_successor("blocked", "blocked", "mir42-cap-ownership-multiforce-blocked")
end

local function advance_blocked_to_removal()
  local state = storage[storage_key]
  if selected_cap() ~= 0 or blocker_active() then return end
  if state.configuration_changed_events < 3 then
    fail("Removal stage did not observe configuration change")
  end
  expect_removed()
  save_successor("removal", "removal", "mir42-cap-ownership-multiforce-removal")
end

script.on_init(function()
  if selected_cap() ~= 0 or blocker_active() then
    fail("Seed requires an infinite cap and no late blocker")
  end
  local names = {"owned", "foreign-disabled", "below-cap", "event-probe"}
  for _, name in ipairs(names) do
    if game.forces[name] then fail("seed force already exists " .. name) end
    game.create_force(name)
  end
  configure_force(game.forces["owned"], 4, true, false)
  configure_force(game.forces["foreign-disabled"], 4, false, false)
  configure_force(game.forces["below-cap"], 2, true, false)
  configure_force(game.forces["event-probe"], 4, true, false)
  storage[storage_key] = {
    phase = "seed",
    configuration_changed_events = 0,
    force_names = names
  }
  expect_seed()
  log_state("seed")
end)

script.on_configuration_changed(function()
  local state = storage[storage_key]
  if not state then return end
  state.configuration_changed_events = state.configuration_changed_events + 1
  log("[mir42-cap-ownership-multiforce] CONFIGURATION-CHANGED count="
    .. tostring(state.configuration_changed_events)
    .. " phase=" .. tostring(state.phase)
    .. " cap=" .. tostring(selected_cap())
    .. " blocker=" .. bool(blocker_active()))
end)

script.on_load(function()
  local state = storage[storage_key]
  terminal_pending = state ~= nil and state.phase == "removal"
  terminal_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if not state then fail("fixture state is absent") end

  if terminal_pending then
    if selected_cap() ~= 0 or blocker_active() then
      fail("terminal reload no longer represents the removal candidate")
    end
    if not terminal_logged then
      expect_removed()
      log_state("terminal")
      terminal_logged = true
    end
    return
  end

  if state.phase == "seed" then
    advance_seed_to_capped()
  elseif state.phase == "capped" then
    advance_capped_to_blocked()
  elseif state.phase == "blocked" then
    advance_blocked_to_removal()
  elseif state.phase ~= "removal" then
    fail("unknown fixture phase " .. tostring(state.phase))
  end
end)

local technology_name = "recipe-prod-research_copper-1"
local setting_name = "ips-max-level-research_copper"
local storage_key = "mir42_f200_settings_cap_transition"

local function fail(message)
  error("[mir42-f200-settings-cap-transition] " .. message)
end

local function selected_cap()
  local setting = settings.startup[setting_name]
  local value = setting and tonumber(setting.value) or nil
  if value == 0 then return 0 end
  if type(value) ~= "number" or value ~= value or value == math.huge
      or value == -math.huge or value < 1 or value ~= math.floor(value) then
    fail("fixture startup cap is not a finite non-negative integer")
  end
  return value
end

local function technology_for(force)
  local technology = force and force.technologies[technology_name]
  if not technology then fail("Copper technology is absent for " .. tostring(force and force.name)) end
  return technology
end

local function configure(force, enabled)
  force.enable_all_prototypes()
  local technology = technology_for(force)
  -- Advancing an infinite technology can restore Factorio's default
  -- enablement. Apply the intended seed state after the level write so the
  -- foreign-disabled force is genuinely disabled before MIR owns anything.
  technology.level = 4
  technology.visible_when_disabled = false
  technology.enabled = enabled
end

local function expect(force_name, enabled, visible)
  local force = game.forces[force_name]
  local technology = technology_for(force)
  if technology.level ~= 4 or technology.enabled ~= enabled
      or technology.visible_when_disabled ~= visible then
    fail("state differs for " .. force_name
      .. " level=" .. tostring(technology.level)
      .. " enabled=" .. tostring(technology.enabled)
      .. " visible=" .. tostring(technology.visible_when_disabled))
  end
end

local function bool(value) return value and "true" or "false" end

local function state_json(stage)
  local owned = technology_for(game.forces["owned"])
  local foreign = technology_for(game.forces["foreign-disabled"])
  local state = storage[storage_key]
  return "{\"stage\":\"" .. stage .. "\""
    .. ",\"cap\":" .. tostring(selected_cap())
    .. ",\"configuration_changed_events\":" .. tostring(state.configuration_changed_events)
    .. ",\"owned\":{\"level\":" .. tostring(owned.level)
    .. ",\"enabled\":" .. bool(owned.enabled)
    .. ",\"visible_when_disabled\":" .. bool(owned.visible_when_disabled) .. "}"
    .. ",\"foreign_disabled\":{\"level\":" .. tostring(foreign.level)
    .. ",\"enabled\":" .. bool(foreign.enabled)
    .. ",\"visible_when_disabled\":" .. bool(foreign.visible_when_disabled) .. "}}"
end

local function save(stage, save_name)
  log("[mir42-f200-settings-cap-transition] STATE JSON " .. state_json(stage))
  game.server_save(save_name)
end

script.on_init(function()
  if selected_cap() ~= 0 then fail("seed requires an infinite cap") end
  for _, name in ipairs({"owned", "foreign-disabled"}) do
    if game.forces[name] then fail("seed force already exists " .. name) end
    game.create_force(name)
  end
  configure(game.forces["owned"], true)
  configure(game.forces["foreign-disabled"], false)
  storage[storage_key] = {phase = "seed", configuration_changed_events = 0}
  expect("owned", true, false)
  expect("foreign-disabled", false, false)
  log("[mir42-f200-settings-cap-transition] STATE JSON " .. state_json("seed"))
end)

script.on_configuration_changed(function()
  local state = storage[storage_key]
  if state then state.configuration_changed_events = state.configuration_changed_events + 1 end
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if not state then fail("fixture state is absent") end
  if state.phase == "seed" and selected_cap() == 3 then
    if state.configuration_changed_events < 1 then fail("finite stage did not observe configuration change") end
    expect("owned", false, true)
    expect("foreign-disabled", false, true)
    state.phase = "capped"
    save("capped", "mir42-f200-settings-cap-transition-capped")
  elseif state.phase == "capped" and selected_cap() == 0 then
    if state.configuration_changed_events < 2 then fail("cap-zero stage did not observe configuration change") end
    -- The first row was disabled by MIR and is restored. The second row was
    -- already foreign-disabled, so settings-derived V3 ownership must restore
    -- only MIR's visibility write and leave its enablement disabled.
    expect("owned", true, false)
    expect("foreign-disabled", false, false)
    state.phase = "relaxed"
    save("relaxed", "mir42-f200-settings-cap-transition-relaxed")
  end
end)

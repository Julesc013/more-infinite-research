local predecessor_version = "__MIR_UPGRADE_FROM_VERSION__"
local candidate_version = "__MIR_UPGRADE_TO_VERSION__"
local factorio_line = "__MIR_FACTORIO_LINE__"
local infinite_technology_name = "__MIR_INFINITE_TECHNOLOGY__"
local governed_save_name = "__MIR_UPGRADE_SAVE_NAME__"
local finite_technology_name = "research-speed-4"
local expected_progress = 0.37
local epsilon = 0.000001
local loaded_candidate_state = false

local function fail(message)
  error("MIR historical terminal continuity validation failed: " .. message)
end

local function write(message)
  log("[mir-fixture] " .. message)
end

local function force()
  local value = game.forces.player
  if not value then fail("missing player force") end
  return value
end

local function technology(name)
  local value = force().technologies[name]
  if not value then fail("missing required technology " .. name) end
  return value
end

local function seed_source_state()
  local research = technology(finite_technology_name)
  for level = 1, 3 do
    technology("research-speed-" .. level).researched = true
  end
  research.researched = false

  local infinite = nil
  if infinite_technology_name ~= "" then
    local infinite_technology = technology(infinite_technology_name)
    local level_before = infinite_technology.level
    local bonus_before = force().mining_drill_productivity_bonus
    if type(level_before) ~= "number" or type(bonus_before) ~= "number" then
      fail("missing infinite research state on " .. factorio_line)
    end
    infinite_technology.researched = true
    local observed_level = infinite_technology.level
    local observed_bonus = force().mining_drill_productivity_bonus
    if type(observed_level) ~= "number" or observed_level <= level_before or type(observed_bonus) ~= "number" or observed_bonus <= bonus_before then
      fail("infinite research did not advance on " .. factorio_line)
    end
    infinite = {
      technology = infinite_technology_name,
      level = observed_level,
      bonus = observed_bonus
    }
  end

  -- Set the unfinished finite current research last: completing the optional
  -- infinite level must not replace this source-state observation.  0.17 exposes
  -- current_research read-only, so put the lone technology into its queue first.
  if factorio_line == "0.17" then
    force().research_queue_enabled = true
    force().research_queue = { research.name }
  else
    force().current_research = research.name
  end
  local current = force().current_research
  if not current or current.name ~= research.name then
    fail("could not select current finite research on " .. factorio_line)
  end
  force().research_progress = expected_progress

  global.mir42_historical_terminal = {
    source_version = predecessor_version,
    candidate_version = candidate_version,
    finite = {
      technology = finite_technology_name,
      completed_prerequisite_levels = 3,
      current_level = 4,
      progress = expected_progress
    },
    infinite = infinite
  }
end

local function assert_retained_state(phase)
  local state = global.mir42_historical_terminal
  if not state or state.source_version ~= predecessor_version or state.candidate_version ~= candidate_version then
    fail(phase .. " lost predecessor/candidate state")
  end
  if not state.finite or state.finite.technology ~= finite_technology_name or state.finite.completed_prerequisite_levels ~= 3 or state.finite.current_level ~= 4 then
    fail(phase .. " lost finite research level state")
  end
  for level = 1, state.finite.completed_prerequisite_levels do
    if not technology("research-speed-" .. level).researched then fail(phase .. " lost researched prerequisite level " .. level) end
  end

  local research = technology(state.finite.technology)
  if research.researched then fail(phase .. " unexpectedly completed finite research level 4") end
  local current = force().current_research
  if not current or current.name ~= state.finite.technology then fail(phase .. " lost current research") end
  if math.abs((force().research_progress or 0) - state.finite.progress) > epsilon then
    fail(phase .. " changed fractional research progress")
  end

  if infinite_technology_name == "" then
    if state.infinite ~= nil then fail(phase .. " recorded unsupported infinite state") end
  else
    if not state.infinite or state.infinite.technology ~= infinite_technology_name then
      fail(phase .. " lost infinite technology state")
    end
    local infinite_technology = technology(infinite_technology_name)
    if infinite_technology.level ~= state.infinite.level then
      fail(phase .. " changed infinite research level")
    end
    if math.abs(force().mining_drill_productivity_bonus - state.infinite.bonus) > epsilon then
      fail(phase .. " changed infinite mining productivity bonus")
    end
  end
end

script.on_init(function()
  seed_source_state()
  write(predecessor_version .. " upgrade source proof complete archetype=base-default")
end)

script.on_configuration_changed(function()
  assert_retained_state("configuration change")
  global.mir42_historical_terminal.candidate_verified = true
  write(predecessor_version .. " to " .. candidate_version .. " upgrade proof complete archetype=base-default")
end)

-- on_load only observes saved state. The first later tick performs the normal
-- writable verification and emits the reload receipt marker.
script.on_load(function()
  local state = global.mir42_historical_terminal
  loaded_candidate_state = state and state.candidate_verified and state.server_save_requested or false
end)

script.on_event(defines.events.on_tick, function()
  local state = global.mir42_historical_terminal
  if loaded_candidate_state then
    assert_retained_state("reload")
    write(candidate_version .. " upgraded save reload proof complete archetype=base-default")
    loaded_candidate_state = false
  elseif state and state.candidate_verified and not state.server_save_requested then
    assert_retained_state("candidate server")
    state.server_save_requested = true
    game.server_save(governed_save_name)
  end
end)
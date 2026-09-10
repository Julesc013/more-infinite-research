local early_technology_name = "recipe-prod-research_advanced_circuit-1"
local late_technology_name = "recipe-prod-research_belts-1"
local expected_progress = 0.42
local epsilon = 0.000001

local expected_early_science = {
  "automation-science-pack",
  "chemical-science-pack",
  "electromagnetic-science-pack",
  "logistic-science-pack",
  "production-science-pack"
}

local expected_late_science = {
  "production-science-pack",
  "space-science-pack"
}

local function fail(message)
  error("MIR A04 K2 progressed-save validation failed: " .. message)
end

local function science_names(technology)
  local names = {}
  for _, ingredient in pairs((technology and technology.prototype.research_unit_ingredients) or {}) do
    names[#names + 1] = ingredient.name
  end
  table.sort(names)
  return names
end

local function assert_sequence(actual, expected, label)
  if #actual ~= #expected then fail(label .. " science count differs") end
  for index, name in ipairs(expected) do
    if actual[index] ~= name then
      fail(label .. " science differs at " .. index .. ": " .. tostring(actual[index]))
    end
  end
end

local function assert_exact_environment()
  if script.active_mods.Krastorio2 ~= "2.1.2" then fail("Krastorio2 version differs") end
  if script.active_mods["Krastorio2-spaced-out"] ~= "2.0.13" then fail("K2SO version differs") end
  if script.active_mods["more-infinite-research"] ~= "4.2.21000" then fail("MIR candidate version differs") end
end

local function assert_progressed_state(stage)
  assert_exact_environment()
  local force = game.forces.player
  local early = force.technologies[early_technology_name]
  local late = force.technologies[late_technology_name]
  if not early or not late then fail("representative MIR technology is absent") end
  assert_sequence(science_names(early), expected_early_science, "early")
  assert_sequence(science_names(late), expected_late_science, "late")
  if not force.current_research or force.current_research.name ~= early_technology_name then
    fail("current research differs after " .. stage)
  end
  if math.abs((force.research_progress or -1) - expected_progress) > epsilon then
    fail("fractional research progress differs after " .. stage)
  end
  local queue = force.research_queue or {}
  if #queue ~= 1 or queue[1].name ~= early_technology_name then fail("research queue differs after " .. stage) end
  if not storage.mir_a04_k2_science or storage.mir_a04_k2_science.progress ~= expected_progress then
    fail("persisted fixture state differs after " .. stage)
  end
  log("[MIR4_A04_K2_PROGRESS] stage=" .. stage .. " technology=" .. early_technology_name .. " progress=0.42 early=automation-science-pack,chemical-science-pack,electromagnetic-science-pack,logistic-science-pack,production-science-pack late=production-science-pack,space-science-pack")
end

script.on_init(function()
  assert_exact_environment()
  local force = game.forces.player
  force.enable_all_prototypes()
  local technology = force.technologies[early_technology_name]
  if not technology then fail("early technology is absent during initialization") end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  if force.current_research then force.cancel_current_research() end
  technology.enabled = true
  technology.researched = false
  if not force.add_research(technology) then fail("could not queue early technology") end
  force.research_queue = {technology}
  force.research_progress = expected_progress
  storage.mir_a04_k2_science = {technology = early_technology_name, progress = expected_progress}
  assert_progressed_state("initial")
end)

local pending_reload = false
script.on_load(function() pending_reload = true end)
script.on_nth_tick(1, function()
  if not pending_reload then return end
  pending_reload = false
  assert_progressed_state("reload")
end)
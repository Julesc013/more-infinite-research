-- Exact-scenario diagnostic only. This fixture reads the packaged F200 graph
-- after MIR and its Bob/Angel roots have run; it neither writes prototypes nor
-- enters the player-facing MIR API surface.
local science = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local reachability = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.pack_production_reachability")
local compiler_context = require(
  "__more-infinite-research__.prototypes.mir.pipeline.compiler_context")

local function fail(message)
  error("MIR F200 science researchability diagnostic assertion failed: " .. message)
end

local subjects = {
  {
    stream = "research_cannon_shooting_speed",
    generated_technology = "recipe-prod-research_cannon_shooting_speed-1",
    prerequisite = "weapon-shooting-speed-5"
  },
  {
    stream = "research_electric_shooting_speed",
    generated_technology = "recipe-prod-research_electric_shooting_speed-1",
    prerequisite = "discharge-defense-equipment"
  },
  {
    stream = "research_flamethrower_shooting_speed",
    generated_technology = "recipe-prod-research_flamethrower_shooting_speed-1",
    prerequisite = "flamethrower"
  },
  {
    stream = "research_rocket_shooting_speed",
    generated_technology = "recipe-prod-research_rocket_shooting_speed-1",
    prerequisite = "rocketry"
  }
}

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
end

-- Return the real technology in this prerequisite closure which consumes the
-- queried pack. The fixture derives this only from Factorio's final prototype
-- graph; no MIR planner result is used to justify the assertion.
local function prerequisite_chain_logistic_consumer(root_name)
  local visiting = {}
  local function visit(technology_name)
    if visiting[technology_name] then return nil end
    visiting[technology_name] = true
    local technology = data.raw.technology[technology_name]
    if not technology then return nil end
    for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
      if ingredient_name(ingredient) == "logistic-science-pack" then return technology_name end
    end
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      local consumer = visit(prerequisite)
      if consumer then return consumer end
    end
    return nil
  end
  return visit(root_name)
end

compiler_context.with_active(compiler_context.new({execution_mode = "SAFE"}), function()
  -- Register only the private traversal services on the fixture's short-lived
  -- parent context. pack_production_rejection_projection itself creates a
  -- second fresh context for every observation, so no cache or telemetry can
  -- escape into the normal packaged compilation context.
  science.ensure_services()
  -- The bounded observation may borrow only an already-materialized immutable
  -- recipe snapshot from this short-lived parent. Build that canonical parent
  -- snapshot here, before any projection, rather than allowing the child
  -- observation to construct recipe facts without an observer.
  local canonical_recipe_facts = require(
    "__more-infinite-research__.prototypes.mir.index.recipe_facts")
  local parent_recipe_index = canonical_recipe_facts.index_view()
  if type(parent_recipe_index) ~= "table" then
    fail("canonical parent recipe index did not initialize")
  end
  for index, subject in ipairs(subjects) do
    local generated = data.raw.technology[subject.generated_technology]
    if not generated then
      fail(subject.stream .. " is missing MIR generated technology " .. subject.generated_technology)
    end
    if not contains(generated.prerequisites, subject.prerequisite) then
      fail(subject.stream .. " generated technology is not bound to " .. subject.prerequisite)
    end
    if not data.raw.technology[subject.prerequisite] then
      fail(subject.stream .. " is missing expected prerequisite technology " .. subject.prerequisite)
    end
    local logistic_consumer = prerequisite_chain_logistic_consumer(subject.prerequisite)
    if not logistic_consumer then
      fail(subject.stream .. " prerequisite chain does not consume logistic-science-pack")
    end
    local projection = reachability.pack_production_rejection_projection(
      "logistic-science-pack",
      {
        limits = {candidates = 16, nodes = 128, depth = 32, bytes = 32768},
        subject = {
          stream = subject.stream,
          generated_technology = subject.generated_technology,
          prerequisite = subject.prerequisite,
          logistic_consumer = logistic_consumer
        }
      }
    )
    if projection and projection.status == "indeterminate" then
      fail(subject.stream .. " logistic-science observation exhausted its diagnostic work budget")
    end
    if not projection or projection.status ~= "unreachable"
      or projection.pack_name ~= "logistic-science-pack" or #projection.candidates == 0
      or not projection.subject or projection.subject.stream ~= subject.stream
      or projection.subject.prerequisite ~= subject.prerequisite
      or projection.subject.logistic_consumer ~= logistic_consumer then
      fail(subject.stream .. " did not retain a bounded unreachable logistic-science projection")
    end
    local first = projection.first_failure or {}
    log("[mir-fixture-assert-f200-science-researchability-diagnostic] projection=" .. index
      .. " stream=" .. subject.stream
      .. " generated=" .. subject.generated_technology
      .. " prerequisite=" .. subject.prerequisite
      .. " logistic_consumer=" .. logistic_consumer
      .. " pack=logistic-science-pack"
      .. " status=" .. projection.status
      .. " candidates=" .. tostring(#projection.candidates) .. "/" .. tostring(projection.candidate_count)
      .. " first_kind=" .. tostring(first.kind)
      .. " first_reason=" .. tostring(first.reason)
      .. " truncated=" .. table.concat(projection.truncation.truncated or {}, "+"))
  end
end)

log("[mir-fixture-assert-f200-science-researchability-diagnostic] PASS projections=4"
  .. " player-mutation=false prototype-write=false")

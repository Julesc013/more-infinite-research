local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local researchability_index = require("prototypes.mir.graph.researchability_index")

local M = {}

local function pack_production_status(...)
  local service = compiler_context.current():service("science.pack_production_status")
  if not service then error("MIR science pack-production service is not registered in CompilerContext.", 2) end
  return service(...)
end

local function independent_pack_acquisition_witness(...)
  local service = compiler_context.current():service("science.independent_pack_acquisition_witness")
  if not service then error("MIR independent science-pack acquisition service is not registered in CompilerContext.", 2) end
  return service(...)
end

local function graph_index()
  return compiler_context.current():state_view("technology_researchability_index", researchability_index.build)
end

local function enabled_and_reachable(tech_name)
  local technology = data_raw.technology(tech_name)
  if not technology or technology.enabled == false then return false end
  return not graph_index().structural_failures[tech_name]
end

-- A bounded rejection projection supplies this observer from a short-lived
-- CompilerContext. Normal admission has none, so exhausting the diagnostic
-- budget cannot alter production reachability or telemetry.
local function diagnostic_visit(context, depth)
  local observer = context and context.diagnostic_observer
  if not observer then return true end
  if type(observer.is_stopped) == "function" and observer:is_stopped() then return false end
  if type(observer.reserve_visit) == "function" then
    return observer:reserve_visit(depth or context.diagnostic_depth or 0)
  end
  return true
end

-- The normal graph index is deliberately comprehensive and cache-backed. A
-- rejection projection must not build that unrestricted index before applying
-- its own cap, so its short-lived context walks only the named prerequisite
-- closure and reserves work before each node. This helper is diagnostic-only;
-- normal admission continues to use the established indexed evaluator below.
local function bounded_prerequisite_closure(tech_name, context)
  local seen, active, names = {}, {}, {}
  local function visit(name, depth)
    if not diagnostic_visit(context, depth) then return "diagnostic-budget-exhausted" end
    if active[name] then return "technology-cycle" end
    if seen[name] then return nil end
    local technology = data_raw.technology(name)
    if not technology then return "missing" end
    if technology.enabled == false then return "disabled" end
    seen[name], active[name] = true, true
    table.insert(names, name)
    local prerequisites = {}
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if not diagnostic_visit(context, depth + 1) then
        active[name] = nil
        return "diagnostic-budget-exhausted"
      end
      table.insert(prerequisites, prerequisite)
    end
    table.sort(prerequisites)
    for _, prerequisite in ipairs(prerequisites) do
      local rejection = visit(prerequisite, depth + 1)
      if rejection then
        active[name] = nil
        return rejection
      end
    end
    active[name] = nil
    return nil
  end
  local rejection = visit(tech_name, context.diagnostic_depth or 0)
  table.sort(names)
  return rejection, names
end

local function research_mechanism_reason(technology, technology_name, context)
  if technology.research_trigger then return nil end
  local unit = technology.unit
  local ingredients = unit and unit.ingredients or nil
  if not unit or not ingredients or #ingredients == 0 then return "missing-research-mechanism" end
  if unit.count == nil and unit.count_formula == nil then return "missing-research-count" end
  if not lab_compatibility.valid_research_ingredients(ingredients, context.diagnostic_observer) then
    return "no-accepting-lab"
  end

  local unlock_recipe = context.unlock_recipe_name
    and data_raw.prototype("recipe", context.unlock_recipe_name) or nil
  for _, ingredient in ipairs(ingredients) do
    if not diagnostic_visit(context, context.diagnostic_depth or 0) then
      return "diagnostic-budget-exhausted"
    end
    local pack_name = lab_compatibility.ingredient_name(ingredient)
    if pack_name then
      if not pack_registry.science_pack_exists(pack_name, context.diagnostic_observer) then
        return "unrecognized-science-" .. pack_name
      end
      local independently_acquired = false
      if unlock_recipe and recipe_facts.recipe_outputs_item(
        unlock_recipe,
        pack_name,
        context.diagnostic_observer
      ) then
        local witness = independent_pack_acquisition_witness(
          pack_name,
          technology_name,
          context.visiting_packs or {},
          context.visiting_technologies or {},
          context.diagnostic_observer
        )
        if not witness then return "science-self-lock-" .. pack_name end
        independently_acquired = true
      end
      if context.diagnostic_observer and type(context.diagnostic_observer.is_stopped) == "function"
        and context.diagnostic_observer:is_stopped() then
        return "diagnostic-budget-exhausted"
      end
      -- The active route deliberately marks its output pack as visiting.
      -- Once the narrow witness above has proved an independent acquisition
      -- route, asking the generic traversal status again would only rediscover
      -- that in-progress marker and falsely reject the same technology.
      if not independently_acquired
        and pack_production_status(
          pack_name,
          context.visiting_packs or {},
          context.visiting_technologies or {},
          context.diagnostic_observer
        ) == "unreachable" then
        return "unreachable-science-" .. pack_name
      end
    end
  end
  return nil
end

local function reason(tech_name, context)
  context = context or {}
  if not diagnostic_visit(context) then return "diagnostic-budget-exhausted" end
  local technology = data_raw.technology(tech_name)
  if not technology then return "missing" end
  if technology.enabled == false then return "disabled" end

  local visiting_technologies = context.visiting_technologies or {}
  if visiting_technologies[tech_name] then return "technology-cycle" end
  visiting_technologies[tech_name] = true

  if context.diagnostic_observer then
    local structural_rejection, candidates = bounded_prerequisite_closure(tech_name, context)
    if structural_rejection then
      visiting_technologies[tech_name] = nil
      return structural_rejection == "diagnostic-budget-exhausted"
        and structural_rejection or "unreachable-prerequisite"
    end
    -- Do not observe normal compiler telemetry here. The projection is an
    -- exact-test surface and must be query-local even in its own accounting.
    for _, candidate_name in ipairs(candidates) do
      if not diagnostic_visit(context) then
        visiting_technologies[tech_name] = nil
        return "diagnostic-budget-exhausted"
      end
      local candidate = data_raw.technology(candidate_name)
      local rejection = research_mechanism_reason(candidate, candidate_name, {
        visiting_packs = context.visiting_packs,
        visiting_technologies = visiting_technologies,
        unlock_recipe_name = context.unlock_recipe_name,
        diagnostic_observer = context.diagnostic_observer,
        diagnostic_depth = context.diagnostic_depth
      })
      if rejection then
        visiting_technologies[tech_name] = nil
        if candidate_name == tech_name then return rejection end
        return "prerequisite-" .. candidate_name .. "-" .. rejection
      end
    end
    visiting_technologies[tech_name] = nil
    return nil
  end

  local index = graph_index()
  local failure = index.structural_failures[tech_name]
  if failure then
    visiting_technologies[tech_name] = nil
    return "unreachable-prerequisite"
  end

  local candidates = researchability_index.reachable_names(index, tech_name)
  telemetry.observe_max("technology_prerequisite_closure_max", #candidates)
  telemetry.count("technology_graph_index_queries", 1)
  for _, candidate_name in ipairs(candidates) do
    if not diagnostic_visit(context) then
      visiting_technologies[tech_name] = nil
      return "diagnostic-budget-exhausted"
    end
    local candidate = data_raw.technology(candidate_name)
    local rejection = research_mechanism_reason(candidate, candidate_name, {
      visiting_packs = context.visiting_packs,
      visiting_technologies = visiting_technologies,
      unlock_recipe_name = context.unlock_recipe_name,
      diagnostic_observer = context.diagnostic_observer,
      diagnostic_depth = context.diagnostic_depth
    })
    if rejection then
      visiting_technologies[tech_name] = nil
      if candidate_name == tech_name then return rejection end
      return "prerequisite-" .. candidate_name .. "-" .. rejection
    end
  end
  visiting_technologies[tech_name] = nil
  return nil
end

function M.reason_with_context(tech_name, context)
  return reason(tech_name, context)
end

function M.technology_researchability_reason(tech_name)
  return reason(tech_name, {visiting_packs = {}, visiting_technologies = {}})
end

function M.technology_is_researchable(tech_name)
  return M.technology_researchability_reason(tech_name) == nil
end

function M.technology_is_enabled_and_reachable(tech_name)
  return enabled_and_reachable(tech_name)
end

return M

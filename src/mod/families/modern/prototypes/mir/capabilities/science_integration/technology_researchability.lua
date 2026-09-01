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

local function graph_index()
  return compiler_context.current():state_view("technology_researchability_index", researchability_index.build)
end

local function enabled_and_reachable(tech_name)
  local technology = data_raw.technology(tech_name)
  if not technology or technology.enabled == false then return false end
  return not graph_index().structural_failures[tech_name]
end

local function research_mechanism_reason(technology, context)
  if technology.research_trigger then return nil end
  local unit = technology.unit
  local ingredients = unit and unit.ingredients or nil
  if not unit or not ingredients or #ingredients == 0 then return "missing-research-mechanism" end
  if unit.count == nil and unit.count_formula == nil then return "missing-research-count" end
  if not lab_compatibility.valid_research_ingredients(ingredients) then return "no-accepting-lab" end

  local unlock_recipe = context.unlock_recipe_name
    and data_raw.prototype("recipe", context.unlock_recipe_name) or nil
  for _, ingredient in ipairs(ingredients) do
    local pack_name = lab_compatibility.ingredient_name(ingredient)
    if pack_name then
      if not pack_registry.science_pack_exists(pack_name) then
        return "unrecognized-science-" .. pack_name
      end
      if unlock_recipe and recipe_facts.recipe_outputs_item(unlock_recipe, pack_name) then
        return "science-self-lock-" .. pack_name
      end
      if pack_production_status(pack_name, context.visiting_packs or {}) == "unreachable" then
        return "unreachable-science-" .. pack_name
      end
    end
  end
  return nil
end

local function reason(tech_name, context)
  context = context or {}
  local technology = data_raw.technology(tech_name)
  if not technology then return "missing" end
  if technology.enabled == false then return "disabled" end

  local visiting_technologies = context.visiting_technologies or {}
  if visiting_technologies[tech_name] then return "technology-cycle" end
  visiting_technologies[tech_name] = true

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
    local candidate = data_raw.technology(candidate_name)
    local rejection = research_mechanism_reason(candidate, {
      visiting_packs = context.visiting_packs,
      visiting_technologies = visiting_technologies,
      unlock_recipe_name = context.unlock_recipe_name
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

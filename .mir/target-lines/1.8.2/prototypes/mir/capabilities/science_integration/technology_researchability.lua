local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")

local M = {}
local pack_production_status = nil
local technology_reachability_cache = {}

function M.configure(dependencies)
  pack_production_status = assert(dependencies.pack_production_status, "technology researchability requires pack production status")
end

local function enabled_and_reachable(tech_name, visiting)
  if technology_reachability_cache[tech_name] ~= nil then return technology_reachability_cache[tech_name] end
  local tech = data_raw.technology(tech_name)
  if not tech or tech.enabled == false then
    technology_reachability_cache[tech_name] = false
    return false
  end
  visiting = visiting or {}
  if visiting[tech_name] then
    technology_reachability_cache[tech_name] = false
    return false
  end
  visiting[tech_name] = true
  local prerequisites = {}
  for _, prerequisite in ipairs(tech.prerequisites or {}) do table.insert(prerequisites, prerequisite) end
  table.sort(prerequisites)
  for _, prerequisite in ipairs(prerequisites) do
    if not enabled_and_reachable(prerequisite, visiting) then
      visiting[tech_name] = nil
      technology_reachability_cache[tech_name] = false
      return false
    end
  end
  visiting[tech_name] = nil
  technology_reachability_cache[tech_name] = true
  return true
end

local function reason(tech_name, context)
  if not pack_production_status then error("MIR technology researchability dependencies were not configured.", 2) end
  context = context or {}
  local technology = data_raw.technology(tech_name)
  if not technology then return "missing" end
  if technology.enabled == false then return "disabled" end
  if not enabled_and_reachable(tech_name) then return "unreachable-prerequisite" end

  local visiting_technologies = context.visiting_technologies or {}
  if visiting_technologies[tech_name] then return "technology-cycle" end
  visiting_technologies[tech_name] = true
  local function finish(value)
    visiting_technologies[tech_name] = nil
    return value
  end

  local prerequisites = {}
  for _, prerequisite in ipairs(technology.prerequisites or {}) do table.insert(prerequisites, prerequisite) end
  table.sort(prerequisites)
  for _, prerequisite in ipairs(prerequisites) do
    local prerequisite_reason = reason(prerequisite, {
      visiting_packs = context.visiting_packs,
      visiting_technologies = visiting_technologies,
      unlock_recipe_name = context.unlock_recipe_name
    })
    if prerequisite_reason then return finish("prerequisite-" .. prerequisite .. "-" .. prerequisite_reason) end
  end

  if technology.research_trigger then return finish(nil) end
  local unit = technology.unit
  local ingredients = unit and unit.ingredients or nil
  if not unit or not ingredients or #ingredients == 0 then return finish("missing-research-mechanism") end
  if unit.count == nil and unit.count_formula == nil then return finish("missing-research-count") end
  if not lab_compatibility.valid_research_ingredients(ingredients) then return finish("no-accepting-lab") end

  local unlock_recipe = context.unlock_recipe_name
    and data_raw.prototype("recipe", context.unlock_recipe_name) or nil
  for _, ingredient in ipairs(ingredients) do
    local pack_name = lab_compatibility.ingredient_name(ingredient)
    if pack_name then
      if not pack_registry.science_pack_exists(pack_name) then
        return finish("unrecognized-science-" .. pack_name)
      end
      if unlock_recipe and recipe_facts.recipe_outputs_item(unlock_recipe, pack_name) then
        return finish("science-self-lock-" .. pack_name)
      end
      if pack_production_status(pack_name, context.visiting_packs or {}) == "unreachable" then
        return finish("unreachable-science-" .. pack_name)
      end
    end
  end
  return finish(nil)
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

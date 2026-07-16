local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local telemetry = require("prototypes.mir.report.compiler_telemetry")

local M = {}
local pack_production_status = nil
local technology_reachability_cache = {}
local prerequisite_order_cache = {}

function M.configure(dependencies)
  pack_production_status = assert(dependencies.pack_production_status, "technology researchability requires pack production status")
end

local function sorted_prerequisites(technology)
  local out = {}
  for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
    table.insert(out, prerequisite)
  end
  table.sort(out)
  return out
end

local function prerequisite_order(root_name)
  local cached = prerequisite_order_cache[root_name]
  if cached then return cached.order, cached.failure end

  local visited, visiting, order = {}, {}, {}
  local stack = {{name = root_name, entered = false}}
  local failure = nil
  while #stack > 0 and not failure do
    local frame = stack[#stack]
    if visited[frame.name] then
      table.remove(stack)
    elseif not frame.entered then
      local technology = data_raw.technology(frame.name)
      if not technology then
        failure = "missing-prerequisite-" .. tostring(frame.name)
      elseif technology.enabled == false then
        failure = "disabled-prerequisite-" .. tostring(frame.name)
      elseif visiting[frame.name] then
        failure = "technology-cycle-" .. tostring(frame.name)
      else
        frame.entered = true
        frame.prerequisites = sorted_prerequisites(technology)
        frame.next_index = 1
        visiting[frame.name] = true
      end
    else
      local prerequisite = frame.prerequisites[frame.next_index]
      if prerequisite then
        frame.next_index = frame.next_index + 1
        if visiting[prerequisite] then
          failure = "technology-cycle-" .. tostring(prerequisite)
        elseif not visited[prerequisite] then
          table.insert(stack, {name = prerequisite, entered = false})
        end
      else
        visiting[frame.name] = nil
        visited[frame.name] = true
        table.insert(order, frame.name)
        table.remove(stack)
      end
    end
  end

  prerequisite_order_cache[root_name] = {order = order, failure = failure}
  telemetry.observe_max("technology_prerequisite_closure_max", #order)
  return order, failure
end

local function enabled_and_reachable(tech_name)
  if technology_reachability_cache[tech_name] ~= nil then return technology_reachability_cache[tech_name] end
  local technology = data_raw.technology(tech_name)
  if not technology or technology.enabled == false then
    technology_reachability_cache[tech_name] = false
    return false
  end
  local _, failure = prerequisite_order(tech_name)
  technology_reachability_cache[tech_name] = failure == nil
  return technology_reachability_cache[tech_name]
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
  if not pack_production_status then error("MIR technology researchability dependencies were not configured.", 2) end
  context = context or {}
  local technology = data_raw.technology(tech_name)
  if not technology then return "missing" end
  if technology.enabled == false then return "disabled" end

  local visiting_technologies = context.visiting_technologies or {}
  if visiting_technologies[tech_name] then return "technology-cycle" end
  visiting_technologies[tech_name] = true

  local order, failure = prerequisite_order(tech_name)
  if failure then
    visiting_technologies[tech_name] = nil
    return "unreachable-prerequisite"
  end

  for _, candidate_name in ipairs(order) do
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

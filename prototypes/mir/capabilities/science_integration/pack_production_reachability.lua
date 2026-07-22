local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local canonical_recipe_facts = require("prototypes.mir.index.recipe_facts")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local technology_researchability_reason = nil

local function science_pack_resolution_cache()
  return compiler_context.current():state_view("science_pack_production", function() return {} end)
end

function M.configure(dependencies)
  technology_researchability_reason = assert(
    dependencies.technology_researchability_reason,
    "pack production reachability requires technology researchability"
  )
end

function M.pack_production_status(pack_name, visiting_packs)
  if not technology_researchability_reason then
    error("MIR pack production reachability dependencies were not configured.", 2)
  end
  local cache = science_pack_resolution_cache()
  local cached = cache[pack_name]
  if cached then return cached.status, cached.prerequisite end
  if not pack_name or not pack_registry.science_pack_exists(pack_name) then return "unreachable", nil end

  visiting_packs = visiting_packs or {}
  if visiting_packs[pack_name] then return "unreachable", nil end
  local recipe_status = recipe_facts.pack_recipe_status(pack_name)
  if recipe_status and recipe_status.initially_available then
    cache[pack_name] = {status = "initial"}
    return "initial", nil
  end

  if recipe_status and recipe_status.has_recipe then
    visiting_packs[pack_name] = true
    local candidates = {}
    for _, recipe_name in ipairs(recipe_status.recipes or {}) do
      for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
        candidates[technology_name] = candidates[technology_name] or recipe_name
      end
    end
    local technology_names = {}
    for technology_name, _ in pairs(candidates) do table.insert(technology_names, technology_name) end
    table.sort(technology_names)
    for _, technology_name in ipairs(technology_names) do
      local rejection = technology_researchability_reason(technology_name, {
        visiting_packs = visiting_packs,
        visiting_technologies = {},
        unlock_recipe_name = candidates[technology_name]
      })
      if not rejection then
        visiting_packs[pack_name] = nil
        cache[pack_name] = {status = "research", prerequisite = technology_name}
        return "research", technology_name
      end
    end
    visiting_packs[pack_name] = nil
    cache[pack_name] = {status = "unreachable"}
    return "unreachable", nil
  end

  if technology_researchability_reason(pack_name, {
    visiting_packs = visiting_packs,
    visiting_technologies = {}
  }) == nil then
    cache[pack_name] = {status = "non-recipe", prerequisite = pack_name}
    return "non-recipe", pack_name
  end
  cache[pack_name] = {status = "non-recipe"}
  return "non-recipe", nil
end

function M.researchable_unlockers_for_recipe(recipe_name)
  local recipe = canonical_recipe_facts.view(recipe_name)
  if not recipe or recipe_facts.recipe_enabled_without_research(recipe) then return {} end
  local out = {}
  for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
    local rejection = technology_researchability_reason(technology_name, {
      visiting_packs = {},
      visiting_technologies = {},
      unlock_recipe_name = recipe_name
    })
    if not rejection then table.insert(out, technology_name) end
  end
  return out
end

function M.prereq_tech_for_science_pack(pack_name)
  local _, prerequisite = M.pack_production_status(pack_name, {})
  return prerequisite
end

return M

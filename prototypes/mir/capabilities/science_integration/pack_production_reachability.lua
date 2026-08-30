local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local canonical_recipe_facts = require("prototypes.mir.index.recipe_facts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local deepcopy = require("prototypes.mir.core.deepcopy")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local researchability_index = require("prototypes.mir.graph.researchability_index")
local route_policy = require("prototypes.mir.capabilities.science_integration.production_route_policy")

local M = {}

local function technology_researchability_reason(...)
  local service = compiler_context.current():service("science.technology_researchability_reason")
  if not service then error("MIR technology-researchability service is not registered in CompilerContext.", 2) end
  return service(...)
end

local function science_pack_resolution_cache()
  return compiler_context.current():state_view("science_pack_production", function() return {} end)
end

local function graph_index()
  return compiler_context.current():state_view("technology_researchability_index", researchability_index.build)
end

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
end

local EXTRACTION_CATEGORIES = {
  extraction = true,
  harvesting = true,
  mining = true
}

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do
    local name = type(value) == "table" and (value.name or value[1]) or value
    if name == wanted then return true end
  end
  return false
end

local function production_route_class(pack_name, recipe_name, recipe)
  local recycling_route = recipe.source_class == "recycling"
    or string.match(tostring(recipe_name), "%-recycling$") ~= nil
  if recycling_route then
    if contains(recipe.ingredient_names, pack_name) then
      return route_policy.classes.self_return
    end
    return route_policy.classes.recycling
  end
  if contains(recipe.ingredient_names, pack_name) then
    return route_policy.classes.self_return
  end
  if recipe.source_class == "hidden-internal" then
    return route_policy.classes.recovery
  end
  if recipe.source_class == "parameter" then
    return route_policy.classes.opaque
  end
  for _, category in ipairs(recipe.categories or {}) do
    if EXTRACTION_CATEGORIES[category] then return route_policy.classes.extraction end
  end
  if recipe_name == pack_name and recipe.main_product == pack_name then
    return route_policy.classes.ordinary_primary
  end
  return route_policy.classes.ordinary_alternate
end

local function progression_authority_for(pack_name, route)
  local service = compiler_context.current():service("science.production_route_authority_for")
  if not service then return route end
  local authority = service(pack_name, route.recipe, deepcopy(route))
  if authority ~= nil then
    route.progression_authoritative = authority.progression_authoritative
    route.progression_authority = deepcopy(authority.progression_authority)
  end
  return route
end

local function route_for_unlocker(pack_name, recipe_name, recipe, technology_name, visiting_packs)
  local rejection = technology_researchability_reason(technology_name, {
    visiting_packs = visiting_packs,
    visiting_technologies = {},
    unlock_recipe_name = recipe_name
  })
  local index = graph_index()
  local technology_names = researchability_index.reachable_names(index, technology_name)
  local prerequisite_closure, science_burden_set = {}, {}
  for _, candidate_name in ipairs(technology_names) do
    if candidate_name ~= technology_name then table.insert(prerequisite_closure, candidate_name) end
    local candidate = data_raw.technology(candidate_name)
    for _, ingredient in ipairs(((candidate and candidate.unit) or {}).ingredients or {}) do
      local name = ingredient_name(ingredient)
      if name then science_burden_set[name] = true end
    end
  end
  table.sort(prerequisite_closure)
  local science_burden = {}
  for name in pairs(science_burden_set) do table.insert(science_burden, name) end
  table.sort(science_burden)

  local technology = data_raw.technology(technology_name) or {}
  local unit = technology.unit or {}
  return progression_authority_for(pack_name, {
    recipe = recipe_name,
    route_class = production_route_class(pack_name, recipe_name, recipe),
    initial = false,
    unlockers = {technology_name},
    unlocker = technology_name,
    prerequisite_closure = prerequisite_closure,
    science_burden = science_burden,
    reachable = rejection == nil,
    reachability = rejection and {status = "rejected", reason = rejection} or {status = "reachable"},
    progression_key = {
      science_burden_count = #science_burden,
      prerequisite_count = #prerequisite_closure,
      unlock_depth = index.unlock_depths[technology_name],
      research_count = unit.count,
      research_time = unit.time
    },
    provenance = {
      route_policy = route_policy.policy_id,
      recipe = recipe_name,
      unlocker = technology_name
    }
  })
end

local function production_routes(pack_name, recipe_status, visiting_packs)
  local routes = {}
  for _, recipe_name in ipairs(recipe_status.recipes or {}) do
    local recipe = canonical_recipe_facts.view(recipe_name)
    if recipe and recipe.enabled_without_research == true then
      table.insert(routes, progression_authority_for(pack_name, {
        recipe = recipe_name,
        route_class = production_route_class(pack_name, recipe_name, recipe),
        initial = true,
        unlockers = {},
        prerequisite_closure = {},
        science_burden = {},
        reachable = true,
        reachability = {status = "reachable"},
        progression_key = {
          science_burden_count = 0,
          prerequisite_count = 0,
          unlock_depth = 0,
          research_count = 0,
          research_time = 0
        },
        provenance = {route_policy = route_policy.policy_id, recipe = recipe_name}
      }))
    else
      for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
        table.insert(routes, route_for_unlocker(
          pack_name, recipe_name, recipe, technology_name, visiting_packs))
      end
    end
  end
  return routes
end

function M.pack_production_status(pack_name, visiting_packs)
  local cache = science_pack_resolution_cache()
  local cached = cache[pack_name]
  if cached then return cached.status, cached.prerequisite end
  if not pack_name or not pack_registry.science_pack_exists(pack_name) then return "unreachable", nil end

  visiting_packs = visiting_packs or {}
  if visiting_packs[pack_name] then return "unreachable", nil end
  local recipe_status = recipe_facts.pack_recipe_status(pack_name)
  if recipe_status and recipe_status.has_recipe then
    visiting_packs[pack_name] = true
    local selected, decision = route_policy.select(production_routes(pack_name, recipe_status, visiting_packs))
    visiting_packs[pack_name] = nil
    if selected then
      local status = selected.initial and "initial" or "research"
      cache[pack_name] = {
        status = status,
        prerequisite = selected.unlocker,
        route = selected,
        route_decision = decision
      }
      return status, selected.unlocker
    end
    cache[pack_name] = {status = "unreachable", route_decision = decision}
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

function M.production_route_for_pack(pack_name)
  M.pack_production_status(pack_name, {})
  local cached = science_pack_resolution_cache()[pack_name]
  return cached and deepcopy(cached.route) or nil
end

function M.production_route_decision_for_pack(pack_name)
  M.pack_production_status(pack_name, {})
  local cached = science_pack_resolution_cache()[pack_name]
  return cached and deepcopy(cached.route_decision) or nil
end

return M

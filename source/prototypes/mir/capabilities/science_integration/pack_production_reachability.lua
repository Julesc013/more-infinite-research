local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local canonical_recipe_facts = require("prototypes.mir.index.recipe_facts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local deepcopy = require("prototypes.mir.core.deepcopy")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local researchability_index = require("prototypes.mir.graph.researchability_index")
local route_policy = require("prototypes.mir.capabilities.science_integration.production_route_policy")
local route_feasibility = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")

local M = {}

local function technology_researchability_reason(...)
  local service = compiler_context.current():service("science.technology_researchability_reason")
  if not service then error("MIR technology-researchability service is not registered in CompilerContext.", 2) end
  return service(...)
end

local function science_pack_resolution_cache()
  local context = compiler_context.current()
  local source_epoch = canonical_recipe_facts.source_epoch()
  local cached = context:state_view("science_pack_production")
  if cached and cached.recipe_source_epoch == source_epoch then return cached.entries end
  local value = {recipe_source_epoch = source_epoch, entries = {}}
  if cached then
    context:replace_epoch("science_pack_production", value, context:state_epoch("science_pack_production"))
  else
    context:set_state("science_pack_production", value)
  end
  return value.entries
end

local function graph_index()
  return compiler_context.current():state_view("technology_researchability_index", researchability_index.build)
end

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
end

local function route_for_unlocker(recipe_name, technology_name, visiting_packs, visiting_technologies)
  local rejection = technology_researchability_reason(technology_name, {
    visiting_packs = visiting_packs,
    visiting_technologies = visiting_technologies or {},
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
  return {
    recipe = recipe_name,
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
  }
end

local function output_recipe_names(identity)
  if not identity or type(identity.type) ~= "string" or identity.type == ""
    or type(identity.name) ~= "string" or identity.name == "" then
    return {}
  end
  local names = {}
  -- The normalized output index is typed.  A research-unlocked fluid
  -- intermediate (for example, molten solder) must be resolved through its
  -- fluid identity; falling back to an item name would either reject a real
  -- route or conflate same-named products.
  for _, recipe_name in ipairs(canonical_recipe_facts.recipes_by_output_identity_view(identity.type, identity.name) or {}) do
    table.insert(names, recipe_name)
  end
  table.sort(names)
  return names
end

local function unlock_pair_key(recipe_name, technology_name)
  return recipe_name .. "\0" .. technology_name
end

local function active_unlock_context(options)
  local context = options.active_unlock_context
  if context then return context end
  context = {pairs = {}, technologies = {}}
  options.active_unlock_context = context
  return context
end

-- A normal route witness deliberately permits only enabled recipes.  Some
-- ecosystems make an early production intermediate available through a
-- research-trigger technology, however, and that technology has no lab
-- ingredient dependency.  Admit such an intermediate only when the existing
-- technology researchability service proves the concrete unlocker, and then
-- recursively prove every ingredient of its recipe with the same active
-- visitation state.  This is an acquisition witness, not a general license
-- for disabled recipes: ordinary science dependencies still pass through the
-- same pack/self-lock checks as every other technology route.
local function research_unlocked_output_witness(identity, options, state, visiting_packs, visiting_technologies)
  local context = active_unlock_context(options)
  for _, recipe_name in ipairs(output_recipe_names(identity)) do
    local fact = canonical_recipe_facts.view(recipe_name)
    if fact and fact.enabled_without_research ~= true then
      local unlockers = {}
      for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
        table.insert(unlockers, technology_name)
      end
      table.sort(unlockers)
      for _, technology_name in ipairs(unlockers) do
        local pair_key = unlock_pair_key(recipe_name, technology_name)
        -- The precise recipe/technology pair is active while its ingredients
        -- are being proved. Reopening that same pair is an unseeded loop, but
        -- a different recipe unlocked by the already-proved technology is a
        -- legitimate intermediate (for example, a component accompanying the
        -- circuit unlocked by one early technology).
        local rejection = context.pairs[pair_key] and "active-unlock-pair" or nil
        if rejection == nil and context.technologies[technology_name] == nil then
          rejection = technology_researchability_reason(technology_name, {
            visiting_packs = visiting_packs,
            visiting_technologies = visiting_technologies or {},
            unlock_recipe_name = recipe_name
          })
        end
        if rejection == nil then
          local previous_technology = context.technologies[technology_name]
          context.pairs[pair_key] = true
          context.technologies[technology_name] = (previous_technology or 0) + 1
          local recipe_witness = route_feasibility.recipe_witness(recipe_name, identity, options, state)
          context.pairs[pair_key] = nil
          if previous_technology then
            context.technologies[technology_name] = previous_technology
          else
            context.technologies[technology_name] = nil
          end
          if recipe_witness then
            return {
              kind = "research-unlocked-recipe",
              recipe = recipe_name,
              unlocker = technology_name,
              recipe_witness = recipe_witness
            }
          end
        end
      end
    end
  end
  return nil
end

local function production_witness_options(visiting_packs, visiting_technologies)
  -- This is query-local. It records only unlockers which have already passed
  -- the researchability service while their concrete recipe route is being
  -- verified; it never escapes into the science-pack result cache.
  local options = {active_unlock_context = {pairs = {}, technologies = {}}}
  options.research_unlock_witness = function(identity, state)
    return research_unlocked_output_witness(
      identity,
      options,
      state,
      visiting_packs,
      visiting_technologies
    )
  end
  return options
end

local function production_routes(recipe_status, visiting_packs, excluded_unlocker, visiting_technologies)
  local routes = {}
  local witness_options = production_witness_options(visiting_packs, visiting_technologies)
  for _, recipe_name in ipairs(recipe_status.recipes or {}) do
    local recipe = canonical_recipe_facts.view(recipe_name)
    if recipe and recipe.enabled_without_research == true then
      local witness = route_feasibility.initial_recipe_witness(recipe_name, recipe_status.pack_name, witness_options)
      if witness then
        table.insert(routes, {
          recipe = recipe_name,
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
          provenance = {
            route_policy = route_policy.policy_id,
            recipe = recipe_name,
            structural_route_witness = witness.kind
          }
        })
      end
    else
      local witness = route_feasibility.recipe_witness(recipe_name, recipe_status.pack_name, witness_options)
      if witness then
        for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
          if technology_name ~= excluded_unlocker then
            local route = route_for_unlocker(
              recipe_name,
              technology_name,
              visiting_packs,
              visiting_technologies
            )
            route.provenance.structural_route_witness = witness.kind
            table.insert(routes, route)
          end
        end
      end
    end
  end
  return routes
end

local function has_active_traversal(visiting_packs, visiting_technologies)
  for _ in pairs(visiting_packs or {}) do return true end
  for _ in pairs(visiting_technologies or {}) do return true end
  return false
end

local function copy_visitation_without(visiting_packs, pack_name)
  local out = {}
  for name, active in pairs(visiting_packs or {}) do
    if name ~= pack_name and active then out[name] = true end
  end
  return out
end

function M.pack_production_status(pack_name, visiting_packs, visiting_technologies)
  if not pack_name or not pack_registry.science_pack_exists(pack_name) then return "unreachable", nil end

  visiting_packs = visiting_packs or {}
  if visiting_packs[pack_name] then return "unreachable", nil end
  -- A nonempty visitation set makes this result conditional on the caller's
  -- current traversal. Never retain a rejection (or provisional success) from
  -- that branch as a reusable context-wide answer.
  local reusable = not has_active_traversal(visiting_packs, visiting_technologies)
  local cache = science_pack_resolution_cache()
  local cached = reusable and cache[pack_name] or nil
  if cached then return cached.status, cached.prerequisite end

  -- A declared direct source is an independent acquisition seed even when a
  -- later recipe for the same pack also exists. A locked self-output
  -- "improved" recipe cannot erase an earlier natural source and turn its
  -- own research into a false self-lock.
  if route_feasibility.source_witness(pack_name) then
    if reusable then cache[pack_name] = {status = "non-recipe", prerequisite = pack_name} end
    return "non-recipe", pack_name
  end

  local recipe_status = recipe_facts.pack_recipe_status(pack_name)
  if recipe_status and recipe_status.has_recipe then
    visiting_packs[pack_name] = true
    local selected = route_policy.select(production_routes(
      recipe_status,
      visiting_packs,
      nil,
      visiting_technologies
    ))
    visiting_packs[pack_name] = nil
    if selected then
      local status = selected.initial and "initial" or "research"
      if reusable then cache[pack_name] = {status = status, prerequisite = selected.unlocker, route = selected} end
      return status, selected.unlocker
    end
    if reusable then cache[pack_name] = {status = "unreachable"} end
    return "unreachable", nil
  end

  if reusable then cache[pack_name] = {status = "unreachable"} end
  return "unreachable", nil
end

-- A recipe unlocked by the technology currently being evaluated cannot prove
-- that its own research ingredient was already obtainable. This narrow query
-- proves an alternative concrete production route while retaining every other
-- active traversal guard. It is deliberately uncached: the excluded unlocker
-- and inherited traversal make it a contextual witness, not a global fact.
function M.independent_pack_acquisition_witness(
  pack_name,
  excluded_unlocker,
  visiting_packs,
  visiting_technologies
)
  if not pack_name or not excluded_unlocker or not pack_registry.science_pack_exists(pack_name) then return nil end
  -- This witness is deliberately independent of an unlocker. A direct source
  -- remains valid even if the pack also has a recipe unlocked by the
  -- technology under assessment.
  local direct_source = route_feasibility.source_witness(pack_name)
  if direct_source then return direct_source end
  local recipe_status = recipe_facts.pack_recipe_status(pack_name)
  if not recipe_status or not recipe_status.has_recipe then return nil end

  local witness_visiting = copy_visitation_without(visiting_packs, pack_name)
  witness_visiting[pack_name] = true
  local selected = route_policy.select(production_routes(
    recipe_status,
    witness_visiting,
    excluded_unlocker,
    visiting_technologies
  ))
  witness_visiting[pack_name] = nil
  return selected and deepcopy(selected) or nil
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

return M

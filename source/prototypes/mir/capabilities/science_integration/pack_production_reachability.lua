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

-- Rejection projections are an exact-test diagnostic surface, not a second
-- planner. Keep their retained output finite even against a hostile or very
-- large recipe graph. The fixed defaults and fixed maxima make a captured
-- projection reproducible; callers may narrow (never expand) the limits for
-- a controlled cap assertion.
local PROJECTION_DEFAULT_LIMITS = {
  candidates = 16,
  nodes = 128,
  depth = 32,
  bytes = 32768
}
local PROJECTION_MAX_LIMITS = {
  candidates = 64,
  nodes = 1024,
  depth = 128,
  bytes = 262144
}

local function positive_limit(value, default, maximum)
  value = tonumber(value)
  if value == nil then return default end
  value = math.floor(value)
  if value < 1 then return 1 end
  return math.min(value, maximum)
end

local function projection_limits(options)
  local supplied = type(options) == "table" and options.limits or nil
  supplied = type(supplied) == "table" and supplied or {}
  return {
    candidates = positive_limit(supplied.candidates, PROJECTION_DEFAULT_LIMITS.candidates,
      PROJECTION_MAX_LIMITS.candidates),
    nodes = positive_limit(supplied.nodes, PROJECTION_DEFAULT_LIMITS.nodes,
      PROJECTION_MAX_LIMITS.nodes),
    depth = positive_limit(supplied.depth, PROJECTION_DEFAULT_LIMITS.depth,
      PROJECTION_MAX_LIMITS.depth),
    bytes = positive_limit(supplied.bytes, PROJECTION_DEFAULT_LIMITS.bytes,
      PROJECTION_MAX_LIMITS.bytes)
  }
end

local function stable_value_bytes(value)
  local value_type = type(value)
  if value_type == "nil" then return 3 end
  if value_type == "boolean" then return value and 4 or 5 end
  if value_type == "number" then return #tostring(value) end
  if value_type == "string" then return #value end
  if value_type ~= "table" then return #tostring(value) end
  local keys, total = {}, 2
  for key in pairs(value) do table.insert(keys, key) end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  for _, key in ipairs(keys) do
    total = total + stable_value_bytes(key) + stable_value_bytes(value[key]) + 2
  end
  return total
end

local function copy_flags(flags)
  local copied = {}
  for key, value in pairs(flags or {}) do copied[key] = value end
  return copied
end

local function ordered_flags(flags)
  local out = {}
  for _, key in ipairs({"candidates", "nodes", "depth", "bytes"}) do
    if flags[key] then table.insert(out, key) end
  end
  return out
end

local function ordered_keys(values)
  local out = {}
  for key, value in pairs(values or {}) do
    if value then table.insert(out, key) end
  end
  table.sort(out)
  return out
end

local function new_projection_observer(limits)
  local observer = {
    limits = deepcopy(limits),
    events = {},
    candidates = 0,
    -- Work is monotonic.  A diagnostic branch may roll its trace back while
    -- choosing an OR alternative, but it must never regain visits which have
    -- already inspected the graph.  Keeping these counters separate makes a
    -- cap a real traversal bound rather than merely a retained-output bound.
    visits = 0,
    work_maximum_depth = 0,
    stopped = false,
    work_truncated = {},
    unavailable = {},
    -- Trace state is intentionally rollback-able: it represents only the
    -- selected failure tree, not every discarded alternative.
    bytes = 0,
    trace_truncated = {}
  }
  function observer:mark_work(reason)
    self.work_truncated[reason] = true
    self.stopped = true
  end
  function observer:mark_trace(reason)
    self.trace_truncated[reason] = true
  end
  function observer:mark_unavailable(reason)
    self.unavailable[reason] = true
  end
  function observer:is_stopped()
    return self.stopped
  end
  function observer:work_view()
    -- The initial status pass needs the same hard traversal budget, but it is
    -- not itself a retained explanation. Exposing only the work methods keeps
    -- its discarded alternatives out of the rollback-able failure trace.
    local owner = self
    return {
      is_stopped = function() return owner:is_stopped() end,
      reserve_visit = function(_, depth) return owner:reserve_visit(depth) end
    }
  end
  function observer:reserve_visit(depth)
    depth = tonumber(depth) or 0
    if self.stopped then return false end
    if depth > self.limits.depth then
      self:mark_work("depth")
      return false
    end
    if self.visits >= self.limits.nodes then
      self:mark_work("nodes")
      return false
    end
    self.visits = self.visits + 1
    self.work_maximum_depth = math.max(self.work_maximum_depth, depth)
    return true
  end
  function observer:checkpoint()
    return {
      events = #self.events,
      bytes = self.bytes,
      trace_truncated = copy_flags(self.trace_truncated)
    }
  end
  function observer:rollback(checkpoint)
    while #self.events > checkpoint.events do table.remove(self.events) end
    self.bytes = checkpoint.bytes
    self.trace_truncated = copy_flags(checkpoint.trace_truncated)
  end
  function observer:record(failure, depth)
    if self.stopped then return false end
    local bytes = stable_value_bytes(failure)
    if self.bytes + bytes > self.limits.bytes then
      self:mark_trace("bytes")
      return false
    end
    self.bytes = self.bytes + bytes
    table.insert(self.events, deepcopy(failure))
    return true
  end
  function observer:begin_candidate()
    if self.stopped then return false end
    if self.candidates >= self.limits.candidates then
      self:mark_work("candidates")
      return false
    end
    self.candidates = self.candidates + 1
    return true
  end
  function observer:first_failure_since(checkpoint)
    return self.events[(checkpoint and checkpoint.events or 0) + 1]
  end
  function observer:reserve_output(value)
    if self.stopped then return false end
    local bytes = stable_value_bytes(value)
    if self.bytes + bytes > self.limits.bytes then
      self:mark_trace("bytes")
      return false
    end
    self.bytes = self.bytes + bytes
    return true
  end
  function observer:metadata()
    local all_truncated = copy_flags(self.work_truncated)
    for reason, value in pairs(self.trace_truncated) do all_truncated[reason] = value end
    return {
      limits = deepcopy(self.limits),
      usage = {
        candidates = self.candidates,
        visits = self.visits,
        nodes = self.visits,
        maximum_depth = self.work_maximum_depth,
        trace_events = #self.events,
        bytes = self.bytes
      },
      stopped = self.stopped,
      truncated = ordered_flags(all_truncated),
      trace_truncated = ordered_flags(self.trace_truncated),
      unavailable = ordered_keys(self.unavailable)
    }
  end
  return observer
end

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

-- A projection observer may stop only its private traversal. Normal admission
-- has no observer, so these guards cannot participate in route selection or
-- cache population outside an exact-test diagnostic query.
local function diagnostic_visit(observer, depth)
  if not observer then return true end
  if type(observer.is_stopped) == "function" and observer:is_stopped() then return false end
  if type(observer.reserve_visit) == "function" then return observer:reserve_visit(depth or 0) end
  return true
end

local function diagnostic_indeterminate(observer)
  return observer and type(observer.is_stopped) == "function" and observer:is_stopped()
end

-- A diagnostic projection must not materialize the comprehensive technology
-- graph index merely to describe one unlocker. Walk the requested closure
-- under the same irreversible observer budget instead. Normal admission uses
-- graph_index() and keeps its existing route-policy details unchanged.
local function bounded_technology_names(root_name, observer)
  local seen, active, names = {}, {}, {}
  local function visit(name, depth)
    if not diagnostic_visit(observer, depth) then return false end
    if active[name] or seen[name] then return true end
    local technology = data_raw.technology(name)
    if not technology then return true end
    seen[name], active[name] = true, true
    table.insert(names, name)
    local prerequisites = {}
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if not diagnostic_visit(observer, depth + 1) then return false end
      table.insert(prerequisites, prerequisite)
    end
    table.sort(prerequisites)
    for _, prerequisite in ipairs(prerequisites) do
      if not visit(prerequisite, depth + 1) then return false end
    end
    active[name] = nil
    return true
  end
  local complete = visit(root_name, 0)
  table.sort(names)
  return names, complete
end

local function route_for_unlocker(recipe_name, technology_name, visiting_packs, visiting_technologies, observer)
  if not diagnostic_visit(observer, 0) then
    return {
      recipe = recipe_name,
      initial = false,
      unlockers = {technology_name},
      unlocker = technology_name,
      reachable = false,
      reachability = {status = "rejected", reason = "diagnostic-budget-exhausted"},
      progression_key = {science_burden_count = 0, prerequisite_count = 0, unlock_depth = 0},
      provenance = {route_policy = route_policy.policy_id, recipe = recipe_name, unlocker = technology_name}
    }
  end
  local rejection = technology_researchability_reason(technology_name, {
    visiting_packs = visiting_packs,
    visiting_technologies = visiting_technologies or {},
    unlock_recipe_name = recipe_name,
    diagnostic_observer = observer
  })
  local index, technology_names, closure_complete
  if observer then
    technology_names, closure_complete = bounded_technology_names(technology_name, observer)
    if not closure_complete then rejection = rejection or "diagnostic-budget-exhausted" end
  else
    index = graph_index()
    technology_names = researchability_index.reachable_names(index, technology_name)
  end
  local prerequisite_closure, science_burden_set = {}, {}
  for _, candidate_name in ipairs(technology_names) do
    if not diagnostic_visit(observer, 0) then
      rejection = rejection or "diagnostic-budget-exhausted"
      break
    end
    if candidate_name ~= technology_name then table.insert(prerequisite_closure, candidate_name) end
    local candidate = data_raw.technology(candidate_name)
    for _, ingredient in ipairs(((candidate and candidate.unit) or {}).ingredients or {}) do
      if not diagnostic_visit(observer, 0) then
        rejection = rejection or "diagnostic-budget-exhausted"
        break
      end
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
      unlock_depth = index and index.unlock_depths[technology_name] or 0,
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

local function output_recipe_names(identity, observer)
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
    if not diagnostic_visit(observer, 0) then break end
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

local function active_set_key(values)
  local names = {}
  for name, active in pairs(values or {}) do
    if active then table.insert(names, tostring(name)) end
  end
  table.sort(names)
  return table.concat(names, "\1")
end

-- Technology researchability is contextual, but one structural route query
-- can ask the exact same recipe/unlocker question thousands of times while it
-- explores sibling producer recipes. Reuse only that exact query-local
-- decision. The active pack and technology sets remain part of the key, and
-- diagnostic traversals deliberately bypass the memo so their work budget and
-- failure trace remain observationally exact.
local function contextual_technology_researchability_reason(
  technology_name,
  recipe_name,
  options,
  visiting_packs,
  visiting_technologies
)
  if options.diagnostic_observer then
    return technology_researchability_reason(technology_name, {
      visiting_packs = visiting_packs,
      visiting_technologies = visiting_technologies or {},
      unlock_recipe_name = recipe_name,
      diagnostic_observer = options.diagnostic_observer,
      diagnostic_depth = options.diagnostic_depth
    })
  end
  local memo = options.technology_reason_memo
  if not memo then
    return technology_researchability_reason(technology_name, {
      visiting_packs = visiting_packs,
      visiting_technologies = visiting_technologies or {},
      unlock_recipe_name = recipe_name
    })
  end
  local key = table.concat({
    recipe_name,
    technology_name,
    active_set_key(visiting_packs),
    active_set_key(visiting_technologies)
  }, "\0")
  local cached = memo[key]
  if cached ~= nil then return cached == false and nil or cached end
  local rejection = technology_researchability_reason(technology_name, {
    visiting_packs = visiting_packs,
    visiting_technologies = visiting_technologies or {},
    unlock_recipe_name = recipe_name
  })
  memo[key] = rejection or false
  return rejection
end

-- This observer is populated only by the explicit rejection projection below.
-- It must never participate in normal route selection, cache population, or
-- feasibility decisions.
local function record_diagnostic_failure(options, failure)
  local observer = options and options.diagnostic_observer
  if observer and type(observer.record) == "function" then
    observer:record(deepcopy(failure), options.diagnostic_depth or 0)
  elseif type(options.diagnostic_failure) == "function" then
    options.diagnostic_failure(deepcopy(failure))
  end
end

local function diagnostic_checkpoint(options)
  local observer = options and options.diagnostic_observer
  if observer and type(observer.checkpoint) == "function" then return observer:checkpoint() end
  return nil
end

local function diagnostic_rollback(options, checkpoint)
  local observer = options and options.diagnostic_observer
  if checkpoint and observer and type(observer.rollback) == "function" then
    observer:rollback(checkpoint)
  end
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
  local witness_checkpoint = diagnostic_checkpoint(options)
  for _, recipe_name in ipairs(output_recipe_names(identity, options.diagnostic_observer)) do
    if not diagnostic_visit(options.diagnostic_observer, options.diagnostic_depth or 0) then return nil end
    diagnostic_rollback(options, witness_checkpoint)
    local fact = canonical_recipe_facts.view(recipe_name)
    if fact and fact.enabled_without_research ~= true then
      local unlockers = {}
      for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
        if not diagnostic_visit(options.diagnostic_observer, options.diagnostic_depth or 0) then return nil end
        table.insert(unlockers, technology_name)
      end
      table.sort(unlockers)
      for _, technology_name in ipairs(unlockers) do
        if not diagnostic_visit(options.diagnostic_observer, options.diagnostic_depth or 0) then return nil end
        -- Recipe/unlocker pairs are alternatives. Keep only the active pair's
        -- trace so a failed earlier pair cannot mask the final selected pair
        -- or a later successful pair.
        diagnostic_rollback(options, witness_checkpoint)
        local pair_key = unlock_pair_key(recipe_name, technology_name)
        -- The precise recipe/technology pair is active while its ingredients
        -- are being proved. Reopening that same pair is an unseeded loop, but
        -- a different recipe unlocked by the already-proved technology is a
        -- legitimate intermediate (for example, a component accompanying the
        -- circuit unlocked by one early technology).
        local rejection = context.pairs[pair_key] and "active-unlock-pair" or nil
        if rejection == nil and context.technologies[technology_name] == nil then
          rejection = contextual_technology_researchability_reason(
            technology_name,
            recipe_name,
            options,
            visiting_packs,
            visiting_technologies
          )
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
            -- A successful research-unlocked route selects this branch. Drop
            -- provisional observations from rejected recipe/unlocker pairs.
            diagnostic_rollback(options, witness_checkpoint)
            return {
              kind = "research-unlocked-recipe",
              recipe = recipe_name,
              unlocker = technology_name,
              recipe_witness = recipe_witness
            }
          end
        elseif rejection == "active-unlock-pair" then
          record_diagnostic_failure(options, {
            kind = "cycle",
            recipe = recipe_name,
            technology = technology_name,
            identity = deepcopy(identity),
            reason = rejection
          })
        else
          record_diagnostic_failure(options, {
            kind = "technology",
            recipe = recipe_name,
            technology = technology_name,
            identity = deepcopy(identity),
            reason = rejection
          })
        end
      end
    end
  end
  return nil
end

local function production_witness_options(visiting_packs, visiting_technologies, diagnostic_observer)
  -- This is query-local. It records only unlockers which have already passed
  -- the researchability service while their concrete recipe route is being
  -- verified; it never escapes into the science-pack result cache.
  local options = {
    active_unlock_context = {pairs = {}, technologies = {}},
    technology_reason_memo = {},
    diagnostic_observer = diagnostic_observer
  }
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

local function production_routes(recipe_status, visiting_packs, excluded_unlocker, visiting_technologies, observer)
  local routes = {}
  local witness_options = production_witness_options(visiting_packs, visiting_technologies, observer)
  -- All candidates belong to one immutable recipe snapshot and exact active
  -- traversal. Sharing the query state reuses only raw indexes and the
  -- context-free positive witnesses owned by recipe_route_feasibility; its
  -- contextual research decisions remain in witness_options and its active
  -- cycle set is cleared by every completed candidate.
  local witness_state = {}
  for _, recipe_name in ipairs(recipe_status.recipes or {}) do
    if not diagnostic_visit(observer, 0) then break end
    local recipe = canonical_recipe_facts.view(recipe_name)
    if recipe and recipe.enabled_without_research == true then
      local witness = route_feasibility.initial_recipe_witness(
        recipe_name, recipe_status.pack_name, witness_options, witness_state)
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
      local witness = route_feasibility.recipe_witness(
        recipe_name, recipe_status.pack_name, witness_options, witness_state)
      if witness then
        for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
          if not diagnostic_visit(observer, 0) then break end
          if technology_name ~= excluded_unlocker then
            local route = route_for_unlocker(
              recipe_name,
              technology_name,
              visiting_packs,
              visiting_technologies,
              observer
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

local function sorted_recipe_names(recipe_status, observer)
  local names = {}
  for _, recipe_name in ipairs((recipe_status and recipe_status.recipes) or {}) do
    if not diagnostic_visit(observer, 0) then break end
    table.insert(names, recipe_name)
  end
  table.sort(names)
  return names
end

local function sorted_unlocker_names(recipe_name, observer)
  local names = {}
  for _, technology_name in ipairs(recipe_facts.unlockers_for_recipe(recipe_name)) do
    if not diagnostic_visit(observer, 0) then break end
    table.insert(names, technology_name)
  end
  table.sort(names)
  return names
end

-- Build a trace for one candidate using the same witnesses that normal route
-- selection uses. The trace gets fresh traversal state and is never retained
-- in the production cache, so observing a rejection cannot affect a later
-- admission query.
local function rejection_candidate(recipe_name, pack_name, visiting_packs, visiting_technologies, observer)
  local checkpoint = observer:checkpoint()
  local fact = canonical_recipe_facts.view(recipe_name)
  local options = production_witness_options(
    visiting_packs,
    visiting_technologies,
    observer
  )
  local witness
  if fact and fact.enabled_without_research == true then
    witness = route_feasibility.initial_recipe_witness(recipe_name, pack_name, options)
  else
    witness = route_feasibility.recipe_witness(recipe_name, pack_name, options)
  end
  -- route_for_recipe/acquisition_witness roll back all provisional structural
  -- observations once a later OR branch succeeds. Consequently a reachable
  -- structural route has no structural first failure to leak into the
  -- technology decision below.
  local first_structural_failure = observer:first_failure_since(checkpoint)

  local candidate = {
    recipe = recipe_name,
    identity = {type = "item", name = pack_name},
    enabled_without_research = fact and fact.enabled_without_research == true or false,
    structural_route = witness and {
      status = "reachable",
      witness_kind = witness.kind
    } or {
      status = "rejected"
    },
    unlockers = {}
  }
  local first_technology_failure
  for _, technology_name in ipairs(sorted_unlocker_names(recipe_name, observer)) do
    if witness and candidate.enabled_without_research ~= true then
      local reason = technology_researchability_reason(technology_name, {
        visiting_packs = visiting_packs,
        visiting_technologies = visiting_technologies or {},
        unlock_recipe_name = recipe_name,
        diagnostic_observer = observer
      })
      local unlocker = {
        technology = technology_name,
        status = reason and "rejected" or "reachable",
        reason = reason
      }
      table.insert(candidate.unlockers, unlocker)
      if reason and not first_technology_failure then
        first_technology_failure = {
          kind = "technology",
          recipe = recipe_name,
          technology = technology_name,
          identity = {type = "item", name = pack_name},
          reason = reason
        }
      end
    else
      table.insert(candidate.unlockers, {
        technology = technology_name,
        status = "not-evaluated",
        reason = witness and "enabled-recipe" or "structural-route-rejected"
      })
    end
  end
  if witness then
    candidate.first_failure = first_technology_failure or {
      kind = "identity",
      recipe = recipe_name,
      identity = {type = "item", name = pack_name},
      reason = "no-researchable-unlocker"
    }
  else
    candidate.first_failure = first_structural_failure or {
      kind = "identity",
      recipe = recipe_name,
      identity = {type = "item", name = pack_name},
      reason = "no-admissible-route"
    }
  end
  return candidate
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

-- This core query is shared by admission and the isolated diagnostic context.
-- Keeping it private prevents a diagnostic projection from re-entering the
-- public/cache-owning pack_production_status surface of its parent context.
local function resolve_pack_production_status(pack_name, visiting_packs, visiting_technologies, observer)
  if not pack_name then return "unreachable", nil, false end
  local exists = pack_registry.science_pack_exists(pack_name, observer)
  if diagnostic_indeterminate(observer) then return "indeterminate", nil, exists end
  if not exists then return "unreachable", nil, false end
  if not diagnostic_visit(observer, 0) then
    return observer and "indeterminate" or "unreachable", nil, exists
  end

  visiting_packs = visiting_packs or {}
  if visiting_packs[pack_name] then return "unreachable", nil, exists end
  -- A nonempty visitation set makes this result conditional on the caller's
  -- current traversal. Never retain a rejection (or provisional success) from
  -- that branch as a reusable context-wide answer.
  local reusable = observer == nil and not has_active_traversal(visiting_packs, visiting_technologies)
  local cache = reusable and science_pack_resolution_cache() or nil
  local cached = reusable and cache[pack_name] or nil
  if cached then return cached.status, cached.prerequisite, exists end

  -- A declared direct source is an independent acquisition seed even when a
  -- later recipe for the same pack also exists. A locked self-output
  -- "improved" recipe cannot erase an earlier natural source and turn its
  -- own research into a false self-lock.
  if route_feasibility.source_witness(pack_name, observer and {diagnostic_observer = observer} or nil) then
    if reusable then cache[pack_name] = {status = "non-recipe", prerequisite = pack_name} end
    return "non-recipe", pack_name, exists
  end
  if diagnostic_indeterminate(observer) then return "indeterminate", nil, exists end

  local recipe_status = recipe_facts.pack_recipe_status(pack_name, observer)
  if diagnostic_indeterminate(observer) then return "indeterminate", nil, exists end
  if recipe_status and recipe_status.has_recipe then
    visiting_packs[pack_name] = true
    local selected = route_policy.select(production_routes(
      recipe_status,
      visiting_packs,
      nil,
      visiting_technologies,
      observer
    ))
    visiting_packs[pack_name] = nil
    if diagnostic_indeterminate(observer) then return "indeterminate", nil, exists end
    if selected then
      local status = selected.initial and "initial" or "research"
      if reusable then cache[pack_name] = {status = status, prerequisite = selected.unlocker, route = selected} end
      return status, selected.unlocker, exists
    end
    if reusable then cache[pack_name] = {status = "unreachable"} end
    return "unreachable", nil, exists
  end

  if reusable then cache[pack_name] = {status = "unreachable"} end
  return "unreachable", nil, exists
end

function M.pack_production_status(pack_name, visiting_packs, visiting_technologies, observer)
  -- Preserve the established public two-value contract. The third value is a
  -- private hand-off from the common core to the bounded trace constructor.
  local status, prerequisite = resolve_pack_production_status(
    pack_name,
    visiting_packs,
    visiting_technologies,
    observer
  )
  return status, prerequisite
end

-- Diagnostic-only explanation of an already rejected root pack query. This
-- intentionally has no effect on admission: callers must opt in, the normal
-- status result remains authoritative, and the projection uses no persistent
-- trace cache. Candidate recipes and unlockers are lexical so a future exact
-- probe can compare data-stage results across both loads deterministically.
-- Recipe facts normally construct their whole canonical index on first use.
-- A rejection projection is capped before it may inspect even one recipe, so
-- it may borrow only an index that the parent compilation already owns. The
-- reference and both epochs are a scoped lifetime contract: the observation
-- cannot rebuild or replace parent state, and it refuses a missing or changed
-- source instead of silently falling back to an uncapped facts build.
local function observation_recipe_snapshot(parent)
  local recipe_index = parent:state_view("recipe_index")
  local recipe_source = parent:state_view("recipe_source")
  if type(recipe_index) ~= "table" or type(recipe_source) ~= "table" then return nil end
  local index_epoch = parent:state_epoch("recipe_index")
  local source_epoch = parent:state_epoch("recipe_source")
  if type(index_epoch) ~= "number" or type(source_epoch) ~= "number" then return nil end
  return {
    parent = parent,
    recipe_index = recipe_index,
    recipe_source = recipe_source,
    recipe_index_epoch = index_epoch,
    recipe_source_epoch = source_epoch
  }
end

local function observation_recipe_snapshot_is_current(snapshot)
  return snapshot ~= nil
    and snapshot.parent:state_view("recipe_index") == snapshot.recipe_index
    and snapshot.parent:state_view("recipe_source") == snapshot.recipe_source
    and snapshot.parent:state_epoch("recipe_index") == snapshot.recipe_index_epoch
    and snapshot.parent:state_epoch("recipe_source") == snapshot.recipe_source_epoch
end

local function observation_context()
  local parent = compiler_context.current()
  local recipe_snapshot = observation_recipe_snapshot(parent)
  local observation = compiler_context.new({execution_mode = parent:execution_mode()})
  -- Only the services the reachability traversal calls are copied. State,
  -- telemetry, technology indexes, and their epochs deliberately start empty.
  -- The sole exception is the immutable parent recipe snapshot above: importing
  -- it into this short-lived context prevents the normal facts service from
  -- doing an uncapped full-recipe build during a capped diagnostic query.
  if recipe_snapshot then
    observation:set_state("recipe_source", recipe_snapshot.recipe_source)
    observation:set_state("recipe_index", recipe_snapshot.recipe_index)
  end
  for _, service_name in ipairs({
    "science.technology_researchability_reason",
    "science.independent_pack_acquisition_witness",
    "science.prereq_tech_for_science_pack",
    "science.production_route_for_pack"
  }) do
    local service = parent:service(service_name)
    if service then observation:set_service(service_name, service) end
  end
  observation:set_service("science.pack_production_status", resolve_pack_production_status)
  observation:freeze_services()
  return observation, recipe_snapshot
end

local function bounded_projection_subject(options, observer)
  local requested = type(options) == "table" and options.subject or nil
  if type(requested) ~= "table" then return nil end
  local subject = {}
  -- The fixture needs only this fixed provenance tuple. Do not let a test-only
  -- observation option smuggle an arbitrary object around the retained-output
  -- byte cap.
  for _, field in ipairs({"stream", "generated_technology", "prerequisite", "logistic_consumer"}) do
    local value = requested[field]
    if type(value) == "string" and #value > 0 and #value <= 256 then subject[field] = value end
  end
  if next(subject) == nil then return nil end
  return observer:reserve_output(subject) and subject or nil
end

local function indeterminate_projection(pack_name, prerequisite, options, observer, reason)
  local projection = {
    schema = 2,
    kind = "science-pack-production-rejection-projection",
    pack_name = pack_name,
    status = "indeterminate",
    prerequisite = prerequisite,
    candidate_count = 0,
    candidates = {},
    first_failure = {
      kind = "budget",
      identity = {type = "item", name = pack_name},
      reason = reason
    }
  }
  projection.subject = bounded_projection_subject(options, observer)
  projection.truncation = observer:metadata()
  return projection
end

local function rejection_projection_in_observation(pack_name, options)
  -- Do not call M.pack_production_status here: the projection owns a fresh
  -- CompilerContext and invokes the common core directly, so it cannot alter
  -- science_pack_production, science_pack_recipe_status, or telemetry in the
  -- caller's active compilation context.
  local observer = new_projection_observer(projection_limits(options))
  -- The initial status itself uses the bounded observer. It is not a normal
  -- planner preflight and cannot consume unmeasured work before projection.
  local status, prerequisite, initial_exists = resolve_pack_production_status(
    pack_name,
    {},
    {},
    observer:work_view()
  )
  if status == "indeterminate" then
    return indeterminate_projection(
      pack_name,
      prerequisite,
      options,
      observer,
      "diagnostic-work-budget-exhausted"
    )
  end
  if status ~= "unreachable" then return nil end

  local projection = {
    schema = 2,
    kind = "science-pack-production-rejection-projection",
    pack_name = pack_name,
    status = status,
    prerequisite = prerequisite,
    candidate_count = 0,
    candidates = {}
  }
  local subject = bounded_projection_subject(options, observer)
  if subject then
    -- This is assertion-only provenance supplied by an exact fixture. It
    -- binds a captured pack explanation to the generated stream/prerequisite
    -- under test without changing the queried graph or planner semantics.
    projection.subject = subject
  end
  -- The bounded status pass has already tested the physical prototype and its
  -- actual lab input. Do not repeat that scan with the same irreversible
  -- observer: an exact cap would otherwise turn a confirmed pack into a false
  -- no-lab identity failure during trace construction.
  if not initial_exists then
    projection.first_failure = {
      kind = "identity",
      identity = {type = "item", name = pack_name},
      reason = "not-a-lab-compatible-physical-science-pack"
    }
    projection.truncation = observer:metadata()
    return projection
  end

  local recipe_status = recipe_facts.pack_recipe_status(pack_name, observer)
  if diagnostic_indeterminate(observer) then
    return indeterminate_projection(
      pack_name,
      prerequisite,
      options,
      observer,
      "diagnostic-work-budget-exhausted"
    )
  end
  if not recipe_status or not recipe_status.has_recipe then
    projection.first_failure = {
      kind = "identity",
      identity = {type = "item", name = pack_name},
      reason = "no-pack-recipe"
    }
    projection.truncation = observer:metadata()
    return projection
  end

  local visiting_packs = {[pack_name] = true}
  local recipe_names = sorted_recipe_names(recipe_status, observer)
  for _, recipe_name in ipairs(recipe_names) do
    if observer:is_stopped() then break end
    if not observer:begin_candidate() then break end
    local candidate = rejection_candidate(
      recipe_name,
      pack_name,
      visiting_packs,
      {},
      observer
    )
    if not observer:reserve_output(candidate) then break end
    table.insert(projection.candidates, candidate)
  end
  projection.candidate_count = #recipe_names
  projection.truncation = observer:metadata()
  projection.first_failure = projection.candidates[1]
    and deepcopy(projection.candidates[1].first_failure)
    or (#projection.truncation.truncated > 0 and {
      kind = "budget",
      identity = {type = "item", name = pack_name},
      reason = "diagnostic-projection-truncated"
    })
    or {
      kind = "identity",
      identity = {type = "item", name = pack_name},
      reason = "no-candidate-recipes"
    }
  return projection
end

function M.pack_production_rejection_projection(pack_name, options)
  local observation, recipe_snapshot = observation_context()
  return compiler_context.with_active(observation, function()
    if not recipe_snapshot then
      local observer = new_projection_observer(projection_limits(options))
      observer:mark_unavailable("recipe-index")
      return indeterminate_projection(
        pack_name,
        nil,
        options,
        observer,
        "diagnostic-recipe-index-unavailable"
      )
    end
    local projection = rejection_projection_in_observation(pack_name, options)
    if not observation_recipe_snapshot_is_current(recipe_snapshot) then
      local observer = new_projection_observer(projection_limits(options))
      observer:mark_unavailable("recipe-index-lifetime")
      return indeterminate_projection(
        pack_name,
        nil,
        options,
        observer,
        "diagnostic-recipe-index-lifetime-changed"
      )
    end
    return projection
  end)
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
  visiting_technologies,
  observer
)
  if not pack_name or not excluded_unlocker or not pack_registry.science_pack_exists(pack_name, observer) then return nil end
  -- This witness is deliberately independent of an unlocker. A direct source
  -- remains valid even if the pack also has a recipe unlocked by the
  -- technology under assessment.
  local direct_source = route_feasibility.source_witness(pack_name, observer and {diagnostic_observer = observer} or nil)
  if direct_source then return direct_source end
  local recipe_status = recipe_facts.pack_recipe_status(pack_name, observer)
  if diagnostic_indeterminate(observer) then return nil end
  if not recipe_status or not recipe_status.has_recipe then return nil end

  local witness_visiting = copy_visitation_without(visiting_packs, pack_name)
  witness_visiting[pack_name] = true
  local selected = route_policy.select(production_routes(
    recipe_status,
    witness_visiting,
    excluded_unlocker,
    visiting_technologies,
    observer
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

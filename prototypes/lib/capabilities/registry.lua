local D = require("prototypes.diagnostics")
local fact_registry = require("prototypes.lib.facts.registry")
local lookup = require("prototypes.lib.prototype-lookup")

local C = {}

-- Capability resolvers are report-first. They classify prototype evidence and
-- explain how existing MIR streams treat it; they do not emit technologies.

local ENTITY_TYPES = {
  "accumulator",
  "ammo-turret",
  "assembling-machine",
  "beacon",
  "boiler",
  "burner-generator",
  "container",
  "electric-energy-interface",
  "electric-pole",
  "furnace",
  "generator",
  "inserter",
  "lab",
  "loader",
  "loader-1x1",
  "logistic-container",
  "mining-drill",
  "pipe",
  "pipe-to-ground",
  "pump",
  "radar",
  "reactor",
  "rocket-silo",
  "roboport",
  "solar-panel",
  "splitter",
  "storage-tank",
  "transport-belt",
  "underground-belt"
}

local NATIVE_MODIFIERS = {
  ["belt-stack-size-bonus"] = "native_logistics_modifier",
  ["inserter-stack-size-bonus"] = "native_logistics_modifier",
  ["laboratory-productivity"] = "science_modifier",
  ["laboratory-speed"] = "science_modifier",
  ["mining-drill-productivity-bonus"] = "native_mining_yield",
  ["worker-robot-battery"] = "robot_modifier",
  ["worker-robot-speed"] = "robot_modifier",
  ["worker-robot-storage"] = "robot_modifier"
}

local RESOLVERS = {
  {
    id = "logistics-loader-manufacturing",
    family = "logistics_item",
    subfamily = "loader",
    source = "capability:loader-resolver",
    policy = "existing_stream_or_report"
  },
  {
    id = "mining-drill-manufacturing",
    family = "machine_manufacturing",
    subfamily = "mining_drill",
    source = "capability:mining-drill-resolver",
    policy = "existing_stream_or_report"
  },
  {
    id = "native-modifier-ownership",
    family = "native_modifier",
    subfamily = "owner_registry",
    source = "capability:native-modifier-resolver",
    policy = "diagnose_only"
  }
}

local function sorted_keys(tbl)
  return fact_registry.sorted_keys(tbl or {})
end

local function push_unique(list, seen, value)
  if value and not seen[value] then
    seen[value] = true
    table.insert(list, value)
  end
end

local function join_names(list)
  local copy = {}
  for _, value in ipairs(list or {}) do
    table.insert(copy, tostring(value))
  end
  table.sort(copy)
  return table.concat(copy, ",")
end

local function format_bool(value)
  if value then return "true" end
  return "false"
end

local function entity_prototype(name)
  if not name then return nil, nil end
  for _, entity_type in ipairs(ENTITY_TYPES) do
    local bucket = data.raw[entity_type]
    if bucket and bucket[name] then return bucket[name], entity_type end
  end
  return nil, nil
end

local function recipe_outputs_by_item(registry)
  local by_item = {}
  for _, recipe_name in ipairs(sorted_keys(registry.recipes)) do
    local recipe = registry.recipes[recipe_name]
    for _, result in ipairs(recipe.results or {}) do
      by_item[result.name] = by_item[result.name] or {}
      table.insert(by_item[result.name], recipe_name)
    end
  end
  return by_item
end

local function recipe_owner_maps(registry)
  local mir = {}
  local external = {}

  for _, owner in ipairs(registry.owners or {}) do
    if owner.subject_type == "recipe" and owner.subject then
      local target = owner.mod_owner == "more-infinite-research" and mir or external
      target[owner.subject] = target[owner.subject] or {}
      table.insert(target[owner.subject], owner.technology)
    end
  end

  return mir, external
end

local function entity_backed_candidates(registry, wanted_entity_types)
  local recipes_by_item = recipe_outputs_by_item(registry)
  local candidates = {}
  local seen = {}

  lookup.each_item_prototype(function(item_name, item, item_type)
    local place_result = item and item.place_result
    if not place_result then return end

    local _, entity_type = entity_prototype(place_result)
    if not entity_type or not wanted_entity_types[entity_type] then return end

    for _, recipe_name in ipairs(recipes_by_item[item_name] or {}) do
      local key = recipe_name .. "|" .. item_name
      if not seen[key] then
        seen[key] = true
        table.insert(candidates, {
          item = item_name,
          item_type = item_type,
          recipe = recipe_name,
          recipe_fact = registry.recipes[recipe_name],
          entity = place_result,
          entity_type = entity_type
        })
      end
    end
  end)

  table.sort(candidates, function(a, b)
    if a.recipe ~= b.recipe then return a.recipe < b.recipe end
    return a.item < b.item
  end)

  return candidates
end

local function ownership_decision(recipe_name, mir_owners, external_owners)
  if mir_owners[recipe_name] and #mir_owners[recipe_name] > 0 then
    return "generate_stream", true, "", mir_owners[recipe_name]
  end
  if external_owners[recipe_name] and #external_owners[recipe_name] > 0 then
    return "diagnose_only", false, join_names(external_owners[recipe_name]), external_owners[recipe_name]
  end
  return "propose_stream", false, "no_existing_recipe_productivity_owner", {}
end

local function evidence_for(candidate)
  return table.concat({
    "item_type:" .. tostring(candidate.item_type),
    "item_place_result:" .. tostring(candidate.entity),
    "entity_type:" .. tostring(candidate.entity_type),
    "recipe_outputs_item:" .. tostring(candidate.item)
  }, ",")
end

local function emit_recipe_capability_decisions(registry, resolver, wanted_entity_types)
  local mir_owners, external_owners = recipe_owner_maps(registry)
  local generated = 0
  local proposed = 0
  local diagnosed = 0
  local candidates = entity_backed_candidates(registry, wanted_entity_types)

  for _, candidate in ipairs(candidates) do
    local recipe = candidate.recipe_fact or {}
    local decision, emitted, blockers, owners = ownership_decision(candidate.recipe, mir_owners, external_owners)
    if emitted then
      generated = generated + 1
    elseif decision == "propose_stream" then
      proposed = proposed + 1
    else
      diagnosed = diagnosed + 1
    end

    D.decision({
      key = candidate.recipe,
      status = "diagnostic",
      reason = emitted and "entity_backed_recipe_stream_generated" or "entity_backed_recipe_stream_not_emitted",
      subject_type = "recipe",
      subject = candidate.recipe,
      capability = resolver.id,
      family = resolver.family,
      subfamily = resolver.subfamily,
      confidence = recipe.allow_productivity and "family=0.95,owner=1,total=0.95" or "family=0.95,owner=0.5,total=0.7",
      source = resolver.source,
      policy = resolver.policy,
      decision = decision,
      emitted = format_bool(emitted),
      blockers = blockers,
      risks = recipe.allow_productivity and "" or "recipe_productivity_not_explicitly_allowed",
      stable_stream_id = emitted and join_names(owners) or "",
      recipe = candidate.recipe,
      recipes = candidate.recipe,
      target = candidate.item,
      effect = "change-recipe-productivity",
      evidence = evidence_for(candidate)
    })
  end

  D.compatibility_plan({
    key = "capability:" .. resolver.id,
    status = "diagnostic",
    reason = "capability_resolver_summary",
    capability = resolver.id,
    family = resolver.family,
    subfamily = resolver.subfamily,
    total = tostring(#candidates),
    generated = tostring(generated),
    unknown = tostring(proposed),
    warnings = tostring(diagnosed),
    evidence = "entity_backed_item_recipe_scan"
  })

  return #candidates, generated, proposed, diagnosed
end

local function native_owner_summary(registry)
  local by_effect = {}

  for _, owner in ipairs(registry.owners or {}) do
    local subfamily = NATIVE_MODIFIERS[owner.effect_type]
    if subfamily then
      by_effect[owner.effect_type] = by_effect[owner.effect_type] or {
        effect_type = owner.effect_type,
        subfamily = subfamily,
        technologies = {},
        technologies_seen = {},
        mir = 0,
        external = 0
      }

      local row = by_effect[owner.effect_type]
      push_unique(row.technologies, row.technologies_seen, owner.technology)
      if owner.mod_owner == "more-infinite-research" then
        row.mir = row.mir + 1
      else
        row.external = row.external + 1
      end
    end
  end

  return by_effect
end

local function emit_native_modifier_decisions(registry, resolver)
  local rows = native_owner_summary(registry)
  local total = 0
  local warnings = 0

  for _, effect_type in ipairs(sorted_keys(rows)) do
    local row = rows[effect_type]
    total = total + 1
    if row.external > 0 then warnings = warnings + 1 end

    D.decision({
      key = effect_type,
      status = "diagnostic",
      reason = row.external > 0 and "native_modifier_external_owner_observed" or "native_modifier_mir_owner_observed",
      subject_type = "modifier",
      subject = effect_type,
      capability = resolver.id,
      family = resolver.family,
      subfamily = row.subfamily,
      confidence = "owner=1,total=1",
      source = resolver.source,
      policy = row.external > 0 and "prefer_existing_owner" or resolver.policy,
      decision = "observe_existing_owner",
      emitted = "false",
      blockers = row.external > 0 and "external_native_modifier_owner" or "",
      risks = row.external > 0 and "duplicate_native_modifier_owner" or "",
      technologies = join_names(row.technologies),
      evidence = "technology_effect_type:" .. effect_type,
      total = tostring(row.mir + row.external),
      mir_owned = tostring(row.mir),
      external_owned_unknown = tostring(row.external)
    })
  end

  D.compatibility_plan({
    key = "capability:" .. resolver.id,
    status = "diagnostic",
    reason = "native_modifier_ownership_summary",
    capability = resolver.id,
    family = resolver.family,
    subfamily = resolver.subfamily,
    total = tostring(total),
    warnings = tostring(warnings),
    evidence = "technology_effect_scan"
  })

  return total, 0, 0, warnings
end

function C.resolvers()
  return RESOLVERS
end

function C.emit(registry)
  if not D.enabled() then return end

  local total = 0
  local generated = 0
  local proposed = 0
  local warnings = 0

  local count, gen, prop, warn = emit_recipe_capability_decisions(
    registry,
    RESOLVERS[1],
    {loader = true, ["loader-1x1"] = true}
  )
  total = total + count
  generated = generated + gen
  proposed = proposed + prop
  warnings = warnings + warn

  count, gen, prop, warn = emit_recipe_capability_decisions(
    registry,
    RESOLVERS[2],
    {["mining-drill"] = true}
  )
  total = total + count
  generated = generated + gen
  proposed = proposed + prop
  warnings = warnings + warn

  count, gen, prop, warn = emit_native_modifier_decisions(registry, RESOLVERS[3])
  total = total + count
  generated = generated + gen
  proposed = proposed + prop
  warnings = warnings + warn

  D.compatibility_plan({
    key = "capability_registry",
    status = "diagnostic",
    reason = "capability_resolvers_reported",
    capability = "registry",
    total = tostring(total),
    generated = tostring(generated),
    unknown = tostring(proposed),
    warnings = tostring(warnings),
    evidence = "discover,classify,propose,validate,emit,diagnose"
  })
end

return C

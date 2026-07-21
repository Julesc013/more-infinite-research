local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local relationships = require("prototypes.mir.index.relationships")
local rule_registry = require("prototypes.mir.families.registry")
local policy_authority = require("prototypes.mir.compatibility.policy_authority")
local productivity_owners = require("prototypes.mir.index.productivity_owners")
local competing_productivity = require("prototypes.mir.policy.competing_productivity")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local operator_dsl = require("prototypes.mir.families.operator_dsl")

local M = {}

local HARD_BLOCKERS = {
  recipe_fact_missing = true,
  recipe_productivity_not_allowed = true,
  variant_productivity_not_allowed = true,
  zero_productivity_cap = true,
  variant_zero_productivity_cap = true,
  parameter_recipe = true,
  recycling_recipe = true,
  self_return_risk = true,
  non_exclusive_placeable_output = true,
  non_deterministic_placeable_output = true,
  existing_recipe_productivity_owner = true
}

local function infer_seed_item(seed, fact)
  if seed.item then return seed.item end
  local names, seen = {}, {}
  for _, result in ipairs((fact and fact.results) or {}) do
    if result.type == "item" and result.name and not seen[result.name] then
      seen[result.name] = true
      table.insert(names, result.name)
    end
  end
  if #names == 1 then return names[1] end
  return nil
end

local function candidates_for_rule(rule, indexes, seeds)
  local by_key = {}
  local stream = operator_dsl.grouping_stream(rule.operators)
  for _, item_name in ipairs(operator_dsl.candidate_items(rule.operators, indexes)) do
    for _, recipe_name in ipairs(indexes.recipes_by_output[item_name] or {}) do
      by_key[recipe_name .. "\0" .. item_name] = {
        recipe = recipe_name,
        item = item_name,
        source = "structural"
      }
    end
  end
  for _, seed in ipairs(seeds or {}) do
    if seed.family == rule.id and seed.stream == stream then
      local fact = recipe_facts.view(seed.recipe)
      local item_name = infer_seed_item(seed, fact)
      if not item_name then
        error("CompatibilityPack candidate seed requires an exact item for ambiguous recipe " .. seed.recipe, 2)
      end
      by_key[seed.recipe .. "\0" .. item_name] = {
        recipe = seed.recipe,
        item = item_name,
        source = "compatibility-pack-seed",
        pack = seed.pack,
        evidence = deepcopy(seed.evidence),
        change = seed.change,
        tier = seed.tier
      }
    end
  end
  local out = {}
  for _, candidate in pairs(by_key) do table.insert(out, candidate) end
  table.sort(out, function(a, b)
    if a.recipe ~= b.recipe then return a.recipe < b.recipe end
    return a.item < b.item
  end)
  return out
end

local function build()
  local context = compiler_context.current()
  local canonical = context:state_view("family_resolution")
  if canonical then return canonical end
  local indexes = relationships.view()
  local rules = rule_registry.snapshot().rules
  local seeds = policy_authority.candidate_seeds()
  local attachments, decisions, ownership = {}, {}, {}

  for _, seed in ipairs(seeds) do
    local matched = false
    for _, rule in ipairs(rules) do
      if seed.family == rule.id and seed.stream == operator_dsl.grouping_stream(rule.operators) then matched = true; break end
    end
    if not matched then
      error("CompatibilityPack candidate seed references unknown family/stream: " .. seed.family .. "/" .. seed.stream, 2)
    end
  end

  for _, rule in ipairs(rules) do
    local target_stream = operator_dsl.grouping_stream(rule.operators)
    for _, candidate in ipairs(candidates_for_rule(rule, indexes, seeds)) do
        local item_name, recipe_name = candidate.item, candidate.recipe
        local fact = recipe_facts.view(recipe_name)
        local eligible, blocker = operator_dsl.eligibility(rule.operators, fact, item_name)
        local pack_decision = policy_authority.resolve_candidate({
          recipe = recipe_name,
          item = item_name,
          family = rule.id,
          stream = target_stream,
          blocker = blocker
        })
        if pack_decision.action == "attach" and (blocker == nil or policy_authority.blocker_is_reviewable(blocker)) then
          eligible, blocker = true, nil
        elseif pack_decision.action == "diagnose" then
          eligible, blocker = false, pack_decision.reason or blocker
        end
        if blocker and HARD_BLOCKERS[blocker] then eligible = false end
        local external_owners = productivity_owners.blocking_recipe_productivity_owner_records(recipe_name, {
          ignore_owner = competing_productivity.ignores_existing_owner,
          snapshot_phase = "input"
        })
        if #external_owners > 0 then eligible, blocker = false, "existing_recipe_productivity_owner" end

        local change = operator_dsl.effect_change(rule.operators, candidate, indexes)
        if tonumber(pack_decision.change) then change = tonumber(pack_decision.change) end

        local decision = operator_dsl.grouping_action(rule.operators)
        if not eligible then decision = "diagnose" end
        table.insert(decisions, {
          schema = 2,
          provider_id = rule.provider_id,
          rule = rule.id,
          source_key = "recipe:" .. recipe_name,
          prototype_type = "recipe",
          prototype_name = recipe_name,
          capability = rule.capability,
          candidate_family = rule.family,
          recipe = recipe_name,
          item = item_name,
          target_stream = target_stream,
          final_state = decision,
          decision = decision,
          blocker = blocker or rule.blocker,
          change = change,
          policy_scope = "automatic-productivity",
          identity_seed = rule.provider_id .. "\0" .. recipe_name .. "\0" .. item_name,
          diagnostic_provenance = {provider = rule.provider_id, evidence = deepcopy(rule.required_evidence)},
          target_support = deepcopy(rule.targets),
          emission = {adapter = "generation-plan-family-rule", mutates_prototypes = false},
          candidate_source = candidate.source,
          compatibility_pack = candidate.pack or pack_decision.pack,
          evidence = candidate.evidence or pack_decision.evidence
        })

        if eligible and decision == "attach" then
          local previous = ownership[recipe_name]
          if previous and previous ~= target_stream then
            error("FamilyRule attachment is ambiguous for recipe " .. recipe_name, 2)
          end
          ownership[recipe_name] = target_stream
          attachments[target_stream] = attachments[target_stream] or {}
          table.insert(attachments[target_stream], {
            recipe = recipe_name,
            change = change,
            rule = rule.id,
            provider_id = rule.provider_id
          })
        end
    end
  end

  for _, rows in pairs(attachments) do
    table.sort(rows, function(a, b)
      if a.change ~= b.change then return a.change > b.change end
      return a.recipe < b.recipe
    end)
  end
  table.sort(decisions, function(a, b)
    if a.rule ~= b.rule then return a.rule < b.rule end
    return a.recipe < b.recipe
  end)
  canonical = {schema = 2, attachments = attachments, decisions = decisions}
  return context:set_state("family_resolution", canonical)
end

function M.attachments_for_stream(stream_key)
  return deepcopy(build().attachments[stream_key] or {})
end

function M.provider_ids_for_stream(stream_key)
  local ids, seen = {}, {}
  for _, attachment in ipairs(build().attachments[stream_key] or {}) do
    if not seen[attachment.provider_id] then
      seen[attachment.provider_id] = true
      table.insert(ids, attachment.provider_id)
    end
  end
  table.sort(ids)
  return ids
end

function M.family_ids_for_stream(stream_key)
  local ids, seen = {}, {}
  for _, decision in ipairs(build().decisions or {}) do
    if decision.target_stream == stream_key and decision.candidate_family
      and not seen[decision.candidate_family] then
      seen[decision.candidate_family] = true
      table.insert(ids, decision.candidate_family)
    end
  end
  table.sort(ids)
  return ids
end

function M.snapshot()
  return deepcopy(build())
end

return M

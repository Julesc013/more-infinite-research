local D = require("prototypes.diagnostics")
local capabilities = require("prototypes.lib.capabilities.registry")
local decision_record = require("prototypes.mir.domain.decisions.decision_record")
local decision_export = require("prototypes.mir.report.decision_export")
local fact_registry = require("prototypes.lib.facts.registry")
local productivity_owners = require("prototypes.compat.productivity-owners")

local M = {}

local function join_names(list)
  local out = {}
  for _, entry in ipairs(list or {}) do
    local value = entry.name or entry[1] or entry
    if value then table.insert(out, tostring(value)) end
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function count_owner_policies(owners)
  local counts = {}
  for _, owner in ipairs(owners or {}) do
    counts[owner.policy] = (counts[owner.policy] or 0) + 1
  end
  return counts
end

local function emit_fact_registry(registry)
  local s = registry.summary or {}
  D.fact_registry({
    key = "prototype_index",
    status = "diagnostic",
    reason = "facts_indexed",
    recipes = tostring(s.recipes or 0),
    technologies = tostring(s.technologies or 0),
    machines = tostring(s.machines or 0),
    labs = tostring(s.labs or 0),
    owners = tostring(s.owners or 0),
    rule_mutations = tostring(s.rule_mutations or 0),
    loop_risks = tostring(s.loop_risks or 0),
    generated = tostring(s.generated_technologies or 0)
  })

  D.compatibility_plan({
    key = "productivity_compiler",
    status = "diagnostic",
    reason = "fact_registry_summary",
    total = tostring(s.recipes or 0),
    recipes = tostring(s.recipes or 0),
    technologies = tostring(s.technologies or 0),
    warnings = tostring((s.rule_mutations or 0) + (s.loop_risks or 0))
  })
end

local function emit_owner_summary(registry)
  local counts = count_owner_policies(registry.owners)
  D.compatibility_plan({
    key = "owner_registry",
    status = "diagnostic",
    reason = "owner_facts_indexed",
    total = tostring(registry.summary.owners or 0),
    mir_owned = tostring(counts.mir_owned or 0),
    external_owned_exact = tostring(counts.external_owned_exact or 0),
    external_owned_unknown = tostring(counts.external_owned_unknown or 0)
  })
end

local function emit_lab_matrix(registry)
  local total_inputs = 0
  for _, lab_name in ipairs(fact_registry.sorted_keys(registry.labs)) do
    local lab = registry.labs[lab_name]
    total_inputs = total_inputs + #(lab.inputs or {})
    D.lab_matrix({
      key = lab_name,
      subject_type = "lab",
      subject = lab_name,
      status = "diagnostic",
      reason = "lab_inputs_indexed",
      science = join_names(lab.inputs),
      total = tostring(#(lab.inputs or {})),
      module_slots = tostring(lab.module_slots or 0),
      allowed_effects = join_names(lab.allowed_effects)
    })
  end

  D.compatibility_plan({
    key = "lab_matrix",
    status = "diagnostic",
    reason = "labs_indexed",
    total = tostring(registry.summary.labs or 0),
    science = tostring(total_inputs)
  })
end

local function emit_rule_mutations(registry)
  for _, fact in ipairs(registry.rule_mutations or {}) do
    D.rule_mutation({
      key = fact.subject,
      subject_type = fact.subject_type,
      subject = fact.subject,
      status = "diagnostic",
      reason = "external_rule_surface_observed",
      field = fact.field,
      observed_value = fact.observed_value,
      expected_baseline = fact.expected_baseline,
      likely_mutator_mod = fact.likely_mutator_mod or "",
      confidence = tostring(fact.confidence or "")
    })

    decision_export.emit(D, {
      key = fact.subject,
      subject_type = fact.subject_type,
      subject = fact.subject,
      family = "rule_mutation",
      confidence = decision_record.format_confidence({total = fact.confidence or 0.7}),
      source = "compiler:rule-mutation",
      policy = "diagnose_only",
      decision = "diagnose_only",
      emitted = "false",
      reason = "external_rule_surface_observed",
      blockers = fact.field,
      risks = "rule_mutation"
    })
  end
end

local function emit_loop_risks(registry)
  for _, fact in ipairs(registry.loop_risks or {}) do
    local flags = join_names(fact.risk_flags)
    D.loop_risk({
      key = fact.subject,
      subject_type = fact.subject_type,
      subject = fact.subject,
      status = "diagnostic",
      reason = "loop_risk_flags",
      risks = flags,
      shared_inputs_outputs = join_names(fact.shared_inputs_outputs),
      confidence = tostring(fact.confidence or "")
    })

    decision_export.emit(D, {
      key = fact.subject,
      subject_type = fact.subject_type,
      subject = fact.subject,
      family = "recipe_graph_risk",
      confidence = decision_record.format_confidence({loop_safety = 0.25, total = 0.25}),
      source = "compiler:loop-risk",
      policy = "diagnose_only",
      decision = "diagnose_only",
      emitted = "false",
      reason = "loop_risk_flags",
      blockers = flags,
      risks = flags
    })
  end
end

local function emit_generated_technology_decisions(registry)
  for _, tech_name in ipairs(fact_registry.sorted_keys(registry.technologies)) do
    if productivity_owners.is_mir_recipe_productivity_tech(tech_name) then
      local fact = registry.technologies[tech_name]
      local labs = fact_registry.labs_for_packs(registry.labs, fact.science_packs)
      local lab_compatible = #labs > 0
      decision_export.emit(D, decision_record.generated_technology({
        technology_name = tech_name,
        lab_compatible = lab_compatible,
        effect_count = fact.effect_count or 0,
        science = join_names(fact.science_packs),
        labs = join_names(labs),
        stable_stream_id = tech_name
      }))
    end
  end
end

function M.emit()
  if not D.enabled() then return end

  local registry = fact_registry.build()
  emit_fact_registry(registry)
  emit_owner_summary(registry)
  emit_lab_matrix(registry)
  emit_rule_mutations(registry)
  emit_loop_risks(registry)
  emit_generated_technology_decisions(registry)
  capabilities.emit(registry)
end

return M

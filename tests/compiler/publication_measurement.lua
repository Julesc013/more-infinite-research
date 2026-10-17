-- Controlled publication fixture. It executes the real publication module
-- with bounded test doubles; it does not measure native startup performance.
local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  if not condition then error(message) end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

-- Load actual public projection and journal contracts before this controlled
-- publication fixture substitutes its bounded module doubles below.
local actual_deepcopy = require("prototypes.mir.core.deepcopy")
local actual_fingerprint = require("prototypes.mir.core.fingerprint")
local actual_public_artifacts = require("prototypes.mir.report.public_compiler_artifacts")
local actual_public_artifact_budget = require("prototypes.mir.domain.compiler.public_artifact_budget")
local actual_compiler_evidence = require("prototypes.mir.domain.evidence.compiler_evidence")
local actual_transformation_plan = require("prototypes.mir.domain.compiler.transformation_plan")
local actual_mutation_journal = require("prototypes.mir.domain.compiler.mutation_journal")

local state = {}
local telemetry = {}

-- The publication module must not make an ordinary full copy of final-result
-- or selected diagnostic records. The wrapper is installed before it loads.
package.loaded["prototypes.mir.core.deepcopy"] = function(value)
  if type(value) == "table" and value._publication_copy_probe then
    state.probe_deepcopy_calls = (state.probe_deepcopy_calls or 0) + 1
  end
  return actual_deepcopy(value)
end

local function canonical(value)
  return actual_fingerprint.canonical(value)
end

local function actual_evidence_input()
  return {
    compilation_plan_schema = 2,
    compilation_fingerprint = "mir32-compilation",
    qualification_fingerprint = "mir32-qualification",
    telemetry = {schema = 1, counters = {public_bytes = 17}, phases = {}, witnesses = {}},
    compiler_result = {
      schema = 3,
      result_phase = "final",
      result_fingerprint = "mir32-result",
      planned_result_fingerprint = "mir32-planned",
      status = "PASS",
      dimensions = {execution = "APPLIED", safety = "QUALIFIED", release = "ELIGIBLE"},
      execution_evidence = {journal_fingerprint = "mir32-journal", applied = 1},
      ignored_full_result_material = {payload = {"large", "unexported", "projection"}}
    },
    mutation_journal = {
      schema = 2,
      plan_fingerprint = "mir32-plan",
      journal_fingerprint = "mir32-journal",
      required_operation_count = 1,
      terminal_counts = {applied = 1, failed = 0},
      missing_operation_count = 0,
      duplicate_operation_count = 0,
      undeclared_operation_count = 0,
      out_of_plan_operation_count = 0,
      complete = true,
      entries = {{before_snapshot = {unexported = true}, after_projection = {unexported = true}}}
    },
    input_sanitation_ledger = {
      schema = 1, pass = "input", scanned_technology_count = 2,
      scanned_effect_count = 3, pruned_effect_count = 1, affected_technology_count = 1,
      generated_technology_count = 1, external_technology_count = 1,
      emptied_technology_count = 0, sanitized_target_inventory_fingerprint = "mir32-target",
      technologies = {{original_technology = "ignored-ledger-row", retained_effects = {"x"}}}
    },
    output_sanitation_ledger = {
      schema = 1, pass = "output", scanned_technology_count = 2,
      scanned_effect_count = 3, pruned_effect_count = 1, affected_technology_count = 1,
      generated_technology_count = 1, external_technology_count = 1,
      emptied_technology_count = 0, sanitized_target_inventory_fingerprint = "mir32-target",
      technologies = {{original_technology = "ignored-ledger-row", retained_effects = {"x"}}}
    }
  }
end

local publication_plan = actual_transformation_plan.new({
  phase = "publication", execution_mode = "SAFE",
  compilation_snapshot_fingerprint = "mir32-snapshot", policy_fingerprint = "mir32-policy",
  operations = {}
})
local publication_journal = actual_mutation_journal.new(publication_plan)
local prefinal_ok, prefinal_message = pcall(function() return publication_journal:publication_summary() end)
check(not prefinal_ok and string.find(tostring(prefinal_message), "requires finalization", 1, true),
  "journal rejects a public summary before finalization")
publication_journal:finalize()
local isolated_summary = publication_journal:publication_summary()
check(isolated_summary.entries == nil and isolated_summary.violations == nil
  and isolated_summary.terminal_counts.applied == 0,
  "journal public summary excludes operation material")
isolated_summary.terminal_counts.applied = 99
check(publication_journal:publication_summary().terminal_counts.applied == 0,
  "journal public summary is copy-isolated")

local actual_input = actual_evidence_input()
local actual_public_full = actual_public_artifacts.compiler_evidence(actual_input)
local actual_public_full_bytes = canonical(actual_public_full)
local actual_summary_input = copy(actual_input)
actual_summary_input.mutation_journal.entries = nil
local actual_public_summary = actual_public_artifacts.compiler_evidence(actual_summary_input)
check(canonical(actual_public_summary) == actual_public_full_bytes,
  "actual public evidence ignores complete journal operation rows")
local actual_ignored_result = copy(actual_summary_input)
actual_ignored_result.compiler_result.ignored_full_result_material.payload[1] = "changed-unexported"
check(canonical(actual_public_artifacts.compiler_evidence(actual_ignored_result)) == actual_public_full_bytes,
  "actual public evidence ignores complete result-only projection material")
local function actual_evidence_changes(mutator)
  local changed = copy(actual_summary_input)
  mutator(changed)
  return canonical(actual_public_artifacts.compiler_evidence(changed)) ~= actual_public_full_bytes
end
check(actual_evidence_changes(function(value) value.compiler_result.dimensions.release = "BLOCKED" end),
  "actual public evidence binds result dimensions")
check(actual_evidence_changes(function(value) value.compiler_result.execution_evidence.applied = 2 end),
  "actual public evidence binds execution evidence")
check(actual_evidence_changes(function(value) value.mutation_journal.terminal_counts.applied = 2 end),
  "actual public evidence binds journal terminal counts")
check(actual_evidence_changes(function(value) value.input_sanitation_ledger.technologies[1].retained_effects[1] = "changed" end),
  "actual public evidence binds complete sanitation ledgers")
actual_summary_input.compiler_result.dimensions.release = "MUTATED_AFTER_BUILD"
actual_summary_input.mutation_journal.terminal_counts.applied = 44
check(canonical(actual_public_summary) == actual_public_full_bytes,
  "actual public evidence defensively isolates returned result and journal rows")

-- The real public builders return an owned exact final byte count beside the
-- ordinary first return. Independently canonicalize the final record here;
-- generic budget validation deliberately remains a separate fresh traversal.
local function check_owned_public_bytes(label, build, input, field)
  local public, owned_bytes = build(input)
  local independently_counted = #canonical(public)
  check(owned_bytes == independently_counted,
    label .. " derives exact final canonical bytes from the pre-fingerprint text")
  check(actual_public_artifacts.assert_byte_budget(public) == independently_counted,
    label .. " generic budget guard independently validates the final public record")
  local pre_fingerprint = copy(public)
  pre_fingerprint[field] = nil
  check(public[field] == actual_fingerprint.of(pre_fingerprint),
    label .. " retains the established pre-field self-fingerprint formula")
  return public, owned_bytes
end

local public_plan_input = {
  schema = 3, plan_fingerprint = "mir32-plan", source_fingerprints = {},
  validation_summary = {accepted = 1},
  rows = {{stream_key = "fixture", action = "emit", reason = "accepted", technology_name = "fixture-tech",
    gates = {hard = true}, fields = {effects = {}}}}
}
local public_plan, public_plan_bytes = check_owned_public_bytes("generation plan",
  actual_public_artifacts.generation_plan, public_plan_input, "public_fingerprint")
public_plan.rows[1].reason = "mutated-returned-projection"
check(actual_public_artifacts.generation_plan(public_plan_input).rows[1].reason == "accepted",
  "owned public plan projection is copy isolated from a returned-record mutation")
local public_coverage, public_coverage_bytes = check_owned_public_bytes("coverage",
  actual_public_artifacts.coverage, {schema = 1, summary = {total_recipes = 1}}, "public_fingerprint")
local public_catalog, public_catalog_bytes = check_owned_public_bytes("technology catalog",
  actual_public_artifacts.technology_catalog, {
    schema = 4, phase = "final", catalog_fingerprint = "mir32-catalog",
    alternative_evaluation = {mode = "full-diagnostics", complete = true,
      evaluated_alternatives = 0, deferred_diagnostic_alternatives = 0,
      deferred_rejected_diagnostic_alternatives = 0},
    current_selections = {}, candidates = {}, qualifications = {}
  }, "public_fingerprint")
local public_evidence, public_evidence_bytes = check_owned_public_bytes("compiler evidence",
  actual_public_artifacts.compiler_evidence, actual_evidence_input(), "evidence_fingerprint")
check(public_plan_bytes > 0 and public_coverage_bytes > 0 and public_catalog_bytes > 0
    and public_evidence_bytes > 0, "owned public byte counts remain positive scalars")

public_plan.rows[1].reason = "post-return-mutation-with-a-different-canonical-length"
check(actual_public_artifacts.assert_byte_budget(public_plan) ~= public_plan_bytes,
  "generic budget guard reserializes a post-return public mutation instead of accepting an owned scalar")
public_plan.cycle = public_plan
local cycle_ok, cycle_message = pcall(function() actual_public_artifacts.assert_byte_budget(public_plan) end)
check(not cycle_ok and string.find(tostring(cycle_message), "Cannot fingerprint cyclic table", 1, true),
  "generic budget guard rejects a post-return public cycle")
local overflow_ok, overflow_message = pcall(function()
  actual_public_artifacts.assert_byte_budget({kind = "mir-compiler-evidence-public", payload = string.rep("x", 131072)})
end)
check(not overflow_ok and string.find(tostring(overflow_message), "exceeds its hard byte budget", 1, true),
  "generic budget guard retains overflow refusal for an arbitrary public record")
local unknown_kind_cycle = {kind = "mir-unknown-public-artifact"}
unknown_kind_cycle.self = unknown_kind_cycle
local unknown_kind_ok, unknown_kind_message = pcall(function()
  actual_public_artifacts.assert_byte_budget(unknown_kind_cycle)
end)
check(not unknown_kind_ok and string.find(tostring(unknown_kind_message), "Unknown MIR public artifact byte budget", 1, true),
  "generic budget guard resolves unknown artifact kind before canonicalizing arbitrary material")
local invalid_count_ok, invalid_count_message = pcall(function()
  actual_public_artifact_budget.assert_byte_count_within_limit("mir-coverage-public", -1)
end)
check(not invalid_count_ok and string.find(tostring(invalid_count_message), "Owned public artifact byte count is invalid.", 1, true),
  "shared owned scalar boundary rejects an invalid byte count")

local actual_internal_input = actual_evidence_input()
actual_internal_input.compiler_input_fingerprint = "mir32-input"
actual_internal_input.compiler_result_fingerprint = "mir32-result"
actual_internal_input.technology_catalog_fingerprint = "mir32-catalog"
actual_internal_input.technology_graph_parity = {valid = true, rows = {{technology = "mir32-tech"}}}
actual_internal_input.provider_resolution = {rows = {{provider = "mir32-provider"}}}
actual_internal_input.provider_decision_diagnostics = {
  {kind = "decision", reason = "canonical_provider_decision_projection", payload = {complete = true}}
}
local internal_copied_input = copy(actual_internal_input)
local actual_internal_bytes = canonical(actual_compiler_evidence.build(internal_copied_input))
check(canonical(actual_compiler_evidence.build(actual_internal_input)) == actual_internal_bytes,
  "actual internal evidence retains complete journal, parity, and decision rows from owned inputs")

local function reset(mod_data_supported, factorio_version, reject_evidence_budget, diagnostics_enabled, owned_boundary_kind, owned_boundary_bytes)
  state = {
    mod_data_supported = mod_data_supported,
    factorio_version = factorio_version,
    reject_evidence_budget = reject_evidence_budget,
    diagnostics_enabled = diagnostics_enabled,
    owned_boundary_kind = owned_boundary_kind,
    owned_boundary_bytes = owned_boundary_bytes,
    counters = {
      generation_plan_public_bytes = 0,
      technology_catalog_public_bytes = 0,
      coverage_public_bytes = 0,
      research_cost_support_public_bytes = 0,
      compiler_evidence_public_bytes = 0,
      public_artifact_total_bytes = 0
    },
    evidence_constructions = 0,
    internal_constructions = 0,
    work_volume_records = 0,
    budget_calls = {},
    adapter_calls = {},
    generation_plan_constructions = 0,
    catalog_constructions = 0,
    coverage_publications = 0,
    probe_deepcopy_calls = 0,
    journal_summary_calls = 0,
    journal_snapshot_calls = 0,
    diagnostics_accesses = 0,
    artifact_calls = {}
  }
end

function telemetry.count(name, amount)
  state.counters[name] = (state.counters[name] or 0) + (amount or 1)
  return state.counters[name]
end

function telemetry.observe_max(name, value)
  state.counters[name] = math.max(state.counters[name] or 0, tonumber(value) or 0)
end

function telemetry.snapshot()
  return {schema = 1, counters = copy(state.counters), phases = {}, witnesses = {}}
end

package.loaded["prototypes.mir.pipeline.compiler_orchestrator.context_construction"] = {
  compile = function(context) return context.plan end,
  record_work_volume = function() state.work_volume_records = state.work_volume_records + 1 end,
  maximum_level_policy = function() return nil end
}
package.loaded["prototypes.mir.pipeline.compiler_context"] = {current = function() error("fixture context required") end}
package.loaded["prototypes.mir.domain.evidence.compiler_evidence"] = {
  build = function(input)
    state.internal_constructions = state.internal_constructions + 1
    state.internal_input = input
    return {kind = "internal-evidence", compilation_fingerprint = input.compilation_fingerprint}
  end
}
package.loaded["prototypes.mir.families.resolver"] = {
  inspection_snapshot = function()
    state.provider_inspection_calls = (state.provider_inspection_calls or 0) + 1
    return {providers = {{provider_id = "mir32-provider", full_metrics = {unexported = true}}}}
  end
}
package.loaded["prototypes.mir.report.compiler_telemetry"] = telemetry
package.loaded["prototypes.mir.report.diagnostics_sink"] = {enabled = function() return state.diagnostics_enabled end}
local function owned_public(kind, bytes, fields)
  local selected = state.owned_boundary_kind == kind and state.owned_boundary_bytes or bytes
  fields = fields or {}
  fields.kind = kind
  fields.bytes = selected
  return fields, selected
end

package.loaded["prototypes.mir.report.public_compiler_artifacts"] = {
  generation_plan = function()
    state.generation_plan_constructions = state.generation_plan_constructions + 1
    return owned_public("mir-generation-plan-public", 11)
  end,
  technology_catalog = function()
    state.catalog_constructions = state.catalog_constructions + 1
    return owned_public("mir-technology-catalog-public", 13)
  end,
  compiler_evidence = function(input)
    state.evidence_constructions = state.evidence_constructions + 1
    state.public_input = input
    state.evidence_telemetry = copy(input.telemetry)
    return owned_public("mir-compiler-evidence-public", 17, {
      compilation_fingerprint = input.compilation_fingerprint,
      qualification_fingerprint = input.qualification_fingerprint,
      telemetry = copy(input.telemetry)
    })
  end,
  research_cost_compatibility = function() return {kind = "research-cost", bytes = 19} end,
  assert_byte_budget = function(artifact)
    state.budget_calls[artifact.kind] = (state.budget_calls[artifact.kind] or 0) + 1
    return artifact.bytes
  end
}
package.loaded["prototypes.mir.domain.compiler.execution_mode"] = {
  include_full_diagnostics = function() return false end
}
package.loaded["prototypes.mir.domain.research_cost.compatibility_slice"] = {
  build = function() return {kind = "research-cost"} end
}
package.loaded["prototypes.mir.platform.factorio.target_line"] = {
  mod_data_supported = function() return state.mod_data_supported end,
  feature_enabled = function() return false end,
  factorio_version = nil
}
package.loaded["prototypes.mir.emit.mod_data"] = {
  emit_coverage = function() end,
  emit_generation_plan = function() end,
  emit_maximum_level_policy = function() end,
  emit_technology_catalog = function() end,
  emit_internal_generation_plan = function() end,
  emit_internal_technology_catalog = function() end
}
package.loaded["prototypes.mir.report.coverage"] = {
  publish = function()
    state.coverage_publications = state.coverage_publications + 1
    telemetry.count("coverage_public_bytes", 23)
  end
}
package.loaded["prototypes.mir.emit.research_cost_compatibility_adapter"] = {publish = function() end}
package.loaded["prototypes.mir.emit.compiler_evidence_adapter"] = {
  publish = function(public, internal)
    table.insert(state.adapter_calls, {public = public, internal = internal})
  end
}

local target_line = package.loaded["prototypes.mir.platform.factorio.target_line"]
local publication = require("prototypes.mir.pipeline.compiler_orchestrator.publication")
-- Load the actual coverage publisher after its public projection is restored,
-- while retaining this fixture's telemetry and no-op mod-data transport.
local saved_public_artifacts = package.loaded["prototypes.mir.report.public_compiler_artifacts"]
local saved_coverage = package.loaded["prototypes.mir.report.coverage"]
local saved_recipe_facts = package.loaded["prototypes.mir.index.recipe_facts"]
local saved_adoption = package.loaded["prototypes.mir.emit.transactions.productivity_family_adoption"]
local saved_registry = package.loaded["prototypes.mir.domain.facts.generated_technology_registry"]
package.loaded["prototypes.mir.report.public_compiler_artifacts"] = actual_public_artifacts
package.loaded["prototypes.mir.index.recipe_facts"] = {}
package.loaded["prototypes.mir.emit.transactions.productivity_family_adoption"] = {snapshot = function() return {} end}
package.loaded["prototypes.mir.domain.facts.generated_technology_registry"] = {contains = function() return false end}
package.loaded["prototypes.mir.report.coverage"] = nil
local owned_coverage_publisher = require("prototypes.mir.report.coverage")
package.loaded["prototypes.mir.report.public_compiler_artifacts"] = saved_public_artifacts
package.loaded["prototypes.mir.report.coverage"] = saved_coverage
package.loaded["prototypes.mir.index.recipe_facts"] = saved_recipe_facts
package.loaded["prototypes.mir.emit.transactions.productivity_family_adoption"] = saved_adoption
package.loaded["prototypes.mir.domain.facts.generated_technology_registry"] = saved_registry

local function context()
  local final_result = {
    schema = 1, result_fingerprint = "mir32-result", _publication_copy_probe = "final-result",
    dimensions = {execution = "APPLIED"}, execution_evidence = {journal_fingerprint = "mir32-journal"},
    ignored_full_result_material = {unexported = {"large", "row"}}
  }
  local journal = {
    publication_summary = function()
      state.journal_summary_calls = state.journal_summary_calls + 1
      return {
        schema = 2, plan_fingerprint = "mir32-plan", journal_fingerprint = "mir32-journal",
        required_operation_count = 1, terminal_counts = {applied = 1, failed = 0},
        missing_operation_count = 0, duplicate_operation_count = 0,
        undeclared_operation_count = 0, out_of_plan_operation_count = 0, complete = true
      }
    end,
    snapshot = function()
      state.journal_snapshot_calls = state.journal_snapshot_calls + 1
      return {
        schema = 2, plan_fingerprint = "mir32-plan", journal_fingerprint = "mir32-journal",
        entries = {{before_snapshot = {unexported = true}, after_projection = {unexported = true}}},
        terminal_counts = {applied = 1, failed = 0}, complete = true,
        _publication_copy_probe = "journal-snapshot"
      }
    end
  }
  return {
    plan = {
      schema = 2,
      compilation_fingerprint = "mir32-compilation",
      qualification_fingerprint = "mir32-qualification",
      compiler_input = {input_fingerprint = "mir32-input"},
      stream_plan = {rows = {}},
      technology_catalog = {schema = 4, catalog_fingerprint = "mir32-catalog"},
      technology_catalog_fingerprint = "mir32-catalog-fingerprint",
      input_sanitation_ledger = {
        schema = 1, pass = "input", scanned_technology_count = 1,
        sanitized_target_inventory_fingerprint = "mir32-target", _publication_copy_probe = "input-ledger",
        technologies = {{ignored = true}}
      },
      base_extension_operations = {},
      pure_compilation = {execution_mode = "SAFE"}
    },
    state_view = function(_, key)
      if key == "final_compiler_result" then return final_result end
      if key == "family_resolution" then return {} end
      if key == "diagnostics" then
        state.diagnostics_accesses = state.diagnostics_accesses + 1
        return {rows = {{kind = "decision", reason = "canonical_provider_decision_projection",
          _publication_copy_probe = "provider-decision", payload = {unexported = true}}}}
      end
      if key == "mutation_journal" then return journal end
      return nil
    end,
    artifact = function(_, name)
      state.artifact_calls[name] = (state.artifact_calls[name] or 0) + 1
      if name == "output_sanitation_ledger" then
        return {schema = 1, pass = "output", scanned_technology_count = 1,
          sanitized_target_inventory_fingerprint = "mir32-target", technologies = {{ignored = true}}}
      end
      if name == "technology_graph_parity" then
        return {valid = true, full_parity_rows = {{unexported = true}}}
      end
      return {}
    end,
    state_key_count = function() return 7 end,
    execution_mode = function() return "SAFE" end
  }
end

reset(true, "2.1", false, false)
target_line.factorio_version = state.factorio_version
check(publication.publish(context()) == true, "modern publication succeeds")
check(state.evidence_constructions == 1,
  "modern publication constructs and owned-budgets public evidence once")
check(state.work_volume_records == 2 and #state.adapter_calls == 1,
  "modern publication records work around one public evidence construction")
check(state.adapter_calls[1].public.compilation_fingerprint == "mir32-compilation"
  and state.adapter_calls[1].public.qualification_fingerprint == "mir32-qualification",
  "modern publication preserves semantic evidence identities")
check(state.evidence_telemetry.counters.compiler_evidence_public_bytes == 0
  and state.evidence_telemetry.counters.public_artifact_total_bytes == 0,
  "public evidence freezes telemetry before measuring itself")
check(state.counters.compiler_evidence_public_bytes == 17
  and state.counters.public_artifact_total_bytes == 83,
  "live telemetry records exact public artifact bytes after publication")
check(state.journal_summary_calls == 1 and state.journal_snapshot_calls == 0
  and state.probe_deepcopy_calls == 0,
  "ordinary publication avoids full result and journal copies")
check(state.diagnostics_accesses == 0 and (state.artifact_calls.technology_graph_parity or 0) == 0
  and (state.artifact_calls.output_sanitation_ledger or 0) == 1,
  "ordinary publication does not construct internal diagnostics or graph parity")
check(state.public_input.compiler_input_fingerprint == nil
  and state.public_input.technology_graph_parity == nil
  and state.public_input.provider_decision_diagnostics == nil,
  "ordinary public evidence receives only its declared projection")

reset(false, "1.1", false, false)
target_line.factorio_version = state.factorio_version
check(publication.publish(context()) == true, "older-engine publication succeeds")
check(state.evidence_constructions == 1 and state.generation_plan_constructions == 0
  and state.catalog_constructions == 0 and state.coverage_publications == 0,
  "older engine emits one validation evidence projection without mod-data artifacts")

-- Construct each actual public projection at exact hard-limit minus one,
-- exactly hard-limit, and hard-limit plus one. The chosen padding field is
-- projected once, so the independently canonicalized target remains exact.
local owned_kinds = {
  "mir-generation-plan-public", "mir-technology-catalog-public",
  "mir-coverage-public", "mir-compiler-evidence-public"
}
local owned_limits = {}
for _, kind in ipairs(owned_kinds) do owned_limits[kind] = actual_public_artifact_budget.limit(kind) end
local function boundary_generation_plan()
  return {schema = 3, plan_fingerprint = "", source_fingerprints = {}, validation_summary = {}, rows = {}}
end
local function boundary_catalog()
  return {schema = 4, phase = "final", catalog_fingerprint = "",
    alternative_evaluation = {mode = "full-diagnostics", complete = true, evaluated_alternatives = 0,
      deferred_diagnostic_alternatives = 0, deferred_rejected_diagnostic_alternatives = 0},
    current_selections = {}, candidates = {}, qualifications = {}}
end
local function boundary_coverage()
  return {schema = 1, summary = {boundary_pad = ""}}
end
local function boundary_evidence()
  local input = actual_evidence_input()
  input.telemetry.counters.boundary_pad = ""
  return input
end
local boundary_builders = {
  {kind = "mir-generation-plan-public", build = function(input) return actual_public_artifacts.generation_plan(input) end,
    fresh = boundary_generation_plan, pad = function(input, value) input.plan_fingerprint = value end},
  {kind = "mir-technology-catalog-public", build = function(input) return actual_public_artifacts.technology_catalog(input, {}) end,
    fresh = boundary_catalog, pad = function(input, value) input.catalog_fingerprint = value end},
  {kind = "mir-coverage-public", build = function(input) return actual_public_artifacts.coverage(input) end,
    fresh = boundary_coverage, pad = function(input, value) input.summary.boundary_pad = value end},
  {kind = "mir-compiler-evidence-public", build = function(input) return actual_public_artifacts.compiler_evidence(input) end,
    fresh = boundary_evidence, pad = function(input, value) input.telemetry.counters.boundary_pad = value end}
}
local boundary_artifacts, boundary_bytes = {}, {}
for _, builder in ipairs(boundary_builders) do
  boundary_artifacts[builder.kind], boundary_bytes[builder.kind] = {}, {}
  for _, offset in ipairs({-1, 0, 1}) do
    local input = builder.fresh()
    builder.pad(input, "")
    local _, base_bytes = builder.build(input)
    local expected = owned_limits[builder.kind] + offset
    local padding = expected - base_bytes
    check(padding >= 0, builder.kind .. " boundary fixture must start below its hard limit")
    builder.pad(input, string.rep("x", padding))
    local public, owned_bytes = builder.build(input)
    check(owned_bytes == expected and #canonical(public) == expected,
      builder.kind .. " owned boundary has exact independently canonicalized bytes")
    local generic_ok = pcall(function() actual_public_artifacts.assert_byte_budget(public) end)
    check(generic_ok == (offset <= 0),
      builder.kind .. " generic guard has exact below/equal/above hard-limit behavior")
    boundary_artifacts[builder.kind][offset] = input
    boundary_bytes[builder.kind][offset] = owned_bytes
  end
end
-- Publication owns plan/catalog/evidence until the adapter call. Feed the
-- independently generated exact count into its immediate local boundary.
for _, kind in ipairs({"mir-generation-plan-public", "mir-technology-catalog-public", "mir-compiler-evidence-public"}) do
  for _, offset in ipairs({-1, 0, 1}) do
    reset(true, "2.1", false, false, kind, boundary_bytes[kind][offset])
    target_line.factorio_version = state.factorio_version
    local accepted = pcall(function() publication.publish(context()) end)
    check(accepted == (offset <= 0), kind .. " owned publisher honors below/equal/above hard limit")
  end
end
-- Coverage has its own local publisher boundary. Use its actual builder and
-- the same independently exact artifacts; its output must not escape on +1.
for _, offset in ipairs({-1, 0, 1}) do
  reset(true, "2.1", false, false)
  local context_with_coverage = {
    state_snapshot = function() return boundary_artifacts["mir-coverage-public"][offset] end
  }
  local accepted, message = pcall(function() return owned_coverage_publisher.publish(context_with_coverage) end)
  check(accepted == (offset <= 0), "coverage owned publisher honors below/equal/above hard limit offset=" .. offset .. " message=" .. tostring(message))
end

reset(true, "2.1", false, true)
target_line.factorio_version = state.factorio_version
check(publication.publish(context()) == true and state.internal_constructions == 1
  and state.adapter_calls[1].internal.kind == "internal-evidence",
  "diagnostics retain one paired internal evidence projection")
check(state.journal_summary_calls == 1 and state.journal_snapshot_calls == 1
  and state.diagnostics_accesses == 1 and state.provider_inspection_calls == 1
  and (state.artifact_calls.technology_graph_parity or 0) == 1,
  "internal publication constructs the complete diagnostic inputs only on request")
check(state.internal_input.mutation_journal.entries[1].before_snapshot.unexported
  and state.internal_input.technology_graph_parity.full_parity_rows[1].unexported
  and state.internal_input.provider_decision_diagnostics[1].payload.unexported,
  "internal evidence retains complete journal, parity, and decision rows")

print("MIR-PUBLICATION-MEASUREMENT-PASS " .. assertions)

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

local state = {}
local telemetry = {}

local function reset(mod_data_supported, factorio_version, reject_evidence_budget, diagnostics_enabled)
  state = {
    mod_data_supported = mod_data_supported,
    factorio_version = factorio_version,
    reject_evidence_budget = reject_evidence_budget,
    diagnostics_enabled = diagnostics_enabled,
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
    coverage_publications = 0
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
    return {kind = "internal-evidence", compilation_fingerprint = input.compilation_fingerprint}
  end
}
package.loaded["prototypes.mir.report.compiler_telemetry"] = telemetry
package.loaded["prototypes.mir.report.diagnostics_sink"] = {enabled = function() return state.diagnostics_enabled end}
package.loaded["prototypes.mir.report.public_compiler_artifacts"] = {
  generation_plan = function()
    state.generation_plan_constructions = state.generation_plan_constructions + 1
    return {kind = "generation-plan", bytes = 11}
  end,
  technology_catalog = function()
    state.catalog_constructions = state.catalog_constructions + 1
    return {kind = "technology-catalog", bytes = 13}
  end,
  compiler_evidence = function(input)
    state.evidence_constructions = state.evidence_constructions + 1
    state.evidence_telemetry = copy(input.telemetry)
    return {
      kind = "compiler-evidence", bytes = 17,
      compilation_fingerprint = input.compilation_fingerprint,
      qualification_fingerprint = input.qualification_fingerprint,
      telemetry = copy(input.telemetry)
    }
  end,
  research_cost_compatibility = function() return {kind = "research-cost", bytes = 19} end,
  assert_byte_budget = function(artifact)
    state.budget_calls[artifact.kind] = (state.budget_calls[artifact.kind] or 0) + 1
    if state.reject_evidence_budget and artifact.kind == "compiler-evidence" then
      error("controlled compiler-evidence budget rejection")
    end
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

local function context()
  local final_result = {schema = 1, result_fingerprint = "mir32-result"}
  return {
    plan = {
      schema = 2,
      compilation_fingerprint = "mir32-compilation",
      qualification_fingerprint = "mir32-qualification",
      compiler_input = {input_fingerprint = "mir32-input"},
      stream_plan = {rows = {}},
      technology_catalog = {schema = 3, catalog_fingerprint = "mir32-catalog"},
      input_sanitation_ledger = {},
      base_extension_operations = {},
      pure_compilation = {execution_mode = "SAFE"}
    },
    state_view = function(_, key)
      if key == "final_compiler_result" then return final_result end
      if key == "family_resolution" then return {} end
      if key == "diagnostics" then return {rows = {}} end
      if key == "mutation_journal" then return {snapshot = function() return {schema = 1} end} end
      return nil
    end,
    artifact = function() return {} end,
    state_key_count = function() return 7 end,
    execution_mode = function() return "SAFE" end
  }
end

reset(true, "2.1", false, false)
target_line.factorio_version = state.factorio_version
check(publication.publish(context()) == true, "modern publication succeeds")
check(state.evidence_constructions == 1 and state.budget_calls["compiler-evidence"] == 1,
  "modern publication constructs and budgets public evidence once")
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

reset(true, "2.1", true, false)
target_line.factorio_version = state.factorio_version
local accepted, message = pcall(function() publication.publish(context()) end)
check(not accepted and string.find(tostring(message), "controlled compiler-evidence budget rejection", 1, true),
  "public evidence budget rejection remains fatal")
check(state.evidence_constructions == 1 and state.budget_calls["compiler-evidence"] == 1
  and #state.adapter_calls == 0, "rejected public evidence is not emitted")

reset(false, "1.1", false, false)
target_line.factorio_version = state.factorio_version
check(publication.publish(context()) == true, "older-engine publication succeeds")
check(state.evidence_constructions == 1 and state.generation_plan_constructions == 0
  and state.catalog_constructions == 0 and state.coverage_publications == 0,
  "older engine emits one validation evidence projection without mod-data artifacts")

reset(true, "2.1", false, true)
target_line.factorio_version = state.factorio_version
check(publication.publish(context()) == true and state.internal_constructions == 1
  and state.adapter_calls[1].internal.kind == "internal-evidence",
  "diagnostics retain one paired internal evidence projection")

print("MIR-PUBLICATION-MEASUREMENT-PASS " .. assertions)

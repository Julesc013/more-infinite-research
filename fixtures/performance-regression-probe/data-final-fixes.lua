local probe = require("probe")
local prototype = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-compiler-evidence"]
local evidence = prototype and prototype.data or nil
local science = require("__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local bindings = science.binding_snapshot()
local binding_summary = {declared = 0, initial = 0, research = 0, not_admitted = 0, unresolved = 0}
for _, binding in pairs(bindings.packs or {}) do
  if type(binding) == "table" then
    binding_summary.declared = binding_summary.declared + 1
    if binding.status == "initial" then binding_summary.initial = binding_summary.initial + 1
    elseif binding.status == "research" then binding_summary.research = binding_summary.research + 1
    elseif binding.status == "not-admitted" then binding_summary.not_admitted = binding_summary.not_admitted + 1
    end
  end
end
for _ in pairs(bindings.issues or {}) do binding_summary.unresolved = binding_summary.unresolved + 1 end
local artifact = {
  schema = 1,
  kind = "mir-performance-regression-probe",
  phases = probe.phases,
  approved_binding_work = binding_summary,
  telemetry = evidence and {
    schema = 1,
    fingerprint = evidence.telemetry_fingerprint,
    counters = evidence.counts,
    phases = evidence.phases
  } or nil
}
log("[MIR_PERFORMANCE_PROBE] " .. helpers.table_to_json(artifact))

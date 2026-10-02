local probe = require("probe")
local prototype = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-compiler-evidence"]
local evidence = prototype and prototype.data or nil
local artifact = {
  schema = 1,
  kind = "mir-performance-regression-probe",
  phases = probe.phases,
  telemetry = evidence and {
    schema = 1,
    fingerprint = evidence.telemetry_fingerprint,
    counters = evidence.counts,
    phases = evidence.phases
  } or nil
}
log("[MIR_PERFORMANCE_PROBE] " .. helpers.table_to_json(artifact))

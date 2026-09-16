local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.proof_fingerprint(summary)
  return fingerprint.of({
    graph_fingerprint = summary.graph_fingerprint,
    component_assignment_fingerprint = summary.component_assignment_fingerprint,
    condensation_topology_fingerprint = summary.condensation_topology_fingerprint,
    proofs = summary.proofs,
    rejected = summary.rejected,
    cyclic_components = summary.cyclic_components
  })
end

return M

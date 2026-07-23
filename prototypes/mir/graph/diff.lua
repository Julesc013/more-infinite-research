local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.compare(expected, actual)
  local result = {
    schema = 1,
    expected_graph_fingerprint = expected.graph_fingerprint,
    actual_graph_fingerprint = actual.graph_fingerprint,
    equal = expected.graph_fingerprint == actual.graph_fingerprint
  }
  result.diff_fingerprint = fingerprint.of(result)
  return result
end

return M

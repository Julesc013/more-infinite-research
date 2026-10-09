local M = {}

M.schema = 1

M.codes = {
  automatic_productivity_disabled = "MIR-AUTO-001",
  automatic_productivity_preview_only = "MIR-AUTO-002",
  automatic_research_creation_disabled = "MIR-AUTO-003",
  reviewed_compatibility_data_required = "MIR-AUTO-004",
  reviewed_compatibility_data_authorized = "MIR-AUTO-005",
  registered_family_module_authorized = "MIR-AUTO-006",
  automatic_family_not_reviewed = "MIR-AUTO-007",
  provider_candidate_discovered = "MIR-PROVIDER-001",
  provider_candidate_rejected = "MIR-PROVIDER-002",
  provider_candidate_attached = "MIR-PROVIDER-003",
  provider_candidate_planned = "MIR-PROVIDER-004"
}

local ordered = nil

function M.all()
  if ordered then
    local copy = {}
    for index, row in ipairs(ordered) do copy[index] = {key = row.key, code = row.code} end
    return copy
  end
  local rows, seen = {}, {}
  for key, code in pairs(M.codes) do
    if seen[code] then error("Duplicate MIR diagnostic code: " .. code, 2) end
    seen[code] = true
    table.insert(rows, {key = key, code = code})
  end
  table.sort(rows, function(a, b) return a.code < b.code end)
  ordered = rows
  return M.all()
end

function M.get(key)
  local code = M.codes[key]
  if not code then error("Unknown MIR diagnostic key: " .. tostring(key), 2) end
  return code
end

return M

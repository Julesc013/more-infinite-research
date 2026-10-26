-- Bob Logistics owns this continuation on F210.  The caller selects this
-- adapter only for the F210 Bob Logistics boundary; the exact owner lookup
-- below deliberately consumes no presentation, science, cost, or version
-- fields from the foreign technology.
local M = {}

M.native_technology = "inserter-capacity-bonus-8"

-- Confirm the supported native owner before MIR publishes anything.  This is
-- intentionally read-only: the existing Bob technology remains the owner of
-- its effects and the central catalogue omits only MIR's duplicate row.
function M.preflight(raw)
  local technologies = type(raw) == "table" and raw.technology or nil
  if type(technologies) ~= "table" then
    error("MIR Bob native inserter preflight requires data.raw.technology", 2)
  end

  local native = technologies[M.native_technology]
  if type(native) ~= "table" then
    error("MIR Bob native inserter preflight missing " .. M.native_technology, 2)
  end
  if native.max_level ~= "infinite" then
    error("MIR Bob native inserter preflight requires infinite " .. M.native_technology, 2)
  end

  return true
end

return M

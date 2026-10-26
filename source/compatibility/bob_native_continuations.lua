-- Bob Logistics owns these two F210 continuations.  The caller selects this
-- adapter only for the F210 Bob Logistics boundary; the exact owner lookups
-- below deliberately consume no presentation, science, cost, or version
-- fields from the foreign technologies.
local M = {}

M.native_technologies = {
  "inserter-capacity-bonus-8",
  "bob-infinite-worker-robots-storage-4",
}

-- Confirm both supported native owners before MIR publishes anything.  This
-- is intentionally read-only: the existing Bob technologies remain owners of
-- their effects and the central catalogue omits only MIR's duplicate rows.
function M.preflight(raw)
  local technologies = type(raw) == "table" and raw.technology or nil
  if type(technologies) ~= "table" then
    error("MIR Bob native continuation preflight requires data.raw.technology", 2)
  end

  for _, name in ipairs(M.native_technologies) do
    local native = technologies[name]
    if type(native) ~= "table" then
      error("MIR Bob native continuation preflight missing " .. name, 2)
    end
    if native.max_level ~= "infinite" then
      error("MIR Bob native continuation preflight requires infinite " .. name, 2)
    end
  end

  return true
end

return M

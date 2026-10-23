-- Select the published opt-in policy without creating recipes or technologies.
-- The same observer is a no-op in the matched no-MIR reference arm.
for name, value in pairs({
  ["mir-automatic-create-research"] = true,
  ["mir-automatic-require-reviewed-data"] = false,
}) do
  local row = data.raw["bool-setting"] and data.raw["bool-setting"][name]
  if row then row.default_value = value end
end

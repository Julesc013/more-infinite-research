-- Consumed by the existing library-selection verifier for control-only and
-- asset-only mods which have no data-stage Loading mod line of their own.
local selected = {}
for name, version in pairs(mods) do
  if name ~= "core" then selected[#selected + 1] = name .. "@" .. version end
end
table.sort(selected)
log("[MIR_ACTIVE_MODS] " .. table.concat(selected, "|"))

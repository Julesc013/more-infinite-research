-- Include asset-only dependencies in the existing loaded-selection check.
local active = {}
for name, version in pairs(mods) do
  if name ~= "core" then active[#active + 1] = name .. "@" .. version end
end
table.sort(active)
log("[MIR_ACTIVE_MODS] " .. table.concat(active, "|"))

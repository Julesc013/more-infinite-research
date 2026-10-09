-- The engine's loader lines omit asset-only dependencies. Report the actual
-- complete selection through the existing source-bound inventory collector.
local active = {}
for name, version in pairs(mods) do
  if name ~= "core" then active[#active + 1] = name .. "@" .. version end
end
table.sort(active)
log("[MIR_ACTIVE_MODS] " .. table.concat(active, "|"))

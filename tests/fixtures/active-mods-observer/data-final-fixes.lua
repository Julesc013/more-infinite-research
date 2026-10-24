if type(mods) ~= "table" then
  error("[mir5-active-mods-observer] Factorio data-stage mods dictionary is required")
end

local identities = {}
for name, version in pairs(mods) do
  if type(name) ~= "string" or type(version) ~= "string" then
    error("[mir5-active-mods-observer] mods must map string names to string versions")
  end
  identities[#identities + 1] = name .. "@" .. version
end

table.sort(identities)
log("[MIR_ACTIVE_MODS] " .. table.concat(identities, "|"))

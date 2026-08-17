local technology = data.raw.technology["recipe-prod-research_copper-1"]
if not technology then error("MIR generated maximum-level fixture is missing copper productivity") end
local function contains(value, expected)
  if tostring(value) == tostring(expected) then return true end
  if type(value) ~= "table" then return false end
  for _, child in pairs(value) do if contains(child, expected) then return true end end
  return false
end
if technology.max_level ~= "infinite" then
  error("MIR generated maximum-level fixture requires a lossless infinite prototype")
end
if technology.show_levels_info ~= false then
  error("MIR generated maximum-level fixture still exposes the misleading infinity badge")
end
if not contains(technology.localised_description, 5) then
  error("MIR generated maximum-level fixture does not disclose configured maximum 5")
end

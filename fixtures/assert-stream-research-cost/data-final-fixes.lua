local technology = data.raw.technology and data.raw.technology["recipe-prod-research_gears-1"]
if not technology then
  error("MIR stream research-cost fixture expected recipe-prod-research_gears-1")
end
if not technology.unit then
  error("MIR stream research-cost fixture expected unit data")
end
if technology.unit.count ~= nil then
  error("MIR stream research-cost fixture expected a canonical count formula")
end
local expected = "(1000+250*(L-1))*1.5^(L-1)"
if technology.unit.count_formula ~= expected then
  error("MIR stream research-cost formula differs; expected " .. expected
    .. " got " .. tostring(technology.unit.count_formula))
end

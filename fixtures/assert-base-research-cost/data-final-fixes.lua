local technology = data.raw.technology and data.raw.technology["worker-robots-storage-4"]
if not technology then
  error("MIR base research-cost fixture expected worker-robots-storage-4")
end
if not technology.unit then
  error("MIR base research-cost fixture expected unit data")
end
if technology.unit.count ~= nil then
  error("MIR base research-cost fixture expected a canonical count formula")
end
local expected = "1000+250*(L-4)"
if technology.unit.count_formula ~= expected then
  error("MIR base research-cost formula differs; expected " .. expected
    .. " got " .. tostring(technology.unit.count_formula))
end

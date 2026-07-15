local external = data.raw.technology and data.raw.technology["laboratory-productivity-4"]
if not external then
  error("MIR validation failed: fixture laboratory-productivity-4 technology is missing.")
end

if external.max_level ~= "infinite" then
  error("MIR validation failed: fixture laboratory-productivity-4 is not infinite.")
end

local found_lab_productivity = false
for _, effect in ipairs(external.effects or {}) do
  if effect.type == "laboratory-productivity" and math.abs(tonumber(effect.modifier or 0) - 0.10) < 0.000000001 then
    found_lab_productivity = true
    break
  end
end

if not found_lab_productivity then
  error("MIR validation failed: fixture laboratory-productivity-4 does not have the expected laboratory-productivity effect.")
end

if data.raw.technology and data.raw.technology["recipe-prod-research_lab_productivity-1"] then
  error("MIR validation failed: MIR lab productivity generated despite an effect-proven laboratory-productivity-4 owner.")
end

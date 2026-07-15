local function fail(message)
  error("MIR validation failed: " .. message)
end

local finite = data.raw.technology and data.raw.technology["worker-robots-battery-1"]
if not finite then
  fail("fixture finite worker-robots-battery-1 technology is missing")
end

local owner = data.raw.technology and data.raw.technology["worker-robots-battery-6"]
if not owner then
  fail("fixture infinite worker-robots-battery-6 technology is missing")
end
if owner.max_level ~= "infinite" then
  fail("fixture worker-robots-battery-6 is not infinite")
end

local found_owner_effect = false
for _, effect in ipairs(owner.effects or {}) do
  if effect.type == "worker-robot-battery" and math.abs(tonumber(effect.modifier or 0) - 0.70) < 0.000000001 then
    found_owner_effect = true
    break
  end
end
if not found_owner_effect then
  fail("fixture worker-robots-battery-6 does not have the expected worker-robot-battery effect")
end

if data.raw.technology and data.raw.technology["recipe-prod-research_robot_battery-1"] then
  fail("MIR robot battery generated despite an effect-proven Better Bot Battery owner")
end

local preserved = data.raw.technology and data.raw.technology["research-speed-7"]
if not preserved then
  error("MIR validation failed: fixture research-speed-7 was removed.")
end

if not preserved.unit or preserved.unit.count ~= 777 or preserved.unit.time ~= 77 then
  error("MIR validation failed: existing finite research-speed-7 unit data was mutated.")
end

for _, ingredient in ipairs(preserved.unit.ingredients or {}) do
  local name = ingredient.name or ingredient[1]
  if name == "mir-fixture-science-pack" then
    error("MIR validation failed: existing finite research-speed-7 received generated science-pack policy ingredients.")
  end
end

local generated = data.raw.technology and data.raw.technology["research-speed-8"]
if not generated then
  error("MIR validation failed: MIR did not extend after existing finite research-speed-7.")
end

if generated.max_level ~= "infinite" then
  error("MIR validation failed: generated research-speed-8 was not infinite.")
end

local found_fixture_pack = false
for _, ingredient in ipairs((generated.unit and generated.unit.ingredients) or {}) do
  local name = ingredient.name or ingredient[1]
  if name == "mir-fixture-science-pack" then
    found_fixture_pack = true
    break
  end
end

if not found_fixture_pack then
  error("MIR validation failed: generated research-speed-8 did not receive all-policy fixture science pack.")
end

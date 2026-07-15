local target = "item-microculture-vat-incineration"

if not data.raw.recipe[target] then
  error("MIR late-removal fixture setup failed: missing recipe " .. target)
end

local breeding = data.raw.technology["recipe-prod-research_breeding-1"]
if not breeding then
  error("MIR late-removal fixture setup failed: missing breeding productivity technology")
end

local referenced_by_breeding = {}
for _, effect in ipairs(breeding.effects or {}) do
  if effect.type == "change-recipe-productivity" then
    referenced_by_breeding[effect.recipe] = true
  end
end

local classifier_cases = {
  {recipe = "item-microculture-vat-incineration", expected = false},
  {recipe = "example-culture-incinerate", expected = false},
  {recipe = "example-incineration", expected = false},
  {recipe = "microculture-vat-breeding", expected = true},
  {recipe = "microculture-cultivation", expected = true},
  {recipe = "mir-fixture-normal-crafting", expected = false}
}

for _, case in ipairs(classifier_cases) do
  local actual = referenced_by_breeding[case.recipe] == true
  if actual ~= case.expected then
    error("MIR breeding classifier fixture failed for "
      .. case.recipe
      .. ": expected="
      .. tostring(case.expected)
      .. " actual="
      .. tostring(actual))
  end
end

for technology_name, technology in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == target then
      error("MIR late-removal fixture failed: "
        .. technology_name
        .. " references sink recipe "
        .. target)
    end
  end
end

data.raw.recipe[target] = nil

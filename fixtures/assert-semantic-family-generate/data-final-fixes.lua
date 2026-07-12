local expected = {
  ["mir-auto-prod-manufacturing-assembling-machine-1"] = "assemble-theta",
  ["mir-auto-prod-manufacturing-lab-1"] = "assemble-zeta"
}

local function fail(message)
  error("MIR semantic family generation validation failed: " .. message)
end

for technology_name, recipe_name in pairs(expected) do
  local technology = data.raw.technology and data.raw.technology[technology_name]
  if not technology then fail("missing generated family technology " .. technology_name) end
  local found = false
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      found = true
      if math.abs((tonumber(effect.change) or 0) - 0.02) > 0.000000001 then
        fail(recipe_name .. " has wrong change " .. tostring(effect.change))
      end
    end
  end
  if not found then fail(recipe_name .. " is absent from " .. technology_name) end
end

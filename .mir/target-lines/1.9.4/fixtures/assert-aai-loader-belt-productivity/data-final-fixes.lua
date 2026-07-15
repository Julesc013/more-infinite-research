local tech = data.raw.technology and data.raw.technology["recipe-prod-research_belts-1"]

local expected = {
  ["aai-loader"] = 0.10,
  ["aai-fast-loader"] = 0.05,
  ["aai-express-loader"] = 0.02,
  ["aai-turbo-loader"] = 0.01
}

local function fail(message)
  error("MIR AAI loader validation failed: " .. message)
end

if not tech then fail("missing generated belt productivity technology.") end

local seen = {}
for _, effect in ipairs(tech.effects or {}) do
  if effect.type == "change-recipe-productivity" and expected[effect.recipe] then
    local expected_change = expected[effect.recipe]
    local actual_change = tonumber(effect.change) or 0
    if math.abs(actual_change - expected_change) > 0.000000001 then
      fail(effect.recipe .. " should use +" .. tostring(expected_change) .. ", got " .. tostring(effect.change) .. ".")
    end
    seen[effect.recipe] = true
  end
end

local missing = {}
for recipe_name, _ in pairs(expected) do
  if not seen[recipe_name] then table.insert(missing, recipe_name) end
end
table.sort(missing)

if #missing > 0 then
  fail("loader recipes did not receive belt productivity: " .. table.concat(missing, ", "))
end

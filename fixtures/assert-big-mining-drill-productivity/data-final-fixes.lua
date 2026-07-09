local tech = data.raw.technology and data.raw.technology["recipe-prod-research_mining_drill-1"]

local function fail(message)
  error("MIR Big Mining Drill validation failed: " .. message)
end

if not tech then fail("missing generated mining drill productivity technology.") end

local found = false
for _, effect in ipairs(tech.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "big-mining-drill" then
    found = true
    local change = tonumber(effect.change) or 0
    if math.abs(change - 0.05) > 0.000000001 then
      fail("big-mining-drill should use +0.05, got " .. tostring(effect.change) .. ".")
    end
  end
end

if not found then
  fail("big-mining-drill did not receive mining drill productivity.")
end

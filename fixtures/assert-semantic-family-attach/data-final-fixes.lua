local expected = {
  ["recipe-prod-research_belts-1"] = {recipe = "assemble-alpha", change = 0.01, additional_recipe = "pack-only-recipe"},
  ["recipe-prod-research_mining_drill-1"] = {recipe = "assemble-beta", change = 0.05},
  ["recipe-prod-research_furnace-1"] = {recipe = "assemble-gamma", change = 0.02},
  ["recipe-prod-research_electric_energy-1"] = {recipe = "assemble-delta", change = 0.02},
  ["recipe-prod-research_inserters-1"] = {recipe = "assemble-epsilon", change = 0.01},
  ["recipe-prod-research_modules-1"] = {recipe = "assemble-eta", change = 0.01}
}

local function fail(message)
  error("MIR semantic family attach validation failed: " .. message)
end

for technology_name, wanted in pairs(expected) do
  local technology = data.raw.technology and data.raw.technology[technology_name]
  if not technology then fail("missing stable stream " .. technology_name) end
  local found = false
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == wanted.recipe then
      found = true
      if math.abs((tonumber(effect.change) or 0) - wanted.change) > 0.000000001 then
        fail(wanted.recipe .. " has wrong change " .. tostring(effect.change))
      end
    end
  end
  if not found then fail(wanted.recipe .. " was not attached to " .. technology_name) end
  if wanted.additional_recipe then
    local additional_found = false
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == wanted.additional_recipe then additional_found = true end
    end
    if not additional_found then fail("pack-seeded candidate was not attached to " .. technology_name) end
  end
end

local finite_owner = data.raw.technology and data.raw.technology["mir-fixture-finite-family-owner"]
if not finite_owner or finite_owner.max_level == "infinite" then fail("finite owner fixture is missing") end

for technology_name, technology in pairs(data.raw.technology or {}) do
  if string.find(technology_name, "assemble%-") then
    fail("per-recipe technology identity was created: " .. technology_name)
  end
  if string.find(technology_name, "^recipe%-prod%-") then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == "assemble-zeta" then
        fail("lab manufacturing recipe was attached to an unrelated fixed stream")
      end
    end
  end
end


for _, denied_recipe in ipairs({"pack-hard-productivity-false", "pack-hard-recycling"}) do
  for technology_name, technology in pairs(data.raw.technology or {}) do
    if technology.max_level == "infinite" then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "change-recipe-productivity" and effect.recipe == denied_recipe then
          fail("CompatibilityPack bypassed hard gate for " .. denied_recipe .. " through " .. technology_name)
        end
      end
    end
  end
end


for _, technology_name in ipairs({
  "mir-auto-prod-manufacturing-assembling-machine-1",
  "mir-auto-prod-manufacturing-lab-1"
}) do
  if data.raw.technology and data.raw.technology[technology_name] then
    fail("safe-attach default emitted generated family technology " .. technology_name)
  end
end

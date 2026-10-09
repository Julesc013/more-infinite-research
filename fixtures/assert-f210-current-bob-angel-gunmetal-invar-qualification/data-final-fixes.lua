-- Package-excluded qualification for the two exact current F210 Bob/Angel
-- material routes.  It binds emitted effects and their unique ownership; it
-- does not select routes or modify gameplay prototypes.
local subjects = {
  {
    family = "gunmetal",
    technology = "recipe-prod-research_material_gunmetal-1",
    recipe = "angels-plate-gunmetal"
  },
  {
    family = "invar",
    technology = "recipe-prod-research_material_invar-1",
    recipe = "angels-plate-invar"
  }
}

local function fail(message)
  error("[mir-f210-current-ba-gunmetal-invar] " .. message)
end

local function effect_owners(recipe)
  local owners = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
        owners[#owners + 1] = technology_name .. ":" .. tostring(effect.change)
      end
    end
  end
  table.sort(owners)
  return owners
end

for _, subject in ipairs(subjects) do
  local technology = data.raw.technology[subject.technology]
  if type(technology) ~= "table" or technology.max_level ~= 3 then
    fail(subject.family .. " early technology differs")
  end

  local matching, unexpected = 0, 0
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" then
      if effect.recipe == subject.recipe and effect.change == 0.02 then
        matching = matching + 1
      else
        unexpected = unexpected + 1
      end
    end
  end
  if matching ~= 1 or unexpected ~= 0 then
    fail(subject.family .. " generated effect differs")
  end

  local owners = effect_owners(subject.recipe)
  local expected = subject.technology .. ":0.02"
  if #owners ~= 1 or owners[1] ~= expected then
    fail(subject.family .. " productivity owner differs: " .. table.concat(owners, ","))
  end
end

log("[mir-f210-current-ba-gunmetal-invar] DATA PASS"
  .. " gunmetal=recipe-prod-research_material_gunmetal-1:angels-plate-gunmetal:0.02"
  .. " invar=recipe-prod-research_material_invar-1:angels-plate-invar:0.02"
  .. " unique-owners=true")

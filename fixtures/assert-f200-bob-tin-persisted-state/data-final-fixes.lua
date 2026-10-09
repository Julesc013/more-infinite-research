local technology_name = "recipe-prod-research_material_tin-1"
local recipe_name = "bob-tin-plate"

local function fail(message)
  error("[mir-f200-bob-tin-persisted-state] " .. message)
end

if mods["angelssmelting"] or mods["angelsrefining"] or mods["angelspetrochem"] then
  fail("fixture refuses Angel modules")
end
local technology = data.raw.technology[technology_name]
if not technology or technology.max_level ~= "infinite" then fail("published Tin anchor differs") end
local recipe = data.raw.recipe[recipe_name]
if not recipe or recipe.allow_productivity ~= true then fail("final Bob Tin recipe does not permit productivity") end

local owners, change = 0, nil
for owner_name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owners = owners + 1
      if owner_name ~= technology_name then fail("unexpected Tin productivity owner " .. owner_name) end
      change = effect.change
    end
  end
end
if owners ~= 1 or change ~= 0.02 then fail("Tin anchor must have exactly one 0.02 productivity owner") end

log("[mir-f200-bob-tin-persisted-state] DATA JSON {\"technology\":\"" .. technology.name ..
  "\",\"recipe\":\"" .. recipe.name .. "\",\"owner_count\":" .. owners ..
  ",\"effect_change\":" .. tostring(change) .. ",\"prototype_max_level\":\"" .. tostring(technology.max_level) .. "\"}")

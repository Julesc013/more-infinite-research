local science = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local compiler_context = require(
  "__more-infinite-research__.prototypes.mir.pipeline.compiler_context")

local function fail(message)
  error("MIR Cubium route assertion failed: " .. message)
end

local packs = {
  "automation-science-pack",
  "logistic-science-pack",
  "chemical-science-pack",
  "military-science-pack",
  "production-science-pack",
  "utility-science-pack",
  "metallurgic-science-pack",
  "agricultural-science-pack",
  "electromagnetic-science-pack",
  "cryogenic-science-pack",
  "promethium-science-pack"
}

local cube_mastery = data.raw.technology["cube-mastery-4"]
if not cube_mastery then fail("cube-mastery-4 is missing from the exact Cubium closure.") end

local function entry_name(entry)
  if type(entry) == "string" then return entry end
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function recipe_outputs_pack(recipe, pack_name)
  local function outputs(variant)
    for _, result in ipairs((variant or {}).results or {}) do
      if entry_name(result) == pack_name and (result.type == nil or result.type == "item") then return true end
    end
    local result = (variant or {}).result
    return entry_name(result) == pack_name and (result.type == nil or result.type == "item")
  end
  return outputs(recipe) or outputs(recipe and recipe.normal) or outputs(recipe and recipe.expensive)
end

local function declared_route(pack_name)
  local route = science.production_route_for_pack(pack_name)
  if type(route) ~= "table" or route.pack_name ~= pack_name
      or type(route.recipe_name) ~= "string" or route.acquisition_proof ~= false then
    fail(pack_name .. " lacks a compact declared binding.")
  end
  local recipe = data.raw.recipe[route.recipe_name]
  if type(recipe) ~= "table" or not recipe_outputs_pack(recipe, pack_name) then
    fail(pack_name .. " declared recipe does not produce the named science pack.")
  end
  return route
end

local unlocked = {}
for _, effect in ipairs(cube_mastery.effects or {}) do
  if effect.type == "unlock-recipe" and effect.recipe then unlocked[effect.recipe] = true end
end
for _, pack_name in ipairs(packs) do
  local cubic_recipe = pack_name .. "-cubic"
  if not data.raw.recipe[cubic_recipe] or not unlocked[cubic_recipe] then
    fail(cubic_recipe .. " is not an alternate route unlocked by cube-mastery-4.")
  end
end

compiler_context.with_active(compiler_context.new({execution_mode = "SAFE"}), function()
  for _, pack_name in ipairs(packs) do
    local status, prerequisite = science.pack_production_status(pack_name)
    local route = declared_route(pack_name)
    if status ~= "initial" and status ~= "research" then
      fail(pack_name .. " has no declared progression binding: " .. tostring(status) .. ".")
    end
    if prerequisite == "cube-mastery-4" or route.unlocker == "cube-mastery-4"
        or (route.unlockers or {})[1] == "cube-mastery-4" then
      fail(pack_name .. " was delayed behind cube-mastery-4.")
    end
  end
end)

for technology_name, technology in pairs(data.raw.technology or {}) do
  if string.match(technology_name, "^recipe%-prod%-research_") then
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if prerequisite == "cube-mastery-4" then
        fail("generated technology " .. technology_name .. " retained cube-mastery-4.")
      end
    end
  end
end

log("[mir-fixture-assert-cubium-production-routes] PASS packs=11 declared-bindings=true late-route=cube-mastery-4")

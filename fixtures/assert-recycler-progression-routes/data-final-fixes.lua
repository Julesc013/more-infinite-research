local science = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local compiler_context = require(
  "__more-infinite-research__.prototypes.mir.pipeline.compiler_context")

local function fail(message)
  error("MIR Recycler Progression route assertion failed: " .. message)
end

local recycler_1 = data.raw.technology["recycler-1"]
if not recycler_1 then fail("recycler-1 is missing from the exact Recycler Progression closure.") end

local recycler_unlocks = {}
for _, effect in ipairs(recycler_1.effects or {}) do
  if effect.type == "unlock-recipe" and effect.recipe then recycler_unlocks[effect.recipe] = true end
end
if not recycler_unlocks["automation-science-pack-recycling"] then
  fail("recycler-1 does not carry the reported science-pack recycling unlock surface.")
end

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

local packs = {
  "automation-science-pack",
  "logistic-science-pack",
  "chemical-science-pack",
  "military-science-pack",
  "production-science-pack",
  "utility-science-pack",
  "space-science-pack",
  "metallurgic-science-pack",
  "agricultural-science-pack",
  "electromagnetic-science-pack",
  "cryogenic-science-pack",
  "promethium-science-pack"
}

local exercised = 0
compiler_context.with_active(compiler_context.new({execution_mode = "SAFE"}), function()
  for _, pack_name in ipairs(packs) do
    local recycling_recipe = pack_name .. "-recycling"
    if data.raw.recipe[recycling_recipe] and recycler_unlocks[recycling_recipe] then
      exercised = exercised + 1
      local status, prerequisite = science.pack_production_status(pack_name)
      local route = declared_route(pack_name)
      if status ~= "initial" and status ~= "research" then
        fail(pack_name .. " lost its declared progression binding.")
      end
      if route.recipe_name == recycling_recipe then
        fail(pack_name .. " declared its recycler-1 recycling route.")
      end
      if prerequisite == "recycler-1" or route.unlocker == "recycler-1"
          or (route.unlockers or {})[1] == "recycler-1" then
        fail(pack_name .. " was delayed behind recycler-1.")
      end
    end
  end
end)

if exercised < 6 then
  fail("only " .. tostring(exercised) .. " science-pack recycling routes were exercised.")
end
for technology_name, technology in pairs(data.raw.technology or {}) do
  if string.match(technology_name, "^recipe%-prod%-research_") then
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if prerequisite == "recycler-1" then
        fail("generated technology " .. technology_name .. " retained recycler-1.")
      end
    end
  end
end

log("[mir-fixture-assert-recycler-progression-routes] PASS recycler-1-routes-excluded-from-bindings=true")

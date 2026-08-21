local science = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local compiler_context = require(
  "__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local route_policy = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.production_route_policy")

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
    local route = science.production_route_for_pack(pack_name)
    local decision = science.production_route_decision_for_pack(pack_name)
    if status ~= "initial" and status ~= "research" then
      fail(pack_name .. " has no progression-authoritative ordinary route: " .. tostring(status) .. ".")
    end
    if not route or route.recipe ~= pack_name
        or route.route_class ~= route_policy.classes.ordinary_primary then
      fail(pack_name .. " selected " .. tostring(route and route.recipe)
        .. " class=" .. tostring(route and route.route_class) .. " instead of its ordinary primary route.")
    end
    if prerequisite == "cube-mastery-4" or route.unlocker == "cube-mastery-4" then
      fail(pack_name .. " was delayed behind cube-mastery-4.")
    end
    if not decision or decision.status ~= "selected"
        or decision.selected_recipe ~= pack_name
        or (route.provenance or {}).candidate_route_count < 2 then
      fail(pack_name .. " lacks a deterministic multi-route selection witness.")
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

log("[mir-fixture-assert-cubium-production-routes] PASS packs=11 selected=ordinary-primary late-route=cube-mastery-4")

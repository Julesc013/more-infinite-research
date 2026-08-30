local science = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local compiler_context = require(
  "__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local route_policy = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.production_route_policy")
local recipe_facts = require(
  "__more-infinite-research__.prototypes.mir.index.recipe_facts")

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
      local route = science.production_route_for_pack(pack_name)
      local decision = science.production_route_decision_for_pack(pack_name)
      if status ~= "initial" and status ~= "research" then
        fail(pack_name .. " lost its ordinary first-acquisition route.")
      end
      if not route or route.recipe == recycling_recipe
          or route.route_class == route_policy.classes.recycling then
        fail(pack_name .. " selected its recycler-1 recycling route.")
      end
      if prerequisite == "recycler-1" or route.unlocker == "recycler-1" then
        fail(pack_name .. " was delayed behind recycler-1.")
      end
      local rejected_recycling = false
      for _, rejected in ipairs((decision or {}).rejected_routes or {}) do
        if rejected.recipe == recycling_recipe
            and (rejected.route_class == route_policy.classes.recycling
              and rejected.reason == "non_authoritative_route_class"
              or rejected.route_class == route_policy.classes.self_return
                and rejected.reason == "self_return_cannot_prove_acquisition") then
          rejected_recycling = true
        end
      end
      if not rejected_recycling then
        local rejected = {}
        for _, row in ipairs((decision or {}).rejected_routes or {}) do
          table.insert(rejected, tostring(row.recipe) .. ":" .. tostring(row.route_class)
            .. ":" .. tostring(row.reason))
        end
        local candidates = {}
        for _, recipe_name in ipairs(recipe_facts.recipes_by_output_view(pack_name)) do
          local fact = recipe_facts.view(recipe_name) or {}
          table.insert(candidates, recipe_name .. ":" .. tostring(fact.source_class)
            .. ":" .. table.concat(fact.categories or {}, "+")
            .. ":ingredients=" .. table.concat(fact.ingredient_names or {}, "+"))
        end
        fail(pack_name .. " lacks an explainable rejected recycling-route witness: candidates="
          .. tostring((decision or {}).candidate_route_count) .. " selected="
          .. tostring((decision or {}).selected_recipe) .. " rejected=" .. table.concat(rejected, ",")
          .. " facts=" .. table.concat(candidates, ",") .. ".")
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

log("[mir-fixture-assert-recycler-progression-routes] PASS recycler-1-routes-rejected=true")

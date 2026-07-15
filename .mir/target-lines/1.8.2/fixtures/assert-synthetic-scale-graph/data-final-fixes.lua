local function fail(message)
  error("MIR synthetic scale validation failed: " .. message)
end

local prototype = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-coverage-report"]
local summary = prototype and prototype.data and prototype.data.summary
if not summary then fail("coverage summary is missing") end

local minimums = {
  total_recipes = 1000,
  accounted_recipes = 1000,
  candidate_count = 1000,
  technology_count = 1000,
  technology_effect_count = 10000,
  graph_edge_count = 999
}
for field, minimum in pairs(minimums) do
  if (tonumber(summary[field]) or 0) < minimum then
    fail(field .. " expected at least " .. minimum .. ", got " .. tostring(summary[field]))
  end
end
if summary.accounted_recipes ~= summary.total_recipes then fail("recipe accounting is incomplete") end
if summary.dangling_effects ~= 0 then fail("dangling recipe effects were found") end
if summary.duplicate_owners ~= 0 then fail("duplicate recipe owners were found") end
if summary.recipe_fact_scan_count ~= 1 then fail("recipe facts were rebuilt") end
if summary.technology_scan_count ~= 1 then fail("technology coverage scan count changed") end

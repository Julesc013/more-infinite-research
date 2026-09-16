local technology_name = "recipe-prod-research_copper-1"
local policy_name = "more-infinite-research-maximum-level-policy"

local function fail(message)
  error("[mir42-v2-v3-cap-migration] " .. message)
end

local technology = data.raw.technology[technology_name]
if not technology or technology.max_level ~= "infinite" then
  fail("Copper maximum-level anchor is not lossless infinite")
end

local policy = data.raw["mod-data"] and data.raw["mod-data"][policy_name]
local artifact = policy and policy.data
if not artifact or (artifact.schema ~= 2 and artifact.schema ~= 3) then
  fail("Expected predecessor V2 or current V3 maximum-level policy transport")
end
if artifact.schema == 2 and artifact.kind ~= "MIRMaximumLevelPolicyV2" then
  fail("V2 predecessor maximum-level policy kind differs")
end
if artifact.schema == 3 and artifact.kind ~= "MIRMaximumLevelPolicyV3" then
  fail("V3 candidate maximum-level policy kind differs")
end

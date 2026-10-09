local technology_name = "recipe-prod-research_copper-1"
local policy_name = "more-infinite-research-maximum-level-policy"

local function fail(message)
  error("[late-mir42-cap-binding-blocker] " .. message)
end

local policy_data = data.raw["mod-data"] and data.raw["mod-data"][policy_name]
local policy = policy_data and policy_data.data
if not policy_data or policy_data.data_type ~= "more-infinite-research.maximum-level-policy-v3"
    or type(policy) ~= "table" or policy.schema ~= 3
    or policy.kind ~= "MIRMaximumLevelPolicyV3"
    or policy.finalizer_status ~= "accepted" then
  fail("requires an accepted V3 policy before the late mutation")
end

local binding, binding_count = nil, 0
for _, candidate in ipairs(policy.bindings or {}) do
  if candidate.technology_id == technology_name then
    binding = candidate
    binding_count = binding_count + 1
  end
end
if binding_count ~= 1 or not binding or binding.finalizer_observation.status ~= "accepted"
    or binding.finalizer_observation.observed_prototype_max_level ~= "infinite" then
  fail("requires the accepted Copper finalizer observation before the late mutation")
end

local technology = data.raw.technology[technology_name]
if not technology or technology.max_level ~= "infinite" then
  fail("requires an infinite Copper prototype before the late mutation")
end
technology.max_level = 5

log("[late-mir42-cap-binding-blocker] DATA technology=" .. technology_name
  .. " pre=infinite post=5 policy=v3")

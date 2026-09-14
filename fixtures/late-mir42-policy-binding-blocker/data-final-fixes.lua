local technology_name = "recipe-prod-research_copper-1"
local policy_name = "more-infinite-research-maximum-level-policy"
local expected_adapter = "factorio-data-final-fixes-v1"

local function fail(message)
  error("[late-mir42-policy-binding-blocker] " .. message)
end

local policy_data = data.raw["mod-data"] and data.raw["mod-data"][policy_name]
local policy = policy_data and policy_data.data
if not policy_data or policy_data.data_type ~= "more-infinite-research.maximum-level-policy-v3"
    or type(policy) ~= "table" or policy.schema ~= 3
    or policy.kind ~= "MIRMaximumLevelPolicyV3"
    or policy.finalizer_status ~= "accepted"
    or policy.finalizer_adapter ~= expected_adapter
    or type(policy.artifact_fingerprint) ~= "string"
    or policy.artifact_fingerprint == "" then
  fail("requires a fully identified accepted V3 policy before the mutation")
end

local binding, count = nil, 0
for _, candidate in ipairs(policy.bindings or {}) do
  if candidate.technology_id == technology_name then
    binding = candidate
    count = count + 1
  end
end
if count ~= 1 or not binding
    or type(binding.binding_fingerprint) ~= "string"
    or binding.binding_fingerprint == ""
    or type(binding.finalizer_observation) ~= "table"
    or binding.finalizer_observation.adapter ~= expected_adapter
    or binding.finalizer_observation.status ~= "accepted"
    or binding.finalizer_observation.observed_prototype_max_level ~= "infinite" then
  fail("requires one fully identified accepted Copper binding before the mutation")
end

local technology = data.raw.technology[technology_name]
if not technology or technology.max_level ~= "infinite" then
  fail("requires the infinite Copper prototype to remain unchanged")
end

-- This is a late V3 forgery after the compiler has bound both identities.
-- Keep both fingerprint strings nonempty, but do not recompute either one.
binding.cap.effective = 4
log("[late-mir42-policy-binding-blocker] DATA technology=" .. technology_name
  .. " prototype=infinite cap-pre=3 cap-post=4 artifact-identity=stale")

local technology_name = "recipe-prod-research_copper-1"
local setting_name = "ips-max-level-research_copper"
local policy_name = "more-infinite-research-maximum-level-policy"

local function fail(message)
  error("[mir42-cap-ownership-multiforce] " .. message)
end

local function finite(value)
  local parsed = tonumber(value)
  if not parsed or parsed <= 0 then return nil end
  return math.floor(parsed)
end

local function binding_for(policy, technology)
  local result, count = nil, 0
  for _, binding in ipairs(policy.bindings or {}) do
    if binding.technology_id == technology then
      result = binding
      count = count + 1
    end
  end
  return result, count
end

local direct = settings.startup[setting_name]
if not direct then fail("Copper startup cap setting is absent") end
local expected_cap = finite(direct.value) or "infinite"

local mod_data = data.raw["mod-data"] and data.raw["mod-data"][policy_name]
if not mod_data or mod_data.data_type ~= "more-infinite-research.maximum-level-policy-v3" then
  fail("V3 maximum-level policy transport is absent")
end
local policy = mod_data.data
if type(policy) ~= "table" or policy.schema ~= 3
    or policy.kind ~= "MIRMaximumLevelPolicyV3"
    or policy.semantics ~= "absolute-highest-technology-level"
    or policy.finalizer_adapter ~= "factorio-data-final-fixes-v1"
    or policy.finalizer_status ~= "accepted" then
  fail("V3 maximum-level policy header differs")
end

local binding, binding_count = binding_for(policy, technology_name)
if binding_count ~= 1 or not binding or binding.record_type ~= "MaximumLevelBinding"
    or binding.binding.source ~= "generated-stream"
    or binding.binding.scope ~= "exact-stream"
    or binding.binding.operation ~= "emit"
    or binding.setting.name ~= setting_name
    or binding.cap.semantics ~= "absolute-highest-technology-level"
    or binding.cap.effective ~= expected_cap
    or binding.prototype_strategy.mode ~= "lossless-infinite-prototype"
    or binding.prototype_strategy.max_level ~= "infinite"
    or binding.finalizer_observation.adapter ~= "factorio-data-final-fixes-v1"
    or binding.finalizer_observation.status ~= "accepted"
    or binding.finalizer_observation.observed_prototype_max_level ~= "infinite"
    or binding.diagnostics.status ~= "accepted" then
  fail("Copper V3 maximum-level binding differs")
end

if expected_cap == "infinite" then
  if binding.runtime_strategy.mode ~= "unbounded" then
    fail("infinite Copper cap has a finite runtime strategy")
  end
else
  if binding.runtime_strategy.mode ~= "absolute-cap-controller"
      or binding.runtime_strategy.queue ~= "remove-only-levels-above-effective-cap"
      or binding.runtime_strategy.restoration ~= "restore-only-mir-disabled-technologies"
      or binding.presentation_strategy.mode ~= "finite-runtime-cap"
      or binding.presentation_strategy.visible_when_disabled ~= true then
    fail("finite Copper cap runtime/presentation binding differs")
  end
end

local technology = data.raw.technology[technology_name]
if not technology or technology.max_level ~= "infinite" then
  fail("Copper prototype was not preserved as infinite before late finalization")
end

log("[mir42-cap-ownership-multiforce] DATA policy=v3 technology=" .. technology_name
  .. " cap=" .. tostring(expected_cap) .. " finalizer=accepted prototype=infinite")

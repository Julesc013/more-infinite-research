local policy = require("__more-infinite-research__.prototypes.mir.compatibility.policies.k2_science_phase")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")

local function fail(message)
  error("MIR K2 science phase policy validation failed: " .. message)
end

local function assert_equal(left, right, message)
  if fingerprint.of(left) ~= fingerprint.of(right) then fail(message) end
end

local policy_id = policy.policy_id
local policy_v2 = policy_id == "K2SciencePhasePolicyV2"
if policy_id ~= "K2SciencePhasePolicyV1" and not policy_v2 then
  fail("unsupported K2 science phase policy " .. tostring(policy_id) .. ".")
end

local capabilities = {science_packs = {}}
if policy_v2 then
  for _, name in ipairs(policy.required_science_packs()) do capabilities.science_packs[name] = true end
end

local f210_versions = {
  Krastorio2 = "2.1.2",
  ["Krastorio2-spaced-out"] = "2.0.13"
}
if policy_v2 then f210_versions.base = "2.1.14" end

local f200_versions = {
  base = "2.0.73",
  ["Krastorio2-spaced-out"] = "1.6.21"
}

local f200_capabilities = {science_packs = {}}
for name, present in pairs(capabilities.science_packs) do f200_capabilities.science_packs[name] = present end
f200_capabilities.science_packs["kr-basic-tech-card"] = nil

local phase_two_input = {
  {"kr-basic-tech-card", 2},
  {type = "item", name = "automation-science-pack", amount = 3},
  {"logistic-science-pack", 4},
  {"military-science-pack", 5},
  {"chemical-science-pack", 6},
  {"production-science-pack", 7},
  {type = "item", name = "space-science-pack", amount = 8}
}
local phase_two_before = fingerprint.of(phase_two_input)
local normalized, decision = policy.normalize(phase_two_input, f210_versions, capabilities)
if fingerprint.of(phase_two_input) ~= phase_two_before then fail("normalization mutated its input.") end
if decision.policy_id ~= policy_id or decision.status ~= "normalized"
    or decision.applicable ~= true or decision.changed ~= true then
  fail("qualified Factorio 2.1 K2/K2SO normalization did not emit the expected decision.")
end
if policy_v2 and (decision.matched_profile ~= "factorio-2.1-k2so" or decision.qualified_target ~= "f210") then
  fail("qualified Factorio 2.1 K2/K2SO normalization matched the wrong V2 profile.")
end
assert_equal(normalized, {
  {"production-science-pack", 7},
  {type = "item", name = "space-science-pack", amount = 8}
}, "phase-two normalization did not preserve order, shapes, and amounts.")
if #normalized == 0 then fail("phase-two normalization emitted an empty ingredient list.") end

local repeated, repeated_decision = policy.normalize(normalized, f210_versions, capabilities)
assert_equal(repeated, normalized, "normalization was not idempotent.")
if repeated_decision.status ~= "already-normalized" or repeated_decision.changed ~= false then
  fail("idempotent normalization did not report already-normalized.")
end

local phase_one_input = {
  {"kr-basic-tech-card", 1},
  {"automation-science-pack", 2},
  {"production-science-pack", 3}
}
local phase_one = policy.normalize(phase_one_input, f210_versions, capabilities)
assert_equal(phase_one, {
  {"automation-science-pack", 2},
  {"production-science-pack", 3}
}, "production/utility phase did not remove only the K2 basic card.")
if #phase_one == 0 then fail("phase-one normalization emitted an empty ingredient list.") end

if policy_v2 then
for label, versions in pairs({
  f210_lower_endpoint = {base = "2.1.0", Krastorio2 = "2.1.2", ["Krastorio2-spaced-out"] = "2.0.11"},
  f210_interior_patch = {base = "2.1.14", Krastorio2 = "2.1.2", ["Krastorio2-spaced-out"] = "2.0.12"},
  f200_standalone = f200_versions
}) do
  local facts = label == "f200_standalone" and f200_capabilities or capabilities
  local result, qualified = policy.normalize(phase_two_input, versions, facts)
  assert_equal(result, normalized, label .. " did not normalize through its bounded envelope.")
  if qualified.applicable ~= true or qualified.status ~= "normalized" then
    fail(label .. " was not admitted by the bounded envelope.")
  end
end

local f200_result, f200_decision = policy.normalize(phase_two_input, f200_versions, f200_capabilities)
assert_equal(f200_result, normalized, "Factorio 2.0 standalone K2SO did not normalize science.")
if f200_decision.matched_profile ~= "factorio-2.0-k2so-standalone" or f200_decision.qualified_target ~= "f200" then
  fail("Factorio 2.0 standalone K2SO matched the wrong profile.")
end

local missing_capability = {science_packs = {}}
for name, present in pairs(capabilities.science_packs) do missing_capability.science_packs[name] = present end
missing_capability.science_packs["kr-singularity-tech-card"] = nil

for label, envelope in pairs({
  absent = {versions = {}, facts = capabilities},
  k2_only = {versions = {base = "2.1.14", Krastorio2 = "2.1.2"}, facts = capabilities},
  below_f210 = {versions = {base = "2.1.14", Krastorio2 = "2.1.2", ["Krastorio2-spaced-out"] = "2.0.10"}, facts = capabilities},
  above_f210 = {versions = {base = "2.1.14", Krastorio2 = "2.1.2", ["Krastorio2-spaced-out"] = "2.0.14"}, facts = capabilities},
  wrong_k2 = {versions = {base = "2.1.14", Krastorio2 = "2.1.3", ["Krastorio2-spaced-out"] = "2.0.13"}, facts = capabilities},
  f200_with_forbidden_k2 = {versions = {base = "2.0.73", Krastorio2 = "2.1.2", ["Krastorio2-spaced-out"] = "1.6.21"}, facts = capabilities},
  missing_capability = {versions = f210_versions, facts = missing_capability}
}) do
  local untouched, inactive = policy.normalize(phase_two_input, envelope.versions, envelope.facts)
  assert_equal(untouched, phase_two_input, label .. " envelope unexpectedly changed science.")
  if inactive.status ~= "not-applicable" or inactive.applicable ~= false or inactive.changed ~= false then
    fail(label .. " envelope did not fail closed as not-applicable.")
  end
end
else
for label, versions in pairs({
  absent = {},
  k2_only = {Krastorio2 = "2.1.2"},
  wrong_k2 = {Krastorio2 = "2.1.1", ["Krastorio2-spaced-out"] = "2.0.13"},
  wrong_k2so = {Krastorio2 = "2.1.2", ["Krastorio2-spaced-out"] = "2.0.12"}
}) do
  local untouched, inactive = policy.normalize(phase_two_input, versions)
  assert_equal(untouched, phase_two_input, label .. " envelope unexpectedly changed science.")
  if inactive.status ~= "not-applicable" or inactive.applicable ~= false or inactive.changed ~= false then
    fail(label .. " envelope did not fail closed as not-applicable.")
  end
end
end

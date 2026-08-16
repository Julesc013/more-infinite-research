local policy = require("__more-infinite-research__.prototypes.mir.compatibility.policies.k2_science_phase")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")

local function fail(message)
  error("MIR K2 science phase policy validation failed: " .. message)
end

local function assert_equal(left, right, message)
  if fingerprint.of(left) ~= fingerprint.of(right) then fail(message) end
end

local exact_versions = {
  Krastorio2 = "2.1.2",
  ["Krastorio2-spaced-out"] = "2.0.13"
}

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
local normalized, decision = policy.normalize(phase_two_input, exact_versions)
if fingerprint.of(phase_two_input) ~= phase_two_before then fail("normalization mutated its input.") end
if decision.policy_id ~= "K2SciencePhasePolicyV1" or decision.status ~= "normalized"
    or decision.applicable ~= true or decision.changed ~= true then
  fail("exact K2/K2SO normalization did not emit the expected decision.")
end
assert_equal(normalized, {
  {"production-science-pack", 7},
  {type = "item", name = "space-science-pack", amount = 8}
}, "phase-two normalization did not preserve order, shapes, and amounts.")
if #normalized == 0 then fail("phase-two normalization emitted an empty ingredient list.") end

local repeated, repeated_decision = policy.normalize(normalized, exact_versions)
assert_equal(repeated, normalized, "normalization was not idempotent.")
if repeated_decision.status ~= "already-normalized" or repeated_decision.changed ~= false then
  fail("idempotent normalization did not report already-normalized.")
end

local phase_one_input = {
  {"kr-basic-tech-card", 1},
  {"automation-science-pack", 2},
  {"production-science-pack", 3}
}
local phase_one = policy.normalize(phase_one_input, exact_versions)
assert_equal(phase_one, {
  {"automation-science-pack", 2},
  {"production-science-pack", 3}
}, "production/utility phase did not remove only the K2 basic card.")
if #phase_one == 0 then fail("phase-one normalization emitted an empty ingredient list.") end

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

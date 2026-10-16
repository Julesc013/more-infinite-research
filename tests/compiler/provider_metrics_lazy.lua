-- Host-only controls for the ProviderMetrics lazy-inspection boundary.  The
-- resolver below is the real source module; surrounding provider data is a
-- deliberately small deterministic fixture.
local resolver = assert(PROVIDER_METRICS_LAZY_RESOLVER, "Missing resolver module")
local fingerprint = assert(PROVIDER_METRICS_LAZY_FINGERPRINT, "Missing fingerprint module")

local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

local function expect_error(callback, expected)
  local ok, message = pcall(callback)
  check(not ok and string.find(tostring(message), expected, 1, true) ~= nil,
    "Expected refusal: " .. expected .. "; got " .. tostring(message))
end

local resolution = resolver.view()
check(resolution.provider_metrics == nil,
  "Normal family resolution must not materialize ProviderMetrics")
check(resolution.provider_metric_inputs == nil
    and type(TEST_PROVIDER_CONTEXT.states.provider_metric_inspection_inputs) == "table"
    and TEST_PROVIDER_CONTEXT.states.provider_metric_inspection_inputs.environment_fingerprint == "environment-a",
  "Normal family snapshots must omit the small pre-emission inspection anchor")

local projection = resolver.compilation_projection()
check(projection.schema == 1 and #projection.decisions == 4
    and projection.decision_set_fingerprint == resolution.decision_set_fingerprint,
  "Compilation projection retains the complete decision rows and their identity")
check(projection.attachments == nil and projection.provider_cardinality == nil
    and projection.provider_metric_inputs == nil and projection.provider_metrics == nil,
  "Compilation projection omits non-decision resolver material")
check(TEST_PROVIDER_METRIC_BUILDS == 0,
  "Normal resolution and compilation projection must not build ProviderMetrics")

local before_mutation = fingerprint.of(projection)
projection.decisions[1].risk_disposition = "tampered"
check(fingerprint.of(projection) ~= before_mutation,
  "A deep decision mutation remains visible to the compilation-input fingerprint")
projection.decisions[1].risk_disposition = "NONE"

check(resolver.metrics_for_provider("unknown-provider") == nil
    and TEST_PROVIDER_METRIC_BUILDS == 0,
  "Unknown provider inspection must not manufacture a metric record")

local anchors = TEST_PROVIDER_CONTEXT.states.provider_metric_inspection_inputs
check(anchors.metric_rows_by_provider["provider-a"][1].recipe == "recipe-z"
    and anchors.metric_rows_by_provider["provider-a"][2].recipe == "recipe-a",
  "Lazy inspection retains the pre-sort provider row order for metric witnesses")
local reference = PROVIDER_METRICS_LAZY_REAL_METRICS.build(
  TEST_PROVIDER_LAST_RULE,
  anchors.metric_rows_by_provider["provider-a"],
  resolution.provider_cardinality["provider-a"],
  {
    researchability_index = TEST_PROVIDER_CONTEXT.states.technology_researchability_index,
    environment_identity = anchors.environment_identity,
    environment_fingerprint = anchors.environment_fingerprint,
    phase_seconds = anchors.phase_seconds["provider-a"]
  }
)
local first = resolver.metrics_for_provider("provider-a")
check(TEST_PROVIDER_METRIC_BUILDS == 1 and first.provider_id == "provider-a"
    and first.family_id == "family-b"
    and first.environment_identity.environment_fingerprint == "environment-a",
  "Explicit inspection retains the former last-rule metadata for a shared provider id")
check(first.metrics.earliest_unlock_depth.witnesses[1] == "recipe-z@automation=1",
  "Lazy inspection preserves the former pre-sort witness order")
check(fingerprint.of(first) == fingerprint.of(reference),
  "Lazy inspection preserves the exact eager ProviderMetrics rows, witnesses, and phase context")
first.metrics.member_count.value = 999
local second = resolver.metrics_for_provider("provider-a")
check(TEST_PROVIDER_METRIC_BUILDS == 2 and second.metrics.member_count.value == 4,
  "Inspection returns a defensive copy and does not retain caller mutation")

local inspection = resolver.inspection_snapshot()
check(TEST_PROVIDER_METRIC_BUILDS == 3 and inspection.provider_metrics["provider-a"] ~= nil,
  "Internal inspection materializes ProviderMetrics only when explicitly requested")
inspection.decisions[1].recipe = "caller-corruption"
inspection.provider_metrics["provider-a"].metrics.member_count.value = 123
local fresh_inspection = resolver.inspection_snapshot()
check(TEST_PROVIDER_METRIC_BUILDS == 4
    and fresh_inspection.decisions[1].recipe == "recipe-a"
    and fresh_inspection.provider_metrics["provider-a"].metrics.member_count.value == 4,
  "Inspection snapshots cannot mutate Context-owned decisions or later metric evidence")

TEST_PROVIDER_EPOCH = 2
expect_error(function() resolver.metrics_for_provider("provider-a") end,
  "recipe source epoch differs")
TEST_PROVIDER_EPOCH = 1

TEST_PROVIDER_CONTEXT.states.recipe_unlock_index = nil
expect_error(function() resolver.metrics_for_provider("provider-a") end,
  "pre-emission recipe unlock index is unavailable")
TEST_PROVIDER_CONTEXT.states.recipe_unlock_index = {
  recipe_source_epoch = 1, unlockers_by_recipe = { ["recipe-a"] = {"automation"} }
}

TEST_PROVIDER_CONTEXT.states.technology_researchability_index = nil
expect_error(function() resolver.metrics_for_provider("provider-a") end,
  "pre-emission researchability index is unavailable")

return {assertions = assertions, metric_builds = TEST_PROVIDER_METRIC_BUILDS}

-- Source-bound controls for the Context-owned Boolean lab-acquisition memo.
-- The production module is real; the runner supplies only a compact compiler
-- Context and acquisition solver so the tests can force epoch/input changes
-- which normal data-stage compilation must merely bypass.

local production = assert(CONTEXTUAL_BOOLEAN_ACQUISITION_MODULE)
local context = assert(TEST_BOOLEAN_CONTEXT)
local state = assert(TEST_BOOLEAN_STATE)
local owner = assert(TEST_BOOLEAN_OWNER)

local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

local function canonical_services()
  context.services["science.technology_researchability_reason"] = TEST_BOOLEAN_TECH_REASON
  context.services["science.pack_production_status"] = production.pack_production_status
  context.services["science.independent_pack_acquisition_witness"] = production.independent_pack_acquisition_witness
  context.services["science.item_acquisition_witness"] = production.item_acquisition_witness
end

local function reset_cache()
  owner.contextual_boolean_acquisition_memo = {}
  owner.contextual_boolean_acquisition_memo_key_count = 0
  owner.contextual_boolean_acquisition_memo_estimated_bytes = 0
  owner.contextual_boolean_acquisition_memo_source_epoch = nil
  owner.contextual_boolean_acquisition_memo_recipe_index_epoch = nil
  owner.contextual_boolean_acquisition_memo_research_index_epoch = nil
  owner.contextual_boolean_acquisition_memo_research_index_fingerprint = nil
  owner.contextual_boolean_acquisition_memo_root_generation = owner.root_entry_generation
  owner.contextual_boolean_acquisition_memo_stable_generation = state.stable_acquisition_generation
  owner.contextual_boolean_acquisition_memo_bindings = nil
end

canonical_services()
reset_cache()

local initial_calls = TEST_BOOLEAN_ACQUISITION_CALLS
local available, paired = production.item_acquisition_available("lab-kit", {pack = true}, {technology = true})
check(available == true and paired == true and TEST_BOOLEAN_ACQUISITION_CALLS == initial_calls + 1,
  "A canonical completed positive answer must use the cold acquisition proof once")
available, paired = production.item_acquisition_available("lab-kit", {pack = true}, {technology = true})
check(available == true and paired == true and TEST_BOOLEAN_ACQUISITION_CALLS == initial_calls + 1,
  "An exact fresh Boolean query must reuse only the retained true answer")
check((owner.contextual_boolean_acquisition_memo_key_count or 0) == 1,
  "The Boolean memo retains one compact answer, never a witness graph")

TEST_BOOLEAN_RETURN_FALSE = true
local before_false = TEST_BOOLEAN_ACQUISITION_CALLS
local false_one = production.item_acquisition_available("false-kit", {pack = true}, {technology = true})
local false_two = production.item_acquisition_available("false-kit", {pack = true}, {technology = true})
TEST_BOOLEAN_RETURN_FALSE = false
check(false_one == false and false_two == false and TEST_BOOLEAN_ACQUISITION_CALLS == before_false + 2,
  "False and nil acquisition outcomes must remain cold and never enter the positive memo")

local before_guard_change = TEST_BOOLEAN_ACQUISITION_CALLS
production.item_acquisition_available("lab-kit", {other_pack = true}, {technology = true})
state.visiting["item\0outer"] = true
production.item_acquisition_available("lab-kit", {pack = true}, {technology = true})
state.visiting["item\0outer"] = nil
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_guard_change + 2,
  "Pack and acquisition ancestry changes must not reuse an otherwise valid true answer")

local observer = {}
local before_observer = TEST_BOOLEAN_ACQUISITION_CALLS
production.item_acquisition_available("observed-kit", {pack = true}, {technology = true}, observer)
production.item_acquisition_available("observed-kit", {pack = true}, {technology = true}, observer)
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_observer + 2,
  "Observers retain two cold proofs so their callback-visible work is never skipped")

local before_public = TEST_BOOLEAN_ACQUISITION_CALLS
local public_one = production.item_acquisition_witness("lab-kit", {pack = true}, {technology = true})
local public_two = production.item_acquisition_witness("lab-kit", {pack = true}, {technology = true})
check(public_one ~= nil and public_two ~= nil and public_one ~= public_two
    and TEST_BOOLEAN_ACQUISITION_CALLS == before_public + 2,
  "Public witnesses never use the Boolean cache and retain their copied-result boundary")
public_one.child.kind = "caller-mutated"
check(TEST_BOOLEAN_WITNESS.child.kind == "private-child" and public_two.child.kind == "private-child",
  "Boolean caching cannot expose or mutate the private public-witness source graph")

reset_cache()
TEST_BOOLEAN_MUTATE_ROOT = true
local before_root_race = TEST_BOOLEAN_ACQUISITION_CALLS
production.item_acquisition_available("root-race", {pack = true}, {technology = true})
TEST_BOOLEAN_MUTATE_ROOT = false
check((owner.contextual_boolean_acquisition_memo_key_count or 0) == 0,
  "A root generation change during proof rejects Boolean retention")
production.item_acquisition_available("root-race", {pack = true}, {technology = true})
production.item_acquisition_available("root-race", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_root_race + 2,
  "After a root-race refusal, the next completed proof is cold once then reusable")

reset_cache()
TEST_BOOLEAN_MUTATE_STABLE = true
local before_stable_race = TEST_BOOLEAN_ACQUISITION_CALLS
production.item_acquisition_available("stable-race", {pack = true}, {technology = true})
TEST_BOOLEAN_MUTATE_STABLE = false
check((owner.contextual_boolean_acquisition_memo_key_count or 0) == 0,
  "A stable acquisition generation change during proof rejects Boolean retention")
production.item_acquisition_available("stable-race", {pack = true}, {technology = true})
production.item_acquisition_available("stable-race", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_stable_race + 2,
  "After a stable-race refusal, the next completed proof is cold once then reusable")

reset_cache()
local changing_packs = {pack = true}
TEST_BOOLEAN_MUTATE_PACK_GUARDS = changing_packs
production.item_acquisition_available("guard-race", changing_packs, {technology = true})
TEST_BOOLEAN_MUTATE_PACK_GUARDS = nil
check((owner.contextual_boolean_acquisition_memo_key_count or 0) == 0,
  "Mutating caller ancestry during proof rejects Boolean retention")

reset_cache()
local before_index_race = TEST_BOOLEAN_ACQUISITION_CALLS
TEST_BOOLEAN_MUTATE_RECIPE_EPOCH = true
production.item_acquisition_available("index-race", {pack = true}, {technology = true})
TEST_BOOLEAN_MUTATE_RECIPE_EPOCH = false
check((owner.contextual_boolean_acquisition_memo_key_count or 0) == 0,
  "A recipe-index epoch change during proof rejects Boolean retention")
production.item_acquisition_available("index-race", {pack = true}, {technology = true})
production.item_acquisition_available("index-race", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_index_race + 2,
  "Index-race refusal returns to a cold proof and only then admits a current answer")

reset_cache()
local before_service_change = TEST_BOOLEAN_ACQUISITION_CALLS
context.services["science.pack_production_status"] = function() return "foreign" end
production.item_acquisition_available("service-race", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_service_change + 1,
  "A replaced contextual service bypasses the Boolean memo but retains the cold proof")
canonical_services()
production.item_acquisition_available("service-race", {pack = true}, {technology = true})
production.item_acquisition_available("service-race", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_service_change + 2,
  "Restoring canonical services requires one fresh proof before a Boolean hit")

local before_witness_replacement = TEST_BOOLEAN_ACQUISITION_CALLS
context.services["science.item_acquisition_witness"] = function() return nil end
local unavailable, unpaired = production.item_acquisition_available("lab-kit", {pack = true}, {technology = true})
check(unavailable == nil and unpaired == false and TEST_BOOLEAN_ACQUISITION_CALLS == before_witness_replacement,
  "A replaced public witness service refuses Boolean use before any cached or cold result")
canonical_services()

owner.contextual_boolean_acquisition_memo_key_count = 512
local before_capacity = TEST_BOOLEAN_ACQUISITION_CALLS
production.item_acquisition_available("capacity", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_capacity + 1,
  "A full Boolean cache refuses only retention and still returns the complete cold answer")

reset_cache()
TEST_BOOLEAN_MUTATE_SOURCE = true
production.item_acquisition_available("source-race", {pack = true}, {technology = true})
TEST_BOOLEAN_MUTATE_SOURCE = false
check((owner.contextual_boolean_acquisition_memo_key_count or 0) == 0,
  "A recipe-source epoch change during proof rejects Boolean retention")
TEST_BOOLEAN_SOURCE_EPOCH = "boolean-epoch-a"

reset_cache()
local before_state_replacement = TEST_BOOLEAN_ACQUISITION_CALLS
production.item_acquisition_available("state-replacement", {pack = true}, {technology = true})
TEST_BOOLEAN_REPLACE_ROUTE_STATE()
production.item_acquisition_available("state-replacement", {pack = true}, {technology = true})
production.item_acquisition_available("state-replacement", {pack = true}, {technology = true})
check(TEST_BOOLEAN_ACQUISITION_CALLS == before_state_replacement + 2,
  "A same-epoch route-state replacement must bypass the old Boolean answer, then admit only the new state")

local counters = context:state_view("compiler_telemetry").counters
check((counters.science_contextual_boolean_acquisition_hits or 0) >= 4
    and (counters.science_contextual_boolean_acquisition_generation_refusals or 0) >= 4
    and (counters.science_contextual_boolean_acquisition_capacity_refusals or 0) >= 1
    and (counters.science_contextual_boolean_acquisition_service_bypasses or 0) >= 1,
  "Telemetry records Boolean cache hits and conservative bypass/refusal reasons")

print("MIR-CONTEXTUAL-BOOLEAN-ACQUISITION-MEMO-PASS " .. assertions)
return {assertions = assertions, calls = TEST_BOOLEAN_ACQUISITION_CALLS}

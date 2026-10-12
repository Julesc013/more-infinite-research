local service = assert(ITEM_ACQUISITION_SERVICE_MODULE,
  "Missing item acquisition service module")

local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

check(service.item_acquisition_witness("") == nil and #TEST_ACQUISITION_CALLS == 0,
  "Invalid item names must not enter the private acquisition service")

local first = service.item_acquisition_witness("public-item")
local second = service.item_acquisition_witness("public-item")
check(first ~= nil and second ~= nil,
  "The controlled private acquisition witness must reach the public service")
check(first ~= TEST_PRIVATE_WITNESS and second ~= TEST_PRIVATE_WITNESS and first ~= second,
  "Each public item service result must be isolated from the private DAG and other callers")
check(#TEST_ACQUISITION_CALLS == 2 and TEST_ACQUISITION_CALLS[1].options.private_marker
    and TEST_ACQUISITION_CALLS[2].options.private_marker
    and TEST_ACQUISITION_CALLS[1].state == TEST_ACQUISITION_CALLS[2].state,
  "The opposing control must exercise repeated compiler-owned private acquisition calls")

local available, paired = service.item_acquisition_available("public-item")
check(available == true and paired == true and #TEST_ACQUISITION_CALLS == 3,
  "The canonical Boolean companion proves the same private route without exporting a witness")
check(type(available) == "boolean",
  "The Boolean companion cannot expose a mutable private witness graph")

TEST_ACQUISITION_RETURN_FALSE = true
local false_witness = service.item_acquisition_witness("public-item")
local false_available, false_paired = service.item_acquisition_available("public-item")
TEST_ACQUISITION_RETURN_FALSE = nil
check(false_witness == nil and false_available == false and false_paired == true
    and #TEST_ACQUISITION_CALLS == 5,
  "A false solver result has the same unavailable meaning through public and Boolean consumers")

TEST_SERVICE_CONTEXT.services["science.item_acquisition_witness"] = function() return nil end
local stale_available, stale_paired = service.item_acquisition_available("public-item")
check(stale_available == nil and stale_paired == false and #TEST_ACQUISITION_CALLS == 5,
  "A stale Boolean companion refuses a later replaced public witness service")

first.ingredients[1].kind = "caller-mutated-child"
first.machine.launcher.kind = "caller-mutated-launcher"
check(TEST_PRIVATE_WITNESS.ingredients[1].kind == "private-child"
    and TEST_PRIVATE_WITNESS.machine.launcher.kind == "private-launcher"
    and second.ingredients[1].kind == "private-child"
    and second.machine.launcher.kind == "private-launcher",
  "Mutating one public warm result must not alter the private memo graph or another result")

print("MIR-ITEM-ACQUISITION-SERVICE-ISOLATION-PASS " .. assertions)
return {assertions = assertions, calls = #TEST_ACQUISITION_CALLS}

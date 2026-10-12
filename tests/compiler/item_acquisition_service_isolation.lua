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

first.ingredients[1].kind = "caller-mutated-child"
first.machine.launcher.kind = "caller-mutated-launcher"
check(TEST_PRIVATE_WITNESS.ingredients[1].kind == "private-child"
    and TEST_PRIVATE_WITNESS.machine.launcher.kind == "private-launcher"
    and second.ingredients[1].kind == "private-child"
    and second.machine.launcher.kind == "private-launcher",
  "Mutating one public warm result must not alter the private memo graph or another result")

print("MIR-ITEM-ACQUISITION-SERVICE-ISOLATION-PASS " .. assertions)
return {assertions = assertions, calls = #TEST_ACQUISITION_CALLS}

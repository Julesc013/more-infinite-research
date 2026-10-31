-- This intentionally accelerates only the named MIR breeding stage so the
-- private native mechanism control can complete one real lab without changing
-- a runtime research-unit-count property.
local MAIN = "recipe-prod-research_breeding-1"
local value = data.raw.technology[MAIN]
assert(value ~= nil and value.unit ~= nil, "MIR breeding research is absent")
assert(value.unit.count == nil and value.unit.count_formula == "8000*2^(L-1)" and value.unit.time == 60,
  "MIR breeding research no longer has the pinned F200 native workload")

value.unit.count = nil
value.unit.count_formula = "1"
value.unit.time = 1

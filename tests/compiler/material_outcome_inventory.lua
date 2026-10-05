local inventory = dofile("fixtures/assert-f210-current-bob-angel-final-routes-observer/material-outcome-inventory.lua")
local assertions = 0
local function check(condition, message)
  assert(condition, message)
  assertions = assertions + 1
end
local function row(result, id)
  for _, value in ipairs(result.rows) do if value.id == id then return value end end
  error("Missing independent outcome " .. id)
end
local raw = {
  item = {["bob-tin-plate"] = {}, ["angels-plate-platinum"] = {hidden = true}, ["angels-wire-platinum"] = {}},
  recipe = {
    ["ordinary-tin"] = {results = {{type = "item", name = "bob-tin-plate", amount = 1}}},
    ["unselected-casting"] = {hidden = true, enabled = false, allow_productivity = false,
      results = {{type = "item", name = "angels-plate-platinum", amount = 4}}},
    ["wire-only"] = {results = {{type = "item", name = "angels-wire-platinum", amount = 5}}},
    ["fluid-collision"] = {results = {{type = "fluid", name = "bob-tin-plate", amount = 1}}},
    ["zero-result"] = {results = {{type = "item", name = "bob-tin-plate", amount = 0}}},
    ["zero-probability"] = {results = {{type = "item", name = "bob-tin-plate", amount = 1, probability = 0}}}
  }
}
local result = inventory.collect(raw)
check(#result.rows == 17, "sixteen requested outcomes and supplementary platinum wire stay separate")
check(result.complete and not result.acquisition_proved and not result.admission_granted,
  "a complete denominator grants neither acquisition proof nor admission")
check(row(result, "platinum/plate").status == "observed"
    and row(result, "platinum/plate").present_items[1].hidden,
  "a hidden platinum plate remains a separate observed plate subject")
check(row(result, "platinum/wire").producers[1].name == "wire-only",
  "wire is observed through its own producer")
check(#row(result, "tin/plate").producers == 1,
  "typed fluid collisions, zero quantity and zero probability do not become item producers")
raw.recipe["independent-zero"] = {results = {{name = "bob-tin-plate", amount = 1, probability = 1, independent_probability = 0}}}
check(#row(inventory.collect(raw), "tin/plate").producers == 1,
  "an explicit zero independent probability does not borrow an ordinary probability")
check(row(result, "gold/plate").status == "prototype-absent", "provider absence is explicit")
local producer = row(result, "platinum/plate").producers[1]
check(producer.hidden and not producer.enabled_without_research and producer.declared_allow_productivity == false,
  "hidden, research-locked and productivity-denied routes stay visible in the independent denominator")
local gaps = inventory.route_gaps(result, {"ordinary-tin", "wire-only"})
check(#gaps == 1 and gaps[1].subject == "platinum/plate" and gaps[1].recipe == "unselected-casting",
  "deliberately omitted casting is detected independently of MIR's selected families")
check(#inventory.route_gaps(result, {"ordinary-tin", "wire-only", "unselected-casting"}) == 0,
  "recording the missing route closes observation coverage only")
local wire_raw = {item = {["angels-wire-platinum"] = {}}, recipe = {wire = raw.recipe["wire-only"]}}
local wire_inventory = inventory.collect(wire_raw)
check(row(wire_inventory, "platinum/plate").status == "prototype-absent"
    and row(wire_inventory, "platinum/wire").status == "observed",
  "wire coverage cannot satisfy plate absence")
local unavailable_producer = inventory.collect({item = {["bob-tin-plate"] = {}}, recipe = {}})
check(row(unavailable_producer, "tin/plate").status == "no-observed-producer",
  "a prototype alone does not establish even an observed producer")
check(not pcall(inventory.collect, raw, {recipes = 1}), "recipe traversal fails closed at its budget")
check(not pcall(inventory.collect, raw, {results = 1}), "result traversal fails closed at its budget")
check(not pcall(inventory.collect, raw, {recipes = math.huge}), "unbounded budgets are rejected")
check(not pcall(inventory.route_gaps, {complete = false}, {}), "incomplete inventories cannot prove route coverage")
check(not pcall(inventory.route_gaps, result, {"ordinary-tin", "ordinary-tin"}),
  "duplicate observation identities cannot conceal a missing route")
check(raw.recipe["unselected-casting"].allow_productivity == false
    and raw.recipe["unselected-casting"].enabled == false and raw.item["angels-plate-platinum"].hidden,
  "read-only inventory preserves upstream permissions and visibility")
local lines = inventory.lines(result, {"ordinary-tin", "wire-only"})
check(lines[#lines]:find("PASS complete=true phase=finalized-raw-prototypes subjects=17", 1, true)
    and lines[#lines]:find("gaps=1 acquisition=false admission=false", 1, true),
  "the consumed observer log states completeness and preserves non-admission")
local gap_line
for _, line in ipairs(lines) do if line:find("GAP subject=platinum/plate", 1, true) then gap_line = line end end
check(gap_line and gap_line:find("recipe=unselected-casting", 1, true), "the log names the omitted casting route")
raw.recipe["named route%one"] = {results = {{name = "bob-tin-plate", amount = 1}}}
local encoded = table.concat(inventory.lines(inventory.collect(raw), {}), "\n")
check(encoded:find("recipe=named%20route%25one", 1, true), "identity tokens escape whitespace and literal percent")
print(encoded)

local fluid_start_assertions = assertions
local fluid_raw = {
  item = {["angels-liquid-glycerol"] = {}},
  fluid = {["angels-liquid-nitric-acid"] = {}, ["angels-liquid-hydrochloric-acid"] = {hidden = true},
    ["angels-liquid-hydrofluoric-acid"] = {}},
  recipe = {
    ["named-acid"] = {results = {{type = "fluid", name = "angels-liquid-nitric-acid", amount = 50}}},
    ["unselected-synthesis"] = {hidden = true, enabled = false, allow_productivity = false,
      results = {{type = "fluid", name = "angels-liquid-hydrochloric-acid", amount = 70},
        {type = "item", name = "salt", amount = 3}}},
    ["fluid-item-collision"] = {results = {{type = "item", name = "angels-liquid-hydrofluoric-acid", amount = 50}}},
    ["untyped-collision"] = {results = {{name = "angels-liquid-hydrofluoric-acid", amount = 50}}},
    ["zero-fluid"] = {results = {{type = "fluid", name = "angels-liquid-hydrofluoric-acid", amount = 0}}},
    ["zero-fluid-probability"] = {results = {{type = "fluid", name = "angels-liquid-hydrofluoric-acid", amount = 50, probability = 0}}},
    ["zero-independent-fluid"] = {results = {{type = "fluid", name = "angels-liquid-hydrofluoric-acid", amount = 50, probability = 1, independent_probability = 0}}}
  }
}
local fluids = inventory.collect_petrochem(fluid_raw)
check(#fluids.rows == 4 and fluids.kind == "MIRFluidMaterialOutcomeInventoryV1",
  "four chemical fluids have a separate typed inventory")
check(fluids.complete and not fluids.acquisition_proved and not fluids.admission_granted,
  "a fluid inventory grants no acquisition or admission")
check(row(fluids, "nitric-acid/fluid").producers[1].name == "named-acid",
  "a finalized typed fluid producer is observed")
check(row(fluids, "hydrochloric-acid/fluid").present_fluids[1].hidden
    and row(fluids, "hydrochloric-acid/fluid").producers[1].declared_allow_productivity == false,
  "hidden fluids and denied coproduct routes remain visible as observations")
check(row(fluids, "hydrofluoric-acid/fluid").status == "no-observed-producer",
  "same-named items, untyped results, zero quantity and zero probabilities do not qualify as fluid producers")
check(row(fluids, "glycerol/fluid").status == "prototype-absent",
  "a same-named item cannot supply the required fluid prototype")
local fluid_gaps = inventory.route_gaps(fluids, {"named-acid"})
check(#fluid_gaps == 1 and fluid_gaps[1].subject == "hydrochloric-acid/fluid"
    and fluid_gaps[1].recipe == "unselected-synthesis",
  "the denominator detects a producer outside named MIR selectors")
check(#inventory.route_gaps(fluids, {"named-acid", "unselected-synthesis"}) == 0,
  "observation coverage closes only after the second producer is captured")
check(not pcall(inventory.collect_petrochem, fluid_raw, {recipes = 1})
    and not pcall(inventory.collect_petrochem, fluid_raw, {results = 1}),
  "fluid traversal consumes the existing recipe and result budgets")
check(#inventory.collect(fluid_raw).rows == 17
    and row(inventory.collect(fluid_raw), "tin/plate").status == "prototype-absent",
  "the original item denominator remains independent of chemical observations")
check(fluid_raw.recipe["unselected-synthesis"].allow_productivity == false
    and fluid_raw.recipe["unselected-synthesis"].results[2].amount == 3,
  "fluid observations preserve upstream permission and coproduct quantities")
local fluid_lines = inventory.lines(fluids, {"named-acid"})
check(fluid_lines[#fluid_lines]:find("subjects=4", 1, true)
    and fluid_lines[#fluid_lines]:find("gaps=1 acquisition=false admission=false", 1, true),
  "the fluid protocol retains a complete denominator and one real coverage gap")
print(table.concat(fluid_lines, "\n"))
print("[mir-f210-current-ba-final-observer] ROUTE recipe=named-acid family=nitric-acid shape=fluid status=present")
print("MIR-FLUID-MATERIAL-OUTCOME-INVENTORY-PASS " .. (assertions - fluid_start_assertions))
print("MIR-MATERIAL-OUTCOME-INVENTORY-PASS " .. assertions)

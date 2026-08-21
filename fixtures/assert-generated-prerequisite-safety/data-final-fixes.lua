local science = require("__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local compiler_context = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local route_policy = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.production_route_policy")

local function fail(message)
  error("MIR generated prerequisite safety validation failed: " .. message)
end

if data.raw.technology["worker-robots-storage-4"] then
  fail("base extension was emitted from disabled worker-robots-storage-3.")
end
if data.raw.technology["worker-robots-storage-3"].enabled ~= false then
  fail("disabled base-extension anchor was unexpectedly re-enabled.")
end
if data.raw.technology["automation-science-pack"].enabled ~= false then
  fail("disabled vanilla automation-science-pack technology was unexpectedly re-enabled.")
end
if data.raw.recipe["automation-science-pack"].enabled ~= true then
  fail("initially available automation-science-pack recipe was unexpectedly disabled.")
end

-- MIR's production CompilerContext is intentionally closed before dependent
-- mods enter data-final-fixes. Exercise the public science facade in a fresh,
-- fixture-owned context instead of reopening or depending on compiler state.
compiler_context.with_active(compiler_context.new({execution_mode = "SAFE"}), function()
local initial_status, initial_prerequisite = science.pack_production_status("mir-fixture-initial-science-pack")
if initial_status ~= "initial" or initial_prerequisite ~= nil then
  fail("already-enabled fixture science should have no inferred prerequisite.")
end

local fixture_pack = "mir-fixture-prerequisite-science-pack"
local fixture_status, fixture_prerequisite = science.pack_production_status(fixture_pack)
if fixture_status ~= "research" then
  fail("fixture science pack should require an enabled unlock technology, got " .. tostring(fixture_status) .. ".")
end
if fixture_prerequisite ~= "mir-fixture-custom-unlocker-a" then
  fail("deterministic unlock selection chose " .. tostring(fixture_prerequisite) .. ".")
end

local alternate_status, alternate_prerequisite = science.pack_production_status(
  "mir-fixture-alternate-route-science-pack")
if alternate_status ~= "research" then
  fail("alternate-route fixture science should be researchable, got " .. tostring(alternate_status) .. ".")
end
if alternate_prerequisite ~= "mir-fixture-z-early-route-unlocker" then
  fail("a later alternate route delayed science behind " .. tostring(alternate_prerequisite) .. ".")
end
local alternate_route = science.production_route_for_pack("mir-fixture-alternate-route-science-pack")
if not alternate_route or alternate_route.recipe ~= "mir-fixture-alternate-route-early" then
  fail("alternate-route provenance did not retain the earliest safe recipe.")
end
if alternate_route.route_class ~= route_policy.classes.ordinary_alternate then
  fail("alternate-route classification was " .. tostring(alternate_route.route_class) .. ".")
end
if alternate_route.provenance.selection_policy ~= "SciencePackProductionRoutePolicyV2" then
  fail("alternate-route provenance did not bind SciencePackProductionRoutePolicyV2.")
end
alternate_route.recipe = "tampered-by-fixture"
if science.production_route_for_pack("mir-fixture-alternate-route-science-pack").recipe
    ~= "mir-fixture-alternate-route-early" then
  fail("alternate-route cache escaped its defensive-copy boundary.")
end

local canonical_primary = {
  recipe = "mir-fixture-primary-science-pack",
  route_class = route_policy.classes.ordinary_primary,
  reachable = true,
  initial = false,
  prerequisite_closure = {"mir-fixture-primary-unlocker"},
  science_burden = {"automation-science-pack", "logistic-science-pack"},
  progression_key = {science_burden_count = 2, prerequisite_count = 1, unlock_depth = 4}
}
local misleading_later_alternate = {
  recipe = "mir-fixture-primary-science-pack-later-alternate",
  route_class = route_policy.classes.ordinary_alternate,
  reachable = true,
  initial = false,
  prerequisite_closure = {"mir-fixture-trigger-unlocker"},
  science_burden = {},
  progression_key = {science_burden_count = 0, prerequisite_count = 1, unlock_depth = 8}
}
local canonical_selected = route_policy.select({misleading_later_alternate, canonical_primary})
if not canonical_selected or canonical_selected.recipe ~= canonical_primary.recipe then
  fail("a later ordinary alternate replaced the reachable canonical primary route.")
end

local immediate_alternate = table.deepcopy(misleading_later_alternate)
immediate_alternate.initial = true
local immediate_selected = route_policy.select({canonical_primary, immediate_alternate})
if not immediate_selected or immediate_selected.recipe ~= immediate_alternate.recipe then
  fail("an immediately available ordinary alternate was not retained as first acquisition.")
end

local recycling_pack = "mir-fixture-recycling-alternate-science-pack"
local recycling_status, recycling_prerequisite = science.pack_production_status(recycling_pack)
if recycling_status ~= "research"
    or recycling_prerequisite ~= "mir-fixture-recycling-alternate-primary-unlocker" then
  fail("an initially enabled recycling route replaced the ordinary first-acquisition route: status="
    .. tostring(recycling_status) .. " prerequisite=" .. tostring(recycling_prerequisite) .. ".")
end
local recycling_route = science.production_route_for_pack(recycling_pack)
if not recycling_route
    or recycling_route.recipe ~= recycling_pack
    or recycling_route.route_class ~= route_policy.classes.ordinary_primary then
  fail("recycling demotion did not retain the ordinary primary route.")
end
local recycling_decision = science.production_route_decision_for_pack(recycling_pack)
if not recycling_decision
    or recycling_decision.status ~= "selected"
    or #recycling_decision.rejected_routes ~= 1
    or recycling_decision.rejected_routes[1].route_class ~= route_policy.classes.recycling then
  fail("recycling demotion did not retain an explainable rejected-route witness.")
end

for _, rejected_pack in ipairs({
  "mir-fixture-self-return-science-pack",
  "mir-fixture-recycling-only-science-pack"
}) do
  local status = science.pack_production_status(rejected_pack)
  if status ~= "unreachable" then
    fail(rejected_pack .. " used a non-authoritative recycling route for first acquisition.")
  end
  local decision = science.production_route_decision_for_pack(rejected_pack)
  if not decision or decision.status ~= "no-progression-authoritative-route"
      or #decision.rejected_routes ~= 1 then
    fail(rejected_pack .. " did not emit one stable rejected-route witness.")
  end
end

local declared_recycling = {
  recipe = "mir-fixture-declared-recycling-first",
  route_class = route_policy.classes.recycling,
  reachable = true,
  initial = true,
  prerequisite_closure = {},
  science_burden = {},
  progression_key = {},
  progression_authoritative = true,
  progression_authority = {
    kind = "exact-profile",
    id = "mir-fixture-declared-recycling-first",
    process_ir_certificate = "fixture-process-ir-certificate",
    target_proof = "fixture-f210-target-proof"
  }
}
local declared_selected = route_policy.select({declared_recycling})
if not declared_selected or declared_selected.recipe ~= declared_recycling.recipe then
  fail("an exact fully proved recycling-first declaration was not admitted.")
end

local incomplete_declaration = table.deepcopy(declared_recycling)
incomplete_declaration.progression_authority.target_proof = nil
if route_policy.select({incomplete_declaration}) ~= nil then
  fail("an incomplete recycling-first declaration was admitted.")
end

local declared_self_return = table.deepcopy(declared_recycling)
declared_self_return.route_class = route_policy.classes.self_return
if route_policy.select({declared_self_return}) ~= nil then
  fail("a declared self-return route was allowed to prove first acquisition.")
end

for _, unreachable_pack in ipairs({
  "mir-fixture-self-lock-science-pack",
  "mir-fixture-cycle-science-pack-a",
  "mir-fixture-cycle-science-pack-b",
  "mir-fixture-self-return-science-pack",
  "mir-fixture-recycling-only-science-pack"
}) do
  local status = science.pack_production_status(unreachable_pack)
  if status ~= "unreachable" then
    fail(unreachable_pack .. " should be unreachable, got " .. tostring(status) .. ".")
  end
end

local no_mechanism_technology = data.raw.technology["mir-fixture-no-research-mechanism-unlocker"]
local saved_unit = no_mechanism_technology.unit
no_mechanism_technology.unit = nil
local mechanism_reason = science.technology_researchability_reason("mir-fixture-no-research-mechanism-unlocker")
no_mechanism_technology.unit = saved_unit
if mechanism_reason ~= "missing-research-mechanism" then
  fail("missing-mechanism unlocker reason was " .. tostring(mechanism_reason) .. ".")
end

if #science.researchable_unlockers_for_recipe("mir-fixture-initial-science-pack") ~= 0 then
  fail("initially enabled recipe retained inferred unlock prerequisites.")
end

local technologies = data.raw.technology or {}
local complete = {}

local function assert_reachable(name, visiting, path)
  if complete[name] then return end
  if visiting[name] then
    fail("prerequisite cycle: " .. table.concat(path, " -> ") .. " -> " .. name .. ".")
  end

  local technology = technologies[name]
  if not technology then fail("missing prerequisite " .. tostring(name) .. ".") end
  if technology.enabled == false then fail("disabled prerequisite " .. name .. ".") end

  visiting[name] = true
  table.insert(path, name)
  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    assert_reachable(prerequisite, visiting, path)
  end
  table.remove(path)
  visiting[name] = nil
  complete[name] = true
end

local generated_count = 0
local fixture_pack_user_count = 0
local unreachable_pack_user_count = 0
local unreachable_packs = {
  ["mir-fixture-self-lock-science-pack"] = true,
  ["mir-fixture-cycle-science-pack-a"] = true,
  ["mir-fixture-cycle-science-pack-b"] = true,
  ["mir-fixture-self-return-science-pack"] = true,
  ["mir-fixture-recycling-only-science-pack"] = true
}
for name, technology in pairs(technologies) do
  if string.match(name, "^recipe%-prod%-research_") then
    generated_count = generated_count + 1
    assert_reachable(name, {}, {})

    for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
      local pack_name = ingredient.name or ingredient[1]
      local status = science.pack_production_status(pack_name)
      if status == "unreachable" then
        fail("generated technology " .. name .. " uses unreachable science pack " .. tostring(pack_name) .. ".")
      end
      if pack_name == fixture_pack then fixture_pack_user_count = fixture_pack_user_count + 1 end
      if unreachable_packs[pack_name] then unreachable_pack_user_count = unreachable_pack_user_count + 1 end
    end
  end
end

if generated_count == 0 then fail("no generated stream technologies were found.") end
if fixture_pack_user_count == 0 then fail("the all-science scenario did not exercise the fixture science pack.") end
if unreachable_pack_user_count ~= 0 then fail("generated streams retained unreachable fixture science packs.") end
end)

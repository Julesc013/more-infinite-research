local deepcopy = require("__more-infinite-research__.prototypes.mir.core.deepcopy")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local family_registry = require("__more-infinite-research__.prototypes.mir.families.registry")
local pack_schema = require("__more-infinite-research__.prototypes.mir.compatibility.packs.schema")
local pack_registry = require("__more-infinite-research__.prototypes.mir.compatibility.packs.registry")
local precedence = require("__more-infinite-research__.prototypes.mir.compatibility.packs.precedence")
local generation_plan = require("__more-infinite-research__.prototypes.mir.planner.generation_plan")

local function fail(message)
  error("MIR compiler contract validation failed: " .. message)
end

local function expect_error(label, expected, callback)
  local ok, message = pcall(callback)
  if ok then fail(label .. " did not fail") end
  if not tostring(message):find(expected, 1, true) then
    fail(label .. " failed with unexpected message: " .. tostring(message))
  end
end

local function valid_pack(id, line, mod_id, version)
  return {
    schema = 2,
    id = id,
    applicability = {mods = {{id = mod_id, version = version}}},
    aliases = {},
    exact = {includes = {}, excludes = {}},
    family_hints = {},
    science_roles = {},
    owner_claims = {},
    risk_overrides = {},
    targets = {factorio_lines = {line}},
    evidence = {fixtures = {"assert-compiler-contracts"}, real_mod = {}},
    claim = {level = "fixture-only", public = false}
  }
end

local function skip_row(stream_key, manifest_id)
  local function proof(evidence)
    return {passed = true, status = "not-applicable", evidence = {evidence}}
  end
  return {
    schema = 3,
    stream_key = stream_key,
    manifest_id = manifest_id,
    action = "skip",
    source = "compiler-contract-test",
    reason = "pure-test",
    gates = {
      target_supported = proof("test:target"),
      effect_valid = proof("test:effect"),
      owner_conflict_free = proof("test:owner"),
      science_compatible = proof("test:science"),
      lab_compatible = proof("test:lab"),
      prerequisites_acyclic = proof("test:prerequisite"),
      loop_safe = proof("test:loop"),
      progression_safe = proof("test:progression"),
      migration_safe = proof("test:migration"),
      output_identity_safe = proof("test:output")
    }
  }
end

local rules = family_registry.snapshot()
local reversed = {schema = 2, rules = {}}
for index = #rules.rules, 1, -1 do table.insert(reversed.rules, rules.rules[index]) end
local normalized = family_registry.validate(reversed)
for index = 2, #normalized.rules do
  if normalized.rules[index - 1].id >= normalized.rules[index].id then fail("FamilyRule sorting is unstable") end
end

local duplicate_rules = deepcopy(rules)
table.insert(duplicate_rules.rules, deepcopy(duplicate_rules.rules[1]))
expect_error("duplicate FamilyRule id", "Duplicate FamilyRule id", function() family_registry.validate(duplicate_rules) end)
local invalid_rule = deepcopy(rules)
invalid_rule.rules[1].require.lab_compatible = nil
expect_error("incomplete FamilyRule safety requirements", "hard evidence requirements are incomplete", function() family_registry.validate(invalid_rule) end)
local behavioral_rule = deepcopy(rules)
behavioral_rule.rules[1].callback = function() end
expect_error("behavioral FamilyRule", "FamilyRule must be data-only", function() family_registry.validate(behavioral_rule) end)

local base_pack = valid_pack("pack-a", "2.1", "test-mod", "= 1.0.0")
pack_schema.validate(base_pack)
local public_fixture_pack = deepcopy(base_pack)
public_fixture_pack.claim.public = true
expect_error("public fixture-only CompatibilityPack", "fixture-only packs cannot publish a claim", function() pack_schema.validate(public_fixture_pack) end)
local unsafe_override_pack = deepcopy(base_pack)
unsafe_override_pack.risk_overrides = {{risk = "recycling_loop", action = "allow-reviewed", evidence = {}}}
expect_error("unreviewed CompatibilityPack override", "allow-reviewed risk overrides require named evidence", function() pack_schema.validate(unsafe_override_pack) end)

local compiled = pack_registry.compile({
  ["pack-z"] = valid_pack("pack-z", "2.1", "test-mod", "1.0.0"),
  ["pack-a"] = base_pack,
  ["pack-old"] = valid_pack("pack-old", "2.0", "test-mod", "1.0.0"),
  ["pack-missing"] = valid_pack("pack-missing", "2.1", "absent-mod", "1.0.0")
}, {factorio_line = "2.1", active_mods = {['test-mod'] = "1.0.0"}})
if #compiled ~= 2 or compiled[1].id ~= "pack-a" or compiled[2].id ~= "pack-z" then
  fail("CompatibilityPack target/applicability filtering or stable sorting failed")
end
local ranged_pack = valid_pack("pack-range", "2.1", "test-mod", ">= 0.9.0, < 2.0.0")
ranged_pack.applicability.mods_all = {{id = "required-peer", version = ">= 2.0.0"}}
ranged_pack.applicability.mods_none = {{id = "blocked-peer"}}
local ranged = pack_registry.compile({[ranged_pack.id] = ranged_pack}, {
  factorio_line = "2.1",
  active_mods = {['test-mod'] = "1.0.0", ['required-peer'] = "2.1.0"}
})
if #ranged ~= 1 then fail("CompatibilityPack mods_all/mods_none or version-range applicability failed") end

local operational_pack = valid_pack("pack-operational", "2.1", "test-mod", "1.0.0")
operational_pack.exact.excludes = {{recipe = "blocked-recipe", reason = "reviewed-deny"}}
operational_pack.exact.includes = {{recipe = "included-recipe", family = "assembler", change = 0.03}}
operational_pack.aliases = {['aliased-item'] = {family = "assembler", change = 0.02}}
operational_pack.family_hints = {{recipe = "hinted-recipe", family = "assembler", change = 0.04}}
operational_pack.science_roles = {{stream = "research_auto_assembling_machine", pack = "automation-science-pack", role = "include"}}
operational_pack.risk_overrides = {{recipe = "reviewed-recipe", risk = "recycling_recipe", action = "allow-reviewed", evidence = {"compiler-contracts"}}}
local active_operational = {pack_schema.validate(operational_pack)}
local excluded = pack_registry.resolve_candidate({recipe = "blocked-recipe", item = "x", family = "assembler", stream = "s"}, active_operational)
if excluded.action ~= "diagnose" then fail("CompatibilityPack exact exclude did not affect candidate resolution") end
local included = pack_registry.resolve_candidate({recipe = "included-recipe", item = "x", family = "assembler", stream = "s"}, active_operational)
if included.action ~= "attach" or included.change ~= 0.03 then fail("CompatibilityPack exact include did not affect candidate resolution") end
local reviewed = pack_registry.resolve_candidate({recipe = "reviewed-recipe", item = "x", family = "assembler", stream = "s", blocker = "recycling_recipe"}, active_operational)
if reviewed.action ~= "attach" then fail("CompatibilityPack reviewed risk override did not affect candidate resolution") end
local roles = pack_registry.science_roles_for_stream("research_auto_assembling_machine", active_operational)
if #roles ~= 1 or roles[1].pack ~= "automation-science-pack" then fail("CompatibilityPack science role was not consumed") end
expect_error("CompatibilityPack transport identity", "transport key must match pack id", function()
  pack_registry.compile({wrong = base_pack}, {factorio_line = "2.1", active_mods = {['test-mod'] = "1.0.0"}})
end)

local target_winner = precedence.resolve({
  {kind = "generic-structural", id = "generic", action = "attach"},
  {kind = "target-exclusion", id = "target", action = "skip", reason = "unsupported-target"},
  {kind = "exact-reviewed", id = "reviewed", action = "attach"}
})
if target_winner.id ~= "target" then fail("target exclusion did not win precedence") end
local deny_winner = precedence.resolve({
  {kind = "exact-deny", id = "deny", action = "skip", reason = "loop-risk"},
  {kind = "compatibility-pack-hint", id = "hint", action = "attach"}
})
if deny_winner.id ~= "deny" then fail("exact deny did not win precedence") end
local reviewed_winner = precedence.resolve({
  {kind = "exact-deny", id = "deny", action = "skip", reason = "loop-risk"},
  {kind = "exact-reviewed", id = "reviewed", action = "attach", overrides_reason = "loop-risk"}
})
if reviewed_winner.id ~= "reviewed" then fail("named reviewed override did not supersede exact deny") end
expect_error("equal-precedence conflict", "Conflicting compatibility signals at equal precedence", function()
  precedence.resolve({
    {kind = "compatibility-pack-hint", id = "a", action = "attach"},
    {kind = "compatibility-pack-hint", id = "b", action = "skip"}
  })
end)

local plan_a = generation_plan.new({source_fingerprints = {rules = "r", facts = "f"}})
plan_a:add(skip_row("z-stream", "z-id"))
plan_a:add(skip_row("a-stream", "a-id"))
plan_a:finalize()
local plan_b = generation_plan.new({source_fingerprints = {facts = "f", rules = "r"}})
plan_b:add(skip_row("a-stream", "a-id"))
plan_b:add(skip_row("z-stream", "z-id"))
plan_b:finalize()
if plan_a.plan_fingerprint ~= plan_b.plan_fingerprint then fail("GenerationPlan fingerprint depends on insertion or map order") end
if plan_a:snapshot()[1].stream_key ~= "a-stream" then fail("GenerationPlan rows are not stably sorted") end
local duplicate_plan = generation_plan.new()
duplicate_plan:add(skip_row("same", "id-a"))
duplicate_plan:add(skip_row("same", "id-b"))
expect_error("duplicate GenerationPlan stream id", "duplicate stream key", function() duplicate_plan:finalize() end)

local function emitted_row(stream_key, technology_name)
  local row = skip_row(stream_key, stream_key)
  row.action = "emit"
  row.technology_name = technology_name
  row.fields = {
    effects = {{type = "change-recipe-productivity", recipe = "shared-recipe", change = 0.1}},
    ingredients = {{"automation-science-pack", 1}}, prerequisites = {},
    count_formula = "100", research_time = 30, max_level = "infinite"
  }
  for _, proof in pairs(row.gates) do proof.status = "passed" end
  return row
end
local duplicate_effect_plan = generation_plan.new()
duplicate_effect_plan:add(emitted_row("effect-a", "effect-tech-a"))
duplicate_effect_plan:add(emitted_row("effect-b", "effect-tech-b"))
expect_error("duplicate materialized effect", "duplicate materialized effect identity", function() duplicate_effect_plan:finalize() end)

if fingerprint.of({b = 2, a = 1}) ~= fingerprint.of({a = 1, b = 2}) then fail("map fingerprint is iteration-order dependent") end
local cyclic = {}; cyclic.self = cyclic
expect_error("cyclic fingerprint", "Cannot fingerprint cyclic table", function() fingerprint.of(cyclic) end)

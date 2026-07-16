local deepcopy = require("__more-infinite-research__.prototypes.mir.core.deepcopy")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local family_registry = require("__more-infinite-research__.prototypes.mir.families.registry")
local provider_registry = require("__more-infinite-research__.prototypes.mir.providers.registry")
local diagnostic_codes = require("__more-infinite-research__.prototypes.mir.domain.diagnostics.codes")
local pack_schema = require("__more-infinite-research__.prototypes.mir.compatibility.packs.schema")
local pack_registry = require("__more-infinite-research__.prototypes.mir.compatibility.packs.registry")
local precedence = require("__more-infinite-research__.prototypes.mir.compatibility.packs.precedence")
local generation_plan = require("__more-infinite-research__.prototypes.mir.planner.generation_plan")
local compilation_plan = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan")
local output_validator = require("__more-infinite-research__.prototypes.mir.planner.output_validator")
local effect_ownership = require("__more-infinite-research__.prototypes.mir.planner.effect_ownership")
local effect_safety = require("__more-infinite-research__.prototypes.mir.emit.effect_safety")
local automatic_compiler_contract = require("__more-infinite-research__.prototypes.mir.settings.automatic_compiler_contract")
local native_owner_cost_model = require("__more-infinite-research__.prototypes.mir.domain.native_owner.cost_model")

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
    family_authorizations = {},
    candidate_seeds = {},
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

local function expect_policy(label, values, expected)
  local actual = automatic_compiler_contract.resolve(values)
  for field, value in pairs(expected) do
    if actual[field] ~= value then
      fail(label .. " expected " .. field .. "=" .. tostring(value) .. " but received " .. tostring(actual[field]))
    end
  end
  return actual
end

expect_policy("default automatic controls", {}, {
  action = "apply", create_research = false, require_reviewed_data = true,
  apply_changes = true, preview = false, source = "controls-v2", preset = "safe"
})
expect_policy("disabled automatic controls", {action = "disabled"}, {
  action = "disabled", discover = false, apply_changes = false, source = "controls-v2"
})
expect_policy("preview automatic controls", {action = "preview"}, {
  action = "preview", discover = true, preview = true, apply_changes = false, source = "controls-v2"
})
expect_policy("new automatic controls override legacy", {
  action = "preview", create_research = true, require_reviewed_data = false, legacy_mode = "off"
}, {
  action = "preview", create_research = true, require_reviewed_data = false, source = "controls-v2"
})

local legacy_expectations = {
  off = {action = "disabled", create_research = false, require_reviewed_data = true},
  report = {action = "preview", create_research = false, require_reviewed_data = true},
  ["safe-attach"] = {action = "apply", create_research = false, require_reviewed_data = true},
  ["exact-pack"] = {action = "apply", create_research = true, require_reviewed_data = true},
  ["safe-generate"] = {action = "apply", create_research = true, require_reviewed_data = false}
}
for mode, expected in pairs(legacy_expectations) do
  local values = {legacy_mode = mode}
  if mode == "safe-attach" then values = {} end
  local policy = expect_policy("legacy automatic mode " .. mode, values, expected)
  if mode ~= "safe-attach" and policy.source ~= "legacy:" .. mode then
    fail("legacy automatic mode " .. mode .. " did not use the migration bridge")
  end
end

local denied, denied_reason = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true}), false)
if denied or denied_reason ~= "reviewed_compatibility_data_required" then
  fail("reviewed-data generation gate did not fail closed")
end
local experimental, experimental_reason, experimental_code = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true}), true, "experimental")
if experimental or experimental_reason ~= "automatic_family_not_reviewed"
  or experimental_code ~= diagnostic_codes.get("automatic_family_not_reviewed") then
  fail("experimental family was accepted by the reviewed-data creation lane")
end
expect_error("unknown automatic family creation maturity", "Unknown automatic family creation maturity", function()
  automatic_compiler_contract.generation_decision(
    automatic_compiler_contract.resolve({create_research = true, require_reviewed_data = false}), false, "unknown")
end)
local approved = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true}), true, "reviewed")
if not approved then fail("reviewed-data generation gate rejected named authorization") end
local generic = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true, require_reviewed_data = false}), false, "experimental")
if not generic then fail("registered family module generation was not independently configurable") end

for _, preset_name in ipairs(automatic_compiler_contract.preset_names) do
  local custom = preset_name == "custom" and {
    action = "disabled", create_research = true, require_reviewed_data = false
  } or nil
  local preset = automatic_compiler_contract.resolve_preset(preset_name, custom)
  if preset.preset ~= preset_name then fail("automatic preset did not expand deterministically: " .. preset_name) end
  if preset_name ~= "custom" and automatic_compiler_contract.classify_preset(preset) ~= preset_name then
    fail("automatic preset did not round-trip: " .. preset_name)
  end
end
expect_error("custom preset without explicit controls", "requires explicit control values", function()
  automatic_compiler_contract.resolve_preset("custom")
end)

local descriptors = automatic_compiler_contract.descriptors()
if #descriptors ~= 4 then fail("automatic setting descriptor count changed unexpectedly") end
for _, descriptor in ipairs(descriptors) do
  if descriptor.schema ~= 1 or descriptor.id ~= descriptor.prototype.name
    or not descriptor.consequence or not descriptor.compatibility_consequence
    or not descriptor.default_rationale
    or #(descriptor.tests or {}) == 0 or #(descriptor.documentation or {}) == 0
  then
    fail("automatic setting descriptor is incomplete: " .. tostring(descriptor.id))
  end
end
local specs = automatic_compiler_contract.setting_specs()
descriptors[1].prototype.default_value = "disabled"
if specs[1].default_value ~= "apply" then fail("automatic setting specs are not isolated from descriptor mutation") end

local _, _, denied_code = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true}), false)
if denied_code ~= diagnostic_codes.get("reviewed_compatibility_data_required") then
  fail("automatic generation decision omitted its stable diagnostic code")
end
if #diagnostic_codes.all() ~= 11 then fail("automatic/provider diagnostic registry is incomplete") end

local providers = provider_registry.snapshot()
if #providers.providers ~= 9 then fail("built-in CompilerProvider count changed unexpectedly") end
for index, provider in ipairs(providers.providers) do
  if index > 1 and providers.providers[index - 1].id >= provider.id then
    fail("CompilerProvider sorting is unstable")
  end
  if provider.family_rule.provider_id ~= provider.id
    or provider.emission_adapter.mutates_prototypes ~= false
    or provider.runtime_handler.required ~= false
  then
    fail("CompilerProvider contract metadata is incomplete: " .. provider.id)
  end
end
local reversed_providers = {schema = 1, providers = {}}
for index = #providers.providers, 1, -1 do table.insert(reversed_providers.providers, providers.providers[index]) end
local normalized_providers = provider_registry.validate(reversed_providers)
if fingerprint.of(normalized_providers) ~= fingerprint.of(providers) then
  fail("CompilerProvider normalization depends on registration order")
end
local duplicate_providers = deepcopy(providers)
table.insert(duplicate_providers.providers, deepcopy(duplicate_providers.providers[1]))
expect_error("duplicate CompilerProvider id", "Duplicate CompilerProvider id", function()
  provider_registry.validate(duplicate_providers)
end)
local behavioral_provider = deepcopy(providers)
behavioral_provider.providers[1].callback = function() end
expect_error("behavioral CompilerProvider", "CompilerProvider must be data-only", function()
  provider_registry.validate(behavioral_provider)
end)
local mutating_provider = deepcopy(providers)
mutating_provider.providers[1].emission_adapter.mutates_prototypes = true
expect_error("mutating CompilerProvider", "must be planning-only", function()
  provider_registry.validate(mutating_provider)
end)
local isolated_providers = provider_registry.snapshot()
isolated_providers.providers[1].family = "mutated"
if provider_registry.snapshot().providers[1].family == "mutated" then
  fail("CompilerProvider snapshots are not isolated")
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
unsafe_override_pack.risk_overrides = {{recipe = "recycle-x", risk = "recycling_recipe", action = "allow-reviewed", evidence = {"assert-compiler-contracts"}}}
expect_error("hard CompatibilityPack override", "allow-reviewed cannot override hard risk", function() pack_schema.validate(unsafe_override_pack) end)
local broad_override_pack = deepcopy(base_pack)
broad_override_pack.risk_overrides = {{risk = "hidden_recipe", action = "allow-reviewed", evidence = {"assert-compiler-contracts"}}}
expect_error("broad CompatibilityPack override", "require an exact recipe selector", function() pack_schema.validate(broad_override_pack) end)
local unknown_evidence_pack = deepcopy(base_pack)
unknown_evidence_pack.risk_overrides = {{recipe = "hidden-x", risk = "hidden_recipe", action = "allow-reviewed", evidence = {"missing-proof"}}}
expect_error("unknown CompatibilityPack evidence", "references unknown evidence", function() pack_schema.validate(unknown_evidence_pack) end)

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

local operational_pack = valid_pack("pack-operational", "2.1", "test-mod", "= 1.0.0")
operational_pack.exact.excludes = {{recipe = "blocked-recipe", reason = "reviewed-deny"}}
operational_pack.exact.includes = {{recipe = "included-recipe", family = "assembler", change = 0.03}}
operational_pack.aliases = {['aliased-item'] = {family = "assembler", change = 0.02}}
operational_pack.family_hints = {{recipe = "hinted-recipe", family = "assembler", change = 0.04}}
operational_pack.science_roles = {{stream = "research_auto_assembling_machine", pack = "automation-science-pack", role = "include"}}
operational_pack.risk_overrides = {{recipe = "reviewed-recipe", risk = "hidden_recipe", action = "allow-reviewed", evidence = {"assert-compiler-contracts"}}}
operational_pack.family_authorizations = {{family = "assembling-machine-manufacturing", stream = "research_auto_assembling_machine", action = "generate", evidence = {"assert-compiler-contracts"}, claim_boundary = "fixture-only"}}
operational_pack.candidate_seeds = {{recipe = "seeded-recipe", item = "seeded-item", family = "assembling-machine-manufacturing", stream = "research_auto_assembling_machine", change = 0.02, evidence = {"assert-compiler-contracts"}}}
local active_operational = {pack_schema.validate(operational_pack)}
local excluded = pack_registry.resolve_candidate({recipe = "blocked-recipe", item = "x", family = "assembler", stream = "s"}, active_operational)
if excluded.action ~= "diagnose" then fail("CompatibilityPack exact exclude did not affect candidate resolution") end
local included = pack_registry.resolve_candidate({recipe = "included-recipe", item = "x", family = "assembler", stream = "s"}, active_operational)
if included.action ~= "attach" or included.change ~= 0.03 then fail("CompatibilityPack exact include did not affect candidate resolution") end
local reviewed = pack_registry.resolve_candidate({recipe = "reviewed-recipe", item = "x", family = "assembler", stream = "s", blocker = "hidden_recipe"}, active_operational)
if reviewed.action ~= "attach" then fail("CompatibilityPack reviewed risk override did not affect candidate resolution") end
local hard_denied = pack_registry.resolve_candidate({recipe = "reviewed-recipe", item = "x", family = "assembler", stream = "s", blocker = "recycling_recipe"}, active_operational)
if hard_denied.action ~= "diagnose" then fail("CompatibilityPack bypassed a hard blocker") end
local malicious_pack = deepcopy(operational_pack)
malicious_pack.risk_overrides = {{recipe = "reviewed-recipe", risk = "recycling_recipe", action = "allow-reviewed", evidence = {"assert-compiler-contracts"}}}
local malicious_denied = pack_registry.resolve_candidate({recipe = "reviewed-recipe", item = "x", family = "assembler", stream = "s", blocker = "recycling_recipe"}, {malicious_pack})
if malicious_denied.action ~= "diagnose" then fail("registry hard-safety sentinel accepted unvalidated malicious pack data") end
local authorization = pack_registry.authorizes_family_stream("research_auto_assembling_machine", "assembling-machine-manufacturing", active_operational)
if not authorization or authorization.pack ~= "pack-operational" then fail("exact-pack family authorization was not resolved") end
local seeds = pack_registry.candidate_seeds(active_operational)
if #seeds ~= 1 or seeds[1].recipe ~= "seeded-recipe" then fail("CompatibilityPack candidate seed was not resolved") end
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
for seed = 1, 8 do
  local rows = {skip_row("property-a", "property-a"), skip_row("property-b", "property-b"), skip_row("property-c", "property-c")}
  for index = #rows, 2, -1 do
    local target = ((seed * 17 + index * 13) % index) + 1
    rows[index], rows[target] = rows[target], rows[index]
  end
  local property_plan = generation_plan.new({source_fingerprints = {facts = "f", rules = "r"}})
  for _, row in ipairs(rows) do property_plan:add(row) end
  property_plan:finalize()
  if seed == 1 then
    plan_a.property_fingerprint = property_plan.plan_fingerprint
  elseif plan_a.property_fingerprint ~= property_plan.plan_fingerprint then
    fail("property test found insertion-order-dependent plan fingerprint")
  end
end
if plan_a:snapshot()[1].stream_key ~= "a-stream" then fail("GenerationPlan rows are not stably sorted") end
local duplicate_plan = generation_plan.new()
duplicate_plan:add(skip_row("same", "id-a"))
duplicate_plan:add(skip_row("same", "id-b"))
expect_error("duplicate GenerationPlan stream id", "duplicate stream key", function() duplicate_plan:finalize() end)

local function emitted_row(stream_key, technology_name, recipe_name)
  local row = skip_row(stream_key, stream_key)
  row.action = "emit"
  row.technology_name = technology_name
  row.fields = {
    effects = {{
      type = "change-recipe-productivity",
      recipe = recipe_name or "iron-gear-wheel",
      change = 0.1
    }},
    ingredients = {{"automation-science-pack", 1}}, prerequisites = {},
    count_formula = "100", research_time = 30, max_level = "infinite"
  }
  for _, proof in pairs(row.gates) do proof.status = "passed" end
  return row
end

local function native_owner_row(stream_key, owner, recipe)
  local row = emitted_row(stream_key, "unused")
  local input = {
    name = owner,
    max_level = "infinite",
    prerequisites = {},
    unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1.5^L*1000", time = 60},
    effects = {}
  }
  local expected = deepcopy(input)
  local effect = {type = "change-recipe-productivity", recipe = recipe, change = 0.03}
  table.insert(expected.effects, deepcopy(effect))
  row.action = "adopt"
  row.technology_name = nil
  row.fields = nil
  row.adoption = {
    schema = 2,
    key = stream_key,
    owner = owner,
    operation = "adopt_native_owner_effects",
    configured_fields = {},
    effects = {effect},
    input_snapshot = input,
    expected_snapshot = expected,
    input_fingerprint = fingerprint.of(input),
    output_fingerprint = fingerprint.of(expected)
  }
  return row
end
local duplicate_effect_plan = generation_plan.new()
duplicate_effect_plan:add(emitted_row("effect-a", "effect-tech-a"))
duplicate_effect_plan:add(emitted_row("effect-b", "effect-tech-b"))
expect_error("duplicate materialized effect", "duplicate materialized effect identity", function() duplicate_effect_plan:finalize() end)

local overlap_b = emitted_row("research_sulfur", "effect-tech-sulfur")
overlap_b.fields.effects[1].change = 0.05
local resolved_overlap, overlap_summary = effect_ownership.resolve({overlap_b, emitted_row("research_carbon", "effect-tech-carbon")})
if overlap_summary.conflict_count ~= 1 then fail("effect ownership did not count the cross-stream collision") end
if resolved_overlap[1].stream_key ~= "research_carbon" or resolved_overlap[1].action ~= "emit" then
  fail("effect ownership did not select the stable lexical fixed-stream owner")
end
if resolved_overlap[2].stream_key ~= "research_sulfur" or resolved_overlap[2].action ~= "skip"
  or resolved_overlap[2].reason ~= "covered_by_planned_stream" then
  fail("effect ownership did not convert an empty losing stream into an auditable skip")
end
local resolved_plan = generation_plan.new()
for _, row in ipairs(resolved_overlap) do resolved_plan:add(row) end
resolved_plan:finalize()
if resolved_plan.validation_summary.effect_ownership_conflict_count ~= 1 then
  fail("GenerationPlan did not retain the resolved ownership conflict count")
end

local reversed_overlap = effect_ownership.resolve({emitted_row("research_carbon", "effect-tech-carbon"), overlap_b})
if fingerprint.of(resolved_overlap) ~= fingerprint.of(reversed_overlap) then
  fail("effect ownership depends on candidate insertion order")
end

local malformed_single_stream = emitted_row("malformed-single-stream", "malformed-single-stream-tech")
table.insert(malformed_single_stream.fields.effects, {
  type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.1
})
local malformed_rows = effect_ownership.resolve({malformed_single_stream})
local malformed_plan = generation_plan.new()
malformed_plan:add(malformed_rows[1])
expect_error("same-stream duplicate materialized effect", "duplicate materialized effect identity", function()
  malformed_plan:finalize()
end)

local partial = emitted_row("research_sulfur", "effect-tech-sulfur")
table.insert(partial.fields.effects, {type = "change-recipe-productivity", recipe = "sulfur-only-recipe", change = 0.1})
local partial_rows = effect_ownership.resolve({partial, emitted_row("research_carbon", "effect-tech-carbon")})
if partial_rows[2].action ~= "emit" or #partial_rows[2].fields.effects ~= 1
  or partial_rows[2].fields.effects[1].recipe ~= "sulfur-only-recipe" then
  fail("effect ownership removed a losing stream instead of retaining its unique effects")
end

local adoption = native_owner_row("research_adopted", "existing-productivity-owner", "iron-gear-wheel")
local adoption_rows = effect_ownership.resolve({emitted_row("research_emitted", "effect-tech-emitted"), adoption})
if adoption_rows[1].stream_key ~= "research_adopted" or adoption_rows[1].action ~= "adopt"
  or adoption_rows[2].action ~= "skip" then
  fail("existing adopted effect ownership did not win over generated ownership")
end


local duplicate_owner_plan = generation_plan.new()
duplicate_owner_plan:add(native_owner_row("native-owner-a", "shared-native-owner", "native-owner-recipe-a"))
duplicate_owner_plan:add(native_owner_row("native-owner-b", "shared-native-owner", "native-owner-recipe-b"))
expect_error("duplicate native-owner binding", "duplicate native-owner binding", function()
  duplicate_owner_plan:finalize()
end)

local native_model = native_owner_cost_model.classify(
  {count_formula = "1.5^L*1000"},
  {target_native_formulas = {"1.5^L*1000"}}
)
if native_model.kind ~= "target-native-exponential" or native_model.base ~= 1000 or native_model.growth ~= 1.5 then
  fail("target native cost formula was not classified")
end
local configured_native = native_owner_cost_model.configure(native_model, {base = 2000, growth = 1.25})
if not configured_native or configured_native.count_formula ~= "1.25^L*2000" then
  fail("target native cost formula was not configured deterministically")
end
local mir_model = native_owner_cost_model.classify({count_formula = "8000 * 2^(L-1)"}, {})
local configured_mir = native_owner_cost_model.configure(mir_model, {growth = 1.1})
if not configured_mir or configured_mir.count_formula ~= "8000*1.1^(L-1)" then
  fail("MIR exponential cost formula was not configured deterministically")
end
local unrecognized_model = native_owner_cost_model.classify({count_formula = "1000 + 100 * L"}, {})
local preserved_unrecognized = native_owner_cost_model.configure(unrecognized_model, {})
if not preserved_unrecognized or preserved_unrecognized.changed then
  fail("unrecognized cost formula was not preserved by default")
end
local rejected_unrecognized, rejected_reason = native_owner_cost_model.configure(unrecognized_model, {base = 2000})
if rejected_unrecognized or rejected_reason ~= "unrecognized_cost_formula" then
  fail("unsafe unrecognized cost formula override did not fail closed")
end

local collision_plan = generation_plan.new()
collision_plan:add(emitted_row("collision-stream", "collision-tech"))
collision_plan:finalize()
expect_error("CompilationPlan cross collision", "technology-name collision", function()
  compilation_plan.finalize(collision_plan, {{
    operation = "emit_base_extension",
    key = "collision-base",
    technology_name = "collision-tech",
    technology = {name = "collision-tech", effects = {}, prerequisites = {}, unit = {ingredients = {}, count_formula = "1", time = 1}, max_level = "infinite"}
  }})
end)
local missing_prerequisite_plan = compilation_plan.finalize(generation_plan.new():finalize(), {{
    operation = "emit_base_extension",
    key = "missing-prerequisite",
    technology_name = "missing-prerequisite-tech",
    technology = {name = "missing-prerequisite-tech", effects = {}, prerequisites = {"definitely-missing-technology"}, unit = {ingredients = {}, count_formula = "1", time = 1}, max_level = "infinite"}
  }})
if #missing_prerequisite_plan.operations ~= 0
  or missing_prerequisite_plan.validation_summary.technology_graph.rejected["missing-prerequisite-tech"].code
    ~= "prerequisite_missing" then
  fail("CompilationPlan did not withhold and classify a missing-prerequisite operation")
end

expect_error("output effect numeric parity", "numeric effect value differs", function()
  output_validator.assert_effects(
    {{type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.02}},
    {{type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.01}},
    "numeric-parity-test",
    true
  )
end)

expect_error("base extension output parity", "prerequisites differs", function()
  output_validator.assert_technology_shape(
    {effects = {}, prerequisites = {"automation"}, unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "100", time = 30}, max_level = "infinite", upgrade = true},
    {effects = {}, prerequisites = {}, unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "100", time = 30}, max_level = "infinite", upgrade = true},
    "base-parity-test"
  )
end)
local cyclic_plan = compilation_plan.finalize(generation_plan.new():finalize(), {
    {
      operation = "emit_base_extension",
      key = "cycle-a",
      technology_name = "mir-planned-cycle-a",
      technology = {
        name = "mir-planned-cycle-a",
        effects = {{type = "nothing"}},
        prerequisites = {"mir-planned-cycle-b"},
        unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1", time = 1},
        max_level = "infinite"
      }
    },
    {
      operation = "emit_base_extension",
      key = "cycle-b",
      technology_name = "mir-planned-cycle-b",
      technology = {
        name = "mir-planned-cycle-b",
        effects = {{type = "nothing"}},
        prerequisites = {"mir-planned-cycle-a"},
        unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1", time = 1},
        max_level = "infinite"
      }
    }
  })
if #cyclic_plan.operations ~= 0
  or cyclic_plan.validation_summary.technology_graph.rejected_planned_technology_count ~= 2
  or cyclic_plan.validation_summary.technology_graph.rejected["mir-planned-cycle-a"].code
    ~= "prerequisite_mir_cycle"
  or cyclic_plan.validation_summary.technology_graph.rejected["mir-planned-cycle-b"].code
    ~= "prerequisite_mir_cycle" then
  fail("CompilationPlan did not withhold and classify the planned prerequisite SCC")
end

local dangling_effect_candidate = {
  effects = {
    {type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.01},
    {type = "change-recipe-productivity", recipe = "mir-fixture-definitely-missing-recipe", change = 0.01}
  }
}
local dangling_effect_result = effect_safety.prune_missing_recipe_effects(
  dangling_effect_candidate,
  "compiler-contract-dangling-effect")
if dangling_effect_result.pruned_effect_count ~= 1
  or dangling_effect_result.remaining_effect_count ~= 1
  or dangling_effect_candidate.effects[1].recipe ~= "iron-gear-wheel"
then
  fail("final effect safety did not prune only the missing recipe-productivity target")
end
effect_safety.assert_effects_allowed(dangling_effect_candidate.effects, "compiler-contract-dangling-effect")

local generic_effect_candidate = {
  effects = {
    {type = "unlock-recipe", recipe = "iron-gear-wheel"},
    {type = "unlock-recipe", recipe = "mir-fixture-definitely-missing-recipe"},
    {type = "gun-speed", ammo_category = "bullet", modifier = 0.1},
    {type = "gun-speed", ammo_category = "mir-fixture-definitely-missing-ammo-category", modifier = 0.1}
  }
}
local kept_generic, removed_generic = effect_safety.sanitize_effects(
  generic_effect_candidate.effects,
  "compiler-contract-generic-effects",
  "external")
if #kept_generic ~= 2 or #removed_generic ~= 2 then
  fail("generic effect contracts did not retain valid targets and prune missing targets")
end

if fingerprint.of({b = 2, a = 1}) ~= fingerprint.of({a = 1, b = 2}) then fail("map fingerprint is iteration-order dependent") end
local cyclic = {}; cyclic.self = cyclic
expect_error("cyclic fingerprint", "Cannot fingerprint cyclic table", function() fingerprint.of(cyclic) end)

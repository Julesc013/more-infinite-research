local deepcopy = require("__more-infinite-research__.prototypes.mir.core.deepcopy")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local family_registry = require("__more-infinite-research__.prototypes.mir.families.registry")
local family_operator_dsl = require("__more-infinite-research__.prototypes.mir.families.operator_dsl")
local provider_registry = require("__more-infinite-research__.prototypes.mir.providers.registry")
local diagnostic_codes = require("__more-infinite-research__.prototypes.mir.domain.diagnostics.codes")
local pack_schema = require("__more-infinite-research__.prototypes.mir.compatibility.packs.schema")
local pack_registry = require("__more-infinite-research__.prototypes.mir.compatibility.packs.registry")
local compatibility_policy = require("__more-infinite-research__.prototypes.mir.compatibility.policy_authority")
local precedence = require("__more-infinite-research__.prototypes.mir.compatibility.packs.precedence")
local generation_plan = require("__more-infinite-research__.prototypes.mir.planner.generation_plan")
local compilation_plan = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan")
local output_validator = require("__more-infinite-research__.prototypes.mir.planner.output_validator")
local effect_ownership = require("__more-infinite-research__.prototypes.mir.planner.effect_ownership")
local effect_safety = require("__more-infinite-research__.prototypes.mir.emit.effect_safety")
local effect_contracts = require("__more-infinite-research__.prototypes.mir.integrity.effect_contracts")
local automatic_compiler_contract = require("__more-infinite-research__.prototypes.mir.settings.automatic_compiler_contract")
local native_owner_cost_model = require("__more-infinite-research__.prototypes.mir.domain.native_owner.cost_model")
local technology_design = require("__more-infinite-research__.prototypes.mir.domain.technology.technology_design")
local technology_candidate = require("__more-infinite-research__.prototypes.mir.domain.technology.technology_candidate")
local technology_qualification = require("__more-infinite-research__.prototypes.mir.domain.technology.technology_qualification")
local c7_contracts = {
  gate = require("__more-infinite-research__.prototypes.mir.domain.technology.gate"),
  safety = require("__more-infinite-research__.prototypes.mir.domain.technology.safety_qualification"),
  assessment = require("__more-infinite-research__.prototypes.mir.domain.technology.design_assessment"),
  promotion = require("__more-infinite-research__.prototypes.mir.domain.technology.promotion_authorization"),
  registry = require("__more-infinite-research__.prototypes.mir.domain.technology.promotion_registry")
}
local technology_approval = require("__more-infinite-research__.prototypes.mir.domain.technology.technology_approval")
local applicability_envelope = require("__more-infinite-research__.prototypes.mir.domain.technology.applicability_envelope")
local technology_promotion = require("__more-infinite-research__.prototypes.mir.domain.technology.technology_promotion")
local technology_migration = require("__more-infinite-research__.prototypes.mir.domain.technology.technology_migration")
local technology_catalog = require("__more-infinite-research__.prototypes.mir.planner.technology_catalog")
local pipeline_commands = require("__more-infinite-research__.prototypes.mir.pipeline.commands")
local compiler_context = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local recipe_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_facts")
local relationships = require("__more-infinite-research__.prototypes.mir.index.relationships")
local recipe_risk_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_risk_facts")
local family_resolver = require("__more-infinite-research__.prototypes.mir.families.resolver")
local science_packs = require("__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")

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
    return c7_contracts.gate.not_applicable("compiler-contract-fixture", {evidence})
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
  automatic_compiler_contract.resolve({create_research = true}), {
    promotion_verified = true, trust_class = "mir-reviewed"
  }, "experimental")
if experimental or experimental_reason ~= "automatic_family_not_reviewed"
  or experimental_code ~= diagnostic_codes.get("automatic_family_not_reviewed") then
  fail("experimental family was accepted by the reviewed-data creation lane")
end
expect_error("unknown automatic family creation maturity", "Unknown automatic family creation maturity", function()
  automatic_compiler_contract.generation_decision(
    automatic_compiler_contract.resolve({create_research = true, require_reviewed_data = false}), false, "unknown")
end)
local approved = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true}), {
    promotion_verified = true, trust_class = "mir-reviewed"
  }, "reviewed")
if not approved then fail("reviewed-data generation gate rejected named authorization") end
local untrusted = automatic_compiler_contract.generation_decision(
  automatic_compiler_contract.resolve({create_research = true}), {
    promotion_verified = false, trust_class = "external-mod-author"
  }, "reviewed")
if untrusted then fail("reviewed-data generation accepted an externally self-asserted trust class") end
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
    or type(provider.default_policy.cardinality) ~= "table"
  then
    fail("CompilerProvider contract metadata is incomplete: " .. provider.id)
  end
end

local cardinality_rows, cardinality = family_resolver.apply_cardinality_guard({
  {final_state = "attach", decision = "attach", blocker = nil, promotion_class = "new-unreviewed"},
  {final_state = "attach", decision = "attach", blocker = nil, promotion_class = "new-unreviewed"},
  {final_state = "diagnose", decision = "diagnose", blocker = "recycling_loop", promotion_class = "new-unreviewed"},
  {final_state = "attach", decision = "attach", blocker = nil, promotion_class = "exact-reviewed"}
}, {maximum_candidates = 2, maximum_attachments = 2, maximum_review_required = 2}, 3)
if cardinality.status ~= "REVIEW_REQUIRED"
  or cardinality_rows[1].decision ~= "review-required"
  or cardinality_rows[2].decision ~= "review-required"
  or cardinality_rows[3].decision ~= "diagnose"
  or cardinality_rows[4].decision ~= "attach"
  or cardinality.retained_reviewed_or_promoted_count ~= 1
  or type(cardinality_rows[1].decision_fingerprint) ~= "string" then
  fail("provider cardinality overflow did not stop expansion before emission while preserving hard rejection")
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
local operator_schema = family_operator_dsl.schema_authority()
if operator_schema.schema ~= 1
  or #operator_schema.operators.selectors < 6
  or rules.rules[1].operators.effect_model.operator == nil then
  fail("family operator DSL authority or provider composition is incomplete")
end
local unknown_operator_rule = deepcopy(rules)
unknown_operator_rule.rules[1].operators.selectors[1].operator = "recipe.opaque-machine-learning"
expect_error("unknown family operator", "unsupported selectors operator", function()
  family_registry.validate(unknown_operator_rule)
end)

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
operational_pack.family_authorizations = {{
  family = "assembling-machine-manufacturing",
  stream = "research_auto_assembling_machine",
  action = "generate",
  evidence = {"assert-compiler-contracts"},
  claim_boundary = "fixture-only",
  promotion_authorization_id = "mir.reviewed.compiler-contract-fixture-v1",
  trust_class = "mir-reviewed",
  provider_version = "family-rule-v3"
}}
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
  row.source = "fixed-stream"
  row.spec = {manifest_id = stream_key, migration_policy = "stable"}
  for gate_name in pairs(row.gates) do
    row.gates[gate_name] = c7_contracts.gate.passed("compiler-contract:" .. gate_name, {"fixture:" .. gate_name})
  end
  row.technology_design = technology_design.from_generation_row(row)
  return row
end

local design_row = emitted_row("technology-design-contract", "technology-design-contract-tech")
design_row.source = "fixed-stream"
design_row.spec = {manifest_id = "technology-design-contract", migration_policy = "stable"}
local normalized_design = technology_design.from_generation_row(design_row)
local normalized_shape = technology_design.prototype_shape(normalized_design)
if normalized_design.schema ~= 2
  or normalized_design.candidate_id ~= "mir-candidate/recipe-productivity/technology-design-contract"
  or normalized_design.technology_id ~= "technology-design-contract-tech"
  or normalized_design.design.identity.lock_state ~= "partial"
  or normalized_design.design.progression.locked ~= false
  or normalized_design.provenance.fields["identity.technology_id"].locked ~= true
  or normalized_design.provenance.fields["presentation.icons"].locked ~= false
  or normalized_shape.effects[1].recipe ~= "iron-gear-wheel"
  or normalized_shape.unit.count_formula ~= "100"
  or normalized_design.maturity.identity_stability ~= "released"
  or type(normalized_design.subject_fingerprint) ~= "string"
  or type(normalized_design.design_fingerprint) ~= "string"
  or type(normalized_design.prototype_fingerprint) ~= "string"
  or type(normalized_design.qualification_fingerprint) ~= "string"
then
  fail("TechnologyDesign did not preserve normalized fixed-stream semantics and independent field locks")
end
local stale_design_row = emitted_row("stale-design-contract", "stale-design-contract-tech", "iron-gear-wheel")
stale_design_row.fields.effects[1].change = 0.2
expect_error("emitted row TechnologyDesign authority", "legacy projection differs", function()
  generation_plan.new():add(stale_design_row)
end)
local unlocked_overlay = deepcopy(normalized_design)
unlocked_overlay.design.progression.value.prerequisites = {"automation"}
unlocked_overlay.provenance.fields["progression.prerequisites"].value = {"automation"}
technology_design.refresh_fingerprints(unlocked_overlay)
technology_design.merge(normalized_design, unlocked_overlay, {})
local locked_overlay = deepcopy(normalized_design)
locked_overlay.design.presentation.value.localised_name = {"", "Unauthorized rename"}
locked_overlay.provenance.fields["presentation.localised_name"].value = {"", "Unauthorized rename"}
locked_overlay.provenance.fields["presentation.localised_name"].present = true
technology_design.refresh_fingerprints(locked_overlay)
expect_error("TechnologyDesign locked field mutation", "locked field changed without authorization", function()
  technology_design.merge(normalized_design, locked_overlay, {})
end)
local malformed_design = deepcopy(normalized_design)
malformed_design.provenance.fields["identity.candidate_id"].value = "contradictory-candidate"
technology_design.refresh_fingerprints(malformed_design)
expect_error("TechnologyDesign cross-field invariant", "dimension differs from leaf provenance", function()
  technology_design.validate(malformed_design)
end)
if normalized_design.semantic_fingerprint
  ~= technology_design.from_generation_row(design_row).semantic_fingerprint then
  fail("TechnologyDesign semantic fingerprint is not deterministic")
end
local qualification_row = deepcopy(design_row)
qualification_row.gates.effect_valid = c7_contracts.gate.passed(
  "compiler-contract:effect-valid", {"fixture:qualification-refresh"})
local refreshed_qualification_design = technology_design.with_qualification(
  normalized_design,
  qualification_row,
  {validated = true, share_immutable = true}
)
local rebuilt_qualification_design = technology_design.from_generation_row(qualification_row)
if fingerprint.of(refreshed_qualification_design) ~= fingerprint.of(rebuilt_qualification_design) then
  fail("TechnologyDesign qualification-only refresh differs from a complete rebuild")
end
if normalized_design.gates.effect_valid.evidence[1] == "fixture:qualification-refresh" then
  fail("TechnologyDesign qualification-only refresh mutated its source design")
end
local mismatched_qualification_row = deepcopy(qualification_row)
mismatched_qualification_row.technology_name = "mismatched-technology-design"
expect_error("TechnologyDesign qualification identity", "changed design identity", function()
  technology_design.with_qualification(normalized_design, mismatched_qualification_row)
end)
local candidate = technology_candidate.from_design(normalized_design, design_row)
local qualification = technology_qualification.from_design(normalized_design, design_row)
do
  local pending_row = deepcopy(design_row)
  pending_row.gates.progression_safe = c7_contracts.gate.pending("compiler-contract:pending-progression")
  pending_row.technology_design = technology_design.from_generation_row(pending_row)
  local pending_qualification = c7_contracts.safety.from_design(
    pending_row.technology_design, pending_row, nil, {validated = true})
  if pending_qualification.decision ~= "proposal"
    or #pending_qualification.unresolved_gates ~= 1
    or pending_qualification.unresolved_gates[1] ~= "progression_safe" then
    fail("pending hard gate was represented as a false pass or terminal rejection")
  end
  local failed_gate = c7_contracts.gate.failed("compiler-contract:graph", "fixture-cycle", {"cycle:a-b"})
  local superseded_gate = c7_contracts.gate.supersede(
    c7_contracts.gate.pending("compiler-contract:provisional"), "compiler-contract:graph", failed_gate)
  c7_contracts.gate.validate(superseded_gate)
  expect_error("tampered gate evidence", "evidence fingerprint is invalid", function()
    local tampered = deepcopy(failed_gate)
    tampered.evidence = {"cycle:tampered"}
    c7_contracts.gate.validate(tampered)
  end)
  local diagnostic_design = technology_design.as_diagnostic_alternative(normalized_design, "fixture-diagnostic")
  if diagnostic_design.materialization.kind ~= "diagnose"
    or diagnostic_design.design.ownership.value.action ~= "diagnose"
    or diagnostic_design.maturity.runtime_action ~= "diagnose"
    or diagnostic_design.context.runtime_action ~= nil then
    fail("TechnologyDesign diagnostic conversion wrote runtime action to the wrong object or violated invariants")
  end
end
local lifecycle_catalog = technology_catalog.from_generation_rows({design_row}, {fixture = "lifecycle"})
technology_catalog.validate(lifecycle_catalog)
local trusted_lifecycle_catalog = technology_catalog.from_generation_rows(
  {design_row},
  {fixture = "lifecycle"},
  {trusted_designs = true}
)
technology_catalog.validate(trusted_lifecycle_catalog)
if fingerprint.of(lifecycle_catalog) ~= fingerprint.of(trusted_lifecycle_catalog) then
  fail("trusted technology catalog construction differs from the defensive path")
end
if candidate.candidate_id ~= normalized_design.candidate_id
  or candidate.semantic_identity.capability ~= "recipe-productivity"
  or qualification.decision ~= "qualified"
  or qualification.design_fingerprint ~= normalized_design.design_fingerprint
  or lifecycle_catalog.schema ~= 2
  or lifecycle_catalog.mutation_authority ~= false
  or #lifecycle_catalog.candidates ~= 1
  or #lifecycle_catalog.candidates[1].alternatives ~= 2
  or #lifecycle_catalog.qualifications ~= 2
  or #lifecycle_catalog.alternative_qualifications ~= 2
  or #lifecycle_catalog.current_selections ~= 1 then
  fail("technology candidate catalog and qualification records are inconsistent")
end
do
  local second_design_row = emitted_row("technology-design-contract-b", "technology-design-contract-tech-b")
  local ordered_catalog = technology_catalog.from_generation_rows(
    {design_row, second_design_row}, {fixture = "catalog-order"})
  local reversed_catalog = technology_catalog.from_generation_rows(
    {second_design_row, design_row}, {fixture = "catalog-order"})
  if ordered_catalog.catalog_fingerprint ~= reversed_catalog.catalog_fingerprint
    or ordered_catalog.selection_fingerprint ~= reversed_catalog.selection_fingerprint then
    fail("TechnologyCatalog selection depends on candidate discovery order")
  end
  local assessment = c7_contracts.assessment.new({
    candidate_id = candidate.candidate_id,
    design_fingerprint = normalized_design.design_fingerprint,
    qualification_fingerprint = qualification.qualification_fingerprint,
    profile_id = "compiler-contract-profile",
    status = "PASS",
    evidence_sha256 = {"ASSESSMENT-EVIDENCE"}
  })
  local promotion_record = c7_contracts.promotion.new({
    authorization_id = "promotion-authorization/compiler-contract/1",
    candidate_id = candidate.candidate_id,
    design_fingerprint = normalized_design.design_fingerprint,
    safety_qualification_fingerprint = qualification.qualification_fingerprint,
    provider_id = "mir.fixture-provider",
    provider_version = "1",
    quality_policy_version = "1",
    trust_class = "mir-reviewed",
    applicability_envelope = {factorio_line = "2.1", fixture = "compiler-contracts"},
    profile_fingerprints = {"PROFILE"},
    quality_assessment_fingerprints = {assessment.assessment_fingerprint},
    upgrade_evidence_sha256 = {"UPGRADE"},
    performance_evidence_sha256 = {"PERFORMANCE"},
    human_review = {decision = "approved", reviewer = "fixture-reviewer"}
  })
  if not c7_contracts.promotion.is_reviewed_trust(promotion_record)
    or c7_contracts.registry.snapshot().trust_authority ~= "mir-owned-source" then
    fail("promotion authorization did not keep design quality and trust as explicit independent contracts")
  end
end
local approval_envelope = applicability_envelope.new({
  envelope_id = "compiler-contract-fixture-v1",
  factorio_lines = {"2.1"},
  required_features = {"recipe-productivity"},
  required_mods = {{id = "base"}},
  structural_predicates = {
    {predicate = "recipe.visible"},
    {predicate = "recipe.productivity-eligible"}
  },
  positive_examples = {"compiler-contract-positive"},
  negative_examples = {"compiler-contract-negative"},
  maximum_new_matches = 0
})
local envelope_matches = applicability_envelope.matches(approval_envelope, {
  factorio_line = "2.1",
  features = {["recipe-productivity"] = true},
  active_mods = {base = true},
  predicates = {["recipe.visible"] = true, ["recipe.productivity-eligible"] = true},
  new_matches = 0
})
if not envelope_matches then fail("technology applicability envelope rejected its reviewed context") end
local expansion_matches, expansion_reason = applicability_envelope.matches(approval_envelope, {
  factorio_line = "2.1",
  features = {["recipe-productivity"] = true},
  active_mods = {base = true},
  predicates = {["recipe.visible"] = true, ["recipe.productivity-eligible"] = true},
  new_matches = 1
})
if expansion_matches or expansion_reason ~= "new-matches" then
  fail("technology applicability envelope did not fail closed on an unreviewed match")
end
local policy_snapshot = compatibility_policy.snapshot()
if policy_snapshot.schema ~= 1 or type(policy_snapshot.policy_fingerprint) ~= "string"
  or type(policy_snapshot.active_packs) ~= "table" or type(policy_snapshot.claims) ~= "table" then
  fail("context-owned compatibility policy authority is incomplete")
end
local approval = technology_approval.new({
  approval_id = "approval/compiler-contract/1",
  decision = "approved",
  candidate_selector = {candidate_id = candidate.candidate_id},
  applicability = {exact_mods = {"base"}, structural_envelope = approval_envelope},
  selected_alternative = lifecycle_catalog.candidates[1].alternatives[1].alternative_id,
  approved_design_fingerprint = normalized_design.design_fingerprint,
  qualification_fingerprint = qualification.qualification_fingerprint,
  locked_fields = {"identity.technology_id", "presentation.localised_name"},
  adaptive_envelopes = {},
  required_evidence = {"positive-fixture", "negative-fixture"},
  reviewer = "fixture-reviewer",
  decided_at = "2026-07-18T00:00:00Z"
})
local promotion = technology_promotion.new({
  promotion_id = "promotion/compiler-contract/1",
  technology_id = normalized_design.technology_id,
  candidate_id = candidate.candidate_id,
  approval_id = approval.approval_id,
  approved_design_fingerprint = normalized_design.design_fingerprint,
  prior_identity_state = "reserved",
  identity_state = "stable-unreleased",
  migration_policy = "stable",
  introduced_in = "3.2.0",
  evidence = {qualification.qualification_fingerprint}
})
local migration = technology_migration.new({
  migration_id = "migration/compiler-contract/1",
  from_technology_id = "old-fixture-technology",
  to_technology_id = normalized_design.technology_id,
  strategy = "retain-hidden-alias",
  save_behavior = "preserve researched state through an alias migration",
  approval_id = approval.approval_id,
  evidence = {promotion.promotion_fingerprint}
})
if type(approval.approval_fingerprint) ~= "string"
  or type(promotion.promotion_fingerprint) ~= "string"
  or type(migration.migration_fingerprint) ~= "string" then
  fail("technology lifecycle records are not independently fingerprinted")
end
expect_error("TechnologyPromotion state regression", "transition is not permitted", function()
  technology_promotion.assert_transition("released", "reserved")
end)

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
  row.technology_design = technology_design.from_generation_row(row)
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
if adoption.technology_design.materialization.kind ~= "patch-existing"
  or adoption.technology_design.materialization.target ~= adoption.adoption.owner
  or adoption.technology_design.prototype_fingerprint ~= adoption.adoption.output_fingerprint
  or adoption.technology_design.context.patch_input_fingerprint ~= adoption.adoption.input_fingerprint then
  fail("native-owner adoption did not bind a patch-existing TechnologyDesign")
end
local mismatched_patch_design = deepcopy(adoption)
mismatched_patch_design.technology_design.materialization.target = "wrong-owner"
technology_design.refresh_fingerprints(mismatched_patch_design.technology_design)
expect_error("native-owner patch design parity", "projection differs from TechnologyDesign", function()
  technology_design.assert_generation_row(mismatched_patch_design)
end)
local mismatched_patch_input = deepcopy(adoption)
mismatched_patch_input.technology_design.context.patch_input_fingerprint = "tampered-input"
technology_design.refresh_fingerprints(mismatched_patch_input.technology_design)
expect_error("native-owner patch input authority", "projection differs from TechnologyDesign", function()
  technology_design.assert_generation_row(mismatched_patch_input)
end)
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

local partial_sanitation_row = emitted_row(
  "partial-effect-sanitation-stream",
  "partial-effect-sanitation-tech",
  "iron-gear-wheel"
)
table.insert(partial_sanitation_row.fields.effects, {
  type = "change-recipe-productivity",
  recipe = "definitely-missing-partial-sanitation-recipe",
  change = 0.1
})
partial_sanitation_row.technology_design = technology_design.from_generation_row(partial_sanitation_row)
local partial_sanitation_source = generation_plan.new()
partial_sanitation_source:add(partial_sanitation_row)
partial_sanitation_source:finalize()
local partial_sanitation_plan = compilation_plan.finalize(partial_sanitation_source, {})
local partial_sanitation_operation = partial_sanitation_plan.operations[1]
local partial_sanitation_design = partial_sanitation_operation
  and partial_sanitation_operation.technology_design
if not partial_sanitation_operation
  or #partial_sanitation_operation.technology.effects ~= 1
  or partial_sanitation_operation.technology.effects[1].recipe ~= "iron-gear-wheel"
  or not partial_sanitation_design
  or #partial_sanitation_design.design.effects.value ~= 1
  or partial_sanitation_design.design.effects.value[1].recipe ~= "iron-gear-wheel"
  or partial_sanitation_plan.validation_summary.effect_integrity.streams.removed_effect_count ~= 1 then
  fail("CompilationPlan partial effect sanitation did not rebuild TechnologyDesign from retained effects")
end

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
local missing_rejection = missing_prerequisite_plan.validation_summary.technology_graph
  .rejected["missing-prerequisite-tech"]
local saw_research_mechanism = false
for _, reason in ipairs(missing_rejection.contributing or {}) do
  if reason.code == "research_mechanism_missing" then saw_research_mechanism = true end
end
if missing_rejection.primary.code ~= "prerequisite_missing" or not saw_research_mechanism then
  fail("semantic rejection priority did not preserve the subordinate research mechanism reason")
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
local continuation_design_plan = compilation_plan.finalize(generation_plan.new():finalize(), {{
  operation = "emit_base_extension",
  key = "compiler-contract-continuation",
  manifest_id = "base-continuation/compiler-contract-continuation",
  base_technology_name = "automation",
  technology_name = "mir-compiler-contract-continuation",
  technology = {
    type = "technology",
    name = "mir-compiler-contract-continuation",
    localised_name = {"", "Compiler contract continuation"},
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    effects = {{type = "nothing"}},
    prerequisites = {"automation"},
    unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1", time = 1},
    max_level = "infinite",
    upgrade = true
  }
}})
local continuation_operation = continuation_design_plan.operations[1]
if not continuation_operation or not continuation_operation.technology_design
  or continuation_operation.technology_design.materialization.kind ~= "continuation"
  or continuation_operation.technology_design.design.presentation.value.icon
    ~= "__base__/graphics/technology/automation.png"
  or continuation_operation.technology_design.identity_authority.source ~= "base-continuation-manifest" then
  fail("base continuation did not use TechnologyDesign and continuation manifest authority")
end
expect_error("presentation output parity", "localized name differs", function()
  output_validator.assert_technology_shape(
    {effects = {}, prerequisites = {}, unit = {}, localised_name = {"", "Expected"}},
    {effects = {}, prerequisites = {}, unit = {}, localised_name = {"", "Actual"}},
    "presentation-parity-test"
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
        prerequisites = {"mir-planned-cycle-c"},
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
    },
    {
      operation = "emit_base_extension",
      key = "cycle-c",
      technology_name = "mir-planned-cycle-c",
      technology = {
        name = "mir-planned-cycle-c",
        effects = {{type = "nothing"}},
        prerequisites = {"mir-planned-cycle-b"},
        unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1", time = 1},
        max_level = "infinite"
      }
    }
  })
if #cyclic_plan.operations ~= 0
  or cyclic_plan.validation_summary.technology_graph.rejected_planned_technology_count ~= 3
  or cyclic_plan.validation_summary.technology_graph.rejected["mir-planned-cycle-a"].code
    ~= "prerequisite_mir_cycle"
  or cyclic_plan.validation_summary.technology_graph.rejected["mir-planned-cycle-b"].code
    ~= "prerequisite_mir_cycle"
  or cyclic_plan.validation_summary.technology_graph.rejected["mir-planned-cycle-c"].code
    ~= "prerequisite_mir_cycle" then
  fail("CompilationPlan did not withhold and classify the planned prerequisite SCC")
end
local component = cyclic_plan.validation_summary.technology_graph.cyclic_components[1]
local witness = component and component.actual_cycle_witness or {}
local actual_edges = {
  ["mir-planned-cycle-a\0mir-planned-cycle-c"] = true,
  ["mir-planned-cycle-c\0mir-planned-cycle-b"] = true,
  ["mir-planned-cycle-b\0mir-planned-cycle-a"] = true
}
if not component or type(component.component_member_id) ~= "string"
  or type(component.component_topology_fingerprint) ~= "string" or component.internal_edge_count ~= 3
  or #component.member_sample ~= 3
  or #witness ~= 4 then
  fail("technology SCC did not publish bounded component identity and actual cycle evidence")
end
for index = 1, #witness - 1 do
  if not actual_edges[witness[index] .. "\0" .. witness[index + 1]] then
    fail("technology SCC witness contains a nonexistent prerequisite edge")
  end
end

local semantic_plan_a = compilation_plan.finalize(generation_plan.new():finalize(), {})
local semantic_plan_b = compilation_plan.finalize(generation_plan.new():finalize(), {})
if semantic_plan_a.semantic_fingerprint ~= semantic_plan_b.semantic_fingerprint
  or semantic_plan_a.fingerprint ~= semantic_plan_a.compilation_fingerprint
  or semantic_plan_a.semantic_fingerprint ~= semantic_plan_a.qualification_fingerprint then
  fail("CompilationPlan semantic fingerprint depends on operational telemetry")
end
if semantic_plan_a.telemetry_fingerprint == semantic_plan_b.telemetry_fingerprint then
  fail("CompilationPlan did not separate changing run telemetry evidence")
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
    {type = "gun-speed", ammo_category = "mir-fixture-definitely-missing-ammo-category", modifier = 0.1},
    {type = "unlock-space-location", space_location = "nauvis"},
    {type = "unlock-space-location", space_location = "mir-fixture-definitely-missing-space-location"},
    {type = "unlock-quality", quality = "normal"},
    {type = "unlock-quality", quality = "mir-fixture-definitely-missing-quality"},
    {type = "turret-attack", turret_id = "gun-turret", modifier = 0.1},
    {type = "turret-attack", turret_id = "mir-fixture-definitely-missing-entity", modifier = 0.1},
    {type = "give-item", item = "iron-plate", count = 1},
    {type = "give-item", item = "iron-plate", quality = "mir-fixture-definitely-missing-quality", count = 1}
  }
}
local kept_generic, removed_generic, retained_effect_order, retained_effect_identities = effect_safety.sanitize_effects(
  generic_effect_candidate.effects,
  "compiler-contract-generic-effects",
  "external")
if #kept_generic ~= 6 or #removed_generic ~= 6
  or removed_generic[1].original_effect_index ~= 2
  or removed_generic[2].original_effect_index ~= 4
  or removed_generic[3].original_effect_index ~= 6
  or removed_generic[4].original_effect_index ~= 8
  or removed_generic[5].original_effect_index ~= 10
  or removed_generic[6].original_effect_index ~= 12
  or type(removed_generic[1].removed_effect_fingerprint) ~= "string"
  or #retained_effect_identities ~= 6
  or retained_effect_order[1] ~= 1 or retained_effect_order[2] ~= 3
  or retained_effect_order[3] ~= 5 or retained_effect_order[4] ~= 7
  or retained_effect_order[5] ~= 9 or retained_effect_order[6] ~= 11 then
  fail("generic effect contracts did not retain valid targets and prune missing targets")
end
local default_quality_identity = effect_contracts.identity({type = "give-item", item = "iron-plate"})
local normal_quality_identity = effect_contracts.identity({type = "give-item", item = "iron-plate", quality = "normal"})
local epic_quality_identity = effect_contracts.identity({type = "give-item", item = "iron-plate", quality = "epic"})
if default_quality_identity ~= normal_quality_identity or normal_quality_identity == epic_quality_identity then
  fail("give-item identities do not bind the effective quality target")
end

local command_positions = {}
for index, id in ipairs(pipeline_commands.order()) do command_positions[id] = index end
if not (command_positions["compatibility-repairs"] < command_positions["sanitize-input-technology-effects"]
  and command_positions["sanitize-input-technology-effects"] < command_positions["module-permissions"]
  and command_positions["assert-technology-safety"] < command_positions["emit-compatibility-diagnostics"]
  and command_positions["assert-technology-safety"] < command_positions["assert-plan-output"]) then
  fail("pipeline does not sanitize finalized input before indexes or output before reports and parity checks")
end

if fingerprint.of({b = 2, a = 1}) ~= fingerprint.of({a = 1, b = 2}) then fail("map fingerprint is iteration-order dependent") end
local cyclic = {}; cyclic.self = cyclic
expect_error("cyclic fingerprint", "Cannot fingerprint cyclic table", function() fingerprint.of(cyclic) end)

local production_context = compiler_context.current()
local production_graph_parity = production_context:artifact("technology_graph_parity")
if not production_graph_parity or production_graph_parity.schema ~= 2
  or production_graph_parity.valid ~= true
  or production_graph_parity.registered_technology_count ~= production_graph_parity.planned_technology_count
  or production_graph_parity.expected_graph_fingerprint ~= production_graph_parity.actual_graph_fingerprint
  or type(production_graph_parity.component_assignment_fingerprint) ~= "string"
  or type(production_graph_parity.condensation_topology_fingerprint) ~= "string"
  or type(production_graph_parity.proof_fingerprint) ~= "string"
  or type(production_graph_parity.parity_fingerprint) ~= "string" then
  fail("emitted and planned technology graphs do not have exact parity evidence")
end
local relationship_view = relationships.view("output")
if relationship_view ~= relationships.view("output")
  or fingerprint.of(relationship_view) ~= fingerprint.of(relationships.snapshot("output")) then
  fail("relationship index view is not stable or snapshot-equivalent")
end
local recipe_view = recipe_facts.view("iron-plate")
if recipe_view and recipe_view ~= recipe_facts.view("iron-plate") then
  fail("recipe fact view is not stable within one CompilerContext")
end
local risk_source = recipe_facts.index_view()
local permuted_risk_source = {schema = risk_source.schema, facts = risk_source.facts, names = {}}
for index = #risk_source.names, 1, -1 do table.insert(permuted_risk_source.names, risk_source.names[index]) end
local canonical_risks = recipe_risk_facts.index_facts(risk_source, relationships.view("input"))
local permuted_risks = recipe_risk_facts.index_facts(permuted_risk_source, relationships.view("input"))
if canonical_risks.risk_index_fingerprint ~= permuted_risks.risk_index_fingerprint then
  fail("RecipeRiskFact canonicalization depends on prototype insertion order")
end
local production_catalog = production_context:state_snapshot("technology_candidate_catalog")
local production_qualifications = production_context:state_snapshot("technology_qualifications")
local production_plan = production_context:state_snapshot("generation_plan")
local public_plan_prototype = (data.raw["mod-data"] or {})["more-infinite-research-generation-plan"]
local public_plan = public_plan_prototype and public_plan_prototype.data
if not production_catalog or production_catalog.schema ~= 2 or production_catalog.mutation_authority ~= false
  or not production_qualifications
  or not production_plan or not public_plan
  or #production_catalog.candidates == 0
  or #production_catalog.qualifications ~= #production_qualifications
  or #production_catalog.current_selections ~= #production_plan.rows
  or #production_catalog.alternative_qualifications < #production_plan.rows then
  fail("CompilerContext does not own the technology candidate and qualification catalogs")
end
local public_rows = {}
for _, row in ipairs(public_plan.rows or {}) do public_rows[row.stream_id] = row end
local skipped_design_count = 0
for _, row in ipairs(production_plan.rows or {}) do
  local public_row = public_rows[row.stream_key]
  if not public_row or type(public_row.decision_fingerprint) ~= "string" then
    fail("public GenerationPlan row lacks a decision fingerprint")
  end
  if row.action == "skip" then
    skipped_design_count = skipped_design_count + 1
    if row.technology_design ~= nil
      or public_row.subject_fingerprint ~= nil
      or public_row.qualification_fingerprint ~= nil then
      fail("skipped GenerationPlan row eagerly constructed or published a TechnologyDesign")
    end
  elseif not row.technology_design
    or type(public_row.subject_fingerprint) ~= "string"
    or type(public_row.qualification_fingerprint) ~= "string" then
    fail("materializing GenerationPlan row lacks its public design fingerprints")
  end
end
if skipped_design_count == 0 then fail("compiler-contract fixture did not exercise skipped-row design deferral") end
local canonical_decisions = {}
for _, row in ipairs(family_resolver.snapshot().decisions or {}) do
  if row.rule == "loader-manufacturing" or row.rule == "mining-drill-manufacturing" then
    canonical_decisions[row.decision_fingerprint] = row
  end
end
local projected_decisions = 0
for _, row in ipairs((production_context:state_view("diagnostics") or {}).rows or {}) do
  if row.kind == "decision" and row.reason == "canonical_provider_decision_projection" then
    projected_decisions = projected_decisions + 1
    local canonical = canonical_decisions[row.decision_fingerprint]
    if not canonical or row.planner_decision_fingerprint ~= canonical.decision_fingerprint
      or row.risk_fingerprint ~= canonical.risk_fingerprint then
      fail("capability diagnostics did not project the exact planner decision and risk fingerprints")
    end
  end
end
local canonical_decision_count = 0
for _ in pairs(canonical_decisions) do canonical_decision_count = canonical_decision_count + 1 end
if projected_decisions ~= canonical_decision_count then
  fail("capability diagnostics omitted or duplicated canonical provider decisions")
end
local first_context = compiler_context.new()
first_context:set_state("fixture-derived-state", {value = 1})
first_context:set_state("fixture-epoch-state", {value = 1})
local _, epoch = first_context:replace_epoch("fixture-epoch-state", {value = 2}, 1)
if epoch ~= 2 or first_context:state_view("fixture-epoch-state").value ~= 2 then
  fail("CompilerContext explicit state epoch replacement is inconsistent")
end
expect_error("CompilerContext stale epoch", "epoch mismatch", function()
  first_context:replace_epoch("fixture-epoch-state", {value = 3}, 1)
end)
first_context:freeze_state("fixture-epoch-state")
expect_error("CompilerContext frozen state", "state is frozen", function()
  first_context:replace_epoch("fixture-epoch-state", {value = 4}, 2)
end)
first_context:record_artifact("fixture-artifact", {value = 2})
science_packs.all_lab_inputs()
science_packs.pack_production_status("automation-science-pack")
science_packs.technology_is_enabled_and_reachable("automation")
science_packs.mod_progression_packs_for({"automation-science-pack"})
for _, key in ipairs({
  "lab_input_index", "science_pack_recipe_status", "science_pack_production",
  "technology_researchability_index", "mod_progression_cache"
}) do
  if not first_context:has_state(key) then fail("science/progression cache was not context-owned: " .. key) end
end
if not first_context:has_service("science.pack_production_status")
  or not first_context:has_service("science.technology_researchability_reason") then
  fail("science dependency callbacks were not CompilerContext-owned services")
end
expect_error("CompilerContext duplicate service", "registered more than once", function()
  first_context:set_service("science.pack_production_status", function() return "invalid" end)
end)
first_context:freeze_services()
expect_error("CompilerContext frozen services", "services are frozen", function()
  first_context:set_service("fixture.late-service", function() return true end)
end)
local second_context = compiler_context.new()
if second_context:has_state("fixture-derived-state")
  or second_context:artifact("fixture-artifact") ~= nil then
  fail("CompilerContext instances leaked derived state or artifacts")
end
for _, key in ipairs({
  "lab_input_index", "science_pack_recipe_status", "science_pack_production",
  "technology_researchability_index", "mod_progression_cache"
}) do
  if second_context:has_state(key) then fail("science/progression cache crossed CompilerContext boundary: " .. key) end
end
compiler_context.activate(first_context)
local telemetry_before_snapshot = fingerprint.of(first_context:state_snapshot("compiler_telemetry"))
local first_snapshot = first_context:snapshot()
if telemetry_before_snapshot ~= fingerprint.of(first_context:state_snapshot("compiler_telemetry")) then
  fail("CompilerContext snapshot mutated live telemetry state")
end
first_snapshot.state["fixture-derived-state"].value = 99
first_snapshot.artifacts["fixture-artifact"].value = 99
if first_context:state_view("fixture-derived-state").value ~= 1
  or first_context:artifact("fixture-artifact").value ~= 2 then
  fail("CompilerContext snapshot did not isolate owned state")
end
compiler_context.activate(production_context)

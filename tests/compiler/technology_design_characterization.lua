local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local gate = require("prototypes.mir.domain.technology.gate")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_catalog = require("prototypes.mir.planner.technology_catalog")
local public_compiler_artifacts = require("prototypes.mir.report.public_compiler_artifacts")

local assertions = 0
local function check(condition, message)
  assert(condition, message)
  assertions = assertions + 1
end

local function expect_error(action, fragment)
  local ok, message = pcall(action)
  check(not ok and string.find(tostring(message), fragment, 1, true) ~= nil,
    "expected error containing: " .. fragment .. "; actual: " .. tostring(message))
end

local function row(changes)
  local result = {
    schema = 3,
    action = "emit",
    reason = "technology-design-characterization",
    source = "fixture-stream",
    stream_key = "fixture-productivity",
    manifest_id = "fixture-productivity",
    technology_name = "mir-fixture-productivity",
    target_profile_fingerprint = "mir32-01234567",
    provider_ids = {"fixture-provider"},
    family_ids = {"fixture-family"},
    fields = {
      localised_name = {"technology-name.mir-fixture-productivity"},
      localised_description = {"technology-description.mir-fixture-productivity"},
      icon = "__base__/graphics/technology/automation.png",
      icon_size = 256,
      effects = {{type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1}},
      prerequisites = {"automation"},
      ingredients = {{"automation-science-pack", 1}},
      count_formula = "100*L",
      research_time = 30,
      max_level = "infinite",
      order = "p[fixture-productivity]",
      level = 1,
      enabled = true,
      hidden = false,
      upgrade = true
    },
    spec = {
      family = "fixture-family",
      identity_state = "stable-unreleased",
      migration_policy = "stable",
      items = {"iron-plate"}
    },
    gates = {
      structural = gate.passed("fixture:structural", {"fixture:exact"})
    }
  }
  for key, value in pairs(changes or {}) do
    if key == "fields" then
      for field, field_value in pairs(value) do result.fields[field] = field_value end
    else
      result[key] = value
    end
  end
  return result
end

local schema = technology_design.schema_authority()
check(schema.schema == 2 and #schema.dimensions == 7, "schema-2 authority")
schema.dimensions[1] = "forged"
check(technology_design.schema_authority().dimensions[1] == "identity", "schema authority defensive copy")

local source_row = row()
local design = technology_design.from_generation_row(source_row)
check(technology_design.is_trusted(design), "constructor registers trusted record")
check(technology_design.assert_trusted(design), "trusted record assertion")
check(technology_design.validate(design), "trusted record remains deeply valid")
check(design.schema == 2 and design.technology_id == source_row.technology_name, "canonical identity")
check(design.subjects.recipes[1] == "iron-plate" and design.subjects.items[1] == "iron-plate",
  "canonical subjects")
local multiple_targets = technology_design.from_generation_row(row({fields = {effects = {
  {type = "gun-speed", ammo_category = "rocket", modifier = 0.1},
  {type = "gun-speed", ammo_category = "bullet", modifier = 0.1},
  {type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.1},
  {type = "gun-speed", ammo_category = "bullet", modifier = 0.2}
}}}))
check(#multiple_targets.subjects.effect_targets == 3
  and multiple_targets.subjects.effect_targets[1].name == "bullet"
  and multiple_targets.subjects.effect_targets[2].name == "cannon-shell"
  and multiple_targets.subjects.effect_targets[3].name == "rocket",
  "effect-target subjects retain canonical ordering and deduplication")

local equivalent = technology_design.from_generation_row(row())
check(design.subject_fingerprint == equivalent.subject_fingerprint, "stable subject fingerprint")
check(design.design_fingerprint == equivalent.design_fingerprint, "stable design fingerprint")
check(design.prototype_fingerprint == equivalent.prototype_fingerprint, "stable prototype fingerprint")
check(design.qualification_fingerprint == equivalent.qualification_fingerprint,
  "stable qualification fingerprint")

source_row.technology_design = design
check(technology_design.assert_generation_row(source_row), "legacy generation projection agreement")
local mismatched_row = row()
mismatched_row.technology_design = design
mismatched_row.fields.research_time = 31
expect_error(function() technology_design.assert_generation_row(mismatched_row) end,
  "GenerationPlan legacy projection differs from TechnologyDesign")

local prototype = technology_design.prototype_projection(design, {validated = true})
prototype.effects[1].change = 99
prototype.unit.ingredients[1][2] = 99
local prototype_again = technology_design.prototype_projection(design, {validated = true})
check(prototype_again.effects[1].change == 0.1, "prototype effect defensive copy")
check(prototype_again.unit.ingredients[1][2] == 1, "prototype science defensive copy")
local trusted_view = technology_design.trusted_prototype_projection_view(design)
check(trusted_view.name == design.technology_id and trusted_view.effects == design.design.effects.value,
  "trusted prototype view preserves the owned projection")
local graph = technology_design.graph_projection(design)
graph.prerequisites[1] = "forged"
check(technology_design.graph_projection(design).prerequisites[1] == "automation", "graph defensive copy")
local presentation = technology_design.presentation_projection(design)
presentation.localised_name[1] = "forged"
check(technology_design.presentation_projection(design).localised_name[1]
  == "technology-name.mir-fixture-productivity", "presentation defensive copy")

local copied = deepcopy(design)
check(not technology_design.is_trusted(copied), "deep copy carries no trust")
expect_error(function() technology_design.assert_trusted(copied) end, "Trusted TechnologyDesign record is required")
check(technology_design.verify_untrusted(copied), "exact copied record re-enters through deep verification")
check(technology_design.is_trusted(copied), "verified copy gains only its own trust")

local field_modified = deepcopy(design)
field_modified.design.cost.value.count_formula = "1"
expect_error(function() technology_design.verify_untrusted(field_modified) end,
  "TechnologyDesign dimension differs from leaf provenance")
local fingerprint_modified = deepcopy(design)
fingerprint_modified.design_fingerprint = "mir32-deadbeef"
expect_error(function() technology_design.verify_untrusted(fingerprint_modified) end,
  "TechnologyDesign semantic identity fingerprints differ")
local unknown_materialization = deepcopy(design)
unknown_materialization.materialization.future_authority = true
expect_error(function() technology_design.verify_untrusted(unknown_materialization) end,
  "TechnologyDesign materialization contains unknown field")

local scalar_tamper = technology_design.from_generation_row(row())
scalar_tamper.technology_id = "forged-technology"
expect_error(function() technology_design.assert_trusted(scalar_tamper) end,
  "Trusted TechnologyDesign record is required")

local changed_name = row({fields = {
  localised_name = {"technology-name.changed-fixture-productivity"}
}})
local changed_design = technology_design.from_generation_row(changed_name)
local changes = technology_design.diff(design, changed_design)
check(#changes == 1 and changes[1].path == "presentation.localised_name", "deterministic field diff")
expect_error(function() technology_design.merge(design, changed_design) end,
  "TechnologyDesign locked field changed without authorization")
local overridden = technology_design.merge(design, changed_design, "override")
check(not technology_design.is_trusted(overridden), "merge result is a defensive untrusted copy")
check(technology_design.verify_untrusted(overridden), "authorized merge result remains structurally valid")

local extended_effects = row({fields = {effects = {
  {type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1},
  {type = "change-recipe-productivity", recipe = "copper-plate", change = 0.1}
}}})
local extended_design = technology_design.from_generation_row(extended_effects)
check(technology_design.assert_locks(design, extended_design), "effect addition inside fixed envelope")
local outside_envelope = row({fields = {effects = {
  {type = "change-recipe-productivity", recipe = "iron-plate", change = 0.2}
}}})
expect_error(function()
  technology_design.assert_locks(design, technology_design.from_generation_row(outside_envelope))
end, "TechnologyDesign effect value left its approved envelope")

local qualified_row = row({
  reason = "qualified-fixture",
  target_profile_fingerprint = "mir32-89abcdef",
  gates = {structural = gate.passed("fixture:structural", {"fixture:qualified"})}
})
local qualified = technology_design.with_qualification(design, qualified_row,
  {validated = true, share_immutable = true})
check(technology_design.is_trusted(qualified), "qualified derivation is trusted")
check(qualified.subject_fingerprint == design.subject_fingerprint
  and qualified.design_fingerprint == design.design_fingerprint
  and qualified.prototype_fingerprint == design.prototype_fingerprint,
  "qualification preserves subject design and prototype identity")
check(qualified.qualification_fingerprint ~= design.qualification_fingerprint,
  "qualification changes qualification identity")
check(qualified.design == design.design and qualified.subjects == design.subjects,
  "qualified derivation shares immutable semantic branches")

local diagnostic = technology_design.as_diagnostic_alternative(qualified, "fixture-diagnostic",
  {validated = true})
check(technology_design.is_trusted(diagnostic), "diagnostic derivation is trusted")
check(diagnostic.materialization.kind == "diagnose"
  and diagnostic.design.ownership.value.action == "diagnose"
  and diagnostic.maturity.runtime_action == "diagnose", "diagnostic action projection")
check(diagnostic.subject_fingerprint == qualified.subject_fingerprint
  and diagnostic.prototype_fingerprint == qualified.prototype_fingerprint,
  "diagnostic preserves subject and prototype identity")
check(diagnostic.design_fingerprint ~= qualified.design_fingerprint
  and diagnostic.qualification_fingerprint ~= qualified.qualification_fingerprint,
  "diagnostic recomputes changed identities")

local continuation = technology_design.from_base_extension_operation({
  key = "fixture-continuation",
  manifest_id = "fixture-continuation",
  base_technology_name = "automation",
  technology = {
    name = "mir-fixture-continuation",
    localised_name = {"technology-name.mir-fixture-continuation"},
    localised_description = {"technology-description.mir-fixture-continuation"},
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    effects = {}, prerequisites = {"automation"},
    unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "100*L", time = 30},
    max_level = "infinite", order = "p[fixture-continuation]", level = 1, upgrade = true
  },
  gates = {structural = gate.passed("fixture:continuation", {"fixture:exact"})}
})
check(continuation.materialization.kind == "continuation"
  and continuation.maturity.runtime_action == "continuation", "base continuation construction")
check(technology_design.save_identity_projection(continuation).technology_id
  == "mir-fixture-continuation", "save identity projection")

-- The player catalog can defer a diagnostic only when the exact final primary
-- alternative has already qualified and policy will select it.  The catalog
-- must describe that omission explicitly, retain normal diagnostics in every
-- other case, and never let a partial inventory pass as an export inventory.
local function catalog_gates(state)
  local gates = {}
  for _, gate_name in ipairs(hard_gate_authority.order()) do
    if state == "failed" and gate_name == "loop_safe" then
      gates[gate_name] = gate.failed("catalog-fixture:" .. gate_name, "fixture-failed", {})
    elseif state == "pending" and gate_name == "loop_safe" then
      gates[gate_name] = gate.pending("catalog-fixture:" .. gate_name)
    else
      gates[gate_name] = gate.passed("catalog-fixture:" .. gate_name, {"fixture-passed"})
    end
  end
  return gates
end

local function catalog_emit_row(suffix, action, gate_state)
  local result = row({
    action = action or "emit",
    reason = "catalog-fixture-" .. suffix,
    stream_key = "fixture-catalog-" .. suffix,
    manifest_id = "fixture-catalog-" .. suffix,
    technology_name = "mir-fixture-catalog-" .. suffix,
    gates = catalog_gates(gate_state)
  })
  result.fields.localised_name = {"technology-name." .. result.technology_name}
  result.fields.localised_description = {"technology-description." .. result.technology_name}
  result.fields.order = "p[" .. result.stream_key .. "]"
  result.technology_design = technology_design.from_generation_row(result)
  return result
end

local function catalog_adopt_row(suffix)
  local owner = "fixture-native-" .. suffix
  local result = row({
    action = "adopt",
    reason = "catalog-adopt-" .. suffix,
    stream_key = "fixture-adopt-" .. suffix,
    manifest_id = "fixture-adopt-" .. suffix,
    gates = catalog_gates(),
    fields = {
      localised_name = {"technology-name." .. owner},
      localised_description = {"technology-description." .. owner},
      order = "p[fixture-adopt-" .. suffix .. "]"
    }
  })
  result.technology_name = nil
  local expected = {
    name = owner,
    effects = deepcopy(result.fields.effects),
    prerequisites = deepcopy(result.fields.prerequisites),
    unit = {
      ingredients = deepcopy(result.fields.ingredients),
      count_formula = result.fields.count_formula,
      time = result.fields.research_time
    },
    max_level = result.fields.max_level,
    localised_name = deepcopy(result.fields.localised_name),
    localised_description = deepcopy(result.fields.localised_description),
    icon = result.fields.icon,
    icon_size = result.fields.icon_size,
    order = result.fields.order,
    level = result.fields.level,
    enabled = result.fields.enabled,
    hidden = result.fields.hidden,
    upgrade = result.fields.upgrade
  }
  result.adoption = {
    owner = owner,
    operation = "fixture-preserve",
    configured_fields = {},
    expected_snapshot = expected,
    input_fingerprint = "mir32-01234567",
    output_fingerprint = "mir32-01234567"
  }
  local provisional = technology_design.from_generation_row(result)
  result.adoption.output_fingerprint = provisional.prototype_fingerprint
  result.technology_design = technology_design.from_generation_row(result)
  check(technology_design.assert_generation_row(result), "adopt fixture retains its exact native projection")
  return result
end

local function catalog_operation(row_value)
  return {stream_key = row_value.stream_key, technology_design = row_value.technology_design}
end

local function finalize_catalog(row_value, defer)
  local operations = (row_value.action == "emit" or row_value.action == "adopt")
    and {catalog_operation(row_value)} or {}
  return technology_catalog.finalize(
    {row_value},
    {fixture = "catalog-deferred-diagnostics"},
    operations,
    {defer_diagnostic_alternatives = defer == true}
  )
end

local catalog_emit = catalog_emit_row("emit")
local catalog_full = finalize_catalog(catalog_emit, false)
local catalog_deferred = finalize_catalog(catalog_emit, true)
check(catalog_full.schema == 4 and catalog_full.alternative_evaluation.mode == "full-diagnostics"
  and catalog_full.alternative_evaluation.complete
  and catalog_full.alternative_evaluation.evaluated_alternatives == 2
  and catalog_full.alternative_evaluation.deferred_diagnostic_alternatives == 0,
  "default final catalog retains its complete diagnostic inventory")
check(#catalog_full.candidates[1].alternatives == 2
  and catalog_full.candidates[1].diagnostic_evaluation.state == "constructed",
  "default final catalog records its constructed diagnostic binding")
check(catalog_deferred.alternative_evaluation.mode == "player-selected-primary-plus-required-fallbacks"
  and not catalog_deferred.alternative_evaluation.complete
  and catalog_deferred.alternative_evaluation.evaluated_alternatives == 1
  and catalog_deferred.alternative_evaluation.deferred_diagnostic_alternatives == 1
  and #catalog_deferred.candidates[1].alternatives == 1,
  "qualified final emit omits only its otherwise-losing diagnostic")
check(catalog_deferred.candidates[1].diagnostic_evaluation.state == "deferred-primary-qualified"
  and catalog_deferred.current_selections[1].action == "emit"
  and fingerprint.of(catalog_full.current_selections) == fingerprint.of(catalog_deferred.current_selections),
  "deferred final emit preserves the exact selected vector")
check(technology_catalog.require_full_diagnostics(catalog_full) == catalog_full,
  "complete catalog satisfies full diagnostics guard")
expect_error(function() technology_catalog.require_full_diagnostics(catalog_deferred) end,
  "full diagnostics are required")

local catalog_adopt = catalog_adopt_row("qualified")
local catalog_adopt_full = finalize_catalog(catalog_adopt, false)
local catalog_adopt_deferred = finalize_catalog(catalog_adopt, true)
check(catalog_adopt_deferred.candidates[1].diagnostic_evaluation.state == "deferred-primary-qualified"
  and #catalog_adopt_deferred.candidates[1].alternatives == 1
  and catalog_adopt_deferred.current_selections[1].action == "adopt"
  and fingerprint.of(catalog_adopt_full.current_selections)
    == fingerprint.of(catalog_adopt_deferred.current_selections),
  "qualified final adopt defers only its diagnostic and preserves selection")

local catalog_skip = catalog_emit_row("skip", "skip")
local catalog_skip_final = finalize_catalog(catalog_skip, true)
check(catalog_skip_final.alternative_evaluation.mode == "full-diagnostics"
  and catalog_skip_final.alternative_evaluation.complete
  and #catalog_skip_final.candidates[1].alternatives == 2
  and catalog_skip_final.candidates[1].diagnostic_evaluation.state == "constructed"
  and catalog_skip_final.current_selections[1].action == "diagnose",
  "skip retains the full required diagnostic fallback")

local catalog_failed = technology_catalog.from_preselection_rows(
  {catalog_emit_row("failed", "emit", "failed")},
  {fixture = "catalog-failed"},
  {phase = "final", defer_diagnostic_alternatives = true, defer_validation = true, children_admitted = true}
)
check(catalog_failed.alternative_evaluation.mode == "full-diagnostics"
  and catalog_failed.alternative_evaluation.complete
  and #catalog_failed.candidates[1].alternatives == 2
  and catalog_failed.candidates[1].diagnostic_evaluation.state == "constructed",
  "rejected primary retains a complete diagnostic fallback")
check(technology_catalog.verify_untrusted(deepcopy(catalog_failed)),
  "rejected primary complete fallback remains a valid final catalog")

local catalog_unresolved = technology_catalog.from_preselection_rows(
  {catalog_emit_row("unresolved", "emit", "pending")},
  {fixture = "catalog-unresolved"},
  {phase = "final", defer_diagnostic_alternatives = true, defer_validation = true, children_admitted = true}
)
check(catalog_unresolved.alternative_evaluation.mode == "full-diagnostics"
  and #catalog_unresolved.candidates[1].alternatives == 2
  and catalog_unresolved.candidates[1].diagnostic_evaluation.state == "constructed",
  "unresolved primary cannot omit its diagnostic")
expect_error(function() technology_catalog.verify_untrusted(deepcopy(catalog_unresolved)) end,
  "final qualification has an unresolved hard gate")

local catalog_preselection = technology_catalog.from_preselection_rows(
  {catalog_emit_row("preselection")},
  {fixture = "catalog-preselection"},
  {phase = "preselection", defer_diagnostic_alternatives = true}
)
check(catalog_preselection.alternative_evaluation.mode == "full-diagnostics"
  and catalog_preselection.alternative_evaluation.complete
  and #catalog_preselection.candidates[1].alternatives == 2
  and catalog_preselection.candidates[1].diagnostic_evaluation.state == "constructed",
  "preselection never omits diagnostic alternatives")

local selected_permutation_left = catalog_emit_row("permutation-left")
local selected_permutation_right = catalog_emit_row("permutation-right")
local function finalize_permutation(rows)
  local operations = {}
  for _, row_value in ipairs(rows) do table.insert(operations, catalog_operation(row_value)) end
  return technology_catalog.finalize(
    rows, {fixture = "catalog-permutation"}, operations,
    {defer_diagnostic_alternatives = true}
  )
end
local permutation_forward = finalize_permutation({selected_permutation_left, selected_permutation_right})
local permutation_reverse = finalize_permutation({selected_permutation_right, selected_permutation_left})
check(fingerprint.of(permutation_forward.current_selections) == fingerprint.of(permutation_reverse.current_selections)
  and permutation_forward.alternative_evaluation.deferred_diagnostic_alternatives == 2
  and permutation_reverse.alternative_evaluation.deferred_diagnostic_alternatives == 2,
  "deferred primary selection remains permutation independent")

local forged_deferred_binding = technology_catalog.snapshot(catalog_deferred)
forged_deferred_binding.candidates[1].diagnostic_evaluation.primary_design_fingerprint = "mir32-forged"
expect_error(function() technology_catalog.verify_untrusted(forged_deferred_binding) end,
  "deferred diagnostic primary proof is invalid")
local forged_deferred_diagnostic = technology_catalog.snapshot(catalog_deferred)
forged_deferred_diagnostic.candidates[1].diagnostic_evaluation.diagnostic_design_fingerprint = "mir32-invented"
expect_error(function() technology_catalog.verify_untrusted(forged_deferred_diagnostic) end,
  "deferred diagnostic evaluation contains an unknown field")
local forged_evaluation_field = technology_catalog.snapshot(catalog_deferred)
forged_evaluation_field.alternative_evaluation.invented_total = 1
expect_error(function() technology_catalog.verify_untrusted(forged_evaluation_field) end,
  "alternative evaluation state contains an unknown field")
local forged_deferred_count = technology_catalog.snapshot(catalog_deferred)
forged_deferred_count.alternative_evaluation.evaluated_alternatives = 2
expect_error(function() technology_catalog.verify_untrusted(forged_deferred_count) end,
  "alternative evaluation counts are invalid")
local forged_rejected_qualification = technology_catalog.snapshot(catalog_deferred)
local rejected_qualification = deepcopy(catalog_failed.qualifications[1])
forged_rejected_qualification.qualifications[1] = rejected_qualification
forged_rejected_qualification.candidates[1].alternatives[1].qualification_fingerprint
  = rejected_qualification.qualification_fingerprint
forged_rejected_qualification.candidates[1].diagnostic_evaluation.primary_qualification_fingerprint
  = rejected_qualification.qualification_fingerprint
forged_rejected_qualification.alternative_qualifications[1].qualification_fingerprint
  = rejected_qualification.qualification_fingerprint
expect_error(function() technology_catalog.verify_untrusted(forged_rejected_qualification) end,
  "alternative qualification does not bind its candidate")
local unbound_qualification = technology_catalog.snapshot(catalog_deferred)
table.insert(unbound_qualification.qualifications, deepcopy(catalog_failed.qualifications[1]))
expect_error(function() technology_catalog.verify_untrusted(unbound_qualification) end,
  "qualification inventory does not match alternatives")
local missing_alternative_mapping = technology_catalog.snapshot(catalog_deferred)
table.remove(missing_alternative_mapping.alternative_qualifications, 1)
expect_error(function() technology_catalog.verify_untrusted(missing_alternative_mapping) end,
  "alternative qualification mappings are incomplete")
local duplicate_alternative_mapping = technology_catalog.snapshot(catalog_deferred)
table.insert(duplicate_alternative_mapping.alternative_qualifications,
  deepcopy(duplicate_alternative_mapping.alternative_qualifications[1]))
expect_error(function() technology_catalog.verify_untrusted(duplicate_alternative_mapping) end,
  "alternative qualification mapping is duplicated")
local duplicate_deferred_selection = technology_catalog.snapshot(catalog_deferred)
table.insert(duplicate_deferred_selection.current_selections,
  deepcopy(duplicate_deferred_selection.current_selections[1]))
expect_error(function() technology_catalog.verify_untrusted(duplicate_deferred_selection) end,
  "deferred diagnostic primary selection is invalid")
local missing_deferred_selection = technology_catalog.snapshot(catalog_deferred)
table.remove(missing_deferred_selection.current_selections, 1)
expect_error(function() technology_catalog.verify_untrusted(missing_deferred_selection) end,
  "deferred diagnostic primary selection is invalid")

local caller_snapshot = technology_catalog.snapshot(catalog_deferred)
caller_snapshot.candidates[1].diagnostic_evaluation.state = "forged"
caller_snapshot.alternative_evaluation.evaluated_alternatives = 99
local caller_snapshot_again = technology_catalog.snapshot(catalog_deferred)
check(caller_snapshot_again.candidates[1].diagnostic_evaluation.state == "deferred-primary-qualified"
  and caller_snapshot_again.alternative_evaluation.evaluated_alternatives == 1,
  "catalog query snapshots isolate deferred-evaluation metadata")

local public_full_catalog = public_compiler_artifacts.technology_catalog(catalog_full, {})
local public_deferred_catalog = public_compiler_artifacts.technology_catalog(catalog_deferred, {})
check(public_full_catalog.schema == 2 and public_full_catalog.alternative_evaluation.complete
  and public_full_catalog.counts.evaluated_alternatives == 2
  and public_full_catalog.counts.deferred_diagnostic_alternatives == 0,
  "public complete catalog reports complete evaluated inventory")
check(public_deferred_catalog.schema == 2 and not public_deferred_catalog.alternative_evaluation.complete
  and public_deferred_catalog.counts.evaluated_alternatives == 1
  and public_deferred_catalog.counts.deferred_diagnostic_alternatives == 1,
  "public partial catalog reports evaluated and deferred counts honestly")
local forged_public_catalog = technology_catalog.snapshot(catalog_deferred)
forged_public_catalog.alternative_evaluation.evaluated_alternatives = 2
expect_error(function() public_compiler_artifacts.technology_catalog(forged_public_catalog, {}) end,
  "evaluated alternative count differs")

-- Compare cold and warm digests against the pre-cache scalar recurrence,
-- including byte-block boundaries, binary text and the cache's size cutoff.
local fingerprint = require("prototypes.mir.core.fingerprint")
check(fingerprint.canonical(nil) == "null" and fingerprint.canonical(false) == "false"
  and fingerprint.canonical(2) == "2", "scalar canonical bytes")
check(fingerprint.canonical({z = {false, true}, a = {b = "value"}})
  == '{"a":{"b":"value"},"z":[false,true]}', "nested map and array canonical bytes")
check(fingerprint.canonical({[0] = "zero", [10] = "ten", a = {}})
  == '{[0]:"zero",[10]:"ten","a":[]}', "mixed-key canonical ordering")
check(fingerprint.canonical({[1] = "one", [3] = "three"})
  == '{[1]:"one",[3]:"three"}', "sparse arrays remain maps")
local shared = {v = 2}
check(fingerprint.canonical({shared, shared}) == '[{"v":2},{"v":2}]',
  "shared branches are serialized at each occurrence")
local escaped = "quote\"\n\000\\"
check(fingerprint.canonical({escaped}) == '[' .. string.format("%q", escaped) .. ']',
  "quoted string bytes remain engine compatible")
local repeated = {}
for index = 1, 1024 do repeated[index] = {a = "value", z = {false, true}} end
check(fingerprint.canonical(repeated) == '['
  .. string.rep('{"a":"value","z":[false,true]},', 1023)
  .. '{"a":"value","z":[false,true]}]', "large nested canonical buffer bytes")
local function scalar_digest(text)
  local hash = 2166136261.0
  for index = 1, #text do
    hash = (hash * 65599.0 + string.byte(text, index)) % 4294967291.0
  end
  return "mir32-" .. string.format("%08x", hash)
end
for _, length in ipairs({0, 1, 7, 8, 15, 16, 17, 65536, 65537}) do
  local text = string.sub(string.rep("\000\255cache\n\"", math.ceil(length / 9)), 1, length)
  local expected = scalar_digest(text)
  check(fingerprint.of_canonical(text) == expected, "cold scalar digest parity " .. length)
  check(fingerprint.of_canonical(text) == expected, "warm scalar digest parity " .. length)
end
-- Independent scalar oracle for the fused polynomial reduction. Cover each
-- tail length after several sixteen-byte blocks, all byte values, maximal
-- byte coefficients, and payloads above the cache's retained-text cutoff.
do
  local all_bytes = {}
  for byte = 0, 255 do all_bytes[#all_bytes + 1] = string.char(byte) end
  all_bytes = table.concat(all_bytes)
  for length = 0, 95 do
    for pattern, text in ipairs({string.rep(string.char(0), length),
      string.rep(string.char(255), length), all_bytes:sub(1, length)}) do
      check(fingerprint.of_canonical(text) == scalar_digest(text),
        "fused binary block scalar parity " .. pattern .. ":" .. length)
    end
  end
  for _, text in ipairs({string.rep(all_bytes, 257), string.rep(string.char(255), 65537)}) do
    check(fingerprint.of_canonical(text) == scalar_digest(text), "fused uncached scalar parity")
  end
end
-- Fixed independent MIR32 vectors cross the 64-byte front block exactly.
-- They deliberately include NUL and binary bytes; the literals remain stable
-- even if the polynomial block implementation is accidentally corrupted.
do
  local seed = string.char(0, 255, 1, 128, 13, 10, 34, 92)
  local vectors = {
    {length = 63, digest = "mir32-733948da"},
    {length = 64, digest = "mir32-a3f52eab"},
    {length = 65, digest = "mir32-8804b0a6"},
    {length = 127, digest = "mir32-1a5c4038"},
    {length = 128, digest = "mir32-bcec520e"},
    {length = 129, digest = "mir32-d039e2f4"}
  }
  for _, vector in ipairs(vectors) do
    local text = string.sub(string.rep(seed, math.ceil(vector.length / #seed)), 1, vector.length)
    check(fingerprint.of_canonical(text) == vector.digest,
      "64-byte fixed binary MIR32 cold vector " .. vector.length)
    check(fingerprint.of_canonical(text) == vector.digest,
      "64-byte fixed binary MIR32 warm vector " .. vector.length)
  end
end
for index = 1, 4100 do fingerprint.of_canonical("fifo-eviction-" .. index) end
local cache_metrics = fingerprint.metrics()
check(cache_metrics.hash_cache_entries <= 4096 and cache_metrics.hash_cache_bytes <= 2 * 1024 * 1024,
  "canonical digest cache residency is bounded")
check(fingerprint.of_canonical("fifo-eviction-1") == scalar_digest("fifo-eviction-1"),
  "eviction preserves digest identity")
local oversized = string.rep("oversized", 8000)
local before = fingerprint.metrics().hash_computations
fingerprint.of_canonical(oversized)
fingerprint.of_canonical(oversized)
check(fingerprint.metrics().hash_computations == before + 2, "oversized inputs are not retained")
local mutable = {nested = {value = 1}}
local previous_digest = fingerprint.of(mutable)
mutable.nested.value = 2
check(fingerprint.of(mutable) ~= previous_digest, "mutable input is reserialized before cache lookup")
local cyclic = {}; cyclic.self = cyclic
expect_error(function() fingerprint.of({nested = cyclic}) end, "cyclic table at $.nested.self")
expect_error(function() fingerprint.of({outer = {[{}] = "invalid key"}}) end,
  "map keys must be strings or numbers at $.outer")
check(fingerprint.canonical({{}, {a = {}}, {}, {b = {false, {}, true}}})
  == '[[],{"a":[]},[],{"b":[false,[],true]}]',
  "buffer cursor follows empty and populated sibling branches")
check(fingerprint.canonical({nested = {{[0] = "zero", [2] = "two"}, {}}})
  == '{"nested":[{[0]:"zero",[2]:"two"},[]]}',
  "buffer cursor crosses nested mixed-key maps and arrays")
expect_error(function() fingerprint.canonical({1, {deep = function() end}}) end,
  "Cannot fingerprint value of type function at $[2].deep")
local mixed_cycle = {}; mixed_cycle[0] = {back = mixed_cycle}
expect_error(function() fingerprint.canonical(mixed_cycle) end,
  "cyclic table at $[0].back")
check(fingerprint.canonical({true, {}, false}) == '[true,[],false]',
  "a diagnostic failure cannot retain another call's buffer cursor")

-- Cached numeric text must preserve the engine's exact formatting, including
-- signed zero and NaN, without retaining any containing mutable record.
do
  local values = {0, -1 / math.huge, 1, -1, 0.1, -0.1, 1 / 3, -1 / 3,
    2 ^ 53, -2 ^ 53, 1e-308, -1e-308, 1e308, -1e308, math.huge, -math.huge, 0 / 0}
  for index, value in ipairs(values) do
    local expected = string.format("%.17g", value)
    check(fingerprint.canonical(value) == expected, "numeric canonical bytes " .. index)
    check(fingerprint.of(value) == scalar_digest(expected), "numeric scalar digest " .. index)
    check(fingerprint.canonical_length(value) == #expected, "numeric canonical length " .. index)
  end
  local map = {[-3.25] = math.huge, [2.5] = -1 / math.huge, tag = {1 / 3}}
  local expected_map = '{[-3.25]:' .. string.format("%.17g", math.huge)
    .. ',[2.5]:' .. string.format("%.17g", -1 / math.huge)
    .. ',"tag":[' .. string.format("%.17g", 1 / 3) .. ']}'
  check(fingerprint.canonical(map) == expected_map, "cached numeric mixed-map bytes and ordering")
  check(fingerprint.of(map) == scalar_digest(expected_map), "cached numeric mixed-map digest")

  fingerprint.canonical(12345.625)
  local warm_before = fingerprint.metrics()
  fingerprint.canonical(12345.625)
  fingerprint.canonical(12345.625)
  local warm_after = fingerprint.metrics()
  check(warm_after.numeric_text_computations == warm_before.numeric_text_computations,
    "warm numeric values do not repeat formatting")
  check(warm_after.numeric_text_cache_hits == warm_before.numeric_text_cache_hits + 2,
    "numeric cache reports actual scalar reuse")
  local record = {nested = {amount = 1 / 3}}
  local old_text, old_digest = fingerprint.canonical(record), fingerprint.of(record)
  record.nested.amount = -1 / 3
  check(fingerprint.canonical(record) ~= old_text and fingerprint.of(record) ~= old_digest,
    "numeric reuse does not hide mutations in containing records")

  for index = 1, 4200 do
    local value = 987000 + index + 0.375
    local expected = string.format("%.17g", value)
    check(fingerprint.canonical(value) == expected and fingerprint.of(value) == scalar_digest(expected),
      "numeric cache capacity preserves bytes and digest " .. index)
  end
  local full = fingerprint.metrics()
  check(full.numeric_text_cache_entries == 4096, "numeric text residency stops at its fixed capacity")
  local uncached = 7777777.25
  local expected_uncached = string.format("%.17g", uncached)
  local first, second = fingerprint.canonical(uncached), fingerprint.canonical(uncached)
  check(first == expected_uncached and second == expected_uncached
    and fingerprint.metrics().numeric_text_computations == full.numeric_text_computations + 2,
    "full numeric cache falls back to exact formatting without changing admission")
  fingerprint.reset_metrics()
  local reset = fingerprint.metrics()
  check(reset.numeric_text_computations == 0 and reset.numeric_text_cache_hits == 0
    and reset.numeric_text_cache_entries == full.numeric_text_cache_entries,
    "metric reset preserves bounded scalar residency")
end

-- Projection composition must equal two ordinary complete serializations,
-- including empty selections, sparse/mixed children, aliases and long fields.
-- The expected digest uses the independent scalar recurrence above.
do
  local fixtures = {
    {},
    {a = false, b = {}, c = 1 / 3, d = escaped},
    {a = {shared, shared}, b = {[0] = "zero", [3] = "three"},
      c = {nested = {false, true}}, d = string.rep("x", 65537)},
    {a = string.rep("\000\255\n\"", 17000), b = repeated, c = -1.25, d = "tail"}
  }
  for fixture_index, value in ipairs(fixtures) do
    for mask = 0, 15 do
      local selected, projected = {}, {}
      for index, key in ipairs({"a", "b", "c", "d"}) do
        if value[key] ~= nil and math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then
          -- Reverse selection order must not affect external canonical order.
          table.insert(selected, 1, key)
          projected[key] = value[key]
        end
      end
      local full_text, projected_text = fingerprint.canonical(value), fingerprint.canonical(projected)
      local full_digest, projected_digest, projected_bytes = fingerprint.of_map_with_projection(value, selected)
      check(full_digest == scalar_digest(full_text), "map full scalar parity " .. fixture_index .. ":" .. mask)
      check(projected_digest == scalar_digest(projected_text), "map projection scalar parity " .. fixture_index .. ":" .. mask)
      check(projected_bytes == #projected_text, "map projection exact length " .. fixture_index .. ":" .. mask)
    end
  end
  local alias = {amount = 1}
  local value = {facts = {left = alias, right = alias}, names = {"left", "right"}, schema = 2}
  local old_full, old_projected = fingerprint.of_map_with_projection(value, {"facts"})
  alias.amount = 2
  local new_full, new_projected = fingerprint.of_map_with_projection(value, {"facts"})
  check(old_full ~= new_full and old_projected ~= new_projected,
    "projection composition does not retain mutable table identity")
  check(new_full == fingerprint.of(value) and new_projected == fingerprint.of({facts = value.facts}),
    "mutated shared projection remains byte equivalent")
  local root_alias = {a = alias, z = alias}
  local alias_full, alias_projected, alias_bytes = fingerprint.of_map_with_projection(root_alias, {"z"})
  check(alias_full == fingerprint.of(root_alias), "top-level shared aliases remain distinct serialized occurrences")
  check(alias_projected == fingerprint.of({z = alias}), "top-level selected alias projection parity")
  check(alias_bytes == #fingerprint.canonical({z = alias}), "top-level selected alias projection length")
  for _, fragment_bytes in ipairs({7, 8, 15, 16, 17, 31, 32, 33, 65535, 65536, 65537, 1048576}) do
    local field = string.rep("x", fragment_bytes - 6)
    local boundary_value, boundary_projection = {a = field, z = {false, true}}, {a = field}
    local boundary_full, boundary_digest, boundary_length = fingerprint.of_map_with_projection(boundary_value, {"a"})
    check(boundary_full == scalar_digest(fingerprint.canonical(boundary_value)), "fragment full scalar boundary " .. fragment_bytes)
    check(boundary_digest == scalar_digest(fingerprint.canonical(boundary_projection)), "fragment projection scalar boundary " .. fragment_bytes)
    check(boundary_length == #fingerprint.canonical(boundary_projection), "fragment exact byte boundary " .. fragment_bytes)
  end
  local large_fragment = {a = string.rep("x", 100000)}
  local retained_before = fingerprint.metrics()
  fingerprint.of_map_with_projection(large_fragment, {"a"})
  fingerprint.of_map_with_projection(large_fragment, {"a"})
  local retained_after = fingerprint.metrics()
  check(retained_after.hash_computations == retained_before.hash_computations + 2,
    "large projection fragment is hashed once per call and is never retained")
  check(retained_after.hash_cache_bytes == retained_before.hash_cache_bytes,
    "large shared fragments add no retained digest-cache text")
  local root_cycle = {}; root_cycle.facts = {back = root_cycle}
  expect_error(function() fingerprint.of_map_with_projection(root_cycle, {"facts"}) end,
    "cyclic table at $.facts.back")
  expect_error(function() fingerprint.of_map_with_projection({a = 1, excluded = function() end}, {"a"}) end,
    "Cannot fingerprint value of type function at $.excluded")
  expect_error(function() fingerprint.of_map_with_projection({a = 1, excluded = cyclic}, {"a"}) end,
    "cyclic table at $.excluded.self")
  expect_error(function() fingerprint.of_map_with_projection({a = 1}, {"a", "a"}) end,
    "keys must be distinct existing strings")
  expect_error(function() fingerprint.of_map_with_projection({a = 1}, {"absent"}) end,
    "keys must be distinct existing strings")
  expect_error(function() fingerprint.of_map_with_projection(setmetatable({a = 1}, {__index = {absent = 2}}), {"absent"}) end,
    "requires a string-keyed map and key array")
  expect_error(function() fingerprint.of_map_with_projection(setmetatable({}, {__pairs = function() return next, {virtual = 1}, nil end}), {}) end,
    "requires a string-keyed map and key array")
  expect_error(function() fingerprint.of_map_with_projection(setmetatable({a = 1}, {__pairs = function() return next, {virtual = 1}, nil end}), {"a"}) end,
    "requires a string-keyed map and key array")
  expect_error(function() fingerprint.of_map_with_projection({a = 1}, setmetatable({"a"}, {})) end,
    "requires a string-keyed map and key array")
  expect_error(function() fingerprint.of_map_with_projection({[0] = 1}, {}) end,
    "requires a string-keyed map and key array")
  expect_error(function() fingerprint.of_map_with_projection({a = 1}, {[1] = "a", [3] = "a"}) end,
    "requires a string-keyed map and key array")
  expect_error(function() fingerprint.of_map_with_projection({a = 1}, {1}) end,
    "keys must be distinct existing strings")
  local guarded = {a = {inner = {[{}] = "unsupported key"}}}
  expect_error(function() fingerprint.of_map_with_projection(guarded, {"a"}) end,
    "map keys must be strings or numbers at $.a.inner")
  fingerprint.reset_metrics()
  fingerprint.of_map_with_projection({facts = string.rep("large", 20000), names = {"large"}, schema = 2}, {"facts", "names", "schema"})
  local projection_metrics = fingerprint.metrics()
  check(projection_metrics.map_projection_calls == 1 and projection_metrics.shared_projection_bytes > 100000,
    "shared projection work has bounded scalar telemetry")
  check(projection_metrics.hash_cache_entries <= 4096 and projection_metrics.hash_cache_bytes <= 2 * 1024 * 1024,
    "projection composition preserves existing digest cache bounds")
end

local length_fixture = {nested = {{[0] = "zero", [2] = "two"}, {quoted = escaped}}}
local canonical_length_fixture = fingerprint.canonical(length_fixture)
fingerprint.reset_metrics()
check(fingerprint.canonical_length(length_fixture) == #canonical_length_fixture,
  "counting canonical writer preserves exact mixed-key bytes")
local length_metrics = fingerprint.metrics()
check(length_metrics.canonical_calls == 1 and length_metrics.canonical_bytes == #canonical_length_fixture,
  "counting canonical writer remains visible as one canonicalization pass")
expect_error(function() fingerprint.canonical_length({nested = cyclic}) end,
  "cyclic table at $.nested.self")

local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local qualification_snapshot = compilation_snapshot.new({
  fact_domains = {
    recipes = {}, technologies = {}, items = {}, entities = {}, labs = {}, science_packs = {}
  },
  relationship_indexes = {}, owner_index = {}, graph_input = {}, effect_target_inventory = {},
  provider_inputs = {}, stream_inputs = {plan = {schema = 1, plan_fingerprint = "mir32-stream"}},
  base_continuation_inputs = {operations = {}}, source_fingerprints = {},
  structural_sharing = {reused_domains = {}, copied_domains = {"stream_inputs"}}, metrics = {}
})
check(compilation_snapshot.is_trusted(qualification_snapshot), "qualification snapshot is trusted")
local copied_qualification_snapshot = compilation_snapshot.snapshot(qualification_snapshot)
local expected_qualification_snapshot_bytes = #fingerprint.canonical(copied_qualification_snapshot)
local snapshot_metrics_before = require("prototypes.mir.core.trusted_record").metrics().CompilationSnapshot
local actual_qualification_snapshot_bytes = compilation_snapshot.snapshot_canonical_bytes(qualification_snapshot)
local snapshot_metrics_after = require("prototypes.mir.core.trusted_record").metrics().CompilationSnapshot
check(actual_qualification_snapshot_bytes == expected_qualification_snapshot_bytes,
  "qualification snapshot counting preserves the public projection byte count")
check(snapshot_metrics_after.explicit_snapshots == snapshot_metrics_before.explicit_snapshots
  and snapshot_metrics_after.full_copies == snapshot_metrics_before.full_copies,
  "qualification snapshot measurement does not create a defensive snapshot copy")

-- The recipes domain is a projection of the Context-owned full fact index.
-- Exercise the real ownership boundary here: exact current-index components
-- may reuse the paired scalar digest, while copies, replaced sources and
-- independent contexts must never share that authority.
do
  local loaded_names = {
    "prototypes.mir.platform.factorio.data_raw",
    "prototypes.mir.domain.facts.recipe_semantics",
    "prototypes.mir.platform.factorio.target_profiles",
    "prototypes.mir.report.compiler_telemetry",
    "prototypes.mir.platform.factorio.prototype_lookup",
    "prototypes.mir.index.relationships",
    "prototypes.mir.integrity.effect_contracts",
    "prototypes.mir.platform.factorio.effect_target_inventory",
    "prototypes.mir.capabilities.science_integration.pack_registry",
    "prototypes.mir.domain.compiler.execution_mode",
    "prototypes.mir.pipeline.compiler_context",
    "prototypes.mir.graph.snapshot",
    "prototypes.mir.index.recipe_facts",
    "prototypes.mir.pipeline.compilation_snapshot_adapter"
  }
  local saved = {}
  for _, name in ipairs(loaded_names) do saved[name] = package.loaded[name] end

  local recipes = {
    ["make-widget"] = {
      name = "make-widget", enabled = true, allow_productivity = true,
      ingredients = {{"ore", 1}}, results = {{type = "item", name = "widget", amount = 1}}
    }
  }
  local technologies = {
    automation = {enabled = true, unit = {ingredients = {{"automation-science-pack", 1}}}}
  }
  package.loaded["prototypes.mir.platform.factorio.data_raw"] = {
    prototypes = function(kind)
      if kind == "recipe" then return recipes end
      if kind == "technology" then return technologies end
      return {}
    end,
    technology = function(name) return technologies[name] end
  }
  package.loaded["prototypes.mir.domain.facts.recipe_semantics"] = {
    resolve = function()
      return {
        declared_allow_productivity = true, effective_allow_productivity = true,
        declared_allow_quality = nil, effective_allow_quality = true,
        declared_maximum_productivity = nil, effective_maximum_productivity = 3
      }
    end,
    maximum_base_result_amount = function(entry) return tonumber(entry.amount or entry[2]) or 1 end,
    productivity_excluded_amount = function() return 0 end,
    recipe_categories = function() return {"crafting"} end
  }
  package.loaded["prototypes.mir.platform.factorio.target_profiles"] = {
    current = function()
      return {
        prototype_shapes = {
          product_probability_fields = {"probability"},
          recipe_property_defaults = {allow_productivity = true, allow_quality = true, maximum_productivity = 3}
        }
      }
    end
  }
  package.loaded["prototypes.mir.report.compiler_telemetry"] = {
    count = function() end, observe_max = function() end, start_phase = function() end, finish_phase = function() end
  }
  package.loaded["prototypes.mir.platform.factorio.prototype_lookup"] = {
    item_prototype = function() return nil end,
    each_entity_prototype = function() end
  }
  package.loaded["prototypes.mir.index.relationships"] = {
    view = function()
      return {technologies_by_effect_identity = {}, technologies_by_recipe_effect = {}, items = {}}
    end
  }
  package.loaded["prototypes.mir.integrity.effect_contracts"] = {
    identity = function(effect) return tostring(effect.type or "") end
  }
  package.loaded["prototypes.mir.platform.factorio.effect_target_inventory"] = {
    capture = function() return {resolvers = {item = {}, entity = {}, ["space-location"] = {}}} end
  }
  package.loaded["prototypes.mir.capabilities.science_integration.pack_registry"] = {
    pack_list_all = function() return {} end,
    research_pack_prototype = function() return nil end,
    is_official_science_pack = function() return false end
  }
  package.loaded["prototypes.mir.index.recipe_facts"] = nil
  package.loaded["prototypes.mir.pipeline.compilation_snapshot_adapter"] = nil

  local compiler_context = require("prototypes.mir.pipeline.compiler_context")
  local recipe_facts = require("prototypes.mir.index.recipe_facts")
  local snapshot_adapter = require("prototypes.mir.pipeline.compilation_snapshot_adapter")
  local context_a, context_b = compiler_context.new(), compiler_context.new()
  local first = compiler_context.with_active(context_a, function()
    local index = recipe_facts.index_view()
    local full = recipe_facts.fingerprint()
    local component = recipe_facts.snapshot_recipe_domain_fingerprint(index)
    local projected = {facts = index.facts, names = index.names, schema = index.schema}
    check(full == fingerprint.of(index), "owned recipe index full digest preserves existing identity")
    check(component and component.fingerprint == fingerprint.of(projected),
      "owned recipe domain digest preserves its exact projection")
    check(component.canonical_bytes == #fingerprint.canonical(projected),
      "owned recipe domain reports exact canonical bytes")
    check(recipe_facts.snapshot_recipe_domain_fingerprint(deepcopy(index)) == nil,
      "copied recipe index cannot claim owned digest authority")
    local capture_metrics_before = require("prototypes.mir.core.trusted_record").metrics().CompilationSnapshot
    local captured = snapshot_adapter.capture()
    local capture_metrics_after = require("prototypes.mir.core.trusted_record").metrics().CompilationSnapshot
    check(captured.domain_fingerprints.recipes == component.fingerprint,
      "adapter reuses only the owned recipes-domain digest")
    check(captured.metrics.reused_recipe_canonical_bytes == component.canonical_bytes,
      "adapter reports exact reused recipe canonical bytes")
    check(capture_metrics_after.explicit_snapshots == capture_metrics_before.explicit_snapshots
        and capture_metrics_after.full_copies == capture_metrics_before.full_copies,
      "adapter byte telemetry does not request an observable snapshot copy")
    local public_captured_snapshot = compilation_snapshot.snapshot(captured)
    local captured_snapshot_bytes = public_captured_snapshot.metrics.snapshot_bytes
    public_captured_snapshot.metrics.snapshot_bytes = nil
    public_captured_snapshot.metrics.canonicalization_passes = public_captured_snapshot.metrics.canonicalization_passes - 1
    local expected_captured_snapshot_bytes = #fingerprint.canonical(public_captured_snapshot)
    check(captured_snapshot_bytes == expected_captured_snapshot_bytes,
      "adapter byte telemetry preserves the pre-metric public projection length")
    public_captured_snapshot.metrics.snapshot_bytes = -1
    check(captured.metrics.snapshot_bytes == expected_captured_snapshot_bytes,
      "public snapshot mutation cannot alter adapter byte telemetry")
    return {full = full, domain = component.fingerprint,
      index_epoch = context_a:state_epoch("recipe_index"),
      material_epoch = context_a:state_epoch("recipe_index_fingerprint_material"),
      full_epoch = context_a:state_epoch("recipe_index_fingerprint")}
  end)
  local second = compiler_context.with_active(context_b, function()
    local index = recipe_facts.index_view()
    return {full = recipe_facts.fingerprint(), domain = recipe_facts.snapshot_recipe_domain_fingerprint(index).fingerprint}
  end)
  check(first.full == second.full and first.domain == second.domain,
    "independent contexts begin with equivalent owned recipe identities")

  local replaced = compiler_context.with_active(context_a, function()
    local next_recipes = {
      ["make-advanced-widget"] = {
        name = "make-advanced-widget", enabled = true, allow_productivity = true,
        ingredients = {{"ore", 2}}, results = {{type = "item", name = "advanced-widget", amount = 1}}
      }
    }
    recipe_facts.replace_source(next_recipes, recipe_facts.source_epoch())
    local index = recipe_facts.index_view()
    local component = recipe_facts.snapshot_recipe_domain_fingerprint(index)
    return {
      full = recipe_facts.fingerprint(), domain = component.fingerprint,
      index_epoch = context_a:state_epoch("recipe_index"),
      material_epoch = context_a:state_epoch("recipe_index_fingerprint_material"),
      full_epoch = context_a:state_epoch("recipe_index_fingerprint")
    }
  end)
  check(replaced.full ~= first.full and replaced.domain ~= first.domain,
    "source replacement recomputes both full and projected recipe identities")
  check(replaced.index_epoch > first.index_epoch and replaced.material_epoch > first.material_epoch
      and replaced.full_epoch > first.full_epoch,
    "source replacement advances index and paired digest epochs together")
  local second_after = compiler_context.with_active(context_b, function()
    local index = recipe_facts.index_view()
    return {full = recipe_facts.fingerprint(), domain = recipe_facts.snapshot_recipe_domain_fingerprint(index).fingerprint}
  end)
  check(second_after.full == second.full and second_after.domain == second.domain,
    "recipe replacement in one context cannot alter another context's digest material")

  expect_error(function()
    compilation_snapshot.new({
      fact_domains = {
        recipes = {schema = 2, names = {"forged"}, facts = {}},
        technologies = {}, items = {}, entities = {}, labs = {}, science_packs = {}
      },
      domain_fingerprints = {recipes = "mir32-deadbeef"},
      relationship_indexes = {}, owner_index = {}, graph_input = {}, effect_target_inventory = {},
      provider_inputs = {}, stream_inputs = {}, base_continuation_inputs = {}, source_fingerprints = {},
      structural_sharing = {reused_domains = {}, copied_domains = {}}, metrics = {}
    })
  end, "CompilationSnapshot fact-domain fingerprint differs: recipes")

  for _, name in ipairs(loaded_names) do package.loaded[name] = saved[name] end
end


-- Private constructor-boundary control: final catalog validation accepts only
-- constructor-owned child records on its cheap path. This preserves the
-- complete catalog shape and fingerprints while rejecting forged lookalikes.
do
  local catalog_validate = require("prototypes.mir.planner.technology_catalog.validate")
  local normal_fingerprints = {
    candidate = catalog_deferred.candidate_catalog_fingerprint,
    qualification = catalog_deferred.qualification_catalog_fingerprint,
    preselection = catalog_deferred.preselection_catalog_fingerprint,
    selection = catalog_deferred.selection_fingerprint,
    catalog = catalog_deferred.catalog_fingerprint
  }
  check(catalog_validate.assert_newly_constructed(catalog_deferred),
    "constructor-owned final catalog remains accepted by the cheap ownership guard")
  check(catalog_deferred.candidate_catalog_fingerprint == normal_fingerprints.candidate
      and catalog_deferred.qualification_catalog_fingerprint == normal_fingerprints.qualification
      and catalog_deferred.preselection_catalog_fingerprint == normal_fingerprints.preselection
      and catalog_deferred.selection_fingerprint == normal_fingerprints.selection
      and catalog_deferred.catalog_fingerprint == normal_fingerprints.catalog,
    "cheap ownership guard preserves normal catalog fingerprint semantics")

  local function shallow_catalog(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
  end

  -- Full-looking candidate data copied out of the catalog has no registered
  -- identity. It must not be admitted by a caller-provided fast-path flag.
  local unowned = shallow_catalog(catalog_deferred)
  unowned.candidates = {deepcopy(catalog_deferred.candidates[1])}
  expect_error(function() catalog_validate.assert_newly_constructed(unowned) end,
    "Trusted TechnologyCandidate record is required")

  -- This is the compact schema-invalid selection record from the independent
  -- anchor experiment: sufficient for selection fields but not a Candidate.
  local original_candidate = catalog_deferred.candidates[1]
  local compact = shallow_catalog(catalog_deferred)
  compact.candidates = {{
    candidate_id = original_candidate.candidate_id,
    selection_key = original_candidate.selection_key,
    alternatives = original_candidate.alternatives,
    diagnostic_evaluation = original_candidate.diagnostic_evaluation
  }}
  expect_error(function() catalog_validate.assert_newly_constructed(compact) end,
    "Trusted TechnologyCandidate record is required")

  -- A registered candidate whose authority identity changes after construction
  -- also fails without entering a full fingerprint pass.
  local identity_mutated = shallow_catalog(catalog_deferred)
  local candidate = catalog_deferred.candidates[1]
  local candidate_id = candidate.candidate_id
  candidate.candidate_id = candidate_id .. "/forged"
  expect_error(function() catalog_validate.assert_newly_constructed(identity_mutated) end,
    "Trusted TechnologyCandidate record is required")
  candidate.candidate_id = candidate_id
  check(catalog_validate.assert_newly_constructed(catalog_deferred),
    "restored constructor-owned candidate remains valid after opposing identity control")

  -- A hard gate participates in final-resolution policy and must be owned too.
  -- Replacing only that registered child keeps its qualification otherwise valid.
  local qualification = catalog_deferred.qualifications[1]
  local gate_name = hard_gate_authority.order()[1]
  local original_gate = qualification.hard_gates[gate_name]
  qualification.hard_gates[gate_name] = deepcopy(original_gate)
  expect_error(function() catalog_validate.assert_newly_constructed(catalog_deferred) end,
    "Trusted TechnologyGate record is required")
  qualification.hard_gates[gate_name] = original_gate
  check(catalog_validate.assert_newly_constructed(catalog_deferred),
    "restored constructor-owned hard gate remains valid after opposing identity control")
end

-- The operation constructor is the ownership boundary for adopted native
-- research. Planner inputs may be reused without a second preparatory copy,
-- but neither those inputs nor an exported plan may mutate admitted output.
do
  local planner = require("prototypes.mir.planner.compiler")
  local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")
  local plan_contract = require("prototypes.mir.domain.compiler.transformation_plan")
  local policy = require("prototypes.mir.domain.compiler.policy_snapshot").new({})
  local adopted = catalog_adopt_row("ownership-boundary")
  adopted.adoption.input_snapshot = deepcopy(adopted.adoption.expected_snapshot)
  adopted.adoption.input_snapshot.unit.count_formula = "50*L"
  adopted.adoption.input_fingerprint = fingerprint.of(adopted.adoption.input_snapshot)
  adopted.adoption.configured_fields = {"effects", "unit"}
  adopted.technology_design = technology_design.from_generation_row(adopted)
  local created = catalog_emit_row("ownership-create")
  local snapshot = compilation_snapshot.new({
    stream_inputs = {rows = {adopted, created}}, base_continuation_inputs = {operations = {}}
  })
  local expected_adoption = fingerprint.canonical(adopted.adoption)
  local expected_before = fingerprint.canonical(adopted.adoption.input_snapshot)
  local expected_after = fingerprint.canonical(adopted.adoption.expected_snapshot)
  local compiled = planner.compile(snapshot, policy)
  local plan = compiled.transformation_plan
  check(#plan.operations == 2 and plan.operation_counts.patch == 1 and plan.operation_counts.create == 1,
    "actual planner preserves both adopted and newly generated operations")
  local operation
  for _, candidate in ipairs(plan.operations) do
    if candidate.action == "patch" then operation = candidate end
  end
  check(operation and fingerprint.canonical(operation.expected_before_snapshot) == expected_before
      and fingerprint.canonical(operation.expected_after_projection) == expected_after
      and fingerprint.canonical(operation.payload.adoption) == expected_adoption,
    "adoption constructor preserves complete snapshots and payload")
  check(operation.expected_before_snapshot ~= adopted.adoption.input_snapshot
      and operation.expected_after_projection ~= adopted.adoption.expected_snapshot
      and operation.payload.adoption ~= adopted.adoption,
    "constructor owns independent adoption tables")
  local original_plan = fingerprint.canonical(plan_contract.snapshot(plan))
  local original_operation_fingerprint = operation.operation_fingerprint
  local original_plan_fingerprint = plan.plan_fingerprint
  adopted.adoption.input_snapshot.unit.ingredients[1][2] = 999
  adopted.adoption.expected_snapshot.effects[1].change = 999
  adopted.adoption.configured_fields[1] = "forged-field"
  check(fingerprint.canonical(operation.expected_before_snapshot) == expected_before
      and fingerprint.canonical(operation.expected_after_projection) == expected_after
      and fingerprint.canonical(operation.payload.adoption) == expected_adoption,
    "nested source mutation cannot alter admitted adoption")
  check(operation_contract.verify_untrusted(operation) and operation_contract.assert_trusted(operation)
      and operation.operation_fingerprint == original_operation_fingerprint,
    "source mutation preserves valid operation fingerprint and trust")
  check(fingerprint.canonical(plan_contract.snapshot(plan)) == original_plan
      and plan.plan_fingerprint == original_plan_fingerprint,
    "source mutation preserves complete plan bytes and fingerprint")
  local exported = plan_contract.snapshot(plan)
  for _, candidate in ipairs(exported.operations) do
    if candidate.action == "patch" then
      candidate.expected_before_snapshot.unit.ingredients[1][2] = 1000
      candidate.expected_after_projection.effects[1].change = 1000
      candidate.payload.adoption.configured_fields[1] = "forged-export"
    end
  end
  check(fingerprint.canonical(plan_contract.snapshot(plan)) == original_plan,
    "nested exported-plan mutation cannot alter owned adoption")
end

print("MIR-TECHNOLOGY-DESIGN-CHARACTERIZATION-PASS " .. assertions)

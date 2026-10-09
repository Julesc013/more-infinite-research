local deepcopy = require("prototypes.mir.core.deepcopy")
local gate = require("prototypes.mir.domain.technology.gate")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

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

print("MIR-TECHNOLOGY-DESIGN-CHARACTERIZATION-PASS " .. assertions)

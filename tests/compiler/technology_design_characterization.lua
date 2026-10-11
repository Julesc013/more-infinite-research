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
    local captured = snapshot_adapter.capture()
    check(captured.domain_fingerprints.recipes == component.fingerprint,
      "adapter reuses only the owned recipes-domain digest")
    check(captured.metrics.reused_recipe_canonical_bytes == component.canonical_bytes,
      "adapter reports exact reused recipe canonical bytes")
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

print("MIR-TECHNOLOGY-DESIGN-CHARACTERIZATION-PASS " .. assertions)

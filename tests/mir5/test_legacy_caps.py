"""Pure Lua 5.2 controls for the bounded MIR4-to-MIR5 cap-right decoder."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LegacyCapsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          legacy = require("runtime.legacy_caps")

          function candidate(name, setting, source, operation, admitted)
            return {name = name, setting = setting, source = source,
              operation = operation, admitted = admitted ~= false}
          end

          function cap_key(candidate)
            return table.concat({candidate.name, candidate.setting, candidate.source,
              candidate.operation}, "\\0")
          end

          function policy_for(candidate, cap, fingerprint)
            return {technology = candidate.name, setting = candidate.setting,
              source = candidate.source, operation = candidate.operation,
              policy_transport = "transported-v3", ownership_kind = "transported-v3",
              legacy = false, selected = cap, binding_fingerprint = fingerprint}
          end

          function visibility_for(index, candidate, value)
            return {policy_version = 3, force_index = index, ownership_key = cap_key(candidate),
              ownership_kind = "transported-v3", value = value}
          end

          function disabled_for(index, candidate, cap, fingerprint)
            return {policy_version = 3, force_index = index, cap = cap,
              binding_fingerprint = fingerprint, ownership_key = cap_key(candidate),
              ownership_kind = "transported-v3", enabled_before_cap = true}
          end

          function old_bucket(index, candidate, cap, fingerprint, disable)
            local row = {policy_version = 3,
              managed_technologies = {[candidate.name] = policy_for(candidate, cap, fingerprint)},
              visibility_by_cap = {[index] = {[candidate.name] = visibility_for(index, candidate, false)}},
              disabled_by_cap = {[index] = {}}, unowned_disabled_by_cap = {[index] = {}}
            }
            if disable ~= false then
              row.disabled_by_cap[index][candidate.name] = disabled_for(index, candidate, cap, fingerprint)
            end
            return row
          end

          function native_force(index, technologies)
            local value = {valid = true, index = index, technologies = technologies}
            return setmetatable(value, {__newindex = function()
              error("legacy decoder must not mutate a force")
            end})
          end

          function native_technology(enabled)
            local value = {enabled = enabled == true, visible_when_disabled = true,
              level = 11, researched = true, saved_progress = .42}
            return setmetatable(value, {__newindex = function()
              error("legacy decoder must not mutate a technology")
            end})
          end
        ''')

    def test_imports_exact_paired_gear_disable_without_mutating_native_state(self):
        self.lua.execute('''
          -- Exact accepted 4.7.21000 F210 provenance: archive member
          -- `prototypes/mir/domain/technology/maximum_level_binding.lua`
          -- lines 264-277 emits this generated technology with operation=emit.
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local technology = native_technology()
          local f = native_force(4, {[gear.name] = technology})
          local old = old_bucket(4, gear, 10, "mir32-1a2b3c4d")
          local rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(facts.legacy_policy3 and facts.candidates_checked == 1 and facts.imported == 1)
          assert(facts.decisions[1].outcome == "owned_disable_imported")
          assert(rows[gear.name].disabled and rows[gear.name].visible_when_disabled == false)
          rows[gear.name].visible_when_disabled = true
          assert(old.visibility_by_cap[4][gear.name].value == false,
            "output retained a mutable legacy row")
          assert(technology.enabled == false and technology.visible_when_disabled == true
            and technology.level == 11 and technology.researched and technology.saved_progress == .42)
        ''')

    def test_rejects_the_former_runtime_settings_transport_tuple_for_published_gear_state(self):
        self.lua.execute('''
          -- The archive-backed `emit` tuple is exact. Do not admit the prior
          -- synthetic runtime-settings-transport tuple as an alternate key.
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local f = native_force(41, {[gear.name] = native_technology()})
          local old = old_bucket(41, gear, 2, "mir32-1a2b3c4d")
          local former = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "runtime-settings-transport")
          local rows, facts = legacy.import_for_force(old, f, {former}, nil)
          assert(rows[gear.name] == nil and facts.imported == 0)
          assert(facts.decisions[1].outcome == "candidate_not_admitted")
        ''')

    def test_imports_worker_only_when_the_revalidated_candidate_is_supplied(self):
        self.lua.execute('''
          local worker = candidate("worker-robots-speed-6", "mir-max-level-worker-robots-speed",
            "native-owner", "native-owner-cap")
          local technology = native_technology()
          local f = native_force(5, {[worker.name] = technology})
          local old = old_bucket(5, worker, 2, "mir32-5e6f7a8b")
          local rows, facts = legacy.import_for_force(old, f, {worker}, nil)
          assert(rows[worker.name].disabled and facts.decisions[1].outcome == "owned_disable_imported")
          worker.admitted = false
          rows, facts = legacy.import_for_force(old, f, {worker}, nil)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")
        ''')

    def test_imports_only_the_exact_published_direct_stream_tuples(self):
        self.lua.execute('''
          local candidates = {
            candidate("recipe-prod-research_agricultural_growth_speed-1",
              "ips-max-level-research_agricultural_growth_speed", "generated-stream", "emit"),
            candidate("recipe-prod-research_spoilage_preservation-1",
              "ips-max-level-research_spoilage_preservation", "generated-stream", "emit")
          }
          for index, direct in ipairs(candidates) do
            local f = native_force(50 + index, {[direct.name] = native_technology()})
            local old = old_bucket(50 + index, direct, 2, "mir32-1234abcd")
            local rows, facts = legacy.import_for_force(old, f, {direct}, nil)
            assert(rows[direct.name].disabled and rows[direct.name].visible_when_disabled == false)
            assert(facts.decisions[1].outcome == "owned_disable_imported")

            local foreign = candidate(direct.name, direct.setting, "native-owner", "emit")
            rows, facts = legacy.import_for_force(old, f, {foreign}, nil)
            assert(rows[direct.name] == nil and facts.imported == 0)
            assert(facts.decisions[1].outcome == "candidate_not_admitted")
          end
        ''')

    def test_visibility_only_preserves_a_foreign_disable_and_current_rows_win(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local f = native_force(6, {[gear.name] = native_technology()})
          local old = old_bucket(6, gear, 3, "mir32-0a1b2c3d", false)
          local rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_only_imported")
          rows, facts = legacy.import_for_force(old, f, {gear}, {[gear.name] = {disabled = true}})
          assert(rows[gear.name] == nil and facts.imported == 0)
          assert(facts.decisions[1].outcome == "current_mir5_ownership_retained")
        ''')

    def test_any_non_nil_current_entry_blocks_historical_restoration(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local f = native_force(61, {[gear.name] = native_technology()})
          local old = old_bucket(61, gear, 3, "mir32-0a1b2c3d")
          local values = {false, "preserved-tombstone", 7}
          for index = 1, 3 do
            local rows, facts = legacy.import_for_force(old, f, {gear}, {
              [gear.name] = values[index]
            })
            assert(rows[gear.name] == nil and facts.imported == 0)
            assert(facts.decisions[1].outcome == "current_mir5_ownership_retained")
          end
        ''')

    def test_visibility_is_independent_of_malformed_disable_v2_continuity_and_reenablement(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local f = native_force(7, {[gear.name] = native_technology()})
          local old = old_bucket(7, gear, 4, "mir32-1234abcd")
          old.disabled_by_cap[7][gear.name].binding_fingerprint = "mir32-deadbeef"
          local rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_imported_disable_unproven")
          old = old_bucket(7, gear, 4, "mir32-1234abcd")
          old.visibility_by_cap[7][gear.name] = false
          rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "visibility_record_mismatch")
          old = old_bucket(7, gear, 4, "mir32-1234abcd")
          old.visibility_by_cap[7][gear.name] = nil
          rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "visibility_record_mismatch")
          old = old_bucket(7, gear, 4, "mir32-1234abcd")
          old.disabled_by_cap[7][gear.name] = true
          rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name].disabled == nil
            and facts.decisions[1].outcome == "visibility_imported_disable_unproven")
          old = old_bucket(7, gear, 4, "mir32-1234abcd")
          old.managed_technologies[gear.name].binding_fingerprint = "not-a-published-fingerprint"
          rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          old = old_bucket(7, gear, 4, "mir32-1234abcd")
          old.unowned_disabled_by_cap[7][gear.name] = {
            policy_version = 3, force_index = 7, enabled_before_cap = false,
            migrated_from_policy_version = 2
          }
          rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_imported_unowned_disable_excluded")
          f = native_force(7, {[gear.name] = native_technology(true)})
          old = old_bucket(7, gear, 4, "mir32-1234abcd")
          rows, facts = legacy.import_for_force(old, f, {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_imported_enablement_reenabled")
        ''')

    def test_uses_only_four_declared_candidates_and_does_not_enumerate_legacy_maps(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local agriculture = candidate("recipe-prod-research_agricultural_growth_speed-1",
            "ips-max-level-research_agricultural_growth_speed", "generated-stream", "emit")
          local spoilage = candidate("recipe-prod-research_spoilage_preservation-1",
            "ips-max-level-research_spoilage_preservation", "generated-stream", "emit")
          local worker = candidate("worker-robots-speed-7", "mir-max-level-worker-robots-speed",
            "native-owner", "native-owner-cap")
          local reads = 0
          local old = setmetatable({policy_version = 3}, {__index = function(_, key)
            reads = reads + 1
            if key == "managed_technologies" then return {} end
            if key == "disabled_by_cap" or key == "visibility_by_cap" or key == "unowned_disabled_by_cap" then
              return {}
            end
            error("unexpected legacy field " .. tostring(key))
          end, __pairs = function() error("legacy maps must not be enumerated") end})
          local f = native_force(8, {})
          local rows, facts = legacy.import_for_force(old, f, {gear, agriculture, spoilage, worker}, nil)
          assert(next(rows) == nil and facts.candidates_checked == 4 and #facts.decisions == 4)
          assert(reads <= 4)
          local ok = pcall(function()
            legacy.import_for_force(old, f, {gear, agriculture, spoilage, worker, gear}, nil)
          end)
          assert(not ok, "fifth candidate was accepted")
        ''')

    def test_source_has_no_old_runtime_import_or_mutating_assignment(self):
        source = (ROOT / "source/mir5/runtime/legacy_caps.lua").read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("storage[", source)
        self.assertNotIn("global[", source)
        self.assertNotIn(".enabled =", source)
        self.assertNotIn(".visible_when_disabled =", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyCapsTests))
    sys.exit(0 if result.wasSuccessful() else 1)

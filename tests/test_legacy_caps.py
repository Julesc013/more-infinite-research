"""Pure Lua 5.2 controls for the bounded MIR4-to-MIR5 cap-right decoder."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LegacyCapsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          legacy = require("runtime.legacy_caps")

          -- The runtime builds this exact catalogue-derived allowlist once at
          -- control parse. Keep the pure decoder tests independent of runtime
          -- storage while preserving the same strict boundary.
          local direct_allowlist = legacy.allowlist({
            {id = "recipe-prod-research_gears-1", cap_setting = "ips-max-level-research_gears",
              legacy_binding = {source = "generated-stream", operation = "emit"}},
            {id = "recipe-prod-research_agricultural_growth_speed-1",
              cap_setting = "ips-max-level-research_agricultural_growth_speed",
              legacy_binding = {source = "generated-stream", operation = "emit"}},
            {id = "recipe-prod-research_spoilage_preservation-1",
              cap_setting = "ips-max-level-research_spoilage_preservation",
              legacy_binding = {source = "generated-stream", operation = "emit"}}
          })
          V1_ALLOWLIST = legacy.allowlist({
            {id = "recipe-prod-research_gears-1", cap_setting = "ips-max-level-research_gears",
              legacy_binding = {source = "generated-stream", operation = "emit"}},
            {id = "braking-force-8", cap_setting = "mir-max-level-braking-force",
              legacy_binding = {source = "base-continuation", operation = "emit_base_extension"}}
          })
          F200_ALLOWLIST = legacy.allowlist({
            {id = "recipe-prod-research_gears-1", cap_setting = "ips-max-level-research_gears",
              legacy_binding = {source = "generated-stream", operation = "runtime-settings-transport",
                target = "f200", policy_transport = "settings-derived-v3",
                ownership_kind = "settings-derived-v3"}}
          }, "f200")
          F200_DIRECT_HOP_ALLOWLIST = legacy.f200_direct_hop_allowlist({
            {id = "recipe-prod-research_gears-1", cap_setting = "ips-max-level-research_gears",
              ownership_kind = "authored_generated",
              legacy_binding = {source = "generated-stream", operation = "emit"}},
            {id = "braking-force-8", cap_setting = "mir-max-level-braking-force",
              ownership_kind = "authored_generated",
              legacy_binding = {source = "base-continuation", operation = "emit_base_extension"}},
            {id = "foreign-generated", cap_setting = "ips-max-level-foreign",
              ownership_kind = "authored_generated",
              legacy_binding = {source = "generated-stream", operation = "foreign-operation"}}
          })
          F200_WORKER_ALLOWLIST = legacy.allowlist({}, "f200")
          F210_WORKER_ALLOWLIST = legacy.allowlist({}, "f210")
          local raw_import_for_force = legacy.import_for_force
          function legacy.import_for_force(bucket, force, candidates, current, allowlist)
            return raw_import_for_force(bucket, force, candidates, current, allowlist or direct_allowlist)
          end
          local raw_import_boolean_for_force = legacy.import_boolean_for_force
          function legacy.import_boolean_for_force(bucket, force, candidates, current, allowlist)
            return raw_import_boolean_for_force(bucket, force, candidates, current, allowlist or V1_ALLOWLIST)
          end

          function candidate(name, setting, source, operation, admitted)
            return {name = name, setting = setting, source = source,
              operation = operation, admitted = admitted ~= false}
          end

          function cap_key(candidate)
            return table.concat({candidate.name, candidate.setting, candidate.source,
              candidate.operation}, "\\0")
          end

          function policy_for(candidate, cap, fingerprint, kind)
            kind = kind or "transported-v3"
            return {technology = candidate.name, setting = candidate.setting,
              source = candidate.source, operation = candidate.operation,
              policy_transport = kind, ownership_kind = kind,
              legacy = false, selected = cap, binding_fingerprint = fingerprint}
          end

          function visibility_for(index, candidate, value, kind)
            kind = kind or "transported-v3"
            return {policy_version = 3, force_index = index, ownership_key = cap_key(candidate),
              ownership_kind = kind, value = value}
          end

          function disabled_for(index, candidate, cap, fingerprint, kind)
            kind = kind or "transported-v3"
            return {policy_version = 3, force_index = index, cap = cap,
              binding_fingerprint = fingerprint, ownership_key = cap_key(candidate),
              ownership_kind = kind, enabled_before_cap = true}
          end

          function old_bucket(index, candidate, cap, fingerprint, disable, kind)
            local row = {policy_version = 3,
              managed_technologies = {[candidate.name] = policy_for(candidate, cap, fingerprint, kind)},
              visibility_by_cap = {[index] = {[candidate.name] = visibility_for(index, candidate, false, kind)}},
              disabled_by_cap = {[index] = {}}, unowned_disabled_by_cap = {[index] = {}}
            }
            if disable ~= false then
              row.disabled_by_cap[index][candidate.name] = disabled_for(index, candidate, cap, fingerprint, kind)
            end
            if kind == "settings-derived-v3" then
              -- Accepted F3943E...1010B7 maximum_level_control.lua:109-133,
              -- 414-421, 668-675, 862-878: map-key identity, absent digest.
              local policy = row.managed_technologies[candidate.name]
              policy.technology, policy.binding_fingerprint = nil, nil
              policy.native_finite_stage = false
              local key = table.concat({"nil", candidate.setting, candidate.source, candidate.operation}, "\\0")
              row.visibility_by_cap[index][candidate.name].ownership_key = key
              local disabled = row.disabled_by_cap[index][candidate.name]
              if disabled then disabled.ownership_key, disabled.binding_fingerprint = key, nil end
            end
            return row
          end

          function boolean_bucket(index, candidate, cap, disable, visibility)
            local row = {policy_version = 1,
              managed_technologies = {[candidate.name] = {
                source = candidate.source, operation = candidate.operation,
                setting = candidate.setting, selected = cap
              }},
              disabled_by_cap = {[index] = {}}, unowned_disabled_by_cap = {[index] = {}}
            }
            if disable ~= false then row.disabled_by_cap[index][candidate.name] = true end
            if visibility ~= nil then
              row.visibility_by_cap = {[index] = {[candidate.name] = visibility}}
            end
            return row
          end

          function native_force(index, technologies)
            local value = {valid = true, index = index, technologies = technologies}
            return setmetatable(value, {__newindex = function()
              error("legacy decoder must not mutate a force")
            end})
          end

          function native_technology(enabled, visible)
            local value = {enabled = enabled == true, visible_when_disabled = visible ~= false,
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

    def test_imports_only_the_published_f200_settings_derived_gear_tuple(self):
        self.lua.execute('''
          -- Published F200 4.7.20002 `maximum_level_control.lua:109-146`
          -- used the settings-derived V3 runtime-settings transport.  This
          -- remains separate from the emitted F210 binding tested above.
          local f200 = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "runtime-settings-transport")
          local f = native_force(41, {[f200.name] = native_technology()})
          local old = old_bucket(41, f200, 2, "mir32-1a2b3c4d", nil, "settings-derived-v3")
          local rows, facts = legacy.import_for_force(old, f, {f200}, nil, F200_ALLOWLIST)
          assert(rows[f200.name].disabled and rows[f200.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "owned_disable_imported")

          -- The direct-hop map is deliberately a separate exact F200 tuple
          -- constructed from a current authored F210 successor.  Selecting it
          -- is lifecycle's event-gated responsibility; generic F210 remains
          -- transported-only below.
          assert(legacy.f200_direct_hop_candidate({id = "foreign-native-owner",
            cap_setting = "ips-max-level-foreign", ownership_kind = "nativeowner",
            legacy_binding = {source = "generated-stream", operation = "emit"}}) == nil,
            "a native owner gained the generated predecessor tuple")
          rows, facts = legacy.import_for_force(old, f, {f200}, nil, F200_DIRECT_HOP_ALLOWLIST)
          assert(rows[f200.name].disabled and facts.decisions[1].outcome == "owned_disable_imported")
          local foreign = candidate("foreign-generated", "ips-max-level-foreign",
            "generated-stream", "runtime-settings-transport")
          rows, facts = legacy.import_for_force(old, f, {foreign}, nil, F200_DIRECT_HOP_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")

          -- F210's archive-backed `emit` admission cannot accept the F200
          -- policy form merely because the name and setting happen to match.
          local f210 = candidate(f200.name, f200.setting, "generated-stream", "emit")
          rows, facts = legacy.import_for_force(old, f, {f210}, nil, direct_allowlist)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "policy_mismatch")

          local wrong_operation = candidate(f200.name, f200.setting, "generated-stream", "emit")
          rows, facts = legacy.import_for_force(old, f, {wrong_operation}, nil, F200_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")
          local wrong_source = candidate(f200.name, f200.setting, "native-owner", "runtime-settings-transport")
          rows, facts = legacy.import_for_force(old, f, {wrong_source}, nil, F200_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")
          local wrong_setting = candidate(f200.name, "ips-max-level-research_iron", "generated-stream", "runtime-settings-transport")
          rows, facts = legacy.import_for_force(old, f, {wrong_setting}, nil, F200_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")

          local zero_cap = old_bucket(41, f200, 0, "mir32-1a2b3c4d", nil, "settings-derived-v3")
          rows, facts = legacy.import_for_force(zero_cap, f, {f200}, nil, F200_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          local wrong_kind = old_bucket(41, f200, 2, "mir32-1a2b3c4d", nil, "transported-v3")
          rows, facts = legacy.import_for_force(wrong_kind, f, {f200}, nil, F200_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          local wrong_old_cap = old_bucket(41, f200, 2, "mir32-1a2b3c4d", nil, "settings-derived-v3")
          wrong_old_cap.disabled_by_cap[41][f200.name].cap = 3
          rows, facts = legacy.import_for_force(wrong_old_cap, f, {f200}, nil, F200_ALLOWLIST)
          assert(rows[f200.name].disabled == nil
            and facts.decisions[1].outcome == "visibility_imported_disable_unproven")
          local invented_fingerprint = old_bucket(41, f200, 2, nil, nil, "settings-derived-v3")
          invented_fingerprint.managed_technologies[f200.name].binding_fingerprint = "mir32-1a2b3c4d"
          rows, facts = legacy.import_for_force(invented_fingerprint, f, {f200}, nil, F200_ALLOWLIST)
          assert(rows[f200.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
        ''')

    def test_f200_shape_rejects_invented_identity_stale_records_and_foreign_writes(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "runtime-settings-transport")
          local cases = {
            {function(p,v,d,b,t) p.technology=gear.name end, "none"},
            {function(p,v,d,b,t) p.binding_fingerprint="mir32-1234abcd" end, "none"},
            {function(p,v,d,b,t) p.native_finite_stage=nil end, "none"},
            {function(p,v,d,b,t) p.native_finite_stage="false" end, "none"},
            {function(p,v,d,b,t) p.source="native-owner" end, "none"},
            {function(p,v,d,b,t) p.operation="emit" end, "none"},
            {function(p,v,d,b,t) p.setting="ips-max-level-research_iron" end, "none"},
            {function(p,v,d,b,t) v.ownership_key=cap_key(gear) end, "none"},
            {function(p,v,d,b,t) v.force_index=42 end, "none"},
            {function(p,v,d,b,t) t.visible_when_disabled=false end, "none"},
            {function(p,v,d,b,t) d.binding_fingerprint="mir32-1234abcd" end, "visibility"},
            {function(p,v,d,b,t) d.ownership_key=cap_key(gear) end, "visibility"},
            {function(p,v,d,b,t) d.force_index=42 end, "visibility"},
            {function(p,v,d,b,t) d.enabled_before_cap=false end, "visibility"},
            {function(p,v,d,b,t) d.migrated_from_policy_version=2 end, "visibility"},
            {function(p,v,d,b,t) b.unowned_disabled_by_cap[41][gear.name]=true end, "visibility"},
            {function(p,v,d,b,t) t.enabled=true end, "visibility"}
          }
          for index, opponent in ipairs(cases) do
            local old=old_bucket(41,gear,2,nil,nil,"settings-derived-v3")
            local t=native_technology()
            opponent[1](old.managed_technologies[gear.name],old.visibility_by_cap[41][gear.name],
              old.disabled_by_cap[41][gear.name],old,t)
            local rows=legacy.import_for_force(old,native_force(41,{[gear.name]=t}),{gear},nil,F200_ALLOWLIST)
            if opponent[2]=="none" then assert(rows[gear.name]==nil,"F200 opponent admitted: "..index)
            else assert(rows[gear.name] and rows[gear.name].disabled==nil
              and rows[gear.name].visible_when_disabled==false,"F200 foreign disable claimed: "..index) end
          end
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

    def test_imports_only_the_published_f200_settings_derived_worker_tuple(self):
        self.lua.execute('''
          -- Published F200 4.7.20002 maximum_level_control's native worker
          -- tail used this settings-derived V3 tuple.  The caller's package
          -- target, never this saved bucket, selects that authority.
          local worker = candidate("worker-robots-speed-6", "mir-max-level-worker-robots-speed",
            "native-owner", "native-owner-cap")
          local f = native_force(61, {[worker.name] = native_technology()})
          local old = old_bucket(61, worker, 2, "mir32-5e6f7a8b", nil, "settings-derived-v3")
          local rows, facts = legacy.import_for_force(old, f, {worker}, nil, F200_WORKER_ALLOWLIST)
          assert(rows[worker.name].disabled and rows[worker.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "owned_disable_imported")

          -- The same persisted policy cannot select F200 authority in a
          -- different package.  F210 keeps only the transported V3 worker
          -- form even though the current native candidate is otherwise exact.
          rows, facts = legacy.import_for_force(old, f, {worker}, nil, F210_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "policy_mismatch")

          local wrong_operation = candidate(worker.name, worker.setting, "native-owner", "emit")
          rows, facts = legacy.import_for_force(old, f, {wrong_operation}, nil, F200_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")
          local wrong_source = candidate(worker.name, worker.setting, "generated-stream", "native-owner-cap")
          rows, facts = legacy.import_for_force(old, f, {wrong_source}, nil, F200_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")
          local unknown_tail = candidate("worker-robots-speed-8", worker.setting,
            "native-owner", "native-owner-cap")
          rows, facts = legacy.import_for_force(old, f, {unknown_tail}, nil, F200_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")

          local wrong_kind = old_bucket(61, worker, 2, "mir32-5e6f7a8b", nil, "transported-v3")
          rows, facts = legacy.import_for_force(wrong_kind, f, {worker}, nil, F200_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          local wrong_fingerprint = old_bucket(61, worker, 2, "mir32-5E6f7a8b", nil,
            "settings-derived-v3")
          wrong_fingerprint.managed_technologies[worker.name].binding_fingerprint = "mir32-5E6f7a8b"
          rows, facts = legacy.import_for_force(wrong_fingerprint, f, {worker}, nil,
            F200_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
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

    def test_uses_bounded_declared_candidates_and_does_not_enumerate_legacy_maps(self):
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
          local oversized = {}
          for index = 1, 129 do oversized[index] = gear end
          local ok = pcall(function() legacy.import_for_force(old, f, oversized, nil) end)
          assert(not ok, "candidate bound was not enforced")
        ''')

    def test_imports_schema1_boolean_rights_with_and_without_a_visibility_snapshot(self):
        self.lua.execute('''
          -- Published 3.2.11 and the released F200/F210 4.0/4.1 ZIPs use
          -- policy_version=1 and this exact boolean marker shape.
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local technology = native_technology(false, true)
          local old = boolean_bucket(14, gear, 3, true, false)
          local rows, facts = legacy.import_boolean_for_force(old,
            native_force(14, {[gear.name] = technology}), {gear}, nil)
          assert(facts.legacy_policy1 and facts.candidates_checked == 1 and facts.imported == 1)
          assert(facts.decisions[1].outcome == "owned_disable_imported")
          assert(rows[gear.name].disabled and rows[gear.name].visible_when_disabled == false)
          rows[gear.name].visible_when_disabled = true
          assert(old.visibility_by_cap[14][gear.name] == false,
            "boolean output retained a mutable saved visibility value")
          assert(technology.enabled == false and technology.visible_when_disabled == true
            and technology.level == 11 and technology.researched and technology.saved_progress == .42)

          -- Earlier V1 bodies had no visibility map.  They can prove the
          -- disable right but cannot manufacture a visibility restoration.
          old = boolean_bucket(14, gear, 3, true, nil)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(14, {[gear.name] = native_technology(false, false)}), {gear}, nil)
          assert(rows[gear.name].disabled and rows[gear.name].visible_when_disabled == nil)
          assert(facts.decisions[1].outcome == "owned_disable_imported")
        ''')

    def test_schema1_keeps_foreign_and_changed_enablement_separate_from_visibility(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local old = boolean_bucket(18, gear, 3, true, false)
          old.unowned_disabled_by_cap[18][gear.name] = true
          local rows, facts = legacy.import_boolean_for_force(old,
            native_force(18, {[gear.name] = native_technology(false, true)}), {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_imported_unowned_disable_excluded")

          old = boolean_bucket(18, gear, 3, true, false)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(18, {[gear.name] = native_technology(true, true)}), {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_imported_enablement_reenabled")

          old = boolean_bucket(18, gear, 3, false, false)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(18, {[gear.name] = native_technology(false, false)}), {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "visibility_state_changed")

          old = boolean_bucket(18, gear, 3, true, false)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(18, {[gear.name] = native_technology(false, true)}), {gear}, {
              [gear.name] = {disabled = true}
            })
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "current_mir5_ownership_retained")
        ''')

    def test_schema1_accepts_only_actual_producer_tuple_shapes_and_boolean_markers(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local force = native_force(23, {[gear.name] = native_technology(false, true)})
          local old = boolean_bucket(23, gear, 4, true, false)
          old.managed_technologies[gear.name].setting = "ips-max-level-research_iron"
          local rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "policy_mismatch")

          old = boolean_bucket(23, gear, 0, true, false)
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          old = boolean_bucket(23, gear, 4, true, false)
          old.managed_technologies[gear.name].blocked_reason = "late_prototype_mutation"
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "policy_mismatch")

          old = boolean_bucket(23, gear, 4, true, false)
          old.disabled_by_cap[23][gear.name] = {enabled_before_cap = true}
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name].disabled == nil and rows[gear.name].visible_when_disabled == false)
          assert(facts.decisions[1].outcome == "visibility_imported_disable_unproven")

          old = boolean_bucket(23, gear, 4, true, false)
          old.visibility_by_cap[23][gear.name] = {value = false}
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "visibility_record_mismatch")

          local worker = candidate("worker-robots-speed-6", "mir-max-level-worker-robots-speed",
            "native-owner", "native-owner-cap")
          old = boolean_bucket(23, worker, 4, true, false)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(23, {[worker.name] = native_technology(false, true)}), {worker}, nil,
            F200_WORKER_ALLOWLIST)
          assert(rows[worker.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")

          local invalid_operation = candidate(gear.name, gear.setting,
            "generated-stream", "foreign-operation")
          old = boolean_bucket(23, invalid_operation, 4, true, false)
          rows, facts = legacy.import_boolean_for_force(old, force, {invalid_operation}, nil,
            V1_ALLOWLIST)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "candidate_not_admitted")

          -- Both real V1 producer forms remain bounded: the compiled base
          -- continuation and the no-mod-data runtime transport fallback.
          local braking = candidate("braking-force-8", "mir-max-level-braking-force",
            "base-continuation", "emit_base_extension")
          old = boolean_bucket(23, braking, 2, true, nil)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(23, {[braking.name] = native_technology(false, false)}), {braking}, nil)
          assert(rows[braking.name].disabled and facts.decisions[1].outcome == "owned_disable_imported")

          local fallback = candidate(gear.name, gear.setting,
            "generated-stream", "runtime-settings-transport")
          old = boolean_bucket(23, fallback, 4, true, false)
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(23, {[fallback.name] = native_technology(false, true)}), {fallback}, nil,
            F200_ALLOWLIST)
          assert(rows[fallback.name].disabled and facts.decisions[1].outcome == "owned_disable_imported")

          -- A V1 source could use its no-mod-data fallback before a current
          -- F210 planned binding, and vice versa for F200.  The operation is
          -- a bounded historical producer detail, not a different identity.
          old = boolean_bucket(23, gear, 4, true, false)
          old.managed_technologies[gear.name].operation = "runtime-settings-transport"
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name].disabled and facts.decisions[1].outcome == "owned_disable_imported")
          old = boolean_bucket(23, fallback, 4, true, false)
          old.managed_technologies[fallback.name].operation = "emit"
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(23, {[fallback.name] = native_technology(false, true)}), {fallback}, nil,
            F200_ALLOWLIST)
          assert(rows[fallback.name].disabled and facts.decisions[1].outcome == "owned_disable_imported")

          -- Equivalence is source-class-specific: an operation from the other
          -- class, or an unknown operation, cannot create a historical right.
          old = boolean_bucket(23, gear, 4, true, false)
          old.managed_technologies[gear.name].operation = "emit_base_extension"
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          old = boolean_bucket(23, braking, 2, true, nil)
          old.managed_technologies[braking.name].operation = "emit"
          rows, facts = legacy.import_boolean_for_force(old,
            native_force(23, {[braking.name] = native_technology(false, false)}), {braking}, nil)
          assert(rows[braking.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
          old = boolean_bucket(23, gear, 4, true, false)
          old.managed_technologies[gear.name].operation = "unknown-operation"
          rows, facts = legacy.import_boolean_for_force(old, force, {gear}, nil)
          assert(rows[gear.name] == nil and facts.decisions[1].outcome == "policy_mismatch")
        ''')

    def test_schema1_is_bounded_pure_and_does_not_change_structured_v3_imports(self):
        self.lua.execute('''
          local gear = candidate("recipe-prod-research_gears-1", "ips-max-level-research_gears",
            "generated-stream", "emit")
          local reads = 0
          local old = setmetatable({policy_version = 1}, {__index = function(_, key)
            reads = reads + 1
            if key == "managed_technologies" or key == "disabled_by_cap"
                or key == "visibility_by_cap" or key == "unowned_disabled_by_cap" then return {} end
            error("unexpected schema1 legacy field " .. tostring(key))
          end, __pairs = function() error("schema1 legacy maps must not be enumerated") end})
          local rows, facts = legacy.import_boolean_for_force(old, native_force(29, {}), {gear}, nil)
          assert(next(rows) == nil and facts.legacy_policy1 and facts.candidates_checked == 1)
          assert(reads <= 4)
          local oversized = {}
          for index = 1, 129 do oversized[index] = gear end
          local ok = pcall(function() legacy.import_boolean_for_force(old, native_force(29, {}), oversized, nil) end)
          assert(not ok, "schema1 candidate bound was not enforced")

          local structured = old_bucket(29, gear, 3, "mir32-1234abcd")
          rows, facts = legacy.import_boolean_for_force(structured,
            native_force(29, {[gear.name] = native_technology(false, true)}), {gear}, nil)
          assert(rows[gear.name] == nil and not facts.legacy_policy1)
          rows, facts = legacy.import_for_force(structured,
            native_force(29, {[gear.name] = native_technology(false, true)}), {gear}, nil)
          assert(rows[gear.name].disabled and facts.legacy_policy3,
            "schema1 decoder changed structured-v3 admission")
        ''')

    def test_source_has_no_old_runtime_import_or_mutating_assignment(self):
        source = (ROOT / "source/runtime/legacy_caps.lua").read_text(encoding="utf-8")
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

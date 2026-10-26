"""Host-only controls for one-shot historical cap restoration; not save evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LegacyCapsLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          gear_name = "recipe-prod-research_gears-1"
          agriculture_name = "recipe-prod-research_agricultural_growth_speed-1"
          spoilage_name = "recipe-prod-research_spoilage_preservation-1"
          function technology(name)
            return {name = name, level = 3, researched = false, enabled = false,
              visible_when_disabled = true, prototype = {enabled = true}}
          end
          function force(index, technologies)
            return {index = index, valid = true, technologies = technologies,
              research_queue = {}, research_progress = .42}
          end
          function worker(name)
            local result = technology(name)
            result.prototype = {max_level = 4294967295,
              effects = {{type = "worker-robot-speed", modifier = .65}}}
            local predecessor = name == "worker-robots-speed-7"
              and "worker-robots-speed-6" or "worker-robots-speed-5"
            result.prerequisites = {[predecessor] = {name = predecessor}}
            return result
          end
          -- Synthetic rows use the published V3 field/identity contract.
          -- Only a native upgrade of the immutable published save can qualify
          -- actual predecessor provenance and engine persistence.
          function legacy(names, indexes)
            local old = {policy_version = 3, managed_technologies = {},
              disabled_by_cap = {}, visibility_by_cap = {}, unique = {keep = true}}
            for _, name in ipairs(names) do
              local gear = name == gear_name
              local direct = name == agriculture_name or name == spoilage_name
              local continuation = name == "braking-force-8"
              local native_owner = name == "low-density-structure-productivity"
              local setting = gear and "ips-max-level-research_gears"
                or direct and "ips-max-level-" .. (name == agriculture_name
                  and "research_agricultural_growth_speed" or "research_spoilage_preservation")
                or continuation and "mir-max-level-braking-force"
                or native_owner and "ips-max-level-research_low_density_structure"
                or "mir-max-level-worker-robots-speed"
              local source = (gear or direct) and "generated-stream"
                or continuation and "base-continuation"
                or "native-owner"
              -- Only the predecessor-storage decoder uses this tuple. The
              -- published F210 V3 generated binding recorded `emit`; MIR5's
              -- live cap provenance is intentionally not represented here.
              local operation = (gear or direct) and "emit"
                or continuation and "emit_base_extension"
                or native_owner and "preserve_native_owner"
                or "native-owner-cap"
              local key = table.concat({name, setting, source, operation}, "\\0")
              old.managed_technologies[name] = {technology = name, setting = setting,
                source = source, operation = operation, policy_transport = "transported-v3",
                ownership_kind = "transported-v3", legacy = false, selected = 2,
                binding_fingerprint = "mir32-1234abcd"}
              for _, index in ipairs(indexes) do
                old.disabled_by_cap[index] = old.disabled_by_cap[index] or {}
                old.visibility_by_cap[index] = old.visibility_by_cap[index] or {}
                old.disabled_by_cap[index][name] = {policy_version = 3, force_index = index,
                  cap = 2, binding_fingerprint = "mir32-1234abcd", ownership_key = key,
                  ownership_kind = "transported-v3", enabled_before_cap = true}
                old.visibility_by_cap[index][name] = {policy_version = 3, force_index = index,
                  ownership_key = key, ownership_kind = "transported-v3", value = false}
              end
            end
            return old
          end
          -- Exact published F200 4.7.20002 maximum-level controller shape
          -- for its generated gear stream.  Its V3 policy was settings-derived
          -- because the 2.0 target did not carry the later finalizer binding.
          function f200_gear_legacy(index, cap)
            local name, setting = gear_name, "ips-max-level-research_gears"
            local source, operation = "generated-stream", "runtime-settings-transport"
            local kind = "settings-derived-v3"
            local key = table.concat({"nil", setting, source, operation}, "\\0")
            return {policy_version = 3, unique = {keep = true},
              managed_technologies = {[name] = {setting = setting,
                source = source, operation = operation, policy_transport = kind,
                ownership_kind = kind, legacy = false, selected = cap,
                native_finite_stage = false}},
              disabled_by_cap = {[index] = {[name] = {policy_version = 3, force_index = index,
                cap = cap, ownership_key = key,
                ownership_kind = kind, enabled_before_cap = true}}},
              visibility_by_cap = {[index] = {[name] = {policy_version = 3, force_index = index,
                ownership_key = key, ownership_kind = kind, value = false}}},
              unowned_disabled_by_cap = {[index] = {}}
            }
          end
          -- The same published F200 controller recorded a settings-derived
          -- V3 ownership row for either one of the two exact native worker
          -- tails. Runtime still has to revalidate its current .65 effect.
          function f200_worker_legacy(index, cap, name)
            name = name or "worker-robots-speed-6"
            local setting = "mir-max-level-worker-robots-speed"
            local source, operation = "native-owner", "native-owner-cap"
            local kind = "settings-derived-v3"
            local key = table.concat({"nil", setting, source, operation}, "\\0")
            return {policy_version = 3, unique = {keep = true},
              managed_technologies = {[name] = {setting = setting,
                source = source, operation = operation, policy_transport = kind,
                ownership_kind = kind, legacy = false, selected = cap,
                native_finite_stage = false}},
              disabled_by_cap = {[index] = {[name] = {policy_version = 3, force_index = index,
                cap = cap, ownership_key = key,
                ownership_kind = kind, enabled_before_cap = true}}},
              visibility_by_cap = {[index] = {[name] = {policy_version = 3, force_index = index,
                ownership_key = key, ownership_kind = kind, value = false}}},
              unowned_disabled_by_cap = {[index] = {}}
            }
          end
          function boot(forces, old, current, options)
            options = options or {}
            script = {active_mods = options.active_mods or {}}
            storage = {mir = {maximum_level_control = old, unrelated = {keep = true}},
              mir_caps = current}
            game = {forces = forces}
            mods = options.active_mods or {}
            local target = require("platform.target")
            if options.target_id == "f200" then
              target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
              target.distribution_version, target.cargo_research = "5.0.20000", false
              target.recipe_probability, target.receiver_limits = "probability", false
              target.productivity_ignores_stats = true
            else
              target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
              target.distribution_version, target.cargo_research = "5.0.21000", true
              target.recipe_probability, target.receiver_limits = "independent_probability", true
              target.productivity_ignores_stats = false
            end
            package.loaded["research.catalogue"] = nil
            local streams = {}
            for _, row in ipairs(require("research.catalogue").declared()) do
              local value = {enabled = options.enabled ~= false, max_level = options.limit or 0}
              if row.family == "research_agricultural_growth_speed" and options.agriculture then
                value = options.agriculture
              elseif row.family == "research_spoilage_preservation" and options.spoilage then
                value = options.spoilage
              end
              streams[row.family] = value
            end
            package.loaded["runtime.configuration"] = {
              enabled = options.enabled ~= false, max_level = options.limit or 0,
              worker_robots_speed_max_level = options.worker_limit or 0,
              streams = streams,
              agricultural_growth_speed = options.agriculture,
              spoilage_preservation = options.spoilage}
            package.loaded["runtime.lifecycle"] = nil
            lifecycle = require("runtime.lifecycle")
          end
          function f200_to_f210_event(old_version, new_version)
            return {mod_changes = {['more-infinite-research'] = {
              old_version = old_version or "4.7.20003", new_version = new_version or "5.0.21000"}}}
          end
        ''')

    def test_k2_historical_worker_right_is_bound_to_the_admitted_native_effect(self):
        self.lua.execute('''
          local name = "worker-robots-speed-7"
          local k2 = {Krastorio2 = "2.1.4", ['Krastorio2-spaced-out'] = "2.0.19",
            Krastorio2Assets = "2.1.0", ['k2so-assets'] = "1.0.7", ['space-age'] = "2.1.23"}
          local native = worker(name)
          native.level, native.prototype.effects[1].modifier = 9, .6
          local f = force(7, {[name] = native})
          local old = legacy({name}, {7})
          old.managed_technologies[name].selected = 8
          old.disabled_by_cap[7][name].cap = 8
          boot({[7] = f}, old, nil, {active_mods = k2, worker_limit = 8})
          lifecycle.on_configuration_changed()
          assert(not native.enabled and native.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[7][name].worker_effect_modifier == .6)
          assert(old.disabled_by_cap[7][name].enabled_before_cap
            and old.visibility_by_cap[7][name].value == false)
          local saved = storage.mir_caps
          boot({[7] = f}, old, saved, {active_mods = k2, worker_limit = 0})
          lifecycle.on_configuration_changed()
          assert(native.enabled and not native.visible_when_disabled and native.level == 9)
          assert(native.prototype.effects[1].modifier == .6)
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil)
          native.enabled = false
          lifecycle.on_configuration_changed()
          assert(not native.enabled, "old K2 rights were imported twice")
        ''')

    def test_fresh_unlimited_config_and_load_do_not_allocate_or_use_game(self):
        self.lua.execute('''
          boot({}, nil)
          lifecycle.on_configuration_changed()
          assert(storage.mir_caps == nil)
          local before = storage.mir
          game = setmetatable({}, {__index = function() error("game used on load") end})
          lifecycle.on_load()
          assert(storage.mir == before and storage.mir_caps == nil)
        ''')

    def test_owned_and_foreign_restoration_keep_old_bucket_unchanged(self):
        self.lua.execute('''
          local owned, foreign = technology(gear_name), technology(gear_name)
          local old = legacy({gear_name}, {1, 2})
          old.disabled_by_cap[2][gear_name] = nil
          boot({[1] = force(1, {[gear_name] = owned}),
            [2] = force(2, {[gear_name] = foreign})}, old)
          lifecycle.on_configuration_changed()
          assert(owned.enabled and not owned.visible_when_disabled and owned.level == 3)
          assert(not foreign.enabled and not foreign.visible_when_disabled and foreign.level == 3)
          assert(storage.mir.maximum_level_control == old and old.unique.keep)
          assert(old.disabled_by_cap[1][gear_name].enabled_before_cap)
          assert(old.visibility_by_cap[2][gear_name].value == false)
          assert(storage.mir.unrelated.keep and storage.mir_caps.legacy_caps_checked == true)
          assert(next(storage.mir_caps.owned_disabled) == nil)
        ''')

    def test_f200_settings_derived_gear_right_restores_only_on_the_f200_catalogue(self):
        self.lua.execute('''
          local player, foreign = technology(gear_name), technology(gear_name)
          player.level, player.researched = 3, false
          player.enabled, player.visible_when_disabled = false, true
          foreign.level, foreign.researched = 3, false
          foreign.enabled, foreign.visible_when_disabled = false, false
          local player_force = force(1, {[gear_name] = player})
          player_force.research_queue, player_force.current_research, player_force.research_progress = {player}, player, .42
          local foreign_force = force(2, {[gear_name] = foreign})
          local old = f200_gear_legacy(1, 2)
          boot({[1] = player_force, [2] = foreign_force}, old, nil,
            {target_id = "f200", limit = 40})
          local binding, generated = nil, 0
          for _, row in ipairs(require("research.catalogue").declared()) do
            if row.ownership_kind == "authored_generated" then
              generated = generated + 1
              local f200_binding = row.legacy_binding
              assert(f200_binding and (f200_binding.source == "generated-stream"
                or f200_binding.source == "base-continuation")
                and f200_binding.operation == "runtime-settings-transport"
                and f200_binding.target == "f200"
                and f200_binding.policy_transport == "settings-derived-v3"
                and f200_binding.ownership_kind == "settings-derived-v3",
                "an F200 generated declaration gained a non-published cap identity")
            end
            if row.id == gear_name then binding = row.legacy_binding end
          end
          assert(generated > 1, "F200 control parse did not retain its named generated catalogue")
          assert(binding and binding.source == "generated-stream"
            and binding.operation == "runtime-settings-transport" and binding.target == "f200"
            and binding.policy_transport == "settings-derived-v3"
            and binding.ownership_kind == "settings-derived-v3")
          local limits = lifecycle.cap_limits(player_force)
          assert(limits[gear_name] == 40, "F200 current cap was not the configured successor value")
          lifecycle.on_configuration_changed()
          assert(player.level == 3 and player.researched == false
            and player.enabled and not player.visible_when_disabled,
            "F200 owned cap relaxation changed earned state or missed restoration")
          assert(player_force.research_queue[1] == player and player_force.current_research == player
            and player_force.research_progress == .42,
            "F200 owned cap relaxation changed a valid queued level or progress")
          assert(not foreign.enabled and not foreign.visible_when_disabled and foreign.level == 3,
            "F200 restoration claimed the foreign force's disablement")
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil
            and old.unique.keep and old.disabled_by_cap[1][gear_name].cap == 2,
            "F200 import changed predecessor evidence or left stale ownership")

          -- The same old bucket is not a valid predecessor on ordinary F210,
          -- where the current named gear declaration has transported `emit`
          -- identity.  A direct cross-engine event is required separately.
          local f210 = technology(gear_name)
          f210.level, f210.enabled, f210.visible_when_disabled = 3, false, true
          local f210_force = force(1, {[gear_name] = f210})
          boot({[1] = f210_force}, old, nil, {target_id = "f210", limit = 40})
          lifecycle.on_configuration_changed()
          assert(not f210.enabled and f210.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked
            and storage.mir_caps.owned_disabled[1] == nil,
            "F210 accepted an F200 settings-derived restoration right")
        ''')

    def test_f200_hop_map_is_built_only_for_its_first_exact_configuration(self):
        self.lua.execute('''
          local legacy = require("runtime.legacy_caps")
          local construct, calls = legacy.f200_direct_hop_allowlist, 0
          legacy.f200_direct_hop_allowlist = function(...)
            calls = calls + 1
            return construct(...)
          end
          boot({}, nil, nil, {target_id = "f210"})
          assert(calls == 0, "ordinary F210 parsing constructed a predecessor map")
          lifecycle.on_configuration_changed()
          assert(calls == 0, "fresh F210 configuration constructed a predecessor map")

          local old = f200_gear_legacy(1, 2)
          local function predecessor()
            local item = technology(gear_name)
            item.level, item.enabled, item.visible_when_disabled = 3, false, true
            boot({[1] = force(1, {[gear_name] = item})}, old, nil,
              {target_id = "f210", limit = 40})
          end
          predecessor()
          assert(calls == 0)
          lifecycle.on_configuration_changed()
          assert(calls == 0, "unproven F210 configuration constructed a predecessor map")
          predecessor()
          lifecycle.on_configuration_changed(f200_to_f210_event())
          assert(calls == 1, "exact F200 transition did not construct its one predecessor map")
          lifecycle.on_configuration_changed(f200_to_f210_event())
          assert(calls == 1, "completed F200 import reconstructed its predecessor map")
        ''')

    def test_direct_f200_to_f210_event_restores_only_the_proven_owned_right(self):
        self.lua.execute('''
          local player, foreign = technology(gear_name), technology(gear_name)
          player.level, player.researched = 3, false
          player.enabled, player.visible_when_disabled = false, true
          foreign.level, foreign.researched = 3, false
          foreign.enabled, foreign.visible_when_disabled = false, false
          local player_force = force(1, {[gear_name] = player})
          player_force.research_queue, player_force.current_research, player_force.research_progress =
            {player}, player, .42
          local foreign_force = force(2, {[gear_name] = foreign})
          local old = f200_gear_legacy(1, 2)
          boot({[1] = player_force, [2] = foreign_force}, old, nil,
            {target_id = "f210", limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event())
          assert(player.enabled and not player.visible_when_disabled and player.level == 3
            and player.researched == false, "exact direct F200 event missed its owned cap restoration")
          assert(player_force.research_queue[1] == player and player_force.current_research == player
            and player_force.research_progress == .42,
            "direct F200 restoration rewrote a valid queue or progress")
          assert(not foreign.enabled and not foreign.visible_when_disabled and foreign.level == 3,
            "direct F200 restoration claimed the foreign force's disablement")
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil
            and old.disabled_by_cap[1][gear_name].enabled_before_cap,
            "direct F200 restoration changed predecessor evidence or kept ownership")

          -- Current MIR5 ownership, including a tombstone, remains ahead of
          -- the exceptional predecessor reader.
          local retained = technology(gear_name)
          retained.level, retained.enabled, retained.visible_when_disabled = 3, false, true
          local current = {schema = 1, owned_disabled = {[1] = {[gear_name] = false}}}
          boot({[1] = force(1, {[gear_name] = retained})}, old, current,
            {target_id = "f210", limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event())
          assert(not retained.enabled and retained.visible_when_disabled
            and current.owned_disabled[1][gear_name] == false and current.legacy_caps_checked,
            "direct F200 import displaced an existing MIR5 ownership decision")
        ''')

    def test_f200_to_f210_bridge_refuses_missing_wrong_or_malformed_event(self):
        self.lua.execute('''
          local old = f200_gear_legacy(1, 2)
          local function refused(event, index)
            local item = technology(gear_name)
            item.level, item.enabled, item.visible_when_disabled = 3, false, true
            boot({[1] = force(1, {[gear_name] = item})}, old, nil,
              {target_id = "f210", limit = 40})
            lifecycle.on_configuration_changed(event)
            assert(not item.enabled and item.visible_when_disabled
              and storage.mir_caps.legacy_caps_checked and storage.mir_caps.owned_disabled[1] == nil,
              "F210 bridge admitted non-exact event " .. index)
          end
          refused(nil, 1)
          refused(f200_to_f210_event("4.7.21003", "5.0.21000"), 2)
          refused(f200_to_f210_event("4.7.20003", "5.0.21001"), 3)
          refused({mod_changes = {['more-infinite-research'] = {
            old_version = "4.7.20003", new_version = false}}}, 4)
          refused({mod_changes = {['more-infinite-research'] = false}}, 5)
        ''')

    def test_f200_to_f210_bridge_revalidates_the_current_native_worker_tail(self):
        self.lua.execute('''
          local name = "worker-robots-speed-6"
          local invalid = worker(name)
          invalid.level, invalid.researched = 3, false
          invalid.enabled, invalid.visible_when_disabled = false, true
          invalid.prototype.effects[1].modifier = .66
          local old = f200_worker_legacy(1, 2, name)
          boot({[1] = force(1, {[name] = invalid})}, old, nil,
            {target_id = "f210", worker_limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event())
          assert(not invalid.enabled and invalid.visible_when_disabled and invalid.level == 3
            and storage.mir_caps.legacy_caps_checked and storage.mir_caps.owned_disabled[1] == nil,
            "direct F200 bridge accepted a mismatched current F210 native worker")
        ''')

    def test_disabled_f200_family_defers_a_proven_cap_right_until_reenabled_and_relaxed(self):
        self.lua.execute('''
          local item = technology(gear_name)
          item.enabled, item.visible_when_disabled, item.prototype.enabled = false, true, false
          local f, old = force(1, {[gear_name] = item}), f200_gear_legacy(1, 2)

          -- The disabled startup setting produces a retained, disabled data
          -- prototype. The prior V3 row proves MIR, rather than a foreign
          -- actor, performed the force-level disablement.
          boot({[1] = f}, old, nil, {target_id = "f200", enabled = false, limit = 2})
          lifecycle.on_configuration_changed()
          local saved = storage.mir_caps
          local retained = saved.owned_disabled[1][gear_name]
          assert(saved.legacy_caps_checked and retained.disabled
            and retained.visible_when_disabled == false)
          assert(not item.enabled and item.visible_when_disabled and item.prototype.enabled == false
            and old.disabled_by_cap[1][gear_name].enabled_before_cap)

          -- Re-enabling the family alone must retain the proven disablement
          -- while its configured cap remains below the earned level.
          item.prototype.enabled = true
          boot({[1] = f}, old, saved, {target_id = "f200", enabled = true, limit = 2})
          lifecycle.on_configuration_changed()
          assert(not item.enabled and item.visible_when_disabled
            and saved.owned_disabled[1][gear_name].disabled)

          boot({[1] = f}, old, saved, {target_id = "f200", enabled = true, limit = 40})
          lifecycle.on_configuration_changed()
          assert(item.enabled and not item.visible_when_disabled and item.level == 3
            and saved.legacy_caps_checked and next(saved.owned_disabled) == nil)
        ''')

    def test_disabled_f200_direct_hop_defers_the_exact_right_until_f210_reenable(self):
        self.lua.execute('''
          local item = technology(gear_name)
          item.enabled, item.visible_when_disabled, item.prototype.enabled = false, true, false
          local f, old = force(1, {[gear_name] = item}), f200_gear_legacy(1, 2)

          boot({[1] = f}, old, nil, {target_id = "f210", enabled = false, limit = 2})
          lifecycle.on_configuration_changed(f200_to_f210_event())
          local saved = storage.mir_caps
          assert(saved.legacy_caps_checked and saved.owned_disabled[1][gear_name].disabled
            and not item.enabled and item.prototype.enabled == false)

          item.prototype.enabled = true
          boot({[1] = f}, old, saved, {target_id = "f210", enabled = true, limit = 40})
          lifecycle.on_configuration_changed()
          assert(item.enabled and not item.visible_when_disabled and item.level == 3
            and saved.legacy_caps_checked and next(saved.owned_disabled) == nil)
        ''')

    def test_disabled_family_never_defers_a_missing_or_unowned_legacy_disablement(self):
        self.lua.execute('''
          local function assert_foreign_disablement_is_retained(old, label)
            local item = technology(gear_name)
            item.enabled, item.visible_when_disabled, item.prototype.enabled = false, true, false
            local f = force(1, {[gear_name] = item})
            boot({[1] = f}, old, nil, {target_id = "f200", enabled = false, limit = 2})
            lifecycle.on_configuration_changed()
            local saved = storage.mir_caps
            local record = saved.owned_disabled[1] and saved.owned_disabled[1][gear_name]
            assert(type(record) ~= "table" or record.disabled ~= true,
              label .. " gained a MIR enablement right while disabled")

            item.prototype.enabled = true
            boot({[1] = f}, old, saved, {target_id = "f200", enabled = true, limit = 40})
            lifecycle.on_configuration_changed()
            -- Visibility is independently owned by the validated old V3 row;
            -- only force enablement remains unavailable without the proof.
            assert(not item.enabled and not item.visible_when_disabled
              and saved.legacy_caps_checked and saved.owned_disabled[1] == nil,
              label .. " enabled a foreign or unproven disablement after re-enable")
          end

          local missing = f200_gear_legacy(1, 2)
          missing.disabled_by_cap[1][gear_name] = nil
          assert_foreign_disablement_is_retained(missing, "missing V3 disablement")

          local unowned = f200_gear_legacy(1, 2)
          unowned.unowned_disabled_by_cap[1][gear_name] = true
          assert_foreign_disablement_is_retained(unowned, "unowned V3 disablement")
        ''')

    def test_f200_mir5_finite_cap_ledger_restores_on_later_f210_relaxation(self):
        self.lua.execute('''
          local item = technology(gear_name)
          item.level, item.researched = 3, false
          item.enabled, item.visible_when_disabled = false, true
          local f = force(1, {[gear_name] = item})
          local old = f200_gear_legacy(1, 2)
          boot({[1] = f}, old, nil, {target_id = "f200", limit = 2})
          lifecycle.on_configuration_changed()
          local saved = storage.mir_caps
          assert(saved.legacy_caps_checked and saved.owned_disabled[1][gear_name].disabled
            and saved.owned_disabled[1][gear_name].visible_when_disabled == false
            and not item.enabled and item.visible_when_disabled,
            "F200 MIR5 finite cap did not retain its proven ownership ledger")

          -- This route does not reread the F200 bucket: it restores only the
          -- current MIR5 record after current F210 prototype admission.
          boot({[1] = f}, old, saved, {target_id = "f210", limit = 40})
          lifecycle.on_configuration_changed()
          assert(item.enabled and not item.visible_when_disabled and item.level == 3
            and item.researched == false and saved.legacy_caps_checked
            and next(saved.owned_disabled) == nil,
            "F200 MIR5 ownership ledger was not restored by its F210 successor")
          assert(old.disabled_by_cap[1][gear_name].enabled_before_cap
            and old.visibility_by_cap[1][gear_name].value == false,
            "later F210 reconciliation altered the F200 predecessor bucket")
        ''')

    def test_f200_settings_derived_worker_right_restores_only_the_exact_native_tail(self):
        self.lua.execute('''
          local name = "worker-robots-speed-6"
          local player, foreign = worker(name), worker(name)
          player.level, player.researched = 3, false
          player.enabled, player.visible_when_disabled = false, true
          foreign.level, foreign.researched = 3, false
          foreign.enabled, foreign.visible_when_disabled = false, false
          local player_force = force(1, {[name] = player})
          player_force.research_queue, player_force.current_research, player_force.research_progress =
            {player}, player, .42
          local foreign_force = force(2, {[name] = foreign})
          local old = f200_worker_legacy(1, 2, name)
          boot({[1] = player_force, [2] = foreign_force}, old, nil,
            {target_id = "f200", worker_limit = 40})
          assert(lifecycle.cap_limits(player_force)[name] == 40,
            "F200 current worker successor cap was not configured")
          lifecycle.on_configuration_changed()
          assert(player.level == 3 and not player.researched and player.enabled
            and not player.visible_when_disabled,
            "F200 worker restoration changed earned state or missed its owned disable")
          assert(player_force.research_queue[1] == player and player_force.current_research == player
            and player_force.research_progress == .42,
            "F200 worker restoration changed a valid queued level or progress")
          assert(not foreign.enabled and not foreign.visible_when_disabled and foreign.level == 3,
            "F200 worker restoration claimed a foreign disable")
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil
            and old.disabled_by_cap[1][name].cap == 2,
            "F200 worker import changed predecessor evidence or retained stale ownership")

          -- Native tuple validation remains ahead of persistence decoding. An
          -- old F200 row cannot restore a similar foreign worker effect.
          local invalid = worker(name)
          invalid.level, invalid.researched = 3, false
          invalid.enabled, invalid.visible_when_disabled = false, true
          invalid.prototype.effects[1].modifier = .66
          boot({[1] = force(1, {[name] = invalid})}, old, nil,
            {target_id = "f200", worker_limit = 40})
          lifecycle.on_configuration_changed()
          assert(not invalid.enabled and invalid.visible_when_disabled and invalid.level == 3
            and storage.mir_caps.legacy_caps_checked
            and storage.mir_caps.owned_disabled[1] == nil,
            "F200 worker import accepted a non-published native effect")
        ''')

    def test_marker_survives_empty_map_and_prevents_later_reimport(self):
        self.lua.execute('''
          local item = technology(gear_name)
          local old = legacy({gear_name}, {1})
          local f = force(1, {[gear_name] = item})
          boot({[1] = f}, old)
          lifecycle.on_configuration_changed()
          local saved = storage.mir_caps
          assert(saved and saved.legacy_caps_checked and item.enabled)
          item.enabled, item.visible_when_disabled = false, true
          boot({[1] = f}, old, saved)
          lifecycle.on_load()
          lifecycle.on_configuration_changed()
          assert(not item.enabled and item.visible_when_disabled,
            "untouched historical rows reclaimed a later foreign disable")
          -- Reusing an index must not create a second opportunity to import.
          local replacement = technology(gear_name)
          game.forces[1] = force(1, {[gear_name] = replacement})
          lifecycle.on_force_created({force = game.forces[1]})
          lifecycle.on_configuration_changed()
          assert(not replacement.enabled and replacement.visible_when_disabled)
          assert(storage.mir_caps == saved and saved.legacy_caps_checked)
        ''')

    def test_current_mir5_rights_win_over_historical_disable_rights(self):
        self.lua.execute('''
          local item = technology(gear_name)
          local current = {schema = 1, owned_disabled = {
            [1] = {[gear_name] = {visible_when_disabled = false}}}}
          boot({[1] = force(1, {[gear_name] = item})}, legacy({gear_name}, {1}), current)
          lifecycle.on_configuration_changed()
          assert(not item.enabled and not item.visible_when_disabled)
          assert(storage.mir_caps == current and current.legacy_caps_checked)
        ''')

    def test_current_tombstone_blocks_import_and_non_table_force_map_is_rejected(self):
        self.lua.execute('''
          local item = technology(gear_name)
          local current = {schema = 1, owned_disabled = {
            [1] = {[gear_name] = false}}}
          boot({[1] = force(1, {[gear_name] = item})}, legacy({gear_name}, {1}), current)
          lifecycle.on_configuration_changed()
          assert(current.owned_disabled[1][gear_name] == false and current.legacy_caps_checked)
          assert(not item.enabled and item.visible_when_disabled,
            "a tombstone gained a historical enablement right")

          local malformed_item = technology(gear_name)
          local malformed = {schema = 1, owned_disabled = {[1] = "preserved-malformed-row"}}
          boot({[1] = force(1, {[gear_name] = malformed_item})}, legacy({gear_name}, {1}), malformed)
          local ok, message = pcall(lifecycle.on_configuration_changed)
          assert(not ok and tostring(message):find("current ownership", 1, true))
          assert(malformed.owned_disabled[1] == "preserved-malformed-row"
            and not malformed_item.enabled and malformed_item.visible_when_disabled)
        ''')

    def test_unrecognized_old_state_is_examined_only_once(self):
        self.lua.execute('''
          local item, old = technology(gear_name), legacy({gear_name}, {1})
          old.policy_version = 2
          boot({[1] = force(1, {[gear_name] = item})}, old)
          lifecycle.on_configuration_changed()
          assert(not item.enabled and item.visible_when_disabled)
          assert(storage.mir_caps and storage.mir_caps.legacy_caps_checked)
          old.policy_version = 3
          lifecycle.on_configuration_changed()
          assert(not item.enabled and item.visible_when_disabled)
        ''')

    def test_worker_admission_is_revalidated_even_when_new_limit_is_zero(self):
        self.lua.execute('''
          local name = "worker-robots-speed-6"
          local item = worker(name)
          boot({[1] = force(1, {[name] = item})}, legacy({name}, {1}))
          lifecycle.on_configuration_changed()
          assert(item.enabled and not item.visible_when_disabled)
          local invalid = worker(name)
          invalid.prototype.effects[1].modifier = .66
          boot({[1] = force(1, {[name] = invalid})}, legacy({name}, {1}))
          lifecycle.on_configuration_changed()
          assert(not invalid.enabled and invalid.visible_when_disabled)
          local lower, higher = worker(name), worker("worker-robots-speed-7")
          boot({[1] = force(1, {[name] = lower, [higher.name] = higher})}, legacy({name}, {1}))
          lifecycle.on_configuration_changed()
          assert(not lower.enabled and lower.visible_when_disabled,
            "superseded worker tail gained restoration rights")
        ''')

    def test_disabled_gear_feature_never_gains_enablement_from_old_or_current_rights(self):
        self.lua.execute('''
          local item = technology(gear_name)
          local current = {schema = 1, owned_disabled = {
            [1] = {[gear_name] = {disabled = true, visible_when_disabled = false}}}}
          boot({[1] = force(1, {[gear_name] = item})}, legacy({gear_name}, {1}), current,
            {enabled = false, limit = 2})
          assert(not lifecycle.caps_active())
          lifecycle.on_configuration_changed()
          assert(not item.enabled and item.visible_when_disabled)
          assert(current.owned_disabled[1] == nil and current.legacy_caps_checked)
        ''')

    def test_policy_disabled_generated_prototype_rejects_a_v3_enablement_right(self):
        self.lua.execute('''
          local policy_disabled = technology(gear_name)
          policy_disabled.prototype.enabled = false
          local old = legacy({gear_name}, {1})
          boot({[1] = force(1, {[gear_name] = policy_disabled})}, old)
          lifecycle.on_configuration_changed()
          assert(not policy_disabled.enabled and policy_disabled.visible_when_disabled)
          assert(storage.mir_caps.legacy_caps_checked
            and storage.mir_caps.owned_disabled[1] == nil,
            "policy-disabled prototype imported an old cap enablement right")

          -- A normally enabled prototype still imports and restores the exact
          -- published V3 right when the current cap is unlimited.
          local ordinary = technology(gear_name)
          local ordinary_old = legacy({gear_name}, {2})
          boot({[2] = force(2, {[gear_name] = ordinary})}, ordinary_old)
          lifecycle.on_configuration_changed()
          assert(ordinary.enabled and not ordinary.visible_when_disabled)
          assert(storage.mir_caps.legacy_caps_checked
            and next(storage.mir_caps.owned_disabled) == nil)
        ''')

    def test_scripted_families_import_their_exact_rights_and_a_disabled_family_cannot_reclaim_them(self):
        self.lua.execute('''
          local agriculture, spoilage = technology(agriculture_name), technology(spoilage_name)
          local old = legacy({agriculture_name, spoilage_name}, {1})
          boot({[1] = force(1, {[agriculture_name] = agriculture, [spoilage_name] = spoilage})}, old,
            nil, {active_mods = {['space-age'] = '2.1.23'},
              agriculture = {enabled = true, max_level = 2},
              spoilage = {enabled = true, max_level = 2}})
          lifecycle.on_configuration_changed()
          local owned = storage.mir_caps.owned_disabled[1]
          assert(owned[agriculture_name].disabled and owned[spoilage_name].disabled)
          assert(not agriculture.enabled and agriculture.visible_when_disabled)
          assert(not spoilage.enabled and spoilage.visible_when_disabled)

          local saved = storage.mir_caps
          boot({[1] = force(1, {[agriculture_name] = agriculture, [spoilage_name] = spoilage})}, old,
            saved, {active_mods = {['space-age'] = '2.1.23'},
              agriculture = {enabled = true, max_level = 0},
              spoilage = {enabled = true, max_level = 0}})
          lifecycle.on_configuration_changed()
          assert(agriculture.enabled and spoilage.enabled)
          assert(not agriculture.visible_when_disabled and not spoilage.visible_when_disabled)
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil)

          agriculture.enabled, agriculture.visible_when_disabled = false, true
          local disabled_old = legacy({agriculture_name}, {1})
          boot({[1] = force(1, {[agriculture_name] = agriculture})}, disabled_old, nil,
            {active_mods = {['space-age'] = '2.1.23'},
              agriculture = {enabled = false, max_level = 2},
              spoilage = {enabled = true, max_level = 0}})
          lifecycle.on_configuration_changed()
          assert(not agriculture.enabled and agriculture.visible_when_disabled,
            "disabled scripted feature gained a predecessor enablement right")
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil)
        ''')

    def test_complete_catalogue_imports_a_continuation_and_exact_space_age_owner(self):
        self.lua.execute('''
          local continuation = technology("braking-force-8")
          local owner = technology("low-density-structure-productivity")
          owner.prototype = {max_level = 4294967295, effects = {
            {type = "change-recipe-productivity", recipe = "low-density-structure", change = .1},
            {type = "change-recipe-productivity", recipe = "casting-low-density-structure", change = .1}
          }}
          local f = force(51, {[continuation.name] = continuation, [owner.name] = owner})
          local old = legacy({continuation.name, owner.name}, {51})
          boot({[51] = f}, old, nil, {active_mods = {['space-age'] = '2.1.23'}, limit = 2})
          lifecycle.on_configuration_changed()
          local owned = storage.mir_caps.owned_disabled[51]
          assert(owned and owned[continuation.name] and owned[owner.name]
            and owned[continuation.name].disabled and owned[owner.name].disabled,
            "exact full-catalogue predecessors did not import")
          assert(not continuation.enabled and not owner.enabled
            and continuation.visible_when_disabled and owner.visible_when_disabled)

          local saved = storage.mir_caps
          boot({[51] = f}, old, saved, {active_mods = {['space-age'] = '2.1.23'}, limit = 0})
          lifecycle.on_configuration_changed()
          assert(continuation.enabled and owner.enabled
            and not continuation.visible_when_disabled and not owner.visible_when_disabled,
            "unlimited current settings did not restore the imported exact rights")
        ''')

    def test_init_does_not_import_predecessor_rights(self):
        self.lua.execute('''
          local item = technology(gear_name)
          boot({[1] = force(1, {[gear_name] = item})}, legacy({gear_name}, {1}))
          lifecycle.on_init()
          assert(not item.enabled and item.visible_when_disabled and storage.mir_caps == nil)
          lifecycle.on_configuration_changed()
          assert(item.enabled and not item.visible_when_disabled)
        ''')

    def test_stale_force_index_exception_is_contained_during_cleanup(self):
        self.lua.execute('''
          local item = technology(gear_name)
          local current = {schema = 1, owned_disabled = {
            [999] = {[gear_name] = {disabled = true, visible_when_disabled = false}}}}
          local forces = setmetatable({[1] = force(1, {[gear_name] = item})}, {
            __index = function(_, index) error("Invalid force index " .. tostring(index)) end})
          boot(forces, nil, current)
          lifecycle.on_configuration_changed()
          assert(storage.mir_caps == nil and not item.enabled and item.visible_when_disabled)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyCapsLifecycleTests))
    sys.exit(0 if result.wasSuccessful() else 1)

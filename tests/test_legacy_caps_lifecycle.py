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
          -- Public policy-v1 retained only its exact managed tuple, a true
          -- disable marker, and (in the later 09eb cohort) an optional
          -- visibility boolean.  This helper is intentionally not a full
          -- old-engine model.
          function schema1(index, entries)
            local old = {policy_version = 1, managed_technologies = {},
              disabled_by_cap = {[index] = {}}, unowned_disabled_by_cap = {[index] = {}},
              unique = {keep = true}}
            for _, entry in ipairs(entries) do
              old.managed_technologies[entry.name] = {source = entry.source,
                operation = entry.operation, setting = entry.setting,
                selected = entry.selected or 2}
              if entry.disabled ~= false then old.disabled_by_cap[index][entry.name] = true end
              if entry.visibility ~= nil then
                old.visibility_by_cap = old.visibility_by_cap or {}
                old.visibility_by_cap[index] = old.visibility_by_cap[index] or {}
                old.visibility_by_cap[index][entry.name] = entry.visibility
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

    def test_live_enabled_v3_first_off_write_retains_only_newly_imported_cap_right(self):
        self.lua.execute('''
          -- R10 observes this exact boundary: the protected V3 row has a
          -- positive disable proof and visibility value=true, while the live
          -- player technology is enabled even though its authored prototype
          -- is disabled.  MIR makes the first force-level true -> false write.
          local function exercise(label, target_id, event, old)
            local player, foreign = technology(gear_name), technology(gear_name)
            player.level, player.researched, player.saved_progress = 3, false, .27
            player.enabled, player.visible_when_disabled, player.prototype.enabled = true, true, false
            foreign.level, foreign.researched, foreign.saved_progress = 3, false, .27
            foreign.enabled, foreign.visible_when_disabled, foreign.prototype.enabled = false, true, false
            local player_force = force(1, {[gear_name] = player})
            local foreign_force = force(2, {[gear_name] = foreign})
            old = old or f200_gear_legacy(1, 2)
            old.visibility_by_cap[1][gear_name].value = true
            boot({[1] = player_force, [2] = foreign_force}, old, nil,
              {target_id = target_id, enabled = false, limit = 2})
            lifecycle.on_configuration_changed(event)
            local saved, owned = storage.mir_caps, storage.mir_caps.owned_disabled[1][gear_name]
            assert(saved.legacy_caps_checked and owned.disabled == true
              and owned.visible_when_disabled == true,
              label .. " did not retain the observed MIR first-off write")
            assert(not player.enabled and player.visible_when_disabled and player.level == 3
              and player.researched == false and player.saved_progress == .27,
              label .. " changed player earned or saved state during first-off capture")
            assert(not foreign.enabled and foreign.visible_when_disabled and foreign.level == 3
              and foreign.researched == false and foreign.saved_progress == .27,
              label .. " claimed the independently disabled foreign force")
            assert(old.disabled_by_cap[1][gear_name].enabled_before_cap
              and old.visibility_by_cap[1][gear_name].value == true and old.unique.keep,
              label .. " altered its exact predecessor evidence")

            -- A cold parse/load and repeated disabled configuration has no
            -- import opportunity. The durable row, not a callback-local
            -- signal, must remain the same exact two-field ownership row.
            local retained = owned
            boot({[1] = player_force, [2] = foreign_force}, old, saved,
              {target_id = target_id, enabled = false, limit = 2})
            lifecycle.on_load()
            lifecycle.on_configuration_changed()
            assert(storage.mir_caps == saved and saved.owned_disabled[1][gear_name] == retained
              and retained.disabled == true and retained.visible_when_disabled == true,
              label .. " lost its one-time first-off ownership across reload")
            for key in pairs(retained) do
              assert(key == "disabled" or key == "visible_when_disabled",
                label .. " persisted callback-local import state")
            end

            -- Prototype admission resumes only after the first-off record is
            -- persisted; finite current settings are deliberately relaxed.
            player.prototype.enabled, foreign.prototype.enabled = true, true
            boot({[1] = player_force, [2] = foreign_force}, old, saved,
              {target_id = target_id, enabled = true, limit = 40})
            lifecycle.on_configuration_changed()
            assert(player.enabled and player.visible_when_disabled and player.level == 3
              and player.researched == false and player.saved_progress == .27,
              label .. " did not restore its proven cap right after re-admission")
            assert(not foreign.enabled and foreign.visible_when_disabled and foreign.level == 3
              and foreign.researched == false and foreign.saved_progress == .27,
              label .. " restored a foreign force after re-admission")
            assert(saved.legacy_caps_checked and next(saved.owned_disabled) == nil,
              label .. " reread legacy state or retained stale cap ownership")
          end

          exercise("same-engine F200", "f200", nil)
          exercise("exact F200-to-F210", "f210", f200_to_f210_event())
          exercise("ordinary transported F210", "f210", nil, legacy({gear_name}, {1}))
        ''')

    def test_live_enabled_v3_first_off_never_upgrades_current_or_unproven_right(self):
        self.lua.execute('''
          local function assert_no_right(label, old, current)
            local item = technology(gear_name)
            item.level, item.researched, item.saved_progress = 3, false, .27
            item.enabled, item.visible_when_disabled, item.prototype.enabled = true, true, false
            local f = force(1, {[gear_name] = item})
            boot({[1] = f}, old, current, {target_id = "f210", enabled = false, limit = 2})
            lifecycle.on_configuration_changed(f200_to_f210_event())
            local saved = storage.mir_caps
            local record = saved.owned_disabled[1] and saved.owned_disabled[1][gear_name]
            assert(not item.enabled and item.visible_when_disabled and item.level == 3
              and item.researched == false and item.saved_progress == .27,
              label .. " changed live state before re-admission")
            assert(type(record) ~= "table" or record.disabled ~= true,
              label .. " gained a fresh MIR enablement right")

            item.prototype.enabled = true
            boot({[1] = f}, old, saved, {target_id = "f210", enabled = true, limit = 40})
            lifecycle.on_configuration_changed()
            assert(not item.enabled and item.visible_when_disabled and item.level == 3
              and item.researched == false and item.saved_progress == .27,
              label .. " restored without a newly imported positive V3 proof")
            assert(saved.legacy_caps_checked and saved.owned_disabled[1] == nil,
              label .. " reread legacy state after its one-time decision")
          end

          local current_negative = {schema = 1, owned_disabled = {
            [1] = {[gear_name] = {disabled = false, visible_when_disabled = true}}}}
          assert_no_right("current disabled=false", f200_gear_legacy(1, 2), current_negative)

          local current_visibility_only = {schema = 1, owned_disabled = {
            [1] = {[gear_name] = {visible_when_disabled = true}}}}
          assert_no_right("current visibility-only", f200_gear_legacy(1, 2), current_visibility_only)

          local missing = f200_gear_legacy(1, 2)
          missing.visibility_by_cap[1][gear_name].value = true
          missing.disabled_by_cap[1][gear_name] = nil
          assert_no_right("missing V3 disable proof", missing, nil)

          local corrupt = f200_gear_legacy(1, 2)
          corrupt.visibility_by_cap[1][gear_name].value = true
          corrupt.disabled_by_cap[1][gear_name].enabled_before_cap = false
          assert_no_right("corrupt V3 disable proof", corrupt, nil)

          local unowned = f200_gear_legacy(1, 2)
          unowned.visibility_by_cap[1][gear_name].value = true
          unowned.unowned_disabled_by_cap[1][gear_name] = true
          assert_no_right("unowned V3 disable proof", unowned, nil)
        ''')

    def test_earlier_published_f200_v3_hops_keep_regular_f210_reader_and_boundaries(self):
        self.lua.execute('''
          -- Archive inspection establishes these as the published F200 V3
          -- controller versions: 5d covers 4.2rc/stable through 4.4.1 and
          -- 48 covers 4.4.2 through 4.6.  They use the same settings-derived
          -- source tuple, but cannot be admitted by an unbounded old-version
          -- prefix or by the ordinary F210 transported reader alone.
          local published = {
            "4.2.20000", "4.2.20001", "4.2.20002", "4.3.20000",
            "4.4.20000", "4.4.20001", "4.4.20002",
            "4.5.20000", "4.5.20001", "4.5.20002", "4.6.20000"
          }
          for index, version in ipairs(published) do
            local item = technology(gear_name)
            item.level, item.researched = 3, false
            item.enabled, item.visible_when_disabled = false, true
            local source = f200_gear_legacy(index, 2)
            boot({[index] = force(index, {[gear_name] = item})}, source, nil,
              {target_id = "f210", limit = 40})
            lifecycle.on_configuration_changed(f200_to_f210_event(version))
            assert(item.enabled and not item.visible_when_disabled
              and item.level == 3 and item.researched == false
              and storage.mir_caps.legacy_caps_checked
              and storage.mir_caps.owned_disabled[index] == nil,
              "published F200 V3 hop was not restored: " .. version)
            assert(source.disabled_by_cap[index][gear_name].enabled_before_cap
              and source.visibility_by_cap[index][gear_name].value == false,
              "published F200 V3 source evidence was altered: " .. version)
          end

          -- This synthetic collision does not represent the published F210
          -- archive, whose exact metadata is4.2.21000. Its normal
          -- transported record must continue through the ordinary reader when
          -- the event has that colliding version, rather than being consumed
          -- only as an F200 predecessor.
          local f210 = technology(gear_name)
          f210.level, f210.researched = 3, false
          f210.enabled, f210.visible_when_disabled = false, true
          local transported = legacy({gear_name}, {80})
          boot({[80] = force(80, {[gear_name] = f210})}, transported, nil,
            {target_id = "f210", limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event("4.2.20000"))
          assert(f210.enabled and not f210.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil,
            "colliding F210 V3 record lost its ordinary transported reader")

          -- Neither the already-published V1 4.1 F200 version nor absent
          -- patch codecs can select the extra settings-derived V3 bridge.
          for index, version in ipairs({"4.1.20000", "4.2.20003", "4.4.20003", "4.8.20000"}) do
            local item = technology(gear_name)
            item.enabled, item.visible_when_disabled = false, true
            local source = f200_gear_legacy(index, 2)
            boot({[index] = force(index, {[gear_name] = item})}, source, nil,
              {target_id = "f210", limit = 40})
            lifecycle.on_configuration_changed(f200_to_f210_event(version))
            assert(not item.enabled and item.visible_when_disabled
              and storage.mir_caps.legacy_caps_checked
              and storage.mir_caps.owned_disabled[index] == nil,
              "unpublished or non-V3 F200 codec gained a bridge: " .. version)
          end
        ''')

    def test_442_f200_worker_hop_keeps_current_and_foreign_boundaries(self):
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
          local source = f200_worker_legacy(1, 2, name)
          boot({[1] = player_force, [2] = force(2, {[name] = foreign})}, source, nil,
            {target_id = "f210", worker_limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event("4.4.20002"))
          assert(player.enabled and not player.visible_when_disabled and player.level == 3
            and player_force.research_queue[1] == player and player_force.current_research == player
            and player_force.research_progress == .42
            and not foreign.enabled and not foreign.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil,
            "published 4.4.20002 worker hop changed earned, queue, or foreign state")

          -- A current MIR5 decision wins even for this earlier direct-hop
          -- predecessor; the exceptional reader cannot overwrite a tombstone.
          local retained = worker(name)
          retained.enabled, retained.visible_when_disabled = false, true
          local current = {schema = 1, owned_disabled = {[1] = {[name] = false}}}
          boot({[1] = force(1, {[name] = retained})}, source, current,
            {target_id = "f210", worker_limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event("4.4.20002"))
          assert(not retained.enabled and retained.visible_when_disabled
            and current.owned_disabled[1][name] == false and current.legacy_caps_checked,
            "earlier worker predecessor displaced current MIR5 ownership")

          local invalid = worker(name)
          invalid.enabled, invalid.visible_when_disabled = false, true
          invalid.prototype.effects[1].modifier = .66
          boot({[3] = force(3, {[name] = invalid})}, f200_worker_legacy(3, 2, name), nil,
            {target_id = "f210", worker_limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event("4.4.20002"))
          assert(not invalid.enabled and invalid.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked and storage.mir_caps.owned_disabled[3] == nil,
            "earlier worker predecessor bypassed current native-owner admission")
        ''')

    def test_47_f200_worker_hop_keeps_current_false_tombstone(self):
        self.lua.execute('''
          -- The existing 4.7 bridge has the same current-MIR5 precedence
          -- boundary as the newly admitted 4.4.2 worker predecessor. A
          -- literal false is a durable current decision, not a malformed row
          -- to discard before either exceptional reader observes it.
          local name = "worker-robots-speed-6"
          local retained = worker(name)
          retained.enabled, retained.visible_when_disabled = false, true
          local current = {schema = 1, owned_disabled = {[1] = {[name] = false}}}
          boot({[1] = force(1, {[name] = retained})}, f200_worker_legacy(1, 2, name), current,
            {target_id = "f210", worker_limit = 40})
          lifecycle.on_configuration_changed(f200_to_f210_event("4.7.20003"))
          assert(not retained.enabled and retained.visible_when_disabled
            and current.owned_disabled[1][name] == false and current.legacy_caps_checked,
            "4.7 worker predecessor displaced a current MIR5 false tombstone")
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

    def test_first_live_enabled_v3_import_retains_its_new_finite_cap_write(self):
        self.lua.execute('''
          local function check(target, event, transported)
            local item = technology(gear_name)
            item.enabled, item.prototype.enabled, item.saved_progress = true, true, .27
            local f = force(1, {[gear_name] = item})
            local old = transported and legacy({gear_name}, {1}) or f200_gear_legacy(1, 2)
            old.visibility_by_cap[1][gear_name].value = true
            boot({[1] = f}, old, nil, {target_id = target, enabled = true, limit = 2})
            lifecycle.on_configuration_changed(event)
            local saved = storage.mir_caps
            assert(not item.enabled and saved.owned_disabled[1][gear_name].disabled == true,
              "the first exact positive V3 import lost its new finite-cap disablement right")
            assert(item.level == 3 and not item.researched and item.saved_progress == .27)
            -- A cold load must reconstruct subscriptions without replaying
            -- the transient proof or altering its durable positive result.
            lifecycle.on_load()
            assert(saved.owned_disabled[1][gear_name].disabled == true and not item.enabled)
            boot({[1] = f}, old, saved, {target_id = target, enabled = true, limit = 40})
            lifecycle.on_configuration_changed()
            assert(item.enabled and item.visible_when_disabled and item.level == 3
              and not item.researched and item.saved_progress == .27
              and saved.legacy_caps_checked and next(saved.owned_disabled) == nil,
              "relaxation failed to restore the exact newly owned finite-cap write")
          end
          check("f200", nil, false)
          check("f210", f200_to_f210_event(), false)
          check("f210", nil, true)
        ''')

    def test_first_live_enabled_worker_v3_import_retains_only_its_own_cap_write(self):
        self.lua.execute('''
          local name = "worker-robots-speed-6"
          local item, foreign = worker(name), worker(name)
          item.level, item.enabled, item.saved_progress = 7, true, .27
          foreign.level, foreign.enabled, foreign.saved_progress = 7, false, .19
          local probe = technology("braking-force-1")
          local f = force(1, {[name] = item, [probe.name] = probe})
          f.research_queue, f.current_research, f.research_progress = {probe}, probe, .42
          local other = force(2, {[name] = foreign})
          local old = f200_worker_legacy(1, 6, name)
          boot({[1] = f, [2] = other}, old, nil, {target_id = "f210", worker_limit = 6})
          lifecycle.on_configuration_changed(f200_to_f210_event("4.4.20002"))
          local saved = storage.mir_caps
          assert(not item.enabled and saved.owned_disabled[1][name].disabled == true
            and saved.owned_disabled[1][name].worker_effect_modifier == .65,
            "the exact admitted native worker lost its newly written cap right")
          assert(not foreign.enabled and saved.owned_disabled[2][name].disabled == false)
          boot({[1] = f, [2] = other}, old, saved, {target_id = "f210", worker_limit = 40})
          lifecycle.on_configuration_changed()
          assert(item.enabled and item.level == 7 and not item.researched and item.saved_progress == .27
            and f.research_queue[1] == probe and f.current_research == probe and f.research_progress == .42)
          assert(not foreign.enabled and foreign.level == 7 and foreign.saved_progress == .19
            and saved.legacy_caps_checked and next(saved.owned_disabled) == nil,
            "worker relaxation changed foreign rights, earned state or unrelated work")
        ''')

    def test_live_enabled_first_cap_never_promotes_existing_or_unproven_rows(self):
        self.lua.execute('''
          local function check(current, old, label)
            local item = technology(gear_name)
            item.enabled, item.prototype.enabled = true, true
            local f = force(1, {[gear_name] = item})
            boot({[1] = f}, old, current, {target_id = "f200", enabled = true, limit = 2})
            lifecycle.on_configuration_changed()
            local saved = storage.mir_caps
            assert(not item.enabled and saved.owned_disabled[1][gear_name].disabled == false,
              label .. " gained a positive right from an older import")
            boot({[1] = f}, old, saved, {target_id = "f200", enabled = true, limit = 40})
            lifecycle.on_configuration_changed()
            assert(not item.enabled and next(saved.owned_disabled) == nil,
              label .. " was incorrectly enabled after relaxation")
          end
          check({schema = 1, owned_disabled = {[1] = {[gear_name] =
            {disabled = false, visible_when_disabled = true}}}}, f200_gear_legacy(1, 2), "current negative")
          check({schema = 1, owned_disabled = {[1] = {[gear_name] =
            {visible_when_disabled = true}}}}, f200_gear_legacy(1, 2), "existing visibility-only")
          local missing = f200_gear_legacy(1, 2)
          missing.disabled_by_cap[1][gear_name] = nil
          check(nil, missing, "missing V3 positive proof")
          local unowned = f200_gear_legacy(1, 2)
          unowned.unowned_disabled_by_cap[1][gear_name] = true
          check(nil, unowned, "unowned V3 marker")
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

    def test_schema1_f200_fallback_and_f210_planned_rows_preserve_owned_state_only(self):
        self.lua.execute('''
          -- The V1 09eb public controller's no-mod-data path used this exact
          -- F200 runtime-settings tuple.  The source cap is two; current F200
          -- first retains the earned level and later restores only its own
          -- disablement when the current cap is unlimited.
          local player, foreign = technology(gear_name), technology(gear_name)
          player.level, player.researched = 3, false
          player.enabled, player.visible_when_disabled = false, true
          foreign.level, foreign.researched = 3, false
          foreign.enabled, foreign.visible_when_disabled = false, false
          local player_force, foreign_force = force(1, {[gear_name] = player}), force(2, {[gear_name] = foreign})
          local old = schema1(1, {{name = gear_name, setting = "ips-max-level-research_gears",
            source = "generated-stream", operation = "runtime-settings-transport", selected = 2, visibility = false}})
          old.disabled_by_cap[2] = {[gear_name] = false}
          boot({[1] = player_force, [2] = foreign_force}, old, nil,
            {target_id = "f200", limit = 2})
          lifecycle.on_configuration_changed()
          local saved = storage.mir_caps
          assert(not player.enabled and player.visible_when_disabled
            and saved.owned_disabled[1][gear_name].disabled
            and saved.owned_disabled[1][gear_name].visible_when_disabled == false,
            "schema1 source cap did not retain its owned finite state")
          assert(not foreign.enabled and foreign.visible_when_disabled
            and saved.owned_disabled[2][gear_name].disabled == false,
            "schema1 false foreign marker gained an enablement right")

          player_force.research_queue, player_force.current_research, player_force.research_progress =
            {player}, player, .42
          boot({[1] = player_force, [2] = foreign_force}, old, saved,
            {target_id = "f200", limit = 0})
          lifecycle.on_configuration_changed()
          assert(player.enabled and not player.visible_when_disabled
            and player.level == 3 and player.researched == false
            and player_force.research_queue[1] == player and player_force.current_research == player
            and player_force.research_progress == .42,
            "schema1 cap relaxation changed owned earned state or progress")
          assert(not foreign.enabled and not foreign.visible_when_disabled and foreign.level == 3
            and saved.legacy_caps_checked and next(saved.owned_disabled) == nil,
            "schema1 cap relaxation restored a foreign false marker")
          assert(old.unique.keep and old.disabled_by_cap[1][gear_name] == true,
            "schema1 import changed predecessor evidence")

          -- F210's planned V1 tuple is independently admitted from the
          -- current authored generated row; no predecessor version label or
          -- F200 special event selects this reader.
          local planned = technology(gear_name)
          planned.level, planned.researched = 3, false
          planned.enabled, planned.visible_when_disabled = false, true
          local planned_old = schema1(3, {{name = gear_name, setting = "ips-max-level-research_gears",
            source = "generated-stream", operation = "emit", selected = 2, visibility = false}})
          boot({[3] = force(3, {[gear_name] = planned})}, planned_old, nil,
            {target_id = "f210", limit = 0})
          lifecycle.on_configuration_changed()
          assert(planned.enabled and not planned.visible_when_disabled and planned.level == 3
            and storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil,
            "schema1 planned F210 tuple was not restored through current admission")
        ''')

    def test_schema1_base_continuation_optional_visibility_and_native_tail_boundary(self):
        self.lua.execute('''
          -- The compiled V1 continuation was an independently named emitted
          -- row.  A missing visibility map proves only the true disable
          -- marker, never a visibility restoration.
          local braking = technology("braking-force-8")
          braking.level, braking.researched = 3, false
          braking.enabled, braking.visible_when_disabled = false, false
          local continuation_old = schema1(51, {{name = braking.name,
            setting = "mir-max-level-braking-force", source = "base-continuation",
            operation = "emit_base_extension", selected = 2}})
          boot({[51] = force(51, {[braking.name] = braking})}, continuation_old, nil,
            {target_id = "f210", active_mods = {['space-age'] = '2.1.23'}, limit = 0})
          lifecycle.on_configuration_changed()
          assert(braking.enabled and not braking.visible_when_disabled and braking.level == 3
            and storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled) == nil,
            "schema1 continuation changed an uncaptured visibility baseline")

          -- Schema1 never grants the later native-owner/worker-speed tail a
          -- right, even where current native preflight recognises the .65
          -- owner.  It remains disabled and no MIR5 row is persisted.
          local name, tail = "worker-robots-speed-6", worker("worker-robots-speed-6")
          tail.enabled, tail.visible_when_disabled = false, true
          local worker_old = schema1(7, {{name = name,
            setting = "mir-max-level-worker-robots-speed", source = "native-owner",
            operation = "native-owner-cap", selected = 2, visibility = false}})
          boot({[7] = force(7, {[name] = tail})}, worker_old, nil,
            {target_id = "f210", worker_limit = 0})
          lifecycle.on_configuration_changed()
          assert(not tail.enabled and tail.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked and storage.mir_caps.owned_disabled[7] == nil,
            "schema1 granted a later native worker tail restoration right")
        ''')

    def test_schema1_f200_transport_tuple_maps_to_current_f210_emissions(self):
        self.lua.execute('''
          -- The public schema-1 F200 component persisted the same finite
          -- settings transport for both producer classes.  Current F210
          -- admission identifies their emitted forms as `emit` and
          -- `emit_base_extension`; the historical tuple must not be rejected
          -- merely because the successor has those current operation names.
          local gear, braking = technology(gear_name), technology("braking-force-8")
          gear.level, gear.researched = 3, false
          gear.enabled, gear.visible_when_disabled = false, true
          braking.level, braking.researched = 3, false
          braking.enabled, braking.visible_when_disabled = false, true
          local old = schema1(23, {
            {name = gear_name, setting = "ips-max-level-research_gears",
              source = "generated-stream", operation = "runtime-settings-transport",
              selected = 2, visibility = false},
            {name = braking.name, setting = "mir-max-level-braking-force",
              source = "base-continuation", operation = "runtime-settings-transport",
              selected = 2, visibility = false}
          })
          boot({[23] = force(23, {[gear.name] = gear, [braking.name] = braking})}, old, nil,
            {target_id = "f210", limit = 0})
          lifecycle.on_configuration_changed()
          assert(gear.enabled and not gear.visible_when_disabled
            and braking.enabled and not braking.visible_when_disabled
            and gear.level == 3 and braking.level == 3
            and storage.mir_caps.legacy_caps_checked
            and next(storage.mir_caps.owned_disabled) == nil,
            "schema1 F200 transport tuple did not restore current F210 emitted rows")
          assert(old.unique.keep
            and old.managed_technologies[gear.name].operation == "runtime-settings-transport"
            and old.managed_technologies[braking.name].operation == "runtime-settings-transport",
            "schema1 cross-hop altered predecessor tuple evidence")
        ''')

    def test_schema1_rejects_unadmitted_or_current_state_and_is_never_read_on_load(self):
        self.lua.execute('''
          local item = technology(gear_name)
          item.enabled, item.visible_when_disabled = false, true
          local old = schema1(1, {{name = gear_name, setting = "ips-max-level-research_gears",
            source = "generated-stream", operation = "emit", selected = 2, visibility = false}})
          boot({[1] = force(1, {[gear_name] = item})}, old)
          lifecycle.on_load()
          assert(storage.mir_caps == nil and not item.enabled and item.visible_when_disabled,
            "on_load imported a schema1 predecessor right")
          lifecycle.on_configuration_changed()
          assert(item.enabled and not item.visible_when_disabled and storage.mir_caps.legacy_caps_checked)

          local current_item = technology(gear_name)
          current_item.enabled, current_item.visible_when_disabled = false, true
          local current = {schema = 1, owned_disabled = {
            [1] = {[gear_name] = {disabled = false, visible_when_disabled = false}}}}
          boot({[1] = force(1, {[gear_name] = current_item})}, old, current)
          lifecycle.on_configuration_changed()
          assert(not current_item.enabled and not current_item.visible_when_disabled
            and current.legacy_caps_checked,
            "schema1 overwrote current MIR5 ownership")

          local disabled_prototype = technology(gear_name)
          disabled_prototype.enabled, disabled_prototype.visible_when_disabled = false, true
          disabled_prototype.prototype.enabled = false
          boot({[1] = force(1, {[gear_name] = disabled_prototype})}, old)
          lifecycle.on_configuration_changed()
          assert(not disabled_prototype.enabled and disabled_prototype.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked and storage.mir_caps.owned_disabled[1] == nil,
            "schema1 imported a row without current prototype admission")

          local malformed = schema1(1, {{name = gear_name, setting = "ips-max-level-research_gears",
            source = "generated-stream", operation = "emit", selected = 2, visibility = false}})
          malformed.policy_version = 2
          local malformed_item = technology(gear_name)
          malformed_item.enabled, malformed_item.visible_when_disabled = false, true
          boot({[1] = force(1, {[gear_name] = malformed_item})}, malformed)
          lifecycle.on_configuration_changed()
          assert(not malformed_item.enabled and malformed_item.visible_when_disabled
            and storage.mir_caps.legacy_caps_checked,
            "an unknown schema gained schema1 restoration authority")
          malformed.policy_version = 1
          lifecycle.on_configuration_changed()
          assert(not malformed_item.enabled and malformed_item.visible_when_disabled,
            "one-time marker reread a repaired schema1 bucket")
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

    def test_non_table_legacy_bucket_cannot_crash_or_grant_ownership(self):
        self.lua.execute('''
          for _, old in ipairs({true, 7, "legacy"}) do
            local item = technology(gear_name)
            boot({[1] = force(1, {[gear_name] = item})}, old)
            lifecycle.on_configuration_changed()
            assert(not item.enabled and item.visible_when_disabled
              and storage.mir.maximum_level_control == old
              and storage.mir_caps.legacy_caps_checked
              and next(storage.mir_caps.owned_disabled) == nil,
              "malformed predecessor gained authority or lost its original value")
            lifecycle.on_configuration_changed()
            assert(not item.enabled and item.visible_when_disabled,
              "repeated configuration imported malformed predecessor rights")
          end
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

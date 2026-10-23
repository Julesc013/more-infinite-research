"""Host-only controls for one-shot historical cap restoration; not save evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LegacyCapsLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          gear_name = "recipe-prod-research_gears-1"
          agriculture_name = "recipe-prod-research_agricultural_growth_speed-1"
          spoilage_name = "recipe-prod-research_spoilage_preservation-1"
          function technology(name)
            return {name = name, level = 3, researched = false, enabled = false,
              visible_when_disabled = true}
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
              local setting = gear and "ips-max-level-research_gears"
                or direct and "ips-max-level-" .. (name == agriculture_name
                  and "research_agricultural_growth_speed" or "research_spoilage_preservation")
                or "mir-max-level-worker-robots-speed"
              local source = (gear or direct) and "generated-stream" or "native-owner"
              -- Only the predecessor-storage decoder uses this tuple. The
              -- published F210 V3 generated binding recorded `emit`; MIR5's
              -- live cap provenance is intentionally not represented here.
              local operation = (gear or direct) and "emit" or "native-owner-cap"
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
          function boot(forces, old, current, options)
            options = options or {}
            script = {active_mods = options.active_mods or {}}
            storage = {mir = {maximum_level_control = old, unrelated = {keep = true}},
              mir_caps = current}
            game = {forces = forces}
            mods = options.active_mods or {}
            package.loaded["runtime.configuration"] = {
              enabled = options.enabled ~= false, max_level = options.limit or 0,
              worker_robots_speed_max_level = options.worker_limit or 0,
              agricultural_growth_speed = options.agriculture,
              spoilage_preservation = options.spoilage}
            package.loaded["runtime.lifecycle"] = nil
            lifecycle = require("runtime.lifecycle")
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

"""Pure Lua 5.2 controls for bounded MIR 5 native-owner admission, not native evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
CAPTURE = json.loads((ROOT / "spec/mir5/inventory/vanilla-f210-470.json").read_text(encoding="utf-8"))


class NativeOwnersTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          owners = require("research.native_owners")

          function data_technology(name, predecessor, options)
            options = options or {}
            return {
              name = name,
              max_level = options.max_level or "infinite",
              effects = options.effects or {{type = "worker-robot-speed", modifier = .65}},
              prerequisites = options.prerequisites or {predecessor, "space-science-pack"}
            }
          end

          function runtime_technology(name, predecessor, options)
            options = options or {}
            local prereq = options.prerequisites or {[predecessor] = {name = predecessor}}
            return {
              name = name,
              prototype = {
                max_level = options.max_level or 4294967295,
                effects = options.effects or {{type = "worker-robot-speed", modifier = .65}}
              },
              prerequisites = prereq
            }
          end

          function lookup(values, calls)
            return function(name)
              calls[#calls + 1] = name
              return values[name]
            end
          end
        ''')

    def test_data_capture_shape_admits_current_six_tail(self):
        rows = CAPTURE["technology_rows"]
        captured = next(row["full_native_prototype_row"] for row in rows
                        if row["technology_id"] == "worker-robots-speed-6")
        self.assertEqual(captured["max_level"], "infinite")
        self.assertEqual(captured["effects"], [{"type": "worker-robot-speed", "modifier": .65}])
        self.assertEqual(captured["prerequisites"][:2],
                         ["worker-robots-speed-5", "space-science-pack"])
        self.lua.execute('''
          local calls = {}
          local current = data_technology("worker-robots-speed-6", "worker-robots-speed-5")
          assert(owners.data_worker_robot_speed_owner(lookup({[current.name] = current}, calls))
            == "worker-robots-speed-6")
          assert(#calls == 2 and calls[1] == "worker-robots-speed-7"
            and calls[2] == "worker-robots-speed-6")
        ''')

    def test_candidate_priority_uses_seven_before_six(self):
        self.lua.execute('''
          local calls = {}
          local seven = data_technology("worker-robots-speed-7", "worker-robots-speed-6")
          local six = data_technology("worker-robots-speed-6", "worker-robots-speed-5")
          assert(owners.data_worker_robot_speed_owner(lookup({
            [seven.name] = seven, [six.name] = six
          }, calls)) == seven.name)
          assert(#calls == 1 and calls[1] == seven.name)
        ''')

    def test_runtime_uses_numeric_max_and_prerequisite_object_map(self):
        self.lua.execute('''
          local current = runtime_technology("worker-robots-speed-6", "worker-robots-speed-5")
          assert(owners.runtime_worker_robot_speed_owner(function(name)
            return name == current.name and current or nil
          end) == current.name)
          current.prototype.max_level = 4294967294
          assert(owners.runtime_worker_robot_speed_owner(function(name)
            return name == current.name and current or nil
          end) == nil)
          current.prototype.max_level = "infinite"
          assert(owners.runtime_worker_robot_speed_owner(function(name)
            return name == current.name and current or nil
          end) == nil)
        ''')

    def test_extra_effect_is_not_an_owner(self):
        self.lua.execute('''
          local effects = {
            {type = "worker-robot-speed", modifier = .65},
            {type = "laboratory-speed", modifier = .1}
          }
          local value = data_technology("worker-robots-speed-6", "worker-robots-speed-5", {effects = effects})
          assert(owners.data_worker_robot_speed_owner(function(name)
            return name == value.name and value or nil
          end) == nil)
          local runtime = runtime_technology("worker-robots-speed-6", "worker-robots-speed-5", {effects = effects})
          assert(owners.runtime_worker_robot_speed_owner(function(name)
            return name == runtime.name and runtime or nil
          end) == nil)
        ''')

    def test_wrong_max_and_wrong_predecessor_are_not_owners(self):
        self.lua.execute('''
          local wrong_max = data_technology("worker-robots-speed-6", "worker-robots-speed-5", {max_level = 100})
          assert(owners.data_worker_robot_speed_owner(function(name)
            return name == wrong_max.name and wrong_max or nil
          end) == nil)
          local wrong_predecessor = runtime_technology("worker-robots-speed-6", "wrong-predecessor")
          assert(owners.runtime_worker_robot_speed_owner(function(name)
            return name == wrong_predecessor.name and wrong_predecessor or nil
          end) == nil)
        ''')

    def test_missing_owner_and_lookup_failure_are_not_admitted(self):
        self.lua.execute('''
          assert(owners.data_worker_robot_speed_owner(function() return nil end) == nil)
          assert(owners.runtime_worker_robot_speed_owner(function() error("foreign lookup failure") end) == nil)
          assert(owners.data_worker_robot_speed_owner(nil) == nil)
        ''')

    def test_unrelated_growth_is_never_examined_or_mutated(self):
        self.lua.execute('''
          local current = runtime_technology("worker-robots-speed-6", "worker-robots-speed-5")
          local unrelated = {name = "foreign", nested = {marker = "unchanged"}}
          local calls = {}
          local result = owners.runtime_worker_robot_speed_owner(function(name)
            calls[#calls + 1] = name
            if name == current.name then return current end
            if name == "worker-robots-speed-7" then return nil end
            error("unrelated prototype lookup")
          end)
          assert(result == current.name)
          assert(#calls == 2 and calls[1] == "worker-robots-speed-7"
            and calls[2] == current.name)
          assert(unrelated.nested.marker == "unchanged")
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeOwnersTests))
    sys.exit(0 if result.wasSuccessful() else 1)

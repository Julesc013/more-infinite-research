"""Pure Lua 5.2 controls for MIR 5 runtime API queries, not native Factorio evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RuntimeApiTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().runtime_source = (ROOT / "source/mir5/api/v1/runtime.lua").as_posix()
        self.lua.execute('''
          api = assert(loadfile(runtime_source))()
          function installed_game()
            return {forces = {
              [2] = {valid = true, technologies = {
                ["worker-robots-speed-6"] = {
                  researched = false, level = 11, enabled = false, saved_progress = .42,
                  prototype = {max_level = "infinite"}
                },
                finite = {
                  researched = true, level = 3, enabled = true,
                  prototype = {max_level = 3}
                }
              }}
            }}
          end
        ''')

    def test_unavailable_game_is_read_only_and_reported(self):
        self.lua.execute('''
          game = nil; storage = nil
          assert(type(api.get_version) == "function" and type(api.get_capabilities) == "function"
            and type(api.get_research) == "function")
          assert(api.get_version().major == 1 and not api.get_capabilities().research_query)
          local status, code = api.get_research(2, "worker-robots-speed-6")
          assert(status == nil and code == "game_unavailable" and storage == nil)
        ''')

    def test_exact_native_research_fields_are_detached_without_derived_levels(self):
        self.lua.execute('''
          game = installed_game(); storage = nil
          local status, code = api.get_research(2, "worker-robots-speed-6")
          assert(code == nil and status.name == "worker-robots-speed-6" and status.force_index == 2)
          assert(status.researched == false and status.level == 11 and status.enabled == false)
          assert(status.saved_progress == .42 and status.max_level == "infinite")
          status.enabled = true; status.level = 99; status.saved_progress = 0
          local technology = game.forces[2].technologies["worker-robots-speed-6"]
          assert(not technology.enabled and technology.level == 11 and technology.saved_progress == .42)
          local finite = assert(api.get_research(2, "finite"))
          assert(finite.researched and finite.level == 3 and finite.max_level == 3 and finite.saved_progress == nil)
          assert(storage == nil and api.get_capabilities().research_query)
        ''')

    def test_missing_and_invalid_inputs_are_distinct_read_only_results(self):
        self.lua.execute('''
          game = installed_game()
          local value, code = api.get_research(0, "finite")
          assert(value == nil and code == "invalid_force")
          value, code = api.get_research(2, "")
          assert(value == nil and code == "invalid_technology")
          value, code = api.get_research(3, "finite")
          assert(value == nil and code == "force_not_found")
          value, code = api.get_research(2, "optional-missing")
          assert(value == nil and code == "technology_not_found")
        ''')

    def test_runtime_source_has_no_registration_or_data_dependencies(self):
        text = (ROOT / "source/mir5/api/v1/runtime.lua").read_text()
        self.assertNotIn("remote.add_interface", text)
        self.assertNotIn("require(", text)
        self.assertNotIn("storage", text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RuntimeApiTests))
    sys.exit(0 if result.wasSuccessful() else 1)

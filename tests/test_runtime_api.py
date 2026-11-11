"""Pure Lua 5.2 controls for MIR 5 runtime API queries, not native Factorio evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RuntimeApiTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.globals().runtime_source = (ROOT / "source/api/v1/runtime.lua").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          api = assert(loadfile(runtime_source))()
          function installed_game()
            return {forces = {
              [2] = {valid = true, technologies = {
                ["worker-robots-speed-6"] = {
                  researched = false, level = 11, enabled = false, saved_progress = .42,
                  prototype = {max_level = 4294967295}
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
          assert(status.saved_progress == .42 and status.max_level == 4294967295)
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

    def test_worker_public_identity_never_projects_preservation_holder_state(self):
        for target_id in ("f200", "f210"):
            with self.subTest(target=target_id):
                self.lua.globals().query_target = target_id
                self.lua.execute('''
                  package.loaded["platform.target"] = {
                    id = query_target, research_levels = true
                  }
                  api = assert(loadfile(runtime_source))()
                  storage = nil
                  local public = "worker-robots-storage-4"
                  local holder = "mir-worker-storage-preservation-4"
                  local technologies = {
                    [public] = {
                      level = 8, researched = false, enabled = false, saved_progress = .27,
                      prototype = {max_level = 4294967295}
                    },
                    [holder] = {
                      level = 12, researched = true, enabled = true, saved_progress = .61,
                      prototype = {max_level = 4294967295}
                    }
                  }
                  game = {forces = {[2] = {valid = true, technologies = technologies}}}

                  local ordinary = assert(api.get_research(2, public))
                  assert(ordinary.name == public and ordinary.force_index == 2)
                  assert(ordinary.level == 8 and not ordinary.researched and not ordinary.enabled)
                  assert(ordinary.saved_progress == .27 and ordinary.max_level == 4294967295)
                  local preserved = assert(api.get_research(2, holder))
                  assert(preserved.name == holder and preserved.force_index == 2)
                  assert(preserved.level == 12 and preserved.researched and preserved.enabled)
                  assert(preserved.saved_progress == .61 and preserved.max_level == 4294967295)

                  ordinary.level = 99; ordinary.enabled = true; ordinary.saved_progress = 0
                  preserved.level = 99; preserved.researched = false; preserved.saved_progress = 0
                  assert(technologies[public].level == 8 and not technologies[public].enabled)
                  assert(technologies[public].saved_progress == .27)
                  assert(technologies[holder].level == 12 and technologies[holder].researched)
                  assert(technologies[holder].saved_progress == .61)

                  -- A finite provider keeps its own actual status while the old
                  -- infinite preservation holder remains separately queryable.
                  technologies[public] = {
                    level = 4, researched = true, enabled = false,
                    prototype = {max_level = 4}
                  }
                  local finite = assert(api.get_research(2, public))
                  assert(finite.name == public and finite.level == 4 and finite.max_level == 4)
                  assert(finite.researched and not finite.enabled and finite.saved_progress == nil)
                  assert(api.get_research(2, holder).level == 12)

                  technologies[public] = nil
                  local absent, code = api.get_research(2, public)
                  assert(absent == nil and code == "technology_not_found")
                  assert(api.get_research(2, holder).name == holder and storage == nil)
                ''')

    def test_stable_worker_owner_and_foreign_first_stage_remain_literal_queries(self):
        for target_id in ("f200", "f210"):
            with self.subTest(target=target_id):
                self.lua.globals().query_target = target_id
                self.lua.execute('''
                  package.loaded["platform.target"] = {id=query_target, research_levels=true}
                  api = assert(loadfile(runtime_source))()
                  storage = nil
                  local public, owner = "worker-robots-storage-4", "mir-worker-storage-default-4"
                  local technologies = {
                    [public] = {level=5, researched=false, enabled=false, saved_progress=0,
                      prototype={max_level=4294967295}},
                    [owner] = {level=8, researched=false, enabled=true, saved_progress=.42,
                      prototype={max_level=4294967295}}
                  }
                  game = {forces={[2]={valid=true, technologies=technologies}}}
                  local head, tail = assert(api.get_research(2, public)), assert(api.get_research(2, owner))
                  assert(head.name==public and head.level==5 and not head.enabled and head.saved_progress==0)
                  assert(tail.name==owner and tail.level==8 and tail.enabled and tail.saved_progress==.42)
                  tail.level=99; tail.saved_progress=0
                  assert(technologies[owner].level==8 and technologies[owner].saved_progress==.42)
                  technologies[public] = {level=4, researched=true, enabled=true,
                    prototype={max_level=4}}
                  head = assert(api.get_research(2, public))
                  assert(head.name==public and head.level==4 and head.max_level==4 and head.researched)
                  tail = assert(api.get_research(2, owner))
                  assert(tail.name==owner and tail.level==8 and tail.saved_progress==.42)
                  technologies[owner] = nil
                  local absent, code = api.get_research(2, owner)
                  assert(absent==nil and code=="technology_not_found")
                  assert(api.get_research(2, public).max_level==4 and storage==nil)
                ''')

    def test_runtime_source_has_no_registration_or_data_dependencies(self):
        text = (ROOT / "source/api/v1/runtime.lua").read_text()
        self.assertNotIn("remote.add_interface", text)
        self.assertIn('require("platform.target")', text)
        self.assertNotIn("research.generator", text)
        self.assertNotIn("storage", text)

    def test_native_custom_table_rejection_is_a_missing_force_result(self):
        self.lua.execute('''
          game = installed_game()
          local original = game.forces
          game.forces = setmetatable({}, {__index = function(_, index)
            if index > 255 then error("native force index outside allocated range") end
            return original[index]
          end})
          for _, index in ipairs({256, 2147483647, 4294967295}) do
            local value, code = api.get_research(index, "finite")
            assert(value == nil and code == "force_not_found")
          end
          local value, code = api.get_research(4294967296, "finite")
          assert(value == nil and code == "invalid_force")
          assert(api.get_research(2, "finite").researched)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RuntimeApiTests))
    sys.exit(0 if result.wasSuccessful() else 1)

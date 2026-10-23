"""Pure Lua 5.2 host-stage parse checks for MIR 5 API consumer controls."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_API = Path("C:/Program Files/Steam/steamapps/common/Factorio/doc-html/runtime-api.json")


class FixtureControlHostStageTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r"""
          function parse_consumer_control(path, active_mir)
            local callbacks = {}
            local forbidden = {reads = {}, writes = {}}
            local active_mods = {base = "2.1.23"}
            if active_mir then active_mods["more-infinite-research"] = "5.0.21000" end

            local remote_probe = setmetatable({}, {
              __index = function() error("control parse accessed remote") end
            })
            local environment = {
              script = {
                active_mods = active_mods,
                on_init = function(callback) callbacks.on_init = callback end,
                on_load = function(callback) callbacks.on_load = callback end,
                on_configuration_changed = function(callback) callbacks.on_configuration_changed = callback end,
                on_event = function(event, callback)
                  callbacks.on_event = {event = event, callback = callback}
                end
              },
              defines = {events = {on_tick = 1}},
              remote = remote_probe,
              helpers = {table_to_json = function() return "{}" end},
              log = function() end,
              require = function() error("control parse imported a module") end
            }
            environment._G = environment
            setmetatable(environment, {
              __index = function(_, key)
                if key == "mods" then
                  forbidden.reads.mods = (forbidden.reads.mods or 0) + 1
                  return nil
                end
                if key == "game" or key == "storage" then
                  forbidden.reads[key] = (forbidden.reads[key] or 0) + 1
                  return nil
                end
                return _G[key]
              end,
              __newindex = function(table, key, value)
                if key == "game" or key == "storage" then
                  forbidden.writes[key] = value
                  return
                end
                rawset(table, key, value)
              end
            })

            local chunk, message = loadfile(path, "t", environment)
            if chunk == nil then return false, message, callbacks, forbidden, environment end
            local ok, result = pcall(chunk)
            return ok, result, callbacks, forbidden, environment
          end

          function assert_consumer_control_parse(path, active_mir, expected_callbacks)
            local ok, result, callbacks, forbidden, environment =
              parse_consumer_control(path, active_mir)
            assert(ok, tostring(result))
            assert(rawget(environment, "mods") == nil, "control created a mods global")
            assert(rawget(environment, "game") == nil and rawget(environment, "storage") == nil,
              "control created a game or storage global")
            assert(forbidden.reads.game == nil and forbidden.reads.storage == nil,
              "control parsed against game or storage")
            assert(forbidden.writes.game == nil and forbidden.writes.storage == nil,
              "control wrote game or storage")
            if expected_callbacks then
              assert(type(callbacks.on_init) == "function")
              assert(type(callbacks.on_load) == "function")
              assert(type(callbacks.on_configuration_changed) == "function")
              assert(type(callbacks.on_event) == "table"
                and callbacks.on_event.event == 1
                and type(callbacks.on_event.callback) == "function")
            else
              assert(next(callbacks) == nil, "optional consumer registered callbacks while MIR was absent")
            end
            return forbidden.reads.mods
          end
        """)

    def control(self, fixture):
        return (ROOT / "tests/mir5/fixtures" / fixture / "control.lua").as_posix()

    def test_lua_bootstrap_active_mods_is_the_pinned_runtime_dictionary(self):
        if not RUNTIME_API.is_file():
            self.skipTest("local Factorio runtime API documentation is not installed")
        document = json.loads(RUNTIME_API.read_text(encoding="utf-8"))
        self.assertEqual(document["application_version"], "2.1.23")
        bootstrap = next(row for row in document["classes"] if row["name"] == "LuaBootstrap")
        active_mods = next(field for field in bootstrap["attributes"] if field["name"] == "active_mods")
        self.assertEqual(
            active_mods["description"],
            "A dictionary listing the names of all currently active mods and mapping them to their version.",
        )
        self.assertFalse(active_mods["optional"])
        self.assertEqual(active_mods["read_type"], {
            "complex_type": "dictionary", "key": "string", "value": "string",
        })

    def test_both_controls_parse_with_mods_nil_and_runtime_mir_present(self):
        for fixture in ("api-alpha", "api-beta"):
            self.lua.globals().fixture_control = self.control(fixture)
            reads_mods = self.lua.eval(
                "assert_consumer_control_parse(fixture_control, true, true)"
            )
            self.assertIsNone(reads_mods, fixture)

    def test_alpha_control_keeps_its_required_runtime_registration_when_mir_is_absent(self):
        self.lua.globals().fixture_control = self.control("api-alpha")
        reads_mods = self.lua.eval(
            "assert_consumer_control_parse(fixture_control, false, true)"
        )
        self.assertIsNone(reads_mods)

    def test_beta_control_returns_before_runtime_registration_when_mir_is_absent(self):
        self.lua.globals().fixture_control = self.control("api-beta")
        reads_mods = self.lua.eval(
            "assert_consumer_control_parse(fixture_control, false, false)"
        )
        self.assertIsNone(reads_mods)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(FixtureControlHostStageTests))
    sys.exit(0 if result.wasSuccessful() else 1)

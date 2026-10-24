"""Lua 5.2 controls for the MIR 5 SDK examples and annotations.

These execute the package-excluded SDK examples against the current public
MIR data/runtime modules with small native-shaped host doubles. They are not
Factorio engine, save/reload, client, or modpack qualification.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAYER_ROOT = ROOT / "source"
SDK_ROOT = ROOT / "sdk"
DATA_MODULE = "__more-infinite-research__.api.v1.data"
RUNTIME_INTERFACE = "more-infinite-research.api.v1"
REQUIRED_NAME = "mir-api-example-required-gears-1"
OPTIONAL_NAME = "mir-api-example-optional-cable-1"


class SdkTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER_ROOT.as_posix()
        self.lua.globals().data_source = (PLAYER_ROOT / "api/v1/data.lua").as_posix()
        self.lua.globals().runtime_source = (PLAYER_ROOT / "api/v1/runtime.lua").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          package.preload["__more-infinite-research__/platform/target"] = function()
            return assert(loadfile(player_root .. "/platform/target.lua"))()
          end
          package.preload["__more-infinite-research__.api.v1.data"] = function()
            return assert(loadfile(data_source))()
          end

          function sdk_world()
            local raw = {
              technology = {automation = {}},
              tool = {["automation-science-pack"] = {}},
              recipe = {["iron-gear-wheel"] = {}, ["copper-cable"] = {}}
            }
            local stage = {raw = raw, writes = 0}
            function stage:extend(prototypes)
              self.writes = self.writes + 1
              for _, prototype in ipairs(prototypes) do
                self.raw[prototype.type] = self.raw[prototype.type] or {}
                self.raw[prototype.type][prototype.name] = prototype
              end
            end
            return stage
          end

          function run_sdk_file(path)
            return assert(loadfile(path))()
          end

          function install_runtime_interface()
            local api = assert(loadfile(runtime_source))()
            remote = {interfaces = {["more-infinite-research.api.v1"] = api}}
            function remote.call(interface_name, method, ...)
              local interface = remote.interfaces[interface_name]
              assert(interface ~= nil, "missing native-shaped remote interface")
              local callback = interface[method]
              assert(type(callback) == "function", "unknown native-shaped remote method")
              return callback(...)
            end
            return api
          end

          function installed_runtime_game()
            local technology = {
              researched = false,
              level = 1,
              enabled = true,
              saved_progress = .5,
              prototype = {max_level = 4294967295}
            }
            local force = {valid = true, index = 1, technologies = {
              ["mir-api-example-required-gears-1"] = technology
            }}
            return {forces = {player = force, [1] = force}}, force, technology
          end
        ''')

    def sdk_path(self, *parts):
        return (SDK_ROOT.joinpath(*parts)).as_posix()

    def fresh_data_stage(self):
        self.lua.execute(
            'data = sdk_world(); mods = {["more-infinite-research"] = "5.0.21000"}; '
            'package.loaded["__more-infinite-research__.api.v1.data"] = nil'
        )

    def test_example_metadata_declares_required_and_optional_dependencies(self):
        required = json.loads((SDK_ROOT / "examples/required/info.json").read_text(encoding="utf-8"))
        optional = json.loads((SDK_ROOT / "examples/optional/info.json").read_text(encoding="utf-8"))
        self.assertIn("more-infinite-research >= 5.0.21000", required["dependencies"])
        self.assertIn("? more-infinite-research >= 5.0.21000", optional["dependencies"])
        self.assertNotEqual(required["name"], optional["name"])

    def test_required_and_optional_final_fixes_publish_distinct_native_effects(self):
        self.fresh_data_stage()
        self.lua.globals().required_example = self.sdk_path("examples/required/data-final-fixes.lua")
        self.lua.globals().optional_example = self.sdk_path("examples/optional/data-final-fixes.lua")
        self.lua.execute(r'''
          run_sdk_file(required_example)
          run_sdk_file(optional_example)
          assert(data.writes == 2)
          local required = assert(data.raw.technology["mir-api-example-required-gears-1"])
          local optional = assert(data.raw.technology["mir-api-example-optional-cable-1"])
          assert(required ~= optional and required.unit.count_formula == "100 * 2^(L-1)")
          assert(optional.unit.count_formula == "100 * 2^(L-1)")
          assert(#required.effects == 1 and required.effects[1].type == "change-recipe-productivity"
            and required.effects[1].recipe == "iron-gear-wheel" and required.effects[1].change == .01)
          assert(#optional.effects == 1 and optional.effects[1].type == "change-recipe-productivity"
            and optional.effects[1].recipe == "copper-cable" and optional.effects[1].change == .01)
        ''')

    def test_optional_example_is_inert_before_import_when_mir_is_absent(self):
        self.lua.globals().optional_example = self.sdk_path("examples/optional/data-final-fixes.lua")
        self.lua.execute(r'''
          data = sdk_world(); mods = {}
          package.loaded["__more-infinite-research__.api.v1.data"] = nil
          package.preload["__more-infinite-research__.api.v1.data"] = function()
            error("optional SDK example imported MIR while absent")
          end
          run_sdk_file(optional_example)
          assert(data.writes == 0)
          assert(package.loaded["__more-infinite-research__.api.v1.data"] == nil)
        ''')

    def test_data_metadata_is_detached_and_reports_only_implemented_capabilities(self):
        self.fresh_data_stage()
        self.lua.execute(r'''
          local api = require("__more-infinite-research__.api.v1.data")
          local version = api.get_version()
          assert(version.major == 1 and version.minor == 0 and version.product == "5.0.21000")
          version.major = 99
          assert(api.get_version().major == 1)

          local capabilities = api.get_capabilities()
          assert(capabilities.technology_creation and capabilities.technology_family
            and capabilities.recipe_productivity and capabilities.research_query == false)
          assert(capabilities.future_sdk_operation == nil)
          capabilities.recipe_productivity = false
          assert(api.get_capabilities().recipe_productivity == true)
        ''')

    def test_required_runtime_example_parses_then_negotiates_and_queries_actual_runtime_api(self):
        self.lua.globals().required_control = self.sdk_path("examples/required/control.lua")
        self.lua.execute(r'''
          local callbacks = {}
          script = {on_init = function(callback) callbacks.on_init = callback end}
          game = nil
          storage = nil
          assert(loadfile(required_control))()
          assert(type(callbacks.on_init) == "function" and game == nil and storage == nil)

          local api = install_runtime_interface()
          assert(api.get_capabilities().research_query == false)
          game, force, technology = installed_runtime_game()
          callbacks.on_init()
          assert(technology.researched == false and technology.level == 1 and technology.enabled == true)
          assert(storage == nil)

          local status = assert(remote.call("more-infinite-research.api.v1", "get_research", 1,
            "mir-api-example-required-gears-1"))
          assert(status.name == "mir-api-example-required-gears-1" and status.force_index == 1
            and status.level == 1 and status.saved_progress == .5 and status.max_level == 4294967295)
          status.level = 99; status.enabled = false; status.saved_progress = 0; status.max_level = 1
          local fresh = assert(remote.call("more-infinite-research.api.v1", "get_research", 1,
            "mir-api-example-required-gears-1"))
          assert(fresh.level == 1 and fresh.enabled == true and fresh.saved_progress == .5
            and fresh.max_level == 4294967295)
          assert(remote.call("more-infinite-research.api.v1", "get_capabilities").future_sdk_operation == nil)
        ''')

    def test_runtime_unknown_method_and_missing_technology_remain_nonmutating(self):
        self.lua.execute(r'''
          local api = install_runtime_interface()
          game, force, technology = installed_runtime_game()
          local missing, code = remote.call("more-infinite-research.api.v1", "get_research", 1,
            "optional-sdk-technology-is-absent")
          assert(missing == nil and code == "technology_not_found")
          local ok = pcall(function()
            remote.call("more-infinite-research.api.v1", "future_sdk_operation")
          end)
          assert(not ok)
          assert(technology.researched == false and technology.level == 1 and storage == nil)
          local unavailable_game = game
          game = nil
          local unavailable, unavailable_code = api.get_research(1, "mir-api-example-required-gears-1")
          assert(unavailable == nil and unavailable_code == "game_unavailable")
          game = unavailable_game
        ''')

    def test_annotations_describe_the_actual_native_infinite_marker(self):
        annotations = (SDK_ROOT / "api-v1.lua").read_text(encoding="utf-8")
        self.assertIn("---@alias MIRNativeMaxLevel integer|string", annotations)
        self.assertIn("---@field max_level MIRNativeMaxLevel", annotations)
        self.assertNotIn("---@field max_level integer", annotations)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SdkTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

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
    def test_native_optional_absence_observer_checks_exact_read_only_closure(self):
        path = ROOT / 'tests/fixtures/api-optional-absence/control.lua'
        self.lua.execute(r'''
          function optional_absence_observer(path, base_version, opponent)
            local callback, report
            local active = {base=base_version, ['mir-fixture-mir5-api-beta']='0.1.0',
              ['mir-fixture-mir5-api-optional-absence']='0.1.0',
              ['mir-fixture-mir5-active-mods-observer']='0.1.0'}
            local interface, technology, productivity = nil, nil, 0
            if opponent == 'mir' then active['more-infinite-research']='5.0.20000'
            elseif opponent == 'consumer' then active['mir-fixture-mir5-api-beta']=nil
            elseif opponent == 'interface' then interface={}
            elseif opponent == 'technology' then technology={}
            elseif opponent == 'effect' then productivity=.01 end
            local function readonly(value)
              return setmetatable({}, {__index=value,__newindex=function()error('native write')end})
            end
            local environment = {
              script={active_mods=active,on_init=function(value)callback=value end},
              remote={interfaces=readonly({['more-infinite-research.api.v1']=interface}),
                call=function()error('unexpected remote call')end},
              game={forces={player=readonly({valid=true,technologies=readonly({['mir-api-fixture-beta-cable-1']=technology}),
                recipes=readonly({['copper-cable']=readonly({productivity_bonus=productivity})})})}},
              helpers={table_to_json=function(value)report=value;return '{}' end},
              log=function()end, storage=setmetatable({}, {__index=function()error('storage read')end,
                __newindex=function()error('storage write')end})
            }
            environment._G=environment;setmetatable(environment,{__index=_G})
            assert(loadfile(path,'t',environment))()
            local ok, message = pcall(callback)
            return {ok=ok,message=message,report=report}
          end
        ''')
        for base_version in ('2.0.77', '2.1.23'):
            for opponent in ('', 'base', 'mir', 'consumer', 'interface', 'technology', 'effect'):
                with self.subTest(base_version=base_version, opponent=opponent):
                    observed_base = '2.1.22' if opponent == 'base' else base_version
                    result = self.lua.eval('optional_absence_observer')(path.as_posix(), observed_base, opponent)
                    self.assertEqual(not opponent, result['ok'], result['message'])
                    if not opponent:
                        self.assertFalse(result['report']['mir_present'])
                        self.assertEqual(0, result['report']['cable_productivity_bonus'])
        f200_profile = json.loads((ROOT / 'tests/profiles/api-optional-absence-f200-2077.json').read_text())
        f210_profile = json.loads((ROOT / 'tests/profiles/api-optional-absence-f210-2123.json').read_text())
        for profile, target, base_version, observer_sha256 in (
            (f200_profile, 'f200', '2.0.77', '723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87'),
            (f210_profile, 'f210', '2.1.23', '2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C'),
        ):
            with self.subTest(profile=target):
                self.assertEqual(target, profile['target'])
                self.assertEqual(4, len(profile['mods']))
                self.assertEqual(base_version, profile['mods'][0]['version'])
                self.assertNotIn('more-infinite-research', {row['name'] for row in profile['mods']})
                self.assertEqual(observer_sha256, profile['archive_sha256']['mir-fixture-mir5-active-mods-observer_0.1.0.zip'])
        f210_info = json.loads((ROOT / 'tests/fixtures/api-optional-absence/info-f210.json').read_text())
        self.assertEqual('2.1', f210_info['factorio_version'])
        self.assertEqual([
            'base >= 2.1.23',
            'mir-fixture-mir5-api-beta = 0.1.0',
            'mir-fixture-mir5-active-mods-observer = 0.1.0',
        ], f210_info['dependencies'])

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
          assert(required ~= optional and required.unit.count == 100 and optional.unit.count == 100)
          assert(required.icon == "__more-infinite-research__/thumbnail.png" and required.icon_size == 288)
          assert(optional.icon == "__more-infinite-research__/thumbnail.png" and optional.icon_size == 288)
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

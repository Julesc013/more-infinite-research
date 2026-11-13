"""Lifecycle, opposing settings and read-only cold controls; no native result."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/profile-native-runner"
PERCENTAGES = {
    "mir-pipeline-extent-multiplier": 123.45,
    "mir-prototype-productivity-cap": 4321.5,
    "mir-prototype-efficiency-cap": -83.25,
    "mir-prototype-pollution-cap": -91.125,
    "mir-prototype-speed-floor": -75.5,
    "mir-prototype-speed-cap": 1234.5,
    "mir-prototype-quality-cap": 678.9,
    "mir-recycling-return-chance": 12.34,
}


class ProfileNativeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute("""
          storage={}; reports={}; saves=0; forbid_save=false
          defines={events={on_tick=1}}
          script={on_init=function(f) init=f end,on_load=function(f) load=f end,
            on_event=function(event,f) assert(event==1);tick=f end}
          log=function(line) assert(line:find('[MIR5_NATIVE_FIXTURE] RESULT ',1,true)) end
          helpers={decode_string=function(value) assert(value=='full-profile');return 'json' end,
            json_to_table=function(value) assert(value=='json');return export end,
            table_to_json=function(value) reports[#reports+1]=value;return '<json>' end}
          native={stage='runtime',family='f200',mode='numeric',maximum_productivity=43.215,
            recycling_amount=1,recycling_probability=.1234000027179718,receiver_limits_supported=false}
          wire='MIRSET1:full-profile'
          remote={call=function(interface,method,options)
            if interface=='mir_profile_native_witness' then assert(method=='observe');return native end
            assert(interface=='more-infinite-research-settings' and method=='export_string')
            assert(type(options)=='table');return wire
          end}
          game={server_save=function(name)
            assert(not forbid_save,'unexpected cold save')
            assert(name=='mir5-native-complete');saves=saves+1
          end}
          function readonly(value)
            if type(value)~='table' then return value end
            local proxy={}
            return setmetatable(proxy,{
              __index=function(_,key)return readonly(value[key])end,
              __newindex=function()error('read-only-cold-write')end,
              __pairs=function()
                local key=nil
                return function()key=next(value,key);if key~=nil then return key,readonly(value[key])end end
              end})
          end
        """)
        exported = self.lua.table_from(PERCENTAGES)
        self.lua.globals()["export"] = self.lua.table_from({"settings": exported})
        self.lua.execute("dofile(actor_path)")

    def test_initial_save_once_and_two_readonly_cold_observations(self):
        self.lua.execute("""
          init();assert(storage.mir_profile_native_lifecycle.phase=='pending');assert(saves==0)
          tick();tick();assert(saves==1 and #reports==1)
          assert(reports[1].case=='profile-native-numeric' and reports[1].stage=='initial')
          assert(reports[1].ordinary_research_completion==false)
          assert(storage.mir_profile_native_lifecycle.phase=='completed')
          forbid_save=true;storage=readonly(storage)
          for ordinal=1,2 do
            load();tick();tick();assert(saves==1 and #reports==ordinal+1)
            assert(reports[ordinal+1].stage=='reload' and reports[ordinal+1].status=='passed')
          end
        """)

    def test_wrong_export_refuses_before_acquiring_completed_state_or_save(self):
        for name in PERCENTAGES:
            with self.subTest(name=name):
                self.setUp()
                self.lua.globals()["export"]["settings"][name] = PERCENTAGES[name] + 1
                self.lua.execute("""
                  init();local ok,reason=pcall(tick);assert(not ok)
                  assert(tostring(reason):find('effective percentage',1,true))
                  assert(saves==0 and #reports==0 and storage.mir_profile_native_lifecycle.phase=='pending')
                """)

    def test_bad_profile_framing_refuses_before_save(self):
        self.lua.execute("""
          init();wire='not-a-profile';local ok,reason=pcall(tick)
          assert(not ok and tostring(reason):find('export framing',1,true))
          assert(saves==0 and #reports==0 and storage.mir_profile_native_lifecycle.phase=='pending')
        """)

    def test_changed_cold_native_snapshot_cannot_be_relabelled_passed(self):
        self.lua.execute("""
          init();tick();storage.mir_profile_native_lifecycle.snapshot.native.recycling_amount=2
          -- Copy the next observation rather than aliasing the saved witness.
          native={stage='runtime',family='f200',mode='numeric',maximum_productivity=43.215,
            recycling_amount=1,recycling_probability=.1234000027179718,receiver_limits_supported=false}
          forbid_save=true;load();local ok,reason=pcall(tick)
          assert(not ok and tostring(reason):find('cold value',1,true))
          assert(saves==1 and #reports==1)
        """)

    def test_settings_stage_import_opposes_each_raw_dropdown(self):
        self.lua.execute("data={raw={['string-setting']={}}}")
        strings = self.lua.globals().data["raw"]["string-setting"]
        for name in [*PERCENTAGES, "mir-settings-profile-import"]:
            strings[name] = self.lua.table_from({"default_value": "previous-default"})
        self.lua.globals().settings_path = (FIXTURE / "settings-updates.lua").as_posix()
        self.lua.execute("dofile(settings_path)")
        imported = json.loads(strings["mir-settings-profile-import"]["default_value"])
        self.assertEqual(imported["settings"], PERCENTAGES)
        for name, value in PERCENTAGES.items():
            self.assertIsInstance(strings[name]["default_value"], str)
            self.assertNotEqual(strings[name]["default_value"], value)

    def test_metadata_pins_the_selected_available_f200_boundary(self):
        info = json.loads((FIXTURE / "info.json").read_text())
        self.assertEqual(info["factorio_version"], "2.0")
        self.assertEqual(info["dependencies"], [
            "base = 2.0.77", "quality = 2.0.77", "more-infinite-research = 5.0.20014",
            "mir-fixture-mir5-profile-native-witness = 0.1.0",
        ])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ProfileNativeRunnerTests))
    sys.exit(0 if result.wasSuccessful() else 1)

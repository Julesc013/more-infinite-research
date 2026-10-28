"""Independent controls for the exact published MIR 1.2.0 F200 source fixture."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-120-source"
PROFILE = ROOT / "tests/profiles/migration-origins-1.2.0-source-f200-2077.json"
ORIGINAL_ARCHIVE = "880C137F7AB35FE7AF1DA5538BFA91F620C80785134DB488800352DD6154AB22"
FACTS_SHA256 = "A017240FA9AF6E438462F5417397DBC3768AE1CC0BDB0DF5EE9D5313E593F98F"
# This is the complete static fixture catalogue rendered once from the
# independently captured 7714/C512 selected-native-facts projection.  It is
# deliberately pinned here rather than reconstructed from current MIR code.
CATALOGUE_SHA256 = "FAA7EA3CFE3FD0657845F4697A7214F442621A1AC1C380EAC18BAC3A1BF91A51"
FIXTURE_NAME = "mir-fixture-mir5-migration-origin-f200-120-source"


def py(value):
    if hasattr(value, "items"):
        items = list(value.items())
        keys = [key for key, _ in items]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in items}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class MigrationOriginF200120SourceControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        cls.lua.execute("migration_origin_120_catalogue=assert(loadfile(catalogue_path))()")
        cls.catalogue = py(cls.lua.globals().migration_origin_120_catalogue)

    def mods(self):
        return {"base": "2.0.77", "more-infinite-research": "1.2.0", FIXTURE_NAME: "0.1.0"}

    def settings_raw(self):
        raw = {"sentinel": {"unchanged": 37}}
        for name, expected in self.catalogue["settings"].items():
            raw.setdefault(expected["kind"], {})[name] = {
                "type": expected["kind"], "name": name, "setting_type": "startup",
                "default_value": expected["default_value"],
            }
        return raw

    def data_raw(self):
        technology = copy.deepcopy(self.catalogue["rows"])
        technology.update(copy.deepcopy(self.catalogue["weapons"]))
        for name, row in technology.items():
            row["type"] = "technology"
            row["name"] = name
        return {"technology": technology, "sentinel": {"unchanged": 41}}

    def run_settings(self, raw):
        self.lua.globals().settings_path = (FIXTURE / "settings-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          function migration_origin_120_run_settings(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_120_run_settings")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, self.mods())))

    def run_data(self, raw, settings=None):
        if settings is None:
            settings = {name: row["default_value"] for name, row in self.catalogue["settings"].items()}
        self.lua.globals().data_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          function migration_origin_120_run_data(raw, mods, settings_values)
            local env={data={raw=raw},mods=mods,settings={startup={}}}
            for name,value in pairs(settings_values) do env.settings.startup[name]={value=value} end
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_120_run_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, self.mods()), lua(self.lua, settings)))

    def test_frozen_native_catalogue_identity_and_exact_source_scope(self):
        self.assertEqual(CATALOGUE_SHA256, hashlib.sha256((FIXTURE / "catalogue.lua").read_bytes()).hexdigest().upper())
        self.assertEqual(34, len(self.catalogue["rows"]))
        self.assertEqual({"bool-setting": 45, "int-setting": 88, "double-setting": 44}, self.catalogue["setting_counts"])
        self.assertEqual(177, len(self.catalogue["settings"]))
        self.assertEqual("recipe-prod-research_gears-1", self.catalogue["direct"])
        self.assertEqual("weapon-shooting-speed-1", self.catalogue["finite_weapon_seed"])
        self.assertEqual(("rocket", "cannon-shell", "electric", "flamethrower"), tuple(self.catalogue["gun_categories"]))
        self.assertEqual({"bullet": .1, "shotgun-shell": .1}, self.catalogue["finite_owner_gun_speed"])
        self.assertEqual(7, len(self.catalogue["weapons"]))
        self.assertEqual("8000 * 2^(L-1)", self.catalogue["source_formula"])
        self.assertEqual(60, self.catalogue["source_time"])
        self.assertEqual(ORIGINAL_ARCHIVE, "880C137F7AB35FE7AF1DA5538BFA91F620C80785134DB488800352DD6154AB22")
        self.assertEqual(FACTS_SHA256, "A017240FA9AF6E438462F5417397DBC3768AE1CC0BDB0DF5EE9D5313E593F98F")

    def test_separate_stages_refuse_wrong_numeric_settings_and_incomplete_cannon_owner(self):
        accepted_settings = self.run_settings(self.settings_raw())
        self.assertTrue(accepted_settings["ok"], accepted_settings["message"])
        self.assertEqual(37, accepted_settings["raw"]["sentinel"]["unchanged"])
        self.assertNotIn("technology", accepted_settings["raw"])

        accepted_data = self.run_data(self.data_raw())
        self.assertTrue(accepted_data["ok"], accepted_data["message"])
        direct = accepted_data["raw"]["technology"][self.catalogue["direct"]]
        self.assertEqual((1, None, 1), (direct["unit"]["count"], direct["unit"].get("count_formula"), direct["unit"]["time"]))
        self.assertEqual(41, accepted_data["raw"]["sentinel"]["unchanged"])
        self.assertNotIn("bool-setting", accepted_data["raw"])

        double_name = next(name for name, row in self.catalogue["settings"].items() if row["kind"] == "double-setting")
        wrong_numeric = self.settings_raw()
        wrong_numeric["double-setting"][double_name]["default_value"] += 1
        missing_cannon = self.data_raw()
        rocket = missing_cannon["technology"]["recipe-prod-research_rocket_shooting_speed-1"]
        rocket["effects"] = [effect for effect in rocket["effects"] if effect.get("ammo_category") != "cannon-shell"]
        wrong_weapon = self.data_raw()
        wrong_weapon["technology"]["weapon-shooting-speed-1"]["effects"][0]["modifier"] = .05
        wrong_runtime = {name: row["default_value"] for name, row in self.catalogue["settings"].items()}
        wrong_runtime[double_name] += 1
        for label, runner, candidate in (
            ("wrong-numeric-default", self.run_settings, wrong_numeric),
            ("missing-combined-cannon", self.run_data, missing_cannon),
            ("wrong-finite-effect", self.run_data, wrong_weapon),
            ("wrong-effective-numeric", lambda raw: self.run_data(raw, wrong_runtime), self.data_raw()),
        ):
            with self.subTest(label=label):
                before = copy.deepcopy(candidate)
                result = runner(candidate)
                self.assertFalse(result["ok"], result["message"])
                self.assertEqual(before, result["raw"])

    def test_control_retains_full_gun_snapshot_and_source_only_boundaries(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("finite_weapon_owner_seeds", control)
        self.assertIn("source_cannon_gun_speed", control)
        self.assertIn("foreign.research_queue, foreign.research_progress = {direct, probe}, .42", control)
        self.assertIn("saved_progress = .27", control)
        self.assertIn("game.server_save(SAVE)", control)
        self.assertIn('marker("reload", value)', control)
        self.assertIn("assert_same_snapshot", control)
        self.assertIn("force.get_gun_speed_modifier(category)", control)
        self.assertNotIn('more-infinite-research"] ~= "5.', control)
        self.assertNotIn("count_formula = nil\n  direct.unit.count = 1\n  direct.unit.time = 60", control)

    def test_runtime_snapshot_refuses_an_incomplete_cannon_contribution(self):
        self.lua.globals().fixture_control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          function migration_origin_120_incomplete_gun_snapshot()
            local callbacks={events={}}
            local env={script={on_init=function(fn)callbacks.init=fn end,on_load=function()end,
              on_event=function(event,fn)callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            assert(loadfile(fixture_control_path,"t",env))()
            local function upvalue(fn, wanted)
              for index=1,64 do
                local name,value=debug.getupvalue(fn,index)
                if name==nil then break end
                if name==wanted then return value end
              end
              error("missing upvalue " .. wanted)
            end
            local catalogue=env.require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
            local rows,weapons,technologies,recipes={}, {}, {}, {}
            for name,row in pairs(catalogue.rows) do
              rows[#rows+1]=name
              technologies[name]={name=name,valid=true,level=row.level,researched=false,enabled=true,
                visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295,effects=row.effects}}
              for _,effect in ipairs(row.effects) do
                if effect.type=="change-recipe-productivity" then recipes[effect.recipe]={valid=true,productivity_bonus=0} end
              end
            end
            for name,row in pairs(catalogue.weapons) do
              weapons[#weapons+1]=name
              technologies[name]={name=name,valid=true,level=1,researched=false,enabled=true,
                visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295,effects=row.effects}}
            end
            local force={technologies=technologies,recipes=recipes,worker_robots_battery_modifier=.1,guns={}}
            for category,value in pairs(catalogue.direct_gun_speed) do force.guns[category]=value end
            for category,value in pairs(catalogue.finite_owner_gun_speed) do force.guns[category]=value end
            force.get_gun_speed_modifier=function(category) return force.guns[category] or 0 end
            local completed=upvalue(callbacks.events[2],"assert_completed")
            local same=upvalue(completed,"assert_same_snapshot")
            local snapshot=upvalue(same,"snapshot")
            local expected=snapshot(force,rows,weapons)
            force.guns["cannon-shell"]=0
            local ok,message=pcall(same,force,rows,weapons,expected,"incomplete")
            return {ok=ok,message=tostring(message)}
          end
        ''')
        result = py(self.lua.eval("migration_origin_120_incomplete_gun_snapshot")())
        self.assertFalse(result["ok"])
        self.assertIn("gun speed changed: cannon-shell", result["message"])

    def test_profile_and_fixture_are_source_only_preparation(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual((FIXTURE_NAME, "0.1.0", "2.0"), (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual({"README.md", "catalogue.lua", "control.lua", "data-final-fixes.lua", "settings-final-fixes.lua", "info.json"},
                         {path.name for path in FIXTURE.iterdir() if path.is_file()})
        self.assertFalse(PROFILE.exists(), "profile is created only after the exact raw-Git fixture archive is frozen")
        self.assertIn("not a migration pass", (FIXTURE / "README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    MigrationOriginF200120SourceControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginF200120SourceControls))
    sys.exit(0 if result.wasSuccessful() else 1)

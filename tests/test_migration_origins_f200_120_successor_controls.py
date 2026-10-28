"""Independent controls for the protected MIR 1.2.0 direct-successor fixture."""
import argparse
import copy
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-120-successor"
SOURCE_FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-120-source"
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


class MigrationOriginF200120SuccessorControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        cls.lua.execute("migration_origin_120_successor_catalogue=assert(loadfile(catalogue_path))()")
        cls.catalogue = py(cls.lua.globals().migration_origin_120_successor_catalogue)

    def target_mods(self, target):
        metadata = self.catalogue["targets"][target]
        return {
            "base": metadata["base"],
            "more-infinite-research": metadata["mir"],
            FIXTURE_NAME: metadata["fixture"],
            "mir-fixture-mir5-active-mods-observer": "0.1.0",
        }

    def data_raw(self):
        def technology(name, level=1, maximum="infinite", effects=None):
            return {"type": "technology", "name": name, "level": level, "max_level": maximum,
                    "upgrade": True, "effects": copy.deepcopy(effects or [])}

        raw = {"technology": {"sentinel": {"unchanged": 31}}}
        raw["technology"][self.catalogue["source_combined"]] = technology(
            self.catalogue["source_combined"], effects=self.catalogue["split_effects"]["rocket"])
        raw["technology"][self.catalogue["cannon"]] = technology(
            self.catalogue["cannon"], effects=self.catalogue["split_effects"]["cannon"])
        raw["technology"][self.catalogue["direct"]] = technology(
            self.catalogue["direct"], effects=[{"type": "change-recipe-productivity",
                                                   "recipe": self.catalogue["gear_recipe"], "change": .1}])
        raw["technology"][self.catalogue["direct"]]["unit"] = {
            "count": 8000, "count_formula": "8000 * 2^(L-1)", "time": 60,
            "ingredients": [["automation-science-pack", 1]],
        }
        for name, row in self.catalogue["current_runtime"].items():
            raw["technology"][name] = technology(name, row["level"], row["maximum"], row["effects"])
        return raw

    def run_data(self, raw, target):
        self.lua.globals().data_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          function migration_origin_120_successor_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_120_successor_data")(lua(self.lua, copy.deepcopy(raw)),
                                                                          lua(self.lua, self.target_mods(target))))

    def test_catalogue_pins_source_identity_and_separate_current_finite_vectors(self):
        catalogue = self.catalogue
        self.assertEqual("mir5_migration_origin_f200_120_source", catalogue["storage_key"])
        self.assertEqual(FIXTURE_NAME, catalogue["fixture"])
        self.assertEqual("recipe-prod-research_rocket_shooting_speed-1", catalogue["source_combined"])
        self.assertEqual("recipe-prod-research_cannon_shooting_speed-1", catalogue["cannon"])
        self.assertEqual(34, catalogue["source_rows"])
        self.assertEqual(7, catalogue["source_weapons"])
        self.assertEqual(("weapon-shooting-speed-1", "weapon-shooting-speed-2", "weapon-shooting-speed-3",
                          "weapon-shooting-speed-4", "weapon-shooting-speed-5", "weapon-shooting-speed-6"),
                         tuple(catalogue["source_finite_seed_sets"]["player"]))
        self.assertEqual(("weapon-shooting-speed-1",), tuple(catalogue["source_finite_seed_sets"]["foreign"]))
        self.assertEqual({}, catalogue["source_finite_seed_sets"]["detached"])
        self.assertEqual(
            [("rocket", .5)],
            [(row["ammo_category"], row["modifier"])
             for row in catalogue["current_runtime"]["weapon-shooting-speed-3"]["effects"] if row["ammo_category"] == "rocket"])
        self.assertEqual(
            [("cannon-shell", .8), ("rocket", .9)],
            [(row["ammo_category"], row["modifier"])
             for row in catalogue["current_runtime"]["weapon-shooting-speed-5"]["effects"]
             if row["ammo_category"] in {"cannon-shell", "rocket"}])
        self.assertEqual(
            [("cannon-shell", 1.5), ("rocket", 1.3)],
            [(row["ammo_category"], row["modifier"])
             for row in catalogue["current_runtime"]["weapon-shooting-speed-6"]["effects"]
             if row["ammo_category"] in {"cannon-shell", "rocket"}])

    def test_source_fixture_contract_remains_separate_and_protected(self):
        source_control = (SOURCE_FIXTURE / "control.lua").read_text(encoding="utf-8")
        successor = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local KEY = "mir5_migration_origin_f200_120_source"', source_control)
        self.assertIn("source_combined_signature", successor)
        self.assertIn("assert_source_before(value)", successor)
        self.assertIn("assert_current_weapons", successor)
        self.assertIn("saved - (old[category] or 0) + (current[category] or 0)", successor)
        self.assertIn("candidate lab", successor)
        self.assertIn("game.server_save(C.save)", successor)
        self.assertIn('marker("reload"', successor)

    def test_f210_data_guard_admits_only_the_exact_split_and_finite_base_vectors(self):
        raw = self.data_raw()
        result = self.run_data(raw, "f210")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(31, result["raw"]["technology"]["sentinel"]["unchanged"])
        gear = result["raw"]["technology"][self.catalogue["direct"]]
        self.assertEqual((1, None, 1), (gear["unit"]["count"], gear["unit"].get("count_formula"), gear["unit"]["time"]))

    def test_f200_data_guard_admits_the_same_direct_protocol(self):
        result = self.run_data(self.data_raw(), "f200")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("infinite", result["raw"]["technology"][self.catalogue["cannon"]]["max_level"])

    def test_data_guard_rejects_missing_current_cannon_public_row(self):
        raw = self.data_raw()
        del raw["technology"][self.catalogue["cannon"]]
        before = copy.deepcopy(raw)
        result = self.run_data(raw, "f210")
        self.assertFalse(result["ok"])
        self.assertIn("candidate technology is absent", result["message"])
        self.assertEqual(before, result["raw"])

    def test_data_guard_rejects_old_combined_effect_shape_on_current_rocket_row(self):
        raw = self.data_raw()
        raw["technology"][self.catalogue["source_combined"]]["effects"].append(
            {"type": "gun-speed", "ammo_category": "cannon-shell", "modifier": .1})
        result = self.run_data(raw, "f210")
        self.assertFalse(result["ok"])
        self.assertIn("candidate split gun effects differ", result["message"])

    def test_data_guard_rejects_incomplete_or_wrong_native_finite_vector(self):
        raw = self.data_raw()
        row = raw["technology"]["weapon-shooting-speed-6"]
        row["effects"] = [effect for effect in row["effects"] if effect["ammo_category"] != "cannon-shell"]
        result = self.run_data(raw, "f210")
        self.assertFalse(result["ok"])
        self.assertIn("current finite vector differs", result["message"])

    def test_data_guard_rejects_duplicate_or_wrong_candidate_gear_effect(self):
        raw = self.data_raw()
        raw["technology"][self.catalogue["direct"]]["effects"].append(
            {"type": "change-recipe-productivity", "recipe": self.catalogue["gear_recipe"], "change": .1})
        result = self.run_data(raw, "f210")
        self.assertFalse(result["ok"])
        self.assertIn("candidate gear effect or science differs", result["message"])

    def test_wrappers_preserve_storage_owner_and_distinguish_f200_from_f210(self):
        f210 = json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8"))
        f200 = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        self.assertEqual(FIXTURE_NAME, f210["name"])
        self.assertEqual(FIXTURE_NAME, f200["name"])
        self.assertEqual(("0.2.0", "2.1", "more-infinite-research = 5.0.21000"),
                         (f210["version"], f210["factorio_version"], f210["dependencies"][1]))
        self.assertEqual(("0.3.0", "2.0", "more-infinite-research = 5.0.20000"),
                         (f200["version"], f200["factorio_version"], f200["dependencies"][1]))

    def test_control_declares_non_scripted_lab_reset_and_two_cold_reload_boundary(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("event.by_script ~= false", control)
        self.assertIn("candidate gear lab completed more than once", control)
        self.assertIn("player.reset_technology_effects()", control)
        self.assertIn("loaded and not reload_reported", control)
        self.assertIn("source actual labs", control.replace("_", " "))
        self.assertNotIn("on_tick(function()", control)

    def test_pre_lab_cannon_conservation_refuses_the_uncredited_current_shape(self):
        self.lua.globals().fixture_control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          function migration_origin_120_successor_cannon_boundary(credited)
            local callbacks={}
            local env={script={on_configuration_changed=function(fn) callbacks.configuration=fn end,
              on_load=function(fn) callbacks.load=fn end,on_event=function() end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            assert(loadfile(fixture_control_path,"t",env))()
            local function upvalue(fn,wanted)
              for index=1,64 do
                local name,value=debug.getupvalue(fn,index)
                if name==nil then break end
                if name==wanted then return value end
              end
              error("missing upvalue "..wanted)
            end
            local catalogue=env.require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
            local assert_source_before=upvalue(callbacks.configuration,"assert_source_before")
            local assert_force=upvalue(assert_source_before,"assert_force")
            local function copy_effects(source)
              local out={};for index,effect in ipairs(source) do
                out[index]={type=effect.type,ammo_category=effect.ammo_category,modifier=effect.modifier}
              end;return out
            end
            local technologies={}
            local function add(name,level,maximum,effects,researched)
              technologies[name]={name=name,valid=true,level=level,researched=researched,enabled=true,
                visible_when_disabled=false,saved_progress=0,
                prototype={level=level,max_level=maximum,effects=copy_effects(effects)}}
            end
            add(catalogue.direct,2,4294967295,{},false)
            add(catalogue.source_combined,2,4294967295,catalogue.split_effects.rocket,false)
            add(catalogue.cannon,1,4294967295,catalogue.split_effects.cannon,false)
            local weapons={}
            for name,row in pairs(catalogue.current_runtime) do
              local researched=name~="weapon-shooting-speed-7"
              add(name,row.level,row.maximum,row.effects,researched)
              weapons[name]={level=row.level,maximum=row.maximum,researched=researched,enabled=true,visible=false,saved=0,
                effects=(catalogue.source_runtime[name] and (function()
                  local rows={};for _,effect in ipairs(catalogue.source_runtime[name].effects) do
                    rows[#rows+1]=effect.type.."|"..effect.ammo_category.."|"..string.format("%.17g",effect.modifier)
                  end;table.sort(rows);return table.concat(rows,",")
                end)() or "")}
            end
            local snapshot={technologies={
              [catalogue.direct]={level=2,researched=false,enabled=true,visible=false,maximum=4294967295,saved=0},
              [catalogue.source_combined]={level=2,researched=false,enabled=true,visible=false,maximum=4294967295,saved=0,
                effects=catalogue.source_combined_signature},
              },weapons=weapons,recipes={[catalogue.gear_recipe]=.1},fields={worker_robots_battery_modifier=.1},
              gun_speed={bullet=1.5,["shotgun-shell"]=1.6,rocket=.1,["cannon-shell"]=.1,electric=.1,flamethrower=.1}}
            local speeds={bullet=1.5,["shotgun-shell"]=1.6,rocket=3.5,["cannon-shell"]=credited and 2.4 or 2.3,electric=.1,flamethrower=.1}
            local force={valid=true,technologies=technologies,recipes={[catalogue.gear_recipe]={valid=true,productivity_bonus=.1},},
              worker_robots_battery_modifier=.1,get_gun_speed_modifier=function(category) return speeds[category] end}
            local ok,message=pcall(function() assert_force(force,snapshot,"player",0) end)
            return {ok=ok,message=tostring(message)}
          end
        ''')
        invoke = self.lua.eval("migration_origin_120_successor_cannon_boundary")
        accepted = py(invoke(True))
        rejected = py(invoke(False))
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertFalse(rejected["ok"])
        self.assertIn("preserved gun contribution differs: cannon-shell", rejected["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys_path = args.lua_runtime_dir.resolve(strict=True)
    import sys
    sys.path.insert(0, str(sys_path))
    from lupa.lua52 import LuaRuntime
    MigrationOriginF200120SuccessorControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginF200120SuccessorControls))
    sys.exit(0 if result.wasSuccessful() else 1)

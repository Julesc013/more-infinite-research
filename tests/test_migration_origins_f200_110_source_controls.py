"""Independent controls for the exact published MIR 1.1.0 F200 source fixture."""
import argparse
import copy
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-110-source"
PROFILE = ROOT / "tests/profiles/migration-origins-1.1.0-source-f200-2077.json"
DIRECT = "recipe-prod-research_gears-1"
ROBOT = "recipe-prod-research_robot_battery-1"
ORDINARY = ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack")
MILITARY = ORDINARY[:-1] + ("military-science-pack", "space-science-pack")
ALL_TOOLS = ORDINARY[:-1] + ("military-science-pack", "utility-science-pack", "space-science-pack")

# Exact archived 1.1.0 config combined with the installed Base 2.0.77 recipe
# outputs.  This is intentionally not imported from the fixture catalogue.
EFFECTS = {
    "plastic": {"plastic-bar": .10}, "sulfur": {"sulfur": .10}, "batteries": {"battery": .10},
    "explosives": {"explosives": .10}, "gears": {"iron-gear-wheel": .10}, "iron_sticks": {"iron-stick": .10},
    "copper_cable": {"copper-cable": .10}, "electronic_circuit": {"electronic-circuit": .10},
    "advanced_circuit": {"advanced-circuit": .10}, "processing_unit": {"processing-unit": .10},
    "low_density_structure": {"low-density-structure": .10}, "rocket_fuel": {"rocket-fuel": .10},
    "copper": {"copper-plate": .10}, "iron": {"iron-plate": .10}, "engine": {"engine-unit": .10},
    "electric_engine": {"electric-engine-unit": .10}, "flying_robot_frame": {"flying-robot-frame": .10},
    "modules": {"productivity-module": .10, "speed-module": .10, "efficiency-module": .10,
                "productivity-module-2": .05, "speed-module-2": .05, "efficiency-module-2": .05,
                "productivity-module-3": .02, "speed-module-3": .02, "efficiency-module-3": .02},
    "belts": {"transport-belt": .10, "underground-belt": .10, "splitter": .10,
              "fast-transport-belt": .05, "fast-underground-belt": .05, "fast-splitter": .05,
              "express-transport-belt": .02, "express-underground-belt": .02, "express-splitter": .02},
    "inserters": {"inserter": .10, "burner-inserter": .10, "fast-inserter": .05,
                  "long-handed-inserter": .05, "bulk-inserter": .02},
    "bullets": {"firearm-magazine": .10, "shotgun-shell": .10, "piercing-rounds-magazine": .05,
                "piercing-shotgun-shell": .05, "uranium-rounds-magazine": .02},
    "rockets": {"rocket": .10, "explosive-rocket": .05, "atomic-bomb": .02},
    "science_pack_productivity": {"automation-science-pack": .10, "logistic-science-pack": .10,
                                  "chemical-science-pack": .10, "military-science-pack": .10,
                                  "production-science-pack": .10, "utility-science-pack": .10},
    "walls": {"stone-wall": .10, "gate": .05}, "grenades": {"grenade": .10, "cluster-grenade": .05},
    "rails": {"rail": .10}, "electric_energy": {"solar-panel": .10, "accumulator": .10},
    "concrete": {"stone-brick": .10, "concrete": .05, "hazard-concrete": .05,
                 "refined-concrete": .02, "refined-hazard-concrete": .02},
    "furnace": {"stone-furnace": .20, "steel-furnace": .10, "electric-furnace": .05},
    "mining_drill": {"burner-mining-drill": .20, "electric-mining-drill": .10},
}
ROW_SCIENCE = {key: ORDINARY for key in EFFECTS}
ROW_SCIENCE.update({"bullets": MILITARY, "rockets": MILITARY, "science_pack_productivity": ALL_TOOLS})
STREAM_KEYS = (
    "breeding", "plastic", "sulfur", "batteries", "explosives", "gears", "iron_sticks", "copper_cable",
    "electronic_circuit", "advanced_circuit", "processing_unit", "low_density_structure", "rocket_fuel", "copper",
    "iron", "engine", "electric_engine", "flying_robot_frame", "tungsten", "holmium", "supercapacitor",
    "superconductor", "bioflux", "carbon_fiber", "lithium", "quantum_processor", "modules", "belts", "inserters",
    "bullets", "rockets", "inventory_capacity", "robot_battery", "science_pack_productivity", "walls", "grenades",
    "rails", "electric_energy", "concrete", "furnace", "mining_drill",
)
SETTINGS = {"ips-require-space-gate": True, **{f"ips-enable-research_{key}": key != "inventory_capacity" for key in STREAM_KEYS}}


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


class MigrationOriginF200110SourceControls(unittest.TestCase):
    def expected_rows(self):
        rows = {}
        for key, recipes in EFFECTS.items():
            name = f"recipe-prod-research_{key}-1"
            rows[name] = {
                "science": ROW_SCIENCE[key],
                "effects": [{"type": "change-recipe-productivity", "recipe": recipe, "change": change}
                            for recipe, change in recipes.items()],
            }
        rows[ROBOT] = {"science": ORDINARY, "effects": [{"type": "worker-robot-battery", "modifier": .10}]}
        return rows

    def source_technology_raw(self):
        rows = {}
        for name, expected in self.expected_rows().items():
            rows[name] = {
                "type": "technology", "name": name, "upgrade": True, "max_level": "infinite", "enabled": True,
                "unit": {"count_formula": "8000 * 2^(L-1)", "time": 60,
                         "ingredients": [[pack, 1] for pack in expected["science"]]},
                "prerequisites": list(expected["science"]), "effects": copy.deepcopy(expected["effects"]),
            }
        return {"technology": rows, "sentinel": {"unchanged": 17}}

    def source_settings_raw(self):
        setting_rows = {
            name: {"type": "bool-setting", "name": name, "setting_type": "startup", "default_value": value}
            for name, value in SETTINGS.items()
        }
        return {"bool-setting": setting_rows, "sentinel": {"unchanged": 19}}

    def run_settings(self, raw, mods):
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        settings_path = (FIXTURE / "settings-final-fixes.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.globals().settings_path = settings_path
        self.lua.execute(r'''
          function migration_origin_110_run_settings(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_110_run_settings")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def run_data(self, raw, mods, settings=SETTINGS):
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        data_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.globals().data_path = data_path
        self.lua.execute(r'''
          function migration_origin_110_run_data(raw, mods, settings_values)
            local env={data={raw=raw},mods=mods,settings={startup={}}}
            for name, value in pairs(settings_values) do env.settings.startup[name]={value=value} end
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_110_run_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods), lua(self.lua, settings)))

    def test_separate_settings_and_data_guards_pin_the_42_defaults_and_31_source_rows(self):
        mods = {"base": "2.0.77", "more-infinite-research": "1.1.0", "mir-fixture-mir5-migration-origin-f200-110-source": "0.1.0"}
        accepted_settings = self.run_settings(self.source_settings_raw(), mods)
        self.assertTrue(accepted_settings["ok"], accepted_settings["message"])
        self.assertEqual(19, accepted_settings["raw"]["sentinel"]["unchanged"])

        # Factorio's data-final stage has technologies and effective startup
        # values, but not settings prototypes. The historical default check is
        # intentionally exercised in settings-final-fixes instead.
        accepted = self.run_data(self.source_technology_raw(), mods)
        self.assertTrue(accepted["ok"], accepted["message"])
        rows = accepted["raw"]["technology"]
        self.assertEqual(31, len(rows))
        self.assertNotIn("recipe-prod-research_inventory_capacity-1", rows)
        self.assertEqual(6, len(rows["recipe-prod-research_science_pack_productivity-1"]["effects"]))
        self.assertNotIn("space-science-pack", {effect["recipe"] for effect in rows["recipe-prod-research_science_pack_productivity-1"]["effects"]})
        self.assertEqual([[pack, 1] for pack in ORDINARY], rows[DIRECT]["unit"]["ingredients"])
        self.assertEqual(list(ORDINARY), rows[DIRECT]["prerequisites"])
        self.assertEqual((1, None, 1), (rows[DIRECT]["unit"].get("count"), rows[DIRECT]["unit"].get("count_formula"), rows[DIRECT]["unit"]["time"]))
        self.assertEqual((None, "8000 * 2^(L-1)", 60),
                         (rows["recipe-prod-research_plastic-1"].get("level"), rows["recipe-prod-research_plastic-1"]["unit"]["count_formula"], rows["recipe-prod-research_plastic-1"]["unit"]["time"]))
        self.assertEqual(17, accepted["raw"]["sentinel"]["unchanged"])

        data_variants = []
        missing = self.source_technology_raw(); del missing["technology"][DIRECT]; data_variants.append(("missing-row", missing, SETTINGS))
        wrong_effect = self.source_technology_raw(); wrong_effect["technology"][DIRECT]["effects"][0]["change"] = .05; data_variants.append(("gear-effect", wrong_effect, SETTINGS))
        foreign_effect = self.source_technology_raw(); foreign_effect["technology"][DIRECT]["effects"].append({"type": "change-recipe-productivity", "recipe": "foreign", "change": .10}); data_variants.append(("foreign-effect", foreign_effect, SETTINGS))
        raw_level = self.source_technology_raw(); raw_level["technology"][DIRECT]["level"] = 1; data_variants.append(("raw-level", raw_level, SETTINGS))
        missing_space = self.source_technology_raw(); missing_space["technology"][DIRECT]["prerequisites"].remove("space-science-pack"); data_variants.append(("space-prerequisite", missing_space, SETTINGS))
        wrong_effective = dict(SETTINGS); wrong_effective["ips-enable-research_breeding"] = False; data_variants.append(("breeding-effective", self.source_technology_raw(), wrong_effective))
        for label, candidate, candidate_settings in data_variants:
            with self.subTest(label=label):
                before = copy.deepcopy(candidate)
                rejected = self.run_data(candidate, mods, candidate_settings)
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, rejected["raw"])

        wrong_default = self.source_settings_raw()
        wrong_default["bool-setting"]["ips-enable-research_breeding"]["default_value"] = False
        before = copy.deepcopy(wrong_default)
        rejected_settings = self.run_settings(wrong_default, mods)
        self.assertFalse(rejected_settings["ok"])
        self.assertEqual(before, rejected_settings["raw"])

    def test_catalogue_records_the_archived_base_output_set_without_current_catalogue_fallbacks(self):
        text = (FIXTURE / "catalogue.lua").read_text(encoding="utf-8")
        self.assertIn('recipe("bulk-inserter", .02)', text)
        self.assertNotIn('recipe("stack-inserter"', text)
        self.assertNotIn('recipe("space-science-pack", .10)', text)
        self.assertNotIn('research_inventory_capacity-1"] =', text)
        self.assertIn('["ips-enable-research_breeding"] = true', text)
        self.assertIn('["ips-enable-research_inventory_capacity"] = false', text)
        self.assertEqual(31, len(self.expected_rows()))
        self.assertEqual(72, sum(len(row["effects"]) for row in self.expected_rows().values()))

    def test_settings_defaults_are_checked_only_in_the_settings_stage(self):
        settings_stage = (FIXTURE / "settings-final-fixes.lua").read_text(encoding="utf-8")
        data_stage = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertIn('data.raw["bool-setting"]', settings_stage)
        self.assertIn("published setting count differs", settings_stage)
        self.assertNotIn("settings.startup", settings_stage)
        self.assertIn("settings.startup", data_stage)
        self.assertNotIn('data.raw["bool-setting"]', data_stage)

    def test_control_is_source_only_and_retains_real_lab_reload_and_force_state_boundaries(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("source_labs ~= 1", control)
        self.assertIn("game.server_save(SAVE)", control)
        self.assertIn('marker("reload", state_value)', control)
        self.assertIn("foreign.research_progress = .42", control)
        self.assertIn("saved_progress = .27", control)
        self.assertIn("worker_robots_battery_modifier", control)
        self.assertIn("recipe-prod-research_inventory_capacity-1", control)
        self.assertIn("native manual-mining baseline differs", control)
        self.assertNotIn("manual_mining_speed_modifier = .125", control)
        self.assertLess(control.index("force.reset_technology_effects()"), control.index("foreign.research_queue"))
        self.assertNotIn('more-infinite-research"] ~= "5.', control)
        self.assertNotRegex(control, re.compile(r"\.level\s*=.*?\n.*?\.researched\s*=\s*false", re.DOTALL))

    def test_profile_and_fixture_bind_only_the_exact_published_source_stage(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-migration-origin-f200-110-source", "0.1.0", "2.0"),
                         (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual(("1.1.0", "2fb64822b82569e3b50f0653e361fb7148f18b63", "2.0.77",
                          "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"),
                         (profile["origin_tag"], profile["origin_source_commit"], profile["engine"]["version"], profile["engine"]["sha256"]))
        self.assertEqual("6395C4A5A0F74C67729746D0FBF6162329978B47C5C29D54CC0045F2977C7E44",
                         profile["archive_sha256"]["more-infinite-research_1.1.0.zip"])
        self.assertEqual("82F954450AB7AB761686C288B23331E5C087C29F0846837810D1F3F96BD98A18",
                         profile["archive_sha256"]["mir-fixture-mir5-migration-origin-f200-110-source_0.1.0.zip"])
        self.assertEqual({"README.md", "catalogue.lua", "control.lua", "data-final-fixes.lua", "settings-final-fixes.lua", "info.json"},
                         {path.name for path in FIXTURE.iterdir() if path.is_file()})
        self.assertIn("not a migration pass", (FIXTURE / "README.md").read_text(encoding="utf-8"))

    def test_control_registers_callbacks_without_runtime_access_at_load(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().fixture_control_path = path
        self.lua.execute(r'''
          function migration_origin_110_parse_control()
            local callbacks,forbidden={events={}},{ }
            local env={script={active_mods={base="2.0.77",["more-infinite-research"]="1.1.0",
              ["mir-fixture-mir5-migration-origin-f200-110-source"]="0.1.0"},
              on_init=function(fn) callbacks.init=fn end,on_load=function(fn) callbacks.load=fn end,
              on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue");return {} end
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local ok,message=pcall(function() assert(loadfile(fixture_control_path,"t",env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        result = py(self.lua.eval("migration_origin_110_parse_control")())
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertEqual({}, result["forbidden"])

    def test_runtime_bad_roster_refuses_before_speed_or_fixture_mutation(self):
        self.lua.globals().fixture_control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.execute(r'''
          function migration_origin_110_bad_roster_preflight()
            local catalogue=assert(loadfile(catalogue_path))()
            local callbacks,counters={events={}}, {labels=0,resets=0,research=0,labs=0,forces=0}
            local startup={}
            for name,value in pairs(catalogue.settings) do startup[name]={value=value} end
            local technologies={}
            for name in pairs(catalogue.rows) do
              technologies[name]={name=name,valid=true,level=1,researched=false,enabled=true,saved_progress=0,
                prototype={level=1,max_level=4294967295}}
            end
            technologies[catalogue.direct].prototype.max_level=7
            local force={valid=true,technologies=technologies,recipes={},research_queue={},research_progress=0}
            function force.enable_all_prototypes() counters.labels=counters.labels+1 end
            function force.reset_technology_effects() counters.resets=counters.resets+1 end
            function force.add_research() counters.research=counters.research+1;return true end
            local game={speed=1,tick=0,forces={player=force},surfaces={[1]={create_entity=function()
              counters.labs=counters.labs+1;return nil end}}}
            function game.create_force() counters.forces=counters.forces+1;return nil end
            local storage={}
            local env={game=game,storage=storage,settings={startup=startup},
              script={active_mods={base="2.0.77",["more-infinite-research"]="1.1.0",
                ["mir-fixture-mir5-migration-origin-f200-110-source"]="0.1.0"},
                on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_event=function(event,fn)callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            assert(loadfile(fixture_control_path,"t",env))()
            local ok,message=pcall(callbacks.init)
            return {ok=ok,message=tostring(message),speed=game.speed,storage=storage,counters=counters}
          end
        ''')
        result = py(self.lua.eval("migration_origin_110_bad_roster_preflight")())
        self.assertFalse(result["ok"])
        self.assertIn("source runtime roster identity differs", result["message"])
        self.assertEqual(1, result["speed"])
        self.assertEqual({}, result["storage"])
        self.assertEqual({"labels": 0, "resets": 0, "research": 0, "labs": 0, "forces": 0}, result["counters"])

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    MigrationOriginF200110SourceControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginF200110SourceControls))
    sys.exit(0 if result.wasSuccessful() else 1)

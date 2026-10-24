# Host controls for the private K2SO published-carrier transition fixture.
#
# Native Factorio must qualify each selected saved-game path. These controls
# validate explicit closure, data preflights, fixture-only acceleration, and
# read-only control registration without launching the engine.
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/k2-imersite-transition"
PROFILES = ROOT / "tests/mir5/profiles"
EARLY = "recipe-prod-research_material_imersite-1"
TAIL = "recipe-prod-research_material_imersite-4"
HOLDER = "mir-k2-imersite-staged-state-1"
CARRIER = "mir-k2-imersite-continuation-state-4"
POWDER = "kr-imersite-powder"
ENGINE_SHA = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
MIR_ARCHIVES = {
    "4.6.21000": "B376C9A67651894F10A71A29110131B7D7490326A818360B10FE9595DBDFB1BB",
    "4.7.21002": "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F",
}
STAGES = {
    "predecessor-4.6": ("4.6.21000", "0.1.0"),
    "published-4.7": ("4.7.21002", "0.2.0"),
    "mir5": ("5.0.21000", "0.3.0"),
}


class K2ImersiteTransitionFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_root = FIXTURE.as_posix()
        self.lua.execute(r'''
          local early, tail = "recipe-prod-research_material_imersite-1", "recipe-prod-research_material_imersite-4"
          local holder, carrier = "mir-k2-imersite-staged-state-1", "mir-k2-imersite-continuation-state-4"
          local powder = "kr-imersite-powder"
          local science_early = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
          local predecessor_science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
          local science_tail = {"production-science-pack", "space-science-pack"}

          local function ingredients(names)
            local result = {}
            for index, name in ipairs(names) do result[index] = {name, 1} end
            return result
          end
          local function effect()
            return {{type="change-recipe-productivity", recipe=powder, change=.02}}
          end
          local function public(name, level, maximum, formula, packs)
            return {type="technology", name=name, level=level, upgrade=true, max_level=maximum, enabled=true,
              effects=effect(), unit={count_formula=formula, time=30, ingredients=ingredients(packs)}, prerequisites={}}
          end
          local function carrier_row(name, level, packs)
            return {type="technology", name=name, level=level, upgrade=false, hidden=true, enabled=true,
              max_level="infinite", effects=effect(), prerequisites={},
              unit={count_formula=level == 1 and "200*2^(L-1)" or "1600+200*(L-4)", time=30,
                ingredients=ingredients(packs)}}
          end
          local function rows_for(stage)
            local rows = {}
            if stage == "predecessor-4.6" then
              rows[early] = public(early, 1, "infinite", "200*2^(L-1)", predecessor_science)
              rows[early].prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "kr-quarry-minerals-extraction"}
            elseif stage == "published-4.7" then
              rows[early] = public(early, 1, 3, "200*2^(L-1)", science_early)
              rows[holder], rows[carrier] = carrier_row(holder, 1, science_early), carrier_row(carrier, 4, science_early)
            else
              rows[early] = public(early, 1, 3, "200*2^(L-1)", science_early)
              rows[early].prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "kr-quarry-minerals-extraction"}
              rows[tail] = public(tail, 4, "infinite", "1600+200*(L-4)", science_tail)
              rows[tail].visible_when_disabled, rows[tail].show_levels_info = true, false
              rows[tail].prerequisites = {"kr-quarry-minerals-extraction", "production-science-pack", early, "space-science-pack"}
              rows[holder], rows[carrier] = carrier_row(holder, 1, science_early), carrier_row(carrier, 4, science_tail)
            end
            return rows
          end
          function run_k2_data_fixture(path, setting_path, stage, opponent, setting_default)
            local rows = rows_for(stage)
            if opponent == "effect" then
              local target = stage == "predecessor-4.6" and early or tail
              rows[target].effects[1].change = .03
            end
            if opponent == "withheld" then rows[tail] = public(tail, 4, "infinite", "1600+200*(L-4)", science_tail) end
            if opponent == "carrier" then rows[carrier].hidden = false end
            if opponent == "carrier-unit" then rows[carrier].unit.count_formula = "1" end
            mods = {base="2.1.23", ["Krastorio2-spaced-out"]="2.0.19", ["more-infinite-research"]=stage == "predecessor-4.6" and "4.6.21000" or (stage == "published-4.7" and "4.7.21002" or "5.0.21000")}
            data = {raw={technology=rows, ["int-setting"]={["ips-max-level-research_material_imersite"]={default_value=setting_default or 0}}}}
            if setting_path ~= "" then
              local setting, message = loadfile(setting_path, "t", _G)
              assert(setting, message)
              local ok, value = pcall(setting)
              if not ok then return {ok=false, message=tostring(value), rows=rows, setting=data.raw["int-setting"]["ips-max-level-research_material_imersite"]} end
            end
            local chunk, message = loadfile(path, "t", _G)
            assert(chunk, message)
            local ok, value = pcall(chunk)
            return {ok=ok, message=tostring(value), rows=rows, setting=data.raw["int-setting"]["ips-max-level-research_material_imersite"]}
          end
          function parse_k2_control(path)
            local callbacks, forbidden = {events={}}, {}
            local environment = {
              script={
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_configuration_changed=function(callback) callbacks.configuration=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end,
              },
              defines={events={on_tick=1, on_research_finished=2}, inventory={lab_input=1}},
            }
            environment._G = environment
            setmetatable(environment, {__index=function(_, key)
              if key == "game" or key == "storage" then forbidden[key] = true; return nil end
              return _G[key]
            end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk, message)
            local ok, value = pcall(chunk)
            return {ok=ok, message=tostring(value), callbacks=callbacks, forbidden=forbidden}
          end
        ''')

    def _data(self, stage: str, opponent: str = "", setting_default=None):
        if setting_default is None:
            setting_default = 3 if stage == "predecessor-4.6" else 0
        path = (FIXTURE / stage / "data-final-fixes.lua").as_posix()
        setting = FIXTURE / stage / "settings-updates.lua"
        return self.lua.eval("run_k2_data_fixture")(
            path, setting.as_posix() if setting.exists() else "", stage, opponent, setting_default
        )

    def test_exact_profiles_pin_the_three_stage_k2so_closure(self):
        expected_external = {
            "flib_0.17.2.zip", "k2so-assets_1.0.7.zip", "Krastorio2_2.1.4.zip",
            "Krastorio2-spaced-out_2.0.19.zip", "Krastorio2Assets_2.1.0.zip",
            "Krastorio2MenuSimulations_2.1.0.zip", "xy-k2so-enhancements-nulls-fork_0.8.3.zip",
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip",
        }
        for stage, (mir, fixture) in STAGES.items():
            with self.subTest(stage=stage):
                profile = json.loads((PROFILES / f"k2-imersite-transition-{stage}-f210.json").read_text(encoding="utf-8"))
                self.assertEqual(1, profile["schema"])
                self.assertEqual("f210", profile["target"])
                self.assertEqual("2.1", profile["factorio_line"])
                self.assertEqual(("2.1.23", ENGINE_SHA), (profile["engine"]["version"], profile["engine"]["sha256"]))
                mods = {row["name"]: row["version"] for row in profile["mods"]}
                self.assertEqual(mir, mods["more-infinite-research"])
                self.assertEqual(fixture, mods["mir-fixture-mir5-k2-imersite-transition"])
                self.assertEqual("2.0.19", mods["Krastorio2-spaced-out"])
                self.assertEqual("1.0.7", mods["k2so-assets"])
                self.assertEqual(expected_external, set(profile["archive_sha256"]))
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        for digest in MIR_ARCHIVES.values():
            self.assertIn(digest, readme)

    def test_data_preflight_keeps_published_input_and_accelerates_only_real_lab_rows(self):
        predecessor = self._data("predecessor-4.6", setting_default=3)
        self.assertTrue(predecessor["ok"], predecessor["message"])
        self.assertEqual(0, predecessor["setting"]["default_value"])
        row = predecessor["rows"][EARLY]
        self.assertIsNone(row["unit"]["count"])
        self.assertEqual("1", row["unit"]["count_formula"])
        self.assertEqual(1, row["unit"]["time"])
        self.assertEqual("infinite", row["max_level"])
        self.assertEqual(POWDER, row["effects"][1]["recipe"])
        self.assertIsNone(predecessor["rows"][TAIL])

        published = self._data("published-4.7")
        self.assertTrue(published["ok"], published["message"])
        self.assertEqual(3, published["setting"]["default_value"])
        self.assertIsNone(published["rows"][TAIL])
        self.assertTrue(published["rows"][CARRIER]["hidden"])
        self.assertEqual("1600+200*(L-4)", published["rows"][CARRIER]["unit"]["count_formula"])
        self.assertEqual(30, published["rows"][CARRIER]["unit"]["time"])
        self.assertEqual(
            ["automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"],
            [published["rows"][CARRIER]["unit"]["ingredients"][index][1] for index in range(1, 5)],
        )

        successor = self._data("mir5")
        self.assertTrue(successor["ok"], successor["message"])
        self.assertEqual(0, successor["setting"]["default_value"])
        self.assertEqual("200*2^(L-1)", successor["rows"][EARLY]["unit"]["count_formula"])
        self.assertEqual(30, successor["rows"][EARLY]["unit"]["time"])
        self.assertEqual("1", successor["rows"][TAIL]["unit"]["count_formula"])
        self.assertEqual(1, successor["rows"][TAIL]["unit"]["time"])
        self.assertTrue(successor["rows"][CARRIER]["hidden"])

    def test_data_preflight_rejects_drift_before_fixture_mutation(self):
        checks = (
            ("predecessor-4.6", "effect", "powder effect changed", EARLY),
            ("published-4.7", "withheld", "was not withheld", HOLDER),
            ("mir5", "carrier", "carrier identity changed", TAIL),
        )
        for stage, opponent, phrase, untouched in checks:
            with self.subTest(stage=stage, opponent=opponent):
                result = self._data(stage, opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                row = result["rows"][untouched]
                self.assertEqual(30, row["unit"]["time"])
                self.assertNotEqual("1", row["unit"]["count_formula"])
        carrier_unit = self._data("published-4.7", "carrier-unit")
        self.assertFalse(carrier_unit["ok"])
        self.assertIn("carrier unit changed", carrier_unit["message"])

    def test_predecessor_cap_refuses_unknown_default_before_fixture_mutation(self):
        for source_default in (0, 1):
            with self.subTest(source_default=source_default):
                result = self._data("predecessor-4.6", setting_default=source_default)
                self.assertFalse(result["ok"])
                self.assertIn("published predecessor Imersite cap default changed", result["message"])
                self.assertEqual(source_default, result["setting"]["default_value"])
                row = result["rows"][EARLY]
                self.assertEqual("200*2^(L-1)", row["unit"]["count_formula"])
                self.assertEqual(30, row["unit"]["time"])

    def test_controls_register_without_game_or_storage_reads_and_keep_native_boundaries(self):
        for stage in STAGES:
            with self.subTest(stage=stage):
                result = self.lua.eval("parse_k2_control")((FIXTURE / stage / "control.lua").as_posix())
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                source = (FIXTURE / stage / "control.lua").read_text(encoding="utf-8")
                self.assertIn("game.server_save", source)
                self.assertIn('local SAVE = "mir5-native-complete"', source)
                self.assertNotIn("force.research_queue =", source)
                self.assertNotIn("reset_technology_effects", source)
                on_load = source.split("script.on_load", 1)[1].split("script.on_event", 1)[0]
                self.assertNotIn("game.", on_load)
                if stage == "predecessor-4.6":
                    self.assertIsNotNone(result["callbacks"]["init"])
                    self.assertIn("local REQUIRED_COMPLETIONS = 5", source)
                    self.assertIn("legacy.saved_progress = 0.42", source)
                    self.assertIn("legacy.level ~= 6", source)
                    self.assertNotIn("mir-k2-imersite", source)
                    self.assertNotIn("legacy.level =", source)
                else:
                    self.assertIsNotNone(result["callbacks"]["configuration"])
        published = (FIXTURE / "published-4.7/control.lua").read_text(encoding="utf-8")
        self.assertIn("force.technologies[TAIL] ~= nil", published)
        self.assertIn("state.published_mir", published)
        self.assertNotIn("CARRIER].enabled = true", published)
        successor = (FIXTURE / "mir5/control.lua").read_text(encoding="utf-8")
        self.assertIn('direct_predecessor_handoff=state.handoff_source == "direct-4.6"', successor)
        self.assertIn("recovered_tail_saved_progress_before_lab=0.42", successor)
        self.assertIn("state.published_mir ~= \"4.7.21002\"", successor)
        self.assertIn("destination_lab_completions ~= 1", successor)

    def _successor_configuration(self, kind, opponent=""):
        self.lua.globals().successor_path = (FIXTURE / "mir5/control.lua").as_posix()
        self.lua.globals().source_kind_fixture = kind
        self.lua.globals().source_opponent = opponent
        return self.lua.execute(r'''
          local callbacks, calls = {}, {created=0, inserted=0, added=0, prerequisites=0}
          local diagnostics = {}
          local early, tail = "recipe-prod-research_material_imersite-1", "recipe-prod-research_material_imersite-4"
          local holder, carrier = "mir-k2-imersite-staged-state-1", "mir-k2-imersite-continuation-state-4"
          local powder = "kr-imersite-powder"
          local function technology(name, level, researched, maximum, hidden, enabled)
            local values = {name=name,valid=true,level=level,researched=researched,
              enabled=enabled,visible_when_disabled=false,saved_progress=name == tail and .42 or 0,
              research_unit_count=1,research_unit_energy=60,
              research_unit_ingredients={{name="production-science-pack",amount=1},{name="space-science-pack",amount=1}},
              prerequisites={{research_recursive=function() calls.prerequisites=calls.prerequisites+1 end}},
              prototype={max_level=maximum,hidden=hidden,
                effects={{type="change-recipe-productivity",recipe=powder,change=.02}}}}
            return setmetatable({}, {__index=values,__newindex=function() error("fixture wrote selected technology") end})
          end
          local rows = {
            [early]=technology(early,3,true,3,false,true),
            [tail]=technology(tail,6,false,4294967295,false,true),
            [holder]=technology(holder,1,false,4294967295,true,false),
            [carrier]=technology(carrier,4,false,4294967295,true,false),
          }
          local force = {technologies=rows,recipes={[powder]={productivity_bonus=.10}},research_queue={}}
          force.add_research=function(value)
            assert(value == rows[tail], "successor passed a detached snapshot instead of LuaTechnology")
            calls.added=calls.added+1
            force.current_research=value; force.research_queue={value}; force.research_progress=value.saved_progress
            return true
          end
          local witness = {phase="complete",source_mir="4.6.21000",actual_lab_completions=5,
            completed_legacy={level=6,saved_progress=.42,bonus=.10}}
          if source_kind_fixture == "published" then
            witness.phase="published-ready"; witness.published_mir="4.7.21002"
            witness.published={carrier_level=6,carrier_progress=.42,bonus=.10}
          end
          if source_opponent == "lab-count" then witness.actual_lab_completions=4 end
          if source_opponent == "progress" then witness.completed_legacy.saved_progress=.25 end
          if source_opponent == "bonus" then witness.completed_legacy.bonus=.12 end
          if source_opponent == "source-version" then witness.source_mir="4.5.21000" end
          if source_opponent == "mixed-published" then witness.published_mir="4.7.21002" end
          if source_opponent == "published-progress" then witness.published.carrier_progress=.25 end
          if source_opponent == "native-bonus" then force.recipes[powder].productivity_bonus=.12 end
          helpers = {table_to_json=function(value) diagnostics[#diagnostics+1]=value; return "readback-json" end}
          log = function(value) assert(value == "[MIR5_NATIVE_FIXTURE] DIAGNOSTIC readback-json") end
          local inventory = {insert=function(value)
            assert((value.name == "production-science-pack" or value.name == "space-science-pack") and value.count == 8)
            calls.inserted=calls.inserted+1; return value.count
          end}
          local entity = {valid=true,get_inventory=function() return inventory end}
          game = {tick=100,forces={player=force},surfaces={{create_entity=function()
            calls.created=calls.created+1; return entity
          end}}}
          storage = {mir5_k2_imersite_transition=witness}
          settings = {startup={["ips-max-level-research_material_imersite"]={value=0}}}
          defines = {inventory={lab_input=1},events={on_tick=1,on_research_finished=2}}
          script = {active_mods={base="2.1.23",["Krastorio2-spaced-out"]="2.0.19",
            ["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-k2-imersite-transition"]="0.3.0"},
            on_configuration_changed=function(callback) callbacks.configuration=callback end,
            on_load=function(callback) callbacks.load=callback end,
            on_event=function() end}
          assert(loadfile(successor_path))()
          local ok,message=pcall(callbacks.configuration)
          return {ok=ok,message=tostring(message),calls=calls,route=witness.handoff_source,
            phase=witness.phase,progress=force.research_progress,real_tail=force.current_research == rows[tail],
            diagnostics=diagnostics,bonus=force.recipes[powder].productivity_bonus}
        ''')

    def test_successor_accepts_both_exact_source_witnesses_and_starts_the_actual_native_tail(self):
        for kind, route in (("direct", "direct-4.6"), ("published", "published-4.7")):
            with self.subTest(kind=kind):
                result = self._successor_configuration(kind)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(route, result["route"])
                self.assertEqual("await-successor-lab", result["phase"])
                self.assertEqual(0.42, result["progress"])
                self.assertTrue(result["real_tail"])
                self.assertEqual((1, 2, 1, 1), tuple(result["calls"][key] for key in
                                                  ("created", "inserted", "added", "prerequisites")))

    def test_successor_refuses_changed_or_mixed_source_witnesses_before_lab_or_research_writes(self):
        for kind, opponent in (("direct", "lab-count"), ("direct", "progress"), ("direct", "bonus"),
                               ("direct", "source-version"), ("direct", "mixed-published"),
                               ("published", "published-progress")):
            with self.subTest(kind=kind, opponent=opponent):
                result = self._successor_configuration(kind, opponent)
                self.assertFalse(result["ok"], result["message"])
                self.assertEqual((0, 0, 0, 0), tuple(result["calls"][key] for key in
                                                  ("created", "inserted", "added", "prerequisites")))

    def test_failed_native_readback_reports_values_without_repair_or_successor_writes(self):
        result = self._successor_configuration("direct", "native-bonus")
        self.assertFalse(result["ok"])
        self.assertIn("recovered public Imersite state differs", result["message"])
        self.assertEqual((0, 0, 0, 0), tuple(result["calls"][key] for key in
                                          ("created", "inserted", "added", "prerequisites")))
        self.assertEqual(0.12, result["bonus"])
        diagnostic = result["diagnostics"][1]
        self.assertEqual("direct-4.6", diagnostic["handoff_source"])
        self.assertEqual(0.10, diagnostic["expected"]["powder_productivity"])
        self.assertEqual(0.12, diagnostic["actual"]["powder_productivity"])
        self.assertEqual(6, diagnostic["actual"]["tail"]["level"])
        self.assertEqual(0.42, diagnostic["actual"]["tail"]["saved_progress"])
        self.assertIsNone(result["diagnostics"][2])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(K2ImersiteTransitionFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

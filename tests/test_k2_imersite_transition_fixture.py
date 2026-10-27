# Host controls for the private K2SO published-carrier transition fixture.
#
# Native Factorio must qualify each selected saved-game path. These controls
# validate explicit closure, data preflights, fixture-only acceleration, and
# read-only control registration without launching the engine.
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/k2-imersite-transition"
HELD_FLAGS_FIXTURE = ROOT / "tests/fixtures/k2-imersite-held-public-flags"
PROFILES = ROOT / "tests/profiles"
EARLY = "recipe-prod-research_material_imersite-1"
TAIL = "recipe-prod-research_material_imersite-4"
HOLDER = "mir-k2-imersite-staged-state-1"
CARRIER = "mir-k2-imersite-continuation-state-4"
POWDER = "kr-imersite-powder"
ENGINE_SHA = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
CURRENT_FREEZE = ROOT / "spec/evidence/current-assets-b251ae7a-aero-readback.json"
CURRENT_SOURCE = "b251ae7a54104ace87cb0da4cf531cf53f03c93d"
CURRENT_SOURCE_TREE = "79b73a6a8e68987737e69bf2d95ec6555b49f901"
CURRENT_MIR_ARCHIVE = "E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE"
CURRENT_MIR_BYTES = 679250
CURRENT_MIR_NAME = "more-infinite-research_5.0.21000.zip"
HELD_FLAGS_FIXED_SOURCE = "98fbdd33fe47eb678a5e1aaf17fee903eba2a22a"
HELD_FLAGS_FIXED_SOURCE_TREE = "ffc5f2e3359de4f326a184cf6a3c29a55941150a"
HELD_FLAGS_FIXED_MIR_ARCHIVE = "58F04FB9D417F2726835F4A6740490DE3C1841665DAC81C2BA3DFA94050D9457"
HELD_FLAGS_FIXED_MIR_BYTES = 679860
HELD_FLAGS_SOURCE_PROFILE = PROFILES / "k2-imersite-held-public-flags-source-f210.json"
HELD_FLAGS_FIXED_PROFILE = PROFILES / "k2-imersite-held-public-flags-fixed-f210.json"
HELD_FLAGS_INPUT_REVISION = "a9754abcd7405e1ddffa9f4dc8051b71d00855fe"
HELD_FLAGS_INPUT_RECEIPT = ROOT / "spec/evidence/k2-imersite-held-public-flags-inputs-a9754abc.json"
FROZEN_PACKAGE_TOOL_SHA256 = "00ED00D66BD558554068405C8882419F852FC2F66646088052888D70E25DA61E"
HELD_FLAGS_FIXTURE_ARCHIVES = {
    "source": ("mir-fixture-mir5-k2-imersite-held-public-flags_0.1.0.zip",
               "F57D35293380C5B06D49FE5841341E6D8F2E217A81312D6C43049974633BFC59", 6816),
    "fixed": ("mir-fixture-mir5-k2-imersite-held-public-flags_0.2.0.zip",
              "FB33961AB84A0A5CFACF682AF0E0A29AD58CF9EBB665F92AACA06EAADBF091B9", 6815),
}
OBSERVER_ARCHIVE = "mir-fixture-mir5-active-mods-observer_0.1.0.zip"
EXTERNAL_ARCHIVES = {
    "flib_0.17.2.zip": "0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D",
    "k2so-assets_1.0.7.zip": "C3E11214407B08120B2EE717405D3B0398F533647695AB2E6EF6DF9267D62017",
    "Krastorio2_2.1.4.zip": "9E5A56AC52BA0DD96A2D9FFBEFB8B242270EC946159D3DBED77B24B3C1C7147E",
    "Krastorio2-spaced-out_2.0.19.zip": "8FCA3A3C202DD4939D5D85ACE93BE775CEDFE3D02FBDAF9DB78B77883B2C662B",
    "Krastorio2Assets_2.1.0.zip": "39EF950EC8B21A40357DD0240EF8389501EE75CCA82717F2773B98554DA46E29",
    "Krastorio2MenuSimulations_2.1.0.zip": "3A485B449B356DC4B3EB4233DE4E803B3A001259FBC251BDC9F9D9120B3C53A7",
    "xy-k2so-enhancements-nulls-fork_0.8.3.zip": "930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE",
    OBSERVER_ARCHIVE: "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
}
MIR_ARCHIVES = {
    "4.6.21000": "B376C9A67651894F10A71A29110131B7D7490326A818360B10FE9595DBDFB1BB",
    "4.7.21002": "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F",
}
STAGES = {
    "predecessor-4.6": ("4.6.21000", "0.1.0"),
    "published-4.7": ("4.7.21002", "0.2.0"),
    "mir5": ("5.0.21000", "0.3.0"),
}
_package_spec = importlib.util.spec_from_file_location("k2_imersite_transition_package", ROOT / "tools" / "package.py")
PACKAGE = importlib.util.module_from_spec(_package_spec)
assert _package_spec.loader is not None
_package_spec.loader.exec_module(PACKAGE)


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
          function run_direct_cost_fixture(path, opponent)
            local rows = rows_for("mir5")
            if opponent == "early-identity" then rows[early].upgrade = false end
            if opponent == "early-effect" then rows[early].effects[1].change = .03 end
            if opponent == "early-science" then rows[early].unit.ingredients[1][1] = "military-science-pack" end
            if opponent == "early-unit" then rows[early].unit.count_formula = "199" end
            if opponent == "early-hidden" then rows[early].hidden = true end
            if opponent == "holder-identity" then rows[holder].max_level = 3 end
            if opponent == "holder-effect" then rows[holder].effects[1].change = .03 end
            if opponent == "holder-science" then rows[holder].unit.ingredients[1][1] = "military-science-pack" end
            if opponent == "holder-unit" then rows[holder].unit.count_formula = "199" end
            if opponent == "holder-hidden" then rows[holder].hidden = false end
            mods = {base="2.1.23", ["Krastorio2-spaced-out"]="2.0.19", ["more-infinite-research"]="5.0.21000",
              ["mir-fixture-mir5-k2-imersite-transition"]="0.3.0",
              ["mir-fixture-mir5-k2-imersite-direct-cost"]="0.1.0"}
            data = {raw={technology=rows}}
            local chunk, message = loadfile(path, "t", _G)
            assert(chunk, message)
            local ok, value = pcall(chunk)
            return {ok=ok, message=tostring(value), rows=rows}
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

    def _direct_cost(self, opponent: str = ""):
        return self.lua.eval("run_direct_cost_fixture")(
            (FIXTURE / "direct-cost/data-final-fixes.lua").as_posix(), opponent
        )

    def test_exact_profiles_pin_the_three_stage_k2so_closure(self):
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
                archives = profile["archive_sha256"]
                external = {name: digest for name, digest in archives.items() if name != CURRENT_MIR_NAME}
                self.assertEqual(EXTERNAL_ARCHIVES, external)
                if stage == "mir5":
                    self.assertEqual(CURRENT_MIR_ARCHIVE, archives[CURRENT_MIR_NAME])
                else:
                    self.assertNotIn(CURRENT_MIR_NAME, archives)
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        for digest in MIR_ARCHIVES.values():
            self.assertIn(digest, readme)

    def test_direct_profile_adds_only_the_ordered_direct_cost_companion(self):
        direct = json.loads((PROFILES / "k2-imersite-transition-direct-f210.json").read_text(encoding="utf-8"))
        self.assertEqual("mir5-k2-imersite-transition-direct-4.6-to-mir5", direct["kind"])
        self.assertEqual(("2.1.23", ENGINE_SHA), (direct["engine"]["version"], direct["engine"]["sha256"]))
        names = [row["name"] for row in direct["mods"]]
        versions = {row["name"]: row["version"] for row in direct["mods"]}
        self.assertEqual("5.0.21000", versions["more-infinite-research"])
        self.assertEqual("0.3.0", versions["mir-fixture-mir5-k2-imersite-transition"])
        self.assertEqual("0.1.0", versions["mir-fixture-mir5-k2-imersite-direct-cost"])
        self.assertGreater(
            names.index("mir-fixture-mir5-k2-imersite-direct-cost"),
            names.index("mir-fixture-mir5-k2-imersite-transition"),
        )
        archives = direct["archive_sha256"]
        external = {name: digest for name, digest in archives.items() if name != CURRENT_MIR_NAME}
        self.assertEqual(EXTERNAL_ARCHIVES, external)
        self.assertEqual(CURRENT_MIR_ARCHIVE, archives[CURRENT_MIR_NAME])

        published = json.loads((PROFILES / "k2-imersite-transition-published-4.7-f210.json").read_text(encoding="utf-8"))
        self.assertNotIn(
            "mir-fixture-mir5-k2-imersite-direct-cost",
            {row["name"] for row in published["mods"]},
        )

        info = json.loads((FIXTURE / "direct-cost/info.json").read_text(encoding="utf-8"))
        self.assertEqual("mir-fixture-mir5-k2-imersite-direct-cost", info["name"])
        self.assertIn("mir-fixture-mir5-k2-imersite-transition >= 0.3.0", info["dependencies"])
        self.assertFalse((FIXTURE / "direct-cost/control.lua").exists())

    def test_current_successor_profiles_bind_the_freeze_and_keep_direct_and_failed_paths_separate(self):
        freeze = json.loads(CURRENT_FREEZE.read_text(encoding="utf-8"))
        self.assertEqual((CURRENT_SOURCE, CURRENT_SOURCE_TREE),
                         (freeze["source"]["commit"], freeze["source"]["source_tree"]))
        asset = next(row for row in freeze["files"] if row["name"] == CURRENT_MIR_NAME)
        self.assertEqual((CURRENT_MIR_BYTES, CURRENT_MIR_ARCHIVE), (asset["bytes"], asset["sha256"]))

        current = json.loads((PROFILES / "k2-imersite-transition-mir5-f210.json").read_text(encoding="utf-8"))
        direct = json.loads((PROFILES / "k2-imersite-transition-direct-f210.json").read_text(encoding="utf-8"))
        for profile in (current, direct):
            with self.subTest(kind=profile["kind"]):
                self.assertEqual(CURRENT_MIR_ARCHIVE, profile["archive_sha256"][CURRENT_MIR_NAME])
                for expected in (CURRENT_SOURCE, CURRENT_SOURCE_TREE, CURRENT_MIR_ARCHIVE, f"{CURRENT_MIR_BYTES} bytes"):
                    self.assertIn(expected, profile["scope"])

        self.assertIn("failed published4.7 intermediate", current["scope"])
        self.assertIn("protected already-passed published4.6 source save", direct["scope"])
        self.assertIn("not the failed published4.7 intermediate", direct["scope"])
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        for expected in (CURRENT_SOURCE, CURRENT_SOURCE_TREE, CURRENT_MIR_ARCHIVE, f"{CURRENT_MIR_BYTES} bytes",
                         "run40075366627", "does not convert that adverse into a pass"):
            self.assertIn(expected, readme)

    def test_direct_cost_companion_preflights_both_rows_then_matches_the_source_fixture_cost(self):
        result = self._direct_cost()
        self.assertTrue(result["ok"], result["message"])
        for name in (EARLY, HOLDER):
            with self.subTest(name=name):
                row = result["rows"][name]
                self.assertIsNone(row["unit"]["count"])
                self.assertEqual("1", row["unit"]["count_formula"])
                self.assertEqual(1, row["unit"]["time"])
        self.assertEqual(3, result["rows"][EARLY]["max_level"])
        self.assertFalse(result["rows"][EARLY]["hidden"])
        self.assertTrue(result["rows"][HOLDER]["hidden"])

    def test_direct_cost_companion_refuses_each_preflight_before_either_cost_write(self):
        checks = (
            ("early-identity", "public early identity changed"),
            ("early-effect", "public early effect changed"),
            ("early-science", "public early science changed"),
            ("early-unit", "public early unit changed"),
            ("early-hidden", "public early identity changed"),
            ("holder-identity", "JSON early holder identity changed"),
            ("holder-effect", "JSON early holder effect changed"),
            ("holder-science", "JSON early holder science changed"),
            ("holder-unit", "JSON early holder unit changed"),
            ("holder-hidden", "JSON early holder identity changed"),
        )
        for opponent, phrase in checks:
            with self.subTest(opponent=opponent):
                result = self._direct_cost(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                for name in (EARLY, HOLDER):
                    row = result["rows"][name]
                    self.assertIsNone(row["unit"]["count"])
                    self.assertNotEqual("1", row["unit"]["count_formula"])
                    self.assertEqual(30, row["unit"]["time"])

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

    def _held_flags_data(self, stage: str, opponent: str = ""):
        self.lua.globals().held_data_path = (HELD_FLAGS_FIXTURE / "fixture_data_final.lua").as_posix()
        self.lua.globals().held_settings_path = (HELD_FLAGS_FIXTURE / "fixture_settings.lua").as_posix()
        self.lua.globals().held_stage = stage
        self.lua.globals().held_opponent = opponent
        return self.lua.execute(r'''
          local early, tail = "recipe-prod-research_material_imersite-1", "recipe-prod-research_material_imersite-4"
          local holder, carrier = "mir-k2-imersite-staged-state-1", "mir-k2-imersite-continuation-state-4"
          local powder = "kr-imersite-powder"
          local function row(name, level, maximum, hidden)
            return {name=name, level=level, max_level=maximum, hidden=hidden,
              effects={{type="change-recipe-productivity", recipe=powder, change=.02}}}
          end
          mods = {base="2.1.23",["elevated-rails"]="2.1.23",quality="2.1.23",recycler="2.1.23",
            ["space-age"]="2.1.23",flib="0.17.2",["k2so-assets"]="1.0.7",Krastorio2="2.1.4",
            ["Krastorio2-spaced-out"]="2.0.19",Krastorio2Assets="2.1.0",
            Krastorio2MenuSimulations="2.1.0",["xy-k2so-enhancements-nulls-fork"]="0.8.3",
            ["more-infinite-research"]="5.0.21000",
            ["mir-fixture-mir5-k2-imersite-held-public-flags"]=held_stage == "source" and "0.1.0" or "0.2.0"}
          data = {raw={technology={
            [early]=row(early,1,3,false), [tail]=row(tail,4,"infinite",false),
            [holder]=row(holder,1,"infinite",true), [carrier]=row(carrier,4,"infinite",true),
          }, ["int-setting"]={["ips-max-level-research_material_imersite"]={default_value=0}}}}
          if held_opponent == "effect" then data.raw.technology[tail].effects[1].change=.03 end
          if held_opponent == "carrier" then data.raw.technology[carrier].hidden=false end
          if held_opponent == "missing" then data.raw.technology[tail]=nil end
          if held_opponent == "duplicate" then table.insert(data.raw.technology[tail].effects,
            {type="change-recipe-productivity",recipe=powder,change=.02}) end
          if held_opponent == "setting" then data.raw["int-setting"]["ips-max-level-research_material_imersite"].default_value=1 end
          if held_opponent == "closure" then mods["space-age"]="2.1.22" end
          local settings = assert(loadfile(held_settings_path, "t", _G))()
          local final = assert(loadfile(held_data_path, "t", _G))()
          local ok, message = pcall(function() settings.apply(held_stage); final.apply(held_stage) end)
          return {ok=ok, message=tostring(message), rows=data.raw.technology,
            setting=data.raw["int-setting"]["ips-max-level-research_material_imersite"]}
        ''')

    def _held_flags_flow(self, opponent: str = ""):
        self.lua.globals().held_control_path = (HELD_FLAGS_FIXTURE / "fixture_control.lua").as_posix()
        self.lua.globals().held_opponent = opponent
        return self.lua.execute(r'''
          local callbacks, calls, logs = {}, {saves=0}, {}
          local early, tail = "recipe-prod-research_material_imersite-1", "recipe-prod-research_material_imersite-4"
          local holder, carrier = "mir-k2-imersite-staged-state-1", "mir-k2-imersite-continuation-state-4"
          local powder = "kr-imersite-powder"
          local function technology(name, level, maximum, hidden)
            local values = {name=name, valid=true, level=level, researched=false, saved_progress=0,
              enabled=true, visible_when_disabled=false,
              prototype={max_level=maximum, hidden=hidden,
                effects={{type="change-recipe-productivity", recipe=powder, change=.02}}}}
            return setmetatable({}, {__index=values, __newindex=function(_, key, value)
              values[key]=value
              -- Factorio's level setter re-enables a technology. This catches
              -- accidental multi-assignment ordering in the fixture setup.
              if key == "level" then values.enabled=true end
              if key == "researched" and value == false then values.level=level end
            end})
          end
          local function make_force(index)
            local values = {index=index, technologies={
              [early]=technology(early,1,3,false), [tail]=technology(tail,4,4294967295,false),
              [holder]=technology(holder,1,4294967295,true), [carrier]=technology(carrier,4,4294967295,true),
            }, recipes={[powder]={productivity_bonus=0}}, research_queue={}, research_progress=0}
            local value = {}
            value.enable_all_prototypes=function() end
            value.reset_technology_effects=function()
              for _,technology in pairs(values.technologies) do technology.enabled=true end
              local state=values.technologies[holder]
              values.recipes[powder].productivity_bonus=(state.level-1)*.02
            end
            return setmetatable(value, {__index=values, __newindex=function(_, key, entry) values[key]=entry end})
          end
          local player, foreign = make_force(1), nil
          game = {forces={player=player}, create_force=function(name)
            assert(name == "mir5-k2-imersite-held-public-flags-foreign")
            foreign=make_force(2); game.forces[foreign.index]=foreign; return foreign
          end, server_save=function(name) assert(name == "mir5-native-complete"); calls.saves=calls.saves+1 end}
          storage = {}
          settings = {startup={["ips-max-level-research_material_imersite"]={value=0}}}
          defines = {events={on_tick=1}}
          helpers = {table_to_json=function(value) return "host-json" end}
          log = function(value) logs[#logs+1]=value end
          script = {active_mods={base="2.1.23",["elevated-rails"]="2.1.23",quality="2.1.23",recycler="2.1.23",
              ["space-age"]="2.1.23",flib="0.17.2",["k2so-assets"]="1.0.7",Krastorio2="2.1.4",
              ["Krastorio2-spaced-out"]="2.0.19",Krastorio2Assets="2.1.0",
              Krastorio2MenuSimulations="2.1.0",["xy-k2so-enhancements-nulls-fork"]="0.8.3",
              ["more-infinite-research"]="5.0.21000",
              ["mir-fixture-mir5-k2-imersite-held-public-flags"]="0.1.0"},
            on_init=function(callback) callbacks.init=callback end,
            on_load=function(callback) callbacks.load=callback end,
            on_configuration_changed=function(callback) callbacks.configuration=callback end,
            on_event=function(event, callback) callbacks.tick=callback end}
          local module = assert(loadfile(held_control_path, "t", _G))()
          module.apply("source")
          local ok, message = pcall(function()
            callbacks.init()
            if held_opponent ~= "skipped-transition" then
              callbacks.tick()
              assert(storage.mir5_k2_imersite_held_public_flags.phase == "source-complete")
              callbacks.load(); callbacks.tick()
            end
            -- This is the expected result of the normal fixed MIR lifecycle,
            -- supplied by the host double only to exercise fixture ordering.
            local e, t, h, c = player.technologies[early], player.technologies[tail],
              player.technologies[holder], player.technologies[carrier]
            e.level=3; e.researched=true; e.saved_progress=0; e.enabled=false; e.visible_when_disabled=true
            t.level=4; t.researched=false; t.saved_progress=held_opponent == "saved-progress" and .26 or .27
              ; t.enabled=false; t.visible_when_disabled=false
            h.level=1; h.researched=false; h.saved_progress=0; h.enabled=false; h.visible_when_disabled=false
            c.level=4; c.researched=false; c.saved_progress=0; c.enabled=false; c.visible_when_disabled=false
            player.recipes[powder].productivity_bonus=.06
            if held_opponent == "public-flags" then e.enabled=true end
            script.active_mods["mir-fixture-mir5-k2-imersite-held-public-flags"]="0.2.0"
            module.apply("fixed")
            callbacks.configuration()
            assert(storage.mir5_k2_imersite_held_public_flags.phase == "fixed-prepared")
            callbacks.tick()
            assert(storage.mir5_k2_imersite_held_public_flags.phase == "fixed-complete")
            callbacks.load(); callbacks.tick()
          end)
          return {ok=ok, message=tostring(message), saves=calls.saves, markers=#logs,
            phase=storage.mir5_k2_imersite_held_public_flags and storage.mir5_k2_imersite_held_public_flags.phase,
            foreign=foreign and {early_enabled=foreign.technologies[early].enabled,
              early_visible=foreign.technologies[early].visible_when_disabled,
              tail_enabled=foreign.technologies[tail].enabled,
              tail_visible=foreign.technologies[tail].visible_when_disabled}}
        ''')

    def test_held_public_flags_profiles_pin_e3a_source_and_reviewed_fixed_successor(self):
        source = json.loads(HELD_FLAGS_SOURCE_PROFILE.read_text(encoding="utf-8"))
        fixed = json.loads(HELD_FLAGS_FIXED_PROFILE.read_text(encoding="utf-8"))
        for stage, profile, fixture_version in (("source", source, "0.1.0"), ("fixed", fixed, "0.2.0")):
            with self.subTest(kind=profile["kind"]):
                self.assertEqual(("f210", "2.1", "Defaults"),
                                 (profile["target"], profile["factorio_line"], profile["settings_mode"]))
                self.assertEqual(("2.1.23", ENGINE_SHA),
                                 (profile["engine"]["version"], profile["engine"]["sha256"]))
                mods = {row["name"]: row["version"] for row in profile["mods"]}
                self.assertEqual(("5.0.21000", fixture_version),
                                 (mods["more-infinite-research"], mods["mir-fixture-mir5-k2-imersite-held-public-flags"]))
                self.assertEqual("2.0.19", mods["Krastorio2-spaced-out"])
                fixture_archive, fixture_sha, fixture_bytes = HELD_FLAGS_FIXTURE_ARCHIVES[stage]
                self.assertEqual(EXTERNAL_ARCHIVES,
                                 {name: digest for name, digest in profile["archive_sha256"].items()
                                  if name not in {CURRENT_MIR_NAME, fixture_archive}})
                self.assertEqual(fixture_sha, profile["archive_sha256"][fixture_archive])
                self.assertIn(fixture_sha, profile["scope"])
                self.assertIn(f"{fixture_bytes} bytes", profile["scope"])
        self.assertEqual(CURRENT_MIR_ARCHIVE, source["archive_sha256"][CURRENT_MIR_NAME])
        self.assertEqual(HELD_FLAGS_FIXED_MIR_ARCHIVE, fixed["archive_sha256"][CURRENT_MIR_NAME])
        for expected in (HELD_FLAGS_FIXED_SOURCE, HELD_FLAGS_FIXED_SOURCE_TREE,
                         HELD_FLAGS_FIXED_MIR_ARCHIVE, f"{HELD_FLAGS_FIXED_MIR_BYTES} bytes",
                         "prepared but not a native result"):
            self.assertIn(expected, fixed["scope"])
        for stage, version in (("source", "0.1.0"), ("fixed", "0.2.0")):
            with self.subTest(stage=stage):
                info = json.loads((HELD_FLAGS_FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
                self.assertEqual(("mir-fixture-mir5-k2-imersite-held-public-flags", version),
                                 (info["name"], info["version"]))
                self.assertEqual(
                    f'require("__mir-fixture-mir5-k2-imersite-held-public-flags__/fixture_control").apply("{stage}")\n',
                    (HELD_FLAGS_FIXTURE / stage / "control.lua").read_text(encoding="utf-8"),
                )
        readme = (HELD_FLAGS_FIXTURE / "README.md").read_text(encoding="utf-8")
        for expected in (CURRENT_SOURCE, CURRENT_SOURCE_TREE, CURRENT_MIR_ARCHIVE, "679250 bytes",
                         HELD_FLAGS_FIXED_SOURCE, HELD_FLAGS_FIXED_SOURCE_TREE, HELD_FLAGS_FIXED_MIR_ARCHIVE,
                         f"{HELD_FLAGS_FIXED_MIR_BYTES}-byte", HELD_FLAGS_INPUT_REVISION,
                         "CaseName=k2-imersite-held-public-flags", "exactly seven members",
                         "fixture_control.lua", "fixture_data_final.lua", "fixture_settings.lua",
                         "post-MIR state only", "neither invokes nor evidences the real MIR configuration callback",
                         "Assert-MIRLibraryFixtureArchive", "zero laboratory completions", "pending"):
            self.assertIn(expected, readme)

    def test_held_public_flags_prepared_inputs_bind_raw_git_projections_without_native_callback_claims(self):
        receipt = json.loads(HELD_FLAGS_INPUT_RECEIPT.read_bytes())
        self.assertEqual("MIR5K2ImersiteHeldPublicFlagsPreparedInputsV1", receipt["kind"])
        self.assertEqual(HELD_FLAGS_INPUT_REVISION, receipt["fixture_source_commit"])
        self.assertEqual("k2-imersite-held-public-flags", receipt["case_name"])
        for field in ("native_execution", "library_mutation", "lab_completion", "release_qualification"):
            self.assertIs(receipt[field], False)
        self.assertIn("pending", receipt["saved_input_hashes"])
        self.assertEqual(
            ["info.json", "control.lua", "data-final-fixes.lua", "settings-updates.lua",
             "fixture_control.lua", "fixture_data_final.lua", "fixture_settings.lua"],
            receipt["projection_contract"]["members"],
        )
        self.assertEqual(7, receipt["projection_contract"]["member_count"])
        self.assertIn("no README or alternate metadata", receipt["projection_contract"]["description"])
        self.assertEqual("both-seven-member-source-projections-pass-real-guard", receipt["archive_guard"]["status"])
        self.assertIn("Assert-MIRLibraryFixtureArchive", receipt["archive_guard"]["command"])
        self.assertIn("post-MIR configuration state", receipt["host_control_limit"])
        self.assertIn("neither invokes nor evidences an actual MIR configuration callback", receipt["host_control_limit"])

        profiles = {"source": json.loads(HELD_FLAGS_SOURCE_PROFILE.read_bytes()),
                    "fixed": json.loads(HELD_FLAGS_FIXED_PROFILE.read_bytes())}
        self.assertEqual(["source", "fixed"], [row["stage"] for row in receipt["stages"]])
        for row in receipt["stages"]:
            stage = row["stage"]
            archive, digest, bytes_count = HELD_FLAGS_FIXTURE_ARCHIVES[stage]
            with self.subTest(stage=stage):
                self.assertEqual((archive.rsplit("_", 1)[1][:-4], digest, bytes_count),
                                 (row["version"], row["sha256"], row["bytes"]))
                self.assertEqual(digest, profiles[stage]["archive_sha256"][archive])
                self.assertEqual(7, len(row["members"]))
                expected = {name: f"tests/fixtures/k2-imersite-held-public-flags/{stage}/{name}"
                            for name in ("info.json", "control.lua", "data-final-fixes.lua", "settings-updates.lua")}
                expected.update({name: f"tests/fixtures/k2-imersite-held-public-flags/{name}"
                                 for name in ("fixture_control.lua", "fixture_data_final.lua", "fixture_settings.lua")})
                self.assertEqual(expected, {member["path"]: member["source_path"] for member in row["members"]})
                for revision in (HELD_FLAGS_INPUT_REVISION, "HEAD"):
                    for member in row["members"]:
                        raw = subprocess.check_output(
                            ["git", "show", f"{revision}:{member['source_path']}"], cwd=ROOT)
                        self.assertEqual((member["sha256"], member["bytes"]),
                                         (hashlib.sha256(raw).hexdigest().upper(), len(raw)),
                                         f"{revision}:{member['source_path']}")
        helper = receipt["package_tool"]
        self.assertEqual(FROZEN_PACKAGE_TOOL_SHA256, helper["committed_sha256"])
        self.assertEqual(FROZEN_PACKAGE_TOOL_SHA256, helper["executed_worktree_sha256"])
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            for row in receipt["stages"]:
                with self.subTest(current_helper_stage=row["stage"]):
                    projection = temporary / (row["stage"] + "-projection")
                    projection.mkdir()
                    for member in row["members"]:
                        (projection / member["path"]).write_bytes(subprocess.check_output(
                            ["git", "show", f"{HELD_FLAGS_INPUT_REVISION}:{member['source_path']}"], cwd=ROOT))
                    record = PACKAGE.build(projection, temporary / Path(row["archive"]).name)
                    self.assertEqual((row["sha256"], row["bytes"]),
                                     (record["sha256"].upper(), record["bytes"]))
                    self.assertEqual([{"path": member["path"], "sha256": member["sha256"].lower(),
                                       "bytes": member["bytes"]}
                                      for member in row["members"]], record["members"])

    def test_held_public_flags_data_preflights_the_real_k2so_rows_before_fixture_state(self):
        for stage in ("source", "fixed"):
            with self.subTest(stage=stage):
                result = self._held_flags_data(stage)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(0, result["setting"]["default_value"])
                self.assertEqual(.02, result["rows"][TAIL]["effects"][1]["change"])
        for opponent, phrase, unchanged in (("effect", "Imersite effect differs", TAIL),
                                            ("carrier", "carrier identity differs", CARRIER),
                                            ("missing", "public Imersite continuation row is absent", EARLY),
                                            ("duplicate", "Imersite effect differs", TAIL),
                                            ("setting", "K2SO Imersite maximum default differs", EARLY),
                                            ("closure", "unexpected F210 K2SO Imersite closure", EARLY)):
            with self.subTest(opponent=opponent):
                result = self._held_flags_data("fixed", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertEqual(1 if opponent == "setting" else 0, result["setting"]["default_value"])
                self.assertEqual(.03 if opponent == "effect" else .02,
                                 result["rows"][unchanged]["effects"][1]["change"])

    def test_held_public_flags_control_defers_server_save_and_requires_preserved_unqueued_flags(self):
        source = (HELD_FLAGS_FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        self.assertIn('state.phase ~= "source-complete"', source)
        self.assertIn("game.server_save(SAVE)", source)
        self.assertNotIn("remote.call", source)
        self.assertNotIn("storage.mir", source)
        on_load = source.split("script.on_load", 1)[1].split("script.on_event", 1)[0]
        self.assertNotIn("game.", on_load)
        self.assertNotIn("storage", on_load)
        positive = self._held_flags_flow()
        self.assertTrue(positive["ok"], positive["message"])
        self.assertEqual((2, 4, "fixed-complete"), (positive["saves"], positive["markers"], positive["phase"]))
        self.assertEqual((False, False, False, True),
                         (positive["foreign"]["early_enabled"], positive["foreign"]["early_visible"],
                          positive["foreign"]["tail_enabled"], positive["foreign"]["tail_visible"]))
        corrupted = self._held_flags_flow("public-flags")
        self.assertFalse(corrupted["ok"])
        self.assertIn("public enabled/visibility flags differ", corrupted["message"])
        self.assertEqual((1, 2, "source-complete"), (corrupted["saves"], corrupted["markers"], corrupted["phase"]))
        for opponent, phrase, source_saves in (("saved-progress", "public continuation detached work differs", 1),
                                               ("skipped-transition", "completed E3A source state is absent", 0)):
            with self.subTest(opponent=opponent):
                result = self._held_flags_flow(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertEqual(source_saves, result["saves"])


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

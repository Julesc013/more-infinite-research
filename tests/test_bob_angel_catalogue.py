"""Complete Bob/Angel default publication against independent native references."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import recover_modern_catalogue as catalogue
from test_k2_base_catalogue import _lua_value, _plain
from native_credit_oracle import NATIVE_CREDIT_DEFAULT_SCALAR, NATIVE_CREDIT_DESCRIPTORS, native_credit_carrier_rows, legacy_module_credit_rows, verified_public_rows

SETTINGS_INTENT = ROOT / "spec/inventory/bob-angel-f200-intent-r03.json"
SETTINGS_INTENT_SHA256 = "1D200906E8996F4049009EE6761E73C88FFC70824BC838496786A32EF927207C"
GROWTH_MAXIMUM = 1000
BASE_LITERAL_NAME_PRESENTATION_REPAIRS = {
    # Retain the independent B6 rows unchanged, then apply the two separately
    # reviewed F210 Base locale repairs. Both enclosing MIR keys are literal
    # titles in the shipped locale catalogue; the nested item keys are absent.
    "recipe-prod-research_mining_drill-1": {
        "captured": ["technology-name.more-infinite-research.research_mining_drill",
                     ["item-name.electric-mining-drill"]],
        "emitted": ["technology-name.more-infinite-research.research_mining_drill"],
    },
    "recipe-prod-research_walls-1": {
        "captured": ["technology-name.more-infinite-research.research_walls",
                     ["item-name.stone-wall"]],
        "emitted": ["technology-name.more-infinite-research.research_walls"],
    },
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def canonical_row_sha256(row):
    text = json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def repair_base_literal_name_presentation(data):
    """Apply only the two independently pinned successor presentation fields."""
    repaired = deepcopy(data)
    for technology, expected in BASE_LITERAL_NAME_PRESENTATION_REPAIRS.items():
        actual = repaired["technology"].get(technology, {}).get("localised_name")
        if actual != expected["captured"]:
            raise AssertionError(f"captured Bob/Angel presentation changed: {technology}")
        repaired["technology"][technology]["localised_name"] = deepcopy(expected["emitted"])
    return repaired


class BobAngelCatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = json.loads((ROOT / "tests/fixtures/bob-angel-f200-catalogue-inputs.json").read_text())
        for name in ("published_oracle", "reviewed_intent"):
            record = cls.inputs[name]
            if sha256(ROOT / record["path"]) != record["sha256"]:
                raise AssertionError(f"independent Bob/Angel {name} changed")
        source = cls.inputs["source"]
        if (ROOT / source["path"]).is_file():
            if sha256(ROOT / source["path"]) != source["sha256"]:
                raise AssertionError("local native Bob/Angel input changed")
            native = json.loads((ROOT / source["path"]).read_text())
            # Every portable field is an actual native field. The subset is
            # developer custody, never the player catalogue or test output.
            for kind, rows in cls.inputs["raw"].items():
                for name, fields in rows.items():
                    for field, value in fields.items():
                        if native.get(kind, {}).get(name, {}).get(field) != value:
                            raise AssertionError(f"native input drifted: {kind}/{name}/{field}")
        profile = catalogue._inventory_profile(json.loads(
            (ROOT / cls.inputs["published_oracle"]["path"]).read_text()), "bob-angel-f200")
        cls.expected_data = catalogue._overlay_domain({}, catalogue._intended_domain(profile, "data"), "data")
        cls.expected_settings = catalogue._overlay_domain({}, catalogue._intended_domain(profile, "settings"), "settings")
        reviewed = catalogue._reviewed_differences(ROOT / cls.inputs["reviewed_intent"]["path"], "bob-angel-f200")
        if sha256(SETTINGS_INTENT) != SETTINGS_INTENT_SHA256:
            raise AssertionError("predeclared Bob/Angel growth-cap intent changed")
        r03 = catalogue._reviewed_differences(SETTINGS_INTENT, "bob-angel-f200")
        r03_data = [row for row in r03 if row["domain"] == "data"]
        settings_review = [row for row in r03 if row["domain"] == "settings"]
        if not catalogue._same(reviewed, r03_data):
            raise AssertionError("Bob/Angel r03 changed the retained r02 data dispositions")
        expected_growth_names = {
            name for name, row in cls.expected_settings["double-setting"].items()
            if name.startswith(("ips-cost-growth-", "mir-cost-growth-"))
        }
        if len(settings_review) != 121 or {row["name"] for row in settings_review} != expected_growth_names:
            raise AssertionError("Bob/Angel r03 growth-cap intent does not replace every and only named growth setting")
        for row in settings_review:
            before = cls.expected_settings[row["type"]][row["name"]]
            minimum = 1 if row["name"].startswith("ips-cost-growth-") else 0
            expected = deepcopy(before)
            expected["maximum_value"] = GROWTH_MAXIMUM
            if (row["type"] != "double-setting" or before.get("type") != "double-setting"
                    or before.get("setting_type") != "startup" or before.get("minimum_value") != minimum
                    or "maximum_value" in before
                    or canonical_row_sha256(before) != row.get("independent_before_sha256")
                    or not catalogue._same(expected, row["expected_candidate"])):
                raise AssertionError("Bob/Angel r03 growth-cap record is not an exact independent replacement: " + row["name"])
        catalogue._apply_reviewed(cls.expected_settings, settings_review, "settings")
        # Derive every dormant carrier from the published public rows and
        # captured recipes, independently of candidate or player code.
        public_review = [row for row in reviewed if not row["name"].startswith("mir-native-credit-")]
        catalogue._apply_reviewed(cls.expected_data, public_review, "data")
        cls.expected_data = repair_base_literal_name_presentation(cls.expected_data)
        credits = native_credit_carrier_rows(cls.expected_data["technology"], cls.inputs["raw"]["recipe"])
        credit_review = {row["name"]: row["expected_candidate"] for row in reviewed
                         if row["name"].startswith("mir-native-credit-")}
        if len(reviewed) != 27 or len(public_review) != 7 or len(credits) != 20:
            raise AssertionError("Bob/Angel intent requires seven public dispositions and twenty exact dormant carriers")
        if not catalogue._same(credit_review, credits):
            raise AssertionError("Bob/Angel native comparison credit descriptors differ from independent published routes")
        for family, main_id, recipe in NATIVE_CREDIT_DESCRIPTORS:
            if main_id in cls.expected_data["technology"] and recipe in cls.inputs["raw"]["recipe"]:
                setting = cls.expected_settings["double-setting"]["ips-effect-per-level-" + family]
                if setting["default_value"] != 100 * NATIVE_CREDIT_DEFAULT_SCALAR:
                    raise AssertionError("Credit scalar lacks its independent captured setting default: " + family)
        cls.expected_complete_data = deepcopy(cls.expected_data)
        catalogue._apply_reviewed(cls.expected_complete_data, reviewed, "data")
        cls.expected_complete_data["technology"].update(legacy_module_credit_rows(cls.inputs["raw"]["recipe"]))
        cls.mods = {row["name"]: row["version"] for row in json.loads(
            (ROOT / "tests/profiles/bob-angel-f200-2077.json").read_text())["mods"] if row["enabled"]}

    def stage(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        lua.globals().mods = _lua_value(lua, self.mods)
        lua.globals().captured_raw = _lua_value(lua, deepcopy(self.inputs["raw"]))
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"; package.cpath = ""
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.distribution_version, target.cargo_research = "5.0.20000", false
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "probability", false, true
          settings = {startup={}}; helpers={}; log=function()end
          emitted={}; publications=0; data={raw=captured_raw}
          function data:extend(rows)
            publications=publications+1
            for _,row in ipairs(rows)do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate "..row.name)
              self.raw[row.type][row.name]=row
              emitted[row.type]=emitted[row.type] or {};emitted[row.type][row.name]=row
            end
          end
          assert(loadfile(player_root.."/data.lua"))()
          assert(loadfile(player_root.."/data-final-fixes.lua"))()
        ''')
        return lua

    def test_complete_native_definitions_and_foreign_inputs(self):
        lua = self.stage()
        emitted = _plain(lua.globals().emitted)
        self.assertTrue(catalogue._same(self.expected_complete_data, emitted),
                        f"complete native output: {catalogue._changed_paths(self.expected_complete_data, emitted)}")
        expected = deepcopy(self.expected_data)
        self.assertEqual(len(expected["technology"]), 67)
        public = verified_public_rows(
            emitted["technology"], self.inputs["raw"]["recipe"].keys()
        )
        self.assertEqual(set(public), set(expected["technology"]))
        for name, row in expected["technology"].items():
            found = public[name]
            self.assertTrue(catalogue._same(row, found), f"{name}: {catalogue._changed_paths(row, found)}")
        # Neither the ordinary adapter nor material emission may mutate the
        # source recipe/technology/item/lab tables used for this construction.
        actual = _plain(lua.globals().data.raw)
        for kind, rows in self.inputs["raw"].items():
            for name, row in rows.items():
                self.assertTrue(catalogue._same(row, actual[kind][name]), f"foreign {kind}/{name} changed")
        self.assertEqual(lua.globals().publications, 2)  # shortcut, one complete technology publication
        declared = _plain(lua.execute('return require("research.catalogue").declared()'))
        self.assertEqual({row["id"] for row in declared}, set(expected["technology"]))

    def test_all_875_settings_match_published_fields_with_reviewed_growth_bound(self):
        lua = self.stage()
        rows = _plain(lua.execute('return require("research.settings").prototypes()'))
        actual = {}
        for row in rows:
            actual.setdefault(row["type"], {})[row["name"]] = row
        expected = self.expected_settings
        self.assertEqual(sum(len(rows) for rows in expected.values()), 875)
        self.assertEqual(set(actual), set(expected))
        for kind, rows in expected.items():
            self.assertEqual(set(actual[kind]), set(rows))
            for name, row in rows.items():
                self.assertTrue(catalogue._same(row, actual[kind][name]),
                                f"{kind}/{name}: {catalogue._changed_paths(row, actual[kind][name])}")

    def test_dormant_credit_oracle_retains_excluded_routes_and_rejects_conflicting_effects(self):
        rows = deepcopy(self.expected_data["technology"])
        recipes = self.inputs["raw"]["recipe"]
        name = "recipe-prod-research_lubricant_productivity-1"
        self.assertFalse(any(effect.get("recipe") == "lubricant" for effect in rows[name]["effects"]))
        dormant = native_credit_carrier_rows(rows, recipes)
        for direction in ("positive", "negative"):
            row = dormant["mir-native-credit-research_lubricant_productivity-lubricant-" + direction]
            self.assertFalse(row["enabled"])
            self.assertTrue(row["hidden"])
        wrong = {"type": "change-recipe-productivity", "recipe": "lubricant", "change": 0.2}
        rows[name]["effects"].append(wrong)
        with self.assertRaisesRegex(AssertionError, "conflicting captured default route"):
            native_credit_carrier_rows(rows, recipes)
        wrong["change"] = NATIVE_CREDIT_DEFAULT_SCALAR
        rows[name]["effects"].append(deepcopy(wrong))
        with self.assertRaisesRegex(AssertionError, "conflicting captured default route"):
            native_credit_carrier_rows(rows, recipes)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelCatalogueTests))
    sys.exit(0 if result.wasSuccessful() else 1)

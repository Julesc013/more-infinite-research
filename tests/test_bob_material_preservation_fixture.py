"""Opposing host controls for the disposable Bob paid-state transition.

No Factorio execution or saved-state acceptance follows from these controls.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/bob-material-preservation"
FAMILIES = ("tin", "lead", "bronze", "gunmetal", "invar", "nitinol", "copper_tungsten")
RECIPES = ("bob-tin-plate", "bob-lead-plate", "bob-bronze-alloy", "bob-gunmetal-alloy",
           "bob-invar-alloy", "bob-nitinol-alloy", "bob-copper-tungsten-alloy")


def source_snapshot():
    return dict(current="bronze-tail", queue=["bronze-tail", "bronze-tail", "automation"],
                progress=0.42, lead_saved=0.27,
                technologies={f"paid-{key}": dict(level=5, researched=False, enabled=True)
                              for key in FAMILIES},
                bonuses={name: 0.08 for name in RECIPES})


class PreservationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.control = self.lua.execute((FIXTURE / "fixture_control.lua").read_text(encoding="utf-8"))
        self.data_module = self.lua.execute((FIXTURE / "fixture_data.lua").read_text(encoding="utf-8"))

    def table(self, value):
        return self.lua.table_from(value, recursive=True)

    def check(self, actual, expected, exact=False):
        self.control.assert_preserved(self.table(actual), self.table(expected), "opponent", exact)

    def test_retained_source_and_only_policy_enablement_change_are_accepted(self):
        expected = source_snapshot()
        self.check(expected, expected, True)
        changed = deepcopy(expected)
        changed["technologies"]["paid-tin"]["enabled"] = False
        self.check(changed, expected)
        with self.assertRaisesRegex(Exception, "enablement changed"):
            self.check(changed, expected, True)

    def test_each_lost_recipe_bonus_is_rejected(self):
        expected = source_snapshot()
        for name in RECIPES:
            with self.subTest(recipe=name):
                actual = deepcopy(expected)
                actual["bonuses"][name] = 0
                with self.assertRaisesRegex(Exception, "earned recipe effect changed"):
                    self.check(actual, expected)

    def test_each_paid_identity_reset_or_deletion_is_rejected(self):
        expected = source_snapshot()
        for key in expected["technologies"]:
            for mode in ("level", "researched", "missing"):
                with self.subTest(identity=key, mode=mode):
                    actual = deepcopy(expected)
                    if mode == "missing":
                        del actual["technologies"][key]
                    else:
                        actual["technologies"][key][mode] = 1 if mode == "level" else True
                    with self.assertRaisesRegex(Exception, "paid native level changed"):
                        self.check(actual, expected)

    def test_current_progress_detached_work_and_queue_corruption_are_rejected(self):
        expected = source_snapshot()
        for field, value in (("progress", 0), ("lead_saved", 0), ("current", False),
                             ("queue", ["bronze-tail", "automation"]),
                             ("queue", ["bronze-tail", "automation", "bronze-tail"])):
            with self.subTest(field=field, value=value):
                actual = deepcopy(expected)
                actual[field] = value
                with self.assertRaisesRegex(Exception, "work changed|queue order changed"):
                    self.check(actual, expected)

    def raw(self, stage):
        technologies = {}
        for key, recipe in zip(FAMILIES, RECIPES):
            for suffix in ("1", "4"):
                disabled = stage != "source" and key != "lead" and not (stage == "readmitted" and key == "tin")
                technologies[f"recipe-prod-research_material_{key}-{suffix}"] = dict(
                    enabled=not disabled, effects=[dict(type="change-recipe-productivity", recipe=recipe, change=0.02)],
                    unit=dict(count_formula="independent-before", time=30,
                              ingredients=[["automation-science-pack", 1]]))
        return {"technology": technologies, "int-setting": {
            "ips-max-level-research_material_tin": dict(default_value=0)}}

    def test_all_three_data_stages_keep_effects_and_apply_only_timing_and_cap(self):
        for stage, cap in (("source", 4), ("unavailable", 7), ("readmitted", 7)):
            with self.subTest(stage=stage):
                raw = self.raw(stage)
                before = deepcopy(raw)
                data = self.table(dict(raw=raw))
                self.lua.globals().data = data
                self.data_module.settings(stage)
                self.data_module.accelerate(stage)
                self.assertEqual(data.raw["int-setting"]["ips-max-level-research_material_tin"].default_value, cap)
                for name, expected in before["technology"].items():
                    actual = data.raw.technology[name]
                    self.assertEqual(actual.effects[1].recipe, expected["effects"][0]["recipe"])
                    self.assertEqual(actual.effects[1].change, 0.02)
                    if name in ("recipe-prod-research_material_tin-4", "recipe-prod-research_material_bronze-4"):
                        self.assertEqual(actual.unit.count, 100)
                        self.assertIsNone(actual.unit.count_formula)
                    else:
                        self.assertEqual(actual.unit.count_formula, "independent-before")

    def test_wrong_effect_or_admission_never_gets_accelerated_into_a_pass(self):
        for field, value in (("change", 0.01), ("recipe", "wrong-recipe"), ("type", "nothing")):
            raw = self.raw("unavailable")
            raw["technology"]["recipe-prod-research_material_tin-4"]["effects"][0][field] = value
            self.lua.globals().data = self.table(dict(raw=raw))
            with self.subTest(field=field), self.assertRaisesRegex(Exception, "identity/effect differs"):
                self.data_module.accelerate("unavailable")
        raw = self.raw("unavailable")
        raw["technology"]["recipe-prod-research_material_bronze-4"]["enabled"] = True
        self.lua.globals().data = self.table(dict(raw=raw))
        with self.assertRaisesRegex(Exception, "returning route was admitted"):
            self.data_module.accelerate("unavailable")

    def test_wrappers_pin_real_predecessor_and_distinct_successor_stages(self):
        for stage, version, mir in (("source", "0.1.0", "5.0.21005"),
                                    ("unavailable", "0.2.0", "5.0.21006"),
                                    ("readmitted", "0.3.0", "5.0.21006")):
            info = json.loads((FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
            self.assertEqual(info["version"], version)
            self.assertIn("more-infinite-research = " + mir, info["dependencies"])
            for name in ("control.lua", "data.lua", "data-final-fixes.lua", "settings-updates.lua"):
                body = (FIXTURE / stage / name).read_text(encoding="utf-8")
                self.lua.execute("assert(load(...))", body)
                self.assertIn('("' + stage + '")', body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]], verbosity=2)

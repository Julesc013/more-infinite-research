"""Independent full/individual BobTech continuation science and publication."""
import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest

import test_bob_plates_f210_pipeline as pipeline

ROOT = Path(__file__).resolve().parents[1]
CONTEXT = ROOT / "tests/fixtures/bob-tech-progression-f210-upstream-context.json.gz"
CONTEXT_SHA256 = "724E48BBACAA76FA18E692CA13A8D8314948EB60D6DDD49538700E99D37B3BD3"
ENGINE = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
PUBLISHED = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"


class BobTechProgressionF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data = CONTEXT.read_bytes()
        if len(data) > 192 * 1024 or hashlib.sha256(data).hexdigest().upper() != CONTEXT_SHA256:
            raise AssertionError("BobTech upstream-only context identity/bound changed")
        cls.context = json.loads(gzip.decompress(data))
        pipeline.BobPlatesF210PipelineTests.setUpClass()

    def stage(self, case, *, raw=None, startup=None):
        captured = self.context["cases"][case]
        lua = LuaRuntime(unpack_returned_tuples=True)
        # Capture the real runtime even when preflight raises. Only its Python
        # factory is supplied; every Lua module and stage executes unchanged.
        original = pipeline.LuaRuntime
        pipeline.LuaRuntime = lambda **options: lua
        try:
            pipeline.BobPlatesF210PipelineTests().stage("q097", startup_overrides=startup,
                raw_override=raw if raw is not None else captured["raw"], mods_override=captured["selection"])
            return lua, None
        except Exception as error:
            return lua, str(error)
        finally:
            pipeline.LuaRuntime = original

    def test_exact_upstream_and_published_provenance_excludes_candidate_worlds(self):
        self.assertEqual("MIR5BobTechProgressionF210PipelineContextV1", self.context["schema"])
        self.assertEqual({"q005", "q113", "q114"}, set(self.context["cases"]))
        self.assertIn("no candidate world", self.context["scope"])
        for case in self.context["cases"].values():
            for arm in ("upstream", "published"):
                provenance = case["provenance"][arm]
                self.assertEqual(ENGINE, provenance["engine"]["sha256"])
                self.assertEqual("ea41cbc6d27626283db9d8bbf6211b2171b6e36a", provenance["source_head"])
                self.assertEqual(64, len(provenance["raw_sha256"]))
            self.assertEqual(PUBLISHED, case["provenance"]["published"]["mir_archive"]["sha256"])
            self.assertIsNone(case["provenance"]["upstream"]["mir_archive"])

    def test_full_pipeline_matches_all_ten_independent_published_continuations(self):
        for case, count in (("q005", 2), ("q113", 4), ("q114", 4)):
            with self.subTest(case=case):
                lua, error = self.stage(case)
                self.assertIsNone(error)
                emitted = pipeline._plain(lua.globals().emitted)
                expected = self.context["cases"][case]["expected"]
                self.assertEqual(count, len(expected))
                for name, published in expected.items():
                    self.assertIn(name, emitted)
                    self.assertEqual(pipeline._technology_contract(published),
                                     pipeline._technology_contract(emitted[name]), (case, name))

    def test_configured_time_cost_and_effect_preserve_the_native_science_choice(self):
        for case in ("q005", "q113", "q114"):
            with self.subTest(case=case):
                lua, error = self.stage(case, startup={"mir-cost-base-research-speed": 500,
                    "mir-research-time-research-speed": 45, "mir-effect-per-level-research-speed": 25})
                self.assertIsNone(error)
                actual = pipeline._plain(lua.globals().emitted)["research-speed-7"]
                expected = self.context["cases"][case]["expected"]["research-speed-7"]
                self.assertEqual(expected["unit"]["ingredients"], actual["unit"]["ingredients"])
                self.assertEqual(expected["prerequisites"], actual["prerequisites"])
                self.assertEqual(45, actual["unit"]["time"])
                # The historical configured base is level one's cost:
                # 500 * 1.5^6 = 5695.3125 when the native tail starts at seven.
                self.assertEqual("5695.3125*1.5^(L-7)", actual["unit"]["count_formula"])
                self.assertEqual([{"type": "laboratory-speed", "modifier": .25}], actual["effects"])

    def test_named_science_drift_refuses_before_any_technology_publication(self):
        for case, kind, name in (("q005", "recipe", "bob-alien-science-pack-blue"),
                                 ("q005", "lab", "bob-lab-alien"),
                                 ("q113", "recipe", "bob-advanced-logistic-science-pack"),
                                 ("q114", "technology", "bob-advanced-logistic-science-pack")):
            with self.subTest(case=case, kind=kind, name=name):
                raw = deepcopy(self.context["cases"][case]["raw"])
                raw[kind].pop(name)
                lua, error = self.stage(case, raw=raw)
                self.assertIsNotNone(error)
                self.assertIn("progression", error)
                self.assertEqual(0, lua.globals().technology_writes)

    def test_repeated_profile_bindings_do_not_expose_shared_core_tables(self):
        for case in ("q005", "q113", "q114"):
            with self.subTest(case=case):
                lua, error = self.stage(case)
                self.assertIsNone(error)
                self.assertTrue(lua.execute('''
                  local adapter = require("compatibility.modern_catalogue.bob_tech_progression")
                  local first = adapter.continuation_overrides(mods, data.raw)
                  local expected = first.research_speed.science
                  first.research_speed.science = "corrupted"
                  local second = adapter.continuation_overrides(mods, data.raw)
                  return first ~= second and first.research_speed ~= second.research_speed
                    and second.research_speed.science == expected
                '''))

    def test_unusable_or_conflicting_alien_output_probability_refuses_before_publication(self):
        for fields in ({"probability": 0}, {"independent_probability": 0},
                       {"probability": 1, "independent_probability": 1},
                       {"probability": float("nan")}, {"independent_probability": float("inf")},
                       {"shared_probability": {"min": 0, "max": 0}},
                       {"shared_probability": {"min": 0, "max": 2}}):
            with self.subTest(fields=fields):
                raw = deepcopy(self.context["cases"]["q005"]["raw"])
                product = raw["recipe"]["bob-alien-science-pack-blue"]["results"][0]
                for name in ("probability", "independent_probability", "shared_probability"):
                    product.pop(name, None)
                product.update(fields)
                lua, error = self.stage("q005", raw=raw)
                self.assertIsNotNone(error)
                self.assertIn("named alien science output changed: bob-alien-science-pack-blue", error)
                self.assertEqual(0, lua.globals().technology_writes)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    pipeline.LuaRuntime = LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobTechProgressionF210PipelineTests))
    raise SystemExit(not result.wasSuccessful())

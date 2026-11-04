"""Published cost-family expectations through the named native-owner boundary; host only."""
import argparse
from copy import deepcopy
from pathlib import Path
import sys
import unittest

from historical_sources import read_published_source
import test_generator as generator_fixture
import test_native_family_product_targets as fixture

ROOT = Path(__file__).resolve().parents[1]
LEGACY = {
    "prototypes.mir.domain.native_owner.cost_model": "A74598753DD9E990BC23291010901ACE499725363967FB41E374CDCA34B37CE9",
    "prototypes.mir.domain.research_cost.classification": "6208A3BDBEE81D0B7391F2BB25CA8ABFDECC01527E3827D4B80C4431ED9139D1",
    "prototypes.mir.domain.research_cost.model": "89072B22B2ADE5D0DFEF8FAB60DFFC5B784466364F0D5E875B1BF18C90ABA32A",
    "prototypes.mir.domain.research_cost.formula": "574C8B3CD07E91A4ECFECD8259443E568940C27EC5FC137E2D25FF5A38F30627",
    "prototypes.mir.domain.research_cost.validation": "2A66484BB453D7C9BF18F29DB3DF54CF45404603004A0993463EC7553DFF28D0",
    "prototypes.mir.core.deepcopy": "D18F286FD1AAFA9648133B7E32217F6B4B1E7697B2590D7A793F165447F3524C",
    "prototypes.mir.core.fingerprint": "737FF86E4507177CA0986B92A0A8C383FF82EB00D3534A87AAD9FBCAE057F05A",
}
FORMULAS = [
    "1000", "1000+250*(L-1)", "250*L+750", "(L+3)*250", "1000/2+250*L",
    "1.5^L*1000", "1000*1.5^(L-1)", "2^(L+2)*1000",
    "(1000+250*(L-1))*1.25^(L-1)", "1.25^(L-1)*(1000+250*(L-1))",
    "1e3+2.5e2*(l-1)", "-(250-500*L)+1000", "2^(L-1)",
    "1^(L-1)", "L^0+999", "(L*L)^0*1000",
]
UNKNOWN = [
    "1000+100*L^2", "1000+0.5*(L-1)", "1000-250*(L-1)", "0", "1e301",
    "1000*0.9^(L-1)", "1000/0", "1000+sin(L)", "1000+L*L", "1000--comment",
]


class NativeOwnerCostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture.LuaRuntime = LuaRuntime
        fixture.NativeFamilyProductTargetTests.setUpClass()
        # Exact complete modules from the published4.7.2 Git object; all seven
        # bodies are also identical at4.7.3. No live-source fallback or retired
        # compiler/controller is executed. These pure modules are host oracles.
        cls.originals = {name: read_published_source(ROOT, "source/" + name.replace(".", "/") + ".lua", sha).decode()
                         for name, sha in LEGACY.items()}

    def setUp(self):
        self.case = fixture.NativeFamilyProductTargetTests()
        self.case.setUp()
        self.lua = self.case.lua
        self.lua.globals().legacy_sources = generator_fixture.lua_table(self.lua, self.originals)
        self.lua.execute('''
          for name,source in pairs(legacy_sources) do
            package.preload[name]=assert(load(source,"@published472/"..name,"t",_G))
          end
          original_cost=require("prototypes.mir.domain.native_owner.cost_model")
          function original_style(unit)
            local ok,model=pcall(original_cost.classify,unit,nil,{technology_name="processing-unit-productivity"})
            if not ok or model.style=="preserve-only" then return nil end
            return model.style=="fixed-count" and "fixed-count" or "formula"
          end
          function original_configured(unit,base,increment,growth)
            local model=original_cost.classify(unit,nil,{technology_name="processing-unit-productivity"})
            return assert(original_cost.configure(model,{base=base,linear_increment=increment,growth=growth}))
          end
        ''')

    def unit(self, cost):
        return {"count": cost} if isinstance(cost, (int, float)) else {"count_formula": cost}

    def configure(self, cost, values=(200, 3, 1.25)):
        for family in fixture.OWNERS:
            owner = self.case.owner(family)
            owner.unit["count"], owner.unit["count_formula"] = None, None
            for key, value in self.unit(cost).items():
                owner.unit[key] = value
            owner.unit["fixture_field"] = "retained"
            for prefix, value in zip(("ips-cost-base-", "ips-cost-linear-increment-", "ips-cost-growth-"), values):
                self.lua.globals().settings.startup[prefix + family].value = value

    def test_recognized_family_admission_matches_original_bounded_classifier(self):
        classifier = self.lua.eval('require("compatibility.native_owner_cost")')
        for cost in [1000, *FORMULAS]:
            with self.subTest(cost=cost):
                unit = generator_fixture.lua_table(self.lua, self.unit(cost))
                original = self.lua.globals().original_style(unit)
                self.assertIsNotNone(original)
                self.assertEqual(classifier.classify(unit), original)

    def test_unrecognized_and_budgeted_formulas_match_original_safe_nonbinding(self):
        classifier = self.lua.eval('require("compatibility.native_owner_cost")')
        for text in [*UNKNOWN, "(" * 40 + "1000" + ")" * 40, "1+" * 80 + "1000", " " * 513 + "1000"]:
            with self.subTest(text=text[:70]):
                unit = generator_fixture.lua_table(self.lua, self.unit(text))
                self.assertIsNone(self.lua.globals().original_style(unit))
                self.assertIsNone(classifier.classify(unit))

    def test_invalid_count_and_conflicting_fields_are_not_admitted(self):
        classifier = self.lua.eval('require("compatibility.native_owner_cost")')
        for unit in ({}, {"count": 0}, {"count": -1}, {"count": 1.5}, {"count": float("inf")},
                     {"count": 1000, "count_formula": "1000"}, {"count_formula": False}):
            self.assertIsNone(classifier.classify(generator_fixture.lua_table(self.lua, unit)))

    def test_pipeline_configured_cost_accepts_each_recognized_model(self):
        for cost in (1000, "1000", "1000+250*(L-1)", "1.5^L*1000", "(1000+250*(L-1))*1.25^(L-1)"):
            with self.subTest(cost=cost):
                self.setUp()
                self.configure(cost)
                before = self.case.owner_rows()
                expected = self.lua.globals().original_configured(generator_fixture.lua_table(self.lua, self.unit(cost)), 200, 3, 1.25)
                self.case.pipeline()
                for family, owner in self.case.owner_rows().items():
                    self.assertEqual(owner["unit"].get("count"), expected.count)
                    self.assertEqual(owner["unit"].get("count_formula"), expected.count_formula)
                    wanted = deepcopy(before[family]["unit"])
                    wanted.pop("count", None)
                    wanted["count_formula"] = "(200+3*(L-1))*1.25^(L-1)"
                    self.assertEqual(owner["unit"], wanted)

    def test_fixed_output_preserves_numeric_versus_formula_representation(self):
        for cost in (1000, "1000", "1000+250*(L-1)"):
            with self.subTest(cost=cost):
                self.setUp()
                self.configure(cost, (200, 0, 1))
                expected = self.lua.globals().original_configured(generator_fixture.lua_table(self.lua, self.unit(cost)), 200, 0, 1)
                self.case.pipeline()
                for owner in self.case.owner_rows().values():
                    self.assertEqual(owner["unit"].get("count"), expected.count)
                    self.assertEqual(owner["unit"].get("count_formula"), expected.count_formula)

    def test_each_visible_knob_activates_the_whole_effective_tuple(self):
        for values in ((200, 0, 2), (8000, 3, 2), (8000, 0, 1.25)):
            with self.subTest(values=values):
                self.setUp()
                self.configure("1000+250*(L-1)", values)
                expected = self.lua.globals().original_configured(generator_fixture.lua_table(self.lua, {"count_formula": "1000+250*(L-1)"}), *values)
                self.case.pipeline()
                for owner in self.case.owner_rows().values():
                    self.assertEqual(owner["unit"].get("count_formula"), expected.count_formula)

    def test_inherited_or_independent_time_effect_never_loads_cost_classifier(self):
        for values in ((None, None), (17, None), (None, 31), (17, 31)):
            with self.subTest(values=values):
                self.setUp()
                for family in fixture.OWNERS:
                    owner = self.case.owner(family)
                    owner.unit.count_formula = "1000+100*L^2"
                    if values[0] is not None:
                        self.lua.globals().settings.startup["ips-effect-per-level-" + family].value = values[0]
                    if values[1] is not None:
                        self.lua.globals().settings.startup["ips-research-time-" + family].value = values[1]
                self.lua.execute('package.preload["compatibility.native_owner_cost"]=function() error("inactive cost classifier imported") end')
                self.case.pipeline()
                for owner in self.case.owner_rows().values():
                    self.assertEqual(owner["unit"]["count_formula"], "1000+100*L^2")

    def test_late_unknown_cost_withholds_only_that_owner(self):
        self.configure(1000)
        self.case.owner("research_steel").unit.count = None
        self.case.owner("research_steel").unit.count_formula = "1000+100*L^2"
        before = self.case.owner_rows()
        self.case.pipeline()
        after = self.case.owner_rows()
        self.assertEqual(before["research_steel"], after["research_steel"])
        for family in fixture.OWNERS:
            if family != "research_steel":
                self.assertEqual("(200+3*(L-1))*1.25^(L-1)", after[family]["unit"]["count_formula"])
        self.assertEqual(1, self.lua.globals().data.writes)
        private = self.lua.globals().data.raw["mod-data"]["more-infinite-research-native-adoptions"].data
        self.assertTrue(private.withheld["steel-plate-productivity"].generated)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    unittest.main(argv=[sys.argv[0], *remaining])

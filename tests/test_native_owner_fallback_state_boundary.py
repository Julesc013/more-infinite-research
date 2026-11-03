"""MIG-01 data-boundary counterexamples for the unfinished fallback draft.

These expose identity/startup gaps before native earned/partial/queue tests.
They do not emulate engine persistence or prescribe a credit implementation.
The known failures deliberately remain outside the accepted host plan until
the complete state policy is implemented and independently reviewed.
"""
import argparse
from pathlib import Path
import sys
import unittest

import test_native_owner_fallback as fallback
import test_sif_retained_manufacturing as sif
import test_generator as generator


class FallbackStateBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fallback.LuaRuntime = LuaRuntime
        fallback.NativeOwnerFallbackTests.setUpClass()

    def test_clearing_cost_override_retains_the_previously_public_identity(self):
        for family in fallback.fixture.OWNERS:
            with self.subTest(family=family):
                source = fallback.NativeOwnerFallbackTests().boot(family, uncovered=True, combined=True)
                source.pipeline()
                name = "recipe-prod-" + family + "-1"
                self.assertIsNotNone(source.lua.globals().data.raw.technology[name])
                destination = fallback.NativeOwnerFallbackTests().boot(family, uncovered=True, combined=True)
                destination.lua.globals().family = family
                destination.lua.execute('''
                  for _,row in ipairs(require("research.settings").prototypes()) do
                    if row.name=="ips-cost-base-"..family
                      or row.name=="ips-cost-linear-increment-"..family
                      or row.name=="ips-cost-growth-"..family then
                      settings.startup[row.name].value=row.default_value
                    end
                  end
                ''')
                destination.pipeline()
                retained = destination.lua.globals().data.raw.technology[name]
                self.assertIsNotNone(retained,
                    "engine loading cannot preserve earned/partial/queued state for an omitted prior MIR identity")
                self.assertIs(True, retained.hidden)
                self.assertEqual(fallback.fixture.plain(source.lua.globals().data.raw.technology[name].effects),
                                 fallback.fixture.plain(retained.effects))

    def test_private_retention_does_not_grant_another_familys_prior_native_claim(self):
        family = "research_steel"
        def boot(*, clear_cost):
            case = fallback.NativeOwnerFallbackTests().boot(family, uncovered=True, combined=True)
            case.lua.execute('''
              data.raw.recipe["multi-native"]={type="recipe",name="multi-native",category="crafting",
                enabled=false,allow_productivity=true,
                ingredients={{type="item",name="iron-plate",amount=5}},
                results={{type="item",name="low-density-structure",amount=1},{type="item",name="steel-plate",amount=1}}}
            ''')
            if clear_cost:
                case.lua.execute('''
                  for _,row in ipairs(require("research.settings").prototypes()) do
                    if row.name=="ips-cost-base-research_steel"
                      or row.name=="ips-cost-linear-increment-research_steel"
                      or row.name=="ips-cost-growth-research_steel" then
                      settings.startup[row.name].value=row.default_value
                    end
                  end
                ''')
            case.pipeline()
            return case
        source, destination = boot(clear_cost=False), boot(clear_cost=True)
        name = "recipe-prod-research_steel-1"
        expected = [{"type": "change-recipe-productivity", "recipe": fallback.fixture.RECIPES[family], "change": .17}]
        self.assertEqual(expected, fallback.fixture.plain(source.lua.globals().data.raw.technology[name].effects))
        self.assertEqual(expected, fallback.fixture.plain(destination.lua.globals().data.raw.technology[name].effects),
                         "a private holder must not grant unpaid effects for the earlier LDS-owned recipe")

    def test_sif_paid_identities_and_uncovered_fallback_can_compose(self):
        family = "research_processing_unit"
        case = fallback.NativeOwnerFallbackTests().boot(family, uncovered=True, combined=True)
        sif.LuaRuntime = LuaRuntime
        paid = sif.SIFRetainedManufacturingTests()
        paid.setUp()
        case.lua.globals().paid_raw = generator.lua_table(case.lua, paid.raw)
        case.lua.execute('''
          local target=require("platform.target")
          target.id,target.factorio_version,target.minimum_base="f200","2.0","2.0.77"
          target.cargo_research,target.productivity_ignores_stats=false,true
          target.recipe_probability,target.receiver_limits="probability",false
          mods={base="2.0.77",["space-age"]="2.0.77",["space-is-fake"]="1.0.60",["cr-commons"]="1.0.27"}
          for kind,rows in pairs(paid_raw) do
            data.raw[kind]=data.raw[kind] or {}
            for name,row in pairs(rows) do data.raw[kind][name]=row end
          end
          data.raw.technology["processing-unit-productivity"].unit.count_formula="1000 + 100 * L^2"
        ''')
        before = case.owner_rows()
        case.pipeline()
        self.assertEqual(before, case.owner_rows())
        for row in sif.EXPECTED["rows"]:
            self.assertIsNotNone(case.lua.globals().data.raw.technology[row["id"]])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

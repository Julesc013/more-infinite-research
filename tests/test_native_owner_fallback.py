"""Published native-cost nonbinding and ordinary Space Age fallback expectations; host only."""
import argparse
from pathlib import Path
import sys
import unittest

from historical_sources import read_published_source
import test_native_family_product_targets as fixture

BASE_SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
# Published4.7.3 science_selector's default branch and STREAM_EXTRA_PACKS,
# independent of the candidate catalogue. Its science/progression policies
# still need their affected native observations.
EXTRA_SCIENCE = {
    "research_low_density_structure": {"metallurgic-science-pack"},
    "research_plastic": {"agricultural-science-pack"},
    "research_processing_unit": {"electromagnetic-science-pack"},
    "research_rocket_fuel": {"agricultural-science-pack"},
    "research_steel": set(),
}
POLYNOMIAL = "1000 + 100 * L^2"


class NativeOwnerFallbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture.LuaRuntime = LuaRuntime
        fixture.NativeFamilyProductTargetTests.setUpClass()
        cls.science_original = read_published_source(Path(__file__).resolve().parents[1],
            "source/prototypes/mir/capabilities/science_integration/science_selector.lua",
            "8425E1E6FA44EFB99084BFB951558647F6D4736FFB44E877C5A6C58ED6B264E4")

    def boot(self, family, *, uncovered=False, combined=False):
        case = fixture.NativeFamilyProductTargetTests()
        case.setUp()
        lua = case.lua
        for key, recipe in fixture.RECIPES.items():
            if key != family or not uncovered:
                lua.globals().data.raw.recipe[recipe] = None
        owner = case.owner(family)
        owner.unit.count_formula = POLYNOMIAL
        for key, value in [("ips-cost-base-", 200), ("ips-cost-linear-increment-", 3), ("ips-cost-growth-", 1.25)]:
            lua.globals().settings.startup[key + family].value = value
        if combined:
            for key, value in [("ips-effect-per-level-", 17), ("ips-research-time-", 31), ("ips-max-level-", 50)]:
                lua.globals().settings.startup[key + family].value = value
        return case

    def test_covered_only_preserves_native_without_a_duplicate_mir_identity(self):
        # The original final-stage assertion explicitly requires nonbinding,
        # polynomial retention and absent recipe-prod ID in this selection.
        for family in fixture.OWNERS:
            with self.subTest(family=family):
                case = self.boot(family, combined=True)
                before = case.owner_rows()
                case.pipeline()
                self.assertEqual(before, case.owner_rows())
                self.assertIsNone(case.lua.globals().data.raw.technology["recipe-prod-" + family + "-1"])

    def test_uncovered_producer_uses_existing_mir_identity_and_original_science(self):
        for family in fixture.OWNERS:
            with self.subTest(family=family):
                case = self.boot(family, uncovered=True, combined=True)
                before = case.owner_rows()
                case.pipeline()
                self.assertEqual(before, case.owner_rows())
                row = fixture.plain(case.lua.globals().data.raw.technology["recipe-prod-" + family + "-1"])
                self.assertEqual([{"type": "change-recipe-productivity", "recipe": fixture.RECIPES[family], "change": .17}], row["effects"])
                self.assertEqual("(200+3*(L-1))*1.25^(L-1)", row["unit"]["count_formula"])
                self.assertNotIn("count", row["unit"])
                self.assertEqual(31, row["unit"]["time"])
                packs = {ingredient[0] if isinstance(ingredient, list) else ingredient["name"] for ingredient in row["unit"]["ingredients"]}
                self.assertEqual(BASE_SCIENCE | EXTRA_SCIENCE[family], packs)

    def test_control_catalogue_distinguishes_withheld_native_and_actual_mir_route(self):
        family = "research_processing_unit"
        for uncovered in (False, True):
            with self.subTest(uncovered=uncovered):
                case = self.boot(family, uncovered=uncovered, combined=True)
                case.pipeline()
                case.lua.execute('''
                  script={active_mods=mods}
                  prototypes={technology={},mod_data={}}
                  local private=data.raw["mod-data"]["more-infinite-research-native-adoptions"]
                  prototypes.mod_data[private.name]={data=private.data}
                  -- Factorio parses control in a fresh Lua state. The host
                  -- harness has already imported this module in settings.
                  package.loaded["research.catalogue"]=nil
                  package.loaded["runtime.catalogue"]=nil
                  control_rows=require("runtime.catalogue").declared()
                ''')
                ids = {row["id"] for row in fixture.plain(case.lua.globals().control_rows)}
                self.assertNotIn("processing-unit-productivity", ids)
                self.assertEqual(uncovered, "recipe-prod-research_processing_unit-1" in ids)

    def test_internal_duplicate_still_rejects_before_all_native_writes(self):
        family = "research_processing_unit"
        case = self.boot(family, uncovered=True, combined=True)
        case.lua.execute('''
          data.raw.technology["recipe-prod-research_processing_unit-1"]={
            type="technology",name="recipe-prod-research_processing_unit-1",foreign_sentinel=42}
        ''')
        before = case.owner_rows()
        with self.assertRaisesRegex(LuaError, "duplicate technology recipe-prod-research_processing_unit-1"):
            case.pipeline()
        self.assertEqual(before, case.owner_rows())
        self.assertEqual(0, case.lua.globals().data.writes)
        self.assertEqual(42, case.lua.globals().data.raw.technology["recipe-prod-research_processing_unit-1"].foreign_sentinel)

    def test_mixed_count_and_formula_remains_a_real_refusal(self):
        family = "research_processing_unit"
        case = self.boot(family)
        case.owner(family).unit.count = 1000
        before = case.owner_rows()
        with self.assertRaisesRegex(LuaError, "native-owner preflight"):
            case.pipeline()
        self.assertEqual(before, case.owner_rows())
        self.assertEqual(0, case.lua.globals().data.writes)

    def test_withheld_transport_is_detached_and_old_empty_data_remains_readable(self):
        case = self.boot("research_processing_unit")
        case.lua.execute('''
          local transport=require("research.native_adoption")
          local definitions=require("compatibility.modern_catalogue").native_owners(mods)
          local private=data.raw["mod-data"][transport.prototype_name]
          local decisions={["processing-unit-productivity"]={family="research_processing_unit",generated=false}}
          local patch=transport.plan(data.raw,{},decisions)
          assert(next(private.data.withheld)==nil)
          transport.apply(patch)
          local adopted,withheld=transport.read(private.data,definitions)
          assert(next(adopted)==nil and withheld["processing-unit-productivity"].generated==false)
          withheld["processing-unit-productivity"].generated=true
          assert(private.data.withheld["processing-unit-productivity"].generated==false)
          local old,empty=transport.read({schema=1,owners={}},definitions)
          assert(next(old)==nil and next(empty)==nil)
        ''')

    def test_withheld_transport_refuses_unknown_mismatched_and_untyped_owners(self):
        case = self.boot("research_processing_unit")
        case.lua.execute('''
          local transport=require("research.native_adoption")
          local definitions=require("compatibility.modern_catalogue").native_owners(mods)
          for _,bad in ipairs({
            {["foreign-productivity"]={family="research_processing_unit",generated=false}},
            {["processing-unit-productivity"]={family="research_steel",generated=false}},
            {["processing-unit-productivity"]={family="research_processing_unit",generated=1}},
            {["processing-unit-productivity"]={family="research_processing_unit",generated=false,owner_override=true}}
          }) do
            assert(not pcall(transport.plan,data.raw,{},bad))
            assert(not pcall(transport.read,{schema=1,owners={},withheld=bad},definitions))
          end
          assert(next(data.raw["mod-data"][transport.prototype_name].data.withheld)==nil)
        ''')

    def test_one_native_owner_cannot_be_both_adopted_and_withheld(self):
        case = self.boot("research_processing_unit")
        case.lua.execute('''
          local transport=require("research.native_adoption")
          local definitions=require("compatibility.modern_catalogue").native_owners(mods)
          local withheld={["processing-unit-productivity"]={family="research_processing_unit",generated=false}}
          local row={extended=true,definition={id="processing-unit-productivity"},
            admitted_recipes={"new-processing"},effect_change=.1,configured_effect=false}
          assert(not pcall(transport.plan,data.raw,{row},withheld))
          local owners={["processing-unit-productivity"]={recipes={"new-processing"},
            effect_change=.1,configured_change=false}}
          assert(not pcall(transport.read,{schema=1,owners=owners,withheld=withheld},definitions))
          assert(next(data.raw["mod-data"][transport.prototype_name].data.owners)==nil)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    unittest.main(argv=[sys.argv[0], *remaining])

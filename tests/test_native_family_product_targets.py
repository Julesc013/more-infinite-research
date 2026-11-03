"""Original five-owner recipe adoption controls; host only, no native claim."""
import argparse
from copy import deepcopy
from pathlib import Path
import sys
import unittest

from historical_sources import read_published_source
import test_generator as generator_fixture

ROOT = Path(__file__).resolve().parents[1]
OWNERS = {
    "research_low_density_structure": ("low-density-structure-productivity", ["low-density-structure", "casting-low-density-structure"]),
    "research_plastic": ("plastic-bar-productivity", ["plastic-bar", "bioplastic"]),
    "research_processing_unit": ("processing-unit-productivity", ["processing-unit"]),
    "research_rocket_fuel": ("rocket-fuel-productivity", ["rocket-fuel", "rocket-fuel-from-jelly", "ammonia-rocket-fuel"]),
    "research_steel": ("steel-plate-productivity", ["steel-plate", "casting-steel"]),
}
RECIPES = {
    "research_low_density_structure": "mir-fixture-adopt-low-density-structure",
    "research_plastic": "mir-fixture-adopt-plastic-bar",
    "research_processing_unit": "mir-fixture-adopt-processing-unit",
    "research_rocket_fuel": "mir-fixture-adopt-rocket-fuel",
    "research_steel": "mir-fixture-adopt-steel-plate",
}


def plain(value):
    if not hasattr(value, "items"):
        return value
    rows = dict(value.items())
    if rows and set(rows) == set(range(1, len(rows) + 1)):
        return [plain(rows[i]) for i in range(1, len(rows) + 1)]
    return {k: plain(v) for k, v in rows.items()}


class NativeFamilyProductTargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # These exact blobs are identical at the published 4.7.2/4.7.3 refs.
        cls.producer = read_published_source(ROOT,
            "fixtures/vanilla-family-adoption-recipes/data.lua",
            "22B80CE74F4940FC4BCE4CA77F36120D6557E15520424987297C343F1305B9A9").decode()
        oracle = read_published_source(ROOT,
            "fixtures/assert-vanilla-family-adoption/data-final-fixes.lua",
            "91EA8E7216095F4CF1905F859878392AEE0F2532F8FAA2779B572EC82FD72415").decode()
        # Keep every original player assertion, including denials and absent
        # duplicate MIR IDs. Retired schema4 report/signature metadata is not
        # the player contract and is not restored into MIR5.
        assert oracle.count("local adoption_data =") == 1
        cls.player_oracle = oracle.split("local adoption_data =", 1)[0]

    def setUp(self):
        self.boot()

    def boot(self):
        generator_fixture.LuaRuntime = LuaRuntime
        harness = generator_fixture.GeneratorTests()
        harness.setUp()
        self.lua = harness.lua
        self.lua.execute('''
          mods={base="2.1.23",["space-age"]="2.1.23"}
          package.loaded["research.settings"]=nil
          local config=require("research.settings");local startup={}
          for _,row in ipairs(config.prototypes()) do startup[row.name]={value=row.default_value} end
          settings,data,helpers,log={startup=startup},full_world(mods),nil,function() end
          function data:extend(rows)
            self.writes=self.writes+1;self.emitted=rows
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate publication")
              self.raw[row.type][row.name]=row
            end
          end
        ''')
        # Canonical native scaffold, independent of the candidate selector.
        # This supports host preflight; it is not an engine observation.
        for owner, recipes in OWNERS.values():
            self.lua.globals().data.raw.technology[owner] = generator_fixture.lua_table(self.lua, {
                "name": owner, "type": "technology", "max_level": "infinite",
                "effects": [{"type": "change-recipe-productivity", "recipe": recipe, "change": .1}
                            for recipe in recipes],
                "unit": {"count_formula": "1.5^L*1000", "time": 60},
            })
        self.lua.execute(self.producer)
        self.lua.execute('dofile(player_root.."/data.lua")')
        self.lua.execute("data.writes,data.emitted=0,nil")

    def pipeline(self):
        self.lua.execute("dofile(data_final_path)")

    def owner(self, family):
        return self.lua.globals().data.raw.technology[OWNERS[family][0]]

    def owner_rows(self):
        return {family: plain(self.owner(family)) for family in OWNERS}

    def changes(self, family, recipe=None):
        recipe = recipe or RECIPES[family]
        return [row["change"] for row in plain(self.owner(family).effects)
                if row.get("type") == "change-recipe-productivity" and row.get("recipe") == recipe]

    def test_full_pipeline_passes_all_original_player_assertions(self):
        before = {n: plain(self.lua.globals().data.raw.recipe[n]) for n in RECIPES.values()}
        self.pipeline()
        self.lua.execute(self.player_oracle)
        self.assertEqual(1, self.lua.globals().data.writes)
        for family in OWNERS:
            self.assertEqual([.1], self.changes(family))
        self.assertEqual(before, {n: plain(self.lua.globals().data.raw.recipe[n]) for n in RECIPES.values()})

    def test_nondefault_native_effects_extend_at_the_selected_value(self):
        for family in OWNERS:
            self.lua.globals().settings.startup["ips-effect-per-level-" + family].value = 20
        self.pipeline()
        for family, (_, recipes) in OWNERS.items():
            self.assertEqual([.2], self.changes(family))
            for recipe in recipes:
                self.assertEqual([.2], self.changes(family, recipe))

    def test_existing_foreign_effect_and_inherited_unit_are_preserved(self):
        owner = self.owner("research_steel")
        owner.unit.count_formula, owner.unit.time = "foreign-formula", 31
        owner.enabled = True
        self.lua.execute('''
          local owner=data.raw.technology["steel-plate-productivity"]
          owner.effects[#owner.effects+1]={type="character-crafting-speed",modifier=.33,foreign={keep=true}}
          owner.effects[#owner.effects+1]={type="unlock-recipe",recipe="mir-fixture-adopt-steel-plate"}
        ''')
        before = plain(owner)
        self.lua.globals().retained_effects = owner.effects
        self.pipeline()
        after = plain(owner)
        self.assertEqual(before["unit"], after["unit"])
        self.assertIs(True, after["enabled"])
        self.assertEqual(before["effects"], after["effects"][:-1])
        self.assertEqual([.1], self.changes("research_steel"))
        # Output arrays are detached from the retained input effect vector.
        self.assertEqual(before["effects"], plain(self.lua.globals().retained_effects))
        self.lua.execute('data.raw.technology["steel-plate-productivity"].effects[3].foreign.keep=false')
        self.assertEqual(before["effects"], plain(self.lua.globals().retained_effects))

    def test_existing_native_recipe_owner_is_tuned_once_in_the_declared_product_scope(self):
        self.lua.execute('''
          local effects=data.raw.technology["steel-plate-productivity"].effects
          effects[#effects+1]={type="change-recipe-productivity",recipe="mir-fixture-adopt-steel-plate",change=.33}
        ''')
        self.lua.globals().settings.startup["ips-effect-per-level-research_steel"].value = 20
        self.pipeline()
        self.assertEqual([.2], self.changes("research_steel"))

    def test_disabled_native_family_keeps_upstream_effects_without_new_adoption(self):
        before = plain(self.owner("research_steel"))
        self.lua.globals().settings.startup["ips-enable-research_steel"].value = False
        self.pipeline()
        self.assertEqual(before, plain(self.owner("research_steel")))
        self.assertEqual([], self.changes("research_steel"))
        self.assertEqual([.1], self.changes("research_plastic"))

    def test_missing_permission_and_bad_variants_do_not_gain_native_effects(self):
        for case in ("missing", "false", "zero-cap", "fluid", "hidden", "recycling", "productive-return", "bad-variant"):
            with self.subTest(case=case):
                self.boot()
                recipe = self.lua.globals().data.raw.recipe[RECIPES["research_steel"]]
                if case == "missing": recipe.allow_productivity = None
                if case == "false": recipe.allow_productivity = False
                if case == "zero-cap": recipe.maximum_productivity = 0
                if case == "fluid": recipe.results[1].type = "fluid"
                if case == "hidden": recipe.hidden = True
                if case == "recycling": recipe.categories = self.lua.table_from(["recycling"])
                if case == "productive-return": recipe.ingredients[1].name = "steel-plate"
                if case == "bad-variant":
                    payload = plain(recipe)
                    recipe.normal = generator_fixture.lua_table(self.lua, deepcopy(payload))
                    payload["allow_productivity"] = False
                    recipe.expensive = generator_fixture.lua_table(self.lua, payload)
                self.pipeline()
                self.assertEqual([], self.changes("research_steel"))

    def test_last_owner_preflight_and_generator_duplicate_fail_before_native_writes(self):
        for case in ("owner", "finite-owner", "disabled-owner", "duplicate"):
            with self.subTest(case=case):
                self.boot()
                if case == "owner": self.owner("research_steel").effects[1].change = .2
                elif case == "finite-owner": self.owner("research_steel").max_level = 3
                elif case == "disabled-owner": self.owner("research_steel").enabled = False
                else: self.lua.globals().data.raw.technology["recipe-prod-research_gears-1"] = self.lua.table()
                before = self.owner_rows()
                with self.assertRaises(LuaError) as raised:
                    self.pipeline()
                self.assertIn("duplicate technology" if case == "duplicate" else "native-owner preflight", str(raised.exception))
                self.assertEqual(0, self.lua.globals().data.writes)
                self.assertEqual(before, self.owner_rows())

    def test_known_native_overlap_uses_one_collector_and_existing_owner_precedence(self):
        self.lua.execute('''
          data.raw.recipe["multi-native"]={category="crafting",enabled=false,allow_productivity=true,
            ingredients={{type="item",name="iron-plate",amount=5}},
            results={{type="item",name="low-density-structure",amount=1},
              {type="item",name="steel-plate",amount=1},{type="item",name="copper-plate",amount=1}}}
          local collector=require("compatibility.product_targets");local real=collector.collect
          collector_calls=0
          collector.collect=function(...) collector_calls=collector_calls+1;return real(...) end
          setmetatable(data.raw.technology,{__pairs=function() error("foreign technology traversal") end})
        ''')
        self.pipeline()
        self.assertEqual(1, self.lua.globals().collector_calls)
        self.assertEqual([.1], self.changes("research_low_density_structure", "multi-native"))
        self.assertEqual([], self.changes("research_steel", "multi-native"))
        copper = plain(self.lua.globals().data.raw.technology["recipe-prod-research_copper-1"].effects)
        self.assertFalse(any(r.get("recipe") == "multi-native" for r in copper))

    def test_existing_native_owner_precedes_another_family_even_when_disabled(self):
        for enabled in (True, False):
            with self.subTest(steel_enabled=enabled):
                self.boot()
                self.lua.execute('''
                  data.raw.recipe["existing-native"]={category="crafting",enabled=false,allow_productivity=true,
                    ingredients={{type="item",name="iron-plate",amount=5}},
                    results={{type="item",name="low-density-structure",amount=1},
                      {type="item",name="steel-plate",amount=1}}}
                  local effects=data.raw.technology["steel-plate-productivity"].effects
                  effects[#effects+1]={type="change-recipe-productivity",recipe="existing-native",change=.1}
                ''')
                self.lua.globals().settings.startup["ips-enable-research_steel"].value = enabled
                self.pipeline()
                self.assertEqual([.1], self.changes("research_steel", "existing-native"))
                self.assertEqual([], self.changes("research_low_density_structure", "existing-native"))

    def test_new_native_claim_never_removes_an_existing_generated_effect(self):
        self.lua.execute('''
          local extend=require("research.product_target_extension").extend
          local owner=data.raw.technology["steel-plate-productivity"]
          native_row={family="research_steel",owner=owner,effects={},active=true}
          generated={name="recipe-prod-research_copper-1",effects={
            {type="change-recipe-productivity",recipe="mir-fixture-adopt-steel-plate",change=.31}}}
          extend_overlap=function()
            extend({generated},{streams={research_steel={effect_percent=10},research_copper={effect_percent=10}}},
              {raw=data.raw,mods=mods,native_owner_targets={native_row}})
          end
        ''')
        before = self.owner_rows()
        with self.assertRaisesRegex(LuaError, "native-owner target overlaps an existing MIR effect"):
            self.lua.globals().extend_overlap()
        self.assertEqual(before, self.owner_rows())
        self.assertEqual(.31, self.lua.globals().generated.effects[1].change)
        self.assertEqual(0, len(self.lua.globals().native_row.effects))
        self.assertEqual(0, self.lua.globals().data.writes)

    def test_default_adoption_inherits_the_uniform_upstream_effect(self):
        for family in OWNERS:
            for effect in self.owner(family).effects.values():
                effect.change = .23
        self.pipeline()
        for family in OWNERS:
            self.assertEqual([.23], self.changes(family))
            for recipe in OWNERS[family][1]:
                self.assertEqual([.23], self.changes(family, recipe))

    def test_inactive_space_age_does_not_import_native_target_bindings(self):
        self.lua.execute('''
          package.loaded["compatibility.product_bindings"]=nil
          package.preload["compatibility.product_bindings"]=function() error("inactive native bindings imported") end
          local poison=setmetatable({}, {__index=function() error("inactive native fields read") end})
          assert(#modern.native_owner_product_targets(poison,poison,poison,poison,{})==0)
        ''')

    def test_explicit_generated_family_keeps_its_authored_owner(self):
        self.lua.execute('''
          local selection=require("compatibility.modern_catalogue").select(mods,data.raw)
          selection.definitions[#selection.definitions+1]={family="research_steel"}
          local values=require("research.settings").resolve(settings.startup,helpers,log)
          local targets=modern.native_owner_product_targets(selection,data.raw,values,{},mods)
          assert(#targets==4)
          for _,row in ipairs(targets) do assert(row.family~="research_steel") end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeFamilyProductTargetTests))
    sys.exit(0 if result.wasSuccessful() else 1)

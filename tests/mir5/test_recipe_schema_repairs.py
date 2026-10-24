"""Exact-version repair boundaries; host controls do not qualify upstream mods."""
import argparse
from pathlib import Path
import sys
import unittest

from native_credit_oracle import verified_public_rows

ROOT = Path(__file__).resolve().parents[2]


class RecipeSchemaRepairTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          repair = require("overrides.recipe_schema")
        ''')

    def test_inactive_unknown_versions_and_other_engines_never_read_prototypes(self):
        self.lua.execute('''
          local raw = setmetatable({}, {__index=function() error("inactive prototype read") end})
          for _, mods in ipairs({{}, {base="2.1.23"}, {base="2.0.77",["atan-ash"]="2.2.1"},
              {base="3.0.0",["atan-ash"]="2.2.1"}, {base="2.1.23",["atan-ash"]="2.2.2"},
              {base="2.1.23",["atan-nuclear-science"]="0.3.4"}}) do
            assert(repair.apply(raw, mods, function() error("inactive report") end) == 0)
          end
        ''')

    def test_all_five_ash_categories_preserve_order_and_only_named_fields_change(self):
        self.lua.execute('''
          local names = {"atan-ash-seperation", "atan-foundation-from-ash", "atan-landfill-from-ash",
            "atan-nutrients-from-ash", "atan-stone-brick-from-ash"}
          local recipes = setmetatable({}, {__pairs=function() error("global recipe scan") end})
          for _, name in ipairs(names) do recipes[name] = {
            categories={"first","second"},category="second",additional_categories={"third","first","fourth"},
            foreign={marker=17},ingredients={{"ore",1}},results={{name="ash",amount=1}}
          } end
          local untouched = {category="foreign",additional_categories={"extra"},results={{probability=.5}}}
          recipes["foreign-ash-process"] = untouched
          local messages = {}
          local count = repair.apply({recipe=recipes}, {base="2.1.23",["atan-ash"]="2.2.1"},
            function(message) messages[#messages+1]=message end)
          assert(count == 5 and #messages == 1 and messages[1]:find("atan%-ash 2%.2%.1"))
          for _, name in ipairs(names) do
            local recipe = recipes[name]
            assert(table.concat(recipe.categories,",") == "first,second,third,fourth")
            assert(recipe.category == nil and recipe.additional_categories == nil)
            assert(recipe.foreign.marker == 17 and recipe.ingredients[1][1] == "ore")
          end
          assert(untouched.category == "foreign" and untouched.additional_categories[1] == "extra"
            and untouched.results[1].probability == .5)
          assert(repair.apply({recipe=recipes},{base="2.1.23",["atan-ash"]="2.2.1"}) == 0)
        ''')

    def test_probability_zero_existing_independent_roll_and_variants_are_preserved(self):
        self.lua.execute('''
          local recipe = {categories={"chemistry"},results={
            {name="a",amount=1,probability=0},
            {name="b",amount=2,probability=.75,independent_probability=0,foreign=9},
            {name="c",amount=3,shared_probability={min=.1,max=.3}}},
            normal={results={{name="a",amount=1,probability=.25}}},
            expensive={results={{name="b",amount=2,probability=1}}}}
          local original_categories, shared = recipe.categories,recipe.results[3].shared_probability
          local raw = {recipe={["atan-ash-seperation"]=recipe}}
          assert(repair.apply(raw,{base="2.1.23",["atan-ash"]="2.2.1"}) == 1)
          assert(recipe.categories == original_categories and recipe.results[1].independent_probability == 0)
          assert(recipe.results[2].independent_probability == 0 and recipe.results[2].foreign == 9)
          assert(recipe.results[1].probability == nil and recipe.results[2].probability == nil)
          assert(recipe.results[3].shared_probability == shared and recipe.results[3].independent_probability == nil)
          assert(recipe.normal.results[1].independent_probability == .25 and recipe.expensive.results[1].independent_probability == 1)
        ''')

    def test_nuclear_repair_does_not_convert_unapproved_products_or_touch_other_recipes(self):
        self.lua.execute('''
          local named = {category="crafting",results={{name="bomb",amount=1,probability=.2}}}
          local foreign = {category="crafting",additional_categories={"chemistry"}}
          local raw = {recipe={["atomic-bomb"]=named,["unknown-nuclear-process"]=foreign}}
          assert(repair.apply(raw,{base="2.1.23",["atan-nuclear-science"]="0.3.3"}) == 1)
          assert(named.categories[1] == "crafting" and named.category == nil)
          assert(named.results[1].probability == .2 and named.results[1].independent_probability == nil)
          assert(foreign.category == "crafting" and foreign.categories == nil)
        ''')

    def test_missing_optional_recipes_and_empty_legacy_categories_are_untouched(self):
        self.lua.execute('''
          local empty = {category="",additional_categories={false,17}}
          assert(repair.apply({recipe={["atan-landfill-from-ash"]=empty}},
            {base="2.1.23",["atan-ash"]="2.2.1"}) == 0)
          assert(empty.category == "" and empty.additional_categories[1] == false)
          assert(repair.apply({}, {base="2.1.23",["atan-ash"]="2.2.1",["atan-nuclear-science"]="0.3.3"}) == 0)
        ''')

    def test_real_data_entry_loads_the_body_only_for_the_two_admitted_versions(self):
        import test_generator
        test_generator.LuaRuntime = LuaRuntime
        for selected in (False, True):
            with self.subTest(selected=selected):
                host = test_generator.GeneratorTests("runTest")
                host.setUp()
                host.lua.globals().selected = selected
                host.lua.execute('''
                  local environment = full_world({})
                  local recipe = {category="old",additional_categories={"other"},results={{name="ash",amount=1,probability=.25}}}
                  environment.raw.recipe["atan-ash-seperation"] = recipe
                  settings,mods,data,helpers,log={startup=defaults()},{base="2.1.23"},environment,nil,function() end
                  if selected then mods["atan-ash"]="2.2.1" else mods["atan-ash"]="2.2.2" end
                  assert(dofile(data_final_path) == nil and environment.writes == 1 and #environment.emitted == 73)
                  schema_output, schema_recipes = environment.emitted, environment.raw.recipe
                  if selected then
                    assert(package.loaded["overrides.recipe_schema"] and recipe.category == nil)
                    assert(recipe.results[1].independent_probability == .25 and recipe.results[1].probability == nil)
                  else
                    assert(package.loaded["overrides.recipe_schema"] == nil and recipe.category == "old")
                    assert(recipe.results[1].probability == .25 and recipe.results[1].independent_probability == nil)
                  end
                ''')
                actual = {
                    row["name"]: test_generator.plain_lua(row)
                    for row in host.lua.globals().schema_output.values()
                }
                public = verified_public_rows(
                    actual,
                    {str(name) for name in host.lua.globals().schema_recipes.keys()},
                )
                self.assertEqual(len(public), 53)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RecipeSchemaRepairTests))
    sys.exit(0 if result.wasSuccessful() else 1)

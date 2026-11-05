"""RIC's one authored Marine route: independent historical oracle, host only."""
import argparse
import json
from pathlib import Path
import sys
import unittest

from historical_sources import read_published_source
import test_generator as scaffold

ROOT = Path(__file__).resolve().parents[1]
FAMILY = "research_material_ric_coke"
NAME = "recipe-prod-" + FAMILY + "-1"
RECIPE = "ric-carbonise-marine-biomass"
SOURCE_VERSION = json.loads((ROOT / "source/info.json").read_bytes())["version"]
EDITIONS = json.loads((ROOT / "targets/editions.json").read_bytes())["targets"]


def recipe_input():
    # Independent facts in the actual0.35.8 archive and original0.36.1 oracle.
    return {"type": "recipe", "name": RECIPE, "categories": ["ric-coking"],
            "enabled": False, "allow_productivity": True, "energy_required": 5,
            "ingredients": [{"type": "item", "name": "ric-dried-marine-biomass", "amount": 6}],
            "results": [{"type": "item", "name": "ric-coke", "amount": 3},
                        {"type": "item", "name": "ric-ash", "amount": 1}]}


class RicMarineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        original = read_published_source(ROOT,
            "fixtures/assert-ric-marine-carbonisation/data-final-fixes.lua",
            "E07E54579732539B6A133724C6AA7105F6F1AB445002AB71AAAFC3546359F60B").decode()
        # Port only the retired mod-data policy-schema boundary. Keep the old
        # recipe, identity, effect, unique-owner, withheld-route and unlock checks.
        first, last = original.index("local transport ="), original.index("local function amount(")
        cls.original_oracle = original[:first] + original[last:]

    def stage(self, mode="marine", provider=True, target="f210", changes=None):
        scaffold.LuaRuntime = LuaRuntime
        harness = scaffold.GeneratorTests()
        harness.setUp()
        lua = harness.lua
        lua.globals().selected_mode = mode
        lua.globals().selected_provider = provider
        major, minor, encoded = SOURCE_VERSION.split(".")
        lua.globals().selected_target = scaffold.lua_table(lua, {
            **EDITIONS[target], "id": target,
            "distribution_version": f"{major}.{minor}.{int(target[1:])*100+int(encoded)%100:05d}"})
        lua.globals().selected_changes = scaffold.lua_table(lua, changes or {})
        lua.globals().ric_recipe = scaffold.lua_table(lua, recipe_input())
        lua.execute('''
          local target=require("platform.target")
          for key,value in pairs(selected_target) do target[key]=value end
          mods={base=target.minimum_base,["space-age"]=target.minimum_base}
          if selected_provider then mods["real-industrial-chemistry"]="0.35.8" end
          package.loaded["research.settings"]=nil
          config=require("research.settings")
          settings={startup={}}
          for _,spec in ipairs(config.prototypes()) do settings.startup[spec.name]={value=spec.default_value} end
          for name,value in pairs(selected_changes) do settings.startup[name].value=value end
          settings.startup["ric-world-mode"]={value=selected_mode}
          settings.startup["ric-progression-mode"]={value="space-age"}
          data=full_world(mods,true)
          for _,id in ipairs({"ric-dried-marine-biomass","ric-coke","ric-ash"}) do
            data.raw.item[id]={type="item",name=id,
              icon="__real-industrial-chemistry__/graphics/vendor/permissive/bzfoundry2/graphics/icons/coke.png",icon_size=128}
          end
          if selected_mode=="marine" then data.raw.recipe[ric_recipe.name]=ric_recipe end
          data.raw.technology["automation"]=data.raw.technology["automation"] or {name="automation"}
          data.raw.technology["ric-ore-processing-1"]={type="technology",name="ric-ore-processing-1",
            prerequisites={"automation"},unit={count=30,time=15,ingredients={{"automation-science-pack",1}}}}
          data.raw.technology["ric-coking"]={type="technology",name="ric-coking",
            prerequisites={"ric-ore-processing-1"},unit={count=35,time=15,ingredients={{"automation-science-pack",1}}},
            effects={{type="unlock-recipe",recipe="ric-carbonise-marine-biomass"}}}
          log=function(_) end
          helpers=nil
          function data:extend(rows)
            self.writes=self.writes+1;self.emitted=rows
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate publication")
              self.raw[row.type][row.name]=row
            end
          end
          dofile(player_root.."/data.lua")
          data.writes=0
        ''')
        return lua

    def pipeline(self, lua):
        lua.execute("dofile(data_final_path)")

    def test_original_marine_oracle_and_literal_defaults(self):
        lua = self.stage()
        before = scaffold.plain_lua(lua.globals().data.raw.recipe[RECIPE])
        self.pipeline(lua)
        lua.execute(self.original_oracle)
        row = scaffold.plain_lua(lua.globals().data.raw.technology[NAME])
        self.assertEqual("infinite", row["max_level"])
        self.assertEqual(["ric-coking"], row["prerequisites"])
        self.assertEqual([["automation-science-pack", 1]], row["unit"]["ingredients"])
        self.assertEqual({"count_formula": "200*2^(L-1)", "time": 30,
                          "ingredients": [["automation-science-pack", 1]]}, row["unit"])
        self.assertEqual([{"type": "change-recipe-productivity", "recipe": RECIPE, "change": .02}], row["effects"])
        self.assertEqual(before, scaffold.plain_lua(lua.globals().data.raw.recipe[RECIPE]))
        self.assertEqual(1, lua.globals().data.writes)
        lua.execute('''data.raw.technology["recipe-prod-research_material_ric_coke-1"].unit.ingredients[1][1]="caller-mutated"
          assert(data.raw.technology["ric-coking"].unit.ingredients[1][1]=="automation-science-pack")
        ''')
        lua.execute('data.raw.technology["'+NAME+'"].effects[1].change=.01')
        with self.assertRaisesRegex(LuaError, r"exact carbonisation route at \+2%"):
            lua.execute(self.original_oracle)

    def test_tuning_and_disabled_identity(self):
        lua = self.stage(changes={"ips-cost-base-"+FAMILY: 300,
            "ips-cost-linear-increment-"+FAMILY: 25, "ips-cost-growth-"+FAMILY: 3,
            "ips-research-time-"+FAMILY: 17, "ips-effect-per-level-"+FAMILY: 5,
            "ips-max-level-"+FAMILY: 7, "ips-enable-"+FAMILY: False})
        self.pipeline(lua)
        row = lua.globals().data.raw.technology[NAME]
        self.assertFalse(row.enabled)
        self.assertEqual("infinite", row.max_level)
        self.assertEqual("(300+25*(L-1))*3^(L-1)", row.unit.count_formula)
        self.assertEqual(17, row.unit.time)
        self.assertAlmostEqual(.05, row.effects[1].change)
        lua.execute('''local values=config.resolve(settings.startup)
          assert(values.streams.research_material_ric_coke.max_level==7)
          local found=0
          for _,spec in ipairs(config.prototypes()) do
            if spec.name:find("research_material_ric_coke",1,true) then
              assert(spec.hidden~=true);found=found+1
            end
          end
          assert(found==7)
        ''')

    def test_imported_false_zero_cap_and_percentage_override_raw_values(self):
        lua = self.stage()
        lua.execute('''
          local imported={schema=1,settings={
            ["ips-enable-research_material_ric_coke"]=false,
            ["ips-max-level-research_material_ric_coke"]=0,
            ["ips-effect-per-level-research_material_ric_coke"]=4.5,
            ["ips-research-time-research_material_ric_coke"]=0}}
          -- Existing host codec boundary: actual compression/JSON helpers and
          -- rendered import controls retain their separate native checks.
          helpers={encode_string=function(text) return text end,
            decode_string=function(text) return text end,
            json_to_table=function(text) return imported end}
          local wire,err=require("research.settings_profile").encode(imported,helpers)
          assert(wire and not err)
          settings.startup[config.import_setting_name].value=wire
          assert(settings.startup["ips-enable-research_material_ric_coke"].value==true)
        ''')
        self.pipeline(lua)
        row = lua.globals().data.raw.technology[NAME]
        self.assertFalse(row.enabled)
        self.assertAlmostEqual(.045, row.effects[1].change)
        self.assertEqual(30, row.unit.time)
        lua.execute('''local values=config.resolve(settings.startup,helpers)
          assert(values.streams.research_material_ric_coke.max_level==0)
          assert(settings.startup["ips-max-level-research_material_ric_coke"].value==3)
        ''')

    def test_continental_original_absence_and_inactive_module_boundaries(self):
        lua = self.stage(mode="continental")
        self.pipeline(lua)
        lua.execute(self.original_oracle)
        self.assertIsNone(lua.globals().data.raw.technology[NAME])
        lua.execute('assert(package.loaded["integrations.ric.research"]==nil)')
        for provider,target in ((False,"f210"),(True,"f200")):
            lua = self.stage(provider=provider,target=target)
            self.pipeline(lua)
            self.assertIsNone(lua.globals().data.raw.technology[NAME])
            lua.execute('assert(package.loaded["integrations.ric.research"]==nil)')

    def test_same_typed_scaled_quantities_are_not_mutated(self):
        lua = self.stage()
        lua.execute('''local recipe=data.raw.recipe["ric-carbonise-marine-biomass"]
          recipe.ingredients[1].amount=12
          recipe.results[1].amount,recipe.results[2].amount=6,2
        ''')
        expected = scaffold.plain_lua(lua.globals().data.raw.recipe[RECIPE])
        self.pipeline(lua)
        self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.recipe[RECIPE]))
        self.assertAlmostEqual(.02, lua.globals().data.raw.technology[NAME].effects[1].change)

    def test_upstream_icon_representation_is_not_a_gameplay_gate(self):
        lua = self.stage()
        lua.execute('''local item=data.raw.item["ric-coke"]
          item.icons={{icon=item.icon,icon_size=128}};item.icon=nil
        ''')
        before = scaffold.plain_lua(lua.globals().data.raw.item["ric-coke"])
        self.pipeline(lua)
        lua.execute(self.original_oracle)
        row = lua.globals().data.raw.technology[NAME]
        self.assertEqual(1, len(row.icons))
        self.assertEqual("__core__/graphics/icons/technology/constants/constant-recipe-productivity.png", row.icons[1].icon)
        self.assertEqual(before, scaffold.plain_lua(lua.globals().data.raw.item["ric-coke"]))

    def test_unsupported_inputs_and_foreign_productivity_refuse_before_publication(self):
        changes = [
            'data.raw.recipe["'+RECIPE+'"].allow_productivity=false',
            'data.raw.recipe["'+RECIPE+'"].ingredients[1].name="ric-coke"',
            'data.raw.recipe["'+RECIPE+'"].results[1].amount=0',
            'data.raw.recipe["'+RECIPE+'"].results[1].probability=.5',
            'data.raw.recipe["'+RECIPE+'"].results[1].ignored_by_productivity=1',
            'data.raw.recipe["'+RECIPE+'"].results[2]=nil',
            'data.raw.technology["ric-coking"].effects={}',
            'data.raw.technology["ric-coking"].unit.ingredients[1][1]="future-science-pack"',
            'data.raw.item["ric-coke"]=nil',
            'data.raw.technology.foreign={effects={{type="change-recipe-productivity",recipe="'+RECIPE+'",change=.1}}}',
        ]
        for change in changes:
            with self.subTest(change=change):
                lua = self.stage()
                lua.execute(change)
                before = scaffold.plain_lua(lua.globals().data.raw.recipe[RECIPE])
                with self.assertRaisesRegex(LuaError, "MIR RIC Marine"):
                    self.pipeline(lua)
                self.assertEqual(0, lua.globals().data.writes)
                self.assertEqual(before, scaffold.plain_lua(lua.globals().data.raw.recipe[RECIPE]))

    def test_existing_identity_keeps_generator_duplicate_protection(self):
        lua = self.stage()
        lua.execute('data.raw.technology["'+NAME+'"]={name="'+NAME+'",effects={}}')
        with self.assertRaisesRegex(LuaError, "duplicate technology "+NAME):
            self.pipeline(lua)
        self.assertEqual(0, lua.globals().data.writes)

    def test_runtime_cap_keeps_paid_levels_partial_and_foreign_work(self):
        lua = self.stage()
        self.pipeline(lua)
        lua.execute('''
          local id="recipe-prod-research_material_ric_coke-1"
          local prototype=data.raw.technology[id]
          assert(prototype,"missing restored RIC identity")
          prototype.max_level=4294967295
          local tech={name=id,valid=true,level=4,researched=false,enabled=true,
            saved_progress=.27,visible_when_disabled=false,prototype=prototype}
          local foreign={name="foreign-current",valid=true,level=2,enabled=true}
          local force={index=1,valid=true,technologies={[id]=tech,[foreign.name]=foreign},
            research_queue={foreign,tech},current_research=foreign,research_progress=.42}
          tech.force,foreign.force=force,force
          script={active_mods=mods}
          prototypes={technology={[id]=prototype},recipe={},get_history=function()
            return {created="more-infinite-research"}
          end}
          game,storage={forces={[1]=force}},{}
          for _,name in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
            package.loaded[name]=nil
          end
          local lifecycle=require("runtime.lifecycle")
          assert(lifecycle.cap_limits(force)[id]==3)
          lifecycle.on_init()
          assert(not tech.enabled and tech.level==4 and tech.saved_progress==.27 and not tech.researched)
          assert(storage.mir_caps.owned_disabled[1][id].disabled)
          assert(#force.research_queue==1 and force.research_queue[1]==foreign)
          assert(force.current_research==foreign and force.research_progress==.42)
          settings.startup["ips-max-level-research_material_ric_coke"].value=0
          package.loaded["runtime.configuration"],package.loaded["runtime.lifecycle"]=nil,nil
          require("runtime.lifecycle").on_configuration_changed({})
          assert(tech.enabled and tech.level==4 and tech.saved_progress==.27)
          assert(force.current_research==foreign and force.research_progress==.42)
        ''')

    def test_foreign_disabled_state_never_gains_a_restoration_right(self):
        lua = self.stage()
        self.pipeline(lua)
        lua.execute('''
          local id="recipe-prod-research_material_ric_coke-1"
          local prototype=data.raw.technology[id];prototype.max_level=4294967295
          local tech={name=id,valid=true,level=4,researched=false,enabled=false,
            saved_progress=.27,visible_when_disabled=false,prototype=prototype}
          local force={index=1,valid=true,technologies={[id]=tech},research_queue={}}
          tech.force=force
          script={active_mods=mods}
          prototypes={technology={[id]=prototype},recipe={},get_history=function()
            return {created="more-infinite-research"}
          end}
          game,storage={forces={[1]=force}},{}
          for _,name in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
            package.loaded[name]=nil
          end
          require("runtime.lifecycle").on_init()
          local rights=storage.mir_caps and storage.mir_caps.owned_disabled[1]
          -- A literal false marker records denial; it is not an enablement right.
          assert(not rights or not rights[id] or rights[id].disabled==false)
          settings.startup["ips-max-level-research_material_ric_coke"].value=0
          package.loaded["runtime.configuration"],package.loaded["runtime.lifecycle"]=nil,nil
          require("runtime.lifecycle").on_configuration_changed({})
          assert(not tech.enabled and tech.level==4 and tech.saved_progress==.27)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RicMarineTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Collected carrier construction only; host controls, never save evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

import test_native_credit_definitions as fixed_fixture


class NativeFamilyCreditDefinitionTests(unittest.TestCase):
    def test_published_m4_base_masks_match_independent_captures_and_are_detached(self):
        root = Path(__file__).resolve().parents[1]
        expected = {}
        for edition in ("f200", "f210"):
            inventory = json.loads((root / "spec/inventory" / ("modern-" + edition + "-470.json")).read_bytes())
            profile = next(p for p in inventory["profiles"] if p["id"] == "base-" + edition)
            additions = profile["published_output"]["data"]["additions"]
            for family in ("low_density_structure", "plastic", "processing_unit", "rocket_fuel", "steel"):
                row = next(r["row"] for r in additions if r["type"] == "technology"
                           and r["name"] == "recipe-prod-research_" + family + "-1")
                self.assertEqual(len(row["effects"]), 1)
                effect = row["effects"][0]
                self.assertEqual(effect["type"], "change-recipe-productivity")
                key = "research_" + family
                if key in expected:
                    self.assertEqual(expected[key], effect["recipe"])
                expected[key] = effect["recipe"]
        self.lua.globals().old_base_recipes = self.lua.table_from(expected)
        self.lua.execute('''
          local contracts=require("research.native_credit_contracts")
          for _,version in ipairs({"4.7.20003","4.7.21003"}) do
            local mask=assert(contracts.published_m4_base_paid_recipe_sets(version))
            local count=0
            for family,recipes in pairs(mask) do
              local recipe=assert(old_base_recipes[family])
              assert(recipes[recipe]==true and next(recipes,recipe)==nil);count=count+1
            end
            assert(count==5)
            mask.research_plastic["plastic-bar"]=false;mask.fake={unearned=true}
            local again=contracts.published_m4_base_paid_recipe_sets(version)
            assert(again.research_plastic["plastic-bar"] and again.fake==nil)
          end
          for _,version in ipairs({"4.7.20002","4.7.21004","5.0.21003",false,{}}) do
            assert(contracts.published_m4_base_paid_recipe_sets(version)==nil)
          end
          assert(contracts.published_m4_base_paid_recipe_sets(nil)==nil)
        ''')

    def test_data_only_base_masks_are_exact_original_contracts_and_detached(self):
        root = Path(__file__).resolve().parents[1]
        self.lua.globals().original_fixture_root = (root / "tests/fixtures/migration-origins").as_posix()
        self.lua.execute(r'''
          local contracts=require("research.native_credit_contracts")
          local expected={research_low_density_structure="low-density-structure",research_plastic="plastic-bar",
            research_processing_unit="processing-unit",research_rocket_fuel="rocket-fuel"}
          for _,case in ipairs({{"1.1.0","110"},{"1.2.0","120"}}) do
            local old=assert(loadfile(original_fixture_root.."/f200-"..case[2].."-source/catalogue.lua"))()
            local mask=contracts.published_data_only_base_paid_recipe_sets(case[1])
            local count=0
            for family,recipe in pairs(expected) do
              local effects=assert(old.rows["recipe-prod-"..family.."-1"]).effects
              assert(#effects==1 and effects[1].recipe==recipe and effects[1].change==.1)
              assert(mask[family][recipe]==true and next(mask[family],recipe)==nil)
              count=count+1
            end
            local actual=0;for family in pairs(mask) do assert(expected[family]);actual=actual+1 end
            assert(count==4 and actual==4 and mask.research_steel==nil
              and old.rows["recipe-prod-research_steel-1"]==nil)
            mask.research_plastic["plastic-bar"]=false;mask.research_steel={fake=true}
            local again=contracts.published_data_only_base_paid_recipe_sets(case[1])
            assert(again.research_plastic["plastic-bar"] and again.research_steel==nil)
          end
          for _,version in ipairs({"1.0.1","1.1.1","1.2.5","1.2.9","4.7.20003","5.0.20006"}) do
            assert(contracts.published_data_only_base_paid_recipe_sets(version)==nil)
          end
        ''')

    def test_original_100_conditional_mask_does_not_claim_a_complete_source_roster(self):
        # Numeric tag1.0.0 config/util/tech-gen, also verified against public
        # ZIP C328D8F9: each of these nongroup streams targets one Base item at
        # .10. Conflict trimming can retain its recipe or suppress the identity.
        self.lua.execute(r'''
          local contracts=require("research.native_credit_contracts")
          local expected={research_low_density_structure="low-density-structure",research_plastic="plastic-bar",
            research_processing_unit="processing-unit",research_rocket_fuel="rocket-fuel"}
          local mask=assert(contracts.published_data_only_base_paid_recipe_sets("1.0.0"))
          local count=0
          for family,recipes in pairs(mask) do
            assert(expected[family] and recipes[expected[family]]==true)
            local n=0;for recipe in pairs(recipes) do assert(recipe==expected[family]);n=n+1 end
            assert(n==1);count=count+1
          end
          assert(count==4 and mask.research_steel==nil)
          mask.research_plastic["plastic-bar"]=false
          assert(contracts.published_data_only_base_paid_recipe_sets("1.0.0").research_plastic["plastic-bar"])
        ''')

    def test_settings_stage_never_imports_credit_construction_or_recipe_collection(self):
        root = Path(__file__).resolve().parents[1]
        editions = json.loads((root / "targets/editions.json").read_bytes())["targets"]
        for edition, version, sif in (("f200", "2.0.77", True), ("f210", "2.1.23", False)):
            with self.subTest(edition=edition):
                lua = LuaRuntime(unpack_returned_tuples=True)
                lua.globals().player_root = (root / "source").as_posix()
                lua.globals().selected_target = lua.table_from({
                    **{key: value for key, value in editions[edition].items()
                       if isinstance(value, (str, int, bool))}, "id": edition})
                mods = {"base": version, "space-age": version}
                if sif: mods.update({"space-is-fake": "1.0.60", "cr-commons": "1.0.27"})
                lua.globals().mods = lua.table_from(mods)
                lua.execute('''
                  package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
                  package.loaded["platform.target"]=selected_target
                  package.preload["research.native_credit_definitions"]=function() error("settings imported carrier construction") end
                  package.preload["compatibility.product_bindings"]=function() error("settings imported recipe collection") end
                  package.preload["research.generator"]=function() error("settings imported Generator") end
                  local seen={}
                  data={extend=function(_,rows)
                    assert(#rows>0)
                    for _,row in ipairs(rows) do assert(row.type:match("%-setting$") and not seen[row.name]);seen[row.name]=true end
                  end}
                  dofile(player_root.."/settings.lua")
                  assert(seen["ips-max-level-research_steel"] and seen["ips-research-time-research_steel"])
                ''')

    def setUp(self):
        fixed_fixture.LuaRuntime = LuaRuntime
        harness = fixed_fixture.NativeCreditDefinitionTests()
        harness.setUp()
        self.lua = harness.lua
        self.lua.execute(r'''
          families={"research_low_density_structure","research_plastic","research_processing_unit",
            "research_rocket_fuel","research_steel"}
          function groups_for_all()
            local groups={}
            for index,family in ipairs(families) do
              groups[family]={{recipe="shared-route",change=index/100}}
            end
            return groups
          end
          function collected_inputs()
            local technologies={{type="technology",name="foreign-unrelated-row",
              effects={{type="change-recipe-productivity",recipe="foreign",change=.77}}}}
            for _,family in ipairs(families) do
              technologies[#technologies+1]={type="technology",name="recipe-prod-"..family.."-1",
                effects={{type="change-recipe-productivity",recipe="shared-route",change=.5}}}
            end
            local recipes={['shared-route']={type="recipe",name="shared-route",foreign_field="preserve"}}
            local raw={recipe=setmetatable(recipes,{__pairs=function() error("enumerated recipe world") end}),
              technology=setmetatable({},{__index=function() error("read raw technology world") end,
                __pairs=function() error("enumerated raw technology world") end})}
            return technologies,raw
          end
          function refuse(body)
            local ok,message=pcall(body)
            assert(not ok,"required rejection absent")
            assert(tostring(message):find("MIR native credit",1,true),message)
          end
          function same(a,b)
            if type(a)~=type(b) then return false end
            if type(a)~="table" then return a==b end
            for key,value in pairs(a) do if not same(value,b[key]) then return false end end
            for key in pairs(b) do if a[key]==nil then return false end end
            return true
          end
        ''')

    def test_canonical_namespaces_family_order_recipe_order_and_detached_rows(self):
        self.lua.execute(r'''
          local groups=groups_for_all()
          groups.research_steel={{recipe="z-steel",change=.3},{recipe="a-steel",change=.2}}
          groups.research_low_density_structure={{recipe="z-lds",change=.7},{recipe="shared-route",change=.01}}
          local rows=credit.collected_descriptors(groups)
          local expected_families={families[1],families[1],families[2],families[3],families[4],families[5],families[5]}
          local expected_recipes={"shared-route","z-lds","shared-route","shared-route","shared-route","a-steel","z-steel"}
          assert(#rows==7)
          local seen={}
          for index,row in ipairs(rows) do
            local family,recipe=expected_families[index],expected_recipes[index]
            assert(row.family==family and row.recipe==recipe and row.main_id=="recipe-prod-"..family.."-1")
            assert(row.key==family..string.char(0)..recipe and row.collected==true)
            assert(row.positive_id=="mir-native-credit-"..family.."-"..recipe.."-positive")
            assert(row.negative_id=="mir-native-credit-"..family.."-"..recipe.."-negative")
            assert(not seen[row.key] and not seen[row.positive_id] and not seen[row.negative_id])
            seen[row.key],seen[row.positive_id],seen[row.negative_id]=true,true,true
          end
          assert(rows[1].change==.01 and rows[2].change==.7 and rows[6].change==.2 and rows[7].change==.3)
          local repeat_rows=credit.collected_descriptors(groups)
          assert(same(rows,repeat_rows))
          rows[1].recipe,rows[1].change,rows[1].key="tampered",99,"foreign"
          assert(groups.research_low_density_structure[2].recipe=="shared-route"
            and groups.research_low_density_structure[2].change==.01)
          assert(credit.collected_descriptors(groups)[1].recipe=="shared-route")
          groups.research_low_density_structure[2].change=.9
          assert(repeat_rows[1].change==.01,"input mutation changed previously returned descriptor")
        ''')

    def test_exact_native_carrier_shape_and_declared_scalar_without_settings_or_globals(self):
        self.lua.execute(r'''
          local technologies,raw=collected_inputs()
          local groups=groups_for_all();groups.research_low_density_structure[1].change=.0001
          local poison=setmetatable({},{__index=function() error("constructor read settings or globals") end})
          data,settings,mods,game,prototypes=poison,poison,poison,poison,poison
          local before=#technologies
          local added=credit.append(technologies,raw,poison,{recipe_productivity=true},groups)
          assert(#added==10 and #technologies==before+10)
          for index,family in ipairs(families) do
            local change=groups[family][1].change
            for offset,direction in ipairs({"positive","negative"}) do
              local id="mir-native-credit-"..family.."-shared-route-"..direction
              local expected={type="technology",name=id,icon="__base__/graphics/technology/automation-1.png",
                icon_size=256,level=1,upgrade=true,hidden=true,enabled=false,visible_when_disabled=false,
                max_level="infinite",order="zz[mir-native-credit]-"..id,
                effects={{type="change-recipe-productivity",recipe="shared-route",
                  change=direction=="positive" and change or -change}},
                unit={count=1,time=1,ingredients={{"automation-science-pack",1}}}}
              assert(same(added[(index-1)*2+offset],expected),"native carrier contract differs")
            end
          end
          added[1].effects[1].change,added[1].unit.ingredients[1][1]=99,"foreign-science"
          assert(added[2].effects[1].change==-.0001 and added[2].unit.ingredients[1][1]=="automation-science-pack")
          assert(technologies[1].effects[1].change==.77 and technologies[2].effects[1].change==.5)
          assert(raw.recipe['shared-route'].foreign_field=="preserve" and groups[families[1]][1].change==.0001)
        ''')

    def test_fixed_thirteen_descriptor_and_carrier_outputs_stay_exact_with_no_groups(self):
        self.lua.execute(r'''
          local baseline=credit.descriptors()
          assert(#baseline==13 and #credit.descriptors({})==13)
          for index,wanted in ipairs(expected) do
            local row=baseline[index]
            local keys=0;for _ in pairs(row) do keys=keys+1 end
            assert(keys==5 and row.family==wanted[1] and row.main_id==wanted[2] and row.recipe==wanted[3])
            assert(row.key==nil and row.change==nil and row.collected==nil)
          end
          local a,raw_a=inputs();local b,raw_b=inputs()
          local emitted_a=credit.append(a,raw_a,values(2.5),{recipe_productivity=true})
          local emitted_b=credit.append(b,raw_b,values(2.5),{recipe_productivity=true},{})
          assert(#emitted_a==26 and same(emitted_a,emitted_b) and same(a,b))
          local groups=groups_for_all();local combined=credit.descriptors(groups)
          assert(#combined==18)
          for index=1,13 do assert(same(combined[index],baseline[index])) end
        ''')

    def test_malformed_maps_arrays_values_metatables_aliases_and_cycles_refuse(self):
        self.lua.execute(r'''
          local cases={
            function() return false end,
            function() return {unknown={}} end,
            function() return {[1]={}} end,
            function() return {['research_plastic'..string.char(0)]={}} end,
            function() return {research_plastic=false} end,
            function() return {research_plastic={false}} end,
            function() return {research_plastic={{recipe="",change=.1}}} end,
            function() return {research_plastic={{recipe="a"..string.char(0).."b",change=.1}}} end,
            function() return {research_plastic={{recipe=1,change=.1}}} end,
            function() return {research_plastic={{recipe="x"}}} end,
            function() return {research_plastic={{change=.1}}} end,
            function() return {research_plastic={{recipe="x",change=".1"}}} end,
            function() return {research_plastic={{recipe="x",change=true}}} end,
            function() return {research_plastic={{recipe="x",change=0}}} end,
            function() return {research_plastic={{recipe="x",change=-.1}}} end,
            function() return {research_plastic={{recipe="x",change=math.huge}}} end,
            function() return {research_plastic={{recipe="x",change=-math.huge}}} end,
            function() return {research_plastic={{recipe="x",change=0/0}}} end,
            function() return {research_plastic={{recipe="x",change=.1,main_id="foreign"}}} end,
            function() return {research_plastic={{recipe="x",change=.1,positive_id="foreign"}}} end,
            function() return {research_plastic={{recipe="x",change=.1,key="foreign"}}} end,
            function() return {research_plastic={{recipe="x",change=.1,collected=true}}} end,
            function() return {research_plastic={{recipe="x",change=.1,[1]="foreign"}}} end,
            function() return {research_plastic={{recipe="x",change=.1},{recipe="x",change=.2}}} end,
            function() return {research_plastic={[2]={recipe="x",change=.1}}} end,
            function() return {research_plastic={[1]={recipe="x",change=.1},[3]={recipe="y",change=.2}}} end,
            function() return {research_plastic={name={recipe="x",change=.1}}} end,
            function() return {research_plastic={[0]={recipe="x",change=.1}}} end,
            function() return {research_plastic={[1.5]={recipe="x",change=.1}}} end,
            function() return setmetatable({},{}) end,
            function() return {research_plastic=setmetatable({},{})} end,
            function() return {research_plastic={setmetatable({recipe="x",change=.1},{})}} end,
            function() local g={};g.research_plastic=g;return g end,
            function() local a={};a[1]=a;return {research_plastic=a} end,
            function() local e={recipe="x",change=.1};return {research_plastic={e,e}} end,
            function() local a={{recipe="x",change=.1}};return {research_plastic=a,research_steel=a} end,
            function() local e={recipe="x",change=.1};return {research_plastic={e},research_steel={e}} end,
          }
          for _,build in ipairs(cases) do
            local malformed=build()
            refuse(function() credit.collected_descriptors(malformed) end)
            local technologies,raw=collected_inputs();local before=#technologies
            refuse(function() credit.append(technologies,raw,nil,{recipe_productivity=true},malformed) end)
            assert(#technologies==before and technologies[1].effects[1].change==.77)
          end
        ''')

    def test_late_missing_named_main_recipe_or_identity_collision_never_appends_partial_set(self):
        self.lua.execute(r'''
          for _,case in ipairs({"missing-main","wrong-main-type","missing-recipe","wrong-recipe-type",
              "wrong-recipe-name","positive-collision","negative-collision","duplicate-main"}) do
            local fixed,raw_fixed=inputs()
            local dynamic,raw=collected_inputs();local groups=groups_for_all()
            -- A late failure must preserve a pending full fixed24 set too.
            for index=2,#fixed do dynamic[#dynamic+1]=fixed[index] end
            for _,row in ipairs(expected) do raw.recipe[row[3]]=raw_fixed.recipe[row[3]] end
            local last="recipe-prod-research_steel-1"
            if case=="missing-main" then dynamic[6].name="foreign-other-main"
            elseif case=="wrong-main-type" then dynamic[6].type="item"
            elseif case=="missing-recipe" then groups.research_steel[1].recipe="last-missing-route"
            elseif case=="wrong-recipe-type" then raw.recipe['shared-route'].type="item"
            elseif case=="wrong-recipe-name" then raw.recipe['shared-route'].name="foreign"
            elseif case=="positive-collision" then dynamic[#dynamic+1]={name="mir-native-credit-research_steel-shared-route-positive"}
            elseif case=="negative-collision" then dynamic[#dynamic+1]={name="mir-native-credit-research_steel-shared-route-negative"}
            else dynamic[#dynamic+1]={type="technology",name=last} end
            local before=#dynamic
            refuse(function() credit.append(dynamic,raw,values(10),{recipe_productivity=true},groups) end)
            assert(#dynamic==before and dynamic[1].effects[1].change==.77,case.." appended a partial set")
          end
          local technologies,raw=collected_inputs();local groups=groups_for_all()
          groups.research_steel={{recipe="shared-route",change=.1},{recipe="shared-route",change=.1}}
          local before=#technologies
          refuse(function() credit.append(technologies,raw,nil,{recipe_productivity=true},groups) end)
          assert(#technologies==before)
        ''')

    def test_one_owned_output_index_and_named_recipe_lookups_only(self):
        self.lua.execute(r'''
          local backing,raw=collected_inputs();local original=#backing;local reads=0
          local output=setmetatable({},{__len=function() return #backing end,
            __index=function(_,key) reads=reads+1;assert(key>=1 and key<=original);return backing[key] end,
            __newindex=function(_,key,value) assert(key>#backing);backing[key]=value end,
            __pairs=function() error("enumerated output") end})
          local added=credit.append(output,raw,nil,{recipe_productivity=true},groups_for_all())
          assert(reads==original and #added==10 and #backing==original+10,"output indexed more than once")
          local fixed,full_raw=inputs()
          local one={fixed[2]}
          full_raw.recipe=setmetatable({['copper-plate']={name='copper-plate'}},
            {__index=function() error("absent fixed main caused an irrelevant recipe lookup") end})
          assert(#credit.append(one,full_raw,values(10),{recipe_productivity=true})==2)
        ''')

    def test_empty_groups_and_inactive_target_retain_existing_no_work_boundary(self):
        self.lua.execute(r'''
          assert(#credit.collected_descriptors()==0 and #credit.collected_descriptors({})==0)
          assert(#credit.collected_descriptors({research_plastic={}})==0)
          local poison=setmetatable({},{__index=function() error("inactive target consumed input") end})
          local technologies={{name="foreign"}}
          assert(#credit.append(technologies,poison,nil,{recipe_productivity=false},poison)==0)
          assert(#technologies==1)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeFamilyCreditDefinitionTests))
    raise SystemExit(0 if result.wasSuccessful() else 1)

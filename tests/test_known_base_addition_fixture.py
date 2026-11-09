"""Bounded successor fixture controls; no native save or lab qualification."""
import argparse
import json
from pathlib import Path
import sys
import unittest

import test_generator as generator
import test_native_family_paid_credits as paid_fixture

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/known-base-addition"


class KnownBaseAdditionFixtureTests(unittest.TestCase):
    def controller(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        lua.execute('''
          function table.deepcopy(value)
            if type(value)~="table"then return value end
            local out={};for k,v in pairs(value)do out[k]=table.deepcopy(v)end;return out
          end
          storage,callbacks,markers={}, {}, {}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}
          script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20012",
            ["mir-fixture-mir5-known-base-addition"]="0.1.0"},
            on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,
            on_configuration_changed=function(f)callbacks.configuration=f end,
            on_event=function(id,f)callbacks[id]=f end}
          helpers={table_to_json=function(value)markers[#markers+1]=table.deepcopy(value);return "{}"end}
          log=function()end
          local names={"player","mir5-migration-origin-f200-110-foreign","mir5-migration-origin-f200-110-detached"}
          local families={{"low_density_structure","low-density-structure"},{"plastic","plastic-bar"},
            {"processing_unit","processing-unit"},{"rocket_fuel","rocket-fuel"},{"steel","steel-plate"}}
          game={tick=10,speed=1,forces={},surface_calls=0,saves={}}
          local function technology(force,name,level,hidden,enabled,recipe,change)
            local t={name=name,valid=true,force=force,level=level,researched=false,enabled=enabled,
              saved_progress=0,visible_when_disabled=false,
              prototype={hidden=hidden,max_level=4294967295,effects={}},
              research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1}}}
            if recipe then t.prototype.effects={{type="change-recipe-productivity",recipe=recipe,change=change}}end
            force.technologies[name]=t;return t
          end
          for i,name in ipairs(names)do
            local force={name=name,index=i==1 and 1 or i==2 and 4 or 5,valid=true,technologies={},recipes={},
              research_queue={},research_progress=0,mining_drill_productivity_bonus=0,worker_robots_battery_modifier=.1,
              get_ammo_damage_modifier=function()return 0 end}
            game.forces[name]=force
            for _,family in ipairs(families)do
              technology(force,"recipe-prod-research_"..family[1].."-1",2,family[1]=="plastic",family[1]~="plastic")
              force.recipes[family[2]]={valid=true,productivity_bonus=.1}
            end
            force.recipes["iron-gear-wheel"]={valid=true,productivity_bonus=i==1 and .2 or 0}
            technology(force,"recipe-prod-research_gears-1",i==1 and 3 or 1,false,true)
            for _,family in ipairs({{"plastic","plastic-bar"},{"low_density_structure","low-density-structure"}})do
              local extra="mir-known-base-unpaid-"..family[2]
              force.recipes[extra]={valid=true,productivity_bonus=0}
              for _,recipe in ipairs({family[2],extra})do
                for _,direction in ipairs({"positive","negative"})do
                  local level=family[1]=="plastic" and recipe==family[2] and direction=="positive" and 2
                    or family[1]=="low_density_structure" and recipe==extra and direction=="negative" and 2 or 1
                  technology(force,"mir-native-credit-research_"..family[1].."-"..recipe.."-"..direction,
                    level,true,false,recipe,direction=="positive"and .1 or -.1)
                end
              end
            end
          end
          foreign=game.forces[names[2]];detached=game.forces[names[3]]
          gear=foreign.technologies["recipe-prod-research_gears-1"]
          plastic=foreign.technologies["recipe-prod-research_plastic-1"]
          foreign.current_research=gear;foreign.research_queue={gear,plastic};foreign.research_progress=.42
          detached.technologies["recipe-prod-research_gears-1"].saved_progress=.27
          function game.create_surface()
            game.surface_calls=game.surface_calls+1
            local surface={request_to_generate_chunks=function()end,force_generate_chunk_requests=function()end,set_tiles=function()end}
            surface.create_entity=function(spec)
              local counts={};local inventory={clear=function()counts={}end,
                insert=function(row)counts[row.name]=(counts[row.name]or 0)+row.count;return row.count end,
                get_item_count=function(name)return counts[name]or 0 end}
              return {valid=true,force=spec.force,get_inventory=function()return inventory end}
            end
            return surface
          end
          function game.server_save(name)game.saves[#game.saves+1]=name end
          event={mod_startup_settings_changed=false,mod_changes={
            ["more-infinite-research"]={old_version="5.0.20001",new_version="5.0.20012"},
            ["mir-fixture-mir5-known-base-addition"]={new_version="0.1.0"}}}
          dofile(control_path)
          function begin()callbacks.init();callbacks.configuration(event);game.tick=11;callbacks[1]()end
          function consume()
            for _,lab in ipairs(storage.mir5_known_base_addition.labs)do
              local input=lab.get_inventory(1);local old=input.get_item_count("automation-science-pack")
              input.clear();input.insert{name="automation-science-pack",count=old-1}
              input.insert{name="logistic-science-pack",count=old-1}
            end
          end
          function finish_gear()
            consume();gear.level=gear.level+1;foreign.current_research=plastic
            foreign.research_queue={plastic};foreign.research_progress=0
            foreign.recipes["iron-gear-wheel"].productivity_bonus=.1
            game.tick=12;callbacks[2]({research=gear,by_script=false});callbacks[1]()
          end
          function finish_plastic()
            consume();plastic.level=plastic.level+1;foreign.current_research=nil;foreign.research_queue={}
            foreign.recipes["plastic-bar"].productivity_bonus=.2
            foreign.technologies["mir-native-credit-research_plastic-plastic-bar-positive"].level=3
            game.tick=13;callbacks[2]({research=plastic,by_script=false});callbacks[1]()
          end
        ''')
        return lua

    def pipeline(self, retire=True):
        generator.LuaRuntime = LuaRuntime
        case = generator.GeneratorTests()
        case.setUp()
        lua = case.lua
        lua.globals().addition_fixture = FIXTURE.as_posix()
        lua.execute('''
          -- Stand-in for the engine-provided helper, absent in bare Lua.
          function table.deepcopy(value)
            if type(value)~="table" then return value end
            local out={};for key,item in pairs(value)do out[key]=table.deepcopy(item)end;return out
          end
          local target=require("platform.target")
          target.id="f200";target.factorio_version="2.0";target.minimum_base="2.0.77"
          mods={base="2.0.77",["mir-fixture-mir5-known-base-addition"]="0.1.0"}
          package.loaded["research.settings"]=nil
          local config=require("research.settings");local startup={}
          for _,row in ipairs(config.prototypes())do startup[row.name]={value=row.default_value}end
          settings,data,helpers,log={startup=startup},full_world(mods,true),nil,function()end
          function data:extend(rows)
            self.writes=self.writes+1
            for _,row in ipairs(rows)do
              self.raw[row.type]=self.raw[row.type]or{};self.raw[row.type][row.name]=row
            end
          end
          -- full_world supplies existence-only Base recipes. Give these two
          -- host stand-ins explicit independent product/ingredient rows;
          -- this is not a capture of their native recipe workload.
          for _,name in ipairs({"plastic-bar","low-density-structure"})do
            local row=data.raw.recipe[name]
            row.ingredients={{type="item",name=name=="plastic-bar" and "coal" or "copper-plate",amount=1}}
            row.results={{type="item",name=name,amount=1}}
            row.allow_productivity=true
          end
          dofile(addition_fixture.."/data.lua")
          dofile(player_root.."/data.lua");dofile(data_final_path)
        ''')
        if retire:
            lua.execute('dofile(addition_fixture.."/data-final-fixes.lua")')
        return lua

    def test_real_pipeline_retains_both_new_credit_routes_and_public_lds(self):
        lua = self.pipeline()
        lua.execute('''
          local plastic=data.raw.technology["recipe-prod-research_plastic-1"]
          local lds=data.raw.technology["recipe-prod-research_low_density_structure-1"]
          assert(plastic.hidden==true and plastic.enabled==false and #plastic.effects==0)
          assert(lds.hidden~=true and #lds.effects==2)
          local expected={["low-density-structure"]=true,["mir-known-base-unpaid-low-density-structure"]=true}
          for _,effect in ipairs(lds.effects)do
            assert(effect.type=="change-recipe-productivity" and effect.change==.1 and expected[effect.recipe])
            expected[effect.recipe]=nil
          end
          assert(next(expected)==nil)
          local groups=data.raw["mod-data"]["more-infinite-research-native-adoptions"].data.credits
          for _,family in ipairs({"plastic","low_density_structure"})do
            local recipe=family=="plastic" and "plastic-bar" or "low-density-structure"
            local rows=groups["research_"..family]
            assert(#rows==2 and rows[1].change==.1 and rows[2].change==.1)
            local found={};for _,row in ipairs(rows)do found[row.recipe]=true end
            assert(found[recipe] and found["mir-known-base-unpaid-"..recipe])
            local original=data.raw.recipe[recipe]
            local extra=data.raw.recipe["mir-known-base-unpaid-"..recipe]
            assert(original~=extra and original.ingredients~=extra.ingredients)
            assert(extra.allow_productivity==true and extra.enabled==true and extra.hidden==false)
          end
        ''')

    def test_emitted_vectors_cross_the_actual_credit_runtime_without_old_rights_for_new_recipes(self):
        pipeline = self.pipeline()
        groups = generator.plain_lua(pipeline.globals().data.raw["mod-data"]
                                     ["more-infinite-research-native-adoptions"].data.credits)
        prototypes = generator.plain_lua(pipeline.globals().data.raw.technology)
        paid_fixture.LuaRuntime = LuaRuntime
        case = paid_fixture.NativeFamilyPaidCreditsTests()
        case.setUp()
        lua = case.lua
        lua.globals().GROUPS = generator.lua_table(lua, groups)
        lua.globals().emitted = generator.lua_table(lua, prototypes)
        lua.execute('''
          local active={base="2.0.77",["more-infinite-research"]="5.0.20012",
            ["mir-fixture-mir5-known-base-addition"]="0.1.0"}
          reload_credits(active,"f200")
          local mask={}
          for family,recipes in pairs(GROUPS)do
            if family~="research_plastic"then for _,row in ipairs(recipes)do mask[key(family,row.recipe)]=true end end
          end
          local force=make_collected_force(1,2,mask)
          for name,state in pairs(force._states)do
            if emitted[name]then
              local prototype=emitted[name];prototype.level=prototype.level or 1
              assert(prototype.max_level=="infinite");prototype.max_level=UINT32_MAX
              -- The retained independent F200 observations expose binary32
              -- hundredths here, rather than authored Lua doubles.
              for _,effect in ipairs(prototype.effects or {})do
                if effect.type=="change-recipe-productivity"then effect.change=fixture_effect(effect.change)end
              end
              state.prototype=prototype
            end
          end
          local main=force.technologies["recipe-prod-research_plastic-1"]
          local queue={force.technologies.foreign,main}
          force.current_research=force.technologies.foreign;force.research_queue=queue
          main.saved_progress=.27
          native_credits.on_configuration_changed({mod_startup_settings_changed=false,mod_changes={
            ["more-infinite-research"]={old_version="5.0.20001",new_version="5.0.20012"},
            ["mir-fixture-mir5-known-base-addition"]={new_version="0.1.0"}}})
          close(own_contribution(force,"research_plastic","plastic-bar"),.1)
          close(own_contribution(force,"research_low_density_structure","low-density-structure"),.1)
          close(own_contribution(force,"research_plastic","mir-known-base-unpaid-plastic-bar"),0)
          close(own_contribution(force,"research_low_density_structure","mir-known-base-unpaid-low-density-structure"),0)
          assert(record(force,"research_plastic","plastic-bar").payable==true)
          assert(record(force,"research_plastic","mir-known-base-unpaid-plastic-bar").payable==false)
          assert(force.research_queue==queue and main.saved_progress==.27 and force.research_progress==.42)
          advance(force,main.name,3,false);native_credits.on_research_finished({research=main,by_script=false})
          close(own_contribution(force,"research_plastic","plastic-bar"),.2)
          close(own_contribution(force,"research_plastic","mir-known-base-unpaid-plastic-bar"),0)
          native_credits.on_research_finished({research=main,by_script=false})
          close(own_contribution(force,"research_plastic","plastic-bar"),.2)
          no_foreign_write(force)
        ''')

    def test_late_retirement_refuses_unknown_vectors_without_rewriting_the_main(self):
        for opponent in ("missing", "extra", "duplicate", "scalar", "effect-type", "already-private"):
            with self.subTest(opponent=opponent):
                lua = self.pipeline(retire=False)
                lua.globals().opponent = opponent
                lua.execute('''
                  local main=data.raw.technology["recipe-prod-research_plastic-1"]
                  if opponent=="missing" then table.remove(main.effects) end
                  if opponent=="extra" then main.effects[3]={type="change-recipe-productivity",recipe="foreign",change=.1} end
                  if opponent=="duplicate" then main.effects[2].recipe=main.effects[1].recipe end
                  if opponent=="scalar" then main.effects[2].change=.2 end
                  if opponent=="effect-type" then main.effects[2].type="laboratory-speed" end
                  if opponent=="already-private" then main.hidden=true end
                  local effects,hidden,enabled=main.effects,main.hidden,main.enabled
                  local ok=pcall(dofile,addition_fixture.."/data-final-fixes.lua")
                  assert(not ok,"unexpected vector was silently retired")
                  assert(main.effects==effects and main.hidden==hidden and main.enabled==enabled)
                ''')

    def test_selection_requires_a_new_verified_pure_source(self):
        profile = json.loads((ROOT / "tests/profiles/known-base-addition-f200-2077.json").read_bytes())
        required = profile["protected_input_requirement"]
        self.assertEqual(required["status"], "missing-verified-pure-Base-derivative")
        self.assertEqual(required["old_mods"], ["base", "more-infinite-research"])
        self.assertEqual(required["old_mir"], "5.0.20001")
        self.assertEqual(required["parent_save_sha256"], "0C783E41265F9A0EF818E92B5B44435A4585329C06AC959FE988310CDFF3FBEA")
        self.assertNotIn("protected_input_save", profile)
        self.assertIs(required["startup_changed_on_successor"], False)
        self.assertEqual(required["game_speed"], 1)
        info = json.loads((FIXTURE / "info.json").read_bytes())
        self.assertEqual(info["dependencies"], ["base = 2.0.77", "more-infinite-research = 5.0.20012"])
        self.assertEqual(info["version"], "0.1.0")

    def test_actor_preserves_initial_receipt_and_requires_later_tick_before_save(self):
        lua = self.controller()
        lua.execute('''
          begin();assert(game.speed==1 and foreign.research_progress==.42 and #foreign.research_queue==2)
          assert(gear.level==1 and plastic.level==2 and #game.saves==0)
          finish_gear();finish_plastic();assert(#game.saves==0,"event-time state was counted as settled")
          game.tick=14;callbacks[1]()
          local state=storage.mir5_known_base_addition
          assert(state.phase=="completed" and #state.completions==2)
          assert(state.initial[foreign.name].progress==.42 and state.final[foreign.name].progress==0)
          assert(#game.saves==1 and game.saves[1]=="mir5-native-complete")
          assert(#markers==1 and markers[1].stage=="initial")
          for _=1,2 do
            local original=game;game=nil;callbacks.load();game=original
            callbacks[1]();callbacks[1]()
          end
          assert(#markers==3 and markers[2].stage=="reload" and markers[3].stage=="reload")
          assert(#game.saves==1 and game.surface_calls==1 and game.speed==1)
        ''')

    def test_actor_refuses_unproven_source_or_lost_state_before_lab_creation(self):
        for opponent in ("startup", "startup-absent", "old-helper", "removed-provider", "wrong-origin",
                         "speed", "lost-detached", "new-bonus", "changed-base"):
            with self.subTest(opponent=opponent):
                lua = self.controller()
                lua.globals().opponent = opponent
                lua.execute('''
                  if opponent=="startup"then event.mod_startup_settings_changed=true end
                  if opponent=="startup-absent"then event.mod_startup_settings_changed=nil end
                  if opponent=="old-helper"then event.mod_changes["mir-fixture-mir5-known-base-addition"].old_version="0.1.0"end
                  if opponent=="removed-provider"then event.mod_changes.removed={old_version="1.0.0"}end
                  if opponent=="wrong-origin"then event.mod_changes["more-infinite-research"].old_version="5.0.20009"end
                  if opponent=="speed"then game.speed=16 end
                  if opponent=="lost-detached"then detached.technologies["recipe-prod-research_gears-1"].saved_progress=0 end
                  if opponent=="new-bonus"then foreign.recipes["mir-known-base-unpaid-plastic-bar"].productivity_bonus=.1 end
                  if opponent=="changed-base"then event.mod_changes.base={old_version="2.0.76",new_version="2.0.77"}end
                  callbacks.init();local ok=pcall(callbacks.configuration,event)
                  assert(not ok,"unproven source was accepted")
                  assert(game.surface_calls==0 and #game.saves==0 and #markers==0)
                  assert(gear.level==1 and plastic.level==2 and foreign.research_queue[1]==gear)
                ''')

    def test_actor_does_not_invent_paid_steel_from_the_four_family_parent_capture(self):
        lua = self.controller()
        lua.execute('''
          for _,force in pairs(game.forces)do
            force.technologies["recipe-prod-research_steel-1"].level=1
            force.recipes["steel-plate"].productivity_bonus=0
          end
          begin()
          for name,force in pairs(game.forces)do
            local recorded=storage.mir5_known_base_addition.initial[name]
            assert(recorded.rows["recipe-prod-research_steel-1"].level==1 and recorded.bonuses["steel-plate"]==0)
            assert(force.technologies["recipe-prod-research_steel-1"].level==1 and force.recipes["steel-plate"].productivity_bonus==0)
          end
        ''')

    def test_actor_rejects_script_completion_no_consumption_and_unrelated_final_drift(self):
        for opponent in ("scripted", "no-consumption", "unrelated-drift"):
            with self.subTest(opponent=opponent):
                lua = self.controller()
                lua.globals().opponent = opponent
                lua.execute('''
                  begin();local ok
                  if opponent=="scripted"then ok=pcall(callbacks[2],{research=gear,by_script=true})
                  elseif opponent=="no-consumption"then ok=pcall(callbacks[2],{research=gear,by_script=false})
                  else
                    finish_gear();finish_plastic();game.forces.player.mining_drill_productivity_bonus=.1
                    game.tick=14;ok=pcall(callbacks[1])
                  end
                  assert(not ok,"false ordinary/preservation result accepted")
                  assert(#game.saves==0 and #markers==0)
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

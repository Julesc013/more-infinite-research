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
    def controller(self, base_lab_speed=1):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        lua.globals().base_lab_speed = base_lab_speed
        lua.execute('''
          local function host_copy(value)
            if type(value)~="table"then return value end
            local out={};for k,v in pairs(value)do out[k]=host_copy(v)end;return out
          end
          assert(table.deepcopy==nil,"runtime must not supply the data-stage copy helper")
          storage,callbacks,markers={}, {}, {}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}
          script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20012",
            ["mir-fixture-mir5-known-base-addition"]="0.1.0"},
            on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,
            on_configuration_changed=function(f)callbacks.configuration=function(e)host_worker_transfer();f(e)end end,
            on_event=function(id,f)callbacks[id]=f end}
          helpers={table_to_json=function(value)
            assert(value.mods~=script.active_mods)
            local state=storage.mir5_known_base_addition
            assert(value.event~=state.event and value.event.mod_changes~=state.event.mod_changes)
            markers[#markers+1]=host_copy(value);return "{}"
          end}
          log=function()end
          local names={"player","mir5-migration-origin-f200-110-foreign","mir5-migration-origin-f200-110-detached"}
          local families={{"low_density_structure","low-density-structure"},{"plastic","plastic-bar"},
            {"processing_unit","processing-unit"},{"rocket_fuel","rocket-fuel"},{"steel","steel-plate"}}
          game={tick=10,speed=16,forces={},surface_calls=0,saves={},difficulty_settings={technology_price_multiplier=1}}
          --875-shaped native readback stand-in; only the owner can compare
          -- an actual engine dictionary with the protected source receipt.
          settings={startup={}}
          for i=1,875 do settings.startup["host-observed-setting-"..i]={value=i}end
          local function technology(force,name,level,hidden,enabled,recipe,change)
            local t={name=name,valid=true,force=force,level=level,researched=false,enabled=enabled,
              saved_progress=0,visible_when_disabled=false,
              prototype={hidden=hidden,enabled=enabled,max_level=4294967295,effects={},research_unit_energy=3600,ignore_tech_cost_multiplier=false,
                research_unit_count_formula="8000*2^(L-1)"},research_unit_ingredients={}}
            for _,pack in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"})do
              t.research_unit_ingredients[#t.research_unit_ingredients+1]={name=pack,amount=1}
            end
            setmetatable(t,{__index=function(_,key)if key=="research_unit_count"then return 8000*2^(t.level-1)end end})
            if recipe then t.prototype.effects={{type="change-recipe-productivity",recipe=recipe,change=change}}end
            force.technologies[name]=t;return t
          end
          for i,name in ipairs(names)do
            local force={name=name,index=i==1 and 1 or i==2 and 4 or 5,valid=true,technologies={},recipes={},
              research_queue={},research_progress=0,manual_mining_speed_modifier=0,mining_drill_productivity_bonus=1.25,
              worker_robots_battery_modifier=.1,get_gun_speed_modifier=function()return 0 end,
              get_ammo_damage_modifier=function()return .75 end,laboratory_productivity_bonus=0,laboratory_speed_modifier=0}
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
          WORKER={"worker-robots-storage-4","mir-worker-storage-default-4","mir-worker-storage-head-4","mir-worker-storage-preservation-4"}
          for _,force in pairs(game.forces)do
            force.worker_robots_storage_bonus=0
            for index,name in ipairs(WORKER)do
              local debit=index==3;local private=index==4
              local science={}
              for _,pack in ipairs(debit and{"automation-science-pack"}or{"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"})do science[#science+1]={name=pack,amount=1}end
              local hidden=debit or private
              force.technologies[name]={name=name,valid=true,force=force,level=4,researched=false,
                enabled=not hidden,visible_when_disabled=false,saved_progress=0,research_unit_count=debit and 1 or 675,
                research_unit_ingredients=science,prototype={level=4,max_level=debit and 4 or 4294967295,
                  hidden=hidden,enabled=not hidden,visible_when_disabled=false,prerequisites=debit and{}or{["worker-robots-storage-3"]={name="worker-robots-storage-3"}},
                  research_unit_count_formula=not debit and"675*1.5^(L-4)"or nil,research_unit_energy=debit and 60 or 3600,
                  ignore_tech_cost_multiplier=false,effects={{type="worker-robot-storage",modifier=debit and -1 or 1}}}}
            end
          end
          function host_worker_transfer()
            -- Independent native setter outcome stand-in, never product imports.
            for _,force in pairs(game.forces)do
              local c,t=force.technologies[WORKER[1]],force.technologies[WORKER[2]]
              t.enabled,t.visible_when_disabled=c.enabled,c.visible_when_disabled;c.enabled=false
            end
          end
          gear=foreign.technologies["recipe-prod-research_gears-1"]
          plastic=foreign.technologies["recipe-prod-research_plastic-1"]
          foreign.current_research=gear;foreign.research_queue={gear,plastic};foreign.research_progress=.42/8000
          detached.technologies["recipe-prod-research_gears-1"].saved_progress=.27/8000
          function game.create_surface()
            game.surface_calls=game.surface_calls+1
            local surface={request_to_generate_chunks=function()end,force_generate_chunk_requests=function()end,set_tiles=function()end}
            surface.create_entity=function(spec)
              local counts={};local inventory={clear=function()counts={}end,
                insert=function(row)counts[row.name]=(counts[row.name]or 0)+row.count;return row.count end,
                remove=function(row)local n=math.min(counts[row.name]or 0,row.count);counts[row.name]=(counts[row.name]or 0)-n;return n end,
                get_item_count=function(name)return counts[name]or 0 end}
              return setmetatable({valid=true,name=spec.name,force=spec.force,disabled_by_script=false,
                prototype={get_researching_speed=function(quality)
                  assert(quality=="normal");return spec.name=="mir-known-base-fast-lab"and 14400 or base_lab_speed
                end},get_inventory=function()return inventory end},
                {__newindex=function(t,k,v)assert(k~="active","active is not a portable writable field");rawset(t,k,v)end})
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
              input.clear()
              for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"})do
                input.insert{name=name,count=old-1}
              end
            end
          end
          function finish_gear()
            consume();gear.level=gear.level+1;foreign.current_research=plastic
            foreign.research_queue={plastic};foreign.research_progress=0
            foreign.recipes["iron-gear-wheel"].productivity_bonus=.1
            game.tick=12;callbacks[2]({research=gear,by_script=false});callbacks[1]()
            game.tick=13;callbacks[1]() -- settle the native gear debit before stocking plastic
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
          -- Explicit Base lab facts consumed by the new test-only clone.
          data.raw.lab.lab={type="lab",name="lab",researching_speed=1,energy_source={type="electric"},
            inputs={"automation-science-pack","logistic-science-pack","military-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack","space-science-pack"}}
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

    def test_empty_worker_native_projection_is_explicit_and_immutable_on_two_colds(self):
        lua=self.controller();lua.execute('''
          begin();local state=storage.mir5_known_base_addition
          for name,source in pairs(state.worker_source)do
            local actual=state.worker_initial[name]
            assert(source.rows[WORKER[1]].enabled and not actual.rows[WORKER[1]].enabled)
            assert(actual.rows[WORKER[2]].enabled and actual.bonus==0)
            for _,id in ipairs(WORKER)do assert(actual.rows[id].level==4 and not actual.rows[id].researched and actual.rows[id].saved==0)end
          end
          finish_gear();finish_plastic();game.tick=14;callbacks[1]()
          assert(markers[1].worker_provenance:find("prior-D38-C4-not-captured",1,true))
          for _=1,2 do local oldgame=game;game=nil;callbacks.load();game=oldgame;callbacks[1]()end
          assert(#markers==3 and #game.saves==1)
          for _,marker in ipairs(markers)do
            assert(marker.worker_final.player.bonus==0 and marker.worker_final.player.rows[WORKER[2]].enabled)
          end
          markers[1].worker_source.player.rows[WORKER[1]].enabled=false
          assert(state.worker_source.player.rows[WORKER[1]].enabled)
        ''')

    def test_empty_worker_source_rejects_earned_current_queued_saved_and_nonboolean_flags(self):
        for change in ('c.level=5','c.researched=true','c.saved_progress=.01',
                       'foreign.current_research=c','foreign.research_queue={gear,c}',
                       'c.enabled=nil','c.visible_when_disabled=0','foreign.worker_robots_storage_bonus=1'):
            with self.subTest(change=change):
                lua=self.controller();lua.execute('local c=foreign.technologies[WORKER[1]];'+change+'''
                  local ok=pcall(callbacks.init)
                  assert(not ok and game.surface_calls==0 and #game.saves==0 and #markers==0)
                ''')

    def test_worker_missing_holder_wrong_projection_and_late_drift_remain_fatal(self):
        changes=('foreign.technologies[WORKER[2]]=nil','foreign.technologies[WORKER[3]]=nil',
                 'c.enabled=true','t.enabled=false','t.visible_when_disabled=true','t.saved_progress=.01',
                 't.level=5','h.researched=true','h.visible_when_disabled=true','p.enabled=true',
                 'foreign.worker_robots_storage_bonus=1','t.prototype.research_unit_count_formula="676*1.5^(L-4)"',
                 't.prototype.hidden=nil','t.prototype.enabled="true"',
                 't.research_unit_ingredients[1].amount=2')
        for change in changes:
            with self.subTest(change=change):
                lua=self.controller();lua.globals().change=change
                lua.execute('''
                  callbacks.init();local original=host_worker_transfer
                  host_worker_transfer=function()original()
                    c=foreign.technologies[WORKER[1]];t=foreign.technologies[WORKER[2]]
                    h=foreign.technologies[WORKER[3]];p=foreign.technologies[WORKER[4]]
                    assert(load(change))()
                  end
                  local ok=pcall(callbacks.configuration,event)
                  assert(not ok and game.surface_calls==0 and #game.saves==0 and #markers==0)
                ''')
        for cold in (False, True):
            lua=self.controller();lua.globals().cold=cold;lua.execute('''
              begin();finish_gear();finish_plastic();game.tick=14
              if cold then callbacks[1]();callbacks.load()end
              detached.technologies[WORKER[2]].saved_progress=.01
              local count=#game.saves;local ok=pcall(callbacks[1])
              assert(not ok and #game.saves==count)
            ''')

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
        self.assertEqual(required["status"], "qualified-pure-source-owner-binds-local-input")
        self.assertEqual(required["old_mods"], ["base", "more-infinite-research"])
        self.assertEqual(required["old_mir"], "5.0.20001")
        self.assertEqual(required["parent_save_sha256"], "0C783E41265F9A0EF818E92B5B44435A4585329C06AC959FE988310CDFF3FBEA")
        self.assertNotIn("protected_input_save", profile)
        self.assertIs(required["startup_changed_on_successor"], False)
        self.assertEqual(required["game_speed"], 16)
        self.assertEqual(required["qualified_source_save_sha256"], "D38CD57B0C2310569DD3039AD9109EB7F6F19930E27BA73A8E86E9869F000CA2")
        self.assertEqual(required["transition_input_sha256"], "1FD23C73DFBCFB10F5D1D1F6808BDDA10B0E20F46137BBBB42649DD10B532AF7")
        self.assertNotIn("mir-fixture-mir5-active-mods-observer", [row["name"] for row in profile["mods"]])
        info = json.loads((FIXTURE / "info.json").read_bytes())
        self.assertEqual(info["dependencies"], ["base = 2.0.77", "more-infinite-research = 5.0.20012"])
        self.assertEqual(info["version"], "0.1.0")

    def test_actor_preserves_initial_receipt_and_requires_later_tick_before_save(self):
        lua = self.controller()
        lua.execute('''
          begin();assert(game.speed==16 and foreign.research_progress==.42/8000 and #foreign.research_queue==2)
          assert(gear.level==1 and plastic.level==2 and #game.saves==0)
          finish_gear();finish_plastic();assert(#game.saves==0,"event-time state was counted as settled")
          game.tick=14;callbacks[1]()
          local state=storage.mir5_known_base_addition
          assert(state.phase=="completed" and #state.completions==2)
          assert(state.initial[foreign.name].progress==.42/8000 and state.final[foreign.name].progress==0)
          assert(state.initial[foreign.name].rows[gear.name].level==1)
          assert(state.initial[foreign.name].rows[plastic.name].level==2)
          assert(state.initial[foreign.name].bonuses["iron-gear-wheel"]==0)
          assert(state.initial[foreign.name].queue[1]==gear.name and #state.initial[foreign.name].queue==2)
          assert(#game.saves==1 and game.saves[1]=="mir5-native-complete")
          assert(#markers==1 and markers[1].stage=="initial")
          for _=1,2 do
            local original=game;game=nil;callbacks.load();game=original
            callbacks[1]();callbacks[1]()
          end
          assert(#markers==3 and markers[2].stage=="reload" and markers[3].stage=="reload")
          assert(#game.saves==1 and game.surface_calls==1 and game.speed==16)
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
                  if opponent=="speed"then game.speed=1 end
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
                    finish_gear();finish_plastic();game.forces.player.manual_mining_speed_modifier=.1
                    game.tick=14;ok=pcall(callbacks[1])
                  end
                  assert(not ok,"false ordinary/preservation result accepted")
                  assert(#game.saves==0 and #markers==0)
                ''')


    def test_normal_cost_16000_level_refills_past_6400_stock_without_cost_changes(self):
        # Even granting the OLD standard-lab actor the proposed fast speed,
        # its one-time6400 stock cannot pay the16000 plastic level.
        self.assertLess(64 * 100, 16000)
        self.assertGreater(16000 * 3600 / 64, 180 * 60 * 16)
        lua = self.controller(base_lab_speed=14400)
        lua.execute('''
          begin()
          local gear_formula=gear.prototype.research_unit_count_formula
          local plastic_formula=plastic.prototype.research_unit_count_formula
          for tick=12,500 do
            game.tick=tick;callbacks[1]()
            local state=storage.mir5_known_base_addition
            if state.phase=="completed"then break end
            local research=foreign.current_research
            if research then
              local cost=research.research_unit_count
              local remaining=cost*(1-foreign.research_progress)
              for _,lab in ipairs(state.labs)do
                if not lab.disabled_by_script then
                  local input=lab.get_inventory(1)
                  local units=math.min(lab.prototype.get_researching_speed("normal")/research.prototype.research_unit_energy,remaining)
                  for _,ingredient in ipairs(research.research_unit_ingredients)do
                    units=math.min(units,input.get_item_count(ingredient.name)/ingredient.amount)
                  end
                  for _,ingredient in ipairs(research.research_unit_ingredients)do
                    input.remove{name=ingredient.name,count=units*ingredient.amount}
                  end
                  foreign.research_progress=foreign.research_progress+units/cost;remaining=remaining-units
                  if remaining<.00000001 then
                    research.level=research.level+1;foreign.research_progress=0
                    if research==gear then
                      foreign.current_research=plastic;foreign.research_queue={plastic}
                      foreign.recipes["iron-gear-wheel"].productivity_bonus=.1
                    else
                      foreign.current_research=nil;foreign.research_queue={}
                      foreign.recipes["plastic-bar"].productivity_bonus=.2
                      foreign.technologies["mir-native-credit-research_plastic-plastic-bar-positive"].level=3
                    end
                    callbacks[2]({research=research,by_script=false});break
                  end
                end
              end
            end
          end
          local state=storage.mir5_known_base_addition
          assert(state.phase=="completed"and #state.completions==2,"normal16000 workload starved at6400stock")
          assert(state.science[plastic.name].unit.count==16000 and state.science[gear.name].unit.count==8000)
          for _,ingredient in ipairs(plastic.research_unit_ingredients)do
            local ledger=state.science[plastic.name]
            assert(ledger.inserted[ingredient.name]>6400 and ledger.consumed[ingredient.name]>0)
          end
          assert(gear.prototype.research_unit_count_formula==gear_formula and plastic.prototype.research_unit_count_formula==plastic_formula)
          assert(gear.prototype.research_unit_energy==3600 and plastic.prototype.research_unit_energy==3600 and game.speed==16)
          assert(#state.supply_log>2,"same-research refill was not observed")
        ''')

    def test_fast_lab_preserves_base_inputs_and_native_research_units(self):
        lua = self.pipeline()
        lua.execute('''
          local base=data.raw.lab.lab
          local lab=data.raw.lab["mir-known-base-fast-lab"]
          assert(base.researching_speed==1 and base.energy_source.type=="electric")
          assert(lab~=base and lab.inputs~=base.inputs and lab.type=="lab")
          assert(lab.researching_speed==14400 and lab.energy_source.type=="void"and lab.minable==nil)
          local expected={"automation-science-pack","logistic-science-pack","military-science-pack","chemical-science-pack",
            "production-science-pack","utility-science-pack","space-science-pack"}
          assert(#lab.inputs==#expected)
          for i,name in ipairs(expected)do assert(lab.inputs[i]==name and base.inputs[i]==name)end
          for _,id in ipairs({"recipe-prod-research_gears-1","recipe-prod-research_plastic-1"})do
            local unit=data.raw.technology[id].unit
            assert(unit.count==nil and unit.count_formula=="8000*2^(L-1)"and unit.time==60)
            local packs={};for _,pair in ipairs(unit.ingredients)do packs[pair[1]]=pair[2]end
            for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"})do
              assert(packs[name]==1);packs[name]=nil
            end
            assert(next(packs)==nil)
          end
        ''')
        actor = (FIXTURE / "control.lua").read_text()
        for forbidden in ("lab.energy", ".active=", ".active =", "research_recursive", "reset_technology_effects",
                          "game.speed=", "force.research_progress=", "input.clear()"):
            self.assertNotIn(forbidden, actor)

    def test_wrong_target_unconsumed_second_level_and_cold_stock_drift_refuse(self):
        for opponent in ("wrong-target", "unconsumed-plastic", "cold-stock"):
            with self.subTest(opponent=opponent):
                lua = self.controller()
                lua.globals().opponent = opponent
                lua.execute('''
                  begin();local ok,message
                  if opponent=="wrong-target"then
                    ok,message=pcall(callbacks[2],{research=plastic,by_script=false})
                    assert(not ok and tostring(message):find("declared ordinary queue",1,true))
                  elseif opponent=="unconsumed-plastic"then
                    finish_gear();ok,message=pcall(callbacks[2],{research=plastic,by_script=false})
                    assert(not ok and tostring(message):find("consumed no",1,true))
                  else
                    finish_gear();finish_plastic();game.tick=14;callbacks[1]()
                    storage.mir5_known_base_addition.labs[1].get_inventory(1).remove{name="automation-science-pack",count=1}
                    callbacks.load();ok,message=pcall(callbacks[1])
                    assert(not ok and tostring(message):find("cold science stock",1,true))
                  end
                ''')


    def test_original_getter_identities_preserve_nonzero_unobserved_extras(self):
        lua = self.controller()
        lua.execute('''
          begin()
          local state=storage.mir5_known_base_addition
          for name,force in pairs(game.forces)do
            assert(state.initial[name].mining==0 and state.initial[name].cannon==0)
            assert(force.mining_drill_productivity_bonus==1.25 and force.get_ammo_damage_modifier("cannon-shell")==.75)
          end
          finish_gear();finish_plastic();game.tick=14;callbacks[1]()
          callbacks.load();callbacks[1]()
          for name,force in pairs(game.forces)do
            assert(state.final[name].mining==0 and state.final[name].cannon==0)
            assert(force.mining_drill_productivity_bonus==1.25 and force.get_ammo_damage_modifier("cannon-shell")==.75)
          end
        ''')

    def test_captured_manual_mining_and_gun_speed_drift_still_refuse(self):
        for getter in ("manual-mining", "gun-speed"):
            for phase in ("entry", "final"):
                with self.subTest(getter=getter, phase=phase):
                    lua = self.controller()
                    lua.globals().getter, lua.globals().phase = getter, phase
                    lua.execute('''
                      if phase=="final"then begin();finish_gear();finish_plastic()end
                      if getter=="manual-mining"then foreign.manual_mining_speed_modifier=.25
                      else foreign.get_gun_speed_modifier=function()return .25 end end
                      local ok,message
                      if phase=="entry"then callbacks.init();ok,message=pcall(callbacks.configuration,event)
                      else game.tick=14;ok,message=pcall(callbacks[1])end
                      assert(not ok,"captured foreign getter drift was accepted")
                      assert(#game.saves==0)
                    ''')


    def test_observed_clock_and_tight_gear_work_guard_reject_wrong_inputs(self):
        for mutation in ("game.speed=1", "foreign.research_progress=.42",
                         "foreign.research_progress=foreign.research_progress+1e-12",
                         "detached.technologies['recipe-prod-research_gears-1'].saved_progress=.27",
                         "detached.technologies['recipe-prod-research_gears-1'].saved_progress=0",
                         "gear.research_unit_count=8001", "game.difficulty_settings.technology_price_multiplier=2",
                         "plastic.enabled=true", "plastic.prototype.enabled=true"):
            with self.subTest(mutation=mutation):
                lua = self.controller()
                lua.execute(mutation)
                lua.execute('''
                  callbacks.init();local ok=pcall(callbacks.configuration,event)
                  assert(not ok and game.surface_calls==0 and #game.saves==0,"wrong observed source input accepted")
                ''')

    def test_markers_expose_actual_875_mods_clock_event_for_owner_comparison(self):
        lua = self.controller()
        lua.execute('''
          assert(table.deepcopy==nil)
          callbacks.init();callbacks.configuration(event)
          local state=storage.mir5_known_base_addition
          assert(state.event.mod_changes~=event.mod_changes)
          assert(state.event.mod_changes["more-infinite-research"]~=event.mod_changes["more-infinite-research"])
          event.mod_changes["more-infinite-research"].old_version="host-mutated-after-callback"
          assert(state.event.mod_changes["more-infinite-research"].old_version=="5.0.20001")
          game.tick=11;callbacks[1]()
          local science=state.science[gear.name].unit.science
          assert(science~=gear.research_unit_ingredients and science[1]~=gear.research_unit_ingredients[1])
          gear.research_unit_ingredients[1].amount=2
          assert(science[1].amount==1)
          gear.research_unit_ingredients[1].amount=1
          finish_gear();finish_plastic();game.tick=14;callbacks[1]()
          callbacks.load();callbacks[1]()
          for _,m in ipairs(markers)do
            assert(m.clock==16 and m.mods.base=="2.0.77"and m.mods["more-infinite-research"]=="5.0.20012")
            local n=0;for name,value in pairs(settings.startup)do assert(m.startup[name]==value.value);n=n+1 end
            assert(n==875 and m.event.mod_startup_settings_changed==false)
            assert(m.event.mod_changes["more-infinite-research"].old_version=="5.0.20001")
          end
        ''')
        source = {f"host-observed-setting-{i}": i for i in range(1, 876)}
        observed = dict(lua.globals().markers[1].startup.items())
        self.assertEqual(source, observed)
        for changed in ({k: v for k, v in observed.items() if k != "host-observed-setting-875"},
                        observed | {"host-observed-setting-1": "changed"}):
            with self.assertRaises(AssertionError):
                self.assertEqual(source, changed)  # exact owner comparison, not actor-inferred history
        lua = self.controller()
        lua.execute('''
          settings.startup["host-observed-setting-875"]=nil
          callbacks.init();local ok,message=pcall(callbacks.configuration,event)
          assert(not ok and tostring(message):find("not875",1,true)and game.surface_calls==0)
        ''')

    def test_only_eight_scripted_carriers_are_separate_from_ordinary_work(self):
        lua = self.controller()
        lua.execute('''
          begin()
          local state=storage.mir5_known_base_addition
          local names={
            "mir-native-credit-research_plastic-plastic-bar-positive",
            "mir-native-credit-research_plastic-plastic-bar-negative",
            "mir-native-credit-research_plastic-mir-known-base-unpaid-plastic-bar-positive",
            "mir-native-credit-research_plastic-mir-known-base-unpaid-plastic-bar-negative",
            "mir-native-credit-research_low_density_structure-low-density-structure-positive",
            "mir-native-credit-research_low_density_structure-low-density-structure-negative",
            "mir-native-credit-research_low_density_structure-mir-known-base-unpaid-low-density-structure-positive",
            "mir-native-credit-research_low_density_structure-mir-known-base-unpaid-low-density-structure-negative"}
          local stock=state.labs[1].get_inventory(1).get_item_count("automation-science-pack")
          for i,name in ipairs(names)do
            callbacks[2]({research=foreign.technologies[name],by_script=true})
            assert(#state.completions==0 and gear.level==1 and plastic.level==2)
            assert(state.phase=="labs"and state.stocked==gear.name and state.finish_pending==nil)
            assert(state.labs[1].disabled_by_script==false)
            assert(state.labs[1].get_inventory(1).get_item_count("automation-science-pack")==stock)
            local recorded=state.scripted_carrier_events[i]
            assert(recorded.name==name and recorded.by_script==true and recorded.force==foreign.name and recorded.tick==game.tick)
          end
          finish_gear()
          local observe=callbacks[2]
          callbacks[2]=function(event)
            -- Model the Source level setter's nested carrier notification
            -- before the fixture receives the outer ordinary plastic event.
            if event.research==plastic and event.by_script==false then
              local before=#state.completions
              local carrier=foreign.technologies[names[1]]
              carrier.enabled=true -- native setter notification precedes Source re-disablement
              observe({research=carrier,by_script=true})
              assert(carrier.enabled==true,"observer wrote or required a settled flag inside the setter")
              carrier.enabled=false -- Source resumes its own setter after the nested notification
              assert(#state.completions==before)
            end
            observe(event)
          end
          finish_plastic();game.tick=14;callbacks[1]()
          assert(#state.completions==2 and #state.scripted_carrier_events==9 and #game.saves==1)
          assert(#markers[1].ordinary_completions==2 and #markers[1].scripted_carrier_events==9)
          callbacks.load();callbacks[1]();callbacks.load();callbacks[1]()
          assert(#markers==3 and #game.saves==1 and #state.scripted_carrier_events==9)
          for _,marker in ipairs(markers)do
            assert(#marker.scripted_carrier_events==9 and #marker.ordinary_completions==2)
          end
        ''')

    def test_ordinary_carriers_scripted_mains_and_unknown_events_still_refuse(self):
        for opponent in ("ordinary-carrier", "missing-carrier-flag", "scripted-gear", "scripted-plastic",
                         "unknown-scripted", "unknown-ordinary", "other-family-carrier", "missing-main-flag"):
            with self.subTest(opponent=opponent):
                lua = self.controller()
                lua.globals().opponent = opponent
                lua.execute('''
                  begin();local state=storage.mir5_known_base_addition
                  local research,by_script=gear,true
                  if opponent=="ordinary-carrier"or opponent=="missing-carrier-flag"then
                    research=foreign.technologies["mir-native-credit-research_plastic-plastic-bar-positive"]
                    if opponent=="ordinary-carrier"then by_script=false else by_script=nil end
                  elseif opponent=="scripted-plastic"then research=plastic
                  elseif opponent=="missing-main-flag"then by_script=nil
                  elseif opponent=="unknown-scripted"or opponent=="unknown-ordinary"or opponent=="other-family-carrier"then
                    research={force=foreign,name=opponent=="other-family-carrier"
                      and "mir-native-credit-research_processing_unit-processing-unit-positive"
                      or "mir-native-credit-research_plastic-unowned-positive"}
                    by_script=opponent~="unknown-ordinary"
                  end
                  local ok,message=pcall(callbacks[2],{research=research,by_script=by_script})
                  assert(not ok,"unexpected event was accepted")
                  message=tostring(message)
                  assert(message:find("name="..research.name,1,true))
                  assert(message:find("by_script="..tostring(by_script),1,true))
                  assert(message:find("force="..foreign.name,1,true))
                  assert(#state.completions==0 and #state.scripted_carrier_events==0)
                  assert(gear.level==1 and plastic.level==2 and #game.saves==0 and #markers==0)
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

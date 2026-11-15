"""Test-owned vector data/scenario controls, not native or reporter acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

import test_native_family_paid_credits as family_fixture
import test_generator as generator_fixture

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/native-credit-vectors"
ALL_FIVE_FIXTURE = ROOT / "tests/fixtures/native-credit-vectors-allfive"
ALL_FIVE_UPSTREAM = ROOT / "tests/fixtures/native-credit-vectors-allfive-upstream"


class NativeCreditVectorFixtureControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.fixture_path = FIXTURE.as_posix()
        self.lua.execute(r'''
          package.path=fixture_path.."/?.lua;"..package.path
          C=require('contract')
          package.preload['__mir-fixture-native-credit-vectors__/contract']=function()return C end
          function clone(v)if type(v)~='table'then return v end local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
          table.deepcopy=clone
          function data_case(phase,opponent)
            mods={base='2.1.23',['space-age']='2.1.23',quality='2.1.23',['elevated-rails']='2.1.23',recycler='2.1.23',
              ['more-infinite-research']='5.0.21012',[C.mod]=phase}
            settings={startup={['mir-prefer-this-mod-for-competing-techs']={value=true}}}
            data={raw={technology={},recipe={},lab={lab={type='lab',name='lab'}},['mod-data']={}}}
            function data:extend(rows)for _,v in ipairs(rows)do self.raw[v.type]=self.raw[v.type]or{};assert(self.raw[v.type][v.name]==nil);self.raw[v.type][v.name]=v end end
            local tech=data.raw.technology
            tech[C.main]={name=C.main,hidden=true,effects={},unit={count_formula='8000*2^(L-1)',time=60,
              ingredients={{'automation-science-pack',1},{'logistic-science-pack',1},{'chemical-science-pack',1},{'production-science-pack',1}}}}
            local rows={}
            for _,recipe in ipairs({'low-density-structure','casting-low-density-structure','scrap-recycling'})do
              rows[#rows+1]={recipe=recipe,change=.1}
              for _,sign in ipairs({'positive','negative'})do
                tech[C.carrier(recipe,sign)]={hidden=true,enabled=false,effects={{type='change-recipe-productivity',recipe=recipe,change=sign=='positive'and .1 or -.1}}}
              end
            end
            tech[C.public]={effects={{type='change-recipe-productivity',recipe='scrap-recycling',change=.1}}}
            tech['processing-unit-productivity']={effects={{type='change-recipe-productivity',recipe='processing-unit',change=.1}}}
            data.raw['mod-data']['more-infinite-research-native-adoptions']={data={credits={research_low_density_structure=rows}}}
            data.raw.recipe['processing-unit']={type='recipe',name='processing-unit'}
            data.raw.recipe['scrap-recycling']={type='recipe',name='scrap-recycling'}
            if opponent=='foreign-extra'then data.raw['mod-data']['more-infinite-research-native-adoptions'].data.credits.research_low_density_structure[4]={recipe='unknown',change=.1}end
            if opponent=='changed-time'then tech[C.main].unit.time=1 end
            if opponent=='changed-formula'then tech[C.main].unit.count_formula='1'end
            if opponent=='missing-pack'then table.remove(tech[C.main].unit.ingredients)end
            if opponent=='paid-mask-baseline'then tech[C.main].hidden=false end
            dofile(fixture_path..'/data.lua')
            package.loaded['cerys-technology-first45']=nil
            dofile(fixture_path..'/data-final-fixes.lua')
            return tech
          end
        ''')

    def story(self, target="f210", opponent="", completed_shape=False):
        self.lua.globals().target = target
        self.lua.globals().opponent = opponent
        self.lua.globals().completed_shape = completed_shape
        self.lua.execute(r'''
          local callbacks,commands_map,logs,saves={},{},{},{}
          storage={};last_storage=storage;last_logs=logs;last_saves=saves
          local base=target=='f200'and'2.0.77'or'2.1.23'
          local mods={base=base,['space-age']=base,quality=base,['elevated-rails']=base,
            ['more-infinite-research']=target=='f200'and'5.0.20012'or'5.0.21012',[C.mod]='0.1.0'}
          if target=='f210' then mods.recycler=base end
          if opponent=='wrong-engine'then mods.base='2.1.24'end
          if opponent=='wrong-mir'then mods['more-infinite-research']='5.0.21013'end
          local f={technologies={},recipes={},research_progress=0,index=1,name='player',
            laboratory_speed_modifier=0,laboratory_productivity_bonus=0}
          if opponent=='nonzero-lab-speed'then f.laboratory_speed_modifier=.1 end
          if opponent=='nonzero-lab-productivity'then f.laboratory_productivity_bonus=.1 end
          local inv={counts={}}
          inv.insert=function(s)local n=math.min(s.count,1000-(inv.counts[s.name]or 0));inv.counts[s.name]=(inv.counts[s.name]or 0)+n;return n end
          inv.get_item_count=function(name)return inv.counts[name]or 0 end
          local lab=setmetatable({valid=true,disabled_by_script=true},{
            __index=function(t,k)if k=='active'then return not t.disabled_by_script end end,
            __newindex=function(t,k,v)
              if k=='active'then error('native LuaEntity.active is read-only')end
              rawset(t,k,v)
            end})
          lab.get_inventory=function()return inv end
          lab.name=C.lab
          lab.prototype={get_researching_speed=function(quality)
            assert(quality=='normal');return C.lab_speed+(opponent=='fractional-lab-rate'and 1 or 0)
          end}
          local game={tick=0,forces={player=f},difficulty_settings={technology_price_multiplier=1},surfaces={{}}}
          game.surfaces[1].create_entity=function(v)assert(v.name=='mir-vector-lab');return lab end
          game.server_save=function(name)saves[#saves+1]={name=name,tick=game.tick}end
          local function effects(names,sign)
            local out={};for _,name in ipairs(names)do
              local e={type='change-recipe-productivity',recipe=name,change=sign*.1}
              if target=='f210' then e.hidden=false end
              out[#out+1]=e
            end;return out
          end
          local ingredients={};for _,name in ipairs({'automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack'})do ingredients[#ingredients+1]={name=name,amount=1}end
          local function tech(id,names,sign,holder)
            local p={level=1,max_level=4294967295,hidden=holder==true,enabled=not holder,visible_when_disabled=false,effects=effects(names,sign or 1),
              research_unit_count_formula='8000*2^(L-1)',research_unit_energy=3600}
            local t={name=id,valid=true,force=f,prototype=p,level=1,researched=false,enabled=not holder,visible_when_disabled=false,saved_progress=0,research_unit_ingredients=ingredients,prerequisites={}}
            setmetatable(t,{__index=function(_,k)if k=='research_unit_count'then return 8000*2^(t.level-1)end end})
            f.technologies[id]=t;return t
          end
          local main=tech(C.main,C.singles)
          tech(C.public,C.recipes)
          local sentinel=tech(C.sentinel,{});sentinel.prototype.max_level=1
          for _,recipe in ipairs({'scrap-recycling','low-density-structure','casting-low-density-structure'})do
            for _,sign in ipairs({'positive','negative'})do tech(C.carrier(recipe,sign),recipe=='scrap-recycling'and C.recipes or{recipe},sign=='positive'and 1 or -1,true)end
          end
          local prerequisite=tech('production-science-pack',{});prerequisite.prototype.max_level=1
          prerequisite.research_recursive=function()prerequisite.researched=true;callbacks.finished{research=prerequisite,by_script=true}end
          main.prerequisites[prerequisite.name]=prerequisite
          local function count(t)return t.level-1+(t.researched and 1 or 0)end
          local function offset(recipe,n)
            f.technologies[C.carrier(recipe,'positive')].level=1+math.max(n,0)
            f.technologies[C.carrier(recipe,'negative')].level=1+math.max(-n,0)
          end
          local function bonus(scrap,lds)
            for _,name in ipairs(C.recipes)do f.recipes[name]={productivity_bonus=scrap}end
            for _,name in ipairs(C.singles)do f.recipes[name]={productivity_bonus=lds}end
            f.recipes['processing-unit']={productivity_bonus=0};f.recipes['cerys-processing-units-from-nitric-acid']={productivity_bonus=0}
          end
          bonus(0,0)
          local q={}
          setmetatable(f,{__index=function(_,k)if k=='research_queue'then return q end end,
            __newindex=function(_,k,v)if k=='research_queue'then
              if f.current_research then f.current_research.saved_progress=f.research_progress end
              q=v;f.current_research=v[1]
              if v[1]and v[1].researched then v[1].level=v[1].level+1;v[1].researched=false end
              f.research_progress=v[1]and v[1].saved_progress or 0
            else rawset(f,k,v)end end})
          local env={storage=storage,game=game,settings={startup={['mir-prefer-this-mod-for-competing-techs']={value=true}}},
            script={active_mods=mods},commands={},defines={inventory={lab_input=1},events={on_research_finished=1,on_tick=2}},
            helpers={table_to_json=function(v)logs[#logs+1]=clone(v);return 'record'end},log=function()end,require=require,
            pairs=pairs,ipairs=ipairs,next=next,type=type,tostring=tostring,math=math,error=error}
          env.script.on_init=function(fn)callbacks.init=fn end
          env.script.on_load=function(fn)callbacks.load=fn end
          env.script.on_configuration_changed=function(fn)callbacks.config=fn end
          env.script.on_event=function(id,fn)callbacks[id==1 and'finished'or'tick']=fn end
          env.commands.add_command=function(id,_,fn)commands_map[id]=fn end
          assert(loadfile(fixture_path..'/control.lua','t',env))()
          local function step()
            game.tick=game.tick+1;callbacks.tick()
            if not lab.disabled_by_script and f.current_research==main then
              local cost=main.research_unit_count
              local n=math.min(100,cost*(1-f.research_progress))
              if opponent~='no-consumption'then for _,name in ipairs(C.packs)do assert(inv.counts[name]>=n);inv.counts[name]=inv.counts[name]-n end end
              f.research_progress=f.research_progress+n/cost
              if f.research_progress>=1-1e-10 then
                local paid=count(main)+1
                if completed_shape then main.level=paid;main.researched=true else main.level=paid+1;main.researched=false end
                main.saved_progress=0;f.research_progress=0
                local phase=mods[C.mod]
                bonus(phase=='0.1.0'and 0 or phase=='0.2.0'and(paid-2)*.1 or(paid-2)*.1,paid*.1)
                if phase=='0.3.0'then offset('scrap-recycling',paid-2);for _,r in ipairs(C.singles)do offset(r,paid)end end
                callbacks.finished{research=main,by_script=opponent=='scripted'}
                table.remove(q,1);f.current_research=q[1]
              end
            end
          end
          local function until_phase(wanted)
            for _=1,10000 do if storage.mir_native_credit_vectors_fixture.phase==wanted then return end;step()end
            error('host loop did not reach '..wanted)
          end
          local function cold_read()
            local s=storage.mir_native_credit_vectors_fixture;game.tick=s.saved_tick
            local before=clone(storage);callbacks.load()
            if opponent=='bad-cold'then main.saved_progress=.123 end
            if opponent=='premature-cold'then game.tick=game.tick+1 end
            step()
            local function same(a,b)
              if type(a)~='table'then return a==b end
              for k,v in pairs(a)do if not same(v,b[k])then return false end end
              for k in pairs(b)do if a[k]==nil then return false end end
              return true
            end
            assert(same(before,storage),'cold mutated fixture storage')
          end
          callbacks.init()
          if opponent=='timeout'then storage.mir_native_credit_vectors_fixture.deadline=-1 end
          until_phase('f0-saved');cold_read();cold_read()
          if opponent=='unexpected-carrier'then callbacks.finished{research=f.technologies[C.carrier('scrap-recycling','positive')],by_script=true}end
          local function configure(version,old)
            callbacks.load();mods[C.mod]=version
            if version=='0.2.0'then local names=clone(C.singles);for _,n in ipairs(C.recipes)do names[#names+1]=n end;main.prototype.effects=effects(names,1);bonus(.2,.2)
            else main.prototype.effects={};main.prototype.hidden=true;main.prototype.enabled=false;bonus(-.2,0)end
            if opponent=='lost-pending'and version=='0.3.0'then f.research_progress=0 end
            callbacks.config{mod_changes={[C.mod]={old_version=old,new_version=version}}}
            if version=='0.2.0'then offset('scrap-recycling',-2);bonus(0,.2)
            else offset('scrap-recycling',1);for _,r in ipairs(C.singles)do offset(r,3)end;bonus(.1,.3)end
            -- A native MIR level setter may emit a scripted carrier event;
            -- it must remain separate from all ordinary earnings.
            callbacks.finished{research=f.technologies[C.carrier('scrap-recycling','positive')],by_script=true}
            if opponent=='public-flag-drift-config'then f.technologies[C.public].visible_when_disabled=true end
            if opponent=='sentinel-flag-drift-config'then f.technologies[C.sentinel].visible_when_disabled=true end
            if opponent=='retired-main-flag-drift'and version=='0.3.0'then main.enabled=false end
            if opponent=='wrong-last-recipe'then f.recipes['mir-vector-synthetic-scrap-95'].productivity_bonus=99 end
            if opponent=='wrong-negative'and version=='0.2.0'then offset('scrap-recycling',-1)end
            if opponent=='lost-source-bonus'then bonus(0,.1)end
            if opponent=='wrong-sign'then f.technologies[C.carrier('scrap-recycling','negative')].prototype.effects[97].change=.1 end
            step()
          end
          configure('0.2.0','0.1.0');until_phase('f1-negative-saved');cold_read();cold_read()
          commands_map['mir-native-credit-vectors']{parameter='continue'}
          if opponent=='public-flag-drift-ordinary'then f.technologies[C.public].visible_when_disabled=true end
          if opponent=='sentinel-flag-drift-ordinary'then f.technologies[C.sentinel].visible_when_disabled=true end
          until_phase('f1-pending-saved')
          if opponent=='duplicate'then callbacks.finished{research=main,by_script=false}end
          configure('0.3.0','0.2.0');until_phase('f2-positive-saved');cold_read();cold_read()
          commands_map['mir-native-credit-vectors']{parameter='continue'};until_phase('f2-final-saved');cold_read();cold_read()
          assert(storage.mir_native_credit_vectors_fixture.ordinary==4)
          assert(#saves==5)
        ''')

    def test_exact_metadata_and_original_upstream_excerpt(self):
        expected = {"f200": ("2.0.77", "5.0.20012"), "f210": ("2.1.23", "5.0.21012")}
        for target, (base, mir) in expected.items():
            for phase, version in (("f0", "0.1.0"), ("f1", "0.2.0"), ("f2", "0.3.0")):
                info = json.loads((FIXTURE / f"info-{phase}-{target}.json").read_text())
                self.assertEqual(version, info["version"])
                self.assertEqual([f"base = {base}", f"space-age = {base}", f"more-infinite-research = {mir}"], info["dependencies"])
        self.assertEqual("F9C5646B863A3FC3332A0616053913A713A778D563B5DB2B147EF5BE3F0B51B1",
                         hashlib.sha256((FIXTURE / "cerys-technology-first45.lua").read_bytes()).hexdigest().upper())
        self.assertEqual(45, len((FIXTURE / "cerys-technology-first45.lua").read_text().splitlines()))
        self.assertEqual("F7F28B8C7A1AF76B9874CA6D040E8B1EB6768FD1043106C9D315090EA96754E7",
                         hashlib.sha256((FIXTURE / "Cerys-LICENSE.txt").read_bytes()).hexdigest().upper())

    def test_actual_excerpt_and_synthetic_vector_masks_preserve_main_cost(self):
        for phase, size in (("0.1.0", 2), ("0.2.0", 99), ("0.3.0", 0)):
            self.setUp()
            self.lua.globals().case_phase = phase
            self.lua.execute(r'''
              local t=data_case(case_phase)
              assert(#t[C.public].effects==97)
              assert(#t[C.carrier('scrap-recycling','positive')].effects==97)
              assert(#t[C.carrier('scrap-recycling','negative')].effects==97)
              assert(#t['processing-unit-productivity'].effects==2)
              assert(t[C.main].unit.count_formula=='8000*2^(L-1)'and t[C.main].unit.time==60)
              assert(#data.raw.lab['mir-vector-lab'].inputs==4 and data.raw.lab['mir-vector-lab'].researching_speed==115200)
              assert(115200/3600==32)
              for level=1,4 do assert((8000*2^(level-1))%32==0)end
            ''')
            self.assertEqual(size, len(self.lua.globals().data.raw.technology[self.lua.globals().C.main].effects))

    def test_changed_authored_data_is_rejected_before_modeling_masks(self):
        for opponent in ("foreign-extra", "changed-time", "changed-formula", "missing-pack", "paid-mask-baseline"):
            with self.subTest(opponent=opponent):
                self.setUp()
                self.assertRaises(LuaError, self.lua.globals().data_case, "0.1.0", opponent)

    def test_shared_story_all_97_totals_pending_and_repeated_immutable_colds(self):
        for target in ("f200", "f210"):
            for shape in (False, True):
                with self.subTest(target=target, completed_shape=shape):
                    self.setUp()
                    self.story(target, completed_shape=shape)
                    hidden = self.lua.eval("last_storage.mir_native_credit_vectors_fixture.endpoint.prototypes['scrap-recycling-productivity'].effects[1].hidden")
                    self.assertIs(None if target == "f200" else False, hidden)

    def test_exact_engine_package_fixture_closure_opponents(self):
        for target, base, mir in (("f200", "2.0.77", "5.0.20012"), ("f210", "2.1.23", "5.0.21012")):
            active = {"base": base, "space-age": base, "quality": base, "elevated-rails": base,
                      "more-infinite-research": mir, "mir-fixture-native-credit-vectors": "0.1.0"}
            if target == "f210":
                active["recycler"] = base
            phase = self.lua.globals().C.phase
            self.assertEqual("F0", phase(self.lua.table_from(active)))
            mutations = [{"more-infinite-research": "5.0.21012" if target == "f200" else "5.0.20012"},
                         {"more-infinite-research": mir[:-2] + "11"}, {"more-infinite-research": mir[:-2] + "13"},
                         {"mir-fixture-native-credit-vectors": "0.4.0"}, {"quality": "2.1.24"}, {"unknown-mod": "1.0.0"}]
            for mutation in mutations:
                with self.subTest(target=target, mutation=mutation):
                    self.assertRaises(LuaError, phase, self.lua.table_from(active | mutation))

    def test_retained_private_main_must_preserve_its_actual_force_flag(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.setUp()
                self.assertRaisesRegex(LuaError, "MIR changed native pending/queue/unit/flags frame",
                                       self.story, target, "retired-main-flag-drift")

    def test_whole_science_quantum_rejects_fractional_rate_and_lab_modifiers(self):
        for target in ("f200", "f210"):
            for opponent in ("fractional-lab-rate", "nonzero-lab-speed", "nonzero-lab-productivity"):
                with self.subTest(target=target, opponent=opponent):
                    self.setUp()
                    message = "whole science quantum" if opponent == "fractional-lab-rate" else "lab modifiers"
                    self.assertRaisesRegex(LuaError, message, self.story, target, opponent)

    def test_scripted_unconsumed_duplicate_and_unpaid_recipe_opponents(self):
        opponents = {"scripted": "main completion was scripted", "no-consumption": "actual science consumption",
                     "duplicate": "main completion outside ordinary phase", "wrong-last-recipe": "native Scrap total",
                     "wrong-negative": "signed native carrier counts differ", "lost-pending": "pre-MIR paid/pending frame",
                     "unexpected-carrier": "carrier event outside reconciliation window", "timeout": "lab deadline exceeded",
                     "lost-source-bonus": "native LDS total", "wrong-sign": "complete vector differs"}
        for opponent, refusal in opponents.items():
            with self.subTest(opponent=opponent):
                self.setUp()
                self.assertRaisesRegex(LuaError, refusal, self.story, opponent=opponent)

    def test_wrong_tuples_and_changed_or_premature_cold_are_rejected(self):
        for opponent, refusal in {"wrong-engine": "exact engine/MIR/SA tuple", "wrong-mir": "exact engine/MIR/SA tuple",
                                  "bad-cold": "immutable endpoint frame", "premature-cold": "cold is not one update"}.items():
            with self.subTest(opponent=opponent):
                self.setUp()
                self.assertRaisesRegex(LuaError, refusal, self.story, opponent=opponent)

    def test_unchanged_public_reference_and_sentinel_flags_guard_configuration_and_ordinary_work(self):
        for target in ("f200", "f210"):
            for opponent in ("public-flag-drift-config", "sentinel-flag-drift-config",
                             "public-flag-drift-ordinary", "sentinel-flag-drift-ordinary"):
                with self.subTest(target=target, opponent=opponent):
                    self.setUp()
                    self.assertRaisesRegex(LuaError, "unchanged native reference/sentinel state", self.story,
                                           target=target, opponent=opponent)

    def test_real_complete_credit_module_accepts_the_three_recipe_story(self):
        # Real module + real saved-ledger lifecycle; native objects remain host
        # doubles. The engine fixture itself never imports this runtime.
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                family_fixture.LuaRuntime = LuaRuntime
                harness = family_fixture.NativeFamilyPaidCreditsTests()
                harness.setUp()
                lua = harness.lua
                lua.globals().case_target = target
                lua.execute(r'''
                  local family='research_low_density_structure'
                  GROUPS={[family]={{recipe='scrap-recycling',change=.1},{recipe='low-density-structure',change=.1},{recipe='casting-low-density-structure',change=.1}}}
                  local base=case_target=='f200'and'2.0.77'or'2.1.23'
                  reload_credits({base=base,['space-age']=base,['more-infinite-research']=case_target=='f200'and'5.0.20012'or'5.0.21012'},case_target)
                  game.forces={};storage={}
                  local f=make_collected_force(1,1,{[key(family,'low-density-structure')]=true,[key(family,'casting-low-density-structure')]=true},false)
                  local main=f.technologies['recipe-prod-'..family..'-1']
                  local recipes={'scrap-recycling','cerys-nuclear-scrap-recycling'}
                  for i=1,95 do recipes[#recipes+1]='mir-vector-synthetic-scrap-'..i end
                  local function vector(sign)local out={};for _,name in ipairs(recipes)do out[#out+1]={type='change-recipe-productivity',recipe=name,change=sign*fixture_effect(.1)}end;return out end
                  local p={name='scrap-recycling-productivity',level=1,max_level=4294967295,hidden=false,effects=vector(1)}
                  local public,public_state=make_technology(p.name,p,1,false,true);public.force=f
                  f.technologies[p.name]=public;f._states[p.name]=public_state;prototypes.technology[p.name]=p
                  local history=prototypes.get_history
                  prototypes.get_history=function(kind,name)if name==p.name then return{created='space-age'}end;return history(kind,name)end
                  local descriptors=native_credit_definitions.collected_descriptors(GROUPS)
                  local scrap
                  for _,d in ipairs(descriptors)do if d.recipe=='scrap-recycling'then
                    scrap=d;f.technologies[d.positive_id].prototype.effects=vector(1);f.technologies[d.negative_id].prototype.effects=vector(-1)
                  end end
                  f.research_queue={};f.research_progress=0
                  local function totals(scrap_units,lds_units)
                    local actual={};for _,name in ipairs(recipes)do actual[name]=0 end
                    actual['low-density-structure']=0;actual['casting-low-density-structure']=0
                    for _,state in pairs(f._states)do
                      local n=state.level-1+(state.researched and 1 or 0)
                      for _,e in ipairs(state.prototype.effects)do if actual[e.recipe]then actual[e.recipe]=actual[e.recipe]+n*e.change end end
                    end
                    for _,name in ipairs(recipes)do assert(math.abs(actual[name]-scrap_units*fixture_effect(.1))<1e-7,name)end
                    assert(math.abs(actual['low-density-structure']-lds_units*fixture_effect(.1))<1e-7)
                    assert(math.abs(actual['casting-low-density-structure']-lds_units*fixture_effect(.1))<1e-7)
                  end
                  native_credits.on_init();native_credits.on_configuration_changed({mod_changes={}})
                  local basis=record(f,family,'scrap-recycling').basis;local size=0;for _,v in pairs(basis)do assert(v==1);size=size+1 end;assert(size==97)
                  advance(f,main.name,3,false);totals(0,2)
                  for _,e in ipairs(vector(1))do main.prototype.effects[#main.prototype.effects+1]=e end
                  native_credits.on_configuration_changed({mod_changes={}});totals(0,2)
                  assert(record(f,family,'scrap-recycling').offset==-2)
                  advance(f,main.name,4,false);totals(1,3)
                  f.research_queue={main,f.technologies.foreign};f.research_progress=.234;main.saved_progress=.234
                  main.prototype.effects={};main.prototype.hidden=true
                  native_credits.on_configuration_changed({mod_changes={}});totals(1,3)
                  assert(f.research_progress==.234 and main.saved_progress==.234 and #f.research_queue==2)
                  advance(f,main.name,5,false)
                  native_credits.on_research_finished({research=main,by_script=false});totals(2,4)
                  assert(record(f,family,'scrap-recycling').offset==2)
                  native_credits.on_load();native_credits.on_configuration_changed({mod_changes={}});totals(2,4)
                ''')

    def test_actor_never_sets_native_rewards_or_partial_work(self):
        actor = (FIXTURE / "control.lua").read_text()
        self.assertIsNone(re.search(r"\.(?:level|researched|saved_progress|research_progress|productivity_bonus|active)\s*=(?!=)", actor))
        for forbidden in ("reset_technology_effects", 'require("runtime.'):
            self.assertNotIn(forbidden, actor)
        self.assertIn("p.research_recursive()", actor)
        self.assertIn("game.tick<=state.transition_tick", actor)
        self.assertIn("state.lab.disabled_by_script==true", actor)


class NativeCreditAllFiveFixtureControls(unittest.TestCase):
    """Controlled all-five vector shape; this is not reporter-mod gameplay."""

    OLD_VECTOR_BLOB = "C03A6AE2439B56E71BB84B9E3B20C8D317E3A821"

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_path = ALL_FIVE_FIXTURE.as_posix()
        self.lua.execute(r'''
          package.path=fixture_path.."/?.lua;"..package.path
          C=require("contract")
          function clone(v)if type(v)~="table"then return v end local out={};for k,x in pairs(v)do out[k]=clone(x)end;return out end
          table.deepcopy=clone
          function allfive_effect(recipe,change)return {type="change-recipe-productivity",recipe=recipe,change=change}end
          function allfive_pair(module,family,recipe,opponent)
            local extra,public_only=family.extra[recipe],family.public_only[recipe]
            local positive={allfive_effect(recipe,.1),allfive_effect(extra,.1)}
            local negative={allfive_effect(recipe,-.1),allfive_effect(extra,-.1)}
            local reference={allfive_effect(recipe,.1),allfive_effect(extra,.1),allfive_effect(public_only,.1)}
            if opponent=="public-in-positive"then positive[#positive+1]=allfive_effect(public_only,.1)end
            if opponent=="missing-negative"then table.remove(negative,#negative)end
            local vector,basis=module.pair(positive,negative,recipe,reference,.1,
              function(left,right)return math.abs(left-right)<0.0000001 end,
              function(left,right)return math.abs(left-right)<0.0000001 end)
            return vector~=nil,basis,positive,negative,reference
          end
          function allfive_data_case(target,phase,opponent)
            local tuple=C.targets[target]
            mods={base=tuple.base,["space-age"]=tuple.base,quality=tuple.base,["elevated-rails"]=tuple.base,
              ["more-infinite-research"]=tuple.mir15,[C.mod]=phase,[C.upstream]="0.1.0"}
            if tuple.recycler then mods.recycler=tuple.base end
            data={raw={technology={},recipe={},lab={lab={type="lab",name="lab"}},
              ["assembling-machine"]={["assembling-machine-1"]={type="assembling-machine",name="assembling-machine-1"}},["mod-data"]={}}}
            function data:extend(rows)for _,row in ipairs(rows)do self.raw[row.type]=self.raw[row.type]or{};assert(self.raw[row.type][row.name]==nil,"duplicate "..row.name);self.raw[row.type][row.name]=row end end
            local credits={}
            for _,family in ipairs(C.families)do
              local ingredients={};local prerequisites={}
              for _,name in ipairs(C.packs)do ingredients[#ingredients+1]={name,1};prerequisites[#prerequisites+1]=name end
              local main={name=C.main(family),hidden=true,enabled=false,effects={},prerequisites=prerequisites,
                unit={count_formula=C.formula,time=C.seconds,ingredients=ingredients}}
              credits[family.key]={}
              for _,recipe in ipairs(family.routes)do
                local reference_name=C.reference(family,recipe)
                local reference=data.raw.technology[reference_name]
                if not reference then
                  reference={name=reference_name,hidden=false,effects={}}
                  data.raw.technology[reference_name]=reference
                end
                reference.effects[#reference.effects+1]=allfive_effect(recipe,.1)
                credits[family.key][#credits[family.key]+1]={recipe=recipe,change=.1}
                data.raw.recipe[recipe]={type="recipe",name=recipe,enabled=false,ingredients={},results={}}
                for _,sign in ipairs({"positive","negative"})do
                  local change=sign=="positive"and .1 or-.1
                  local id=C.carrier(family,recipe,sign)
                  data.raw.technology[id]={name=id,hidden=true,enabled=false,effects={allfive_effect(recipe,change)}}
                end
              end
              data.raw.technology[main.name]=main
            end
            data.raw["mod-data"]["more-infinite-research-native-adoptions"]={data={credits=credits}}
            if opponent=="missing-public-route"then table.remove(data.raw.technology[C.families[1].reference].effects)end
            if opponent=="noncarrier-route"then data.raw.technology[C.carrier(C.families[2],C.families[2].routes[1],"positive")].hidden=false end
            dofile(fixture_path.."/data.lua");dofile(fixture_path.."/data-final-fixes.lua")
            return data.raw
          end
          function allfive_shared_actor_case(target,opponent)
            local tuple=C.targets[target];local callbacks,commands_map,saves={}, {}, {};storage={}
            local mods={base=tuple.base,["space-age"]=tuple.base,quality=tuple.base,["elevated-rails"]=tuple.base,
              ["more-infinite-research"]=tuple.mir15,[C.mod]="0.1.0",[C.upstream]="0.1.0"}
            if tuple.recycler then mods.recycler=tuple.base end
            local queue={};local force={technologies={},recipes={},laboratory_speed_modifier=0,laboratory_productivity_bonus=0}
            setmetatable(force,{__index=function(_,key)if key=="research_queue"then return queue end end,
              __newindex=function(value,key,row)if key=="research_queue"then queue=row;rawset(value,"current_research",row[1])else rawset(value,key,row)end end})
            local packs={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},
              {name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1}}
            local function technology(name,effects,hidden,enabled)
              local t={name=name,valid=true,level=1,researched=false,enabled=enabled,research_unit_ingredients=clone(packs),prerequisites={}}
              t.prototype={effects=effects,hidden=hidden,enabled=enabled};force.technologies[name]=t;return t
            end
            local function vector(names,sign)local out={};for _,name in ipairs(names)do out[#out+1]=allfive_effect(name,sign*.1)end;return out end
            local function family_shape(phase)
              for _,family in ipairs(C.families)do
                local names={};for _,recipe in ipairs(family.routes)do names[#names+1]=recipe;names[#names+1]=family.extra[recipe]end
                local main=force.technologies[C.main(family)]
                main.prototype.effects=phase=="F1"and vector(names,1)or{}
                main.prototype.hidden=phase=="F2";main.prototype.enabled=phase~="F2";main.enabled=phase~="F2"
                for _,recipe in ipairs(family.routes)do
                  local extra=family.extra[recipe]
                  local positive=force.technologies[C.carrier(family,recipe,"positive")]
                  local negative=force.technologies[C.carrier(family,recipe,"negative")]
                  positive.prototype.effects=vector({recipe,extra},1);negative.prototype.effects=vector({recipe,extra},-1)
                end
              end
            end
            for _,family in ipairs(C.families)do
              technology(C.main(family),{},false,true)
              local references={};for _,recipe in ipairs(family.routes)do
                local reference=C.reference(family,recipe);references[reference]=references[reference]or{}
                references[reference][#references[reference]+1]=recipe;references[reference][#references[reference]+1]=family.extra[recipe]
                references[reference][#references[reference]+1]=family.public_only[recipe]
                technology(C.carrier(family,recipe,"positive"),vector({recipe,family.extra[recipe]},1),true,false)
                technology(C.carrier(family,recipe,"negative"),vector({recipe,family.extra[recipe]},-1),true,false)
                force.recipes[recipe]={productivity_bonus=0};force.recipes[family.extra[recipe]]={productivity_bonus=0}
                force.recipes[family.public_only[recipe]]={productivity_bonus=0}
              end
              for reference,names in pairs(references)do technology(reference,vector(names,1),false,true)end
            end
            local function inventory()
              local value={counts={}}
              function value.insert(row)
                local accepted=row.count
                if opponent=="partial-input" and row.name==C.physical_input then accepted=math.max(0,row.count-1)end
                value.counts[row.name]=(value.counts[row.name]or 0)+accepted;return accepted
              end
              function value.get_item_count(name)return value.counts[name]or 0 end
              function value.get_contents()
                local rows={};for name,count in pairs(value.counts)do if count~=0 then rows[name]=count end end;return rows
              end
              function value.remove(row)
                local count=math.min(value.counts[row.name]or 0,row.count);value.counts[row.name]=(value.counts[row.name]or 0)-count;return count
              end
              function value.is_empty()for _,count in pairs(value.counts)do if count~=0 then return false end end;return true end
              return value
            end
            local lab_inventory=inventory()
            local lab={valid=true,disabled_by_script=false,name=C.lab,prototype={}}
            lab.prototype.get_researching_speed=function(quality)assert(quality=="normal");return 3600 end
            lab.get_inventory=function()return lab_inventory end
            local machines={}
            local function machine()
              local input,output=inventory(),inventory()
              local value={name=C.assembler,valid=true,productivity_bonus=0,crafting_progress=0,bonus_progress=0}
              function value.get_inventory(which)
                if which==2 then return input elseif which==3 then return output elseif which==4 then return nil end
              end
              function value.set_recipe(name)value.recipe={name=name}end
              function value.get_recipe()return value.recipe end
              machines[#machines+1]=value;return value
            end
            local game={tick=0,forces={player=force},surfaces={{}},server_save=function(name)saves[#saves+1]=name end}
            game.surfaces[1].create_entity=function(row)
              assert(row.force==force)
              if row.name==C.lab then return lab end
              assert(row.name==C.assembler);return machine()
            end
            local function advance_machines()
              for _,value in ipairs(machines)do
                local input,output=value.get_inventory(2),value.get_inventory(3)
                if value.recipe and input.get_item_count(C.physical_input)>0 then
                  if opponent=="ongoing"then value.crafting_progress=.5
                  else
                    local consumed=input.remove{name=C.physical_input,count=input.get_item_count(C.physical_input)}
                    local bonus=force.recipes[value.recipe.name].productivity_bonus
                    local made=consumed+(bonus>0 and 1 or 0)
                    if opponent=="wrong-output"then made=made-1 end
                    output.insert{name=C.physical_output,count=made};value.crafting_progress=0;value.bonus_progress=0
                    if opponent=="extra-output"then output.insert{name="stone",count=1}end
                  end
                end
              end
            end
            local env={storage=storage,game=game,script={active_mods=mods},remote={add_interface=function()end},commands={},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1,crafter_input=2,crafter_output=3,crafter_modules=4}},helpers={table_to_json=function()return "record"end},
              log=function()end,require=require,pairs=pairs,ipairs=ipairs,next=next,type=type,tostring=tostring,math=math,error=error}
            env.script.on_init=function(fn)callbacks.init=fn end;env.script.on_load=function(fn)callbacks.load=fn end
            env.script.on_configuration_changed=function(fn)callbacks.config=fn end
            env.script.on_event=function(id,fn)callbacks[id==1 and"finished"or"tick"]=fn end
            env.commands.add_command=function(name,_,fn)commands_map[name]=fn end
            package.preload["__mir-fixture-native-credit-vectors-allfive__/contract"]=function()return C end
            assert(loadfile(fixture_path.."/control.lua","t",env))();callbacks.init()
            local function engine_tick()
              game.tick=game.tick+1;advance_machines();callbacks.tick()
            end
            if opponent=="ongoing"then game.tick=storage[C.key].physical.deadline+1;callbacks.tick()
            else engine_tick()end
            local function cold_reads()
              for _=1,2 do game.tick=storage[C.key].saved_tick;callbacks.load();game.tick=game.tick+1;callbacks.tick()end
            end
            local function finish_cohort(phase)
              engine_tick()
              for _,family in ipairs(C.families)do
                local main=force.technologies[C.main(family)];main.level=main.level+1
                if phase=="F1"then
                  for _,recipe in ipairs(family.routes)do force.recipes[recipe].productivity_bonus=.1;force.recipes[family.extra[recipe]].productivity_bonus=.1 end
                end
                callbacks.finished{research=main,by_script=opponent=="scripted"}
              end
            end
            commands_map["mir-native-credit-vectors-allfive"]{player_index=nil,parameter="continue"};finish_cohort("F0");cold_reads()
            mods[C.mod]="0.2.0";family_shape("F1")
            for _,family in ipairs(C.families)do for _,recipe in ipairs(family.routes)do
              force.technologies[C.carrier(family,recipe,"negative")].level=2
            end end
            callbacks.config{mod_changes={[C.mod]={old_version="0.1.0",new_version="0.2.0"}}};cold_reads()
            commands_map["mir-native-credit-vectors-allfive"]{player_index=nil,parameter="continue"};finish_cohort("F1");engine_tick();cold_reads()
            mods[C.mod]="0.3.0";family_shape("F2")
            for _,family in ipairs(C.families)do for _,recipe in ipairs(family.routes)do
              force.technologies[C.carrier(family,recipe,"negative")].level=1
              force.technologies[C.carrier(family,recipe,"positive")].level=2
            end end
            callbacks.config{mod_changes={[C.mod]={old_version="0.2.0",new_version="0.3.0"}}}
            if opponent=="cold-string"then storage[C.key].endpoint.phase="wrong"end
            if opponent=="cold-boolean"then storage[C.key].endpoint.boolean_mutant=true end
            if opponent=="cold-physical"then storage[C.key].endpoint.physical.current[1].output=12 end
            cold_reads();assert(#saves==4 and saves[1]=="native-credit-allfive-f0" and saves[2]=="native-credit-allfive-f1-negative"
              and saves[3]=="native-credit-allfive-f1" and saves[4]=="native-credit-allfive-f2-positive",
              "save sequence "..#saves..":"..tostring(saves[1])..":"..tostring(saves[2])..":"..tostring(saves[3])..":"..tostring(saves[4]))
            return storage[C.key].endpoint
          end
        ''')
        old_blob = subprocess.check_output(
            ["git", "show", "v5.0.14:source/runtime/native_credit_vectors.lua"],
            cwd=ROOT, text=True)
        old_hash = subprocess.check_output(
            ["git", "rev-parse", "v5.0.14:source/runtime/native_credit_vectors.lua"],
            cwd=ROOT, text=True).strip().upper()
        self.assertEqual(self.OLD_VECTOR_BLOB, old_hash)
        self.old_vectors = self.lua.execute(old_blob)
        self.current_vectors = self.lua.execute(
            (ROOT / "source/runtime/native_credit_vectors.lua").read_text())

    def test_exact_14_15_fixture_tuples_and_synthetic_scope(self):
        expected = {
            "f200": ("2.0.77", "5.0.20015", "2.0", False),
            "f210": ("2.1.24", "5.0.21015", "2.1", True),
        }
        contract = (ALL_FIVE_FIXTURE / "contract.lua").read_text()
        actor = (ALL_FIVE_FIXTURE / "control.lua").read_text()
        self.assertIn("controlled synthetic fixture", (ALL_FIVE_FIXTURE / "README.md").read_text())
        self.assertIn("Scrap97", (ALL_FIVE_FIXTURE / "README.md").read_text())
        self.assertNotIn("require(\"runtime.", actor)
        self.assertNotRegex(actor, r"storage\.mir_native_credits")
        self.assertNotRegex(actor, r"\.productivity_bonus\s*=")
        self.assertNotRegex(actor, r"\.level\s*=")
        self.assertIn("game.server_save", actor)
        self.assertIn("script.on_load", actor)
        self.assertIn("event.by_script==false", actor)
        self.assertIn("synthetic_companion_production=true", actor)
        self.assertNotIn("Cerys", contract)
        for target, (base, mir, factorio, recycler) in expected.items():
            upstream = json.loads((ALL_FIVE_UPSTREAM / f"info-{target}.json").read_text())
            self.assertEqual("a-mir-fixture-native-credit-vectors-allfive-upstream", upstream["name"])
            self.assertEqual("0.1.0", upstream["version"])
            self.assertEqual(factorio, upstream["factorio_version"])
            self.assertIn(f"base = {base}", upstream["dependencies"])
            self.assertNotIn("more-infinite-research", "\n".join(upstream["dependencies"]))
            for phase, version in (("f0", "0.1.0"), ("f1", "0.2.0"), ("f2", "0.3.0")):
                info = json.loads((ALL_FIVE_FIXTURE / f"info-{phase}-{target}.json").read_text())
                self.assertEqual(factorio, info["factorio_version"])
                self.assertEqual(version, info["version"])
                dependencies = set(info["dependencies"])
                self.assertIn(f"base = {base}", dependencies)
                self.assertIn("a-mir-fixture-native-credit-vectors-allfive-upstream = 0.1.0", dependencies)
                self.assertIn(f"more-infinite-research >= {mir[:-2]}14", dependencies)
                self.assertEqual(recycler, any(row.startswith("recycler =") for row in dependencies))
                active = {"base": base, "space-age": base, "quality": base, "elevated-rails": base,
                          "more-infinite-research": mir, "mir-fixture-native-credit-vectors-allfive": version,
                          "a-mir-fixture-native-credit-vectors-allfive-upstream": "0.1.0"}
                if recycler:
                    active["recycler"] = base
                self.assertEqual(target, self.lua.globals().C.target(self.lua.table_from(active))[0])
                self.assertEqual(phase.upper(), self.lua.globals().C.phase(self.lua.table_from(active))[2])
                active["more-infinite-research"] = mir[:-2] + "14"
                self.assertEqual(target, self.lua.globals().C.target(self.lua.table_from(active))[0])
                with self.assertRaises(LuaError):
                    self.lua.globals().C.target(self.lua.table_from(active | {"unknown": "1.0.0"}))
                with self.assertRaises(LuaError):
                    self.lua.globals().C.target(self.lua.table_from(active | {"more-infinite-research": mir[:-2] + "13"}))
                with self.assertRaises(LuaError):
                    self.lua.globals().C.target(self.lua.table_from(active | {"more-infinite-research": mir[:-2] + "16"}))

    def test_data_fixture_expands_each_actual_carrier_but_only_public_references_get_public_only_recipes(self):
        for target in ("f200", "f210"):
            for phase, version in (("F0", "0.1.0"), ("F1", "0.2.0"), ("F2", "0.3.0")):
                raw = self.lua.globals().allfive_data_case(target, version, "")
                technologies, recipes = raw["technology"], raw["recipe"]
                assembler = raw["assembling-machine"][self.lua.globals().C.assembler]
                self.assertEqual("void", assembler["energy_source"]["type"])
                self.assertEqual(0, assembler["module_slots"])
                for family in self.lua.globals().C.families.values():
                    main = technologies[self.lua.globals().C.main(family)]
                    main_recipes = {effect["recipe"] for effect in main["effects"].values()}
                    self.assertEqual(phase == "F2", main["hidden"])
                    self.assertEqual(phase != "F2", main["enabled"])
                    for recipe in family["routes"].values():
                        reference = technologies[self.lua.globals().C.reference(family, recipe)]
                        public_only, extra = family["public_only"][recipe], family["extra"][recipe]
                        self.assertIsNotNone(recipes[public_only])
                        reference_recipes = {effect["recipe"] for effect in reference["effects"].values()}
                        self.assertIn(public_only, reference_recipes)
                        self.assertIn(extra, reference_recipes)
                        for synthetic in (extra, public_only):
                            row = recipes[synthetic]
                            self.assertTrue(row["enabled"])
                            self.assertTrue(row["allow_productivity"])
                            self.assertEqual("iron-gear-wheel", row["main_product"])
                            self.assertEqual(("iron-plate", 1), (row["ingredients"][1]["name"], row["ingredients"][1]["amount"]))
                            self.assertEqual(("iron-gear-wheel", 1), (row["results"][1]["name"], row["results"][1]["amount"]))
                        self.assertEqual(phase == "F1", recipe in main_recipes)
                        self.assertEqual(phase == "F1", extra in main_recipes)
                        for sign in ("positive", "negative"):
                            holder = technologies[self.lua.globals().C.carrier(family, recipe, sign)]
                            holder_recipes = {effect["recipe"] for effect in holder["effects"].values()}
                            self.assertEqual({recipe, extra}, holder_recipes)
                            self.assertNotIn(public_only, holder_recipes)
            with self.assertRaises(LuaError):
                self.lua.globals().allfive_data_case(target, "0.1.0", "missing-public-route")
            with self.assertRaises(LuaError):
                self.lua.globals().allfive_data_case(target, "0.1.0", "noncarrier-route")

    def test_real_mir_data_stage_has_the_private_empty_main_baseline_before_fixture_masks(self):
        """Use the current source data stage, not the local hand-built data double."""
        generator_fixture.LuaRuntime = LuaRuntime
        for target, base, mir in (("f200", "2.0.77", "5.0.20015"), ("f210", "2.1.24", "5.0.21015")):
            stage = generator_fixture.GeneratorTests()
            stage.setUp()
            stage.lua.globals().fixture_path = ALL_FIVE_FIXTURE.as_posix()
            stage.lua.globals().upstream_path = ALL_FIVE_UPSTREAM.as_posix()
            stage.lua.globals().case_target = target
            stage.lua.globals().case_base = base
            stage.lua.globals().case_mir = mir
            output = stage.lua.execute(r'''
              local target=require("platform.target")
              target.id,target.factorio_version,target.minimum_base=case_target,case_target=="f200"and"2.0"or"2.1",case_base
              target.distribution_version=case_target=="f200"and"5.0.20015"or"5.0.21015"
              target.cargo_research=case_target=="f210";target.recipe_probability=case_target=="f210"and"independent_probability"or"probability"
              target.productivity_ignores_stats=true;target.receiver_limits=case_target=="f210"
              package.path=fixture_path.."/?.lua;"..package.path
              package.preload["__mir-fixture-native-credit-vectors-allfive__/contract"]=function()return require("contract")end
              mods={base=case_base,["space-age"]=case_base,quality=case_base,["elevated-rails"]=case_base,
                ["a-mir-fixture-native-credit-vectors-allfive-upstream"]="0.1.0"}
              if case_target=="f210"then mods.recycler=case_base end
              package.loaded["research.settings"]=nil
              data=full_world(mods,true);data.raw.lab.lab={type="lab",name="lab",inputs={}}
              data.raw["assembling-machine"]={["assembling-machine-1"]={type="assembling-machine",name="assembling-machine-1"}}
              table.deepcopy=function(value)
                if type(value)~="table"then return value end
                local result={};for key,child in pairs(value)do result[key]=table.deepcopy(child)end;return result
              end
              function data:extend(rows)
                self.writes=self.writes+1
                for _,row in ipairs(rows)do
                  self.raw[row.type]=self.raw[row.type]or{}
                  assert(self.raw[row.type][row.name]==nil,"duplicate source row "..row.name)
                  self.raw[row.type][row.name]=row
                end
              end
              settings={startup=defaults()};helpers=nil;log=function()end
              dofile(upstream_path.."/data.lua")
              dofile(player_root.."/data.lua");dofile(data_final_path)
              local before={}
              for _,family in ipairs(require("__mir-fixture-native-credit-vectors-allfive__/contract").families)do
                local main=assert(data.raw.technology["recipe-prod-"..family.key.."-1"])
                assert(main.hidden==true and #main.effects==0,"source main was not private-empty: "..family.key)
                before[family.key]={hidden=main.hidden,effects=#main.effects}
              end
              mods["more-infinite-research"]=case_mir;mods["mir-fixture-native-credit-vectors-allfive"]="0.2.0"
              package.path=fixture_path.."/?.lua;"..player_root.."/?.lua;"..package.path
              dofile(fixture_path.."/data.lua");dofile(fixture_path.."/data-final-fixes.lua")
              local after={}
              for _,family in ipairs(require("contract").families)do
                local main=assert(data.raw.technology["recipe-prod-"..family.key.."-1"])
                after[family.key]={hidden=main.hidden,enabled=main.enabled,effects=#main.effects}
              end
              return {before=before,after=after,writes=data.writes}
            ''')
            for family in self.lua.globals().C.families.values():
                self.assertEqual({"hidden": True, "effects": 0}, dict(output["before"][family["key"]].items()))
                self.assertFalse(output["after"][family["key"]]["hidden"])
                self.assertTrue(output["after"][family["key"]]["enabled"])
                self.assertEqual(2 * len(family["routes"]), output["after"][family["key"]]["effects"])

    def test_old14_rejects_public_reference_superset_current_module_accepts_full_allfive_vectors(self):
        for target in ("f200", "f210"):
            for family in self.lua.globals().C.families.values():
                for recipe in family["routes"].values():
                    with self.subTest(target=target, family=family["key"], recipe=recipe):
                        # Exact published 5.0.14 rejects the named strict public
                        # superset. Current 5.0.15 accepts only its signed pair.
                        old_ok, _, _, _, _ = self.lua.globals().allfive_pair(self.old_vectors, family, recipe, "")
                        self.assertFalse(old_ok)
                        current_ok, basis, positive, negative, reference = self.lua.globals().allfive_pair(
                            self.current_vectors, family, recipe, "")
                        self.assertTrue(current_ok)
                        self.assertLess(len(positive), len(reference))
                        self.assertEqual(len(positive), len(negative))
                        self.assertIsNone(basis[family["public_only"][recipe]])
                        self.assertEqual(1, basis[recipe])
                        for opponent in ("public-in-positive", "missing-negative"):
                            with self.subTest(opponent=opponent):
                                accepted, _, _, _, _ = self.lua.globals().allfive_pair(
                                    self.current_vectors, family, recipe, opponent)
                                self.assertFalse(accepted)

    def test_shared_actor_runs_five_family_researches_then_signed_debit_credit_and_immutable_colds(self):
        for target in ("f200", "f210"):
            endpoint = self.lua.globals().allfive_shared_actor_case(target, "")
            self.assertEqual("f2-positive-saved", endpoint["phase"])
            self.assertTrue(all(endpoint["science"][pack] > 0 for pack in self.lua.globals().C.packs.values()))
            physical = endpoint["physical"]
            self.assertEqual("F1-complete", physical["phase"])
            self.assertEqual(6, len(list(physical["f0"].values())))
            self.assertEqual(6, len(list(physical["f1"].values())))
            for row in physical["f0"].values():
                self.assertEqual((10, 10, 0, 10), (row["inserted"], row["consumed"], row["input"], row["output"]))
                self.assertEqual({}, dict(row["input_contents"].items()))
                self.assertEqual({"iron-gear-wheel": 10}, dict(row["output_contents"].items()))
            for row in physical["f1"].values():
                expected = 11 if row["kind"] == "companion" else 10
                self.assertEqual((10, 10, 0, expected), (row["inserted"], row["consumed"], row["input"], row["output"]))
                self.assertEqual({}, dict(row["input_contents"].items()))
                self.assertEqual({"iron-gear-wheel": expected}, dict(row["output_contents"].items()))
                self.assertEqual(0, row["progress"])
                self.assertEqual(0, row["machine_productivity"])
                self.assertTrue(row["modules_empty"])
            self.assertEqual(5, len(list(endpoint["families"].values())))
            for row in endpoint["families"].values():
                self.assertEqual(2, row["main"])
                self.assertEqual({0}, {holder["negative"] for holder in row["holders"].values()})
                self.assertEqual({1}, {holder["positive"] for holder in row["holders"].values()})
                self.assertEqual({0, 0.1}, set(row["bonus"].values()))
                self.assertTrue(all(reference["level"] == 1 and not reference["researched"]
                                    for reference in row["references"].values()))
        for opponent, refusal in (("scripted", "ordinary family completion differs"),
                                  ("partial-input", "synthetic physical input was partial"),
                                  ("wrong-output", "synthetic physical output/state differs"),
                                  ("extra-output", "synthetic physical output/state differs"),
                                  ("ongoing", "synthetic physical cohort timed out"),
                                  ("cold-string", "immutable cold endpoint differs"),
                                  ("cold-boolean", "immutable cold endpoint differs"),
                                  ("cold-physical", "immutable cold endpoint differs")):
            with self.subTest(opponent=opponent):
                with self.assertRaisesRegex(LuaError, refusal):
                    self.lua.globals().allfive_shared_actor_case("f200", opponent)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

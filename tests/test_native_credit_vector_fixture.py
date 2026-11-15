"""Test-owned vector data/scenario controls, not native or reporter acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest

import test_native_family_paid_credits as family_fixture

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/native-credit-vectors"


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
            local function unit()return {count_formula='8000*2^(L-1)',time=60,
              ingredients={{'automation-science-pack',1},{'logistic-science-pack',1},{'chemical-science-pack',1},{'production-science-pack',1}}}end
            local rows={}
            for _,family in ipairs(C.families)do
              tech[family.main]={name=family.main,hidden=true,effects={},unit=unit()}
              rows[family.family]={}
              for _,route in ipairs(family.routes)do
                rows[family.family][#rows[family.family]+1]={recipe=route.recipe,change=.1}
                data.raw.recipe[route.recipe]={type='recipe',name=route.recipe}
                for _,sign in ipairs({'positive','negative'})do
                  tech[C.carrier_for(route.family,route.recipe,sign)]={hidden=true,enabled=false,
                    effects={{type='change-recipe-productivity',recipe=route.recipe,change=sign=='positive'and .1 or -.1}}}
                end
              end
            end
            for reference,names in pairs(C.base_reference_vectors)do
              tech[reference]={effects={}}
              for _,recipe in ipairs(names)do tech[reference].effects[#tech[reference].effects+1]={type='change-recipe-productivity',recipe=recipe,change=.1}end
            end
            data.raw['mod-data']['more-infinite-research-native-adoptions']={data={credits=rows}}
            if opponent=='foreign-extra'then rows.research_low_density_structure[4]={recipe='unknown',change=.1}end
            if opponent=='missing-family'then rows.research_steel=nil end
            if opponent=='missing-route'then table.remove(rows.research_rocket_fuel)end
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
          local function main_names(family,phase)
            local names={};if phase=='F2'then return names end
            for _,route in ipairs(family.routes)do
              if phase=='F1'or route.f0 then
                for _,name in ipairs(C.carrier_vector(route))do names[#names+1]=name end
              end
            end
            return names
          end
          local mains={}
          for _,family in ipairs(C.families)do mains[family.main]=tech(family.main,main_names(family,'F0'))end
          local main=mains[C.main]
          for _,reference in ipairs(C.reference_ids)do tech(reference,C.reference_vectors[reference])end
          local sentinel=tech(C.sentinel,{});sentinel.prototype.max_level=1
          for _,route in ipairs(C.routes)do
            for _,sign in ipairs({'positive','negative'})do
              tech(C.carrier_for(route.family,route.recipe,sign),C.carrier_vector(route),sign=='positive'and 1 or -1,true)
            end
          end
          local prerequisite=tech('production-science-pack',{});prerequisite.prototype.max_level=1
          prerequisite.research_recursive=function()prerequisite.researched=true;callbacks.finished{research=prerequisite,by_script=true}end
          for _,id in ipairs(C.main_ids)do mains[id].prerequisites[prerequisite.name]=prerequisite end
          local function count(t)return t.level-1+(t.researched and 1 or 0)end
          local function recompute_bonus()
            for _,name in ipairs(C.observed_recipes)do f.recipes[name]={productivity_bonus=0}end
            for _,t in pairs(f.technologies)do
              local n=count(t)
              for _,effect in ipairs(t.prototype.effects)do
                if f.recipes[effect.recipe]then f.recipes[effect.recipe].productivity_bonus=f.recipes[effect.recipe].productivity_bonus+n*effect.change end
              end
            end
          end
          local function set_carriers(phase)
            for _,route in ipairs(C.routes)do
              local positive,negative=0,0
              if phase=='F1'then
                if route.recipe=='scrap-recycling'then negative=2
                elseif not route.f0 then negative=1 end
              elseif phase=='F2'then
                if route.f0 then positive=count(mains[route.main])
                elseif route.recipe=='scrap-recycling'then positive=math.max(count(main)-2,0)end
              end
              f.technologies[C.carrier_for(route.family,route.recipe,'positive')].level=1+positive
              f.technologies[C.carrier_for(route.family,route.recipe,'negative')].level=1+negative
            end
            recompute_bonus()
          end
          recompute_bonus()
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
            local current=f.current_research
            if not lab.disabled_by_script and current and C.main_set[current.name]then
              local cost=current.research_unit_count
              local n=math.min(100,cost*(1-f.research_progress))
              if opponent~='no-consumption'then for _,name in ipairs(C.packs)do assert(inv.counts[name]>=n);inv.counts[name]=inv.counts[name]-n end end
              f.research_progress=f.research_progress+n/cost
              if f.research_progress>=1-1e-10 then
                local paid=count(current)+1
                if completed_shape then current.level=paid;current.researched=true else current.level=paid+1;current.researched=false end
                current.saved_progress=0;f.research_progress=0
                recompute_bonus()
                callbacks.finished{research=current,by_script=opponent=='scripted'}
                if mods[C.mod]=='0.3.0' then set_carriers('F2') end
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
            local phase=version=='0.2.0'and'F1'or'F2'
            for _,family in ipairs(C.families)do
              local t=mains[family.main]
              t.prototype.effects=effects(main_names(family,phase),1)
              t.prototype.hidden=phase=='F2';t.prototype.enabled=phase~='F2'
            end
            if opponent=='lost-pending'and version=='0.3.0'then f.research_progress=0 end
            callbacks.config{mod_changes={[C.mod]={old_version=old,new_version=version}}}
            set_carriers(phase)
            -- A native MIR level setter may emit a scripted carrier event;
            -- it must remain separate from all ordinary earnings.
            callbacks.finished{research=f.technologies[C.carrier('scrap-recycling','positive')],by_script=true}
            if opponent=='public-flag-drift-config'then f.technologies[C.public].visible_when_disabled=true end
            if opponent=='sentinel-flag-drift-config'then f.technologies[C.sentinel].visible_when_disabled=true end
            if opponent=='retired-main-flag-drift'and version=='0.3.0'then main.enabled=false end
            if opponent=='wrong-last-recipe'then f.recipes['mir-vector-synthetic-scrap-95'].productivity_bonus=99 end
            if opponent=='wrong-negative'and version=='0.2.0'then f.technologies[C.carrier('scrap-recycling','negative')].level=2;recompute_bonus()end
            if opponent=='lost-source-bonus'then f.recipes['low-density-structure'].productivity_bonus=0 end
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
          local state=storage.mir_native_credit_vectors_fixture
          for _,id in ipairs(C.main_ids)do
            local wanted=id==C.main and 4 or 1
            assert(state.ordinary_by_main[id]==wanted,'final ordinary schedule '..id)
          end
          local bonuses=state.endpoint.bonuses
          assert(bonuses['low-density-structure']==.4 and bonuses['casting-low-density-structure']==.4)
          assert(bonuses['plastic-bar']==.1 and bonuses['processing-unit']==.1
            and bonuses['cerys-processing-units-from-nitric-acid']==.1)
          assert(bonuses['rocket-fuel']==.1 and bonuses['steel-plate']==.1 and bonuses['scrap-recycling']==.2)
          assert(bonuses['bioplastic']==0 and bonuses['rocket-fuel-from-jelly']==0
            and bonuses['ammonia-rocket-fuel']==0 and bonuses['casting-steel']==0 and bonuses[C.noncarrier]==0)
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
        for phase in ("0.1.0", "0.2.0", "0.3.0"):
            self.setUp()
            self.lua.globals().case_phase = phase
            self.lua.execute(r'''
              local t=data_case(case_phase)
              assert(#t[C.public].effects==97)
              assert(#t[C.carrier('scrap-recycling','positive')].effects==97)
              assert(#t[C.carrier('scrap-recycling','negative')].effects==97)
              assert(#t['processing-unit-productivity'].effects==3)
              local routes=0
              for _,route in ipairs(C.routes)do
                routes=routes+1
                local vector=C.carrier_vector(route)
                assert(#t[C.carrier_for(route.family,route.recipe,'positive')].effects==#vector)
                assert(#t[C.carrier_for(route.family,route.recipe,'negative')].effects==#vector)
                for _,effect in ipairs(t[C.carrier_for(route.family,route.recipe,'positive')].effects)do
                  assert(effect.recipe~=C.noncarrier)
                end
              end
              assert(routes==11 and #C.reference_ids==6)
              for _,reference in ipairs(C.reference_ids)do assert(#t[reference].effects==#C.reference_vectors[reference])end
              local sizes=case_phase=='0.1.0'and {
                [C.main]=2,['recipe-prod-research_plastic-1']=1,['recipe-prod-research_processing_unit-1']=2,
                ['recipe-prod-research_rocket_fuel-1']=1,['recipe-prod-research_steel-1']=1,
              }or case_phase=='0.2.0'and {
                [C.main]=99,['recipe-prod-research_plastic-1']=2,['recipe-prod-research_processing_unit-1']=2,
                ['recipe-prod-research_rocket_fuel-1']=3,['recipe-prod-research_steel-1']=2,
              }or {
                [C.main]=0,['recipe-prod-research_plastic-1']=0,['recipe-prod-research_processing_unit-1']=0,
                ['recipe-prod-research_rocket_fuel-1']=0,['recipe-prod-research_steel-1']=0,
              }
              for _,id in ipairs(C.main_ids)do
                assert(#t[id].effects==sizes[id])
                assert(t[id].unit.count_formula=='8000*2^(L-1)'and t[id].unit.time==60)
              end
              assert(#data.raw.lab['mir-vector-lab'].inputs==4 and data.raw.lab['mir-vector-lab'].researching_speed==115200)
              assert(115200/3600==32)
              for level=1,4 do assert((8000*2^(level-1))%32==0)end
            ''')

    def test_changed_authored_data_is_rejected_before_modeling_masks(self):
        for opponent in ("foreign-extra", "missing-family", "missing-route", "changed-time", "changed-formula", "missing-pack", "paid-mask-baseline"):
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Complete native-vector controls; synthetic recipe worlds are not gameplay proof."""
import argparse
from pathlib import Path
import sys
import unittest

import test_native_family_paid_credits as family_fixture


ROOT = Path(__file__).resolve().parents[1]


class NativeCreditVectorTests(unittest.TestCase):
    def setUp(self):
        family_fixture.LuaRuntime = LuaRuntime
        case = family_fixture.NativeFamilyPaidCreditsTests()
        case.setUp()
        self.lua = case.lua
        self.lua.execute(r'''
          function vector_world(size, included, target, change, level, family, recipe, public_id)
            family=family or "research_low_density_structure";recipe=recipe or "scrap-recycling"
            GROUPS={[family]={{recipe=recipe,change=change or .1}}}
            reload_credits(nil,target or "f210");game.forces={};storage={}
            local f=make_collected_force(1,level or 1,{},not included)
            local d=native_credit_definitions.collected_descriptors(GROUPS)[1]
            public_id=public_id or "scrap-recycling-productivity"
            local reference={name=public_id,level=1,max_level=UINT32_MAX,hidden=false,effects={}}
            for i=1,size do
              reference.effects[i]={type="change-recipe-productivity",recipe=i==1 and recipe or"synthetic-recycling-"..i,
                change=fixture_effect(.1)}
            end
            local pub,pub_state=make_technology(public_id,reference,4,false,true)
            pub.force=f;f.technologies[public_id]=pub;f._states[public_id]=pub_state
            prototypes.technology[public_id]=reference
            local old_history=prototypes.get_history
            prototypes.get_history=function(kind,name)
              if name==public_id then return{created="space-age"}end
              return old_history(kind,name)
            end
            local function effect_vector(sign)
              local out={};for _,e in ipairs(reference.effects)do out[#out+1]={type=e.type,recipe=e.recipe,change=sign*fixture_effect(change or .1)}end;return out
            end
            f.technologies[d.positive_id].prototype.effects=effect_vector(1)
            f.technologies[d.negative_id].prototype.effects=effect_vector(-1)
            function vector_mask(value,private)
              f.technologies[d.main_id].prototype.effects=value and effect_vector(1)or{}
              f.technologies[d.main_id].prototype.hidden=private==true
            end
            vector_mask(included,not included)
            function vector_totals()
              local out={}
              for _,e in ipairs(reference.effects)do out[e.recipe]=0 end
              for _,state in pairs(f._states)do
                local completed=state.level-1+(state.researched and 1 or 0)
                for _,e in ipairs(state.prototype.effects)do
                  if out[e.recipe]~=nil then out[e.recipe]=out[e.recipe]+completed*e.change end
                end
              end
              return out
            end
            function check_vector_total(main_units)
              local total=vector_totals()
              for _,e in ipairs(reference.effects)do
                local expected=3*e.change+main_units*fixture_effect(change or .1)
                assert(math.abs(total[e.recipe]-expected)<1e-8,e.recipe.." total "..total[e.recipe].." expected "..expected)
              end
              assert(pub_state.writes.level==0 and pub_state.writes.enabled==0,"public reference was written")
              no_foreign_write(f)
            end
            function assert_no_vector_writes()
              assert(storage.mir_native_credits==nil,"refusal allocated ledger")
              for _,s in pairs(f._states)do assert(s.writes.level==0 and s.writes.enabled==0,"refusal wrote native fields")end
            end
            function earn_vector_main(count)
              for _=1,count do
                local t=f.technologies[d.main_id]
                advance(f,d.main_id,t.level+1,false)
                native_credits.on_research_finished{research=t,by_script=false}
              end
              native_credits.on_configuration_changed()
            end
            VF,VD,VR=f,d,reference
            return f,d,reference
          end
        ''')

    def test_each_family_reference_accepts_hidden_empty_enabled_main_and_preserves_state(self):
        # Independent public identities: none takes the scrap-recycling override.
        families = (
            ("research_low_density_structure", "low-density-structure", "low-density-structure-productivity"),
            ("research_plastic", "plastic-bar", "plastic-bar-productivity"),
            ("research_processing_unit", "processing-unit", "processing-unit-productivity"),
            ("research_rocket_fuel", "rocket-fuel", "rocket-fuel-productivity"),
            ("research_steel", "steel-plate", "steel-plate-productivity"),
        )
        # Exact independent native .1 representations; no implementation oracle.
        for target, native_change in (("f200", 0.10000000149011612), ("f210", 0.1)):
            for family, recipe, reference_id in families:
                with self.subTest(target=target, family=family):
                    self.lua.globals().case_target = target
                    self.lua.globals().case_family = family
                    self.lua.globals().case_recipe = recipe
                    self.lua.globals().case_reference = reference_id
                    self.lua.globals().expected_native = native_change
                    self.lua.execute(r'''
                      local f,d=vector_world(2,false,case_target,.1,1,case_family,case_recipe,case_reference)
                      local main=f.technologies[d.main_id];main.prototype.enabled=true
                      local foreign=f.technologies.foreign;foreign.saved_progress=.27
                      local queue={foreign};f.research_queue=queue;f.current_research=foreign
                      local function preserved_no_writes()
                        local row=record(f,case_family,case_recipe)
                        assert(row and row.private and not row.included and row.offset==0)
                        assert(row.basis[case_recipe]==1 and row.basis['synthetic-recycling-2']==1)
                        assert(main.prototype.hidden and #main.prototype.effects==0)
                        assert(main.prototype.enabled and main.enabled and main.level==1)
                        assert(f.research_queue==queue and queue[1]==foreign and f.current_research==foreign)
                        assert(f.research_progress==.42 and foreign.saved_progress==.27)
                        local totals=vector_totals()
                        close(totals[case_recipe],3*expected_native)
                        close(totals['synthetic-recycling-2'],3*expected_native)
                        for _,s in pairs(f._states)do
                          assert(s.writes.level==0 and s.writes.enabled==0,'valid baseline wrote native state')
                        end
                        no_foreign_write(f)
                      end
                      native_credits.on_init();preserved_no_writes()
                      local baseline=storage.mir_native_credits
                      native_credits.on_configuration_changed();preserved_no_writes()
                      -- Fresh Lua module with saved ledger; this is a host reload control.
                      local saved_game=game;game=nil;package.loaded['runtime.native_credits']=nil
                      native_credits=require('runtime.native_credits');native_credits.on_load();game=saved_game
                      assert(storage.mir_native_credits==baseline);preserved_no_writes()
                      native_credits.on_configuration_changed();preserved_no_writes()
                      vector_mask(true,false);native_credits.on_configuration_changed();earn_vector_main(2)
                      vector_mask(false,true);native_credits.on_configuration_changed()
                      assert(record(f,case_family,case_recipe).offset==2)
                      assert(main.level==3 and f.technologies[d.positive_id].level==3)
                      assert(f.technologies[d.negative_id].level==1)
                      local totals=vector_totals()
                      close(totals[case_recipe],5*expected_native)
                      close(totals['synthetic-recycling-2'],5*expected_native)
                      assert(f.research_queue==queue and f.current_research==foreign)
                      assert(f.research_progress==.42 and foreign.saved_progress==.27)
                      for _,id in ipairs({d.main_id,case_reference,'foreign'})do
                        assert(f._states[id].writes.level==0 and f._states[id].writes.enabled==0)
                      end
                      no_foreign_write(f)
                    ''')

    def test_processing_tail_and_reference_rejections_are_distinct_and_make_no_writes(self):
        cases = (
            ('n[2].change=.2', 'negative-component', (
                'rejection.role="negative"', 'rejection.component=2',
                'rejection.recipe="cerys-processing-units-from-nitric-acid"',
                'rejection.positive=0.1', 'rejection.negative=0.2')),
            ('prototypes.technology[r.name]=nil', 'reference-missing', ('reference.present=false',)),
            ('r.hidden=true', 'reference-hidden', ('reference.hidden=true',)),
            ('table.remove(r.effects)', 'reference-vector-count', ('reference.effects_count=1',)),
        )
        messages = []
        for opponent, reason, details in cases:
            with self.subTest(reason=reason):
                self.setUp()
                self.lua.globals().opponent = opponent
                message = self.lua.execute(r'''
                  local f,d,r=vector_world(2,false,'f210',.1,1,
                    'research_processing_unit','processing-unit','processing-unit-productivity')
                  f.technologies[d.main_id].prototype.enabled=true
                  local p=f.technologies[d.positive_id].prototype.effects
                  local n=f.technologies[d.negative_id].prototype.effects
                  for _,effects in ipairs({p,n,r.effects})do
                    effects[2].recipe='cerys-processing-units-from-nitric-acid'
                  end
                  assert(load('return function(f,d,r,p,n) '..opponent..' end'))()(f,d,r,p,n)
                  local ok,message=pcall(native_credits.on_init)
                  assert(not ok,'malformed vector admitted');assert_no_vector_writes()
                  -- Strip the call-site location; all old visible first components agree.
                  return tostring(message):match('(MIR native family credit.*)')
                ''')
                self.assertIsNotNone(message)
                messages.append(message)
                for unchanged in ('main.hidden=true', 'main.enabled=true', 'main.effects_count=0',
                                  'positive.effects_count=2', 'negative.effects_count=2',
                                  'positive.recipe="processing-unit"',
                                  'negative.recipe="processing-unit"'):
                    self.assertIn(unchanged, message)
                self.assertIn('reference.id="processing-unit-productivity"', message)
                self.assertIn('rejection.reason="' + reason + '"', message)
                for field in details:
                    self.assertIn(field, message)
                if reason == 'negative-component':
                    for field in ('reference.present=true', 'reference.hidden=false', 'reference.first=1',
                                  'reference.max=4294967295', 'reference.created="space-age"',
                                  'reference.effects_count=2'):
                        self.assertIn(field, message)
        # This fails on the previous error: four different causes printed one identical body.
        self.assertEqual(len(set(messages)), len(cases))

    def test_processing_recheck_failure_preserves_existing_ledger_and_foreign_progress(self):
        self.lua.execute(r'''
          local f,d=vector_world(2,false,'f210',.1,1,
            'research_processing_unit','processing-unit','processing-unit-productivity')
          local main=f.technologies[d.main_id];main.prototype.enabled=true
          local foreign=f.technologies.foreign;foreign.saved_progress=.27
          local queue={foreign};f.research_queue=queue;f.current_research=foreign
          native_credits.on_init()
          local ledger=storage.mir_native_credits;local row=record(f,d.family,d.recipe)
          local basis=row.basis
          f.technologies[d.negative_id].prototype.effects[2].change=.2
          local ok=pcall(native_credits.on_configuration_changed);assert(not ok)
          assert(storage.mir_native_credits==ledger and record(f,d.family,d.recipe)==row)
          assert(row.basis==basis and basis[d.recipe]==1 and basis['synthetic-recycling-2']==1)
          assert(row.private and not row.included and row.offset==0)
          assert(f.research_queue==queue and f.current_research==foreign)
          assert(f.research_progress==.42 and foreign.saved_progress==.27)
          for _,s in pairs(f._states)do assert(s.writes.level==0 and s.writes.enabled==0)end
          no_foreign_write(f)
        ''')

    def test_complete_97_recipe_totals_survive_both_inclusion_directions_and_repetition(self):
        for target in ("f200", "f210"):
            for change in (.1, .3):
                with self.subTest(target=target, change=change):
                    self.lua.globals().case_target = target
                    self.lua.globals().case_change = change
                    self.lua.execute(r'''
                      local f,d=vector_world(97,true,case_target,case_change)
                      native_credits.on_init();earn_vector_main(4);check_vector_total(4)
                      vector_mask(false,true);native_credits.on_configuration_changed()
                      check_vector_total(4);assert(f.technologies[d.positive_id].level==5)
                      local state=storage.mir_native_credits;local before=record(f,d.family,d.recipe).offset
                      for _=1,2 do native_credits.on_configuration_changed();native_credits.on_load();check_vector_total(4)end
                      assert(storage.mir_native_credits==state and record(f,d.family,d.recipe).offset==before)
                      vector_mask(true,false);native_credits.on_configuration_changed();check_vector_total(4)
                      assert(f.technologies[d.positive_id].level==1 and f.technologies[d.negative_id].level==1)
                    ''')

    def test_negative_credit_and_new_ordinary_main_completion_preserve_all_97_totals(self):
        self.lua.execute(r'''
          local f,d=vector_world(97,false)
          native_credits.on_init();earn_vector_main(4);check_vector_total(0)
          vector_mask(true,false);native_credits.on_configuration_changed();check_vector_total(0)
          assert(f.technologies[d.negative_id].level==5)
          advance(f,d.main_id,6,false);native_credits.on_research_finished{research=f.technologies[d.main_id],by_script=false}
          check_vector_total(1);native_credits.on_configuration_changed();check_vector_total(1)
        ''')

    def test_pending_private_ordinary_completion_pays_one_entire_vector_once(self):
        self.lua.execute(r'''
          local f,d=vector_world(97,true)
          native_credits.on_init();earn_vector_main(4);f.research_queue={f.technologies[d.main_id]}
          vector_mask(false,true);native_credits.on_configuration_changed();check_vector_total(4)
          assert(native_credits.needs_research_events())
          advance(f,d.main_id,6,false)
          native_credits.on_research_finished{research=f.technologies[d.main_id],by_script=false}
          check_vector_total(5);assert(not native_credits.needs_research_events())
          native_credits.on_research_finished{research=f.technologies[d.main_id],by_script=false};check_vector_total(5)
          native_credits.on_configuration_changed();check_vector_total(5)
        ''')

    def test_vector_order_is_semantic_by_recipe_not_effect_index(self):
        self.lua.execute(r'''
          local f,d,r=vector_world(97,true)
          for _,effects in ipairs({r.effects,f.technologies[d.positive_id].prototype.effects,f.technologies[d.main_id].prototype.effects})do
            for i=1,math.floor(#effects/2)do effects[i],effects[#effects-i+1]=effects[#effects-i+1],effects[i]end
          end
          native_credits.on_init();earn_vector_main(4);check_vector_total(4)
          vector_mask(false,true);native_credits.on_configuration_changed();check_vector_total(4)
        ''')

    def test_saved_paid_single_recipe_cannot_gain_new_alias_from_current_public_reference(self):
        for old_schema in (False, True):
            with self.subTest(old_schema_without_basis=old_schema):
                self.setUp()
                self.lua.globals().old_schema = old_schema
                self.lua.execute(r'''
                  local f,d,r=vector_world(1,true)
                  native_credits.on_init();earn_vector_main(4);check_vector_total(4)
                  local saved=storage.mir_native_credits;local row=record(f,d.family,d.recipe)
                  if old_schema then row.basis=nil end
                  r.effects[2]={type='change-recipe-productivity',recipe='new-unpaid-recycling',change=.1}
                  f.technologies[d.positive_id].prototype.effects[2]={type='change-recipe-productivity',recipe='new-unpaid-recycling',change=.1}
                  f.technologies[d.negative_id].prototype.effects[2]={type='change-recipe-productivity',recipe='new-unpaid-recycling',change=-.1}
                  vector_mask(false,true)
                  local ok,message=pcall(native_credits.on_configuration_changed)
                  assert(not ok and tostring(message):find('basis is unknown or changed',1,true))
                  assert(storage.mir_native_credits==saved and row.included and row.offset==0)
                  assert(row.basis==nil or row.basis['new-unpaid-recycling']==nil)
                  for _,s in pairs(f._states)do assert(s.writes.level==0 and s.writes.enabled==0)end
                  -- Desired MIR restoration is (.4,0), but both available
                  -- signed holders have basis(1,1): no scalar can express it.
                  assert(f.technologies[d.positive_id].level==1 and f.technologies[d.negative_id].level==1)
                ''')

    def test_zero_uninvested_old_record_can_learn_basis_but_invested_unknown_cannot(self):
        self.lua.execute(r'''
          local f,d,r=vector_world(1,false)
          native_credits.on_init();record(f,d.family,d.recipe).basis=nil
          r.effects[2]={type='change-recipe-productivity',recipe='new-unpaid-recycling',change=.1}
          f.technologies[d.positive_id].prototype.effects[2]={type='change-recipe-productivity',recipe='new-unpaid-recycling',change=.1}
          f.technologies[d.negative_id].prototype.effects[2]={type='change-recipe-productivity',recipe='new-unpaid-recycling',change=-.1}
          native_credits.on_configuration_changed()
          assert(record(f,d.family,d.recipe).basis['new-unpaid-recycling']==1)
        ''')
        for opponent in ('advance(f,d.main_id,2,false)',
                         'f.research_queue={f.technologies[d.main_id]}',
                         'f.technologies[d.main_id].saved_progress=.25'):
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute('local f,d=vector_world(97,false);' + opponent + r'''
                  local ok,message=pcall(native_credits.on_init)
                  assert(not ok and tostring(message):find('basis is unknown or changed',1,true))
                  assert_no_vector_writes()
                ''')

    def test_saved_basis_is_validated_and_pending_event_cannot_change_basis(self):
        self.lua.execute(r'''
          local f,d,r=vector_world(97,true)
          native_credits.on_init();earn_vector_main(4);f.research_queue={f.technologies[d.main_id]}
          vector_mask(false,true);native_credits.on_configuration_changed()
          local row=record(f,d.family,d.recipe);local old=row.offset
          row.basis['synthetic-recycling-97']=nil
          advance(f,d.main_id,6,false)
          local ok,message=pcall(native_credits.on_research_finished,{research=f.technologies[d.main_id],by_script=false})
          assert(not ok and tostring(message):find('basis changed',1,true)and row.offset==old)
        ''')
        for malformed in ('true','{}','{["scrap-recycling"]=2}',
                          '{["scrap-recycling"]=1,["bad"]=0/0}'):
            with self.subTest(basis=malformed):
                self.setUp()
                self.lua.execute('local f,d=vector_world(97,false);native_credits.on_init();'
                    'record(f,d.family,d.recipe).basis=' + malformed + r'''
                      local ok=pcall(native_credits.on_configuration_changed);assert(not ok)
                      for _,s in pairs(f._states)do assert(s.writes.level==0 and s.writes.enabled==0)end
                    ''')

    def test_weighted_public_basis_preserves_every_recipe_at_both_native_precisions(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.setUp()
                self.lua.globals().case_target = target
                self.lua.execute(r'''
                  local f,d,r=vector_world(97,true,case_target,.3)
                  r.effects[2].change=fixture_effect(.05)
                  f.technologies[d.positive_id].prototype.effects[2].change=fixture_effect(.15)
                  f.technologies[d.negative_id].prototype.effects[2].change=-fixture_effect(.15)
                  f.technologies[d.main_id].prototype.effects[2].change=fixture_effect(.15)
                  native_credits.on_init();earn_vector_main(4)
                  assert(record(f,d.family,d.recipe).basis['synthetic-recycling-2']==.5)
                  f.technologies[d.main_id].prototype.effects={};f.technologies[d.main_id].prototype.hidden=true
                  native_credits.on_configuration_changed()
                  local totals=vector_totals()
                  for _,e in ipairs(r.effects)do
                    local expected=3*e.change+4*fixture_effect(e.recipe=='synthetic-recycling-2'and .15 or .3)
                    assert(math.abs(totals[e.recipe]-expected)<1e-8,e.recipe)
                  end
                ''')

    def test_sparse_carrier_cannot_hide_extra_effect_behind_single_effect_fast_path(self):
        self.lua.execute(r'''
          local f,d=vector_world(1,false)
          f.technologies[d.positive_id].prototype.effects[97]={type='change-recipe-productivity',recipe='hidden-extra',change=.1}
          local ok=pcall(native_credits.on_init);assert(not ok);assert_no_vector_writes()
        ''')

    def test_incomplete_duplicate_scaled_or_nonproductivity_vectors_refuse_before_writes(self):
        opponents = [
            'table.remove(p)', 'table.remove(n)', 'table.remove(r.effects)',
            'p[97].recipe=p[1].recipe', 'n[97].recipe=n[1].recipe',
            'r.effects[97].recipe=r.effects[1].recipe', 'p[97].change=.2',
            'n[97].change=.1', 'p[1].change=.2', 'p[97].type="unlock-recipe"',
            'r.effects[97].type="unlock-recipe"', 'p[97].change=0/0',
            'p[97].change=math.huge', 'r.hidden=true',
            'prototypes.technology["scrap-recycling-productivity"]=nil',
            'prototypes.get_history=function()return{created="more-infinite-research"}end',
        ]
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute('local f,d,r=vector_world(97,true);local p=f.technologies[d.positive_id].prototype.effects;'
                    'local n=f.technologies[d.negative_id].prototype.effects;' + opponent + r'''
                      local ok=pcall(native_credits.on_init);assert(not ok,"bad vector admitted")
                      assert_no_vector_writes()
                    ''')

    def test_partial_or_wrong_main_vector_cannot_use_a_scalar_inclusion_flag(self):
        for opponent in ('table.remove(main)', 'main[97].change=.2', 'main[97].type="laboratory-speed"',
                         'main[97].recipe=main[1].recipe'):
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute('local f,d=vector_world(97,true);local main=f.technologies[d.main_id].prototype.effects;'
                    + opponent + 'local ok=pcall(native_credits.on_init);assert(not ok);assert_no_vector_writes()')



    def test_independent_families_with_identical_vectors_add_their_own_earned_units(self):
        self.lua.execute(r'''
          vector_world(97,true)
          local reference=VR
          GROUPS.research_steel={{recipe='scrap-recycling',change=.17}}
          reload_credits();storage={};game.forces={}
          local f=make_collected_force(1,1,{},false)
          prototypes.technology['scrap-recycling-productivity']=reference
          local old=prototypes.get_history
          prototypes.get_history=function(kind,name)if name=='scrap-recycling-productivity'then return{created='space-age'}end;return old(kind,name)end
          local descriptors=native_credit_definitions.collected_descriptors(GROUPS)
          local function effects(change)
            local out={};for _,e in ipairs(reference.effects)do out[#out+1]={type=e.type,recipe=e.recipe,change=change}end;return out
          end
          for _,d in ipairs(descriptors)do
            f.technologies[d.positive_id].prototype.effects=effects(d.change)
            f.technologies[d.negative_id].prototype.effects=effects(-d.change)
            f.technologies[d.main_id].prototype.effects=effects(d.change)
          end
          local public,ps=make_technology('scrap-recycling-productivity',reference,4,false,true)
          f.technologies[ps.name]=public;f._states[ps.name]=ps
          local function total()
            for _,reference_effect in ipairs(reference.effects)do
              local recipe=reference_effect.recipe
              local amount=0
              for _,state in pairs(f._states)do
                local paid=state.level-1+(state.researched and 1 or 0)
                for _,e in ipairs(state.prototype.effects)do if e.recipe==recipe then amount=amount+paid*e.change end end
              end
              close(amount,.3+2*.1+4*.17)
            end
            assert(ps.writes.level==0 and ps.writes.enabled==0)
          end
          native_credits.on_init()
          advance(f,descriptors[1].main_id,3,false);advance(f,descriptors[2].main_id,5,false)
          native_credits.on_configuration_changed();total()
          f.technologies[descriptors[2].main_id].prototype.effects={};f.technologies[descriptors[2].main_id].prototype.hidden=true
          native_credits.on_configuration_changed();total()
          f.technologies[descriptors[1].main_id].prototype.effects={};f.technologies[descriptors[1].main_id].prototype.hidden=true
          native_credits.on_configuration_changed();total()
          for _=1,2 do native_credits.on_load();native_credits.on_configuration_changed();total()end
        ''')

    def test_same_main_sum_all_or_none_is_exact_and_inconsistent_component_refuses(self):
        self.lua.execute(r'''
          vector_world(2,true);local reference=VR
          GROUPS={research_low_density_structure={{recipe='scrap-recycling',change=.1},{recipe='synthetic-recycling-2',change=.1}}}
          reload_credits();storage={};game.forces={}
          local f=make_collected_force(1,1,{},false);local ds=native_credit_definitions.collected_descriptors(GROUPS);local d=ds[1]
          prototypes.technology['scrap-recycling-productivity']=reference
          local old=prototypes.get_history
          prototypes.get_history=function(kind,name)if name=='scrap-recycling-productivity'then return{created='space-age'}end;return old(kind,name)end
          f.technologies[d.positive_id].prototype.effects={{type='change-recipe-productivity',recipe='scrap-recycling',change=.1},{type='change-recipe-productivity',recipe='synthetic-recycling-2',change=.1}}
          f.technologies[d.negative_id].prototype.effects={{type='change-recipe-productivity',recipe='scrap-recycling',change=-.1},{type='change-recipe-productivity',recipe='synthetic-recycling-2',change=-.1}}
          local main=f.technologies[d.main_id]
          main.prototype.effects={{type='change-recipe-productivity',recipe='scrap-recycling',change=.1},{type='change-recipe-productivity',recipe='synthetic-recycling-2',change=.2}}
          native_credits.on_init();advance(f,d.main_id,5,false);native_credits.on_configuration_changed()
          main.prototype.effects={};main.prototype.hidden=true;native_credits.on_configuration_changed()
          local totals={['scrap-recycling']=0,['synthetic-recycling-2']=0}
          for _,state in pairs(f._states)do
            for _,e in ipairs(state.prototype.effects)do if totals[e.recipe]then totals[e.recipe]=totals[e.recipe]+(state.level-1)*e.change end end
          end
          close(totals['scrap-recycling'],.4);close(totals['synthetic-recycling-2'],.8)
          local row=record(f,d.family,d.recipe);local prior=row.offset
          main.prototype.effects={{type='change-recipe-productivity',recipe='scrap-recycling',change=.1},{type='change-recipe-productivity',recipe='synthetic-recycling-2',change=.15}}
          local ok,message=pcall(native_credits.on_configuration_changed)
          assert(not ok and tostring(message):find('inconsistent expanded main',1,true)and row.offset==prior)
        ''')

    def test_quantized_zero_vector_keeps_exact_zero_negative_components(self):
        self.lua.execute(r'''
          local f,d=vector_world(2,false,'f200',.0001)
          for _,id in ipairs({d.positive_id,d.negative_id})do
            for _,e in ipairs(f.technologies[id].prototype.effects)do e.change=0 end
          end
          f.technologies[d.negative_id].prototype.effects[2].change=1e-9
          local ok=pcall(native_credits.on_init);assert(not ok);assert_no_vector_writes()
          f.technologies[d.negative_id].prototype.effects[2].change=0
          native_credits.on_init()
          assert(record(f,d.family,d.recipe).basis['synthetic-recycling-2']==1)
        ''')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--lua-runtime-dir', type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

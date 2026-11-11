"""Worker continuation identity guards; host doubles are not native save proof."""
import argparse
from pathlib import Path
import sys
import unittest

import test_bootstrap as bootstrap_fixture
from worker_storage_recovery_fixture import MINIMAL_NATIVE_FACTS, RECOVERY_WORLD

# Explicit parse-time runtime configuration for these native-fact doubles.
# Real bootstrap controls use the actual resolver; older-origin controls below
# also exercise an imported profile through that resolver.
WORKER_RUNTIME_CONFIGURATION = r'''
  package.loaded["runtime.configuration"]={streams={["worker-robots-storage"]={
    base_cost=200,growth_factor=1.5,linear_increment=0,research_time=60,
    effect_percent=1,max_level=0,enabled=true}}}
'''
RECOVERY_WORLD = WORKER_RUNTIME_CONFIGURATION + RECOVERY_WORLD


class WorkerStorageHistoryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (Path(__file__).resolve().parents[1] / "source").as_posix()
        self.lua.execute(WORKER_RUNTIME_CONFIGURATION)
        self.lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          storage={};script={active_mods={base="2.1.24",["more-infinite-research"]="5.0.21009"}}
          function route(last,owner)
            return {technology="worker-robots-storage-"..(last+1),level=last+1,
              predecessor="worker-robots-storage-4",owned=owner~=false,legacy_compatible=true,
              provider=owner==false and "foreign-infinite" or nil,
              finite={{name="worker-robots-storage-4",max_level=last,provider="foreign-finite"}}}
          end
          function upgrade(old,changed)
            return {mod_startup_settings_changed=changed==true,
              mod_changes={["more-infinite-research"]={old_version=old,new_version="5.0.21009"}}}
          end
          history=require("runtime.worker_robot_storage")
        ''')
        self.lua.execute(MINIMAL_NATIVE_FACTS)
        self.lua.execute('game={forces={}};install_worker_recovery_facts()')

    def test_fresh_route_is_detached_and_two_cold_loads_are_read_only(self):
        self.lua.execute(r'''
          local selected=route(9);history.on_init(selected)
          local saved=storage.mir_worker_storage_route
          assert(saved.route~=selected and saved.route.finite~=selected.finite)
          selected.finite[1].provider="changed-caller"
          assert(saved.route.finite[1].provider=="foreign-finite")
          for i=1,2 do
            package.loaded["runtime.worker_robot_storage"]=nil
            history=require("runtime.worker_robot_storage");history.on_load(route(9))
            assert(storage.mir_worker_storage_route==saved)
          end
          assert(history.preflight(upgrade("5.0.21008",true),route(9))==nil)
          assert(storage.mir_worker_storage_route==saved)
        ''')

    def test_new_mir_install_has_no_marker_write_until_all_preflights_pass(self):
        self.lua.execute(r'''
          local plan=history.preflight(upgrade(nil),route(4))
          assert(storage.mir_worker_storage_route==nil and plan.route.technology=="worker-robots-storage-5")
          history.apply(plan);assert(storage.mir_worker_storage_route==plan)
        ''')

    def test_changed_endpoint_creator_ownership_and_removal_refuse_without_writes(self):
        self.lua.execute(r'''
          history.on_init(route(9));local saved=storage.mir_worker_storage_route
          for _,opponent in ipairs({"endpoint","finite-creator","infinite-owner","removal"}) do
            local candidate=route(opponent=="endpoint" and 10 or 9,opponent~="infinite-owner")
            if opponent=="finite-creator" then candidate.finite[1].provider="another-mod" end
            if opponent=="removal" then candidate=nil end
            local ok,message=pcall(history.preflight,upgrade("5.0.21008"),candidate)
            assert(not ok and tostring(message):find("MIR-WORKER-HISTORY",1,true),opponent)
            assert(storage.mir_worker_storage_route==saved)
            -- on_load cannot inspect native force state or decide whether
            -- this is an ordinary cold versus a configuration transition.
            assert(pcall(history.on_load,candidate),"read-only load refused "..opponent)
            assert(storage.mir_worker_storage_route==saved)
          end
        ''')

    def test_unknown_prior_save_is_not_inferred_from_current_prototype_or_version(self):
        self.lua.execute(r'''
          for _,old in ipairs({"5.0.21008","4.7.21003","4.7.20003"}) do
            local ok,message=pcall(history.preflight,upgrade(old),route(4))
            assert(not ok and tostring(message):find("previous continuation ownership is unknown",1,true))
            assert(storage.mir_worker_storage_route==nil)
          end
          assert(history.preflight(upgrade("5.0.21008"),nil)==nil)
        ''')

    def test_exact_transported_legacy_emission_is_admitted_but_lookalikes_are_not(self):
        self.lua.execute(r'''
          local selected=route(9)
          local row={technology=selected.technology,setting="mir-max-level-worker-robots-storage",
            source="base-continuation",operation="emit_base_extension",policy_transport="transported-v3",
            ownership_kind="transported-v3",legacy=false,native_finite_stage=false,
            binding_fingerprint="mir32-12345678",selected="infinite"}
          storage.mir={maximum_level_control={policy_version=3,managed_technologies={[selected.technology]=row}}}
          local plan=history.preflight(upgrade("4.7.21003"),selected)
          assert(plan and plan.route.technology==selected.technology and storage.mir_worker_storage_route==nil)
          for _,field in ipairs({"operation","source","ownership_kind","policy_transport","binding_fingerprint"}) do
            local old=row[field];row[field]="settings-derived"
            assert(not pcall(history.preflight,upgrade("4.7.21003"),selected),field)
            row[field]=old
          end
          assert(not pcall(history.preflight,upgrade("4.7.21003",true),selected))
          local event=upgrade("4.7.21003");event.mod_changes.foreign={old_version="1.0",new_version="1.1"}
          assert(not pcall(history.preflight,event,selected))
          assert(not pcall(history.preflight,upgrade("4.7.21003"),route(9,false)))
          selected.legacy_compatible=false
          assert(not pcall(history.preflight,upgrade("4.7.21003"),selected))
          assert(storage.mir_worker_storage_route==nil)
        ''')

    def test_malformed_saved_chain_is_rejected(self):
        self.lua.execute(r'''
          for _,opponent in ipairs({"schema","level","gap","provider","endpoint","extra","sparse"}) do
            local selected=route(9);local saved={schema=1,route=selected}
            if opponent=="schema" then saved.schema=2 end
            if opponent=="level" then selected.level=0 end
            if opponent=="gap" then selected.finite[1].name="worker-robots-storage-5" end
            if opponent=="provider" then selected.finite[1].provider="more-infinite-research" end
            if opponent=="endpoint" then selected.predecessor="worker-robots-storage-9" end
            if opponent=="extra" then selected.finite.foreign="ignored" end
            if opponent=="sparse" then selected.finite[3]=selected.finite[1] end
            storage.mir_worker_storage_route=saved
            assert(not pcall(history.on_load,route(9)),opponent)
            assert(storage.mir_worker_storage_route==saved)
          end
        ''')

    def test_bootstrap_refuses_before_lifecycle_or_other_credit_writes(self):
        bootstrap_fixture.LuaRuntime = LuaRuntime
        fixture = bootstrap_fixture.BootstrapTests()
        fixture.setUp()
        fixture.lua.execute(r'''
          install_modules(true,false,false,true)
          install_runtime(nil,{base="2.1.24",["more-infinite-research"]="5.0.21009"})
          local catalogue=require("runtime.catalogue")
          catalogue.worker_storage_route=function()
            return {technology="worker-robots-storage-5",level=5,predecessor="worker-robots-storage-4",
              owned=true,finite={{name="worker-robots-storage-4",max_level=4,provider="planet-provider"}}}
          end
          load_control()
          local ok,message=pcall(handlers.configuration,{mod_startup_settings_changed=false,
            mod_changes={["more-infinite-research"]={old_version="5.0.21008",new_version="5.0.21009"}}})
          assert(not ok and tostring(message):find("MIR-WORKER-HISTORY",1,true),tostring(message))
          assert(#configuration_order==0 and lifecycle_calls.configuration==nil)
          assert(storage.mir_worker_storage_route==nil)
        ''')


class WorkerStorageRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (Path(__file__).resolve().parents[1] / "source").as_posix()
        self.lua.execute('package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""')
        self.lua.execute(RECOVERY_WORLD)

    def sdk_world(self, target):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = self.lua.globals().player_root
        lua.globals().declared_target = target
        lua.execute('package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath="";'
                    'package.loaded["platform.target"]={id=declared_target,minimum_base=declared_target=="f200"and"2.0.77"or"2.1.23"}')
        lua.execute(RECOVERY_WORLD)
        return lua

    def test_declared_package_target_uses_its_sdk_effect_shape_on_empty_init(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.sdk_world(target)
                lua.execute(r'''
                  local effect=prototypes.technology[ID].effects[1]
                  assert(declared_target=="f200" and effect.hidden==nil
                    or declared_target=="f210" and effect.hidden==false)
                  -- The world hint remains2.1; the declared package target
                  -- alone selects its supported SDK effect representation.
                  assert(script.active_mods.base=="2.1.23")
                  history.on_init(nil)
                  assert(writes==0 and storage.mir_worker_storage_route.current.kind=="default")
                  assert(declared_target=="f200" and effect.hidden==nil
                    or declared_target=="f210" and effect.hidden==false)
                ''')

    def test_target_specific_hidden_opponents_refuse_before_init_writes(self):
        for target, expressions in (("f200", ('"false"', '0', '{}')),
                                    ("f210", ('nil', '"false"', '0', '{}'))):
            for expression in expressions:
                with self.subTest(target=target, expression=expression):
                    lua = self.sdk_world(target)
                    lua.execute('prototypes.technology[ID].effects[1].hidden='+expression+r'''
                      writes=0;local ok,message=pcall(history.on_init,nil)
                      assert(not ok and tostring(message):find("effect contract is invalid",1,true))
                      assert(writes==0 and storage.mir_worker_storage_route==nil)
                    ''')

    def test_f200_absent_hidden_normalizes_without_writing_native_fields(self):
        lua = self.sdk_world("f200")
        lua.execute(r'''
          local recovery=require("research.worker_storage_recovery")
          local prototype=prototypes.technology[ID];local effect=prototype.effects[1]
          local absent=recovery.fingerprint(prototype);assert(effect.hidden==nil and writes==0)
          effect.hidden=false;assert(recovery.fingerprint(prototype)==absent)
          effect.hidden=true;assert(recovery.fingerprint(prototype)~=absent)
        ''')

    def test_prepare_moves_actual_counts_complete_queue_and_partial_frames_once(self):
        self.lua.execute(r'''
          seed();local a,b,c=player.worker_robots_storage_bonus,uninvested.worker_robots_storage_bonus,suspended.worker_robots_storage_bonus
          assert(history.prepare(nil));local state=storage.mir_worker_storage_route
          assert(state.schema==2 and state.kind=="prepared" and state.cap==0)
          assert(player.worker_robots_storage_bonus==a and uninvested.worker_robots_storage_bonus==b and suspended.worker_robots_storage_bonus==c)
          assert(player.technologies[ID].level==8 and not player.technologies[ID].researched)
          assert(player.current_research.name==ID and player.research_progress==.375 and player.research_queue[2].name==OTHER)
          assert(suspended.current_research.name==OTHER and suspended.research_progress==.42)
          assert(suspended.research_queue[2].name==ID and suspended.technologies[ID].saved_progress==.27)
          for _,f in pairs(game.forces)do local t=f.technologies[CANONICAL];assert(t.level==4 and not t.researched and t.saved_progress==0)end
          assert(not uninvested.technologies[ID].enabled and not uninvested.technologies[CANONICAL].enabled)
          assert(state.forces[1].limit==8 and state.forces[3].limit==7, "partial belongs to first queued level")
          writes=0;assert(history.prepare(nil)==false and writes==0 and storage.mir_worker_storage_route==state)
        ''')

    def test_researched_true_counts_are_normalized_by_native_level_setter(self):
        self.lua.execute(r'''
          player.technologies[CANONICAL].level=8;player.technologies[CANONICAL].researched=true
          player.technologies[CANONICAL].enabled=false
          local bonus=player.worker_robots_storage_bonus
          history.prepare(nil)
          assert(player.technologies[ID].level==9 and not player.technologies[ID].researched)
          assert(not player.technologies[ID].enabled and not player.technologies[CANONICAL].enabled)
          assert(player.worker_robots_storage_bonus==bonus)
        ''')

    def test_all_force_contract_custody_and_frame_opponents_refuse_before_writes(self):
        opponents = [
            'creators[CANONICAL]="foreign"', 'creators[ID]="foreign"',
            'prototypes.technology[ID].effects[1].modifier=2',
            'prototypes.technology[ID].effects[1].hidden=true',
            'prototypes.technology[ID].effects[1].hidden=nil',
            'prototypes.technology[ID].ignore_tech_cost_multiplier=true',
            'prototypes.technology[ID].ignore_tech_cost_multiplier=nil',
            'prototypes.technology[ID].research_unit_count_formula="101*2^(L-4)"',
            'prototypes.technology[ID].research_unit_energy=1801',
            'prototypes.technology[ID].research_unit_ingredients[1].amount=2',
            'prototypes.technology[ID].prerequisites.extra={name="extra"}',
            'suspended.technologies[ID].level=5',
            'suspended.technologies[OTHER].enabled=false',
            'suspended.technologies[CANONICAL].saved_progress=1',
            'prototypes.technology[ID]=nil', 'prototypes=nil',
        ]
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute('seed();'+opponent+';writes=0;local ok=pcall(history.prepare,nil);assert(not ok and writes==0 and storage.mir_worker_storage_route==nil)')

    def test_old_nil_is_not_a_default_marker_and_clamped_fields_prove_no_counts(self):
        self.lua.execute(r'''
          seed();add_provider(5)
          for _,f in pairs(game.forces)do f.technologies[CANONICAL].level=4;f.technologies[CANONICAL].researched=true;f.research_queue={OTHER};f.research_progress=0 end
          writes=0
          local ok,message=pcall(history.preflight,{mod_startup_settings_changed=false,
            mod_changes={['more-infinite-research']={old_version="5.0.21010",new_version="5.0.21011"},provider={new_version="1.0"}}},provider_route(5))
          assert(not ok and tostring(message):find("unknown",1,true) and writes==0 and storage.mir_worker_storage_route==nil)
        ''')

    def test_new_world_marker_is_explicit_and_both_readonly_loads_defer_route_decision(self):
        self.lua.execute(r'''
          history.on_init(nil);local state=storage.mir_worker_storage_route
          assert(state.schema==2 and state.kind=="route" and state.current.kind=="default")
          writes=0;game=setmetatable({}, {__index=function()error("load read game")end})
          for i=1,2 do history.on_load(provider_route(5));assert(storage.mir_worker_storage_route==state and writes==0)end
        ''')

    def test_unknown_history_reports_actual_route_and_event_without_default_inference(self):
        self.lua.execute(r'''
          seed();add_provider(5);writes=0
          local ok,message=pcall(history.preflight,{mod_startup_settings_changed=false,
            mod_changes={['more-infinite-research']={old_version="5.0.21010",new_version="5.0.21012"},
              ['planet-ferrum']={new_version="0.1.5"}}},provider_route(5))
          assert(not ok and writes==0 and storage.mir_worker_storage_route==nil)
          assert(message:find("technology=worker-robots-storage-6",1,true))
          assert(message:find("previous_mir=5.0.21010",1,true) and message:find("new_mir=5.0.21012",1,true))
          assert(message:find("startup_changed=false",1,true) and message:find("saved_route=absent",1,true))
          assert(message:find("current_route=finite",1,true) and message:find("planet-ferrum=unknown->0.1.5",1,true))
          assert(not message:find("technology=default",1,true))
        ''')

    def test_known_secretas_upgrade_records_route_and_survives_the_next_upgrade(self):
        for prefix, base in (("210", "2.1.23"), ("200", "2.0.77")):
            for patch in ("09", "10", "11"):
                with self.subTest(prefix=prefix, patch=patch):
                    self.setUp()
                    self.lua = self.sdk_world("f200" if prefix == "200" else "f210")
                    self.lua.globals().old_version = "5.0." + prefix + patch
                    self.lua.globals().new_version = "5.0." + prefix + "12"
                    self.lua.globals().later_version = "5.0." + prefix + "13"
                    self.lua.globals().engine_version = base
                    self.lua.execute(r'''
                      script.active_mods={base=engine_version,secretas="1.0.38",['more-infinite-research']=new_version}
                      add_provider(8);local route=provider_route(8);writes=0
                      local plan=history.preflight({mod_startup_settings_changed=false,mod_changes={
                        ['more-infinite-research']={old_version=old_version,new_version=new_version}}},route)
                      assert(storage.mir_worker_storage_route==nil and writes==0,"preflight wrote state")
                      history.apply(plan)
                      local saved=storage.mir_worker_storage_route
                      assert(saved and saved.schema==1 and saved.route.technology=='worker-robots-storage-9',
                        'accepted legacy route was never recorded for the next upgrade')
                      assert(saved.route~=route and saved.route.finite~=route.finite,"route aliases candidate metadata")
                      assert(writes==0,"recording a known unchanged route changed native state")
                      for _=1,2 do
                        package.loaded['runtime.worker_robot_storage']=nil;history=require('runtime.worker_robot_storage')
                        history.on_load();assert(storage.mir_worker_storage_route==saved and writes==0)
                      end
                      script.active_mods['more-infinite-research']=later_version
                      local next_plan=history.preflight({mod_startup_settings_changed=false,mod_changes={
                        ['more-infinite-research']={old_version=new_version,new_version=later_version}}},provider_route(8))
                      history.apply(next_plan)
                      assert(storage.mir_worker_storage_route==saved and writes==0,'next unchanged upgrade refused or rewrote state')
                    ''')

    def test_new_known_secretas_readers_require_old_profile_provenance_before_writes(self):
        for patch in ("09", "11"):
            for opponent in ("startup", "unknown-startup", "base-change", "added", "removed", "updated",
                             "missing-secretas", "foreign-tail", "endpoint", "wrong-new", "wrong-edition", "wrong-target", "unknown-origin"):
                with self.subTest(patch=patch, opponent=opponent):
                    self.setUp()
                    self.lua.globals().old_version = "5.0.210" + patch
                    self.lua.globals().opponent = opponent
                    self.lua.execute(r'''
                      script.active_mods={base="2.1.23",secretas="1.0.38",['more-infinite-research']='5.0.21012'}
                      add_provider(8);local route=provider_route(8)
                      local e={mod_startup_settings_changed=false,mod_changes={
                        ['more-infinite-research']={old_version=old_version,new_version='5.0.21012'}}}
                      if opponent=='startup' then e.mod_startup_settings_changed=true end
                      if opponent=='unknown-startup' then e.mod_startup_settings_changed=nil end
                      if opponent=='base-change' then e.mod_changes.base={old_version='2.1.22',new_version='2.1.23'} end
                      if opponent=='added' then e.mod_changes.secretas={new_version='1.0.38'} end
                      if opponent=='removed' then e.mod_changes.old_provider={old_version='1.0.0'} end
                      if opponent=='updated' then e.mod_changes.other={old_version='1.0.0',new_version='1.1.0'} end
                      if opponent=='missing-secretas' then script.active_mods.secretas=nil end
                      if opponent=='foreign-tail' then route.owned=false;route.provider='foreign' end
                      if opponent=='endpoint' then route=provider_route(5) end
                      if opponent=='wrong-new' then e.mod_changes['more-infinite-research'].new_version='5.0.21013' end
                      if opponent=='wrong-edition' then
                        script.active_mods['more-infinite-research']='5.0.20012'
                        e.mod_changes['more-infinite-research'].new_version='5.0.20012'
                      end
                      if opponent=='wrong-target' then require('platform.target').id='f200' end
                      if opponent=='unknown-origin' then e.mod_changes['more-infinite-research'].old_version='5.0.21008' end
                      writes=0;local ok=pcall(history.preflight,e,route)
                      assert(not ok and writes==0 and storage.mir_worker_storage_route==nil,'unproven old route admitted')
                    ''')

    def test_explicit_unprepared_route_reports_surviving_marker_without_recovery_writes(self):
        self.lua.execute(r'''
          history.on_init(nil);local saved=storage.mir_worker_storage_route;seed();add_provider(8);writes=0
          local ok,message=pcall(history.preflight,{mod_startup_settings_changed=true,
            mod_changes={secretas={new_version="1.0.38"}}},provider_route(8))
          assert(not ok and writes==0 and storage.mir_worker_storage_route==saved)
          assert(message:find("unprepared worker route changed",1,true))
          assert(message:find("technology=worker-robots-storage-9",1,true))
          assert(message:find("previous_mir=unchanged",1,true) and message:find("saved_route=default",1,true))
          assert(message:find("current_route=finite",1,true) and message:find("startup_changed=true",1,true))
        ''')

    def test_unknown_history_context_stays_bounded_printable_and_does_not_gain_authority(self):
        self.lua.execute(r'''
          seed();add_provider(5);writes=0
          local old=string.rep("a",95).."\195\169\0\n"..string.rep("z",500)
          local ok,message=pcall(history.preflight,{mod_changes={
            ['more-infinite-research']={old_version=old,new_version="5.0.21012"},
            secretas={new_version="1.0.38\0\n"}}},provider_route(5))
          assert(not ok and writes==0 and storage.mir_worker_storage_route==nil)
          assert(not message:find("[%z\1-\31\127-\255]") and #message<4096)
          assert(message:find("\\xC3",1,true) and message:find("\\x00",1,true))
          assert(message:find("startup_changed=unknown",1,true))
        ''')

    def test_prepared_default_accepts_named_finite_routes_without_public_grants(self):
        for last in (5, 8):
            with self.subTest(last=last):
                self.setUp()
                self.lua.globals().last = last
                self.lua.execute(r'''
                  seed();history.prepare(nil);local private=player.technologies[ID];local state=storage.mir_worker_storage_route
                  add_provider(last);uninvested.technologies[CANONICAL].enabled=false
                  writes=0;local plan=history.preflight({mod_changes={provider={new_version="1.0"}}},provider_route(last))
                  assert(writes==0 and history.plan_prepared(plan));history.apply(plan)
                  assert(storage.mir_worker_storage_route.phase=="provider" and private.level==8 and player.research_progress==.375)
                  assert(not uninvested.technologies[CANONICAL].enabled)
                  for _,f in pairs(game.forces)do for n=4,last+1 do assert(not f.technologies['worker-robots-storage-'..n].researched)end end
                  writes=0;local ok=pcall(history.preflight,{mod_changes={provider={old_version="1.0"}}},nil)
                  assert(not ok and writes==0, "unqualified removal accepted")
                ''')

    def test_changed_cap_enable_contract_or_intervening_canonical_work_refuses(self):
        for opponent in ('history.configure(9,true)', 'history.configure(0,false)', 'player.technologies[CANONICAL].saved_progress=.1',
                         'prototypes.technology[ID].research_unit_count_formula=nil;prototypes.technology[ID].research_unit_count=1;prototypes.technology[ID].research_unit_energy=60;prototypes.technology[ID].prerequisites={}',
                         'storage.mir_worker_storage_route.forces[1].next_level=7', 'player.technologies[ID].enabled=false'):
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute('seed();history.prepare(nil);'+opponent+';writes=0;assert(not pcall(history.preflight,{},nil) and writes==0)')
        self.setUp()
        self.lua.execute('seed();history.configure(7,true);writes=0;assert(not pcall(history.prepare,nil) and writes==0)')

    def test_one_preserved_suspended_level_retires_without_touching_unrelated_progress(self):
        self.lua.execute(r'''
          seed();history.prepare(nil)
          local f=suspended;local p=f.technologies[ID]
          f.research_queue={OTHER};f.research_progress=.42;p.level=8
          history.on_research_event({research=p,by_script=false},true)
          assert(p.level==8 and not p.enabled and f.current_research.name==OTHER and f.research_progress==.42)
          assert(not storage.mir_worker_storage_route.forces[f.index].pending)
          assert(storage.mir_worker_storage_route.forces[f.index].limit==7)
        ''')

    def test_detached_partial_resume_is_explicit_and_preserves_foreign_current(self):
        self.lua.execute(r'''
          seed();suspended.research_queue={OTHER};suspended.research_progress=.42
          suspended.technologies[CANONICAL].saved_progress=.27
          history.prepare(nil);local f=suspended
          assert(history.resume(f,nil))
          assert(f.current_research.name==OTHER and f.research_progress==.42 and f.research_queue[2].name==ID)
          assert(f.technologies[ID].saved_progress==.27)
        ''')

    def test_owned_resume_defers_reentrant_transient_queue_frames_until_stable(self):
        for transient in ("current_research", "research_progress"):
            with self.subTest(transient=transient):
                self.setUp()
                self.lua.globals().transient_field = transient
                self.lua.execute(r'''
                  seed();suspended.research_queue={OTHER};suspended.research_progress=.42
                  suspended.technologies[CANONICAL].saved_progress=.27;history.prepare(nil)
                  local f=suspended;local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex
                  local changing=false;local callbacks=0;local before=f.worker_robots_storage_bonus
                  mt.__index=function(o,k)if changing and k==transient_field then return nil end;return read(o,k)end
                  mt.__newindex=function(o,k,v)
                    if k=="research_queue"then changing=true;callbacks=callbacks+1
                      assert(history.on_research_event({research=f.technologies[ID]})==false)
                      changing=false
                    end
                    return write(o,k,v)
                  end
                  assert(history.resume(f,nil));assert(callbacks==1)
                  assert(f.current_research.name==OTHER and f.research_progress==.42)
                  assert(f.research_queue[2].name==ID and f.technologies[ID].saved_progress==.27)
                  assert(f.worker_robots_storage_bonus==before)
                  local record=storage.mir_worker_storage_route.forces[f.index]
                  assert(record.next_level==7 and record.limit==7 and record.pending)
                  changing=true;local ok,message=pcall(history.on_research_event,{research=f.technologies[ID]});changing=false
                  assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true),"external guard weakened")
                ''')

    def test_owned_queue_gate_is_restored_after_native_setter_error(self):
        self.lua.execute(r'''
          seed();suspended.research_queue={OTHER};suspended.research_progress=.42
          suspended.technologies[CANONICAL].saved_progress=.27;history.prepare(nil)
          local f=suspended;local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex
          local changing=false
          mt.__index=function(o,k)if changing and k=="research_progress"then return nil end;return read(o,k)end
          mt.__newindex=function(o,k,v)
            if k=="research_queue"then changing=true
              local ok,message=pcall(history.on_research_event,{research=f.technologies[ID]});changing=false
              assert(ok and message==false);error("injected native queue failure")
            end
            return write(o,k,v)
          end
          local ok,message=pcall(history.resume,f,nil)
          assert(not ok and tostring(message):find("injected native queue failure",1,true))
          changing=true;ok,message=pcall(history.on_research_event,{research=f.technologies[ID]});changing=false
          assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true),"gate leaked after error")
          mt.__newindex=write;assert(history.resume(f,nil))
          assert(f.current_research.name==OTHER and f.research_progress==.42 and f.research_queue[2].name==ID)
        ''')

    def test_owned_queue_gate_does_not_mute_another_forces_external_event(self):
        self.lua.execute(r'''
          seed();suspended.research_queue={OTHER};suspended.research_progress=.42
          suspended.technologies[CANONICAL].saved_progress=.27;history.prepare(nil)
          local other=getmetatable(player);local read=other.__index;local broken=false
          other.__index=function(o,k)if broken and k=="research_progress"then return nil end;return read(o,k)end
          local mt=getmetatable(suspended);local write=mt.__newindex
          mt.__newindex=function(o,k,v)
            if k=="research_queue"then broken=true
              local ok,message=pcall(history.on_research_event,{research=player.technologies[ID]});broken=false
              assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true),"another force was muted")
            end
            return write(o,k,v)
          end
          assert(history.resume(suspended,nil))
          assert(suspended.current_research.name==OTHER and suspended.research_progress==.42)
        ''')

    def test_retirement_owned_caps_queue_write_does_not_reenter_partial_state(self):
        self.lua.execute(r'''
          seed();history.prepare(nil);local f=player;local p=f.technologies[ID]
          f.technologies[OTHER].saved_progress=.42;f.research_progress=0;p.level=9
          local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex;local changing=false;local callbacks=0
          mt.__index=function(o,k)if changing and k=="research_progress"then return nil end;return read(o,k)end
          mt.__newindex=function(o,k,v)
            if k=="research_queue"then changing=true;callbacks=callbacks+1
              assert(history.on_research_event({research=f.technologies[OTHER]})==false);changing=false
            end
            return write(o,k,v)
          end
          assert(history.on_research_event({research=p,by_script=false},true));assert(callbacks==1)
          assert(f.current_research.name==OTHER and f.research_progress==.42 and #f.research_queue==1)
          assert(not p.enabled and not storage.mir_worker_storage_route.forces[f.index].pending)
        ''')

    def test_owned_resume_still_refuses_a_malformed_settled_frame(self):
        self.lua.execute(r'''
          seed();suspended.research_queue={OTHER};suspended.research_progress=.42
          suspended.technologies[CANONICAL].saved_progress=.27;history.prepare(nil)
          local f=suspended;local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex;local broken=false
          mt.__index=function(o,k)if broken and k=="research_progress"then return nil end;return read(o,k)end
          mt.__newindex=function(o,k,v)write(o,k,v);if k=="research_queue"then broken=true end end
          local ok,message=pcall(history.resume,f,nil)
          assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true),"settled invariant was skipped")
        ''')

    def test_pending_caps_reconcile_queue_write_has_the_same_owned_gate(self):
        self.lua.execute(r'''
          seed();history.prepare(nil);local f=player;local p=f.technologies[ID]
          f.research_queue={ID,ID,OTHER};f.research_progress=.375
          local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex;local changing=false;local callbacks=0
          mt.__index=function(o,k)if changing and k=="research_progress"then return nil end;return read(o,k)end
          mt.__newindex=function(o,k,v)
            if k=="research_queue"then changing=true;callbacks=callbacks+1
              assert(history.on_research_event({research=p})==false);changing=false
            end
            return write(o,k,v)
          end
          assert(history.on_research_event({research=p}));assert(callbacks==1)
          assert(f.current_research.name==ID and f.research_progress==.375 and #f.research_queue==2)
          assert(f.research_queue[2].name==OTHER and storage.mir_worker_storage_route.forces[f.index].limit==8)
        ''')

    def test_finished_sentinel_admits_only_observed_zero_progress_queue_gap(self):
        self.lua.execute(r'''
          seed();history.prepare(nil);local f=suspended;local p=f.technologies[ID]
          local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex;local queue_writes=0
          mt.__index=function(o,k)
            if k=="current_research"then return nil elseif k=="research_queue"then return {p}
            elseif k=="research_progress"then return 0 end;return read(o,k)
          end
          mt.__newindex=function(o,k,v)if k=="research_queue"or k=="research_progress"then queue_writes=queue_writes+1 end;return write(o,k,v)end
          assert(history.on_research_event({research=f.technologies[OTHER],by_script=false},true))
          local record=storage.mir_worker_storage_route.forces[f.index]
          assert(queue_writes==0 and f.current_research==nil and f.research_progress==0)
          assert(p.level==7 and not p.researched and p.saved_progress==.27 and record.next_level==7 and record.limit==7 and record.pending)
          writes=0;local ok,message=pcall(history.on_research_event,{research=f.technologies[OTHER]},false)
          assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true) and writes==0)
          package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage");writes=0;history.on_load(nil)
          ok,message=pcall(history.preflight,{},nil)
          assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true) and writes==0,"finish context leaked into cold state")
        ''')

    def test_private_finished_gap_preserves_both_native_completed_representations(self):
        for researched in (False, True):
            with self.subTest(researched=researched):
                self.setUp();self.lua.globals().completed_true=researched
                self.lua.execute(r'''
                  seed();history.prepare(nil);local f=player;local p=f.technologies[ID];local other=f.technologies[OTHER]
                  p.level=completed_true and 8 or 9;p.researched=completed_true;other.saved_progress=.42
                  local bonus=f.worker_robots_storage_bonus;local mt=getmetatable(f);local read=mt.__index
                  mt.__index=function(o,k)
                    if k=="current_research"then return nil elseif k=="research_queue"then return {other}
                    elseif k=="research_progress"then return 0 end;return read(o,k)
                  end
                  assert(history.on_research_event({research=p,by_script=false},true))
                  local record=storage.mir_worker_storage_route.forces[f.index]
                  assert(record.next_level==9 and record.limit==8 and not record.pending and not p.enabled)
                  assert(f.current_research==nil and f.research_progress==0 and other.saved_progress==.42 and f.worker_robots_storage_bonus==bonus)
                ''')

    def test_finish_gap_exclusions_refuse_before_native_writes(self):
        for opponent in ("not-finished", "no-research", "wrong-force", "nonzero", "one", "nil", "present-mismatch"):
            with self.subTest(opponent=opponent):
                self.setUp();self.lua.globals().opponent=opponent
                self.lua.execute(r'''
                  seed();history.prepare(nil);local f=suspended;local p=f.technologies[ID]
                  local mt=getmetatable(f);local read=mt.__index
                  mt.__index=function(o,k)
                    if k=="current_research"then return opponent=="present-mismatch"and f.technologies[OTHER]or nil
                    elseif k=="research_queue"then return {p}
                    elseif k=="research_progress"then if opponent=="nil"then return nil end;return opponent=="one"and 1 or opponent=="nonzero"and .1 or 0 end
                    return read(o,k)
                  end
                  local event={research=f.technologies[OTHER],by_script=false}
                  if opponent=="no-research"then event={force=f}elseif opponent=="wrong-force"then event={force=f,research=player.technologies[OTHER]}end
                  writes=0;local ok,message=pcall(history.on_research_event,event,opponent~="not-finished")
                  assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true),opponent)
                  assert(writes==0,"invalid finish frame wrote native state")
                ''')

    def test_finish_context_does_not_cover_unsettled_owned_queue_rewrite(self):
        self.lua.execute(r'''
          seed();history.prepare(nil);local f=suspended;local p=f.technologies[ID];local other=f.technologies[OTHER]
          local queue={p,p,other};local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex;local queue_writes=0
          mt.__index=function(o,k)
            if k=="current_research"then return nil elseif k=="research_queue"then return queue
            elseif k=="research_progress"then return 0 end;return read(o,k)
          end
          mt.__newindex=function(o,k,v)if k=="research_queue"then queue_writes=queue_writes+1;queue=v end;return write(o,k,v)end
          local ok,message=pcall(history.on_research_event,{research=other,by_script=false},true)
          assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true) and queue_writes==1,"owned setter escaped strict settled guard")
        ''')

    def test_native_merge_reconciles_only_surviving_metadata_without_native_writes(self):
        self.lua.execute(r'''
          seed();history.prepare(nil)
          game.forces.uninvested=nil
          local before=player.worker_robots_storage_bonus;writes=0
          history.on_forces_merged({source_index=2,destination=player})
          assert(writes==0 and player.worker_robots_storage_bonus==before and player.research_progress==.375)
          local state=storage.mir_worker_storage_route
          assert(state.forces[2]==nil and state.forces[1].next_level==8 and state.forces[1].limit==8)
        ''')

    def test_completed_investment_retires_future_private_work_and_new_force_stays_empty(self):
        self.lua.execute(r'''
          player.technologies[CANONICAL].level=8
          player.research_queue={OTHER};player.research_progress=.2
          local bonus=player.worker_robots_storage_bonus
          history.prepare(nil)
          assert(player.worker_robots_storage_bonus==bonus and not player.technologies[ID].enabled)
          assert(player.technologies[CANONICAL].enabled and not history.needs_research_events())
          local fresh=make_force("fresh",4);game.forces.fresh=fresh
          fresh.technologies[ID].enabled=true;fresh.technologies[ID].visible_when_disabled=true
          history.on_force_created({force=fresh})
          assert(not fresh.technologies[ID].enabled and not fresh.technologies[ID].visible_when_disabled)
          assert(fresh.worker_robots_storage_bonus==3 and storage.mir_worker_storage_route.forces[4].next_level==4)
        ''')

    def test_foreign_first_install_keeps_actual_levels_bonus_and_work(self):
        self.lua.execute(r'''
          seed();creators[CANONICAL]="foreign-infinite"
          local queue=player.research_queue;local bonus=player.worker_robots_storage_bonus
          writes=0;history.on_init(nil)
          assert(writes==0 and storage.mir_worker_storage_route.current.kind=="external")
          assert(player.research_queue==queue and player.research_progress==.375 and player.worker_robots_storage_bonus==bonus)
          writes=0;assert(not pcall(history.prepare,nil) and writes==0)
        ''')

    def test_admin_command_and_malformed_load_have_explicit_readonly_boundaries(self):
        self.lua.execute(r'''
          seed();local replies={}
          local nonadmin={admin=false,print=function(text)replies[#replies+1]=text end}
          game.get_player=function()return nonadmin end
          history.command({player_index=1,parameter="prepare"},nil)
          assert(writes==0 and storage.mir_worker_storage_route==nil and replies[1]:find("administrator",1,true))
          history.command({parameter="prepare"},nil)
          local state=storage.mir_worker_storage_route;assert(state.kind=="prepared")
          state.forces[1].pending="invented";writes=0
          game=setmetatable({}, {__index=function()error("load read game")end})
          assert(not pcall(history.on_load) and writes==0 and storage.mir_worker_storage_route==state)
        ''')

    def test_multiple_queue_occurrences_authorize_only_their_actual_count(self):
        self.lua.execute(r'''
          seed();player.research_queue={CANONICAL,CANONICAL,OTHER};player.research_progress=.375
          history.prepare(nil);local p=player.technologies[ID]
          assert(storage.mir_worker_storage_route.forces[1].limit==9)
          player.research_queue={ID,OTHER};player.research_progress=.2;p.level=9
          history.on_research_event({research=p},true)
          assert(p.enabled and storage.mir_worker_storage_route.forces[1].limit==9)
          player.research_queue={OTHER};player.research_progress=.3;p.level=10
          history.on_research_event({research=p},true)
          assert(not p.enabled and not storage.mir_worker_storage_route.forces[1].pending)
          assert(player.research_progress==.3 and player.current_research.name==OTHER)
        ''')

    def test_saved_external_route_cannot_be_replaced_by_current_default_appearance(self):
        self.lua.execute(r'''
          seed();local state={schema=2,kind="route",current={kind="external",provider="previous-owner"}}
          storage.mir_worker_storage_route=state;writes=0
          assert(not pcall(history.prepare,nil) and writes==0 and storage.mir_worker_storage_route==state)
        ''')

    def test_closed_provider_recovery_allows_later_cap_and_enable_changes_without_native_writes(self):
        self.lua.execute(r'''
          seed();history.prepare(nil);add_provider(5)
          history.apply(history.preflight({},provider_route(5)))
          for _,f in ipairs({player,suspended})do
            local p=f.technologies[ID]
            f.research_queue={OTHER};f.research_progress=f==player and .51 or .42
            p.level=p.level+1
            history.on_research_event({research=p},true)
          end
          assert(not history.needs_research_events())
          local original=storage.mir_worker_storage_route
          local frames={}
          for _,f in pairs(game.forces)do
            local p=f.technologies[ID]
            assert(not p.enabled and not original.forces[f.index].pending)
            frames[f.index]={level=p.level,bonus=f.worker_robots_storage_bonus,queue=f.research_queue,
              current=f.current_research,progress=f.research_progress,canonical_enabled=f.technologies[CANONICAL].enabled}
          end
          for _,policy in ipairs({{7,false},{0,true},{5,true}})do
            history.configure(policy[1],policy[2]);writes=0
            local plan=history.preflight({mod_startup_settings_changed=true},provider_route(5))
            assert(storage.mir_worker_storage_route==original and writes==0,"preflight mutated settled state")
            history.apply(plan)
            original=storage.mir_worker_storage_route
            assert(original.cap==policy[1] and original.family_enabled==policy[2] and writes==0)
            for _,f in pairs(game.forces)do
              local p,b=f.technologies[ID],frames[f.index]
              assert(p.level==b.level and not p.enabled and f.worker_robots_storage_bonus==b.bonus)
              assert(f.research_queue==b.queue and f.current_research==b.current and f.research_progress==b.progress)
              assert(f.technologies[CANONICAL].enabled==b.canonical_enabled)
              for level=4,6 do assert(not f.technologies['worker-robots-storage-'..level].researched)end
            end
          end
          -- The normal public-tail cap writer still runs independently after
          -- recovery admission; it may prune only its own above-cap work.
          local name='worker-robots-storage-6';local tail=player.technologies[name]
          tail.name=name;tail.visible_when_disabled=false
          player.research_queue={OTHER,name};player.research_progress=.51
          local bonus,private_level=player.worker_robots_storage_bonus,player.technologies[ID].level
          local ownership={};require('runtime.caps').reconcile(player,{[name]=5},ownership)
          assert(not tail.enabled and ownership[player.index][name].disabled)
          assert(player.current_research.name==OTHER and player.research_progress==.51 and #player.research_queue==1)
          assert(player.worker_robots_storage_bonus==bonus and player.technologies[ID].level==private_level
            and not player.technologies[ID].enabled)
        ''')

    def test_policy_change_remains_temporary_while_provider_legacy_work_is_pending(self):
        self.lua.execute(r'''
          seed();history.prepare(nil);add_provider(5)
          history.apply(history.preflight({},provider_route(5)))
          local state=storage.mir_worker_storage_route
          for _,policy in ipairs({{7,true},{0,false}})do
            history.configure(policy[1],policy[2]);writes=0
            local queue,bonus=player.research_queue,player.worker_robots_storage_bonus
            assert(not pcall(history.preflight,{mod_startup_settings_changed=true},provider_route(5)))
            assert(writes==0 and storage.mir_worker_storage_route==state and state.cap==0 and state.family_enabled)
            assert(player.research_queue==queue and player.research_progress==.375 and player.worker_robots_storage_bonus==bonus)
          end
        ''')

    def test_no_pending_marker_alone_cannot_release_preparation_or_actual_work_guards(self):
        self.lua.execute(r'''
          player.technologies[CANONICAL].level=8
          history.prepare(nil);assert(not history.needs_research_events())
          history.configure(7,false);writes=0
          assert(not pcall(history.preflight,{},nil) and writes==0,"pre-entry settings were relaxed")
          history.configure(0,true);add_provider(5)
          history.apply(history.preflight({},provider_route(5)))
          player.technologies[ID].saved_progress=.2
          history.configure(7,false);writes=0
          assert(not pcall(history.preflight,{},provider_route(5)) and writes==0,"actual detached work was ignored")
        ''')

class WorkerDefaultNativeOwnerTransferTests(unittest.TestCase):
    """Independent native contribution and exact-work controls for full4 ownership."""

    def world(self, target="f210"):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root=(Path(__file__).resolve().parents[1]/"source").as_posix()
        lua.globals().package_family=target
        lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          local f200=package_family=="f200"
          package.loaded["platform.target"]={id=package_family,minimum_base=f200 and "2.0.77"or"2.1.23",
            distribution_version=f200 and "5.0.20012"or"5.0.21012"}
        ''')
        lua.execute(RECOVERY_WORLD)
        lua.execute(r'''
          local target=require("platform.target")
          script.active_mods.base=target.minimum_base;script.active_mods["more-infinite-research"]=target.distribution_version
          ORDINARY="mir-worker-storage-default-4";HEAD="mir-worker-storage-head-4";OWNER_KEY="mir_worker_storage_native_owner"
          function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
          function same(a,b)if type(a)~=type(b)then return false end;if type(a)~="table"then return a==b end
            for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
          prototypes.technology[ORDINARY]=copy(prototypes.technology[CANONICAL])
          local owner=prototypes.technology[ORDINARY];owner.name=ORDINARY;owner.hidden=false;owner.visible_when_disabled=false
          local debit=copy(prototypes.technology[CANONICAL]);prototypes.technology[HEAD]=debit
          debit.name=HEAD;debit.max_level=4294967295;debit.hidden=true;debit.enabled=false;debit.visible_when_disabled=false
          debit.effects[1].modifier=-1;debit.research_unit_count_formula=nil;debit.research_unit_count=1
          debit.research_unit_energy=60;debit.prerequisites={}
          creators[ORDINARY]="more-infinite-research";creators[HEAD]="more-infinite-research"
          detached=make_force("detached",4);game.forces.detached=detached
          queue_writes={};progress_writes={};foreign_bonus={};gaps={}
          function install_force(force)
            local index=force.index;foreign_bonus[index]=20
            for _,id in ipairs{ORDINARY,HEAD}do
              local proto=prototypes.technology[id]
              local v={name=id,level=4,researched=false,enabled=proto.enabled,visible_when_disabled=proto.visible_when_disabled,
                saved_progress=0,prototype=proto,force=force,prerequisites=id==HEAD and{}or{foundation={researched=true}}}
              force.technologies[id]=setmetatable({},{__index=function(_,key)
                if key=="research_unit_count"then return id==HEAD and 1 or math.floor(100*2^(v.level-4))end
                return v[key]
              end,__newindex=function(_,key,value)
                writes=writes+1
                if key=="level"then v.level=value;v.researched=false;v.enabled=true;v.saved_progress=0 else v[key]=value end
              end})
            end
            local mt=getmetatable(force);local read,write=mt.__index,mt.__newindex
            mt.__index=function(object,key)
              if key=="worker_robots_storage_bonus"then
                local total=foreign_bonus[index]
                for _,id in ipairs{CANONICAL,ORDINARY,ID}do local t=force.technologies[id]
                  total=total+(t.level-4+(t.researched and 1 or 0))*prototypes.technology[id].effects[1].modifier
                end
                local h=force.technologies[HEAD]
                return total+(h.level-4+(h.researched and 1 or 0))*prototypes.technology[HEAD].effects[1].modifier
              end
              if gaps[index]and key=="current_research"then return nil end
              if gaps[index]and key=="research_progress"then return 0 end
              return read(object,key)
            end
            mt.__newindex=function(object,key,value)
              if key=="research_queue"then
                queue_writes[index]=(queue_writes[index]or 0)+1
                local admitted={}
                for _,entry in ipairs(value)do
                  local t=force.technologies[type(entry)=="string"and entry or entry.name];local valid=t and t.enabled
                  for _,pr in pairs(t and t.prerequisites or{})do local proto=pr.prototype
                    if not pr.researched and not(proto and proto.max_level==4294967295 and pr.level>proto.level)then valid=false end
                  end
                  if valid then admitted[#admitted+1]=entry end
                end
                value=admitted
              elseif key=="research_progress"then progress_writes[index]=(progress_writes[index]or 0)+1 end
              write(object,key,value)
            end
          end
          for _,f in pairs(game.forces)do install_force(f)end
          function set_reward(value)
            prototypes.technology[CANONICAL].effects[1].modifier=value
            prototypes.technology[ORDINARY].effects[1].modifier=value
            prototypes.technology[HEAD].effects[1].modifier=value==0 and 0 or -value
            prototypes.technology[ID].effects[1].modifier=value
          end
          function owner_event(old)return{mod_startup_settings_changed=false,mod_changes={
            ["more-infinite-research"]={old_version=old,new_version=target.distribution_version}}}end
          function seed_owner()
            seed();detached.technologies[CANONICAL].level=6;detached.technologies[CANONICAL].saved_progress=.23
            detached.research_queue={OTHER};detached.research_progress=.625;writes=0;queue_writes={};progress_writes={}
          end
          function tech_frame(t)return{level=t.level,researched=t.researched,enabled=t.enabled,
            visible=t.visible_when_disabled,saved=t.saved_progress,count=t.research_unit_count}end
          function frame(f)
            local queue={}for i,t in ipairs(f.research_queue)do queue[i]=t.name end
            return{source=tech_frame(f.technologies[CANONICAL]),owner=tech_frame(f.technologies[ORDINARY]),
              debit=tech_frame(f.technologies[HEAD]),private=tech_frame(f.technologies[ID]),
              current=f.current_research and f.current_research.name,progress=f.research_progress,queue=queue,
              bonus=f.worker_robots_storage_bonus,other_saved=f.technologies[OTHER].saved_progress}
          end
          function all_frames()local out={}for _,f in pairs(game.forces)do out[f.index]=frame(f)end;return out end
          function transfer()
            local plan=history.plan_default_owner_transfer(owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011"),nil,false)
            return history.apply_default_owner_transfer(plan),plan
          end
          function init_default()history.on_init(nil);assert(history.default_owner_on_init(nil,true));writes=0;queue_writes={};progress_writes={}end
          function finish_frame(force,representation,remainder,gap)
            force.research_progress=0;force.technologies[ORDINARY].saved_progress=0
            if representation=="completed"then force.technologies[ORDINARY].researched=true else force.technologies[ORDINARY].level=5 end
            force.research_queue=remainder;force.research_progress=0;gaps[force.index]=gap
            writes=0;queue_writes={};progress_writes={}
          end
          function finish_event(force)return{research=force.technologies[ORDINARY],by_script=false,tick=100}end
        ''')
        return lua

    def test_four_forces_full_work_and_independent_scalar_totals_move_once(self):
        for target in ("f200","f210"):
            for scalar in (0,1,2):
                lua=self.world(target);lua.globals().scalar=scalar
                lua.execute(r'''
                  set_reward(scalar);seed_owner();local old={schema=2,kind="route",current={kind="default"}};storage.mir_worker_storage_route=old
                  local before=all_frames();local plan=history.plan_default_owner_transfer(owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011"),nil,false)
                  assert(writes==0 and same(before,all_frames()))
                  for _,item in ipairs(plan.items)do assert(item.moved and item.phase=="owned")end
                  assert(history.apply_default_owner_transfer(plan));local state=storage[OWNER_KEY]
                  assert(state.schema==3 and state.kind=="full-default"and state.owner==ORDINARY and state.source==CANONICAL)
                  assert(storage.mir_worker_storage_route==old and state.producer.kind=="recorded-default")
                  for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index];local paid=b.source.level>=5
                    assert(a.source.level==(paid and 5 or 4)and not a.source.researched and not a.source.enabled and a.source.saved==0)
                    assert(a.owner.level==b.source.level and not a.owner.researched and a.owner.enabled==b.source.enabled and a.owner.visible==b.source.visible)
                    assert(a.owner.saved==b.source.saved and a.debit.level==(paid and 5 or 4)and not a.debit.researched and not a.debit.enabled)
                    assert(a.bonus==20+(b.source.level-4)*scalar and a.bonus==b.bonus and a.other_saved==b.other_saved)
                    assert(same(a.private,b.private)and state.forces[f.index].phase=="owned")
                    assert(state.forces[f.index].retired_flags.disabled_by_mir==b.source.enabled)
                    assert(state.forces[f.index].level==nil and state.forces[f.index].progress==nil)
                  end
                  assert(player.current_research.name==ORDINARY and player.research_progress==.375 and player.research_queue[2].name==OTHER)
                  assert(suspended.current_research.name==OTHER and suspended.research_progress==.42 and suspended.research_queue[2].name==ORDINARY)
                  assert(suspended.technologies[ORDINARY].saved_progress==.27 and detached.technologies[ORDINARY].saved_progress==.23)
                  assert(queue_writes[1]==1 and queue_writes[3]==1 and queue_writes[2]==nil and queue_writes[4]==nil)
                  local after=all_frames();writes=0;assert(not history.apply_default_owner_transfer(plan)and writes==0 and same(after,all_frames()))
                ''')

    def test_unpaid_current_repeated_suspended_and_detached_work_move_at_four(self):
        for scalar in (0,2):
            lua=self.world();lua.globals().scalar=scalar
            lua.execute(r'''
              set_reward(scalar);seed_owner();for _,f in pairs(game.forces)do f.technologies[CANONICAL].level=4 end
              suspended.technologies[CANONICAL].saved_progress=.27;detached.technologies[CANONICAL].saved_progress=.23
              player.research_queue={CANONICAL,CANONICAL,OTHER};player.research_progress=.37
              local before=all_frames();writes=0;queue_writes={};history.configure(4,true);transfer()
              for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                assert(a.owner.level==4 and a.owner.saved==b.source.saved and a.bonus==20 and not a.debit.researched)
                assert(a.source.level==4 and a.source.saved==0 and not a.source.enabled)
              end
              assert(player.current_research.name==ORDINARY and player.research_progress==.37 and player.research_queue[2].name==ORDINARY)
              assert(suspended.research_queue[2].name==ORDINARY and suspended.technologies[ORDINARY].saved_progress==.27)
              assert(detached.technologies[ORDINARY].saved_progress==.23 and queue_writes[4]==nil)
            ''')

    def test_completed_source_normalizes_exact_count_and_external_disabled_flags(self):
        lua=self.world();lua.execute(r'''
          player.technologies[CANONICAL].level=8;player.technologies[CANONICAL].researched=true
          player.technologies[CANONICAL].enabled=false;player.technologies[CANONICAL].visible_when_disabled=true
          local bonus=player.worker_robots_storage_bonus;writes=0;transfer()
          assert(player.technologies[ORDINARY].level==9 and not player.technologies[ORDINARY].researched)
          assert(not player.technologies[ORDINARY].enabled and player.technologies[ORDINARY].visible_when_disabled)
          assert(player.worker_robots_storage_bonus==bonus and bonus==25)
          local rights=storage[OWNER_KEY].forces[1].retired_flags
          assert(not rights.enabled and not rights.disabled_by_mir and not rights.visibility_hidden_by_mir)
        ''')

    def test_pristine_init_and_exact_old_nil_origins_both_families(self):
        for target in ("f200","f210"):
            lua=self.world(target);lua.execute('init_default();assert(storage[OWNER_KEY].producer.kind=="initial-empty")')
            for patch in (9,10,11):
                lua=self.world(target);lua.globals().old="5.0."+("200"if target=="f200"else"210")+str(patch).zfill(2)
                lua.execute('seed_owner();assert(history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event(old),nil,false)))')

    def test_initial_investment_unknown_producer_and_prepared_history_refuse_before_writes(self):
        for opponent in ('player.technologies[CANONICAL].saved_progress=.1','player.research_queue={CANONICAL}','player.technologies[CANONICAL].level=5'):
            lua=self.world();lua.execute(opponent+r''';local b=all_frames();writes=0
              assert(not pcall(history.plan_default_owner_transfer,nil,nil,true)and writes==0 and same(b,all_frames()))
            ''')
        for old in ("4.7.21003","5.0.21042","5.0.21043","5.0.20011"):
            lua=self.world();lua.globals().old=old;lua.execute(r'''
              seed_owner();local b=all_frames();writes=0;assert(not pcall(history.plan_default_owner_transfer,owner_event(old),nil,false))
              assert(writes==0 and same(b,all_frames())and storage[OWNER_KEY]==nil)
            ''')
        lua=self.world();lua.execute(r'''
          seed_owner();history.prepare(nil);local b=all_frames();writes=0
          assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false)and writes==0 and same(b,all_frames()))
        ''')

    def test_all_force_contract_custody_pristine_and_event_opponents_before_writes(self):
        opponents=['creators[CANONICAL]="foreign"','creators[ORDINARY]="foreign"','creators[HEAD]="foreign"',
          'prototypes.technology[CANONICAL].max_level=4','prototypes.technology[ORDINARY].level=5',
          'prototypes.technology[ORDINARY].research_unit_energy=3600','prototypes.technology[ORDINARY].research_unit_count_formula="200*2^(L-4)"',
          'prototypes.technology[ORDINARY].effects[1].modifier=2','prototypes.technology[ORDINARY].research_unit_ingredients[1].amount=2',
          'prototypes.technology[ORDINARY].prerequisites[HEAD]={name=HEAD}','prototypes.technology[HEAD].effects[1].modifier=0',
          'prototypes.technology[HEAD].research_unit_count=2','prototypes.technology[HEAD].research_unit_energy=1',
          'prototypes.technology[HEAD].research_unit_ingredients[1].name="wrong"','prototypes.technology[HEAD].ignore_tech_cost_multiplier=true',
          'detached.technologies[ORDINARY].saved_progress=.1','detached.technologies[ORDINARY].level=5',
          'suspended.technologies[HEAD].researched=true','suspended.technologies[HEAD].enabled=true',
          'uninvested.technologies[ORDINARY].enabled=false','suspended.technologies[CANONICAL].saved_progress=1',
          'event.mod_startup_settings_changed=true','event.mod_changes["more-infinite-research"].new_version="5.0.21013"',
          'event.mod_changes.foreign={old_version="1",new_version="2"}',
          'script.active_mods.foreign="1";event.mod_changes.foreign={new_version="1"}',
          'prototypes.technology["worker-robots-storage-5"]={}','route=provider_route(5)']
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua=self.world();lua.execute('seed_owner();local event=owner_event("5.0.21011");local route=nil;'+opponent+r'''
                  local before=all_frames();writes=0;assert(not pcall(history.plan_default_owner_transfer,event,route,false))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                ''')

    def test_stale_plan_detects_last_force_work_bonus_and_debit_changes(self):
        for change in ('detached.technologies[CANONICAL].saved_progress=.29','foreign_bonus[4]=21','detached.technologies[HEAD].researched=true'):
            lua=self.world();lua.execute(r'''
              seed_owner();local plan=history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false)
            '''+change+r''';local before=all_frames();writes=0
              assert(not pcall(history.apply_default_owner_transfer,plan)and writes==0 and same(before,all_frames()))
            ''')

    def test_malformed_old_split_record_and_native_owner_drift_refuse(self):
        for change in ('state.schema=2;state.kind="split-default"','state.owner="mir-worker-storage-default-5"',
                       'state.producer.old_version="5.0.21042"','state.forces[2].retired_flags.disabled_by_mir=true',
                       'state.forces[99]=state.forces[1]','state.contract="changed"',
                       'player.technologies[CANONICAL].saved_progress=.1','player.technologies[CANONICAL].enabled=true','uninvested.technologies[HEAD].researched=true'):
            lua=self.world();lua.execute('seed_owner();transfer();local state=storage[OWNER_KEY];'+change+r'''
              local before=all_frames();writes=0;assert(not pcall(history.plan_default_owner_transfer,{},nil,false)and writes==0 and same(before,all_frames()))
            ''')

    def test_earned_first_keeps_foreign_prerequisite_and_unrelated_queue_not_reassigned(self):
        lua=self.world();lua.execute(r'''
          seed_owner();player.technologies[OTHER].prerequisites={[CANONICAL]=player.technologies[CANONICAL]}
          player.research_queue={CANONICAL,OTHER};player.research_progress=.375;detached.technologies[OTHER].enabled=false
          writes=0;queue_writes={};transfer()
          assert(player.technologies[CANONICAL].level==5 and not player.technologies[CANONICAL].researched)
          assert(player.current_research.name==ORDINARY and player.research_queue[2].name==OTHER and player.research_progress==.375)
          assert(queue_writes[4]==nil and detached.research_progress==.625 and not detached.technologies[OTHER].enabled)
        ''')
        lua=self.world();lua.execute(r'''
          seed_owner();player.technologies[OTHER].prerequisites={finite={researched=false,level=5,prototype={level=4,max_level=8}}}
          local before=all_frames();writes=0
          assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false)and writes==0 and same(before,all_frames()))
        ''')

    def test_missing_debit_mutant_cannot_commit_independent_native_contribution(self):
        source=(Path(__file__).resolve().parents[1]/"source/runtime/worker_robot_storage.lua").read_text()
        literal='gate.level = level';self.assertEqual(source.count(literal),1)
        lua=self.world();lua.globals().mutant=source.replace(literal,'gate.level = 4',1)
        lua.execute(r'''
          history=assert(load(mutant))();seed_owner();local ok,e=pcall(transfer)
          assert(not ok and tostring(e):find("native full default contribution",1,true)and storage[OWNER_KEY]==nil)
          assert(player.worker_robots_storage_bonus==25)
        ''')

    def test_recorded_settings_preserve_overcap_detached_work_and_external_false(self):
        lua=self.world();lua.execute(r'''
          history.on_init(nil);seed_owner();player.research_queue={OTHER};player.research_progress=.42
          player.technologies[CANONICAL].saved_progress=.27;player.technologies[CANONICAL].enabled=false
          history.configure(7,false);local event=owner_event("5.0.21011");event.mod_startup_settings_changed=true
          local old=storage.mir_worker_storage_route;writes=0;queue_writes={}
          local plan=history.default_owner_preflight(event,nil,true);assert(writes==0);history.default_owner_apply(plan)
          assert(player.technologies[ORDINARY].level==8 and not player.technologies[ORDINARY].enabled)
          assert(player.technologies[ORDINARY].saved_progress==.27 and player.worker_robots_storage_bonus==24)
          assert(player.current_research.name==OTHER and player.research_progress==.42 and queue_writes[1]==nil and storage.mir_worker_storage_route==old)
        ''')
        lua=self.world();lua.execute(r'''
          history.on_init(nil);seed_owner();player.technologies[CANONICAL].enabled=false;local b=all_frames();writes=0
          assert(not pcall(history.default_owner_preflight,owner_event("5.0.21011"),nil,true)and writes==0 and same(b,all_frames()))
        ''')


    def test_old_unpaid_public_route_retention_mutant_cannot_commit(self):
        source=(Path(__file__).resolve().parents[1]/"source/runtime/worker_robot_storage.lua").read_text()
        literal='if item.action == "transfer" then';self.assertEqual(source.count(literal),2)
        lua=self.world();lua.globals().mutant=source.replace(literal,'if item.action == "transfer" and item.source.next_level >= 5 then',1)
        lua.execute(r'''
          history=assert(load(mutant))();player.research_queue={CANONICAL,CANONICAL};player.research_progress=.37
          local ok,e=pcall(transfer)
          assert(not ok and tostring(e):find("native full default contribution",1,true)and storage[OWNER_KEY]==nil)
          assert(player.current_research.name==CANONICAL and player.research_progress==.37)
        ''')

    def test_owned_paid_scalar_and_cost_changes_update_only_valid_current_contract(self):
        for scalar in (0,2):
            lua=self.world();lua.globals().scalar=scalar
            lua.execute(r'''
              seed_owner();transfer();set_reward(scalar)
              prototypes.technology[CANONICAL].research_unit_energy=3600;prototypes.technology[ORDINARY].research_unit_energy=3600
              local before=all_frames();local contract=storage[OWNER_KEY].contract;writes=0
              local plan=history.default_owner_preflight({mod_startup_settings_changed=true,mod_changes={}},nil,true)
              assert(history.default_owner_apply(plan)and writes==0 and same(before,all_frames()))
              assert(storage[OWNER_KEY].contract~=contract and player.worker_robots_storage_bonus==20+4*scalar)
              assert(player.technologies[CANONICAL].level==5 and player.technologies[HEAD].level==5 and not player.technologies[HEAD].researched)
            ''')


class WorkerDefaultNativeLifecycleTests(unittest.TestCase):
    def world(self,target="f210"):
        return WorkerDefaultNativeOwnerTransferTests.world(self,target)

    def test_init_noop_unsupported_provider_and_manual_prepare_are_explicit(self):
        lua=self.world();lua.execute(r'''
          init_default();assert(history.needs_research_events());local b=all_frames();writes=0
          assert(not pcall(history.default_owner_preflight,{},provider_route(5),true))
          assert(not pcall(history.default_owner_preflight,{},nil,false))
          assert(not pcall(history.prepare,nil)and writes==0 and same(b,all_frames()))
        ''')
        lua=self.world();lua.execute(r'''
          game=nil;prototypes=nil;assert(history.default_owner_preflight({},provider_route(5),true)==nil)
          assert(history.default_owner_preflight({},nil,false)==nil and history.default_owner_apply(nil)==false)
        ''')

    def test_first_completion_sets_only_public_first_and_debit_both_native_representations(self):
        for target in ("f200","f210"):
            for scalar in (0,1,2):
                for representation in ("completed","advanced"):
                    lua=self.world(target);lua.globals().scalar=scalar;lua.globals().representation=representation
                    lua.execute(r'''
                      set_reward(scalar);init_default();player.research_queue={ORDINARY,ORDINARY,OTHER};player.research_progress=.37
                      suspended.technologies[ORDINARY].saved_progress=.27;suspended.research_queue={OTHER,ORDINARY};suspended.research_progress=.42
                      local other=frame(suspended);finish_frame(player,representation,{ORDINARY,OTHER},true)
                      local before=frame(player);assert(history.default_owner_on_research_finished(finish_event(player)))
                      local actual=frame(player)
                      assert(actual.source.level==5 and not actual.source.researched and not actual.source.enabled and actual.debit.level==5 and not actual.debit.researched)
                      assert(same(before.owner,actual.owner)and same(before.queue,actual.queue)and actual.progress==0 and actual.current==nil)
                      assert(actual.bonus==20+scalar and actual.bonus==before.bonus and same(other,frame(suspended)))
                      assert(queue_writes[1]==nil and progress_writes[1]==nil and not history.default_owner_mutating{force=player})
                    ''')

    def test_completed_still_current_progress_one_is_preserved_without_queue_or_progress_setter(self):
        for target in ("f200","f210"):
            lua=self.world(target);lua.execute(r'''
              init_default();player.research_queue={ORDINARY,ORDINARY,OTHER};player.research_progress=1
              player.technologies[ORDINARY].researched=true
              local before=frame(player);writes=0;queue_writes={};progress_writes={}
              assert(history.default_owner_on_research_finished(finish_event(player)))
              assert(player.current_research.name==ORDINARY and player.research_progress==1)
              assert(same(before.owner,frame(player).owner)and same(before.queue,frame(player).queue))
              assert(queue_writes[1]==nil and progress_writes[1]==nil and player.worker_robots_storage_bonus==21)
              -- This explicit completion representation never leaks into configuration/transfer admission.
              writes=0;assert(not pcall(history.default_owner_preflight,{mod_startup_settings_changed=false,mod_changes={}},nil,true)and writes==0)
            ''')

    def test_foreign_remainder_and_saved_work_stay_unstarted_in_finish_callback(self):
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(player,"completed",{OTHER,ORDINARY},true);player.technologies[OTHER].saved_progress=.19
          local b=frame(player);assert(history.default_owner_on_research_finished(finish_event(player)))
          assert(player.current_research==nil and player.research_progress==0 and player.technologies[OTHER].saved_progress==.19)
          assert(same(b.owner,frame(player).owner)and same(b.queue,frame(player).queue)and queue_writes[1]==nil and progress_writes[1]==nil)
        ''')

    def test_scripted_no_earned_bad_native_and_foreign_force_drift_refuse_before_writes(self):
        for change in ('event.by_script=true','event.by_script=nil',
                       'player.technologies[ORDINARY].level=4;player.technologies[ORDINARY].researched=false',
                       'player.research_progress=1.01','player.technologies[CANONICAL].saved_progress=.1','uninvested.technologies[HEAD].enabled=true'):
            lua=self.world();lua.execute(r'''
              init_default();finish_frame(player,"advanced",{},false);local event=finish_event(player)
            '''+change+r''';local before=all_frames();writes=0
              assert(not pcall(history.default_owner_on_research_finished,event)and writes==0 and same(before,all_frames()))
            ''')

    def test_later_owner_completions_do_not_duplicate_public_reward(self):
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(player,"advanced",{},false);assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].level=8;local b=all_frames();writes=0
          assert(not history.default_owner_on_research_finished(finish_event(player))and writes==0 and same(b,all_frames()))
          assert(player.worker_robots_storage_bonus==24 and player.technologies[CANONICAL].level==5)
        ''')

    def test_on_load_is_storage_only_and_malformed_fields_are_not_cached_work(self):
        lua=self.world();lua.execute(r'''
          init_default();local state=storage[OWNER_KEY]
          game=setmetatable({},{__index=function()error("game read")end});prototypes=setmetatable({},{__index=function()error("prototype read")end});writes=0
          for i=1,2 do history.on_load();history.default_owner_on_load(true);assert(storage[OWNER_KEY]==state and history.needs_research_events())end
          state.forces[1].progress=.37;assert(not pcall(history.default_owner_on_load,true)and writes==0)
        ''')

    def test_owned_setting_contract_changes_validate_current_pair_without_frozen_private_policy(self):
        lua=self.world();lua.execute(r'''
          init_default();local state=storage[OWNER_KEY];local oldcontract=state.contract;local before=all_frames()
          prototypes.technology[CANONICAL].research_unit_energy=3600;prototypes.technology[ORDINARY].research_unit_energy=3600
          prototypes.technology[CANONICAL].enabled=false;prototypes.technology[ORDINARY].enabled=false;history.configure(4,false);writes=0
          local plan=history.default_owner_preflight({mod_startup_settings_changed=true,mod_changes={}},nil,true)
          assert(plan.already_owned and history.default_owner_apply(plan)and writes==0 and same(before,all_frames()))
          assert(storage[OWNER_KEY].contract~=oldcontract and not player.technologies[CANONICAL].enabled)
          player.technologies[CANONICAL].visible_when_disabled=true;before=all_frames();writes=0
          assert(not history.default_owner_apply(history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)))
          assert(writes==0 and same(before,all_frames()))
        ''')

    def test_same_force_guard_skips_nested_callbacks_and_restores_after_setter_error(self):
        for fail in (False,True):
            lua=self.world();lua.globals().fail=fail;lua.execute(r'''
              init_default();finish_frame(player,"advanced",{},false)
              local c=player.technologies[CANONICAL];local mt=getmetatable(c);local write=mt.__newindex;local calls=0
              mt.__newindex=function(object,key,value)
                if key=="level"then
                  assert(history.default_owner_mutating{research={force=player}}and not history.default_owner_mutating{force=uninvested})
                  assert(history.default_owner_on_research_finished(finish_event(player))==false);calls=calls+1
                  if fail then error("injected native setter failure")end
                end
                write(object,key,value)
              end
              local ok,e=pcall(history.default_owner_on_research_finished,finish_event(player))
              assert(calls==1 and not history.default_owner_mutating{force=player})
              if fail then assert(not ok and tostring(e):find("injected native setter failure",1,true))else assert(ok and player.worker_robots_storage_bonus==21)end
            ''')

    def test_force_create_and_reset_use_empty_native_state_without_earned_replay(self):
        lua=self.world();lua.execute(r'''
          init_default();local fresh=make_force("fresh",5);install_force(fresh);game.forces.fresh=fresh;writes=0
          history.on_force_created{force=fresh};assert(history.default_owner_on_force_created{force=fresh})
          assert(storage[OWNER_KEY].forces[5].phase=="owned"and fresh.technologies[ORDINARY].level==4 and not fresh.technologies[CANONICAL].enabled)
          finish_frame(player,"advanced",{},false);history.default_owner_on_research_finished(finish_event(player));player.technologies[ORDINARY].level=8
          player.technologies[CANONICAL].level=4;player.technologies[ORDINARY].level=4;player.technologies[HEAD].level=4;player.technologies[HEAD].enabled=false
          history.on_force_reset{force=player};writes=0;assert(history.default_owner_on_force_reset{force=player})
          assert(player.technologies[ORDINARY].level==4 and not player.technologies[CANONICAL].enabled and player.worker_robots_storage_bonus==20)
        ''')

    def test_merge_changes_metadata_only_and_preserves_mixed_native_refusal(self):
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(player,"advanced",{},false);history.default_owner_on_research_finished(finish_event(player))
          game.forces.uninvested=nil;local before=all_frames();writes=0
          local ok,why=history.default_owner_on_forces_merged{source_index=2,destination=player}
          assert(ok and why=="native-merge-metadata-only"and writes==0 and same(before,all_frames())and storage[OWNER_KEY].forces[2]==nil)
        ''')
        lua=self.world();lua.execute(r'''
          init_default();game.forces.uninvested=nil;player.technologies[CANONICAL].enabled=true;player.research_queue={CANONICAL};player.research_progress=.2
          local before=all_frames();local state=storage[OWNER_KEY];writes=0
          local ok,why=history.default_owner_on_forces_merged{source_index=2,destination=player}
          assert(not ok and why=="unqualified-native-merge-frame"and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==state)
        ''')

    def test_cap_four_moves_unpaid_duplicates_before_policy_and_caps_actual_owner(self):
        lua=self.world();lua.execute(r'''
          history.on_init(nil);player.research_queue={CANONICAL,CANONICAL,OTHER};player.research_progress=.37;history.configure(4,true)
          local plan=history.default_owner_preflight(owner_event("5.0.21011"),nil,true);assert(plan.items[1].moved)
          history.default_owner_apply(plan);assert(player.current_research.name==ORDINARY and player.research_progress==.37)
          local caps=require("runtime.caps");local rights={};caps.reconcile(player,{[CANONICAL]=4,[ORDINARY]=4},rights)
          assert(#player.research_queue==2 and player.current_research.name==ORDINARY and player.research_progress==.37)
          finish_frame(player,"advanced",{OTHER},true);history.default_owner_on_research_finished(finish_event(player))
          assert(queue_writes[1]==nil and progress_writes[1]==nil)
          gaps[1]=false;caps.reconcile(player,{[CANONICAL]=4,[ORDINARY]=4},rights)
          assert(not player.technologies[ORDINARY].enabled and player.technologies[CANONICAL].level==5 and player.worker_robots_storage_bonus==21)
        ''')

class WorkerFullDefaultProviderHandoverTests(unittest.TestCase):
    def world(self,target="f210"):
        lua=WorkerDefaultNativeOwnerTransferTests.world(self,target)
        lua.execute(r'''
          prototypes.technology[ID].visible_when_disabled=false
          function full_source(a,unpaid_pending)
            history.on_init(nil);set_reward(a);seed_owner()
            if unpaid_pending then uninvested.technologies[CANONICAL].enabled=true;uninvested.research_queue={CANONICAL};uninvested.research_progress=.37 end
            transfer();writes=0;queue_writes={};progress_writes={}
          end
          function provider_event()
            return {mod_startup_settings_changed=false,mod_changes={provider={new_version="1.0"}}}
          end
          function finite_entry(b)
            script.active_mods.provider="1.0";add_provider(5)
            creators["worker-robots-storage-6"]="more-infinite-research"
            local public=prototypes.technology[CANONICAL]
            public.effects[1].modifier=b;public.research_unit_count_formula=nil;public.research_unit_count=1000
            public.research_unit_energy=3600;public.research_unit_ingredients={{name="automation-science-pack",amount=1},{name="space-science-pack",amount=1}}
            prototypes.technology[HEAD].effects[1].modifier=b==0 and 0 or -b
            for _,f in pairs(game.forces)do
              local c=f.technologies[CANONICAL];local paid=f.technologies[HEAD].level==5;local enabled,visible=c.enabled,c.visible_when_disabled
              -- Explicit host representation of already-loaded finite4, not a claim of new engine observation.
              c.level=4;c.researched=paid;c.enabled=enabled;c.visible_when_disabled=visible
              local mt=getmetatable(c);local read=mt.__index
              mt.__index=function(object,key)if key=="research_unit_count"then return 1000 end;return read(object,key)end
            end
            writes=0;queue_writes={};progress_writes={}
          end
          function delegate(event,route)
            event,route=event or provider_event(),route or provider_route(5)
            local plan=history.default_owner_preflight(event,route,true)
            assert(history.default_owner_delegated(plan))
            local legacy=history.preflight(event,route,plan)
            return plan,legacy
          end
          function handover(event,route)
            local plan,legacy=delegate(event,route)
            assert(history.default_owner_apply(plan));history.apply(legacy)
            return plan,legacy
          end
          function foreign_frames()
            local out={}
            for _,f in pairs(game.forces)do local rows={}
              for n=5,6 do local t=f.technologies['worker-robots-storage-'..n];rows[n]={level=t.level,researched=t.researched,enabled=t.enabled,saved=t.saved_progress}end
              out[f.index]=rows
            end
            return out
          end
        ''')
        return lua

    def test_four_force_handover_reuses_private_quota_and_conserves_each_scalar_basis(self):
        for target in ("f200","f210"):
            for a,b in ((0,0),(0,2),(1,1),(2,0),(2,2)):
                lua=self.world(target);lua.globals().a=a;lua.globals().b=b
                lua.execute(r'''
                  full_source(a,true);finite_entry(b);local before=all_frames();local foreign=foreign_frames()
                  local oldkey=storage.mir_worker_storage_route;local plan,legacy=delegate()
                  assert(writes==0 and same(before,all_frames())and storage.mir_worker_storage_route==oldkey)
                  assert(plan.kind=="default-native-provider-handover" and history.plan_prepared(legacy))
                  assert(history.default_owner_apply(plan)and storage.mir_worker_storage_route==oldkey)
                  assert(storage[OWNER_KEY].kind=="provider-retired"and not history.needs_research_events())
                  history.apply(legacy);local quota=storage.mir_worker_storage_route
                  assert(quota.schema==2 and quota.kind=="prepared"and quota.phase=="provider")
                  assert(history.needs_research_events()and same(foreign,foreign_frames()))
                  for _,f in pairs(game.forces)do local old,now=before[f.index],frame(f);local p=f.technologies[ID];local r=quota.forces[f.index]
                    assert(p.level==old.owner.level and not p.researched and p.saved_progress==old.owner.saved)
                    assert(f.technologies[ORDINARY].level==4 and not f.technologies[ORDINARY].researched and not f.technologies[ORDINARY].enabled)
                    assert(f.technologies[ORDINARY].saved_progress==0 and not f.technologies[ORDINARY].visible_when_disabled)
                    assert(now.bonus==old.bonus and now.other_saved==old.other_saved and same(now.debit,old.debit))
                    assert(now.source.level==old.source.level and now.source.researched==old.source.researched and now.source.saved==0)
                    assert(r.next_level==old.owner.level and r.pending and r.enabled==old.owner.enabled and r.visible==old.owner.visible)
                  end
                  assert(quota.forces[1].limit==8 and quota.forces[2].limit==4 and quota.forces[3].limit==7 and quota.forces[4].limit==6)
                  assert(player.current_research.name==ID and player.research_progress==.375 and player.research_queue[2].name==OTHER)
                  assert(uninvested.current_research.name==ID and uninvested.research_progress==.37)
                  assert(suspended.current_research.name==OTHER and suspended.research_progress==.42 and suspended.research_queue[2].name==ID)
                  assert(detached.current_research.name==OTHER and detached.research_progress==.625 and detached.technologies[ID].saved_progress==.23)
                  writes=0;assert(not history.default_owner_apply(plan));history.apply(legacy);assert(writes==0)
                ''')

    def test_unpaid_private_finish_earns_old_scalar_without_foreign_first_or_head_debit(self):
        lua=self.world();lua.execute(r'''
          full_source(2,true);finite_entry(1);handover()
          local f=uninvested;local c,h=f.technologies[CANONICAL],f.technologies[HEAD]
          assert(not c.researched and not h.researched and f.worker_robots_storage_bonus==20)
          f.research_queue={OTHER};f.research_progress=.23;f.technologies[ID].level=5
          local before=tech_frame(c);local head=tech_frame(h)
          assert(history.on_research_event({research=f.technologies[ID],by_script=false},true))
          assert(not history.default_owner_on_research_finished({research=f.technologies[ID],by_script=false}))
          assert(f.worker_robots_storage_bonus==22 and not f.technologies[ID].enabled)
          assert(same(before,tech_frame(c))and same(head,tech_frame(h))and not c.researched and not h.researched)
          assert(not storage.mir_worker_storage_route.forces[f.index].pending)
        ''')

    def test_boolean_startup_flags_preserve_four_force_authority_and_work(self):
        for target in ("f200", "f210"):
            for changed in (False, True):
                lua=self.world(target);lua.globals().changed=changed
                lua.execute(r'''
                  full_source(2,true);finite_entry(1);history.configure(8,true)
                  local event=provider_event();event.mod_startup_settings_changed=changed
                  local before=all_frames();local old=storage[OWNER_KEY];local key=storage.mir_worker_storage_route
                  local plan,legacy=delegate(event)
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==old and storage.mir_worker_storage_route==key)
                  history.default_owner_apply(plan);history.apply(legacy)
                  for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                    assert(a.bonus==b.bonus and a.other_saved==b.other_saved and same(a.debit,b.debit))
                    assert(a.private.level==b.owner.level and a.private.saved==b.owner.saved)
                    assert(same(a.queue,(function()local q=copy(b.queue);for i,n in ipairs(q)do if n==ORDINARY then q[i]=ID end end;return q end)()))
                    assert(a.current==(b.current==ORDINARY and ID or b.current)and a.progress==b.progress)
                  end
                  assert(storage.mir_worker_storage_route.cap==8 and storage.mir_worker_storage_route.family_enabled)
                ''')

    def test_missing_or_nonboolean_startup_flags_refuse_with_context_before_writes(self):
        for value, label in (("nil", "unknown"), ('"true"', "true"), ('"false"', "false"), ("1", "1")):
            lua=self.world();lua.globals().label=label
            lua.execute('full_source(1,true);finite_entry(1);local event=provider_event();event.mod_startup_settings_changed='+value+r'''
              local before=all_frames();local old=storage[OWNER_KEY];local key=storage.mir_worker_storage_route
              local ok,message=pcall(history.default_owner_preflight,event,provider_route(5),true)
              assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==old and storage.mir_worker_storage_route==key)
              assert(tostring(message):find("startup_changed="..label,1,true))
              assert(tostring(message):find("startup_type="..type(event.mod_startup_settings_changed),1,true))
              assert(tostring(message):find("new_mir=5.0.21012",1,true)and tostring(message):find("expected_mir=5.0.21012",1,true))
            ''')

    def test_current_pending_policy_rejects_disabled_overcap_and_last_force_before_writes(self):
        cases=(('history.configure(0,false)', "enabled=false"),
               ('history.configure(7,true)', "limit=8"),
               ('player.research_queue={ORDINARY,ORDINARY,OTHER};player.research_progress=.375;history.configure(8,true)', "limit=9"),
               ('detached.technologies[ORDINARY].level=9;detached.technologies[ORDINARY].saved_progress=.23;history.configure(8,true)', "limit=9"))
        for change, detail in cases:
            lua=self.world();lua.globals().detail=detail
            lua.execute('full_source(1,true);finite_entry(1);'+change+r'''
              local event=provider_event();event.mod_startup_settings_changed=true
              local before=all_frames();local old=storage[OWNER_KEY];local key=storage.mir_worker_storage_route;writes=0
              local ok,message=pcall(history.default_owner_preflight,event,provider_route(5),true)
              assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==old and storage.mir_worker_storage_route==key)
              assert(tostring(message):find("pending default worker work exceeds the current enabled/cap policy",1,true))
              assert(tostring(message):find(detail,1,true))
            ''')

    def test_no_pending_rights_do_not_require_enabled_or_unlimited_current_policy(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(1)
          for _,f in pairs(game.forces)do f.research_queue={OTHER};f.research_progress=.42;f.technologies[ORDINARY].saved_progress=0 end
          history.configure(4,false);writes=0
          local event=provider_event();event.mod_startup_settings_changed=true;local before=all_frames()
          handover(event)
          for _,f in pairs(game.forces)do local r=storage.mir_worker_storage_route.forces[f.index]
            assert(not r.pending and not r.enabled and r.limit==before[f.index].owner.level-1)
            assert(f.worker_robots_storage_bonus==before[f.index].bonus and f.research_progress==.42)
          end
        ''')

    def test_true_startup_flag_does_not_admit_changed_contract_or_stale_policy(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(1);local event=provider_event();event.mod_startup_settings_changed=true
          prototypes.technology[ORDINARY].research_unit_count_formula="101*2^(L-4)"
          local before=all_frames();local old=storage[OWNER_KEY];writes=0
          assert(not pcall(history.default_owner_preflight,event,provider_route(5),true)and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==old)
        ''')
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(1);history.configure(8,true)
          local event=provider_event();event.mod_startup_settings_changed=true;local plan,legacy=delegate(event)
          history.configure(7,true);local before=all_frames();local old=storage[OWNER_KEY];writes=0
          assert(not pcall(history.default_owner_apply,plan)and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==old)
        ''')

    def test_repeated_and_detached_partial_work_use_existing_resume_and_retirement(self):
        lua=self.world();lua.execute(r'''
          full_source(1,false);player.research_queue={ORDINARY,ORDINARY,OTHER};player.research_progress=.375
          finite_entry(2);handover();assert(storage.mir_worker_storage_route.forces[1].limit==9)
          local f=player;f.research_queue={ID,OTHER};f.research_progress=.25;f.technologies[ID].level=9
          history.on_research_event({research=f.technologies[ID],by_script=false},true)
          assert(storage.mir_worker_storage_route.forces[1].pending and f.technologies[ID].enabled)
          f.research_queue={OTHER};f.research_progress=.41;f.technologies[ID].level=10
          history.on_research_event({research=f.technologies[ID],by_script=false},true)
          assert(not storage.mir_worker_storage_route.forces[1].pending and not f.technologies[ID].enabled)
          local d=detached;assert(history.resume(d,provider_route(5)))
          assert(d.research_queue[2].name==ID and d.research_progress==.625 and d.technologies[ID].saved_progress==.23)
          d.research_queue={OTHER};d.research_progress=.625;d.technologies[ID].level=7
          history.on_research_event({research=d.technologies[ID],by_script=false},true)
          assert(not storage.mir_worker_storage_route.forces[4].pending and not d.technologies[ID].enabled)
        ''')

    def test_public_disablement_release_requires_actual_recorded_positive_right(self):
        cases=((True,True,False,True,1),(False,True,False,False,0),(True,False,False,False,0),(True,True,True,True,0))
        for original,proto,incoming,expected,count in cases:
            with self.subTest(original=original,proto=proto,incoming=incoming):
                lua=self.world();lua.globals().original=original;lua.globals().proto=proto;lua.globals().incoming=incoming;lua.globals().expected=expected;lua.globals().count=count
                lua.execute(r'''
                  history.on_init(nil);set_reward(1);seed_owner()
                  if not original then player.research_queue={OTHER};player.research_progress=.42;player.technologies[CANONICAL].enabled=false end
                  transfer();finite_entry(2);prototypes.technology[CANONICAL].enabled=proto;player.technologies[CANONICAL].enabled=incoming
                  local c=player.technologies[CANONICAL];local before=tech_frame(c);local head=tech_frame(player.technologies[HEAD])
                  local mt=getmetatable(c);local write=mt.__newindex;local n=0
                  mt.__newindex=function(o,k,v)if k=="enabled"then n=n+1 end;return write(o,k,v)end
                  handover();assert(c.enabled==expected and n==count)
                  before.enabled=expected;assert(same(before,tech_frame(c))and same(head,tech_frame(player.technologies[HEAD])))
                ''')

    def test_malformed_origin_contract_native_and_route_opponents_refuse_before_writes(self):
        opponents=[
          'prototypes.technology[ORDINARY].research_unit_count_formula="101*2^(L-4)"',
          'prototypes.technology[ID].research_unit_energy=3600','prototypes.technology[ID].hidden=false',
          'prototypes.technology[HEAD].effects[1].modifier=1','prototypes.technology[CANONICAL].effects[2]={type="worker-robot-storage",modifier=1,hidden=false}',
          'prototypes.technology[CANONICAL].effects[1].type="worker-robot-speed"','creators[ORDINARY]="foreign"',
          'creators[ID]="foreign"','creators[HEAD]="foreign"','creators[CANONICAL]="wrong"',
          'creators["worker-robots-storage-6"]="wrong"','prototypes.technology["worker-robots-storage-5"].max_level=6',
          'player.technologies[CANONICAL].researched=false','uninvested.technologies[CANONICAL].researched=true',
          'player.technologies[HEAD].level=4','player.technologies[CANONICAL].saved_progress=.1',
          'detached.technologies[ID].saved_progress=.1','suspended.technologies[ID].enabled=true',
          'event.mod_startup_settings_changed="true"','event.mod_changes["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21012"}','event.mod_changes.provider.old_version="0.9"',
          'event.mod_changes.provider.new_version="2.0"','event.mod_changes.other={old_version="1",new_version="2"};script.active_mods.other="2"',
          'script.active_mods["more-infinite-research"]="5.0.21013"','route.finite[1].provider="unknown"',
          'storage[OWNER_KEY].contract="unknown"','storage.mir_worker_storage_route.current={kind="external",provider="old"}',
          'route=nil']
        for change in opponents:
            with self.subTest(change=change):
                lua=self.world();lua.execute('full_source(1,true);finite_entry(2);local event=provider_event();local route=provider_route(5);'+change+r'''
                  local before=all_frames();local old=storage[OWNER_KEY];local key=storage.mir_worker_storage_route;writes=0
                  assert(not pcall(history.default_owner_preflight,event,route,true))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==old and storage.mir_worker_storage_route==key)
                ''')

    def test_no_owner_or_fresh_provider_cannot_borrow_old_default_authority(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(1);storage[OWNER_KEY]=nil;local b=all_frames();writes=0
          assert(history.default_owner_preflight(provider_event(),provider_route(5),true)==nil)
          assert(not pcall(history.preflight,provider_event(),provider_route(5))and writes==0 and same(b,all_frames()))
          assert(not history.default_owner_delegated{kind="default-native-provider-handover"})
        ''')
        lua=self.world();lua.execute(r'''
          finite_entry(1);for _,f in pairs(game.forces)do f.technologies[ORDINARY].enabled=false;f.technologies[ORDINARY].visible_when_disabled=false end
          local b=all_frames();writes=0;history.on_init(provider_route(5));assert(not history.default_owner_on_init(provider_route(5),true))
          assert(storage[OWNER_KEY]==nil and storage.mir_worker_storage_route.schema==1 and same(b,all_frames())and writes==0)
        ''')

    def test_token_and_apply_order_cannot_commit_half_private_state(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(2);local before=all_frames();local old=storage.mir_worker_storage_route
          local plan=history.default_owner_preflight(provider_event(),provider_route(5),true)
          assert(not pcall(history.default_owner_apply,plan)and writes==0 and same(before,all_frames()))
          assert(not pcall(history.preflight,provider_event(),provider_route(5),{kind=plan.kind}))
          local legacy=history.preflight(provider_event(),provider_route(5),plan)
          assert(not pcall(history.apply,legacy)and writes==0 and storage.mir_worker_storage_route==old)
          assert(history.default_owner_apply(plan)and storage.mir_worker_storage_route==old)
          local copied=copy(legacy);assert(not pcall(history.apply,copied)and storage.mir_worker_storage_route==old)
          history.apply(legacy);assert(storage.mir_worker_storage_route.kind=="prepared")
        ''')

    def test_stale_last_force_and_changed_quota_refuse_before_first_native_setter(self):
        for change in ('detached.technologies[ORDINARY].saved_progress=.29','foreign_bonus[4]=21',
                       'detached.technologies[HEAD].level=4','plan.prepared.forces[1].limit=99',
                       'legacy.state.forces[1].limit=99','plan.event.mod_startup_settings_changed=true'):
            with self.subTest(change=change):
                lua=self.world();lua.execute('full_source(1,true);finite_entry(1);local plan,legacy=delegate();'+change+r'''
                  local b=all_frames();local old=storage[OWNER_KEY];writes=0
                  assert(not pcall(history.default_owner_apply,plan)and writes==0 and same(b,all_frames())and storage[OWNER_KEY]==old)
                ''')

    def test_native_frame_change_between_handover_and_quota_commit_refuses_metadata_write(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(2);local plan,legacy=delegate();history.default_owner_apply(plan)
          player.research_progress=.5;local b=all_frames();local old=storage.mir_worker_storage_route;writes=0
          assert(not pcall(history.apply,legacy)and writes==0 and same(b,all_frames())and storage.mir_worker_storage_route==old)
        ''')

    def test_provider_retired_load_and_default_callbacks_are_storage_only_or_noops(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(1);handover();local owner=storage[OWNER_KEY];local key=storage.mir_worker_storage_route
          local actualgame,actualprototypes=game,prototypes;game=setmetatable({},{__index=function()error("game read")end})
          prototypes=setmetatable({},{__index=function()error("prototype read")end});writes=0
          history.on_load();history.default_owner_on_load();assert(history.needs_research_events()and writes==0)
          assert(not history.default_owner_on_force_created{force=player}and not history.default_owner_on_force_reset{force=player})
          assert(not history.default_owner_on_forces_merged{source_index=2,destination=player})
          assert(not history.default_owner_on_research_finished{research=player.technologies[ORDINARY],by_script=true})
          assert(storage[OWNER_KEY]==owner and storage.mir_worker_storage_route==key)
          game,prototypes=actualgame,actualprototypes
        ''')

    def test_same_provider_config_does_not_repeat_release_and_removal_or_change_refuses(self):
        lua=self.world();lua.execute(r'''
          full_source(1,true);finite_entry(1);handover();player.technologies[CANONICAL].enabled=false
          local b=all_frames();writes=0
          assert(history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},provider_route(5),true)==nil)
          history.apply(history.preflight({},provider_route(5)));assert(writes==0 and same(b,all_frames())and not player.technologies[CANONICAL].enabled)
          for _,route in ipairs{provider_route(6),provider_route(8)}do assert(not pcall(history.default_owner_preflight,{},route,true))end
          assert(not pcall(history.default_owner_preflight,{},nil,true))
          assert(not pcall(history.default_owner_preflight,{mod_changes={provider={old_version="1.0",new_version="2.0"}}},provider_route(5),true))
        ''')

    def test_scoped_transfer_guard_restores_on_nested_callback_and_setter_error(self):
        for fail in (False,True):
            lua=self.world();lua.globals().fail=fail;lua.execute(r'''
              full_source(1,true);finite_entry(1);local plan,legacy=delegate();local oldkey=storage.mir_worker_storage_route
              local mt=getmetatable(player.technologies[ID]);local write=mt.__newindex;local checks=0
              mt.__newindex=function(o,k,v)
                if k=="level"then
                  assert(history.default_owner_mutating{force=player}and not history.default_owner_mutating{force=uninvested})
                  assert(not history.on_research_event{research=player.technologies[ID],by_script=true})
                  assert(not history.default_owner_on_research_finished{research=player.technologies[ORDINARY],by_script=true})
                  assert(storage.mir_worker_storage_route==oldkey);checks=checks+1
                  if fail then error("injected provider native setter")end
                end
                write(o,k,v)
              end
              local ok,e=pcall(history.default_owner_apply,plan)
              assert(checks==1 and not history.default_owner_mutating{force=player})
              if fail then assert(not ok and tostring(e):find("injected provider native setter",1,true)and storage.mir_worker_storage_route==oldkey)
              else assert(ok);history.apply(legacy)end
            ''')

    def test_completed_owner_cursor_normalizes_without_inventing_any_unfinished_quota(self):
        lua=self.world();lua.execute(r'''
          full_source(2,false);player.research_queue={OTHER};player.research_progress=.45
          player.technologies[ORDINARY].saved_progress=0;player.technologies[ORDINARY].researched=true
          finite_entry(1);local before=all_frames();handover()
          local quota=storage.mir_worker_storage_route;local p=player.technologies[ID]
          assert(p.level==9 and not p.researched and not p.enabled and p.saved_progress==0)
          assert(quota.forces[1].next_level==9 and quota.forces[1].limit==8 and not quota.forces[1].pending)
          assert(player.worker_robots_storage_bonus==before[1].bonus and player.worker_robots_storage_bonus==30)
          assert(player.current_research.name==OTHER and player.research_progress==.45)
          assert(quota.forces[2].next_level==4 and quota.forces[2].limit==3 and not quota.forces[2].pending)
          assert(uninvested.technologies[ID].level==4 and not uninvested.technologies[ID].enabled and uninvested.worker_robots_storage_bonus==20)
        ''')

class WorkerInfiniteHeadDebitTests(unittest.TestCase):
    def world(self,target="f210"):
        return WorkerFullDefaultProviderHandoverTests.world(self,target)

    def test_zero_two_scalar_native_debit_count_is_one_or_zero_across_handover(self):
        for target in ("f200","f210"):
            for a,b in ((0,0),(0,2),(2,0),(2,2)):
                lua=self.world(target);lua.globals().a=a;lua.globals().b=b;lua.execute(r'''
                  full_source(a,true)
                  local paid={}
                  for _,f in pairs(game.forces)do local t,h=f.technologies[ORDINARY],f.technologies[HEAD]
                    paid[f.index]=t.level>=5
                    assert(h.level==(paid[f.index]and 5 or 4)and not h.researched and not h.enabled and not h.visible_when_disabled)
                    assert(h.saved_progress==0 and h.research_unit_count==1 and f.worker_robots_storage_bonus==20+(t.level-4)*a)
                  end
                  finite_entry(b);local before=all_frames();handover()
                  for _,f in pairs(game.forces)do local h=f.technologies[HEAD]
                    assert(h.level==(paid[f.index]and 5 or 4)and not h.researched and not h.enabled and h.saved_progress==0)
                    assert(f.worker_robots_storage_bonus==before[f.index].bonus)
                  end
                ''')

    def test_finite_or_malformed_native_head_cannot_be_adopted_before_writes(self):
        changes=('h.level=3;h.enabled=false','h.level=6;h.enabled=false','h.level=4.5;h.enabled=false',
                 'h.level=5;h.enabled=false','h.researched=true','h.saved_progress=.01',
                 'h.enabled=true','h.visible_when_disabled=true',
                 'h.enabled=true;player.research_queue={h};h.enabled=false',
                 'h.enabled=true;player.research_queue={OTHER,h};h.enabled=false',
                 'prototypes.technology[HEAD].max_level=4','prototypes.technology[HEAD].research_unit_count_formula="1"')
        for target in ("f200","f210"):
            for change in changes:
                with self.subTest(target=target,change=change):
                    lua=self.world(target);lua.execute('seed_owner();local h=player.technologies[HEAD];'+change+r'''
                      local before=all_frames();writes=0
                      local ok=pcall(history.plan_default_owner_transfer,owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011"),nil,false)
                      assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                    ''')

    def test_retired_provider_validates_bounded_infinite_head_and_cold_load_does_not_repair_it(self):
        for change in ('h.level=6;h.enabled=false','h.researched=true','h.saved_progress=.01',
                       'h.enabled=true;player.research_queue={OTHER,h};h.enabled=false'):
            lua=self.world();lua.execute('full_source(1,true);finite_entry(2);handover();local h=player.technologies[HEAD];'+change+r'''
              local before=all_frames();local owner=storage[OWNER_KEY];local key=storage.mir_worker_storage_route;writes=0
              local original_game,original_prototypes=game,prototypes
              game=setmetatable({},{__index=function()error("on_load game read")end})
              prototypes=setmetatable({},{__index=function()error("on_load prototype read")end})
              history.on_load();history.default_owner_on_load()
              game,prototypes=original_game,original_prototypes
              assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==owner and storage.mir_worker_storage_route==key)
              assert(not pcall(history.default_owner_preflight,{mod_startup_settings_changed=false,mod_changes={}},provider_route(5),true))
              assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==owner and storage.mir_worker_storage_route==key)
            ''')

    def test_first_debit_level_write_restores_hidden_flags_and_scoped_guard_even_on_error(self):
        for fail in (False,True):
            lua=self.world();lua.globals().fail=fail;lua.execute(r'''
              init_default();finish_frame(player,"advanced",{OTHER},true)
              local h=player.technologies[HEAD];local mt=getmetatable(h);local write=mt.__newindex;local seen=0
              mt.__newindex=function(o,k,v)
                if k=="level"then
                  seen=seen+1;assert(v==5 and history.default_owner_mutating{force=player})
                  assert(not history.default_owner_mutating{force=uninvested})
                  assert(not history.default_owner_on_research_finished{research=h,by_script=true})
                  if fail then error("injected debit setter failure")end
                end
                write(o,k,v)
                if k=="level"then assert(h.enabled and h.researched==false)end
              end
              local ok,message=pcall(history.default_owner_on_research_finished,finish_event(player))
              assert(seen==1 and not history.default_owner_mutating{force=player})
              assert(queue_writes[1]==nil and progress_writes[1]==nil)
              if fail then assert(not ok and tostring(message):find("injected debit setter failure",1,true))
              else assert(ok and h.level==5 and not h.researched and not h.enabled and not h.visible_when_disabled and player.worker_robots_storage_bonus==21)end
            ''')


class WorkerOlderDefaultAdmissionTests(unittest.TestCase):
    """Separate all-force501-empty and473-paid-idle source restrictions."""

    world = WorkerDefaultNativeOwnerTransferTests.world

    def older_world(self, target="f200"):
        lua = self.world(target)
        lua.execute(r'''
          for _,id in ipairs({CANONICAL,ORDINARY,ID})do
            prototypes.technology[id].research_unit_count_formula="675*1.5^(L-4)"
            prototypes.technology[id].research_unit_energy=3600
            for _,force in pairs(game.forces)do
              local t=force.technologies[id];local mt=getmetatable(t);local read=mt.__index
              mt.__index=function(object,key)
                if key=="research_unit_count"then return math.floor(675*1.5^(read(object,"level")-4))end
                return read(object,key)
              end
            end
          end
          function older_event(old,addition)
            local event=owner_event(old)
            if addition then script.active_mods["test-observer"]="0.1.0"
              event.mod_changes["test-observer"]={new_version="0.1.0"}end
            return event
          end
          function paid_idle()
            player.technologies[CANONICAL].level=5;uninvested.technologies[CANONICAL].level=5
            suspended.technologies[CANONICAL].level=6
            player.research_queue={OTHER};player.research_progress=.42
            suspended.research_queue={OTHER};suspended.research_progress=.125
            detached.technologies[OTHER].saved_progress=.27
            uninvested.technologies[CANONICAL].enabled=false
            writes=0;queue_writes={};progress_writes={}
          end
          function older_plan(event)return history.plan_default_owner_transfer(event,nil,false)end
          function refuse_older(event,route)
            local before=all_frames();writes=0
            assert(not pcall(history.plan_default_owner_transfer,event,route,false))
            assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
          end
        ''')
        return lua

    def test_501_empty_all_forces_admits_new_observer_without_zero_aggregate_inference(self):
        lua=self.older_world();lua.execute(r'''
          player.research_queue={OTHER};player.research_progress=.42
          uninvested.technologies[CANONICAL].enabled=false
          local event=older_event("5.0.20001",true);local before=all_frames();writes=0
          queue_writes={};progress_writes={}
          local plan=older_plan(event);assert(writes==0 and same(before,all_frames()))
          assert(plan.record.producer.kind=="older-mir501-empty-default")
          assert(history.apply_default_owner_transfer(plan))
          for _,f in pairs(game.forces)do
            local a,b=frame(f),before[f.index]
            assert(a.owner.level==4 and not a.owner.researched and not a.debit.researched)
            assert(a.owner.enabled==b.source.enabled and a.bonus==b.bonus and a.bonus==20)
            assert(a.current==b.current and a.progress==b.progress and same(a.queue,b.queue))
          end
          assert(queue_writes[1]==nil and storage[OWNER_KEY].producer.old_version=="5.0.20001")
        ''')

    def test_473_paid_idle_preserves_native_levels_and_foreign_work(self):
        lua=self.older_world();lua.execute(r'''
          paid_idle();local event=older_event("4.7.20003",true);local before=all_frames()
          local plan=older_plan(event);assert(writes==0 and plan.record.producer.kind=="published473-idle-default")
          assert(history.apply_default_owner_transfer(plan))
          for _,f in pairs(game.forces)do
            local a,b=frame(f),before[f.index];local n=b.source.level
            assert(a.owner.level==n and a.owner.count==b.source.count and a.owner.enabled==b.source.enabled)
            assert(a.debit.level==(n>=5 and 5 or 4)and not a.debit.researched and a.bonus==b.bonus and same(a.private,b.private))
            assert(a.current==b.current and a.progress==b.progress and same(a.queue,b.queue))
            assert(a.other_saved==b.other_saved and queue_writes[f.index]==nil)
          end
          assert(player.technologies[ORDINARY].level==5 and player.technologies[ORDINARY].research_unit_count==1012)
          assert(player.worker_robots_storage_bonus==21 and not uninvested.technologies[ORDINARY].enabled)
        ''')

    def test_one_force_paid_501_and_any_pending_older_work_refuse_before_writes(self):
        for old, opponents in (("5.0.20001", (
                'detached.technologies[CANONICAL].level=5',
                'detached.technologies[CANONICAL].researched=true')),
                ("4.7.20003", ())):
            for opponent in opponents + (
                    'detached.technologies[CANONICAL].saved_progress=.1',
                    'detached.research_queue={CANONICAL}',
                    'detached.research_queue={OTHER,CANONICAL}'):
                with self.subTest(old=old, opponent=opponent):
                    lua=self.older_world();lua.globals().old=old
                    lua.execute(opponent+';refuse_older(older_event(old,true))')

    def test_older_previous_profile_engine_event_and_current_route_opponents(self):
        opponents=(
            'script.active_mods.foreign="1"',
            'script.active_mods.foreign="1";event.mod_changes.foreign={old_version="1",new_version="1"}',
            'event.mod_changes.removed={old_version="1"}',
            'script.active_mods.foreign="2";event.mod_changes.foreign={old_version="1",new_version="2"}',
            'script.active_mods["test-observer"]="0.2.0"',
            'event.mod_changes.base={old_version="2.0.76",new_version="2.0.77"}',
            'event.mod_changes.base={new_version="2.0.77"}',
            'event.mod_startup_settings_changed=true',
            'event.mod_changes["more-infinite-research"].new_version="5.0.20013"',
            'script.active_mods.base="2.0.78"',
            'script.active_mods["space-age"]="2.0.77";event.mod_changes["space-age"]={new_version="2.0.77"}',
            'creators[CANONICAL]="foreign"',
            'add_provider(7);route=provider_route(7)',
            'detached.technologies[ID].level=5',
            'detached.technologies[ORDINARY].saved_progress=.1')
        for old in ("5.0.20001","4.7.20003"):
            for opponent in opponents:
                with self.subTest(old=old, opponent=opponent):
                    lua=self.older_world();lua.globals().old=old
                    lua.execute('local event=older_event(old,true);local route=nil;'+opponent+';refuse_older(event,route)')
        for target, old in (("f210","5.0.21042"),("f210","4.7.21003"),("f200","5.0.20043"),("f200","4.7.20002")):
            lua=self.older_world(target);lua.globals().old=old;lua.execute('refuse_older(older_event(old))')

    def test_473_requires_each_resolved_default_worker_value_and_selected_caps(self):
        opponents=('values.base_cost=201','values.growth_factor=2','values.linear_increment=1',
            'values.research_time=0','values.effect_percent=2','values.max_level=4','values.enabled=false',
            'history.configure(4,true)','history.configure(0,false)',
            'set_reward(0)','prototypes.technology[CANONICAL].level=5')
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua=self.older_world();lua.execute('paid_idle();local values=require("runtime.configuration").streams["worker-robots-storage"];'+
                    opponent+';refuse_older(older_event("4.7.20003",true))')

    def test_473_imported_profile_uses_actual_resolver_instead_of_raw_default_settings(self):
        lua=self.older_world();lua.execute(r'''
          settings={startup={
            ["mir-enable-worker-robots-storage"]={value=true},["mir-cost-base-worker-robots-storage"]={value=200},
            ["mir-cost-growth-worker-robots-storage"]={value=1.5},["mir-cost-linear-increment-worker-robots-storage"]={value=0},
            ["mir-research-time-worker-robots-storage"]={value=60},["mir-effect-per-level-worker-robots-storage"]={value=1},
            ["mir-max-level-worker-robots-storage"]={value=0},["mir-settings-profile-import"]={value="MIRSET1:host-profile"}}}
          helpers={encode_string=function(s)return s end,decode_string=function(s)return s end,
            json_to_table=function()return{schema=1,kind="mir-settings-profile",settings={
              ["mir-effect-per-level-worker-robots-storage"]=2}}end}
          package.loaded["runtime.configuration"]=nil;package.loaded["runtime.worker_robot_storage"]=nil
          history=require("runtime.worker_robot_storage")
          assert(settings.startup["mir-effect-per-level-worker-robots-storage"].value==1)
          assert(require("runtime.configuration").streams["worker-robots-storage"].effect_percent==2)
          paid_idle();refuse_older(older_event("4.7.20003",true))
        ''')

    def test_saved_older_producer_kinds_are_strict_and_cold_validation_is_storage_only(self):
        for old, kind in (("5.0.20001","older-mir501-empty-default"),("4.7.20003","published473-idle-default")):
            lua=self.older_world();lua.globals().old=old;lua.globals().kind=kind
            lua.execute(r'''
              if old=="4.7.20003"then paid_idle()end
              history.apply_default_owner_transfer(older_plan(older_event(old,true)))
              local saved=storage[OWNER_KEY];assert(saved.producer.kind==kind)
              writes=0;local original_game,original_prototypes=game,prototypes
              game=setmetatable({}, {__index=function()error("cold native game read")end})
              prototypes=setmetatable({}, {__index=function()error("cold prototype read")end})
              for i=1,2 do package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage")
                history.default_owner_on_load();assert(storage[OWNER_KEY]==saved and writes==0)end
              game,prototypes=original_game,original_prototypes
              for _,change in ipairs({function(p)p.old_version="5.0.20008"end,
                function(p)p.new_version="5.0.21012"end,function(p)p.kind="unknown"end,
                function(p)p.kind=kind=="older-mir501-empty-default"and"published473-idle-default"or"older-mir501-empty-default"end})do
                local original=copy(saved.producer);change(saved.producer)
                assert(not pcall(history.default_owner_on_load));saved.producer=original
              end
            ''')


class WorkerPaidHeadConfigurationFlagTests(unittest.TestCase):
    """Model the observed config-only re-enable of a paid native infinite H5."""

    def world(self, target="f210"):
        lua = WorkerFullDefaultProviderHandoverTests.world(self, target)
        lua.execute(r'''
          function reenable_paid_heads()
            local count=0
            for _,f in pairs(game.forces)do local h=f.technologies[HEAD]
              if h.level==5 then h.enabled=true;count=count+1 end
            end
            assert(count==3);writes=0;queue_writes={};progress_writes={}
          end
          function default_config()return{mod_startup_settings_changed=true,mod_changes={}}end
          function only_head_flags_settled(before)
            local expected=copy(before)
            for _,f in pairs(expected)do f.debit.enabled=false end
            assert(same(expected,all_frames()))
            assert(next(queue_writes)==nil and next(progress_writes)==nil)
          end
        ''')
        return lua

    def test_paid_default_configuration_settles_only_enabled_after_all_force_preflight(self):
        for target in ("f200", "f210"):
            for scalar in (0, 1, 2):
                lua = self.world(target); lua.globals().scalar = scalar
                lua.execute(r'''
                  full_source(scalar,true);reenable_paid_heads();local before=all_frames()
                  local owner,key=storage[OWNER_KEY],storage.mir_worker_storage_route
                  local plan=history.default_owner_preflight(default_config(),nil,true)
                  assert(plan.changed and writes==0 and same(before,all_frames()))
                  assert(storage[OWNER_KEY]==owner and storage.mir_worker_storage_route==key)
                  assert(history.default_owner_apply(plan));only_head_flags_settled(before);assert(writes==3)
                  assert(storage.mir_worker_storage_route==key and same(storage[OWNER_KEY],owner))
                  local settled=all_frames();writes=0
                  local again=history.default_owner_preflight(default_config(),nil,true)
                  assert(not again.changed and not history.default_owner_apply(again)and writes==0 and same(settled,all_frames()))
                ''')

    def test_provider_handover_settles_paid_head_flags_without_reconstructing_work(self):
        for target in ("f200", "f210"):
            for a,b in ((0,2),(1,1),(2,0)):
                lua=self.world(target);lua.globals().a=a;lua.globals().b=b
                lua.execute(r'''
                  full_source(a,true);finite_entry(b);reenable_paid_heads();local before=all_frames();local foreign=foreign_frames()
                  local plan,legacy=delegate();assert(writes==0 and same(before,all_frames()))
                  assert(history.default_owner_apply(plan));history.apply(legacy)
                  assert(same(foreign,foreign_frames()))
                  for _,f in pairs(game.forces)do local old=before[f.index];local p,h=f.technologies[ID],f.technologies[HEAD]
                    assert(h.level==old.debit.level and not h.researched and not h.enabled and not h.visible_when_disabled and h.saved_progress==0)
                    assert(p.level==old.owner.level and p.saved_progress==old.owner.saved and f.worker_robots_storage_bonus==old.bonus)
                    assert(f.technologies[OTHER].saved_progress==old.other_saved)
                  end
                  assert(player.current_research.name==ID and player.research_progress==.375)
                  assert(uninvested.current_research.name==ID and uninvested.research_progress==.37)
                  assert(suspended.current_research.name==OTHER and suspended.research_progress==.42)
                  assert(detached.current_research.name==OTHER and detached.research_progress==.625)
                ''')

    def test_retired_provider_configuration_has_explicit_flag_only_plan_and_read_only_load(self):
        for target in ("f200", "f210"):
            lua=self.world(target);lua.execute(r'''
              full_source(1,true);finite_entry(2);handover();reenable_paid_heads();local before=all_frames()
              local owner,key=storage[OWNER_KEY],storage.mir_worker_storage_route
              local saved_game,saved_prototypes=game,prototypes
              game=setmetatable({},{__index=function()error("on_load game read")end})
              prototypes=setmetatable({},{__index=function()error("on_load prototype read")end})
              history.on_load();history.default_owner_on_load();assert(writes==0)
              game,prototypes=saved_game,saved_prototypes
              local plan=history.default_owner_preflight(default_config(),provider_route(5),true)
              assert(type(plan)=="table"and plan.kind=="default-native-provider-gate-settle"and plan.changed)
              assert(not history.default_owner_delegated(plan)and writes==0 and same(before,all_frames()))
              -- Bootstrap commits the unchanged legacy quota before this nondelegated plan.
              history.apply(history.preflight(default_config(),provider_route(5)));key=storage.mir_worker_storage_route
              assert(history.default_owner_apply(plan));only_head_flags_settled(before);assert(writes==3)
              assert(storage[OWNER_KEY]==owner and storage.mir_worker_storage_route==key)
              writes=0;assert(history.default_owner_preflight(default_config(),provider_route(5),true)==nil and writes==0)
            ''')

    def test_config_flag_admission_keeps_unpaid_malformed_and_foreign_heads_strict(self):
        opponents=("uninvested.technologies[HEAD].enabled=true", "h.enabled='true'", "h.level=6;h.enabled=true",
                   "h.researched=true", "h.saved_progress=.01", "h.visible_when_disabled=true",
                   "player.research_queue={h}", "player.research_queue={OTHER,h}", "creators[HEAD]='foreign'")
        for context in ("default", "handover", "retired"):
            for opponent in opponents:
                with self.subTest(context=context,opponent=opponent):
                    lua=self.world();lua.globals().context=context;lua.globals().opponent=opponent
                    lua.execute(r'''
                      full_source(1,true)
                      if context~="default"then finite_entry(1)end
                      if context=="retired"then handover()end
                      reenable_paid_heads();local h=player.technologies[HEAD]
                    '''+opponent+r'''
                      local before=all_frames();local owner,key=storage[OWNER_KEY],storage.mir_worker_storage_route;writes=0
                      local event=context=="handover"and provider_event()or default_config()
                      local route=context~="default"and provider_route(5)or nil
                      assert(not pcall(history.default_owner_preflight,event,route,true))
                      assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==owner and storage.mir_worker_storage_route==key)
                    ''')

    def test_raw_head_enabled_is_sealed_against_both_stale_directions(self):
        for context in ("default", "handover", "retired"):
            for initially_enabled in (False, True):
                if context=="retired"and not initially_enabled:
                    continue
                lua=self.world();lua.globals().context=context;lua.globals().initially_enabled=initially_enabled
                lua.execute(r'''
                  full_source(1,true)
                  if context~="default"then finite_entry(1)end
                  if context=="retired"then handover()end
                  local h=detached.technologies[HEAD];h.enabled=initially_enabled;writes=0
                  local event=context=="handover"and provider_event()or default_config()
                  local route=context~="default"and provider_route(5)or nil
                  local plan=history.default_owner_preflight(event,route,true)
                  if context=="handover"then history.preflight(event,route,plan)end
                  h.enabled=not initially_enabled;local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_apply,plan))
                  assert(writes==0 and same(before,all_frames()))
                ''')

    def test_paid_head_reenable_is_not_admitted_in_an_ordinary_finish_context(self):
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(detached,"advanced",{OTHER},true)
          assert(history.default_owner_on_research_finished(finish_event(detached)))
          detached.technologies[HEAD].enabled=true;finish_frame(player,"advanced",{OTHER},true)
          local before=all_frames();writes=0
          assert(not pcall(history.default_owner_on_research_finished,finish_event(player)))
          assert(writes==0 and same(before,all_frames()))
        ''')

    def test_gate_only_setter_guard_is_force_scoped_and_restored_on_error(self):
        for context in ("default", "retired"):
            for fail in (False, True):
                lua=self.world();lua.globals().context=context;lua.globals().fail=fail
                lua.execute(r'''
                  full_source(1,true)
                  if context=="retired"then finite_entry(1);handover()end
                  reenable_paid_heads();local before=all_frames();local h=player.technologies[HEAD]
                  local plan=history.default_owner_preflight(default_config(),context=="retired"and provider_route(5)or nil,true)
                  local mt=getmetatable(h);local write=mt.__newindex;local seen=0
                  mt.__newindex=function(o,k,v)
                    assert(k=="enabled"and v==false and history.default_owner_mutating{force=player})
                    assert(not history.default_owner_mutating{force=uninvested})
                    assert(not history.default_owner_on_research_finished{research=h,by_script=true})
                    seen=seen+1;if fail then error("injected H flag setter")end;write(o,k,v)
                  end
                  local ok,message=pcall(history.default_owner_apply,plan)
                  assert(seen==1 and not history.default_owner_mutating{force=player})
                  if fail then assert(not ok and tostring(message):find("injected H flag setter",1,true)and writes==0 and same(before,all_frames()))
                  else assert(ok);only_head_flags_settled(before)end
                ''')

    def test_retired_flag_settlement_requires_real_configuration_and_force_authority(self):
        for opponent in ("missing", "string", "package", "force"):
            lua=self.world();lua.globals().opponent=opponent
            lua.execute(r'''
              full_source(1,true);finite_entry(1);handover();reenable_paid_heads();local event=default_config()
              if opponent=="missing"then event.mod_startup_settings_changed=nil
              elseif opponent=="string"then event.mod_startup_settings_changed="true"
              elseif opponent=="package"then script.active_mods["more-infinite-research"]="5.0.21013"
              else storage[OWNER_KEY].forces[detached.index]=nil end
              local before=all_frames();writes=0
              assert(not pcall(history.default_owner_preflight,event,provider_route(5),true))
              assert(writes==0 and same(before,all_frames()))
            ''')


class WorkerUnchangedSelectionDefaultOriginTests(unittest.TestCase):
    def world(self, target="f210"):
        return WorkerDefaultNativeOwnerTransferTests.world(self,target)

    def test_known_nil_history_versions_preserve_paid_and_pending_work_with_unchanged_qol(self):
        for target in ("f200","f210"):
            for old_patch in (9,10,11):
                for explicit_change in (False,True):
                    lua=self.world(target);lua.globals().old_patch=old_patch;lua.globals().explicit_change=explicit_change
                    lua.execute(r'''
                      seed_owner();uninvested.technologies[CANONICAL].enabled=true
                      uninvested.research_queue={CANONICAL};uninvested.research_progress=.37
                      script.active_mods.qol="1.2.3"
                      local old=string.format("5.0.%d",(package_family=="f200"and 20000 or 21000)+old_patch)
                      local event=owner_event(old)
                      if explicit_change then event.mod_changes.qol={old_version="1.2.3",new_version="1.2.3"}end
                      local before=all_frames();writes=0
                      local plan=history.plan_default_owner_transfer(event,nil,false)
                      assert(writes==0 and same(before,all_frames()));assert(history.apply_default_owner_transfer(plan))
                      local state=storage[OWNER_KEY]
                      assert(state.schema==3 and state.producer.kind=="unchanged-mir5-default"and state.producer.old_version==old)
                      for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                        assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved and a.owner.enabled==b.source.enabled)
                        assert(a.bonus==b.bonus and a.other_saved==b.other_saved and same(a.private,b.private))
                      end
                      assert(player.current_research.name==ORDINARY and player.research_progress==.375 and player.research_queue[2].name==OTHER)
                      assert(uninvested.current_research.name==ORDINARY and uninvested.research_progress==.37)
                      assert(suspended.current_research.name==OTHER and suspended.research_progress==.42 and suspended.research_queue[2].name==ORDINARY)
                      assert(suspended.technologies[ORDINARY].saved_progress==.27 and detached.technologies[ORDINARY].saved_progress==.23)
                    ''')

    def test_empty_unchanged_qol_accepts_but_added_removed_updated_and_official_mismatch_refuse(self):
        for target in ("f200","f210"):
            for opponent in ("unchanged","added","removed","updated","official"):
                lua=self.world(target);lua.globals().opponent=opponent
                lua.execute(r'''
                  for _,f in pairs(game.forces)do local c=f.technologies[CANONICAL]
                    c.level=4;c.researched=false;c.saved_progress=0;f.research_queue={};f.research_progress=0
                  end
                  script.active_mods.qol="1.2.3"
                  local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                  event.mod_changes.qol={old_version="1.2.3",new_version="1.2.3"}
                  if opponent=="added"then event.mod_changes.qol.old_version=nil
                  elseif opponent=="removed"then script.active_mods.qol=nil;event.mod_changes.qol.new_version=nil
                  elseif opponent=="updated"then event.mod_changes.qol.old_version="1.2.2"
                  elseif opponent=="official"then script.active_mods.quality="wrong-engine"end
                  local before=all_frames();writes=0
                  local ok,plan=pcall(history.plan_default_owner_transfer,event,nil,false)
                  assert(writes==0 and same(before,all_frames()))
                  if opponent=="unchanged"then assert(ok);assert(history.apply_default_owner_transfer(plan))
                  else assert(not ok and storage[OWNER_KEY]==nil)end
                ''')


class WorkerDefaultEditionContinuityTests(unittest.TestCase):
    """Exact existing Base hop and stable historical producer facts, host only."""

    def world(self, target="f210"):
        return WorkerFullDefaultProviderHandoverTests.world(self, target)

    def test_exact_473_and_recorded_modern_base_hop_preserve_all_native_work(self):
        for old in ("4.7.20003","5.0.20009","5.0.20010","5.0.20011"):
            for changed in (False,True):
                lua=WorkerOlderDefaultAdmissionTests().older_world("f210") if old.startswith("4.7")else self.world()
                lua.globals().old=old;lua.globals().changed=changed
                lua.execute(r'''
                  if old=="4.7.20003"then paid_idle()
                  else seed_owner();storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                    uninvested.technologies[CANONICAL].enabled=true;uninvested.research_queue={CANONICAL};uninvested.research_progress=.37 end
                  local event=owner_event(old);event.mod_startup_settings_changed=changed
                  event.mod_changes.base={old_version="2.0.77",new_version="2.1.23"}
                  local before=all_frames();writes=0;queue_writes={};progress_writes={}
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(writes==0 and same(before,all_frames()));assert(history.default_owner_apply(plan))
                  local producer=storage[OWNER_KEY].producer
                  assert(producer.old_version==old and producer.new_version=="5.0.21012")
                  assert(producer.kind==(old=="4.7.20003"and"published473-idle-default"or"recorded-default"))
                  for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                    assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved and a.owner.enabled==b.source.enabled)
                    assert(a.bonus==b.bonus and a.other_saved==b.other_saved and same(a.private,b.private))
                    local expected=copy(b.queue)
                    for i,name in ipairs(expected)do if name==CANONICAL then expected[i]=ORDINARY end end
                    assert(same(a.queue,expected)and a.progress==b.progress)
                    assert(a.current==(b.current==CANONICAL and ORDINARY or b.current))
                  end
                ''')

    def test_f200_schema3_producer_loads_read_only_under_f210_and_stays_historical(self):
        for scalar in (0,2):
            lua=self.world("f200");lua.globals().scalar=scalar
            lua.execute(r'''
              full_source(scalar,true);local owner=storage[OWNER_KEY];local producer=copy(owner.producer);local before=all_frames()
              local target=package.loaded["platform.target"];target.id="f210";target.minimum_base="2.1.23";target.distribution_version="5.0.21012"
              package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage")
              local saved_game,saved_prototypes=game,prototypes
              game=setmetatable({},{__index=function()error("on_load game access")end})
              prototypes=setmetatable({},{__index=function()error("on_load prototype access")end});writes=0
              history.default_owner_on_load();assert(writes==0 and storage[OWNER_KEY]==owner)
              game,prototypes=saved_game,saved_prototypes
              -- F210's native getter exposes the default false effect flag.
              for _,id in ipairs{CANONICAL,ORDINARY,HEAD,ID}do for _,effect in ipairs(prototypes.technology[id].effects)do effect.hidden=false end end
              script.active_mods.base="2.1.23";script.active_mods["more-infinite-research"]="5.0.21012"
              local event={mod_startup_settings_changed=true,mod_changes={base={old_version="2.0.77",new_version="2.1.23"},
                ["more-infinite-research"]={old_version="5.0.20012",new_version="5.0.21012"}}}
              local plan=history.default_owner_preflight(event,nil,true)
              assert(not history.default_owner_apply(plan)and writes==0 and same(before,all_frames()))
              assert(same(storage[OWNER_KEY].producer,producer)and producer.new_version=="5.0.20012")
              assert(history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true))
              assert(history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={
                base={old_version="2.1.23",new_version="2.1.23"}}},nil,true))
              for _,bad in ipairs({"old-base","new-base","future-source","before-producer","missing-MIR","added-mod"})do
                local invalid=copy(event)
                if bad=="old-base"then invalid.mod_changes.base.old_version="2.0.76"
                elseif bad=="new-base"then invalid.mod_changes.base.new_version="2.1.24"
                elseif bad=="future-source"then invalid.mod_changes["more-infinite-research"].old_version="5.0.20013"
                elseif bad=="before-producer"then invalid.mod_changes["more-infinite-research"].old_version="5.0.20011"
                elseif bad=="missing-MIR"then invalid.mod_changes["more-infinite-research"]=nil
                else script.active_mods.qol="1";invalid.mod_changes.qol={new_version="1"}end
                writes=0;assert(not pcall(history.default_owner_preflight,invalid,nil,true)and writes==0 and same(before,all_frames()))
                script.active_mods.qol=nil
              end
            ''')

    def test_historical_f200_producer_does_not_repeat_hop_proof_on_later_f210_base_patch(self):
        lua=self.world("f200");lua.execute(r'''
          full_source(1,true);local producer=copy(storage[OWNER_KEY].producer);local before=all_frames()
          local target=package.loaded["platform.target"];target.id="f210";target.minimum_base="2.1.23";target.distribution_version="5.0.21012"
          for _,id in ipairs{CANONICAL,ORDINARY,HEAD,ID}do for _,effect in ipairs(prototypes.technology[id].effects)do effect.hidden=false end end
          script.active_mods.base="2.1.23";script.active_mods["more-infinite-research"]="5.0.21012"
          package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage");history.default_owner_on_load()
          local first={mod_startup_settings_changed=true,mod_changes={base={old_version="2.0.77",new_version="2.1.23"},
            ["more-infinite-research"]={old_version="5.0.20012",new_version="5.0.21012"}}}
          writes=0;assert(not history.default_owner_apply(history.default_owner_preflight(first,nil,true)))
          assert(writes==0 and same(before,all_frames())and same(producer,storage[OWNER_KEY].producer))
          script.active_mods.base="2.1.24"
          local later={mod_startup_settings_changed=false,mod_changes={base={old_version="2.1.23",new_version="2.1.24"}}}
          assert(not history.default_owner_apply(history.default_owner_preflight(later,nil,true)))
          assert(writes==0 and same(before,all_frames())and same(producer,storage[OWNER_KEY].producer))
          for _,versions in ipairs{{"2.0.76","2.1.23"},{"2.0.77","2.1.24"},{"2.1.24","2.0.77"}}do
            script.active_mods.base=versions[2]
            local invalid={mod_startup_settings_changed=false,mod_changes={base={old_version=versions[1],new_version=versions[2]},
              ["more-infinite-research"]={old_version="5.0.20012",new_version="5.0.21012"}}}
            assert(not pcall(history.default_owner_preflight,invalid,nil,true)and writes==0 and same(before,all_frames()))
          end
          script.active_mods.base="2.1.24";creators[ORDINARY]="foreign"
          assert(not pcall(history.default_owner_preflight,later,nil,true)and writes==0 and same(before,all_frames()))
        ''')

    def test_hop_is_not_a_new_mod_unknown_engine_downgrade_or_unrecorded_adoption(self):
        opponents=("old-base","new-base","missing-base","old-package","new-mod","unchanged-qol","space-age","private-work","foreign-source","unrecorded")
        for old in ("4.7.20003","5.0.20011"):
            for opponent in opponents:
                lua=WorkerOlderDefaultAdmissionTests().older_world("f210") if old.startswith("4.7")else self.world()
                lua.globals().old=old;lua.globals().opponent=opponent
                lua.execute(r'''
                  if old=="4.7.20003"then paid_idle()else seed_owner();storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}end
                  local event=owner_event(old);event.mod_changes.base={old_version="2.0.77",new_version="2.1.23"}
                  if opponent=="old-base"then event.mod_changes.base.old_version="2.0.76"
                  elseif opponent=="new-base"then script.active_mods.base="2.1.24";event.mod_changes.base.new_version="2.1.24"
                  elseif opponent=="missing-base"then event.mod_changes.base=nil
                  elseif opponent=="old-package"then event.mod_changes["more-infinite-research"].old_version="5.0.20042"
                  elseif opponent=="new-mod"then script.active_mods.qol="1";event.mod_changes.qol={new_version="1"}
                  elseif opponent=="unchanged-qol"then script.active_mods.qol="1";event.mod_changes.qol={old_version="1",new_version="1"}
                  elseif opponent=="space-age"then script.active_mods["space-age"]="2.1.23";event.mod_changes["space-age"]={new_version="2.1.23"}
                  elseif opponent=="private-work"then detached.technologies[ID].saved_progress=.1
                  elseif opponent=="foreign-source"then creators[CANONICAL]="foreign"
                  else storage.mir_worker_storage_route=nil;event.mod_changes["more-infinite-research"].old_version="5.0.20011"end
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_preflight,event,nil,true))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                ''')
        lua=self.world("f200");lua.execute(r'''
          seed_owner();storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
          local event=owner_event("5.0.21011");event.mod_changes.base={old_version="2.1.23",new_version="2.0.77"};writes=0
          assert(not pcall(history.default_owner_preflight,event,nil,true)and writes==0)
        ''')

    def test_historical_producer_validation_keeps_invalid_and_reverse_editions_strict(self):
        for opponent in ("unknown-edition","future-patch","backward-patch","backward-edition","unproved-cross-kind","direct501"):
            lua=self.world("f200");lua.globals().opponent=opponent
            lua.execute(r'''
              full_source(1,true);local saved=storage[OWNER_KEY]
              local target=package.loaded["platform.target"];target.id="f210";target.distribution_version="5.0.21012"
              if opponent=="unknown-edition"then saved.producer.new_version="5.0.22012"
              elseif opponent=="future-patch"then saved.producer.new_version="5.0.20013"
              elseif opponent=="backward-patch"then saved.producer.new_version="5.0.20009"
              elseif opponent=="backward-edition"then saved.producer.old_version="5.0.21011"
              elseif opponent=="unproved-cross-kind"then saved.producer.kind="unchanged-mir5-default";saved.producer.new_version="5.0.21012"
              else saved.producer.kind="older-mir501-empty-default";saved.producer.old_version="5.0.20001";saved.producer.new_version="5.0.21012"end
              package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage");writes=0
              local saved_game,saved_prototypes=game,prototypes
              game=setmetatable({},{__index=function()error("on_load game access")end})
              prototypes=setmetatable({},{__index=function()error("on_load prototype access")end})
              local ok,message=pcall(history.default_owner_on_load)
              assert(not ok and tostring(message):find("unknown default native-owner producer",1,true)and writes==0)
              game,prototypes=saved_game,saved_prototypes
            ''')
        lua=self.world();lua.execute(r'''
          full_source(1,true);local target=package.loaded["platform.target"];target.id="f200";target.distribution_version="5.0.20012"
          package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage");writes=0
          assert(not pcall(history.default_owner_on_load)and writes==0)
        ''')

    def test_retired_metadata_patch_keeps_route_work_flags_and_no_second_release(self):
        for reenabled in (False,True):
            lua=self.world();lua.globals().reenabled=reenabled
            lua.execute(r'''
              full_source(1,true);finite_entry(1);handover();player.technologies[CANONICAL].enabled=false
              if reenabled then for _,f in pairs(game.forces)do local h=f.technologies[HEAD];if h.level==5 then h.enabled=true end end end
              script.active_mods.provider="1.0.1"
              local event={mod_startup_settings_changed=false,mod_changes={provider={old_version="1.0",new_version="1.0.1"}}}
              local before=all_frames();writes=0;queue_writes={};progress_writes={}
              local plan=history.default_owner_preflight(event,provider_route(5),true)
              local legacy=history.preflight(event,provider_route(5));assert(writes==0 and same(before,all_frames()))
              history.apply(legacy);assert(history.default_owner_apply(plan)==reenabled)
              local expected=copy(before);for _,row in pairs(expected)do row.debit.enabled=false end
              assert(same(expected,all_frames())and not player.technologies[CANONICAL].enabled)
              assert(writes==(reenabled and 3 or 0)and next(queue_writes)==nil and next(progress_writes)==nil)
            ''')
        for opponent in ("removed","added","unbound-version","changed-route","changed-contract","last-force-work"):
            lua=self.world();lua.globals().opponent=opponent
            lua.execute(r'''
              full_source(1,true);finite_entry(1);handover();script.active_mods.provider="1.0.1"
              local event={mod_startup_settings_changed=false,mod_changes={provider={old_version="1.0",new_version="1.0.1"}}};local route=provider_route(5)
              if opponent=="removed"then event.mod_changes.provider.new_version=nil;script.active_mods.provider=nil
              elseif opponent=="added"then event.mod_changes.provider.old_version=nil
              elseif opponent=="unbound-version"then script.active_mods.provider="1.0.2"
              elseif opponent=="changed-route"then route=provider_route(6)
              elseif opponent=="changed-contract"then prototypes.technology[ID].research_unit_energy=3601
              else detached.technologies[ORDINARY].saved_progress=.1 end
              local before=all_frames();writes=0
              assert(not pcall(history.default_owner_preflight,event,route,true)and writes==0 and same(before,all_frames()))
            ''')



class WorkerPrivateQueueEventContextTests(unittest.TestCase):
    def world(self,target="f210"):
        lua=WorkerFullDefaultProviderHandoverTests.world(self,target)
        lua.execute('defines={events={on_research_queued=25,on_research_started=26}}')
        return lua

    def test_retired_force_ignores_other_queue_event_while_another_force_is_pending(self):
        for target in ("f200","f210"):
            lua=self.world(target);lua.execute(r"""
              full_source(1,true);finite_entry(1);handover()
              local f=player;local p=f.technologies[ID]
              local continuation=f.technologies["worker-robots-storage-6"]
              continuation.name="worker-robots-storage-6";continuation.force=f;continuation.visible_when_disabled=false
              f.research_queue={OTHER};f.research_progress=0;p.level=9
              assert(history.on_research_event({research=p,by_script=false},true))
              local state=storage.mir_worker_storage_route
              assert(not state.forces[f.index].pending and state.forces[suspended.index].pending and history.needs_research_events())
              local saved=copy(state);local mt=getmetatable(f);local read=mt.__index
              mt.__index=function(o,k)if k=="research_queue"then return {f.technologies["worker-robots-storage-6"],f.technologies[OTHER]}end;return read(o,k)end
              writes=0;assert(not history.on_research_event({force=f,research=f.technologies["worker-robots-storage-6"],name=25}))
              assert(writes==0 and same(saved,state))
              -- Unexpected private completion is still checked, even on this retired force.
              assert(not pcall(history.on_research_event,{research=p,by_script=false},true)and writes==0)
              mt.__index=read
            """)

    def test_pending_setter_observation_is_read_only_then_started_enforces_quota_and_finish(self):
        for target in ("f200","f210"):
            lua=self.world(target);lua.execute(r"""
              full_source(1,true);finite_entry(1);handover()
              local f=player;local mt=getmetatable(f);local read,write=mt.__index,mt.__newindex
              local changing=false;local newqueue;local observed=0
              mt.__index=function(o,k)if changing and k=="research_queue"then return newqueue end;return read(o,k)end
              mt.__newindex=function(o,k,v)
                if k=="research_queue"then
                  newqueue={};for _,id in ipairs(v)do newqueue[#newqueue+1]=f.technologies[type(id)=="string"and id or id.name]end
                  local before=copy(storage.mir_worker_storage_route);local count=writes
                  changing=true;if observed==0 then assert(f.current_research.name~=f.research_queue[1].name)end
                  local ok,result=pcall(history.on_research_event,{force=f,research=f.technologies[ID],name=25});changing=false
                  assert(ok and result==false and writes==count and same(before,storage.mir_worker_storage_route));observed=observed+1
                end
                return write(o,k,v)
              end
              f.research_queue={OTHER,ID,ID}
              assert(observed==1 and f.current_research.name==OTHER and #f.research_queue==3)
              local quota=storage.mir_worker_storage_route.forces[f.index]
              assert(quota.next_level==8 and quota.limit==8 and quota.pending)
              assert(history.on_research_event({research=f.technologies[OTHER],name=26}))
              assert(#f.research_queue==2 and f.research_queue[2].name==ID and quota.limit==8)
              mt.__newindex=write;mt.__index=read
              f.research_queue={OTHER};f.research_progress=.23;f.technologies[ID].level=9
              assert(history.on_research_event({research=f.technologies[ID],by_script=false},true))
              assert(not quota.pending and not f.technologies[ID].enabled and f.current_research.name==OTHER and f.research_progress==.23)
            """)

    def test_pending_other_and_private_queue_observations_are_always_read_only(self):
        for transient in (False,True):
            for private_event in (False,True):
                lua=self.world();lua.globals().transient=transient;lua.globals().private_event=private_event
                lua.execute(r"""
                  full_source(1,true);finite_entry(1);handover()
                  local f=player;local mt=getmetatable(f);local read=mt.__index
                  if transient then mt.__index=function(o,k)
                    if k=="research_queue"then return {f.technologies[OTHER],f.technologies[ID]}end;return read(o,k)end end
                  local state=copy(storage.mir_worker_storage_route);local before=all_frames();writes=0
                  assert((f.current_research.name~=f.research_queue[1].name)==transient)
                  assert(not history.on_research_event({force=f,research=f.technologies[private_event and ID or OTHER],name=25}))
                  assert(writes==0 and same(state,storage.mir_worker_storage_route)and same(before,all_frames()))
                  mt.__index=read
                """)

    def test_queue_deferral_does_not_admit_other_contexts_bad_frames_or_config(self):
        for opponent in ("started","progress","level","enabled","saved","configuration"):
            lua=self.world();lua.globals().opponent=opponent;lua.execute(r"""
              full_source(1,true);finite_entry(1);handover()
              local f=player;local mt=getmetatable(f);local read=mt.__index
              mt.__index=function(o,k)if k=="research_queue"then return {f.technologies[OTHER],f.technologies[ID]}end
                if k=="research_progress"and opponent=="progress"then return 1 end;return read(o,k)end
              if opponent=="level"then f.technologies[ID].level=9 end
              if opponent=="enabled"then f.technologies[ID].enabled=false end
              if opponent=="saved"then f.technologies[ID].saved_progress=1 end
              local state=copy(storage.mir_worker_storage_route);writes=0
              local ok
              if opponent=="configuration"then ok=pcall(history.preflight,{},provider_route(5))
              else ok=pcall(history.on_research_event,{force=f,research=f.technologies[ID],name=opponent=="started"and 26 or 25})end
              assert(not ok and writes==0 and same(state,storage.mir_worker_storage_route))
            """)


class WorkerSameFamilyEnginePatchTests(unittest.TestCase):
    def world(self,target="f210"):
        return WorkerDefaultNativeOwnerTransferTests.world(self,target)

    def test_known_unrecorded_defaults_accept_supported_current_and_synchronized_official_patch(self):
        for target in ("f200","f210"):
            for old_patch in (9,10,11):
                for with_event in (False,True):
                    lua=self.world(target);lua.globals().old_patch=old_patch;lua.globals().with_event=with_event
                    lua.execute(r"""
                      seed_owner();local target=require("platform.target");local oldbase=target.minimum_base
                      local newbase=package_family=="f200"and"2.0.78"or"2.1.24"
                      script.active_mods.base=newbase;local event=owner_event(string.format("5.0.%d",(package_family=="f200"and 20000 or 21000)+old_patch))
                      for _,name in ipairs{"space-age","quality","elevated-rails","recycler"}do
                        script.active_mods[name]=newbase
                        if with_event then event.mod_changes[name]={old_version=oldbase,new_version=newbase}end
                      end
                      if with_event then event.mod_changes.base={old_version=oldbase,new_version=newbase}end
                      local before=all_frames();writes=0;local plan=history.plan_default_owner_transfer(event,nil,false)
                      assert(writes==0 and same(before,all_frames()));assert(history.apply_default_owner_transfer(plan))
                      assert(storage[OWNER_KEY].producer.kind=="unchanged-mir5-default")
                      for _,f in pairs(game.forces)do assert(f.worker_robots_storage_bonus==before[f.index].bonus)end
                    """)

    def test_all_empty_nil_history_defaults_accept_supported_patch_without_work_inference(self):
        for target in ("f200","f210"):
            for with_event in (False,True):
                lua=self.world(target);lua.globals().with_event=with_event
                lua.execute(r"""
                  local target=require("platform.target");local oldbase=target.minimum_base
                  for _,f in pairs(game.forces)do local c=f.technologies[CANONICAL]
                    c.level=4;c.researched=false;c.saved_progress=0;f.research_queue={};f.research_progress=0
                  end
                  script.active_mods.base=package_family=="f200"and"2.0.78"or"2.1.24"
                  local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                  if with_event then event.mod_changes.base={old_version=oldbase,new_version=script.active_mods.base}end
                  local before=all_frames();writes=0;queue_writes={};progress_writes={}
                  local plan=history.plan_default_owner_transfer(event,nil,false)
                  assert(writes==0 and same(before,all_frames()));assert(history.apply_default_owner_transfer(plan))
                  for _,f in pairs(game.forces)do assert(f.technologies[ORDINARY].level==4 and f.technologies[HEAD].level==4
                    and f.worker_robots_storage_bonus==before[f.index].bonus)end
                  assert(next(queue_writes)==nil and next(progress_writes)==nil)
                """)

    def test_secretas_known_origins_accept_only_the_same_official_patch_without_native_writes(self):
        for target in ("f200","f210"):
            for patch in (9,10,11):
                for with_event in (False,True):
                    lua=self.world(target);lua.globals().old_patch=patch;lua.globals().with_event=with_event
                    lua.execute(r"""
                      seed_owner();add_provider(8);local target=require("platform.target");local oldbase=target.minimum_base
                      local newbase=package_family=="f200"and"2.0.78"or"2.1.24"
                      script.active_mods.base=newbase;script.active_mods.secretas="1.0.38"
                      local event=owner_event(string.format("5.0.%d",(package_family=="f200"and 20000 or 21000)+old_patch))
                      for _,name in ipairs{"space-age","quality","elevated-rails","recycler"}do
                        script.active_mods[name]=newbase;if with_event then event.mod_changes[name]={old_version=oldbase,new_version=newbase}end
                      end
                      if with_event then event.mod_changes.base={old_version=oldbase,new_version=newbase}end
                      local before=all_frames();writes=0;local plan=history.preflight(event,provider_route(8));history.apply(plan)
                      assert(writes==0 and same(before,all_frames())and storage.mir_worker_storage_route.route.technology=="worker-robots-storage-9")
                    """)

    def test_patch_exclusions_preserve_all_native_frames_before_refusal(self):
        for target in ("f200","f210"):
          for secretas in (False,True):
            for opponent in ("old-floor","current-floor","downgrade","cross-family","base-new","DLC-old","DLC-new","DLC-add","DLC-remove","third-add","third-remove","third-update","startup","unknown-producer","DLC-without-base","DLC-without-event"):
                lua=self.world(target);lua.globals().secretas_case=secretas;lua.globals().opponent=opponent
                lua.execute(r"""
                  seed_owner();local f200=package_family=="f200"
                  local floor=f200 and "2.0.77"or"2.1.23";local current=f200 and "2.0.78"or"2.1.24"
                  local below=f200 and "2.0.76"or"2.1.22";local higher=f200 and "2.0.79"or"2.1.25"
                  local other_family=f200 and "2.1.23"or"2.0.77"
                  local event=owner_event(f200 and "5.0.20011"or"5.0.21011");script.active_mods.base=current
                  event.mod_changes.base={old_version=floor,new_version=current}
                  script.active_mods.quality=current;event.mod_changes.quality={old_version=floor,new_version=current}
                  if secretas_case then add_provider(8);script.active_mods.secretas="1.0.38"end
                  if opponent=="old-floor"then event.mod_changes.base.old_version=below;event.mod_changes.quality.old_version=below
                  elseif opponent=="current-floor"then script.active_mods.base=below;script.active_mods.quality=below
                    event.mod_changes.base={old_version=below,new_version=below};event.mod_changes.quality={old_version=below,new_version=below}
                  elseif opponent=="downgrade"then event.mod_changes.base.old_version=higher;event.mod_changes.quality.old_version=higher
                  elseif opponent=="cross-family"then event.mod_changes.base.old_version=other_family;event.mod_changes.quality.old_version=other_family
                  elseif opponent=="base-new"then event.mod_changes.base.new_version=higher
                  elseif opponent=="DLC-old"then event.mod_changes.quality.old_version=below
                  elseif opponent=="DLC-new"then script.active_mods.quality=higher;event.mod_changes.quality.new_version=higher
                  elseif opponent=="DLC-add"then event.mod_changes.quality.old_version=nil
                  elseif opponent=="DLC-remove"then script.active_mods.quality=nil;event.mod_changes.quality.new_version=nil
                  elseif opponent=="third-add"then script.active_mods.qol="1";event.mod_changes.qol={new_version="1"}
                  elseif opponent=="third-remove"then event.mod_changes.qol={old_version="1"}
                  elseif opponent=="third-update"then script.active_mods.qol="2";event.mod_changes.qol={old_version="1",new_version="2"}
                  elseif opponent=="startup"then event.mod_startup_settings_changed=true
                  elseif opponent=="unknown-producer"then event.mod_changes["more-infinite-research"].old_version=f200 and "5.0.20042"or"5.0.21042"
                  elseif opponent=="DLC-without-base"then event.mod_changes.base=nil
                  elseif opponent=="DLC-without-event"then event.mod_changes.quality=nil end
                  local before=all_frames();writes=0
                  local ok=secretas_case and pcall(history.preflight,event,provider_route(8))or false
                  if not secretas_case then ok=pcall(history.plan_default_owner_transfer,event,nil,false)end
                  assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil and storage.mir_worker_storage_route==nil)
                """)



class WorkerPublished08DefaultCompatibilityTests(unittest.TestCase):
    """Published08/09 share the exact worker contract; native qualification is separate."""

    def world(self, target="f210"):
        return WorkerFullDefaultProviderHandoverTests.world(self, target)

    def test_08_earned_current_repeated_queue_and_detached_work_move_exactly(self):
        for target in ("f200", "f210"):
            for scalar in (0, 1, 2):
                lua=self.world(target);lua.globals().scalar=scalar
                lua.execute(r'''
                  set_reward(scalar);seed_owner()
                  player.research_queue={CANONICAL,CANONICAL,OTHER};player.research_progress=.375
                  local old=package_family=="f200"and"5.0.20008"or"5.0.21008"
                  local before=all_frames();writes=0;queue_writes={};progress_writes={}
                  local plan=history.default_owner_preflight(owner_event(old),nil,true)
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                  assert(history.default_owner_apply(plan))
                  assert(storage[OWNER_KEY].producer.kind=="unchanged-mir5-default"and storage[OWNER_KEY].producer.old_version==old)
                  for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                    assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved and a.owner.enabled==b.source.enabled)
                    assert(a.bonus==b.bonus and a.other_saved==b.other_saved and same(a.private,b.private))
                    local expected=copy(b.queue);for i,name in ipairs(expected)do if name==CANONICAL then expected[i]=ORDINARY end end
                    assert(same(a.queue,expected)and a.progress==b.progress)
                  end
                  assert(player.current_research.name==ORDINARY and player.research_progress==.375
                    and player.research_queue[2].name==ORDINARY and player.research_queue[3].name==OTHER)
                  assert(suspended.technologies[ORDINARY].saved_progress==.27 and detached.technologies[ORDINARY].saved_progress==.23)
                ''')

    def test_08_all_worker_empty_keeps_unrelated_finite_and_foreign_work(self):
        for target in ("f200", "f210"):
            lua=self.world(target);lua.execute(r'''
              for _,f in pairs(game.forces)do
                f.technologies.automation={name="automation",level=1,researched=true,enabled=true,saved_progress=0}
                f.research_queue={OTHER};f.research_progress=f.index/8
              end
              local old=package_family=="f200"and"5.0.20008"or"5.0.21008"
              local before=all_frames();writes=0;queue_writes={};progress_writes={}
              local plan=history.default_owner_preflight(owner_event(old),nil,true)
              assert(writes==0 and same(before,all_frames()));assert(history.default_owner_apply(plan))
              for _,f in pairs(game.forces)do
                assert(f.technologies[ORDINARY].level==4 and f.technologies[HEAD].level==4)
                assert(f.current_research.name==OTHER and f.research_progress==f.index/8 and #f.research_queue==1)
                assert(f.technologies.automation.researched and f.worker_robots_storage_bonus==before[f.index].bonus)
              end
              assert(next(queue_writes)==nil and next(progress_writes)==nil)
            ''')

    def test_08_producer_survives_readonly_load_next_config_and_base_patch(self):
        for target in ("f200", "f210"):
            lua=self.world(target);lua.execute(r'''
              seed_owner();local old=package_family=="f200"and"5.0.20008"or"5.0.21008"
              history.default_owner_apply(history.default_owner_preflight(owner_event(old),nil,true))
              local saved=storage[OWNER_KEY];local before=all_frames();writes=0
              local native_game,native_prototypes=game,prototypes
              game=setmetatable({},{__index=function()error("cold native read")end})
              prototypes=setmetatable({},{__index=function()error("cold prototype read")end})
              package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage")
              history.default_owner_on_load();assert(storage[OWNER_KEY]==saved and writes==0)
              game,prototypes=native_game,native_prototypes
              local same_event={mod_startup_settings_changed=false,mod_changes={}}
              assert(not history.default_owner_apply(history.default_owner_preflight(same_event,nil,true)))
              assert(storage[OWNER_KEY]==saved and saved.producer.old_version==old and same(before,all_frames())and writes==0)
              local previous_base=script.active_mods.base
              local next_base=package_family=="f200"and"2.0.78"or"2.1.24";script.active_mods.base=next_base
              local patch={mod_startup_settings_changed=false,mod_changes={base={old_version=previous_base,new_version=next_base}}}
              assert(not history.default_owner_apply(history.default_owner_preflight(patch,nil,true)))
              assert(storage[OWNER_KEY]==saved and saved.producer.old_version==old and same(before,all_frames())and writes==0)
            ''')

    def test_08_does_not_admit_future42_changed_inputs_or_invalid_native_state(self):
        for target in ("f200", "f210"):
            for opponent in ("future42", "startup", "added", "removed", "updated", "private", "foreign", "owner-effect", "last-force"):
                lua=self.world(target);lua.globals().opponent=opponent
                lua.execute(r'''
                  seed_owner();local old=package_family=="f200"and"5.0.20008"or"5.0.21008";local event=owner_event(old)
                  if opponent=="future42"then event.mod_changes["more-infinite-research"].old_version=package_family=="f200"and"5.0.20042"or"5.0.21042"
                  elseif opponent=="startup"then event.mod_startup_settings_changed=true
                  elseif opponent=="added"then script.active_mods.qol="1";event.mod_changes.qol={new_version="1"}
                  elseif opponent=="removed"then event.mod_changes.qol={old_version="1"}
                  elseif opponent=="updated"then script.active_mods.qol="2";event.mod_changes.qol={old_version="1",new_version="2"}
                  elseif opponent=="private"then detached.technologies[ID].saved_progress=.1
                  elseif opponent=="foreign"then creators[CANONICAL]="foreign"
                  elseif opponent=="owner-effect"then prototypes.technology[ORDINARY].effects[1].modifier=2
                  else detached.technologies[HEAD].researched=true end
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_preflight,event,nil,true))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                ''')


class WorkerPublishedDefaultContractContinuityTests(unittest.TestCase):
    'Public00Ã¢â‚¬â€œ11 default native stream and complete schema3 handover authority.'

    def world(self, target="f210"):
        return WorkerFullDefaultProviderHandoverTests.world(self, target)

    def test_all_public_default_versions_keep_native_paid_or_empty_work_both_families(self):
        for target in ("f200", "f210"):
            for patch in range(12):
                for empty in (False, True):
                    lua=self.world(target);lua.globals().patch=patch;lua.globals().empty=empty
                    lua.execute(r'''
                      set_reward(patch%3)
                      if not empty then seed_owner()else
                        for _,f in pairs(game.forces)do f.research_queue={OTHER};f.research_progress=f.index/8 end
                      end
                      local old=string.format("5.0.%d",(package_family=="f200"and 20000 or 21000)+patch)
                      script.active_mods.qol="1";local event=owner_event(old);event.mod_changes.qol={old_version="1",new_version="1"}
                      local before=all_frames();writes=0;queue_writes={};progress_writes={}
                      local plan=history.default_owner_preflight(event,nil,true)
                      assert(writes==0 and same(before,all_frames())and storage.mir_worker_storage_route==nil)
                      assert(plan.record.producer.kind=="unchanged-mir5-default"and history.default_owner_apply(plan))
                      for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                        assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved and a.bonus==b.bonus)
                        assert(a.progress==b.progress and a.other_saved==b.other_saved and same(a.private,b.private))
                        local expected=copy(b.queue);for i,name in ipairs(expected)do if name==CANONICAL then expected[i]=ORDINARY end end
                        assert(same(a.queue,expected))
                      end
                      assert(storage[OWNER_KEY].producer.old_version==old and storage.mir_worker_storage_route==nil)
                      if empty then assert(next(queue_writes)==nil and next(progress_writes)==nil)end
                    ''')

    def test_unrecorded08_09_owner_cold_config_provider_and_retired_config_without_init(self):
        for target in ("f200", "f210"):
            for patch in (8, 9):
                lua=self.world(target);lua.globals().patch=patch
                lua.execute(r'''
                  seed_owner();local old=string.format("5.0.%d",(package_family=="f200"and 20000 or 21000)+patch)
                  local event=owner_event(old);local owner=history.default_owner_preflight(event,nil,true)
                  history.apply(history.preflight(event,nil));assert(history.default_owner_apply(owner))
                  assert(storage.mir_worker_storage_route==nil and storage[OWNER_KEY].producer.old_version==old)
                  local saved=storage[OWNER_KEY];local before=all_frames();writes=0
                  local g,p=game,prototypes
                  game=setmetatable({},{__index=function()error("cold native read")end})
                  prototypes=setmetatable({},{__index=function()error("cold prototype read")end})
                  package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage")
                  history.on_load();history.default_owner_on_load();assert(writes==0 and storage[OWNER_KEY]==saved)
                  game,prototypes=g,p
                  assert(not history.default_owner_apply(history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)))
                  assert(same(before,all_frames())and storage.mir_worker_storage_route==nil)
                  finite_entry(1);before=all_frames();local plan,legacy=delegate()
                  assert(plan.prior_state==nil and storage.mir_worker_storage_route==nil and writes==0)
                  assert(history.default_owner_apply(plan));assert(storage.mir_worker_storage_route==nil)
                  history.apply(legacy);assert(storage.mir_worker_storage_route==legacy.state)
                  assert(storage[OWNER_KEY].kind=="provider-retired"and storage[OWNER_KEY].producer.old_version==old)
                  for _,f in pairs(game.forces)do assert(f.worker_robots_storage_bonus==before[f.index].bonus)end
                  before=all_frames();writes=0;script.active_mods.provider="1.0.1"
                  local update={mod_startup_settings_changed=false,mod_changes={provider={old_version="1.0",new_version="1.0.1"}}}
                  local again=history.default_owner_preflight(update,provider_route(5),true)
                  history.apply(history.preflight(update,provider_route(5)));assert(not history.default_owner_apply(again))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY].producer.old_version==old)
                ''')

    def test_absent_legacy_handover_still_refuses_bad_authority_private_or_other_force(self):
        for target in ("f200", "f210"):
            for opponent in ("no-owner", "bad-owner", "wrong-key", "malformed-key", "private", "other-force", "contract", "disabled", "overcap"):
                lua=self.world(target);lua.globals().opponent=opponent
                lua.execute(r'''
                  seed_owner();local old=package_family=="f200"and"5.0.20008"or"5.0.21008"
                  history.default_owner_apply(history.default_owner_preflight(owner_event(old),nil,true))
                  assert(storage.mir_worker_storage_route==nil);finite_entry(1)
                  if opponent=="no-owner"then storage[OWNER_KEY]=nil
                  elseif opponent=="bad-owner"then storage[OWNER_KEY].schema=2
                  elseif opponent=="wrong-key"then storage.mir_worker_storage_route={schema=2,kind="route",current={kind="finite",route=provider_route(5)}}
                  elseif opponent=="malformed-key"then storage.mir_worker_storage_route={schema=42}
                  elseif opponent=="private"then player.technologies[ID].saved_progress=.1
                  elseif opponent=="other-force"then detached.technologies[ID].level=5
                  elseif opponent=="contract"then prototypes.technology[ORDINARY].research_unit_energy=3601
                  elseif opponent=="disabled"then history.configure(0,false)
                  else history.configure(4,true)end
                  local before=all_frames();writes=0
                  local ok,plan=pcall(history.default_owner_preflight,provider_event(),provider_route(5),true)
                  if opponent=="no-owner"then
                    assert(ok and plan==nil and not history.default_owner_delegated(plan))
                    assert(not pcall(history.preflight,provider_event(),provider_route(5),{kind="default-native-provider-handover"}))
                  else assert(not ok)end
                  assert(writes==0 and same(before,all_frames()))
                ''')

    def test_absent_legacy_handover_stale_state_or_last_force_refuses_before_writes(self):
        for target in ("f200", "f210"):
            for opponent in ("state-created", "last-force-work", "owner-replaced"):
                lua=self.world(target);lua.globals().opponent=opponent
                lua.execute(r'''
                  seed_owner();local old=package_family=="f200"and"5.0.20008"or"5.0.21008"
                  history.default_owner_apply(history.default_owner_preflight(owner_event(old),nil,true));finite_entry(1)
                  local plan,legacy=delegate();assert(plan.prior_state==nil)
                  if opponent=="state-created"then storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                  elseif opponent=="last-force-work"then detached.technologies[ORDINARY].saved_progress=.29
                  else storage[OWNER_KEY]=copy(storage[OWNER_KEY])end
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_apply,plan))
                  assert(writes==0 and same(before,all_frames())and not pcall(history.apply,legacy))
                ''')


    def test_new_selection_keeps_only_existing_501_empty_exception(self):
        for target in ("f200", "f210"):
            for patch in range(12):
                lua=self.world(target);lua.globals().patch=patch
                lua.execute(r'''
                  local old=string.format("5.0.%d",(package_family=="f200"and 20000 or 21000)+patch)
                  script.active_mods.observer="1";local event=owner_event(old);event.mod_changes.observer={new_version="1"}
                  local before=all_frames();writes=0
                  local ok,plan=pcall(history.default_owner_preflight,event,nil,true)
                  assert(writes==0 and same(before,all_frames()))
                  if package_family=="f200"and patch==1 then
                    assert(ok and plan.record.producer.kind=="older-mir501-empty-default")
                    assert(history.default_owner_apply(plan))
                  else assert(not ok and storage[OWNER_KEY]==nil)end
                ''')

    def test_same_edition_public_group_does_not_extend_direct_base_hop(self):
        for patch in range(9):
            lua=self.world();lua.globals().patch=patch
            lua.execute(r'''
              seed_owner();storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
              local event=owner_event(string.format("5.0.%d",20000+patch))
              event.mod_changes.base={old_version="2.0.77",new_version="2.1.23"}
              local before=all_frames();writes=0
              assert(not pcall(history.default_owner_preflight,event,nil,true))
              assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
            ''')

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

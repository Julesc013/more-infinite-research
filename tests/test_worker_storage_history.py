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
                    'package.loaded["platform.target"]={id=declared_target}')
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
        for old in ("4.7.21003","5.0.21001","5.0.21008","5.0.20011"):
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
          'event.mod_changes.foreign={old_version="1",new_version="2"}','script.active_mods.foreign="1"',
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
                       'state.producer.old_version="5.0.21008"','state.forces[2].retired_flags.disabled_by_mir=true',
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
        for target, old in (("f210","5.0.21001"),("f210","4.7.21003"),("f200","5.0.20002"),("f200","4.7.20002")):
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

"""Worker continuation identity guards; host doubles are not native save proof."""
import argparse
from pathlib import Path
import sys
import unittest

import test_bootstrap as bootstrap_fixture
from worker_storage_recovery_fixture import MINIMAL_NATIVE_FACTS, RECOVERY_WORLD


class WorkerStorageHistoryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (Path(__file__).resolve().parents[1] / "source").as_posix()
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
    """Draft transfer only: native-level effects are independent host expectations."""

    def world(self, target="f210"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (Path(__file__).resolve().parents[1] / "source").as_posix()
        lua.globals().package_family = target
        lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          local f200=package_family=="f200"
          package.loaded["platform.target"]={id=package_family,minimum_base=f200 and "2.0.77" or "2.1.23",
            distribution_version=f200 and "5.0.20012" or "5.0.21012"}
        ''')
        lua.execute(RECOVERY_WORLD)
        lua.execute(r'''
          local target=require("platform.target")
          script.active_mods.base=target.minimum_base;script.active_mods["more-infinite-research"]=target.distribution_version
          ORDINARY="mir-worker-storage-default-5";HEAD="mir-worker-storage-head-4";OWNER_KEY="mir_worker_storage_native_owner"
          local function copy(t)if type(t)~="table"then return t end local o={}for k,v in pairs(t)do o[k]=copy(v)end return o end
          prototypes.technology[ORDINARY]=copy(prototypes.technology[CANONICAL])
          prototypes.technology[ORDINARY].name=ORDINARY;prototypes.technology[ORDINARY].level=5
          prototypes.technology[ORDINARY].hidden=false;prototypes.technology[ORDINARY].visible_when_disabled=false
          prototypes.technology[ORDINARY].prerequisites[HEAD]={name=HEAD}
          prototypes.technology[HEAD]=copy(prototypes.technology[CANONICAL])
          local gate=prototypes.technology[HEAD]
          gate.name=HEAD;gate.max_level=4;gate.hidden=true;gate.enabled=false;gate.visible_when_disabled=false
          gate.effects[1].modifier=0;gate.research_unit_count_formula=nil;gate.research_unit_count=1
          gate.research_unit_energy=60;gate.prerequisites={}
          creators[ORDINARY]="more-infinite-research";creators[HEAD]="more-infinite-research"
          detached=make_force("detached",4);game.forces.detached=detached
          queue_writes={}
          for _,force in pairs(game.forces)do
            force.technologies[HEAD]={name=HEAD,level=4,researched=false,enabled=false,visible_when_disabled=false,
              saved_progress=0,prototype=prototypes.technology[HEAD],force=force,prerequisites={}}
            local t={name=ORDINARY,level=5,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
              force=force,prototype=prototypes.technology[ORDINARY],
              prerequisites={foundation={researched=true},[HEAD]=force.technologies[HEAD]}}
            local function earned()return (t.level-5+(t.researched and 1 or 0))*prototypes.technology[ORDINARY].effects[1].modifier end
            force.technologies[ORDINARY]=setmetatable({}, {__index=function(_,key)
              if key=="research_unit_count"then return math.floor(100*2^(t.level-4))end;return t[key]
            end,__newindex=function(_,key,value)
              writes=writes+1
              if key=="level"then local old=earned();t.level=value;t.researched=false;t.enabled=true;t.saved_progress=0;force.bonus=force.bonus+earned()-old
              elseif key=="researched"then local old=earned();t.researched=value;force.bonus=force.bonus+earned()-old
              else t[key]=value end
            end})
            -- Independent native queue admission: an infinite prerequisite's
            -- paid first level suffices; an incomplete finite range does not.
            local mt=getmetatable(force);local write=mt.__newindex
            mt.__newindex=function(object,key,value)
              if key=="research_queue"then
                queue_writes[force.index]=(queue_writes[force.index]or 0)+1
                local admitted={}
                for _,id in ipairs(value)do
                  local candidate=force.technologies[type(id)=="string"and id or id.name];local valid=candidate and candidate.enabled
                  for _,p in pairs(candidate and candidate.prerequisites or {})do
                    local proto=p.prototype
                    if not p.researched and not(proto and proto.max_level==4294967295 and p.level>proto.level)then valid=false end
                  end
                  if valid then admitted[#admitted+1]=id end
                end
                value=admitted
              end
              write(object,key,value)
            end
          end
          function owner_event(old)
            return {mod_startup_settings_changed=false,mod_changes={["more-infinite-research"]={old_version=old,new_version=target.distribution_version}}}
          end
          function seed_owner()
            seed();detached.technologies[CANONICAL].level=6;detached.technologies[CANONICAL].saved_progress=.23
            detached.research_queue={OTHER};detached.research_progress=.625
            for _,force in pairs(game.forces)do force.bonus=force.bonus+17 end
            writes=0;queue_writes={}
          end
          function frame(force)
            local q={}for i,t in ipairs(force.research_queue)do q[i]=t.name end
            local c,t=force.technologies[CANONICAL],force.technologies[ORDINARY]
            return {sourcelevel=c.level,sourceresearched=c.researched,sourceenabled=c.enabled,sourcevisible=c.visible_when_disabled,
              sourcesaved=c.saved_progress,targetlevel=t.level,targetresearched=t.researched,targetenabled=t.enabled,
              targetvisible=t.visible_when_disabled,targetsaved=t.saved_progress,gateresearched=force.technologies[HEAD].researched,
              current=force.current_research and force.current_research.name,
              progress=force.research_progress,queue=q,bonus=force.worker_robots_storage_bonus,othersaved=force.technologies[OTHER].saved_progress}
          end
          function same(a,b)if type(a)~=type(b)then return false end;if type(a)~="table"then return a==b end
            for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
          function all_frames()local out={}for _,force in pairs(game.forces)do out[force.index]=frame(force)end;return out end
        ''')
        return lua

    def test_transfer_preserves_four_native_frames_bonus_and_legacy_marker(self):
        lua = self.world()
        lua.execute(r'''
          seed_owner();local old={schema=2,kind="route",current={kind="default"}};storage.mir_worker_storage_route=old
          local before=all_frames();local plan=history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false)
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
          assert(history.apply_default_owner_transfer(plan));local state=storage[OWNER_KEY]
          assert(state.schema==2 and state.kind=="split-default" and state.owner==ORDINARY and state.source==CANONICAL)
          assert(storage.mir_worker_storage_route==old and state.progress==nil)
          local levels={8,5,7,6};local bonuses={24,20,23,22}
          for _,f in pairs(game.forces)do
            local c,t=f.technologies[CANONICAL],f.technologies[ORDINARY]
            assert(c.level==(f.index==2 and 4 or 5) and not c.researched and c.saved_progress==0)
            assert(c.enabled==before[f.index].sourceenabled and c.visible_when_disabled==before[f.index].sourcevisible)
            assert(t.level==levels[f.index] and not t.researched and f.worker_robots_storage_bonus==bonuses[f.index])
            local record=state.forces[f.index];assert(record.phase==(f.index==2 and "head" or "tail"))
            assert(record.retired_flags.enabled==before[f.index].sourceenabled)
            assert(record.retired_flags.disabled_by_mir==false and record.retired_flags.visibility_hidden_by_mir==false)
            assert(f.technologies[HEAD].researched==(f.index~=2) and record.progress==nil and record.level==nil)
            assert(f.technologies[ID].level==4 and not f.technologies[ID].enabled)
          end
          assert(player.current_research.name==ORDINARY and player.research_progress==.375 and player.research_queue[2].name==OTHER)
          assert(suspended.current_research.name==OTHER and suspended.research_progress==.42 and suspended.research_queue[2].name==ORDINARY)
          assert(suspended.technologies[ORDINARY].saved_progress==.27)
          assert(detached.current_research.name==OTHER and detached.research_progress==.625 and detached.technologies[ORDINARY].saved_progress==.23)
          assert(not uninvested.technologies[ORDINARY].enabled and uninvested.research_progress==.125)
          assert(queue_writes[1]==1 and queue_writes[3]==1 and queue_writes[2]==nil and queue_writes[4]==nil)
          writes=0;assert(history.apply_default_owner_transfer(plan)==false and writes==0 and storage[OWNER_KEY]==state)
          player.technologies[ORDINARY].level=9;local after=all_frames();writes=0
          local again=history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false)
          assert(history.apply_default_owner_transfer(again)==false and writes==0 and same(after,all_frames()))
        ''')

    def test_completed_true_and_foreign_disabled_flags_keep_exact_native_benefit(self):
        lua = self.world()
        lua.execute(r'''
          player.technologies[CANONICAL].level=8;player.technologies[CANONICAL].researched=true
          player.technologies[CANONICAL].enabled=false;player.technologies[CANONICAL].visible_when_disabled=true
          writes=0;local p=history.plan_default_owner_transfer(owner_event("5.0.21010"),nil,false)
          history.apply_default_owner_transfer(p)
          assert(player.worker_robots_storage_bonus==8 and player.technologies[ORDINARY].level==9)
          assert(not player.technologies[ORDINARY].researched and not player.technologies[ORDINARY].enabled)
          assert(player.technologies[ORDINARY].visible_when_disabled)
          local flags=storage[OWNER_KEY].forces[1].retired_flags
          assert(flags.enabled==false and flags.disabled_by_mir==false and flags.visible and not flags.visibility_hidden_by_mir)
        ''')

    def test_configured_zero_and_two_unit_effects_conserve_independent_native_totals(self):
        for reward in (0, 2):
            with self.subTest(reward=reward):
                lua=self.world();lua.globals().reward=reward
                lua.execute(r'''
                  prototypes.technology[CANONICAL].effects[1].modifier=reward
                  prototypes.technology[ORDINARY].effects[1].modifier=reward
                  seed_owner();local expected={20+4*reward,20,20+3*reward,20+2*reward}
                  history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false))
                  for _,f in pairs(game.forces)do assert(f.worker_robots_storage_bonus==expected[f.index])end
                ''')

    def test_empty_initialization_and_exact_old_nil_producers_both_sdk_families(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua=self.world(target)
                lua.execute(r'''
                  local plan=history.plan_default_owner_transfer(nil,nil,true);assert(writes==0)
                  assert(history.apply_default_owner_transfer(plan) and storage.mir_worker_storage_route==nil)
                ''')
            for patch in (9,10,11):
                with self.subTest(target=target,patch=patch):
                    lua=self.world(target)
                    lua.globals().old_patch=patch
                    lua.execute(r'''
                      seed_owner();local old=string.format("5.0.%s%02d",package_family=="f200" and "200" or "210",old_patch)
                      local plan=history.plan_default_owner_transfer(owner_event(old),nil,false)
                      assert(writes==0);history.apply_default_owner_transfer(plan)
                      assert(storage.mir_worker_storage_route==nil and player.technologies[ORDINARY].level==8)
                    ''')

    def test_recorded_default_has_its_own_authority_but_prepared_conversion_is_not_admitted(self):
        lua=self.world()
        lua.execute(r'''
          seed_owner();script.active_mods.foreign="1"
          storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
          assert(history.apply_default_owner_transfer(history.plan_default_owner_transfer({mod_startup_settings_changed=false,mod_changes={}},nil,false)))
        ''')
        lua=self.world()
        lua.execute(r'''
          seed_owner();history.prepare(nil);local before=all_frames();writes=0
          assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false))
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
        ''')

    def test_all_force_contract_custody_policy_and_origin_opponents_are_no_write(self):
        opponents=[
            'creators[CANONICAL]="foreign"','creators[ORDINARY]="foreign"',
            'prototypes.technology[CANONICAL].max_level=4','prototypes.technology[ORDINARY].effects[1].modifier=2',
            'prototypes.technology[ORDINARY].research_unit_energy=3600',
            'prototypes.technology[ORDINARY].research_unit_ingredients[1].amount=2',
            'prototypes.technology[ORDINARY].research_unit_count_formula="200*2^(L-4)"',
            'prototypes.technology[ORDINARY].ignore_tech_cost_multiplier=true',
            'prototypes.technology[ORDINARY].effects[2]={type="worker-robot-storage",modifier=1,hidden=false}',
            'prototypes.technology[ORDINARY].prerequisites={different={name="different"}}',
            'suspended.technologies[ORDINARY].saved_progress=.1','detached.technologies[ORDINARY].level=6',
            'uninvested.technologies[ORDINARY].enabled=false','event.mod_startup_settings_changed=true',
            'event.mod_changes["more-infinite-research"].old_version="5.0.21008"',
            'event.mod_changes["more-infinite-research"].old_version="5.0.20011"',
            'event.mod_changes["more-infinite-research"].new_version="5.0.21013"',
            'event.mod_changes.foreign={old_version="1",new_version="2"}',
            'script.active_mods.foreign="1"','prototypes.technology["worker-robots-storage-5"]={}',
            'route=provider_route(5)', 'suspended.technologies[CANONICAL].saved_progress=1',
            'creators[HEAD]="foreign"', 'prototypes.technology[HEAD].effects[1].modifier=1',
            'prototypes.technology[HEAD].research_unit_count=2', 'prototypes.technology[HEAD].research_unit_energy=1',
            'prototypes.technology[HEAD].research_unit_ingredients[1].name="wrong-pack"',
            'prototypes.technology[ORDINARY].prerequisites[HEAD]=nil', 'suspended.technologies[HEAD].researched=true'
        ]
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua=self.world();lua.execute('seed_owner();event=owner_event("5.0.21011");route=nil;'+opponent+r'''
                  local before=all_frames();writes=0
                  assert(not pcall(history.plan_default_owner_transfer,event,route,false),"opponent admitted")
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                ''')

    def test_initial_investment_stale_plan_and_malformed_owner_record_refuse(self):
        lua=self.world();lua.execute(r'''
          player.technologies[CANONICAL].saved_progress=.1;writes=0
          assert(not pcall(history.plan_default_owner_transfer,nil,nil,true) and writes==0)
        ''')
        lua=self.world();lua.execute(r'''
          seed_owner();local plan=history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false)
          suspended.technologies[CANONICAL].saved_progress=.28;local before=all_frames();writes=0
          assert(not pcall(history.apply_default_owner_transfer,plan) and writes==0 and same(before,all_frames()))
        ''')
        for opponent in ('schema=3','owner="worker-robots-storage-4"','unexpected=true'):
            lua=self.world();lua.execute('storage[OWNER_KEY]={'+opponent+r'''};writes=0
              assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false) and writes==0)
            ''')

    def test_multiple_queue_entries_and_unrelated_saved_work_are_transferred_exactly(self):
        lua=self.world();lua.execute(r'''
          seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER};player.research_progress=.375
          player.technologies[OTHER].saved_progress=.19;writes=0;history.configure(9,true)
          history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false))
          assert(#player.research_queue==3 and player.research_queue[1].name==ORDINARY
            and player.research_queue[2].name==ORDINARY and player.research_queue[3].name==OTHER)
          assert(player.research_progress==.375 and player.technologies[OTHER].saved_progress==.19)
          assert(player.worker_robots_storage_bonus==24 and player.technologies[ORDINARY].level==8)
        ''')

    def test_real_owner_record_opponents_do_not_grant_retirement_or_rewrite_native_work(self):
        for opponent in (
                'state.producer.old_version="5.0.21008"', 'state.producer.new_version="unproved"',
                'state.forces[2].retired_flags.disabled_by_mir=true', 'state.forces[99]=state.forces[1]',
                'state.contract="changed"', 'player.technologies[CANONICAL].saved_progress=.1'):
            with self.subTest(opponent=opponent):
                lua=self.world();lua.execute(r'''
                  seed_owner();history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false))
                  state=storage[OWNER_KEY]
                '''+opponent+r'''
                  local before=all_frames();writes=0
                  assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false))
                  assert(writes==0 and storage[OWNER_KEY]==state and same(before,all_frames()))
                ''')

    def test_level_setter_transient_disable_creates_no_worker_head_cap_right(self):
        lua=self.world();lua.execute(r'''
          seed_owner();local canonical=player.technologies[CANONICAL]
          local mt=getmetatable(canonical);local write=mt.__newindex
          mt.__newindex=function(object,key,value)
            write(object,key,value)
            if key=="level" and value==5 then write(object,"enabled",false)end
          end
          history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false))
          local state=storage[OWNER_KEY];local flags=state.forces[1].retired_flags
          assert(flags.enabled and flags.disabled_by_mir==false and canonical.enabled)
          writes=0;assert(history.apply_default_owner_transfer(history.plan_default_owner_transfer({},nil,false))==false and writes==0)
        ''')

    def test_unpaid_head_current_queued_detached_and_flags_remain_native_for_zero_and_two(self):
        for reward in (0, 2):
            with self.subTest(reward=reward):
                lua=self.world();lua.globals().reward=reward
                lua.execute(r'''
                  prototypes.technology[CANONICAL].effects[1].modifier=reward
                  prototypes.technology[ORDINARY].effects[1].modifier=reward
                  seed_owner()
                  player.technologies[CANONICAL].level=4;player.technologies[CANONICAL].visible_when_disabled=true
                  suspended.technologies[CANONICAL].level=4;suspended.technologies[CANONICAL].saved_progress=.27
                  detached.technologies[CANONICAL].level=4;detached.technologies[CANONICAL].saved_progress=.23
                  local before=all_frames();writes=0;queue_writes={};history.configure(4,true)
                  history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false))
                  for _,f in pairs(game.forces)do
                    local actual,old=frame(f),before[f.index];local record=storage[OWNER_KEY].forces[f.index]
                    assert(record.phase=="head" and not record.retired_flags.disabled_by_mir and not record.retired_flags.visibility_hidden_by_mir)
                    for _,key in ipairs{"sourcelevel","sourceresearched","sourceenabled","sourcevisible","sourcesaved","current","progress","queue","bonus","othersaved"}do
                      assert(same(actual[key],old[key]),key)
                    end
                    assert(actual.bonus==20 and actual.targetlevel==5 and not actual.targetenabled and not actual.targetresearched)
                    assert(not actual.gateresearched and queue_writes[f.index]==nil)
                  end
                  assert(player.current_research.name==CANONICAL and player.research_progress==.375)
                  assert(suspended.research_queue[2].name==CANONICAL and suspended.technologies[CANONICAL].saved_progress==.27)
                  -- The eventual head completion is intentionally a later
                  -- wiring obligation, not an on_tick snapshot conversion.
                  player.technologies[CANONICAL].researched=true;writes=0
                  assert(not pcall(history.plan_default_owner_transfer,{},nil,false) and writes==0)
                ''')

    def test_earned_public_first_level_keeps_foreign_prerequisite_and_exact_queue(self):
        for reward in (0, 2):
            with self.subTest(reward=reward):
                lua=self.world();lua.globals().reward=reward
                lua.execute(r'''
                  prototypes.technology[CANONICAL].effects[1].modifier=reward
                  prototypes.technology[ORDINARY].effects[1].modifier=reward
                  seed_owner();player.technologies[OTHER].prerequisites={[CANONICAL]=player.technologies[CANONICAL]}
                  player.research_queue={CANONICAL,OTHER};player.research_progress=.375;writes=0;queue_writes={}
                  history.apply_default_owner_transfer(history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false))
                  local head,tail=player.technologies[CANONICAL],player.technologies[ORDINARY]
                  assert(head.level==5 and not head.researched and head.level>head.prototype.level)
                  assert(tail.level==8 and not tail.researched and player.technologies[HEAD].researched)
                  assert(player.worker_robots_storage_bonus==20+reward+3*reward)
                  assert(#player.research_queue==2 and player.current_research.name==ORDINARY and player.research_queue[2].name==OTHER)
                  assert(player.research_progress==.375 and queue_writes[1]==1)
                ''')
        lua=self.world();lua.execute(r'''
          seed_owner();player.technologies[OTHER].prerequisites={finite={researched=false,level=5,prototype={level=4,max_level=8}}}
          local before=all_frames();writes=0
          assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false))
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
        ''')

    def test_old_reset_to_unpaid_public_four_loses_native_capacity_and_cannot_commit(self):
        lua=self.world()
        source=(Path(__file__).resolve().parents[1]/"source/runtime/worker_robot_storage.lua").read_text()
        literal="if frame.next_level ~= 5 or frame.researched then canonical.level = 5 end"
        self.assertEqual(source.count(literal),1)
        lua.globals().mutant_runtime=source.replace(literal,"canonical.level = 4 -- injected prior reset defect",1)
        lua.execute(r'''
          history=assert(load(mutant_runtime))();seed_owner()
          local plan=history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false)
          local ok,err=pcall(history.apply_default_owner_transfer,plan)
          assert(not ok and tostring(err):find("native default split did not preserve",1,true))
          assert(player.worker_robots_storage_bonus==23 and storage[OWNER_KEY]==nil)
        ''')

class WorkerDefaultNativeLifecycleTests(unittest.TestCase):
    def world(self, target="f210"):
        lua=WorkerDefaultNativeOwnerTransferTests.world(self,target)
        lua.execute(r'''
          local gaps={}
          for _,force in pairs(game.forces)do
            local index=force.index
            local mt=getmetatable(force);local read,write=mt.__index,mt.__newindex
            mt.__index=function(object,key)
              if gaps[index]and key=="current_research"then return nil end
              if gaps[index]and key=="research_progress"then return 0 end
              return read(object,key)
            end
            mt.__newindex=function(object,key,value)
              if key=="research_queue"and gaps[index]then
                local saved={}for _,entry in ipairs(read(object,"research_queue"))do saved[entry.name]=entry.saved_progress end
                write(object,key,{})
                for name,progress in pairs(saved)do force.technologies[name].saved_progress=progress end
                gaps[index]=nil
              end
              write(object,key,value)
            end
          end
          function init_default()
            history.on_init(nil);assert(history.default_owner_on_init(nil,true))
            writes=0;queue_writes={}
          end
          function finish_frame(force,representation,remainder,gap)
            local head=force.technologies[CANONICAL]
            force.research_progress=0;head.saved_progress=0
            if representation=="completed"then head.researched=true else head.level=5 end
            force.research_queue=remainder;force.research_progress=0
            if gap then gaps[force.index]=true end
            writes=0;queue_writes={}
          end
          function finish_event(force)return {research=force.technologies[CANONICAL],by_script=false,tick=100}end
          function new_head_force(name,index)
            local f=make_force(name,index)
            f.technologies[HEAD]={name=HEAD,level=4,researched=false,enabled=false,visible_when_disabled=false,saved_progress=0,
              research_unit_count=1,prototype=prototypes.technology[HEAD],force=f,prerequisites={}}
            f.technologies[ORDINARY]={name=ORDINARY,level=5,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
              research_unit_count=200,prototype=prototypes.technology[ORDINARY],force=f,
              prerequisites={foundation={researched=true},[HEAD]=f.technologies[HEAD]}}
            game.forces[name]=f;return f
          end
        ''')
        return lua

    def test_existing_init_order_no_split_noop_and_unsupported_owned_routes(self):
        lua=self.world();lua.execute(r'''
          init_default();assert(storage.mir_worker_storage_route.current.kind=="default")
          assert(history.needs_research_events())
          local state=storage[OWNER_KEY];local before=all_frames();writes=0
          assert(not pcall(history.default_owner_preflight,{mod_startup_settings_changed=false,mod_changes={}},nil,false))
          assert(not pcall(history.default_owner_preflight,{},provider_route(5),true))
          assert(writes==0 and storage[OWNER_KEY]==state and same(before,all_frames()))
        ''')
        lua=self.world();lua.execute(r'''
          game=nil;prototypes=nil
          assert(history.default_owner_preflight({},nil,false)==nil)
          assert(history.default_owner_preflight({},provider_route(5),true)==nil)
          assert(history.default_owner_apply(nil)==false and history.default_owner_on_init(nil,false)==false)
        ''')

    def test_first_finish_nil_current_remainder_preserves_all_repeats_both_representations_and_families(self):
        for target in ("f200","f210"):
            for representation in ("completed","advanced"):
                with self.subTest(target=target,representation=representation):
                    lua=self.world(target);lua.globals().representation=representation
                    lua.execute(r'''
                      init_default();player.research_queue={CANONICAL,CANONICAL,CANONICAL,OTHER};player.research_progress=.375
                      suspended.technologies[CANONICAL].saved_progress=.27;suspended.research_queue={OTHER,CANONICAL};suspended.research_progress=.42
                      local untouched=frame(suspended)
                      finish_frame(player,representation,{CANONICAL,CANONICAL,OTHER},true)
                      assert(player.current_research==nil and player.research_progress==0)
                      assert(history.default_owner_on_research_finished(finish_event(player)))
                      assert(player.technologies[CANONICAL].level==5 and not player.technologies[CANONICAL].researched)
                      assert(player.technologies[HEAD].researched and player.technologies[ORDINARY].level==5)
                      assert(player.worker_robots_storage_bonus==4 and player.current_research.name==ORDINARY and player.research_progress==0)
                      assert(#player.research_queue==3 and player.research_queue[2].name==ORDINARY and player.research_queue[3].name==OTHER)
                      assert(same(untouched,frame(suspended)) and storage[OWNER_KEY].forces[1].phase=="tail")
                    ''')

    def test_finished_remainder_activates_saved_foreign_work_once_without_inventing_current(self):
        lua=self.world();lua.execute(r'''
          init_default();player.research_queue={CANONICAL,OTHER,CANONICAL};player.research_progress=.375
          finish_frame(player,"completed",{OTHER,CANONICAL},true)
          player.technologies[OTHER].saved_progress=.19
          assert(player.current_research==nil and player.research_progress==0)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          assert(player.current_research.name==OTHER and player.research_progress==.19 and player.technologies[OTHER].saved_progress==0)
          assert(player.research_queue[2].name==ORDINARY and player.technologies[ORDINARY].saved_progress==0)
          assert(player.worker_robots_storage_bonus==4)
        ''')

    def test_completed_still_current_progress_one_refuses_before_any_setter(self):
        lua=self.world();lua.execute(r'''
          init_default();player.research_queue={CANONICAL,CANONICAL};player.research_progress=1
          player.technologies[CANONICAL].researched=true;local before=all_frames();local state=storage[OWNER_KEY];writes=0
          assert(not pcall(history.default_owner_on_research_finished,finish_event(player)))
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state and not player.technologies[HEAD].researched)
        ''')

    def test_readonly_load_reconnects_heads_and_rejects_malformed_records_without_game(self):
        lua=self.world();lua.execute(r'''
          init_default();local state=storage[OWNER_KEY];local oldgame,oldprototypes=game,prototypes
          game=setmetatable({},{__index=function()error("game read during load")end})
          prototypes=setmetatable({},{__index=function()error("prototype read during load")end});writes=0
          for i=1,2 do history.on_load();history.default_owner_on_load(true);assert(storage[OWNER_KEY]==state and history.needs_research_events())end
          assert(writes==0);state.forces[1].unexpected=true
          assert(not pcall(history.default_owner_on_load,true) and writes==0)
          game,prototypes=oldgame,oldprototypes
        ''')

    def test_ordinary_setting_contract_updates_and_standard_capped_head_visibility_are_not_frozen(self):
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(player,"advanced",{},false);history.default_owner_on_research_finished(finish_event(player))
          local head=player.technologies[CANONICAL];head.enabled=false;head.visible_when_disabled=true
          local state=storage[OWNER_KEY];local before=all_frames();local oldcontract=state.contract
          prototypes.technology[CANONICAL].research_unit_energy=3600;prototypes.technology[ORDINARY].research_unit_energy=3600
          prototypes.technology[CANONICAL].enabled=false;prototypes.technology[ORDINARY].enabled=false
          history.configure(0,false);writes=0
          local plan=history.default_owner_preflight({mod_startup_settings_changed=true,mod_changes={}},nil,true)
          assert(plan.items and plan.already_owned and writes==0)
          assert(history.default_owner_apply(plan) and writes==0 and same(before,all_frames()))
          assert(storage[OWNER_KEY].contract~=oldcontract and storage[OWNER_KEY].forces[1].phase=="tail")
          assert(not head.enabled and head.visible_when_disabled)
        ''')

    def test_manual_legacy_prepare_is_blocked_before_writes_on_native_owner(self):
        lua=self.world();lua.execute(r'''
          init_default();local before=all_frames();local state=storage[OWNER_KEY];writes=0
          assert(not pcall(history.prepare,nil) and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state)
        ''')

    def test_mutating_guard_is_same_force_skips_nested_worker_and_restores_after_error(self):
        for fail in (False,True):
            with self.subTest(fail=fail):
                lua=self.world();lua.globals().fail=fail
                lua.execute(r'''
                  init_default();player.technologies[CANONICAL].level=6;player.research_queue={CANONICAL};player.research_progress=0
                  local t=player.technologies[ORDINARY];local mt=getmetatable(t);local write=mt.__newindex
                  local checks=0
                  mt.__newindex=function(object,key,value)
                    if key=="level"then
                      assert(history.default_owner_mutating{research={force=player}})
                      assert(not history.default_owner_mutating{force=uninvested})
                      assert(history.default_owner_on_research_finished(finish_event(player))==false);checks=checks+1
                      if fail then error("injected native setter failure")end
                    end
                    write(object,key,value)
                  end
                  local ok,err=pcall(history.default_owner_on_research_finished,finish_event(player))
                  assert(checks==1 and not history.default_owner_mutating{force=player})
                  if fail then assert(not ok and tostring(err):find("injected native setter failure",1,true))
                  else assert(ok and player.worker_robots_storage_bonus==5 and t.level==6)end
                ''')

    def test_force_creation_and_native_reset_never_restore_cached_earned_levels(self):
        lua=self.world();lua.execute(r'''
          init_default();local fresh=new_head_force("new",5);writes=0
          history.on_force_created{force=fresh};assert(history.default_owner_on_force_created{force=fresh})
          assert(storage[OWNER_KEY].forces[5].phase=="head" and not fresh.technologies[ORDINARY].enabled)
          finish_frame(player,"advanced",{},false);history.default_owner_on_research_finished(finish_event(player))
          player.technologies[ORDINARY].level=7;assert(player.worker_robots_storage_bonus==6)
          player.research_queue={};player.technologies[CANONICAL].level=4;player.technologies[ORDINARY].level=5
          player.technologies[HEAD].researched=false
          history.on_force_reset{force=player};writes=0
          assert(history.default_owner_on_force_reset{force=player})
          assert(storage[OWNER_KEY].forces[1].phase=="head" and player.worker_robots_storage_bonus==3)
          assert(player.technologies[CANONICAL].level==4 and player.technologies[ORDINARY].level==5)
        ''')

    def test_native_merge_updates_metadata_only_and_marks_unknown_mixed_pending_shape_unqualified(self):
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(player,"advanced",{},false);history.default_owner_on_research_finished(finish_event(player))
          game.forces.uninvested=nil;local before=all_frames();writes=0
          local ok,kind=history.default_owner_on_forces_merged{source_index=2,destination=player}
          assert(ok and kind=="native-merge-metadata-only" and writes==0 and same(before,all_frames()))
          assert(storage[OWNER_KEY].forces[2]==nil and storage[OWNER_KEY].forces[1].phase=="tail")
          game.forces.detached=nil;before=all_frames();writes=0
          assert(history.default_owner_on_forces_merged{source_index=4,destination=suspended})
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY].forces[3].phase=="head")
        ''')
        lua=self.world();lua.execute(r'''
          init_default();finish_frame(player,"advanced",{},false);history.default_owner_on_research_finished(finish_event(player))
          player.technologies[ORDINARY].level=8;player.research_queue={CANONICAL};player.research_progress=.2
          game.forces.uninvested=nil;local before=all_frames();local state=storage[OWNER_KEY];writes=0
          local ok,kind=history.default_owner_on_forces_merged{source_index=2,destination=player}
          assert(not ok and kind=="unqualified-native-merge-frame" and writes==0)
          assert(same(before,all_frames()) and storage[OWNER_KEY]==state)
        ''')

    def test_legal_unpaid_head_duplicate_queue_cap_four_preserves_work_before_policy(self):
        lua=self.world();lua.execute(r'''
          history.on_init(nil);player.research_queue={CANONICAL,CANONICAL,OTHER};player.research_progress=.37
          player.technologies[OTHER].saved_progress=.19;history.configure(4,true)
          local before=frame(player);writes=0;queue_writes={}
          local plan=history.default_owner_preflight(owner_event("5.0.21011"),nil,true)
          assert(writes==0);history.default_owner_apply(plan)
          assert(player.current_research.name==CANONICAL and player.research_progress==.37)
          assert(#player.research_queue==3 and player.research_queue[2].name==CANONICAL and queue_writes[1]==nil)
          assert(player.technologies[OTHER].saved_progress==.19 and storage[OWNER_KEY].forces[1].phase=="head")
          local caps=require("runtime.caps");local rights={}
          caps.reconcile(player,{[CANONICAL]=4},rights)
          assert(player.research_progress==.37 and #player.research_queue==2)
          assert(player.research_queue[1].name==CANONICAL and player.research_queue[2].name==OTHER)
          finish_frame(player,"advanced",{OTHER},true)
          player.technologies[OTHER].saved_progress=.19
          assert(history.default_owner_on_research_finished(finish_event(player)))
          caps.reconcile(player,{[CANONICAL]=4,[ORDINARY]=4},rights)
          assert(player.technologies[CANONICAL].level==5 and player.worker_robots_storage_bonus==4)
          assert(player.technologies[ORDINARY].level==5 and not player.technologies[ORDINARY].researched)
          assert(not player.technologies[ORDINARY].enabled and player.current_research.name==OTHER)
          assert(#player.research_queue==1 and player.research_progress==.19)
        ''')

    def test_recorded_default_overcap_disabled_detached_work_survives_settings_change(self):
        lua=self.world();lua.execute(r'''
          history.on_init(nil);seed_owner();player.research_queue={OTHER};player.research_progress=.42
          player.technologies[CANONICAL].saved_progress=.27;player.technologies[CANONICAL].enabled=false
          history.configure(7,false);local event=owner_event("5.0.21011");event.mod_startup_settings_changed=true
          local before=all_frames();local marker=storage.mir_worker_storage_route;writes=0;queue_writes={}
          local plan=history.default_owner_preflight(event,nil,true);assert(writes==0)
          history.default_owner_apply(plan)
          assert(player.technologies[ORDINARY].level==8 and not player.technologies[ORDINARY].enabled)
          assert(player.technologies[ORDINARY].saved_progress==.27 and player.worker_robots_storage_bonus==24)
          assert(player.current_research.name==OTHER and player.research_progress==.42 and queue_writes[1]==nil)
          assert(storage.mir_worker_storage_route==marker)
        ''')
        lua=self.world();lua.execute(r'''
          history.on_init(nil);seed_owner();player.technologies[CANONICAL].enabled=false
          local event=owner_event("5.0.21011");event.mod_startup_settings_changed=true
          local before=all_frames();writes=0
          assert(not pcall(history.default_owner_preflight,event,nil,true))
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
        ''')
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

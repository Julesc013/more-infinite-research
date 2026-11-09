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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

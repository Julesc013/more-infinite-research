"""Worker continuation identity guards; host doubles are not native save proof."""
import argparse
import ast
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest

from bootstrap_control_world import build_bootstrap_control_world
from worker_storage_default_world import (
    DEFAULT_WORKER_RUNTIME_CONFIGURATION,
    build_default_native_owner_world,
    build_full_default_provider_handover_world,
    build_older_default_admission_world,
    install_published_default_reader,
)
from worker_storage_recovery_fixture import MINIMAL_NATIVE_FACTS, RECOVERY_WORLD as RECOVERY_WORLD_FIXTURE

ROOT = Path(__file__).resolve().parents[1]

# Literal persisted contract in native SE seed CCC6EB4A (archive7A30), retained
# by capsule C11E5DA5. This is independent native input, not a production
# projection or an assertion that private7A30 was the published B0BF package.
NATIVE_517_SE_CONTRACT = (
    "worker-storage-1|20:worker-robot-storage|1:1|false|false|formula|13:675*1.5^(L-4)"
    "|4:3600|1:5|23:automation-science-pack|1:1|21:logistic-science-pack|1:1"
    "|21:chemical-science-pack|1:1|23:production-science-pack|1:1|20:utility-science-pack|1:1"
    "|1:2|20:utility-science-pack|23:worker-robots-storage-3"
)

# Explicit parse-time runtime configuration for these native-fact doubles.
# Real bootstrap controls use the actual resolver; older-origin controls below
# also exercise an imported profile through that resolver.
WORKER_RUNTIME_CONFIGURATION = DEFAULT_WORKER_RUNTIME_CONFIGURATION
RECOVERY_WORLD = WORKER_RUNTIME_CONFIGURATION + RECOVERY_WORLD_FIXTURE


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
          local writes=0
          storage=setmetatable({}, {__newindex=function()
            writes=writes+1;error("unknown legacy history wrote storage",0)
          end})
          for _,old in ipairs({"5.0.21008","4.7.21003","4.7.20003"}) do
            local ok,message=pcall(history.preflight,upgrade(old),route(4))
            assert(not ok and tostring(message):find("previous continuation ownership is unknown",1,true))
            assert(tostring(message):find("keep the protected original COPY",1,true))
            assert(not tostring(message):find("/mir-worker-storage-recovery prepare",1,true))
            assert(tostring(message):find("previous_mir="..old,1,true))
            assert(tostring(message):find("new_mir=5.0.21009",1,true))
            assert(tostring(message):find("saved_route=absent",1,true) and tostring(message):find("current_route=finite",1,true))
            assert(rawget(storage,"mir_worker_storage_route")==nil and writes==0)
          end
          assert(history.preflight(upgrade("5.0.21008"),nil)==nil)
        ''')

    def test_late_checked_route_lookup_keeps_its_exact_error_without_history_enrichment(self):
        self.lua.execute(r'''
          local writes=0
          storage=setmetatable({}, {__newindex=function()
            writes=writes+1;error("late checked route lookup wrote storage",0)
          end})
          local candidate=setmetatable({technology="worker-robots-storage-5",
            predecessor="worker-robots-storage-4",owned=true,legacy_compatible=true,
            finite={{name="worker-robots-storage-4",max_level=4,provider="foreign-finite"}}},
            {__index=function(_,key)
              assert(key=="level")
              error("late checked route lookup: previous continuation ownership is unknown",0)
            end})
          local ok,observed=pcall(history.preflight,upgrade("5.0.21008"),candidate)
          assert(not ok and observed=="late checked route lookup: previous continuation ownership is unknown")
          assert(not tostring(observed):find("MIR-WORKER-HISTORY",1,true))
          assert(not tostring(observed):find("previous_mir=",1,true))
          assert(rawget(storage,"mir_worker_storage_route")==nil and writes==0)
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

    def test_unexpected_legacy_read_error_is_not_classified_by_its_prose(self):
        self.lua.execute(r'''
          local rendered=0
          local opaque=setmetatable({}, {__tostring=function()
            rendered=rendered+1
            return "decoy: previous continuation ownership is unknown"
          end})
          for _,failure in ipairs({"decoy: previous continuation ownership is unknown", opaque,
              "unrelated legacy lookup failure"}) do
            local writes=0
            storage=setmetatable({}, {
              __index=function(_,key) if key=="mir" then error(failure,0) end end,
              __newindex=function() writes=writes+1;error("unexpected history write",0) end})
            local before=storage
            local ok,observed=pcall(history.preflight,upgrade("4.7.21003"),route(9))
            assert(not ok and observed==failure,"unexpected read error was replaced")
            assert(storage==before and rawget(storage,"mir_worker_storage_route")==nil and writes==0)
          end
          assert(rendered==0,"unexpected error was rendered for classification")
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
        lua = build_bootstrap_control_world(LuaRuntime, source_root=ROOT / "source")
        lua.execute(r'''
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

    def test_bootstrap_refusal_uses_explicit_world_not_bootstrap_testcase(self):
        import test_bootstrap as bootstrap_fixture

        missing_runtime = object()
        original_runtime = getattr(bootstrap_fixture, "LuaRuntime", missing_runtime)
        original_setup = bootstrap_fixture.BootstrapTests.setUp

        def forbidden_setup(_case):
            raise AssertionError("worker-history bootstrap selected borrowed BootstrapTests.setUp")

        bootstrap_fixture.BootstrapTests.setUp = forbidden_setup
        try:
            self.test_bootstrap_refuses_before_lifecycle_or_other_credit_writes()
        finally:
            bootstrap_fixture.BootstrapTests.setUp = original_setup
            if original_runtime is missing_runtime:
                if hasattr(bootstrap_fixture, "LuaRuntime"):
                    delattr(bootstrap_fixture, "LuaRuntime")
            else:
                bootstrap_fixture.LuaRuntime = original_runtime


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

    def test_prepare_refuses_unavailable_or_truncated_queues_before_any_force_writes(self):
        for incomplete in ("unavailable", "hole"):
            with self.subTest(incomplete=incomplete):
                self.setUp()
                self.lua.globals().incomplete = incomplete
                self.lua.execute(r'''
                  seed()
                  local force = suspended
                  if incomplete == "unavailable" then force.research_queue = {} end
                  local queue = force.research_queue
                  local observed = nil
                  if incomplete == "hole" then observed = {queue[1], [3]=queue[2]} end
                  local mt = getmetatable(force)
                  local read = mt.__index
                  mt.__index = function(object, key)
                    if key == "research_queue" and writes == 0 then return observed end
                    return read(object, key)
                  end
                  writes = 0
                  local ok, failure = pcall(history.prepare, nil)
                  mt.__index = read
                  assert(not ok and tostring(failure):find("native queue", 1, true),
                    "accepted an incomplete queue: " .. tostring(failure))
                  assert(writes == 0 and storage.mir_worker_storage_route == nil)
                  assert(force.research_queue == queue and force.technologies[CANONICAL].saved_progress == .27)
                  assert(player.current_research.name == CANONICAL and player.research_progress == .375)
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
          assert(message:find("keep the protected original COPY",1,true))
          assert(not message:find("/mir-worker-storage-recovery prepare",1,true))
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

    def test_public_prepare_does_not_swallow_failures_after_native_writes(self):
        for point in ("first-write", "queue", "later-force", "work-price"):
            with self.subTest(point=point):
                self.setUp()
                self.lua.globals().failure_point = point
                self.lua.execute(r'''
                  seed();local original={7,3,6}
                  assert(player.worker_robots_storage_bonus==original[1])
                  assert(uninvested.worker_robots_storage_bonus==original[2])
                  assert(suspended.worker_robots_storage_bonus==original[3])
                  local previous
                  if failure_point=="later-force"then
                    previous={schema=2,kind="route",current={kind="default"}}
                    storage.mir_worker_storage_route=previous
                  end
                  if failure_point=="queue"then
                    local mt=getmetatable(player);local write=mt.__newindex
                    mt.__newindex=function(o,k,v)
                      write(o,k,v)
                      if k=="research_queue"then error("injected after native queue assignment")end
                    end
                  else
                    local f=failure_point=="later-force"and suspended or player
                    local holder=f.technologies[ID];local mt=getmetatable(holder)
                    local read,write=mt.__index,mt.__newindex
                    if failure_point=="work-price"then
                      mt.__index=function(o,k)
                        if k=="research_unit_count"and read(o,"level")>4 then return 1 end
                        return read(o,k)
                      end
                    else
                      mt.__newindex=function(o,k,v)
                        write(o,k,v)
                        if k=="level"then error("injected after native holder write")end
                      end
                    end
                  end
                  local ok,message=pcall(history.command,{parameter="prepare"},nil)
                  assert(not ok,"public command swallowed a failure after native writes")
                  assert(tostring(message):find("reload the original",1,true),tostring(message))
                  local cause=failure_point=="work-price"and"native transferred work price differs"
                    or failure_point=="queue"and"injected after native queue assignment"
                    or "injected after native holder write"
                  assert(tostring(message):find(cause,1,true),tostring(message))
                  assert(writes>0 and storage.mir_worker_storage_route==previous)
                  if previous then assert(previous.schema==2 and previous.kind=="route"and previous.current.kind=="default")end
                  -- Failure containment is not rollback: retain the actual
                  -- partial frame, and do not manufacture a committed history.
                  if failure_point=="first-write"then
                    assert(writes==1 and player.technologies[CANONICAL].level==8)
                    assert(player.technologies[ID].level==8 and player.worker_robots_storage_bonus==11)
                  elseif failure_point=="later-force"then
                    assert(player.technologies[CANONICAL].level==4 and player.technologies[ID].level==8)
                    assert(suspended.technologies[CANONICAL].level==7 and suspended.technologies[ID].level==7)
                    assert(suspended.worker_robots_storage_bonus==9)
                  else
                    assert(player.technologies[CANONICAL].level==4 and player.technologies[ID].level==8)
                    assert(player.research_queue[1].name==ID and player.worker_robots_storage_bonus==7)
                  end
                  assert(#messages==0,"post-write failure was reduced to an ordinary reply")
                  -- If a host caller catches the fatal error, another prepare
                  -- still refuses the invested holder without adding writes.
                  local before=writes
                  assert(pcall(history.command,{parameter="prepare"},nil))
                  assert(writes==before and #messages==1 and messages[1]:find("MIR-WORKER-HISTORY",1,true))
                ''')

    def test_public_resume_does_not_swallow_failure_after_queue_assignment(self):
        self.lua.execute(r'''
          seed();suspended.research_queue={OTHER};suspended.research_progress=.42
          suspended.technologies[CANONICAL].saved_progress=.27
          assert(history.prepare(nil));writes=0
          local state=storage.mir_worker_storage_route
          local mt=getmetatable(suspended);local write=mt.__newindex
          mt.__newindex=function(o,k,v)
            write(o,k,v)
            if k=="research_queue"then error("injected after resume queue assignment")end
          end
          local ok,message=pcall(history.command,{parameter="resume suspended"},nil)
          assert(not ok and tostring(message):find("reload the original",1,true),tostring(message))
          assert(tostring(message):find("injected after resume queue assignment",1,true),tostring(message))
          assert(writes==1 and storage.mir_worker_storage_route==state)
          assert(suspended.research_queue[1].name==OTHER and suspended.research_queue[2].name==ID)
          assert(suspended.research_progress==.42 and suspended.worker_robots_storage_bonus==6)
          assert(state.forces[3].pending and #messages==0)
          -- assign_queue must still restore its force-local event gate.
          local read=mt.__index
          mt.__index=function(o,k)if k=="research_progress"then return nil end;return read(o,k)end
          ok,message=pcall(history.on_research_event,{research=suspended.technologies[ID]})
          assert(not ok and tostring(message):find("inconsistent native current/queue frame",1,true))
        ''')

    def test_public_recovery_preflight_refusal_is_readonly_and_can_be_corrected(self):
        self.lua.execute(r'''
          seed();creators[CANONICAL]="foreign-infinite"
          local queue=player.research_queue
          assert(pcall(history.command,{parameter="prepare"},nil))
          assert(writes==0 and storage.mir_worker_storage_route==nil and player.research_queue==queue)
          assert(player.worker_robots_storage_bonus==7 and suspended.worker_robots_storage_bonus==6)
          assert(#messages==1 and messages[1]:find("MIR-WORKER-HISTORY",1,true))
          creators[CANONICAL]="more-infinite-research"
          assert(pcall(history.command,{parameter="prepare"},nil))
          assert(storage.mir_worker_storage_route.kind=="prepared")
          assert(player.worker_robots_storage_bonus==7 and suspended.worker_robots_storage_bonus==6)
          local before=writes
          assert(pcall(history.command,{parameter="prepare"},nil))
          assert(writes==before and #messages==3 and messages[3]:find("Already prepared",1,true))
        ''')

    def test_public_resume_preflight_refusal_and_ordinary_success_preserve_work(self):
        self.lua.execute(r'''
          seed();suspended.research_queue={OTHER};suspended.research_progress=.42
          suspended.technologies[CANONICAL].saved_progress=.27
          assert(history.prepare(nil));writes=0
          local holder=suspended.technologies[ID]
          holder.prerequisites.foundation.researched=false
          assert(pcall(history.command,{parameter="resume suspended"},nil))
          assert(writes==0 and #suspended.research_queue==1 and suspended.research_progress==.42)
          assert(#messages==1 and messages[1]:find("prerequisite",1,true))
          holder.prerequisites.foundation.researched=true
          assert(pcall(history.command,{parameter="resume suspended"},nil))
          assert(suspended.research_queue[1].name==OTHER and suspended.research_queue[2].name==ID)
          assert(suspended.research_progress==.42 and holder.saved_progress==.27)
          assert(suspended.worker_robots_storage_bonus==6 and #messages==2)
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
        return build_default_native_owner_world(
            LuaRuntime, target=target, source_root=Path(__file__).resolve().parents[1] / "source"
        )

    def test_unrelated_research_does_not_read_the_worker_owner(self):
        lua = self.world()
        lua.execute(r'''
          init_default()
          local saved = assert(storage[OWNER_KEY])
          local other = assert(player.technologies[OTHER])
          assert(other.force == player)
          storage[OWNER_KEY] = nil
          local reads = 0
          setmetatable(storage, {__index=function(_, key)
            if key == OWNER_KEY then
              reads = reads + 1
              return saved
            end
          end})
          local handled, changed = history.default_owner_on_research_finished{research=other, by_script=false}
          assert(not handled and not changed)
          assert(reads == 0, "unrelated research read the worker owner")
        ''')

    def test_initial_native_mirror_keeps_one_award_and_unrelated_work(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  game.tick=0
                  set_reward(.25)
                  prototypes.technology[CANONICAL].visible_when_disabled=false
                  for _,f in ipairs{player,detached}do
                    f.technologies[CANONICAL].level=5
                    f.technologies[ORDINARY].level=5
                  end
                  player.research_queue={OTHER}
                  player.research_progress=.625
                  assert(player.worker_robots_storage_bonus==20.5)
                  local before=frame(player)
                  queue_writes={};progress_writes={}
                  history.on_init(nil)
                  assert(history.default_owner_on_init(nil,true))
                  for _,f in ipairs{player,detached}do
                    local after=frame(f)
                    assert(after.bonus==20.25 and after.owner.level==5 and after.owner.enabled)
                    assert(after.source.level==5 and not after.source.enabled)
                    assert(after.debit.level==5 and not after.debit.enabled)
                    assert(storage[OWNER_KEY].forces[f.index].retired_flags.disabled_by_mir)
                  end
                  local after=frame(player)
                  assert(same(before.owner,after.owner) and same(before.queue,after.queue))
                  assert(after.current==before.current and after.progress==before.progress)
                  assert(next(queue_writes)==nil and next(progress_writes)==nil)
                  local saved=all_frames();writes=0
                  history.default_owner_on_load()
                  assert(same(saved,all_frames()) and writes==0)
                ''')

    def test_initial_native_mirror_rejects_other_earned_or_unfinished_frames(self):
        for change in (
            "game.tick=1",
            "game.tick=nil",
            "detached.technologies[CANONICAL].level=4",
            "detached.technologies[ORDINARY].level=4",
            "detached.technologies[ORDINARY].level=6",
            "detached.technologies[ORDINARY].saved_progress=.125",
            "detached.technologies[CANONICAL].saved_progress=.125",
            "detached.research_queue={ORDINARY}",
            "detached.technologies[HEAD].level=5;detached.technologies[HEAD].enabled=false",
        ):
            with self.subTest(change=change):
                lua = self.world()
                lua.execute(r'''
                  game.tick=0
                  prototypes.technology[CANONICAL].visible_when_disabled=false
                  for _,f in ipairs{player,detached}do
                    f.technologies[CANONICAL].level=5
                    f.technologies[ORDINARY].level=5
                  end
                ''' + change + r'''
                  history.on_init(nil)
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_on_init,nil,true))
                  assert(same(before,all_frames()) and writes==0 and storage[OWNER_KEY]==nil)
                ''')

    def published517_world(self, cap):
        """Use the three actual published B0BF producer bodies, not a current initializer."""
        revision = "17e78c4d5d339413668e30e8eb422b915d390179"
        pins = {
            "runtime.caps": "A50E7D56082E8454FA40FA0DB0CD7DA33B5441FAA7A39AABAD9438A77E5A3C52",
            "research.worker_storage_recovery": "074D9EE66CFFC82DA30B6D1B950D7538A2E2C6E673C0E7B9D63BD36B12390381",
            "runtime.worker_robot_storage": "A393C05576193B6D3D16AEA125C185CD36AAF87BA9126720C87DDA479C1143F9",
        }
        historical = {}
        for name, expected in pins.items():
            body = subprocess.run(["git", "show", revision + ":source/" + name.replace(".", "/") + ".lua"],
                                  cwd=ROOT, check=True, capture_output=True).stdout
            self.assertEqual(expected, hashlib.sha256(body).hexdigest().upper(), name)
            historical[name] = body.decode("utf-8")
        lua = self.world("f200")
        install_published_default_reader(lua, historical_sources=historical)
        lua.globals().source_cap = cap
        lua.execute(r'''
          published517_source_contract(source_cap)
          published_version="5.0.20017";history=published_reader();history.configure(source_cap,true)
          init_default()
          assert(storage[OWNER_KEY].schema==3 and storage[OWNER_KEY].settings==nil
            and storage[OWNER_KEY].producer.kind=="initial-empty"
            and storage[OWNER_KEY].producer.new_version=="5.0.20017")
        ''')
        return lua

    def test_default_world_uses_the_explicit_runtime_factory(self):
        calls = []

        def factory(**kwargs):
            calls.append(kwargs)
            return LuaRuntime(**kwargs)

        lua = build_default_native_owner_world(
            factory, target="f200", source_root=Path(__file__).resolve().parents[1] / "source"
        )
        self.assertEqual(calls, [{"unpack_returned_tuples": True}])
        lua.execute('assert(package_family=="f200" and require("platform.target").distribution_version=="5.0.20012")')

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

    def test_private_head_ignores_map_multiplier_without_exempting_ordinary_work(self):
        for target in ("f200", "f210"):
            for multiplier, public_exempt in ((1, False), (2, False), (4, False), (.5, True), (4, True)):
                with self.subTest(target=target, multiplier=multiplier, public_exempt=public_exempt):
                    lua=self.world(target)
                    lua.globals().map_price=multiplier
                    lua.globals().public_exempt=public_exempt
                    lua.execute(r'''
                      -- Runtime prototype counts already include the map multiplier.
                      -- These are projected engine facts, not native qualification.
                      game.difficulty_settings={technology_price_multiplier=map_price}
                      for _,id in ipairs{CANONICAL,ORDINARY,ID}do
                        prototypes.technology[id].ignore_tech_cost_multiplier=public_exempt
                      end
                      local head=prototypes.technology[HEAD]
                      head.research_unit_count=head.ignore_tech_cost_multiplier and 1 or map_price
                      seed_owner();local before=all_frames();writes=0
                      local plan=history.plan_default_owner_transfer(owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011"),nil,false)
                      assert(plan and writes==0 and same(before,all_frames()))
                      assert(head.ignore_tech_cost_multiplier and head.research_unit_count==1)
                      assert(prototypes.technology[CANONICAL].ignore_tech_cost_multiplier==public_exempt)
                      assert(prototypes.technology[ORDINARY].ignore_tech_cost_multiplier==public_exempt)
                    ''')

    def test_initial_investment_unknown_producer_and_invalid_prepared_history_refuse_before_writes(self):
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
          seed_owner();history.prepare(nil)
          storage.mir_worker_storage_route.contract=storage.mir_worker_storage_route.contract..":changed"
          local b=all_frames();writes=0
          assert(not pcall(history.plan_default_owner_transfer,owner_event("5.0.21011"),nil,false)and writes==0 and same(b,all_frames()))
        ''')

    def test_all_force_contract_custody_pristine_and_event_opponents_before_writes(self):
        opponents=['creators[CANONICAL]="foreign"','creators[ORDINARY]="foreign"','creators[HEAD]="foreign"',
          'prototypes.technology[CANONICAL].max_level=4','prototypes.technology[ORDINARY].level=5',
          'prototypes.technology[ORDINARY].research_unit_energy=3600','prototypes.technology[ORDINARY].research_unit_count_formula="200*2^(L-4)"',
          'prototypes.technology[ORDINARY].effects[1].modifier=2','prototypes.technology[ORDINARY].research_unit_ingredients[1].amount=2',
          'prototypes.technology[ORDINARY].prerequisites[HEAD]={name=HEAD}','prototypes.technology[HEAD].effects[1].modifier=0',
          'prototypes.technology[HEAD].research_unit_count=2','prototypes.technology[HEAD].research_unit_energy=1',
          'prototypes.technology[HEAD].research_unit_ingredients[1].name="wrong"','prototypes.technology[HEAD].ignore_tech_cost_multiplier=false',
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

    def test_default_contract_refusals_identify_failed_predicate_without_writes(self):
        opponents = (
            ('creators[CANONICAL]="foreign"', ('predicate=public-route', 'route=external', 'owner_creator=unobserved')),
            ('creators[ORDINARY]="foreign"', ('predicate=owner-creator', 'owner_creator=foreign')),
            ('local previous_history=prototypes.get_history;prototypes.get_history=function(kind,name) '
             'if name==ORDINARY then return {} end;return previous_history(kind,name) end',
             ('predicate=owner-creator', 'owner_creator=absent')),
            ('prototypes.technology[ORDINARY].research_unit_energy=3600',
             ('predicate=work-contract', 'comparison=unequal-fingerprint', 'research_unit_energy.canonical=1800',
              'research_unit_energy.owner=3600')),
            ('prototypes.technology[CANONICAL].research_unit_ingredients[1].amount="invalid"',
             ('predicate=work-contract', 'comparison=canonical-fingerprint', 'science[1].amount.canonical=invalid')),
            ('prototypes.technology[CANONICAL].research_unit_ingredients[1]=setmetatable({amount=1},'
             '{__index=function() error("science-observation-failed") end})',
             ('predicate=work-contract', 'comparison=canonical-fingerprint', 'science[1].name.canonical=unavailable:',
              'science-observation-failed')),
            ('prototypes.technology[ORDINARY].research_unit_ingredients[1].amount=2',
             ('predicate=work-contract', 'comparison=unequal-fingerprint', 'science[1].amount.owner=2')),
            ('prototypes.technology[ORDINARY].research_unit_ingredients[1].amount="invalid"',
             ('predicate=work-contract', 'comparison=owner-fingerprint', 'science[1].amount.owner=invalid')),
            ('prototypes.technology[ORDINARY].hidden=true',
             ('predicate=owner-flags', 'hidden.owner=true')),
            ('prototypes.technology[ORDINARY].hidden=nil;setmetatable(prototypes.technology[ORDINARY],'
             '{__index=function(_,key) if key=="hidden" then error("owner-hidden-unavailable") end end})',
             ('predicate=owner-flags', 'comparison=unavailable-flags', 'hidden.owner=unavailable:',
              'owner-hidden-unavailable')),
        )
        for target in ("f200", "f210"):
            for mutation, expected in opponents:
                with self.subTest(target=target, mutation=mutation):
                    lua = self.world(target)
                    lua.execute('seed_owner();' + mutation + r'''
                      local before=all_frames(); writes=0
                      contract_ok,contract_error=pcall(history.plan_default_owner_transfer,
                        owner_event(package_family=="f200" and "5.0.20011" or "5.0.21011"),nil,false)
                      assert(not contract_ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                    ''')
                    message = str(lua.globals().contract_error)
                    for token in expected:
                        self.assertIn(token, message)

    def test_stale_plan_detects_last_force_work_bonus_and_debit_changes(self):
        for change in ('detached.technologies[CANONICAL].saved_progress=.29','foreign_bonus[4]=21','detached.technologies[HEAD].researched=true'):
            lua=self.world();lua.execute(r'''
              seed_owner();local plan=history.plan_default_owner_transfer(owner_event("5.0.21011"),nil,false)
            '''+change+r''';local before=all_frames();writes=0
              assert(not pcall(history.apply_default_owner_transfer,plan)and writes==0 and same(before,all_frames()))
            ''')

    def test_default_transfer_preserves_newer_parked_work_on_a_later_force(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner()
                  local updated, owner = nil, storage[OWNER_KEY]
                  after_first_level_write(player.technologies[ORDINARY], function()
                    detached.technologies[CANONICAL].saved_progress = .71
                    updated = frame(detached)
                  end)
                  local ok, message = pcall(transfer)
                  assert(not ok and tostring(message):find("work changed during another force's transfer", 1, true))
                  assert(updated and updated.source.saved == .71 and same(frame(detached), updated))
                  assert(storage[OWNER_KEY] == owner and not history.default_owner_mutating{force=player})
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
              require("runtime.configuration").streams["worker-robots-storage"].base_cost=201
              local before=all_frames();local contract=storage[OWNER_KEY].contract;writes=0
              local plan=history.default_owner_preflight({mod_startup_settings_changed=true,mod_changes={}},nil,true)
              assert(history.default_owner_apply(plan)and writes==0 and same(before,all_frames()))
              assert(storage[OWNER_KEY].contract~=contract and player.worker_robots_storage_bonus==20+4*scalar)
              assert(player.technologies[CANONICAL].level==5 and player.technologies[HEAD].level==5 and not player.technologies[HEAD].researched)
            ''')

    def test_exact_411_raw_runtime_characterizes_false_setting_drift(self):
        source=(Path(__file__).resolve().parents[1]/"source/runtime/worker_robot_storage.lua").read_text()
        guard='''        recover_error("unrelated startup setting change cannot authorize changing paid worker research")'''
        self.assertEqual(source.count(guard),1)
        revision="411b74c364bee277b7f8bedc80679aa602935682"
        path="source/runtime/worker_robot_storage.lua"
        blob=subprocess.run(["git","rev-parse",f"{revision}:{path}"],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
        self.assertEqual(blob,"d564a866651adaa938f6df059d89392241b0bd9d")
        legacy=subprocess.run(["git","show",f"{revision}:{path}"],cwd=ROOT,check=True,capture_output=True,text=True).stdout
        self.assertNotIn("automatic_owner_contract_has_invested_work",legacy)
        for target in ("f200","f210"):
            for drift in ("science","prerequisite","time"):
                with self.subTest(target=target,drift=drift):
                    lua=self.world(target);lua.globals().drift=drift;lua.globals().legacy=legacy
                    lua.execute(r'''
                      set_reward(0);init_default()
                      local later=make_force("later",5);install_force(later);game.forces.later=later
                      history.on_force_created{force=later};assert(history.default_owner_on_force_created{force=later})
                      finish_frame(later,"advanced",{ORDINARY},false)
                      assert(history.default_owner_on_research_finished(finish_event(later)))
                      assert(later.technologies[ORDINARY].level==5 and later.worker_robots_storage_bonus==20)
                      if drift=="science"then
                        for _,id in ipairs{CANONICAL,ORDINARY}do
                          table.insert(prototypes.technology[id].research_unit_ingredients,{name="se-material-science-pack-1",amount=1})
                        end
                      elseif drift=="prerequisite"then
                        for _,id in ipairs{CANONICAL,ORDINARY}do
                          prototypes.technology[id].prerequisites["space-science-pack"]={name="space-science-pack"}
                        end
                      else
                        for _,id in ipairs{CANONICAL,ORDINARY}do prototypes.technology[id].research_unit_energy=3600 end
                      end
                      local event=owner_event(package_family=="f200"and"5.0.20017"or"5.0.21017");event.mod_startup_settings_changed=true
                      local before,state=all_frames(),copy(storage[OWNER_KEY]);writes=0;queue_writes={};progress_writes={}
                      local ok,message=pcall(history.default_owner_preflight,event,nil,true)
                      assert(not ok and tostring(message):find("unrelated startup setting change cannot authorize",1,true))
                      assert(writes==0 and same(before,all_frames())and same(state,storage[OWNER_KEY]))
                      -- The exact raw 411 runtime accepts an unrelated-setting
                      -- drift and replaces recorded provenance without native
                      -- writes in this same established world.
                      storage[OWNER_KEY].settings=nil;state.settings=nil
                      history=assert(load(legacy))()
                      local plan=history.default_owner_preflight(event,nil,true)
                      assert(plan.already_owned and history.default_owner_apply(plan))
                      assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY].contract~=state.contract)
                    ''')

    def test_automatic_owner_contract_drift_refuses_each_investment_signal(self):
        for target in ("f200","f210"):
            for signal in ("earned","completed","partial","current","queued"):
                with self.subTest(target=target,signal=signal):
                    lua=self.world(target);lua.globals().signal=signal
                    lua.execute(r'''
                      set_reward(0);init_default()
                      local later=make_force("later",5);install_force(later);game.forces.later=later
                      history.on_force_created{force=later};assert(history.default_owner_on_force_created{force=later})
                      if signal=="earned"then
                        finish_frame(later,"advanced",{},false)
                        assert(history.default_owner_on_research_finished(finish_event(later)))
                        assert(later.technologies[ORDINARY].level==5 and later.worker_robots_storage_bonus==20)
                      elseif signal=="completed"then
                        later.technologies[ORDINARY].researched=true
                        assert(later.technologies[ORDINARY].level==4 and later.technologies[ORDINARY].researched)
                      elseif signal=="partial"then
                        later.technologies[ORDINARY].saved_progress=.42
                      elseif signal=="current"then
                        later.research_queue={ORDINARY};later.research_progress=.42
                      else
                        later.research_queue={OTHER,ORDINARY};later.research_progress=.42
                      end
                      for _,id in ipairs{CANONICAL,ORDINARY}do prototypes.technology[id].research_unit_energy=3600 end
                      local event=owner_event(package_family=="f200"and"5.0.20017"or"5.0.21017");event.mod_startup_settings_changed=true
                      local before,state=all_frames(),copy(storage[OWNER_KEY]);writes=0;queue_writes={};progress_writes={}
                      local ok,message=pcall(history.default_owner_preflight,event,nil,true)
                      assert(not ok and tostring(message):find("unrelated startup setting change cannot authorize",1,true))
                      assert(writes==0 and same(before,all_frames())and same(state,storage[OWNER_KEY]))
                    ''')

    def test_automatic_owner_contract_investment_disjuncts_are_independent(self):
        source=(Path(__file__).resolve().parents[1]/"source/runtime/worker_robot_storage.lua").read_text()
        marker="\nlocal function automatic_owner_contract_has_invested_work(owned)"
        self.assertEqual(source.count(marker),1)
        exposed=source.replace(marker,"\nM._test_default_owner_frame_has_invested_work=default_owner_frame_has_invested_work"+marker)
        disjuncts={
            "earned":("  return frame.next_level > 4\n","  return false\n"),
            "partial":("    or frame.saved_progress > 0\n","    or false\n"),
            "current":("    or frame.current == id\n","    or false\n"),
            "queued":("    or frame.occurrences > 0\n","    or false\n"),
        }
        for target in ("f200","f210"):
            for signal,(disjunct,replacement) in disjuncts.items():
                with self.subTest(target=target,signal=signal):
                    self.assertEqual(exposed.count(disjunct),1)
                    lua=self.world(target);lua.globals().signal=signal;lua.globals().probe_source=exposed
                    lua.globals().broken_source=exposed.replace(disjunct,replacement,1)
                    lua.execute(r'''
                      local frame={next_level=4,saved_progress=0,current="other",occurrences=0}
                      if signal=="earned"then frame.next_level=5
                      elseif signal=="partial"then frame.saved_progress=.42
                      elseif signal=="current"then frame.current=ORDINARY
                      else frame.occurrences=1 end
                      local current=assert(load(probe_source))()
                      local deleted=assert(load(broken_source))()
                      assert(current._test_default_owner_frame_has_invested_work(frame,ORDINARY))
                      assert(not deleted._test_default_owner_frame_has_invested_work(frame,ORDINARY))
                    ''')

    def test_automatic_owner_contract_drift_updates_only_uninvested_existing_owners(self):
        for target in ("f200","f210"):
            for drift in ("science","prerequisite","time"):
                with self.subTest(target=target,drift=drift):
                    lua=self.world(target);lua.globals().drift=drift
                    lua.execute(r'''
                      init_default()
                      if drift=="science"then
                        for _,id in ipairs{CANONICAL,ORDINARY}do
                          table.insert(prototypes.technology[id].research_unit_ingredients,{name="se-material-science-pack-1",amount=1})
                        end
                      elseif drift=="prerequisite"then
                        for _,id in ipairs{CANONICAL,ORDINARY}do
                          prototypes.technology[id].prerequisites["space-science-pack"]={name="space-science-pack"}
                        end
                      else
                        for _,id in ipairs{CANONICAL,ORDINARY}do prototypes.technology[id].research_unit_energy=3600 end
                      end
                      local event=owner_event(package_family=="f200"and"5.0.20017"or"5.0.21017")
                      local before,contract=all_frames(),storage[OWNER_KEY].contract;writes=0;queue_writes={};progress_writes={}
                      local plan=history.default_owner_preflight(event,nil,true)
                      assert(plan.already_owned and history.default_owner_apply(plan))
                      assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY].contract~=contract)
                    ''')

    def test_published517_bridge_matches_the_literal_retained_native_contract(self):
        lua = self.world("f200")
        lua.globals().native_contract = NATIVE_517_SE_CONTRACT
        lua.execute(r'''
          published517_source_contract();init_default()
          assert(storage[OWNER_KEY].contract==native_contract)
          finish_frame(player,"advanced",{ORDINARY,OTHER},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
          local plan=history.default_owner_preflight(published517_se_bridge_event(),nil,true)
          assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
          assert(history.default_owner_apply(plan))
          assert(storage[OWNER_KEY].legacy.contract==native_contract
            and storage[OWNER_KEY].forces[player.index].phase=="legacy"
            and player.current_research.name==LEGACY517 and player.research_progress==.42
            and player.technologies[LEGACY517].level==5
            and player.technologies[LEGACY517].saved_progress==before[player.index].owner.saved)
        ''')

    def test_published517_preserves_default_and_other_caps_and_explicit_uncapping(self):
        for old_cap, new_cap, startup_changed in (
            (0, 0, False), (10, 10, False), (12, 12, False), (10, 0, True), (10, 4, True)
        ):
            with self.subTest(old_cap=old_cap, new_cap=new_cap, startup_changed=startup_changed):
                lua = self.published517_world(old_cap)
                lua.globals().old_cap, lua.globals().new_cap = old_cap, new_cap
                lua.globals().startup_changed = startup_changed
                lua.globals().native_contract = NATIVE_517_SE_CONTRACT
                lua.execute(r'''
                  assert(storage[OWNER_KEY].contract==native_contract and storage[OWNER_KEY].settings==nil)
                  finish_frame(player,"advanced",{ORDINARY,ORDINARY,OTHER},false)
                  assert(history.default_owner_on_research_finished(finish_event(player)))
                  assert(storage[OWNER_KEY].settings==nil)
                  player.research_queue={ORDINARY,ORDINARY,OTHER};player.research_progress=.42
                  require("runtime.configuration").streams["worker-robots-storage"].max_level=new_cap
                  candidate_reader();history.configure(new_cap,true);current_se_contract()
                  local event=published517_se_bridge_event();event.mod_startup_settings_changed=startup_changed
                  local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
                  assert(history.default_owner_apply(plan))
                  local record=storage[OWNER_KEY]
                  assert(record.schema==4 and record.settings.max_level==new_cap
                    and record.legacy.contract==native_contract)
                  assert(record.forces[player.index].phase=="legacy"
                    and player.worker_robots_storage_bonus==before[player.index].bonus
                    and player.technologies[LEGACY517].level==before[player.index].owner.level
                    and player.technologies[LEGACY517].saved_progress==before[player.index].owner.saved
                    and player.research_progress==.42 and player.research_queue[1].name==LEGACY517
                    and player.research_queue[2].name==LEGACY517 and player.research_queue[3].name==OTHER)
                  for _,f in ipairs{uninvested,suspended,detached}do assert(same(frame(f),before[f.index]))end
                  local closed,saved=all_frames(),copy(record);writes=0
                  history.default_owner_on_load()
                  assert(writes==0 and same(closed,all_frames()) and same(saved,storage[OWNER_KEY]))
                  local steady={mod_startup_settings_changed=false,mod_changes={}}
                  history.default_owner_apply(history.default_owner_preflight(steady,nil,true))
                  assert(writes==0 and same(closed,all_frames()) and same(saved,storage[OWNER_KEY]))
                ''')

    def test_published517_cap_admission_requires_consistent_configuration_and_selected_policy(self):
        for configured, selected in ((0, 10), (10, 0)):
            with self.subTest(configured=configured, selected=selected):
                lua = self.published517_world(10)
                lua.globals().configured, lua.globals().selected = configured, selected
                lua.execute(r'''
                  finish_frame(player,"advanced",{ORDINARY,OTHER},false)
                  assert(history.default_owner_on_research_finished(finish_event(player)))
                  player.research_queue={ORDINARY,OTHER};player.research_progress=.42
                  require("runtime.configuration").streams["worker-robots-storage"].max_level=configured
                  candidate_reader();history.configure(selected,true);current_se_contract()
                  local event=published517_se_bridge_event();event.mod_startup_settings_changed=true
                  local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
                  assert(not pcall(history.default_owner_preflight,event,nil,true))
                  assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
                ''')

    def test_published517_cap_fix_keeps_the_other_paid_terms_exact(self):
        for field, changed in (("enabled", False), ("base_cost", 201), ("linear_increment", 1),
                               ("growth_factor", 2), ("research_time", 61), ("effect_percent", 2)):
            with self.subTest(field=field, changed=changed):
                lua = self.published517_world(10)
                lua.globals().field, lua.globals().changed = field, changed
                lua.execute(r'''
                  finish_frame(player,"advanced",{ORDINARY,OTHER},false)
                  assert(history.default_owner_on_research_finished(finish_event(player)))
                  player.research_queue={ORDINARY,OTHER};player.research_progress=.42
                  local config=require("runtime.configuration").streams["worker-robots-storage"]
                  config[field]=changed
                  candidate_reader();history.configure(10,config.enabled);current_se_contract()
                  local event=published517_se_bridge_event();event.mod_startup_settings_changed=true
                  local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
                  assert(not pcall(history.default_owner_preflight,event,nil,true))
                  assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
                ''')

    def test_published517_bridge_rejects_an_extra_holder_prerequisite_before_writes(self):
        lua = self.world("f200")
        lua.globals().native_contract = NATIVE_517_SE_CONTRACT
        lua.execute(r'''
          published517_source_contract();init_default()
          assert(storage[OWNER_KEY].contract==native_contract)
          finish_frame(player,"advanced",{ORDINARY,OTHER},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          prototypes.technology[LEGACY517].prerequisites["worker-robots-storage-2"]={name="worker-robots-storage-2"}
          local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
          local ok,message=pcall(history.default_owner_preflight,published517_se_bridge_event(),nil,true)
          assert(not ok and tostring(message):find("holder or current contract differs",1,true),tostring(message))
          assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
        ''')

    def test_published517_paid_bridge_settles_exact_engine_reenabled_owned_shell(self):
        lua = self.world("f200")
        lua.execute(r'''
          published517_source_contract(); init_default()
          finish_frame(player, "advanced", {ORDINARY, ORDINARY, OTHER}, false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          local old = player.technologies[ORDINARY]
          old.level = 9
          player.research_queue = {ORDINARY, ORDINARY, OTHER}
          player.research_progress = .039024390243902438
          local bonus = player.worker_robots_storage_bonus
          current_se_contract()
          local canonical = player.technologies[CANONICAL]
          local gate = player.technologies["mir-worker-storage-head-4"]
          assert(canonical.level == 5 and gate.level == 5)
          canonical.enabled, canonical.visible_when_disabled, gate.enabled = true, true, true
          assert(storage[OWNER_KEY].forces[player.index].retired_flags.disabled_by_mir)
          local before, ownership = all_frames(), copy(storage[OWNER_KEY]); writes = 0
          local plan = history.default_owner_preflight(published517_se_bridge_event(), nil, true)
          assert(writes == 0 and same(before, all_frames()) and same(ownership, storage[OWNER_KEY]))
          assert(history.default_owner_apply(plan))
          assert(canonical.level == 5 and not canonical.enabled and canonical.visible_when_disabled)
          assert(gate.level == 5 and not gate.enabled and player.worker_robots_storage_bonus == bonus)
          assert(player.technologies[LEGACY517].level == 9 and player.current_research.name == LEGACY517)
          assert(player.research_progress == .039024390243902438)
          assert(player.research_queue[1].name == LEGACY517 and player.research_queue[2].name == LEGACY517
            and player.research_queue[3].name == OTHER)
        ''')

    def test_published517_reenabled_shell_preserves_ambiguous_states_without_writes(self):
        for mutation in ("debit stayed disabled", "parked canonical work", "no MIR disablement right"):
            with self.subTest(mutation=mutation):
                lua = self.world("f200")
                lua.globals().modify_shell = mutation
                lua.execute(r'''
                  published517_source_contract(); init_default()
                  finish_frame(player, "advanced", {ORDINARY, ORDINARY, OTHER}, false)
                  assert(history.default_owner_on_research_finished(finish_event(player)))
                  player.research_queue = {ORDINARY, ORDINARY, OTHER}; player.research_progress = .42
                  current_se_contract()
                  canonical = player.technologies[CANONICAL]
                  gate = player.technologies["mir-worker-storage-head-4"]
                  flags = storage[OWNER_KEY].forces[player.index].retired_flags
                  canonical.enabled, canonical.visible_when_disabled, gate.enabled = true, true, true
                  if modify_shell == "debit stayed disabled" then gate.enabled = false
                  elseif modify_shell == "parked canonical work" then canonical.saved_progress = .27
                  else flags.enabled, flags.disabled_by_mir = false, false end
                  local before, ownership = all_frames(), copy(storage[OWNER_KEY]); writes = 0
                  local ok, reason = pcall(history.default_owner_preflight, published517_se_bridge_event(), nil, true)
                  assert(not ok and tostring(reason):find("published517 SE paid-worker frame differs", 1, true))
                  assert(writes == 0 and same(before, all_frames()) and same(ownership, storage[OWNER_KEY]))
                ''')

    def test_published517_se_paid_contract_moves_only_known_old_work_to_the_old_holder(self):
        """A published F200 SE Base-five partial must not become current SE-seven work."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY,OTHER},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          suspended.technologies[ORDINARY].saved_progress=.27
          suspended.research_queue={OTHER,ORDINARY};suspended.research_progress=.19
          detached.technologies[ORDINARY].saved_progress=.31
          local before=all_frames();local owner=copy(storage[OWNER_KEY]);writes=0;queue_writes={};progress_writes={}
          current_se_contract()
          local plan=history.default_owner_preflight(published517_se_bridge_event(),nil,true)
          assert(plan.kind=="published517-se-paid-bridge")
          assert(writes==0 and same(before,all_frames())and same(owner,storage[OWNER_KEY]))
          assert(history.default_owner_apply(plan))
          local record=storage[OWNER_KEY]
          assert(record.schema==4 and record.kind=="full-default" and record.legacy.kind=="published517-se-paid")
          for _,force in pairs(game.forces)do
            local prior=before[force.index];local old=force.technologies[LEGACY517]
            local current=force.technologies[ORDINARY]
            if record.forces[force.index].phase=="legacy"then
              assert(old.level==prior.owner.level and old.saved_progress==prior.owner.saved)
              assert(old.enabled==prior.owner.enabled and old.visible_when_disabled==prior.owner.visible)
              assert(current.level==4 and current.saved_progress==0 and not current.enabled)
            else
              assert(old.level==4 and old.saved_progress==0 and not old.enabled)
              assert(current.level==prior.owner.level and current.saved_progress==prior.owner.saved)
            end
            assert(force.worker_robots_storage_bonus==prior.bonus)
          end
          assert(player.current_research.name==LEGACY517 and player.research_queue[1].name==LEGACY517
            and player.research_queue[2].name==OTHER and player.research_progress==.42)
          assert(suspended.research_queue[1].name==OTHER and suspended.research_queue[2].name==LEGACY517
            and suspended.research_progress==.19)
        ''')

    def test_published517_se_paid_completion_settles_to_current_contract_without_changing_bonus(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local before_bonus=player.worker_robots_storage_bonus
          player.technologies[LEGACY517].level=6
          player.research_queue={OTHER};player.research_progress=0
          player.technologies[LEGACY517].saved_progress=0
          local changed=history.default_owner_on_research_finished{
            research=player.technologies[LEGACY517],by_script=false,tick=101}
          assert(changed)
          local record=storage[OWNER_KEY]
          assert(record.schema==4 and record.forces[player.index].phase=="owned")
          assert(player.technologies[ORDINARY].level==6 and player.technologies[ORDINARY].saved_progress==0)
          assert(player.technologies[ORDINARY].enabled and player.technologies[LEGACY517].level==4
            and not player.technologies[LEGACY517].enabled)
          assert(player.technologies[CANONICAL].level==5 and player.technologies[HEAD].level==5)
          assert(player.worker_robots_storage_bonus==before_bonus+1 and player.current_research.name==OTHER)
        ''')

    def test_published517_advanced_completion_waits_for_the_unstarted_queue_tail(self):
        lua = self.world("f200")
        lua.execute(r'''
          published517_source_contract(); init_default()
          finish_frame(player, "advanced", {ORDINARY}, false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.research_queue={ORDINARY,ORDINARY,OTHER}; player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local debit_meta=getmetatable(player.technologies[HEAD])
          local debit_read=debit_meta.__index
          debit_meta.__index=function(technology,key)
            local value=debit_read(technology,key)
            assert(value~=nil,"LuaTechnology doesn't contain key "..key)
            return value
          end
          local legacy=player.technologies[LEGACY517]
          legacy.level=6; player.research_queue={LEGACY517,OTHER}; player.research_progress=0
          gaps[player.index]=true
          local before=all_frames(); writes=0
          local changed,settled=history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101}
          assert(changed and not settled and writes==0 and same(before,all_frames()))
          assert(history.default_owner_completion_pending_tick()==102)
          gaps[player.index]=false
          changed,settled=history.default_owner_on_completion_tick{tick=102}
          assert(changed and #settled==0 and writes==0 and player.current_research.name==LEGACY517)
          assert(storage[OWNER_KEY].forces[player.index].phase=="legacy")

          legacy.level=7; player.research_queue={OTHER}; player.research_progress=0
          player.technologies[OTHER].saved_progress=.19
          gaps[player.index]=true
          local bonus=player.worker_robots_storage_bonus
          before=all_frames(); writes=0; queue_writes={}; progress_writes={}
          changed,settled=history.default_owner_on_research_finished{research=legacy,by_script=false,tick=105}
          assert(changed and not settled and history.default_owner_completion_pending_tick()==106)
          assert(writes==0 and same(before,all_frames()) and player.current_research==nil)
          gaps[player.index]=false
          changed,settled=history.default_owner_on_completion_tick{tick=106}
          assert(changed and #settled==1 and settled[1]==player)
          assert(storage[OWNER_KEY].forces[player.index].phase=="owned")
          assert(player.technologies[ORDINARY].level==7 and legacy.level==4 and not legacy.enabled)
          assert(player.current_research.name==OTHER and player.technologies[OTHER].saved_progress==.19)
          assert(player.worker_robots_storage_bonus==bonus and queue_writes[1]==nil and progress_writes[1]==nil)
        ''')

    def test_published517_engine_owned_completion_defers_then_settles_without_repricing(self):
        """The progress-one callback is Factorio-owned, not a settled paid-work frame."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          local callback=all_frames();local bonus=player.worker_robots_storage_bonus;writes=0
          -- The old settled-frame reader rejected this exact callback shape.
          local changed,settled=history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101}
          assert(changed and not settled)
          assert(storage[OWNER_KEY].forces[player.index].phase=="legacy-completion-pending")
          assert(storage[OWNER_KEY].forces[player.index].completion_tick==101)
          assert(history.default_owner_completion_pending_tick()==102 and writes==0 and same(callback,all_frames()))
          -- Mimic the engine's later released representation; MIR must not
          -- synchronously reset an engine-owned completed row above.
          player.research_progress=0;player.research_queue={OTHER}
          legacy.researched=false;legacy.level=6;legacy.saved_progress=0;writes=0
          local changed,settled=history.default_owner_on_completion_tick{tick=102}
          assert(changed and #settled==1 and settled[1]==player)
          assert(storage[OWNER_KEY].forces[player.index].phase=="owned")
          assert(history.default_owner_completion_pending_tick()==nil and writes>0)
          assert(player.technologies[ORDINARY].level==6 and player.technologies[ORDINARY].saved_progress==0)
          assert(legacy.level==4 and not legacy.enabled and player.current_research.name==OTHER)
          assert(player.worker_robots_storage_bonus==bonus)
        ''')

    def test_published517_nil_current_completion_rehydrates_once_across_load(self):
        """A queue remainder with no current research also gets exactly one later observation."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={OTHER};player.research_progress=0;legacy.researched=true;gaps[player.index]=true
          writes=0
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=201})
          local pending=storage[OWNER_KEY]
          assert(pending.forces[player.index].phase=="legacy-completion-pending"
            and history.default_owner_completion_pending_tick()==202 and writes==0)
          local native_game,native_prototypes=game,prototypes
          game=nil;prototypes=nil;history.default_owner_on_load()
          assert(storage[OWNER_KEY]==pending and history.default_owner_completion_pending_tick()==202 and writes==0)
          game,prototypes=native_game,native_prototypes
          package.loaded["runtime.worker_robot_storage"]=nil;history=require("runtime.worker_robot_storage")
          history.default_owner_on_load();assert(history.default_owner_completion_pending_tick()==202 and writes==0)
          gaps[player.index]=false;legacy.researched=false;legacy.level=6;legacy.saved_progress=0
          player.research_queue={OTHER};player.research_progress=0;writes=0
          assert(history.default_owner_on_completion_tick{tick=202})
          assert(storage[OWNER_KEY].forces[player.index].phase=="owned" and writes>0)
          assert(player.technologies[ORDINARY].level==6 and player.current_research.name==OTHER)
        ''')

    def test_published517_completion_preserves_foreign_holder_enablement_and_visibility(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=251})
          local rights=copy(storage[OWNER_KEY].forces[player.index].retired_flags)
          player.research_progress=0;player.research_queue={OTHER}
          legacy.researched=false;legacy.level=6;legacy.saved_progress=0
          -- An external data/runtime owner changed the retiring holder after
          -- the callback. The successor must retain that visible disablement,
          -- not silently enable a new current-contract progression.
          legacy.enabled=false;legacy.visible_when_disabled=true;writes=0
          assert(history.default_owner_on_completion_tick{tick=252})
          local current=player.technologies[ORDINARY]
          assert(storage[OWNER_KEY].forces[player.index].phase=="owned")
          assert(current.level==6 and not current.enabled and current.visible_when_disabled)
          assert(legacy.level==4 and not legacy.enabled and not legacy.visible_when_disabled)
          assert(same(storage[OWNER_KEY].forces[player.index].retired_flags,rights))
        ''')

    def test_published517_completion_keeps_the_current_cap_when_old_work_reaches_its_boundary(self):
        for holder_enabled in (False, True):
            lua=self.world("f200")
            lua.globals().holder_enabled = holder_enabled
            lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          -- The original published contract permits the final paid level at
          -- its cap. Its completion must retain the earned bonus but leave
          -- future seven-pack work disabled at the current cap.
          player.technologies[ORDINARY].level=10;player.technologies[ORDINARY].saved_progress=0
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          assert(legacy.level==10 and legacy.enabled)
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=271})
          player.research_progress=0;player.research_queue={OTHER}
          legacy.researched=false;legacy.level=11;legacy.saved_progress=0
          legacy.enabled=holder_enabled;writes=0
          local restore_enabled
          assert(history.default_owner_on_completion_tick({tick=272},function(force, enabled)
            assert(force==player)
            restore_enabled=enabled
          end))
          local current=player.technologies[ORDINARY]
          assert(current.level==11 and not current.enabled and legacy.level==4 and not legacy.enabled)
          assert(player.current_research.name==OTHER and storage[OWNER_KEY].forces[player.index].phase=="owned")
          assert(restore_enabled==holder_enabled,"settlement lost the holder's cap restoration baseline")
        ''')

    def test_published517_pending_completion_admits_ordinary_repeats_without_duplicate_authority(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=301})
          local pending=storage[OWNER_KEY];local rights=copy(pending.forces[player.index].retired_flags);writes=0
          -- A same-tick old-holder completion can follow before the one later
          -- observation. It is admitted as a no-op: it cannot create another
          -- authority or settle the historical contract twice.
          local changed,settled=history.default_owner_on_research_finished{research=legacy,by_script=false,tick=301}
          assert(not changed and not settled and writes==0 and storage[OWNER_KEY]==pending)
          local ok,message=pcall(history.default_owner_on_research_finished,{research=legacy,by_script=true,tick=301})
          assert(not ok and tostring(message):find("ordinary native research",1,true) and writes==0 and storage[OWNER_KEY]==pending)
          local before=all_frames()
          ok,message=pcall(history.default_owner_on_forces_merging,{source=player,destination=suspended})
          assert(not ok and tostring(message):find("unsettled historical work",1,true)
            and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==pending)
          ok,message=pcall(history.default_owner_on_force_reset,{force=player})
          assert(not ok and tostring(message):find("awaiting its bounded native observation",1,true)
            and writes==0 and storage[OWNER_KEY]==pending)
          -- A changed callback row is stale evidence, not permission to apply
          -- the saved plan.  It remains pending and performs no native writes.
          player.technologies[CANONICAL].enabled=true;writes=0
          ok,message=pcall(history.default_owner_on_completion_tick,{tick=302})
          assert(not ok and writes==0 and storage[OWNER_KEY]==pending)
          player.technologies[CANONICAL].enabled=false
          -- A second ordinary level completes before the marker tick. It
          -- remains old-cost debt and retains the original marker rather than
          -- becoming a second settlement plan.
          player.research_progress=0;player.research_queue={LEGACY517,LEGACY517,OTHER}
          legacy.researched=false;legacy.level=6;legacy.saved_progress=0
          player.research_progress=1;legacy.researched=true;writes=0
          changed,settled=history.default_owner_on_research_finished{research=legacy,by_script=false,tick=301}
          assert(not changed and not settled and writes==0 and storage[OWNER_KEY]==pending)
          player.research_progress=0;player.research_queue={LEGACY517,LEGACY517,OTHER}
          legacy.researched=false;legacy.level=7;legacy.saved_progress=0
          player.technologies[OTHER].saved_progress=.19;player.research_progress=.2;writes=0
          assert(history.default_owner_on_completion_tick{tick=302})
          local record=storage[OWNER_KEY].forces[player.index]
          assert(record.phase=="legacy" and record.completion_tick==nil and same(record.retired_flags,rights))
          assert(writes==0 and player.current_research.name==LEGACY517 and player.research_progress==.2)
          assert(player.research_queue[2].name==LEGACY517 and player.research_queue[3].name==OTHER)
          assert(player.technologies[OTHER].saved_progress==.19 and history.default_owner_completion_pending_tick()==nil)
        ''')

    def test_published517_pending_completion_preserves_unrelated_force_creation_and_reset(self):
        """A pending callback row is debt on its force, not a global lifecycle lock."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101})
          local pending_frame,pending_record=frame(player),copy(storage[OWNER_KEY].forces[player.index])
          local fresh=make_force("late",5);install_force(fresh);game.forces.late=fresh
          history.on_force_created{force=fresh};writes=0
          assert(history.default_owner_on_force_created{force=fresh})
          assert(writes==10 and storage[OWNER_KEY].forces[fresh.index].phase=="owned")
          assert(same(pending_frame,frame(player)) and same(pending_record,storage[OWNER_KEY].forces[player.index]))
          -- A different ordinary current-contract completion is similarly
          -- local: it may settle that force but cannot consume or invent a
          -- released frame for the pending old-contract player row.
          finish_frame(fresh,"advanced",{OTHER},false)
          assert(history.default_owner_on_research_finished(finish_event(fresh)))
          assert(fresh.technologies[ORDINARY].level==5 and same(pending_frame,frame(player))
            and same(pending_record,storage[OWNER_KEY].forces[player.index]))
          local function cleared_reset_frame(force)
            force.research_queue={OTHER};force.research_progress=0
            for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517,HEAD}do
              local tech=force.technologies[id]
              tech.level=4;tech.researched=false;tech.saved_progress=0
              local prototype=prototypes.technology[id]
              tech.enabled=type(prototype.enabled)=="boolean" and prototype.enabled or false
              tech.visible_when_disabled=type(prototype.visible_when_disabled)=="boolean"
                and prototype.visible_when_disabled or false
              assert(type(tech.level)=="number" and type(tech.researched)=="boolean"
                and type(tech.enabled)=="boolean" and type(tech.visible_when_disabled)=="boolean"
                and type(tech.saved_progress)=="number", "incomplete unrelated reset frame: "..id)
            end
            history.on_force_reset{force=force}
          end
          cleared_reset_frame(suspended);writes=0
          assert(history.default_owner_on_force_reset{force=suspended})
          assert(storage[OWNER_KEY].forces[suspended.index].phase=="owned" and writes>0)
          assert(same(pending_frame,frame(player)) and same(pending_record,storage[OWNER_KEY].forces[player.index]))
          local before,state=all_frames(),storage[OWNER_KEY];writes=0
          local ok,message=pcall(history.default_owner_on_force_reset,{force=player})
          assert(not ok and tostring(message):find("awaiting its bounded native observation",1,true)
            and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state)
        ''')

    def test_published517_pending_completion_is_local_to_an_unrelated_owned_merge(self):
        """A third-force marker survives an owned merge; either merge endpoint debt still refuses."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=151})
          local pending_frame,pending_record=frame(player),copy(storage[OWNER_KEY].forces[player.index])
          local function own_after_reset(force)
            force.research_queue={OTHER};force.research_progress=0
            for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517,HEAD}do
              local tech=force.technologies[id]
              tech.level=4;tech.researched=false;tech.saved_progress=0
              local prototype=prototypes.technology[id]
              tech.enabled=type(prototype.enabled)=="boolean" and prototype.enabled or false
              tech.visible_when_disabled=type(prototype.visible_when_disabled)=="boolean"
                and prototype.visible_when_disabled or false
              assert(type(tech.level)=="number" and type(tech.researched)=="boolean"
                and type(tech.enabled)=="boolean" and type(tech.visible_when_disabled)=="boolean"
                and type(tech.saved_progress)=="number", "incomplete unrelated reset frame: "..id)
            end
            history.on_force_reset{force=force};assert(history.default_owner_on_force_reset{force=force})
            assert(storage[OWNER_KEY].forces[force.index].phase=="owned")
          end
          own_after_reset(uninvested);own_after_reset(suspended)
          local before,state=all_frames(),storage[OWNER_KEY];writes=0
          local ok,message=pcall(history.default_owner_on_forces_merging,{source=uninvested,destination=player})
          assert(not ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state)
          ok,message=pcall(history.default_owner_on_forces_merging,{source=player,destination=uninvested})
          assert(not ok and tostring(message):find("source has unsettled historical work",1,true)
            and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state)
          assert(history.default_owner_on_forces_merging{source=suspended,destination=uninvested})
          assert(writes==0 and storage[OWNER_KEY]==state and same(pending_frame,frame(player))
            and same(pending_record,state.forces[player.index]))
          game.forces.suspended=nil
          local source_index=suspended.index
          assert(history.default_owner_on_forces_merged{source_index=source_index,destination=uninvested})
          assert(writes==0 and storage[OWNER_KEY].forces[source_index]==nil
            and same(pending_frame,frame(player)) and same(pending_record,storage[OWNER_KEY].forces[player.index]))
        ''')

    def test_published517_pending_completion_accepts_the_finite_maptick_domain(self):
        """MapTick is not a technology-level uint32 field; this remains host API-domain evidence."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          -- 2^53 cannot advance by one in the Lua number domain, even though
          -- it is a finite integral value. It cannot be a durable marker
          -- because its required later observation would be ambiguous.
          local before,ok
          for _,indistinct in ipairs{9007199254740992,9007199254740994}do
            -- Rounding may also advance by two, rather than stay equal.
            -- Either fails the required exact one-tick successor.
            before=all_frames();writes=0
            ok=pcall(history.default_owner_on_research_finished,
              {research=legacy,by_script=false,tick=indistinct})
            assert(not ok and writes==0 and same(before,all_frames())
              and storage[OWNER_KEY].forces[player.index].phase=="legacy")
          end
          local boundary=4294967295
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=boundary})
          local pending=storage[OWNER_KEY]
          assert(pending.forces[player.index].completion_tick==boundary
            and history.default_owner_completion_pending_tick()==boundary+1)
          before=all_frames();writes=0
          ok=pcall(history.default_owner_on_completion_tick,{tick=math.huge})
          assert(not ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==pending)
          ok=pcall(history.default_owner_on_research_finished,{research=legacy,by_script=false,tick=boundary+.5})
          assert(not ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==pending)
        ''')

    def test_published517_pending_resume_is_revalidated_after_another_force_settles(self):
        """A nested later completion must not clear a stale second force marker."""
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          for _,force in ipairs({player,suspended})do
            finish_frame(force,"advanced",{ORDINARY},false)
            assert(history.default_owner_on_research_finished(finish_event(force)))
            force.technologies[ORDINARY].saved_progress=.42
            force.research_queue={ORDINARY,OTHER};force.research_progress=.42
          end
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local first,second=player.technologies[LEGACY517],suspended.technologies[LEGACY517]
          for _,item in ipairs({{force=player,legacy=first},{force=suspended,legacy=second}})do
            item.force.research_queue={LEGACY517,OTHER};item.force.research_progress=1;item.legacy.researched=true
            assert(history.default_owner_on_research_finished{research=item.legacy,by_script=false,tick=401})
          end
          -- Player is ready to settle; suspended has real old queue work and
          -- is initially only ready to resume its legacy phase.
          player.research_progress=0;player.research_queue={OTHER}
          first.researched=false;first.level=6;first.saved_progress=0
          suspended.research_progress=0;suspended.research_queue={LEGACY517,OTHER}
          second.researched=false;second.level=6;second.saved_progress=0;suspended.research_progress=.2
          local mt=getmetatable(first);local write=mt.__newindex;local fired=false
          mt.__newindex=function(object,key,value)
            if key=="level" and value==4 and not fired then
              fired=true
              -- A genuine second ordinary completion arrives during the first
              -- force's native writer. It retains the marker but invalidates
              -- the pre-read resume frame for suspended.
              suspended.research_progress=1;second.researched=true
              local changed,settled=history.default_owner_on_research_finished{
                research=second,by_script=false,tick=402}
              assert(not changed and not settled)
            end
            return write(object,key,value)
          end
          local pending=storage[OWNER_KEY];writes=0
          local ok,message=pcall(history.default_owner_on_completion_tick,{tick=402})
          assert(not ok and fired)
          -- The first setter already happened; do not claim rollback. The
          -- durable owner record retains both markers rather than silently
          -- disposing suspended's newly completed historical work.
          assert(writes>0 and storage[OWNER_KEY]==pending)
          assert(pending.forces[player.index].phase=="legacy-completion-pending"
            and pending.forces[suspended.index].phase=="legacy-completion-pending")
          assert(player.technologies[ORDINARY].level==6 and second.researched and suspended.research_progress==1)
        ''')

    def test_published517_paid_bridge_preserves_newer_active_work_on_a_later_force(self):
        lua = self.world("f200")
        lua.execute(r'''
          published517_source_contract()
          init_default()
          for _, force in ipairs({player, detached}) do
            finish_frame(force, "advanced", {ORDINARY}, false)
            assert(history.default_owner_on_research_finished(finish_event(force)))
            force.technologies[ORDINARY].saved_progress = .42
            force.research_queue = {ORDINARY}
            force.research_progress = .42
          end
          current_se_contract()
          local plan = history.default_owner_preflight(published517_se_bridge_event(), nil, true)
          local updated, owner = nil, storage[OWNER_KEY]
          after_first_level_write(player.technologies[LEGACY517], function()
            detached.research_progress = .71
            updated = frame(detached)
          end)
          local ok, message = pcall(history.default_owner_apply, plan)
          assert(not ok and tostring(message):find("work changed during another force's transfer", 1, true))
          assert(updated and updated.current == ORDINARY and updated.progress == .71)
          assert(same(frame(detached), updated) and storage[OWNER_KEY] == owner)
        ''')

    def test_published517_exact_settings_admit_the_paid_bridge_when_an_unrelated_setting_changed(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          local event=published517_se_bridge_event();event.mod_startup_settings_changed=true
          local before=all_frames();writes=0;queue_writes={};progress_writes={}
          local plan=history.default_owner_preflight(event,nil,true)
          assert(plan.kind=="published517-se-paid-bridge" and writes==0 and same(before,all_frames()))
          assert(history.default_owner_apply(plan))
          assert(storage[OWNER_KEY].schema==4 and storage[OWNER_KEY].settings.max_level==10)
        ''')

    def test_published517_se_paid_bridge_reloads_and_reenters_without_rewriting_old_work(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local record,before=storage[OWNER_KEY],all_frames();writes=0
          local native_game,native_prototypes=game,prototypes
          game=nil;prototypes=nil;history.default_owner_on_load()
          game,prototypes=native_game,native_prototypes
          local event={mod_startup_settings_changed=false,mod_changes={}}
          local plan=history.default_owner_preflight(event,nil,true)
          assert(plan.already_owned and not history.default_owner_apply(plan))
          assert(storage[OWNER_KEY]==record and same(before,all_frames())and writes==0)
        ''')

    def test_unchanged_automatic_configuration_keeps_invested_zero_reward_work(self):
        for target in ("f200","f210"):
            with self.subTest(target=target):
                lua=self.world(target)
                lua.execute(r'''
                  set_reward(0);init_default()
                  local later=make_force("later",5);install_force(later);game.forces.later=later
                  history.on_force_created{force=later};assert(history.default_owner_on_force_created{force=later})
                  finish_frame(later,"advanced",{ORDINARY},false)
                  assert(history.default_owner_on_research_finished(finish_event(later)))
                  local event=owner_event(package_family=="f200"and"5.0.20017"or"5.0.21017")
                  local before,state=all_frames(),storage[OWNER_KEY];writes=0;queue_writes={};progress_writes={}
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(plan.already_owned and not history.default_owner_apply(plan))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==state)
                ''')


class WorkerDefaultNativeLifecycleTests(unittest.TestCase):
    def world(self,target="f210"):
        return build_default_native_owner_world(LuaRuntime, target=target, source_root=ROOT / "source")

    def retuned_legacy_world(self, *, price=False, time=False, before_retune=None):
        """Old five-pack work and future seven-pack terms are independent inputs."""
        lua = self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          for _,force in ipairs{player,suspended}do
            finish_frame(force,"advanced",{ORDINARY},false)
            assert(history.default_owner_on_research_finished(finish_event(force)))
            force.technologies[ORDINARY].saved_progress=.42
            force.research_queue={ORDINARY,ORDINARY,OTHER};force.research_progress=.42
          end
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          old_current_contract=storage[OWNER_KEY].contract
          old_legacy_contract=storage[OWNER_KEY].legacy.contract
        ''')
        if before_retune:
            lua.execute(before_retune)
        if price:
            lua.execute(r'''
              local config=require("runtime.configuration").streams["worker-robots-storage"]
              config.base_cost,config.growth_factor=900,2
              for _,id in ipairs{CANONICAL,ORDINARY,ID}do
                prototypes.technology[id].research_unit_count_formula="7200*2^(L-4)"
                for _,force in pairs(game.forces)do
                  local row=force.technologies[id];local mt=getmetatable(row);local read=mt.__index
                  mt.__index=function(object,key)
                    if key=="research_unit_count"then return math.floor(7200*2^(read(object,"level")-4))end
                    return read(object,key)
                  end
                end
              end
            ''')
        if time:
            lua.execute(r'''
              require("runtime.configuration").streams["worker-robots-storage"].research_time=120
              for _,id in ipairs{CANONICAL,ORDINARY,ID}do prototypes.technology[id].research_unit_energy=7200 end
            ''')
        return lua

    def test_legacy_work_survives_explicit_future_price_time_changes_and_later_handover(self):
        for price, time in ((True, False), (False, True), (True, True)):
            with self.subTest(price=price, time=time):
                lua = self.retuned_legacy_world(price=price, time=time)
                lua.globals().price_changed = price
                lua.execute(r'''
                  local before,prior=all_frames(),storage[OWNER_KEY];writes=0
                  local event={mod_startup_settings_changed=true,mod_changes={}}
                  assert(history.default_owner_apply(history.default_owner_preflight(event,nil,true)))
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]~=prior)
                  assert(storage[OWNER_KEY].contract~=old_current_contract
                    and storage[OWNER_KEY].legacy.contract==old_legacy_contract)
                  assert(prototypes.technology[LEGACY517].research_unit_energy==3600
                    and player.technologies[LEGACY517].research_unit_count==1012)
                  for cycle=1,2 do
                    local native_game,native_prototypes=game,prototypes
                    game,prototypes=nil,nil;history.default_owner_on_load()
                    game,prototypes=native_game,native_prototypes
                    local steady={mod_startup_settings_changed=false,mod_changes={}}
                    assert(not history.default_owner_apply(history.default_owner_preflight(steady,nil,true)))
                    assert(writes==0 and same(before,all_frames()))
                  end
                  local legacy=player.technologies[LEGACY517]
                  player.research_progress=1;legacy.researched=true
                  assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101})
                  player.research_progress=0;player.research_queue={LEGACY517,OTHER}
                  legacy.level=6;legacy.researched=false;legacy.saved_progress=0
                  assert(history.default_owner_on_completion_tick{tick=102})
                  assert(storage[OWNER_KEY].forces[player.index].phase=="legacy"
                    and player.current_research.name==LEGACY517
                    and legacy.research_unit_count==1518
                    and prototypes.technology[LEGACY517].research_unit_energy==3600)
                  player.research_progress=1;legacy.researched=true
                  assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=103})
                  player.research_progress=0;player.research_queue={OTHER}
                  legacy.level=7;legacy.researched=false;legacy.saved_progress=0
                  local bonus,other=player.worker_robots_storage_bonus,frame(suspended)
                  assert(history.default_owner_on_completion_tick{tick=104})
                  assert(player.worker_robots_storage_bonus==bonus and same(other,frame(suspended)))
                  assert(storage[OWNER_KEY].forces[player.index].phase=="owned"
                    and storage[OWNER_KEY].forces[suspended.index].phase=="legacy")
                  assert(player.technologies[ORDINARY].level==7 and legacy.level==4
                    and player.technologies[ORDINARY].research_unit_count==(price_changed and 57600 or 2278))
                  assert(player.current_research.name==OTHER and player.research_progress==0)
                ''')

    def test_legacy_retuning_still_requires_recorded_relevant_settings_and_configuration_authority(self):
        for change, message in (
            ('storage[OWNER_KEY].settings=nil', "no recorded relevant startup settings"),
            ('require("runtime.configuration").streams["worker-robots-storage"].research_time=60', "unrelated startup setting"),
            ('event.mod_startup_settings_changed=false', "without a configuration-change authority"),
        ):
            with self.subTest(change=change):
                lua = self.retuned_legacy_world(time=True)
                lua.execute('local event={mod_startup_settings_changed=true,mod_changes={}};' + change + r'''
                  local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
                  local ok,message=pcall(history.default_owner_preflight,event,nil,true)
                  assert(not ok and tostring(message):find(''' + repr(message) + r''',1,true),tostring(message))
                  assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
                ''')

    def test_legacy_retuning_refuses_effect_changes_and_other_force_current_investment_before_writes(self):
        for change in (
            'set_reward(2);require("runtime.configuration").streams["worker-robots-storage"].effect_percent=2',
            'finish_frame(uninvested,"advanced",{},false);assert(history.default_owner_on_research_finished(finish_event(uninvested)))',
            'uninvested.technologies[ORDINARY].saved_progress=.23',
            'uninvested.research_queue={ORDINARY,OTHER};uninvested.research_progress=.27',
            'storage[OWNER_KEY].legacy.contract="worker-storage-1:counterfeit"',
        ):
            with self.subTest(change=change):
                lua = self.retuned_legacy_world(time=True, before_retune=change)
                lua.execute(r'''
                  local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
                  local ok=pcall(history.default_owner_preflight,{mod_startup_settings_changed=true,mod_changes={}},nil,true)
                  assert(not ok and writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
                ''')

    def test_legacy_retuning_revalidates_another_force_old_work_before_application(self):
        lua = self.retuned_legacy_world(price=True, time=True)
        lua.execute(r'''
          local plan=history.default_owner_preflight({mod_startup_settings_changed=true,mod_changes={}},nil,true)
          suspended.research_progress=.31
          local before,prior=all_frames(),copy(storage[OWNER_KEY]);writes=0
          assert(not pcall(history.default_owner_apply,plan))
          assert(writes==0 and same(before,all_frames()) and same(prior,storage[OWNER_KEY]))
        ''')

    def test_unrelated_force_operations_preserve_another_forces_pending_completion(self):
        for pending in (False, True):
            for operation in ("create", "reset", "finish"):
                with self.subTest(pending=pending, operation=operation):
                    lua=self.world("f200")
                    lua.globals().completion_pending=pending
                    lua.globals().operation=operation
                    lua.execute(r'''
                      published517_source_contract();init_default()
                      finish_frame(player,"advanced",{ORDINARY},false)
                      assert(history.default_owner_on_research_finished(finish_event(player)))
                      player.technologies[ORDINARY].saved_progress=.42
                      player.research_queue={ORDINARY,OTHER};player.research_progress=.42
                      current_se_contract()
                      assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
                      if completion_pending then
                        local legacy=player.technologies[LEGACY517]
                        player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
                        assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101})
                      end
                      local before,marker=frame(player),copy(storage[OWNER_KEY].forces[player.index])
                      local event_force=detached
                      if operation=="create" then
                        event_force=make_force("late",5);install_force(event_force);game.forces.late=event_force
                        history.on_force_created{force=event_force}
                      elseif operation=="finish" then finish_frame(event_force,"advanced",{},false) end
                      writes=0
                      local changed
                      if operation=="create" then changed=history.default_owner_on_force_created{force=event_force}
                      elseif operation=="reset" then changed=history.default_owner_on_force_reset{force=event_force}
                      else changed=history.default_owner_on_research_finished(finish_event(event_force)) end
                      assert(changed and writes>0)
                      assert(same(before,frame(player)) and same(marker,storage[OWNER_KEY].forces[player.index]))
                      assert(storage[OWNER_KEY].forces[event_force.index].phase=="owned")
                      if operation=="finish" then assert(event_force.technologies[CANONICAL].level==5)
                      else assert(event_force.technologies[ORDINARY].level==4) end
                    ''')

    def test_pending_completion_does_not_admit_reset_of_its_own_force(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101})
          local before,marker=all_frames(),copy(storage[OWNER_KEY]);writes=0
          local ok,message=pcall(history.default_owner_on_force_reset,{force=player})
          assert(not ok and tostring(message):find("awaiting its bounded native observation",1,true))
          assert(writes==0 and same(before,all_frames()) and same(marker,storage[OWNER_KEY]))
          ok,message=pcall(history.default_owner_preflight,published517_se_bridge_event(),nil,true)
          assert(not ok and tostring(message):find("awaiting its bounded native observation",1,true))
          assert(writes==0 and same(before,all_frames()) and same(marker,storage[OWNER_KEY]))
          for _,initializing in ipairs{false,true}do
            ok,message=pcall(history.plan_default_owner_transfer,nil,nil,initializing,{})
            assert(not ok and tostring(message):find("awaiting its bounded native observation",1,true))
            assert(writes==0 and same(before,all_frames()) and same(marker,storage[OWNER_KEY]))
          end
          ok,message=pcall(history.plan_default_owner_transfer,nil,nil,false,{created_force=9999})
          assert(not ok and tostring(message):find("default local event force is unavailable",1,true))
          ok,message=pcall(history.plan_default_owner_transfer,nil,nil,false,
            {created_force=detached.index,finished_force=player.index})
          assert(not ok and tostring(message):find("default local event context is invalid",1,true))
          assert(writes==0 and same(before,all_frames()) and same(marker,storage[OWNER_KEY]))
        ''')

    def test_unrelated_force_apply_rejects_a_changed_pending_completion_marker(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=101})
          local fresh=make_force("late",5);install_force(fresh);game.forces.late=fresh
          history.on_force_created{force=fresh}
          local plan=history.plan_default_owner_transfer(nil,nil,false,{created_force=fresh.index})
          local owner=storage[OWNER_KEY];owner.forces[player.index].completion_tick=102
          local before=all_frames();writes=0
          local ok,message=pcall(history.apply_default_owner_transfer,plan)
          assert(not ok and tostring(message):find("stale default transfer plan",1,true))
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==owner
            and owner.forces[player.index].completion_tick==102)
          -- A nested setter callback must not let the final metadata publish
          -- overwrite a completion marker changed during native mutation.
          owner.forces[player.index].completion_tick=101
          plan=history.plan_default_owner_transfer(nil,nil,false,{created_force=fresh.index})
          local pending_frame=frame(player)
          local mt=getmetatable(fresh.technologies[ORDINARY]);local write=mt.__newindex;local nested=false
          mt.__newindex=function(object,key,value)
            write(object,key,value)
            if not nested then nested=true;owner.forces[player.index].completion_tick=103 end
          end
          writes=0;ok,message=pcall(history.apply_default_owner_transfer,plan)
          assert(not ok and tostring(message):find("pending completion changed during default mutation",1,true))
          assert(nested and writes>0 and same(pending_frame,frame(player)) and storage[OWNER_KEY]==owner
            and owner.forces[player.index].completion_tick==103)
        ''')

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

    def test_published517_premerge_refuses_each_unsettled_historical_source_without_writes(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY,OTHER};player.research_progress=.42
          suspended.technologies[ORDINARY].saved_progress=.27
          suspended.research_queue={OTHER,ORDINARY};suspended.research_progress=.19
          detached.technologies[ORDINARY].saved_progress=.31
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          assert(player.current_research.name==LEGACY517 and player.research_queue[1].name==LEGACY517,
            "current historical worker obligation was not prepared")
          assert(suspended.research_queue[2].name==LEGACY517
            and detached.technologies[LEGACY517].saved_progress==.31,
            "queued/detached historical worker obligations were not prepared")
          -- The old pre-capture accepted every one of these rows, then its
          -- post event dropped the invalid source metadata. Each signal is an
          -- independently observed historical obligation: current/queued,
          -- queued behind foreign research, and detached saved work.
          for _,source in ipairs{player,suspended,detached}do
            local before,state=all_frames(),storage[OWNER_KEY];writes=0
            local ok,message=pcall(history.default_owner_on_forces_merging,{source=source,destination=uninvested})
            assert(not ok and tostring(message):find("source has unsettled historical work",1,true)
              and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state
              and game.forces[source.name]==source)
          end
        ''')
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          -- Native completion can precede the research-finished callback.
          -- It is still historical debt until that callback settles the
          -- authenticated old contract onto current ownership.
          player.research_queue={OTHER};player.research_progress=0
          player.technologies[LEGACY517].level=6
          player.technologies[LEGACY517].saved_progress=0
          local before,state=all_frames(),storage[OWNER_KEY];writes=0
          local ok,message=pcall(history.default_owner_on_forces_merging,{source=player,destination=uninvested})
          assert(not ok and tostring(message):find("source has unsettled historical work",1,true)
            and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state,
            "completed historical pre-merge result: "..tostring(message))
        ''')
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          player.research_queue={OTHER};player.research_progress=0
          player.technologies[LEGACY517].level=6
          player.technologies[LEGACY517].saved_progress=0
          assert(history.default_owner_on_research_finished{research=player.technologies[LEGACY517],by_script=false,tick=101})
          assert(storage[OWNER_KEY].forces[player.index].phase=="owned")
          local state=storage[OWNER_KEY];local source_index=player.index;local destination_before=frame(suspended);writes=0
          assert(history.default_owner_on_forces_merging{source=player,destination=suspended})
          assert(writes==0 and storage[OWNER_KEY]==state)
          game.forces.player=nil
          local ok,why=history.default_owner_on_forces_merged{source_index=source_index,destination=suspended}
          assert(ok and why=="native-merge-metadata-only" and storage[OWNER_KEY]~=state)
          assert(storage[OWNER_KEY].forces[source_index]==nil and same(destination_before,frame(suspended)))
        ''')

    def test_published517_reset_requires_the_old_holder_to_be_empty_before_resuming_current_ownership(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local before,state=all_frames(),storage[OWNER_KEY];writes=0
          local ok,message=pcall(history.default_owner_on_force_reset,{force=player})
          assert(not ok and tostring(message):find("reset retained historical work",1,true)
            and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state)
        ''')
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          -- Host representation of Factorio's reset boundary: the reset has
          -- already cleared every owned and historical worker row.  This does
          -- not substitute for the exact-engine reset observation required by
          -- native qualification.
          player.research_queue={OTHER};player.research_progress=0
          for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517,HEAD}do
            local tech=player.technologies[id]
            tech.level=4;tech.researched=false;tech.saved_progress=0
            tech.enabled=prototypes.technology[id].enabled
            -- The authored public prototype leaves its default visibility
            -- implicit; Factorio exposes the resulting force property as
            -- false, rather than a missing observation.
            if id==CANONICAL then tech.visible_when_disabled=false
            else tech.visible_when_disabled=prototypes.technology[id].visible_when_disabled end
          end
          writes=0;queue_writes={};progress_writes={}
          for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517,HEAD}do
            local tech=player.technologies[id]
            assert(type(tech.level)=="number" and type(tech.researched)=="boolean"
              and type(tech.enabled)=="boolean" and type(tech.visible_when_disabled)=="boolean"
              and type(tech.saved_progress)=="number", "incomplete reset frame: "..id
                .." level="..type(tech.level).." researched="..type(tech.researched)
                .." enabled="..type(tech.enabled).." visible="..type(tech.visible_when_disabled)
                .." saved="..type(tech.saved_progress))
          end
          local legacy=player.technologies[LEGACY517]
          assert(legacy.level==4 and not legacy.researched and legacy.saved_progress==0
            and not legacy.enabled and not legacy.visible_when_disabled,
            "reset did not clear legacy holder: level="..legacy.level.." researched="..tostring(legacy.researched)
              .." saved="..legacy.saved_progress.." enabled="..tostring(legacy.enabled)
              .." visible="..tostring(legacy.visible_when_disabled))
          -- Bootstrap routes the retained private-worker reset hook before
          -- default-owner recovery.  Its no-history path must not turn the
          -- cleared historical holder into current work.
          history.on_force_reset{force=player};writes=0
          assert(history.default_owner_on_force_reset{force=player})
          local record=storage[OWNER_KEY]
          assert(record.schema==4 and record.forces[player.index].phase=="owned")
          assert(player.technologies[ORDINARY].level==4 and not player.technologies[CANONICAL].enabled
            and player.technologies[LEGACY517].level==4 and not player.technologies[LEGACY517].enabled
            and player.technologies[HEAD].level==4 and not player.technologies[HEAD].enabled)
          assert(player.worker_robots_storage_bonus==20 and player.current_research.name==OTHER)
        ''')

    def test_published517_late_force_starts_only_on_the_current_contract(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local fresh=make_force("late",5);install_force(fresh);game.forces.late=fresh
          history.on_force_created{force=fresh};writes=0
          assert(history.default_owner_on_force_created{force=fresh})
          local record=storage[OWNER_KEY];local legacy=fresh.technologies[LEGACY517]
          assert(record.schema==4 and record.forces[fresh.index].phase=="owned")
          assert(fresh.technologies[ORDINARY].level==4 and not fresh.technologies[CANONICAL].enabled
            and legacy.level==4 and not legacy.enabled and not legacy.visible_when_disabled
            and fresh.technologies[HEAD].level==4 and not fresh.technologies[HEAD].enabled)
          assert(fresh.worker_robots_storage_bonus==20)
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
    def world(self, target="f210"):
        return build_full_default_provider_handover_world(
            LuaRuntime, target=target, source_root=ROOT / "source"
        )

    def test_published517_provider_handover_waits_for_old_work_then_retires_the_legacy_schema(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)),"bridge")
          assert(storage[OWNER_KEY].schema==4 and storage[OWNER_KEY].forces[player.index].phase=="legacy","legacy phase")
          player.technologies[LEGACY517].level=6
          player.research_queue={OTHER};player.research_progress=0
          player.technologies[LEGACY517].saved_progress=0
          local changed=history.default_owner_on_research_finished{research=player.technologies[LEGACY517],by_script=false,tick=101}
          assert(changed)
          for _,force in pairs(game.forces)do
            local t=force.technologies[ID];local mt=getmetatable(t);local read=mt.__index
            mt.__index=function(object,key)
              if key=="research_unit_count"then return math.floor(675*1.5^(read(object,"level")-4))end
              return read(object,key)
            end
          end
          finite_entry(1);local event=provider_event()
          local recovery=require("research.worker_storage_recovery")
          assert(recovery.fingerprint(prototypes.technology[ID])==recovery.fingerprint(prototypes.technology[ORDINARY]),"private contract")
          local ok,plan,legacy=pcall(delegate,event,provider_route(5));assert(ok,plan)
          assert(plan.record.schema==3 and plan.record.legacy==nil and plan.record.kind=="provider-retired")
          assert(history.default_owner_apply(plan));history.apply(legacy)
          assert(storage[OWNER_KEY].schema==3 and storage[OWNER_KEY].kind=="provider-retired")
        ''')

    def test_published517_pending_completion_refuses_provider_handover_before_any_native_write(self):
        lua=self.world("f200")
        lua.execute(r'''
          published517_source_contract();init_default()
          finish_frame(player,"advanced",{ORDINARY},false)
          assert(history.default_owner_on_research_finished(finish_event(player)))
          player.technologies[ORDINARY].saved_progress=.42
          player.research_queue={ORDINARY};player.research_progress=.42
          current_se_contract()
          assert(history.default_owner_apply(history.default_owner_preflight(published517_se_bridge_event(),nil,true)))
          local legacy=player.technologies[LEGACY517]
          player.research_queue={LEGACY517,OTHER};player.research_progress=1;legacy.researched=true
          assert(history.default_owner_on_research_finished{research=legacy,by_script=false,tick=351})
          finite_entry(1);local before,state=all_frames(),storage[OWNER_KEY];writes=0
          local ok,message=pcall(delegate,provider_event(),provider_route(5))
          assert(not ok and tostring(message):find("paid work must settle",1,true)
            and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==state)
        ''')

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

    def test_provider_addition_after_successive_updates_preserves_origin_and_native_work(self):
        for target in ("f200", "f210"):
            for sequence in ("direct", "one-update", "two-updates", "separate"):
                for scalar in (0, 2):
                    with self.subTest(target=target, sequence=sequence, scalar=scalar):
                        lua=self.world(target)
                        lua.globals().sequence=sequence;lua.globals().scalar=scalar
                        lua.execute(r'''
                          full_source(scalar,true)
                          player.research_queue={ORDINARY,ORDINARY,OTHER};player.research_progress=.375
                          local target=package.loaded["platform.target"]
                          local prefix=package_family=="f200"and"5.0.200"or"5.0.210"
                          local producer=copy(storage[OWNER_KEY].producer)
                          local steps=sequence=="one-update"and{16}or sequence=="two-updates"and{14,16}
                            or sequence=="separate"and{14,16,17}or{}
                          for _,patch in ipairs(steps)do
                            local previous=target.distribution_version
                            target.distribution_version=prefix..string.format("%02d",patch)
                            script.active_mods["more-infinite-research"]=target.distribution_version
                            local before=all_frames();writes=0
                            local plan=history.default_owner_preflight(owner_event(previous),nil,true)
                            assert(not history.default_owner_apply(plan)and writes==0 and same(before,all_frames()))
                            assert(same(producer,storage[OWNER_KEY].producer))
                          end
                          local previous=target.distribution_version
                          target.distribution_version=prefix.."17"
                          script.active_mods["more-infinite-research"]=target.distribution_version
                          finite_entry(1);local event=provider_event()
                          if sequence~="separate"then
                            event.mod_changes["more-infinite-research"]={old_version=previous,new_version=target.distribution_version}
                          end
                          local before=all_frames();local foreign=foreign_frames()
                          local owner=storage[OWNER_KEY];local state=storage.mir_worker_storage_route
                          local plan,legacy=delegate(event)
                          assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==owner
                            and storage.mir_worker_storage_route==state)
                          history.default_owner_apply(plan);history.apply(legacy)
                          assert(same(producer,storage[OWNER_KEY].producer)and producer.new_version==prefix.."12")
                          assert(same(foreign,foreign_frames()))
                          for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                            local queue=copy(b.queue)
                            for i,name in ipairs(queue)do if name==ORDINARY then queue[i]=ID end end
                            assert(a.private.level==b.owner.level and a.private.saved==b.owner.saved)
                            assert(a.bonus==b.bonus and a.other_saved==b.other_saved and same(a.debit,b.debit))
                            assert(same(a.queue,queue)and a.progress==b.progress)
                            assert(a.current==(b.current==ORDINARY and ID or b.current))
                          end
                          local after=all_frames();owner=storage[OWNER_KEY];state=storage.mir_worker_storage_route
                          -- Host module reconstruction checks are not native save/cold-load evidence.
                          for i=1,2 do
                            package.loaded["runtime.worker_robot_storage"]=nil
                            history=require("runtime.worker_robot_storage");writes=0
                            local saved_game,saved_prototypes=game,prototypes
                            game=setmetatable({},{__index=function()error("on_load game access")end})
                            prototypes=setmetatable({},{__index=function()error("on_load prototype access")end})
                            history.on_load();history.default_owner_on_load()
                            game,prototypes=saved_game,saved_prototypes
                            assert(writes==0 and same(after,all_frames())and storage[OWNER_KEY]==owner
                              and storage.mir_worker_storage_route==state)
                          end
                          local f=uninvested;local bonus=f.worker_robots_storage_bonus
                          f.research_queue={OTHER};f.research_progress=.23;f.technologies[ID].level=5
                          assert(history.on_research_event({research=f.technologies[ID],by_script=false},true))
                          assert(f.worker_robots_storage_bonus==bonus+scalar and not f.technologies[ID].enabled)
                          assert(not state.forces[f.index].pending and same(producer,storage[OWNER_KEY].producer))
                          assert(same(foreign,foreign_frames()))
                        ''')

    def test_intervening_updates_do_not_authorize_contradictory_package_or_provider_events(self):
        for target in ("f200", "f210"):
            for opponent in ("false-change", "non-table", "missing-old", "non-string-old", "before-origin",
                             "future-old", "other-edition", "legacy-old", "missing-new", "wrong-new",
                             "provider-update", "unrelated-update"):
                with self.subTest(target=target, opponent=opponent):
                    lua=self.world(target);lua.globals().opponent=opponent
                    lua.execute(r'''
                      full_source(2,true);local target=package.loaded["platform.target"]
                      local prefix=package_family=="f200"and"5.0.200"or"5.0.210"
                      local previous=target.distribution_version
                      target.distribution_version=prefix.."16";script.active_mods["more-infinite-research"]=target.distribution_version
                      history.default_owner_apply(history.default_owner_preflight(owner_event(previous),nil,true))
                      target.distribution_version=prefix.."17";script.active_mods["more-infinite-research"]=target.distribution_version
                      finite_entry(1);local event=provider_event()
                      local mir={old_version=prefix.."16",new_version=prefix.."17"};event.mod_changes["more-infinite-research"]=mir
                      if opponent=="false-change"then event.mod_changes["more-infinite-research"]=false
                      elseif opponent=="non-table"then event.mod_changes["more-infinite-research"]="16"
                      elseif opponent=="missing-old"then mir.old_version=nil
                      elseif opponent=="non-string-old"then mir.old_version=16
                      elseif opponent=="before-origin"then mir.old_version=prefix.."11"
                      elseif opponent=="future-old"then mir.old_version=prefix.."18"
                      elseif opponent=="other-edition"then mir.old_version=(package_family=="f200"and"5.0.210"or"5.0.200").."16"
                      elseif opponent=="legacy-old"then mir.old_version="4.7.21003"
                      elseif opponent=="missing-new"then mir.new_version=nil
                      elseif opponent=="wrong-new"then mir.new_version=prefix.."16"
                      elseif opponent=="provider-update"then event.mod_changes.provider.old_version="0.9"
                      else event.mod_changes.other={old_version="1",new_version="2"};script.active_mods.other="2"end
                      local before=all_frames();local owner=storage[OWNER_KEY];local state=storage.mir_worker_storage_route;writes=0
                      local ok,message=pcall(history.default_owner_preflight,event,provider_route(5),true)
                      assert(not ok and tostring(message):find("MIR-WORKER-HISTORY",1,true))
                      assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==owner
                        and storage.mir_worker_storage_route==state)
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

    def test_provider_transfer_preserves_newer_parked_work_on_a_later_force(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  full_source(1, true)
                  finite_entry(1)
                  local plan = delegate()
                  local updated, owner, quota = nil, storage[OWNER_KEY], storage.mir_worker_storage_route
                  after_first_level_write(player.technologies[ID], function()
                    detached.technologies[ORDINARY].saved_progress = .71
                    updated = frame(detached)
                  end)
                  local ok, message = pcall(history.default_owner_apply, plan)
                  assert(not ok and tostring(message):find("work changed during another force's transfer", 1, true))
                  assert(updated and updated.owner.saved == .71 and same(frame(detached), updated))
                  assert(storage[OWNER_KEY] == owner and storage.mir_worker_storage_route == quota)
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
        return build_full_default_provider_handover_world(LuaRuntime, target=target, source_root=ROOT / "source")

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
    """Known473 default work, old idle records and501-empty restrictions."""

    def world(self, target="f210"):
        return build_default_native_owner_world(
            LuaRuntime, target=target, source_root=ROOT / "source"
        )

    def older_world(self, target="f200"):
        return build_older_default_admission_world(
            LuaRuntime, target=target, source_root=ROOT / "source"
        )

    def enable_space_age(self, lua, engine_version="2.1.23", recycler=True):
        lua.globals().official_engine_version = engine_version
        lua.globals().official_recycler = recycler
        lua.execute(r'''
          script.active_mods.base=official_engine_version
          for _,name in ipairs({"space-age","quality","elevated-rails"})do
            script.active_mods[name]=official_engine_version
          end
          if official_recycler then script.active_mods.recycler=official_engine_version end
          for _,id in ipairs({CANONICAL,ORDINARY,ID})do
            table.insert(prototypes.technology[id].research_unit_ingredients,
              {name="electromagnetic-science-pack",amount=1})
          end
        ''')

    def published472_se_world(self):
        # Exact F394 data observation: 151772B05E30D288EC3CD85E62A6B7E3313B6C5F9D89A66EAF0FD66D635A1104.
        # These are native-frame doubles, not an earned source save.
        lua=self.older_world("f200")
        lua.execute(r'''
          current_se_contract();script.active_mods["space-exploration"]="0.7.57"
          require("runtime.configuration").streams["worker-robots-storage"].max_level=10
          history.configure(10,true)
          for _,force in pairs(game.forces)do
            for _,id in ipairs{CANONICAL,ORDINARY}do
              force.technologies[id].prerequisites={["worker-robots-storage-3"]={researched=true}}
            end
          end
        ''')
        return lua

    def test_472_se_observed_contract_transfers_full_native_work_once(self):
        lua=self.published472_se_world()
        lua.execute(r'''
          seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER}
          foreign_bonus[detached.index]=73
          local event=older_event("4.7.20002",false);local before=all_frames();writes=0
          local plan=history.default_owner_preflight(event,nil,true)
          assert(type(plan)=="table" and plan.kind=="default-native-owner-transfer"
            and plan.record.producer.kind=="published472-se-default"
            and writes==0 and same(before,all_frames()))
          assert(history.default_owner_apply(plan))
          for _,force in pairs(game.forces)do
            local a,b=frame(force),before[force.index]
            local current=b.current==CANONICAL and ORDINARY or b.current
            local queue={}for i,id in ipairs(b.queue)do queue[i]=id==CANONICAL and ORDINARY or id end
            assert(a.owner.level==b.source.level and not a.owner.researched and a.owner.saved==b.source.saved)
            assert(a.owner.count==b.source.count and a.owner.enabled==b.source.enabled
              and a.owner.visible==b.source.visible)
            assert(a.current==current and a.progress==b.progress and same(a.queue,queue))
            assert(a.other_saved==b.other_saved and same(a.private,b.private) and a.bonus==b.bonus)
          end
          assert(player.research_queue[1].name==ORDINARY and player.research_queue[2].name==ORDINARY)
          local settled=all_frames();writes=0;history.default_owner_on_load()
          local again=history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)
          assert(not history.default_owner_apply(again) and writes==0 and same(settled,all_frames()))
          assert(storage[OWNER_KEY].producer.old_version=="4.7.20002")
          local producer=storage[OWNER_KEY].producer
          for _,invalid in ipairs{"4.7.20001","4.7.20003","4.7.21002"}do
            producer.old_version=invalid
            assert(not pcall(history.default_owner_on_load) and writes==0 and same(settled,all_frames()))
          end
          producer.old_version="4.7.20002";history.default_owner_on_load()
          -- After authentication, a later explicit cap change is governed by
          -- the ordinary owned-state path, not this first-upgrade admission.
          require("runtime.configuration").streams["worker-robots-storage"].max_level=0
          history.configure(0,true)
          local retune=history.default_owner_preflight({mod_startup_settings_changed=true,mod_changes={}},nil,true)
          history.default_owner_apply(retune)
          assert(writes==0 and same(settled,all_frames()) and storage[OWNER_KEY].settings.max_level==0)
        ''')

    def test_472_se_transfers_paid_work_with_unchanged_elevated_rails(self):
        for explicit_rail_row in (False, True):
            with self.subTest(explicit_rail_row=explicit_rail_row):
                lua = self.published472_se_world()
                lua.globals().explicit_rail_row = explicit_rail_row
                lua.execute(r'''
                  script.active_mods["elevated-rails"]="2.0.77"
                  local event=older_event("4.7.20002",false)
                  if explicit_rail_row then
                    event.mod_changes["elevated-rails"]={old_version="2.0.77",new_version="2.0.77"}
                  end
                  seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER}
                  -- Level 11 was already earned in this old save. A cap on
                  -- future research must preserve that credit and parked work.
                  detached.technologies[CANONICAL].level=12
                  local before=all_frames();writes=0
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(plan.record.producer.kind=="published472-se-default")
                  assert(writes==0 and same(before,all_frames()))
                  assert(history.default_owner_apply(plan))
                  for _,force in pairs(game.forces)do
                    local a,b=frame(force),before[force.index]
                    local queue={}for i,id in ipairs(b.queue)do queue[i]=id==CANONICAL and ORDINARY or id end
                    assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                    assert(a.owner.count==b.source.count and a.bonus==b.bonus)
                    assert(a.current==(b.current==CANONICAL and ORDINARY or b.current))
                    assert(a.progress==b.progress and same(a.queue,queue)and a.other_saved==b.other_saved)
                  end
                ''')

    def test_472_se_admission_rejects_other_events_settings_and_native_contracts_without_writes(self):
        opponents=(
            'event.mod_startup_settings_changed=true',
            'event.mod_changes["more-infinite-research"].old_version="4.7.20001"',
            'script.active_mods["space-exploration"]="0.7.58"',
            'script.active_mods.base="2.0.78"',
            'script.active_mods.Krastorio2="1.0.0"',
            'script.active_mods["space-age"]="2.0.77"',
            'script.active_mods["elevated-rails"]="2.0.76"',
            'script.active_mods["elevated-rails"]="2.0.77";event.mod_changes["elevated-rails"]={new_version="2.0.77"}',
            'script.active_mods["elevated-rails"]="2.0.77";event.mod_changes["elevated-rails"]={old_version="2.0.76",new_version="2.0.77"}',
            'event.mod_changes["elevated-rails"]={old_version="2.0.77"}',
            'script.active_mods["new-mod"]="1";event.mod_changes["new-mod"]={new_version="1"}',
            'event.mod_changes["space-exploration"]={old_version="0.7.56",new_version="0.7.57"}',
            'event.mod_changes["removed-mod"]={old_version="1"}',
            'setmetatable(event.mod_changes,{})',
            'setmetatable(event.mod_changes["more-infinite-research"],{})',
            'require("runtime.configuration").streams["worker-robots-storage"].base_cost=201',
            'require("runtime.configuration").streams["worker-robots-storage"].max_level=9;history.configure(9,true)',
            'for _,id in ipairs{CANONICAL,ORDINARY}do prototypes.technology[id].research_unit_count_formula="676*1.5^(L-4)"end',
            'for _,id in ipairs{CANONICAL,ORDINARY}do prototypes.technology[id].research_unit_ingredients[7].name="automation-science-pack"end',
            'for _,id in ipairs{CANONICAL,ORDINARY}do prototypes.technology[id].prerequisites={foundation={name="foundation"}}end',
            'uninvested.technologies[ORDINARY].level=5',
            'uninvested.technologies[ORDINARY].saved_progress=.1',
            'uninvested.research_queue={ORDINARY}',
        )
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua=self.published472_se_world();lua.globals().opponent=opponent
                lua.execute(r'''
                  seed_owner();local event=older_event("4.7.20002",false)
                  assert(load(opponent,"independent472opponent","t",setmetatable({event=event},{__index=_G})))()
                  local before=all_frames();writes=0
                  local ok=pcall(history.default_owner_preflight,event,nil,true)
                  assert(not ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                ''')

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

    def archived_k2_worker_world(self, *, extra=True):
        lua = self.older_world("f210")
        self.enable_space_age(lua, "2.1.23")
        lua.execute(r'''
          local frozen_dependencies={
            Krastorio2="2.1.4", ["Krastorio2-spaced-out"]="2.0.19",
            Krastorio2Assets="2.1.0", Krastorio2MenuSimulations="2.1.0",
            ["k2so-assets"]="1.0.7", flib="0.17.2", ["xy-k2so-enhancements-nulls-fork"]="0.8.3"
          }
          for name,version in pairs(frozen_dependencies)do script.active_mods[name]=version end
          local prior_history=prototypes.get_history
          prototypes.get_history=function(kind,name)
            if kind=="technology" and name==CANONICAL then
              return {created="more-infinite-research",changed={"more-infinite-research"}}
            end
            return prior_history(kind,name)
          end
          archived_event=older_event("4.6.21000",false)
        ''')
        if extra:
            lua.execute('script.active_mods["neutral-unchanged-addon"]="1.0.0"')
        return lua

    def test_archived_k2_worker_admission_preserves_unrelated_paid_work(self):
        self.archived_k2_worker_world().execute(r'''
          player.research_queue={OTHER};player.research_progress=.42
          detached.technologies[OTHER].saved_progress=.27
          uninvested.technologies[CANONICAL].enabled=false
          local before=all_frames();writes=0;queue_writes={};progress_writes={}
          local plan=history.default_owner_preflight(archived_event,nil,true)
          assert(plan.record.producer.kind=="archived-uninvested-default"
            and plan.record.producer.old_version=="4.6.21000")
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
          assert(history.default_owner_apply(plan))
          history.default_owner_on_load()
          for _,force in pairs(game.forces)do
            local old,now=before[force.index],frame(force)
            assert(now.owner.level==4 and not now.owner.researched and now.owner.enabled==old.source.enabled)
            assert(now.bonus==old.bonus and now.other_saved==old.other_saved)
            assert(now.current==old.current and now.progress==old.progress and same(now.queue,old.queue))
            assert(queue_writes[force.index]==nil and progress_writes[force.index]==nil)
          end
        ''')

    def test_archived_k2_worker_admission_refuses_unverified_history_before_writes(self):
        for change, expected in (
            ("detached.technologies[CANONICAL].level=5", "earned, queued or unfinished worker work"),
            ("detached.research_queue={OTHER,CANONICAL}", "earned, queued or unfinished worker work"),
            ("detached.technologies[CANONICAL].saved_progress=.27", "earned, queued or unfinished worker work"),
            ("archived_event.mod_startup_settings_changed=true", "requires unchanged startup settings"),
            ('archived_event.mod_changes["unreported-provider"]={old_version="1.0.0"}',
             "requires the unchanged mod selection"),
            ('script.active_mods["Krastorio2-spaced-out"]="2.0.18"', "qualified dependency versions"),
            ('archived_event.mod_changes["more-infinite-research"].old_version="4.6.21001"',
             "unrecorded default source has no qualified MIR5 producer"),
            ('script.active_mods.recycler=nil', "requires its official mod selection"),
            ('prototypes.technology[CANONICAL].research_unit_count_formula="676*1.5^(L-4)"',
             "canonical4/full default4 contract or custody differs"),
            ('local prior=prototypes.get_history;prototypes.get_history=function(kind,name) '
             'local observed=prior(kind,name);if name==CANONICAL then observed.changed={"unknown-worker-editor"} end;'
             'return observed end', "unverified prototype history"),
        ):
            with self.subTest(change=change):
                lua = self.archived_k2_worker_world()
                lua.globals().expected_refusal = expected
                lua.execute(change + r'''
                  local before=all_frames();writes=0
                  local ok,why=pcall(history.default_owner_preflight,archived_event,nil,true)
                  assert(not ok and tostring(why):find(expected_refusal,1,true),tostring(why))
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                ''')

    def test_473_startup_change_adopts_empty_workers_and_preserves_unrelated_work(self):
        for target, legacy_version, base, space_age in (
            ("f200", "4.7.20003", "2.0.77", False),
            ("f200", "4.7.20003", "2.0.77", True),
            ("f210", "4.7.21003", "2.1.24", False),
            ("f210", "4.7.21003", "2.1.24", True),
        ):
            with self.subTest(target=target, space_age=space_age):
                lua = self.older_world(target)
                lua.globals().legacy_version = legacy_version
                lua.globals().test_base = base
                lua.execute("script.active_mods.base=test_base")
                if space_age:
                    self.enable_space_age(lua, base, recycler=target == "f210")
                lua.execute(r'''
                  player.research_queue={OTHER};player.research_progress=.42
                  suspended.technologies[OTHER].saved_progress=.27
                  uninvested.technologies[CANONICAL].enabled=false
                  local event=older_event(legacy_version,false);event.mod_startup_settings_changed=true
                  if not script.active_mods["space-age"] then
                    script.active_mods["unrelated-updated-mod"]="0.8.0"
                    script.active_mods["unrelated-unchanged-mod"]="1.0.0"
                    event.mod_changes["unrelated-updated-mod"]={old_version="0.4.0",new_version="0.8.0"}
                  end
                  local before=all_frames();writes=0;queue_writes={};progress_writes={}
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                  assert(plan.record.producer.kind=="published473-idle-default")
                  assert(history.default_owner_apply(plan))
                  history.default_owner_on_load()
                  for _,force in pairs(game.forces)do
                    local old,now=before[force.index],frame(force)
                    assert(now.owner.level==4 and not now.owner.researched and now.owner.enabled==old.source.enabled)
                    assert(now.bonus==old.bonus and now.other_saved==old.other_saved)
                    assert(now.current==old.current and now.progress==old.progress and same(now.queue,old.queue))
                    assert(queue_writes[force.index]==nil and progress_writes[force.index]==nil)
                  end
                ''')

    def test_473_f210_startup_change_refuses_earned_queued_or_paid_cargo(self):
        for change, expected in (
            ("detached.technologies[CANONICAL].level=5", "earned worker levels"),
            ("detached.research_queue={CANONICAL};detached.research_progress=.27",
             "unfinished native worker work"),
            ("detached.research_queue={OTHER,CANONICAL}", "unfinished native worker work"),
            ("detached.technologies[CANONICAL].saved_progress=.27",
             "unfinished native worker work"),
            ("detached.technologies[HEAD].level=5;detached.technologies[HEAD].enabled=false",
             "owner/debit is not pristine"),
        ):
            with self.subTest(change=change):
                lua = self.older_world("f210")
                self.enable_space_age(lua, "2.1.24")
                lua.globals().expected_refusal = expected
                lua.execute(change + r'''
                  local event=older_event("4.7.21003",false)
                  event.mod_startup_settings_changed=true
                  local before=all_frames();writes=0
                  local ok,reason=pcall(history.default_owner_preflight,event,nil,true)
                  assert(not ok and tostring(reason):find(expected_refusal,1,true),tostring(reason))
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                ''')

    def test_f200_473_startup_change_refuses_worker_investment_or_unavailable_inputs(self):
        opponents=(
            'detached.technologies[CANONICAL].level=5',
            'detached.technologies[CANONICAL].researched=true',
            'detached.technologies[CANONICAL].saved_progress=.27',
            'detached.research_queue={CANONICAL}',
            'detached.research_queue={OTHER,CANONICAL}',
            'detached.technologies[ORDINARY].level=5',
            'event.mod_changes.removed={old_version="1"}',
            'event.mod_changes["unrelated-updated-mod"].new_version="0.9.0"',
            'event.mod_changes["unrelated-updated-mod"].old_version=false',
            'setmetatable(event.mod_changes["unrelated-updated-mod"],{})',
            'script.active_mods["space-age"]="2.0.77"',
            'require("runtime.configuration").streams["worker-robots-storage"].base_cost=201',
        )
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua=self.older_world()
                lua.execute(r'''
                  local event=older_event("4.7.20003",false);event.mod_startup_settings_changed=true
                  script.active_mods["unrelated-updated-mod"]="0.8.0"
                  event.mod_changes["unrelated-updated-mod"]={old_version="0.4.0",new_version="0.8.0"}
                '''+opponent+r'''
                  refuse_older(event)
                ''')

    def sif_removal_world(self):
        lua = self.older_world()
        lua.execute(r'''
          for _,name in ipairs({"space-age","quality","elevated-rails"}) do
            script.active_mods[name]="2.0.77"
          end
          for _,id in ipairs({CANONICAL,ORDINARY,ID}) do
            table.insert(prototypes.technology[id].research_unit_ingredients,
              {name="electromagnetic-science-pack",amount=1})
          end
          event=older_event("5.0.20003",false)
          event.mod_startup_settings_changed=true
          event.mod_changes["space-is-fake"]={old_version="1.0.60"}
          event.mod_changes["cr-commons"]={old_version="1.0.27"}
        ''')
        return lua

    def test_sif_removal_transfers_empty_worker_ownership_and_keeps_unrelated_work(self):
        lua = self.sif_removal_world()
        lua.execute(r'''
          player.research_queue={OTHER};player.research_progress=.42
          suspended.technologies[OTHER].saved_progress=.27
          uninvested.technologies[CANONICAL].enabled=false
          local before=all_frames();writes=0;queue_writes={};progress_writes={}
          local plan=history.default_owner_preflight(event,nil,true)
          assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
          assert(plan.record.producer.kind=="published503-sif-empty-default")
          assert(history.default_owner_apply(plan))
          history.default_owner_on_load()
          for _,force in pairs(game.forces) do
            local old,now=before[force.index],frame(force)
            assert(now.owner.level==4 and not now.owner.researched and now.owner.enabled==old.source.enabled)
            assert(now.bonus==old.bonus and now.other_saved==old.other_saved)
            assert(now.current==old.current and now.progress==old.progress and same(now.queue,old.queue))
            assert(queue_writes[force.index]==nil and progress_writes[force.index]==nil)
          end
        ''')

    def test_sif_removal_refuses_invested_workers_and_different_source_contracts(self):
        opponents = (
            'detached.technologies[CANONICAL].level=5',
            'detached.technologies[CANONICAL].researched=true',
            'detached.technologies[CANONICAL].saved_progress=.27',
            'detached.research_queue={OTHER,CANONICAL}',
            'detached.research_queue={CANONICAL}',
            'event.mod_changes["space-is-fake"].old_version="1.0.61"',
            'event.mod_changes["cr-commons"]=nil',
            'event.mod_changes.third={old_version="1.0.0"}',
            'script.active_mods["extra"]="1.0.0"',
            'script.active_mods.quality="2.0.76"',
            'event.mod_changes.quality={old_version="2.0.76",new_version="2.0.77"}',
            'event.mod_changes["more-infinite-research"].old_version="5.0.20004"',
            'require("runtime.configuration").streams["worker-robots-storage"].base_cost=201',
        )
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua = self.sif_removal_world()
                lua.execute(opponent + "\nrefuse_older(event)")

    def test_473_paid_idle_preserves_native_levels_and_foreign_work(self):
        lua=self.older_world();lua.execute(r'''
          paid_idle();local event=older_event("4.7.20003",true);local before=all_frames()
          local plan=older_plan(event);assert(writes==0 and plan.record.producer.kind=="published473-default")
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

    def test_473_f210_same_edition_preserves_empty_and_paid_idle_work_and_producer(self):
        # MIG-05 requires the published same-edition4.7.3 predecessor. The
        # existing4.7.20003 forward route does not cover4.7.21003.
        for paid in (False, True):
            for observer_added in (False, True):
                with self.subTest(paid=paid, observer_added=observer_added):
                    lua=self.older_world("f210")
                    lua.globals().paid=paid;lua.globals().observer_added=observer_added
                    lua.execute(r'''
                      if paid then paid_idle()else
                        for _,f in pairs(game.forces)do f.research_queue={OTHER};f.research_progress=.42 end
                        uninvested.technologies[CANONICAL].enabled=false
                        detached.technologies[OTHER].saved_progress=.27
                      end
                      writes=0;queue_writes={};progress_writes={};local before=all_frames()
                      local event=older_event("4.7.21003",observer_added)
                      local plan=history.default_owner_preflight(event,nil,true)
                      assert(writes==0 and same(before,all_frames()))
                      assert(plan.record.producer.kind=="published473-default")
                      assert(plan.record.producer.old_version=="4.7.21003")
                      assert(plan.record.producer.new_version=="5.0.21012")
                      assert(history.default_owner_apply(plan))
                      for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                        assert(a.owner.level==b.source.level and a.owner.count==b.source.count)
                        assert(a.owner.enabled==b.source.enabled and a.bonus==b.bonus)
                        assert(a.current==b.current and a.progress==b.progress and same(a.queue,b.queue))
                        assert(a.other_saved==b.other_saved and same(a.private,b.private))
                        assert(queue_writes[f.index]==nil and progress_writes[f.index]==nil)
                      end
                      local saved=storage[OWNER_KEY];local settled=all_frames();writes=0
                      local original_game,original_prototypes=game,prototypes
                      game=setmetatable({}, {__index=function()error("cold native game read")end})
                      prototypes=setmetatable({}, {__index=function()error("cold prototype read")end})
                      for i=1,2 do package.loaded["runtime.worker_robot_storage"]=nil
                        history=require("runtime.worker_robot_storage");history.default_owner_on_load()
                        assert(storage[OWNER_KEY]==saved and writes==0)
                      end
                      game,prototypes=original_game,original_prototypes;history.configure(0,true)
                      local again=history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)
                      assert(not history.default_owner_apply(again)and writes==0 and same(settled,all_frames()))
                      saved.producer.new_version="5.0.20012"
                      assert(not pcall(history.default_owner_on_load)and writes==0)
                    ''')

    def test_473_f210_rejects_ambiguous_or_unfinished_history_before_writes(self):
        opponents=(
            'script.active_mods.foreign="1"',
            'script.active_mods.foreign="1";event.mod_changes.foreign={old_version="1",new_version="1"}',
            'event.mod_changes.removed={old_version="1"}',
            'event.mod_startup_settings_changed=true;detached.technologies[CANONICAL].saved_progress=.27',
            'event.mod_changes.base={old_version="2.1.22",new_version="2.1.23"}',
            'script.active_mods["space-age"]="2.1.23";event.mod_changes["space-age"]={new_version="2.1.23"}',
            'event.mod_changes["more-infinite-research"].old_version="4.7.21002"',
            'event.mod_changes["more-infinite-research"].old_version="4.7.20003"',
            'event.mod_changes["more-infinite-research"].new_version="5.0.21013"',
            'creators[CANONICAL]="foreign"',
            'detached.technologies[CANONICAL].saved_progress=1.1',
            'detached.technologies[ID].level=5',
            'history.configure(4,true)',
            'require("runtime.configuration").streams["worker-robots-storage"].effect_percent=2')
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                lua=self.older_world("f210")
                lua.execute('local event=older_event("4.7.21003",true);'+opponent+';refuse_older(event)')

    def test_first_owner_refusals_report_the_actual_473_event_base_and_current_route(self):
        cases=(
            ("f210", "4.7.21002", "2.1.24", "2.1.23", "2.1.24", True,
             "unrecorded default source requires unchanged startup settings"),
            ("f210", "4.7.21003", "2.1.24", "2.1.22", "2.1.24", True,
             "older default source requires its qualified Base engine and unchanged settings"),
            ("f200", "4.7.20003", "2.0.76", "2.0.77", "2.0.76", False,
             "older default source requires its qualified Base engine and unchanged settings"),
        )
        for target, old, active_base, old_base, new_base, startup, reason in cases:
            with self.subTest(target=target, reason=reason):
                lua=self.older_world(target)
                lua.globals().old=old;lua.globals().active_base=active_base
                lua.globals().old_base=old_base;lua.globals().new_base=new_base
                lua.globals().startup=startup
                lua.globals().reason=reason
                lua.execute(r'''
                  local event=older_event(old,false);script.active_mods.base=active_base
                  event.mod_startup_settings_changed=startup
                  event.mod_changes.base={old_version=old_base,new_version=new_base}
                  local before=all_frames();writes=0
                  local ok,message=pcall(history.default_owner_preflight,event,nil,true)
                  assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                  message=tostring(message);assert(message:find(reason,1,true))
                  assert(message:find("previous_mir="..old,1,true))
                  assert(message:find("new_mir=5.0."..(package_family=="f210"and"21012"or"20012"),1,true))
                  assert(message:find("startup_changed="..tostring(startup),1,true))
                  assert(message:find("saved_route=absent",1,true)and message:find("current_route=default",1,true))
                  assert(message:find("active_base="..active_base,1,true))
                  assert(message:find("qualified_minimum_base="..(package_family=="f210"and"2.1.23"or"2.0.77"),1,true))
                  assert(message:find("base_event=base="..old_base.."->"..new_base,1,true))
                ''')

    def test_first_owner_refusal_escapes_the_available_base_event_without_writes(self):
        lua=self.older_world("f210")
        lua.execute(r'''
          local event=older_event("4.7.21003",false);event.mod_startup_settings_changed=false
          event.mod_changes.base={old_version="2.1.23\0\nold",new_version="2.1.24"}
          script.active_mods.base="2.1.24";local before=all_frames();writes=0
          local ok,message=pcall(history.default_owner_preflight,event,nil,true)
          assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
          message=tostring(message)
          assert(message:find("older default source requires its qualified Base engine and unchanged settings",1,true))
          assert(message:find("base_event=base=2.1.23\\x00\\x0Aold->2.1.24",1,true))
          assert(message:find("current_route=default",1,true)and not message:find("\0",1,true))
        ''')

    def test_current_package_minimum_and_historical_base_floor_are_independent(self):
        cases = (("2.1.22", "2.1.22", "2.1.25"), ("2.1.25", "2.1.23", "2.1.24"))
        for minimum, predecessor, active in cases:
            with self.subTest(minimum=minimum, predecessor=predecessor, active=active):
                lua = self.older_world("f210")
                lua.globals().minimum, lua.globals().predecessor, lua.globals().active = minimum, predecessor, active
                lua.execute(r'''
                  require("platform.target").minimum_base=minimum
                  script.active_mods.base=active
                  local event=older_event("4.7.21003",false)
                  event.mod_changes.base={old_version=predecessor,new_version=active}
                  refuse_older(event)
                ''')

    def test_unrecorded_default_first_owner_refusal_keeps_event_state_and_current_context(self):
        lua=self.world("f210")
        lua.execute(r'''
          local event=owner_event("5.0.21042");script.active_mods.base="2.1.24"
          event.mod_changes.base={old_version="2.1.23",new_version="2.1.24"}
          local before=all_frames();writes=0
          local ok,message=pcall(history.default_owner_preflight,event,nil,true)
          assert(not ok and writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
          message=tostring(message)
          assert(message:find("unrecorded default source has no qualified MIR5 producer",1,true))
          assert(message:find("previous_mir=5.0.21042",1,true)and message:find("new_mir=5.0.21012",1,true))
          assert(message:find("startup_changed=false",1,true))
          assert(message:find("saved_route=absent",1,true)and message:find("current_route=default",1,true))
          assert(message:find("active_base=2.1.24",1,true)and message:find("qualified_minimum_base=2.1.23",1,true))
          assert(message:find("base_event=base=2.1.23->2.1.24",1,true))
        ''')

    def test_473_matching_contract_transfers_current_repeated_queued_and_detached_work(self):
        cases = (
            ("f200", "4.7.20003", "base", "2.0.77"),
            ("f200", "4.7.20003", "space-age", "2.0.77"),
            ("f200", "4.7.20003", "space-age-unchanged-rows", "2.0.77"),
            ("f210", "4.7.21003", "base", "2.1.23"),
            ("f210", "4.7.20003", "base-hop", "2.1.23"),
            ("f210", "4.7.21003", "space-age", "2.1.23"),
            ("f210", "4.7.21003", "space-age-unchanged-rows", "2.1.23"),
            ("f210", "4.7.21003", "space-age", "2.1.24"),
            ("f210", "4.7.21003", "space-age-unchanged-rows", "2.1.24"),
            ("f210", "4.7.21003", "space-age", "2.1.25"),
            ("f210", "4.7.21003", "space-age-engine-patch", "2.1.25"),
            ("f210", "4.7.21003", "space-age-engine-patch-raised-minimum", "2.1.25"),
            ("f210", "4.7.21003", "space-age-engine-patch-with-addons", "2.1.25"),
            ("f210", "4.7.21003", "space-age-engine-patch-with-reported-addons", "2.1.25"),
        )
        for target, old, selection, engine_version in cases:
            with self.subTest(target=target, old=old, selection=selection, engine_version=engine_version):
                lua = self.older_world(target)
                if selection.startswith("space-age"):
                    self.enable_space_age(lua, engine_version, recycler=target == "f210")
                lua.globals().old = old
                lua.globals().selection = selection
                lua.execute(r'''
                  seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER}
                  local event=older_event(old,false)
                  local reported_addons=selection=="space-age-engine-patch-with-reported-addons"
                  local checked_addons=reported_addons or selection=="space-age-engine-patch-with-addons"
                  local raised_minimum=selection=="space-age-engine-patch-raised-minimum"
                  if raised_minimum then require("platform.target").minimum_base="2.1.25" end
                  if selection=="base-hop"then
                    event.mod_changes.base={old_version="2.0.77",new_version="2.1.23"}
                    event.mod_startup_settings_changed=true
                  elseif selection=="space-age-unchanged-rows"then
                    for name,version in pairs(script.active_mods)do
                      if name~="more-infinite-research"then
                        event.mod_changes[name]={old_version=version,new_version=version}
                      end
                    end
                  elseif selection=="space-age-engine-patch" or checked_addons or raised_minimum then
                    for name,version in pairs(script.active_mods)do
                      if name~="more-infinite-research"then
                        event.mod_changes[name]={old_version="2.1.24",new_version=version}
                      end
                    end
                  end
                  if checked_addons then
                    local addons={["Return-Inserter"]="1.0.0",["spider-launcher"]="2.9.87"}
                    if reported_addons then
                      addons.CleanedConcrete="2.1.0"
                      addons["even-distribution-fork"]="2.1.2"
                      addons.pump="2.2.6"
                      event.mod_changes.pump={old_version="2.2.6",new_version="2.2.6"}
                    end
                    for name,version in pairs(addons)do script.active_mods[name]=version end
                    event.mod_changes["Return-Inserter"]={old_version="1.0.0",new_version="1.0.0"}
                    local read=prototypes.get_history
                    prototypes.get_history=function(kind,id)
                      local result=read(kind,id)
                      if kind=="technology" and id==CANONICAL then
                        result.changed={"space-age","more-infinite-research"}
                      end
                      return result
                    end
                  end
                  local before=all_frames();writes=0;queue_writes={};progress_writes={}
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(writes==0 and same(before,all_frames()))
                  assert(plan.record.producer.kind=="published473-default")
                  assert(history.default_owner_apply(plan))
                  for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                    local current=b.current==CANONICAL and ORDINARY or b.current
                    local queue={}for i,id in ipairs(b.queue)do queue[i]=id==CANONICAL and ORDINARY or id end
                    assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                    assert(a.owner.count==b.source.count and a.owner.enabled==b.source.enabled)
                    assert(a.current==current and a.progress==b.progress and same(a.queue,queue))
                    assert(a.other_saved==b.other_saved and same(a.private,b.private)and a.bonus==b.bonus)
                  end
                  assert(player.research_queue[1].name==ORDINARY and player.research_queue[2].name==ORDINARY)
                  assert(queue_writes[player.index]==1 and queue_writes[suspended.index]==1)
                  assert(queue_writes[uninvested.index]==nil and queue_writes[detached.index]==nil)
                  local settled=all_frames();writes=0;history.default_owner_on_load()
                  local again=history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)
                  assert(not history.default_owner_apply(again)and writes==0 and same(settled,all_frames()))
                ''')

    def test_archived_46_profile_preserves_current_and_detached_worker_work(self):
        lua = self.archived_k2_worker_world(extra=False)
        lua.execute(r'''
          seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER}
          local before=all_frames();writes=0;queue_writes={};progress_writes={}
          local plan=history.default_owner_preflight(archived_event,nil,true)
          assert(writes==0 and same(before,all_frames()))
          assert(plan.record.producer.kind=="archived-default" and plan.record.producer.old_version=="4.6.21000")
          assert(history.default_owner_apply(plan))
          for _,force in pairs(game.forces)do
            local current,old=frame(force),before[force.index]
            local queue={}
            for index,id in ipairs(old.queue)do queue[index]=id==CANONICAL and ORDINARY or id end
            assert(current.owner.level==old.source.level and current.owner.count==old.source.count)
            assert(current.owner.enabled==old.source.enabled and current.owner.saved==old.source.saved)
            assert(same(current.queue,queue) and current.progress==old.progress)
            assert(current.other_saved==old.other_saved and current.bonus==old.bonus and same(current.private,old.private))
          end
          local settled=all_frames();writes=0;history.default_owner_on_load()
          local again=history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)
          assert(not history.default_owner_apply(again) and writes==0 and same(settled,all_frames()))
        ''')

    def test_473_f210_space_age_refuses_uncertain_origins_and_different_science(self):
        opponents = {
            "added DLC": 'event.mod_changes.quality={new_version="2.1.23"}',
            "removed DLC": 'script.active_mods.quality=nil; event.mod_changes.quality={old_version="2.1.23"}',
            "inactive DLC": 'script.active_mods.recycler=nil',
            "unqualified official patch": 'for name,version in pairs(script.active_mods)do if version=="2.1.23"then script.active_mods[name]="2.1.26" end end',
            "missing official patch row": '''
              for name,version in pairs(script.active_mods)do
                if version=="2.1.23"then
                  script.active_mods[name]="2.1.24"
                  event.mod_changes[name]={old_version=version,new_version="2.1.24"}
                end
              end
              event.mod_changes.recycler=nil
            ''',
            "changed startup settings": 'event.mod_startup_settings_changed=true',
            "missing worker editor history": 'script.active_mods["Return-Inserter"]="1.0.0"',
            "foreign worker edit": '''
              script.active_mods["Return-Inserter"]="1.0.0"
              local read=prototypes.get_history
              prototypes.get_history=function(kind,id)
                local result=read(kind,id)
                if kind=="technology" and id==CANONICAL then result.changed={"Return-Inserter"} end
                return result
              end
            ''',
            "changed addon with known worker editors": '''
              script.active_mods["Return-Inserter"]="1.0.0"
              event.mod_changes["Return-Inserter"]={old_version="0.9.9",new_version="1.0.0"}
              local read=prototypes.get_history
              prototypes.get_history=function(kind,id)
                local result=read(kind,id)
                if kind=="technology" and id==CANONICAL then result.changed={"space-age"} end
                return result
              end
            ''',
            "historical-only addon edit with clean current history": '''
              script.active_mods["mir-fixture-worker-source-only-price"]="0.1.0"
              local read=prototypes.get_history
              prototypes.get_history=function(kind,id)
                local result=read(kind,id)
                if kind=="technology" and id==CANONICAL then result.changed={} end
                return result
              end
            ''',
            "another version of an admitted addon": '''
              script.active_mods["Return-Inserter"]="1.0.1"
              local read=prototypes.get_history
              prototypes.get_history=function(kind,id)
                local result=read(kind,id)
                if kind=="technology" and id==CANONICAL then result.changed={} end
                return result
              end
            ''',
            "added mod": '''
              script.active_mods.observer="1.0.0"
              event.mod_changes.observer={new_version="1.0.0"}
            ''',
            "removed mod": 'event.mod_changes.observer={old_version="1.0.0"}',
            "missing science": 'table.remove(packs)',
            "wrong science": 'packs[6].name="metallurgic-science-pack"',
            "wrong science amount": 'packs[6].amount=2',
            "duplicated science": 'packs[6].name=packs[5].name',
        }
        for case, change in opponents.items():
            with self.subTest(case=case):
                lua = self.older_world("f210")
                self.enable_space_age(lua)
                lua.execute(r'''
                  seed_owner()
                  local event=older_event("4.7.21003",false)
                  local packs=prototypes.technology[CANONICAL].research_unit_ingredients
                ''' + change + r'''
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_preflight,event,nil,true))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                ''')

    def test_473_f200_space_age_only_admits_unchanged_official_2077(self):
        opponents = {
            "added quality": 'event.mod_changes.quality={new_version="2.0.77"}',
            "removed rails": 'script.active_mods["elevated-rails"]=nil; event.mod_changes["elevated-rails"]={old_version="2.0.77"}',
            "recycler present": 'script.active_mods.recycler="2.0.77"',
            "recycler event": 'event.mod_changes.recycler={old_version="2.0.77",new_version="2.0.77"}',
            "unrelated existing mod": 'script.active_mods.observer="1.0.0"',
            "unqualified patch": '''
              for name,version in pairs(script.active_mods)do
                if version=="2.0.77"then script.active_mods[name]="2.0.78" end
              end
            ''',
            "changed startup settings": 'event.mod_startup_settings_changed=true',
            "wrong science": 'prototypes.technology[CANONICAL].research_unit_ingredients[6].name="metallurgic-science-pack"',
        }
        for case, change in opponents.items():
            with self.subTest(case=case):
                lua = self.older_world("f200")
                self.enable_space_age(lua, "2.0.77", recycler=False)
                lua.execute(r'''
                  seed_owner()
                  local event=older_event("4.7.20003",false)
                ''' + change + r'''
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_preflight,event,nil,true))
                  assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                ''')

    def test_473_supported_same_edition_patches_preserve_the_complete_default_work(self):
        # A minimum engine version is a floor. An unchanged supported patch or
        # same-family patch update does not change this exact worker contract.
        for target, old, cases in (
                ("f200", "4.7.20003", (("2.0.78", None), ("2.0.78", "2.0.77"),
                                       ("2.0.78", "2.0.78"), ("2.0.79", "2.0.78"))),
                ("f210", "4.7.21003", (("2.1.24", None), ("2.1.24", "2.1.23"),
                                       ("2.1.24", "2.1.24"), ("2.1.25", "2.1.24")))):
            for current_base, previous_base in cases:
                with self.subTest(target=target, current=current_base, previous=previous_base):
                    lua=self.older_world(target);lua.globals().old=old
                    lua.globals().current_base=current_base;lua.globals().previous_base=previous_base
                    lua.execute(r'''
                      seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER}
                      foreign_bonus[detached.index]=73
                      script.active_mods.base=current_base;local event=older_event(old,false)
                      if previous_base then event.mod_changes.base={old_version=previous_base,new_version=current_base}end
                      local before=all_frames();writes=0;queue_writes={};progress_writes={}
                      local plan=history.default_owner_preflight(event,nil,true)
                      assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
                      assert(plan.record.producer.kind=="published473-default"and plan.record.producer.old_version==old)
                      assert(history.default_owner_apply(plan))
                      for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                        local queue={}for i,id in ipairs(b.queue)do queue[i]=id==CANONICAL and ORDINARY or id end
                        assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                        assert(a.owner.count==b.source.count and a.owner.enabled==b.source.enabled
                          and a.owner.visible==b.source.visible and not a.owner.researched)
                        assert(a.current==(b.current==CANONICAL and ORDINARY or b.current)
                          and a.progress==b.progress and same(a.queue,queue))
                        assert(a.bonus==foreign_bonus[f.index]+b.source.level-4 and a.bonus==b.bonus)
                        assert(a.other_saved==b.other_saved and same(a.private,b.private))
                      end
                      assert(player.research_progress==.375 and player.research_queue[2].name==ORDINARY)
                      assert(suspended.technologies[ORDINARY].saved_progress==.27)
                      assert(detached.technologies[ORDINARY].saved_progress==.23)
                      assert(queue_writes[player.index]==1 and queue_writes[suspended.index]==1)
                      assert(queue_writes[uninvested.index]==nil and queue_writes[detached.index]==nil)
                      local saved=storage[OWNER_KEY];local settled=all_frames();writes=0
                      local original_game,original_prototypes=game,prototypes
                      game=setmetatable({}, {__index=function()error("cold native game read")end})
                      prototypes=setmetatable({}, {__index=function()error("cold prototype read")end})
                      for i=1,2 do package.loaded["runtime.worker_robot_storage"]=nil
                        history=require("runtime.worker_robot_storage");history.default_owner_on_load()
                        assert(storage[OWNER_KEY]==saved and writes==0)
                      end
                      game,prototypes=original_game,original_prototypes;history.configure(0,true)
                      local again=history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)
                      assert(not history.default_owner_apply(again)and writes==0 and same(settled,all_frames()))
                    ''')

    def test_501_observer_exception_remains_empty_only_on_supported_same_family_patches(self):
        for previous_base in (None, "2.0.77", "2.0.78"):
            for paid in (False, True):
                with self.subTest(previous=previous_base, paid=paid):
                    lua=self.older_world();lua.globals().previous_base=previous_base;lua.globals().paid=paid
                    lua.execute(r'''
                      player.research_queue={OTHER};player.research_progress=.42
                      if paid then detached.technologies[CANONICAL].level=5 end
                      script.active_mods.base="2.0.78";local event=older_event("5.0.20001",true)
                      if previous_base then event.mod_changes.base={old_version=previous_base,new_version="2.0.78"}end
                      if paid then refuse_older(event);return end
                      local before=all_frames();writes=0;queue_writes={};progress_writes={}
                      local plan=older_plan(event);assert(writes==0 and same(before,all_frames()))
                      assert(plan.record.producer.kind=="older-mir501-empty-default")
                      assert(history.apply_default_owner_transfer(plan))
                      for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                        assert(a.owner.level==4 and not a.owner.researched and a.bonus==20 and a.bonus==b.bonus)
                        assert(a.current==b.current and a.progress==b.progress and same(a.queue,b.queue))
                      end
                      assert(next(queue_writes)==nil and next(progress_writes)==nil)
                    ''')

    def test_older_patch_admission_retains_engine_event_and_worker_authority_refusals(self):
        opponents=("current-floor", "current-family", "current-malformed", "current-leading-zero",
            "old-floor", "downgrade", "old-family", "old-malformed", "base-new", "base-new-only",
            "base-old-only", "base-not-table", "changes-not-table", "startup-missing", "startup-not-boolean",
            "startup-changed", "previous-mod", "removed-mod", "updated-mod", "official-mod",
            "foreign-source", "clamped-source", "provider", "cap", "private-work", "unqualified-472")
        for target, old in (("f200", "4.7.20003"), ("f210", "4.7.21003"), ("f200", "5.0.20001")):
            # The501 exception proves every force is empty and already allows
            # a selected cap. Only the473 paid-work contract requires max0.
            cases=opponents if old!="5.0.20001"else tuple(case for case in opponents if case!="cap")
            for opponent in cases:
                with self.subTest(target=target, old=old, opponent=opponent):
                    lua=self.older_world(target);lua.globals().old=old;lua.globals().opponent=opponent
                    lua.execute(r'''
                      if old~="5.0.20001"then seed_owner()end
                      local f200=package_family=="f200";local current=f200 and"2.0.78"or"2.1.24"
                      local floor=f200 and"2.0.77"or"2.1.23";local below=f200 and"2.0.76"or"2.1.22"
                      local higher=f200 and"2.0.79"or"2.1.25";local other=f200 and"2.1.23"or"2.0.77"
                      script.active_mods.base=current;local event=older_event(old,true);local route=nil
                      event.mod_changes.base={old_version=floor,new_version=current}
                      if opponent=="current-floor"then script.active_mods.base=below
                        event.mod_changes.base={old_version=below,new_version=below}
                      elseif opponent=="current-family"then script.active_mods.base=other
                        event.mod_changes.base={old_version=other,new_version=other}
                      elseif opponent=="current-malformed"then script.active_mods.base=current..".0";event.mod_changes.base=nil
                      elseif opponent=="current-leading-zero"then script.active_mods.base=f200 and"2.0.078"or"2.1.024";event.mod_changes.base=nil
                      elseif opponent=="old-floor"then event.mod_changes.base.old_version=below
                      elseif opponent=="downgrade"then event.mod_changes.base.old_version=higher
                      elseif opponent=="old-family"then event.mod_changes.base.old_version=other
                      elseif opponent=="old-malformed"then event.mod_changes.base.old_version=floor..".0"
                      elseif opponent=="base-new"then event.mod_changes.base.new_version=higher
                      elseif opponent=="base-new-only"then event.mod_changes.base.old_version=nil
                      elseif opponent=="base-old-only"then event.mod_changes.base.new_version=nil
                      elseif opponent=="base-not-table"then event.mod_changes.base=true
                      elseif opponent=="changes-not-table"then event.mod_changes=true
                      elseif opponent=="startup-missing"then event.mod_startup_settings_changed=nil
                      elseif opponent=="startup-not-boolean"then event.mod_startup_settings_changed="false"
                      elseif opponent=="startup-changed"then event.mod_startup_settings_changed=true
                      elseif opponent=="previous-mod"then script.active_mods.foreign="1"
                      elseif opponent=="removed-mod"then event.mod_changes.foreign={old_version="1"}
                      elseif opponent=="updated-mod"then script.active_mods.foreign="2";event.mod_changes.foreign={old_version="1",new_version="2"}
                      elseif opponent=="official-mod"then script.active_mods.quality=current;event.mod_changes.quality={old_version=floor,new_version=current}
                      elseif opponent=="foreign-source"then creators[CANONICAL]="foreign"
                      elseif opponent=="clamped-source"then prototypes.technology[CANONICAL].max_level=4
                      elseif opponent=="provider"then add_provider(7);route=provider_route(7)
                      elseif opponent=="cap"then history.configure(10,true)
                      elseif opponent=="private-work"then detached.technologies[ID].saved_progress=.1
                      elseif opponent=="unqualified-472"then event.mod_changes["more-infinite-research"].old_version=f200 and"4.7.20002"or"4.7.21002"
                        script.active_mods["space-exploration"]="0.7.57";history.configure(10,true)end
                      refuse_older(event,route)
                    ''')

    def test_one_force_paid_501_and_pending_501_work_refuse_before_writes(self):
        for old, opponents in (("5.0.20001", (
                'detached.technologies[CANONICAL].level=5',
                'detached.technologies[CANONICAL].researched=true')),):
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
            'event.mod_startup_settings_changed=true;paid_idle()',
            'event.mod_changes["more-infinite-research"].new_version="5.0.20013"',
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
        for target, old in (("f210","5.0.21042"),("f210","4.7.21002"),("f200","5.0.20043"),("f200","4.7.20002")):
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

    def test_473_requires_the_historical_work_vector_even_when_current_pair_agrees(self):
        mutations=(
            'p.research_unit_count_formula="100*2^(L-4)"',
            'p.research_unit_energy=1800',
            'p.ignore_tech_cost_multiplier=true',
            'p.research_unit_ingredients[5]=nil',
            'p.research_unit_ingredients[5].amount=2',
            'p.research_unit_ingredients[5].name="space-science-pack"',
            'p.research_unit_ingredients[5].name="automation-science-pack"')
        for target,old in (("f200","4.7.20003"),("f210","4.7.21003")):
            for mutation in mutations:
                with self.subTest(target=target,mutation=mutation):
                    lua=self.older_world(target);lua.globals().old=old
                    lua.execute('seed_owner();for _,id in ipairs({CANONICAL,ORDINARY,ID})do '+
                        'local p=prototypes.technology[id];'+mutation+' end;refuse_older(older_event(old,false))')

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
              -- Published12 used this narrower producer. Its saved meaning and
              -- storage-only reader must survive the new full-work admission.
              if old=="4.7.20003"then storage[OWNER_KEY].producer.kind=kind end
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
        lua = build_full_default_provider_handover_world(LuaRuntime, target=target, source_root=ROOT / "source")
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

    def test_adding_solar_restores_only_owned_retirement_and_debit_flags(self):
        for debit_reenabled in (False, True):
            with self.subTest(debit_reenabled=debit_reenabled):
                lua = self.world()
                lua.globals().debit_reenabled = debit_reenabled
                lua.execute(r'''
                  full_source(1,true);reenable_paid_heads()
                  local retired=player.technologies[CANONICAL]
                  retired.enabled=true;retired.visible_when_disabled=true
                  player.technologies[HEAD].enabled=debit_reenabled
                  local event=default_config()
                  event.mod_changes["solar-productivity"]={new_version="3.0.0"}
                  script.active_mods["solar-productivity"]="3.0.0"
                  local before=all_frames();local ownership=copy(storage[OWNER_KEY])
                  writes=0;queue_writes={};progress_writes={}
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(writes==0 and same(before,all_frames()))
                  assert(history.default_owner_apply(plan))
                  before[player.index].source.enabled=false
                  for _,row in pairs(before)do row.debit.enabled=false end
                  assert(same(before,all_frames())and same(ownership,storage[OWNER_KEY]))
                  assert(next(queue_writes)==nil and next(progress_writes)==nil)
                  writes=0
                  local again=history.default_owner_preflight(event,nil,true)
                  assert(not again.changed and not history.default_owner_apply(again) and writes==0)
                ''')

    def test_configuration_cannot_retake_a_foreign_retirement_or_discard_work(self):
        for opponent in ('local flags=storage[OWNER_KEY].forces[player.index].retired_flags;'
                         'flags.enabled=false;flags.disabled_by_mir=false',
                         'retired.saved_progress=.1',
                         'retired.level=6',
                         'player.research_queue={CANONICAL,ORDINARY,OTHER}',
                         'player.technologies[HEAD].level=4'):
            with self.subTest(opponent=opponent):
                lua = self.world()
                lua.execute(r'''
                  full_source(1,true);reenable_paid_heads()
                  local retired=player.technologies[CANONICAL];retired.enabled=true
                ''' + opponent + r'''
                  local before=all_frames();writes=0
                  assert(not pcall(history.default_owner_preflight,default_config(),nil,true))
                  assert(writes==0 and same(before,all_frames()))
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
        return build_default_native_owner_world(LuaRuntime, target=target, source_root=ROOT / "source")

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

    def test_empty_unchanged_and_published11_added_qol_accept_but_changed_prior_selection_refuses(self):
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
                  -- Published11 authored infinite C4 even when capped or disabled.
                  -- Its proved prior Base+MIR selection and empty native frames
                  -- admit this addition without inferring a previous work contract.
                  if opponent=="unchanged"or opponent=="added"then
                    local kind=opponent=="added"and"published511-empty-default"or"unchanged-mir5-default"
                    assert(ok and plan.record.producer.kind==kind)
                    assert(history.apply_default_owner_transfer(plan))
                    for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                      assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                      assert(a.owner.enabled==b.source.enabled and a.owner.visible==b.source.visible)
                      assert(a.bonus==b.bonus and a.progress==b.progress and a.other_saved==b.other_saved)
                      assert(same(a.queue,b.queue)and same(a.private,b.private)and same(a.debit,b.debit))
                    end
                  else assert(not ok and storage[OWNER_KEY]==nil)end
                ''')

    def test_unrecorded_mod_selection_refusal_reports_only_the_rejecting_tuple_without_writes(self):
        for target in ("f200", "f210"):
            for opponent in ("added", "removed", "updated", "active-proxy", "false-zero", "malformed"):
                with self.subTest(target=target, opponent=opponent):
                    lua=self.world(target);lua.globals().opponent=opponent
                    lua.execute(r'''
                      for _,f in pairs(game.forces)do local c=f.technologies[CANONICAL]
                        c.level=4;c.researched=false;c.saved_progress=0;f.research_queue={};f.research_progress=0
                      end
                      local name="sage-\1"..string.rep("x",100)
                      local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                      script.active_mods["unrelated-unchanged"]="7.0"
                      event.mod_changes["unrelated-unchanged"]={old_version="7.0",new_version="7.0"}
                      if opponent=="added"then
                        event.mod_changes[name]={new_version="new\2"};script.active_mods[name]="new\2"
                      elseif opponent=="removed"then
                        event.mod_changes[name]={old_version="old\3"};script.active_mods[name]=nil
                      elseif opponent=="updated" or opponent=="active-proxy"then
                        event.mod_changes[name]={old_version="old\4",new_version="new\5"};script.active_mods[name]="new\5"
                      elseif opponent=="false-zero"then
                        event.mod_changes[name]={old_version=false,new_version=0};script.active_mods[name]=false
                      else
                        event.mod_changes[name]=setmetatable({}, {__index=function()error("rejecting row metamethod invoked")end})
                        script.active_mods[name]="active\6"
                      end
                      if opponent=="active-proxy"then
                        local original=script.active_mods
                        script.active_mods=setmetatable({}, {__index=function(_,key)return original[key]end})
                      end
                      local before=all_frames();writes=0
                      local ok,message=pcall(history.plan_default_owner_transfer,event,nil,false)
                      assert(not ok and tostring(message):find("default transfer requires the unchanged mod selection",1,true))
                      assert(not tostring(message):find("rejecting row metamethod invoked",1,true))
                      assert(message:find("cannot be repaired by /mir-worker-storage-recovery prepare",1,true))
                      assert(message:find("a supported upgrade may establish native ownership automatically",1,true))
                      assert(message:find("restore the previous mod selection and original save",1,true))
                      assert(not message:find("Only if that copy has MIR-owned default infinite worker4",1,true))
                      assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                      assert(message:find("previous_mir="..event.mod_changes["more-infinite-research"].old_version,1,true))
                      assert(message:find("new_mir="..script.active_mods["more-infinite-research"],1,true))
                      assert(message:find("startup_changed=false",1,true) and message:find("saved_route=absent",1,true)
                        and message:find("current_route=default",1,true))
                      local escaped_name="sage-\\x01"..string.rep("x",90)
                      assert(message:find("rejecting_mod_name="..escaped_name,1,true))
                      assert(not message:find("unrelated-unchanged",1,true))
                      if opponent=="added"then
                        assert(message:find("rejecting_old_version=absent",1,true))
                        assert(message:find("rejecting_new_version=new\\x02",1,true))
                        assert(message:find("rejecting_active_version=new\\x02",1,true))
                      elseif opponent=="removed"then
                        assert(message:find("rejecting_old_version=old\\x03",1,true))
                        assert(message:find("rejecting_new_version=absent",1,true))
                        assert(message:find("rejecting_active_version=absent",1,true))
                      elseif opponent=="updated" or opponent=="active-proxy"then
                        assert(message:find("rejecting_old_version=old\\x04",1,true))
                        assert(message:find("rejecting_new_version=new\\x05",1,true))
                        assert(message:find("rejecting_active_version=new\\x05",1,true))
                      elseif opponent=="false-zero"then
                        assert(message:find("rejecting_old_version=false",1,true))
                        assert(message:find("rejecting_new_version=0",1,true))
                        assert(message:find("rejecting_active_version=false",1,true))
                      else
                        assert(message:find("rejecting_old_version=malformed-table",1,true))
                        assert(message:find("rejecting_new_version=malformed-table",1,true))
                        assert(message:find("rejecting_active_version=active\\x06",1,true))
                      end
                    ''')

    def test_named_malformed_rejected_row_does_not_invoke_context_metamethods(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua=self.world(target)
                lua.execute(r'''
                  for _,f in pairs(game.forces)do local c=f.technologies[CANONICAL]
                    c.level=4;c.researched=false;c.saved_progress=0;f.research_queue={};f.research_progress=0
                  end
                  local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                  event.mod_changes.secretas=setmetatable({}, {__index=function()error("named rejecting row metamethod invoked")end})
                  script.active_mods.secretas="1.0"
                  local before=all_frames();writes=0
                  local ok,message=pcall(history.plan_default_owner_transfer,event,nil,false)
                  assert(not ok and tostring(message):find("default transfer requires the unchanged mod selection",1,true))
                  assert(not tostring(message):find("named rejecting row metamethod invoked",1,true))
                  assert(message:find("secretas=malformed-table",1,true))
                  assert(message:find("rejecting_mod_name=secretas",1,true))
                  assert(message:find("rejecting_old_version=malformed-table",1,true))
                  assert(message:find("rejecting_new_version=malformed-table",1,true))
                  assert(message:find("rejecting_active_version=1.0",1,true))
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                ''')


class WorkerRecordedDefaultModChangeTests(unittest.TestCase):
    """A saved MIR route plus surviving native work is not a whole-modpack lock."""

    def world(self, target="f210"):
        return build_default_native_owner_world(LuaRuntime, target=target, source_root=ROOT / "source")

    def test_recorded_default_refusals_do_not_invent_a_rejected_mod(self):
        for target in ("f200", "f210"):
            for bad_entry in (True, {"old_version": "1.2.2", "new_version": "1.2.4"}):
                with self.subTest(target=target, bad_entry=bad_entry):
                    lua = self.world(target)
                    lua.globals().bad_entry = lua.table_from(bad_entry) if isinstance(bad_entry, dict) else bad_entry
                    lua.execute(r'''
                      seed_owner()
                      storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                      script.active_mods.qol="1.2.3"
                      local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                      event.mod_changes.qol=bad_entry
                      local before=all_frames();writes=0
                      local ok,message=pcall(history.plan_default_owner_transfer,event,nil,false)
                      assert(not ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                      message=tostring(message)
                      assert(message:find("current_route=default",1,true))
                      assert(not message:find("rejecting_mod_name=",1,true))
                    ''')

    def test_default_origin_reuses_the_already_observed_native_route(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner()
                  storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                  local observed=prototypes.get_history;local canonical_reads=0
                  prototypes.get_history=function(kind,name)
                    if name==CANONICAL then
                      canonical_reads=canonical_reads+1
                      assert(canonical_reads==1,"diagnostic repeated the native route lookup")
                    end
                    return observed(kind,name)
                  end
                  local event=owner_event(package_family=="f200"and"5.0.20042"or"5.0.21042")
                  local before=all_frames();writes=0
                  local ok,message=pcall(history.plan_default_owner_transfer,event,nil,false)
                  assert(not ok and writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                  message=tostring(message)
                  assert(canonical_reads==1)
                  assert(message:find("recorded default source has an inconsistent producer event",1,true))
                  assert(message:find("current_route=default",1,true))
                  assert(message:find("keep the protected original COPY",1,true))
                  assert(not message:find("/mir-worker-storage-recovery prepare",1,true))
                ''')

    def test_recorded_default_accepts_later_same_edition_mir5_producers(self):
        for target in ("f200", "f210"):
            for patch in ("12", "22"):
                with self.subTest(target=target, patch=patch):
                    lua = self.world(target)
                    lua.globals().prior_patch = patch
                    lua.execute(r'''
                      seed_owner()
                      storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                      local metadata = require("platform.target")
                      local prefix = metadata.distribution_version:sub(1,-3)
                      local prior, current = prefix..prior_patch, prefix.."23"
                      metadata.distribution_version = current
                      script.active_mods["more-infinite-research"] = current
                      script.active_mods["credit-provider"] = "0.3.0"
                      local event = {mod_startup_settings_changed=false,mod_changes={
                        ["more-infinite-research"]={old_version=prior,new_version=current},
                        ["credit-provider"]={old_version="0.2.0",new_version="0.3.0"},
                      }}
                      local before=all_frames();writes=0
                      local plan=history.plan_default_owner_transfer(event,nil,false)
                      assert(writes==0 and same(before,all_frames()))
                      assert(history.apply_default_owner_transfer(plan))
                      local producer=storage[OWNER_KEY].producer
                      assert(producer.kind=="recorded-default" and producer.old_version==prior and producer.new_version==current)
                      assert(player.current_research.name==ORDINARY and player.research_progress==.375)
                      assert(player.research_queue[2].name==OTHER and suspended.current_research.name==OTHER)
                      assert(suspended.technologies[ORDINARY].saved_progress==.27 and detached.technologies[ORDINARY].saved_progress==.23)
                      for _,force in pairs(game.forces) do assert(frame(force).bonus==before[force.index].bonus) end
                      history.default_owner_on_load()
                      local after=all_frames();writes=0
                      local again=history.default_owner_preflight(event,nil,true)
                      history.default_owner_apply(again)
                      assert(writes==0 and same(after,all_frames()))
                    ''')

    def test_recorded_default_preserves_paid_and_pending_work_across_consistent_mod_changes(self):
        for target in ("f200", "f210"):
            for change in ("added", "removed", "updated"):
                with self.subTest(target=target, change=change):
                    lua = self.world(target)
                    lua.globals().change_kind = change
                    lua.execute(r'''
                      seed_owner()
                      storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                      uninvested.technologies[CANONICAL].enabled=true
                      uninvested.research_queue={CANONICAL};uninvested.research_progress=.37
                      script.active_mods["cosmetic-example"]="1.2.3"
                      local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                      event.mod_changes["cosmetic-example"]={old_version="1.2.2",new_version="1.2.3"}
                      if change_kind=="added"then event.mod_changes["cosmetic-example"].old_version=nil
                      elseif change_kind=="removed"then
                        event.mod_changes["cosmetic-example"].new_version=nil;script.active_mods["cosmetic-example"]=nil
                      end
                      local before=all_frames();writes=0
                      local plan=history.plan_default_owner_transfer(event,nil,false)
                      assert(writes==0 and same(before,all_frames()))
                      assert(history.apply_default_owner_transfer(plan))
                      local state=storage[OWNER_KEY]
                      assert(state.schema==3 and state.producer.kind=="recorded-default")
                      for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                        assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                        assert(a.owner.enabled==b.source.enabled and a.owner.visible==b.source.visible)
                        assert(a.bonus==b.bonus and a.other_saved==b.other_saved and same(a.private,b.private))
                      end
                      assert(player.current_research.name==ORDINARY and player.research_progress==.375 and player.research_queue[2].name==OTHER)
                      assert(uninvested.current_research.name==ORDINARY and uninvested.research_progress==.37)
                      assert(suspended.current_research.name==OTHER and suspended.research_progress==.42 and suspended.research_queue[2].name==ORDINARY)
                      assert(suspended.technologies[ORDINARY].saved_progress==.27 and detached.technologies[ORDINARY].saved_progress==.23)
                      local accepted=all_frames();writes=0
                      local again=history.default_owner_preflight(event,nil,true)
                      history.default_owner_apply(again)
                      assert(same(accepted,all_frames()) and writes==0)
                    ''')

    def test_recorded_default_keeps_the_existing_base_only_engine_hop_boundary(self):
        for removed in ("quality", "space-age", "old-helper"):
            with self.subTest(removed=removed):
                lua = self.world("f210")
                lua.globals().removed = removed
                lua.execute(r'''
                  seed_owner()
                  storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                  local event=owner_event("5.0.20011")
                  event.mod_changes.base={old_version="2.0.77",new_version="2.1.23"}
                  event.mod_changes[removed]={old_version=removed=="old-helper"and"1.2.3"or"2.0.77"}
                  local before=all_frames();writes=0
                  assert(not pcall(history.plan_default_owner_transfer,event,nil,false))
                  assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                ''')

    def test_recorded_default_does_not_admit_inconsistent_events_or_unsafe_native_state(self):
        for target in ("f200", "f210"):
            for opponent in ("active-mismatch", "removed-active", "both-absent", "old-type", "new-type",
                             "empty-old", "empty-new", "entry-type", "entry-metatable", "name-type",
                             "unknown-mir", "first-install", "external", "absent-route", "malformed-route",
                             "private-contract", "foreign-tail", "official-mismatch"):
                with self.subTest(target=target, opponent=opponent):
                    lua = self.world(target)
                    lua.globals().opponent = opponent
                    lua.execute(r'''
                      seed_owner()
                      storage.mir_worker_storage_route={schema=2,kind="route",current={kind="default"}}
                      script.active_mods.qol="1.2.3"
                      local event=owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011")
                      local entry={old_version="1.2.2",new_version="1.2.3"};event.mod_changes.qol=entry
                      if opponent=="active-mismatch"then script.active_mods.qol="1.2.4"
                      elseif opponent=="removed-active"then entry.new_version=nil
                      elseif opponent=="both-absent"then entry.old_version=nil;entry.new_version=nil;script.active_mods.qol=nil
                      elseif opponent=="old-type"then entry.old_version=12
                      elseif opponent=="new-type"then entry.new_version=12;script.active_mods.qol=12
                      elseif opponent=="empty-old"then entry.old_version=""
                      elseif opponent=="empty-new"then entry.new_version="";script.active_mods.qol=""
                      elseif opponent=="entry-type"then event.mod_changes.qol=true
                      elseif opponent=="entry-metatable"then setmetatable(entry,{})
                      elseif opponent=="name-type"then event.mod_changes[7]=entry;script.active_mods[7]="1.2.3"
                      elseif opponent=="unknown-mir"then event.mod_changes["more-infinite-research"].old_version="5.0.99999"
                      elseif opponent=="first-install"then event.mod_changes["more-infinite-research"].old_version=nil
                      elseif opponent=="external"then storage.mir_worker_storage_route.current={kind="external",provider="old-foreign"}
                      elseif opponent=="absent-route"then storage.mir_worker_storage_route.current={kind="absent"}
                      elseif opponent=="malformed-route"then storage.mir_worker_storage_route.current.extra=true
                      elseif opponent=="private-contract"then prototypes.technology[ORDINARY].research_unit_energy=999
                      elseif opponent=="foreign-tail"then prototypes.technology["worker-robots-storage-5"]={}
                      else script.active_mods.quality="different-engine"end
                      local before=all_frames();writes=0
                      assert(not pcall(history.plan_default_owner_transfer,event,nil,false))
                      assert(writes==0 and same(before,all_frames()) and storage[OWNER_KEY]==nil)
                    ''')


class WorkerDefaultEditionContinuityTests(unittest.TestCase):
    """Exact existing Base hop and stable historical producer facts, host only."""

    def world(self, target="f210"):
        return build_full_default_provider_handover_world(LuaRuntime, target=target, source_root=ROOT / "source")

    def test_exact_473_and_recorded_modern_base_hop_preserve_all_native_work(self):
        for old in ("4.7.20003","5.0.20009","5.0.20010","5.0.20011"):
            for changed in (False,True):
                lua=build_older_default_admission_world(LuaRuntime, target="f210", source_root=ROOT / "source") if old.startswith("4.7")else self.world()
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
                  assert(producer.kind==(old=="4.7.20003"and"published473-default"or"recorded-default"))
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

    def test_provider_addition_after_qualified_engine_hop_keeps_f200_provenance(self):
        for scalar in (0, 2):
            with self.subTest(scalar=scalar):
                lua=self.world("f200");lua.globals().scalar=scalar
                lua.execute(r'''
                  full_source(scalar,true);local producer=copy(storage[OWNER_KEY].producer);local before=all_frames()
                  local target=package.loaded["platform.target"]
                  target.id="f210";target.minimum_base="2.1.23";target.distribution_version="5.0.21016"
                  for _,id in ipairs{CANONICAL,ORDINARY,HEAD,ID}do
                    for _,effect in ipairs(prototypes.technology[id].effects)do effect.hidden=false end
                  end
                  script.active_mods.base="2.1.23";script.active_mods["more-infinite-research"]="5.0.21016"
                  local hop={mod_startup_settings_changed=true,mod_changes={base={old_version="2.0.77",new_version="2.1.23"},
                    ["more-infinite-research"]={old_version="5.0.20012",new_version="5.0.21016"}}}
                  assert(not history.default_owner_apply(history.default_owner_preflight(hop,nil,true)))
                  assert(writes==0 and same(before,all_frames())and same(producer,storage[OWNER_KEY].producer))
                  target.distribution_version="5.0.21017";script.active_mods["more-infinite-research"]="5.0.21017"
                  finite_entry(1);local event=provider_event()
                  event.mod_changes["more-infinite-research"]={old_version="5.0.21016",new_version="5.0.21017"}
                  before=all_frames();local plan,legacy=delegate(event)
                  assert(writes==0 and same(before,all_frames()))
                  history.default_owner_apply(plan);history.apply(legacy)
                  assert(same(producer,storage[OWNER_KEY].producer)and producer.new_version=="5.0.20012")
                  for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                    assert(a.bonus==b.bonus and a.private.level==b.owner.level and a.private.saved==b.owner.saved)
                    assert(a.progress==b.progress and a.other_saved==b.other_saved)
                  end
                ''')

    def test_hop_is_not_a_new_mod_unknown_engine_downgrade_or_unrecorded_adoption(self):
        opponents=("old-base","new-base","missing-base","old-package","new-mod","unchanged-qol","space-age","private-work","foreign-source","unrecorded")
        for old in ("4.7.20003","5.0.20011"):
            for opponent in opponents:
                lua=build_older_default_admission_world(LuaRuntime, target="f210", source_root=ROOT / "source") if old.startswith("4.7")else self.world()
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
        lua=build_full_default_provider_handover_world(LuaRuntime, target=target, source_root=ROOT / "source")
        lua.execute('defines={events={on_research_queued=25,on_research_started=26,on_research_cancelled=27}}')
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

    def test_pending_setter_observation_is_read_only_then_tick_enforces_quota_and_finish(self):
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
              assert(history.on_research_event({research=f.technologies[OTHER],name=26,tick=100}))
              assert(#f.research_queue==3 and history.prepared_queue_pending())
              history.on_prepared_queue_tick({tick=100})
              assert(#f.research_queue==3 and quota.queue_tick==100)
              history.on_prepared_queue_tick({tick=101})
              assert(#f.research_queue==2 and f.research_queue[2].name==ID and quota.limit==8)
              assert(not history.prepared_queue_pending() and quota.queue_tick==nil)
              mt.__newindex=write;mt.__index=read
              f.research_queue={OTHER};f.research_progress=.23;f.technologies[ID].level=9
              assert(history.on_research_event({research=f.technologies[ID],by_script=false},true))
              assert(not quota.pending and not f.technologies[ID].enabled and f.current_research.name==OTHER and f.research_progress==.23)
            """)

    def test_start_inside_queue_replacement_keeps_the_private_tail_and_survives_reload(self):
        for target in ("f200","f210"):
            lua=self.world(target);lua.execute(r"""
              full_source(1,true);finite_entry(1);handover()
              local f=player;local p=f.technologies[ID]
              local record=storage.mir_worker_storage_route.forces[f.index]
              local limit=record.limit
              -- Factorio starts the new head before appending the old private row.
              f.research_progress=0;p.saved_progress=0
              f.research_queue={OTHER};f.research_progress=.42
              writes=0
              assert(history.on_research_event({research=f.technologies[OTHER],name=26,tick=312}))
              assert(writes==0 and p.enabled and record.pending and record.limit==limit)
              f.research_queue={OTHER,ID};f.research_progress=.42
              local world=game;game=nil;history.on_load();game=world
              assert(history.prepared_queue_pending())
              history.on_prepared_queue_tick({tick=313})
              assert(not history.prepared_queue_pending() and p.enabled and record.pending and record.limit==limit)
              assert(f.research_queue[1].name==OTHER and f.research_queue[2].name==ID and f.research_progress==.42)
            """)

    def test_real_cancellation_retires_and_configuration_restores_only_that_owned_flag(self):
        for opponent in (False,True):
            lua=self.world();lua.globals().opponent=opponent;lua.execute(r"""
              full_source(1,true);finite_entry(1);handover()
              local f=player;local p=f.technologies[ID]
              f.research_progress=0;p.saved_progress=0
              f.research_queue={OTHER};f.research_progress=.42
              local record=storage.mir_worker_storage_route.forces[f.index]
              assert(history.on_research_event({force=f,research={[ID]=1},name=27,tick=312}))
              assert(record.pending and p.enabled)
              history.on_prepared_queue_tick({tick=313})
              assert(not record.pending and not p.enabled)
              local cargo,level=f.worker_robots_storage_bonus,p.level
              prototypes.technology[ID].enabled=false
              p.enabled=true -- Native configuration can re-enable an earned prerequisite.
              writes=0
              local plan=history.preflight({mod_startup_settings_changed=false,mod_changes={}},provider_route(5))
              assert(writes==0 and plan.retired[f.index]==p)
              if opponent then
                p.saved_progress=.25;writes=0
                assert(not pcall(history.apply,plan) and writes==0 and p.enabled and p.saved_progress==.25)
              else
                history.apply(plan)
                assert(not p.enabled and p.level==level and f.worker_robots_storage_bonus==cargo)
                assert(f.current_research.name==OTHER and f.research_progress==.42)
              end
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
        return build_default_native_owner_world(LuaRuntime, target=target, source_root=ROOT / "source")

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
        return build_full_default_provider_handover_world(LuaRuntime, target=target, source_root=ROOT / "source")

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
    'Public00ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“11 default native stream and complete schema3 handover authority.'

    def world(self, target="f210"):
        return build_full_default_provider_handover_world(LuaRuntime, target=target, source_root=ROOT / "source")

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


    def test_new_selection_keeps_only_proved_501_and_published11_empty_origins(self):
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
                  elseif patch==11 then
                    -- The immutable published11 Base+MIR producer retained
                    -- infinite C4 under cap/enable settings; no force has work.
                    assert(ok and plan.record.producer.kind=="published511-empty-default")
                    assert(history.default_owner_apply(plan))
                    for _,f in pairs(game.forces)do local a,b=frame(f),before[f.index]
                      assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                      assert(a.owner.enabled==b.source.enabled and a.owner.visible==b.source.visible)
                      assert(a.bonus==b.bonus and a.progress==b.progress and a.other_saved==b.other_saved)
                      assert(same(a.queue,b.queue)and same(a.private,b.private)and same(a.debit,b.debit))
                    end
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

def borrowed_test_worlds(source):
    """Find world construction delegated to another test case."""
    tree = ast.parse(source)
    test_classes = {node.name for node in tree.body if isinstance(node, ast.ClassDef)}
    borrowed = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Attribute) or node.attr not in ("world", "older_world"):
            continue
        owner = node.value.func if isinstance(node.value, ast.Call) else node.value
        if isinstance(owner, ast.Name) and owner.id in test_classes:
            borrowed.append((node.lineno, ast.get_source_segment(source, node)))
    return borrowed


class WorkerWorldConstructionTests(unittest.TestCase):
    def test_worker_worlds_do_not_borrow_test_case_construction(self):
        self.assertEqual(borrowed_test_worlds(Path(__file__).read_text(encoding="utf-8")), [])

    def test_borrow_guard_rejects_calls_aliases_and_constructed_cases(self):
        for expression in (
            "WorkerDefaultNativeOwnerTransferTests.world",
            "WorkerDefaultNativeOwnerTransferTests.world(self, target)",
            "WorkerFullDefaultProviderHandoverTests.world(self, target)",
            "WorkerOlderDefaultAdmissionTests().older_world('f210')",
        ):
            with self.subTest(expression=expression):
                source = (
                    "class WorkerDefaultNativeOwnerTransferTests: pass\n"
                    "class WorkerFullDefaultProviderHandoverTests: pass\n"
                    "class WorkerOlderDefaultAdmissionTests: pass\n"
                    "class Consumer:\n    world = " + expression + "\n"
                )
                self.assertEqual(len(borrowed_test_worlds(source)), 1)

    def test_builders_use_explicit_inputs_and_return_independent_worlds(self):
        builders = (
            build_default_native_owner_world,
            build_full_default_provider_handover_world,
            build_older_default_admission_world,
        )
        source_root = ROOT / "source" / "runtime" / ".."
        missing_root = ROOT / "tests" / ".missing-worker-world-source"
        self.assertFalse(missing_root.exists())
        for builder in builders:
            for target, base in (("f200", "2.0.77"), ("f210", "2.1.23")):
                with self.subTest(builder=builder.__name__, target=target):
                    calls = []

                    def factory(**options):
                        calls.append(options)
                        return LuaRuntime(**options)

                    first = builder(factory, target=target, source_root=source_root)
                    first.execute("storage.fixture_probe=71; package.loaded['platform.target'].minimum_base='changed'")
                    second = builder(factory, target=target, source_root=source_root)
                    self.assertIsNot(first, second)
                    self.assertEqual(calls, [{"unpack_returned_tuples": True}] * 2)
                    self.assertEqual(second.eval("player_root"), source_root.as_posix())
                    self.assertEqual(second.eval("package_family"), target)
                    self.assertEqual(second.eval("require('platform.target').minimum_base"), base)
                    self.assertIsNone(second.eval("storage.fixture_probe"))
            with self.subTest(builder=builder.__name__, missing_source=True):
                with self.assertRaisesRegex(Exception, r"module 'runtime\.worker_robot_storage' not found"):
                    builder(LuaRuntime, target="f210", source_root=missing_root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

"""Authentic published11 prepared-default transfer; host state, not native acceptance."""
import argparse
from pathlib import Path
import sys
import unittest

import test_worker_storage_inherited_origin as origin
import test_bootstrap as bootstrap_fixture

ROOT = Path(__file__).resolve().parents[1]


class WorkerPreparedDefaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        origin.WorkerInheritedOriginTests.setUpClass.__func__(cls)

    world = origin.WorkerInheritedOriginTests.world

    def prepared(self, target):
        origin.LuaRuntime = LuaRuntime
        lua = self.world(target)
        lua.execute(r'''
          seed_owner();local old=inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
          assert(old.prepare(nil));candidate_reader();writes=0
        ''')
        return lua

    def test_published_preparation_transfers_the_complete_work_once(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                origin.LuaRuntime = LuaRuntime
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner();player.research_queue={CANONICAL,CANONICAL,OTHER}
                  uninvested.technologies[CANONICAL].enabled=true
                  local before=all_frames()
                  local old=inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
                  assert(old.prepare(nil));local prepared=storage.mir_worker_storage_route
                  candidate_reader();writes=0
                  local prepared_frames=all_frames()
                  local plan=history.default_owner_preflight(owner_event(published_version),nil,true)
                  assert(writes==0 and same(prepared_frames,all_frames()))
                  assert(history.default_owner_apply(plan))
                  assert(storage.mir_worker_storage_route==nil)
                  assert(storage[OWNER_KEY].producer.kind=="prepared-default")
                  for _,force in pairs(game.forces)do local a,b=frame(force),before[force.index]
                    assert(a.owner.level==b.source.level and not a.owner.researched)
                    assert(a.owner.saved==b.source.saved and a.owner.count==b.source.count)
                    assert(a.owner.enabled==b.source.enabled and a.owner.visible==b.source.visible)
                    assert(a.bonus==b.bonus and a.progress==b.progress and a.other_saved==b.other_saved)
                    local queue={}for i,name in ipairs(b.queue)do queue[i]=name==CANONICAL and ORDINARY or name end
                    assert(same(a.queue,queue)and a.current==(b.current==CANONICAL and ORDINARY or b.current))
                    assert(a.private.level==4 and not a.private.researched and a.private.saved==0
                      and not a.private.enabled and not a.private.visible)
                    assert(a.source.level==(b.source.level>=5 and 5 or 4)and not a.source.enabled)
                  end
                  assert(not prepared.forces[uninvested.index].enabled and uninvested.technologies[ORDINARY].enabled)
                  local settled=all_frames();local record=storage[OWNER_KEY];writes=0
                  local native_game,native_prototypes=game,prototypes
                  game=setmetatable({},{__index=function()error("load read native game")end})
                  prototypes=setmetatable({},{__index=function()error("load read prototypes")end})
                  for _=1,2 do history.on_load();history.default_owner_on_load()
                    assert(storage[OWNER_KEY]==record and storage.mir_worker_storage_route==nil and writes==0)end
                  game,prototypes=native_game,native_prototypes
                  local again=history.default_owner_preflight({mod_startup_settings_changed=false,mod_changes={}},nil,true)
                  assert(not history.default_owner_apply(again)and same(settled,all_frames())and writes==0)
                ''')

    def test_invalid_prepared_contracts_and_last_force_refuse_before_any_write(self):
        opponents = (
            'storage.mir_worker_storage_route.contract=storage.mir_worker_storage_route.contract..":changed"',
            'creators[ID]="foreign-owner"',
            'creators[ORDINARY]="foreign-owner"',
            'prototypes.technology[ID].research_unit_energy=1',
            'prototypes.technology[CANONICAL].research_unit_count_formula="2*L"',
            'history.configure(10,true)',
            'history.configure(0,false)',
            'storage.mir_worker_storage_route.forces[detached.index]=nil',
            'storage.mir_worker_storage_route.forces[99]=copy(storage.mir_worker_storage_route.forces[1])',
            'storage.mir_worker_storage_route.forces[detached.index].limit=3',
            'detached.technologies[ID].visible_when_disabled=not detached.technologies[ID].visible_when_disabled',
            'detached.technologies[ORDINARY].level=5',
            'detached.technologies[HEAD].level=5',
            'detached.technologies[CANONICAL].saved_progress=.01',
            'player.technologies[CANONICAL].enabled=false',
        )
        for target in ("f200", "f210"):
            for opponent in opponents:
                with self.subTest(target=target, opponent=opponent):
                    lua = self.prepared(target)
                    lua.execute(opponent + r'''
                      local before=all_frames();local state=storage.mir_worker_storage_route;writes=0
                      assert(not pcall(history.default_owner_preflight,owner_event(published_version),nil,true))
                      assert(writes==0 and same(before,all_frames())and storage.mir_worker_storage_route==state
                        and storage[OWNER_KEY]==nil)
                    ''')

    def test_mutation_after_preflight_cannot_partially_transfer_an_earlier_force(self):
        changes = (
            'detached.technologies[ID].saved_progress=.24',
            'detached.technologies[CANONICAL].enabled=not detached.technologies[CANONICAL].enabled',
            'storage.mir_worker_storage_route.forces[detached.index].limit=storage.mir_worker_storage_route.forces[detached.index].limit+1',
            'plan.prepared_snapshot.forces[detached.index].limit=plan.prepared_snapshot.forces[detached.index].limit+1',
            'foreign_bonus[detached.index]=74',
        )
        for target in ("f200", "f210"):
            for change in changes:
                with self.subTest(target=target, change=change):
                    lua = self.prepared(target)
                    lua.execute(r'''
                      local plan=history.default_owner_preflight(owner_event(published_version),nil,true)
                    ''' + change + r'''
                      local before=all_frames();local state=storage.mir_worker_storage_route;writes=0
                      assert(not pcall(history.default_owner_apply,plan))
                      assert(writes==0 and same(before,all_frames())and storage.mir_worker_storage_route==state
                        and storage[OWNER_KEY]==nil)
                    ''')

    def test_stale_legacy_quota_cannot_be_reinstalled_after_transfer(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.prepared(target)
                lua.execute(r'''
                  local event=owner_event(published_version)
                  local legacy=history.preflight(event,nil)
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(history.default_owner_apply(plan))
                  local settled=all_frames();local record=storage[OWNER_KEY];writes=0
                  assert(not pcall(history.apply,legacy))
                  assert(storage.mir_worker_storage_route==nil and storage[OWNER_KEY]==record
                    and writes==0 and same(settled,all_frames()))
                ''')

    def test_published11_preparation_requires_its_actual_package_change_event_before_writes(self):
        for target in ("f200", "f210"):
            for opponent in ("old10", "no-package-change", "other-edition"):
                with self.subTest(target=target, opponent=opponent):
                    lua=self.prepared(target);lua.globals().opponent=opponent
                    lua.execute(r'''
                      local event=owner_event(published_version)
                      if opponent=="old10"then
                        event.mod_changes["more-infinite-research"].old_version=package_family=="f200"and"5.0.20010"or"5.0.21010"
                      elseif opponent=="no-package-change"then event.mod_changes={}
                      else event.mod_changes["more-infinite-research"].old_version=package_family=="f200"and"5.0.21011"or"5.0.20011"end
                      local before=all_frames();local prepared=storage.mir_worker_storage_route;writes=0
                      local ok,message=pcall(history.default_owner_preflight,event,nil,true)
                      assert(not ok,"accepted a prepared witness under a different or missing producer event")
                      assert(tostring(message):find("MIR worker storage history",1,true))
                      assert(writes==0 and same(before,all_frames())and storage.mir_worker_storage_route==prepared
                        and storage[OWNER_KEY]==nil)
                    ''')

    def test_persisted_prepared_owner_cannot_claim_old10_on_storage_only_load(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua=self.prepared(target)
                lua.execute(r'''
                  assert(history.default_owner_apply(history.default_owner_preflight(owner_event(published_version),nil,true)))
                  storage[OWNER_KEY].producer.old_version=package_family=="f200"and"5.0.20010"or"5.0.21010"
                  writes=0
                  game=setmetatable({},{__index=function()error("load accessed native game")end})
                  prototypes=setmetatable({},{__index=function()error("load accessed native prototypes")end})
                  local ok,message=pcall(history.default_owner_on_load)
                  assert(not ok,"accepted a persisted prepared owner attributed to the wrong published producer")
                  assert(tostring(message):find("unknown default native%-owner producer")and writes==0)
                ''')

    def test_unrelated_changes_do_not_erase_authenticated_work_or_foreign_disablement(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.prepared(target)
                lua.execute(r'''
                  local before=all_frames();local event=owner_event(published_version)
                  script.active_mods.observer="2";event.mod_changes.observer={old_version="1",new_version="2"}
                  event.mod_startup_settings_changed=true
                  local plan=history.default_owner_preflight(event,nil,true)
                  assert(history.default_owner_apply(plan))
                  assert(not uninvested.technologies[ORDINARY].enabled)
                  for _,force in pairs(game.forces)do local a,b=frame(force),before[force.index]
                    assert(a.bonus==b.bonus and a.progress==b.progress and a.other_saved==b.other_saved)
                    assert(a.owner.enabled==b.source.enabled)
                  end
                ''')

    def test_prepared_above_cap_earnings_and_cap_restoration_right_follow_the_owner(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                origin.LuaRuntime = LuaRuntime
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner();uninvested.technologies[CANONICAL].level=11
                  uninvested.technologies[CANONICAL].enabled=false
                  local old=inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
                  old.configure(10,true);assert(old.prepare(nil));candidate_reader();history.configure(10,true)
                  local right={disabled=true,visible_when_disabled=false}
                  storage.mir_caps={schema=1,owned_disabled={[uninvested.index]={[CANONICAL]=right}}}
                  local values=require("runtime.configuration")
                  values.worker_robots_speed_max_level=0
                  for _,row in ipairs(require("runtime.catalogue").declared())do
                    if values.streams[row.family]==nil then values.streams[row.family]={enabled=false,max_level=0}end
                  end
                  values.streams["worker-robots-storage"]={enabled=true,max_level=10}
                  local lifecycle=require("runtime.lifecycle")
                  local before=all_frames();local plan=history.default_owner_preflight(owner_event(published_version),nil,true)
                  local caps=lifecycle.preflight_worker_storage_split_caps(plan)
                  assert(storage.mir_caps.owned_disabled[uninvested.index][CANONICAL]==right)
                  assert(history.default_owner_apply(plan));lifecycle.apply_worker_storage_split_caps(caps)
                  assert(uninvested.technologies[ORDINARY].level==11 and not uninvested.technologies[ORDINARY].enabled)
                  assert(uninvested.worker_robots_storage_bonus==before[uninvested.index].bonus)
                  local rights=storage.mir_caps.owned_disabled[uninvested.index]
                  assert(rights[CANONICAL]==nil and rights[ORDINARY]==right)
                ''')

    def test_actual_bootstrap_consumes_prepared_default_without_issuing_a_legacy_quota(self):
        # Callback routing is an actual bootstrap control. The authentic old11
        # native-frame host controls above separately exercise the transfer.
        bootstrap_fixture.LuaRuntime = LuaRuntime
        for invalid_caps in (False, True):
            with self.subTest(invalid_caps=invalid_caps):
                fixture = bootstrap_fixture.BootstrapTests();fixture.setUp()
                fixture.lua.globals().invalid_caps = invalid_caps
                fixture.lua.execute(r'''
                  install_modules(false);install_runtime()
                  local catalogue=require("runtime.catalogue")
                  catalogue.worker_default_split=function()return true end
                  local worker=require("runtime.worker_robot_storage")
                  local lifecycle=require("runtime.lifecycle")
                  local plan={kind="default-native-owner-transfer",prepared_default=true,changed=true}
                  local order={}
                  worker.default_owner_preflight=function(event,route,split)
                    assert(split and route==nil);order[#order+1]="owner-preflight";return plan
                  end
                  worker.preflight=function()error("must not issue a retiring legacy quota")end
                  worker.apply=function()error("must not reinstall a retiring legacy quota")end
                  worker.default_owner_apply=function(value)
                    assert(value==plan);order[#order+1]="owner-apply";return true
                  end
                  lifecycle.preflight_worker_storage_split_caps=function(value)
                    assert(value==plan);order[#order+1]="caps-preflight"
                    if invalid_caps then error("invalid cap rights")end
                    return "rights"
                  end
                  lifecycle.apply_worker_storage_split_caps=function(value)
                    assert(value=="rights");order[#order+1]="caps-apply"
                  end
                  package.preload["runtime.worker_robot_storage"]=function()return worker end
                  package.preload["runtime.lifecycle"]=function()return lifecycle end
                  load_control()
                  local ok,message=pcall(handlers.configuration,{mod_startup_settings_changed=false,mod_changes={}})
                  if invalid_caps then
                    assert(not ok and tostring(message):find("invalid cap rights",1,true))
                    assert(table.concat(order,",")=="owner-preflight,caps-preflight")
                    assert(lifecycle_calls.configuration==nil)
                  else
                    assert(ok,message)
                    assert(table.concat(order,",")=="owner-preflight,caps-preflight,owner-apply,caps-apply")
                    assert(lifecycle_calls.configuration~=nil)
                  end
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

"""Published worker-history producer controls; no native or reporter-save claim.

An existing save passing through 5.0.11 is not equivalent to a new 5.0.11
world. Execute the immutable published reader against the existing native
doubles, rather than manufacturing its route marker in successor setup.
"""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import unittest

from worker_storage_default_world import (
    build_default_native_owner_world,
    install_published_default_reader,
)


ROOT = Path(__file__).resolve().parents[1]
PUBLISHED = "29da2a250efa9235c9bde0f5bf9f4a9013f990a3"  # v5.0.11
PUBLISHED_MEMBERS = {
    "runtime.worker_robot_storage": (
        "source/runtime/worker_robot_storage.lua",
        "DFF0B2145DC22CB263EE95A4DA87F04D771CF8B7E9809F77BBF5BC821D5F621A",
    ),
    "research.worker_storage_recovery": (
        "source/research/worker_storage_recovery.lua",
        "80FEB07F5C4D4D722D5ECD7BD2CCFF8C6768A11791CBDBBC855CF844328E1B93",
    ),
    "runtime.caps": (
        "source/runtime/caps.lua",
        "A50E7D56082E8454FA40FA0DB0CD7DA33B5441FAA7A39AABAD9438A77E5A3C52",
    ),
}


def published_source(path, digest):
    env = dict(os.environ, GIT_NO_LAZY_FETCH="1")
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(ROOT), "show", PUBLISHED + ":" + path],
            stderr=subprocess.PIPE, env=env,
        )
    except subprocess.CalledProcessError as error:
        raise AssertionError(
            f"Fetch exact published worker source {PUBLISHED} before host controls"
        ) from error
    if hashlib.sha256(raw).hexdigest().upper() != digest:
        raise AssertionError(f"Published worker source differs: {PUBLISHED}:{path}")
    return raw.decode("utf-8")


def published_modules():
    return {
        name: published_source(path, digest)
        for name, (path, digest) in PUBLISHED_MEMBERS.items()
    }


class WorkerInheritedOriginTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.published = published_modules()

    def world(self, target):
        lua = build_default_native_owner_world(
            LuaRuntime, target=target, source_root=ROOT / "source"
        )
        return install_published_default_reader(lua, historical_sources=self.published)

    def test_fresh_init_records_default_but_inherited_configuration_does_not(self):
        for target in ("f200", "f210"):
            for origin in ("4.7", "5.0"):
                with self.subTest(target=target, origin=origin):
                    lua = self.world(target)
                    lua.globals().older = origin + (".20002" if target == "f200" else ".21002")
                    lua.execute(r'''
                      seed_owner();local before=all_frames()
                      inherited_configuration(older)
                      assert(storage.mir_worker_storage_route==nil)
                      assert(same(before,all_frames()),"published upgrade changed native work")
                      assert(player.technologies[CANONICAL].level==8)
                      assert(player.research_progress==.375)
                      assert(suspended.technologies[CANONICAL].saved_progress==.27)
                      assert(detached.technologies[CANONICAL].saved_progress==.23)
                    ''')
            with self.subTest(target=target, origin="fresh-init"):
                lua = self.world(target)
                lua.execute(r'''
                  local reader=published_reader();local before=all_frames()
                  reader.on_init(nil)
                  local marker=storage.mir_worker_storage_route
                  assert(marker.schema==2 and marker.kind=="route"and marker.current.kind=="default")
                  assert(same(before,all_frames()))
                ''')

    def test_inherited_absence_survives_old11_reparse_and_configuration(self):
        for target in ("f200", "f210"):
            for operation in ("added", "removed", "updated"):
                with self.subTest(target=target, operation=operation):
                    lua = self.world(target)
                    lua.globals().operation = operation
                    lua.execute(r'''
                      seed_owner();local before=all_frames()
                      inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
                      local reader=published_reader();reader.on_load()
                      local change={old_version="1",new_version="2"};script.active_mods.observer="2"
                      if operation=="added"then change.old_version=nil end
                      if operation=="removed"then change.new_version=nil;script.active_mods.observer=nil end
                      reader.apply(reader.preflight({mod_startup_settings_changed=false,
                        mod_changes={observer=change}},nil))
                      assert(storage.mir_worker_storage_route==nil and same(before,all_frames()))
                      reader=published_reader();reader.on_load()
                      assert(storage.mir_worker_storage_route==nil and same(before,all_frames()))
                    ''')

    def test_current_unchanged_upgrade_preserves_the_actual_inherited_shape(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner();local before=all_frames()
                  inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
                  assert(storage.mir_worker_storage_route==nil)
                  candidate_reader();writes=0
                  local event=owner_event(published_version)
                  assert(event.mod_startup_settings_changed==false)
                  assert(player.technologies[CANONICAL].level>4 and player.research_progress>0)
                  local plan=history.plan_default_owner_transfer(event,nil,false)
                  assert(writes==0 and same(before,all_frames()))
                  assert(plan.record.producer.kind=="unchanged-mir5-default")
                  assert(history.apply_default_owner_transfer(plan))
                  for _,force in pairs(game.forces)do local a,b=frame(force),before[force.index]
                    assert(a.owner.level==b.source.level and a.owner.saved==b.source.saved)
                    assert(a.owner.count==b.source.count and a.bonus==b.bonus)
                    assert(a.progress==b.progress and a.other_saved==b.other_saved)
                    local queue=copy(b.queue)
                    for i,name in ipairs(queue)do if name==CANONICAL then queue[i]=ORDINARY end end
                    assert(same(a.queue,queue))
                  end
                  assert(storage.mir_worker_storage_route==nil)
                ''')

    def test_published_preparation_records_observed_work_without_an_init_marker(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner();local before=all_frames()
                  local reader=inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
                  assert(storage.mir_worker_storage_route==nil)
                  assert(reader.prepare(nil))
                  local state=storage.mir_worker_storage_route
                  assert(state.schema==2 and state.kind=="prepared"and state.current.kind=="default")
                  for _,force in pairs(game.forces)do local a,b=frame(force),before[force.index]
                    assert(a.private.level==b.source.level and a.private.saved==b.source.saved)
                    assert(a.private.count==b.source.count and a.bonus==b.bonus)
                    assert(a.source.level==4 and a.source.saved==0)
                    assert(a.progress==b.progress and a.other_saved==b.other_saved)
                    local queue=copy(b.queue)
                    for i,name in ipairs(queue)do if name==CANONICAL then queue[i]=ID end end
                    assert(same(a.queue,queue))
                    assert(state.forces[force.index].next_level==b.source.level)
                  end
                  local prepared=all_frames();reader=published_reader();reader.on_load()
                  assert(storage.mir_worker_storage_route==state and same(prepared,all_frames()))
                ''')

    def test_old_preparation_rejects_a_foreign_current_owner_without_writes(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute(r'''
                  seed_owner()
                  local reader=inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
                  creators[CANONICAL]="foreign-worker-provider"
                  local before=all_frames();writes=0
                  assert(not pcall(reader.prepare,nil))
                  assert(storage.mir_worker_storage_route==nil and writes==0 and same(before,all_frames()))
                ''')

    def uninvested_world(self, target):
        lua = self.world(target)
        lua.execute(r'''
          -- Execute the published producer; do not manufacture a missing marker.
          inherited_configuration(package_family=="f200"and"4.7.20002"or"4.7.21002")
          assert(storage.mir_worker_storage_route==nil)
          candidate_reader()
          event=owner_event(published_version);event.mod_startup_settings_changed=true
          player.research_queue={OTHER};player.research_progress=.375
          suspended.technologies[OTHER].saved_progress=.27
          detached.research_queue={OTHER};detached.research_progress=.625
          storage.unrelated_credits={paid=17,partial=.21}
          writes=0;queue_writes={};progress_writes={}
          function refuse_without_writes(operation)
            local before,records=all_frames(),copy(storage)
            writes=0;queue_writes={};progress_writes={}
            local ok=pcall(operation)
            assert(not ok,"unsafe uninvested admission")
            assert(writes==0 and next(queue_writes)==nil and next(progress_writes)==nil)
            assert(same(before,all_frames())and same(records,storage))
          end
        ''')
        return lua

    def test_published11_empty_settings_change_preserves_work_flags_and_cap_rights(self):
        for target in ("f200", "f210"):
            for scalar in (0, 2):
                with self.subTest(target=target, scalar=scalar):
                    lua = self.uninvested_world(target)
                    lua.globals().scalar = scalar
                    lua.execute(r'''
                      set_reward(scalar);history.configure(10,false)
                      for _,id in ipairs{CANONICAL,ORDINARY,ID}do
                        prototypes.technology[id].research_unit_energy=7200
                        prototypes.technology[id].research_unit_count_formula="100*2^(L-4)"
                      end
                      uninvested.technologies[CANONICAL].enabled=false
                      uninvested.technologies[CANONICAL].visible_when_disabled=true
                      local right={disabled=false,visible_when_disabled=true,discovery_enabled=false}
                      storage.mir_caps={schema=1,owned_disabled={[uninvested.index]={[CANONICAL]=right}}}
                      local values=require("runtime.configuration")
                      values.worker_robots_speed_max_level=0
                      for _,row in ipairs(require("runtime.catalogue").declared())do
                        if values.streams[row.family]==nil then values.streams[row.family]={enabled=false,max_level=0}end
                      end
                      values.streams["worker-robots-storage"]={enabled=false,max_level=10}
                      local lifecycle=require("runtime.lifecycle")
                      local before,credits=all_frames(),copy(storage.unrelated_credits)
                      writes=0;queue_writes={};progress_writes={}
                      local plan=history.default_owner_preflight(event,nil,true)
                      local caps=lifecycle.preflight_worker_storage_split_caps(plan)
                      assert(plan.record.producer.kind=="published511-empty-default")
                      assert(writes==0 and same(before,all_frames()))
                      assert(history.default_owner_apply(plan));lifecycle.apply_worker_storage_split_caps(caps)
                      for _,force in pairs(game.forces)do local a,b=frame(force),before[force.index]
                        assert(a.source.level==4 and not a.source.enabled and a.source.saved==0)
                        assert(a.owner.level==4 and not a.owner.researched and a.owner.saved==0)
                        assert(a.owner.enabled==b.source.enabled and a.owner.visible==b.source.visible)
                        assert(same(a.private,b.private)and same(a.debit,b.debit))
                        assert(a.bonus==20 and a.bonus==b.bonus and a.other_saved==b.other_saved)
                        assert(a.progress==b.progress and a.current==b.current and same(a.queue,b.queue))
                      end
                      local rights=storage.mir_caps.owned_disabled[uninvested.index]
                      assert(rights[CANONICAL]==nil and rights[ORDINARY]==right)
                      assert(right.disabled==false and right.visible_when_disabled and right.discovery_enabled==false)
                      assert(same(storage.unrelated_credits,credits))
                      assert(next(queue_writes)==nil and next(progress_writes)==nil)
                      local after=all_frames();writes=0
                      local saved_game=game;game=nil
                      history.default_owner_on_load();history.default_owner_on_load()
                      game=saved_game
                      assert(writes==0 and same(after,all_frames()))
                      assert(not history.default_owner_apply(history.default_owner_preflight(event,nil,true)))
                      assert(writes==0 and same(after,all_frames()))
                    ''')

    def test_published11_empty_reconstructs_prior_base_selection_from_added_mods(self):
        for target in ("f200", "f210"):
            for settings_changed in (False, True):
                with self.subTest(target=target, settings_changed=settings_changed):
                    lua = self.uninvested_world(target)
                    lua.globals().settings_changed = settings_changed
                    lua.execute(r'''
                      event.mod_startup_settings_changed=settings_changed
                      script.active_mods.observer="2"
                      event.mod_changes.observer={new_version="2"}
                      local previous=script.active_mods.base
                      script.active_mods.base=package_family=="f200"and"2.0.78"or"2.1.24"
                      event.mod_changes.base={old_version=previous,new_version=script.active_mods.base}
                      local before=all_frames();writes=0
                      local plan=history.plan_default_owner_transfer(event,nil,false)
                      assert(plan.record.producer.kind=="published511-empty-default")
                      assert(writes==0 and same(before,all_frames()))
                      assert(history.apply_default_owner_transfer(plan))
                      for _,force in pairs(game.forces)do local a,b=frame(force),before[force.index]
                        assert(a.bonus==b.bonus and a.progress==b.progress and a.other_saved==b.other_saved)
                        assert(a.current==b.current and same(a.queue,b.queue))
                        assert(a.owner.level==4 and not a.owner.researched and a.owner.saved==0)
                      end
                      assert(next(queue_writes)==nil and next(progress_writes)==nil)
                    ''')

    def test_false_flag_addition_requires_empty_work_and_proved_prior_selection(self):
        opponents = (
            'detached.technologies[CANONICAL].level=5',
            'detached.technologies[CANONICAL].saved_progress=.01',
            'player.research_queue={CANONICAL};player.research_progress=0',
            'suspended.research_queue={OTHER,CANONICAL}',
            'event.mod_changes.base={new_version=script.active_mods.base}',
            'script.active_mods["space-age"]=script.active_mods.base;event.mod_changes["space-age"]={new_version=script.active_mods.base}',
            'event.mod_changes.observer=setmetatable({new_version="2"},{})',
            'script.active_mods.previous="1"',
            'script.active_mods.previous="2";event.mod_changes.previous={old_version="1",new_version="2"}',
            'event.mod_changes.previous={old_version="1"}',
        )
        for target in ("f200", "f210"):
            for opponent in opponents:
                with self.subTest(target=target, opponent=opponent):
                    lua = self.uninvested_world(target)
                    lua.execute(r'''
                      event.mod_startup_settings_changed=false
                      script.active_mods.observer="2";event.mod_changes.observer={new_version="2"}
                    ''' + opponent + r'''
                      refuse_without_writes(function()history.plan_default_owner_transfer(event,nil,false)end)
                    ''')

    def test_published11_empty_accepts_disabled_infinite_prototypes_without_enabling_them(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.uninvested_world(target)
                lua.execute(r'''
                  history.configure(4,false)
                  prototypes.technology[CANONICAL].enabled=false
                  prototypes.technology[ORDINARY].enabled=false
                  for _,force in pairs(game.forces)do
                    force.technologies[CANONICAL].enabled=false
                    force.technologies[ORDINARY].enabled=false
                  end
                  local before=all_frames();writes=0
                  local plan=history.plan_default_owner_transfer(event,nil,false)
                  assert(writes==0 and same(before,all_frames()))
                  assert(history.apply_default_owner_transfer(plan))
                  for _,force in pairs(game.forces)do
                    assert(not force.technologies[CANONICAL].enabled)
                    assert(not force.technologies[ORDINARY].enabled)
                    assert(force.worker_robots_storage_bonus==before[force.index].bonus)
                  end
                ''')

    def test_published11_empty_rejects_any_worker_investment_or_contract_ambiguity(self):
        opponents = (
            'detached.technologies[CANONICAL].level=5',
            'set_reward(0);detached.technologies[CANONICAL].level=5',
            'detached.technologies[CANONICAL].researched=true',
            'detached.technologies[CANONICAL].saved_progress=.01',
            'player.research_queue={CANONICAL};player.research_progress=0',
            'suspended.research_queue={OTHER,CANONICAL}',
            'detached.technologies[ID].level=5',
            'detached.technologies[ID].saved_progress=.01',
            'detached.technologies[ORDINARY].saved_progress=.01',
            'detached.technologies[ORDINARY].level=5',
            'detached.technologies[HEAD].researched=true',
            'detached.technologies[HEAD].enabled=true',
            'creators[CANONICAL]="foreign"',
            'creators[ORDINARY]="foreign"',
            'creators[ID]="foreign"',
            'prototypes.technology["worker-robots-storage-9"]={}',
            'prototypes.technology[CANONICAL].max_level=4',
            'prototypes.technology[ORDINARY].effects[1].modifier=2',
            'prototypes.technology[ORDINARY].research_unit_energy=1',
        )
        for target in ("f200", "f210"):
            for opponent in opponents:
                with self.subTest(target=target, opponent=opponent):
                    lua = self.uninvested_world(target)
                    lua.execute(opponent + r'''
                      refuse_without_writes(function()history.plan_default_owner_transfer(event,nil,false)end)
                    ''')

    def test_published11_empty_rejects_unproved_prior_selection_and_producer(self):
        opponents = (
            'script.active_mods.observer="1"',
            'script.active_mods.observer="2";event.mod_changes.observer={old_version="1",new_version="2"}',
            'event.mod_changes.observer={old_version="1"}',
            'script.active_mods.observer="2";event.mod_changes.observer={new_version="1"}',
            'event.mod_changes.observer={new_version="2"}',
            'event.mod_changes.observer=setmetatable({new_version="2"},{})',
            'script.active_mods["space-age"]=script.active_mods.base;event.mod_changes["space-age"]={new_version=script.active_mods.base}',
            'event.mod_changes["more-infinite-research"].old_version=package_family=="f200"and"5.0.20010"or"5.0.21010"',
            'event.mod_changes["more-infinite-research"].old_version=package_family=="f200"and"5.0.21011"or"5.0.20011"',
            'event.mod_changes["more-infinite-research"].old_version=nil',
            'event.mod_changes["more-infinite-research"].new_version="unknown"',
            'event.mod_changes["more-infinite-research"]=nil',
            'event.mod_startup_settings_changed=nil',
            'event.mod_startup_settings_changed="true"',
            'event.mod_changes.base={old_version="2.0.76",new_version=script.active_mods.base}',
            'event.mod_changes.base={old_version=package_family=="f200"and"2.0.78"or"2.1.24",new_version=script.active_mods.base}',
        )
        for target in ("f200", "f210"):
            for opponent in opponents:
                with self.subTest(target=target, opponent=opponent):
                    lua = self.uninvested_world(target)
                    lua.execute(opponent + r'''
                      refuse_without_writes(function()history.plan_default_owner_transfer(event,nil,false)end)
                    ''')

    def test_published11_empty_rechecks_last_force_contract_and_settings_before_writes(self):
        for opponent in (
            'detached.technologies[CANONICAL].saved_progress=.01',
            'detached.technologies[CANONICAL].enabled=false',
            'foreign_bonus[4]=21',
            'history.configure(10,false)',
            'prototypes.technology[ORDINARY].research_unit_energy=1',
            'script.active_mods.observer="1"',
        ):
            with self.subTest(opponent=opponent):
                lua = self.uninvested_world("f210")
                lua.execute('plan=history.plan_default_owner_transfer(event,nil,false);' + opponent + r'''
                  refuse_without_writes(function()history.apply_default_owner_transfer(plan)end)
                ''')

    def test_published11_empty_producer_record_cannot_claim_a_different_origin(self):
        for opponent in (
            'storage[OWNER_KEY].producer.old_version="5.0.21010"',
            'storage[OWNER_KEY].producer.old_version="5.0.20011"',
            'storage[OWNER_KEY].producer.new_version="5.0.21010"',
        ):
            with self.subTest(opponent=opponent):
                lua = self.uninvested_world("f210")
                lua.execute(r'''
                  assert(history.apply_default_owner_transfer(history.plan_default_owner_transfer(event,nil,false)))
                ''' + opponent + r'''
                  refuse_without_writes(function()history.default_owner_on_load()end)
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

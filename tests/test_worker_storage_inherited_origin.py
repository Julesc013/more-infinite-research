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

import test_worker_storage_history as history_fixture


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


class WorkerInheritedOriginTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.published = {
            name: published_source(path, digest)
            for name, (path, digest) in PUBLISHED_MEMBERS.items()
        }

    def world(self, target):
        history_fixture.LuaRuntime = LuaRuntime
        lua = history_fixture.WorkerDefaultNativeOwnerTransferTests.world(self, target)
        lua.globals().published_modules = lua.table_from(self.published)
        lua.execute(r'''
          candidate_history=history
          candidate_modules={}
          for name in pairs(published_modules)do candidate_modules[name]=package.loaded[name]end
          local target=require("platform.target")
          candidate_version=target.distribution_version
          published_version=package_family=="f200"and"5.0.20011"or"5.0.21011"
          function published_reader()
            target.distribution_version=published_version
            script.active_mods["more-infinite-research"]=published_version
            package.loaded["runtime.caps"]=assert(load(published_modules["runtime.caps"]))()
            package.loaded["research.worker_storage_recovery"]=assert(load(published_modules["research.worker_storage_recovery"]))()
            return assert(load(published_modules["runtime.worker_robot_storage"]))()
          end
          function inherited_configuration(old)
            local reader=published_reader()
            reader.on_load()
            local event={mod_startup_settings_changed=false,mod_changes={
              ["more-infinite-research"]={old_version=old,new_version=published_version}}}
            reader.apply(reader.preflight(event,nil))
            return reader
          end
          function candidate_reader()
            target.distribution_version=candidate_version
            script.active_mods["more-infinite-research"]=candidate_version
            for name,module in pairs(candidate_modules)do package.loaded[name]=module end
            history=candidate_history
          end
        ''')
        return lua

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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

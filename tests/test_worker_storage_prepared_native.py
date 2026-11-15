"""Independent fixed prepared-default native actor controls; no engine acceptance."""
import argparse
import json
from pathlib import Path
import sys
import unittest

import test_worker_storage_default_native as common

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/worker-storage-default-native"


class PreparedNativeActorTests(unittest.TestCase):
    def setUp(self):
        common.LuaRuntime = LuaRuntime
        common.WorkerStorageDefaultNativeTests.setUp(self)
        self.lua.globals().prepared_source = (FIXTURE / "prepared_native.lua").read_text()
        self.lua.execute('prepared=assert(load(prepared_source))()')

    def test_exact_stage_tuples_reject_other_packages_and_engines(self):
        self.lua.execute(r'''
          for _,engine in ipairs{"2.0.77","2.1.23","2.1.24"}do
            local prefix=engine=="2.0.77"and"200"or"210"
            assert(prepared.tuple(engine,"4.7."..prefix.."02")=="origin")
            assert(prepared.tuple(engine,"5.0."..prefix.."11")=="inherited")
            assert(prepared.tuple(engine,"5.0."..prefix.."15")=="successor")
            for _,wrong in ipairs{"5.0."..prefix.."14","5.0."..prefix.."12","4.7."..prefix.."03"}do
              assert(not pcall(prepared.tuple,engine,wrong))
            end
          end
          assert(not pcall(prepared.tuple,"2.1.25","5.0.21015"))
        ''')

    def test_inherited_adds_only_the_new_pristine_holder(self):
        self.lua.execute(r'''
          local before=source_frame();for _,f in ipairs(before)do f.rows[actor.ids.private]=nil end
          local original=deep(before);local after=prepared.expected_inherited(before)
          actor.same(before,original)
          for i,f in ipairs(after)do
            actor.same(f.rows[actor.ids.private],{name=actor.ids.private,level=4,researched=false,
              enabled=false,visible=false,saved=0,count=675})
            f.rows[actor.ids.private]=nil;actor.same(f,original[i])
          end
          original[1].rows[actor.ids.private]={}
          assert(not pcall(prepared.expected_inherited,original))
        ''')

    def test_observed_global_settings_flag_is_not_a_worker_contract_and_patch_hop_is_exact(self):
        self.lua.execute(r'''
          local function event(flag)return{mod_startup_settings_changed=flag,mod_changes={
            ["more-infinite-research"]={old_version="5.0.21011",new_version="5.0.21015"}}}end
          for _,flag in ipairs{true,false}do
            prepared.event_transition(event(flag),"2.1.24","5.0.21011","5.0.21015")
            local patch=event(flag);patch.mod_changes.base={old_version="2.1.23",new_version="2.1.24"}
            prepared.event_transition(patch,"2.1.24","5.0.21011","5.0.21015")
            patch.mod_changes.base.old_version="2.1.22"
            assert(not pcall(prepared.event_transition,patch,"2.1.24","5.0.21011","5.0.21015"))
          end
          for _,bad in ipairs{"false",0,1}do assert(not pcall(prepared.event_transition,event(bad),"2.1.24","5.0.21011","5.0.21015"))end
          local foreign=event(false);foreign.mod_changes.observer={new_version="1"}
          assert(not pcall(prepared.event_transition,foreign,"2.1.24","5.0.21011","5.0.21015"))
        ''')

    def test_full_preparation_maps_native_work_and_preserves_foreign_state(self):
        self.lua.execute(r'''
          local before=source_frame();before[1].queue={actor.ids.main,actor.ids.main,actor.ids.queued}
          local original=deep(before);local after=prepared.expected_prepared(before)
          actor.same(before,original)
          for i,f in ipairs(after)do local b=before[i];local holder=f.rows[actor.ids.private]
            assert(holder.level==b.rows[actor.ids.main].level and holder.saved==b.rows[actor.ids.main].saved)
            assert(holder.count==b.rows[actor.ids.main].count and f.bonus==b.bonus and f.progress==b.progress)
            assert(f.rows[actor.ids.main].level==4 and f.rows[actor.ids.main].saved==0)
            assert(f.rows[actor.ids.main].enabled==b.rows[actor.ids.main].enabled and f.other_saved==b.other_saved)
          end
          actor.same(after[1].queue,{actor.ids.private,actor.ids.private,actor.ids.queued})
          assert(after[1].current==actor.ids.private)
          assert(after[2].rows[actor.ids.private].saved==.27)
          assert(after[3].rows[actor.ids.private].saved==.23)
          assert(after[4].rows[actor.ids.private].level==4)
        ''')

    def test_two_literal_successor_completions_preserve_all_other_work(self):
        self.lua.execute(r'''
          local source=source_frame();source[1].queue={actor.ids.main,actor.ids.main,actor.ids.queued}
          local first=actor.expected_upgrade(source);local original=deep(first)
          local paid=prepared.expected_completion(first,1)
          actor.same(first,original)
          assert(paid[1].rows[actor.ids.tail].level==9 and paid[1].rows[actor.ids.tail].count==5125)
          assert(paid[1].bonus==source[1].bonus+1 and paid[1].current==actor.ids.tail and paid[1].progress==0)
          actor.same(paid[1].queue,{actor.ids.tail,actor.ids.queued})
          for i=2,4 do actor.same(first[i],paid[i])end
          local unpaid=prepared.expected_completion(paid,4)
          assert(unpaid[4].rows[actor.ids.tail].level==5 and unpaid[4].bonus==source[4].bonus+1)
          assert(unpaid[4].current==nil and #unpaid[4].queue==0 and unpaid[4].progress==0)
          for i=1,3 do actor.same(paid[i],unpaid[i])end
          assert(math.ceil(3417*(1-.42))==1982 and math.ceil(675*(1-.37))==426)
          unpaid[4].current=actor.ids.queued
          assert(not pcall(prepared.expected_completion,unpaid,4))
        ''')

    def test_load_callback_is_locals_only_and_selection_keeps_legacy_default(self):
        self.lua.execute(r'''
          local callbacks=prepared.bind(actor)
          game=setmetatable({},{__index=function()error("native read on load")end})
          storage=setmetatable({},{__index=function()error("storage read on load")end})
          callbacks.on_load()
        ''')
        info=json.loads((FIXTURE / "info-f200.json").read_text())
        self.assertEqual(info["name"], "mir-worker-storage-default-native")
        self.assertEqual(info["factorio_version"], "2.0")
        self.assertEqual(info["dependencies"], ["base >= 2.0.77", "more-infinite-research"])


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir",type=Path,required=True)
    args=parser.parse_args();sys.path.insert(0,str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

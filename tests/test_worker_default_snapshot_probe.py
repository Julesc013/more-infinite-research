"""Host fixture guards only; native save/physics ordering remains unobserved."""
import argparse
import json
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/worker-default-snapshot-probe"


class WorkerDefaultSnapshotProbeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().snapshot_source = (FIXTURE / "snapshot.lua").read_text()
        self.lua.execute("probe=assert(load(snapshot_source))(); native_frame={{current='worker-robots-storage-4',progress=.42,queue={'worker-robots-storage-4','sentinel'},main={level=4,researched=false,saved_progress=.27,enabled=true},bonus=3}}")

    def observe_world(self):
        self.lua.execute(r'''
          game={tick=264,speed=1,difficulty_settings={technology_price_multiplier=1}}
          script={active_mods={base='2.1.23',['more-infinite-research']='5.0.21012',[probe.fixture]='0.1.1'}}
          storage={last_tick={tick=263,native=native_frame,continuous_advances=20},
            autosave_requested_tick=263,setup={scripted_prerequisites=true,scripted_initial_partials=true}}
          logs={};emitted={};helpers={table_to_json=function(body)emitted[#emitted+1]=body;return '{}'end}
          log=function(line)logs[#logs+1]=line end
          probe.capture=function()return native_frame end;probe.lab_witnesses=function()return {}end
        ''')

    def test_exact_comparator_preserves_complete_frame(self):
        self.lua.execute("local function clone(t)local o={} for k,v in pairs(t)do o[k]=type(v)=='table'and clone(v)or v end return o end;assert(probe.same(native_frame,clone(native_frame)))")

    def test_one_tick_and_one_ulp_loss_are_not_tolerated(self):
        for amount in (1 / 675, math.nextafter(.42, 1) - .42):
            with self.subTest(amount=amount):
                self.lua.globals().loss = amount
                self.lua.execute("local changed={{current='worker-robots-storage-4',progress=.42+loss,queue={'worker-robots-storage-4','sentinel'},main={level=4,researched=false,saved_progress=.27,enabled=true},bonus=3}};assert(not probe.same(native_frame,changed))")

    def test_queue_level_bonus_flags_and_suspended_opponents(self):
        for field in ("t[1].queue={'sentinel','worker-robots-storage-4'}", "t[1].main.level=5",
                      "t[1].bonus=4", "t[1].main.enabled=false", "t[1].main.saved_progress=0", "t[1].extra=true"):
            with self.subTest(field=field):
                self.lua.execute("local t={{current='worker-robots-storage-4',progress=.42,queue={'worker-robots-storage-4','sentinel'},main={level=4,researched=false,saved_progress=.27,enabled=true},bonus=3}};"+field+";assert(not probe.same(native_frame,t))")

    def test_observation_is_readonly_and_exact_match_passes(self):
        self.observe_world()
        self.lua.execute("setmetatable(storage,{__newindex=function()error('observation wrote storage')end});assert(probe.observe('lua-migration-entry'));assert(#logs==1 and emitted[1].equal_native_state==true)")

    def test_mismatch_emits_both_frames_before_same_strict_refusal(self):
        self.observe_world()
        self.lua.execute(r'''
          storage.last_tick.native={{current='worker-robots-storage-4',progress=.42-1/675}}
          local before=storage.last_tick;local ok,err=pcall(probe.observe,'lua-migration-entry')
          assert(not ok and tostring(err):find('no one-tick allowance',1,true))
          assert(storage.last_tick==before and #logs==1 and emitted[1].saved_lua==before)
          assert(emitted[1].native==native_frame and emitted[1].equal_native_state==false)
        ''')

    def test_exact_tuple_clock_and_price_opponents(self):
        for opponent in ("game.speed=16", "game.difficulty_settings.technology_price_multiplier=2",
                         "script.active_mods.base='2.1.24'", "script.active_mods['more-infinite-research']='5.0.21011'",
                         "script.active_mods.foreign='1'", "script.active_mods[probe.fixture]='0.1.2'"):
            with self.subTest(opponent=opponent):
                self.observe_world()
                self.lua.execute(opponent+";assert(not pcall(probe.closure))")

    def test_nonround_autosave_request_does_not_stop_observing_or_labs(self):
        self.observe_world()
        self.lua.globals().control_source = (FIXTURE / "control.lua").read_text()
        self.lua.execute(r'''
          script.active_mods[probe.fixture]='0.1.0'
          local stock={get_item_count=function()return 100 end,insert=function()error('unneeded supply mutation')end}
          storage={labs={},continuous_advances=0,ordinary_completions=0}
          for _,name in ipairs(probe.forces)do storage.labs[name]={get_inventory=function()return stock end}end
          defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}}
          script.on_init=function()end;script.on_load=function()end;script.on_configuration_changed=function()end;script.on_event=function()end
          game.auto_save=function(name)saves=(saves or 0)+1;saved_name=name;saved_tick=game.tick end
          require=function(name)assert(name=='__mir-fixture-worker-default-snapshot__/snapshot');return probe end
          probe.capture=function()
            return {{current='a',progress=game.tick/675},{current='b',progress=.42+game.tick/100000},{current='c',progress=.125+game.tick/100000}}
          end
          probe.lab_witnesses=function()
            local out={}for i=1,3 do out[i]={disabled=false,modules_empty=true,speed=3600,force_speed=0,force_productivity=0}end;return out
          end
          actor=assert(load(control_source))()
          for tick=240,265 do game.tick=tick;actor.on_tick{tick=tick}end
          assert(saves==1 and saved_tick==263 and saved_name==probe.save_name)
          assert(storage.last_tick.tick==265 and storage.last_tick.native[1].progress==265/675)
        ''')

    def test_data_changes_only_two_owned_prototypes(self):
        inventory=json.loads((ROOT/"spec/inventory/modern-f200-470.json").read_text())
        base=next(p for p in inventory["profiles"] if p["id"]=="base-f200")
        row=next(e["row"] for e in base["published_output"]["data"]["additions"] if e["name"]=="worker-robots-storage-4")
        self.lua.globals().worker_row=self.lua.table_from(row,recursive=True)
        self.lua.execute("data={raw={lab={lab={type='lab',name='lab',researching_speed=1,energy_source={type='electric'}}},technology={['worker-robots-storage-4']=worker_row}},emitted={}};data.extend=function(self,rows)for _,r in ipairs(rows)do self.emitted[#self.emitted+1]=r end end")
        self.lua.execute((FIXTURE/"data.lua").read_text())
        self.lua.execute((FIXTURE/"data-final-fixes.lua").read_text())
        self.lua.execute(r'''
          assert(#data.emitted==2 and data.raw.lab.lab.researching_speed==1 and worker_row.effects[1].modifier==1)
          local lab,s=data.emitted[1],data.emitted[2]
          assert(lab.name==probe.lab and lab.researching_speed==3600 and lab.energy_source.type=='void')
          assert(s.name==probe.sentinel and s.level==1 and s.max_level==1 and #s.effects==0)
          assert(s.unit.count==100000 and s.unit.count_formula==nil and s.unit.time==60)
          assert(worker_row.name==probe.main and worker_row.unit.count_formula=='675*1.5^(L-4)')
        ''')

    def test_target_migration_keeps_strict_observation_error(self):
        self.observe_world()
        self.lua.execute("require=function(name)return probe end;storage.last_tick.native={}")
        source=(FIXTURE/"migrations/0.1.1.lua").read_text()
        self.lua.globals().migration_source=source
        self.lua.execute("local ok,err=pcall(assert(load(migration_source)));assert(not ok and tostring(err):find('no one-tick allowance',1,true) and #logs==1)")

    def test_roles_and_missing_source_witness_refuse(self):
        self.observe_world()
        self.lua.execute("storage.setup=nil;assert(not pcall(probe.observe,'lua-migration-entry'));assert(#logs==1)")
        info=json.loads((FIXTURE/"info.json").read_text())
        self.assertEqual(info["version"],"0.1.0")
        self.assertEqual(info["dependencies"],["base >= 2.1.23","more-infinite-research = 5.0.21012"])


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir",type=Path,required=True)
    args=parser.parse_args();sys.path.insert(0,str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

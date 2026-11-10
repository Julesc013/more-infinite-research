"""Bounded host controls for the actual-provider observer; no native qualification."""
import argparse
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/worker-storage-default-native"


class WorkerStorageProviderNativeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_source = (FIXTURE / "control.lua").read_text()
        self.lua.globals().provider_source = (FIXTURE / "provider_native.lua").read_text()
        self.lua.globals().data_source = (FIXTURE / "data.lua").read_text()
        self.lua.execute(r'''
          function deep(v)if type(v)~="table"then return v end local o={}
            for k,x in pairs(v)do o[k]=deep(x)end return o end
          handlers={};script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21012",
            ["mir-worker-storage-default-native"]="0.1.0"},on_init=function(f)handlers.init=f end,
            on_load=function(f)handlers.load=f end,on_configuration_changed=function(f)handlers.configuration=f end,
            on_event=function(id,f)handlers[id]=f end}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1,lab_modules=2}}
          remote={add_interface=function()end};actor=assert(load(actor_source))()
          provider=assert(load(provider_source))()
          local ids=actor.ids
          function row(id,n,count,enabled,visible,saved,researched)
            return {name=id,level=n,count=count,enabled=enabled,visible=visible,saved=saved or 0,researched=researched or false}
          end
          function source()
            local out={}
            for i,n in ipairs({8,7,6,4})do
              local paid=n>=5
              out[i]={name=({"player","mir-worker-default-queued","mir-worker-default-detached","mir-worker-default-unpaid"})[i],
                bonus=({7,6,5,3})[i],current=(i==1 or i==4)and ids.tail or ids.current,
                progress=({.42000000000000004,.125,.19,.37})[i],queue=i==1 and {ids.tail,ids.queued}
                  or i==2 and {ids.current,ids.tail,ids.queued}or i==3 and {ids.current}or {ids.tail},
                mining=0,manual_mining=0,lab_speed=0,lab_productivity=0,robot_speed=0,
                rows={[ids.main]=row(ids.main,paid and 5 or 4,paid and 1012 or 675,false,paid),
                  [ids.tail]=row(ids.tail,n,({3417,2278,1518,675})[i],true,false,i==2 and .27 or i==3 and .23000000000000004 or 0),
                  [ids.gate]=row(ids.gate,4,1,false,false,0,paid),[ids.private]=row(ids.private,4,675,false,false),
                  [ids.current]=row(ids.current,1,100000,true,false),[ids.queued]=row(ids.queued,1,100000,true,false),
                  [ids.detached]=row(ids.detached,1,100000,true,false,.27)}}
            end
            return out
          end
          -- Independently authored expected native rows, including untouched force fields.
          function expected()
            local out=source()
            for i,n in ipairs({8,7,6,4})do local f=out[i]
              f.current=(i==1 or i==4)and ids.private or ids.current
              f.queue=i==1 and {ids.private,ids.queued}or i==2 and {ids.current,ids.private,ids.queued}
                or i==3 and {ids.current}or {ids.private}
              f.rows[ids.private]=row(ids.private,n,({3417,2278,1518,675})[i],true,false,i==2 and .27 or i==3 and .23000000000000004 or 0)
              f.rows[ids.main]=row(ids.main,4,1000,true,false,0,n>=5)
              f.rows[ids.tail]=row(ids.tail,4,675,false,false)
              for level=5,8 do local id="worker-robots-storage-"..level
                f.rows[id]=row(id,level,({2000,4000,8000,16000})[level-4],true,false)
              end
            end
            return out
          end
          function world(actual)
            actual=actual or expected();world_frames=actual
            actor.frames=function()return deep(world_frames)end
            script.active_mods.WorkerRobotCargoSizeResearch="1.0.0"
            settings={startup={["worker-robot-cargo-size-max-level"]={value=7},["worker-robot-cargo-size-infinite"]={value=false}}}
            inventory={};insert_calls=0
            local input={get_item_count=function(n)return inventory[n]or 0 end,
              insert=function(stack)insert_calls=insert_calls+1;inventory[stack.name]=(inventory[stack.name]or 0)+stack.count;return stack.count end}
            lab={valid=true,disabled_by_script=true,unit_number=12,
              prototype={get_researching_speed=function()return 115200 end},
              get_inventory=function(id)return id==1 and input or {is_empty=function()return true end}end}
            game={tick=2,speed=1,difficulty_settings={technology_price_multiplier=1},forces={},
              is_multiplayer=function()return true end,server_save=function()error("unexpected host save")end}
            prototypes={technology={},get_history=function(_,id)return {created=id:match("^worker%-robots%-storage%-[4-7]$")
              and "WorkerRobotCargoSizeResearch"or "more-infinite-research"}end}
            for _,f in ipairs(actual)do
              local technologies={};game.forces[f.name]={name=f.name,technologies=technologies,worker_robots_storage_bonus=f.bonus}
              for id,r in pairs(f.rows)do
                technologies[id]={name=id,level=r.level,researched=r.researched,enabled=r.enabled,
                  visible_when_disabled=r.visible,saved_progress=r.saved,research_unit_count=r.count}
                prototypes.technology[id]={level=r.level,max_level=(id==ids.main and 4 or id==ids.gate and 4 or 4294967295),
                  enabled=id~=ids.tail,hidden=id==ids.tail,visible_when_disabled=false,research_unit_count=r.count,
                  research_unit_energy=3600,effects={{type="worker-robot-storage",modifier=id==ids.gate and -1 or 1}},
                  research_unit_ingredients={}}
              end
            end
            local ingredients={};for _,p in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack","space-science-pack"})do ingredients[#ingredients+1]={name=p,amount=1}end
            prototypes.technology["worker-robots-storage-8"].research_unit_ingredients=ingredients
            storage={worker_storage_default_native_fixture={phase="upgrade-saved",mode="upgrade",ordinary={},
              administrative={},inserted={},closed=source(),lab=lab}}
            logs={};written={};last_body=nil
            log=function(s)logs[#logs+1]=s end
            helpers={table_to_json=function(b)last_body=deep(b);return "{}"end,
              write_file=function(p)written[#written+1]=p end}
            event={mod_changes={WorkerRobotCargoSizeResearch={new_version="1.0.0"}}}
            callbacks=provider.bind(actor)
          end
        ''')

    def test_independent_four_force_map_and_input_immutability(self):
        self.lua.execute('local before=source();local saved=deep(before);actor.same(expected(),provider.expected_handover(before));actor.same(before,saved)')

    def test_unpaid_current_partial_and_gate_are_preserved(self):
        self.lua.execute(r'''
          local f=provider.expected_handover(source())[4];local id=actor.ids
          assert(f.current==id.private and f.progress==.37 and f.queue[1]==id.private and f.bonus==3)
          assert(f.rows[id.private].level==4 and f.rows[id.private].count==675 and f.rows[id.private].enabled)
          assert(not f.rows[id.main].researched and not f.rows[id.gate].researched)
          assert(f.rows[id.main].enabled and not f.rows[id.main].visible and not f.rows[id.tail].enabled)
        ''')

    def test_source_identity_prices_and_representation_opponents(self):
        self.lua.execute(r'''
          for _,mutate in ipairs({function(f)f[1].rows[actor.ids.tail].researched=true end,
            function(f)f[2].rows[actor.ids.tail].count=2279 end,function(f)f[4].rows[actor.ids.gate].researched=true end,
            function(f)f[1].rows["worker-robots-storage-8"]={}end})do
            local before=source();mutate(before);assert(not pcall(provider.expected_handover,before))
          end
          local out=provider.expected_handover(source());out[1].queue[1]="changed";out[2].rows[actor.ids.private].saved=.9
          assert(source()[1].queue[1]==actor.ids.tail and source()[2].rows[actor.ids.tail].saved==.27)
        ''')

    def test_exact_ulp_queue_bonus_flags_and_foreign_opponents(self):
        self.lua.globals().ulp = math.nextafter(.42000000000000004, 1) - .42000000000000004
        self.lua.execute(r'''
          for _,mutate in ipairs({function(f)f[1].progress=f[1].progress+ulp end,
            function(f)f[2].rows[actor.ids.private].saved=0 end,function(f)f[3].rows[actor.ids.private].saved=.23 end,
            function(f)f[2].queue[2],f[2].queue[3]=f[2].queue[3],f[2].queue[2]end,
            function(f)f[4].current=actor.ids.tail end,function(f)f[4].bonus=4 end,
            function(f)f[1].rows[actor.ids.main].enabled=false end,function(f)f[3].rows[actor.ids.detached].saved=0 end})do
            local actual=expected();mutate(actual);assert(not pcall(actor.same,provider.expected_handover(source()),actual))
          end
        ''')

    def test_configuration_records_raw_before_rejection_and_setup_writes(self):
        self.lua.execute(r'''
          local actual=expected();actual[4].progress=0;world(actual)
          local s=storage.worker_storage_default_native_fixture;local saved=deep(s.closed)
          assert(not pcall(callbacks.on_configuration_changed,event))
          assert(last_body.stage=="provider-configuration-observed" and last_body.frames[4].progress==0)
          assert(s.phase=="upgrade-saved" and s.mode=="upgrade" and s.provider_baseline==nil and insert_calls==0)
          actor.same(s.closed,saved);assert(lab.disabled_by_script and #written==1)
        ''')

    def test_valid_configuration_checks_all_forces_before_starting_test_lab(self):
        self.lua.execute(r'''
          world();callbacks.on_configuration_changed(event)
          local s=storage.worker_storage_default_native_fixture
          assert(s.phase=="provider-private-ready" and s.mode=="provider" and lab.disabled_by_script and insert_calls==0)
          actor.same(s.provider_baseline,expected());actor.same(s.provider_input,source())
          callbacks.on_tick();assert(s.phase=="provider-private-research" and not lab.disabled_by_script and insert_calls==5)
          assert(inventory["space-science-pack"]==nil)
        ''')

    def test_tuple_settings_and_unrelated_transition_refuse_before_setup(self):
        self.lua.execute(r'''
          for _,bad in ipairs({function()script.active_mods.WorkerRobotCargoSizeResearch="1.0.1"end,
            function()settings.startup["worker-robot-cargo-size-max-level"].value=8 end,
            function()settings.startup["worker-robot-cargo-size-infinite"].value=true end,
            function()event.mod_changes.other={new_version="1"}end})do
            world();bad();assert(not pcall(callbacks.on_configuration_changed,event))
            assert(storage.worker_storage_default_native_fixture.phase=="upgrade-saved" and insert_calls==0 and lab.disabled_by_script)
          end
        ''')

    def test_actual_finish_pauses_lab_and_refuses_wrong_ordinary_identity(self):
        self.lua.execute(r'''
          world();storage.worker_storage_default_native_fixture.phase="provider-private-research";lab.disabled_by_script=false
          assert(not pcall(callbacks.on_finished,{research={name="worker-robots-storage-8",force=game.forces.player},by_script=false,tick=64}))
          assert(lab.disabled_by_script and last_body.stage=="provider-private-completion-observed")
          assert(#storage.worker_storage_default_native_fixture.ordinary==0)
        ''')

    def test_scripted_setup_is_labelled_and_never_ordinary(self):
        self.lua.execute(r'''
          world();local s=storage.worker_storage_default_native_fixture
          assert(not pcall(callbacks.on_finished,{research={name="worker-robots-storage-5",force=game.forces.player},by_script=true,tick=65}))
          s.provider_setting_up=true
          callbacks.on_finished{research={name="worker-robots-storage-5",force=game.forces.player},by_script=true,tick=65}
          assert(#s.administrative==1 and #s.ordinary==0 and last_body.extra.by_script)
          s.provider_setting_up=nil
          assert(not pcall(callbacks.on_finished,{research={name="foreign",force=game.forces.player},by_script=true,tick=65}))
        ''')

    def test_load_is_local_only_and_cold_is_exact_read_only(self):
        self.lua.execute(r'''
          world();local s=storage.worker_storage_default_native_fixture
          s.phase="provider-saved";s.ordinary={{name=actor.ids.private},{name="worker-robots-storage-8"}}
          s.closed=expected();s.closed_lab={disabled=true,unit=12,speed=115200,inventory={
            ["automation-science-pack"]=0,["logistic-science-pack"]=0,["chemical-science-pack"]=0,
            ["production-science-pack"]=0,["utility-science-pack"]=0,["space-science-pack"]=0},modules_empty=true}
          local oldgame,oldstorage=game,storage
          game=setmetatable({}, {__index=function()error("load game")end})
          storage=setmetatable({}, {__index=function()error("load storage")end,__newindex=function()error("load write")end})
          callbacks.on_load();game,storage=oldgame,oldstorage
          callbacks.on_tick();assert(last_body.stage=="cold" and insert_calls==0 and lab.disabled_by_script)
          world_frames[4].progress=0;assert(not pcall(callbacks.begin,"cold"))
          assert(not pcall(callbacks.begin,"provider"))
        ''')

    def test_setup_admits_and_labels_only_expected_base_finite_gate_closure(self):
        self.lua.execute(r'''
          world();local s=storage.worker_storage_default_native_fixture;s.provider_setting_up=true
          for _,id in ipairs({"concrete","electric-energy-accumulators","electric-energy-distribution-1","flammables",
            "productivity-module-2","productivity-module-3","radar","rocket-fuel","rocket-silo","solar-energy",
            "space-science-pack","speed-module","speed-module-2","speed-module-3"})do
            prototypes.technology[id]={max_level=1}
            prototypes.get_history=function(_,name)return {created=name==id and "base"or "more-infinite-research"}end
            callbacks.on_finished{research={name=id,force=game.forces.player},by_script=true,tick=65}
            assert(last_body.extra.setup_class=="finite-base-prerequisite-setup")
          end
          assert(#s.administrative==14 and #s.ordinary==0)
          for _,entry in ipairs(s.administrative)do assert(entry.by_script and entry.setup_class=="finite-base-prerequisite-setup")end
        ''')

    def test_setup_refuses_foreign_base_infinite_unlisted_base_and_continuation(self):
        self.lua.execute(r'''
          for _,opponent in ipairs({{id="rocket-silo",creator="foreign",maximum=1},
            {id="speed-module",creator="base",maximum=4294967295},
            {id="automation",creator="base",maximum=1},
            {id="worker-robots-storage-8",creator="more-infinite-research",maximum=4294967295}})do
            world();local s=storage.worker_storage_default_native_fixture;s.provider_setting_up=true
            if opponent.id~="worker-robots-storage-8"then prototypes.technology[opponent.id]={max_level=opponent.maximum}end
            prototypes.get_history=function()return {created=opponent.creator}end
            assert(not pcall(callbacks.on_finished,{research={name=opponent.id,force=game.forces.player},by_script=true,tick=65}))
            assert(last_body.stage=="provider-scripted-completion-observed" and #s.administrative==0 and #s.ordinary==0)
          end
          world();prototypes.technology["rocket-silo"]={max_level=1}
          prototypes.get_history=function()return {created="base"}end
          assert(not pcall(callbacks.on_finished,{research={name="rocket-silo",force=game.forces.player},by_script=true,tick=65}))
        ''')

    def test_only_actual_provider_selects_parse_time_module(self):
        self.lua.execute(r'''
          local calls=0;require=function(name)assert(name=="provider_native");calls=calls+1;return provider end
          assert(load(actor_source))();assert(calls==0)
          script.active_mods.WorkerRobotCargoSizeResearch="1.0.0"
          assert(load(actor_source))();assert(calls==1)
          handlers.load();assert(calls==1)
        ''')

    def test_provider_lab_only_changes_owned_prototype_and_default_path_stays3600(self):
        self.lua.execute(r'''
          for _,present in ipairs({false,true})do
            mods=present and {WorkerRobotCargoSizeResearch="1.0.0"}or nil
            local original={type="lab",name="lab",researching_speed=1,energy_source={type="electric"}}
            data={raw={lab={lab=original}},extend=function(self,rows)self.rows=rows end};assert(load(data_source))()
            assert(#data.rows==4 and data.rows[1].researching_speed==(present and 115200 or 3600))
            assert(original.researching_speed==1 and original.energy_source.type=="electric")
          end
        ''')

    def test_science_predictions_are_strict_independent_arithmetic(self):
        self.assertEqual(1984, math.ceil(3417 * (1 - .42000000000000004) / 32) * 32)
        self.assertEqual(16000, 1000 * 2 ** (8 - 4))
        self.assertEqual(500, 16000 // 32)
        text = (FIXTURE / "provider_native.lua").read_text()
        self.assertIn('used[pack] == (i == 6 and 0 or 1984)', text)
        self.assertIn('used[pack] - s.provider_continuation_consumed[pack] == 16000', text)
        self.assertNotIn("storage.mir", text)
        self.assertNotIn('require("runtime.', text)
        cold = text.split("local function cold()", 1)[1].split("local callbacks", 1)[0]
        for forbidden in ("server_save", "research_queue =", "researched =", "insert{", "saved_progress ="):
            self.assertNotIn(forbidden, cold)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WorkerStorageProviderNativeTests))
    sys.exit(0 if result.wasSuccessful() else 1)

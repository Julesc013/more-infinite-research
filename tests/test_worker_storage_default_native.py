"""Independent host controls for the draft default-worker native fixture; no native acceptance."""
import argparse
import json
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/worker-storage-default-native"


class WorkerStorageDefaultNativeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_source = (FIXTURE / "control.lua").read_text()
        self.lua.execute(r'''
          handlers={};interfaces={};script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21012",
            ["mir-worker-storage-default-native"]="0.1.0"},
            on_init=function(fn)handlers.init=fn end,on_load=function(fn)handlers.load=fn end,
            on_configuration_changed=function(fn)handlers.configuration=fn end,
            on_event=function(id,fn)handlers[id]=fn end}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1,lab_modules=2}}
          remote={add_interface=function(name,body)interfaces[name]=body end}
          storage={};actor=assert(load(actor_source))();logs={};written={}
          log=function(line)logs[#logs+1]=line end
          helpers={table_to_json=function(body)last_body=body;return "{}"end,
            write_file=function(path,text,append)written[#written+1]=path end}
          function deep(v)if type(v)~="table"then return v end local out={}
            for k,x in pairs(v)do out[k]=deep(x)end return out end
          function r(name,level,count,enabled,saved)
            return {name=name,level=level,researched=false,enabled=enabled,visible=false,saved=saved or 0,count=count}
          end
          function source_frame()
            local ids=actor.ids;local out={}
            for i,n in ipairs({8,7,6,4})do
              local name=({"player","mir-worker-default-queued","mir-worker-default-detached","mir-worker-default-unpaid"})[i]
              out[i]={name=name,bonus=3+n-4,current=i==1 or i==4 and ids.main or ids.current,
                progress=({.42,.125,.19,.37})[i],queue=i==1 and {ids.main,ids.queued}
                  or i==2 and {ids.current,ids.main,ids.queued}or i==3 and {ids.current}or {ids.main},
                rows={[ids.main]=r(ids.main,n,math.floor(675*1.5^(n-4)),true,i==2 and .27 or i==3 and .23 or 0),
                  [ids.private]=r(ids.private,4,675,false),[ids.detached]=r(ids.detached,1,100000,true,.27)},
                mining=0,manual_mining=0,lab_speed=0,lab_productivity=0,robot_speed=0}
              if i==1 or i==4 then out[i].current=ids.main end
            end
            return out
          end
        ''')

    def test_canonical_metadata_supports_same_fixture_version_after_mir(self):
        info = json.loads((FIXTURE / "info.json").read_text())
        self.assertEqual("0.1.0", info["version"])
        self.assertEqual("2.1", info["factorio_version"])
        self.assertEqual(["base >= 2.1.23", "more-infinite-research"], info["dependencies"])
        self.assertFalse((FIXTURE / "settings.lua").exists())

    def test_exact_map_price_mode_selection_rejects_old_or_unsupported_routes(self):
        self.lua.execute(r'''
          assert(actor.select_mode("5.0.21011",1)=="old-source")
          assert(actor.select_mode("5.0.20011",1)=="old-source")
          assert(actor.select_mode("5.0.21012",1)=="first")
          assert(actor.select_mode("5.0.20012",1)=="first")
          assert(actor.select_mode("5.0.21012",2)=="first-map-price")
          assert(actor.select_mode("5.0.20012",4)=="first-map-price")
          for _,input in ipairs({{"5.0.21011",2},{"5.0.20011",4},{"5.0.21012",0},
            {"5.0.21012",3},{"5.0.21012",1.5},{"5.0.21013",1}})do
            assert(not pcall(actor.select_mode,input[1],input[2]))
          end
          game={speed=1,difficulty_settings={technology_price_multiplier=1}}
          storage={};assert(not pcall(interfaces["mir-worker-storage-default-native"].begin,"first-map-price"))
          assert(storage.worker_storage_default_native_fixture==nil)
        ''')

    def test_first_level4_map_price_witness_has_only_independent_integer_expectations(self):
        self.lua.execute(r'''
          assert(actor.first_level4_science(2)==1350 and actor.first_level4_science(4)==2700)
          assert(not pcall(actor.first_level4_science,1) and not pcall(actor.first_level4_science,3))
        ''')
        text = (FIXTURE / "control.lua").read_text()
        self.assertIn('p.ignore_tech_cost_multiplier == true', text)
        self.assertIn('p.research_unit_count == 1', text)
        self.assertIn('check(#s.ordinary == 1, "one actual first level4 completion")', text)
        self.assertIn('"first-map-price-" .. s.map_price .. "x-level4-saved"', text)
        for unproven_level5_count in ("3374", "6748", "3375", "6750"):
            self.assertNotIn(unproven_level5_count, text)

    def _install_map_price_world(self):
        self.lua.execute(r'''
          local function worker(name, level, count, enabled, visible, saved)
            return {name=name,level=level,researched=false,enabled=enabled,visible_when_disabled=visible,
              saved_progress=saved or 0,research_unit_count=count}
          end
          function map_price_world(multiplier, spent, ordinary, inserted, phase)
            local id, science = actor.ids, {"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack"}
            local prerequisites = {"worker-robots-storage-2","worker-robots-storage-3","automation-science-pack",
              "logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"}
            local function ingredients()
              local out={};for i,name in ipairs(science)do out[i]={name=name,amount=1}end;return out
            end
            local function full(name, hidden, enabled, modifier)
              local required={};for _,name in ipairs(prerequisites)do required[name]={name=name}end
              return {name=name,level=4,max_level=4294967295,hidden=hidden,enabled=enabled,visible_when_disabled=false,
                research_unit_count_formula="675*1.5^(L-4)",research_unit_count=675,research_unit_energy=3600,
                research_unit_ingredients=ingredients(),effects={{type="worker-robot-storage",modifier=modifier}},
                prerequisites=required,ignore_tech_cost_multiplier=false}
            end
            prototypes={technology={[id.main]=full(id.main,false,true,1),[id.tail]=full(id.tail,false,true,1),
              [id.private]=full(id.private,true,false,1),[id.gate]={name=id.gate,level=4,max_level=4294967295,
                hidden=true,enabled=false,visible_when_disabled=false,research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name=science[1],amount=1}},effects={{type="worker-robot-storage",modifier=-1}},
                prerequisites={},ignore_tech_cost_multiplier=true}},get_history=function(kind,name)return {created="more-infinite-research"}end}
            local function force(name, player)
              local rows={[id.main]=worker(id.main,5,9999,false,true),[id.tail]=worker(id.tail,5,7777,true,false),
                [id.gate]=worker(id.gate,5,1,false,false),[id.private]=worker(id.private,4,675,false,false),
                [id.current]=worker(id.current,1,100000,true,false),[id.queued]=worker(id.queued,1,100000,true,false),
                [id.detached]=worker(id.detached,1,100000,true,false)}
              local current=player and rows[id.tail] or rows[id.current]
              return {name=name,valid=true,technologies=rows,worker_robots_storage_bonus=player and 4 or 3,current_research=current,
                research_progress=0,research_queue=player and {rows[id.tail],rows[id.queued]} or {current},
                mining_drill_productivity_bonus=0,manual_mining_speed_modifier=0,laboratory_speed_modifier=0,
                laboratory_productivity_bonus=0,worker_robots_speed_modifier=0}
            end
            local expected=675*multiplier;inserted=inserted or math.ceil(expected/200)*200
            local input={counts={}};for _,name in ipairs(science)do input.counts[name]=inserted-spent end
            input.get_item_count=function(name)return input.counts[name]end
            local modules={is_empty=function()return true end}
            local lab={valid=true,disabled_by_script=false,unit_number=17,prototype={get_researching_speed=function()return 3600 end},
              get_inventory=function(kind)return kind==defines.inventory.lab_input and input or modules end}
            saves={};game={tick=300,speed=1,difficulty_settings={technology_price_multiplier=multiplier},
              forces={player=force("player",true),["mir-worker-default-queued"]=force("mir-worker-default-queued"),
                ["mir-worker-default-detached"]=force("mir-worker-default-detached"),["mir-worker-default-unpaid"]=force("mir-worker-default-unpaid")},
              is_multiplayer=function()return true end,server_save=function(name)saves[#saves+1]=name end}
            storage={};local state={mode="first-map-price",map_price=multiplier,phase=phase or "head-research",lab=lab,
              ordinary={},administrative={},inserted={}}
            for _,name in ipairs(science)do state.inserted[name]=inserted end
            for i=1,ordinary do state.ordinary[i]={name=id.tail,tick=i,by_script=false}end
            storage.worker_storage_default_native_fixture=state;state.baseline=deep(actor.frames())
            return state,id,science
          end

        ''')

    def test_map_price_first_completion_saves_then_cold_loads_exact_closed_frame(self):
        self._install_map_price_world()
        self.lua.execute(r'''
          for _,multiplier in ipairs({2,4})do
            local state,id=map_price_world(multiplier,675*multiplier,0)
            actor.on_finished{research={name=id.tail,force=game.forces.player},by_script=false,tick=game.tick}
            assert(state.phase=="head-finished" and state.lab.disabled_by_script and #state.ordinary==1)
            actor.on_tick()
            local phase="first-map-price-"..multiplier.."x-level4-saved"
            assert(state.phase==phase and saves[1]=="worker-default-"..phase)
            assert(last_body.stage==state.phase and last_body.map_price==multiplier and #last_body.ordinary==1)
            assert(last_body.frames[1].bonus==4 and last_body.frames[1].current==id.tail)
            assert(last_body.frames[1].rows[id.main].level==5 and last_body.frames[1].rows[id.gate].count==1)
            assert(last_body.contracts[id.gate].ignore_price==true and type(last_body.frames[1].rows[id.tail].count)=="number")
            local closed=deep(state.closed);handlers.load();actor.on_tick()
            assert(last_body.stage=="cold" and #saves==1 and state.phase==phase)
            actor.same(closed,state.closed)
          end
        ''')

    def test_map_price_witness_refuses_changed_frames_science_and_ordinary_counts(self):
        self._install_map_price_world()
        self.lua.execute(r'''
          local id=actor.ids
          local function make(spent, ordinary, inserted)
            local state=map_price_world(2,spent,ordinary,inserted,"head-finished")
            state.lab.disabled_by_script=true
            return state
          end
          for _,case in ipairs({{1349,1,nil},{1351,1,nil},{1350,1,1350},{1350,1,1600},{1350,0,nil},{1350,2,nil}})do
            local state=make(case[1],case[2],case[3]);local ok=pcall(actor.on_tick)
            assert(not ok and #saves==0 and state.phase=="head-finished")
          end
          local state=make(1350,1);game.forces.player.technologies[id.private].saved_progress=.5
          local ok=pcall(actor.on_tick);assert(not ok and #saves==0 and state.phase=="head-finished")
          state=make(1350,1);game.forces.player.technologies[id.gate].research_unit_count=2
          ok=pcall(actor.on_tick);assert(not ok and #saves==0 and state.phase=="head-finished")
        ''')

    def test_existing_one_x_first_and_old_routes_remain_separate_from_map_price_witness(self):
        text = (FIXTURE / "control.lua").read_text()
        self.assertIn('save("first-saved", frames)', text)
        self.assertIn('675 + 1012', text)
        self.assertIn('s.phase == "old-source-saved"', text)
        self.assertIn('closure(false, "upgrade")', text)

    def test_data_is_four_detached_owned_prototypes_without_foreign_changes(self):
        self.lua.globals().data_source = (FIXTURE / "data.lua").read_text()
        self.lua.execute(r'''
          local original={type="lab",name="lab",researching_speed=1,energy_source={type="electric"}}
          data={raw={lab={lab=original}},emitted={}}
          data.extend=function(self,rows)self.emitted=rows end;assert(load(data_source))()
          assert(#data.emitted==4 and original.researching_speed==1 and original.energy_source.type=="electric")
          assert(data.emitted[1].researching_speed==3600 and data.emitted[1].energy_source.type=="void")
          for i=2,4 do local row=data.emitted[i]
            assert(row.name:match("^mir%-worker%-default%-native%-") and not row.name:match("%-%d+$"))
            assert(next(row.effects)==nil and next(row.prerequisites)==nil and row.max_level==1)
          end
          data.emitted[1].energy_source.type="changed";assert(original.energy_source.type=="electric")
        ''')

    def test_old_source_expected_mapping_preserves_all_four_native_work_modes(self):
        self.lua.execute(r'''
          local before=source_frame();local original=deep(before);local out=actor.expected_upgrade(before);local id=actor.ids
          actor.same(before,original)
          for i,n in ipairs({8,7,6})do
            assert(out[i].bonus==3+n-4 and out[i].rows[id.main].level==5 and out[i].rows[id.main].enabled==false)
            assert(out[i].rows[id.main].visible==true)
            assert(out[i].rows[id.main].count==1012 and out[i].rows[id.tail].level==n)
            assert(out[i].rows[id.tail].count==({3417,2278,1518})[i]
              and out[i].rows[id.gate].level==5 and out[i].rows[id.gate].researched==false)
          end
          assert(out[1].current==id.tail and out[1].queue[1]==id.tail and out[1].progress==.42)
          assert(out[2].current==id.current and out[2].queue[2]==id.tail and out[2].rows[id.tail].saved==.27)
          assert(out[3].current==id.current and out[3].rows[id.tail].saved==.23)
          assert(out[4].rows[id.main].level==4 and not out[4].rows[id.main].enabled and out[4].rows[id.main].saved==0)
          assert(out[4].rows[id.gate].level==4 and out[4].rows[id.gate].researched==false
            and out[4].rows[id.tail].enabled and out[4].rows[id.tail].level==4)
          assert(out[4].current==id.tail and out[4].progress==.37 and out[4].queue[1]==id.tail)
          for i=1,4 do actor.same(out[i].rows[id.detached],before[i].rows[id.detached])end
        ''')

    def test_old_implementation_cannot_pass_candidate_frame(self):
        self.lua.execute('local old=source_frame();local expected=actor.expected_upgrade(old);assert(not pcall(actor.same,expected,old))')

    def test_exact_native_frames_reject_ulp_work_loss_queue_bonus_and_flags(self):
        self.lua.globals().ulp = math.nextafter(.42, 1) - .42
        self.lua.execute(r'''
          local expected=actor.expected_upgrade(source_frame());local id=actor.ids
          for _,change in ipairs({function(x)x[1].progress=x[1].progress+ulp end,
            function(x)x[2].rows[id.tail].saved=0 end,function(x)x[3].rows[id.tail].level=5 end,
            function(x)x[1].queue[1]=id.main end,function(x)x[1].bonus=8 end,
            function(x)x[1].rows[id.main].enabled=true end,function(x)x[4].rows[id.gate].researched=true end})do
            local actual=deep(expected);change(actual);assert(not pcall(actor.same,expected,actual))
          end
        ''')

    def test_callback_guard_rejects_late_tick_transfer_and_all_canonical_work_residue(self):
        self.lua.execute(r'''
          local id=actor.ids;local expected=actor.expected_upgrade(source_frame())[1]
          actor.assert_callback_safe(expected)
          actor.assert_settled_flags(expected)
          for _,change in ipairs({function(x)x.rows[id.main].visible=false end,
            function(x)x.rows[id.tail].visible=true end,function(x)x.rows[id.gate].enabled=true end,
            function(x)x.rows[id.gate].visible=true end,function(x)x.rows[id.gate].saved=.001 end})do
            local wrong=deep(expected);change(wrong);assert(not pcall(actor.assert_settled_flags,wrong))
          end
          for _,change in ipairs({function(x)x.current=id.main end,
            function(x)x.queue[1]=id.main end,function(x)x.rows[id.main].saved=.001 end,
            function(x)x.rows[id.main].level=4 end,function(x)x.rows[id.main].researched=true end,
            function(x)x.rows[id.gate].level=4 end,function(x)x.rows[id.gate].researched=true end,
            function(x)x.rows[id.tail].level=4 end})do
            local unsafe=deep(expected);change(unsafe)
            assert(not pcall(actor.assert_callback_safe,unsafe))
            -- A later tick could replace this frame; that cannot admit this callback.
            actor.assert_callback_safe(deep(expected))
          end
        ''')

    def test_real_completion_observer_logs_then_refuses_deferred_identity_move(self):
        self.lua.execute(r'''
          local id=actor.ids;local frames=actor.expected_upgrade(source_frame())
          frames[1].bonus=4;frames[1].rows[id.tail].level=5;frames[1].rows[id.tail].count=1012
          local state={mode="first",phase="head-research",ordinary={},administrative={},baseline=deep(frames)}
          storage.worker_storage_default_native_fixture=state
          frames[1].current=id.main -- A proposed next-tick rewrite cannot admit this callback.
          actor.frames=function()return frames end
          local world={name="player"};game={tick=100,forces={player=world},server_save=function()error("unexpected save")end}
          local ok,message=pcall(actor.on_finished,{research={name=id.tail,force=world},by_script=false,tick=100})
          assert(not ok and tostring(message):find("canonical current work",1,true))
          assert(last_body.stage=="completion-head-observed" and last_body.frames[1].current==id.main)
          assert(state.phase=="head-research" and #written==1)
        ''')

    def test_closed_source_cannot_invent_completed_representation_or_alias_input(self):
        self.lua.execute(r'''
          local source=source_frame();source[1].rows[actor.ids.main].researched=true
          assert(not pcall(actor.expected_upgrade,source))
          source=source_frame();local expected=actor.expected_upgrade(source)
          expected[1].queue[1]="changed";expected[2].rows[actor.ids.tail].saved=.9
          assert(source[1].queue[1]==actor.ids.main and source[2].rows[actor.ids.main].saved==.27)
        ''')

    def test_unknown_modes_refuse_and_load_hook_does_not_touch_game_or_storage(self):
        self.lua.execute(r'''
          assert(not pcall(interfaces["mir-worker-storage-default-native"].begin,"provider"))
          game=setmetatable({}, {__index=function()error("on_load read game")end})
          storage=setmetatable({}, {__index=function()error("on_load read storage")end,
            __newindex=function()error("on_load wrote storage")end})
          handlers.load()
        ''')

    def test_exact_first_tick_auto_mode_selection_does_not_reinitialize_saved_or_cold_state(self):
        self.lua.execute(r'''
          local calls={};actor.begin=function(mode)calls[#calls+1]=mode end
          game={difficulty_settings={technology_price_multiplier=1}}
          for _,version in ipairs({"5.0.21011","5.0.20011","5.0.21012","5.0.20012"})do
            storage={};script.active_mods["more-infinite-research"]=version;actor.on_tick()
            assert(calls[#calls]==(version:sub(-2)=="11"and"old-source"or"first"))
          end
          for _,multiplier in ipairs({2,4})do
            storage={};game.difficulty_settings.technology_price_multiplier=multiplier
            script.active_mods["more-infinite-research"]="5.0.21012";actor.on_tick()
            assert(calls[#calls]=="first-map-price")
          end
          game.difficulty_settings.technology_price_multiplier=1
          script.active_mods["more-infinite-research"]="5.0.21013";storage={}
          assert(not pcall(actor.on_tick))
          local count=#calls;local state={phase="first-saved"};storage={worker_storage_default_native_fixture=state}
          local colds=0;actor.cold=function()colds=colds+1 end
          handlers.load();actor.on_tick();actor.on_tick()
          assert(#calls==count and colds==1 and storage.worker_storage_default_native_fixture==state)
          assert(state.phase=="first-saved")
        ''')

    def test_scripted_and_ordinary_event_classes_cannot_be_pooled(self):
        self.lua.execute(r'''
          local id=actor.ids
          storage.worker_storage_default_native_fixture={mode="first",phase="head-research",ordinary={},administrative={}}
          local world={name="player"};game={forces={player=world}}
          actor.frames=function()return source_frame()end
          assert(not pcall(actor.on_finished,{research={name="foreign",force=world},by_script=true,tick=1}))
          actor.on_finished{research={name=id.gate,force=world},by_script=true,tick=1}
          assert(#storage.worker_storage_default_native_fixture.administrative==1)
          assert(#storage.worker_storage_default_native_fixture.ordinary==0)
        ''')

    def test_no_source_or_mir_storage_import_and_no_research_grants_in_cold(self):
        text = (FIXTURE / "control.lua").read_text()
        self.assertNotIn('require("runtime.', text)
        self.assertNotIn("storage.mir", text)
        self.assertNotRegex(text, r"game\.speed\s*=(?!=)")
        cold = text.split("function M.cold()", 1)[1].split("function M.on_configuration_changed", 1)[0]
        for forbidden in ("server_save", "research_queue =", "researched =", "insert{", "saved_progress ="):
            self.assertNotIn(forbidden, cold)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerStorageDefaultNativeTests))
    sys.exit(0 if result.wasSuccessful() else 1)

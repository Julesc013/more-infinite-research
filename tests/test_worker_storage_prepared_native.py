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

    def install_prepared_successor_harness(self):
        self.lua.execute(r'''
          function install_prepared_successor_harness()
            settings.startup['worker-default-native-scenario']={value='prepared-default'}
            script.active_mods={base='2.1.23',['more-infinite-research']='5.0.21015',
              ['mir-worker-storage-default-native']='0.1.0'}
            local before=source_frame();before[1].queue={actor.ids.main,actor.ids.main,actor.ids.queued}
            local indices={11,22,33,44};local forces={}
            for i,frame in ipairs(before)do
              frame.index=indices[i]
              forces[frame.name]={name=frame.name,index=indices[i],valid=true,
                worker_robots_storage_bonus=frame.bonus}
            end
            forces.neutral={name='neutral',index=90,valid=true,worker_robots_storage_bonus=0}
            local function inventory()
              local counts={}
              return {get_item_count=function(name)return counts[name]or 0 end,
                insert=function(stack)counts[stack.name]=(counts[stack.name]or 0)+stack.count;return stack.count end,
                is_empty=function()return next(counts)==nil end}
            end
            local function lab(role,unit)
              local input,modules=inventory(),inventory()
              return {valid=true,name='mir-worker-default-native-lab',force=forces[role],unit_number=unit,
                disabled_by_script=true,prototype={get_researching_speed=function(quality)assert(quality=='normal');return 3600 end},
                get_inventory=function(kind)return kind==defines.inventory.lab_input and input or modules end}
            end
            local labs={player=lab('player',101),['mir-worker-default-unpaid']=lab('mir-worker-default-unpaid',404)}
            local function lab_frame(role)
              local l=labs[role];local input=l.get_inventory(defines.inventory.lab_input);local packs={}
              for _,pack in ipairs{'automation-science-pack','logistic-science-pack','chemical-science-pack',
                'production-science-pack','utility-science-pack'}do packs[pack]=input.get_item_count(pack)end
              return {name=l.name,unit=l.unit_number,force={name=l.force.name,index=l.force.index},disabled=l.disabled_by_script,
                inventory=packs}
            end
            local function bonus_map()
              local out={};for _,force in pairs(forces)do out[tostring(force.index)]=force.worker_robots_storage_bonus end;return out
            end
            local ingredients={}
            local prerequisites={'worker-robots-storage-2','worker-robots-storage-3','automation-science-pack',
              'logistic-science-pack','chemical-science-pack','production-science-pack','utility-science-pack'}
            for _,name in ipairs{'automation-science-pack','logistic-science-pack','chemical-science-pack',
              'production-science-pack','utility-science-pack'}do ingredients[#ingredients+1]={name=name,amount=1}end
            local function contract(id,modifier,hidden,enabled)
              return {name=id,level=4,max_level=4294967295,hidden=hidden,enabled=enabled,visible_when_disabled=false,
                effects={{type='worker-robot-storage',modifier=modifier}},research_unit_count_formula='675*1.5^(L-4)',
                research_unit_energy=3600,research_unit_count=675,ignore_tech_cost_multiplier=false,
                prerequisites=deep(prerequisites),research_unit_ingredients=deep(ingredients)}
            end
            prototypes={technology={
              [actor.ids.main]=contract(actor.ids.main,1,false,true),
              [actor.ids.private]=contract(actor.ids.private,1,true,false),
              [actor.ids.tail]=contract(actor.ids.tail,1,false,true),
              [actor.ids.gate]={name=actor.ids.gate,level=4,max_level=4294967295,hidden=true,enabled=false,
                visible_when_disabled=false,effects={{type='worker-robot-storage',modifier=-1}},research_unit_count=1,
                research_unit_energy=60,ignore_tech_cost_multiplier=true,prerequisites={},research_unit_ingredients={}}},
              get_history=function(kind,id)return{created='more-infinite-research'}end}
            frames=actor.expected_upgrade(before);actor.frames=function()return frames end
            game={tick=0,forces=forces,speed=1,difficulty_settings={technology_price_multiplier=1},
              is_multiplayer=function()return true end,server_save=function(name)saved[#saved+1]=name end}
            storage={worker_prepared_default_native_fixture={fixture_scenario='prepared-default',phase='prepared-saved',
              labs=labs,inserted={player={},['mir-worker-default-unpaid']={}},ordinary={},administrative={},
              before_preparation=deep(before),closed=prepared.expected_prepared(before),closed_bonuses=bonus_map(),
              closed_labs={player=lab_frame('player'),['mir-worker-default-unpaid']=lab_frame('mir-worker-default-unpaid')}}}
            written={};saved={};prepared_event={mod_changes={['more-infinite-research']={old_version='5.0.21011',new_version='5.0.21015'}},
              mod_startup_settings_changed=false}
          end
        ''')
        self.lua.execute("install_prepared_successor_harness()")

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
          local paid=prepared.expected_completion(first,1,first[1].index)
          actor.same(first,original)
          assert(paid[1].rows[actor.ids.tail].level==9 and paid[1].rows[actor.ids.tail].count==5125)
          assert(paid[1].bonus==source[1].bonus+1 and paid[1].current==actor.ids.tail and paid[1].progress==0)
          actor.same(paid[1].queue,{actor.ids.tail,actor.ids.queued})
          for i=2,4 do actor.same(first[i],paid[i])end
          local unpaid=prepared.expected_completion(paid,4,paid[4].index)
          assert(unpaid[4].rows[actor.ids.tail].level==5 and unpaid[4].bonus==source[4].bonus+1)
          assert(unpaid[4].current==nil and #unpaid[4].queue==0 and unpaid[4].progress==0)
          for i=1,3 do actor.same(paid[i],unpaid[i])end
          assert(math.ceil(3417*(1-.42))==1982 and math.ceil(675*(1-.37))==426)
          unpaid[4].current=actor.ids.queued
          assert(not pcall(prepared.expected_completion,unpaid,4,unpaid[4].index))
          assert(not pcall(prepared.expected_completion,paid,4,4))
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

    def test_full_bound_actor_rejects_bonus_lab_scenario_and_prototype_drift_before_writes(self):
        self.install_prepared_successor_harness()
        self.lua.execute(r'''
          local callbacks=prepared.bind(actor)
          game.forces.neutral.worker_robots_storage_bonus=.25
          assert(not pcall(callbacks.on_configuration_changed,prepared_event)and #written==0)

          for _,change in ipairs({function()prototypes.technology[actor.ids.tail].enabled=false end,
            function()table.remove(prototypes.technology[actor.ids.main].prerequisites)end})do
            install_prepared_successor_harness();callbacks=prepared.bind(actor);change()
            assert(not pcall(callbacks.on_configuration_changed,prepared_event)and #written==0)
          end

          install_prepared_successor_harness();callbacks=prepared.bind(actor)
          callbacks.on_configuration_changed(prepared_event)
          local s=storage.worker_prepared_default_native_fixture;local writes=#written
          s.labs['mir-worker-default-unpaid'].disabled_by_script=false
          assert(not pcall(callbacks.on_tick)and s.phase=='successor-ready'
            and s.labs['mir-worker-default-unpaid'].disabled_by_script==false and #written==writes)

          for _,change in ipairs({function(s)s.labs['mir-worker-default-unpaid'].unit_number=405 end,
            function(s)s.labs['mir-worker-default-unpaid'].get_inventory(defines.inventory.lab_input).insert{
              name='automation-science-pack',count=1}end})do
            install_prepared_successor_harness();callbacks=prepared.bind(actor);callbacks.on_configuration_changed(prepared_event)
            s=storage.worker_prepared_default_native_fixture;writes=#written;change(s)
            assert(not pcall(callbacks.on_tick)and s.phase=='successor-ready'and #written==writes)
          end

          install_prepared_successor_harness();callbacks=prepared.bind(actor);writes=#written
          settings.startup['worker-default-native-scenario'].value='legacy'
          assert(not pcall(callbacks.on_configuration_changed,prepared_event)and #written==writes)

          install_prepared_successor_harness();callbacks=prepared.bind(actor);writes=#written
          storage.worker_prepared_default_native_fixture.fixture_scenario='legacy'
          assert(not pcall(callbacks.on_tick)and #written==writes)

          settings.startup['worker-default-native-scenario'].value='legacy';storage={worker_storage_default_native_fixture={fixture_scenario='prepared-default'}}
          writes=#written;assert(not pcall(actor.on_tick)and #written==writes)
        ''')

    def test_full_bound_actor_uses_live_force_indices_and_preserves_stopped_labs_through_cold(self):
        self.install_prepared_successor_harness()
        self.lua.execute(r'''
          local callbacks=prepared.bind(actor);callbacks.on_configuration_changed(prepared_event);callbacks.on_tick()
          local s=storage.worker_prepared_default_native_fixture
          assert(s.phase=='research'and s.role=='player'and s.frame_ordinal==1 and s.force_index==11
            and s.labs.player.disabled_by_script==false and s.labs['mir-worker-default-unpaid'].disabled_by_script==true)
          frames=prepared.expected_completion(frames,1,11);game.forces.player.worker_robots_storage_bonus=8
          callbacks.on_finished{research={name=actor.ids.tail,force=game.forces.player},by_script=false,tick=1}
          assert(s.labs.player.disabled_by_script==true and s.callback_bonuses['11']==8 and s.callback_bonuses['1']==nil)
          for _,pack in ipairs{'automation-science-pack','logistic-science-pack','chemical-science-pack',
            'production-science-pack','utility-science-pack'}do s.inserted.player[pack]=1982 end
          callbacks.on_tick()
          assert(s.phase=='research'and s.role=='mir-worker-default-unpaid'and s.frame_ordinal==4 and s.force_index==44
            and s.labs.player.disabled_by_script==true and s.labs['mir-worker-default-unpaid'].disabled_by_script==false)
          frames=prepared.expected_completion(frames,4,44);game.forces['mir-worker-default-unpaid'].worker_robots_storage_bonus=4
          callbacks.on_finished{research={name=actor.ids.tail,force=game.forces['mir-worker-default-unpaid']},by_script=false,tick=2}
          for _,pack in ipairs{'automation-science-pack','logistic-science-pack','chemical-science-pack',
            'production-science-pack','utility-science-pack'}do s.inserted['mir-worker-default-unpaid'][pack]=426 end
          callbacks.on_tick()
          assert(s.phase=='successor-saved'and s.closed_bonuses['11']==8 and s.closed_bonuses['44']==4
            and s.closed_bonuses['90']==0 and s.labs.player.disabled_by_script and s.labs['mir-worker-default-unpaid'].disabled_by_script)
          callbacks.on_load();callbacks.on_tick()
          assert(s.phase=='successor-saved'and #s.ordinary==2 and #saved==1)
        ''')


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir",type=Path,required=True)
    args=parser.parse_args();sys.path.insert(0,str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

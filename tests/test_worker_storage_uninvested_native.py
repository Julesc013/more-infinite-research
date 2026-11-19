"""Host controls for the empty p4.7 -> published11 worker-storage actor; no native result."""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/worker-storage-uninvested-native"


class WorkerStorageUninvestedNativeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.lua.execute(r'''
          handlers, logs, written, markers, storage = {}, {}, {}, {}, {}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1,lab_modules=2}}
          script={active_mods={},on_init=function(fn)handlers.init=fn end,on_load=function(fn)handlers.load=fn end,
            on_configuration_changed=function(fn)handlers.configuration=fn end,on_event=function(id,fn)handlers[id]=fn end}
          remote={add_interface=function()end};log=function(value)logs[#logs+1]=value end
          function deep(value)if type(value)~="table"then return value end local out={}
            for key,item in pairs(value)do out[key]=deep(item)end return out end
          function same(left,right)
            if type(left)~=type(right)then return false end;if type(left)~="table"then return left==right end
            for key,value in pairs(left)do if not same(value,right[key])then return false end end
            for key in pairs(right)do if left[key]==nil then return false end end;return true
          end
          capture_body_by_reference=false
          helpers={table_to_json=function(body)
              markers[#markers+1]=capture_body_by_reference and body or deep(body);return "{}"end,
            write_file=function(path,text,append)written[#written+1]={path=path,text=text,append=append}end}
           function tech(name, level, readonly, on_researched)
            local values={name=name,valid=true,level=level or 1,researched=false,enabled=true,
              visible_when_disabled=false,saved_progress=0,research_unit_count=100,prerequisites={}}
             local function assign(key, value)
               if key=="researched" and value==true and values.researched==false and on_researched~=nil then on_researched() end
               values[key]=value
             end
            values.research_recursive=function()
               assign("researched",true);values.enabled=true
              if recursive_trap~=nil then recursive_trap.researched=true end
            end
             values.native_set=function(key,value)assign(key,value)end
            local proxy={};setmetatable(proxy,{__index=function(_,key)
                if key=="saved_progress" and values.name=="logistics" and source_saved_readback~=nil then return source_saved_readback end
                return values[key]end,
              __newindex=function(_,key,value)
                 if readonly then error("worker C4 write before ordinary completion: "..key) end;assign(key,value)
              end})
            return proxy
          end
          function make_force(name,index)
             local technologies={}
             local values={name=name,index=index,valid=true,technologies=technologies,research_enabled=true,research_progress=0,
              worker_robots_storage_bonus=0,worker_robots_speed_modifier=0,research_queue={}}
             local function researched_effect(technology_name)
               return function()
                 local amount=researched_bonus_effects[technology_name] or 0
                 values.worker_robots_storage_bonus=values.worker_robots_storage_bonus+amount
               end
             end
             technologies["worker-robots-storage-4"]=tech("worker-robots-storage-4",4,true)
             technologies["worker-robots-storage-2"]=tech("worker-robots-storage-2",2,false,researched_effect("worker-robots-storage-2"))
             technologies["worker-robots-storage-3"]=tech("worker-robots-storage-3",3,false,researched_effect("worker-robots-storage-3"))
             technologies["worker-robots-storage-2"].native_set("research_unit_count",300)
             technologies["worker-robots-storage-3"].native_set("research_unit_count",450)
             technologies["steam-power"]=tech("steam-power",1,false,researched_effect("steam-power"))
             technologies.electronics=tech("electronics",1,false,researched_effect("electronics"))
             technologies["automation-science-pack"]=tech("automation-science-pack",1,false,researched_effect("automation-science-pack"))
             technologies.automation=tech("automation",1,false,researched_effect("automation"))
             technologies.logistics=tech("logistics",1,false,researched_effect("logistics"))
             technologies["logistic-science-pack"]=tech("logistic-science-pack",1,false,researched_effect("logistic-science-pack"))
             technologies["chemical-science-pack"]=tech("chemical-science-pack",1,false,researched_effect("chemical-science-pack"))
             technologies["production-science-pack"]=tech("production-science-pack",1,false,researched_effect("production-science-pack"))
             technologies["utility-science-pack"]=tech("utility-science-pack",1,false,researched_effect("utility-science-pack"))
             technologies["worker-robots-speed-4"]=tech("worker-robots-speed-4",4,false,researched_effect("worker-robots-speed-4"))
            local force={};setmetatable(force,{__index=function(_,key)
              if key=="current_research"then local first=values.research_queue[1];return first and values.technologies[first.name]or nil end
              if key=="research_progress" and source_progress_readback~=nil then return source_progress_readback end
              if key=="worker_robots_speed_modifier" and source_bonus_readback~=nil then return source_bonus_readback end
              return values[key]
            end,__newindex=function(_,key,value)
              if key=="research_queue"then local rows={};for i,item in ipairs(value)do
                local name=type(item)=="string"and item or item.name;assert(values.technologies[name]);rows[i]=values.technologies[name]end
                values.research_queue=rows
              else values[key]=value end
            end});return force
          end
          function install_candidate(force)
            local ordinary=tech("mir-worker-storage-default-4",4,true)
            ordinary.native_set("research_unit_count",675)
            ordinary.native_set("prerequisites",{
              ["worker-robots-storage-2"]=force.technologies["worker-robots-storage-2"],
              ["worker-robots-storage-3"]=force.technologies["worker-robots-storage-3"],
              ["automation-science-pack"]=force.technologies["automation-science-pack"],
              ["logistic-science-pack"]=force.technologies["logistic-science-pack"],
              ["chemical-science-pack"]=force.technologies["chemical-science-pack"],
              ["production-science-pack"]=force.technologies["production-science-pack"],
              ["utility-science-pack"]=force.technologies["utility-science-pack"],
            })
            force.technologies[ordinary.name]=ordinary
            force.technologies["mir-worker-storage-head-4"]=tech("mir-worker-storage-head-4",4,true)
          end
           function apply_expected_default_transfer()
             local seen={}
             for _,force in pairs(game.forces) do
               if force.valid~=false and not seen[force.index] then
                 seen[force.index]=true
                 local canonical=force.technologies["worker-robots-storage-4"]
                 local ordinary=force.technologies["mir-worker-storage-default-4"]
                 local head=force.technologies["mir-worker-storage-head-4"]
                 local enabled,visible=canonical.enabled,canonical.visible_when_disabled
                 canonical.native_set("enabled",false);canonical.native_set("visible_when_disabled",visible)
                 ordinary.native_set("enabled",enabled);ordinary.native_set("visible_when_disabled",visible)
                 head.native_set("enabled",false);head.native_set("visible_when_disabled",false)
               end
             end
           end
          function make_lab()
            local input={counts={}};function input.get_item_count(name)return input.counts[name]or 0 end
            function input.insert(item)
              local accepted=math.min(item.count,200-(input.counts[item.name]or 0))
              input.counts[item.name]=(input.counts[item.name]or 0)+accepted;return accepted
            end
            local modules={};function modules.is_empty()return true end
            return {valid=true,unit_number=91,disabled_by_script=false,test_input=input,
              prototype={get_researching_speed=function()return 3600 end},
              get_inventory=function(kind)return kind==1 and input or modules end}
          end
          function world(base,mir)
             storage={};markers={};logs={};written={};saved_name=nil;recursive_trap=nil
            source_progress_readback=nil;source_saved_readback=nil;source_bonus_readback=nil;labs_created=0
             researched_bonus_effects={["worker-robots-storage-2"]=1,["worker-robots-storage-3"]=1}
            local player=make_force("player",1);local forces={player=player,[1]=player};local next_index=2
            game={tick=0,forces=forces,surfaces={[1]={create_entity=function(spec)
              assert(spec.name=="mir-worker-uninvested-native-lab"and spec.force==player);labs_created=labs_created+1;return make_lab()end}},
              is_multiplayer=function()return true end,server_save=function(name)saved_name=name end}
            function game.create_force(name)local force=make_force(name,next_index);next_index=next_index+1;forces[name]=force;forces[force.index]=force;return force end
            script.active_mods={base=base,["more-infinite-research"]=mir,["mir-worker-storage-uninvested-native"]="0.13.0"}
          end
          actor=assert(load(actor_source))()
        ''')

    def source_to_middle(self, target):
        base = "2.0.77" if target == "f200" else "2.1.23"
        source = "4.7.20002" if target == "f200" else "4.7.21002"
        published = "5.0.20011" if target == "f200" else "5.0.21011"
        self.lua.globals().world(base, source)
        self.lua.execute(r'''
          handlers.init()
          assert(storage.mir_worker_storage_uninvested_native.phase=="source-ready")
          assert(#markers==2 and markers[1].stage=="source-unaccepted-after-final-setup"
            and markers[1].accepted==false and markers[2].stage=="source-ready")
          script.active_mods["more-infinite-research"]=published_version
          script.active_mods["mir-worker-storage-uninvested-native"]=nil
          -- Actual removal discards the fixture's private storage.  No actor is
          -- invoked during the Base+MIR-only published11 middle selection.
          storage={};assert(next(storage)==nil)
        '''.replace("published_version", repr(published)))

    def candidate_admission(self, target, settings_changed, before_candidate=None):
        self.source_to_middle(target)
        if before_candidate is not None:
            self.lua.execute(before_candidate)
        candidate = "5.0.20017" if target == "f200" else "5.0.21017"
        published = "5.0.20011" if target == "f200" else "5.0.21011"
        self.lua.globals().settings_changed = settings_changed
        self.lua.execute(r'''
          script.active_mods["more-infinite-research"]=candidate_version
          script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
          -- Candidate data identities exist before its first read-only on_init.
          install_candidate(game.forces.player);install_candidate(game.forces["mir-worker-uninvested-native-foreign"])
          handlers.init()
           -- Model only the documented public flag effects of MIR's native
           -- default transfer between the observer's pre-config and config callbacks.
           apply_expected_default_transfer()
          local state=storage.mir_worker_storage_uninvested_native
          assert(state.phase=="candidate-awaiting-config" and state.pre_config~=nil)
          handlers.configuration({mod_startup_settings_changed=settings_changed,mod_changes={
            ["more-infinite-research"]={old_version=published_version,new_version=candidate_version},
            ["mir-worker-storage-uninvested-native"]={new_version="0.13.0"}}})
        '''.replace("candidate_version", repr(candidate)).replace("published_version", repr(published)))

    def test_metadata_and_data_only_define_fixture_lab(self):
        f210 = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        f200 = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        self.assertEqual(("0.13.0", "2.1", ["base >= 2.1.23", "more-infinite-research"]),
                         (f210["version"], f210["factorio_version"], f210["dependencies"]))
        self.assertEqual(("0.13.0", "2.0", ["base >= 2.0.77", "more-infinite-research"]),
                         (f200["version"], f200["factorio_version"], f200["dependencies"]))
        self.lua.globals().data_source = (FIXTURE / "data.lua").read_text(encoding="utf-8")
        self.lua.execute(r'''
          local original={type="lab",name="lab",researching_speed=1,energy_source={type="electric"}}
          data={raw={lab={lab=original}},emitted={}};function data:extend(rows)self.emitted=rows end
          assert(load(data_source))();assert(#data.emitted==1 and data.emitted[1].name=="mir-worker-uninvested-native-lab")
          assert(original.researching_speed==1 and original.energy_source.type=="electric")
        ''')
        control_source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertNotIn("mir_worker_storage_route", control_source)
        self.assertNotIn("storage.mir_", control_source)
        self.assertNotIn("research_recursive()", control_source)

    def test_source_is_removed_for_base_mir_only_published11_middle(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.source_to_middle(target)
                self.lua.execute(r'''
                  assert(script.active_mods["mir-worker-storage-uninvested-native"]==nil and next(storage)==nil)
                  assert(game.forces.player.technologies["worker-robots-storage-4"].level==4)
                  assert(game.forces["mir-worker-uninvested-native-foreign"].technologies["worker-robots-storage-4"].level==4)
                ''')

    def test_source_ready_exports_a_detached_exact_foreign_public_frame(self):
        self.lua.globals().world("2.0.77", "4.7.20002")
        self.lua.execute(r'''
          capture_body_by_reference=true
          handlers.init()
          local state=storage.mir_worker_storage_uninvested_native
          local observed=markers[2].source_foreign
          assert(observed~=false and not rawequal(observed,state.source_foreign))
          assert(observed.current=="automation" and observed.progress==.42
            and #observed.queue==2 and observed.queue[1]=="automation" and observed.queue[2]=="logistics")
          assert(observed.logistics.saved==.27 and observed.disabled.enabled==false
            and observed.disabled.visible==true and observed.bonus==.75)
          assert(observed.rows["steam-power"].researched==true and observed.rows.electronics.researched==true
            and observed.rows["automation-science-pack"].researched==true)
          assert(observed.rows.automation.researched==false and observed.rows.logistics.researched==false
            and observed.rows["worker-robots-speed-4"].level==4)
          observed.rows.automation.saved=99
          assert(state.source_foreign.rows.automation.saved==0)
        ''')

    def test_source_final_setup_diagnostic_precedes_refusal_without_storage_lab_or_save(self):
        self.lua.globals().world("2.0.77", "4.7.20002")
        self.lua.execute(r'''
          source_progress_readback=.4200002
          assert(not pcall(handlers.init))
          assert(storage.mir_worker_storage_uninvested_native==nil and labs_created==0 and saved_name==nil)
          assert(#markers==1 and markers[1].stage=="source-unaccepted-after-final-setup" and markers[1].accepted==false)
          local observed=markers[1]
          assert(observed.current=="automation" and observed.expected_current=="automation")
          assert(observed.progress==.4200002 and observed.progress_text==string.format("%.17g",.4200002))
          assert(observed.expected_progress==.42 and observed.expected_progress_text==string.format("%.17g",.42))
          assert(observed.research_queue_enabled.supported==false
            and observed.research_queue_enabled.reason=="not-declared-2.0.77-runtime-api")
          assert(observed.research_enabled.supported==true and observed.research_enabled.value==true)
          assert(#written==1 and written[1].path=="worker-storage-uninvested-native/source-unaccepted-after-final-setup.json")
        ''')

    def test_source_fraction_rounding_is_bounded_but_real_fraction_or_bonus_drift_refuses(self):
        for progress, saved in ((".42+5e-8", ".27+5e-8"),):
            with self.subTest(progress=progress, saved=saved):
                self.lua.globals().world("2.0.77", "4.7.20002")
                self.lua.execute("source_progress_readback=" + progress + ";source_saved_readback=" + saved + r'''
                  handlers.init()
                  assert(storage.mir_worker_storage_uninvested_native.phase=="source-ready" and #markers==2)
                ''')
        for assignment in ("source_progress_readback=.42+1.1e-7", "source_saved_readback=.27+1.1e-7",
                           "source_bonus_readback=.75+1e-9"):
            with self.subTest(assignment=assignment):
                self.lua.globals().world("2.0.77", "4.7.20002")
                self.lua.execute(assignment + r'''
                  assert(not pcall(handlers.init))
                  assert(storage.mir_worker_storage_uninvested_native==nil and #markers==1)
                  assert(markers[1].stage=="source-unaccepted-after-final-setup")
                ''')

    def test_candidate_trigger_arms_preserve_foreign_rows_then_complete_save_and_two_colds(self):
        for target in ("f200", "f210"):
            for settings_changed in (False, True):
                with self.subTest(target=target, settings_changed=settings_changed):
                    self.candidate_admission(target, settings_changed)
                    trigger = "startup-settings-plus-fixture-addition" if settings_changed else "fixture-addition"
                    self.lua.globals().expected_trigger = trigger
                    self.lua.execute(r'''
                      local state=storage.mir_worker_storage_uninvested_native
                      assert(state.phase=="candidate-admitted" and state.candidate_event.trigger==expected_trigger)
                      assert(state.candidate_event.startup_settings_changed==settings_changed and #state.candidate_event.mod_changes==2)
                       local flags=state.candidate_event.worker_flag_transitions
                       assert(flags["1"].canonical.before.enabled==true and flags["1"].canonical.after.enabled==false)
                       assert(flags["1"].ordinary.after.enabled==flags["1"].canonical.before.enabled
                         and flags["1"].ordinary.after.visible==flags["1"].canonical.before.visible)
                       assert(flags["1"].head.after.enabled==false and flags["1"].head.after.visible==false)
                       assert(flags["2"].canonical.after.enabled==false
                         and flags["2"].ordinary.after.enabled==flags["2"].canonical.before.enabled
                         and flags["2"].ordinary.after.visible==flags["2"].canonical.before.visible
                         and flags["2"].head.after.enabled==false and flags["2"].head.after.visible==false)
                      assert(state.pre_config.worker_frames["1"].name=="player"
                        and state.pre_config.worker_frames["2"].name=="mir-worker-uninvested-native-foreign")
                      local fixture_change,mir_change=state.candidate_event.mod_changes[1],state.candidate_event.mod_changes[2]
                      assert(fixture_change.name=="mir-worker-storage-uninvested-native" and fixture_change.old_version_present==false
                        and fixture_change.new_version=="0.13.0")
                      assert(mir_change.name=="more-infinite-research" and mir_change.old_version_present==true
                        and mir_change.new_version==script.active_mods["more-infinite-research"])
                      handlers[1]();assert(state.phase=="ordinary-active" and state.lab~=nil)
                      local prefix=state.ordinary_prefix
                      assert(prefix.before.bonus==0 and prefix.after.bonus==2
                        and prefix.expected_delta==2 and prefix.observed_delta==2 and #prefix.rows==2)
                      for index,name in ipairs({"worker-robots-storage-2","worker-robots-storage-3"}) do
                        local item=prefix.rows[index]
                        assert(item.name==name and item.before.researched==false and item.after.researched==true
                          and item.newly_researched==true and #item.effects==1
                          and item.effects[1].type=="worker-robot-storage" and item.effects[1].modifier==1
                          and item.before.level==index+1 and item.after.level==index+1
                          and item.before.count==({300,450})[index] and item.after.count==({300,450})[index]
                          and item.before.enabled==item.after.enabled and item.before.visible==item.after.visible
                          and item.before.saved==0 and item.after.saved==0)
                      end
                      local player=game.forces.player
                      assert(player.current_research.name=="mir-worker-storage-default-4")
                      player.technologies["mir-worker-storage-default-4"].native_set("level",5)
                      player.worker_robots_storage_bonus=3
                      handlers[2]({research={name="mir-worker-storage-default-4",force=player},by_script=false,tick=10})
                      assert(state.phase=="ordinary-finished");handlers[1]()
                      assert(state.phase=="ordinary-saved" and saved_name=="worker-storage-uninvested-native")
                      local before=deep(storage)
                      for _=1,2 do
                        local saved_game,saved_storage=game,storage
                        game=setmetatable({}, {__index=function()error("on_load read game")end,
                          __newindex=function()error("on_load wrote game")end})
                        storage=setmetatable({}, {__index=function()error("on_load read storage")end,
                          __newindex=function()error("on_load wrote storage")end})
                        handlers.load()
                        game,storage=saved_game,saved_storage
                        handlers[1]();assert(same(before,storage))
                      end
                      assert(markers[#markers].stage=="cold" and markers[#markers].ordinary_prefix.expected_delta==2
                        and markers[#markers].ordinary_prefix.observed_delta==2)
                    ''')

    def test_ordinary_prefix_effect_receipt_allows_an_already_researched_prefix_once(self):
        self.candidate_admission("f200", False, r'''
          local player=game.forces.player
          player.technologies["worker-robots-storage-2"].researched=true
          assert(player.worker_robots_storage_bonus==1)
        ''')
        self.lua.execute(r'''
          handlers[1]()
          local prefix=storage.mir_worker_storage_uninvested_native.ordinary_prefix
          assert(prefix.before.bonus==1 and prefix.after.bonus==2)
          assert(prefix.rows[1].before.researched==true and prefix.rows[1].after.researched==true
            and prefix.rows[1].newly_researched==false)
          assert(prefix.rows[2].before.researched==false and prefix.rows[2].after.researched==true
            and prefix.rows[2].newly_researched==true)
          assert(prefix.expected_delta==1 and prefix.observed_delta==1)
        ''')

    def test_ordinary_prefix_effect_refuses_wrong_or_unexpected_native_grant_before_lab(self):
        cases = {
            "wrong-prefix-effect": 'researched_bonus_effects["worker-robots-storage-2"]=2',
            "unexpected-science-grant": 'researched_bonus_effects["automation-science-pack"]=1',
        }
        for name, mutation in cases.items():
            with self.subTest(name=name):
                self.candidate_admission("f200", False)
                self.lua.execute(r'''
                  local state=storage.mir_worker_storage_uninvested_native
                  local markers_before,writes_before=#markers,#written
                ''' + mutation + r'''
                  assert(not pcall(handlers[1]))
                  assert(state.phase=="candidate-admitted" and state.lab==nil)
                  assert(#markers==markers_before and #written==writes_before)
                ''')

    def test_ordinary_prefix_snapshot_refuses_a_change_before_config_or_work(self):
        for mutation in ('player.technologies["worker-robots-storage-2"].researched=true',
                         'player.technologies["worker-robots-storage-3"].enabled=false'):
            with self.subTest(mutation=mutation):
                self.source_to_middle("f200")
                self.lua.execute(r'''
                  script.active_mods["more-infinite-research"]="5.0.20017"
                  script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
                  local player=game.forces.player;local foreign=game.forces["mir-worker-uninvested-native-foreign"]
                  install_candidate(player);install_candidate(foreign);handlers.init()
                ''' + mutation + r'''
                  apply_expected_default_transfer()
                  local state=storage.mir_worker_storage_uninvested_native;local markers_before,writes_before=#markers,#written
                  assert(not pcall(function() handlers.configuration({mod_startup_settings_changed=false,mod_changes={
                    ["more-infinite-research"]={old_version="5.0.20011",new_version="5.0.20017"},
                    ["mir-worker-storage-uninvested-native"]={new_version="0.13.0"}}}) end))
                  assert(state.phase=="candidate-awaiting-config" and #markers==markers_before and #written==writes_before)
                ''')
                self.candidate_admission("f200", False)
                self.lua.execute(r'''
                  local state=storage.mir_worker_storage_uninvested_native;local player=game.forces.player
                ''' + mutation + r'''
                  local markers_before,writes_before=#markers,#written
                  assert(not pcall(handlers[1]))
                  assert(state.phase=="candidate-admitted" and state.lab==nil
                    and #markers==markers_before and #written==writes_before)
                ''')

    def test_post_source_drift_refuses_before_candidate_observation_or_worker_write(self):
        for mutation in ('foreign.research_queue={"logistics"}',
                         'foreign.technologies["worker-robots-speed-4"].enabled=true',
                         'foreign.technologies["automation-science-pack"].researched=false'):
            with self.subTest(mutation=mutation):
                self.source_to_middle("f200")
                self.lua.execute(r'''
                  local foreign=game.forces["mir-worker-uninvested-native-foreign"]
                ''' + mutation + r'''
                  script.active_mods["more-infinite-research"]="5.0.20017"
                  script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
                  local count=#markers;assert(not pcall(handlers.init));assert(#markers==count and next(storage)==nil)
                  assert(game.forces.player.technologies["worker-robots-storage-4"].level==4)
                ''')

    def test_candidate_transfer_refuses_any_nonflag_work_or_foreign_mutation(self):
        cases = {
            "bonus": 'game.forces.player.worker_robots_storage_bonus=1',
            "queue": 'game.forces.player.research_queue={"worker-robots-storage-4"}',
            "work": 'game.forces.player.technologies["worker-robots-storage-4"].native_set("level",5)',
            "foreign-flag": 'game.forces["mir-worker-uninvested-native-foreign"].technologies.automation.native_set("enabled",false)',
        }
        for name, mutation in cases.items():
            with self.subTest(name=name):
                self.source_to_middle("f200")
                self.lua.execute(r'''
                  script.active_mods["more-infinite-research"]="5.0.20017"
                  script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
                  install_candidate(game.forces.player);install_candidate(game.forces["mir-worker-uninvested-native-foreign"])
                  handlers.init();apply_expected_default_transfer()
                  local state=storage.mir_worker_storage_uninvested_native;local count=#markers
                ''' + mutation + r'''
                  assert(not pcall(function() handlers.configuration({mod_startup_settings_changed=false,mod_changes={
                    ["more-infinite-research"]={old_version="5.0.20011",new_version="5.0.20017"},
                    ["mir-worker-storage-uninvested-native"]={new_version="0.13.0"}}}) end))
                  assert(state.phase=="candidate-awaiting-config" and #markers==count)
                ''')

    def test_ordinary_start_refuses_an_unexpected_prerequisite_set_before_lab_or_queue_write(self):
        self.candidate_admission("f200", False)
        self.lua.execute(r'''
          local state=storage.mir_worker_storage_uninvested_native;local player=game.forces.player
          player.technologies["mir-worker-storage-default-4"].native_set("prerequisites",{})
          local markers_before,writes_before=#markers,#written
          assert(not pcall(handlers[1]))
          assert(state.phase=="candidate-admitted" and state.lab==nil)
          assert(#markers==markers_before and #written==writes_before)
          assert(player.technologies["worker-robots-storage-4"].level==4)
        ''')

    def test_ordinary_direct_prerequisite_writes_do_not_traverse_an_unlisted_technology(self):
        self.candidate_admission("f200", False)
        self.lua.execute(r'''
          local player=game.forces.player
          local unlisted=tech("unlisted-base-ancestor",1,false)
          player.technologies[unlisted.name]=unlisted
          recursive_trap=unlisted
          handlers[1]()
          assert(storage.mir_worker_storage_uninvested_native.phase=="ordinary-active")
          assert(unlisted.researched==false)
        ''')

    def test_ordinary_science_refills_to_actual_capacity_and_stops_after_completion(self):
        self.candidate_admission("f200", False)
        self.lua.execute(r'''
          handlers[1]()
          local state=storage.mir_worker_storage_uninvested_native;local player=game.forces.player
          local input=state.lab.test_input
          assert(player.technologies["mir-worker-storage-default-4"].research_unit_count==675)
          for _,pack in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack"}) do
            assert(input.counts[pack]==200 and state.inserted[pack]==200)
            for _=1,4 do input.counts[pack]=63;handlers[1]();assert(input.counts[pack]==200) end
            assert(state.inserted[pack]==748 and state.inserted[pack]>=675)
          end
          player.technologies["mir-worker-storage-default-4"].native_set("level",5);player.worker_robots_storage_bonus=3
          handlers[2]({research={name="mir-worker-storage-default-4",force=player},by_script=false,tick=10})
          local inserted_before=deep(state.inserted)
          for _,pack in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack"}) do input.counts[pack]=63 end
          handlers[1]()
          assert(state.phase=="ordinary-saved" and same(inserted_before,state.inserted))
        ''')

    def test_candidate_refuses_an_invested_third_force_before_marker_or_fixture_write(self):
        self.source_to_middle("f200")
        self.lua.execute(r'''
          script.active_mods["more-infinite-research"]="5.0.20017"
          script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
          local third=game.create_force("mir-worker-uninvested-native-third")
          install_candidate(game.forces.player);install_candidate(game.forces["mir-worker-uninvested-native-foreign"]);install_candidate(third)
          third.technologies["worker-robots-storage-4"].native_set("researched",true)
          local marker_count,write_count=#markers,#written
          assert(not pcall(handlers.init))
          assert(next(storage)==nil and #markers==marker_count and #written==write_count)
        ''')

    def test_candidate_serializes_an_uninvested_third_force_in_the_all_worker_map(self):
        self.source_to_middle("f200")
        self.lua.execute(r'''
          script.active_mods["more-infinite-research"]="5.0.20017"
          script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
          local third=game.create_force("mir-worker-uninvested-native-third")
          install_candidate(game.forces.player);install_candidate(game.forces["mir-worker-uninvested-native-foreign"]);install_candidate(third)
          handlers.init();apply_expected_default_transfer()
          local state=storage.mir_worker_storage_uninvested_native
          assert(state.pre_config.worker_frames["3"].name=="mir-worker-uninvested-native-third")
          assert(markers[#markers].worker_frames["3"].name=="mir-worker-uninvested-native-third")
          handlers.configuration({mod_startup_settings_changed=false,mod_changes={
            ["more-infinite-research"]={old_version="5.0.20011",new_version="5.0.20017"},
            ["mir-worker-storage-uninvested-native"]={new_version="0.13.0"}}})
          local flags=state.candidate_event.worker_flag_transitions["3"]
          assert(flags.canonical.after.enabled==false
            and flags.ordinary.after.enabled==flags.canonical.before.enabled
            and flags.ordinary.after.visible==flags.canonical.before.visible
            and flags.head.after.enabled==false and flags.head.after.visible==false)
        ''')

    def test_candidate_refuses_invested_or_queued_head_before_marker_or_fixture_write(self):
        for mutation in ('head.native_set("researched",true)', 'player.research_queue={"mir-worker-storage-head-4"}'):
            with self.subTest(mutation=mutation):
                self.source_to_middle("f200")
                self.lua.execute(r'''
                  script.active_mods["more-infinite-research"]="5.0.20017"
                  script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
                  local player=game.forces.player;local foreign=game.forces["mir-worker-uninvested-native-foreign"]
                  install_candidate(player);install_candidate(foreign)
                  local head=player.technologies["mir-worker-storage-head-4"]
                ''' + mutation + r'''
                  local marker_count,write_count=#markers,#written
                  assert(not pcall(handlers.init))
                  assert(next(storage)==nil and #markers==marker_count and #written==write_count)
                ''')

    def test_candidate_init_reads_candidate_pair_without_reseeding(self):
        self.source_to_middle("f200")
        self.lua.execute(r'''
          script.active_mods["more-infinite-research"]="5.0.20017";script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
          install_candidate(game.forces.player);install_candidate(game.forces["mir-worker-uninvested-native-foreign"])
          handlers.init();assert(storage.mir_worker_storage_uninvested_native.phase=="candidate-awaiting-config")
          assert(game.forces.player.technologies["worker-robots-storage-4"].level==4)
        ''')

    def test_exact_old16_added_mod_role_is_passive_before_mir_history_validation(self):
        for target, old16 in (("f200", "5.0.20016"), ("f210", "5.0.21016")):
            with self.subTest(target=target):
                self.source_to_middle(target)
                self.lua.globals().old16 = old16
                self.lua.execute(r'''
                  script.active_mods["more-infinite-research"]=old16
                  script.active_mods["mir-worker-storage-uninvested-native"]="0.13.0"
                  local player=game.forces.player;local foreign=game.forces["mir-worker-uninvested-native-foreign"]
                  local markers_before,writes_before=#markers,#written
                  handlers.init()
                  handlers.configuration({mod_startup_settings_changed=false,mod_changes={
                    ["more-infinite-research"]={old_version=script.active_mods.base=="2.0.77"and"5.0.20011"or"5.0.21011",new_version=old16},
                    ["mir-worker-storage-uninvested-native"]={new_version="0.13.0"}}})
                  handlers[1]()
                  assert(next(storage)==nil and #markers==markers_before and #written==writes_before)
                  assert(player.technologies["worker-robots-storage-4"].level==4
                    and foreign.technologies["worker-robots-storage-4"].level==4)
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerStorageUninvestedNativeTests))
    sys.exit(0 if result.wasSuccessful() else 1)

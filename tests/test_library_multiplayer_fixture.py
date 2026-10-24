"""Host controls for the private F200 two-client Library fixture, not native evidence."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-multiplayer"
CONTROL = FIXTURE / "control.lua"
PROFILE = ROOT / "tests/profiles/library-multiplayer-f200-2077.json"
WRAPPER = ROOT / "tools/Invoke-MultiplayerFixture.ps1"
SESSION = ROOT / "tools/Invoke-MultiplayerSession.ps1"
MEMORY_CALIBRATION = ROOT / "spec/evidence/library-multiplayer-session-memory-calibration-r01.json"


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("fixture result is cyclic")
    seen.add(id(value))
    entries = list(value.items())
    keys = [key for key, _ in entries]
    if keys and all(isinstance(key, int) and key >= 1 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in entries}
    seen.remove(id(value))
    return result


class LibraryMultiplayerFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().control_path = CONTROL.as_posix()
        self.lua.execute(r'''
          function run_library_multiplayer_fixture(path, opponent)
            local ROOT_NAME="mir_research_browser"
            local FILTERS="mir_library_filters"
            local QUERY="mir_library_query"
            local SORT="mir_library_sort"
            local TABS="mir_library_tabs"
            local CONTENT="mir_library_research_content"
            local RESULTS="mir_library_results"
            local DETAIL="mir_library_detail"
            local DETAIL_TITLE="mir_library_detail_title"
            local AVAILABILITY={"mir_library_availability_1","mir_library_availability_2"}
            local AVAILABILITY_FAMILIES={"research_agricultural_growth_speed","research_spoilage_preservation"}
            local key="mir5_library_multiplayer"
            local gear="recipe-prod-research_gears-1"
            local mining="recipe-prod-research_mining_drill-1"
            local players, markers, screenshots, saves = {}, {}, {}, {}
            local force={valid=true,index=1,name="player",technologies={},recipes={},research_queue={},research_progress=0}
            for _,name in ipairs({gear,mining}) do
              force.technologies[name]={valid=true,name=name,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,
                research_unit_count=1,research_unit_energy=60,
                prototype={effects={{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}}}
            end
            for _,name in ipairs({"iron-gear-wheel","burner-mining-drill","electric-mining-drill"}) do
              force.recipes[name]={valid=true,name=name,productivity_bonus=0}
            end
            for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}) do
              force.technologies[name]={valid=true,name=name,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false}
            end
            local function player(index, locale)
              local value={valid=true,index=index,name=index==1 and "MIR5English" or "MIR5Deutsch",locale=locale,connected=false,force=force,gui={screen={valid=true,type="screen"}}}
              players[index]=value
              return value
            end
            local en,de=player(1,"en"),player(2,opponent=="locale" and "fr" or "de")
            local storage={}
            local callbacks={events={}}
            local next_profiler=0
            local profiler_logs={}
            local game={forces={player=force},surfaces={[1]={valid=true,index=1}},tick=0}
            local function fire(name,event)
              local callback=callbacks.events[name]
              if callback then
                local ok,message=pcall(callback,event)
                if not ok then error(message,0) end
              end
            end
            force.add_research=function(technology)
              if opponent=="missing-queue" and #force.research_queue>=1 then return true end
              force.research_queue[#force.research_queue+1]=technology
              if force.current_research==nil then
                force.current_research=technology
                fire(4,{research=technology})
              end
              return true
            end
            force.cancel_current_research=function()
              local cancelled=force.current_research
              force.current_research=nil;force.research_queue={};force.research_progress=0
              fire(7,{force=force,research={[gear]=cancelled and 1 or 0}})
            end
            game.get_player=function(index) return players[index] end
            force.get_spawn_position=function(surface) return {0,0} end
            local inventory={counts={}}
            inventory.insert=function(spec)
              inventory.counts[spec.name]=(inventory.counts[spec.name] or 0)+spec.count
              return spec.count
            end
            inventory.get_item_count=function(name) return inventory.counts[name] or 0 end
            local lab={valid=true,energy=0}
            lab.get_inventory=function(index) assert(index==1);return inventory end
            game.surfaces[1].create_entity=function(spec)
              assert(spec.name=="lab" and spec.force==force)
              return lab
            end
            game.create_force=function(name)
              local foreign={valid=true,index=2,name=name,technologies={},recipes={},research_queue={},research_progress=0}
              for _,tech_name in ipairs({gear,mining}) do
                foreign.technologies[tech_name]={valid=true,name=tech_name,force=foreign,level=1,researched=false,enabled=true,
                  visible_when_disabled=false}
              end
              foreign.recipes["iron-gear-wheel"]={valid=true,name="iron-gear-wheel",productivity_bonus=0}
              fire(8,{force=opponent=="wrong-force-event" and force or foreign})
              if opponent=="foreign-force-gui" then en.gui.screen[ROOT_NAME]={valid=true,type="frame",visible=true} end
              return foreign
            end
            game.create_profiler=function(stopped)
              next_profiler=next_profiler+1
              local result={valid=true,stopped=stopped,ordinal=next_profiler}
              result.restart=function() result.running=true end
              result.stop=function() result.running=false end
              return setmetatable(result,{__tostring=function()error('profiler is not a Lua timing string')end})
            end
            game.take_screenshot=function(spec)
              screenshots[#screenshots+1]={by_player=spec.by_player,player_matches=spec.player==players[spec.by_player],show_gui=spec.show_gui,
                force_render=spec.force_render,path=spec.path,resolution={spec.resolution[1],spec.resolution[2]}}
            end
            local last_screenshot_tick=nil
            local take_screenshot=game.take_screenshot
            game.take_screenshot=function(spec) last_screenshot_tick=game.tick;take_screenshot(spec) end
            game.server_save=function(name)
              assert(last_screenshot_tick~=nil and game.tick-last_screenshot_tick>=60,"save overlapped pending GUI captures")
              saves[#saves+1]=name
            end
            local function element(kind,name)
              return {valid=true,type=kind,name=name}
            end
            local function build_gui(client, options)
              local target=client
              if opponent=="view-crosspollution" and client.index==2 then target=en end
              local root=element("frame",ROOT_NAME);root.visible=true
              local filters=element("flow",FILTERS)
              root[FILTERS]=filters
              filters[QUERY]=element("textfield",QUERY)
              filters[QUERY].text=options.search
              filters[SORT]=element("drop-down",SORT)
              filters[SORT].selected_index=options.sort=="native" and 2 or 1
              local tabs=element("tabbed-pane",TABS)
              root[TABS]=tabs
              local content=element("flow",CONTENT)
              content.children={}
              tabs[CONTENT]=content
              if options.tab=="availability" then
                if opponent~="missing-availability-label" then
                  for index,name in ipairs(AVAILABILITY) do
                    local label=element("label",name)
                    label.caption={"mir-browser.availability-entry",
                      {"technology-name.more-infinite-research."..AVAILABILITY_FAMILIES[index]},
                      {"mir-browser.availability-requires-space-age"}}
                    content[name]=label
                    content.children[#content.children+1]=label
                  end
                end
                if opponent=="extra-availability-label" then
                  content.children[#content.children+1]=element("label","mir_library_availability_unexpected")
                end
                target.gui.screen[ROOT_NAME]=root
                return
              end
              assert(options.visibility==1,"ordinary Library opens must reset Availability visibility")
              local results=element("list-box",RESULTS)
              results.items={options.selected};results.selected_index=1
              content[RESULTS]=results
              local detail=element("flow",DETAIL)
              detail[DETAIL_TITLE]=element("label",DETAIL_TITLE)
              detail[DETAIL_TITLE].caption=options.selected
              local context=element("flow","mir_library_detail_context")
              detail["mir_library_detail_context"]=context
              context["mir_library_context_status"]=element("label","mir_library_context_status")
              detail["mir_library_detail_level"]=element("label","mir_library_detail_level")
              content[DETAIL]=detail
              target.gui.screen[ROOT_NAME]=root
            end
            local function refresh_mock_gui(client)
              local root=client.gui.screen[ROOT_NAME]
              local filters=root and root[FILTERS]
              local query=filters and filters[QUERY]
              local tabs=root and root[TABS]
              local content=tabs and tabs[CONTENT]
              local detail=content and content[DETAIL]
              if not (root and query and detail) or query.text~=gear then return end
              local context=detail["mir_library_detail_context"]
              local queued=#force.research_queue
              local current=force.current_research~=nil
              context["mir_library_context_status"].caption={"mir-browser.context-status",{current or queued>0 and "mir-browser.status-queued" or "mir-browser.status-ready"}}
              context["mir_library_context_current"]=current and element("label","mir_library_context_current") or nil
              context["mir_library_context_queued"]=(not current and queued>0) and element("label","mir_library_context_queued") or nil
              context["mir_library_context_not_queued"]=queued==0 and element("label","mir_library_context_not_queued") or nil
              context["mir_library_context_queue_count"]=queued>0 and element("label","mir_library_context_queue_count") or nil
              context["mir_library_context_queue_position"]=queued>0 and element("label","mir_library_context_queue_position") or nil
              if queued>0 then
                context["mir_library_context_queue_count"].caption={"mir-browser.context-queue-count",queued}
                context["mir_library_context_queue_position"].caption={"mir-browser.context-queue-position",1}
              end
              detail["mir_library_detail_level"].caption={"mir-browser.level",force.technologies[gear].level}
            end
            local remote={interfaces={["more-infinite-research-browser"]={open=true}}}
            remote.call=function(interface, method, index, options)
              assert(interface=="more-infinite-research-browser" and method=="open")
              local client=players[index]
              assert(client and client.connected==true)
              build_gui(client,options)
              refresh_mock_gui(client)
              if opponent=="gameplay-mutation" then force.recipes["iron-gear-wheel"].productivity_bonus=.1 end
              if opponent=="native-witness-overwritten" then
                local witness=storage[key] and storage[key].native_initial
                if witness then witness.recipes["iron-gear-wheel"]=.1 end
              end
              return true
            end
            local function complete_mock_lab()
              local current=force.current_research
              if not current then return end
              if opponent~="no-lab-consumption" then
                for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}) do
                  inventory.counts[name]=inventory.counts[name]-1
                end
              end
              table.remove(force.research_queue,1)
              current.level=current.level+1
              force.recipes["iron-gear-wheel"].productivity_bonus=force.recipes["iron-gear-wheel"].productivity_bonus+.1
              force.current_research=force.research_queue[1]
              fire(6,{research=current,by_script=opponent=="script-completion"})
              if force.current_research then fire(4,{research=force.current_research,last_research=current}) end
            end
            local environment={
              script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-library-multiplayer"]="0.1.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"},
                on_init=function(callback)callbacks.init=callback end,on_load=function(callback)callbacks.load=callback end,
                on_event=function(event,callback)callbacks.events[event]=callback end},
              defines={events={on_tick=1,on_player_joined_game=2,on_player_locale_changed=3,on_research_started=4,
                on_research_finished=6,on_research_cancelled=7,on_force_created=8},inventory={lab_input=1}},
              game=game,storage=storage,remote=remote,
              helpers={table_to_json=function(value)markers[#markers+1]=value;return "{}" end},
              log=function(value)
                if type(value)=="table" then
                  assert(value[1]=="" and value[2]=="[MIR5_LIBRARY_PROFILE] " and value[4]==" ")
                  local profiler=value[5]
                  assert(profiler.valid and profiler.running==false, 'native profiler was not stopped')
                  profiler_logs[#profiler_logs+1]={label=value[3],
                    native_output=(opponent=="profiler-variant" and "different-host-" or "host-")..profiler.ordinal}
                else
                  assert(value:match("^%[MIR5_LIBRARY_MULTIPLAYER%] RESULT ")
                    or value:match("^%[MIR5_LIBRARY_MULTIPLAYER_JOIN%] ")
                    or value:match("^%[MIR5_LIBRARY_MULTIPLAYER_LOCALE%] "))
                end
              end,
            }
            environment._G=environment;setmetatable(environment,{__index=function(_,name)return _G[name]end})
            local chunk,message=loadfile(path,"t",environment);assert(chunk,message)
            local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)} end
            local function call(callback,event)
              local success,value=pcall(callback,event)
              return success,tostring(value)
            end
            ok,result=call(callbacks.init);if not ok then return {ok=false,message=result} end
            if opponent=="fake-connected" then
              ok,result=call(callbacks.events[2],{player_index=1})
              return {ok=ok,message=result,phase=storage[key].phase,markers=markers}
            end
            en.connected=true
            ok,result=call(callbacks.events[2],{player_index=1});if not ok then return {ok=false,message=result} end
            if opponent~="unchanged-locales" then
              ok,result=call(callbacks.events[3],{player_index=1});if not ok then return {ok=false,message=result} end
            end
            if opponent=="absent-second-client" then
              ok,result=call(callbacks.events[1]);return {ok=ok,message=result,phase=storage[key].phase,markers=markers,saves=saves}
            end
            de.connected=true
            ok,result=call(callbacks.events[2],{player_index=2});if not ok then return {ok=false,message=result} end
            if opponent~="unchanged-locales" then
              ok,result=call(callbacks.events[3],{player_index=2});if not ok then return {ok=false,message=result} end
            end
            game.tick=game.tick+120
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-availability" then return {ok=false,message="Availability capture did not retain the terminal view"} end
            game.tick=game.tick+59
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-availability" then return {ok=false,message="Availability view restored before render grace"} end
            game.tick=game.tick+1
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            local live_ready=false
            for step=1,32 do
              game.tick=game.tick+1
              if storage[key].phase=="researching-live-research" and force.current_research
                  and (storage[key].finished==0 or (storage[key].finished==1 and storage[key].first_completion_seen)) then
                ok,result=pcall(complete_mock_lab);if not ok then return {ok=false,message=tostring(result)} end
              end
              refresh_mock_gui(en);refresh_mock_gui(de)
              ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
              if storage[key].phase=="awaiting-rejoin" then live_ready=true;break end
            end
            if not live_ready then return {ok=false,message="actual Library refresh did not reach rejoin state"} end
            en.connected,de.connected=false,false
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            en.connected,de.connected=true,true
            ok,result=call(callbacks.events[2],{player_index=1});if not ok then return {ok=false,message=result} end
            ok,result=call(callbacks.events[2],{player_index=2});if not ok then return {ok=false,message=result} end
            game.tick=game.tick+120
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-rejoin" or #saves~=0 then return {ok=false,message="rejoin capture did not defer the save"} end
            game.tick=game.tick+59
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if #saves~=0 then return {ok=false,message="rejoin saved before render grace"} end
            game.tick=game.tick+1
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="awaiting-host-restart" then return {ok=false,message="rejoin phase did not request host restart"} end
            local before_load={phase=storage[key].phase,joins=storage[key].join_events,screenshots=storage[key].screenshot_calls,
              availability=storage[key].availability_checked,first=storage[key].measurements.first_open,native=storage[key].native.recipes["iron-gear-wheel"]}
            ok,result=call(callbacks.load);if not ok then return {ok=false,message=result} end
            local after_load={phase=storage[key].phase,joins=storage[key].join_events,screenshots=storage[key].screenshot_calls,
              availability=storage[key].availability_checked,first=storage[key].measurements.first_open,native=storage[key].native.recipes["iron-gear-wheel"]}
            local load_unchanged=before_load.phase==after_load.phase and before_load.joins==after_load.joins
              and before_load.screenshots==after_load.screenshots and before_load.availability==after_load.availability
              and before_load.first==after_load.first and before_load.native==after_load.native
            en.connected,de.connected=false,false
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            en.connected,de.connected=true,true
            ok,result=call(callbacks.events[2],{player_index=1});if not ok then return {ok=false,message=result} end
            ok,result=call(callbacks.events[2],{player_index=2});if not ok then return {ok=false,message=result} end
            game.tick=game.tick+120
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-restart" or #saves~=1 then return {ok=false,message="restart capture did not defer the save"} end
            game.tick=game.tick+60
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            return {ok=true,message="",phase=storage[key].phase,markers=markers,screenshots=screenshots,saves=saves,
              load_unchanged=load_unchanged,join_events=storage[key].join_events,measurements=storage[key].measurements,
              profiler_logs=profiler_logs}
          end
        ''')

    def run_case(self, opponent=None):
        self.lua.globals().opponent = opponent
        return plain(self.lua.eval("run_library_multiplayer_fixture(control_path,opponent)"))

    def test_profile_and_fixture_pin_the_base_only_f200_closure(self):
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual((profile["target"], profile["factorio_line"], profile["engine"]["version"]), ("f200", "2.0", "2.0.77"))
        self.assertEqual(profile["engine"]["sha256"], "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B")
        self.assertEqual(profile["mods"], [
            {"name": "base", "version": "2.0.77", "enabled": True},
            {"name": "mir-fixture-mir5-active-mods-observer", "version": "0.1.0", "enabled": True},
            {"name": "more-infinite-research", "version": "5.0.20000", "enabled": True},
            {"name": "mir-fixture-mir5-library-multiplayer", "version": "0.1.0", "enabled": True},
        ])
        self.assertEqual(profile["archive_sha256"], {
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"
        })
        self.assertEqual((info["name"], info["version"], info["factorio_version"]),
                         ("mir-fixture-mir5-library-multiplayer", "0.1.0", "2.0"))
        self.assertEqual(info["dependencies"], ["base >= 2.0.77", "more-infinite-research = 5.0.20000"])

    def test_two_real_client_join_rejoin_and_restart_state_machine(self):
        result = self.run_case()
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((result["phase"], result["join_events"]), ("completed", 6))
        self.assertTrue(result["load_unchanged"])
        self.assertEqual([item["stage"] for item in result["markers"]], ["ready", "rejoin-ready", "restart-ready", "completed"])
        completed = result["markers"][-1]["witnesses"]
        self.assertTrue(completed["on_load_read_only"])
        self.assertTrue(completed["availability_terminal_labels_checked"])
        self.assertEqual(completed["screenshot_calls"], 8)
        self.assertEqual(result["saves"], ["mir5-library-multiplayer-restart", "mir5-native-complete"])
        live_refresh = completed["live_refresh"]
        self.assertEqual(live_refresh["real_lab_completions"], 2)
        self.assertFalse(live_refresh["native_laboratory_completion_by_script"])
        self.assertGreaterEqual(live_refresh["native_research_started_events"], 2)
        self.assertEqual(live_refresh["queue_lengths_observed"], [2, 1, 0])
        self.assertEqual(live_refresh["native_research_cancelled_events"], 1)
        self.assertEqual(live_refresh["native_foreign_force_created_events"], 1)
        self.assertEqual(live_refresh["gear_level"], 3)
        self.assertAlmostEqual(live_refresh["gear_productivity"], .2)
        self.assertEqual(live_refresh["science_consumed_per_named_pack"], 2)
        self.assertTrue(live_refresh["fixture_accelerates_gear_count_and_time_only"])
        self.assertFalse(live_refresh["ordinary_tuning_qualified"])
        self.assertTrue(live_refresh["root_and_query_identity_preserved"])
        self.assertTrue(live_refresh["cross_force_view_state_preserved"])
        self.assertEqual(set(result["measurements"]), {"first_open", "search", "refresh", "reopen"})
        self.assertTrue(all(value is True for value in result["measurements"].values()))
        self.assertEqual([row["label"] for row in result["profiler_logs"]],
                         ["first_open", "search", "refresh", "reopen"])
        self.assertEqual(len(result["screenshots"]), 8)
        self.assertEqual(
            {stage: sum(f"/{stage}-" in item["path"] for item in result["screenshots"])
             for stage in ("availability", "initial", "rejoin", "restart")},
            {"availability": 2, "initial": 2, "rejoin": 2, "restart": 2},
        )
        for screenshot in result["screenshots"]:
            self.assertTrue(screenshot["player_matches"])
            self.assertTrue(screenshot["show_gui"])
            self.assertTrue(screenshot["force_render"])
            self.assertEqual(screenshot["resolution"], [1280, 720])
            self.assertRegex(screenshot["path"], r"^mir5-library-multiplayer/(availability|initial|rejoin|restart)-[12]\.png$")

    def test_profiler_output_does_not_change_saved_witnesses(self):
        first, other = self.run_case(), self.run_case("profiler-variant")
        self.assertTrue(first["ok"], first["message"])
        self.assertTrue(other["ok"], other["message"])
        self.assertNotEqual(first["profiler_logs"], other["profiler_logs"])
        self.assertEqual(first["measurements"], other["measurements"])
        self.assertEqual(first["markers"], other["markers"])
        self.assertEqual(first["saves"], other["saves"])

    def test_fixture_rejects_missing_clients_wrong_locale_cross_player_view_and_native_mutation(self):
        absent = self.run_case("absent-second-client")
        self.assertTrue(absent["ok"], absent["message"])
        self.assertEqual(absent["phase"], "waiting-initial-clients")
        self.assertEqual([item["stage"] for item in absent["markers"]], ["ready"])
        self.assertFalse(absent["saves"])

        expected = {
            "fake-connected": "actually connected client",
            "locale": "actual en/de locales",
            "view-crosspollution": "Availability browser GUI tree is incomplete",
            "gameplay-mutation": "mutated native research, queue, or recipe effects",
            "native-witness-overwritten": "stored initial native witness was overwritten",
            "missing-queue": "native Library refresh queue differs before laboratory progress",
            "script-completion": "actual Library laboratory completion callback differs",
            "no-lab-consumption": "actual Library refresh lab science consumption differs",
            "wrong-force-event": "native foreign-force callback differs",
            "foreign-force-gui": "native public browser GUI tree is incomplete",
            "missing-availability-label": "Availability terminal label differs",
            "extra-availability-label": "Availability terminal label count differs",
        }
        for opponent, message in expected.items():
            with self.subTest(opponent=opponent):
                result = self.run_case(opponent)
                self.assertFalse(result["ok"])
                self.assertIn("[mir5-library-multiplayer]", result["message"])
                self.assertIn(message, result["message"])

    def test_initial_native_locales_need_no_synthetic_locale_change_event(self):
        result = self.run_case("unchanged-locales")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((result["phase"], result["join_events"]), ("completed", 6))

    def test_fixture_uses_only_public_browser_and_native_gui_witnesses(self):
        source = CONTROL.read_text(encoding="utf-8")
        self.assertIn('remote.call(BROWSER, "open", player.index', source)
        self.assertIn('{tab="availability", search=""}', source)
        self.assertIn('tab="research", visibility=1', source)
        self.assertIn('state.capture_after_tick = game.tick + 60', source)
        self.assertIn('"research_agricultural_growth_speed"', source)
        self.assertIn('"research_spoilage_preservation"', source)
        self.assertIn("on_player_locale_changed", source)
        self.assertIn("on_player_joined_game", source)
        self.assertIn("force.add_research(gear)", source)
        self.assertIn("force.cancel_current_research()", source)
        self.assertIn("on_research_started", source)
        self.assertIn("queue_lengths_observed", source)
        self.assertIn("on_research_finished", source)
        self.assertIn("on_research_cancelled", source)
        self.assertIn("on_force_created", source)
        self.assertIn("event.by_script ~= false", source)
        self.assertIn("state.native_initial_guard", source)
        self.assertIn("state.native_after_lab", source)
        self.assertIn("game.create_profiler(true)", source)
        self.assertIn("rendering_pending_external_png_readback=true", source)
        self.assertNotIn("game.create_player", source)
        self.assertNotIn("require(", source)
        self.assertNotIn("storage.mir_library", source)
        self.assertNotIn("script.raise_event", source)
        self.assertNotIn("research_queue_enabled", source)

    def test_live_refresh_acceleration_is_fixture_owned_and_limited(self):
        updates_path = (FIXTURE / "settings-updates.lua").as_posix()
        updates = Path(updates_path).read_text(encoding="utf-8")
        self.assertIn('"ips-cost-base-research_gears"', updates)
        self.assertIn('"ips-cost-linear-increment-research_gears"', updates)
        self.assertIn('"ips-cost-growth-research_gears"', updates)
        self.assertIn('"ips-research-time-research_gears"', updates)
        self.assertNotIn("require(", updates)
        self.lua.globals().updates_path = updates_path
        values = plain(self.lua.execute(r"""
          data = {raw={
            ["int-setting"]={
              ["ips-cost-base-research_gears"]={setting_type="startup",default_value=8000},
              ["ips-cost-linear-increment-research_gears"]={setting_type="startup",default_value=0},
              ["ips-research-time-research_gears"]={setting_type="startup",default_value=60},
            },
            ["double-setting"]={
              ["ips-cost-growth-research_gears"]={setting_type="startup",default_value=2},
            }
          }}
          assert(loadfile(updates_path))()
          return {
            base=data.raw["int-setting"]["ips-cost-base-research_gears"].default_value,
            increment=data.raw["int-setting"]["ips-cost-linear-increment-research_gears"].default_value,
            growth=data.raw["double-setting"]["ips-cost-growth-research_gears"].default_value,
            time=data.raw["int-setting"]["ips-research-time-research_gears"].default_value,
          }
        """))
        self.assertEqual(values, {"base": 1, "increment": 0, "growth": 1, "time": 1})
        wrong_default = plain(self.lua.execute(r"""
          data = {raw={
            ["int-setting"]={
              ["ips-cost-base-research_gears"]={setting_type="startup",default_value=7999},
              ["ips-cost-linear-increment-research_gears"]={setting_type="startup",default_value=0},
              ["ips-research-time-research_gears"]={setting_type="startup",default_value=60},
            },
            ["double-setting"]={
              ["ips-cost-growth-research_gears"]={setting_type="startup",default_value=2},
            }
          }}
          local ok, message = pcall(function() assert(loadfile(updates_path))() end)
          return {ok=ok, message=tostring(message), defaults={
            base=data.raw["int-setting"]["ips-cost-base-research_gears"].default_value,
            increment=data.raw["int-setting"]["ips-cost-linear-increment-research_gears"].default_value,
            growth=data.raw["double-setting"]["ips-cost-growth-research_gears"].default_value,
            time=data.raw["int-setting"]["ips-research-time-research_gears"].default_value,
          }}
        """))
        self.assertFalse(wrong_default["ok"])
        self.assertIn("unexpected Library refresh fixture setting ips-cost-base-research_gears", wrong_default["message"])
        self.assertEqual(wrong_default["defaults"], {"base": 7999, "increment": 0, "growth": 2, "time": 60})
        missing = self.lua.execute(r"""
          data = {raw={ ["int-setting"]={}, ["double-setting"]={} }}
          return pcall(function() assert(loadfile(updates_path))() end)
        """)
        self.assertFalse(missing[0])
        self.assertIn("unexpected Library refresh fixture setting", missing[1])

    def test_native_session_requires_eight_client_local_captures(self):
        wrapper = WRAPPER.read_text(encoding="utf-8")
        session = SESSION.read_text(encoding="utf-8")
        self.assertIn("@('availability','initial','rejoin','restart')", wrapper)
        self.assertIn("$patterns.Count -eq 8", session)
        self.assertIn("$clientPatterns.Count -eq 4", session)
        self.assertIn("@('availability','initial','rejoin','restart')", session)
        self.assertIn("$completed.witnesses.availability_terminal_labels_checked -eq $true", session)
        self.assertIn("$completed.witnesses.screenshot_calls -eq 8", session)

    def test_pre_session_admission_refusal_is_preserved_without_launch_or_secrets(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'wrapper parse failed'}
          $nodes=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.Contains("'session-admission-refusal.json'")
          },$true))
          if($nodes.Count -ne 1){throw 'admission receipt writer missing or ambiguous'}
          $write=[scriptblock]::Create($nodes[0].Extent.Text)
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Invoke-MIRNativeProbeProcess {throw 'native process must not start'}
          function New-MIRNativeProbeResourceContext {throw 'admission must not be retried'}
          $script:fullWrites=0
          function Write-MIRNativeProbeResult {param($Context,$Record) $script:fullWrites++}
          foreach($case in @('library-multiplayer','scripted-effects-multiplayer')){
            $output=Join-Path $env:MIR_TEST_WORK $case
            $null=New-Item -ItemType Directory -Path $output
            $resources=$null
            $failure=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('[mir441-resource-admission-memory]'),'controlled',[Management.Automation.ErrorCategory]::ResourceUnavailable,$null)
            $admission=@{snapshot=@{memory=@{total_bytes=32GB;free_bytes=13GB;committed_bytes=24GB;commit_limit_bytes=40GB}};limits=@{physical_bytes=6GB;commit_bytes=6GB};expected_peak_memory_bytes=8GB;estimated_peak_bytes=512MB}
            $failure.Exception.Data['mir441_resource_admission']=$admission
            $record=[ordered]@{case=$case;source_head=('a'*40);harness_sha256=('e'*64);engine=@{sha256=('b'*64);base_version='2.0.77'};profile=@{sha256=('c'*64)};mir_archive=@{sha256=('d'*64)};failure='[mir441-resource-admission-memory]';resource_admission=$admission;preparation=@{private_value='do-not-serialize'};rcon_password='do-not-serialize'}
            & $write
            $path=Join-Path $output 'session-admission-refusal.json'
            $bytes=[IO.File]::ReadAllBytes($path);$text=[Text.Encoding]::UTF8.GetString($bytes);$receipt=$text|ConvertFrom-Json -AsHashtable
            if($bytes.Length -gt 64KB -or $text.Contains('do-not-serialize')){throw 'unbounded/private receipt'}
            if($receipt.status -cne 'refused-before-session' -or $receipt.case -cne $case -or $receipt.native_session_started -ne $false -or $receipt.release_qualification -ne $false){throw 'refusal claimed native acceptance'}
            if($receipt.resource_admission.snapshot.memory.free_bytes -ne 13GB -or $receipt.resource_admission.expected_peak_memory_bytes -ne 8GB -or $receipt.source_head -cne ('a'*40) -or $receipt.profile_sha256 -cne ('c'*64) -or $receipt.mir_archive_sha256 -cne ('d'*64)){throw 'lost exact refusal facts'}
            & $write
            if([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String($bytes) -or -not$failure.Exception.Data.Contains('admission_receipt_failure')){throw 'existing receipt was overwritten'}
            if($failure.Exception.Message -cne '[mir441-resource-admission-memory]' -or $failure.Exception.Data['mir441_resource_admission'].snapshot.memory.free_bytes -ne 13GB){throw 'original admission exception changed'}
          }
          $output=Join-Path $env:MIR_TEST_WORK 'oversize';$null=New-Item -ItemType Directory -Path $output
          $record.resource_admission=@{unexpected=('x'*64KB)}
          & $write
          if(Test-Path -LiteralPath (Join-Path $output 'session-admission-refusal.json')){throw 'oversize receipt written'}
          $record.resource_admission=$null
          & $write
          if(Test-Path -LiteralPath (Join-Path $output 'session-admission-refusal.json')){throw 'non-admission error gained receipt'}
          $resources=@{runs=[Collections.Generic.List[object]]::new()}
          & $write
          if($script:fullWrites -ne 1){throw 'admitted context lost its original result writer'}
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-mp-refusal-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_WORK=work), check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_session_success_waits_for_clients_first_teardown_and_preserves_failures(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $text=[IO.File]::ReadAllText($env:MIR_TEST_SESSION)
          $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $nodes=@($ast.EndBlock.Statements|Where-Object {
            $_ -is [Management.Automation.Language.TryStatementAst] -and
              $_.Body.Extent.Text.Contains("Start-Server 'server-initial'")
          })
          if($nodes.Count -ne 1){throw 'session execution tail missing or ambiguous'}
          $execute=[scriptblock]::Create($text.Substring($nodes[0].Extent.StartOffset))
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Get-SessionHash([string]$Path){return ('a'*64)}
          function Read-LogText([string]$Path){return ''}
          function Invoke-LoopbackRconKicks {param($Port,$Password)}
          function Start-Server([string]$Name,[string]$Save){
            $record=[pscustomobject]@{name=$Name;closed=$false}
            $script:records.Add($record);return $record
          }
          function Start-Clients([string]$Phase){
            if($script:mode -eq 'primary-and-cleanup' -and $Phase -eq 'initial'){
              throw 'original session failure'
            }
            foreach($locale in @('en','de')){
              $record=[pscustomobject]@{name="client-$Phase-$locale";closed=$false}
              $script:records.Add($record);$record
            }
          }
          function Stop-Record($Record){
            $script:stops.Add($Record.name)
            if(Test-Path -LiteralPath $script:sessionPath){throw 'success receipt preceded teardown'}
            if($Record.name -like 'server-*' -and @($script:records|Where-Object {
                $_.name -like 'client-*' -and -not $_.closed}).Count){
              throw 'server stopped before its live clients'
            }
            $Record.closed=$true
            if(($script:mode -eq 'cleanup' -and $Record.name -eq 'client-restart-de') -or
                ($script:mode -eq 'primary-and-cleanup' -and $Record.name -eq 'server-initial')){
              throw 'late native cleanup failure'
            }
          }
          function Wait-For([string]$Description,[scriptblock]$Predicate){
            if($Description -eq 'completed marker'){
              return [pscustomobject]@{witnesses=@{host_restart_observed=$true;on_load_read_only=$true;
                availability_terminal_labels_checked=$true;screenshot_calls=8}}
            }
            if($Description -eq 'complete final save and client screenshots'){
              return [pscustomobject]@{files=@()}
            }
            return $true
          }
          foreach($fixtureCase in @('library-multiplayer','scripted-effects-multiplayer')){
            foreach($script:mode in @('success','cleanup','primary-and-cleanup')){
              $output=Join-Path $env:MIR_TEST_WORK ($fixtureCase+'-'+$script:mode)
              $null=New-Item -ItemType Directory -Path $output
              $script:sessionPath=Join-Path $output 'session.json'
              $script:records=[Collections.Generic.List[object]]::new()
              $script:stops=[Collections.Generic.List[string]]::new()
              $sessionFailure=$null;$result=$null;$server=$null;$activeClients=@()
              $serverWriteData=$output;$engine='unused';$seed='seed';$restartSave='restart';$finalSave='final'
              $seedHash=('a'*64);$clientGraphics=@();$rconPort=1;$rconPassword='not-a-real-password'
              $clients=@([pscustomobject]@{name='en';locale='en';port=2;config='en.ini';write_data='en'},
                [pscustomobject]@{name='de';locale='de';port=3;config='de.ini';write_data='de'})
              $caught=$null
              try{& $execute|Out-Null}catch{$caught=$_}
              if(@($script:records|Where-Object {-not $_.closed}).Count){throw 'cleanup abandoned owned records'}
              if($script:mode -eq 'success'){
                if($null -ne $caught){throw $caught}
                $receipt=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json
                if($receipt.status -cne 'passed-private-two-client-session' -or $script:stops.Count -ne 8){
                  throw 'successful session lost completed teardown'
                }
                if(($script:stops.ToArray()|Select-Object -Last 3) -join ',' -cne
                    'client-restart-de,client-restart-en,server-restart'){throw 'final teardown is not reversed'}
              }else{
                if($null -eq $caught -or (Test-Path -LiteralPath $sessionPath)){throw 'failed session claimed success'}
                $expected=if($script:mode -eq 'cleanup'){'late native cleanup failure'}else{'original session failure'}
                if($caught.Exception.Message -cne $expected){throw 'original session/cleanup failure was replaced'}
              }
            }
          }
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-mp-teardown-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_SESSION=str(SESSION), MIR_TEST_WORK=work), check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_library_session_memory_calibration_keeps_the_generic_ceiling(self):
        wrapper = WRAPPER.read_text(encoding="utf-8")
        calibration = json.loads(MEMORY_CALIBRATION.read_text(encoding="utf-8"))

        self.assertIn("[ValidateSet(7168,8192)][int]$SessionExpectedPeakMemoryMiB=8192", wrapper)
        self.assertIn(
            "$FixtureCase -ceq 'library-multiplayer' -or $SessionExpectedPeakMemoryMiB -eq 8192",
            wrapper,
        )
        self.assertIn(
            "-ExpectedPeakMemoryMiB $SessionExpectedPeakMemoryMiB -MaxNewOutputMiB 512",
            wrapper,
        )
        self.assertNotIn("-ExpectedPeakMemoryMiB 8192 -MaxNewOutputMiB 512", wrapper)
        self.assertIn("session_expected_peak_memory_mib=$SessionExpectedPeakMemoryMiB", wrapper)

        self.assertEqual(calibration["profile"]["path"], "tests/profiles/library-multiplayer-f200-2077.json")
        self.assertEqual(
            hashlib.sha256(PROFILE.read_bytes()).hexdigest().upper(),
            calibration["profile"]["sha256"],
        )
        self.assertEqual(calibration["engine"]["sha256"], "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B")
        self.assertEqual(calibration["override"]["parameter"], "SessionExpectedPeakMemoryMiB")
        self.assertEqual(calibration["override"]["default_mib"], 8192)
        self.assertEqual(calibration["override"]["library_mib"], 7168)
        self.assertEqual(calibration["override"]["allowed_mib"], [7168, 8192])
        self.assertEqual(calibration["field_path"], "process.result.peak_sampled_private_bytes")

        peaks = []
        for receipt in calibration["receipts"]:
            with self.subTest(receipt=receipt["run"]):
                path = ROOT / receipt["gzip_path"]
                compressed = path.read_bytes()
                self.assertEqual(hashlib.sha256(compressed).hexdigest().upper(), receipt["gzip_sha256"])
                raw = gzip.decompress(compressed)
                self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), receipt["raw_sha256"])
                captured = json.loads(raw)
                self.assertEqual(captured["status"], "passed-private-two-client-fixture")
                self.assertEqual(captured["source_head"], receipt["source_commit"])
                self.assertEqual(captured["engine"]["sha256"], calibration["engine"]["sha256"])
                self.assertEqual(captured["profile"]["sha256"], calibration["profile"]["sha256"])
                peak = captured["process"]["result"]["peak_sampled_private_bytes"]
                self.assertEqual(peak, receipt["peak_sampled_private_bytes"])
                peaks.append(peak)

        self.assertEqual(max(peaks), calibration["observed_max_private_bytes"])
        self.assertEqual(
            calibration["override"]["library_bytes"] - max(peaks),
            calibration["observed_headroom_bytes"],
        )
        self.assertGreater(calibration["observed_headroom_bytes"], 0)
        self.assertEqual(
            calibration["observed_headroom_percent"],
            round(calibration["observed_headroom_bytes"] * 100 / max(peaks), 1),
        )

        refusal = calibration["refused_current_library_attempt"]
        default_bytes = calibration["override"]["default_mib"] * 1024 * 1024
        self.assertEqual(
            refusal["physical_reserve_bytes"] + default_bytes,
            refusal["default_required_bytes"],
        )
        self.assertEqual(
            refusal["default_required_bytes"] - refusal["free_bytes"],
            refusal["default_deficit_bytes"],
        )
        self.assertEqual(
            refusal["physical_reserve_bytes"] + calibration["override"]["library_bytes"],
            refusal["calibrated_required_bytes"],
        )
        self.assertEqual(
            refusal["free_bytes"] - refusal["calibrated_required_bytes"],
            refusal["calibrated_snapshot_headroom_bytes"],
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LibraryMultiplayerFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Host controls for the private F200 two-client Library fixture, not native evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-multiplayer"
CONTROL = FIXTURE / "control.lua"
PROFILE = ROOT / "tests/profiles/library-multiplayer-f200-2077.json"
WRAPPER = ROOT / "tools/Invoke-MultiplayerFixture.ps1"
SESSION = ROOT / "tools/Invoke-MultiplayerSession.ps1"


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
            local force={valid=true,index=1,technologies={},recipes={},research_queue={},research_progress=.42}
            for _,name in ipairs({gear,mining}) do
              force.technologies[name]={valid=true,name=name,level=1,researched=false,enabled=true,visible_when_disabled=false}
            end
            force.research_queue={force.technologies[gear]}
            force.current_research=force.technologies[gear]
            for _,name in ipairs({"iron-gear-wheel","burner-mining-drill","electric-mining-drill"}) do
              force.recipes[name]={valid=true,name=name,productivity_bonus=0}
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
            local game={forces={player=force},surfaces={[1]={valid=true,index=1}},tick=0}
            game.get_player=function(index) return players[index] end
            game.create_profiler=function(stopped)
              next_profiler=next_profiler+1
              local result={valid=true,stopped=stopped,ordinal=next_profiler}
              result.restart=function() result.running=true end
              result.stop=function() result.running=false end
              return setmetatable(result,{__tostring=function(value)return "mock-profiler-"..value.ordinal end})
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
              content[DETAIL]=detail
              target.gui.screen[ROOT_NAME]=root
            end
            local remote={interfaces={["more-infinite-research-browser"]={open=true}}}
            remote.call=function(interface, method, index, options)
              assert(interface=="more-infinite-research-browser" and method=="open")
              local client=players[index]
              assert(client and client.connected==true)
              build_gui(client,options)
              if opponent=="gameplay-mutation" then force.recipes["iron-gear-wheel"].productivity_bonus=.1 end
              if opponent=="native-witness-overwritten" then
                local witness=storage[key] and storage[key].native
                if witness then witness.recipes["iron-gear-wheel"]=.1 end
              end
              return true
            end
            local environment={
              script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-library-multiplayer"]="0.1.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"},
                on_init=function(callback)callbacks.init=callback end,on_load=function(callback)callbacks.load=callback end,
                on_event=function(event,callback)callbacks.events[event]=callback end},
              defines={events={on_tick=1,on_player_joined_game=2,on_player_locale_changed=3}},
              game=game,storage=storage,remote=remote,
              helpers={table_to_json=function(value)markers[#markers+1]=value;return "{}" end},
              log=function(value)assert(value:match("^%[MIR5_LIBRARY_MULTIPLAYER%] RESULT ")
                or value:match("^%[MIR5_LIBRARY_MULTIPLAYER_JOIN%] ")
                or value:match("^%[MIR5_LIBRARY_MULTIPLAYER_LOCALE%] "))end,
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
            if storage[key].phase~="awaiting-rejoin" then return {ok=false,message="initial client phase did not await an actual rejoin"} end
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
              load_unchanged=load_unchanged,join_events=storage[key].join_events,measurements=storage[key].measurements}
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
        self.assertEqual(set(result["measurements"]), {"first_open", "search", "refresh", "reopen"})
        self.assertTrue(all(isinstance(value, str) and value.startswith("mock-profiler-") for value in result["measurements"].values()))
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
            "native-witness-overwritten": "stored native witness was overwritten",
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
        self.assertIn("game.create_profiler(true)", source)
        self.assertIn("rendering_pending_external_png_readback=true", source)
        self.assertNotIn("game.create_player", source)
        self.assertNotIn("require(", source)
        self.assertNotIn("storage.mir_library", source)
        self.assertNotIn("research_queue_enabled", source)

    def test_native_session_requires_eight_client_local_captures(self):
        wrapper = WRAPPER.read_text(encoding="utf-8")
        session = SESSION.read_text(encoding="utf-8")
        self.assertIn("@('availability','initial','rejoin','restart')", wrapper)
        self.assertIn("$patterns.Count -eq 8", session)
        self.assertIn("$clientPatterns.Count -eq 4", session)
        self.assertIn("@('availability','initial','rejoin','restart')", session)
        self.assertIn("$completed.witnesses.availability_terminal_labels_checked -eq $true", session)
        self.assertIn("$completed.witnesses.screenshot_calls -eq 8", session)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LibraryMultiplayerFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

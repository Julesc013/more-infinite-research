"""Host controls for the passive real-input Library personal-view observer; no native verdict."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-personal-view-input"
OLD_SINGLEPLAYER_FIXTURE_COMMIT = "a6ace8a48dd59b3f5eb46722273d7545e0de7011"
FIXTURE_CONTROL_PATH = "tests/fixtures/library-personal-view-input/control.lua"


class LibraryPersonalViewInputFixtureControls(unittest.TestCase):
    def setUp(self, *, base="2.1.24", package="5.0.21016", extra_mods=None,
              actor_source=None, fixture_version="0.1.5"):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_source = actor_source or (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.lua.globals().base_version = base
        self.lua.globals().package_version = package
        self.lua.globals().fixture_version = fixture_version
        self.lua.execute(r'''
          callbacks={events={}}
          storage={}
          logs={}
          interfaces={}
          writes={}
          defines={events={on_player_joined_game=1,on_lua_shortcut=2,on_gui_click=3,
            on_gui_selected_tab_changed=4,on_gui_text_changed=5,on_gui_closed=6,on_tick=7},
            gui_type={custom=99},controllers={character=1,cutscene=6}}
          script={active_mods={base=base_version, ["more-infinite-research"]=package_version,
            ["mir-fixture-library-personal-view-input"]=fixture_version},
            on_init=function(fn) callbacks.init=fn end,
            on_event=function(event,fn) callbacks.events[event]=fn end}
          remote={add_interface=function(name,values) interfaces[name]=values end}
          helpers={table_to_json=function(value) return value end,
            write_file=function(path,value,append,index)
              assert(append==false and index==1 and writes[path]==nil)
              writes[path]=value
            end}
          log=function(message) logs[#logs+1]=message end
          next_gui_index=0
          local function element(kind,name)
            next_gui_index=next_gui_index+1
            return {valid=true,type=kind,name=name,index=next_gui_index,get_mod=function() return "more-infinite-research" end}
          end
          force={valid=true,name="player",current_research=nil,research_progress=0,research_queue={},
            worker_robots_storage_bonus=0}
          player={valid=true,connected=true,index=1,force=force,display_scale=1.25,
            display_resolution={width=1920,height=1080},controller_type=defines.controllers.character,
            gui={screen={}},opened=nil}
          player2={valid=true,connected=true,index=2,force=force,display_scale=1.25,
            display_resolution={width=1920,height=1080},controller_type=defines.controllers.character,
            gui={screen={}},opened=nil}
          game={tick=0,connected_players={player},get_player=function(index)
            if index==1 then return player end
            if index==2 then return player2 end
            return nil
          end}
          setmetatable(game,{__index=function(_,key) error("undeclared LuaGameScript member: "..key) end})
          function build_root(query_text, x, y)
            local function readable_style(values)
              return setmetatable(values,{__index=function(_,field)
                if field=="width" or field=="height" then error("write-only style read: "..field) end
                return nil
              end})
            end
            local root=element("frame","mir_research_browser")
            root.location={x=x or 20,y=y or 30}
            root.style=readable_style({minimal_width=0,maximal_width=1100,minimal_height=0,maximal_height=800})
            local tabs=element("tabbed-pane","mir_library_tabs");tabs.selected_tab_index=1
            tabs.style=readable_style({minimal_width=0,maximal_width=0,minimal_height=nil,maximal_height=nil})
            tabs.mir_library_tab_research=element("tab","mir_library_tab_research")
            tabs.mir_library_tab_help=element("tab","mir_library_tab_help")
            local page=element("scroll-pane","mir_library_research_page");page.visible=true
            local help=element("scroll-pane","mir_library_help_content");help.visible=true
            local filters=element("flow","mir_library_filters")
            local query=element("textfield","mir_library_query");query.text=query_text or ""
            filters.mir_library_query=query;page.mir_library_filters=filters;tabs.mir_library_research_page=page
            tabs.mir_library_help_content=help
            root.mir_library_tabs=tabs
            return root,query
          end
          function open_library(query_text, x, y)
            local root,query=build_root(query_text,x,y)
            player.gui.screen.mir_research_browser=root;player.opened=root
            return root,query
          end
          function retire_library()
            local root=player.gui.screen.mir_research_browser
            if root then
              root.valid=false
              root.mir_library_tabs.valid=false
            end
            player.gui.screen.mir_research_browser=nil;player.opened=nil
          end
          assert(load(actor_source,"@mir-fixture-library-personal-view-input/control.lua"))()
          function initialize() callbacks.init() end
          function emit(id,row) return callbacks.events[id](row) end
          function tick()
            game.tick=game.tick+1
            return callbacks.events[defines.events.on_tick]({tick=game.tick})
          end
          function report() return interfaces["mir5-library-personal-view-input"].report() end
        ''')
        if extra_mods:
            for name, version in extra_mods.items():
                self.lua.globals().name = name
                self.lua.globals().version = version
                self.lua.execute("script.active_mods[name]=version")

    def initialize_join_initial(self):
        self.lua.execute("initialize();emit(defines.events.on_player_joined_game,{player_index=1});tick()")

    def initialize_singleplayer_initial(self):
        self.lua.execute("initialize();tick();tick()")

    def source_at(self, commit):
        return subprocess.run(
            ["git", "show", f"{commit}:{FIXTURE_CONTROL_PATH}"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def open_and_click_query(self):
        self.lua.execute(r'''
          emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
          local root,query=open_library("")
          tick()
          local tabs=root.mir_library_tabs
          emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_help})
          tabs.selected_tab_index=4
          emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
          tick()
          emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_research})
          tabs.selected_tab_index=1
          emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
          tick()
          emit(defines.events.on_gui_click,{player_index=1,element=query})
          tick()
        ''')

    def complete_real_event_model(self):
        self.initialize_singleplayer_initial()
        self.open_and_click_query()
        self.lua.execute(r'''
          local query=player.gui.screen.mir_research_browser.mir_library_tabs.mir_library_research_page
            .mir_library_filters.mir_library_query
          -- XTEST key presses may coalesce into one game tick.  All are real
          -- text callbacks; the observer must wait for the deferred tree read.
          for _,text in ipairs({"g","ge","gea","gear"}) do
            query.text=text
            emit(defines.events.on_gui_text_changed,{player_index=1,element=query})
          end
          tick()
          retire_library()
          emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,
            element={valid=false}})
          tick()
          emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
          open_library("gear")
          tick()
        ''')

    def test_passive_fixture_records_real_event_order_and_retained_personal_view(self):
        self.complete_real_event_model()
        self.lua.execute(r'''
          local observed=report()
          assert(observed.complete and observed.phase=="complete")
          assert(observed.events.shortcut==2 and observed.events.tab==2 and observed.events.tab_click==2
            and observed.events.click==1 and observed.events.text==4
            and observed.events.close==1)
          assert(#observed.event_log==13 and observed.event_log[1].kind=="singleplayer-load")
          assert(observed.event_log[2].kind=="shortcut" and observed.event_log[3].kind=="tab-click")
          assert(observed.event_log[4].kind=="tab-selected" and observed.event_log[6].kind=="tab-selected")
          assert(observed.event_log[7].kind=="query-click" and observed.event_log[12].kind=="closed")
          assert(observed.event_log[13].kind=="shortcut")
          assert(observed.close_gui_type==defines.gui_type.custom and observed.native_snapshot_unchanged)
          assert(#observed.snapshots==8)
          assert(observed.snapshots[1].stage=="initial" and observed.snapshots[2].stage=="open")
          assert(observed.snapshots[3].stage=="help-tab" and observed.snapshots[3].tab_index==4)
          assert(observed.snapshots[4].stage=="research-tab" and observed.snapshots[4].tab_index==1)
          assert(observed.snapshots[2].tab_bar_index==observed.snapshots[3].tab_bar_index
            and observed.snapshots[3].tab_bar_index==observed.snapshots[4].tab_bar_index)
          assert(observed.snapshots[5].stage=="query-click" and observed.snapshots[6].query=="gear")
          assert(observed.snapshots[7].stage=="closed" and observed.snapshots[8].stage=="reopen")
          assert(observed.snapshots[8].tab_bar_index~=observed.snapshots[2].tab_bar_index)
          assert(observed.snapshots[8].geometry.x==20 and observed.snapshots[8].geometry.maximal_width==1100)
          assert(writes["mir-library-personal-view-input/01-initial.json"].phase=="await-open")
          assert(writes["mir-library-personal-view-input/03-help-tab.json"].snapshot.tab_index==4)
          assert(writes["mir-library-personal-view-input/08-reopen.json"].complete)
          assert(writes["mir-library-personal-view-input/08-reopen.json"].active_mods==observed.active_mods)
          local count=0;for _ in pairs(writes) do count=count+1 end;assert(count==8)
        ''')
        self.assertEqual(
            self.lua.eval("logs[1]"),
            "[MIR_ACTIVE_MODS] base@2.1.24|mir-fixture-library-personal-view-input@0.1.5|more-infinite-research@5.0.21016",
        )
        self.assertEqual(self.lua.eval("#logs"), 1)

    def test_singleplayer_load_bootstrap_replaces_only_the_missing_join_event(self):
        old_source = self.source_at(OLD_SINGLEPLAYER_FIXTURE_COMMIT)
        self.setUp(actor_source=old_source, fixture_version="0.1.4")
        with self.assertRaisesRegex(Exception, "assertion failed"):
            self.lua.execute('initialize();tick();assert(report().phase=="await-open")')

        self.setUp()
        self.initialize_singleplayer_initial()
        self.lua.execute(r'''
          local observed=report()
          assert(observed.phase=="await-open" and #observed.event_log==1)
          assert(observed.event_log[1].kind=="singleplayer-load" and observed.event_log[1].player_index==1)
          assert(writes["mir-library-personal-view-input/01-initial.json"] ~= nil)
        ''')

    def test_bootstrap_requires_one_connected_player_and_real_join_does_not_rebootstrap(self):
        self.lua.execute(r'''
          initialize()
          game.connected_players={}
          tick()
          assert(report().phase=="await-join" and #report().event_log==0 and next(writes)==nil)
          game.connected_players={player,player2}
          tick()
          assert(report().phase=="await-join" and #report().event_log==0 and next(writes)==nil)
          game.connected_players={{valid=false,connected=true,index=1}}
          tick()
          assert(report().phase=="await-join" and #report().event_log==0 and next(writes)==nil)
          game.connected_players={player}
          tick();tick()
          assert(report().phase=="await-open" and #report().event_log==1)
          assert(report().event_log[1].kind=="singleplayer-load")
        ''')

        self.setUp()
        self.lua.execute(r'''
          initialize()
          emit(defines.events.on_player_joined_game,{player_index=1})
          tick();tick()
          assert(report().phase=="await-open" and #report().event_log==1)
          assert(report().event_log[1].kind=="joined")
        ''')

    def test_wrong_tuple_or_extra_mod_refuses_before_event_observation(self):
        for base, package, extra in [
            ("2.1.23", "5.0.21016", None),
            ("2.1.24", "5.0.21015", None),
            ("2.1.24", "5.0.21016", {"observer": "1.0.0"}),
        ]:
            with self.subTest(base=base, package=package, extra=extra):
                self.setUp(base=base, package=package, extra_mods=extra)
                with self.assertRaisesRegex(Exception, "exact active-mod selection"):
                    self.lua.execute("initialize()")
                self.assertEqual(self.lua.eval("#logs"), 0)
        self.setUp()
        self.lua.execute('script.active_mods["mir-fixture-library-personal-view-input"]="0.1.3"')
        with self.assertRaisesRegex(Exception, "exact active-mod selection"):
            self.lua.execute("initialize()")

    def test_wrong_order_refuses_and_missing_shortcut_or_text_stays_incomplete(self):
        self.initialize_join_initial()
        with self.assertRaisesRegex(Exception, "query click event out of order"):
            self.lua.execute('emit(defines.events.on_gui_click,{player_index=1,element={valid=true,name="mir_library_query"}})')

        self.setUp()
        self.initialize_join_initial()
        self.lua.execute('emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="foreign"})')
        self.assertEqual(self.lua.eval('report().phase'), "await-open")
        self.assertFalse(self.lua.eval("report().complete"))

        self.setUp()
        self.initialize_join_initial()
        self.open_and_click_query()
        self.assertEqual(self.lua.eval('report().phase'), "await-query-text")
        self.assertFalse(self.lua.eval("report().complete"))

        self.setUp()
        self.initialize_join_initial()
        self.lua.execute(r'''
          emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
          local root=open_library("");tick()
          emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=root.mir_library_tabs})
        ''')
        with self.assertRaisesRegex(Exception, "Help tab was not selected"):
            self.lua.execute("tick()")

        self.setUp()
        self.lua.execute("initialize();emit(defines.events.on_player_joined_game,{player_index=1});helpers=nil")
        with self.assertRaisesRegex(Exception, "phase output helpers unavailable"):
            self.lua.execute("tick()")

    def test_pre_shortcut_base_events_and_cutscene_wait_do_not_count_as_mir_input(self):
        self.setUp()
        self.lua.execute(r'''
          initialize()
          player.controller_type=defines.controllers.cutscene
          tick()
          assert(report().phase=="settling-initial" and next(writes)==nil)
          emit(defines.events.on_gui_click,{player_index=1,element={valid=true,name="base_welcome_confirm"}})
          emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})
          assert(report().events.setup==2 and report().events.shortcut==0 and report().events.close==0)
          player.controller_type=defines.controllers.character
          tick()
          assert(report().phase=="await-open")
          local initial=writes["mir-library-personal-view-input/01-initial.json"]
          assert(initial and initial.snapshot.controller_type==defines.controllers.character)
          assert(initial.events.setup==2 and initial.events.shortcut==0)
        ''')

    def test_initial_waits_for_actual_base_ui_dismissal_before_reporting_ready(self):
        self.setUp()
        self.lua.execute(r'''
          initialize()
          player.opened={valid=true,name="base_welcome"}
          tick()
          assert(report().phase=="settling-initial" and next(writes)==nil)
          emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})
          assert(report().events.setup==1 and report().events.shortcut==0)
          player.opened=nil
          tick()
          local initial=writes["mir-library-personal-view-input/01-initial.json"]
          assert(initial and initial.phase=="await-open" and initial.snapshot.controller_type==defines.controllers.character)
          assert(report().phase=="await-open" and report().complete==false)
        ''')

    def test_invalid_closed_element_is_not_dereferenced_and_deferred_retirement_is_required(self):
        self.initialize_join_initial()
        self.open_and_click_query()
        self.lua.execute(r'''
          local query=player.gui.screen.mir_research_browser.mir_library_tabs.mir_library_research_page
            .mir_library_filters.mir_library_query
          query.text="gear";emit(defines.events.on_gui_text_changed,{player_index=1,element=query});tick()
          emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})
        ''')
        with self.assertRaisesRegex(Exception, "Library root should be retired"):
            self.lua.execute("tick()")

        self.setUp()
        self.initialize_join_initial()
        self.open_and_click_query()
        self.lua.execute(r'''
          local query=player.gui.screen.mir_research_browser.mir_library_tabs.mir_library_research_page
            .mir_library_filters.mir_library_query
          query.text="gear";emit(defines.events.on_gui_text_changed,{player_index=1,element=query});tick()
          retire_library()
          emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})
          tick()
          assert(report().phase=="await-reopen")
        ''')

    def test_geometry_native_state_and_query_must_survive_the_reopen(self):
        self.initialize_join_initial()
        self.open_and_click_query()
        self.lua.execute(r'''
          local query=player.gui.screen.mir_research_browser.mir_library_tabs.mir_library_research_page
            .mir_library_filters.mir_library_query
          query.text="gear";emit(defines.events.on_gui_text_changed,{player_index=1,element=query});tick()
          retire_library();emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element=nil});tick()
          emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
          open_library("gear",21,30)
        ''')
        with self.assertRaisesRegex(Exception, "root geometry was not retained"):
            self.lua.execute("tick()")

        self.setUp()
        self.initialize_join_initial()
        self.lua.execute(r'''
          emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
          local root=open_library("");tick()
          local tabs=root.mir_library_tabs;tabs.selected_tab_index=4
          emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs});tick()
          tabs.selected_tab_index=1;tabs.style.maximal_width=1067
          emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
        ''')
        with self.assertRaisesRegex(Exception, "tab-bar identity or geometry was not retained"):
            self.lua.execute("tick()")

        self.setUp()
        self.initialize_join_initial()
        self.lua.execute("force.worker_robots_storage_bonus=1")
        with self.assertRaisesRegex(Exception, "native research state changed"):
            self.lua.execute("emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name='mir-research-browser'});open_library('');tick()")

    def test_metadata_protocol_and_no_mutation_authority(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info, {
            "name": "mir-fixture-library-personal-view-input",
            "version": "0.1.5",
            "title": "MIR Library personal-view input observer",
            "author": "MIR maintainers",
            "factorio_version": "2.1",
            "dependencies": ["base = 2.1.24", "~ more-infinite-research = 5.0.21016"],
        })
        code = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        for forbidden in ["remote.call", "script.raise_event", "server_save", "auto_save", "require(",
                          "research_queue =", ".researched =", ".level ="]:
            self.assertNotIn(forbidden, code)
        self.assertIsNone(re.search(r"\\b(?:player|root|query)\\.(?:text|opened)\\s*=(?!=)", code))
        self.assertEqual(code.count("[MIR_ACTIVE_MODS] "), 1)
        self.assertIn("script.on_event(defines.events.on_tick, settle)", code)
        self.assertIn('begin_observation(player, "singleplayer-load")', code)
        self.assertIn('begin_observation(player, "joined")', code)
        self.assertIn("script.on_event(defines.events.on_gui_selected_tab_changed, on_selected_tab_changed)", code)
        self.assertIn('helpers.write_file(name, helpers.table_to_json({', code)
        self.assertIn("MAX_INITIAL_READY_TICKS = 1800", code)
        self.assertNotIn("style.width", code)
        self.assertNotIn("style.height", code)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryPersonalViewInputFixtureControls)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

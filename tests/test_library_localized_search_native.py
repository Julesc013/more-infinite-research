"""Host controls for the passive German Library localized-search observer.

These controls model only the public Factorio GUI tree and engine-delivered
events.  They never create a native GUI verdict or synthesize an observer
event from inside the fixture.
"""

import argparse
import json
from pathlib import Path
import sys
import unittest

from library_observer_authority import GUI_FIELD_ASSIGNMENT, LUA_GUI_AUTHORITY


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "library-localized-search-native"
CONTROL = FIXTURE / "control.lua"
INFO = FIXTURE / "info.json"
PERSONAL_CONTROL = ROOT / "tests" / "fixtures" / "library-personal-view-input" / "control.lua"

MIR = "more-infinite-research"
FIXTURE_NAME = "mir-fixture-library-localized-search-native"
TARGET_ID = "recipe-prod-research_gears-1"
PREFIX = "[img=technology/recipe-prod-research_gears-1] "
INITIAL_QUERY = "recipe-prod-research_mining_drill-1"
LOCALIZED_QUERY = "Eisenzahnrad"


class LocalizedSearchNativeFixtureControls(unittest.TestCase):
    """A closed public GUI model for the exact six-mod localized-search path."""

    def setUp(self, *, actor_source=None, locale="en", extra_mods=None):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_source = actor_source or CONTROL.read_text(encoding="utf-8")
        self.lua.globals().initial_locale = locale
        self.lua.execute(
            LUA_GUI_AUTHORITY
            + r'''
              callbacks={events={}}
              storage={}
              logs={}
              log=function(message) logs[#logs+1]=message end
              writes={}
              interfaces={}
              defines={events={on_player_joined_game=1,on_lua_shortcut=2,on_gui_click=3,
                on_gui_selected_tab_changed=4,on_gui_text_changed=5,on_gui_closed=6,on_tick=7},
                gui_type={custom=99},controllers={character=1,spectator=2}}
              script={active_mods={base="2.1.24",["more-infinite-research"]="5.0.21017",
                ["mir-fixture-library-localized-search-native"]="0.1.2",
                ["mir-fixture-mir5-api-alpha"]="0.1.0",
                ["mir-fixture-mir5-api-beta"]="0.1.0",
                ["mir-fixture-mir5-active-mods-observer"]="0.1.0"},
                on_init=function(fn) callbacks.init=observer_callback(fn) end,
                on_event=function(event,fn) callbacks.events[event]=observer_callback(fn) end}
              remote={add_interface=function(name,values)
                for key,fn in pairs(values) do values[key]=observer_callback(fn) end
                interfaces[name]=values
              end}
              local function clone(value, seen)
                if type(value)~="table" then return value end
                seen=seen or {}
                if seen[value] then return seen[value] end
                local copied={};seen[value]=copied
                for key,item in pairs(value) do copied[clone(key,seen)]=clone(item,seen) end
                return copied
              end
              helpers={table_to_json=function(value) return clone(value) end,
                write_file=function(path,value,append,index)
                  assert(append==false and index==1 and writes[path]==nil)
                  writes[path]=value
                end}
              next_gui_index=0
              local function element(kind,name)
                next_gui_index=next_gui_index+1
                return gui_state({valid=true,type=kind,name=name,index=next_gui_index,
                  get_mod=function() return "more-infinite-research" end},name)
              end
              gear={valid=true,name="recipe-prod-research_gears-1",level=3,researched=false,enabled=true}
              force={valid=true,name="player",current_research=nil,research_progress=0,research_queue={},
                worker_robots_storage_bonus=0,technologies={["recipe-prod-research_gears-1"]=gear},
                recipes={["iron-gear-wheel"]={productivity_bonus=0.2}}}
              player=gui_state({valid=true,connected=true,index=1,name="MIR5Deutsch",locale=initial_locale,
                controller_type=defines.controllers.character,character={valid=true},
                force=force,display_scale=1.25,display_resolution={width=1280,height=720},
                gui={screen={}},opened=nil},"player")
              wrong_player=gui_state({valid=true,connected=true,index=2,name="MIR5English",locale="en",
                force=force,display_scale=1.25,display_resolution={width=1280,height=720},
                gui={screen={}},opened=nil},"wrong-player")
              game={tick=0,get_player=function(index)
                if index==1 then return player end
                if index==2 then return wrong_player end
                return nil
              end}
              setmetatable(game,{__index=function(_,key) error("undeclared LuaGameScript member: "..key) end})
              local function readable_style(values)
                return setmetatable(values,{__index=function(_,field)
                  if field=="width" or field=="height" then error("write-only style read: "..field) end
                  return nil
                end})
              end
              function set_results(results,query)
                local root=player.gui.screen.mir_research_browser
                local page=root.mir_library_tabs.mir_library_research_page
                local list=page.mir_library_research_content.mir_library_list_pane.mir_library_results
                list.items=results or {}
                local text=page.mir_library_filters.mir_library_query
                text.text=query
              end
              function expected_results()
                return {{"","[img=technology/recipe-prod-research_gears-1] ","Eisenzahnrad-Produktivit"..string.char(195,164).."t"}}
              end
              function build_root(query_text,results,x,y)
                local root=element("frame","mir_research_browser")
                root.location={x=x or 100,y=y or 80}
                root.style=readable_style({minimal_width=1024,maximal_width=1024,minimal_height=864,maximal_height=864})
                local tabs=element("tabbed-pane","mir_library_tabs")
                tabs.parent=root
                tabs.style=readable_style({minimal_width=992,maximal_width=992,minimal_height=0,maximal_height=0})
                tabs.selected_tab_index=1
                local research_tab=element("tab","mir_library_tab_research");research_tab.parent=tabs
                local help_tab=element("tab","mir_library_tab_help");help_tab.parent=tabs
                tabs.mir_library_tab_research=research_tab;tabs.mir_library_tab_help=help_tab
                local page=element("scroll-pane","mir_library_research_page");page.parent=tabs;page.visible=true
                local filters=element("flow","mir_library_filters");filters.parent=page
                local query=element("textfield","mir_library_query");query.parent=filters;query.text=query_text
                filters.mir_library_query=query;page.mir_library_filters=filters
                local content=element("flow","mir_library_research_content");content.parent=page
                local pane=element("flow","mir_library_list_pane");pane.parent=content
                local list=element("list-box","mir_library_results");list.parent=pane;list.items=results or {}
                pane.mir_library_results=list;content.mir_library_list_pane=pane
                page.mir_library_research_content=content
                tabs.mir_library_research_page=page
                root.mir_library_tabs=tabs
                return root,query
              end
              function open_library(query_text,results)
                local root,query=build_root(query_text,results)
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
              observer_callback(assert(load(actor_source,"@mir-fixture-library-localized-search-native/control.lua")))()
              function initialize() callbacks.init() end
              function emit(id,row) return callbacks.events[id](row) end
              function tick()
                game.tick=game.tick+1
                return callbacks.events[defines.events.on_tick]({tick=game.tick})
              end
              function report() return interfaces["mir5-library-localized-search-native"].report() end
            '''
        )
        if extra_mods:
            for name, version in extra_mods.items():
                self.lua.globals().name = name
                self.lua.globals().version = version
                self.lua.execute("script.active_mods[name]=version")

    def exec(self, source):
        self.lua.execute(source)

    def begin(self):
        self.exec(
            "open_library('recipe-prod-research_mining_drill-1',{});initialize();"
            "emit(defines.events.on_player_joined_game,{player_index=1});"
        )

    def make_locale_ready(self):
        self.exec("player.locale='de';tick()")

    def prepare_open(self, *, close_event=True):
        self.begin()
        self.make_locale_ready()
        self.lua.globals().deliver_close_event = close_event
        self.exec(
            r'''
              retire_library()
              if deliver_close_event then
                emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})
              end
              tick()
              if not deliver_close_event then tick() end
              emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
              local root,query=open_library("recipe-prod-research_mining_drill-1",{})
              tick()
            '''
        )

    def through_query_click(self, *, selected_first=True, close_event=True):
        self.prepare_open(close_event=close_event)
        self.lua.globals().selected_first = selected_first
        self.exec(
            r'''
              local root=player.gui.screen.mir_research_browser
              local tabs=root.mir_library_tabs
              if selected_first then
                tabs.selected_tab_index=4
                emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
                emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_help})
              else
                emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_help})
                tabs.selected_tab_index=4
                emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
              end
              tick()
              if selected_first then
                tabs.selected_tab_index=1
                emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
                emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_research})
              else
                emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_research})
                tabs.selected_tab_index=1
                emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
              end
              tick()
              local query=root.mir_library_tabs.mir_library_research_page.mir_library_filters.mir_library_query
              emit(defines.events.on_gui_click,{player_index=1,element=query})
              tick()
            '''
        )

    def clear_and_type(self, *, results=True):
        self.exec(
            r'''
              local query=player.gui.screen.mir_research_browser.mir_library_tabs.mir_library_research_page
                .mir_library_filters.mir_library_query
              query.text=""
              emit(defines.events.on_gui_text_changed,{player_index=1,element=query})
              tick()
              for _,text in ipairs({"E","Ei","Eis","Eise","Eisen","Eisenz","Eisenza","Eisenzah", "Eisenzahn", "Eisenzahnrad"}) do
                if text=="Eisenzahnrad" then
                  if final_results then set_results(expected_results(),text) else set_results({},text) end
                else
                  query.text=text
                end
                emit(defines.events.on_gui_text_changed,{player_index=1,element=query})
              end
              tick()
            '''
        )

    def close_and_reopen(self, *, retained=True, results=True, close_event=True):
        self.lua.globals().reopened_retained = retained
        self.lua.globals().reopened_results = results
        self.lua.globals().deliver_close_event = close_event
        self.exec(
            r'''
              retire_library()
              if deliver_close_event then
                emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})
              end
              tick()
              if not deliver_close_event then tick() end
              emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
              open_library(reopened_retained and "Eisenzahnrad" or "",reopened_results and expected_results() or {})
              tick()
            '''
        )

    def complete(self):
        self.through_query_click()
        self.lua.globals().final_results = True
        self.clear_and_type()
        self.close_and_reopen()

    def test_exact_passive_event_protocol_writes_ten_phase_files(self):
        self.complete()
        self.exec(
            r'''
              local observed=report()
              assert(observed.phase=="complete" and #observed.snapshots==10)
              assert(observed.events.joined==1 and observed.events.shortcut==2 and observed.events.tab_click==2)
              assert(observed.events.tab_selected==2 and observed.events.query_click==1 and observed.events.clear==1)
              assert(observed.events.close==2 and observed.events.text==10)
              assert(observed.snapshots[1].stage=="initial" and observed.snapshots[2].stage=="setup-closed")
              assert(observed.snapshots[3].stage=="open" and observed.snapshots[4].stage=="help-tab")
              assert(observed.snapshots[5].stage=="research-tab" and observed.snapshots[6].stage=="query-click")
              assert(observed.snapshots[7].stage=="cleared" and observed.snapshots[8].stage=="localized-query")
              assert(observed.snapshots[9].stage=="closed" and observed.snapshots[10].stage=="reopen")
              assert(observed.snapshots[3].tab_bar_index==observed.snapshots[4].tab_bar_index)
              assert(observed.snapshots[4].tab_bar_index==observed.snapshots[5].tab_bar_index)
              assert(observed.snapshots[10].tab_bar_index~=observed.snapshots[3].tab_bar_index)
              assert(observed.event_log[4].kind=="tab-selected" and observed.event_log[4].stage=="help-tab")
              assert(observed.event_log[5].kind=="tab-click" and observed.event_log[5].stage=="help-tab")
              assert(observed.event_log[6].kind=="tab-selected" and observed.event_log[6].stage=="research-tab")
              assert(observed.event_log[7].kind=="tab-click" and observed.event_log[7].stage=="research-tab")
              assert(observed.snapshots[4].tick>observed.event_log[4].tick and observed.snapshots[4].tick>observed.event_log[5].tick)
              assert(observed.snapshots[5].tick>observed.event_log[6].tick and observed.snapshots[5].tick>observed.event_log[7].tick)
              local expected_caption="Eisenzahnrad-Produktivit"..string.char(195,164).."t"
              assert(observed.snapshots[8].result.caption==expected_caption)
              assert(observed.snapshots[10].result.icon=="[img=technology/recipe-prod-research_gears-1] ")
              assert(writes["mir-library-localized-search-native/09-reopen.json"].native_snapshot_unchanged)
              assert(writes["mir-library-localized-search-native/00-initial.json"].player.locale=="de")
              assert(writes["mir-library-localized-search-native/00-initial.json"].phase=="initial")
              assert(writes["mir-library-localized-search-native/06-cleared.json"].snapshot.query=="")
              assert(writes["mir-library-localized-search-native/07-localized-query.json"].snapshot.result.count==1)
              assert(writes["mir-library-localized-search-native/09-reopen.json"].complete)
              assert(writes["mir-library-localized-search-native/09-reopen.json"].phase=="reopen")
              assert(writes["mir-library-localized-search-native/09-reopen.json"].next_phase=="complete")
              assert(writes["mir-library-localized-search-native/09-reopen.json"].snapshot.result.caption==expected_caption)
              assert(#writes["mir-library-localized-search-native/09-reopen.json"].snapshots==10)
              local count=0;for _ in pairs(writes) do count=count+1 end;assert(count==10)
            '''
        )
        self.assertEqual(
            self.lua.eval("logs[1]"),
            "[MIR_ACTIVE_MODS] base@2.1.24|mir-fixture-library-localized-search-native@0.1.2|"
            "mir-fixture-mir5-active-mods-observer@0.1.0|mir-fixture-mir5-api-alpha@0.1.0|"
            "mir-fixture-mir5-api-beta@0.1.0|more-infinite-research@5.0.21017",
        )

    def test_retired_root_without_observer_close_event_is_observed_without_inventing_an_event(self):
        self.begin()
        self.make_locale_ready()
        self.exec(
            r'''
              retire_library()
              tick()
              assert(report().phase=="settling-setup-closed" and report().events.close==0)
              assert(writes["mir-library-localized-search-native/01-setup-closed.json"]==nil)
              tick()
              local row=writes["mir-library-localized-search-native/01-setup-closed.json"]
              assert(row and row.next_phase=="await-open" and row.events.close==0)
              assert(#row.event_log==1 and row.event_log[1].kind=="joined")
              assert(row.snapshot.close_observation.root_absent and row.snapshot.close_observation.opened_absent)
              assert(row.snapshot.close_observation.event_received==false)
              assert(row.snapshot.close_observation.tick<row.snapshot.tick)
              emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name="mir-research-browser"})
              open_library("recipe-prod-research_mining_drill-1",{})
              tick()
              assert(report().phase=="await-help-click")
            '''
        )

    def test_retirement_observation_requires_live_character_empty_opened_and_retired_root(self):
        self.begin()
        self.make_locale_ready()
        self.exec("for i=1,3 do tick() end;assert(report().phase=='await-setup-close' and #report().snapshots==1)")
        for change in ("player.opened={valid=true}", "player.character=nil", "player.character.valid=false",
                       "player.controller_type=defines.controllers.spectator", "player.connected=false"):
            with self.subTest(change=change):
                self.setUp()
                self.begin()
                self.make_locale_ready()
                self.exec("retire_library();"+change)
                with self.assertRaises(Exception):
                    self.exec("tick()")
                self.exec("assert(writes['mir-library-localized-search-native/01-setup-closed.json']==nil)")

    def test_close_state_observation_cannot_hide_native_frame_changes(self):
        self.begin()
        self.make_locale_ready()
        self.exec("retire_library();force.worker_robots_storage_bonus=1;tick()")
        with self.assertRaisesRegex(Exception,"native fresh frame changed"):
            self.exec("tick()")
        self.exec("assert(report().events.close==0 and writes['mir-library-localized-search-native/01-setup-closed.json']==nil)")

    def test_both_real_root_retirements_preserve_localized_query_without_fabricated_close_events(self):
        self.through_query_click(close_event=False)
        self.lua.globals().final_results = True
        self.clear_and_type()
        self.close_and_reopen(close_event=False)
        self.exec(
            r'''
              local observed=report()
              assert(observed.phase=="complete" and #observed.snapshots==10 and observed.events.close==0)
              for _,event in ipairs(observed.event_log) do assert(event.kind~="closed") end
              for _,index in ipairs({2,9}) do
                local close=observed.snapshots[index].close_observation
                assert(close.root_absent and close.opened_absent and close.event_received==false)
              end
              assert(observed.snapshots[10].query=="Eisenzahnrad" and observed.snapshots[10].result.count==1)
            '''
        )

    def test_received_close_event_cannot_substitute_for_retiring_the_owned_root(self):
        self.begin()
        self.make_locale_ready()
        self.exec("emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})")
        with self.assertRaisesRegex(Exception,"Library root should be retired"):
            self.exec("tick()")

    def test_native_selected_first_pair_rejects_the_retained_click_first_policy(self):
        # R03 retained 2.1.24 facts record selected -> click on the same tick.
        # The mutant represents the original 9a click-first transition without
        # adding a shallow-CI dependency on historical actor bytes.
        old_policy = CONTROL.read_text(encoding="utf-8").replace(
            "if pair == nil or pair.selected or tabs.selected_tab_index ~= pair.index then",
            "if pair == nil or not pair.clicked or pair.selected or tabs.selected_tab_index ~= pair.index then",
            1,
        )
        self.setUp(actor_source=old_policy)
        self.prepare_open()
        with self.assertRaisesRegex(Exception, "tab selection differs"):
            self.exec(
                "local tabs=player.gui.screen.mir_research_browser.mir_library_tabs;tabs.selected_tab_index=4;"
                "emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})"
            )

        self.setUp()
        self.through_query_click(selected_first=True)
        self.exec("assert(report().events.tab_selected==2 and report().events.tab_click==2 and #report().snapshots==6)")

    def test_tab_pair_permits_click_first_but_never_snapshots_an_incomplete_pair(self):
        self.prepare_open()
        self.exec(
            r'''
              local tabs=player.gui.screen.mir_research_browser.mir_library_tabs
              tabs.selected_tab_index=4
              emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
              tick()
              assert(report().phase=="await-help-click" and #report().snapshots==3
                and writes["mir-library-localized-search-native/03-help-tab.json"]==nil)
              emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_help})
              tick()
              assert(report().phase=="await-research-click" and #report().snapshots==4)
            '''
        )

        self.setUp()
        self.through_query_click(selected_first=False)
        self.exec("assert(report().events.tab_selected==2 and report().events.tab_click==2 and #report().snapshots==6)")

    def test_tab_pair_refuses_duplicate_or_wrong_tab_facts(self):
        self.prepare_open()
        self.exec(
            r'''
              local tabs=player.gui.screen.mir_research_browser.mir_library_tabs
              tabs.selected_tab_index=4
              emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})
            '''
        )
        with self.assertRaisesRegex(Exception, "tab selection differs"):
            self.exec("emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=player.gui.screen.mir_research_browser.mir_library_tabs})")

        self.setUp()
        self.prepare_open()
        with self.assertRaisesRegex(Exception, "tab selection differs"):
            self.exec("local tabs=player.gui.screen.mir_research_browser.mir_library_tabs;tabs.selected_tab_index=1;emit(defines.events.on_gui_selected_tab_changed,{player_index=1,element=tabs})")

        self.setUp()
        self.prepare_open()
        with self.assertRaisesRegex(Exception, "tab click differs"):
            self.exec("local tabs=player.gui.screen.mir_research_browser.mir_library_tabs;emit(defines.events.on_gui_click,{player_index=1,element=tabs.mir_library_tab_research})")

    def test_locale_waits_without_writes_then_refuses_the_wrong_locale(self):
        self.begin()
        self.exec("tick();assert(next(writes)==nil and report().phase=='settling-initial')")
        self.make_locale_ready()
        self.exec("assert(writes['mir-library-localized-search-native/00-initial.json']~=nil)")

        self.setUp(locale="en")
        self.begin()
        with self.assertRaisesRegex(Exception, "German locale did not become ready"):
            self.exec("game.tick=1800;tick()")

    def test_exact_six_mod_tuple_refuses_before_state_or_output(self):
        self.setUp(extra_mods={"unexpected": "0.1.0"})
        with self.assertRaisesRegex(Exception, "exact active-mod selection required"):
            self.exec("initialize()")
        self.exec("assert(next(storage)==nil and next(writes)==nil)")

    def test_wrong_connected_role_and_out_of_order_shortcut_refuse(self):
        self.exec("initialize()")
        with self.assertRaisesRegex(Exception, "client role differs"):
            self.exec("emit(defines.events.on_player_joined_game,{player_index=2})")

        self.setUp()
        self.begin()
        self.make_locale_ready()
        with self.assertRaisesRegex(Exception, "shortcut event out of order"):
            self.exec("emit(defines.events.on_lua_shortcut,{player_index=1,prototype_name='mir-research-browser'})")

    def test_missing_wrong_and_raw_identifier_results_refuse(self):
        for mode, error in (("missing", "localized result count differs"), ("wrong", "localized result differs"), ("raw", "localized result differs")):
            with self.subTest(mode=mode):
                self.setUp()
                self.through_query_click()
                self.exec(
                    {
                        "missing": "final_results=false",
                        "wrong": "function expected_results() return {{'', '[img=technology/recipe-prod-research_gears-1] ', 'Wrong caption'}} end;final_results=true",
                        "raw": "function expected_results() return {'recipe-prod-research_gears-1'} end;final_results=true",
                    }[mode]
                )
                with self.assertRaisesRegex(Exception, error):
                    self.clear_and_type()

    def test_reopened_query_requires_the_retained_localized_result(self):
        self.through_query_click()
        self.lua.globals().final_results = True
        self.clear_and_type()
        self.close_and_reopen(results=False)
        self.exec('assert(report().phase=="settling-reopen" and #report().snapshots==9);game.tick=report().pending.deadline-1')
        with self.assertRaisesRegex(Exception, "localized result not ready before reopen deadline"):
            self.exec("tick()")
        self.exec('assert(#report().snapshots==9 and writes["mir-library-localized-search-native/09-reopen.json"]==nil)')

    def prepare_delayed_reopen(self):
        self.through_query_click()
        self.lua.globals().final_results = True
        self.clear_and_type()
        self.close_and_reopen(results=False)

    def test_reopen_waits_for_the_exact_localized_result_without_another_event(self):
        self.prepare_delayed_reopen()
        self.exec(r'''
          assert(report().phase=="settling-reopen" and #report().snapshots==9)
          assert(writes["mir-library-localized-search-native/09-reopen.json"]==nil)
          local events=#report().event_log
          for i=1,7 do tick() end
          assert(#report().event_log==events and #report().snapshots==9)
          set_results(expected_results(),"Eisenzahnrad")
          tick()
          assert(report().phase=="complete" and #report().snapshots==10)
          assert(#report().event_log==events)
          local row=writes["mir-library-localized-search-native/09-reopen.json"]
          assert(row.snapshot.result.count==1 and row.snapshot.query=="Eisenzahnrad")
          assert(row.native_snapshot_unchanged)
        ''')

    def test_reopen_wait_refuses_a_nonempty_wrong_result_immediately(self):
        for items in ("{'raw-id'}", "{{'', 'wrong-icon', 'wrong-caption'}}", "{expected_results()[1], expected_results()[1]}"):
            with self.subTest(items=items):
                self.setUp()
                self.prepare_delayed_reopen()
                self.exec(f'set_results({items},"Eisenzahnrad")')
                with self.assertRaisesRegex(Exception, "localized result"):
                    self.exec("tick()")
                self.exec('assert(#report().snapshots==9 and writes["mir-library-localized-search-native/09-reopen.json"]==nil)')

    def test_reopen_wait_refuses_query_shell_controller_and_native_drift(self):
        mutations = (
            ("force.worker_robots_storage_bonus=1", "native fresh frame changed"),
            ("set_results({},'wrong query')", "localized query was not retained"),
            ("player.controller_type=defines.controllers.spectator", "live character controller"),
            ("player.character.valid=false", "live character controller"),
            ("player.connected=false", "player unavailable"),
            ("retire_library()", "root"),
            ("player.gui.screen.mir_research_browser.mir_library_tabs.selected_tab_index=4", "Research localized-search view"),
            ("player.gui.screen.mir_research_browser.location.x=321", "geometry"),
        )
        for mutation, error in mutations:
            with self.subTest(mutation=mutation):
                self.setUp()
                self.prepare_delayed_reopen()
                self.exec(mutation)
                with self.assertRaisesRegex(Exception, error):
                    self.exec("tick()")
                self.exec('assert(#report().snapshots==9 and writes["mir-library-localized-search-native/09-reopen.json"]==nil)')

    def test_reopen_deadline_accepts_ready_boundary_but_never_a_late_result(self):
        self.prepare_delayed_reopen()
        self.exec(r'''
          game.tick=report().pending.deadline-1
          set_results(expected_results(),"Eisenzahnrad")
          tick()
          assert(report().phase=="complete" and #report().snapshots==10)
        ''')
        self.setUp()
        self.prepare_delayed_reopen()
        self.exec('game.tick=report().pending.deadline;set_results(expected_results(),"Eisenzahnrad")')
        with self.assertRaisesRegex(Exception, "reopen deadline"):
            self.exec("tick()")
        self.exec('assert(#report().snapshots==9 and writes["mir-library-localized-search-native/09-reopen.json"]==nil)')

    def test_native_frame_and_query_retention_refuse_changes(self):
        self.begin()
        self.make_locale_ready()
        self.exec("force.worker_robots_storage_bonus=1;retire_library();emit(defines.events.on_gui_closed,{player_index=1,gui_type=defines.gui_type.custom,element={valid=false}})")
        with self.assertRaisesRegex(Exception, "native fresh frame changed"):
            self.exec("tick()")

        self.setUp()
        self.through_query_click()
        self.lua.globals().final_results = True
        self.clear_and_type()
        with self.assertRaisesRegex(Exception, "localized query was not retained"):
            self.close_and_reopen(retained=False)

    def test_authority_proxy_rejects_alias_and_bracket_gui_writes(self):
        source = CONTROL.read_text(encoding="utf-8").replace(
            "  current.player_index, current.events.joined", "  local alias = player; alias.opened = nil\n  current.player_index, current.events.joined", 1
        )
        self.setUp(actor_source=source)
        self.exec("open_library('recipe-prod-research_mining_drill-1',{});initialize()")
        with self.assertRaisesRegex(Exception, "observer GUI mutation: player.opened"):
            self.exec("emit(defines.events.on_player_joined_game,{player_index=1})")

        source = CONTROL.read_text(encoding="utf-8").replace(
            "  local text = query.text", "  query['text'] = ''\n  local text = query.text", 1
        )
        self.setUp(actor_source=source)
        self.through_query_click()
        with self.assertRaisesRegex(Exception, "observer GUI mutation: mir_library_query.text"):
            self.exec(
                "local q=player.gui.screen.mir_research_browser.mir_library_tabs.mir_library_research_page.mir_library_filters.mir_library_query;q.text='';emit(defines.events.on_gui_text_changed,{player_index=1,element=q})"
            )

    def test_helpers_are_a_required_write_closure(self):
        self.begin()
        self.exec("helpers={};player.locale='de'")
        with self.assertRaisesRegex(Exception, "phase output helpers unavailable"):
            self.exec("tick()")

    def test_fixture_source_is_passive_and_old_personal_observer_cannot_claim_this_protocol(self):
        source = CONTROL.read_text(encoding="utf-8")
        self.assertEqual(GUI_FIELD_ASSIGNMENT.findall(source), [])
        for forbidden in ("remote.call", "script.raise_event", "server_save", "auto_save", "player.opened =", "query.text ="):
            self.assertNotIn(forbidden, source)
        old = PERSONAL_CONTROL.read_text(encoding="utf-8")
        self.assertNotIn(FIXTURE_NAME, old)
        self.assertNotIn("mir-library-localized-search-native/06-cleared.json", old)
        self.assertNotIn("Eisenzahnrad", old)

    def test_metadata_and_public_result_path_are_exact(self):
        metadata = json.loads(INFO.read_text(encoding="utf-8"))
        self.assertEqual(metadata["name"], FIXTURE_NAME)
        self.assertEqual(metadata["version"], "0.1.2")
        self.assertEqual(metadata["factorio_version"], "2.1")
        self.assertEqual(
            metadata["dependencies"],
            [
                "base = 2.1.24",
                "~ more-infinite-research = 5.0.21017",
                "mir-fixture-mir5-api-alpha = 0.1.0",
                "mir-fixture-mir5-api-beta = 0.1.0",
                "mir-fixture-mir5-active-mods-observer = 0.1.0",
            ],
        )
        source = CONTROL.read_text(encoding="utf-8")
        for token in ("research_content", "list_pane", "results", TARGET_ID, "TARGET_CAPTION"):
            self.assertIn(token, source)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    runtime = args.lua_runtime_dir.resolve(strict=True)
    sys.path.insert(0, str(runtime))
    global LuaRuntime
    from lupa.lua52 import LuaRuntime

    unittest.main(argv=[sys.argv[0], *remaining])


if __name__ == "__main__":
    main()

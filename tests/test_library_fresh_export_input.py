"""Host controls for the passive fresh two-client Library export observer; no native verdict."""
import argparse
import json
from pathlib import Path
import sys
import unittest

import mir_test_versions as SHARED
from library_observer_authority import GUI_FIELD_ASSIGNMENT, LUA_GUI_AUTHORITY


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-fresh-export-input"
MIR_517_F210 = SHARED.alias_for("5.0.17", "f210").distribution_version
class LibraryFreshExportInputControls(unittest.TestCase):
    def setUp(self, *, base="2.1.24", package=MIR_517_F210, fixture="0.1.0", extra_mods=None,
              actor_source=None):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_source = actor_source or (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.lua.globals().base_version = base
        self.lua.globals().package_version = package
        self.lua.globals().fixture_version = fixture
        self.lua.execute(LUA_GUI_AUTHORITY + r'''
          callbacks={events={}}
          storage={}
          logs={}
          writes={[1]={},[2]={}}
          external_files={[1]={},[2]={}}
          defines={events={on_player_joined_game=1,on_gui_click=2,on_tick=3}}
          script={active_mods={base=base_version,["more-infinite-research"]=package_version,
            ["mir-fixture-library-fresh-export-input"]=fixture_version,
            ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
            ["mir-fixture-mir5-api-alpha"]="0.1.0",["mir-fixture-mir5-api-beta"]="0.1.0"},
            on_init=function(fn) callbacks.init=observer_callback(fn) end,
            on_event=function(event,fn)
              callbacks.events[event]=callbacks.events[event] or {}
              if fn~=nil then callbacks.events[event][#callbacks.events[event]+1]=observer_callback(fn) end
            end}
          helpers={table_to_json=function(value)return value end,
            write_file=function(path,value,append,index)
              assert(append==false and (index==1 or index==2) and writes[index][path]==nil)
              writes[index][path]=value
            end}
          log=function(message) logs[#logs+1]=message end
          local function emit_handlers(event,row)
            local handlers=callbacks.events[event] or {}
            for _,handler in ipairs(handlers) do handler(row) end
          end
          function emit(event,row) return emit_handlers(event,row) end
          function initialize() return callbacks.init() end
          function tick()
            game.tick=game.tick+1
            return emit_handlers(defines.events.on_tick,{tick=game.tick})
          end
          next_gui_index=0
          local MIR="more-infinite-research"
          function element(parent,kind,name,values)
            next_gui_index=next_gui_index+1
            values=values or {}
            values.valid=true;values.type=kind;values.name=name;values.index=next_gui_index;values.parent=parent
            values.get_mod=function()return MIR end
            local value=gui_state(values,name)
            if parent~=nil then parent[name]=value end
            return value
          end
          force={valid=true,name="player",current_research=nil,research_progress=0,research_queue={},
            worker_robots_storage_bonus=0,
            technologies={ ["recipe-prod-research_gears-1"]={name="recipe-prod-research_gears-1",level=3,
              researched=false,enabled=true}},
            recipes={ ["iron-gear-wheel"]={productivity_bonus=.2}}}
          local function player(index,name,locale)
            return gui_state({valid=true,connected=true,index=index,name=name,locale=locale,force=force,
              gui={screen={}},opened=nil},name)
          end
          player_en=player(1,"MIR5English","en")
          player_de=player(2,"MIR5Deutsch","de")
           player_other=player(3,"MIR5Other","en")
           foreign_force={valid=true,name="enemy"}
          game={tick=0,connected_players={player_en,player_de},get_player=function(index)
            if index==1 then return player_en end
            if index==2 then return player_de end
             if index==3 then return player_other end
            return nil
          end}
           function connected(...) game.connected_players={...} end
          function root_for(player,tab)
            local root=element(nil,"frame","mir_research_browser",{tags={["more-infinite-research.library-root.v1"]=true}})
            local tabs=element(root,"tabbed-pane","mir_library_tabs",{selected_tab_index=tab})
            player.gui.screen.mir_research_browser=root;player.opened=root
            return root,tabs
          end
          function settings_button(player,kind)
            local root,tabs=root_for(player,3)
            local content=element(tabs,"flow","mir_library_settings_content")
            local toolbar=element(content,"table","mir_library_settings_toolbar")
            local name=kind=="compact" and "mir_library_export_compact" or "mir_library_export_settings"
            return element(toolbar,"button",name),content
          end
          function diagnostics_button(player)
            local root,tabs=root_for(player,4)
            local content=element(tabs,"flow","mir_library_help_content")
            local panes=element(content,"flow","mir_library_help_panes")
            local panel=element(panes,"flow","mir_library_report_panel")
            element(panel,"text-box","mir_library_report_preview",{read_only=true,text="MIR diagnostic report\ninitial"})
            return element(panel,"button","mir_library_export_diagnostics"),panel
          end
          function apply_export(player,kind,variant)
            local root=player.gui.screen.mir_research_browser
            local tabs=root.mir_library_tabs
            local profile=(variant=="bad-profile") and "not-a-profile" or
              ("MIRSET1:"..(player.locale=="en" and "EN" or "DE").."-"..string.upper(kind))
            local destination
            if kind=="diagnostics" then
              destination=tabs.mir_library_help_content.mir_library_help_panes.mir_library_report_panel
              destination.mir_library_report_preview.text=(variant=="bad-report") and "wrong report" or
                ("MIR diagnostic report\n"..player.name)
            else
              destination=tabs.mir_library_settings_content
            end
            element(destination,"text-box","mir_library_export_profile",{read_only=true,text=profile})
            external_files[player.index]["more-infinite-research/settings/mir-settings-profile.txt"]=profile.."\n"
            if kind=="diagnostics" then
              external_files[player.index]["more-infinite-research/mir.log"]=
                destination.mir_library_report_preview.text
            end
          end
          function button_for(role,kind)
            local player=role=="en" and player_en or player_de
            if kind=="diagnostics" then return player,diagnostics_button(player) end
            return player,settings_button(player,kind)
          end
          function drive_action(role,kind,variant,change_native)
            local player,button=button_for(role,kind)
            emit(defines.events.on_gui_click,{player_index=player.index,element=button})
            if change_native then force.research_progress=.5 end
            apply_export(player,kind,variant)
            tick()
          end
          function assert_external_bytes(player_index,row)
            for _,entry in pairs(row.snapshot.files) do
              assert(external_files[player_index][entry.path]==entry.bytes)
            end
          end
          function install_extra(name,version) script.active_mods[name]=version end
          assert(load(actor_source,"fixture","t",_ENV))()
        ''')
        for name, version in (extra_mods or {}).items():
            self.lua.globals().install_extra(name, version)

    def initialize_baseline(self):
        self.lua.execute(r'''
          initialize()
          emit(defines.events.on_player_joined_game,{player_index=1})
          emit(defines.events.on_player_joined_game,{player_index=2})
          tick()
          assert(storage.mir_fresh_export_input.phase=="settling-baseline")
          assert(next(writes[1])==nil and next(writes[2])==nil)
          tick()
          local current=storage.mir_fresh_export_input
          assert(current.phase=="ready" and current.fresh_frame.gear.level==3 and current.fresh_frame.gear.researched==false)
          assert(writes[1]["mir-library-fresh-export-input/00-baseline.json"]~=nil)
        ''')

    def test_r09_completed_gear_is_unresearched_and_truthy_flag_refuses(self):
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.setUp(actor_source=source.replace("row.researched ~= false", "row.researched ~= true"))
        self.lua.execute(r'''
          initialize()
          force.technologies["recipe-prod-research_gears-1"].researched=true
          emit(defines.events.on_player_joined_game,{player_index=1})
          emit(defines.events.on_player_joined_game,{player_index=2})
          tick();tick()
          assert(writes[1]["mir-library-fresh-export-input/00-baseline.json"]~=nil)
        ''')

        self.setUp()
        self.lua.execute(r'''
          initialize()
          force.technologies["recipe-prod-research_gears-1"].researched=true
          emit(defines.events.on_player_joined_game,{player_index=1})
          emit(defines.events.on_player_joined_game,{player_index=2})
          tick()
        ''')
        with self.assertRaisesRegex(Exception, "fresh earned provider frame differs"):
            self.lua.execute("tick()")
        self.assertTrue(self.lua.eval("next(writes[1]) == nil and next(writes[2]) == nil"))

    def test_join_identity_waits_for_localized_pair_without_phase_writes(self):
        self.lua.execute(r'''
          initialize()
          player_de.locale="en"
          emit(defines.events.on_player_joined_game,{player_index=1})
          emit(defines.events.on_player_joined_game,{player_index=2})
          local current=storage.mir_fresh_export_input
          assert(current.phase=="await-locales" and current.roles.en==1 and current.roles.de==2)
          assert(next(writes[1])==nil and next(writes[2])==nil)
          tick()
          assert(current.phase=="await-locales" and next(writes[1])==nil and next(writes[2])==nil)
          player_de.locale="de"
          tick()
          assert(current.phase=="settling-baseline" and next(writes[1])==nil and next(writes[2])==nil)
          tick()
          assert(current.phase=="ready" and writes[1]["mir-library-fresh-export-input/00-baseline.json"]~=nil)
        ''')

    def test_join_readiness_rejects_persistent_wrong_locale_and_identity_faults(self):
        self.lua.execute(r'''
          initialize()
          player_de.locale="en"
          emit(defines.events.on_player_joined_game,{player_index=1})
          emit(defines.events.on_player_joined_game,{player_index=2})
          game.tick=1799
        ''')
        with self.assertRaisesRegex(Exception, "locale did not become ready"):
            self.lua.execute("tick()")
        self.assertTrue(self.lua.eval("next(writes[1]) == nil and next(writes[2]) == nil"))

        for fault, expected in (
            ('emit(defines.events.on_player_joined_game,{player_index=1})', "duplicate export client role"),
            ('emit(defines.events.on_player_joined_game,{player_index=3})', "unexpected export client join"),
            ('player_de.connected=false;tick()', "exact export client pair differs"),
            ('player_de.force=foreign_force;tick()', "exact export client pair differs"),
        ):
            with self.subTest(fault=fault):
                self.setUp()
                self.lua.execute(r'''
                  initialize()
                  emit(defines.events.on_player_joined_game,{player_index=1})
                ''')
                if "player_index=3" in fault:
                    self.lua.execute('emit(defines.events.on_player_joined_game,{player_index=2})')
                    self.lua.execute('connected(player_en,player_de,player_other)')
                elif "connected=false" in fault or "foreign_force" in fault:
                    self.lua.execute('emit(defines.events.on_player_joined_game,{player_index=2})')
                with self.assertRaisesRegex(Exception, expected):
                    self.lua.execute(fault)
                self.assertTrue(self.lua.eval("next(writes[1]) == nil and next(writes[2]) == nil"))

    def test_six_actual_export_clicks_defer_gui_reads_and_bind_role_local_bytes(self):
        self.initialize_baseline()
        for ordinal, (role, kind) in enumerate((("en", "full"), ("en", "compact"), ("en", "diagnostics"),
                                                ("de", "full"), ("de", "compact"), ("de", "diagnostics")), 1):
            with self.subTest(role=role, kind=kind):
                self.lua.execute(f'drive_action("{role}","{kind}")')
                player_index = 1 if role == "en" else 2
                action = f"{role}-{kind}"
                self.lua.execute(
                    f'assert_external_bytes({player_index},writes[{player_index}]'
                    f'["mir-library-fresh-export-input/{ordinal:02d}-{action}.json"])'
                )
        self.lua.execute(r'''
          local current=storage.mir_fresh_export_input
          assert(current.phase=="completed" and #current.actions==6 and current.phase_count==7)
          assert(table.concat(current.actions,"|")=="en-full|en-compact|en-diagnostics|de-full|de-compact|de-diagnostics")
          local en_full=writes[1]["mir-library-fresh-export-input/01-en-full.json"]
          local en_diag=writes[1]["mir-library-fresh-export-input/03-en-diagnostics.json"]
          local de_diag=writes[2]["mir-library-fresh-export-input/06-de-diagnostics.json"]
          assert(en_full.phase=="ready" and en_full.snapshot.preview:sub(1,8)=="MIRSET1:")
          assert(en_diag.snapshot.diagnostic_preview:sub(1,21)=="MIR diagnostic report")
          assert(de_diag.complete and de_diag.snapshot.frame.gear_productivity==.2)
          assert(en_full.active_mods=="base@2.1.24|mir-fixture-library-fresh-export-input@0.1.0|mir-fixture-mir5-active-mods-observer@0.1.0|mir-fixture-mir5-api-alpha@0.1.0|mir-fixture-mir5-api-beta@0.1.0|more-infinite-research@5.0.21017")
        ''')

    def test_wrong_tuple_or_extra_closure_refuses_before_state_or_phase_writes(self):
        cases = [
            ("2.1.23", MIR_517_F210, "0.1.0", None),
            ("2.1.24", "5.0.21016", "0.1.0", None),
            ("2.1.24", MIR_517_F210, "0.1.1", None),
            ("2.1.24", MIR_517_F210, "0.1.0", {"unexpected": "1.0.0"}),
        ]
        for base, package, fixture, extra in cases:
            with self.subTest(base=base, package=package, fixture=fixture, extra=extra):
                self.setUp(base=base, package=package, fixture=fixture, extra_mods=extra)
                with self.assertRaisesRegex(Exception, "exact active-mod selection"):
                    self.lua.execute("initialize()")
                self.assertTrue(self.lua.eval("storage.mir_fresh_export_input == nil"))
                self.assertTrue(self.lua.eval("next(writes[1]) == nil and next(writes[2]) == nil"))

    def test_wrong_role_click_path_body_native_state_and_external_file_refuse(self):
        self.initialize_baseline()
        with self.assertRaisesRegex(Exception, "export client role differs"):
            self.lua.execute('drive_action("de","full")')

        self.setUp(); self.initialize_baseline()
        with self.assertRaisesRegex(Exception, "export action differs"):
            self.lua.execute('drive_action("en","compact")')

        self.setUp(); self.initialize_baseline()
        with self.assertRaisesRegex(Exception, "owned export GUI path differs"):
            self.lua.execute(r'''
              local root=select(1,root_for(player_en,3))
              local foreign=element(root,"button","mir_library_export_settings")
              emit(defines.events.on_gui_click,{player_index=1,element=foreign})
            ''')

        self.setUp(); self.initialize_baseline()
        with self.assertRaisesRegex(Exception, "MIRSET1 preview differs"):
            self.lua.execute('drive_action("en","full","bad-profile")')

        self.setUp(); self.initialize_baseline()
        self.lua.execute('drive_action("en","full");drive_action("en","compact")')
        with self.assertRaisesRegex(Exception, "diagnostic preview differs"):
            self.lua.execute('drive_action("en","diagnostics","bad-report")')

        self.setUp(); self.initialize_baseline()
        with self.assertRaisesRegex(Exception, "fresh native frame (differs|changed)"):
            self.lua.execute('drive_action("en","full",nil,true)')

        self.setUp(); self.initialize_baseline()
        self.lua.execute('drive_action("en","full")')
        with self.assertRaisesRegex(Exception, "assertion failed"):
            self.lua.execute(r'''
              local row=writes[1]["mir-library-fresh-export-input/01-en-full.json"]
              external_files[1]["more-infinite-research/settings/mir-settings-profile.txt"]="forged\n"
              assert_external_bytes(1,row)
            ''')

    def test_helper_closure_and_deferred_snapshot_are_required(self):
        self.lua.execute(r'''
          initialize()
          emit(defines.events.on_player_joined_game,{player_index=1})
          emit(defines.events.on_player_joined_game,{player_index=2})
          tick()
          helpers=nil
        ''')
        with self.assertRaisesRegex(Exception, "phase output helpers unavailable"):
            self.lua.execute("tick()")

        self.setUp(); self.initialize_baseline()
        self.lua.execute(r'''
          local player,button=button_for("en","full")
          emit(defines.events.on_gui_click,{player_index=player.index,element=button})
          assert(storage.mir_fresh_export_input.phase=="settling-export")
          assert(writes[1]["mir-library-fresh-export-input/01-en-full.json"]==nil)
          apply_export(player,"full");tick()
          assert(writes[1]["mir-library-fresh-export-input/01-en-full.json"]~=nil)
        ''')

    def test_executed_observer_cannot_write_gui_fields_through_aliases_or_brackets(self):
        for statement, setup in (
            ('local alias=player_en;alias.opened=nil', 'settings_button(player_en,"full")'),
            ('local alias=player_en;alias["opened"]=nil', 'settings_button(player_en,"full")'),
            ('local alias=player_en.gui.screen.mir_research_browser.mir_library_tabs.mir_library_settings_content.mir_library_export_profile;alias.text="forged"',
             'local _,content=settings_button(player_en,"full");apply_export(player_en,"full")'),
        ):
            with self.subTest(statement=statement):
                self.setUp(actor_source='script.on_event(defines.events.on_tick,function() ' + statement + ' end)')
                self.lua.execute(setup)
                with self.assertRaisesRegex(Exception, "observer GUI mutation"):
                    self.lua.execute("tick()")

    def test_metadata_readme_and_passivity_contract(self):
        expected = {
            "name": "mir-fixture-library-fresh-export-input",
            "version": "0.1.0",
            "title": "MIR fresh Library export input observer",
            "author": "MIR maintainers",
            "factorio_version": "2.1",
            "dependencies": ["base = 2.1.24", "~ more-infinite-research = " + MIR_517_F210],
        }
        self.assertEqual(json.loads((FIXTURE / "info.json").read_text(encoding="utf-8")), expected)
        code = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        for forbidden in ("remote.call", "script.raise_event", "server_save", "auto_save", "require(",
                          ".researched =", ".level =", "research_queue =", "player.opened ="):
            self.assertNotIn(forbidden, code)
        self.assertIsNone(GUI_FIELD_ASSIGNMENT.search(code))
        self.assertIn('script.on_event(defines.events.on_gui_click, on_click)', code)
        self.assertIn('script.on_event(defines.events.on_tick, settle)', code)
        self.assertIn('"00-baseline.json"', code)
        self.assertIn('"MIRSET1 preview differs"', code)
        self.assertIn('"fresh earned provider frame differs"', code)
        self.assertIn("LOCALE_READY_TICKS = 1800", code)
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        self.assertIn("0dac003903a317137cf993b5bd22074a3e5013a8", readme)
        self.assertIn("locale=en", readme)
        self.assertIn("R09", readme)
        self.assertIn("does not prove desktop delivery", readme)

    def test_shared_lexical_assignment_guard_keeps_its_narrow_intended_scope(self):
        for code in (
            "player.opened = root",
            'query.text = "forged"',
            "root.opened\t= nil",
            'query.text\n= "forged"',
        ):
            with self.subTest(code=code):
                self.assertIsNotNone(GUI_FIELD_ASSIGNMENT.search(code))
        for code in (
            "if player.opened == root then return end",
            "local text = query.text",
            "some_player.opened = root",
            "player.opened_caption = root",
        ):
            with self.subTest(code=code):
                self.assertIsNone(GUI_FIELD_ASSIGNMENT.search(code))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryFreshExportInputControls)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

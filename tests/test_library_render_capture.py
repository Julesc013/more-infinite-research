"""Host controls for render-only public Library screenshots; no native verdict."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-render-capture"


class LibraryRenderCaptureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          local tick_callback
          handlers={}
          defines={controllers={cutscene=6}}
          storage={}
          script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21012"},
            on_nth_tick=function(n,fn) assert(n==30);tick_callback=fn end,
            on_init=function(fn) handlers.init=fn end,
            on_configuration_changed=function(fn) handlers.configuration=fn end}
          local tech={name="worker-robots-storage-4",level=4,researched=false,enabled=true}
          local force={technologies={[tech.name]=tech},recipes={iron={enabled=true}},
            research_queue={},research_progress=0,worker_robots_storage_bonus=0}
          local tabs={valid=true,selected_tab_index=1}
          local root={valid=true,mir_library_tabs=tabs,location={x=20,y=30},
            style={minimal_width=1100,maximal_width=1100,maximal_height=800},
            get_mod=function() return "more-infinite-research" end}
          player={valid=true,connected=true,index=1,locale="en",force=force,controller_type=1,
            display_scale=1.25,display_resolution={width=1920,height=1080},
            gui={screen={mir_research_browser=root}}}
          screenshots,writes,calls,flushes={}, {}, {},0
          game={tick=0,
            connected_players={player},take_screenshot=function(args)
              assert(args.show_gui and args.force_render and args.by_player==1 and args.player==player)
              assert(args.resolution==nil and args.anti_alias==false)
              screenshots[#screenshots+1]={args=args,tick=game.tick}
            end,set_wait_for_screenshots_to_finish=function() flushes=flushes+1 end}
          setmetatable(game,{__index=function(_,key) error("undeclared LuaGameScript member: "..key) end})
          intro_sets,intro_flag=0,nil
          remote={interfaces={["more-infinite-research-browser"]={open=true},
            freeplay={get_skip_intro=true,set_skip_intro=true}},
            call=function(interface,method,index,options)
              if interface=="freeplay" then
                if method=="get_skip_intro" then return intro_flag end
                assert(method=="set_skip_intro" and index==true)
                intro_sets=intro_sets+1;intro_flag=true;return
              end
              assert(interface=="more-infinite-research-browser" and method=="open" and index==1)
              if #screenshots>0 then assert(game.tick-screenshots[#screenshots].tick>=60) end
              calls[#calls+1]=options
              tabs.selected_tab_index=({research=1,queue=2,settings=3,help=4,availability=1})[options.tab]
              return true
            end}
          helpers={table_to_json=function(value) return value end,
            write_file=function(path,value,append,index)
              assert(append==false and index==1);writes[path]=value
            end}
          log=function() end
          dofile(actor_path)
          handlers.init()
          function step(n) for i=1,n do game.tick=game.tick+30;tick_callback() end end
          function run() step(100) end
        ''')

    def test_all_pages_are_public_real_gui_render_requests(self):
        self.lua.execute(r'''
          run()
          assert(#calls==7 and #screenshots==7 and flushes==1)
          assert(calls[1].tab=="research" and calls[2].tab=="queue")
          assert(calls[3].settings_scope=="research" and calls[4].settings_scope=="options")
          assert(calls[5].tab=="help" and calls[6].tab=="availability" and calls[7].search=="robot")
          local report=writes["mir-library-render/en/complete.json"]
          assert(report and #report.observations==7 and report.native_snapshot_unchanged)
          assert(report.input_acceptance==false and report.settings_menu_acceptance==false)
          assert(report.export_acceptance==false and report.lifecycle_acceptance==false)
          assert(report.release_qualification==false)
          assert(report.observations[1].display_scale==1.25)
          assert(report.observations[1].display_resolution.width==1920)
          assert(report.observations[1].minimal_width==1100)
        ''')

    def test_german_uses_actual_locale_and_separate_output(self):
        self.lua.execute('player.locale="de";run();assert(writes["mir-library-render/de/complete.json"])')

    def test_exact_engine_and_package_are_required(self):
        for opponent in ['script.active_mods.base="2.1.24"',
                         'script.active_mods["more-infinite-research"]="5.0.21011"']:
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute(opponent)
                with self.assertRaisesRegex(Exception, "exact engine/package"):
                    self.lua.execute('step(1)')

    def test_non_declared_locale_or_absent_scale_refuses(self):
        for opponent in ['player.locale="fr"', 'player.display_scale=0']:
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute(opponent)
                with self.assertRaises(Exception):
                    self.lua.execute('step(1)')

    def test_multiple_players_or_disconnect_refuses(self):
        self.lua.execute('game.connected_players[2]=player')
        with self.assertRaisesRegex(Exception, "one connected player"):
            self.lua.execute('step(1)')
        self.setUp()
        self.lua.execute('step(1);player.connected=false')
        with self.assertRaisesRegex(Exception, "disconnected"):
            self.lua.execute('step(6)')

    def test_named_native_state_changes_refuse_before_screenshot(self):
        for opponent in ['player.force.technologies["worker-robots-storage-4"].level=5',
                         'player.force.recipes.iron.enabled=false',
                         'player.force.research_progress=0.5',
                         'player.force.worker_robots_storage_bonus=1',
                         'player.force.research_queue={{name="worker-robots-storage-4"}}']:
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute('step(1);' + opponent)
                with self.assertRaisesRegex(Exception, "named native"):
                    self.lua.execute('run()')
                self.assertEqual(self.lua.eval('#screenshots'), 0)

    def test_missing_or_foreign_root_and_wrong_tab_refuse(self):
        for opponent in ['player.gui.screen.mir_research_browser.valid=false',
                         'player.gui.screen.mir_research_browser.get_mod=function() return "foreign" end',
                         'remote.call=function() return true end']:
            with self.subTest(opponent=opponent):
                self.setUp()
                self.lua.execute(opponent)
                with self.assertRaises(Exception):
                    self.lua.execute('run()')
                self.assertNotEqual(self.lua.eval('storage.mir_render_capture.phase'), 'complete')

    def test_render_settlement_and_completion_are_bounded_and_separate(self):
        self.lua.execute(r'''
          step(1);assert(#calls==0 and #screenshots==0)
          step(6);assert(#calls==1 and #screenshots==0)
          step(6);assert(#screenshots==1 and writes["mir-library-render/en/complete.json"]==nil)
          local first=game.tick
          step(1);assert(#calls==1)
          run();assert(screenshots[1].tick==first and flushes==1)
          local count=#calls;run();assert(#calls==count and #screenshots==7 and flushes==1)
        ''')

    def test_public_freeplay_setup_prevents_intro_modal_without_input_or_save(self):
        self.lua.execute(r'''
          assert(intro_sets==1 and intro_flag==true)
          assert(storage.mir_render_setup.original_flag_unset and not storage.mir_render_setup.original_skip_intro)
          assert(storage.mir_render_setup.saved_to_original==false)
          handlers.configuration()
          assert(intro_sets==2 and storage.mir_render_setup.original_flag_unset)
          run()
          assert(writes["mir-library-render/en/complete.json"].scenario_setup==storage.mir_render_setup)
        ''')
        self.setUp()
        self.lua.execute('remote.interfaces.freeplay=nil')
        with self.assertRaisesRegex(Exception, "freeplay setup interface absent"):
            self.lua.execute('handlers.configuration()')

    def test_unsuppressed_750_tick_base_intro_stalls_after_two_captures(self):
        # Independent installed Base cutscene:450 transition+150 wait+150 transition,
        # then show_message_dialog pauses ticks unless freeplay.skip_intro is set.
        modal_model = r'''
          local advance=step
          function step(n)
            for i=1,n do
              if game.tick<750 or intro_flag then advance(1) end
            end
          end
        '''
        self.lua.execute(modal_model + 'intro_flag=nil;run();assert(#screenshots==2);assert(writes["mir-library-render/en/complete.json"]==nil)')
        self.setUp()
        self.lua.execute(modal_model + 'run();assert(#screenshots==7);assert(writes["mir-library-render/en/complete.json"])')

    def test_initial_cutscene_finishes_naturally_before_any_library_open(self):
        self.lua.execute(r'''
          player.controller_type=defines.controllers.cutscene
          step(30)
          assert(storage.mir_render_capture==nil and #calls==0 and #screenshots==0)
          player.controller_type=1
          run()
          assert(#screenshots==7 and writes["mir-library-render/en/complete.json"])
        ''')

    def test_locale_may_settle_before_first_render_but_not_during_sequence(self):
        self.lua.execute('step(1);player.locale="de";run();assert(writes["mir-library-render/de/complete.json"])')
        self.setUp()
        self.lua.execute('step(7);player.locale="de"')
        with self.assertRaisesRegex(Exception, "locale changed"):
            self.lua.execute('run()')

    def test_fixture_metadata_and_no_mutation_authority(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["dependencies"], ["base = 2.1.23", "~ more-infinite-research = 5.0.21012"])
        code = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        for forbidden in ["remote.add_interface", "raise_event", "require(", "server_save", "auto_save",
                          "research_queue =", ".researched =", ".level =", "root.style.width ="]:
            self.assertNotIn(forbidden, code)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LibraryRenderCaptureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

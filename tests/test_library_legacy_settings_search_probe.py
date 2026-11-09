"""Fixed test-only preparation for legacy Library Settings search observations."""
import argparse
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tests/fixtures/library-legacy-settings-search/probe.lua"


def plain(value):
    if not hasattr(value, "items"):
        return value
    values = list(value.items())
    if values and {key for key, _ in values} == set(range(1, len(values) + 1)):
        return [plain(value[index]) for index in range(1, len(values) + 1)]
    return {key: plain(item) for key, item in values}


class LibraryLegacySettingsSearchProbeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().probe_path = PROBE.as_posix()
        self.lua.execute(r'''
          function run_legacy_settings_probe(opponent, invalid)
            local tick,world=0,1
            local calls={}
            local function node(parent,element_type,name,mod)
              local value={valid=true,type=element_type,name=name,parent=parent,children={},tags={},items={},caption={},text=""}
              function value.get_mod() return mod end
              if parent then parent[name]=value;parent.children[#parent.children+1]=value end
              return value
            end
            local screen=node(nil,"screen","screen","fixture")
            local player={valid=true,index=47,gui={screen=screen}}
            local frame,tabs,research,settings,settings_query,research_query,list,count,scope_label
            local retained_tab,retained_scope,retained_research,retained_settings="research","research","science",""
            local function render(options)
              if not frame then
                local root_mod=opponent=="foreign-ownership" and "other" or "more-infinite-research"
                frame=node(screen,"frame","mir_research_browser",root_mod)
                frame.tags["more-infinite-research.library-root.v1"]=true
                tabs=node(frame,"tabbed-pane","mir_library_tabs",root_mod)
                local page=node(tabs,"scroll-pane","mir_library_research_page",root_mod)
                local filters=node(page,"flow","mir_library_filters",root_mod)
                research_query=node(filters,"textfield","mir_library_query",root_mod)
                settings=node(tabs,"scroll-pane","mir_library_settings_content",root_mod)
                settings_query=node(settings,"textfield","mir_library_settings_query",root_mod)
                if opponent=="malformed-query" then settings_query.type="label" end
                local dynamic=node(settings,"table","mir_library_settings_dynamic",root_mod)
                list=node(dynamic,"list-box","mir_library_settings_list",root_mod)
                count=node(dynamic,"label","mir_library_settings_count",root_mod)
                scope_label=node(dynamic,"label","mir_library_settings_scope_label",root_mod)
              end
              local requested=options.tab
              if opponent=="old-route-only-changes-research" then requested="research" end
              if requested=="research" or requested=="settings" then retained_tab=requested end
              if options.settings_scope=="research" or options.settings_scope=="options" then retained_scope=options.settings_scope end
              if type(options.search)=="string" then
                local text=opponent=="unbounded-no-match" and options.search or options.search:sub(1,160)
                if retained_tab=="settings" then retained_settings=text else retained_research=text end
              end
              if opponent=="wrong-scope" and options.settings_scope=="options" then retained_scope="research" end
              if opponent=="transient-research-leak" and retained_tab=="settings" then
                retained_research=retained_settings=="repair" and "leaked" or "science"
              end
              research_query.text=retained_research;settings_query.text=retained_settings
              tabs.selected_tab_index=retained_tab=="settings" and 3 or 1
              local items
              if retained_scope=="research" then
                items=retained_settings=="" and {"Research growth","Research costs"} or {}
              elseif opponent=="unfiltered-rows" and retained_settings=="repair" then
                items={"Passive repair","Recipe options","Default options"}
              elseif retained_settings=="" then
                items={"Passive repair","Recipe options","Default options"}
              elseif retained_settings=="repair" then
                items={"Passive repair"}
              elseif retained_settings=="default" then
                items={"Default options"}
              else items={} end
              if opponent=="wrong-query" and retained_settings=="repair" then settings_query.text="wrong" end
              list.items=items;count.caption={"mir-browser.settings-count",#items}
              scope_label.caption={"mir-browser.settings-scope-" .. (opponent=="stale-scope-label" and "research" or retained_scope)}
            end
            remote={call=function(interface,method,index,options)
              if interface~="more-infinite-research-browser" or method~="open" or index~=player.index then error("wrong remote facade") end
              calls[#calls+1]=options;render(options);return true
            end}
            local probe=assert(loadfile(probe_path))().new({player=player,research_query="science",tick=function()return tick end,
              assert_world=function()if world~=1 then error("protected world changed")end end})
            if invalid=="early" then probe.prepare("research");return pcall(function()probe.check("research")end) end
            if invalid=="order" then return pcall(function()probe.prepare("settings-options-baseline")end) end
            if invalid=="wrong-check" then probe.prepare("research");tick=30;return pcall(function()probe.check("settings-options-baseline")end) end
            for _,stage in ipairs({"research","settings-options-baseline","settings-options-repair","settings-options-retained-default","settings-options-no-match","restore-settings-options-empty","restore-research"}) do
              probe.prepare(stage)
              if opponent=="world-mutation" and stage=="settings-options-repair" then world=2 end
              tick=tick+30
              probe.check(stage)
            end
            local result=probe.report()
            return result,calls
          end
        ''')

    def test_fixed_sequence_records_owned_settings_projection_and_restores_queries(self):
        result, calls = self.lua.globals().run_legacy_settings_probe("", "")
        result, calls = plain(result), plain(calls)
        self.assertIsNone(result.get("next_stage"))
        self.assertEqual(result["research_text"], "science")
        observations = result["observations"]
        self.assertEqual(observations["settings-options-baseline"]["list_count"], 3)
        self.assertEqual(observations["settings-options-repair"]["list_items"], ["Passive repair"])
        self.assertEqual(observations["settings-options-retained-default"]["list_count"], 1)
        self.assertEqual(observations["settings-options-no-match"]["settings_text"], "x" * 160)
        self.assertEqual(observations["settings-options-no-match"]["list_count"], 0)
        self.assertEqual(observations["restore-settings-options-empty"]["settings_text"], "")
        self.assertEqual(observations["restore-research"]["research_text"], "science")
        self.assertEqual(observations["restore-research"]["settings_text"], "")
        self.assertEqual(observations["restore-research"]["selected_tab"], 1)
        for stage in ("settings-options-baseline", "settings-options-repair", "settings-options-retained-default",
                      "settings-options-no-match", "restore-settings-options-empty", "restore-research"):
            self.assertEqual(observations[stage]["scope_caption"], ["mir-browser.settings-scope-options"])
        self.assertEqual([call.get("tab") for call in calls], ["research", "settings", "settings", None, None, "settings", "research"])
        self.assertEqual(calls[1], {"tab": "settings", "settings_scope": "options", "search": ""})
        self.assertEqual(calls[2], {"tab": "settings", "settings_scope": "options", "search": "repair"})
        self.assertEqual(calls[3], {"search": "default"})
        self.assertEqual(calls[4], {"search": "x" * 161})
        self.assertEqual(calls[5], {"tab": "settings", "settings_scope": "options", "search": ""})
        self.assertEqual(calls[6], {"tab": "research"})

    def test_rejects_wrong_remote_projection_or_protected_world_mutation(self):
        for opponent in ("old-route-only-changes-research", "wrong-query", "wrong-scope", "stale-scope-label", "unfiltered-rows", "foreign-ownership",
                         "malformed-query", "unbounded-no-match", "transient-research-leak", "world-mutation"):
            with self.subTest(opponent=opponent):
                with self.assertRaises(Exception):
                    self.lua.globals().run_legacy_settings_probe(opponent, "")

    def test_rejects_early_and_out_of_order_operations(self):
        for invalid in ("early", "order", "wrong-check"):
            with self.subTest(invalid=invalid):
                ok, message = self.lua.globals().run_legacy_settings_probe("", invalid)
                self.assertFalse(ok)
                self.assertIn("stage/order" if invalid != "early" else "settle", str(message))

    def test_helper_remains_preparation_only_without_dispatch_or_fixture_metadata(self):
        source = PROBE.read_text(encoding="utf-8")
        self.assertIn('remote.call(BROWSER, "open", player.index, options)', source)
        self.assertNotIn("remote.add_interface", source)
        self.assertNotIn("script.on_", source)
        self.assertNotIn("game.server_save", source)
        fixture = PROBE.parent
        self.assertFalse((fixture / "control.lua").exists())
        self.assertFalse((fixture / "info.json").exists())

    def test_real_library_search_finds_repair_only_in_other_options(self):
        import test_library

        test_library.LuaRuntime = LuaRuntime
        case = test_library.LibraryTests()
        case.setUp()
        case.lua.execute(r'''
          boot()
          local function count(scope)
            local root=library.open(player,{tab="settings",settings_scope=scope,search="repair"})
            local dynamic=root.mir_library_tabs.mir_library_settings_content.mir_library_settings_dynamic
            return #dynamic.mir_library_settings_list.items,storage.mir_library.players[1].settings_scope
          end
          local options,options_scope=count("options")
          local research,research_scope=count("research")
          assert(options_scope=="options" and options>0,"passive repair must be found in Other options")
          assert(research_scope=="research" and research==0,"passive repair must not enter Research settings")
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryLegacySettingsSearchProbeTests))
    sys.exit(0 if result.wasSuccessful() else 1)

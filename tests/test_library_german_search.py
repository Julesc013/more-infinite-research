"""EN/DE search regressions through the existing model and runtime fixtures."""
import argparse
from pathlib import Path
import sys
import unittest

import test_library
import test_library_model


class GermanSearchTests(unittest.TestCase):
    def test_model_matches_german_case_and_sharp_s_without_changing_query(self):
        fixture = test_library_model.LibraryModelTests()
        fixture.setUp()
        fixture.lua.execute(r'''
          local id = "recipe-prod-research_gears-1"
          local force = {technologies = {[id] = technology(id)}, research_queue = {}}
          local declared = {{id = id, family = "research_gears"}}
          for _, pair in ipairs{{"GRÖSSERE", "Größere"}, {"FUSS", "Fuß"},
            {"FÜSSE", "Füße"}, {"ÄÖÜ", "äöü"}, {"GROẞ", "groß"},
            {"GEAR_WHEEL", "Gear-Wheel"}, {"齿轮", "齿轮"}} do
            local view = {search = pair[1]}
            assert(#model.rows(force, declared, view, {[id] = pair[2]}) == 1,
              "search failed for " .. pair[1] .. " / " .. pair[2])
            assert(view.search == pair[1], "matching rewrote caller query bytes")
          end
          assert(#model.rows(force, declared, {search="FUXX"}, {[id]="Fuß"}) == 0)
        ''')

    def test_runtime_late_research_translation_matches_and_preserves_saved_query(self):
        fixture = test_library.LibraryTests()
        fixture.setUp()
        fixture.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          local root = library.open(player)
          local request = assert(player.translation_requests[1])
          local query = research_filters(root).mir_library_query
          query.text = "FUSS"
          library.on_gui_text_changed{player_index=1, element=query}
          game.tick = game.tick + 1
          library.on_string_translated{player_index=1, id=request.id,
            translated=true, result="Fuß"}
          local list = research_content(root).mir_library_list_pane.mir_library_results
          assert(#list.items == 1, "late German translation did not match saved research query")
          assert(query.text == "FUSS" and storage.mir_library.players[1].query == "FUSS",
            "translation or matching rewrote saved research query bytes")
        ''')

    def test_runtime_late_settings_translation_matches_and_preserves_saved_query(self):
        fixture = test_library.LibraryTests()
        fixture.setUp()
        fixture.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          local catalog = require("research.settings")
          local target = catalog.registered_names()[1]
          local spec = catalog.spec(target)
          local scope = spec.stream and "research" or "options"
          local prototypes = {}
          for _, prototype in ipairs(catalog.prototypes()) do prototypes[prototype.name] = prototype end
          local root = library.open(player, {tab="settings", settings_scope=scope})
          local function equal(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
            for key in pairs(b) do if a[key] == nil then return false end end
            return true
          end
          local request
          for _, value in ipairs(player.translation_requests) do
            if equal(value.localised, prototypes[target].localised_name) then request=value; break end
          end
          assert(request, "target setting label was not requested")
          local content = root.mir_library_tabs.mir_library_settings_content
          local query = content.mir_library_settings_query
          query.text = "FUSSREICHWEITE"
          library.on_gui_text_changed{player_index=1, element=query}
          game.tick = game.tick + 1
          -- Settings translations refresh in the existing batches of eight.
          for index = 1, 8 do
            local reply = player.translation_requests[index]
            assert(reply)
            library.on_string_translated{player_index=1, id=reply.id,
              translated=true, result=reply.id == request.id and "Größere Fußreichweite"
                or ("unrelated-setting-" .. reply.id)}
          end
          local dynamic = content.mir_library_settings_dynamic
          assert(#dynamic.mir_library_settings_list.items == 1,
            "late German setting translation did not match saved Settings query")
          assert(query.text == "FUSSREICHWEITE"
            and storage.mir_library.players[1].settings_query == "FUSSREICHWEITE",
            "translation or matching rewrote saved Settings query bytes")
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--player-source-root", type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    test_library.LuaRuntime = test_library_model.LuaRuntime = LuaRuntime
    if args.player_source_root is not None:
        test_library.ROOT = test_library_model.ROOT = args.player_source_root.resolve(strict=True).parent
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(GermanSearchTests))
    sys.exit(0 if result.wasSuccessful() else 1)

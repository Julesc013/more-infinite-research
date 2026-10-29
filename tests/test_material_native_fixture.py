"""Host controls for the private K2SO finite-material native fixture.

The production result remains a Factorio-native observation.  These checks
exercise the fixture's own data preflight and reload opponents without
building a ZIP or launching Factorio.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/materials"
NAMES = (
    "recipe-prod-research_material_rare_metals-1",
    "recipe-prod-research_material_silicon-1",
    "recipe-prod-research_material_glass-1",
)


class MaterialNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().data_final_fixes = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          local names = {
            "recipe-prod-research_material_rare_metals-1",
            "recipe-prod-research_material_silicon-1",
            "recipe-prod-research_material_glass-1",
          }

          function material_rows()
            local rows = {}
            local function technology(name, prerequisites, science, recipes)
              local effects = {}
              for index, recipe in ipairs(recipes) do
                effects[index] = {type="change-recipe-productivity", recipe=recipe, change=.02}
              end
              local ingredients = {}
              for index, pack in ipairs(science) do ingredients[index] = {pack, 1} end
              return {
                type="technology", name=name, level=1, upgrade=true, max_level=3,
                prerequisites=prerequisites, effects=effects,
                unit={count_formula="200*2^(L-1)", time=30, ingredients=ingredients},
              }
            end
            rows[names[1]] = technology(names[1], {
              "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "kr-rare-metal-processing", "kr-enriched-ores",
            }, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
              {"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"})
            rows[names[2]] = technology(names[2], {
              "automation-science-pack", "logistic-science-pack", "kr-silicon-processing",
            }, {"automation-science-pack", "logistic-science-pack"}, {"kr-silicon"})
            rows[names[3]] = technology(names[3], {
              "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "kr-stone-processing",
            }, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, {"kr-glass"})
            return rows
          end

          function run_material_data_fixture(path, opponent)
            local rows = material_rows()
            if opponent == "effects" then rows[names[1]].effects[1].change = .03 end
            if opponent == "science" then rows[names[2]].unit.ingredients[1][1] = "chemical-science-pack" end
            if opponent == "maximum" then rows[names[3]].max_level = 4 end
            data = {raw={technology=rows}}
            local chunk, message = loadfile(path, "t", _G)
            assert(chunk, message)
            local ok, result = pcall(chunk)
            return {ok=ok, message=tostring(result), rows=rows}
          end

          function parse_material_control(path)
            local callbacks, forbidden = {events={}}, {reads={}}
            local environment = {
              script = {
                active_mods = {base="2.1.23", ["Krastorio2-spaced-out"]="2.0.19",
                  ["more-infinite-research"]="5.0.21000"},
                on_init = function(callback) callbacks.init = callback end,
                on_load = function(callback) callbacks.load = callback end,
                on_event = function(event, callback) callbacks.events[event] = callback end,
              },
              defines = {events={on_tick=1, on_research_finished=2}, inventory={lab_input=1}},
            }
            environment._G = environment
            setmetatable(environment, {__index=function(_, key)
              if key == "game" or key == "storage" then
                forbidden.reads[key] = (forbidden.reads[key] or 0) + 1
              end
              return _G[key]
            end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk, message)
            local ok, result = pcall(chunk)
            return {ok=ok, message=tostring(result), callbacks=callbacks, forbidden=forbidden}
          end

          local function material_technology(name, recipes, level, researched, enabled, visible)
            local effects = {}
            for index, recipe in ipairs(recipes) do
              effects[index] = {type="change-recipe-productivity", recipe=recipe, change=.02}
            end
            return {name=name, level=level, researched=researched, enabled=enabled,
              visible_when_disabled=visible, prototype={max_level=3, effects=effects}}
          end

          local function completed_force(name, index, foreign)
            local force = {name=name, index=index, valid=true, technologies={}, recipes={},
              laboratory_productivity_bonus=0, research_queue={}, current_research=nil}
            force.technologies[names[1]] = material_technology(names[1],
              {"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"}, foreign and 1 or 3,
              false, not foreign, false)
            force.technologies[names[2]] = material_technology(names[2], {"kr-silicon"},
              foreign and 1 or 3, false, not foreign, false)
            force.technologies[names[3]] = material_technology(names[3], {"kr-glass"},
              foreign and 1 or 3, false, not foreign, false)
            if not foreign then
              for _, value in pairs(force.technologies) do value.researched = true end
            end
            for _, recipe in ipairs({"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals",
              "kr-silicon", "kr-glass"}) do
              force.recipes[recipe] = {productivity_bonus=foreign and 0 or .06}
            end
            return force
          end

          function reload_material_control(path, opponent)
            local callbacks, markers = {events={}}, 0
            local player = completed_force("player", 1, false)
            local foreign = completed_force("mir5-materials-foreign", 2, true)
            local remaining = {
              ["automation-science-pack"]=23, ["logistic-science-pack"]=23,
              ["chemical-science-pack"]=26,
            }
            local inventory = {get_item_count=function(name) return remaining[name] end}
            local lab = {valid=true, get_inventory=function(index)
              assert(index == 1, "unexpected inventory")
              return inventory
            end}
            local state = {phase="complete", finished=9, next=10, foreign_index=2, lab=lab, deadline=36000}
            local storage = {["mir5_native_materials"]=state}
            local environment = {
              script = {
                active_mods = {base="2.1.23", ["Krastorio2-spaced-out"]="2.0.19",
                  ["more-infinite-research"]="5.0.21000"},
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end,
              },
              defines = {events={on_tick=1, on_research_finished=2}, inventory={lab_input=1}},
              game = {tick=100, forces={player=player, [2]=foreign}},
              storage = storage,
              helpers = {table_to_json=function(value)
                assert(value.case == "materials" and value.stage == "reload" and value.status == "passed")
                return "{}"
              end},
              log = function(message)
                assert(message:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))
                markers = markers + 1
              end,
            }
            environment._G = environment
            setmetatable(environment, {__index=function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk, message)
            assert(pcall(chunk))
            local saved_phase, saved_finished, saved_next = state.phase, state.finished, state.next
            local load_ok, load_message = pcall(callbacks.load)
            local on_load_read_only = state.phase == saved_phase and state.finished == saved_finished
              and state.next == saved_next
            if opponent == "lost-bonus" then player.recipes["kr-silicon"].productivity_bonus = .04 end
            if opponent == "lost-earned" then
              local value = player.technologies[names[1]]
              value.level, value.researched = 2, false
            end
            if opponent == "foreign" then foreign.technologies[names[3]].enabled = true end
            if opponent == "science" then remaining["chemical-science-pack"] = 27 end
            local tick_ok, tick_message = pcall(callbacks.events[1])
            return {load_ok=load_ok, load_message=tostring(load_message), tick_ok=tick_ok,
              tick_message=tostring(tick_message), on_load_read_only=on_load_read_only,
              markers=markers, phase=state.phase, finished=state.finished, next=state.next}
          end
        ''')

    def test_info_pins_the_k2so_fixture_to_the_native_player_package(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual("mir-fixture-mir5-materials", info["name"])
        self.assertEqual("0.1.0", info["version"])
        self.assertEqual("2.1", info["factorio_version"])
        self.assertEqual([
            "base >= 2.1.23", "space-age", "Krastorio2-spaced-out",
            "more-infinite-research = 5.0.21000",
        ], info["dependencies"])

    def test_data_preflight_keeps_exact_default_rows_then_accelerates_only_unit_cost_and_time(self):
        result = self.lua.eval("run_material_data_fixture")(self.lua.globals().data_final_fixes, "")
        self.assertTrue(result["ok"], result["message"])
        expected = {
            NAMES[0]: (["automation-science-pack", "logistic-science-pack", "chemical-science-pack"],
                       ["kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"]),
            NAMES[1]: (["automation-science-pack", "logistic-science-pack"], ["kr-silicon"]),
            NAMES[2]: (["automation-science-pack", "logistic-science-pack", "chemical-science-pack"],
                       ["kr-glass"]),
        }
        for name, (science, recipes) in expected.items():
            with self.subTest(name=name):
                row = result["rows"][name]
                self.assertEqual(1, row["level"])
                self.assertTrue(row["upgrade"])
                self.assertEqual(3, row["max_level"])
                self.assertIsNone(row["unit"]["count"])
                self.assertEqual("1", row["unit"]["count_formula"])
                self.assertEqual(1, row["unit"]["time"])
                self.assertEqual(science, [row["unit"]["ingredients"][index][1]
                                           for index in range(1, len(science) + 1)])
                self.assertEqual(recipes, [row["effects"][index]["recipe"]
                                           for index in range(1, len(recipes) + 1)])
                self.assertTrue(all(row["effects"][index]["type"] == "change-recipe-productivity"
                                    and row["effects"][index]["change"] == 0.02
                                    for index in range(1, len(recipes) + 1)))

    def test_data_preflight_rejects_effect_science_or_maximum_drift_before_any_acceleration(self):
        for opponent, expected in (("effects", "effect changed"), ("science", "science changed"),
                                   ("maximum", "finite progression changed")):
            with self.subTest(opponent=opponent):
                result = self.lua.eval("run_material_data_fixture")(self.lua.globals().data_final_fixes, opponent)
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                for name in NAMES:
                    row = result["rows"][name]
                    self.assertIsNone(row["unit"]["count"])
                    self.assertEqual("200*2^(L-1)", row["unit"]["count_formula"])
                    self.assertEqual(30, row["unit"]["time"])

    def test_control_registration_is_game_and_storage_free_and_uses_native_event_flow(self):
        result = self.lua.eval("parse_material_control")(self.lua.globals().control_path)
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNone(result["forbidden"]["reads"]["game"])
        self.assertIsNone(result["forbidden"]["reads"]["storage"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        self.assertIsNotNone(result["callbacks"]["events"][2])
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('surface.create_entity{', source)
        self.assertIn("defines.inventory.lab_input", source)
        self.assertIn("game.speed = 16", source)
        self.assertIn("force.add_research", source)
        self.assertIn("game.server_save(SAVE)", source)
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("enable_all_prototypes", source)
        self.assertNotIn("force.research_queue =", source)
        finished_handler = source.split("script.on_event(defines.events.on_research_finished", 1)[1].split(
            "script.on_load", 1
        )[0]
        self.assertNotIn("add_research", finished_handler)

    def test_reload_reasserts_earned_native_state_foreign_isolation_and_science_without_writing_on_load(self):
        passed = self.lua.eval("reload_material_control")(self.lua.globals().control_path, "")
        self.assertTrue(passed["load_ok"], passed["load_message"])
        self.assertTrue(passed["on_load_read_only"])
        self.assertTrue(passed["tick_ok"], passed["tick_message"])
        self.assertEqual(1, passed["markers"])
        self.assertEqual(("complete", 9, 10), (passed["phase"], passed["finished"], passed["next"]))

        for opponent, expected in (
            ("lost-bonus", "productivity bonus changed"),
            ("lost-earned", "did not retain its three earned finite stages"),
            ("foreign", "foreign material state changed"),
            ("science", "science consumption changed"),
        ):
            with self.subTest(opponent=opponent):
                result = self.lua.eval("reload_material_control")(self.lua.globals().control_path, opponent)
                self.assertTrue(result["load_ok"], result["load_message"])
                self.assertTrue(result["on_load_read_only"])
                self.assertFalse(result["tick_ok"])
                self.assertIn(expected, result["tick_message"])
                self.assertEqual(0, result["markers"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MaterialNativeFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

"""Focused host controls for the F210 fresh science earned-effect transition."""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/fresh-science-transition"
PROFILES = ROOT / "tests/profiles"


class FreshScienceTransitionFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function run_transition_settings(path, version, base_default, time_default)
            mods = {base="2.1.23", ["space-age"]="2.1.23", ["more-infinite-research"]=version}
            data = {raw={ ["int-setting"]={
              ["ips-cost-base-research_science_pack_productivity"]={type="int-setting", default_value=base_default},
              ["ips-research-time-research_science_pack_productivity"]={type="int-setting", default_value=time_default},
              untouched={type="int-setting", default_value=77},
            }}}
            local ok, message = pcall(dofile, path)
            return {ok=ok, message=tostring(message),
              base=data.raw["int-setting"]["ips-cost-base-research_science_pack_productivity"].default_value,
              time=data.raw["int-setting"]["ips-research-time-research_science_pack_productivity"].default_value,
              untouched=data.raw["int-setting"].untouched.default_value}
          end

          function run_transition_final(path, opponent)
            local TARGET = "recipe-prod-research_science_pack_productivity-1"
            local SEEDED = "mir473-seeded-planetary-owner"
            local CIRCULAR = "mir473-circular-planetary-owner"
            local packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack",
              "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack",
              "cryogenic-science-pack", "promethium-science-pack", "planetary-data"}
            local ingredients, prerequisites = {}, {}
            for index, name in ipairs(packs) do ingredients[index] = {name=name, amount=1} end
            for index = 1, 12 do prerequisites[index] = packs[index] end
            prerequisites[13] = SEEDED
            local effects = {
              {type="change-recipe-productivity", recipe="a-mir473-circular-planetary-data", change=.1},
              {type="change-recipe-productivity", recipe="z-mir473-seeded-planetary-data", change=.1},
            }
            local row = {type="technology", name=TARGET, level=1, upgrade=true, max_level="infinite",
              prerequisites=prerequisites, effects=effects,
              unit={count_formula="1*2^(L-1)", time=1, ingredients=ingredients}}
            local untouched = {name="unrelated-technology", prerequisites={"unrelated-gate"}}
            if opponent == "missing-gate" then table.remove(row.prerequisites, 13)
            elseif opponent == "circular-gate" then row.prerequisites[13] = CIRCULAR
            elseif opponent == "wrong-growth" then row.unit.count_formula = "1*3^(L-1)"
            elseif opponent == "zero-input" then row.unit.ingredients[13].amount = 0
            elseif opponent == "fluid-input" then row.unit.ingredients[13].type = "fluid"
            elseif opponent == "wrong-effect" then row.effects[1].change = .02
            end
            data = {raw={technology={[TARGET]=row, [untouched.name]=untouched}}}
            local ok, message = pcall(dofile, path)
            return {ok=ok, message=tostring(message), prerequisites=row.prerequisites,
              formula=row.unit.count_formula, time=row.unit.time, effects=row.effects,
              untouched_prerequisites=untouched.prerequisites}
          end

          function run_transition_control(path, opponent)
            local TARGET = "recipe-prod-research_science_pack_productivity-1"
            local A = "a-mir473-circular-planetary-data"
            local Z = "z-mir473-seeded-planetary-data"
            local callbacks, calls, saves, markers = {events={}}, {created=0, inserted=0, added=0}, {}, {}
            local inputs = {"automation-science-pack", "logistic-science-pack", "military-science-pack",
              "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack",
              "metallurgic-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
              "cryogenic-science-pack", "promethium-science-pack", "planetary-data"}
            local allowed = {}
            for _, name in ipairs(inputs) do allowed[name] = true end
            local function readonly(values, label)
              return setmetatable({}, {__index=values, __newindex=function() error("fixture wrote " .. label) end})
            end
            local effects = {
              {type="change-recipe-productivity", recipe=A, change=opponent == "missing-effect" and .02 or .1},
              {type="change-recipe-productivity", recipe=Z, change=.1},
            }
            local target_values = {name=TARGET, valid=true, level=1, researched=false, enabled=true,
              research_unit_count=1, research_unit_energy=60, saved_progress=0, prerequisites={},
              prototype={max_level=4294967295, effects=effects}, research_unit_ingredients={}}
            for index, name in ipairs(inputs) do target_values.research_unit_ingredients[index] = {name=name, amount=1} end
            local target = readonly(target_values, "target technology")
            local circular_values = {valid=true, productivity_bonus=0}
            local seeded_values = {valid=true, productivity_bonus=0}
            local recipes = {[A]=readonly(circular_values, "circular recipe"), [Z]=readonly(seeded_values, "seeded recipe")}
            local force = {technologies={[TARGET]=target}, recipes=recipes, research_queue={}, research_progress=0}
            target_values.force = force
            function force.add_research(value)
              assert(value == target, "fixture did not queue the native target")
              calls.added = calls.added + 1
              force.current_research, force.research_queue, force.research_progress = value, {value}, 0
              return true
            end
            local empty = true
            local inventory = {
              clear=function() empty = true end,
              insert=function(request)
                if not allowed[request.name] or request.count ~= 8 then return 0 end
                calls.inserted = calls.inserted + 1
                empty = false
                return request.count
              end,
              is_empty=function() return empty end,
            }
            local lab_values = {name="biolab", valid=true, energy=0,
              get_inventory=function() return inventory end}
            local lab = setmetatable({}, {__index=lab_values, __newindex=function(_, key, value)
              if key == "energy" then lab_values.energy = value
              elseif key == "active" then error("fixture wrote readonly lab.active")
              else error("fixture wrote readonly lab field: " .. tostring(key)) end
            end})
            game = {tick=100, forces={player=force}, surfaces={{create_entity=function(spec)
              assert(spec.name == "biolab" and spec.force == force)
              calls.created = calls.created + 1
              return lab
            end}}, server_save=function(name) saves[#saves + 1] = name end}
            storage = {}
            helpers = {table_to_json=function(value) markers[#markers + 1] = value; return "fixture-marker" end}
            log = function(message) assert(message == "[MIR5_NATIVE_FIXTURE] RESULT fixture-marker") end
            defines = {events={on_tick=1, on_research_finished=2}, inventory={lab_input=1}}
            script = {
              active_mods={base="2.1.23", ["elevated-rails"]="2.1.23", quality="2.1.23", recycler="2.1.23",
                ["space-age"]="2.1.23", ["more-infinite-research"]="4.7.21003",
                ["mir-fixture-mir5-fresh-science-sources"]="0.1.0",
                ["mir-fixture-mir5-fresh-science-transition"]="0.1.0"},
              on_init=function(callback) callbacks.init=callback end,
              on_configuration_changed=function(callback) callbacks.configuration=callback end,
              on_load=function(callback) callbacks.load=callback end,
              on_event=function(event, callback) callbacks.events[event]=callback end,
            }
            local chunk, message = loadfile(path)
            assert(chunk, message)
            local loaded, load_message = pcall(chunk)
            if not loaded then return {loaded=false, message=tostring(load_message)} end
            local source_ok, source_message = pcall(callbacks.init)
            if not source_ok then return {loaded=true, source_ok=false, message=tostring(source_message), calls=calls} end
            target_values.level, target_values.research_unit_count = 2, 2
            circular_values.productivity_bonus, seeded_values.productivity_bonus = .1, .1
            force.current_research, force.research_queue, force.research_progress = nil, {}, 0
            callbacks.events[2]({research=target})
            local source_tick_ok, source_tick_message = pcall(callbacks.events[1])
            if not source_tick_ok then return {loaded=true, source_ok=true, source_tick_ok=false,
              message=tostring(source_tick_message), calls=calls} end
            local before_configuration = {created=calls.created, inserted=calls.inserted, added=calls.added}
            script.active_mods["more-infinite-research"] = "5.0.21000"
            if opponent == "missing-bonus" then circular_values.productivity_bonus = 0 end
            local configuration_ok, configuration_message = pcall(callbacks.configuration)
            if not configuration_ok then
              local source = storage.mir5_fresh_science_transition
              return {loaded=true, source_ok=true, source_tick_ok=true, configuration_ok=false,
                message=tostring(configuration_message), calls=calls, before_configuration=before_configuration,
                phase=source.phase, source_mir=source.source_mir, source_labs=source.source_labs,
                successor_labs=source.successor_labs}
            end
            target_values.level, target_values.research_unit_count = 3, 4
            circular_values.productivity_bonus, seeded_values.productivity_bonus = .2, .2
            force.current_research, force.research_queue, force.research_progress = nil, {}, 0
            callbacks.events[2]({research=target})
            local successor_ok, successor_message = pcall(callbacks.events[1])
            if not successor_ok then return {loaded=true, source_ok=true, source_tick_ok=true, configuration_ok=true,
              successor_ok=false, message=tostring(successor_message), calls=calls} end
            callbacks.load()
            local reload_ok, reload_message = pcall(callbacks.events[1])
            return {loaded=true, source_ok=true, source_tick_ok=true, configuration_ok=true, successor_ok=successor_ok,
              reload_ok=reload_ok, message=tostring(reload_message), calls=calls, saves=saves, markers=markers,
              phase=storage.mir5_fresh_science_transition.phase, lab_energy=lab.energy,
              source_labs=storage.mir5_fresh_science_transition.source_labs,
              successor_labs=storage.mir5_fresh_science_transition.successor_labs}
          end
        ''')

    def test_settings_preflight_then_accelerates_only_the_existing_target(self):
        path = (FIXTURE / "settings-updates.lua").as_posix()
        for version in ("4.7.21003", "5.0.21000"):
            with self.subTest(version=version):
                result = self.lua.eval("run_transition_settings")(path, version, 8000, 120)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((1, 1, 77), (result["base"], result["time"], result["untouched"]))
        for base, time in ((7999, 120), (8000, 119)):
            with self.subTest(base=base, time=time):
                result = self.lua.eval("run_transition_settings")(path, "4.7.21003", base, time)
                self.assertFalse(result["ok"])
                # Both original values remain: the adapter has no partial write.
                self.assertEqual((base, time, 77), (result["base"], result["time"], result["untouched"]))

    def test_profiles_are_exact_paired_f210_transition_inputs(self):
        expected = {
            "published": ("4.7.21003", "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"),
            "mir5": ("5.0.21000", "3D6AE35B16A5CE7492EF617B62CF3D6DBE6AAB2C1540096AF05BB3CCFEFC942B"),
        }
        profiles = []
        for arm, (version, digest) in expected.items():
            profile = json.loads((PROFILES / f"fresh-science-transition-{arm}-f210-2123.json").read_text(encoding="utf-8"))
            self.assertEqual((profile["schema"], profile["kind"], profile["target"], profile["factorio_line"],
                              profile["settings_mode"]),
                             (1, "mir5-fresh-science-transition-f210-native-selection", "f210", "2.1", "Defaults"))
            self.assertEqual(profile["engine"], {"version": "2.1.23",
                                                  "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"})
            self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]],
                             [(name, "2.1.23", True) for name in
                              ("base", "elevated-rails", "quality", "recycler", "space-age")] + [
                              ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
                              ("more-infinite-research", version, True),
                              ("mir-fixture-mir5-fresh-science-sources", "0.1.0", True),
                              ("mir-fixture-mir5-fresh-science-transition", "0.1.0", True),
                             ])
            self.assertEqual(profile["archive_sha256"], {
                "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                    "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
                f"more-infinite-research_{version}.zip": digest,
            })
            profiles.append(profile)
        for profile in profiles:
            profile["mods"] = [row for row in profile["mods"] if row["name"] != "more-infinite-research"]
            profile["archive_sha256"] = {key: value for key, value in profile["archive_sha256"].items()
                                          if not key.startswith("more-infinite-research_")}
            profile.pop("scope")
        self.assertEqual(*profiles)

    def test_data_final_preflights_all_real_gates_then_clears_only_the_fixture_witness(self):
        path = (FIXTURE / "data-final-fixes.lua").as_posix()
        expected = (
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
            "mir473-seeded-planetary-owner",
        )
        good = self.lua.eval("run_transition_final")(path, "")
        self.assertTrue(good["ok"], good["message"])
        self.assertEqual(0, len(good["prerequisites"]))
        self.assertEqual(("unrelated-gate",), tuple(good["untouched_prerequisites"][index] for index in (1,)))
        self.assertEqual(("1*2^(L-1)", 1), (good["formula"], good["time"]))
        self.assertEqual((.1, .1), tuple(good["effects"][index]["change"] for index in (1, 2)))
        for opponent in ("missing-gate", "circular-gate", "wrong-growth", "zero-input", "fluid-input", "wrong-effect"):
            with self.subTest(opponent=opponent):
                result = self.lua.eval("run_transition_final")(path, opponent)
                self.assertFalse(result["ok"])
                # The sole mutation is after every preflight; failed shapes
                # retain their supplied, nonempty gate witness.
                self.assertEqual(12 if opponent == "missing-gate" else 13, len(result["prerequisites"]))
                if opponent not in ("missing-gate", "circular-gate"):
                    self.assertEqual(expected, tuple(result["prerequisites"][index] for index in range(1, 14)))

    def test_control_uses_actual_source_and_successor_lab_events_then_read_only_reload(self):
        result = self.lua.eval("run_transition_control")((FIXTURE / "control.lua").as_posix(), "")
        self.assertTrue(result["loaded"], result["message"])
        self.assertTrue(result["source_ok"], result["message"])
        self.assertTrue(result["source_tick_ok"], result["message"])
        self.assertTrue(result["configuration_ok"], result["message"])
        self.assertTrue(result["successor_ok"], result["message"])
        self.assertTrue(result["reload_ok"], result["message"])
        self.assertEqual((1, 1, "successor-completed"),
                         (result["source_labs"], result["successor_labs"], result["phase"]))
        self.assertEqual((1, 26, 2), tuple(result["calls"][key] for key in ("created", "inserted", "added")))
        self.assertEqual(("mir5-native-complete", "mir5-native-complete"),
                         tuple(result["saves"][index] for index in (1, 2)))
        self.assertEqual(("initial", "initial", "reload"),
                         tuple(result["markers"][index]["stage"] for index in (1, 2, 3)))
        # The proxy refuses a LuaEntity.active write; F210 permits only the
        # actual energy/inventory fixture setup and teardown path.
        self.assertEqual(0, result["lab_energy"])
        self.assertEqual(0.2, result["markers"][2]["witnesses"]["circular_recipe_productivity"])
        self.assertTrue(result["markers"][3]["witnesses"]["on_load_read_only"])

    def test_control_refuses_missing_effect_before_source_lab_writes(self):
        result = self.lua.eval("run_transition_control")((FIXTURE / "control.lua").as_posix(), "missing-effect")
        self.assertTrue(result["loaded"])
        self.assertFalse(result["source_ok"])
        self.assertIn("science effect changed", result["message"])
        self.assertEqual((0, 0, 0), tuple(result["calls"][key] for key in ("created", "inserted", "added")))

    def test_control_refuses_lost_source_bonus_before_successor_lab_writes(self):
        result = self.lua.eval("run_transition_control")((FIXTURE / "control.lua").as_posix(), "missing-bonus")
        self.assertTrue(result["source_ok"], result["message"])
        self.assertTrue(result["source_tick_ok"], result["message"])
        self.assertFalse(result["configuration_ok"])
        self.assertIn("MIR5 preflight native recipe productivity differs", result["message"])
        self.assertEqual((result["before_configuration"]["created"], result["before_configuration"]["inserted"],
                          result["before_configuration"]["added"]),
                         tuple(result["calls"][key] for key in ("created", "inserted", "added")))
        self.assertEqual("source-completed", result["phase"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(FreshScienceTransitionFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

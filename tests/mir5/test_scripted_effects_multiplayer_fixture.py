"""Host controls for the private F200 Space Age scripted-effects MP fixture."""

from __future__ import annotations

import argparse
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "mir5" / "fixtures" / "scripted-effects-multiplayer"
CONTROL = FIXTURE / "control.lua"
DATA_FINAL = FIXTURE / "data-final-fixes.lua"
PROFILE = ROOT / "tests" / "mir5" / "profiles" / "scripted-effects-multiplayer-f200-sa-2077.json"


class ScriptedEffectsMultiplayerFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)

    def test_profile_and_fixture_pin_the_exact_f200_space_age_closure(self):
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))

        self.assertEqual((profile["target"], profile["factorio_line"], profile["engine"]["version"]),
                         ("f200", "2.0", "2.0.77"))
        self.assertEqual(profile["engine"]["sha256"],
                         "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B")
        self.assertEqual(
            [(entry["name"], entry["version"]) for entry in profile["mods"]],
            [
                ("base", "2.0.77"), ("elevated-rails", "2.0.77"), ("quality", "2.0.77"),
                ("space-age", "2.0.77"), ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                ("more-infinite-research", "5.0.20000"),
                ("mir-fixture-mir5-scripted-effects-multiplayer", "0.1.0"),
            ],
        )
        self.assertEqual(
            (info["name"], info["version"], info["factorio_version"]),
            ("mir-fixture-mir5-scripted-effects-multiplayer", "0.1.0", "2.0"),
        )
        self.assertEqual(
            info["dependencies"],
            ["base >= 2.0.77", "space-age >= 2.0.77", "more-infinite-research = 5.0.20000"],
        )

    def test_data_stage_preflights_rows_before_fixture_only_spoil_shortening(self):
        lua = self.lua
        lua.execute(
            """
            local science = {
              {"automation-science-pack", 1}, {"logistic-science-pack", 1},
              {"chemical-science-pack", 1}, {"production-science-pack", 1},
              {"agricultural-science-pack", 1}, {"electromagnetic-science-pack", 1},
              {"cryogenic-science-pack", 1}
            }
            local spoilage_science = {
              {"automation-science-pack", 1}, {"logistic-science-pack", 1},
              {"chemical-science-pack", 1}, {"production-science-pack", 1},
              {"space-science-pack", 1}, {"agricultural-science-pack", 1}, {"cryogenic-science-pack", 1}
            }
            local function row(ingredients)
              local prerequisites = {}
              for i, ingredient in ipairs(ingredients) do prerequisites[i] = ingredient[1] end
              return {enabled=true, level=1, max_level="infinite", upgrade=true,
                unit={count_formula="1", time=1, ingredients=ingredients}, prerequisites=prerequisites,
                effects={{type="nothing", effect_description={"modifier-description.mir", "1"}}}}
            end
            data = {raw={technology={
              ["recipe-prod-research_agricultural_growth_speed-1"] = row(science),
              ["recipe-prod-research_spoilage_preservation-1"] = row(spoilage_science)
            }, capsule={yumako={spoil_ticks=216000, spoil_result="spoilage"}}}}
            """
        )
        chunk = lua.eval(f"assert(loadfile({str(DATA_FINAL)!r}))")
        self.assertIsNone(chunk())
        self.assertEqual(lua.eval('data.raw.capsule.yumako.spoil_ticks'), 600)

        lua.execute('data.raw.capsule.yumako.spoil_ticks = 215999')
        with self.assertRaises(Exception):
            chunk()

    def test_load_callback_is_read_only_and_completion_requires_host_reload(self):
        path = json.dumps(str(CONTROL))
        result = self.lua.execute(
            f"""
            local callbacks = {{}}
            local writes = 0
            local state = {{phase="awaiting-host-restart", join_events=4, after_external_rebase=3,
              restart_wall_unit=42, restart_wall_pre_restart_health=50}}
            local storage = setmetatable({{}}, {{
              __index=function(_, key) assert(key=="mir5_scripted_effects_multiplayer"); return state end,
              __newindex=function() writes=writes+1; error("on_load wrote durable state") end
            }})
            local guarded_game = setmetatable({{}}, {{__index=function() error("on_load accessed game") end}})
            local environment = {{
              script={{active_mods={{}}, on_init=function() end, on_load=function(callback) callbacks.load=callback end,
                on_event=function() end}},
              storage=storage, game=guarded_game, defines={{events={{}}}}, settings={{}}, helpers={{}}, log=function() end
            }}
            environment._G = environment
            setmetatable(environment, {{__index=function(_, name) return _G[name] end}})
            local chunk, message = loadfile({path}, "t", environment)
            assert(chunk, message); chunk(); callbacks.load()
            return {{writes=writes, phase=state.phase, joins=state.join_events}}
            """
        )
        self.assertEqual((result["writes"], result["phase"], result["joins"]), (0, "awaiting-host-restart", 4))

        source = CONTROL.read_text(encoding="utf-8")
        self.assertIn('fail("completed without a read-only host restart witness")', source)
        self.assertIn('game.server_save(RESTART_SAVE)', source)
        self.assertIn('game.server_save(FINAL_SAVE)', source)

    def test_first_postload_tick_exits_the_saved_pre_restart_phase_before_damage_dispatch(self):
        path = json.dumps(str(CONTROL))
        result = self.lua.execute(
            f"""
            local callbacks = {{events={{}}}}
            local state = {{phase="awaiting-host-restart", join_events=4, after_external_rebase=3,
              restart_wall_unit=42, restart_wall_pre_restart_health=50,
              restart_wall={{valid=true, unit_number=42, health=50}}}}
            local guarded_game = setmetatable({{}}, {{__index=function() error("pre-restart dispatch accessed game") end}})
            local environment = {{
              script={{active_mods={{}}, on_init=function() end, on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end}},
              storage={{mir5_scripted_effects_multiplayer=state}}, game=guarded_game,
              defines={{events={{on_player_joined_game=1, on_player_locale_changed=2, on_research_finished=3,
                on_tower_planted_seed=4, on_tick=5}}}}, settings={{}}, helpers={{}}, log=function() end
            }}
            environment._G=environment
            setmetatable(environment, {{__index=function(_, name) return _G[name] end}})
            local chunk, message=loadfile({path}, "t", environment); assert(chunk, message); chunk()
            callbacks.load()
            local ok, message=pcall(callbacks.events[5])
            return {{ok=ok, message=tostring(message), phase=state.phase,
              restarted=state.host_restart_observed, readonly=state.on_load_read_only}}
            """
        )
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(result["phase"], "awaiting-final-clients")
        self.assertTrue(result["restarted"])
        self.assertTrue(result["readonly"])

    def test_init_and_join_callbacks_reject_a_bad_closure_disconnected_client_and_wrong_locale(self):
        path = json.dumps(str(CONTROL))
        result = self.lua.execute(
            f"""
            local function run(opponent)
              local callbacks, storage = {{events={{}}}}, {{}}
              local active = {{base="2.0.77", ["elevated-rails"]="2.0.77", quality="2.0.77", ["space-age"]="2.0.77",
                ["more-infinite-research"]="5.0.20000",
                ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
                ["mir-fixture-mir5-scripted-effects-multiplayer"]="0.1.0"}}
              if opponent == "bad-closure" then active["unexpected-mod"] = "1.0.0" end
              local player = {{name="MIR5English", connected=opponent ~= "disconnected", locale=opponent == "wrong-locale" and "de" or "en"}}
              local settings = {{startup={{["mir-enable-passive-repair"]={{value=true}}}}}}
              for _, family in ipairs({{"research_agricultural_growth_speed", "research_spoilage_preservation"}}) do
                settings.startup["ips-cost-base-" .. family] = {{value=1}}
                settings.startup["ips-cost-linear-increment-" .. family] = {{value=0}}
                settings.startup["ips-cost-growth-" .. family] = {{value=1}}
                settings.startup["ips-max-level-" .. family] = {{value=0}}
                settings.startup["ips-research-time-" .. family] = {{value=1}}
                settings.startup["ips-effect-per-level-" .. family] = {{value=1}}
              end
              local environment = {{
                script={{active_mods=active, on_init=function(callback) callbacks.init=callback end,
                  on_load=function(callback) callbacks.load=callback end,
                  on_event=function(event, callback) callbacks.events[event]=callback end}},
                defines={{events={{on_player_joined_game=1, on_player_locale_changed=2, on_research_finished=3,
                  on_tower_planted_seed=4, on_tick=5}}}},
                settings=settings, storage=storage,
                game={{get_player=function(index) assert(index==1); return player end}},
                helpers={{table_to_json=function() return "{{}}" end}}, log=function() end
              }}
              environment._G=environment
              setmetatable(environment, {{__index=function(_, name) return _G[name] end}})
              local chunk, message = loadfile({path}, "t", environment); assert(chunk, message); chunk()
              local ok, message = pcall(callbacks.init)
              if not ok then return {{ok=false, message=tostring(message)}} end
              if opponent == "normal" then return {{ok=true, phase=storage.mir5_scripted_effects_multiplayer.phase}} end
              local callback = callbacks.events[opponent == "wrong-locale" and 2 or 1]
              ok, message = pcall(callback, {{player_index=1}})
              return {{ok=ok, message=tostring(message)}}
            end
            return run
            """
        )
        normal = result("normal")
        self.assertTrue(normal["ok"])
        self.assertEqual(normal["phase"], "waiting-initial-clients")
        for opponent, expected in {
            "bad-closure": "unexpected multiplayer closure member",
            "disconnected": "expected actually connected client",
            "wrong-locale": "wrong client locale",
        }.items():
            with self.subTest(opponent=opponent):
                observed = result(opponent)
                self.assertFalse(observed["ok"])
                self.assertIn(expected, observed["message"])

    def test_fixture_requires_actual_clients_and_native_runtime_witnesses(self):
        source = CONTROL.read_text(encoding="utf-8")
        required = [
            "on_player_joined_game", "on_player_locale_changed", "on_research_finished",
            "on_tower_planted_seed", "game.create_force", "game.merge_forces",
            "reset_technology_effects", "wall.damage", "spoil_tick", "restart_wall_pending",
            "runtime_owned_state_checked", "physical_rates_checked", "foreign_offsets_preserved",
            "host_restart_observed", "on_load_read_only",
        ]
        for token in required:
            with self.subTest(token=token):
                self.assertIn(token, source)
        for forbidden in ("game.create_player", "require(", "storage.mir", "take_screenshot", "research_queue_enabled"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)

        self.assertIn('if not player or player.connected ~= true then return false end', source)
        self.assertIn('if player.locale ~= locale then fail("client locale differs for " .. name) end', source)
        self.assertIn('if state.join_events == 4 and two_connected_clients(state) then seed_restart_repair(state) end', source)
        self.assertIn('if state.join_events ~= 6 or not two_connected_clients(state)', source)
        self.assertIn('comparison.set_friend(player, true)', source)
        self.assertIn('player.set_friend(comparison, true)', source)
        self.assertNotIn('comparison.set_friend(true, player)', source)
        self.assertNotIn('player.set_friend(true, comparison)', source)

    def test_marker_contract_separates_prejoin_preparation_from_native_completion(self):
        source = CONTROL.read_text(encoding="utf-8")
        protocol = (FIXTURE / "README.md").read_text(encoding="utf-8")
        self.assertIn('marker("ready", state)', source)
        self.assertIn('marker("rejoin-ready", state)', source)
        self.assertIn('marker("restart-ready", state)', source)
        self.assertIn('marker("completed", state)', source)
        self.assertIn('rendering_qualified = false', source)
        self.assertIn('performance_or_stress_qualified = false', source)
        self.assertIn('state.physical_rates_checked = true', source)
        self.assertIn('state.runtime_owned_state_checked = true', source)
        self.assertIn('state.foreign_offsets_preserved = true', source)
        self.assertIn('if loaded then check_loaded_state(state) end', source)
        self.assertLess(source.index('if loaded then check_loaded_state(state) end'),
                        source.index('if state.phase == "awaiting-host-restart" then restart_wall_pending(state); return end'))
        self.assertIn('native force merge did not retain the player spoilage research state', source)
        self.assertIn('player_spoilage_level_after_merge', source)
        self.assertIn('LuaGameScript.merge_forces(source,\ndestination)', protocol)
        self.assertIn('caps-api-current-native.json', protocol)
        self.assertIn('source level 3 and\nretained destination level 1', protocol)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ScriptedEffectsMultiplayerFixtureTests)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)

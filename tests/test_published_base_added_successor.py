"""Focused controls for the published Base paid-source added-mod observer."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import unittest
from pathlib import Path

from published_base_added_successor_world import FIXTURE, FOREIGN, MAINS, install


ROOT = Path(__file__).resolve().parents[1]
CONTROL = FIXTURE / "control.lua"
INFO = FIXTURE / "info.json"
DATA = FIXTURE / "data.lua"
EXPECTED = FIXTURE / "expected-source.lua"


def expected_source() -> tuple[str, dict]:
    text = EXPECTED.read_text(encoding="utf-8")
    start, end = text.index("[==[") + 4, text.rindex("]==]")
    source = text[start:end].strip()
    return source, json.loads(source)


class PublishedBaseAddedSuccessorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.source_text, self.source = expected_source()
        install(self.lua, self.source, self.source_text)

    def call(self, expression: str):
        return self.lua.eval(expression)

    def config(self, version: str = "5.0.20018", extra: str | None = None) -> None:
        if extra:
            self.lua.globals().added_extra = extra
            expression = "added_init_config(%r,added_extra)" % version
        else:
            expression = "added_init_config(%r,nil)" % version
        ok, message = self.call(expression)
        self.assertTrue(ok, message)

    def save(self) -> None:
        self.config()
        ok, message = self.call("added_until_saved()")
        self.assertTrue(ok, message)

    def test_fixture_is_exact_added_mod_and_embeds_portable_retained_source(self) -> None:
        info = json.loads(INFO.read_text(encoding="utf-8"))
        self.assertEqual(info["dependencies"], ["more-infinite-research >= 5.0.20016"])
        self.assertNotIn("settings", info)
        self.assertEqual(self.source["kind"], "MIRPublished473BasePaidSourceV1")
        self.assertEqual(self.source["tick"], 1252)
        self.assertEqual(self.source["endpoint"]["lab"]["position"], {"x": 0.5, "y": 0.5})
        self.assertIn("BCDED2247121D9F0268D1F4F0DF16EB5C89E6BECD4DE66E04EBDB23ECFE2FD98", EXPECTED.read_text(encoding="utf-8"))
        self.assertEqual(hashlib.sha256(self.source_text.encode("utf-8")).hexdigest().upper(), "BCDED2247121D9F0268D1F4F0DF16EB5C89E6BECD4DE66E04EBDB23ECFE2FD98")
        data = DATA.read_text(encoding="utf-8")
        for _, _, recipe, alias in MAINS:
            self.assertIn(f'{{"{recipe}", "{alias}"}}', data)
            self.assertNotIn(f'data.raw.recipe["{recipe}"] =', data)
        self.assertNotIn("data.raw.technology", data)

    def test_current_added_config_observes_retained_source_before_one_real_ordinary_completion(self) -> None:
        self.save()
        self.assertEqual(self.call("storage.mir_published_base_added_successor.phase"), "saved")
        self.assertEqual(self.call("#saves"), 1)
        self.assertEqual(self.call("saves[1].name"), "mir473-base-added-successor")
        self.assertGreaterEqual(self.call("storage.mir_published_base_added_successor.saved_tick-storage.mir_published_base_added_successor.hold_start"), 2)
        self.assertEqual(self.call("markers[1].phase"), "added-pre-work")
        self.assertEqual(self.call("markers[2].phase"), "added-saved")
        self.assertEqual(self.call("markers[2].source_observation_sha256"), "BCDED2247121D9F0268D1F4F0DF16EB5C89E6BECD4DE66E04EBDB23ECFE2FD98")
        self.assertEqual(self.call("markers[2].source_save_sha256"), "4354251431E4A495DACF6DA44207A5ECAE2F1D5A29FFD2A990415ACC98CD2413")
        self.assertFalse(self.call("markers[1].callback.startup_changed"))
        self.assertEqual(self.call('markers[1].callback.startup["mir-max-level-worker-robots-storage"]'), 0)
        for _, _, _, alias in MAINS:
            self.assertEqual(self.call(f'markers[1].before.aliases.player["{alias}"]'), 0)
            self.assertEqual(self.call(f'markers[1].before.aliases.foreign["{alias}"]'), 0)
        self.assertEqual(self.call("markers[2].endpoint.ordinary.name"), "recipe-prod-research_steel-1")
        self.assertEqual(self.call("markers[2].endpoint.ordinary.completed"), 1)
        self.assertFalse(self.call("markers[2].endpoint.ordinary.by_script"))
        self.assertEqual(self.call("markers[2].endpoint.ordinary.event.level"), 3)
        self.assertEqual(self.call("markers[2].endpoint.ordinary.event.force_name"), "player")
        self.assertFalse(self.call("markers[2].endpoint.ordinary.event.by_script"))
        self.assertEqual(self.call('markers[2].endpoint.observed_forces.player.mains["recipe-prod-research_steel-1"].state.level'), 3)
        self.assertEqual(self.call('game.forces.player.recipes["steel-plate"].productivity_bonus'), 0.2)
        self.assertEqual(self.call('game.forces.player.recipes["mir-fixture-added-steel-plate"].productivity_bonus'), 0.1)
        for _, name, recipe, alias in MAINS[:-1]:
            self.assertEqual(self.call(f'game.forces.player.recipes["{recipe}"].productivity_bonus'), 0.1)
            self.assertEqual(self.call(f'game.forces.player.recipes["{alias}"].productivity_bonus'), 0)
            self.assertEqual(self.call(f'markers[2].endpoint.aliases.player["{alias}"]'), 0)
        self.assertEqual(self.call('markers[2].endpoint.aliases.player["mir-fixture-added-steel-plate"]'), 0.1)
        for _, _, _, alias in MAINS:
            self.assertEqual(self.call(f'markers[2].endpoint.aliases.foreign["{alias}"]'), 0)
        self.assertEqual(self.call(f'game.forces["{FOREIGN}"].research_progress'), 0.42)
        self.assertEqual(self.call(f'game.forces["{FOREIGN}"].recipes["steel-plate"].productivity_bonus'), 0)
        self.assertEqual(self.call("#markers[2].endpoint.force_registry"), 4)
        for pack in ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"):
            self.assertEqual(self.call(f'markers[2].endpoint.science.consumed["{pack}"]'), 16000)
            self.assertGreater(self.call(f'markers[2].endpoint.science.remaining["{pack}"]'), 0)
        topups = self.call("#markers[2].endpoint.topups")
        ok, message = self.call("added_tick(1,false)")
        self.assertTrue(ok, message)
        self.assertEqual(self.call("#storage.mir_published_base_added_successor.topups"), topups)

    def test_old_and_malformed_configuration_events_refuse_without_repairing_source(self) -> None:
        ok, message = self.call('added_init_config("5.0.20015",nil)')
        self.assertTrue(ok, message)
        self.assertEqual(self.call("storage.mir_published_base_added_successor.phase"), "initialized")
        self.assertEqual(self.call("game.forces.player.current_research.name"), "recipe-prod-research_steel-1")
        self.assertEqual(self.call("game.forces.player.research_progress"), 0)
        lua = LuaRuntime(unpack_returned_tuples=True)
        install(lua, self.source, self.source_text)
        lua.globals().added_extra = "unexpected-mod"
        ok, message = lua.eval('added_init_config("5.0.20018",added_extra)')
        self.assertFalse(ok)
        self.assertIn("exact old-to-current addition event differs", message)

    def test_scripted_carrier_binds_real_force_before_config_and_refuses_forged_closed_or_main_events(self) -> None:
        ok, message = self.call('added_call("init")')
        self.assertTrue(ok, message)
        ok, message = self.call('added_call(2,{research={name="mir-native-credit-research_steel-steel-plate-positive"},by_script=true})')
        self.assertFalse(ok)
        self.assertIn("unexpected scripted research event", message)
        ok, message = self.call('added_scripted_forged_force("mir-native-credit-research_steel-steel-plate-positive")')
        self.assertFalse(ok)
        self.assertIn("unexpected scripted research event", message)
        ok, message = self.call('added_scripted_forged_object("mir-native-credit-research_steel-steel-plate-positive")')
        self.assertFalse(ok)
        self.assertIn("unexpected scripted research event", message)
        ok, message = self.call('added_scripted("mir-native-credit-research_steel-steel-plate-positive")')
        self.assertTrue(ok, message)
        self.assertEqual(self.call("#storage.mir_published_base_added_successor.scripted_carriers"), 1)
        self.assertEqual(self.call("storage.mir_published_base_added_successor.scripted_carriers[1].force_name"), "player")
        self.assertEqual(self.call("storage.mir_published_base_added_successor.scripted_carriers[1].force_index"), 1)
        ok, message = self.call('added_config_only("5.0.20018",nil)')
        self.assertTrue(ok, message)
        ok, message = self.call('added_scripted_foreign("mir-native-credit-research_steel-steel-plate-positive")')
        self.assertTrue(ok, message)
        self.assertEqual(self.call("#storage.mir_published_base_added_successor.scripted_carriers"), 2)
        ok, message = self.call('added_scripted("recipe-prod-research_steel-1")')
        self.assertFalse(ok)
        self.assertIn("unexpected scripted research event", message)
        ok, message = self.call("added_call(2,{research=game.forces.player.technologies['recipe-prod-research_plastic-1'],by_script=false})")
        self.assertFalse(ok)
        self.assertIn("ordinary research event differs", message)
        while self.call("storage.mir_published_base_added_successor.phase") != "holding":
            ok, message = self.call("added_tick(1,false)")
            self.assertTrue(ok, message)
        ok, message = self.call('added_scripted("mir-native-credit-research_steel-steel-plate-positive")')
        self.assertFalse(ok)
        self.assertIn("scripted carrier phase differs", message)
        ok, message = self.call("added_until_saved()")
        self.assertTrue(ok, message)
        ok, message = self.call('added_scripted("mir-native-credit-research_steel-steel-plate-positive")')
        self.assertFalse(ok)
        self.assertIn("scripted carrier phase differs", message)

    def test_foreign_partial_drift_early_hold_and_cold_world_access_refuse(self) -> None:
        self.config()
        while self.call("storage.mir_published_base_added_successor.phase") != "holding":
            ok, message = self.call("added_tick(1,false)")
            self.assertTrue(ok, message)
        self.lua.execute("world_values.foreign.progress=.5")
        ok, message = self.call("added_tick(1,false)")
        self.assertFalse(ok)
        self.assertIn("foreign queue", message)
        lua = LuaRuntime(unpack_returned_tuples=True)
        install(lua, self.source, self.source_text)
        ok, message = lua.eval('added_init_config("5.0.20018",nil)')
        self.assertTrue(ok, message)
        ok, message = lua.eval("added_until_saved()")
        self.assertTrue(ok, message)
        ok, message = lua.eval("added_load_throwing()")
        self.assertTrue(ok, message)
        ok, message = lua.eval("added_tick(1,false)")
        self.assertTrue(ok, message)
        self.assertEqual(lua.eval("markers[3].phase"), "added-cold")
        self.assertEqual(lua.eval('markers[3].endpoint.aliases.player["mir-fixture-added-steel-plate"]'), 0.1)
        for _, _, _, alias in MAINS[:-1]:
            self.assertEqual(lua.eval(f'markers[3].endpoint.aliases.player["{alias}"]'), 0)
        for _, _, _, alias in MAINS:
            self.assertEqual(lua.eval(f'markers[3].endpoint.aliases.foreign["{alias}"]'), 0)

    def test_wrong_bonus_and_early_elapsed_hold_refuse_or_do_not_save(self) -> None:
        self.lua.execute("added_seed_bonus(.3)")
        ok, message = self.call('added_init_config("5.0.20018",nil)')
        self.assertFalse(ok)
        self.assertIn("frozen public source player.recipe_bonuses.steel-plate differs", message)
        lua = LuaRuntime(unpack_returned_tuples=True)
        install(lua, self.source, self.source_text)
        ok, message = lua.eval('added_init_config("5.0.20018",nil)')
        self.assertTrue(ok, message)
        while lua.eval("storage.mir_published_base_added_successor.phase") != "holding":
            ok, message = lua.eval("added_tick(1,false)")
            self.assertTrue(ok, message)
        ok, message = lua.eval("added_tick(1,false)")
        self.assertTrue(ok, message)
        self.assertEqual(lua.eval("#saves"), 0)
        ok, message = lua.eval("added_tick(1,false)")
        self.assertTrue(ok, message)
        self.assertEqual(lua.eval("#saves"), 1)

    def test_actual_throughput_energy_and_public_write_guards_are_independent(self) -> None:
        self.assertEqual(self.call("added_ticks_needed(115199)"), 500)
        self.assertGreater(self.call("added_ticks_needed(64)"), 60 * 300)
        self.config()
        ok, message = self.call("added_tick(1,false)")
        self.assertTrue(ok, message)
        self.call("added_starve_energy()")
        ok, message = self.call("added_tick(1,false)")
        self.assertFalse(ok)
        self.assertIn("energy exhausted", message)
        lua = LuaRuntime(unpack_returned_tuples=True)
        install(lua, self.source, self.source_text)
        writes = lua.eval("added_observer_writes_refuse()")
        for field in (
            "level", "researched", "saved", "enabled", "current", "queue", "progress", "bonus",
            "bracket_level", "bracket_researched", "bracket_saved", "bracket_enabled",
            "bracket_current", "bracket_queue", "bracket_progress", "bracket_bonus",
        ):
            with self.subTest(field=field):
                self.assertFalse(writes[field])

    def test_exact_zero_and_complete_saved_endpoint_refuse_tiny_or_coordinated_drift(self) -> None:
        self.lua.execute("added_seed_alias_bonus(1e-12)")
        ok, message = self.call('added_init_config("5.0.20018",nil)')
        self.assertFalse(ok)
        self.assertIn("new alias inherited old paid bonus", message)
        lua = LuaRuntime(unpack_returned_tuples=True)
        install(lua, self.source, self.source_text)
        ok, message = lua.eval('added_init_config("5.0.20018",nil)')
        self.assertTrue(ok, message)
        ok, message = lua.eval("added_until_saved()")
        self.assertTrue(ok, message)
        lua.execute("added_drift_settled()")
        ok, message = lua.eval("added_tick(1,false)")
        self.assertFalse(ok)
        self.assertIn("completed steel state", message)
        alias_lua = LuaRuntime(unpack_returned_tuples=True)
        install(alias_lua, self.source, self.source_text)
        ok, message = alias_lua.eval('added_init_config("5.0.20018",nil)')
        self.assertTrue(ok, message)
        ok, message = alias_lua.eval("added_until_saved()")
        self.assertTrue(ok, message)
        alias_lua.execute("added_drift_alias()")
        ok, message = alias_lua.eval("added_load_throwing()")
        self.assertTrue(ok, message)
        ok, message = alias_lua.eval("added_tick(1,false)")
        self.assertFalse(ok)
        self.assertIn("steel paid/new alias bonuses", message)
        cold_lua = LuaRuntime(unpack_returned_tuples=True)
        install(cold_lua, self.source, self.source_text)
        ok, message = cold_lua.eval('added_init_config("5.0.20018",nil)')
        self.assertTrue(ok, message)
        ok, message = cold_lua.eval("added_until_saved()")
        self.assertTrue(ok, message)
        cold_lua.execute("added_corrupt_saved_endpoint()")
        ok, message = cold_lua.eval("added_load_throwing()")
        self.assertTrue(ok, message)
        ok, message = cold_lua.eval("added_tick(1,false)")
        self.assertFalse(ok)
        self.assertIn("cold saved endpoint", message)

    def test_observer_never_gets_research_queue_or_progress_write_authority(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        for forbidden in ("research_queue =", "research_progress =", "research_all", "research_recursive", "remote.call"):
            self.assertNotIn(forbidden, text)
        self.assertIn("research.level == 3", text)
        self.assertIn("event.by_script == false", text)
        self.assertIn("game.server_save(SAVE)", text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(Path(args.lua_runtime_dir)))
    global LuaRuntime
    from lupa import LuaRuntime

    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

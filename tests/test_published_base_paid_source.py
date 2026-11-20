"""Focused Lua52 controls for the two-mod published Base paid-source scenario."""

from __future__ import annotations

import argparse
import json
import re
import sys
import unittest
from pathlib import Path

from published_base_paid_source_world import FIXTURE, FOREIGN, MAINS, ROWS, install, load_actor


ROOT = Path(__file__).resolve().parents[1]
CONTROL = FIXTURE / "control.lua"
FACTS = FIXTURE / "captured-facts.json"
DESCRIPTION = FIXTURE / "description.json"


def has_level_assignment(text: str) -> bool:
    """Reject a real public technology-level assignment, not comparisons."""
    return re.search(r"\.level\s*=(?!=)", text) is not None


class NativeRow:
    """A Python userdata row exposed to Lua through Lupa's normal index bridge."""

    def __init__(self, name: str) -> None:
        self.name = name


class PublishedBasePaidSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        install(self.lua)
        load_actor(self.lua)

    def lua_value(self, expression: str):
        return self.lua.eval(expression)

    def call(self, handler: str):
        return self.lua.eval(f'paid_source_call("{handler}")')

    def init(self) -> None:
        ok, message = self.call("init")
        self.assertTrue(ok, message)

    def tick(self, count: int = 1) -> None:
        ok, message = self.lua.eval(f"paid_source_tick({count}, false)")
        self.assertTrue(ok, message)

    def save_source(self) -> None:
        self.init()
        ok, message = self.lua.eval("paid_source_until_saved(600)")
        self.assertTrue(ok, message)

    def reach_holding(self) -> None:
        # Use the same finite tick allowance as source creation. A stalled or
        # changed fixture must fail rather than leave a host process spinning.
        for _ in range(600):
            phase = self.lua_value("storage.mir_published473_base_paid_source.phase")
            if phase == "holding":
                return
            self.tick()
        phase = self.lua_value("storage.mir_published473_base_paid_source.phase")
        self.assertEqual(phase, "holding", f"source did not reach holding after 600 ticks; phase={phase!r}")

    def test_captured_facts_are_small_exact_authoring_input(self) -> None:
        facts = json.loads(FACTS.read_text(encoding="utf-8"))
        description = json.loads(DESCRIPTION.read_text(encoding="utf-8"))
        self.assertEqual(facts["raw"]["sha256"], "43FF6868BCE10E7290A5E656F6E7A55A67F16B575C3BB54B8E0A05C057B37097")
        self.assertEqual(facts["tuple"], {"base": "2.0.77", "more-infinite-research": "4.7.20003"})
        self.assertEqual(facts["finite_prerequisite_order"], list(ROWS))
        self.assertEqual(facts["finite_direct_parents"], ROWS)
        self.assertEqual(len(facts["finite_prerequisite_order"]), 23)
        self.assertEqual(description["multiplayer-compatible"], True)
        self.assertNotIn("multiplayer_compatible", description)

    def test_source_constructs_real_paid_levels_and_persists_endpoint_after_two_elapsed_ticks(self) -> None:
        self.save_source()
        self.assertEqual(self.lua_value("storage.mir_published473_base_paid_source.phase"), "saved")
        self.assertGreaterEqual(
            self.lua_value("storage.mir_published473_base_paid_source.saved_tick-storage.mir_published473_base_paid_source.hold_start_tick"),
            2,
        )
        self.assertEqual(self.lua_value("storage.mir_published473_base_paid_source.original_laboratory_speed_modifier"), 0)
        self.assertEqual(self.lua_value("game.forces.player.laboratory_speed_modifier"), 0)
        self.assertEqual(self.lua_value("#storage.mir_published473_base_paid_source.events"), 5)
        self.assertEqual(self.lua_value("#saves"), 1)
        self.assertEqual(self.lua_value("saves[1].name"), "mir473-base-paid-source")
        self.assertEqual(self.lua_value("#markers"), 3)
        self.assertEqual(self.lua_value("markers[1].phase"), "source-preflight")
        self.assertEqual(self.lua_value("markers[2].phase"), "source-pre-hold")
        self.assertEqual(self.lua_value("markers[3].phase"), "source-saved")
        self.assertEqual(self.lua_value("files[1].path"), "published-base-paid-source/preflight.json")
        self.assertEqual(self.lua_value("files[2].path"), "published-base-paid-source/source.json")
        self.assertEqual(self.lua_value("#markers[3].endpoint.force_registry"), 4)
        self.assertEqual(self.lua_value("markers[3].endpoint.observed_force_count"), 2)
        self.assertEqual(self.lua_value("markers[3].endpoint.observed_forces.player.name"), "player")
        self.assertEqual(self.lua_value("markers[3].endpoint.observed_forces.foreign.name"), FOREIGN)
        self.assertEqual(
            [self.lua_value(f"markers[3].endpoint.force_registry[{index}].name") for index in range(1, 5)],
            ["player", "enemy", "neutral", FOREIGN],
        )
        self.assertEqual(self.lua_value("markers[3].endpoint.lab.force_name"), "player")
        self.assertEqual(self.lua_value("markers[3].endpoint.lab.force_index"), 1)
        self.assertEqual(self.lua_value("markers[3].endpoint.lab.surface_index"), 1)
        self.assertEqual(self.lua_value("markers[3].endpoint.lab.position.x"), 0.5)
        self.assertEqual(self.lua_value("markers[3].endpoint.lab.position.y"), 0.5)
        for name, recipe in MAINS:
            self.assertEqual(self.lua_value(f'game.forces.player.technologies["{name}"].level'), 2)
            self.assertEqual(self.lua_value(f'game.forces.player.recipes["{recipe}"].productivity_bonus'), 0.1)
            self.assertEqual(self.lua_value(f'markers[3].endpoint.player.mains["{name}"].unit.energy_ticks'), 3600)
            self.assertEqual(self.lua_value(f'markers[3].endpoint.player.mains["{name}"].unit.count'), 16000)
        self.assertEqual(self.lua_value('game.forces.player.technologies["recipe-prod-research_plastic-1"].saved_progress'), 0.27)
        self.assertEqual(self.lua_value('markers[3].endpoint.player.queue.names[1]'), "recipe-prod-research_steel-1")
        self.assertEqual(self.lua_value('markers[3].endpoint.player.queue.names[2]'), "recipe-prod-research_steel-1")
        self.assertEqual(self.lua_value('markers[3].endpoint.foreign.queue.progress'), 0.42)
        self.assertEqual(self.lua_value('markers[3].endpoint.foreign.queue.names[2]'), "recipe-prod-research_gears-1")
        self.assertTrue(self.lua_value("paid_source_marker_is_plain(1)"))
        self.assertTrue(self.lua_value("paid_source_marker_is_plain(3)"))
        for science in ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"):
            self.assertEqual(self.lua_value(f'markers[3].endpoint.science.consumed["{science}"]'), 40000)
            self.assertGreaterEqual(self.lua_value(f'markers[3].endpoint.science.remaining["{science}"]'), 0)
        for row in ROWS:
            self.assertTrue(self.lua_value(f'game.forces.player.technologies["{row}"].researched'))
            self.assertTrue(self.lua_value(f'game.forces["{FOREIGN}"].technologies["{row}"].researched'))

    def test_preflight_exports_actual_tier_two_native_ordinals_before_foreign_creation(self) -> None:
        self.init()
        self.assertEqual(self.lua_value("#markers"), 1)
        self.assertEqual(self.lua_value("#files"), 1)
        self.assertEqual(self.lua_value("markers[1].kind"), "MIRPublished473BasePaidSourcePreflightV1")
        self.assertEqual(self.lua_value("markers[1].schema"), 1)
        self.assertEqual(self.lua_value("markers[1].phase"), "source-preflight")
        self.assertEqual(self.lua_value("files[1].path"), "published-base-paid-source/preflight.json")
        self.assertEqual(self.lua_value("#markers[1].force_registry"), 3)
        self.assertEqual(
            [self.lua_value(f"markers[1].force_registry[{index}].name") for index in range(1, 4)],
            ["player", "enemy", "neutral"],
        )
        self.assertEqual(self.lua_value("markers[1].player.name"), "player")
        self.assertEqual(self.lua_value('markers[1].finite["automation-2"].technology_level'), 2)
        self.assertEqual(self.lua_value('markers[1].finite["automation-2"].prototype_level'), 2)
        self.assertEqual(self.lua_value('markers[1].finite["automation-2"].prototype_max_level'), 2)
        self.assertEqual(self.lua_value('markers[1].finite["automation"].technology_level'), 1)
        self.assertEqual(self.lua_value('markers[1].finite["automation"].prototype_level'), 0)
        self.assertEqual(self.lua_value('markers[1].finite["automation"].prototype_max_level'), 1)
        self.assertFalse(self.lua_value('markers[1].finite["automation-2"].researched'))
        self.assertEqual(self.lua_value('markers[1].finite["automation-2"].saved_progress'), 0)

    def test_native_userdata_prerequisite_rows_are_admitted_by_indexed_name(self) -> None:
        self.lua.globals().native_parent = NativeRow("steam-power")
        self.lua.execute(
            'game.forces.player.technologies["automation-science-pack"].prerequisites={native_parent, game.forces.player.technologies["electronics"]}'
        )
        self.init()

    def test_missing_required_prerequisite_refuses_before_any_administrative_grant(self) -> None:
        self.lua.execute('game.forces.player.technologies["railway"]=nil')
        ok, message = self.call("init")
        self.assertFalse(ok)
        self.assertIn("finite technology is absent", message)
        self.assertIsNone(self.lua_value("storage.mir_published473_base_paid_source"))
        self.assertFalse(self.lua_value('game.forces.player.technologies["automation-science-pack"].researched'))
        self.assertEqual(self.lua_value("#markers"), 0)
        self.assertEqual(self.lua_value("#files"), 0)

    def test_finite_native_ordinal_refuses_mismatch_multilevel_infinite_and_earned_shapes_before_export(self) -> None:
        cases = {
            "current-max-mismatch": 'game.forces.player.technologies["automation-2"].level=1',
            "multi-level": 'game.forces.player.technologies["automation-2"].prototype.level=1',
            "runtime-infinite": 'game.forces.player.technologies["automation-2"].prototype.max_level=4294967295',
            "earned": 'game.forces.player.technologies["automation-2"].researched=true',
        }
        for name, mutation in cases.items():
            with self.subTest(name=name):
                lua = LuaRuntime(unpack_returned_tuples=True)
                install(lua)
                load_actor(lua)
                lua.execute(mutation)
                ok, message = lua.eval('paid_source_call("init")')
                self.assertFalse(ok)
                self.assertIn("finite technology", message)
                self.assertEqual(lua.eval("#markers"), 0)
                self.assertEqual(lua.eval("#files"), 0)
                self.assertIsNone(lua.eval("storage.mir_published473_base_paid_source"))
                self.assertFalse(lua.eval('game.forces.player.technologies["automation-science-pack"].researched'))

    def test_stale_or_scripted_research_event_refuses(self) -> None:
        self.init()
        self.tick()
        ok, message = self.lua.eval("paid_source_emit_stale()")
        self.assertFalse(ok)
        self.assertIn("ordinary research event differs", message)
        self.assertEqual(self.lua_value("#saves"), 0)

    def test_endpoint_mutation_during_hold_refuses(self) -> None:
        self.init()
        self.reach_holding()
        self.lua.eval("paid_source_drift_foreign_queue()")
        ok, message = self.lua.eval("paid_source_tick(1, false)")
        self.assertFalse(ok)
        self.assertIn("foreign current or repeated gear queue differs", message)
        self.assertEqual(self.lua_value("#saves"), 0)

    def test_material_nonzero_progress_drift_refuses_despite_native_float_tolerance(self) -> None:
        self.init()
        self.reach_holding()
        self.lua.execute(f'game.forces["{FOREIGN}"].research_progress=.421')
        ok, message = self.lua.eval("paid_source_tick(1, false)")
        self.assertFalse(ok)
        self.assertIn("foreign current or repeated gear queue differs", message)

    def test_load_is_locals_only_and_cold_observation_is_read_only(self) -> None:
        self.save_source()
        before = self.lua_value("markers[3].endpoint.player.queue.names[1]")
        ok, message = self.lua.eval("paid_source_load_with_throwing_globals()")
        self.assertTrue(ok, message)
        self.tick()
        self.assertEqual(self.lua_value("#markers"), 4)
        self.assertEqual(self.lua_value("markers[4].phase"), "source-cold")
        self.assertEqual(self.lua_value("files[3].path"), "published-base-paid-source/cold.json")
        self.assertEqual(self.lua_value("markers[4].endpoint.player.queue.names[1]"), before)
        self.assertEqual(self.lua_value("storage.mir_published473_base_paid_source.phase"), "saved")

    def test_wrong_mir_is_inert_for_init_config_and_tick(self) -> None:
        self.lua.eval('paid_source_set_mir("4.7.20004")')
        for handler in ("init", "configuration"):
            ok, message = self.call(handler)
            self.assertTrue(ok, message)
        ok, message = self.lua.eval("paid_source_tick(1, false)")
        self.assertTrue(ok, message)
        self.assertIsNone(self.lua_value("storage.mir_published473_base_paid_source"))
        self.assertIsNone(self.lua_value("game.lab"))
        self.assertEqual(self.lua_value("#markers"), 0)
        self.assertEqual(self.lua_value("#files"), 0)
        self.assertEqual(self.lua_value("#saves"), 0)

    def test_control_never_uses_recursive_or_manufactured_research_paths(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        for forbidden in ("research_all", "research_recursive", "script.raise_event"):
            self.assertNotIn(forbidden, text)
        self.assertFalse(has_level_assignment(text))
        for assignment in ("technology.level = 2", "technology.level\t=2", "technology.level= 2"):
            with self.subTest(assignment=assignment):
                self.assertTrue(has_level_assignment(assignment))
        for non_assignment in ("technology.level == 2", "technology.level ~= 2", "technology.level >= 2"):
            with self.subTest(non_assignment=non_assignment):
                self.assertFalse(has_level_assignment(non_assignment))
        self.assertIn("research_queue = rows", text)
        self.assertIn("force.research_progress = progress", text)
        self.assertIn("game.server_save(SAVE_NAME)", text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    runtime_dir = Path(args.lua_runtime_dir)
    sys.path.insert(0, str(runtime_dir))
    global LuaRuntime
    from lupa.lua52 import LuaRuntime

    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
    return 0


if __name__ == "__main__":
    main()

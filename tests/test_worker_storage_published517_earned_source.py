"""Focused Lua52 controls for the published-5.0.20017 source-only fixture."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-storage-published517-earned-source"
sys.path.insert(0, str(ROOT))
from tests import worker_storage_published517_earned_source_world as world


LuaRuntime = None
LuaError = RuntimeError


class Published517EarnedSourceTests(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        world.install(self.lua)
        world.load(self.lua)

    def logs(self):
        return list(self.lua.globals().p517_logs().values())

    def source_to_partial(self):
        self.lua.globals().p517_begin()
        self.lua.globals().p517_tick(1)
        self.assertEqual("source-working", self.lua.globals().p517_phase())
        for _ in range(5):
            self.lua.globals().p517_complete(False)
            self.lua.globals().p517_tick(1)
        self.assertEqual("source-await-partial", self.lua.globals().p517_phase())
        self.lua.globals().p517_partial(0.42)
        self.lua.globals().p517_tick(1)
        self.assertEqual("source-partial", self.lua.globals().p517_phase())

    def data_stage(self, *, ingredients=None, settings_values=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        values = dict(world.SETTINGS if settings_values is None else settings_values)
        startup = lua.table()
        for name, value in values.items():
            startup[name] = lua.table_from({"valid": True, "value": value}, recursive=True)
        unit_rows = lua.table()
        for index, name in enumerate(world.SCIENCE if ingredients is None else ingredients, 1):
            unit_rows[index] = lua.table_from({1: name, 2: 1}, recursive=True)
        target = lua.table_from({
            "max_level": "infinite", "level": 4, "enabled": True, "hidden": False,
            "prerequisites": lua.table_from({1: "worker-robots-storage-2", 2: "utility-science-pack", 3: world.PREDECESSOR}),
            "unit": lua.table_from({"count_formula": "675*1.5^(L-4)", "time": 60, "ingredients": unit_rows}),
            "effects": lua.table_from({1: lua.table_from({"type": "worker-robot-storage", "modifier": 1})}),
        }, recursive=True)
        active = {**world.CLOSURE, "more-infinite-research": "5.0.20017",
                  "mir-fixture-mir5-worker-storage-published517-earned-source": "0.1.0"}
        logs: list[str] = []
        env = lua.table_from({
            "mods": lua.table_from(active, recursive=True),
            "settings": lua.table_from({"startup": startup}),
            "data": lua.table_from({"raw": lua.table_from({"technology": lua.table_from({world.TARGET: target})})}),
            "log": logs.append,
        })
        lua.globals().DATA_ENV = env
        lua.execute("setmetatable(DATA_ENV, {__index = _G})")
        execute = lua.eval("function(path, env) local fn, message = loadfile(path, 't', env); if not fn then return false, message end; return pcall(fn) end")
        return execute((FIXTURE / "data-final-fixes.lua").as_posix(), env), logs

    def test_literal_101_row_setup_has_only_the_three_authorized_additions(self):
        rows = world.rows()
        self.assertEqual(101, len(rows))
        self.assertEqual(["modules"], rows["efficiency-module"])
        self.assertEqual(["se-pulveriser", "industrial-furnace"], rows["se-processing-cryonite"])
        self.assertEqual(["se-space-supercomputer-1", "se-processing-cryonite", "efficiency-module"], rows["utility-science-pack"])
        source = (FIXTURE / "prerequisites.lua").read_text(encoding="utf-8")
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("data.raw", source)
        metadata = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertIn("more-infinite-research = 5.0.20017", metadata["dependencies"])

    def test_data_stage_proves_the_five_pack_published_default_contract(self):
        result, logs = self.data_stage()
        self.assertTrue(result)
        self.assertEqual(20, next(row for row in logs if row.startswith("[MIR_ACTIVE_MODS]")).count("@"))
        marker = next(row for row in logs if row.startswith("[MIR_PUBLISHED517_EARNED_SOURCE]"))
        self.assertIn("science=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,utility-science-pack", marker)
        self.assertIn("formula=675*1.5^(L-4)", marker)
        self.assertIn("prerequisites=worker-robots-storage-2,utility-science-pack,worker-robots-storage-3", marker)
        self.assertIn("mir-max-level-worker-robots-storage=number:10", next(row for row in logs if row.startswith("[MIR_WORKER_STORAGE_SETTINGS]")))

    def test_data_stage_rejects_a_changed_five_pack_contract_before_runtime(self):
        result, _ = self.data_stage(ingredients=world.SCIENCE[:-1])
        self.assertFalse(result[0])
        self.assertIn("published ordinary worker science count differs", result[1])

    def test_dedicated_force_natively_earns_four_through_eight_then_partial_nine(self):
        self.source_to_partial()
        rows = [line for line in self.logs() if line.startswith("[MIR_SE_CARGO_NATIVE]")]
        ordinary = [line for line in rows if "phase=source-ordinary" in line]
        self.assertEqual(5, len(ordinary))
        self.assertEqual([4, 5, 6, 7, 8], [int(line.split("completed_level=")[1].split("|")[0]) for line in ordinary])
        self.assertTrue(all("by_script=false" in line for line in ordinary))
        partial = next(line for line in rows if "phase=source-partial" in line)
        self.assertIn("research_force=mir5-worker-storage-published517-earned-source", partial)
        self.assertIn("target=mir-worker-storage-default-4", partial)
        self.assertIn("level=9", partial)
        self.assertIn("researched=false", partial)
        self.assertIn("enabled=true", partial)
        self.assertIn("visible=true", partial)
        self.assertIn("queue=mir-worker-storage-default-4,mir-worker-storage-default-4,mir-fixture-published517-earned-source-tail", partial)
        self.assertIn("force_count=5", partial)
        self.assertIn("vectors_complete=true", partial)
        self.assertEqual(["mir5-published517-earned-source"], list(self.lua.globals().p517_saves().values()))

    def test_source_cold_read_preserves_the_complete_partial_frame_without_writes(self):
        self.source_to_partial()
        state_before = self.lua.globals().p517_state()
        ordinary_before, saves_before = state_before["ordinary"], list(self.lua.globals().p517_saves().values())
        self.lua.globals().p517_cold()
        self.assertEqual("source-partial", self.lua.globals().p517_phase())
        self.assertEqual(ordinary_before, self.lua.globals().p517_state()["ordinary"])
        self.assertEqual(saves_before, list(self.lua.globals().p517_saves().values()))
        cold = next(line for line in reversed(self.logs()) if "phase=source-cold-read" in line)
        self.assertIn("cold_writes=0", cold)
        self.assertIn("vectors_complete=true", cold)
        self.assertIn("queue=mir-worker-storage-default-4,mir-worker-storage-default-4,mir-fixture-published517-earned-source-tail", cold)

    def test_scripted_worker_completion_is_rejected(self):
        self.lua.globals().p517_begin()
        self.lua.globals().p517_tick(1)
        with self.assertRaisesRegex(LuaError, "ordinary worker completion differs"):
            self.lua.globals().p517_complete(True)

    def test_force_vector_capture_refuses_an_unbounded_registry_before_setup_writes(self):
        self.lua.globals().p517_add_foreign(29)
        with self.assertRaisesRegex(LuaError, "force vector limit differs"):
            self.lua.globals().p517_begin()
        self.assertEqual("idle", self.lua.globals().p517_phase())
        self.assertEqual([], self.logs())

    def test_configuration_change_refuses_instead_of_entering_a_candidate_route(self):
        self.source_to_partial()
        with self.assertRaisesRegex(LuaError, "configuration changes are outside this published-source fixture"):
            self.lua.globals().p517_configuration()
        self.assertEqual("source-partial", self.lua.globals().p517_phase())
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertNotIn("CANDIDATE", control)
        self.assertNotIn("mir-worker-storage-head-4", control)

    def test_source_actor_never_grants_or_sets_an_ordinary_worker_level(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertNotRegex(control, r"TARGET\]\.researched\s*=")
        self.assertNotRegex(control, r"target\.level\s*=(?!=)")
        self.assertNotRegex(control, r"research_progress\s*=(?!=)")
        self.assertIn("event.by_script == false", control)
        self.assertIn('local KEY = "mir5_worker_storage_published517_earned_source"', control)

    def test_readme_retains_the_resolved_published_and_contradicted_archive_identities(self):
        text = (FIXTURE / "README.md").read_text(encoding="utf-8")
        self.assertIn("B0BFA7418CFF77F249262C98864A386FA022C73E59B29EC30D028AE279A6AB27", text)
        self.assertIn("1046681", text)
        self.assertIn("7A30705CB510E668544D7827BE44F7FA7232BEBE30DB10FED540522DE338E4E5", text)
        self.assertIn("contradicted", text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    arguments = parser.parse_args()
    sys.path.insert(0, str(arguments.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaError as _LuaError, LuaRuntime as _LuaRuntime
    LuaRuntime, LuaError = _LuaRuntime, _LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(Published517EarnedSourceTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

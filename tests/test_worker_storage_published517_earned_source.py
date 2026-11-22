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

    def data_stage(self, *, ingredients=None, prerequisites=None, settings_values=None):
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
            "prerequisites": lua.table_from({
                index: name for index, name in enumerate(
                    prerequisites or ("utility-science-pack", world.PREDECESSOR), 1
                )
            }),
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

    def test_tail_uses_the_available_automation_one_icon_asset(self):
        source = (FIXTURE / "data.lua").read_text(encoding="utf-8")
        self.assertIn('icon = "__base__/graphics/technology/automation-1.png"', source)
        self.assertNotIn('icon = "__base__/graphics/technology/automation.png"', source)

    def test_data_stage_proves_the_five_pack_published_default_contract(self):
        result, logs = self.data_stage()
        self.assertTrue(result)
        self.assertEqual(20, next(row for row in logs if row.startswith("[MIR_ACTIVE_MODS]")).count("@"))
        marker = next(row for row in logs if row.startswith("[MIR_PUBLISHED517_EARNED_SOURCE] stage=data target="))
        self.assertIn("science=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,utility-science-pack", marker)
        self.assertIn("formula=675*1.5^(L-4)", marker)
        self.assertIn("prerequisites=utility-science-pack,worker-robots-storage-3", marker)
        self.assertIn("mir-max-level-worker-robots-storage=number:10", next(row for row in logs if row.startswith("[MIR_WORKER_STORAGE_SETTINGS]")))

    def test_data_stage_rejects_a_changed_five_pack_contract_before_runtime(self):
        result, _ = self.data_stage(ingredients=world.SCIENCE[:-1])
        self.assertFalse(result[0])
        self.assertIn("published ordinary worker science count differs", result[1])

    def test_data_stage_logs_the_actual_prerequisite_map_before_refusing_an_extra_or_missing_contract(self):
        for label, prerequisites, count, observed in (
            ("extra", ("worker-robots-storage-2", "utility-science-pack", world.PREDECESSOR), 3,
             "utility-science-pack,worker-robots-storage-2,worker-robots-storage-3"),
            ("missing", (world.PREDECESSOR,), 1, "worker-robots-storage-3"),
        ):
            with self.subTest(label=label):
                result, logs = self.data_stage(prerequisites=prerequisites)
                self.assertFalse(result[0])
                self.assertIn("published ordinary worker prerequisite count differs", result[1])
                diagnostic = next(row for row in logs if "stage=data-prerequisites" in row)
                self.assertIn(f"observed_count={count}", diagnostic)
                self.assertIn(f"observed={observed}", diagnostic)
                self.assertIn("final_expected=utility-science-pack,worker-robots-storage-3", diagnostic)
                self.assertIn("catalogue_declaration=worker-robots-storage-2,utility-science-pack,worker-robots-storage-3", diagnostic)

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
        self.assertIn("visible=false", partial)
        self.assertIn("queue=mir-worker-storage-default-4,mir-worker-storage-default-4,mir-fixture-published517-earned-source-tail", partial)
        self.assertIn("force_count=5", partial)
        self.assertIn("vectors_complete=true", partial)
        self.assertEqual(["mir5-published517-earned-source"], list(self.lua.globals().p517_saves().values()))

    def test_partial_queue_diagnostics_preserve_the_documented_active_first_three_row_frame(self):
        self.source_to_partial()
        stages = {
            row.split("|", 1)[0].split("stage=", 1)[1]: row
            for row in self.logs()
            if row.startswith("[MIR_PUBLISHED517_EARNED_SOURCE] stage=source-partial-queue")
        }
        before = stages["source-partial-queue-before-assignment"]
        after = stages["source-partial-queue-after-assignment"]
        pre_refusal = stages["source-partial-queue-before-refusal"]
        self.assertIn("current_name=none|current_object=none|progress=number:0|queue_array_length=0|queue_pair_count=0|queue_pairs=", before)
        expected_rows = "queue_pairs=number:1:LuaTechnology:mir-worker-storage-default-4;number:2:LuaTechnology:mir-worker-storage-default-4;number:3:LuaTechnology:mir-fixture-published517-earned-source-tail"
        for diagnostic in (after, pre_refusal):
            self.assertIn("current_name=mir-worker-storage-default-4|current_object=LuaTechnology", diagnostic)
            self.assertIn("queue_array_length=3|queue_pair_count=3|" + expected_rows, diagnostic)
            self.assertIn("target_level=number:9|target_next_level=number:9|target_researched=boolean:false|target_enabled=boolean:true|target_visible=boolean:false", diagnostic)
            self.assertIn("tail_name=mir-fixture-published517-earned-source-tail|tail_level=number:1|tail_researched=boolean:false|tail_enabled=boolean:true|tail_visible=boolean:false|tail_prerequisite_count=1|tail_prerequisites=automation-science-pack", diagnostic)

    def test_host_tail_drop_is_diagnosed_then_retains_the_strict_three_row_refusal(self):
        self.lua.globals().p517_drop_tail_on_partial_assignment()
        self.lua.globals().p517_begin()
        self.lua.globals().p517_tick(1)
        for _ in range(5):
            self.lua.globals().p517_complete(False)
            self.lua.globals().p517_tick(1)
        self.assertEqual("source-await-partial", self.lua.globals().p517_phase())
        self.lua.globals().p517_partial(0.42)
        with self.assertRaisesRegex(LuaError, "source partial queue count differs"):
            self.lua.globals().p517_tick(1)
        logs = self.logs()
        after = next(row for row in logs if "stage=source-partial-queue-after-assignment" in row)
        pre_refusal = next(row for row in logs if "stage=source-partial-queue-before-refusal" in row)
        for diagnostic in (after, pre_refusal):
            self.assertIn("queue_array_length=2|queue_pair_count=2|queue_pairs=number:1:LuaTechnology:mir-worker-storage-default-4;number:2:LuaTechnology:mir-worker-storage-default-4", diagnostic)
            self.assertIn("tail_name=mir-fixture-published517-earned-source-tail", diagnostic)
            self.assertIn("tail_prerequisites=automation-science-pack", diagnostic)
        self.assertIn("[MIR_PUBLISHED517_EARNED_SOURCE] stage=refusal|message=source partial queue count differs", logs)
        self.assertEqual("source-await-partial", self.lua.globals().p517_phase())
        self.assertEqual([], list(self.lua.globals().p517_saves().values()))

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
        self.assertEqual(
            ["[MIR_PUBLISHED517_EARNED_SOURCE] stage=refusal|message=force vector limit differs"],
            self.logs(),
        )

    def test_runtime_logs_the_actual_prerequisite_map_before_any_finite_setup_grant_refusal(self):
        self.lua.execute("P517_EXTRA_TARGET_PREREQUISITE='worker-robots-storage-2'")
        with self.assertRaisesRegex(LuaError, "ordinary worker direct prerequisite count differs"):
            self.lua.globals().p517_begin()
        self.assertEqual("idle", self.lua.globals().p517_phase())
        diagnostic = next(row for row in self.logs() if "stage=runtime-pregrant" in row)
        self.assertIn("observed_count=3", diagnostic)
        self.assertIn("observed=utility-science-pack,worker-robots-storage-2,worker-robots-storage-3", diagnostic)
        self.assertIn("final_expected=utility-science-pack,worker-robots-storage-3", diagnostic)
        self.assertIn("catalogue_declaration=worker-robots-storage-2,utility-science-pack,worker-robots-storage-3", diagnostic)
        self.assertNotIn("phase=source-begin", "\n".join(self.logs()))

    def test_runtime_missing_parent_logs_before_any_finite_setup_grant_refusal(self):
        self.lua.execute("P517_OMIT_TARGET_PREREQUISITE='utility-science-pack'")
        with self.assertRaisesRegex(LuaError, "ordinary worker direct prerequisite count differs"):
            self.lua.globals().p517_begin()
        self.assertEqual("idle", self.lua.globals().p517_phase())
        diagnostic = next(row for row in self.logs() if "stage=runtime-pregrant" in row)
        self.assertIn("observed_count=1", diagnostic)
        self.assertIn("observed=worker-robots-storage-3", diagnostic)
        self.assertNotIn("phase=source-begin", "\n".join(self.logs()))

    def test_initial_role_marker_records_each_typed_observed_and_expected_predicate(self):
        self.lua.globals().p517_begin()
        pregrant = next(row for row in self.logs() if "stage=runtime-pregrant" in row)
        self.assertIn("before_force_count=4", pregrant)
        self.assertIn("after_force_count=5", pregrant)
        for index, name, bonus in ((1, "player", 0), (2, "enemy", 0), (3, "neutral", 0), (4, "se-system", 3),
                                   (5, "mir5-worker-storage-published517-earned-source", 0)):
            self.assertIn(f'{index}:"{name}":{bonus}:0:0:0:0:0', pregrant)
        diagnostic = next(row for row in self.logs() if "stage=runtime-initial-role" in row)
        self.assertIn("level_observed=number:4|level_expected=number:4|level_matches=true", diagnostic)
        self.assertIn("researched_observed=boolean:false|researched_expected=boolean:false|researched_matches=true", diagnostic)
        self.assertIn("enabled_observed=boolean:true|enabled_expected=boolean:true|enabled_matches=true", diagnostic)
        self.assertIn("visible_observed=boolean:false|visible_expected=boolean:false|visible_matches=true", diagnostic)

    def test_initial_role_refusal_reports_each_changed_predicate_before_finite_setup_writes(self):
        for field, value, observed, expected in (
            ("level", 5, "number:5", "number:4"),
            ("researched", True, "boolean:true", "boolean:false"),
            ("enabled", False, "boolean:false", "boolean:true"),
            ("visible_when_disabled", True, "boolean:true", "boolean:false"),
        ):
            with self.subTest(field=field):
                lua = LuaRuntime(unpack_returned_tuples=True)
                world.install(lua)
                world.load(lua)
                lua.globals().p517_override_initial_role(field, value)
                with self.assertRaisesRegex(LuaError, "ordinary worker initial role differs"):
                    lua.globals().p517_begin()
                logs = list(lua.globals().p517_logs().values())
                diagnostic = next(row for row in logs if "stage=runtime-initial-role" in row)
                marker = "visible" if field == "visible_when_disabled" else field
                self.assertIn(f"{marker}_observed={observed}|{marker}_expected={expected}|{marker}_matches=false", diagnostic)
                self.assertIn("[MIR_PUBLISHED517_EARNED_SOURCE] stage=refusal|message=ordinary worker initial role differs", logs)
                self.assertEqual("idle", lua.globals().p517_phase())
                self.assertFalse(lua.eval("p517_force().technologies['efficiency-module'].researched"))
                self.assertEqual([], list(lua.globals().p517_saves().values()))

    def test_initial_role_marker_distinguishes_unavailable_nil_from_false(self):
        self.lua.globals().p517_omit_initial_role("visible_when_disabled")
        with self.assertRaisesRegex(LuaError, "ordinary worker initial role differs"):
            self.lua.globals().p517_begin()
        diagnostic = next(row for row in self.logs() if "stage=runtime-initial-role" in row)
        self.assertIn("visible_observed=unavailable:nil|visible_expected=boolean:false|visible_matches=false", diagnostic)
        self.assertIn("[MIR_PUBLISHED517_EARNED_SOURCE] stage=refusal|message=ordinary worker initial role differs", self.logs())
        self.assertFalse(self.lua.eval("p517_force().technologies['efficiency-module'].researched"))

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

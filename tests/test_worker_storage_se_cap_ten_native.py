"""Strict Lua52 controls for the F200/SE worker-storage cargo fixture.

These are fixture-construction controls only.  They do not package an actor,
create a Factorio process, or establish a gameplay result.  Their host world
records save requests as assertions; it never creates an engine save.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-storage-se-cap-ten-native"
sys.path.insert(0, str(ROOT))
from tests import worker_storage_se_cap_ten_native_world as world


LuaRuntime = None
LuaError = RuntimeError


def _lua_array(values):
    return "{" + ",".join(json.dumps(value) for value in values) + "}"


class WorkerStorageSECapTenNativeTests(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.lua = self.fresh_actor()

    def fresh_actor(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        world.install(lua)
        world.load(lua)
        return lua

    def static_role_actor(self):
        """Load the former static-C4 expectation as an in-memory actor mutant."""
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        old = "state.worker = CANDIDATE; assert_worker_contract(state.player, CANDIDATE)"
        self.assertIn(old, source)
        source = source.replace(old, "state.worker = SOURCE; assert_worker_contract(state.player, SOURCE)", 1)
        lua = LuaRuntime(unpack_returned_tuples=True)
        world.install(lua)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "static-canonical-control.lua"
            path.write_text(source, encoding="utf-8", newline="\n")
            lua.globals().cargo_load(path.as_posix())
        return lua

    def unsupported_queue_flag_actor(self):
        """Load an in-memory actor mutant that reads a removed LuaForce member."""
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        old = "local player = game.forces.player\n  check(player and player.valid ~= false, \"player force differs\")"
        new = "local player = game.forces.player\n  local removed_queue_flag = player.research_queue_enabled\n  check(player and player.valid ~= false, \"player force differs\")"
        self.assertIn(old, source)
        source = source.replace(old, new, 1)
        lua = LuaRuntime(unpack_returned_tuples=True)
        world.install(lua)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "removed-queue-flag-control.lua"
            path.write_text(source, encoding="utf-8", newline="\n")
            lua.globals().cargo_load(path.as_posix())
        return lua

    def unconditional_cold_pending_actor(self):
        """Load the AFA actor behavior that treated every saved phase as cold."""
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        fixed = '''  if cold_pending then
    if cold_phase == "closed" then
      check(state.phase == "closed" and same(frame(state), state.closed), "cold process changed candidate endpoint")
      marker("cold-read", state, {cold_writes = 0}); cold_pending, cold_phase = false, nil; return
    elseif cold_phase == "idle" then
      check(state.phase == "idle" or state.phase == "source-working", "cold load phase differs")
    elseif cold_phase == "source-partial" then
      check(state.phase == "candidate-working", "cold load phase differs")
    else
      fail("cold load phase differs")
    end
    cold_pending, cold_phase = false, nil
  end'''
        original = '''  if cold_pending then
    check(state.phase == "closed" and same(frame(state), state.closed), "cold process changed candidate endpoint")
    marker("cold-read", state, {cold_writes = 0}); cold_pending = false; return
  end'''
        self.assertIn(fixed, source)
        source = source.replace(fixed, original, 1)
        lua = LuaRuntime(unpack_returned_tuples=True)
        world.install(lua)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unconditional-cold-pending-control.lua"
            path.write_text(source, encoding="utf-8", newline="\n")
            lua.globals().cargo_load(path.as_posix())
        return lua

    def source_to_partial(self):
        self.lua.globals().cargo_begin()
        for _ in range(5):
            self.lua.globals().cargo_complete(False)
            self.lua.globals().cargo_tick(1)
        self.assertEqual("source-await-partial", self.lua.globals().cargo_phase())
        self.lua.globals().cargo_partial(0.42)
        self.lua.globals().cargo_tick(1)
        self.assertEqual("source-partial", self.lua.globals().cargo_phase())

    def candidate_to_closed(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.assertEqual("candidate-working", self.lua.globals().cargo_phase())
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.assertEqual("closed", self.lua.globals().cargo_phase())

    def logs(self):
        return list(self.lua.globals().cargo_logs().values())

    def data_stage(self, values=None, ingredients=None):
        """Execute the data-only marker through strict, actual-value proxies."""
        lua = LuaRuntime(unpack_returned_tuples=True)
        rows = dict(world.SETTINGS if values is None else values)
        active = {**world.CLOSURE, "more-infinite-research": "5.0.20018",
                  "mir-fixture-mir5-worker-storage-se-cap-ten-native": "0.1.0"}
        startup = lua.table()
        for name, value in rows.items():
            startup[name] = lua.table_from({"value": value, "default_value": 0}, recursive=True)
        science = world.SCIENCE if ingredients is None else ingredients
        unit_rows = lua.table()
        for index, name in enumerate(science, 1):
            unit_rows[index] = lua.table_from({1: name, 2: 1}, recursive=True)
        target = lua.table_from({
            "prerequisites": lua.table_from({1: world.PREDECESSOR}),
            "unit": lua.table_from({"count_formula": "675*1.5^(L-4)", "time": 60, "ingredients": unit_rows}),
            "effects": lua.table_from({1: lua.table_from({"type": "worker-robot-storage", "modifier": 1})}),
        }, recursive=True)
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
        result = execute((FIXTURE / "data-final-fixes.lua").as_posix(), env)
        return result, logs

    def test_metadata_has_same_full_actor_identity_for_both_engine_families(self):
        canonical = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        f200 = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        self.assertEqual(canonical["name"], f200["name"])
        self.assertEqual(canonical["version"], f200["version"])
        self.assertEqual("2.1", canonical["factorio_version"])
        self.assertEqual("2.0", f200["factorio_version"])
        self.assertEqual(["base >= 2.0.77", "space-exploration >= 0.7.57", "more-infinite-research"], f200["dependencies"])

    def test_fixed_declaration_has_exact_roots_order_and_count(self):
        rows = world.rows()
        self.assertEqual(98, len(rows))
        self.assertEqual(["worker-robots-storage-2", "se-material-science-pack-1"], rows["worker-robots-storage-3"])
        self.assertEqual(["se-space-belt"], rows["se-space-science-lab"])
        self.assertEqual(["se-processing-iridium", "se-space-catalogue-material-1", "se-space-hypercooling-1"], rows["se-material-science-pack-1"])
        declaration = (FIXTURE / "prerequisites.lua").read_text(encoding="utf-8")
        self.assertNotIn("research_recursive", declaration)
        self.assertNotIn("data.raw", declaration)

    def test_source_stays_idle_until_explicit_remote_begin(self):
        self.assertEqual("idle", self.lua.globals().cargo_phase())
        self.assertEqual([], self.logs())
        self.lua.globals().cargo_begin()
        self.assertEqual("source-working", self.lua.globals().cargo_phase())
        self.assertIn("phase=source-begin", self.logs()[-1])

    def test_afa_cold_pending_mutant_refuses_both_source_load_orders(self):
        old = self.unconditional_cold_pending_actor()
        old.globals().cargo_on_load()
        with self.assertRaisesRegex(LuaError, "cold process changed candidate endpoint"):
            old.globals().cargo_tick(1)

        old_after_begin = self.unconditional_cold_pending_actor()
        old_after_begin.globals().cargo_on_load()
        old_after_begin.globals().cargo_begin()
        with self.assertRaisesRegex(LuaError, "cold process changed candidate endpoint"):
            old_after_begin.globals().cargo_tick(1)

    def test_documented_on_load_source_idle_admits_both_first_tick_orders(self):
        self.lua.globals().cargo_on_load()
        self.lua.globals().cargo_tick(1)
        self.assertEqual("idle", self.lua.globals().cargo_phase())
        self.assertEqual([], self.logs())
        self.lua.globals().cargo_begin()
        self.assertEqual("source-working", self.lua.globals().cargo_phase())

        after_begin = self.fresh_actor()
        after_begin.globals().cargo_on_load()
        after_begin.globals().cargo_begin()
        after_begin.globals().cargo_tick(1)
        self.assertEqual("source-working", after_begin.globals().cargo_phase())

    def test_documented_on_load_configuration_then_candidate_tick_remains_working(self):
        old = self.unconditional_cold_pending_actor()
        old.globals().cargo_begin()
        for _ in range(5):
            old.globals().cargo_complete(False)
            old.globals().cargo_tick(1)
        old.globals().cargo_partial(0.42)
        old.globals().cargo_tick(1)
        old.globals().cargo_on_load()
        old.globals().cargo_candidate("5.0.20018", None, True)
        with self.assertRaisesRegex(LuaError, "cold process changed candidate endpoint"):
            old.globals().cargo_tick(1)

        self.source_to_partial()
        self.lua.globals().cargo_on_load()
        self.lua.globals().cargo_candidate("5.0.20018", None, True)
        self.lua.globals().cargo_tick(1)
        self.assertEqual("candidate-working", self.lua.globals().cargo_phase())
        self.assertIn("phase=candidate-pre-work", self.logs()[-1])
        self.assertNotIn("phase=cold-read", self.logs()[-1])

    def test_on_load_refuses_unrecognized_persisted_phase(self):
        self.lua.globals().cargo_set_phase("unknown-persisted-phase")
        self.lua.globals().cargo_on_load()
        with self.assertRaisesRegex(LuaError, "cold load phase differs"):
            self.lua.globals().cargo_tick(1)

    def test_on_load_source_partial_requires_configuration_before_first_tick(self):
        self.source_to_partial()
        self.lua.globals().cargo_on_load()
        with self.assertRaisesRegex(LuaError, "cold load phase differs"):
            self.lua.globals().cargo_tick(1)

    def test_strict_world_rejects_removed_research_queue_enabled_force_read(self):
        lua = self.unsupported_queue_flag_actor()
        with self.assertRaisesRegex(LuaError, "LuaForce unsupported read research_queue_enabled"):
            lua.globals().cargo_begin()

    def test_source_records_five_native_ordinary_completions_then_real_partial(self):
        self.source_to_partial()
        log = self.logs()[-1]
        self.assertIn("phase=source-partial", log)
        self.assertIn("ordinary=5", log)
        self.assertIn("level=9", log)
        self.assertIn("progress=0.42", log)
        self.assertIn("queue=worker-robots-storage-4,worker-robots-storage-4,mir-fixture-worker-storage-se-cap-ten-tail", log)
        self.assertEqual(["mir5-se-worker-storage-cap10-source"], list(self.lua.globals().cargo_saves().values()))

    def test_synthetic_partial_exercises_the_f200_normal_tool_durability_reader(self):
        self.source_to_partial()
        log = self.logs()[-1]
        self.assertIn("science_remaining=automation-science-pack:194.58", log)
        self.assertIn("science_debit=automation-science-pack:5.42", log)

    def test_f200_tool_science_reader_rejects_invalid_durability_before_research(self):
        self.lua.globals().cargo_bad_science_durability()
        with self.assertRaisesRegex(LuaError, "native science durability differs"):
            self.lua.globals().cargo_begin()
        self.assertEqual("source-working", self.lua.globals().cargo_phase())

    def test_source_requires_the_native_plus_one_worker_bonus_for_each_completion(self):
        self.lua.globals().cargo_begin()
        with self.assertRaisesRegex(LuaError, "source ordinary earned worker bonus differs"):
            self.lua.globals().cargo_complete(False, None, -100)

    def test_source_requires_existing_foreign_force_bonus_to_stay_unchanged(self):
        self.lua.globals().cargo_begin()
        self.lua.globals().cargo_add_late_force()
        with self.assertRaisesRegex(LuaError, "source ordinary foreign worker bonus differs"):
            self.lua.globals().cargo_complete(False)

    def test_native_completions_consume_the_five_row_queue_before_staging_partial_and_tail(self):
        self.lua.globals().cargo_begin()
        self.assertEqual([world.SOURCE] * 5, list(self.lua.globals().cargo_queue_names().values()))
        for expected_remaining in range(4, -1, -1):
            self.lua.globals().cargo_complete(False)
            self.assertEqual(expected_remaining, len(self.lua.globals().cargo_queue_names()))
            if expected_remaining:
                self.assertEqual(world.SOURCE, self.lua.globals().cargo_current_name())
            else:
                self.assertFalse(self.lua.globals().cargo_current_name())
            self.lua.globals().cargo_tick(1)
        self.assertEqual([world.SOURCE, world.SOURCE, world.TAIL], list(self.lua.globals().cargo_queue_names().values()))
        self.assertEqual(world.SOURCE, self.lua.globals().cargo_current_name())

    def test_published_canonical_to_private_transfer_maps_current_and_all_worker_queue_rows(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None, True)
        self.assertEqual("candidate-working", self.lua.globals().cargo_phase())
        marker = self.logs()[-1]
        self.assertIn(f"worker={world.CANDIDATE}", marker)
        self.assertIn(f"current={world.CANDIDATE}", marker)
        self.assertIn(f"queue={world.CANDIDATE},{world.CANDIDATE},{world.TAIL}", marker)
        self.assertIn(f"source_role={world.SOURCE}:9:false:true:false", marker)
        self.assertIn(f"canonical_role={world.SOURCE}:5:false:false:false", marker)
        self.assertIn(f"private_role={world.CANDIDATE}:9:false:true:false", marker)
        self.assertIn(f"head_role={world.HEAD}:5:false:false:false", marker)
        self.assertIn("configuration_startup_settings_changed=true", marker)

    def test_static_canonical_role_mutant_rejects_the_published_private_mapping(self):
        lua = self.static_role_actor()
        lua.globals().cargo_begin()
        for _ in range(5):
            lua.globals().cargo_complete(False)
            lua.globals().cargo_tick(1)
        lua.globals().cargo_partial(0.42)
        lua.globals().cargo_tick(1)
        with self.assertRaisesRegex(LuaError, "candidate changed source frame"):
            lua.globals().cargo_candidate("5.0.20018", None)

    def test_configuration_requires_boolean_event_flag_but_does_not_presume_false(self):
        self.source_to_partial()
        with self.assertRaisesRegex(LuaError, "configuration event differs"):
            self.lua.globals().cargo_candidate("5.0.20018", None, 0)

    def test_candidate_rejects_published_head_gate_mismatch_before_new_work(self):
        self.source_to_partial()
        with self.assertRaisesRegex(LuaError, "candidate head debit differs"):
            self.lua.globals().cargo_candidate("5.0.20018", self.lua.globals().cargo_wrong_gate)

    def test_candidate_rejects_later_existing_force_bonus_change(self):
        self.source_to_partial()
        self.lua.globals().cargo_add_late_force()
        with self.assertRaisesRegex(LuaError, "candidate changed source frame"):
            self.lua.globals().cargo_candidate("5.0.20018", None)

    def test_candidate_requires_the_native_plus_one_bonus(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        with self.assertRaisesRegex(LuaError, "candidate ordinary earned worker bonus differs"):
            self.lua.globals().cargo_complete(False, None, -100)

    def test_candidate_requires_existing_foreign_force_bonus_to_stay_unchanged(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.lua.globals().cargo_add_late_force()
        with self.assertRaisesRegex(LuaError, "candidate ordinary foreign worker bonus differs"):
            self.lua.globals().cargo_complete(False)

    def test_scripted_completion_is_rejected(self):
        self.lua.globals().cargo_begin()
        with self.assertRaisesRegex(LuaError, "scripted worker completion"):
            self.lua.globals().cargo_complete(True)

    def test_engine_event_cursor_must_be_incremented_before_callback(self):
        self.lua.globals().cargo_begin()
        with self.assertRaisesRegex(LuaError, "source ordinary completion level differs"):
            self.lua.globals().cargo_complete(False, 4)

    def test_candidate_configuration_observes_source_before_any_new_work(self):
        self.source_to_partial()
        before = list(self.lua.globals().cargo_counts().values())
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.assertEqual("candidate-working", self.lua.globals().cargo_phase())
        self.assertIn("phase=candidate-pre-work", self.logs()[-1])
        self.assertGreaterEqual(sum(self.lua.globals().cargo_counts().values()), sum(before))

    def test_candidate_rejects_wrong_five_pack_construction_before_work(self):
        self.source_to_partial()
        self.lua.globals().cargo_science(self.lua.eval(_lua_array(world.SCIENCE[:5])))
        with self.assertRaisesRegex(LuaError, "worker science count differs"):
            self.lua.globals().cargo_candidate("5.0.20018", None)
        self.assertEqual("source-partial", self.lua.globals().cargo_phase())

    def test_candidate_rejects_changed_partial_current_or_queue(self):
        self.source_to_partial()
        self.lua.globals().cargo_drop_queue()
        with self.assertRaisesRegex(LuaError, "candidate changed source frame"):
            self.lua.globals().cargo_candidate("5.0.20018", None)

    def test_candidate_completes_two_ordinary_events_and_refuses_cap_start_without_debit(self):
        self.candidate_to_closed()
        log = self.logs()[-1]
        self.assertIn("phase=candidate-closed", log)
        self.assertIn("candidate_events=2", log)
        self.assertIn("cap_attempt=refused", log)
        self.assertIn("level=11", log)
        self.assertIn(f"current={world.TAIL}", log)
        self.assertIn(f"queue={world.TAIL}", log)
        self.assertIn("expected_worker_bonus=7", log)
        self.assertIn("laboratory_productivity_bonus=0", log)
        self.assertIn("technology_price_multiplier=1", log)
        self.assertIn("science_debit=automation-science-pack:7.42", log)
        self.assertEqual(["mir5-se-worker-storage-cap10-source", "mir5-se-worker-storage-cap10-candidate"], list(self.lua.globals().cargo_saves().values()))

    def test_cap_refusal_preserves_unrelated_tail_as_current_queue_and_science(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.lua.globals().cargo_complete(False)
        self.assertEqual([world.TAIL], list(self.lua.globals().cargo_queue_names().values()))
        self.assertEqual(world.TAIL, self.lua.globals().cargo_current_name())
        before = dict(self.lua.globals().cargo_counts().items())
        self.lua.globals().cargo_tick(1)
        self.assertEqual("closed", self.lua.globals().cargo_phase())
        self.assertEqual(before, dict(self.lua.globals().cargo_counts().items()))
        self.assertEqual([world.TAIL], list(self.lua.globals().cargo_queue_names().values()))

    def test_cap_refusal_requires_native_disabled_endpoint_before_trying_to_queue_again(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_reenable_cap()
        with self.assertRaisesRegex(LuaError, "candidate cap disabled state differs"):
            self.lua.globals().cargo_tick(1)
        self.assertEqual(world.TAIL, self.lua.globals().cargo_current_name())
        self.assertEqual([world.TAIL], list(self.lua.globals().cargo_queue_names().values()))

    def test_queue_enabled_model_appends_an_explicitly_reenabled_cap_technology_after_the_tail(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.lua.globals().cargo_complete(False)
        self.assertTrue(self.lua.globals().cargo_reenable_cap_and_queue())
        self.assertEqual([world.TAIL, world.CANDIDATE], list(self.lua.globals().cargo_queue_names().values()))

    def test_candidate_close_rejects_post_completion_wrong_earned_bonus(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_mutate_bonus(-100)
        with self.assertRaisesRegex(LuaError, "candidate cap earned worker bonus differs"):
            self.lua.globals().cargo_tick(1)

    def test_tail_loss_after_native_candidate_completion_is_rejected(self):
        self.source_to_partial()
        self.lua.globals().cargo_candidate("5.0.20018", None)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_tick(1)
        self.lua.globals().cargo_complete(False)
        self.lua.globals().cargo_drop_queue()
        with self.assertRaisesRegex(LuaError, "candidate cap tail current differs"):
            self.lua.globals().cargo_tick(1)

    def test_cold_handler_reads_closed_state_without_feed_or_persistent_initialization(self):
        self.candidate_to_closed()
        before = dict(self.lua.globals().cargo_counts().items())
        saves = list(self.lua.globals().cargo_saves().values())
        self.lua.globals().cargo_cold()
        self.assertEqual("closed", self.lua.globals().cargo_phase())
        self.assertEqual(before, dict(self.lua.globals().cargo_counts().items()))
        self.assertEqual(saves, list(self.lua.globals().cargo_saves().values()))
        self.assertIn("phase=cold-read", self.logs()[-1])
        self.assertIn("cold_writes=0", self.logs()[-1])

    def test_cold_mutation_is_rejected(self):
        self.candidate_to_closed()
        self.lua.globals().cargo_mutate_closed()
        with self.assertRaisesRegex(LuaError, "cold process changed candidate endpoint"):
            self.lua.globals().cargo_cold()

    def test_missing_fixture_owned_external_power_refuses_before_research(self):
        self.lua.globals().cargo_missing_power()
        with self.assertRaisesRegex(LuaError, "fixture external power differs"):
            self.lua.globals().cargo_begin()
        self.assertEqual("idle", self.lua.globals().cargo_phase())

    def test_missing_science_feed_refuses_without_completion(self):
        self.lua.globals().cargo_block_feed()
        with self.assertRaisesRegex(LuaError, "native science feed differs"):
            self.lua.globals().cargo_begin()
        self.assertEqual("source-working", self.lua.globals().cargo_phase())

    def test_unmodified_native_se_lab_speed_is_required(self):
        self.lua.globals().cargo_lab_speed(14400)
        with self.assertRaisesRegex(LuaError, "native SE lab speed differs"):
            self.lua.globals().cargo_begin()

    def test_loaded_file_settings_are_not_prototype_defaults(self):
        source = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertIn("settings.startup", source)
        self.assertIn("row.value", source)
        self.assertNotIn("default_value", source)
        self.assertEqual(10, world.SETTINGS["mir-max-level-worker-robots-storage"])

    def test_data_stage_strict_proxy_logs_all_twenty_mods_and_actual_file_values(self):
        result, logs = self.data_stage()
        self.assertTrue(result)
        active = next(row for row in logs if row.startswith("[MIR_ACTIVE_MODS]"))
        settings = next(row for row in logs if row.startswith("[MIR_WORKER_STORAGE_SETTINGS]"))
        construction = next(row for row in logs if row.startswith("[MIR_SE_CARGO_CONSTRUCTION]"))
        self.assertEqual(20, active.count("@"))
        self.assertIn("mir-max-level-worker-robots-storage=number:10", settings)
        self.assertIn("mir-enable-worker-robots-storage=boolean:true", settings)
        self.assertIn("se-material-science-pack-1:1", construction)
        self.assertIn("space-science-pack:1", construction)

    def test_data_stage_rejects_missing_wrong_or_nonfinite_loaded_setting(self):
        for label, values, expected in (
            ("missing", {key: value for key, value in world.SETTINGS.items() if key != "mir-max-level-worker-robots-storage"}, "missing setting"),
            ("wrong-type", {**world.SETTINGS, "mir-max-level-worker-robots-storage": True}, "wrong setting type"),
            ("nonfinite", {**world.SETTINGS, "mir-cost-growth-worker-robots-storage": float("inf")}, "nonfinite setting"),
        ):
            with self.subTest(label=label):
                result, _ = self.data_stage(values)
                self.assertFalse(result[0])
                self.assertIn(expected, result[1])

    def test_data_stage_observes_wrong_five_pack_construction_without_masking_candidate_refusal(self):
        result, logs = self.data_stage(ingredients=world.SCIENCE[:5])
        self.assertTrue(result)
        construction = next(row for row in logs if row.startswith("[MIR_SE_CARGO_CONSTRUCTION]"))
        self.assertNotIn("se-material-science-pack-1", construction)
        self.assertNotIn("space-science-pack", construction)

    def test_data_stage_construction_marker_is_observation_not_candidate_mask(self):
        source = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertIn("[MIR_SE_CARGO_CONSTRUCTION]", source)
        self.assertNotIn("error(PREFIX .. \" worker science", source)
        self.assertIn("assert_worker_contract(state.player, CANDIDATE)", (FIXTURE / "control.lua").read_text(encoding="utf-8"))

    def test_actor_uses_no_continuation_or_progress_setter(self):
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertNotRegex(source, r"target\.level\s*=(?!=)")
        self.assertNotRegex(source, r"research_progress\s*=(?!=)")
        self.assertIn("event.by_script == false", source)
        self.assertIn("state.player.add_research(target) == false", source)

    def test_fixture_power_is_owned_but_never_clones_or_alters_the_native_lab_prototype(self):
        data = (FIXTURE / "data.lua").read_text(encoding="utf-8")
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('data.raw["electric-energy-interface"]["electric-energy-interface"]', data)
        self.assertIn("mir-fixture-worker-storage-se-cap-ten-power", data)
        self.assertIn("se-space-science-lab", control)
        self.assertNotIn("table.deepcopy(data.raw.lab", data)
        self.assertNotIn("researching_speed =", data)

    def test_strict_world_rejects_unapproved_force_write(self):
        with self.assertRaisesRegex(LuaError, "LuaForce unsupported write"):
            self.lua.globals().cargo_unsupported_force_write()

    def test_full_actor_keeps_data_observer_and_runtime_role_distinct(self):
        data_observer = ROOT / "tests" / "fixtures" / "worker-storage-se-cap-ten"
        self.assertNotEqual(data_observer.name, FIXTURE.name)
        self.assertNotEqual((data_observer / "data-final-fixes.lua").read_bytes(), (FIXTURE / "data-final-fixes.lua").read_bytes())
        self.assertTrue((FIXTURE / "control.lua").is_file())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    arguments = parser.parse_args()
    sys.path.insert(0, str(arguments.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaError as _LuaError, LuaRuntime as _LuaRuntime
    LuaRuntime, LuaError = _LuaRuntime, _LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerStorageSECapTenNativeTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

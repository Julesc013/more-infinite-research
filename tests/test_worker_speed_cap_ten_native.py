"""Pinned host controls for the reduced F200/SE worker-speed tail-ten actor.

They exercise fixture setup and the real pure cap reconciler with native-shaped
doubles. They neither start Factorio nor qualify native gameplay.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from worker_speed_cap_world import build_worker_speed_world


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-speed-cap-ten-native"
SOURCE = FIXTURE / "source"
OLD_NEGATIVE = FIXTURE / "cap10"
SUCCESSOR = FIXTURE / "successor16"
CURRENT_OLD_NEGATIVE = FIXTURE / "current-old15"
CURRENT_SUCCESSOR = FIXTURE / "current-successor16"
CURRENT_OBSERVE = FIXTURE / "current-observe16"
CURRENT_SUCCESSOR17 = FIXTURE / "current-successor17"
SOURCE_PRODUCER15 = FIXTURE / "source-producer15"
PRODUCER_OLD15 = FIXTURE / "producer-old15"
PRODUCER_SUCCESSOR17 = FIXTURE / "producer-successor17"
LUA_ROOT = ROOT / "source"
WORKER = "worker-robots-speed-10"
PREDECESSOR = "worker-robots-speed-9"
DEEP_SCIENCE = "se-deep-space-science-pack-1"
AUTOMATION_SCIENCE = "automation-science-pack"
AUTOMATION = "automation"
ELECTRICITY = "electricity"
UNRELATED = "mir-fixture-unrelated-disabled"
CURRENT_SENTINEL = "stone-wall"
CAP = "mir-max-level-worker-robots-speed"
# Independent native oracle: mir516-se-cap-preconditions-r01/.../preconditions.json
# SHA256 644CE236FBEBEFF24F74D72F2F770FAE2D107FF1529371C1E081EC5980E7B758.
PREDECESSOR_LEVEL = 9
PACKS = (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "utility-science-pack", "space-science-pack", "se-rocket-science-pack",
    "se-energy-science-pack-4", "se-deep-space-science-pack-1",
)
ACTIVE_MODS = (
    "aai-containers@0.3.2", "aai-industry@0.6.16", "aai-signal-transmission@0.5.3",
    "alien-biomes-graphics@0.7.1", "alien-biomes@0.7.4", "base@2.0.77",
    "informatron@0.4.0", "jetpack@0.4.17",
    "mir-fixture-mir5-worker-speed-cap-ten@0.5.0", "more-infinite-research@5.0.20015",
    "robot_attrition@0.6.6", "shield-projector@0.2.2",
    "space-exploration-graphics-2@0.7.2", "space-exploration-graphics-3@0.7.2",
    "space-exploration-graphics-4@0.7.2", "space-exploration-graphics-5@0.7.3",
    "space-exploration-graphics@0.7.5", "space-exploration-menu-simulations@0.7.4",
    "space-exploration-postprocess@0.7.5", "space-exploration@0.7.57",
)
ACTIVE_MODS_OBSERVER = "mir-fixture-mir5-worker-speed-cap-ten"


class WorkerSpeedCapTenNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.world = build_worker_speed_world(self.lua, LUA_ROOT)

    def data_result(self, stage: str, opponent: str = ""):
        directory = {"source15": SOURCE, "old-negative15": OLD_NEGATIVE, "successor16": SUCCESSOR,
                     "current-old15": CURRENT_OLD_NEGATIVE, "current-successor16": CURRENT_SUCCESSOR,
                      "current-observe16": CURRENT_OBSERVE, "current-successor17": CURRENT_SUCCESSOR17,
                      "source-producer15": SOURCE_PRODUCER15, "producer-old15": PRODUCER_OLD15,
                      "producer-successor17": PRODUCER_SUCCESSOR17}[stage]
        return self.world["data_case"](str(directory / "settings-updates.lua"), str(directory / "data-final-fixes.lua"),
                                          str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"), stage, opponent)

    def flow_result(self, mode: str = "successor", opponent: str = ""):
        return self.world["flow"](str(SOURCE / "control.lua"), str(OLD_NEGATIVE / "control.lua"), str(SUCCESSOR / "control.lua"),
                                     str(FIXTURE / "fixture_control.lua"), mode, opponent)

    def source_producer_result(self, cold: bool = False, fixture_control: Path = FIXTURE / "fixture_control.lua"):
        return self.world["source_producer_flow"](str(SOURCE_PRODUCER15 / "control.lua"),
                                                       str(fixture_control), cold)

    def producer_transition_result(self, mode: str = "successor", opponent: str = "", fixture_control: Path = FIXTURE / "fixture_control.lua"):
        return self.world["producer_successor_flow"](
            str(SOURCE_PRODUCER15 / "control.lua"), str(PRODUCER_OLD15 / "control.lua"),
            str(PRODUCER_SUCCESSOR17 / "control.lua"), str(fixture_control), mode, opponent)

    def current_state_result(self, mode: str = "candidate", opponent: str = "", fixture_control: Path = FIXTURE / "fixture_control.lua"):
        return self.world["current_state_flow"](str(CURRENT_OLD_NEGATIVE / "control.lua"),
                                                   str(CURRENT_SUCCESSOR / "control.lua"),
                                                   str(CURRENT_SUCCESSOR17 / "control.lua"),
                                                   str(CURRENT_OBSERVE / "control.lua"),
                                                   str(fixture_control), mode, opponent)

    def test_metadata_declares_three_explicit_f200_se_stages(self):
        for directory, version, mir in ((SOURCE, "0.4.0", "5.0.20015"), (OLD_NEGATIVE, "0.5.0", "5.0.20015"),
                                        (SUCCESSOR, "0.6.0", "5.0.20016"),
                                        (CURRENT_OLD_NEGATIVE, "0.7.0", "5.0.20015"),
                                        (CURRENT_SUCCESSOR, "0.8.0", "5.0.20016"),
                                        (CURRENT_OBSERVE, "0.9.0", "5.0.20016"),
                                         (CURRENT_SUCCESSOR17, "0.12.0", "5.0.20017"),
                                         (SOURCE_PRODUCER15, "0.13.0", "5.0.20015")):
            with self.subTest(stage=directory.name):
                info = json.loads((directory / "info.json").read_text(encoding="utf-8"))
                self.assertEqual(("mir-fixture-mir5-worker-speed-cap-ten", version, "2.0"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(["base = 2.0.77", "space-exploration = 0.7.57", f"more-infinite-research = {mir}"], info["dependencies"])

    def test_data_preflight_retains_actual_tail_ten_contract_and_only_adds_fixture_lab(self):
        for stage, cap in (("source15", 0), ("old-negative15", 10), ("successor16", 10),
                           ("current-old15", 10), ("current-successor16", 10), ("current-observe16", 10),
                            ("current-successor17", 10), ("source-producer15", 0)):
            with self.subTest(stage=stage):
                result = self.data_result(stage)
                self.assertTrue(result["ok"], result["message"])
                worker = result["raw"]["technology"][WORKER]
                self.assertEqual(("infinite", "worker-robot-speed", .65), (worker["max_level"], worker["effects"][1]["type"], worker["effects"][1]["modifier"]))
                self.assertEqual(("0.2*(2^(L-6)*1000)", 60, PACKS), (worker["unit"]["count_formula"], worker["unit"]["time"], tuple(worker["unit"]["ingredients"][i][1] for i in range(1, 9))))
                self.assertEqual((PREDECESSOR, DEEP_SCIENCE), tuple(worker["prerequisites"][i] for i in range(1, 3)))
                self.assertEqual(cap, result["raw"]["int-setting"][CAP]["default_value"])
                if stage == "current-observe16":
                    self.assertEqual((1, 0), (len(result["rows"]), len(result["logs"])))
                else:
                    self.assertEqual(PACKS, tuple(result["rows"][1]["inputs"][i] for i in range(1, 9)))
                    self.assertEqual(1, len(result["logs"]))
                    observed = result["logs"][1]
                    self.assertTrue(observed.startswith("[MIR_ACTIVE_MODS] "))
                    reported = observed.removeprefix("[MIR_ACTIVE_MODS] ").split("|")
                    expected_mods = sorted(f"{name}@{version}" for name, version in result["mods"].items())
                    self.assertEqual(expected_mods, reported)
                    self.assertEqual(20, len(reported))
        current_successor = self.data_result("current-successor16")
        current_successor17 = self.data_result("current-successor17")
        observe = self.data_result("current-observe16")
        def lab_signature(row):
            return (row["name"], row["minable"], row["energy_source"]["type"], row["researching_speed"],
                    tuple(row["inputs"][index] for index in range(1, len(row["inputs"]) + 1)))
        def prototype_signature(result):
            worker = result["raw"]["technology"][WORKER]
            return (worker["max_level"], worker["effects"][1]["type"], worker["effects"][1]["modifier"],
                    tuple(worker["prerequisites"][index] for index in range(1, len(worker["prerequisites"]) + 1)),
                    worker["unit"]["count_formula"], worker["unit"]["time"],
                    tuple((worker["unit"]["ingredients"][index][1], worker["unit"]["ingredients"][index][2])
                          for index in range(1, len(worker["unit"]["ingredients"]) + 1)),
                    result["raw"]["int-setting"][CAP]["default_value"], lab_signature(result["rows"][1]))
        self.assertEqual(prototype_signature(current_successor), prototype_signature(current_successor17))
        self.assertEqual(lab_signature(current_successor["rows"][1]), lab_signature(observe["rows"][1]))
        self.assertEqual((1, 1, 1), (len(current_successor["rows"]), len(current_successor17["rows"]), len(observe["rows"])))
        self.assertEqual((1, 1, 0), (len(current_successor["logs"]), len(current_successor17["logs"]), len(observe["logs"])))
        self.assertEqual(prototype_signature(self.data_result("source15")),
                         prototype_signature(self.data_result("source-producer15")))
        for opponent, phrase in (("wrong-cap", "worker-speed cap startup differs"), ("wrong-effect", "SE worker-speed effect differs"), ("wrong-formula", "SE worker-speed research unit differs")):
            with self.subTest(opponent=opponent):
                result = self.data_result("successor16", opponent); self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])
        old_bad = self.data_result("current-successor16", "wrong-effect")
        observe_bad = self.data_result("current-observe16", "wrong-effect")
        self.assertFalse(old_bad["ok"]); self.assertIn("SE worker-speed effect differs", old_bad["message"])
        self.assertFalse(observe_bad["ok"]); self.assertIn("SE worker-speed effect differs", observe_bad["message"])
        self.assertEqual((1, 0), (len(old_bad["logs"]), len(observe_bad["logs"])))
        stale_mir = self.data_result("current-successor17", "stale-mir17")
        self.assertFalse(stale_mir["ok"])
        self.assertIn("fixture stage version differs", stale_mir["message"])

    @staticmethod
    def _current_markers(result):
        return {row["phase"]: row for row in (result["markers"][index]
                for index in range(1, len(result["markers"]) + 1))}

    @staticmethod
    def _current_frame_signature(frame):
        worker = frame["worker"]
        queue = worker["queue"]
        flags = frame["prerequisite_flags"]
        return (
            frame["force_index"], frame["force_name"], worker["level"], worker["researched"], worker["enabled"],
            worker["visible"], worker["saved_progress"], worker["bonus"], worker["per_level_speed_effect"],
            worker["research_unit_count"], worker["research_unit_energy"], queue["current"],
            tuple(queue["queue"][index] for index in range(1, len(queue["queue"]) + 1)), queue["progress"],
            tuple((name, flags[name]["researched"], flags[name]["enabled"], flags[name]["visible"],
                   flags[name]["level"], flags[name]["valid"])
                  for name in (PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION)),
            frame["unrelated_sentinel"]["name"], frame["unrelated_sentinel"]["researched"],
            frame["unrelated_sentinel"]["enabled"], frame["unrelated_sentinel"]["visible"],
            frame["unrelated_sentinel"]["level"], frame["unrelated_sentinel"]["valid"],
        )

    @staticmethod
    def _current_admin_helper_source():
        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        prefix = "local function apply_current_admin_sequence"
        return prefix + source.split(prefix, 1)[1].split("local function begin_current_observe", 1)[0]

    def _run_current_admin_proxy(self, helper_source: str, callback_disables_gate: bool):
        runner = self.lua.execute(r'''
local WORKER = "worker-robots-speed-10"
local PROBE = "automation"
local EARNED_LEVEL = 13
local PARTIAL = .27
local FOREIGN_PROGRESS = .42
local set_current_prerequisites
local technology
''' + helper_source + r'''

return function(callback_disables_gate)
  local writes, frames, boundaries, setter_effects = {}, {}, {}, {}
  local current_boundary = "before-admin"
  local function snapshot(values)
    return {level=values.level, researched=values.researched, enabled=values.enabled,
      visible_when_disabled=values.visible_when_disabled}
  end
  local function target(role)
    local values = {level=10, researched=true, enabled=false, visible_when_disabled=true,
      initial_level=10, pending_level_write=false}
    local proxy = {}
    setmetatable(proxy, {
      __index = function(_, key) return values[key] end,
      __newindex = function(_, key, value)
        if key == "researched" and value == false then
          values.researched = false
            -- Model only the retained r01 observed level->researched=false outcome;
            -- this is not a general LuaTechnology setter rule.
          if values.pending_level_write then values.level = values.initial_level end
          values.pending_level_write = false
          setter_effects[#setter_effects + 1] = {role=role, effect="researched-false-restores-initial-level",
            level=values.level}
        elseif key == "level" then
            -- The 2.0.77 SDK documents that a level write reenables the technology.
          values.level, values.enabled, values.pending_level_write = value, true, true
          setter_effects[#setter_effects + 1] = {role=role, effect="level-write-reenables",
            level=values.level, enabled=values.enabled}
        else
          values[key] = value
        end
        writes[#writes + 1] = {role=role, field=key, value=value, boundary=current_boundary}
        if callback_disables_gate and key == "level" then
          values.enabled = false
          values.visible_when_disabled = true
          writes[#writes + 1] = {role=role, field="callback-disable", value=false,
            boundary=current_boundary}
        end
      end,
    })
    return proxy, values
  end
  local function force(role)
    local worker, values = target(role)
    local force = {role=role, worker=worker}
    setmetatable(force, {
      __newindex = function(subject, key, value)
        rawset(subject, key, value)
        writes[#writes + 1] = {role=role, field=key, value=value, boundary=current_boundary}
      end,
    })
    return force, values
  end
  local player, player_values = force("player")
  local foreign, foreign_values = force("foreign")
  local earned, earned_values = force("earned")
  set_current_prerequisites = function(force, foreign_role, label)
    writes[#writes + 1] = {role=force.role, field="prerequisites", value=foreign_role,
      boundary=current_boundary}
  end
  technology = function(force, name)
    assert(name == WORKER or name == "automation")
    return force.worker
  end
  local function frame(action)
    frames[#frames + 1] = {action=action, player=snapshot(player_values),
      foreign=snapshot(foreign_values), earned=snapshot(earned_values)}
  end
  local hooks = {
    before = function(action)
      current_boundary = action
      boundaries[#boundaries + 1] = "before:" .. action
    end,
    after = function(action)
      frame(action)
      boundaries[#boundaries + 1] = "after:" .. action
    end,
  }
  apply_current_admin_sequence(player, foreign, earned, "proxy", hooks)
  return {writes=writes, frames=frames, boundaries=boundaries, setter_effects=setter_effects}
end
''')
        return runner(callback_disables_gate)

    @staticmethod
    def _lua_rows(table):
        return [table[index] for index in range(1, len(table) + 1)]

    def test_current_admin_target_setters_model_observed_reversal_and_documented_reenable(self):
        helper = self._current_admin_helper_source()
        actual = self._run_current_admin_proxy(helper, True)
        writes = self._lua_rows(actual["writes"])
        target_fields = {"level", "researched", "enabled", "visible_when_disabled"}
        expected_levels = {"player": 10, "foreign": 11, "earned": 13}
        for role, level in expected_levels.items():
            with self.subTest(role=role):
                target_writes = [row for row in writes if row["role"] == role and row["field"] in target_fields]
                self.assertEqual([("researched", False), ("level", level), ("enabled", True),
                                  ("visible_when_disabled", False)],
                                 [(row["field"], row["value"]) for row in target_writes])
                for row in target_writes:
                    if row["field"] != "level":
                        self.assertIs(type(row["value"]), bool)
        ordered_writes = [(row["role"], row["field"]) for row in writes
                          if row["field"] in target_fields | {"research_queue", "research_progress"}]
        self.assertEqual([
            ("player", "researched"), ("player", "level"), ("player", "enabled"), ("player", "visible_when_disabled"),
            ("player", "research_queue"), ("player", "research_progress"),
            ("foreign", "researched"), ("foreign", "level"), ("foreign", "enabled"), ("foreign", "visible_when_disabled"),
            ("foreign", "research_queue"), ("foreign", "research_progress"),
            ("earned", "researched"), ("earned", "level"), ("earned", "enabled"), ("earned", "visible_when_disabled"),
            ("earned", "research_queue"),
        ], ordered_writes)
        self.assertEqual([
            "before:prerequisites", "after:prerequisites", "before:player-target", "after:player-target",
            "before:player-queue", "after:player-queue", "before:player-progress", "after:player-progress",
            "before:foreign-target", "after:foreign-target", "before:foreign-queue", "after:foreign-queue",
            "before:foreign-progress", "after:foreign-progress", "before:earned-target", "after:earned-target",
            "before:earned-queue", "after:earned-queue",
        ], [actual["boundaries"][index] for index in range(1, len(actual["boundaries"]) + 1)])
        frames = {row["action"]: row for row in self._lua_rows(actual["frames"])}
        for action, role, level in (("player-target", "player", 10), ("foreign-target", "foreign", 11),
                                    ("earned-target", "earned", 13)):
            with self.subTest(frame=action):
                self.assertEqual((level, False, True, False),
                                 (frames[action][role]["level"], frames[action][role]["researched"],
                                  frames[action][role]["enabled"], frames[action][role]["visible_when_disabled"]))

        effects = self._lua_rows(actual["setter_effects"])
        self.assertEqual([
            ("player", "researched-false-restores-initial-level", 10),
            ("player", "level-write-reenables", 10),
            ("foreign", "researched-false-restores-initial-level", 10),
            ("foreign", "level-write-reenables", 11),
            ("earned", "researched-false-restores-initial-level", 10),
            ("earned", "level-write-reenables", 13),
        ], [(row["role"], row["effect"], row["level"]) for row in effects])
        self.assertTrue(all(row["enabled"] is True for row in effects if row["effect"] == "level-write-reenables"))

        level_first_mutant = helper
        flags_first_mutant = helper
        for level in ("10", "11", "EARNED_LEVEL"):
            original = (f"owner.researched = false\n  owner.level = {level}\n  owner.enabled = true\n"
                        "  owner.visible_when_disabled = false")
            level_first_mutant = level_first_mutant.replace(
                original,
                f"owner.level = {level}\n  owner.researched = false\n  owner.enabled = true\n"
                "  owner.visible_when_disabled = false",
            )
            flags_first_mutant = flags_first_mutant.replace(
                original,
                f"owner.enabled = true\n  owner.visible_when_disabled = false\n  owner.researched = false\n  owner.level = {level}",
            )
        self.assertNotEqual(helper, level_first_mutant)
        self.assertNotEqual(helper, flags_first_mutant)
        level_first_frames = {row["action"]: row for row in self._lua_rows(
            self._run_current_admin_proxy(level_first_mutant, True)["frames"])}
        for action, role in (("foreign-target", "foreign"), ("earned-target", "earned")):
            with self.subTest(mutant="level-first", frame=action):
                self.assertEqual((10, False, True, False),
                                 (level_first_frames[action][role]["level"], level_first_frames[action][role]["researched"],
                                  level_first_frames[action][role]["enabled"], level_first_frames[action][role]["visible_when_disabled"]))
        flags_frames = {row["action"]: row for row in self._lua_rows(
            self._run_current_admin_proxy(flags_first_mutant, True)["frames"])}
        for action, role in (("player-target", "player"), ("foreign-target", "foreign"),
                             ("earned-target", "earned")):
            with self.subTest(mutant="flags-first", frame=action):
                self.assertEqual((False, True), (flags_frames[action][role]["enabled"],
                                                 flags_frames[action][role]["visible_when_disabled"]))

    def test_current_state_reset_roles_keep_the_declared_three_force_boundary(self):
        old = self.current_state_result("old")
        self.assertFalse(old["ok"])
        self.assertIn("MIR_EXPECTED_CURRENT_OLD15_RESET_NOT_ENFORCED", old["message"])
        self.assertEqual((0, 0), (old["saves"], old["labs"]))
        old_markers = self._current_markers(old)
        self.assertEqual({"current-provider", "current-admin-observed", "current-pre-reset", "current-post-reset"}, set(old_markers))
        provider, admin_observed, old_pre, old_post = (old_markers[phase] for phase in
            ("current-provider", "current-admin-observed", "current-pre-reset", "current-post-reset"))
        self.assertEqual(("post-provider-normalization-before-fixture-admin", "controller-bound-A0-base-input-only",
                          "not-read-no-continuation-precondition"),
                         (provider["snapshot_role"], provider["source_base"]["identity"],
                          provider["source_base"]["fixture_source_phase"]))
        self.assertEqual("published15-reset-event-not-enforced", old_post["outcome"])
        self.assertEqual(3, old_post["reset_call_count"])
        self.assertEqual({"player", "foreign", "earned_above_cap"},
                         {old_post["reset_rows"][index]["force_role"]
                          for index in range(1, len(old_post["reset_rows"]) + 1)})
        self.assertTrue(all(old_post["reset_rows"][index]["native_event_delivered"] is True
                            for index in range(1, len(old_post["reset_rows"]) + 1)))

        for frame_name in ("player", "foreign", "earned_above_cap"):
            frame = provider[frame_name]
            self.assertIsInstance(frame["force_index"], int)
            self.assertIsInstance(frame["force_name"], str)
            self.assertTrue(frame["unrelated_sentinel"]["enabled"])
            self.assertIsNone(frame["unrelated_sentinel"]["queue"])
            self.assertEqual({PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION},
                             set(frame["prerequisite_flags"].keys()))
            self.assertFalse(admin_observed[frame_name]["unrelated_sentinel"]["enabled"])
            self.assertFalse(old_pre[frame_name]["unrelated_sentinel"]["enabled"])
        self.assertEqual("after-declared-admin-before-baseline-validation", admin_observed["snapshot_role"])

        player_intent = old_pre["admin_intent"]["player"]
        foreign_intent = old_pre["admin_intent"]["foreign"]
        self.assertEqual((10, False, True, (WORKER, WORKER), .27),
                         (player_intent["worker"]["level"], player_intent["worker"]["researched"],
                          player_intent["worker"]["enabled"], tuple(player_intent["worker"]["queue"][index]
                                                                        for index in range(1, len(player_intent["worker"]["queue"]) + 1)),
                          player_intent["worker"]["progress"]))
        self.assertEqual((11, True, (AUTOMATION,), .42),
                         (foreign_intent["worker"]["level"], foreign_intent["worker"]["enabled"],
                          tuple(foreign_intent["queue"][index] for index in range(1, len(foreign_intent["queue"]) + 1)),
                          foreign_intent["progress"]))
        self.assertEqual((CURRENT_SENTINEL, False), (old_pre["admin_intent"]["unrelated_sentinel"]["name"],
                                                      old_pre["admin_intent"]["unrelated_sentinel"]["enabled"]))
        self.assertEqual((10, True, 2, .27), (old_pre["player"]["worker"]["level"],
                                               old_pre["player"]["worker"]["enabled"],
                                               len(old_pre["player"]["worker"]["queue"]["queue"]),
                                               old_pre["player"]["worker"]["queue"]["progress"]))
        self.assertEqual((11, True, AUTOMATION, .42), (old_pre["foreign"]["worker"]["level"],
                                                        old_pre["foreign"]["worker"]["enabled"],
                                                        old_pre["foreign"]["worker"]["queue"]["current"],
                                                        old_pre["foreign"]["worker"]["queue"]["progress"]))
        self.assertEqual((13, True, False), (old_pre["earned_above_cap"]["worker"]["level"],
                                              old_pre["earned_above_cap"]["worker"]["enabled"],
                                              old_pre["earned_above_cap"]["worker"]["queue"]["current"]))

        candidate = self.current_state_result()
        self.assertTrue(candidate["ok"], candidate["message"])
        self.assertEqual((1, 1), (candidate["saves"], candidate["labs"]))
        candidate_markers = self._current_markers(candidate)
        self.assertEqual({"current-provider", "current-admin-observed", "current-pre-reset", "current-post-reset",
                          "current-pre-work", "current-complete", "current-cold"}, set(candidate_markers))
        candidate_pre, candidate_post, pre_work = (candidate_markers[phase] for phase in
                                                    ("current-pre-reset", "current-post-reset", "current-pre-work"))
        for role in ("player", "foreign", "earned_above_cap"):
            self.assertEqual(self._current_frame_signature(old_pre[role]), self._current_frame_signature(candidate_pre[role]))
        self.assertEqual("candidate16-reset-event-enforced", candidate_post["outcome"])
        self.assertEqual((10, 1, .27), (candidate_post["player"]["worker"]["level"],
                                        len(candidate_post["player"]["worker"]["queue"]["queue"]),
                                        candidate_post["player"]["worker"]["queue"]["progress"]))
        self.assertEqual((False, AUTOMATION, .42), (candidate_post["foreign"]["worker"]["enabled"],
                                                     candidate_post["foreign"]["worker"]["queue"]["current"],
                                                     candidate_post["foreign"]["worker"]["queue"]["progress"]))
        self.assertEqual((13, False), (candidate_post["earned_above_cap"]["worker"]["level"],
                                       candidate_post["earned_above_cap"]["worker"]["enabled"]))
        self.assertIsInstance(pre_work["post_reset_player_bonus"], (int, float))
        complete, cold = candidate_markers["current-complete"], candidate_markers["current-cold"]
        self.assertEqual((1, 0, 2), (complete["ordinary_native_completion_count"],
                                     complete["level_eleven_start_count"], complete["post_completion_hold_ticks"]))
        for phase in (complete, cold):
            self.assertEqual((WORKER, False, 10, 11), (
                phase["ordinary_events"][1]["name"], phase["ordinary_events"][1]["by_script"],
                phase["ordinary_events"][1]["completed_level"], phase["ordinary_events"][1]["event_post_increment_level"]))
            self.assertIsInstance(phase["ordinary_events"][1]["tick"], int)
        self.assertAlmostEqual(complete["post_reset_player_bonus"] + .65,
                               complete["post_completion"]["player"]["worker"]["bonus"])
        self.assertEqual(set(PACKS), set(complete["lab"]["input_by_name"].keys()))
        self.assertTrue(all(complete["lab"]["input_by_name"][name] > 0 for name in PACKS))
        self.assertEqual((True, 2), (cold["on_load_read_only"], cold["post_completion_hold_ticks"]))
        for phase in (complete, cold):
            self.assertEqual({"player", "foreign", "earned_above_cap"}, set(phase["completed_forces"].keys()))
            for role in ("player", "foreign", "earned_above_cap"):
                self.assertEqual(self._current_frame_signature(phase["completed_forces"][role]),
                                 self._current_frame_signature(phase["post_completion"][role]))
        self.assertEqual(["worker-speed-cap-ten/current-provider.json", "worker-speed-cap-ten/current-admin-observed.json",
                          "worker-speed-cap-ten/current-pre-reset.json", "worker-speed-cap-ten/current-post-reset.json",
                          "worker-speed-cap-ten/current-pre-work.json", "worker-speed-cap-ten/current-complete.json",
                          "worker-speed-cap-ten/current-cold.json", "worker-speed-cap-ten/current-cold.json"],
                         [candidate["files"][index]["path"] for index in range(1, len(candidate["files"]) + 1)])

    def test_current_successor17_runs_the_shared_current_lifecycle_with_source17_headers(self):
        candidate = self.current_state_result("candidate17")
        self.assertTrue(candidate["ok"], candidate["message"])
        self.assertEqual((1, 1), (candidate["saves"], candidate["labs"]))
        markers = self._current_markers(candidate)
        self.assertEqual({"current-provider", "current-admin-observed", "current-pre-reset", "current-post-reset",
                          "current-pre-work", "current-complete", "current-cold"}, set(markers))
        for phase, marker in markers.items():
            with self.subTest(phase=phase):
                self.assertEqual(("current-successor17", "0.12.0", "5.0.20017"),
                                 (marker["stage"], marker["fixture_stage"], marker["mir_version"]))
        self.assertEqual("candidate17-reset-event-enforced", markers["current-post-reset"]["outcome"])
        for phase in (markers["current-complete"], markers["current-cold"]):
            event = phase["ordinary_events"][1]
            self.assertEqual((WORKER, False, 10, 11),
                             (event["name"], event["by_script"], event["completed_level"],
                              event["event_post_increment_level"]))
        self.assertEqual(["worker-speed-cap-ten/current-provider.json", "worker-speed-cap-ten/current-admin-observed.json",
                          "worker-speed-cap-ten/current-pre-reset.json", "worker-speed-cap-ten/current-post-reset.json",
                          "worker-speed-cap-ten/current-pre-work.json", "worker-speed-cap-ten/current-complete.json",
                          "worker-speed-cap-ten/current-cold.json", "worker-speed-cap-ten/current-cold.json"],
                         [candidate["files"][index]["path"] for index in range(1, len(candidate["files"]) + 1)])
        for opponent in ("scripted-finish", "preincrement-finish"):
            with self.subTest(opponent=opponent):
                adverse = self.current_state_result("candidate17", opponent)
                self.assertFalse(adverse["ok"])
                self.assertIn("scripted or non-level-ten current-state completion cannot satisfy ordinary cap-ten work",
                              adverse["message"])

    def test_current_successor17_complete_and_each_cold_share_the_full_observed_snapshot(self):
        required = {
            "case", "phase", "role", "fixture_stage", "mir_version", "mods", "active_mod_count", "cap", "stage", "target",
            "per_level_speed_effect", "formula", "research_time", "admin_intent", "pre_reset", "post_reset", "pre_work", "post_completion",
            "post_reset_player_bonus", "ordinary_native_completion_count", "level_eleven_start_count", "level_eleven_queue_attempt",
            "lab", "post_completion_hold_ticks", "reset_rows", "native_reset_events", "ordinary_events", "player", "foreign",
            "earned_above_cap", "completed_forces", "on_load_read_only",
        }

        def observed(value):
            if hasattr(value, "keys"):
                return {key: observed(value[key]) for key in value.keys()}
            return value

        candidate = self.current_state_result("candidate17")
        self.assertTrue(candidate["ok"], candidate["message"])
        rows = [candidate["markers"][index] for index in range(1, len(candidate["markers"]) + 1)]
        complete = [row for row in rows if row["phase"] == "current-complete"]
        colds = [row for row in rows if row["phase"] == "current-cold"]
        self.assertEqual((1, 2), (len(complete), len(colds)))
        complete = observed(complete[0])
        self.assertEqual(required, set(complete))
        self.assertEqual((False, False), (complete["on_load_read_only"], complete["level_eleven_queue_attempt"]["accepted"]))
        def assert_full_cold_snapshot(cold):
            cold = observed(cold)
            self.assertEqual(required, set(cold))
            self.assertEqual((True, False), (cold["on_load_read_only"], cold["level_eleven_queue_attempt"]["accepted"]))
            expected = dict(complete)
            expected["phase"] = "current-cold"
            expected["on_load_read_only"] = True
            self.assertEqual(expected, cold)

        for ordinal, cold in enumerate(colds, start=1):
            with self.subTest(cold=ordinal):
                assert_full_cold_snapshot(cold)

        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        marker = '  current_emit("cold", cold)\n'
        self.assertEqual(1, source.count(marker))
        with tempfile.TemporaryDirectory(prefix="mir5-current-completion-snapshot-queue-omission-") as work:
            omitted = Path(work) / "fixture_control.lua"
            omitted.write_text(source.replace(marker, '  cold.level_eleven_queue_attempt = nil\n' + marker), encoding="utf-8", newline="\n")
            adverse = self.current_state_result("candidate17", fixture_control=omitted)
        self.assertTrue(adverse["ok"], adverse["message"])
        adverse_rows = [adverse["markers"][index] for index in range(1, len(adverse["markers"]) + 1)]
        adverse_complete = [row for row in adverse_rows if row["phase"] == "current-complete"]
        adverse_colds = [row for row in adverse_rows if row["phase"] == "current-cold"]
        self.assertEqual((1, 2), (len(adverse_complete), len(adverse_colds)))
        complete = observed(adverse_complete[0])
        self.assertIn("level_eleven_queue_attempt", complete)
        for ordinal, cold in enumerate(adverse_colds, start=1):
            with self.subTest(omitted_cold=ordinal):
                self.assertNotIn("level_eleven_queue_attempt", cold)
                with self.assertRaises(AssertionError):
                    assert_full_cold_snapshot(cold)

    def test_current_observe_role_records_interleaved_public_boundaries_then_stops_before_reset(self):
        result = self.current_state_result("observe")
        self.assertFalse(result["ok"])
        self.assertIn("MIR_EXPECTED_CURRENT_OBSERVE16_TRACE_COMPLETE", result["message"])
        self.assertEqual((0, 0), (result["saves"], result["labs"]))
        markers = self._current_markers(result)
        self.assertEqual({"current-provider", "current-observe"}, set(markers))
        trace = markers["current-observe"]
        self.assertEqual(("MIR516SECapCallbackTraceV1", "reduced-synthetic-current-state-callback-observation", "0.9.0", "5.0.20016", 20),
                         (trace["trace_schema"], trace["role"], trace["fixture_stage"], trace["mir_version"], trace["active_mod_count"]))
        frames = [trace["frames"][index] for index in range(1, len(trace["frames"]) + 1)]
        expected_boundaries = ("before-admin", "after-prerequisites", "after-player-target", "after-player-queue", "after-player-progress",
                               "after-foreign-target", "after-foreign-queue", "after-foreign-progress", "after-earned-target", "after-earned-queue",
                               "after-admin", "passive-next-tick")
        self.assertEqual(expected_boundaries, tuple(frame["boundary"] for frame in frames))
        self.assertTrue(all(set(frame.keys()) == {"sequence", "boundary", "player", "foreign", "earned_above_cap"}
                            for frame in frames))
        frame_by_boundary = {frame["boundary"]: frame for frame in frames}
        self.assertTrue(all(frame_by_boundary["before-admin"][role]["unrelated_sentinel"]["enabled"]
                            for role in ("player", "foreign", "earned_above_cap")))
        self.assertTrue(all(not frame_by_boundary["after-prerequisites"][role]["unrelated_sentinel"]["enabled"]
                            for role in ("player", "foreign", "earned_above_cap")))
        self.assertEqual((10, False, 0), (frame_by_boundary["after-player-target"]["player"]["worker"]["level"],
                                            frame_by_boundary["after-player-target"]["player"]["worker"]["queue"]["current"],
                                            len(frame_by_boundary["after-player-target"]["player"]["worker"]["queue"]["queue"])))
        self.assertEqual((WORKER, 2, 0), (frame_by_boundary["after-player-queue"]["player"]["worker"]["queue"]["current"],
                                           len(frame_by_boundary["after-player-queue"]["player"]["worker"]["queue"]["queue"]),
                                           frame_by_boundary["after-player-queue"]["player"]["worker"]["queue"]["progress"]))
        self.assertEqual(.27, frame_by_boundary["after-player-progress"]["player"]["worker"]["queue"]["progress"])
        self.assertEqual((11, False, 0), (frame_by_boundary["after-foreign-target"]["foreign"]["worker"]["level"],
                                            frame_by_boundary["after-foreign-target"]["foreign"]["worker"]["queue"]["current"],
                                            len(frame_by_boundary["after-foreign-target"]["foreign"]["worker"]["queue"]["queue"])))
        self.assertEqual((AUTOMATION, 1, 0), (frame_by_boundary["after-foreign-queue"]["foreign"]["worker"]["queue"]["current"],
                                               len(frame_by_boundary["after-foreign-queue"]["foreign"]["worker"]["queue"]["queue"]),
                                               frame_by_boundary["after-foreign-queue"]["foreign"]["worker"]["queue"]["progress"]))
        self.assertEqual(.42, frame_by_boundary["after-foreign-progress"]["foreign"]["worker"]["queue"]["progress"])
        self.assertEqual((13, False, 0), (frame_by_boundary["after-earned-target"]["earned_above_cap"]["worker"]["level"],
                                            frame_by_boundary["after-earned-target"]["earned_above_cap"]["worker"]["queue"]["current"],
                                            len(frame_by_boundary["after-earned-target"]["earned_above_cap"]["worker"]["queue"]["queue"])))
        self.assertEqual(self._current_frame_signature(frame_by_boundary["after-admin"]["player"]),
                         self._current_frame_signature(frame_by_boundary["passive-next-tick"]["player"]))

        events = [trace["events"][index] for index in range(1, len(trace["events"]) + 1)]
        self.assertEqual(("on_research_started", "on_research_cancelled", "on_research_finished", "on_research_reversed", "on_technology_effects_reset"),
                         tuple(event["event"] for event in events))
        self.assertTrue(all(event["boundary"] == "after-admin" for event in events))
        self.assertEqual(tuple(range(1, len(frames) + len(events) + 1)),
                         tuple(sorted([frame["sequence"] for frame in frames] + [event["sequence"] for event in events])))
        self.assertEqual((True, False), (events[0]["by_script_present"], events[0]["by_script"]))
        self.assertEqual((True, True), (events[1]["by_script_present"], events[1]["by_script"]))
        self.assertFalse(events[-1]["by_script_present"])
        self.assertEqual((foreign := result["foreign"])["index"], events[-1]["force_index"])
        self.assertEqual(("MIR_EXPECTED_CURRENT_OBSERVE16_TRACE_COMPLETE", 0, False, False, False),
                         (trace["terminal"]["expected_token"], trace["terminal"]["explicit_reset_calls"],
                          trace["terminal"]["lab_created"], trace["terminal"]["save_requested"], trace["terminal"]["cold_requested"]))
        self.assertEqual(["worker-speed-cap-ten/current-provider.json", "worker-speed-cap-ten/current-observe.json"],
                         [result["files"][index]["path"] for index in range(1, len(result["files"]) + 1)])
        active_logs = [result["logs"][index] for index in range(1, len(result["logs"]) + 1)
                       if result["logs"][index].startswith("[MIR_ACTIVE_MODS] ")]
        self.assertEqual(1, len(active_logs))
        observed = active_logs[0]
        self.assertTrue(observed.startswith("[MIR_ACTIVE_MODS] "))
        self.assertEqual(sorted(f"{name}@{version}" for name, version in {
            **{row.partition("@")[0]: row.partition("@")[2] for row in ACTIVE_MODS},
            ACTIVE_MODS_OBSERVER: "0.9.0", "more-infinite-research": "5.0.20016",
        }.items()), observed.removeprefix("[MIR_ACTIVE_MODS] ").split("|"))

        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        observe = source.split("local function begin_current_observe()", 1)[1].split("local function begin_current_state", 1)[0]
        reset = source.split("local function begin_current_state(stage)", 1)[1].split("local function tick_current_state", 1)[0]
        shared = source.split("local function apply_current_admin_sequence", 1)[1].split("local function begin_current_observe", 1)[0]
        ordered = ("before(\"prerequisites\")", "set_current_prerequisites(player, false", "set_current_prerequisites(foreign, true", "set_current_prerequisites(earned, false",
                   "before(\"player-target\")", "player.research_queue = {owner, owner}", "player.research_progress = PARTIAL",
                   "before(\"foreign-target\")", "foreign.research_queue = {technology(foreign, PROBE)}", "foreign.research_progress = FOREIGN_PROGRESS",
                   "before(\"earned-target\")", "earned.research_queue = {}")
        self.assertEqual(sorted(shared.index(item) for item in ordered), [shared.index(item) for item in ordered])
        self.assertIn('apply_current_admin_sequence(player, foreign, earned, "current observe", {', observe)
        self.assertIn('apply_current_admin_sequence(player, foreign, earned, "current", nil)', reset)
        for write in ("set_current_prerequisites(", "research_queue =", "research_progress =", "owner.level,"):
            self.assertNotIn(write, observe)
            self.assertNotIn(write, reset)
        for forbidden in ("reset_technology_effects", "create_lab", "game.server_save", "cold_requested", "storage[CURRENT_KEY]",
                          "remote.", "script.raise_event", "enable_all_prototypes", "research_recursive"):
            self.assertNotIn(forbidden, observe)
        observe_control = (CURRENT_OBSERVE / "control.lua").read_text(encoding="utf-8")
        observe_data = (CURRENT_OBSERVE / "data-final-fixes.lua").read_text(encoding="utf-8")
        observe_settings = (CURRENT_OBSERVE / "settings-updates.lua").read_text(encoding="utf-8")
        self.assertIn('log("[MIR_ACTIVE_MODS] " .. text)', observe_control)
        self.assertNotIn('[MIR_ACTIVE_MODS]', observe_data)
        self.assertEqual('local fixture = require("__mir-fixture-mir5-worker-speed-cap-ten__/fixture_data_final")\nfixture.apply("current-observe16")\n', observe_data)
        self.assertEqual('local fixture = require("__mir-fixture-mir5-worker-speed-cap-ten__/fixture_settings")\nfixture.apply("current-observe16")\n', observe_settings)
        overflow = self.current_state_result("observe", "observe-event-overflow")
        self.assertFalse(overflow["ok"])
        self.assertIn("current observe event limit exceeded", overflow["message"])

    def test_current_state_controls_refuse_missing_or_extra_reset_and_boundary_mutation(self):
        for opponent, phrase in {
            "missing-prerequisite": "technology is absent: worker-robots-speed-9",
            "missing-reset-event": "native reset event was not delivered synchronously",
            "candidate-no-cap": "candidate player reset state differs",
            "fourth-reset": "observed reset outside the declared three-force boundary",
            "post-boundary-admin-write": "post-reset public state changed before ordinary lab work",
            "post-boundary-sentinel-write": "current pre-work player unrelated sentinel is enabled",
            "post-boundary-bonus-drift": "post-reset public state changed before ordinary lab work",
            "missing-ordinary-event": "ordinary native level-ten event differs",
            "await-eleven": "level eleven research started",
            "after-eleven": "level eleven research started",
            "scripted-finish": "scripted or non-level-ten current-state completion cannot satisfy ordinary cap-ten work",
            "preincrement-finish": "scripted or non-level-ten current-state completion cannot satisfy ordinary cap-ten work",
        }.items():
            with self.subTest(opponent=opponent):
                result = self.current_state_result("candidate", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        sentinel_setup = '  set_current_technology(force, SENTINEL, false, false, label)\n'
        self.assertEqual(1, source.count(sentinel_setup))
        with tempfile.TemporaryDirectory(prefix="mir5-current-sentinel-omission-") as work:
            omitted = Path(work) / "fixture_control.lua"
            omitted.write_text(source.replace(sentinel_setup, "", 1), encoding="utf-8", newline="\n")
            old_omission = self.current_state_result("candidate", fixture_control=omitted)
        self.assertFalse(old_omission["ok"])
        self.assertIn("current pre-reset player unrelated sentinel is enabled", old_omission["message"])
        old_omission_markers = self._current_markers(old_omission)
        self.assertTrue(all(old_omission_markers["current-provider"][role]["unrelated_sentinel"]["enabled"]
                            for role in ("player", "foreign", "earned_above_cap")))
        self.assertTrue(all(old_omission_markers["current-admin-observed"][role]["unrelated_sentinel"]["enabled"]
                            for role in ("player", "foreign", "earned_above_cap")))
        current = source.split("local function begin_current_state", 1)[1].split("function M.apply", 1)[0]
        for forbidden in ("game.create_force", "add_research", "worker_robots_speed_modifier =", "storage[KEY]",
                          "remote.", "script.raise_event", "enable_all_prototypes", "research_recursive"):
            self.assertNotIn(forbidden, current)
        self.assertIn('local roles = {"player", "foreign", "earned_above_cap"}', source)
        self.assertIn("state.reset_call_count ~= 3", source)

    def test_library_observer_accepts_only_the_wrapper_report_of_the_full_active_tuple(self):
        """Bind the producer's wrapper call site to the real selection reader."""
        tuple_text = "|".join(ACTIVE_MODS)
        fixture_log = lambda script, rows=tuple_text, loading="": (
            f"{loading}1.860 Script @__{ACTIVE_MODS_OBSERVER}__/{script}:3: [MIR_ACTIVE_MODS] {rows}\n"
        )
        with tempfile.TemporaryDirectory(prefix="mir5-cap-ten-active-mods-") as work:
            temporary = Path(work)
            selection = temporary / "selected.json"
            selection.write_text(json.dumps([
                {"name": row.partition("@")[0], "version": row.partition("@")[2]}
                for row in ACTIVE_MODS
            ]), encoding="utf-8")
            logs = {
                "accepted": fixture_log("data-final-fixes.lua"),
                "shared": fixture_log("fixture_data_final.lua"),
                "contradictory": fixture_log("data-final-fixes.lua", loading="1.859 Loading mod base 2.0.78 (data.lua)\n"),
                "missing_asset": fixture_log("data-final-fixes.lua", rows="|".join(
                    row for row in ACTIVE_MODS if row != "space-exploration-graphics-5@0.7.3")),
            }
            paths = {}
            for name, contents in logs.items():
                path = temporary / f"{name}.log"
                path.write_text(contents, encoding="utf-8", newline="\n")
                paths[name] = str(path)
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              . $env:MIR_TEST_LIBRARY_ACTIVATION
              $activation=[pscustomobject]@{selected=@(Get-Content -LiteralPath $env:MIR_TEST_SELECTION -Raw|ConvertFrom-Json)}
              $observer=$env:MIR_TEST_OBSERVER
              Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $env:MIR_TEST_ACCEPTED -ActiveModsObserver $observer|Out-Null
              function Assert-ObserverRefusal([string]$Path,[string]$Expected){
                $refused=$false
                try{Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $Path -ActiveModsObserver $observer|Out-Null}catch{
                  if(-not $_.Exception.Message.Contains($Expected)){throw ('unexpected observer refusal: '+$_.Exception.Message)}
                  $refused=$true
                }
                if(-not $refused){throw ('observer opponent accepted: '+$Path)}
              }
              Assert-ObserverRefusal $env:MIR_TEST_SHARED '[mir-library-loaded-observation]'
              Assert-ObserverRefusal $env:MIR_TEST_CONTRADICTORY '[mir-library-loaded-selection] Duplicate or contradictory native identity.'
              Assert-ObserverRefusal $env:MIR_TEST_MISSING_ASSET '[mir-library-loaded-selection] Actual mod names/versions differ from the profile.'
            '''
            environment = dict(os.environ, MIR_TEST_LIBRARY_ACTIVATION=str(ROOT / "tools/lib/compatibility/LibraryActivation.ps1"),
                               MIR_TEST_SELECTION=str(selection), MIR_TEST_OBSERVER=ACTIVE_MODS_OBSERVER,
                               MIR_TEST_ACCEPTED=paths["accepted"], MIR_TEST_SHARED=paths["shared"],
                               MIR_TEST_CONTRADICTORY=paths["contradictory"], MIR_TEST_MISSING_ASSET=paths["missing_asset"])
            result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
                                    cwd=ROOT, env=environment, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        shared = (FIXTURE / "fixture_data_final.lua").read_text(encoding="utf-8")
        self.assertNotIn('log("[MIR_ACTIVE_MODS] ', shared)
        for stage in (SOURCE, OLD_NEGATIVE, SUCCESSOR):
            wrapper = (stage / "data-final-fixes.lua").read_text(encoding="utf-8")
            self.assertIn('log("[MIR_ACTIVE_MODS] " .. tuple)', wrapper)

        observe_mods = tuple("mir-fixture-mir5-worker-speed-cap-ten@0.9.0" if row.startswith("mir-fixture-")
                             else "more-infinite-research@5.0.20016" if row.startswith("more-infinite-research@") else row
                             for row in ACTIVE_MODS)
        with tempfile.TemporaryDirectory(prefix="mir5-cap-ten-observe-control-") as work:
            temporary = Path(work)
            selection = temporary / "selected.json"
            selection.write_text(json.dumps([{"name": row.partition("@")[0], "version": row.partition("@")[2]}
                                              for row in observe_mods]), encoding="utf-8")
            observed = temporary / "observed.log"
            observed.write_text(f"1.860 Script @__{ACTIVE_MODS_OBSERVER}__/control.lua:3: [MIR_ACTIVE_MODS] {'|'.join(sorted(observe_mods))}\n",
                                encoding="utf-8", newline="\n")
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              . $env:MIR_TEST_LIBRARY_ACTIVATION
              $activation=[pscustomobject]@{selected=@(Get-Content -LiteralPath $env:MIR_TEST_SELECTION -Raw|ConvertFrom-Json)}
              Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $env:MIR_TEST_OBSERVED -ActiveModsObserver $env:MIR_TEST_OBSERVER -ActiveModsObserverScript 'control.lua'|Out-Null
            '''
            environment = dict(os.environ, MIR_TEST_LIBRARY_ACTIVATION=str(ROOT / "tools/lib/compatibility/LibraryActivation.ps1"),
                               MIR_TEST_SELECTION=str(selection), MIR_TEST_OBSERVER=ACTIVE_MODS_OBSERVER,
                               MIR_TEST_OBSERVED=str(observed))
            result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
                                    cwd=ROOT, env=environment, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_published15_old_negative_records_public_adverse_before_expected_failure(self):
        result = self.flow_result("old-negative")
        self.assertFalse(result["ok"]); self.assertIn("MIR_EXPECTED_OLD15_CAP_NOT_ENFORCED", result["message"]); self.assertEqual((0, 0), (result["saves"], result["labs"]))
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "preconditions", "old-negative"], [row["phase"] for row in markers])
        preconditions, adverse = markers[1], markers[2]
        self.assertEqual(("pre-assert-configuration", "source-seeded", "5.0.20015"),
                         (preconditions["source_snapshot_role"], preconditions["source_state"]["phase"], preconditions["source_state"]["source_mir"]))
        self.assertEqual(20, preconditions["active_mod_count"])
        self.assertEqual(("5.0.20015", "5.0.20015"), (adverse["pre_work"]["source_mir"], adverse["pre_work"]["active_mir"]))
        self.assertEqual((10, True, 2, .27), (adverse["player"]["level"], adverse["player"]["enabled"], len(adverse["player"]["queue"]["queue"]), adverse["player"]["queue"]["progress"]))
        self.assertEqual((11, False, "automation", .42), (adverse["foreign"]["level"], adverse["foreign"]["enabled"], adverse["foreign"]["queue"]["current"], adverse["foreign"]["queue"]["progress"]))
        self.assertEqual((13, True, False), (adverse["earned_above_cap"]["level"], adverse["earned_above_cap"]["enabled"], adverse["earned_above_cap"]["queue"]["current"]))
        self.assertFalse(adverse["lab"]["present"]); self.assertEqual(0, adverse["ordinary_native_completion_count"])
        self.assertTrue(all(result[force]["technologies"][UNRELATED]["enabled"] is False
                            for force in ("player", "foreign", "earned")))
        self.assertNotIn("cap_owner", {key: adverse[key] for key in adverse})
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/preconditions.json", "worker-speed-cap-ten/old-negative.json"], [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])

    def test_published15_cap_zero_source_producer_records_validated_frames_and_read_only_cold(self):
        result = self.source_producer_result(cold=True)
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((0, 0), (result["saves"], result["labs"]))
        rows = [result["markers"][index] for index in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source-producer", "source-producer-cold"], [row["phase"] for row in rows])
        def observed(value):
            if hasattr(value, "keys"):
                return {key: observed(value[key]) for key in value.keys()}
            return value
        source, cold = (observed(row) for row in rows)
        self.assertEqual(("published15-cap-zero-source-producer", "0.13.0", "5.0.20015", 0, 20, True),
                         (source["role"], source["fixture_stage"], source["mir_version"], source["cap"],
                          source["active_mod_count"], source["foreign_queue_admitted"]))
        self.assertEqual("post-final-producer-validation", source["source_snapshot_role"])
        self.assertEqual(("source-producer-ready", "5.0.20015"),
                         (source["source_state"]["phase"], source["source_state"]["source_mir"]))
        expected_frames = {
            "player": (10, False, True, False, 0, .65, (WORKER, WORKER), .27),
            "foreign": (11, False, False, False, 0, 1.3, (AUTOMATION,), .42),
            "earned_above_cap": (13, False, True, False, 0, 2.6, (), 0),
        }
        expected_researched = {
            "player": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: False, ELECTRICITY: False, AUTOMATION: False},
            "foreign": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: True, ELECTRICITY: True, AUTOMATION: False},
            "earned_above_cap": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: False, ELECTRICITY: False, AUTOMATION: False},
        }
        expected_levels = {PREDECESSOR: PREDECESSOR_LEVEL, DEEP_SCIENCE: 1, AUTOMATION_SCIENCE: 1, ELECTRICITY: 1, AUTOMATION: 1}
        for role, expected in expected_frames.items():
            with self.subTest(role=role):
                frame = source["worker_frames"][role]
                queue = frame["queue"]
                self.assertEqual(expected, (frame["level"], frame["researched"], frame["enabled"], frame["visible"],
                                            frame["saved_progress"], frame["bonus"],
                                            tuple(queue["queue"][index] for index in range(1, len(queue["queue"]) + 1)),
                                            queue["progress"]))
                flags = source["prerequisite_flags"][role]
                self.assertEqual({PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION}, set(flags.keys()))
                for name, researched in expected_researched[role].items():
                    value = flags[name]
                    self.assertEqual((researched, True, expected_levels[name], True),
                                     (value["researched"], value["enabled"], value["level"], value["valid"]),
                                     f"{role}/{name}")
        expected_cold = dict(source)
        expected_cold["phase"] = "source-producer-cold"
        expected_cold["source_snapshot_role"] = "same-version-source-cold-read-only"
        expected_cold["on_load_read_only"] = True
        self.assertEqual(expected_cold, cold)
        self.assertEqual(["worker-speed-cap-ten/source-producer.json", "worker-speed-cap-ten/source-producer-cold.json"],
                         [result["files"][index]["path"] for index in range(1, len(result["files"]) + 1)])

    def test_source_producer_refuses_post_final_flag_or_queue_drift_before_accepted_marker(self):
        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        marker = '  source_producer_marker("source-producer", state)\n'
        self.assertEqual(1, source.count(marker))
        opponents = {
            "cleared-direct-flag": ('  technology(player, PREDECESSOR).researched = false\n' + marker,
                                    "source-producer player named flag differs: worker-robots-speed-9"),
            "changed-unchecked-player-automation": ('  technology(player, PROBE).researched = true\n' + marker,
                                                      "source-producer player named flag differs: automation"),
            "changed-predecessor-level": ('  technology(player, PREDECESSOR).level = 8\n' + marker,
                                            "source-producer player named flag differs: worker-robots-speed-9"),
            "changed-player-queue": ('  player.research_queue = {}\n' + marker,
                                     "source-producer scripted player seed differs"),
        }
        for name, (replacement, phrase) in opponents.items():
            with self.subTest(opponent=name), tempfile.TemporaryDirectory(prefix=f"mir5-source-producer-{name}-") as work:
                mutated = Path(work) / "fixture_control.lua"
                mutated.write_text(source.replace(marker, replacement), encoding="utf-8", newline="\n")
                result = self.source_producer_result(fixture_control=mutated)
            self.assertFalse(result["ok"])
            self.assertIn(phrase, result["message"])
            self.assertEqual((0, 0, 0), (len(result["markers"]), len(result["files"]), result["saves"]))
            self.assertEqual(0, result["labs"])

    def test_successor_cap_keeps_one_ordinary_tail_ten_completion_then_two_cold_reads(self):
        result = self.flow_result(); self.assertTrue(result["ok"], result["message"]); self.assertEqual((1, 1), (result["saves"], result["labs"]))
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "preconditions", "pre-work", "complete", "cold", "cold"], [row["phase"] for row in markers])
        self.assertEqual(("5.0.20015", "5.0.20016"), (markers[0]["mir_version"], markers[2]["mir_version"]))
        complete = markers[3]
        self.assertEqual((1, 0), (complete["ordinary_native_completion_count"], complete["level_eleven_start_count"]))
        self.assertEqual((WORKER, False, 10, 11), (complete["ordinary_events"][1]["name"], complete["ordinary_events"][1]["by_script"],
                                                    complete["ordinary_events"][1]["completed_level"], complete["ordinary_events"][1]["event_post_increment_level"]))
        self.assertEqual((WORKER, False), (complete["ordinary"][1]["name"], complete["ordinary"][1]["by_script"]))
        self.assertEqual((2, 1, 0), (len(markers[0]["player"]["queue"]["queue"]), len(markers[2]["player"]["queue"]["queue"]), len(complete["player"]["queue"]["queue"])))
        self.assertEqual(3600, complete["player"]["research_unit_energy"])
        self.assertEqual(set(PACKS), set(complete["post_completion"]["lab"]["input_by_name"].keys()))
        self.assertTrue(all(complete["post_completion"]["lab"]["input_by_name"][name] > 0 for name in PACKS))
        post_input = complete["post_completion"]["lab"]["input_by_name"]
        end_input = complete["post_completion"]["end_lab"]["input_by_name"]
        self.assertEqual({name: post_input[name] for name in PACKS}, {name: end_input[name] for name in PACKS})
        self.assertEqual((False, 2), (complete["level_eleven_queue_attempt"]["accepted"], complete["post_completion_hold_ticks"]))
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/preconditions.json", "worker-speed-cap-ten/pre-work.json", "worker-speed-cap-ten/complete.json", "worker-speed-cap-ten/cold.json", "worker-speed-cap-ten/cold.json"], [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])

    def test_source_and_successor_controls_refuse_adverse_states(self):
        source_tick = self.flow_result("successor", "source-tick"); self.assertFalse(source_tick["ok"]); self.assertIn("source create-only stage received an actor tick", source_tick["message"])
        admin = self.flow_result("successor", "source-admin"); self.assertTrue(admin["ok"]); self.assertEqual("scripted-prerequisite", admin["state"]["scripted_administrative_events"][1]["setup_class"])
        electricity_admin = self.flow_result("successor", "source-admin-electricity")
        self.assertTrue(electricity_admin["ok"])
        self.assertEqual(ELECTRICITY, electricity_admin["state"]["scripted_administrative_events"][1]["name"])
        preinit = self.flow_result("successor", "preinit-unrelated"); self.assertTrue(preinit["ok"]); self.assertIsNone(preinit["state"])
        for opponent, phrase in {"source-worker": "source stage observed non-administrative research completion", "missing-electricity": "foreign automation electricity prerequisite is absent", "missing-predecessor": "player worker prerequisite is not researched: worker-robots-speed-9", "missing-deep": "player worker prerequisite is not researched: se-deep-space-science-pack-1", "skip-caps": "cap-ten did not retain only current level-ten work", "partial-drift": "cap-ten did not retain only current level-ten work", "foreign-reenabled": "foreign disabled sentinel differs", "scripted-finish": "scripted or non-level-ten completion cannot satisfy ordinary cap-ten work", "preincrement-finish": "scripted or non-level-ten completion cannot satisfy ordinary cap-ten work", "await-eleven": "level eleven research started", "after-eleven": "level eleven research started", "wrong-runtime-energy": "worker research-unit contract differs"}.items():
            with self.subTest(opponent=opponent):
                result = self.flow_result("successor", opponent); self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])
        control = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        on_load = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
        self.assertNotIn("game", on_load); self.assertNotIn("storage", on_load)

    def test_precondition_observer_precedes_the_known_missing_predecessor_assertion(self):
        result = self.flow_result("successor", "missing-predecessor")
        self.assertFalse(result["ok"])
        self.assertIn("player worker prerequisite is not researched: worker-robots-speed-9", result["message"])
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "preconditions"], [row["phase"] for row in markers])
        preconditions = markers[1]
        self.assertEqual(("pre-assert-configuration", "source-seeded", "5.0.20015"),
                         (preconditions["source_snapshot_role"], preconditions["source_state"]["phase"], preconditions["source_state"]["source_mir"]))
        self.assertEqual(False, preconditions["prerequisite_flags"]["player"][PREDECESSOR]["researched"])
        self.assertEqual(True, preconditions["prerequisite_flags"]["foreign"][PREDECESSOR]["researched"])
        self.assertEqual(True, preconditions["prerequisite_flags"]["earned_above_cap"][PREDECESSOR]["researched"])
        self.assertEqual(20, preconditions["active_mod_count"])
        self.assertEqual("0.7.57", preconditions["mods"]["space-exploration"])
        self.assertEqual("0.6.0", preconditions["mods"]["mir-fixture-mir5-worker-speed-cap-ten"])
        self.assertEqual("5.0.20016", preconditions["mods"]["more-infinite-research"])
        expected_researched = {
            "player": {PREDECESSOR: False, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: False, ELECTRICITY: False, AUTOMATION: False},
            "foreign": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: True, ELECTRICITY: True, AUTOMATION: False},
            "earned_above_cap": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: False, ELECTRICITY: False, AUTOMATION: False},
        }
        expected_levels = {PREDECESSOR: PREDECESSOR_LEVEL, DEEP_SCIENCE: 1, AUTOMATION_SCIENCE: 1, ELECTRICITY: 1, AUTOMATION: 1}
        for force_name in ("player", "foreign", "earned_above_cap"):
            flags = preconditions["prerequisite_flags"][force_name]
            self.assertEqual({PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION}, set(flags.keys()))
            for technology_name in (PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION):
                value = flags[technology_name]
                self.assertEqual((expected_researched[force_name][technology_name], True, expected_levels[technology_name], True),
                                 (value["researched"], value["enabled"], value["level"], value["valid"]),
                                 f"{force_name}/{technology_name}")
        self.assertEqual((10, 11, 13), (preconditions["worker_frames"]["player"]["level"],
                                        preconditions["worker_frames"]["foreign"]["level"],
                                        preconditions["worker_frames"]["earned_above_cap"]["level"]))
        self.assertEqual(2, len(result["logs"]))
        self.assertTrue(result["logs"][2].startswith("[MIR_WORKER_SPEED_CAP_TEN phase=preconditions] "))
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/preconditions.json"],
                         [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])


    def test_producer_transition_roles_pin_their_distinct_full_protocol(self):
        for folder, version, mir in ((PRODUCER_OLD15, "0.14.0", "5.0.20015"),
                                     (PRODUCER_SUCCESSOR17, "0.15.0", "5.0.20017")):
            with self.subTest(role=folder.name):
                info = json.loads((folder / "info.json").read_text(encoding="utf-8"))
                self.assertEqual((ACTIVE_MODS_OBSERVER, version, "2.0"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(["base = 2.0.77", "space-exploration = 0.7.57", "more-infinite-research = " + mir], info["dependencies"])
                result = self.data_result(folder.name)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(10, result["raw"]["int-setting"][CAP]["default_value"])
                self.assertEqual("infinite", result["raw"]["technology"][WORKER]["max_level"])
                self.assertEqual(1, len(result["rows"]))
                self.assertEqual((version, mir), (result["mods"][ACTIVE_MODS_OBSERVER], result["mods"]["more-infinite-research"]))

    def test_producer_successor_preserves_source_and_finishes_then_reads_twice_cold(self):
        result = self.producer_transition_result()
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((1, 1, True), (result["labs"], result["saves"], result["cold_storage_unchanged"]))
        state = result["state"]
        self.assertEqual((True, "5.0.20015", "complete", 1, 0),
                         (state["source_producer"], state["source_mir"], state["phase"],
                          state["ordinary_native_completion_count"], state["level_eleven_start_count"]))
        self.assertEqual(("source-producer-ready", "5.0.20015", "producer-successor17"),
                         (state["producer_origin"]["phase"], state["producer_origin"]["source_mir"], state["producer_origin"]["role"]))
        self.assertEqual((11, False, 1.3), (result["player"]["technologies"][WORKER]["level"],
                         result["player"]["technologies"][WORKER]["enabled"], result["player"]["worker_robots_speed_modifier"]))
        self.assertEqual((False, 1.3, .42), (result["foreign"]["technologies"][WORKER]["enabled"],
                         result["foreign"]["worker_robots_speed_modifier"], result["foreign"]["research_progress"]))
        self.assertEqual((13, False, 2.6), (result["earned"]["technologies"][WORKER]["level"],
                         result["earned"]["technologies"][WORKER]["enabled"], result["earned"]["worker_robots_speed_modifier"]))
        rows = self._lua_rows(result["markers"])
        self.assertEqual(["source-producer", "preconditions", "pre-work", "complete", "cold", "cold"], [row["phase"] for row in rows])
        for row in rows[2:]:
            self.assertEqual(("producer-successor17", "0.15.0", "5.0.20015", "5.0.20017", 20),
                             (row["role"], row["fixture_stage"], row["source_mir"], row["active_mir"], row["active_mod_count"]))
            self.assertEqual(("source-producer-ready", "5.0.20015", "producer-successor17"),
                             (row["source_origin"]["phase"], row["source_origin"]["source_mir"], row["source_origin"]["role"]))
        self.assertEqual((10, .27, 1), (rows[2]["player"]["level"], rows[2]["player"]["queue"]["progress"], len(rows[2]["player"]["queue"]["queue"])))
        self.assertEqual((1, False, 10, 11), (rows[3]["ordinary_native_completion_count"],
                         rows[3]["ordinary_events"][1]["by_script"], rows[3]["ordinary_events"][1]["completed_level"],
                         rows[3]["ordinary_events"][1]["event_post_increment_level"]))
        self.assertTrue(all(row["on_load_read_only"] for row in rows[4:]))
        legacy = self.flow_result()
        self.assertTrue(legacy["ok"], legacy["message"])
        for row in self._lua_rows(legacy["markers"]):
            self.assertIsNone(row["role"])
            self.assertIsNone(row["source_origin"])

    def test_producer_successor_refuses_incompatible_origin_before_lab_or_save(self):
        opponents = ("wrong-phase", "wrong-source", "not-producer", "absent-state", "wrong-player-index", "missing-force",
                     "aliased-forces", "fractional-index", "wrong-force-name", "no-queue-admission", "prior-ordinary",
                     "prior-start", "ordinary-history", "missing-ordinary-history", "missing-admin-history", "prior-lab",
                     "prior-pre-work", "prior-completion", "prior-deadline", "prior-queue-attempt", "prior-origin", "wrong-saved-bonus")
        for opponent in opponents:
            with self.subTest(opponent=opponent):
                result = self.producer_transition_result(opponent=opponent)
                self.assertFalse(result["ok"], opponent)
                self.assertIn("producer source", result["message"])
                self.assertTrue(result["rejected_fixture_state_unchanged"], opponent)
                self.assertEqual((0, 0), (result["labs"], result["saves"]))

    def test_producer_successor_retains_admin_history_and_real_event_guards(self):
        admitted = self.producer_transition_result(opponent="admin-history")
        self.assertTrue(admitted["ok"], admitted["message"])
        self.assertEqual((1, "scripted-prerequisite"), (len(admitted["state"]["scripted_administrative_events"]),
                         admitted["state"]["scripted_administrative_events"][1]["setup_class"]))
        for opponent in ("init", "skip-caps", "missing-prerequisite", "changed-progress", "changed-bonus",
                         "enabled-foreign", "enabled-earned", "level-eleven-start", "scripted-completion", "preincrement-completion", "cold-origin"):
            with self.subTest(opponent=opponent):
                result = self.producer_transition_result(opponent=opponent)
                self.assertFalse(result["ok"], opponent)
        wrong = self.producer_transition_result(opponent="cold-write")
        self.assertTrue(wrong["ok"], wrong["message"])
        self.assertFalse(wrong["cold_storage_unchanged"], "The cold-state invariant must detect a forbidden saved-state write")

    def test_producer_saved_work_is_validated_at_each_transition_output(self):
        for prefix, expected_saves in (("saved-", 0), ("late-saved-", 0), ("cold-saved-", 1)):
            for role in ("player", "foreign", "earned"):
                with self.subTest(stage=prefix, force=role):
                    result = self.producer_transition_result(opponent=prefix + role)
                    self.assertFalse(result["ok"], prefix + role)
                    self.assertIn("saved progress", result["message"])
                    self.assertEqual(expected_saves, result["saves"])
                    if prefix == "saved-":
                        self.assertEqual(0, result["labs"])
                        self.assertTrue(result["rejected_fixture_state_unchanged"])

    def test_producer_admission_state_guard_detects_a_forbidden_early_write(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        call = "      assert_ready_producer_source(state)\n"
        self.assertEqual(1, original.count(call))
        mutant = original.replace(call, "      state.forbidden_early_write = true\n" + call, 1)
        temporary_parent = ROOT / "build" / "tmp"
        temporary_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="producer-admission-mutant-", dir=temporary_parent) as directory:
            self.assertTrue(Path(directory).resolve().is_relative_to(temporary_parent.resolve()))
            path = Path(directory) / "fixture_control.lua"
            path.write_text(mutant, encoding="utf-8")
            result = self.producer_transition_result(opponent="wrong-source", fixture_control=path)
        self.assertFalse(result["ok"])
        self.assertEqual((0, 0), (result["labs"], result["saves"]))
        self.assertFalse(result["rejected_fixture_state_unchanged"],
                         "The admission invariant must detect an actual forbidden fixture-state write")

    def test_producer_old15_records_the_exact_opposing_outcome_without_labs(self):
        result = self.producer_transition_result(mode="old")
        self.assertFalse(result["ok"])
        self.assertIn("MIR_EXPECTED_OLD15_CAP_NOT_ENFORCED", result["message"])
        self.assertEqual((0, 0), (result["labs"], result["saves"]))
        rows = self._lua_rows(result["markers"])
        self.assertEqual(["source-producer", "preconditions", "old-negative"], [row["phase"] for row in rows])
        row = rows[-1]
        self.assertEqual(("producer-old15", "0.14.0", "5.0.20015", "5.0.20015"),
                         (row["role"], row["fixture_stage"], row["source_mir"], row["active_mir"]))
        self.assertEqual((10, 2, .27, .65), (row["player"]["level"], len(row["player"]["queue"]["queue"]),
                         row["player"]["queue"]["progress"], row["player"]["bonus"]))
        self.assertEqual((False, 1.3, True, 2.6), (row["foreign"]["enabled"], row["foreign"]["bonus"],
                         row["earned_above_cap"]["enabled"], row["earned_above_cap"]["bonus"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args(); sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WorkerSpeedCapTenNativeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

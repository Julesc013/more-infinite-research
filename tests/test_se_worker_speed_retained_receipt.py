"""Frozen documentary checks for the accepted SE worker-speed native receipt.

This checks the public *summary's* internal contracts, not the private native
bodies, independent rehashing of actual ZIP bytes, gameplay or release qualification. Do not
convert this host check into a replacement for the independently reviewed native
sequence or the remaining worker-cargo/reporter migration gates.
"""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ROOT / "spec/evidence/se-worker-speed-provider-cap-successor-gunmetal-r03.json"


def check_receipt(r: dict) -> None:
    """Reject drift in the bounded, already-accepted result's declared claims."""
    def require(predicate: bool, label: str) -> None:
        if not predicate:
            raise AssertionError(label)

    require(r["kind"] == "MIRSEProviderCapSuccessorAcceptedV1"
            and r["status"] == "accepted_bounded_native_sequence", "historical status")
    require(r["engine"]["version"] == "2.0.77"
            and r["selection"]["space-exploration"] == "0.7.57"
            and r["selection"]["selected_mods"] == 20, "frozen source closure")
    require(r["player_archive"]["version"] == "5.0.20018"
            and r["player_archive"]["private_only"] is True, "private candidate identity")

    require(r["player_archive"]["sha256"] == "7046DDBD02ECF99BEA4853DBB8C0C4AD58E2457B8917808F4AD3114B6560E87A"
            and r["player_archive"]["bytes"] == 1052778,
            "private candidate archive custody")

    actual = r["actual"]
    exits = actual["stage_exits"]
    require(actual["native_processes"] == 4
            and len(actual["owned_pids"]) == 4
            and len(set(actual["owned_pids"])) == 4
            and exits == {"old": 1, "candidate": 137, "cold1": 0, "cold2": 0},
            "four-stage native exit accounting")
    require(actual["native_ordinary_completions"] == 1
            and actual["ordinary_event"]["name"] == "worker-robots-speed-10"
            and actual["ordinary_event"]["by_script"] is False
            and actual["ordinary_event"]["completed_level"] == 10
            and actual["ordinary_event"]["event_post_increment_level"] == 11,
            "one ordinary worker-speed completion")
    require(actual["pre_work_tick"] < actual["ordinary_event"]["tick"]
            and actual["ordinary_event"]["tick"] < actual["closed_tick"]
            and actual["closed_tick"] - actual["ordinary_event"]["tick"] >= 2
            and actual["closed_hold_elapsed_ticks"] == 2
            and actual["level_eleven_starts"] == 0, "post-completion hold and cap")
    require(abs(actual["player_bonus_before"] - 5.0) < 1e-9
            and abs(actual["player_bonus_after"] - 5.65) < 1e-9
            and abs((actual["player_bonus_after"] - actual["player_bonus_before"]) - .65) < 1e-9,
            "earned bonus continuity")
    require(actual["science_tool_types"] == 8
            and actual["science_consumed_each"] == 2336, "recorded science debit")

    closed = actual["player_worker_after"]
    require(closed == {"level": 11, "researched": False, "enabled": False,
                       "visible": True, "saved": 0}, "closed worker state")
    require(actual["observed_forces"] == 3
            and actual["completed_prerequisites_per_force"] == 196
            and actual["unrelated_force_frames_preserved"] is True
            and actual["closed_frames_bonuses_queues_partials_lab_inventory_and_event_count_preserved"] is True,
            "closed unrelated and paid-work preservation claims")

    protected = r["protected"]
    require(protected["source"]["sha256"] == "7FAD213E47A0AB6B2660FE67C4047213B5048063A5F571C82321EBF148D243C7"
            and protected["source"]["bytes"] == 833284
            and protected["candidate"]["sha256"] == "C34EEFC45055D467E6FE3F68C5C60070D61A775F5AFB3C10CBF027E449155825"
            and protected["candidate"]["bytes"] == 854638
            and protected["source"]["sha256"] != protected["candidate"]["sha256"]
            and protected["source"]["crc_entries"] == 55
            and protected["candidate"]["crc_entries"] == 55, "source/successor ZIP custody")
    require(actual["cold_processes"] == 2
            and actual["both_cold_inputs_equal_same_protected_successor"] is True,
            "two cold inputs of same successor")
    custody = r["custody"]
    require(custody["readback_rehashed_bodies"] == 109
            and custody["hash_mismatches"] == 0
            and custody["protected_source_unchanged"] is True
            and custody["library_restored"] is True
            and custody["cleanup_errors"] == []
            and custody["remaining_factorio"] == 0, "reported independent custody")

    require(r["release_published"] is False
            and r["published_assets_changed"] is False
            and r["stable_acceptance"] is False, "historical prerelease boundary")
    remaining = r["not_established"]
    require("worker-cargo capacity or cap repair" in remaining
            and "original reporter reproduction" in remaining
            and "release or stable acceptance" in remaining, "unqualified obligations")


class SERetainedNativeReceiptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))

    def test_frozen_retained_successor_receipt_is_consistent(self) -> None:
        check_receipt(self.receipt)

    def test_mutants_refuse_scripted_or_premature_completion(self) -> None:
        for field, value, message in (
            ("by_script", True, "ordinary worker-speed completion"),
            ("event_post_increment_level", 10, "ordinary worker-speed completion"),
        ):
            bad = deepcopy(self.receipt)
            bad["actual"]["ordinary_event"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(AssertionError, message):
                check_receipt(bad)
        early = deepcopy(self.receipt)
        early["actual"]["closed_tick"] = early["actual"]["ordinary_event"]["tick"]
        with self.assertRaisesRegex(AssertionError, "post-completion hold"):
            check_receipt(early)

    def test_mutants_refuse_replaced_archive_digests_and_sizes(self) -> None:
        # Mutate to another syntactically valid 64-hex digest: inequality alone
        # must never pass as an immutable-archive identity guard.
        for group, label in (
            ("source", "source/successor ZIP custody"),
            ("candidate", "source/successor ZIP custody"),
            ("player_archive", "private candidate archive custody"),
        ):
            bad_digest = deepcopy(self.receipt)
            target = (bad_digest["player_archive"] if group == "player_archive"
                      else bad_digest["protected"][group])
            original_digest = target["sha256"]
            target["sha256"] = ("0" if original_digest[0] != "0" else "1") + original_digest[1:]
            with self.subTest(group=group, mutation="sha256"), self.assertRaisesRegex(AssertionError, label):
                check_receipt(bad_digest)

            bad_size = deepcopy(self.receipt)
            target = (bad_size["player_archive"] if group == "player_archive"
                      else bad_size["protected"][group])
            target["bytes"] += 1
            with self.subTest(group=group, mutation="bytes"), self.assertRaisesRegex(AssertionError, label):
                check_receipt(bad_size)

    def test_mutants_refuse_single_cold_and_stable_promotion(self) -> None:
        mutations = (
            (lambda r: r["actual"].update(cold_processes=1), "two cold inputs"),
            (lambda r: r["actual"]["stage_exits"].update(cold2=1), "four-stage native"),
            (lambda r: r["custody"].update(hash_mismatches=1), "reported independent custody"),
            (lambda r: r.update(stable_acceptance=True), "historical prerelease"),
        )
        for mutate, message in mutations:
            bad = deepcopy(self.receipt)
            mutate(bad)
            with self.subTest(message=message), self.assertRaisesRegex(AssertionError, message):
                check_receipt(bad)


if __name__ == "__main__":
    unittest.main()

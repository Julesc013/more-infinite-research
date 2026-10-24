"""Opposing controls for the package-excluded modern-catalogue oracle."""
import contextlib
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import recover_modern_catalogue as catalogue


def _json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def _write_json(path: Path, value) -> None:
    path.write_bytes(_json_bytes(value))


def _record(root: Path, path: Path) -> dict:
    return {
        "path": path.relative_to(root).as_posix(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest().upper(),
        "bytes": path.stat().st_size,
    }


def _set_profile_receipt(capture_root: Path, profile: Path) -> None:
    receipt_path = capture_root / "result.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    receipt["profile_input"] = {
        "path": str(profile),
        "sha256": hashlib.sha256(profile.read_bytes()).hexdigest().upper(),
    }
    _write_json(receipt_path, receipt)


def _baseline_raw() -> dict:
    return {
        "technology": {
            "automation": {
                "type": "technology", "name": "automation", "effects": [],
                "unit": {"count": 1, "time": 1, "ingredients": [["automation-science-pack", 1]]},
            },
        },
        "recipe": {
            "foreign-recipe": {
                "type": "recipe", "name": "foreign-recipe", "allow_productivity": False,
            },
        },
    }


def _baseline_settings() -> dict:
    return {
        "bool-setting": {
            "foreign-setting": {
                "type": "bool-setting", "name": "foreign-setting", "setting_type": "startup", "default_value": True,
            },
        },
    }


def _maximum_level_policy() -> dict:
    return {
        "type": "mod-data",
        "name": "more-infinite-research-maximum-level-policy",
        "data_type": "more-infinite-research.maximum-level-policy-v3",
        "data": {
            "schema": 3,
            "bindings": [
                {
                    "technology": "recipe-prod-research_alpha-1",
                    "setting_name": "ips-max-level-research_alpha",
                    "source": "generated-stream",
                    "operation": "emit",
                    "semantic": {"family_id": "research_alpha", "stream_id": "research_alpha"},
                    "provenance": {"manifest_id": "research_alpha"},
                },
                {
                    "technology": "native-owner-productivity",
                    "setting_name": "ips-max-level-research_owner",
                    "source": "native-owner",
                    "operation": "preserve_native_owner",
                    "semantic": {"family_id": "research_owner", "stream_id": "research_owner"},
                    "provenance": {"manifest_id": "research_owner"},
                },
            ],
        },
    }


def _published_raw() -> dict:
    raw = _baseline_raw()
    raw["technology"].update({
        "recipe-prod-research_alpha-1": {
            "type": "technology", "name": "recipe-prod-research_alpha-1", "prerequisites": ["automation"],
            "max_level": "infinite", "unit": {"count_formula": "100 * L", "time": 30,
                                                "ingredients": [["automation-science-pack", 1]]},
            "effects": [{"type": "change-recipe-productivity", "recipe": "foreign-recipe", "change": 0.1}],
        },
        "worker-robots-storage-4": {
            "type": "technology", "name": "worker-robots-storage-4", "prerequisites": ["automation"],
            "max_level": "infinite", "unit": {"count_formula": "200 * L", "time": 30,
                                                "ingredients": [["automation-science-pack", 1]]},
            "effects": [{"type": "worker-robot-storage", "modifier": 1}],
        },
    })
    raw["recipe"]["foreign-recipe"]["allow_productivity"] = True
    raw["shortcut"] = {
        "mir-research-browser": {"type": "shortcut", "name": "mir-research-browser", "action": "lua"},
    }
    raw["mod-data"] = {
        "more-infinite-research-compiler-evidence": {
            "type": "mod-data", "name": "more-infinite-research-compiler-evidence", "data_type": "private",
            "data": {"compiler": "captured"},
        },
        "more-infinite-research-maximum-level-policy": _maximum_level_policy(),
    }
    return raw


def _published_settings() -> dict:
    settings = _baseline_settings()
    settings["bool-setting"]["mir-browser"] = {
        "type": "bool-setting", "name": "mir-browser", "setting_type": "runtime-per-user", "default_value": True,
    }
    settings["int-setting"] = {
        "ips-max-level-research_alpha": {
            "type": "int-setting", "name": "ips-max-level-research_alpha", "setting_type": "startup",
            "default_value": 99, "minimum_value": 1, "maximum_value": 1000,
        },
    }
    return settings


def _capture(root: Path, raw: dict, settings: dict, *, published: bool,
             target: str = "f210", mir_version: str | None = None) -> Path:
    family, engine_version = ("2.0", "2.0.77") if target == "f200" else ("2.1", "2.1.23")
    mir_version = mir_version or "4.7." + target[1:] + "00"
    root.mkdir(parents=True)
    external = root.parent / "external"
    external.mkdir(exist_ok=True)
    engine = external / "factorio.exe"
    profile = external / "profile.json"
    base = external / "base-info.json"
    mir = external / ("more-infinite-research_" + mir_version + ".zip")
    for path, content in ((engine, b"synthetic engine"), (profile, b"synthetic shared profile\n"),
                          (base, b"synthetic base"), (mir, b"synthetic published MIR")):
        if not path.exists():
            path.write_bytes(content)
    data_path, settings_path, selection_path = (
        root / "data-raw-dump.json", root / "mod-settings-dump.json", root / "selection.json")
    _write_json(data_path, raw)
    _write_json(settings_path, settings)
    mods = [{"name": "base", "version": engine_version, "enabled": True}]
    selected = [{"name": "base", "version": engine_version, "builtin": True,
                 "sha256": hashlib.sha256(base.read_bytes()).hexdigest().upper()}]
    loaded = ["base@" + engine_version]
    if published:
        mods.append({"name": "more-infinite-research", "version": mir_version, "enabled": True})
        selected.append({"name": "more-infinite-research", "version": mir_version, "builtin": False,
                         "sha256": hashlib.sha256(mir.read_bytes()).hexdigest().upper()})
        loaded.append("more-infinite-research@" + mir_version)
    _write_json(selection_path, {"mods": mods})
    result = {
        "status": "completed-data-stage-observation-only",
        "process": {"passed": True, "timed_out": False, "exit_code": 0},
        "engine": {"sha256": hashlib.sha256(engine.read_bytes()).hexdigest().upper(),
                   "base_version": engine_version, "factorio_version": family},
        "profile_input": {"path": str(profile), "sha256": hashlib.sha256(profile.read_bytes()).hexdigest().upper()},
        "generated_selection": {**_record(root, selection_path), "mods": mods},
        "selected_archives": selected,
        "loaded_selection": loaded,
        "dumps": {"data_raw": _record(root, data_path), "mod_settings": _record(root, settings_path)},
        "mir_archive": ({"name": "more-infinite-research", "version": mir_version,
                         "sha256": hashlib.sha256(mir.read_bytes()).hexdigest().upper()} if published else None),
    }
    _write_json(root / "result.json", result)
    return root


class ModernCatalogueTests(unittest.TestCase):
    def test_f200_recovery_compares_complete_output_and_rejects_wrong_engine_or_oracle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline = _capture(root / "baseline", _baseline_raw(), _baseline_settings(), published=False, target="f200")
            published_raw = _published_raw()
            del published_raw["mod-data"]
            published = _capture(root / "published", published_raw, _published_settings(), published=True, target="f200")
            inventory = catalogue.recover_inventory(baseline, published, baseline, published, target="f200")
            self.assertEqual(inventory["kind"], catalogue.GENERAL_KIND)
            self.assertEqual(inventory["source"], {"published_version": "4.7.20000", "engine_family": "2.0",
                             "profiles": ["base-f200", "space-age-f200"]})
            self.assertIsNone(inventory["profiles"][0]["captured_maximum_level_bindings"])
            inventory_path = root / "inventory.json"
            catalogue._write_new_json(inventory_path, inventory)
            raw = deepcopy(published_raw)
            candidate = _capture(root / "candidate", raw, _published_settings(), published=True,
                                 target="f200", mir_version="5.0.20000")
            result = catalogue.compare_candidate(inventory_path, "base-f200", baseline, candidate)
            self.assertEqual(result["status"], "equal-intended-native-output")
            raw["technology"]["recipe-prod-research_alpha-1"]["effects"].append({"type": "nothing"})
            changed = _capture(root / "changed", raw, _published_settings(), published=True,
                               target="f200", mir_version="5.0.20000")
            self.assertEqual(catalogue.compare_candidate(inventory_path, "base-f200", baseline, changed)["status"],
                             "different-intended-native-output")
            with self.assertRaisesRegex(catalogue.CatalogueError, "never a MIR5 candidate"):
                catalogue.recover_inventory(baseline, candidate, baseline, candidate, target="f200")
            wrong_version = _capture(root / "wrong-version", _published_raw(), _published_settings(),
                                     published=True, target="f200", mir_version="4.7.20001")
            with self.assertRaisesRegex(catalogue.CatalogueError, "exact published 4.7.0"):
                catalogue.recover_inventory(baseline, wrong_version, baseline, wrong_version, target="f200")
            baseline210 = _capture(root / "engine210-baseline", _baseline_raw(), _baseline_settings(), published=False)
            published210 = _capture(root / "engine210-published", _published_raw(), _published_settings(),
                                     published=True, mir_version="4.7.20000")
            with self.assertRaisesRegex(catalogue.CatalogueError, "actual captured engine family"):
                catalogue.recover_inventory(baseline210, published210, baseline210, published210, target="f200")

    def _captures(self, root: Path) -> tuple[Path, Path, Path, Path]:
        no_mir = _capture(root / "base-no-mir", _baseline_raw(), _baseline_settings(), published=False)
        published = _capture(root / "base-published", _published_raw(), _published_settings(), published=True)
        space_no_mir = _capture(root / "space-no-mir", _baseline_raw(), _baseline_settings(), published=False)
        space_published = _capture(root / "space-published", _published_raw(), _published_settings(), published=True)
        return no_mir, published, space_no_mir, space_published

    def _inventory(self, root: Path) -> tuple[Path, Path, Path]:
        no_mir, published, space_no_mir, space_published = self._captures(root)
        inventory = catalogue.recover_inventory(no_mir, published, space_no_mir, space_published)
        path = root / "modern-catalogue.json"
        catalogue._write_new_json(path, inventory)
        return path, no_mir, published

    def test_identical_profile_bytes_compare_across_run_directories_but_changed_inputs_refuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inventory_path, baseline, _ = self._inventory(root)
            expected_raw = _published_raw()
            del expected_raw["mod-data"]["more-infinite-research-compiler-evidence"]
            del expected_raw["mod-data"]["more-infinite-research-maximum-level-policy"]
            candidate = _capture(root / "candidate", expected_raw, _published_settings(), published=True)
            relocated = root / "later-run" / "profile.json"
            relocated.parent.mkdir()
            relocated.write_bytes((root / "external" / "profile.json").read_bytes())
            _set_profile_receipt(candidate, relocated)
            receipt_path = candidate / "result.json"
            receipt_bytes = receipt_path.read_bytes()

            result = catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate)
            self.assertEqual(result["status"], "equal-intended-native-output")
            self.assertNotIn("profile_input_equivalence", result)
            self.assertEqual(receipt_path.read_bytes(), receipt_bytes)

            # Locator independence cannot excuse either a different engine or
            # changed profile bytes, even when all output dumps are equal.
            changed = json.loads(receipt_bytes)
            changed["engine"]["sha256"] = "0" * 64
            _write_json(receipt_path, changed)
            with self.assertRaisesRegex(catalogue.CatalogueError, "capture engines differ"):
                catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate)
            receipt_path.write_bytes(receipt_bytes)
            relocated.write_bytes(b"different profile settings\n")
            _set_profile_receipt(candidate, relocated)
            with self.assertRaisesRegex(catalogue.CatalogueError, "profile input receipts differ"):
                catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate)

    def test_optional_k2so_profile_requires_a_pair_and_compares_as_its_own_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base_no_mir, base_published, space_no_mir, space_published = self._captures(root)
            with self.assertRaisesRegex(catalogue.CatalogueError, "requires both"):
                catalogue.recover_inventory(base_no_mir, base_published, space_no_mir, space_published,
                                            base_no_mir, None)
            inventory = catalogue.recover_inventory(base_no_mir, base_published, space_no_mir, space_published,
                                                    base_no_mir, base_published)
            self.assertEqual([profile["id"] for profile in inventory["profiles"]],
                             ["base-f210", "space-age-f210", "k2so-f210"])
            path = root / "k2so-inventory.json"
            catalogue._write_new_json(path, inventory)
            expected_raw, expected_settings = _published_raw(), _published_settings()
            del expected_raw["mod-data"]["more-infinite-research-compiler-evidence"]
            del expected_raw["mod-data"]["more-infinite-research-maximum-level-policy"]
            candidate = _capture(root / "k2so-candidate", expected_raw, expected_settings, published=True)
            self.assertEqual(catalogue.compare_candidate(path, "k2so-f210", base_no_mir, candidate)["status"],
                             "equal-intended-native-output")

    def test_paired_profile_files_allow_only_hash_verified_full_document_equivalence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            document = {
                "schema": 1,
                "kind": "synthetic-complete-profile",
                "target": "f210",
                "settings": {"mode": "Defaults", "all": [True, 1, "named"]},
                "mods": [{"name": "base", "version": "2.1.23", "enabled": True}],
            }
            baseline_profile = root / "baseline-profile.json"
            candidate_profile = root / "candidate-profile.json"
            _write_json(baseline_profile, document)
            candidate_profile.write_text(
                json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\r\n", encoding="utf-8"
            )
            self.assertNotEqual(baseline_profile.read_bytes(), candidate_profile.read_bytes())

            baseline, published, space_baseline, space_published = self._captures(root)
            for capture in (baseline, published, space_baseline, space_published):
                _set_profile_receipt(capture, baseline_profile)
            inventory_path = root / "modern-catalogue.json"
            catalogue._write_new_json(
                inventory_path,
                catalogue.recover_inventory(baseline, published, space_baseline, space_published),
            )
            expected_raw = _published_raw()
            del expected_raw["mod-data"]["more-infinite-research-compiler-evidence"]
            del expected_raw["mod-data"]["more-infinite-research-maximum-level-policy"]
            candidate = _capture(root / "candidate", expected_raw, _published_settings(), published=True)
            _set_profile_receipt(candidate, candidate_profile)

            with self.assertRaisesRegex(catalogue.CatalogueError, "profile input receipts differ"):
                catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate)
            for kwargs in (
                {"baseline_profile_file": baseline_profile},
                {"candidate_profile_file": candidate_profile},
            ):
                with self.subTest(missing_pair=kwargs):
                    with self.assertRaisesRegex(catalogue.CatalogueError, "requires both"):
                        catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate, **kwargs)

            result = catalogue.compare_candidate(
                inventory_path, "base-f210", baseline, candidate,
                baseline_profile_file=baseline_profile, candidate_profile_file=candidate_profile,
            )
            self.assertEqual(result["status"], "equal-intended-native-output")
            equivalence = result["profile_input_equivalence"]
            self.assertEqual(equivalence["status"], "accepted-format-and-locator-equivalence")
            self.assertEqual(equivalence["baseline"]["verified_sha256"],
                             hashlib.sha256(baseline_profile.read_bytes()).hexdigest().upper())
            self.assertEqual(equivalence["candidate"]["verified_sha256"],
                             hashlib.sha256(candidate_profile.read_bytes()).hexdigest().upper())
            self.assertNotEqual(equivalence["baseline"]["verified_sha256"],
                                equivalence["candidate"]["verified_sha256"])
            self.assertEqual(equivalence["canonical_full_document_sha256"],
                             hashlib.sha256(_json_bytes(document)).hexdigest().upper())

            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(catalogue.main([
                    "compare", "--inventory", str(inventory_path), "--profile", "base-f210",
                    "--baseline", str(baseline), "--candidate", str(candidate),
                    "--baseline-profile-file", str(baseline_profile),
                    "--candidate-profile-file", str(candidate_profile),
                ]), 0)

            changed_document = deepcopy(document)
            changed_document["settings"]["mode"] = "Changed"
            changed_profile = root / "changed-profile.json"
            _write_json(changed_profile, changed_document)
            _set_profile_receipt(candidate, changed_profile)
            with self.assertRaisesRegex(catalogue.CatalogueError, "full parsed JSON documents"):
                catalogue.compare_candidate(
                    inventory_path, "base-f210", baseline, candidate,
                    baseline_profile_file=baseline_profile, candidate_profile_file=changed_profile,
                )

            duplicate_key_profile = root / "duplicate-key-profile.json"
            duplicate_key_profile.write_text('{"schema":1,"schema":1}\n', encoding="utf-8")
            _set_profile_receipt(candidate, duplicate_key_profile)
            with self.assertRaisesRegex(catalogue.CatalogueError, "strict UTF-8 JSON"):
                catalogue.compare_candidate(
                    inventory_path, "base-f210", baseline, candidate,
                    baseline_profile_file=baseline_profile, candidate_profile_file=duplicate_key_profile,
                )

            _set_profile_receipt(candidate, candidate_profile)
            wrong_bytes = root / "wrong-profile.json"
            wrong_bytes.write_text('{"not":"the captured profile"}\n', encoding="utf-8")
            with self.assertRaisesRegex(catalogue.CatalogueError, "hash differs"):
                catalogue.compare_candidate(
                    inventory_path, "base-f210", baseline, candidate,
                    baseline_profile_file=baseline_profile, candidate_profile_file=wrong_bytes,
                )

    def test_settings_targets_retirement_is_exact_and_does_not_touch_captured_rows(self):
        records = {
            "additions": [{
                "type": "bool-setting", "name": "ips-enable-research_alpha",
                "row": {"type": "bool-setting", "name": "ips-enable-research_alpha", "targets": {"planner": "only"}},
            }],
            "patches": [],
        }
        instruction = catalogue._intended_settings(records)
        self.assertEqual(instruction["remove_published_fields"], [{
            "type": "bool-setting", "name": "ips-enable-research_alpha", "field": "targets",
            "reason": "MIR4 planner-only target metadata has no Factorio setting or MIR5 runtime consumer",
            "provenance": "published-4.7 setting descriptor targets field",
        }])
        profile = {"published_output": {"settings": records}, "intended_player_output": {"settings": instruction}}
        intended = catalogue._intended_domain(profile, "settings")
        self.assertNotIn("targets", intended["additions"][0]["row"])
        self.assertEqual(records["additions"][0]["row"]["targets"], {"planner": "only"})
        forged = deepcopy(instruction)
        forged["remove_published_fields"][0]["field"] = "default_value"
        profile["intended_player_output"]["settings"] = forged
        with self.assertRaisesRegex(catalogue.CatalogueError, "exact settings targets"):
            catalogue._intended_domain(profile, "settings")

    def test_recovery_retains_full_rows_and_explicitly_excludes_private_mir4_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            inventory_path, _, _ = self._inventory(Path(temporary))
            inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
            profile = inventory["profiles"][0]
            additions = {(row["type"], row["name"]): row["row"]
                         for row in profile["published_output"]["data"]["additions"]}
            self.assertEqual(additions[("technology", "recipe-prod-research_alpha-1")]["unit"]["count_formula"], "100 * L")
            self.assertTrue(additions[("mod-data", "more-infinite-research-compiler-evidence")]["data"]["compiler"])
            self.assertEqual(profile["published_output"]["data"]["patches"][0]["before"]["allow_productivity"], False)
            self.assertEqual(profile["published_output"]["data"]["patches"][0]["after"]["allow_productivity"], True)
            descriptor = profile["published_output"]["settings"]["additions"][-1]["row"]
            self.assertEqual(descriptor["maximum_value"], 1000)
            excluded = profile["intended_player_output"]["data"]["exclude_published_additions"]
            self.assertEqual({row["name"] for row in excluded}, {
                "more-infinite-research-compiler-evidence", "more-infinite-research-maximum-level-policy",
            })
            bindings = profile["captured_maximum_level_bindings"]["bindings"]
            self.assertEqual(bindings[0]["native_owner_identity"], None)
            self.assertEqual(bindings[1]["native_owner_identity"], "native-owner-productivity")

    def test_receipt_hash_tampering_and_mir_identity_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, published, _, _ = self._captures(root)
            (published / "data-raw-dump.json").write_bytes(b"{}\n")
            with self.assertRaisesRegex(catalogue.CatalogueError, "hash differs"):
                catalogue.read_capture(published, require_mir=True)

            _, published, _, _ = self._captures(root / "identity")
            receipt_path = published / "result.json"
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            receipt["mir_archive"]["sha256"] = "0" * 64
            _write_json(receipt_path, receipt)
            with self.assertRaisesRegex(catalogue.CatalogueError, "differs from the selected archive"):
                catalogue.read_capture(published, require_mir=True)

    def test_comparison_rejects_missing_extra_effect_science_progression_settings_and_foreign_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inventory_path, baseline, _ = self._inventory(root)
            expected_raw, expected_settings = _published_raw(), _published_settings()
            del expected_raw["mod-data"]["more-infinite-research-compiler-evidence"]
            del expected_raw["mod-data"]["more-infinite-research-maximum-level-policy"]
            equal = _capture(root / "candidate-equal", expected_raw, expected_settings, published=True)
            self.assertEqual(
                catalogue.compare_candidate(inventory_path, "base-f210", baseline, equal)["status"],
                "equal-intended-native-output",
            )
            mutations = {
                "missing": lambda raw, settings: raw["technology"].pop("recipe-prod-research_alpha-1"),
                "extra": lambda raw, settings: raw["technology"].update({"unexpected": {
                    "type": "technology", "name": "unexpected", "effects": [], "unit": {"count": 1}}}),
                "effect": lambda raw, settings: raw["technology"]["recipe-prod-research_alpha-1"]["effects"].append({"type": "nothing"}),
                "science": lambda raw, settings: raw["technology"]["recipe-prod-research_alpha-1"]["unit"]["ingredients"].append(["logistic-science-pack", 1]),
                "progression": lambda raw, settings: raw["technology"]["recipe-prod-research_alpha-1"].update({"prerequisites": []}),
                "setting": lambda raw, settings: settings["int-setting"]["ips-max-level-research_alpha"].update({"default_value": 42}),
                "foreign": lambda raw, settings: raw["recipe"]["foreign-recipe"].update({"allow_productivity": False}),
            }
            for label, mutate in mutations.items():
                with self.subTest(mutation=label):
                    raw, settings = deepcopy(expected_raw), deepcopy(expected_settings)
                    mutate(raw, settings)
                    candidate = _capture(root / f"candidate-{label}", raw, settings, published=True)
                    result = catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate)
                    self.assertEqual(result["status"], "different-intended-native-output")
                    self.assertTrue(result["differences"])

    def test_reviewed_difference_requires_one_complete_named_disposition(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inventory_path, baseline, _ = self._inventory(root)
            raw, settings = _published_raw(), _published_settings()
            raw["mod-data"].clear()
            del raw["shortcut"]["mir-research-browser"]
            candidate = _capture(root / "candidate", raw, settings, published=True)
            self.assertEqual(catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate)["status"],
                             "different-intended-native-output")
            review = {
                "schema": catalogue.SCHEMA,
                "kind": catalogue.REVIEW_KIND,
                "differences": [{
                    "id": "reviewed-shortcut-removal", "profile": "base-f210", "domain": "data",
                    "type": "shortcut", "name": "mir-research-browser", "expected_candidate": None,
                    "reason": "synthetic explicit cutover disposition",
                }],
            }
            review_path = root / "review.json"
            _write_json(review_path, review)
            self.assertEqual(
                catalogue.compare_candidate(inventory_path, "base-f210", baseline, candidate, review_path)["status"],
                "equal-intended-native-output",
            )


if __name__ == "__main__":
    unittest.main()

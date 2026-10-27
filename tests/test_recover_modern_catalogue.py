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


F210_BOB_ANGEL_EFFECT_ORDER_IDS = (
    "recipe-prod-research_concrete-1",
    "recipe-prod-research_copper-1",
    "recipe-prod-research_copper_cable-1",
    "recipe-prod-research_explosives-1",
    "recipe-prod-research_heavy_ammo-1",
    "recipe-prod-research_inserters-1",
    "recipe-prod-research_iron-1",
    "recipe-prod-research_landfill-1",
    "recipe-prod-research_modules-1",
)


def _canonical_hash(value) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest().upper()


def _reconstruct_static_prefix_effects(effects, base_seed_recipes, published_recipes):
    """Keep the declared Base seed sequence, then canonically append B6-only effects."""
    by_recipe = {}
    for effect in effects:
        if not isinstance(effect, dict) or not isinstance(effect.get("recipe"), str) or not effect["recipe"]:
            raise ValueError("effect lacks a concrete recipe identity")
        if effect["recipe"] in by_recipe:
            raise ValueError("effect recipes must be unique")
        by_recipe[effect["recipe"]] = effect
    if len(published_recipes) != len(set(published_recipes)):
        raise ValueError("published B6 recipe sequence is duplicate")
    missing = [recipe for recipe in base_seed_recipes if recipe not in by_recipe]
    if missing:
        raise ValueError("published B6 payload is missing a required Base seed recipe")
    if set(published_recipes) != set(by_recipe):
        raise ValueError("effect recipes differ from the complete published B6 payload")
    return [by_recipe[recipe] for recipe in base_seed_recipes] + [
        by_recipe[recipe] for recipe in sorted(set(published_recipes) - set(base_seed_recipes))
    ]


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
    def test_bob_angel_f210_effect_order_dispositions_reconstruct_only_nine_complete_b6_rows(self):
        """B6 supplies payloads; unmodded Base supplies only the static prefix order."""
        intent_path = ROOT / "spec/inventory/bob-angel-f210-intent-r01.json"
        intent = json.loads(intent_path.read_text(encoding="utf-8"))
        provenance = intent["provenance"]["effect_order_representation"]
        base_inventory_path = ROOT / provenance["unmodded_space_age_base_inventory"]["path"]
        self.assertEqual(
            hashlib.sha256(base_inventory_path.read_bytes()).hexdigest().upper(),
            provenance["unmodded_space_age_base_inventory"]["sha256"],
        )
        self.assertEqual(
            base_inventory_path.stat().st_size,
            provenance["unmodded_space_age_base_inventory"]["bytes"],
        )
        self.assertEqual(provenance["unmodded_space_age_base_inventory"]["profile"], "space-age-f210")
        self.assertEqual(
            [row["sha256"] for row in provenance["combined_b6_payload_captures"]],
            ["A8935196FBF9A58DA01BB26EFD739CE74941DB2885C6A1514E9379F64A33C3C1"] * 2,
        )
        self.assertEqual(
            [row["path"] for row in provenance["combined_b6_payload_captures"]],
            [
                "build/mir5/recovery-historical/broad-ecosystem-f210-1c90-r04/"
                "q010-published/write-data/script-output/data-raw-dump.json",
                "build/mir5/recovery-historical/bob-angel-q010-standalone-preparation-r04/"
                "published/write-data/script-output/data-raw-dump.json",
            ],
        )

        base_inventory = json.loads(base_inventory_path.read_text(encoding="utf-8"))
        profile = catalogue._inventory_profile(base_inventory, "space-age-f210")
        base_rows = {
            row["name"]: row["row"]
            for row in catalogue._intended_domain(profile, "data")["additions"]
            if row["type"] == "technology"
        }
        reviewed = {
            row["name"]: row
            for row in intent["differences"]
            if row["id"].startswith("BA-F210-EFFECT-ORDER-RECONSTRUCT-")
        }
        self.assertEqual(set(reviewed), set(F210_BOB_ANGEL_EFFECT_ORDER_IDS))
        self.assertEqual(len(intent["differences"]), 158)
        self.assertNotIn(
            "BA-F210-EFFECT-ORDER-UNRESOLVED",
            {row["id"] for row in intent["unresolved_categories"]},
        )

        for name in F210_BOB_ANGEL_EFFECT_ORDER_IDS:
            with self.subTest(technology=name):
                record = reviewed[name]
                representation = record["representation"]
                expected = deepcopy(record["expected_candidate"])
                expected_effects = expected.pop("effects")
                base_seed = [effect["recipe"] for effect in base_rows[name]["effects"]]
                self.assertEqual(representation["base_seed_recipe_order"], base_seed)
                self.assertEqual(
                    {
                        key: representation[key]
                        for key in (
                            "base_seed_recipe_order",
                            "published_effect_recipe_order",
                            "canonical_remaining_recipe_order",
                        )
                    },
                    provenance["technologies"][name],
                )
                self.assertEqual(_canonical_hash(expected), representation["published_non_effect_fields_sha256"])

                by_recipe = {effect["recipe"]: effect for effect in expected_effects}
                published_effects = [
                    by_recipe[recipe] for recipe in representation["published_effect_recipe_order"]
                ]
                self.assertEqual(len(by_recipe), len(expected_effects))
                self.assertEqual(
                    _canonical_hash(sorted(published_effects, key=lambda effect: json.dumps(
                        effect, ensure_ascii=False, sort_keys=True, separators=(",", ":")
                    ))),
                    representation["published_effect_multiset_sha256"],
                )
                published = {**expected, "effects": published_effects}
                self.assertEqual(_canonical_hash(published), record["independent_before_sha256"])
                self.assertEqual(
                    _reconstruct_static_prefix_effects(
                        published_effects,
                        representation["base_seed_recipe_order"],
                        representation["published_effect_recipe_order"],
                    ),
                    expected_effects,
                )
                self.assertEqual(
                    representation["canonical_remaining_recipe_order"],
                    sorted(set(representation["published_effect_recipe_order"]) - set(base_seed)),
                )

        sample = deepcopy(reviewed["recipe-prod-research_inserters-1"])
        published = _reconstruct_static_prefix_effects(
            sample["expected_candidate"]["effects"],
            sample["representation"]["base_seed_recipe_order"],
            sample["representation"]["published_effect_recipe_order"],
        )
        with self.assertRaisesRegex(ValueError, "missing a required Base seed"):
            _reconstruct_static_prefix_effects(
                published[1:], sample["representation"]["base_seed_recipe_order"],
                sample["representation"]["published_effect_recipe_order"],
            )
        with self.assertRaisesRegex(ValueError, "differ from the complete published B6 payload"):
            _reconstruct_static_prefix_effects(
                published + [{"type": "change-recipe-productivity", "recipe": "unexpected", "change": 0.1}],
                sample["representation"]["base_seed_recipe_order"],
                sample["representation"]["published_effect_recipe_order"],
            )
        with self.assertRaisesRegex(ValueError, "must be unique"):
            _reconstruct_static_prefix_effects(
                published + [deepcopy(published[0])], sample["representation"]["base_seed_recipe_order"],
                sample["representation"]["published_effect_recipe_order"],
            )
        self.assertNotEqual(
            _reconstruct_static_prefix_effects(
                published,
                list(reversed(sample["representation"]["base_seed_recipe_order"])),
                sample["representation"]["published_effect_recipe_order"],
            ),
            sample["expected_candidate"]["effects"],
        )

    def test_bob_angel_growth_review_retains_data_and_changes_only_exact_published_ceiling_fields(self):
        inventory = json.loads((ROOT / "spec/inventory/bob-angel-f200-472.json").read_text(encoding="utf-8"))
        profile = catalogue._inventory_profile(inventory, "bob-angel-f200")
        independent = catalogue._intended_domain(profile, "settings")["additions"]
        expected = {row["name"]: row["row"] for row in independent
                    if row["type"] == "double-setting"
                    and row["name"].startswith(("ips-cost-growth-", "mir-cost-growth-"))}
        prior = json.loads((ROOT / "spec/inventory/bob-angel-f200-intent-r02.json").read_text(encoding="utf-8"))
        current = json.loads((ROOT / "spec/inventory/bob-angel-f200-intent-r03.json").read_text(encoding="utf-8"))
        self.assertEqual(current["differences"][:27], prior["differences"])
        reviewed = catalogue._reviewed_differences(ROOT / "spec/inventory/bob-angel-f200-intent-r03.json", "bob-angel-f200")
        changes = [row for row in reviewed if row["domain"] == "settings"]
        self.assertEqual((len(expected), len(changes), len(reviewed)), (121, 121, 148))
        self.assertEqual({row["name"] for row in changes}, set(expected))
        for row in changes:
            before = expected[row["name"]]
            after = deepcopy(row["expected_candidate"])
            self.assertNotIn("maximum_value", before)
            self.assertEqual(after.pop("maximum_value"), 1000)
            self.assertEqual(after, before, row["name"])
            self.assertEqual((row["type"], before["setting_type"]), ("double-setting", "startup"))

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

    def test_bob_angel_f210_recovery_canonicalises_selected_archive_order_only(self):
        """q010's historic no-MIR/B6 archive receipts contain equal identities in a different order."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline = _capture(root / "upstream", _baseline_raw(), _baseline_settings(), published=False)
            published = _capture(root / "published", _published_raw(), _published_settings(), published=True,
                                 mir_version="4.7.21003")
            external = root / "external"
            extra = {
                "name": "bob-angel-provider", "version": "2.1.0", "builtin": False,
                "sha256": hashlib.sha256((external / "base-info.json").read_bytes()).hexdigest().upper(),
            }

            def set_selected(capture: Path, rows: list[dict]) -> None:
                receipt_path = capture / "result.json"
                receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                receipt["selected_archives"] = rows
                _write_json(receipt_path, receipt)

            baseline_receipt = json.loads((baseline / "result.json").read_text(encoding="utf-8"))
            published_receipt = json.loads((published / "result.json").read_text(encoding="utf-8"))
            # The selected-archive receipt is an identity set; generated and
            # loaded selection ordering remains separately exact.
            set_selected(baseline, [baseline_receipt["selected_archives"][0], extra])
            set_selected(published, [extra, published_receipt["selected_archives"][0],
                                     published_receipt["selected_archives"][1]])

            inventory_path = root / "bob-angel-f210.json"
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(catalogue.main([
                    "recover-bob-angel-f210", "--no-mir", str(baseline), "--published", str(published),
                    "--output", str(inventory_path),
                ]), 0)
            inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
            self.assertEqual(inventory["source"], {
                "published_version": "4.7.21003", "engine_family": "2.1", "profiles": ["bob-angel-f210"],
            })
            expected_raw = _published_raw()
            del expected_raw["mod-data"]
            candidate = _capture(root / "candidate", expected_raw, _published_settings(), published=True,
                                 mir_version="5.0.21000")
            candidate_receipt = json.loads((candidate / "result.json").read_text(encoding="utf-8"))
            set_selected(candidate, [extra, candidate_receipt["selected_archives"][0],
                                     candidate_receipt["selected_archives"][1]])

            self.assertEqual(
                catalogue.compare_candidate(inventory_path, "bob-angel-f210", baseline, candidate)["status"],
                "equal-intended-native-output",
            )
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(catalogue.main([
                    "compare", "--inventory", str(inventory_path), "--profile", "bob-angel-f210",
                    "--baseline", str(baseline), "--candidate", str(candidate),
                ]), 0)

            changed = deepcopy(extra)
            changed["sha256"] = "0" * 64
            set_selected(candidate, [changed, candidate_receipt["selected_archives"][0],
                                     candidate_receipt["selected_archives"][1]])
            with self.assertRaisesRegex(catalogue.CatalogueError, "selected upstream archive identities differ"):
                catalogue.compare_candidate(inventory_path, "bob-angel-f210", baseline, candidate)

    def test_old_inventory_archive_order_preserves_other_receipt_fields_and_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = self._captures(root)
            provider = {"name": "zzz-upstream", "version": "1.0.0", "enabled": True}
            identity = {"name": provider["name"], "version": provider["version"], "builtin": False,
                        "sha256": hashlib.sha256(b"independent upstream archive").hexdigest().upper()}

            def add_provider(capture):
                receipt_path = capture / "result.json"
                receipt = json.loads(receipt_path.read_bytes())
                mods = [provider, *receipt["generated_selection"]["mods"]]
                selection_path = capture / "selection.json"
                _write_json(selection_path, {"mods": mods})
                receipt["generated_selection"] = {**_record(capture, selection_path), "mods": mods}
                receipt["selected_archives"].insert(0, identity)
                receipt["loaded_selection"].insert(0, "zzz-upstream@1.0.0")
                _write_json(receipt_path, receipt)

            for capture in captures:
                add_provider(capture)
            inventory = catalogue.recover_inventory(*captures)
            # Older sealed inventories preserve archive enumeration order.
            # Neither their bytes nor order-sensitive selection fields change.
            profile = catalogue._inventory_profile(inventory, "base-f210")
            original_receipt = profile["capture_receipts"]["no_mir"]
            original_receipt["selected_archives_without_mir"].reverse()
            inventory_path = root / "old-order.json"
            _write_json(inventory_path, inventory)
            original_bytes = inventory_path.read_bytes()
            baseline_bytes = (captures[0] / "result.json").read_bytes()

            expected = _published_raw()
            del expected["mod-data"]
            candidate = _capture(root / "candidate", expected, _published_settings(),
                                 published=True, mir_version="5.0.21000")
            add_provider(candidate)
            self.assertEqual(catalogue.compare_candidate(
                inventory_path, "base-f210", captures[0], candidate)["status"],
                "equal-intended-native-output")
            self.assertEqual(inventory_path.read_bytes(), original_bytes)
            self.assertEqual((captures[0] / "result.json").read_bytes(), baseline_bytes)

            for opponent in ("sha", "generated-order", "loaded-order", "extra-mir", "duplicate", "extra-field"):
                with self.subTest(opponent=opponent):
                    changed = deepcopy(inventory)
                    receipt = catalogue._inventory_profile(changed, "base-f210")["capture_receipts"]["no_mir"]
                    archives = receipt["selected_archives_without_mir"]
                    if opponent == "sha":
                        archives[0]["sha256"] = "0" * 64
                    elif opponent == "generated-order":
                        receipt["selection_without_mir"].reverse()
                    elif opponent == "loaded-order":
                        receipt["loaded_without_mir"].reverse()
                    elif opponent == "extra-mir":
                        archives.append({"name": "more-infinite-research", "version": "4.7.21000",
                                         "builtin": False, "sha256": "0" * 64})
                    elif opponent == "duplicate":
                        archives.append(deepcopy(archives[0]))
                    else:
                        archives[0]["unexpected_identity_field"] = "must remain visible"
                    bad_path = root / (opponent + ".json")
                    _write_json(bad_path, changed)
                    with self.assertRaisesRegex(catalogue.CatalogueError, "baseline does not match"):
                        catalogue.compare_candidate(bad_path, "base-f210", captures[0], candidate)

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

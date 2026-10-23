"""Compare K2 Base against published Base output plus explicit source/native facts.

Both published K2 captures failed. This is an independent intended-output
comparison, never a recovered successful historical K2 output or player code.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import recover_modern_catalogue as catalogue


ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / "spec/mir5/inventory/modern-f200-470.json"
FACTS = ROOT / "tests/mir5/fixtures/k2-base-f200-captured-facts.json"


def _semantic_hash(value):
    return hashlib.sha256(catalogue._json_bytes(value)).hexdigest().upper()


def intended_output():
    """No candidate input: retain every published field except named adaptations."""
    inventory = catalogue._load_json(INVENTORY, "published Base inventory")
    facts = catalogue._load_json(FACTS, "K2 source/native facts")
    profile = catalogue._inventory_profile(inventory, "base-f200")
    data = deepcopy(catalogue._intended_domain(profile, "data"))
    settings = deepcopy(catalogue._intended_domain(profile, "settings"))
    technologies = {row["name"]: row["row"] for row in data["additions"] if row["type"] == "technology"}
    defaults = {row["name"]: row["row"].get("default_value") for row in settings["additions"]}
    if (set(technologies) != set(facts["emitted_ids"]) or len(technologies) != 54
            or data["patches"] or settings["patches"] or len(settings["additions"]) != 875):
        raise catalogue.CatalogueError("independent K2/Base identities or scope changed")
    icons = facts["presentation_icon_facts"]
    if len(icons) != 10 or len({row["id"] for row in icons}) != 10:
        raise catalogue.CatalogueError("K2 presentation facts must name ten unique identities")
    for fact in icons:
        # Retain the published overlay layers and every non-icon field.
        technologies[fact["id"]]["icons"][0] = deepcopy(fact["emitted"])
    for fact in facts["continuations"]:
        row = technologies[fact["id"]]
        expected = fact["default"]
        if (row["unit"]["count_formula"] != expected["count_formula"]
                or row["unit"]["time"] != expected["time"]
                or row["unit"]["ingredients"] != [[name, 1] for name in expected["science"]]):
            raise catalogue.CatalogueError("K2 facts disagree with independently captured Base progression")
        row["effects"] = deepcopy(expected["effects"])
    additions = facts["k2_product_target_additions"]
    if len(additions) != 32:
        raise catalogue.CatalogueError("K2 product facts must retain all 32 additions")
    for fact in additions:
        family = fact["family"]
        row = technologies[f"recipe-prod-{family}-1"]
        percent = defaults[f"ips-effect-per-level-{family}"]
        if any(effect.get("recipe") == fact["recipe"] for effect in row["effects"]):
            raise catalogue.CatalogueError("independent K2 addition duplicates a published target")
        # Published setting percent and authored target weight, with the retained
        # arithmetic order. Do not infer percentages from the candidate effects.
        row["effects"].append({"type": "change-recipe-productivity", "recipe": fact["recipe"],
                               "change": percent * fact["weight"] / 100})
    return {
        "schema": 1,
        "kind": "MIR5K2BaseIndependentIntendedOutputV1",
        "basis": "published Base F200 output plus explicit K2 source/native facts; published K2 failed",
        "inputs": {
            "base_inventory_semantic_sha256": _semantic_hash(inventory),
            "k2_facts_semantic_sha256": _semantic_hash(facts),
            "no_mir_raw_sha256": facts["raw"]["sha256"],
            "no_mir_settings_sha256": facts["native_settings"]["sha256"],
        },
        "adaptations": {"presentation_identities": [row["id"] for row in icons],
                        "continuation_effect_identities": [row["id"] for row in facts["continuations"]],
                        "additional_product_effects": len(additions)},
        "data": data,
        "settings": settings,
    }


def compare(expected, baseline_root, candidate_root):
    if not catalogue._same(expected, intended_output()):
        raise catalogue.CatalogueError("frozen expectation differs from independent source/native facts")
    baseline = catalogue.read_capture(baseline_root, require_mir=False)
    candidate = catalogue.read_capture(candidate_root, require_mir=True)
    if baseline["files"]["data_raw"]["sha256"] != expected["inputs"]["no_mir_raw_sha256"]:
        raise catalogue.CatalogueError("K2 baseline differs from the independent native reference")
    if baseline["files"]["mod_settings"]["sha256"] != expected["inputs"]["no_mir_settings_sha256"]:
        raise catalogue.CatalogueError("K2 baseline settings differ from the independent native reference")
    catalogue._assert_matching_inputs(baseline, candidate)
    differences = []
    for domain, key in (("data", "raw"), ("settings", "settings")):
        intended = catalogue._overlay_domain(baseline[key], expected[domain], domain)
        differences += catalogue._difference_summary(intended, candidate[key], domain)
    return {
        "schema": 1,
        "kind": "MIR5K2BaseIndependentCandidateComparisonV1",
        "status": "equal-intended-native-output" if not differences else "different-intended-native-output",
        "scope": "complete data/settings; no physical production, gameplay, saves, multiplayer or release pass",
        "basis": expected["basis"],
        "expected_semantic_sha256": _semantic_hash(expected),
        "inputs": expected["inputs"],
        "adaptations": expected["adaptations"],
        "baseline_receipt": catalogue._capture_receipt(baseline),
        "candidate_receipt": catalogue._capture_receipt(candidate),
        "candidate_player": candidate["published_mir"],
        "differences": differences,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    freeze = commands.add_parser("freeze")
    freeze.add_argument("--output", type=Path, required=True)
    check = commands.add_parser("compare")
    check.add_argument("--expected", type=Path, required=True)
    check.add_argument("--baseline", type=Path, required=True)
    check.add_argument("--candidate", type=Path, required=True)
    check.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "freeze":
            value = intended_output()
        else:
            value = compare(catalogue._load_json(args.expected, "frozen K2 expectation"), args.baseline, args.candidate)
        catalogue._write_new_json(args.output, value)
        print(value.get("status", value["kind"]))
        return 1 if value.get("differences") else 0
    except catalogue.CatalogueError as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    raise SystemExit(main())

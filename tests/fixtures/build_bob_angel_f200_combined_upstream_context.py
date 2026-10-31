"""Derive the bounded F200 combined-profile upstream data-final context.

The only prototype input is the retained EAD7 control-without-MIR raw dump.
The selected groups are the finite groups the F200 data-final path consumes:
the complete recipe and technology collections, every selectable item family,
and labs.  Published MIR rows are not an input to this fixture.
"""

from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRIMARY = Path(r"D:/Projects/Factorio/more-infinite-research")
SOURCE = PRIMARY / "build/qualification/whole-product-heavy-space-age-f200-admission-r01-controller"
RAW = SOURCE / "native-captures/control-without-mir/write-data/script-output/data-raw-dump.json"
OUTPUT = ROOT / "tests/fixtures/bob-angel-f200-combined-upstream-context.json.gz"
RAW_SHA256 = "AD702CC98FA30A672C8A358305D0F562A5965E51F28CED8D0EFC8ABD26F5F487"
RAW_BYTES = 64158857
PROFILE = ROOT / "tests/profiles/bob-angel-full-space-age-f200-2077.json"
PROFILE_SHA256 = "61CBE6299DD2708079EA80FB3871AC980C6FF7281DD126C61B3126A7FF294857"
ITEM_GROUPS = (
    "item", "tool", "mining-tool", "module", "ammo", "capsule", "gun", "armor", "repair-tool",
    "item-with-entity-data", "item-with-inventory", "item-with-label", "item-with-tags",
    "selection-tool", "copy-paste-tool", "blueprint", "blueprint-book", "deconstruction-item",
    "upgrade-item", "spidertron-remote", "rail-planner", "space-platform-starter-pack",
)
REQUESTED_GROUPS = ("recipe", "technology", "lab") + ITEM_GROUPS


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> None:
    if not RAW.is_file() or RAW.stat().st_size != RAW_BYTES or digest(RAW) != RAW_SHA256:
        raise SystemExit("retained EAD7 NoMIR data-raw body differs or is unavailable")
    if not PROFILE.is_file() or digest(PROFILE) != PROFILE_SHA256:
        raise SystemExit("declared F200 combined profile differs or is unavailable")
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    selected = {}
    for group in REQUESTED_GROUPS:
        value = raw.get(group)
        # Factorio's raw dump omits an empty prototype class rather than
        # serializing it as an empty map. Preserve that NoMIR fact instead of
        # fabricating a class that the actual dump did not contain.
        if group in ITEM_GROUPS and value is None:
            continue
        if not isinstance(value, dict):
            raise SystemExit(f"NoMIR raw dump lacks object group {group}")
        selected[group] = value
    groups = tuple(selected)
    profile = json.loads(PROFILE.read_text(encoding="utf-8"))
    output = {
        "schema": 1,
        "kind": "MIR5BobAngelF200CombinedUpstreamDataFinalContextV1",
        "scope": "Bounded F200/2.0.77 control-without-MIR upstream input for the actual selected data-final path. It retains complete recipes,technologies,selectable item families,and labs; no published or candidate MIR technology body is present.",
        "source": {
            "capture": "EAD7 control-without-mir",
            "path": str(RAW),
            "bytes": RAW_BYTES,
            "sha256": RAW_SHA256,
            "engine_sha256": "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B",
        },
        "profile": {
            "path": "tests/profiles/bob-angel-full-space-age-f200-2077.json",
            "sha256": PROFILE_SHA256,
            "selection": {row["name"]: row["version"] for row in profile["mods"] if row["enabled"]},
        },
        "groups": list(groups),
        "counts": {group: len(selected[group]) for group in groups},
        "raw": selected,
    }
    plain = (json.dumps(output, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    OUTPUT.write_bytes(gzip.compress(plain, compresslevel=9, mtime=0))
    print(json.dumps({"path": str(OUTPUT), "bytes": OUTPUT.stat().st_size, "sha256": digest(OUTPUT)}, sort_keys=True))


if __name__ == "__main__":
    main()

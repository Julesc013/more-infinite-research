"""Compare complete native data/settings output for a private MIR4.7 replay.

No projection or technology-only allowlist: all JSON object fields and array
ordering participate. Receipts retain their original identities; optional
custody archives must hash to the MIR bytes in those unmodified receipts.
"""
import argparse
import json
from pathlib import Path
import sys

import replay


def compare(left: Path, right: Path, left_archive: Path, right_archive: Path):
    before = replay._read_capture(left, True, left_archive)
    after = replay._read_capture(right, True, right_archive)
    replay._assert_matching_inputs(before, after)
    for capture in (before, after):
        replay._validate_raw(capture["raw"], "native data")
        replay._validate_raw(capture["settings"], "native settings")
    differences = []
    for domain in ("raw", "settings"):
        if not replay._same_json_value(before[domain], after[domain]):
            # Top-level domains plus prototype IDs give a bounded useful
            # report, while equality above still checks every nested value.
            for kind in sorted(set(before[domain]) | set(after[domain])):
                a = before[domain].get(kind, {})
                b = after[domain].get(kind, {})
                if not replay._same_json_value(a, b):
                    differences.append({"domain": domain, "type": kind,
                        "names": [name for name in sorted(set(a) | set(b))
                                  if name not in a or name not in b
                                  or not replay._same_json_value(a[name], b[name])]})
    return {"schema": 1, "kind": "MIR5CompleteReplayNativeOutputComparisonV1",
        "status": "equal-complete-native-output" if not differences else "different-native-output",
        "scope": "data/settings only; no gameplay, menu, runtime or release qualification",
        "left": {"result_sha256": replay._sha256(before["result_path"]), "files": before["files"]},
        "right": {"result_sha256": replay._sha256(after["result_path"]), "files": after["files"]},
        "differences": differences}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("left", "right", "left-archive", "right-archive", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Preserve existing comparison output")
    try:
        result = compare(args.left, args.right, args.left_archive, args.right_archive)
    except (replay.ReplayError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("xb") as stream:
        stream.write(replay._json_bytes(result))
    print(result["status"])
    return 0 if not result["differences"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

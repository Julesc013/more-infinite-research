"""Write bounded test-only Factorio 2.0.77/2.1.23 startup settings files.

Format: https://wiki.factorio.com/Mod_settings_file_format and
https://wiki.factorio.com/Property_tree; historical short-string reference:
mir-native-worker/projects/mir/tasks/data-only-paid-upgrade/Write-PureUpgradeSettings.py.
Output is an input to native tests, not evidence that Factorio accepted it.
"""
import argparse
import json
import math
from pathlib import Path
import struct

VERSIONS = {"2.0.77": (2, 0, 77, 0), "2.1.23": (2, 1, 23, 0)}
MAX_STRING_BYTES = 1024 * 1024
MAX_SETTINGS = 10000
MAX_FILE_BYTES = 4 * 1024 * 1024


def _string(value):
    if len(value) > MAX_STRING_BYTES:
        raise ValueError("string exceeds input bound")
    raw = value.encode("utf-8")
    if len(raw) > MAX_STRING_BYTES:
        raise ValueError("string exceeds input bound")
    if not raw:
        return b"\x01"
    length = bytes([len(raw)]) if len(raw) < 255 else b"\xff" + struct.pack("<I", len(raw))
    return b"\x00" + length + raw


def _dictionary(items):
    return b"\x05\x00" + struct.pack("<I", len(items)) + b"".join(
        _string(name) + value for name, value in sorted(items.items())
    )


def _value(value):
    if type(value) is bool:
        return b"\x01\x00" + bytes([value])
    if type(value) in (int, float):
        if abs(value) > 2**53 or not math.isfinite(value):
            raise ValueError("nonfinite or inexact numeric setting")
        return b"\x02\x00" + struct.pack("<d", value)
    if type(value) is str:
        return b"\x03\x00" + _string(value)
    raise ValueError("setting must be a boolean, finite number, or string")


def encode(version, startup):
    if version not in VERSIONS:
        raise ValueError("unsupported engine version")
    if type(startup) is not dict or len(startup) > MAX_SETTINGS:
        raise ValueError("startup must be a bounded object")
    header = struct.pack("<4H?", *VERSIONS[version], False)
    sections = {"startup": _dictionary({}), "runtime-global": _dictionary({}),
                "runtime-per-user": _dictionary({})}
    # Keep accumulated rows bounded, including their names and dictionary
    # framing. A direct encode() caller is not subject to the CLI JSON limit.
    size = len(header) + len(_dictionary(sections))
    rows = {}
    for name, value in startup.items():
        if type(name) is not str or not name:
            raise ValueError("setting name must be a nonempty string")
        name_size = len(_string(name))
        row = _dictionary({"value": _value(value)})
        size += name_size + len(row)
        if size > MAX_FILE_BYTES:
            raise ValueError("file exceeds output bound")
        rows[name] = row
    sections["startup"] = _dictionary(rows)
    result = header + _dictionary(sections)
    if len(result) > MAX_FILE_BYTES:
        raise ValueError("file exceeds output bound")
    return result


def _no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", choices=sorted(VERSIONS), required=True)
    parser.add_argument("--startup-json", type=Path, required=True,
                        help="JSON object of startup setting names to scalar values")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.startup_json.stat().st_size > 2 * MAX_STRING_BYTES:
        raise ValueError("JSON input exceeds bound")
    startup = json.loads(args.startup_json.read_text(encoding="utf-8-sig"), object_pairs_hook=_no_duplicates)
    data = encode(args.engine, startup)
    with args.output.open("xb") as stream:
        stream.write(data)
    print(json.dumps({"engine": args.engine, "startup_count": len(startup), "bytes": len(data),
                      "native_acceptance": False}))


if __name__ == "__main__":
    main()

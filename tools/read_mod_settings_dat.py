"""Independently read the bounded scalar startup subset used by native tests.

This deliberately refuses unsupported property-tree forms and versions; it is
not a general reader for arbitrary player mod-settings.dat files.
"""
import argparse
import json
import math
from pathlib import Path
import struct

MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_STRING_BYTES = 1024 * 1024
MAX_SETTINGS = 10000
VERSIONS = {(2, 0, 77, 0): "2.0.77", (2, 1, 23, 0): "2.1.23"}


class Reader:
    def __init__(self, data):
        if len(data) > MAX_FILE_BYTES:
            raise ValueError("file exceeds bound")
        self.data = data
        self.pos = 0

    def take(self, size):
        end = self.pos + size
        if end > len(self.data):
            raise ValueError("truncated settings file")
        result = self.data[self.pos:end]
        self.pos = end
        return result

    def byte(self):
        return self.take(1)[0]

    def boolean(self):
        value = self.byte()
        if value not in (0, 1):
            raise ValueError("noncanonical boolean")
        return value == 1

    def text(self):
        if self.boolean():
            return ""
        size = self.byte()
        if size == 255:
            size = struct.unpack("<I", self.take(4))[0]
            if size < 255:
                raise ValueError("noncanonical long string")
        if size == 0 or size > MAX_STRING_BYTES:
            raise ValueError("invalid string size")
        return self.take(size).decode("utf-8", errors="strict")

    def tree(self, depth=0):
        if depth > 3:
            raise ValueError("tree exceeds supported depth")
        kind = self.byte()
        if self.boolean():
            raise ValueError("unsupported any-type flag")
        if kind == 1:
            return self.boolean()
        if kind == 2:
            number = struct.unpack("<d", self.take(8))[0]
            if not math.isfinite(number) or abs(number) > 2**53:
                raise ValueError("invalid numeric setting")
            return number
        if kind == 3:
            return self.text()
        if kind != 5:
            raise ValueError("unsupported property type")
        count = struct.unpack("<I", self.take(4))[0]
        if count > MAX_SETTINGS:
            raise ValueError("dictionary exceeds bound")
        result = {}
        for _ in range(count):
            key = self.text()
            if not key or key in result:
                raise ValueError("empty or duplicate dictionary key")
            result[key] = self.tree(depth + 1)
        return result


def decode(data):
    reader = Reader(data)
    header = struct.unpack("<4H", reader.take(8))
    if header not in VERSIONS or reader.boolean():
        raise ValueError("unsupported engine header")
    root = reader.tree()
    if reader.pos != len(data) or type(root) is not dict or set(root) != {"startup", "runtime-global", "runtime-per-user"}:
        raise ValueError("unexpected root or trailing bytes")
    if root["runtime-global"] != {} or root["runtime-per-user"] != {} or type(root["startup"]) is not dict:
        raise ValueError("only scalar startup settings are supported")
    startup = {}
    for name, row in root["startup"].items():
        if type(row) is not dict or set(row) != {"value"} or type(row["value"]) not in (bool, float, str):
            raise ValueError("invalid startup setting shape")
        startup[name] = row["value"]
    return {"engine": VERSIONS[header], "startup": startup}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    args = parser.parse_args()
    if args.file.stat().st_size > MAX_FILE_BYTES:
        raise ValueError("file exceeds bound")
    print(json.dumps(decode(args.file.read_bytes()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

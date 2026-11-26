"""Check a Factorio 2.0.77 save against a witnessed mod configuration.

Treat saved data checksums as configuration evidence. Archive custody still
requires SHA-256 verification against the original input inventory.
"""

import argparse
from hashlib import file_digest
import io
import json
from pathlib import Path
import struct
import zipfile
import zlib


ENGINE = "2.0.77"
MAP_VERSION = struct.pack("<4H", 2, 0, 77, 0)
BASE_ROW_PREFIX = b"\x04base\x02\x00\x4d"
HEADER_LIMIT = 128 * 1024


def read_prefix(save):
    with zipfile.ZipFile(save) as archive:
        chunks = [item for item in archive.infolist()
                  if item.filename.count("/") == 1 and item.filename.endswith("/level.dat0")]
        if len(chunks) != 1:
            raise ValueError("expected one root level.dat0 map chunk")
        decoder = zlib.decompressobj()
        header = bytearray()
        with archive.open(chunks[0]) as compressed:
            while len(header) < HEADER_LIMIT and not decoder.eof:
                block = compressed.read(4096)
                if not block:
                    break
                header.extend(decoder.decompress(block, HEADER_LIMIT - len(header)))
        return bytes(header)


def take(stream, width):
    result = stream.read(width)
    if len(result) != width:
        raise ValueError("truncated saved mod table")
    return result


def read_version(stream):
    components = []
    for _ in range(3):
        value = take(stream, 1)[0]
        if value == 255:
            value = int.from_bytes(take(stream, 2), "little")
        components.append(str(value))
    return ".".join(components)


def read_rows(header, count):
    if not header.startswith(MAP_VERSION):
        raise ValueError(f"expected Factorio {ENGINE} map version")
    signature = bytes((count,)) + BASE_ROW_PREFIX
    opening = header[:4096]
    if opening.count(signature) != 1:
        raise ValueError("saved mod table is missing, ambiguous, or has a different row count")
    rows = {}
    stream = io.BytesIO(header)
    stream.seek(opening.index(signature) + 1)
    for _ in range(count):
        name_length = take(stream, 1)[0]
        name = take(stream, name_length).decode("utf-8")
        if not name or name in rows:
            raise ValueError("empty or duplicate mod name in saved mod table")
        rows[name] = {
            "version": read_version(stream),
            "data_checksum": int.from_bytes(take(stream, 4), "little"),
        }
    return rows


def verify_save(path, witness):
    if not isinstance(witness, dict) or not 1 <= len(witness) < 255:
        raise ValueError("expected a witnessed roster with 1 to 254 mods")
    for row in witness.values():
        if (not isinstance(row, dict) or set(row) != {"version", "data_checksum"}
                or not isinstance(row["version"], str) or type(row["data_checksum"]) is not int
                or not 0 <= row["data_checksum"] < 2**32):
            raise ValueError("witness rows require a version and an unsigned 32-bit data checksum")
    if witness.get("base", {}).get("version") != ENGINE:
        raise ValueError(f"witness must record Base {ENGINE}")
    with path.open("rb") as save:
        rows = read_rows(read_prefix(save), len(witness))
        different = sorted(name for name in rows.keys() | witness.keys()
                           if rows.get(name) != witness.get(name))
        if different:
            raise ValueError("saved configuration differs from witness for " + ", ".join(different))
        save.seek(0)
        return {"engine": ENGINE, "save_sha256": file_digest(save, "sha256").hexdigest(), "mods": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path, help="Protected original save ZIP")
    parser.add_argument("--witness", type=Path, required=True,
                        help="JSON object keyed by mod name with version and data_checksum fields")
    args = parser.parse_args()
    try:
        witness = json.loads(args.witness.read_text(encoding="utf-8-sig"))
        result = verify_save(args.save, witness)
    except (OSError, ValueError, zipfile.BadZipFile, zlib.error) as error:
        parser.exit(1, f"{error}\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()

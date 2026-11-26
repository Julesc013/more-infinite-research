"""Build a private worker preparation mod for a witnessed legacy save."""

import argparse
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import zipfile

from read_save_mod_checksums import verify_save


ROOT = Path(__file__).resolve().parents[1]
NAME = "mir-worker-storage-preparation"
VERSION = "0.1.0"
CHECKPOINT = "research/worker_storage_checkpoint.lua"


def build(save, witness_path, output):
    witness_bytes = witness_path.read_bytes()
    proof = verify_save(save, json.loads(witness_bytes.decode("utf-8-sig")))
    selection = {name: row["version"] for name, row in proof["mods"].items()}
    if selection.get("more-infinite-research") != "4.7.20002" or selection.get("space-exploration") != "0.7.57":
        raise ValueError("expected the published MIR 4.7.20002 and Space Exploration 0.7.57 predecessor")
    if NAME in selection:
        raise ValueError("start with the original save before worker preparation")
    if not all(name.isprintable() and version.isprintable() for name, version in selection.items()):
        raise ValueError("the original mod selection cannot be serialized")
    profile = "return {\n" + "".join(
        f"  [{json.dumps(name, ensure_ascii=False)}] = {json.dumps(version)},\n"
        for name, version in sorted(selection.items())
    ) + "}\n"
    info = {
        "name": NAME, "version": VERSION, "title": "MIR Worker Storage Preparation",
        "author": "Julesc013", "factorio_version": "2.0",
        "dependencies": ["base = 2.0.77", "more-infinite-research >= 4.7.20002", "space-exploration = 0.7.57"],
    }
    root = f"{NAME}_{VERSION}"
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as package:
        members = {
            "info.json": json.dumps(info, indent=2) + "\n",
            "control.lua": 'require("research.worker_storage_checkpoint").register_legacy_preparation(require("profile"))\n',
            "profile.lua": profile,
            CHECKPOINT: (ROOT / "source" / CHECKPOINT).read_bytes(),
            "LICENSE": (ROOT / "source/LICENSE").read_bytes(),
        }
        for name, value in members.items():
            package.writestr(zipfile.ZipInfo(f"{root}/{name}"), value, compress_type=zipfile.ZIP_DEFLATED)
    payload = buffer.getvalue()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{root}.zip"
    with archive.open("xb") as file:
        file.write(payload)
    return {
        "original_save_sha256": proof["save_sha256"],
        "witness_sha256": sha256(witness_bytes).hexdigest(),
        "archive": str(archive),
        "archive_sha256": sha256(payload).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path, help="Protected Factorio 2.0.77 predecessor")
    parser.add_argument("--witness", type=Path, required=True, help="Mod versions and data checksums from the original native setup")
    parser.add_argument("--output-directory", type=Path, required=True, help="Private output outside the active mod library")
    args = parser.parse_args()
    try:
        result = build(args.save, args.witness, args.output_directory)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()

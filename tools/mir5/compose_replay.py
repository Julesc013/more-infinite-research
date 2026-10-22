"""Compose an offline MIR 4.7 diagnostic replay archive without product imports.

The composer starts from the exact published 4.7.21000 archive and replaces
only the six Factorio data/settings entrypoints with files already rendered and
hash-recorded by ``tools/mir5/replay.py``.  It writes a private diagnostic
artifact and receipt; it neither executes Factorio nor creates a release
package.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import sys
from typing import Any, BinaryIO
import zipfile


class ComposeReplayError(ValueError):
    """The archive or replay custody inputs cannot be safely composed."""


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PUBLISHED_ARCHIVE_NAME = "more-infinite-research_4.7.21000.zip"
ARCHIVE_ROOT = "more-infinite-research_4.7.21000"
MOD_NAME = "more-infinite-research"
MOD_VERSION = "4.7.21000"
STAGE_ENTRYPOINTS = (
    "data.lua",
    "data-updates.lua",
    "data-final-fixes.lua",
    "settings.lua",
    "settings-updates.lua",
    "settings-final-fixes.lua",
)
REPLAY_RECEIPT = "comparison-receipt.json"
REPLAY_INVENTORY = "hash-inventory.json"
COMPOSITION_RECEIPT = "composition-receipt.json"
CHUNK_BYTES = 1024 * 1024


def _sha256_stream(stream: BinaryIO) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = stream.read(CHUNK_BYTES)
        if not chunk:
            break
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest().upper(), size


def _sha256_file(path: Path) -> tuple[str, int]:
    with path.open("rb") as source:
        return _sha256_stream(source)


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def _read_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ComposeReplayError(f"{label} is absent or not a regular file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ComposeReplayError(f"{label} is not valid UTF-8 JSON: {path}") from error
    if not isinstance(value, dict):
        raise ComposeReplayError(f"{label} must be a JSON object")
    return value


def _normalise_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(character not in "0123456789abcdefABCDEF" for character in value):
        raise ComposeReplayError(f"{label} must be a SHA-256 hex digest")
    return value.upper()


def _output_record_map(value: Any, label: str) -> dict[str, dict[str, Any]]:
    if not isinstance(value, list):
        raise ComposeReplayError(f"{label} must be an array")
    records: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(value, 1):
        if not isinstance(item, dict):
            raise ComposeReplayError(f"{label}[{index}] must be an object")
        path = item.get("path")
        size = item.get("bytes")
        if not isinstance(path, str) or not path or Path(path).name != path or path in {".", ".."}:
            raise ComposeReplayError(f"{label}[{index}] has an unsafe output path")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise ComposeReplayError(f"{label}[{index}] has an invalid byte count")
        digest = _normalise_sha256(item.get("sha256"), f"{label}[{index}].sha256")
        if path in records:
            raise ComposeReplayError(f"{label} duplicates output path: {path}")
        records[path] = {"path": path, "sha256": digest, "bytes": size}
    return records


def _verify_recorded_file(root: Path, name: str, record: dict[str, Any], label: str) -> dict[str, Any]:
    path = root / name
    if not path.is_file() or path.is_symlink():
        raise ComposeReplayError(f"{label} is absent or not a regular file: {path}")
    digest, size = _sha256_file(path)
    if digest != record["sha256"] or size != record["bytes"]:
        raise ComposeReplayError(f"{label} differs from its recorded hash inventory")
    return {"path": name, "sha256": digest, "bytes": size}


def _validate_replay_root(replay_root: Path) -> dict[str, Any]:
    root = replay_root.resolve()
    if not root.is_dir():
        raise ComposeReplayError(f"replay output root is absent: {root}")
    receipt_path = root / REPLAY_RECEIPT
    inventory_path = root / REPLAY_INVENTORY
    receipt = _read_json(receipt_path, "replay comparison receipt")
    inventory = _read_json(inventory_path, "replay hash inventory")
    if receipt.get("kind") != "MIR5OfflineDiagnosticReplayV1":
        raise ComposeReplayError("replay comparison receipt has an unexpected kind")
    if receipt.get("schema") != 1:
        raise ComposeReplayError("replay comparison receipt has an unexpected schema")
    if receipt.get("status") != "generated-offline-diagnostic-not-native-evidence":
        raise ComposeReplayError("replay comparison receipt is not an offline diagnostic")
    claims = receipt.get("claims")
    if not isinstance(claims, dict) or any(claims.get(name) is not False for name in (
        "native_qualification", "player_package", "replay_execution",
    )):
        raise ComposeReplayError("replay comparison receipt has unsafe claims")
    if inventory.get("kind") != "MIR5OfflineDiagnosticReplayHashInventoryV1":
        raise ComposeReplayError("replay hash inventory has an unexpected kind")
    if inventory.get("schema") != 1:
        raise ComposeReplayError("replay hash inventory has an unexpected schema")

    published_mir = receipt.get("published_mir")
    if not isinstance(published_mir, dict):
        raise ComposeReplayError("replay comparison receipt lacks published MIR custody")
    if published_mir.get("name") != MOD_NAME or published_mir.get("version") != MOD_VERSION:
        raise ComposeReplayError("replay comparison receipt has an unexpected published MIR identity")
    published_mir_sha256 = _normalise_sha256(
        published_mir.get("sha256"), "replay comparison receipt published MIR SHA-256")

    receipt_outputs = _output_record_map(receipt.get("outputs"), "replay comparison receipt outputs")
    inventory_outputs = _output_record_map(inventory.get("outputs"), "replay hash inventory outputs")
    required_receipt = set(STAGE_ENTRYPOINTS)
    required_inventory = required_receipt | {REPLAY_RECEIPT}
    if set(receipt_outputs) != required_receipt:
        raise ComposeReplayError("replay comparison receipt does not record exactly six stage entrypoints")
    if set(inventory_outputs) != required_inventory:
        raise ComposeReplayError("replay hash inventory does not record the six stages and comparison receipt")

    generated: dict[str, dict[str, Any]] = {}
    for name in STAGE_ENTRYPOINTS:
        receipt_record = receipt_outputs[name]
        inventory_record = inventory_outputs[name]
        if receipt_record != inventory_record:
            raise ComposeReplayError(f"replay receipt and inventory disagree for {name}")
        generated[name] = _verify_recorded_file(root, name, receipt_record, f"generated stage {name}")
    receipt_record = inventory_outputs[REPLAY_RECEIPT]
    verified_receipt = _verify_recorded_file(root, REPLAY_RECEIPT, receipt_record, "replay comparison receipt")
    inventory_digest, inventory_size = _sha256_file(inventory_path)
    return {
        "root": root,
        "stages": generated,
        "comparison_receipt": verified_receipt,
        "hash_inventory": {"path": REPLAY_INVENTORY, "sha256": inventory_digest, "bytes": inventory_size},
        "published_mir": {"sha256": published_mir_sha256},
    }


def _member_parts(name: str) -> tuple[str, ...]:
    if not isinstance(name, str) or not name or "\\" in name or "//" in name:
        raise ComposeReplayError(f"archive has an unsafe member name: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} or ":" in part for part in path.parts):
        raise ComposeReplayError(f"archive has an unsafe member name: {name!r}")
    return path.parts


def _is_symlink(info: zipfile.ZipInfo) -> bool:
    return info.create_system == 3 and ((info.external_attr >> 16) & 0o170000) == 0o120000


def _validate_archive(archive_path: Path, expected_sha256: str) -> tuple[zipfile.ZipFile, list[zipfile.ZipInfo], dict[str, zipfile.ZipInfo]]:
    source = archive_path.resolve()
    if source.name != PUBLISHED_ARCHIVE_NAME:
        raise ComposeReplayError(f"published archive must use canonical filename: {PUBLISHED_ARCHIVE_NAME}")
    if not source.is_file() or source.is_symlink():
        raise ComposeReplayError(f"published archive is absent or not a regular file: {source}")
    expected = _normalise_sha256(expected_sha256, "expected published archive SHA-256")
    actual, _ = _sha256_file(source)
    if actual != expected:
        raise ComposeReplayError("published archive SHA-256 differs from the required expected SHA-256")
    try:
        archive = zipfile.ZipFile(source, "r")
    except (OSError, zipfile.BadZipFile) as error:
        raise ComposeReplayError(f"published archive is not a readable ZIP: {source}") from error
    try:
        infos = archive.infolist()
        if not infos:
            raise ComposeReplayError("published archive has no members")
        by_name: dict[str, zipfile.ZipInfo] = {}
        casefolded: set[str] = set()
        paths: set[tuple[str, ...]] = set()
        for info in infos:
            parts = _member_parts(info.filename)
            if info.is_dir() or _is_symlink(info) or info.flag_bits & 0x1:
                raise ComposeReplayError(f"published archive has an unsafe member: {info.filename}")
            if parts[0] != ARCHIVE_ROOT:
                raise ComposeReplayError(f"published archive root does not match {ARCHIVE_ROOT}: {info.filename}")
            if info.filename in by_name or info.filename.casefold() in casefolded:
                raise ComposeReplayError(f"published archive duplicates member: {info.filename}")
            for index in range(1, len(parts)):
                if parts[:index] in paths:
                    raise ComposeReplayError(f"published archive has ambiguous member hierarchy: {info.filename}")
            paths.add(parts)
            by_name[info.filename] = info
            casefolded.add(info.filename.casefold())
        info_member = by_name.get(f"{ARCHIVE_ROOT}/info.json")
        if info_member is None:
            raise ComposeReplayError("published archive lacks info.json")
        try:
            with archive.open(info_member, "r") as raw:
                info_json = json.load(io.TextIOWrapper(raw, encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, zipfile.BadZipFile) as error:
            raise ComposeReplayError("published archive info.json is not valid UTF-8 JSON") from error
        if not isinstance(info_json, dict) or info_json.get("name") != MOD_NAME or info_json.get("version") != MOD_VERSION:
            raise ComposeReplayError("published archive info.json does not retain the expected MIR 4.7 identity")
        return archive, infos, by_name
    except Exception:
        archive.close()
        raise


def _copy_info(info: zipfile.ZipInfo) -> zipfile.ZipInfo:
    copied = zipfile.ZipInfo(info.filename, date_time=info.date_time)
    copied.compress_type = info.compress_type
    copied.comment = info.comment
    copied.extra = info.extra
    copied.internal_attr = info.internal_attr
    copied.external_attr = info.external_attr
    copied.create_system = info.create_system
    copied.create_version = info.create_version
    copied.extract_version = info.extract_version
    copied.flag_bits = info.flag_bits
    return copied


def _new_stage_info(relative: str) -> zipfile.ZipInfo:
    created = zipfile.ZipInfo(f"{ARCHIVE_ROOT}/{relative}", date_time=(1980, 1, 1, 0, 0, 0))
    created.compress_type = zipfile.ZIP_DEFLATED
    return created


def _copy_stream(source: BinaryIO, destination: BinaryIO) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = source.read(CHUNK_BYTES)
        if not chunk:
            break
        destination.write(chunk)
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest().upper(), size


def _hash_member(archive: zipfile.ZipFile, info: zipfile.ZipInfo) -> tuple[str, int]:
    with archive.open(info, "r") as source:
        return _sha256_stream(source)


def _write_member(destination: zipfile.ZipFile, info: zipfile.ZipInfo, source: BinaryIO) -> tuple[str, int]:
    with destination.open(_copy_info(info), "w") as target:
        return _copy_stream(source, target)


def _safe_output_root(output_root: Path) -> Path:
    output = output_root.resolve()
    dist = (REPOSITORY_ROOT / "dist").resolve()
    if output == dist or dist in output.parents:
        raise ComposeReplayError("diagnostic output root must never be inside dist")
    if output.exists():
        raise ComposeReplayError(f"diagnostic output root must be fresh: {output}")
    if not output.parent.is_dir():
        raise ComposeReplayError(f"diagnostic output parent is absent: {output.parent}")
    return output


def compose_replay(published_archive: Path, expected_sha256: str, replay_root: Path, output_root: Path) -> dict[str, Any]:
    """Compose a private diagnostic ZIP and return its external custody receipt."""
    expected_archive_sha256 = _normalise_sha256(expected_sha256, "expected published archive SHA-256")
    replay = _validate_replay_root(replay_root)
    output = _safe_output_root(output_root)
    archive, infos, by_name = _validate_archive(published_archive, expected_archive_sha256)
    if replay["published_mir"]["sha256"] != expected_archive_sha256:
        archive.close()
        raise ComposeReplayError(
            "supplied published archive SHA-256 does not match the replay's published native-capture archive")
    source_path = published_archive.resolve()
    try:
        output.mkdir()
        archive_output = output / PUBLISHED_ARCHIVE_NAME
        changed_members: list[dict[str, Any]] = []
        unchanged_members: list[dict[str, Any]] = []
        with zipfile.ZipFile(archive_output, "x") as destination:
            for info in infos:
                member = info.filename
                relative = member[len(ARCHIVE_ROOT) + 1:]
                if relative in replay["stages"]:
                    prior_digest, prior_size = _hash_member(archive, info)
                    stage_path = replay["root"] / relative
                    with stage_path.open("rb") as replacement:
                        digest, size = _write_member(destination, info, replacement)
                    recorded = replay["stages"][relative]
                    if digest != recorded["sha256"] or size != recorded["bytes"]:
                        raise ComposeReplayError(f"generated stage changed while being composed: {relative}")
                    changed_members.append({
                        "path": member,
                        "change": "replaced",
                        "prior_sha256": prior_digest,
                        "prior_bytes": prior_size,
                        "sha256": digest,
                        "bytes": size,
                    })
                else:
                    with archive.open(info, "r") as source:
                        digest, size = _write_member(destination, info, source)
                    unchanged_members.append({"path": member, "sha256": digest, "bytes": size})
            for relative in STAGE_ENTRYPOINTS:
                member = f"{ARCHIVE_ROOT}/{relative}"
                if member in by_name:
                    continue
                stage_path = replay["root"] / relative
                with stage_path.open("rb") as replacement:
                    digest, size = _write_member(destination, _new_stage_info(relative), replacement)
                recorded = replay["stages"][relative]
                if digest != recorded["sha256"] or size != recorded["bytes"]:
                    raise ComposeReplayError(f"generated stage changed while being composed: {relative}")
                changed_members.append({
                    "path": member,
                    "change": "added",
                    "prior_sha256": None,
                    "prior_bytes": 0,
                    "sha256": digest,
                    "bytes": size,
                })
        output_digest, output_size = _sha256_file(archive_output)
        source_digest, source_size = _sha256_file(source_path)
        receipt = {
            "schema": 1,
            "kind": "MIR5OfflineDiagnosticReplayCompositionV1",
            "status": "composed-offline-diagnostic-nonrelease-not-native-execution",
            "claims": {
                "diagnostic": True,
                "release": False,
                "native_execution": False,
                "player_package": False,
            },
            "published_archive": {
                "path": str(source_path),
                "sha256": source_digest,
                "bytes": source_size,
                "root": ARCHIVE_ROOT,
                "name": MOD_NAME,
                "version": MOD_VERSION,
            },
            "replay": {
                "comparison_receipt": replay["comparison_receipt"],
                "hash_inventory": replay["hash_inventory"],
            },
            "output_archive": {"path": PUBLISHED_ARCHIVE_NAME, "sha256": output_digest, "bytes": output_size},
            "changed_members": sorted(changed_members, key=lambda row: row["path"].encode("utf-8")),
            "unchanged_members": sorted(unchanged_members, key=lambda row: row["path"].encode("utf-8")),
        }
        (output / COMPOSITION_RECEIPT).write_bytes(_json_bytes(receipt))
        return receipt
    except Exception:
        shutil.rmtree(output, ignore_errors=True)
        raise
    finally:
        archive.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--published-archive", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--replay-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        receipt = compose_replay(args.published_archive, args.expected_sha256, args.replay_root, args.output_root)
    except ComposeReplayError as error:
        print(f"[mir5-compose-replay] {error}", file=sys.stderr)
        return 2
    print(json.dumps({"status": receipt["status"], "output_root": str(args.output_root.resolve())}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

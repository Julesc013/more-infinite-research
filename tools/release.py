#!/usr/bin/env python3
"""Freeze and verify MIR 5 player assets locally; this never tags or publishes."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
import zlib


PACKAGE_PATH = Path(__file__).with_name("package.py")
PACKAGE_SPEC = importlib.util.spec_from_file_location("mir5_release_package", PACKAGE_PATH)
package = importlib.util.module_from_spec(PACKAGE_SPEC)
PACKAGE_SPEC.loader.exec_module(package)

KIND = "MIR5ReleaseAssetInventoryV1"
INVENTORY_NAME = KIND + ".json"
SUMS_NAME = "SHA256SUMS.txt"
TARGETS = ("f013", "f014", "f015", "f016", "f017", "f100", "f110", "f200", "f210")
EARLY_COHORT_KIND = "MIR5EarlyBestEffortAssetCohortV1"
EARLY_SUMS_NAME = "SHA256SUMS-early.txt"
EARLY_TARGETS = ("f006", "f007", "f008", "f009", "f010", "f011", "f012")
EARLY_QUALIFICATION = "best-effort-early-data-only-distributions-not-native-qualified"
MOD_NAME = "more-infinite-research"
SOURCE_VERSION = "5.0.0"
SOURCE_DISTRIBUTION_VERSION = "5.0.21000"
SOURCE_LABEL = "source5.0.0"
RELEASE_TAG = "v5.0.0"
RELEASE_TITLE = "MIR 5.0.0"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical_json(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"


def _controller_identity():
    """Name the local, offline packager controller without attributing it to player source."""
    return {
        "release_tool": {"path": "tools/release.py", "sha256": digest(Path(__file__).read_bytes())},
        "package_tool": {"path": "tools/package.py", "sha256": digest(PACKAGE_PATH.read_bytes())},
        "runtime": {
            "implementation": sys.implementation.name,
            "version": list(sys.version_info[:3]),
            "zlib_build_version": zlib.ZLIB_VERSION,
            "zlib_runtime_version": getattr(zlib, "ZLIB_RUNTIME_VERSION", zlib.ZLIB_VERSION),
        },
        "zip_policy": {
            "compression": "ZIP_DEFLATED",
            "compresslevel": 9,
            "member_timestamp": [1980, 1, 1, 0, 0, 0],
            "member_create_system": 3,
            "member_external_attr": 0o100644 << 16,
        },
    }


def _git(repository, *arguments):
    return subprocess.check_output(["git", "-C", str(repository), *arguments]).decode("utf-8").strip()


def _source_identity(source, revision):
    source, repository = package.git_repository(source)
    commit = _git(repository, "rev-parse", "--verify", revision + "^{commit}")
    relative = source.relative_to(repository).as_posix()
    tree = _git(repository, "rev-parse", commit + "^{tree}")
    source_tree = tree if relative == "." else _git(repository, "rev-parse", commit + ":" + relative)
    if _git(repository, "cat-file", "-t", source_tree) != "tree":
        raise ValueError("Frozen player source is not a tracked tree")
    frozen_commit, files = package.git_source(source, commit)
    if frozen_commit != commit:
        raise ValueError("Frozen player source commit changed during resolution")
    try:
        info = json.loads(files["info.json"].decode("utf-8"))
    except (KeyError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Frozen player source has invalid info.json") from error
    if (info.get("name") != MOD_NAME or info.get("version") != SOURCE_DISTRIBUTION_VERSION
            or not isinstance(info.get("title"), str) or not info["title"]):
        raise ValueError("Frozen player source is not the exact MIR 5.0.0 source identity")
    return source, repository, files, {
        "commit": commit,
        "tree": tree,
        "source_tree": source_tree,
        "path": relative,
        "mod_name": MOD_NAME,
        "mod_title": info["title"],
        "source_distribution_version": SOURCE_DISTRIBUTION_VERSION,
    }


def _target_identity(source, repository, commit, target_record):
    relative, raw = package.checked_target_record(source, target_record, commit)
    entry = _git(repository, "ls-tree", commit, "--", relative)
    try:
        metadata, name = entry.split("\t", 1)
        _, kind, blob = metadata.split()
    except ValueError as error:
        raise ValueError("Frozen target record has no ordinary tracked identity") from error
    if kind != "blob" or name != relative:
        raise ValueError("Frozen target record has no ordinary tracked identity")
    try:
        editions = json.loads(raw.decode("utf-8"))["targets"]
    except (UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise ValueError("Frozen target record is invalid") from error
    if set(editions) != set(TARGETS):
        raise ValueError("Frozen target record must declare exactly the nine MIR editions")
    for target in TARGETS:
        edition = editions[target]
        if not isinstance(edition, dict) or not edition.get("source_available"):
            raise ValueError("Frozen target record has an unavailable edition: " + target)
        if not isinstance(edition.get("factorio_version"), str) or not isinstance(edition.get("minimum_base"), str):
            raise ValueError("Frozen target record has invalid edition metadata: " + target)
    return editions, {
        "path": relative,
        "blob": blob,
        "sha256": digest(raw),
    }


def _early_target_identity(source, repository, commit, target_record):
    relative, raw = package.checked_target_record(source, target_record, commit)
    if relative != package.EARLY_TARGET_RECORD:
        raise ValueError("Early cohort requires the exact early target record")
    entry = _git(repository, "ls-tree", commit, "--", relative)
    try:
        metadata, name = entry.split("\t", 1)
        _, kind, blob = metadata.split()
        record = json.loads(raw.decode("utf-8"))
        editions = record["targets"]
    except (UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        raise ValueError("Frozen early target record is invalid") from error
    if kind != "blob" or name != relative:
        raise ValueError("Frozen early target record has no ordinary tracked identity")
    if (not isinstance(record, dict) or not isinstance(editions, dict)
            or record.get("schema") != 1 or record.get("qualification") != EARLY_QUALIFICATION
            or set(editions) != set(EARLY_TARGETS)):
        raise ValueError("Frozen early target record has an invalid cohort")
    for target in EARLY_TARGETS:
        edition = editions[target]
        if (not isinstance(edition, dict)
                or set(edition) != {"factorio_version", "minimum_base", "source_available", "delivery"}
                or edition.get("source_available") is not True
                or edition.get("delivery") not in {"extract-to-folder", "zip"}
                or not isinstance(edition.get("factorio_version"), str)
                or not isinstance(edition.get("minimum_base"), str)):
            raise ValueError("Frozen early target record has an invalid edition: " + target)
    return editions, {
        "path": relative,
        "blob": blob,
        "sha256": digest(raw),
    }


def _version(target):
    return "5.0." + target[1:] + "00"


def _archive_name(target):
    return MOD_NAME + "_" + _version(target) + ".zip"


def _asset(record, target, edition):
    path = Path(record["archive"])
    version = _version(target)
    root = MOD_NAME + "_" + version
    if (record.get("target") != target or record.get("name") != MOD_NAME
            or record.get("version") != version or path.name != _archive_name(target)):
        raise ValueError("Packager returned an unexpected MIR 5 asset identity")
    members = record.get("members")
    if not isinstance(members, list) or not members:
        raise ValueError("Packager returned no player members")
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            expected = [root + "/" + row["path"] for row in members]
            if names != expected or len(names) != len(set(names)):
                raise ValueError("Archive member identity differs from the frozen package")
            info = json.loads(archive.read(root + "/info.json").decode("utf-8"))
    except (OSError, zipfile.BadZipFile, KeyError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Archive has invalid frozen player metadata") from error
    dependencies = info.get("dependencies")
    if (info.get("name") != MOD_NAME or info.get("version") != version
            or info.get("factorio_version") != edition["factorio_version"]
            or not isinstance(dependencies, list) or not dependencies
            or dependencies[0] != "base >= " + edition["minimum_base"]):
        raise ValueError("Archive info.json differs from the declared edition")
    return {
        "target": target,
        "name": path.name,
        "version": version,
        "factorio_version": edition["factorio_version"],
        "minimum_base": edition["minimum_base"],
        "archive_sha256": record["sha256"],
        "bytes": record["bytes"],
        "root": root,
        "info": {
            "name": info["name"],
            "title": info.get("title"),
            "version": info["version"],
            "factorio_version": info["factorio_version"],
            "dependencies": info["dependencies"],
        },
        "members": members,
    }


def _early_asset(record, target, edition):
    if (record.get("kind") != "early-data-only-package-members-not-gameplay-qualification"
            or record.get("delivery") != edition["delivery"]):
        raise ValueError("Packager returned an unexpected early MIR asset cohort")
    asset = _asset(record, target, edition)
    asset["delivery"] = edition["delivery"]
    return asset


def _sums(assets):
    return "".join(asset["archive_sha256"] + " *" + asset["name"] + "\n" for asset in assets).encode("ascii")


def _body(source, target_record, controller, assets, sums, early_cohort=None):
    body = {
        "schema": 1,
        "kind": KIND,
        "release": {
            "source_version": SOURCE_VERSION,
            "source_label": SOURCE_LABEL,
            "tag": RELEASE_TAG,
            "title": RELEASE_TITLE,
        },
        "source": source,
        "target_record": target_record,
        "controller": controller,
        "assets": assets,
        "checksums": {"name": SUMS_NAME, "sha256": digest(sums), "bytes": len(sums)},
    }
    if early_cohort is not None:
        body["early_cohort"] = early_cohort
    return body


def _inventory_bytes(body):
    inventory = dict(body)
    inventory["inventory_sha256"] = digest(canonical_json(body))
    return canonical_json(inventory)


def _new_output(source, output):
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise FileExistsError("Preserve existing release output: " + str(output))
    _, repository = package.git_repository(source)
    try:
        output.resolve(strict=False).relative_to(repository)
    except ValueError:
        pass
    else:
        raise ValueError("Release output must not modify the source repository")
    output.mkdir(parents=True)
    return output


def _early_cohort_body(target_record, assets, sums):
    return {
        "kind": EARLY_COHORT_KIND,
        "qualification": EARLY_QUALIFICATION,
        "target_record": target_record,
        "assets": assets,
        "checksums": {"name": EARLY_SUMS_NAME, "sha256": digest(sums), "bytes": len(sums)},
    }


def _preflight_early_cohort(source, commit, target_record, editions):
    _, files = package.git_source(source, commit, include_early_locale=True)
    for target in EARLY_TARGETS:
        package.members(source, committed_files=files, target=target, editions=editions,
                        target_record=target_record["path"])


def _build_early_cohort(source, output, commit, target_record, editions):
    assets = []
    for target in EARLY_TARGETS:
        record = package.build(source, output / _archive_name(target), revision=commit,
                               target=target, target_record=target_record["path"])
        assets.append(_early_asset(record, target, editions[target]))
    if len({asset["target"] for asset in assets}) != len(EARLY_TARGETS):
        raise ValueError("Expected early release assets are not unique")
    sums = _sums(assets)
    (output / EARLY_SUMS_NAME).write_bytes(sums)
    return _early_cohort_body(target_record, assets, sums)


def freeze(source, output, revision="HEAD", target_record=package.TARGET_RECORD, early_target_record=None):
    """Build all nine committed player packages into one new, offline-only directory."""
    source, repository, _, source_identity = _source_identity(Path(source), revision)
    editions, target_identity = _target_identity(source, repository, source_identity["commit"], target_record)
    early_editions, early_identity = (None, None)
    if early_target_record is not None:
        early_editions, early_identity = _early_target_identity(
            source, repository, source_identity["commit"], early_target_record)
        _preflight_early_cohort(source, source_identity["commit"], early_identity, early_editions)
    controller = _controller_identity()
    output = _new_output(source, output)
    assets = []
    for target in TARGETS:
        record = package.build(source, output / _archive_name(target), revision=source_identity["commit"],
                               target=target, target_record=target_identity["path"])
        assets.append(_asset(record, target, editions[target]))
    sums = _sums(assets)
    (output / SUMS_NAME).write_bytes(sums)
    early_cohort = (None if early_identity is None else _build_early_cohort(
        source, output, source_identity["commit"], early_identity, early_editions))
    body = _body(source_identity, target_identity, controller, assets, sums, early_cohort)
    (output / INVENTORY_NAME).write_bytes(_inventory_bytes(body))
    return verify(source, output, target_record=target_identity["path"],
                  early_target_record=(None if early_identity is None else early_identity["path"]))


def _read_inventory(output):
    path = output / INVENTORY_NAME
    try:
        raw = path.read_bytes()
        inventory = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Release inventory is missing or invalid") from error
    if not isinstance(inventory, dict) or canonical_json(inventory) != raw:
        raise ValueError("Release inventory is not canonical")
    claimed = inventory.pop("inventory_sha256", None)
    if not isinstance(claimed, str) or claimed != digest(canonical_json(inventory)):
        raise ValueError("Release inventory self-digest differs")
    return inventory


def verify(source, output, target_record=None, early_target_record=None):
    """Verify an offline inventory against committed source and exact rebuilt packages."""
    source = Path(source)
    output = Path(output)
    inventory = _read_inventory(output)
    release = inventory.get("release")
    frozen_source = inventory.get("source")
    frozen_record = inventory.get("target_record")
    frozen_controller = inventory.get("controller")
    frozen_early = inventory.get("early_cohort")
    if (not isinstance(release, dict) or not isinstance(frozen_source, dict)
            or not isinstance(frozen_record, dict) or not isinstance(frozen_controller, dict)):
        raise ValueError("Release inventory is structurally invalid")
    if (frozen_early is not None
            and (not isinstance(frozen_early, dict)
                 or not isinstance(frozen_early.get("target_record"), dict))):
        raise ValueError("Release inventory has an invalid early cohort")
    if release != {"source_version": SOURCE_VERSION, "source_label": SOURCE_LABEL,
                   "tag": RELEASE_TAG, "title": RELEASE_TITLE}:
        raise ValueError("Release title, tag, or source version differs")
    if frozen_controller != _controller_identity():
        raise ValueError("Local release controller or compression runtime differs")
    record_path = frozen_record.get("path")
    if target_record is not None and package.target_record_path(target_record) != record_path:
        raise ValueError("Selected target record differs from the frozen inventory")
    if early_target_record is not None:
        if (frozen_early is None
                or package.target_record_path(early_target_record)
                != frozen_early.get("target_record", {}).get("path")):
            raise ValueError("Selected early target record differs from the frozen inventory")
    try:
        source, repository, _, source_identity = _source_identity(source, frozen_source["commit"])
        editions, target_identity = _target_identity(source, repository, source_identity["commit"], record_path)
        early_editions, early_identity = (None, None)
        if frozen_early is not None:
            early_path = frozen_early.get("target_record", {}).get("path")
            early_editions, early_identity = _early_target_identity(
                source, repository, source_identity["commit"], early_path)
    except (KeyError, TypeError, ValueError, subprocess.CalledProcessError) as error:
        raise ValueError("Frozen source or target record cannot be resolved") from error
    if frozen_source != source_identity or frozen_record != target_identity:
        raise ValueError("Frozen source or target record identity differs")
    if frozen_early is not None:
        if frozen_early.get("target_record") != early_identity:
            raise ValueError("Frozen early target record identity differs")
    expected_files = {_archive_name(target) for target in TARGETS} | {SUMS_NAME, INVENTORY_NAME}
    if frozen_early is not None:
        expected_files |= {_archive_name(target) for target in EARLY_TARGETS} | {EARLY_SUMS_NAME}
    try:
        actual_files = {path.name for path in output.iterdir()}
    except OSError as error:
        raise ValueError("Release output cannot be read") from error
    if actual_files != expected_files:
        raise ValueError("Release output has absent or extra assets")
    if any((output / name).is_symlink() for name in actual_files):
        raise ValueError("Release output contains linked assets")
    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        expected_assets = []
        for target in TARGETS:
            name = _archive_name(target)
            expected_record = package.build(source, temporary / name, revision=source_identity["commit"],
                                            target=target, target_record=target_identity["path"])
            actual = output / name
            if actual.read_bytes() != (temporary / name).read_bytes():
                raise ValueError("Archive bytes differ from the frozen source: " + name)
            expected_assets.append(_asset(expected_record, target, editions[target]))
        expected_early = None
        if frozen_early is not None:
            early_assets = []
            for target in EARLY_TARGETS:
                name = _archive_name(target)
                expected_record = package.build(source, temporary / name, revision=source_identity["commit"],
                                                target=target, target_record=early_identity["path"])
                actual = output / name
                if actual.read_bytes() != (temporary / name).read_bytes():
                    raise ValueError("Archive bytes differ from the frozen source: " + name)
                early_assets.append(_early_asset(expected_record, target, early_editions[target]))
            if len({asset["target"] for asset in early_assets}) != len(EARLY_TARGETS):
                raise ValueError("Expected early release assets are not unique")
            early_sums = _sums(early_assets)
            if (output / EARLY_SUMS_NAME).read_bytes() != early_sums:
                raise ValueError("Early checksum asset differs from the frozen archives")
            expected_early = _early_cohort_body(early_identity, early_assets, early_sums)
    if len({asset["target"] for asset in expected_assets}) != len(TARGETS):
        raise ValueError("Expected release assets are not unique")
    sums = _sums(expected_assets)
    if (output / SUMS_NAME).read_bytes() != sums:
        raise ValueError("Checksum asset differs from the frozen archives")
    expected = _body(source_identity, target_identity, frozen_controller, expected_assets, sums, expected_early)
    if inventory != expected:
        raise ValueError("Release inventory differs from frozen source or assets")
    return json.loads(_inventory_bytes(expected).decode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", default="HEAD", help="Committed source revision to freeze")
    parser.add_argument("--target-record", default=package.TARGET_RECORD)
    parser.add_argument("--early-target-record",
                        help="Opt in to the exact F006-F012 best-effort data-only cohort")
    parser.add_argument("--verify", action="store_true", help="Verify an existing offline inventory without building output")
    args = parser.parse_args()
    result = (verify(args.source, args.output, args.target_record, args.early_target_record) if args.verify
              else freeze(args.source, args.output, args.revision, args.target_record, args.early_target_record))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

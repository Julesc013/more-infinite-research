#!/usr/bin/env python3
"""Export one final Portal metadata copy from a completed extended MIR ZIP.

This is deliberately a post-package operation. It never reads player source
or selects an edition: it validates one completed, stable extended package and
creates a distinct copy whose only member-content changes are the two package
version literals required by the final Portal-copy contract.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


MIR_NAME = "more-infinite-research"
# Final-copy-only mapping: do not reuse this table as a source/package codec.
STABLE_PORTAL_EDITIONS = {
    "f013": 1,
    "f014": 2,
    "f015": 3,
    "f016": 4,
    "f017": 5,
    "f100": 6,
    "f110": 7,
    "f200": 8,
    "f210": 9,
}
EXTENDED_VERSION = re.compile(r"^(?P<major>\d+)\.(?P<minor>\d+)\.(?P<encoded>\d{5})$")
INFO_VERSION = re.compile(
    rb'"version"(?P<before>[ \t\r\n]*:[ \t\r\n]*")(?P<version>\d+\.\d+\.\d+)(?P<after>")'
)
TARGET_ID_ASSIGNMENT = re.compile(rb"(?m)^[ \t]*id[ \t]*=")
TARGET_ID = re.compile(
    rb'(?m)^[ \t]*id[ \t]*=[ \t]*"(?P<target>f\d{3})"[ \t]*,[ \t]*\r?$'
)
TARGET_VERSION_ASSIGNMENT = re.compile(rb"(?m)^[ \t]*distribution_version[ \t]*=")
TARGET_VERSION = re.compile(
    rb'(?m)^[ \t]*distribution_version[ \t]*=[ \t]*"(?P<version>\d+\.\d+\.\d+)"[ \t]*,[ \t]*\r?$'
)


class PortalExportError(ValueError):
    """A completed archive does not satisfy the final Portal-copy boundary."""


def _sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def _ordinary_input(path: Path) -> Path:
    if path.is_symlink() or not path.is_file() or path.suffix.lower() != ".zip":
        raise PortalExportError("Portal export input must be an ordinary ZIP file")
    return path.resolve(strict=True)


def _ordinary_output(path: Path) -> Path:
    if path.exists() or path.is_symlink():
        raise FileExistsError("Preserve existing Portal export output: " + str(path))
    if not path.parent.is_dir():
        raise PortalExportError("Portal export output parent must already exist")
    return path


def _member_root(name: str) -> str:
    if not isinstance(name, str) or not name or "\\" in name or name.startswith("/"):
        raise PortalExportError("Portal export archive has an invalid member path")
    pieces = name.split("/")
    if len(pieces) < 2 or any(not piece or piece in {".", ".."} or ":" in piece for piece in pieces):
        raise PortalExportError("Portal export archive has an invalid member path")
    return pieces[0]


def _replace_one(pattern: re.Pattern[bytes], payload: bytes, old: str, new: str, label: str) -> bytes:
    matches = list(pattern.finditer(payload))
    if len(matches) != 1 or matches[0].group("version").decode("ascii") != old:
        raise PortalExportError("Portal export has invalid " + label + " version metadata")
    match = matches[0]
    return payload[:match.start("version")] + new.encode("ascii") + payload[match.end("version"):]


def _read_completed_archive(path: Path, target: str, expected_version: str, expected_root: str):
    try:
        with zipfile.ZipFile(path) as archive:
            members = archive.infolist()
            if not members:
                raise PortalExportError("Portal export input has no members")
            names = [member.filename for member in members]
            if len(names) != len(set(names)):
                raise PortalExportError("Portal export input has duplicate member paths")
            roots = set()
            payloads = {}
            for member in members:
                if member.is_dir() or member.flag_bits & 0x1 or member.compress_type != zipfile.ZIP_DEFLATED:
                    raise PortalExportError("Portal export input has an unsupported member")
                roots.add(_member_root(member.filename))
                payloads[member.filename] = archive.read(member)
            if roots != {expected_root}:
                raise PortalExportError("Portal export archive root differs from its completed extended package")
            info_path = expected_root + "/info.json"
            target_path = expected_root + "/platform/target.lua"
            if info_path not in payloads or target_path not in payloads:
                raise PortalExportError("Portal export input lacks required package metadata")
            try:
                info = json.loads(payloads[info_path].decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise PortalExportError("Portal export info metadata is not valid JSON") from error
            if not isinstance(info, dict) or info.get("name") != MIR_NAME or info.get("version") != expected_version:
                raise PortalExportError("Portal export info metadata differs from the completed package")
            target_payload = payloads[target_path]
            ids = list(TARGET_ID.finditer(target_payload))
            versions = list(TARGET_VERSION.finditer(target_payload))
            if (len(TARGET_ID_ASSIGNMENT.findall(target_payload)) != 1
                    or len(TARGET_VERSION_ASSIGNMENT.findall(target_payload)) != 1
                    or len(ids) != 1 or len(versions) != 1
                    or ids[0].group("target").decode("ascii") != target
                    or versions[0].group("version").decode("ascii") != expected_version):
                raise PortalExportError("Portal export target metadata differs from the completed package")
            return members, payloads, archive.comment, info_path, target_path
    except zipfile.BadZipFile as error:
        raise PortalExportError("Portal export input is not a readable ZIP archive") from error


def _portal_version(target: str, extended_version: str) -> str:
    if target not in STABLE_PORTAL_EDITIONS:
        raise PortalExportError("Portal export accepts only the nine stable editions")
    match = EXTENDED_VERSION.fullmatch(extended_version)
    if match is None:
        raise PortalExportError("Portal export input does not use the completed extended codec")
    major, minor, encoded = (int(match.group("major")), int(match.group("minor")), int(match.group("encoded")))
    target_code = int(target[1:])
    if major > 65535 or minor > 65535 or encoded // 100 != target_code:
        raise PortalExportError("Portal export extended version selects a different edition")
    source_patch = encoded % 100
    third = 10 * source_patch + STABLE_PORTAL_EDITIONS[target]
    if third > 65535:
        raise PortalExportError("Portal export version component exceeds Factorio metadata limits")
    return f"{major}.{minor}.{third:02d}"


def _copied_zip_info(member: zipfile.ZipInfo) -> zipfile.ZipInfo:
    copied = zipfile.ZipInfo(member.filename, date_time=member.date_time)
    copied.comment = member.comment
    copied.extra = member.extra
    copied.internal_attr = member.internal_attr
    copied.external_attr = member.external_attr
    copied.create_system = member.create_system
    copied.create_version = member.create_version
    copied.extract_version = member.extract_version
    copied.flag_bits = member.flag_bits
    copied.compress_type = member.compress_type
    return copied


def export_portal_copy(input_archive: Path, target: str, output_archive: Path) -> dict:
    """Write one unqualified final Portal copy without regenerating player source."""
    input_archive = _ordinary_input(Path(input_archive))
    output_archive = _ordinary_output(Path(output_archive))
    if input_archive == output_archive.resolve(strict=False):
        raise PortalExportError("Portal export output must differ from its input")
    if target not in STABLE_PORTAL_EDITIONS:
        raise PortalExportError("Portal export accepts only the nine stable editions")

    name_prefix = MIR_NAME + "_"
    if not input_archive.name.startswith(name_prefix) or not input_archive.name.endswith(".zip"):
        raise PortalExportError("Portal export input filename is not a completed MIR package")
    expected_extended = input_archive.stem[len(name_prefix):]
    portal_version = _portal_version(target, expected_extended)
    expected_root = name_prefix + expected_extended
    expected_output_name = name_prefix + portal_version + ".zip"
    if output_archive.name != expected_output_name:
        raise PortalExportError("Portal export output filename must be " + expected_output_name)

    members, payloads, archive_comment, info_path, target_path = _read_completed_archive(
        input_archive, target, expected_extended, expected_root)
    updated = dict(payloads)
    updated[info_path] = _replace_one(INFO_VERSION, payloads[info_path], expected_extended, portal_version, "info.json")
    updated[target_path] = _replace_one(
        TARGET_VERSION, payloads[target_path], expected_extended, portal_version, "platform target")

    with output_archive.open("xb") as stream:
        with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as destination:
            destination.comment = archive_comment
            for member in members:
                destination.writestr(_copied_zip_info(member), updated[member.filename],
                                     compress_type=member.compress_type, compresslevel=9)

    output_members, output_payloads, output_comment, _, _ = _read_completed_archive(
        output_archive, target, portal_version, expected_root)
    if output_comment != archive_comment or [member.filename for member in output_members] != [member.filename for member in members]:
        raise PortalExportError("Portal export did not preserve archive member order and comment")
    changed = {info_path, target_path}
    for path, contents in payloads.items():
        if path not in changed and output_payloads[path] != contents:
            raise PortalExportError("Portal export changed an unapproved member: " + path)
    return {
        "schema": 1,
        "kind": "MIR5PortalCopyExportV1",
        "status": "exported-not-release-qualified",
        "target": target,
        "extended_version": expected_extended,
        "portal_version": portal_version,
        "root": expected_root,
        "input": {"path": str(input_archive), "sha256": _sha256_path(input_archive), "bytes": input_archive.stat().st_size},
        "output": {"path": str(output_archive.resolve()), "sha256": _sha256_path(output_archive), "bytes": output_archive.stat().st_size},
        "permitted_member_differences": [
            {"path": path, "before_sha256": _sha256(payloads[path]), "after_sha256": _sha256(output_payloads[path])}
            for path in (info_path, target_path)
        ],
    }


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Completed extended-version MIR player ZIP")
    parser.add_argument("--target", required=True, choices=sorted(STABLE_PORTAL_EDITIONS))
    parser.add_argument("--output", type=Path, required=True, help="New final Portal-copy ZIP path")
    return parser.parse_args(argv)


def main(argv=None):
    arguments = parse_arguments(argv)
    print(json.dumps(export_portal_copy(arguments.input, arguments.target, arguments.output), indent=2))


if __name__ == "__main__":
    main()

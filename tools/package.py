#!/usr/bin/env python3
"""Build an explicitly selected native player/fixture root; never infer research."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

TARGET_RECORD = "targets/editions.json"
EARLY_TARGET_RECORD = "targets/early-editions.json"
REQUIRE = re.compile(r'''\brequire\s*\(\s*["']([^"']+)["']\s*\)''')
ENTRYPOINTS = ("data.lua", "settings.lua", "data-final-fixes.lua", "control.lua")
F210_ONLY_MIGRATION = "migrations/more-infinite-research_4.7.0.json"
F110_PLUS_MIGRATION = "migrations/more-infinite-research_5.0.11000.json"
F110_PLUS_MIGRATION_TARGETS = frozenset({"f110", "f200", "f210"})
EARLY_TARGET_IDS = frozenset({"f006", "f007", "f008", "f009", "f010", "f011", "f012"})
EARLY_LOCALE_SOURCE = "adapters/early/locale/en/more-infinite-research.cfg"
EARLY_LOCALE_OUTPUT = "locale/en/more-infinite-research.cfg"
EARLY_DESCRIPTION = ("Adds fixed finite default continuations of selected research bonus lines for museum "
                     "Factorio releases; it has no configurable startup settings.")
MIR_PLAYER_NAME = "more-infinite-research"
SOURCE_TARGET_PATH = "platform/target.lua"
SOURCE_TARGET_ID_ASSIGNMENT = re.compile(rb'(?m)^[ \t]*id[ \t]*=')
SOURCE_TARGET_ID = re.compile(rb'(?m)^[ \t]*id[ \t]*=[ \t]*"(?P<id>f\d{3})"[ \t]*,[ \t]*\r?$')
SOURCE_DISTRIBUTION_VERSION_ASSIGNMENT = re.compile(rb'(?m)^[ \t]*distribution_version[ \t]*=')
SOURCE_DISTRIBUTION_VERSION = re.compile(
    rb'(?m)^[ \t]*distribution_version[ \t]*=[ \t]*"(?P<version>\d+\.\d+\.\d{5})"[ \t]*,[ \t]*\r?$')
CODEC_VERSION = re.compile(r"^(?P<major>\d+)\.(?P<minor>\d+)\.(?P<encoded>\d{5})$")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def admitted(relative):
    path = Path(relative)
    if any(part in {"tests", "tools", "docs", "sdk", "fixtures", "build", "dist"}
           or part.startswith(".") for part in path.parts):
        return False
    return (relative in {"info.json", "LICENSE", "LICENSE.txt", "changelog.txt", "thumbnail.png"}
            or path.suffix == ".lua"
            or (len(path.parts) == 2 and path.parts[0] == "migrations" and path.suffix == ".json")
            or (relative.startswith("locale/") and path.suffix == ".cfg")
            or (relative.startswith("graphics/") and path.suffix.lower() in {".png", ".jpg", ".ogg"}))


def target_record_path(value):
    """Return one unambiguous, repository-relative target record path."""
    try:
        raw = os.fspath(value)
    except TypeError as error:
        raise ValueError("Target record must be a repository path") from error
    if not isinstance(raw, str) or not raw or "\x00" in raw:
        raise ValueError("Target record must be a repository path")
    portable = raw.replace("\\", "/")
    parts = portable.split("/")
    if (portable.startswith("/") or re.match(r"^[A-Za-z]:", portable)
            or any(part in {"", ".", ".."} for part in parts)
            or parts[0] != "targets" or not parts[-1].endswith(".json")):
        raise ValueError("Target record must be an unambiguous targets/*.json repository path")
    return "/".join(parts)


def git_repository(source):
    source = Path(source).resolve(strict=True)
    repository = Path(subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "--show-toplevel"]).decode().strip()).resolve()
    try:
        source.relative_to(repository)
    except ValueError as error:
        raise ValueError("Package source must be inside its Git repository") from error
    return source, repository


def checked_target_record(source, target_record, revision=None):
    """Read a tracked target record without mixing a frozen source with local metadata."""
    source, repository = git_repository(source)
    relative = target_record_path(target_record)
    pieces = relative.split("/")
    current = repository
    for piece in pieces:
        current /= piece
        if current.is_symlink() or (hasattr(current, "is_junction") and current.is_junction()):
            raise ValueError("Linked target record path is not admitted")
    try:
        current.resolve(strict=True).relative_to(repository)
    except (FileNotFoundError, ValueError) as error:
        raise ValueError("Selected target record is not an ordinary repository file") from error
    if not current.is_file():
        raise ValueError("Selected target record is not an ordinary repository file")

    commit = revision
    if commit is None:
        commit = subprocess.check_output(
            ["git", "-C", str(repository), "rev-parse", "--verify", "HEAD^{commit}"]).decode().strip()
    else:
        commit = subprocess.check_output(
            ["git", "-C", str(repository), "rev-parse", "--verify", commit + "^{commit}"]).decode().strip()
        status = subprocess.check_output(
            ["git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all", "--", relative])
        if status:
            raise ValueError("Selected target record differs from the frozen revision")
    tree = subprocess.check_output(
        ["git", "-C", str(repository), "ls-tree", "-z", commit, "--", relative])
    entries = [entry for entry in tree.split(b"\0") if entry]
    if len(entries) != 1:
        raise ValueError("Selected target record is not tracked at the selected revision")
    metadata, name = entries[0].split(b"\t", 1)
    mode, kind, _ = metadata.split()
    if (name.decode("utf-8") != relative or kind != b"blob"
            or mode not in (b"100644", b"100755")):
        raise ValueError("Selected target record is not an ordinary tracked file")
    if revision is None:
        return relative, current.read_bytes()
    return relative, subprocess.check_output(
        ["git", "-C", str(repository), "show", commit + ":" + relative])


def git_source(source, revision, include_early_locale=False):
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(source), *arguments])
    source, repository = git_repository(source)
    relative = source.relative_to(repository).as_posix()
    commit = git("rev-parse", "--verify", revision + "^{commit}").decode().strip()
    prefix = relative + "/" if relative != "." else ""
    entries = git("ls-tree", "-rz", "--full-tree", commit, "--", relative).split(b"\0")
    records = []
    for entry in filter(None, entries):
        metadata, name = entry.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        name = name.decode("utf-8")
        if kind != b"blob" or mode not in (b"100644", b"100755") or not name.startswith(prefix):
            raise ValueError("Committed package source must contain ordinary files only")
        relative_name = name[len(prefix):]
        if admitted(relative_name) or (include_early_locale and relative_name == EARLY_LOCALE_SOURCE):
            records.append((relative_name, oid))
    if not any(name == "info.json" for name, _ in records):
        raise ValueError("Selected committed source has no info.json")
    process = subprocess.run(["git", "-C", str(repository), "cat-file", "--batch"],
                             input=b"".join(oid + b"\n" for _, oid in records), capture_output=True, check=True)
    cursor, files = 0, {}
    for name, oid in records:
        end = process.stdout.index(b"\n", cursor)
        actual_oid, kind, size = process.stdout[cursor:end].split()
        if actual_oid != oid or kind != b"blob":
            raise ValueError("Committed source blob identity differs")
        cursor = end + 1
        files[name] = process.stdout[cursor:cursor + int(size)]
        cursor += int(size) + 1
    return commit, files


def read_editions(source, revision=None, target_record=TARGET_RECORD):
    _, data = checked_target_record(source, target_record, revision)
    record = json.loads(data.decode("utf-8"))
    if record.get("schema") != 1 or not isinstance(record.get("targets"), dict):
        raise ValueError("Invalid edition record")
    return record["targets"], digest(data)


def source_changelog_version(version):
    """Decode the retained extended codec only for a unified source header."""
    if not isinstance(version, str):
        raise ValueError("Player presentation requires a distribution codec")
    match = CODEC_VERSION.fullmatch(version)
    if match is None:
        raise ValueError("Player presentation requires a distribution codec")
    return (match.group("major") + "." + match.group("minor")
            + "." + str(int(match.group("encoded")) % 100))


def player_presentation(files, info):
    for required in ("LICENSE", "thumbnail.png", "changelog.txt"):
        if not files.get(required):
            raise ValueError("Selected edition has missing player presentation: " + required)
    entry = files["changelog.txt"]
    token = b"@DISTRIBUTION_VERSION@"
    header = (b"Version: " + source_changelog_version(info["version"]).encode("ascii") + b"\n")
    if token in entry or entry.count(header) != 1:
        raise ValueError("Current changelog needs exactly one source-version header")
    out = {name: raw for name, raw in files.items() if not name.startswith("presentation/changelog/")}
    return out


def render_local_mir_target_version(files, source_version, requested_version, name):
    """Keep the runtime version aligned for a generic local MIR package.

    This is deliberately narrower than selected-edition materialization: it
    validates and replaces the one authored source literal, preserving every
    other Lua byte for a same-edition local package.
    """
    if name != MIR_PLAYER_NAME:
        return files
    if SOURCE_TARGET_PATH not in files:
        raise ValueError("MIR local version package has no source target metadata")
    if not isinstance(source_version, str) or not isinstance(requested_version, str):
        raise ValueError("MIR local version package has an invalid distribution codec")
    source_match = CODEC_VERSION.fullmatch(source_version)
    requested_match = CODEC_VERSION.fullmatch(requested_version)
    if source_match is None or requested_match is None:
        raise ValueError("MIR local version package has an invalid distribution codec")

    target = files[SOURCE_TARGET_PATH]
    ids = list(SOURCE_TARGET_ID.finditer(target))
    versions = list(SOURCE_DISTRIBUTION_VERSION.finditer(target))
    if (len(SOURCE_TARGET_ID_ASSIGNMENT.findall(target)) != 1
            or len(SOURCE_DISTRIBUTION_VERSION_ASSIGNMENT.findall(target)) != 1
            or len(ids) != 1 or len(versions) != 1):
        raise ValueError("MIR local version package has invalid source target metadata")
    target_id = ids[0].group("id").decode("ascii")
    target_version = versions[0].group("version").decode("ascii")
    if target_version != source_version:
        raise ValueError("MIR local version package has mismatched source target metadata")
    target_codec = int(target_id[1:])
    if int(source_match.group("encoded")) // 100 != target_codec:
        raise ValueError("MIR local version package has mismatched source target codec")
    if int(requested_match.group("encoded")) // 100 != target_codec:
        raise ValueError("Local distribution version selects a different MIR edition")

    rendered = dict(files)
    match = versions[0]
    rendered[SOURCE_TARGET_PATH] = (target[:match.start("version")]
                                    + requested_version.encode("ascii")
                                    + target[match.end("version"):])
    entry = files.get("changelog.txt")
    if entry is not None:
        old = b"Version: " + source_changelog_version(source_version).encode("ascii") + b"\n"
        if b"@DISTRIBUTION_VERSION@" in entry or entry.count(old) != 1:
            raise ValueError("MIR local version package has invalid source changelog")
        rendered["changelog.txt"] = entry.replace(
            old, b"Version: " + source_changelog_version(requested_version).encode("ascii") + b"\n", 1)
    return rendered


def require_closure(files, pending):
    """Resolve exact Lua imports from explicit entrypoints only."""
    closure = set()
    while pending:
        relative = pending.pop()
        if relative in closure:
            continue
        if relative not in files:
            raise ValueError("Selected edition has a missing source dependency: " + relative)
        closure.add(relative)
        for module in REQUIRE.findall(files[relative].decode("utf-8")):
            if module.startswith("__more-infinite-research__/"):
                module = module[len("__more-infinite-research__/"):]
            dependency = module.replace(".", "/") + ".lua"
            if ".." in dependency or dependency.startswith("/"):
                raise ValueError("Invalid player module dependency")
            pending.append(dependency)
    return closure


def select_edition(files, info, target, editions):
    if info.get("name") != "more-infinite-research" or target not in editions:
        raise ValueError("Select a declared MIR player edition")
    selected = editions[target]
    if not selected.get("source_available"):
        raise ValueError("Edition source adaptation remains incomplete: " + target)
    if not re.fullmatch(r"f\d{3}", target):
        raise ValueError("Invalid target codec")
    source_targets = [key for key, value in editions.items()
                      if value["factorio_version"] == info.get("factorio_version")]
    if len(source_targets) != 1:
        raise ValueError("Source metadata has no unique declared edition")
    major, minor, encoded = info["version"].split(".")
    if len(encoded) != 5 or int(encoded) // 100 != int(source_targets[0][1:]):
        raise ValueError("Source version does not use the declared distribution codec")
    info["version"] = major + "." + minor + "." + str(int(target[1:]) * 100 + int(encoded) % 100).zfill(5)
    info["factorio_version"] = selected["factorio_version"]
    dependencies = info.get("dependencies", [])
    extras = [item for item in dependencies if not re.match(r"^\s*base(?:\s|[<>=!]|$)", item)]
    # Reduced published editions have no optional integration ordering. The
    # 2.0 target retains its own DLC minima and lacks the 2.1 K2SO adapter.
    extras = [] if selected["reduced"] else selected.get("optional_dependencies", extras)
    if not isinstance(extras, list) or any(not isinstance(item, str) for item in extras):
        raise ValueError("Invalid target dependency metadata")
    info["dependencies"] = ["base >= " + selected["minimum_base"]] + extras
    metadata = {key: selected[key] for key in (
        "factorio_version", "minimum_base", "reduced", "research_levels", "recipe_productivity",
        "recipe_probability", "productivity_ignores_stats", "receiver_limits", "cargo_research")}
    metadata.update(id=target, distribution_version=info["version"])
    files = dict(files)
    fields = []
    for key, value in metadata.items():
        literal = str(value).lower() if isinstance(value, bool) else json.dumps(value)
        fields.append("  " + key + " = " + literal)
    files["platform/target.lua"] = ("-- Selected edition metadata; qualification is held outside player source.\nreturn {\n"
        + ",\n".join(fields) + "\n}\n").encode("utf-8")
    if selected["reduced"]:
        for entrypoint in ENTRYPOINTS:
            module = "adapters.reduced." + entrypoint[:-4]
            files[entrypoint] = ('require("' + module + '").apply()\n').encode("utf-8")

    # Follow the actual selected stage/public API imports. A reduced package
    # never ships another edition's unused compiler, GUI or runtime body.
    closure = require_closure(files, [*ENTRYPOINTS, "api/v1/data.lua", "api/v1/runtime.lua", "platform/target.lua"])
    selected_files = {name: data for name, data in files.items() if not name.endswith(".lua") or name in closure}
    return player_presentation(selected_files, info)


def select_early_edition(files, info, target, editions):
    """Materialize the intentionally data-only F006--F012 compatibility package."""
    if info.get("name") != "more-infinite-research" or target not in EARLY_TARGET_IDS:
        raise ValueError("Select a declared early MIR player edition")
    selected = editions.get(target)
    required = {"factorio_version", "minimum_base", "source_available", "delivery"}
    if not isinstance(selected, dict) or set(selected) != required:
        raise ValueError("Invalid early target metadata: " + target)
    if selected["source_available"] is not True:
        raise ValueError("Early edition source adaptation remains incomplete: " + target)
    if selected["delivery"] not in {"extract-to-folder", "zip"}:
        raise ValueError("Invalid early delivery mode: " + target)
    if not re.fullmatch(r"0[.]\d+", selected["factorio_version"]):
        raise ValueError("Invalid early Factorio line: " + target)
    if not re.fullmatch(r"\d+[.]\d+[.]\d+", selected["minimum_base"]):
        raise ValueError("Invalid early base minimum: " + target)
    if selected["factorio_version"] != "0." + str(int(target[1:])):
        raise ValueError("Early target and Factorio line differ: " + target)

    version = info.get("version")
    match = re.fullmatch(r"(\d+)[.](\d+)[.](\d{5})", version if isinstance(version, str) else "")
    if match is None:
        raise ValueError("Source version does not use the declared distribution codec")
    patch = int(match.group(3)) % 100
    info.clear()
    info.update({
        "name": "more-infinite-research",
        "version": match.group(1) + "." + match.group(2) + "." + str(int(target[1:]) * 100 + patch).zfill(5),
        "title": "More Infinite Research",
        "author": "Julesc013",
        "description": EARLY_DESCRIPTION,
        "factorio_version": selected["factorio_version"],
        "dependencies": ["base >= " + selected["minimum_base"]],
    })
    files = dict(files)
    fields = (
        "-- Selected early data-only target; native qualification is held outside player source.\n"
        "return {\n"
        "  id = " + json.dumps(target) + ",\n"
        "  reduced = true,\n"
        "  research_levels = false,\n"
        "  recipe_productivity = false\n"
        "}\n"
    )
    files["platform/target.lua"] = fields.encode("utf-8")
    files["data.lua"] = b'require("adapters.early.data").apply(require("platform.target"))\n'
    closure = require_closure(files, ["data.lua", "platform/target.lua"])
    selected_files = {name: files[name] for name in closure}
    for required in ("info.json", "LICENSE", "thumbnail.png", "changelog.txt", EARLY_LOCALE_SOURCE):
        if required not in files:
            raise ValueError("Selected early edition has missing player asset: " + required)
    selected_files["info.json"] = files["info.json"]
    selected_files["LICENSE"] = files["LICENSE"]
    selected_files["thumbnail.png"] = files["thumbnail.png"]
    selected_files["changelog.txt"] = files["changelog.txt"]
    selected_files[EARLY_LOCALE_OUTPUT] = files[EARLY_LOCALE_SOURCE]
    return player_presentation(selected_files, info)


def members(source, version=None, committed_files=None, target=None, editions=None,
            target_record=TARGET_RECORD):
    selected_record = target_record_path(target_record)
    if target is None and selected_record != TARGET_RECORD:
        raise ValueError("Target record selection requires a declared target")
    if committed_files is None:
        committed_files = {}
        include_early_locale = target is not None and selected_record == EARLY_TARGET_RECORD
        for path in sorted(source.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Linked source is not admitted: {path}")
            relative = path.relative_to(source).as_posix()
            if path.is_file() and (admitted(relative) or (include_early_locale and relative == EARLY_LOCALE_SOURCE)):
                committed_files[relative] = path.read_bytes()
    if "info.json" not in committed_files:
        raise ValueError("Selected source has no info.json")
    info = json.loads(committed_files["info.json"].decode("utf-8"))
    source_version = info.get("version")
    if version is not None:
        info["version"] = version
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", info["name"]):
        raise ValueError("Invalid mod name")
    if not re.fullmatch(r"\d+\.\d+\.\d+", info["version"]):
        raise ValueError("Invalid Factorio distribution version")
    if target is not None:
        if version is not None:
            raise ValueError("Selected player editions derive their version from the source codec")
        if editions is None:
            editions, _ = read_editions(source, target_record=selected_record)
        if selected_record == EARLY_TARGET_RECORD:
            committed_files = select_early_edition(committed_files, info, target, editions)
        else:
            committed_files = select_edition(committed_files, info, target, editions)
        # Published 4.7.3 shipped the K2 Imersite rename only in its F210
        # edition.  Preserve that migration-name history for every other selected
        # player package without narrowing generic fixture archives.
        if selected_record != EARLY_TARGET_RECORD and target != "f210":
            committed_files.pop(F210_ONLY_MIGRATION, None)
        # F018/F100 retain the legacy laser continuation identity.  The
        # canonical rename starts at F110 and remains in later normal targets;
        # early packages are data-only and have no migration members.
        if selected_record != EARLY_TARGET_RECORD and target not in F110_PLUS_MIGRATION_TARGETS:
            committed_files.pop(F110_PLUS_MIGRATION, None)
    else:
        if version is not None:
            committed_files = render_local_mir_target_version(
                committed_files, source_version, info["version"], info["name"])
        if "changelog.txt" in committed_files:
            committed_files = player_presentation(committed_files, info)
    rows = []
    for relative, contents in sorted(committed_files.items()):
        if admitted(relative):
            if relative == "info.json" and (version is not None or target is not None):
                contents = (json.dumps(info, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
            rows.append((relative, contents))
    return info, rows


def build(source, output, version=None, revision=None, target=None, target_record=TARGET_RECORD):
    selected_record = target_record_path(target_record)
    if target is None and selected_record != TARGET_RECORD:
        raise ValueError("Target record selection requires a declared target")
    if source.is_symlink() or (hasattr(source, "is_junction") and source.is_junction()):
        raise ValueError("Select an ordinary source root, not a filesystem link")
    source = source.resolve(strict=True)
    if not source.is_dir() or source.is_symlink():
        raise ValueError("Select an ordinary existing source root")
    early = target is not None and selected_record == EARLY_TARGET_RECORD
    commit, files = (git_source(source, revision, include_early_locale=early)
                     if revision is not None else (None, None))
    record_path = selected_record if target is not None else None
    editions, editions_sha = (read_editions(source, commit, record_path)
                              if target is not None else (None, None))
    info, rows = members(source, version, files, target, editions, record_path or TARGET_RECORD)
    root = f"{info['name']}_{info['version']}"
    expected_name = root + ".zip"
    if not early and output.name != expected_name:
        raise ValueError(f"Archive must be named {expected_name}")
    if output.exists():
        raise FileExistsError(f"Preserve existing package: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream, zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, contents in rows:
            member = zipfile.ZipInfo(root + "/" + relative, date_time=(1980, 1, 1, 0, 0, 0))
            member.create_system = 3
            member.external_attr = 0o100644 << 16
            member.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(member, contents, compresslevel=9)
    return {
        "kind": ("early-data-only-package-members-not-gameplay-qualification"
                 if early else "native-package-members-not-gameplay-qualification"),
        "source_root": str(source), "archive": str(output.resolve()),
        "source_commit": commit,
        "target": target, "target_record": record_path, "edition_record_sha256": editions_sha,
        "name": info["name"], "version": info["version"],
        **({"delivery": editions[target]["delivery"]} if early else {}),
        "sha256": digest(output.read_bytes()), "bytes": output.stat().st_size,
        "members": [{"path": relative, "sha256": digest(contents), "bytes": len(contents)} for relative, contents in rows],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--record", type=Path)
    parser.add_argument("--version", help="Explicit target/fixture metadata version; never a product packaging retry counter")
    parser.add_argument("--revision", help="Read exact committed blobs, excluding dirty and untracked development work")
    parser.add_argument("--target", help="Select an implemented edition; this is not native qualification")
    parser.add_argument("--target-record", default=TARGET_RECORD,
                        help="Tracked targets/*.json selection record, frozen with --revision")
    args = parser.parse_args()
    record = build(args.source, args.output, args.version, args.revision, args.target, args.target_record)
    if args.record:
        args.record.parent.mkdir(parents=True, exist_ok=True)
        with args.record.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(record, stream, indent=2)
            stream.write("\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()

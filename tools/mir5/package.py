#!/usr/bin/env python3
"""Build an explicitly selected native player/fixture root; never infer research."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def admitted(relative):
    path = Path(relative)
    if any(part in {"tests", "tools", "docs", "sdk", "fixtures", "build", "dist"}
           or part.startswith(".") for part in path.parts):
        return False
    return (relative in {"info.json", "LICENSE", "LICENSE.txt", "changelog.txt"}
            or path.suffix == ".lua"
            or (relative.startswith("locale/") and path.suffix == ".cfg")
            or (relative.startswith("graphics/") and path.suffix.lower() in {".png", ".jpg", ".ogg"}))


def git_source(source, revision):
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(source), *arguments])
    repository = Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve()
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
        if admitted(relative_name):
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


def members(source, version=None, committed_files=None):
    if committed_files is None:
        committed_files = {}
        for path in sorted(source.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Linked source is not admitted: {path}")
            relative = path.relative_to(source).as_posix()
            if path.is_file() and admitted(relative):
                committed_files[relative] = path.read_bytes()
    if "info.json" not in committed_files:
        raise ValueError("Selected source has no info.json")
    info = json.loads(committed_files["info.json"].decode("utf-8"))
    if version is not None:
        info["version"] = version
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", info["name"]):
        raise ValueError("Invalid mod name")
    if not re.fullmatch(r"\d+\.\d+\.\d+", info["version"]):
        raise ValueError("Invalid Factorio distribution version")
    rows = []
    for relative, contents in sorted(committed_files.items()):
        if admitted(relative):
            if relative == "info.json" and version is not None:
                contents = (json.dumps(info, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
            rows.append((relative, contents))
    return info, rows


def build(source, output, version=None, revision=None):
    if source.is_symlink() or (hasattr(source, "is_junction") and source.is_junction()):
        raise ValueError("Select an ordinary source root, not a filesystem link")
    source = source.resolve(strict=True)
    if not source.is_dir() or source.is_symlink():
        raise ValueError("Select an ordinary existing source root")
    commit, files = git_source(source, revision) if revision is not None else (None, None)
    info, rows = members(source, version, files)
    root = f"{info['name']}_{info['version']}"
    expected_name = root + ".zip"
    if output.name != expected_name:
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
        "kind": "native-package-members-not-gameplay-qualification",
        "source_root": str(source), "archive": str(output.resolve()),
        "source_commit": commit,
        "name": info["name"], "version": info["version"],
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
    args = parser.parse_args()
    record = build(args.source, args.output, args.version, args.revision)
    if args.record:
        args.record.parent.mkdir(parents=True, exist_ok=True)
        with args.record.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(record, stream, indent=2)
            stream.write("\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()

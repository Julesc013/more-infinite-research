#!/usr/bin/env python3
"""Build an explicitly selected native player/fixture root; never infer research."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def members(source, version=None):
    info = json.loads((source / "info.json").read_text(encoding="utf-8"))
    if version is not None:
        info["version"] = version
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", info["name"]):
        raise ValueError("Invalid mod name")
    if not re.fullmatch(r"\d+\.\d+\.\d+", info["version"]):
        raise ValueError("Invalid Factorio distribution version")
    rows = []
    for path in sorted(source.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Linked source is not admitted: {path}")
        if not path.is_file():
            continue
        relative = path.relative_to(source).as_posix()
        if any(part in {"tests", "tools", "docs", "sdk", "fixtures", "build", "dist"} or part.startswith(".") for part in path.relative_to(source).parts):
            continue
        allowed = relative in {"info.json", "LICENSE", "LICENSE.txt", "changelog.txt"}
        allowed = allowed or path.suffix == ".lua"
        allowed = allowed or (relative.startswith("locale/") and path.suffix == ".cfg")
        allowed = allowed or (relative.startswith("graphics/") and path.suffix.lower() in {".png", ".jpg", ".ogg"})
        if allowed:
            contents = path.read_bytes()
            if relative == "info.json" and version is not None:
                contents = (json.dumps(info, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
            rows.append((relative, contents))
    return info, rows


def build(source, output, version=None):
    if source.is_symlink() or (hasattr(source, "is_junction") and source.is_junction()):
        raise ValueError("Select an ordinary source root, not a filesystem link")
    source = source.resolve(strict=True)
    if not source.is_dir() or source.is_symlink():
        raise ValueError("Select an ordinary existing source root")
    info, rows = members(source, version)
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
    args = parser.parse_args()
    record = build(args.source, args.output, args.version)
    if args.record:
        args.record.parent.mkdir(parents=True, exist_ok=True)
        with args.record.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(record, stream, indent=2)
            stream.write("\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()

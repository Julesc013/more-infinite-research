"""Verify anonymous GitHub release downloads and deliver the exact frozen files."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote
from urllib.request import Request, urlopen

import release


REPOSITORY = "Julesc013/more-infinite-research"
API = f"https://api.github.com/repos/{REPOSITORY}/"
ORIGIN = re.compile(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)"
                    + re.escape(REPOSITORY) + r"(?:\.git)?/?", re.IGNORECASE)
SHA256 = re.compile(r"[0-9a-fA-F]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")


def _git(primary, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=primary, timeout=30,
                                   env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})


def _git_text(primary, *arguments):
    return _git(primary, *arguments).decode("utf-8").strip()


def _primary_revision(primary):
    root = _git_text(primary, "rev-parse", "--show-toplevel")
    origin = _git_text(primary, "remote", "get-url", "origin")
    branch = _git_text(primary, "branch", "--show-current")
    if Path(root).resolve() != primary or not ORIGIN.fullmatch(origin) or not branch:
        raise ValueError("The primary checkout must be on a branch of the canonical repository")
    head = _git_text(primary, "rev-parse", "HEAD")
    ref = f"refs/heads/{branch}"
    remote = _git_text(primary, "ls-remote", "--heads", "origin", ref).split()
    if _git(primary, "status", "--porcelain=v1", "--untracked-files=normal") or remote != [head, ref]:
        raise ValueError("The primary checkout must be clean and equal to its remote branch")
    return head


def _notes(primary, commit, title):
    tagged = _git(primary, "show", f"{commit}:docs/release-notes.md")
    upload = _git(primary, "show", f"{commit}:docs/upload-text.txt")
    front_matter = re.match(rb"\A---\r?\n(?P<metadata>.*?)\r?\n---(?:\r?\n|\Z)", tagged, re.DOTALL)
    notes = tagged[front_matter.end():].lstrip(b"\r\n") if front_matter else tagged
    if front_matter:
        declared = re.findall(rb'''(?m)^(?:title|applies_to):[ \t]*["']?(MIR [0-9]+\.[0-9]+\.[0-9]+)\b''',
                              front_matter["metadata"])
        if any(value != title.encode("utf-8") for value in declared):
            raise ValueError("Tagged release note metadata names a different release")
    headers, separator, upload_body = upload.replace(b"\r\n", b"\n").partition(b"\n\n")
    if (not separator or headers.split(b"\n")[0] != title.encode("utf-8")
            or not notes.strip() or _text(notes) != _text(upload_body)):
        raise ValueError("Tagged release notes and upload text differ")
    return notes, upload, release.digest(tagged)


def _text(value):
    return value.decode("utf-8").replace("\r\n", "\n").strip()


def _read(url, maximum, accept):
    request = Request(url, headers={"Accept": accept, "User-Agent": "MIR-public-release-readback"})
    with urlopen(request, timeout=45) as response:
        data = response.read(maximum + 1)
        if response.status != 200 or len(data) > maximum:
            raise ValueError(f"Unexpected response status or size for {url}")
    return data


def _public_metadata(endpoint, receipt, name):
    data = _read(API + endpoint, 2 * 1024 * 1024, "application/vnd.github+json")
    (receipt / name).write_bytes(data)
    return json.loads(data)


def _public_assets(inventory):
    rows = [*inventory["assets"], inventory["checksums"]]
    if "early_cohort" in inventory:
        cohort = inventory["early_cohort"]
        rows.extend([*cohort["assets"], cohort["checksums"]])
    assets = {row["name"]: row for row in rows}
    if len(assets) != len(rows) or any(
        name in (".", "..", "release-notes.md", "upload-text.txt") or
        not re.fullmatch(r"[A-Za-z0-9_.-]+", name)
        for name in assets
    ):
        raise ValueError("Unsafe or repeated asset name in the frozen inventory")
    return assets


def _verified_asset(tag, expected, public, stage):
    name = expected["name"]
    size = expected["bytes"]
    expected_hash = expected.get("archive_sha256", expected.get("sha256"))
    url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{quote(name)}"
    if (public["browser_download_url"] != url or public["size"] != size or public["state"] != "uploaded"
            or ("label" in expected and public["label"] != expected["label"])):
        raise ValueError(f"Unexpected public metadata for {name}")
    data = _read(url, size, "application/octet-stream")
    (stage / name).write_bytes(data)
    actual = release.digest(data)
    if len(data) != size or actual != expected_hash:
        raise ValueError(f"Unexpected anonymous download bytes for {name}")
    return {"name": name, "id": public["id"], "bytes": size, "sha256": actual}


def _file_hashes(directory):
    files = {}
    for path in directory.iterdir():
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Unexpected entry in delivery directory: {path}")
        files[path.name] = release.digest(path.read_bytes())
    return files


def _install(stage, destination, files):
    if destination.resolve() != destination:
        raise ValueError(f"Unexpected delivery path. Verified downloads remain at {stage}")
    if not destination.exists():
        try:
            stage.rename(destination)
            stage = None
        except OSError:
            if not destination.exists():
                raise
    if _file_hashes(destination) != files:
        if stage is None:
            raise ValueError(f"Files changed after installing {destination}")
        raise ValueError(f"Existing delivery differs. Verified downloads remain at {stage}")
    if stage is not None:
        for name in files:
            (stage / name).unlink()
        stage.rmdir()


def verify_delivery(primary, frozen, inventory_sha256, commit, release_id, prerelease, receipt):
    if not COMMIT.fullmatch(commit) or not SHA256.fullmatch(inventory_sha256) or release_id <= 0:
        raise ValueError("A full reviewed commit, frozen inventory digest and valid release ID are required")
    inventory_sha256 = inventory_sha256.lower()
    frozen_bytes = (frozen / release.INVENTORY_NAME).read_bytes()
    if release.digest(frozen_bytes) != inventory_sha256:
        raise ValueError("Frozen release inventory digest differs")
    inventory = json.loads(frozen_bytes)
    if not isinstance(inventory, dict):
        raise ValueError("Invalid frozen release inventory")
    inventory.pop("inventory_sha256", None)
    if release._inventory_bytes(inventory) != frozen_bytes:
        raise ValueError("Frozen release inventory is not canonical or its self-digest differs")
    if inventory.get("schema") != 1 or inventory.get("kind") != release.KIND:
        raise ValueError("Unsupported frozen release inventory")
    source = inventory["source"]
    identity = release._release_identity(source["source_distribution_version"])
    if identity != inventory["release"]:
        raise ValueError("Release identity differs from the frozen player version")
    assets = _public_assets(inventory)
    primary = primary.resolve(strict=True)
    tag, title = identity["tag"], identity["title"]
    if _git_text(primary, "rev-parse", commit + "^{tree}") != source["tree"]:
        raise ValueError("The reviewed tag commit differs from the frozen tree")
    notes, upload, notes_blob = _notes(primary, commit, title)
    receipt.mkdir(parents=True, exist_ok=False)
    target = _public_metadata("git/ref/tags/" + tag, receipt, "public-tag.json")["object"]
    if target["type"] == "tag":
        annotation = _public_metadata("git/tags/" + target["sha"], receipt, "public-tag-annotation.json")
        target = annotation["object"]
    if target["type"] != "commit" or target["sha"] != commit:
        raise ValueError("The public tag does not point to the reviewed commit")
    public = _public_metadata(f"releases/{release_id}", receipt, "public-release.json")
    if (public["id"], public["tag_name"], public["name"], public["draft"], public["prerelease"],
        public.get("immutable")) != (release_id, tag, title, False, prerelease, False) or not public["published_at"]:
        raise ValueError("The public release identity, maturity or state differs")
    if _text(public["body"].encode("utf-8")) != _text(notes):
        raise ValueError("The GitHub release body differs from the tagged notes")
    remote = {item["name"]: item for item in public["assets"]}
    if len(public["assets"]) != len(assets) or remote.keys() != assets.keys():
        raise ValueError("The published asset inventory differs")
    dist = primary / "dist"
    if dist.resolve() != dist:
        raise ValueError("Unexpected primary dist path")
    dist.mkdir(exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{tag}-readback-", dir=dist))
    with ThreadPoolExecutor(max_workers=4) as workers:
        verified = list(workers.map(
            lambda name: _verified_asset(tag, assets[name], remote[name], stage), assets
        ))
    (stage / "release-notes.md").write_bytes(notes)
    (stage / "upload-text.txt").write_bytes(upload)
    files = {item["name"]: item["sha256"] for item in verified}
    files.update({"release-notes.md": release.digest(notes), "upload-text.txt": release.digest(upload)})
    try:
        primary_head = _primary_revision(primary)
    except ValueError as error:
        raise ValueError(f"{error}. Verified downloads remain at {stage}") from error
    destination = dist / tag
    _install(stage, destination, files)
    result = {
        "tag": tag, "tag_commit": commit, "release_id": release_id, "release_url": public["html_url"],
        "prerelease": prerelease, "source_tree": source["tree"], "primary_head": primary_head,
        "authorization_header_sent": False, "verified_at": datetime.now(timezone.utc).isoformat(),
        "inventory_sha256": inventory_sha256, "tagged_release_notes_blob_sha256": notes_blob,
        "readback_tool_sha256": release.digest(Path(__file__).read_bytes()),
        "verified_assets": verified, "local_directory": str(destination), "local_file_sha256": files,
    }
    (receipt / "anonymous-readback.json").write_bytes(release.canonical_json(result))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--primary", type=Path, default=Path.cwd(), help="Primary checkout")
    parser.add_argument("--frozen", type=Path, required=True, help="Directory containing the frozen inventory")
    parser.add_argument("--inventory-sha256", required=True)
    parser.add_argument("--tag-commit", required=True)
    parser.add_argument("--release-id", required=True, type=int)
    parser.add_argument("--maturity", required=True, choices=("prerelease", "stable"))
    parser.add_argument("--receipt", required=True, type=Path, help="New directory for the anonymous readback")
    args = parser.parse_args()
    result = verify_delivery(args.primary, args.frozen, args.inventory_sha256, args.tag_commit,
                             args.release_id, args.maturity == "prerelease", args.receipt)
    print(f"{result['tag']} verified anonymously and delivered {len(result['verified_assets'])} assets "
          f"and matching notes to {result['local_directory']}")


if __name__ == "__main__":
    main()

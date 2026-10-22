#!/usr/bin/env python3
"""Reviewed, non-destructive staging-to-canonical tree exporter. Python 3.10+.

No writes to the source repository; no Git mutations or native-game execution.
Plans are explicit per tracked file. Export is a layout preview, never a release seal.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import unicodedata
from urllib.parse import quote, unquote, urlsplit

ROOTS = ("source", "spec", "docs", "tests", "tools", "sdk", "targets")
TRANSIENT = {
    "MIR5-PACK.md", "docs/mir5/cutover.md", "docs/mir5/decisions.md",
    "docs/mir5/first_batch.md", "tools/mir5/cutover.py", "tools/mir5/check_pack.py",
    "tests/mir5/test_cutover.py", "tests/mir5/test_pack.py", "tests/mir5/test_adoption.py",
}
ROOT_TEMPLATES = "tools/mir5/adoption/canonical/"
LINK = re.compile(r"(!?\[[^\]\n]*\]\()([^\s()]+)(\))")
VERSION_DIR = re.compile(r"mir[0-9]+(?:[-_].*)?", re.IGNORECASE)

class CutoverError(RuntimeError):
    pass

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def git(repo: Path, *args: str) -> bytes:
    p = subprocess.run(["git", "-C", str(repo), *args], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, check=False)
    if p.returncode:
        raise CutoverError(p.stderr.decode("utf-8", "replace").strip() or "Git command failed")
    return p.stdout

def path_name(value: str) -> str:
    if not isinstance(value, str) or not value or any(c in value for c in '\\:<>"|?*') or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise CutoverError(f"Unsafe relative path: {value!r}")
    p = PurePosixPath(value)
    if p.is_absolute() or any(x.casefold() in ("", ".", "..", ".git") for x in value.split("/")):
        raise CutoverError(f"Unsafe relative path: {value!r}")
    for part in p.parts:
        base = part.split(".", 1)[0].upper()
        if part.endswith((" ", ".")) or base in {"CON", "PRN", "AUX", "NUL"} or re.fullmatch(r"(?:COM|LPT)[1-9]", base):
            raise CutoverError(f"Non-portable path: {value!r}")
    return value

def no_links(path: Path) -> None:
    """Reject symlinks and Windows reparse-point/junction ancestors that exist."""
    for p in (path, *path.parents):
        if p.exists() or p.is_symlink():
            info = p.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
                raise CutoverError(f"Symbolic/reparse path refused: {p}")

def source_root(repo: Path) -> Path:
    no_links(repo.absolute())
    repo = repo.resolve(strict=True)
    top = Path(os.fsdecode(git(repo, "rev-parse", "--show-toplevel").strip())).resolve()
    if top != repo:
        raise CutoverError("--repo must be the Git worktree root")
    if git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
        raise CutoverError("Source must be clean, including nonignored untracked files; preserve work before proceeding")
    return repo

def external_new_path(path: Path, repo: Path) -> Path:
    path = path.absolute()
    no_links(path)
    path = path.resolve(strict=False)
    if path == repo or repo in path.parents or path in repo.parents:
        raise CutoverError("Output must be outside and not contain the source repository")
    if path.exists():
        raise CutoverError(f"Refusing existing output: {path}")
    if not path.parent.is_dir():
        raise CutoverError(f"Output parent must already exist: {path.parent}")
    return path

def tracked(repo: Path) -> dict[str, dict]:
    out = {}
    for item in git(repo, "ls-files", "--stage", "-z").split(b"\x00"):
        if not item:
            continue
        meta, name_b = item.split(b"\t", 1)
        mode, blob, stage = meta.decode("ascii").split()
        name = path_name(os.fsdecode(name_b))
        if stage != "0" or mode not in ("100644", "100755"):
            raise CutoverError(f"Unmerged, submodule or symbolic entry refused: {name}")
        path = repo / name
        no_links(path)
        if not path.is_file():
            raise CutoverError(f"Missing regular tracked file: {name}")
        out[name] = {"git_blob": blob, "mode": mode, "sha256": digest(path.read_bytes())}
    return out

def default_action(name: str) -> tuple[str, str | None, str, str]:
    if name.startswith(ROOT_TEMPLATES):
        dest = name[len(ROOT_TEMPLATES):]
        if "/" in dest:
            raise CutoverError("Root replacement template must target one root file")
        return "move", dest, "Proposed canonical root replacement; review transferred content before approval", "destination"
    if name in TRANSIENT or name.startswith("tools/mir5/adoption/"):
        return "retire", None, "Transition-only tooling/rationale retained by the source commit", "source"
    for root in ROOTS:
        prefix = root + "/mir5/"
        if name.startswith(prefix):
            return "move", root + "/" + name[len(prefix):], "Remove temporary staging component only", "source"
    return "review", None, "", "source"

def make_plan(repo: Path) -> dict:
    repo = source_root(repo)
    current = tracked(repo)
    entries = []
    for name, identity in sorted(current.items()):
        action, destination, reason, layout = default_action(name)
        entries.append({"source": name, **identity, "action": action,
                        "destination": destination, "reason": reason, "content_layout": layout})
    return {
        "format": 1,
        "purpose": "layout-preview-not-release-acceptance",
        "source_commit": git(repo, "rev-parse", "HEAD").decode().strip(),
        "review": {"inventory_reviewed": False, "historical_custody_reference": "",
                   "preservation_review_reference": "", "root_replacements_reviewed": False},
        "entries": entries,
    }

def strict_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise CutoverError("Duplicate JSON key: " + key)
        result[key] = value
    return result

def reject_constant(value: str):
    raise CutoverError("Nonfinite JSON constant: " + value)

def load_plan(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=strict_object, parse_constant=reject_constant)
    except (OSError, ValueError) as e:
        raise CutoverError(f"Cannot read plan: {e}") from e
    if not isinstance(data, dict) or data.get("format") != 1:
        raise CutoverError("Unsupported plan format")
    return data

def final_path(value: str) -> str:
    value = path_name(value)
    if value == ".incomplete-layout-export":
        raise CutoverError("Reserved layout-export marker destination")
    if any(VERSION_DIR.fullmatch(p) for p in PurePosixPath(value).parts[:-1]):
        raise CutoverError(f"Versioned architecture directory survives: {value}")
    return value

def validate_plan(repo: Path, plan: dict) -> tuple[Path, dict[str, dict]]:
    if not isinstance(plan, dict) or plan.get("format") != 1:
        raise CutoverError("Unsupported plan object")
    repo = source_root(repo)
    head = git(repo, "rev-parse", "HEAD").decode().strip()
    if plan.get("source_commit") != head:
        raise CutoverError("Stale source commit; regenerate/review the plan against the actual head")
    review = plan.get("review", {})
    if not isinstance(review, dict):
        raise CutoverError("Review must be an object")
    if review.get("inventory_reviewed") is not True or review.get("root_replacements_reviewed") is not True:
        raise CutoverError("Explicit inventory/root-template review is required")
    if not all(isinstance(review.get(k), str) and review[k].strip() for k in
               ("historical_custody_reference", "preservation_review_reference")):
        raise CutoverError("Historical custody and preservation review references are required")
    actual = tracked(repo)
    entries = plan.get("entries")
    if not isinstance(entries, list):
        raise CutoverError("Plan entries must be a list")
    by_source, seen_dest = {}, {}
    for row in entries:
        if not isinstance(row, dict):
            raise CutoverError("Invalid plan row")
        name = path_name(row.get("source"))
        if name in by_source or name not in actual:
            raise CutoverError(f"Duplicate or untracked source: {name}")
        if any(row.get(k) != actual[name][k] for k in ("git_blob", "mode", "sha256")):
            raise CutoverError(f"Changed source identity: {name}")
        if row.get("action") not in ("keep", "move", "retire"):
            raise CutoverError(f"Unresolved disposition: {name}")
        if not isinstance(row.get("reason"), str) or not row["reason"].strip():
            raise CutoverError(f"Missing disposition reason: {name}")
        if row.get("content_layout") not in ("source", "destination"):
            raise CutoverError(f"Invalid content-layout value: {name}")
        if row["action"] == "retire":
            if row.get("destination") is not None:
                raise CutoverError(f"Retired file has a destination: {name}")
        else:
            dest = final_path(row.get("destination"))
            if row["action"] == "keep" and dest != name:
                raise CutoverError(f"Keep must retain its original path: {name}")
            key = unicodedata.normalize("NFC", dest).casefold()
            if key in seen_dest:
                raise CutoverError(f"Destination collision: {dest} / {seen_dest[key]}")
            seen_dest[key] = dest
        by_source[name] = row
    if set(by_source) != set(actual):
        raise CutoverError("Every tracked file must have exactly one reviewed disposition")
    destinations = {r["destination"] for r in entries if r["action"] != "retire"}
    folded = {unicodedata.normalize("NFC", p).casefold() for p in destinations}
    for dest in destinations:
        for parent in PurePosixPath(dest).parents:
            if str(parent) != "." and unicodedata.normalize("NFC", str(parent)).casefold() in folded:
                raise CutoverError(f"File/directory destination collision: {dest}")
    return repo, by_source

def local_target(source: str, href: str) -> tuple[str, str] | None:
    parsed = urlsplit(href)
    if parsed.scheme or parsed.netloc or href.startswith("#"):
        return None
    raw = unquote(parsed.path)
    if not raw:
        return None
    if raw.startswith("/") or "\\" in raw:
        raise CutoverError(f"Nonportable local Markdown link in {source}: {href}")
    parts = list(PurePosixPath(source).parent.parts)
    for segment in raw.split("/"):
        if segment in ("", "."):
            continue
        if segment == "..":
            if not parts:
                raise CutoverError(f"Markdown link escapes root in {source}: {href}")
            parts.pop()
        else:
            parts.append(segment)
    target = path_name("/".join(parts))
    suffix = ("?" + parsed.query if parsed.query else "") + ("#" + parsed.fragment if parsed.fragment else "")
    return target, suffix

def markdown_links(text: str, transform) -> str:
    """Rewrite inline links outside fenced code. Other Markdown syntaxes need review."""
    lines, fence = [], None
    for line in text.splitlines(keepends=True):
        m = re.match(r"^\s*(`{3,}|~{3,})", line)
        if m:
            token = m.group(1)
            if fence is None:
                fence = (token[0], len(token))
            elif token[0] == fence[0] and len(token) >= fence[1]:
                fence = None
            lines.append(line)
        elif fence is not None:
            lines.append(line)
        else:
            # Reference-style and raw HTML local links are not rewritten by this helper.
            if re.match(r"^\s*\[[^\]]+\]:\s*\S+", line) or re.search(r"<(?:a|img)\b[^>]*(?:href|src)=", line, re.I):
                raise CutoverError("Reference-style/HTML links require conversion or explicit separate review before export")
            lines.append(LINK.sub(lambda m: m.group(1) + transform(m.group(2)) + m.group(3), line))
    return "".join(lines)

def relative_link(source: str, target: str) -> str:
    parts = list(PurePosixPath(source).parent.parts)
    to = list(PurePosixPath(target).parts)
    while parts and to and parts[0] == to[0]:
        parts.pop(0); to.pop(0)
    return quote("/".join([".."] * len(parts) + to), safe="/.-_~")

def render(repo: Path, rows: dict[str, dict]) -> tuple[dict[str, bytes], list[dict]]:
    output, edits = {}, []
    destinations = {r["destination"] for r in rows.values() if r["action"] != "retire"}
    for name, row in rows.items():
        if row["action"] == "retire":
            continue
        dest = row["destination"]
        content = (repo / name).read_bytes()
        if digest(content) != row["sha256"]:
            raise CutoverError(f"Source changed during export: {name}")
        if name.lower().endswith(".md"):
            try:
                text = content.decode("utf-8")
            except UnicodeDecodeError as e:
                raise CutoverError(f"Markdown must be UTF-8: {name}") from e
            def rewrite(href: str) -> str:
                at = dest if row["content_layout"] == "destination" else name
                found = local_target(at, href)
                if found is None:
                    return href
                target, suffix = found
                if row["content_layout"] == "destination":
                    final = target
                else:
                    target_row = rows.get(target)
                    if target_row is None or target_row["action"] == "retire":
                        raise CutoverError(f"Unresolved/retired local link in {name}: {href}")
                    final = target_row["destination"]
                if final not in destinations:
                    raise CutoverError(f"Missing final local link target: {final}")
                new = relative_link(dest, final) + suffix
                if new != href:
                    edits.append({"source": name, "destination": dest, "before": href, "after": new})
                return new
            content = markdown_links(text, rewrite).encode("utf-8")
        output[dest] = content
    return output, edits

def export_tree(repo: Path, plan: dict, output_dir: Path) -> dict:
    repo, rows = validate_plan(repo, plan)
    output_dir = external_new_path(output_dir, repo)
    output, edits = render(repo, rows)  # all preflight/link validation before output writes
    source_root(repo)  # refuse concurrent dirtying before writing
    output_dir.mkdir(exist_ok=False)
    marker = output_dir / ".incomplete-layout-export"
    marker.write_text("This export has not completed. Source checkout was not modified.\n", encoding="utf-8")
    report = {"kind": "layout-preview-not-product-acceptance", "source_commit": plan["source_commit"],
              "source_unchanged": True, "local_link_edits": edits, "files": [],
              "retired": [{"source": n, "reason": r["reason"], "sha256": r["sha256"]}
                          for n, r in rows.items() if r["action"] == "retire"]}
    mode_by_dest = {r["destination"]: r["mode"] for r in rows.values() if r["action"] != "retire"}
    try:
        for name, data in output.items():
            path = output_dir / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("xb") as stream:
                stream.write(data)
            path.chmod(0o755 if mode_by_dest[name] == "100755" else 0o644)
            report["files"].append({"path": name, "sha256": digest(data), "bytes": len(data)})
        source_root(repo)
        if git(repo, "rev-parse", "HEAD").decode().strip() != plan["source_commit"]:
            raise CutoverError("Source HEAD changed during export; output remains marked incomplete")
        if tracked(repo) != {n: {k:r[k] for k in ("git_blob", "mode", "sha256")} for n,r in rows.items()}:
            raise CutoverError("Source changed during export; output remains marked incomplete")
        marker.unlink()
    except Exception:
        # Leave the newly owned incomplete directory for inspection; never delete source/user data.
        raise
    return report

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)
    a = sub.add_parser("plan"); a.add_argument("--repo", type=Path, required=True); a.add_argument("--output", type=Path, required=True)
    a = sub.add_parser("check"); a.add_argument("--repo", type=Path, required=True); a.add_argument("--plan", type=Path, required=True)
    a = sub.add_parser("export"); a.add_argument("--repo", type=Path, required=True); a.add_argument("--plan", type=Path, required=True); a.add_argument("--output", type=Path, required=True)
    ns = ap.parse_args()
    try:
        if ns.command == "plan":
            repo = source_root(ns.repo)
            plan = make_plan(repo)
            out = external_new_path(ns.output, repo)
            with out.open("x", encoding="utf-8", newline="\n") as f:
                json.dump(plan, f, indent=2); f.write("\n")
            print(f"Plan written: {out}; review every disposition. No source files changed.")
        else:
            plan = load_plan(ns.plan)
            if ns.command == "check":
                repo, rows = validate_plan(ns.repo, plan)
                output, edits = render(repo, rows)
                print(f"Layout checks passed: {len(output)} output files; {len(edits)} link edits. Not product acceptance.")
            else:
                print(json.dumps(export_tree(ns.repo, plan, ns.output), indent=2))
        return 0
    except (CutoverError, OSError, ValueError, TypeError) as e:
        print(f"Cutover refused: {e}", file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())

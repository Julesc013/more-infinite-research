#!/usr/bin/env python3
"""Validate current MIR repository documents and static assets, never gameplay."""
from pathlib import Path, PurePosixPath
import json
import re
import stat
import struct
import sys
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

from render_diagrams import atlas, mermaid_source, validate_catalog


ROOT = Path(__file__).resolve().parents[1]
COMPONENT_ROOTS = ("source", "spec", "docs", "tests", "tools", "sdk", "targets")
INLINE_LINK = re.compile(r"(!?\[[^\]\n]*\]\()([^\s()]+)(\))")


class CheckError(ValueError):
    pass


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CheckError("Duplicate JSON key: " + key)
        result[key] = value
    return result


def reject_constant(value):
    raise CheckError("Nonfinite JSON constant: " + value)


def refuse_links(path):
    """Refuse symbolic links and Windows reparse points in an input path."""
    for candidate in (path, *path.parents):
        if candidate.exists() or candidate.is_symlink():
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, "st_file_attributes", 0) & 0x400:
                raise CheckError("Symbolic/reparse path refused: " + str(candidate))


def safe_repository_path(value):
    if (not isinstance(value, str) or not value or "\\" in value
            or any(character in value for character in ':<>"|?*')
            or any(ord(character) < 32 or ord(character) == 127 for character in value)):
        raise CheckError("Unsafe repository-relative path: " + repr(value))
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", "..", ".git"} for part in value.split("/")):
        raise CheckError("Unsafe repository-relative path: " + repr(value))
    for part in path.parts:
        reserved = part.split(".", 1)[0].upper()
        if part.endswith((" ", ".")) or reserved in {"CON", "PRN", "AUX", "NUL"} or re.fullmatch(r"(?:COM|LPT)[1-9]", reserved):
            raise CheckError("Non-portable repository-relative path: " + repr(value))
    return value


def local_markdown_target(source, href):
    parsed = urlsplit(href)
    if parsed.scheme or parsed.netloc or href.startswith("#"):
        return None
    raw = unquote(parsed.path)
    if not raw:
        return None
    if raw.startswith("/") or "\\" in raw:
        raise CheckError(f"Nonportable local Markdown link in {source}: {href}")
    parts = list(PurePosixPath(source).parent.parts)
    for part in raw.split("/"):
        if part in {"", "."}:
            continue
        if part == "..":
            if not parts:
                raise CheckError(f"Markdown link escapes repository in {source}: {href}")
            parts.pop()
        else:
            parts.append(part)
    return safe_repository_path("/".join(parts))


def validate_inline_markdown_links(text, visit):
    """Visit inline links outside fenced code; reject unsupported local forms."""
    fence = None
    for line in text.splitlines(keepends=True):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = (token[0], len(token))
            elif token[0] == fence[0] and len(token) >= fence[1]:
                fence = None
            continue
        if fence is not None:
            continue
        if re.match(r"^\s*\[[^\]]+\]:\s*\S+", line) or re.search(r"<(?:a|img)\b[^>]*(?:href|src)=", line, re.I):
            raise CheckError("Reference-style/HTML links require a separately reviewed validator")
        for match in INLINE_LINK.finditer(line):
            visit(match.group(2))


def component_files():
    files = list(ROOT.glob("*.md"))
    for root in COMPONENT_ROOTS:
        directory = ROOT / root
        refuse_links(directory)
        for path in directory.rglob("*"):
            relative = path.relative_to(ROOT).as_posix()
            if (path.is_file() and "__pycache__" not in path.parts
                    and not relative.startswith("tools/adoption/")):
                refuse_links(path)
                files.append(path)
    return sorted(files)


def validate_diagrams(directory, counts):
    catalogue = json.loads((directory / "catalog.json").read_text(encoding="utf-8"),
                           object_pairs_hook=strict_object, parse_constant=reject_constant)
    diagrams = validate_catalog(catalogue)
    for diagram in diagrams:
        diagram_id = diagram["id"]
        if (directory / (diagram_id + ".mmd")).read_text(encoding="utf-8") != mermaid_source(diagram):
            raise CheckError("Stale Mermaid " + diagram_id)
        for suffix in (".svg", ".png"):
            if not (directory / (diagram_id + suffix)).is_file():
                raise CheckError("Missing render " + diagram_id + suffix)
    if (directory / "index.html").read_text(encoding="utf-8") != atlas(diagrams, directory):
        raise CheckError("Stale atlas")
    counts["diagrams"] += len(diagrams)


def main():
    errors = []
    counts = {"markdown": 0, "json": 0, "python": 0, "links": 0,
              "diagrams": 0, "svg": 0, "diagram_png": 0, "native_asset_png": 0}
    truths = set()
    requirements = set()

    for path in component_files():
        relative = path.relative_to(ROOT).as_posix()
        try:
            if path.suffix == ".json":
                json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=strict_object,
                           parse_constant=reject_constant)
                counts["json"] += 1
            elif path.suffix == ".py":
                compile(path.read_bytes(), str(path), "exec")
                counts["python"] += 1
            elif path.suffix == ".md":
                text = path.read_text(encoding="utf-8")
                counts["markdown"] += 1
                if relative.startswith("spec/"):
                    for requirement in re.findall(r"^`([A-Z]+-[0-9]+)`\s*[—-]", text, re.M):
                        if requirement in requirements:
                            raise CheckError("Duplicate requirement ID " + requirement)
                        requirements.add(requirement)
                if relative.startswith(("docs/", "spec/")):
                    if not text.startswith("---\n"):
                        raise CheckError("Missing front matter")
                    front_matter = text.split("---", 2)[1]
                    for key in ("title:", "status:", "applies_to:", "audience:", "doc_type:", "owner:", "last_reviewed:", "source_of_truth_for:"):
                        if key not in front_matter:
                            raise CheckError("Missing front matter " + key)
                    token = re.search(r"source_of_truth_for:\s*\n\s*-\s*(\S+)", front_matter)
                    if not token or token.group(1) in truths:
                        raise CheckError("Duplicate/missing source_of_truth_for")
                    truths.add(token.group(1))

                def verify_link(href):
                    target = local_markdown_target(relative, href)
                    if target is not None:
                        candidate = ROOT / target
                        refuse_links(candidate)
                        if not candidate.is_file():
                            raise CheckError("Missing local file link: " + target)
                        counts["links"] += 1

                validate_inline_markdown_links(text, verify_link)
            elif path.suffix == ".svg":
                text = path.read_text(encoding="utf-8")
                ET.fromstring(text)
                if re.search(r"<script\b", text, re.I):
                    raise CheckError("SVG script not permitted")
                counts["svg"] += 1
            elif path.suffix == ".png":
                content = path.read_bytes()
                if content[:8] != b"\x89PNG\r\n\x1a\n":
                    raise CheckError("Invalid PNG signature")
                width, height = struct.unpack(">II", content[16:24])
                if relative.startswith("docs/diagrams/"):
                    if not (100 < width < 16000 and 100 < height < 16000):
                        raise CheckError("Implausible diagram PNG dimensions")
                    counts["diagram_png"] += 1
                else:
                    if not (0 < width <= 4096 and 0 < height <= 4096):
                        raise CheckError("Implausible native asset PNG dimensions")
                    counts["native_asset_png"] += 1
            elif path.suffix == ".html":
                text = path.read_text(encoding="utf-8")
                if re.search(r"<script\b|(?:src|href)=[\"']https?://", text, re.I):
                    raise CheckError("Atlas must be offline and script-free")
        except Exception as error:
            errors.append(f"{relative}: {error}")

    try:
        validate_diagrams(ROOT / "docs/diagrams", counts)
    except Exception as error:
        errors.append("docs/diagrams: " + str(error))

    try:
        cases = json.loads((ROOT / "tests/cases.json").read_text(encoding="utf-8"),
                           object_pairs_hook=strict_object, parse_constant=reject_constant)["cases"]
        case_ids = [case["id"] for case in cases]
        if len(set(case_ids)) != len(case_ids):
            raise CheckError("Duplicate acceptance case ID")
        for case in cases:
            if case["status"] != "not_run" or case["implementation_command"] is not None:
                raise CheckError("Acceptance record invents executed product acceptance: " + case["id"])
            if case["requirement"] not in requirements:
                raise CheckError("Unknown requirement " + case["requirement"])
    except Exception as error:
        errors.append("tests/cases.json: " + str(error))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(json.dumps({
        "status": "pass",
        "scope": "repository-documents-and-static-assets-not-gameplay",
        "checked": counts,
        "normative_requirement_ids": len(requirements),
        "product_acceptance_cases": len(cases),
        "native_tests_run": False,
        "mermaid_renderer_executed": False,
        "native_gameplay_claimed": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

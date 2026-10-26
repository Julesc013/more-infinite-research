#!/usr/bin/env python3
"""Project the authoritative root CHANGELOG.md into Factorio changelog.txt."""
import argparse
import json
from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parents[1]
SEPARATOR = "-" * 99
VERSION = re.compile(r"## \[([0-9]+[.][0-9]+[.][0-9]+)\](?: - (Unreleased|[0-9]{4}-[0-9]{2}-[0-9]{2}))?")


def entries(text):
    """Read one logical Markdown line per paragraph/bullet; refuse dropped prose."""
    result = []
    current = None
    category = None
    for line in text.splitlines():
        match = VERSION.fullmatch(line)
        if match:
            current = {"version": match[1], "date": match[2], "sections": []}
            result.append(current)
            category = None
        elif current is None:
            if line.startswith("## "):
                raise ValueError("Invalid release heading: " + line)
        elif not line.strip():
            continue
        elif line.startswith("### ") and line[4:].strip():
            category = {"name": line[4:], "items": []}
            current["sections"].append(category)
        elif re.match(r"^(?:  )*- \S", line) and category is not None:
            depth = (len(line) - len(line.lstrip())) // 2
            if depth and (not category["items"] or depth > category["items"][-1]["depth"] + 1):
                raise ValueError("Invalid nested changelog bullet")
            category["items"].append({"depth": depth, "text": line.strip()[2:]})
        else:
            raise ValueError("Unrecognized or manually wrapped changelog line: " + line)
    versions = [entry["version"] for entry in result]
    if not result or len(versions) != len(set(versions)):
        raise ValueError("Missing or duplicate changelog versions")
    if versions != sorted(versions, key=lambda v: tuple(map(int, v.split("."))), reverse=True):
        raise ValueError("Changelog releases must be in descending source-version order")
    if any(v == "0.0.0" or any(int(part) > 65535 for part in v.split(".")) for v in versions):
        raise ValueError("Changelog version exceeds Factorio's numeric range")
    if any(entry["date"] == "Unreleased" for entry in result[1:]):
        raise ValueError("Only the current changelog entry may be unreleased")
    if any(not entry["sections"] or any(not section["items"] for section in entry["sections"]) for entry in result):
        raise ValueError("Empty changelog release or section")
    if any(len({section["name"] for section in entry["sections"]}) != len(entry["sections"]) for entry in result):
        raise ValueError("Repeated changelog category")
    return result


def factorio(text, source_version):
    records = entries(text)
    if records[0]["version"] != source_version:
        raise ValueError("Current changelog version differs from source/info.json")
    lines = []
    for index, record in enumerate(records):
        lines.extend([SEPARATOR, "Version: " + ("@DISTRIBUTION_VERSION@" if index == 0 else record["version"])])
        if record["date"] and record["date"] != "Unreleased":
            lines.append("Date: " + record["date"])
        for section in record["sections"]:
            lines.extend(["", "  " + section["name"] + ":", ""])
            # Factorio has entries and continuations, not nested Markdown lists.
            # Keep each parent and its details together as one complete entry.
            paragraphs = []
            for item in section["items"]:
                if item["depth"] == 0:
                    paragraphs.append(item["text"])
                else:
                    paragraphs[-1] += " " + item["text"]
            seen = set()
            for paragraph in paragraphs:
                # Its parser also rejects duplicate individual continuation
                # lines. Reflow an affected entry without changing any words.
                for width in range(132, 79, -1):
                    wrapped = textwrap.wrap(paragraph, width=width, initial_indent="    - ",
                                            subsequent_indent="      ", break_long_words=False,
                                            break_on_hyphens=False, replace_whitespace=False)
                    if len(set(wrapped)) == len(wrapped) and not seen.intersection(wrapped):
                        break
                else:
                    raise ValueError("Repeated Factorio changelog entry/continuation in " + record["version"])
                seen.update(wrapped)
                lines.extend(wrapped)
        lines.append("")
    output = "\n".join(lines).rstrip() + "\n"
    if max(map(len, output.splitlines())) > 132:
        raise ValueError("Unbreakable changelog token exceeds Factorio's line bound")
    return output


def rendered(root=ROOT):
    info = json.loads((root / "source/info.json").read_text(encoding="utf-8"))
    major, minor, distribution = map(int, info["version"].split("."))
    source_version = f"{major}.{minor}.{distribution % 100}"
    return factorio((root / "CHANGELOG.md").read_text(encoding="utf-8"), source_version)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="update source/changelog.txt; default checks it")
    arguments = parser.parse_args()
    expected = rendered()
    output = ROOT / "source/changelog.txt"
    if arguments.write:
        output.write_text(expected, encoding="utf-8", newline="\n")
    elif output.read_text(encoding="utf-8") != expected:
        raise SystemExit("source/changelog.txt is stale; run python tools/changelog.py --write")
    print("Unified changelog: authored Markdown and Factorio projection agree")


if __name__ == "__main__":
    main()

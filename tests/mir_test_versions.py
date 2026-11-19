"""Explicit test-only aliases for MIR source releases and declared target codecs.

This module formats new test expectations.  It neither reads production package
code nor rewrites historical archives, saves, profiles, or native input pins.
"""
from dataclasses import dataclass
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
TARGET_RECORDS = (Path("targets/editions.json"), Path("targets/early-editions.json"))
_SOURCE_RELEASE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]?)$")
_TARGET = re.compile(r"^f([0-9]{3})$")
_CHANGELOG_HEADER = re.compile(
    r"^## \[(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]?)\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"
)


@dataclass(frozen=True)
class VersionAlias:
    """One source release rendered for one declared distribution target."""

    source_release: str
    target: str
    distribution_version: str

    @property
    def python_literal(self):
        return repr(self.distribution_version)

    @property
    def lua_literal(self):
        return json.dumps(self.distribution_version)

    @property
    def json_literal(self):
        return json.dumps(self.distribution_version)

    @property
    def dependency(self):
        return "more-infinite-research = " + self.distribution_version

    @property
    def archive_root(self):
        return "more-infinite-research_" + self.distribution_version

    @property
    def archive_name(self):
        return self.archive_root + ".zip"

    def archive_path(self, directory):
        return Path(directory) / self.archive_name


def _source_components(source_release):
    if not isinstance(source_release, str):
        raise ValueError("MIR source release must be a canonical string")
    match = _SOURCE_RELEASE.fullmatch(source_release)
    if match is None:
        raise ValueError("MIR source release must be MAJOR.MINOR.PATCH with PATCH from 0 through 99")
    return match.groups()


def declared_targets(root=ROOT):
    """Read the finite, authored target declarations used by release tests."""
    root = Path(root)
    targets = []
    for relative in TARGET_RECORDS:
        try:
            document = json.loads((root / relative).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError("MIR test target declaration is unavailable: " + relative.as_posix()) from error
        if not isinstance(document, dict):
            raise ValueError("MIR test target declaration is malformed: " + relative.as_posix())
        rows = document.get("targets")
        if document.get("schema") != 1 or not isinstance(rows, dict):
            raise ValueError("MIR test target declaration is malformed: " + relative.as_posix())
        for target, metadata in rows.items():
            if not isinstance(target, str) or _TARGET.fullmatch(target) is None or not isinstance(metadata, dict):
                raise ValueError("MIR test target declaration has an invalid target: " + relative.as_posix())
            targets.append(target)
    if len(targets) != len(set(targets)):
        raise ValueError("MIR test target declarations have duplicate target IDs")
    return tuple(targets)


def alias_for(source_release, target, *, root=ROOT):
    """Return the explicit five-digit edition codec for a source release."""
    major, minor, patch = _source_components(source_release)
    if not isinstance(target, str) or target not in declared_targets(root):
        raise ValueError("MIR test alias target is not declared")
    target_match = _TARGET.fullmatch(target)
    if target_match is None:
        raise ValueError("MIR test alias target is malformed")
    distribution = major + "." + minor + "." + target_match.group(1) + f"{int(patch):02d}"
    return VersionAlias(source_release, target, distribution)


def current_source_release(*, root=ROOT):
    """Read only the first authored release heading from the root changelog."""
    try:
        lines = (Path(root) / "CHANGELOG.md").read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ValueError("MIR authored changelog is unavailable") from error
    for line in lines:
        if line.startswith("## "):
            match = _CHANGELOG_HEADER.fullmatch(line)
            if match is None:
                raise ValueError("MIR authored changelog has no canonical current release heading")
            return ".".join(match.groups())
    raise ValueError("MIR authored changelog has no release heading")


def current_alias(target, *, root=ROOT):
    return alias_for(current_source_release(root=root), target, root=root)

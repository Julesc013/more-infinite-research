"""Pure custody checks for the later owned derivative seed.

This helper only operates on caller-provided synthetic ZIPs in host controls.
It deliberately does not locate or read the retained private F1 source archive.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import zipfile

CONTROL = "native-vector-f1-negative/control.lua"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def rows(path: Path) -> list[tuple[str, bytes]]:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("duplicate seed member")
        return [(name, archive.read(name)) for name in names]


def derive(source: Path, destination: Path, replacement: bytes, expected_source_sha256: str,
           expected_old_control_sha256: str) -> None:
    source_bytes = source.read_bytes()
    if sha256(source_bytes) != expected_source_sha256:
        raise ValueError("source archive hash differs")
    source_rows = rows(source)
    original = dict(source_rows).get(CONTROL)
    if original is None or sha256(original) != expected_old_control_sha256:
        raise ValueError("source observer member differs")
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for name, body in source_rows:
            output.writestr(name, replacement if name == CONTROL else body)


def verify(source: Path, derivative: Path, expected_source_sha256: str,
           expected_old_control_sha256: str, expected_new_control_sha256: str) -> None:
    if sha256(source.read_bytes()) != expected_source_sha256:
        raise ValueError("source archive hash differs")
    source_rows, derived_rows = rows(source), rows(derivative)
    if [name for name, _ in source_rows] != [name for name, _ in derived_rows]:
        raise ValueError("derivative member order or names differ")
    for (source_name, source_body), (_, derived_body) in zip(source_rows, derived_rows):
        if source_name == CONTROL:
            if sha256(source_body) != expected_old_control_sha256 or sha256(derived_body) != expected_new_control_sha256:
                raise ValueError("observer replacement hash differs")
        elif source_body != derived_body:
            raise ValueError(f"non-observer member changed: {source_name}")

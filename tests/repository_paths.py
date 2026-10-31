"""Locate retained evidence after the mechanical source-layout cutover.

Captured records keep their original bytes, paths and hashes. Translate only a
known former root at the lookup boundary; never search or fall back to old files.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def reference_path(relative):
    for root in ("source", "spec", "tests"):
        old = root + "/mir5/"
        if relative.startswith(old):
            return ROOT / (root + "/" + relative[len(old):])
    return ROOT / relative

#!/usr/bin/env python3
"""CLI entrypoint for the isolated Linux private-display boundary."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import sys
import types


MODULE_KIND = "MIRLinuxLibraryDisplayLoaderReceiptV1"
MAX_MODULE_BYTES = 256 * 1024


def load_verified_module(path: Path, expected_sha256: str):
    """Compile the one hash-bound source buffer; never import before binding."""
    if not re.fullmatch(r"[0-9A-F]{64}", expected_sha256):
        raise RuntimeError("display module SHA-256 differs")
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or path.is_symlink() or not (0 < info.st_size <= MAX_MODULE_BYTES):
        raise RuntimeError("display module identity differs")
    raw = path.read_bytes()
    if len(raw) != info.st_size or hashlib.sha256(raw).hexdigest().upper() != expected_sha256:
        raise RuntimeError("display module identity differs")
    module = types.ModuleType("mir_linux_library_display")
    module.__file__ = str(path)
    sys.modules[module.__name__] = module
    exec(compile(raw, str(path), "exec"), module.__dict__)
    return module


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--module-sha256", required=True)
    arguments, remainder = parser.parse_known_args(argv)
    receipt = {"kind": MODULE_KIND, "status": "refused", "factorio_processes": 0}
    library = Path(__file__).resolve().parent / "lib" / "validation" / "LinuxLibraryDisplay.py"
    try:
        module = load_verified_module(library, arguments.module_sha256)
        return module.main(remainder)
    except Exception as error:
        receipt["error"] = str(error)[:512]
        print(json.dumps(receipt, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

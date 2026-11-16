#!/usr/bin/env python3
"""CLI entrypoint for the isolated Linux private-display boundary."""

import importlib.util
from pathlib import Path
import sys


def main() -> int:
    library = Path(__file__).resolve().parent / "lib" / "validation" / "LinuxLibraryDisplay.py"
    specification = importlib.util.spec_from_file_location("mir_linux_library_display", library)
    if specification is None or specification.loader is None:
        raise RuntimeError("Linux private-display module cannot be loaded")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module.main()


if __name__ == "__main__":
    raise SystemExit(main())

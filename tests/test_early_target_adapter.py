"""Exercise the actual shared early adapter with published finite-default vectors."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EarlyTargetAdapterTests(unittest.TestCase):
    def test_all_seven_early_catalogues_and_rejected_inputs(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        control = lua.execute((ROOT / "tests/lua/early_target_adapter.lua").read_text(encoding="utf-8"))
        self.assertTrue(control.run((ROOT / "source").as_posix()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(EarlyTargetAdapterTests))
    sys.exit(0 if result.wasSuccessful() else 1)

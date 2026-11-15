"""Host control for copied all-five fixture entities' Factorio upgrade legality.

This executes the fixture's actual data.lua under the pinned Lua 5.2 runtime.
It does not start Factorio or qualify a native case.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "native-credit-vectors-allfive"


def engine_upgrade_legal(row) -> bool:
    """Model the engine rule relevant to this copied-prototype fixture.

    A prototype with next_upgrade must remain minable.  The fixture intentionally
    removes minability for its controlled void-energy entities, so its copied
    upgrade links must be removed too.
    """
    return row["next_upgrade"] is None or row["minable"] is not None


class AllFivePrototypeLegalityControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_path = FIXTURE.as_posix()
        self.lua.execute(
            r'''
              package.path=fixture_path.."/?.lua;"..package.path
              function table.deepcopy(value, seen)
                if type(value)~="table" then return value end
                seen=seen or {}
                if seen[value] then return seen[value] end
                local result={};seen[value]=result
                for key,item in pairs(value)do result[table.deepcopy(key,seen)]=table.deepcopy(item,seen)end
                return result
              end
              package.preload["contract"]=nil
              package.loaded["contract"]=nil
              emitted={}
              data={raw={
                lab={lab={type="lab",name="lab",minable={result="lab"},next_upgrade="lab-2"}},
                ["assembling-machine"]={
                  ["assembling-machine-1"]={type="assembling-machine",name="assembling-machine-1",
                    minable={result="assembling-machine-1"},next_upgrade="assembling-machine-2"}
                }
              }}
              function data:extend(rows)
                for _,row in ipairs(rows)do emitted[#emitted+1]=row end
              end
              dofile(fixture_path.."/data.lua")
            '''
        )

    def test_copied_nonminable_entities_clear_source_upgrade_links(self):
        emitted = self.lua.globals().emitted
        self.assertEqual(2, len(emitted))
        by_name = {emitted[index]["name"]: emitted[index] for index in range(1, len(emitted) + 1)}
        self.assertEqual({"mir-allfive-credit-lab", "mir-allfive-credit-assembler"}, set(by_name))

        # The non-nil source links make this an engine-legality opponent rather
        # than merely proving an already-empty synthetic input.
        raw = self.lua.globals().data.raw
        self.assertEqual("lab-2", raw.lab.lab["next_upgrade"])
        self.assertEqual("assembling-machine-2", raw["assembling-machine"]["assembling-machine-1"]["next_upgrade"])
        for row in by_name.values():
            self.assertIsNone(row["minable"])
            self.assertIsNone(row["next_upgrade"])
            self.assertTrue(engine_upgrade_legal(row))

        # This is the exact rejected pre-fix shape: a copied source upgrade on
        # a deliberately non-minable fixture entity.
        self.assertFalse(engine_upgrade_legal({"minable": None, "next_upgrade": "assembling-machine-2"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

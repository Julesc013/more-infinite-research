"""Keep the independent technology-reload diagnostic inert (host Lua only).

The native owner composes this one data file into its existing early-stop
fixture with unchanged published MIR. These controls grant no native result.
"""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/sif-technology-reload-data.lua"
NAME = "mir-fixture-sif-technology-reload-sentinel"


class TechnologyReloadFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.source = FIXTURE.read_text()
        self.lua.globals().sentinel = NAME
        self.lua.execute(r'''
          local function copy(value)
            if type(value) ~= "table" then return value end
            local out = {}
            for key, child in pairs(value) do out[key] = copy(child) end
            return out
          end
          function same(actual, expected)
            assert(type(actual) == type(expected), "existing prototype type changed")
            if type(expected) ~= "table" then assert(actual == expected); return end
            for key, child in pairs(expected) do same(actual[key], child) end
            for key in pairs(actual) do assert(expected[key] ~= nil, "existing prototype gained a field") end
          end
          backing, originals = {}, {}
          for _, name in ipairs({"recipe-prod-research_low_density_structure-1",
              "recipe-prod-research_plastic-1", "recipe-prod-research_processing_unit-1",
              "recipe-prod-research_rocket_fuel-1", "recipe-prod-research_steel-1", "mining-productivity-3"}) do
            backing[name] = {type="technology", name=name, enabled=false, hidden=true,
              max_level="infinite", effects={{type="mining-drill-productivity-bonus", modifier=.1}},
              unit={count=10, time=30, ingredients={{"automation-science-pack", 1}}}}
            originals[name] = copy(backing[name])
          end
          data = {raw={technology=setmetatable({}, {
            __index=function(_, name) return backing[name] end,
            __newindex=function() error("direct publication bypassed data.extend") end,
            __pairs=function() error("diagnostic scanned existing technologies") end})}}
          extend_calls = 0
          function data:extend(rows)
            extend_calls = extend_calls + 1
            assert(#rows == 1, "diagnostic must add exactly one technology")
            local row = rows[1]
            assert(backing[row.name] == nil, "diagnostic overwrote a prototype")
            backing[row.name] = row
          end
          local function runtime_forbidden() error("data fixture accessed runtime state") end
          for _, name in ipairs({"game", "storage", "script", "remote"}) do
            _G[name] = setmetatable({}, {__index=runtime_forbidden, __newindex=runtime_forbidden})
          end
        ''')

    def test_adds_one_inert_technology_without_changing_existing_prototypes(self):
        self.lua.execute(self.source)
        self.lua.execute(r'''
          assert(extend_calls == 1)
          local row = assert(backing[sentinel])
          assert(row.type == "technology" and row.name == sentinel)
          assert(row.enabled == false and row.hidden == true and row.upgrade == false)
          assert(#row.effects == 0 and #row.prerequisites == 0)
          assert(row.unit.count == 1 and row.unit.time == 1)
          assert(#row.unit.ingredients == 1 and row.unit.ingredients[1][1] == "automation-science-pack"
            and row.unit.ingredients[1][2] == 1)
          for name, expected in pairs(originals) do same(backing[name], expected) end
          local count = 0
          for _ in pairs(backing) do count = count + 1 end
          assert(count == 7, "diagnostic added another identity")
        ''')

    def test_collision_refuses_before_publication_or_existing_prototype_writes(self):
        self.lua.execute("collision={name=sentinel,enabled=false,foreign={value=7}};backing[sentinel]=collision")
        with self.assertRaisesRegex(LuaError, "identity already exists"):
            self.lua.execute(self.source)
        self.lua.execute(r'''
          assert(extend_calls == 0 and backing[sentinel] == collision)
          assert(collision.enabled == false and collision.foreign.value == 7)
          for name, expected in pairs(originals) do same(backing[name], expected) end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, args.lua_runtime_dir)
    from lupa.lua52 import LuaRuntime, LuaError
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)

"""Named public-boundary fixture controls; no native/API stability verdict."""
import argparse
import json
from pathlib import Path
import sys
import unittest

import test_api as api_controls

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/api-boundary"


class ApiBoundaryFixtureTests(unittest.TestCase):
    def world(self, target):
        harness = api_controls.ApiTests()
        harness.setUp()
        (harness.fresh_f200 if target == "f200" else harness.fresh)()
        lua = harness.lua
        lua.globals().boundary_data = str(FIXTURE / "data-final-fixes.lua")
        lua.execute('logs={}; log=function(text) logs[#logs+1]=text end')
        return lua

    def test_actual_public_helper_passes_both_target_shapes(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                lua = self.world(target)
                lua.execute('assert(loadfile(boundary_data))()')
                self.assertEqual(lua.eval("data.writes"), 2)
                self.assertEqual(lua.eval('data.raw.technology["mir-api-boundary-single-1"].effects[1].modifier'), .03125)
                self.assertIsNone(lua.eval('data.raw.technology["mir-api-boundary-refused-a-1"]'))
                self.assertIsNone(lua.eval('data.raw.technology["mir-api-boundary-refused-b-1"]'))
                self.assertEqual(lua.eval("#logs"), 1)

    def test_unexpected_acceptance_and_input_aliasing_are_detected(self):
        for opponent in ("accept-invalid", "alias-input"):
            with self.subTest(opponent=opponent):
                lua = self.world("f210")
                if opponent == "accept-invalid":
                    lua.execute('''
                    local actual=api.add_technologies
                    api.add_technologies=function(rows)
                      if rows[2] and rows[2].icon then return {rows[1].name,rows[2].name} end
                      return actual(rows)
                    end
                    ''')
                else:
                    lua.execute('''
                    local actual=api.add_technology
                    api.add_technology=function(row)
                      local name=actual(row)
                      data.raw.technology[name].unit=row.unit
                      return name
                    end
                    ''')
                with self.assertRaises(LuaError):
                    lua.execute('assert(loadfile(boundary_data))()')

    def native(self, base, opponent=""):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().control = str(FIXTURE / "control.lua")
        result = lua.execute(r'''
        return function(base, opponent)
          local callback, report, logs, blocked = nil, nil, 0, true
          local function readonly(backing)
            return setmetatable({}, {__index=backing, __newindex=function() error("native mutation") end})
          end
          local names={"mir-api-boundary-single-1", "mir-api-boundary-family-a-1", "mir-api-boundary-family-b-1"}
          local technologies={}
          for _,name in ipairs(names) do
            technologies[name]=readonly({researched=false, level=1, enabled=true,
              prototype=readonly({effects={{type="character-crafting-speed", modifier=opponent=="effect" and .5 or .03125}}})})
          end
          if opponent=="missing" then technologies[names[2]]=nil end
          if opponent=="refused" then technologies["mir-api-boundary-refused-a-1"]={} end
          local force=readonly({valid=true,index=1,technologies=readonly(technologies),manual_crafting_speed_modifier=.05})
          local product=base=="2.0.77" and "5.0.20000" or "5.0.21000"
          local aliased
          local env={script={active_mods={base=base,["more-infinite-research"]=product},
            on_init=function(fn) callback=fn end},
            remote={interfaces={["more-infinite-research.api.v1"]={}},call=function(interface,method,_,name)
              assert(interface=="more-infinite-research.api.v1")
              if method=="get_version" then return {major=1,minor=0,product=product} end
              assert(method=="get_research")
              if opponent=="aliased-query" and aliased then return aliased end
              local value={name=name,force_index=1,level=1,max_level=1,enabled=true,researched=false}
              aliased=value
              return value
            end},
            helpers={table_to_json=function(value) report=value;return "{}" end},
            log=function(text) assert(text:find("[MIR5_API_BOUNDARY] RESULT ",1,true));logs=logs+1 end}
          setmetatable(env,{__index=function(_,key)
            if key=="game" then assert(not blocked,"game accessed during parse");return readonly({forces=readonly({player=force})}) end
            if key=="storage" or key=="global" or key=="settings" then error("forbidden native access") end
            return _G[key]
          end})
          assert(loadfile(control,"t",env))()
          assert(callback and logs==0)
          blocked=false
          local ok,message=pcall(callback)
          return {ok=ok,message=tostring(message),report=report,logs=logs}
        end
        ''')(base, opponent)
        return result

    def test_read_only_runtime_witness_observes_native_rows_on_both_engines(self):
        for base in ("2.0.77", "2.1.23"):
            with self.subTest(base=base):
                result = self.native(base)
                self.assertTrue(result.ok, result.message)
                self.assertEqual(result.logs, 1)
                self.assertEqual(result.report.stage, "init")
                self.assertEqual(result.report.native_rows, 3)
                self.assertFalse(result.report.release_qualification)

    def test_missing_wrong_rejected_or_aliasing_native_state_is_refused(self):
        for opponent in ("missing", "effect", "refused", "aliased-query"):
            with self.subTest(opponent=opponent):
                result = self.native("2.1.23", opponent)
                self.assertFalse(result.ok)
                self.assertEqual(result.logs, 0)

    def test_metadata_requires_exact_modern_candidate_and_has_no_private_import(self):
        for target, family, base, product in (("f200", "2.0", "2.0.77", "5.0.20000"), ("f210", "2.1", "2.1.23", "5.0.21000")):
            value = json.loads((FIXTURE / f"info-{target}.json").read_text())
            self.assertEqual(value["factorio_version"], family)
            self.assertEqual(value["dependencies"], [f"base = {base}", f"more-infinite-research = {product}"])
        source = (FIXTURE / "data-final-fixes.lua").read_text()
        self.assertEqual(source.count('require("'), 1)
        self.assertIn('require("__more-infinite-research__.api.v1.data")', source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(Path(args.lua_runtime_dir).resolve()))
    from lupa.lua52 import LuaRuntime, LuaError
    api_controls.LuaRuntime = LuaRuntime
    unittest.main(argv=[sys.argv[0], *remaining])

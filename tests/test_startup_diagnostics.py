"""Observational logging cannot change prototypes or add a recipe pass; host only."""
import argparse
import json
from pathlib import Path
import sys
import unittest

import test_generator as fixture
import test_product_targets as collector_fixture
import test_historical_direct as direct_fixture
import test_historical_continuations as continuation_fixture

ROOT = Path(__file__).resolve().parents[1]


class StartupDiagnosticsTests(unittest.TestCase):
    def lua(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        lua.execute('package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"; package.cpath=""')
        return lua

    def test_fixed_phase_transport_budget_fallback_and_throwing_logger(self):
        lua = self.lua()
        lua.execute('''
          local rows={}; log=function(row) rows[#rows+1]=row end
          local trace=require("startup_diagnostics").start("data")
          trace.phase("stage","end")
          assert(#rows==2 and rows[1]:find("event=begin",1,true) and rows[2]:find("event=end",1,true))
          for i=1,1000 do trace.phase("example","begin") end
          assert(#rows==48)
          log=nil; print=function(row) rows[#rows+1]=row end
          trace=require("startup_diagnostics").start("settings")
          assert(#rows==49 and rows[49]:find("stage=settings",1,true))
          print=nil; trace=require("startup_diagnostics").start("data")
          trace.phase("stage","end")
          log=function() error("broken diagnostic sink") end
          trace=require("startup_diagnostics").start("data")
          trace.phase("stage","end")
        ''')

    def test_recipe_detail_is_bounded_on_one_pass_and_transport_cannot_mutate_work(self):
        collector_fixture.LuaRuntime = LuaRuntime
        harness = collector_fixture.ProductTargetTests()
        harness.setUp()
        harness.lua.execute('''
          local recipes={}
          for i=1,40000 do recipes["r"..i]=recipe({}, {product("item","copper-plate")}) end
          local context=targets.prepare({binding("copper",.1,{{type="item",name="copper-plate"}})})
          local baseline=targets.collect(recipes,context)
          local real_pairs,visits=pairs,0
          pairs=function(t) if t==recipes then visits=visits+1 end; return real_pairs(t) end
          local messages={};log=function(t) messages[#messages+1]=t end
          local trace=require("startup_diagnostics").start("data-final-fixes")
          local diagnostic=targets.collect(recipes,context,trace.progress)
          assert(visits==1 and #messages==10) -- one stage begin, eight checkpoints, one final
          assert(messages[#messages]:find("recipes=40000",1,true))
          assert(messages[#messages]:find("complete=true",1,true))
          assert(frozen_copy(baseline)==frozen_copy(diagnostic))
          local broken=targets.collect(recipes,context,function() error("sink") end)
          assert(frozen_copy(baseline)==frozen_copy(broken))
        ''')

    def test_modern_output_identical_for_detail_off_on_and_broken_log(self):
        fixture.LuaRuntime = LuaRuntime
        outputs = []
        for detail, sink in ((False, "capture"), (True, "capture"), (True, "broken")):
            harness = fixture.GeneratorTests()
            harness.setUp()
            lua = harness.lua
            lua.globals().detail = detail
            lua.globals().broken = sink == "broken"
            lua.execute('''
              mods={base="2.1.23",["space-age"]="2.1.23"}
              settings={startup=defaults()};settings.startup["mir-debug-generation-report"].value=detail
              data=full_world(mods); messages={}
              log=function(row)
                if broken and row:find("[MIR startup]",1,true) then error("sink") end
                messages[#messages+1]=row
              end
              dofile(data_final_path)
            ''')
            outputs.append(fixture.plain_lua(lua.globals().data.emitted))
            if sink == "capture":
                messages = list(lua.globals().messages.values())
                self.assertEqual(any("event=work" in m for m in messages), detail)
                self.assertLessEqual(len([m for m in messages if "[MIR startup]" in m]), 48)
        self.assertEqual(outputs[0], outputs[1])
        self.assertEqual(outputs[0], outputs[2])

    def test_product_errors_still_fail_with_incomplete_phase(self):
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.GeneratorTests()
        harness.setUp()
        lua = harness.lua
        lua.execute('''
          mods={base="2.1.23"};settings={startup=defaults()};data=full_world(mods)
          data.raw.technology["recipe-prod-research_gears-1"]={name="foreign"}
          messages={};log=function(row) messages[#messages+1]=row end
          local ok,err=pcall(dofile,data_final_path)
          assert(not ok and tostring(err):find("duplicate technology",1,true))
          assert(data.writes==0)
          assert(not messages[#messages]:find("event=end",1,true))
        ''')

    def test_seven_stable_reduced_adapters_keep_output_with_captured_or_discarded_logs(self):
        direct_fixture.LuaRuntime = continuation_fixture.LuaRuntime = LuaRuntime
        editions = json.loads((ROOT / "targets/editions.json").read_text())["targets"]
        for identifier in ("f013", "f014", "f015", "f016", "f017", "f100", "f110"):
            output = []
            for capture in (False, True):
                with self.subTest(target=identifier, capture=capture):
                    direct = direct_fixture.HistoricalDirectTests()
                    direct.setUp()
                    continuation = continuation_fixture.HistoricalContinuationTests()
                    continuation.setUp()
                    raw = fixture.plain_lua(direct.lua.globals().raw_for(identifier))
                    other = fixture.plain_lua(continuation.lua.globals().raw_for(identifier))
                    for kind, rows in other.items():
                        raw.setdefault(kind, {}).update(rows)
                    lua = direct.lua
                    lua.globals().raw_input = fixture.lua_table(lua, raw)
                    lua.globals().edition_input = fixture.lua_table(lua, {**editions[identifier], "id": identifier})
                    lua.globals().capture = capture
                    lua.execute('''
                      package.loaded["platform.target"]=edition_input
                      messages={};log=function(row) if capture then messages[#messages+1]=row end end
                      data={raw=raw_input,extend=function(self,rows) self.emitted=rows end}
                      require("adapters.reduced.settings").apply()
                      local prototypes=data.emitted
                      settings={startup={}}
                      for _,row in ipairs(prototypes) do settings.startup[row.name]={value=row.default_value} end
                      require("adapters.reduced.data").apply()
                      require("adapters.reduced.data-final-fixes").apply()
                    ''')
                    output.append(fixture.plain_lua(lua.globals().data.emitted))
                    if capture:
                        messages = list(lua.globals().messages.values())
                        self.assertEqual(sum("phase=stage event=end" in m for m in messages), 3)
            self.assertEqual(*output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *remaining])

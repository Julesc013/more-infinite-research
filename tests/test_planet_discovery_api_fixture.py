"""Lua 5.2 controls for the prepared, read-only planet discovery API witness."""
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "tests" / "fixtures" / "planet-discovery-api" / "control.lua"


class PlanetDiscoveryApiFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().control_source = CONTROL.as_posix()
        self.lua.execute(r'''
          function run_planet_discovery_api(mode, wrong_closure)
            local callbacks, logs, rows = {}, {}, {}
            local locations = {nauvis={},vulcanus={},gleba={},fulgora={},aquilo={}}
            local technologies = setmetatable({}, {
              __index={witness={researched=false}},
              __pairs=function(value) return next, getmetatable(value).__index, nil end,
              __newindex=function() error("observer wrote technologies") end,
            })
            local force = {valid=true, technologies=technologies}
            local calls = 0
            function force.is_space_location_unlocked(name)
              calls = calls + 1
              if mode == "nil" and name == "nauvis" then return nil end
              if mode == "string" and name == "nauvis" then return "unknown" end
              if mode == "mixed" then return name == "nauvis" or name == "gleba" end
              return false
            end
            function force.unlock_space_location() error("observer unlocked a location") end
            function force.reset_technology_effects() error("observer reset technology effects") end
            function force.add_research() error("observer changed research") end
            local forces = setmetatable({}, {
              __index={player=force},
              __pairs=function(value) return next, getmetatable(value).__index, nil end,
              __newindex=function() error("observer wrote forces") end,
            })
            local active={base="2.1.23",quality="2.1.23",["elevated-rails"]="2.1.23",recycler="2.1.23",
              ["space-age"]="2.1.23",["mir-fixture-planet-discovery-api"]="0.1.0"}
            if wrong_closure then active.unexpected="0.1.0" end
            local env={
              game={forces=forces,create_force=function() error("observer created force") end,
                server_save=function() error("observer saved game") end},
              prototypes={space_location=setmetatable({}, {
                __index=locations,__pairs=function(value) return next,getmetatable(value).__index,nil end,
                __newindex=function() error("observer wrote locations") end,
              })},
              storage=setmetatable({}, {__index=function() error("observer read storage") end,
                __newindex=function() error("observer wrote storage") end}),
              script={active_mods=active,on_init=function(callback) callbacks.init=callback end,
                on_tick=function() error("observer registered on_tick") end,
                on_load=function() error("observer registered on_load") end,
                on_configuration_changed=function() error("observer registered configuration callback") end,
                on_event=function() error("observer registered event callback") end},
              helpers={table_to_json=function(row) rows[#rows+1]=row;return "{}" end},
              log=function(line) logs[#logs+1]=line end,
            }
            env._G=env;setmetatable(env,{__index=function(_, key) return _G[key] end})
            assert(loadfile(control_source,"t",env))()
            assert(type(callbacks.init)=="function")
            local ok,message=pcall(callbacks.init)
            return {ok=ok,message=tostring(message),calls=calls,logs=logs,rows=rows,callbacks=callbacks}
          end
        ''')

    def test_mixed_boolean_values_are_logged_and_pass(self):
        self.lua.execute(r'''
          local result=run_planet_discovery_api("mixed",false)
          assert(result.ok and result.calls==5 and #result.logs==3 and #result.rows==3)
          local observed=result.rows[2].queries
          assert(observed[1].value==true and observed[2].value==false and observed[3].value==true)
          assert(observed[4].value==false and observed[5].value==false)
          for _,row in ipairs(observed) do assert(row.value_type=="boolean") end
          assert(result.rows[3].status=="passed")
        ''')

    def test_all_false_values_are_retained_and_pass(self):
        self.lua.execute(r'''
          local result=run_planet_discovery_api("false",false)
          assert(result.ok and result.calls==5 and #result.logs==3 and #result.rows==3)
          for _,row in ipairs(result.rows[2].queries) do
            assert(row.value==false and row.value_type=="boolean")
          end
          assert(result.rows[3].status=="passed")
        ''')

    def test_nil_and_non_boolean_values_are_observed_before_refusal(self):
        self.lua.execute(r'''
          for _,mode in ipairs({"nil","string"}) do
            local result=run_planet_discovery_api(mode,false)
            assert(not result.ok and result.calls==5 and #result.logs==2 and #result.rows==2)
            assert(result.rows[2].queries[1].value_type==(mode=="nil" and "nil" or "string"))
            assert(not result.message:match("observer unlocked") and result.rows[3]==nil)
          end
        ''')

    def test_wrong_closure_refuses_before_location_queries_or_result(self):
        self.lua.execute(r'''
          local result=run_planet_discovery_api("mixed",true)
          assert(not result.ok and result.calls==0 and #result.logs==1 and #result.rows==1)
          assert(result.logs[1]:match("^%[MIR_PLANET_DISCOVERY_API%] SHAPES "))
          assert(result.rows[2]==nil and result.message:match("active mod closure"))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PlanetDiscoveryApiFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

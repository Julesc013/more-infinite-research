"""Independent host controls for the first native research slice (Lua 5.2)."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          config = require("research.settings")
          productivity = require("research.productivity")
          generator = require("research.generator")
          function defaults()
            local values = {}
            for _, spec in ipairs(config.prototypes()) do values[spec.name] = {value = spec.default_value} end
            return values
          end
          function build()
            return productivity.gears(config.resolve(defaults()))
          end
          function world()
            local packs = {}
            for _, name in ipairs({"automation", "logistic", "chemical", "production"}) do
              packs[name .. "-science-pack"] = {}
            end
            return {raw = {technology = packs, tool = packs, recipe = {["iron-gear-wheel"] = {}}},
              writes = 0, extend = function(self, values) self.writes = self.writes + 1; self.emitted = values end}
          end
          function refused(prototypes, environment, fragment)
            local ok, message = pcall(generator.install, prototypes, environment)
            assert(not ok, "invalid family was accepted")
            assert(environment.writes == 0, "preflight rejection wrote prototypes")
            assert(tostring(message):find(fragment, 1, true), tostring(message))
          end
        ''')

    def test_published_default_and_detachment(self):
        self.lua.execute('''
          local a, b = build(), build()
          assert(a.name == "recipe-prod-research_gears-1" and a.max_level == "infinite" and a.upgrade)
          assert(a.unit.count_formula == "8000*2^(L-1)" and a.unit.time == 60)
          assert(#a.unit.ingredients == 4 and #a.prerequisites == 4)
          local expected = {"automation", "logistic", "chemical", "production"}
          for index, name in ipairs(expected) do
            assert(a.unit.ingredients[index][1] == name .. "-science-pack")
            assert(a.unit.ingredients[index][2] == 1 and a.prerequisites[index] == name .. "-science-pack")
          end
          assert(#a.effects == 1 and a.effects[1].type == "change-recipe-productivity")
          assert(a.effects[1].recipe == "iron-gear-wheel" and a.effects[1].change == .10)
          a.effects[1].change = 99; a.unit.ingredients[1][2] = 99; a.prerequisites[1] = "changed"
          assert(b.effects[1].change == .10 and b.unit.ingredients[1][2] == 1)
          assert(b.prerequisites[1] == "automation-science-pack")
        ''')

    def test_cost_variants_and_nonfinite(self):
        self.lua.execute('''
          assert(productivity.cost(100, 0, 1) == "100")
          assert(productivity.cost(100, 25, 1) == "100+25*(L-1)")
          assert(productivity.cost(100, 0, 1.5) == "100*1.5^(L-1)")
          assert(productivity.cost(100, 25, 1.5) == "(100+25*(L-1))*1.5^(L-1)")
          assert(not pcall(productivity.cost, 100, 0, math.huge))
          assert(not pcall(productivity.cost, 0/0, 0, 2))
          assert(not pcall(productivity.cost, 100, 0, 1001))
        ''')

    def test_import_precedence_false_zero_and_invalid_entries(self):
        self.lua.execute('''
          local startup = defaults()
          startup["ips-cost-base-research_gears"].value = 100
          startup["mir-settings-profile-import"].value = '{"schema":1}'
          local values = {schema=1, kind="mir-settings-profile", settings={
            ["ips-cost-base-research_gears"] = 8000, ["ips-enable-research_gears"] = false,
            ["ips-cost-linear-increment-research_gears"] = 0, ["ips-research-time-research_gears"] = 0,
            ["ips-cost-growth-research_gears"] = -1}}
          local codec = {json_to_table=function() return values end, decode_string=function(s) return s end, encode_string=function(s) return s end}
          local result = config.resolve(startup, codec)
          assert(result.base_cost == 8000 and result.enabled == false and result.linear_increment == 0)
          assert(result.research_time == 60 and result.growth_factor == 2)
          startup["mir-settings-profile-import"].value = "MIRSET1:anything"
          assert(config.resolve(startup, codec).enabled == false)
          codec.json_to_table = function() error("malformed JSON") end
          assert(config.resolve(startup, codec).base_cost == 100)
        ''')

    def test_disabled_identity_and_finite_cap_preserve_native_tail(self):
        self.lua.execute('''
          local startup = defaults(); startup["ips-enable-research_gears"].value = false
          local a = productivity.gears(config.resolve(startup))
          assert(a.name == "recipe-prod-research_gears-1" and a.enabled == false and a.effects[1].change == .1)
          startup["ips-max-level-research_gears"].value = 10
          local capped = productivity.gears(config.resolve(startup))
          assert(capped.name == a.name and capped.max_level == "infinite" and capped.enabled == false)
          assert(capped.effects[1].change == .1 and capped.unit.count_formula == a.unit.count_formula)
        ''')

    def test_valid_family_forward_reference_and_one_write(self):
        self.lua.execute('''
          local a, b = build(), build(); a.name = "alpha-1"; b.name = "beta-1"
          a.prerequisites = {"beta-1"}; b.prerequisites = {}
          local environment = world(); generator.install({a, b}, environment)
          assert(environment.writes == 1 and environment.emitted[1].name == "alpha-1")
        ''')

    def test_all_family_failures_precede_first_write(self):
        self.lua.execute('''
          local a, b = build(), build(); b.name = "second-1"; b.effects[1].recipe = "missing"
          refused({a,b}, world(), "missing recipe")
          b = build(); refused({a,b}, world(), "duplicate")
          local environment = world(); environment.raw.technology[a.name] = {}
          refused({a}, environment, "duplicate")
          b.name = "second-1"; a.prerequisites = {b.name}; b.prerequisites = {a.name}
          refused({a,b}, world(), "cycle")
          a = build(); a.unit.ingredients[1][1] = "missing"; refused({a}, world(), "ingredient")
          a = build(); a.effects[1].change = 0/0; refused({a}, world(), "productivity")
          refused({[1]=build(),[3]=build()}, world(), "missing entry")
        ''')

    def test_item_science_is_not_limited_to_tools(self):
        self.lua.execute('''
          local environment = world(); environment.raw.item = environment.raw.tool; environment.raw.tool = {}
          generator.install({build()}, environment); assert(environment.writes == 1)
        ''')

    def test_unrelated_world_growth_is_not_traversed(self):
        self.lua.execute('''
          local environment = world()
          environment.raw.fluid = setmetatable({}, {__pairs=function() error("unrelated world scan") end})
          environment.raw.recipe = setmetatable(environment.raw.recipe, {__pairs=function() error("whole recipe scan") end})
          generator.install({build()}, environment); assert(environment.writes == 1)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(GeneratorTests))
    if args.output:
        paths = sorted((ROOT / "source/mir5").rglob("*.lua")) + [Path(__file__).resolve()]
        record = {"kind": "mir5-gear-host-controls-not-native-evidence", "status": "passed" if result.wasSuccessful() else "failed",
                  "tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors), "lua": "5.2",
                  "inputs": [{"path": p.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    sys.exit(0 if result.wasSuccessful() else 1)

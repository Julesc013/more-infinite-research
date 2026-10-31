"""Named prerequisite-repair boundaries; host controls do not qualify optional mods."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PUBLISHED_473 = "8643cc91bc915e008556a5315dbb0a743247e7ab"
PUBLISHED_473_BLOBS = {
    "source/prototypes/mir/compatibility/repairs/angels_smelting.lua": "d49c9999b8a569cbb7aed8632524adeb048d1f52",
    "source/prototypes/mir/compatibility/repairs/technology_prerequisite_cycles.lua": "5f9cabebc79787da3168899558be095bb8e9d32a",
}


class PrerequisiteRepairTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        published_cycle = subprocess.run(
            ["git", "show", f"{PUBLISHED_473}:source/prototypes/mir/compatibility/repairs/technology_prerequisite_cycles.lua"],
            cwd=ROOT, check=True, text=True, capture_output=True,
        ).stdout
        self.lua.globals().published_cycle_source = published_cycle
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          package.preload["prototypes.mir.platform.factorio.data_raw"] = function() return {} end
          package.preload["prototypes.mir.report.diagnostics_sink"] = function() return {} end
          published_cycle = assert(load(published_cycle_source, "@published-4.7.3-cycle-repair"))()
          repair = require("overrides.prerequisite_repairs")
        ''')

    def test_published_473_named_functions_are_read_only_recovery_evidence(self):
        # The workflow fetches this immutable baseline before host controls;
        # the test remains offline and fails if that declared input is absent.
        subprocess.run(
            ["git", "cat-file", "-e", f"{PUBLISHED_473}^{{commit}}"], cwd=ROOT,
            check=True, text=True, capture_output=True,
        )
        self.assertEqual(set(PUBLISHED_473_BLOBS), {
            "source/prototypes/mir/compatibility/repairs/angels_smelting.lua",
            "source/prototypes/mir/compatibility/repairs/technology_prerequisite_cycles.lua",
        })
        self.assertTrue(all(len(blob) == 40 and int(blob, 16) >= 0 for blob in PUBLISHED_473_BLOBS.values()))
        def published(path: str) -> str:
            resolved = subprocess.run(
                ["git", "rev-parse", f"{PUBLISHED_473}:{path}"], cwd=ROOT,
                check=True, text=True, capture_output=True,
            ).stdout.strip()
            self.assertEqual(resolved, PUBLISHED_473_BLOBS[path])
            return subprocess.run(
                ["git", "show", f"{PUBLISHED_473}:{path}"], cwd=ROOT,
                check=True, text=True, capture_output=True,
            ).stdout

        angel = published("source/prototypes/mir/compatibility/repairs/angels_smelting.lua")
        cycle = published("source/prototypes/mir/compatibility/repairs/technology_prerequisite_cycles.lua")
        self.assertIn('local silver = "angels-silver-smelting-1"', angel)
        self.assertIn('modules.enabled == false', angel)
        self.assertIn('prerequisite.enabled ~= false', angel)
        self.assertIn('id = "muluna-astroponics-space-science-cycle"', cycle)
        self.assertIn('required_mods = {"astroponics", "planet-muluna"}', cycle)
        self.assertIn('remove_prerequisite = "space-science-pack"', cycle)

    def test_unsupported_or_inactive_paths_never_inspect_raw(self):
        self.lua.execute('''
          local raw = setmetatable({}, {__index=function() error("inactive raw read") end})
          local cases = {
            {{}, {id="f017"}},
            {{angelssmelting="1.0.0"}, {id="f110"}},
            {{angelssmelting="1.0.0"}, {id="f220"}},
            {{}, {id="f200"}},
            {{astroponics="1.7.3"}, {id="f210"}},
            {{["planet-muluna"]="2.3.18"}, {id="f210"}},
          }
          for _, case in ipairs(cases) do
            assert(repair.apply(raw, case[1], case[2], function() error("inactive repair reported") end) == 0)
          end
        ''')

    def test_angel_removes_only_disabled_silver_from_a_fresh_prerequisite_list_on_both_targets(self):
        self.lua.execute('''
          for _, base in ipairs({"2.0.77", "2.1.23"}) do
            local original = {"automation", "angels-silver-smelting-1", "foreign", "angels-silver-smelting-1"}
            local foreign_list, silver_list = {"not-this-edge"}, {"foreign-silver-edge"}
            local modules = {enabled=true,prerequisites=original,foreign={marker=17}}
            local silver = {enabled=false,prerequisites=silver_list,foreign={marker=23}}
            local foreign = {enabled=true,prerequisites=foreign_list,foreign={marker=31}}
            local raw = {technology={modules=modules,["angels-silver-smelting-1"]=silver,foreign=foreign}}
            local target = {id=base == "2.0.77" and "f200" or "f210"}
            local messages = {}
            assert(repair.apply(raw,{angelssmelting="1.0.0"},target,
              function(message) messages[#messages + 1] = message end) == 1)
            assert(#messages == 1 and messages[1] == "[more-infinite-research] Repaired "
              .. "angels-disabled-silver-modules-prerequisite: removed modules -> angels-silver-smelting-1.")
            assert(modules.prerequisites ~= original and #modules.prerequisites == 2)
            assert(modules.prerequisites[1] == "automation" and modules.prerequisites[2] == "foreign")
            assert(modules.enabled and modules.foreign.marker == 17)
            assert(silver.prerequisites == silver_list and silver.foreign.marker == 23)
            assert(foreign.prerequisites == foreign_list and foreign.foreign.marker == 31)
            local repaired = modules.prerequisites
            assert(repair.apply(raw,{angelssmelting="1.0.0"},target,
              function() error("no-op Angel repair reported") end) == 0)
            assert(modules.prerequisites == repaired)
            local single = {enabled=true,prerequisites={"angels-silver-smelting-1"}}
            local single_raw = {technology={modules=single,["angels-silver-smelting-1"]={enabled=false}}}
            assert(repair.apply(single_raw,{angelssmelting="1.0.0"},target) == 1 and single.prerequisites == nil)
          end
        ''')

    def test_angel_requires_active_smelt_module_enabled_modules_and_disabled_silver_edge(self):
        self.lua.execute('''
          local function untouched(modules, silver, mods, target)
            local original = modules.prerequisites
            local raw = {technology={modules=modules,["angels-silver-smelting-1"]=silver}}
            assert(repair.apply(raw, mods, target, function() error("no-op Angel repair reported") end) == 0)
            assert(modules.prerequisites == original)
          end
          local active, target = {angelssmelting="1.0.0"}, {id="f210"}
          untouched({enabled=false,prerequisites={"angels-silver-smelting-1"}}, {enabled=false}, active, target)
          untouched({enabled=true,prerequisites={"angels-silver-smelting-1"}}, {enabled=true}, active, target)
          untouched({enabled=true,prerequisites={"foreign"}}, {enabled=false}, active, target)
          untouched({enabled=true,prerequisites={"angels-silver-smelting-1"}}, nil, active, target)
          local raw = setmetatable({}, {__index=function() error("inactive Angel read") end})
          assert(repair.apply(raw, {}, target, function() error("inactive Angel repair reported") end) == 0)
        ''')

    def test_astroponics_repairs_the_published_three_edge_path_on_both_targets(self):
        self.lua.execute('''
          for _, base in ipairs({"2.0.77", "2.1.23"}) do
            local astro_list = {"landfill", "space-science-pack", "foreign"}
            local space_list, propellant_list, foreign_list = {"muluna-alice-propellant"}, {"astroponics"}, {"space-science-pack"}
            local astroponics = {prerequisites=astro_list,foreign={marker=41}}
            local space = {prerequisites=space_list,foreign={marker=43}}
            local propellant = {prerequisites=propellant_list,foreign={marker=47}}
            local foreign = {prerequisites=foreign_list,foreign={marker=53}}
            local raw = {technology={astroponics=astroponics,["space-science-pack"]=space,
              ["muluna-alice-propellant"]=propellant,foreign=foreign}}
            local mods = {astroponics="1.7.3",["planet-muluna"]="2.3.18"}
            local target = {id=base == "2.0.77" and "f200" or "f210"}
            local messages = {}
            assert(repair.apply(raw, mods, target, function(message) messages[#messages + 1] = message end) == 1)
            assert(#messages == 1 and messages[1] == "[more-infinite-research] Repaired "
              .. "muluna-astroponics-space-science-cycle: removed astroponics -> space-science-pack.")
            assert(astroponics.prerequisites ~= astro_list and #astroponics.prerequisites == 2)
            assert(astroponics.prerequisites[1] == "landfill" and astroponics.prerequisites[2] == "foreign")
            assert(space.prerequisites == space_list and propellant.prerequisites == propellant_list)
            assert(foreign.prerequisites == foreign_list and astroponics.foreign.marker == 41)
            local repaired = astroponics.prerequisites
            assert(repair.apply(raw, mods, target,
              function() error("no-op Astroponics repair reported") end) == 0 and astroponics.prerequisites == repaired)
          end
        ''')

    def test_astroponics_refuses_missing_or_different_paths_without_touching_foreign_arrays(self):
        self.lua.execute('''
          local function raw_for(space_prerequisites)
            local astro_list, propellant_list, foreign_list = {"landfill", "space-science-pack"}, {"astroponics"}, {"astroponics"}
            local raw = {technology={astroponics={prerequisites=astro_list},
              ["space-science-pack"]={prerequisites=space_prerequisites},
              ["muluna-alice-propellant"]={prerequisites=propellant_list},foreign={prerequisites=foreign_list}}}
            return raw, astro_list, propellant_list, foreign_list
          end
          local mods, target = {astroponics="1.7.3",["planet-muluna"]="2.3.18"}, {id="f210"}
          for _, space_prerequisites in ipairs({{"different-edge"}, {}}) do
            local raw, astro_list, propellant_list, foreign_list = raw_for(space_prerequisites)
            assert(repair.apply(raw, mods, target, function() error("no-op Astroponics repair reported") end) == 0)
            assert(raw.technology.astroponics.prerequisites == astro_list)
            assert(raw.technology["muluna-alice-propellant"].prerequisites == propellant_list)
            assert(raw.technology.foreign.prerequisites == foreign_list)
          end
          local raw = {technology={astroponics={prerequisites={"space-science-pack"}},
            ["space-science-pack"]={prerequisites={"muluna-alice-propellant"}}}}
          assert(repair.apply(raw, mods, target, function() error("no-op Astroponics repair reported") end) == 0)
        ''')

    def test_astroponics_matches_published_reachability_on_finite_independent_graphs(self):
        self.lua.execute('''
          local mods, target = {astroponics="1.7.3", ["planet-muluna"]="2.3.18"}, {id="f210"}
          local function historical_result(technologies)
            return #published_cycle.plan(technologies, mods) == 1
          end
          local function current_result(technologies)
            return repair.apply({technology=technologies}, mods, target) == 1
          end
          local function graph(edges)
            local technologies = {astroponics={prerequisites={"landfill", "space-science-pack"}}}
            for name, prerequisites in pairs(edges) do technologies[name] = {prerequisites=prerequisites} end
            return technologies
          end
          local cases = {
            {"direct", true, { ["space-science-pack"]={"astroponics"} }},
            {"longer", true, { ["space-science-pack"]={"middle"}, middle={"end"}, ["end"]={"astroponics"} }},
            {"branched", true, { ["space-science-pack"]={"dead", "branch"}, dead={}, branch={"loop", "middle"}, loop={"branch"}, middle={"astroponics"} }},
            {"self-cyclic", true, { ["space-science-pack"]={"space-science-pack", "astroponics"} }},
            {"unreachable", false, { ["space-science-pack"]={"dead"}, dead={"dead"} }},
          }
          for _, case in ipairs(cases) do
            local name, expected, edges = case[1], case[2], case[3]
            local historical = graph(edges)
            assert(historical_result(historical) == expected, name .. " historical result")
            local current = graph(edges)
            local original = current.astroponics.prerequisites
            assert(current_result(current) == historical_result(graph(edges)), name .. " current parity")
            if expected then
              assert(current.astroponics.prerequisites ~= original and #current.astroponics.prerequisites == 1
                and current.astroponics.prerequisites[1] == "landfill", name .. " only declared edge removed")
            else
              assert(current.astroponics.prerequisites == original, name .. " no proof leaves declared edge")
            end
          end
        ''')

    def test_astroponics_reachability_is_deterministic_and_visits_only_the_reached_graph_once(self):
        self.lua.execute('''
          local mods, target = {astroponics="1.7.3", ["planet-muluna"]="2.3.18"}, {id="f210"}
          local function graph(space_edges, branch_edges)
            return {
              astroponics={prerequisites={"landfill", "space-science-pack"}},
              ["space-science-pack"]={prerequisites=space_edges},
              alpha={prerequisites={"shared"}},
              branch={prerequisites=branch_edges},
              shared={prerequisites={"astroponics"}},
              cycle={prerequisites={"branch"}},
            }
          end
          local first = graph({"alpha", "branch"}, {"cycle", "shared"})
          local second = graph({"branch", "alpha"}, {"shared", "cycle"})
          assert(#published_cycle.plan(first, mods) == 1 and #published_cycle.plan(second, mods) == 1)
          assert(repair.apply({technology=first}, mods, target) == 1)
          assert(repair.apply({technology=second}, mods, target) == 1)
          assert(#first.astroponics.prerequisites == 1 and first.astroponics.prerequisites[1] == "landfill")
          assert(#second.astroponics.prerequisites == 1 and second.astroponics.prerequisites[1] == "landfill")

          local backing = {
            astroponics={prerequisites={"landfill", "space-science-pack"}},
            ["space-science-pack"]={prerequisites={"alpha", "branch"}},
            alpha={prerequisites={"shared"}},
            branch={prerequisites={"shared", "cycle"}},
            shared={prerequisites={"astroponics"}},
            cycle={prerequisites={"branch"}},
          }
          local reads = {}
          local technologies = setmetatable({}, {
            __index=function(_, name)
              if name == "poison" then error("unrelated world inspected") end
              reads[name] = (reads[name] or 0) + 1
              return backing[name]
            end,
            __pairs=function() error("prototype world enumerated") end,
          })
          assert(repair.apply({technology=technologies}, mods, target) == 1)
          for _, name in ipairs({"astroponics", "space-science-pack", "alpha", "branch", "shared", "cycle"}) do
            assert(reads[name] == 1, name .. " inspected more than once")
          end
          assert(reads.poison == nil)
        ''')

    def test_data_final_imports_the_repair_only_for_an_active_supported_named_input(self):
        import test_generator
        test_generator.LuaRuntime = LuaRuntime
        host = test_generator.GeneratorTests("runTest")
        host.setUp()
        host.lua.execute('''
          local environment = full_world({})
          local modules = {enabled=true,prerequisites={"automation", "angels-silver-smelting-1"}}
          local astroponics = {prerequisites={"landfill", "space-science-pack"}}
          environment.raw.technology.modules = modules
          environment.raw.technology["angels-silver-smelting-1"] = {enabled=false}
          environment.raw.technology.astroponics = astroponics
          environment.raw.technology["space-science-pack"] = {prerequisites={"muluna-alice-propellant"}}
          environment.raw.technology["muluna-alice-propellant"] = {prerequisites={"astroponics"}}
          local messages = {}
          settings, mods, data, helpers, log = {startup=defaults()}, {
            base="2.1.23",angelssmelting="1.0.0",astroponics="1.7.3",["planet-muluna"]="2.3.18"
          }, environment, nil, function(message) messages[#messages + 1] = message end
          package.loaded["overrides.prerequisite_repairs"] = nil
          assert(dofile(data_final_path) == nil and package.loaded["overrides.prerequisite_repairs"] ~= nil)
          assert(#modules.prerequisites == 1 and modules.prerequisites[1] == "automation")
          assert(#astroponics.prerequisites == 1 and astroponics.prerequisites[1] == "landfill")
          assert(#messages == 2 and messages[1] == "[more-infinite-research] Repaired "
            .. "angels-disabled-silver-modules-prerequisite: removed modules -> angels-silver-smelting-1.")
          assert(messages[2] == "[more-infinite-research] Repaired "
            .. "muluna-astroponics-space-science-cycle: removed astroponics -> space-science-pack.")
        ''')

        inactive = test_generator.GeneratorTests("runTest")
        inactive.setUp()
        inactive.lua.execute('''
          settings, mods, data, helpers, log = {startup=defaults()}, {base="2.1.23"}, full_world({}), nil, function() end
          package.loaded["overrides.prerequisite_repairs"] = nil
          package.preload["overrides.prerequisite_repairs"] = function() error("inactive repair import") end
          local ok, message = pcall(dofile, data_final_path)
          package.preload["overrides.prerequisite_repairs"] = nil
          assert(ok, message)
          assert(package.loaded["overrides.prerequisite_repairs"] == nil)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PrerequisiteRepairTests))
    sys.exit(0 if result.wasSuccessful() else 1)

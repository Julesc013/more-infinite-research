"""Pure Lua controls for the bounded MIR science and laboratory policy."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"


class ScienceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          science = require("research.science")
          bindings = require("compatibility.science_bindings")

          function raw_with(packs, labs, technologies)
            local raw = {item = {}, tool = {}, lab = {}, technology = technologies or {}}
            for _, name in ipairs(packs or {}) do raw.tool[name] = {name=name} end
            for name, inputs in pairs(labs or {}) do raw.lab[name] = {name=name, inputs=inputs} end
            return raw
          end
          function technology(ingredients, prerequisites)
            return {name="mir-owned", enabled=true, prerequisites=prerequisites or {},
              unit={ingredients=ingredients, count_formula="100*1.5^(L-1)", time=60}}
          end
          function names(rows)
            local out = {}
            for _, row in ipairs(rows or {}) do out[#out+1] = row[1] .. ":" .. tostring(row[2]) end
            return table.concat(out, ",")
          end
          function same(left, right)
            if #left ~= #right then return false end
            for index, value in ipairs(left) do if value ~= right[index] then return false end end
            return true
          end
        ''')

    def test_generation_report_names_each_owned_outcome_only_when_enabled(self):
        self.lua.execute(r'''
          local messages, options = {}, {["mir-lab-incompatibility-policy"]="skip"}
          local raw = raw_with({"automation-science-pack","logistic-science-pack"},
            {restricted={"automation-science-pack"}})
          local function run()
            return science.apply_family({technology({{"logistic-science-pack",1}})}, nil, {
              options=options, raw=raw, target={id="f210"}, mods={},
              log=function(message) messages[#messages+1] = message end})
          end
          local reports = run()
          assert(reports[1].enabled == false and #messages == 0)
          options["mir-debug-generation-report"] = true
          run()
          assert(#messages == 1 and messages[1] ==
            "[more-infinite-research] mir-owned: disabled (lab-incompatible-skip)")
        ''')

    def test_target_bindings_keep_historical_aliases_and_named_end_gates(self):
        self.lua.execute(r'''
          local early = bindings.select({id="f013"}, {})
          assert(same(early.official, {"science-pack-1","science-pack-2","science-pack-3","alien-science-pack"}))
          assert(early.progression["alien-science-pack"][4] == "alien-science-pack")
          assert(early.end_game.pack == "alien-science-pack" and early.end_game.prerequisites[1] == "alien-technology")

          local middle = bindings.select({id="f016"}, {})
          assert(same(middle.official, {"science-pack-1","science-pack-2","science-pack-3","production-science-pack","military-science-pack","high-tech-science-pack","space-science-pack"}))
          assert(middle.progression["high-tech-science-pack"][5] == "high-tech-science-pack")
          assert(same(middle.pack_prerequisites["space-science-pack"], {"rocket-silo"}))
          assert(same(middle.pack_prerequisites["science-pack-3"], {"advanced-electronics", "engine"}))

          local modern = bindings.select({id="f210"}, {})
          assert(modern.end_game.pack == "space-science-pack" and modern.end_game.prerequisites[1] == "space-science-pack")
          assert(middle.end_game.pack == "space-science-pack" and middle.end_game.prerequisites[1] == "rocket-silo")
          local f017 = bindings.select({id="f017"}, {})
          assert(f017.end_game.prerequisites[1] == "space-science-pack")
          assert(same(f017.pack_prerequisites["space-science-pack"], {"space-science-pack"}))
          local f100 = bindings.select({id="f100"}, {})
          assert(f100.pack_prerequisites["logistic-science-pack"] == nil)
          assert(same(f100.pack_prerequisites["space-science-pack"], {"space-science-pack"}))
          local f110 = bindings.select({id="f110"}, {})
          assert(same(f110.pack_prerequisites["space-science-pack"], {"space-science-pack"}))
          local space = bindings.select({id="f210"}, {["space-age"]="2.1.23"})
          assert(space.end_game.pack == "promethium-science-pack" and space.end_game.prerequisites[1] == "promethium-science-pack")
          assert(#space.official == 12 and space.progression["promethium-science-pack"][12] == "promethium-science-pack")

          local unknown = bindings.select({id="unreviewed-target"}, {})
          assert(#unknown.official == 0 and unknown.space == nil and unknown.end_game == nil)
        ''')

    def test_policies_preserve_existing_order_amounts_and_append_only_missing_packs(self):
        self.lua.execute(r'''
          local packs = {"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack",
            "military-science-pack","utility-science-pack","space-science-pack","agricultural-science-pack",
            "metallurgic-science-pack","electromagnetic-science-pack","cryogenic-science-pack","promethium-science-pack","external-card"}
          local raw = raw_with(packs, {whole=packs})
          for _, name in ipairs(packs) do raw.technology[name] = {} end
          local env = {raw=raw, target={id="f210"}, mods={["space-age"]="2.1.23"}}

          env.options = {["mir-science-pack-ingredient-policy"]="configured"}
          local configured = technology({{"external-card",7},{"automation-science-pack",3}})
          assert(science.apply(configured, {}, science.prepare(env)).reason == "configured")
          assert(names(configured.unit.ingredients) == "external-card:7,automation-science-pack:3")

          env.options["mir-science-pack-ingredient-policy"] = "all-official"
          local official = technology({{"external-card",7},{"automation-science-pack",3}})
          science.apply(official, {}, science.prepare(env))
          assert(names(official.unit.ingredients) == "automation-science-pack:3,logistic-science-pack:1,chemical-science-pack:1,production-science-pack:1,military-science-pack:1,utility-science-pack:1,space-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1")

          env.options["mir-science-pack-ingredient-policy"] = "space"
          local space_only = technology({{"automation-science-pack",3}})
          science.apply(space_only, {}, science.prepare(env))
          assert(names(space_only.unit.ingredients) == "automation-science-pack:3,space-science-pack:1")

          env.options["mir-science-pack-ingredient-policy"] = "space-and-promethium"
          local space_promethium = technology({{"automation-science-pack",3}})
          science.apply(space_promethium, {}, science.prepare(env))
          assert(names(space_promethium.unit.ingredients) == "automation-science-pack:3,space-science-pack:1,promethium-science-pack:1")

          env.options["mir-science-pack-ingredient-policy"] = "space-age-progression"
          local phase = technology({{"promethium-science-pack",5}})
          science.apply(phase, {}, science.prepare(env))
          assert(names(phase.unit.ingredients) == "promethium-science-pack:5,space-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1")

          env.options["mir-science-pack-ingredient-policy"] = "official-progression"
          local high = technology({{"promethium-science-pack",5}})
          science.apply(high, {}, science.prepare(env))
          assert(names(high.unit.ingredients):find("promethium-science-pack:5", 1, true) == 1)
          assert(#high.unit.ingredients == 12)

          env.options["mir-science-pack-ingredient-policy"] = "all"
          local all_inputs = technology({{"external-card",7},{"automation-science-pack",3}})
          science.apply(all_inputs, {}, science.prepare(env))
          assert(names(all_inputs.unit.ingredients) == "external-card:7,automation-science-pack:3,logistic-science-pack:1,chemical-science-pack:1,production-science-pack:1,military-science-pack:1,utility-science-pack:1,space-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1")
        ''')

    def test_lab_policies_never_union_labs_and_disable_established_identity(self):
        self.lua.execute(r'''
          local raw = raw_with({"A","B","foreign"}, {a={"A"}, b={"B"}, pair={"A","B"}})
          local env = {raw=raw, target={id="f210"}, options={}}
          local reduced = technology({{"A",2},{"B",3},{"foreign",4}})
          local result = science.apply(reduced, {}, science.prepare(env))
          assert(result.reason == "lab-reduced" and names(reduced.unit.ingredients) == "A:2,B:3")

          raw.lab.pair = nil
          local no_union = technology({{"A",2},{"B",3}})
          result = science.apply(no_union, {}, science.prepare(env))
          assert(result.reason == "lab-reduced" and #no_union.unit.ingredients == 1)

          env.options["mir-lab-incompatibility-policy"] = "skip"
          local skipped = technology({{"A",2},{"B",3}})
          result = science.apply(skipped, {}, science.prepare(env))
          assert(not result.enabled and skipped.enabled == false and skipped.name == "mir-owned")
          assert(names(skipped.unit.ingredients) == "A:2,B:3")

          env.options["mir-lab-incompatibility-policy"] = "engine-default"
          local strict = technology({{"A",2},{"B",3}})
          result = science.apply(strict, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "lab-incompatible-engine-default")
        ''')

    def test_lab_collector_keeps_supported_non_tool_research_items(self):
        self.lua.execute(r'''
          local raw = raw_with({}, {lab={"archival-token"}})
          raw["mining-tool"] = { ["archival-token"] = {name="archival-token"} }
          local row = technology({{"archival-token", 9}})
          local result = science.apply(row, {}, science.prepare({raw=raw, target={id="f014"}, options={}}))
          assert(result.enabled and names(row.unit.ingredients) == "archival-token:9")
        ''')

    def test_empty_broad_selection_retains_a_disabled_valid_identity(self):
        self.lua.execute(r'''
          local raw = raw_with({"foreign-only"}, {lab={"foreign-only"}})
          local row = technology({{"foreign-only", 6}})
          local result = science.apply(row, {}, science.prepare({raw=raw, target={id="f210"},
            options={ ["mir-science-pack-ingredient-policy"]="all-official" }}))
          assert(not result.enabled and result.reason == "empty-science-selection" and row.enabled == false)
          assert(names(row.unit.ingredients) == "foreign-only:6")
        ''')

    def test_preserved_hidden_carrier_bypasses_every_science_policy_and_gate(self):
        self.lua.execute(r'''
          local raw = raw_with({"legacy-card"}, {})
          local row = technology({{"legacy-card", 6}}, {"earned-carrier"})
          row.enabled = false
          local result = science.apply(row, {preserve_identity=true, space_gate=false}, science.prepare({raw=raw,
            target={id="f210"}, options={ ["ips-require-space-gate"]=true,
              ["mir-science-pack-ingredient-policy"]="all-official" }}))
          assert(not result.enabled and result.reason == "preserved-carrier")
          assert(names(row.unit.ingredients) == "legacy-card:6" and row.prerequisites[1] == "earned-carrier")
        ''')

    def test_required_and_phase_science_survive_reduction_or_disable_before_publication(self):
        self.lua.execute(r'''
          local raw = raw_with({"A","cryo","phase"}, {a={"A"}, good={"A","cryo","phase"}})
          local env = {raw=raw, target={id="f210"}, options={}}
          local row = technology({{"A",2}})
          local result = science.apply(row, {required_science={"cryo"},phase_any_science={"phase"}}, science.prepare(env))
          -- The phase list constrains reduction; it does not fabricate an
          -- additional science ingredient that the authored row did not have.
          assert(not result.enabled and row.enabled == false and result.reason == "lab-incompatible-reduce")
          assert(names(row.unit.ingredients) == "A:2,cryo:1")

          row = technology({{"A",2},{"phase",4}})
          result = science.apply(row, {required_science={"cryo"},phase_any_science={"phase"}}, science.prepare(env))
          assert(result.enabled and names(row.unit.ingredients) == "A:2,phase:4,cryo:1")

          raw.tool.cryo = nil
          row = technology({{"A",2}})
          result = science.apply(row, {required_science={"cryo"}}, science.prepare(env))
          assert(not result.enabled and result.reason == "missing-required-science:cryo")
        ''')

    def test_named_space_gates_and_explicit_mod_progression_bindings(self):
        self.lua.execute(r'''
          local raw = raw_with({"A","promethium-science-pack","foreign","foreign-earlier"},
            {lab={"A","promethium-science-pack","foreign","foreign-earlier"}},
            { ["promethium-science-pack"]={} })
          local env = {raw=raw, target={id="f210"}, mods={["space-age"]="2.1.23"},
            options={ ["ips-require-space-gate"]=true, ["mir-science-pack-ingredient-policy"]="mod-progression" }}
          local context = science.prepare(env)
          local row = technology({{"A",2},{"foreign",4}}, {"existing"})
          local result = science.apply(row, {mod_progression={foreign={"foreign-earlier"}}}, context)
          assert(result.enabled and names(row.unit.ingredients) == "A:2,foreign:4,foreign-earlier:1")
          assert(row.prerequisites[1] == "existing" and row.prerequisites[2] == "promethium-science-pack")

          local missing = technology({{"A",2}})
          raw.technology["promethium-science-pack"] = nil
          result = science.apply(missing, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "missing-end-game-gate-prerequisite:promethium-science-pack")

          env.options["ips-require-space-gate"] = false
          local unknown = technology({{"A",2},{"foreign",4}})
          context = science.prepare(env)
          result = science.apply(unknown, {}, context)
          assert(result.enabled and context.mod_progression_unbound.foreign and names(unknown.unit.ingredients) == "A:2,foreign:4")
        ''')

    def test_policy_added_science_uses_only_explicit_target_prerequisites(self):
        self.lua.execute(r'''
          local raw = raw_with({"A", "space-science-pack"},
            {lab={"A", "space-science-pack"}}, { ["space-science-pack"]={} })
          local env = {raw=raw, target={id="f210"},
            options={ ["mir-science-pack-ingredient-policy"]="space", ["ips-require-space-gate"]=false }}
          local row = technology({{"A",2}}, {"existing"})
          local result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled and names(row.unit.ingredients) == "A:2,space-science-pack:1")
          assert(table.concat(row.prerequisites, ",") == "existing,space-science-pack")

          raw.technology["space-science-pack"] = nil
          local missing = technology({{"A",2}}, {"existing"})
          result = science.apply(missing, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "missing-science-prerequisite:space-science-pack:space-science-pack")
          assert(names(missing.unit.ingredients) == "A:2" and missing.prerequisites[1] == "existing")

          raw.technology["rocket-silo"] = {}
          local legacy = technology({{"science-pack-1",2}})
          raw.tool["science-pack-1"] = {name="science-pack-1"}
          raw.tool["space-science-pack"] = {name="space-science-pack"}
          result = science.apply(legacy, {}, science.prepare({raw=raw, target={id="f016"},
            options={ ["mir-science-pack-ingredient-policy"]="space" }}))
          assert(result.enabled and table.concat(legacy.prerequisites, ",") == "rocket-silo")
        ''')

    def test_exact_k2so_phase_binding_normalizes_selected_policy_and_preserves_a_phase_trigger(self):
        self.lua.execute(r'''
          local packs = {"kr-basic-tech-card","automation-science-pack","production-science-pack",
            "space-science-pack","kr-advanced-tech-card"}
          local raw = raw_with(packs, {whole=packs, late={"production-science-pack","space-science-pack"}})
          for _, name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
            "production-science-pack","military-science-pack","utility-science-pack","space-science-pack"}) do
            raw.technology[name] = {}
          end
          local exact = {
            base="2.1.23", ["space-age"]="2.1.23", Krastorio2="2.1.4",
            ["Krastorio2-spaced-out"]="2.0.19", Krastorio2Assets="2.1.0", ["k2so-assets"]="1.0.7"
          }
          local env = {raw=raw, target={id="f210"}, mods=exact,
            options={ ["mir-science-pack-ingredient-policy"]="configured" }}
          local row = technology({{"kr-basic-tech-card",3},{"automation-science-pack",2},{"production-science-pack",4}})
          local result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled and names(row.unit.ingredients) == "automation-science-pack:2,production-science-pack:4")

          env.options["mir-science-pack-ingredient-policy"] = "all"
          row = technology({{"production-science-pack",4}})
          result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled and names(row.unit.ingredients):find("kr-basic-tech-card", 1, true) == nil)
          assert(names(row.unit.ingredients):find("production-science-pack:4", 1, true) ~= nil)
          assert(names(row.unit.ingredients):find("kr-advanced-tech-card:1", 1, true) ~= nil)

          local markers = {"base", "space-age", "Krastorio2", "Krastorio2-spaced-out", "Krastorio2Assets", "k2so-assets"}
          for _, marker in ipairs(markers) do
            local partial = {}
            for name, version in pairs(exact) do partial[name] = version end
            partial[marker] = nil
            assert(bindings.select({id="f210"}, partial).k2_phase == nil, "partial K2SO phase selected for " .. marker)
            row = technology({{"kr-basic-tech-card",3},{"production-science-pack",4}})
            result = science.apply(row, {}, science.prepare({raw=raw, target={id="f210"}, mods=partial, options={}}))
            assert(result.enabled and names(row.unit.ingredients) == "kr-basic-tech-card:3,production-science-pack:4")
          end

          for _, marker in ipairs(markers) do
            local unknown = {}
            for name, version in pairs(exact) do unknown[name] = version end
            unknown[marker] = "unreviewed-version"
            assert(bindings.select({id="f210"}, unknown).k2_phase == nil, "unknown K2SO phase selected for " .. marker)
            row = technology({{"kr-basic-tech-card",3},{"production-science-pack",4}})
            result = science.apply(row, {}, science.prepare({raw=raw, target={id="f210"}, mods=unknown, options={}}))
            assert(result.enabled and names(row.unit.ingredients) == "kr-basic-tech-card:3,production-science-pack:4")
          end
        ''')

    def test_family_reuses_one_bounded_collector(self):
        self.lua.execute(r'''
          local raw = raw_with({"A","B","C"}, {z={"A"}, a={"A","B"}, c={"A","B","C"}})
          local rows, bindings = {}, {}
          for index = 1, 75 do rows[index], bindings[index] = technology({{"A",1},{"B",1}}), {} end
          local reports, context = science.apply_family(rows, bindings, {raw=raw, target={id="f210"}, options={}})
          assert(context.lab_visits == 3 and #reports == 75)
          for _, row in ipairs(rows) do assert(names(row.unit.ingredients) == "A:1,B:1") end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ScienceTests))
    sys.exit(0 if result.wasSuccessful() else 1)

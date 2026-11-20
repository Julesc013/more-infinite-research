"""Incident #1807 final-output regressions; host controls, never native evidence.

These controls intentionally fail on the reported dev baseline. They are a
separate Aero expectation proposal until the integrator accepts the source fix.
"""
import argparse
import hashlib
from pathlib import Path
import sys
import unittest
import zipfile

from test_science import ScienceTests

WORKER_SOURCE = None
SIF_UPDATES = None
SIF_PREREQUISITES = None


class SifFinalOutputTests(unittest.TestCase):
    def setUp(self):
        # Reuse only the existing stage-faithful science-input doubles. Expected
        # identities below are incident obligations, not candidate snapshots.
        self.harness = ScienceTests()
        self.harness.setUp()
        self.lua = self.harness.lua
        self.lua.execute(r'''
          catalogue = require("compatibility.modern_catalogue")
          modern = require("research.modern")
          generator = require("research.generator")
          packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"}
          function copy(value)
            if type(value) ~= "table" then return value end
            local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
          end
          function same_table(left, right)
            if type(left) ~= type(right) then return false end
            if type(left) ~= "table" then return left == right end
            for key, value in pairs(left) do if not same_table(value, right[key]) then return false end end
            for key in pairs(right) do if left[key] == nil then return false end end
            return true
          end
          function has(values, name)
            for _, value in ipairs(values or {}) do
              if (type(value) == "table" and (value.name or value[1]) or value) == name then return true end
            end
            return false
          end
          function environment(target, retired, sif)
            require("platform.target").id = target
            local mods = {["space-age"] = target == "f200" and "2.0.77" or "2.1.23"}
            if sif then mods["space-is-fake"] = target == "f200" and "1.0.60" or "1.0.78" end
            local raw = install_sources(raw_with(packs, {whole=packs}), true, target)
            if target == "f210" then
              raw.item["space-science-pack"] = raw.tool["space-science-pack"]
              raw.tool["space-science-pack"] = nil
            end
            if sif then
              raw.technology["promethium-science-pack"].prerequisites = {
                "agricultural-science-pack", "metallurgic-science-pack",
                "electromagnetic-science-pack", "quantum-processor"}
              if target == "f200" then
                table.insert(raw.technology["promethium-science-pack"].prerequisites, "fusion-reactor")
              end
              raw.technology["quantum-processor"] = {}
            end
            if retired then
              -- Actual archived SIF rewrites this owner and hides the recipe,
              -- item and technology. A leftover satellite field is deliberate:
              -- it does not restore Space Age's retired native source contract.
              raw.technology["space-science-pack"].prerequisites = {
                "utility-science-pack", "production-science-pack"}
              raw.technology["space-science-pack"].hidden = true
              raw.recipe["space-science-pack"].hidden = true
              (raw.item["space-science-pack"] or raw.tool["space-science-pack"]).hidden = true
              raw.item.satellite = {name="satellite",
                rocket_launch_products={{type="item",name="space-science-pack",amount=1000}}}
            end
            for _, name in ipairs({"finite-anchor", "research-speed-5", "research-speed-6",
                "weapon-shooting-speed-5", "weapon-shooting-speed-6", "laser-shooting-speed-6",
                "laser-shooting-speed-7", "braking-force-6", "braking-force-7",
                "inserter-capacity-bonus-6", "inserter-capacity-bonus-7",
                "worker-robots-storage-2", "worker-robots-storage-3"}) do
              raw.technology[name] = {type="technology",name=name}
            end
            return raw, mods
          end
          function authored(family, raw, mods)
            for _, definition in ipairs(catalogue.continuations(mods, raw)) do
              if definition.family == family then
                return modern.continuation(definition, {streams={[family]=definition.defaults}})
              end
            end
            error("missing required continuation " .. family)
          end
          function publish(rows, raw, mods, policy, gate, family_bindings)
            local reports = science.apply_family(rows, family_bindings, {raw=raw,
              target=require("platform.target"), mods=mods, options={
                ["mir-science-pack-ingredient-policy"]=policy,
                ["ips-require-space-gate"]=gate or false}})
            local stage = {raw=raw, writes=0, output={}}
            function stage:extend(values)
              self.writes = self.writes + 1
              for _, value in ipairs(values) do self.output[value.name] = value end
            end
            generator.install(rows, stage)
            assert(stage.writes == 1, "final family did not publish exactly once")
            return stage.output, reports
          end
          function useful(row, white)
            assert(row ~= nil and row.enabled ~= false and row.hidden ~= true,
              "intended public research disappeared, became disabled or became hidden")
            assert(#row.unit.ingredients > 0 and #row.effects > 0, "research lost its useful work")
            assert(has(row.unit.ingredients, "space-science-pack") == white,
              row.name .. ": final white-science ingredient differs")
            if not white then
              assert(not has(row.prerequisites, "space-science-pack"), row.name .. ": retired gate survived")
            end
          end
          function preserved_ingredients(before, after)
            local index = 0
            for _, ingredient in ipairs(before) do
              if ingredient[1] ~= "space-science-pack" then
                index = index + 1
                local got = after[index]
                assert(got and got[1] == ingredient[1] and got[2] == ingredient[2],
                  "retirement changed unaffected ingredient order, identity or amount")
              end
            end
          end
        ''')

    def test_all_six_authored_tails_retire_white_at_final_publication(self):
        for target in ("f200", "f210"):
            for family, identity in (
                ("braking-force", "braking-force-8"),
                ("inserter-capacity-bonus", "inserter-capacity-bonus-8"),
                ("laser-shooting-speed", "laser-shooting-speed-8"),
                ("research-speed", "research-speed-7"),
                ("weapon-shooting-speed", "weapon-shooting-speed-7"),
                ("worker-robots-storage", "worker-robots-storage-4"),
            ):
                for policy in ("configured", "space", "all-official", "all"):
                    with self.subTest(target=target, family=family, policy=policy):
                        self.lua.globals().case_target = target
                        self.lua.globals().case_family = family
                        self.lua.globals().case_identity = identity
                        self.lua.globals().case_policy = policy
                        self.lua.execute(r'''
                          local raw, mods = environment(case_target, true, true)
                          local row = authored(case_family, raw, mods)
                          assert(row.name == case_identity, "historical public identity changed")
                          local before, foreign = copy(row), copy(raw)
                          local output = publish({row}, raw, mods, case_policy, true)
                          useful(output[case_identity], false)
                          assert(same_table(before.effects, row.effects), "earned effect vector changed")
                          assert(before.unit.count_formula == row.unit.count_formula and before.unit.time == row.unit.time,
                            "retirement changed cost or time")
                          preserved_ingredients(before.unit.ingredients,row.unit.ingredients)
                          for _, gate in ipairs(before.prerequisites) do
                            if gate ~= "space-science-pack" then assert(has(row.prerequisites,gate), "lost a finite anchor") end
                          end
                          assert(has(row.prerequisites,"promethium-science-pack"), "lost selected usable end-game gate")
                          assert(same_table(foreign, raw), "science policy mutated foreign prototypes")
                        ''')

    def test_shifted_supported_weapon_tail_retains_retirement(self):
        self.lua.execute(r'''
          local raw, mods = environment("f210", true, true)
          local row = authored("weapon-shooting-speed", raw, mods)
          -- Opposing suffix control: the family's rule survives a selected
          -- finite-provider shift; this does not claim native provider proof.
          row.name, row.level = "weapon-shooting-speed-9", 9
          local output = publish({row}, raw, mods, "configured")
          useful(output["weapon-shooting-speed-9"], false)
        ''')

    def test_productivity_research_stays_useful_under_expanded_policies(self):
        for target in ("f200", "f210"):
            for policy in ("configured", "space", "space-and-promethium", "space-age-progression",
                           "official-progression", "mod-progression", "all-official", "all"):
                with self.subTest(target=target, policy=policy):
                    self.lua.globals().case_target = target
                    self.lua.globals().case_policy = policy
                    self.lua.execute(r'''
                      local raw, mods = environment(case_target,true,true)
                      -- Exact retained authored rocket-productivity targets.
                      -- These are independent fixture names, not effect targets
                      -- discovered from a candidate's unexpected output.
                      for _, name in ipairs({"rocket","explosive-rocket","atomic-bomb"}) do
                        raw.recipe[name] = {name=name}
                      end
                      local definition
                      for _, candidate in ipairs(catalogue.select(mods,raw).definitions) do
                        if candidate.key == "research_rockets" then definition = candidate end
                      end
                      assert(definition, "intended productivity family disappeared")
                      local row = modern.technology(definition,{streams={research_rockets=definition.tuning}})
                      local before = copy(row)
                      local output = publish({row},raw,mods,case_policy,true)
                      useful(output["recipe-prod-research_rockets-1"],false)
                      assert(same_table(before.effects,row.effects) and before.unit.count_formula == row.unit.count_formula
                        and before.unit.time == row.unit.time, "science repair changed productivity tuning")
                      preserved_ingredients(before.unit.ingredients,row.unit.ingredients)
                    ''')

    def test_required_white_cannot_restore_the_retired_role(self):
        self.lua.execute(r'''
          local raw, mods = environment("f210", true, true)
          local row = authored("research-speed", raw, mods)
          local binding = bindings.conditions_for("research-speed", row.name, mods)
          binding.required_science = {"space-science-pack"}
          local output = publish({row}, raw, mods, "all-official", true, {[1]=binding})
          useful(output[row.name], false)
        ''')

    def test_an_independently_restored_white_source_remains_available_with_sif(self):
        self.lua.execute(r'''
          local raw, mods = environment("f210", false, true)
          local row = authored("research-speed", raw, mods)
          -- Deliberate restored-source opponent, not an unmodified SIF capture:
          -- another supported source has restored the valid recipe/trigger/gate.
          -- Hidden presentation alone cannot negate that usable relationship.
          raw.item["space-science-pack"].hidden = true
          assert(science.validate_source_contract(raw,
            bindings.select(require("platform.target"), mods).source_contracts["space-science-pack"],
            "space-science-pack"), "positive white source is not actually admitted")
          local output = publish({row}, raw, mods, "configured")
          useful(output[row.name], true)
        ''')

    def test_no_sif_retains_white_and_its_gate(self):
        self.lua.execute(r'''
          local raw, mods = environment("f210", false, false)
          local row = authored("research-speed", raw, mods)
          local output = publish({row}, raw, mods, "configured")
          useful(output[row.name], true)
          assert(has(output[row.name].prerequisites, "space-science-pack"))
        ''')

    def test_preserved_private_holder_is_unchanged(self):
        self.lua.execute(r'''
          local raw, mods = environment("f210", true, true)
          local row = authored("research-speed", raw, mods)
          row.name, row.hidden = "mir-private-regression-1", true
          local before = copy(row)
          publish({row}, raw, mods, "all", true, {[1]={preserve_identity=true,space_gate=false}})
          assert(same_table(before, row), "retirement changed an explicit private earned-state holder")
        ''')

    def test_internal_duplicate_still_refuses_before_publication(self):
        self.lua.execute(r'''
          local raw, mods = environment("f210", true, true)
          local row = authored("research-speed", raw, mods)
          local stage = {raw=raw,writes=0}
          function stage:extend() self.writes = self.writes + 1 end
          local ok, message = pcall(generator.install, {row,copy(row)}, stage)
          assert(not ok and tostring(message):find("duplicate technology",1,true) and stage.writes == 0)
        ''')

    def test_actual_worker_source_and_sif_retirement_compose_before_mir(self):
        if WORKER_SOURCE is None:
            self.skipTest("supply exact --worker-data-source and --sif-archive for source execution")
        for maximum in (4, 5, 7, 10):
            for infinite in (False, True):
                with self.subTest(maximum=maximum, infinite=infinite):
                    self.lua.globals().worker_source = WORKER_SOURCE
                    self.lua.globals().sif_updates = SIF_UPDATES
                    self.lua.globals().sif_prerequisites = SIF_PREREQUISITES
                    self.lua.globals().worker_maximum = maximum
                    self.lua.globals().worker_infinite = infinite
                    self.lua.execute(r'''
                      local raw, mods = environment("f210", true, true)
                      mods.WorkerRobotCargoSizeResearch = "1.0.0"
                      raw.technology["worker-robots-storage-1"] = {type="technology",
                        name="worker-robots-storage-1",icons={{icon="host-only.png",icon_size=64}}}
                      -- A valid finite predecessor is needed to inherit the
                      -- growth from max4, where no provider level5 exists.
                      raw.technology["worker-robots-storage-3"].unit = {
                        count=450,time=60,ingredients={{"utility-science-pack",1}}}
                      data = {raw=raw}
                      function data:extend(rows)
                        for _, row in ipairs(rows) do
                          assert(self.raw[row.type][row.name] == nil, "upstream duplicate " .. row.name)
                          self.raw[row.type][row.name] = row
                        end
                      end
                      settings = {startup={
                        ["worker-robot-cargo-size-max-level"]={value=worker_maximum},
                        ["worker-robot-cargo-size-infinite"]={value=worker_infinite}}}
                      assert(load(worker_source, "unchanged-worker-data", "t"))()
                      assert(has(raw.technology["worker-robots-storage-4"].unit.ingredients,"space-science-pack"))
                      assert(load(sif_updates, "unchanged-sif-data-updates", "t"))()
                      -- Execute the exact pinned archive's local replacement
                      -- function and its white-gate call, without loading its
                      -- unrelated world/recipe/entity transformations.
                      assert(load("local sif_tech=data.raw.technology; local debug=function()end;\n"
                        .. sif_prerequisites, "exact-sif-prerequisite-replacement", "t"))()
                      local upstream_tail = worker_maximum + (worker_infinite and 1 or 0)
                      for level=4,upstream_tail do
                        local owner = assert(raw.technology["worker-robots-storage-" .. level])
                        assert(#owner.unit.ingredients == 5 and not has(owner.unit.ingredients,"space-science-pack"))
                        assert(not has(owner.prerequisites,"space-science-pack"))
                        assert(owner.effects[1].type == "worker-robot-storage" and owner.effects[1].modifier == 1)
                      end
                      assert(has(raw.technology["worker-robots-storage-4"].prerequisites,"utility-science-pack")
                        and has(raw.technology["worker-robots-storage-4"].prerequisites,"production-science-pack"))
                      local foreign = copy(raw)
                      local definition
                      for _, candidate in ipairs(catalogue.continuations(mods,raw)) do
                        if candidate.family == "worker-robots-storage" then
                          assert(definition == nil, "multiple MIR worker tails")
                          definition = candidate
                        end
                      end
                      if worker_infinite then
                        assert(definition == nil, "MIR overlaps the provider's infinite tail")
                      else
                        local expected = "worker-robots-storage-" .. (worker_maximum+1)
                        assert(definition and definition.id == expected, "MIR did not follow the actual finite provider tail")
                        local row = modern.continuation(definition,
                          {streams={[definition.family]=definition.defaults}})
                        local output = publish({row},raw,mods,"configured")
                        useful(output[expected],false)
                        assert(has(row.prerequisites,"worker-robots-storage-" .. worker_maximum))
                        -- Published v4.7.3 source/prototypes/mir/settings/defaults.lua
                        -- independently declares inherit + electromagnetic, also
                        -- retained by the pre-fix Space Age continuation binding.
                        local terminal = raw.technology["worker-robots-storage-" .. worker_maximum]
                        preserved_ingredients(terminal.unit.ingredients,row.unit.ingredients)
                        assert(#row.unit.ingredients == 6 and has(row.unit.ingredients,"electromagnetic-science-pack"),
                          "MIR lost adapted upstream science or its published electromagnetic addition")
                      end
                      assert(same_table(foreign,raw), "MIR mutated the adapted provider")
                    ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--player-source-root", type=Path,
                        help="Read-only source from an exact independent candidate checkout")
    parser.add_argument("--worker-data-source", type=Path)
    parser.add_argument("--sif-archive", type=Path)
    args = parser.parse_args()
    if bool(args.worker_data_source) != bool(args.sif_archive):
        parser.error("the two external source inputs must be supplied together")
    if args.worker_data_source:
        worker_bytes = args.worker_data_source.read_bytes()
        worker_blob = hashlib.sha1(f"blob {len(worker_bytes)}\0".encode() + worker_bytes).hexdigest()
        if worker_blob != "ec2cd18754032e4229c27d6b7a895c352356871d":
            parser.error("worker source differs from upstream commit 61c361b7")
        if hashlib.sha256(args.sif_archive.read_bytes()).hexdigest() != (
                "3b5f2a381adf1d9aecf048293e20035963a528720fbdc148ccc2b0418049ff13"):
            parser.error("SIF archive differs from the retained F210 1.0.78 input")
        with zipfile.ZipFile(args.sif_archive) as archive:
            SIF_UPDATES = archive.read("space-is-fake_1.0.78/data-updates.lua").decode("utf-8-sig")
            technology_source = archive.read("space-is-fake_1.0.78/prototypes/technology.lua").decode("utf-8-sig")
        start = technology_source.index("local function replace_prerequisite(")
        end = technology_source.index('\nreplace_prerequisite("biter-egg-handling"', start)
        call = 'replace_prerequisite("space-science-pack", {"utility-science-pack", "production-science-pack"})'
        if technology_source.count(call) != 1:
            parser.error("the retained SIF white-gate call changed")
        SIF_PREREQUISITES = technology_source[start:end] + "\n" + call
        WORKER_SOURCE = worker_bytes.decode("utf-8-sig")
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    import test_science
    test_science.LuaRuntime = LuaRuntime
    if args.player_source_root:
        test_science.PLAYER = args.player_source_root.resolve(strict=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SifFinalOutputTests))
    sys.exit(0 if result.wasSuccessful() else 1)

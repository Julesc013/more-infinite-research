"""Pure Lua controls for the bounded MIR science and laboratory policy."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"
NATIVE_SOURCE_ORACLE = ROOT / "tests/mir5/fixtures/science-source-native-oracle.json"


class ScienceTests(unittest.TestCase):
    def lua_value(self, value):
        if isinstance(value, dict):
            table = self.lua.table()
            for key, member in value.items():
                table[key] = self.lua_value(member)
            return table
        if isinstance(value, list):
            table = self.lua.table()
            for index, member in enumerate(value, start=1):
                table[index] = self.lua_value(member)
            return table
        return value

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          science = require("research.science")
          bindings = require("compatibility.science_bindings")

          function raw_with(packs, labs, technologies)
            local raw = {item = {}, tool = {}, recipe = {}, lab = {}, technology = technologies or {}}
            for _, name in ipairs(packs or {}) do raw.tool[name] = {name=name} end
            for name, inputs in pairs(labs or {}) do raw.lab[name] = {name=name, inputs=inputs} end
            return raw
          end
          function source_recipe(raw, pack, enabled)
            raw.recipe[pack] = {name=pack, enabled=enabled, results={{type="item", name=pack, amount=1}}}
          end
          function source_owner(raw, pack, owner, trigger, prerequisites)
            raw.technology[owner] = {name=owner, effects={{type="unlock-recipe", recipe=pack}},
              research_trigger=trigger, prerequisites=prerequisites}
          end
          function install_sources(raw, space_age, target)
            target = target or "f210"
            local base = {"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","military-science-pack","utility-science-pack"}
            if target == "f015" or target == "f016" then
              -- The installed 0.15/0.16 red and green definitions omit
              -- `enabled`; RecipePrototype defaults that field to true.
              source_recipe(raw, "science-pack-1", nil)
              source_recipe(raw, "science-pack-2", nil)
              for _, row in ipairs({{"science-pack-3","advanced-electronics"},
                {"production-science-pack","advanced-material-processing-2"},
                {"military-science-pack","military-2"}, {"high-tech-science-pack","advanced-electronics-2"}}) do
                source_recipe(raw, row[1], false); source_owner(raw, row[1], row[2])
              end
              source_recipe(raw, "space-science-pack", false)
              source_owner(raw, "rocket-silo", "rocket-silo")
              raw.item.satellite = {name="satellite"}
              if target == "f015" then
                raw["rocket-silo-rocket"] = { ["rocket-silo-rocket"] = {
                  result_items={{"space-science-pack",1000,"satellite"}}}}
              else raw.item.satellite.rocket_launch_product = {"space-science-pack",1000} end
              return raw
            end
            for _, pack in ipairs(base) do source_recipe(raw, pack, false); source_owner(raw, pack, pack) end
            if space_age then
              source_recipe(raw, "space-science-pack", false)
              source_owner(raw, "space-science-pack", "space-science-pack",
                {type="build-entity", entity="asteroid-collector"}, {"space-platform"})
              raw.technology["space-platform"] = {}
              for _, pack in ipairs({"agricultural-science-pack","metallurgic-science-pack","electromagnetic-science-pack"}) do
                source_recipe(raw, pack, false); source_owner(raw, pack, pack)
              end
              source_recipe(raw, "cryogenic-science-pack", false)
              source_owner(raw, "cryogenic-science-pack", "cryogenic-science-pack",
                {type="craft-item", item="cryogenic-plant"}, {"cryogenic-plant"})
              raw.technology["cryogenic-plant"] = {}
              source_recipe(raw, "promethium-science-pack", false)
              source_owner(raw, "promethium-science-pack", "promethium-science-pack", nil,
                {"biter-egg-handling", "stellar-discovery-solar-system-edge"})
              raw.technology["biter-egg-handling"] = {}
              raw.technology["stellar-discovery-solar-system-edge"] = {}
            elseif target == "f017" or target == "f100" or target == "f110" then
              raw.technology["space-science-pack"] = {name="space-science-pack",
                effects={{type="unlock-recipe", recipe="satellite"}}}
              raw.item.satellite = {name="satellite", rocket_launch_product={"space-science-pack",1000}}
            else
              raw.technology["space-science-pack"] = {name="space-science-pack",
                effects={}, research_trigger={type="send-item-to-orbit", item="satellite"}}
              raw.item.satellite = {name="satellite", rocket_launch_products={{type="item", name="space-science-pack", amount=1000}}}
            end
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
          install_sources(raw, true)
          raw.tool["unbound-lab-card"] = {name="unbound-lab-card"}
          raw.lab.whole.inputs[#raw.lab.whole.inputs + 1] = "unbound-lab-card"
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
          local all_context = science.prepare(env)
          local all_result = science.apply(all_inputs, {}, all_context)
          assert(names(all_inputs.unit.ingredients) == "external-card:7,automation-science-pack:3,logistic-science-pack:1,chemical-science-pack:1,production-science-pack:1,military-science-pack:1,utility-science-pack:1,space-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1")
          assert(all_result.reason == "all-unbound-sources" and all_context.unbound_science_sources["unbound-lab-card"] == "all")
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
          install_sources(raw, true)
          source_recipe(raw, "foreign-earlier", false)
          source_owner(raw, "foreign-earlier", "foreign-earlier-owner")
          local env = {raw=raw, target={id="f210"}, mods={["space-age"]="2.1.23"},
            options={ ["ips-require-space-gate"]=true, ["mir-science-pack-ingredient-policy"]="mod-progression" }}
          local context = science.prepare(env)
          local row = technology({{"A",2},{"foreign",4}}, {"existing"})
          local result = science.apply(row, {mod_progression={foreign={"foreign-earlier"}},
            mod_progression_sources={ ["foreign-earlier"]={kind="recipe-unlock", pack="foreign-earlier",
              recipe="foreign-earlier", owner="foreign-earlier-owner"}}}, context)
          assert(result.enabled and names(row.unit.ingredients) == "A:2,foreign:4,foreign-earlier:1")
          assert(row.prerequisites[1] == "existing" and row.prerequisites[2] == "promethium-science-pack")

          local missing = technology({{"A",2}})
          raw.technology["promethium-science-pack"] = nil
          result = science.apply(missing, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-end-game-science-source:promethium-science-pack:missing-owner:promethium-science-pack")

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
          install_sources(raw, false)
          local env = {raw=raw, target={id="f210"},
            options={ ["mir-science-pack-ingredient-policy"]="space", ["ips-require-space-gate"]=false }}
          local row = technology({{"A",2}}, {"existing"})
          local result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled and names(row.unit.ingredients) == "A:2,space-science-pack:1")
          assert(table.concat(row.prerequisites, ",") == "existing,space-science-pack")

          raw.technology["space-science-pack"] = nil
          local missing = technology({{"A",2}}, {"existing"})
          result = science.apply(missing, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:missing-owner:space-science-pack")
          assert(names(missing.unit.ingredients) == "A:2" and missing.prerequisites[1] == "existing")

          raw.technology["rocket-silo"] = {}
          local legacy = technology({{"science-pack-1",2}})
          raw.tool["science-pack-1"] = {name="science-pack-1"}
          raw.tool["space-science-pack"] = {name="space-science-pack"}
          install_sources(raw, false, "f016")
          result = science.apply(legacy, {}, science.prepare({raw=raw, target={id="f016"},
            options={ ["mir-science-pack-ingredient-policy"]="space" }}))
          assert(result.enabled and table.concat(legacy.prerequisites, ",") == "rocket-silo")
        ''')

    def test_named_source_contracts_validate_base_space_age_and_required_or_gated_science(self):
        self.lua.execute(r'''
          local base = raw_with({"A","space-science-pack"}, {lab={"A","space-science-pack"}})
          install_sources(base, false)
          local env = {raw=base, target={id="f210"}, options={ ["mir-science-pack-ingredient-policy"]="space" }}
          local row = technology({{"A",2}})
          local result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled and names(row.unit.ingredients) == "A:2,space-science-pack:1")

          base.item.satellite.rocket_launch_products[1].type = "fluid"
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite")
          base.item.satellite.rocket_launch_products[1] = {type="item", name="space-science-pack", amount=1}
          base.item.satellite.rocket_launch_products[1].independent_probability = 0
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite")
          base.item.satellite.rocket_launch_products[1] = {type="item", name="space-science-pack", amount_min=1, amount_max=3}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled, "positive ranged product is a valid source")
          base.item.satellite.rocket_launch_products[1] = {type="item", name="space-science-pack", amount_min=0, amount_max=1}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled, "zero-to-positive range remains productive")
          base.item.satellite.rocket_launch_products[1] = {type="item", name="space-science-pack", amount_min=0, amount_max=0}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite")
          base.item.satellite.rocket_launch_products[1] = {type="item", name="space-science-pack", amount_min=3, amount_max=2}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite")
          base.item.satellite.rocket_launch_products[1] = "not-a-product"
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite")
          base.item.satellite.rocket_launch_products[1] = {type="item", name="space-science-pack", amount=1}
          base.technology["space-science-pack"].enabled = false
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:disabled-owner:space-science-pack")

          local age = raw_with({"A","space-science-pack","cryogenic-science-pack","promethium-science-pack"},
            {lab={"A","space-science-pack","cryogenic-science-pack","promethium-science-pack"}})
          install_sources(age, true)
          local age_env = {raw=age, target={id="f210"}, mods={ ["space-age"]="2.1.23"},
            options={ ["mir-science-pack-ingredient-policy"]="space" }}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(age_env))
          assert(result.enabled and names(row.unit.ingredients) == "A:2,space-science-pack:1")
          age.technology["space-science-pack"].research_trigger.entity = "wrong-collector"
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(age_env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:owner-trigger:space-science-pack")
          age.technology["space-science-pack"].research_trigger.entity = "asteroid-collector"

          age_env.options = { ["mir-science-pack-ingredient-policy"]="configured" }
          row = technology({{"A",2}})
          result = science.apply(row, {required_science={"cryogenic-science-pack"}}, science.prepare(age_env))
          assert(result.enabled and names(row.unit.ingredients) == "A:2,cryogenic-science-pack:1")
          age.recipe["cryogenic-science-pack"].results[1].amount = 0
          row = technology({{"A",2}})
          result = science.apply(row, {required_science={"cryogenic-science-pack"}}, science.prepare(age_env))
          assert(not result.enabled and result.reason == "invalid-required-science-source:cryogenic-science-pack:recipe-output:cryogenic-science-pack")
          age.recipe["cryogenic-science-pack"].results[1].amount = 1

          age_env.options = { ["ips-require-space-gate"]=true }
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(age_env))
          assert(result.enabled and row.prerequisites[1] == "promethium-science-pack")
          age.technology["promethium-science-pack"].effects = {}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(age_env))
          assert(not result.enabled and result.reason == "invalid-end-game-science-source:promethium-science-pack:missing-owner-unlock:promethium-science-pack")
        ''')

    def test_hash_verified_native_source_oracle_accepts_base_and_space_age_white_paths(self):
        oracle = json.loads(NATIVE_SOURCE_ORACLE.read_text(encoding="utf-8"))
        verify = self.lua.eval(r'''
          function(raw, target, mods, is_space_age)
            local selected = bindings.select(target, mods)
            local contract = selected.source_contracts["space-science-pack"]
            assert(type(contract) == "table")
            if is_space_age then
              assert(raw.recipe["space-science-pack"] ~= nil)
            else
              assert(raw.recipe["space-science-pack"] == nil,
                "Base white is acquired only through the satellite trigger")
            end
            assert(science.validate_source_contract(raw, contract, "space-science-pack"))
            raw.lab = {oracle = {inputs = {"automation-science-pack", "space-science-pack"}}}
            local row = {name="mir-source-oracle", enabled=true, prerequisites={},
              unit={ingredients={{"automation-science-pack", 2}}, count=1, time=60}}
            local result = science.apply(row, {}, science.prepare({raw=raw, target=target, mods=mods,
              options={ ["mir-science-pack-ingredient-policy"]="space" }}))
            assert(result.enabled and #row.unit.ingredients == 2 and row.unit.ingredients[2][1] == "space-science-pack")
          end
        ''')
        profiles = oracle["profiles"]
        verify(self.lua_value(profiles["base-f210"]["raw"]), self.lua_value({"id": "f210"}),
               self.lua_value({}), False)
        verify(self.lua_value(profiles["space-age-f210"]["raw"]), self.lua_value({"id": "f210"}),
               self.lua_value({"space-age": "2.1.23"}), True)

    def test_explicit_trigger_recipe_remains_a_strict_optional_contract(self):
        self.lua.execute(r'''
          local raw = raw_with({"space-science-pack"}, {})
          raw.item.satellite = {name="satellite", rocket_launch_products={
            {type="item", name="space-science-pack", amount=1000}}}
          raw.technology["space-science-pack"] = {effects={},
            research_trigger={type="send-item-to-orbit", item="satellite"}}
          raw.recipe["bound-space-recipe"] = {enabled=false,
            results={{type="item", name="space-science-pack", amount=1}}}
          local contract = {kind="trigger-output", pack="space-science-pack", recipe="bound-space-recipe",
            owner="space-science-pack", payload="satellite",
            owner_trigger={type="send-item-to-orbit", item="satellite"}}
          assert(science.validate_source_contract(raw, contract))
          raw.recipe["bound-space-recipe"].enabled = true
          local valid, reason = science.validate_source_contract(raw, contract)
          assert(not valid and reason == "trigger-recipe-enabled:bound-space-recipe")
          raw.recipe["bound-space-recipe"].enabled = false
          raw.recipe["bound-space-recipe"].results[1].amount = 0
          assert(not science.validate_source_contract(raw, contract))
        ''')

    def test_legacy_rocket_source_contracts_keep_f015_and_f016_distinct(self):
        self.lua.execute(r'''
          local f015 = bindings.select({id="f015"}, {})
          local f016 = bindings.select({id="f016"}, {})
          assert(f015.source_contracts["space-science-pack"].kind == "legacy-rocket-result")
          assert(f016.source_contracts["space-science-pack"].kind == "legacy-rocket-product")

          local old = raw_with({"A","space-science-pack"}, {lab={"A","space-science-pack"}})
          install_sources(old, false, "f015")
          local env = {raw=old, target={id="f015"}, options={ ["mir-science-pack-ingredient-policy"]="space" }}
          local row = technology({{"A",2}})
          local result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled)
          old["rocket-silo-rocket"]["rocket-silo-rocket"].result_items[1][2] = 0
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:rocket-result:rocket-silo-rocket")

          local middle = raw_with({"A","space-science-pack"}, {lab={"A","space-science-pack"}})
          install_sources(middle, false, "f016")
          env = {raw=middle, target={id="f016"}, options={ ["mir-science-pack-ingredient-policy"]="space" }}
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(result.enabled)
          middle.item.satellite.rocket_launch_product[2] = 0
          row = technology({{"A",2}})
          result = science.apply(row, {}, science.prepare(env))
          assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite")
        ''')

    def test_initial_and_difficulty_recipe_forms_preserve_engine_enabled_semantics(self):
        self.lua.execute(r'''
          local raw = raw_with({}, {})
          local initial = {kind="initial-recipe", pack="science-pack-1", recipe="science-pack-1"}
          -- F013/F014/F015 red and green rows omit `enabled`; the engine
          -- default makes those recipes initial.
          raw.recipe["science-pack-1"] = {name="science-pack-1", result="science-pack-1"}
          assert(science.validate_source_contract(raw, initial))
          raw.recipe["science-pack-1"].enabled = false
          local valid, reason = science.validate_source_contract(raw, initial)
          assert(not valid and reason == "recipe-not-initial:science-pack-1")

          raw.recipe["science-pack-1"] = {name="science-pack-1",
            normal={result="science-pack-1"}, expensive={result="science-pack-1"}}
          assert(science.validate_source_contract(raw, initial), "both difficulty forms retain omitted enabled=true")
          raw.recipe["science-pack-1"].expensive.enabled = false
          valid, reason = science.validate_source_contract(raw, initial)
          assert(not valid and reason == "recipe-not-initial:science-pack-1")

          raw.recipe["science-pack-3"] = {name="science-pack-3",
            normal={result="science-pack-3"}, expensive={result="science-pack-3"}}
          raw.technology["advanced-electronics"] = {
            effects={{type="unlock-recipe", recipe="science-pack-3"}}, unit={ingredients={{"science-pack-1",1}}}}
          local unlocked = {kind="recipe-unlock", pack="science-pack-3", recipe="science-pack-3",
            owner="advanced-electronics"}
          assert(science.validate_source_contract(raw, unlocked), "normal/expensive unlock remains valid")
          raw.recipe["science-pack-3"].normal.result = "wrong-pack"
          assert(not science.validate_source_contract(raw, unlocked))
        ''')

    def test_f017_through_f110_keep_satellite_launch_sources_without_a_research_trigger(self):
        self.lua.execute(r'''
          for _, id in ipairs({"f017", "f100", "f110"}) do
            local selected = bindings.select({id=id}, {})
            assert(selected.source_contracts["space-science-pack"].kind == "satellite-launch-product")
            local raw = raw_with({"A", "space-science-pack"}, {lab={"A", "space-science-pack"}})
            install_sources(raw, false, id)
            local row = technology({{"A", 2}})
            local result = science.apply(row, {}, science.prepare({raw=raw, target={id=id},
              options={ ["mir-science-pack-ingredient-policy"]="space" }}))
            assert(result.enabled and names(row.unit.ingredients) == "A:2,space-science-pack:1", id)
            raw.item.satellite.rocket_launch_product[2] = 0
            row = technology({{"A", 2}})
            result = science.apply(row, {}, science.prepare({raw=raw, target={id=id},
              options={ ["mir-science-pack-ingredient-policy"]="space" }}))
            assert(not result.enabled and result.reason == "invalid-science-source:space-science-pack:payload-output:satellite", id)
          end
        ''')

    def test_finite_alternatives_and_declared_resources_do_not_search_or_seed_cycles(self):
        self.lua.execute(r'''
          local raw = raw_with({}, {})
          raw.recipe = {
            preferred = {name="preferred", enabled=false, results={{type="item", name="bound-pack", amount=1}}},
            alternate = {name="alternate", enabled=false, results={{type="item", name="bound-pack", amount=1}}}
          }
          raw.technology = {
            preferred_owner = {effects={{type="unlock-recipe", recipe="preferred"}}, unit={ingredients={{"other-pack",1}}}},
            alternate_owner = {effects={{type="unlock-recipe", recipe="alternate"}}, unit={ingredients={{"other-pack",1}}}}
          }
          local contract = {kind="alternatives", pack="bound-pack", alternatives={
            {kind="recipe-unlock", pack="bound-pack", recipe="missing", owner="missing"},
            {kind="recipe-unlock", pack="bound-pack", recipe="alternate", owner="alternate_owner"}
          }}
          assert(science.validate_source_contract(raw, contract))
          raw.recipe.unrelated = {name="unrelated", enabled=true, results={{type="item", name="bound-pack", amount=1}}}
          assert(science.validate_source_contract(raw, contract), "unlisted alternative changed selected finite route")
          raw.technology.alternate_owner.unit.ingredients = {{"bound-pack",1}}
          local valid, reason = science.validate_source_contract(raw, contract)
          assert(not valid and reason:find("self%-supporting%-owner", 1) ~= nil)

          local wrong_pack = {kind="recipe-unlock", pack="other-pack", recipe="alternate", owner="alternate_owner"}
          valid, reason = science.validate_source_contract(raw, wrong_pack, "bound-pack")
          assert(not valid and reason == "contract-pack-mismatch:other-pack")
          local wrong_alternative = {kind="alternatives", pack="bound-pack", alternatives={wrong_pack}}
          valid, reason = science.validate_source_contract(raw, wrong_alternative, "bound-pack")
          assert(not valid and reason == "contract-pack-mismatch:other-pack")
          local cycle = {kind="alternatives", pack="bound-pack", alternatives={}}
          cycle.alternatives[1] = cycle
          valid, reason = science.validate_source_contract(raw, cycle, "bound-pack")
          assert(not valid and reason == "cyclic-alternative")
          local nested={kind='alternatives',pack='bound-pack',alternatives={
            {kind='initial-recipe',pack='bound-pack',recipe='unrelated'},
            {kind='alternatives',pack='bound-pack',alternatives={}}
          }}
          local guarded={recipe=setmetatable({}, {__index=function() error('source read before flat preflight') end})}
          valid,reason=science.validate_source_contract(guarded,nested,'bound-pack')
          assert(not valid and reason=='nested-alternative')

          raw.resource = { ["dmrsa-tenemut"] = {name="dmrsa-tenemut", autoplace={},
            minable={results={{type="item", name="dmrsa-tenemut", amount=1}}}}}
          local resource = {kind="resource", pack="dmrsa-tenemut", resource="dmrsa-tenemut"}
          assert(science.validate_source_contract(raw, resource))
          raw.resource["dmrsa-tenemut"].minable.results[1].type = "fluid"
          assert(not science.validate_source_contract(raw, resource))
          raw.resource["dmrsa-tenemut"].minable.results[1] = {type="item", name="dmrsa-tenemut", amount=1}
          raw.resource["dmrsa-tenemut"].minable.required_fluid = "sulfuric-acid"
          assert(not science.validate_source_contract(raw, resource))
        ''')

    def test_exact_k2so_phase_binding_normalizes_selected_policy_and_preserves_a_phase_trigger(self):
        self.lua.execute(r'''
          local packs = {"kr-basic-tech-card","automation-science-pack","production-science-pack",
            "space-science-pack","kr-advanced-tech-card"}
          local raw = raw_with(packs, {whole=packs, late={"production-science-pack","space-science-pack"}})
          install_sources(raw, true)
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
          local all_context = science.prepare(env)
          result = science.apply(row, {}, all_context)
          assert(result.enabled and names(row.unit.ingredients):find("kr-basic-tech-card", 1, true) == nil)
          assert(names(row.unit.ingredients):find("production-science-pack:4", 1, true) ~= nil)
          assert(names(row.unit.ingredients):find("kr-advanced-tech-card:1", 1, true) == nil)
          assert(result.reason == "all-unbound-sources" and all_context.unbound_science_sources["kr-advanced-tech-card"] == "all")

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


    def test_472_foreign_native_science_unit_preserves_named_cryo_gate_and_quantities(self):
        self.lua.execute(r'''
          local packs={'A','automation-science-pack','logistic-science-pack','chemical-science-pack',
            'production-science-pack','military-science-pack','utility-science-pack','space-science-pack',
            'agricultural-science-pack','metallurgic-science-pack','electromagnetic-science-pack',
            'cryogenic-science-pack','promethium-science-pack','mir472-native-science'}
          local raw=raw_with(packs,{lab=packs})
          install_sources(raw,true)
          local owner=raw.technology['cryogenic-science-pack']
          owner.research_trigger=nil
          owner.unit={count=1,time=1,ingredients={{'mir472-native-science',1}}}
          raw.resource={['mir472-native-science-resource']={minable={result='mir472-native-science'}}}
          raw.recipe['late-cryo']={enabled=false,ingredients={{'cryogenic-science-pack',1}},
            results={{type='item',name='cryogenic-science-pack',amount=1}}}
          raw.technology['late-cyclic-owner']={prerequisites={'late-cyclic-owner'},
            effects={{type='unlock-recipe',recipe='late-cryo'}}}
          setmetatable(raw.technology,{__pairs=function() error('must not scan foreign research graphs') end})
          setmetatable(raw.recipe,{__pairs=function() error('must not scan optional science producers') end})
          local context=science.prepare({raw=raw,target={id='f210'},mods={['space-age']='2.1.23'},
            options={['mir-science-pack-ingredient-policy']='all-official'}})
          local row=technology({{'A',2},{'cryogenic-science-pack',3}}, {'cryogenic-science-pack'})
          local result=science.apply(row,{required_science={'cryogenic-science-pack'}},context)
          assert(result.enabled, result.reason)
          local cryo,gate=false,false
          for _,ingredient in ipairs(row.unit.ingredients) do
            if ingredient[1]=='cryogenic-science-pack' then assert(ingredient[2]==3);cryo=true end
          end
          for _,name in ipairs(row.prerequisites) do if name=='cryogenic-science-pack' then gate=true end end
          assert(cryo and gate and owner.research_trigger==nil)
          local added=technology({{'A',2}})
          assert(science.apply(added,{},context).enabled)
          local added_pack,added_gate=false,false
          for _,ingredient in ipairs(added.unit.ingredients) do
            if ingredient[1]=='cryogenic-science-pack' then assert(ingredient[2]==1);added_pack=true end
          end
          for _,name in ipairs(added.prerequisites) do if name=='cryogenic-science-pack' then added_gate=true end end
          assert(added_pack and added_gate)
          assert(owner.unit.ingredients[1][1]=='mir472-native-science' and owner.unit.ingredients[1][2]==1)
          assert(raw.technology['late-cyclic-owner'].prerequisites[1]=='late-cyclic-owner')
        ''')

    def test_cryo_unit_alternative_remains_narrow_and_rejects_invalid_native_units(self):
        self.lua.execute(r'''
          local raw=raw_with({'cryogenic-science-pack','foreign-native-pack'}, {})
          install_sources(raw,true)
          local contract=bindings.select({id='f210'},{['space-age']='2.1.23'}).source_contracts['cryogenic-science-pack']
          local function owner()
            local row={prerequisites={'cryogenic-plant'},
              effects={{type='unlock-recipe',recipe='cryogenic-science-pack'}},
              unit={count=1,time=1,ingredients={{'foreign-native-pack',1}}}}
            raw.technology['cryogenic-science-pack']=row
            return row
          end
          assert(science.validate_source_contract(raw,contract))
          for _,mutate in ipairs({
            function(o) o.enabled=false end,
            function(o) o.effects={} end,
            function(o) o.prerequisites={} end,
            function(o) o.research_trigger={type='craft-item',item='wrong'} end,
            function(o) o.unit.count=0 end,
            function(o) o.unit.time=0 end,
            function(o) o.unit.count=0/0 end,
            function(o) o.unit.ingredients={} end,
            function(o) o.unit.ingredients[1][2]=0 end,
            function(o) o.unit.ingredients[1].type='fluid' end,
            function(o) o.unit.ingredients[1][1]='missing-native-pack' end,
            function(o) o.unit.ingredients[2]={'foreign-native-pack',1} end,
            function(o) o.unit.ingredients={{'cryogenic-science-pack',1}} end,
            function(o) o.unit.count_formula='100' end,
            function(o) o.unit.count=nil;o.unit.count_formula='   ' end,
          }) do
            local row=owner();mutate(row)
            assert(not science.validate_source_contract(raw,contract))
          end
          local row=owner()
          row.unit.count=nil;row.unit.count_formula='100*2^L'
          assert(science.validate_source_contract(raw,contract))
          contract.pack='foreign-native-pack'
          assert(not science.validate_source_contract(raw,contract,'foreign-native-pack'),
            'the cryogenic unit alternative must not admit another pack')
          contract.pack='cryogenic-science-pack'
          contract.owner_unit_alternative=false
          assert(not science.validate_source_contract(raw,contract))
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

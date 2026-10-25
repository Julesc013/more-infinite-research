"""Pure Lua controls for the bounded MIR science and laboratory policy."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"
NATIVE_SOURCE_ORACLE = ROOT / "tests/fixtures/science-source-native-oracle.json"


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
        self.lua.globals().fresh_science_fixture = (
            ROOT / "tests/fixtures/fresh-science-sources").as_posix()
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
            local initial_red = target == "f017" or target == "f100" or target == "f110"
            for _, pack in ipairs(base) do
              if pack == "automation-science-pack" and initial_red then
                -- Installed Base 0.17/1.0/1.1 has an initially enabled
                -- shorthand-result red recipe and no red technology.
                source_recipe(raw, pack, nil)
              else
                source_recipe(raw, pack, false); source_owner(raw, pack, pack)
              end
            end
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
              local promethium_prerequisites = target == "f200"
                and {"biter-egg-handling", "fusion-reactor"}
                or {"biter-egg-handling", "stellar-discovery-solar-system-edge"}
              source_owner(raw, "promethium-science-pack", "promethium-science-pack", nil,
                promethium_prerequisites)
              raw.technology["biter-egg-handling"] = {}
              raw.technology[promethium_prerequisites[2]] = {}
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
          assert(f017.source_contracts["automation-science-pack"].kind == "initial-recipe")
          assert(f017.pack_prerequisites["automation-science-pack"] == nil)
          assert(same(f017.pack_prerequisites["space-science-pack"], {"space-science-pack"}))
          local f100 = bindings.select({id="f100"}, {})
          assert(f100.source_contracts["automation-science-pack"].kind == "initial-recipe")
          assert(f100.pack_prerequisites["automation-science-pack"] == nil)
          assert(f100.pack_prerequisites["logistic-science-pack"] == nil)
          assert(same(f100.pack_prerequisites["space-science-pack"], {"space-science-pack"}))
          local f110 = bindings.select({id="f110"}, {})
          assert(f110.source_contracts["automation-science-pack"].kind == "initial-recipe")
          assert(f110.pack_prerequisites["automation-science-pack"] == nil)
          assert(same(f110.pack_prerequisites["space-science-pack"], {"space-science-pack"}))
          local space = bindings.select({id="f210"}, {["space-age"]="2.1.23"})
          assert(space.end_game.pack == "promethium-science-pack" and space.end_game.prerequisites[1] == "promethium-science-pack")
          assert(#space.official == 12 and space.progression["promethium-science-pack"][12] == "promethium-science-pack")

          local unknown = bindings.select({id="unreviewed-target"}, {})
          assert(#unknown.official == 0 and unknown.space == nil and unknown.end_game == nil)
        ''')

    def test_red_science_contracts_cover_every_target_and_seed_legacy_fresh_owner_units(self):
        self.lua.execute(r'''
          local initial = {
            f013="science-pack-1", f014="science-pack-1", f015="science-pack-1", f016="science-pack-1",
            f017="automation-science-pack", f100="automation-science-pack", f110="automation-science-pack"
          }
          for id, pack in pairs(initial) do
            local selected = bindings.select({id=id}, {})
            local contract = selected.source_contracts[pack]
            assert(contract.kind == "initial-recipe" and contract.recipe == pack, id .. " red source")
            assert(selected.pack_prerequisites[pack] == nil, id .. " red prerequisite")
          end
          for _, id in ipairs({"f200", "f210"}) do
            local selected = bindings.select({id=id}, {})
            local contract = selected.source_contracts["automation-science-pack"]
            assert(contract.kind == "recipe-unlock" and contract.owner == "automation-science-pack", id .. " native red owner")
            assert(same(selected.pack_prerequisites["automation-science-pack"], {"automation-science-pack"}),
              id .. " native red prerequisite")
          end

          local function has(values, wanted)
            for _, value in ipairs(values or {}) do if value == wanted then return true end end
            return false
          end
          local function amount(rows, wanted)
            for _, row in ipairs(rows or {}) do if row[1] == wanted then return row[2] end end
            return nil
          end
          for _, id in ipairs({"f017", "f100", "f110"}) do
            local selected = bindings.select({id=id}, {})
            local fresh, owner = "fresh-unit-seed", "fresh-unit-seed-owner"
            local packs, inputs = {fresh}, {fresh}
            for _, name in ipairs(selected.official) do
              packs[#packs + 1], inputs[#inputs + 1] = name, name
            end
            local raw = raw_with(packs, {all=inputs})
            install_sources(raw, false, id)
            assert(raw.technology["automation-science-pack"] == nil, id .. " created a nonexistent red owner")
            raw.recipe[fresh] = {enabled=false, results={{type="item", name=fresh, amount=1}}}
            raw.technology[owner] = {prerequisites={}, effects={{type="unlock-recipe", recipe=fresh}},
              unit={count=1, time=1, ingredients={{"automation-science-pack", 1}}}}
            local row = technology({{"chemical-science-pack", 9}}, {})
            local result = science.apply(row, {}, science.prepare({raw=raw, target={id=id},
              options={ ["mir-science-pack-ingredient-policy"]="all" }}))
            assert(result.enabled and result.reason == "all", id .. " disabled an authored non-red row")
            assert(amount(row.unit.ingredients, "automation-science-pack") == 1, id .. " omitted initial red")
            assert(amount(row.unit.ingredients, fresh) == 1, id .. " rejected fresh unit seed")
            assert(has(row.prerequisites, owner), id .. " omitted fresh owner")
            assert(not has(row.prerequisites, "automation-science-pack"), id .. " added nonexistent red gate")
          end
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

    def test_sif_retires_space_from_only_the_two_level_seven_continuations_under_every_policy(self):
        self.lua.execute(r'''
          local policies = {
            "configured", "space", "space-and-promethium", "space-age-progression",
            "official-progression", "mod-progression", "all-official", "all"
          }
          local packs = {
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"
          }
          local rows = {
            {
              id="research-speed-7", family="research-speed",
              ingredients={{"automation-science-pack",2},{"logistic-science-pack",3},{"chemical-science-pack",5},
                {"production-science-pack",7},{"utility-science-pack",11},{"military-science-pack",13}},
              prerequisites={"research-speed-5","utility-science-pack","research-speed-6"},
              expected={
                configured="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13",
                space="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13",
                ["space-and-promethium"]="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13,promethium-science-pack:1",
                ["space-age-progression"]="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13",
                ["official-progression"]="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13",
                ["mod-progression"]="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13",
                ["all-official"]="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1",
                all="automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1"
              }
            },
            {
              id="weapon-shooting-speed-7", family="weapon-shooting-speed",
              ingredients={{"automation-science-pack",17},{"logistic-science-pack",19},{"chemical-science-pack",23},
                {"military-science-pack",29},{"utility-science-pack",31}},
              prerequisites={"weapon-shooting-speed-5","utility-science-pack","weapon-shooting-speed-6"},
              expected={
                configured="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31",
                space="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31",
                ["space-and-promethium"]="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31,promethium-science-pack:1",
                ["space-age-progression"]="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31",
                ["official-progression"]="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31,production-science-pack:1",
                ["mod-progression"]="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31",
                ["all-official"]="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31,production-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1",
                all="automation-science-pack:17,logistic-science-pack:19,chemical-science-pack:23,military-science-pack:29,utility-science-pack:31,production-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1"
              }
            }
          }
          local function has_name(values, wanted)
            for _, value in ipairs(values or {}) do if value == wanted then return true end end
            return false
          end
          local function sif_promethium_prerequisites(target)
            if target == "f200" then
              return {"agricultural-science-pack", "metallurgic-science-pack",
                "electromagnetic-science-pack", "quantum-processor", "fusion-reactor"}
            end
            return {"agricultural-science-pack", "metallurgic-science-pack",
              "electromagnetic-science-pack", "quantum-processor"}
          end
          local function sif_raw(target)
            target = target or "f210"
            local raw = raw_with(packs, {whole=packs})
            install_sources(raw, true, target)
            -- Exact archived SIF behavior replaces the selected source
            -- technology's space-platform prerequisite. If policy expansion
            -- reaches that retired source, source validation must not disable
            -- either continuation before its own science exclusion applies.
            raw.technology["space-science-pack"].prerequisites = {
              "utility-science-pack", "production-science-pack"
            }
            raw.technology["promethium-science-pack"].prerequisites = sif_promethium_prerequisites(target)
            raw.technology["quantum-processor"] = {}
            return raw
          end

          -- This is the pre-fix diagnostic: without the named binding, the
          -- archived prerequisite rewrite makes the policy-added space source
          -- invalid before a continuation can be published.
          local unbound = technology(rows[1].ingredients, rows[1].prerequisites)
          unbound.name, unbound.family = rows[1].id, rows[1].family
          local unbound_report = science.apply_family({unbound}, {[1]={}}, {raw=sif_raw(), target={id="f210"},
            mods={["space-age"]="2.1.23", ["space-is-fake"]="observed"},
            options={["mir-science-pack-ingredient-policy"]="space"}})[1]
          assert(not unbound_report.enabled and unbound_report.reason:match(
            "^invalid%-science%-source:space%-science%-pack:"))

          for _, target in ipairs({"f200", "f210"}) do
            for _, definition in ipairs(rows) do
              for _, policy in ipairs(policies) do
                local row = technology(definition.ingredients, definition.prerequisites)
                row.name, row.family = definition.id, definition.family
                local context = science.prepare({raw=sif_raw(target), target={id=target},
                  mods={["space-age"]="2.1.23", ["space-is-fake"]="observed"},
                  options={["mir-science-pack-ingredient-policy"]=policy}})
                local report = science.apply_family({row}, nil, context)[1]
                assert(report.enabled, target .. ":" .. definition.id .. ":" .. policy .. ":" .. tostring(report.reason))
                assert(names(row.unit.ingredients) == definition.expected[policy],
                  target .. ":" .. definition.id .. ":" .. policy .. " changed the named remaining vector")
                assert(not names(row.unit.ingredients):find("space-science-pack", 1, true))
                assert(not has_name(row.prerequisites, "space-science-pack"))
                for _, prerequisite in ipairs(definition.prerequisites) do
                  assert(has_name(row.prerequisites, prerequisite), "lost finite anchor " .. prerequisite)
                end
              end
            end
          end

          -- The activation is strictly SIF-scoped. An ordinary Space Age
          -- selection retains the added space science and its named gate.
          for _, target in ipairs({"f200", "f210"}) do
            for _, definition in ipairs(rows) do
              local raw = raw_with(packs, {whole=packs})
              install_sources(raw, true, target)
              local row = technology(definition.ingredients, definition.prerequisites)
              row.name, row.family = definition.id, definition.family
              local report = science.apply_family({row}, nil, science.prepare({raw=raw, target={id=target},
                mods={["space-age"]="2.1.23"}, options={["mir-science-pack-ingredient-policy"]="space"}}))[1]
              assert(report.enabled and names(row.unit.ingredients):find("space-science-pack:1", 1, true))
              assert(has_name(row.prerequisites, "space-science-pack"))
            end
          end

          -- Explicit required science and the selected Space Age end-game
          -- gate remain hard requirements; only policy-selected retired space
          -- science is excluded for the two named rows.
          local raw = sif_raw()
          local required = technology({{"automation-science-pack",37}}, {"finite-anchor"})
          required.name, required.family = "unrelated-owned-row", "unrelated-owned-row"
          local report = science.apply(required, {required_science={"space-science-pack"}}, science.prepare({raw=raw,
            target={id="f210"}, mods={["space-age"]="2.1.23", ["space-is-fake"]="observed"},
            options={["mir-science-pack-ingredient-policy"]="configured"}}))
          assert(report.enabled and names(required.unit.ingredients) == "automation-science-pack:37,space-science-pack:1")

          -- Even on one of the two bound names, an explicit requirement is
          -- appended after the finite policy exclusion.  The exclusion cannot
          -- silently override a declared hard requirement.
          local named_required = technology(rows[1].ingredients, rows[1].prerequisites)
          named_required.name, named_required.family = rows[1].id, rows[1].family
          local named_binding = bindings.conditions_for(rows[1].family, rows[1].id,
            {["space-is-fake"]="observed"})
          named_binding.required_science = {"space-science-pack"}
          report = science.apply(named_required, named_binding, science.prepare({raw=sif_raw(), target={id="f210"},
            mods={["space-age"]="2.1.23", ["space-is-fake"]="observed"},
            options={["mir-science-pack-ingredient-policy"]="space"}}))
          assert(report.enabled and names(named_required.unit.ingredients) ==
            "automation-science-pack:2,logistic-science-pack:3,chemical-science-pack:5,production-science-pack:7,utility-science-pack:11,military-science-pack:13,space-science-pack:1")

          local gated = technology(rows[1].ingredients, rows[1].prerequisites)
          gated.name, gated.family = rows[1].id, rows[1].family
          report = science.apply_family({gated}, nil, {raw=sif_raw(), target={id="f210"},
            mods={["space-age"]="2.1.23", ["space-is-fake"]="observed"}, options={
              ["mir-science-pack-ingredient-policy"]="space", ["ips-require-space-gate"]=true}})[1]
          assert(report.enabled and not names(gated.unit.ingredients):find("space-science-pack", 1, true))
          assert(has_name(gated.prerequisites, "promethium-science-pack"))
        ''')

    def test_sif_promethium_contract_preserves_native_validation_and_accepts_only_the_captured_owner_shape(self):
        self.lua.execute(r'''
          local packs = {
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"
          }
          local function native_prerequisites(target)
            return target == "f200" and {"biter-egg-handling", "fusion-reactor"}
              or {"biter-egg-handling", "stellar-discovery-solar-system-edge"}
          end
          local function sif_prerequisites(target)
            return target == "f200" and {
              "agricultural-science-pack", "metallurgic-science-pack",
              "electromagnetic-science-pack", "quantum-processor", "fusion-reactor"
            } or {
              "agricultural-science-pack", "metallurgic-science-pack",
              "electromagnetic-science-pack", "quantum-processor"
            }
          end
          local function sif_owner_raw(target)
            local raw = raw_with(packs, {whole=packs})
            install_sources(raw, true, target)
            raw.technology["promethium-science-pack"].prerequisites = sif_prerequisites(target)
            raw.technology["quantum-processor"] = {}
            return raw
          end
          for _, target in ipairs({"f200", "f210"}) do
            local native_raw = raw_with(packs, {whole=packs})
            install_sources(native_raw, true, target)
            local native = bindings.select({id=target}, { ["space-age"]="observed" })
            local native_contract = native.source_contracts["promethium-science-pack"]
            assert(same(native_contract.owner_prerequisites, native_prerequisites(target)))
            assert(science.validate_source_contract(native_raw, native_contract, "promethium-science-pack"))

            local raw = sif_owner_raw(target)
            -- This is the f522 rejection: the native contract cannot accept
            -- the actual archived SIF owner facts.
            local valid, reason = science.validate_source_contract(raw, native_contract, "promethium-science-pack")
            assert(not valid and reason == "owner-prerequisites:promethium-science-pack")

            local mods = { ["space-age"]="observed", ["space-is-fake"]="observed" }
            local selected = bindings.select({id=target}, mods)
            local contract = selected.source_contracts["promethium-science-pack"]
            assert(contract.kind == "recipe-unlock" and contract.owner == "promethium-science-pack"
              and contract.recipe == "promethium-science-pack")
            assert(same(contract.owner_prerequisites, sif_prerequisites(target)))
            assert(science.validate_source_contract(raw, contract, "promethium-science-pack"))

            local row = technology({{"automation-science-pack", 17}}, {"finite-anchor"})
            row.name = "weapon-shooting-speed-7"
            local report = science.apply_family({row}, nil, {raw=raw, target={id=target}, mods=mods,
              options={ ["mir-science-pack-ingredient-policy"]="space-and-promethium" }})[1]
            assert(report.enabled and names(row.unit.ingredients) ==
              "automation-science-pack:17,promethium-science-pack:1")
            assert(row.prerequisites[1] == "finite-anchor" and row.prerequisites[2] == "promethium-science-pack")

            raw.technology["promethium-science-pack"].effects = {}
            local no_unlock = technology({{"automation-science-pack", 17}}, {"finite-anchor"})
            no_unlock.name = "weapon-shooting-speed-7"
            report = science.apply_family({no_unlock}, nil, {raw=raw, target={id=target}, mods=mods,
              options={ ["mir-science-pack-ingredient-policy"]="space-and-promethium" }})[1]
            assert(not report.enabled and report.reason ==
              "invalid-science-source:promethium-science-pack:missing-owner-unlock:promethium-science-pack")
            raw.technology["promethium-science-pack"].effects = {
              {type="unlock-recipe", recipe="promethium-science-pack"}
            }

            raw.technology["promethium-science-pack"].prerequisites[4] = "wrong-sif-owner-prerequisite"
            local blocked = technology({{"automation-science-pack", 17}}, {"finite-anchor"})
            blocked.name = "weapon-shooting-speed-7"
            report = science.apply_family({blocked}, nil, {raw=raw, target={id=target}, mods=mods,
              options={ ["mir-science-pack-ingredient-policy"]="space-and-promethium" }})[1]
            assert(not report.enabled and report.reason ==
              "invalid-science-source:promethium-science-pack:owner-prerequisites:promethium-science-pack")
            assert(names(blocked.unit.ingredients) == "automation-science-pack:17")

            contract.owner_prerequisites[1] = "caller-mutation"
            assert(bindings.select({id=target}, mods).source_contracts["promethium-science-pack"].owner_prerequisites[1]
              == "agricultural-science-pack")
          end
        ''')

    def test_sif_real_space_age_continuations_keep_the_full_vector_and_retire_only_the_named_gate(self):
        self.lua.execute(r'''
          local catalogue = require("compatibility.modern_catalogue")
          local modern = require("research.modern")
          local target = require("platform.target")
          local policies = {"configured", "space", "space-and-promethium", "space-age-progression",
            "official-progression", "mod-progression", "all-official", "all"}
          local packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "utility-science-pack", "military-science-pack", "space-science-pack",
            "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack",
            "cryogenic-science-pack", "promethium-science-pack"}
          -- Independent retained Space Age/SIF expectations, not a snapshot
          -- of the current builder's result. Only retired space is removed.
          local expected = {
            ["research-speed-7"] = {
              science = "automation-science-pack:1,logistic-science-pack:1,chemical-science-pack:1,production-science-pack:1,utility-science-pack:1,military-science-pack:1,agricultural-science-pack:1,metallurgic-science-pack:1,electromagnetic-science-pack:1,cryogenic-science-pack:1,promethium-science-pack:1",
              prerequisites = "research-speed-5,utility-science-pack,research-speed-6,automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,military-science-pack,agricultural-science-pack,metallurgic-science-pack,electromagnetic-science-pack,cryogenic-science-pack,promethium-science-pack"
            },
            ["weapon-shooting-speed-7"] = {
              science = "automation-science-pack:1,logistic-science-pack:1,chemical-science-pack:1,military-science-pack:1,utility-science-pack:1",
              prerequisites = "weapon-shooting-speed-5,utility-science-pack,weapon-shooting-speed-6,automation-science-pack,logistic-science-pack,chemical-science-pack,military-science-pack"
            }
          }
          local weapon_additions = {
            ["space-and-promethium"] = {"promethium-science-pack"},
            ["official-progression"] = {"production-science-pack"},
            ["all-official"] = {"production-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
              "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"},
            all = {"production-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
              "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"}
          }
          local function sif_promethium_prerequisites(id)
            if id == "f200" then
              return {"agricultural-science-pack", "metallurgic-science-pack",
                "electromagnetic-science-pack", "quantum-processor", "fusion-reactor"}
            end
            return {"agricultural-science-pack", "metallurgic-science-pack",
              "electromagnetic-science-pack", "quantum-processor"}
          end
          for _, id in ipairs({"f200", "f210"}) do
            target.id = id
            for _, policy in ipairs(policies) do
              local mods = {["space-age"]="observed", ["space-is-fake"]="observed"}
              local raw = raw_with(packs, {whole=packs})
              install_sources(raw, true, id)
              raw.technology["space-science-pack"].prerequisites = {
                "utility-science-pack", "production-science-pack"}
              raw.technology["promethium-science-pack"].prerequisites = sif_promethium_prerequisites(id)
              raw.technology["quantum-processor"] = {}
              local checked = 0
              for _, definition in ipairs(catalogue.continuations(mods)) do
                local wanted = expected[definition.id]
                if wanted then
                  local row = modern.continuation(definition, {streams={[definition.family]=definition.defaults}})
                  local authored = row.prerequisites
                  local before = table.concat(authored, ",")
                  assert(before:find("space-science-pack", 1, true), "missing real pre-policy gate")
                  local report = science.apply_family({row}, nil, {raw=raw, target={id=id}, mods=mods,
                    options={["mir-science-pack-ingredient-policy"]=policy}})[1]
                  assert(report.enabled, id .. ":" .. policy .. ":" .. definition.id .. ":" .. tostring(report.reason))
                  local wanted_science, wanted_prerequisites = wanted.science, wanted.prerequisites
                  if definition.id == "weapon-shooting-speed-7" then
                    for _, pack in ipairs(weapon_additions[policy] or {}) do
                      wanted_science = wanted_science .. "," .. pack .. ":1"
                      wanted_prerequisites = wanted_prerequisites .. "," .. pack
                    end
                  end
                  assert(names(row.unit.ingredients) == wanted_science,
                    id .. ":" .. policy .. ":" .. definition.id .. " full Space Age science changed: " .. names(row.unit.ingredients))
                  assert(table.concat(row.prerequisites, ",") == wanted_prerequisites,
                    id .. ":" .. policy .. ":" .. definition.id .. " retained retired gate or lost an anchor")
                  assert(table.concat(authored, ",") == before, "mutated the original prerequisite array")
                  if policy == "configured" then
                    for _, opponent in ipairs({"no-sif", "adjacent-name"}) do
                      local unchanged = modern.continuation(definition, {streams={[definition.family]=definition.defaults}})
                      local opponent_mods = opponent == "no-sif" and {["space-age"]="observed"} or mods
                      if opponent == "adjacent-name" then unchanged.name = definition.id .. "-unbound" end
                      local ordinary_raw = raw_with(packs, {whole=packs})
                      install_sources(ordinary_raw, true, id)
                      local ordinary_report = science.apply_family({unchanged}, nil, {raw=ordinary_raw,
                        target={id=id}, mods=opponent_mods,
                        options={["mir-science-pack-ingredient-policy"]="configured"}})[1]
                      assert(ordinary_report.enabled and table.concat(unchanged.prerequisites, ",") == before,
                        "named SIF prerequisite exclusion escaped its activation boundary")
                    end
                  end
                  checked = checked + 1
                end
              end
              assert(checked == 2)
            end
          end
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
            local changed = {}
            for name, version in pairs(exact) do changed[name] = version end
            -- Exercise a concrete official patch as well as changed provider
            -- versions. A complete predecessor must not fall back to the
            -- ordinary vector and retain its basic card.
            changed[marker] = marker == "base" and "2.1.24" or "unreviewed-version"
            local ok, message = pcall(bindings.select, {id="f210"}, changed)
            assert(not ok and tostring(message):find("unsupported F210 K2SO science%-phase saved%-profile transition"),
              "changed K2SO tuple silently selected for " .. marker)
            row = technology({{"kr-basic-tech-card",3},{"production-science-pack",4}})
            local before = names(row.unit.ingredients)
            ok, message = pcall(function()
              return science.apply(row, {}, science.prepare({raw=raw, target={id="f210"}, mods=changed, options={}}))
            end)
            assert(not ok and tostring(message):find("unsupported F210 K2SO science%-phase saved%-profile transition"))
            assert(names(row.unit.ingredients) == before, "changed phase tuple mutated owned science")
          end
        ''')

    def test_prepared_context_reuses_lab_decisions_without_aliasing_current_rows(self):
        self.lua.execute(r'''
          local labs = {}
          for index = 1, 64 do
            local name = string.format("lab-%03d", index)
            if index <= 2 then labs[name] = {"A", "B"}
            elseif index % 3 == 0 then labs[name] = {"A"}
            elseif index % 3 == 1 then labs[name] = {"B"}
            else labs[name] = {"C"} end
          end
          local raw, options = raw_with({"A", "B", "C"}, labs), {}
          local context = science.prepare({raw=raw, target={id="f210"}, options=options})

          -- Seed a reduction before wrapping the collected lookup maps.  The
          -- two first labs tie; canonical lab order must retain A,B.
          local seed = technology({{"A",2},{"B",3},{"C",5}})
          local result = science.apply(seed, {}, context)
          assert(result.reason == "lab-reduced" and names(seed.unit.ingredients) == "A:2,B:3")
          assert(context.lab_visits == 64)

          -- `accepted` is private collector state.  Test-only metatables make
          -- every compatibility lookup visible, distinguishing it from merely
          -- reusing the raw-lab collector.
          local accesses = 0
          for _, lab in ipairs(context.collector.labs) do
            local accepted = lab.accepted
            lab.accepted = setmetatable({}, {__index=function(_, name)
              accesses = accesses + 1
              return accepted[name]
            end})
          end

          -- Same ordered names, different amounts: the cached selection has
          -- indices only, so all rows retain their own quantities and tables.
          for index = 1, 96 do
            local row = technology({{"A",index},{"B",index + 100},{"C",index + 200}})
            result = science.apply(row, {}, context)
            assert(result.reason == "lab-reduced")
            assert(names(row.unit.ingredients) == "A:" .. index .. ",B:" .. (index + 100))
            assert(row.unit.ingredients ~= seed.unit.ingredients)
          end
          assert(accesses == 0, "identical vectors repeated lab comparisons")

          seed.unit.ingredients[1][2] = 999
          local amounts = technology({{"A",17},{"B",19},{"C",23}})
          result = science.apply(amounts, {}, context)
          assert(result.reason == "lab-reduced" and names(amounts.unit.ingredients) == "A:17,B:19")
          assert(amounts.unit.ingredients ~= seed.unit.ingredients
            and amounts.unit.ingredients[1] ~= seed.unit.ingredients[1])
          assert(accesses == 0, "cached indices retained a prior output")

          -- Policy is part of the decision key. A strict pass must not reuse
          -- the reduction, while returning to reduce reuses its earlier result.
          accesses = 0
          options["mir-lab-incompatibility-policy"] = "skip"
          local skipped = technology({{"A",27},{"B",31},{"C",33}})
          result = science.apply(skipped, {}, context)
          assert(not result.enabled and result.reason == "lab-incompatible-skip")
          assert(accesses > 0, "skip reused a reduce decision")
          accesses = 0
          options["mir-lab-incompatibility-policy"] = "reduce"
          local reduced_again = technology({{"A",37},{"B",41},{"C",43}})
          result = science.apply(reduced_again, {}, context)
          assert(result.reason == "lab-reduced" and names(reduced_again.unit.ingredients) == "A:37,B:41")
          assert(accesses == 0, "reduce did not reuse its earlier decision")

          -- Full acceptance also retains only the decision. The second output
          -- is a new row with its own amount and table identity.
          accesses = 0
          local full_seed = technology({{"A",71}})
          result = science.apply(full_seed, {}, context)
          assert(result.reason == "configured" and accesses > 0)
          accesses = 0
          local full_again = technology({{"A",73}})
          result = science.apply(full_again, {}, context)
          assert(result.reason == "configured" and names(full_again.unit.ingredients) == "A:73")
          assert(full_again.unit.ingredients ~= full_seed.unit.ingredients and accesses == 0)

          -- Authored duplicate positions remain positions: an accepted A,B
          -- lab preserves both A entries in order and derives fresh amounts.
          accesses = 0
          local duplicate_seed = technology({{"A",79},{"B",83},{"A",89},{"C",97}})
          result = science.apply(duplicate_seed, {}, context)
          assert(result.reason == "lab-reduced" and names(duplicate_seed.unit.ingredients) == "A:79,B:83,A:89")
          assert(accesses > 0)
          accesses = 0
          local duplicate_again = technology({{"A",101},{"B",103},{"A",107},{"C",109}})
          result = science.apply(duplicate_again, {}, context)
          assert(result.reason == "lab-reduced" and names(duplicate_again.unit.ingredients) == "A:101,B:103,A:107")
          assert(duplicate_again.unit.ingredients ~= duplicate_seed.unit.ingredients and accesses == 0)

          -- Ordered names and each constraint sequence form the bounded cache
          -- key.  These new shapes must perform lab lookups, then retain the
          -- same canonical reduction and current amounts.
          accesses = 0
          local reordered = technology({{"B",31},{"A",29},{"C",37}})
          result = science.apply(reordered, {}, context)
          assert(result.reason == "lab-reduced" and names(reordered.unit.ingredients) == "B:31,A:29")
          assert(accesses > 0, "reordered science vector bypassed lab decision")

          accesses = 0
          local required = technology({{"A",41},{"B",43},{"C",47}})
          result = science.apply(required, {required_science={"A"}}, context)
          assert(result.reason == "lab-reduced" and names(required.unit.ingredients) == "A:41,B:43")
          assert(accesses > 0, "required-science constraint bypassed lab decision")

          accesses = 0
          local phased = technology({{"A",53},{"B",59},{"C",61}})
          result = science.apply(phased, {phase_any_science={"B"}}, context)
          assert(result.reason == "lab-reduced" and names(phased.unit.ingredients) == "A:53,B:59")
          assert(accesses > 0, "phase-science constraint bypassed lab decision")
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

    def test_family_all_policy_binds_the_published_fresh_trigger_seed_once_and_deterministically(self):
        self.lua.execute(r'''
          -- This is the published 4.7.3 planetary-data reproducer shape: the
          -- first recipe/owner is circular, while the later disabled recipe is
          -- independently seeded by a craft-item trigger.  The test calls the
          -- real family path with no injected compatibility binding.
          local selected = bindings.select({id="f200"}, {})
          local official, pack, foreign = selected.official, "planetary-data", "foreign-lab-card"
          local circular_recipe, seeded_recipe = "a-circular-planetary-data", "z-seeded-planetary-data"
          local circular_owner, seeded_owner = "circular-planetary-owner", "seeded-planetary-owner"

          local function count(values)
            local total = 0
            for _ in pairs(values) do total = total + 1 end
            return total
          end
          local function has(values, wanted)
            for _, value in ipairs(values or {}) do if value == wanted then return true end end
            return false
          end
          local function amount(rows, wanted)
            for _, row in ipairs(rows or {}) do
              if row[1] == wanted then return row[2] end
            end
            return nil
          end
          local function source_ingredients()
            local rows = {{foreign, 17}}
            for index, name in ipairs(official) do rows[#rows + 1] = {name, index + 2} end
            return rows
          end
          local function foreign_fingerprint(raw)
            local circular = raw.recipe[circular_recipe]
            local seeded = raw.recipe[seeded_recipe]
            local circular_technology = raw.technology[circular_owner]
            local seeded_technology = raw.technology[seeded_owner]
            return table.concat({
              raw.tool[pack].name,
              tostring(circular.enabled), circular.ingredients[1][1], tostring(circular.results[1].amount),
              tostring(seeded.enabled), seeded.ingredients[1][1], tostring(seeded.results[1].amount),
              circular_technology.unit.ingredients[1][1], tostring(#circular_technology.prerequisites),
              seeded_technology.research_trigger.type, seeded_technology.research_trigger.item,
              tostring(seeded_technology.research_trigger.count), tostring(#seeded_technology.prerequisites)
            }, "|")
          end
          local function make_raw(reversed, unrelated)
            local packs, inputs = {foreign, pack}, {foreign, pack}
            for _, name in ipairs(official) do packs[#packs + 1] = name; inputs[#inputs + 1] = name end
            local raw = raw_with(packs, {all = inputs})
            install_sources(raw, false, "f200")
            local automation_clone = {}
            for key, value in pairs(raw.tool["automation-science-pack"]) do automation_clone[key] = value end
            automation_clone.name = pack
            raw.tool[pack] = automation_clone
            raw.item["iron-plate"] = {name="iron-plate"}
            local function circular()
              raw.recipe[circular_recipe] = {enabled=false, ingredients={{"iron-plate", 1}},
                results={{type="item", name=pack, amount=1}}}
              raw.technology[circular_owner] = {unit={count=1, time=1, ingredients={{pack, 1}}},
                prerequisites={}, effects={{type="unlock-recipe", recipe=circular_recipe}}}
            end
            local function seeded()
              raw.recipe[seeded_recipe] = {enabled=false, ingredients={{"iron-plate", 1}},
                results={{type="item", name=pack, amount=1}}}
              raw.technology[seeded_owner] = {prerequisites={},
                research_trigger={type="craft-item", item="iron-plate", count=1},
                effects={{type="unlock-recipe", recipe=seeded_recipe}}}
            end
            if reversed then seeded(); circular() else circular(); seeded() end
            if unrelated then
              raw.recipe["middle-unrelated-recipe"] = {enabled=false, ingredients={{"iron-plate", 1}},
                results={{type="item", name="unrelated-output", amount=1}}}
            end
            return raw
          end
          local function owned(index)
            local row = technology(source_ingredients(), {})
            row.name = "recipe-prod-fresh-science-" .. index
            row.effects = {{type="change-recipe-productivity", recipe="iron-gear-wheel", change=0.25}}
            return row
          end
          local function run(reversed, unrelated)
            local raw = make_raw(reversed, unrelated)
            local before = foreign_fingerprint(raw)
            local rows = {}
            for index = 1, 37 do rows[index] = owned(index) end
            local reports, context = science.apply_family(rows, nil, {
              raw=raw, target={id="f200"}, options={ ["mir-science-pack-ingredient-policy"]="all" }
            })
            assert(not has(selected.official, pack), "a fresh input became an official science role")
            for _, row in ipairs(rows) do
              assert(amount(row.unit.ingredients, foreign) == 17, "existing foreign amount changed")
              for index, name in ipairs(official) do
                assert(amount(row.unit.ingredients, name) == index + 2, "official amount changed: " .. name)
              end
              assert(amount(row.unit.ingredients, pack) == 1, "fresh seed was not appended once")
              assert(same(row.prerequisites, {seeded_owner}), "only the independently seeded owner may gate fresh science")
              assert(row.effects[1].type == "change-recipe-productivity" and row.effects[1].change > 0,
                "owned positive effect changed")
            end
            assert(#reports == #rows and reports[1].enabled and reports[1].reason == "all")
            assert(foreign_fingerprint(raw) == before, "fresh binding mutated foreign raw prototypes")
            return {
              ingredients=names(rows[1].unit.ingredients), prerequisites=table.concat(rows[1].prerequisites, ","),
              recipe_visits=context.fresh_recipe_visits, technology_visits=context.fresh_technology_visits,
              expected_recipe_visits=count(raw.recipe), expected_technology_visits=count(raw.technology)
            }
          end

          local forward = run(false, false)
          local reversed = run(true, false)
          local unrelated = run(false, true)
          assert(forward.ingredients == reversed.ingredients and forward.prerequisites == reversed.prerequisites,
            "producer insertion order changed the fresh binding")
          assert(forward.ingredients == unrelated.ingredients and forward.prerequisites == unrelated.prerequisites,
            "an unrelated producer changed the fresh binding")
          for _, result in ipairs({forward, reversed, unrelated}) do
            assert(result.recipe_visits == result.expected_recipe_visits,
              "fresh recipes were not enumerated exactly once for the family")
            assert(result.technology_visits == result.expected_technology_visits,
              "fresh technologies were not enumerated exactly once for the family")
          end
        ''')

    def test_fresh_all_policy_rejects_unseeded_forms_and_skips_raw_enumeration_without_unknown_inputs(self):
        self.lua.execute(r'''
          local selected = bindings.select({id="f200"}, {})
          local official, pack, foreign = selected.official, "planetary-data", "foreign-lab-card"
          local circular_recipe, seeded_recipe = "a-circular-planetary-data", "z-seeded-planetary-data"
          local circular_owner, seeded_owner = "circular-planetary-owner", "seeded-planetary-owner"

          local function count(values)
            local total = 0
            for _ in pairs(values) do total = total + 1 end
            return total
          end
          local function amount(rows, wanted)
            for _, row in ipairs(rows or {}) do if row[1] == wanted then return row[2] end end
            return nil
          end
          local function source_ingredients()
            local rows = {{foreign, 17}}
            for index, name in ipairs(official) do rows[#rows + 1] = {name, index + 2} end
            return rows
          end
          local function owned(index, include_foreign)
            local rows = include_foreign and source_ingredients() or {}
            if not include_foreign then
              for item_index, name in ipairs(official) do rows[#rows + 1] = {name, item_index + 2} end
            end
            local row = technology(rows, {})
            row.name = "recipe-prod-fresh-variant-" .. index
            return row
          end
          local function signature(raw)
            local a, z = raw.recipe[circular_recipe], raw.recipe[seeded_recipe]
            local c, s = raw.technology[circular_owner], raw.technology[seeded_owner]
            local z_result = z and z.results and z.results[1]
            return table.concat({
              raw.tool[pack].name, tostring(a.enabled), tostring(a.results[1].type), tostring(a.results[1].amount),
              tostring(z and z.enabled), tostring(z_result and z_result.type), tostring(z_result and z_result.amount),
              tostring(z and z.result), tostring(z and z.result_type),
              tostring(c.unit.ingredients[1][1]), tostring(c.enabled), tostring(s and s.enabled),
              tostring(s and s.research_trigger and s.research_trigger.item),
              tostring(s and s.research_trigger and s.research_trigger.count),
              tostring(s and s.unit and s.unit.ingredients[1][1]), tostring(raw.item["iron-plate"] ~= nil)
            }, "|")
          end
          local function insert(raw, reversed, first, second)
            if reversed then second(); first() else first(); second() end
          end
          local function variant_raw(kind, reversed)
            local packs, inputs = {foreign, pack}, {foreign, pack}
            for _, name in ipairs(official) do packs[#packs + 1] = name; inputs[#inputs + 1] = name end
            local raw = raw_with(packs, {all=inputs})
            install_sources(raw, false, "f200")
            local automation_clone = {}
            for key, value in pairs(raw.tool["automation-science-pack"]) do automation_clone[key] = value end
            automation_clone.name = pack
            raw.tool[pack] = automation_clone
            raw.item["iron-plate"] = {name="iron-plate"}
            local function circular()
              raw.recipe[circular_recipe] = {enabled=false, ingredients={{"iron-plate", 1}},
                results={{type="item", name=pack, amount=1}}}
              raw.technology[circular_owner] = {prerequisites={}, unit={count=1, time=1, ingredients={{pack, 1}}},
                effects={{type="unlock-recipe", recipe=circular_recipe}}}
            end
            local function seeded_recipe_row()
              raw.recipe[seeded_recipe] = {enabled=kind == "initial", ingredients={{"iron-plate", 1}},
                results={{type="item", name=pack, amount=1}}}
              if kind == "zero" then raw.recipe[seeded_recipe].results[1].amount = 0 end
              if kind == "fluid" then raw.recipe[seeded_recipe].results[1].type = "fluid" end
              if kind == "shorthandfluid" then
                raw.recipe[seeded_recipe].enabled = true
                raw.recipe[seeded_recipe].results = nil
                raw.recipe[seeded_recipe].result = pack
                raw.recipe[seeded_recipe].result_type = "fluid"
              end
            end
            insert(raw, reversed, circular, seeded_recipe_row)
            if kind ~= "initial" and kind ~= "noowner" then
              raw.technology[seeded_owner] = {prerequisites={}, effects={{type="unlock-recipe", recipe=seeded_recipe}},
                research_trigger={type="craft-item", item="iron-plate", count=1}}
              if kind == "disabled" then raw.technology[seeded_owner].enabled = false end
              if kind == "circular" then
                raw.technology[seeded_owner].research_trigger = nil
                raw.technology[seeded_owner].unit = {count=1, time=1, ingredients={{pack, 1}}}
              end
              if kind == "research" then
                -- A finite owner unit is accepted only through this already
                -- declared craft-seeded automation source, which the shared
                -- lab can use.  Merely enabling its recipe is not a seed.
                raw.technology["automation-science-pack"].research_trigger = {
                  type="craft-item", item="iron-plate", count=1
                }
                raw.technology[seeded_owner].research_trigger = nil
                raw.technology[seeded_owner].unit = {count=1, time=1,
                  ingredients={{"automation-science-pack", 1}}}
              end
              if kind == "formula" then
                raw.technology["automation-science-pack"].research_trigger = {
                  type="craft-item", item="iron-plate", count=1
                }
                raw.technology[seeded_owner].research_trigger = nil
                raw.technology[seeded_owner].unit = {count_formula="2", time=1,
                  ingredients={{"automation-science-pack", 1}}}
              end
              if kind == "falsecount" then raw.technology[seeded_owner].research_trigger.count = false end
              if kind == "emptytriggeritem" then raw.technology[seeded_owner].research_trigger.item = "" end
              if kind == "missing" then raw.item["iron-plate"] = nil end
            end
            if kind == "numerickey" then
              local malformed = raw.recipe[seeded_recipe]
              raw.recipe[seeded_recipe] = nil
              malformed.name = seeded_recipe
              raw.recipe[17] = malformed
            end
            return raw
          end

          local expected = {
            initial={added=true, prerequisite=""},
            research={added=true, prerequisite=seeded_owner},
            noowner={added=false, prerequisite=""}, disabled={added=false, prerequisite=""},
            circular={added=false, prerequisite=""}, zero={added=false, prerequisite=""},
            fluid={added=false, prerequisite=""}, missing={added=false, prerequisite=""},
            formula={added=false, prerequisite=""}, falsecount={added=false, prerequisite=""},
            shorthandfluid={added=false, prerequisite=""}, emptytriggeritem={added=false, prerequisite=""},
            numerickey={added=false, prerequisite=""}
          }
          local variants = {"initial", "research", "noowner", "disabled", "circular", "zero", "fluid", "missing", "formula", "falsecount", "shorthandfluid", "emptytriggeritem", "numerickey"}
          for _, reversed in ipairs({false, true}) do
            for _, kind in ipairs(variants) do
              local want = expected[kind]
              local raw = variant_raw(kind, reversed)
              local before = signature(raw)
              local rows = {}
              for index = 1, 13 do rows[index] = owned(index, true) end
              local reports, context = science.apply_family(rows, nil, {
                raw=raw, target={id="f200"}, options={ ["mir-science-pack-ingredient-policy"]="all" }
              })
              for _, row in ipairs(rows) do
                assert(amount(row.unit.ingredients, foreign) == 17, "foreign input changed: " .. kind)
                assert((amount(row.unit.ingredients, pack) == 1) == want.added, "fresh variant changed: " .. kind)
                assert(table.concat(row.prerequisites, ",") == want.prerequisite,
                  "fresh owner prerequisites differ: " .. kind)
              end
              assert((reports[1].reason == "all") == want.added, "unbound variant was reported as bound: " .. kind)
              assert(signature(raw) == before, "variant mutated foreign raw: " .. kind)
              assert(context.fresh_recipe_visits == count(raw.recipe)
                and context.fresh_technology_visits == (kind == "initial" and 0 or count(raw.technology)),
                "fresh enumeration was not bounded to one pass: " .. kind)
            end
          end

          -- No all-policy fresh search is justified when every accepted lab
          -- input is already a target-approved official pack.
          for _, options in ipairs({{}, {["mir-science-pack-ingredient-policy"]="all-official"},
              {["mir-science-pack-ingredient-policy"]="all"}}) do
            local raw = raw_with(official, {all=official})
            install_sources(raw, false, "f200")
            local rows = {}
            for index = 1, 19 do rows[index] = owned(index, false) end
            local reports, context = science.apply_family(rows, nil, {raw=raw, target={id="f200"}, options=options})
            assert(#reports == #rows and reports[1].enabled)
            assert(context.fresh_recipe_visits == 0 and context.fresh_technology_visits == 0,
              "known-only policy enumerated foreign source tables")
          end

          -- A current owned row which already carries its unfamiliar input
          -- does not search.  If a later family row needs that same input,
          -- the fixed context scans once and then reuses its unbound result.
          local raw = raw_with({foreign}, {all={foreign}})
          for _, name in ipairs(official) do
            raw.tool[name] = {name=name}
            raw.lab.all.inputs[#raw.lab.all.inputs + 1] = name
            raw.recipe[name] = {enabled=false, results={{type="item", name=name, amount=1}}}
            raw.technology[name] = {effects={{type="unlock-recipe", recipe=name}}}
          end
          local carried = owned(1, true)
          local later, final = owned(2, false), owned(3, false)
          local reports, context = science.apply_family({carried, later, final}, nil, {
            raw=raw, target={id="f200"}, options={ ["mir-science-pack-ingredient-policy"]="all" }
          })
          assert(reports[1].reason == "all" and reports[2].reason == "all-unbound-sources"
            and reports[3].reason == "all-unbound-sources")
          assert(amount(carried.unit.ingredients, foreign) == 17 and amount(later.unit.ingredients, foreign) == nil)
          assert(context.fresh_recipe_visits == count(raw.recipe) and context.fresh_technology_visits == 0,
            "later missing unfamiliar input did not trigger one bounded recipe-only scan")
        ''')

    def test_fresh_science_native_selections_change_only_the_frozen_mir_arm(self):
        profiles = []
        expected_arms = (
            ("mir5", "5.0.21000", "C8E0C570213F41CA8C816A29D1556FD40A36896D31ED56B07856652B2DE7F32A"),
            ("published", "4.7.21003", "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"),
        )
        for arm, version, digest in expected_arms:
            profile = json.loads((ROOT / "tests/profiles" /
                f"fresh-science-sources-{arm}-f210-2123.json").read_bytes())
            self.assertEqual(profile["kind"], "mir5-fresh-science-sources-f210-native-selection")
            self.assertEqual((profile["target"], profile["factorio_line"], profile["settings_mode"]),
                ("f210", "2.1", "Defaults"))
            self.assertEqual(profile["engine"], {
                "version": "2.1.23",
                "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
            })
            self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]],
                [(name, "2.1.23", True) for name in
                    ("base", "elevated-rails", "quality", "recycler", "space-age")] + [
                    ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
                    ("more-infinite-research", version, True),
                    ("mir-fixture-mir5-fresh-science-sources", "0.1.0", True),
                ])
            self.assertEqual(profile["archive_sha256"], {
                "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                    "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
                f"more-infinite-research_{version}.zip": digest,
            })
            profiles.append(profile)
        # The independent oracles above pin both arms; this comparison also
        # detects a new unmatched setting/selection field in either arm.
        for profile in profiles:
            profile["mods"] = [row for row in profile["mods"] if row["name"] != "more-infinite-research"]
            profile["archive_sha256"] = {name: digest for name, digest in profile["archive_sha256"].items()
                if not name.startswith("more-infinite-research_")}
            profile.pop("scope")
        self.assertEqual(*profiles)

    def test_fresh_science_fixture_executes_its_actual_data_stage_predicate(self):
        fixture = ROOT / "tests/fixtures/fresh-science-sources"
        info = json.loads((fixture / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["factorio_version"], "2.1")
        self.assertEqual(info["dependencies"], [
            "base >= 2.1.23", "more-infinite-research >= 4.7.21003",
        ])
        self.lua.execute(r'''
          local PACK = "planetary-data"
          local CIRCULAR = "mir473-circular-planetary-owner"
          local SEEDED = "mir473-seeded-planetary-owner"
          local function fixture(name) return fresh_science_fixture .. "/" .. name end
          local function deep_copy(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local copy = {}
            seen[value] = copy
            for key, member in pairs(value) do copy[deep_copy(key, seen)] = deep_copy(member, seen) end
            return copy
          end
          local function staged()
            data = {raw={item={}, tool={
              ["automation-science-pack"]={type="tool", name="automation-science-pack", stack_size=200}
            }, lab={one={inputs={"automation-science-pack"}}, two={inputs={"automation-science-pack"}}},
              recipe={}, technology={}, ["string-setting"]={
                ["mir-science-pack-ingredient-policy"]={default_value="configured"}
              }}}
            function data:extend(rows)
              for _, row in ipairs(rows) do
                self.raw[row.type] = self.raw[row.type] or {}
                self.raw[row.type][row.name] = row
              end
            end
            table.deepcopy = deep_copy
            dofile(fixture("settings-updates.lua"))
            assert(data.raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value == "all")
            dofile(fixture("data-updates.lua"))
            assert(data.raw.tool[PACK] and data.raw.tool[PACK].stack_size == 200)
            for _, lab in pairs(data.raw.lab) do assert(lab.inputs[#lab.inputs] == PACK) end
            local row = {unit={ingredients={{type="item", name=PACK, amount=1}}},
              prerequisites={SEEDED}, effects={{type="change-recipe-productivity", recipe="iron-gear-wheel", change=0.2}}}
            data.raw.technology["recipe-prod-research_fixture-1"] = row
            -- Minimal companion for the producer-effect oracle; the row above
            -- remains the isolated retained-ingredient/positive-effect witness.
            data.raw.technology["recipe-prod-research_science_pack_productivity-1"] = {effects={
              {type="change-recipe-productivity",recipe="a-mir473-circular-planetary-data",change=0.1},
              {type="change-recipe-productivity",recipe="z-mir473-seeded-planetary-data",change=0.1}
            }}
            data.raw.technology["automation-science-pack"] = {prerequisites={}}
            return row
          end
          local function evaluate(mutate)
            local row = staged()
            if mutate then mutate(row) end
            return pcall(dofile, fixture("data-final-fixes.lua"))
          end
          local ok = evaluate()
          assert(ok, "actual fixture rejected the typed positive data-stage shape")
          assert(evaluate(function(row) row.prerequisites = {"automation-science-pack", SEEDED} end),
            "actual fixture rejected the retained authored official gate")
          assert(evaluate(function(row)
            data.raw.technology["recipe-prod-research_spoilage_preservation-1"] = {
              unit={ingredients={{PACK,1}}}, prerequisites={SEEDED},
              effects={{type="nothing",effect_description={"fixture-scripted-effect"}}}
            }
          end), "actual fixture confused a legitimate scripted effect with removed productivity")
          for _, mutate in ipairs({
            function(row) table.remove(data.raw.technology["recipe-prod-research_science_pack_productivity-1"].effects) end,
            function(row) data.raw.technology["recipe-prod-research_science_pack_productivity-1"].effects[1].change = 0.02 end,
            function(row)
              local effects=data.raw.technology["recipe-prod-research_science_pack_productivity-1"].effects
              effects[#effects+1]=deep_copy(effects[1])
            end,
            function(row) row.unit.ingredients[1].amount = 0 end,
            function(row) row.unit.ingredients[1].type = "fluid" end,
            function(row) row.prerequisites = {"automation-science-pack"} end,
            function(row) row.prerequisites = {CIRCULAR} end,
            function(row) row.effects = {{type="change-recipe-productivity", recipe="iron-gear-wheel", change=0}} end
          }) do
            local accepted = evaluate(mutate)
            assert(not accepted, "actual fixture accepted a zero/fluid/wrong-gate/opposing-effect shape")
          end
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

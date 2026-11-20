"""Selected modern native capabilities; no engine or historical pass claimed."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ModernTargetTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          package.preload["__more-infinite-research__/platform/target"] = function() return target end
          catalogue = require("compatibility.modern_catalogue")
          function f200()
            target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
            target.distribution_version, target.cargo_research = "5.0.20000", false
            target.recipe_probability, target.receiver_limits = "probability", false
            target.productivity_ignores_stats = true
          end
          function f210()
            target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
            target.distribution_version, target.cargo_research = "5.0.21018", true
            target.recipe_probability, target.receiver_limits = "independent_probability", true
            target.productivity_ignores_stats = true
          end
          function names(rows)
            local out = {}
            for _, row in ipairs(rows) do out[row.key] = row end
            return out
          end
          function effect_vector(definition)
            local out = {}
            for _, effect in ipairs(definition.effects or {}) do
              out[#out + 1] = effect.recipe .. ":" .. tostring(effect.scale or effect.change)
            end
            return table.concat(out, ",")
          end
          function recipe_map(recipes)
            local raw = {recipe = {}}
            for _, name in ipairs(recipes) do
              raw.recipe[name] = {type="recipe", name=name, ingredients={},
                results={{type="item", name=name, amount=1}}}
            end
            return raw
          end
          function recipe_shape(raw)
            local out = {}
            for name, recipe in pairs(raw.recipe or {}) do
              out[#out + 1] = name .. ":" .. tostring(recipe.allow_productivity)
                .. ":" .. tostring(recipe.results and recipe.results[1] and recipe.results[1].name)
            end
            table.sort(out)
            return table.concat(out, ",")
          end
        ''')

    def test_only_two_actual_cargo_modifiers_are_absent_in_f200(self):
        self.lua.execute('''
          local modern = catalogue.select({["space-age"]="2.1.23"})
          local existing = names(modern.definitions)
          assert(#modern.definitions == 62 and existing.research_cargo_landing_pad_count
            and existing.research_cargo_bay_unloading_distance)
          f200()
          local historical = catalogue.select({["space-age"]="2.0.77"})
          local selected = names(historical.definitions)
          assert(#historical.definitions == 60 and not selected.research_cargo_landing_pad_count
            and not selected.research_cargo_bay_unloading_distance)
          for key in pairs(existing) do
            if key ~= "research_cargo_landing_pad_count" and key ~= "research_cargo_bay_unloading_distance" then
              assert(selected[key], "unrelated family removed: " .. key)
            end
          end
          assert(#modern.definitions == 62 and existing.research_cargo_landing_pad_count)
          local molten = selected.research_molten_metals.effects
          assert(molten[1].recipe == "molten-copper-from-lava" and molten[1].scale == 1)
          assert(molten[2].recipe == "molten-iron-from-lava" and molten[2].scale == 1)
          assert(#molten == 2, "2.0 must retain the published lava-only effect scope")
          assert(existing.research_molten_metals.effects[3].recipe == "copper-ore-melting"
            and existing.research_molten_metals.effects[4].recipe == "iron-ore-melting")
          local base = catalogue.select({})
          assert(#base.definitions == 47 and names(base.definitions).research_science_pack_productivity)
          for _, row in ipairs(historical.definitions) do
            for _, effect in ipairs(row.effects) do
              assert(effect.type ~= "cargo-landing-pad-count" and effect.type ~= "max-cargo-bay-unloading-distance")
            end
          end
        ''')

    def test_base_literal_names_do_not_keep_absent_f210_item_children(self):
        locale_files = sorted((ROOT / "source" / "locale").glob("*/more-infinite-research.cfg"))
        self.assertEqual(len(locale_files), 50)
        for path in locale_files:
            values = {}
            for line in path.read_text(encoding="utf-8").splitlines():
                key, separator, value = line.partition("=")
                if separator:
                    values[key] = value
            for key in ("more-infinite-research.research_mining_drill",
                        "more-infinite-research.research_walls"):
                self.assertNotIn("__", values[key], f"literal title unexpectedly gained a placeholder: {path}")
        self.lua.execute('''
          local selected = names(catalogue.select({}).definitions)
          -- F210 Base locale supplies entity-name.electric-mining-drill and
          -- entity-name.stone-wall, but not their item-name variants.  Each
          -- restored MIR title is a literal in all shipped locales, so neither
          -- child is a valid substitution argument.
          assert(selected.research_mining_drill.localised_name[1]
            == "technology-name.more-infinite-research.research_mining_drill"
            and #selected.research_mining_drill.localised_name == 1)
          assert(selected.research_walls.localised_name[1]
            == "technology-name.more-infinite-research.research_walls"
            and #selected.research_walls.localised_name == 1)
          -- A real parameter remains independent evidence that this control
          -- has not flattened unrelated LocalisedStrings.
          assert(selected.research_advanced_circuit.localised_name[2][1] == "item-name.advanced-circuit")
        ''')

    def test_f200_keeps_875_settings_and_supported_nondefault_values(self):
        self.lua.execute('''
          f200()
          mods = {base="2.0.77", ["space-age"]="2.0.77"}
          local config = require("research.settings")
          local descriptors = config.prototypes()
          assert(#descriptors == 875)
          assert(config.spec("ips-enable-research_cargo_landing_pad_count") == nil)
          assert(config.spec("ips-effect-per-level-research_cargo_bay_unloading_distance") == nil)
          assert(config.spec("ips-enable-research_platform") ~= nil)
          local direct = config.spec("ips-cost-growth-research_gears")
          local inherited = config.spec("mir-cost-growth-inserter-capacity-bonus")
          assert(direct.minimum_value == 1 and direct.maximum_value == 1000)
          assert(inherited.minimum_value == 0 and inherited.maximum_value == 1000)
          local ok, message = pcall(config.resolve, { [direct.name] = {value=1001} })
          assert(not ok and string.find(message, "MIR invalid effective setting: " .. direct.name, 1, true))
          local values = config.resolve({["ips-effect-per-level-research_gears"]={value=17},
            ["mir-recycling-return-chance"]={value="percent-20"}, [direct.name]={value=1000},
            [inherited.name]={value=0}})
          assert(values.effect_percent == 17 and values.options["mir-recycling-return-chance"] == "percent-20")
          assert(values.streams.research_gears.growth_factor == 1000
            and values.native_continuations["inserter-capacity-bonus"].growth_factor == 0)
        ''')

    def test_f200_api_rejects_unadmitted_cargo_effects_before_publication(self):
        self.lua.execute('''
          f200()
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          local api = assert(loadfile(player_root .. "/api/v1/data.lua"))()
          local writes = 0
          data = {raw = {
            technology = {automation = {}},
            tool = {["automation-science-pack"] = {}},
            recipe = {["iron-gear-wheel"] = {}}
          }}
          function data.extend() writes = writes + 1 end
          for _, kind in ipairs({"cargo-landing-pad-count", "max-cargo-bay-unloading-distance"}) do
            local ok, message = pcall(api.add_technology, {type="technology", name="consumer",
              unit={count=1, ingredients={{"automation-science-pack", 1}}, time=1},
              effects={{type=kind, modifier=1}}})
            assert(not ok and tostring(message):find("MIR_API:invalid_definition",1,true), tostring(message))
            ok, message = pcall(api.add_productivity, {type="technology", name="consumer",
              unit={count=1, ingredients={{"automation-science-pack", 1}}, time=1},
              effects={{type=kind, modifier=1}}}, {"iron-gear-wheel"}, 0.1)
            assert(not ok and tostring(message):find("MIR_API:invalid_definition",1,true), tostring(message))
          end
          assert(writes == 0)
          assert(api.get_version().product == "5.0.20000" and api.get_capabilities().recipe_productivity)
        ''')

    def test_capability_check_keeps_typed_errors_for_malformed_effects(self):
        self.lua.execute('''
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          local api = assert(loadfile(player_root .. "/api/v1/data.lua"))()
          local writes = 0
          data = {raw = {
            technology = {automation = {}},
            tool = {["automation-science-pack"] = {}},
            recipe = {}
          }}
          function data.extend() writes = writes + 1 end
          for _, effects in ipairs({false, 5, "bad", {5}, {[2]={type="laboratory-speed",modifier=0.1}}}) do
            local ok, message = pcall(api.add_technology, {
              type="technology", name="consumer",
              unit={count=1, ingredients={{"automation-science-pack", 1}}, time=1},
              effects=effects
            })
            assert(not ok and tostring(message):find("MIR_API:invalid_definition",1,true), tostring(message))
          end
          assert(writes == 0)
        ''')

    def test_se_without_k2_restores_only_the_four_published_drill_manufacturing_effects(self):
        """F394 data contract: four named manufacturing recipes, never an ore-yield route."""
        self.lua.execute('''
          local expected = "burner-mining-drill:1,electric-mining-drill:0.5,area-mining-drill:0.25,se-core-miner-drill:0.25"
          local source_mods = {base="2.0.77", ["space-exploration"]="0.7.57"}
          local recipe_names = {"burner-mining-drill", "electric-mining-drill", "area-mining-drill", "se-core-miner-drill"}
          local function mining(selection)
            return assert(names(selection.definitions).research_mining_drill)
          end
          local function continuation_ids(selection)
            local out = {}
            for _, row in ipairs(selection.continuations) do out[#out + 1] = row.id end
            table.sort(out)
            return table.concat(out, ",")
          end

          f200()
          local base = catalogue.select({base="2.0.77"})
          local selected = catalogue.select(source_mods)
          assert(selected.profile == "space-exploration-f200")
          assert(effect_vector(mining(base)) == "burner-mining-drill:1,electric-mining-drill:0.5")
          assert(effect_vector(mining(selected)) == expected)
          assert(#selected.native_owners == #base.native_owners and #selected.native_paid == #base.native_paid)
          assert(continuation_ids(selected) == continuation_ids(base), "SE manufacturing cannot add a carrier")
          assert(selected.exact_product_target_families.research_mining_drill == true)
          assert(selected.required_product_targets.research_mining_drill[1] == "area-mining-drill"
            and selected.required_product_targets.research_mining_drill[4] == "se-core-miner-drill")

          local k2 = catalogue.select({base="2.0.77", ["space-exploration"]="0.7.57",
            Krastorio2="1.0", Krastorio2Assets="1.0"})
          assert(k2.profile == "k2-base-f200")
          assert(effect_vector(mining(k2)) == "burner-mining-drill:1,electric-mining-drill:0.5")
          assert(not k2.exact_product_target_families.research_mining_drill)

          f210()
          local se210 = catalogue.select({base="2.1.23", ["space-exploration"]="0.7.57"})
          assert(se210.profile == "space-exploration-f210" and effect_vector(mining(se210)) == expected)
          local k2se = catalogue.select({base="2.1.23", ["space-exploration"]="0.7.57",
            Krastorio2="1.0", Krastorio2Assets="1.0"})
          assert(k2se.profile == "k2-space-exploration-f210")
          assert(effect_vector(mining(k2se)) ==
            "burner-mining-drill:1,electric-mining-drill:0.5,area-mining-drill:0.25,kr-quarry-drill:0.25,se-core-miner-drill:0.25")

          f200()
          mods = source_mods
          package.loaded["research.settings"] = nil
          local settings = require("research.settings")
          local values = settings.resolve({})
          local modern = require("research.modern")
          local extension = require("research.product_target_extension")
          local technology = modern.technology(mining(selected), values)
          assert(effect_vector(technology) == "burner-mining-drill:0.2,electric-mining-drill:0.1,area-mining-drill:0.05,se-core-miner-drill:0.05")
          local raw = recipe_map(recipe_names)
          raw.recipe["synthetic-ore-extraction"] = {type="recipe", name="synthetic-ore-extraction", ingredients={},
            results={{type="item", name="iron-ore", amount=1}}}
          local before_raw, before_effects = recipe_shape(raw), effect_vector(technology)
          local report = extension.extend({technology}, values, {
            mods=source_mods, raw=raw, exact_product_bindings=selected.exact_product_bindings,
            exact_product_target_families=selected.exact_product_target_families,
            required_product_targets=selected.required_product_targets,
          })
          assert(report.extended_effects == 0 and effect_vector(technology) == before_effects)
          assert(recipe_shape(raw) == before_raw, "product collection must not mutate foreign recipes")

          local incomplete = recipe_map({"burner-mining-drill", "electric-mining-drill", "area-mining-drill"})
          local failed = modern.technology(mining(selected), values)
          local before_incomplete, before_failed = recipe_shape(incomplete), effect_vector(failed)
          local ok, message = pcall(extension.extend, {failed}, values, {
            mods=source_mods, raw=incomplete, exact_product_bindings=selected.exact_product_bindings,
            exact_product_target_families=selected.exact_product_target_families,
            required_product_targets=selected.required_product_targets,
          })
          assert(not ok and tostring(message):find("MIR product targets changed required family research_mining_drill", 1, true))
          assert(recipe_shape(incomplete) == before_incomplete and effect_vector(failed) == before_failed)

          local denied = recipe_map(recipe_names)
          denied.recipe["se-core-miner-drill"].allow_productivity = false
          ok, message = pcall(extension.extend, {modern.technology(mining(selected), values)}, values, {
            mods=source_mods, raw=denied, exact_product_bindings=selected.exact_product_bindings,
            exact_product_target_families=selected.exact_product_target_families,
            required_product_targets=selected.required_product_targets,
          })
          assert(not ok and tostring(message):find("MIR product targets changed required family research_mining_drill", 1, true))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ModernTargetTests))
    sys.exit(0 if result.wasSuccessful() else 1)

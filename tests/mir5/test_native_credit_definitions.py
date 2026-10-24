"""Pure controls for dormant, explicit native recipe-productivity credit carriers."""
import argparse
from pathlib import Path
import sys
import unittest

from native_credit_oracle import NATIVE_CREDIT_ICON


ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"


class NativeCreditDefinitionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          credit = require("research.native_credit_definitions")

          expected = {
            {"research_copper", "recipe-prod-research_copper-1", "copper-plate"},
            {"research_iron", "recipe-prod-research_iron-1", "iron-plate"},
            {"research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"},
            {"research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"},
            {"research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"},
            {"research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"},
            {"research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"},
            {"research_grenades", "recipe-prod-research_grenades-1", "grenade"},
            {"research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"},
            {"research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"},
            {"research_concrete", "recipe-prod-research_concrete-1", "stone-brick"},
            {"research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"},
          }

          function values(percent)
            local streams = {}
            for _, row in ipairs(expected) do streams[row[1]] = {effect_percent=percent} end
            return {streams=streams}
          end

          function inputs(omit_main, omit_recipe)
            local technologies, recipes = {{name="foreign-unrelated-row", effects={{recipe="foreign", change=.77}}}}, {
              ["foreign-unrelated-recipe"]={name="foreign-unrelated-recipe"}
            }
            local main_seen = {}
            for _, row in ipairs(expected) do
              if row[2] ~= omit_main and not main_seen[row[2]] then technologies[#technologies + 1] = {
                type="technology", name=row[2], effects={{type="change-recipe-productivity", recipe=row[3], change=.1}}
              }; main_seen[row[2]] = true end
              if row[3] ~= omit_recipe then recipes[row[3]] = {name=row[3]} end
            end
            return technologies, {
              recipe=setmetatable(recipes, {
                __pairs=function() error("native credit definitions scanned recipe world") end
              }),
              technology=setmetatable({}, {
                __index=function() error("native credit definitions inspected raw technologies") end,
                __pairs=function() error("native credit definitions scanned raw technologies") end
              })
            }
          end

          function rows_by_name(rows)
            local out = {}
            for _, row in ipairs(rows) do out[row.name] = row end
            return out
          end
        ''')

    def test_exact_twelve_descriptors_emit_twenty_four_isolated_native_carriers(self):
        self.lua.execute(r'''
          local descriptors = credit.descriptors()
          assert(#descriptors == #expected)
          local seen, main_rows = {}, {}
          for index, wanted in ipairs(expected) do
            local row = descriptors[index]
            assert(row.family == wanted[1] and row.main_id == wanted[2] and row.recipe == wanted[3])
            assert(row.positive_id == "mir-native-credit-" .. wanted[1] .. "-" .. wanted[3] .. "-positive")
            assert(row.negative_id == "mir-native-credit-" .. wanted[1] .. "-" .. wanted[3] .. "-negative")
            assert(not seen[row.positive_id] and not seen[row.negative_id])
            seen[row.positive_id], seen[row.negative_id] = true, true
            main_rows[row.main_id] = true
          end
          local main_count = 0; for _ in pairs(main_rows) do main_count = main_count + 1 end
          assert(main_count == 9)
          descriptors[1].recipe = "corrupted"
          assert(credit.descriptors()[1].recipe == "copper-plate", "descriptor export leaked mutable state")

          local technologies, raw = inputs()
          local original_count, original_effect = #technologies, technologies[1].effects[1].change
          local added = credit.append(technologies, raw, values(10), {recipe_productivity=true})
          assert(#added == 24 and #technologies == original_count + 24)
          assert(technologies[1].effects[1].change == original_effect and raw.recipe["copper-plate"].name == "copper-plate")
          local names = rows_by_name(added)
          for _, descriptor in ipairs(credit.descriptors()) do
            local positive, negative = names[descriptor.positive_id], names[descriptor.negative_id]
            assert(positive and negative and positive ~= negative)
            for _, row in ipairs({positive, negative}) do
              assert(row.type == "technology" and row.icon == "__base__/graphics/technology/automation-1.png"
                and row.icon_size == 256 and row.level == 1 and row.upgrade == true
                and row.hidden == true and row.enabled == false and row.visible_when_disabled == false
                and row.max_level == "infinite" and row.unit.count == 1 and row.unit.time == 1
                and #row.unit.ingredients == 1 and row.unit.ingredients[1][1] == "automation-science-pack"
                and row.unit.ingredients[1][2] == 1 and #row.effects == 1
                and row.effects[1].type == "change-recipe-productivity"
                and row.effects[1].recipe == descriptor.recipe)
            end
            assert(positive.effects[1].change == .1 and negative.effects[1].change == -.1)
          end
          local first, second = added[1], added[2]
          first.effects[1].change, first.unit.ingredients[1][1] = 99, "corrupted-science"
          assert(second.effects[1].change == -.1 and second.unit.ingredients[1][1] == "automation-science-pack")
          assert(raw.recipe["copper-plate"].name == "copper-plate")
        ''')

    def test_scalar_tuning_and_named_absence_change_only_their_authored_pairs(self):
        self.lua.execute(r'''
          local technologies, raw = inputs()
          local rows = credit.append(technologies, raw, values(2.5), {recipe_productivity=true})
          local by_name = rows_by_name(rows)
          assert(by_name["mir-native-credit-research_breeding-fish-breeding-positive"].effects[1].change == .025)
          assert(by_name["mir-native-credit-research_breeding-fish-breeding-negative"].effects[1].change == -.025)
          assert(by_name["mir-native-credit-research_copper-copper-plate-positive"].effects[1].change == .025)

          technologies, raw = inputs("recipe-prod-research_concrete-1", "firearm-magazine")
          rows = credit.append(technologies, raw, values(10), {recipe_productivity=true})
          by_name = rows_by_name(rows)
          assert(#rows == 20)
          assert(by_name["mir-native-credit-research_concrete-stone-brick-positive"] == nil)
          assert(by_name["mir-native-credit-research_bullets-firearm-magazine-positive"] == nil)
          assert(by_name["mir-native-credit-research_oil_processing_productivity-advanced-oil-processing-positive"] ~= nil)
          assert(technologies[1].name == "foreign-unrelated-row"
            and technologies[1].effects[1].recipe == "foreign"
            and raw.recipe["foreign-unrelated-recipe"].name == "foreign-unrelated-recipe")
        ''')

    def test_inactive_target_and_invalid_active_tuning_do_not_mutate_existing_output(self):
        self.lua.execute(r'''
          local technologies = {{name="foreign-unrelated-row"}}
          local poison = setmetatable({}, {__index=function() error("inactive target inspected raw") end})
          local none = credit.append(technologies, poison, nil, {recipe_productivity=false})
          assert(#none == 0 and #technologies == 1)

          local active, raw = inputs()
          local before = #active
          local configured = values(10)
          configured.streams.research_breeding.effect_percent = 0
          local ok, message = pcall(credit.append, active, raw, configured, {recipe_productivity=true})
          assert(not ok and tostring(message):find("no positive configured effect for research_breeding", 1, true))
          assert(#active == before, "invalid tuning appended a partial carrier set")
        ''')

    def test_carrier_icons_exist_in_f200_and_f210_base_assets_and_reject_the_missing_legacy_path(self):
        self.assertEqual("__base__/graphics/technology/automation-1.png", NATIVE_CREDIT_ICON)
        relative = Path("graphics/technology/automation-1.png")
        legacy = Path("graphics/technology/automation.png")
        engines = {
            "f200": Path(r"D:/Programs/Factorio/2.0/data/base"),
            "f210": Path(r"C:/Program Files/Steam/steamapps/common/Factorio/data/base"),
        }
        for target, base in engines.items():
            with self.subTest(target=target):
                if not base.is_dir():
                    self.skipTest(f"{target} native assets are unavailable on this host")
                self.assertTrue((base / relative).is_file(), f"{target} missing {relative.as_posix()}")
                self.assertFalse((base / legacy).exists(), f"{target} unexpectedly restored the invalid legacy icon")
                technology_source = (base / "prototypes/technology.lua").read_text(encoding="utf-8")
                self.assertRegex(
                    technology_source,
                    r'type = "technology",\s+name = "automation",\s+'
                    r'icon = "__base__/graphics/technology/automation-1\.png",\s+icon_size = 256',
                )

    def test_source_remains_descriptor_bounded_and_does_not_scan_raw_worlds(self):
        source = (PLAYER / "research/native_credit_definitions.lua").read_text(encoding="utf-8")
        modern = (PLAYER / "research/modern.lua").read_text(encoding="utf-8")
        self.assertIn(NATIVE_CREDIT_ICON, source)
        self.assertIn(NATIVE_CREDIT_ICON, modern)
        self.assertNotIn("__base__/graphics/technology/automation.png", source)
        self.assertNotIn("__base__/graphics/technology/automation.png", modern)
        self.assertNotIn("require(", source)
        self.assertNotIn("pairs(raw.recipe)", source)
        self.assertNotIn("ipairs(raw.recipe)", source)
        self.assertNotIn("raw.technology", source)
        self.assertNotIn("pairs(technologies)", source)
        self.assertIn("target.recipe_productivity ~= true", source)
        self.assertIn('raw.recipe[row.recipe]', source)
        composition = (PLAYER / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertLess(composition.index('retain_foreign_coverage('),
                        composition.index('require("research.native_credit_definitions").append('))
        self.assertLess(composition.index('require("research.native_credit_definitions").append('),
                        composition.index('generator.install(technologies, data)'))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeCreditDefinitionTests)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)

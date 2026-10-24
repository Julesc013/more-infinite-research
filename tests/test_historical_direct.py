'''Pure Lua 5.2 controls for the isolated historical direct-target draft.'''
import argparse
import json
from pathlib import Path
import sys
import unittest

TESTS_MIR5 = Path(__file__).resolve().parent
DRAFT_ROOT = TESTS_MIR5.parent
PLAYER = DRAFT_ROOT / "source"
NATIVE_ORACLE = TESTS_MIR5 / "fixtures/historical-direct-native-oracle.json"


def repository_root(start):
    for candidate in (start, *start.parents):
        if (candidate / ".git").exists() and (candidate / "source").is_dir():
            return candidate
    raise RuntimeError("MIR source root was not found from the historical direct control")


ROOT = repository_root(TESTS_MIR5)


class HistoricalDirectTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.globals().live_base_path = (ROOT / "source/compatibility/modern_catalogue/base.lua").as_posix()
        self.lua.globals().live_player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua;" .. live_player_root .. "/?.lua;" .. live_player_root .. "/?/init.lua"
          package.cpath = ""
          direct = require("research.native_direct_definitions")
          contracts = require("compatibility.historical_direct")
          constructor = require("research.historical_direct")
          historical_settings = require("research.historical_direct_settings")

          function same(left, right, seen)
            if type(left) ~= type(right) then return false end
            if type(left) ~= "table" then return left == right end
            seen = seen or {}
            if seen[left] == right then return true end
            if seen[left] ~= nil then return false end
            seen[left] = right
            for key, value in pairs(left) do if not same(value, right[key], seen) then return false end end
            for key in pairs(right) do if left[key] == nil then return false end end
            return true
          end

          function raw_for(target)
            local raw = {technology={}, tool={}, item={}}
            local contract = contracts.for_target(target)
            for _, row in ipairs(contract.emitted) do
              for _, prerequisite in ipairs(row.prerequisites) do
                raw.technology[prerequisite] = {icon="__base__/fake/" .. prerequisite .. ".png", icon_size=64}
              end
              for _, science in ipairs(row.science) do
                raw.tool[science] = {icon="__base__/fake/" .. science .. ".png", icon_size=64}
              end
              for _, candidate in ipairs(direct.definition(row.key).icon_candidates) do
                if candidate.technology and not candidate.required_mod then
                  raw.technology[candidate.technology] = {icon="__base__/fake/" .. candidate.technology .. ".png", icon_size=64}
                elseif candidate.item then
                  raw.tool[candidate.item] = {icon="__base__/fake/" .. candidate.item .. ".png", icon_size=64}
                end
              end
            end
            return raw
          end

          function by_name(technologies, name)
            for _, technology in ipairs(technologies) do if technology.name == name then return technology end end
            return nil
          end

          function assert_native_projection(target, expected)
            local actual = constructor.technologies(target, nil, raw_for(target))
            local count = 0
            for id, wanted in pairs(expected) do
              local technology = by_name(actual, id)
              assert(technology, "missing native-snapshot technology " .. id)
              assert(same(technology.effects, wanted.effects), "effects differ for " .. id)
              assert(same(technology.prerequisites, wanted.prerequisites), "prerequisites differ for " .. id)
              assert(same(technology.unit.ingredients, wanted.ingredients), "ingredients differ for " .. id)
              assert(technology.order == wanted.order, "order differs for " .. id)
              assert(technology.unit.time == wanted.unit_time, "research time differs for " .. id)
              if wanted.max_level_observed then
                assert(technology.max_level == wanted.max_level, "maximum level differs for " .. id)
              end
              if wanted.numeric_cost then
                assert(technology.unit.count == wanted.unit_count and technology.unit.count_formula == nil,
                  "numeric cost differs for " .. id)
              elseif wanted.unit_count_formula_observed then
                assert(technology.unit.count == nil and technology.unit.count_formula == wanted.unit_count_formula,
                  "formula cost differs for " .. id)
              end
              if wanted.enabled_observed then
                local enabled = technology.enabled
                if enabled == nil then enabled = true end
                assert(enabled == wanted.enabled, "enabled state differs for " .. id)
              end
              if wanted.visible_when_disabled_observed then
                assert(technology.visible_when_disabled == wanted.visible_when_disabled, "visibility differs for " .. id)
              end
              if wanted.hidden_observed then
                assert(wanted.hidden == false and technology.hidden == nil, "hidden default differs for " .. id)
              end
              count = count + 1
            end
            assert(count == #actual, "native snapshot has a different emitted surface")
          end
        ''')

    def _to_lua(self, value):
        if isinstance(value, list):
            return self.lua.table_from([self._to_lua(item) for item in value])
        if isinstance(value, dict):
            table = self.lua.table()
            for key, item in value.items():
                table[key] = self._to_lua(item)
            return table
        return value

    @staticmethod
    def _native_array(value):
        return [item for _, item in sorted(value.items(), key=lambda pair: int(pair[0]))]

    def test_exact_profile_surfaces_and_settings(self):
        self.lua.execute(r'''
          local expected = {
            f013={7, 9, 63}, f014={7, 9, 63}, f015={9, 10, 120}, f016={10, 11, 127},
            f017={11, 11, 127}, f100={11, 11, 127}, f110={11, 11, 127},
          }
          for target, counts in pairs(expected) do
            local contract = contracts.for_target(target)
            assert(#contract.emitted == counts[1] and #contract.settings == counts[2])
            assert(#historical_settings.prototypes(target) == counts[3])
          end
          local f013 = contracts.for_target("f013")
          assert(f013.factorio_line == "0.13")
          for _, row in ipairs(f013.emitted) do
            assert(row.key ~= "research_cannon_shooting_speed" and row.key ~= "research_flamethrower_shooting_speed")
          end
          local f015 = contracts.for_target("f015")
          assert(contracts.for_target("f014").factorio_line == "0.14")
          for _, row in ipairs(f015.emitted) do
            assert(row.key ~= "research_cannon_shooting_speed" and row.key ~= "research_lab_productivity")
          end
          local f016 = contracts.for_target("f016")
          for _, row in ipairs(f016.emitted) do assert(row.key ~= "research_cannon_shooting_speed") end
          local f110 = contracts.for_target("f110")
          local cannon
          for _, row in ipairs(f110.emitted) do if row.key == "research_cannon_shooting_speed" then cannon = row end end
          assert(cannon and cannon.prerequisites[#cannon.prerequisites] == "tank")
        ''')

    def test_historical_settings_keep_exact_names_defaults_and_time_sentinel(self):
        self.lua.execute(r'''
          local f015 = historical_settings.prototypes("f015")
          local by_name = {}
          for _, setting in ipairs(f015) do by_name[setting.name] = setting end
          local growth = by_name["ips-cost-growth-research_inventory_capacity"]
          assert(growth and growth.type == "double-setting" and growth.default_value == 1.1)
          assert(growth.minimum_value == 1 and growth.maximum_value == nil)
          assert(by_name["ips-enable-research_cannon_shooting_speed"] ~= nil)

          for _, name in ipairs({"research_character_reach", "research_inventory_capacity"}) do
            local effect = by_name["ips-effect-per-level-" .. name]
            assert(effect.type == "int-setting" and effect.minimum_value == 1 and effect.maximum_value == 1000000)
            assert(same(effect.localised_name, {"mod-setting-name.ips-effect-per-level-stream",
              {"technology-name.more-infinite-research." .. name}}))
          end

          -- Seven historical setting labels retain their short family locale,
          -- rather than the richer direct-technology caption used elsewhere.
          for _, name in ipairs({"research_character_mining_speed", "research_character_reach",
              "research_character_walking_speed", "research_flamethrower_shooting_speed",
              "research_inventory_capacity", "research_robot_battery", "research_rocket_shooting_speed"}) do
            local setting = by_name["ips-enable-" .. name]
            assert(same(setting.localised_name, {"mod-setting-name.ips-enable-stream",
              {"technology-name.more-infinite-research." .. name}}))
          end

          local expected_options = {
            ["mir-compiler-profile"]={type="string-setting", value="full", allowed={"full", "classic"}, hidden=true},
            ["ips-require-space-gate"]={type="bool-setting", value=false},
            ["mir-science-pack-ingredient-policy"]={type="string-setting", value="configured",
              allowed={"configured", "space", "space-and-promethium", "space-age-progression", "official-progression",
                "mod-progression", "all-official", "all"}},
            ["mir-lab-incompatibility-policy"]={type="string-setting", value="reduce",
              allowed={"reduce", "skip", "engine-default"}},
            ["mir-prefer-this-mod-for-competing-techs"]={type="bool-setting", value=true},
            ["mir-adjust-vanilla-weapon-speed-techs"]={type="string-setting", value="only-when-dedicated-tech-enabled",
              allowed={"off", "only-when-dedicated-tech-enabled", "always"}},
            ["mir-debug-generation-report"]={type="bool-setting", value=false},
            ["mir-debug-recipe-matches"]={type="bool-setting", value=false},
          }
          for name, expected in pairs(expected_options) do
            local setting = by_name[name]
            assert(setting and setting.setting_type == "startup" and setting.type == expected.type)
            assert(setting.default_value == expected.value and same(setting.allowed_values, expected.allowed))
            assert(setting.hidden == expected.hidden)
          end

          local expected_bases = {
            ["inserter-capacity-bonus"]={200, 3.333333333333, 60, 4, true,
              "technology-name.inserter-capacity-bonus"},
            ["braking-force"]={115, 1.333333333333, 60, 15, false, "technology-name.braking-force"},
            ["research-speed"]={60, 1.5, 120, 60, false, "technology-name.research-speed"},
            ["laser-shooting-speed"]={60, 1.5, 120, 50, false, "technology-name.laser-shooting-speed"},
            ["weapon-shooting-speed"]={60, 1.5, 120, 40, false, "technology-name.weapon-shooting-speed"},
            ["worker-robots-storage"]={200, 1.5, 60, 1, true, "technology-name.worker-robots-storage"},
          }
          for key, expected in pairs(expected_bases) do
            local enabled = by_name["mir-enable-" .. key]
            local base = by_name["mir-cost-base-" .. key]
            local linear = by_name["mir-cost-linear-increment-" .. key]
            local growth = by_name["mir-cost-growth-" .. key]
            local maximum = by_name["mir-max-level-" .. key]
            local time = by_name["mir-research-time-" .. key]
            local effect = by_name["mir-effect-per-level-" .. key]
            assert(enabled.type == "bool-setting" and enabled.default_value == true)
            assert(base.type == "int-setting" and base.default_value == expected[1]
              and base.minimum_value == 0 and base.maximum_value == 2147483647)
            assert(linear.type == "int-setting" and linear.default_value == 0
              and linear.minimum_value == 0 and linear.maximum_value == 2147483647)
            assert(growth.type == "double-setting" and growth.default_value == expected[2]
              and growth.minimum_value == 0 and growth.maximum_value == nil)
            assert(maximum.type == "int-setting" and maximum.default_value == 0
              and maximum.minimum_value == 0 and maximum.maximum_value == 2147483647)
            assert(time.type == "int-setting" and time.default_value == expected[3]
              and time.minimum_value == 0 and time.maximum_value == 2147483647)
            assert(effect.default_value == expected[4] and effect.maximum_value == 1000000)
            assert(effect.type == (expected[5] and "int-setting" or "double-setting"))
            assert(effect.minimum_value == (expected[5] and 1 or 0.01))
            assert(same(enabled.localised_name, {"mod-setting-name.mir-enable-base-tech", {expected[6]}}))
          end
          assert(same(by_name["mir-enable-inserter-capacity-bonus"].localised_description,
            {"", {"mod-setting-description.mir-enable-base-tech", {"technology-name.inserter-capacity-bonus"}},
              "\n\n", {"mod-setting-description.mir-note-inserter-capacity"}}))

          local values = historical_settings.resolve("f017", {
            ["ips-enable-research_character_crafting_speed"] = {value=false},
            ["ips-research-time-research_lab_productivity"] = {value=0},
            ["ips-require-space-gate"] = {value=true},
            ["mir-science-pack-ingredient-policy"] = {value="all"},
            ["mir-enable-inserter-capacity-bonus"] = {value=false},
            ["mir-research-time-inserter-capacity-bonus"] = {value=0},
            ["mir-effect-per-level-worker-robots-storage"] = {value=2},
          })
          assert(values.streams.research_character_crafting_speed.enabled == false)
          assert(values.streams.research_lab_productivity.research_time == 120)
          assert(values.streams.research_lab_productivity.configured.research_time == true)
          assert(values.options["ips-require-space-gate"] == true)
          assert(values.options["mir-science-pack-ingredient-policy"] == "all")
          assert(values.base_extensions["inserter-capacity-bonus"].enabled == false)
          assert(values.base_extensions["inserter-capacity-bonus"].research_time == 0)
          assert(values.base_extensions["inserter-capacity-bonus"].configured.research_time == true)
          assert(values.base_extensions["worker-robots-storage"].effect_percent == 2)

          -- The earlier source evidence does not authorize later settings.
          local f013 = historical_settings.prototypes("f013")
          for _, setting in ipairs(f013) do
            assert(setting.name:sub(1, 4) == "ips-")
            assert(setting.name ~= "ips-require-space-gate")
          end
          local early = historical_settings.resolve("f013", {
            ["mir-enable-inserter-capacity-bonus"] = {value=false},
          })
          assert(next(early.options) == nil and next(early.base_extensions) == nil)

          local ok, message = pcall(historical_settings.resolve, "f017", {
            ["ips-effect-per-level-research_character_reach"] = {value=1.5},
          })
          assert(not ok and string.find(message, "ips-effect-per-level-research_character_reach", 1, true))
          ok, message = pcall(historical_settings.resolve, "f017", {
            ["mir-effect-per-level-worker-robots-storage"] = {value=1.5},
          })
          assert(not ok and string.find(message, "mir-effect-per-level-worker-robots-storage", 1, true))
          ok, message = pcall(historical_settings.resolve, "f017", {
            ["mir-lab-incompatibility-policy"] = {value="invented"},
          })
          assert(not ok and string.find(message, "mir-lab-incompatibility-policy", 1, true))
        ''')

    def test_numeric_formula_maximum_visibility_and_constant_overlay_shapes(self):
        self.lua.execute(r'''
          local f013 = constructor.technologies("f013", nil, raw_for("f013"))
          local mining = by_name(f013, "recipe-prod-research_character_mining_speed-1")
          assert(mining.unit.count == 8000 and mining.unit.count_formula == nil)
          assert(mining.level == 1 and mining.upgrade and mining.max_level == "infinite" and mining.icons == nil)
          assert(mining.icon == "__base__/fake/steel-axe.png" and mining.icon_size == 64)

          local numeric_values = historical_settings.resolve("f013", {
            ["ips-max-level-research_character_mining_speed"] = {value=2},
            ["ips-enable-research_character_mining_speed"] = {value=false},
          })
          mining = by_name(constructor.technologies("f013", numeric_values, raw_for("f013")),
            "recipe-prod-research_character_mining_speed-1")
          assert(mining.max_level == 2 and mining.enabled == false)

          local f015 = constructor.technologies("f015", nil, raw_for("f015"))
          local crafting = by_name(f015, "recipe-prod-research_character_crafting_speed-1")
          assert(crafting.level == 1 and crafting.upgrade and crafting.max_level == "infinite")
          assert(crafting.visible_when_disabled == nil and crafting.unit.count_formula == "1*(8000*2^(L-1))")

          local f016 = constructor.technologies("f016", nil, raw_for("f016"))
          local lab = by_name(f016, "recipe-prod-research_lab_productivity-1")
          assert(lab and lab.unit.time == 120 and lab.unit.count_formula == "1*(1000*1.2^(L-1))")

          local f017 = constructor.technologies("f017", nil, raw_for("f017"))
          assert(f017[1].visible_when_disabled == false)

          local f110 = constructor.technologies("f110", nil, raw_for("f110"))
          local overlay = f110[1].icons[2]
          assert(overlay.icon == "__core__/graphics/icons/technology/constants/constant-speed.png")
          assert(overlay.icon_size == 128 and overlay.shift[1] == 100 and overlay.shift[2] == 100 and overlay.floating == true)
          local lab = by_name(f110, "recipe-prod-research_lab_productivity-1")
          assert(lab.icons[2].icon == "__core__/graphics/icons/technology/constants/constant-mining-productivity.png")

          local values = historical_settings.resolve("f017", {
            ["ips-cost-linear-increment-research_rocket_shooting_speed"] = {value=20},
            ["ips-cost-growth-research_rocket_shooting_speed"] = {value=1},
            ["ips-max-level-research_rocket_shooting_speed"] = {value=3},
          })
          local rocket = by_name(constructor.technologies("f017", values, raw_for("f017")),
            "recipe-prod-research_rocket_shooting_speed-1")
          assert(rocket.unit.count_formula == "1*(60+20*(L-1))" and rocket.max_level == 3)

          values = historical_settings.resolve("f017", {
            ["ips-cost-linear-increment-research_rocket_shooting_speed"] = {value=20},
            ["ips-cost-growth-research_rocket_shooting_speed"] = {value=2},
          })
          rocket = by_name(constructor.technologies("f017", values, raw_for("f017")),
            "recipe-prod-research_rocket_shooting_speed-1")
          assert(rocket.unit.count_formula == "1*((60+20*(L-1))*2^(L-1))")
        ''')

    def test_preflight_is_bounded_and_outputs_are_detached(self):
        self.lua.execute(r'''
          local raw = raw_for("f017")
          raw.technology["rocketry"] = nil
          local ok, message = pcall(constructor.technologies, "f017", nil, raw)
          assert(not ok and string.find(message, "requires technology rocketry", 1, true))

          raw = raw_for("f017")
          -- A foreign technology with a Space Age-only name cannot replace
          -- the delivered electric icon on an old target.
          raw.technology["electric-weapons-damage-1"] = {icon="foreign-space-age.png", icon_size=64}
          local electric = by_name(constructor.technologies("f017", nil, raw), "recipe-prod-research_electric_shooting_speed-1")
          assert(electric.icons[1].icon ~= "foreign-space-age.png")

          local first = constructor.technologies("f017", nil, raw)
          first[1].effects[1].modifier = 999
          first[1].icons[1].icon = "foreign"
          local second = constructor.technologies("f017", nil, raw)
          assert(second[1].effects[1].modifier ~= 999 and second[1].icons[1].icon ~= "foreign")

          raw = raw_for("f013")
          raw.technology["steel-axe"], raw.tool["steel-axe"] = nil, nil
          raw["mining-tool"] = { ["steel-axe"] = {icon="mining-tool-steel-axe.png", icon_size=64} }
          local mining = by_name(constructor.technologies("f013", nil, raw),
            "recipe-prod-research_character_mining_speed-1")
          assert(mining.icon == "mining-tool-steel-axe.png")

          raw = raw_for("f110")
          raw.technology["weapon-shooting-speed-3"], raw.technology["physical-projectile-damage-2"] = nil, nil
          raw.tool["cannon-shell"] = nil
          raw.ammo = { ["cannon-shell"] = {icon="cannon-ammo.png", icon_size=64} }
          local cannon = by_name(constructor.technologies("f110", nil, raw),
            "recipe-prod-research_cannon_shooting_speed-1")
          assert(cannon.icons[1].icon == "cannon-ammo.png")
        ''')

    def test_shared_modern_projection_and_pure_cost_extraction(self):
        self.lua.execute(r'''
          local live = assert(loadfile(live_base_path))()
          local found = {}
          for _, definition in ipairs(live.definitions) do found[definition.key] = definition end
          for _, key in ipairs(direct.keys()) do assert(same(direct.modern(key), found[key])) end
          local cost = require("research.cost")
          local productivity = require("research.productivity")
          assert(cost.cost(60, 0, 1) == "60")
          assert(cost.cost(60, 20, 1) == "60+20*(L-1)")
          assert(cost.cost(60, 20, 2) == "(60+20*(L-1))*2^(L-1)")
          assert(cost.cost(60, 20, 1000) == "(60+20*(L-1))*1000^(L-1)")
          local ok = pcall(cost.cost, 60, 20, 1000.1)
          assert(not ok)
          assert(cost.cost(8000, 0, 2) == "8000*2^(L-1)")
          assert(cost.cost(60, 0, 1.5) == "60*1.5^(L-1)")
          assert(productivity.cost(8000, 0, 2) == cost.cost(8000, 0, 2))
        ''')

    def test_historical_characterization_matches_portable_native_oracle(self):
        """This is historical source characterization, never MIR5 qualification."""
        oracle = json.loads(NATIVE_ORACLE.read_text(encoding="utf-8"))
        self.assertEqual(oracle["schema"], 1)
        self.assertEqual(oracle["kind"], "MIR5HistoricalDirectNativeCharacterizationV1")
        self.assertEqual(oracle["status"], "historical-characterization-not-mir5-native-qualification")
        self.assertTrue(oracle["limits"]["captured_fields_only"])
        self.assertIn("unit_count_formula", oracle["limits"]["f013_f014_missing_definition_fields"])
        self.assertIn("visible_when_disabled", oracle["limits"]["f013_f014_missing_state_fields"])

        for capture in oracle["captures"]:
            target = capture["target"]
            with self.subTest(target=target):
                source = capture["source"]
                self.assertEqual(source["force"], "player")
                self.assertTrue(source["path"].startswith("C:\\"))
                self.assertRegex(source["sha256"], r"^[A-F0-9]{64}$")
                self.assertEqual(len(capture["technologies"]), {"f013": 7, "f014": 7, "f015": 9,
                                                               "f016": 10, "f017": 11, "f100": 11,
                                                               "f110": 11}[target])
                self.assertEqual(len({row["id"] for row in capture["technologies"]}), len(capture["technologies"]))

                expected = {}
                for observed in capture["technologies"]:
                    definition = observed["definition"]
                    formula_observed = "unit_count_formula" in definition
                    row = {
                        "effects": self._native_array(definition["effects"]),
                        "prerequisites": self._native_array(definition["prerequisites"]),
                        "ingredients": [
                            [ingredient["name"], ingredient["amount"]]
                            for ingredient in self._native_array(definition["ingredients"])
                        ],
                        "order": definition["order"],
                        "unit_time": definition["unit_energy"] // 60,
                        "numeric_cost": not formula_observed,
                        "unit_count_formula_observed": formula_observed,
                        "enabled_observed": "enabled" in observed,
                        "enabled": observed.get("enabled"),
                        "visible_when_disabled_observed": "visible_when_disabled" in observed,
                        "visible_when_disabled": observed.get("visible_when_disabled"),
                        "hidden_observed": "hidden" in definition,
                        "hidden": definition.get("hidden"),
                        "max_level_observed": "max_level" in definition,
                    }
                    if formula_observed:
                        row["unit_count_formula"] = definition["unit_count_formula"]
                    else:
                        row["unit_count"] = definition["unit_count"]
                    if row["max_level_observed"]:
                        self.assertEqual(definition["max_level"], 4294967295)
                        row["max_level"] = "infinite"
                    expected[observed["id"]] = row

                self.lua.globals().native_expected = self._to_lua(expected)
                self.lua.execute(f'assert_native_projection("{target}", native_expected)')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(HistoricalDirectTests))
    sys.exit(0 if result.wasSuccessful() else 1)

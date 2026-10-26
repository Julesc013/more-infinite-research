"""Pure controls for exact historical base-continuation target subsets."""
import argparse
import json
from pathlib import Path
import sys
import unittest

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
PLAYER = ROOT / "source"
ORACLE = TESTS / "fixtures/historical-continuation-native-oracle.json"


class HistoricalContinuationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          contracts = require("compatibility.historical_continuations")
          constructor = require("research.historical_continuations")
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

          function source_time(family)
            return ({
              ["braking-force"]=60, ["inserter-capacity-bonus"]=30, ["research-speed"]=30,
              ["weapon-shooting-speed"]=60, ["worker-robots-storage"]=60, ["laser-shooting-speed"]=60,
            })[family]
          end

          function raw_for(target)
            local raw, contract = {technology={}, tool={}}, contracts.for_target(target)
            for _, row in ipairs(contract.rows) do
              for _, prerequisite in ipairs(row.prerequisites) do
                raw.technology[prerequisite] = {
                  icon="__base__/fake/" .. prerequisite .. ".png", icon_size=64,
                  order="other-" .. prerequisite, unit={count=1, time=30},
                }
              end
              for _, ingredient in ipairs(row.science) do raw.tool[ingredient[1]] = {} end
              local time = source_time(row.family)
              raw.technology[row.predecessor] = {
                icon="__base__/fake/" .. row.predecessor .. ".png", icon_size=64,
                localised_name={"technology-name." .. row.family},
                localised_description={"technology-description." .. row.family},
                order=row.order, unit={count=row.expected_predecessor_count, time=time},
              }
              raw.technology[row.previous] = {
                icon="__base__/fake/" .. row.previous .. ".png", icon_size=64,
                order="previous-" .. row.previous, unit={count=row.expected_previous_count, time=time},
              }
            end
            return raw
          end

          function values_for(target, startup)
            if target == "f013" or target == "f014" then return nil end
            return historical_settings.resolve(target, startup or {})
          end

          function by_name(rows, name)
            for _, row in ipairs(rows) do if row.name == name then return row end end
            return nil
          end

          function assert_projection(target, expected)
            local actual = constructor.technologies(target, values_for(target), raw_for(target))
            local count = 0
            for id, wanted in pairs(expected) do
              local technology = by_name(actual, id)
              assert(technology, "missing historical continuation " .. id)
              assert(technology.order == wanted.order, "order differs for " .. id)
              assert(same(technology.prerequisites, wanted.prerequisites), "prerequisites differ for " .. id)
              assert(same(technology.effects, wanted.effects), "effects differ for " .. id)
              assert(same(technology.unit.ingredients, wanted.ingredients), "ingredients differ for " .. id)
              assert(technology.unit.time == wanted.unit_time, "research time differs for " .. id)
              local enabled = technology.enabled
              if enabled == nil then enabled = true end
              assert(enabled == wanted.enabled, "enabled differs for " .. id)
              if wanted.numeric then
                assert(technology.unit.count == wanted.unit_count and technology.unit.count_formula == nil,
                  "numeric unit differs for " .. id)
                assert(technology.level == nil and technology.upgrade == nil and technology.max_level == nil,
                  "numeric target invented level fields for " .. id)
              else
                assert(technology.unit.count == nil and technology.unit.count_formula == wanted.unit_count_formula,
                  "formula differs for " .. id)
                assert(technology.level == wanted.first_level and technology.upgrade and technology.max_level == "infinite",
                  "progression fields differ for " .. id)
              end
              assert(technology.hidden == wanted.hidden, "hidden differs for " .. id)
              assert(technology.visible_when_disabled == wanted.visible_when_disabled,
                "visibility differs for " .. id)
              count = count + 1
            end
            assert(count == #actual, "historical continuation surface differs")
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

    def test_selected_targets_preserve_exact_observed_subsets(self):
        self.lua.execute(r'''
          local counts = {f013=2, f014=2, f015=4, f016=4, f017=5, f018=6, f100=5, f110=6}
          for target, count in pairs(counts) do
            local contract = contracts.for_target(target)
            assert(#contract.rows == count, target)
          end
          for _, target in ipairs({"f013", "f014"}) do
            local rows = constructor.technologies(target, nil, raw_for(target))
            assert(#rows == 2 and rows[1].unit.count and rows[1].unit.count_formula == nil)
          end
          for _, target in ipairs({"f015", "f016"}) do
            local rows = constructor.technologies(target, values_for(target), raw_for(target))
            assert(by_name(rows, "weapon-shooting-speed-7") == nil and by_name(rows, "laser-shooting-speed-8") == nil)
          end
          for _, target in ipairs({"f017", "f100"}) do
            local rows = constructor.technologies(target, values_for(target), raw_for(target))
            assert(by_name(rows, "weapon-shooting-speed-7") and by_name(rows, "laser-shooting-speed-8") == nil)
          end
          local f018 = constructor.technologies("f018", values_for("f018"), raw_for("f018"))
          local laser = by_name(f018, "laser-turret-speed-8")
          assert(laser and laser.effects[1].ammo_category == "laser-turret")
          assert(by_name(f018, "laser-shooting-speed-8") == nil and by_name(f018, "worker-robots-speed-6") == nil)
          local f110 = constructor.technologies("f110", values_for("f110"), raw_for("f110"))
          assert(by_name(f110, "laser-shooting-speed-8") and by_name(f110, "worker-robots-speed-6") == nil)
        ''')

    def test_settings_preserve_disabled_identities_finite_caps_and_historical_formula(self):
        self.lua.execute(r'''
          local raw = raw_for("f017")
          local values = values_for("f017", {
            ["mir-enable-braking-force"]={value=false},
            ["mir-max-level-braking-force"]={value=9},
            ["mir-max-level-inserter-capacity-bonus"]={value=7},
            ["mir-research-time-inserter-capacity-bonus"]={value=0},
            ["mir-effect-per-level-inserter-capacity-bonus"]={value=8},
            ["mir-cost-base-research-speed"]={value=115},
            ["mir-cost-linear-increment-research-speed"]={value=20},
            ["mir-cost-growth-research-speed"]={value=1},
          })
          local rows = constructor.technologies("f017", values, raw)
          local braking = by_name(rows, "braking-force-8")
          assert(braking.enabled == false and braking.max_level == 9)
          local inserter = by_name(rows, "inserter-capacity-bonus-8")
          assert(inserter.enabled == false and inserter.max_level == "infinite")
          assert(inserter.unit.time == 30 and inserter.effects[1].modifier == 4 and inserter.effects[2].modifier == 8)
          local research = by_name(rows, "research-speed-7")
          assert(research.unit.count_formula == "1*(115+20*(L-7))")

          -- Zero retains the legacy named-chain inheritance sentinel.  A
          -- sub-one configured growth also reaches the historical floor.
          values = values_for("f017", {
            ["mir-cost-base-research-speed"]={value=0},
            ["mir-cost-growth-research-speed"]={value=0},
          })
          rows = constructor.technologies("f017", values, raw)
          research = by_name(rows, "research-speed-7")
          assert(research.unit.count_formula == "1*(500)")
          values = values_for("f017", {
            ["mir-cost-base-research-speed"]={value=0},
            ["mir-cost-growth-research-speed"]={value=.5},
          })
          rows = constructor.technologies("f017", values, raw)
          assert(by_name(rows, "research-speed-7").unit.count_formula == "1*(500)")

          -- The base coefficient is L=1, so zero on an inserter stream with
          -- its default steep growth anchors from level 7 at exponent 6.
          values = values_for("f017", {
            ["mir-cost-base-inserter-capacity-bonus"]={value=0},
          })
          rows = constructor.technologies("f017", values, raw)
          assert(by_name(rows, "inserter-capacity-bonus-8").unit.count_formula
            == "1*(1999.986000042*3.33333^(L-8))")

          values = values_for("f017", {
            ["mir-max-level-research-speed"]={value=7},
          })
          rows = constructor.technologies("f017", values, raw)
          research = by_name(rows, "research-speed-7")
          assert(research.enabled == nil and research.max_level == 7)

          values = values_for("f018", {
            ["mir-enable-laser-shooting-speed"]={value=false},
            ["mir-effect-per-level-laser-shooting-speed"]={value=75},
          })
          rows = constructor.technologies("f018", values, raw_for("f018"))
          local laser = by_name(rows, "laser-turret-speed-8")
          assert(laser.enabled == false and laser.effects[1].ammo_category == "laser-turret"
            and laser.effects[1].modifier == .75)
        ''')

    def test_named_preflight_rejects_foreign_or_infinite_sources_before_output(self):
        self.lua.execute(r'''
          local values, raw = values_for("f110"), raw_for("f110")
          raw.technology["laser-shooting-speed-7"].max_level = "infinite"
          local ok, message = pcall(constructor.technologies, "f110", values, raw)
          assert(not ok and string.find(message, "infinite predecessor laser-shooting-speed-7", 1, true))

          raw = raw_for("f017")
          raw.technology["braking-force-7"].unit.count = 651
          ok, message = pcall(constructor.technologies, "f017", values_for("f017"), raw)
          assert(not ok and string.find(message, "unexpected source costs for braking-force-8", 1, true))

          raw = raw_for("f110")
          raw.technology["laser-shooting-speed-7"].max_level = 6
          ok, message = pcall(constructor.technologies, "f110", values_for("f110"), raw)
          assert(not ok and string.find(message, "unexpected finite predecessor levels for laser-shooting-speed-8", 1, true))

          raw = raw_for("f017")
          raw.technology["research-speed-7"] = {max_level="infinite"}
          ok, message = pcall(constructor.technologies, "f017", values_for("f017"), raw)
          assert(not ok and string.find(message, "identity is already owned: research-speed-7", 1, true))

          raw = raw_for("f018")
          raw.technology["laser-turret-speed-7"].unit.count = 451
          ok, message = pcall(constructor.technologies, "f018", values_for("f018"), raw)
          assert(not ok and string.find(message,
            "unexpected source costs for laser-turret-speed-8", 1, true))
        ''')

    def test_outputs_are_detached_and_use_only_named_source_rows(self):
        self.lua.execute(r'''
          local raw = raw_for("f110")
          raw.technology["worker-robots-speed-5"] = {max_level="infinite", unit={count=1, time=1}}
          local first = constructor.technologies("f110", values_for("f110"), raw)
          local laser = by_name(first, "laser-shooting-speed-8")
          laser.effects[1].modifier = 999
          laser.prerequisites[1] = "foreign"
          local second = constructor.technologies("f110", values_for("f110"), raw)
          laser = by_name(second, "laser-shooting-speed-8")
          assert(laser.effects[1].modifier == .5 and laser.prerequisites[1] == "chemical-science-pack")
        ''')

    def test_portable_native_characterization_matches_default_projection(self):
        """This is historical characterization, never MIR5 native qualification."""
        oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
        self.assertEqual(oracle["schema"], 1)
        self.assertEqual(oracle["kind"], "MIR5HistoricalContinuationNativeCharacterizationV1")
        self.assertEqual(oracle["status"], "historical-characterization-not-mir5-native-qualification")
        self.assertTrue(oracle["limits"]["captured_fields_only"])
        self.assertIn("retains", oracle["limits"]["retained_disabled_identity"])
        admission = oracle["admission_evidence"]
        self.assertEqual(admission["kind"], "hash-verified-local-engine-base-prototype-and-archived-planner-evidence")
        self.assertIn("omits raw max_level", admission["finite_predecessor_policy"])
        self.assertEqual(len(admission["engine_sources"]), 7)
        for source in admission["engine_sources"]:
            self.assertRegex(source["factorio_version"], r"^(0\.1[3-7]|1\.[01])$")
            for member in source["files"]:
                self.assertTrue(member["path"].startswith("D:\\Programs\\Factorio\\"))
                self.assertRegex(member["sha256"], r"^[A-F0-9]{64}$")
        resolver = admission["archived_formula_resolver"]
        self.assertRegex(resolver["archive_sha256"], r"^[A-F0-9]{64}$")
        self.assertIn("base setting 0 inherits predecessor_count / growth^(first_level - 1)", resolver["rules"])

        self.lua.globals().admission_facts = self._to_lua(admission["named_predecessor_facts"])
        self.lua.execute(r'''
          for _, target in ipairs({"f013", "f014", "f015", "f016", "f017", "f100", "f110"}) do
            for _, row in ipairs(contracts.for_target(target).rows) do
              local fact = admission_facts[row.id]
              assert(fact and row.predecessor == fact.predecessor.id and row.previous == fact.previous.id)
              assert(row.expected_predecessor_count == fact.predecessor.unit_count)
              assert(row.expected_previous_count == fact.previous.unit_count and row.order == fact.predecessor.order)
              assert(fact.raw_max_level == "omitted-native-finite-default")
            end
          end
        ''')

        expected_counts = {"f013": 2, "f014": 2, "f015": 4, "f016": 4, "f017": 5, "f100": 5, "f110": 6}
        for capture in oracle["captures"]:
            target = capture["target"]
            with self.subTest(target=target):
                source = capture["source"]
                self.assertTrue(source["path"].startswith("C:\\"))
                self.assertRegex(source["sha256"], r"^[A-F0-9]{64}$")
                self.assertEqual(len(capture["technologies"]), expected_counts[target])

                expected = {}
                for observed in capture["technologies"]:
                    definition = observed["definition"]
                    numeric = "unit_count_formula" not in definition
                    identifier = observed["id"]
                    first_level = int(identifier.rsplit("-", 1)[1])
                    expected[identifier] = {
                        "effects": self._native_array(definition["effects"]),
                        "prerequisites": self._native_array(definition["prerequisites"]),
                        "ingredients": [
                            [ingredient["name"], ingredient["amount"]]
                            for ingredient in self._native_array(definition["ingredients"])
                        ],
                        "order": definition["order"],
                        "unit_time": definition["unit_energy"] // 60,
                        "enabled": observed.get("enabled", True),
                        "numeric": numeric,
                        "hidden": definition.get("hidden"),
                        "visible_when_disabled": observed.get("visible_when_disabled"),
                        "first_level": first_level,
                    }
                    if numeric:
                        expected[identifier]["unit_count"] = definition["unit_count"]
                    else:
                        expected[identifier]["unit_count_formula"] = definition["unit_count_formula"]
                self.lua.globals().native_expected = self._to_lua(expected)
                self.lua.execute(f'assert_projection("{target}", native_expected)')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(HistoricalContinuationTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

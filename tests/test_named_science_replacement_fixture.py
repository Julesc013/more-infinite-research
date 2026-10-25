"""Focused host controls for the F210 named science replacement fixture."""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/named-science-replacement"
PROFILES = ROOT / "tests/profiles"
FREEZE = ROOT / "spec/evidence/current-assets-5658246a-readback.json"
PACKS = (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "utility-science-pack",
    "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
    "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
)
TARGET = "recipe-prod-research_gears-1"
CIRCULAR_OWNER = "a-mir473-circular-electromagnetic-owner"
SEEDED_OWNER = "z-mir473-seeded-electromagnetic-owner"


class NamedScienceReplacementFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          local PACK = "electromagnetic-science-pack"
          local CIRCULAR_RECIPE = "a-mir473-circular-electromagnetic-science"
          local SEEDED_RECIPE = "z-mir473-seeded-electromagnetic-science"
          local CIRCULAR_OWNER = "a-mir473-circular-electromagnetic-owner"
          local SEEDED_OWNER = "z-mir473-seeded-electromagnetic-owner"
          local FOREIGN = "mir473-named-science-foreign"
          local TARGET = "recipe-prod-research_gears-1"
          local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"}

          table.deepcopy = function(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local copy = {}
            seen[value] = copy
            for key, item in pairs(value) do copy[table.deepcopy(key, seen)] = table.deepcopy(item, seen) end
            return copy
          end

          local function base_raw()
            return {recipe={[PACK]={type="recipe", name=PACK, enabled=true,
              ingredients={{type="item", name="iron-plate", amount=1}},
              results={{type="item", name=PACK, amount=1}}}},
              technology={[PACK]={type="technology", name=PACK, icon="icon.png", icon_size=64,
                prerequisites={}, effects={{type="unlock-recipe", recipe=PACK}}}},
              ["string-setting"]={["mir-science-pack-ingredient-policy"]={type="string-setting", default_value="configured"}}}
          end

          local function data_for(raw)
            return {raw=raw, extend=function(self, rows)
              for _, row in ipairs(rows) do
                self.raw[row.type] = self.raw[row.type] or {}
                assert(self.raw[row.type][row.name] == nil, "fixture duplicate " .. row.name)
                self.raw[row.type][row.name] = row
              end
            end}
          end

          function run_settings(path, default)
            data = data_for(base_raw())
            data.raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value = default
            local ok, message = pcall(dofile, path)
            return {ok=ok, message=tostring(message),
              policy=data.raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value}
          end

          function run_updates(path, opponent)
            local raw = base_raw()
            if opponent == "missing-unlock" then raw.technology[PACK].effects = {} end
            data = data_for(raw)
            local ok, message = pcall(dofile, path)
            local unlocks = 0
            for _, effect in ipairs(raw.technology[PACK].effects or {}) do
              if effect.type == "unlock-recipe" and effect.recipe == PACK then unlocks = unlocks + 1 end
            end
            return {ok=ok, message=tostring(message), canonical_recipe=raw.recipe[PACK],
              canonical_unlocks=unlocks, circular=raw.technology[CIRCULAR_OWNER],
              seeded=raw.technology[SEEDED_OWNER], foreign=raw.technology[FOREIGN]}
          end

          function run_final(update_path, final_path, opponent)
            local raw = base_raw()
            data = data_for(raw)
            if opponent ~= "wrong-stage" then
              local updated, update_message = pcall(dofile, update_path)
              if not updated then return {ok=false, message=tostring(update_message), stage="updates"} end
            end
            local ingredients, prerequisites = {}, {}
            for index, name in ipairs(PACKS) do
              ingredients[index] = {name=name, amount=1}
              prerequisites[index] = name == PACK and SEEDED_OWNER or name
            end
            raw.technology[TARGET] = {type="technology", name=TARGET, enabled=true,
              prerequisites=prerequisites, unit={count_formula="1*2^(L-1)", time=60, ingredients=ingredients},
              effects={{type="change-recipe-productivity", recipe="iron-gear-wheel", change=.1}}}
            if opponent == "wrong-gate" then
              for index, name in ipairs(raw.technology[TARGET].prerequisites) do
                if name == SEEDED_OWNER then raw.technology[TARGET].prerequisites[index] = CIRCULAR_OWNER end
              end
            elseif opponent == "missing-gate" then
              for index, name in ipairs(raw.technology[TARGET].prerequisites) do
                if name == SEEDED_OWNER then table.remove(raw.technology[TARGET].prerequisites, index); break end
              end
            elseif opponent == "wrong-amount" then raw.technology[TARGET].unit.ingredients[1].amount = 2
            elseif opponent == "foreign-mutation" and raw.technology[FOREIGN] then raw.technology[FOREIGN].unit.time = 9
            elseif opponent == "missing-recipe" then raw.recipe[SEEDED_RECIPE] = nil
            elseif opponent == "canonical-restored" then raw.recipe[PACK] = {type="recipe", name=PACK, enabled=true}
            end
            local ok, message = pcall(dofile, final_path)
            return {ok=ok, message=tostring(message), target=raw.technology[TARGET], foreign=raw.technology[FOREIGN]}
          end
        ''')

    def test_settings_selects_all_official_without_touching_the_fixture_graph(self):
        result = self.lua.eval("run_settings")((FIXTURE / "settings-updates.lua").as_posix(), "configured")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("all-official", result["policy"])

    def test_data_updates_removes_only_the_canonical_recipe_unlock_and_adds_two_valid_sources(self):
        result = self.lua.eval("run_updates")((FIXTURE / "data-updates.lua").as_posix(), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNone(result["canonical_recipe"])
        self.assertEqual(0, result["canonical_unlocks"])
        self.assertEqual((True, 1, "electromagnetic-science-pack"),
                         (result["circular"]["enabled"], result["circular"]["unit"]["ingredients"][1][2],
                          result["circular"]["unit"]["ingredients"][1][1]))
        self.assertEqual(("craft-item", "iron-plate", 1),
                         (result["seeded"]["research_trigger"]["type"],
                          result["seeded"]["research_trigger"]["item"],
                          result["seeded"]["research_trigger"]["count"]))
        self.assertEqual((2, 5, 2),
                         (result["foreign"]["unit"]["count"], result["foreign"]["unit"]["time"],
                          result["foreign"]["unit"]["ingredients"][1][2]))

    def test_data_updates_rejects_a_noncanonical_starting_unlock(self):
        result = self.lua.eval("run_updates")((FIXTURE / "data-updates.lua").as_posix(), "missing-unlock")
        self.assertFalse(result["ok"])
        self.assertIn("removed exactly once", result["message"])

    def test_final_predicate_accepts_only_the_seeded_gate_with_complete_vector(self):
        result = self.lua.eval("run_final")(
            (FIXTURE / "data-updates.lua").as_posix(), (FIXTURE / "data-final-fixes.lua").as_posix(), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertTrue(result["target"]["enabled"])
        expected_prerequisites = tuple(SEEDED_OWNER if name == "electromagnetic-science-pack" else name for name in PACKS)
        self.assertEqual(expected_prerequisites,
                         tuple(result["target"]["prerequisites"][index] for index in range(1, 13)))
        self.assertEqual(tuple((name, 1) for name in PACKS),
                         tuple((result["target"]["unit"]["ingredients"][index]["name"],
                                result["target"]["unit"]["ingredients"][index]["amount"])
                               for index in range(1, 13)))

    def test_final_predicate_rejects_wrong_gate_missing_gate_amount_foreign_and_stage_opponents(self):
        for opponent in ("wrong-gate", "missing-gate", "wrong-amount", "foreign-mutation", "missing-recipe", "canonical-restored", "wrong-stage"):
            with self.subTest(opponent=opponent):
                result = self.lua.eval("run_final")(
                    (FIXTURE / "data-updates.lua").as_posix(),
                    (FIXTURE / "data-final-fixes.lua").as_posix(), opponent)
                self.assertFalse(result["ok"])
                self.assertTrue(result["message"])

    def test_published_profile_is_the_exact_f210_createonly_comparator(self):
        profile = json.loads((PROFILES / "named-science-replacement-published-f210-2123.json").read_text(encoding="utf-8"))
        self.assertEqual((1, "mir5-named-science-replacement-f210-native-selection", "f210", "2.1", "Defaults"),
                         (profile["schema"], profile["kind"], profile["target"], profile["factorio_line"],
                          profile["settings_mode"]))
        self.assertEqual({"version": "2.1.23",
                          "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"},
                         profile["engine"])
        self.assertEqual([(name, "2.1.23", True) for name in ("base", "elevated-rails", "quality", "recycler", "space-age")] + [
            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ("more-infinite-research", "4.7.21003", True),
            ("mir-fixture-mir5-named-science-replacement", "0.1.0", True),
        ], [(row["name"], row["version"], row["enabled"]) for row in profile["mods"]])
        self.assertEqual({
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
            "more-infinite-research_4.7.21003.zip":
                "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852",
        }, profile["archive_sha256"])
        self.assertIn("CreateOnly comparator", profile["scope"])

    def test_mir5_profile_changes_only_the_frozen_mir_arm_and_matches_accepted_565_assets(self):
        published = json.loads((PROFILES / "named-science-replacement-published-f210-2123.json").read_text(encoding="utf-8"))
        candidate = json.loads((PROFILES / "named-science-replacement-mir5-f210-2123.json").read_text(encoding="utf-8"))
        freeze = json.loads(FREEZE.read_text(encoding="utf-8"))
        self.assertEqual({key: value for key, value in published.items() if key not in ("mods", "archive_sha256", "scope")},
                         {key: value for key, value in candidate.items() if key not in ("mods", "archive_sha256", "scope")})
        self.assertEqual([row for row in published["mods"] if row["name"] != "more-infinite-research"],
                         [row for row in candidate["mods"] if row["name"] != "more-infinite-research"])
        published_mods = {row["name"]: row for row in published["mods"]}
        candidate_mods = {row["name"]: row for row in candidate["mods"]}
        self.assertEqual(1, sum(row["name"] == "more-infinite-research" for row in published["mods"]))
        self.assertEqual(1, sum(row["name"] == "more-infinite-research" for row in candidate["mods"]))
        self.assertEqual(("4.7.21003", True),
                         (published_mods["more-infinite-research"]["version"], published_mods["more-infinite-research"]["enabled"]))
        self.assertEqual(("5.0.21000", True),
                         (candidate_mods["more-infinite-research"]["version"], candidate_mods["more-infinite-research"]["enabled"]))
        self.assertEqual(set(published["archive_sha256"]),
                         {"mir-fixture-mir5-active-mods-observer_0.1.0.zip", "more-infinite-research_4.7.21003.zip"})
        self.assertEqual(set(candidate["archive_sha256"]),
                         {"mir-fixture-mir5-active-mods-observer_0.1.0.zip", "more-infinite-research_5.0.21000.zip"})
        self.assertEqual({key: value for key, value in published["archive_sha256"].items()
                          if key.startswith("mir-fixture-")},
                         {key: value for key, value in candidate["archive_sha256"].items()
                          if key.startswith("mir-fixture-")})
        self.assertEqual("B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852",
                         published["archive_sha256"]["more-infinite-research_4.7.21003.zip"])
        f210 = next(asset for asset in freeze["assets"] if asset["target"] == "f210")
        self.assertEqual(("5658246a7b8ea213d84496c420042c2ea9ad2eaa", "b1d04b99e1988d76de2ea09f869020dc986982a6"),
                         (freeze["source"]["commit"], freeze["source"]["source_tree"]))
        self.assertEqual(("more-infinite-research_5.0.21000.zip", 553252,
                          "428A789CA03828D2F7F93EC65C49FD3157FD6D547CC569DDA2C0129D6504647A"),
                         (f210["name"], f210["bytes"], f210["archive_sha256"].upper()))
        self.assertEqual(f210["archive_sha256"].upper(),
                         candidate["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
        self.assertIn("CreateOnly comparator", candidate["scope"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NamedScienceReplacementFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

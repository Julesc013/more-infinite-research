"""Pure checks for the bounded K2SO material technology constructor."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTINUATIONS = ROOT / "spec/inventory/k2so-material-continuations.json"
FACTS = json.loads((ROOT / "spec/inventory/k2so-material-facts.json").read_text(encoding="utf-8"))


def lua_table(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = lua_table(lua, item)
        return table
    if isinstance(value, (list, tuple)):
        table = lua.table()
        for index, item in enumerate(value, 1):
            table[index] = lua_table(lua, item)
        return table
    return value


class MaterialCatalogueTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.catalogue = self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          return require("compatibility.material_catalogue")
        ''')
        self.generator = self.lua.execute('return require("research.generator")')

    def active_mods(self):
        return lua_table(self.lua, {
            "space-age": "2.1.23", "Krastorio2Assets": "2.1.0", "k2so-assets": "1.0.7",
            "Krastorio2": "2.1.4",
            "Krastorio2-spaced-out": "2.0.19",
        })

    def values(self):
        streams = {}
        for name in (
            "research_material_rare_metals",
            "research_material_silicon",
            "research_material_glass",
        ):
            streams[name] = {
                "enabled": True,
                "base_cost": 200,
                "linear_increment": 0,
                "growth_factor": 2,
                "max_level": 0,
                "research_time": 30,
                "effect_percent": 2,
                "configured": {},
            }
        return lua_table(self.lua, {"streams": streams})

    def raw_fixture(self):
        items = {
            "automation-science-pack": {},
            "logistic-science-pack": {},
            "chemical-science-pack": {},
            "kr-rare-metals": {"icon": "__Krastorio2Assets__/icons/items/rare-metals.png"},
            "kr-silicon": {"icon": "__Krastorio2Assets__/icons/items/silicon.png"},
            "kr-glass": {"icon": "__Krastorio2Assets__/icons/items/glass.png"},
        }
        recipes = {row["recipe"]: {
            "enabled": row["enabled"], "allow_productivity": row["allow_productivity"],
            "ingredients": row["ingredients"], "results": row["products"],
        } for row in FACTS["current_no_mir_native"]["recipes"]}
        technologies = {
            "kr-rare-metal-processing": self.owner("kr-rare-metal-mining", "kr-rare-metals"),
            "kr-enriched-ores": self.owner("kr-advanced-chemistry", "kr-rare-metals-from-enriched-rare-metals"),
            "kr-silicon-processing": self.owner(
                ("kr-fluids-chemistry", "automation-2"), "kr-silicon"
            ),
            "kr-stone-processing": self.owner("kr-crusher", "kr-glass"),
        }
        for name in (
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "kr-rare-metal-mining", "kr-advanced-chemistry", "kr-fluids-chemistry",
            "automation-2", "kr-crusher",
        ):
            technologies.setdefault(name, {})
        return lua_table(self.lua, {
            "item": items,
            "recipe": recipes,
            "technology": technologies,
        })

    def owner(self, prerequisites, recipe):
        if isinstance(prerequisites, str):
            prerequisites = (prerequisites,)
        return {
            "prerequisites": list(prerequisites),
            "effects": [{"type": "unlock-recipe", "recipe": recipe}],
        }

    def rows(self, values=None, raw=None, active_mods=None):
        return self.catalogue["technologies"](
            values or self.values(), raw or self.raw_fixture(), active_mods or self.active_mods()
        )

    def test_authors_the_three_current_k2so_early_materials(self):
        rows = self.rows()
        expected = {
            "recipe-prod-research_material_rare_metals-1": {
                "recipes": ["kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"],
                "science": ["automation-science-pack", "logistic-science-pack", "chemical-science-pack"],
                "icon": "__Krastorio2Assets__/icons/items/rare-metals.png",
                "order": "p[research_material_rare_metals]",
            },
            "recipe-prod-research_material_silicon-1": {
                "recipes": ["kr-silicon"],
                "science": ["automation-science-pack", "logistic-science-pack"],
                "icon": "__Krastorio2Assets__/icons/items/silicon.png",
                "order": "p[research_material_silicon]",
            },
            "recipe-prod-research_material_glass-1": {
                "recipes": ["kr-glass"],
                "science": ["automation-science-pack", "logistic-science-pack", "chemical-science-pack"],
                "icon": "__Krastorio2Assets__/icons/items/glass.png",
                "order": "p[research_material_glass]",
            },
        }
        self.assertEqual(3, len(rows))
        for index in range(1, 4):
            row = rows[index]
            facts = expected[row["name"]]
            self.assertEqual("technology", row["type"])
            self.assertEqual(1, row["level"])
            self.assertTrue(row["upgrade"])
            self.assertEqual(3, row["max_level"])
            self.assertEqual("200*2^(L-1)", row["unit"]["count_formula"])
            self.assertEqual(30, row["unit"]["time"])
            self.assertEqual(facts["order"], row["order"])
            self.assertEqual(facts["icon"], row["icons"][1]["icon"])
            self.assertEqual(
                "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
                row["icons"][2]["icon"],
            )
            self.assertEqual(
                facts["science"],
                [row["unit"]["ingredients"][i][1] for i in range(1, len(facts["science"]) + 1)],
            )
            self.assertEqual(
                facts["recipes"],
                [row["effects"][i]["recipe"] for i in range(1, len(facts["recipes"]) + 1)],
            )
            self.assertTrue(all(
                row["effects"][i]["type"] == "change-recipe-productivity"
                and row["effects"][i]["change"] == 0.02
                for i in range(1, len(facts["recipes"]) + 1)
            ))
            self.assertEqual("", row["localised_name"][1])
            self.assertEqual("description.productivity-bonus", row["localised_name"][2][1])
            self.assertEqual(": ", row["localised_name"][3])
            self.assertTrue(row["localised_name"][4][1].startswith("item-name.kr-"))
            self.assertEqual(
                "technology-description.more-infinite-research.recipe_productivity",
                row["localised_description"][1],
            )

        self.lua.globals().catalogue_raw = self.raw_fixture()
        stage = self.lua.execute('''
          local stage = {raw = catalogue_raw, writes = 0}
          function stage:extend(batch)
            self.writes = self.writes + 1
            self.batch = batch
          end
          return stage
        ''')
        self.generator["install"](rows, stage)
        self.assertEqual(1, stage["writes"])
        self.assertEqual(3, len(stage["batch"]))

    def test_resolved_settings_control_cost_effect_time_cap_and_disabled_identity(self):
        values = self.values()
        rare = values["streams"]["research_material_rare_metals"]
        rare["base_cost"] = 250
        rare["linear_increment"] = 3
        rare["growth_factor"] = 2
        rare["research_time"] = 45
        rare["effect_percent"] = 3
        rare["max_level"] = 2
        values["streams"]["research_material_silicon"]["enabled"] = False

        rows = self.rows(values=values)
        rare_row = rows[1]
        silicon_row = rows[2]
        self.assertEqual("(250+3*(L-1))*2^(L-1)", rare_row["unit"]["count_formula"])
        self.assertEqual(45, rare_row["unit"]["time"])
        self.assertEqual(3, rare_row["max_level"])
        self.assertTrue(all(rare_row["effects"][i]["change"] == 0.03 for i in (1, 2)))
        self.assertEqual("recipe-prod-research_material_silicon-1", silicon_row["name"])
        self.assertFalse(silicon_row["enabled"])

        invalid = self.values()
        invalid["streams"]["research_material_glass"]["effect_percent"] = float("inf")
        with self.assertRaisesRegex(Exception, "research_material_glass resolved settings are invalid"):
            self.rows(values=invalid)

    def test_narrow_mod_gate_and_detached_output(self):
        self.assertEqual(0, len(self.rows(active_mods=lua_table(self.lua, {"Krastorio2": "2.1.4"}))))
        # Installed F200 K2SO 1.6.21 is a standalone overhaul: its native
        # dependencies exclude Krastorio2 and rare metals are enabled at
        # startup. This distinct binding remains outside this K2+K2SO batch.
        f200_k2so = lua_table(self.lua, {
            "space-age": "2.0.77", "Krastorio2-spaced-out": "1.6.21",
            "Krastorio2Assets": "2.0.5", "k2so-assets": "1.0.7",
        })
        self.assertEqual(0, len(self.rows(active_mods=f200_k2so)))
        for missing in ("space-age", "Krastorio2Assets", "k2so-assets"):
            partial = self.active_mods()
            partial[missing] = None
            self.assertEqual(0, len(self.rows(active_mods=partial)))
        first = self.rows()
        first[1]["effects"][1]["change"] = 99
        first[1]["icons"][1]["icon"] = "changed"
        second = self.rows()
        self.assertEqual(0.02, second[1]["effects"][1]["change"])
        self.assertEqual("__Krastorio2Assets__/icons/items/rare-metals.png", second[1]["icons"][1]["icon"])

    def test_named_raw_checks_are_semantic_and_do_not_scan(self):
        raw = self.raw_fixture()
        poison_pairs = self.lua.eval(
            'function(value) return setmetatable(value, {__pairs = function() error("global scan") end}) end'
        )
        raw["recipe"] = poison_pairs(raw["recipe"])
        raw["technology"] = poison_pairs(raw["technology"])
        self.assertEqual(3, len(self.rows(raw=raw)))

        cosmetic = self.raw_fixture()
        cosmetic["item"]["kr-silicon"]["icon"] = "__another-mod__/silicon.png"
        cosmetic["technology"]["kr-silicon-processing"]["prerequisites"] = lua_table(
            self.lua, ["another-prerequisite", "automation-2", "kr-fluids-chemistry"]
        )
        self.assertEqual(3, len(self.rows(raw=cosmetic)))

        full_probability = self.raw_fixture()
        full_probability["recipe"]["kr-silicon"]["results"][1]["shared_probability"] = lua_table(
            self.lua, {"min": 0, "max": 1}
        )
        self.assertEqual(3, len(self.rows(raw=full_probability)))

        wrong_type = self.raw_fixture()
        wrong_type["recipe"]["kr-glass"]["results"][1]["type"] = "fluid"
        with self.assertRaisesRegex(Exception, "kr-glass changed"):
            self.rows(raw=wrong_type)

        zero_product = self.raw_fixture()
        zero_product["recipe"]["kr-silicon"]["results"][1]["amount"] = 0
        with self.assertRaisesRegex(Exception, "kr-silicon changed"):
            self.rows(raw=zero_product)

        not_productive = self.raw_fixture()
        not_productive["recipe"]["kr-glass"]["allow_productivity"] = False
        with self.assertRaisesRegex(Exception, "kr-glass changed"):
            self.rows(raw=not_productive)

        missing_unlock = self.raw_fixture()
        missing_unlock["technology"]["kr-silicon-processing"]["effects"] = lua_table(self.lua, [])
        with self.assertRaisesRegex(Exception, "kr-silicon-processing no longer owns kr-silicon"):
            self.rows(raw=missing_unlock)

    def test_local_route_drift_and_named_duplicate_owner_fail_before_publication(self):
        for label in ("return", "extra-product", "probability", "shared-probability", "ignored", "changed-input",
                      "duplicate-owner", "negative-owner", "zero-owner", "invalid-owner"):
            with self.subTest(label=label):
                raw = self.raw_fixture()
                recipe = raw["recipe"]["kr-silicon"]
                if label == "return":
                    recipe["ingredients"][2] = lua_table(self.lua, {"type":"item", "name":"kr-silicon", "amount":1})
                elif label == "extra-product":
                    recipe["results"][2] = lua_table(self.lua, {"type":"item", "name":"kr-quartz", "amount":1})
                elif label == "probability":
                    recipe["results"][1]["probability"] = 0.5
                elif label == "shared-probability":
                    recipe["results"][1]["shared_probability"] = lua_table(self.lua, {"min": 0, "max": 0.5})
                elif label == "ignored":
                    recipe["results"][1]["ignored_by_productivity"] = 9
                elif label == "changed-input":
                    recipe["ingredients"][1]["name"] = "kr-silicon"
                else:
                    raw["technology"]["kr-silicon-processing"]["effects"][2] = lua_table(self.lua, {
                        "type":"change-recipe-productivity", "recipe":"kr-silicon",
                        "change": {"duplicate-owner": 0.01, "negative-owner": -0.02,
                                   "zero-owner": 0, "invalid-owner": float("nan")}[label],
                    })
                with self.assertRaisesRegex(Exception, "kr-silicon changed|already supplies productivity"):
                    self.rows(raw=raw)

    def test_runtime_metadata_never_imports_the_material_constructor(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          script = {active_mods={['space-age']='2.1.23',Krastorio2='2.1.4',
            ['Krastorio2-spaced-out']='2.0.19',Krastorio2Assets='2.1.0',['k2so-assets']='1.0.7'}}
          local rows = require('research.catalogue').declared()
          local count = 0
          for _, row in ipairs(rows) do
            if row.family == 'research_material_rare_metals' or row.family == 'research_material_silicon'
              or row.family == 'research_material_glass' then count = count + 1 end
          end
          assert(count == 3)
          assert(package.loaded['compatibility.material_catalogue'] == nil)
          assert(package.loaded['research.generator'] == nil)
        ''')

    def test_unsupported_late_identities_remain_inventory_only(self):
        inventory = json.loads(CONTINUATIONS.read_text(encoding="utf-8"))
        continuations = inventory["continuations"]
        self.assertEqual(
            [
                "recipe-prod-research_material_rare_metals-4",
                "recipe-prod-research_material_silicon-4",
                "recipe-prod-research_material_glass-4",
            ],
            [row["technology"] for row in continuations],
        )
        self.assertTrue(all(row["carrier_ids"] == [] for row in continuations))
        self.assertTrue(all(self.rows()[index]["name"].endswith("-1") for index in range(1, 4)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MaterialCatalogueTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

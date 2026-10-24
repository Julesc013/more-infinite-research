"""Bounded F210 BobTech material admission checks; no MIR5 native result claimed."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
FACTS_PATH = ROOT / "tests/mir5/fixtures/bob-tech-f210-captured-facts.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = _lua_value(lua, item)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, item in enumerate(value, 1):
            table[index] = _lua_value(lua, item)
        return table
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(item) for key, item in items.items()}


class BobTechMaterialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        profile = ROOT / cls.facts["profile"]
        if _sha256(profile) != cls.facts["profile_sha256"]:
            raise AssertionError(f"hash-locked F210 BobTech profile changed: {profile}")
        for evidence in cls.facts["qualification_evidence"]:
            path = ROOT / evidence["path"]
            if _sha256(path) != evidence["sha256"]:
                raise AssertionError(f"F210 BobTech evidence changed: {path}")

        # The independent source package is retained with the repository. A
        # clean hosted checkout may omit distribution custody; semantic tests
        # below still execute from the committed compact fact record.
        source = cls.facts["published_source"]
        package = ROOT / source["path"]
        if package.is_file():
            if _sha256(package) != source["sha256"]:
                raise AssertionError("published F210 source package changed")
            with zipfile.ZipFile(package) as archive:
                if _sha256_bytes(archive.read(source["member"])) != source["member_sha256"]:
                    raise AssertionError("published F210 productivity source member changed")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits = "independent_probability", true
          target.productivity_ignores_stats = true
        ''')
        self.catalogue = self.lua.execute('return require("compatibility.bob_tech_materials")')
        self.generator = self.lua.execute('return require("research.generator")')

    def active_mods(self):
        return _lua_value(self.lua, self.facts["required_mods"])

    def values(self):
        streams = {}
        for family in self.facts["families"]:
            streams[family["key"]] = {
                "enabled": True, "base_cost": 200, "linear_increment": 0,
                "growth_factor": 2, "max_level": 0, "research_time": 30,
                "effect_percent": 2,
            }
        return _lua_value(self.lua, {"streams": streams})

    def raw_fixture(self):
        raw = {
            "item": {}, "tool": {name: {} for name in self.facts["laboratory"]["inputs"]},
            "recipe": {}, "technology": {},
            "lab": {self.facts["laboratory"]["name"]: {"inputs": deepcopy(self.facts["laboratory"]["inputs"])}},
        }
        for family in self.facts["families"]:
            raw["item"][family["item"]] = {
                "icon": family["icon"], "icon_size": family["icon_size"],
            }
            for route in family["routes"]:
                raw["recipe"][route["recipe"]] = {
                    "enabled": False, "allow_productivity": True,
                    "maximum_productivity": route["maximum_productivity"],
                    "ingredients": deepcopy(route["ingredients"]),
                    "results": deepcopy(route["results"]),
                }
                owner = raw["technology"].setdefault(route["owner"], {
                    "prerequisites": deepcopy(route["owner_prerequisites"]),
                    "unit": {"ingredients": deepcopy(route["owner_science"])},
                    "effects": [],
                })
                owner["effects"].append({"type": "unlock-recipe", "recipe": route["recipe"]})
            for stage_name in ("early", "continuation"):
                stage = family.get(stage_name)
                if stage:
                    for prerequisite in stage["prerequisites"]:
                        if prerequisite != family["early"]["id"]:
                            raw["technology"].setdefault(prerequisite, {})
        return _lua_value(self.lua, raw)

    def rows(self, values=None, raw=None, active_mods=None):
        return self.catalogue["technologies"](
            values or self.values(), raw or self.raw_fixture(), active_mods or self.active_mods()
        )

    def test_exact_five_rows_preserve_stage_boundaries_and_named_routes(self):
        rows = _plain(self.rows())
        self.assertEqual(self.facts["totals"]["technology_rows"], len(rows))
        by_id = {row["name"]: row for row in rows}
        self.assertEqual(len(rows), len(by_id))
        expected_ids = []
        for family in self.facts["families"]:
            expected_ids.append(family["early"]["id"])
            if family.get("continuation"):
                expected_ids.append(family["continuation"]["id"])
        self.assertEqual(expected_ids, [row["name"] for row in rows])

        for family in self.facts["families"]:
            expected_recipes = [route["recipe"] for route in family["routes"]]
            for stage_name in ("early", "continuation"):
                stage = family.get(stage_name)
                if not stage:
                    continue
                row = by_id[stage["id"]]
                self.assertEqual("technology", row["type"])
                self.assertEqual(stage["level"], row["level"])
                self.assertTrue(row["upgrade"])
                self.assertEqual(stage["max_level"], row["max_level"])
                self.assertEqual(stage["order"], row["order"])
                self.assertEqual(stage["count_formula"], row["unit"]["count_formula"])
                self.assertEqual(stage["time"], row["unit"]["time"])
                self.assertEqual(stage["prerequisites"], row["prerequisites"])
                self.assertEqual(stage["science"], [
                    ingredient[0] for ingredient in row["unit"]["ingredients"]
                ])
                self.assertEqual(expected_recipes, [
                    effect["recipe"] for effect in row["effects"]
                ])
                self.assertTrue(all(
                    effect["type"] == "change-recipe-productivity" and effect["change"] == 0.02
                    for effect in row["effects"]
                ))
                self.assertEqual(family["icon"], row["icons"][0]["icon"])
                self.assertEqual(family["icon_size"], row["icons"][0]["icon_size"])

        tin_tail = self.facts["families"][0]["withheld_continuation"]
        self.assertNotIn(tin_tail["id"], by_id)
        for family in self.facts["withheld_families"]:
            self.assertNotIn(f"recipe-prod-{family}-1", by_id)
            self.assertNotIn(f"recipe-prod-{family}-4", by_id)

        self.lua.globals().fixture_raw = self.raw_fixture()
        stage = self.lua.execute(r'''
          local stage = {raw=fixture_raw, writes=0}
          function stage:extend(batch) self.writes = self.writes + 1; self.batch = batch end
          return stage
        ''')
        self.generator["install"](self.rows(), stage)
        self.assertEqual(1, stage["writes"])
        self.assertEqual(rows, _plain(stage["batch"]))

    def test_settings_change_tuning_without_erasing_finite_or_tail_boundaries(self):
        values = self.values()
        gunmetal = values["streams"]["research_material_gunmetal"]
        gunmetal["base_cost"] = 250
        gunmetal["linear_increment"] = 3
        gunmetal["growth_factor"] = 2
        gunmetal["research_time"] = 45
        gunmetal["effect_percent"] = 3
        values["streams"]["research_material_tin"]["enabled"] = False
        rows = {row["name"]: row for row in _plain(self.rows(values=values))}
        self.assertEqual("(250+3*(L-1))*2^(L-1)", rows["recipe-prod-research_material_gunmetal-1"]["unit"]["count_formula"])
        self.assertEqual("2072+250*(L-4)", rows["recipe-prod-research_material_gunmetal-4"]["unit"]["count_formula"])
        self.assertEqual(45, rows["recipe-prod-research_material_gunmetal-1"]["unit"]["time"])
        self.assertEqual(45, rows["recipe-prod-research_material_gunmetal-4"]["unit"]["time"])
        self.assertEqual(0.03, rows["recipe-prod-research_material_gunmetal-1"]["effects"][0]["change"])
        self.assertEqual(0.03, rows["recipe-prod-research_material_gunmetal-4"]["effects"][0]["change"])
        self.assertFalse(rows["recipe-prod-research_material_tin-1"]["enabled"])
        self.assertEqual(3, rows["recipe-prod-research_material_gunmetal-1"]["max_level"])
        self.assertEqual("infinite", rows["recipe-prod-research_material_gunmetal-4"]["max_level"])

    def test_default_science_policy_keeps_each_authored_vector_in_the_named_f210_lab(self):
        rows = self.rows()
        raw = self.raw_fixture()
        self.lua.globals().fixture_rows = rows
        self.lua.globals().fixture_raw = raw
        self.lua.globals().fixture_mods = self.active_mods()
        reports = self.lua.execute(r'''
          local science = require("research.science")
          local target = require("platform.target")
          local reports = science.apply_family(fixture_rows, nil, {
            options={}, raw=fixture_raw, target=target, mods=fixture_mods,
          })
          return reports
        ''')
        expected = {
            family[stage_name]["id"]: family[stage_name]["science"]
            for family in self.facts["families"]
            for stage_name in ("early", "continuation")
            if family.get(stage_name)
        }
        actual_rows = _plain(rows)
        for row in actual_rows:
            self.assertNotEqual(False, row.get("enabled"), row["name"])
            self.assertEqual(expected[row["name"]], [ingredient[0] for ingredient in row["unit"]["ingredients"]])
        self.assertTrue(all(report["reason"] == "configured" for report in reports.values()))

    def test_profile_gate_admits_changed_versions_only_for_the_same_raw_contract(self):
        self.assertEqual(5, len(self.rows()))
        self.lua.execute('target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"')
        self.assertEqual(0, len(self.rows()))
        self.lua.execute('target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"')
        self.lua.execute('target.minimum_base = "2.1.24"')
        with self.assertRaisesRegex(Exception, "unsupported F210 BobTech saved-profile transition"):
            self.rows()
        self.lua.execute('target.minimum_base = "2.1.23"')

        # Captured versions lock the qualified evidence, but an unchanged named
        # raw contract remains applicable across an official patch or graphics
        # package version change.  Semantic admission remains validate_raw.
        baseline = _plain(self.rows())
        for changed in ("base", "space-age", "bobtech", "angelssmeltinggraphics"):
            mods = dict(self.facts["required_mods"])
            mods[changed] = "2.1.24" if changed in ("base", "space-age") else "changed"
            self.assertEqual(baseline, _plain(self.rows(active_mods=_lua_value(self.lua, mods))))

        changed = dict(self.facts["required_mods"])
        changed["bobtech"] = "changed"
        wrong_io = self.raw_fixture()
        wrong_io["recipe"]["angels-plate-invar"]["results"][1]["amount"] = 5
        with self.assertRaisesRegex(Exception, "angels-plate-invar changed"):
            self.rows(raw=wrong_io, active_mods=_lua_value(self.lua, changed))
        wrong_owner = self.raw_fixture()
        wrong_owner["technology"]["angels-gunmetal-smelting-1"]["effects"][1]["type"] = "change-recipe-productivity"
        with self.assertRaisesRegex(Exception, "angels-gunmetal-smelting-1 no longer owns angels-plate-gunmetal"):
            self.rows(raw=wrong_owner, active_mods=_lua_value(self.lua, changed))
        for marker in self.facts["forbidden_markers"]:
            mods = dict(self.facts["required_mods"])
            mods[marker] = "present"
            with self.assertRaisesRegex(Exception, "unsupported F210 BobTech saved-profile transition"):
                self.rows(active_mods=_lua_value(self.lua, mods))

        partial = dict(self.facts["required_mods"])
        del partial["angelssmelting"]
        self.assertEqual(0, len(self.rows(active_mods=_lua_value(self.lua, partial))))
        unrelated = {**self.facts["required_mods"], "unrelated-observer": "0.1.0"}
        self.assertEqual(5, len(self.rows(active_mods=_lua_value(self.lua, unrelated))))

    def test_complete_changed_bobtech_closure_declares_settings_before_raw_preflight(self):
        # Settings are declared before data-final emission. This must fail
        # there too, rather than hiding the three setting families and later
        # omitting their five established technology IDs.
        changed = dict(self.facts["required_mods"])
        changed["base"] = "2.1.24"
        self.lua.globals().mods = _lua_value(self.lua, changed)
        settings = self.lua.execute('package.loaded["research.settings"] = nil; return require("research.settings")')
        self.assertIsNotNone(settings)

    def test_named_preflight_rejects_route_owner_and_stage_drift_without_scanning(self):
        poison = self.lua.eval('function(value) return setmetatable(value, {__pairs=function() error("global scan") end}) end')
        raw = self.raw_fixture()
        raw["recipe"] = poison(raw["recipe"])
        raw["technology"] = poison(raw["technology"])
        self.assertEqual(5, len(self.rows(raw=raw)))

        wrong_cap = self.raw_fixture()
        wrong_cap["recipe"]["angels-plate-gunmetal"]["maximum_productivity"] = 2
        with self.assertRaisesRegex(Exception, "angels-plate-gunmetal changed"):
            self.rows(raw=wrong_cap)

        wrong_io = self.raw_fixture()
        wrong_io["recipe"]["angels-plate-invar"]["results"][1]["amount"] = 5
        with self.assertRaisesRegex(Exception, "angels-plate-invar changed"):
            self.rows(raw=wrong_io)

        wrong_probability = self.raw_fixture()
        wrong_probability["recipe"]["angels-plate-tin"]["results"][1]["shared_probability"] = {"min": 0.1, "max": 1}
        with self.assertRaisesRegex(Exception, "angels-plate-tin changed"):
            self.rows(raw=wrong_probability)

        wrong_owner = self.raw_fixture()
        wrong_owner["technology"]["angels-gunmetal-smelting-1"]["effects"][1]["type"] = "change-recipe-productivity"
        with self.assertRaisesRegex(Exception, "angels-gunmetal-smelting-1 no longer owns angels-plate-gunmetal"):
            self.rows(raw=wrong_owner)

        missing_tail_gate = self.raw_fixture()
        missing_tail_gate["technology"]["space-science-pack"] = None
        with self.assertRaisesRegex(Exception, "recipe-prod-research_material_gunmetal-4 has missing prerequisite space-science-pack"):
            self.rows(raw=missing_tail_gate)

    def test_outputs_are_detached_and_catalogue_metadata_names_exact_routes_and_boundaries(self):
        first = self.rows()
        first[1]["effects"][1]["recipe"] = "corrupted"
        first[2]["prerequisites"][1] = "corrupted"
        first[3]["icons"][1]["icon"] = "corrupted"
        second = _plain(self.rows())
        self.assertEqual("angels-plate-tin", second[0]["effects"][0]["recipe"])
        self.assertEqual("angels-gunmetal-smelting-1", second[1]["prerequisites"][0])
        self.assertEqual(self.facts["families"][1]["icon"], second[2]["icons"][0]["icon"])

        self.lua.globals().mods = self.active_mods()
        catalogue = self.lua.execute('package.loaded["research.catalogue"] = nil; return require("research.catalogue")')
        declared = {
            row["id"]: _plain(row)
            for row in catalogue["declared"]().values()
            if row["id"].startswith("recipe-prod-research_material_")
        }
        self.assertEqual({
            "recipe-prod-research_material_tin-1",
            "recipe-prod-research_material_gunmetal-1",
            "recipe-prod-research_material_gunmetal-4",
            "recipe-prod-research_material_invar-1",
            "recipe-prod-research_material_invar-4",
        }, set(declared))
        self.assertNotIn("recipe-prod-research_material_tin-4", declared)
        for family in self.facts["families"]:
            recipes = [route["recipe"] for route in family["routes"]]
            for stage_name in ("early", "continuation"):
                stage = family.get(stage_name)
                if not stage:
                    continue
                row = declared[stage["id"]]
                self.assertEqual(stage["level"], row["progression"])
                self.assertEqual(family["productivity_ceiling"], row["productivity_ceiling"])
                self.assertEqual(recipes, row["productivity_recipes"])
                self.assertEqual(f"ips-max-level-{family['key']}", row["cap_setting"])

    def test_only_the_three_admitted_family_settings_are_visible(self):
        self.lua.globals().mods = self.active_mods()
        settings = self.lua.execute('package.loaded["research.settings"] = nil; return require("research.settings")')
        specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
        for family in self.facts["families"]:
            for prefix in ("ips-enable-", "ips-cost-base-", "ips-cost-linear-increment-", "ips-cost-growth-", "ips-max-level-", "ips-research-time-", "ips-effect-per-level-"):
                self.assertNotIn("hidden", specs[f"{prefix}{family['key']}"])
        self.assertTrue(specs["ips-enable-research_material_aluminium"]["hidden"])

    def test_data_final_hook_appends_the_exact_profile_rows_before_the_single_install(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        lua.globals().mods = _lua_value(lua, self.facts["required_mods"])
        lua.globals().fixture_raw = _lua_value(lua, _plain(self.raw_fixture()))
        fixture_values = _plain(self.values())
        fixture_values["options"] = {}
        lua.globals().fixture_values = _lua_value(lua, fixture_values)
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          data = {raw=fixture_raw}
          settings, helpers, log = {startup={}}, {}, function() end
          package.preload["research.settings"] = function()
            return {resolve=function() return fixture_values end, default_value=function() return nil end}
          end
          package.preload["research.productivity"] = function()
            return {gears=function() return {type="technology", name="fixture-gears", unit={time=1, ingredients={{"automation-science-pack", 1}}}} end}
          end
          package.preload["research.generator"] = function()
            return {install=function(rows, stage) stage.installed = rows end}
          end
          package.preload["compatibility.modern_catalogue"] = function()
            return {is_k2_base=function() return false end, is_k2so=function() return false end,
              select=function() return {bob_angel=false, definitions={}, continuations={}} end}
          end
          package.preload["research.modern"] = function()
            return {preflight_recipe_patches=function() end, preflight_native_owner_patches=function() return {} end,
              technologies=function() return {} end, apply_weapon_speed_overlap=function() end,
              apply_native_owner_patches=function() end, apply_recipe_patches=function() end}
          end
          package.preload["research.product_target_extension"] = function() return {extend=function() end} end
          package.preload["research.science"] = function() return {apply_family=function() end} end
          package.preload["research.native_credit_definitions"] = function() return {append=function() end} end
          require("data-final-fixes")
        ''')
        installed = _plain(lua.globals().data["installed"])
        emitted = {row["name"] for row in installed}
        expected = {
            "recipe-prod-research_material_tin-1",
            "recipe-prod-research_material_gunmetal-1",
            "recipe-prod-research_material_gunmetal-4",
            "recipe-prod-research_material_invar-1",
            "recipe-prod-research_material_invar-4",
        }
        self.assertTrue(expected <= emitted)
        self.assertNotIn("recipe-prod-research_material_tin-4", emitted)


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobTechMaterialTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

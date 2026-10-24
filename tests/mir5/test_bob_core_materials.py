"""Pure F210 Bob Core material controls from an independent no-Angel capture."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
FACTS_PATH = ROOT / "tests/mir5/fixtures/bob-core-f210-captured-facts.json"


def _canonical_lf_sha256(path: Path) -> str:
    # This selected profile is governed by .gitattributes as text eol=lf.
    # Hash its canonical Git content so a Windows CRLF working copy and a
    # hosted LF checkout bind the same portable input; reject bare CR bytes
    # instead of accepting an ungoverned line-ending transformation.
    raw = path.read_bytes()
    canonical = raw.replace(b"\r\n", b"\n")
    if b"\r" in canonical:
        raise AssertionError(f"profile has non-Git line endings: {path}")
    return hashlib.sha256(canonical).hexdigest().upper()


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


class BobCoreMaterialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        cls.profile = ROOT / cls.facts["profile"]
        if _canonical_lf_sha256(cls.profile) != cls.facts["profile_sha256"]:
            raise AssertionError(f"hash-locked F210 Bob Core profile changed: {cls.profile}")
        reference = cls.facts["independent_reference"]
        if reference["candidate_output_used"] or reference["release_qualification"]:
            raise AssertionError("Bob Core source facts must remain independent, non-qualification evidence")
        run = reference["native_run"]
        if run["id"] != 40069301778 or run["artifact_id"] != 12550447321 or run["members_verified"] != 26:
            raise AssertionError("Bob Core facts must retain the verified independent capture chain")
        if cls.facts["totals"] != {"families": 7, "technology_rows": 14, "withheld_families": 9}:
            raise AssertionError("Bob Core facts must retain all seven captured families and fourteen rows")

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
        self.catalogue = self.lua.execute('return require("compatibility.bob_core_materials")')
        self.generator = self.lua.execute('return require("research.generator")')

    def active_mods(self):
        return _lua_value(self.lua, self.facts["required_mods"])

    def values(self):
        streams = {family["key"]: deepcopy(self.facts["defaults"]) for family in self.facts["families"]}
        return _lua_value(self.lua, {"streams": streams})

    def raw_fixture(self):
        raw = {"item": {}, "recipe": {}, "technology": {}, "lab": {}}
        science = set()
        for family in self.facts["families"]:
            raw["item"][family["item"]] = {"icon": family["icon"], "icon_size": family["icon_size"]}
            for route in family["routes"]:
                recipe = {
                    "allow_productivity": True,
                    "ingredients": deepcopy(route["ingredients"]),
                    "results": deepcopy(route["results"]),
                }
                if "enabled" in route:
                    recipe["enabled"] = route["enabled"]
                raw["recipe"][route["recipe"]] = recipe
                if "owner" in route:
                    owner = raw["technology"].setdefault(route["owner"], {"effects": []})
                    owner.setdefault("effects", []).append({
                        "type": "unlock-recipe", "recipe": route["recipe"],
                    })
            for stage_name in ("early", "continuation"):
                stage = family[stage_name]
                science.update(stage["science"])
                for prerequisite in stage["prerequisites"]:
                    if prerequisite != family["early"]["id"]:
                        raw["technology"].setdefault(prerequisite, {})
        for name in science:
            raw["item"].setdefault(name, {})
        raw["lab"]["lab"] = {"inputs": sorted(science)}
        return _lua_value(self.lua, raw)

    def rows(self, values=None, raw=None, active_mods=None):
        return self.catalogue["technologies"](
            values or self.values(), raw or self.raw_fixture(), active_mods or self.active_mods()
        )

    def expected_ids(self):
        return [stage["id"] for family in self.facts["families"]
                for stage in (family["early"], family["continuation"])]

    def test_complete_independent_catalogue_matches_all_fourteen_rows_and_named_routes(self):
        rows = _plain(self.rows())
        self.assertEqual(self.expected_ids(), [row["name"] for row in rows])
        self.assertEqual(self.facts["totals"]["technology_rows"], len(rows))
        by_id = {row["name"]: row for row in rows}
        self.assertEqual(len(rows), len(by_id))

        for family in self.facts["families"]:
            expected_recipes = [route["recipe"] for route in family["routes"]]
            for stage_name in ("early", "continuation"):
                stage = family[stage_name]
                row = by_id[stage["id"]]
                self.assertEqual("technology", row["type"])
                self.assertEqual(stage["level"], row["level"])
                self.assertTrue(row["upgrade"])
                self.assertEqual(stage["max_level"], row["max_level"])
                self.assertEqual(stage["order"], row["order"])
                self.assertEqual(stage["count_formula"], row["unit"]["count_formula"])
                self.assertEqual(stage["time"], row["unit"]["time"])
                self.assertEqual(stage["prerequisites"], row["prerequisites"])
                self.assertEqual(stage["science"], [ingredient[0] for ingredient in row["unit"]["ingredients"]])
                self.assertEqual(expected_recipes, [effect["recipe"] for effect in row["effects"]])
                self.assertTrue(all(
                    effect["type"] == "change-recipe-productivity" and effect["change"] == 0.02
                    for effect in row["effects"]
                ))
                self.assertEqual(family["icon"], row["icons"][0]["icon"])
                self.assertEqual(family["icon_size"], row["icons"][0]["icon_size"])
                self.assertEqual(stage["show_levels_info"], row.get("show_levels_info"))
                self.assertEqual(stage["visible_when_disabled"], row.get("visible_when_disabled"))

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

    def test_settings_visibility_and_defaults_match_the_independent_capture(self):
        self.lua.globals().mods = self.active_mods()
        settings = self.lua.execute('package.loaded["research.settings"] = nil; return require("research.settings")')
        specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
        prefixes = ("ips-enable-", "ips-cost-base-", "ips-cost-linear-increment-", "ips-cost-growth-",
                    "ips-max-level-", "ips-research-time-", "ips-effect-per-level-")
        for family in self.facts["visible_material_streams"]:
            for prefix in prefixes:
                self.assertNotIn("hidden", specs[f"{prefix}{family}"])
        for family in self.facts["families"]:
            defaults = self.facts["defaults"]
            self.assertEqual(defaults["enabled"], specs[f"ips-enable-{family['key']}"]["default_value"])
            self.assertEqual(defaults["base_cost"], specs[f"ips-cost-base-{family['key']}"]["default_value"])
            self.assertEqual(defaults["linear_increment"], specs[f"ips-cost-linear-increment-{family['key']}"]["default_value"])
            self.assertEqual(defaults["growth_factor"], specs[f"ips-cost-growth-{family['key']}"]["default_value"])
            self.assertEqual(defaults["max_level"], specs[f"ips-max-level-{family['key']}"]["default_value"])
            self.assertEqual(defaults["research_time"], specs[f"ips-research-time-{family['key']}"]["default_value"])
            self.assertEqual(defaults["effect_percent"], specs[f"ips-effect-per-level-{family['key']}"]["default_value"])

    def test_tuning_is_bounded_and_preserves_the_captured_stage_boundary(self):
        values = self.values()
        lead = values["streams"]["research_material_lead"]
        lead["base_cost"], lead["linear_increment"], lead["growth_factor"] = 250, 3, 2
        lead["research_time"], lead["effect_percent"] = 45, 3
        values["streams"]["research_material_tin"]["enabled"] = False
        rows = {row["name"]: row for row in _plain(self.rows(values=values))}
        self.assertEqual("(250+3*(L-1))*2^(L-1)", rows["recipe-prod-research_material_lead-1"]["unit"]["count_formula"])
        self.assertEqual("2072+250*(L-4)", rows["recipe-prod-research_material_lead-4"]["unit"]["count_formula"])
        self.assertEqual(45, rows["recipe-prod-research_material_lead-1"]["unit"]["time"])
        self.assertEqual(0.03, rows["recipe-prod-research_material_lead-4"]["effects"][0]["change"])
        self.assertFalse(rows["recipe-prod-research_material_tin-1"]["enabled"])
        self.assertEqual(3, rows["recipe-prod-research_material_lead-1"]["max_level"])
        self.assertEqual("infinite", rows["recipe-prod-research_material_lead-4"]["max_level"])

    def test_named_preflight_rejects_safety_drift_without_scanning_raw_tables(self):
        poison = self.lua.eval('function(value) return setmetatable(value, {__pairs=function() error("global scan") end}) end')
        raw = self.raw_fixture()
        raw["recipe"] = poison(raw["recipe"])
        raw["technology"] = poison(raw["technology"])
        self.assertEqual(14, len(self.rows(raw=raw)))

        explicit_default = self.raw_fixture()
        explicit_default["recipe"]["bob-tin-plate"]["enabled"] = True
        explicit_default["recipe"]["bob-lead-plate"]["enabled"] = True
        explicit_default["recipe"]["bob-nitinol-alloy"]["maximum_productivity"] = 3
        self.assertEqual(_plain(self.rows()), _plain(self.rows(raw=explicit_default)))

        wrong_icon = self.raw_fixture()
        wrong_icon["item"]["bob-lead-plate"]["icon"] = "wrong"
        with self.assertRaisesRegex(Exception, "bob-lead-plate presentation changed"):
            self.rows(raw=wrong_icon)
        disabled = self.raw_fixture()
        disabled["recipe"]["bob-lead-plate"]["enabled"] = False
        with self.assertRaisesRegex(Exception, "bob-lead-plate changed"):
            self.rows(raw=disabled)
        pre_enabled = self.raw_fixture()
        pre_enabled["recipe"]["bob-bronze-alloy"]["enabled"] = True
        with self.assertRaisesRegex(Exception, "bob-bronze-alloy changed"):
            self.rows(raw=pre_enabled)
        missing_owner = self.raw_fixture()
        missing_owner["technology"]["bob-alloy-processing"] = None
        with self.assertRaisesRegex(Exception, "bob-alloy-processing no longer owns bob-bronze-alloy"):
            self.rows(raw=missing_owner)
        wrong_unlock = self.raw_fixture()
        wrong_unlock["technology"]["bob-zinc-processing"]["effects"][1]["type"] = "change-recipe-productivity"
        with self.assertRaisesRegex(Exception, "bob-zinc-processing no longer owns bob-gunmetal-alloy"):
            self.rows(raw=wrong_unlock)
        duplicate_unlock = self.raw_fixture()
        duplicate_unlock["technology"]["bob-invar-processing"]["effects"][2] = {
            "type": "unlock-recipe", "recipe": "bob-invar-alloy",
        }
        with self.assertRaisesRegex(Exception, "bob-invar-processing no longer owns bob-invar-alloy"):
            self.rows(raw=duplicate_unlock)
        wrong_route = self.raw_fixture()
        wrong_route["recipe"]["bob-copper-tungsten-alloy"]["ingredients"][2]["type"] = "item"
        with self.assertRaisesRegex(Exception, "bob-copper-tungsten-alloy changed"):
            self.rows(raw=wrong_route)
        capped = self.raw_fixture()
        capped["recipe"]["bob-nitinol-alloy"]["maximum_productivity"] = 4
        with self.assertRaisesRegex(Exception, "bob-nitinol-alloy changed"):
            self.rows(raw=capped)
        missing = self.raw_fixture()
        missing["technology"]["chemical-science-pack"] = None
        with self.assertRaisesRegex(Exception, "recipe-prod-research_material_lead-1 has missing prerequisite chemical-science-pack"):
            self.rows(raw=missing)

    def test_profile_is_no_angel_only_and_outputs_are_detached(self):
        baseline = _plain(self.rows())
        changed = dict(self.facts["required_mods"])
        changed["bobtech"] = "newer"
        self.assertEqual(baseline, _plain(self.rows(active_mods=_lua_value(self.lua, changed))))
        partial = dict(self.facts["required_mods"])
        del partial["bobtech"]
        self.assertEqual(0, len(self.rows(active_mods=_lua_value(self.lua, partial))))
        angel = dict(self.facts["required_mods"])
        angel["angelssmelting"] = "present"
        self.assertEqual(0, len(self.rows(active_mods=_lua_value(self.lua, angel))))
        for name in ("Krastorio2", "pycoalprocessing"):
            incompatible = dict(self.facts["required_mods"])
            incompatible[name] = "present"
            with self.assertRaisesRegex(Exception, "unsupported F210 Bob Core saved-profile transition"):
                self.rows(active_mods=_lua_value(self.lua, incompatible))

        first = self.rows()
        first[1]["effects"][1]["recipe"] = "corrupted"
        first[2]["prerequisites"][1] = "corrupted"
        first[3]["icons"][1]["icon"] = "corrupted"
        self.assertEqual(baseline, _plain(self.rows()))

    def test_science_catalogue_data_hook_and_library_availability_are_wired_without_force_mutation(self):
        rows, raw = self.rows(), self.raw_fixture()
        self.lua.globals().fixture_rows = rows
        self.lua.globals().fixture_raw = raw
        self.lua.globals().fixture_mods = self.active_mods()
        reports = self.lua.execute(r'''
          local science = require("research.science")
          local target = require("platform.target")
          return science.apply_family(fixture_rows, nil, {
            options={}, raw=fixture_raw, target=target, mods=fixture_mods,
          })
        ''')
        if isinstance(reports, tuple):
            reports = reports[0]
        expected = {
            stage["id"]: stage["science"]
            for family in self.facts["families"]
            for stage in (family["early"], family["continuation"])
        }
        for row in _plain(rows):
            self.assertEqual(expected[row["name"]], [ingredient[0] for ingredient in row["unit"]["ingredients"]])
        self.assertTrue(all(report["reason"] == "configured" for report in reports.values()))

        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().player_root = (ROOT / "source/mir5").as_posix()
        runtime.globals().mods = _lua_value(runtime, self.facts["required_mods"])
        runtime.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
        ''')
        declared = _plain(runtime.execute('return require("research.catalogue").declared()'))
        declared_by_id = {row["id"]: row for row in declared}
        expected_ids = self.expected_ids()
        self.assertEqual(expected_ids, [row["id"] for row in declared if row["id"] in set(expected_ids)])
        for family in self.facts["families"]:
            for stage in (family["early"], family["continuation"]):
                row = declared_by_id[stage["id"]]
                self.assertEqual(family["key"], row["family"])
                self.assertEqual(stage["level"], row["progression"])
                self.assertEqual(family["productivity_ceiling"], row["productivity_ceiling"])
                self.assertEqual([route["recipe"] for route in family["routes"]], row["productivity_recipes"])

        self.lua.globals().core_mods = self.active_mods()
        availability = self.lua.execute('return require("presentation.availability")')
        target = self.lua.eval('{id="f210", factorio_version="2.1", minimum_base="2.1.23", recipe_productivity=true}')
        empty_force = self.lua.execute(r'''
          local technologies = setmetatable({}, {
            __pairs=function() error("availability scanned force") end,
            __newindex=function() error("availability mutated force") end,
          })
          return {technologies=technologies}
        ''')
        effective = _lua_value(self.lua, {family: {"enabled": True} for family in self.facts["visible_material_streams"]})
        omitted = _plain(availability["rows"](self.lua.globals().core_mods, target, empty_force, "material", effective))
        self.assertEqual(self.facts["withheld_families"], [row["family"] for row in omitted])
        self.assertTrue(all(row["reason"] == "not-available-in-bob-core-profile" for row in omitted))
        angel_mods = dict(self.facts["required_mods"])
        angel_mods["angelssmelting"] = "present"
        self.assertEqual(0, len(availability["rows"](
            _lua_value(self.lua, angel_mods), target, empty_force, "material", effective
        )))
        effective["research_material_brass"]["enabled"] = False
        suppressed = _plain(availability["rows"](self.lua.globals().core_mods, target, empty_force, "brass", effective))
        self.assertEqual(0, len(suppressed))
        present = self.lua.execute('return {technologies={["recipe-prod-research_material_brass-1"]={valid=true}}}')
        self.assertEqual(0, len(availability["rows"](self.lua.globals().core_mods, target, present, "brass", _lua_value(self.lua, {"research_material_brass": {"enabled": True}}))))

        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        lua.globals().mods = _lua_value(lua, self.facts["required_mods"])
        lua.globals().fixture_raw = _lua_value(lua, _plain(raw))
        values = _plain(self.values())
        values["options"] = {}
        lua.globals().fixture_values = _lua_value(lua, values)
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          data = {raw=fixture_raw}
          settings, helpers, log = {startup={}}, {}, function() end
          package.preload["research.settings"] = function() return {resolve=function() return fixture_values end, default_value=function() return nil end} end
          package.preload["research.productivity"] = function() return {gears=function() return {type="technology", name="fixture-gears", unit={time=1, ingredients={{"automation-science-pack", 1}}}} end} end
          package.preload["research.generator"] = function() return {install=function(rows, stage) stage.installed = rows end} end
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
        emitted = {row["name"] for row in _plain(lua.globals().data["installed"])}
        self.assertTrue(set(self.expected_ids()) <= emitted)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobCoreMaterialTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

"""Published native field-setting intents through the real data stage; host only."""
import argparse
from copy import deepcopy
from pathlib import Path
import sys
import unittest

from historical_sources import read_published_source
import test_native_family_product_targets as data_fixture
import test_native_owner_cap_adoption as cap_fixture

ROOT = Path(__file__).resolve().parents[1]
MUTATORS = {
    "fixed-count": "15CD878E1543466DD0AC486F812357DBF44658C01DAA55A945E80A29D19FA802",
    "linear-formula": "390582877D7D1D97B3CFF51E67E89EC227FC003D01AB729B12246A9257F5FB85",
    "unrecognized-formula": "49C2A0D9C5F2EDB8BE216EA283C9C2AAC49502B67DDD37E15BFFDABE0D1C3C8B",
}


class NativeOwnerFieldTuningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data_fixture.LuaRuntime, data_fixture.LuaError = LuaRuntime, LuaError
        cap_fixture.LuaRuntime, cap_fixture.LuaError = LuaRuntime, LuaError
        data_fixture.NativeFamilyProductTargetTests.setUpClass()
        cls.mutators = {kind: read_published_source(ROOT,
            "fixtures/native-owner-" + kind + "/data-updates.lua", digest).decode()
            for kind, digest in MUTATORS.items()}
        cls.foreign_effect = read_published_source(ROOT,
            "fixtures/native-owner-settings-source/data-updates.lua",
            "0E09998994F6A65740A2EAF83D1C86381C4197E7219C6D5B3D33344034CE208D").decode()

    def case(self, cost="native", inherited_time=60, foreign=True):
        case = data_fixture.NativeFamilyProductTargetTests()
        case.setUp()
        if cost != "native":
            case.lua.execute(self.mutators[cost])
        # Apply the exact published cost mutation to every named owner, while
        # keeping each owner's authored recipes. No candidate cost parser/oracle.
        unit = data_fixture.plain(case.owner("research_processing_unit").unit)
        for family in data_fixture.OWNERS:
            owner = case.owner(family)
            owner.unit.count, owner.unit.count_formula = unit.get("count"), unit.get("count_formula")
            owner.unit.time = inherited_time
            owner.unit.ingredients = data_fixture.generator_fixture.lua_table(case.lua, [["foreign-science", 3]])
            owner.unit.foreign_field = data_fixture.generator_fixture.lua_table(case.lua, {"keep": [3, 4]})
            owner.prerequisites = data_fixture.generator_fixture.lua_table(case.lua, ["foreign-prerequisite"])
            owner.foreign_flag = "preserve"
        if foreign:
            case.lua.execute(self.foreign_effect)
        return case

    def settings(self, case, values):
        for family in data_fixture.OWNERS:
            for key, value in values.items():
                case.lua.globals().settings.startup["ips-" + key + "-" + family].value = value

    def assert_fields(self, case, before, effect=0.1, time=None):
        after = case.owner_rows()
        for family, old in before.items():
            with self.subTest(family=family):
                expected_unit = deepcopy(old["unit"])
                if time is not None:
                    expected_unit["time"] = time
                self.assertEqual(expected_unit, after[family]["unit"])
                self.assertEqual(old["prerequisites"], after[family]["prerequisites"])
                self.assertEqual("preserve", after[family]["foreign_flag"])
                self.assertEqual([effect], case.changes(family))
                for recipe in data_fixture.OWNERS[family][1]:
                    self.assertEqual([effect], case.changes(family, recipe))
        extra = [row for row in after["research_processing_unit"]["effects"] if row["type"] == "ammo-damage"]
        self.assertEqual([{"type": "ammo-damage", "ammo_category": "bullet", "modifier": .07}], extra)
        self.assertEqual(1, case.lua.globals().data.writes)

    def test_defaults_preserve_all_original_native_cost_forms(self):
        for kind in ("native", *MUTATORS):
            with self.subTest(cost=kind):
                case = self.case(kind)
                before = case.owner_rows()
                case.pipeline()
                self.assert_fields(case, before)

    def test_independent_effect_time_and_combination_preserve_all_original_cost_forms(self):
        for kind in ("native", *MUTATORS):
            for values in ({"effect-per-level": 17}, {"research-time": 31},
                           {"effect-per-level": 17, "research-time": 31}):
                with self.subTest(cost=kind, settings=values):
                    case = self.case(kind)
                    before = case.owner_rows()
                    self.settings(case, values)
                    case.pipeline()
                    self.assert_fields(case, before, effect=values.get("effect-per-level", 10) / 100,
                                       time=values.get("research-time"))

    def test_inherited_nondefault_time_survives_effect_and_zero_or_default_time_settings(self):
        for kind in MUTATORS:
            for selected_time in (None, 0, 60):
                with self.subTest(cost=kind, time=selected_time):
                    case = self.case(kind, inherited_time=45.5)
                    before = case.owner_rows()
                    values = {"effect-per-level": 17}
                    if selected_time is not None:
                        values["research-time"] = selected_time
                    self.settings(case, values)
                    case.pipeline()
                    self.assert_fields(case, before, effect=.17)

    def test_explicit_time_replaces_the_inherited_time_and_keeps_detached_fields(self):
        case = self.case("unrecognized-formula", inherited_time=45.5)
        before = case.owner_rows()
        self.settings(case, {"research-time": 31})
        case.lua.execute('''
          held_unit=data.raw.technology["processing-unit-productivity"].unit
        ''')
        case.pipeline()
        self.assert_fields(case, before, time=31)
        self.assertEqual(before["research_processing_unit"]["unit"], data_fixture.plain(case.lua.globals().held_unit))
        case.owner("research_processing_unit").unit.foreign_field.keep[1] = 99
        self.assertEqual(3, case.lua.globals().held_unit.foreign_field.keep[1])

    def test_effect_only_keeps_the_original_unit_table(self):
        case = self.case("fixed-count")
        self.settings(case, {"effect-per-level": 17})
        case.lua.execute('held_unit=data.raw.technology["processing-unit-productivity"].unit')
        case.pipeline()
        self.assertTrue(case.lua.eval('held_unit==data.raw.technology["processing-unit-productivity"].unit'))

    def test_disabled_family_ignores_stale_nondefault_field_settings(self):
        case = self.case("unrecognized-formula", inherited_time=45.5)
        before = case.owner_rows()
        self.settings(case, {"enable": False, "effect-per-level": 17, "research-time": 31})
        case.pipeline()
        self.assertEqual(before, case.owner_rows())

    def test_malformed_inherited_cost_and_time_refuse_before_any_publication_or_patch(self):
        # A late named owner fails after earlier detached plans were built.
        # The guard must preserve all-before-write, rather than skip a bad row.
        for change in ('unit.count=0;unit.count_formula=nil',
                       'unit.count=-1;unit.count_formula=nil',
                       'unit.count=1.5;unit.count_formula=nil',
                       'unit.count=math.huge;unit.count_formula=nil',
                       'unit.count=0/0;unit.count_formula=nil',
                       'unit.count=1000;unit.count_formula="L"',
                       'unit.count=nil;unit.count_formula=nil',
                       'unit.count=nil;unit.count_formula=""',
                       'unit.count=nil;unit.count_formula="  "',
                       'unit.time=math.huge', 'unit.time=0/0', 'unit.time=-1'):
            with self.subTest(mutation=change):
                case = self.case()
                self.settings(case, {"effect-per-level": 17, "research-time": 31})
                case.lua.execute('local unit=data.raw.technology["steel-plate-productivity"].unit;' + change)
                case.lua.execute('''
                  held_units={};held_effects={}
                  for name,row in pairs(data.raw.technology) do
                    held_units[name]=row.unit;held_effects[name]=row.effects
                  end
                ''')
                with self.assertRaisesRegex(LuaError, "native-owner preflight"):
                    case.pipeline()
                self.assertEqual(0, case.lua.globals().data.writes)
                self.assertTrue(case.lua.execute('''
                  for name,row in pairs(data.raw.technology) do
                    if row.unit~=held_units[name] or row.effects~=held_effects[name] then return false end
                  end
                  return true
                '''))
                self.assertEqual([.1], case.changes("research_low_density_structure", "low-density-structure"))

    def test_original_cost_forms_keep_actual_data_to_control_cap_and_restore_boundary(self):
        # Unit fields are not runtime ownership evidence; the exact effect and
        # private admitted-recipe guards still decide caps/restoration.
        for kind in MUTATORS:
            with self.subTest(cost=kind):
                case = self.case(kind, foreign=False)
                self.settings(case, {"research-time": 31})
                case.pipeline()
                metadata = data_fixture.plain(case.lua.globals().data.raw["mod-data"][cap_fixture.MOD_DATA].data)
                harness = cap_fixture.NativeOwnerCapAdoptionTests()
                lua = harness.runtime(case.owner_rows(), metadata,
                                      emitted_mir_rows=harness.emitted_mir_technologies(case))
                harness.boot(lua, 2)
                lua.globals().handlers.init()
                retained = data_fixture.plain(lua.globals().storage)
                for name, _ in data_fixture.OWNERS.values():
                    self.assertFalse(lua.globals().world.technologies[name].enabled)
                harness.boot(lua, 0, storage=data_fixture.generator_fixture.lua_table(lua, retained))
                lua.globals().handlers.configuration(data_fixture.generator_fixture.lua_table(lua, {
                    "mod_startup_settings_changed": True, "mod_changes": {}}))
                for name, _ in data_fixture.OWNERS.values():
                    self.assertTrue(lua.globals().world.technologies[name].enabled)
                    self.assertEqual(3, lua.globals().world.technologies[name].level)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeOwnerFieldTuningTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Real data-to-control cap boundary for admitted native recipes; host only."""
import argparse
from copy import deepcopy
import json
import re
from pathlib import Path
import sys
import unittest

import test_lifecycle as lifecycle_fixture
import test_native_family_product_targets as data_fixture

ROOT = Path(__file__).resolve().parents[1]
MOD_DATA = "more-infinite-research-native-adoptions"
MODS = {"base": "2.1.23", "space-age": "2.1.23"}


class NativeOwnerCapAdoptionTests(unittest.TestCase):
    @staticmethod
    def emitted_mir_technologies(case):
        return {row["name"]: row for row in data_fixture.plain(case.lua.globals().data.emitted)
                if row["type"] == "technology"}

    @classmethod
    def setUpClass(cls):
        data_fixture.LuaRuntime, data_fixture.LuaError = LuaRuntime, LuaError
        data_fixture.NativeFamilyProductTargetTests.setUpClass()

    def stage(self, *, configured_effect=None, inherited_effect=None, existing_alternate=None):
        case = data_fixture.NativeFamilyProductTargetTests()
        case.setUp()
        before = case.owner_rows()
        for family in data_fixture.OWNERS:
            if existing_alternate is not None:
                effects = case.owner(family).effects
                effects[len(effects) + 1] = data_fixture.generator_fixture.lua_table(case.lua, {
                    "type": "change-recipe-productivity", "recipe": data_fixture.RECIPES[family],
                    "change": existing_alternate})
            if inherited_effect is not None:
                for effect in case.owner(family).effects.values(): effect.change = inherited_effect
            if configured_effect is not None:
                case.lua.globals().settings.startup["ips-effect-per-level-" + family].value = configured_effect
        case.pipeline()
        # Runtime consumes the same MIR-created paid mains and signed holders
        # emitted by the real preceding stage, not only the foreign owners.
        self.emitted_mir_rows = self.emitted_mir_technologies(case)
        group = case.lua.globals().data.raw["mod-data"]
        record = group[MOD_DATA] if group is not None else None
        metadata = data_fixture.plain(record.data) if record is not None else {"schema": 1, "owners": {}}
        return before, case.owner_rows(), metadata

    def runtime(self, owners, metadata, *, enabled=True, emitted_mir_rows=None):
        lifecycle_fixture.LuaRuntime = LuaRuntime
        harness = lifecycle_fixture.LifecycleTests()
        harness.setUp()
        lua = harness.lua
        technologies = lua.table()
        for family, row in owners.items():
            name = data_fixture.OWNERS[family][0]
            technology = lua.globals().technology(name, 3, enabled)
            technology.prototype = data_fixture.generator_fixture.lua_table(lua, {
                "effects": row["effects"], "max_level": 4294967295, "enabled": True})
            technologies[name] = technology
        emitted = self.emitted_mir_rows if emitted_mir_rows is None else emitted_mir_rows
        for name, row in emitted.items():
            self.assertIsNone(technologies[name], "MIR transport collided with a foreign owner")
            prototype = deepcopy(row)
            # Native initial level comes from the numeric name suffix; an
            # omitted authored `level` never turns head4 into runtime level1.
            suffix = re.search(r"-(\d+)$", name)
            prototype.setdefault("level", int(suffix.group(1)) if suffix else 1)
            prototype.setdefault("enabled", True)
            prototype.setdefault("hidden", False)
            prototype.setdefault("visible_when_disabled", False)
            if prototype.get("max_level") == "infinite": prototype["max_level"] = 4294967295
            technology = lua.globals().technology(name, prototype["level"], prototype.get("enabled", True))
            technology.prototype = data_fixture.generator_fixture.lua_table(lua, prototype)
            # Transport the actual runtime API shape. A data-stage omitted
            # enabled default is exposed as true, unit.time is in ticks, and
            # native research ingredients use named fields rather than pairs.
            # Freshly constructed native rows expose zero saved research work.
            technology.saved_progress = 0
            unit = prototype.get("unit", {})
            if "count" in unit:
                technology.research_unit_count = unit["count"]
            elif unit.get("count_formula") == "1":
                technology.research_unit_count = 1
            elif name in ("worker-robots-storage-4", "mir-worker-storage-default-4", "mir-worker-storage-preservation-4"):
                self.assertEqual("675*1.5^(L-4)", unit.get("count_formula"))
                technology.research_unit_count = 675
            technology.research_unit_energy = unit["time"] * 60
            technology.research_unit_ingredients = data_fixture.generator_fixture.lua_table(lua, [
                {"name": ingredient[0], "amount": ingredient[1]}
                for ingredient in unit["ingredients"]])
            prototype["research_unit_count_formula"] = unit.get("count_formula")
            prototype["research_unit_count"] = unit.get("count")
            prototype["research_unit_energy"] = unit["time"] * 60
            prototype["research_unit_ingredients"] = [
                {"name": ingredient[0], "amount": ingredient[1]} for ingredient in unit["ingredients"]]
            prototype["ignore_tech_cost_multiplier"] = prototype.get("ignore_tech_cost_multiplier", False)
            prototype["prerequisites"] = {prerequisite: {"name": prerequisite}
                                           for prerequisite in prototype.get("prerequisites", [])}
            for effect in prototype["effects"]:
                effect.setdefault("hidden", False)
            technology.prototype = data_fixture.generator_fixture.lua_table(lua, prototype)
            technologies[name] = technology
        lua.globals().mir_created = data_fixture.generator_fixture.lua_table(lua, {
            name: True for name in emitted})
        lua.execute('''
          function native_history(kind,name)
            assert(kind=="technology" and mir_created[name],"unexpected creation-history query")
            return {created="more-infinite-research"}
          end
        ''')
        lua.globals().world = lua.globals().force(41, technologies, lua.table(), None, 0)
        lua.globals().world.foreign_state = "preserve"
        # This host force has no paid worker levels (Base rows are absent).
        # The empty native transfer must retain its literal zero contribution.
        lua.globals().world.worker_robots_storage_bonus = 0
        lua.globals().active_mods = data_fixture.generator_fixture.lua_table(lua, MODS)
        lua.execute('active_mods["more-infinite-research"]=require("platform.target").distribution_version')
        native_prototypes = lua.table()
        for name, technology in technologies.items():
            native_prototypes[name] = technology.prototype
        lua.globals().emitted_native_prototypes = native_prototypes
        lua.globals().native_data = data_fixture.generator_fixture.lua_table(lua, {MOD_DATA: {"data": metadata}})
        return lua

    def boot(self, lua, cap, *, configured_effect=None, storage=None):
        extra = {"ips-max-level-" + family: cap for family in data_fixture.OWNERS}
        if configured_effect is not None:
            extra.update({"ips-effect-per-level-" + family: configured_effect for family in data_fixture.OWNERS})
        lua.globals().extra_settings = data_fixture.generator_fixture.lua_table(lua, extra)
        lua.globals().retained_storage = storage
        lua.execute('''
          boot({[41]=world},0,"",retained_storage,nil,0,active_mods,nil,extra_settings,{},native_data,native_history,
            emitted_native_prototypes)
        ''')

    def test_paid_runtime_transport_requires_mir_creation_and_named_holders(self):
        _, owners, metadata = self.stage()
        for invalid in ("missing-history", "foreign-creator", "missing-paid-history",
                        "foreign-paid-creator", "missing-main"):
            with self.subTest(invalid=invalid):
                lua = self.runtime(owners, metadata)
                expected_refusal = "MIR native family"
                if invalid == "missing-history": lua.globals().native_history = None
                elif invalid == "foreign-creator":
                    lua.execute('native_history=function() return {created="space-age"} end')
                elif invalid in ("missing-paid-history", "foreign-paid-creator"):
                    lua.globals().invalid_paid_creator = invalid == "foreign-paid-creator"
                    lua.execute('''
                      local original=native_history
                      native_history=function(kind,name)
                        if name=="recipe-prod-research_steel-1" then
                          if invalid_paid_creator then return {created="space-age"} end
                          return nil
                        end
                        return original(kind,name)
                      end
                    ''')
                else:
                    lua.globals().world.technologies["recipe-prod-research_steel-1"] = None
                if invalid in ("missing-history", "foreign-creator"):
                    # Global loss now fails at the earlier worker split
                    # custody boundary. The paid-only opponents above still
                    # independently reach the original native-family guard.
                    expected_refusal = "MIR worker default requires its authored native owner and first-level debit"
                with self.assertRaisesRegex(LuaError, expected_refusal):
                    self.boot(lua, 2)
                    lua.globals().handlers.init()
                self.assertIsNone(lua.globals().storage.mir_native_credits)

    def test_actual_admitted_five_owners_keep_cap_two_and_owned_disable_rights(self):
        for configured, inherited in ((None, None), (20, None), (None, .23)):
            with self.subTest(configured=configured, inherited=inherited):
                _, owners, metadata = self.stage(configured_effect=configured, inherited_effect=inherited)
                lua = self.runtime(owners, metadata)
                self.boot(lua, 2, configured_effect=configured)
                lua.globals().handlers.init()
                for family, (name, _) in data_fixture.OWNERS.items():
                    self.assertFalse(lua.globals().world.technologies[name].enabled)
                    self.assertTrue(lua.globals().storage.mir_caps.owned_disabled[41][name].disabled)
                    self.assertEqual(3, lua.globals().world.technologies[name].level)
                self.assertEqual("preserve", lua.globals().world.foreign_state)

    def test_previously_proven_baseline_right_restores_after_adoption_and_cap_zero(self):
        before, after, metadata = self.stage()
        lua = self.runtime(before, {"schema": 1, "owners": {}})
        self.boot(lua, 2)
        lua.globals().handlers.init()
        retained = data_fixture.plain(lua.globals().storage)
        for family, row in after.items():
            lua.globals().world.technologies[data_fixture.OWNERS[family][0]].prototype.effects = (
                data_fixture.generator_fixture.lua_table(lua, row["effects"]))
        lua.globals().native_data = data_fixture.generator_fixture.lua_table(lua, {MOD_DATA: {"data": metadata}})
        self.boot(lua, 0, storage=data_fixture.generator_fixture.lua_table(lua, retained))
        lua.globals().handlers.configuration(data_fixture.generator_fixture.lua_table(lua, {
            "mod_startup_settings_changed": True, "mod_changes": {}}))
        for name, _ in data_fixture.OWNERS.values():
            self.assertTrue(lua.globals().world.technologies[name].enabled)
            self.assertEqual(3, lua.globals().world.technologies[name].level)
        caps = lua.globals().storage.mir_caps
        self.assertTrue(caps is None or caps.owned_disabled[41] is None)

    def test_foreign_pre_disabled_owner_never_gains_a_restore_right(self):
        _, owners, metadata = self.stage()
        lua = self.runtime(owners, metadata, enabled=False)
        self.boot(lua, 2)
        lua.globals().handlers.init()
        retained = data_fixture.plain(lua.globals().storage)
        self.boot(lua, 0, storage=data_fixture.generator_fixture.lua_table(lua, retained))
        lua.globals().handlers.configuration(data_fixture.generator_fixture.lua_table(lua, {
            "mod_startup_settings_changed": True, "mod_changes": {}}))
        for name, _ in data_fixture.OWNERS.values():
            self.assertFalse(lua.globals().world.technologies[name].enabled)

    def test_explicit_tuning_of_an_existing_matching_route_keeps_exact_cap_admission(self):
        _, owners, metadata = self.stage(configured_effect=20, existing_alternate=.33)
        for family, row in owners.items():
            matching = [effect for effect in row["effects"] if effect.get("recipe") == data_fixture.RECIPES[family]]
            self.assertEqual([.2], [effect["change"] for effect in matching])
        lua = self.runtime(owners, metadata)
        self.boot(lua, 2, configured_effect=20)
        lua.globals().handlers.init()
        for name, _ in data_fixture.OWNERS.values():
            self.assertFalse(lua.globals().world.technologies[name].enabled)
            self.assertTrue(lua.globals().storage.mir_caps.owned_disabled[41][name].disabled)

    def test_foreign_effects_and_missing_admission_are_still_refused(self):
        _, original, metadata = self.stage()
        family = "research_steel"
        name = data_fixture.OWNERS[family][0]
        for case in ("extra-recipe", "extra-benefit", "wrong-change", "duplicate", "missing-canonical", "finite", "no-metadata"):
            with self.subTest(case=case):
                owners = deepcopy(original)
                effects = owners[family]["effects"]
                if case == "extra-recipe": effects.append({"type": "change-recipe-productivity", "recipe": "foreign", "change": .1})
                if case == "extra-benefit": effects.append({"type": "ammo-damage", "ammo_category": "bullet", "modifier": .07})
                if case == "wrong-change": effects[-1]["change"] = .11
                if case == "duplicate": effects.append(deepcopy(effects[-1]))
                if case == "missing-canonical": effects.pop(0)
                lua = self.runtime(owners, metadata if case != "no-metadata" else {"schema": 1, "owners": {}})
                if case == "finite": lua.globals().world.technologies[name].prototype.max_level = 7
                self.boot(lua, 2)
                lua.globals().handlers.init()
                self.assertTrue(lua.globals().world.technologies[name].enabled)
                caps = lua.globals().storage.mir_caps
                owned = caps.owned_disabled[41] if caps is not None else None
                self.assertTrue(owned is None or owned[name] is None)

    def test_private_metadata_preflight_fails_before_any_final_publication_or_owner_write(self):
        case = data_fixture.NativeFamilyProductTargetTests()
        case.setUp()
        before = case.owner_rows()
        case.lua.globals().data.raw["mod-data"][MOD_DATA].data.owners.foreign = case.lua.table()
        with self.assertRaisesRegex(LuaError, "changed private prototype"):
            case.pipeline()
        self.assertEqual(0, case.lua.globals().data.writes)
        self.assertEqual(before, case.owner_rows())

    def test_control_metadata_is_detached_and_malformed_scope_refuses(self):
        _, owners, metadata = self.stage()
        lua = self.runtime(owners, metadata)
        self.boot(lua, 2)
        first = data_fixture.plain(lua.execute('return require("runtime.catalogue").declared()'))
        lua.execute('''
          local rows=require("runtime.catalogue").declared()
          for _,row in ipairs(rows) do
            if row.native_adoption then row.native_adoption.recipes[1]="changed" end
          end
        ''')
        self.assertEqual(first, data_fixture.plain(lua.execute('return require("runtime.catalogue").declared()')))
        for mutation in ("unknown-owner", "duplicate-recipe", "bad-change", "unknown-field"):
            with self.subTest(mutation=mutation):
                invalid = deepcopy(metadata)
                row = invalid["owners"]["steel-plate-productivity"]
                if mutation == "unknown-owner": invalid["owners"]["foreign"] = row
                if mutation == "duplicate-recipe": row["recipes"].append(row["recipes"][0])
                if mutation == "bad-change": row["effect_change"] = "0.1"
                if mutation == "unknown-field": row["foreign"] = True
                vm = self.runtime(owners, invalid)
                with self.assertRaisesRegex(LuaError, "MIR native adoption data"):
                    self.boot(vm, 2)

    def test_named_galore_retirement_is_validated_without_changing_read_return_shape(self):
        _, owners, metadata = self.stage()
        metadata["galore_sulfur_retired"] = True
        lua = self.runtime(owners, metadata)
        self.boot(lua,2)
        self.assertIs(True,lua.execute('return require("runtime.catalogue").galore_sulfur_retired()'))
        lua.execute('''
          local facts={}
          local payload=prototypes.mod_data["more-infinite-research-native-adoptions"].data
          local definitions=require("compatibility.modern_catalogue").native_owners(script.active_mods)
          assert(select("#",require("research.native_adoption").read(payload,definitions,facts))==3)
          assert(facts.galore_sulfur_retired==true)
        ''')
        for invalid in ("true", 1, {}):
            with self.subTest(invalid=invalid):
                malformed=deepcopy(metadata)
                malformed["galore_sulfur_retired"]=invalid
                vm=self.runtime(owners,malformed)
                with self.assertRaisesRegex(LuaError,"MIR native adoption data"):
                    self.boot(vm,2)

    def test_selected_effect_setting_must_match_the_data_stage_selection(self):
        _, owners, metadata = self.stage(configured_effect=20)
        lua = self.runtime(owners, metadata)
        self.boot(lua, 2, configured_effect=17)
        lua.globals().handlers.init()
        for name, _ in data_fixture.OWNERS.values():
            self.assertTrue(lua.globals().world.technologies[name].enabled)
        self.assertIsNone(lua.globals().storage.mir_caps)

    def test_cold_control_load_preserves_the_saved_restore_right_without_writes(self):
        _, owners, metadata = self.stage()
        lua = self.runtime(owners, metadata)
        self.boot(lua, 2)
        lua.globals().handlers.init()
        retained = data_fixture.plain(lua.globals().storage)
        self.boot(lua, 2, storage=data_fixture.generator_fixture.lua_table(lua, retained))
        lua.globals().handlers.load()
        self.assertEqual(retained, data_fixture.plain(lua.globals().storage))
        for name, _ in data_fixture.OWNERS.values():
            self.assertFalse(lua.globals().world.technologies[name].enabled)

    def test_earlier_base_data_and_control_do_not_import_the_inactive_bridge(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        target = json.loads((ROOT / "targets/editions.json").read_text())["targets"]["f110"]
        lua.globals().selected_target = data_fixture.generator_fixture.lua_table(lua, {**target, "id": "f110"})
        lua.execute('''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          package.loaded["platform.target"]=selected_target
          package.preload["research.native_adoption"]=function() error("inactive bridge imported") end
          mods={base=selected_target.minimum_base};script={active_mods=mods};settings={startup={}};log=function() end
          data={extend=function(_,rows) assert(#rows==1 and rows[1].type=="shortcut") end}
          dofile(player_root.."/data.lua")
          assert(#require("runtime.catalogue").declared()>0)
        ''')

    def test_modern_base_paid_transport_grants_no_native_owner_adoption(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        lua.execute('''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          package.preload["research.generator"]=function() error("runtime imported Generator") end
          mods={base="2.1.23"};script={active_mods=mods};settings={startup={}};log=function() end
          local record
          data={extend=function(_,rows)
            assert(#rows==2 and rows[1].type=="shortcut" and rows[2].type=="mod-data")
            record=rows[2]
          end}
          dofile(player_root.."/data.lua")
          assert(record.name=="more-infinite-research-native-adoptions" and record.data.schema==1)
          assert(next(record.data.owners)==nil and next(record.data.withheld)==nil and next(record.data.credits)==nil)
          prototypes={mod_data={[record.name]=record}}
          local catalogue=require("runtime.catalogue")
          assert(#catalogue.declared()>0 and next(catalogue.native_credit_groups())==nil)
          for _,row in ipairs(catalogue.declared()) do assert(row.ownership_kind~="nativeowner") end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeOwnerCapAdoptionTests))
    sys.exit(0 if result.wasSuccessful() else 1)

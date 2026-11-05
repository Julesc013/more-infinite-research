"""Opposing host controls for the disposable Bob paid-state transition.

No Factorio execution or saved-state acceptance follows from these controls.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/bob-material-preservation"
FAMILIES = ("tin", "lead", "bronze", "gunmetal", "invar", "nitinol", "copper_tungsten")
RECIPES = ("bob-tin-plate", "bob-lead-plate", "bob-bronze-alloy", "bob-gunmetal-alloy",
           "bob-invar-alloy", "bob-nitinol-alloy", "bob-copper-tungsten-alloy")


def source_snapshot():
    return dict(current="bronze-tail", queue=["bronze-tail", "bronze-tail", "automation"],
                progress=0.42, lead_saved=0.27,
                technologies={f"paid-{key}": dict(level=5, researched=False, enabled=True)
                              for key in FAMILIES},
                bonuses={name: 0.08 for name in RECIPES})


class PreservationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.control = self.lua.execute((FIXTURE / "fixture_control.lua").read_text(encoding="utf-8"))
        self.data_module = self.lua.execute((FIXTURE / "fixture_data.lua").read_text(encoding="utf-8"))

    def table(self, value):
        return self.lua.table_from(value, recursive=True)

    def check(self, actual, expected, exact=False):
        self.control.assert_preserved(self.table(actual), self.table(expected), "opponent", exact)

    def test_retained_source_and_only_policy_enablement_change_are_accepted(self):
        expected = source_snapshot()
        self.check(expected, expected, True)
        changed = deepcopy(expected)
        changed["technologies"]["paid-tin"]["enabled"] = False
        self.check(changed, expected)
        with self.assertRaisesRegex(Exception, "enablement changed"):
            self.check(changed, expected, True)

    def test_each_lost_recipe_bonus_is_rejected(self):
        expected = source_snapshot()
        for name in RECIPES:
            with self.subTest(recipe=name):
                actual = deepcopy(expected)
                actual["bonuses"][name] = 0
                with self.assertRaisesRegex(Exception, "earned recipe effect changed"):
                    self.check(actual, expected)

    def test_each_paid_identity_reset_or_deletion_is_rejected(self):
        expected = source_snapshot()
        for key in expected["technologies"]:
            for mode in ("level", "researched", "missing"):
                with self.subTest(identity=key, mode=mode):
                    actual = deepcopy(expected)
                    if mode == "missing":
                        del actual["technologies"][key]
                    else:
                        actual["technologies"][key][mode] = 1 if mode == "level" else True
                    with self.assertRaisesRegex(Exception, "paid native level changed"):
                        self.check(actual, expected)

    def test_current_progress_detached_work_and_queue_corruption_are_rejected(self):
        expected = source_snapshot()
        for field, value in (("progress", 0), ("lead_saved", 0), ("current", False),
                             ("queue", ["bronze-tail", "automation"]),
                             ("queue", ["bronze-tail", "automation", "bronze-tail"])):
            with self.subTest(field=field, value=value):
                actual = deepcopy(expected)
                actual[field] = value
                with self.assertRaisesRegex(Exception, "work changed|queue order changed"):
                    self.check(actual, expected)

    def test_progress_failure_reports_force_and_prototype_flags_at_failure_time(self):
        expected = source_snapshot()
        expected["current"] = "paid-bronze"
        actual = deepcopy(expected)
        actual["progress"] = 0.43
        actual["technologies"]["paid-bronze"].update(enabled=False, prototype_enabled=False)
        with self.assertRaisesRegex(Exception, "force_enabled=false prototype_enabled=false"):
            self.check(actual, expected)

    def raw(self, stage):
        technologies = {}
        for key, recipe in zip(FAMILIES, RECIPES):
            for suffix in ("1", "4"):
                disabled = stage != "source" and key != "lead" and not (stage == "readmitted" and key == "tin")
                technologies[f"recipe-prod-research_material_{key}-{suffix}"] = dict(
                    enabled=not disabled, effects=[dict(type="change-recipe-productivity", recipe=recipe, change=0.02)],
                    unit=dict(count_formula="independent-before", time=30,
                              ingredients=[["automation-science-pack", 1]]))
        return {"technology": technologies, "int-setting": {
            "ips-max-level-research_material_tin": dict(default_value=0)}}

    def test_all_three_data_stages_keep_effects_and_apply_only_timing_and_cap(self):
        for stage, cap in (("source", 4), ("unavailable", 7), ("readmitted", 7)):
            with self.subTest(stage=stage):
                raw = self.raw(stage)
                before = deepcopy(raw)
                data = self.table(dict(raw=raw))
                self.lua.globals().data = data
                self.data_module.settings(stage)
                self.data_module.accelerate(stage)
                self.assertEqual(data.raw["int-setting"]["ips-max-level-research_material_tin"].default_value, cap)
                for name, expected in before["technology"].items():
                    actual = data.raw.technology[name]
                    self.assertEqual(actual.effects[1].recipe, expected["effects"][0]["recipe"])
                    self.assertEqual(actual.effects[1].change, 0.02)
                    if name in ("recipe-prod-research_material_tin-4", "recipe-prod-research_material_bronze-4"):
                        self.assertEqual(actual.unit.count, 100)
                        self.assertIsNone(actual.unit.count_formula)
                    else:
                        self.assertEqual(actual.unit.count_formula, "independent-before")

    def test_wrong_effect_or_admission_never_gets_accelerated_into_a_pass(self):
        for field, value in (("change", 0.01), ("recipe", "wrong-recipe"), ("type", "nothing")):
            raw = self.raw("unavailable")
            raw["technology"]["recipe-prod-research_material_tin-4"]["effects"][0][field] = value
            self.lua.globals().data = self.table(dict(raw=raw))
            with self.subTest(field=field), self.assertRaisesRegex(Exception, "identity/effect differs"):
                self.data_module.accelerate("unavailable")
        raw = self.raw("unavailable")
        raw["technology"]["recipe-prod-research_material_bronze-4"]["enabled"] = True
        self.lua.globals().data = self.table(dict(raw=raw))
        with self.assertRaisesRegex(Exception, "returning route was admitted"):
            self.data_module.accelerate("unavailable")

    def test_wrappers_pin_real_predecessor_and_distinct_successor_stages(self):
        for stage, version, mir in (("source", "0.1.0", "5.0.21005"),
                                    ("unavailable", "0.2.0", "5.0.21006"),
                                    ("readmitted", "0.3.0", "5.0.21006")):
            info = json.loads((FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
            self.assertEqual(info["version"], version)
            self.assertIn("more-infinite-research = " + mir, info["dependencies"])
            for name in ("control.lua", "data.lua", "data-final-fixes.lua", "settings-updates.lua"):
                body = (FIXTURE / stage / name).read_text(encoding="utf-8")
                self.lua.execute("assert(load(...))", body)
                self.assertIn('("' + stage + '")', body)

    def test_lab_uses_writable_script_disablement_with_read_only_active(self):
        entity = self.lua.execute('''
            local state = {disabled_by_script=false, energy=0}
            return setmetatable({}, {
              __index=function(_, key)
                if key=="active" then return not state.disabled_by_script end
                return state[key]
              end,
              __newindex=function(_, key, value)
                if key~="disabled_by_script" and key~="energy" then error("read only native attribute") end
                state[key]=value
              end})
        ''')
        for running in (False, True, False):
            self.control.set_lab_running(entity, running)
            self.assertEqual(entity.active, running)
            self.assertEqual(entity.energy, 1000000000 if running else 0)

    def test_source_setup_uses_native_shaped_2123_objects_without_removed_force_methods(self):
        prepare = self.lua.execute('''return function(module, mods)
          local TIN="recipe-prod-research_material_tin-4"
          local LEAD="recipe-prod-research_material_lead-4"
          local BRONZE="recipe-prod-research_material_bronze-4"
          local keys={"tin","lead","bronze","gunmetal","invar","nitinol","copper_tungsten"}
          local recipes={"bob-tin-plate","bob-lead-plate","bob-bronze-alloy","bob-gunmetal-alloy",
            "bob-invar-alloy","bob-nitinol-alloy","bob-copper-tungsten-alloy"}
          local function strict(values, label)
            return setmetatable(values,{__index=function(_,key) error(label.." has no native member "..key) end})
          end
          local function force(paid)
            local technologies={automation={name="automation",valid=true,researched=false},
              ["automation-science-pack"]={name="automation-science-pack",valid=true,researched=false}}
            local rs={}
            for i,key in ipairs(keys) do
              for _,suffix in ipairs{"1","4"} do
                local name="recipe-prod-research_material_"..key.."-"..suffix
                technologies[name]={name=name,valid=true,level=paid and 5 or 4,researched=false,
                  saved_progress=0,enabled=name~=TIN}
              end
              rs[recipes[i]]={productivity_bonus=paid and 0.08 or 0}
            end
            local f
            f=strict({technologies=technologies,recipes=rs,index=paid and 1 or 2,
              get_spawn_position=function() return {0,0} end,
              add_research=function(id) f.current_research=technologies[id];return true end},"LuaForce")
            return f
          end
          local inventory={clear=function() end,insert=function(stack)return stack.count end}
          local function entity()
            local state={valid=true,disabled_by_script=false,energy=0,get_inventory=function()return inventory end}
            return setmetatable({}, {__index=function(_,key)
              if key=="active" then return not state.disabled_by_script end
              if state[key]==nil then error("LuaEntity has no native member "..key) end
              return state[key] end,
              __newindex=function(_,key,value)
                if key~="disabled_by_script" and key~="energy" then error("read only native attribute") end
                state[key]=value end})
          end
          local player,foreign=force(true),force(false)
          local old_lab,new_lab=entity(),entity()
          storage={}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}
          local callbacks={}
          script={active_mods=mods,on_init=function(f)callbacks.init=f end,
            on_configuration_changed=function(f)callbacks.config=f end,
            on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks[e]=f end}
          settings={startup={["ips-max-level-research_material_tin"]={value=4},
            ["mir-settings-profile-import"]={value=""}}}
          game={tick=7453,forces={player=player},create_force=function()return foreign end,
            surfaces={{find_entities_filtered=function()return {old_lab} end,
              create_entity=function()return new_lab end}}}
          module.apply("source")
          callbacks.init();callbacks[1]()
          assert(storage.bob_material_preservation.phase=="earn-partial")
          assert(player.technologies[LEAD].saved_progress==0.27)
          assert(foreign.technologies[LEAD].saved_progress==0.17)
          assert(old_lab.disabled_by_script and not new_lab.disabled_by_script)
          assert(#player.research_queue==3 and player.research_queue[1].name==BRONZE
            and player.research_queue[2].name==BRONZE)
        end''')
        profile = json.loads((ROOT / "tests/profiles/bob-material-preservation-source-f210-2123.json").read_text(encoding="utf-8"))
        mods = {row["name"]: row["version"] for row in profile["mods"]}
        prepare(self.control, self.table(mods))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]], verbosity=2)

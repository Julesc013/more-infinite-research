"""Host controls of the cryogenic laboratory witness; these do not run Factorio."""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/cryogenic-gameplay"
PACKS = [
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "utility-science-pack",
    "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
    "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
]
OWNER = "cryogenic-science-pack"
GEAR = "recipe-prod-research_gears-1"
FOREIGN = "mir5-cryogenic-native-science"
EXPECTED_GEAR_PRODUCTIVITY = 0.10
EXPECTED_LABORATORY_PRODUCTIVITY = 0


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class CryogenicGameplayFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def stage(self, row):
        self.lua.globals().gear = lua(self.lua, row)
        self.lua.globals().stage_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        return self.lua.execute('''
          local env = {data={raw={technology={["recipe-prod-research_gears-1"]=gear}}}}
          setmetatable(env, {__index=_G})
          return pcall(assert(loadfile(stage_path, "t", env)))
        ''')

    @staticmethod
    def gear():
        return {"enabled": True, "prerequisites": PACKS[:], "unit": {
            "count_formula": "8000*2^(L-1)", "time": 60,
            "ingredients": [[name, 1] for name in PACKS],
        }}

    def test_acceleration_follows_complete_independent_science_and_gate_preflight(self):
        result = self.stage(self.gear())
        self.assertTrue(result[0] if isinstance(result, tuple) else result)
        row = self.lua.globals().gear
        self.assertEqual(1, row["unit"]["count"])
        self.assertEqual(1, row["unit"]["time"])
        self.assertIsNone(row["unit"]["count_formula"])
        self.assertEqual(PACKS, [row["unit"]["ingredients"][i][1] for i in range(1, 13)])

    def test_bad_native_inputs_refuse_before_acceleration(self):
        mutations = []
        missing = self.gear(); missing["unit"]["ingredients"].pop(); mutations.append(missing)
        wrong = self.gear(); wrong["unit"]["ingredients"][0][0] = FOREIGN; mutations.append(wrong)
        amount = self.gear(); amount["unit"]["ingredients"][0][1] = 2; mutations.append(amount)
        duplicate = self.gear(); duplicate["unit"]["ingredients"][1] = [PACKS[0], 1]; mutations.append(duplicate)
        gate = self.gear(); gate["prerequisites"].remove(OWNER); mutations.append(gate)
        disabled = self.gear(); disabled["enabled"] = False; mutations.append(disabled)
        for index, row in enumerate(mutations):
            with self.subTest(mutation=index):
                ok, _ = self.stage(row)
                self.assertFalse(ok)
                actual = self.lua.globals().gear["unit"]
                self.assertEqual(row["unit"]["count_formula"], actual["count_formula"])
                self.assertEqual(row["unit"]["time"], actual["time"])
                self.assertIsNone(actual["count"])

    def runtime(self):
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().packs = lua(self.lua, PACKS)
        return self.lua.execute('''
          local force = {valid=true, technologies={}, current_research=nil,
            laboratory_productivity_bonus=0, recipes={["iron-gear-wheel"]={productivity_bonus=0}}}
          for _, name in ipairs(packs) do
            force.technologies[name] = {valid=true, name=name, researched=false, enabled=true, level=1}
          end
          force.technologies["cryogenic-plant"] = {valid=true, name="cryogenic-plant", researched=false}
          local owner = force.technologies["cryogenic-science-pack"]
          owner.research_unit_ingredients = {{name="mir5-cryogenic-native-science", amount=1}}
          local gear = {valid=true, name="recipe-prod-research_gears-1", enabled=true, researched=false,
            level=1, research_unit_ingredients={}, prototype={effects={{type="change-recipe-productivity",
              recipe="iron-gear-wheel",change=.1}}}}
          for _, name in ipairs(packs) do gear.research_unit_ingredients[#gear.research_unit_ingredients+1]={name=name,amount=1} end
          force.technologies[gear.name] = gear
          local prototypes = {item={}}
          for _, name in ipairs(packs) do
            prototypes.item[name] = {science_capacity=1, lab_ignores_spoil_percent=false,
              get_spoil_ticks=function() return 0 end}
          end
          prototypes.item["agricultural-science-pack"] = {science_capacity=1,
            lab_ignores_spoil_percent=false, get_spoil_ticks=function() return 216000 end}
          prototypes.item["mir5-cryogenic-native-science"] = {science_capacity=1,
            lab_ignores_spoil_percent=false, get_spoil_ticks=function() return 0 end}
          local inventory, stored = {}, {}
          local inserted = {}
          local slots = {}
          inventory.insert = function(row)
            inserted[row.name]=(inserted[row.name] or 0)+row.count
            local stack = slots[row.name]
            if not stack then
              stack = {valid_for_read=true, name=row.name, count=0, spoil_percent=0,
                spoil_tick=0, prototype=prototypes.item[row.name]}
              slots[row.name] = stack
            end
            stack.count=inserted[row.name]
            return row.count
          end
          inventory.get_item_count = function(name) return inserted[name] or 0 end
          setmetatable(inventory, {__len=function() return #packs + 1 end,
            __index=function(_, index)
              if type(index) ~= "number" then return nil end
              local name = index <= #packs and packs[index] or "mir5-cryogenic-native-science"
              return slots[name]
            end})
          local lab = {valid=true, get_inventory=function() return inventory end,
            get_stored_durability=function(name) return stored[name] or {durability=0} end}
          local callbacks, events = {}, {}
          local env = {
            script={active_mods={base="2.1.23", ["space-age"]="2.1.23", ["more-infinite-research"]="5.0.21000"},
              on_init=function(f) callbacks.init=f end, on_load=function(f) callbacks.load=f end,
              on_event=function(event, f) events[event]=f end},
            defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
          }
          setmetatable(env, {__index=_G})
          -- Registration must not read game or storage.
          assert(loadfile(control_path, "t", env))()
          env.storage = {}
          env.game = {tick=0, forces={player=force}, surfaces={{create_entity=function() return lab end}}}
          local reports, logs = {}, {}
          env.helpers = {table_to_json=function(row) reports[#reports+1]=row; return "fixture-json" end}
          env.log = function(message) logs[#logs+1]=message end
          return {env=env,callbacks=callbacks,events=events,force=force,lab=lab,inserted=inserted,
            reports=reports,logs=logs,stored=stored,set_count=function(name, count, spoil_percent)
              inserted[name] = count
              slots[name].count = count
              slots[name].spoil_percent = spoil_percent or 0
            end}
        ''')

    def test_registration_and_seed_do_not_earn_either_lab_witness(self):
        runtime = self.runtime()
        runtime["callbacks"]["init"]()
        force = runtime["force"]
        self.assertFalse(force["technologies"][OWNER]["researched"])
        self.assertFalse(force["technologies"][GEAR]["researched"])
        for name in PACKS:
            if name != OWNER:
                self.assertTrue(force["technologies"][name]["researched"])
        self.assertTrue(force["technologies"]["cryogenic-plant"]["researched"])
        for name in PACKS + [FOREIGN]:
            self.assertEqual(32, runtime["inserted"][name])
        self.assertEqual(0, runtime["env"]["storage"]["mir5_cryogenic_gameplay"]["finished"])

    def test_reload_checks_saved_native_completion_and_consumption_without_repairing_it(self):
        for mutation in ("pass", "missing-completion", "wrong-input", "wrong-gear", "wrong-lab", "wrong-consumption",
                         "wrong-agricultural-remainder", "wrong-agricultural-freshness"):
            with self.subTest(mutation=mutation):
                runtime = self.runtime()
                runtime["callbacks"]["init"]()
                force = runtime["force"]
                state = runtime["env"]["storage"]["mir5_cryogenic_gameplay"]
                state["phase"], state["finished"] = "complete", 2
                force["technologies"][OWNER]["researched"] = True
                force["technologies"][GEAR]["level"] = 2
                force["recipes"]["iron-gear-wheel"]["productivity_bonus"] = EXPECTED_GEAR_PRODUCTIVITY
                for name in PACKS + [FOREIGN]:
                    runtime["set_count"](name, 31)
                runtime["set_count"]("agricultural-science-pack", 30, 0.01)
                runtime["stored"]["agricultural-science-pack"] = lua(self.lua, {"durability": 0.99})
                if mutation == "missing-completion": state["finished"] = 1
                if mutation == "wrong-input": force["technologies"][OWNER]["research_unit_ingredients"][1]["name"] = PACKS[0]
                if mutation == "wrong-gear": force["recipes"]["iron-gear-wheel"]["productivity_bonus"] = 0.02
                if mutation == "wrong-lab": force["laboratory_productivity_bonus"] = 0.10
                if mutation == "wrong-consumption": runtime["inserted"][FOREIGN] = 32
                if mutation == "wrong-agricultural-remainder": runtime["stored"]["agricultural-science-pack"] = lua(self.lua, {"durability": 0})
                if mutation == "wrong-agricultural-freshness": runtime["set_count"]("agricultural-science-pack", 30, 0)
                runtime["callbacks"]["load"]()
                if mutation == "pass":
                    runtime["events"][1]()
                    result = runtime["reports"][1]
                    self.assertEqual("reload", result["stage"])
                    self.assertEqual(EXPECTED_GEAR_PRODUCTIVITY, result["witnesses"]["native_gear_productivity"])
                    self.assertEqual(EXPECTED_LABORATORY_PRODUCTIVITY, result["witnesses"]["laboratory_productivity"])
                    self.assertEqual(1, result["witnesses"]["each_nonperishable_official_science_consumed"])
                    self.assertEqual(2, result["witnesses"]["agricultural_science_items_drawn"])
                    self.assertEqual(30, result["witnesses"]["agricultural_science"]["inventory_count"])
                    self.assertGreater(result["witnesses"]["agricultural_science"]["stored_durability"], 0)
                    self.assertIsNone(result["witnesses"]["each_official_science_consumed"])
                    self.assertEqual(1, result["witnesses"]["gear"]["recipe_effect_matches"])
                    self.assertEqual(EXPECTED_GEAR_PRODUCTIVITY,
                                     result["witnesses"]["gear"]["recipe_effect_change"])
                else:
                    with self.assertRaises(Exception): runtime["events"][1]()
                    failure = runtime["reports"][1]
                    self.assertEqual("failed", failure["status"])
                    self.assertEqual(EXPECTED_GEAR_PRODUCTIVITY, failure["expected_recipe_productivity"])
                    self.assertEqual(EXPECTED_LABORATORY_PRODUCTIVITY, failure["expected_laboratory_productivity"])
                    if mutation == "wrong-gear":
                        self.assertEqual("native gear productivity differs", failure["error"])
                        self.assertEqual(0.02, failure["actual_recipe_productivity"])
                        self.assertEqual(0, failure["actual_laboratory_productivity"])
                    elif mutation == "wrong-lab":
                        self.assertEqual("native laboratory productivity differs", failure["error"])
                        self.assertEqual(EXPECTED_GEAR_PRODUCTIVITY, failure["actual_recipe_productivity"])
                        self.assertEqual(0.10, failure["actual_laboratory_productivity"])
                    if mutation in ("wrong-gear", "wrong-lab"):
                        self.assertEqual(2, failure["gear"]["level"])
                        self.assertIsNotNone(failure["gear"]["researched"])
                        self.assertEqual(1, failure["gear"]["recipe_effect_matches"])
                        self.assertEqual(EXPECTED_GEAR_PRODUCTIVITY, failure["gear"]["recipe_effect_change"])
                    if mutation in ("wrong-agricultural-remainder", "wrong-agricultural-freshness"):
                        self.assertEqual("perishable agricultural science consumption differs", failure["error"])
                        inputs = failure["official_input_consumption"]
                        self.assertEqual(set(PACKS + [FOREIGN]), set(inputs.keys()))
                        for name in PACKS + [FOREIGN]:
                            self.assertIn("inventory_count", inputs[name])
                            self.assertIn("stored_durability", inputs[name])
                            self.assertIn("stacks", inputs[name])
                        agricultural = inputs["agricultural-science-pack"]
                        self.assertEqual(30, agricultural["inventory_count"])
                        self.assertEqual(216000, agricultural["prototype_spoil_ticks"])
                        self.assertFalse(agricultural["prototype_lab_ignores_spoil_percent"])
                        self.assertEqual(0 if mutation == "wrong-agricultural-freshness" else 0.01,
                                         agricultural["stacks"][1]["spoil_percent"])
                self.assertEqual(1 if mutation == "missing-completion" else 2, state["finished"])
                self.assertEqual(32 if mutation == "wrong-consumption" else 31, runtime["inserted"][FOREIGN])
                if mutation == "wrong-gear":
                    self.assertEqual(0.02, force["recipes"]["iron-gear-wheel"]["productivity_bonus"])
                if mutation == "wrong-lab":
                    self.assertEqual(0.10, force["laboratory_productivity_bonus"])

    def test_profile_binds_both_fixtures_current_engine_and_observer(self):
        profile = json.loads((ROOT / "tests/profiles/cryogenic-gameplay-space-age-f210.json").read_text())
        mods = {row["name"]: row["version"] for row in profile["mods"] if row["enabled"]}
        self.assertEqual("2.1.23", mods["base"])
        self.assertEqual("2.1.23", mods["space-age"])
        self.assertEqual("5.0.21000", mods["more-infinite-research"])
        self.assertEqual("0.1.0", mods["mir-fixture-mir5-cryogenic-native"])
        self.assertEqual("0.1.0", mods["mir-fixture-mir5-cryogenic-gameplay"])
        self.assertEqual("0.1.0", mods["mir-fixture-mir5-active-mods-observer"])
        info = json.loads((FIXTURE / "info.json").read_text())
        self.assertIn("mir-fixture-mir5-cryogenic-native = 0.1.0", info["dependencies"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CryogenicGameplayFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

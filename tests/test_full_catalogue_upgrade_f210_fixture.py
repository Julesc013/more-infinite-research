import argparse
import copy
import json
import os
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/full-catalogue-upgrade"
F210 = FIXTURE / "f210"
SHARED = FIXTURE / "shared"
PROFILES = ROOT / "tests/profiles"
ORACLE = ROOT / "spec/inventory/modern-f210-470.json"
F210_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F210_RUNTIME_API"),
    "C:/Program Files/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
    "D:/Games/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
    "D:/Games/Factorio/2.1/doc-html/runtime-api.json",
    "D:/Programs/Factorio/2.1/doc-html/runtime-api.json",
)
OBSERVER = "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"
OBSERVER_A15 = "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0"
PUBLISHED_4702 = "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F"
PUBLISHED_4703 = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"
CANDIDATE_4702 = "C8E0C570213F41CA8C816A29D1556FD40A36896D31ED56B07856652B2DE7F32A"
CANDIDATE_CURRENT = "8F858F6B7E604757DE84D960E7D7701021B956782C65A13978E3AFD711F7B071"
STAGES = (
    ("published-4.7", "4.7.21002", "0.1.0", PUBLISHED_4702, OBSERVER),
    ("mir5", "5.0.21000", "0.2.0", CANDIDATE_4702, OBSERVER),
    ("published-4.7.3", "4.7.21003", "0.1.0", PUBLISHED_4703, OBSERVER_A15),
    ("mir5-from-4.7.3", "5.0.21000", "0.2.0", CANDIDATE_CURRENT, OBSERVER_A15),
)
SOURCE_STAGES = {"published-4.7", "published-4.7.3"}
GEAR_SCIENCE = [[name, 1] for name in ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack")]
OWNERS = {
    "low-density-structure-productivity",
    "plastic-bar-productivity",
    "processing-unit-productivity",
    "rocket-fuel-productivity",
    "steel-plate-productivity",
}
DESCRIPTORS = (
    ("research_copper", "recipe-prod-research_copper-1", "copper-plate"),
    ("research_iron", "recipe-prod-research_iron-1", "iron-plate"),
    ("research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"),
    ("research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"),
    ("research_grenades", "recipe-prod-research_grenades-1", "grenade"),
    ("research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"),
    ("research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"),
    ("research_concrete", "recipe-prod-research_concrete-1", "stone-brick"),
    ("research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"),
)


def f210_runtime_api_path():
    for candidate in F210_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


def py(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [py(value[key]) for key in range(1, max(keys) + 1)]
        return {key: py(value[key]) for key in keys}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        out = runtime.table()
        for key, item in value.items():
            out[key] = lua(runtime, item)
        return out
    if isinstance(value, list):
        out = runtime.table()
        for index, item in enumerate(value, 1):
            out[index] = lua(runtime, item)
        return out
    return value


class FullCatalogueUpgradeF210FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.oracle = {row["id"]: row for row in json.loads(ORACLE.read_text(encoding="utf-8"))["profiles"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("function load_plan(path) return assert(loadfile(path))() end")
        self.plan = py(self.lua.eval("load_plan")((SHARED / "f210-catalogue.lua").as_posix()))

    def expected(self, name):
        facts = self.oracle[name]["technology_owner_progression_facts"]
        return (
            {fact["name"] for fact in facts},
            {fact["name"] for fact in facts if fact["group"] != "scripted-runtime-carriers"},
            {fact["name"] for fact in facts if fact["group"] == "scripted-runtime-carriers"},
            {effect["recipe"] for fact in facts for effect in fact["effects"] if effect["type"] == "change-recipe-productivity"},
            {effect["ammo_category"] for fact in facts for effect in fact["effects"] if effect["type"] == "gun-speed"},
        )

    def test_exact_independent_inventory_and_published_owner_closure(self):
        for key, oracle_name, owners in (("base", "base-f210", set()), ("space_age", "space-age-f210", OWNERS)):
            public, state, scripted, recipes, guns = self.expected(oracle_name)
            plan = self.plan[key]
            with self.subTest(key=key):
                self.assertEqual(public, {row["name"] for row in plan["public"]})
                self.assertEqual(state, {row["name"] for row in plan["state"]})
                self.assertEqual(scripted, set(plan["scripted"]))
                self.assertEqual(recipes, set(plan["recipes"]))
                self.assertEqual(guns, set(plan["guns"]))
                self.assertEqual(owners, set(plan["native_owners"]))
                credits = {
                    f"mir-native-credit-{family}-{recipe}-{direction}"
                    for family, main, recipe in DESCRIPTORS if main in public for direction in ("positive", "negative")
                }
                self.assertEqual(credits, set(plan["credits"]))
        self.assertEqual((53, 71, 20, 24), (len(self.plan["base"]["public"]), len(self.plan["space_age"]["public"]), len(self.plan["base"]["credits"]), len(self.plan["space_age"]["credits"])))
        self.assertEqual((53, 69), (len(self.plan["base"]["state"]), len(self.plan["space_age"]["state"])))
        self.assertEqual({"recipe-prod-research_agricultural_growth_speed-1", "recipe-prod-research_spoilage_preservation-1"}, set(self.plan["space_age"]["scripted"]))
        self.assertTrue({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_cargo_landing_pad_count-1"} <= {row["name"] for row in self.plan["space_age"]["state"]})
        owners = {
            row["native_owner_identity"]
            for row in self.oracle["space-age-f210"]["captured_maximum_level_bindings"]["bindings"]
            if row["operation"] == "preserve_native_owner"
        }
        self.assertEqual(OWNERS, owners)

    def test_stage_data_guard_accelerates_only_exact_f210_gear(self):
        for profile in ("base-f210", "space-age-f210"):
            gear = next(row for row in self.oracle[profile]["technology_owner_progression_facts"] if row["name"] == "recipe-prod-research_gears-1")
            self.assertEqual(GEAR_SCIENCE, gear["science"])
        self.lua.execute("""
          function run_data(path, common, catalogue, f210_catalogue, raw, mods)
            local env = {data={raw=raw}, mods=mods}
            env.require = function(name)
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_data_final" then
                return assert(loadfile(common, "t", env))()
              end
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue, "t", env))()
              end
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue" then
                return assert(loadfile(f210_catalogue, "t", env))()
              end
              error("unexpected fixture module: " .. tostring(name))
            end
            setmetatable(env, {__index=_G})
            local ok, message = pcall(function() assert(loadfile(path, "t", env))() end)
            return {ok=ok, message=tostring(message), raw=raw}
          end
        """)
        for stage, mir, fixture, _, _ in STAGES:
            for space in (False, True):
                effects = [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]
                if space:
                    effects.insert(0, {"type": "change-recipe-productivity", "recipe": "casting-iron-gear-wheel", "change": .1})
                gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 60, "ingredients": GEAR_SCIENCE}, "effects": effects}
                raw = {"technology": {"recipe-prod-research_gears-1": gear}, "unchanged": {"value": 17}}
                mods = {"base": "2.1.23", "more-infinite-research": mir, "mir-fixture-mir5-full-catalogue-upgrade": fixture}
                if space:
                    mods.update({"elevated-rails": "2.1.23", "quality": "2.1.23", "recycler": "2.1.23", "space-age": "2.1.23"})
                with self.subTest(stage=stage, space=space):
                    result = self.lua.eval("run_data")((F210 / stage / "data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / stage / "catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), lua(self.lua, raw), lua(self.lua, mods))
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]
                    self.assertEqual((None, "1", 1), (actual.get("count"), actual["count_formula"], actual["time"]))
                    self.assertEqual(17, py(result["raw"])["unchanged"]["value"])
                    self.assertEqual(GEAR_SCIENCE, actual["ingredients"])
                wrong_amount = copy.deepcopy(GEAR_SCIENCE)
                wrong_amount[0][1] = 2
                wrong_name = copy.deepcopy(GEAR_SCIENCE)
                wrong_name[0][0] = "foreign-science-pack"
                duplicate = copy.deepcopy(GEAR_SCIENCE)
                duplicate[1] = duplicate[0][:]
                for ingredients in (None, [], GEAR_SCIENCE[:-1], wrong_amount, wrong_name, duplicate):
                    altered = copy.deepcopy(gear)
                    altered["unit"]["ingredients"] = ingredients
                    with self.subTest(stage=stage, space=space, ingredients=ingredients):
                        raw_input = lua(self.lua, {"technology": {"recipe-prod-research_gears-1": altered}})
                        before = py(raw_input)
                        result = self.lua.eval("run_data")((F210 / stage / "data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / stage / "catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), raw_input, lua(self.lua, mods))
                        self.assertFalse(result["ok"])
                        self.assertIn("gear science", str(result["message"]))
                        self.assertEqual(before, py(result["raw"]))
                if stage == "published-4.7.3":
                    for wrong_mir in ("4.7.21002", "5.0.21000"):
                        with self.subTest(stage=stage, wrong_mir=wrong_mir):
                            raw_input = lua(self.lua, {"technology": {"recipe-prod-research_gears-1": copy.deepcopy(gear)}})
                            before = py(raw_input)
                            result = self.lua.eval("run_data")((F210 / stage / "data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / stage / "catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), raw_input, lua(self.lua, {**mods, "more-infinite-research": wrong_mir}))
                            self.assertFalse(result["ok"])
                            self.assertIn("unexpected MIR target closure", str(result["message"]))
                            self.assertEqual(before, py(result["raw"]))
        gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 61}, "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]}
        result = self.lua.eval("run_data")((F210 / "mir5/data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / "mir5/catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), lua(self.lua, {"technology": {"recipe-prod-research_gears-1": gear}}), lua(self.lua, {"base": "2.1.23", "more-infinite-research": "5.0.21000", "mir-fixture-mir5-full-catalogue-upgrade": "0.2.0"}))
        self.assertFalse(result["ok"])
        self.assertIn("workload differs", str(result["message"]))
        self.assertEqual(61, py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]["time"])
        gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 60, "ingredients": GEAR_SCIENCE}, "effects": [{"type": "change-recipe-productivity", "recipe": "casting-iron-gear-wheel", "change": .1}, {"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]}
        result = self.lua.eval("run_data")((F210 / "published-4.7/data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / "published-4.7/catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), lua(self.lua, {"technology": {"recipe-prod-research_gears-1": gear}}), lua(self.lua, {"base": "2.1.23", "elevated-rails": "2.1.23", "quality": "2.1.23", "space-age": "2.1.23", "more-infinite-research": "4.7.21002", "mir-fixture-mir5-full-catalogue-upgrade": "0.1.0"}))
        self.assertFalse(result["ok"])
        self.assertIn("Space Age closure differs", str(result["message"]))
        self.assertEqual(60, py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]["time"])

    def test_shared_control_registers_f210_stages_without_runtime_reads(self):
        for stage, mir, fixture, _, _ in STAGES:
            with self.subTest(stage=stage):
                self.lua.globals().control_path = (F210 / stage / "control.lua").as_posix()
                self.lua.globals().catalogue_path = (F210 / stage / "catalogue.lua").as_posix()
                self.lua.globals().f210_catalogue_path = (SHARED / "f210-catalogue.lua").as_posix()
                self.lua.globals().common_control_path = (SHARED / "control.lua").as_posix()
                self.lua.globals().source_stage = stage in SOURCE_STAGES
                self.lua.globals().stage_mir = mir
                self.lua.globals().fixture_version = fixture
                self.lua.execute("""
                  function parse_f210_control()
                    local callbacks, forbidden = {events={}}, {}
                    local env = {
                      script={on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                        on_configuration_changed=function(fn) callbacks.configuration=fn end,
                        on_event=function(event, fn) callbacks.events[event]=fn end,
                        active_mods={base="2.1.23", ["more-infinite-research"]=stage_mir,
                          ["mir-fixture-mir5-full-catalogue-upgrade"]=fixture_version}},
                      defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
                    }
                    env.require=function(name)
                        if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_control" then
                          return assert(loadfile(common_control_path, "t", env))()
                        end
                        if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                          return assert(loadfile(catalogue_path, "t", env))()
                        end
                        assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
                        return assert(loadfile(f210_catalogue_path, "t", env))()
                      end
                    env._G=env
                    setmetatable(env,{__index=function(_,key)
                      if key == "game" or key == "storage" then forbidden[key]=true; return nil end
                      return _G[key]
                    end})
                    local ok,message=pcall(function() assert(loadfile(control_path, "t", env))() end)
                    return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
                  end
                """)
                result = self.lua.eval("parse_f210_control")()
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                if stage in SOURCE_STAGES:
                    self.assertIsNotNone(result["callbacks"]["init"])
                else:
                    self.assertIsNotNone(result["callbacks"]["configuration"])

    def test_f210_source_callbacks_fill_and_freeze_read_only_active_lab(self):
        self.lua.globals().control_path = (F210 / "published-4.7" / "control.lua").as_posix()
        self.lua.globals().catalogue_path = (F210 / "published-4.7" / "catalogue.lua").as_posix()
        self.lua.globals().f210_catalogue_path = (SHARED / "f210-catalogue.lua").as_posix()
        self.lua.globals().common_control_path = (SHARED / "control.lua").as_posix()
        self.lua.execute("""
          function run_f210_source_with_read_only_active()
            local callbacks, storage = {events={}}, {}
            local plan = assert(loadfile(f210_catalogue_path))().base
            local inserted, contents, clears, energy = {}, {}, 0, 0
            local inventory = {}
            function inventory.clear()
              clears, contents = clears + 1, {}
            end
            function inventory.insert(stack)
              inserted[stack.name] = (inserted[stack.name] or 0) + stack.count
              contents[stack.name] = (contents[stack.name] or 0) + stack.count
              return stack.count
            end
            local entity_values = {}
            local entity = setmetatable({}, {
              __index=function(_, key)
                if key == "valid" then return true end
                if key == "active" then return true end
                if key == "energy" then return energy end
                if key == "get_inventory" then
                  return function(slot) assert(slot == 1); return inventory end
                end
                return entity_values[key]
              end,
              __newindex=function(_, key, value)
                if key == "active" then error("active is read only") end
                if key == "energy" then energy = value else entity_values[key] = value end
              end,
            })
            local function make_force(index)
              local force = {index=index, technologies={}, recipes={}}
              setmetatable(force, {__newindex=function(target, key, value)
                rawset(target, key, value)
                if key == "research_queue" then rawset(target, "current_research", value[1]) end
              end})
              local function add_technology(name)
                if force.technologies[name] ~= nil then return force.technologies[name] end
                local value = {
                  valid=true, name=name, prototype={max_level=4294967295, level=1},
                  level=1, researched=false, enabled=true, visible_when_disabled=true,
                  saved_progress=0, prerequisites={},
                }
                force.technologies[name] = value
                return value
              end
              for _, row in ipairs(plan.state) do add_technology(row.name) end
              local gear = add_technology("recipe-prod-research_gears-1")
              add_technology("braking-force-1")
              gear.research_unit_ingredients = {
                {name="automation-science-pack", amount=1}, {name="logistic-science-pack", amount=1},
                {name="chemical-science-pack", amount=1}, {name="production-science-pack", amount=1},
              }
              for _, recipe in ipairs(plan.recipes) do force.recipes[recipe] = {valid=true, productivity_bonus=0} end
              for _, field in ipairs(assert(loadfile(f210_catalogue_path))().force_fields) do force[field] = 0 end
              function force.enable_all_prototypes() end
              function force.reset_technology_effects() end
              function force.get_gun_speed_modifier() return 0 end
              function force.add_research(value) return value == gear end
              for _, technology in pairs(force.technologies) do technology.force = force end
              return force
            end
            local player = make_force(1)
            local game = {tick=0, forces={player=player}, surfaces={[1]={create_entity=function() return entity end}}}
            function game.create_force()
              local paused = make_force(2); game.forces[paused.index] = paused; return paused
            end
            function game.server_save() game.saved = true end
            local env = {
              script={on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_event=function(event, fn) callbacks.events[event]=fn end,
                active_mods={base="2.1.23", ["more-infinite-research"]="4.7.21002",
                  ["mir-fixture-mir5-full-catalogue-upgrade"]="0.1.0"}},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
              game=game, storage=storage, helpers={table_to_json=function() return "{}" end}, log=function() end,
            }
            env.require=function(name)
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_control" then
                return assert(loadfile(common_control_path, "t", env))()
              end
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue_path, "t", env))()
              end
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", env))()
            end
            setmetatable(env, {__index=_G})
            local ok, message = pcall(function()
              assert(loadfile(control_path, "t", env))()
              callbacks.init()
              callbacks.events[1]{research=player.technologies["recipe-prod-research_gears-1"]}
              callbacks.events[2]()
            end)
            local paused = game.forces[2]
            return {ok=ok, message=tostring(message), energy=energy, inserted=inserted, contents=contents,
              clears=clears, phase=storage.mir5_full_catalogue_upgrade and storage.mir5_full_catalogue_upgrade.phase,
              source_labs=storage.mir5_full_catalogue_upgrade and storage.mir5_full_catalogue_upgrade.source_labs,
              paused_progress=paused and paused.technologies["recipe-prod-research_gears-1"].saved_progress,
              paused_current_absent=paused and paused.current_research == nil,
              paused_queue_size=paused and #(paused.research_queue or {}), saved=game.saved}
          end
        """)
        result = py(self.lua.eval("run_f210_source_with_read_only_active")())
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(0, result["energy"])
        self.assertEqual(2, result["clears"])
        self.assertEqual({}, result["contents"])
        self.assertEqual({name: 64 for name, _ in GEAR_SCIENCE}, result["inserted"])
        self.assertEqual(("completed", 1, .27, True, 0, True), (result["phase"], result["source_labs"], result["paused_progress"], result["paused_current_absent"], result["paused_queue_size"], result["saved"]))

    def test_f210_473_source_snapshot_reaches_the_current_successor_unchanged(self):
        self.lua.globals().source_control_path = (F210 / "published-4.7.3" / "control.lua").as_posix()
        self.lua.globals().source_catalogue_path = (F210 / "published-4.7.3" / "catalogue.lua").as_posix()
        self.lua.globals().successor_control_path = (F210 / "mir5-from-4.7.3" / "control.lua").as_posix()
        self.lua.globals().successor_catalogue_path = (F210 / "mir5-from-4.7.3" / "catalogue.lua").as_posix()
        self.lua.globals().f210_catalogue_path = (SHARED / "f210-catalogue.lua").as_posix()
        self.lua.globals().common_control_path = (SHARED / "control.lua").as_posix()
        self.lua.execute("""
          function run_f210_473_handoff()
            local function copy(value, seen)
              if type(value) ~= "table" then return value end
              seen = seen or {}; if seen[value] then return seen[value] end
              local out = {}; seen[value] = out
              for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
              return out
            end
            local function same(left, right, seen)
              if type(left) ~= type(right) then return false end
              if type(left) ~= "table" then return left == right end
              seen = seen or {}; if seen[left] == right then return true end
              seen[left] = right
              for key, value in pairs(left) do if not same(value, right[key], seen) then return false end end
              for key in pairs(right) do if left[key] == nil then return false end end
              return true
            end
            local f210_env = {}
            f210_env._G = f210_env; setmetatable(f210_env, {__index=_G})
            local f210_plan = assert(loadfile(f210_catalogue_path, "t", f210_env))()
            local source_env = {}
            source_env.require = function(name)
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", source_env))()
            end
            source_env._G = source_env; setmetatable(source_env, {__index=_G})
            local plan = assert(loadfile(source_catalogue_path, "t", source_env))().base
            local inventory, contents = {}, {}
            function inventory.clear() contents = {} end
            function inventory.insert(stack)
              contents[stack.name] = (contents[stack.name] or 0) + stack.count
              return stack.count
            end
            local lab = {valid=true, energy=0, get_inventory=function(slot) assert(slot == 1); return inventory end}
            local function make_force(index)
              local force = {index=index, technologies={}, recipes={}, research_progress=0}
              setmetatable(force, {__newindex=function(target, key, value)
                rawset(target, key, value)
                if key == "research_queue" then rawset(target, "current_research", value[1]) end
              end})
              local function technology(name, credit)
                if force.technologies[name] then return force.technologies[name] end
                local row = {valid=true, name=name, force=force,
                  prototype={max_level=4294967295, level=0, hidden=credit == true},
                  level=credit and 1 or 0, researched=false, enabled=not credit,
                  visible_when_disabled=not credit, saved_progress=0, prerequisites={},
                  research_recursive=function() end}
                force.technologies[name] = row
                return row
              end
              for _, row in ipairs(plan.state) do technology(row.name, false) end
              for _, name in ipairs(plan.native_owners) do technology(name, false) end
              for _, name in ipairs(plan.credits) do technology(name, true) end
              local gear = technology("recipe-prod-research_gears-1", false)
              technology("braking-force-1", false)
              gear.research_unit_ingredients = {
                {name="automation-science-pack", amount=1}, {name="logistic-science-pack", amount=1},
                {name="chemical-science-pack", amount=1}, {name="production-science-pack", amount=1},
              }
              for _, recipe in ipairs(plan.recipes) do force.recipes[recipe] = {valid=true, productivity_bonus=0} end
              for _, field in ipairs(f210_plan.force_fields) do force[field] = 0 end
              function force.enable_all_prototypes() end
              function force.reset_technology_effects() end
              function force.get_gun_speed_modifier() return 0 end
              function force.add_research(value) return value == gear end
              return force
            end
            local player = make_force(1)
            local game = {tick=0, forces={player=player}, surfaces={[1]={create_entity=function() return lab end}}}
            function game.create_force()
              local paused = make_force(2); game.forces[paused.index] = paused; return paused
            end
            function game.server_save(name) game.saved = name end
            local storage = {}
            local function load_stage(control_path, catalogue_path, mods)
              local callbacks, env = {events={}}, {}
              env.script = {active_mods=mods, on_init=function(fn) callbacks.init=fn end,
                on_load=function(fn) callbacks.load=fn end,
                on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_event=function(event, fn) callbacks.events[event]=fn end}
              env.defines = {events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
              env.game, env.storage, env.helpers, env.log = game, storage, {table_to_json=function() return "{}" end}, function() end
              env.require = function(name)
                if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_control" then
                  return assert(loadfile(common_control_path, "t", env))()
                end
                if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                  return assert(loadfile(catalogue_path, "t", env))()
                end
                assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
                return assert(loadfile(f210_catalogue_path, "t", env))()
              end
              env._G = env; setmetatable(env, {__index=_G})
              assert(loadfile(control_path, "t", env))()
              return callbacks
            end
            local source = load_stage(source_control_path, source_catalogue_path, {
              base="2.1.23", ["more-infinite-research"]="4.7.21003",
              ["mir-fixture-mir5-full-catalogue-upgrade"]="0.1.0"})
            source.init()
            local gear = player.technologies["recipe-prod-research_gears-1"]
            gear.level = gear.level + 1; player.recipes["iron-gear-wheel"].productivity_bonus = .1
            source.events[1]{research=gear}; source.events[2]()
            local state = storage.mir5_full_catalogue_upgrade
            local source_snapshot = copy(state.source_snapshot)
            local successor = load_stage(successor_control_path, successor_catalogue_path, {
              base="2.1.23", ["more-infinite-research"]="5.0.21000",
              ["mir-fixture-mir5-full-catalogue-upgrade"]="0.2.0"})
            successor.configuration()
            return {phase=state.phase, source_labs=state.source_labs, successor_labs=state.successor_labs,
              saved=game.saved, source_snapshot_read_only=same(source_snapshot, state.source_snapshot),
              paused_progress=game.forces[2].technologies["recipe-prod-research_gears-1"].saved_progress,
              successor_science=contents}
          end
        """)
        result = py(self.lua.eval("run_f210_473_handoff")())
        self.assertEqual(("await-successor-lab", 1, 0, "mir5-native-complete"), (result["phase"], result["source_labs"], result["successor_labs"], result["saved"]))
        self.assertTrue(result["source_snapshot_read_only"])
        self.assertEqual(.27, result["paused_progress"])
        self.assertEqual({name: 64 for name, _ in GEAR_SCIENCE}, result["successor_science"])

    def test_f210_runtime_force_schema_when_local_api_is_available(self):
        runtime_api = f210_runtime_api_path()
        if runtime_api is None:
            self.skipTest("F210 runtime API documentation is not installed")
        document = json.loads(runtime_api.read_text(encoding="utf-8"))
        self.assertEqual(document["application_version"], "2.1.23")
        lua_force = next(row for row in document["classes"] if row["name"] == "LuaForce")
        fields = {row["name"]: row for row in lua_force["attributes"]}
        fixture_fields = set(self.plan["force_fields"])
        self.assertTrue(fixture_fields <= set(fields))
        self.assertEqual(("double", "double"), (fields["max_cargo_bay_unloading_distance"]["read_type"], fields["max_cargo_bay_unloading_distance"]["write_type"]))
        self.assertEqual(("uint32", "uint32"), (fields["cargo_landing_pad_limit"]["read_type"], fields["cargo_landing_pad_limit"]["write_type"]))

    def test_profiles_and_shared_staging_contract_are_explicit(self):
        for stage, mir, fixture, _, _ in STAGES:
            info = json.loads((F210 / stage / "info.json").read_text(encoding="utf-8"))
            with self.subTest(info_stage=stage):
                self.assertEqual(("mir-fixture-mir5-full-catalogue-upgrade", fixture, "2.1"), (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual([
                    "base = 2.1.23",
                    "? elevated-rails = 2.1.23",
                    "? quality = 2.1.23",
                    "? recycler = 2.1.23",
                    "? space-age = 2.1.23",
                    f"more-infinite-research = {mir}",
                ], info["dependencies"])
        for profile in ("base", "space-age"):
            for stage, mir, fixture, archive, observer in STAGES:
                data = json.loads((PROFILES / f"full-catalogue-upgrade-{stage}-{profile}-f210-2123.json").read_text(encoding="utf-8"))
                expected_mods = [
                    {"name": "base", "version": "2.1.23", "enabled": True},
                ]
                if profile == "space-age":
                    expected_mods.extend([
                        {"name": "elevated-rails", "version": "2.1.23", "enabled": True},
                        {"name": "quality", "version": "2.1.23", "enabled": True},
                        {"name": "recycler", "version": "2.1.23", "enabled": True},
                        {"name": "space-age", "version": "2.1.23", "enabled": True},
                    ])
                expected_mods.extend([
                    {"name": "mir-fixture-mir5-active-mods-observer", "version": "0.1.0", "enabled": True},
                    {"name": "more-infinite-research", "version": mir, "enabled": True},
                    {"name": "mir-fixture-mir5-full-catalogue-upgrade", "version": fixture, "enabled": True},
                ])
                with self.subTest(profile=profile, stage=stage):
                    self.assertEqual(("f210", "2.1"), (data["target"], data["factorio_line"]))
                    self.assertEqual("Defaults", data["settings_mode"])
                    self.assertEqual({"version": "2.1.23", "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"}, data["engine"])
                    self.assertEqual(expected_mods, data["mods"])
                    self.assertEqual({"mir-fixture-mir5-active-mods-observer_0.1.0.zip": observer, f"more-infinite-research_{mir}.zip": archive}, data["archive_sha256"])
        self.assertEqual((F210 / "published-4.7/control.lua").read_bytes(), (F210 / "mir5/control.lua").read_bytes())
        self.assertEqual((F210 / "published-4.7/data-final-fixes.lua").read_bytes(), (F210 / "mir5/data-final-fixes.lua").read_bytes())
        self.assertEqual((F210 / "published-4.7.3/control.lua").read_bytes(), (F210 / "mir5-from-4.7.3/control.lua").read_bytes())
        self.assertEqual((F210 / "published-4.7.3/data-final-fixes.lua").read_bytes(), (F210 / "mir5-from-4.7.3/data-final-fixes.lua").read_bytes())
        self.assertEqual("4.7.21002", self.plan["target"]["published_mir"])
        for stage in ("published-4.7.3", "mir5-from-4.7.3"):
            self.lua.globals().catalogue_path = (F210 / stage / "catalogue.lua").as_posix()
            self.lua.globals().f210_catalogue_path = (SHARED / "f210-catalogue.lua").as_posix()
            self.lua.execute("""
              function load_f210_473_catalogue()
                local env = {}
                env.require = function(name)
                  assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
                  return assert(loadfile(f210_catalogue_path, "t", env))()
                end
                env._G = env
                setmetatable(env, {__index=_G})
                return assert(loadfile(catalogue_path, "t", env))()
              end
            """)
            with self.subTest(catalogue_stage=stage):
                self.assertEqual("4.7.21003", py(self.lua.eval("load_f210_473_catalogue")())["target"]["published_mir"])
        for path in FIXTURE.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("__more-infinite-research__", text)
            self.assertNotIn('require("research.', text)
            self.assertNotIn('require("compatibility.', text)
        common = (SHARED / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local SAVE = "mir5-native-complete"', common)
        self.assertIn("script.on_load(function()", common)
        self.assertIn("assert_credits(player, plan", common)
        self.assertIn("assert_successor_snapshot", common)
        self.assertIn("queued_progress=.42", common)
        self.assertIn("paused_progress=.27", common)
        self.assertNotIn("productivity_bonus =", common)
        self.assertNotIn("research_unit_count =", common)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FullCatalogueUpgradeF210FixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

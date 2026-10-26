"""Host controls for the private F210 Bob-core material laboratory witness.

These controls only execute the fixture against small data/runtime doubles. They
never launch Factorio, claim native completion, or replace the required current
candidate full-catalogue comparison.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/bob-core-gameplay"
PROFILE = ROOT / "tests/profiles/bob-core-gameplay-f210-2123.json"
BASE_PROFILE = ROOT / "tests/profiles/bob-core-f210-2123.json"
FACTS = ROOT / "tests/fixtures/bob-core-f210-captured-facts.json"
INITIAL_PACKS = 64
CONSUMPTION = {
    "automation-science-pack": 28,
    "logistic-science-pack": 20,
    "chemical-science-pack": 16,
    "production-science-pack": 8,
    "space-science-pack": 10,
    "metallurgic-science-pack": 4,
}
ALLOY_ROUTES = (
    {
        "recipe": "bob-bronze-alloy",
        "owner": "bob-alloy-processing",
        "machine": "mir5-bob-core-alloy-witness-furnace",
        "inherent_productivity": 0,
        "energy": 16,
        "category": "bob-mixing-furnace",
        "categories": ["bob-mixing-furnace"],
        "ingredients": [
            {"type": "item", "name": "copper-plate", "amount": 3},
            {"type": "item", "name": "bob-tin-plate", "amount": 2},
        ],
        "results": [{"type": "item", "name": "bob-bronze-alloy", "amount": 5}],
    },
    {
        "recipe": "bob-gunmetal-alloy",
        "owner": "bob-zinc-processing",
        "machine": "mir5-bob-core-alloy-witness-furnace",
        "inherent_productivity": 0,
        "energy": 32,
        "category": "bob-mixing-furnace",
        "categories": ["bob-mixing-furnace"],
        "ingredients": [
            {"type": "item", "name": "copper-plate", "amount": 8},
            {"type": "item", "name": "bob-tin-plate", "amount": 1},
            {"type": "item", "name": "bob-zinc-plate", "amount": 1},
        ],
        "results": [{"type": "item", "name": "bob-gunmetal-alloy", "amount": 10}],
    },
    {
        "recipe": "bob-invar-alloy",
        "owner": "bob-invar-processing",
        "machine": "mir5-bob-core-alloy-witness-furnace",
        "inherent_productivity": 0,
        "energy": 16,
        "category": "bob-mixing-furnace",
        "categories": ["bob-mixing-furnace"],
        "ingredients": [
            {"type": "item", "name": "bob-nickel-plate", "amount": 2},
            {"type": "item", "name": "iron-plate", "amount": 3},
        ],
        "results": [{"type": "item", "name": "bob-invar-alloy", "amount": 5}],
    },
    {
        "recipe": "bob-nitinol-alloy",
        "owner": "bob-nitinol-processing",
        "machine": "mir5-bob-core-alloy-witness-furnace",
        "inherent_productivity": 0,
        "energy": 16,
        "category": "bob-mixing-furnace",
        "categories": ["bob-mixing-furnace"],
        "ingredients": [
            {"type": "item", "name": "bob-nickel-plate", "amount": 3},
            {"type": "item", "name": "bob-titanium-plate", "amount": 2},
        ],
        "results": [{"type": "item", "name": "bob-nitinol-alloy", "amount": 5}],
    },
    {
        "recipe": "bob-copper-tungsten-alloy",
        "owner": "bob-tungsten-processing",
        "machine": "mir5-bob-core-alloy-witness-foundry",
        "inherent_productivity": .5,
        "energy": 16,
        "category": "metallurgy",
        "categories": ["metallurgy"],
        "ingredients": [
            {"type": "item", "name": "bob-powdered-tungsten", "amount": 3},
            {"type": "fluid", "name": "molten-copper", "amount": 20},
        ],
        "results": [{"type": "item", "name": "bob-copper-tungsten-alloy", "amount": 5}],
    },
)
SOURCE_MACHINE = "bob-electric-mixing-furnace"
FIXTURE_MACHINE = "mir5-bob-core-alloy-witness-furnace"
SOURCE_METALLURGY_MACHINE = "foundry"
FIXTURE_METALLURGY_MACHINE = "mir5-bob-core-alloy-witness-foundry"
ALLOY_CRAFTS = 100


def lua_value(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua_value(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua_value(runtime, item) for item in value])
    return value


def row_value(family, stage_name):
    stage = family[stage_name]
    finite = stage_name == "early"
    value = {
        "type": "technology",
        "name": stage["id"],
        "level": stage["level"],
        "upgrade": True,
        "max_level": stage["max_level"],
        "order": stage["order"],
        "enabled": True,
        "prerequisites": stage["prerequisites"],
        "effects": [{
            "type": "change-recipe-productivity",
            "recipe": route["recipe"],
            "change": 0.02,
        } for route in family["routes"]],
        "unit": {
            "count_formula": stage["count_formula"],
            "time": stage["time"],
            "ingredients": [[name, 1] for name in stage["science"]],
        },
    }
    if not finite:
        value["show_levels_info"] = False
        value["visible_when_disabled"] = True
    return value


def fixture_rows(facts):
    return {
        family[stage_name]["id"]: row_value(family, stage_name)
        for family in facts["families"]
        for stage_name in ("early", "continuation")
    }


def fixture_spec(facts):
    return [{
        "key": family["key"],
        "early": family["early"]["id"],
        "tail": family["continuation"]["id"],
        "recipes": [route["recipe"] for route in family["routes"]],
    } for family in facts["families"]]


def fixture_raw(facts):
    raw = {
        "technology": fixture_rows(facts),
        "recipe": {},
        "assembling-machine": {
            SOURCE_MACHINE: {
                "type": "assembling-machine",
                "name": SOURCE_MACHINE,
                "crafting_speed": 2,
                "module_slots": 2,
                "crafting_categories": ["smelting", "bob-mixing-furnace"],
                "minable": {"result": SOURCE_MACHINE},
                "next_upgrade": "other-mixing-furnace",
            },
            SOURCE_METALLURGY_MACHINE: {
                "type": "assembling-machine",
                "name": SOURCE_METALLURGY_MACHINE,
                "crafting_speed": 4,
                "module_slots": 4,
                "crafting_categories": ["metallurgy"],
                "effect_receiver": {"base_effect": {"productivity": .5}},
                "fluid_boxes_off_when_no_fluid_recipe": True,
                "fluid_boxes": [
                    {"production_type": "input", "volume": 1000},
                    {"production_type": "input", "volume": 1000},
                    {"production_type": "output", "volume": 100},
                    {"production_type": "output", "volume": 100},
                ],
                "minable": {"result": SOURCE_METALLURGY_MACHINE},
                "next_upgrade": "other-foundry",
            },
        },
    }
    for route in ALLOY_ROUTES:
        raw["recipe"][route["recipe"]] = {
            "type": "recipe",
            "name": route["recipe"],
            "enabled": False,
            "allow_productivity": True,
            "energy_required": route["energy"],
            "categories": deepcopy(route["categories"]),
            "ingredients": deepcopy(route["ingredients"]),
            "results": deepcopy(route["results"]),
        }
        raw["technology"][route["owner"]] = {
            "type": "technology",
            "name": route["owner"],
            "effects": [{"type": "unlock-recipe", "recipe": route["recipe"]}],
        }
    return raw


class BobCoreGameplayFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS.read_text(encoding="utf-8"))
        cls.expected_ids = [
            family[stage]["id"]
            for family in cls.facts["families"]
            for stage in ("early", "continuation")
        ]

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().data_fixture = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control_fixture = (FIXTURE / "control.lua").as_posix()
        runner = (ROOT / "tools/Invoke-NativeFixture.ps1").read_text(encoding="utf-8")
        completed_save = re.findall(r"\$complete=Join-Path \$writeData 'saves/([^'/]+)\.zip'", runner)
        self.assertEqual(1, len(completed_save), "native runner must have one completed-save contract")
        self.expected_complete_save = completed_save[0]

    def run_data_fixture(self, raw):
        self.lua.globals().fixture_raw = lua_value(self.lua, raw)
        return self.lua.execute(r'''
          local function copy(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local out = {}
            seen[value] = out
            for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
            return out
          end
          table.deepcopy = copy
          data = {raw = fixture_raw}
          function data:extend(rows)
            for _, row in ipairs(rows) do
              self.raw[row.type][row.name] = row
            end
          end
          return pcall(assert(loadfile(data_fixture)))
        ''')

    def test_profile_and_fixture_pin_the_exact_no_angel_closure(self):
        base = json.loads(BASE_PROFILE.read_text(encoding="utf-8"))
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(base["engine"], profile["engine"])
        self.assertEqual(base["archive_sha256"], profile["archive_sha256"])
        self.assertEqual(base["source_selection"], profile["source_selection"])
        self.assertEqual(base["mods"] + [
            {"name": "more-infinite-research", "version": "5.0.21000", "enabled": True},
            {"name": "mir-fixture-mir5-bob-core-gameplay", "version": "0.1.0", "enabled": True},
        ], profile["mods"])
        self.assertEqual("mir5-bob-core-gameplay-native-selection", profile["kind"])
        self.assertIn("full-catalogue capture/comparison remains required", profile["scope"])
        self.assertNotIn("angelssmelting", {entry["name"] for entry in profile["mods"]})

        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-bob-core-gameplay", "0.1.0", "2.1"),
                         (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual([
            "base = 2.1.23", "space-age = 2.1.23", "boblibrary = 3.0.1",
            "bobores = 3.0.0", "bobplates = 3.0.2", "bobelectronics = 3.0.1",
            "bobtech = 3.0.0", "more-infinite-research = 5.0.21000",
        ], info["dependencies"])

    def test_data_preflight_matches_all_fourteen_independent_rows_then_changes_only_cost_and_time(self):
        raw = fixture_raw(self.facts)
        result = self.run_data_fixture(raw)
        self.assertTrue(result[0] if isinstance(result, tuple) else result,
                        result[1] if isinstance(result, tuple) else result)
        actual = self.lua.globals().data["raw"]["technology"]
        self.assertEqual(self.expected_ids, [
            family[stage]["id"]
            for family in self.facts["families"]
            for stage in ("early", "continuation")
        ])
        for family in self.facts["families"]:
            for stage_name in ("early", "continuation"):
                with self.subTest(family=family["key"], stage=stage_name):
                    stage = family[stage_name]
                    row = actual[stage["id"]]
                    self.assertEqual((stage["id"], stage["order"], stage["level"], stage["max_level"]),
                                     (row["name"], row["order"], row["level"], row["max_level"]))
                    self.assertEqual(stage["prerequisites"], [row["prerequisites"][index]
                                                                for index in range(1, len(stage["prerequisites"]) + 1)])
                    self.assertEqual(stage["science"], [row["unit"]["ingredients"][index][1]
                                                         for index in range(1, len(stage["science"]) + 1)])
                    self.assertEqual([route["recipe"] for route in family["routes"]],
                                     [row["effects"][index]["recipe"]
                                      for index in range(1, len(family["routes"]) + 1)])
                    self.assertEqual((None, 1, 1), (row["unit"]["count_formula"],
                                                    row["unit"]["count"], row["unit"]["time"]))
                    if stage_name == "early":
                        self.assertIsNone(row["show_levels_info"])
                        self.assertIsNone(row["visible_when_disabled"])
                    else:
                        self.assertEqual((False, True), (row["show_levels_info"], row["visible_when_disabled"]))
        source = self.lua.globals().data["raw"]["assembling-machine"][SOURCE_MACHINE]
        fixture = self.lua.globals().data["raw"]["assembling-machine"][FIXTURE_MACHINE]
        self.assertEqual((2, 2, ["smelting", "bob-mixing-furnace"]),
                         (source["crafting_speed"], source["module_slots"],
                          [source["crafting_categories"][index] for index in (1, 2)]))
        self.assertEqual((200, 0, None, None),
                         (fixture["crafting_speed"], fixture["module_slots"],
                          fixture["minable"], fixture["next_upgrade"]))
        metallurgy_source = self.lua.globals().data["raw"]["assembling-machine"][SOURCE_METALLURGY_MACHINE]
        metallurgy_fixture = self.lua.globals().data["raw"]["assembling-machine"][FIXTURE_METALLURGY_MACHINE]
        self.assertEqual((4, 4, ["metallurgy"], .5, True),
                         (metallurgy_source["crafting_speed"], metallurgy_source["module_slots"],
                          [metallurgy_source["crafting_categories"][1]],
                          metallurgy_source["effect_receiver"]["base_effect"]["productivity"],
                          metallurgy_source["fluid_boxes_off_when_no_fluid_recipe"]))
        self.assertEqual([(1000, "input"), (1000, "input"), (100, "output"), (100, "output")], [
            (metallurgy_source["fluid_boxes"][index]["volume"],
             metallurgy_source["fluid_boxes"][index]["production_type"])
            for index in range(1, 5)])
        self.assertEqual((200, 0, None, None, .5),
                         (metallurgy_fixture["crafting_speed"], metallurgy_fixture["module_slots"],
                          metallurgy_fixture["minable"], metallurgy_fixture["next_upgrade"],
                          metallurgy_fixture["effect_receiver"]["base_effect"]["productivity"]))
        for route in ALLOY_ROUTES:
            recipe = self.lua.globals().data["raw"]["recipe"][route["recipe"]]
            self.assertEqual(route["ingredients"], [
                {"type": recipe["ingredients"][index]["type"],
                 "name": recipe["ingredients"][index]["name"],
                 "amount": recipe["ingredients"][index]["amount"]}
                for index in range(1, len(route["ingredients"]) + 1)
            ])
            self.assertEqual(route["results"], [{
                "type": recipe["results"][1]["type"],
                "name": recipe["results"][1]["name"],
                "amount": recipe["results"][1]["amount"],
            }])

    def test_data_preflight_refuses_late_science_effect_or_continuation_boundary_drift_without_partial_acceleration(self):
        mutations = {
            "science": lambda rows: rows["recipe-prod-research_material_copper_tungsten-4"]
            ["unit"]["ingredients"].__setitem__(5, ["wrong-science", 1]),
            "effect": lambda rows: rows["recipe-prod-research_material_lead-1"]
            ["effects"].__setitem__(0, {"type": "change-recipe-productivity", "recipe": "bob-lead-plate", "change": 0.03}),
            "boundary": lambda rows: rows["recipe-prod-research_material_tin-4"].__setitem__("max_level", 3),
        }
        for name, mutate in mutations.items():
            with self.subTest(mutation=name):
                raw = fixture_raw(self.facts)
                mutate(raw["technology"])
                result = self.run_data_fixture(raw)
                self.assertFalse(result[0])
                for family in self.facts["families"]:
                    for stage_name in ("early", "continuation"):
                        row = self.lua.globals().data["raw"]["technology"][family[stage_name]["id"]]
                        self.assertIsNone(row["unit"]["count"])
                        self.assertEqual(family[stage_name]["count_formula"], row["unit"]["count_formula"])
                        self.assertEqual(30, row["unit"]["time"])
                self.assertIsNone(self.lua.globals().data["raw"]["assembling-machine"][FIXTURE_MACHINE])
                self.assertIsNone(self.lua.globals().data["raw"]["assembling-machine"][FIXTURE_METALLURGY_MACHINE])

    def test_data_preflight_refuses_captured_alloy_or_machine_drift_before_any_acceleration(self):
        mutations = {
            "alloy-input": lambda raw: raw["recipe"]["bob-bronze-alloy"]["ingredients"].__setitem__(0, {
                "type": "item", "name": "copper-plate", "amount": 4}),
            "alloy-independent-probability": lambda raw: raw["recipe"]["bob-bronze-alloy"]["results"][0]
            .__setitem__("independent_probability", .5),
            "alloy-extra-count-fraction": lambda raw: raw["recipe"]["bob-bronze-alloy"]["results"][0]
            .__setitem__("extra_count_fraction", .25),
            "alloy-ignored-by-productivity": lambda raw: raw["recipe"]["bob-bronze-alloy"]["results"][0]
            .__setitem__("ignored_by_productivity", 1),
            "alloy-ignored-by-stats-default": lambda raw: raw["recipe"]["bob-bronze-alloy"]["results"][0]
            .__setitem__("ignored_by_stats", 1),
            "alloy-owner": lambda raw: raw["technology"]["bob-zinc-processing"]["effects"].__setitem__(0, {
                "type": "unlock-recipe", "recipe": "wrong-route"}),
            "alloy-machine": lambda raw: raw["assembling-machine"][SOURCE_MACHINE].__setitem__("crafting_speed", 3),
            "invar-input": lambda raw: raw["recipe"]["bob-invar-alloy"]["ingredients"].__setitem__(1, {
                "type": "item", "name": "iron-plate", "amount": 4}),
            "nitinol-owner": lambda raw: raw["technology"]["bob-nitinol-processing"]["effects"].__setitem__(0, {
                "type": "unlock-recipe", "recipe": "wrong-route"}),
            "copper-tungsten-fluid": lambda raw: raw["recipe"]["bob-copper-tungsten-alloy"]["ingredients"].__setitem__(1, {
                "type": "fluid", "name": "molten-copper", "amount": 19}),
            "metallurgy-machine": lambda raw: raw["assembling-machine"][SOURCE_METALLURGY_MACHINE]
            ["effect_receiver"]["base_effect"].__setitem__("productivity", .4),
        }
        for name, mutate in mutations.items():
            with self.subTest(mutation=name):
                raw = fixture_raw(self.facts)
                mutate(raw)
                result = self.run_data_fixture(raw)
                self.assertFalse(result[0] if isinstance(result, tuple) else result)
                for family in self.facts["families"]:
                    for stage_name in ("early", "continuation"):
                        row = self.lua.globals().data["raw"]["technology"][family[stage_name]["id"]]
                        self.assertIsNone(row["unit"]["count"])
                        self.assertEqual(family[stage_name]["count_formula"], row["unit"]["count_formula"])
                self.assertIsNone(self.lua.globals().data["raw"]["assembling-machine"][FIXTURE_MACHINE])
                self.assertIsNone(self.lua.globals().data["raw"]["assembling-machine"][FIXTURE_METALLURGY_MACHINE])

    def test_control_registration_is_read_only(self):
        result = self.lua.execute(r'''
          local callbacks, reads = {events={}}, {}
          local environment = {
            script = {
              active_mods = {},
              on_init=function(callback) callbacks.init=callback end,
              on_load=function(callback) callbacks.load=callback end,
              on_event=function(event, callback) callbacks.events[event]=callback end,
            },
            defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
          }
          environment._G = environment
          setmetatable(environment, {__index=function(_, key)
            if key == "game" or key == "storage" then reads[key] = (reads[key] or 0) + 1 end
            return _G[key]
          end})
          local chunk = assert(loadfile(control_fixture, "t", environment))
          local ok, message = pcall(chunk)
          return {ok=ok,message=tostring(message),callbacks=callbacks,reads=reads}
        ''')
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNone(result["reads"]["game"])
        self.assertIsNone(result["reads"]["storage"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        self.assertIsNotNone(result["callbacks"]["events"][2])
        self.assertIn(f'local SAVE = "{self.expected_complete_save}"',
                      (FIXTURE / "control.lua").read_text(encoding="utf-8"))

    def test_physical_alloy_witness_requires_real_route_inputs_and_precedes_mir_research(self):
        self.lua.globals().spec = lua_value(self.lua, fixture_spec(self.facts))
        self.lua.globals().alloys = lua_value(self.lua, list(ALLOY_ROUTES))
        for opponent, expected in (
                ("", ""),
                ("wrong-output:bob-bronze-alloy", "native alloy output differs"),
                ("wrong-output:bob-invar-alloy", "native alloy output differs"),
                ("wrong-output:bob-nitinol-alloy", "native alloy output differs"),
                ("wrong-output:bob-copper-tungsten-alloy", "native alloy output differs"),
                ("independent-probability:bob-bronze-alloy", "native alloy result changed"),
                ("independent-probability:bob-invar-alloy", "native alloy result changed"),
                ("extra-count-fraction:bob-bronze-alloy", "native alloy result changed"),
                ("extra-count-fraction:bob-nitinol-alloy", "native alloy result changed"),
                ("ignored-by-productivity:bob-bronze-alloy", "native alloy result changed"),
                ("ignored-by-productivity:bob-copper-tungsten-alloy", "native alloy result changed"),
                ("ignored-by-stats:bob-copper-tungsten-alloy", "native alloy result changed"),
                ("changed-category:bob-copper-tungsten-alloy", "native alloy categories changed")):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent = opponent
                result = self.lua.execute(r'''
                  local callbacks, machines, started = {events={}}, {}, 0
                  local active = {
                    base="2.1.23", ["space-age"]="2.1.23", boblibrary="3.0.1", bobores="3.0.0",
                    bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
                    ["more-infinite-research"]="5.0.21000",
                    ["mir-fixture-mir5-bob-core-gameplay"]="0.1.0",
                  }
                  local function inventory()
                    local contents = {}
                    return {
                      contents=contents,
                      insert=function(stack) contents[stack.name] = (contents[stack.name] or 0) + stack.count; return stack.count end,
                      remove=function(stack)
                        local removed = math.min(contents[stack.name] or 0, stack.count)
                        contents[stack.name] = (contents[stack.name] or 0) - removed
                        return removed
                      end,
                      get_item_count=function(name) return contents[name] or 0 end,
                      is_empty=function() for _, count in pairs(contents) do if count ~= 0 then return false end end return true end,
                    }
                  end
                  local kind, target = opponent:match("^([^:]+):(.+)$")
                  local function alloy_machine(route)
                    local input, output, modules = inventory(), inventory(), inventory()
                    local fluids = {}
                    local machine = {
                      valid=true,crafting_progress=0,bonus_progress=0,productivity_bonus=route.inherent_productivity,
                      fluids_count=route.category == "metallurgy" and 4 or 0,
                      prototype={name=route.machine,crafting_categories={[route.category]=true}},
                    }
                    machine.set_recipe = function(name) machine.selected = {name=name}; return {} end
                    machine.get_recipe = function() return machine.selected end
                    machine.get_inventory = function(index)
                      if index == 1 then return input end
                      if index == 2 then return output end
                      if index == 3 then return modules end
                    end
                    machine.insert_fluid = function(fluid)
                      local capacity = 1000
                      local inserted = math.min(capacity - (fluids[fluid.name] or 0), fluid.amount)
                      fluids[fluid.name] = (fluids[fluid.name] or 0) + inserted
                      return inserted
                    end
                    machine.get_fluid_count = function(name) return fluids[name] or 0 end
                    machine.get_fluid_capacity = function(index)
                      return index <= 2 and 1000 or 100
                    end
                    machine.fluids = fluids
                    return machine
                  end
                  local player = {
                    valid=true,technologies={},recipes={},current_research=nil,research_queue={},
                    get_spawn_position=function() return {0, 0} end,
                    add_research=function() started = started + 1; return true end,
                  }
                  for _, family in ipairs(spec) do
                    local function technology(name, level, researched, maximum)
                      local effects = {}
                      for index, recipe in ipairs(family.recipes) do
                        effects[index] = {type="change-recipe-productivity", recipe=recipe, change=.02}
                        player.recipes[recipe] = {valid=true,enabled=true,productivity_bonus=0}
                      end
                      return {valid=true,name=name,level=level,researched=researched,enabled=true,
                        prototype={max_level=maximum,effects=effects},research_unit_count=1,research_unit_energy=60}
                    end
                    player.technologies[family.early] = technology(family.early, 1, false, 3)
                    player.technologies[family.tail] = technology(family.tail, 4, false, 4294967295)
                  end
                  for _, name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
                      "production-science-pack","space-science-pack","metallurgic-science-pack","bob-alloy-processing",
                      "bob-zinc-processing","bob-invar-processing","bob-nitinol-processing","bob-tungsten-processing"}) do
                    player.technologies[name] = {valid=true,name=name,researched=false,enabled=true}
                  end
                  local function copy_products(products)
                    local copied = {}
                    for index, product in ipairs(products) do
                      copied[index] = {}
                      for key, value in pairs(product) do copied[index][key] = value end
                    end
                    return copied
                  end
                  local proto_recipes = {}
                  for _, route in ipairs(alloys) do
                    local products = route.results
                    if route.recipe == target and (kind == "independent-probability"
                        or kind == "extra-count-fraction" or kind == "ignored-by-productivity"
                        or kind == "ignored-by-stats") then
                      products = copy_products(route.results)
                      if kind == "independent-probability" then products[1].independent_probability = .5 end
                      if kind == "extra-count-fraction" then products[1].extra_count_fraction = .25 end
                      if kind == "ignored-by-productivity" then products[1].ignored_by_productivity = 1 end
                      if kind == "ignored-by-stats" then products[1].ignored_by_stats = 1 end
                    end
                    local categories = route.categories
                    if route.recipe == target and kind == "changed-category" then categories = {"wrong-category"} end
                    proto_recipes[route.recipe] = {
                      name=route.recipe,energy=route.energy,maximum_productivity=3,
                      categories=categories,ingredients=route.ingredients,products=products,
                    }
                  end
                  local lab_input = inventory()
                  local lab = {valid=true,get_inventory=function(index) assert(index == 4); return lab_input end}
                  local surface = {create_entity=function(parameters)
                    if parameters.name == "lab" then return lab end
                    local route
                    for _, candidate in ipairs(alloys) do
                      if candidate.machine == parameters.name then route = candidate break end
                    end
                    assert(route, "unknown fixture machine")
                    local machine = alloy_machine(route)
                    machines[parameters.name .. tostring(parameters.position[1])] = machine
                    return machine
                  end}
                  local environment = {
                    script={active_mods=active,on_init=function(callback) callbacks.init=callback end,
                      on_load=function(callback) callbacks.load=callback end,
                      on_event=function(event, callback) callbacks.events[event]=callback end},
                    defines={events={on_tick=1,on_research_finished=2},inventory={crafter_input=1,crafter_output=2,crafter_modules=3,lab_input=4}},
                    prototypes={recipe=proto_recipes},
                    game={tick=1,speed=1,forces={player=player},surfaces={[1]=surface}}, storage={},
                  }
                  environment._G = environment
                  setmetatable(environment,{__index=function(_, key) return _G[key] end})
                  local chunk = assert(loadfile(control_fixture, "t", environment))
                  assert(pcall(chunk))
                  assert(pcall(callbacks.init))
                  local state = environment.storage.mir5_bob_core_gameplay
                  local function remaining_inputs(production)
                    for _, ingredient in ipairs(production.route.ingredients) do
                      if production.remaining[ingredient.name] ~= 0 then return true end
                    end
                    return false
                  end
                  local function finish_named_route()
                    local production = state.alloy
                    if not production then
                      local started_ok, started_message = pcall(callbacks.events[1])
                      if not started_ok then return false, started_message end
                      production = state.alloy
                    end
                    local recipe = production and production.recipe
                    if not recipe then return false, "alloy route did not start" end
                    for _ = 1, 4 do
                      local machine = state.alloy_machines[recipe]
                      local input = machine.get_inventory(1)
                      local output = machine.get_inventory(2)
                      for _, ingredient in ipairs(production.route.ingredients) do
                        if ingredient.type == "fluid" then machine.fluids[ingredient.name] = 0
                        else input.contents[ingredient.name] = 0 end
                      end
                      if not remaining_inputs(production) and output.get_item_count(production.route.result.name) == 0 then
                        local inherent_productivity = production.route.inherent_productivity or 0
                        local amount = production.route.result.amount * (100 + inherent_productivity * 100)
                        if kind == "wrong-output" and target == production.recipe then
                          amount = amount - production.route.result.amount
                        end
                        output.contents[production.route.result.name] = amount
                      end
                      local tick_ok, tick_message = pcall(callbacks.events[1])
                      if not tick_ok then return false, tick_message end
                      if state.alloy == nil or state.alloy.recipe ~= recipe then return true, tick_message end
                      production = state.alloy
                    end
                    return false, "alloy route did not finish"
                  end
                  local first_ok, first_message
                  for index = 1, #alloys do
                    first_ok, first_message = finish_named_route()
                    if not first_ok then break end
                  end
                  return {
                    first_ok=first_ok,first_message=tostring(first_message),
                    phase=state.phase,alloy_index=state.alloy_index,alloy_count=#alloys,
                    started=started,physical=state.physical,lab_automation=lab_input.get_item_count("automation-science-pack"),
                  }
                ''')
                if opponent:
                    self.assertFalse(result["first_ok"])
                    self.assertIn(expected, result["first_message"])
                else:
                    self.assertTrue(result["first_ok"], result["first_message"])
                    self.assertEqual(("researching", 1, len(ALLOY_ROUTES), 0, INITIAL_PACKS),
                                     (result["phase"], result["alloy_index"], result["alloy_count"],
                                      result["started"], result["lab_automation"]))
                    for route in ALLOY_ROUTES:
                        record = result["physical"]["physical-before"][route["recipe"]]
                        expected_bonus = ALLOY_CRAFTS * route["inherent_productivity"]
                        self.assertEqual((route["results"][0]["amount"] * (ALLOY_CRAFTS + expected_bonus),
                                          expected_bonus, 0),
                                         (record["output"], record["bonus_crafts"], record["native_bonus_progress"]))

    def test_saved_witness_is_read_only_and_rejects_lost_lab_or_physical_state(self):
        self.lua.globals().spec = lua_value(self.lua, fixture_spec(self.facts))
        self.lua.globals().alloys = lua_value(self.lua, list(ALLOY_ROUTES))
        self.lua.globals().consumption = lua_value(self.lua, CONSUMPTION)
        for opponent, expected in (
                ("", ""),
                ("lost-earned", "earned finite-three/tail-four"),
                ("lost-bonus", "native recipe productivity differs"),
                ("science", "science consumption differs"),
                ("lost-tail", "earned finite-three/tail-four"),
                ("physical-output:bob-bronze-alloy", "physical-after alloy record differs"),
                ("physical-output:bob-invar-alloy", "physical-after alloy record differs"),
                ("physical-output:bob-nitinol-alloy", "physical-after alloy record differs"),
                ("physical-output:bob-copper-tungsten-alloy", "physical-after alloy record differs"),
                ("physical-machine:bob-bronze-alloy", "physical-after native alloy machine state differs"),
                ("physical-machine:bob-invar-alloy", "physical-after native alloy machine state differs"),
                ("physical-machine:bob-nitinol-alloy", "physical-after native alloy machine state differs"),
                ("physical-machine:bob-copper-tungsten-alloy", "physical-after native alloy machine state differs"),
                ("physical-fluid:bob-copper-tungsten-alloy", "native alloy fluid input was not clean")):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent = opponent
                result = self.lua.execute(r'''
                  local callbacks, markers = {events={}}, 0
                  local kind, target = opponent:match("^([^:]+):(.+)$")
                  local active = {
                    base="2.1.23", ["space-age"]="2.1.23", boblibrary="3.0.1", bobores="3.0.0",
                    bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
                    ["more-infinite-research"]="5.0.21000",
                    ["mir-fixture-mir5-bob-core-gameplay"]="0.1.0",
                  }
                  local function inventory(contents)
                    return {
                      get_item_count=function(name) return contents[name] or 0 end,
                      is_empty=function() for _, count in pairs(contents) do if count ~= 0 then return false end end return true end,
                    }
                  end
                  local player = {valid=true, technologies={}, recipes={}, current_research=nil, research_queue={}}
                  for _, family in ipairs(spec) do
                    local function technology(name, level, researched, maximum)
                      local effects = {}
                      for index, recipe in ipairs(family.recipes) do
                        effects[index] = {type="change-recipe-productivity", recipe=recipe, change=.02}
                        player.recipes[recipe] = {valid=true,enabled=true,productivity_bonus=.08}
                      end
                      return {valid=true,name=name,level=level,researched=researched,enabled=true,
                        visible_when_disabled=false,prototype={max_level=maximum,effects=effects}}
                    end
                    player.technologies[family.early] = technology(family.early, 3, true, 3)
                    player.technologies[family.tail] = technology(family.tail, 5, false, 4294967295)
                  end
                  local proto_recipes, machines = {}, {}
                  for index, route in ipairs(alloys) do
                    proto_recipes[route.recipe] = {
                      name=route.recipe,energy=route.energy,maximum_productivity=3,
                      categories=route.categories,ingredients=route.ingredients,products=route.results,
                    }
                    local input, output, modules = inventory({}), inventory({}), inventory({})
                    local fluids = {}
                    machines[route.recipe] = {
                      valid=true,energy=index == 1 and 17 or 29,crafting_progress=0,bonus_progress=1,
                      productivity_bonus=route.inherent_productivity + .08,
                      fluids_count=route.category == "metallurgy" and 4 or 0,
                      prototype={name=route.machine,crafting_categories={[route.category]=true}},
                      get_inventory=function(index)
                        if index == 1 then return input end
                        if index == 2 then return output end
                        if index == 3 then return modules end
                      end,
                      get_fluid_count=function(name) return fluids[name] or 0 end,
                      get_fluid_capacity=function(index) return index <= 2 and 1000 or 100 end,
                      insert_fluid=function(fluid)
                        local inserted = math.min(1000 - (fluids[fluid.name] or 0), fluid.amount)
                        fluids[fluid.name] = (fluids[fluid.name] or 0) + inserted
                        return inserted
                      end,
                      fluids=fluids,
                    }
                  end
                  local remaining = {}
                  for name, count in pairs(consumption) do remaining[name] = 64 - count end
                  local lab = {valid=true,get_inventory=function(index)
                    assert(index == 4, "unexpected lab inventory")
                    return {get_item_count=function(name) return remaining[name] end}
                  end}
                  local plan = {}
                  for _, family in ipairs(spec) do
                    plan[#plan+1] = family.early
                    plan[#plan+1] = family.early
                    plan[#plan+1] = family.early
                    plan[#plan+1] = family.tail
                  end
                  local physical = {["physical-before"]={}, ["physical-after"]={}}
                  for _, route in ipairs(alloys) do
                    local baseline = route.inherent_productivity * 100
                    physical["physical-before"][route.recipe] = {
                      output=route.results[1].amount * (100 + baseline), bonus_crafts=baseline,
                      native_bonus_progress=0, machine_productivity_bonus=route.inherent_productivity,
                    }
                    physical["physical-after"][route.recipe] = {
                      output=route.results[1].amount * (100 + baseline + 7), bonus_crafts=baseline + 7,
                      native_bonus_progress=1, machine_productivity_bonus=route.inherent_productivity + .08,
                    }
                  end
                  local state = {
                    phase="complete",plan=plan,next=29,finished=28,events=28,lab=lab,
                    alloy_machines=machines,physical=physical,deadline=36000,
                  }
                  local environment = {
                    script={active_mods=active,on_init=function(callback) callbacks.init=callback end,
                      on_load=function(callback) callbacks.load=callback end,
                      on_event=function(event, callback) callbacks.events[event]=callback end},
                    defines={events={on_tick=1,on_research_finished=2},inventory={crafter_input=1,crafter_output=2,crafter_modules=3,lab_input=4}},
                    prototypes={recipe=proto_recipes},
                    game={tick=2,forces={player=player}}, storage={mir5_bob_core_gameplay=state},
                    helpers={table_to_json=function(value)
                      assert(value.case == "bob-core-gameplay" and value.stage == "reload"
                        and value.witnesses.actual_lab_completions == 28
                        and value.witnesses.physical_alloy_witness == true
                        and value.witnesses.physical_mixing_routes == 4
                        and value.witnesses.physical_metallurgy_fluid_routes == 1
                        and value.witnesses.physical_foundry_inherent_productivity == .5)
                      assert(#value.witnesses.physical_routes == #alloys)
                      for index, route in ipairs(alloys) do
                        assert(value.witnesses.physical_routes[index] == route.recipe)
                      end
                      return "{}"
                    end},
                    log=function(value) assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")); markers=markers+1 end,
                  }
                  environment._G = environment
                  setmetatable(environment,{__index=function(_, key) return _G[key] end})
                  local chunk = assert(loadfile(control_fixture, "t", environment))
                  assert(pcall(chunk))
                  local saved = {phase=state.phase,next=state.next,finished=state.finished,events=state.events,
                    outputs={},energies={}}
                  for _, route in ipairs(alloys) do
                    saved.outputs[route.recipe] = state.physical["physical-after"][route.recipe].output
                    saved.energies[route.recipe] = machines[route.recipe].energy
                  end
                  local function sentinel_energies_unchanged()
                    for _, route in ipairs(alloys) do
                      if machines[route.recipe].energy ~= saved.energies[route.recipe] then return false end
                    end
                    return true
                  end
                  local load_ok, load_message = pcall(callbacks.load)
                  local on_load_read_only = state.phase == saved.phase and state.next == saved.next
                    and state.finished == saved.finished and state.events == saved.events
                    and sentinel_energies_unchanged()
                  for _, route in ipairs(alloys) do
                    on_load_read_only = on_load_read_only
                      and state.physical["physical-after"][route.recipe].output == saved.outputs[route.recipe]
                  end
                  if opponent == "lost-earned" then player.technologies[spec[1].early].level = 2 end
                  if opponent == "lost-bonus" then player.recipes[spec[2].recipes[1]].productivity_bonus = .06 end
                  if opponent == "science" then remaining["metallurgic-science-pack"] = remaining["metallurgic-science-pack"] + 1 end
                  if opponent == "lost-tail" then player.technologies[spec[3].tail].level = 4 end
                  if kind == "physical-output" then state.physical["physical-after"][target].output = 0 end
                  if kind == "physical-machine" then machines[target].bonus_progress = 0 end
                  if kind == "physical-fluid" then machines[target].fluids["molten-copper"] = 1 end
                  local tick_ok, tick_message = pcall(callbacks.events[1])
                  return {load_ok=load_ok,load_message=tostring(load_message),on_load_read_only=on_load_read_only,
                    completed_observer_read_only=sentinel_energies_unchanged(),tick_ok=tick_ok,
                    tick_message=tostring(tick_message),markers=markers}
                ''')
                self.assertTrue(result["load_ok"], result["load_message"])
                self.assertTrue(result["on_load_read_only"])
                self.assertTrue(result["completed_observer_read_only"])
                if opponent:
                    self.assertFalse(result["tick_ok"])
                    self.assertIn(expected, result["tick_message"])
                    self.assertEqual(0, result["markers"])
                else:
                    self.assertTrue(result["tick_ok"], result["tick_message"])
                    self.assertEqual(1, result["markers"])

        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("on_research_finished", source)
        self.assertIn("actual_lab_completions=state.finished", source)
        self.assertIn("physical_before_mir_productivity=true", source)
        self.assertIn("candidate_full_catalogue_comparison_required=true", source)
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("enable_all_prototypes", source)
        self.assertNotIn("game.create_force", source)
        self.assertNotIn("force.research_queue =", source)
        self.assertNotIn("early.level =", source)
        self.assertNotIn("tail.level =", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobCoreGameplayFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Host controls for the private F200 K2 Base continuation native fixture.

These checks exercise the fixture preflight and its controlled callback flow.
They do not launch Factorio or qualify the native result.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/k2-base-continuations"
FACTS_PATH = ROOT / "tests/mir5/fixtures/k2-base-f200-captured-facts.json"

SPECS = (
    {
        "name": "braking-force-8", "level": 8,
        "prerequisites": ("braking-force-6", "braking-force-7", "automation-science-pack",
                          "logistic-science-pack", "chemical-science-pack", "production-science-pack",
                          "utility-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "production-science-pack", "utility-science-pack"),
        "formula": "861.51212960553*1.33333^(L-8)", "time": 60,
        "effects": (("train-braking-force-bonus", {"modifier": .15}),),
    },
    {
        "name": "inserter-capacity-bonus-8", "level": 8,
        "prerequisites": ("inserter-capacity-bonus-6", "utility-science-pack", "inserter-capacity-bonus-7",
                          "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                          "production-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "production-science-pack", "utility-science-pack"),
        "formula": "914488.340211249*3.33333^(L-8)", "time": 60,
        "effects": (
            ("inserter-stack-size-bonus", {"modifier": 2}),
            ("bulk-inserter-capacity-bonus", {"modifier": 4}),
        ),
    },
    {
        "name": "laser-shooting-speed-8", "level": 8,
        "prerequisites": ("laser-shooting-speed-6", "laser-shooting-speed-7", "automation-science-pack",
                          "logistic-science-pack", "chemical-science-pack", "military-science-pack",
                          "utility-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "military-science-pack", "utility-science-pack"),
        "formula": "1025.15625*1.5^(L-8)", "time": 120,
        "effects": (
            ("gun-speed", {"ammo_category": "laser", "modifier": .1}),
            ("gun-speed", {"ammo_category": "kr-impulse-rifle", "modifier": .1}),
        ),
    },
    {
        "name": "research-speed-7", "level": 7,
        "prerequisites": ("research-speed-5", "utility-science-pack", "research-speed-6",
                          "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                          "production-science-pack", "military-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "production-science-pack", "utility-science-pack", "military-science-pack"),
        "formula": "683.4375*1.5^(L-7)", "time": 120,
        "effects": (("laboratory-speed", {"modifier": .6}),),
    },
    {
        "name": "weapon-shooting-speed-7", "level": 7,
        "prerequisites": ("weapon-shooting-speed-5", "utility-science-pack", "weapon-shooting-speed-6",
                          "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                          "military-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "military-science-pack", "utility-science-pack"),
        "formula": "683.4375*1.5^(L-7)", "time": 120,
        "effects": (
            ("gun-speed", {"ammo_category": "bullet", "modifier": .15}),
            ("gun-speed", {"ammo_category": "shotgun-shell", "modifier": .15}),
            ("gun-speed", {"ammo_category": "kr-pistol", "modifier": .15}),
            ("gun-speed", {"ammo_category": "kr-anti-materiel-rifle-ammo", "modifier": .15}),
            ("gun-speed", {"ammo_category": "kr-railgun-shell", "modifier": .2}),
            ("gun-speed", {"ammo_category": "kr-turret-missile", "modifier": .2}),
            ("gun-speed", {"ammo_category": "kr-heavy-rocket", "modifier": .2}),
        ),
    },
    {
        "name": "worker-robots-storage-4", "level": 4,
        "prerequisites": ("worker-robots-storage-2", "utility-science-pack", "worker-robots-storage-3",
                          "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                          "production-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "production-science-pack", "utility-science-pack"),
        "formula": "675*1.5^(L-4)", "time": 60,
        "effects": (("worker-robot-storage", {"modifier": 1}),),
    },
    {
        "name": "recipe-prod-research_gears-1", "level": 1,
        "prerequisites": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                          "production-science-pack"),
        "science": ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                    "production-science-pack"),
        "formula": "8000*2^(L-1)", "time": 60,
        "effects": (
            ("change-recipe-productivity", {"recipe": "iron-gear-wheel", "change": .1}),
            ("change-recipe-productivity", {"recipe": "kr-iron-gear-wheel-from-enriched-iron", "change": .1}),
            ("change-recipe-productivity", {"recipe": "kr-iron-gear-wheel-from-iron-ore", "change": .1}),
        ),
    },
)
def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, nested in value.items():
            table[key] = _lua_value(lua, nested)
        return table
    if isinstance(value, (tuple, list)):
        table = lua.table()
        for index, nested in enumerate(value, start=1):
            table[index] = _lua_value(lua, nested)
        return table
    return value


class K2BaseNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().data_fixes_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          function load_k2_fixture(path, environment)
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk, message)
            local ok, result = pcall(chunk)
            return {ok=ok, message=tostring(result)}
          end

          function parse_k2_control(path)
            local callbacks, forbidden = {events={}}, {reads={}}
            local environment = {
              script = {
                active_mods = {base="2.0.77", Krastorio2="2.0.19", Krastorio2Assets="2.0.5",
                  ["more-infinite-research"]="5.0.20000"},
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end,
              },
              defines = {events={on_tick=1, on_research_finished=2}, inventory={lab_input=1}},
            }
            environment._G = environment
            setmetatable(environment, {__index=function(_, key)
              if key == "game" or key == "storage" then forbidden.reads[key] = (forbidden.reads[key] or 0) + 1 end
              return _G[key]
            end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk, message)
            local ok, result = pcall(chunk)
            return {ok=ok, message=tostring(result), callbacks=callbacks, forbidden=forbidden}
          end

          function run_k2_control(path, opponent)
            local plan = {
              {name="braking-force-8", level=8, prerequisites={"braking-force-6", "braking-force-7", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}, effects={{type="train-braking-force-bonus", modifier=.15}}},
              {name="inserter-capacity-bonus-8", level=8, prerequisites={"inserter-capacity-bonus-6", "utility-science-pack", "inserter-capacity-bonus-7", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}, effects={{type="inserter-stack-size-bonus", modifier=2}, {type="bulk-inserter-capacity-bonus", modifier=4}}},
              {name="laser-shooting-speed-8", level=8, prerequisites={"laser-shooting-speed-6", "laser-shooting-speed-7", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack"}, effects={{type="gun-speed", ammo_category="laser", modifier=.1}, {type="gun-speed", ammo_category="kr-impulse-rifle", modifier=.1}}},
              {name="research-speed-7", level=7, prerequisites={"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "military-science-pack"}, effects={{type="laboratory-speed", modifier=.6}}},
              {name="weapon-shooting-speed-7", level=7, prerequisites={"weapon-shooting-speed-5", "utility-science-pack", "weapon-shooting-speed-6", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack"}, effects={{type="gun-speed", ammo_category="bullet", modifier=.15}, {type="gun-speed", ammo_category="shotgun-shell", modifier=.15}, {type="gun-speed", ammo_category="kr-pistol", modifier=.15}, {type="gun-speed", ammo_category="kr-anti-materiel-rifle-ammo", modifier=.15}, {type="gun-speed", ammo_category="kr-railgun-shell", modifier=.2}, {type="gun-speed", ammo_category="kr-turret-missile", modifier=.2}, {type="gun-speed", ammo_category="kr-heavy-rocket", modifier=.2}}},
              {name="worker-robots-storage-4", level=4, prerequisites={"worker-robots-storage-2", "utility-science-pack", "worker-robots-storage-3", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}, effects={{type="worker-robot-storage", modifier=1}}},
              {name="recipe-prod-research_gears-1", level=1, prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}, science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}, effects={{type="change-recipe-productivity", recipe="iron-gear-wheel", change=.1}, {type="change-recipe-productivity", recipe="kr-iron-gear-wheel-from-enriched-iron", change=.1}, {type="change-recipe-productivity", recipe="kr-iron-gear-wheel-from-iron-ore", change=.1}}},
            }
            local science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "military-science-pack"}
            local gear_recipes = {"iron-gear-wheel", "kr-iron-gear-wheel-from-enriched-iron", "kr-iron-gear-wheel-from-iron-ore"}
            local function copied_effects(effects)
              local out = {}
              for i, effect in ipairs(effects) do
                out[i] = {}
                for key, value in pairs(effect) do out[i][key] = value end
              end
              return out
            end
            local function force_for(name, index)
              local force = {name=name, index=index, valid=true, technologies={}, recipes={}, research_queue={},
                research_queue_enabled=false,
                current_research=nil, train_braking_force_bonus=0, inserter_stack_size_bonus=0,
                bulk_inserter_capacity_bonus=0, laboratory_speed_modifier=0, worker_robots_storage_bonus=0, guns={}}
              function force.get_gun_speed_modifier(category) return force.guns[category] or 0 end
              function force.get_spawn_position(_) return {0, 0} end
              function force.add_research(technology)
                if force.research_queue_enabled ~= true then return false end
                table.insert(force.research_queue, technology)
                if not force.current_research then force.current_research = technology end
                return true
              end
              for _, recipe in ipairs(gear_recipes) do force.recipes[recipe] = {productivity_bonus=0} end
              for _, expected in ipairs(plan) do
                local prerequisites = {}
                for _, prerequisite in ipairs(expected.prerequisites) do prerequisites[prerequisite] = {name=prerequisite} end
                local technology = {name=expected.name, level=expected.level, researched=false, enabled=true,
                  visible_when_disabled=false, valid=true, force=force, research_unit_count=1,
                  research_unit_count_formula="1", research_unit_energy=60,
                  prototype={level=expected.level, max_level=4294967295, upgrade=true, prerequisites=prerequisites,
                    effects=copied_effects(expected.effects)}}
                force.technologies[expected.name] = technology
              end
              for _, expected in ipairs(plan) do
                for _, prerequisite in ipairs(expected.prerequisites) do
                  if not force.technologies[prerequisite] then
                    force.technologies[prerequisite] = {name=prerequisite, researched=false, valid=true}
                  end
                end
              end
              return force
            end
            local function apply_effect(force, technology)
              for _, effect in ipairs(technology.prototype.effects) do
                if effect.type == "train-braking-force-bonus" then force.train_braking_force_bonus = force.train_braking_force_bonus + effect.modifier
                elseif effect.type == "inserter-stack-size-bonus" then force.inserter_stack_size_bonus = force.inserter_stack_size_bonus + effect.modifier
                elseif effect.type == "bulk-inserter-capacity-bonus" then force.bulk_inserter_capacity_bonus = force.bulk_inserter_capacity_bonus + effect.modifier
                elseif effect.type == "laboratory-speed" then force.laboratory_speed_modifier = force.laboratory_speed_modifier + effect.modifier
                elseif effect.type == "worker-robot-storage" then force.worker_robots_storage_bonus = force.worker_robots_storage_bonus + effect.modifier
                elseif effect.type == "gun-speed" then force.guns[effect.ammo_category] = (force.guns[effect.ammo_category] or 0) + effect.modifier
                elseif effect.type == "change-recipe-productivity" then force.recipes[effect.recipe].productivity_bonus = force.recipes[effect.recipe].productivity_bonus + effect.change
                else error("unknown simulated effect " .. effect.type) end
              end
            end
            local player, foreign, markers, saves = force_for("player", 1), nil, 0, 0
            local inventory = {items={}}
            function inventory.insert(row) inventory.items[row.name] = (inventory.items[row.name] or 0) + row.count; return row.count end
            function inventory.get_item_count(name) return inventory.items[name] or 0 end
            local lab = {valid=true, energy=0}
            function lab.get_inventory(index) assert(index == 1); return inventory end
            local callbacks, storage = {events={}}, {}
            local game = {tick=100, forces={player=player, [1]=player}, surfaces={}}
            function game.create_force(name)
              foreign = force_for(name, 2)
              game.forces[name], game.forces[2] = foreign, foreign
              return foreign
            end
            game.surfaces[1] = {create_entity=function(row)
              assert(row.name == "kr-advanced-lab" and row.force == player)
              return lab
            end}
            function game.server_save(name) assert(name == "mir5-native-complete"); saves = saves + 1 end
            local environment = {
              script={active_mods={base="2.0.77", Krastorio2="2.0.19", Krastorio2Assets="2.0.5", ["more-infinite-research"]="5.0.20000"},
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end},
              defines={events={on_tick=1, on_research_finished=2}, inventory={lab_input=1}}, game=game, storage=storage,
              helpers={table_to_json=function(value)
                assert(value.case == "k2-base-continuations" and value.status == "passed")
                return "{}"
              end},
              log=function(message) assert(message:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")); markers = markers + 1 end,
            }
            environment._G = environment
            setmetatable(environment, {__index=function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk, message)
            local loaded, result = pcall(chunk)
            if not loaded then return {ok=false, message=tostring(result)} end
            local init_ok, init_message = pcall(callbacks.init)
            if not init_ok then return {ok=false, message=tostring(init_message)} end
            for index, expected in ipairs(plan) do
              local actual_index = index
              if opponent == "out-of-order" and index == 1 then actual_index = 3 end
              local technology = player.technologies[plan[actual_index].name]
              technology.level = technology.level + 1
              technology.researched = false
              apply_effect(player, technology)
              for _, pack in ipairs(plan[actual_index].science) do inventory.items[pack] = inventory.items[pack] - 1 end
              local event_ok, event_message = pcall(callbacks.events[2], {research=technology})
              if not event_ok then return {ok=false, message=tostring(event_message), markers=markers, saves=saves} end
              table.remove(player.research_queue, 1)
              player.current_research = player.research_queue[1]
            end
            if opponent == "lost-bonus" then player.guns.laser = player.guns.laser - .1 end
            if opponent == "not-advanced" then player.technologies[plan[1].name].level = plan[1].level end
            if opponent == "foreign" then foreign.technologies[plan[1].name].enabled = true end
            if opponent == "foreign-bonus" then foreign.guns.laser = .1 end
            if opponent == "science" then inventory.items["chemical-science-pack"] = inventory.items["chemical-science-pack"] + 1 end
            if opponent == "duplicate" then
              local event_ok, event_message = pcall(callbacks.events[2], {research=player.technologies[plan[1].name]})
              if not event_ok then return {ok=false, message=tostring(event_message), markers=markers, saves=saves} end
            end
            local tick_ok, tick_message = pcall(callbacks.events[1])
            if not tick_ok then return {ok=false, message=tostring(tick_message), markers=markers, saves=saves} end
            local state = storage["mir5_k2_base_continuations"]
            local saved = {phase=state.phase, finished=state.finished, events=state.events, queue_count=state.queue_count}
            local load_ok, load_message = pcall(callbacks.load)
            local read_only = state.phase == saved.phase and state.finished == saved.finished and state.events == saved.events and state.queue_count == saved.queue_count
            local reload_ok, reload_message = pcall(callbacks.events[1])
            return {ok=reload_ok, message=tostring(reload_message), load_ok=load_ok, load_message=tostring(load_message),
              on_load_read_only=read_only, phase=state.phase, finished=state.finished, events=state.events,
              queue_count=state.queue_count, markers=markers, saves=saves, foreign_name=foreign.name}
          end
        ''')

    def data_rows(self):
        rows = self.lua.table()
        for spec in SPECS:
            effects = self.lua.table()
            for index, (kind, fields) in enumerate(spec["effects"], start=1):
                effect = self.lua.table(type=kind)
                for key, value in fields.items():
                    effect[key] = value
                effects[index] = effect
            ingredients = self.lua.table()
            for index, pack in enumerate(spec["science"], start=1):
                ingredients[index] = self.lua.table(pack, 1)
            row = self.lua.table(
                type="technology", name=spec["name"], level=spec["level"], upgrade=True,
                max_level="infinite", prerequisites=_lua_value(self.lua, spec["prerequisites"]),
                effects=effects, unit=self.lua.table(count_formula=spec["formula"], time=spec["time"], ingredients=ingredients),
            )
            if spec["name"] != "recipe-prod-research_gears-1":
                row["hidden"] = False
            rows[spec["name"]] = row
        return rows

    def run_data_fixes(self, opponent=""):
        rows = self.data_rows()
        if opponent == "effect":
            rows["laser-shooting-speed-8"]["effects"][2]["modifier"] = .2
        elif opponent == "science":
            rows["research-speed-7"]["unit"]["ingredients"][6][1] = "space-science-pack"
        elif opponent == "formula":
            rows["recipe-prod-research_gears-1"]["unit"]["count_formula"] = "8001*2^(L-1)"
        environment = self.lua.table(
            data=self.lua.table(raw=self.lua.table(technology=rows)),
            mods=self.lua.table(base="2.0.77", Krastorio2="2.0.19", Krastorio2Assets="2.0.5",
                                **{"more-infinite-research": "5.0.20000"}),
        )
        environment["_G"] = environment
        self.lua.execute("setmetatable(..., {__index=function(_, key) return _G[key] end})", environment)
        result = self.lua.eval("load_k2_fixture")(self.lua.globals().data_fixes_path, environment)
        return result["ok"], str(result["message"]), rows

    def test_info_pins_the_disposable_fixture_to_f200_k2_base(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual("mir-fixture-mir5-k2-base-continuations", info["name"])
        self.assertEqual("0.1.0", info["version"])
        self.assertEqual("2.0", info["factorio_version"])
        self.assertEqual([
            "base >= 2.0.77", "Krastorio2 = 2.0.19", "Krastorio2Assets = 2.0.5",
            "more-infinite-research = 5.0.20000",
        ], info["dependencies"])

    def test_fixture_defaults_are_tied_to_committed_independent_k2_base_facts(self):
        facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        continuations = facts["continuations"]
        self.assertEqual(6, len(continuations))
        for spec, fact in zip(SPECS[:6], continuations):
            with self.subTest(name=spec["name"]):
                self.assertEqual(spec["name"], fact["id"])
                self.assertEqual(spec["formula"], fact["default"]["count_formula"])
                self.assertEqual(spec["time"], fact["default"]["time"])
                self.assertEqual(list(spec["science"]), fact["default"]["science"])
                self.assertEqual(
                    [{"type": kind, **fields} for kind, fields in spec["effects"]],
                    fact["default"]["effects"],
                )
        gear_facts = facts["captured_native_subset"]["gear"]
        self.assertEqual("iron-gear-wheel", gear_facts["recipe"])
        self.assertEqual("__Krastorio2Assets__/icons/items/iron-gear-wheel.png", gear_facts["native_item_icon"])
        self.assertTrue({"iron-gear-wheel", "kr-iron-gear-wheel-from-enriched-iron",
                         "kr-iron-gear-wheel-from-iron-ore"}.issubset(
            set(facts["captured_native_subset"]["native_recipe_names"])
        ))

    def test_data_preflight_validates_every_default_row_then_accelerates_only_cost_and_time(self):
        ok, message, rows = self.run_data_fixes()
        self.assertTrue(ok, message)
        for spec in SPECS:
            with self.subTest(name=spec["name"]):
                row = rows[spec["name"]]
                self.assertEqual(spec["level"], row["level"])
                self.assertTrue(row["upgrade"])
                self.assertEqual("infinite", row["max_level"])
                self.assertIsNone(row["unit"]["count"])
                self.assertEqual("1", row["unit"]["count_formula"])
                self.assertEqual(1, row["unit"]["time"])
                self.assertEqual(list(spec["prerequisites"]), [row["prerequisites"][i]
                    for i in range(1, len(spec["prerequisites"]) + 1)])
                self.assertEqual(list(spec["science"]), [row["unit"]["ingredients"][i][1]
                    for i in range(1, len(spec["science"]) + 1)])
                for index, (kind, fields) in enumerate(spec["effects"], start=1):
                    self.assertEqual(kind, row["effects"][index]["type"])
                    for key, value in fields.items():
                        self.assertEqual(value, row["effects"][index][key])

    def test_bad_default_is_rejected_before_any_row_is_accelerated(self):
        for opponent, phrase in (("effect", "effects changed"), ("science", "science changed"),
                                 ("formula", "default cost or time changed")):
            with self.subTest(opponent=opponent):
                ok, message, rows = self.run_data_fixes(opponent)
                self.assertFalse(ok)
                self.assertIn(phrase, message)
                for spec in SPECS:
                    row = rows[spec["name"]]
                    self.assertIsNone(row["unit"]["count"])
                    expected_formula = ("8001*2^(L-1)" if opponent == "formula"
                                        and spec["name"] == "recipe-prod-research_gears-1" else spec["formula"])
                    self.assertEqual(expected_formula, row["unit"]["count_formula"])
                    self.assertEqual(spec["time"], row["unit"]["time"])

    def test_control_registration_is_read_only_and_uses_one_native_queue_and_lab(self):
        result = self.lua.eval("parse_k2_control")(self.lua.globals().control_path)
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNone(result["forbidden"]["reads"]["game"])
        self.assertIsNone(result["forbidden"]["reads"]["storage"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        self.assertIsNotNone(result["callbacks"]["events"][2])
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('name = "kr-advanced-lab"', source)
        self.assertIn("defines.inventory.lab_input", source)
        self.assertIn("force.add_research", source)
        self.assertIn("force.research_queue_enabled = true", source)
        self.assertIn("#force.research_queue ~= #PLAN", source)
        self.assertIn("game.server_save(SAVE)", source)
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("enable_all_prototypes", source)
        self.assertNotIn("force.research_queue =", source)

    def test_seven_native_completion_events_effects_science_foreign_state_and_cold_reload(self):
        result = self.lua.eval("run_k2_control")(self.lua.globals().control_path, "")
        self.assertTrue(result["ok"], result["message"])
        self.assertTrue(result["load_ok"], result["load_message"])
        self.assertTrue(result["on_load_read_only"])
        self.assertEqual("complete", result["phase"])
        self.assertEqual((7, 7, 7), (result["finished"], result["events"], result["queue_count"]))
        self.assertEqual(2, result["markers"])
        self.assertEqual(1, result["saves"])
        self.assertEqual("mir5-k2-base-continuations-foreign", result["foreign_name"])

    def test_completion_order_and_reloaded_state_opponents_are_rejected(self):
        for opponent, phrase in (
            ("out-of-order", "unexpected native research completion"),
            ("not-advanced", "did not retain its one completed native level"),
            ("duplicate", "unexpected native research completion"),
            ("lost-bonus", "native gun-speed effect changed"),
            ("foreign", "foreign disabled state changed"),
            ("foreign-bonus", "foreign gun bonus changed"),
            ("science", "science consumption changed"),
        ):
            with self.subTest(opponent=opponent):
                result = self.lua.eval("run_k2_control")(self.lua.globals().control_path, opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(K2BaseNativeFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

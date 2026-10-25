"""Host controls for the F200 Base save -> F210 Base catalogue successor.

This establishes fixture and callback boundaries only. It is not native save,
migration, physical-output, or performance qualification.
"""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/full-catalogue-upgrade"
F200 = FIXTURE / "published-4.7"
F200_CROSS = FIXTURE / "f200/cross-to-f210"
F210 = FIXTURE / "f210"
CROSS = F210 / "cross-from-f200"
SHARED = FIXTURE / "shared"
SCIENCE = "recipe-prod-research_science_pack_productivity-1"
SCIENCE_INGREDIENTS = [[name, 1] for name in (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "utility-science-pack",
)]
SCIENCE_EFFECTS = [
    {"type": "change-recipe-productivity", "recipe": name, "change": .1}
    for name in (
        "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
        "military-science-pack", "production-science-pack", "utility-science-pack",
    )
]
GEAR_INGREDIENTS = [[name, 1] for name in (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
)]


def py(value):
    if hasattr(value, "items"):
        items = list(value.items())
        keys = [key for key, _ in items]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in items}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class F200F210CatalogueUpgradeFixtureTests(unittest.TestCase):
    def load_cross_catalogue(self):
        self.lua.globals().cross_catalogue_path = CROSS.joinpath("catalogue.lua").as_posix()
        self.lua.globals().f210_catalogue_path = SHARED.joinpath("f210-catalogue.lua").as_posix()
        self.lua.execute("""
          function load_cross_catalogue()
            local env = {}
            env.require = function(name)
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", env))()
            end
            env._G = env; setmetatable(env, {__index=_G})
            return assert(loadfile(cross_catalogue_path, "t", env))()
          end
        """)
        return py(self.lua.eval("load_cross_catalogue")())

    def load_cross_source_catalogue(self):
        self.lua.globals().cross_source_catalogue_path = F200_CROSS.joinpath("catalogue.lua").as_posix()
        self.lua.globals().f210_catalogue_path = SHARED.joinpath("f210-catalogue.lua").as_posix()
        self.lua.execute("""
          function load_cross_source_catalogue()
            local env = {}
            env.require = function(name)
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", env))()
            end
            env._G = env; setmetatable(env, {__index=_G})
            return assert(loadfile(cross_source_catalogue_path, "t", env))()
          end
        """)
        return py(self.lua.eval("load_cross_source_catalogue")())

    def test_cross_catalogue_restores_only_f200_base_state_and_recipe_coverage(self):
        source = py(self.lua.execute(f"return assert(loadfile({F200.joinpath('catalogue.lua').as_posix()!r}))()"))
        ordinary = py(self.lua.execute(f"return assert(loadfile({SHARED.joinpath('f210-catalogue.lua').as_posix()!r}))()"))
        cross_source = self.load_cross_source_catalogue()
        cross = self.load_cross_catalogue()
        source_state = [row["name"] for row in source["base"]["state"]]
        ordinary_state = [row["name"] for row in ordinary["base"]["state"]]
        cross_state = [row["name"] for row in cross["base"]["state"]]
        self.assertNotIn(SCIENCE, ordinary_state)
        self.assertEqual(source_state, cross_state)
        self.assertEqual(source_state, [row["name"] for row in cross_source["base"]["state"]])
        self.assertEqual(source["force_fields"], cross_source["force_fields"])
        self.assertEqual(("f200", "2.0.77", "4.7.20003", "0.2.1"), (cross_source["target"]["id"], cross_source["target"]["version"], cross_source["target"]["published_mir"], cross_source["target"]["source_fixture_version"]))
        self.assertEqual(1, cross_state.count(SCIENCE))
        self.assertEqual(set(source["base"]["recipes"]), set(cross["base"]["recipes"]))
        self.assertEqual({effect["recipe"] for effect in SCIENCE_EFFECTS}, set(source["base"]["recipes"]) - set(ordinary["base"]["recipes"]))
        self.assertEqual(ordinary["space_age"], cross["space_age"])

    def test_data_preflight_requires_science_before_gear_acceleration(self):
        self.lua.globals().cross_data_path = CROSS.joinpath("data-final-fixes.lua").as_posix()
        self.lua.globals().common_data_path = SHARED.joinpath("data-final-fixes.lua").as_posix()
        self.lua.globals().cross_catalogue_path = CROSS.joinpath("catalogue.lua").as_posix()
        self.lua.globals().f210_catalogue_path = SHARED.joinpath("f210-catalogue.lua").as_posix()
        self.lua.execute("""
          function run_cross_data(path, catalogue_path, raw, mods)
            local env = {data={raw=raw}, mods=mods}
            env.require = function(name)
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_data_final" then
                return assert(loadfile(common_data_path, "t", env))()
              elseif name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue_path, "t", env))()
              end
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", env))()
            end
            env._G = env; setmetatable(env, {__index=_G})
            local ok, message = pcall(function() assert(loadfile(path, "t", env))() end)
            return {ok=ok, message=tostring(message), raw=raw}
          end
        """)
        science = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 120, "ingredients": SCIENCE_INGREDIENTS}, "effects": SCIENCE_EFFECTS}
        gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 60, "ingredients": GEAR_INGREDIENTS}, "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]}
        mods = {"base": "2.1.23", "more-infinite-research": "5.0.21000", "mir-fixture-mir5-full-catalogue-upgrade": "0.3.0"}
        raw = {"technology": {SCIENCE: science, "recipe-prod-research_gears-1": gear}, "unchanged": {"sentinel": 17}}
        result = self.lua.eval("run_cross_data")(CROSS.joinpath("data-final-fixes.lua").as_posix(), CROSS.joinpath("catalogue.lua").as_posix(), lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods))
        actual = py(result["raw"])
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(science, actual["technology"][SCIENCE])
        self.assertEqual((None, "1", 1), tuple(actual["technology"]["recipe-prod-research_gears-1"]["unit"].get(key) for key in ("count", "count_formula", "time")))
        self.assertEqual(17, actual["unchanged"]["sentinel"])
        for label, altered, altered_mods in (
            ("missing", None, mods),
            ("wrong-effect", {**science, "effects": SCIENCE_EFFECTS[:-1]}, mods),
            ("space-age", science, {**mods, "space-age": "2.1.23"}),
        ):
            raw_input = {"technology": {"recipe-prod-research_gears-1": copy.deepcopy(gear)}, "unchanged": {"sentinel": 17}}
            if altered is not None:
                raw_input["technology"][SCIENCE] = copy.deepcopy(altered)
            before = copy.deepcopy(raw_input)
            with self.subTest(label=label):
                rejected = self.lua.eval("run_cross_data")(CROSS.joinpath("data-final-fixes.lua").as_posix(), CROSS.joinpath("catalogue.lua").as_posix(), lua(self.lua, raw_input), lua(self.lua, altered_mods))
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, py(rejected["raw"]))
                if label != "space-age": self.assertIn("F200 science productivity", str(rejected["message"]))

        source_mods = {"base": "2.0.77", "more-infinite-research": "4.7.20003", "mir-fixture-mir5-full-catalogue-upgrade": "0.2.1"}
        source_result = self.lua.eval("run_cross_data")(F200_CROSS.joinpath("data-final-fixes.lua").as_posix(), F200_CROSS.joinpath("catalogue.lua").as_posix(), lua(self.lua, copy.deepcopy(raw)), lua(self.lua, source_mods))
        self.assertTrue(source_result["ok"], source_result["message"])
        source_actual = py(source_result["raw"])
        self.assertEqual(science, source_actual["technology"][SCIENCE])
        self.assertEqual((None, "1", 1), tuple(source_actual["technology"]["recipe-prod-research_gears-1"]["unit"].get(key) for key in ("count", "count_formula", "time")))

    def test_callbacks_preserve_f200_state_through_successor_and_cold_reload(self):
        for name, path in {
            "source_control_path": F200_CROSS / "control.lua", "source_catalogue_path": F200_CROSS / "catalogue.lua",
            "cross_control_path": CROSS / "control.lua", "cross_catalogue_path": CROSS / "catalogue.lua",
            "common_control_path": SHARED / "control.lua", "f210_catalogue_path": SHARED / "f210-catalogue.lua",
        }.items(): self.lua.globals()[name] = path.as_posix()
        self.lua.execute("""
          function run_cross_callbacks()
            local f210_plan = assert(loadfile(f210_catalogue_path))()
            local source_env = {}
            source_env.require=function(name)
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", source_env))()
            end
            source_env._G=source_env; setmetatable(source_env,{__index=_G})
            local source_plan = assert(loadfile(source_catalogue_path, "t", source_env))().base
            local cross_env = {}
            cross_env.require=function(name)
              assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
              return assert(loadfile(f210_catalogue_path, "t", cross_env))()
            end
            cross_env._G=cross_env; setmetatable(cross_env, {__index=_G})
            local cross_plan = assert(loadfile(cross_catalogue_path, "t", cross_env))().base
            local names, recipes = {}, {}
            local function collect(plan)
              for _, row in ipairs(plan.state) do names[row.name] = true end
              for _, name in ipairs(plan.native_owners) do names[name] = true end
              for _, name in ipairs(plan.credits) do names[name] = true end
              for _, name in ipairs(plan.recipes) do recipes[name] = true end
            end
            collect(source_plan); collect(cross_plan)
            local inventory, contents = {}, {}
            function inventory.clear() contents = {} end
            function inventory.insert(stack) contents[stack.name] = (contents[stack.name] or 0) + stack.count; return stack.count end
            local energy = 0
            local lab = {valid=true, get_inventory=function(slot) assert(slot == 1); return inventory end}
            setmetatable(lab, {__index=function(_, key) if key == "energy" then return energy end end,
              __newindex=function(_, key, value) if key == "energy" then energy=value else rawset(_, key, value) end end})
            local function make_force(index)
              local force = {index=index, technologies={}, recipes={}, research_progress=0}
              setmetatable(force, {__newindex=function(target, key, value)
                rawset(target, key, value); if key == "research_queue" then rawset(target, "current_research", value[1]) end
              end})
              for name, _ in pairs(names) do
                local credit = string.sub(name, 1, 18) == "mir-native-credit-"
                force.technologies[name] = {valid=true, name=name, force=force,
                  prototype={max_level=4294967295, level=0, hidden=credit}, level=credit and 1 or 0,
                  researched=false, enabled=not credit, visible_when_disabled=not credit, saved_progress=0,
                  prerequisites={}, research_recursive=function() end}
              end
              force.technologies["recipe-prod-research_gears-1"].research_unit_ingredients = {
                {name="automation-science-pack", amount=1}, {name="logistic-science-pack", amount=1},
                {name="chemical-science-pack", amount=1}, {name="production-science-pack", amount=1},
              }
              force.technologies["braking-force-1"] = {valid=true, name="braking-force-1", force=force,
                prototype={max_level=4294967295, level=0, hidden=false}, level=0, researched=false, enabled=true,
                visible_when_disabled=true, saved_progress=0, prerequisites={}, research_recursive=function() end}
              for name, _ in pairs(recipes) do force.recipes[name] = {valid=true, productivity_bonus=0} end
              for _, field in ipairs(f210_plan.force_fields) do force[field] = 0 end
              function force.enable_all_prototypes() end; function force.reset_technology_effects() end
              function force.get_gun_speed_modifier() return 0 end
              function force.add_research(value) return value.name == "recipe-prod-research_gears-1" end
              return force
            end
            local player = make_force(1)
            local game = {tick=0, forces={player=player}, surfaces={[1]={create_entity=function() return lab end}}}
            function game.create_force() local paused=make_force(2); game.forces[paused.index]=paused; return paused end
            function game.server_save(name) game.saved=name end
            local storage = {}
            local function load_stage(control_path, catalogue_path, mods)
              local callbacks, env = {events={}}, {}
              env.script={active_mods=mods, on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                on_configuration_changed=function(fn) callbacks.configuration=fn end, on_event=function(event, fn) callbacks.events[event]=fn end}
              env.defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
              env.game,env.storage,env.helpers,env.log=game,storage,{table_to_json=function() return "{}" end},function() end
              env.require=function(name)
                if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_control" then return assert(loadfile(common_control_path,"t",env))() end
                if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then return assert(loadfile(catalogue_path,"t",env))() end
                assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
                return assert(loadfile(f210_catalogue_path,"t",env))()
              end
              env._G=env; setmetatable(env,{__index=_G}); assert(loadfile(control_path,"t",env))(); return callbacks
            end
            local source=load_stage(source_control_path,source_catalogue_path,{base="2.0.77",["more-infinite-research"]="4.7.20003",["mir-fixture-mir5-full-catalogue-upgrade"]="0.2.1"})
            source.init(); local gear=player.technologies["recipe-prod-research_gears-1"]
            gear.level=gear.level+1; player.recipes["iron-gear-wheel"].productivity_bonus=.1; source.events[1]{research=gear}; source.events[2]()
            local science_before=player.technologies["recipe-prod-research_science_pack_productivity-1"].level
            local successor=load_stage(cross_control_path,cross_catalogue_path,{base="2.1.23",["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-full-catalogue-upgrade"]="0.3.0"})
            successor.configuration(); gear.level=gear.level+1; gear.saved_progress=0; player.recipes["iron-gear-wheel"].productivity_bonus=.2
            successor.events[1]{research=gear}; successor.events[2](); successor.load(); successor.events[2]()
            local paused, state=game.forces[2],storage.mir5_full_catalogue_upgrade
            return {phase=state.phase,source_labs=state.source_labs,successor_labs=state.successor_labs,saved=game.saved,
              current=player.current_research and player.current_research.name,queue={player.research_queue[1].name,player.research_queue[2].name},progress=player.research_progress,
              paused_progress=paused.technologies["recipe-prod-research_gears-1"].saved_progress,science_before=science_before,
              science_after=player.technologies["recipe-prod-research_science_pack_productivity-1"].level,
              science_researched=player.technologies["recipe-prod-research_science_pack_productivity-1"].researched,
              probe_researched=player.technologies["braking-force-1"].researched,gear_bonus=player.recipes["iron-gear-wheel"].productivity_bonus}
          end
        """)
        result = py(self.lua.eval("run_cross_callbacks")())
        self.assertEqual("successor-completed", result["phase"])
        self.assertEqual((1, 1, "mir5-native-complete"), (result["source_labs"], result["successor_labs"], result["saved"]))
        self.assertEqual(("recipe-prod-research_gears-1", ["recipe-prod-research_gears-1", "braking-force-1"], .42), (result["current"], result["queue"], result["progress"]))
        self.assertEqual((.27, 1, 1, False, False, .2), (result["paused_progress"], result["science_before"], result["science_after"], result["science_researched"], result["probe_researched"], result["gear_bonus"]))

    def test_cross_fixture_staging_is_explicit_and_does_not_import_player_source(self):
        info = json.loads(CROSS.joinpath("info.json").read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-full-catalogue-upgrade", "0.3.0", "2.1"), (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual(["base = 2.1.23", "? elevated-rails = 2.1.23", "? quality = 2.1.23", "? recycler = 2.1.23", "? space-age = 2.1.23", "more-infinite-research = 5.0.21000"], info["dependencies"])
        for path in [*CROSS.glob("*.lua"), *F200_CROSS.glob("*.lua")]:
            self.assertNotIn("__more-infinite-research__", path.read_text(encoding="utf-8"))
        source_info = json.loads(F200_CROSS.joinpath("info.json").read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-full-catalogue-upgrade", "0.2.1", "2.0"), (source_info["name"], source_info["version"], source_info["factorio_version"]))
        self.assertIn("more-infinite-research = 4.7.20003", source_info["dependencies"])
        self.assertIn("native research, save, migration and performance qualification remain separate", FIXTURE.joinpath("README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    F200F210CatalogueUpgradeFixtureTests.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(F200F210CatalogueUpgradeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

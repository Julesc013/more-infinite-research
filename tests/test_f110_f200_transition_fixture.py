"""Host controls for the published F110 -> MIR5 F200 transition fixture.

These controls exercise staged fixture callbacks and source preflight only.
They are not a native save, migration, performance, or release result.
"""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/f110-f200-transition"
SHARED = FIXTURE / "shared"
SOURCE = FIXTURE / "f110/published-4.7.3"
SUCCESSOR = FIXTURE / "f200/mir5"
DIRECT = "recipe-prod-research_character_mining_speed-1"
CONTINUATION = "inserter-capacity-bonus-8"


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


class F110F200TransitionFixtureTests(unittest.TestCase):
    def load_catalogue(self, path):
        return py(self.lua.execute(f"return assert(loadfile({path.as_posix()!r}))()"))

    def run_data(self, path, catalogue, raw, mods):
        self.lua.globals().data_path = path.as_posix()
        self.lua.globals().catalogue_path = catalogue.as_posix()
        self.lua.globals().shared_data_path = SHARED.joinpath("data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          function f110_f200_run_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              if name == "__mir-fixture-mir5-f110-f200-transition__/catalogue" then
                return assert(loadfile(catalogue_path,"t",env))()
              end
              assert(name == "__mir-fixture-mir5-f110-f200-transition__/fixture_data_final")
              return assert(loadfile(shared_data_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return self.lua.eval("f110_f200_run_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods))

    def test_catalogue_is_exact_f110_direct_and_continuation_union(self):
        source = self.load_catalogue(SOURCE / "catalogue.lua")
        successor = self.load_catalogue(SUCCESSOR / "catalogue.lua")
        direct = json.loads((ROOT / "tests/fixtures/historical-direct-native-oracle.json").read_text(encoding="utf-8"))
        continuations = json.loads((ROOT / "tests/fixtures/historical-continuation-native-oracle.json").read_text(encoding="utf-8"))
        direct_rows = next(row for row in direct["captures"] if row["target"] == "f110")["technologies"]
        continuation_rows = next(row for row in continuations["captures"] if row["target"] == "f110")["technologies"]
        expected = {row["id"] for row in direct_rows} | {row["id"] for row in continuation_rows}
        self.assertEqual(17, len(expected))
        for plan, stage in ((source, "source"), (successor, "successor")):
            with self.subTest(stage=stage):
                self.assertEqual(stage, plan["stage"])
                self.assertEqual((DIRECT, CONTINUATION, "braking-force-1"),
                                 (plan["direct"], plan["continuation"], plan["probe"]))
                self.assertEqual(17, len(plan["rows"]))
                self.assertEqual(expected, set(plan["rows"]))
        inserter = next(row for row in continuation_rows if row["id"] == CONTINUATION)
        self.assertEqual([{"type": "inserter-stack-size-bonus", "modifier": 2},
                          {"type": "stack-inserter-capacity-bonus", "modifier": 4}],
                         [inserter["definition"]["effects"][key]
                          for key in sorted(inserter["definition"]["effects"], key=int)])

    def test_stage_preflights_accelerate_only_verified_mining_row(self):
        raw = {"technology": {DIRECT: {
            "name": DIRECT, "level": 1, "upgrade": True, "max_level": "infinite", "enabled": True,
            "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                     "ingredients": [["military-science-pack", 1], ["utility-science-pack", 1]]},
            "effects": [{"type": "character-mining-speed", "modifier": .05}],
        }}, "sentinel": {"value": 17}}
        mods = {"base": "1.1.110", "more-infinite-research": "4.7.11003",
                "mir-fixture-mir5-f110-f200-transition": "0.1.0"}
        accepted = self.run_data(SOURCE / "data-final-fixes.lua", SOURCE / "catalogue.lua", raw, mods)
        self.assertTrue(accepted["ok"], accepted["message"])
        actual = py(accepted["raw"])
        self.assertEqual((1, None, 1), tuple(actual["technology"][DIRECT]["unit"].get(key)
                                               for key in ("count", "count_formula", "time")))
        self.assertEqual(raw["technology"][DIRECT]["effects"], actual["technology"][DIRECT]["effects"])
        self.assertEqual(17, actual["sentinel"]["value"])
        for label, altered, altered_mods in (
            ("effect", {**raw["technology"][DIRECT], "effects": [{"type": "character-mining-speed", "modifier": .1}]}, mods),
            ("science", {**raw["technology"][DIRECT], "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                        "ingredients": [["utility-science-pack", 1], ["military-science-pack", 1]]}}, mods),
            ("closure", raw["technology"][DIRECT], {**mods, "more-infinite-research": "4.7.11002"}),
        ):
            candidate = copy.deepcopy(raw)
            candidate["technology"][DIRECT] = copy.deepcopy(altered)
            before = copy.deepcopy(candidate)
            with self.subTest(label=label):
                rejected = self.run_data(SOURCE / "data-final-fixes.lua", SOURCE / "catalogue.lua", candidate, altered_mods)
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, py(rejected["raw"]))

        successor_raw = {"technology": {DIRECT: {
            "name": DIRECT, "level": 1, "upgrade": True, "max_level": "infinite", "enabled": True,
            "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                     "ingredients": [["utility-science-pack", 1], ["military-science-pack", 1]]},
            "effects": [{"type": "character-mining-speed", "modifier": .05}],
        }}}
        successor_mods = {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                          "mir-fixture-mir5-f110-f200-transition": "0.2.0"}
        accepted = self.run_data(SUCCESSOR / "data-final-fixes.lua", SUCCESSOR / "catalogue.lua",
                                 successor_raw, successor_mods)
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual((1, None, 1), tuple(py(accepted["raw"])["technology"][DIRECT]["unit"].get(key)
                                               for key in ("count", "count_formula", "time")))
        for label, altered in (
            ("ingredients", {**successor_raw["technology"][DIRECT], "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                "ingredients": [["military-science-pack", 1], ["utility-science-pack", 1]]}}),
            ("effect", {**successor_raw["technology"][DIRECT], "effects": [{"type": "character-mining-speed", "modifier": .1}]}),
        ):
            candidate = copy.deepcopy(successor_raw)
            candidate["technology"][DIRECT] = copy.deepcopy(altered)
            before = copy.deepcopy(candidate)
            with self.subTest(successor=label):
                rejected = self.run_data(SUCCESSOR / "data-final-fixes.lua", SUCCESSOR / "catalogue.lua", candidate, successor_mods)
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, py(rejected["raw"]))

    def test_callbacks_preserve_17_rows_and_translate_only_capacity_token(self):
        paths = {
            "source_control_path": SOURCE / "control.lua", "source_catalogue_path": SOURCE / "catalogue.lua",
            "successor_control_path": SUCCESSOR / "control.lua", "successor_catalogue_path": SUCCESSOR / "catalogue.lua",
            "shared_control_path": SHARED / "control.lua",
        }
        for name, path in paths.items():
            self.lua.globals()[name] = path.as_posix()
        self.lua.execute(r'''
          function f110_f200_callbacks(mutate_capacity, omit_row)
            local function read_plan(path)
              return assert(loadfile(path))()
            end
            local source_plan, successor_plan = read_plan(source_catalogue_path), read_plan(successor_catalogue_path)
            local names={};for _, name in ipairs(source_plan.rows) do names[name]=true end
            local next_force_index=1
            local function force(index, engine)
              local values={index=index,valid=true,technologies={},research_progress=0,research_queue_enabled=false,
                manual_mining_speed_modifier=0,inserter_stack_size_bonus=0,
                stack_inserter_capacity_bonus=engine == "f110" and 0 or nil,
                bulk_inserter_capacity_bonus=engine == "f200" and 0 or nil,engine=engine}
              local saved, fields={},{ }
              local value={}
              setmetatable(value,{__index=function(_,key)return values[key] end,
                __newindex=function(_,key,item)
                  values[key]=item
                  if key == "research_queue" then values.current_research=item[1] end
                end})
              local function technology(name)
                local row={valid=true,name=name,force=value,prototype={level=1,max_level=4294967295},
                  level=1,researched=false,enabled=true,visible_when_disabled=false,prerequisites={}}
                fields[name]=row
                return setmetatable({}, {__index=function(_,key)
                  if key == "saved_progress" and values.engine == "f110" then
                    error("F110 LuaTechnology has no saved_progress")
                  end
                  return row[key]
                end, __newindex=function(_,key,item)
                  if key == "saved_progress" and values.engine == "f110" then
                    error("F110 LuaTechnology has no saved_progress")
                  end
                  row[key]=item
                end})
              end
              for name in pairs(names) do
                values.technologies[name]=technology(name)
              end
              values.technologies[source_plan.probe]=technology(source_plan.probe)
              values.technologies[source_plan.direct].research_unit_ingredients={
                {name="military-science-pack",amount=1},{name="utility-science-pack",amount=1}}
              values.get_saved_technology_progress=function(item)
                assert(values.engine == "f110" and item.force == value)
                return saved[item.name]
              end
              values.set_saved_technology_progress=function(item,progress)
                assert(values.engine == "f110" and item.force == value and values.current_research ~= item)
                assert(type(progress) == "number" and progress >= 0 and progress < 1)
                saved[item.name]=progress
              end
              values._migrate_to_f200=function()
                values.engine="f200";values.stack_inserter_capacity_bonus=nil
                values.bulk_inserter_capacity_bonus=values.bulk_inserter_capacity_bonus or 4
                for name,row in pairs(fields) do row.saved_progress=saved[name] or 0 end
              end
              values.enable_all_prototypes=function() end
              values.reset_technology_effects=function()
                values.inserter_stack_size_bonus=2
                if values.engine == "f110" then values.stack_inserter_capacity_bonus=4
                else values.bulk_inserter_capacity_bonus=4 end
              end
              values.add_research=function(item)
                values.research_queue={item}; values.current_research=item; return true
              end
              return value
            end
            local contents={}
            local inventory={
              clear=function() contents={} end,
              insert=function(stack) contents[stack.name]=(contents[stack.name] or 0)+stack.count;return stack.count end,
              get_item_count=function(name)return contents[name] or 0 end,
            }
            local function lab()
              local entity={valid=true,energy=0}
              entity.get_inventory=function(slot) assert(slot == 1);return inventory end
              return entity
            end
            local player=force(1,"f110")
            if omit_row then player.technologies[source_plan.continuation]=nil end
            local game={tick=0,forces={player=player},surfaces={[1]={create_entity=function()return lab()end}}}
            function game.create_force()
              next_force_index=next_force_index+1
              local item=force(next_force_index,"f110");game.forces[next_force_index]=item;return item
            end
            function game.server_save(name) game.saved=name end
            local logs, legacy={},{}
            local function load_stage(control_path,catalogue_path,mods,modern)
              local callbacks,env={events={}},{}
              env.script={active_mods=mods,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_configuration_changed=function(fn)callbacks.configuration=fn end,on_event=function(event,fn)callbacks.events[event]=fn end}
              env.defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
              env.game,env.log=game,function(row)logs[#logs+1]=row end
              if modern then env.storage=legacy else env.global=legacy end
              env.require=function(name)
                if name == "__mir-fixture-mir5-f110-f200-transition__/fixture_control" then
                  return assert(loadfile(shared_control_path,"t",env))()
                end
                assert(name == "__mir-fixture-mir5-f110-f200-transition__/catalogue")
                return assert(loadfile(catalogue_path,"t",env))()
              end
              env._G=env;setmetatable(env,{__index=_G});assert(loadfile(control_path,"t",env))()
              return callbacks
            end
            local source=load_stage(source_control_path,source_catalogue_path,
              {base="1.1.110",["more-infinite-research"]="4.7.11003",["mir-fixture-mir5-f110-f200-transition"]="0.1.0"},false)
            local ok,message=pcall(function()
              source.init()
              local direct=player.technologies[source_plan.direct]
              direct.level=2;player.manual_mining_speed_modifier=.05
              source.events[1]{research=direct};source.events[2]()
            end)
            if not ok then return {ok=false,message=tostring(message),logs=logs} end
            local direct=player.technologies[source_plan.direct]
            local state=legacy.mir5_f110_f200_transition
            if mutate_capacity then player.bulk_inserter_capacity_bonus=3 end
            for _,item in pairs(game.forces) do item._migrate_to_f200() end
            local successor=load_stage(successor_control_path,successor_catalogue_path,
              {base="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-f110-f200-transition"]="0.2.0"},true)
            ok,message=pcall(successor.configuration)
            if not ok then return {ok=false,message=tostring(message),logs=logs,state=state} end
            direct.level=3;direct.saved_progress=0;player.manual_mining_speed_modifier=.1
            player.research_queue={player.technologies[source_plan.probe]};player.research_progress=0
            successor.events[1]{research=direct};successor.events[2]()
            local before={phase=state.phase,source=state.source_direct_labs,successor=state.successor_direct_labs,
              rows=state.seeded_catalogue_rows,save=game.saved,logs=#logs}
            successor.load();successor.events[2]();successor.load();successor.events[2]()
            return {ok=true,phase=state.phase,source=state.source_direct_labs,successor=state.successor_direct_labs,
              rows=state.seeded_catalogue_rows,save=game.saved,logs=logs,before=before,
              stack=player.inserter_stack_size_bonus,bulk=player.bulk_inserter_capacity_bonus,
              current=player.current_research and player.current_research.name,foreign=game.forces[state.foreign_index].technologies[source_plan.direct].enabled,
              paused=game.forces[state.suspended_index].technologies[source_plan.direct].saved_progress}
          end
        ''')
        result = py(self.lua.eval("f110_f200_callbacks")(False, False))
        self.assertTrue(result["ok"], result["message"] if "message" in result else result)
        self.assertEqual(("successor-complete", 1, 1, 16, "mir5-native-complete"),
                         (result["phase"], result["source"], result["successor"], result["rows"], result["save"]))
        self.assertEqual((2, 4, "braking-force-1", False, .27),
                         (result["stack"], result["bulk"], result["current"], result["foreign"], result["paused"]))
        self.assertEqual(4, len(result["logs"]))
        self.assertTrue(all('"case":"f110-f200-transition"' in row for row in result["logs"]))
        self.assertTrue(any('"stage":"reload"' in row and '"on_load_read_only":true' in row for row in result["logs"]))
        wrong_capacity = py(self.lua.eval("f110_f200_callbacks")(True, False))
        self.assertFalse(wrong_capacity["ok"])
        self.assertIn("F200 bulk inserter effects differ", wrong_capacity["message"])
        missing = py(self.lua.eval("f110_f200_callbacks")(False, True))
        self.assertFalse(missing["ok"])
        self.assertIn("missing required technology", missing["message"])

    def test_profiles_and_stage_aliases_bind_only_declared_inputs(self):
        source_profile = json.loads((ROOT / "tests/profiles/f110-f200-transition-published-f110-11110.json").read_text(encoding="utf-8"))
        successor_profile = json.loads((ROOT / "tests/profiles/f110-f200-transition-mir5-f200-2077.json").read_text(encoding="utf-8"))
        self.assertEqual(("f110", "1.1", "Defaults", "1.1.110",
                          "B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1"),
                         (source_profile["target"], source_profile["factorio_line"], source_profile["settings_mode"],
                          source_profile["engine"]["version"], source_profile["engine"]["sha256"]))
        self.assertEqual({"base": "1.1.110", "more-infinite-research": "4.7.11003",
                          "mir-fixture-mir5-f110-f200-transition": "0.1.0"},
                         {row["name"]: row["version"] for row in source_profile["mods"]})
        self.assertEqual({"more-infinite-research_4.7.11003.zip":
                          "66C127D8BFC1919FA88F19D2D9B3047316A1B90401CAA05A6D05979B7A099D1E"},
                         source_profile["archive_sha256"])
        self.assertEqual(("f200", "2.0", "2.0.77", "CDC687538EEE4BB6E3E897057ACBA6DE51C74C164F8339D613D034BA952D89FD"),
                         (successor_profile["target"], successor_profile["factorio_line"], successor_profile["engine"]["version"],
                          successor_profile["archive_sha256"]["more-infinite-research_5.0.20000.zip"]))
        for stage in (SOURCE, SUCCESSOR):
            self.assertEqual('require("__mir-fixture-mir5-f110-f200-transition__/fixture_control")\n',
                             stage.joinpath("control.lua").read_text(encoding="utf-8"))
            self.assertIn('fixture_data_final', stage.joinpath("data-final-fixes.lua").read_text(encoding="utf-8"))
            self.assertNotIn("__more-infinite-research__", stage.joinpath("control.lua").read_text(encoding="utf-8"))
        readme = FIXTURE.joinpath("README.md").read_text(encoding="utf-8")
        self.assertIn("not a native result", readme)
        self.assertIn("must be rebound", readme)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    F110F200TransitionFixtureTests.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(F110F200TransitionFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

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
SUCCESSOR = FIXTURE / "f200/successor"
F110_SUCCESSOR = FIXTURE / "f110/successor"
F210_SUCCESSOR = FIXTURE / "f210/successor"
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
    def f110_effects(self):
        direct = json.loads((ROOT / "tests/fixtures/historical-direct-native-oracle.json").read_text(encoding="utf-8"))
        continuations = json.loads((ROOT / "tests/fixtures/historical-continuation-native-oracle.json").read_text(encoding="utf-8"))
        rows = next(row for row in direct["captures"] if row["target"] == "f110")["technologies"]
        rows += next(row for row in continuations["captures"] if row["target"] == "f110")["technologies"]
        return {row["id"]: [{key: effect[key] for key in ("type", "modifier", "ammo_category") if key in effect}
                            for _, effect in sorted(row["definition"]["effects"].items(), key=lambda item: int(item[0]))]
                for row in rows}

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
        same = self.load_catalogue(F110_SUCCESSOR / "catalogue.lua")
        self.assertEqual("f110", same["successor_engine"])
        direct = json.loads((ROOT / "tests/fixtures/historical-direct-native-oracle.json").read_text(encoding="utf-8"))
        continuations = json.loads((ROOT / "tests/fixtures/historical-continuation-native-oracle.json").read_text(encoding="utf-8"))
        direct_rows = next(row for row in direct["captures"] if row["target"] == "f110")["technologies"]
        continuation_rows = next(row for row in continuations["captures"] if row["target"] == "f110")["technologies"]
        expected = {row["id"] for row in direct_rows} | {row["id"] for row in continuation_rows}
        self.assertEqual(17, len(expected))
        for plan, stage in ((source, "source"), (successor, "successor"), (same, "successor")):
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
                     "ingredients": [["utility-science-pack", 1], ["military-science-pack", 1]]},
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
                        "ingredients": [["military-science-pack", 1], ["utility-science-pack", 1]]}}, mods),
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

    def test_callbacks_preserve_17_rows_and_translate_only_capacity_token(
            self, successor_dir=SUCCESSOR, modern_base="2.0.77",
            modern_mir="5.0.20000", modern_fixture="0.2.0"):
        effects = self.f110_effects()
        self.assertEqual(17, len(effects))
        self.lua.globals().source_effects = lua(self.lua, effects)
        paths = {
            "source_control_path": SOURCE / "control.lua", "source_catalogue_path": SOURCE / "catalogue.lua",
            "successor_control_path": successor_dir / "control.lua", "successor_catalogue_path": successor_dir / "catalogue.lua",
            "shared_control_path": SHARED / "control.lua",
            "same_control_path": F110_SUCCESSOR / "control.lua", "same_catalogue_path": F110_SUCCESSOR / "catalogue.lua",
        }
        for name, path in paths.items():
            self.lua.globals()[name] = path.as_posix()
        self.lua.globals().fixture_modern_base = modern_base
        self.lua.globals().fixture_modern_mir = modern_mir
        self.lua.globals().fixture_modern_version = modern_fixture
        self.lua.execute(r'''
          function f110_f200_callbacks(mutate_capacity, omit_row, mutate_effect, same_edition, mutate_progress, disable_queue, mutate_reload_queue, mutate_laser)
            local function read_plan(path)
              return assert(loadfile(path))()
            end
            local source_plan, successor_plan = read_plan(source_catalogue_path),
              read_plan(same_edition and same_catalogue_path or successor_catalogue_path)
            local names={};for _, name in ipairs(source_plan.rows) do names[name]=true end
            local next_force_index=1
            local function force(index, engine)
              local values={index=index,valid=true,technologies={},research_progress=0,research_queue_enabled=false,
                manual_mining_speed_modifier=0,inserter_stack_size_bonus=0,
                stack_inserter_capacity_bonus=engine == "f110" and 0 or nil,
                bulk_inserter_capacity_bonus=engine == "f200" and 0 or nil,engine=engine}
              local saved, fields={},{ }
              local value={}
              setmetatable(value,{__index=function(_,key)
                  if key == "research_queue_enabled" and values.engine == "f200" then
                    error("F200 LuaForce has no research_queue_enabled")
                  end
                  return values[key]
                end,
                __newindex=function(_,key,item)
                  if key == "research_queue_enabled" and values.engine == "f200" then
                    error("F200 LuaForce has no research_queue_enabled")
                  end
                  values[key]=item
                  if key == "research_queue" then values.current_research=item[1] end
                end})
              local function copy_effects(effects)
                local copy={}
                for index,effect in pairs(effects) do
                  copy[index]={type=effect.type,modifier=effect.modifier,ammo_category=effect.ammo_category}
                end
                return copy
              end
              local function technology(name)
                local row={valid=true,name=name,force=value,prototype={level=1,max_level=4294967295,effects=copy_effects(source_effects[name] or {})},
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
                saved[item.name]=progress ~= 0 and progress or nil
              end
              values._migrate_to_f200=function()
                values.engine="f200";values.research_queue_enabled=nil;values.stack_inserter_capacity_bonus=nil
                values.bulk_inserter_capacity_bonus=values.bulk_inserter_capacity_bonus or 4
                for name,row in pairs(fields) do row.saved_progress=saved[name] or 0 end
                for _,effect in pairs(fields[source_plan.continuation].prototype.effects) do
                  if effect.type == "stack-inserter-capacity-bonus" then effect.type="bulk-inserter-capacity-bonus" end
                end
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
              local entity={valid=true,active=true,energy=0}
              entity.get_inventory=function(slot) assert(slot == 1);return inventory end
              return entity
            end
            local player=force(1,"f110")
            if omit_row then player.technologies[source_plan.continuation]=nil end
            local game={tick=0,tick_paused=false,speed=1,forces={player=player},surfaces={[1]={create_entity=function()return lab()end}}}
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
              local source_state=legacy.mir5_f110_f200_transition
              source_state.lab.energy=0;source.events[2]()
              source_state.source_energized=source_state.lab.energy
              local direct=player.technologies[source_plan.direct]
              direct.level=2;player.manual_mining_speed_modifier=.05
              source.events[1]{research=direct};source.events[2]()
            end)
            if not ok then return {ok=false,message=tostring(message),logs=logs} end
            local direct=player.technologies[source_plan.direct]
            local state=legacy.mir5_f110_f200_transition
            if mutate_capacity then
              if same_edition then player.stack_inserter_capacity_bonus=3 else player.bulk_inserter_capacity_bonus=3 end
            end
            if not same_edition then
              for _,item in pairs(game.forces) do item._migrate_to_f200() end
            end
            if mutate_progress then
              local paused=game.forces[state.suspended_index]
              if same_edition then paused.set_saved_technology_progress(paused.technologies[source_plan.direct],.26)
              else paused.technologies[source_plan.direct].saved_progress=.26 end
            end
            if disable_queue then player.research_queue_enabled=false end
            if mutate_effect then
              game.forces.player.technologies["recipe-prod-research_character_walking_speed-1"].prototype.effects[1].modifier=.04
            end
            if mutate_laser then
              game.forces.player.technologies["laser-shooting-speed-8"].prototype.effects[1].ammo_category="laser-turret"
            end
            local successor=load_stage(same_edition and same_control_path or successor_control_path,
              same_edition and same_catalogue_path or successor_catalogue_path,
              {base=same_edition and "1.1.110" or fixture_modern_base,
                ["more-infinite-research"]=same_edition and "5.0.11000" or fixture_modern_mir,
                ["mir-fixture-mir5-f110-f200-transition"]=same_edition and "0.3.0" or fixture_modern_version},not same_edition)
            ok,message=pcall(successor.configuration)
            if not ok then return {ok=false,message=tostring(message),logs=logs,state=state} end
            state.lab.energy=0;successor.events[2]();state.successor_energized=state.lab.energy
            direct.level=3
            if same_edition then
              player.current_research=nil;player.set_saved_technology_progress(direct,0)
              -- F110 force getter exposes no retained work as nil.
            else direct.saved_progress=0 end
            player.manual_mining_speed_modifier=.1
            player.research_queue={player.technologies[source_plan.probe]};player.research_progress=0
            successor.events[1]{research=direct};successor.events[2]()
            local before={phase=state.phase,source=state.source_direct_labs,successor=state.successor_direct_labs,
              rows=state.seeded_catalogue_rows,save=game.saved,logs=#logs}
            ok,message=pcall(function()
              successor.load();successor.events[2]()
              if mutate_reload_queue then player.research_progress=.01 end
              successor.load();successor.events[2]()
            end)
            if not ok then return {ok=false,message=tostring(message),state=state} end
            local configuration_ok,configuration_message=pcall(successor.configuration)
            return {ok=true,configuration_refused=not configuration_ok,
              configuration_message=tostring(configuration_message),phase=state.phase,source=state.source_direct_labs,successor=state.successor_direct_labs,
              rows=state.seeded_catalogue_rows,save=game.saved,logs=logs,before=before,
              stack=player.inserter_stack_size_bonus,bulk=player.bulk_inserter_capacity_bonus,
              current=player.current_research and player.current_research.name,foreign=game.forces[state.foreign_index].technologies[source_plan.direct].enabled,
              paused=same_edition and game.forces[state.suspended_index].get_saved_technology_progress(
                game.forces[state.suspended_index].technologies[source_plan.direct])
                or game.forces[state.suspended_index].technologies[source_plan.direct].saved_progress,
              same_stack=player.stack_inserter_capacity_bonus,
              source_energy=state.source_energized,successor_energy=state.successor_energized}
          end
        ''')
        result = py(self.lua.eval("f110_f200_callbacks")(False, False))
        self.assertTrue(result["ok"], result["message"] if "message" in result else result)
        self.assertEqual(("successor-complete", 1, 1, 16, "mir5-native-complete"),
                         (result["phase"], result["source"], result["successor"], result["rows"], result["save"]))
        self.assertEqual((2, 4, "braking-force-1", False, .27),
                         (result["stack"], result["bulk"], result["current"], result["foreign"], result["paused"]))
        self.assertEqual((100000000, 100000000), (result["source_energy"], result["successor_energy"]))
        fixture_results = [row for row in result["logs"] if row.startswith("[MIR5_NATIVE_FIXTURE] RESULT ")]
        diagnostics = [row for row in result["logs"] if row.startswith("[MIR5_F110_SOURCE_DIAGNOSTIC] ")]
        self.assertEqual(4, len(fixture_results))
        self.assertTrue(all('"case":"f110-f200-transition"' in row for row in fixture_results))
        self.assertTrue(any('"stage":"reload"' in row and '"on_load_read_only":true' in row for row in fixture_results))
        self.assertEqual(2, len(diagnostics))
        self.assertIn('"checkpoint":"init"', diagnostics[0])
        self.assertIn('"checkpoint":"first-tick"', diagnostics[1])
        for row in diagnostics:
            self.assertIn('"tick_paused":false', row)
            self.assertIn('"game_speed":1', row)
            self.assertIn('"phase":"await-source-lab"', row)
            self.assertIn('"queue_enabled":true', row)
            self.assertIn('"queue_length":1', row)
            self.assertIn(f'"current_research":"{DIRECT}"', row)
            self.assertIn('"research_progress":0', row)
            self.assertIn('"direct_enabled":true', row)
            self.assertIn('"direct_researched":false', row)
            self.assertIn('"lab_valid":true', row)
            self.assertIn('"lab_active":true', row)
        self.assertIn('"lab_energy":100000000', diagnostics[0])
        self.assertIn('"lab_energy":0', diagnostics[1])
        self.assertIn('"direct_level":1', diagnostics[0])
        self.assertIn('"source_direct_labs":0', diagnostics[0])
        self.assertIn('"direct_level":1', diagnostics[1])
        self.assertIn('"source_direct_labs":0', diagnostics[1])
        wrong_capacity = py(self.lua.eval("f110_f200_callbacks")(True, False))
        self.assertFalse(wrong_capacity["ok"])
        self.assertIn("F200 bulk inserter effects differ", wrong_capacity["message"])
        missing = py(self.lua.eval("f110_f200_callbacks")(False, True))
        self.assertFalse(missing["ok"])
        self.assertIn("missing required technology", missing["message"])
        wrong_effect = py(self.lua.eval("f110_f200_callbacks")(False, False, True))
        self.assertFalse(wrong_effect["ok"])
        self.assertIn("retained technology state differs", wrong_effect["message"])
        self.assertEqual("source-complete", wrong_effect["state"]["phase"])
        same = py(self.lua.eval("f110_f200_callbacks")(False, False, False, True))
        self.assertTrue(same["ok"], same.get("message", same))
        self.assertEqual(("successor-complete", 1, 1, 16, "mir5-native-complete"),
                         (same["phase"], same["source"], same["successor"], same["rows"], same["save"]))
        self.assertEqual((2, 4, "braking-force-1", False, .27),
                         (same["stack"], same["same_stack"], same["current"], same["foreign"], same["paused"]))
        same_markers = [json.loads(row.split(" RESULT ")[1]) for row in same["logs"]
                        if row.startswith("[MIR5_NATIVE_FIXTURE] RESULT ")]
        self.assertEqual(4, len(same_markers))
        self.assertTrue(all(row["stack_inserter_capacity_bonus"] == 4 for row in same_markers))
        self.assertTrue(all("bulk_inserter_capacity_bonus" not in row for row in same_markers))
        self.assertTrue(same["configuration_refused"])
        self.assertIn("successor lacks complete published F110 source witness", same["configuration_message"])
        changed_reload = py(self.lua.eval("f110_f200_callbacks")(False, False, False, True, False, False, True))
        self.assertFalse(changed_reload["ok"])
        self.assertIn("successor reload queue/progress differs", changed_reload["message"])
        self.assertEqual("successor-complete", changed_reload["state"]["phase"])
        for capacity, effect, progress, queue, message in (
            (True, False, False, False, "stack inserter effects differ"),
            (False, True, False, False, "retained technology state differs"),
            (False, False, True, False, "retained technology state differs"),
            (False, False, False, True, "queue/progress differs"),
        ):
            with self.subTest(f110_opponent=message):
                refused = py(self.lua.eval("f110_f200_callbacks")(capacity, False, effect, True, progress, queue))
                self.assertFalse(refused["ok"])
                self.assertIn(message, refused["message"])
                self.assertEqual("source-complete", refused["state"]["phase"])

    def test_same_edition_preflight_retains_native_f110_cost_science_and_effect(self):
        # Independent F110 expectations also exercised by the historical fixture.
        raw = {"technology": {DIRECT: {
            "name": DIRECT, "level": 1, "upgrade": True, "max_level": "infinite",
            "unit": {"count_formula": "1*(8000*2^(L-1))", "time": 60,
                     "ingredients": [["military-science-pack", 1], ["utility-science-pack", 1]]},
            "effects": [{"type": "character-mining-speed", "modifier": .05}],
        }}, "sentinel": {"value": 17}}
        mods = {"base": "1.1.110", "more-infinite-research": "5.0.11000",
                "mir-fixture-mir5-f110-f200-transition": "0.3.0"}
        for enabled in (None, True):
            candidate = copy.deepcopy(raw)
            if enabled is not None:
                candidate["technology"][DIRECT]["enabled"] = enabled
            accepted = self.run_data(F110_SUCCESSOR / "data-final-fixes.lua",
                                     F110_SUCCESSOR / "catalogue.lua", candidate, mods)
            self.assertTrue(accepted["ok"], accepted["message"])
            observed = py(accepted["raw"])
            self.assertEqual((1, None, 1), tuple(observed["technology"][DIRECT]["unit"].get(key)
                                                 for key in ("count", "count_formula", "time")))
            self.assertEqual(raw["technology"][DIRECT]["effects"], observed["technology"][DIRECT]["effects"])
            self.assertEqual(17, observed["sentinel"]["value"])
        for field, value in (("enabled", False), ("enabled", "true"), ("level", 2),
                             ("effects", [{"type": "character-mining-speed", "modifier": .1}]),
                             ("unit", {"count_formula": "8000*2^(L-1)", "time": 60,
                                       "ingredients": raw["technology"][DIRECT]["unit"]["ingredients"]}),
                             ("unit", {"count_formula": "1*(8000*2^(L-1))", "time": 60,
                                       "ingredients": [["utility-science-pack", 1], ["military-science-pack", 1]]})):
            candidate = copy.deepcopy(raw)
            candidate["technology"][DIRECT][field] = value
            before = copy.deepcopy(candidate)
            with self.subTest(field=field, value=value):
                rejected = self.run_data(F110_SUCCESSOR / "data-final-fixes.lua",
                                         F110_SUCCESSOR / "catalogue.lua", candidate, mods)
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, py(rejected["raw"]))
        for field, value in (("base", "2.0.77"), ("more-infinite-research", "4.7.11003"),
                             ("mir-fixture-mir5-f110-f200-transition", "0.2.0")):
            rejected = self.run_data(F110_SUCCESSOR / "data-final-fixes.lua",
                                     F110_SUCCESSOR / "catalogue.lua", raw, {**mods, field: value})
            self.assertFalse(rejected["ok"])
            self.assertEqual(raw, py(rejected["raw"]))


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
        self.assertEqual(("f200", "2.0", "2.0.77", "8BA029A01E1F08C311C6A127C81313D7664F0ABADAF3C79F84157775D35ADFD7"),
                         (successor_profile["target"], successor_profile["factorio_line"], successor_profile["engine"]["version"],
                          successor_profile["archive_sha256"]["more-infinite-research_5.0.20000.zip"]))
        for stage in (SOURCE, SUCCESSOR, F110_SUCCESSOR, F210_SUCCESSOR):
            self.assertEqual('require("__mir-fixture-mir5-f110-f200-transition__/fixture_control")\n',
                             stage.joinpath("control.lua").read_text(encoding="utf-8"))
            self.assertIn('fixture_data_final', stage.joinpath("data-final-fixes.lua").read_text(encoding="utf-8"))
            self.assertNotIn("__more-infinite-research__", stage.joinpath("control.lua").read_text(encoding="utf-8"))
        readme = FIXTURE.joinpath("README.md").read_text(encoding="utf-8")
        self.assertIn("not a native result", readme)
        self.assertIn("must be rebound", readme)


    def test_f210_callbacks_retain_all_source_assertions_and_reject_laser_drift(self):
        self.test_callbacks_preserve_17_rows_and_translate_only_capacity_token(
            F210_SUCCESSOR, "2.1.23", "5.0.21000", "0.4.0")
        passed = py(self.lua.eval("f110_f200_callbacks")())
        self.assertTrue(passed["ok"])
        markers = [json.loads(row.split(" RESULT ")[1]) for row in passed["logs"]
                   if row.startswith("[MIR5_NATIVE_FIXTURE] RESULT ")]
        target = [row for row in markers if row.get("target") == "f210"]
        self.assertEqual(["initial", "reload", "reload"], [row["stage"] for row in target])
        self.assertTrue(all(row["origin"] == "published-f110-4.7.11003" and row["base_version"] == "2.1.23"
                            for row in target))
        wrong = py(self.lua.eval("f110_f200_callbacks")(
            False, False, False, False, False, False, False, True))
        self.assertFalse(wrong["ok"])
        self.assertIn("retained technology state differs", wrong["message"])
        self.assertEqual("source-complete", wrong["state"]["phase"])

    def test_f210_preflight_pins_destination_and_preserves_ordinary_settings(self):
        raw = {"technology": {DIRECT: {
            "name": DIRECT, "level": 1, "upgrade": True, "max_level": "infinite", "enabled": True,
            "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                     "ingredients": [["utility-science-pack", 1], ["military-science-pack", 1]]},
            "effects": [{"type": "character-mining-speed", "modifier": .05}],
        }}, "sentinel": {"value": 17}}
        mods = {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                "mir-fixture-mir5-f110-f200-transition": "0.4.0"}
        accepted = self.run_data(F210_SUCCESSOR / "data-final-fixes.lua", F210_SUCCESSOR / "catalogue.lua", raw, mods)
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual({"count": 1, "time": 1,
                          "ingredients": [["utility-science-pack", 1], ["military-science-pack", 1]]},
                         py(accepted["raw"])["technology"][DIRECT]["unit"])
        self.assertEqual({"value": 17}, py(accepted["raw"])["sentinel"])
        for key, bad in [("base", "2.0.77"), ("more-infinite-research", "5.0.20000"),
                         ("mir-fixture-mir5-f110-f200-transition", "0.2.0")]:
            changed = dict(mods, **{key: bad})
            refused = self.run_data(F210_SUCCESSOR / "data-final-fixes.lua", F210_SUCCESSOR / "catalogue.lua", raw, changed)
            self.assertFalse(refused["ok"])
            self.assertEqual(raw, py(refused["raw"]))


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

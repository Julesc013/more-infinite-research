"""Host controls for the private F200 native-worker positive-cap continuity fixture.

These bounded mocks execute the fixture controls and immutable F200 row preflight.
They do not replace the required published-to-MIR5 native save qualification.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/f200-legacy-worker"
PUBLISHED_PROFILE = ROOT / "tests/mir5/profiles/f200-legacy-worker-published-4.7-2077.json"
MIR5_PROFILE = ROOT / "tests/mir5/profiles/f200-legacy-worker-mir5-2077.json"
NAME = "mir-fixture-mir5-f200-legacy-worker"
WORKER = "worker-robots-speed-6"
SCIENCE = ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
           "production-science-pack", "utility-science-pack", "space-science-pack")
ROW = {
    "type": "technology", "name": WORKER, "upgrade": True, "max_level": "infinite",
    "prerequisites": ["worker-robots-speed-5", "space-science-pack"],
    "unit": {"count_formula": "2^(L-6)*1000", "time": 60,
             "ingredients": [[name, 1] for name in SCIENCE]},
    "effects": [{"type": "worker-robot-speed", "modifier": .65}],
}


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (list, tuple)):
        return lua.table_from([lua_value(lua, item) for item in value])
    return value


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("cyclic Lua fixture value")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


class F200LegacyWorkerFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function worker_data(path, mir, row)
            local env={mods={base="2.0.77",["more-infinite-research"]=mir},data={raw={technology={[row.name]=row}}}}
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),row=row}
          end

          function worker_parse(path, mir, fixture)
            local callbacks,reads={events={}},{ }
            local env={script={active_mods={base="2.0.77",["more-infinite-research"]=mir,
              ["mir-fixture-mir5-f200-legacy-worker"]=fixture},on_init=function(f)callbacks.init=f end,
              on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,
              on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then reads[key]=(reads[key]or 0)+1 end
              return _G[key]
            end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end

          function worker_flow(source_path, destination_path, opponent)
            local callbacks,markers,saves={events={}},0,0
            local WORKER="worker-robots-speed-6"
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack","space-science-pack"}
            local function inventory()
              local value={items={},slots={},slot_by_name={}}
              local function stack(name)
                local current=value.slot_by_name[name]
                if current==nil then
                  current={valid_for_read=true,name=name,count=0,quality={name="normal"},durability=1}
                  value.slot_by_name[name]=current;value.slots[#value.slots+1]=current
                end
                return current
              end
              function value.insert(row)
                local current=stack(row.name);current.count=current.count+row.count;current.valid_for_read=current.count>0
                value.items[row.name]=current.count;return row.count
              end
              function value.get_item_count(name)
                local current=value.slot_by_name[name];return current and current.count or 0
              end
              function value.consume(name,amount)
                local current=stack(name);assert(current.count>=1 and current.durability>0)
                if amount==1 then
                  assert(math.abs(current.durability-1)<.000001)
                  current.count=current.count-1;current.valid_for_read=current.count>0
                else
                  assert(amount>0 and amount<1 and math.abs(current.durability-1)<.000001)
                  current.durability=current.durability-amount
                end
                value.items[name]=current.count
              end
              return setmetatable(value,{__len=function(current)return #current.slots end,
                __index=function(current,key)
                  if type(key)=="number" then return current.slots[key] end
                  return rawget(current,key)
                end})
            end
            local item_prototypes={}
            for _,name in ipairs(science) do
              item_prototypes[name]={get_durability=function(quality)
                assert(quality and quality.name=="normal");return 1
              end}
            end
            local input=inventory();local modules=setmetatable({},{__len=function()return 0 end})
            local lab={valid=true,energy=0,quality={name="normal"},prototype={get_researching_speed=function(quality)
              assert(quality and quality.name=="normal");return 1
            end}}
            function lab.get_inventory(index)assert(index==1);return input end
            function lab.get_module_inventory()return modules end
            local function prereq(name)return {name=name,research_recursive=function()end}end
            local function tech(name,force)
              local effect=name==WORKER and {{type="worker-robot-speed",modifier=.65}} or {}
              local prerequisites=name==WORKER and {['worker-robots-speed-5']=prereq('worker-robots-speed-5'),
                ['space-science-pack']=prereq('space-science-pack')} or {}
              local ingredients={};for _,science_name in ipairs(science)do ingredients[#ingredients+1]={name=science_name,amount=1}end
              return {name=name,valid=true,force=force,level=name==WORKER and 6 or 1,researched=false,
                enabled=true,visible_when_disabled=false,saved_progress=0,
                prototype={max_level=4294967295,effects=effect,visible_when_disabled=false},prerequisites=prerequisites,
                research_unit_count=1,research_unit_energy=60,research_unit_ingredients=ingredients}
            end
            local function force(name,index,modifier)
              local value={name=name,index=index,valid=true,technologies={},research_queue={},research_progress=0,
                worker_robots_speed_modifier=modifier,laboratory_speed_modifier=0,laboratory_productivity_bonus=0}
              value.technologies[WORKER]=tech(WORKER,value);value.technologies["braking-force-1"]=tech("braking-force-1",value)
              function value.enable_all_prototypes()end
              function value.add_research(research)
                if type(research)=="string"then research=value.technologies[research]end
                if research==nil or value.current_research~=nil then return false end
                local transferred=research.saved_progress or 0
                if opponent=="lost-investment" and value.name=="player" and transferred>0 then transferred=.26 end
                value.current_research=research;value.research_queue={research};value.research_progress=transferred;research.saved_progress=0;return true
              end
              return value
            end
            local player,foreign=force("player",1,1.25),nil
            local game={tick=0,speed=1,forces={player=player,[1]=player},surfaces={}}
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
            function game.create_force(name)
              foreign=force(name,2,2.5)
              -- Prototype presentation was patched globally by published F200 data final fixes.
              foreign.technologies[WORKER].prototype.visible_when_disabled=player.technologies[WORKER].prototype.visible_when_disabled
              game.forces[name]=foreign;game.forces[2]=foreign;return foreign
            end
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local function startup(cap)
              return {startup={["mir-max-level-worker-robots-speed"]={value=cap},["mir-settings-profile-import"]={value=""}}}
            end
            local function load_control(path,mir,version,settings_values)
              local c={events={}}
              local env={script={active_mods={base="2.0.77",["more-infinite-research"]=mir,
                ["mir-fixture-mir5-f200-legacy-worker"]=version},on_init=function(f)c.init=f end,
                on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,
                on_event=function(e,f)c.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
                game=game,storage=storage,settings=settings_values,prototypes={item=item_prototypes},helpers={table_to_json=function(row)assert(row.status=="passed");assert(row.stage=="initial" or row.stage=="reload");return "{}"end},
                log=function(row)assert(row:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
              return ok and c or nil,tostring(result)
            end
            local function invoke(control,kind,event)
              local callback=kind=="tick" and control.events[1] or (kind=="finished" and control.events[2] or control[kind])
              if type(callback)~="function"then return false,"missing "..kind.." callback"end
              local ok,result=pcall(callback,event);return ok,tostring(result)
            end
            local function tick(control)game.tick=game.tick+1;return invoke(control,"tick")end
            local function complete(control,level,bonus,consumed_units)
              player.current_research=nil;player.research_queue={};player.research_progress=0;player.technologies[WORKER].level=level
              player.technologies[WORKER].researched=false;player.worker_robots_speed_modifier=bonus
              for _,science_name in ipairs(science)do input.consume(science_name,consumed_units or 1) end
              return invoke(control,"finished",{research=player.technologies[WORKER]})
            end
            local source,message=load_control(source_path,"4.7.20002","0.1.0",startup(7));if not source then return {ok=false,message=message}end
            -- Published MIR is a dependency, so its on_init cap presentation precedes fixture on_init.
            player.technologies[WORKER].prototype.visible_when_disabled=true
            player.technologies[WORKER].visible_when_disabled=true
            local ok,result=invoke(source,"init");if not ok then return {ok=false,message=result}end
            local state=storage.mir5_f200_legacy_worker
            ok,result=complete(source,7,state.player_with_independent+.65,1);if not ok then return {ok=false,message=result}end
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            ok,result=complete(source,8,state.player_with_independent+1.3,1);if not ok then return {ok=false,message=result}end
            -- Emulates the published cap controller, outside the fixture: the fixture only observes this player write.
            player.technologies[WORKER].enabled=true;player.technologies[WORKER].visible_when_disabled=true
            -- The second actual completion is followed by the published cap controller disabling it.
            player.technologies[WORKER].enabled=false;player.technologies[WORKER].visible_when_disabled=true
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            for _=1,2 do ok,result=invoke(source,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(source);if not ok then return {ok=false,message=result}end end
            if opponent=="stale-enable"then player.technologies[WORKER].enabled=false
            elseif opponent=="native-level"then player.technologies[WORKER].level=7
            elseif opponent=="foreign-queue"then foreign.research_progress=.41
            elseif opponent=="saved-progress"then player.technologies[WORKER].saved_progress=.26
            elseif opponent=="speed-bonus"then player.worker_robots_speed_modifier=0
            elseif opponent=="lab-count"then state.actual_lab_completions=1 end
            -- The source state owns the published positive-cap presentation.
            -- The successor data-stage prototype independently returns to the
            -- Base default before its lifecycle restores the source value.
            if opponent~="stale-enable"then player.technologies[WORKER].enabled=true;player.technologies[WORKER].visible_when_disabled=true;player.technologies[WORKER].prototype.visible_when_disabled=false end
            local destination,message=load_control(destination_path,"5.0.20000","0.2.0",startup(40));if not destination then return {ok=false,message=message}end
            -- Native upgrade loads the old fixture state before configuration_changed.
            ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end
            ok,result=invoke(destination,"changed");if not ok then return {ok=false,message=result}end
            local consumed_units=state.destination_science_accounting.consumed_units
            local elapsed_ticks=state.destination_science_accounting.remaining_ticks
            if opponent=="wrong-tick-span" then elapsed_ticks=elapsed_ticks-1 end
            game.tick=game.tick+elapsed_ticks
            if opponent=="consumption-overshoot" then consumed_units=consumed_units+1/60 end
            ok,result=complete(destination,9,state.player_with_independent+1.95,consumed_units);if not ok then return {ok=false,message=result}end
            if opponent=="duplicate-lab"then state.destination_lab_completions=2 end
            ok,result=tick(destination);if not ok then return {ok=false,message=result}end
            for _=1,2 do ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(destination);if not ok then return {ok=false,message=result}end end
            return {ok=true,message="",phase=state.phase,source_labs=state.actual_lab_completions,destination_labs=state.destination_lab_completions,
              player_level=player.technologies[WORKER].level,bonus=player.worker_robots_speed_modifier,
              player_enabled=player.technologies[WORKER].enabled,player_visible=player.technologies[WORKER].visible_when_disabled,
              science_before=state.destination_science_units_before[science[1]],science_after=state.destination_science_units_after[science[1]],
              consumed_units=state.destination_science_accounting.consumed_units,remaining_ticks=state.destination_science_accounting.remaining_ticks,
              elapsed_ticks=state.destination_elapsed_ticks,current_progress=state.destination_science_accounting.progress,foreign_progress=foreign.research_progress,foreign_enabled=foreign.technologies[WORKER].enabled,markers=markers,saves=saves}
          end
        ''')

    def row(self):
        return lua_value(self.lua, deepcopy(ROW))

    def test_profiles_use_f200_base_observer_and_explicit_fixture_versions(self):
        for path, mir, version in ((PUBLISHED_PROFILE, "4.7.20002", "0.1.0"), (MIR5_PROFILE, "5.0.20000", "0.2.0")):
            with self.subTest(profile=path.name):
                profile = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(("f200", "2.0.77"), (profile["target"], profile["engine"]["version"]))
                self.assertEqual(["base", "mir-fixture-mir5-active-mods-observer", "more-infinite-research", NAME],
                                 [row["name"] for row in profile["mods"]])
                self.assertEqual((mir, version), (profile["mods"][2]["version"], profile["mods"][3]["version"]))
                self.assertNotIn("space-age", [row["name"] for row in profile["mods"]])
                info = json.loads((FIXTURE / ("published" if version == "0.1.0" else "mir5") / "info.json").read_text())
                self.assertEqual((NAME, version, "2.0"), (info["name"], info["version"], info["factorio_version"]))

    def test_exact_base_native_row_preflight_precedes_only_disposable_count_time_mutation(self):
        for directory, mir in (("published", "4.7.20002"), ("mir5", "5.0.20000")):
            with self.subTest(directory=directory):
                row = self.row()
                if directory == "published":
                    row["visible_when_disabled"] = True
                result = self.lua.eval("worker_data")(str(FIXTURE / directory / "data-final-fixes.lua"), mir, row)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((None, "1", 1), (result["row"]["unit"]["count"], result["row"]["unit"]["count_formula"], result["row"]["unit"]["time"]))
        bad = self.row(); bad["visible_when_disabled"] = True; bad["effects"][1]["modifier"] = .6
        result = self.lua.eval("worker_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), "4.7.20002", bad)
        self.assertFalse(result["ok"]); self.assertIn("published native worker effect changed", result["message"])
        self.assertEqual("2^(L-6)*1000", result["row"]["unit"]["count_formula"])
        bad_default = self.row(); bad_default["visible_when_disabled"] = False
        result = self.lua.eval("worker_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), "4.7.20002", bad_default)
        self.assertFalse(result["ok"]); self.assertIn("identity or progression changed", result["message"])

    def test_controls_parse_without_game_access_and_source_never_writes_player_presentation(self):
        for directory, mir, version in (("published", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
            with self.subTest(directory=directory):
                result = self.lua.eval("worker_parse")(str(FIXTURE / directory / "control.lua"), mir, version)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, plain(result["reads"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
        source = (FIXTURE / "published/control.lua").read_text(encoding="utf-8")
        self.assertNotIn("technology(game.forces.player, WORKER).enabled =", source)
        self.assertNotIn("technology(game.forces.player, WORKER).visible_when_disabled =", source)
        self.assertNotRegex(source, r"(?<!foreign_)native\.enabled\s*=")
        self.assertIn("technology(game.forces.player, WORKER).saved_progress = 0.27", source)
        self.assertIn('state.milestone = "actual2labs"', source)
        self.assertIn("published_controller_initial_visible_when_disabled", source)
        self.assertIn("await-second-queue", source)
        self.assertNotIn("research_queue_enabled", source)
        for directory in ("published", "mir5"):
            control = (FIXTURE / directory / "control.lua").read_text(encoding="utf-8")
            body = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
            self.assertNotIn("game.", body, f"{directory} on_load touched LuaGameScript")
            self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=", f"{directory} on_load wrote fixture storage")

    def test_two_real_native_worker_labs_restore_source_right_then_one_successor_lab_and_reloads(self):
        result = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(FIXTURE / "mir5/control.lua"), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(("completed", 2, 1, 9), (result["phase"], result["source_labs"], result["destination_labs"], result["player_level"]))
        self.assertAlmostEqual(3.323, result["bonus"], places=6)
        self.assertTrue(result["player_enabled"]); self.assertTrue(result["player_visible"])
        self.assertAlmostEqual(22, result["science_before"], places=6)
        self.assertAlmostEqual(22 - 44 / 60, result["science_after"], places=6)
        self.assertAlmostEqual(44 / 60, result["consumed_units"], places=6)
        self.assertEqual(44, result["remaining_ticks"])
        self.assertEqual(44, result["elapsed_ticks"])
        self.assertAlmostEqual(.27, result["current_progress"], places=6)
        self.assertEqual(.42, result["foreign_progress"]); self.assertFalse(result["foreign_enabled"])
        self.assertEqual((6, 2), (result["markers"], result["saves"]))

    def test_stale_state_native_bonus_foreign_queue_and_duplicate_completion_are_rejected(self):
        opponents = {
            "stale-enable": "MIR5 restored native worker native worker state differs",
            "native-level": "MIR5 restored native worker native worker state differs",
            "foreign-queue": "foreign worker queue or progress changed",
            "saved-progress": "MIR5 restored native worker saved progress differs",
            "speed-bonus": "MIR5 restored native worker native worker state differs",
            "lab-count": "published native-worker source witness is absent",
            "duplicate-lab": "successor did not finish exactly one further native worker lab level",
            "lost-investment": "successor native worker saved investment did not become current research",
            "wrong-tick-span": "successor real native worker lab tick duration differs",
            "consumption-overshoot": "successor real native worker lab consumption differs for automation-science-pack: observed_units=",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(FIXTURE / "mir5/control.lua"), opponent)
                self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])
                if opponent == "consumption-overshoot":
                    self.assertIn("expected_units=21.266", result["message"])
                    self.assertIn("consumed_units=0.733", result["message"])
                    self.assertIn("remaining_ticks=44", result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(F200LegacyWorkerFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

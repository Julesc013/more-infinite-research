"""Host controls for the fresh current-MIR5 F100 -> F110 laser bridge.

These controls exercise only fixture and runner preflight/callback contracts.
They are not a historical 4.7.3 save, native, or release qualification result.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/f100-f110-laser-transition"
SHARED = FIXTURE / "shared"
SOURCE = FIXTURE / "source"
SUCCESSOR = FIXTURE / "successor"
RUNNER = ROOT / "tools/Invoke-NativeFixture.ps1"
NAME = "mir-fixture-mir5-f100-f110-laser-transition"
SOURCE_ID = "laser-turret-speed-8"
SUCCESSOR_ID = "laser-shooting-speed-8"
SCIENCE = ("automation-science-pack", "chemical-science-pack", "logistic-science-pack",
           "military-science-pack", "utility-science-pack")
SOURCE_FORMULA = "1*(1025.15625*1.5^(L-8))"
SUCCESSOR_FORMULA = "1*(1025.15625*1.5^(L-8))"
SOURCE_TIME = 60
SUCCESSOR_TIME = 120


def py(value):
    if hasattr(value, "items"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in value.items()}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


def _run_powershell(script, env):
    return subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-Command", script], cwd=ROOT,
                          env=env, text=True, capture_output=True, check=False)


class F100F110LaserTransitionFixtureControls(unittest.TestCase):
    def setUp(self):
        from lupa.lua52 import LuaRuntime
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def run_data(self, stage, raw, mods):
        data_path = (stage / "data-final-fixes.lua").as_posix()
        self.lua.globals().data_path = data_path
        self.lua.globals().shared_path = (SHARED / "fixture_data_final.lua").as_posix()
        self.lua.execute(r'''
          function f100_f110_run_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-f100-f110-laser-transition__/fixture_data_final")
              return assert(loadfile(shared_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("f100_f110_run_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def run_settings(self, stage, raw, mods):
        settings_path = (stage / "settings-updates.lua").as_posix()
        self.lua.globals().settings_path = settings_path
        self.lua.execute(r'''
          function f100_f110_run_settings(raw, mods)
            local env={data={raw=raw},mods=mods};env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("f100_f110_run_settings")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    @staticmethod
    def raw_technology(name, ammo, maximum, formula, research_time):
        return {"technology": {name: {
            "type": "technology", "name": name, "level": 8, "upgrade": True,
            "max_level": maximum, "enabled": True,
            "unit": {"count_formula": formula, "time": research_time,
                     "ingredients": [[pack, 1] for pack in SCIENCE]},
            "effects": [{"type": "gun-speed", "ammo_category": ammo, "modifier": .75}],
        }}, "sentinel": {"untouched": 17}}

    def test_data_preflight_is_independent_and_accelerates_only_verified_laser(self):
        cases = ((SOURCE, SOURCE_ID, "laser-turret", 8, SOURCE_FORMULA, SOURCE_TIME, "1.0.0", "5.0.10000", "0.1.0"),
                 (SUCCESSOR, SUCCESSOR_ID, "laser", 40, SUCCESSOR_FORMULA, SUCCESSOR_TIME, "1.1.110", "5.0.11000", "0.2.0"))
        for stage, name, ammo, maximum, formula, research_time, base, mir, fixture_version in cases:
            with self.subTest(stage=stage.name):
                raw = self.raw_technology(name, ammo, maximum, formula, research_time)
                mods = {"base": base, "more-infinite-research": mir, NAME: fixture_version}
                accepted = self.run_data(stage, raw, mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                unit = accepted["raw"]["technology"][name]["unit"]
                self.assertEqual((1, None, 1), tuple(unit.get(key) for key in ("count", "count_formula", "time")))
                self.assertEqual(17, accepted["raw"]["sentinel"]["untouched"])
                for label, altered in (
                    ("identity", {**raw["technology"][name], "name": name + "-wrong"}),
                    ("effect", {**raw["technology"][name], "effects": [{"type": "gun-speed", "ammo_category": ammo, "modifier": .5}]}),
                    ("formula", {**raw["technology"][name], "unit": {"count_formula": "1*(1025.15625*1.5^(L-7))", "time": research_time, "ingredients": [[pack, 1] for pack in SCIENCE]}}),
                    ("time", {**raw["technology"][name], "unit": {"count_formula": formula, "time": research_time + 1, "ingredients": [[pack, 1] for pack in SCIENCE]}}),
                    ("science", {**raw["technology"][name], "unit": {"count_formula": formula, "time": research_time, "ingredients": [[pack, 1] for pack in reversed(SCIENCE)]}}),
                    ("cap", {**raw["technology"][name], "max_level": maximum + 1}),
                ):
                    candidate = copy.deepcopy(raw)
                    candidate["technology"][name] = altered
                    before = copy.deepcopy(candidate)
                    refused = self.run_data(stage, candidate, mods)
                    self.assertFalse(refused["ok"], label)
                    self.assertEqual(before, refused["raw"], label)

    def test_successor_formula_is_bound_to_the_independent_f110_native_reference(self):
        oracle = json.loads((ROOT / "tests/fixtures/historical-continuation-native-oracle.json").read_text(encoding="utf-8"))
        rows = [technology for capture in oracle["captures"] if capture.get("target") == "f110"
                for technology in capture.get("technologies", []) if technology.get("id") == SUCCESSOR_ID]
        self.assertEqual(1, len(rows))
        self.assertEqual(SUCCESSOR_FORMULA, rows[0]["definition"]["unit_count_formula"])
        self.assertEqual(SUCCESSOR_TIME * 60, rows[0]["definition"]["unit_energy"])
        self.assertIn(f'formula = "{SOURCE_FORMULA}"', (SOURCE / "data-final-fixes.lua").read_text(encoding="utf-8"))
        self.assertIn(f'formula = "{SUCCESSOR_FORMULA}"', (SUCCESSOR / "data-final-fixes.lua").read_text(encoding="utf-8"))

    def test_settings_stage_sets_only_the_established_laser_cap_and_effect(self):
        for stage, base, mir, fixture_version, cap in ((SOURCE, "1.0.0", "5.0.10000", "0.1.0", 8),
                                                        (SUCCESSOR, "1.1.110", "5.0.11000", "0.2.0", 40)):
            raw = {"int-setting": {
                "mir-max-level-laser-shooting-speed": {"default_value": 0},
                "mir-effect-per-level-laser-shooting-speed": {"default_value": 10},
                "unrelated": {"default_value": 19},
            }}
            mods = {"base": base, "more-infinite-research": mir, NAME: fixture_version}
            with self.subTest(stage=stage.name):
                accepted = self.run_settings(stage, raw, mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                settings = accepted["raw"]["int-setting"]
                self.assertEqual((cap, 75, 19), (settings["mir-max-level-laser-shooting-speed"]["default_value"],
                                                 settings["mir-effect-per-level-laser-shooting-speed"]["default_value"],
                                                 settings["unrelated"]["default_value"]))
                broken = copy.deepcopy(raw)
                del broken["int-setting"]["mir-max-level-laser-shooting-speed"]
                before = copy.deepcopy(broken)
                refused = self.run_settings(stage, broken, mods)
                self.assertFalse(refused["ok"])
                self.assertEqual(before, refused["raw"])

    def test_identity_profiles_and_fixed_current_freeze_are_literal(self):
        expected = (("f100-f110-laser-bridge-source-100.json", "mir5-f100-f110-laser-bridge-source", "f100", "1.0.0", "5.0.10000", "0.1.0", "51EE1EFB685CE7EFF76E1CD671FF0E5AFBA9DC5357B54694E8F5CC24C1B12AA5"),
                    ("f100-f110-laser-bridge-successor-11110.json", "mir5-f100-f110-laser-bridge-successor", "f110", "1.1.110", "5.0.11000", "0.2.0", "0BBA35402356C14FA0339632E63F8602E39969D4E635E28FA2450CFF24939A95"))
        for file_name, kind, target, base, mir, version, archive in expected:
            profile = json.loads((ROOT / "tests/profiles" / file_name).read_text(encoding="utf-8"))
            with self.subTest(profile=file_name):
                self.assertEqual((1, kind, target, "Defaults"),
                                 (profile["schema"], profile["kind"], profile["target"], profile["settings_mode"]))
                self.assertEqual([( "base", base), ("more-infinite-research", mir), (NAME, version)],
                                 [(row["name"], row["version"]) for row in profile["mods"]])
                self.assertEqual(archive, profile["archive_sha256"][f"more-infinite-research_{mir}.zip"])
                self.assertTrue("not" in profile["scope"].lower() or "no " in profile["scope"].lower())
        self.assertNotIn("219EF", "\n".join(path.read_text(encoding="utf-8") for path in FIXTURE.rglob("*" ) if path.is_file()))

    def test_on_load_is_read_only_and_wrappers_use_one_same_name_fixture(self):
        paths = [SOURCE / "control.lua", SUCCESSOR / "control.lua"]
        for path in paths:
            self.assertIn('require("__mir-fixture-mir5-f100-f110-laser-transition__/fixture_control").apply({', path.read_text(encoding="utf-8"))
        for path, version in ((SOURCE / "info.json", "0.1.0"), (SUCCESSOR / "info.json", "0.2.0")):
            self.assertEqual((NAME, version), tuple(json.loads(path.read_text(encoding="utf-8"))[key] for key in ("name", "version")))
        source = (SHARED / "fixture_control.lua").read_text(encoding="utf-8")
        self.assertIn("on_load deliberately touches no game", source)
        self.assertIn("F100 laser source does not accept an input save", RUNNER.read_text(encoding="utf-8"))

    def run_callbacks(self, defect=""):
        """Execute the authored callbacks against a finite native-shaped model.

        The model deliberately owns its expected .75/.1.5 bonuses rather than
        importing them from the candidate fixture.  It is host evidence only.
        """
        for key, path in {"source_control_path": SOURCE / "control.lua",
                          "successor_control_path": SUCCESSOR / "control.lua",
                          "shared_control_path": SHARED / "fixture_control.lua"}.items():
            self.lua.globals()[key] = path.as_posix()
        self.lua.execute(r'''
          function f100_f110_callbacks(defect)
            local handlers, results, saves={}, {}, 0
            local initial, configured, loaded, tick, research
            local events={on_research_finished=1,on_tick=2}
            local function copy_effect(ammo)
              return {{type="gun-speed",ammo_category=ammo,modifier=.75}}
            end
            local function tech(name, ammo, maximum)
              return {valid=true,name=name,level=1,researched=false,enabled=true,
                visible_when_disabled=false,saved_progress=0,
                prototype={name=name,level=8,upgrade=true,max_level=maximum,effects=copy_effect(ammo)},
                research_unit_ingredients={{name="automation-science-pack"},{name="chemical-science-pack"},
                  {name="logistic-science-pack"},{name="military-science-pack"},{name="utility-science-pack"}}}
            end
              local function force(index, direct, ammo, maximum)
              local fields={index=index,valid=true,technologies={},research_progress=0,research_queue_enabled=true,
                research_queue={},current_research=nil,gun=0,damage=0}
              for _,name in ipairs({direct,"braking-force-1","chemical-science-pack","laser-turret-speed-6",
                "laser-turret-speed-7","logistic-science-pack","military-science-pack","utility-science-pack","railway"}) do
                fields.technologies[name]=tech(name,ammo,maximum)
              end
              fields.technologies[direct].prerequisites={"chemical-science-pack","laser-turret-speed-6",
                "laser-turret-speed-7","logistic-science-pack","military-science-pack","utility-science-pack"}
              fields.technologies["braking-force-1"].prerequisites={"railway","chemical-science-pack"}
              local object={}
              function fields.get_saved_technology_progress(value)return value.saved_progress end
              function fields.set_saved_technology_progress(value,progress)value.saved_progress=progress end
              function fields.enable_all_prototypes() end
              function fields.get_gun_speed_modifier(_) return fields.gun end
              function fields.get_ammo_damage_modifier(_) return fields.damage end
              function fields.add_research(value)
                for _,name in ipairs(value.prerequisites or {}) do
                  local prerequisite=fields.technologies[name]
                  if prerequisite==nil or prerequisite.researched~=true then return false end
                end
                fields.research_queue[#fields.research_queue+1]=value
                fields.current_research=fields.research_queue[1]
                return true
              end
              setmetatable(object,{__index=fields,__newindex=function(_,key,value)
                if key=="research_queue" then
                  local prior=fields.current_research
                  if prior~=nil then
                    if defect=="lost-queued-work" and prior.name=="braking-force-1"
                        and value[1] and value[1].name=="laser-shooting-speed-8" then
                      prior.saved_progress=0
                    else
                      prior.saved_progress=fields.research_progress
                    end
                  end
                  fields[key]=value;fields.current_research=value[1]
                  fields.research_progress=value[1] and value[1].saved_progress or 0
                else fields[key]=value end
              end})
              for _,row in pairs(fields.technologies) do row.force=object end
              return object,fields
            end
            local player,player_fields=force(1,"laser-turret-speed-8","laser-turret",8)
            local science={"automation-science-pack","chemical-science-pack","logistic-science-pack",
              "military-science-pack","utility-science-pack"}
            local game={forces={player=player,[1]=player},tick=1,surfaces={[1]={}},item_prototypes={}}
            for _,name in ipairs(science) do game.item_prototypes[name]={durability=1} end
            local next_force=2
            function game.create_force(_)
              local object=force(next_force,"laser-turret-speed-8","laser-turret",8)
              game.forces[next_force]=object;next_force=next_force+1;return object
            end
            game.surfaces[1].create_entity=function(_)
              local contents,order={},{}
              local inventory={}
              function inventory.clear() contents={};order={} end
              function inventory.insert(stack)
                local prior=contents[stack.name]
                if prior==nil then prior={count=0,durability=1};contents[stack.name]=prior;order[#order+1]=stack.name end
                prior.count=prior.count+stack.count
                return stack.count
              end
              function inventory.get_item_count(name)local row=contents[name];return row and row.count or 0 end
              function inventory.set_tool_units(name,units)
                local count=math.ceil(units)
                local durability=units-math.floor(units)
                if durability==0 then durability=1 end
                if contents[name]==nil then order[#order+1]=name end
                contents[name]={count=count,durability=durability}
              end
              setmetatable(inventory,{__len=function()return #order end,__index=function(value,key)
                if type(key)=="number" then
                  local name=order[key];local row=name and contents[name]
                  if row==nil then return {valid_for_read=false} end
                  return {valid_for_read=true,name=name,count=row.count,is_tool=true,durability=row.durability}
                end
                return rawget(value,key)
              end})
              return {valid=true,energy=0,get_inventory=function(_)return inventory end,_contents=contents}
            end
            local script={active_mods={base="1.0.0",["more-infinite-research"]="5.0.10000",
              ["mir-fixture-mir5-f100-f110-laser-transition"]="0.1.0"}}
            function script.on_init(fn) initial=fn end
            function script.on_configuration_changed(fn) configured=fn end
            function script.on_load(fn) loaded=fn end
            function script.on_event(event,fn) handlers[event]=fn end
            local env={game=game,script=script,global={},defines={events=events,inventory={lab_input=1}},
              log=function(value) results[#results+1]=value end}
            env.game.server_save=function(_) saves=saves+1 end
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-f100-f110-laser-transition__/fixture_control")
              return assert(loadfile(shared_control_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local function load_control(path)
              return assert(loadfile(path,"t",env))()
            end
            local function migrate(force_object, force_fields, is_player)
              local old=force_fields.technologies["laser-turret-speed-8"]
              local new=tech("laser-shooting-speed-8","laser",40)
              new.force=force_object
              new.prerequisites=old.prerequisites
              new.level=is_player and (old.level+1) or old.level;new.researched=false;new.enabled=old.enabled;new.saved_progress=old.saved_progress
              force_fields.technologies["laser-turret-speed-8"]=nil;force_fields.technologies["laser-shooting-speed-8"]=new
              for name,row in pairs(force_fields.technologies) do
                if row.name=="laser-turret-speed-8" then row.name="laser-shooting-speed-8" end
              end
              if force_fields.current_research==old then force_fields.current_research=nil;force_fields.research_queue={} end
            end
            local function migrate_all()
              for index,force_object in pairs(game.forces) do
                if type(index)=="number" then
                  local fields=getmetatable(force_object).__index
                  migrate(force_object,fields,force_object==player)
                end
              end
              script.active_mods={base="1.1.110",["more-infinite-research"]="5.0.11000",
                ["mir-fixture-mir5-f100-f110-laser-transition"]="0.2.0"}
            end
            local ok,message=pcall(function()
              load_control(source_control_path);initial()
              if defect=="missing-probe-prereq" then
                local railway=player_fields.technologies["railway"]
                railway.researched=nil
                setmetatable(railway,{__index=function(_,key)
                  if key=="researched" then return false end
                end,__newindex=function(row,key,value)
                  if key=="researched" then rawset(row,key,false) else rawset(row,key,value) end
                end})
              end
              local source=player_fields.technologies["laser-turret-speed-8"]
              source.level=8;source.researched=true;player_fields.gun=.75;player_fields.damage=.75
              local state=env.global.mir5_f100_f110_laser_transition
              for _,name in pairs(state.source_lab_supplied) do end
              -- The engine removes the completed source research before it
              -- delivers on_research_finished.  Retain a .75 damage decoy:
              -- source would accept the wrong getter, successor must not.
              player.research_queue={}
              local source_input=state.source_lab.get_inventory(1)
              for _,name in ipairs(science) do
                source_input.set_tool_units(name,(defect=="partial-consumption" and name=="automation-science-pack") and 31.5 or 31)
              end
              handlers[events.on_research_finished]({research=source,by_script=defect=="scripted-completion"})
              handlers[events.on_tick]({})
              handlers[events.on_tick]({})
              -- The protected F100 process takes its own two cold read-only
              -- reload observations before the F110 process is started.
              local source_saves=saves
              loaded();handlers[events.on_tick]({});handlers[events.on_tick]({})
              loaded();handlers[events.on_tick]({})
              if saves~=source_saves then error("source cold reload wrote a save") end
              if defect=="source-off-by-one" then source.level=7 end
              if defect=="lost-progress" then
                local detached=game.forces[state.detached_index]
                detached.technologies["laser-turret-speed-8"].saved_progress=.26
              end
              if defect=="foreign-drift" then
                game.forces[state.foreign_index].technologies["laser-turret-speed-8"].enabled=true
              end
              migrate_all()
              state=env.global.mir5_f100_f110_laser_transition
              if defect=="changed-effect" then player_fields.technologies["laser-shooting-speed-8"].prototype.effects[1].modifier=.5 end
              load_control(successor_control_path);configured({})
              local successor=player_fields.technologies["laser-shooting-speed-8"]
              successor.level=10;successor.researched=false;player_fields.gun=1.5
              if defect=="damage-decoy" then player_fields.damage=99 end
              local successor_input=state.successor_lab.get_inventory(1)
              for _,name in ipairs(science) do successor_input.set_tool_units(name,31) end
              player.research_queue={}
              handlers[events.on_research_finished]({research=successor,by_script=false})
              handlers[events.on_tick]({})
              handlers[events.on_tick]({})
              local before_load_saves=saves
              loaded();handlers[events.on_tick]({});handlers[events.on_tick]({})
              loaded();handlers[events.on_tick]({})
              if saves~=before_load_saves then error("cold reload wrote a save") end
              if defect=="unexpected-config" then configured({}) end
            end)
            local result_state=env.global.mir5_f100_f110_laser_transition or {}
            local foreign=game.forces[result_state.foreign_index]
            local foreign_enabled=nil
            if foreign then foreign_enabled=(foreign.technologies["laser-shooting-speed-8"] or {}).enabled end
            return {ok=ok,message=tostring(message),results=results,saves=saves,
              player_queue=player_fields.current_research and player_fields.current_research.name or nil,
              player_progress=player_fields.research_progress,
              player_level=(player_fields.technologies["laser-shooting-speed-8"] or {}).level,
              braking_saved_progress=(player_fields.technologies["braking-force-1"] or {}).saved_progress,
              railway_researched=(player_fields.technologies["railway"] or {}).researched,
              foreign_enabled=foreign_enabled}
          end
        ''')
        return py(self.lua.eval("f100_f110_callbacks")(defect))

    def test_callbacks_preserve_forward_intent_state_then_emit_two_read_only_reloads(self):
        accepted = self.run_callbacks()
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual(2, accepted["saves"])
        self.assertEqual("braking-force-1", accepted["player_queue"])
        self.assertAlmostEqual(.42, accepted["player_progress"])
        self.assertAlmostEqual(.42, accepted["braking_saved_progress"])
        self.assertTrue(accepted["railway_researched"])
        self.assertEqual(10, accepted["player_level"])
        self.assertFalse(accepted["foreign_enabled"])
        markers = [line for line in accepted["results"] if "[MIR5_NATIVE_FIXTURE] RESULT" in line]
        self.assertEqual(6, len(markers), markers)
        self.assertEqual(["initial", "reload", "reload", "initial", "reload", "reload"], [json.loads(line.split(" RESULT ", 1)[1])["stage"] for line in markers])
        self.assertIn('"source_laser_lab_completions":1', markers[0])
        self.assertIn('"successor_laser_lab_completions":1', markers[-1])
        # The model keeps damage at .75 while gun speed reaches 1.5.  A
        # damage getter would therefore refuse this otherwise valid path.
        self.assertIn('"laser_delta":1.5', markers[-1])

    def test_gun_speed_witness_ignores_an_opposing_ammo_damage_decoy(self):
        accepted = self.run_callbacks("damage-decoy")
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertAlmostEqual(.42, accepted["braking_saved_progress"])

    def test_callback_opponents_refuse_before_successor_fixture_completion(self):
        for defect in ("source-off-by-one", "lost-progress", "foreign-drift", "changed-effect", "scripted-completion", "partial-consumption", "missing-probe-prereq", "lost-queued-work", "unexpected-config"):
            with self.subTest(defect=defect):
                refused = self.run_callbacks(defect)
                self.assertFalse(refused["ok"], refused["message"])
                # No F110 successor completion marker may be used to hide a
                # malformed carried source state.
                markers = [line for line in refused["results"] if '"stage":"initial"' in line]
                self.assertLessEqual(len(markers), 2 if defect == "unexpected-config" else 1, refused["results"])

    def test_runner_fixed_opt_in_binds_stage_profile_and_composed_members(self):
        """Exercise the parsed fixed-mode admission helper without Factorio."""
        with tempfile.TemporaryDirectory(prefix="mir5-f100-f110-runner-") as work:
            work = Path(work)
            repo = work / "repo"
            shutil.copytree(FIXTURE, repo / "tests/fixtures/f100-f110-laser-transition")
            engine_data = work / "engine-data"
            (engine_data / "base").mkdir(parents=True)
            engine = work / "factorio.exe"
            engine.write_bytes(b"host-only engine")
            cases = (("source", "f100-f110-laser-bridge-source-100.json", "1.0.0", ""),
                     ("successor", "f100-f110-laser-bridge-successor-11110.json", "1.1.110", "a" * 64))
            for stage, profile_name, base_version, input_hash in cases:
                with self.subTest(stage=stage):
                    (engine_data / "base/info.json").write_text(json.dumps({"version": base_version}), encoding="utf-8")
                    profile = json.loads((ROOT / "tests/profiles" / profile_name).read_text(encoding="utf-8"))
                    profile_path = work / f"{stage}.json"
                    profile_path.write_text(json.dumps(profile), encoding="utf-8")
                    staged = repo / "build" / f"{stage}-staged"
                    staged.mkdir(parents=True, exist_ok=True)
                    canonical = repo / "tests/fixtures/f100-f110-laser-transition" / stage
                    shared = repo / "tests/fixtures/f100-f110-laser-transition/shared"
                    for name in ("control.lua", "data-final-fixes.lua", "info.json", "settings-updates.lua"):
                        shutil.copyfile(canonical / name, staged / name)
                    shutil.copyfile(shared / "fixture_control.lua", staged / "fixture_control.lua")
                    shutil.copyfile(shared / "fixture_data_final.lua", staged / "fixture_data_final.lua")
                    env = {**__import__("os").environ,
                           "MIR_LASER_RUNNER": str(RUNNER), "MIR_LASER_REPO": str(repo),
                           "MIR_LASER_PROFILE": str(profile_path), "MIR_LASER_SOURCE": str(staged),
                           "MIR_LASER_ENGINE": str(engine), "MIR_LASER_ENGINE_DATA": str(engine_data),
                           "MIR_LASER_INPUT": input_hash, "MIR_LASER_STAGE": stage}
                    script = r'''
                      $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
                      $tokens=$null;$errors=$null
                      $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_LASER_RUNNER,[ref]$tokens,[ref]$errors)
                      if($errors.Count){throw 'runner parse failed'}
                      foreach($name in @('Assert-Fixture','Get-FixtureSha','Test-F100F110LaserBridgeRelativePath','Get-F100F110LaserBridgeFixture')){
                        $node=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
                        if($node.Count -ne 1){throw ('missing helper '+$name)}
                        Invoke-Expression $node[0].Extent.Text
                      }
                      $realHash=${function:Get-FixtureSha}
                      function Get-FixtureSha([string]$Path){
                        if($Path -ceq $env:MIR_LASER_ENGINE){
                          if($env:MIR_LASER_INPUT -eq ''){return '99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70'}
                          return 'B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1'
                        }
                        return & $realHash $Path
                      }
                      $profile=Get-Content -LiteralPath $env:MIR_LASER_PROFILE -Raw|ConvertFrom-Json -AsHashtable
                      $base=@{Repo=$env:MIR_LASER_REPO;ProfileDefinition=$profile;ProfileRows=@($profile.mods);Sources=@($env:MIR_LASER_SOURCE)
                        EngineData=$env:MIR_LASER_ENGINE_DATA;Engine=$env:MIR_LASER_ENGINE;ExpectedMIRSha256=$profile.archive_sha256.Values[0]
                        Case='f100-f110-laser-transition';Historical=$false;HistoricalTransition=$false;Create=$false;Absent=$false;Active=$false;ActiveKind=''
                        InputSave='';InputSaveSha256='';Observer='';Markers=@();HistoricalTarget='';HistoricalMetadata='';TransitionStage='';TransitionMetadata='';Stage=$env:MIR_LASER_STAGE}
                      if($env:MIR_LASER_INPUT -ne ''){$base.InputSave='protected.zip';$base.InputSaveSha256=$env:MIR_LASER_INPUT}
                      $result=Get-F100F110LaserBridgeFixture @base
                      if($result.name -cne 'mir-fixture-mir5-f100-f110-laser-transition'){throw 'positive refused'}
                      $opponents=@(
                        @{name='case';patch=@{Case='historical-native'};message='case differs'},
                        @{name='active';patch=@{Active=$true};message='fixed installed-MIR route'},
                        @{name='observer';patch=@{Observer='active-mods'};message='observers or consumers'},
                        @{name='wrong-mir';patch=@{ExpectedMIRSha256=('0'*64)};message='archive hash differs'}
                      )
                      if($env:MIR_LASER_STAGE -eq 'source'){$opponents+=@{name='save';patch=@{InputSave='old.zip';InputSaveSha256=('a'*64)};message='does not accept an input save'}}else{$opponents+=@{name='missing-save';patch=@{InputSave='';InputSaveSha256=''};message='requires an immutable F100 source save hash'}}
                      foreach($opponent in $opponents){
                        $args=@{};foreach($key in $base.Keys){$args[$key]=$base[$key]};foreach($key in $opponent.patch.Keys){$args[$key]=$opponent.patch[$key]}
                        $refused=$false;try{Get-F100F110LaserBridgeFixture @args|Out-Null}catch{$refused=$_.Exception.Message.Contains($opponent.message)}
                        if(-not $refused){throw ('opponent accepted '+$opponent.name)}
                      }
                      $alias=Join-Path $env:MIR_LASER_SOURCE 'fixture_control.lua';[IO.File]::AppendAllText($alias,'changed')
                      $refused=$false;try{Get-F100F110LaserBridgeFixture @base|Out-Null}catch{$refused=$_.Exception.Message.Contains('stage member differs: fixture_control.lua')}
                      if(-not $refused){throw 'changed composed member accepted'}
                    '''
                    result = _run_powershell(script, env)
                    self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    arguments = parser.parse_args()
    lua_runtime = Path(arguments.lua_runtime_dir).resolve()
    if not lua_runtime.is_dir():
        raise SystemExit("invalid Lua runtime")
    sys.path.insert(0, str(lua_runtime))
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(F100F110LaserTransitionFixtureControls)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)

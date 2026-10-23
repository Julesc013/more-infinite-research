"""Host controls for the prepared F200 Expanded Productivity Research save chain.

These controls execute the fixture data stages and successor assertions against a
small native-shaped mock.  They prepare no Factorio process and do not qualify
save migration, laboratory behavior, or queue transition semantics.
"""
import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/competing-epr"
FACTS_PATH = ROOT / "tests/mir5/fixtures/competing-epr-f200-captured-facts.json"
CHAIN_PATH = ROOT / "spec/mir5/evidence/competing-epr-reference-chain.json"
PROFILES = (
    ROOT / "tests/mir5/profiles/competing-epr-published-4.7-f200-2077.json",
    ROOT / "tests/mir5/profiles/competing-epr-mir5-prefer-mir-f200-2077.json",
    ROOT / "tests/mir5/profiles/competing-epr-mir5-prefer-foreign-f200-2077.json",
)
NAME = "mir-fixture-mir5-competing-epr"
TAIL = "epr_iron-gear-wheel-productivity-5"
PROBE = "braking-force-1"
UINT32_MAX = 4294967295


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


class CompetingEprNativeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        cls.tail = deepcopy(next(row for row in cls.facts["removed_epr_tails"] if row["name"] == TAIL))
        cls.tail_names = tuple(row["name"] for row in cls.facts["removed_epr_tails"])

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function epr_fixture_data(path, mir, row)
            local raw={technology={[row.name]=row},["bool-setting"]={
              ["mir-prefer-this-mod-for-competing-techs"]={default_value=true}}}
            local env={mods={base="2.0.77",ExpandedProductivityResearch="1.3.8",["more-infinite-research"]=mir},data={raw=raw}}
            env._G=env;setmetatable(env,{__index=function(_, key)return _G[key]end})
            local settings_path=path:gsub("data%-final%-fixes%.lua$", "settings-updates.lua")
            local settings_chunk,settings_message=loadfile(settings_path,"t",env);assert(settings_chunk,settings_message)
            local settings_ok,settings_result=pcall(settings_chunk)
            if not settings_ok then return {ok=false,message=tostring(settings_result),row=row,raw=raw} end
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),row=row,raw=raw}
          end

          function epr_fixture_parse(path, mir, fixture)
            local callbacks,reads={events={}},{ }
            local env={script={active_mods={base="2.0.77",ExpandedProductivityResearch="1.3.8",
              ["more-infinite-research"]=mir,["mir-fixture-mir5-competing-epr"]=fixture},
              on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
              on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then reads[key]=(reads[key]or 0)+1 end
              return _G[key]
            end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end

          function epr_fixture_successor_flow(preferred_path, foreign_path, opponent, tails)
            local callbacks,markers,saves={events={}},0,0
            local function inventory()
              local value={items={}}
              function value.get_item_count(name)return value.items[name]or 0 end
              return value
            end
            local input=inventory()
            local lab={valid=true,active=false,energy=0}
            function lab.get_inventory(index)assert(index==1);return input end
            local function tech(name, force, level)
              return {name=name,valid=true,force=force,level=level or 5,researched=false,enabled=true,
                visible_when_disabled=false,saved_progress=0,
                prototype={max_level=4294967295},research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},
                  {name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1},
                  {name="utility-science-pack",amount=1},{name="space-science-pack",amount=1}}}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={['iron-gear-wheel']={productivity_bonus=.6}},research_queue={},research_progress=0}
              for _,tail in ipairs(tails) do value.technologies[tail]=tech(tail,value,tail:match("%-4$") and 4 or 5) end
              value.technologies["braking-force-1"]=tech("braking-force-1",value,1)
              return value
            end
            -- LuaForce owns active progress.  Queueing the first technology
            -- transfers its saved progress and empties the raw technology field.
            local function set_queue(value, entries)
              rawset(value, "research_queue", entries)
              local current = entries and entries[1] or nil
              rawset(value, "current_research", current)
              if current then
                rawset(value, "research_progress", current.saved_progress or 0)
                current.saved_progress = 0
              else rawset(value, "research_progress", 0) end
            end
            local player=force("player",1)
            local foreign=force("mir5-competing-epr-foreign",2)
            foreign.recipes['iron-gear-wheel'].productivity_bonus=.4
            for _,epr in ipairs(tails) do foreign.technologies[epr].enabled=false;foreign.technologies[epr].visible_when_disabled=true end
            local fprobe=foreign.technologies["braking-force-1"]
            fprobe.saved_progress=.42; set_queue(foreign,{fprobe})
            local tail=player.technologies["epr_iron-gear-wheel-productivity-5"]
            local probe=player.technologies["braking-force-1"]
            tail.level=7;tail.saved_progress=.27;probe.saved_progress=.42
            set_queue(player,{tail,probe})
            local game={forces={player=player,[1]=player,[2]=foreign,["mir5-competing-epr-foreign"]=foreign}}
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={mir5_competing_epr={phase="source-completed",source_mir="4.7.20002",fixture_version="0.1.0",
              actual_lab_completions=2,milestone="two-native-epr-tail-labs",prerequisite_seeding="completed-before-native-tail-labs",player_start_bonus=.4,player_bonus=.6,
              foreign_bonus=.4,foreign_force_index=2,foreign_queue={current="braking-force-1",queue={"braking-force-1"},progress=.42},
              foreign_current_saved_progress=0,
              player_queue={current="epr_iron-gear-wheel-productivity-5",queue={"epr_iron-gear-wheel-productivity-5","braking-force-1"},progress=.27},
              player_current_saved_progress=0,braking_inactive_saved_progress=.42,lab=lab}}
            local function load_control(path, version, preference)
              local c={events={}}
              local env={script={active_mods={base="2.0.77",ExpandedProductivityResearch="1.3.8",["more-infinite-research"]="5.0.20000",
                ["mir-fixture-mir5-competing-epr"]=version},on_init=function(f)c.init=f end,
                on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,on_event=function(e,f)c.events[e]=f end},
                defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage=storage,
                settings={startup={["mir-prefer-this-mod-for-competing-techs"]={value=preference}}},
                helpers={table_to_json=function(value)assert(value.status=="passed" and (value.stage=="initial" or value.stage=="reload"));return "{}"end},
                log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
              return ok and c or nil,tostring(result)
            end
            local function invoke(control, kind)
              local callback=kind=="tick" and control.events[1] or control[kind]
              if type(callback)~="function" then return false,"missing "..kind end
              local ok,result=pcall(callback);return ok,tostring(result)
            end
            -- Candidate runtime outcome under test; the fixture itself does not make these writes.
            -- Removing the active EPR tail pauses its effective force progress on that
            -- now-inactive technology, then makes braking current with its own progress.
            tail.saved_progress=player.research_progress;tail.enabled=false;tail.visible_when_disabled=true;set_queue(player,{probe})
            if opponent=="stale-disable" then tail.enabled=true
            elseif opponent=="lost-tail-progress" then tail.saved_progress=.26
            elseif opponent=="lost-braking" then player.research_progress=.41
            elseif opponent=="duplicate-current-progress" then probe.saved_progress=.42
            elseif opponent=="foreign-reenabled" then foreign.technologies["epr_iron-gear-wheel-productivity-5"].enabled=true
            elseif opponent=="stale-epr-current" then set_queue(player,{tail,probe}) end
            local preferred,message=load_control(preferred_path,"0.2.0",true);if not preferred then return {ok=false,message=message}end
            local ok,result=invoke(preferred,"changed");if not ok then return {ok=false,message=result}end
            if markers~=0 or saves~=0 then return {ok=false,message="preferred saved before native hosting tick"} end
            ok,result=invoke(preferred,"tick");if not ok then return {ok=false,message=result}end
            for _=1,2 do ok,result=invoke(preferred,"load");if not ok then return {ok=false,message=result}end;ok,result=invoke(preferred,"tick");if not ok then return {ok=false,message=result}end end
            -- Candidate release under test; the fixture itself does not re-enable player EPR research.
            if opponent~="stale-release" then tail.enabled=true;tail.visible_when_disabled=false end
            local released,message=load_control(foreign_path,"0.3.0",false);if not released then return {ok=false,message=message}end
            ok,result=invoke(released,"changed");if not ok then return {ok=false,message=result}end
            if markers~=3 or saves~=1 then return {ok=false,message="released saved before native hosting tick"} end
            ok,result=invoke(released,"tick");if not ok then return {ok=false,message=result}end
            for _=1,2 do ok,result=invoke(released,"load");if not ok then return {ok=false,message=result}end;ok,result=invoke(released,"tick");if not ok then return {ok=false,message=result}end end
            return {ok=true,message="",phase=storage.mir5_competing_epr.phase,tail_level=tail.level,tail_enabled=tail.enabled,
              tail_visible=tail.visible_when_disabled,tail_progress=tail.saved_progress,bonus=player.recipes['iron-gear-wheel'].productivity_bonus,
              probe_progress=probe.saved_progress,current_progress=player.research_progress,
              foreign_enabled=foreign.technologies["epr_iron-gear-wheel-productivity-5"].enabled,
              markers=markers,saves=saves}
          end
        ''')
        self.lua.execute(r'''
          function epr_fixture_source_flow(path, opponent, tails)
            local callbacks,markers,saves={events={}},0,0
            local function inventory()
              local value={items={}}
              function value.insert(row)value.items[row.name]=(value.items[row.name]or 0)+row.count;return row.count end
              function value.get_item_count(name)return value.items[name]or 0 end
              function value.clear()value.items={} end
              return value
            end
            local input=inventory()
            local lab={valid=true,active=true,energy=0}
            function lab.get_inventory(index)assert(index==1);return input end
            local function tech(name, force, level)
              return {name=name,valid=true,force=force,level=level or 5,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
                prototype={max_level=4294967295},prerequisites={},research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},{name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1},{name="utility-science-pack",amount=1},{name="space-science-pack",amount=1}}}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={['iron-gear-wheel']={productivity_bonus=.4}},research_queue={},research_progress=0}
              for _,tail in ipairs(tails) do value.technologies[tail]=tech(tail,value,tail:match("%-4$") and 4 or 5) end
              value.technologies["braking-force-1"]=tech("braking-force-1",value,1)
              value.technologies["epr_iron-gear-wheel-productivity-5"].prerequisites={{research_recursive=function() end}}
              setmetatable(value,{__newindex=function(target,key,item)
                rawset(target,key,item)
                if key=="research_queue" then
                  rawset(target,"current_research",item and item[1] or nil)
                  if item and item[1] then
                    rawset(target,"research_progress",item[1].saved_progress or 0)
                    rawset(item[1],"saved_progress",0)
                  else rawset(target,"research_progress",0) end
                end
              end})
              function value.enable_all_prototypes()end
              function value.add_research(research)
                if type(research)=="string" then research=value.technologies[research] end
                if research==nil or value.current_research~=nil then return false end
                local progress=research.saved_progress or 0
                research.saved_progress=0;value.current_research=research;value.research_queue={research};value.research_progress=progress;return true
              end
              return value
            end
            local player=force("player",1)
            if opponent=="probe-researched" then player.technologies["braking-force-1"].researched=true end
            local foreign=nil
            local game={tick=0,speed=1,forces={player=player,[1]=player},surfaces={}}
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
            function game.create_force(name)foreign=force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign end
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local c={events={}}
            local env={script={active_mods={base="2.0.77",ExpandedProductivityResearch="1.3.8",["more-infinite-research"]="4.7.20002",["mir-fixture-mir5-competing-epr"]="0.1.0"},
              on_init=function(f)c.init=f end,on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,on_event=function(e,f)c.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage=storage,
              settings={startup={["mir-prefer-this-mod-for-competing-techs"]={value=false}}},
              helpers={table_to_json=function(value)assert(value.status=="passed" and (value.stage=="initial" or value.stage=="reload"));return "{}"end},
              log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)}end
            ok,result=pcall(c.init);if not ok then return {ok=false,message=tostring(result)}end
            local tail=player.technologies["epr_iron-gear-wheel-productivity-5"]
            player.current_research=nil;player.research_queue={};tail.level=6;player.recipes['iron-gear-wheel'].productivity_bonus=.5
            ok,result=pcall(c.events[2],{research=tail});if not ok then return {ok=false,message=tostring(result)}end
            game.tick=game.tick+1;ok,result=pcall(c.events[1]);if not ok then return {ok=false,message=tostring(result)}end
            player.current_research=nil;player.research_queue={};tail.level=7;player.recipes['iron-gear-wheel'].productivity_bonus=opponent=="wrong-tail-bonus" and .59 or .6
            ok,result=pcall(c.events[2],{research=tail});if not ok then return {ok=false,message=tostring(result)}end
            -- Factorio's research_queue setter makes its first entry current. Remove the
            -- mock's raw field so its narrow metamethod models that native setter.
            player.research_queue=nil;player.current_research=nil
            game.tick=game.tick+1;ok,result=pcall(c.events[1]);if not ok then return {ok=false,message=tostring(result)}end
            if opponent=="unfrozen" then lab.active=true end
            for _=1,2 do ok,result=pcall(c.load);if not ok then return {ok=false,message=tostring(result)}end;game.tick=game.tick+1;ok,result=pcall(c.events[1]);if not ok then return {ok=false,message=tostring(result)}end end
            local state=storage.mir5_competing_epr
            return {ok=true,message="",phase=state.phase,labs=state.actual_lab_completions,next=tail.level,bonus=player.recipes['iron-gear-wheel'].productivity_bonus,
              tail_saved=tail.saved_progress,probe_saved=player.technologies["braking-force-1"].saved_progress,
              current_progress=player.research_progress,lab_active=lab.active,lab_energy=lab.energy,markers=markers,saves=saves}
          end
        ''')

    def row(self):
        return lua_value(self.lua, deepcopy(self.tail))

    def test_profiles_and_evidence_bind_the_exact_three_stage_closure(self):
        expected = (("4.7.20002", "0.1.0"), ("5.0.20000", "0.2.0"), ("5.0.20000", "0.3.0"))
        for path, (mir, fixture_version) in zip(PROFILES, expected):
            profile = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(("f200", "2.0.77"), (profile["target"], profile["engine"]["version"]))
            self.assertEqual(["base", "ExpandedProductivityResearch", "mir-fixture-mir5-active-mods-observer",
                              "more-infinite-research", NAME], [item["name"] for item in profile["mods"]])
            self.assertEqual(mir, profile["mods"][3]["version"])
            self.assertEqual(fixture_version, profile["mods"][4]["version"])
            self.assertNotIn("space-age", [item["name"] for item in profile["mods"]])
            info = json.loads((FIXTURE / {"0.1.0": "published", "0.2.0": "mir5-prefer-mir", "0.3.0": "mir5-prefer-foreign"}[fixture_version] / "info.json").read_text())
            self.assertEqual((NAME, fixture_version, "2.0"), (info["name"], info["version"], info["factorio_version"]))
        chain = json.loads(CHAIN_PATH.read_text(encoding="utf-8"))
        receipt_path = ROOT / chain["raw_reference_receipt"]["path"]
        compressed = receipt_path.read_bytes()
        self.assertEqual(chain["raw_reference_receipt"]["sha256"], hashlib.sha256(compressed).hexdigest().upper())
        raw = gzip.decompress(compressed)
        self.assertEqual(chain["raw_reference_receipt"]["uncompressed_sha256"], hashlib.sha256(raw).hexdigest().upper())
        receipt = json.loads(raw)
        self.assertEqual(39999658774, receipt["run"]["id"])
        self.assertEqual(30, receipt["observed_transition"]["removed_epr_infinite_tail_count"])
        self.assertEqual([str(path.relative_to(ROOT)).replace("\\", "/") for path in PROFILES],
                         [entry["path"] for entry in chain["profiles"]])
        for entry in chain["profiles"]:
            self.assertEqual(entry["sha256"], hashlib.sha256((ROOT / entry["path"]).read_bytes()).hexdigest().upper())
        self.assertFalse(chain["claims"]["native_save_chain_passed"])

    def test_captured_tail_preflight_precedes_the_only_disposable_count_time_mutation(self):
        variants = (("published", "4.7.20002", False), ("mir5-prefer-mir", "5.0.20000", True),
                    ("mir5-prefer-foreign", "5.0.20000", False))
        for directory, mir, preference in variants:
            with self.subTest(directory=directory):
                result = self.lua.eval("epr_fixture_data")(str(FIXTURE / directory / "data-final-fixes.lua"), mir, self.row())
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(preference, result["raw"]["bool-setting"]["mir-prefer-this-mod-for-competing-techs"]["default_value"])
                row = plain(result["row"])
                self.assertIsNone(row["unit"].get("count"))
                self.assertEqual(("1", 1), (row["unit"]["count_formula"], row["unit"]["time"]))
                self.assertEqual(self.tail["effects"], row["effects"])
                self.assertEqual(self.tail["prerequisites"], row["prerequisites"])
                self.assertEqual(self.tail["icons"], row["icons"])
                self.assertEqual(self.tail["localised_name"], row["localised_name"])
                self.assertEqual(self.tail["localised_description"], row["localised_description"])
        bad = self.row()
        bad["effects"][1]["change"] = .2
        result = self.lua.eval("epr_fixture_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), "4.7.20002", bad)
        self.assertFalse(result["ok"])
        self.assertIn("captured EPR gear tail effect changed", result["message"])
        self.assertEqual("1.5^(L-4)*1000", result["row"]["unit"]["count_formula"])
        self.assertEqual(60, result["row"]["unit"]["time"])

    def test_controls_parse_without_runtime_access_and_on_load_is_read_only(self):
        variants = (("published", "4.7.20002", "0.1.0"), ("mir5-prefer-mir", "5.0.20000", "0.2.0"),
                    ("mir5-prefer-foreign", "5.0.20000", "0.3.0"))
        for directory, mir, version in variants:
            with self.subTest(directory=directory):
                result = self.lua.eval("epr_fixture_parse")(str(FIXTURE / directory / "control.lua"), mir, version)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, plain(result["reads"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                if directory == "published":
                    self.assertIsNotNone(result["callbacks"]["init"])
                    self.assertIsNotNone(result["callbacks"]["events"][2])
                else:
                    self.assertIsNotNone(result["callbacks"]["changed"])
                control = (FIXTURE / directory / "control.lua").read_text(encoding="utf-8")
                body = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
                self.assertNotIn("game.", body, f"{directory} on_load touched LuaGameScript")
                self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=", f"{directory} on_load wrote fixture storage")
                self.assertNotIn("storage.mir_", control)
        source = (FIXTURE / "published" / "control.lua").read_text(encoding="utf-8")
        self.assertIn("await-second-queue", source)
        self.assertIn("two-native-epr-tail-labs", source)
        self.assertIn("state.lab.active = false", source)
        self.assertIn("input.clear()", source)
        self.assertIn("technology(player, TAIL).saved_progress = 0.27", source)
        self.assertIn("probe.saved_progress = 0.42", source)
        self.assertNotIn("research_queue_enabled", source)

    def test_source_uses_two_sequential_native_tail_completions_before_freezing(self):
        run = self.lua.eval("epr_fixture_source_flow")
        result = run(str(FIXTURE / "published" / "control.lua"), "", lua_value(self.lua, self.tail_names))
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(("source-completed", 2, 7, .6, 0, .42, .27),
                         (result["phase"], result["labs"], result["next"], result["bonus"], result["tail_saved"],
                          result["probe_saved"], result["current_progress"]))
        self.assertFalse(result["lab_active"])
        self.assertEqual(0, result["lab_energy"])
        self.assertEqual((3, 1), (result["markers"], result["saves"]))
        opponents = {
            "probe-researched": "unrelated braking probe was already researched",
            "wrong-tail-bonus": "two native EPR labs EPR tail state differs",
            "unfrozen": "source lab was not frozen before cap configuration",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = run(str(FIXTURE / "published" / "control.lua"), opponent, lua_value(self.lua, self.tail_names))
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
    def test_preference_successors_preserve_native_witnesses_and_reject_opponents(self):
        run = self.lua.eval("epr_fixture_successor_flow")
        result = run(str(FIXTURE / "mir5-prefer-mir" / "control.lua"), str(FIXTURE / "mir5-prefer-foreign" / "control.lua"), "", lua_value(self.lua, self.tail_names))
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("prefer-foreign-completed", result["phase"])
        self.assertEqual((7, .6, .27, 0, .42),
                         (result["tail_level"], result["bonus"], result["tail_progress"], result["probe_progress"], result["current_progress"]))
        self.assertTrue(result["tail_enabled"])
        self.assertFalse(result["tail_visible"])
        self.assertFalse(result["foreign_enabled"])
        self.assertEqual((6, 2), (result["markers"], result["saves"]))
        opponents = {
            "stale-disable": "MIR5 preferred player EPR tail state differs",
            "lost-tail-progress": "MIR5 preferred player EPR tail saved progress differs",
            "lost-braking": "MIR5 preferred player queue or progress differs",
            "duplicate-current-progress": "MIR5 duplicated current braking progress",
            "foreign-reenabled": "foreign EPR tail presentation changed",
            "stale-epr-current": "MIR5 preferred player EPR tail saved progress differs",
            "stale-release": "MIR5 released player EPR tail state differs",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = run(str(FIXTURE / "mir5-prefer-mir" / "control.lua"), str(FIXTURE / "mir5-prefer-foreign" / "control.lua"), opponent, lua_value(self.lua, self.tail_names))
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CompetingEprNativeFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

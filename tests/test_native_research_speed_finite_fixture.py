"""Finite7/MIR8 fixture preparation; Lua doubles never qualify native gameplay."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/native-research-speed-finite"


class FiniteResearchSpeedFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().oracle_path = (FIXTURE / "observer/oracle.lua").as_posix()
        self.lua.globals().provider_path = (FIXTURE / "provider/data-final-fixes.lua").as_posix()
        self.lua.globals().control_path = (FIXTURE / "observer/control.lua").as_posix()
        self.lua.execute(r'''
          O=dofile(oracle_path)
          function copy(value)
            if type(value)~="table" then return value end
            local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
          end
          table.deepcopy=copy
          function independent_prototypes()
            local six={type="technology",name="research-speed-6",effects={{type="laboratory-speed",modifier=.6}},
              prerequisites={"research-speed-5","utility-science-pack"},unit={count=500,time=30,
                ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
                  {"chemical-science-pack",1},{"production-science-pack",1},{"utility-science-pack",1}}}}
            data={raw={technology={[six.name]=six}},extend=function(self,rows)
              for _,row in ipairs(rows)do assert(not self.raw.technology[row.name]);self.raw.technology[row.name]=row end
            end}
            dofile(provider_path)
            local ingredients={};for i,name in ipairs(O.packs)do ingredients[i]={name,1}end
            data.raw.technology["research-speed-8"]={type="technology",name="research-speed-8",level=8,
              max_level="infinite",effects={{type="laboratory-speed",modifier=.6}},
              prerequisites=copy(O.gates),unit={count_formula="1025.15625*1.5^(L-8)",time=120,ingredients=ingredients}}
            return data.raw.technology
          end
          function fixture_flow(version,opponent)
            local callbacks={};local logs,saves,game_reads={},0,0
            local inventory_count=0
            local inventory={insert=function(row)inventory_count=inventory_count+row.count;return row.count end,
              clear=function()inventory_count=0 end,is_empty=function()return inventory_count==0 end}
            local force_index=0
            local function force(name)
              force_index=force_index+1
              local f={index=force_index,name=name,technologies={},research_queue={},research_progress=0,laboratory_speed_modifier=0}
              for _,id in ipairs({"research-speed-6","research-speed-7","research-speed-8","automation",
                  "automation-science-pack","logistic-science-pack","chemical-science-pack",
                  "production-science-pack","military-science-pack","utility-science-pack"})do
                f.technologies[id]={name=id,level=id=="research-speed-8" and 8 or 7,researched=false,
                  enabled=true,visible_when_disabled=false,saved_progress=0,force=f}
              end
              f.reset_technology_effects=function()f.laboratory_speed_modifier=1.2 end
              f.add_research=function(t)f.current_research=t;f.research_queue={t};return true end
              return setmetatable(f,{__newindex=function(self,key,value)
                rawset(self,key,value)
              end})
            end
            -- Queue assignment is a Factorio property. A proxy preserves that
            -- native property relationship without changing the fixture oracle.
            local function proxy(f)
              local q=f.research_queue;f.research_queue=nil
              return setmetatable(f,{__index=function(_,k)if k=="research_queue"then return q end end,
                __newindex=function(self,k,v)
                  if k=="research_queue"then q=v;self.current_research=v[1] else rawset(self,k,v)end
                end})
            end
            local p=proxy(force("player"));local forces={player=p,[p.index]=p}
            -- Pinned2.1.23 exposes active as read-only. Script disablement is
            -- writable and reflected by active; reject the original native fault.
            local entity_values={disabled_by_script=false,energy=0,get_inventory=function()return inventory end}
            local entity=setmetatable({},{__index=function(_,key)
                if key=="active"then return not entity_values.disabled_by_script end
                return entity_values[key]
              end,__newindex=function(_,key,value)
                assert(key~="active","LuaEntity.active is read-only")
                entity_values[key]=value
              end})
            assert(not pcall(function()entity.active=false end),"host double permits read-only active write")
            local game_value={tick=0,forces=forces,surfaces={{create_entity=function()return entity end}},
              create_force=function(name)local f=proxy(force(name));forces[f.index]=f;return f end,
              server_save=function(name)assert(name=="mir5-native-complete");saves=saves+1 end}
            local env={storage={},settings={startup={["mir-max-level-research-speed"]={value=0}}},
              prototypes={get_history=function(_,name)return {created=name=="research-speed-7"
                and "mir-fixture-finite-base-extension-level" or "more-infinite-research"}end},
              defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}},
              helpers={table_to_json=function(value)logs[#logs+1]=value;return "host-double" end},log=function()end}
            env.script={active_mods={base="2.1.23",["more-infinite-research"]=version,
              ["mir-fixture-finite-base-extension-level"]="0.1.0",["mir-fixture-native-research-speed-finite"]="0.1.0"},
              on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,
              on_configuration_changed=function(f)callbacks.changed=f end,on_event=function(e,f)callbacks[e]=f end}
            env.require=function(name)assert(name=="__mir-fixture-native-research-speed-finite__/oracle");return O end
            setmetatable(env,{__index=function(_,key)if key=="game"then game_reads=game_reads+1;return game_value end;return _G[key]end})
            assert(loadfile(control_path,"t",env))();assert(game_reads==0,"game read while parsing")
            callbacks.init()
            assert(p.technologies["research-speed-8"].level==8,"fixture seeded MIR8")
            p.technologies["research-speed-8"].level=9
            p.laboratory_speed_modifier=1.8
            p.current_research=nil;p.research_queue={}
            callbacks[2]({research=p.technologies["research-speed-8"]})
            assert(entity.disabled_by_script and not entity.active and entity.energy==0
              and inventory.is_empty(),"completed lab can still work")
            callbacks[1]()
            assert(saves==1 and #logs==1 and logs[1].stage=="initial")
            local state=env.storage.mir_native_research_speed_finite
            assert(state.completions==1 and O.close(state.player.queue.progress,.42))
            local before=game_reads;callbacks.load();assert(game_reads==before,"on_load read game")
            callbacks[1]();assert(logs[#logs].stage=="reload")
            if version=="4.7.21003" then
              env.script.active_mods["more-infinite-research"]="5.0.21007"
              if opponent=="lost-level"then p.technologies["research-speed-8"].level=8
              elseif opponent=="lost-bonus"then p.laboratory_speed_modifier=1.2
              elseif opponent=="foreign-enabled"then p.technologies["research-speed-7"].enabled=true
              elseif opponent=="lost-queue"then p.research_queue={p.technologies["research-speed-8"]}
              elseif opponent=="lost-progress"then p.research_progress=0
              elseif opponent=="lost-paused"then forces[state.paused_index].technologies["research-speed-8"].saved_progress=0
              elseif opponent=="lab-enabled"then entity.disabled_by_script=false
              elseif opponent=="lab-energy"then entity.energy=1
              elseif opponent=="lab-input"then inventory.insert{name="automation-science-pack",count=1} end
              local ok,message=pcall(callbacks.changed,{mod_changes={
                ["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21007"}}})
              if opponent then assert(not ok,"broken transition admitted: "..opponent);assert(saves==1);return end
              assert(ok,message);callbacks[1]();assert(saves==2)
              for _=1,2 do callbacks.load();callbacks[1]() end
              assert(#logs==5 and logs[3].stage=="initial" and logs[4].stage=="reload" and logs[5].stage=="reload")
            end
          end
        ''')

    def test_provider_is_exact_original_published_fixture(self):
        expected = {
            "data-final-fixes.lua": "ff786df22eabb9725f7b193f4b4e3971ed494c462c7e8d1e53ce33ad8a664ffa",
        }
        for name, sha in expected.items():
            self.assertEqual(hashlib.sha256((FIXTURE / "provider" / name).read_bytes()).hexdigest(), sha)
        info = json.loads((FIXTURE / "provider/info.json").read_text())
        self.assertEqual(info["name"], "mir-fixture-finite-base-extension-level")
        self.assertEqual(info["version"], "0.1.0")

    def test_profiles_pin_identical_nonmir_archives_and_rebuild_exact_fixtures(self):
        profiles = [json.loads((ROOT / "tests/profiles" / name).read_text()) for name in (
            "native-research-speed-finite-published-f210.json", "native-research-speed-finite-current-f210.json")]
        self.assertEqual(profiles[0]["engine"], {"version": "2.1.23", "sha256":
            "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38"})
        self.assertEqual(profiles[0]["engine"], profiles[1]["engine"])
        nonmir = lambda profile: [row for row in profile["mods"] if row["name"] != "more-infinite-research"]
        pins = lambda profile: {key: value for key, value in profile["archive_sha256"].items()
                                if not key.startswith("more-infinite-research_")}
        self.assertEqual(nonmir(profiles[0]), nonmir(profiles[1]))
        self.assertEqual(pins(profiles[0]), pins(profiles[1]))
        spec = importlib.util.spec_from_file_location("finite_fixture_package", ROOT / "tools/package.py")
        package = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(package)
        scratch = ROOT / "build/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="finite-fixture-host-", dir=scratch) as directory:
            for source in (FIXTURE / "provider", FIXTURE / "observer", ROOT / "tests/fixtures/active-mods-observer"):
                info = json.loads((source / "info.json").read_text())
                name = info["name"] + "_" + info["version"] + ".zip"
                record = package.build(source, Path(directory) / name)
                self.assertEqual(record["sha256"].upper(), pins(profiles[0])[name])

    def test_independent_prototype_oracle_and_provider_preservation(self):
        self.lua.execute('local raw=independent_prototypes();O.prototypes(raw);assert(raw["research-speed-6"].unit.count==500)')

    def test_mir_context_capture_preserves_actual_absent_or_adverse_row(self):
        self.lua.globals().capture_path = (FIXTURE / "observe-published.lua").as_posix()
        self.lua.execute(r'''
          for _,mode in ipairs({"absent","adverse","present"})do
            local original={technology="research-speed-8",selected="infinite",
              binding_fingerprint=mode=="adverse" and "actual-adverse-value" or "mir32-12345678"}
            if mode=="absent"then original=nil end
            local saved={mir={maximum_level_control={policy_version=3,managed_technologies={
              ["research-speed-8"]=original}}}}
            local output
            local env={storage=saved,script={active_mods={base="2.1.23",["more-infinite-research"]="4.7.21003"}},
              settings={startup={}},game={tick=123},prototypes={get_history=function()return {created="actual-native-owner"}end},
              helpers={table_to_json=function(out)output=out;return "host-double"end,
                write_file=function(name,body,append)assert(name=="mir-finite-source-producer.json" and not append)end},
              rcon={print=function()end}}
            setmetatable(env,{__index=function(_,key)return _G[key]end})
            assert(loadfile(capture_path,"t",env))()
            assert(output.row_present==(mode~="absent") and saved.mir.maximum_level_control.managed_technologies["research-speed-8"]==original)
            if original then
              assert(output.managed_eight~=original and output.managed_eight.binding_fingerprint==original.binding_fingerprint)
            else assert(output.managed_eight==false) end
          end
        ''')

    def test_oracle_rejects_duplicate_identity_and_mutated_foreign_or_eight(self):
        for change in (
            'raw["research-speed-8"]=nil',
            'raw["research-speed-7"].max_level="infinite"',
            'raw["research-speed-7"].unit.count=1',
            'raw["research-speed-7"].effects[1].modifier=.3',
            'raw["research-speed-7"].unit.ingredients[2]={"utility-science-pack",1}',
            'raw["research-speed-8"].unit.count_formula="777"',
            'raw["research-speed-8"].prerequisites[2]="research-speed-6"',
            'raw["research-speed-8"].unit.ingredients[5]={"space-science-pack",1}',
            'raw["research-speed-8"].effects[2]={type="laboratory-speed",modifier=.6}',
        ):
            with self.subTest(change=change):
                self.lua.execute('local raw=independent_prototypes();' + change + ';assert(not pcall(O.prototypes,raw))')

    def test_source_successor_two_reloads_with_one_unchanged_observer(self):
        self.lua.execute('fixture_flow("4.7.21003")')

    def test_fresh_current(self):
        self.lua.execute('fixture_flow("5.0.21007")')

    def test_transition_negatives_fail_before_successor_save(self):
        for opponent in ("lost-level", "lost-bonus", "foreign-enabled", "lost-queue", "lost-progress", "lost-paused",
                         "lab-enabled", "lab-energy", "lab-input"):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent = opponent
                self.lua.execute('fixture_flow("4.7.21003",opponent)')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FiniteResearchSpeedFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

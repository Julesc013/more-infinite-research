"""Recovered Secretas finite-tail expectations through current source; host only."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

from historical_sources import read_published_source
import test_generator as scaffold
import test_lifecycle as lifecycle_fixture

ROOT = Path(__file__).resolve().parents[1]
EDITIONS = json.loads((ROOT / "targets/editions.json").read_text())["targets"]
SOURCE_VERSION = json.loads((ROOT / "source/info.json").read_text())["version"]
NINE = "worker-robots-storage-9"
PACKS = [name + "-science-pack" for name in (
    "automation", "logistic", "chemical", "production", "utility", "space",
    "metallurgic", "electromagnetic", "agricultural", "cryogenic", "golden", "promethium")]


def finite_inputs():
    # Independent literal facts shared by exact Secretas1.0.33 and1.0.37:
    # technology.lua BEF84B51... and0073FC1A..., retained under CONT07.
    # Do not obtain expectations from MIR's candidate selector.
    return {"worker-robots-storage-" + str(level): {
        "type": "technology", "name": "worker-robots-storage-" + str(level),
        "upgrade": True, "prerequisites": ["worker-robots-storage-" + str(level - 1)]
            + (["planet-discovery-secretas"] if level == 4 else []),
        "effects": [{"type": "worker-robot-storage", "modifier": 1}],
        "unit": {"count": 900 * 2 ** (level - 4), "time": 60,
                 "ingredients": [[name, 1] for name in (PACKS if level == 8 else PACKS[:-1])]},
        "foreign_field": {"preserve": [level, "Secretas"]},
    } for level in range(4, 9)}


class SecretasContinuationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        original = read_published_source(ROOT,
            "fixtures/assert-secretas-finite-continuation-hotfix/control.lua",
            "B1868A92B32D7F5BE4D2470AAD53139CEC65A182030F3A55D01E49456F238703").decode()
        assert original.count("local function queue(") == 1
        # Retain the original shape/effect/science assertions. Historical
        # engine/mod version guards and native save callbacks are not run here.
        cls.original_oracle = original.split("local function queue(", 1)[0] + "\nreturn technologies"

    def stage(self, target_id="f210", inputs=None, changes=None, provider=True):
        scaffold.LuaRuntime = LuaRuntime
        harness = scaffold.GeneratorTests()
        harness.setUp()
        lua = harness.lua
        major, minor, encoded_patch = SOURCE_VERSION.split(".")
        version = f"{major}.{minor}.{int(target_id[1:]) * 100 + int(encoded_patch) % 100:05d}"
        lua.globals().selected_target = scaffold.lua_table(lua, {
            **EDITIONS[target_id], "id": target_id, "distribution_version": version})
        lua.globals().finite_rows = scaffold.lua_table(lua, inputs if inputs is not None else finite_inputs())
        lua.globals().selected_changes = scaffold.lua_table(lua, changes or {})
        lua.globals().selected_provider = provider
        lua.execute('''
          local target=require("platform.target")
          for key,value in pairs(selected_target) do target[key]=value end
          mods={base=target.minimum_base,["space-age"]=target.minimum_base}
          if selected_provider then mods.secretas=target.id=="f200" and "1.0.33" or "1.0.37" end
          package.loaded["research.settings"]=nil
          config=require("research.settings")
          local startup={}
          for _,spec in ipairs(config.prototypes()) do startup[spec.name]={value=spec.default_value} end
          for name,value in pairs(selected_changes) do startup[name].value=value end
          settings,data,helpers,log={startup=startup},full_world(mods,true),nil,function() end
          -- The always-present default preservation row retains native2 as
          -- an authored prerequisite even while public research starts at9.
          data.raw.technology["worker-robots-storage-2"]=data.raw.technology["worker-robots-storage-2"]
            or {type="technology",name="worker-robots-storage-2"}
          data.raw.technology["worker-robots-storage-3"]=data.raw.technology["worker-robots-storage-3"]
            or {type="technology",name="worker-robots-storage-3",prerequisites={"worker-robots-storage-2"},
              effects={{type="worker-robot-storage",modifier=1}},
              unit={count=450,time=60,ingredients={{"automation-science-pack",1}}}}
          for name,row in pairs(finite_rows) do data.raw.technology[name]=row end
          data.raw.tool["golden-science-pack"]={}
          data.raw.lab.fixture.inputs[#data.raw.lab.fixture.inputs+1]="golden-science-pack"
          function data:extend(rows)
            self.writes=self.writes+1;self.emitted=rows
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate publication")
              self.raw[row.type][row.name]=row
            end
          end
          dofile(player_root.."/data.lua")
          data.writes,data.emitted=0,nil
        ''')
        return lua

    def pipeline(self, lua):
        lua.execute("dofile(data_final_path)")

    def oracle(self, lua):
        lua.execute('''
          local technologies={}
          for level=4,9 do
            local name="worker-robots-storage-"..level
            local row=data.raw.technology[name]
            if row then
              local prerequisites,science={},{}
              for _,id in ipairs(row.prerequisites or {}) do prerequisites[#prerequisites+1]={name=id} end
              for _,item in ipairs(row.unit.ingredients) do science[#science+1]={name=item[1],amount=item[2]} end
              technologies[name]={name=name,prototype={effects=row.effects,
                max_level=row.max_level=="infinite" and 4294967295 or level},
                prerequisites=prerequisites,research_unit_ingredients=science}
            end
          end
          game={forces={player={technologies=technologies}}}
        ''')
        lua.execute(self.original_oracle)()

    def test_full_pipeline_preserves_five_finite_inputs_and_satisfies_published_oracle(self):
        for target_id in ("f200", "f210"):
            with self.subTest(target=target_id):
                lua = self.stage(target_id)
                self.pipeline(lua)
                self.assertEqual(1, lua.globals().data.writes)
                for name, expected in finite_inputs().items():
                    self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))
                row = scaffold.plain_lua(lua.globals().data.raw.technology[NINE])
                self.assertEqual(["worker-robots-storage-8"], row["prerequisites"])
                self.assertEqual([[name, 1] for name in PACKS], row["unit"]["ingredients"])
                self.assertEqual([{"type": "worker-robot-storage", "modifier": 1}], row["effects"])
                self.oracle(lua)
                lua.execute('''
                  data.raw.technology["worker-robots-storage-9"].unit.ingredients[11][1]="caller-mutated"
                  data.raw.technology["worker-robots-storage-9"].effects[1].modifier=31
                  assert(data.raw.technology["worker-robots-storage-8"].unit.ingredients[11][1]=="golden-science-pack")
                  assert(data.raw.technology["worker-robots-storage-8"].effects[1].modifier==1)
                ''')

    def test_inherited_and_explicit_settings_use_last_finite_stage_without_mutation(self):
        inputs = finite_inputs()
        inputs["worker-robots-storage-8"]["effects"][0]["modifier"] = 3
        inputs["worker-robots-storage-8"]["unit"]["time"] = 37
        for target_id in ("f200", "f210"):
            for effect, time in ((1, 0), (2, 19)):
                lua = self.stage(target_id, inputs, {
                    "mir-cost-base-worker-robots-storage": 0,
                    "mir-cost-growth-worker-robots-storage": 0,
                    "mir-effect-per-level-worker-robots-storage": effect,
                    "mir-research-time-worker-robots-storage": time})
                self.pipeline(lua)
                row = lua.globals().data.raw.technology[NINE]
                self.assertEqual(3 * effect, row.effects[1].modifier)
                self.assertEqual(time or 37, row.unit.time)
                evaluate = lua.eval("function(text,L) return load('return function(L) return '..text..' end')()(L) end")
                self.assertAlmostEqual(28800, evaluate(row.unit.count_formula, 9), delta=.1)
                self.assertAlmostEqual(57600, evaluate(row.unit.count_formula, 10), delta=.2)
                for name, expected in inputs.items():
                    self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))

    def test_disabled_continuation_keeps_identity_and_finite_chain(self):
        lua = self.stage(changes={"mir-enable-worker-robots-storage": False})
        self.pipeline(lua)
        self.assertFalse(lua.globals().data.raw.technology[NINE].enabled)
        for name, expected in finite_inputs().items():
            self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))

    def test_each_qualified_existing_infinite_stage_keeps_ownership_and_full_definition(self):
        for target_id in ("f200", "f210"):
            for level in range(4, 10):
                inputs = finite_inputs()
                name = "worker-robots-storage-" + str(level)
                inputs[name] = deepcopy(inputs.get(name, inputs["worker-robots-storage-8"]))
                inputs[name].update(name=name, max_level="infinite", level=level,
                                    prerequisites=["worker-robots-storage-" + str(level - 1)])
                lua = self.stage(target_id, inputs)
                self.pipeline(lua)
                self.assertEqual(inputs[name], scaffold.plain_lua(lua.globals().data.raw.technology[name]))
                if level != 9:
                    self.assertIsNone(lua.globals().data.raw.technology[NINE])

    def test_missing_malformed_and_unrelated_inputs_refuse_without_publication(self):
        opponents = []
        for level in range(4, 9):
            inputs = finite_inputs()
            del inputs["worker-robots-storage-" + str(level)]
            opponents.append(inputs)
        for field, value in (("prerequisites", []), ("effects", [])):
            inputs = finite_inputs()
            inputs["worker-robots-storage-8"][field] = value
            opponents.append(inputs)
        for field, value in (("count", 0), ("time", 0), ("ingredients", [["golden-science-pack", 0]])):
            inputs = finite_inputs()
            inputs["worker-robots-storage-8"]["unit"][field] = value
            opponents.append(inputs)
        inputs = finite_inputs()
        inputs[NINE] = {"name": NINE, "type": "technology", "max_level": "infinite",
                        "effects": [{"type": "laboratory-speed", "modifier": .3}]}
        opponents.append(inputs)
        for inputs in opponents:
            lua = self.stage(inputs=inputs)
            with self.assertRaises(LuaError):
                self.pipeline(lua)
            self.assertEqual(0, lua.globals().data.writes)
            for name, expected in inputs.items():
                self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))

    def test_valid_unnamed_provider_continues_and_internal_duplicates_still_refuse(self):
        lua = self.stage(provider=False)
        # The previous expectation required a crash for these same valid
        # finite inputs without the Secretas flag. Ownership follows the
        # actual connected chain, not the provider's display name.
        self.pipeline(lua)
        self.assertEqual(1, lua.globals().data.writes)
        for name, expected in finite_inputs().items():
            self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))
        self.oracle(lua)
        lua = self.stage()
        lua.execute('''
          local selected=modern_catalogue.continuations(mods,data.raw)
          local row
          for _,definition in ipairs(selected) do
            if definition.id=="worker-robots-storage-9" then row=modern.continuation(definition,config.resolve(settings.startup)) end
          end
          refused({row,row},data,"duplicate technology worker-robots-storage-9")
        ''')

    def test_runtime_creator_controls_caps_and_earlier_foreign_tail_suppression(self):
        for target_id in ("f200", "f210"):
            for level in range(4, 10):
                for mir_created in (False, True):
                    lua = self.stage(target_id)
                    lua.globals().selected_level, lua.globals().mir_created = level, mir_created
                    lua.execute('''
                      local name="worker-robots-storage-"..selected_level
                      local technologies={}
                      for level=4,8 do technologies["worker-robots-storage-"..level]={max_level=level} end
                      technologies[name]={max_level=4294967295,enabled=true}
                      if mir_created then technologies["worker-robots-storage-9"]={max_level=4294967295,enabled=true} end
                      prototypes={recipe={},technology=technologies,get_history=function(kind,id)
                        assert(kind=="technology")
                        return {created=mir_created and id=="worker-robots-storage-9" and "more-infinite-research" or "secretas",
                          changed={"science-spread"}}
                      end}
                      script={active_mods=mods}
                      game=setmetatable({}, {__index=function() error("parse read game") end})
                      for _,id in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
                        package.loaded[id]=nil
                      end
                      local catalogue=require("runtime.catalogue")
                      local nine
                      for _,row in ipairs(catalogue.declared()) do if row.id=="worker-robots-storage-9" then nine=row end end
                      assert((nine~=nil)==mir_created,"wrong ownership for MIR9")
                      if nine then assert(nine.family=="worker-robots-storage" and nine.progression==9) end
                      settings.startup["mir-max-level-worker-robots-storage"].value=10
                      local native={name="worker-robots-storage-9",valid=true,level=11,enabled=true,
                        researched=false,saved_progress=.27,visible_when_disabled=false,
                        prototype=technologies["worker-robots-storage-9"] or {max_level=4294967295,enabled=true}}
                      local world={index=1,valid=true,technologies={[native.name]=native},research_queue={}}
                      game,storage={forces={[1]=world}},{}
                      local lifecycle=require("runtime.lifecycle")
                      assert((lifecycle.cap_limits(world)[native.name]~=nil)==mir_created)
                      lifecycle.on_init()
                      assert(native.enabled==not mir_created and native.level==11 and native.saved_progress==.27)
                      local records=storage.mir_caps and storage.mir_caps.owned_disabled[1]
                      assert((records and records[native.name]~=nil or false)==mir_created)
                    ''')

    def test_provider_changes_refuse_before_writes_but_existing_provider_upgrade_is_admitted(self):
        lifecycle_fixture.LuaRuntime = LuaRuntime
        for target_id in ("f200", "f210"):
            harness = lifecycle_fixture.LifecycleTests()
            harness.setUp()
            harness.lua.globals().target_id = target_id
            harness.lua.execute('''
              local target=require("platform.target");target.id=target_id
              local world=force(1,{}, {},nil,nil)
              for _,change in ipairs({{new_version="1.0.37"},{old_version="1.0.37"}}) do
                local saved=setmetatable({}, {__newindex=function() error("state write before Secretas guard") end})
                boot({[1]=world},0,"",saved,nil,0,{base=target.minimum_base})
                local ok,message=pcall(handlers.configuration,{mod_changes={secretas=change}})
                assert(not ok and tostring(message):find("cannot safely add or remove Secretas",1,true),tostring(message))
                assert(next(saved)==nil and #world.research_queue==0)
              end
              boot({[1]=world},0,"",nil,nil,0,{base=target.minimum_base})
              handlers.configuration({mod_changes={secretas={new_version="1.0.37"},
                ["more-infinite-research"]={new_version=target.distribution_version}}})
              handlers.configuration({mod_changes={secretas={old_version="1.0.33",new_version="1.0.37"}}})
            ''')

    def test_existing_paid_nine_and_foreign_current_work_keep_owned_cap_restoration(self):
        for target_id in ("f200", "f210"):
            lua = self.stage(target_id)
            self.pipeline(lua)
            lua.execute('''
              local target=require("platform.target")
              local prototype=data.raw.technology["worker-robots-storage-9"]
              prototype.max_level,prototype.enabled=4294967295,true
              local native={name=prototype.name,valid=true,level=12,researched=false,
                enabled=true,visible_when_disabled=false,saved_progress=.27,prototype=prototype}
              local current={name="foreign-current",valid=true,level=3,enabled=true}
              local world={index=1,valid=true,technologies={[native.name]=native,[current.name]=current},
                research_queue={current,native},current_research=current,research_progress=.42}
              current.force,native.force=world,world
              prototypes={recipe={},technology={[native.name]=prototype},get_history=function(kind,name)
                assert(kind=="technology" and name==native.name)
                return {created="more-infinite-research",changed={"science-spread"}}
              end}
              script,game,storage={active_mods=mods},{forces={[1]=world}},{}
              settings.startup["mir-max-level-worker-robots-storage"].value=10
              for _,id in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
                package.loaded[id]=nil
              end
              require("runtime.lifecycle").on_configuration_changed({mod_changes={
                ["more-infinite-research"]={old_version="4.7."..(tonumber(target.id:sub(2))*100+3),
                  new_version=target.distribution_version}}})
              assert(not native.enabled and native.level==12 and native.saved_progress==.27 and not native.researched)
              assert(storage.mir_caps.owned_disabled[1][native.name].disabled)
              assert(#world.research_queue==1 and world.research_queue[1]==current)
              assert(world.current_research==current and world.research_progress==.42)
              -- Simulate the next control parse under the uncapped startup
              -- selection; retained storage is preserved, not reconstructed.
              settings.startup["mir-max-level-worker-robots-storage"].value=0
              package.loaded["runtime.configuration"],package.loaded["runtime.lifecycle"]=nil,nil
              require("runtime.lifecycle").on_configuration_changed({})
              assert(native.enabled and native.level==12 and native.saved_progress==.27 and not native.researched)
              local rights=storage.mir_caps and storage.mir_caps.owned_disabled[1]
              assert(rights==nil or rights[native.name]==nil)
              assert(world.current_research==current and world.research_progress==.42)
            ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SecretasContinuationTests))
    sys.exit(0 if result.wasSuccessful() else 1)

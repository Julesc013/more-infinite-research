"""Foreign worker-storage chains through the normal pipeline; host controls only."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

import test_generator as scaffold

ROOT = Path(__file__).resolve().parents[1]
EDITIONS = json.loads((ROOT / "targets/editions.json").read_text())["targets"]
TRANSPORT = "more-infinite-research-native-adoptions"
SCIENCE = [["automation-science-pack", 2], ["logistic-science-pack", 3], ["utility-science-pack", 4]]
SCIENCE_GATES = ["automation-science-pack", "logistic-science-pack", "utility-science-pack"]
PUBLISHED_WORKER = json.loads((ROOT / "tests/fixtures/worker-storage-published-473.json").read_text())


def finite_chain(last=4):
    """Independent synthetic provider, deliberately not named Secretas."""
    return {f"worker-robots-storage-{level}": {
        "type": "technology", "name": f"worker-robots-storage-{level}", "upgrade": True,
        "prerequisites": [f"worker-robots-storage-{level - 1}"],
        "effects": [{"type": "worker-robot-storage", "modifier": 2}],
        "unit": {"count": 1000 * 2 ** (level - 4), "time": 37, "ingredients": deepcopy(SCIENCE)},
        "foreign_field": {"keep": [level, "unnamed-planet-provider"]},
    } for level in range(4, last + 1)}


class WorkerStorageContinuationTests(unittest.TestCase):
    def stage(self, rows=None, target_id="f210", changes=None, extra_mods=None):
        scaffold.LuaRuntime = LuaRuntime
        harness = scaffold.GeneratorTests()
        harness.setUp()
        lua = harness.lua
        lua.globals().selected_target = scaffold.lua_table(lua, {**EDITIONS[target_id], "id": target_id})
        lua.globals().foreign_rows = scaffold.lua_table(lua, rows or {})
        lua.globals().selected_changes = scaffold.lua_table(lua, changes or {})
        lua.globals().extra_mods = scaffold.lua_table(lua, extra_mods or {})
        lua.execute('''
          local target=require("platform.target")
          for key,value in pairs(selected_target)do target[key]=value end
          mods={base=target.minimum_base,["unnamed-planet-provider"]="1.0.0"}
          for name,version in pairs(extra_mods)do mods[name]=version end
          package.loaded["research.settings"]=nil
          local config=require("research.settings");settings={startup={}}
          for _,spec in ipairs(config.prototypes())do settings.startup[spec.name]={value=spec.default_value}end
          for key,value in pairs(selected_changes)do settings.startup[key].value=value end
          data,helpers,log=full_world(mods,true),nil,function()end
          data.raw.technology["worker-robots-storage-3"]={type="technology",name="worker-robots-storage-3",
            upgrade=true,prerequisites={"worker-robots-storage-2"},
            effects={{type="worker-robot-storage",modifier=1}},
            unit={count=450,time=60,ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
              {"chemical-science-pack",1},{"utility-science-pack",1}}}}
          for name,row in pairs(foreign_rows)do data.raw.technology[name]=row end
          function data:extend(rows)
            self.writes=self.writes+1;self.emitted=rows
            for _,row in ipairs(rows)do
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

    def runtime(self, lua):
        lua.execute('''
          native_prototypes={}
          for name,row in pairs(data.raw.technology)do
            if name:match("^worker%-robots%-storage%-%d+$")then
              local level=tonumber(name:match("(%d+)$"))
              native_prototypes[name]={name=name,level=level,enabled=row.enabled~=false,
                max_level=row.max_level=="infinite" and 4294967295 or row.max_level or level,
                effects=row.effects,prerequisites=row.prerequisites}
            end
          end
          script={active_mods=mods}
          history_reads={}
          prototypes={recipe={},technology=setmetatable(native_prototypes,{__pairs=function()error("whole technology scan")end}),
            mod_data={["more-infinite-research-native-adoptions"]={
              data=data.raw["mod-data"]["more-infinite-research-native-adoptions"].data}},
            get_history=function(kind,name)
              assert(kind=="technology");history_reads[name]=(history_reads[name]or 0)+1
              return {created=foreign_rows[name] and "unnamed-planet-provider" or "more-infinite-research",
                changed={"science-spread"}}
            end}
          function parse_worker_catalogue()
            for _,id in ipairs({"research.catalogue","runtime.catalogue","runtime.configuration","runtime.lifecycle"})do
              package.loaded[id]=nil
            end
            return require("runtime.catalogue")
          end
          game=setmetatable({}, {__index=function()error("control parse read game")end})
        ''')

    def test_finite_foreign_four_preserved_and_useful_five_emitted(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                inputs = finite_chain()
                lua = self.stage(inputs, target)
                self.pipeline(lua)
                self.assertEqual(1, lua.globals().data.writes)
                self.assertEqual(inputs["worker-robots-storage-4"], scaffold.plain_lua(
                    lua.globals().data.raw.technology["worker-robots-storage-4"]))
                row = scaffold.plain_lua(lua.globals().data.raw.technology["worker-robots-storage-5"])
                self.assertEqual("infinite", row["max_level"])
                self.assertEqual(5, row["level"])
                self.assertEqual(["worker-robots-storage-3", "worker-robots-storage-4"] + SCIENCE_GATES,
                    row["prerequisites"])
                self.assertEqual(SCIENCE, row["unit"]["ingredients"])
                self.assertEqual([{"type": "worker-robot-storage", "modifier": 2}], row["effects"])

    def test_configured_science_matches_genuine_473_native_capture(self):
        # This expectation was captured by the real2.1.24 engine loading the
        # unmodified published4.7.21003 ZIP with the checked-in provider.
        # It is independent of the candidate constructor and authored rows.
        lua = self.stage(finite_chain())
        self.pipeline(lua)
        observed = PUBLISHED_WORKER["observation"]["prototype"]
        row = scaffold.plain_lua(lua.globals().data.raw.technology["worker-robots-storage-5"])
        self.assertEqual([[item["name"], item["amount"]] for item in observed["ingredients"]],
            row["unit"]["ingredients"])
        self.assertEqual(observed["count_formula"], row["unit"]["count_formula"])
        self.assertEqual(observed["research_time"] / 60, row["unit"]["time"])
        self.assertEqual([{"type": effect["type"], "modifier": effect["modifier"]}
            for effect in observed["effects"]], row["effects"])
        published = PUBLISHED_WORKER["published_technology"]
        self.assertEqual(published["prerequisites"], row["prerequisites"])
        self.assertEqual(published["unit"], row["unit"])

    def test_only_explicit_electromagnetic_addition_and_requested_policy_expand_science(self):
        cases = [({}, {}, False, SCIENCE),
            ({"space-age": "2.1.24"}, {}, False, SCIENCE + [["electromagnetic-science-pack", 1]]),
            ({"space-age": "2.1.24"}, {}, True, SCIENCE + [["electromagnetic-science-pack", 7]]),
            ({}, {"mir-science-pack-ingredient-policy": "official-progression"}, False,
                SCIENCE + [["chemical-science-pack", 1], ["production-science-pack", 1]])]
        for mods, changes, inherited_em, expected in cases:
            with self.subTest(mods=mods, policy=changes, inherited_em=inherited_em):
                inputs = finite_chain()
                if inherited_em:
                    inputs["worker-robots-storage-4"]["unit"]["ingredients"].append(
                        ["electromagnetic-science-pack", 7])
                lua = self.stage(inputs, changes=changes, extra_mods=mods)
                self.pipeline(lua)
                row = lua.globals().data.raw.technology["worker-robots-storage-5"]
                self.assertEqual(expected, scaffold.plain_lua(row.unit.ingredients))
                expected_gates = SCIENCE_GATES + (["electromagnetic-science-pack"] if mods else [])
                if changes:
                    expected_gates += ["chemical-science-pack", "production-science-pack"]
                self.assertEqual(set(["worker-robots-storage-3", "worker-robots-storage-4"] + expected_gates),
                    set(scaffold.plain_lua(row.prerequisites)))
                self.assertEqual(inputs["worker-robots-storage-4"], scaffold.plain_lua(
                    lua.globals().data.raw.technology["worker-robots-storage-4"]))

    def test_inherited_science_gates_follow_final_lab_selection_and_direct_replacement(self):
        lua = self.stage(finite_chain(), extra_mods={"space-age": "2.1.24"})
        lua.execute('''
          local inputs={}
          for _,name in ipairs(data.raw.lab.fixture.inputs)do
            if name~="electromagnetic-science-pack"then inputs[#inputs+1]=name end
          end
          data.raw.lab.fixture.inputs=inputs
        ''')
        self.pipeline(lua)
        row = lua.globals().data.raw.technology["worker-robots-storage-5"]
        self.assertEqual(SCIENCE, scaffold.plain_lua(row.unit.ingredients))
        self.assertEqual(["worker-robots-storage-3", "worker-robots-storage-4"] + SCIENCE_GATES,
            scaffold.plain_lua(row.prerequisites))

        lua = self.stage(finite_chain(), changes={"mir-debug-generation-report": True})
        lua.execute('''
          data.raw.recipe["utility-science-pack"]=nil
          data.raw.technology["utility-science-pack"].enabled=false
          data.raw.item["iron-plate"]={type="item",name="iron-plate"}
          data.raw.recipe["fixture-utility-recipe"]={type="recipe",name="fixture-utility-recipe",
            enabled=false,ingredients={{"iron-plate",1}},
            results={{type="item",name="utility-science-pack",amount=1}}}
          data.raw.technology["fixture-utility-owner"]={type="technology",name="fixture-utility-owner",
            research_trigger={type="craft-item",item="iron-plate",count=1},
            effects={{type="unlock-recipe",recipe="fixture-utility-recipe"}}}
          lines={};log=function(line)lines[#lines+1]=line end
        ''')
        self.pipeline(lua)
        row = lua.globals().data.raw.technology["worker-robots-storage-5"]
        self.assertEqual(SCIENCE, scaffold.plain_lua(row.unit.ingredients))
        self.assertEqual(["worker-robots-storage-3", "worker-robots-storage-4",
            "automation-science-pack", "logistic-science-pack", "fixture-utility-owner"],
            scaffold.plain_lua(row.prerequisites))
        diagnostic = next(line for line in scaffold.plain_lua(lua.globals().lines)
            if "worker-robots-storage-5:" in line)
        self.assertIn("fixture-utility-owner", diagnostic)
        self.assertFalse(lua.globals().data.raw.technology["utility-science-pack"].enabled)

    def test_ranged_finite_tail_continues_after_its_real_last_level(self):
        inputs = finite_chain(5)
        inputs["worker-robots-storage-5"]["max_level"] = 9
        lua = self.stage(inputs, changes={"mir-cost-base-worker-robots-storage": 0,
            "mir-cost-growth-worker-robots-storage": 0, "mir-research-time-worker-robots-storage": 0})
        self.pipeline(lua)
        row = lua.globals().data.raw.technology["worker-robots-storage-10"]
        self.assertIsNone(lua.globals().data.raw.technology["worker-robots-storage-6"])
        self.assertEqual(10, row.level)
        self.assertEqual(["worker-robots-storage-4", "worker-robots-storage-5"] + SCIENCE_GATES,
            scaffold.plain_lua(row.prerequisites))
        self.assertEqual("2000", row.unit.count_formula)
        self.assertEqual(37, row.unit.time)
        for name, expected in inputs.items():
            self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))

    def test_foreign_infinite_after_finite_stages_is_retained_without_duplicate_bonus(self):
        inputs = finite_chain(6)
        inputs["worker-robots-storage-6"]["max_level"] = "infinite"
        lua = self.stage(inputs)
        self.pipeline(lua)
        for name, expected in inputs.items():
            self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))
        self.assertIsNone(lua.globals().data.raw.technology["worker-robots-storage-7"])
        self.assertFalse(any(row["name"].startswith("worker-robots-storage-")
            for row in scaffold.plain_lua(lua.globals().data.emitted)))

    def test_normal_default_four_and_direct_foreign_infinite_keep_existing_behavior(self):
        lua = self.stage()
        self.pipeline(lua)
        self.assertEqual("infinite", lua.globals().data.raw.technology["worker-robots-storage-4"].max_level)
        self.assertIsNone(lua.globals().data.raw.technology["worker-robots-storage-5"])
        inputs = finite_chain()
        inputs["worker-robots-storage-4"]["max_level"] = "infinite"
        lua = self.stage(inputs)
        self.pipeline(lua)
        self.assertEqual(inputs["worker-robots-storage-4"], scaffold.plain_lua(
            lua.globals().data.raw.technology["worker-robots-storage-4"]))

    def test_malformed_finite_inputs_refuse_before_publication_or_foreign_mutation(self):
        cases = []
        for field, value in (("prerequisites", []), ("effects", []), ("max_level", 3), ("level", 8)):
            rows = finite_chain()
            rows["worker-robots-storage-4"][field] = value
            cases.append(rows)
        for field, value in (("count", 0), ("time", 0), ("ingredients", [["automation-science-pack", 0]])):
            rows = finite_chain()
            rows["worker-robots-storage-4"]["unit"][field] = value
            cases.append(rows)
        rows = finite_chain(5)
        rows["worker-robots-storage-5"]["prerequisites"] = ["worker-robots-storage-3"]
        cases.append(rows)
        rows = finite_chain(5)
        rows["worker-robots-storage-5"]["effects"] = [{"type": "laboratory-speed", "modifier": 2}]
        cases.append(rows)
        for inputs in cases:
            lua = self.stage(inputs)
            with self.assertRaises(LuaError):
                self.pipeline(lua)
            self.assertEqual(0, lua.globals().data.writes)
            for name, expected in inputs.items():
                self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))

    def test_science_effect_and_cost_settings_inherit_without_aliasing(self):
        inputs = finite_chain(5)
        inputs["worker-robots-storage-5"]["effects"].append({"type": "laboratory-speed", "modifier": .2})
        for enabled in (False, True):
            lua = self.stage(inputs, changes={"mir-enable-worker-robots-storage": enabled,
                "mir-cost-base-worker-robots-storage": 0, "mir-cost-growth-worker-robots-storage": 0,
                "mir-research-time-worker-robots-storage": 0, "mir-effect-per-level-worker-robots-storage": 3})
            self.pipeline(lua)
            row = lua.globals().data.raw.technology["worker-robots-storage-6"]
            # Original4.7.3 descriptor_from_effects rejects mixed units, so
            # the full original vector is preserved even at nondefault3.
            self.assertEqual(2, row.effects[1].modifier)
            self.assertEqual(.2, row.effects[2].modifier)
            self.assertEqual(2, len(row.effects))
            self.assertEqual("4000*2^(L-6)", row.unit.count_formula)
            self.assertEqual(37, row.unit.time)
            self.assertEqual(enabled, row.enabled is not False)
            row.effects[1].modifier = 99
            row.unit.ingredients[1][2] = 99
            for name, expected in inputs.items():
                self.assertEqual(expected, scaffold.plain_lua(lua.globals().data.raw.technology[name]))

    def test_native_unit_effect_vector_scales_like_published_worker_setting(self):
        inputs = finite_chain()
        inputs["worker-robots-storage-4"]["effects"].append({"type": "character-inventory-slots-bonus", "modifier": 3})
        for value in (1, 3):
            lua = self.stage(inputs, changes={"mir-effect-per-level-worker-robots-storage": value})
            self.pipeline(lua)
            row = lua.globals().data.raw.technology["worker-robots-storage-5"]
            self.assertEqual([{"type": "worker-robot-storage", "modifier": 2 * value},
                {"type": "character-inventory-slots-bonus", "modifier": 3 * value}], scaffold.plain_lua(row.effects))
            self.assertFalse(lua.globals().data.raw["mod-data"][TRANSPORT].data.worker_storage.legacy_compatible)

    def test_finite_formula_range_uses_engine_evaluator_at_last_two_levels(self):
        inputs = finite_chain()
        row = inputs["worker-robots-storage-4"]
        row["max_level"] = 6
        del row["unit"]["count"]
        row["unit"]["count_formula"] = "1000*2^(L-4)"
        lua = self.stage(inputs, changes={"mir-cost-base-worker-robots-storage": 0,
            "mir-cost-growth-worker-robots-storage": 0})
        # A fixed host substitute for the official engine expression API;
        # this verifies call semantics, not native formula acceptance.
        lua.execute('''
          evaluator_levels={}
          helpers={evaluate_expression=function(expression,variables)
            assert(expression=="1000*2^(L-4)" and variables.l==variables.L)
            evaluator_levels[#evaluator_levels+1]=variables.L
            return 1000*2^(variables.L-4)
          end}
        ''')
        self.pipeline(lua)
        row = lua.globals().data.raw.technology["worker-robots-storage-7"]
        self.assertEqual("8000*2^(L-7)", row.unit.count_formula)
        self.assertEqual([6, 5], scaffold.plain_lua(lua.globals().evaluator_levels))
        self.assertEqual(inputs["worker-robots-storage-4"], scaffold.plain_lua(
            lua.globals().data.raw.technology["worker-robots-storage-4"]))

    def test_runtime_identity_caps_partial_work_queue_and_two_reparses_agree(self):
        for target in ("f200", "f210"):
            for foreign_owner in (False, True):
                with self.subTest(target=target, foreign_owner=foreign_owner):
                    inputs = finite_chain(5 if foreign_owner else 4)
                    if foreign_owner:
                        inputs["worker-robots-storage-5"]["max_level"] = "infinite"
                    lua = self.stage(inputs, target)
                    self.pipeline(lua)
                    self.runtime(lua)
                    lua.globals().foreign_owner = foreign_owner
                    lua.execute('''
                      local selected="worker-robots-storage-5"
                      local catalogue=parse_worker_catalogue()
                      local route=catalogue.worker_storage_route()
                      assert(route.technology==selected and route.level==5 and route.owned==not foreign_owner)
                      assert(route.legacy_compatible==not foreign_owner)
                      assert(#route.finite==1 and route.finite[1].name=="worker-robots-storage-4"
                        and route.finite[1].max_level==4 and route.finite[1].provider=="unnamed-planet-provider")
                      assert((route.provider~=nil)==foreign_owner)
                      route.technology="caller-change";route.finite[1].provider="caller-change"
                      assert(catalogue.worker_storage_route().technology==selected
                        and catalogue.worker_storage_route().finite[1].provider=="unnamed-planet-provider")
                      local row
                      for _,entry in ipairs(catalogue.declared())do
                        if entry.family=="worker-robots-storage"then assert(row==nil);row=entry end
                      end
                      assert((row~=nil)==not foreign_owner)
                      if row then assert(row.id==selected and row.progression==5
                        and row.cap_setting=="mir-max-level-worker-robots-storage")end
                      assert(catalogue.externally_supplied_continuation("worker-robots-storage-4")==foreign_owner)
                      assert(history_reads["worker-robots-storage-4"]==1 and history_reads[selected]==1)
                      local finite={name="worker-robots-storage-4",valid=true,level=4,researched=true,
                        enabled=false,visible_when_disabled=false,saved_progress=.11,
                        prototype=native_prototypes["worker-robots-storage-4"]}
                      local infinite={name=selected,valid=true,level=8,researched=false,
                        enabled=true,visible_when_disabled=false,saved_progress=.27,prototype=native_prototypes[selected]}
                      local current={name="foreign-current",valid=true,level=2,enabled=true}
                      local world={index=1,valid=true,technologies={[finite.name]=finite,[selected]=infinite,
                        [current.name]=current},research_queue={current,infinite},current_research=current,research_progress=.42}
                      finite.force,infinite.force,current.force=world,world,world
                      game,storage={forces={[1]=world}},{}
                      settings.startup["mir-max-level-worker-robots-storage"].value=6
                      local lifecycle=require("runtime.lifecycle")
                      local limits=lifecycle.cap_limits(world)
                      assert(limits[finite.name]==nil and (limits[selected]~=nil)==not foreign_owner)
                      lifecycle.on_init()
                      assert(infinite.enabled==foreign_owner and infinite.level==8 and infinite.saved_progress==.27)
                      assert(#world.research_queue==(foreign_owner and 2 or 1))
                      assert(world.current_research==current and world.research_progress==.42)
                      for reload=1,2 do
                        catalogue=parse_worker_catalogue()
                        require("runtime.lifecycle").on_load()
                        assert(catalogue.worker_storage_route().technology==selected)
                        assert(infinite.level==8 and infinite.saved_progress==.27)
                        assert(finite.level==4 and finite.researched and not finite.enabled and finite.saved_progress==.11)
                        assert(world.current_research==current and world.research_progress==.42)
                      end
                      settings.startup["mir-max-level-worker-robots-storage"].value=0
                      parse_worker_catalogue();require("runtime.lifecycle").on_configuration_changed({})
                      assert(infinite.enabled and infinite.level==8 and infinite.saved_progress==.27)
                      assert(finite.level==4 and finite.researched and not finite.enabled and finite.saved_progress==.11)
                    ''')

    def test_transport_and_final_creation_custody_reject_malformed_inputs(self):
        for mode in ("wrong-id", "wrong-endpoint", "extra-field", "foreign-created-tail", "mir-created-finite",
                     "missing-tail", "missing-finite", "finite-tail", "unknown-creator"):
            with self.subTest(mode=mode):
                lua = self.stage(finite_chain())
                self.pipeline(lua)
                self.runtime(lua)
                lua.globals().mode = mode
                lua.execute('''
                  local value=prototypes.mod_data["more-infinite-research-native-adoptions"].data.worker_storage
                  if mode=="wrong-id"then value.technology="worker-robots-storage-8"
                  elseif mode=="wrong-endpoint"then value.finite[1].max_level=7
                  elseif mode=="extra-field"then value.finite[1].provider="invented"
                  elseif mode=="foreign-created-tail"then foreign_rows["worker-robots-storage-5"]={}
                  elseif mode=="mir-created-finite"then foreign_rows["worker-robots-storage-4"]=nil
                  elseif mode=="missing-tail"then native_prototypes["worker-robots-storage-5"]=nil
                  elseif mode=="missing-finite"then native_prototypes["worker-robots-storage-4"]=nil
                  elseif mode=="finite-tail"then native_prototypes["worker-robots-storage-5"].max_level=5
                  else prototypes.get_history=function()return {changed={"foreign"}}end end
                  storage=setmetatable({}, {__newindex=function()error("state mutation before admission")end})
                ''')
                with self.assertRaises(LuaError):
                    lua.execute("parse_worker_catalogue()")
                self.assertIs(True, lua.eval("next(storage)==nil"))

    def test_duplicate_diagnostics_distinguish_mir_emission_from_existing_owner(self):
        lua = self.stage()
        lua.execute('''
          local generator=require("research.generator")
          local row={type="technology",name="worker-robots-storage-4"}
          local writes=0
          local stage={raw={technology={}},extend=function()writes=writes+1 end}
          local ok,message=pcall(generator.install,{row,row},stage)
          assert(not ok and message:find("within MIR emission",1,true) and writes==0)
          stage.raw.technology[row.name]={max_level=9}
          ok,message=pcall(generator.install,{row},stage)
          assert(not ok and message:find("already exists in data.raw.technology (max_level=9)",1,true) and writes==0)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime, LuaError
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerStorageContinuationTests))
    sys.exit(0 if result.wasSuccessful() else 1)

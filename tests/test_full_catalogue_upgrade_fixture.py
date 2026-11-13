import argparse
import copy
import json
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/full-catalogue-upgrade"
SUCCESSOR_ROLE = "successor"
PROFILES = ROOT / "tests/profiles"
ORACLE = ROOT / "spec/inventory/modern-f200-470.json"
SHARED = FIXTURE / "shared"
GEAR_SCIENCE = [[name, 1] for name in ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack")]
F200_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F200_RUNTIME_API"),
    "D:/Games/Factorio/2.0/doc-html/runtime-api.json",
    "D:/Programs/Factorio/2.0/doc-html/runtime-api.json",
)
OWNERS = {"low-density-structure-productivity", "plastic-bar-productivity", "processing-unit-productivity", "rocket-fuel-productivity", "steel-plate-productivity"}
DESCRIPTORS = (("research_copper", "recipe-prod-research_copper-1", "copper-plate"), ("research_iron", "recipe-prod-research_iron-1", "iron-plate"), ("research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"), ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"), ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"), ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"), ("research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"), ("research_grenades", "recipe-prod-research_grenades-1", "grenade"), ("research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"), ("research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"), ("research_concrete", "recipe-prod-research_concrete-1", "stone-brick"), ("research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"))


def fixture_role(stage):
    return SUCCESSOR_ROLE if stage == "mir5" else stage


def f200_runtime_api_path():
    for candidate in F200_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


def py(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys): return [py(value[key]) for key in range(1, max(keys)+1)]
        return {key: py(value[key]) for key in keys}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        out = runtime.table()
        for key, item in value.items(): out[key] = lua(runtime, item)
        return out
    if isinstance(value, list):
        out = runtime.table()
        for index, item in enumerate(value, 1): out[index] = lua(runtime, item)
        return out
    return value


class FullCatalogueUpgradeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.oracle = {p["id"]: p for p in json.loads(ORACLE.read_text(encoding="utf-8"))["profiles"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("function load_plan(path) return assert(loadfile(path))() end")
        self.plan = py(self.lua.eval("load_plan")((FIXTURE / "published-4.7/catalogue.lua").as_posix()))

    def expected(self, name):
        facts = self.oracle[name]["technology_owner_progression_facts"]
        return ({f["name"] for f in facts}, {f["name"] for f in facts if f["group"] != "scripted-runtime-carriers"}, {f["name"] for f in facts if f["group"] == "scripted-runtime-carriers"}, {e["recipe"] for f in facts for e in f["effects"] if e["type"] == "change-recipe-productivity"}, {e["ammo_category"] for f in facts for e in f["effects"] if e["type"] == "gun-speed"})

    def worker_owner_controller(self, mode="published473-idle-full4"):
        runtime=LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().control_path=(SHARED/"control.lua").as_posix()
        runtime.globals().owner_mode=mode
        runtime.globals().frozen_plan=lua(runtime,self.plan)
        runtime.execute('''
          local function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end;return o end
          C,T,H,P="worker-robots-storage-4","mir-worker-storage-default-4","mir-worker-storage-head-4","mir-worker-storage-preservation-4"
          GEAR,PROBE="recipe-prod-research_gears-1","braking-force-1"
          local modern=owner_mode~=false
          local plan=modern and copy(frozen_plan.base)or{state={{name=C},{name=GEAR}},public={},native_owners={},scripted={},credits={},recipes={"iron-gear-wheel"},guns={"cannon-shell"}}
          PLAN={worker_native_owner=modern and owner_mode or nil,target={id="f200",version="2.0.77",
            published_mir=modern and"4.7.20003"or"4.7.20002",mir5=modern and"5.0.20012"or"5.0.20000",
            space_age_closure={"space-age","quality","elevated-rails"}},force_fields=modern and copy(frozen_plan.force_fields)or{"worker_robots_storage_bonus","manual_mining_speed_modifier"},base=plan}
          callbacks,markers={},{}
          script={active_mods={base="2.0.77",["more-infinite-research"]=PLAN.target.mir5,
            ["mir-fixture-mir5-full-catalogue-upgrade"]=modern and"0.4.0"or"0.2.0"},
            on_configuration_changed=function(f)callbacks.config=f end,on_init=function(f)callbacks.init=f end,
            on_load=function(f)callbacks.load=f end,on_event=function(id,f)callbacks[id]=f end}
          defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}
          helpers={table_to_json=function(v)markers[#markers+1]=copy(v);return"{}"end};log=function()end
          game={tick=100,speed=16,forces={},saves={},difficulty_settings={technology_price_multiplier=1}}
          function game.server_save(name)game.saves[#game.saves+1]=name end
          local function force(name,index)
            local f={name=name,index=index,valid=true,technologies={},recipes={["iron-gear-wheel"]={valid=true,productivity_bonus=.2}},
              worker_robots_storage_bonus=1,manual_mining_speed_modifier=0,research_progress=0,research_queue={},
              get_gun_speed_modifier=function()return 0 end}
            for i,id in ipairs{C,T,H,P,GEAR,PROBE}do
              local worker=i<=4;local debit=i==3;local hidden=i==3 or i==4
              local science={};for _,pack in ipairs(debit and{"automation-science-pack"}or{"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"})do science[#science+1]={name=pack,amount=1}end
              f.technologies[id]={name=id,valid=true,force=f,level=i<=3 and 5 or worker and 4 or id==GEAR and 3 or 1,
                researched=false,enabled=modern and i==2 or not modern and i<=2 or not worker,
                visible_when_disabled=modern and i==1 or false,saved_progress=0,
                research_unit_count=debit and 1 or i<=2 and 1012 or 675,research_unit_ingredients=science,
                prototype={level=worker and 4 or 1,max_level=4294967295,hidden=hidden,enabled=not hidden,
                  visible_when_disabled=false,ignore_tech_cost_multiplier=false,prerequisites={},
                  research_unit_count_formula=not debit and"675*1.5^(L-4)"or nil,research_unit_energy=debit and 60 or 3600,
                  effects=worker and{{type="worker-robot-storage",modifier=debit and -1 or 1}}or{}}}
            end
            for _,row in ipairs(plan.state)do if not f.technologies[row.name]then
              f.technologies[row.name]={name=row.name,valid=true,force=f,level=2,researched=false,enabled=true,
                visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295,level=1}}
            end end
            for _,name in ipairs(plan.recipes)do if not f.recipes[name]then f.recipes[name]={valid=true,productivity_bonus=.1}end end
            for _,name in ipairs(PLAN.force_fields)do if f[name]==nil then f[name]=0 end end
            for _,name in ipairs(plan.credits)do f.technologies[name]={name=name,valid=true,level=1,researched=false,
              enabled=false,visible_when_disabled=false,prototype={hidden=true,max_level=4294967295}}end
            return f
          end
          player=force("player",1);paused=force("mir5-full-catalogue-upgrade-paused",2);game.forces.player=player;game.forces[2]=paused
          game.forces[paused.name]=paused
          player.current_research=player.technologies[GEAR];player.research_queue={player.technologies[GEAR],player.technologies[PROBE]};player.research_progress=modern and .42/32000 or .42
          paused.technologies[GEAR].saved_progress=modern and .27/16000 or .27
          local function old_snapshot(f)
            local out={technologies={},recipes={},fields={},guns={}}
            for _,row in ipairs(plan.state)do local id=row.name;local t=f.technologies[id]
              out.technologies[id]={level=t.level,researched=false,enabled=true,visible=false,saved=t.saved_progress,maximum=4294967295}
            end
            for _,name in ipairs(plan.recipes)do out.recipes[name]=f.recipes[name].productivity_bonus end
            for _,name in ipairs(PLAN.force_fields)do out.fields[name]=f[name]end
            for _,name in ipairs(plan.guns)do out.guns[name]=0 end
            return out
          end
          local inventory={counts={}}
          function inventory.clear()inventory.counts={}end
          function inventory.insert(row)inventory.counts[row.name]=(inventory.counts[row.name]or 0)+row.count;return row.count end
          function inventory.get_item_count(name)return inventory.counts[name]or 0 end
          local entity={valid=true,energy=0,get_inventory=function()return inventory end}
          storage={mir5_full_catalogue_upgrade={phase="completed",plan="base",source_labs=1,successor_labs=0,
            paused_index=2,lab=entity,source_snapshot=old_snapshot(player),paused_snapshot=old_snapshot(paused),
            player_queue={current=GEAR,queue={GEAR,PROBE},progress=.42}}}
          if modern then
            PLAN.worker_native_owner_source={origin={kind="external_literal_expectations",
              commit="67b271d2c0a1da53f9c0fe9bbf82689fb2e37916",member="source473-r02/published-state.json",
              sha256="72B02BA2A2BDD0D974A6E3C2E9124FAE24CCD21233295D128F44EECFA608B428",
              source_save_sha256="1F7DD178D9CAA6CDD47F82C3B55F19D846D70E36A995F70E858E36A0918A98AF"},
              frames={player=old_snapshot(player),[paused.name]=old_snapshot(paused)},
              queues={player={current=GEAR,queue={GEAR,PROBE},progress=player.research_progress},
                [paused.name]={current=false,queue={},progress=0}}}
            storage={}
          end
          local original_require=require
          require=function(name)if name=="__mir-fixture-mir5-full-catalogue-upgrade__/catalogue"then return PLAN end;return original_require(name)end
          dofile(control_path)
          event={mod_startup_settings_changed=false,mod_changes={
            ["more-infinite-research"]={old_version="4.7.20003",new_version="5.0.20012"},
            ["mir-fixture-mir5-full-catalogue-upgrade"]={new_version="0.4.0"}}}
          function configure()if modern then callbacks.init()end;callbacks.config(event)end
          function ordinary_gear()
            local gear=player.technologies[GEAR];gear.level=gear.level+1
            player.recipes["iron-gear-wheel"].productivity_bonus=.3
            callbacks[2]({research=gear,by_script=false});game.tick=101;callbacks[1]()
          end
        ''')
        return runtime

    def test_current_paid_idle_worker_projection_and_two_colds_are_strict(self):
        runtime=self.worker_owner_controller();runtime.execute('''
          configure();assert(#game.saves==0 and storage.mir5_full_catalogue_upgrade.phase=="known473-observed")
          callbacks[1]()
          assert(#game.saves==1 and #markers==1 and markers[1].worker_native_owner=="published473-idle-full4")
          assert(markers[1].worker_frames.player.rows[T].level==5 and markers[1].worker_frames.player.rows[H].level==5
            and markers[1].worker_frames.player.rows[H].researched==false)
          assert(markers[1].source_snapshot_origin.kind=="external_literal_expectations")
          assert(markers[1].witnesses.successor_gear_lab==0 and markers[1].witnesses.source_gear_lab==1)
          for _=1,2 do local oldgame=game;game=nil;callbacks.load();game=oldgame;callbacks[1]()end
          assert(#markers==3 and #game.saves==1 and player.worker_robots_storage_bonus==1)
          assert(storage.mir5_full_catalogue_upgrade.source_snapshot.technologies[C].enabled)
        ''')

    def test_current_worker_missing_state_wrong_flags_paid_work_and_unrelated_drift_refuse(self):
        changes=('player.technologies[T]=nil','player.technologies[H]=nil',
                 'player.technologies[T].level=6','player.technologies[T].saved_progress=.01',
                 'player.technologies[C].enabled=true','player.technologies[C].visible_when_disabled=false',
                 'player.technologies[T].enabled=false','player.technologies[T].visible_when_disabled=true',
                 'player.technologies[H].researched=true','player.technologies[H].level=4','player.technologies[H].level=6',
                 'player.technologies[H].prototype.max_level=4','player.technologies[H].prototype.research_unit_count_formula="1"',
                 'player.technologies[H].prototype.effects[1].modifier=0',
                 'player.technologies[H].prototype.effects[1].modifier=-2','player.technologies[P].level=5',
                 'player.technologies[T].research_unit_count=1013','player.research_progress=player.research_progress+1e-14',
                 'paused.technologies[GEAR].saved_progress=paused.technologies[GEAR].saved_progress+1e-14',
                 'player.worker_robots_storage_bonus=2','paused.worker_robots_storage_bonus=0',
                 'player.research_queue[2]=player.technologies[T]','player.manual_mining_speed_modifier=.1',
                 'PLAN.worker_native_owner_source.frames.player.technologies[C].enabled=false')
        for change in changes:
            with self.subTest(change=change):
                runtime=self.worker_owner_controller();runtime.execute(change+'''
                  local ok=pcall(configure);assert(not ok and #game.saves==0 and #markers==0)
                ''')
        for change in ('player.technologies[T].enabled=false','player.technologies[H].prototype.effects[1].modifier=0',
                       'paused.technologies[C].visible_when_disabled=false'):
            runtime=self.worker_owner_controller();runtime.execute('configure();callbacks[1]();'+change+'''
              callbacks.load();local ok=pcall(callbacks[1]);assert(not ok and #game.saves==1 and #markers==1)
            ''')

    def test_legacy_worker_flags_are_not_relaxed_and_mode_is_exact(self):
        runtime=self.worker_owner_controller(False);runtime.execute('''
          callbacks.config(event);ordinary_gear();assert(#game.saves==1 and markers[1].worker_native_owner==nil)
        ''')
        runtime=self.worker_owner_controller(False);runtime.execute('''
          player.technologies[C].enabled=false
          assert(not pcall(callbacks.config,event)and #game.saves==0)
        ''')
        for mode in ("unknown", "published473-idle-full5"):
            runtime=self.worker_owner_controller(mode);runtime.execute('assert(not pcall(configure)and #game.saves==0)')
        for change in ('event.mod_startup_settings_changed=true',
                       'event.mod_changes["more-infinite-research"].old_version="5.0.20001"',
                       'event.mod_changes["mir-fixture-mir5-full-catalogue-upgrade"].old_version="0.1.0"',
                       'event.mod_changes.removed={old_version="1.0"}'):
            runtime=self.worker_owner_controller();runtime.execute(change+';assert(not pcall(configure)and #game.saves==0)')

    def test_literal_473_source_metadata_missing_fabricated_partial_or_altered_is_rejected(self):
        changes=('PLAN.worker_native_owner_source=nil','PLAN.worker_native_owner_source.origin.kind="saved-fixture-state"',
                 'PLAN.worker_native_owner_source.origin.sha256="invented"',
                 'PLAN.worker_native_owner_source.origin.source_save_sha256="9D391DB311DA3C82E43648FAE5E6FE9C08D00F0592880B3160F35EE822FECA09"',
                 'PLAN.worker_native_owner_source.frames.player.technologies[C]=nil',
                 'PLAN.worker_native_owner_source.frames.player.recipes["iron-gear-wheel"]=nil',
                 'PLAN.worker_native_owner_source.queues.player.progress=-1')
        for change in changes:
            with self.subTest(change=change):
                runtime=self.worker_owner_controller();runtime.execute(change+';assert(not pcall(configure)and #game.saves==0)')
        runtime=self.worker_owner_controller();runtime.execute('''
          player.manual_mining_speed_modifier=.5
          callbacks.init()
          assert(storage.mir5_full_catalogue_upgrade.incoming_candidate_observation.player.fields.manual_mining_speed_modifier==.5)
          player.manual_mining_speed_modifier=0
          callbacks.config(event);callbacks[1]()
          assert(#game.saves==1 and markers[1].incoming_candidate_observation.player.fields.manual_mining_speed_modifier==.5)
          callbacks.load();storage.mir5_full_catalogue_upgrade.source_snapshot_origin.kind="invented"
          assert(not pcall(callbacks[1])and #game.saves==1)
        ''')

    def test_exact_oracle_identity_effect_and_credit_closure(self):
        for key, oracle_name, owners in (("base", "base-f200", set()), ("space_age", "space-age-f200", OWNERS)):
            public, state, scripted, recipes, guns = self.expected(oracle_name)
            plan = self.plan[key]
            with self.subTest(key=key):
                self.assertEqual(public, {row["name"] for row in plan["public"]})
                self.assertEqual(state, {row["name"] for row in plan["state"]})
                self.assertEqual(scripted, set(plan["scripted"]))
                self.assertEqual(recipes, set(plan["recipes"]))
                self.assertEqual(guns, set(plan["guns"]))
                self.assertEqual(owners, set(plan["native_owners"]))
                credits = {f"mir-native-credit-{family}-{recipe}-{direction}" for family, main, recipe in DESCRIPTORS if main in public for direction in ("positive", "negative")}
                self.assertEqual(credits, set(plan["credits"]))
        self.assertEqual((54, 69, 20, 24), (len(self.plan["base"]["public"]), len(self.plan["space_age"]["public"]), len(self.plan["base"]["credits"]), len(self.plan["space_age"]["credits"])))
        self.assertEqual({"recipe-prod-research_agricultural_growth_speed-1", "recipe-prod-research_spoilage_preservation-1"}, set(self.plan["space_age"]["scripted"]))

    def test_stage_data_guard_accelerates_exact_gear_only(self):
        for profile in ("base-f200", "space-age-f200"):
            gear = next(row for row in self.oracle[profile]["technology_owner_progression_facts"] if row["name"] == "recipe-prod-research_gears-1")
            self.assertEqual(GEAR_SCIENCE, gear["science"])
        self.lua.execute("""
          function run_data(path, common, catalogue, raw, mods)
            local env = {data={raw=raw}, mods=mods}
            env.require = function(name)
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_data_final" then
                return assert(loadfile(common, "t", env))()
              end
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue, "t", env))()
              end
              error("unexpected fixture module: " .. tostring(name))
            end
            setmetatable(env, {__index=_G})
            local ok, message = pcall(function() assert(loadfile(path, "t", env))() end)
            return {ok=ok, message=tostring(message), raw=raw}
          end
        """)
        for stage, mir in (("published-4.7", "4.7.20002"), ("mir5", "5.0.20000")):
            for space in (False, True):
                effects = [{"type":"change-recipe-productivity", "recipe":"iron-gear-wheel", "change":.1}]
                if space: effects.insert(0, {"type":"change-recipe-productivity", "recipe":"casting-iron-gear-wheel", "change":.1})
                gear = {"max_level":"infinite", "unit":{"count_formula":"8000*2^(L-1)", "time":60, "ingredients":GEAR_SCIENCE}, "effects":effects}
                raw = {"technology":{"recipe-prod-research_gears-1":gear}, "unchanged":{"value":17}}
                mods = {"base":"2.0.77", "more-infinite-research":mir,
                        "mir-fixture-mir5-full-catalogue-upgrade":"0.1.0" if stage == "published-4.7" else "0.2.0"}
                if space: mods.update({"space-age":"2.0.77", "elevated-rails":"2.0.77", "quality":"2.0.77"})
                with self.subTest(stage=stage, space=space):
                    result = self.lua.eval("run_data")((FIXTURE / fixture_role(stage) / "data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (FIXTURE / fixture_role(stage) / "catalogue.lua").as_posix(), lua(self.lua, raw), lua(self.lua, mods))
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]
                    self.assertEqual((None, "1", 1), (actual.get("count"), actual["count_formula"], actual["time"]))
                    self.assertEqual(17, py(result["raw"])["unchanged"]["value"])
                    self.assertEqual(GEAR_SCIENCE, actual["ingredients"])
                wrong_amount = copy.deepcopy(GEAR_SCIENCE)
                wrong_amount[0][1] = 2
                wrong_name = copy.deepcopy(GEAR_SCIENCE)
                wrong_name[0][0] = "foreign-science-pack"
                duplicate = copy.deepcopy(GEAR_SCIENCE)
                duplicate[1] = duplicate[0][:]
                for ingredients in (None, [], GEAR_SCIENCE[:-1], wrong_amount, wrong_name, duplicate):
                    altered = copy.deepcopy(gear)
                    altered["unit"]["ingredients"] = ingredients
                    with self.subTest(stage=stage, space=space, ingredients=ingredients):
                        raw_input = lua(self.lua, {"technology": {"recipe-prod-research_gears-1": altered}})
                        before = py(raw_input)
                        result = self.lua.eval("run_data")((FIXTURE / fixture_role(stage) / "data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (FIXTURE / fixture_role(stage) / "catalogue.lua").as_posix(), raw_input, lua(self.lua, mods))
                        self.assertFalse(result["ok"])
                        self.assertIn("gear science", str(result["message"]))
                        self.assertEqual(before, py(result["raw"]))
        gear = {"max_level":"infinite", "unit":{"count_formula":"8000*2^(L-1)", "time":61}, "effects":[{"type":"change-recipe-productivity", "recipe":"iron-gear-wheel", "change":.1}]}
        result = self.lua.eval("run_data")((FIXTURE / "successor/data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (FIXTURE / "successor/catalogue.lua").as_posix(), lua(self.lua, {"technology":{"recipe-prod-research_gears-1":gear}}), lua(self.lua, {"base":"2.0.77", "more-infinite-research":"5.0.20000", "mir-fixture-mir5-full-catalogue-upgrade":"0.2.0"}))
        self.assertFalse(result["ok"]); self.assertIn("workload differs", str(result["message"])); self.assertEqual(61, gear["unit"]["time"])

    def test_controls_register_without_game_or_storage_reads(self):
        for stage in ("published-4.7", "mir5"):
            with self.subTest(stage=stage):
                self.lua.globals().control_path = (FIXTURE / fixture_role(stage) / "control.lua").as_posix()
                self.lua.globals().catalogue_path = (FIXTURE / fixture_role(stage) / "catalogue.lua").as_posix()
                self.lua.globals().common_control_path = (SHARED / "control.lua").as_posix()
                self.lua.globals().source_stage = stage == "published-4.7"
                self.lua.execute("""
                  function parse_full_catalogue_control()
                    local callbacks, forbidden = {events={}}, {}
                    local env = {
                      script={on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                        on_configuration_changed=function(fn) callbacks.configuration=fn end,
                        on_event=function(event, fn) callbacks.events[event]=fn end,
                        active_mods={base="2.0.77", ["more-infinite-research"]=source_stage and "4.7.20002" or "5.0.20000",
                          ["mir-fixture-mir5-full-catalogue-upgrade"]=source_stage and "0.1.0" or "0.2.0"}},
                      defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
                    }
                    env.require=function(name)
                        if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_control" then
                          return assert(loadfile(common_control_path, "t", env))()
                        end
                        assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue")
                        return assert(loadfile(catalogue_path, "t", env))()
                      end
                    env._G=env
                    setmetatable(env,{__index=function(_,key)
                      if key == "game" or key == "storage" then forbidden[key]=true; return nil end
                      return _G[key]
                    end})
                    local ok,message=pcall(function() assert(loadfile(control_path, "t", env))() end)
                    return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
                  end
                """)
                result = self.lua.eval("parse_full_catalogue_control")()
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                if stage == "published-4.7": self.assertIsNotNone(result["callbacks"]["init"])
                else: self.assertIsNotNone(result["callbacks"]["configuration"])

    def test_f200_force_field_schema_when_local_api_is_available(self):
        runtime_api = f200_runtime_api_path()
        if runtime_api is None:
            self.skipTest("F200 runtime API documentation is not installed")
        document = json.loads(runtime_api.read_text(encoding="utf-8"))
        self.assertEqual(document["application_version"], "2.0.77")
        lua_force = next(row for row in document["classes"] if row["name"] == "LuaForce")
        fields = {row["name"] for row in lua_force["attributes"]}
        fixture_fields = set(self.plan["force_fields"])
        self.assertIn("character_trash_slot_count", fixture_fields)
        self.assertNotIn("character_logistic_trash_slots", fixture_fields)
        self.assertNotIn("research_queue_enabled", fields)
        self.assertTrue(fixture_fields <= fields)

    def test_profiles_controls_and_native_boundaries_are_explicit(self):
        expected_hash = {"mir-fixture-mir5-active-mods-observer_0.1.0.zip":"723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"}
        for profile in ("base", "space-age"):
            for stage, mir, fixture in (("published-4.7", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
                data = json.loads((PROFILES / f"full-catalogue-upgrade-{stage}-{profile}-f200-2077.json").read_text(encoding="utf-8"))
                mods = {row["name"]: row["version"] for row in data["mods"]}
                with self.subTest(profile=profile, stage=stage):
                    self.assertEqual(("f200", "2.0", "2.0.77"), (data["target"], data["factorio_line"], data["engine"]["version"]))
                    self.assertEqual((mir, fixture), (mods["more-infinite-research"], mods["mir-fixture-mir5-full-catalogue-upgrade"]))
                    self.assertEqual(profile == "space-age", "space-age" in mods)
                    self.assertEqual(expected_hash, data["archive_sha256"])
        self.assertEqual((FIXTURE / "published-4.7/catalogue.lua").read_bytes(), (FIXTURE / "successor/catalogue.lua").read_bytes())
        for path in FIXTURE.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("__more-infinite-research__", text)
            self.assertNotIn('require("research.', text)
            self.assertNotIn('require("compatibility.', text)
        source = (SHARED / "control.lua").read_text(encoding="utf-8")
        successor = source
        for text in (source, successor):
            self.assertIn('local SAVE = "mir5-native-complete"', text)
            self.assertIn("script.on_load(function()", text)
            self.assertNotIn("productivity_bonus =", text)
            self.assertNotIn("research_unit_count =", text)
        self.assertIn("queued_progress=.42", source); self.assertIn("paused_progress=.27", source)
        self.assertIn("assert_credits(player, plan", successor); self.assertIn("assert_successor_snapshot", successor)
        for text in (source, successor):
            self.assertNotIn("research_queue_enabled", text)
            self.assertIn("paused_snapshot", text)
            self.assertIn("assert_same_snapshot(paused, plan, state.paused_snapshot", text)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FullCatalogueUpgradeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

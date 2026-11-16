"""Synthetic controls for the one-LDS paid-price observer fixture.

This is deliberately a host-only model.  It never opens the retained F1 save,
starts Factorio, or turns its source/candidate assertions into a native result.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/native-credit-price-paid"
OLD_FIXTURE = ROOT / "tests/fixtures/native-credit-vectors"


def load_archive_contract():
    spec = importlib.util.spec_from_file_location("paid_archive_contract", FIXTURE / "archive_contract.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class NativeCreditPricePaidFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_path = FIXTURE.as_posix()
        self.lua.execute(r'''
          package.path=fixture_path.."/?.lua;"..package.path
          C=require("contract")
          package.preload["__mir-fixture-native-credit-vectors__/contract"]=function()return C end
          function clone(value)
            if type(value)~="table" then return value end
            local out={};for key,item in pairs(value)do out[key]=clone(item)end;return out
          end
        ''')

    def story(self, opponent=None, post_drift=False):
        self.lua.globals().opponent = opponent or ""
        self.lua.globals().post_drift = post_drift
        self.lua.execute(r'''
          local callbacks,logs,saves,acks={},{},{},{}
          storage={};queue_writes=0;insert_calls=0;partial_insertions=0;lab_enable_writes=0
          local f={technologies={},recipes={},research_progress=0,index=1,name="player"}
          local game={tick=0,forces={player=f},difficulty_settings={technology_price_multiplier=1},surfaces={{}}}
          local packs=C.packs
          local inv={counts={},capacity=200}
          inv.insert=function(row)
            insert_calls=insert_calls+1
            local accepted=math.min(row.count,inv.capacity-(inv.counts[row.name]or 0))
            if accepted<row.count then partial_insertions=partial_insertions+1 end
            inv.counts[row.name]=(inv.counts[row.name]or 0)+accepted
            return accepted
          end
          inv.get_item_count=function(name)return inv.counts[name]or 0 end
          for _,name in ipairs(packs)do inv.counts[name]=C.source_stock end
          local lab=setmetatable({valid=true,name=C.lab,_disabled=true},{
            __index=function(row,key)if key=="disabled_by_script" then return row._disabled end end,
            __newindex=function(row,key,value)
              if key=="disabled_by_script" then
                if value==false then lab_enable_writes=lab_enable_writes+1 end
                rawset(row,"_disabled",value)
              else rawset(row,key,value)end
            end})
          lab.get_inventory=function()return inv end
          game.surfaces[1].find_entity=function(name,position)
            assert(name==C.lab and position[1]==0 and position[2]==0);return lab
          end
          local function technology(name,holder)
            local proto={hidden=holder==true,enabled=holder~=true,visible_when_disabled=false,
              ignore_tech_cost_multiplier=holder==true,research_unit_count=holder and 1 or nil,
              research_unit_count_formula="8000*2^(L-1)",research_unit_energy=3600,effects={}}
            local row={name=name,valid=true,force=f,prototype=proto,level=1,researched=false,
              enabled=holder~=true,visible_when_disabled=false,saved_progress=0,
              research_unit_ingredients={{name=packs[1],amount=1},{name=packs[2],amount=1},
                {name=packs[3],amount=1},{name=packs[4],amount=1}}}
            setmetatable(row,{__index=function(_,key)
              if key=="research_unit_count" then
                if holder then return 1 end
                return 8000*2^(row.level-1)*game.difficulty_settings.technology_price_multiplier
              end
            end})
            f.technologies[name]=row;return row
          end
          local main=technology(C.main,false);main.level=3
          for _,name in ipairs(C.main_ids)do if not f.technologies[name] then technology(name,false)end end
          for _,name in ipairs(C.reference_ids)do technology(name,false)end
          technology(C.sentinel,false)
          for _,route in ipairs(C.routes)do
            for _,sign in ipairs({"positive","negative"})do
              local name=C.carrier_for(route.family,route.recipe,sign)
              if not f.technologies[name] then technology(name,true)end
            end
          end
          for index,name in ipairs(C.carriers)do
            local carrier=f.technologies[name]
            if index==6 then carrier.level=3 end
          end
          for _,name in ipairs(C.observed_recipes)do
            f.recipes[name]={productivity_bonus=(name=="low-density-structure" or name=="casting-low-density-structure") and .2 or 0}
          end
          local queue={}
          setmetatable(f,{__index=function(_,key)if key=="research_queue" then return queue end end,
            __newindex=function(_,key,value)
              if key=="research_queue" then queue_writes=queue_writes+1;queue=value;f.current_research=value[1]
              else rawset(f,key,value)end
            end})
          local env={storage=storage,game=game,settings={},script={active_mods={base="2.1.23",["space-age"]="2.1.23",
              quality="2.1.23",recycler="2.1.23",["elevated-rails"]="2.1.23",
              ["more-infinite-research"]="5.0.21016",[C.fixture]="0.4.0"}},defines={inventory={lab_input=1},events={on_research_finished=1,on_tick=2}},
            helpers={table_to_json=function(value)logs[#logs+1]=clone(value);return "record"end},log=function()end,
            require=require,pairs=pairs,ipairs=ipairs,next=next,type=type,math=math,error=error,commands={},rcon={}}
          env.script.on_configuration_changed=function(callback)callbacks.config=callback end
          env.script.on_load=function(callback)callbacks.load=callback end
          env.script.on_event=function(id,callback)callbacks[id==1 and "finished" or "tick"]=callback end
          env.commands.add_command=function(name,_,callback)callbacks.command=callback;callbacks.command_name=name end
          env.rcon.print=function(message)acks[#acks+1]=message end
          env.game.server_save=function(name)saves[#saves+1]={name=name,tick=game.tick}end
          assert(loadfile(fixture_path.."/control.lua","t",env))()
          last_game,last_force,last_lab=game,f,lab
          if opponent=="source-partial" then f.research_progress=.1 end
          if opponent=="source-lab-active" then lab.disabled_by_script=false;lab_enable_writes=0 end
          if opponent=="wrong-carrier" then f.technologies[C.carriers[6]].level=2 end
          if opponent=="wrong-ingredients" then main.research_unit_ingredients[4].amount=2 end
          if opponent=="wrong-cost" then main.prototype.ignore_tech_cost_multiplier=true end
          local event={mod_changes={ ["more-infinite-research"]={old_version="5.0.21015",new_version="5.0.21016"},
            [C.fixture]={old_version="0.2.0",new_version=opponent=="bad-transition" and "0.5.0" or "0.4.0"}}}
          local function tick()game.tick=game.tick+1;callbacks.tick()end
          if opponent~="" then
            callbacks.config(event)
            if opponent=="prelab-lab-active" then lab.disabled_by_script=false;lab_enable_writes=0 end
            if opponent~="source-partial" and opponent~="bad-transition" then callbacks.command{player_index=nil,parameter="continue"}end
            return
          end
          callbacks.load();callbacks.config(event)
          assert(logs[1].kind=="source")
          local bonus_count,status_count=0,0
          for _ in pairs(logs[1].frame.bonuses)do bonus_count=bonus_count+1 end
          for _ in pairs(logs[1].frame.technologies)do status_count=status_count+1 end
          assert(bonus_count==109 and status_count==34 and logs[1].map_price==1 and logs[1].lab.name==C.lab
            and logs[1].lab.disabled_by_script==true,"source marker is not the complete F1 frame")
          for _,section in ipairs({"mains","queue","unchanged","inventory","units","bonuses","technologies","prototypes"})do
            assert(logs[1].frame[section]~=nil,"missing live source section "..section)
          end
          local private_count=0;for _,row in pairs(logs[1].private_costs)do
            private_count=private_count+1;assert(row.ignore==true and row.native_count==1 and row.prototype_count==1)
          end;assert(private_count==6,"private carrier cost marker differs")
          tick();tick()
          assert(game.difficulty_settings.technology_price_multiplier==1 and queue_writes==0 and insert_calls==0
            and lab_enable_writes==0,"idle continuation barrier mutated native work")
          callbacks.command{player_index=nil,parameter="continue"}
          assert(queue_writes==1 and insert_calls==0 and lab_enable_writes==1 and #acks==1 and acks[1]=="[MIR516_PAID_CONTINUE]",
            "ordinary work was not uniquely admitted")
          local consumed=0
          for _=1,2000 do
            tick()
            if not lab.disabled_by_script and f.current_research==main then
              local amount=math.min(100,inv.counts[packs[1]])
              assert(amount>0,"capacity-limited refill starved the queued LDS")
              for _,name in ipairs(packs)do assert(inv.counts[name]>=amount);inv.counts[name]=inv.counts[name]-amount end
              consumed=consumed+amount
              if consumed==C.consumed then
                main.level=4;main.researched=false;main.saved_progress=0;f.current_research=nil;queue={};f.research_progress=0
                f.recipes["low-density-structure"].productivity_bonus=.3
                f.recipes["casting-low-density-structure"].productivity_bonus=.3
                f.recipes["scrap-recycling"].productivity_bonus=.1
                f.recipes["cerys-nuclear-scrap-recycling"].productivity_bonus=.1
                for index=1,95 do f.recipes["mir-vector-synthetic-scrap-"..index].productivity_bonus=.1 end
                if post_drift then f.recipes["plastic-bar"].productivity_bonus=.1 end
                callbacks.finished{research=main,by_script=false}
                assert(lab.disabled_by_script==true,"natural completion did not disable the observer lab")
                tick();break
              end
            end
          end
          assert(consumed==C.consumed and partial_insertions>0 and insert_calls>4,"bounded native refill did not use actual partial returns")
          assert(#saves==1 and saves[1].name=="mir516-native-credit-price-paid")
          assert(logs[2].kind=="pre-lab" and logs[2].map_price==2 and logs[2].lab.disabled_by_script==true)
          assert(logs[3].kind=="save" and logs[3].map_price==2 and #logs[3].science.completion_events==1
            and logs[3].science.completion_events[1].by_script==false and logs[3].lab.disabled_by_script==true)
          local snapshot=clone(storage)
          game.tick=storage.mir_native_credit_price_paid_observer.saved_tick;callbacks.load();tick()
          assert(storage.mir_native_credit_price_paid_observer.phase=="saved")
          game.tick=storage.mir_native_credit_price_paid_observer.saved_tick;callbacks.load();tick()
          assert(storage.mir_native_credit_price_paid_observer.phase=="saved")
          assert(logs[4].kind=="cold" and logs[4].map_price==2 and logs[4].lab.disabled_by_script==true)
          assert(logs[5].kind=="cold" and logs[5].map_price==2 and logs[5].lab.disabled_by_script==true)
          return {storage=snapshot,price=game.difficulty_settings.technology_price_multiplier,
            next_count=main.research_unit_count,queue_writes=queue_writes,insert_calls=insert_calls,
            lab_enable_writes=lab_enable_writes,partial_insertions=partial_insertions,logs=logs,saves=saves}
        ''')
        return self.lua.eval("{queue_writes=queue_writes,insert_calls=insert_calls,partial_insertions=partial_insertions,lab_enable_writes=lab_enable_writes}")

    def test_current_transition_consumes_exactly_one_paid_lds_and_cold_observes_only(self):
        result = self.story()
        self.assertEqual(1, result["queue_writes"])
        self.assertGreater(result["insert_calls"], 4)
        self.assertGreater(result["partial_insertions"], 0)
        self.assertEqual(1, result["lab_enable_writes"])
        self.assertEqual(2, self.lua.eval("last_game.difficulty_settings.technology_price_multiplier"))
        self.assertEqual(128000, self.lua.eval("last_force.technologies[C.main].research_unit_count"))
        self.assertEqual([0, 0, 0, 0, 0, 2], [
            self.lua.eval(f"C.completed(last_force.technologies[C.carriers[{index}]])") for index in range(1, 7)])
        self.assertEqual(0.3, self.lua.eval("last_force.recipes['low-density-structure'].productivity_bonus"))
        self.assertEqual(0.1, self.lua.eval("last_force.recipes['mir-vector-synthetic-scrap-95'].productivity_bonus"))

    def test_refusals_happen_before_any_queue_insert_or_lab_enable(self):
        for opponent, message in {
            "source-partial": "source LDS paid/queue state differs",
            "bad-transition": "exact 21015-to-21016/0.2-to-0.4 transition differs",
            "wrong-cost": "pre-lab LDS state differs",
            "wrong-ingredients": "LDS ingredient differs",
            "wrong-carrier": "LDS carrier state differs",
            "source-lab-active": "source observer lab is not disabled",
            "prelab-lab-active": "pre-lab observer lab is not disabled",
        }.items():
            with self.subTest(opponent=opponent):
                with self.assertRaisesRegex(LuaError, message):
                    self.story(opponent)
                self.assertEqual(0, self.lua.eval("queue_writes"))
                self.assertEqual(0, self.lua.eval("insert_calls"))
                self.assertEqual(0, self.lua.eval("lab_enable_writes"))

    def test_endpoint_refuses_an_unrelated_f1_bonus_drift(self):
        with self.assertRaisesRegex(LuaError, "unrelated F1 bonus changed plastic-bar"):
            self.story(post_drift=True)

    def test_false_and_zero_source_values_are_real_required_values(self):
        self.story()
        self.assertFalse(self.lua.eval("last_force.technologies[C.main].researched"))
        self.assertEqual(0, self.lua.eval("last_force.research_progress"))
        self.assertFalse(self.lua.eval("last_force.current_research"))

    def test_actor_has_no_private_or_fake_reward_path(self):
        actor = (FIXTURE / "control.lua").read_text()
        self.assertNotRegex(actor, r"\.(?:level|researched|saved_progress|research_progress|productivity_bonus)\s*=(?!=)")
        for forbidden in ("research_recursive", "reset_technology_effects", "script.raise_event", "require(\"runtime."):
            self.assertNotIn(forbidden, actor)
        self.assertNotIn("technology_price_multiplier=1", actor)
        self.assertIn("event.by_script==false", actor)
        self.assertIn("C.insertion", actor)
        self.assertIn("C.consumed", actor)

    def test_synthetic_derivative_only_replaces_the_observer_member(self):
        helper = load_archive_contract()
        names = [member["name"] for member in json.loads((FIXTURE / "archive-manifest.json").read_text())["source"]["members"]]
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source, derived, altered = directory / "source.zip", directory / "derived.zip", directory / "altered.zip"
            with zipfile.ZipFile(source, "w") as archive:
                for name in names:
                    archive.writestr(name, b"old-control" if name == helper.CONTROL else name.encode("ascii"))
            source_hash = helper.sha256(source.read_bytes())
            old_hash, new = helper.sha256(b"old-control"), b"new-paid-observer"
            helper.derive(source, derived, new, source_hash, old_hash)
            helper.verify(source, derived, source_hash, old_hash, helper.sha256(new))
            with zipfile.ZipFile(derived, "a") as archive:
                archive.writestr("extra", b"forbidden")
            with self.assertRaisesRegex(ValueError, "member order or names"):
                helper.verify(source, derived, source_hash, old_hash, helper.sha256(new))
            helper.derive(source, derived, new, source_hash, old_hash)
            with zipfile.ZipFile(altered, "w") as archive:
                for name, body in helper.rows(derived):
                    archive.writestr(name, b"changed-world" if name.endswith("level.dat0") else body)
            with self.assertRaisesRegex(ValueError, "non-observer member changed"):
                helper.verify(source, altered, source_hash, old_hash, helper.sha256(new))
            with self.assertRaisesRegex(ValueError, "source archive hash"):
                helper.verify(source, derived, "00" * 32, old_hash, helper.sha256(new))
            with self.assertRaisesRegex(ValueError, "observer replacement hash"):
                helper.verify(source, derived, source_hash, "00" * 32, helper.sha256(new))

    def test_borrowed_f1_data_stage_inputs_and_current_metadata_are_pinned(self):
        expected = {
            "data.lua": "33B53A9AAA6427BDCB8E26EC937C28AA5263B129859A94A0E85BAEA83B9B9523",
            "data-final-fixes.lua": "31BDA884A0EA36DD012758F75B54C9E2E49909F2BF89ED95C54D68CDA7E81F37",
            "cerys-technology-first45.lua": "F9C5646B863A3FC3332A0616053913A713A778D563B5DB2B147EF5BE3F0B51B1",
            "Cerys-LICENSE.txt": "F7F28B8C7A1AF76B9874CA6D040E8B1EB6768FD1043106C9D315090EA96754E7",
        }
        manifest = json.loads((FIXTURE / "archive-manifest.json").read_text())
        self.assertEqual(expected, manifest["borrowed_data_stage_members"])
        for name, digest in expected.items():
            self.assertEqual(digest, hashlib.sha256((OLD_FIXTURE / name).read_bytes()).hexdigest().upper())
            self.assertEqual(digest, hashlib.sha256((FIXTURE / name).read_bytes()).hexdigest().upper())
        metadata = json.loads((FIXTURE / "info.json").read_text())
        self.assertEqual("0.4.0", metadata["version"])
        self.assertEqual(["base = 2.1.23", "space-age = 2.1.23", "more-infinite-research = 5.0.21016"], metadata["dependencies"])
        self.assertEqual("recipe-prod-research_low_density_structure-1", self.lua.eval("C.main"))
        self.assertEqual(64000, self.lua.eval("C.consumed"))

    def test_byte_preserved_data_stage_members_produce_the_f1_vector(self):
        self.lua.execute(r'''
          mods={base="2.1.23",["space-age"]="2.1.23",quality="2.1.23",recycler="2.1.23",
            ["elevated-rails"]="2.1.23",["more-infinite-research"]="5.0.21016",[C.fixture]="0.4.0"}
          settings={startup={["mir-prefer-this-mod-for-competing-techs"]={value=true}}}
          table.deepcopy=clone
          data={raw={technology={},recipe={},lab={lab={type="lab",name="lab"}},["mod-data"]={}}}
          function data:extend(rows)for _,row in ipairs(rows)do self.raw[row.type]=self.raw[row.type]or{};self.raw[row.type][row.name]=row end end
          local function unit()return {count_formula="8000*2^(L-1)",time=60,ingredients={{"automation-science-pack",1},
            {"logistic-science-pack",1},{"chemical-science-pack",1},{"production-science-pack",1}}}end
          local credits={}
          for _,family in ipairs(C.families)do
            data.raw.technology[family.main]={name=family.main,hidden=true,effects={},unit=unit()};credits[family.family]={}
            for _,route in ipairs(family.routes)do
              credits[family.family][#credits[family.family]+1]={recipe=route.recipe,change=.1};data.raw.recipe[route.recipe]={type="recipe",name=route.recipe}
              for _,sign in ipairs({"positive","negative"})do data.raw.technology[C.carrier_for(family.family,route.recipe,sign)]={
                hidden=true,enabled=false,effects={{type="change-recipe-productivity",recipe=route.recipe,change=sign=="positive"and .1 or -.1}}}end
            end
          end
          for reference,names in pairs(C.base_reference_vectors)do
            data.raw.technology[reference]={effects={}}
            for _,name in ipairs(names)do data.raw.technology[reference].effects[#data.raw.technology[reference].effects+1]={
              type="change-recipe-productivity",recipe=name,change=.1}end
          end
          data.raw["mod-data"]["more-infinite-research-native-adoptions"]={data={credits=credits}}
          dofile(fixture_path.."/data.lua");dofile(fixture_path.."/data-final-fixes.lua")
          assert(#data.raw.technology[C.main].effects==99,"F1 LDS main vector differs")
          assert(#data.raw.technology[C.carrier_for("research_low_density_structure","scrap-recycling","positive")].effects==97)
          assert(#data.raw.technology["scrap-recycling-productivity"].effects==97)
          assert(data.raw.technology[C.main].hidden==false and data.raw.technology[C.main].enabled==true)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaError, LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Bounded observer opponents. Host physics/preparation are models, never native proof."""
import argparse
import json
from pathlib import Path
import sys
import unittest

from worker_storage_recovery_fixture import RECOVERY_WORLD

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/ferrum-worker-transition-native"


def plain(value):
    if not hasattr(value, "items"):
        return value
    rows = list(value.items())
    if rows and {k for k, _ in rows} == set(range(1, len(rows) + 1)):
        return [plain(value[i]) for i in range(1, len(rows) + 1)]
    return {k: plain(v) for k, v in rows}


class FerrumWorkerTransitionNativeControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().fingerprint = lambda v: json.dumps(plain(v), sort_keys=True)
        self.lua.execute(r'''
          function run_transition(opponent,native_count,actor_override)
            local C,P,N="worker-robots-storage-4","mir-worker-storage-preservation-4","worker-robots-storage-6"
            local S,CAL="mir-ferrum-transition-sentinel","mir-ferrum-transition-count-6"
            local LAB="mir-fixture-ferrum-worker-transition-lab"
            local base={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"}
            local old={table.unpack(base)};old[6]="electromagnetic-science-pack"
            local foreign={table.unpack(base)};foreign[6]="ferrum-robotics-science-pack"
            local useful={table.unpack(foreign)};useful[7]="electromagnetic-science-pack"
            local mods={base="2.1.23",["space-age"]="2.1.23",quality="2.1.23",["elevated-rails"]="2.1.23",recycler="2.1.23",
              ["more-infinite-research"]="5.0.21012",[LAB]="0.1.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            if opponent=="wrong-engine"then mods.base="2.0.77"end
            if opponent=="previous11"then mods["more-infinite-research"]="5.0.21011"end
            if opponent=="future13"then mods["more-infinite-research"]="5.0.21013"end
            local callbacks,commands,logs,saves,store,creators,forces,labs={},{},{},{},{},{},{},{}
            local game={tick=0,forces=forces,difficulty_settings={technology_price_multiplier=1},surfaces={nauvis={}}}
            local function ingredients(list)local out={};for _,id in ipairs(list)do out[#out+1]={name=id,amount=1,type="item"}end;return out end
            local function technology(f,id,first,cost,sci,prereqs,owner,formula)
              local worker=id==P or id:find("^worker%-robots%-storage%-%d+$")
              local t={name=id,force=f,level=first,researched=false,enabled=id~=P and id~=CAL,visible_when_disabled=false,saved_progress=0,prerequisites={}}
              local proto={level=first,max_level=formula and id~=CAL and 4294967295 or first,hidden=id==P or id==CAL,
                research_unit_count_formula=formula,research_unit_energy=3600,research_unit_ingredients=ingredients(sci),
                effects=worker and{{type="worker-robot-storage",modifier=1,hidden=false}}or{}}
              t.prototype=proto;creators[id]=owner
              setmetatable(t,{__index=function(_,key)
                if key=="research_unit_count"then
                  if id==CAL then return native_count elseif id==N then return t.level==6 and native_count or 2278 end
                  return formula and math.floor(675*1.5^(t.level-4))or cost
                elseif key=="research_unit_ingredients"then return proto.research_unit_ingredients end
              end})
              f.technologies[id]=t
              for _,name in ipairs(prereqs)do t.prerequisites[name]=assert(f.technologies[name],name)end
              t.research_recursive=function()
                for _,p in pairs(t.prerequisites)do if not p.researched then p.research_recursive()end end
                if not t.researched then
                  t.researched=true;if worker then f.native_bonus(1)end
                  callbacks.finished{research=t,by_script=true}
                end
              end
              return t
            end
            local function force(name)
              local index=1;for _ in pairs(forces)do index=index+1 end
              local f={name=name,index=index,technologies={}};local q,current,progress,bonus={},nil,0,0
              setmetatable(f,{__index=function(_,key)
                if key=="research_queue"then return q elseif key=="current_research"then return current
                elseif key=="research_progress"then return progress elseif key=="worker_robots_storage_bonus"then return bonus
                elseif key=="laboratory_speed_modifier"then return 0 end
              end,__newindex=function(_,key,v)
                if key=="worker_robots_storage_bonus"then error("actor direct bonus write")
                elseif key=="research_queue"then
                  if current then current.saved_progress=progress end
                  q={};for _,x in ipairs(v)do q[#q+1]=type(x)=="string"and f.technologies[x]or x end
                  current=q[1];progress=current and current.saved_progress or 0
                  if current then
                    if current.researched and current.prototype.max_level==4294967295 then current.level=current.level+1;current.researched=false end
                    current.saved_progress=0
                  end
                elseif key=="research_progress"then progress=v else rawset(f,key,v)end
              end})
              f.native_bonus=function(n)bonus=bonus+n end
              f.finish=function(t)
                t.researched=true;if t.name~=S then bonus=bonus+1 end
                table.remove(q,1);current=nil;progress=0
                callbacks.finished{research=t,by_script=opponent=="scripted-completion"}
                if opponent=="duplicate-completion"then callbacks.finished{research=t,by_script=false}end
                if t.name==P then t.enabled=false end -- Model the independently tested MIR retirement.
              end
              for _,id in ipairs(useful)do technology(f,id,1,1,{}, {},"base")end
              for i=1,3 do technology(f,"worker-robots-storage-"..i,i,150*i,base,i==1 and{}or{"worker-robots-storage-"..(i-1)},"base")end
              technology(f,C,4,0,old,{"worker-robots-storage-2","worker-robots-storage-3",table.unpack(old)},"more-infinite-research","675*1.5^(L-4)")
              technology(f,P,4,0,old,{"worker-robots-storage-2","worker-robots-storage-3",table.unpack(old)},"more-infinite-research","675*1.5^(L-4)")
              technology(f,S,1,1000,{base[1]}, {},LAB)
              technology(f,CAL,6,0,{base[1]}, {},LAB,"1518.75")
              forces[name]=f;return f
            end
            force("player");force("enemy");force("neutral");game.create_force=force
            game.surfaces.nauvis.set_tiles=function()end
            game.surfaces.nauvis.create_entity=function(spec)
              local items={};local inv={insert=function(row)local n=math.min(row.count,200-(items[row.name]or 0));items[row.name]=(items[row.name]or 0)+n;return n end,
                clear=function()for k in pairs(items)do items[k]=nil end end,
                is_empty=function()for _,v in pairs(items)do if v~=0 then return false end end;return true end,
                get_item_count=function(id)return items[id]or 0 end}
              local lab={valid=true,disabled_by_script=true,force=spec.force,items=items,get_inventory=function()return inv end}
              labs[spec.force.name]=lab;return lab
            end
            game.server_save=function(name)saves[#saves+1]=name end
            local env={game=game,storage=store,settings={startup={["mir-max-level-worker-robots-storage"]={value=8},["mir-enable-worker-robots-storage"]={value=true}}},
              prototypes={get_history=function(_,id)return{created=creators[id]}end},helpers={table_to_json=fingerprint},
              commands={add_command=function(id,_,fn)commands[id]=fn end},log=function(s)logs[#logs+1]=s end,
              defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}}}
            env._G=env;setmetatable(env,{__index=_G})
            local function parse()
              callbacks={};env.script={active_mods=mods,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_configuration_changed=function(fn)callbacks.config=fn end,on_event=function(id,fn)callbacks[id==1 and"tick"or"finished"]=fn end}
              if actor_override then assert(load(actor_override,"mutant","t",env))()else assert(loadfile(actor_path,"t",env))()end
            end
            local function step()
              game.tick=game.tick+1
              for name,lab in pairs(labs)do
                local f=forces[name];local t=f.current_research
                if not lab.disabled_by_script and t then
                  local done=math.floor(f.research_progress*t.research_unit_count+.0000001)
                  local amount=math.min(40,t.research_unit_count-done)
                  for _,i in ipairs(t.research_unit_ingredients)do amount=math.min(amount,lab.items[i.name]or 0)end
                  if amount>0 then
                    if opponent~="no-consumption"then for _,i in ipairs(t.research_unit_ingredients)do lab.items[i.name]=lab.items[i.name]-amount end end
                    done=done+amount;f.research_progress=done/t.research_unit_count
                    if done==t.research_unit_count then f.finish(t)end
                  end
                end
              end
              callbacks.tick{}
            end
            local function until_phase(phase)
              for _=1,1600 do if store.mir_ferrum_transition_native.phase==phase then return end;step()end
              error("host phase bound exceeded")
            end
            parse();callbacks.init();until_phase("source-saved")
            local s=store.mir_ferrum_transition_native;local command=commands["mir-ferrum-transition-probe"]
            if opponent=="prepare-before-source"then s.phase="source"end
            command{parameter="begin-prepare"}
            -- Explicit host model of the actual command boundary, not native evidence.
            for _,f in pairs(forces)do
              local c,p=f.technologies[C],f.technologies[P];p.level=c.level+(c.researched and 1 or 0);p.researched=false
              p.enabled=(f.current_research==c or c.saved_progress>0)and c.enabled or false
              p.visible_when_disabled=c.visible_when_disabled;p.saved_progress=c.saved_progress
              local ids={};for _,t in ipairs(f.research_queue)do ids[#ids+1]=t.name==C and P or t.name end
              local progress=f.research_progress;c.level=4;c.researched=false;c.saved_progress=0
              f.research_queue=ids;f.research_progress=progress;c.saved_progress=0
              if f.current_research==p then p.saved_progress=0 end
            end
            if opponent=="lost-transfer-bonus"then forces.player.native_bonus(-1)end
            if opponent=="lost-transfer-queue"then forces.player.research_queue={P}end
            if opponent=="lost-transfer-partial"then forces["worker-suspended"].technologies[P].saved_progress=0 end
            command{parameter="check-prepare-once"}
            if opponent=="repeat-transfer"then forces.player.technologies[P].level=9 end
            command{parameter="prepared"}
            local prepared_fingerprint=fingerprint(s.closed)
            parse();callbacks.load();callbacks.tick{};assert(fingerprint(s.closed)==prepared_fingerprint)
            for _,f in pairs(forces)do
              local oldc=f.technologies[C]
              local c=technology(f,C,4,675,foreign,{"worker-robots-storage-3","ferrum-robotics-science-pack"},"planet-ferrum")
              c.enabled=oldc.enabled;c.visible_when_disabled=oldc.visible_when_disabled
              technology(f,"worker-robots-storage-5",5,1012,foreign,{C},"planet-ferrum")
              technology(f,N,6,0,useful,{C,"worker-robots-storage-5",table.unpack(old)},"more-infinite-research","1518.75*1.5^(L-6)")
            end
            mods["planet-ferrum"],mods.PlanetsLib,mods["spider-launcher"]="0.1.5","2.4.0","2.9.87"
            if opponent=="wrong-provider"then mods["planet-ferrum"]="0.1.4"end
            if opponent=="granted-foreign4"then forces.player.technologies[C].researched=true end
            if opponent=="lost-private-level"then forces.player.technologies[P].level=7 end
            if opponent=="lost-current"then forces.player.research_progress=.1 end
            if opponent=="foreign-flag"then forces["worker-uninvested"].technologies[C].enabled=true end
            if opponent=="missing-robotics"then forces.player.technologies[N].prototype.research_unit_ingredients[6].name="military-science-pack"end
            if opponent=="wrong-private-cost"then forces.player.technologies[P].prototype.research_unit_count_formula="100*2^(L-4)"end
            if opponent=="wrong-time-seconds"then forces.player.technologies[C].prototype.research_unit_energy=60 end
            if opponent=="wrong-finite-level"then forces.player.technologies[C].level=5 end
            if opponent=="wrong-public-count"then rawset(forces.player.technologies[N],"research_unit_count",native_count+1)end
            if opponent=="wrong-cap"then env.settings.startup["mir-max-level-worker-robots-storage"].value=9 end
            parse();callbacks.load();callbacks.config{mod_changes={["planet-ferrum"]={new_version=mods["planet-ferrum"]},PlanetsLib={new_version="2.4.0"},["spider-launcher"]={new_version="2.9.87"}}}
            if opponent=="post-MIR-private"then forces.player.technologies[P].enabled=false end
            callbacks.tick{}
            local f=forces["worker-suspended"];local saved=f.technologies[P].saved_progress;local progress=f.research_progress
            f.research_queue={S,P};f.technologies[P].saved_progress=saved;f.research_progress=progress
            commands["mir-ferrum-transition-probe"]{parameter="run-provider"}
            until_phase("destination-saved")
            if opponent=="altered-cold"then forces["worker-uninvested"].research_progress=.123 end
            if opponent=="premature-cold"then s.phase="provider-ready"end
            local function stable()return{phase=s.phase,source=s.source,prepared=s.prepared,closed=s.closed,ordinary=s.ordinary,consumption=s.consumption,administrative=s.administrative_events,transfers=s.transfer_events}end
            local before=fingerprint(stable())
            for _=1,2 do
              parse();local original_game,original_storage=env.game,env.storage;env.game,env.storage=nil,nil;callbacks.load()
              env.game,env.storage=original_game,original_storage;callbacks.tick{};assert(fingerprint(stable())==before,"cold mutated saved state")
            end
            return{ordinary=s.ordinary,consumption=s.consumption,saves=saves,logs=logs,frames=s.closed,readonly_colds=2,native_evidence=false}
          end
        ''')

    def run_case(self, opponent=None, native_count=1518, actor_override=None):
        return plain(self.lua.globals().run_transition(opponent, native_count, actor_override))

    def test_four_process_observer_model_preserves_entry_and_requires_all_ordinary_work(self):
        for count in (1518, 1519):
            with self.subTest(calibration=count):
                result = self.run_case(native_count=count)
                self.assertEqual(result["ordinary"]["player"], {"worker-robots-storage-4":5,
                    "mir-worker-storage-preservation-4":1,"worker-robots-storage-5":1,"worker-robots-storage-6":1})
                self.assertEqual(result["ordinary"]["worker-suspended"], {"worker-robots-storage-4":3,"mir-worker-storage-preservation-4":1})
                self.assertEqual(result["frames"]["player"]["bonus"], 11)
                self.assertEqual(result["frames"]["worker-suspended"]["bonus"], 7)
                self.assertEqual(result["saves"], ["mir-ferrum-transition-source","mir-ferrum-transition-prepared","mir-ferrum-transition-destination"])
                self.assertEqual(result["readonly_colds"], 2)
                self.assertFalse(result["native_evidence"])

    def test_scripted_duplicate_and_no_consumption_do_not_become_lab_evidence(self):
        for opponent in ("scripted-completion","duplicate-completion","no-consumption"):
            with self.subTest(opponent=opponent), self.assertRaises(Exception):
                self.run_case(opponent)

    def test_wrong_exact_tuple_settings_and_native_seconds_refuse(self):
        for opponent in ("wrong-engine","previous11","future13","wrong-provider","wrong-cap","wrong-time-seconds"):
            with self.subTest(opponent=opponent), self.assertRaises(Exception):
                self.run_case(opponent)

    def test_preparation_cannot_lose_earned_benefit_queue_or_suspended_work(self):
        for opponent in ("prepare-before-source","lost-transfer-bonus","lost-transfer-queue","lost-transfer-partial","repeat-transfer"):
            with self.subTest(opponent=opponent), self.assertRaises(Exception):
                self.run_case(opponent)

    def test_provider_entry_cannot_grant_foreign_work_or_change_private_current_flags_science(self):
        for opponent in ("granted-foreign4","lost-private-level","lost-current","foreign-flag",
                         "missing-robotics","wrong-private-cost","post-MIR-private","wrong-finite-level","wrong-public-count"):
            with self.subTest(opponent=opponent), self.assertRaises(Exception):
                self.run_case(opponent)

    def test_premature_or_altered_cold_is_not_an_immutable_reload(self):
        for opponent in ("premature-cold","altered-cold"):
            with self.subTest(opponent=opponent), self.assertRaises(Exception):
                self.run_case(opponent)

    def test_consumption_guard_has_meaningful_mutant_opposition(self):
        original = (FIXTURE / "control.lua").read_text()
        mutant = original.replace('check(consumed[pack]>0 and consumed[pack]<=budget,"required science was not consumed")', '')
        mutant = mutant.replace('if r.work.initial==0 then check(consumed[pack]==budget,"full ordinary science consumption") end', '')
        self.assertNotEqual(original, mutant)
        result = self.run_case("no-consumption", actor_override=mutant)
        self.assertFalse(result["native_evidence"])

    def test_actual_recovery_module_admits_prepared_two_stage_ferrum_without_public_grants(self):
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""')
        self.lua.execute(RECOVERY_WORLD)
        self.lua.execute(r'''
          history.on_init(nil);seed();assert(history.prepare(nil));local prepared=storage.mir_worker_storage_route
          writes=0;assert(history.prepare(nil)==false and writes==0,"repeat preparation changed native work")
          add_provider(5);creators[CANONICAL]="planet-ferrum"
          local route=provider_route(5)
          for _,stage in ipairs(route.finite)do stage.provider="planet-ferrum"end
          writes=0;local plan=history.preflight({mod_changes={["planet-ferrum"]={new_version="0.1.5"}}},route)
          assert(writes==0 and history.plan_prepared(plan));history.apply(plan)
          assert(storage.mir_worker_storage_route.phase=="provider")
          assert(player.technologies[ID].level==8 and player.current_research.name==ID and player.research_progress==.375)
          assert(suspended.technologies[ID].saved_progress==.27 and suspended.current_research.name==OTHER)
          assert(not uninvested.technologies[CANONICAL].enabled)
          for _,f in pairs(game.forces)do for level=4,6 do assert(not f.technologies["worker-robots-storage-"..level].researched)end end
          local state=storage.mir_worker_storage_route;writes=0
          for _=1,2 do history.on_load();assert(writes==0 and storage.mir_worker_storage_route==state)end
          assert(not pcall(history.preflight,{mod_changes={["planet-ferrum"]={old_version="0.1.5"}}},nil)and writes==0)
        ''')

    def test_actual_recovery_module_refuses_unprepared_or_changed_private_contract_no_write(self):
        for prepare in (False, True):
            with self.subTest(prepared=prepare):
                lua = LuaRuntime(unpack_returned_tuples=True)
                lua.globals().player_root = (ROOT / "source").as_posix()
                lua.execute('package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""')
                lua.execute(RECOVERY_WORLD)
                lua.execute('history.on_init(nil);seed();' + ('history.prepare(nil);prototypes.technology[ID].research_unit_energy=60;' if prepare else '') + r'''
                  add_provider(5);local route=provider_route(5)
                  for _,stage in ipairs(route.finite)do stage.provider="planet-ferrum"end
                  local state=storage.mir_worker_storage_route;writes=0
                  local ok,message=pcall(history.preflight,{mod_changes={["planet-ferrum"]={new_version="0.1.5"}}},route)
                  assert(not ok and writes==0 and storage.mir_worker_storage_route==state)
                ''')

    def test_lab_only_extends_its_own_rows_and_keeps_upstream_robotics_augmentation(self):
        self.lua.globals().lab_path = (FIXTURE / "lab-source/data.lua").as_posix()
        for category in ("item", "tool"):
            self.lua.globals().category = category
            rows = plain(self.lua.execute('''local function clone(v)if type(v)~="table"then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
              local raw={lab={lab={type="lab",name="lab",inputs={"automation-science-pack"}}}};raw[category]={}
              for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack","space-science-pack","electromagnetic-science-pack"})do raw[category][name]={name=name}end
              local rows;local env={data={raw=raw,extend=function(_,r)rows=r end},table={deepcopy=clone}};setmetatable(env,{__index=_G});assert(loadfile(lab_path,"t",env))()
              assert(raw.lab.lab.name=="lab"and #raw.lab.lab.inputs==1);return rows'''))
            self.assertEqual(len(rows), 3)
            self.assertEqual(rows[0]["researching_speed"], 1001)
            self.assertIn("space-science-pack", rows[0]["inputs"])
            self.assertNotIn("ferrum-robotics-science-pack", rows[0]["inputs"])
            self.assertEqual(rows[2]["unit"]["count_formula"], "1518.75")
            self.assertNotIn("count", rows[2]["unit"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Independent scenario rejection controls; no native earnings or gameplay result."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/ferrum-worker-storage-native"


def plain(value):
    if not hasattr(value, "items"):
        return value
    pairs = list(value.items())
    if pairs and {k for k, _ in pairs} == set(range(1, len(pairs) + 1)):
        return [plain(value[i]) for i in range(1, len(pairs) + 1)]
    return {k: plain(v) for k, v in pairs}


class FerrumWorkerStorageNativeControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().actor_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().fingerprint = lambda v: json.dumps(plain(v), sort_keys=True)
        self.lua.execute(r'''
          function run_ferrum(target,opponent,native_count,actor_override,cargo_mode)
            local C4,C5,N,P="worker-robots-storage-4","worker-robots-storage-5","worker-robots-storage-6","mir-worker-storage-preservation-4"
            local S,T,CAL="mir-ferrum-sentinel","mir-ferrum-detached","mir-ferrum-count-control-6"
            local LAB="mir-fixture-ferrum-worker-storage-native-lab"
            local packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"}
            local source={table.unpack(packs)};source[6]="ferrum-robotics-science-pack"
            local useful={table.unpack(source)};useful[7]="electromagnetic-science-pack"
            local private={table.unpack(packs)};private[6]="electromagnetic-science-pack"
            local callbacks,interfaces,store,logs,saves={},{},{},{},{}
            last_ferrum_storage,last_ferrum_logs,last_ferrum_saves=store,logs,saves
            local creators,forces={},{}
            local modern=target=="f210"
            local base=modern and "2.1.23"or"2.0.77"
            local mods={base=base,["space-age"]=base,quality=base,["elevated-rails"]=base,
              PlanetsLib=modern and "2.4.0"or"1.18.0",["spider-launcher"]=modern and "2.9.87"or"2.9.86",
              ["planet-ferrum"]=modern and "0.1.5"or"0.0.5",[LAB]="0.1.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            if modern then mods.recycler=base end
            if opponent=="wrong-engine"then mods.base="2.1.24"end
            if opponent=="wrong-provider"then mods["planet-ferrum"]="0.1.4"end
            local game={forces=forces,tick=0,difficulty_settings={technology_price_multiplier=1},surfaces={nauvis={}}}
            local lab,env
            local function ingredients(list)local out={};for _,n in ipairs(list)do out[#out+1]={name=n,amount=1,type="item"}end;return out end
            local function effect()
              local e={type="worker-robot-storage",modifier=1};if modern then e.hidden=false end;return{e}
            end
            local function technology(f,id,first,cost,science,prerequisites,creator,infinite,formula)
              local proto={level=first,max_level=infinite and 4294967295 or first,hidden=id==P or id==CAL,
                research_unit_count_formula=formula,research_unit_energy=3600,research_unit_ingredients=ingredients(science),
                effects=(id:find("worker%-robots%-storage") or id==P)and effect()or{}}
              local t={name=id,prototype=proto,level=first,researched=false,enabled=id~=P and id~=CAL,
                visible_when_disabled=false,saved_progress=0,prerequisites={},force=f}
              setmetatable(t,{__index=function(_,key)
                if key=="research_unit_count"then
                  if id==CAL then return native_count end
                  if id==N then return t.level==6 and native_count or 2278 end
                  return cost
                elseif key=="research_unit_ingredients"then return proto.research_unit_ingredients end
              end})
              creators[id]=creator
              t.research_recursive=function()
                for _,p in pairs(t.prerequisites)do if not p.researched then p.research_recursive()end end
                if not t.researched then
                  t.researched=true
                  if id:find("^worker%-robots%-storage%-[123]$")then f.worker_robots_storage_bonus=f.worker_robots_storage_bonus+1 end
                  callbacks.finished{research=t,by_script=true}
                end
              end
              f.technologies[id]=t
              for _,name in ipairs(prerequisites)do t.prerequisites[name]=assert(f.technologies[name],name)end
              return t
            end
            local function force(name)
              local f={name=name,index=0,technologies={},worker_robots_storage_bonus=0,laboratory_speed_modifier=0}
              for _ in pairs(forces)do f.index=f.index+1 end
              local q,current,progress={},nil,0
              setmetatable(f,{__index=function(_,key)
                if key=="research_queue"then return q elseif key=="current_research"then return current
                elseif key=="research_progress"then return progress end
              end,__newindex=function(_,key,v)
                if key=="research_queue"then
                  if current then current.saved_progress=progress end
                  q=v;current=q[1];progress=current and current.saved_progress or 0
                  if current then current.saved_progress=0 end
                elseif key=="research_progress"then progress=v else rawset(f,key,v)end
              end})
              f.finish=function(t)
                t.researched=true;f.worker_robots_storage_bonus=f.worker_robots_storage_bonus+1
                current=nil;q={};progress=0
                callbacks.finished{research=t,by_script=opponent=="scripted-completion"}
                if opponent=="duplicate-completion"then callbacks.finished{research=t,by_script=false}end
                if t.name==N and opponent~="completed-native-form"then t.level=7;t.researched=false end
              end
              for _,id in ipairs({table.unpack(useful)})do technology(f,id,1,1,{}, {},"base")end
              for i=1,3 do technology(f,"worker-robots-storage-"..i,i,i*150,packs,i==1 and{}or{"worker-robots-storage-"..(i-1)},"base")end
              technology(f,C4,4,675,source,{"worker-robots-storage-3","ferrum-robotics-science-pack"},"planet-ferrum")
              technology(f,C5,5,1012,source,{C4},"planet-ferrum")
              technology(f,S,1,1000,{packs[1]}, {},LAB);technology(f,T,1,1000,{packs[1]}, {},LAB)
              technology(f,CAL,6,0,{packs[1]}, {},LAB,false,"1518.75")
              forces[name]=f;return f
            end
            force("player");force("enemy");force("neutral")
            if opponent=="raw-seconds-energy"then forces.player.technologies[C4].prototype.research_unit_energy=60 end
            game.create_force=force
            game.server_save=function(name)saves[#saves+1]=name end
            game.surfaces.nauvis.set_tiles=function()end
            game.surfaces.nauvis.create_entity=function(spec)
              local items={}
              local inventory={insert=function(row)
                local added=math.min(row.count,200-(items[row.name]or 0));items[row.name]=(items[row.name]or 0)+added;return added
              end,get_item_count=function(name)return items[name]or 0 end}
              local inputs={table.unpack(useful)};inputs[#inputs+1]="space-science-pack"
              lab={valid=true,disabled_by_script=true,force=spec.force,prototype={lab_inputs=inputs},items=items,
                get_inventory=function()return inventory end}
              last_ferrum_lab=lab
              return lab
            end
            local surface=game.surfaces.nauvis
            local commands,boxes,physical={}, {},{step=0,created=0}
            local network={cells={{}},all_logistic_robots=1,all_construction_robots=0,
              available_logistic_robots=1,logistic_robots={}}
            local slot,section=nil,{}
            section.is_manual=true;section.active=false
            section.set_slot=function(index,value)assert(index==1);slot=value end
            section.get_slot=function(index)assert(index==1);return slot end
            local point={sections_count=0}
            point.add_section=function()point.sections_count=1;return section end
            point.get_section=function(index)assert(index==1);return section end
            local create_lab=surface.create_entity
            surface.find_entities_filtered=function()return{}end
            local function box(name)
              local values={}
              local inventory={get_item_count=function(item)
                if item==nil then local n=0;for _,v in pairs(values)do n=n+v end;return n end
                if type(item)=="table"then assert(item.quality=="normal");item=item.name end
                return values[item]or 0
              end,insert=function(item)
                assert(name~="requester-chest"and name~="robot","actor wrote delivery/cargo inventory")
                assert(item.quality=="normal");values[item.name]=(values[item.name]or 0)+item.count;return item.count
              end}
              return{values=values,inventory=inventory}
            end
            surface.create_entity=function(spec)
              if spec.name=="mir-ferrum-lab"then local v=create_lab(spec);v.surface=surface;return v end
              physical.created=physical.created+1
              local data=box(spec.name);boxes[spec.name]=data
              local entity={valid=true,name=spec.name,quality={name=spec.quality},position={x=spec.position[1],y=spec.position[2]},
                force=spec.force,unit_number=100+physical.created,type=spec.name=="roboport"and"roboport"or"logistic-container",
                get_inventory=function()return data.inventory end}
              if spec.name=="roboport"then entity.electric_buffer_size=100000000;entity.logistic_network=network end
              if spec.name=="requester-chest"then entity.get_logistic_point=function(index)assert(index==1);return point end end
              data.entity=entity;return entity
            end
            local robot_box=box("robot")
            local robot={valid=true,name="logistic-robot",type="logistic-robot",quality={name="normal"},force=forces.player,
              unit_number=200,prototype={max_payload_size=1},position={x=-10,y=12},get_inventory=function()return robot_box.inventory end}
            local function cargo_native_step()
              if not store.mir_ferrum_worker_native.cargo then return end
              physical.step=physical.step+1
              local mode=cargo_mode
              if mode=="timeout"then game.tick=store.mir_ferrum_worker_native.cargo.deadline+1;return end
              local p,r,d=boxes["passive-provider-chest"].values,boxes["requester-chest"].values,boxes.roboport.values
              if physical.step==1 then
                p["iron-plate"]=0;d["logistic-robot"]=0;robot_box.values["iron-plate"]=7
                network.logistic_robots={robot};network.available_logistic_robots=0
                if mode=="partial-trips"then p["iron-plate"]=6;robot_box.values["iron-plate"]=1 end
                if mode=="non-normal"then robot.quality.name="uncommon"end
                if mode=="extra-robot"then network.all_logistic_robots=2 end
                if mode=="invented-iron"then p["iron-plate"]=1 end
                if mode=="lost-iron"then robot_box.values["iron-plate"]=0;p["iron-plate"]=6 end
                if mode=="changed-request"then slot.min=6 end
                if mode=="native-research-write"then forces.player.worker_robots_storage_bonus=7 end
                if mode=="foreign-frame"then forces["mir-ferrum-foreign"].research_progress=.1 end
                if mode=="no-flight"then robot_box.values["iron-plate"]=0;r["iron-plate"]=7 end
              elseif physical.step==2 then
                if mode~="stationary-load"then robot.position={x=-8,y=12}end
                if mode=="changed-robot"then robot.unit_number=201 end
              elseif physical.step==3 then
                robot_box.values["iron-plate"]=0;r["iron-plate"]=mode=="duplicate-delivery"and 8 or 7
              else
                d["logistic-robot"]=1;network.logistic_robots={};network.available_logistic_robots=1
              end
            end
            env={game=game,storage=store,remote={add_interface=function(n,v)interfaces[n]=v end},
              prototypes={get_history=function(_,name)return{created=creators[name]}end,entity={["logistic-robot"]={max_payload_size=1}}},
              commands={add_command=function(name,_,fn)commands[name]=fn end},
              helpers={table_to_json=fingerprint},defines={inventory={lab_input=1,chest=2,roboport_robot=3,robot_cargo=4},
                logistic_member_index={logistic_container=1},events={on_tick=1,on_research_finished=2}},
              log=function(text)logs[#logs+1]=text end}
            env._G=env;setmetatable(env,{__index=_G})
            local function parse()
              callbacks={};env.script={active_mods=mods,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_configuration_changed=function(fn)callbacks.config=fn end,
                on_event=function(id,fn)if id==1 then callbacks.tick=fn else callbacks.finished=fn end end}
              if actor_override then assert(load(actor_override,"mutant","t",env))()else assert(loadfile(actor_path,"t",env))()end
            end
            local work={}
            local function step()
              game.tick=game.tick+1
              local t=forces.player.current_research
              if not lab.disabled_by_script and t and (t.name==C4 or t.name==C5 or t.name==N)then
                local done=work[t.name]or 0;local amount=math.min(40,t.research_unit_count-done)
                for _,i in ipairs(t.research_unit_ingredients)do amount=math.min(amount,lab.items[i.name]or 0)end
                if amount>0 then
                  if opponent~="no-consumption"then for _,i in ipairs(t.research_unit_ingredients)do lab.items[i.name]=lab.items[i.name]-amount end end
                  done=done+amount;work[t.name]=done;forces.player.research_progress=done/t.research_unit_count
                  if done==t.research_unit_count then forces.player.finish(t)end
                end
              end
              if opponent=="no-progress-witness"then forces.player.research_progress=0 end
              if cargo_mode then cargo_native_step()end
              callbacks.tick{}
            end
            local function until_phase(phase)
              for i=1,500 do if store.mir_ferrum_worker_native.phase==phase then return end;step()end
              error("host scenario exceeded bound")
            end
            parse();callbacks.init();until_phase("source-saved")
            local state=store.mir_ferrum_worker_native
            if cargo_mode=="source-phase"then commands["mir-ferrum-worker-cargo"]{parameter="start"}end
            if opponent=="premature-cold"then parse();callbacks.load();callbacks.tick{};error("premature cold admitted")end
            if opponent=="wrong-price"then game.difficulty_settings.technology_price_multiplier=2 end
            if opponent=="lost-source-bonus"then forces.player.worker_robots_storage_bonus=4 end
            if opponent=="lost-earned-flag"then forces.player.technologies[C4].researched=false end
            if opponent=="lost-current-progress"then forces.player.research_progress=.25 end
            if opponent=="lost-foreign-progress"then forces["mir-ferrum-foreign"].technologies[T].saved_progress=.1 end
            if opponent=="lost-disabled-flag"then forces["mir-ferrum-foreign"].technologies[C4].enabled=true end
            if opponent=="wrong-source-science"then forces.player.technologies[C4].prototype.research_unit_ingredients[6].name="military-science-pack"end
            for _,f in pairs(forces)do
              technology(f,P,4,675,private,{"worker-robots-storage-2","worker-robots-storage-3",table.unpack(private)},"more-infinite-research",true,"675*1.5^(L-4)")
              technology(f,N,6,0,useful,{C4,C5,table.unpack(private)},"more-infinite-research",true,"1518.75*1.5^(L-6)")
            end
            local n=forces.player.technologies[N]
            if opponent=="lost-finite-row"then forces.player.technologies[C4]=nil end
            if opponent=="wrong-MIR-science"then n.prototype.research_unit_ingredients[7].name="military-science-pack"end
            if opponent=="wrong-formula"then n.prototype.research_unit_count_formula="1012*1.5^(L-6)"end
            if opponent=="wrong-effect"then n.prototype.effects[1].modifier=2 end
            if opponent=="wrong-native-count"then rawset(n,"research_unit_count",native_count+1)end
            if opponent=="dummy-private"then forces.player.technologies[P].prototype.research_unit_energy=1 end
            if opponent=="missing-private-worker2"then forces.player.technologies[P].prerequisites["worker-robots-storage-2"]=nil end
            if opponent=="private-foreign-investment"then forces["mir-ferrum-foreign"].technologies[P].level=5 end
            if opponent=="public7-overlap"then forces.player.technologies["worker-robots-storage-7"]=n end
            if opponent=="calibration-researched"then forces.player.technologies[CAL].researched=true end
            if opponent=="bad-F210-hidden"then n.prototype.effects[1].hidden=nil end
            if opponent=="bad-F200-hidden"then n.prototype.effects[1].hidden="false"end
            mods["more-infinite-research"]=modern and "5.0.21012"or"5.0.20012"
            if opponent=="wrong-MIR-version"then mods["more-infinite-research"]=modern and"5.0.21013"or"5.0.20013"end
            if opponent=="previous-MIR11"then mods["more-infinite-research"]=modern and"5.0.21011"or"5.0.20011"end
            if opponent=="opposite-edition"then mods["more-infinite-research"]=modern and"5.0.20012"or"5.0.21012"end
            if opponent=="wrong-phase"then state.phase="earning"end
            parse();callbacks.load();callbacks.config{mod_changes={["more-infinite-research"]={new_version=mods["more-infinite-research"]}}}
            if opponent=="post-MIR-foreign"then forces["mir-ferrum-foreign"].research_progress=.33 end
            if opponent=="post-MIR-private"then forces.player.technologies[P].enabled=true end
            until_phase("destination-saved")
            if cargo_mode then
              commands["mir-ferrum-worker-cargo"]{parameter=cargo_mode=="wrong-parameter"and"other"or"start",
                player_index=cargo_mode=="player-command"and 1 or nil}
              if cargo_mode=="duplicate-command"then commands["mir-ferrum-worker-cargo"]{parameter="start"}end
              until_phase("cargo-destination-saved")
              if cargo_mode=="changed-cold-cargo"then boxes["requester-chest"].values["iron-plate"]=6 end
              if cargo_mode=="changed-cold-position"then boxes["requester-chest"].entity.position.x=99 end
            end
            if opponent=="altered-cold"then forces["mir-ferrum-foreign"].research_progress=.123 end
            if opponent=="altered-cold-inventory"then lab.items[packs[1]]=1 end
            local function stable()return{phase=state.phase,ordinary=state.ordinary,consumption=state.consumption,source=state.source,
              entry=state.entry,closed=state.closed,administrative_events=state.administrative_events,
              cargo=state.cargo and state.cargo.report or nil}end
            local before=fingerprint(stable());local old_game,old_storage=env.game,env.storage
            parse();env.game=nil;env.storage=nil;callbacks.load();env.game,env.storage=old_game,old_storage
            assert(fingerprint(stable())==before,"on_load changed state")
            callbacks.tick{};assert(fingerprint(stable())==before,"cold changed state")
            parse();callbacks.load();callbacks.tick{};assert(fingerprint(stable())==before,"second cold changed state")
            local report=interfaces["mir-ferrum-worker-storage-native"].report();assert(fingerprint(stable())==before,"report changed state")
            return{report=report,saves=saves,logs=logs,consumption=state.consumption,entry=state.entry,closed=state.closed,
              ordinary=state.ordinary,administrative=state.administrative_events,cold_readonly=true,native_evidence=false}
          end
        ''')

    def run_case(self, opponent=None, target="f210", native_count=1518, actor_override=None, cargo_mode=None):
        return plain(self.lua.globals().run_ferrum(target, opponent, native_count, actor_override, cargo_mode))

    def test_physical_cargo_phase_requires_loaded_flight_delivery_and_two_colds(self):
        result = self.run_case(cargo_mode="normal")
        report = result["report"]
        self.assertTrue(report["physical_robot_delivery"])
        cargo = report["cargo"]
        self.assertEqual(cargo["loaded"]["frame"]["active"][0]["count"], 7)
        self.assertEqual(cargo["flight"]["frame"]["active"][0]["count"], 7)
        self.assertNotEqual(cargo["loaded"]["frame"]["active"][0]["position"],
                            cargo["flight"]["frame"]["active"][0]["position"])
        self.assertEqual(cargo["delivered"]["frame"]["requester"], 7)
        self.assertEqual(cargo["delivered"]["frame"]["provider"], 0)
        self.assertEqual(cargo["delivered"]["frame"]["docked"], 1)
        self.assertEqual(result["saves"], ["mir-ferrum-worker-source", "mir-ferrum-worker-destination",
                                         "mir-ferrum-worker-cargo-destination"])
        self.assertEqual(result["ordinary"], {"worker-robots-storage-4": 1,
                         "worker-robots-storage-5": 1, "worker-robots-storage-6": 1})
        self.assertTrue(result["cold_readonly"])
        self.assertFalse(result["native_evidence"])
        markers = [json.loads(line.split("] ", 1)[1]) for line in result["logs"]]
        physical = [row["physical_frame"] for row in markers if row["stage"] == "cargo-destination-saved"]
        colds = [row["physical_frame"] for row in markers if row["stage"] == "cold"]
        self.assertEqual(len(physical), 1)
        self.assertEqual(colds, [physical[0], physical[0]])

    def test_cargo_partial_missing_flight_identity_conservation_and_timeout_refuse(self):
        for mode, message in [("partial-trips", "one full seven"), ("non-normal", "normal cargo"),
                              ("extra-robot", "exactly one"), ("invented-iron", "iron conservation"),
                              ("lost-iron", "iron conservation"), ("no-flight", "lacks observed"),
                              ("stationary-load", "lacks observed"), ("duplicate-delivery", "iron conservation"),
                              ("changed-request", "request changed"), ("native-research-write", "cargo-native"),
                              ("foreign-frame", "cargo-native"), ("changed-robot", "robot changed"),
                              ("timeout", "timeout"), ("changed-cold-cargo", "iron conservation"),
                              ("changed-cold-position", "cold-cargo")]:
            with self.subTest(mode=mode), self.assertRaisesRegex(Exception, message):
                self.run_case(cargo_mode=mode)
            if mode not in ("changed-cold-cargo", "changed-cold-position"):
                state = self.lua.globals().last_ferrum_storage["mir_ferrum_worker_native"]
                self.assertIsNone(state.cargo.completed)
                self.assertFalse(state.cargo.report.physical_robot_delivery)
                self.assertNotIn("mir-ferrum-worker-cargo-destination", plain(self.lua.globals().last_ferrum_saves))

    def test_cargo_server_exact_phase_single_request_and_F210_binding(self):
        for mode, message in [("player-command", "server-console"), ("wrong-parameter", "server-console"), ("source-phase", "fresh ordinary"),
                              ("duplicate-command", "fresh ordinary")]:
            with self.subTest(mode=mode), self.assertRaisesRegex(Exception, message):
                self.run_case(cargo_mode=mode)
        with self.assertRaisesRegex(Exception, "cargo exact F210"):
            self.run_case(target="f200", cargo_mode="normal")

    def test_cargo_flight_guard_is_a_meaningful_host_only_mutation(self):
        actor = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        guard = '    check(c.report.flight ~= nil and current.provider == 0, "delivery lacks observed seven-item flight")'
        self.assertEqual(actor.count(guard), 1)
        with self.assertRaisesRegex(Exception, "lacks observed"):
            self.run_case(cargo_mode="no-flight")
        mutant = actor.replace(guard, "    -- Deliberate host-only defect: omit loaded-flight provenance.")
        result = self.run_case(actor_override=mutant, cargo_mode="no-flight")
        self.assertTrue(result["report"]["physical_robot_delivery"])
        self.assertNotIn("loaded", result["report"]["cargo"])
        self.assertNotIn("flight", result["report"]["cargo"])
        self.assertFalse(result["native_evidence"])

    def test_source_destination_and_two_readonly_cold_callbacks(self):
        for target in ("f210", "f200"):
            for count in (1518, 1519):
                with self.subTest(target=target, measured_engine_integer=count):
                    result = self.run_case(target=target, native_count=count)
                    self.assertEqual(result["ordinary"], {"worker-robots-storage-4": 1,
                        "worker-robots-storage-5": 1, "worker-robots-storage-6": 1})
                    self.assertEqual(result["saves"], ["mir-ferrum-worker-source", "mir-ferrum-worker-destination"])
                    self.assertEqual([w["units"] for w in result["consumption"]], [675, 1012, count])
                    self.assertTrue(all(w["progress_seen"] for w in result["consumption"]))
                    self.assertTrue(result["cold_readonly"])
                    self.assertFalse(result["native_evidence"])
                    self.assertFalse(result["report"]["physical_robot_delivery"])
                    self.assertTrue(result["administrative"])
                    markers = [json.loads(line.split("] ", 1)[1]) for line in result["logs"]]
                    stages = [row["stage"] for row in markers]
                    self.assertLess(stages.index("level-pre-MIR-configuration"), stages.index("post-MIR-configuration"))
                    self.assertEqual(stages.count("cold"), 2)

    def test_completed_and_advanced_native_infinite_representations(self):
        for target in ("f210", "f200"):
            result = self.run_case("completed-native-form", target)
            self.assertEqual(result["closed"]["player"]["bonus"], 6)
            self.assertTrue(result["closed"]["player"]["rows"]["worker-robots-storage-6"]["researched"])

    def test_runtime_energy_is_ticks_not_raw_seconds(self):
        for target in ("f210", "f200"):
            result = self.run_case(target=target)
            for name in ("worker-robots-storage-4", "worker-robots-storage-5", "worker-robots-storage-6",
                         "mir-worker-storage-preservation-4", "mir-ferrum-count-control-6"):
                self.assertEqual(result["entry"]["player"]["rows"][name]["time"], 3600)
            with self.assertRaisesRegex(Exception, "finite worker contract"):
                self.run_case("raw-seconds-energy", target)

    def test_private_holder_requires_direct_worker2_prerequisite(self):
        for target in ("f210", "f200"):
            with self.subTest(target=target), self.assertRaisesRegex(Exception, "MIR prerequisites"):
                self.run_case("missing-private-worker2", target)
            state = self.lua.globals().last_ferrum_storage["mir_ferrum_worker_native"]
            self.assertIsNone(state.ordinary["worker-robots-storage-6"])
            self.assertTrue(self.lua.globals().last_ferrum_lab.disabled_by_script)
            self.assertEqual(plain(self.lua.globals().last_ferrum_saves), ["mir-ferrum-worker-source"])

    def test_scripted_duplicate_and_unconsumed_lab_completions_refuse(self):
        for target in ("f210", "f200"):
            for opponent, message in (("scripted-completion", "ordinary lab"),
                                      ("duplicate-completion", "duplicate completion"),
                                      ("no-consumption", "science consumption"),
                                      ("no-progress-witness", "ordinary progress")):
                with self.subTest(target=target, opponent=opponent), self.assertRaisesRegex(Exception, message):
                    self.run_case(opponent, target)

    def test_source_and_post_MIR_preservation_defects_refuse(self):
        for opponent in ("lost-source-bonus", "lost-finite-row", "lost-earned-flag", "lost-current-progress", "lost-foreign-progress",
                         "lost-disabled-flag", "wrong-source-science", "post-MIR-foreign", "post-MIR-private"):
            with self.subTest(opponent=opponent):
                with self.assertRaisesRegex(Exception, "frame"):
                    self.run_case(opponent)
                state = self.lua.globals().last_ferrum_storage["mir_ferrum_worker_native"]
                self.assertIsNone(state.ordinary["worker-robots-storage-6"])
                self.assertTrue(self.lua.globals().last_ferrum_lab.disabled_by_script)
                self.assertEqual(plain(self.lua.globals().last_ferrum_saves), ["mir-ferrum-worker-source"])

    def test_contract_version_phase_and_cold_opponents_refuse(self):
        for opponent in ("wrong-engine", "wrong-provider", "wrong-price", "wrong-MIR-version", "previous-MIR11",
            "opposite-edition", "wrong-phase", "wrong-MIR-science", "wrong-formula", "wrong-effect", "wrong-native-count", "dummy-private", "private-foreign-investment",
            "public7-overlap", "calibration-researched", "bad-F210-hidden", "premature-cold", "altered-cold",
            "altered-cold-inventory"):
            with self.subTest(opponent=opponent), self.assertRaises(Exception):
                self.run_case(opponent)
        with self.assertRaisesRegex(Exception, "2.0 effect hidden"):
            self.run_case("bad-F200-hidden", "f200")

    def test_F200_effect_hidden_absence_is_retained(self):
        result = self.run_case(target="f200")
        effect = result["closed"]["player"]["rows"]["worker-robots-storage-6"]["effects"][0]
        self.assertNotIn("hidden", effect)
        self.assertIs(result["closed"]["mir-ferrum-foreign"]["rows"]["worker-robots-storage-4"]["enabled"], False)

    def test_ordinary_event_guard_is_a_meaningful_opponent_control(self):
        actor = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        guard = '  check(event.by_script == false, "completion requires ordinary lab")'
        self.assertEqual(actor.count(guard), 1)
        with self.assertRaisesRegex(Exception, "completion requires ordinary lab"):
            self.run_case("scripted-completion")
        mutant = actor.replace(guard, "  -- Deliberate host-only defect: ordinary provenance guard removed.")
        result = self.run_case("scripted-completion", actor_override=mutant)
        self.assertEqual(result["ordinary"], {"worker-robots-storage-4": 1,
            "worker-robots-storage-5": 1, "worker-robots-storage-6": 1})
        self.assertFalse(result["native_evidence"])

    def test_lab_mod_changes_no_real_technology_and_uses_native_calibration(self):
        self.lua.globals().lab_data_path = (FIXTURE / "lab-source/data.lua").as_posix()
        emitted = plain(self.lua.execute('''
          local function clone(v)if type(v)~="table"then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
          local rows;local env={table={deepcopy=clone},data={raw={lab={lab={name="lab",inputs={"automation-science-pack"}}}},extend=function(_,v)rows=v end}}
          setmetatable(env,{__index=_G});assert(loadfile(lab_data_path,"t",env))();return rows
        '''))
        self.assertEqual(len(emitted), 4)
        self.assertEqual(emitted[0]["researching_speed"], 1001)
        self.assertEqual(emitted[0]["energy_source"], {"type": "void"})
        self.assertNotIn("ferrum-robotics-science-pack", emitted[0]["inputs"])
        self.assertIn("space-science-pack", emitted[0]["inputs"])
        calibration = emitted[-1]
        self.assertEqual(calibration["unit"]["count_formula"], "1518.75")
        self.assertEqual(calibration["unit"]["time"], 60)
        self.assertNotIn("count", calibration["unit"])
        self.assertTrue(calibration["hidden"])
        self.assertFalse(calibration["enabled"])
        self.assertEqual(calibration["effects"], {})
        self.assertTrue(all(not row["name"].startswith("worker-robots-storage") for row in emitted))

    def test_metadata_has_exact_supported_pairs_and_no_runtime_mod_control(self):
        for filename, family, base, ferrum, mir in (("info.json", "2.1", "2.1.23", "0.1.5", "5.0.21012"),
            ("info-f200.json", "2.0", "2.0.77", "0.0.5", "5.0.20012")):
            row = json.loads((FIXTURE / "lab-source" / filename).read_bytes())
            self.assertEqual(row["version"], "0.1.0")
            self.assertEqual(row["factorio_version"], family)
            self.assertEqual(row["dependencies"], [f"base = {base}", f"space-age = {base}",
                f"planet-ferrum = {ferrum}", f"? more-infinite-research = {mir}"])
        self.assertFalse((FIXTURE / "lab-source/control.lua").exists())

    def test_test_owned_icons_match_the_actual_modern_Base_asset(self):
        self.lua.globals().lab_data_path = (FIXTURE / "lab-source/data.lua").as_posix()
        icons = plain(self.lua.execute('''
          local function clone(v)if type(v)~="table"then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
          local rows;local env={table={deepcopy=clone},data={raw={lab={lab={name="lab",inputs={"automation-science-pack"}}}},extend=function(_,v)rows=v end}}
          setmetatable(env,{__index=_G});assert(loadfile(lab_data_path,"t",env))()
          local out={};for _,row in ipairs(rows)do if row.type=="technology"then out[#out+1]={row.icon,row.icon_size}end end;return out
        '''))
        # Independently observed on both pinned read-data trees: automation.png
        # is absent; automation-1.png is the Base256px icon (480x256 mipmap strip).
        self.assertEqual(icons, [["__base__/graphics/technology/automation-1.png", 256]] * 3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)

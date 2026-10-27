"""Host controls for the bounded 3.2.x Vulcanus discovery recovery fixture.

These native-shaped controls prepare inputs only.  They do not establish a
Factorio run, a source save, or that an old 3.2 package emits the discovery
technology under every closure.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "discovery-recovery"
NAME = "mir-fixture-discovery-recovery"
IRON = "recipe-prod-research_iron-1"
GEAR = "recipe-prod-research_gears-1"
DISCOVERY = "planet-discovery-vulcanus"
OFFICIAL = {
    "base": "2.1.23", "space-age": "2.1.23", "quality": "2.1.23",
    "elevated-rails": "2.1.23", "recycler": "2.1.23",
    "mir-fixture-mir5-active-mods-observer": "0.1.0",
}
SOURCE_STAGES = {"source-320": ("3.2.0", "0.1.0"), "source-321": ("3.2.1", "0.1.1")}


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("cyclic Lua value")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (list, tuple)):
        return lua.table_from([lua_value(lua, item) for item in value])
    return value


class DiscoveryRecoveryFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for stage, (mir, version) in SOURCE_STAGES.items():
            info = (FIXTURE / stage / "info.json").read_text(encoding="utf-8")
            cls._assert_info(cls, info, version, mir)
        cls._assert_info(cls, (FIXTURE / "successor" / "info.json").read_text(encoding="utf-8"), "0.2.0", "5.0.21000")

    @staticmethod
    def _assert_info(_self, text, version, mir):
        import json
        value = json.loads(text)
        assert (value["name"], value["version"], value["factorio_version"]) == (NAME, version, "2.1")
        assert f"more-infinite-research = {mir}" in value["dependencies"]
        assert "base = 2.1.23" in value["dependencies"]
        assert "space-age = 2.1.23" in value["dependencies"]

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function discovery_data(data_path, helper_path, stage, mir, fixture_version, discovery_present, opponent)
  local iron={name="recipe-prod-research_iron-1",type="technology",level=1,upgrade=true,max_level="infinite",
    enabled=true,unit={count_formula="8000*2^(L-1)",time=60,ingredients={{"automation-science-pack",1}}},
    effects={{type="change-recipe-productivity",recipe="casting-iron",change=.1},
      {type="change-recipe-productivity",recipe="iron-plate",change=.1}}}
  if opponent=="missing-iron-effect" then table.remove(iron.effects,1) end
  if opponent=="duplicate-iron-effect" then iron.effects[3]={type="change-recipe-productivity",recipe="iron-plate",change=.1} end
  if opponent=="foreign-iron-effect" then iron.effects[1].recipe="foreign-recipe" end
  if opponent=="wrong-iron-effect" then iron.effects[1].change=.2 end
  local gear={name="recipe-prod-research_gears-1",type="technology",level=1,upgrade=true,max_level="infinite",
    enabled=true,unit={count_formula="8000*2^(L-1)",time=60,ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
      {"chemical-science-pack",1},{"production-science-pack",1}}},
    effects={{type="change-recipe-productivity",recipe="casting-iron-gear-wheel",change=.1},
      {type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}}
  if opponent=="missing-gear-effect" then table.remove(gear.effects,1) end
  if opponent=="wrong-gear-effect" then gear.effects[1].recipe="iron-plate" end
  if opponent=="wrong-gear-unit" then gear.unit.time=61 end
  local technologies={[iron.name]=iron,[gear.name]=gear}
  if discovery_present then
    local discovery_effects={{type="unlock-travel-to-space-platforms",modifier=true}}
    if mir=="3.2.1" then
      discovery_effects={{type="unlock-space-location",space_location="vulcanus",use_icon_overlay_constant=true},
        {type="unlock-travel-to-space-platforms",modifier=true}}
    end
    technologies["planet-discovery-vulcanus"]={name="planet-discovery-vulcanus",type="technology",
      unit={count=1000,time=60,ingredients={{"automation-science-pack",1}}},effects=discovery_effects}
  end
  if opponent=="wrong-discovery-effect" then
    technologies["planet-discovery-vulcanus"].effects={{type="unlock-space-location",space_location="vulcanus"}}
  end
  if opponent=="absent-discovery-overlay" then technologies["planet-discovery-vulcanus"].effects[1].use_icon_overlay_constant=nil end
  if opponent=="missing-discovery-unlock" then table.remove(technologies["planet-discovery-vulcanus"].effects,1) end
  if opponent=="wrong-discovery-unlock" then technologies["planet-discovery-vulcanus"].effects[1].space_location="nauvis" end
  local mods={base="2.1.23",["space-age"]="2.1.23",quality="2.1.23",["elevated-rails"]="2.1.23",recycler="2.1.23",
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["more-infinite-research"]=mir,
    ["mir-fixture-discovery-recovery"]=fixture_version}
  if opponent=="wrong-closure" then mods.base="2.1.22" end
  if opponent=="extra-mod" then mods["unrelated-mod"]="1.0.0" end
  local env={mods=mods,data={raw={technology=technologies}}}
  env.require=function(name)
    assert(name=="__mir-fixture-discovery-recovery__/fixture_data_final")
    return assert(loadfile(helper_path,"t",env))()
  end
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key] end})
  local ok,message=pcall(assert(loadfile(data_path,"t",env)))
  return {ok=ok,message=tostring(message),iron=iron,gear=gear,discovery=technologies["planet-discovery-vulcanus"]}
end

function discovery_parse(wrapper_path, helper_path, stage, source_mir, source_fixture)
  local callbacks,reads={events={}},{game=0,storage=0,settings=0}
  local versions={source=source_mir,successor="5.0.21000"};local fixture_versions={source=source_fixture,successor="0.2.0"}
  local active={base="2.1.23",["space-age"]="2.1.23",quality="2.1.23",["elevated-rails"]="2.1.23",recycler="2.1.23",
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["more-infinite-research"]=versions[stage],
    ["mir-fixture-discovery-recovery"]=fixture_versions[stage]}
  local env={script={active_mods=active,on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
      on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
  env.require=function(name)
    assert(name=="__mir-fixture-discovery-recovery__/fixture_control")
    return assert(loadfile(helper_path,"t",env))()
  end
  env._G=env;setmetatable(env,{__index=function(_,key)
    if key=="game" or key=="storage" or key=="settings" then reads[key]=reads[key]+1 end
    return _G[key]
  end})
  local ok,message=pcall(assert(loadfile(wrapper_path,"t",env)))
  if not ok then return {ok=false,message=tostring(message),callbacks=callbacks,reads=reads} end
  local load_ok,load_message=pcall(callbacks.load)
  return {ok=load_ok,message=tostring(load_message),callbacks=callbacks,reads=reads}
end

function discovery_flow(helper_path, source_path, successor_path, source_mir, source_fixture, opponent)
  local callbacks,markers,saves={events={}}, {}, 0
  local player_iron_queue_assignments=0
  local function tech(name, force, effects, prerequisites, level, ingredients)
    return {name=name,valid=true,force=force,level=level or 1,researched=false,enabled=true,saved_progress=0,
      prototype={effects=effects,max_level=4294967295},prerequisites=prerequisites or {},
      research_unit_ingredients=ingredients or {{name="automation-science-pack",amount=1}}}
  end
  local function force(name,index)
    local queue={}
    local value={name=name,index=index,valid=true,technologies={},recipes={['iron-plate']={valid=true,productivity_bonus=0},
      ['iron-gear-wheel']={valid=true,productivity_bonus=0}}, research_progress=0,locations={vulcanus=false}}
    local prerequisite=tech("fixture-direct-prerequisite",value,{}, {})
    value.technologies[prerequisite.name]=prerequisite
    local discovery_effects={{type='unlock-travel-to-space-platforms',modifier=true}}
    if source_mir=='3.2.1' then
      discovery_effects={{type='unlock-space-location',space_location='vulcanus',use_icon_overlay_constant=true},
        {type='unlock-travel-to-space-platforms',modifier=true}}
    end
    value.technologies['planet-discovery-vulcanus']=tech('planet-discovery-vulcanus',value,discovery_effects,{prerequisite})
    value.technologies['recipe-prod-research_iron-1']=tech('recipe-prod-research_iron-1',value,
      {{type='change-recipe-productivity',recipe='casting-iron',change=.1},
       {type='change-recipe-productivity',recipe='iron-plate',change=.1}},{prerequisite})
    local gear_level=opponent=='nondefault-gear-initial' and name=='player' and 3 or 1
    value.technologies['recipe-prod-research_gears-1']=tech('recipe-prod-research_gears-1',value,
      {{type='change-recipe-productivity',recipe='casting-iron-gear-wheel',change=.1},
       {type='change-recipe-productivity',recipe='iron-gear-wheel',change=.1}},{prerequisite},gear_level,
      {{name='automation-science-pack',amount=1},{name='logistic-science-pack',amount=1},
       {name='chemical-science-pack',amount=1},{name='production-science-pack',amount=1}})
    function value.is_space_location_unlocked(location) return value.locations[location] end
    function value.lock_space_location(location) value.locations[location]=false end
    function value.reset_technology_effects()
      value.recipes['iron-plate'].productivity_bonus=(value.technologies['recipe-prod-research_iron-1'].level-1)*.1
      value.recipes['iron-gear-wheel'].productivity_bonus=(value.technologies['recipe-prod-research_gears-1'].level-1)*.1
    end
    function value.add_research(research)
      if research==nil or value.current_research~=nil then return false end
      value.research_queue={research};return value.current_research==research
    end
    setmetatable(value,{__index=function(table,key)
      if key=='research_queue' then return queue end
      return rawget(table,key)
    end,__newindex=function(table,key,items)
      if key~='research_queue' then rawset(table,key,items);return end
      local restored={}
      for _, item in ipairs(items or {}) do
        local technology=type(item)=='string' and table.technologies[item] or item
        if technology~=nil then restored[#restored+1]=technology end
      end
      if table.name=='player' and #restored==1 and restored[1].name=='recipe-prod-research_iron-1' then
        player_iron_queue_assignments=player_iron_queue_assignments+1
        if opponent=='queue-restore-drop' and player_iron_queue_assignments==2 then restored={} end
      end
      queue=restored;rawset(table,'current_research',queue[1]);rawset(table,'research_progress',0)
    end})
    return value
  end
  local player=force('player',1);local game={tick=0,forces={player=player,[1]=player},lab_count=0}
  function game.create_force(name)
    local foreign=force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign
  end
  local surface={}
  function surface.create_entity(spec)
    game.lab_count=game.lab_count+1
    local inventory={items={}}
    function inventory.clear() inventory.items={} end
    function inventory.insert(item) inventory.items[item.name]=(inventory.items[item.name] or 0)+item.count;return item.count end
    function inventory.get_item_count(name) return inventory.items[name] or 0 end
    local entity={valid=true,energy=0,inventory=inventory}
    function entity.get_inventory(kind) assert(kind==1);return inventory end
    return entity
  end
  game.surfaces={[1]=surface}
  function game.server_save(name) assert(name=='mir5-native-complete');saves=saves+1 end
  local storage={}
  local startup={['ips-enable-research_iron']={value=true},['ips-cost-base-research_iron']={value=8000},
    ['ips-cost-growth-research_iron']={value=2},['ips-max-level-research_iron']={value=0},
    ['ips-research-time-research_iron']={value=60},['ips-effect-per-level-research_iron']={value=10},
    ['ips-require-space-gate']={value=false},['mir-science-pack-ingredient-policy']={value='configured'},
    ['mir-lab-incompatibility-policy']={value='reduce'}}
  local active={base='2.1.23',['space-age']='2.1.23',quality='2.1.23',['elevated-rails']='2.1.23',recycler='2.1.23',
    ['mir-fixture-mir5-active-mods-observer']='0.1.0',['more-infinite-research']=source_mir,
    ['mir-fixture-discovery-recovery']=source_fixture}
  local function load_control(path, stage)
    callbacks={events={}}
    if stage=='successor' then active['more-infinite-research']='5.0.21000';active['mir-fixture-discovery-recovery']='0.2.0' end
    local env={game=game,storage=storage,settings={startup=startup},script={active_mods=active,on_init=function(f)callbacks.init=f end,
        on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,
        on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
      helpers={table_to_json=function(row) markers[#markers+1]=row;return '{}' end},log=function(value) assert(value:match('^%[MIR5_NATIVE_FIXTURE%] RESULT ')) end}
    env.require=function(name)
      assert(name=='__mir-fixture-discovery-recovery__/fixture_control')
      return assert(loadfile(helper_path,'t',env))()
    end
    env._G=env;setmetatable(env,{__index=function(_,key)return _G[key] end})
    local ok,message=pcall(assert(loadfile(path,'t',env)))
    if not ok then return nil,tostring(message) end
    return callbacks,nil
  end
  local function invoke(name, ...)
    local callback=name=='tick' and callbacks.events[1] or name=='research' and callbacks.events[2] or callbacks[name]
    if type(callback)~='function' then return false,'missing '..name end
    local ok,message=pcall(callback,...);return ok,tostring(message)
  end
  local function tick() game.tick=game.tick+1;return invoke('tick') end
  local source,message=load_control(source_path,'source');if source==nil then return {ok=false,message=message} end
  if opponent=='missing-source-definition' then player.technologies['planet-discovery-vulcanus']=nil end
  if opponent=='bad-source-setting' then startup['ips-effect-per-level-research_iron'].value=9 end
  local source_effects=player.technologies['recipe-prod-research_iron-1'].prototype.effects
  if opponent=='runtime-missing-iron-effect' then table.remove(source_effects,1) end
  if opponent=='runtime-duplicate-iron-effect' then source_effects[3]={type='change-recipe-productivity',recipe='iron-plate',change=.1} end
  if opponent=='runtime-foreign-iron-effect' then source_effects[1].recipe='foreign-recipe' end
  if opponent=='runtime-wrong-iron-effect' then source_effects[1].change=.2 end
  local ok,result=invoke('init');if not ok then return {ok=false,message=result,labs=game.lab_count,state=storage.mir5_discovery_recovery_fixture or {}} end
  local source_create_saves=saves
  if opponent=='source-create-save' and saves~=0 then return {ok=false,message='create-only was saved'} end
  -- Factorio calls on_load when this server begins, before the first native
  -- completion.  A later normal tick must not mislabel that initial load as
  -- a reload of the completed save.
  ok,result=invoke('load');if not ok then return {ok=false,message=result} end
  local discovery=player.technologies['planet-discovery-vulcanus'];discovery.researched=true
  player.locations.vulcanus=source_mir=='3.2.1'
  if opponent=='source-unlocked-after-lab' then player.locations.vulcanus=true end
  if opponent=='source-locked-after-lab' then player.locations.vulcanus=false end
  player.current_research=nil;player.research_queue={};player.research_progress=0
  local source_scripted=opponent=='source-scripted-event'
  ok,result=invoke('research',{research=discovery,by_script=source_scripted});if not ok then return {ok=false,message=result} end
  if source_scripted then
    ok,result=tick();if not ok then return {ok=false,message=result} end
    local state=storage.mir5_discovery_recovery_fixture
    return {ok=true,scripted_ignored=state.source_actual_labs==0 and state.phase=='await-source-discovery',
      source_actual_labs=state.source_actual_labs,phase=state.phase,saves=saves,labs=game.lab_count}
  end
  for name in pairs(storage.mir5_discovery_recovery_fixture.source_packs) do storage.mir5_discovery_recovery_fixture.lab.inventory.items[name]=0 end
  if opponent=='nonzero-saved-progress' or opponent=='saved-progress-loss' then
    player.technologies['recipe-prod-research_iron-1'].saved_progress=.17
  end
  ok,result=tick();if not ok then return {ok=false,message=result} end
  local source_initial_markers=#markers
  ok,result=tick();if not ok then return {ok=false,message=result} end
  if #markers~=source_initial_markers then return {ok=false,message='source ordinary tick emitted reload marker'} end
  local source_phase=storage.mir5_discovery_recovery_fixture.phase
  for ordinal=1,2 do
    local source_reload,error=load_control(source_path,'source');if source_reload==nil then return {ok=false,message=error} end
    ok,result=invoke('load');if not ok then return {ok=false,message=result} end
    ok,result=tick();if not ok then return {ok=false,message=result} end
    if storage.mir5_discovery_recovery_fixture.phase~=source_phase then return {ok=false,message='source cold reload wrote phase'} end
    local source_reload_markers=#markers
    ok,result=tick();if not ok then return {ok=false,message=result} end
    if #markers~=source_reload_markers then return {ok=false,message='source cold reload emitted more than one marker'} end
  end
  if opponent=='absent-state' then storage.mir5_discovery_recovery_fixture=nil end
  if opponent=='missing-repair' then
    player.locations.vulcanus=false
  elseif source_mir=='3.2.0' then
    -- The old 3.2.0 effect vector leaves the location locked; only this
    -- branch models ordinary candidate recovery before successor init.
    player.locations.vulcanus=true
  end
  if opponent=='queue-diagnostic' then
    player.current_research=player.technologies['planet-discovery-vulcanus']
    player.research_queue={player.technologies['planet-discovery-vulcanus']}
    player.research_progress=.41
  end
  if opponent=='bad-source' then storage.mir5_discovery_recovery_fixture.player.iron.bonus=.1 end
  if opponent=='foreign-unlocked' then game.forces[2].locations.vulcanus=true end
  if opponent=='saved-progress-loss' then player.technologies['recipe-prod-research_iron-1'].saved_progress=.18 end
  if opponent=='runtime-missing-gear-effect' then
    table.remove(player.technologies['recipe-prod-research_gears-1'].prototype.effects,1)
  end
  local before_labs=game.lab_count
  local successor;successor,message=load_control(successor_path,'successor');if successor==nil then return {ok=false,message=message} end
  ok,result=invoke('load');if not ok then return {ok=false,message=result} end
  ok,result=invoke('changed');if not ok then return {ok=false,message=result,labs=game.lab_count,before_labs=before_labs,markers=markers,state=storage.mir5_discovery_recovery_fixture or {},
    player_current=player.current_research and player.current_research.name or false,player_queue=(function() local out={} for index,value in ipairs(player.research_queue) do out[index]=value.name end return out end)(),player_progress=player.research_progress} end
  local gear=player.technologies['recipe-prod-research_gears-1'];gear.level=gear.level+1;player.current_research=nil;player.research_queue={};player.research_progress=0;player.reset_technology_effects()
  if opponent~='candidate-no-consumption' then
    for name in pairs(storage.mir5_discovery_recovery_fixture.successor.packs) do
      storage.mir5_discovery_recovery_fixture.successor.lab.inventory.items[name]=0
    end
  end
  if opponent=='relock-during-lab' then player.locations.vulcanus=false end
  local successor_scripted=opponent=='successor-scripted-event'
  ok,result=invoke('research',{research=gear,by_script=successor_scripted});if not ok then return {ok=false,message=result,labs=game.lab_count,before_labs=before_labs,state=storage.mir5_discovery_recovery_fixture or {}} end
  if successor_scripted then
    ok,result=tick();if not ok then return {ok=false,message=result} end
    local state=storage.mir5_discovery_recovery_fixture
    return {ok=true,scripted_ignored=state.successor.actual_labs==0 and state.successor.phase=='await-successor-gear',
      successor_actual_labs=state.successor.actual_labs,phase=state.successor.phase,saves=saves,labs=game.lab_count}
  end
  ok,result=tick();if not ok then return {ok=false,message=result,saves=saves,markers=markers,state=storage.mir5_discovery_recovery_fixture or {}} end
  local final=storage.mir5_discovery_recovery_fixture
  local successor_initial_markers=#markers
  ok,result=tick();if not ok then return {ok=false,message=result} end
  if #markers~=successor_initial_markers then return {ok=false,message='successor ordinary tick emitted reload marker'} end
  for ordinal=1,2 do
    local reload,error=load_control(successor_path,'successor');if reload==nil then return {ok=false,message=error} end
    ok,result=invoke('load');if not ok then return {ok=false,message=result} end
    ok,result=tick();if not ok then return {ok=false,message=result} end
    local successor_reload_markers=#markers
    ok,result=tick();if not ok then return {ok=false,message=result} end
    if #markers~=successor_reload_markers then return {ok=false,message='successor cold reload emitted more than one marker'} end
  end
  return {ok=true,saves=saves,source_create_saves=source_create_saves,markers=markers,labs=game.lab_count,state=final,player_bonus=player.recipes['iron-plate'].productivity_bonus,
    gear_bonus=player.recipes['iron-gear-wheel'].productivity_bonus,player_current=player.current_research and player.current_research.name or false,
    player_progress=player.research_progress,foreign_locked=not game.forces[2].locations.vulcanus,foreign_progress=game.forces[2].research_progress}
end
''')

    def data_result(self, stage, *, discovery_present=True, opponent=""):
        if stage == "successor":
            mir, version = "5.0.21000", "0.2.0"
        else:
            mir, version = SOURCE_STAGES[stage]
        return plain(self.lua.eval("discovery_data")(
            str(FIXTURE / stage / "data-final-fixes.lua"), str(FIXTURE / "fixture_data_final.lua"),
            "successor" if stage == "successor" else "source", mir, version, discovery_present, opponent,
        ))

    def flow_result(self, opponent="", source_stage="source-321"):
        source_mir, source_fixture = SOURCE_STAGES[source_stage]
        return plain(self.lua.eval("discovery_flow")(
            str(FIXTURE / "fixture_control.lua"), str(FIXTURE / source_stage / "control.lua"),
            str(FIXTURE / "successor" / "control.lua"), source_mir, source_fixture, opponent,
        ))

    def test_data_preflight_requires_the_emitted_historical_rows_before_only_count_time_change(self):
        for stage in (*SOURCE_STAGES, "successor"):
            with self.subTest(stage=stage):
                result = self.data_result(stage)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((None, "8000*2^(L-1)", 60),
                                 (result["iron"]["unit"].get("count"), result["iron"]["unit"].get("count_formula"),
                                  result["iron"]["unit"]["time"]))
                if stage == "successor":
                    self.assertEqual((1, 5), (result["gear"]["unit"].get("count"), result["gear"]["unit"]["time"]))
                    self.assertIsNone(result["gear"]["unit"].get("count_formula"))
                else:
                    self.assertEqual((None, "8000*2^(L-1)", 60),
                                     (result["gear"]["unit"].get("count"), result["gear"]["unit"].get("count_formula"),
                                      result["gear"]["unit"]["time"]))
                if stage == "source-320":
                    self.assertEqual((1, 1), (result["discovery"]["unit"].get("count"), result["discovery"]["unit"]["time"]))
                    self.assertEqual(
                        [{"type": "unlock-travel-to-space-platforms", "modifier": True}],
                        result["discovery"]["effects"],
                    )
                elif stage == "source-321":
                    self.assertEqual((1, 1), (result["discovery"]["unit"].get("count"), result["discovery"]["unit"]["time"]))
                    self.assertEqual(
                        [{"type": "unlock-space-location", "space_location": "vulcanus", "use_icon_overlay_constant": True},
                         {"type": "unlock-travel-to-space-platforms", "modifier": True}],
                        result["discovery"]["effects"],
                    )
        missing = self.data_result("source-320", discovery_present=False)
        self.assertFalse(missing["ok"])
        self.assertIn("source Vulcanus discovery technology is absent", missing["message"])
        absent_overlay = self.data_result("source-321", opponent="absent-discovery-overlay")
        self.assertTrue(absent_overlay["ok"], absent_overlay["message"])
        self.assertNotIn("use_icon_overlay_constant", absent_overlay["discovery"]["effects"][0])
        for opponent, phrase, stage in (("wrong-iron-effect", "historical Space Age iron productivity effect differs", "source-321"),
                                        ("missing-iron-effect", "historical Space Age iron productivity effect differs", "source-321"),
                                        ("duplicate-iron-effect", "historical Space Age iron productivity effect differs", "source-321"),
                                        ("foreign-iron-effect", "historical Space Age iron productivity effect differs", "source-321"),
                                        ("missing-gear-effect", "current gear productivity effect differs", "successor"),
                                        ("wrong-gear-effect", "current gear productivity effect differs", "successor"),
                                        ("wrong-gear-unit", "current gear unit differs", "successor"),
                                        ("wrong-discovery-effect", "source Vulcanus discovery effect differs", "source-321"),
                                        ("missing-discovery-unlock", "source Vulcanus discovery effect differs", "source-321"),
                                        ("wrong-discovery-unlock", "source Vulcanus discovery effect differs", "source-321"),
                                        ("wrong-closure", "official Space Age closure differs", "source-321"),
                                        ("extra-mod", "unexpected active mod in fixture closure", "source-321")):
            with self.subTest(opponent=opponent, stage=stage):
                result = self.data_result(stage, opponent=opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])

    def test_fixture_preserves_iron_queue_and_runs_one_successor_gear_lab_with_foreign_lock_preserved(self):
        for source_stage, (source_version, _) in SOURCE_STAGES.items():
            with self.subTest(source_stage=source_stage):
                result = self.flow_result(source_stage=source_stage)
                self.assertTrue(result["ok"], result.get("message"))
                self.assertEqual(0, result["source_create_saves"])
                self.assertEqual(2, result["saves"])
                self.assertEqual(2, result["labs"])
                self.assertAlmostEqual(.2, result["player_bonus"])
                self.assertAlmostEqual(.1, result["gear_bonus"])
                self.assertEqual(IRON, result["player_current"])
                self.assertAlmostEqual(.42, result["player_progress"])
                self.assertTrue(result["foreign_locked"])
                self.assertEqual(.27, result["foreign_progress"])
                self.assertEqual(["initial", "reload", "reload", "initial", "reload", "reload"], [row["stage"] for row in result["markers"]])
                self.assertEqual(["discovery-recovery"] * 6, [row["case"] for row in result["markers"]])
                self.assertEqual(["source"] * 3 + ["successor"] * 3,
                                 [row["fixture_role"] for row in result["markers"]])
                self.assertEqual([source_version] * 6, [row["source_version"] for row in result["markers"]])
                self.assertEqual((1, 1), (result["markers"][0]["source_actual_labs"], result["markers"][3]["successor_actual_labs"]))
                self.assertEqual(3, result["markers"][0]["source_scripted_iron_level"])
                self.assertAlmostEqual(.2, result["markers"][0]["source_scripted_iron_plate_bonus"])
                self.assertEqual(IRON, result["markers"][3]["player_iron_queue_current"])
                self.assertAlmostEqual(.42, result["markers"][3]["player_iron_queue_progress"])
                self.assertEqual(result["markers"][3]["successor_gear_level_before"] + 1,
                                 result["markers"][3]["successor_gear_level_after"])
                self.assertAlmostEqual(result["markers"][3]["successor_gear_bonus_before"] +
                                       result["markers"][3]["successor_gear_native_effect"],
                                       result["markers"][3]["successor_gear_bonus_after"])
                source_unlocked = source_version == "3.2.1"
                self.assertEqual(not source_unlocked, result["markers"][0]["source_vulcanus_native_locked_after_discovery"])
                self.assertEqual(source_unlocked, result["markers"][0]["player_vulcanus_unlocked"])
                self.assertTrue(all(row["player_vulcanus_unlocked"] for row in result["markers"][3:]))
                self.assertTrue(all(row["foreign_vulcanus_unresearched_locked"] for row in result["markers"]))

    def test_only_non_scripted_research_events_can_complete_fixture_labs(self):
        for source_stage in SOURCE_STAGES:
            with self.subTest(source_stage=source_stage, phase="source"):
                result = self.flow_result("source-scripted-event", source_stage)
                self.assertTrue(result["ok"], result.get("message"))
                self.assertTrue(result["scripted_ignored"])
                self.assertEqual((0, "await-source-discovery", 0),
                                 (result["source_actual_labs"], result["phase"], result["saves"]))
            with self.subTest(source_stage=source_stage, phase="successor"):
                result = self.flow_result("successor-scripted-event", source_stage)
                self.assertTrue(result["ok"], result.get("message"))
                self.assertTrue(result["scripted_ignored"])
                self.assertEqual((0, "await-successor-gear", 1),
                                 (result["successor_actual_labs"], result["phase"], result["saves"]))

    def test_successor_requires_consumed_science_and_retained_discovery_after_lab(self):
        for opponent, phrase in (("candidate-no-consumption", "successor gear lab did not consume"),
                                  ("relock-during-lab", "successor Vulcanus discovery was not retained after candidate lab")):
            with self.subTest(opponent=opponent):
                result = self.flow_result(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                if opponent == "candidate-no-consumption":
                    self.assertEqual(0, result["state"]["successor"]["actual_labs"])

    def test_nonzero_source_saved_progress_is_captured_and_must_survive_successor_preflight(self):
        result = self.flow_result("nonzero-saved-progress")
        self.assertTrue(result["ok"], result.get("message"))
        self.assertAlmostEqual(.17, result["state"]["player"]["iron"]["saved_progress"])
        lost = self.flow_result("saved-progress-loss")
        self.assertFalse(lost["ok"])
        self.assertIn("protected iron state differs", lost["message"])

    def test_successor_refuses_missing_repair_or_protected_state_before_candidate_lab_or_storage_write(self):
        for opponent, phrase, source_stage in (("missing-repair", "MIR discovery repair did not restore researched Vulcanus", "source-320"),
                                                ("absent-state", "protected 3.2.x source state is absent", "source-321"),
                                                ("bad-source", "protected iron state differs", "source-321"),
                                                ("foreign-unlocked", "unresearched foreign Vulcanus state differs", "source-321"),
                                                ("runtime-missing-gear-effect", "successor player gear effect differs", "source-321")):
            with self.subTest(opponent=opponent, source_stage=source_stage):
                result = self.flow_result(opponent, source_stage)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertEqual(result["before_labs"], result["labs"])
                self.assertNotIn("successor", result["state"])

    def test_successor_queue_refusal_reports_read_only_state_before_lab_storage_or_success_marker(self):
        result = self.flow_result("queue-diagnostic", "source-320")
        self.assertFalse(result["ok"])
        self.assertIn("successor player protected queue/progress differs;", result["message"])
        for detail in ("expected-current=recipe-prod-research_iron-1",
                       "actual-current=planet-discovery-vulcanus",
                       "expected-queue-ids=recipe-prod-research_iron-1",
                       "actual-queue-ids=planet-discovery-vulcanus",
                       "expected-queue-length=1", "actual-queue-length=1",
                       "expected-progress=0.42", "actual-progress=0.41",
                       "vulcanus-unlocked=true"):
            with self.subTest(detail=detail):
                self.assertIn(detail, result["message"])
        self.assertEqual(result["before_labs"], result["labs"])
        self.assertNotIn("successor", result["state"])
        self.assertTrue(all(row["fixture_role"] == "source" for row in result["markers"]))

    def test_gear_preflight_refuses_before_pausing_iron_or_writing_successor_state(self):
        result = self.flow_result("runtime-missing-gear-effect", "source-321")
        self.assertFalse(result["ok"])
        self.assertIn("successor player gear effect differs", result["message"])
        self.assertEqual(result["before_labs"], result["labs"])
        self.assertEqual(IRON, result["player_current"])
        self.assertEqual([IRON], result["player_queue"])
        self.assertAlmostEqual(.42, result["player_progress"])
        self.assertNotIn("successor", result["state"])

    def test_fixture_queue_restore_is_read_back_and_nondefault_gear_baseline_is_observed(self):
        observed = self.flow_result("nondefault-gear-initial", "source-321")
        self.assertTrue(observed["ok"], observed.get("message"))
        self.assertEqual(3, observed["state"]["successor"]["gear_before"]["level"])
        self.assertEqual(4, observed["state"]["successor"]["gear_after"]["level"])
        self.assertEqual(IRON, observed["player_current"])
        self.assertAlmostEqual(.42, observed["player_progress"])
        restored = self.flow_result("queue-restore-drop", "source-321")
        self.assertFalse(restored["ok"])
        self.assertIn("restored player iron queue/progress differs", restored["message"])
        self.assertEqual(1, restored["saves"])
        self.assertTrue(all(row["fixture_role"] == "source" for row in restored["markers"]))

    def test_source_definition_refuses_before_seed_storage_or_lab_mutation(self):
        for opponent, phrase in (("missing-source-definition", "source player technology is absent: planet-discovery-vulcanus"),
                                  ("bad-source-setting", "historical source default differs: ips-effect-per-level-research_iron"),
                                  ("runtime-missing-iron-effect", "source player Space Age iron effect differs"),
                                  ("runtime-duplicate-iron-effect", "source player Space Age iron effect differs"),
                                  ("runtime-foreign-iron-effect", "source player Space Age iron effect differs"),
                                  ("runtime-wrong-iron-effect", "source player Space Age iron effect differs")):
            with self.subTest(opponent=opponent):
                result = self.flow_result(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertEqual(0, result["labs"])
                self.assertEqual({}, result["state"])

    def test_source_refuses_a_location_state_other_than_its_version_oracle_after_the_real_discovery_lab(self):
        for source_stage, opponent in (("source-320", "source-unlocked-after-lab"),
                                       ("source-321", "source-locked-after-lab")):
            with self.subTest(source_stage=source_stage, opponent=opponent):
                result = self.flow_result(opponent, source_stage)
                self.assertFalse(result["ok"])
                self.assertIn("actual source Vulcanus discovery result differs", result["message"])

    def test_wrappers_share_one_fixture_identity_register_handlers_without_runtime_access_and_load_is_read_only(self):
        wrappers = [("source", FIXTURE / source_stage / "control.lua", source_mir, source_fixture)
                    for source_stage, (source_mir, source_fixture) in SOURCE_STAGES.items()]
        wrappers.append(("successor", FIXTURE / "successor" / "control.lua", None, None))
        for stage, path, source_mir, source_fixture in wrappers:
            with self.subTest(stage=path.parent.name):
                result = plain(self.lua.eval("discovery_parse")(str(path), str(FIXTURE / "fixture_control.lua"), stage,
                                                                source_mir, source_fixture))
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({"game": 0, "storage": 0, "settings": 0}, result["reads"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertEqual(2, len(result["callbacks"]["events"]))
        body = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        on_load = body.split("script.on_load(function()", 1)[1].split("script.on_event", 1)[0]
        self.assertNotRegex(on_load, r"\bgame\.")
        self.assertNotRegex(on_load, r"storage\s*\[")
        self.assertNotIn("server_save", on_load)
        self.assertNotIn("unlock_space_location", body)
        self.assertNotIn("lock_space_location", body)
        self.assertNotIn("research_all", body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(DiscoveryRecoveryFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

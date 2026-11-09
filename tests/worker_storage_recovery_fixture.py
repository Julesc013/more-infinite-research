"""Named modern native-fact doubles; these are not engine observations."""

from copy import deepcopy
import json
from pathlib import Path


def expected_private_worker_row(inactive_science=None, space_age=False):
    """Private identity over the frozen published Base work contract."""
    inventory = json.loads((Path(__file__).resolve().parents[1] / "spec/inventory/modern-f200-470.json").read_text())
    base = next(profile for profile in inventory["profiles"] if profile["id"] == "base-f200")
    row = deepcopy(next(entry["row"] for entry in base["published_output"]["data"]["additions"]
                        if entry["name"] == "worker-robots-storage-4"))
    row.update(name="mir-worker-storage-preservation-4", hidden=True, enabled=False,
               visible_when_disabled=False, order="zz[mir-worker-storage-preservation]")
    if space_age:
        row["prerequisites"].append("electromagnetic-science-pack")
        row["unit"]["ingredients"].append(["electromagnetic-science-pack", 1])
    if inactive_science:
        row["prerequisites"] = {}
        row["unit"] = {"count": 1, "time": 1, "ingredients": [[inactive_science, 1]]}
    return row

MINIMAL_NATIVE_FACTS = r'''
function install_worker_recovery_facts(worlds)
  local ID="mir-worker-storage-preservation-4"
  prototypes=prototypes or {};prototypes.technology=prototypes.technology or {}
  prototypes.technology[ID]=prototypes.technology[ID] or {name=ID,level=4,max_level=4294967295,enabled=false,hidden=true,
    effects={{type="worker-robot-storage",modifier=1,hidden=false}},ignore_tech_cost_multiplier=false,
    research_unit_count_formula="100*2^(L-4)",
    research_unit_energy=1800,research_unit_ingredients={{name="automation-science-pack",amount=1}},prerequisites={}}
  if not prototypes._worker_recovery_history then
    local previous=prototypes.get_history
    prototypes.get_history=function(kind,name)
      if kind=="technology" and name==ID then return {created="more-infinite-research"} end
      return previous and previous(kind,name) or {created="base"}
    end
    prototypes._worker_recovery_history=true
  end
  game=game or {}
  if rawget(game,"forces")==nil then rawset(game,"forces",worlds or {}) end
  for _,force in pairs(worlds or rawget(game,"forces") or {})do
    force.technologies=force.technologies or {}
    force.technologies[ID]=force.technologies[ID] or {name=ID,level=4,researched=false,enabled=false,
      visible_when_disabled=false,saved_progress=0,prototype=prototypes.technology[ID],force=force}
  end
end
'''

RECOVERY_WORLD = r'''
ID="mir-worker-storage-preservation-4";CANONICAL="worker-robots-storage-4";OTHER="unrelated"
storage={};writes=0;messages={};creators={[ID]="more-infinite-research",[CANONICAL]="more-infinite-research"}
script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21011"}}
local function prototype(name)
 return {name=name,level=4,max_level=4294967295,enabled=name~=ID,hidden=name==ID,
   effects={{type="worker-robot-storage",modifier=1,hidden=false}},ignore_tech_cost_multiplier=false,
   research_unit_count_formula="100*2^(L-4)",
   research_unit_energy=1800,research_unit_ingredients={{name="automation-science-pack",amount=1}},
   prerequisites={foundation={name="foundation"}}}
end
prototypes={technology={[ID]=prototype(ID),[CANONICAL]=prototype(CANONICAL)},
 get_history=function(kind,name)assert(kind=="technology");return {created=creators[name] or "provider"}end}
function make_force(name,index)
 local values={name=name,index=index,valid=true,queue={},progress=0,bonus=3,technologies={}}
 local force
 local function tech(name,proto)
  local t={name=name,level=4,researched=false,enabled=name~=ID,visible_when_disabled=false,saved_progress=0,
    prototype=proto,prerequisites={foundation={researched=true}}}
  local function earned()return (t.level-4+(t.researched and 1 or 0))*(proto.effects[1].modifier)end
  return setmetatable({}, {__index=function(_,key)
   if key=="force"then return force end
   if key=="research_unit_count"then return math.floor(100*2^(t.level-4))end
   return t[key]
  end,__newindex=function(_,key,value)
   writes=writes+1
   if key=="level"then local before=earned();t.level=value;t.researched=false;t.enabled=true;t.saved_progress=0;values.bonus=values.bonus+earned()-before
   elseif key=="researched"then local before=earned();t.researched=value;values.bonus=values.bonus+earned()-before
   else t[key]=value end
  end})
 end
 force=setmetatable({}, {__index=function(_,key)
  if key=="research_queue"then return values.queue end
  if key=="current_research"then return values.queue[1]end
  if key=="research_progress"then return values.progress end
  if key=="worker_robots_storage_bonus"then return values.bonus end
  return values[key]
 end,__newindex=function(_,key,value)
  if key=="worker_robots_storage_bonus"then error("direct aggregate write")end
  writes=writes+1
  if key=="research_queue"then
   if values.queue[1]then values.queue[1].saved_progress=values.progress end
   local out={}
   for _,id in ipairs(value)do local v=values.technologies[type(id)=="string"and id or id.name];if v and v.enabled then out[#out+1]=v end end
   values.queue=out;values.progress=out[1]and out[1].saved_progress or 0
   if out[1]then out[1].saved_progress=0 end
  elseif key=="research_progress"then values.progress=value
  else values[key]=value end
 end})
 values.technologies[CANONICAL]=tech(CANONICAL,prototypes.technology[CANONICAL])
 values.technologies[ID]=tech(ID,prototypes.technology[ID])
 values.technologies[OTHER]={name=OTHER,level=1,researched=false,enabled=true,visible_when_disabled=false,
   saved_progress=0,prerequisites={},force=force}
 values.reset_technology_effects=function()error("foreign aggregate reset")end
 return force
end
player=make_force("player",1);uninvested=make_force("uninvested",2);suspended=make_force("suspended",3)
game={forces={player=player,uninvested=uninvested,suspended=suspended},get_player=function()return nil end}
log=function(text)messages[#messages+1]=text end
function seed()
 player.technologies[CANONICAL].level=8
 player.research_queue={CANONICAL,OTHER};player.research_progress=.375
 uninvested.technologies[CANONICAL].enabled=false
 uninvested.research_queue={OTHER};uninvested.research_progress=.125
 suspended.technologies[CANONICAL].level=7
 suspended.technologies[CANONICAL].saved_progress=.27
 suspended.research_queue={OTHER,CANONICAL};suspended.research_progress=.42
 writes=0
end
function provider_route(last)
 local finite={}
 for level=4,last do finite[#finite+1]={name="worker-robots-storage-"..level,max_level=level,provider="provider"}end
 return {technology="worker-robots-storage-"..(last+1),level=last+1,predecessor="worker-robots-storage-"..last,
   owned=true,finite=finite,legacy_compatible=true}
end
function add_provider(last)
 prototypes.technology[CANONICAL].max_level=4;creators[CANONICAL]="provider"
 for level=5,last+1 do prototypes.technology["worker-robots-storage-"..level]={name="worker-robots-storage-"..level,
   level=level,max_level=level==last+1 and 4294967295 or level} end
 for _,force in pairs(game.forces)do
  for level=5,last+1 do force.technologies["worker-robots-storage-"..level]={level=level,researched=false,enabled=true,saved_progress=0}end
 end
end
history=require("runtime.worker_robot_storage")
'''

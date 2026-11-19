"""Explicit callback inputs for the K2SO continuation observer's host controls.

This is not a Factorio emulator and never loads MIR production code. Tests supply
ordinary completions, partial work, cap results and science debits. The observer
must reject inconsistent observations; native execution still owns gameplay proof.
"""

from __future__ import annotations

from pathlib import Path


FIXTURE = Path(__file__).parent / "fixtures" / "k2so-material-continuation"
EARLY = {
    "rare_metals": ("kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"),
    "silicon": ("kr-silicon",),
    "glass": ("kr-glass",),
}
PACKS = ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack")


WORLD = r'''
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, member in pairs(value) do out[key] = copy(member) end
  return out
end
local recipes = {
  rare_metals = {"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"},
  silicon = {"kr-silicon"}, glass = {"kr-glass"},
}
local science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}
local technology_values, force_values = {}, {}
local function technology(force, name, first, maximum, effects, ingredients)
  local values = {
    name=name, valid=true, force=force, level=first, researched=false,
    enabled=true, visible_when_disabled=false, saved_progress=0,
    prototype={name=name, level=first, max_level=maximum, effects=effects or {},
      research_unit_energy=1800, hidden=false, enabled=true},
    effects=effects or {}, research_unit_ingredients=ingredients or {}, prerequisites={},
  }
  local result = {}
  setmetatable(result, {
    __index=function(_, key)
      if key == "research_unit_count" then
        if name:match("^recipe%-prod%-research_material_") then
          return first == 1 and 200 * 2^(values.level-1) or 1600 + 200*(values.level-4)
        end
        return name=="mir-k2so-material-continuation-probe" and 20 or 1000
      end
      return values[key]
    end,
    __newindex=function(_, key, value)
      if observation_locked then error("observer technology write: " .. key) end
      values[key] = value
      if key == "researched" and value and handlers.research then
        handlers.research({research=result, by_script=true})
      end
    end,
  })
  technology_values[result] = values
  return result
end
local function set_queue(force, submitted)
  local values = force_values[force]
  if values.current then technology_values[values.current].saved_progress=values.progress end
  local queue = {}
  for _, submitted_row in ipairs(submitted or {}) do
    local row = type(submitted_row) == "string" and force.technologies[submitted_row] or submitted_row
    assert(row and row.valid, "unknown queued technology")
    queue[#queue+1] = row
  end
  values.queue, values.current = queue, queue[1]
  values.progress = values.current and technology_values[values.current].saved_progress or 0
end
local function make_force(name, index)
  local values={name=name,index=index,valid=true,technologies={},recipes={},queue={},
    current=nil,progress=0,laboratory_speed_modifier=0,laboratory_productivity_bonus=0,
    research_queue_enabled=true}
  local force={}
  setmetatable(force, {
    __index=function(_, key)
      if key == "research_queue" then return values.queue end
      if key == "current_research" then return values.current end
      if key == "research_progress" then return values.progress end
      return values[key]
    end,
    __newindex=function(_, key, value)
      if observation_locked then error("observer force write: " .. key) end
      if key == "research_queue" then return set_queue(force, value) end
      if key == "research_progress" then
        assert(values.current, "No research in progress")
        values.progress=value;technology_values[values.current].saved_progress=value;return
      end
      values[key]=value
    end,
  })
  force_values[force]=values
  for family, names in pairs(recipes) do
    local ingredients={{name=science[1],amount=1},{name=science[2],amount=1}}
    if family ~= "silicon" then ingredients[#ingredients+1]={name=science[3],amount=1} end
    local effects={}
    for _, recipe in ipairs(names) do
      effects[#effects+1]={type="change-recipe-productivity",recipe=recipe,change=.02}
      values.recipes[recipe]={valid=true,name=recipe,productivity_bonus=0}
    end
    local id="recipe-prod-research_material_"..family.."-1"
    values.technologies[id]=technology(force,id,1,3,effects,ingredients)
  end
  local prerequisite_names={
    "automation-science-pack","logistic-science-pack","chemical-science-pack","space-science-pack",
    "kr-rare-metal-processing","kr-enriched-ores","kr-silicon-processing","kr-stone-processing",
  }
  for _, id in ipairs(prerequisite_names) do values.technologies[id]=technology(force,id,1,1) end
  values.technologies["mir-k2so-material-continuation-probe"]=technology(force,
    "mir-k2so-material-continuation-probe",1,1,{},{{name="automation-science-pack",amount=1}})
  values.add_research=function(id)
    local row=values.technologies[id]
    if not row or not row.enabled or row.researched then return false end
    local queue={};for _, item in ipairs(values.queue)do queue[#queue+1]=item end
    queue[#queue+1]=row;set_queue(force,queue);return true
  end
  values.get_saved_technology_progress=function(id)
    return values.technologies[id].saved_progress
  end
  values.reset_technology_effects=function() end
  return force
end
local function inventory()
  local values={}
  return {
    insert=function(row)
      if observation_locked then error("observer inventory insertion") end
      local count=math.min(row.count,200-(values[row.name] or 0))
      values[row.name]=(values[row.name] or 0)+count;return count
    end,
    get_item_count=function(name)return values[name] or 0 end,
    is_empty=function()for _,n in pairs(values)do if n>0 then return false end end;return true end,
    get_contents=function()return copy(values)end,
    debit=function(name,count)
      if observation_locked then error("observer inventory debit") end
      assert((values[name] or 0)>=count,"insufficient supplied science");values[name]=values[name]-count
    end,
    set=function(name,count)
      if observation_locked then error("observer inventory replacement") end
      values[name]=count
    end,
  }
end
function world_new()
  handlers,markers,files,saves,logs,storage={},{},{},{},{},{}
  observation_locked=false
  local player=make_force("player",1)
  local force_registry={[1]=player,[2]=make_force("enemy",2),[3]=make_force("neutral",3)}
  setmetatable(force_registry,{__index=function(rows,key)
    if type(key)=="string"then for _,force in pairs(rows)do if force.name==key then return force end end end
  end})
  local surface={index=1}
  world_labs={}
  surface.create_entity=function(arguments)
    local inv=inventory()
    local lab_values={name=arguments.name,valid=true,unit_number=#world_labs+1,
      force=type(arguments.force)=="string" and force_registry[arguments.force] or arguments.force or player,
      surface=surface,position={x=.5,y=.5},energy=0,electric_buffer_size=1000,
      disabled_by_script=false,destructible=true,minable=true,operable=true,
      get_inventory=function(which)assert(which==1);return inv end,
      prototype={get_researching_speed=function()return 1 end},quality={name="normal"}}
    local lab=setmetatable({}, {
      __index=function(_,key)return lab_values[key]end,
      __newindex=function(_,key,value)
        if observation_locked then error("observer lab write: "..key) end
        if key=="energy"then value=math.min(value,lab_values.electric_buffer_size)end
        lab_values[key]=value
      end,
    })
    world_labs[#world_labs+1]=lab;return lab
  end
  surface.find_entity=function(name,position)
    for _,lab in ipairs(world_labs)do if lab.name==name and lab.position.x==position.x and lab.position.y==position.y then return lab end end
  end
  local difficulty=setmetatable({technology_price_multiplier=1},{__index=function(_,key)
    error("unknown DifficultySettings field: "..key)
  end})
  game={tick=0,forces=force_registry,surfaces={[1]=surface},difficulty_settings=difficulty,
    create_force=function(name)
      local count=0;for key in pairs(force_registry)do if type(key)=="number"then count=math.max(count,key)end end
      local force=make_force(name,count+1);force_registry[count+1]=force;return force
    end,
    server_save=function(name)saves[#saves+1]={name=name,tick=game.tick}end,
  }
  return game
end
function world_add_tails()
  for key,force in pairs(game.forces)do
    if type(key)=="number"then
      for family,names in pairs(recipes)do
        local effects={};for _,recipe in ipairs(names)do effects[#effects+1]={type="change-recipe-productivity",recipe=recipe,change=.02}end
        local id="recipe-prod-research_material_"..family.."-4"
        force.technologies[id]=technology(force,id,4,4294967295,effects,{{name="space-science-pack",amount=1}})
        force.technologies[id].prerequisites={["recipe-prod-research_material_"..family.."-1"]=force.technologies["recipe-prod-research_material_"..family.."-1"],
          ["space-science-pack"]=force.technologies["space-science-pack"]}
      end
    end
  end
end
function world_add_probe(name)
  for key,force in pairs(game.forces)do if type(key)=="number"then force.technologies[name]=technology(force,name,1,4294967295,{},{{name="space-science-pack",amount=1}})end end
end
function world_set_state(force_name,id,changes)
  local row=game.forces[force_name].technologies[id]
  for key,value in pairs(changes)do technology_values[row][key]=value end
end
function world_set_work(force_name,queue,progress)
  local force=game.forces[force_name];set_queue(force,queue)
  if progress~=nil then
    assert(force.current_research or progress==0,"idle progress")
    force_values[force].progress=progress
    if force.current_research then technology_values[force.current_research].saved_progress=progress end
  end
end
function world_engine_unit(scripted)
  local force=game.forces.player
  local row=force.current_research
  local lab=world_labs[1]
  if not row or not lab or lab.disabled_by_script then return false end
  assert(lab.energy>0,"bounded host lab energy exhausted before next work unit")
  local inv=lab.get_inventory(1)
  for _,ingredient in ipairs(row.research_unit_ingredients)do if inv.get_item_count(ingredient.name)<ingredient.amount then return false end end
  for _,ingredient in ipairs(row.research_unit_ingredients)do inv.debit(ingredient.name,ingredient.amount)end
  lab.energy=0
  local count=row.research_unit_count
  local completed=math.floor(force.research_progress*count+.5)+1
  force_values[force].progress=completed/count
  technology_values[row].saved_progress=completed/count
  if completed==count then
    local tv=technology_values[row]
    tv.saved_progress=0
    if tv.level==tv.prototype.max_level then tv.researched=true else tv.level=tv.level+1 end
    for _,effect in ipairs(tv.effects)do force.recipes[effect.recipe].productivity_bonus=force.recipes[effect.recipe].productivity_bonus+effect.change end
    local queue={};for index=2,#force.research_queue do queue[#queue+1]=force.research_queue[index]end
    force_values[force].current=nil;force_values[force].progress=0;set_queue(force,queue)
    if handlers.research then handlers.research({research=row,by_script=scripted==true})end
  end
  return true
end
function world_tick(units, scripted)
  for _=1,units do
    game.tick=game.tick+1
    world_engine_unit(scripted)
    if handlers.tick then handlers.tick({tick=game.tick})end
  end
end
function world_call(name,event)
  local ok,message=pcall(handlers[name],event)
  return ok,tostring(message)
end
'''


class FixtureWorld:
    """Isolated explicit runtime and callback registry for one test method."""

    def __init__(self, runtime_type):
        self.lua = runtime_type(unpack_returned_tuples=True)
        self.lua.execute(WORLD)
        self.lua.eval("world_new")()

    def evaluate(self, expression):
        return self.lua.eval(expression)

    def execute(self, statements):
        return self.lua.execute(statements)

    def load(self, stage, actor_source=None):
        self.lua.globals().fixture_directory = str(FIXTURE)
        self.lua.globals().fixture_stage = stage
        self.lua.globals().fixture_control_text = actor_source if actor_source is not None else (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        self.lua.execute(r'''
          local versions={source="0.1.0",upgrade="0.2.0",finite="0.3.0",relaxed="0.4.0"}
          local active={base="2.1.24",["more-infinite-research"]=fixture_stage=="source" and "5.0.21017" or "5.0.21018",
            ["elevated-rails"]="2.1.24",quality="2.1.24",recycler="2.1.24",["space-age"]="2.1.24",
            flib="0.17.2",["k2so-assets"]="1.0.7",["Krastorio2"]="2.1.4",["Krastorio2-spaced-out"]="2.0.19",
            ["Krastorio2Assets"]="2.1.0",["Krastorio2MenuSimulations"]="2.1.0",["xy-k2so-enhancements-nulls-fork"]="0.8.3",
            ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["mir-fixture-k2so-material-continuation"]=versions[fixture_stage]}
          local startup={["mir-settings-profile-import"]={value=""},["mir-science-pack-ingredient-policy"]={value="configured"}}
          for family in pairs({rare_metals=true,silicon=true,glass=true})do
            startup["ips-max-level-research_material_"..family]={value=fixture_stage=="finite" and 3 or 0}
            startup["ips-enable-research_material_"..family]={value=true}
            for key,value in pairs({["cost-base"]=200,["cost-linear-increment"]=0,["cost-growth"]=2,["research-time"]=30,["effect-per-level"]=2})do
              startup["ips-"..key.."-research_material_"..family]={value=value}
            end
          end
          local env={game=game,storage=storage,settings={startup=startup},script={active_mods=active},
            helpers={},defines={inventory={lab_input=1},events={on_tick="tick",on_research_finished="research"}},
            log=function(message)logs[#logs+1]=message end}
          env.script.on_init=function(fn)handlers.init=fn end
          env.script.on_load=function(fn)handlers.load=fn end
          env.script.on_configuration_changed=function(fn)handlers.configuration=fn end
          env.script.on_event=function(key,fn)handlers[key]=fn end
          env.helpers.table_to_json=function(value)markers[#markers+1]=value;return "host-json"end
          env.helpers.write_file=function(path,body,append)files[#files+1]={path=path,body=body,append=append}end
          local modules={}
          env.require=function(name)
            if modules[name] then return modules[name] end
            assert(name=="fixture_control" or name=="fixture_data","unexpected runtime module "..name)
            if name=="fixture_control" then
              modules[name]=assert(load(fixture_control_text,"@k2so-fixture-control","t",env))()
            else
              modules[name]=assert(loadfile(fixture_directory.."/"..name..".lua","t",env))()
            end
            return modules[name]
          end
          setmetatable(env,{__index=_G});scenario_environment=env
          fixture_actor=env.require("fixture_control")
          fixture_actor.apply(fixture_stage)
        ''')

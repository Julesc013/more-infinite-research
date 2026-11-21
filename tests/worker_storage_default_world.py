"""Explicit host-world constructors for default worker-storage owner controls."""
from pathlib import Path

from worker_storage_recovery_fixture import RECOVERY_WORLD as RECOVERY_WORLD_FIXTURE


DEFAULT_WORKER_RUNTIME_CONFIGURATION = r'''
  package.loaded["runtime.configuration"]={streams={["worker-robots-storage"]={
    base_cost=200,growth_factor=1.5,linear_increment=0,research_time=60,
    effect_percent=1,max_level=0,enabled=true}}}
'''
DEFAULT_NATIVE_OWNER_RECOVERY_WORLD = DEFAULT_WORKER_RUNTIME_CONFIGURATION + RECOVERY_WORLD_FIXTURE


_HISTORICAL_MODULES = (
    "runtime.worker_robot_storage",
    "research.worker_storage_recovery",
    "runtime.caps",
)


def build_default_native_owner_world(runtime_factory, *, target, source_root):
    """Return the ordinary default-owner world using the caller's Lua factory."""
    lua = runtime_factory(unpack_returned_tuples=True)
    lua.globals().player_root = Path(source_root).as_posix()
    lua.globals().package_family = target
    lua.execute(r'''
      package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
      local f200=package_family=="f200"
      package.loaded["platform.target"]={id=package_family,minimum_base=f200 and "2.0.77"or"2.1.23",
        distribution_version=f200 and "5.0.20012"or"5.0.21012"}
    ''')
    lua.execute(DEFAULT_NATIVE_OWNER_RECOVERY_WORLD)
    lua.execute(r'''
      local target=require("platform.target")
      script.active_mods.base=target.minimum_base;script.active_mods["more-infinite-research"]=target.distribution_version
      ORDINARY="mir-worker-storage-default-4";HEAD="mir-worker-storage-head-4";LEGACY517="mir-worker-storage-published517-4";OWNER_KEY="mir_worker_storage_native_owner"
      function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
      function same(a,b)if type(a)~=type(b)then return false end;if type(a)~="table"then return a==b end
        for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
      prototypes.technology[ORDINARY]=copy(prototypes.technology[CANONICAL])
      local owner=prototypes.technology[ORDINARY];owner.name=ORDINARY;owner.hidden=false;owner.visible_when_disabled=false
      local debit=copy(prototypes.technology[CANONICAL]);prototypes.technology[HEAD]=debit
      debit.name=HEAD;debit.max_level=4294967295;debit.hidden=true;debit.enabled=false;debit.visible_when_disabled=false
      debit.effects[1].modifier=-1;debit.research_unit_count_formula=nil;debit.research_unit_count=1
      debit.research_unit_energy=60;debit.prerequisites={};debit.ignore_tech_cost_multiplier=true
      local legacy=copy(prototypes.technology[CANONICAL]);prototypes.technology[LEGACY517]=legacy
      legacy.name=LEGACY517;legacy.hidden=true;legacy.enabled=false;legacy.visible_when_disabled=false
      creators[ORDINARY]="more-infinite-research";creators[HEAD]="more-infinite-research";creators[LEGACY517]="more-infinite-research"
      detached=make_force("detached",4);game.forces.detached=detached
      queue_writes={};progress_writes={};foreign_bonus={};gaps={}
      function install_force(force)
        local index=force.index;foreign_bonus[index]=20
        for _,id in ipairs{ORDINARY,HEAD,LEGACY517}do
          local proto=prototypes.technology[id]
          local v={name=id,level=4,researched=false,enabled=proto.enabled,visible_when_disabled=proto.visible_when_disabled,
            saved_progress=0,prototype=proto,force=force,prerequisites=id==HEAD and{}or{foundation={researched=true}}}
          force.technologies[id]=setmetatable({},{__index=function(_,key)
            if key=="research_unit_count"then return id==HEAD and 1 or math.floor(100*2^(v.level-4))end
            return v[key]
          end,__newindex=function(_,key,value)
            writes=writes+1
            if key=="level"then v.level=value;v.researched=false;v.enabled=true;v.saved_progress=0 else v[key]=value end
          end})
        end
        local mt=getmetatable(force);local read,write=mt.__index,mt.__newindex
        mt.__index=function(object,key)
          if key=="worker_robots_storage_bonus"then
            local total=foreign_bonus[index]
            for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517,ID}do local t=force.technologies[id]
              total=total+(t.level-4+(t.researched and 1 or 0))*prototypes.technology[id].effects[1].modifier
            end
            local h=force.technologies[HEAD]
            return total+(h.level-4+(h.researched and 1 or 0))*prototypes.technology[HEAD].effects[1].modifier
          end
          if gaps[index]and key=="current_research"then return nil end
          if gaps[index]and key=="research_progress"then return 0 end
          return read(object,key)
        end
        mt.__newindex=function(object,key,value)
          if key=="research_queue"then
            queue_writes[index]=(queue_writes[index]or 0)+1
            local admitted={}
            for _,entry in ipairs(value)do
              local t=force.technologies[type(entry)=="string"and entry or entry.name];local valid=t and t.enabled
              for _,pr in pairs(t and t.prerequisites or{})do local proto=pr.prototype
                if not pr.researched and not(proto and proto.max_level==4294967295 and pr.level>proto.level)then valid=false end
              end
              if valid then admitted[#admitted+1]=entry end
            end
            value=admitted
          elseif key=="research_progress"then progress_writes[index]=(progress_writes[index]or 0)+1 end
          write(object,key,value)
        end
      end
      for _,f in pairs(game.forces)do install_force(f)end
      function set_reward(value)
        prototypes.technology[CANONICAL].effects[1].modifier=value
        prototypes.technology[ORDINARY].effects[1].modifier=value
        prototypes.technology[HEAD].effects[1].modifier=value==0 and 0 or -value
        prototypes.technology[ID].effects[1].modifier=value
      end
      function owner_event(old)return{mod_startup_settings_changed=false,mod_changes={
        ["more-infinite-research"]={old_version=old,new_version=target.distribution_version}}}end
      function seed_owner()
        seed();detached.technologies[CANONICAL].level=6;detached.technologies[CANONICAL].saved_progress=.23
        detached.research_queue={OTHER};detached.research_progress=.625;writes=0;queue_writes={};progress_writes={}
      end
      function tech_frame(t)return{level=t.level,researched=t.researched,enabled=t.enabled,
        visible=t.visible_when_disabled,saved=t.saved_progress,count=t.research_unit_count}end
      function frame(f)
        local queue={}for i,t in ipairs(f.research_queue)do queue[i]=t.name end
        return{source=tech_frame(f.technologies[CANONICAL]),owner=tech_frame(f.technologies[ORDINARY]),
          debit=tech_frame(f.technologies[HEAD]),legacy517=tech_frame(f.technologies[LEGACY517]),private=tech_frame(f.technologies[ID]),
          current=f.current_research and f.current_research.name,progress=f.research_progress,queue=queue,
          bonus=f.worker_robots_storage_bonus,other_saved=f.technologies[OTHER].saved_progress}
      end
      function all_frames()local out={}for _,f in pairs(game.forces)do out[f.index]=frame(f)end;return out end
      function transfer()
        local plan=history.plan_default_owner_transfer(owner_event(package_family=="f200"and"5.0.20011"or"5.0.21011"),nil,false)
        return history.apply_default_owner_transfer(plan),plan
      end
      function init_default()history.on_init(nil);assert(history.default_owner_on_init(nil,true));writes=0;queue_writes={};progress_writes={}end
      function finish_frame(force,representation,remainder,gap)
        force.research_progress=0;force.technologies[ORDINARY].saved_progress=0
        if representation=="completed"then force.technologies[ORDINARY].researched=true else force.technologies[ORDINARY].level=5 end
        force.research_queue=remainder;force.research_progress=0;gaps[force.index]=gap
        writes=0;queue_writes={};progress_writes={}
      end
      function finish_event(force)return{research=force.technologies[ORDINARY],by_script=false,tick=100}end
      function published517_source_contract()
        target.distribution_version="5.0.20017";script.active_mods["more-infinite-research"]=target.distribution_version
        script.active_mods["space-exploration"]="0.7.57"
        local values=require("runtime.configuration").streams["worker-robots-storage"]
        values.max_level=10;history.configure(10,true)
        local packs={"automation-science-pack","logistic-science-pack","chemical-science-pack",
          "production-science-pack","utility-science-pack"}
        -- The retained native517 contract has these two direct prerequisites;
        -- authored preflight rows can still contain the redundant second level.
        local prerequisites={"utility-science-pack","worker-robots-storage-3"}
        for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517}do
          local p=prototypes.technology[id];p.research_unit_count_formula="675*1.5^(L-4)";p.research_unit_count=nil
          p.research_unit_energy=3600;p.ignore_tech_cost_multiplier=false;p.research_unit_ingredients={};p.prerequisites={}
          for _,name in ipairs(packs)do p.research_unit_ingredients[#p.research_unit_ingredients+1]={name=name,amount=1}end
          for _,name in ipairs(prerequisites)do p.prerequisites[name]={name=name}end
        end
        for _,force in pairs(game.forces)do
          for _,id in ipairs{CANONICAL,ORDINARY,LEGACY517}do
            local t=force.technologies[id];local mt=getmetatable(t);local read=mt.__index
            mt.__index=function(object,key)
              if key=="research_unit_count"then return math.floor(675*1.5^(read(object,"level")-4))end
              return read(object,key)
            end
          end
        end
      end
      function current_se_contract()
        target.distribution_version="5.0.20018";script.active_mods["more-infinite-research"]=target.distribution_version
        local packs={"automation-science-pack","logistic-science-pack","chemical-science-pack",
          "production-science-pack","se-rocket-science-pack","se-material-science-pack-1","space-science-pack"}
        for _,id in ipairs{CANONICAL,ORDINARY,ID}do
          local p=prototypes.technology[id];p.research_unit_ingredients={};p.prerequisites={}
          if id==ID then p.research_unit_count_formula="675*1.5^(L-4)";p.research_unit_count=nil;p.research_unit_energy=3600 end
          for _,name in ipairs(packs)do p.research_unit_ingredients[#p.research_unit_ingredients+1]={name=name,amount=1}end
          p.prerequisites["worker-robots-storage-3"]={name="worker-robots-storage-3"}
        end
      end
      function published517_se_bridge_event()
        return {mod_startup_settings_changed=false,mod_changes={
          ["more-infinite-research"]={old_version="5.0.20017",new_version=target.distribution_version},
          ["space-exploration"]={old_version="0.7.57",new_version="0.7.57"}}}
      end
    ''')
    return lua


def install_published_default_reader(lua, *, historical_sources):
    """Install the caller-pinned published reader and current-reader switch."""
    try:
        modules = {name: historical_sources[name] for name in _HISTORICAL_MODULES}
    except (KeyError, TypeError) as error:
        raise ValueError("published default reader requires the three exact historical modules") from error
    if any(not isinstance(source, str) for source in modules.values()):
        raise ValueError("published default reader source must be text")
    lua.globals().published_modules = lua.table_from(modules)
    lua.execute(r'''
      candidate_history=history
      candidate_modules={}
      for name in pairs(published_modules)do candidate_modules[name]=package.loaded[name]end
      local target=require("platform.target")
      candidate_version=target.distribution_version
      published_version=package_family=="f200"and"5.0.20011"or"5.0.21011"
      function published_reader()
        target.distribution_version=published_version
        script.active_mods["more-infinite-research"]=published_version
        package.loaded["runtime.caps"]=assert(load(published_modules["runtime.caps"]))()
        package.loaded["research.worker_storage_recovery"]=assert(load(published_modules["research.worker_storage_recovery"]))()
        return assert(load(published_modules["runtime.worker_robot_storage"]))()
      end
      function inherited_configuration(old)
        local reader=published_reader()
        reader.on_load()
        local event={mod_startup_settings_changed=false,mod_changes={
          ["more-infinite-research"]={old_version=old,new_version=published_version}}}
        reader.apply(reader.preflight(event,nil))
        return reader
      end
      function candidate_reader()
        target.distribution_version=candidate_version
        script.active_mods["more-infinite-research"]=candidate_version
        for name,module in pairs(candidate_modules)do package.loaded[name]=module end
        history=candidate_history
      end
    ''')
    return lua


def build_full_default_provider_handover_world(runtime_factory, *, target, source_root):
    """Construct the caller-owned provider handover world."""
    lua = build_default_native_owner_world(runtime_factory, target=target, source_root=source_root)
    lua.execute(r'''
          prototypes.technology[ID].visible_when_disabled=false
          function full_source(a,unpaid_pending)
            history.on_init(nil);set_reward(a);seed_owner()
            if unpaid_pending then uninvested.technologies[CANONICAL].enabled=true;uninvested.research_queue={CANONICAL};uninvested.research_progress=.37 end
            transfer();writes=0;queue_writes={};progress_writes={}
          end
          function provider_event()
            return {mod_startup_settings_changed=false,mod_changes={provider={new_version="1.0"}}}
          end
          function finite_entry(b)
            script.active_mods.provider="1.0";add_provider(5)
            creators["worker-robots-storage-6"]="more-infinite-research"
            local public=prototypes.technology[CANONICAL]
            public.effects[1].modifier=b;public.research_unit_count_formula=nil;public.research_unit_count=1000
            public.research_unit_energy=3600;public.research_unit_ingredients={{name="automation-science-pack",amount=1},{name="space-science-pack",amount=1}}
            prototypes.technology[HEAD].effects[1].modifier=b==0 and 0 or -b
            for _,f in pairs(game.forces)do
              local c=f.technologies[CANONICAL];local paid=f.technologies[HEAD].level==5;local enabled,visible=c.enabled,c.visible_when_disabled
              -- Explicit host representation of already-loaded finite4, not a claim of new engine observation.
              c.level=4;c.researched=paid;c.enabled=enabled;c.visible_when_disabled=visible
              local mt=getmetatable(c);local read=mt.__index
              mt.__index=function(object,key)if key=="research_unit_count"then return 1000 end;return read(object,key)end
            end
            writes=0;queue_writes={};progress_writes={}
          end
          function delegate(event,route)
            event,route=event or provider_event(),route or provider_route(5)
            local plan=history.default_owner_preflight(event,route,true)
            assert(history.default_owner_delegated(plan))
            local legacy=history.preflight(event,route,plan)
            return plan,legacy
          end
          function handover(event,route)
            local plan,legacy=delegate(event,route)
            assert(history.default_owner_apply(plan));history.apply(legacy)
            return plan,legacy
          end
          function foreign_frames()
            local out={}
            for _,f in pairs(game.forces)do local rows={}
              for n=5,6 do local t=f.technologies['worker-robots-storage-'..n];rows[n]={level=t.level,researched=t.researched,enabled=t.enabled,saved=t.saved_progress}end
              out[f.index]=rows
            end
            return out
          end
        ''')
    return lua


def build_older_default_admission_world(runtime_factory, *, target, source_root):
    """Construct the caller-owned older default admission world."""
    lua = build_default_native_owner_world(runtime_factory, target=target, source_root=source_root)
    lua.execute(r'''
          for _,id in ipairs({CANONICAL,ORDINARY,ID})do
            prototypes.technology[id].research_unit_count_formula="675*1.5^(L-4)"
            prototypes.technology[id].research_unit_energy=3600
            prototypes.technology[id].research_unit_ingredients={
              {name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},
              {name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1},
              {name="utility-science-pack",amount=1}}
            for _,force in pairs(game.forces)do
              local t=force.technologies[id];local mt=getmetatable(t);local read=mt.__index
              mt.__index=function(object,key)
                if key=="research_unit_count"then return math.floor(675*1.5^(read(object,"level")-4))end
                return read(object,key)
              end
            end
          end
          function older_event(old,addition)
            local event=owner_event(old)
            if addition then script.active_mods["test-observer"]="0.1.0"
              event.mod_changes["test-observer"]={new_version="0.1.0"}end
            return event
          end
          function paid_idle()
            player.technologies[CANONICAL].level=5;uninvested.technologies[CANONICAL].level=5
            suspended.technologies[CANONICAL].level=6
            player.research_queue={OTHER};player.research_progress=.42
            suspended.research_queue={OTHER};suspended.research_progress=.125
            detached.technologies[OTHER].saved_progress=.27
            uninvested.technologies[CANONICAL].enabled=false
            writes=0;queue_writes={};progress_writes={}
          end
          function older_plan(event)return history.plan_default_owner_transfer(event,nil,false)end
          function refuse_older(event,route)
            local before=all_frames();writes=0
            assert(not pcall(history.plan_default_owner_transfer,event,route,false))
            assert(writes==0 and same(before,all_frames())and storage[OWNER_KEY]==nil)
          end
        ''')
    return lua

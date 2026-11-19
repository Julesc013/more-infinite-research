"""Small shared Lua worlds for native-credit host controls.

The builders only materialize the existing test-owned baseline.  Individual
tests continue to own their active-mod tuples, producer/history substitutions,
scenario construction, and assertions.
"""
import struct


def build_native_credit_world(lua_runtime, source_root):
    """Return the original descriptor-bounded native-credit Lua baseline."""
    lua = lua_runtime(unpack_returned_tuples=True)
    lua.globals().player_root = source_root.as_posix()
    lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          storage, game = {}, {forces={}}
          native_credit_definitions = require("research.native_credit_definitions")
           local catalogue = require("runtime.catalogue")
           fixed_credit_scalars = {}
           for _, descriptor in ipairs(native_credit_definitions.fixed_descriptors()) do
             if descriptor.recipe ~= "vgal-coal-crushing" then fixed_credit_scalars[descriptor.recipe] = .1 end
           end
           catalogue.native_credit_scalars = function()
             local out = {}
             for recipe, change in pairs(fixed_credit_scalars) do out[recipe] = change end
             return out
           end
          native_credits = require("runtime.native_credits")
          descriptors = native_credit_definitions.descriptors()
          -- These default worlds contain the original twelve recipes, not
          -- Galore's optional recipe. Its explicit controls opt in below.
          for i=#descriptors,1,-1 do
            if descriptors[i].recipe=="vgal-coal-crushing" then table.remove(descriptors,i) end
          end
          UINT32_MAX = 4294967295

          function make_technology(name, prototype, level, researched, enabled)
            local state = {
              name=name, valid=true, prototype=prototype, level=level or 1,
              researched=researched == true, enabled=enabled == true,
              visible_when_disabled=false, writes={level=0, enabled=0},
            }
            local object = {}
            setmetatable(object, {
              __index=state,
              __newindex=function(_, key, value)
                state[key] = value
                if key == "level" then
                  state.writes.level = state.writes.level + 1
                  -- F200 level writes represent research through the preceding level.
                  state.researched = false
                  -- Native F200 setter behavior: setting a carrier level enables it.
                  state.enabled = true
                elseif key == "enabled" then
                  state.writes.enabled = state.writes.enabled + 1
                end
              end,
            })
            return object, state
          end

          function descriptor_for(recipe)
            for _, descriptor in ipairs(descriptors) do
              if descriptor.recipe == recipe then return descriptor end
            end
            error("unknown descriptor " .. tostring(recipe))
          end

          local function main_level(levels, main_id)
            local specified = levels and levels[main_id]
            if type(specified) == "table" then
              return specified.level or 1, specified.researched == true
            end
            return specified or 1, false
          end

          local function rebuild_effects(force, main_id)
            local effects = {}
            for _, descriptor in ipairs(descriptors) do
              if descriptor.main_id == main_id and force._included[descriptor.recipe] ~= false then
                effects[#effects + 1] = {
                  type="change-recipe-productivity", recipe=descriptor.recipe, change=force._scalar[descriptor.recipe]
                }
              end
            end
            force.technologies[main_id].prototype.effects = effects
          end

          function make_force(index, included, levels, offsets, scalar)
            local technologies = setmetatable({}, {
              __pairs=function() error("native credits scanned force technologies") end,
            })
            local force = {
              index=index, valid=true, technologies=technologies, _included=included or {}, _scalar={}, _states={},
              external_bonus=17.25, reset_calls=0,
              reset_technology_effects=function() error("native credits reset force effects") end,
              recipes=setmetatable({}, {__index=function() error("native credits read aggregate recipe bonus") end}),
            }
            local main_seen = {}
            for _, descriptor in ipairs(descriptors) do
              local change = scalar and scalar[descriptor.recipe] or .1
              force._scalar[descriptor.recipe] = change
              if not main_seen[descriptor.main_id] then
                local level, researched = main_level(levels, descriptor.main_id)
                local technology, state = make_technology(descriptor.main_id, {
                  name=descriptor.main_id, level=1, max_level=UINT32_MAX, effects={}
                }, level, researched, true)
                technologies[descriptor.main_id], force._states[descriptor.main_id] = technology, state
                main_seen[descriptor.main_id] = true
              end
              local offset = offsets and offsets[descriptor.recipe] or 0
              local positive_level = 1 + (offset > 0 and offset or 0)
              local negative_level = 1 + (offset < 0 and -offset or 0)
              local positive, positive_state = make_technology(descriptor.positive_id, {
                name=descriptor.positive_id, level=1, max_level=UINT32_MAX, hidden=true, enabled=false,
                visible_when_disabled=false,
                effects={{type="change-recipe-productivity", recipe=descriptor.recipe, change=change}},
              }, positive_level, false, false)
              local negative, negative_state = make_technology(descriptor.negative_id, {
                name=descriptor.negative_id, level=1, max_level=UINT32_MAX, hidden=true, enabled=false,
                visible_when_disabled=false,
                effects={{type="change-recipe-productivity", recipe=descriptor.recipe, change=-change}},
              }, negative_level, false, false)
              technologies[descriptor.positive_id], technologies[descriptor.negative_id] = positive, negative
              force._states[descriptor.positive_id], force._states[descriptor.negative_id] = positive_state, negative_state
            end
            for main_id in pairs(main_seen) do rebuild_effects(force, main_id) end
            return force
          end

          function set_included(force, recipe, value)
            local descriptor = descriptor_for(recipe)
            force._included[recipe] = value
            rebuild_effects(force, descriptor.main_id)
          end

          function ledger(force, recipe)
            local current = storage.mir_native_credits
            return current and current.forces[force.index] and current.forces[force.index][recipe] or nil
          end

          function holder(force, recipe, direction)
            local descriptor = descriptor_for(recipe)
            return force.technologies[direction == "positive" and descriptor.positive_id or descriptor.negative_id]
          end
        ''')
    return lua


def build_native_family_credit_world(lua_runtime, source_root):
    """Return the baseline plus the existing five-family test extension."""
    lua = build_native_credit_world(lua_runtime, source_root)
    lua.globals().fixture_float32 = lambda value: struct.unpack("<f", struct.pack("<f", value))[0]
    lua.execute(r'''
          GROUPS={research_steel={
            {recipe="alternate-steel",change=.17},{recipe="multi-native",change=.17},
            {recipe="steel-plate",change=.17},{recipe="casting-steel",change=.17}},
            research_low_density_structure={{recipe="multi-native",change=.1}}}
          local function copy(value)
            if type(value)~="table" then return value end
            local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
          end
          -- Ordinary fixture defaults are authored exact quanta. Precision
          -- cases below replace these fields from independent observed units.
          function fixture_effect(value)
            return require("platform.target").id=="f200" and fixture_float32(value) or value
          end
          function reload_credits(active,target_id,fixed)
            script={active_mods=active or {base="2.1.23",["space-age"]="2.1.23",["more-infinite-research"]="5.0.21003"}}
            require("platform.target").id=target_id or "f210"
            prototypes={technology={},mod_data={
              ["more-infinite-research-native-adoptions"]={data={schema=1,owners={},withheld={},credits=copy(GROUPS),
                fixed_credits=copy(fixed or {})}}},
              get_history=function(_,name) return {created=foreign_creation==name and "foreign" or "more-infinite-research"} end}
            package.loaded["research.catalogue"]=nil
            package.loaded["runtime.catalogue"]=nil
            package.loaded["runtime.native_credits"]=nil
            native_credits=require("runtime.native_credits")
          end
          function make_collected_force(index,level,mask,private)
            local force={index=index,valid=true,technologies=setmetatable({}, {
              __pairs=function()error("whole technology traversal")end}),_states={},
              foreign_bonus=17.25,recipes=setmetatable({}, {__index=function()error("aggregate recipe read")end}),
              reset_technology_effects=function()error("force reset")end,research_progress=.42}
            for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
              if not force.technologies[d.main_id] then
                local t,s=make_technology(d.main_id,{name=d.main_id,level=1,max_level=UINT32_MAX,
                  hidden=private==true,effects={}},level or 1,false,true)
                t.force=force;force.technologies[d.main_id]=t;force._states[d.main_id]=s
              end
              for _,direction in ipairs({"positive","negative"}) do
                local name=direction=="positive" and d.positive_id or d.negative_id
                local t,s=make_technology(name,{name=name,level=1,max_level=UINT32_MAX,hidden=true,
                  enabled=false,visible_when_disabled=false,effects={{type="change-recipe-productivity",
                    recipe=d.recipe,change=direction=="positive" and fixture_effect(d.change)
                      or -fixture_effect(d.change)}}},1,false,false)
                t.force=force;force.technologies[name]=t;force._states[name]=s
              end
            end
            local t,s=make_technology("foreign",{name="foreign",level=1,max_level=UINT32_MAX,effects={}},3,false,false)
            t.force=force;force.technologies.foreign=t;force._states.foreign=s
            game.forces[index]=force;set_mask(force,mask or {},private)
            return force
          end
          function set_mask(force,mask,private)
            local seen={}
            for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
              local proto=force.technologies[d.main_id].prototype
              if not seen[d.main_id] then proto.effects={};proto.hidden=private==true;seen[d.main_id]=true end
              if mask[d.family.."\0"..d.recipe] then
                proto.effects[#proto.effects+1]={type="change-recipe-productivity",recipe=d.recipe,change=fixture_effect(d.change)}
              end
            end
          end
          function key(family,recipe)return family.."\0"..recipe end
          function record(force,family,recipe)
            return storage.mir_native_credits and storage.mir_native_credits.forces[force.index]
              and storage.mir_native_credits.forces[force.index][key(family,recipe)]
          end
          function own_contribution(force,family,recipe)
            local wanted
            for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
              if d.family==family and d.recipe==recipe then wanted=d end
            end
            local function completed(t)return t.level-1+(t.researched and 1 or 0)end
            local main=force.technologies[wanted.main_id];local included=false
            for _,e in ipairs(main.prototype.effects) do if e.recipe==recipe then included=true end end
            return wanted.change*((included and completed(main) or 0)
              +completed(force.technologies[wanted.positive_id])-completed(force.technologies[wanted.negative_id]))
          end
          function close(a,b)assert(math.abs(a-b)<1e-8,tostring(a).." differs "..tostring(b))end
          function no_foreign_write(force)
            assert(force.foreign_bonus==17.25 and not force.technologies.foreign.enabled)
            assert(force._states.foreign.writes.enabled==0 and force._states.foreign.writes.level==0)
          end
          function advance(force,id,level,researched)
            force._states[id].level=level;force._states[id].researched=researched
          end
          reload_credits()
        ''')
    return lua

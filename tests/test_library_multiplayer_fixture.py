"""Host controls for the private legacy-F200/current-F200/F210 two-client Library fixture, not native evidence."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-multiplayer"
CONTROL = FIXTURE / "control.lua"
F200_PROFILE = ROOT / "tests/profiles/library-multiplayer-f200-2077.json"
CURRENT_F200_PROFILE = ROOT / "tests/profiles/library-multiplayer-current-f200-2077.json"
F210_PROFILE = ROOT / "tests/profiles/library-multiplayer-f210-2123.json"
STANDALONE_F210_PROFILE = ROOT / "tests/profiles/library-multiplayer-standalone-f210-2123.json"
F210_API_CONSUMERS_PROFILE = ROOT / "tests/profiles/library-api-consumers-f210-2123.json"
PAIRED_PUBLISHED_PROFILE = ROOT / "tests/profiles/library-paired-browser-published-f200-2077.json"
PAIRED_MIR5_PROFILE = ROOT / "tests/profiles/library-paired-browser-mir5-f200-2077.json"
SCRIPTED_EFFECTS_PROFILE = ROOT / "tests/profiles/scripted-effects-multiplayer-f200-sa-2077.json"
WRAPPER = ROOT / "tools/Invoke-MultiplayerFixture.ps1"
SESSION = ROOT / "tools/Invoke-MultiplayerSession.ps1"
SAMPLER = ROOT / "tools/lib/validation/OwnedProcessMemorySampler.ps1"
MEMORY_CALIBRATION = ROOT / "spec/evidence/library-multiplayer-session-memory-calibration-r01.json"


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("fixture result is cyclic")
    seen.add(id(value))
    entries = list(value.items())
    keys = [key for key, _ in entries]
    if keys and all(isinstance(key, int) and key >= 1 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in entries}
    seen.remove(id(value))
    return result


class LibraryMultiplayerFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().control_path = CONTROL.as_posix()
        self.lua.execute(r'''
          function run_library_multiplayer_fixture(path, opponent, target)
            local ROOT_NAME="mir_research_browser"
            local FILTERS="mir_library_filters"
            local QUERY="mir_library_query"
            local SORT="mir_library_sort"
            local TABS="mir_library_tabs"
            local CONTENT="mir_library_research_content"
            local RESULTS="mir_library_results"
            local DETAIL="mir_library_detail"
            local DETAIL_TITLE="mir_library_detail_title"
            local AVAILABILITY={"mir_library_availability_1","mir_library_availability_2"}
            local AVAILABILITY_FAMILIES={"research_agricultural_growth_speed","research_spoilage_preservation"}
            local key="mir5_library_multiplayer"
            local gear="recipe-prod-research_gears-1"
            local mining="recipe-prod-research_mining_drill-1"
            local gear_packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local gear_ingredients={
              {name=gear_packs[1],amount=1},{name=gear_packs[2],amount=1},
              {name=gear_packs[3],amount=1},{name=gear_packs[4],amount=1},
            }
            local targets={
              f200={base="2.0.77",mir="5.0.20000"},
              f210={base="2.1.23",mir="5.0.21000"},
            }
            local selected=targets[target or "f200"]
            assert(selected,"unknown fixture target")
            local base_version,mir_version=selected.base,selected.mir
            if opponent=="f210-wrong-mir-version" then mir_version="5.0.21001"
            elseif opponent=="unsupported-target-base" then base_version="2.1.24" end
            local players, markers, screenshots, saves, lab_diagnostics = {}, {}, {}, {}, {}
            local force={valid=true,index=1,name="player",technologies={},recipes={},research_queue={},research_progress=0,research_enabled=true}
            for _,name in ipairs({gear,mining}) do
              force.technologies[name]={valid=true,name=name,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,
                research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients=name==gear and gear_ingredients or nil,
                prototype={effects={{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}}}
            end
            local ingredients=force.technologies[gear].research_unit_ingredients
            if opponent=="science-missing" then table.remove(ingredients,4)
            elseif opponent=="science-duplicate" then ingredients[5]={name=gear_packs[1],amount=1}
            elseif opponent=="science-extra" then ingredients[5]={name="military-science-pack",amount=1}
            elseif opponent=="science-wrong-amount" then ingredients[3].amount=2
            elseif opponent=="science-reordered" then
              force.technologies[gear].research_unit_ingredients={ingredients[4],ingredients[2],ingredients[1],ingredients[3]}
            end
            for _,name in ipairs({"iron-gear-wheel","burner-mining-drill","electric-mining-drill"}) do
              force.recipes[name]={valid=true,name=name,productivity_bonus=0}
            end
            for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}) do
              force.technologies[name]={valid=true,name=name,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false}
            end
            local function player(index, locale)
              local value={valid=true,index=index,name=index==1 and "MIR5English" or "MIR5Deutsch",locale=locale,connected=false,force=force,gui={screen={valid=true,type="screen"}}}
              players[index]=value
              return value
            end
            local en,de=player(1,"en"),player(2,opponent=="locale" and "fr" or "de")
            local storage={}
            local callbacks={events={}}
            local next_profiler=0
            local open_calls=0
            local profiler_logs={}
            local game={forces={player=force},surfaces={[1]={valid=true,index=1}},tick=0}
            local function fire(name,event)
              local callback=callbacks.events[name]
              if callback then
                local ok,message=pcall(callback,event)
                if not ok then error(message,0) end
              end
            end
            force.add_research=function(technology)
              if opponent=="missing-queue" and #force.research_queue>=1 then return true end
              force.research_queue[#force.research_queue+1]=technology
              if force.current_research==nil then
                force.current_research=technology
                fire(4,{research=technology})
              end
              return true
            end
            force.cancel_current_research=function()
              local cancelled=force.current_research
              force.current_research=nil;force.research_queue={};force.research_progress=0
              fire(7,{force=force,research={[gear]=cancelled and 1 or 0}})
            end
            game.get_player=function(index) return players[index] end
            force.get_spawn_position=function(surface) return {0,0} end
            local insert_counts, rejected_bulk_inserts = {}, 0
            local inventory={counts={}}
            inventory.insert=function(spec)
              insert_counts[#insert_counts+1]=spec.count
              if opponent=="all-at-once-feeding" and spec.count~=1 then
                rejected_bulk_inserts=rejected_bulk_inserts+1
                return 0
              end
              if opponent=="second-feed-rejected" and #insert_counts>#gear_packs then return 0 end
              inventory.counts[spec.name]=(inventory.counts[spec.name] or 0)+spec.count
              return spec.count
            end
            inventory.get_item_count=function(name) return inventory.counts[name] or 0 end
            inventory.is_empty=function()
              for _,count in pairs(inventory.counts) do
                if count~=0 then return false end
              end
              return true
            end
            local lab={valid=true,energy=0,active=true,status=19,electric_network_id=7}
            lab.get_inventory=function(index) assert(index==1);return inventory end
            game.surfaces[1].create_entity=function(spec)
              assert(spec.name=="lab" and spec.force==force)
              return lab
            end
            game.create_force=function(name)
              local foreign={valid=true,index=2,name=name,technologies={},recipes={},research_queue={},research_progress=0}
              for _,tech_name in ipairs({gear,mining}) do
                foreign.technologies[tech_name]={valid=true,name=tech_name,force=foreign,level=1,researched=false,enabled=true,
                  visible_when_disabled=false}
              end
              foreign.recipes["iron-gear-wheel"]={valid=true,name="iron-gear-wheel",productivity_bonus=0}
              fire(8,{force=opponent=="wrong-force-event" and force or foreign})
              if opponent=="foreign-force-gui" then en.gui.screen[ROOT_NAME]={valid=true,type="frame",visible=true} end
              return foreign
            end
            local function create_profiler(stopped)
              next_profiler=next_profiler+1
              local result={valid=true,stopped=stopped,ordinal=next_profiler}
              result.restart=function() result.running=true end
              result.stop=function() result.running=false end
              return setmetatable(result,{__tostring=function()error('profiler is not a Lua timing string')end})
            end
            game.take_screenshot=function(spec)
              screenshots[#screenshots+1]={by_player=spec.by_player,player_matches=spec.player==players[spec.by_player],show_gui=spec.show_gui,
                force_render=spec.force_render,path=spec.path,resolution={spec.resolution[1],spec.resolution[2]},
                tick=game.tick,open_calls=open_calls}
            end
            local last_screenshot_tick=nil
            local take_screenshot=game.take_screenshot
            game.take_screenshot=function(spec) last_screenshot_tick=game.tick;take_screenshot(spec) end
            game.server_save=function(name)
              assert(last_screenshot_tick~=nil and game.tick-last_screenshot_tick>=60,"save overlapped pending GUI captures")
              saves[#saves+1]=name
            end
            setmetatable(game,{__index=function(_,name)
              if name=="create_profiler" then error("removed game.create_profiler API was accessed") end
            end})
            local function native_style()
              local values={}
              return setmetatable({}, {
                __index=function(_,name) return values[name] end,
                __newindex=function(_,name,value)
                  if name=="width" then
                    values.minimal_width = value
                    values.maximal_width = value
                  else
                    values[name]=value
                  end
                end
              })
            end
            local function element(kind,name)
              return {valid=true,type=kind,name=name,style=native_style()}
            end
            local function build_gui(client, options)
              local target=client
              if opponent=="view-crosspollution" and client.index==2 then target=en end
              local root=element("frame",ROOT_NAME);root.visible=true
              local filters=element("flow",FILTERS)
              root[FILTERS]=filters
              filters[QUERY]=element("textfield",QUERY)
              filters[QUERY].text=options.search
              filters[SORT]=element("drop-down",SORT)
              filters[SORT].selected_index=options.sort=="native" and 2 or 1
              local tabs=element("tabbed-pane",TABS)
              root[TABS]=tabs
              local content=element("flow",CONTENT)
              content.children={}
              content.style.width=760
              tabs[CONTENT]=content
              if options.tab=="availability" then
                if opponent~="missing-availability-label" then
                  for index,name in ipairs(AVAILABILITY) do
                    local label=element("label",name)
                    label.caption={"mir-browser.availability-entry",
                      {"technology-name.more-infinite-research."..AVAILABILITY_FAMILIES[index]},
                      {"mir-browser.availability-requires-space-age"}}
                    content[name]=label
                    content.children[#content.children+1]=label
                  end
                end
                if opponent=="extra-availability-label" then
                  content.children[#content.children+1]=element("label","mir_library_availability_unexpected")
                end
                target.gui.screen[ROOT_NAME]=root
                return
              end
              assert(options.visibility==1,"ordinary Library opens must reset Availability visibility")
              local results=element("list-box",RESULTS)
              results.items={options.selected};results.selected_index=1
              content[RESULTS]=results
              local detail=element("flow",DETAIL)
              detail.style.width=content.style.maximal_width
              if opponent=="detail-width-narrow" then detail.style.width=180 end
              detail[DETAIL_TITLE]=element("label",DETAIL_TITLE)
              detail[DETAIL_TITLE].caption=options.selected
              local context=element("flow","mir_library_detail_context")
              detail["mir_library_detail_context"]=context
              context["mir_library_context_status"]=element("label","mir_library_context_status")
              detail["mir_library_detail_level"]=element("label","mir_library_detail_level")
              content[DETAIL]=detail
              target.gui.screen[ROOT_NAME]=root
            end
            local function refresh_mock_gui(client)
              local root=client.gui.screen[ROOT_NAME]
              local filters=root and root[FILTERS]
              local query=filters and filters[QUERY]
              local tabs=root and root[TABS]
              local content=tabs and tabs[CONTENT]
              local detail=content and content[DETAIL]
              if not (root and query and detail) or query.text~=gear then return end
              local context=detail["mir_library_detail_context"]
              local queued=#force.research_queue
              local current=force.current_research~=nil
              context["mir_library_context_status"].caption={"mir-browser.context-status",{current or queued>0 and "mir-browser.status-queued" or "mir-browser.status-ready"}}
              context["mir_library_context_current"]=current and element("label","mir_library_context_current") or nil
              context["mir_library_context_queued"]=(not current and queued>0) and element("label","mir_library_context_queued") or nil
              context["mir_library_context_not_queued"]=queued==0 and element("label","mir_library_context_not_queued") or nil
              context["mir_library_context_queue_count"]=queued>0 and element("label","mir_library_context_queue_count") or nil
              context["mir_library_context_queue_position"]=queued>0 and element("label","mir_library_context_queue_position") or nil
              local level_key="mir-browser.level"
              local level=tostring(force.technologies[gear].level)
              local count,position=tostring(queued),tostring(1)
              if opponent=="caption-wrong-level-key" then level_key="mir-browser.other-level"
              elseif opponent=="caption-numeric-level" then level=force.technologies[gear].level
              elseif opponent=="caption-wrong-level" then level="99"
              elseif opponent=="caption-noncanonical-level" then level="0"..level
              elseif opponent=="caption-wrong-queue-count" then count="99"
              elseif opponent=="caption-noncanonical-queue-count" then count="0"..count
              elseif opponent=="caption-wrong-queue-position" then position="99"
              elseif opponent=="caption-noncanonical-queue-position" then position="0"..position end
              if queued>0 then
                context["mir_library_context_queue_count"].caption={"mir-browser.context-queue-count",count}
                context["mir_library_context_queue_position"].caption={"mir-browser.context-queue-position",position}
              end
              detail["mir_library_detail_level"].caption={level_key,level}
            end
            local remote={interfaces={["more-infinite-research-browser"]={open=true}}}
            remote.call=function(interface, method, index, options)
              assert(interface=="more-infinite-research-browser" and method=="open")
              open_calls=open_calls+1
              local client=players[index]
              assert(client and client.connected==true)
              build_gui(client,options)
              refresh_mock_gui(client)
              if opponent=="gameplay-mutation" then force.recipes["iron-gear-wheel"].productivity_bonus=.1 end
              if opponent=="native-witness-overwritten" then
                local witness=storage[key] and storage[key].native_initial
                if witness then witness.recipes["iron-gear-wheel"]=.1 end
              end
              return true
            end
            local function complete_mock_lab()
              local current=force.current_research
              if not current then return end
              for _,name in ipairs(gear_packs) do
                if inventory.get_item_count(name)<1 then return false end
              end
              if opponent~="no-lab-consumption" then
                for _,name in ipairs(gear_packs) do
                  inventory.counts[name]=inventory.counts[name]-1
                end
              end
              table.remove(force.research_queue,1)
              current.level=current.level+1
              force.recipes["iron-gear-wheel"].productivity_bonus=force.recipes["iron-gear-wheel"].productivity_bonus+.1
              force.current_research=force.research_queue[1]
              fire(6,{research=current,by_script=opponent=="script-completion"})
              if force.current_research then fire(4,{research=force.current_research,last_research=current}) end
              return true
            end
            local discovery=opponent=="standalone-identity-discovery"
            local active_mods={base=base_version,["more-infinite-research"]=mir_version,["mir-fixture-mir5-library-multiplayer"]=(discovery and "0.1.1" or "0.1.0"),["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            if opponent=="f210-api-consumers" then
              active_mods["mir-fixture-mir5-api-alpha"]="0.1.0"
              active_mods["mir-fixture-mir5-api-beta"]="0.1.0"
            elseif opponent=="f210-api-alpha-only" then
              active_mods["mir-fixture-mir5-api-alpha"]="0.1.0"
            elseif opponent=="f210-api-beta-only" then
              active_mods["mir-fixture-mir5-api-beta"]="0.1.0"
            elseif opponent=="f210-api-alpha-wrong-version" then
              active_mods["mir-fixture-mir5-api-alpha"]="0.1.1"
              active_mods["mir-fixture-mir5-api-beta"]="0.1.0"
            elseif opponent=="f210-api-beta-production" then
              active_mods["mir-fixture-mir5-api-alpha"]="0.1.0"
              active_mods["mir-fixture-mir5-api-beta"]="0.1.0"
              active_mods["mir-fixture-mir5-api-beta-production"]="0.1.0"
            end
            local environment={
              script={active_mods=active_mods,
                on_init=function(callback)callbacks.init=callback end,on_load=function(callback)callbacks.load=callback end,
                on_event=function(event,callback)callbacks.events[event]=callback end},
              defines={events={on_tick=1,on_player_joined_game=2,on_player_locale_changed=3,on_research_started=4,
                on_research_finished=6,on_research_cancelled=7,on_force_created=8},inventory={lab_input=1}},
              game=game,storage=storage,remote=remote,
              settings={startup={ ["mir5-library-standalone-identity-discovery"]={value=discovery} }},
              helpers={table_to_json=function(value)
                if value.science_counts then lab_diagnostics[#lab_diagnostics+1]=value
                else markers[#markers+1]=value end
                return "{}"
              end,create_profiler=create_profiler},
              log=function(value)
                if type(value)=="table" then
                  assert(value[1]=="" and value[2]=="[MIR5_LIBRARY_PROFILE] " and value[4]==" ")
                  local profiler=value[5]
                  assert(profiler.valid and profiler.running==false, 'native profiler was not stopped')
                  profiler_logs[#profiler_logs+1]={label=value[3],
                    native_output=(opponent=="profiler-variant" and "different-host-" or "host-")..profiler.ordinal}
                else
                  assert(value:match("^%[MIR5_LIBRARY_MULTIPLAYER%] RESULT ")
                    or value:match("^%[MIR5_LIBRARY_MULTIPLAYER_JOIN%] ")
                    or value:match("^%[MIR5_LIBRARY_MULTIPLAYER_LOCALE%] ")
                    or value:match("^%[MIR5_LIBRARY_STANDALONE_IDENTITY%] ")
                    or value:match("^%[MIR5_LIBRARY_LAB_DIAGNOSTIC%] "))
                end
              end,
            }
            environment._G=environment;setmetatable(environment,{__index=function(_,name)return _G[name]end})
            local chunk,message=loadfile(path,"t",environment);assert(chunk,message)
            local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)} end
            local function call(callback,event)
              local success,value=pcall(callback,event)
              return success,tostring(value)
            end
            ok,result=call(callbacks.init);if not ok then return {ok=false,message=result} end
            if opponent=="fake-connected" then
              ok,result=call(callbacks.events[2],{player_index=1})
              return {ok=ok,message=result,phase=storage[key].phase,markers=markers}
            end
            en.connected=true
            ok,result=call(callbacks.events[2],{player_index=1});if not ok then return {ok=false,message=result} end
            if opponent~="unchanged-locales" then
              ok,result=call(callbacks.events[3],{player_index=1});if not ok then return {ok=false,message=result} end
            end
            if opponent=="absent-second-client" then
              ok,result=call(callbacks.events[1]);return {ok=ok,message=result,phase=storage[key].phase,markers=markers,saves=saves}
            end
            de.connected=true
            ok,result=call(callbacks.events[2],{player_index=2});if not ok then return {ok=false,message=result} end
            if opponent~="unchanged-locales" then
              ok,result=call(callbacks.events[3],{player_index=2});if not ok then return {ok=false,message=result} end
            end
            game.tick=game.tick+120
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if discovery then
              if storage[key].phase~="standalone-identity-discovery-complete" then
                return {ok=false,message="identity discovery did not stop after the pair predicate"}
              end
              return {ok=true,phase=storage[key].phase,markers=markers,screenshots=screenshots,open_calls=open_calls}
            end
            if storage[key].phase~="capturing-availability" then return {ok=false,message="Availability capture did not retain the terminal view"} end
            game.tick=game.tick+59
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-availability" then return {ok=false,message="Availability view restored before render grace"} end
            game.tick=game.tick+1
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            local live_ready=false
            for step=1,256 do
              game.tick=game.tick+1
              if opponent~="lab-deadline" and storage[key].phase=="researching-live-research" and force.current_research
                  and (storage[key].finished==0 or (storage[key].finished==1 and storage[key].first_completion_seen)) then
                ok,result=pcall(complete_mock_lab);if not ok then return {ok=false,message=tostring(result)} end
              end
              refresh_mock_gui(en);refresh_mock_gui(de)
              if storage[key].phase=="settling-initial-view" and game.tick>=storage[key].capture_after_tick then
                if opponent=="settled-root-rebuilt" then
                  local replacement={}
                  for name,value in pairs(en.gui.screen[ROOT_NAME]) do replacement[name]=value end
                  en.gui.screen[ROOT_NAME]=replacement
                elseif opponent=="settled-native-mutation" then
                  force.recipes["burner-mining-drill"].productivity_bonus=.5
                end
              end
              ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
              if storage[key].phase=="awaiting-rejoin" then live_ready=true;break end
            end
            if opponent=="lab-deadline" then
              game.tick=storage[key].live_deadline
              force.research_progress,force.research_enabled=.25,false
              lab.energy,lab.active,lab.status=0,false,23
              lab.electric_network_id=nil
              ok,result=call(callbacks.events[1])
              return {ok=ok,message=result,lab_diagnostics=lab_diagnostics,
                energy=lab.energy,active=lab.active,progress=force.research_progress,
                research_enabled=force.research_enabled,queue_count=#force.research_queue,
                level=force.technologies[gear].level,inventory_counts=inventory.counts,
                finished=storage[key].finished}
            end
            if not live_ready then return {ok=false,message="actual Library refresh did not reach rejoin state"} end
            en.connected,de.connected=false,false
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            en.connected,de.connected=true,true
            ok,result=call(callbacks.events[2],{player_index=1});if not ok then return {ok=false,message=result} end
            ok,result=call(callbacks.events[2],{player_index=2});if not ok then return {ok=false,message=result} end
            game.tick=game.tick+120
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-rejoin" or #saves~=0 then return {ok=false,message="rejoin capture did not defer the save"} end
            game.tick=game.tick+59
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if #saves~=0 then return {ok=false,message="rejoin saved before render grace"} end
            game.tick=game.tick+1
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="awaiting-host-restart" then return {ok=false,message="rejoin phase did not request host restart"} end
            local before_load={phase=storage[key].phase,joins=storage[key].join_events,screenshots=storage[key].screenshot_calls,
              availability=storage[key].availability_checked,first=storage[key].measurements.first_open,native=storage[key].native.recipes["iron-gear-wheel"]}
            ok,result=call(callbacks.load);if not ok then return {ok=false,message=result} end
            local after_load={phase=storage[key].phase,joins=storage[key].join_events,screenshots=storage[key].screenshot_calls,
              availability=storage[key].availability_checked,first=storage[key].measurements.first_open,native=storage[key].native.recipes["iron-gear-wheel"]}
            local load_unchanged=before_load.phase==after_load.phase and before_load.joins==after_load.joins
              and before_load.screenshots==after_load.screenshots and before_load.availability==after_load.availability
              and before_load.first==after_load.first and before_load.native==after_load.native
            en.connected,de.connected=false,false
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            en.connected,de.connected=true,true
            ok,result=call(callbacks.events[2],{player_index=1});if not ok then return {ok=false,message=result} end
            ok,result=call(callbacks.events[2],{player_index=2});if not ok then return {ok=false,message=result} end
            game.tick=game.tick+120
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            if storage[key].phase~="capturing-restart" or #saves~=1 then return {ok=false,message="restart capture did not defer the save"} end
            game.tick=game.tick+60
            ok,result=call(callbacks.events[1]);if not ok then return {ok=false,message=result} end
            return {ok=true,message="",phase=storage[key].phase,markers=markers,screenshots=screenshots,saves=saves,
              load_unchanged=load_unchanged,join_events=storage[key].join_events,measurements=storage[key].measurements,
              profiler_logs=profiler_logs,lab_diagnostics=lab_diagnostics,lab_insert_counts=insert_counts,
              rejected_bulk_inserts=rejected_bulk_inserts}
          end
        ''')

    def run_case(self, opponent=None, target="f200"):
        self.lua.globals().opponent = opponent
        self.lua.globals().target = target
        return plain(self.lua.eval("run_library_multiplayer_fixture(control_path,opponent,target)"))

    def test_profiles_and_fixture_metadata_pin_the_four_finite_base_closures(self):
        cases = (
            (F200_PROFILE, FIXTURE / "info.json", "f200", "2.0", "2.0.77",
             "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B",
             "5.0.20000", "mir5-library-multiplayer-f200-native-selection", "2.0", "base >= 2.0.77", "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"),
            (CURRENT_F200_PROFILE, FIXTURE / "info.json", "f200", "2.0", "2.0.77",
             "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B",
             "5.0.20000", "mir5-library-multiplayer-current-f200-native-selection", "2.0", "base >= 2.0.77", "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"),
            (F210_PROFILE, FIXTURE / "info-f210.json", "f210", "2.1", "2.1.23",
             "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
             "5.0.21000", "mir5-library-multiplayer-f210-native-selection", "2.1", "base >= 2.1.23", "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"),
            (STANDALONE_F210_PROFILE, FIXTURE / "info-f210.json", "f210-standalone", "2.1", "2.1.23",
             "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
             "5.0.21000", "mir5-library-multiplayer-standalone-f210-native-selection", "2.1", "base >= 2.1.23", "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0"),
        )
        for profile_path, info_path, target, line, base, engine_sha, mir, kind, fixture_line, base_dependency, observer_sha in cases:
            with self.subTest(target=target):
                profile = json.loads(profile_path.read_text(encoding="utf-8"))
                info = json.loads(info_path.read_text(encoding="utf-8"))
                self.assertEqual((profile["target"], profile["factorio_line"], profile["engine"]["version"]),
                                 (target, line, base))
                self.assertEqual(profile["kind"], kind)
                self.assertEqual(profile["engine"]["sha256"], engine_sha)
                self.assertEqual(profile["mods"], [
                    {"name": "base", "version": base, "enabled": True},
                    {"name": "mir-fixture-mir5-active-mods-observer", "version": "0.1.0", "enabled": True},
                    {"name": "more-infinite-research", "version": mir, "enabled": True},
                    {"name": "mir-fixture-mir5-library-multiplayer", "version": "0.1.0", "enabled": True},
                ])
                self.assertEqual(profile["archive_sha256"], {
                    "mir-fixture-mir5-active-mods-observer_0.1.0.zip": observer_sha
                })
                self.assertEqual((info["name"], info["version"], info["factorio_version"]),
                                 ("mir-fixture-mir5-library-multiplayer", "0.1.0", fixture_line))
                self.assertEqual(info["dependencies"], [base_dependency, f"more-infinite-research = {mir}"])
                self.assertNotIn("space-age", {entry["name"] for entry in profile["mods"]})

    def test_f210_api_client_profile_binds_the_freeze_and_exact_six_mod_closure(self):
        profile = json.loads(F210_API_CONSUMERS_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile["kind"], "mir5-library-api-consumers-f210-native-selection")
        self.assertEqual((profile["target"], profile["factorio_line"], profile["settings_mode"]),
                         ("f210", "2.1", "Defaults"))
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
        })
        self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]], [
            ("base", "2.1.23", True),
            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ("more-infinite-research", "5.0.21000", True),
            ("mir-fixture-mir5-library-multiplayer", "0.1.0", True),
            ("mir-fixture-mir5-api-alpha", "0.1.0", True),
            ("mir-fixture-mir5-api-beta", "0.1.0", True),
        ])
        self.assertEqual(profile["archive_sha256"], {
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
            "more-infinite-research_5.0.21000.zip":
                "428A789CA03828D2F7F93EC65C49FD3157FD6D547CC569DDA2C0129D6504647A",
        })
        self.assertNotIn("mir-fixture-mir5-api-beta-production", {row["name"] for row in profile["mods"]})

    def test_multiplayer_wrapper_admits_only_the_frozen_complete_api_client_profile(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'
          },$true))
          if($node.Count-ne1){throw 'selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          function Read-Profile {Get-Content -LiteralPath $env:MIR_TEST_API_CLIENT_PROFILE -Raw|ConvertFrom-Json -AsHashtable}
          $engine='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060'
          $selected=Assert-MultiplayerFixtureSelection -Selection (Read-Profile) -EngineSha256 $engine -FixtureCase 'library-multiplayer'
          if($selected.kind-cne'mir5-library-api-consumers-f210-native-selection'-or$selected.api_client_consumers-ne$true){throw 'combined API client target differs'}
          function Assert-Rejected([string]$Name,[scriptblock]$Mutate){
            $selection=Read-Profile;&$Mutate $selection
            try{$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $engine -FixtureCase 'library-multiplayer'}catch{return}
            throw "combined API client profile accepted opponent: $Name"
          }
          Assert-Rejected 'alpha missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-alpha'})}
          Assert-Rejected 'beta missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-beta'})}
          Assert-Rejected 'alpha wrong version' {param($s)@($s['mods']|Where-Object {$_.name-ceq'mir-fixture-mir5-api-alpha'})[0]['version']='0.1.1'}
          Assert-Rejected 'beta production extra' {param($s)$s['mods']=@($s['mods'])+@([ordered]@{name='mir-fixture-mir5-api-beta-production';version='0.1.0';enabled=$true})}
          Assert-Rejected 'wrong frozen MIR archive' {param($s)$s['archive_sha256']['more-infinite-research_5.0.21000.zip']='A'*64}
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_API_CLIENT_PROFILE=str(F210_API_CONSUMERS_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiplayer_wrapper_admits_only_the_exact_case_bound_profiles(self):
        script = r'''
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'},$true))
          if($node.Count -ne 1){throw 'selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $f200=Get-Content -LiteralPath $env:MIR_TEST_F200_PROFILE -Raw|ConvertFrom-Json -AsHashtable
           $f200Current=Get-Content -LiteralPath $env:MIR_TEST_CURRENT_F200_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $f210=Get-Content -LiteralPath $env:MIR_TEST_F210_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $standaloneF210=Get-Content -LiteralPath $env:MIR_TEST_STANDALONE_F210_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $pairedPublished=Get-Content -LiteralPath $env:MIR_TEST_PAIRED_PUBLISHED_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $pairedMir5=Get-Content -LiteralPath $env:MIR_TEST_PAIRED_MIR5_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $scriptedEffects=Get-Content -LiteralPath $env:MIR_TEST_SCRIPTED_EFFECTS_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $selected=Assert-MultiplayerFixtureSelection -Selection $f200 -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'library-multiplayer'
          if($selected.base -cne '2.0.77' -or $selected.mir -cne '5.0.20000' -or $selected.build_version -ne 84539){throw 'F200 selection changed'}
           $selected=Assert-MultiplayerFixtureSelection -Selection $f200Current -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'library-multiplayer'
           if($selected.kind -cne 'mir5-library-multiplayer-current-f200-native-selection' -or $selected.build_version -ne 84539){throw 'current F200 selection changed'}
          $selected=Assert-MultiplayerFixtureSelection -Selection $f210 -EngineSha256 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' -FixtureCase 'library-multiplayer'
          if($selected.base -cne '2.1.23' -or $selected.mir -cne '5.0.21000' -or $selected.build_version -ne 87750){throw 'F210 selection changed'}
          $selected=Assert-MultiplayerFixtureSelection -Selection $standaloneF210 -EngineSha256 '8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38' -FixtureCase 'library-multiplayer'
          if($selected.kind -cne 'mir5-library-multiplayer-standalone-f210-native-selection' -or $selected.standalone_f210-ne$true -or $selected.observer_sha256-cne'A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'){throw 'standalone F210 selection changed'}
          $selected=Assert-MultiplayerFixtureSelection -Selection $pairedPublished -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'library-paired-browser'
          if($selected.mir -cne '4.7.20002'){throw 'published paired selection changed'}
          $selected=Assert-MultiplayerFixtureSelection -Selection $pairedMir5 -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'library-paired-browser'
          if($selected.mir -cne '5.0.20000'){throw 'MIR5 paired selection changed'}
          $selected=Assert-MultiplayerFixtureSelection -Selection $scriptedEffects -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'scripted-effects-multiplayer'
          if($selected.kind -cne 'mir5-scripted-effects-multiplayer-f200-space-age-native-selection'){throw 'scripted effects selection changed'}
          $preparedPaired=Get-Content -LiteralPath $env:MIR_TEST_PAIRED_PUBLISHED_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $preparedPaired['archive_sha256']['more-infinite-research_4.7.20002.zip']=('A'*64)
          $preparedPaired['archive_sha256']['mir-fixture-mir5-library-paired-browser_0.1.0.zip']=('B'*64)
          $preparedPaired['archive_sha256']['mir-fixture-mir5-library-paired-browser-arm-published_0.1.0.zip']=('C'*64)
          $selected=Assert-MultiplayerFixtureSelection -Selection $preparedPaired -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'library-paired-browser'
          if($selected.kind -cne 'mir5-library-paired-browser-f200-native-selection'){throw 'prepared paired archive shape changed'}
          $preparedPairedMir5=Get-Content -LiteralPath $env:MIR_TEST_PAIRED_MIR5_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $preparedPairedMir5['archive_sha256']['more-infinite-research_5.0.20000.zip']=('D'*64)
          $preparedPairedMir5['archive_sha256']['mir-fixture-mir5-library-paired-browser_0.1.0.zip']=('E'*64)
          $preparedPairedMir5['archive_sha256']['mir-fixture-mir5-library-paired-browser-arm-mir5_0.1.0.zip']=('F'*64)
          $selected=Assert-MultiplayerFixtureSelection -Selection $preparedPairedMir5 -EngineSha256 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' -FixtureCase 'library-paired-browser'
          if($selected.mir -cne '5.0.20000'){throw 'prepared MIR5 paired archive shape changed'}
          function Assert-Rejected([string]$Name,[string]$ProfilePath,[string]$Engine,[string]$Case,[scriptblock]$Mutate){
            $selection=Get-Content -LiteralPath $ProfilePath -Raw|ConvertFrom-Json -AsHashtable
            & $Mutate $selection
            $accepted=$false
            try{$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $Engine -FixtureCase $Case;$accepted=$true}catch{}
            if($accepted){throw ('selection accepted opponent: '+$Name)}
          }
          Assert-Rejected 'wrong-engine' $env:MIR_TEST_F200_PROFILE ('A'*64) 'library-multiplayer' {param($s)}
          Assert-Rejected 'wrong-mir' $env:MIR_TEST_F210_PROFILE 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' 'library-multiplayer' {param($s)$s['mods'][2]['version']='5.0.21001'}
          Assert-Rejected 'standalone-wrong-engine' $env:MIR_TEST_STANDALONE_F210_PROFILE '8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38' 'library-multiplayer' {param($s)$s['engine']['sha256']='A'*64}
          Assert-Rejected 'standalone-wrong-observer' $env:MIR_TEST_STANDALONE_F210_PROFILE '8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38' 'library-multiplayer' {param($s)$s['archive_sha256']['mir-fixture-mir5-active-mods-observer_0.1.0.zip']='A'*64}
          Assert-Rejected 'extra-space-age' $env:MIR_TEST_F210_PROFILE 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' 'library-multiplayer' {param($s)$s['mods']=@($s['mods'])+@([ordered]@{name='space-age';version='2.1.23';enabled=$true})}
          Assert-Rejected 'untyped-enabled' $env:MIR_TEST_F210_PROFILE 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' 'library-multiplayer' {param($s)$s['mods'][0]['enabled']='true'}
          Assert-Rejected 'wrong-observer' $env:MIR_TEST_F210_PROFILE 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' 'library-multiplayer' {param($s)$s['archive_sha256']['mir-fixture-mir5-active-mods-observer_0.1.0.zip']='A'*64}
          Assert-Rejected 'f210-paired' $env:MIR_TEST_F210_PROFILE 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' 'library-paired-browser' {param($s)}
          Assert-Rejected 'paired-as-functional' $env:MIR_TEST_PAIRED_PUBLISHED_PROFILE 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' 'library-multiplayer' {param($s)}
          Assert-Rejected 'scripted-as-functional' $env:MIR_TEST_SCRIPTED_EFFECTS_PROFILE 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' 'library-multiplayer' {param($s)}
          Assert-Rejected 'paired-unlisted-archive' $env:MIR_TEST_PAIRED_PUBLISHED_PROFILE 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' 'library-paired-browser' {param($s)$s['archive_sha256']['foreign_1.0.0.zip']=('A'*64)}
          Assert-Rejected 'paired-untyped-archive' $env:MIR_TEST_PAIRED_PUBLISHED_PROFILE 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' 'library-paired-browser' {param($s)$s['archive_sha256']['more-infinite-research_4.7.20002.zip']=$true}
          Assert-Rejected 'paired-arm-version' $env:MIR_TEST_PAIRED_PUBLISHED_PROFILE 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B' 'library-paired-browser' {param($s)$s['mods'][2]['version']='5.0.20000'}
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True,
            text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_F200_PROFILE=str(F200_PROFILE),
                     MIR_TEST_CURRENT_F200_PROFILE=str(CURRENT_F200_PROFILE),
                     MIR_TEST_F210_PROFILE=str(F210_PROFILE),
                     MIR_TEST_STANDALONE_F210_PROFILE=str(STANDALONE_F210_PROFILE),
                     MIR_TEST_PAIRED_PUBLISHED_PROFILE=str(PAIRED_PUBLISHED_PROFILE),
                     MIR_TEST_PAIRED_MIR5_PROFILE=str(PAIRED_MIR5_PROFILE),
                     MIR_TEST_SCRIPTED_EFFECTS_PROFILE=str(SCRIPTED_EFFECTS_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        wrapper = WRAPPER.read_text(encoding="utf-8")
        self.assertIn("build_version=$target.build_version", wrapper)
        self.assertNotIn("'last-played-version'=@{game_version=$target.base;build_version=84539", wrapper)

    def test_f210_closure_uses_the_existing_two_client_lifecycle_and_refuses_drift(self):
        accepted = self.run_case(target="f210")
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual((accepted["phase"], accepted["join_events"]), ("completed", 6))
        wrong_mir = self.run_case("f210-wrong-mir-version", target="f210")
        self.assertFalse(wrong_mir["ok"])
        self.assertIn("unexpected non-base F210 multiplayer closure", wrong_mir["message"])
        wrong_base = self.run_case("unsupported-target-base", target="f210")
        self.assertFalse(wrong_base["ok"])
        self.assertIn("unsupported native Library target base", wrong_base["message"])

    def test_standalone_identity_discovery_selection_is_opt_in_and_exactly_bound(self):
        selection = {
            "schema": 1,
            "kind": "mir5-library-standalone-identity-discovery-f210-selection",
            "target": "standalone-identity-discovery",
            "factorio_line": "2.1",
            "settings_mode": "Defaults",
            "engine": {
                "version": "2.1.23",
                "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
            },
            "mods": [
                {"name": "base", "version": "2.1.23", "enabled": True},
                {"name": "mir-fixture-mir5-active-mods-observer", "version": "0.1.0", "enabled": True},
                {"name": "more-infinite-research", "version": "5.0.21000", "enabled": True},
                {"name": "mir-fixture-mir5-library-multiplayer", "version": "0.1.1", "enabled": True},
            ],
            "archive_sha256": {
                "mir-fixture-mir5-active-mods-observer_0.1.0.zip": "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0",
                "more-infinite-research_5.0.21000.zip": "C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D",
                "mir-fixture-mir5-library-multiplayer_0.1.1.zip": "F" * 64,
            },
        }
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'},$true))
          if($node.Count-ne1){throw 'discovery selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          function Read-Discovery {Get-Content -LiteralPath $env:MIR_TEST_DISCOVERY_PROFILE -Raw|ConvertFrom-Json -AsHashtable}
          $engine='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
          $selected=Assert-MultiplayerFixtureSelection -Selection (Read-Discovery) -EngineSha256 $engine -FixtureCase 'library-multiplayer' -StandaloneIdentityDiscovery
          if($selected.target-cne'standalone-identity-discovery' -or $selected.observer_sha256-cne'A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'){throw 'discovery target differs'}
          function Assert-Rejected([string]$Name,[switch]$WithoutFlag,[scriptblock]$Mutate){
            $candidate=Read-Discovery;&$Mutate $candidate
            try{
              if($WithoutFlag){$null=Assert-MultiplayerFixtureSelection -Selection $candidate -EngineSha256 $engine -FixtureCase 'library-multiplayer'}
              else{$null=Assert-MultiplayerFixtureSelection -Selection $candidate -EngineSha256 $engine -FixtureCase 'library-multiplayer' -StandaloneIdentityDiscovery}
            }catch{return}
            throw "discovery selection accepted opponent: $Name"
          }
          Assert-Rejected 'default-route-isolation' -WithoutFlag {}
          Assert-Rejected 'wrong-engine' {$args[0]['engine']['sha256']='A'*64}
          Assert-Rejected 'wrong-mir-archive' {$args[0]['archive_sha256']['more-infinite-research_5.0.21000.zip']='A'*64}
          Assert-Rejected 'wrong-observer' {$args[0]['archive_sha256']['mir-fixture-mir5-active-mods-observer_0.1.0.zip']='A'*64}
          Assert-Rejected 'missing-fixture-archive' {$args[0]['archive_sha256'].Remove('mir-fixture-mir5-library-multiplayer_0.1.1.zip')}
          Assert-Rejected 'wrong-fixture-version' {$args[0]['mods'][3]['version']='0.1.0'}
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-standalone-identity-") as work:
            profile = Path(work) / "selection.json"
            profile.write_text(json.dumps(selection), encoding="utf-8")
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_DISCOVERY_PROFILE=str(profile)),
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_client_player_data_serializes_isolated_synthetic_names_for_both_routes(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          $loops=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.ForEachStatementAst] -and
            $candidate.Extent.Text.Contains("foreach(`$locale in @('en','de'))") -and
            $candidate.Extent.Text.Contains('player-data.json')
          },$true))
          if($loops.Count-ne1){throw 'client player-data writer loop is absent or ambiguous'}
          $loopText=$loops[0].Extent.Text
          $nameModes=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.AssignmentStatementAst] -and
            $candidate.Left.Extent.Text -ceq '$standaloneClientNames'
          },$true))
          if($nameModes.Count-ne1){throw 'client player-data name-mode assignment is absent or ambiguous'}
          $nameModeText=$nameModes[0].Extent.Text
          $sessionTokens=$null;$sessionErrors=$null
          $sessionAst=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$sessionTokens,[ref]$sessionErrors)
          if($sessionErrors.Count){throw $sessionErrors[0].Message}
          $sessionNameChecks=@($sessionAst.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.IfStatementAst] -and
            $candidate.Extent.Text.Contains('standalone identity discovery client labels differ') -and
            $candidate.Extent.Text.Contains('two client identities must be MIR5English and MIR5Deutsch')
          },$true))
          if($sessionNameChecks.Count-ne1){throw 'session client identity assertion is absent or ambiguous'}
          $sessionNameCheck=$sessionNameChecks[0].Extent.Text
          function Invoke-ClientPlayerDataWriter([bool]$Discovery,[bool]$StandaloneF210,[string]$Label){
            $root=Join-Path $env:MIR_TEST_WORK $Label;$null=New-Item -ItemType Directory -Path $root
            $resources=[pscustomobject]@{root=$root};$engineData='isolated-engine-data'
            $target=[pscustomobject]@{base='2.1.23';build_version=87750;standalone_f210=$StandaloneF210}
            $StandaloneIdentityDiscovery=$Discovery;$standaloneF210=$StandaloneF210
            Invoke-Expression $nameModeText
            $udpPorts=@(41000,41001,41002);$clientIndex=1;$clients=@()
            function New-MIRDirectLibraryStartupConfig {
              param([string]$Path,[string]$EngineDataDirectory,[string]$WriteDataDirectory,[switch]$Graphics)
              [IO.File]::WriteAllText($Path,"[path]`nread-data=$EngineDataDirectory`nwrite-data=$WriteDataDirectory`n[general]`nlocale=en`n",[Text.UTF8Encoding]::new($false))
            }
            $null=Invoke-Expression $loopText
            if($clientIndex -ne 3 -or @($clients).Count -ne 2){throw 'actual client player-data loop did not emit both clients'}
            return [pscustomobject]@{root=$root;clients=@($clients)}
          }
          function Assert-Route([object]$Route,[string[]]$ExpectedNames){
            $clients=@($Route.clients)
            if($clients.Count -ne 2){throw 'route client count differs'}
            $roots=@($clients|ForEach-Object {[string]$_.write_data})
            if(@($roots|Select-Object -Unique).Count -ne 2){throw 'client write-data roots are not distinct'}
            for($index=0;$index-lt2;$index++){
              $client=$clients[$index];$expected=$ExpectedNames[$index]
              if([string]$client.name -cne $expected){throw "client synthetic name differs: $index"}
              $player=Get-Content -LiteralPath (Join-Path $client.write_data 'player-data.json') -Raw|ConvertFrom-Json -AsHashtable
              if($player.Count -ne 3 -or -not $player.Contains('service-username') -or -not $player.Contains('service-token') -or -not $player.Contains('last-played-version')){throw 'player-data keys differ'}
              if([string]$player['service-username'] -cne $expected){throw "player-data username differs: $index"}
              if([string]$player['service-token'] -cne ''){throw "player-data token is not blank: $index"}
              $version=$player['last-played-version']
              if($version['game_version'] -cne '2.1.23' -or $version['build_version'] -ne 87750 -or $version['build_mode'] -cne 'full' -or $version['platform'] -cne 'win64'){throw "player-data version differs: $index"}
              $config=Get-Content -LiteralPath $client.config -Raw
              if($config -notmatch ('(?m)^write-data='+[regex]::Escape([string]$client.write_data)+'$')){throw "config write-data differs: $index"}
            }
          }
          function Assert-GeneratedSessionIdentity([object]$Route,[bool]$Discovery,[bool]$Expected){
            function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
            $names=[Collections.Generic.List[string]]::new()
            foreach($client in @($Route.clients)){$null=$names.Add([string]$client.name)}
            $standaloneIdentityDiscovery=$Discovery
            $accepted=$true
            try{Invoke-Expression $sessionNameCheck}catch{$accepted=$false}
            if($accepted-ne$Expected){throw "actual session identity assertion differs: discovery=$Discovery expected=$Expected"}
          }
          Assert-Route (Invoke-ClientPlayerDataWriter $true $false 'discovery') @('standalone-en','standalone-de')
          $normalStandalone=Invoke-ClientPlayerDataWriter $false $true 'standalone-normal'
          Assert-Route $normalStandalone @('MIR5English','MIR5Deutsch')
          Assert-Route (Invoke-ClientPlayerDataWriter $false $false 'functional') @('MIR5English','MIR5Deutsch')
          Assert-GeneratedSessionIdentity $normalStandalone $false $true
          Assert-GeneratedSessionIdentity (Invoke-ClientPlayerDataWriter $true $false 'discovery-session') $true $true
          Assert-GeneratedSessionIdentity (Invoke-ClientPlayerDataWriter $true $false 'wrong-normal-session') $false $false
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-identity-player-data-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_SESSION=str(SESSION), MIR_TEST_WORK=work), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_normal_route_projects_a15_and_never_requests_steam_identity(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          $projection=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.IfStatementAst] -and $candidate.Extent.Text.Contains('New-StandaloneIdentityObserverSourceProjection') -and $candidate.Extent.Text.Contains('$standaloneF210')},$true))
          if($projection.Count-ne1){throw 'standalone normal observer projection route is absent or ambiguous'}
          $fixtureProjection=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.IfStatementAst] -and $candidate.Extent.Text.Contains('New-StandaloneF210LibraryFixtureSourceProjection') -and $candidate.Extent.Text.Contains('StagedLibraryFixtureSource $standaloneLibraryFixture.source')},$true))
          if($fixtureProjection.Count-ne1){throw 'standalone normal F210 fixture projection route is absent or ambiguous'}
          $steam=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.IfStatementAst] -and $candidate.Extent.Text.Contains('FactorioSteamIdentity')},$true))
          if($steam.Count-ne1){throw 'Steam identity launch gate is absent or ambiguous'}
          function Assert-SteamGate([bool]$Discovery,[bool]$Standalone,[bool]$Expected){
            $StandaloneIdentityDiscovery=$Discovery;$standaloneF210=$Standalone;$processArguments=@{}
            Invoke-Expression $steam[0].Extent.Text
            if($processArguments.ContainsKey('FactorioSteamIdentity')-ne$Expected){throw "Steam identity gate differs: discovery=$Discovery standalone=$Standalone"}
          }
          Assert-SteamGate $false $false $true
          Assert-SteamGate $true $false $false
          Assert-SteamGate $false $true $false
          'PASS standalone normal route and Steam identity gate'
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_f210_normal_preparation_projects_the_runtime_fixture_through_the_real_archive_guard(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          function Get-MIRImmutableInputSha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
          . $env:MIR_TEST_LIBRARY_ACTIVATION
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          foreach($name in @('New-StandaloneF210LibraryFixtureSourceProjection','New-StandaloneIdentityObserverSourceProjection','Get-StandaloneIdentityFixtureSources','Invoke-MultiplayerFixturePreparation')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true))
            if($node.Count-ne1){throw "standalone normal function is absent or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          function New-SourceArchive([string]$Library,[string]$Source,[string[]]$Members){
            $info=Get-Content -LiteralPath (Join-Path $Source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
            $archive=Join-Path $Library ($info.name+'_'+$info.version+'.zip')
            $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{
              $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
              try{foreach($name in $Members){$entry=$zip.CreateEntry($info.name+'_'+$info.version+'/'+$name,[IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();$input=[IO.File]::OpenRead((Join-Path $Source $name));try{$input.CopyTo($entryStream)}finally{$input.Dispose();$entryStream.Dispose()}}}finally{$zip.Dispose()}
            }finally{$stream.Dispose()}
            return $archive
          }
          function Invoke-ActualNormalPreparation([string]$Library,[string[]]$Sources,[string]$Root){
            Invoke-MultiplayerFixturePreparation -ArchiveLibrary $Library -FactorioBin 'engine' -ProfilePath 'profile' -FixtureSources $Sources -ExpectedMIRArchiveSha256 ('A'*64) -FixtureCase 'library-multiplayer' -PreparationRoot (Join-Path $Root 'preparation') -RepoRoot $env:MIR_TEST_REPO -CreateOnlyInvoker {
              param($NativeArguments)
              foreach($source in @($NativeArguments.FixtureSources)){
                $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
                Assert-MIRLibraryFixtureArchive -Archive (Join-Path $NativeArguments.ArchiveLibrary ($info.name+'_'+$info.version+'.zip')) -SourceDirectory $source
              }
              $null=New-Item -ItemType Directory -Path (Join-Path $NativeArguments.OutputRoot 'write-data/saves') -Force
              $seed=Join-Path $NativeArguments.OutputRoot 'write-data/saves/seed.zip';[IO.File]::WriteAllBytes($seed,[byte[]]@(1,2,3))
              [IO.File]::WriteAllText((Join-Path $NativeArguments.OutputRoot 'result.json'),([ordered]@{status='passed-private-native-runtime-load-only';seed_sha256=(Get-FileHash -LiteralPath $seed -Algorithm SHA256).Hash}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            }
          }
          function Assert-PreparationRejects([string]$Name,[string]$Library,[string]$Source,[string]$Root){
            $rejected=$false;try{Invoke-ActualNormalPreparation -Library $Library -Sources @($Source) -Root $Root|Out-Null}catch{$rejected=$true};if(-not$rejected){throw "actual normal preparation accepted opponent: $Name"}
          }
          $root=$env:MIR_TEST_WORK;$repo=$env:MIR_TEST_REPO;$library=Join-Path $root 'library';$null=New-Item -ItemType Directory -Path $library
          $normal=New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $repo -OutputRoot (Join-Path $root 'normal-output')
          $normalInfo=Get-Content -LiteralPath (Join-Path $normal.source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
          if($normal.members.Count-ne3 -or $normal.source_metadata-cne'info-f210.json' -or ((@($normal.excluded_canonical_members)-join'|')-cne'README.md|info.json') -or [string]$normalInfo.factorio_version-cne'2.1' -or ((@($normalInfo.dependencies)-join'|')-cne'base >= 2.1.23|more-infinite-research = 5.0.21000')){throw 'normal F210 projection metadata differs'}
          $fixtureArchive=New-SourceArchive -Library $library -Source $normal.source -Members @('control.lua','info.json','settings-updates.lua')
          $canonicalObserver=Join-Path $repo 'tests/fixtures/active-mods-observer';$observerArchive=New-SourceArchive -Library $library -Source $canonicalObserver -Members @('data-final-fixes.lua','info.json')
          $observerHash=(Get-FileHash -LiteralPath $observerArchive -Algorithm SHA256).Hash
          $observer=New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'observer-output') -ExpectedArchiveSha256 $observerHash
          $canonicalLibrary=Join-Path $repo 'tests/fixtures/library-multiplayer'
          $sources=@(Get-StandaloneIdentityFixtureSources -Sources @($canonicalLibrary,$canonicalObserver) -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $normal.source -StagedObserverSource $observer.source -RepoRoot $repo)
          $prepared=Invoke-ActualNormalPreparation -Library $library -Sources $sources -Root (Join-Path $root 'positive')
          if($prepared.prepared.status-cne'passed-private-native-runtime-load-only' -or $sources.Count-ne2 -or $sources[0]-ine$normal.source -or $sources[1]-ine$observer.source){throw 'actual normal preparation did not retain the two exact projections'}
          $missingLibrary=Join-Path $root 'missing-library';$null=New-Item -ItemType Directory -Path $missingLibrary;New-SourceArchive -Library $missingLibrary -Source $normal.source -Members @('control.lua','info.json')|Out-Null
          Assert-PreparationRejects 'missing runtime member' $missingLibrary $normal.source (Join-Path $root 'missing')
          $changedSource=Join-Path $root 'changed-source';Copy-Item -LiteralPath $normal.source -Destination $changedSource -Recurse;[IO.File]::AppendAllText((Join-Path $changedSource 'control.lua'),'-- changed',[Text.UTF8Encoding]::new($false))
          $changedLibrary=Join-Path $root 'changed-library';$null=New-Item -ItemType Directory -Path $changedLibrary;New-SourceArchive -Library $changedLibrary -Source $normal.source -Members @('control.lua','info.json','settings-updates.lua')|Out-Null
          Assert-PreparationRejects 'changed runtime Lua' $changedLibrary $changedSource (Join-Path $root 'changed')
          $wrongRepo=Join-Path $root 'wrong-target-repo';$wrongFixture=Join-Path $wrongRepo 'tests/fixtures/library-multiplayer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $wrongFixture) -Force;Copy-Item -LiteralPath $canonicalLibrary -Destination $wrongFixture -Recurse
          $wrongInfo=Get-Content -LiteralPath (Join-Path $wrongFixture 'info-f210.json') -Raw|ConvertFrom-Json -AsHashtable;$wrongInfo.factorio_version='2.0';[IO.File]::WriteAllText((Join-Path $wrongFixture 'info-f210.json'),($wrongInfo|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
          $wrongRejected=$false;try{New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $wrongRepo -OutputRoot (Join-Path $root 'wrong-output')|Out-Null}catch{$wrongRejected=$true};if(-not$wrongRejected){throw 'F200 fixture metadata was accepted for standalone F210 projection'}
          'PASS actual normal standalone F210 preparation and projection opponents'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-standalone-normal-preparation-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_REPO=str(ROOT), MIR_TEST_WORK=work,
                         MIR_TEST_LIBRARY_ACTIVATION=str(ROOT / "tools/lib/compatibility/LibraryActivation.ps1")), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_identity_fixture_stage_enables_only_its_hash_bound_hidden_setting(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          function Assert-MIRLibraryFixtureArchive([string]$Archive,[string]$SourceDirectory){
            if(-not(Test-Path -LiteralPath $Archive -PathType Leaf)){throw 'fixture archive is absent'}
            $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
            try{
              $prefix='mir-fixture-mir5-library-multiplayer_0.1.1/'
              $required=@('info.json','control.lua','settings-updates.lua','README.md')
              foreach($name in $required){if($null-eq$zip.GetEntry($prefix+$name)){throw "fixture archive member absent: $name"}}
            }finally{$zip.Dispose()}
          }
          foreach($name in @('Assert-StandaloneIdentityFixtureSource','New-StandaloneIdentityFixtureStage')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true))
            if($node.Count-ne1){throw "staging function is absent or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $stage=New-StandaloneIdentityFixtureStage -Sources @($env:MIR_TEST_LIBRARY_FIXTURE) -OutputRoot $env:MIR_TEST_STAGE_ROOT
          $info=Get-Content -LiteralPath (Join-Path $stage.source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
          $settings=Get-Content -LiteralPath (Join-Path $stage.source 'settings-updates.lua') -Raw
          if($info.version-cne'0.1.1' -or $info.factorio_version-cne'2.1' -or $settings-notmatch'(?s)mir5-library-standalone-identity-discovery.*?default_value\s*=\s*true'){throw 'staged fixture does not bind the discovery-only setting'}
          if((Get-FileHash -LiteralPath $stage.archive -Algorithm SHA256).Hash.ToUpperInvariant()-cne$stage.sha256){throw 'staged fixture archive hash differs'}
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-identity-stage-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_LIBRARY_FIXTURE=str(FIXTURE),
                         MIR_TEST_STAGE_ROOT=str(Path(work) / "output")),
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_identity_fixture_sources_require_the_canonical_observer_once(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Get-StandaloneIdentityFixtureSources'},$true))
          if($node.Count-ne1){throw 'discovery fixture-source binder is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $repo=$env:MIR_TEST_REPO
          $library=Join-Path $repo 'tests/fixtures/library-multiplayer'
          $observer=Join-Path $repo 'tests/fixtures/active-mods-observer'
          $accepted=@(Get-StandaloneIdentityFixtureSources -Sources @($library) -LibraryFixtureSource $library -StagedLibraryFixtureSource $library -StagedObserverSource $observer -RepoRoot $repo)
          if($accepted.Count-ne2 -or $accepted[0]-ine$library -or $accepted[1]-ine$observer){throw 'canonical observer was not appended exactly once'}
          function Assert-Rejects([string]$Name,[scriptblock]$Block){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "discovery observer source accepted opponent: $Name"}}
          $missingRepo=Join-Path $env:MIR_TEST_WORK 'missing-repository';$null=New-Item -ItemType Directory -Path (Join-Path $missingRepo 'tests/fixtures') -Force
          Assert-Rejects 'missing canonical observer' {Get-StandaloneIdentityFixtureSources -Sources @($library) -LibraryFixtureSource $library -StagedLibraryFixtureSource $library -StagedObserverSource $observer -RepoRoot $missingRepo|Out-Null}
          $wrong=Join-Path $env:MIR_TEST_WORK 'wrong-observer';Copy-Item -LiteralPath $observer -Destination $wrong -Recurse
          Assert-Rejects 'wrong observer source' {Get-StandaloneIdentityFixtureSources -Sources @($library,$wrong) -LibraryFixtureSource $library -StagedLibraryFixtureSource $library -StagedObserverSource $observer -RepoRoot $repo|Out-Null}
          Assert-Rejects 'duplicate observer source' {Get-StandaloneIdentityFixtureSources -Sources @($library,$observer,$observer) -LibraryFixtureSource $library -StagedLibraryFixtureSource $library -StagedObserverSource $observer -RepoRoot $repo|Out-Null}
          'PASS standalone identity canonical observer source binding'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-identity-observer-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_REPO=str(ROOT), MIR_TEST_WORK=work), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_identity_observer_projection_requires_hash_bound_canonical_members(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Assert-MIRLibraryFixtureArchive([string]$Archive,[string]$SourceDirectory){
            $names=@(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File|ForEach-Object {[IO.Path]::GetRelativePath($SourceDirectory,$_.FullName).Replace('\','/')}|Sort-Object)
            if(($names-join'|')-cne'data-final-fixes.lua|info.json'){throw 'projection is not the exact two-member source'}
          }
          $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'New-StandaloneIdentityObserverSourceProjection'},$true))
          if($node.Count-ne1){throw 'observer projection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $repo=$env:MIR_TEST_REPO
          $library=Join-Path $env:MIR_TEST_WORK 'library';$null=New-Item -ItemType Directory -Path $library
          $canonical=Join-Path $repo 'tests/fixtures/active-mods-observer'
          $archive=Join-Path $library 'mir-fixture-mir5-active-mods-observer_0.1.0.zip'
          $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
          try {
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
            try {
              foreach($name in @('data-final-fixes.lua','info.json')){
                $entry=$zip.CreateEntry('mir-fixture-mir5-active-mods-observer_0.1.0/'+$name,[IO.Compression.CompressionLevel]::Optimal)
                $entryStream=$entry.Open();$input=[IO.File]::OpenRead((Join-Path $canonical $name))
                try{$input.CopyTo($entryStream)}finally{$input.Dispose();$entryStream.Dispose()}
              }
            } finally {$zip.Dispose()}
          } finally {$stream.Dispose()}
          $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()
          $positiveRoot=Join-Path $env:MIR_TEST_WORK 'positive';$null=New-Item -ItemType Directory -Path $positiveRoot
          $projection=New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot $positiveRoot -ExpectedArchiveSha256 $hash
          if($projection.sha256-cne$hash -or $projection.alternate_metadata-cne'info-f200.json' -or $projection.members.Count-ne2){throw 'projection lost hash-bound canonical observer facts'}
          function Assert-Rejects([string]$Name,[scriptblock]$Block){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "observer projection accepted opponent: $Name"}}
          $changedRepo=Join-Path $env:MIR_TEST_WORK 'changed-repo';$changedSource=Join-Path $changedRepo 'tests/fixtures/active-mods-observer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $changedSource) -Force;Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/active-mods-observer') -Destination $changedSource -Recurse
          [IO.File]::AppendAllText((Join-Path $changedSource 'data-final-fixes.lua'),'-- altered',[Text.UTF8Encoding]::new($false))
          Assert-Rejects 'altered canonical member' {New-StandaloneIdentityObserverSourceProjection -RepoRoot $changedRepo -ArchiveLibrary $library -OutputRoot (Join-Path $env:MIR_TEST_WORK 'changed-output') -ExpectedArchiveSha256 $hash|Out-Null}
          $missingRepo=Join-Path $env:MIR_TEST_WORK 'missing-repo';$missingSource=Join-Path $missingRepo 'tests/fixtures/active-mods-observer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $missingSource) -Force;Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/active-mods-observer') -Destination $missingSource -Recurse;Remove-Item -LiteralPath (Join-Path $missingSource 'data-final-fixes.lua') -Force
          Assert-Rejects 'missing canonical member' {New-StandaloneIdentityObserverSourceProjection -RepoRoot $missingRepo -ArchiveLibrary $library -OutputRoot (Join-Path $env:MIR_TEST_WORK 'missing-output') -ExpectedArchiveSha256 $hash|Out-Null}
          $extraLibrary=Join-Path $env:MIR_TEST_WORK 'extra-library';$null=New-Item -ItemType Directory -Path $extraLibrary;$extraArchive=Join-Path $extraLibrary 'mir-fixture-mir5-active-mods-observer_0.1.0.zip';Copy-Item -LiteralPath $archive -Destination $extraArchive
          $zip=[IO.Compression.ZipFile]::Open($extraArchive,[IO.Compression.ZipArchiveMode]::Update);try{$writer=[IO.StreamWriter]::new($zip.CreateEntry('mir-fixture-mir5-active-mods-observer_0.1.0/unexpected.lua').Open());try{$writer.Write('-- unexpected')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
          $extraHash=(Get-FileHash -LiteralPath $extraArchive -Algorithm SHA256).Hash
          Assert-Rejects 'extra archive member' {New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $extraLibrary -OutputRoot (Join-Path $env:MIR_TEST_WORK 'extra-output') -ExpectedArchiveSha256 $extraHash|Out-Null}
          'PASS standalone identity observer projection members'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-identity-observer-projection-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_REPO=str(ROOT), MIR_TEST_WORK=work), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0", WRAPPER.read_text(encoding="utf-8"))

    def test_standalone_identity_bad_preparation_result_removes_only_the_owned_archive(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Invoke-MultiplayerFixturePreparation'},$true))
          if($node.Count-ne1){throw 'preparation cleanup function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $script:installed=0;$script:removed=0
          function Install-StandaloneIdentityFixtureArchive {param($Library,$Fixture)$script:installed++;[pscustomobject]@{path='owned-0.1.1.zip';sha256=$Fixture.sha256;removed=$false}}
          function Remove-StandaloneIdentityFixtureArchive {param($Install)$script:removed++;if($Install.path-ne'owned-0.1.1.zip' -or $Install.removed){throw 'cleanup targeted an unexpected archive'};$Install.removed=$true}
          $root=Join-Path $env:MIR_TEST_WORK 'bad-preparation';$null=New-Item -ItemType Directory -Path $root
          $rejected=$false
          try {
            Invoke-MultiplayerFixturePreparation -ArchiveLibrary 'library' -FactorioBin 'engine' -ProfilePath 'profile' -FixtureSources @('fixture') -ExpectedMIRArchiveSha256 ('A'*64) -FixtureCase 'library-multiplayer' -PreparationRoot (Join-Path $root 'preparation') -RepoRoot 'repo' -StandaloneIdentityDiscovery -DiscoveryFixture ([pscustomobject]@{source='staged';archive='owned';sha256=('B'*64)}) -CreateOnlyInvoker {
              param($NativeArguments)
              if(-not$NativeArguments.CreateOnly -or $NativeArguments.ActiveModsObserver-cne'mir-fixture-mir5-active-mods-observer'){throw 'mock did not receive the actual CreateOnly contract'}
              $null=New-Item -ItemType Directory -Path $NativeArguments.OutputRoot
              [IO.File]::WriteAllText((Join-Path $NativeArguments.OutputRoot 'result.json'),'{"status":"bad-preparation-result"}',[Text.UTF8Encoding]::new($false))
            }|Out-Null
          } catch {$rejected=$true}
          if(-not$rejected -or $script:installed-ne1 -or $script:removed-ne1){throw 'bad preparation result did not clean up its single owned discovery archive'}
          'PASS standalone identity bad preparation cleanup'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-identity-cleanup-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_WORK=work), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_identity_discovery_stops_after_the_real_pair_before_gui_work(self):
        result = self.run_case("standalone-identity-discovery", target="f210")
        self.assertTrue(result["ok"], result.get("message"))
        self.assertEqual(result["phase"], "standalone-identity-discovery-complete")
        self.assertFalse(result["screenshots"])
        self.assertEqual(result["open_calls"], 0)
        self.assertEqual(len(result["markers"]), 2)
        marker = next(item for item in result["markers"] if item["stage"] == "identity-discovery")
        self.assertEqual(marker["stage"], "identity-discovery")
        self.assertEqual(marker["status"], "passed")
        self.assertEqual(marker["ticks_after_last_join"], 120)
        self.assertFalse(marker["personal_state_checked"])
        self.assertTrue(marker["stop_before_initial_gui"])
        self.assertEqual(marker["screenshot_calls"], 0)
        self.assertEqual(
            [(item["index"], item["locale"], item["force_index"]) for item in marker["players"]],
            [(1, "en", 1), (2, "de", 1)],
        )
        self.assertEqual(len({item["name"] for item in marker["players"]}), 2)

    def test_standalone_identity_discovery_reader_requires_the_real_pair_and_zero_gui_work(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          foreach($name in @('Test-LibraryInteger','Get-StandaloneIdentityDiscoveryMarker')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true))
            if($node.Count-ne1){throw "identity discovery reader is absent or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          function New-Marker {
            [ordered]@{case='library-multiplayer';stage='identity-discovery';status='passed';ticks_after_last_join=120
              two_connected_clients_required=$true;personal_state_checked=$false;stop_before_initial_gui=$true
              shared_force_index=1;screenshot_calls=0;players=@(
                [ordered]@{index=1;name='Actual English!?';locale='en';force_index=1},
                [ordered]@{index=2;name='Deutsch 名';locale='de';force_index=1}
              )}
          }
          $line='[MIR5_LIBRARY_STANDALONE_IDENTITY] '+((New-Marker)|ConvertTo-Json -Depth 8 -Compress)
          $accepted=Get-StandaloneIdentityDiscoveryMarker $line
          if($accepted.players.Count-ne2 -or $accepted.screenshot_calls-ne0){throw 'identity marker lost accepted bounded facts'}
          foreach($mutate in @(
            {param($row)$row.screenshot_calls=1},
            {param($row)$row.players[1].force_index=2},
            {param($row)$row.players[1].name=$row.players[0].name},
            {param($row)$row.players[0].name=''},
            {param($row)$row.personal_state_checked=$true},
            {param($row)$row.stop_before_initial_gui=$false}
          )){
            $row=New-Marker;&$mutate $row
            $candidate='[MIR5_LIBRARY_STANDALONE_IDENTITY] '+($row|ConvertTo-Json -Depth 8 -Compress)
            $rejected=$false;try{$null=Get-StandaloneIdentityDiscoveryMarker $candidate}catch{$rejected=$true}
            if(-not$rejected){throw 'identity marker accepted a discovery opponent'}
          }
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SESSION=str(SESSION)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_identity_discovery_binding_accepts_json_integer_roundtrip_only(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          foreach($name in @('Test-LibraryInteger')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true))
            if($node.Count-ne1){throw "identity discovery reader is absent or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $binding=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.IfStatementAst] -and
            $candidate.Extent.Text.Contains('standalone identity discovery binding is absent')
          },$true))
          if($binding.Count-ne1){throw 'identity discovery binding reader is absent or ambiguous'}
          $bindingText=$binding[0].Extent.Text
          $wrapperSpec=[ordered]@{
            standalone_identity_discovery=$true
            identity_discovery=[ordered]@{
              engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
              mir_archive_sha256='C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D'
              observer_archive_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
              fixture_version='0.1.1';join_budget_seconds=180;environmental_only=$true
            }
          }
          function New-BindingSpec {
            (($wrapperSpec|ConvertTo-Json -Depth 8 -Compress)|ConvertFrom-Json -AsHashtable)
          }
          function Invoke-BindingReader([hashtable]$Candidate){
            $fixtureCase='library-multiplayer'
            $spec=$Candidate
            $standaloneIdentityDiscovery=$false
            $identityBinding=$null
            Invoke-Expression $bindingText
            return [pscustomobject]@{standalone=$standaloneIdentityDiscovery;binding=$identityBinding}
          }
          $acceptedSpec=New-BindingSpec
          if($acceptedSpec.identity_discovery.join_budget_seconds -isnot [long]){throw 'actual JSON roundtrip did not use Int64 budget'}
          $accepted=Invoke-BindingReader $acceptedSpec
          if(-not $accepted.standalone -or $accepted.binding.join_budget_seconds -ne 180){throw 'actual JSON identity binding was not admitted'}
          foreach($field in @('engine_sha256','mir_archive_sha256','observer_archive_sha256','fixture_version','environmental_only')){
            if($accepted.binding[$field].GetType()-ne$acceptedSpec.identity_discovery[$field].GetType()){throw "identity field type changed: $field"}
          }
          $mutations=@(
            @{field='engine_sha256';value='0'*64},
            @{field='fixture_version';value='0.1.2'},
            @{field='environmental_only';value=$false},
            @{field='join_budget_seconds';value=$true},
            @{field='join_budget_seconds';value='180'},
            @{field='join_budget_seconds';value=180.5},
            @{field='join_budget_seconds';value=[double]::NaN},
            @{field='join_budget_seconds';value=[double]::PositiveInfinity},
            @{field='join_budget_seconds';value=181}
          )
          foreach($mutation in $mutations){
            $candidate=New-BindingSpec
            $candidate.identity_discovery[$mutation.field]=$mutation.value
            $rejected=$false;try{$null=Invoke-BindingReader $candidate}catch{$rejected=$true}
            if(-not$rejected){throw "identity binding accepted invalid $($mutation.field)"}
          }
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SESSION=str(SESSION)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_f210_api_consumer_closure_requires_both_exact_independent_consumers(self):
        accepted = self.run_case("f210-api-consumers", target="f210")
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual((accepted["phase"], accepted["join_events"]), ("completed", 6))
        for opponent in ("f210-api-alpha-only", "f210-api-beta-only", "f210-api-alpha-wrong-version",
                         "f210-api-beta-production"):
            with self.subTest(opponent=opponent):
                rejected = self.run_case(opponent, target="f210")
                self.assertFalse(rejected["ok"])
                self.assertIn("unexpected non-base F210 multiplayer closure", rejected["message"])

    def test_two_real_client_join_rejoin_and_restart_state_machine(self):
        result = self.run_case()
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((result["phase"], result["join_events"]), ("completed", 6))
        self.assertTrue(result["load_unchanged"])
        self.assertEqual([item["stage"] for item in result["markers"]], ["ready", "rejoin-ready", "restart-ready", "completed"])
        completed = result["markers"][-1]["witnesses"]
        self.assertTrue(completed["on_load_read_only"])
        self.assertTrue(completed["availability_terminal_labels_checked"])
        self.assertEqual(completed["screenshot_calls"], 10)
        self.assertTrue(completed["initial_settled_without_reopen"])
        self.assertEqual(completed["initial_settle_ticks"], 60)
        self.assertEqual(result["saves"], ["mir5-library-multiplayer-restart", "mir5-native-complete"])
        live_refresh = completed["live_refresh"]
        self.assertEqual(live_refresh["real_lab_completions"], 2)
        self.assertFalse(live_refresh["native_laboratory_completion_by_script"])
        self.assertGreaterEqual(live_refresh["native_research_started_events"], 2)
        self.assertEqual(live_refresh["queue_lengths_observed"], [2, 1, 0])
        self.assertEqual(live_refresh["native_research_cancelled_events"], 1)
        self.assertEqual(live_refresh["native_foreign_force_created_events"], 1)
        self.assertEqual(live_refresh["gear_level"], 3)
        self.assertAlmostEqual(live_refresh["gear_productivity"], .2)
        self.assertEqual(live_refresh["science_consumed_per_named_pack"], 2)
        self.assertTrue(live_refresh["fixture_accelerates_gear_count_and_time_only"])
        self.assertFalse(live_refresh["ordinary_tuning_qualified"])
        self.assertTrue(live_refresh["root_and_query_identity_preserved"])
        self.assertTrue(live_refresh["cross_force_view_state_preserved"])
        self.assertEqual(set(result["measurements"]), {"first_open", "search", "refresh", "reopen"})
        self.assertTrue(all(value is True for value in result["measurements"].values()))
        self.assertEqual([row["label"] for row in result["profiler_logs"]],
                         ["first_open", "search", "refresh", "reopen"])
        self.assertEqual(len(result["screenshots"]), 10)
        self.assertEqual([row["stage"] for row in result["lab_diagnostics"]], ["queued"])
        self.assertEqual(
            {stage: sum(f"/{stage}-" in item["path"] for item in result["screenshots"])
             for stage in ("availability", "initial", "settled", "rejoin", "restart")},
            {"availability": 2, "initial": 2, "settled": 2, "rejoin": 2, "restart": 2},
        )
        for screenshot in result["screenshots"]:
            self.assertTrue(screenshot["player_matches"])
            self.assertTrue(screenshot["show_gui"])
            self.assertTrue(screenshot["force_render"])
            self.assertEqual(screenshot["resolution"], [1280, 720])
            self.assertRegex(screenshot["path"], r"^mir5-library-multiplayer/(availability|initial|settled|rejoin|restart)-[12]\.png$")

    def test_settled_capture_keeps_original_views_and_checks_native_state_before_rejoin(self):
        result = self.run_case()
        self.assertTrue(result["ok"], result["message"])
        captures = {item["path"]: item for item in result["screenshots"]}
        for player in (1, 2):
            initial = captures[f"mir5-library-multiplayer/initial-{player}.png"]
            settled = captures[f"mir5-library-multiplayer/settled-{player}.png"]
            self.assertEqual(settled["tick"] - initial["tick"], 60)
            self.assertEqual(settled["open_calls"], initial["open_calls"])
        self.assertFalse(result["markers"][0]["witnesses"]["initial_settled_without_reopen"])
        self.assertNotIn("initial_settle_ticks", result["markers"][0]["witnesses"])
        for marker in result["markers"][1:]:
            self.assertTrue(marker["witnesses"]["initial_settled_without_reopen"])
            self.assertEqual(marker["witnesses"]["initial_settle_ticks"], 60)
        for opponent, error in (
            ("settled-root-rebuilt", "native Library refresh replaced the owned root or query"),
            ("settled-native-mutation", "public Library browsing mutated native research, queue, or recipe effects"),
        ):
            with self.subTest(opponent=opponent):
                failed = self.run_case(opponent)
                self.assertFalse(failed["ok"])
                self.assertIn(error, failed["message"])

    def test_native_detail_width_must_match_the_research_content_before_captures(self):
        result = self.run_case()
        self.assertTrue(result["ok"], result["message"])
        failed = self.run_case("detail-width-narrow")
        self.assertFalse(failed["ok"])
        self.assertIn("native public browser detail width differs", failed["message"])

    def test_lab_deadline_logs_native_state_without_repair_or_success(self):
        result = self.run_case("lab-deadline")
        self.assertFalse(result["ok"])
        self.assertIn("actual Library refresh laboratory exceeded deadline", result["message"])
        self.assertEqual([row["stage"] for row in result["lab_diagnostics"]], ["queued", "deadline"])
        snapshot = result["lab_diagnostics"][-1]
        self.assertEqual(snapshot["phase"], "researching-live-research")
        self.assertEqual((snapshot["started"], snapshot["finished"]), (1, 0))
        self.assertEqual(snapshot["lab"], {"valid": True, "active": False, "energy": 0,
                                         "status": 23, "electric_network_id": False})
        self.assertEqual(snapshot["research"], {"enabled": False, "current": "recipe-prod-research_gears-1",
            "progress": .25, "queue_count": 2, "queue": ["recipe-prod-research_gears-1"] * 2})
        self.assertEqual(snapshot["gear"], {"level": 1, "enabled": True, "count": 1, "energy": 60})
        self.assertEqual(snapshot["science_counts"], result["inventory_counts"])
        self.assertEqual(set(snapshot["science_counts"].values()), {1})
        self.assertEqual((result["energy"], result["active"], result["progress"], result["research_enabled"],
                          result["queue_count"], result["level"], result["finished"]),
                         (0, False, .25, False, 2, 1, 0))

    def test_native_session_reader_accepts_actual_library_markers_and_rejects_mutations(self):
        results = {target: self.run_case(target=target) for target in ("f200", "f210")}
        for target, result in results.items():
            with self.subTest(target=target):
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual([marker["stage"] for marker in result["markers"]],
                                 ["ready", "rejoin-ready", "restart-ready", "completed"])

        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $text=[IO.File]::ReadAllText($env:MIR_TEST_SESSION)
          $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $allDefinitions=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
          },$true))
          $names=@('Test-LibraryInteger','Get-LibraryWitnessTarget','Assert-LibraryWitnessIdentityMode','Assert-LibraryWitnessBoolean','Assert-LibraryWitnessInteger',
            'Assert-LibraryLiveRefresh','Get-StageMarker')
          $definitions=@{}
          foreach($name in $names){
            $matches=@($allDefinitions|Where-Object {$_.Name -ceq $name})
            if($matches.Count -ne 1){throw "reader definition missing or ambiguous: $name"}
            $definitions[$name]=$matches[0].Extent.Text
          }
          function Assert-Session([bool]$Condition,[string]$Message){
            if(-not $Condition){throw $Message}
          }
          foreach($name in $names){Invoke-Expression $definitions[$name]}
          $fixtureCase='library-multiplayer'
          $markerPrefix='MIR5_LIBRARY_MULTIPLAYER'
          $markerSets=Get-Content -LiteralPath $env:MIR_TEST_LIBRARY_MARKERS -Raw|ConvertFrom-Json -AsHashtable
          $expectedJoins=@{ready=0;'rejoin-ready'=2;'restart-ready'=4;completed=6}
          $targets=[ordered]@{
            f200=[ordered]@{engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';base='2.0.77';mir='5.0.20000'}
            f210=[ordered]@{engine_sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060';base='2.1.23';mir='5.0.21000'}
            standalone_normal=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$false}
            standalone_discovery=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$true}
          }
          function New-LibraryWitnessSpec([hashtable]$Target){
            $spec=@{library_witness_target=([ordered]@{engine_sha256=$Target.engine_sha256;base=$Target.base;mir=$Target.mir})}
            if($Target.Contains('standalone_identity_discovery') -and $Target.standalone_identity_discovery){$spec.standalone_identity_discovery=$true}
            return $spec
          }
          function Assert-LibraryWitnessTargetRejects([hashtable]$Spec,[string]$Engine,[string]$Name){
            try{$null=Get-LibraryWitnessTarget $Spec $Engine}catch{return}
            throw "reader accepted invalid witness target: $Name"
          }
          function Assert-LibraryWitnessModeRejects([bool]$ActualMode,[object]$Target,[string]$Name){
            try{Assert-LibraryWitnessIdentityMode $ActualMode $Target}catch{return}
            throw "reader accepted wrong standalone identity mode: $Name"
          }
          $normalStandalone=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $targets.standalone_normal) $targets.standalone_normal.engine_sha256
          Assert-LibraryWitnessBoolean $normalStandalone 'standalone_identity_discovery' $false 'normal standalone target'
          Assert-LibraryWitnessIdentityMode $false $normalStandalone
          $discoveryStandalone=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $targets.standalone_discovery) $targets.standalone_discovery.engine_sha256
          Assert-LibraryWitnessBoolean $discoveryStandalone 'standalone_identity_discovery' $true 'discovery standalone target'
          Assert-LibraryWitnessIdentityMode $true $discoveryStandalone
          Assert-LibraryWitnessModeRejects $true $normalStandalone 'normal target with discovery mode'
          Assert-LibraryWitnessModeRejects $false $discoveryStandalone 'discovery target with normal mode'
          $malformedStandalone=New-LibraryWitnessSpec $targets.standalone_normal;$malformedStandalone.standalone_identity_discovery='true'
          Assert-LibraryWitnessTargetRejects $malformedStandalone $targets.standalone_normal.engine_sha256 'malformed standalone mode'
          $explicitFalseStandalone=New-LibraryWitnessSpec $targets.standalone_normal;$explicitFalseStandalone.standalone_identity_discovery=$false
          Assert-LibraryWitnessTargetRejects $explicitFalseStandalone $targets.standalone_normal.engine_sha256 'explicit false standalone mode'
          foreach($targetName in @('f200','f210')){
            $target=$targets[$targetName]
            $expectedLibraryWitness=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $target) $target.engine_sha256
            if($expectedLibraryWitness.base -cne $target.base -or $expectedLibraryWitness.mir -cne $target.mir){throw "selected witness target differs: $targetName"}
            Assert-LibraryWitnessIdentityMode $false $expectedLibraryWitness
            $targetMarkers=@($markerSets[$targetName])
            if($targetMarkers.Count -ne 4){throw "actual fixture markers are incomplete: $targetName"}
            foreach($marker in $targetMarkers){
              $stage=[string]$marker['stage']
              $line='[MIR5_LIBRARY_MULTIPLAYER] RESULT '+($marker|ConvertTo-Json -Depth 20 -Compress)
              $accepted=Get-StageMarker $line $stage ([int]$expectedJoins[$stage]) $expectedLibraryWitness
              if($null -eq $accepted -or $accepted.stage -cne $stage){throw "actual fixture marker rejected: $targetName/$stage"}
            }
          }
          Assert-LibraryWitnessTargetRejects (New-LibraryWitnessSpec $targets.f210) $targets.f200.engine_sha256 'cross-base'
          $crossMir=New-LibraryWitnessSpec $targets.f210;$crossMir.library_witness_target.mir=$targets.f200.mir
          Assert-LibraryWitnessTargetRejects $crossMir $targets.f210.engine_sha256 'cross-MIR'
          Assert-LibraryWitnessTargetRejects (New-LibraryWitnessSpec $targets.f200) ('A'*64) 'unknown-engine'
          Assert-LibraryWitnessTargetRejects @{} $targets.f200.engine_sha256 'missing-target'
          $expectedLibraryWitness=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $targets.f200) $targets.f200.engine_sha256
          $markers=@($markerSets['f200'])
          function ConvertTo-LibraryMarkerLine([hashtable]$Marker){
            return '[MIR5_LIBRARY_MULTIPLAYER] RESULT '+($Marker|ConvertTo-Json -Depth 20 -Compress)
          }
          function Copy-LibraryMarker([hashtable]$Marker){
            return ($Marker|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable)
          }
          function Assert-LibraryReaderAccepts([hashtable]$Marker){
            $stage=[string]$Marker['stage']
            if(-not $expectedJoins.ContainsKey($stage)){throw "unexpected actual fixture stage: $stage"}
            $line=ConvertTo-LibraryMarkerLine $Marker
            $accepted=Get-StageMarker $line $stage ([int]$expectedJoins[$stage]) $expectedLibraryWitness
            if($null -eq $accepted -or $accepted.stage -cne $stage){throw "actual fixture marker rejected: $stage"}
          }
          function Assert-LibraryReaderRejects([hashtable]$Marker,[string]$ExpectedStage,[int]$ExpectedJoins,[string]$Name){
            # Construct the candidate marker before validation so construction errors cannot count as rejection.
            $line=ConvertTo-LibraryMarkerLine $Marker
            try{
              $accepted=Get-StageMarker $line $ExpectedStage $ExpectedJoins $expectedLibraryWitness
            }catch{return}
            if($null -ne $accepted){throw "reader accepted invalid marker: $Name"}
          }
          $byStage=@{}
          foreach($marker in $markers){
            Assert-LibraryReaderAccepts $marker
            $byStage[[string]$marker['stage']]=$marker
          }

          $minimumStarted=Copy-LibraryMarker $byStage['completed']
          $minimumStarted['witnesses']['live_refresh']['native_research_started_events']=2
          Assert-LibraryReaderAccepts $minimumStarted

          $tooFewStarted=Copy-LibraryMarker $byStage['completed']
          $tooFewStarted['witnesses']['live_refresh']['native_research_started_events']=1
          Assert-LibraryReaderRejects $tooFewStarted 'completed' 6 'too few native research starts'

          $missingImmutable=Copy-LibraryMarker $byStage['ready']
          $missingImmutable['witnesses'].Remove('initial_native_snapshot_immutable')
          Assert-LibraryReaderRejects $missingImmutable 'ready' 0 'missing immutable snapshot'

          $falseImmutable=Copy-LibraryMarker $byStage['ready']
          $falseImmutable['witnesses']['initial_native_snapshot_immutable']=$false
          Assert-LibraryReaderRejects $falseImmutable 'ready' 0 'false immutable snapshot'

          $stringJoinCount=Copy-LibraryMarker $byStage['ready']
          $stringJoinCount['witnesses']['actual_join_events']='0'
          Assert-LibraryReaderRejects $stringJoinCount 'ready' 0 'string join count'

          $wrongViews=Copy-LibraryMarker $byStage['ready']
          $wrongViews['witnesses']['distinct_personal_query_and_selection']=$false
          Assert-LibraryReaderRejects $wrongViews 'ready' 0 'cross-client view state'

          $stringTwoClients=Copy-LibraryMarker $byStage['ready']
          $stringTwoClients['witnesses']['two_connected_clients_required']='true'
          Assert-LibraryReaderRejects $stringTwoClients 'ready' 0 'string two-client witness'

          foreach($stage in @('ready','rejoin-ready','restart-ready','completed')){
            $wrongBase=Copy-LibraryMarker $byStage[$stage]
            $wrongBase['witnesses']['base_version']='2.0.76'
            Assert-LibraryReaderRejects $wrongBase $stage ([int]$expectedJoins[$stage]) "$stage base version"
            $wrongMir=Copy-LibraryMarker $byStage[$stage]
            $wrongMir['witnesses']['mir_version']='5.0.19999'
            Assert-LibraryReaderRejects $wrongMir $stage ([int]$expectedJoins[$stage]) "$stage MIR version"
            $wrongCaptures=Copy-LibraryMarker $byStage[$stage]
            $wrongCaptures['witnesses']['screenshot_calls']=99
            Assert-LibraryReaderRejects $wrongCaptures $stage ([int]$expectedJoins[$stage]) "$stage capture count"
          }

          $wrongReadyGear=Copy-LibraryMarker $byStage['ready']
          $wrongReadyGear['witnesses']['live_refresh']['gear_level']=2
          Assert-LibraryReaderRejects $wrongReadyGear 'ready' 0 'ready gear level'
          $wrongReadyProductivity=Copy-LibraryMarker $byStage['ready']
          $wrongReadyProductivity['witnesses']['live_refresh']['gear_productivity']=1
          Assert-LibraryReaderRejects $wrongReadyProductivity 'ready' 0 'ready gear productivity'
          $wrongReadyAvailability=Copy-LibraryMarker $byStage['ready']
          $wrongReadyAvailability['witnesses']['availability_terminal_labels_checked']=$true
          Assert-LibraryReaderRejects $wrongReadyAvailability 'ready' 0 'ready Availability witness'
          $prematureSettled=Copy-LibraryMarker $byStage['ready']
          $prematureSettled['witnesses']['initial_settled_without_reopen']=$true
          Assert-LibraryReaderRejects $prematureSettled 'ready' 0 'premature settled capture'
          $prematureDelay=Copy-LibraryMarker $byStage['ready']
          $prematureDelay['witnesses']['initial_settle_ticks']=60
          Assert-LibraryReaderRejects $prematureDelay 'ready' 0 'premature settled delay'
          foreach($stage in @('rejoin-ready','restart-ready','completed')){
            $unsettled=Copy-LibraryMarker $byStage[$stage]
            $unsettled['witnesses']['initial_settled_without_reopen']=$false
            Assert-LibraryReaderRejects $unsettled $stage ([int]$expectedJoins[$stage]) "$stage unsettled capture"
            foreach($delay in @(0,59,61,'60')){
              $wrongDelay=Copy-LibraryMarker $byStage[$stage]
              $wrongDelay['witnesses']['initial_settle_ticks']=$delay
              Assert-LibraryReaderRejects $wrongDelay $stage ([int]$expectedJoins[$stage]) "$stage wrong settled delay"
            }
          }
          foreach($field in @('native_laboratory_completion_by_script','science_consumed_per_named_pack',
              'fixture_accelerates_gear_count_and_time_only','ordinary_tuning_qualified',
              'root_and_query_identity_preserved','cross_force_view_state_preserved')){
            $wrong=Copy-LibraryMarker $byStage['ready']
            switch($field){
              'native_laboratory_completion_by_script' {$wrong['witnesses']['live_refresh'][$field]=$true}
              'science_consumed_per_named_pack' {$wrong['witnesses']['live_refresh'][$field]=0}
              'fixture_accelerates_gear_count_and_time_only' {$wrong['witnesses']['live_refresh'][$field]=$false}
              'ordinary_tuning_qualified' {$wrong['witnesses']['live_refresh'][$field]=$true}
              'root_and_query_identity_preserved' {$wrong['witnesses']['live_refresh'][$field]=$false}
              'cross_force_view_state_preserved' {$wrong['witnesses']['live_refresh'][$field]=$false}
            }
            Assert-LibraryReaderRejects $wrong 'ready' 0 "ready $field"
          }

          $missingLiveRefresh=Copy-LibraryMarker $byStage['rejoin-ready']
          $missingLiveRefresh['witnesses'].Remove('live_refresh')
          Assert-LibraryReaderRejects $missingLiveRefresh 'rejoin-ready' 2 'missing live refresh'

          $wrongLiveRefreshType=Copy-LibraryMarker $byStage['rejoin-ready']
          $wrongLiveRefreshType['witnesses']['live_refresh']='not-a-table'
          Assert-LibraryReaderRejects $wrongLiveRefreshType 'rejoin-ready' 2 'string live refresh'

          $stringQueue=Copy-LibraryMarker $byStage['completed']
          $stringQueue['witnesses']['live_refresh']['queue_lengths_observed']=@('2','1','0')
          Assert-LibraryReaderRejects $stringQueue 'completed' 6 'string queue lengths'

          $wrongCompletionCount=Copy-LibraryMarker $byStage['completed']
          $wrongCompletionCount['witnesses']['live_refresh']['real_lab_completions']=1
          Assert-LibraryReaderRejects $wrongCompletionCount 'completed' 6 'incomplete real labs'

          foreach($field in @('native_laboratory_completion_by_script','native_research_cancelled_events',
              'native_foreign_force_created_events','gear_level','science_consumed_per_named_pack',
              'fixture_accelerates_gear_count_and_time_only','ordinary_tuning_qualified',
              'root_and_query_identity_preserved','cross_force_view_state_preserved')){
            $wrong=Copy-LibraryMarker $byStage['completed']
            switch($field){
              'native_laboratory_completion_by_script' {$wrong['witnesses']['live_refresh'][$field]=$true}
              'native_research_cancelled_events' {$wrong['witnesses']['live_refresh'][$field]=0}
              'native_foreign_force_created_events' {$wrong['witnesses']['live_refresh'][$field]=0}
              'gear_level' {$wrong['witnesses']['live_refresh'][$field]=1}
              'science_consumed_per_named_pack' {$wrong['witnesses']['live_refresh'][$field]=0}
              'fixture_accelerates_gear_count_and_time_only' {$wrong['witnesses']['live_refresh'][$field]=$false}
              'ordinary_tuning_qualified' {$wrong['witnesses']['live_refresh'][$field]=$true}
              'root_and_query_identity_preserved' {$wrong['witnesses']['live_refresh'][$field]=$false}
              'cross_force_view_state_preserved' {$wrong['witnesses']['live_refresh'][$field]=$false}
            }
            Assert-LibraryReaderRejects $wrong 'completed' 6 "completed $field"
          }

          $stringStarted=Copy-LibraryMarker $byStage['completed']
          $stringStarted['witnesses']['live_refresh']['native_research_started_events']='2'
          Assert-LibraryReaderRejects $stringStarted 'completed' 6 'string native research starts'
          $shortQueue=Copy-LibraryMarker $byStage['completed']
          $shortQueue['witnesses']['live_refresh']['queue_lengths_observed']=@(2,0)
          Assert-LibraryReaderRejects $shortQueue 'completed' 6 'short queue lengths'
          $wrongProductivity=Copy-LibraryMarker $byStage['completed']
          $wrongProductivity['witnesses']['live_refresh']['gear_productivity']=.2000005
          Assert-LibraryReaderRejects $wrongProductivity 'completed' 6 'gear productivity tolerance'
          $stringProductivity=Copy-LibraryMarker $byStage['completed']
          $stringProductivity['witnesses']['live_refresh']['gear_productivity']='0.2'
          Assert-LibraryReaderRejects $stringProductivity 'completed' 6 'string gear productivity'
          foreach($field in @('first_open','search','refresh','availability_terminal_labels_checked','reopen')){
            $wrong=Copy-LibraryMarker $byStage['completed']
            $wrong['witnesses'][$field]=$false
            Assert-LibraryReaderRejects $wrong 'completed' 6 "completed $field"
          }

          $wrongStage=Copy-LibraryMarker $byStage['ready']
          $wrongStage['stage']='unknown'
          Assert-LibraryReaderRejects $wrongStage 'ready' 0 'wrong stage'
          'PASS actual marker reader contract'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-library-marker-reader-") as work:
            marker_path = Path(work) / "actual-fixture-markers.json"
            marker_path.write_text(json.dumps({target: result["markers"] for target, result in results.items()}), encoding="utf-8")
            reader = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_SESSION=str(SESSION),
                         MIR_TEST_LIBRARY_MARKERS=str(marker_path)), check=False)
        self.assertEqual(reader.returncode, 0, reader.stdout + reader.stderr)

    def test_profiler_output_does_not_change_saved_witnesses(self):
        first, other = self.run_case(), self.run_case("profiler-variant")
        self.assertTrue(first["ok"], first["message"])
        self.assertTrue(other["ok"], other["message"])
        self.assertNotEqual(first["profiler_logs"], other["profiler_logs"])
        self.assertEqual(first["measurements"], other["measurements"])
        self.assertEqual(first["markers"], other["markers"])
        self.assertEqual(first["saves"], other["saves"])

    def test_fixture_rejects_missing_clients_wrong_locale_cross_player_view_and_native_mutation(self):
        absent = self.run_case("absent-second-client")
        self.assertTrue(absent["ok"], absent["message"])
        self.assertEqual(absent["phase"], "waiting-initial-clients")
        self.assertEqual([item["stage"] for item in absent["markers"]], ["ready"])
        self.assertFalse(absent["saves"])

        expected = {
            "fake-connected": "actually connected client",
            "locale": "actual en/de locales",
            "view-crosspollution": "Availability browser GUI tree is incomplete",
            "gameplay-mutation": "mutated native research, queue, or recipe effects",
            "native-witness-overwritten": "stored initial native witness was overwritten",
            "missing-queue": "native Library refresh queue differs before laboratory progress",
            "script-completion": "actual Library laboratory completion callback differs",
            "no-lab-consumption": "actual Library refresh lab science consumption differs",
            "second-feed-rejected": "actual Library refresh laboratory rejected automation-science-pack during second science feed",
            "wrong-force-event": "native foreign-force callback differs",
            "foreign-force-gui": "native public browser GUI tree is incomplete",
            "missing-availability-label": "Availability terminal label differs",
            "extra-availability-label": "Availability terminal label count differs",
            "caption-wrong-level-key": "native Library refresh level differs",
            "caption-numeric-level": "native Library refresh level differs",
            "caption-wrong-level": "native Library refresh level differs",
            "caption-noncanonical-level": "native Library refresh level differs",
            "caption-wrong-queue-count": "native Library refresh queue facts differ",
            "caption-noncanonical-queue-count": "native Library refresh queue facts differ",
            "caption-wrong-queue-position": "native Library refresh queue facts differ",
            "caption-noncanonical-queue-position": "native Library refresh queue facts differ",
        }
        for opponent, message in expected.items():
            with self.subTest(opponent=opponent):
                result = self.run_case(opponent)
                self.assertFalse(result["ok"])
                self.assertIn("[mir5-library-multiplayer]", result["message"])
                self.assertIn(message, result["message"])

    def test_fixture_preflights_the_exact_unordered_gear_science_vector(self):
        source = CONTROL.read_text(encoding="utf-8")
        self.assertIn("local gear = gear_definition(force)\n  seed_gear_prerequisites(force)", source)

        reordered = self.run_case("science-reordered")
        self.assertTrue(reordered["ok"], reordered["message"])

        expected = {
            "science-missing": "required ingredient is missing",
            "science-duplicate": "duplicate ingredient",
            "science-extra": "unexpected ingredient",
            "science-wrong-amount": "ingredient amount",
        }
        for opponent, reason in expected.items():
            with self.subTest(opponent=opponent):
                result = self.run_case(opponent)
                self.assertFalse(result["ok"])
                self.assertIn("[mir5-library-multiplayer]", result["message"])
                self.assertIn("fixture gear science vector differs", result["message"])
                self.assertIn(reason, result["message"])

    def test_live_lab_stages_each_science_pack_until_the_first_native_completion(self):
        source = CONTROL.read_text(encoding="utf-8")
        initial = 'insert_gear_science(inventory, LAB_PACKS_PER_RESEARCH, "initial science feed")'
        refill = 'insert_gear_science(research_inventory(state), LAB_PACKS_PER_RESEARCH, "second science feed")'
        self.assertIn("inventory.is_empty() ~= true", source)
        self.assertIn(initial, source)
        self.assertIn(refill, source)
        self.assertLess(source.index("assert_live_queue_view(state, 2, 1, true)"), source.index(refill))

        staged = self.run_case("all-at-once-feeding")
        self.assertTrue(staged["ok"], staged["message"])
        self.assertEqual(staged["lab_insert_counts"], [1] * 8)
        self.assertEqual(staged["rejected_bulk_inserts"], 0)

        refill_rejected = self.run_case("second-feed-rejected")
        self.assertFalse(refill_rejected["ok"])
        self.assertIn("actual Library refresh laboratory rejected automation-science-pack during second science feed",
                      refill_rejected["message"])

    def test_initial_native_locales_need_no_synthetic_locale_change_event(self):
        result = self.run_case("unchanged-locales")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((result["phase"], result["join_events"]), ("completed", 6))

    def test_fixture_uses_only_public_browser_and_native_gui_witnesses(self):
        source = CONTROL.read_text(encoding="utf-8")
        self.assertIn('remote.call(BROWSER, "open", player.index', source)
        self.assertIn('{tab="availability", search=""}', source)
        self.assertIn('tab="research", visibility=1', source)
        self.assertIn('state.capture_after_tick = game.tick + 60', source)
        self.assertIn('"research_agricultural_growth_speed"', source)
        self.assertIn('"research_spoilage_preservation"', source)
        self.assertIn("on_player_locale_changed", source)
        self.assertIn("on_player_joined_game", source)
        self.assertIn("force.add_research(gear)", source)
        self.assertIn("force.cancel_current_research()", source)
        self.assertIn("on_research_started", source)
        self.assertIn("queue_lengths_observed", source)
        self.assertIn("on_research_finished", source)
        self.assertIn("on_research_cancelled", source)
        self.assertIn("on_force_created", source)
        self.assertIn("event.by_script ~= false", source)
        self.assertIn("state.native_initial_guard", source)
        self.assertIn("state.native_after_lab", source)
        self.assertIn("helpers.create_profiler(true)", source)
        self.assertNotIn("game.create_profiler", source)
        self.assertIn("rendering_pending_external_png_readback=true", source)
        self.assertNotIn("game.create_player", source)
        self.assertNotIn("require(", source)
        self.assertNotIn("storage.mir_library", source)
        self.assertNotIn("script.raise_event", source)
        self.assertNotIn("research_queue_enabled", source)

    def test_live_refresh_acceleration_is_fixture_owned_and_limited(self):
        updates_path = (FIXTURE / "settings-updates.lua").as_posix()
        updates = Path(updates_path).read_text(encoding="utf-8")
        self.assertIn('"ips-cost-base-research_gears"', updates)
        self.assertIn('"ips-cost-linear-increment-research_gears"', updates)
        self.assertIn('"ips-cost-growth-research_gears"', updates)
        self.assertIn('"ips-research-time-research_gears"', updates)
        self.assertNotIn("require(", updates)
        self.lua.globals().updates_path = updates_path
        values = plain(self.lua.execute(r"""
          data = {raw={
            ["int-setting"]={
              ["ips-cost-base-research_gears"]={setting_type="startup",default_value=8000},
              ["ips-cost-linear-increment-research_gears"]={setting_type="startup",default_value=0},
              ["ips-research-time-research_gears"]={setting_type="startup",default_value=60},
            },
            ["double-setting"]={
              ["ips-cost-growth-research_gears"]={setting_type="startup",default_value=2},
            },
            ["bool-setting"]={}
          }}
          function data:extend(rows)
            assert(type(rows)=="table" and #rows==1, "fixture must use one native prototype row")
            local prototype=rows[1]
            assert(type(prototype)=="table" and prototype.type=="bool-setting" and prototype.name=="mir5-library-standalone-identity-discovery", "unexpected discovery prototype")
            assert(self.raw[prototype.type] and self.raw[prototype.type][prototype.name]==nil, "duplicate discovery prototype")
            self.raw[prototype.type][prototype.name]=prototype
          end
          assert(loadfile(updates_path))()
          return {
            base=data.raw["int-setting"]["ips-cost-base-research_gears"].default_value,
            increment=data.raw["int-setting"]["ips-cost-linear-increment-research_gears"].default_value,
            growth=data.raw["double-setting"]["ips-cost-growth-research_gears"].default_value,
            time=data.raw["int-setting"]["ips-research-time-research_gears"].default_value,
            discovery=data.raw["bool-setting"]["mir5-library-standalone-identity-discovery"].default_value,
          }
        """))
        self.assertEqual(values, {"base": 1, "increment": 0, "growth": 1, "time": 1, "discovery": False})
        wrong_default = plain(self.lua.execute(r"""
          data = {raw={
            ["int-setting"]={
              ["ips-cost-base-research_gears"]={setting_type="startup",default_value=7999},
              ["ips-cost-linear-increment-research_gears"]={setting_type="startup",default_value=0},
              ["ips-research-time-research_gears"]={setting_type="startup",default_value=60},
            },
            ["double-setting"]={
              ["ips-cost-growth-research_gears"]={setting_type="startup",default_value=2},
            },
            ["bool-setting"]={}
          }}
          function data:extend(rows)
            assert(type(rows)=="table" and #rows==1, "fixture must use one native prototype row")
            local prototype=rows[1]
            assert(type(prototype)=="table" and prototype.type=="bool-setting" and prototype.name=="mir5-library-standalone-identity-discovery", "unexpected discovery prototype")
            assert(self.raw[prototype.type] and self.raw[prototype.type][prototype.name]==nil, "duplicate discovery prototype")
            self.raw[prototype.type][prototype.name]=prototype
          end
          local ok, message = pcall(function() assert(loadfile(updates_path))() end)
          return {ok=ok, message=tostring(message), defaults={
            base=data.raw["int-setting"]["ips-cost-base-research_gears"].default_value,
            increment=data.raw["int-setting"]["ips-cost-linear-increment-research_gears"].default_value,
            growth=data.raw["double-setting"]["ips-cost-growth-research_gears"].default_value,
            time=data.raw["int-setting"]["ips-research-time-research_gears"].default_value,
          }}
        """))
        self.assertFalse(wrong_default["ok"])
        self.assertIn("unexpected Library refresh fixture setting ips-cost-base-research_gears", wrong_default["message"])
        self.assertEqual(wrong_default["defaults"], {"base": 7999, "increment": 0, "growth": 2, "time": 60})
        missing = self.lua.execute(r"""
          data = {raw={ ["int-setting"]={}, ["double-setting"]={}, ["bool-setting"]={} }}
          function data:extend(rows)
            assert(type(rows)=="table" and #rows==1, "fixture must use one native prototype row")
            local prototype=rows[1]
            assert(self.raw[prototype.type] and self.raw[prototype.type][prototype.name]==nil, "duplicate discovery prototype")
            self.raw[prototype.type][prototype.name]=prototype
          end
          return pcall(function() assert(loadfile(updates_path))() end)
        """)
        self.assertFalse(missing[0])
        self.assertIn("unexpected Library refresh fixture setting", missing[1])
        duplicate = self.lua.execute(r"""
          data = {raw={
            ["int-setting"]={
              ["ips-cost-base-research_gears"]={setting_type="startup",default_value=8000},
              ["ips-cost-linear-increment-research_gears"]={setting_type="startup",default_value=0},
              ["ips-research-time-research_gears"]={setting_type="startup",default_value=60},
            },
            ["double-setting"]={ ["ips-cost-growth-research_gears"]={setting_type="startup",default_value=2} },
            ["bool-setting"]={ ["mir5-library-standalone-identity-discovery"]={type="bool-setting"} }
          }}
          function data:extend(rows)
            assert(type(rows)=="table" and #rows==1, "fixture must use one native prototype row")
            local prototype=rows[1]
            assert(self.raw[prototype.type] and self.raw[prototype.type][prototype.name]==nil, "duplicate discovery prototype")
            self.raw[prototype.type][prototype.name]=prototype
          end
          return pcall(function() assert(loadfile(updates_path))() end)
        """)
        self.assertFalse(duplicate[0])
        self.assertIn("duplicate discovery prototype", duplicate[1])

    def test_opt_in_owned_process_memory_sampler_is_bounded_identity_checked_and_read_only(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          function Get-Process { throw 'sampler must not rediscover a process' }
          function Get-CimInstance { throw 'sampler must not traverse process trees' }
          . $env:MIR_TEST_SAMPLER
          $start=[Diagnostics.ProcessStartInfo]::new()
          $start.FileName=(Get-Command pwsh -ErrorAction Stop).Source
          $start.UseShellExecute=$false
          [void]$start.ArgumentList.Add('-NoLogo')
          [void]$start.ArgumentList.Add('-NoProfile')
          [void]$start.ArgumentList.Add('-Command')
          [void]$start.ArgumentList.Add('Start-Sleep -Seconds 20')
          $child=[Diagnostics.Process]::new();$child.StartInfo=$start
          if(-not$child.Start()){throw 'could not start bounded sampler child'}
          try {
            $slot=@([pscustomobject]@{phase='initial';role='server'})
            $allSlots=@(foreach($phase in @('initial','rejoin','restart')){foreach($role in @('server','client-en','client-de')){[pscustomobject]@{phase=$phase;role=$role}}})
            $bounded=New-MIROwnedProcessMemorySampler -ExpectedSlots $allSlots
            if($bounded.expected_slots.Count -ne 9 -or $bounded.target_interval_milliseconds -ne 250 -or $bounded.maximum_duration_seconds -ne 900 -or $bounded.maximum_observations -ne 12000 -or $bounded.maximum_serialized_bytes -ne 8MB){throw 'sampler bounds differ'}
            if($null -ne $bounded.PSObject.Properties['context']){throw 'default sampler shape changed'}
            $rejected=$false;try{New-MIROwnedProcessMemorySampler -ExpectedSlots @($allSlots + $slot)|Out-Null}catch{$rejected=$true}
            if(-not$rejected){throw 'sampler accepted more than the nine owned slots'}
            $sampler=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot
            $registration=Register-MIROwnedProcessMemoryProcess -Sampler $sampler -Phase initial -Role server -Process $child
            Add-MIROwnedProcessMemorySample -Sampler $sampler
            Start-Sleep -Milliseconds 260
            Add-MIROwnedProcessMemorySample -Sampler $sampler
            if($sampler.observations.Count -lt 2 -or $sampler.observations[1].elapsed_monotonic_milliseconds -lt 250){throw 'fixed nominal sampler cadence was not observed'}
            if((Get-MIROwnedProcessMemorySleepMilliseconds -Sampler $sampler -MaximumDelayMilliseconds 200) -gt 200){throw 'sampler delay exceeded session wait bound'}
            Complete-MIROwnedProcessMemoryProcess -Sampler $sampler -Registration $registration
            if($child.HasExited){throw 'sampler changed owned child lifetime'}
            $receiptPath=[IO.Path]::GetTempFileName();Remove-Item -LiteralPath $receiptPath -Force
            $receipt=Write-MIROwnedProcessMemoryObservationReceipt -Sampler $sampler -Path $receiptPath
            $receiptBytes=[IO.File]::ReadAllBytes($receiptPath)
            if($receipt.status -cne 'complete-observation' -or $receipt.performance_acceptance -ne $false -or $receipt.observations.Count -lt 2 -or $receipt.PSObject.Properties['context'] -ne $null -or $receiptBytes.Length -gt 8MB -or $receiptBytes.Length -ne (ConvertTo-MIROwnedProcessMemoryObservationBytes -Receipt $receipt).Length){throw 'sampler did not write its exact bounded non-acceptance observation'}
            Remove-Item -LiteralPath $receiptPath -Force

            $benchmarkSlot=@([pscustomobject]@{phase='benchmark';role='factorio'})
            $benchmark=New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots $benchmarkSlot
            if($benchmark.context -cne 'benchmark' -or $benchmark.expected_slots.Count -ne 1){throw 'benchmark sampler did not use its sole declared slot'}
            foreach($invalid in @(
              @([pscustomobject]@{phase='initial';role='server'}),
              @($benchmarkSlot + [pscustomobject]@{phase='benchmark';role='factorio'}),
              @([pscustomobject]@{phase='benchmark';role='server'})
            )){
              $invalidRejected=$false;try{New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots $invalid|Out-Null}catch{$invalidRejected=$true}
              if(-not$invalidRejected){throw 'benchmark sampler accepted an unbounded slot shape'}
            }
            $benchmarkRegistration=Register-MIROwnedProcessMemoryProcess -Sampler $benchmark -Phase benchmark -Role factorio -Process $child
            Add-MIROwnedProcessMemorySample -Sampler $benchmark
            Complete-MIROwnedProcessMemoryProcess -Sampler $benchmark -Registration $benchmarkRegistration
            $benchmarkReceipt=Get-MIROwnedProcessMemoryObservationReceipt -Sampler $benchmark
            if($benchmarkReceipt.status -cne 'complete-observation' -or $benchmarkReceipt.context -cne 'benchmark' -or $benchmarkReceipt.observations.Count -ne 1 -or $benchmarkReceipt.observations[0].phase -cne 'benchmark' -or $benchmarkReceipt.observations[0].role -cne 'factorio'){throw 'benchmark sampler receipt was not narrowly identified'}

            $naturalZero=New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots $benchmarkSlot
            $naturalZeroRegistration=Register-MIROwnedProcessMemoryProcess -Sampler $naturalZero -Phase benchmark -Role factorio -Process $child
            Complete-MIROwnedProcessMemoryProcess -Sampler $naturalZero -Registration $naturalZeroRegistration -NaturalExit
            $naturalZeroReceipt=Get-MIROwnedProcessMemoryObservationReceipt -Sampler $naturalZero
            if($naturalZeroReceipt.status -cne 'incomplete-observation' -or $naturalZeroReceipt.incomplete_reasons -notcontains 'missing-process-observation'){throw 'natural exit accepted a process without a prior observation'}

            $identity=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot
            $identityRegistration=Register-MIROwnedProcessMemoryProcess -Sampler $identity -Phase initial -Role server -Process $child
            $identityRegistration.start_utc='1970-01-01T00:00:00.0000000Z'
            Add-MIROwnedProcessMemorySample -Sampler $identity
            Complete-MIROwnedProcessMemoryProcess -Sampler $identity -Registration $identityRegistration
            if((Get-MIROwnedProcessMemoryObservationReceipt -Sampler $identity).status -cne 'incomplete-observation'){throw 'identity drift did not make evidence incomplete'}

            $overflow=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot
            $overflow.maximum_observations=1
            $overflowRegistration=Register-MIROwnedProcessMemoryProcess -Sampler $overflow -Phase initial -Role server -Process $child
            Add-MIROwnedProcessMemorySample -Sampler $overflow
            $overflow.next_due_monotonic_milliseconds=0
            Add-MIROwnedProcessMemorySample -Sampler $overflow
            Complete-MIROwnedProcessMemoryProcess -Sampler $overflow -Registration $overflowRegistration
            if((Get-MIROwnedProcessMemoryObservationReceipt -Sampler $overflow).status -cne 'incomplete-observation'){throw 'observation limit did not make evidence incomplete'}

            $serialized=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot
            $serializedRegistration=Register-MIROwnedProcessMemoryProcess -Sampler $serialized -Phase initial -Role server -Process $child
            Add-MIROwnedProcessMemorySample -Sampler $serialized
            $serialized.observations.Add([pscustomobject]@{padding=('x'*(9MB))})
            Complete-MIROwnedProcessMemoryProcess -Sampler $serialized -Registration $serializedRegistration
            $serializedPath=[IO.Path]::GetTempFileName();Remove-Item -LiteralPath $serializedPath -Force
            $serializedReceipt=Write-MIROwnedProcessMemoryObservationReceipt -Sampler $serialized -Path $serializedPath
            if($serializedReceipt.status -cne 'incomplete-observation' -or $serializedReceipt.observations.Count -ne 0 -or $serializedReceipt.incomplete_reasons -notcontains 'serialized-output-limit' -or (Get-Item -LiteralPath $serializedPath).Length -gt 8MB){throw 'serialized byte cap was not enforced against the emitted artifact'}
            Remove-Item -LiteralPath $serializedPath -Force
          } finally {
            if(-not$child.HasExited){$child.Kill($true);[void]$child.WaitForExit(5000)}
            $child.Dispose()
          }
          'PASS owned process memory sampler'
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SAMPLER=str(SAMPLER)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_memory_observation_opt_in_is_strict_and_default_session_specs_remain_unchanged(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $definition=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-ProcessMemoryObservationOptIn'},$true))
          if($definition.Count -ne 1){throw 'strict opt-in reader missing or ambiguous'}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          Invoke-Expression $definition[0].Extent.Text
          if(Get-ProcessMemoryObservationOptIn -Spec @{} -FixtureCase 'library-multiplayer'){throw 'absent opt-in created observations'}
          if(Get-ProcessMemoryObservationOptIn -Spec @{process_memory_observations=$false} -FixtureCase 'library-multiplayer'){throw 'false opt-in created observations'}
          if(-not(Get-ProcessMemoryObservationOptIn -Spec @{process_memory_observations=$true} -FixtureCase 'library-multiplayer')){throw 'true functional Library opt-in was ignored'}
          if(-not(Get-ProcessMemoryObservationOptIn -Spec @{process_memory_observations=$true} -FixtureCase 'library-paired-browser')){throw 'true paired Browser opt-in was ignored'}
          if(Get-ProcessMemoryObservationOptIn -Spec @{} -FixtureCase 'library-paired-browser'){throw 'absent paired Browser opt-in created observations'}
          foreach($wrong in @('true',1,1.0,$null)){
            $rejected=$false;try{Get-ProcessMemoryObservationOptIn -Spec @{process_memory_observations=$wrong} -FixtureCase 'library-multiplayer'|Out-Null}catch{$rejected=$true}
            if(-not$rejected){throw 'non-Boolean opt-in was accepted'}
          }
          $rejected=$false;try{Get-ProcessMemoryObservationOptIn -Spec @{process_memory_observations=$true} -FixtureCase 'scripted-effects-multiplayer'|Out-Null}catch{$rejected=$true}
          if(-not$rejected){throw 'non-Library opt-in was accepted'}
          $wrapper=[IO.File]::ReadAllText($env:MIR_TEST_WRAPPER)
          if(-not$wrapper.Contains('if($CollectProcessMemoryObservations){') -or $wrapper.Contains('$spec.process_memory_observations=$false')){throw 'wrapper changed the default session spec'}
          'PASS strict observation opt-in'
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SESSION=str(SESSION), MIR_TEST_WRAPPER=str(WRAPPER)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_paired_browser_session_reader_requires_exact_server_protocol(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $text=[IO.File]::ReadAllText($env:MIR_TEST_SESSION)
          $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $names=@('Test-LibraryInteger','Assert-PairedBrowserInteger','Assert-PairedBrowserBoolean','Get-PairedBrowserStageMarker','Get-PairedBrowserProfilerMarkers')
          $definitions=@{}
          foreach($name in $names){
            $found=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true))
            if($found.Count-ne1){throw "missing paired reader definition: $name"}
            $definitions[$name]=$found[0].Extent.Text
          }
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          foreach($name in $names){Invoke-Expression $definitions[$name]}
          $rows=@(
            @{schema=1;case='library-paired-browser';stage='ready';status='ready';arm='published';join_events=0;action_call_count=0;screenshot_calls=0;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='first-open';status='observed';arm='published';join_events=2;action_call_count=2;screenshot_calls=2;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='search';status='observed';arm='published';join_events=2;action_call_count=2;screenshot_calls=4;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='refresh';status='observed';arm='published';join_events=2;action_call_count=2;screenshot_calls=6;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='restart-ready';status='ready';arm='published';join_events=2;action_call_count=2;screenshot_calls=6;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='reopen';status='observed';arm='published';join_events=4;action_call_count=2;screenshot_calls=8;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='completed';status='passed';arm='published';join_events=4;action_call_count=2;screenshot_calls=8;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false}
          )
          function MarkerText($InputRows){return (($InputRows|ForEach-Object {'[MIR5_LIBRARY_PAIRED_BROWSER] '+($_|ConvertTo-Json -Compress)})-join "`n")+"`n"}
          $text=MarkerText $rows
          foreach($row in $rows){$accepted=Get-PairedBrowserStageMarker $text $row.stage 'published';if($accepted.stage-cne$row.stage){throw 'valid paired stage rejected'}}
          $profiles="[MIR5_LIBRARY_PROFILE] first_open Duration: 1.000000ms`n[MIR5_LIBRARY_PROFILE] search Duration: 1.000000ms`n[MIR5_LIBRARY_PROFILE] refresh Duration: 1.000000ms`n[MIR5_LIBRARY_PROFILE] reopen Duration: 1.000000ms`n"
          $observations=@(Get-PairedBrowserProfilerMarkers $profiles @('first_open','search','refresh','reopen'))
          if($observations.Count-ne4 -or $observations[0].raw_line -cne '[MIR5_LIBRARY_PROFILE] first_open Duration: 1.000000ms'){throw 'paired profiler provenance differs'}
          function Assert-Rejects([scriptblock]$Block,[string]$Name){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "paired reader accepted invalid $Name"}}
          $duplicate=@($rows)+@($rows[-1]);Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $duplicate) 'completed' 'published'|Out-Null} 'duplicate stage'
          $wrongArm=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$wrongArm[1].arm='mir5';Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $wrongArm) 'first-open' 'published'|Out-Null} 'wrong arm'
          $stringJoin=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$stringJoin[2].join_events='2';Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $stringJoin) 'search' 'published'|Out-Null} 'string join count'
          $unknownStage=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$unknownStage[3].stage='unexpected';Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $unknownStage) 'ready' 'published'|Out-Null} 'unknown stage'
          Assert-Rejects {Get-PairedBrowserProfilerMarkers ($profiles+'[MIR5_LIBRARY_PROFILE] search Duration: 1.000000ms'+"`n") @('first_open','search','refresh','reopen')|Out-Null} 'duplicate profiler action'
           Assert-Rejects {Get-PairedBrowserProfilerMarkers ($profiles -replace '\[MIR5_LIBRARY_PROFILE\] reopen[^\r\n]*\r?\n?', '') @('first_open','search','refresh','reopen')|Out-Null} 'missing profiler action'
          Assert-Rejects {Get-PairedBrowserProfilerMarkers '[MIR5_LIBRARY_PROFILE] first-open Duration: 1.000000ms' @('first_open')|Out-Null} 'hyphen profiler token'
          'PASS paired Browser reader'
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SESSION=str(SESSION)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_paired_browser_restart_phase_snapshot_preserves_exact_scope(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $text=[IO.File]::ReadAllText($env:MIR_TEST_SESSION)
          $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $names=@('Test-PairedBrowserBytePrefix','Save-PairedBrowserServerPhaseLog')
          $definitions=@{}
          foreach($name in $names){
            $found=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true))
            if($found.Count-ne1){throw "missing paired phase snapshot definition: $name"}
            $definitions[$name]=$found[0].Extent.Text
          }
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Get-SessionHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
          function Test-Within([string]$Root,[string]$Path){
            $relative=[IO.Path]::GetRelativePath($Root,$Path)
            return $relative-ne'..' -and -not$relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar) -and -not[IO.Path]::IsPathRooted($relative)
          }
          function Resolve-BuildInput([string]$Path,[string]$Type,[string]$Label){
            if(-not(Test-Path -LiteralPath $Path -PathType $Type)){throw "$Label is absent"}
            $resolved=(Resolve-Path -LiteralPath $Path).Path
            if(-not(Test-Within $buildRoot $resolved)){throw "$Label is outside checkout build"}
            return $resolved
          }
          function Resolve-BuildOutput([string]$Path,[string]$Label){
            $full=[IO.Path]::GetFullPath($Path)
            if(-not(Test-Within $buildRoot $full)){throw "$Label is outside checkout build"}
            return $full
          }
          foreach($name in $names){Invoke-Expression $definitions[$name]}
          function Assert-Rejects([scriptblock]$Block,[string]$Name){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "paired phase snapshot accepted invalid $Name"}}
          $encoding=[Text.UTF8Encoding]::new($false)
          $buildRoot=Join-Path $env:MIR_TEST_WORK 'build';$null=New-Item -ItemType Directory -Path $buildRoot
          function New-Phase([string]$Name,[bool]$Append){
            $workroot=Join-Path $buildRoot $Name;$null=New-Item -ItemType Directory -Path $workroot
            $live=Join-Path $workroot 'factorio-current.log'
            $initial='[MIR5_LIBRARY_PROFILE] first_open Duration: 1.000000ms' + "`n" +
              '[MIR5_LIBRARY_PROFILE] search Duration: 1.000000ms' + "`n" +
              '[MIR5_LIBRARY_PROFILE] refresh Duration: 1.000000ms' + "`n" + 'shutdown server-initial' + "`n"
            $restart='Hosting game at 127.0.0.1' + "`n" +
              '[MIR5_LIBRARY_PROFILE] reopen Duration: 1.000000ms' + "`n" + 'shutdown server-restart' + "`n"
            [IO.File]::WriteAllText($live,$initial,$encoding)
            $initialSnapshot=Save-PairedBrowserServerPhaseLog $live 'initial'
            if($Append){[IO.File]::AppendAllText($live,$restart,$encoding)}else{[IO.File]::WriteAllText($live,$restart,$encoding)}
            $restartSnapshot=Save-PairedBrowserServerPhaseLog $live 'restart' $initialSnapshot
            $expected=if($Append){$restart}else{$restart}
            $actual=[IO.File]::ReadAllText($restartSnapshot,$encoding)
            if($actual-cne$expected -or $actual-match'first_open' -or $actual-notmatch'reopen'){throw 'restart phase snapshot is not exact'}
            if((Get-SessionHash $restartSnapshot).Length-ne64){throw 'restart phase hash is unreadable'}
            return [pscustomobject]@{workroot=$workroot;live=$live;initial=$initialSnapshot;restart=$restartSnapshot}
          }
          $appended=New-Phase 'appended' $true
          $replacement=New-Phase 'replacement' $false
          if(([IO.File]::ReadAllText($appended.live,$encoding)-notmatch'first_open') -or ([IO.File]::ReadAllText($appended.live,$encoding)-notmatch'reopen')){throw 'appended full log was not preserved'}
          $workroot=Join-Path $buildRoot 'invalid';$null=New-Item -ItemType Directory -Path $workroot
          $live=Join-Path $workroot 'factorio-current.log';[IO.File]::WriteAllText($live,'inside',$encoding)
          $outside=Join-Path $env:MIR_TEST_WORK 'outside.log';[IO.File]::WriteAllText($outside,'outside',$encoding)
          Assert-Rejects {Save-PairedBrowserServerPhaseLog $live 'restart' $outside|Out-Null} 'outside initial snapshot'
          $workroot=Join-Path $buildRoot 'no-post-initial';$null=New-Item -ItemType Directory -Path $workroot
          $live=Join-Path $workroot 'factorio-current.log';[IO.File]::WriteAllText($live,'initial',$encoding)
          $initialSnapshot=Save-PairedBrowserServerPhaseLog $live 'initial'
          Assert-Rejects {Save-PairedBrowserServerPhaseLog $live 'restart' $initialSnapshot|Out-Null} 'restart without post-initial bytes'
          'PASS paired Browser restart phase snapshots'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-paired-phase-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True,
                text=True,
                env=dict(os.environ, MIR_TEST_SESSION=str(SESSION), MIR_TEST_WORK=work),
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actual_client_starter_matches_each_fixture_join_protocol(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $nodes=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Start-Clients'
          },$true))
          if($nodes.Count-ne1){throw 'actual client starter missing or ambiguous'}
          Invoke-Expression $nodes[0].Extent.Text
          $clients=@(
            @{name='MIR5English';locale='en';config='en.ini';port=1001;ordinal=1;write_data='client-en'},
            @{name='MIR5Deutsch';locale='de';config='de.ini';port=1002;ordinal=2;write_data='client-de'}
          )
          $library='unused';$serverPort=1000;$clientGraphics=@();$serverWriteData='unused'
          $apiClientConsumers=$false;$apiClientLoadMarkers=[Collections.Generic.List[object]]::new()
          function Start-Native([string]$Name,$NativeArguments){
            $index=$script:launches.Count
            $script:launches.Add($Name);$script:order.Add('start')
            $playerName=$clients[$index].name
            $ordinal=$script:ordinals[$index]
            $script:logText+="[$markerPrefix`_JOIN] $playerName $ordinal`n"
            return [pscustomobject]@{name=$Name}
          }
          function Read-LogText([string]$Path){return $script:logText}
          function Wait-For([string]$Description,[scriptblock]$Predicate){
            $script:order.Add('wait')
            if(-not(&$Predicate)){throw 'expected client join absent'}
            return $true
          }
          $cases=@(
            @{fixture='library-paired-browser';phase='initial';ordinals=@(1,2);prefix='MIR5_LIBRARY_PAIRED_BROWSER'},
            @{fixture='library-paired-browser';phase='restart';ordinals=@(3,4);prefix='MIR5_LIBRARY_PAIRED_BROWSER'},
            @{fixture='library-multiplayer';phase='initial';ordinals=@(1,1);prefix='MIR5_LIBRARY_MP'},
            @{fixture='library-multiplayer';phase='rejoin';ordinals=@(2,2);prefix='MIR5_LIBRARY_MP'},
            @{fixture='library-multiplayer';phase='restart';ordinals=@(3,3);prefix='MIR5_LIBRARY_MP'},
            @{fixture='scripted-effects-multiplayer';phase='initial';ordinals=@(1,1);prefix='MIR5_SCRIPTED_MP'},
            @{fixture='scripted-effects-multiplayer';phase='rejoin';ordinals=@(2,2);prefix='MIR5_SCRIPTED_MP'},
            @{fixture='scripted-effects-multiplayer';phase='restart';ordinals=@(3,3);prefix='MIR5_SCRIPTED_MP'}
          )
          foreach($case in $cases){
            foreach($opponent in @('valid','wrong-second-ordinal')){
              $fixtureCase=$case.fixture;$markerPrefix=$case.prefix
              $script:ordinals=@($case.ordinals)
              if($opponent-ceq'wrong-second-ordinal'){$script:ordinals[1]=9}
              $script:logText=''
              $script:launches=[Collections.Generic.List[string]]::new()
              $script:order=[Collections.Generic.List[string]]::new()
              $failure=$null;$actors=@()
              try{$actors=@(Start-Clients $case.phase)}catch{$failure=$_.Exception.Message}
              if($opponent-ceq'valid'){
                if($null-ne$failure){throw "valid $($case.fixture)/$($case.phase) joins rejected: $failure"}
                if($actors.Count-ne2 -or $actors[0].name-cne"client-$($case.phase)-en" -or $actors[1].name-cne"client-$($case.phase)-de"){
                  throw 'client starter lost ordered actor records'
                }
              }elseif($failure-cne'expected client join absent'){throw 'incorrect second join ordinal accepted'}
              if(($script:order-join',')-cne'start,wait,start,wait'){throw 'client startups lost serialized join waits'}
            }
          }
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SESSION=str(SESSION)), check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_api_client_mode_requires_exact_new_load_markers_for_each_join_phase(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $allDefinitions=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
          },$true))
          $names=@('Test-LibraryInteger','Test-ApiClientNumber','Assert-ApiClientLoadMarker',
            'Get-ApiClientLoadMarkers','Get-ClientLogDelta','Start-Clients')
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          foreach($name in $names){
            $node=@($allDefinitions|Where-Object {$_.Name-ceq$name})
            if($node.Count-ne1){throw "missing or ambiguous API client definition: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $clients=@(
            [pscustomobject]@{name='MIR5English';locale='en';config='en.ini';port=1001;write_data='client-en'},
            [pscustomobject]@{name='MIR5Deutsch';locale='de';config='de.ini';port=1002;write_data='client-de'}
          )
          $library='unused';$serverPort=1000;$clientGraphics=@();$serverWriteData='server'
          $fixtureCase='library-multiplayer';$markerPrefix='MIR5_LIBRARY_MULTIPLAYER';$apiClientConsumers=$true
          function New-ApiLine([string]$Name,[bool]$Researched,[string]$Stage='load'){
            $row=[ordered]@{stage=$Stage;tick=100;reload_researched=$Researched;reload_level=1;reload_manual_crafting_speed_modifier=.05}
            '['+$Name+'] RESULT '+($row|ConvertTo-Json -Compress)+"`n"
          }
          function Read-LogText([string]$Path){
            if($Path -like '*server*'){return $script:serverLog}
            if($Path -like '*client-en*'){return $script:clientLogs['en']}
            if($Path -like '*client-de*'){return $script:clientLogs['de']}
            throw 'unexpected client log path'
          }
          function Start-Native([string]$Name,$NativeArguments){
            $parts=$Name.Split('-');$phase=$parts[1];$locale=$parts[2]
            $join=@{initial=1;rejoin=2;restart=3}[$phase]
            $player=if($locale-ceq'en'){'MIR5English'}else{'MIR5Deutsch'}
            $script:serverLog+="[$markerPrefix`_JOIN] $player $join`n"
            $alpha=New-ApiLine 'MIR5_API_ALPHA' $true
            $beta=New-ApiLine 'MIR5_API_BETA' $false
            switch($script:opponent){
              'absent-beta' {$beta=''}
              'duplicate-alpha' {$alpha+=$alpha}
              'wrong-stage' {$alpha=New-ApiLine 'MIR5_API_ALPHA' $true 'configuration'}
              'wrong-researched' {$beta=New-ApiLine 'MIR5_API_BETA' $true}
              'wrong-shape' {$beta='[MIR5_API_BETA] RESULT {"stage":"load","tick":100,"reload_level":1,"reload_manual_crafting_speed_modifier":0.05}' + "`n"}
            }
            $next=$alpha+$beta
            if($phase-ceq'rejoin'){$script:clientLogs[$locale]+=$next}else{$script:clientLogs[$locale]=$next}
            [pscustomobject]@{name=$Name}
          }
          function Wait-For([string]$Description,[scriptblock]$Predicate){
            $value=&$Predicate
            if($null-eq$value-or$value-eq$false){throw "predicate did not produce $Description"}
            return $value
          }
          function Invoke-ApiClientCase([string]$Opponent,[bool]$ExpectPass){
            $script:opponent=$Opponent;$script:serverLog='';$script:clientLogs=@{en='';de=''}
            $script:apiClientLoadMarkers=[Collections.Generic.List[object]]::new()
            $failure=$null
            try{
              foreach($phase in @('initial','rejoin','restart')){
                $actors=@(Start-Clients $phase)
                if($actors.Count-ne2){throw "lost client actors for $phase"}
              }
            }catch{$failure=$_.Exception.Message}
            if($ExpectPass){
              if($null-ne$failure){throw $failure}
              $rows=@($script:apiClientLoadMarkers)
              if($rows.Count-ne6){throw 'API client reader did not retain six per-client phase records'}
              $actual=@($rows|ForEach-Object { $_.phase+'/'+$_.client }|Sort-Object)-join ','
              $expected=@('initial/MIR5Deutsch','initial/MIR5English','rejoin/MIR5Deutsch','rejoin/MIR5English','restart/MIR5Deutsch','restart/MIR5English')-join ','
              if($actual-cne$expected){throw 'API client phase/client records differ'}
              foreach($row in $rows){
                if($row.MIR5_API_ALPHA.reload_researched-ne$true-or$row.MIR5_API_BETA.reload_researched-ne$false){throw 'API client researched state differs'}
              }
            }elseif($null-eq$failure){throw "API client reader accepted opponent: $Opponent"}
          }
          Invoke-ApiClientCase 'valid' $true
          foreach($opponent in @('absent-beta','duplicate-alpha','wrong-stage','wrong-researched','wrong-shape')){
            Invoke-ApiClientCase $opponent $false
          }
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_SESSION=str(SESSION)), check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_paired_browser_session_is_explicit_and_keeps_existing_ten_capture_path(self):
        wrapper = WRAPPER.read_text(encoding="utf-8")
        session = SESSION.read_text(encoding="utf-8")
        self.assertIn("'library-paired-browser'", wrapper)
        self.assertIn("'MIR5LibraryPairedBrowserNativeResultV1'", wrapper)
        self.assertIn("@('first-open','search','refresh','reopen')", wrapper)
        self.assertIn("MIR5LibraryPairedBrowserSessionV1", session)
        self.assertIn("Get-PairedBrowserStageMarker", session)
        self.assertIn("Get-PairedBrowserProfilerMarkers", session)
        self.assertIn("@('initial','restart')", session)
        self.assertIn("$screenshots.Count -eq 8", session)
        self.assertIn("Start-Clients 'initial'", session)
        self.assertIn("Start-Clients 'restart'", session)
        self.assertIn("Invoke-LoopbackRconKicks", session)
        self.assertIn("$patterns.Count -eq 10", session)
        self.assertIn("$clientPatterns.Count -eq 5", session)

    def test_native_session_requires_ten_client_local_captures(self):
        wrapper = WRAPPER.read_text(encoding="utf-8")
        session = SESSION.read_text(encoding="utf-8")
        self.assertIn("@('availability','initial','settled','rejoin','restart')", wrapper)
        self.assertIn("$patterns.Count -eq 10", session)
        self.assertIn("$clientPatterns.Count -eq 5", session)
        self.assertIn("@('availability','initial','settled','rejoin','restart')", session)
        self.assertIn("$completed.witnesses.availability_terminal_labels_checked -eq $true", session)
        self.assertIn("$completed.witnesses.screenshot_calls -eq 10", session)

    def test_pre_session_admission_refusal_is_preserved_without_launch_or_secrets(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'wrapper parse failed'}
          $nodes=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.Contains("'session-admission-refusal.json'")
          },$true))
          if($nodes.Count -ne 1){throw 'admission receipt writer missing or ambiguous'}
          $write=[scriptblock]::Create($nodes[0].Extent.Text)
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Invoke-MIRNativeProbeProcess {throw 'native process must not start'}
          function New-MIRNativeProbeResourceContext {throw 'admission must not be retried'}
          $script:fullWrites=0
          function Write-MIRNativeProbeResult {param($Context,$Record) $script:fullWrites++}
          foreach($case in @('library-multiplayer','scripted-effects-multiplayer')){
            $output=Join-Path $env:MIR_TEST_WORK $case
            $null=New-Item -ItemType Directory -Path $output
            $resources=$null
            $failure=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('[mir441-resource-admission-memory]'),'controlled',[Management.Automation.ErrorCategory]::ResourceUnavailable,$null)
            $admission=@{snapshot=@{memory=@{total_bytes=32GB;free_bytes=13GB;committed_bytes=24GB;commit_limit_bytes=40GB}};limits=@{physical_bytes=6GB;commit_bytes=6GB};expected_peak_memory_bytes=8GB;estimated_peak_bytes=512MB}
            $failure.Exception.Data['mir441_resource_admission']=$admission
            $record=[ordered]@{case=$case;source_head=('a'*40);harness_sha256=('e'*64);engine=@{sha256=('b'*64);base_version='2.0.77'};profile=@{sha256=('c'*64)};mir_archive=@{sha256=('d'*64)};failure='[mir441-resource-admission-memory]';resource_admission=$admission;preparation=@{private_value='do-not-serialize'};rcon_password='do-not-serialize'}
            & $write
            $path=Join-Path $output 'session-admission-refusal.json'
            $bytes=[IO.File]::ReadAllBytes($path);$text=[Text.Encoding]::UTF8.GetString($bytes);$receipt=$text|ConvertFrom-Json -AsHashtable
            if($bytes.Length -gt 64KB -or $text.Contains('do-not-serialize')){throw 'unbounded/private receipt'}
            if($receipt.status -cne 'refused-before-session' -or $receipt.case -cne $case -or $receipt.native_session_started -ne $false -or $receipt.release_qualification -ne $false){throw 'refusal claimed native acceptance'}
            if($receipt.resource_admission.snapshot.memory.free_bytes -ne 13GB -or $receipt.resource_admission.expected_peak_memory_bytes -ne 8GB -or $receipt.source_head -cne ('a'*40) -or $receipt.profile_sha256 -cne ('c'*64) -or $receipt.mir_archive_sha256 -cne ('d'*64)){throw 'lost exact refusal facts'}
            & $write
            if([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String($bytes) -or -not$failure.Exception.Data.Contains('admission_receipt_failure')){throw 'existing receipt was overwritten'}
            if($failure.Exception.Message -cne '[mir441-resource-admission-memory]' -or $failure.Exception.Data['mir441_resource_admission'].snapshot.memory.free_bytes -ne 13GB){throw 'original admission exception changed'}
          }
          $output=Join-Path $env:MIR_TEST_WORK 'oversize';$null=New-Item -ItemType Directory -Path $output
          $record.resource_admission=@{unexpected=('x'*64KB)}
          & $write
          if(Test-Path -LiteralPath (Join-Path $output 'session-admission-refusal.json')){throw 'oversize receipt written'}
          $record.resource_admission=$null
          & $write
          if(Test-Path -LiteralPath (Join-Path $output 'session-admission-refusal.json')){throw 'non-admission error gained receipt'}
          $resources=@{runs=[Collections.Generic.List[object]]::new()}
          & $write
          if($script:fullWrites -ne 1){throw 'admitted context lost its original result writer'}
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-mp-refusal-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_WORK=work), check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_session_success_waits_for_clients_first_teardown_and_preserves_failures(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $text=[IO.File]::ReadAllText($env:MIR_TEST_SESSION)
          $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $nodes=@($ast.EndBlock.Statements|Where-Object {
            $_ -is [Management.Automation.Language.TryStatementAst] -and
              $_.Body.Extent.Text.Contains("Start-Server 'server-initial'")
          })
          if($nodes.Count -ne 1){throw 'session execution tail missing or ambiguous'}
          $execute=[scriptblock]::Create($text.Substring($nodes[0].Extent.StartOffset))
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Get-SessionHash([string]$Path){
            if(Test-Path -LiteralPath $Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
            return ('a'*64)
          }
          function Read-LogText([string]$Path){if(Test-Path -LiteralPath $Path){return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))};return ''}
          function Save-PairedBrowserServerPhaseLog([string]$Source,[string]$Phase,[string]$InitialLog=''){
            if(-not(Test-Path -LiteralPath $Source -PathType Leaf)){throw 'paired Browser phase log source is absent'}
            $destination=Join-Path $workroot ("paired-browser-server-$Phase.factorio-current.log")
            if(Test-Path -LiteralPath $destination){throw 'paired Browser phase log snapshot already exists'}
            [byte[]]$sourceBytes=[IO.File]::ReadAllBytes($Source);[byte[]]$phaseBytes=$sourceBytes
            if($Phase-ceq'restart' -and $InitialLog){
              [byte[]]$initialBytes=[IO.File]::ReadAllBytes($InitialLog)
              $isPrefix=$sourceBytes.Length-ge$initialBytes.Length
              for($index=0;$isPrefix -and $index-lt$initialBytes.Length;$index++){if($sourceBytes[$index]-ne$initialBytes[$index]){$isPrefix=$false}}
              if($isPrefix){
                if($sourceBytes.Length-le$initialBytes.Length){throw 'paired Browser restart server log has no post-initial bytes'}
                $phaseBytes=[byte[]]::new($sourceBytes.Length-$initialBytes.Length)
                [Array]::Copy($sourceBytes,$initialBytes.Length,$phaseBytes,0,$phaseBytes.Length)
              }
            }
            [IO.File]::WriteAllBytes($destination,$phaseBytes)
            return $destination
          }
          function Get-PairedBrowserStageMarker {
            param([string]$Text,[string]$Stage,[string]$ExpectedArm)
            if($Text -notmatch [regex]::Escape("stage=$Stage arm=$ExpectedArm")){return $null}
            return [pscustomobject]@{stage=$Stage}
          }
          function Get-PairedBrowserProfilerMarkers {
            param([string]$Text,[string[]]$ExpectedActions)
            $rows=@()
            foreach($action in $ExpectedActions){
              $matches=@([regex]::Matches($Text,[regex]::Escape("[MIR5_LIBRARY_PROFILE] $action ")))
              if($matches.Count-ne1){throw "profiler action $action differs in phase log"}
              $rows += [pscustomobject]@{action=$action;raw_line=$matches[0].Value.TrimEnd()}
            }
            return @($rows)
          }
          function Find-Screenshots([string[]]$Stages){
            $count=if($Stages.Count-eq4){8}else{6}
            return [pscustomobject]@{files=@(1..$count|ForEach-Object {Join-Path $output ("paired-capture-"+$_.ToString()+'.png')})}
          }
          function Invoke-LoopbackRconKicks {param($Port,$Password)}
          $script:memoryWrites=0;$script:memoryReasons=[Collections.Generic.List[string]]::new()
          function Set-MIROwnedProcessMemoryIncomplete {param($Sampler,[string]$Reason)$script:memoryReasons.Add($Reason)}
          function Write-MIROwnedProcessMemoryObservationReceipt {
            param($Sampler,[string]$Path)
            $script:memoryWrites++
            [IO.File]::WriteAllText($Path,'{}',[Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{status='complete-observation'}
          }
          function Close-ProcessMemoryObservation {param($Record)}
          function Register-MIROwnedProcessMemoryProcess {param($Sampler,$Phase,$Role,$Process) return $null}
          function Start-Server([string]$Name,[string]$Save){
            $live=Join-Path $serverWriteData 'factorio-current.log'
            $text=if($Name-ceq'server-initial'){
              @(
                '[MIR5_LIBRARY_PAIRED_BROWSER] stage=ready arm=published',
                '[MIR5_LIBRARY_PAIRED_BROWSER] stage=first-open arm=published',
                '[MIR5_LIBRARY_PAIRED_BROWSER] stage=search arm=published',
                $(if($script:mode -ceq 'missing-phase') { } else { '[MIR5_LIBRARY_PAIRED_BROWSER] stage=refresh arm=published' }),
                '[MIR5_LIBRARY_PAIRED_BROWSER] stage=restart-ready arm=published',
                '[MIR5_LIBRARY_PROFILE] first_open Duration: 1.000000ms',
                '[MIR5_LIBRARY_PROFILE] search Duration: 1.000000ms',
                '[MIR5_LIBRARY_PROFILE] refresh Duration: 1.000000ms'
              ) -join "`n"
            }else{
              @(
                'Hosting game at 127.0.0.1',
                '[MIR5_LIBRARY_PAIRED_BROWSER] stage=reopen arm=published',
                '[MIR5_LIBRARY_PAIRED_BROWSER] stage=completed arm=published',
                '[MIR5_LIBRARY_PROFILE] reopen Duration: 1.000000ms'
              ) -join "`n"
            }
            if($Name-ceq'server-restart' -and $script:mode-ceq'appended-phase'){
              [IO.File]::AppendAllText($live,$text+"`n",[Text.UTF8Encoding]::new($false))
            }else{
              [IO.File]::WriteAllText($live,$text+"`n",[Text.UTF8Encoding]::new($false))
            }
            $record=[pscustomobject]@{name=$Name;closed=$false;process=$null}
            $script:records.Add($record);return $record
          }
          function Start-Clients([string]$Phase){
            if($script:mode -eq 'primary-and-cleanup' -and $Phase -eq 'initial'){
              throw 'original session failure'
            }
            $ordinal=if($Phase-ceq'initial'){0}else{2}
            foreach($locale in @('en','de')){
              $ordinal++
              $name=if($locale-ceq'en'){'MIR5English'}else{'MIR5Deutsch'}
              [IO.File]::AppendAllText((Join-Path $serverWriteData 'factorio-current.log'),"[MIR5_LIBRARY_PAIRED_BROWSER_JOIN] $name $ordinal`n",[Text.UTF8Encoding]::new($false))
              $record=[pscustomobject]@{name="client-$Phase-$locale";closed=$false}
              $script:records.Add($record);$record
            }
          }
          function Stop-Record($Record){
            $script:stops.Add($Record.name)
            if(Test-Path -LiteralPath $script:sessionPath){throw 'success receipt preceded teardown'}
            if($Record.name -like 'server-*' -and @($script:records|Where-Object {
                $_.name -like 'client-*' -and -not $_.closed}).Count){
              throw 'server stopped before its live clients'
            }
            $Record.closed=$true
            if($Record.name -like 'server-*'){
              [IO.File]::AppendAllText((Join-Path $serverWriteData 'factorio-current.log'),("shutdown $($Record.name)`n"),[Text.UTF8Encoding]::new($false))
            }
            if(($script:mode -eq 'cleanup' -and $Record.name -eq 'client-restart-de') -or
                ($script:mode -eq 'primary-and-cleanup' -and $Record.name -eq 'server-initial')){
              throw 'late native cleanup failure'
            }
          }
          function Wait-For([string]$Description,[scriptblock]$Predicate){
            if($Description -eq 'completed marker'){
              return [pscustomobject]@{witnesses=@{host_restart_observed=$true;on_load_read_only=$true;
                availability_terminal_labels_checked=$true;screenshot_calls=10}}
            }
            if($Description -eq 'complete final save and client screenshots'){
              return [pscustomobject]@{files=@(if($fixtureCase -ceq 'library-multiplayer'){
                1..10 | ForEach-Object {Join-Path $output ("capture-"+$_+".png")}
              })}
            }
            if($Description -eq 'paired Browser final save and client screenshots'){
              return Find-Screenshots @('first-open','search','refresh','reopen')
            }
            return $true
          }
          foreach($fixtureCase in @('library-multiplayer','library-paired-browser','scripted-effects-multiplayer')){
            $modes=if($fixtureCase-ceq'library-paired-browser'){@('success','appended-phase','cleanup','primary-and-cleanup','missing-phase')}else{@('success','cleanup','primary-and-cleanup')}
            foreach($script:mode in $modes){
              $output=Join-Path $env:MIR_TEST_WORK ($fixtureCase+'-'+$script:mode)
              $null=New-Item -ItemType Directory -Path $output
              $script:sessionPath=Join-Path $output 'session.json'
              $script:records=[Collections.Generic.List[object]]::new()
              $script:stops=[Collections.Generic.List[string]]::new()
              $sessionFailure=$null;$result=$null;$server=$null;$activeClients=@()
              $script:memoryWrites=0;$script:memoryReasons.Clear()
              $processMemorySampler=if($fixtureCase -cin @('library-multiplayer','library-paired-browser')){[pscustomobject]@{}}else{$null}
              $processMemoryObservationPath=if($fixtureCase -cin @('library-multiplayer','library-paired-browser')){Join-Path $output 'process-memory-observations.json'}else{$null}
              $serverWriteData=$output;$workroot=$output;$engine='unused';$seed='seed';$restartSave='restart';$finalSave='final'
              $seedHash=('a'*64);$clientGraphics=@();$rconPort=1;$rconPassword='not-a-real-password';$pairedArm='published'
              $apiClientConsumers=$false;$apiClientLoadMarkers=[Collections.Generic.List[object]]::new()
              $clients=@([pscustomobject]@{name='MIR5English';locale='en';port=2;config='en.ini';write_data='en'},
                [pscustomobject]@{name='MIR5Deutsch';locale='de';port=3;config='de.ini';write_data='de'})
              $caught=$null
              try{& $execute|Out-Null}catch{$caught=$_}
              if(@($script:records|Where-Object {-not $_.closed}).Count){throw 'cleanup abandoned owned records'}
              if($script:mode -in @('success','appended-phase')){
                if($null -ne $caught){throw $caught}
                $receipt=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json
                $expectedStops=if($fixtureCase -ceq 'library-paired-browser'){6}else{8}
                if($receipt.status -cne 'passed-private-two-client-session' -or $script:stops.Count -ne $expectedStops){
                  throw 'successful session lost completed teardown'
                }
                if($fixtureCase -cin @('library-multiplayer','library-paired-browser') -and ($script:memoryWrites -ne 1 -or -not(Test-Path -LiteralPath $processMemoryObservationPath) -or $receipt.process_memory_observations.status -cne 'complete-observation' -or $receipt.process_memory_observations.performance_acceptance -ne $false)){
                  throw 'successful opt-in session lost its bounded memory receipt'
                }
                $expectedCaptures=switch($fixtureCase){'library-multiplayer'{10};'library-paired-browser'{8};default{0}}
                if($receipt.screenshots.Count -ne $expectedCaptures){
                  throw 'successful teardown lost a required capture'
                }
                if($fixtureCase -ceq 'library-paired-browser'){
                  $phaseObservations=@($receipt.profiler_observations)
                  if($receipt.kind -cne 'MIR5LibraryPairedBrowserSessionV1' -or $receipt.paired_arm -cne 'published' -or $phaseObservations.Count-ne2){
                    throw 'successful paired Browser session lost its phase protocol evidence'
                  }
                  $initial=$phaseObservations|Where-Object {$_.phase-ceq'initial'}
                  $restart=$phaseObservations|Where-Object {$_.phase-ceq'restart'}
                  if(@($initial).Count-ne1 -or @($restart).Count-ne1 -or @($initial.markers).Count-ne3 -or @($restart.markers).Count-ne1){
                    throw 'paired Browser profiler phase/action counts differ'
                  }
                  foreach($phase in @($initial,$restart)){
                    if($phase.role-cne'server' -or -not(Test-Path -LiteralPath $phase.log_path) -or $phase.log_sha256-cne(Get-SessionHash $phase.log_path)){
                      throw 'paired Browser retained phase log provenance differs'
                    }
                  }
                  $initialText=Get-Content -LiteralPath $initial.log_path -Raw
                  $restartText=Get-Content -LiteralPath $restart.log_path -Raw
                  if($initialText-notmatch'first_open' -or $initialText-notmatch'shutdown server-initial' -or $initialText-match'reopen' -or $restartText-notmatch'reopen' -or $restartText-notmatch'shutdown server-restart' -or $restartText-match'first_open'){
                    throw 'paired Browser phase snapshots did not survive a replaced server log'
                  }
                }
                $expectedTail=if($fixtureCase-ceq'library-paired-browser'){
                  'client-restart-en,client-restart-de,server-restart'
                }else{
                  'client-restart-de,client-restart-en,server-restart'
                }
                if(($script:stops.ToArray()|Select-Object -Last 3) -join ',' -cne $expectedTail){throw 'final teardown is not reversed'}
              }else{
                if($null -eq $caught -or (Test-Path -LiteralPath $sessionPath)){throw 'failed session claimed success'}
                $expected=switch($script:mode){
                  'cleanup'{'late native cleanup failure'}
                  'missing-phase'{'paired Browser initial phase log lacks refresh stage'}
                  default{'original session failure'}
                }
                if($caught.Exception.Message -cne $expected){throw 'original session/cleanup failure was replaced'}
                if($fixtureCase -cin @('library-multiplayer','library-paired-browser') -and ($script:memoryWrites -ne 1 -or -not(Test-Path -LiteralPath $processMemoryObservationPath) -or $script:memoryReasons -notcontains 'native-session-failure')){
                  throw 'failed opt-in session lost its incomplete memory receipt'
                }
              }
            }
          }
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-mp-teardown-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_SESSION=str(SESSION), MIR_TEST_WORK=work), check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_library_session_memory_calibration_keeps_the_generic_ceiling(self):
        wrapper = WRAPPER.read_text(encoding="utf-8")
        calibration = json.loads(MEMORY_CALIBRATION.read_text(encoding="utf-8"))

        self.assertIn("[ValidateSet(7168,8192)][int]$SessionExpectedPeakMemoryMiB=8192", wrapper)
        self.assertIn(
            "$FixtureCase -ceq 'library-multiplayer' -or $SessionExpectedPeakMemoryMiB -eq 8192",
            wrapper,
        )
        self.assertIn(
            "-ExpectedPeakMemoryMiB $SessionExpectedPeakMemoryMiB -MaxNewOutputMiB 512",
            wrapper,
        )
        self.assertNotIn("-ExpectedPeakMemoryMiB 8192 -MaxNewOutputMiB 512", wrapper)
        self.assertIn("session_expected_peak_memory_mib=$SessionExpectedPeakMemoryMiB", wrapper)

        self.assertEqual(calibration["profile"]["path"], "tests/profiles/library-multiplayer-f200-2077.json")
        self.assertEqual(
            hashlib.sha256(F200_PROFILE.read_bytes()).hexdigest().upper(),
            calibration["profile"]["sha256"],
        )
        self.assertEqual(calibration["engine"]["sha256"], "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B")
        self.assertEqual(calibration["override"]["parameter"], "SessionExpectedPeakMemoryMiB")
        self.assertEqual(calibration["override"]["default_mib"], 8192)
        self.assertEqual(calibration["override"]["library_mib"], 7168)
        self.assertEqual(calibration["override"]["allowed_mib"], [7168, 8192])
        self.assertEqual(calibration["field_path"], "process.result.peak_sampled_private_bytes")

        peaks = []
        for receipt in calibration["receipts"]:
            with self.subTest(receipt=receipt["run"]):
                path = ROOT / receipt["gzip_path"]
                compressed = path.read_bytes()
                self.assertEqual(hashlib.sha256(compressed).hexdigest().upper(), receipt["gzip_sha256"])
                raw = gzip.decompress(compressed)
                self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), receipt["raw_sha256"])
                captured = json.loads(raw)
                self.assertEqual(captured["status"], "passed-private-two-client-fixture")
                self.assertEqual(captured["source_head"], receipt["source_commit"])
                self.assertEqual(captured["engine"]["sha256"], calibration["engine"]["sha256"])
                self.assertEqual(captured["profile"]["sha256"], calibration["profile"]["sha256"])
                peak = captured["process"]["result"]["peak_sampled_private_bytes"]
                self.assertEqual(peak, receipt["peak_sampled_private_bytes"])
                peaks.append(peak)

        self.assertEqual(max(peaks), calibration["observed_max_private_bytes"])
        self.assertEqual(
            calibration["override"]["library_bytes"] - max(peaks),
            calibration["observed_headroom_bytes"],
        )
        self.assertGreater(calibration["observed_headroom_bytes"], 0)
        self.assertEqual(
            calibration["observed_headroom_percent"],
            round(calibration["observed_headroom_bytes"] * 100 / max(peaks), 1),
        )

        refusal = calibration["refused_current_library_attempt"]
        default_bytes = calibration["override"]["default_mib"] * 1024 * 1024
        self.assertEqual(
            refusal["physical_reserve_bytes"] + default_bytes,
            refusal["default_required_bytes"],
        )
        self.assertEqual(
            refusal["default_required_bytes"] - refusal["free_bytes"],
            refusal["default_deficit_bytes"],
        )
        self.assertEqual(
            refusal["physical_reserve_bytes"] + calibration["override"]["library_bytes"],
            refusal["calibrated_required_bytes"],
        )
        self.assertEqual(
            refusal["free_bytes"] - refusal["calibrated_required_bytes"],
            refusal["calibrated_snapshot_headroom_bytes"],
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LibraryMultiplayerFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

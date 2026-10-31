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
STANDALONE_F210_API_CONSUMERS_PROFILE = ROOT / "tests/profiles/library-api-consumers-standalone-f210-2123.json"
CURRENT_STANDALONE_F210_API_CONSUMERS_PROFILE = ROOT / "tests/profiles/library-api-consumers-current-standalone-f210-2123.json"
CURRENT_STANDALONE_F210_SPACE_AGE_API_CONSUMERS_PROFILE = ROOT / "tests/profiles/library-api-consumers-current-space-age-standalone-f210-2123.json"
PRIVATE_CREDITS_BASE_PROFILE = ROOT / "tests/profiles/library-api-consumers-private-credits-standalone-f210-2123.json"
PRIVATE_CREDITS_SPACE_AGE_PROFILE = ROOT / "tests/profiles/library-api-consumers-private-credits-space-age-standalone-f210-2123.json"
RESTORATION_PREVIEW_PROFILE = ROOT / "tests/profiles/library-restoration-cfeac3-space-age-standalone-f210-2123.json"
RESTORATION_PREVIEW_CALLER = ROOT / "tools/Invoke-LibraryRestorationPreview.ps1"
PRIVATE_CREDITS_INFO = ROOT / "tests/fixtures/library-multiplayer/info-f210-private-credits.json"
F200_PRIVATE_CREDITS_PROFILE = ROOT / "tests/profiles/library-private-credits-current-f200-2077.json"
F200_PRIVATE_CREDITS_INFO = ROOT / "tests/fixtures/library-private-credits-f200/info.json"
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
        self.lua.globals().positive_state_path = (ROOT / "tests/fixtures/library-positive-state/positive-state.lua").as_posix()
        self.lua.execute(r'''
          function run_library_multiplayer_fixture(path, opponent, target)
            local ROOT_NAME="mir_research_browser"
            local FILTERS="mir_library_filters"
            local QUERY="mir_library_query"
            local FAMILY="mir_library_family"
            local SORT="mir_library_sort"
            local TABS="mir_library_tabs"
            local CONTENT="mir_library_research_content"
            local RESULTS="mir_library_results"
            local DETAIL="mir_library_detail"
            local DETAIL_TITLE="mir_library_detail_title"
            local DETAIL_EMPTY="mir_library_detail_empty"
            local ACTIONS="mir_library_actions"
            local OPEN_NATIVE="mir_library_open_native"
            local AVAILABILITY={"mir_library_availability_1","mir_library_availability_2"}
            local AVAILABILITY_FAMILIES={"research_agricultural_growth_speed","research_spoilage_preservation"}
            local key="mir5_library_multiplayer"
            local gear="recipe-prod-research_gears-1"
            local mining="recipe-prod-research_mining_drill-1"
            local private_credit_ids={
              "mir-legacy-module-credit-speed-module",
              "mir-legacy-module-credit-productivity-module",
              "mir-legacy-module-credit-efficiency-module",
              "mir-legacy-cannon-credit-rocket-shooting-speed",
            }
            local private_credit_id_set={}
            for _,id in ipairs(private_credit_ids) do private_credit_id_set[id]=true end
            local gear_packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local gear_ingredients={
              {name=gear_packs[1],amount=1},{name=gear_packs[2],amount=1},
              {name=gear_packs[3],amount=1},{name=gear_packs[4],amount=1},
            }
            local targets={
              f200={base="2.0.77",mir="5.0.20000"},
              f210={base="2.1.23",mir="5.0.21000"},
              ["f210-space-age"]={base="2.1.23",mir="5.0.21000",space_age=true},
              ["f210-private-credits"]={base="2.1.23",mir="5.0.21000",private_credits=true},
              ["f210-space-age-private-credits"]={base="2.1.23",mir="5.0.21000",space_age=true,private_credits=true},
              ["f200-private-credits"]={base="2.0.77",mir="5.0.20000",private_credits=true},
              ["f200-positive-state"]={base="2.0.77",mir="5.0.20000",private_credits=true,positive_state=true},
              ["f210-positive-state"]={base="2.1.23",mir="5.0.21000",private_credits=true,positive_state=true},
            }
            local selected=targets[target or "f200"]
            assert(selected,"unknown fixture target")
            local base_version,mir_version=selected.base,selected.mir
            local gear_recipes=selected.space_age and {"casting-iron-gear-wheel","iron-gear-wheel"} or {"iron-gear-wheel"}
            local gear_effects={}
            for _,name in ipairs(gear_recipes) do
              gear_effects[#gear_effects+1]={type="change-recipe-productivity",recipe=name,change=.1}
            end
            if opponent=="f210-wrong-mir-version" then mir_version="5.0.21001"
            elseif opponent=="unsupported-target-base" then base_version="2.1.24" end
            local players, markers, screenshots, saves, lab_diagnostics = {}, {}, {}, {}, {}
            local seed_diagnostics={}
            local force={valid=true,index=1,name="player",technologies={},recipes={},research_queue={},research_progress=0,research_enabled=true}
            for _,name in ipairs({gear,mining}) do
              force.technologies[name]={valid=true,name=name,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,
                research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients=name==gear and gear_ingredients or nil,
                prototype={effects=name==gear and gear_effects or {{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}}}
            end
            if selected.space_age and opponent~="sa-native-owner-missing" then
              force.technologies["research-productivity"]={valid=true,name="research-productivity",force=force,level=1,researched=false,
                enabled=true,visible_when_disabled=false,prototype={valid=true,name="research-productivity",
                  effects={{type="laboratory-productivity",modifier=.1}}}}
            end
            if opponent=="sa-casting-effect-missing" then
              force.technologies[gear].prototype.effects={{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}
            elseif opponent=="sa-casting-effect-duplicate" then
              force.technologies[gear].prototype.effects={{type="change-recipe-productivity",recipe="casting-iron-gear-wheel",change=.1},
                {type="change-recipe-productivity",recipe="casting-iron-gear-wheel",change=.1},
                {type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}
            elseif opponent=="sa-casting-effect-wrong" then
              force.technologies[gear].prototype.effects={{type="change-recipe-productivity",recipe="casting-iron-gear-wheel",change=.2},
                {type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}
            end
            local ingredients=force.technologies[gear].research_unit_ingredients
            if opponent=="science-missing" then table.remove(ingredients,4)
            elseif opponent=="science-duplicate" then ingredients[5]={name=gear_packs[1],amount=1}
            elseif opponent=="science-extra" then ingredients[5]={name="military-science-pack",amount=1}
            elseif opponent=="science-wrong-amount" then ingredients[3].amount=2
            elseif opponent=="science-reordered" then
              force.technologies[gear].research_unit_ingredients={ingredients[4],ingredients[2],ingredients[1],ingredients[3]}
            end
            for _,name in ipairs(selected.space_age and {"iron-gear-wheel","casting-iron-gear-wheel","burner-mining-drill","electric-mining-drill"} or {"iron-gear-wheel","burner-mining-drill","electric-mining-drill"}) do
              force.recipes[name]={valid=true,name=name,productivity_bonus=0}
            end
            for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}) do
              force.technologies[name]={valid=true,name=name,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false}
            end
            if selected.private_credits and opponent~="private-credit-missing" then
              for index,id in ipairs(private_credit_ids) do
                force.technologies[id]={valid=true,name=id,force=force,level=index,researchable=false,
                  researched=true,enabled=false,visible_when_disabled=false}
              end
            end
            if selected.private_credits then
              force.technologies["automation"]={valid=true,name="automation",force=force,level=1,
                researched=true,enabled=true,visible_when_disabled=false}
            end
            local reset_count, researched_set_calls=0, 0
            if selected.positive_state then
              for _,id in ipairs(private_credit_ids) do
                local tech=force.technologies[id]
                tech.level,tech.researched,tech.prototype=1,false,{valid=true,hidden=true}
              end
              for _,id in ipairs({"speed-module","productivity-module","efficiency-module"}) do
                force.recipes[id]={valid=true,productivity_bonus=0}
              end
              force.technologies["mir5-fixture-foreign-hidden-research"]={valid=true,level=1,researched=false,
                enabled=true,visible_when_disabled=false,prototype={valid=true,hidden=true}}
              force.cannon_speed=0
              force.get_gun_speed_modifier=function(category) assert(category=="cannon-shell");return force.cannon_speed end
              force.reset_technology_effects=function()
                reset_count=reset_count+1
                for index,id in ipairs({"speed-module","productivity-module","efficiency-module"}) do
                  force.recipes[id].productivity_bonus=(force.technologies[private_credit_ids[index]].level-1)*.01
                end
                force.cannon_speed=(force.technologies[private_credit_ids[4]].level-1)*.1
              end
              do
                for holder_index,id in ipairs(private_credit_ids) do
                  local values=force.technologies[id]
                  local function update_effect()
                    if holder_index<=3 then
                      local recipe=({"speed-module","productivity-module","efficiency-module"})[holder_index]
                      force.recipes[recipe].productivity_bonus=(values.level-1)*.01
                    else force.cannon_speed=(values.level-1)*.1 end
                  end
                  force.technologies[id]=setmetatable({}, {
                    __index=function(_,key)return values[key]end,
                    __newindex=function(_,key,value)
                      values[key]=value
                      if key=="researched" then
                        researched_set_calls=researched_set_calls+1
                        if value==false then values.level=1;update_effect() end
                      elseif key=="level" then values.researched=false;update_effect() end
                    end,
                  })
                end
              end
              if opponent=="positive-not-fresh" then force.technologies[private_credit_ids[1]].level=2 end
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
            local private_query_calls, private_query_order = 0, {}
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
              for _,recipe_name in ipairs(gear_recipes) do
                foreign.recipes[recipe_name]={valid=true,name=recipe_name,productivity_bonus=0}
              end
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
              filters[FAMILY]=element("drop-down",FAMILY)
              filters[FAMILY].selected_index=options.family=="all" and 2 or (options.family=="external" and 3 or 1)
              filters.mir_library_visibility=element("drop-down","mir_library_visibility")
              filters.mir_library_visibility.selected_index=options.visibility
              filters[SORT]=element("drop-down",SORT)
              filters[SORT].selected_index=options.sort=="native" and 2 or 1
              local tabs=element("tabbed-pane",TABS)
              root[TABS]=tabs
              local content=element("table",CONTENT)
              content.column_count=2
              content.children={}
              content.style.width=760
              tabs[CONTENT]=content
              local list_width=math.floor((content.style.maximal_width-36)*.4)
              local detail_width=content.style.maximal_width-36-list_width
              local function browser_results()
                local results=element("list-box",RESULTS)
                results.style.width=list_width
                return results
              end
              local function browser_detail()
                local detail=element("scroll-pane",DETAIL)
                detail.horizontal_scroll_policy="never"
                detail.style.width=detail_width
                return detail
              end
              if options.tab=="availability" then
                if selected.space_age then
                  local label=element("label",AVAILABILITY[1])
                  label.caption={"mir-browser.availability-entry",
                    {"technology-name.more-infinite-research.research_lab_productivity"},
                    {opponent=="sa-availability-wrong" and "mir-browser.availability-requires-space-age" or "mir-browser.availability-native-research-productivity"}}
                  content[AVAILABILITY[1]]=label
                  content.children[#content.children+1]=label
                elseif opponent~="missing-availability-label" then
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
              assert(options.visibility==1 or selected.positive_state,"ordinary Library opens must reset Availability visibility")
              if selected.positive_state then
                if options.hidden~=nil then
                  client.personal_hidden={}
                  for _,id in ipairs(options.hidden) do client.personal_hidden[id]=true end
                end
                if options.search=="mir5-fixture-foreign-hidden-research" then
                  local hidden=client.personal_hidden and client.personal_hidden[options.search]==true
                  local present=(options.visibility==1 and not hidden) or (options.visibility==2 and hidden)
                  if opponent=="positive-foreign-suppressed" then present=false end
                  local results=browser_results()
                  results.items=present and {options.search} or {};results.selected_index=present and 1 or 0
                  content[RESULTS]=results
                  local detail=browser_detail()
                  detail[present and DETAIL_TITLE or DETAIL_EMPTY]=element("label",present and DETAIL_TITLE or DETAIL_EMPTY)
                  content[DETAIL]=detail
                  local actions=element("flow",ACTIONS)
                  actions[OPEN_NATIVE]=element("sprite-button",OPEN_NATIVE);actions[OPEN_NATIVE].enabled=present
                  content[ACTIONS]=actions
                  target.gui.screen[ROOT_NAME]=root
                  return
                end
              end
              local private_query=selected.private_credits and private_credit_id_set[options.selected]==true
                and (options.family=="all" or options.family=="external") and options.search==options.selected
              if private_query then
                private_query_calls=private_query_calls+1
                private_query_order[#private_query_order+1]={player=client.index,family=options.family,id=options.selected}
                local results=browser_results()
                results.items={};results.selected_index=0
                if opponent=="private-credit-listed" then
                  results.items={options.selected};results.selected_index=1
                end
                content[RESULTS]=results
                local detail=browser_detail()
                detail[DETAIL_EMPTY]=element("label",DETAIL_EMPTY)
                content[DETAIL]=detail
                local actions=element("flow",ACTIONS)
                actions[OPEN_NATIVE]=element("sprite-button",OPEN_NATIVE)
                actions[OPEN_NATIVE].enabled=opponent=="private-credit-action-enabled"
                content[ACTIONS]=actions
                target.gui.screen[ROOT_NAME]=root
                if opponent=="private-credit-mutate" and private_query_calls==1 then
                  force.technologies[private_credit_ids[1]].level=force.technologies[private_credit_ids[1]].level+1
                end
                return
              end
              local ordinary_private_query=selected.private_credits and (
                (options.family=="all" and options.search==gear and options.selected==gear) or
                (options.family=="external" and options.search=="automation" and options.selected=="automation")
              )
              if ordinary_private_query and (
                (opponent=="private-credit-empty-all" and options.family=="all") or
                (opponent=="private-credit-empty-external" and options.family=="external")
              ) then
                local results=browser_results()
                results.items={};results.selected_index=0
                content[RESULTS]=results
                local detail=browser_detail()
                detail[DETAIL_EMPTY]=element("label",DETAIL_EMPTY)
                content[DETAIL]=detail
                local actions=element("flow",ACTIONS)
                actions[OPEN_NATIVE]=element("sprite-button",OPEN_NATIVE)
                actions[OPEN_NATIVE].enabled=false
                content[ACTIONS]=actions
                target.gui.screen[ROOT_NAME]=root
                return
              end
              if opponent=="private-credit-restore" and private_query_calls>0 and options.family=="mir" then filters[QUERY].text="restoration-failed" end
              if opponent=="private-credit-stale-external-family" and private_query_calls>0 and options.family=="mir" then filters[FAMILY].selected_index=3 end
              local results=browser_results()
              results.items={options.selected};results.selected_index=1
              content[RESULTS]=results
              local detail=browser_detail()
              if opponent=="detail-width-narrow" then detail.style.width=180 end
              detail[DETAIL_TITLE]=element("label",DETAIL_TITLE)
              detail[DETAIL_TITLE].caption=options.selected
              local context=element("flow","mir_library_detail_context")
              detail["mir_library_detail_context"]=context
              context["mir_library_context_status"]=element("label","mir_library_context_status")
              detail["mir_library_detail_level"]=element("label","mir_library_detail_level")
              content[DETAIL]=detail
              if ordinary_private_query then
                local actions=element("flow",ACTIONS)
                actions[OPEN_NATIVE]=element("sprite-button",OPEN_NATIVE)
                actions[OPEN_NATIVE].enabled=true
                content[ACTIONS]=actions
              end
              target.gui.screen[ROOT_NAME]=root
              if ordinary_private_query and opponent=="private-credit-automation-mutate" and options.family=="external" then
                force.technologies["automation"].level=force.technologies["automation"].level+1
              end
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
              if not context then return end
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
              for _,recipe_name in ipairs(gear_recipes) do
                force.recipes[recipe_name].productivity_bonus=force.recipes[recipe_name].productivity_bonus+.1
              end
              force.current_research=force.research_queue[1]
              fire(6,{research=current,by_script=opponent=="script-completion"})
              if force.current_research then fire(4,{research=force.current_research,last_research=current}) end
              return true
            end
            local discovery=opponent=="standalone-identity-discovery"
            local fixture_version=selected.positive_state and "0.4.0" or (selected.private_credits and "0.3.0" or (selected.space_age and "0.2.0" or (discovery and "0.1.1" or "0.1.0")))
            local active_mods={base=base_version,["more-infinite-research"]=mir_version,["mir-fixture-mir5-library-multiplayer"]=fixture_version,["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            if selected.space_age then
              active_mods["elevated-rails"]="2.1.23"
              active_mods.quality="2.1.23"
              active_mods.recycler="2.1.23"
              active_mods["space-age"]="2.1.23"
            end
            local private_without_api=selected.private_credits and opponent=="private-credit-missing-api"
            if (opponent=="f210-api-consumers" or selected.space_age or selected.private_credits) and not private_without_api then
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
            if selected.space_age then
              if opponent=="sa-dlc-partial" then active_mods.recycler=nil
              elseif opponent=="sa-api-alpha-only" then active_mods["mir-fixture-mir5-api-beta"]=nil
              elseif opponent=="sa-api-beta-only" then active_mods["mir-fixture-mir5-api-alpha"]=nil end
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
                if value.seed_stage then seed_diagnostics[#seed_diagnostics+1]=value
                elseif value.science_counts then lab_diagnostics[#lab_diagnostics+1]=value
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
                    or value:match("^%[MIR5_LIBRARY_POSITIVE_SEED%] ")
                    or value:match("^%[MIR5_LIBRARY_LAB_DIAGNOSTIC%] "))
                end
              end,
            }
            environment._G=environment;setmetatable(environment,{__index=function(_,name)return _G[name]end})
            environment.require=function(name)
              assert(name=="positive-state" and selected.positive_state,"unexpected fixture import")
              if opponent=="positive-researched-setter-resets-level" then
                local stream=assert(io.open(positive_state_path,"r"));local body=stream:read("*a");stream:close()
                local changed,count=body:gsub("technology.level = index %+ 1","technology.level = index + 1\n    technology.researched = false")
                assert(count==1,"seed mutation did not target the single level assignment")
                return assert(load(changed,"fixture-seed-opponent","t",environment))()
              end
              local module,message=loadfile(positive_state_path,"t",environment);assert(module,message)
              return module()
            end
            local chunk,message=loadfile(path,"t",environment);assert(chunk,message)
            local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)} end
            local function call(callback,event)
              local success,value=pcall(callback,event)
              return success,tostring(value)
            end
            ok,result=call(callbacks.init);if not ok then return {ok=false,message=result,seed_diagnostics=seed_diagnostics,researched_set_calls=researched_set_calls} end
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
            if selected.positive_state then
              if opponent=="positive-holder-lost" then force.technologies[private_credit_ids[1]].level=1
              elseif opponent=="positive-holder-enabled" then force.technologies[private_credit_ids[4]].enabled=true
              elseif opponent=="positive-module-lost" then force.recipes["productivity-module"].productivity_bonus=0
              elseif opponent=="positive-cannon-lost" then force.cannon_speed=0
              elseif opponent=="positive-foreign-flags" then force.technologies["mir5-fixture-foreign-hidden-research"].prototype.hidden=false
              elseif opponent=="positive-personal-hidden-lost" then en.personal_hidden={} end
            end
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
              rejected_bulk_inserts=rejected_bulk_inserts,private_query_calls=private_query_calls,
              private_query_order=private_query_order,positive_seed_resets=reset_count,seed_diagnostics=seed_diagnostics,researched_set_calls=researched_set_calls}
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

    def test_standalone_f210_api_client_profile_binds_the_exact_current_six_mod_closure(self):
        profile = json.loads(STANDALONE_F210_API_CONSUMERS_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile["kind"], "mir5-library-api-consumers-standalone-f210-native-selection")
        self.assertEqual((profile["target"], profile["factorio_line"], profile["settings_mode"]),
                         ("f210-standalone", "2.1", "Defaults"))
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
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
                "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0",
            "more-infinite-research_5.0.21000.zip":
                "2ABAF369E020D8AD18A0C04940A8811BECFA5E63E5B479C668E2D3A3123D032B",
            "mir-fixture-mir5-api-alpha_0.1.0.zip":
                "DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904",
            "mir-fixture-mir5-api-beta_0.1.0.zip":
                "690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951",
        })
        self.assertNotIn("mir-fixture-mir5-api-beta-production", {row["name"] for row in profile["mods"]})

    def test_current_standalone_f210_api_client_profile_binds_the_new_current_archive_and_six_mod_closure(self):
        profile = json.loads(CURRENT_STANDALONE_F210_API_CONSUMERS_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile["kind"], "mir5-library-api-consumers-current-standalone-f210-native-selection")
        self.assertEqual((profile["target"], profile["factorio_line"], profile["settings_mode"],
                          profile["session_expected_peak_memory_mib"]),
                         ("f210-standalone", "2.1", "Defaults", 7168))
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
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
                "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0",
            "more-infinite-research_5.0.21000.zip":
                "A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D",
            "mir-fixture-mir5-api-alpha_0.1.0.zip":
                "DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904",
            "mir-fixture-mir5-api-beta_0.1.0.zip":
                "690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951",
        })
        self.assertNotIn("mir-fixture-mir5-api-beta-production", {row["name"] for row in profile["mods"]})

    def test_current_standalone_f210_space_age_api_client_profile_binds_the_exact_ten_mod_closure(self):
        profile = json.loads(CURRENT_STANDALONE_F210_SPACE_AGE_API_CONSUMERS_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile["kind"], "mir5-library-api-consumers-current-space-age-standalone-f210-native-selection")
        self.assertEqual((profile["target"], profile["factorio_line"], profile["settings_mode"],
                          profile["session_expected_peak_memory_mib"], profile["space_age_library"]),
                         ("f210-standalone", "2.1", "Defaults", 8192, True))
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
        })
        self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]], [
            ("base", "2.1.23", True),
            ("elevated-rails", "2.1.23", True),
            ("quality", "2.1.23", True),
            ("recycler", "2.1.23", True),
            ("space-age", "2.1.23", True),
            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ("more-infinite-research", "5.0.21000", True),
            ("mir-fixture-mir5-library-multiplayer", "0.2.0", True),
            ("mir-fixture-mir5-api-alpha", "0.1.0", True),
            ("mir-fixture-mir5-api-beta", "0.1.0", True),
        ])
        self.assertEqual(profile["archive_sha256"], {
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0",
            "more-infinite-research_5.0.21000.zip":
                "A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D",
            "mir-fixture-mir5-api-alpha_0.1.0.zip":
                "DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904",
            "mir-fixture-mir5-api-beta_0.1.0.zip":
                "690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951",
        })
        self.assertNotIn("mir-fixture-mir5-api-beta-production", {row["name"] for row in profile["mods"]})

    def test_private_credit_profiles_bind_the_current_archive_and_distinct_base_and_space_age_closures(self):
        cases = (
            (PRIVATE_CREDITS_BASE_PROFILE,
             "mir5-library-api-consumers-private-credits-standalone-f210-native-selection", 7168, False,
             [
                 ("base", "2.1.23"),
                 ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                 ("more-infinite-research", "5.0.21000"),
                 ("mir-fixture-mir5-library-multiplayer", "0.3.0"),
                 ("mir-fixture-mir5-api-alpha", "0.1.0"),
                 ("mir-fixture-mir5-api-beta", "0.1.0"),
             ]),
            (PRIVATE_CREDITS_SPACE_AGE_PROFILE,
             "mir5-library-api-consumers-private-credits-space-age-standalone-f210-native-selection", 8192, True,
             [
                 ("base", "2.1.23"),
                 ("elevated-rails", "2.1.23"),
                 ("quality", "2.1.23"),
                 ("recycler", "2.1.23"),
                 ("space-age", "2.1.23"),
                 ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                 ("more-infinite-research", "5.0.21000"),
                 ("mir-fixture-mir5-library-multiplayer", "0.3.0"),
                 ("mir-fixture-mir5-api-alpha", "0.1.0"),
                 ("mir-fixture-mir5-api-beta", "0.1.0"),
             ]),
        )
        for path, kind, memory_mib, space_age, expected_mods in cases:
            with self.subTest(profile=path.name):
                profile = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual((profile["kind"], profile["target"], profile["factorio_line"],
                                  profile["settings_mode"], profile["session_expected_peak_memory_mib"]),
                                 (kind, "f210-standalone", "2.1", "Defaults", memory_mib))
                self.assertEqual(profile["engine"], {
                    "version": "2.1.23",
                    "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
                })
                self.assertTrue(profile["private_credit_checks"])
                self.assertEqual(profile.get("space_age_library", False), space_age)
                self.assertEqual([(row["name"], row["version"]) for row in profile["mods"]], expected_mods)
                self.assertTrue(all(row["enabled"] is True for row in profile["mods"]))
                self.assertEqual(profile["archive_sha256"], {
                    "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                        "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0",
                    "more-infinite-research_5.0.21000.zip":
                        "2DDD2A4C967BEF07830218442AE4441BEECD5B9ECE0AC86B09A5F6586BBA80E5",
                    "mir-fixture-mir5-api-alpha_0.1.0.zip":
                        "DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904",
                    "mir-fixture-mir5-api-beta_0.1.0.zip":
                        "690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951",
                })
                self.assertNotIn("mir-fixture-mir5-api-beta-production", {row["name"] for row in profile["mods"]})

    def test_restored_library_preview_pins_its_exact_space_age_package_and_rejects_drift(self):
        profile = json.loads(RESTORATION_PREVIEW_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual((profile["kind"], profile["target"], profile["factorio_line"],
                          profile["settings_mode"], profile["session_expected_peak_memory_mib"]),
                         ("mir5-library-restoration-cfeac3-space-age-standalone-f210-native-selection",
                          "f210-standalone", "2.1", "Defaults", 8192))
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
        })
        self.assertTrue(profile["space_age_library"])
        self.assertTrue(profile["api_client_consumers"])
        self.assertTrue(profile["private_credit_checks"])
        self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]], [
            ("base", "2.1.23", True),
            ("elevated-rails", "2.1.23", True),
            ("quality", "2.1.23", True),
            ("recycler", "2.1.23", True),
            ("space-age", "2.1.23", True),
            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ("more-infinite-research", "5.0.21000", True),
            ("mir-fixture-mir5-library-multiplayer", "0.3.0", True),
            ("mir-fixture-mir5-api-alpha", "0.1.0", True),
            ("mir-fixture-mir5-api-beta", "0.1.0", True),
        ])
        self.assertEqual(profile["archive_sha256"], {
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0",
            "more-infinite-research_5.0.21000.zip":
                "1EF57E3ACD05BE9B1097AC3744C913933A7784FE6513F12C2771B0096CDB2029",
            "mir-fixture-mir5-api-alpha_0.1.0.zip":
                "DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904",
            "mir-fixture-mir5-api-beta_0.1.0.zip":
                "0E48351A5D515506B133ED16FE265119D72EB781FA2A4473D1771C451C3EB633",
        })
        self.assertIn("restored Library and read-only responsive table layout", profile["scope"])
        self.assertIn("cfeac3e8a6583576f6d0165a9f5cf6a9087b441e", profile["scope"])
        self.assertIn("does not replace or qualify the published beta", profile["scope"])

        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          function Assert-Session([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          $node=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'
          },$true))
          if($node.Count-ne1){throw 'selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $profile=Get-Content -LiteralPath $env:MIR_TEST_RESTORATION_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $mir='1EF57E3ACD05BE9B1097AC3744C913933A7784FE6513F12C2771B0096CDB2029'
          $engine='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
          $target=Assert-MultiplayerFixtureSelection -Selection $profile -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $mir -SessionExpectedPeakMemoryMiB 8192
          if($target.kind-cne'mir5-library-restoration-cfeac3-space-age-standalone-f210-native-selection' -or
             $target.mir_archive_sha256-cne$mir -or -not$target.space_age_library -or -not$target.private_credit_checks -or -not$target.api_client_consumers){
            throw 'restored Library preview target differs'
          }
          function Assert-Rejected([string]$Name,[scriptblock]$Mutate,[string]$Expected=$mir,[int]$Budget=8192){
            $bad=$profile|ConvertTo-Json -Depth 16|ConvertFrom-Json -AsHashtable
            &$Mutate $bad
            try{$null=Assert-MultiplayerFixtureSelection -Selection $bad -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $Expected -SessionExpectedPeakMemoryMiB $Budget}catch{return}
            throw "restored Library preview admitted drift: $Name"
          }
          Assert-Rejected 'wrong candidate package' {param($s)$s.archive_sha256['more-infinite-research_5.0.21000.zip']='A'*64}
          Assert-Rejected 'wrong beta consumer archive' {param($s)$s.archive_sha256['mir-fixture-mir5-api-beta_0.1.0.zip']='C'*64}
          Assert-Rejected 'wrong expected package' {} ('B'*64)
          Assert-Rejected 'wrong Space Age closure' {param($s)$s.mods=@($s.mods|Where-Object {$_.name-cne'space-age'})}
          Assert-Rejected 'missing private credit mode' {param($s)$s.Remove('private_credit_checks')|Out-Null}
          Assert-Rejected 'wrong session admission' {} $mir 7168
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_RESTORATION_PROFILE=str(RESTORATION_PREVIEW_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_restored_library_preview_rejects_nested_input_and_output_roots_before_mode_work(self):
        caller = RESTORATION_PREVIEW_CALLER.read_text(encoding="utf-8")
        guard_position = caller.index("Assert-PreviewRootsDisjoint -InputRoot")
        prepare_position = caller.index("if($Mode-ceq'Prepare')")
        self.assertLess(guard_position, prepare_position)
        self.assertLess(guard_position, caller.index("Start-MIRNativeArchiveLease -LibraryDirectory"))
        self.assertIn("runner_invoked=$false;native_execution_succeeded=$false", caller)
        self.assertLess(caller.index("$result.runner_invoked=$true"), caller.index("$runnerResult=& $runner"))
        self.assertLess(caller.index("$runnerResult=& $runner"), caller.index("$result.native_execution_succeeded=$true"))
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_PREVIEW_CALLER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          $node=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-PreviewRootsDisjoint'
          },$true))
          $pathNode=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-PreviewBuildPath'
          },$true))
          if($node.Count-ne1-or$pathNode.Count-ne1){throw 'preview path guards are absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $root=$env:MIR_TEST_WORK;$repo=$root
          foreach($path in @((Join-Path $repo 'build/qualification'),(Join-Path $repo 'build/tmp'),(Join-Path $repo 'build/p'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
          $script:libraryChecks=[Collections.Generic.List[string]]::new();$script:reparseTarget=''
          function Assert-MIRLibraryPath([string]$Path){$full=[IO.Path]::GetFullPath($Path);$script:libraryChecks.Add($full);if($full-ceq$script:reparseTarget){throw '[test-reparse-target]'};$item=Get-Item -LiteralPath $full -Force;while($null-ne$item){if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'unexpected reparse path'};$item=if($item -is [IO.DirectoryInfo]){$item.Parent}else{$item.Directory}}}
          Invoke-Expression $pathNode[0].Extent.Text
          $packet=Join-Path $root 'packet';$native=Join-Path $packet 'native';$parent=Join-Path $root 'parent';$child=Join-Path $parent 'child'
          function Assert-OverlapRejected([string]$InputRoot,[string]$OutputRoot){
            $rejected=$false;try{Assert-PreviewRootsDisjoint -InputRoot $InputRoot -OutputRoot $OutputRoot}catch{$rejected=$_.Exception.Message -like '*must be separate, non-nested directories*'}
            if(-not$rejected){throw "overlapping roots were admitted: $InputRoot | $OutputRoot"}
            if((Test-Path -LiteralPath $InputRoot)-or(Test-Path -LiteralPath $OutputRoot)){throw 'path guard created an input or output root'}
          }
          Assert-OverlapRejected $packet $native
          Assert-OverlapRejected $child $parent
          Assert-PreviewRootsDisjoint -InputRoot (Join-Path $root 'input') -OutputRoot (Join-Path $root 'output')
          $nonce=[guid]::NewGuid().ToString('N')
          $input=Assert-PreviewBuildPath -Path (Join-Path $repo ('build/qualification/'+$nonce+'-input')) -Context 'InputRoot'
          $tmpOutput=Assert-PreviewBuildPath -Path (Join-Path $repo ('build/tmp/'+$nonce+'-output')) -Context 'OutputRoot'
          $pOutput=Assert-PreviewBuildPath -Path (Join-Path $repo ('build/p/'+$nonce+'-output')) -Context 'OutputRoot'
          foreach($bad in @(
            [pscustomobject]@{path=(Join-Path $repo ('build/tmp/'+$nonce+'-input'));context='InputRoot'},
            [pscustomobject]@{path=(Join-Path $repo ('build/qualification/'+$nonce+'-output'));context='OutputRoot'}
          )){$rejected=$false;try{Assert-PreviewBuildPath -Path $bad.path -Context $bad.context|Out-Null}catch{$rejected=$true};if(-not$rejected){throw "preview path policy admitted $($bad.context): $($bad.path)"}}
          $reparseTarget=Join-Path $repo ('build/qualification/'+$nonce+'-existing-input');[IO.Directory]::CreateDirectory($reparseTarget)|Out-Null;$script:reparseTarget=[IO.Path]::GetFullPath($reparseTarget);$script:libraryChecks.Clear()
          $reparseRejected=$false;try{Assert-PreviewBuildPath -Path $reparseTarget -Context 'InputRoot'|Out-Null}catch{$reparseRejected=$_.Exception.Message -ceq'[test-reparse-target]'}
          if(-not$reparseRejected-or-not($script:libraryChecks-contains$script:reparseTarget)){throw 'existing input-root target was not inspected for reparse state'}
          if((Test-Path -LiteralPath $input)-or(Test-Path -LiteralPath $tmpOutput)-or(Test-Path -LiteralPath $pOutput)){throw 'preview path policy created a directory'}
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-preview-roots-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_PREVIEW_CALLER=str(RESTORATION_PREVIEW_CALLER), MIR_TEST_WORK=work),
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_f200_private_profile_and_prelaunch_guards_require_exact_six_mod_inputs(self):
        selection = json.loads(F200_PRIVATE_CREDITS_PROFILE.read_text(encoding='utf-8'))
        info = json.loads(F200_PRIVATE_CREDITS_INFO.read_text(encoding='utf-8'))
        self.assertEqual((info['name'], info['version'], info['factorio_version']),
                         ('mir-fixture-mir5-library-multiplayer', '0.3.0', '2.0'))
        self.assertEqual(info['dependencies'], ['base >= 2.0.77', 'more-infinite-research = 5.0.20000'])
        self.assertEqual({r['name'] for r in selection['mods']}, {
            'base', 'more-infinite-research', 'mir-fixture-mir5-active-mods-observer',
            'mir-fixture-mir5-library-multiplayer', 'mir-fixture-mir5-api-alpha', 'mir-fixture-mir5-api-beta',
        })
        self.assertEqual(selection['archive_sha256']['more-infinite-research_5.0.20000.zip'],
                         '1D45A54DB6F911F665A019897518E46D6614AE7E56903B067F93E116DFC2554F')
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'wrapper parse failed'}
          $found=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Assert-MultiplayerFixtureSelection'},$true))
          if($found.Count-ne1){throw 'selection guard missing'}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          Invoke-Expression $found[0].Extent.Text
          $original=Get-Content -LiteralPath $env:MIR_TEST_PROFILE -Raw|ConvertFrom-Json -AsHashtable
          $engine='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B'
          $mir='1D45A54DB6F911F665A019897518E46D6614AE7E56903B067F93E116DFC2554F'
          $accepted=Assert-MultiplayerFixtureSelection $original $engine 'library-multiplayer' $mir 7168
          if($accepted.base-cne'2.0.77'-or-not$accepted.private_credit_checks-or-not$accepted.api_client_consumers){throw 'valid fixed F200 private selection rejected'}
          foreach($opponent in @('wrong-engine','wrong-player','wrong-case','wrong-budget','no-private','missing-beta','extra-mod','wrong-api-archive','wrong-mir-version')){
            $selection=$original|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
            $actualEngine=$engine;$actualMir=$mir;$case='library-multiplayer';$budget=7168
            switch($opponent){
              'wrong-engine'{$actualEngine='A'*64}
              'wrong-player'{$actualMir='B'*64}
              'wrong-case'{$case='library-paired-browser'}
              'wrong-budget'{$budget=8192}
              'no-private'{$selection.private_credit_checks=$false}
              'missing-beta'{$selection.mods=@($selection.mods|Where-Object name -CNE 'mir-fixture-mir5-api-beta')}
              'extra-mod'{$selection.mods+=@{name='foreign-extra';version='1.0.0';enabled=$true}}
              'wrong-api-archive'{$selection.archive_sha256['mir-fixture-mir5-api-alpha_0.1.0.zip']='C'*64}
              'wrong-mir-version'{($selection.mods|Where-Object name -CEQ 'more-infinite-research').version='5.0.21000'}
            }
            $caught=$false
            try{Assert-MultiplayerFixtureSelection $selection $actualEngine $case $actualMir $budget|Out-Null}catch{$caught=$true}
            if(-not$caught){throw "invalid F200 private input admitted:$opponent"}
          }
          $session=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          $guard=@($session.EndBlock.Statements|Where-Object {$_.Extent.Text.EndsWith("'API client consumer target differs'",[StringComparison]::Ordinal)})
          if($guard.Count-ne1){throw 'API target guard missing'}
          $check=[scriptblock]::Create($guard[0].Extent.Text)
          $apiClientConsumers=$true;$libraryWitnessTarget=[pscustomobject]@{base='2.0.77';mir='5.0.20000'}
          $spec=@{private_credit_checks=$true};&$check
          foreach($spec in @(@{},@{private_credit_checks=$false})){
            $caught=$false;try{&$check}catch{$caught=$true};if(-not$caught){throw 'ordinary F200 API-only mode admitted'}
          }
        '''
        completed = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                   capture_output=True, text=True, check=False,
                                   env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_SESSION=str(SESSION),
                                            MIR_TEST_PROFILE=str(F200_PRIVATE_CREDITS_PROFILE)))
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_multiplayer_wrapper_admits_only_the_exact_standalone_api_client_profile(self):
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
          function Read-Profile {Get-Content -LiteralPath $env:MIR_TEST_STANDALONE_API_CLIENT_PROFILE -Raw|ConvertFrom-Json -AsHashtable}
          $engine='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
          $selected=Assert-MultiplayerFixtureSelection -Selection (Read-Profile) -EngineSha256 $engine -FixtureCase 'library-multiplayer'
          if($selected.kind-cne'mir5-library-api-consumers-standalone-f210-native-selection'-or$selected.standalone_f210-ne$true-or$selected.api_client_consumers-ne$true){throw 'standalone API client target differs'}
          function Assert-Rejected([string]$Name,[scriptblock]$Mutate,[string]$Engine=$engine){
            $selection=Read-Profile;&$Mutate $selection
            try{$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $Engine -FixtureCase 'library-multiplayer'}catch{return}
            throw "standalone API client profile accepted opponent: $Name"
          }
          Assert-Rejected 'wrong engine' {param($s)$s['engine']['sha256']='A'*64}
          Assert-Rejected 'engine argument differs' {} ('A'*64)
          Assert-Rejected 'alpha missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-alpha'})}
          Assert-Rejected 'beta missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-beta'})}
          Assert-Rejected 'unexpected beta production' {param($s)$s['mods']=@($s['mods'])+@([ordered]@{name='mir-fixture-mir5-api-beta-production';version='0.1.0';enabled=$true})}
          Assert-Rejected 'wrong current MIR archive' {param($s)$s['archive_sha256']['more-infinite-research_5.0.21000.zip']='A'*64}
          Assert-Rejected 'wrong standalone observer projection' {param($s)$s['archive_sha256']['mir-fixture-mir5-active-mods-observer_0.1.0.zip']='A'*64}
          Assert-Rejected 'wrong alpha consumer archive' {param($s)$s['archive_sha256']['mir-fixture-mir5-api-alpha_0.1.0.zip']='A'*64}
          Assert-Rejected 'wrong beta consumer archive' {param($s)$s['archive_sha256']['mir-fixture-mir5-api-beta_0.1.0.zip']='A'*64}
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_STANDALONE_API_CLIENT_PROFILE=str(STANDALONE_F210_API_CONSUMERS_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiplayer_wrapper_admits_only_the_exact_current_standalone_api_client_profile_before_admission(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'
          },$true))
          if($node.Count-ne1){throw 'selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          function Read-Profile {Get-Content -LiteralPath $env:MIR_TEST_CURRENT_STANDALONE_API_CLIENT_PROFILE -Raw|ConvertFrom-Json -AsHashtable}
          $engine='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
          $current='A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D'
          $old='2ABAF369E020D8AD18A0C04940A8811BECFA5E63E5B479C668E2D3A3123D032B'
          $selected=Assert-MultiplayerFixtureSelection -Selection (Read-Profile) -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $current -SessionExpectedPeakMemoryMiB 7168
          if($selected.kind-cne'mir5-library-api-consumers-current-standalone-f210-native-selection'-or$selected.standalone_f210-ne$true-or$selected.api_client_consumers-ne$true){throw 'current standalone API client target differs'}
          function Assert-Rejected([string]$Name,[scriptblock]$Mutate,[string]$Expected=$current,[int]$Peak=7168){
            $selection=Read-Profile;&$Mutate $selection
            try{$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $Expected -SessionExpectedPeakMemoryMiB $Peak}catch{return}
            throw "current standalone API client profile accepted opponent: $Name"
          }
          Assert-Rejected 'old MIR archive argument' {} $old
          Assert-Rejected 'old MIR archive profile binding' {param($s)$s['archive_sha256']['more-infinite-research_5.0.21000.zip']=$old}
          Assert-Rejected 'wrong session admission' {} $current 8192
          Assert-Rejected 'alpha missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-alpha'})}
          Assert-Rejected 'unexpected Space Age closure' {param($s)$s['mods']=@($s['mods'])+@([ordered]@{name='space-age';version='2.1.23';enabled=$true})}
          Assert-Rejected 'wrong beta consumer archive' {param($s)$s['archive_sha256']['mir-fixture-mir5-api-beta_0.1.0.zip']='A'*64}
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_CURRENT_STANDALONE_API_CLIENT_PROFILE=str(CURRENT_STANDALONE_F210_API_CONSUMERS_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiplayer_wrapper_admits_only_the_exact_current_standalone_space_age_api_client_profile_before_admission(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'
          },$true))
          if($node.Count-ne1){throw 'selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          function Read-Profile {Get-Content -LiteralPath $env:MIR_TEST_CURRENT_STANDALONE_SPACE_AGE_API_CLIENT_PROFILE -Raw|ConvertFrom-Json -AsHashtable}
          $engine='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
          $current='A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D'
          $selected=Assert-MultiplayerFixtureSelection -Selection (Read-Profile) -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $current -SessionExpectedPeakMemoryMiB 8192
          if($selected.kind-cne'mir5-library-api-consumers-current-space-age-standalone-f210-native-selection'-or$selected.standalone_f210-ne$true-or$selected.api_client_consumers-ne$true-or$selected.space_age_library-ne$true){throw 'current standalone Space Age API client target differs'}
          $graphics=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text-ceq'$clientGraphics'
          },$true))
          if($graphics.Count-ne1){throw 'multiplayer client graphics selection is missing or ambiguous'}
          function Assert-Graphics([string]$Case,[bool]$SpaceAge,[string]$Expected,[string]$Name){
            $FixtureCase=$Case;$spaceAgeLibrary=$SpaceAge;$clientGraphics=$null
            Invoke-Expression $graphics[0].Extent.Text
            if((@($clientGraphics)-join'|')-cne$Expected){throw "client graphics selection differs: $Name"}
          }
          Assert-Graphics 'library-multiplayer' $true '--force-graphics-preset|low|--video-memory-usage|low' 'Space Age Library'
          Assert-Graphics 'library-multiplayer' $false '' 'Base Library'
          Assert-Graphics 'scripted-effects-multiplayer' $false '--force-graphics-preset|low|--video-memory-usage|low' 'existing scripted-effects'
          function Assert-Rejected([string]$Name,[scriptblock]$Mutate,[string]$Expected=$current,[int]$Peak=8192){
            $selection=Read-Profile;&$Mutate $selection
            try{$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $Expected -SessionExpectedPeakMemoryMiB $Peak}catch{return}
            throw "current standalone Space Age API client profile accepted opponent: $Name"
          }
          Assert-Rejected 'wrong session admission' {} $current 7168
          Assert-Rejected 'space age flag false' {param($s)$s['space_age_library']=$false}
          Assert-Rejected 'Space Age companion missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'recycler'})}
          Assert-Rejected 'unexpected extra mod' {param($s)$s['mods']=@($s['mods'])+@([ordered]@{name='mir-fixture-mir5-api-beta-production';version='0.1.0';enabled=$true})}
          Assert-Rejected 'alpha missing' {param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-alpha'})}
          Assert-Rejected 'wrong beta consumer archive' {param($s)$s['archive_sha256']['mir-fixture-mir5-api-beta_0.1.0.zip']='A'*64}
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_CURRENT_STANDALONE_SPACE_AGE_API_CLIENT_PROFILE=str(CURRENT_STANDALONE_F210_SPACE_AGE_API_CONSUMERS_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiplayer_wrapper_admits_only_the_exact_current_private_credit_base_and_space_age_profiles_before_admission(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          $node=@($ast.FindAll({param($candidate)
            $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq 'Assert-MultiplayerFixtureSelection'
          },$true))
          if($node.Count-ne1){throw 'selection function is absent or ambiguous'}
          Invoke-Expression $node[0].Extent.Text
          $engine='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'
          $mir='2DDD2A4C967BEF07830218442AE4441BEECD5B9ECE0AC86B09A5F6586BBA80E5'
          function Read-Profile([string]$Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -AsHashtable}
          function Assert-Selected([string]$Path,[int]$Peak,[bool]$SpaceAge,[string]$Kind){
            $selected=Assert-MultiplayerFixtureSelection -Selection (Read-Profile $Path) -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $mir -SessionExpectedPeakMemoryMiB $Peak
            $spaceAgeProperty=$selected.PSObject.Properties['space_age_library']
            $actualSpaceAge=[bool]($null-ne$spaceAgeProperty -and $spaceAgeProperty.Value -eq $true)
            if($selected.kind-cne$Kind-or$selected.private_credit_checks-ne$true-or$selected.api_client_consumers-ne$true-or$actualSpaceAge-ne$SpaceAge){throw "private-credit target differs: $Kind"}
          }
          function Assert-Rejected([string]$Name,[string]$Path,[int]$Peak,[scriptblock]$Mutate,[switch]$Discovery){
            $selection=Read-Profile $Path;&$Mutate $selection
            try{
              if($Discovery){$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $mir -SessionExpectedPeakMemoryMiB $Peak -StandaloneIdentityDiscovery}
              else{$null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 $engine -FixtureCase 'library-multiplayer' -ExpectedMIRArchiveSha256 $mir -SessionExpectedPeakMemoryMiB $Peak}
            }catch{return}
            throw "private-credit profile accepted opponent: $Name"
          }
          Assert-Selected $env:MIR_TEST_PRIVATE_CREDIT_BASE_PROFILE 7168 $false 'mir5-library-api-consumers-private-credits-standalone-f210-native-selection'
          Assert-Selected $env:MIR_TEST_PRIVATE_CREDIT_SPACE_AGE_PROFILE 8192 $true 'mir5-library-api-consumers-private-credits-space-age-standalone-f210-native-selection'
          foreach($case in @(
            @{path=$env:MIR_TEST_PRIVATE_CREDIT_BASE_PROFILE;peak=7168;name='base false mode';mutate={param($s)$s['private_credit_checks']=$false}},
            @{path=$env:MIR_TEST_PRIVATE_CREDIT_BASE_PROFILE;peak=7168;name='base missing API';mutate={param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-alpha'})}},
            @{path=$env:MIR_TEST_PRIVATE_CREDIT_BASE_PROFILE;peak=7168;name='base wrong fixture version';mutate={param($s)foreach($row in $s['mods']){if($row.name-ceq'mir-fixture-mir5-library-multiplayer'){$row.version='0.2.0'}}}},
            @{path=$env:MIR_TEST_PRIVATE_CREDIT_SPACE_AGE_PROFILE;peak=8192;name='SA false mode';mutate={param($s)$s['private_credit_checks']=$false}},
            @{path=$env:MIR_TEST_PRIVATE_CREDIT_SPACE_AGE_PROFILE;peak=8192;name='SA missing API';mutate={param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'mir-fixture-mir5-api-beta'})}},
            @{path=$env:MIR_TEST_PRIVATE_CREDIT_SPACE_AGE_PROFILE;peak=8192;name='SA companion missing';mutate={param($s)$s['mods']=@($s['mods']|Where-Object {$_.name-cne'recycler'})}}
          )){Assert-Rejected $case.name $case.path $case.peak $case.mutate}
          Assert-Rejected 'private-credit discovery mode' $env:MIR_TEST_PRIVATE_CREDIT_BASE_PROFILE 7168 {} -Discovery
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER),
                     MIR_TEST_PRIVATE_CREDIT_BASE_PROFILE=str(PRIVATE_CREDITS_BASE_PROFILE),
                     MIR_TEST_PRIVATE_CREDIT_SPACE_AGE_PROFILE=str(PRIVATE_CREDITS_SPACE_AGE_PROFILE)),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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
          foreach($name in @('Resolve-StandaloneF210ApiConsumerSourceRevision','Get-StandaloneF210NativeFixtureGitMembers','Get-StandaloneF210NativeFixtureRawGitMemberBytes','New-StandaloneF210LibraryFixtureSourceProjection','New-StandaloneIdentityObserverSourceProjection','Get-StandaloneIdentityFixtureSources','Invoke-MultiplayerFixturePreparation')){
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
          $sourceRevision=Resolve-StandaloneF210ApiConsumerSourceRevision -RepoRoot $repo
          $normal=New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $repo -OutputRoot (Join-Path $root 'normal-output') -SourceRevision $sourceRevision
          $normalInfo=Get-Content -LiteralPath (Join-Path $normal.source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
          if($normal.members.Count-ne3 -or $normal.source_metadata-cne'info-f210.json' -or ((@($normal.excluded_canonical_members)-join'|')-cne'info-f210-private-credits.json|info-f210-space-age.json|info.json|README.md') -or [string]$normalInfo.factorio_version-cne'2.1' -or [string]$normalInfo.version-cne'0.1.0' -or ((@($normalInfo.dependencies)-join'|')-cne'base >= 2.1.23|more-infinite-research = 5.0.21000')){throw 'normal F210 projection metadata differs'}
          $fixtureArchive=New-SourceArchive -Library $library -Source $normal.source -Members @('control.lua','info.json','settings-updates.lua')
          $spaceAge=New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $repo -OutputRoot (Join-Path $root 'space-age-output') -SourceRevision $sourceRevision -SpaceAgeLibrary
          $spaceAgeInfo=Get-Content -LiteralPath (Join-Path $spaceAge.source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
          if($spaceAge.members.Count-ne3 -or $spaceAge.source_metadata-cne'info-f210-space-age.json' -or ((@($spaceAge.excluded_canonical_members)-join'|')-cne'info-f210-private-credits.json|info-f210.json|info.json|README.md') -or [string]$spaceAgeInfo.factorio_version-cne'2.1' -or [string]$spaceAgeInfo.version-cne'0.2.0' -or ((@($spaceAgeInfo.dependencies)-join'|')-cne'base >= 2.1.23|space-age >= 2.1.23|more-infinite-research = 5.0.21000')){throw 'Space Age F210 projection metadata differs'}
          $spaceAgeArchive=New-SourceArchive -Library $library -Source $spaceAge.source -Members @('control.lua','info.json','settings-updates.lua')
          $private=New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $repo -OutputRoot (Join-Path $root 'private-credit-output') -SourceRevision $sourceRevision -PrivateCreditChecks
          $privateInfo=Get-Content -LiteralPath (Join-Path $private.source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
          if($private.members.Count-ne3 -or $private.source_metadata-cne'info-f210-private-credits.json' -or ((@($private.excluded_canonical_members)-join'|')-cne'info-f210-space-age.json|info-f210.json|info.json|README.md') -or [string]$privateInfo.factorio_version-cne'2.1' -or [string]$privateInfo.version-cne'0.3.0' -or ((@($privateInfo.dependencies)-join'|')-cne'base >= 2.1.23|? space-age >= 2.1.23|more-infinite-research = 5.0.21000')){throw 'private-credit F210 projection metadata differs'}
          $privateArchive=New-SourceArchive -Library $library -Source $private.source -Members @('control.lua','info.json','settings-updates.lua')
          $canonicalObserver=Join-Path $repo 'tests/fixtures/active-mods-observer';$observerRaw=Join-Path $root 'observer-raw';$null=New-Item -ItemType Directory -Path $observerRaw
          foreach($member in @('data-final-fixes.lua','info.json')){[IO.File]::WriteAllBytes((Join-Path $observerRaw $member),(Get-StandaloneF210NativeFixtureRawGitMemberBytes -RepoRoot $repo -SourceRevision $sourceRevision -FixtureDirectory 'active-mods-observer' -Member $member))}
          $observerArchive=New-SourceArchive -Library $library -Source $observerRaw -Members @('data-final-fixes.lua','info.json')
          $observerHash=(Get-FileHash -LiteralPath $observerArchive -Algorithm SHA256).Hash
          $observer=New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'observer-output') -SourceRevision $sourceRevision -ExpectedArchiveSha256 $observerHash
          $canonicalLibrary=Join-Path $repo 'tests/fixtures/library-multiplayer'
          $sources=@(Get-StandaloneIdentityFixtureSources -Sources @($canonicalLibrary,$canonicalObserver) -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $normal.source -StagedObserverSource $observer.source -RepoRoot $repo)
          $prepared=Invoke-ActualNormalPreparation -Library $library -Sources $sources -Root (Join-Path $root 'positive')
          if($prepared.prepared.status-cne'passed-private-native-runtime-load-only' -or $sources.Count-ne2 -or $sources[0]-ine$normal.source -or $sources[1]-ine$observer.source){throw 'actual normal preparation did not retain the two exact projections'}
          $spaceAgeSources=@(Get-StandaloneIdentityFixtureSources -Sources @($canonicalLibrary,$canonicalObserver) -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $spaceAge.source -StagedObserverSource $observer.source -RepoRoot $repo)
          $spaceAgePrepared=Invoke-ActualNormalPreparation -Library $library -Sources $spaceAgeSources -Root (Join-Path $root 'space-age-positive')
          if($spaceAgePrepared.prepared.status-cne'passed-private-native-runtime-load-only' -or $spaceAgeSources.Count-ne2 -or $spaceAgeSources[0]-ine$spaceAge.source -or $spaceAgeSources[1]-ine$observer.source){throw 'actual Space Age standalone preparation did not retain the two exact projections'}
          $privateSources=@(Get-StandaloneIdentityFixtureSources -Sources @($canonicalLibrary,$canonicalObserver) -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $private.source -StagedObserverSource $observer.source -RepoRoot $repo)
          $privatePrepared=Invoke-ActualNormalPreparation -Library $library -Sources $privateSources -Root (Join-Path $root 'private-credit-positive')
          if($privatePrepared.prepared.status-cne'passed-private-native-runtime-load-only' -or $privateSources.Count-ne2 -or $privateSources[0]-ine$private.source -or $privateSources[1]-ine$observer.source){throw 'actual private-credit standalone preparation did not retain the two exact projections'}
          $missingLibrary=Join-Path $root 'missing-library';$null=New-Item -ItemType Directory -Path $missingLibrary;New-SourceArchive -Library $missingLibrary -Source $normal.source -Members @('control.lua','info.json')|Out-Null
          Assert-PreparationRejects 'missing runtime member' $missingLibrary $normal.source (Join-Path $root 'missing')
          $changedSource=Join-Path $root 'changed-source';Copy-Item -LiteralPath $normal.source -Destination $changedSource -Recurse;[IO.File]::AppendAllText((Join-Path $changedSource 'control.lua'),'-- changed',[Text.UTF8Encoding]::new($false))
          $changedLibrary=Join-Path $root 'changed-library';$null=New-Item -ItemType Directory -Path $changedLibrary;New-SourceArchive -Library $changedLibrary -Source $normal.source -Members @('control.lua','info.json','settings-updates.lua')|Out-Null
          Assert-PreparationRejects 'changed runtime Lua' $changedLibrary $changedSource (Join-Path $root 'changed')
          $wrongRepo=Join-Path $root 'wrong-target-repo';$wrongFixture=Join-Path $wrongRepo 'tests/fixtures/library-multiplayer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $wrongFixture) -Force;Copy-Item -LiteralPath $canonicalLibrary -Destination $wrongFixture -Recurse
          $wrongInfo=Get-Content -LiteralPath (Join-Path $wrongFixture 'info-f210.json') -Raw|ConvertFrom-Json -AsHashtable;$wrongInfo.factorio_version='2.0';[IO.File]::WriteAllText((Join-Path $wrongFixture 'info-f210.json'),($wrongInfo|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
          $wrongRejected=$false;try{New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $wrongRepo -OutputRoot (Join-Path $root 'wrong-output') -SourceRevision $sourceRevision|Out-Null}catch{$wrongRejected=$true};if(-not$wrongRejected){throw 'F200 fixture metadata was accepted for standalone F210 projection'}
          $wrongSpaceAgeRepo=Join-Path $root 'wrong-space-age-repository';$wrongSpaceAgeFixture=Join-Path $wrongSpaceAgeRepo 'tests/fixtures/library-multiplayer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $wrongSpaceAgeFixture) -Force;Copy-Item -LiteralPath $canonicalLibrary -Destination $wrongSpaceAgeFixture -Recurse
          $wrongSpaceAgeInfo=Get-Content -LiteralPath (Join-Path $wrongSpaceAgeFixture 'info-f210-space-age.json') -Raw|ConvertFrom-Json -AsHashtable;$wrongSpaceAgeInfo.version='0.1.0';[IO.File]::WriteAllText((Join-Path $wrongSpaceAgeFixture 'info-f210-space-age.json'),($wrongSpaceAgeInfo|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
          $wrongSpaceAgeRejected=$false;try{New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $wrongSpaceAgeRepo -OutputRoot (Join-Path $root 'wrong-space-age-output') -SourceRevision $sourceRevision -SpaceAgeLibrary|Out-Null}catch{$wrongSpaceAgeRejected=$true};if(-not$wrongSpaceAgeRejected){throw 'Base metadata was accepted for standalone F210 Space Age projection'}
          $wrongPrivateRepo=Join-Path $root 'wrong-private-credit-repository';$wrongPrivateFixture=Join-Path $wrongPrivateRepo 'tests/fixtures/library-multiplayer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $wrongPrivateFixture) -Force;Copy-Item -LiteralPath $canonicalLibrary -Destination $wrongPrivateFixture -Recurse
          $wrongPrivateInfo=Get-Content -LiteralPath (Join-Path $wrongPrivateFixture 'info-f210-private-credits.json') -Raw|ConvertFrom-Json -AsHashtable;$wrongPrivateInfo.dependencies=@('base >= 2.1.23','more-infinite-research = 5.0.21000');[IO.File]::WriteAllText((Join-Path $wrongPrivateFixture 'info-f210-private-credits.json'),($wrongPrivateInfo|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
          $wrongPrivateRejected=$false;try{New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $wrongPrivateRepo -OutputRoot (Join-Path $root 'wrong-private-credit-output') -SourceRevision $sourceRevision -PrivateCreditChecks|Out-Null}catch{$wrongPrivateRejected=$true};if(-not$wrongPrivateRejected){throw 'private-credit fixture metadata accepted missing optional Space Age dependency'}
          'PASS actual normal standalone F210 preparation and projection opponents'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-standalone-normal-preparation-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_REPO=str(ROOT), MIR_TEST_WORK=work,
                         MIR_TEST_LIBRARY_ACTIVATION=str(ROOT / "tools/lib/compatibility/LibraryActivation.ps1")), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_native_archive_lease_restores_only_owned_bytes_and_preserves_changed_targets(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          . $env:MIR_TEST_ARCHIVE_LEASE
          $root=$env:MIR_TEST_WORK
          $library=Join-Path $root 'library';$sourcesRoot=Join-Path $root 'sources';$output=Join-Path $root 'output'
          foreach($path in @($library,$sourcesRoot,$output)){[IO.Directory]::CreateDirectory($path)|Out-Null}
          $names=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-api-beta_0.1.0.zip','mir-fixture-mir5-library-multiplayer_0.3.0.zip')
          $sources=@();$originals=@{}
          foreach($index in 0..2){
            $name=$names[$index];$source=Join-Path $sourcesRoot $name
            $candidate=[Text.UTF8Encoding]::new($false).GetBytes("candidate-$index")
            [IO.File]::WriteAllBytes($source,$candidate)
            $sources+=,[ordered]@{file_name=$name;source_path=$source;sha256=(Get-MIRImmutableInputSha256 -Path $source)}
            if($index-ne2){
              $target=Join-Path $library $name;$old=[Text.UTF8Encoding]::new($false).GetBytes("original-$index")
              [IO.File]::WriteAllBytes($target,$old)
              $originals[$name]=[ordered]@{sha256=(Get-MIRImmutableInputSha256 -Path $target);identity=(Get-MIRImmutableInputFileIdentity -Path $target)}
            }
          }
          [IO.File]::WriteAllBytes((Join-Path $library 'mod-list.json'),[byte[]](1,2,3,4))
          [IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),[byte[]](5,6,7,8))
          $controls=@{};foreach($name in @('mod-list.json','mod-settings.dat')){$controls[$name]=(Get-MIRImmutableInputSha256 -Path (Join-Path $library $name))}
          $lease=Start-MIRNativeArchiveLease -LibraryDirectory $library -OutputRoot $output -ArchiveSources $sources
          foreach($row in $lease.record.entries){
            $target=Join-Path $library $row.file_name
            if((Get-MIRImmutableInputSha256 -Path $target)-cne$row.candidate_sha256 -or
               (Get-MIRImmutableInputFileIdentity -Path $target)-cne$row.candidate_identity){throw "candidate archive not installed exactly: $($row.file_name)"}
            if($row.original_exists){
              if(-not(Test-Path -LiteralPath $row.backup_path -PathType Leaf) -or
                 (Get-MIRImmutableInputSha256 -Path $row.backup_path)-cne$row.original_sha256 -or
                 (Get-MIRImmutableInputFileIdentity -Path $row.backup_path)-cne$row.original_identity){throw "original archive backup differs: $($row.file_name)"}
            }
          }
          $null=Complete-MIRNativeArchiveLease -Lease $lease
          foreach($name in $names){
            $target=Join-Path $library $name
            if($originals.ContainsKey($name)){
              if((Get-MIRImmutableInputSha256 -Path $target)-cne$originals[$name].sha256 -or
                 (Get-MIRImmutableInputFileIdentity -Path $target)-cne$originals[$name].identity){throw "original bytes/identity not restored: $name"}
            }elseif(Test-Path -LiteralPath $target){throw "new archive was not removed: $name"}
          }
          foreach($name in $controls.Keys){if((Get-MIRImmutableInputSha256 -Path (Join-Path $library $name))-cne$controls[$name]){throw "control changed: $name"}}
          $receipt=Get-Content -LiteralPath (Join-Path $output 'direct-library-archive-lease-receipt.json') -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable
          $journalExists=Test-Path -LiteralPath (Join-Path $library '.mir-library-preview-archive.json')
          if($receipt.state-cne'completed' -or $receipt.terminal_record_sha256-cnotmatch'^[A-F0-9]{64}$' -or $journalExists){throw 'terminal archive lease receipt differs'}

          $sameLibrary=Join-Path $root 'same-library';$sameOutput=Join-Path $root 'same-output'
          [IO.Directory]::CreateDirectory($sameLibrary)|Out-Null;[IO.Directory]::CreateDirectory($sameOutput)|Out-Null
          foreach($index in 0..2){[IO.File]::Copy((Join-Path $sourcesRoot $names[$index]),(Join-Path $sameLibrary $names[$index]),$false)}
          $sameIdentity=@{};foreach($name in $names){$sameIdentity[$name]=Get-MIRImmutableInputFileIdentity -Path (Join-Path $sameLibrary $name)}
          $sameLease=Start-MIRNativeArchiveLease -LibraryDirectory $sameLibrary -OutputRoot $sameOutput -ArchiveSources $sources
          if(@($sameLease.record.entries|Where-Object {-not $_.unchanged -or $_.candidate_temp -cne '' -or $_.backup_path -cne ''}).Count){throw 'identical archive lease staged unnecessary bytes'}
          $null=Complete-MIRNativeArchiveLease -Lease $sameLease
          foreach($name in $names){if((Get-MIRImmutableInputFileIdentity -Path (Join-Path $sameLibrary $name))-cne$sameIdentity[$name]){throw "unchanged archive identity changed: $name"}}

          $recoveryLibrary=Join-Path $root 'recovery-library';$recoveryOutput=Join-Path $root 'recovery-output';$recoveryOutput2=Join-Path $root 'recovery-output-next'
          [IO.Directory]::CreateDirectory($recoveryLibrary)|Out-Null;[IO.Directory]::CreateDirectory($recoveryOutput)|Out-Null;[IO.Directory]::CreateDirectory($recoveryOutput2)|Out-Null
          foreach($index in 0..1){[IO.File]::WriteAllBytes((Join-Path $recoveryLibrary $names[$index]),[Text.UTF8Encoding]::new($false).GetBytes("original-$index"))}
          $recoveryExpected=@{}
          foreach($index in 0..1){$path=Join-Path $recoveryLibrary $names[$index];$recoveryExpected[$names[$index]]=[ordered]@{sha256=(Get-MIRImmutableInputSha256 -Path $path);identity=(Get-MIRImmutableInputFileIdentity -Path $path)}}
          $abandoned=Start-MIRNativeArchiveLease -LibraryDirectory $recoveryLibrary -OutputRoot $recoveryOutput -ArchiveSources $sources
          foreach($handle in $abandoned.source_handles){$handle.Dispose()};$abandoned.lock.Dispose()
          $abandoned.record.owner_pid=2147483647
          $abandoned.record.owner_started_utc='2000-01-01T00:00:00.0000000Z'
          Write-MIRNativeArchiveLeaseRecord -Record $abandoned.record -Path $abandoned.journal_path
          $recovered=Start-MIRNativeArchiveLease -LibraryDirectory $recoveryLibrary -OutputRoot $recoveryOutput2 -ArchiveSources $sources
          foreach($name in $names){
            $row=@($recovered.record.entries|Where-Object file_name -CEQ $name)[0]
            if($recoveryExpected.ContainsKey($name)){
              if(-not$row.original_exists-or$row.original_sha256-cne$recoveryExpected[$name].sha256-or$row.original_identity-cne$recoveryExpected[$name].identity){throw "stale lease did not restore original before retry: $name"}
            }elseif($row.original_exists){throw "stale lease left its added archive behind: $name"}
          }
          $null=Complete-MIRNativeArchiveLease -Lease $recovered

          $badLibrary=Join-Path $root 'bad-library';$badOutput=Join-Path $root 'bad-output'
          [IO.Directory]::CreateDirectory($badLibrary)|Out-Null;[IO.Directory]::CreateDirectory($badOutput)|Out-Null
          foreach($index in 0..1){[IO.File]::WriteAllBytes((Join-Path $badLibrary $names[$index]),[Text.UTF8Encoding]::new($false).GetBytes("original-$index"))}
          $badOriginal=Join-Path $badLibrary $names[0];$badOriginalIdentity=Get-MIRImmutableInputFileIdentity -Path $badOriginal;$badOriginalHash=Get-MIRImmutableInputSha256 -Path $badOriginal
          $badLease=Start-MIRNativeArchiveLease -LibraryDirectory $badLibrary -OutputRoot $badOutput -ArchiveSources $sources
          [IO.File]::WriteAllBytes((Join-Path $badLibrary $names[1]),[Text.UTF8Encoding]::new($false).GetBytes('outside-change'))
          $rejected=$false;try{Complete-MIRNativeArchiveLease -Lease $badLease|Out-Null}catch{$rejected=$true}
          if(-not$rejected){throw 'lease overwrote a changed archive'}
          $badBackup=[string](@($badLease.record.entries|Where-Object file_name -CEQ $names[0])[0].backup_path)
          if(-not(Test-Path -LiteralPath $badBackup -PathType Leaf) -or
             (Get-MIRImmutableInputSha256 -Path $badBackup)-cne$badOriginalHash -or
             (Get-MIRImmutableInputFileIdentity -Path $badBackup)-cne$badOriginalIdentity -or
             (Get-MIRImmutableInputSha256 -Path (Join-Path $badLibrary $names[1]))-ceq$badLease.record.entries[1].candidate_sha256){throw 'changed target or recovery copy was overwritten'}

          $faultLibrary=Join-Path $root 'fault-library';$faultOutput=Join-Path $root 'fault-output'
          [IO.Directory]::CreateDirectory($faultLibrary)|Out-Null;[IO.Directory]::CreateDirectory($faultOutput)|Out-Null
          [IO.File]::WriteAllBytes((Join-Path $faultLibrary $names[0]),[Text.UTF8Encoding]::new($false).GetBytes('fault-original'))
          $faultOriginal=Join-Path $faultLibrary $names[0]
          $faultOriginalHash=Get-MIRImmutableInputSha256 -Path $faultOriginal
          $faultOriginalIdentity=Get-MIRImmutableInputFileIdentity -Path $faultOriginal
          $script:originalLeaseWriter=(Get-Command Write-MIRNativeArchiveLeaseRecord -CommandType Function).ScriptBlock
          function Write-MIRNativeArchiveLeaseRecord {
            param([Collections.IDictionary]$Record,[string]$Path)
            if(@($Record.entries|Where-Object state -CEQ 'installed').Count){throw 'injected setup failure after candidate install'}
            & $script:originalLeaseWriter -Record $Record -Path $Path
          }
          function Restore-MIRNativeArchiveLeaseRecord {
            param([Collections.IDictionary]$Record,[string]$JournalPath,[string]$LibraryDirectory,[switch]$KeepLock)
            throw 'injected restoration failure'
          }
          $failureMessage='';try{Start-MIRNativeArchiveLease -LibraryDirectory $faultLibrary -OutputRoot $faultOutput -ArchiveSources $sources|Out-Null}catch{$failureMessage=$_.Exception.Message}
          if(-not$failureMessage.Contains('[mir-native-archive-lease-restoration-failed]') -or
             -not$failureMessage.Contains('injected setup failure after candidate install') -or
             -not$failureMessage.Contains('injected restoration failure')) {throw "combined setup/restoration failure was not reported: $failureMessage"}
          $faultJournal=Join-Path $faultLibrary '.mir-library-preview-archive.json'
          if(-not(Test-Path -LiteralPath $faultJournal -PathType Leaf)){throw 'recovery journal was discarded after failed restoration'}
          $faultRecord=Get-MIRNativeArchiveLeaseRecord -Path $faultJournal
          $faultBackup=[string](@($faultRecord.entries|Where-Object file_name -CEQ $names[0])[0].backup_path)
          if(-not(Test-Path -LiteralPath $faultBackup -PathType Leaf) -or
             (Get-MIRImmutableInputSha256 -Path $faultBackup)-cne$faultOriginalHash -or
             (Get-MIRImmutableInputFileIdentity -Path $faultBackup)-cne$faultOriginalIdentity -or
             (Get-MIRImmutableInputSha256 -Path $faultOriginal)-cne[string](@($faultRecord.entries|Where-Object file_name -CEQ $names[0])[0].candidate_sha256)) {throw 'original backup or installed candidate was not preserved after failed restoration'}
          'PASS direct-library archive lease restoration and changed-target refusal'
        '''
        temporary_parent = ROOT / "build" / "tmp"
        temporary_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mir5-native-archive-lease-", dir=temporary_parent) as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_ARCHIVE_LEASE=str(ROOT / "tools/lib/compatibility/NativeArchiveLease.ps1"),
                         MIR_TEST_WORK=work), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_f210_api_consumers_project_exact_runtime_members_through_the_real_archive_guard(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          function Get-MIRImmutableInputSha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
          . $env:MIR_TEST_LIBRARY_ACTIVATION
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw $errors[0].Message}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          foreach($name in @('Get-StandaloneF210ApiConsumerRawGitMemberBytes','New-StandaloneF210ApiConsumerSourceProjection','Get-StandaloneIdentityFixtureSources')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true))
            if($node.Count-ne1){throw "standalone API projection function is absent or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          function New-SourceArchive([string]$Library,[string]$RepoRoot,[string]$Revision,[string]$FixtureName,[string[]]$Members,[switch]$ReformattedInfo,[switch]$MutatedInfo,[switch]$DuplicatedInfo){
            $info=[Text.Encoding]::UTF8.GetString((Get-StandaloneF210ApiConsumerRawGitMemberBytes -RepoRoot $RepoRoot -SourceRevision $Revision -FixtureName $FixtureName -Member 'info.json'))|ConvertFrom-Json -AsHashtable
            $archive=Join-Path $Library ($info.name+'_'+$info.version+'.zip')
            $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{
              $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
              try{foreach($name in $Members){$entry=$zip.CreateEntry($info.name+'_'+$info.version+'/'+$name,[IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();try{$raw=Get-StandaloneF210ApiConsumerRawGitMemberBytes -RepoRoot $RepoRoot -SourceRevision $Revision -FixtureName $FixtureName -Member $name;if($name-ceq'info.json'-and($ReformattedInfo-or$MutatedInfo)){$memberInfo=[Text.Encoding]::UTF8.GetString($raw)|ConvertFrom-Json -AsHashtable;if($MutatedInfo){$memberInfo.factorio_version='2.0'};$raw=[Text.Encoding]::UTF8.GetBytes(($memberInfo|ConvertTo-Json -Depth 16)+[Environment]::NewLine)};if($name-ceq'info.json'-and$DuplicatedInfo){$text=[Text.Encoding]::UTF8.GetString($raw);$text=$text.Replace('"factorio_version": "2.1",','"factorio_version": "2.1",'+[Environment]::NewLine+'  "factorio_version": "2.1",');$raw=[Text.Encoding]::UTF8.GetBytes($text)};$entryStream.Write($raw,0,$raw.Length)}finally{$entryStream.Dispose()}}}finally{$zip.Dispose()}
            }finally{$stream.Dispose()}
            return $archive
          }
          $root=$env:MIR_TEST_WORK;$repo=$env:MIR_TEST_REPO;$revision=@(& git -C $repo rev-parse --verify 'HEAD^{commit}');if($LASTEXITCODE-ne0-or$revision.Count-ne1){throw 'test source revision is unavailable'};$library=Join-Path $root 'library';$null=New-Item -ItemType Directory -Path $library
          $alphaSource=Join-Path $repo 'tests/fixtures/api-alpha';$betaSource=Join-Path $repo 'tests/fixtures/api-beta'
          $alphaArchive=New-SourceArchive -Library $library -RepoRoot $repo -Revision $revision[0] -FixtureName 'mir-fixture-mir5-api-alpha' -Members @('control.lua','data.lua','graphics/icon.png','info.json')
          $betaArchive=New-SourceArchive -Library $library -RepoRoot $repo -Revision $revision[0] -FixtureName 'mir-fixture-mir5-api-beta' -Members @('control.lua','data-final-fixes.lua','graphics/icon.png','info.json') -ReformattedInfo
          $alpha=New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'alpha') -FixtureName 'mir-fixture-mir5-api-alpha' -ExpectedArchiveSha256 (Get-MIRImmutableInputSha256 $alphaArchive) -SourceRevision $revision[0]
          $beta=New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'beta') -FixtureName 'mir-fixture-mir5-api-beta' -ExpectedArchiveSha256 (Get-MIRImmutableInputSha256 $betaArchive) -SourceRevision $revision[0]
          if(
            $alpha.members.Count -ne 4 -or
            $beta.members.Count -ne 4 -or
            (@($alpha.members.path) -contains 'info-f200.json') -or
            (@($beta.members.path) -contains 'info-f200.json')
          ){throw 'standalone API runtime projection member set differs'}
          Assert-MIRLibraryFixtureArchive -Archive $alpha.archive -SourceDirectory $alpha.source
          Assert-MIRLibraryFixtureArchive -Archive $beta.archive -SourceDirectory $beta.source
          $sourceInfoBytes=(Get-Item -LiteralPath (Join-Path $beta.source 'info.json')).Length;$archiveInfo=[IO.Compression.ZipFile]::OpenRead($beta.archive);try{$entry=$archiveInfo.GetEntry('mir-fixture-mir5-api-beta_0.1.0/info.json');if($null-eq$entry-or$entry.Length-eq$sourceInfoBytes){throw 'test archive did not reformat fixture metadata'}}finally{$archiveInfo.Dispose()}
          $mutatedLibrary=Join-Path $root 'mutated-metadata-library';$null=New-Item -ItemType Directory -Path $mutatedLibrary;$mutatedArchive=New-SourceArchive -Library $mutatedLibrary -RepoRoot $repo -Revision $revision[0] -FixtureName 'mir-fixture-mir5-api-beta' -Members @('control.lua','data-final-fixes.lua','graphics/icon.png','info.json') -MutatedInfo
          $metadataRejected=$false;try{Assert-MIRLibraryFixtureArchive -Archive $mutatedArchive -SourceDirectory $beta.source}catch{$metadataRejected=$_.Exception.Message.Contains('[mir-library-fixture-metadata] info.json');if(-not$metadataRejected){throw}}
          if(-not$metadataRejected){throw 'archive metadata drift was accepted'}
          $duplicateLibrary=Join-Path $root 'duplicate-metadata-library';$null=New-Item -ItemType Directory -Path $duplicateLibrary;$duplicateArchive=New-SourceArchive -Library $duplicateLibrary -RepoRoot $repo -Revision $revision[0] -FixtureName 'mir-fixture-mir5-api-beta' -Members @('control.lua','data-final-fixes.lua','graphics/icon.png','info.json') -DuplicatedInfo
          $duplicateRejected=$false;try{Assert-MIRLibraryFixtureArchive -Archive $duplicateArchive -SourceDirectory $beta.source}catch{$duplicateRejected=$_.Exception.Message.Contains('[mir-library-fixture-metadata] info.json');if(-not$duplicateRejected){throw}}
          if(-not$duplicateRejected){throw 'duplicate archive metadata keys were accepted'}
          $canonicalLibrary=Join-Path $repo 'tests/fixtures/library-multiplayer';$canonicalObserver=Join-Path $repo 'tests/fixtures/active-mods-observer'
          $sources=@(Get-StandaloneIdentityFixtureSources -Sources @($canonicalLibrary,$canonicalObserver,$alphaSource,$betaSource) -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $canonicalLibrary -StagedObserverSource $canonicalObserver -RepoRoot $repo -StagedApiConsumerSources @{'mir-fixture-mir5-api-alpha'=$alpha.source;'mir-fixture-mir5-api-beta'=$beta.source})
          if($sources.Count-ne4-or$sources[2]-ine$alpha.source-or$sources[3]-ine$beta.source){throw 'standalone API consumer sources were not projected through the actual source binder'}
          function Assert-Rejects([string]$Name,[scriptblock]$Block){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "standalone API projection accepted opponent: $Name"}}
          Assert-Rejects 'unprojected API object' {Get-StandaloneIdentityFixtureSources -Sources @($canonicalLibrary,$canonicalObserver,$alphaSource,$betaSource) -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $canonicalLibrary -StagedObserverSource $canonicalObserver -RepoRoot $repo -StagedApiConsumerSources @{'mir-fixture-mir5-api-alpha'=$alpha;'mir-fixture-mir5-api-beta'=$beta}|Out-Null}
          $extraRepo=Join-Path $root 'extra-repository';$extraSource=Join-Path $extraRepo 'tests/fixtures/api-alpha';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $extraSource) -Force;Copy-Item -LiteralPath $alphaSource -Destination $extraSource -Recurse;[IO.File]::WriteAllText((Join-Path $extraSource 'extra.lua'),'return {}',[Text.UTF8Encoding]::new($false))
          Assert-Rejects 'extra runtime member' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $extraRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'extra-output') -FixtureName 'mir-fixture-mir5-api-alpha' -ExpectedArchiveSha256 (Get-MIRImmutableInputSha256 $alphaArchive) -SourceRevision $revision[0]|Out-Null}
          $driftRepo=Join-Path $root 'drift-repository';$driftSource=Join-Path $driftRepo 'tests/fixtures/api-beta';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $driftSource) -Force;Copy-Item -LiteralPath $betaSource -Destination $driftSource -Recurse;$driftInfo=Get-Content -LiteralPath (Join-Path $driftSource 'info.json') -Raw|ConvertFrom-Json -AsHashtable;$driftInfo.factorio_version='2.0';[IO.File]::WriteAllText((Join-Path $driftSource 'info.json'),($driftInfo|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
          Assert-Rejects 'F210 metadata drift' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $driftRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'drift-output') -FixtureName 'mir-fixture-mir5-api-beta' -ExpectedArchiveSha256 (Get-MIRImmutableInputSha256 $betaArchive) -SourceRevision $revision[0]|Out-Null}
          Assert-Rejects 'stale beta archive' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'stale-output') -FixtureName 'mir-fixture-mir5-api-beta' -ExpectedArchiveSha256 ('A'*64) -SourceRevision $revision[0]|Out-Null}
          'PASS standalone API runtime projections and archive guards'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-standalone-api-projection-") as work:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], capture_output=True, text=True,
                env=dict(os.environ, MIR_TEST_WRAPPER=str(WRAPPER), MIR_TEST_REPO=str(ROOT), MIR_TEST_WORK=work,
                         MIR_TEST_LIBRARY_ACTIVATION=str(ROOT / "tools/lib/compatibility/LibraryActivation.ps1")), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_standalone_f210_api_consumers_project_selected_raw_git_bytes_despite_crlf_worktree(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          function Get-MIRImmutableInputSha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Assert-Rejects([string]$Name,[scriptblock]$Block){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "raw Git projection accepted opponent: $Name"}}
          function Get-GitBytes([string]$Repo,[string]$Revision,[string]$Path){
            $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
            foreach($argument in @('-C',$Repo,'show',($Revision+':'+$Path))){$null=$start.ArgumentList.Add($argument)}
            $process=[Diagnostics.Process]::new();$process.StartInfo=$start;if(-not$process.Start()){throw "raw Git test read did not start: $Path"}
            $output=[IO.MemoryStream]::new();try{$process.StandardOutput.BaseStream.CopyTo($output);$null=$process.StandardError.ReadToEnd();$process.WaitForExit();if($process.ExitCode-ne0){throw "raw Git test member is absent: $Path"}}finally{$process.Dispose()}
            return ,$output.ToArray()
          }
          $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors);if($errors.Count){throw $errors[0].Message}
          . $env:MIR_TEST_LIBRARY_ACTIVATION
          foreach($name in @('Resolve-StandaloneF210ApiConsumerSourceRevision','Get-StandaloneF210NativeFixtureGitMembers','Get-StandaloneF210NativeFixtureRawGitMemberBytes','Get-StandaloneF210ApiConsumerRawGitMemberBytes','New-StandaloneF210LibraryFixtureSourceProjection','New-StandaloneIdentityObserverSourceProjection','New-StandaloneF210ApiConsumerSourceProjection')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true));if($node.Count-ne1){throw "raw Git projection function is absent or ambiguous: $name"};Invoke-Expression $node[0].Extent.Text
          }
          $root=$env:MIR_TEST_WORK;$repo=$env:MIR_TEST_REPO;$sourceRevision=@(& git -C $repo rev-parse --verify 'HEAD^{commit}');if($LASTEXITCODE-ne0-or$sourceRevision.Count-ne1){throw 'source test revision is unavailable'}
          $fixtures=@{
            'api-alpha'=@('control.lua','data.lua','graphics/icon.png','info.json','info-f200.json')
            'api-beta'=@('control.lua','data-final-fixes.lua','graphics/icon.png','info.json','info-f200.json')
            'library-multiplayer'=@('README.md','control.lua','info-f210-private-credits.json','info-f210-space-age.json','info-f210.json','info.json','settings-updates.lua')
            'active-mods-observer'=@('data-final-fixes.lua','info-f200.json','info.json')
          }
          function New-FixtureGitRepository([string]$Destination,[scriptblock]$Mutation){
            foreach($fixture in $fixtures.Keys){foreach($member in $fixtures[$fixture]){$destinationPath=Join-Path $Destination ('tests/fixtures/'+$fixture+'/'+$member);$null=New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force;[IO.File]::WriteAllBytes($destinationPath,(Get-GitBytes $repo $sourceRevision[0] ('tests/fixtures/'+$fixture+'/'+$member)))}}
            if($null-ne$Mutation){&$Mutation $Destination}
            & git -C $Destination init --quiet;if($LASTEXITCODE-ne0){throw 'temporary fixture repository initialization failed'}
            & git -C $Destination add tests;if($LASTEXITCODE-ne0){throw 'temporary fixture repository add failed'}
            & git -C $Destination -c user.name=MIRFixtureTest -c user.email=mir-fixture-test@example.invalid commit --quiet -m fixture;if($LASTEXITCODE-ne0){throw 'temporary fixture repository commit failed'}
            $revision=@(& git -C $Destination rev-parse --verify 'HEAD^{commit}');if($LASTEXITCODE-ne0-or$revision.Count-ne1){throw 'temporary fixture revision is unavailable'}
            return [string]$revision[0]
          }
          function New-GitSourceArchive([string]$RepoRoot,[string]$Revision,[string]$Library,[string]$FixtureName){
            $shortName=if($FixtureName-ceq'mir-fixture-mir5-api-alpha'){'api-alpha'}else{'api-beta'}
            $members=if($shortName-ceq'api-alpha'){@('control.lua','data.lua','graphics/icon.png','info.json')}else{@('control.lua','data-final-fixes.lua','graphics/icon.png','info.json')}
            $info=[Text.Encoding]::UTF8.GetString((Get-GitBytes $RepoRoot $Revision ('tests/fixtures/'+$shortName+'/info.json')))|ConvertFrom-Json -AsHashtable
            $archive=Join-Path $Library ($info.name+'_'+$info.version+'.zip');$stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false);try{foreach($member in $members){$entry=$zip.CreateEntry($info.name+'_'+$info.version+'/'+$member,[IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();try{$raw=Get-GitBytes $RepoRoot $Revision ('tests/fixtures/'+$shortName+'/'+$member);$entryStream.Write($raw,0,$raw.Length)}finally{$entryStream.Dispose()}}}finally{$zip.Dispose()}}finally{$stream.Dispose()}
            return $archive
          }
          function Convert-TextMembersToCrlf([string]$RepoRoot){
            foreach($fixture in $fixtures.Keys){foreach($member in $fixtures[$fixture]){if($member-notmatch'\.(lua|json)$'){continue};$path=Join-Path $RepoRoot ('tests/fixtures/'+$fixture+'/'+$member);$text=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path));if($text.Contains("`r")){throw "fixture source was not raw LF: $fixture/$member"};[IO.File]::WriteAllText($path,$text.Replace("`n","`r`n"),[Text.UTF8Encoding]::new($false))}}
          }
          function New-SourceArchive([string]$Library,[string]$Source,[string[]]$Members){
            $info=Get-Content -LiteralPath (Join-Path $Source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
            $archive=Join-Path $Library ($info.name+'_'+$info.version+'.zip');$stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false);try{foreach($member in $Members){$entry=$zip.CreateEntry($info.name+'_'+$info.version+'/'+$member,[IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();$input=[IO.File]::OpenRead((Join-Path $Source $member));try{$input.CopyTo($entryStream)}finally{$input.Dispose();$entryStream.Dispose()}}}finally{$zip.Dispose()}}finally{$stream.Dispose()}
            return $archive
          }
          $baselineRepo=Join-Path $root 'baseline-repository';$baselineRevision=New-FixtureGitRepository $baselineRepo $null
          $resolvedRevision=Resolve-StandaloneF210ApiConsumerSourceRevision -RepoRoot $baselineRepo;if($resolvedRevision-cne$baselineRevision){throw 'API consumers did not resolve one committed source revision'}
          $library=Join-Path $root 'library';$null=New-Item -ItemType Directory -Path $library
          $alphaArchive=New-GitSourceArchive $baselineRepo $baselineRevision $library 'mir-fixture-mir5-api-alpha';$betaArchive=New-GitSourceArchive $baselineRepo $baselineRevision $library 'mir-fixture-mir5-api-beta'
          Convert-TextMembersToCrlf $baselineRepo
          $legacy=Join-Path $root 'legacy-working-tree-alpha';$null=New-Item -ItemType Directory -Path $legacy
          foreach($member in @('control.lua','data.lua','graphics/icon.png','info.json')){$destination=Join-Path $legacy $member;$null=New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force;[IO.File]::Copy((Join-Path $baselineRepo ('tests/fixtures/api-alpha/'+$member)),$destination,$false)}
          Assert-Rejects 'legacy CRLF working-tree projection' {Assert-MIRLibraryFixtureArchive -Archive $alphaArchive -SourceDirectory $legacy}
          $alpha=New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $baselineRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'alpha') -FixtureName 'mir-fixture-mir5-api-alpha' -ExpectedArchiveSha256 (Get-FileHash -LiteralPath $alphaArchive -Algorithm SHA256).Hash -SourceRevision $resolvedRevision
          $beta=New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $baselineRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'beta') -FixtureName 'mir-fixture-mir5-api-beta' -ExpectedArchiveSha256 (Get-FileHash -LiteralPath $betaArchive -Algorithm SHA256).Hash -SourceRevision $resolvedRevision
          foreach($fixture in @($alpha,$beta)){if($fixture.source_revision-cne$resolvedRevision-or$fixture.members.Count-ne4){throw 'raw Git projection did not retain its selected source revision and four runtime members'};Assert-MIRLibraryFixtureArchive -Archive $fixture.archive -SourceDirectory $fixture.source}
          foreach($fixtureSpec in @(@{name='mir-fixture-mir5-api-alpha';short='api-alpha';projection=$alpha},@{name='mir-fixture-mir5-api-beta';short='api-beta';projection=$beta})){foreach($member in $fixtureSpec.projection.members){$expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Get-GitBytes $baselineRepo $resolvedRevision ('tests/fixtures/'+$fixtureSpec.short+'/'+$member.path))));$actual=(Get-FileHash -LiteralPath (Join-Path $fixtureSpec.projection.source $member.path) -Algorithm SHA256).Hash.ToUpperInvariant();if($actual-cne$expected){throw "raw Git member bytes differ: $($fixtureSpec.short)/$($member.path)"}}}
          $libraryProjection=New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $baselineRepo -OutputRoot (Join-Path $root 'library-fixture') -SourceRevision $resolvedRevision
          $libraryArchive=New-SourceArchive -Library $library -Source $libraryProjection.source -Members @('control.lua','info.json','settings-updates.lua')
          Assert-MIRLibraryFixtureArchive -Archive $libraryArchive -SourceDirectory $libraryProjection.source
          if($libraryProjection.source_revision-cne$resolvedRevision-or$libraryProjection.members.Count-ne3){throw 'Library projection did not retain the selected raw Git revision and exact runtime members'}
          $legacyLibrary=Join-Path $root 'legacy-library-crlf';$null=New-Item -ItemType Directory -Path $legacyLibrary
          foreach($member in @(@{source='control.lua';destination='control.lua'},@{source='settings-updates.lua';destination='settings-updates.lua'},@{source='info-f210.json';destination='info.json'})){[IO.File]::Copy((Join-Path $baselineRepo ('tests/fixtures/library-multiplayer/'+$member.source)),(Join-Path $legacyLibrary $member.destination),$false)}
          Assert-Rejects 'legacy CRLF Library worktree projection' {Assert-MIRLibraryFixtureArchive -Archive $libraryArchive -SourceDirectory $legacyLibrary}
          foreach($member in $libraryProjection.members){$sourceName=[string]$member.source;$expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Get-GitBytes $baselineRepo $resolvedRevision ('tests/fixtures/library-multiplayer/'+$sourceName))));$actual=(Get-FileHash -LiteralPath (Join-Path $libraryProjection.source $member.path) -Algorithm SHA256).Hash.ToUpperInvariant();if($actual-cne$expected){throw "raw Git member bytes differ: library-multiplayer/$($member.path)"}}
          $observerSource=Join-Path $root 'observer-raw';$null=New-Item -ItemType Directory -Path $observerSource
          foreach($member in @('data-final-fixes.lua','info.json')){[IO.File]::WriteAllBytes((Join-Path $observerSource $member),(Get-StandaloneF210NativeFixtureRawGitMemberBytes -RepoRoot $baselineRepo -SourceRevision $resolvedRevision -FixtureDirectory 'active-mods-observer' -Member $member))}
          $observerArchive=New-SourceArchive -Library $library -Source $observerSource -Members @('data-final-fixes.lua','info.json')
          $observer=New-StandaloneIdentityObserverSourceProjection -RepoRoot $baselineRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'observer-fixture') -SourceRevision $resolvedRevision -ExpectedArchiveSha256 (Get-FileHash -LiteralPath $observerArchive -Algorithm SHA256).Hash
          Assert-MIRLibraryFixtureArchive -Archive $observer.archive -SourceDirectory $observer.source
          if($observer.source_revision-cne$resolvedRevision-or$observer.members.Count-ne2){throw 'observer projection did not retain the selected raw Git revision and exact runtime members'}
          $legacyObserver=Join-Path $root 'legacy-observer-crlf';$null=New-Item -ItemType Directory -Path $legacyObserver
          foreach($member in @('data-final-fixes.lua','info.json')){[IO.File]::Copy((Join-Path $baselineRepo ('tests/fixtures/active-mods-observer/'+$member)),(Join-Path $legacyObserver $member),$false)}
          Assert-Rejects 'legacy CRLF observer worktree projection' {Assert-MIRLibraryFixtureArchive -Archive $observerArchive -SourceDirectory $legacyObserver}
          foreach($member in $observer.members){$expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Get-GitBytes $baselineRepo $resolvedRevision ('tests/fixtures/active-mods-observer/'+$member.path))));$actual=(Get-FileHash -LiteralPath (Join-Path $observer.source $member.path) -Algorithm SHA256).Hash.ToUpperInvariant();if($actual-cne$expected){throw "raw Git member bytes differ: active-mods-observer/$($member.path)"}}
          $validAlphaHash=(Get-FileHash -LiteralPath $alphaArchive -Algorithm SHA256).Hash;$validBetaHash=(Get-FileHash -LiteralPath $betaArchive -Algorithm SHA256).Hash
          $tamperedRepo=Join-Path $root 'tampered-repository';$tamperedRevision=New-FixtureGitRepository $tamperedRepo {param($path)[IO.File]::AppendAllText((Join-Path $path 'tests/fixtures/api-alpha/control.lua'),'-- changed',[Text.UTF8Encoding]::new($false))}
          Assert-Rejects 'tampered committed selected member' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $tamperedRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'tampered-output') -FixtureName 'mir-fixture-mir5-api-alpha' -ExpectedArchiveSha256 $validAlphaHash -SourceRevision $tamperedRevision|Out-Null}
          $missingRepo=Join-Path $root 'missing-repository';$missingRevision=New-FixtureGitRepository $missingRepo {param($path)Remove-Item -LiteralPath (Join-Path $path 'tests/fixtures/api-alpha/data.lua')}
          Assert-Rejects 'missing committed runtime member' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $missingRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'missing-output') -FixtureName 'mir-fixture-mir5-api-alpha' -ExpectedArchiveSha256 $validAlphaHash -SourceRevision $missingRevision|Out-Null}
          $extraRepo=Join-Path $root 'extra-repository';$extraRevision=New-FixtureGitRepository $extraRepo {param($path)[IO.File]::WriteAllText((Join-Path $path 'tests/fixtures/api-beta/extra.lua'),'return {}',[Text.UTF8Encoding]::new($false))}
          Assert-Rejects 'extra committed runtime member' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $extraRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'extra-output') -FixtureName 'mir-fixture-mir5-api-beta' -ExpectedArchiveSha256 $validBetaHash -SourceRevision $extraRevision|Out-Null}
          $metadataRepo=Join-Path $root 'metadata-repository';$metadataRevision=New-FixtureGitRepository $metadataRepo {param($path)$metadata=Join-Path $path 'tests/fixtures/api-beta/info.json';$text=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($metadata));[IO.File]::WriteAllText($metadata,$text.Replace('"factorio_version": "2.1"','"factorio_version": "2.0"'),[Text.UTF8Encoding]::new($false))}
          Assert-Rejects 'committed F210 metadata drift' {New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $metadataRepo -ArchiveLibrary $library -OutputRoot (Join-Path $root 'metadata-output') -FixtureName 'mir-fixture-mir5-api-beta' -ExpectedArchiveSha256 $validBetaHash -SourceRevision $metadataRevision|Out-Null}
          'PASS raw Git API, Library and observer projections with CRLF/tamper/membership/metadata controls'
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-standalone-api-raw-git-") as work:
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
          $alpha=Join-Path $repo 'tests/fixtures/api-alpha'
          $beta=Join-Path $repo 'tests/fixtures/api-beta'
          $accepted=@(Get-StandaloneIdentityFixtureSources -Sources @($library) -LibraryFixtureSource $library -StagedLibraryFixtureSource $library -StagedObserverSource $observer -RepoRoot $repo -StagedApiConsumerSources @{})
          if($accepted.Count-ne2 -or $accepted[0]-ine$library -or $accepted[1]-ine$observer){throw 'canonical observer was not appended exactly once'}
          $apiAccepted=@(Get-StandaloneIdentityFixtureSources -Sources @($library,$observer,$alpha,$beta) -LibraryFixtureSource $library -StagedLibraryFixtureSource $library -StagedObserverSource $observer -RepoRoot $repo -StagedApiConsumerSources @{'mir-fixture-mir5-api-alpha'=$alpha;'mir-fixture-mir5-api-beta'=$beta})
          if($apiAccepted.Count-ne4-or$apiAccepted[0]-ine$library-or$apiAccepted[1]-ine$observer-or$apiAccepted[2]-ine$alpha-or$apiAccepted[3]-ine$beta){throw 'standalone API consumer sources were not retained through the normal projection'}
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
          foreach($name in @('Resolve-StandaloneF210ApiConsumerSourceRevision','Get-StandaloneF210NativeFixtureGitMembers','Get-StandaloneF210NativeFixtureRawGitMemberBytes','New-StandaloneIdentityObserverSourceProjection')){
            $node=@($ast.FindAll({param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -ceq $name},$true))
            if($node.Count-ne1){throw "observer projection function is absent or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $repo=$env:MIR_TEST_REPO;$sourceRevision=Resolve-StandaloneF210ApiConsumerSourceRevision -RepoRoot $repo
          $library=Join-Path $env:MIR_TEST_WORK 'library';$null=New-Item -ItemType Directory -Path $library
          $canonical=Join-Path $repo 'tests/fixtures/active-mods-observer'
          $archive=Join-Path $library 'mir-fixture-mir5-active-mods-observer_0.1.0.zip'
          $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
          try {
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
            try {
              foreach($name in @('data-final-fixes.lua','info.json')){
                $entry=$zip.CreateEntry('mir-fixture-mir5-active-mods-observer_0.1.0/'+$name,[IO.Compression.CompressionLevel]::Optimal)
                $entryStream=$entry.Open();$bytes=Get-StandaloneF210NativeFixtureRawGitMemberBytes -RepoRoot $repo -SourceRevision $sourceRevision -FixtureDirectory 'active-mods-observer' -Member $name
                try{$entryStream.Write($bytes,0,$bytes.Length)}finally{$entryStream.Dispose()}
              }
            } finally {$zip.Dispose()}
          } finally {$stream.Dispose()}
          $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()
          $positiveRoot=Join-Path $env:MIR_TEST_WORK 'positive';$null=New-Item -ItemType Directory -Path $positiveRoot
          $projection=New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot $positiveRoot -SourceRevision $sourceRevision -ExpectedArchiveSha256 $hash
          if($projection.sha256-cne$hash -or $projection.alternate_metadata-cne'info-f200.json' -or $projection.members.Count-ne2){throw 'projection lost hash-bound canonical observer facts'}
          function Assert-Rejects([string]$Name,[scriptblock]$Block){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "observer projection accepted opponent: $Name"}}
          $changedRepo=Join-Path $env:MIR_TEST_WORK 'changed-repo';$changedSource=Join-Path $changedRepo 'tests/fixtures/active-mods-observer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $changedSource) -Force;Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/active-mods-observer') -Destination $changedSource -Recurse
          [IO.File]::AppendAllText((Join-Path $changedSource 'data-final-fixes.lua'),'-- altered',[Text.UTF8Encoding]::new($false))
          Assert-Rejects 'source repository without committed members' {New-StandaloneIdentityObserverSourceProjection -RepoRoot $changedRepo -ArchiveLibrary $library -OutputRoot (Join-Path $env:MIR_TEST_WORK 'changed-output') -SourceRevision $sourceRevision -ExpectedArchiveSha256 $hash|Out-Null}
          $missingRepo=Join-Path $env:MIR_TEST_WORK 'missing-repo';$missingSource=Join-Path $missingRepo 'tests/fixtures/active-mods-observer';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $missingSource) -Force;Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/active-mods-observer') -Destination $missingSource -Recurse;Remove-Item -LiteralPath (Join-Path $missingSource 'data-final-fixes.lua') -Force
          Assert-Rejects 'source repository without committed members' {New-StandaloneIdentityObserverSourceProjection -RepoRoot $missingRepo -ArchiveLibrary $library -OutputRoot (Join-Path $env:MIR_TEST_WORK 'missing-output') -SourceRevision $sourceRevision -ExpectedArchiveSha256 $hash|Out-Null}
          $extraLibrary=Join-Path $env:MIR_TEST_WORK 'extra-library';$null=New-Item -ItemType Directory -Path $extraLibrary;$extraArchive=Join-Path $extraLibrary 'mir-fixture-mir5-active-mods-observer_0.1.0.zip';Copy-Item -LiteralPath $archive -Destination $extraArchive
          $zip=[IO.Compression.ZipFile]::Open($extraArchive,[IO.Compression.ZipArchiveMode]::Update);try{$writer=[IO.StreamWriter]::new($zip.CreateEntry('mir-fixture-mir5-active-mods-observer_0.1.0/unexpected.lua').Open());try{$writer.Write('-- unexpected')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
          $extraHash=(Get-FileHash -LiteralPath $extraArchive -Algorithm SHA256).Hash
          Assert-Rejects 'extra archive member' {New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $extraLibrary -OutputRoot (Join-Path $env:MIR_TEST_WORK 'extra-output') -SourceRevision $sourceRevision -ExpectedArchiveSha256 $extraHash|Out-Null}
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

    def test_f210_space_age_api_client_fixture_requires_the_exact_native_and_library_vectors(self):
        accepted = self.run_case(target="f210-space-age")
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual((accepted["phase"], accepted["join_events"]), ("completed", 6))
        self.assertTrue(accepted["load_unchanged"])
        for marker in accepted["markers"]:
            witnesses = marker["witnesses"]
            self.assertTrue(witnesses["space_age_library"])
            live = witnesses["live_refresh"]
            self.assertIn("casting_gear_productivity", live)
            self.assertAlmostEqual(live["gear_productivity"], 0 if marker["stage"] == "ready" else .2)
            self.assertAlmostEqual(live["casting_gear_productivity"], 0 if marker["stage"] == "ready" else .2)

        expected = {
            "sa-casting-effect-missing": "Space Age native gear effect cardinality differs",
            "sa-casting-effect-duplicate": "Space Age native gear effect cardinality differs",
            "sa-casting-effect-wrong": "Space Age native gear effect differs",
            "sa-native-owner-missing": "Space Age native research-productivity owner differs",
            "sa-availability-wrong": "Space Age native research-productivity Availability differs",
            "sa-dlc-partial": "unexpected non-base F210 multiplayer closure",
            "sa-api-alpha-only": "unexpected non-base F210 multiplayer closure",
            "sa-api-beta-only": "unexpected non-base F210 multiplayer closure",
        }
        for opponent, message in expected.items():
            with self.subTest(opponent=opponent):
                rejected = self.run_case(opponent, target="f210-space-age")
                self.assertFalse(rejected["ok"])
                self.assertIn(message, rejected["message"])

    def test_private_credit_browser_probe_is_opt_in_and_preserves_native_state_and_personal_views(self):
        info = json.loads(PRIVATE_CREDITS_INFO.read_text(encoding="utf-8"))
        self.assertEqual(info, {
            "name": "mir-fixture-mir5-library-multiplayer",
            "version": "0.3.0",
            "title": "MIR 5 private-credit Library browser fixture",
            "author": "MIR maintainers",
            "description": "Disposable two-client F210 public Library private-credit browser observation fixture.",
            "factorio_version": "2.1",
            "dependencies": [
                "base >= 2.1.23",
                "? space-age >= 2.1.23",
                "more-infinite-research = 5.0.21000",
            ],
        })
        ids = (
            "mir-legacy-module-credit-speed-module",
            "mir-legacy-module-credit-productivity-module",
            "mir-legacy-module-credit-efficiency-module",
            "mir-legacy-cannon-credit-rocket-shooting-speed",
        )
        expected_state = {
            name: {
                "level": index,
                "researched": True,
                "enabled": False,
                "visible_when_disabled": False,
            }
            for index, name in enumerate(ids, start=1)
        }
        expected_order = [
            {"player": player, "family": family, "id": name}
            for player in (1, 2)
            for family in ("all", "external")
            for name in ids
        ]
        for target in ("f200-private-credits", "f210-private-credits", "f210-space-age-private-credits"):
            with self.subTest(target=target):
                accepted = self.run_case(target=target)
                self.assertTrue(accepted["ok"], accepted["message"])
                self.assertEqual((accepted["phase"], accepted["join_events"]), ("completed", 6))
                self.assertEqual([marker["stage"] for marker in accepted["markers"]],
                                 ["ready", "rejoin-ready", "restart-ready", "completed"])
                self.assertEqual(accepted["private_query_calls"], 16)
                self.assertEqual(accepted["private_query_order"], expected_order)
                for marker in accepted["markers"][:-1]:
                    self.assertNotIn("private_credit_visibility", marker["witnesses"])
                witness = accepted["markers"][-1]["witnesses"]["private_credit_visibility"]
                self.assertEqual(witness, {
                    "ids_checked": 4,
                    "clients_checked": 2,
                    "families_checked": ["all", "external"],
                    "private_selection_not_exposed": True,
                    "native_state_unchanged": True,
                    "personal_views_restored": True,
                    "before": expected_state,
                    "after": expected_state,
                })

        for target in ("f210", "f210-space-age"):
            with self.subTest(old_target=target):
                ordinary = self.run_case(target=target)
                self.assertTrue(ordinary["ok"], ordinary["message"])
                self.assertNotIn("private_credit_visibility", ordinary["markers"][-1]["witnesses"])

        opponents = {
            "private-credit-missing": "private credit holder is absent",
            "private-credit-listed": "private credit query exposed a public result or native action",
            "private-credit-action-enabled": "private credit query exposed a public result or native action",
            "private-credit-mutate": "private credit browse mutated native research state",
            "private-credit-empty-all": "public Library all query did not expose a selected ordinary result",
            "private-credit-empty-external": "public Library external query did not expose a selected ordinary result",
            "private-credit-automation-mutate": "public Library browse mutated the automation native state",
            "private-credit-restore": "personal browser query or selected view differs",
            "private-credit-stale-external-family": "private credit browse did not restore the personal mir family filter",
            "private-credit-missing-api": "unexpected non-base F210 multiplayer closure",
            "standalone-identity-discovery": "private-credit Library fixture cannot use standalone identity discovery",
        }
        for target in ("f200-private-credits", "f210-private-credits"):
            for opponent, message in opponents.items():
                with self.subTest(target=target, opponent=opponent):
                    rejected = self.run_case(opponent, target=target)
                    self.assertFalse(rejected["ok"])
                    expected = message.replace("F210", "F200") if target == "f200-private-credits" and opponent == "private-credit-missing-api" else message
                    self.assertIn(expected, rejected["message"])
        rejected = self.run_case("f210-api-consumers", target="f200")
        self.assertFalse(rejected["ok"])
        self.assertIn("unexpected non-base F200 multiplayer closure", rejected["message"])

    def test_positive_state_mode_preserves_seeded_effects_and_observes_saved_personal_filters(self):
        for target in ("f200-positive-state", "f210-positive-state"):
            with self.subTest(target=target):
                result = self.run_case(target=target)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["positive_seed_resets"], 1)
                self.assertTrue(result["load_unchanged"])
                self.assertEqual((result["join_events"], len(result["screenshots"]), len(result["saves"])), (6, 10, 2))
                for marker in result["markers"]:
                    witness = marker["witnesses"]["positive_private_state"]
                    self.assertEqual(witness["ownership"], "fixture-seeded-disposable-world")
                    self.assertFalse(witness["imported_earnings"])
                    self.assertTrue(witness["seeded_once"])
                    self.assertEqual(sorted(holder["level"] for holder in witness["native"]["holders"].values()), [2, 3, 4, 5])
                    self.assertEqual(witness["native"]["module_productivity"], {
                        "speed-module": .01, "productivity-module": .02, "efficiency-module": .03,
                    })
                    self.assertAlmostEqual(witness["native"]["cannon_speed"], .4)
                    completed = marker["stage"] == "completed"
                    self.assertEqual(witness["persisted_personal_hidden_checked"], completed)
                    self.assertEqual(witness["foreign_inspection_queries"], 44 if completed else 0)
        opponents = {
            "positive-not-fresh": "seed requires fresh zero-credit holder",
            "positive-holder-lost": "positive native holder changed",
            "positive-holder-enabled": "positive native holder changed",
            "positive-module-lost": "positive module contribution changed",
            "positive-cannon-lost": "positive cannon contribution changed",
            "positive-foreign-flags": "foreign hidden technology changed",
            "positive-foreign-suppressed": "foreign hidden research was suppressed",
            "positive-personal-hidden-lost": "excluded research or native action exposed",
        }
        for target in ("f200-positive-state", "f210-positive-state"):
            for opponent, message in opponents.items():
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(opponent, target=target)
                    self.assertFalse(result["ok"])
                    self.assertIn(message, result["message"])

    def test_positive_state_admission_projection_and_typed_readback_refuse_drift(self):
        markers = {target: self.run_case(target=target)["markers"] for target in ("f200-positive-state", "f210-positive-state")}
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Get-MIRImmutableInputSha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
          . (Join-Path $env:MIR_TEST_REPO 'tools/lib/compatibility/LibraryActivation.ps1')
          foreach($file in @($env:MIR_TEST_WRAPPER,$env:MIR_TEST_SESSION)){
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            if($errors.Count){throw 'native runner parse failed'}
            foreach($name in @('Assert-MultiplayerFixtureSelection','New-LibraryPositiveFixtureSourceProjection','Get-LibraryWitnessTarget','Test-LibraryInteger','Assert-LibraryWitnessBoolean','Assert-LibraryWitnessInteger','Assert-LibraryPositiveWitness')){
              $found=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
              if($found.Count-gt1){throw 'ambiguous definition'}
              if($found.Count-eq1){Invoke-Expression $found[0].Extent.Text}
            }
          }
          $sets=Get-Content -LiteralPath $env:MIR_TEST_POSITIVE_MARKERS -Raw|ConvertFrom-Json
          foreach($edition in @('f200','f210')){
            $profileName=if($edition-ceq'f200'){'library-positive-state-current-f200-2077.json'}else{'library-positive-state-standalone-f210-2123.json'}
            $profile=Get-Content -LiteralPath (Join-Path $env:MIR_TEST_REPO ('tests/profiles/'+$profileName)) -Raw|ConvertFrom-Json -AsHashtable
            $mirName=if($edition-ceq'f200'){'more-infinite-research_5.0.20000.zip'}else{'more-infinite-research_5.0.21000.zip'}
            $target=Assert-MultiplayerFixtureSelection $profile $profile.engine.sha256 'library-multiplayer' $profile.archive_sha256[$mirName] 7168
            if(-not$target.positive_private_state_checks){throw 'positive admission flag absent'}
            $spec=@{library_witness_target=@{engine_sha256=$target.engine_sha256;base=$target.base;mir=$target.mir};api_client_consumers=$true;private_credit_checks=$true;positive_private_state_checks=$true}
            $validated=Get-LibraryWitnessTarget $spec $target.engine_sha256
            if(-not$validated.positive_private_state_checks){throw 'positive session flag absent'}
            foreach($mutation in @('false','string','no-private','space-age')){
              $bad=$spec|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
              switch($mutation){
                'false'{$bad.positive_private_state_checks=$false}
                'string'{$bad.positive_private_state_checks='true'}
                'no-private'{$bad.Remove('private_credit_checks')|Out-Null}
                'space-age'{$bad.space_age_library=$true}
              }
              $rejected=$false
              try{$null=Get-LibraryWitnessTarget $bad $target.engine_sha256}catch{$rejected=$true}
              if(-not$rejected){throw "positive session accepted $mutation"}
            }
            foreach($mutation in @('no-positive','false-positive','string-positive','wrong-version','wrong-package','missing-beta','wrong-budget','wrong-case')){
              $bad=$profile|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
              $budget=7168;$case='library-multiplayer'
              switch($mutation){
                'no-positive'{$bad.Remove('positive_private_state_checks')|Out-Null}
                'false-positive'{$bad.positive_private_state_checks=$false}
                'string-positive'{$bad.positive_private_state_checks='true'}
                'wrong-version'{@($bad.mods|Where-Object {$_.name-ceq'mir-fixture-mir5-library-multiplayer'})[0].version='0.3.0'}
                'wrong-package'{$bad.archive_sha256[$mirName]='A'*64}
                'missing-beta'{$bad.mods=@($bad.mods|Where-Object {$_.name-cne'mir-fixture-mir5-api-beta'})}
                'wrong-budget'{$budget=8192}
                'wrong-case'{$case='library-paired-browser'}
              }
              $rejected=$false
              try{$null=Assert-MultiplayerFixtureSelection $bad $profile.engine.sha256 $case $profile.archive_sha256[$mirName] $budget}catch{$rejected=$true}
              if(-not$rejected){throw "positive profile accepted $mutation"}
            }
            $projection=New-LibraryPositiveFixtureSourceProjection -RepoRoot $env:MIR_TEST_REPO -OutputRoot (Join-Path $env:MIR_TEST_TEMP $edition) -Target $edition
            $files=@(Get-ChildItem -LiteralPath $projection.source -File|Sort-Object Name)
            if(($files.Name-join'|')-cne'control.lua|data.lua|info.json|positive-state.lua|settings-updates.lua'){throw 'positive projection membership differs'}
            foreach($member in $projection.members){
              if((Get-FileHash -LiteralPath (Join-Path $projection.source $member.path)).Hash-cne(Get-FileHash -LiteralPath (Join-Path $env:MIR_TEST_REPO $member.source)).Hash){throw 'projected source bytes differ'}
            }
            $archive=Join-Path $env:MIR_TEST_TEMP ($edition+'-positive.zip')
            $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
            try{foreach($file in $files){
              $entry=$zip.CreateEntry('mir-fixture-mir5-library-multiplayer_0.4.0/'+$file.Name)
              $stream=$entry.Open();try{$bytes=[IO.File]::ReadAllBytes($file.FullName);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
            }}finally{$zip.Dispose()}
            Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $projection.source
            $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Update)
            try{$null=$zip.CreateEntry('mir-fixture-mir5-library-multiplayer_0.4.0/developer.txt')}finally{$zip.Dispose()}
            $rejected=$false
            try{Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $projection.source}catch{$rejected=$true}
            if(-not$rejected){throw 'positive archive accepted an extra developer member'}
            $targetWitness=[pscustomobject]@{positive_private_state_checks=$true}
            foreach($marker in $sets.PSObject.Properties[($edition+'-positive-state')].Value){
              Assert-LibraryPositiveWitness $marker.witnesses $targetWitness $marker.stage
            }
            $complete=@($sets.PSObject.Properties[($edition+'-positive-state')].Value|Where-Object {$_.stage-ceq'completed'})[0].witnesses
            foreach($mutation in @('missing','extra-field','import-claim','false-seeded','lost-holder','enabled-holder','lost-module','lost-cannon','lost-persistence','missing-query','unexpected-mode')){
              $bad=$complete|ConvertTo-Json -Depth 30|ConvertFrom-Json
              $actualTarget=$targetWitness
              switch($mutation){
                'missing'{$bad.PSObject.Properties.Remove('positive_private_state')}
                'extra-field'{$bad.positive_private_state|Add-Member extra $true}
                'import-claim'{$bad.positive_private_state.imported_earnings=$true}
                'false-seeded'{$bad.positive_private_state.seeded_once=$false}
                'lost-holder'{$bad.positive_private_state.native.holders.'mir-legacy-module-credit-speed-module'.level=1}
                'enabled-holder'{$bad.positive_private_state.native.holders.'mir-legacy-cannon-credit-rocket-shooting-speed'.enabled=$true}
                'lost-module'{$bad.positive_private_state.native.module_productivity.'productivity-module'=0.0}
                'lost-cannon'{$bad.positive_private_state.native.cannon_speed=0.0}
                'lost-persistence'{$bad.positive_private_state.persisted_personal_hidden_checked=$false}
                'missing-query'{$bad.positive_private_state.foreign_inspection_queries=43}
                'unexpected-mode'{$actualTarget=[pscustomobject]@{}}
              }
              $rejected=$false
              try{Assert-LibraryPositiveWitness $bad $actualTarget 'completed'}catch{$rejected=$true}
              if(-not$rejected){throw "positive witness accepted $mutation"}
            }
          }
        '''
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "markers.json"
            path.write_text(json.dumps(markers), encoding="utf-8")
            process = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT, env={
                **os.environ, "MIR_TEST_REPO": str(ROOT), "MIR_TEST_WRAPPER": str(WRAPPER),
                "MIR_TEST_SESSION": str(SESSION), "MIR_TEST_POSITIVE_MARKERS": str(path), "MIR_TEST_TEMP": temporary,
            }, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)

    def test_positive_seed_avoids_the_native_level_resetting_researched_setter(self):
        ids = ["mir-legacy-module-credit-speed-module", "mir-legacy-module-credit-productivity-module",
               "mir-legacy-module-credit-efficiency-module", "mir-legacy-cannon-credit-rocket-shooting-speed"]
        for target in ("f200-positive-state", "f210-positive-state"):
            for opponent in (None, "positive-researched-setter-resets-level"):
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(opponent, target=target)
                    self.assertEqual(result["ok"], opponent is None)
                    rows = result["seed_diagnostics"]
                    self.assertEqual(len(rows), 7)
                    self.assertEqual([r["seed_stage"] for r in rows], ["before-assignments"] +
                                     ["after-level-assignment"] * 4 +
                                     ["before-effect-reset", "after-effect-reset"])
                    for index, name in enumerate(ids):
                        after_level = rows[1+index]
                        self.assertEqual(after_level["assigned_id"], name)
                        self.assertEqual(after_level["holders"][index]["level"], 1 if opponent else index+2)
                    self.assertEqual(result["researched_set_calls"], 4 if opponent else 0)
                    if opponent:
                        self.assertIn("positive native holder changed", result["message"])
                        self.assertEqual([holder["level"] for holder in rows[-1]["holders"]], [1, 1, 1, 1])
                        self.assertEqual(rows[-1]["cannon_speed"], 0)

    def test_two_real_client_join_rejoin_and_restart_state_machine(self):
        result = self.run_case()
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((result["phase"], result["join_events"]), ("completed", 6))
        self.assertTrue(result["load_unchanged"])
        self.assertEqual([item["stage"] for item in result["markers"]], ["ready", "rejoin-ready", "restart-ready", "completed"])
        completed = result["markers"][-1]["witnesses"]
        self.assertNotIn("space_age_library", completed)
        self.assertTrue(completed["on_load_read_only"])
        self.assertTrue(completed["availability_terminal_labels_checked"])
        self.assertEqual(completed["screenshot_calls"], 10)
        self.assertTrue(completed["initial_settled_without_reopen"])
        self.assertEqual(completed["initial_settle_ticks"], 60)
        self.assertEqual(result["saves"], ["mir5-library-multiplayer-restart", "mir5-native-complete"])
        live_refresh = completed["live_refresh"]
        self.assertNotIn("casting_gear_productivity", live_refresh)
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
        self.assertIn("native public browser list/detail pane geometry differs", failed["message"])

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
        results = {target: self.run_case(target=target) for target in (
            "f200", "f210", "f210-space-age", "f200-private-credits", "f210-private-credits", "f210-space-age-private-credits",
        )}
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
            'Assert-LibraryLiveRefresh','Assert-LibraryPositiveWitness','Get-StageMarker')
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
            f200_private=[ordered]@{engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';base='2.0.77';mir='5.0.20000';private_credit_checks=$true}
            f210=[ordered]@{engine_sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060';base='2.1.23';mir='5.0.21000'}
            standalone_normal=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$false}
            standalone_discovery=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$true}
            standalone_space_age=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$false;space_age_library=$true}
            standalone_private_base=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$false;private_credit_checks=$true}
            standalone_private_space_age=[ordered]@{engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';base='2.1.23';mir='5.0.21000';standalone_identity_discovery=$false;space_age_library=$true;private_credit_checks=$true}
          }
          function New-LibraryWitnessSpec([hashtable]$Target){
            $spec=@{library_witness_target=([ordered]@{engine_sha256=$Target.engine_sha256;base=$Target.base;mir=$Target.mir})}
            if($Target.Contains('standalone_identity_discovery') -and $Target.standalone_identity_discovery){$spec.standalone_identity_discovery=$true}
            if($Target.Contains('space_age_library') -and $Target.space_age_library){$spec.space_age_library=$true;$spec.api_client_consumers=$true}
            if($Target.Contains('private_credit_checks') -and $Target.private_credit_checks){$spec.private_credit_checks=$true;$spec.api_client_consumers=$true}
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
          $spaceAgeStandalone=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $targets.standalone_space_age) $targets.standalone_space_age.engine_sha256
          Assert-LibraryWitnessBoolean $spaceAgeStandalone 'space_age_library' $true 'Space Age standalone target'
          Assert-LibraryWitnessIdentityMode $false $spaceAgeStandalone
          $malformedStandalone=New-LibraryWitnessSpec $targets.standalone_normal;$malformedStandalone.standalone_identity_discovery='true'
          Assert-LibraryWitnessTargetRejects $malformedStandalone $targets.standalone_normal.engine_sha256 'malformed standalone mode'
          $explicitFalseStandalone=New-LibraryWitnessSpec $targets.standalone_normal;$explicitFalseStandalone.standalone_identity_discovery=$false
          Assert-LibraryWitnessTargetRejects $explicitFalseStandalone $targets.standalone_normal.engine_sha256 'explicit false standalone mode'
          $missingSpaceAgeConsumer=New-LibraryWitnessSpec $targets.standalone_space_age;$missingSpaceAgeConsumer.Remove('api_client_consumers')
          Assert-LibraryWitnessTargetRejects $missingSpaceAgeConsumer $targets.standalone_space_age.engine_sha256 'Space Age target without API consumer mode'
          $falseSpaceAge=New-LibraryWitnessSpec $targets.standalone_space_age;$falseSpaceAge.space_age_library=$false
          Assert-LibraryWitnessTargetRejects $falseSpaceAge $targets.standalone_space_age.engine_sha256 'false Space Age target'
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
          $expectedSpaceAgeWitness=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $targets.standalone_space_age) $targets.standalone_space_age.engine_sha256
          $spaceAgeMarkers=@($markerSets['f210-space-age'])
          if($spaceAgeMarkers.Count-ne4){throw 'actual fixture markers are incomplete: f210-space-age'}
          foreach($marker in $spaceAgeMarkers){
            $stage=[string]$marker['stage']
            $line='[MIR5_LIBRARY_MULTIPLAYER] RESULT '+($marker|ConvertTo-Json -Depth 20 -Compress)
            $accepted=Get-StageMarker $line $stage ([int]$expectedJoins[$stage]) $expectedSpaceAgeWitness
            if($null-eq$accepted-or$accepted.stage-cne$stage){throw "actual Space Age fixture marker rejected: $stage"}
          }
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

          $spaceAgeByStage=@{}
          foreach($marker in $spaceAgeMarkers){$spaceAgeByStage[[string]$marker['stage']]=$marker}
          function Assert-SpaceAgeReaderRejects([hashtable]$Marker,[string]$ExpectedStage,[int]$ExpectedJoins,[string]$Name){
            $line=ConvertTo-LibraryMarkerLine $Marker
            try{$accepted=Get-StageMarker $line $ExpectedStage $ExpectedJoins $expectedSpaceAgeWitness}catch{return}
            if($null-ne$accepted){throw "reader accepted invalid Space Age marker: $Name"}
          }
          $missingSpaceAgeWitness=Copy-LibraryMarker $spaceAgeByStage['ready']
          $missingSpaceAgeWitness['witnesses'].Remove('space_age_library')
          Assert-SpaceAgeReaderRejects $missingSpaceAgeWitness 'ready' 0 'missing Space Age witness'
          $falseSpaceAgeWitness=Copy-LibraryMarker $spaceAgeByStage['ready']
          $falseSpaceAgeWitness['witnesses']['space_age_library']=$false
          Assert-SpaceAgeReaderRejects $falseSpaceAgeWitness 'ready' 0 'false Space Age witness'
          $missingCastingReady=Copy-LibraryMarker $spaceAgeByStage['ready']
          $missingCastingReady['witnesses']['live_refresh'].Remove('casting_gear_productivity')
          Assert-SpaceAgeReaderRejects $missingCastingReady 'ready' 0 'missing ready casting productivity'
          $wrongCastingReady=Copy-LibraryMarker $spaceAgeByStage['ready']
          $wrongCastingReady['witnesses']['live_refresh']['casting_gear_productivity']=1
          Assert-SpaceAgeReaderRejects $wrongCastingReady 'ready' 0 'wrong ready casting productivity'
          $wrongCastingCompleted=Copy-LibraryMarker $spaceAgeByStage['completed']
          $wrongCastingCompleted['witnesses']['live_refresh']['casting_gear_productivity']=.1
          Assert-SpaceAgeReaderRejects $wrongCastingCompleted 'completed' 6 'wrong completed casting productivity'
          $crossedBase=Copy-LibraryMarker $byStage['completed']
          $crossedBase['witnesses']['space_age_library']=$true
          $crossedBase['witnesses']['live_refresh']['casting_gear_productivity']=.2
          Assert-LibraryReaderRejects $crossedBase 'completed' 6 'Base marker with Space Age fields'
          $crossedSpaceAge=Copy-LibraryMarker $spaceAgeByStage['completed']
          $line=ConvertTo-LibraryMarkerLine $crossedSpaceAge
          try{$accepted=Get-StageMarker $line 'completed' 6 $expectedLibraryWitness}catch{$accepted=$null}
          if($null-ne$accepted){throw 'Base reader accepted a Space Age marker'}

          $privateTargets=[ordered]@{
            'f200-private-credits'=$targets.f200_private
            'f210-private-credits'=$targets.standalone_private_base
            'f210-space-age-private-credits'=$targets.standalone_private_space_age
          }
          $privateByTarget=@{}
          foreach($targetName in $privateTargets.Keys){
            $target=$privateTargets[$targetName]
            $expectedPrivateWitness=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $target) $target.engine_sha256
            Assert-LibraryWitnessBoolean $expectedPrivateWitness 'private_credit_checks' $true "private target $targetName"
            $targetMarkers=@($markerSets[$targetName])
            if($targetMarkers.Count-ne4){throw "actual private-credit fixture markers are incomplete: $targetName"}
            $byPrivateStage=@{}
            foreach($marker in $targetMarkers){
              $stage=[string]$marker['stage']
              $line=ConvertTo-LibraryMarkerLine $marker
              $accepted=Get-StageMarker $line $stage ([int]$expectedJoins[$stage]) $expectedPrivateWitness
              if($null-eq$accepted-or$accepted.stage-cne$stage){throw "actual private-credit fixture marker rejected: $targetName/$stage"}
              $byPrivateStage[$stage]=$marker
            }
            $privateByTarget[$targetName]=[ordered]@{target=$target;expected=$expectedPrivateWitness;stages=$byPrivateStage}
          }
          function Assert-PrivateReaderRejects([hashtable]$Marker,[object]$Expected,[string]$ExpectedStage,[int]$ExpectedJoins,[string]$Name){
            $line=ConvertTo-LibraryMarkerLine $Marker
            try{$accepted=Get-StageMarker $line $ExpectedStage $ExpectedJoins $Expected}catch{return}
            if($null-ne$accepted){throw "reader accepted invalid private-credit marker: $Name"}
          }
          $privateBase=$privateByTarget['f210-private-credits']
          $privateCompleted=$privateBase.stages['completed']
          $missingPrivate=Copy-LibraryMarker $privateCompleted
          $missingPrivate['witnesses'].Remove('private_credit_visibility')
          Assert-PrivateReaderRejects $missingPrivate $privateBase.expected 'completed' 6 'missing private witness'
          $falsePrivate=Copy-LibraryMarker $privateCompleted
          $falsePrivate['witnesses']['private_credit_visibility']['private_selection_not_exposed']=$false
          Assert-PrivateReaderRejects $falsePrivate $privateBase.expected 'completed' 6 'false private selection witness'
          $malformedPrivate=Copy-LibraryMarker $privateCompleted
          $malformedPrivate['witnesses']['private_credit_visibility']['ids_checked']='4'
          Assert-PrivateReaderRejects $malformedPrivate $privateBase.expected 'completed' 6 'malformed private count'
          $wrongPrivateCount=Copy-LibraryMarker $privateCompleted
          $wrongPrivateCount['witnesses']['private_credit_visibility']['families_checked']=@('all')
          Assert-PrivateReaderRejects $wrongPrivateCount $privateBase.expected 'completed' 6 'private family count'
          $foreignPrivateId=Copy-LibraryMarker $privateCompleted
          $before=$foreignPrivateId['witnesses']['private_credit_visibility']['before']
          $before.Remove('mir-legacy-module-credit-speed-module')
          $before['foreign-credit']=[ordered]@{level=1;researched=$true;enabled=$false;visible_when_disabled=$false}
          Assert-PrivateReaderRejects $foreignPrivateId $privateBase.expected 'completed' 6 'foreign private holder identity'
          $changedPrivateLevel=Copy-LibraryMarker $privateCompleted
          $changedPrivateLevel['witnesses']['private_credit_visibility']['after']['mir-legacy-module-credit-speed-module']['level']=2
          Assert-PrivateReaderRejects $changedPrivateLevel $privateBase.expected 'completed' 6 'changed private holder level'
          $wrongSnapshotKey=Copy-LibraryMarker $privateCompleted
          $holder=$wrongSnapshotKey['witnesses']['private_credit_visibility']['before']['mir-legacy-module-credit-speed-module']
          $holder.Remove('visible_when_disabled');$holder['unexpected']=$false
          Assert-PrivateReaderRejects $wrongSnapshotKey $privateBase.expected 'completed' 6 'private snapshot key'
          $prematurePrivate=Copy-LibraryMarker $privateBase.stages['ready']
          $prematurePrivate['witnesses']['private_credit_visibility']=$privateCompleted['witnesses']['private_credit_visibility']
          Assert-PrivateReaderRejects $prematurePrivate $privateBase.expected 'ready' 0 'premature private witness'
          $expectedNormalStandalone=Get-LibraryWitnessTarget (New-LibraryWitnessSpec $targets.standalone_normal) $targets.standalone_normal.engine_sha256
          Assert-PrivateReaderRejects (Copy-LibraryMarker $privateCompleted) $expectedNormalStandalone 'completed' 6 'private witness crossed into ordinary mode'
          $falsePrivateTarget=New-LibraryWitnessSpec $targets.standalone_private_base;$falsePrivateTarget.private_credit_checks=$false
          Assert-LibraryWitnessTargetRejects $falsePrivateTarget $targets.standalone_private_base.engine_sha256 'false private target mode'
          $missingPrivateConsumer=New-LibraryWitnessSpec $targets.standalone_private_base;$missingPrivateConsumer.Remove('api_client_consumers')
          Assert-LibraryWitnessTargetRejects $missingPrivateConsumer $targets.standalone_private_base.engine_sha256 'private target without API consumer mode'
          $privateDiscovery=New-LibraryWitnessSpec $targets.standalone_private_base;$privateDiscovery.standalone_identity_discovery=$true
          Assert-LibraryWitnessTargetRejects $privateDiscovery $targets.standalone_private_base.engine_sha256 'private target with discovery mode'

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
        library = (ROOT / "source/runtime/library.lua").read_text(encoding="utf-8")
        harness = Path(__file__).read_text(encoding="utf-8")
        self.assertIn('type = "sprite-button", name = PREFIX .. "open_native"', library)
        self.assertIn('native_open.type ~= "sprite-button"', source)
        self.assertIn('actions[OPEN_NATIVE]=element("sprite-button",OPEN_NATIVE)', harness)
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
        self.assertEqual(source.count('require("positive-state")'), 1)
        self.assertNotIn("require(", source.replace('require("positive-state")', ""))
        self.assertLess(source.index('require("positive-state")'), source.index('local GEAR_RECIPES'))
        positive = (ROOT / "tests/fixtures/library-positive-state/positive-state.lua").read_text(encoding="utf-8")
        for forbidden in ("require(", "storage.", "storage[", "script.raise_event", "script.on_event"):
            self.assertNotIn(forbidden, positive)
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

    def test_lifetime_peaks_read_owned_os_counters_at_close_without_extra_periodic_samples(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          function Get-Process {throw 'no process rediscovery'}
          function Get-CimInstance {throw 'no process tree discovery'}
          . $env:MIR_TEST_SAMPLER
          $process=[Diagnostics.Process]::GetCurrentProcess()
          try {
            $slot=@([pscustomobject]@{phase='initial';role='server'})
            $ordinary=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot
            $ordinaryRegistration=Register-MIROwnedProcessMemoryProcess $ordinary initial server $process
            Add-MIROwnedProcessMemorySample $ordinary
            Complete-MIROwnedProcessMemoryProcess $ordinary $ordinaryRegistration
            $ordinaryReceipt=Get-MIROwnedProcessMemoryObservationReceipt $ordinary
            if($ordinaryReceipt.PSObject.Properties['lifetime_peak_counters']-or$ordinaryReceipt.PSObject.Properties['lifetime_peak_observer']){throw 'default receipt gained peak fields'}

            $sampler=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot -IncludeLifetimePeaks
            $registration=Register-MIROwnedProcessMemoryProcess $sampler initial server $process
            Add-MIROwnedProcessMemorySample $sampler
            $firstWorkingSet=$sampler.observations[0].working_set_bytes
            # No periodic sample is due. A final OS high-water read must still
            # occur, without making an off-cadence periodic observation.
            $sampler.next_due_monotonic_milliseconds=[double]::MaxValue
            Complete-MIROwnedProcessMemoryProcess $sampler $registration
            Complete-MIROwnedProcessMemoryProcess $sampler $registration
            $receipt=Get-MIROwnedProcessMemoryObservationReceipt $sampler
            if($receipt.status-cne'complete-observation'-or$receipt.performance_acceptance-or$receipt.observations.Count-ne1-or$receipt.lifetime_peak_counters.Count-ne1){throw 'opted-in close changed sampling or duplicated counters'}
            $peak=$receipt.lifetime_peak_counters[0]
            if($peak.phase-cne'initial'-or$peak.role-cne'server'-or$peak.pid-ne$process.Id-or$peak.start_utc-cne$registration.start_utc){throw 'peak identity differs'}
            if($peak.working_set_peak_bytes-lt$firstWorkingSet-or$peak.paged_memory_peak_bytes-lt0-or$peak.elapsed_monotonic_milliseconds-lt$receipt.observations[0].elapsed_monotonic_milliseconds){throw 'invalid native high-water values'}
            if([datetime]::Parse($peak.observed_utc).ToUniversalTime()-lt$process.StartTime.ToUniversalTime()){throw 'peak UTC precedes process creation'}
            if($receipt.lifetime_peak_observer.changes_periodic_observations-ne$false-or$process.HasExited){throw 'observer changed process lifetime or periodic semantics'}

            $drift=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot -IncludeLifetimePeaks
            $driftRegistration=Register-MIROwnedProcessMemoryProcess $drift initial server $process
            Add-MIROwnedProcessMemorySample $drift
            $drift.next_due_monotonic_milliseconds=[double]::MaxValue
            $driftRegistration.start_utc='1970-01-01T00:00:00.0000000Z'
            Complete-MIROwnedProcessMemoryProcess $drift $driftRegistration
            $refused=Get-MIROwnedProcessMemoryObservationReceipt $drift
            if($refused.status-cne'incomplete-observation'-or$refused.lifetime_peak_counters.Count-ne0-or$refused.incomplete_reasons-notcontains'lifetime-peak-unavailable-or-identity-drift'){throw 'final counter accepted changed process identity'}

            $exited=New-MIROwnedProcessMemorySampler -ExpectedSlots $slot -IncludeLifetimePeaks
            $exitedRegistration=Register-MIROwnedProcessMemoryProcess $exited initial server $process
            Add-MIROwnedProcessMemorySample $exited
            Complete-MIROwnedProcessMemoryProcess $exited $exitedRegistration -NaturalExit
            if((Get-MIROwnedProcessMemoryObservationReceipt $exited).status-cne'incomplete-observation'){throw 'natural exit invented unavailable peaks'}
            $caught=$false
            try{New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots @([pscustomobject]@{phase='benchmark';role='factorio'}) -IncludeLifetimePeaks|Out-Null}catch{$caught=$true}
            if(-not$caught){throw 'benchmark contract silently acquired lifetime peaks'}
          } finally {$process.Dispose()}
        '''
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                capture_output=True, text=True, check=False,
                                env=dict(os.environ, MIR_TEST_SAMPLER=str(SAMPLER)))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_lifetime_peak_opt_in_requires_typed_library_memory_and_stays_absent_by_default(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_SESSION,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session syntax differs'}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          $function=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Get-ProcessLifetimePeakOptIn'},$true))
          if($function.Count-ne1){throw 'typed lifetime opt-in missing'}
          Invoke-Expression $function[0].Extent.Text
          if(Get-ProcessLifetimePeakOptIn @{} 'library-multiplayer' $true){throw 'default activated lifetime counters'}
          foreach($case in @('library-multiplayer','library-paired-browser')){
            if(-not(Get-ProcessLifetimePeakOptIn @{process_memory_lifetime_peaks=$true} $case $true)){throw 'typed opt-in refused'}
          }
          foreach($bad in @('true',1,@{})){
            $caught=$false;try{Get-ProcessLifetimePeakOptIn @{process_memory_lifetime_peaks=$bad} 'library-multiplayer' $true|Out-Null}catch{$caught=$true}
            if(-not$caught){throw 'untyped peak flag accepted'}
          }
          foreach($row in @(@{case='library-multiplayer';memory=$false},@{case='scripted-effects-multiplayer';memory=$true})){
            $caught=$false;try{Get-ProcessLifetimePeakOptIn @{process_memory_lifetime_peaks=$true} $row.case $row.memory|Out-Null}catch{$caught=$true}
            if(-not$caught){throw 'unadmitted peak context accepted'}
          }
          $wrapper=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_WRAPPER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'wrapper syntax differs'}
          $forward=@($wrapper.FindAll({param($n)$n-is[Management.Automation.Language.IfStatementAst]-and$n.Extent.Text-ceq'if($CollectProcessLifetimePeaks){$spec.process_memory_lifetime_peaks=$true}'},$true))
          if($forward.Count-ne1){throw 'explicit forwarding boundary missing'}
          $CollectProcessLifetimePeaks=$false;$spec=@{};Invoke-Expression $forward[0].Extent.Text
          if($spec.ContainsKey('process_memory_lifetime_peaks')){throw 'legacy spec gained a field'}
          $CollectProcessLifetimePeaks=$true;Invoke-Expression $forward[0].Extent.Text
          if($spec.process_memory_lifetime_peaks-isnot[bool]-or-not$spec.process_memory_lifetime_peaks){throw 'typed forwarding lost'}
          $guard=@($wrapper.EndBlock.Statements|Where-Object {$_.Extent.Text.EndsWith("'lifetime peak counters require opted-in Library memory observations'",[StringComparison]::Ordinal)})
          if($guard.Count-ne1){throw 'prelaunch lifetime peak guard missing'}
          $check=[scriptblock]::Create($guard[0].Extent.Text)
          $CollectProcessMemoryObservations=$true;$StandaloneIdentityDiscovery=$false;$FixtureCase='library-paired-browser';&$check
          foreach($opponent in @('without-memory','discovery','different-case')){
            $CollectProcessMemoryObservations=$true;$StandaloneIdentityDiscovery=$false;$FixtureCase='library-paired-browser'
            switch($opponent){
              'without-memory'{$CollectProcessMemoryObservations=$false}
              'discovery'{$StandaloneIdentityDiscovery=$true}
              'different-case'{$FixtureCase='scripted-effects-multiplayer'}
            }
            $caught=$false;try{&$check}catch{$caught=$true};if(-not$caught){throw "unadmitted wrapper context accepted:$opponent"}
          }
        '''
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                capture_output=True, text=True, check=False,
                                env=dict(os.environ, MIR_TEST_SESSION=str(SESSION), MIR_TEST_WRAPPER=str(WRAPPER)))
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
            @{schema=1;case='library-paired-browser';stage='search';status='observed';arm='published';join_events=2;action_call_count=2;screenshot_calls=6;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='refresh';status='observed';arm='published';join_events=2;action_call_count=2;screenshot_calls=8;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='restart-ready';status='ready';arm='published';join_events=2;action_call_count=2;screenshot_calls=8;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='reopen';status='observed';arm='published';join_events=4;action_call_count=2;screenshot_calls=10;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false},
            @{schema=1;case='library-paired-browser';stage='completed';status='passed';arm='published';join_events=4;action_call_count=2;screenshot_calls=12;native_snapshot_unchanged=$true;profiler_observation_only=$true;performance_acceptance=$false}
          )
          foreach($row in $rows){
            $row.requested_family='all'
            $row.native_family_verified=$row.stage -cin @('first-open','search','refresh','reopen')
          }
          function MarkerText($InputRows){return (($InputRows|ForEach-Object {'[MIR5_LIBRARY_PAIRED_BROWSER] '+($_|ConvertTo-Json -Compress)})-join "`n")+"`n"}
          $text=MarkerText $rows
          foreach($row in $rows){$accepted=Get-PairedBrowserStageMarker $text $row.stage 'published';if($accepted.stage-cne$row.stage){throw 'valid paired stage rejected'}}
          $profiles="[MIR5_LIBRARY_PROFILE] first_open Duration: 1.000000ms`n[MIR5_LIBRARY_PROFILE] search Duration: 1.000000ms`n[MIR5_LIBRARY_PROFILE] refresh Duration: 1.000000ms`n[MIR5_LIBRARY_PROFILE] reopen Duration: 1.000000ms`n"
          $observations=@(Get-PairedBrowserProfilerMarkers $profiles @('first_open','search','refresh','reopen'))
          if($observations.Count-ne4 -or $observations[0].raw_line -cne '[MIR5_LIBRARY_PROFILE] first_open Duration: 1.000000ms'){throw 'paired profiler provenance differs'}
          function Assert-Rejects([scriptblock]$Block,[string]$Name){$rejected=$false;try{&$Block}catch{$rejected=$true};if(-not$rejected){throw "paired reader accepted invalid $Name"}}
          $duplicate=@($rows)+@($rows[-1]);Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $duplicate) 'completed' 'published'|Out-Null} 'duplicate stage'
          $wrongArm=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$wrongArm[1].arm='mir5';Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $wrongArm) 'first-open' 'published'|Out-Null} 'wrong arm'
          $wrongFamily=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$wrongFamily[1].requested_family='mir';Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $wrongFamily) 'first-open' 'published'|Out-Null} 'wrong family'
          $unverifiedFamily=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$unverifiedFamily[1].native_family_verified=$false;Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $unverifiedFamily) 'first-open' 'published'|Out-Null} 'unverified actual family'
          $stringFamily=$rows|ForEach-Object {$_|ConvertTo-Json -Compress|ConvertFrom-Json -AsHashtable};$stringFamily[1].native_family_verified='true';Assert-Rejects {Get-PairedBrowserStageMarker (MarkerText $stringFamily) 'first-open' 'published'|Out-Null} 'nonboolean family proof'
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
        self.assertIn("@('first-open','first-open-settled','search','refresh','reopen','reopen-settled')", wrapper)
        self.assertIn("MIR5LibraryPairedBrowserSessionV1", session)
        self.assertIn("Get-PairedBrowserStageMarker", session)
        self.assertIn("Get-PairedBrowserProfilerMarkers", session)
        self.assertIn("@('initial','restart')", session)
        self.assertIn("$screenshots.Count -eq 12", session)
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

    def test_real_capture_files_keep_immediate_and_settled_stages_distinct(self):
        # Exercise the actual filename matcher and PNG reader, rather than a
        # count-only teardown double that cannot expose wildcard collisions.
        import struct
        import zlib
        def chunk(kind, body):
            return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1280, 720, 8, 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(b'\0' * (720 * (1280 * 3 + 1)))) + chunk(b'IEND', b'')
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($env:MIR_TEST_SESSION),[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'session parse failed'}
          function Assert-Session([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
          function Resolve-BuildInput([string]$Path,[string]$Kind,[string]$Label){
            if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'missing capture input'}
            return [IO.Path]::GetFullPath($Path)
          }
          foreach($name in @('Test-Png1280x720','Find-Screenshots')){
            $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($nodes.Count-ne1){throw "missing real screenshot definition: $name"}
            Invoke-Expression $nodes[0].Extent.Text
          }
          $fixtureCase='library-paired-browser'
          $stages=@('first-open','first-open-settled','search','refresh','reopen','reopen-settled')
          $screenshotPatterns=@(foreach($client in @('en','de')){foreach($stage in $stages){
            $folder=Join-Path $env:MIR_TEST_WORK $client
            @{client=$client;stage=$stage;path=(Join-Path $folder ($stage+'-*.png'));leaf=($stage+'-*.png')}
          }})
          $initial=Find-Screenshots @('first-open','first-open-settled','search','refresh')
          $complete=Find-Screenshots $stages
          if($initial.files.Count-ne8-or$complete.files.Count-ne12){throw 'real settled capture inventory lost or collided'}
          $extra=Join-Path $env:MIR_TEST_WORK 'en/first-open-2.png'
          [IO.File]::Copy((Join-Path $env:MIR_TEST_WORK 'en/first-open-1.png'),$extra)
          if($null-ne(Find-Screenshots $stages)){throw 'duplicate player-index capture was accepted'}
          [IO.File]::Delete($extra)
          $missing=Join-Path $env:MIR_TEST_WORK 'de/reopen-settled-2.png'
          $saved=[IO.File]::ReadAllBytes($missing);[IO.File]::Delete($missing)
          if($null-ne(Find-Screenshots $stages)){throw 'missing settled capture was accepted'}
          [IO.File]::WriteAllBytes($missing,$saved)
          [IO.File]::WriteAllBytes($missing,[byte[]]@(1,2,3))
          if($null-ne(Find-Screenshots $stages)){throw 'malformed settled PNG was accepted'}
          [IO.File]::WriteAllBytes($missing,$saved)
          foreach($stage in $stages){Move-Item -LiteralPath (Join-Path $env:MIR_TEST_WORK ('de/'+$stage+'-2.png')) -Destination (Join-Path $env:MIR_TEST_WORK ('de/'+$stage+'-1.png'))}
          $caught=$false
          try{Find-Screenshots $stages|Out-Null}catch{if($_.Exception.Message-cne'client screenshot player indexes are not distinct and stable'){throw};$caught=$true}
          if(-not$caught){throw 'same native player index across clients was accepted'}
          $fixtureCase='library-multiplayer';$stages=@('availability','initial','settled','rejoin','restart')
          $screenshotPatterns=@(foreach($client in @('en','de')){foreach($stage in $stages){
            $index=if($client-ceq'en'){1}else{2};$folder=Join-Path $env:MIR_TEST_WORK $client
            [IO.File]::WriteAllBytes((Join-Path $folder ($stage+'-'+$index+'.png')),$saved)
            @{client=$client;stage=$stage;path=(Join-Path $folder ($stage+'-*.png'));leaf=($stage+'-*.png')}
          }})
          if((Find-Screenshots $stages).files.Count-ne10){throw 'unrelated ten-capture functional path changed'}
        '''
        with tempfile.TemporaryDirectory() as work:
            for locale, index in [('en', 1), ('de', 2)]:
                folder = Path(work) / locale
                folder.mkdir()
                for stage in ['first-open', 'first-open-settled', 'search', 'refresh', 'reopen', 'reopen-settled']:
                    (folder / f'{stage}-{index}.png').write_bytes(png)
            result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script], capture_output=True, text=True,
                                    env=dict(os.environ, MIR_TEST_SESSION=str(SESSION), MIR_TEST_WORK=work), check=False)
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
            $count=2*$Stages.Count
            if($Stages.Count-eq6 -and $script:mode-ceq'missing-settled-capture'){$count--}
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
              return Find-Screenshots @('first-open','first-open-settled','search','refresh','reopen','reopen-settled')
            }
            return $true
          }
          foreach($fixtureCase in @('library-multiplayer','library-paired-browser','scripted-effects-multiplayer')){
            $modes=if($fixtureCase-ceq'library-paired-browser'){@('success','appended-phase','cleanup','primary-and-cleanup','missing-phase','missing-settled-capture')}else{@('success','cleanup','primary-and-cleanup')}
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
                $expectedCaptures=switch($fixtureCase){'library-multiplayer'{10};'library-paired-browser'{12};default{0}}
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
                  'missing-settled-capture'{'paired Browser final screenshot inventory differs'}
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

local ROOT="mir_research_browser"
local INTERFACE="more-infinite-research-browser"
local MARKER="mir-fixture-browser-personal-continuity-config-marker"
local FINITE="mir-browser-personal-finite"
local INFINITE="mir-browser-personal-infinite"
local OUTPUT="browser-personal-state"
local SAVE_DELAY_TICKS=180
local session_complete=false

local function check(value,message) if not value then error("browser personal-state fixture: "..message) end end
local function scalar(value)
  if value==nil then return "<nil>" end
  if type(value)=="boolean" then return value and "true" or "false" end
  if type(value)=="number" then return string.format("%.17g",value) end
  return tostring(value)
end
local function technology_line(name,technology)
  return table.concat({name,scalar(technology.enabled),scalar(technology.researched),scalar(technology.level),scalar(technology.visible_when_disabled),scalar(technology.saved_progress)},"\31")
end
local function queue_names(force)
  local names={}; for _,technology in ipairs(force.research_queue or {}) do names[#names+1]=technology.name end; return table.concat(names,"\30")
end
local function fixture_force_snapshot(force)
  local lines={}; for _,name in ipairs({FINITE,INFINITE}) do lines[#lines+1]=technology_line(name,force.technologies[name]) end
  lines[#lines+1]="current="..(force.current_research and force.current_research.name or "<nil>")
  lines[#lines+1]="progress="..scalar(force.research_progress)
  lines[#lines+1]="queue="..queue_names(force)
  return table.concat(lines,"\n")
end
local function active_force_snapshot(force)
  local lines={}; for name,technology in pairs(force.technologies) do lines[#lines+1]=technology_line(name,technology) end; table.sort(lines)
  lines[#lines+1]="current="..(force.current_research and force.current_research.name or "<nil>")
  lines[#lines+1]="progress="..scalar(force.research_progress)
  lines[#lines+1]="queue="..queue_names(force)
  return table.concat(lines,"\n")
end
local function fixture_force_facts(force)
  local technologies={}; for _,name in ipairs({FINITE,INFINITE}) do local t=force.technologies[name]; technologies[name]={enabled=t.enabled,researched=t.researched,level=scalar(t.level),visible_when_disabled=t.visible_when_disabled,saved_progress=scalar(t.saved_progress)} end
  local queue={}; for _,technology in ipairs(force.research_queue or {}) do queue[#queue+1]=technology.name end
  return {technologies=technologies,current_research=force.current_research and force.current_research.name or "<nil>",research_progress=force.research_progress,research_queue=queue}
end
local function frame_for(player) local frame=player.gui.screen[ROOT]; check(frame and frame.valid,"native browser frame missing for player "..player.index); return frame end
local function result_body(frame)
  local found=nil; for _,child in pairs(frame.children) do if child.valid and child.type=="scroll-pane" then check(found==nil,"browser frame has multiple direct result scroll panes"); found=child end end
  check(found~=nil,"browser frame has no direct result scroll pane"); return found
end
local function direct_result_row_present(body,name)
  for _,child in pairs(body.children) do if child.valid and child.tags and child.tags.mir_browser=="select" and child.tags.technology==name then return true end end; return false
end
local function direct_result_names(body)
  local names={}; for _,child in pairs(body.children) do if child.valid and child.tags and child.tags.mir_browser=="select" and type(child.tags.technology)=="string" then names[#names+1]=child.tags.technology end end; table.sort(names); return table.concat(names,"\30")
end
local function find_tagged(element,action,name)
  if element.valid and element.tags and element.tags.mir_browser==action and (name==nil or element.tags.technology==name) then return element end
  for _,child in pairs(element.children) do local found=find_tagged(child,action,name); if found then return found end end
  return nil
end
local function locale_key(value) check(type(value)=="table" and #value==1 and type(value[1])=="string","GUI caption is not an exact one-key LocalisedString"); return value[1] end
local function browser_facts(player)
  local frame=frame_for(player); local body=result_body(frame); local mode=find_tagged(frame,"mode"); local toggle=find_tagged(frame,"toggle-hide",INFINITE)
  check(mode and mode.valid and mode.type=="drop-down","native mode drop-down missing"); check(toggle and toggle.valid and toggle.type=="button","native hide/show toggle missing")
  return {index=player.index,username=player.name,force_index=player.force.index,mode_selected_index=mode.selected_index,main_row_present=direct_result_row_present(body,INFINITE),toggle_caption_key=locale_key(toggle.caption)}
end
local function expected_view(facts,mode,row,key,label) check(facts.mode_selected_index==mode,label.." mode changed"); check(facts.main_row_present==row,label.." direct main result row changed"); check(facts.toggle_caption_key==key,label.." toggle LocalisedString key changed") end
local function players_from_state(s)
  local a,b=game.get_player(s.player_a_index),game.get_player(s.player_b_index); check(a and a.connected,"player A is not connected"); check(b and b.connected,"player B is not connected"); check(a.name==s.player_a_username,"player A identity changed"); check(b.name==s.player_b_username,"player B identity changed"); return a,b
end
local function assert_shared_force(s,a,b,active)
  check(a.index~=b.index,"players share an index"); check(a.force.index==b.force.index,"players are not on the same force"); check(fixture_force_snapshot(a.force)==s.expected_fixture_force,"fixture-owned technology/current/progress/queue snapshot changed")
  if active then check(active_force_snapshot(a.force)==s.expected_active_force,"full active force technology/current/progress/queue snapshot changed") end
end
local function write_result(stage,body) body.schema=1; body.stage=stage; body.fixture_technology_names={finite=FINITE,infinite=INFINITE,queued=INFINITE}; helpers.write_file(OUTPUT.."/"..stage..".json",helpers.table_to_json(body),false) end
local function arm_save(s,next_phase,save_name) s.phase=next_phase.."-save-pending"; s.next_phase=next_phase; s.save_name=save_name; s.save_after_tick=game.tick+SAVE_DELAY_TICKS end
local function run_open(player,options) check(remote.call(INTERFACE,"open",player.index,options)==true,"production browser host rejected options for player "..player.index) end
local function malformed_hidden_negatives(s,a,b)
  local before=browser_facts(a); run_open(a,{hidden={[2]=INFINITE}}); local sparse=browser_facts(a); run_open(a,{hidden={INFINITE,INFINITE}}); local duplicate=browser_facts(a); run_open(a,{hidden={"no-such-technology"}}); local unknown=browser_facts(a)
  for label,facts in pairs({sparse=sparse,duplicate=duplicate,unknown=unknown}) do check(facts.main_row_present==before.main_row_present and facts.toggle_caption_key==before.toggle_caption_key,"malformed hidden input mutated prior view: "..label) end
  assert_shared_force(s,a,b,true); return {sparse_rejected_without_mutation=true,duplicate_rejected_without_mutation=true,unknown_rejected_without_mutation=true}
end
local function invalid_hidden_page_negative(s,a,b)
  run_open(a,{tab="research",search="",mode=1,status=1,selected=INFINITE,hidden={},page=1}); local first=direct_result_names(result_body(frame_for(a)))
  run_open(a,{page=2}); local second=direct_result_names(result_body(frame_for(a)))
  check(first~="" and second~="" and first~=second,"fixture could not distinguish browser page one from page two")
  run_open(a,{hidden={[2]=FINITE}}); local after=direct_result_names(result_body(frame_for(a)))
  check(after==second,"invalid hidden-only input changed page-two direct results"); assert_shared_force(s,a,b,true)
  run_open(a,{page=0}); local after_invalid_page=direct_result_names(result_body(frame_for(a)))
  check(after_invalid_page==second,"invalid page input changed page-two direct results")
  return {requested_page=2,page_one_rows_differ=true,sparse_hidden_preserved_page_rows=true,invalid_page_preserved_page_rows=true}
end
local function unqueued_hidden_recovery(s,a,b)
  local hidden_name=FINITE
  local selected_name=INFINITE
  local hidden_is_queued=false
  for _,technology in ipairs(a.force.research_queue or {}) do if technology.name==hidden_name then hidden_is_queued=true end end
  check(not hidden_is_queued,"hidden recovery fixture technology is queued")
  run_open(a,{tab="research",search=hidden_name,mode=1,status=1,selected=selected_name,hidden={hidden_name},page=1})
  local frame=frame_for(a)
  local body=result_body(frame)
  local row_while_hidden=direct_result_row_present(body,hidden_name)
  check(not row_while_hidden,"unqueued hidden technology remains in direct results")
  local selected_toggle=find_tagged(frame,"toggle-hide",selected_name)
  check(selected_toggle and selected_toggle.valid,"selected different technology is not rendered after hidden-row navigation")
  local recovery=find_tagged(frame,"show-hidden")
  check(recovery and recovery.valid and recovery.type=="button","bounded native hidden recovery action is absent after navigation")
  local caption_key=locale_key(recovery.caption)
  check(caption_key=="mir-browser.show-hidden","hidden recovery action LocalisedString key differs")
  assert_shared_force(s,a,b,true)
  run_open(a,{hidden={}})
  local shown_frame=frame_for(a)
  local shown_body=result_body(shown_frame)
  local row_after_clear=direct_result_row_present(shown_body,hidden_name)
  check(row_after_clear,"unqueued hidden technology direct row did not return after valid state clear")
  check(find_tagged(shown_frame,"show-hidden")==nil,"hidden recovery action remains after valid state clear")
  assert_shared_force(s,a,b,true)
  return {hidden_technology=hidden_name,selected_technology=selected_name,hidden_technology_is_queued=false,direct_row_present_while_hidden=false,recovery_action_present_after_navigation=true,recovery_caption_key=caption_key,direct_row_present_after_clear=true}
end
local function initial_action(s,a,b)
  run_open(a,{tab="research",search=INFINITE,mode=1,status=1,selected=INFINITE,hidden={INFINITE}}); local ah=browser_facts(a); expected_view(ah,1,false,"mir-browser.show","player A hidden view"); assert_shared_force(s,a,b,true)
  local malformed=malformed_hidden_negatives(s,a,b)
  local invalid_page=invalid_hidden_page_negative(s,a,b)
  local recovery=unqueued_hidden_recovery(s,a,b)
  run_open(a,{tab="research",search=INFINITE,mode=1,status=1,selected=INFINITE,hidden={},page=1}); local shown=browser_facts(a); expected_view(shown,1,true,"mir-browser.hide","player A shown roundtrip"); assert_shared_force(s,a,b,true)
  run_open(a,{tab="research",search=INFINITE,mode=1,status=1,selected=INFINITE,hidden={INFINITE},page=1}); local af=browser_facts(a); expected_view(af,1,false,"mir-browser.show","player A restored hidden view")
  run_open(b,{tab="research",search=INFINITE,mode=3,status=4,selected=INFINITE,hidden={},page=1}); local bf=browser_facts(b); expected_view(bf,3,true,"mir-browser.hide","player B visible view"); assert_shared_force(s,a,b,true)
  write_result("initial",{player_a=af,player_b=bf,same_force=true,malformed_hidden=malformed,invalid_hidden_page_preservation=invalid_page,hidden_recovery=recovery,valid_replacement_show_roundtrip=true,active_full_force_snapshot_unchanged=true,fixture_owned_force_queue_unchanged=true,fixture_force=fixture_force_facts(a.force)})
  arm_save(s,"await-save-reload","mir-browser-personal-state-continuity")
end
local function persistent_action(s,stage,a,b)
  run_open(a,nil); run_open(b,nil); local af,bf=browser_facts(a),browser_facts(b); expected_view(af,1,false,"mir-browser.show","player A persisted view"); expected_view(bf,3,true,"mir-browser.hide","player B persisted view"); assert_shared_force(s,a,b,true)
  write_result(stage,{player_a=af,player_b=bf,same_force=true,active_full_force_snapshot_unchanged=true,fixture_owned_force_queue_unchanged=true,fixture_force=fixture_force_facts(a.force)})
end
local function removal_action(s,a,b)
  assert_shared_force(s,a,b,false); check(remote.interfaces[INTERFACE]==nil,"removed MIR interface remains callable"); local af,bf=a.gui.screen[ROOT],b.gui.screen[ROOT]
  write_result("removal",{player_a={index=a.index,username=a.name,force_index=a.force.index,frame_still_present=af and af.valid or false},player_b={index=b.index,username=b.name,force_index=b.force.index,frame_still_present=bf and bf.valid or false},same_force=true,browser_interface_present=false,personal_state_readability="unavailable-removed-owner-no-interface",removal_disposition="before-after-recorded-no-arbitrary-rollback-claim",fixture_owned_force_queue_unchanged_during_removal=true,fixture_force=fixture_force_facts(a.force)})
  arm_save(s,"await-readd","mir-browser-personal-state-continuity-readd")
end
local function readd_action(s,a,b)
  check(remote.interfaces[INTERFACE]~=nil,"re-added MIR interface is absent"); run_open(a,{tab="research",selected=INFINITE}); run_open(b,{tab="research",selected=INFINITE}); local af,bf=browser_facts(a),browser_facts(b); assert_shared_force(s,a,b,false)
  write_result("readd",{player_a=af,player_b=bf,same_force=true,browser_interface_present=true,personal_state_disposition="observed-after-owner-readd-not-arbitrary-rollback-claim",fixture_owned_force_queue_unchanged_during_removal=true,fixture_force=fixture_force_facts(a.force)}); s.phase="complete"
end
local function initialise(force)
  local finite,infinite=force.technologies[FINITE],force.technologies[INFINITE]; check(finite and infinite,"fixture technologies are absent"); check(force.technologies["automation"],"automation technology is absent"); force.technologies["automation"].researched=true; finite.researched=false; infinite.researched=false; force.research_queue={infinite}; check(force.current_research and force.current_research.name==INFINITE,"fixture infinite technology was not queued as current research"); force.research_progress=0.42
  storage.browser_personal_state={phase="await-initial",expected_fixture_force=fixture_force_snapshot(force),expected_active_force=active_force_snapshot(force)}
end
script.on_init(function() initialise(game.forces.player) end)
script.on_configuration_changed(function(event)
  local s=storage.browser_personal_state; if not s then return end; local marker=event.mod_changes[MARKER]; local mir=event.mod_changes["more-infinite-research"]
  if s.phase=="await-configuration-change" and marker and marker.old_version==nil and marker.new_version~=nil then s.phase="configuration-change-ready"
  elseif s.phase=="await-removal" and mir and mir.old_version~=nil and mir.new_version==nil then s.phase="removal-ready"
  elseif s.phase=="await-readd" and mir and mir.old_version==nil and mir.new_version~=nil then s.phase="readd-ready" end
end)
script.on_event(defines.events.on_tick,function()
  if session_complete then return end; local s=storage.browser_personal_state; if not s or s.phase=="complete" then return end
  if s.save_after_tick and game.tick>=s.save_after_tick then local next_phase,save_name=s.next_phase,s.save_name; s.save_after_tick,s.next_phase,s.save_name=nil,nil,nil; s.phase=next_phase; game.auto_save(save_name); session_complete=true; return end
  if s.phase=="await-initial" then
    if #game.connected_players~=2 then return end; local players={}; for _,player in ipairs(game.connected_players) do players[#players+1]=player end; table.sort(players,function(left,right) return left.index<right.index end); check(players[1].name~=players[2].name,"client usernames are not distinct"); s.player_a_index,s.player_b_index=players[1].index,players[2].index; s.player_a_username,s.player_b_username=players[1].name,players[2].name; initial_action(s,players[1],players[2]); return
  end
  local a,b=game.get_player(s.player_a_index),game.get_player(s.player_b_index); if not (a and a.connected and b and b.connected) then return end; a,b=players_from_state(s)
  if s.phase=="await-save-reload" then persistent_action(s,"save-reload",a,b); arm_save(s,"await-configuration-change","mir-browser-personal-state-continuity-configuration")
  elseif s.phase=="configuration-change-ready" then persistent_action(s,"configuration-change",a,b); arm_save(s,"await-removal","mir-browser-personal-state-continuity-removal")
  elseif s.phase=="removal-ready" then removal_action(s,a,b)
  elseif s.phase=="readd-ready" then readd_action(s,a,b) end
end)

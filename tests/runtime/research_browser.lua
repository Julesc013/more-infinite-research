local function snapshot(force)
  local rows = {}
  for name, tech in pairs(force.technologies) do
    rows[name] = {enabled=tech.enabled, researched=tech.researched, level=tech.level, progress=tech.saved_progress, visible=tech.visible_when_disabled}
  end
  local queue = {}; for _, tech in ipairs(force.research_queue or {}) do queue[#queue+1]=tech.name end
  return helpers.table_to_json{technologies=rows,queue=queue,progress=force.research_progress}
end
script.on_nth_tick(1,function()
  local count=0
  local function check(value,message) assert(value,message); count=count+1 end
  local force=game.forces.player
  if storage.browser_saved then
    check(snapshot(force)==storage.expected_force,"save/reload retains partial research and queue")
    for _, actual in pairs(game.players) do
      check(remote.call("more-infinite-research-browser","open",actual.index),"saved personal view reopens")
      check(snapshot(force)==storage.expected_force,"reopened GUI retains force state")
    end
    helpers.write_file("browser-reload.json",helpers.table_to_json{status="passed",assertions=count,engine=helpers.game_version,scope="native-single-player-save-reload-with-partial-research"},false)
    script.on_nth_tick(1,nil);return
  end
  check(force.add_research("mir-browser-progress"),"initial queue")
  force.research_progress=0.375
  local before=snapshot(force)
  local catalogue={"mir-browser-test-finite","mir-browser-test-infinite"}
  local finite={mode=2,status=1,page=1,search="mir-browser-test"}
  local infinite={mode=3,status=1,page=1,search="mir-browser-test"}
  local a=browser_model.page(catalogue,force,finite,{},{})
  local b=browser_model.page(catalogue,force,infinite,{},{})
  check(#a.rows==1 and a.rows[1]==catalogue[1],"finite personal filter")
  check(#b.rows==1 and b.rows[1]==catalogue[2],"infinite personal filter")
  check(before==snapshot(force),"personal filters changed force state")
  check(finite.mode==2 and infinite.mode==3,"view states not isolated")
  local capped=browser_model.page(catalogue,force,finite,{[catalogue[2]]=3},{})
  check(#capped.rows==2,"effective MIR cap classification")
  local literal=browser_model.page(catalogue,force,{mode=1,status=1,page=1,search="%["},{},{})
  check(#literal.rows==0,"literal search")
  local player={valid=true,force=force,permission_group={allows_action=function() return false end}}
  local tech=force.technologies[catalogue[1]]
  check(not browser_model.can_enqueue(player,tech,defines.input_action.start_research),"permission negative")
  player.permission_group=nil
  check(browser_model.can_enqueue(player,tech,defines.input_action.start_research),"available research")
  player.force=game.forces.enemy
  check(not browser_model.can_enqueue(player,tech,defines.input_action.start_research),"cross-force negative")
  player.force=force
  check(not browser_model.can_enqueue(player,force.current_research,defines.input_action.start_research),"duplicate queue negative")
  check(before==snapshot(force),"predicates changed research state")
  local many={}
  for name in pairs(force.technologies) do many[#many+1]=name end
  table.sort(many)
  local all=browser_model.page(many,force,{mode=1,status=1,page=999999,search=""},{},{})
  check(#all.rows<=browser_model.page_size and all.page==all.pages,"bounded page clamp")
  local native_players=0
  for _, actual in pairs(game.players) do
    native_players=native_players+1
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=2,search="mir-browser-test"}),"native finite GUI")
    check(actual.gui.screen.mir_research_browser.valid,"native frame valid")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=3,search="mir-browser-test"}),"native infinite GUI")
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="settings",search="mir-"}),"native settings GUI")
    check(before==snapshot(force),"native GUI force noninterference")
  end
  helpers.write_file("browser-test.json",helpers.table_to_json{status="passed",assertions=count,scope="exact-package-load-and-controlled-personal-view-model-on-real-force; native-two-client-GUI-not-qualified",native_players=native_players,engine=helpers.game_version},false)
  storage.browser_saved=true;storage.expected_force=before
  if native_players>0 then game.auto_save("mir-browser-acceptance") end
  script.on_nth_tick(1,nil)
end)

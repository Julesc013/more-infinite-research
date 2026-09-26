local function snapshot(force)
  local rows = {}
  for name, tech in pairs(force.technologies) do
    rows[name] = {enabled=tech.enabled, researched=tech.researched, level=tech.level, progress=tech.saved_progress, visible=tech.visible_when_disabled}
  end
  local queue = {}; for _, tech in ipairs(force.research_queue or {}) do queue[#queue+1]=tech.name end
  return helpers.table_to_json{technologies=rows,queue=queue,progress=force.research_progress}
end
local function find_browser_element(element, tag, value)
  if not (element and element.valid) then return nil end
  if element.tags and element.tags[tag] == value then return element end
  -- LuaGuiElement.children is a Factorio custom table. Traverse its keyed
  -- values so labelled flows remain transparent to fixture assertions.
  for _, child in pairs(element.children or {}) do
    local found = find_browser_element(child, tag, value)
    if found then return found end
  end
  return nil
end
local function has_browser_fact(element, fact)
  return find_browser_element(element, "mir_browser_fact", fact) ~= nil
end
local function has_numeric_browser_fact(element, fact, captions)
  local value = find_browser_element(element, "mir_browser_fact", fact)
  local caption = value and value.caption
  local argument_count = type(caption) == "table" and captions[caption[1]]
  if not argument_count then return false end
  for index = 2, argument_count + 1 do
    if tonumber(caption[index]) == nil then return false end
  end
  return true
end
local function emitted_productivity_technology(player)
  local names = {}
  for name, technology in pairs(player.force.technologies) do
    for _, effect in pairs(technology.prototype.effects or {}) do
      if effect.type == "change-recipe-productivity" then
        names[#names + 1] = name
        break
      end
    end
  end
  table.sort(names)
  -- A native productivity technology may belong to the base game. Render each
  -- candidate in MIR scope and retain only the provider-recognized detail.
  for _, name in ipairs(names) do
    if remote.call("more-infinite-research-browser","open",player.index,{tab="research",family="mir",mode=1,sort="progression",selected=name,search=""}) then
      local root = player.gui.screen.mir_research_browser
      if has_browser_fact(root,"productivity_increment") and has_browser_fact(root,"productivity_current_cap") then return name end
    end
  end
  return nil
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
  local catalogue=browser_catalogue.snapshot(force)
  local shortcut=prototypes.shortcut["mir-research-browser"]
  check(shortcut and shortcut.action=="lua" and shortcut.toggleable,"toggleable native browser shortcut")
  local ordering={schema=1,rows={
    {key="later",available=true,researched=false,queued=false,infinite=false,native_order="a",progression=2},
    {key="earlier",available=true,researched=false,queued=false,infinite=false,native_order="z",progression=1}
  }}
  local progression=browser_core.query(ordering,{mode=1,status=1,page=1,search="",sort="progression"})
  local native=browser_core.query(ordering,{mode=1,status=1,page=1,search="",sort="native"})
  check(progression.rows[1].key=="earlier" and native.rows[1].key=="later","progression and native ordering")
  local mir_focus=browser_core.query(catalogue,{mode=1,status=1,page=1,search="mir-browser-test",family="mir"},{schema=1,families={ ["mir-browser-test-finite"]="productivity"}})
  check(#mir_focus.rows==1 and mir_focus.rows[1].key=="mir-browser-test-finite","MIR-focused default family contract")
  local without_mir=browser_core.family_names(nil)
  check(#without_mir==2 and without_mir[1]=="all" and without_mir[2]=="external","provider absence keeps the portable catalogue available")
  local unbounded_productivity={
    schema=2,
    kind="portable-research-enrichment",
    caps={},
    families={["mir-browser-test-finite"]="productivity"},
    details={["mir-browser-test-finite"]={
      schema=1,
      family="productivity",
      action="emit",
      owner={technology_id="mir-browser-test-finite",stream_id="productivity",action="emit",reason="fixture",affected_recipe_ids={"mir-browser-recipe"}},
      compiler_disposition={inclusion="included",action="emit",reason="fixture",route_exclusions={state="no-additional-route-exclusions-published-for-current-row",recipe_ids={}}},
      final_science={rationale="fixture",ingredients={{name="automation-science-pack",amount=1}}},
      current_level=1,
      recipe_benefits={{recipe_id="mir-browser-recipe",effect_change=0.02,current_productivity_bonus=0,maximum_productivity=3,next_level_has_effective_benefit=true}},
      next_level_eligible=true,
      next_level_has_effective_benefit=true
    }}
  }
  local unbounded_detail=browser_core.detail(catalogue,"mir-browser-test-finite",unbounded_productivity)
  check(unbounded_detail and unbounded_detail.enrichment and unbounded_detail.enrichment.effective_cap==nil
    and unbounded_detail.enrichment.next_level_eligible==true
    and unbounded_detail.enrichment.recipe_benefits[1].maximum_productivity==3,"unbounded MIR productivity detail remains provider-visible")
  local capped_productivity=helpers.json_to_table(helpers.table_to_json(unbounded_productivity))
  local capped_detail=capped_productivity.details["mir-browser-test-finite"]
  capped_productivity.caps["mir-browser-test-finite"]=3
  capped_detail.effective_cap=3
  capped_detail.settings={
    maximum_level={name="ips-max-level-productivity",default=3,raw_direct=3,effective=3,source="direct",changed=false,changed_from_default=false,restart_required=true},
    enabled={name="ips-enable-productivity",default=true,raw_direct=true,effective=true,source="direct",changed=false,changed_from_default=false,restart_required=true}
  }
  capped_detail.current_level=4
  check(browser_core.normalize_enrichment(capped_productivity)==nil,"explicit eligibility above the finite cap is rejected")
  capped_detail.current_level=3
  capped_detail.next_level_eligible=false
  capped_detail.next_level_has_effective_benefit=false
  capped_detail.recipe_benefits[1].next_level_has_effective_benefit=false
  check(browser_core.normalize_enrichment(capped_productivity)~=nil,"explicit unavailable state inside the finite cap stays accepted")
  capped_detail.next_level_eligible=nil
  capped_detail.next_level_has_effective_benefit=true
  capped_detail.recipe_benefits[1].next_level_has_effective_benefit=true
  check(browser_core.normalize_enrichment(capped_productivity)~=nil,"legacy finite provider retains cap-derived eligibility")
  local finite={mode=2,status=1,page=1,search="mir-browser-test"}
  local infinite={mode=3,status=1,page=1,search="mir-browser-test"}
  local a=browser_core.query(catalogue,finite)
  local b=browser_core.query(catalogue,infinite)
  check(#a.rows==1 and a.rows[1].key=="mir-browser-test-finite","finite personal filter")
  check(#b.rows==1 and b.rows[1].key=="mir-browser-test-infinite","infinite personal filter")
  check(before==snapshot(force),"personal filters changed force state")
  check(finite.mode==2 and infinite.mode==3,"view states not isolated")
  local capped=browser_core.query(catalogue,finite,{schema=1,caps={["mir-browser-test-infinite"]=3}})
  check(#capped.rows==2,"effective MIR cap classification")
  local literal=browser_core.query(catalogue,{mode=1,status=1,page=1,search="%["})
  check(#literal.rows==0,"literal search")
  local localized=browser_core.query(catalogue,{mode=1,status=1,page=1,search="localized finite"},nil,{["mir-browser-test-finite"]="Localized finite technology"})
  check(#localized.rows==1 and localized.rows[1].key=="mir-browser-test-finite","localized search with stable-ID fallback")
  local descending=browser_core.query(catalogue,{mode=1,status=1,page=1,sort="name-desc",search="mir-browser-test"})
  check(#descending.rows==2 and descending.rows[1].key=="mir-browser-test-infinite","descending deterministic sort")
  local player={valid=true,force=force,permission_group={allows_action=function() return false end}}
  local tech=force.technologies["mir-browser-test-finite"]
  check(not browser_actions.can_enqueue(player,tech,defines.input_action.start_research),"permission negative")
  player.permission_group=nil
  check(browser_actions.can_enqueue(player,tech,defines.input_action.start_research),"available research")
  player.force=game.forces.enemy
  check(not browser_actions.can_enqueue(player,tech,defines.input_action.start_research),"cross-force negative")
  player.force=force
  check(not browser_actions.can_enqueue(player,force.current_research,defines.input_action.start_research),"duplicate queue negative")
  check(before==snapshot(force),"predicates changed research state")
  local queued_before=browser_core.query(catalogue,{mode=1,status=4,page=1,search="mir-browser-test-finite"})
  check(#queued_before.rows==0,"initial snapshot excludes unqueued research")
  check(force.add_research("mir-browser-test-finite"),"queue mutation")
  local refreshed_catalogue=browser_catalogue.snapshot(force)
  local queued_after=browser_core.query(refreshed_catalogue,{mode=1,status=4,page=1,search="mir-browser-test-finite"})
  check(#queued_after.rows==1 and queued_after.rows[1].queued,"second snapshot exposes queued research")
  before=snapshot(force)
  local all=browser_core.query(catalogue,{mode=1,status=1,page=999999,search=""})
  check(#all.rows<=browser_core.page_size and all.page==all.pages,"bounded page clamp")
  local native_players=0
  for _, actual in pairs(game.players) do
    native_players=native_players+1
    check(not actual.gui.top.mir_browser_open,"legacy top launcher absent")
    check(remote.call("more-infinite-research-browser","open",actual.index),"native default MIR browser GUI")
    local default_root=actual.gui.screen.mir_research_browser
    local default_sort=find_browser_element(default_root,"mir_browser","sort")
    local default_scope=find_browser_element(default_root,"mir_browser","family")
    check(default_sort and default_sort.type=="drop-down" and default_sort.selected_index==1,"new personal view defaults to MIR progression")
    check(default_scope and default_scope.type=="drop-down" and default_scope.selected_index==1,"new personal view defaults to MIR scope")
    check(remote.call("more-infinite-research-browser","open",actual.index,{selected="automation"}),"native MIR scope opens with external selection")
    check(not find_browser_element(actual.gui.screen.mir_research_browser,"mir_browser","open-vanilla"),"MIR scope clears stale external selection")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=2,search="mir-browser-test"}),"native finite GUI")
    check(actual.gui.screen.mir_research_browser.valid,"native frame valid")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=3,search="mir-browser-test"}),"native infinite GUI")
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="settings",search="mir-"}),"native settings GUI")
    check(has_browser_fact(actual.gui.screen.mir_research_browser,"profile_import"),"native settings profile summary")
    local mir_productivity = emitted_productivity_technology(actual)
    check(mir_productivity,"native fixture supplies an emitted MIR productivity technology")
    -- This opens a technology carrying a live productivity effect inside MIR
    -- scope. The provider-recognition pass rejects base-game productivity
    -- effects, so the numeric facts below exercise its Factorio recipe values.
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="research",family="mir",mode=1,sort="progression",selected=mir_productivity,search=""}),"native MIR productivity detail GUI")
    local mir_root=actual.gui.screen.mir_research_browser
    check(has_browser_fact(mir_root,"productivity_increment"),"native MIR productivity increment detail")
    check(has_browser_fact(mir_root,"productivity_current_cap"),"native MIR productivity current-limit detail")
    check(has_numeric_browser_fact(mir_root,"productivity_increment",{
      ["mir-browser.productivity-increment"]=1,
      ["mir-browser.productivity-increment-range"]=2
    }),"native MIR provider supplies numerical productivity increment")
    check(has_numeric_browser_fact(mir_root,"productivity_current_cap",{
      ["mir-browser.productivity-current-cap"]=2,
      ["mir-browser.productivity-current-cap-range"]=4
    }),"native MIR provider supplies numerical productivity current limit")
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="research",family="all",mode=1,sort="name-desc",selected="mir-browser-test-finite",search="mir-browser-test"}),"native sorted technology detail GUI")
    local root=actual.gui.screen.mir_research_browser
    local sort_control=find_browser_element(root,"mir_browser","sort")
    check(sort_control and sort_control.type=="drop-down","native sort control")
    local vanilla_link=find_browser_element(root,"mir_browser","open-vanilla")
    check(vanilla_link and vanilla_link.type=="button","native technology link")
    check(has_browser_fact(root,"research_cost"),"native current research cost detail")
    local all_scope=find_browser_element(root,"mir_browser","family")
    check(all_scope and all_scope.type=="drop-down","native all-research scope control")
    local all_scope_index=all_scope.selected_index
    check(remote.call("more-infinite-research-browser","open",actual.index,{family="not-a-browser-family"}),"invalid family request leaves browser open")
    local preserved_scope=find_browser_element(actual.gui.screen.mir_research_browser,"mir_browser","family")
    check(preserved_scope and preserved_scope.selected_index==all_scope_index,"invalid family preserves personal scope")
    check(before==snapshot(force),"native GUI force noninterference")
  end
  helpers.write_file("browser-test.json",helpers.table_to_json{status="passed",assertions=count,scope="exact-package-load-and-controlled-personal-view-model-on-real-force; native-two-client-GUI-not-qualified",native_players=native_players,engine=helpers.game_version},false)
  storage.browser_saved=true;storage.expected_force=before
  if native_players>0 then game.auto_save("mir-browser-acceptance") end
  script.on_nth_tick(1,nil)
end)

-- Pure query regression; accepts the canonical core supplied by the runner.
local function check_browser_sorting(browser_core)
  local queries = 0
  local function ordered(rows, descending)
    for index = 2, #rows do
      local previous, current = rows[index - 1].key, rows[index].key
      assert(descending and previous >= current or not descending and previous <= current,
        "research browser order is inconsistent")
    end
  end
  local function query(rows, direction, page, hidden)
    local original = {}
    for index, row in ipairs(rows) do original[index] = row.key end
    local result = assert(browser_core.query({schema = 1, rows = rows},
      {sort = direction, page = page or 1, hidden = hidden}))
    queries = queries + 1
    ordered(result.rows, direction == "name-desc")
    for index, row in ipairs(rows) do
      assert(row.key == original[index], "query mutated the source catalogue")
    end
    return result
  end
  local keys = {"alpha", "beta", "gamma", "omega"}
  local permutations = 0
  local function permute(index)
    if index > #keys then
      permutations = permutations + 1
      local rows = {}
      for i, key in ipairs(keys) do rows[i] = {key = key} end
      for _, direction in ipairs({"name-asc", "name-desc"}) do
        local result = query(rows, direction)
        assert(result.count == 4 and #result.rows == 4, "sort lost a technology")
        local expected = direction == "name-desc" and "omega,gamma,beta,alpha" or "alpha,beta,gamma,omega"
        local actual = {}; for i, row in ipairs(result.rows) do actual[i] = row.key end
        assert(table.concat(actual, ",") == expected, "sort depends on input order")
      end
      return
    end
    for i = index, #keys do
      keys[index], keys[i] = keys[i], keys[index]
      permute(index + 1)
      keys[index], keys[i] = keys[i], keys[index]
    end
  end
  permute(1)
  for _, direction in ipairs({"name-asc", "name-desc"}) do
    query({}, direction)
    query({{key="only"}}, direction)
    local duplicate = query({{key="b"},{key="a"},{key="b"},{key="a"}}, direction)
    assert(duplicate.count == 4, "sort lost equal keys")
    local rows = {}
    -- Coprime permutation exercises cross-page order without RNG dependence.
    for i = 1, 61 do rows[i] = {key = string.format("tech-%03d", (i * 17) % 61)} end
    local seen, previous, count = {}, nil, 0
    for page = 1, 4 do
      local result = query(rows, direction, page)
      assert(result.count == 61 and result.pages == 4, "pagination count changed")
      for _, row in ipairs(result.rows) do
        assert(not seen[row.key], "technology repeated between pages")
        if previous then
          assert(direction == "name-desc" and previous > row.key
            or direction == "name-asc" and previous < row.key, "page boundary order changed")
        end
        seen[row.key], previous, count = true, row.key, count + 1
      end
    end
    assert(count == 61, "pagination lost a technology")
    local hidden = query(rows, direction, 1, {["tech-030"] = true})
    assert(hidden.count == 60, "personal hide count changed")
    for _, row in ipairs(hidden.rows) do assert(row.key ~= "tech-030", "hidden row retained") end
  end
  return {queries = queries, permutations = permutations}
end

local function snapshot(force)
  local rows = {}
  for name, tech in pairs(force.technologies) do
    rows[name] = {enabled=tech.enabled, researched=tech.researched, level=tech.level, progress=tech.saved_progress, visible=tech.visible_when_disabled}
  end
  local queue = {}; for _, tech in ipairs(force.research_queue or {}) do queue[#queue+1]=tech.name end
  return helpers.table_to_json{technologies=rows,queue=queue,progress=force.research_progress}
end
local function has_browser_action(element, action)
  if element.tags and element.tags.mir_browser == action then return true end
  for _, child in ipairs(element.children or {}) do
    if has_browser_action(child, action) then return true end
  end
  return false
end
local function has_browser_fact(element, fact)
  if element.tags and element.tags.mir_browser_fact == fact then return true end
  for _, child in ipairs(element.children or {}) do
    if has_browser_fact(child, fact) then return true end
  end
  return false
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
  local sorting = check_browser_sorting(browser_core)
  check(sorting.queries == 64 and sorting.permutations == 24, "sorting regression coverage")
  check(force.add_research("mir-browser-progress"),"initial queue")
  force.research_progress=0.375
  local before=snapshot(force)
  local catalogue=browser_catalogue.snapshot(force)
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
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=2,search="mir-browser-test"}),"native finite GUI")
    check(actual.gui.screen.mir_research_browser.valid,"native frame valid")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=3,search="mir-browser-test"}),"native infinite GUI")
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="settings",search="mir-"}),"native settings GUI")
    check(has_browser_fact(actual.gui.screen.mir_research_browser,"profile_import"),"native settings profile summary")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=1,sort="name-desc",selected="mir-browser-test-finite"}),"native sorted technology detail GUI")
    local root=actual.gui.screen.mir_research_browser
    check(has_browser_action(root,"sort"),"native sort control")
    check(has_browser_action(root,"open-vanilla"),"native technology link")
    check(before==snapshot(force),"native GUI force noninterference")
  end
  helpers.write_file("browser-test.json",helpers.table_to_json{status="passed",assertions=count,scope="exact-package-load-and-controlled-personal-view-model-on-real-force; native-two-client-GUI-not-qualified",native_players=native_players,engine=helpers.game_version},false)
  storage.browser_saved=true;storage.expected_force=before
  if native_players>0 then game.auto_save("mir-browser-acceptance") end
  script.on_nth_tick(1,nil)
end)

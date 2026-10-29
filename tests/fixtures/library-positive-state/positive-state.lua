-- Disposable fixture contrasts only. No MIR imports, storage access or events.
local M = {}
local BROWSER = "more-infinite-research-browser"
local FOREIGN = "mir5-fixture-foreign-hidden-research"
local IDS = {
  "mir-legacy-module-credit-speed-module",
  "mir-legacy-module-credit-productivity-module",
  "mir-legacy-module-credit-efficiency-module",
  "mir-legacy-cannon-credit-rocket-shooting-speed",
}
local RECIPES = {"speed-module", "productivity-module", "efficiency-module"}
local function fail(message) error("[mir5-library-positive-state] " .. message) end
local function valid(value) return value ~= nil and value.valid ~= false end
local function close(a, b) return type(a) == "number" and math.abs(a - b) < .000001 end

function M.assert_credits(force)
  local holders, bonuses = {}, {}
  for index, id in ipairs(IDS) do
    local technology = force.technologies[id]
    if not valid(technology) or technology.level ~= index + 1 or technology.researched ~= false
        or technology.enabled ~= false or technology.visible_when_disabled ~= false
        or not valid(technology.prototype) or technology.prototype.hidden ~= true then
      fail("positive native holder changed: " .. id)
    end
    holders[id] = {level=technology.level, researched=false, enabled=false, visible_when_disabled=false}
  end
  for index, recipe in ipairs(RECIPES) do
    local value = force.recipes[recipe]
    if not valid(value) or not close(value.productivity_bonus, index * .01) then
      fail("positive module contribution changed: " .. recipe)
    end
    bonuses[recipe] = value.productivity_bonus
  end
  local cannon = force.get_gun_speed_modifier("cannon-shell")
  if not close(cannon, .4) then fail("positive cannon contribution changed") end
  local foreign = force.technologies[FOREIGN]
  if not valid(foreign) or foreign.level ~= 1 or foreign.researched ~= false or foreign.enabled ~= true
      or foreign.visible_when_disabled ~= false or not valid(foreign.prototype)
      or foreign.prototype.hidden ~= true then fail("foreign hidden technology changed") end
  return {holders=holders, module_productivity=bonuses, cannon_speed=cannon}
end

function M.seed(force)
  -- This mode is never admitted for an imported save. Require genuinely fresh
  -- native state before the four named fixture-owned assignments.
  for _, id in ipairs(IDS) do
    local technology = force.technologies[id]
    if not valid(technology) or technology.level ~= 1 or technology.researched ~= false
        or technology.enabled ~= false or technology.visible_when_disabled ~= false then
      fail("seed requires fresh zero-credit holder: " .. id)
    end
  end
  for _, recipe in ipairs(RECIPES) do
    if not valid(force.recipes[recipe]) or not close(force.recipes[recipe].productivity_bonus, 0) then
      fail("seed requires zero module productivity")
    end
  end
  if not close(force.get_gun_speed_modifier("cannon-shell"), 0) then fail("seed requires zero cannon speed") end
  for index, id in ipairs(IDS) do
    local technology = force.technologies[id]
    technology.level = index + 1
    technology.researched = false
    technology.enabled, technology.visible_when_disabled = false, false
  end
  force.reset_technology_effects()
  return M.assert_credits(force)
end

local function query(player, family, id, visibility, hidden)
  if remote.call(BROWSER, "open", player.index, {
    search=id, selected=id, family=family, visibility=visibility, hidden=hidden,
    sort="progression", tab="research",
  }) ~= true then fail("public browser query failed") end
end

local function assert_result(player, family, id, visibility, present)
  local root = player.gui.screen.mir_research_browser
  local filters = valid(root) and root.mir_library_filters
  local tabs = valid(root) and root.mir_library_tabs
  local content = valid(tabs) and tabs.mir_library_research_content
  local results = valid(content) and content.mir_library_results
  local detail = valid(content) and content.mir_library_detail
  local actions = valid(content) and content.mir_library_actions
  local button = valid(actions) and actions.mir_library_open_native
  local family_index = family == "all" and 2 or 3
  if not valid(filters) or not valid(filters.mir_library_query) or filters.mir_library_query.text ~= id
      or not valid(filters.mir_library_family) or filters.mir_library_family.selected_index ~= family_index
      or not valid(filters.mir_library_visibility) or filters.mir_library_visibility.selected_index ~= visibility
      or not valid(results) or not valid(detail) or not valid(button) then fail("query GUI differs") end
  if present then
    if #results.items ~= 1 or results.selected_index ~= 1 or not valid(detail.mir_library_detail_title)
        or button.enabled ~= true then fail("foreign hidden research was suppressed") end
  elseif #results.items ~= 0 or results.selected_index ~= 0 or valid(detail.mir_library_detail_title)
      or not valid(detail.mir_library_detail_empty) or button.enabled ~= false then
    fail("excluded research or native action exposed: " .. id)
  end
end

function M.prepare_restart(english, german)
  for index, player in ipairs({english, german}) do
    local id = index == 1 and "recipe-prod-research_gears-1" or "recipe-prod-research_mining_drill-1"
    if remote.call(BROWSER, "open", player.index, {
      search=id, selected=id, family="mir", visibility=1, tab="research",
      sort=index == 1 and "progression" or "native", hidden=index == 1 and {FOREIGN} or {},
    }) ~= true then fail("could not prepare distinct saved personal hidden filters") end
  end
end

function M.probe(english, german)
  M.assert_credits(english.force)
  -- Omit hidden here deliberately: observe the real persisted personal list
  -- before any replacement query can mask its loss during saved-host reload.
  for index, player in ipairs({english, german}) do
    query(player, "external", FOREIGN, 1, nil)
    assert_result(player, "external", FOREIGN, 1, index == 2)
  end
  local count = 0
  for _, player in ipairs({english, german}) do
    for _, family in ipairs({"all", "external"}) do
      -- Native prototype.hidden is not MIR's personal inspection filter.
      query(player, family, FOREIGN, 1, {})
      assert_result(player, family, FOREIGN, 1, true)
      query(player, family, FOREIGN, 1, {FOREIGN})
      assert_result(player, family, FOREIGN, 1, false)
      query(player, family, FOREIGN, 2, {FOREIGN})
      assert_result(player, family, FOREIGN, 2, true)
      count = count + 3
      for _, id in ipairs(IDS) do
        for _, visibility in ipairs({1, 2}) do
          query(player, family, id, visibility, {FOREIGN})
          assert_result(player, family, id, visibility, false)
          count = count + 1
        end
      end
    end
  end
  M.assert_credits(english.force)
  return count
end

function M.witness(state, completed)
  if state.positive_seeded ~= true then fail("positive seed witness is absent") end
  return {
    ownership="fixture-seeded-disposable-world", imported_earnings=false, seeded_once=true,
    native=M.assert_credits(game.forces.player),
    persisted_personal_hidden_checked=completed,
    foreign_inspection_queries=completed and state.positive_queries or 0,
  }
end
return M

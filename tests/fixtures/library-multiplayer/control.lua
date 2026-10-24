-- Private two-client Library scenario.  It only uses the shipped public
-- browser interface and native Lua objects; it neither imports MIR modules nor
-- reads MIR storage.
local KEY = "mir5_library_multiplayer"
local CASE = "library-multiplayer"
local RESTART_SAVE = "mir5-library-multiplayer-restart"
local FINAL_SAVE = "mir5-native-complete"
local BROWSER = "more-infinite-research-browser"

local ROOT = "mir_research_browser"
local FILTERS = "mir_library_filters"
local QUERY = "mir_library_query"
local SORT = "mir_library_sort"
local TABS = "mir_library_tabs"
local RESEARCH_CONTENT = "mir_library_research_content"
local RESULTS = "mir_library_results"
local DETAIL = "mir_library_detail"
local DETAIL_TITLE = "mir_library_detail_title"
local AVAILABILITY = {"mir_library_availability_1", "mir_library_availability_2"}
local AVAILABILITY_FAMILIES = {
  "research_agricultural_growth_speed",
  "research_spoilage_preservation",
}

local GEAR = "recipe-prod-research_gears-1"
local MINING = "recipe-prod-research_mining_drill-1"
local TECHNOLOGIES = {GEAR, MINING}
local RECIPES = {"iron-gear-wheel", "burner-mining-drill", "electric-mining-drill"}
local GEAR_PACKS = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
}
local GEAR_EFFECT = .10
local GEAR_LEVEL_AFTER_TWO_LABS = 3
local LAB_PACKS = 2
local LAB_ENERGY = 100000000
local LIVE_DEADLINE_TICKS = 3600
local FOREIGN_FORCE = "mir5-library-multiplayer-foreign"
local VIEWS = {
  en = {query=GEAR, selected=GEAR, sort="progression", sort_index=1},
  de = {query=MINING, selected=MINING, sort="native", sort_index=2},
}

local loaded_restart = false
local ready_logged = false

local function fail(message) error("[mir5-library-multiplayer] " .. message) end
local function valid(value) return value ~= nil and value.valid ~= false end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end

local function named(value)
  if type(value) == "string" then return value end
  return valid(value) and value.name or nil
end

local function copy_queue(force)
  local result = {}
  for index, technology in ipairs(force.research_queue or {}) do
    local name = named(technology)
    if not name then fail("native research queue contains an unnamed entry") end
    result[index] = name
  end
  return result
end

local function native_snapshot(force)
  if not valid(force) then fail("default player force is absent") end
  local technologies, recipes = {}, {}
  for _, name in ipairs(TECHNOLOGIES) do
    local technology = force.technologies[name]
    if not valid(technology) then fail("required native technology is absent: " .. name) end
    technologies[name] = {
      level=technology.level, researched=technology.researched, enabled=technology.enabled,
      visible_when_disabled=technology.visible_when_disabled,
    }
  end
  for _, name in ipairs(RECIPES) do
    local recipe = force.recipes[name]
    if not valid(recipe) then fail("required native recipe is absent: " .. name) end
    recipes[name] = recipe.productivity_bonus
  end
  return {
    force_index=force.index, technologies=technologies, recipes=recipes,
    queue=copy_queue(force), current=named(force.current_research), progress=force.research_progress,
  }
end

local function copy_snapshot(source)
  local result = {force_index=source.force_index, technologies={}, recipes={}, queue={}, current=source.current, progress=source.progress}
  for name, technology in pairs(source.technologies) do
    result.technologies[name] = {
      level=technology.level, researched=technology.researched, enabled=technology.enabled,
      visible_when_disabled=technology.visible_when_disabled,
    }
  end
  for name, bonus in pairs(source.recipes) do result.recipes[name] = bonus end
  for index, name in ipairs(source.queue) do result.queue[index] = name end
  return result
end

local function same_snapshot(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or left.force_index ~= right.force_index
      or left.current ~= right.current or not close(left.progress, right.progress) then return false end
  for _, name in ipairs(TECHNOLOGIES) do
    local a, b = left.technologies[name], right.technologies[name]
    if type(a) ~= "table" or type(b) ~= "table" or a.level ~= b.level or a.researched ~= b.researched
        or a.enabled ~= b.enabled or a.visible_when_disabled ~= b.visible_when_disabled then return false end
  end
  for _, name in ipairs(RECIPES) do if not close(left.recipes[name], right.recipes[name]) then return false end end
  if #left.queue ~= #right.queue then return false end
  for index, name in ipairs(left.queue) do if right.queue[index] ~= name then return false end end
  return true
end

local function assert_native(state, force)
  if not same_snapshot(state.native_initial, state.native_initial_guard) then
    fail("stored initial native witness was overwritten")
  end
  if state.native_after_lab and not same_snapshot(state.native_after_lab, state.native) then
    fail("stored post-lab native witness was overwritten")
  end
  if force.index ~= state.force_index then fail("client force differs from disposable world force") end
  if not same_snapshot(native_snapshot(force), state.native) then
    fail("public Library browsing mutated native research, queue, or recipe effects")
  end
end

local function open(player, view)
  if not (remote.interfaces and remote.interfaces[BROWSER]) then fail("shipped public browser interface is absent") end
  if remote.call(BROWSER, "open", player.index, {
    search=view.query, family="mir", selected=view.selected, sort=view.sort, tab="research", visibility=1
  }) ~= true then
    fail("public browser interface did not open for connected client")
  end
end

local function open_availability(player)
  if not (remote.interfaces and remote.interfaces[BROWSER]) then fail("shipped public browser interface is absent") end
  if remote.call(BROWSER, "open", player.index, {tab="availability", search=""}) ~= true then
    fail("public browser interface did not open Availability for connected client")
  end
end

local function frame_parts(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  if not valid(root) or root.type ~= "frame" or root.visible ~= true then fail("native browser root is absent or hidden") end
  local filters = root[FILTERS]
  local query, sort = valid(filters) and filters[QUERY] or nil, valid(filters) and filters[SORT] or nil
  local tabs = root[TABS]
  local content = valid(tabs) and tabs[RESEARCH_CONTENT] or nil
  local results = valid(content) and content[RESULTS] or nil
  local detail = valid(content) and content[DETAIL] or nil
  if not valid(query) or query.type ~= "textfield" or not valid(sort) or sort.type ~= "drop-down"
      or not valid(tabs) or tabs.type ~= "tabbed-pane" or not valid(results) or results.type ~= "list-box"
      or not valid(detail) or not valid(detail[DETAIL_TITLE]) then
    fail("native public browser GUI tree is incomplete")
  end
  return root, query, sort, results, detail
end

local function assert_view(player, locale)
  local expected = VIEWS[locale]
  local root, query, sort, results = frame_parts(player)
  if query.text ~= expected.query or sort.selected_index ~= expected.sort_index
      or results.selected_index ~= 1 or #results.items ~= 1 then
    fail("personal browser query or selected view differs for locale " .. locale)
  end
  return root, query
end

local function assert_personal_views(english, german)
  local en_root, en_query = assert_view(english, "en")
  local de_root, de_query = assert_view(german, "de")
  if en_root == de_root or en_query == de_query or en_query.text == de_query.text then
    fail("two clients share a browser root or query")
  end
end

-- LuaObjects remain process-local evidence only. The durable fixture state
-- keeps scalar/native witnesses, never GUI objects or MIR-owned state.
local live_views = {}

local function localized_number(caption, key, value)
  -- Native LocalisedString parameters use their textual representation.
  return type(caption) == "table" and caption[1] == key and caption[2] == tostring(value)
end

local function localized_caption_shape(caption, key)
  if type(caption) ~= "table" then return "caption-type=" .. type(caption) end
  return "key-matches=" .. tostring(caption[1] == key) .. ", argument-type=" .. type(caption[2])
end

local function live_detail(player, retained, expected)
  local root, query, _, _, detail = frame_parts(player)
  if root ~= retained.root or query ~= retained.query then
    fail("native Library refresh replaced the owned root or query")
  end
  local context = detail["mir_library_detail_context"]
  if not valid(context) then fail("native Library refresh removed the detail context") end
  local level = detail["mir_library_detail_level"]
  if not valid(level) or not localized_number(level.caption, "mir-browser.level", expected.level) then
    fail("native Library refresh level differs (" .. localized_caption_shape(valid(level) and level.caption, "mir-browser.level") .. ")")
  end
  local current, queued = context["mir_library_context_current"], context["mir_library_context_queued"]
  if expected.current and not valid(current) then fail("native Library refresh lost current research context") end
  if not expected.current and valid(current) then fail("native Library refresh retained stale current research context") end
  if expected.current and valid(queued) then fail("native Library refresh mixed current and queued context") end
  if not expected.current and expected.count > 0 and not valid(queued) then
    fail("native Library refresh lost queued research context")
  end
  if expected.count == 0 then
    if valid(context["mir_library_context_queue_count"]) or valid(context["mir_library_context_queue_position"])
        or not valid(context["mir_library_context_not_queued"]) then
      fail("native Library refresh retained stale queue labels")
    end
  else
    local count, position = context["mir_library_context_queue_count"], context["mir_library_context_queue_position"]
    if not valid(count) or not localized_number(count.caption, "mir-browser.context-queue-count", expected.count)
        or not valid(position) or not localized_number(position.caption, "mir-browser.context-queue-position", 1) then
      fail("native Library refresh queue facts differ (count "
        .. localized_caption_shape(valid(count) and count.caption, "mir-browser.context-queue-count") .. "; position "
        .. localized_caption_shape(valid(position) and position.caption, "mir-browser.context-queue-position") .. ")")
    end
  end
end

local function remember_live_views(english, german)
  local en_root, en_query = assert_view(english, "en")
  local de_root, de_query = assert_view(german, "de")
  live_views[english.index] = {root=en_root, query=en_query}
  live_views[german.index] = {root=de_root, query=de_query}
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if not valid(value) then fail("required native technology is absent: " .. tostring(name)) end
  return value
end

local function exact_queue(force, expected)
  local queue = copy_queue(force)
  if #queue ~= #expected then return false end
  for index, name in ipairs(expected) do if queue[index] ~= name then return false end end
  return true
end

local function assert_gear_science_vector(gear)
  local ingredients = gear.research_unit_ingredients
  if type(ingredients) ~= "table" then fail("fixture gear science vector differs: ingredients are absent") end
  local expected, seen = {}, {}
  for _, name in ipairs(GEAR_PACKS) do expected[name] = true end
  for _, ingredient in ipairs(ingredients) do
    local name = type(ingredient) == "table" and ingredient.name or nil
    if type(name) ~= "string" or expected[name] ~= true then
      fail("fixture gear science vector differs: unexpected ingredient")
    end
    if seen[name] then fail("fixture gear science vector differs: duplicate ingredient") end
    if ingredient.amount ~= 1 then fail("fixture gear science vector differs: ingredient amount") end
    seen[name] = true
  end
  for _, name in ipairs(GEAR_PACKS) do
    if not seen[name] then fail("fixture gear science vector differs: required ingredient is missing") end
  end
end

local function gear_definition(force)
  local gear = technology(force, GEAR)
  if gear.level ~= 1 or gear.researched or gear.enabled ~= true
      or gear.research_unit_count ~= 1 or gear.research_unit_energy ~= 60 then
    fail("fixture gear acceleration or native initial state differs")
  end
  local effects, matches = gear.prototype and gear.prototype.effects or {}, 0
  for _, effect in ipairs(effects) do
    if effect.type == "change-recipe-productivity" and effect.recipe == "iron-gear-wheel"
        and close(effect.change, GEAR_EFFECT) then
      matches = matches + 1
    end
  end
  if matches ~= 1 then fail("native gear effect differs") end
  assert_gear_science_vector(gear)
  return gear
end

local function seed_gear_prerequisites(force)
  for _, name in ipairs(GEAR_PACKS) do
    local prerequisite = technology(force, name)
    prerequisite.researched = true
  end
end

local function research_inventory(state)
  if not valid(state.lab) then fail("actual Library refresh lab is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("actual Library refresh lab input is absent") end
  return inventory
end

-- Two bounded read-only observations distinguish native lab stalls from GUI
-- failures. Never repair state, complete research or relax the deadline here.
local function lab_diagnostic(state, stage)
  local force, lab = game.forces.player, state.lab
  local lab_valid = valid(lab)
  local inventory = lab_valid and lab.get_inventory(defines.inventory.lab_input) or nil
  local counts = {}
  for _, name in ipairs(GEAR_PACKS) do
    counts[name] = inventory and inventory.get_item_count(name) or nil
  end
  local current, pending = force.current_research, force.research_queue or {}
  local queue = {}
  for index = 1, math.min(#pending, 8) do queue[index] = named(pending[index]) end
  local gear = force.technologies[GEAR]
  log("[MIR5_LIBRARY_LAB_DIAGNOSTIC] " .. helpers.table_to_json({
    schema=1, case=CASE, stage=stage, tick=game.tick, phase=state.phase,
    started=state.started, finished=state.finished,
    lab={valid=lab_valid, active=lab_valid and lab.active,
      energy=lab_valid and lab.energy, status=lab_valid and lab.status,
      electric_network_id=lab_valid and (lab.electric_network_id or false)},
    research={enabled=force.research_enabled, current=named(current),
      progress=current and force.research_progress, queue_count=#pending, queue=queue},
    gear={level=gear and gear.level, enabled=gear and gear.enabled,
      count=gear and gear.research_unit_count, energy=gear and gear.research_unit_energy},
    science_counts=counts,
  }))
end

local function assert_lab_consumption(state)
  local inventory = research_inventory(state)
  for _, name in ipairs(GEAR_PACKS) do
    if inventory.get_item_count(name) ~= 0 then
      fail("actual Library refresh lab science consumption differs: " .. name)
    end
  end
end

local function assert_completed_gear(state, force)
  local gear = technology(force, GEAR)
  if state.finished ~= 2 or state.started < 2
      or gear.level ~= GEAR_LEVEL_AFTER_TWO_LABS or gear.researched
      or force.current_research ~= nil or not exact_queue(force, {})
      or not close(force.recipes["iron-gear-wheel"].productivity_bonus, 2 * GEAR_EFFECT) then
    fail("actual Library refresh research/queue state differs")
  end
  assert_lab_consumption(state)
end

local function localized_key(value)
  return type(value) == "table" and value[1] or nil
end

local function assert_availability(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  local filters = valid(root) and root[FILTERS] or nil
  local query = valid(filters) and filters[QUERY] or nil
  local tabs = valid(root) and root[TABS] or nil
  local content = valid(tabs) and tabs[RESEARCH_CONTENT] or nil
  local children = valid(content) and content.children or nil
  if not valid(root) or root.type ~= "frame" or root.visible ~= true or not valid(query) or query.text ~= ""
      or not valid(content) or children == nil then
    fail("native Availability browser GUI tree is incomplete")
  end
  if valid(content[RESULTS]) or valid(content[DETAIL]) or valid(content["mir_library_actions"]) then
    fail("Availability exposed research results or actions")
  end
  for index, name in ipairs(AVAILABILITY) do
    local label = content[name]
    local caption = valid(label) and label.caption or nil
    if not valid(label) or label.type ~= "label" or localized_key(caption) ~= "mir-browser.availability-entry"
        or localized_key(caption[2]) ~= "technology-name.more-infinite-research." .. AVAILABILITY_FAMILIES[index]
        or localized_key(caption[3]) ~= "mir-browser.availability-requires-space-age" then
      fail("native Availability terminal label differs: " .. AVAILABILITY_FAMILIES[index])
    end
  end
  if #children ~= #AVAILABILITY then
    fail("native Availability terminal label count differs")
  end
end

local function measure(state, label, callback)
  local profiler = game.create_profiler(true)
  profiler.restart()
  callback()
  profiler.stop()
  -- Only the engine's LocalisedString renderer exposes the measurement.
  -- Keep profiler objects/output out of synchronized saved state and JSON.
  log({"", "[MIR5_LIBRARY_PROFILE] ", label, " ", profiler})
  state.measurements[label] = true
end

local function screenshot(state, stage, player)
  game.take_screenshot{
    by_player=player.index, player=player, show_gui=true, force_render=true,
    path="mir5-library-multiplayer/" .. stage .. "-" .. player.index .. ".png",
    resolution={1280,720}
  }
  state.screenshot_calls = state.screenshot_calls + 1
end

local function marker(stage, state)
  log("[MIR5_LIBRARY_MULTIPLAYER] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed",
    witnesses={
      base_version=script.active_mods.base,
      mir_version=script.active_mods["more-infinite-research"],
      actual_join_events=state.join_events,
      screenshot_calls=state.screenshot_calls,
      first_open=state.measurements.first_open,
      search=state.measurements.search,
      refresh=state.measurements.refresh,
      reopen=state.measurements.reopen,
      measurement_output="native-localised-profiler-log",
      timing_values_stored=false,
      two_connected_clients_required=true,
      locales_required={"en", "de"},
      distinct_personal_query_and_selection=true,
      initial_native_snapshot_immutable=true,
      live_refresh={
        real_lab_completions=state.finished,
        native_laboratory_completion_by_script=false,
        native_research_started_events=state.started,
        queue_lengths_observed={state.queue_before_lab, state.queue_after_first, state.queue_after_labs},
        native_research_cancelled_events=state.cancelled,
        native_foreign_force_created_events=state.force_created,
        gear_level=state.native and state.native.technologies[GEAR].level,
        gear_productivity=state.native and state.native.recipes["iron-gear-wheel"],
        science_consumed_per_named_pack=LAB_PACKS,
        fixture_accelerates_gear_count_and_time_only=true,
        ordinary_tuning_qualified=false,
        root_and_query_identity_preserved=true,
        cross_force_view_state_preserved=true,
      },
      availability_terminal_labels_checked=state.availability_checked == true,
      host_restart_observed=stage == "completed",
      on_load_read_only=stage == "completed",
      rendering_pending_external_png_readback=true,
      screenshot_requests_are_not_headless_rendering_proof=true,
    }
  }))
end

local function client_count(state)
  local count = 0
  for _ in pairs(state.clients) do count = count + 1 end
  return count
end

local function pair(state, expected_joins)
  local by_locale, connected = {}, 0
  if client_count(state) > 2 then fail("fixture accepts exactly two unique clients") end
  for index, record in pairs(state.clients) do
    if record.joins > expected_joins then fail("client joined more than the required lifecycle count") end
    if record.joins == expected_joins then
      local player = game.get_player(index)
      if valid(player) and player.connected == true then
        connected = connected + 1
        -- A client's initial locale need not change after joining. Read the
        -- actual native value; locale-change events are supplementary rather
        -- than a fabricated prerequisite for an unchanged English locale.
        if player.locale ~= record.locale then
          record.locale = player.locale
          log("[MIR5_LIBRARY_MULTIPLAYER_LOCALE] " .. player.name .. " " .. tostring(record.locale))
        end
        if record.locale ~= "en" and record.locale ~= "de" then
          fail("two connected clients must have actual en/de locales: " .. player.name .. "=" .. tostring(record.locale))
        end
        if record.locale ~= nil then
          if by_locale[record.locale] ~= nil then
            if game.tick - record.join_tick <= 180 then return nil end
            fail("client locales are not distinct: " .. player.name .. "=" .. record.locale)
          end
          by_locale[record.locale] = player
        end
      end
    end
  end
  if connected < 2 then return nil end
  if connected ~= 2 or by_locale.en == nil or by_locale.de == nil then
    fail("two connected clients must have actual en/de locales")
  end
  if by_locale.en.index == by_locale.de.index or by_locale.en.force.index ~= state.force_index
      or by_locale.de.force.index ~= state.force_index then
    fail("connected clients do not share the prepared disposable force")
  end
  -- A join event exposes synchronized simulation objects before the joining
  -- client has necessarily finished its local game/GUI transition. Give both
  -- real clients a bounded render interval before requesting GUI captures.
  if game.tick - math.max(state.clients[by_locale.en.index].join_tick,
      state.clients[by_locale.de.index].join_tick) < 120 then return nil end
  return by_locale.en, by_locale.de
end

local function run_initial(state, english, german)
  open_availability(english)
  open_availability(german)
  assert_availability(english)
  assert_availability(german)
  assert_native(state, english.force)
  state.availability_checked = true
  screenshot(state, "availability", english)
  screenshot(state, "availability", german)
  -- Client screenshot requests are asynchronous. Keep the terminal view open
  -- for a full second before its ordinary personal view replaces it.
  state.phase = "capturing-availability"
  state.capture_after_tick = game.tick + 60
end

local function restore_initial_views(state, english, german)
  measure(state, "first_open", function() open(english, VIEWS.en) end)
  measure(state, "search", function() open(german, VIEWS.de) end)
  measure(state, "refresh", function() open(english, VIEWS.en) end)
  assert_personal_views(english, german)
  assert_native(state, english.force)
  remember_live_views(english, german)

  local force, surface = english.force, game.surfaces[1]
  if force.current_research ~= nil or not exact_queue(force, {}) then
    fail("fresh Library refresh world retained research before the real lab run")
  end
  local gear = gear_definition(force)
  seed_gear_prerequisites(force)
  local lab = surface.create_entity{name="lab", position=force.get_spawn_position(surface), force=force}
  if not valid(lab) then fail("could not create an actual Library refresh laboratory") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("actual Library refresh lab input is absent") end
  for _, name in ipairs(GEAR_PACKS) do
    if inventory.insert{name=name, count=LAB_PACKS} ~= LAB_PACKS then
      fail("actual Library refresh laboratory rejected " .. name)
    end
  end
  lab.energy = LAB_ENERGY
  state.lab, state.finished, state.started, state.cancelled, state.force_created = lab, 0, 0, 0, 0
  state.live_english_index, state.live_german_index = english.index, german.index
  state.live_deadline = game.tick + LIVE_DEADLINE_TICKS
  state.phase = "queueing-live-research"
  if force.add_research(gear) ~= true or force.add_research(gear) ~= true
      or not exact_queue(force, {GEAR, GEAR}) or named(force.current_research) ~= GEAR then
    fail("native Library refresh queue differs before laboratory progress")
  end
  state.queue_before_lab = #copy_queue(force)
  state.refresh_after_tick = game.tick + 2
  lab_diagnostic(state, "queued")
end

local function live_players(state)
  local english, german = game.get_player(state.live_english_index), game.get_player(state.live_german_index)
  if not valid(english) or not valid(german) or not english.connected or not german.connected then
    fail("live Library refresh lost an owned connected view")
  end
  return english, german
end

local function assert_live_queue_view(state, level, count, current)
  local english, german = live_players(state)
  live_detail(english, live_views[english.index], {level=level, count=count, current=current})
  local german_root, german_query = assert_view(german, "de")
  local retained = live_views[german.index]
  if german_root ~= retained.root or german_query ~= retained.query then
    fail("native Library refresh replaced the second owned root or query")
  end
  assert_personal_views(english, german)
end

local function begin_native_cancellation(state)
  local force, gear = game.forces.player, technology(game.forces.player, GEAR)
  state.phase = "cancelling-live-research"
  if force.add_research(gear) ~= true or not exact_queue(force, {GEAR}) or named(force.current_research) ~= GEAR then
    fail("native Library cancellation did not start a bounded third queue entry")
  end
  force.cancel_current_research()
  if state.cancelled ~= 1 or force.current_research ~= nil or not exact_queue(force, {}) then
    fail("native Library cancellation event or queue cleanup differs")
  end
end

local function complete_live_refresh(state)
  local force = game.forces.player
  assert_completed_gear(state, force)
  assert_live_queue_view(state, GEAR_LEVEL_AFTER_TWO_LABS, 0, false)
  state.queue_after_labs = #copy_queue(force)
  if state.queue_after_first ~= 1 or state.queue_after_labs ~= 0 then
    fail("native Library queue state differs after laboratory progress")
  end
  state.native = native_snapshot(force)
  state.native_after_lab = copy_snapshot(state.native)
  begin_native_cancellation(state)
end

local function complete_cancellation_refresh(state)
  local force = game.forces.player
  if state.cancelled ~= 1 then fail("native Library cancellation callback differs") end
  assert_completed_gear(state, force)
  assert_live_queue_view(state, GEAR_LEVEL_AFTER_TWO_LABS, 0, false)
  state.phase = "creating-foreign-force"
  state.foreign = game.create_force(FOREIGN_FORCE)
  if not valid(state.foreign) or state.force_created ~= 1 then
    fail("native foreign force creation event differs")
  end
  state.phase = "awaiting-foreign-force-refresh"
  state.refresh_after_tick = game.tick + 2
end

local function complete_foreign_force_refresh(state)
  local force = game.forces.player
  if state.foreign == force or state.foreign.name ~= FOREIGN_FORCE then
    fail("native foreign force identity differs")
  end
  local foreign_gear = technology(state.foreign, GEAR)
  if foreign_gear.level ~= 1 or foreign_gear.researched
      or not close(state.foreign.recipes["iron-gear-wheel"].productivity_bonus, 0) then
    fail("foreign force inherited player Library research state")
  end
  assert_completed_gear(state, force)
  assert_live_queue_view(state, GEAR_LEVEL_AFTER_TWO_LABS, 0, false)
  local english, german = live_players(state)
  screenshot(state, "initial", english)
  screenshot(state, "initial", german)
  state.phase = "awaiting-rejoin"
  marker("rejoin-ready", state)
end

local function run_rejoin(state, english, german)
  measure(state, "reopen", function()
    open(english, VIEWS.en)
    open(german, VIEWS.de)
  end)
  assert_personal_views(english, german)
  assert_native(state, english.force)
  screenshot(state, "rejoin", english)
  screenshot(state, "rejoin", german)
  -- Screenshots render asynchronously on each client. Saving in this tick
  -- can replace the GUI with the native save overlay before rendering it.
  state.phase = "capturing-rejoin"
  state.capture_after_tick = game.tick + 60
end

local function run_restart(state, english, german)
  if not loaded_restart then return end
  -- The post-restart join handler in the shipped Library must rebuild this
  -- already-open GUI before this fixture observes it; no new open call masks it.
  assert_personal_views(english, german)
  assert_native(state, english.force)
  screenshot(state, "restart", english)
  screenshot(state, "restart", german)
  state.phase = "capturing-restart"
  state.capture_after_tick = game.tick + 60
end

local function closure()
  local allowed = {base="2.0.77", ["more-infinite-research"]="5.0.20000",
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
    ["mir-fixture-mir5-library-multiplayer"]="0.1.0"}
  for name, version in pairs(script.active_mods) do
    if allowed[name] ~= version then fail("unexpected non-base F200 multiplayer closure: " .. tostring(name)) end
  end
  for name, version in pairs(allowed) do
    if script.active_mods[name] ~= version then fail("required multiplayer closure member is absent: " .. name) end
  end
end

script.on_init(function()
  closure()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local force, surface = game.forces.player, game.surfaces[1]
  if not valid(force) or not valid(surface) then fail("fresh disposable base world is absent") end
  local native = native_snapshot(force)
  storage[KEY] = {
    phase="waiting-initial-clients", world={force_index=force.index, surface_index=surface.index}, force_index=force.index,
    native=native, native_initial=copy_snapshot(native), native_initial_guard=copy_snapshot(native), clients={}, join_events=0,
    screenshot_calls=0, measurements={}, availability_checked=false
  }
  marker("ready", storage[KEY])
  ready_logged = true
end)

script.on_load(function()
  local state = storage[KEY]
  -- on_load cannot access game and must not modify durable fixture state.
  loaded_restart = type(state) == "table" and state.phase == "awaiting-host-restart"
  ready_logged = false
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local state = storage[KEY]
  local player = state and event and game.get_player(event.player_index)
  if not valid(player) or player.connected ~= true then fail("join event did not expose an actually connected client") end
  local record = state.clients[player.index]
  if record == nil then
    if client_count(state) >= 2 then fail("fixture accepts exactly two unique clients") end
    record = {joins=0, locale=nil, locale_events=0}
    state.clients[player.index] = record
  end
  record.joins = record.joins + 1
  record.join_tick = game.tick
  record.locale = player.locale
  state.join_events = state.join_events + 1
  log("[MIR5_LIBRARY_MULTIPLAYER_JOIN] " .. player.name .. " " .. tostring(record.joins))
  log("[MIR5_LIBRARY_MULTIPLAYER_LOCALE] " .. player.name .. " " .. tostring(record.locale))
end)

script.on_event(defines.events.on_player_locale_changed, function(event)
  local state = storage[KEY]
  local player = state and event and game.get_player(event.player_index)
  local record = player and state.clients[player.index]
  if not valid(player) or player.connected ~= true or type(record) ~= "table" then
    fail("locale event did not follow an actual connected client join")
  end
  record.locale = player.locale
  record.locale_events = record.locale_events + 1
end)

script.on_event(defines.events.on_research_started, function(event)
  local state = storage[KEY]
  if not state or (state.phase ~= "queueing-live-research" and state.phase ~= "researching-live-research"
      and state.phase ~= "cancelling-live-research") then return end
  local research = event and event.research
  if not valid(research) or research.name ~= GEAR or research.force ~= game.forces.player then
    fail("native Library research-start callback differs")
  end
  state.started = state.started + 1
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching-live-research" then return end
  local research = event and event.research
  if not valid(research) or research.name ~= GEAR or research.force ~= game.forces.player or event.by_script ~= false then
    fail("actual Library laboratory completion callback differs")
  end
  state.finished = state.finished + 1
  if state.finished > 2 then fail("Library refresh lab completed an unexpected third level") end
  state.refresh_after_tick = game.tick + 2
end)

script.on_event(defines.events.on_research_cancelled, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "cancelling-live-research" then return end
  if event.force ~= game.forces.player or type(event.research) ~= "table" or event.research[GEAR] ~= 1 then
    fail("native Library cancellation callback differs")
  end
  state.cancelled = state.cancelled + 1
  if state.cancelled > 1 then fail("Library refresh cancellation callback duplicated") end
  state.refresh_after_tick = game.tick + 2
end)

script.on_event(defines.events.on_force_created, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "creating-foreign-force" then return end
  local force = event and event.force
  if not valid(force) or force.name ~= FOREIGN_FORCE or force == game.forces.player then
    fail("native foreign-force callback differs")
  end
  state.force_created = state.force_created + 1
  if state.force_created > 1 then fail("native foreign-force callback duplicated") end
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("multiplayer fixture state is absent") end
  if state.phase == "waiting-initial-clients" then
    -- --create already initialized the world. The subsequent headless host
    -- loads it, so expose readiness again without changing durable state.
    if not ready_logged then marker("ready", state);ready_logged = true end
    local english, german = pair(state, 1)
    if english and german then run_initial(state, english, german) end
  elseif state.phase == "capturing-availability" and game.tick >= state.capture_after_tick then
    local english, german = pair(state, 1)
    if english and german then
      state.capture_after_tick = nil
      restore_initial_views(state, english, german)
    end
  elseif state.phase == "queueing-live-research" then
    if game.tick >= state.live_deadline then fail("native Library refresh queue did not settle") end
    if game.tick >= (state.refresh_after_tick or game.tick) then
      if state.started < 1 or state.queue_before_lab ~= 2 then
        fail("native Library queue state or research-start callback differs")
      end
      assert_live_queue_view(state, 1, 2, true)
      state.phase = "researching-live-research"
    end
  elseif state.phase == "researching-live-research" then
    if game.tick >= state.live_deadline then
      lab_diagnostic(state, "deadline")
      fail("actual Library refresh laboratory exceeded deadline")
    end
    if not valid(state.lab) then fail("actual Library refresh laboratory was removed") end
    state.lab.energy = LAB_ENERGY
    if state.finished == 1 and game.tick >= (state.refresh_after_tick or game.tick) and not state.first_completion_seen then
      local force = game.forces.player
      if technology(force, GEAR).level ~= 2 or not exact_queue(force, {GEAR}) or named(force.current_research) ~= GEAR then
        fail("first native Library laboratory completion differs")
      end
      assert_live_queue_view(state, 2, 1, true)
      state.queue_after_first = #copy_queue(force)
      state.first_completion_seen = true
    elseif state.finished == 2 and game.tick >= (state.refresh_after_tick or game.tick) then
      state.phase = "awaiting-final-live-refresh"
    end
  elseif state.phase == "awaiting-final-live-refresh" then
    complete_live_refresh(state)
  elseif state.phase == "cancelling-live-research" then
    if game.tick >= state.live_deadline then fail("native Library cancellation refresh exceeded deadline") end
    if game.tick >= (state.refresh_after_tick or game.tick) then complete_cancellation_refresh(state) end
  elseif state.phase == "awaiting-foreign-force-refresh" then
    if game.tick >= state.live_deadline then fail("native foreign-force refresh exceeded deadline") end
    if game.tick >= (state.refresh_after_tick or game.tick) then complete_foreign_force_refresh(state) end
  elseif state.phase == "awaiting-rejoin" then
    local english, german = pair(state, 2)
    if english and german then run_rejoin(state, english, german) end
  elseif state.phase == "awaiting-host-restart" then
    local english, german = pair(state, 3)
    if english and german then run_restart(state, english, german) end
  elseif state.phase == "capturing-rejoin" and game.tick >= state.capture_after_tick then
    state.phase = "awaiting-host-restart"
    state.capture_after_tick = nil
    game.server_save(RESTART_SAVE)
    marker("restart-ready", state)
  elseif state.phase == "capturing-restart" and game.tick >= state.capture_after_tick then
    state.phase = "completed"
    state.capture_after_tick = nil
    marker("completed", state)
    game.server_save(FINAL_SAVE)
  end
end)

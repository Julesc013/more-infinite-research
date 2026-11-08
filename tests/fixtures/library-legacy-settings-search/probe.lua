-- Prepared test-only Library Settings search probe.  A later, separately
-- committed imported/client composition owns invocation and client capture.
-- This helper registers no events or remote interface and performs no gameplay mutation.
local M = {}

local ROOT = "mir_research_browser"
local PREFIX = "mir_library_"
local BROWSER = "more-infinite-research-browser"
local OWNER = "more-infinite-research"
local ROOT_TAG = "more-infinite-research.library-root.v1"
local STAGES = {
  "research",
  "settings-baseline",
  "settings-repair",
  "settings-retained-default",
  "settings-no-match",
  "restore-settings-empty",
  "restore-research",
}
local NO_MATCH = string.rep("x", 161)
local MAX_SETTING_DESCRIPTORS = 2048

local function fail(message)
  error("[mir-library-legacy-settings-search] " .. message, 2)
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function whole(value, minimum, maximum)
  return type(value) == "number" and value == math.floor(value)
    and value >= minimum and value <= maximum
end

local function owned(element, parent, element_type, name)
  if not valid(element) or element.parent ~= parent or element.type ~= element_type or element.name ~= name then
    fail("owned GUI path differs: " .. name)
  end
  if type(element.get_mod) ~= "function" or element.get_mod() ~= OWNER then
    fail("foreign GUI ownership: " .. name)
  end
  return element
end

local function items_from(list)
  local source = list.items
  if type(source) ~= "table" then fail("settings list items differ") end
  local count = #source
  if count > MAX_SETTING_DESCRIPTORS then fail("settings list bound exceeded") end
  local items = {}
  for index = 1, count do items[index] = source[index] end
  return items
end

local function count_from(label, list_count)
  local caption = label.caption
  if type(caption) ~= "table" or caption[1] ~= "mir-browser.settings-count"
      or not whole(caption[2], 0, MAX_SETTING_DESCRIPTORS) or caption[2] ~= list_count then
    fail("settings count differs")
  end
  return caption[2], caption
end

function M.new(context)
  if type(context) ~= "table" or not valid(context.player) or type(context.assert_world) ~= "function"
      or type(context.tick) ~= "function" then
    fail("prepared context differs")
  end
  local player = context.player
  local research_query = context.research_query
  local settle_ticks = context.settle_ticks == nil and 30 or context.settle_ticks
  if type(research_query) ~= "string" or research_query == "" or #research_query > 160
      or not whole(settle_ticks, 1, 3600) then
    fail("prepared query or settle bound differs")
  end
  if type(player.index) ~= "number" or player.gui == nil or player.gui.screen == nil then
    fail("prepared player differs")
  end

  local state = {next = 1, pending = nil, observations = {}, research_text = nil}

  local function world()
    context.assert_world()
  end

  local function now()
    local value = context.tick()
    if not whole(value, 0, 2147483647) then fail("prepared tick differs") end
    return value
  end

  local function root()
    local frame = owned(player.gui.screen[ROOT], player.gui.screen, "frame", ROOT)
    if type(frame.tags) ~= "table" or frame.tags[ROOT_TAG] ~= true then fail("MIR root tag differs") end
    return frame
  end

  local function paths(require_settings)
    local frame = root()
    local tabs = owned(frame[PREFIX .. "tabs"], frame, "tabbed-pane", PREFIX .. "tabs")
    local research_page = owned(tabs[PREFIX .. "research_page"], tabs, "scroll-pane", PREFIX .. "research_page")
    local filters = owned(research_page[PREFIX .. "filters"], research_page, "flow", PREFIX .. "filters")
    local research = owned(filters[PREFIX .. "query"], filters, "textfield", PREFIX .. "query")
    if not whole(tabs.selected_tab_index, 1, 4) then fail("selected tab differs") end
    if type(research.text) ~= "string" then fail("Research query text differs") end
    local result = {tabs = tabs, research = research}
    if require_settings then
      local settings = owned(tabs[PREFIX .. "settings_content"], tabs, "scroll-pane", PREFIX .. "settings_content")
      local query = owned(settings[PREFIX .. "settings_query"], settings, "textfield", PREFIX .. "settings_query")
      local dynamic = owned(settings[PREFIX .. "settings_dynamic"], settings, "table", PREFIX .. "settings_dynamic")
      local list = owned(dynamic[PREFIX .. "settings_list"], dynamic, "list-box", PREFIX .. "settings_list")
      local count = owned(dynamic[PREFIX .. "settings_count"], dynamic, "label", PREFIX .. "settings_count")
      if type(query.text) ~= "string" then fail("Settings query text differs") end
      result.settings_query, result.list, result.count = query, list, count
    end
    return result
  end

  local function observe(stage, expected_tab, expected_query)
    local settings_expected = expected_query ~= nil
    local gui = paths(settings_expected)
    if gui.tabs.selected_tab_index ~= expected_tab then fail("selected tab differs: " .. stage) end
    local observation = {
      stage = stage,
      selected_tab = gui.tabs.selected_tab_index,
      research_text = gui.research.text,
    }
    if settings_expected then
      if gui.settings_query.text ~= expected_query then fail("settings query differs: " .. stage) end
      local items = items_from(gui.list)
      local count, caption = count_from(gui.count, #items)
      observation.settings_text = gui.settings_query.text
      observation.list_items, observation.list_count, observation.count_caption = items, count, caption
    end
    return observation
  end

  local function call(options)
    if type(remote) ~= "table" or type(remote.call) ~= "function" then fail("browser remote is absent") end
    if remote.call(BROWSER, "open", player.index, options) ~= true then fail("browser remote did not open") end
  end

  local function prepare_options(stage)
    if stage == "research" then return {tab = "research", search = research_query} end
    if stage == "settings-baseline" then return {tab = "settings", settings_scope = "research", search = ""} end
    if stage == "settings-repair" then return {tab = "settings", settings_scope = "research", search = "repair"} end
    if stage == "settings-retained-default" then return {search = "default"} end
    if stage == "settings-no-match" then return {search = NO_MATCH} end
    if stage == "restore-settings-empty" then return {tab = "settings", settings_scope = "research", search = ""} end
    if stage == "restore-research" then return {tab = "research"} end
    fail("unknown fixed stage")
  end

  local probe = {}
  function probe.prepare(stage)
    if stage ~= STAGES[state.next] or state.pending ~= nil then fail("prepare stage/order differs") end
    world()
    call(prepare_options(stage))
    state.pending = {stage = stage, ready_tick = now() + settle_ticks}
  end

  function probe.check(stage)
    if state.pending == nil or state.pending.stage ~= stage or stage ~= STAGES[state.next] then
      fail("check stage/order differs")
    end
    if now() < state.pending.ready_tick then fail("check before GUI settle") end
    world()
    local observation
    if stage == "research" then
      observation = observe(stage, 1, nil)
      if observation.research_text ~= research_query then fail("initial Research query differs") end
      state.research_text = observation.research_text
    elseif stage == "settings-baseline" then
      observation = observe(stage, 3, "")
      if observation.list_count < 1 then fail("Settings baseline is empty") end
    elseif stage == "settings-repair" then
      observation = observe(stage, 3, "repair")
      local baseline = state.observations["settings-baseline"]
      if observation.list_count < 1 or baseline == nil or observation.list_count >= baseline.list_count then
        fail("Settings repair filter differs")
      end
    elseif stage == "settings-retained-default" then
      observation = observe(stage, 3, "default")
    elseif stage == "settings-no-match" then
      observation = observe(stage, 3, string.sub(NO_MATCH, 1, 160))
      if observation.list_count ~= 0 then fail("Settings no-match filter differs") end
    elseif stage == "restore-settings-empty" then
      observation = observe(stage, 3, "")
    elseif stage == "restore-research" then
      observation = observe(stage, 1, "")
      if observation.research_text ~= state.research_text or observation.settings_text ~= "" then
        fail("Research or hidden Settings query was not preserved")
      end
    else
      fail("unknown fixed stage")
    end
    if stage ~= "research" and stage ~= "restore-research" and observation.research_text ~= state.research_text then
      fail("Research query leaked during Settings check")
    end
    state.observations[stage] = observation
    state.pending = nil
    state.next = state.next + 1
    return observation
  end

  function probe.report()
    if state.pending ~= nil then fail("probe is waiting for a check") end
    return {next_stage = STAGES[state.next], research_text = state.research_text, observations = state.observations}
  end

  return probe
end

return M

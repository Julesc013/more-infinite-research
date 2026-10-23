-- Private, first vertical slice of the MIR Research Library.
--
-- The catalogue/model modules own research facts. This module owns only a
-- player's small view preference and GUI construction. Control.lua must route
-- its callbacks explicitly; this file never registers handlers or creates a
-- recurring subscription by itself.
local catalogue = require("research.catalogue")
local library_model = require("presentation.library_model")

local M = {}

local STORAGE_KEY = "mir_library"
local SCHEMA = 1
local ROOT = "mir_research_browser"
-- A name is shared global GUI namespace, so it cannot establish ownership.
-- The tag is set when this slice creates the root; callbacks also prove the
-- full parent chain back to the current player's screen before changing state.
local ROOT_TAG = "more-infinite-research.library-root.v1"
local PREFIX = "mir_library_"
local SHORTCUT = "mir-research-browser"
local MAX_QUERY = 160
local LEGACY_NAMESPACE = "mir"
local LEGACY_BROWSER_KEY = "research_browser"
local LEGACY_ROOT_MARKER = "mir_browser_tabs"
local LEGACY_SNAPSHOT_VERSION = 1
local LEGACY_SNAPSHOT_MAX_DEPTH = 8
local LEGACY_SNAPSHOT_MAX_ENTRIES = 512
local LEGACY_SNAPSHOT_MAX_STRING = 4096
local cap_provider = nil

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function player_for(index)
  if type(index) ~= "number" or not game then return nil end
  local ok, player = pcall(function()
    if type(game.get_player) == "function" then return game.get_player(index) end
    return game.players and game.players[index] or nil
  end)
  return ok and valid(player) and player or nil
end

local function existing_state()
  local value = storage[STORAGE_KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= SCHEMA or type(value.players) ~= "table" then
    error("MIR unsupported Library storage schema", 2)
  end
  return value
end

local function ensure_state()
  local value = existing_state()
  if value then return value end
  value = {schema = SCHEMA, players = {}}
  storage[STORAGE_KEY] = value
  return value
end

local function text(value)
  if type(value) ~= "string" then return "" end
  if #value > MAX_QUERY then return string.sub(value, 1, MAX_QUERY) end
  return value
end

local function technology_id(value)
  if type(value) ~= "string" or value == "" or #value > MAX_QUERY then return nil end
  return value
end

local function location(value)
  if type(value) ~= "table" then return nil end
  if not finite_number(value.x) or not finite_number(value.y) then return nil end
  return {x = value.x, y = value.y}
end

local function local_view(raw)
  raw = type(raw) == "table" and raw or {}
  local value = {
    schema = SCHEMA,
    query = text(raw.query),
    family = raw.family == "all" and "all" or "mir",
    status = raw.status,
    selected = technology_id(raw.selected),
    location = location(raw.location),
    scroll = type(raw.scroll) == "number" and raw.scroll > 0 and math.floor(raw.scroll) or 1
  }
  -- The data-only model independently normalizes its own read surface. Keep
  -- this UI-owned record narrow and copy back only fields this host owns.
  local normalized = library_model.normalize({
    search = value.query,
    family = value.family,
    status = value.status,
    selected = value.selected
  })
  if type(normalized) == "table" then
    value.query = text(normalized.search or value.query)
    value.family = normalized.family == "mir" and "mir" or "all"
    value.status = type(normalized.status) == "number" and normalized.status or 1
    value.selected = type(normalized.selected) == "string" and normalized.selected or nil
  end
  return value
end

local function view_for(player_index)
  local state = ensure_state()
  local value = local_view(state.players[player_index])
  state.players[player_index] = value
  return value
end

local function player_index(value)
  if type(value) ~= "number" or value < 1 or value ~= math.floor(value) then return nil end
  return value
end

-- Preserve the old browser's personal records as a bounded convenience copy.
-- The published bucket remains untouched and is the authoritative full-fidelity
-- record. Snapshot metadata makes any bounded copy explicit rather than
-- silently presenting it as a complete migration.
local function legacy_copy(value, depth, budget, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then return value end
  if kind == "number" then
    if finite_number(value) then return value end
    budget.truncated, budget.invalid = true, true
    return nil
  end
  if kind == "string" then
    if #value <= LEGACY_SNAPSHOT_MAX_STRING then return value end
    budget.truncated, budget.string_limited = true, true
    return string.sub(value, 1, LEGACY_SNAPSHOT_MAX_STRING)
  end
  if kind ~= "table" then
    budget.truncated, budget.unsupported = true, true
    return nil
  end
  if depth >= LEGACY_SNAPSHOT_MAX_DEPTH then
    budget.truncated, budget.depth_limited = true, true
    return nil
  end
  if budget.left <= 0 then
    budget.truncated, budget.entry_limited = true, true
    return nil
  end
  if seen[value] then
    budget.truncated, budget.cyclic = true, true
    return nil
  end
  seen[value] = true

  local copy = {}
  for key, child in pairs(value) do
    if budget.left <= 0 then
      budget.truncated, budget.entry_limited = true, true
      break
    end
    local copied_key = legacy_copy(key, depth + 1, budget, seen)
    if copied_key ~= nil then
      budget.left = budget.left - 1
      local copied_value = legacy_copy(child, depth + 1, budget, seen)
      if copied_value ~= nil then copy[copied_key] = copied_value end
    end
  end
  seen[value] = nil
  return copy
end

local function legacy_snapshot(value)
  local budget = {left = LEGACY_SNAPSHOT_MAX_ENTRIES}
  local copied = legacy_copy(value, 0, budget, {})
  return copied, {
    complete = budget.truncated ~= true,
    truncated = budget.truncated == true,
    entry_limited = budget.entry_limited == true,
    depth_limited = budget.depth_limited == true,
    string_limited = budget.string_limited == true,
    cyclic = budget.cyclic == true,
    unsupported = budget.unsupported == true,
    invalid = budget.invalid == true
  }
end

local function legacy_browser_state()
  local namespace = type(storage) == "table" and storage[LEGACY_NAMESPACE] or nil
  local browser = type(namespace) == "table" and namespace[LEGACY_BROWSER_KEY] or nil
  return type(browser) == "table" and browser or nil
end

local function legacy_view_as_private(value)
  return local_view({
    query = value.search,
    family = value.family,
    status = value.status,
    selected = value.selected,
    location = value.location,
    scroll = value.scroll
  })
end

local function named_root(player)
  local gui = player and player.gui
  local screen = gui and gui.screen
  return screen and screen[ROOT] or nil
end

local function root_is_on_screen(player, frame)
  if not valid(frame) then return false end
  local gui = player and player.gui
  local screen = gui and gui.screen
  if not valid(screen) then return false end
  local ok, parent = pcall(function() return frame.parent end)
  return ok and parent == screen
end

local function root_has_tag(frame)
  local ok, tags = pcall(function() return frame.tags end)
  return ok and type(tags) == "table" and tags[ROOT_TAG] == true
end

local function owned_root(player)
  local frame = named_root(player)
  if not root_is_on_screen(player, frame) or not root_has_tag(frame) then return nil end
  return frame
end

-- Event payload names are globally shared. Check every ancestor, ending in
-- this player's tagged root, before accepting a GUI callback.
local function owns_element(player, element, names)
  if not valid(element) or type(names) ~= "table" then return false end
  local current = element
  for index = 1, #names do
    if not valid(current) or current.name ~= names[index] then return false end
    if index < #names then
      local ok, parent = pcall(function() return current.parent end)
      if not ok then return false end
      current = parent
    end
  end
  return current == owned_root(player)
end

local function legacy_marker(player, frame)
  if not root_is_on_screen(player, frame) then return nil end
  local ok, marker = pcall(function() return frame[LEGACY_ROOT_MARKER] end)
  if not ok or not valid(marker) then return nil end
  local parent_ok, parent = pcall(function() return marker.parent end)
  if not parent_ok or parent ~= frame then return nil end
  local type_ok, marker_type = pcall(function() return marker.type end)
  return type_ok and marker_type == "tabbed-pane" and marker or nil
end

local function model_view(view)
  return library_model.normalize({
    search = view.query,
    family = view.family,
    status = view.status,
    selected = view.selected
  })
end

local function context_for(force)
  if type(cap_provider) ~= "function" then return nil end
  local ok, caps = pcall(cap_provider, force)
  if not ok or type(caps) ~= "table" then return nil end
  -- The model may ask this closure about several rows. It receives the same
  -- already-read snapshot and never causes another lifecycle/settings lookup.
  return {cap_provider = function(observed_force)
    if observed_force ~= force then return nil end
    return caps
  end}
end

local function rows_for(player, view, context)
  local rows = library_model.rows(player.force, catalogue.declared(), model_view(view), {}, context)
  if type(rows) ~= "table" then return {} end
  return rows
end

local function selected_detail(player, view, context)
  if not view.selected then return nil end
  return library_model.detail(player.force, catalogue.declared(), model_view(view), {}, context)
end

local function set_shortcut(player, toggled)
  if type(player.set_shortcut_toggled) == "function" then
    player.set_shortcut_toggled(SHORTCUT, toggled == true)
  end
end

local function remember_location(view, frame)
  if valid(frame) then
    local remembered = location(frame.location)
    if remembered then view.location = remembered end
  end
end

local function destroy_frame(player, view)
  local frame = owned_root(player)
  if not valid(frame) then return false end
  remember_location(view, frame)
  frame.destroy()
  set_shortcut(player, false)
  return true
end

-- A same-named frame alone is not enough to claim it.  The historical browser
-- always created this tabbed-pane child, while the MIR5 root uses its own
-- mir_library_filters and mir_library_content children.
local function rebuild_owned_legacy_root(player, view)
  local frame = named_root(player)
  -- This is migration-only evidence for the published untagged browser, never
  -- ordinary open/close ownership. The authoritative legacy storage bucket is
  -- also required by the caller before this branch is reached.
  if not legacy_marker(player, frame) then return false end
  remember_location(view, frame)
  frame.destroy()
  set_shortcut(player, false)
  M.open(player)
  return true
end

local function caption(row)
  if type(row.name) == "string" and row.name ~= "" then return row.name end
  return row.id or ""
end

local function row_index(rows, selected)
  for index, row in ipairs(rows) do
    if row.id == selected then return index end
  end
  return nil
end

local function add(parent, spec)
  return parent.add(spec)
end

local function detail_lines(parent, row, detail)
  if not row then
    add(parent, {type = "label", name = PREFIX .. "detail_empty", caption = {"mir-browser.no-results"}})
    return
  end

  add(parent, {type = "label", name = PREFIX .. "detail_title", caption = caption(row)})
  add(parent, {type = "label", name = PREFIX .. "detail_family", caption = {"mir-browser.family", row.family or "mir"}})
  local context = add(parent, {type = "flow", name = PREFIX .. "detail_context", direction = "vertical"})
  local status_key = {
    ready = "mir-browser.status-ready",
    locked = "mir-browser.status-locked",
    queued = "mir-browser.status-queued",
    missing = "mir-browser.status-missing"
  }
  add(context, {type = "label", name = PREFIX .. "context_status", caption = {"mir-browser.context-status", {status_key[row.status] or "mir-browser.detail-unavailable"}}})
  if row.current == true then
    add(context, {type = "label", name = PREFIX .. "context_current", caption = {"mir-browser.context-current"}})
  elseif type(row.queued_count) == "number" and row.queued_count > 0 then
    add(context, {type = "label", name = PREFIX .. "context_queued", caption = {"mir-browser.context-queued"}})
  else
    add(context, {type = "label", name = PREFIX .. "context_not_queued", caption = {"mir-browser.context-not-queued"}})
  end
  if type(row.queued_count) == "number" and row.queued_count > 0 then
    add(context, {type = "label", name = PREFIX .. "context_queue_count", caption = {"mir-browser.context-queue-count", row.queued_count}})
    if type(row.queue_index) == "number" and row.queue_index > 0 then
      add(context, {type = "label", name = PREFIX .. "context_queue_position", caption = {"mir-browser.context-queue-position", row.queue_index}})
    end
  end
  add(context, {type = "label", name = PREFIX .. "context_queue_guidance", caption = {"mir-browser.native-queue-guidance"}})
  if row.cap and row.cap > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_level", caption = {"mir-browser.level-cap", row.current_level or 1, row.cap}})
    add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"mir-browser.cap-finite", row.cap, tostring(row.cap_setting or "?")}})
  else
    add(parent, {type = "label", name = PREFIX .. "detail_level", caption = {"mir-browser.level", row.current_level or 1}})
    if row.cap_state == "unlimited" then
      add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"mir-browser.cap-unlimited"}})
    elseif row.cap_state == "unavailable" then
      add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"mir-browser.cap-unavailable"}})
    end
  end
  if type(detail) == "table" and detail.cost ~= nil then
    add(parent, {type = "label", name = PREFIX .. "detail_cost", caption = {"mir-browser.research-cost", tostring(type(detail.cost) == "table" and (detail.cost.count or detail.cost[1] or "?") or detail.cost), tostring(type(detail.cost) == "table" and (detail.cost.time or detail.cost.energy or detail.cost[2] or "?") or "?")}})
  end
  if type(detail) == "table" and type(detail.prerequisites) == "table" and #detail.prerequisites > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_prerequisites", caption = {"mir-browser.prerequisites"}})
    for index, prerequisite in ipairs(detail.prerequisites) do
      add(parent, {type = "label", name = PREFIX .. "prerequisite_" .. index, caption = tostring(prerequisite)})
    end
  end
  if type(detail) == "table" and type(detail.effects) == "table" and #detail.effects > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_benefits", caption = {"mir-browser.benefits"}})
    for index, effect in ipairs(detail.effects) do
      local effect_type = type(effect) == "table" and effect.type or effect
      local change = type(effect) == "table" and effect.change or nil
      local text_value = tostring(effect_type or "")
      if change ~= nil then text_value = text_value .. " " .. tostring(change) end
      add(parent, {type = "label", name = PREFIX .. "effect_" .. index, caption = text_value})
    end
  end
end

local function update_content(frame, player, view, context)
  local content = frame[PREFIX .. "content"]
  if not valid(content) then return end
  content.clear()

  local rows = rows_for(player, view, context)
  local labels = {}
  for index, row in ipairs(rows) do labels[index] = caption(row) end
  local selected_index = row_index(rows, view.selected) or 0
  local results = add(content, {type = "list-box", name = PREFIX .. "results", items = labels, selected_index = selected_index})
  if view.scroll and view.scroll <= #labels and type(results.scroll_to_item) == "function" then
    results.scroll_to_item(view.scroll, "top-third")
  end
  add(content, {type = "label", name = PREFIX .. "count", caption = {"mir-browser.count", #rows}})

  local selected = selected_index > 0 and rows[selected_index] or nil
  if selected then view.selected = selected.id end
  local detail = selected and selected_detail(player, view, context) or nil
  local detail_box = add(content, {type = "flow", name = PREFIX .. "detail", direction = "vertical"})
  detail_lines(detail_box, selected, detail)

  local actions = add(content, {type = "flow", name = PREFIX .. "actions", direction = "horizontal"})
  add(actions, {type = "button", name = PREFIX .. "open_native", caption = {"mir-browser.open-research"}, enabled = selected ~= nil})
  add(actions, {type = "button", name = PREFIX .. "close", caption = {"mir-browser.close"}})
end

local function create_frame(player, view)
  local screen = player.gui and player.gui.screen
  if not valid(screen) then return nil end
  local frame = add(screen, {
    type = "frame", name = ROOT, direction = "vertical", caption = {"mir-browser.title"},
    tags = {[ROOT_TAG] = true}
  })
  if view.location then frame.location = view.location end

  local filters = add(frame, {type = "flow", name = PREFIX .. "filters", direction = "horizontal"})
  add(filters, {type = "label", name = PREFIX .. "search_label", caption = {"mir-browser.search-label"}})
  add(filters, {type = "textfield", name = PREFIX .. "query", text = view.query})
  add(filters, {type = "drop-down", name = PREFIX .. "family", items = {{"mir-browser.scope-all"}, {"mir-browser.scope-mir"}}, selected_index = view.family == "mir" and 2 or 1})
  add(filters, {type = "label", name = PREFIX .. "status_label", caption = {"mir-browser.filter-status"}})
  add(filters, {type = "drop-down", name = PREFIX .. "status", items = {{"mir-browser.status-all"}, {"mir-browser.status-ready"}, {"mir-browser.status-locked"}, {"mir-browser.status-queued"}}, selected_index = view.status})
  add(frame, {type = "flow", name = PREFIX .. "content", direction = "vertical"})
  return frame
end

-- Dynamic list/detail content is rebuilt under a stable root. In particular,
-- query edits preserve the existing text field, native focus and caret.
local function render(player, view, context, preserve_query)
  context = context or context_for(player.force)
  local frame = owned_root(player)
  if not valid(frame) then
    -- A foreign same-named root is a collision, not a frame this module may
    -- reuse or replace. In particular it must not cause player preferences.
    if valid(named_root(player)) then return nil end
    frame = create_frame(player, view)
  end
  if not valid(frame) then return nil end

  local filters = frame[PREFIX .. "filters"]
  local query = valid(filters) and filters[PREFIX .. "query"] or nil
  if valid(query) and not preserve_query then query.text = view.query end
  local family = valid(filters) and filters[PREFIX .. "family"] or nil
  if valid(family) then family.selected_index = view.family == "mir" and 2 or 1 end
  local status = valid(filters) and filters[PREFIX .. "status"] or nil
  if valid(status) then status.selected_index = view.status end
  update_content(frame, player, view, context)
  set_shortcut(player, true)
  return frame
end

-- Called by the parse-time composition owner. The provider is the sole
-- bridge from the UI host to lifecycle-resolved cap values; it must return a
-- detached plain id-to-nonnegative-integer map for the supplied force.
function M.set_cap_provider(provider)
  if provider ~= nil and type(provider) ~= "function" then
    error("MIR Library cap provider must be a function or nil", 2)
  end
  cap_provider = provider
end

function M.open(player, options)
  if not valid(player) or type(player.index) ~= "number" then return nil end
  local existing = named_root(player)
  if valid(existing) and existing ~= owned_root(player) then return nil end
  local view = view_for(player.index)
  options = type(options) == "table" and options or {}
  if options.query ~= nil then view.query = text(options.query) end
  if options.family == "all" or options.family == "mir" then view.family = options.family end
  local selected = technology_id(options.selected)
  if selected then view.selected = selected end
  return render(player, view)
end

function M.close(player)
  if not valid(player) or type(player.index) ~= "number" then return end
  if not valid(owned_root(player)) then return end
  local view = view_for(player.index)
  destroy_frame(player, view)
end

function M.on_lua_shortcut(event)
  if not event or event.prototype_name ~= SHORTCUT then return end
  local player = player_for(event.player_index)
  if not player then return end
  local existing = named_root(player)
  if valid(existing) then
    if existing == owned_root(player) then M.close(player) end
    return
  end
  M.open(player)
end

function M.on_gui_text_changed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {
    PREFIX .. "query", PREFIX .. "filters", ROOT
  }) then return end
  local view = view_for(player.index)
  view.query = text(element.text)
  view.scroll = 1
  render(player, view, nil, true)
end

function M.on_gui_selection_state_changed(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event and event.player_index)
  if not player then return end
  if element.name == PREFIX .. "family" then
    if not owns_element(player, element, {
      PREFIX .. "family", PREFIX .. "filters", ROOT
    }) then return end
    local view = view_for(player.index)
    view.family = element.selected_index == 2 and "mir" or "all"
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "status" then
    if not owns_element(player, element, {
      PREFIX .. "status", PREFIX .. "filters", ROOT
    }) then return end
    local view = view_for(player.index)
    local status = element.selected_index
    view.status = type(status) == "number" and status >= 1 and status <= 4 and math.floor(status) == status and status or 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "results" then
    if not owns_element(player, element, {
      PREFIX .. "results", PREFIX .. "content", ROOT
    }) then return end
    local view = view_for(player.index)
    local context = context_for(player.force)
    local rows = rows_for(player, view, context)
    local index = element.selected_index
    local row = type(index) == "number" and rows[index] or nil
    if row then
      view.selected = row.id
      view.scroll = index
      render(player, view, context)
    end
  end
end

function M.on_gui_click(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event and event.player_index)
  if not player then return end
  if element.name == PREFIX .. "close" then
    if not owns_element(player, element, {
      PREFIX .. "close", PREFIX .. "actions", PREFIX .. "content", ROOT
    }) then return end
    M.close(player)
    return
  end
  if element.name ~= PREFIX .. "open_native" then return end
  if not owns_element(player, element, {
    PREFIX .. "open_native", PREFIX .. "actions", PREFIX .. "content", ROOT
  }) then return end
  local view = view_for(player.index)
  local selected = technology_id(view.selected)
  if selected == nil then return end
  local technologies = player.force and player.force.technologies
  if technologies == nil then return end
  local ok, technology = pcall(function() return technologies[selected] end)
  if not ok or not valid(technology) then return end
  destroy_frame(player, view)
  if type(player.open_technology_gui) == "function" then player.open_technology_gui(technology) end
end

function M.on_gui_location_changed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {ROOT}) then return end
  local view = view_for(player.index)
  local remembered = location(element.location)
  if remembered then view.location = remembered end
end

function M.on_gui_closed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {ROOT}) then return end
  M.close(player)
end

function M.on_player_removed(event)
  if not event or type(event.player_index) ~= "number" then return end
  local state = existing_state()
  if state then state.players[event.player_index] = nil end
end

-- Lifecycle callbacks deliberately do not initialize player state.  A later
-- explicit open reconstructs the frame from a normalized saved view.
function M.on_init()
end

-- Published 4.7 stored the browser at storage.mir.research_browser and used
-- view schema 3.  Copy a bounded convenience snapshot into a private
-- preservation envelope, whose provenance points back to the untouched
-- published bucket for full fidelity. Migrate only the fields this first
-- Library slice supports. Existing MIR5 views win so a repeated configuration
-- change cannot overwrite a newer choice. This explicit configuration event
-- visits every saved player record (O(P)); it deliberately does not truncate
-- migration candidates.
function M.on_configuration_changed()
  local legacy = legacy_browser_state()
  local legacy_players = legacy and legacy.players
  if type(legacy_players) ~= "table" then return end

  local candidates = {}
  for index, historical_view in pairs(legacy_players) do
    local normalized_index = player_index(index)
    if normalized_index and type(historical_view) == "table" then
      candidates[#candidates + 1] = {index = normalized_index, view = historical_view}
    end
  end
  if #candidates == 0 then return end

  local state = existing_state() or ensure_state()
  local preserved = state.legacy_browser
  if type(preserved) ~= "table" then
    preserved = {
      version = LEGACY_SNAPSHOT_VERSION,
      source = "storage.mir.research_browser",
      authoritative_source = "storage.mir.research_browser",
      players = {},
      snapshot_status = {}
    }
    state.legacy_browser = preserved
  elseif type(preserved.players) ~= "table" then
    preserved.players = {}
  end
  if type(preserved.snapshot_status) ~= "table" then preserved.snapshot_status = {} end

  for _, candidate in ipairs(candidates) do
    local index, historical_view = candidate.index, candidate.view
    if preserved.players[index] == nil then
      local snapshot, status = legacy_snapshot(historical_view)
      preserved.players[index] = snapshot
      preserved.snapshot_status[index] = status
    end
    if type(state.players[index]) ~= "table" then
      state.players[index] = legacy_view_as_private(historical_view)
    end
  end

  -- game.get_player(uint32) and LuaGuiElement child lookup/destroy are
  -- documented by the local 2.1 runtime API.  No player is created here: a
  -- headless native process cannot establish GUI-client evidence.
  for _, candidate in ipairs(candidates) do
    local player = player_for(candidate.index)
    if player then
      local view = local_view(state.players[candidate.index])
      state.players[candidate.index] = view
      rebuild_owned_legacy_root(player, view)
    end
  end
end

-- Load is intentionally read-only: it neither migrates, repairs, nor rebuilds
-- a player view.  Migration belongs to configuration change only.
function M.on_load()
end

-- Root event composition can call this after any library callback. This first
-- slice resolves search synchronously and has no localization dispatcher, so
-- it requests no periodic work while closed or open.
function M.subscription_needs()
  return nil
end

return M

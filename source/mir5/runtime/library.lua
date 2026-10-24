-- Private, first vertical slice of the MIR Research Library.
--
-- The catalogue/model modules own research facts. This module owns only a
-- player's small view preference and GUI construction. Control.lua must route
-- its callbacks explicitly; this file never registers handlers or creates a
-- recurring subscription by itself.
local catalogue = require("research.catalogue")
local settings_catalog = require("research.settings")
-- Configuration resolves MIRSET1 precedence once at control parse time. The
-- Availability view receives its compact stream map rather than resolving a
-- profile while the player opens or filters the Library.
local effective_configuration = require("runtime.configuration")
local profile_codec = require("research.settings_profile")
local library_model = require("presentation.library_model")
local availability = require("presentation.availability")
local target = require("platform.target")
local translation_queue = require("runtime.library_translations")

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
local MAX_HIDDEN = 128
local MAX_PAGE = 30000
local MAX_FAMILY_DESCRIPTORS = 128
local MAX_SETTING_DESCRIPTORS = 2048
local LEGACY_NAMESPACE = "mir"
local LEGACY_BROWSER_KEY = "research_browser"
local LEGACY_ROOT_MARKER = "mir_browser_tabs"
local LEGACY_SNAPSHOT_VERSION = 1
local LEGACY_SNAPSHOT_MAX_DEPTH = 8
local LEGACY_SNAPSHOT_MAX_ENTRIES = 512
local LEGACY_SNAPSHOT_MAX_STRING = 4096
local cap_provider = nil
local TRANSLATION_SCHEMA = 1
local TRANSLATION_MAINTENANCE_TICKS = 61
local TABS = {"research", "queue", "settings", "help"}
local TAB_INDEX = {research = 1, queue = 2, settings = 3, help = 4}

-- Open translation work is saved separately from personal preferences, so a
-- joining client reconnects the same labels, cursor and issued window.
-- Closing a view drops that working cache and retains only issued native IDs.
local translation_caches = {}
local declaration_cache

-- Authored metadata is immutable within a loaded configuration. Build its
-- private copy only for actual UI use; force/research/cap facts stay live.
local function authored_declarations()
  if declaration_cache == nil then declaration_cache = catalogue.declared() end
  return declaration_cache
end

M.translation_maintenance_ticks = TRANSLATION_MAINTENANCE_TICKS
M.native_refresh_ticks = 1

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

local function whole_option(value, minimum, maximum)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    and value == math.floor(value) and value >= minimum and value <= maximum and value or nil
end

local function status_option(value)
  return whole_option(value, 1, 4)
end

local function sort_option(value)
  if value == "progression" or value == "native" or value == "name-asc" or value == "name-desc" then
    return value
  end
  return nil
end

local SORT_INDEX = {
  ["progression"] = 1,
  ["native"] = 2,
  ["name-asc"] = 3,
  ["name-desc"] = 4
}

-- The published browser offered its aggregate choices plus actual authored
-- family descriptors.  These values come only from the compact declaration
-- catalogue; a force's native technologies never create GUI selectors.
local function family_values()
  local values, known = {"mir", "all", "external"}, {mir = true, all = true, external = true}
  local ok, declared = pcall(authored_declarations)
  if not ok or type(declared) ~= "table" or #declared > MAX_FAMILY_DESCRIPTORS then return values, known end
  local extras = {}
  for index = 1, #declared do
    local row = declared[index]
    local family = type(row) == "table" and technology_id(row.family) or nil
    if family and not known[family] then
      if #extras >= MAX_FAMILY_DESCRIPTORS then
        return {"mir", "all", "external"}, {mir = true, all = true, external = true}
      end
      known[family] = true
      extras[#extras + 1] = family
    end
  end
  table.sort(extras)
  for _, family in ipairs(extras) do values[#values + 1] = family end
  return values, known
end

local function family_option(value)
  local _, known = family_values()
  return type(value) == "string" and known[value] and value or nil
end

local function family_from_index(value)
  local values = family_values()
  return whole_option(value, 1, #values) and values[value] or nil
end

local function family_caption(family, native_names)
  if family == "mir" then return {"mir-browser.scope-mir"} end
  if family == "all" then return {"mir-browser.scope-all"} end
  if family == "external" then return {"mir-browser.scope-native"} end
  -- Authored technology names can require localized parameters. Use the
  -- engine's complete name rather than invoking its locale key without them.
  if native_names[family] ~= nil then return native_names[family] end
  return family:gsub("^research_", ""):gsub("[-_]", " "):gsub("^%l", string.upper)
end

local function family_items(values, player)
  local native_names = {}
  for _, row in ipairs(authored_declarations()) do
    local family = type(row) == "table" and technology_id(row.family) or nil
    if family and native_names[family] == nil then
      local ok, name = pcall(function()
        local technology = player.force.technologies[row.id]
        return technology and technology.localised_name or nil
      end)
      if ok then native_names[family] = name end
    end
  end
  local items = {}
  for index, family in ipairs(values) do items[index] = family_caption(family, native_names) end
  return items
end

local function family_index(values, family)
  for index, candidate in ipairs(values) do
    if candidate == family then return index end
  end
  return nil
end

-- Personal hiding remains a view-local filter.  The published third choice
-- showed its terminal availability explanation within Research, rather than
-- constructing a speculative omitted-technology catalogue.
local function visibility_option(value)
  return whole_option(value, 1, 3)
end

local function sort_from_index(value)
  if value == 1 then return "progression" end
  if value == 2 then return "native" end
  if value == 3 then return "name-asc" end
  if value == 4 then return "name-desc" end
  return "progression"
end

local function known_technology(player, id)
  if not valid(player) or id == nil then return nil end
  local ok, technology = pcall(function()
    local force = player.force
    local technologies = force and force.technologies
    return technologies and technologies[id] or nil
  end)
  return ok and valid(technology) and technology or nil
end

-- The published remote browser accepted only a dense, known-technology list.
-- Validate it before changing the saved view so malformed callers cannot hide
-- arbitrary names or turn a bounded selection into an unbounded native scan.
local function hidden_option(player, values)
  if type(values) ~= "table" then return nil end
  local entries, count, valid_input = {}, 0, true
  local scanned = pcall(function()
    for index, id in pairs(values) do
      if not whole_option(index, 1, MAX_HIDDEN) or technology_id(id) == nil or entries[index] ~= nil then
        valid_input = false
        return
      end
      count = count + 1
      if count > MAX_HIDDEN then
        valid_input = false
        return
      end
      entries[index] = id
    end
  end)
  if not scanned or not valid_input then return nil end

  local hidden, seen = {}, {}
  for index = 1, count do
    local id = entries[index]
    if id == nil or seen[id] or known_technology(player, id) == nil then return nil end
    seen[id], hidden[id] = true, true
  end
  return hidden
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
    family = raw.family ~= nil and raw.family or "mir",
    mode = raw.mode,
    status = raw.status,
    page = raw.page,
    sort = raw.sort,
    stable_sort = raw.stable_sort,
    visibility = raw.visibility,
    hidden = raw.hidden,
    selected = technology_id(raw.selected),
    tab = raw.tab,
    settings_scope = raw.settings_scope,
    settings_query = text(raw.settings_query),
    setting_selected = technology_id(raw.setting_selected),
    open = raw.open == true,
    refresh_pending = raw.refresh_pending == true,
    location = location(raw.location),
    scroll = type(raw.scroll) == "number" and raw.scroll > 0 and math.floor(raw.scroll) or 1
  }
  -- The data-only model independently normalizes its own read surface. Keep
  -- this UI-owned record narrow and copy back only fields this host owns.
  local normalized = library_model.normalize({
    search = value.query,
    family = value.family,
    mode = value.mode,
    status = value.status,
    page = value.page,
    sort = value.sort,
    stable_sort = value.stable_sort,
    visibility = value.visibility,
    hidden = value.hidden,
    selected = value.selected
  })
  if type(normalized) == "table" then
    value.query = text(normalized.search or value.query)
    value.family = family_option(normalized.family) or "mir"
    value.mode = whole_option(normalized.mode, 1, 3) or 1
    value.status = type(normalized.status) == "number" and normalized.status or 1
    value.page = type(normalized.page) == "number" and normalized.page or 1
    value.sort = type(normalized.sort) == "string" and normalized.sort or "progression"
    value.stable_sort = type(normalized.stable_sort) == "string" and normalized.stable_sort or "progression"
    value.visibility = visibility_option(normalized.visibility) or 1
    value.hidden = type(normalized.hidden) == "table" and normalized.hidden or {}
    value.selected = type(normalized.selected) == "string" and normalized.selected or nil
  end
  value.tab = TAB_INDEX[value.tab] and value.tab or "research"
  value.settings_scope = value.settings_scope == "options" and "options" or "research"
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

local function whole_number(value, minimum)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    and value == math.floor(value) and value >= minimum
end

-- The issued-request ledger retains its original schema. The optional working
-- map adds schema-1 open-view caches containing plain bounded translation
-- data only; no LuaObjects, native research facts or Generator state is saved.
local function existing_translation_ledger(state)
  local value = type(state) == "table" and state.translations or nil
  if type(value) ~= "table" or value.schema ~= TRANSLATION_SCHEMA
      or not whole_number(value.next_epoch, 0)
      or type(value.active) ~= "table" or type(value.retired) ~= "table" then
    return nil
  end
  return value
end

-- Unknown or malformed private state may still contain issued native request
-- IDs. A writable view must leave it intact and decline translation issuance;
-- only an absent sidecar may receive this schema.
local function ensure_translation_ledger(state)
  local value = existing_translation_ledger(state)
  if value then return value end
  if state.translations ~= nil then return nil end
  value = {
    schema = TRANSLATION_SCHEMA,
    next_epoch = 0,
    active = {},
    retired = {}
  }
  state.translations = value
  return value
end

local function ordered_player_indices(rows)
  local indices = {}
  for index in pairs(rows) do
    if whole_number(index, 1) then indices[#indices + 1] = index end
  end
  table.sort(indices)
  return indices
end

local function reconnect_translation_caches()
  translation_caches = {}
  local state = type(storage) == "table" and storage[STORAGE_KEY] or nil
  local ledger = existing_translation_ledger(state)
  local working = ledger and ledger.working
  if type(working) ~= "table" then return end
  for index, saved in pairs(working) do
    if whole_number(index, 1) and type(saved) == "table" and saved.schema == 1
        and technology_id(saved.family) ~= nil and type(saved.scope) == "table"
        and saved.scope.player_index == index
        and translation_queue.labels(saved.cache, saved.scope) ~= nil then
      translation_caches[index] = {
        player_index = index, scope = saved.scope, family = saved.family,
        cache = saved.cache, ledger = ledger
      }
    end
  end
end

local function entry_pending(entry)
  return type(entry) == "table" and type(entry.pending) == "table" and #entry.pending > 0
    and entry.pending or nil
end

local function next_translation_epoch(ledger)
  local previous = whole_number(ledger.next_epoch, 0) and ledger.next_epoch or 0
  ledger.next_epoch = previous + 1
  return ledger.next_epoch
end

local function scope_for(player, epoch)
  local force = player and player.force
  if not valid(player) or not whole_number(player.index, 1) or type(player.locale) ~= "string"
      or not whole_number(epoch, 0) or force == nil then
    return nil
  end
  local force_index = force and force.index
  if not whole_number(force_index, 1) then return nil end
  return {
    player_index = player.index,
    locale = player.locale,
    force_index = force_index,
    generation = epoch
  }
end

local function same_translation_scope(left, right)
  return type(left) == "table" and type(right) == "table"
    and left.player_index == right.player_index and left.locale == right.locale
    and left.force_index == right.force_index and left.generation == right.generation
end

-- Authored-only family views translate only declared technologies that exist
-- in this force. All/external views scan the caller's current native force
-- once per family/scope change and keep a bounded deterministic request order.
local function ordered_translation_ids(player, family)
  local ok, declared = pcall(authored_declarations)
  if not ok or type(declared) ~= "table" then return nil end
  local force = player and player.force
  local technologies = force and force.technologies
  if technologies == nil then return nil end
  local ids, seen = {}, {}
  local function add_id(id)
    if type(id) ~= "string" or id == "" or #id > translation_queue.label_limit then return false end
    if seen[id] then return true end
    if #ids >= translation_queue.catalogue_limit then return false end
    seen[id] = true
    ids[#ids + 1] = id
    return true
  end
  local function technology_exists(id)
    local found, technology = pcall(function() return technologies[id] end)
    return found and valid(technology)
  end

  local declarations = {}
  for _, row in ipairs(declared) do
    if type(row) ~= "table" or type(row.id) ~= "string" or row.id == ""
        or #row.id > translation_queue.label_limit then return nil end
    declarations[row.id] = row
    local declared_family = technology_id(row.family) or "mir"
    local include_declared = family == "all"
      or family == "mir" and declared_family ~= "external"
      or family == declared_family
    if include_declared and technology_exists(row.id) and not add_id(row.id) then return nil end
  end
  if family ~= "all" and family ~= "external" then return ids end

  local native, overflow = {}, false
  local scanned_ok = pcall(function()
    for id, technology in pairs(technologies) do
      if not valid(technology) or type(id) ~= "string" or id == "" or #id > translation_queue.label_limit then
        overflow = true
        return
      end
      native[#native + 1] = id
      if #native > translation_queue.catalogue_limit then
        overflow = true
        return
      end
    end
  end)
  if not scanned_ok or overflow then return nil end
  table.sort(native)
  for _, id in ipairs(native) do
    local declaration = declarations[id]
    local declared_family = declaration and technology_id(declaration.family) or "mir"
    if family ~= "external" or declaration == nil or declared_family == "external" then
      if not add_id(id) then return nil end
    end
  end
  return ids
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
    mode = value.mode,
    status = value.status,
    page = value.page,
    sort = value.sort,
    stable_sort = value.stable_sort,
    visibility = value.visibility,
    hidden = value.hidden,
    selected = value.selected,
    tab = value.tab,
    settings_scope = value.settings_scope,
    settings_query = value.settings_search,
    setting_selected = value.setting_selection,
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
    mode = view.mode,
    status = view.status,
    page = view.page,
    sort = view.sort,
    stable_sort = view.stable_sort,
    visibility = view.visibility,
    hidden = view.hidden,
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

local EMPTY_TRANSLATIONS = {}

local function cache_from_pending(pending)
  if type(pending) ~= "table" or #pending == 0 then return nil end
  local first = pending[1]
  if type(first) ~= "table" or type(first.scope) ~= "table" then return nil end
  local cache = translation_queue.new(first.scope)
  if cache == nil or not translation_queue.hydrate_pending(cache, pending) then return nil end
  return cache
end

local function sync_issued_cache(record)
  if type(record) ~= "table" or type(record.ledger) ~= "table" then return false end
  local pending = translation_queue.export_pending(record.cache)
  if pending == nil then return false end
  local working = record.ledger.working
  if working == nil then
    working = {}
    record.ledger.working = working
  end
  if type(working) ~= "table" then return false end
  local previous = working[record.player_index]
  if previous ~= nil and (type(previous) ~= "table" or previous.schema ~= 1
      or previous.cache ~= record.cache) then return false end
  working[record.player_index] = {
    schema = 1, scope = record.scope, family = record.family, cache = record.cache
  }
  if #pending == 0 then
    record.ledger.active[record.player_index] = nil
  else
    record.ledger.active[record.player_index] = {
      epoch = record.scope.generation,
      pending = pending
    }
  end
  return true
end

local function discard_translation_cache(index)
  local record = translation_caches[index]
  if record then sync_issued_cache(record) end
  local ledger = record and record.ledger
  local working = ledger and ledger.working
  if record and type(working) == "table" then
    local saved = working[index]
    if type(saved) ~= "table" or saved.schema ~= 1 or saved.cache ~= record.cache then
      translation_caches[index] = nil
      return
    end
    working[index] = nil
    if next(working) == nil then ledger.working = nil end
  end
  translation_caches[index] = nil
end

local function open_translation_cache(player, view)
  local index = player and player.index
  if not whole_number(index, 1) then return nil end
  local family = type(view) == "table" and family_option(view.family) or "mir"
  local retained = translation_caches[index]
  local same_live_scope = retained and retained.scope and retained.scope.locale == player.locale
    and retained.scope.force_index == (player.force and player.force.index)

  if retained and same_live_scope and retained.family == family then
    -- Ordered identities are local immutable presentation data. Reusing this
    -- record prevents a native catalogue traversal on every GUI render.
    return retained
  end

  if retained and same_live_scope then
    -- Family selection changes the requester-visible catalogue. Retain engine
    -- IDs already issued, but replace all unissued work under a fresh caller
    -- epoch so former responses cannot label the new view.
    local ids = ordered_translation_ids(player, family)
    local ledger = retained.ledger
    local scope = ledger and scope_for(player, next_translation_epoch(ledger)) or nil
    if ids == nil or scope == nil or not translation_queue.prepare(retained.cache, scope, ids) then
      discard_translation_cache(index)
      return nil
    end
    retained.scope, retained.family = scope, family
    sync_issued_cache(retained)
    return retained
  end
  if retained then discard_translation_cache(index) end

  local state = ensure_state()
  local ledger = ensure_translation_ledger(state)
  if ledger == nil then return nil end
  if ledger.working ~= nil and type(ledger.working) ~= "table" then return nil end
  -- A remaining record was not reconnected by this implementation. Preserve
  -- that unknown working protocol rather than overwriting its issued rights.
  if ledger.working and ledger.working[index] ~= nil then return nil end
  -- A removed player can have an old engine request in flight. Preserve an
  -- unfamiliar retired entry rather than deleting it and reusing this index.
  if ledger.retired[index] ~= nil then return nil end

  -- A nonnil active record is an issued native window until it fully validates
  -- through the pure ledger hydrator. Do not discard it and create 16 more.
  local active = ledger.active[index]
  local pending = nil
  if active ~= nil then
    pending = entry_pending(active)
    if pending == nil then return nil end
  end

  local scope = scope_for(player, next_translation_epoch(ledger))
  local ids = ordered_translation_ids(player, family)
  local cache = scope and ids and translation_queue.new(scope) or nil
  if cache == nil or not translation_queue.prepare(cache, scope, ids) then return nil end
  if pending and not translation_queue.hydrate_pending(cache, pending) then return nil end

  local record = {player_index = index, scope = scope, family = family, cache = cache, ledger = ledger}
  translation_caches[index] = record
  return record
end

local function translated_labels(record)
  if type(record) ~= "table" then return EMPTY_TRANSLATIONS end
  return translation_queue.labels(record.cache, record.scope) or EMPTY_TRANSLATIONS
end

local function current_tick()
  local value = game and game.tick
  return whole_number(value, 0) and value or 0
end

local function request_translation(player, key)
  if not valid(player) or player.connected ~= true or type(player.request_translation) ~= "function" then return nil end
  local ok, request_id = pcall(function()
    local force = player.force
    local technologies = force and force.technologies
    local technology = technologies and technologies[key] or nil
    if not valid(technology) then return nil end
    return player.request_translation(technology.localised_name)
  end)
  return ok and request_id or nil
end

local function dispatch_translations(player, record)
  if type(record) ~= "table" or player.connected ~= true or not valid(owned_root(player)) then return end
  translation_queue.dispatch(record.cache, record.scope, current_tick(), function(key)
    return request_translation(player, key)
  end)
  sync_issued_cache(record)
end

local function rows_for(player, view, context, labels)
  local rows = library_model.rows(player.force, authored_declarations(), model_view(view), labels or EMPTY_TRANSLATIONS, context)
  if type(rows) ~= "table" then return {} end
  return rows
end

local function selected_detail(player, view, context, labels)
  if not view.selected then return nil end
  return library_model.detail(player.force, authored_declarations(), model_view(view), labels or EMPTY_TRANSLATIONS, context)
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
  view.open, view.refresh_pending = false, false
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
  local element = parent.add(spec)
  -- Bound only this owned GUI subtree. Native labels wrap inside their
  -- container; no world/catalogue work is involved in sizing a requested view.
  local parent_style = spec.name ~= ROOT and parent.style or nil
  local style = element.style
  local width = parent_style and parent_style.maximal_width
  if style and type(width) == "number" and width > 0 then
    if spec.type == "label" then
      style.single_line = false
      style.maximal_width = width
    elseif spec.type == "flow" or spec.type == "scroll-pane"
        or spec.type == "tabbed-pane" or spec.type == "list-box" then
      style.maximal_width = width
      style.horizontally_stretchable = true
    end
  end
  return element
end

local function research_seconds(cost)
  if type(cost) ~= "table" then return "?" end
  if type(cost.energy) == "number" then return cost.energy / 60 end
  return cost.time or cost[2] or "?"
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
    add(parent, {type = "label", name = PREFIX .. "detail_cost", caption = {"mir-browser.research-cost", tostring(type(detail.cost) == "table" and (detail.cost.count or detail.cost[1] or "?") or detail.cost), tostring(research_seconds(detail.cost))}})
    if type(detail.cost) == "table" and type(detail.cost.ingredients) == "table"
        and #detail.cost.ingredients > 0 then
      add(parent, {type = "label", name = PREFIX .. "detail_science", caption = {"mir-browser.science"}})
      for index, ingredient in ipairs(detail.cost.ingredients) do
        if type(ingredient) == "table" then
          add(parent, {type = "label", name = PREFIX .. "science_" .. index,
            caption = {"mir-browser.science-ingredient", tostring(ingredient.name or "?"), tostring(ingredient.amount or "?")}})
        end
      end
    end
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
      local change = type(effect) == "table" and (effect.change or effect.modifier) or nil
      local text_value = tostring(effect_type or "")
      if effect_type == "change-recipe-productivity" and type(change) == "number" then
        text_value = {"mir-browser.productivity-increment", string.format("%.6g", change * 100)}
      elseif change ~= nil then
        text_value = text_value .. " " .. tostring(change)
        if type(effect) == "table" and effect.ammo_category then text_value = text_value .. " " .. effect.ammo_category end
        if type(effect) == "table" and effect.turret_id then text_value = text_value .. " " .. effect.turret_id end
      elseif type(effect) == "table" and effect.recipe then
        text_value = text_value .. " " .. effect.recipe
      end
      add(parent, {type = "label", name = PREFIX .. "effect_" .. index, caption = text_value})
    end
  end
end

local function tab_content(frame, tab)
  local tabs = frame and frame[PREFIX .. "tabs"]
  return valid(tabs) and tabs[PREFIX .. tab .. "_content"] or nil
end

local function update_research_content(content, player, view, context, translations)
  if not valid(content) then return end
  content.clear()

  local rows = rows_for(player, view, context, translations)
  local item_labels = {}
  for index, row in ipairs(rows) do item_labels[index] = caption(row) end
  local selected_index = row_index(rows, view.selected) or 0
  local results = add(content, {type = "list-box", name = PREFIX .. "results", items = item_labels, selected_index = selected_index})
  if view.scroll and view.scroll <= #item_labels and type(results.scroll_to_item) == "function" then
    results.scroll_to_item(view.scroll, "top-third")
  end
  add(content, {type = "label", name = PREFIX .. "count", caption = {"mir-browser.count", #rows}})

  local selected = selected_index > 0 and rows[selected_index] or nil
  if selected then view.selected = selected.id end
  local detail = selected and selected_detail(player, view, context, translations) or nil
  local detail_box = add(content, {type = "flow", name = PREFIX .. "detail", direction = "vertical"})
  detail_lines(detail_box, selected, detail)

  local actions = add(content, {type = "flow", name = PREFIX .. "actions", direction = "horizontal"})
  add(actions, {type = "button", name = PREFIX .. "open_native", caption = {"mir-browser.open-research"}, enabled = selected ~= nil})
  add(actions, {type = "button", name = PREFIX .. "close", caption = {"mir-browser.close"}})
end

local function setting_value(startup, name, fallback)
  local ok, value = pcall(function()
    local entry = startup and startup[name]
    return entry and entry.value
  end)
  if ok and value ~= nil then return value end
  return fallback
end

local function setting_display(name, value)
  if type(value) == "boolean" then return {"mir-browser.setting-" .. (value and "on" or "off")} end
  if type(value) == "number" and value == 0 and type(name) == "string"
      and name:find("%-max%-level%-", 1) then
    return {"mir-browser.setting-unlimited"}
  end
  return tostring(value)
end

local function setting_catalogue()
  local ok, names = pcall(settings_catalog.registered_names)
  if not ok or type(names) ~= "table" or #names > MAX_SETTING_DESCRIPTORS then return nil end

  local prototypes, by_name = {}, {}
  local prototypes_ok, all_prototypes = pcall(settings_catalog.prototypes)
  if prototypes_ok and type(all_prototypes) == "table" then
    for _, prototype in ipairs(all_prototypes) do
      if type(prototype) == "table" and type(prototype.name) == "string" then
        prototypes[prototype.name] = prototype
      end
    end
  end

  local startup = settings and settings.startup or nil
  local effective_ok, effective = pcall(settings_catalog.effective_values, startup, helpers)
  if not effective_ok or type(effective) ~= "table" then return nil end

  local imported = nil
  local import_name = settings_catalog.import_setting_name
  local imported_text = setting_value(startup, import_name, "")
  if type(imported_text) == "string" and imported_text ~= "" then
    local decoded_ok, profile = pcall(profile_codec.decode, imported_text, helpers)
    if decoded_ok and type(profile) == "table" and type(profile.settings) == "table" then imported = profile.settings end
  end

  local groups, ordered = {}, {}
  for index, name in ipairs(names) do
    if type(name) ~= "string" or name == "" or by_name[name] then return nil end
    by_name[name] = true
    local spec = settings_catalog.spec(name)
    if type(spec) ~= "table" then return nil end
    local stream = type(spec.stream) == "table" and spec.stream or nil
    local scope = stream and "research" or "options"
    local key = stream and type(stream.key) == "string" and stream.key or name
    local group = groups[key]
    if group == nil then
      local title = stream and stream.technology_locale or nil
      if type(title) == "string" then title = {title} end
      group = {key = key, scope = scope, title = title or (prototypes[name] and prototypes[name].localised_name) or name,
        fields = {}, search = key .. " " .. name}
      groups[key], ordered[#ordered + 1] = group, group
    end
    local default = spec.default_value
    local direct = setting_value(startup, name, default)
    local source = "direct"
    if imported and startup and startup[name] and imported[name] ~= nil then
      local accepted = settings_catalog.validate_value(name, imported[name])
      if accepted then source = "mirset1" end
    end
    group.fields[#group.fields + 1] = {
      name = name,
      caption = (prototypes[name] and prototypes[name].localised_name) or name,
      description = prototypes[name] and prototypes[name].localised_description or nil,
      effective = effective[name], direct = direct, default = default, source = source,
      order = spec.field_index or index
    }
    group.search = group.search .. " " .. name
  end
  if import_name and not by_name[import_name] and prototypes[import_name] then
    local group = {key = import_name, scope = "options", title = prototypes[import_name].localised_name or import_name,
      search = import_name, fields = {{name = import_name, caption = prototypes[import_name].localised_name or import_name,
        description = prototypes[import_name].localised_description, effective = setting_value(startup, import_name, ""),
        direct = setting_value(startup, import_name, ""), default = prototypes[import_name].default_value, source = "direct", order = 1}}}
    groups[import_name], ordered[#ordered + 1] = group, group
  end
  for _, group in ipairs(ordered) do
    table.sort(group.fields, function(left, right)
      if left.order ~= right.order then return left.order < right.order end
      return left.name < right.name
    end)
  end
  table.sort(ordered, function(left, right) return left.key < right.key end)
  return ordered
end

local function setting_search_matches(group, query)
  if query == "" then return true end
  local haystack = group.search:lower():gsub("[-_]", " ")
  return haystack:find(query:lower():gsub("[-_]", " "), 1, true) ~= nil
end

local function update_settings_content(content, view, preserve_query)
  if not valid(content) then return end
  local toolbar = content[PREFIX .. "settings_toolbar"]
  if not valid(toolbar) then
    toolbar = add(content, {type = "flow", name = PREFIX .. "settings_toolbar", direction = "horizontal"})
    add(toolbar, {type = "button", name = PREFIX .. "settings_research", caption = {"mir-browser.settings-scope-research"}})
    add(toolbar, {type = "button", name = PREFIX .. "settings_options", caption = {"mir-browser.settings-scope-options"}})
  end
  local query = content[PREFIX .. "settings_query"]
  if not valid(query) then
    query = add(content, {type = "textfield", name = PREFIX .. "settings_query", text = view.settings_query})
  elseif not preserve_query then
    query.text = view.settings_query
  end
  local dynamic = content[PREFIX .. "settings_dynamic"]
  if not valid(dynamic) then dynamic = add(content, {type = "flow", name = PREFIX .. "settings_dynamic", direction = "vertical"}) end
  dynamic.clear()

  local groups = setting_catalogue()
  if groups == nil then
    add(dynamic, {type = "label", name = PREFIX .. "settings_unavailable", caption = {"mir-browser.detail-unavailable", "settings"}})
    return
  end
  local visible, items = {}, {}
  for _, group in ipairs(groups) do
    if group.scope == view.settings_scope and setting_search_matches(group, view.settings_query) then
      visible[#visible + 1], items[#items + 1] = group, group.title
    end
  end
  local selected_index = 0
  for index, group in ipairs(visible) do if group.key == view.setting_selected then selected_index = index; break end end
  if selected_index == 0 and #visible > 0 then selected_index, view.setting_selected = 1, visible[1].key end
  local list = add(dynamic, {type = "list-box", name = PREFIX .. "settings_list", items = items, selected_index = selected_index})
  add(dynamic, {type = "label", name = PREFIX .. "settings_count", caption = {"mir-browser.settings-count", #visible}})
  local detail = add(dynamic, {type = "flow", name = PREFIX .. "settings_detail", direction = "vertical"})
  local selected = visible[selected_index]
  if selected == nil then
    add(detail, {type = "label", name = PREFIX .. "settings_empty", caption = {"mir-browser.settings-empty"}})
    return
  end
  add(detail, {type = "label", name = PREFIX .. "settings_title", caption = selected.title})
  add(detail, {type = "label", name = PREFIX .. "settings_scope", caption = {"mir-browser.scope-startup"}})
  add(detail, {type = "label", name = PREFIX .. "settings_effective", caption = {"mir-browser.effective-values"}})
  for index, field in ipairs(selected.fields) do
    local name = PREFIX .. "setting_" .. index
    add(detail, {type = "label", name = name .. "_name", caption = field.caption, tooltip = field.description})
    add(detail, {type = "label", name = name .. "_value", caption = setting_display(field.name, field.effective),
      tooltip = {"mir-browser.setting-provenance", setting_display(field.name, field.direct),
        setting_display(field.name, field.default), {"mir-browser.source-" .. field.source}}})
  end
  add(detail, {type = "label", name = PREFIX .. "settings_source", caption = {"mir-browser.configuration-source"}})
end

local function queue_name(entry)
  if type(entry) == "string" then return technology_id(entry) end
  local ok, name = pcall(function() return entry and entry.name end)
  return ok and technology_id(name) or nil
end

local function queue_entries(force)
  local ok, queue = pcall(function() return force and force.research_queue end)
  if not ok or queue == nil then return {} end
  local result = {}
  local complete = pcall(function()
    for index, entry in ipairs(queue) do
      if index > MAX_PAGE then error("MIR Library queue limit") end
      local id = queue_name(entry)
      if id then result[#result + 1] = id end
    end
  end)
  return complete and result or {}
end

local function update_queue_content(content, player, view)
  if not valid(content) then return end
  content.clear()
  add(content, {type = "label", name = PREFIX .. "queue_guidance", caption = {"mir-browser.native-queue-guidance"}})
  add(content, {type = "button", name = PREFIX .. "queue_open_native", caption = {"mir-browser.open-research"}})
  local ids, items = queue_entries(player.force), {}
  for index, id in ipairs(ids) do
    local technology = known_technology(player, id)
    items[index] = technology and technology.localised_name or id
  end
  local selected_index = 0
  for index, id in ipairs(ids) do if id == view.selected then selected_index = index; break end end
  add(content, {type = "list-box", name = PREFIX .. "queue_list", items = items, selected_index = selected_index})
  if #items == 0 then add(content, {type = "label", name = PREFIX .. "queue_empty", caption = {"mir-browser.queue-empty"}}) end
end

local function update_availability_content(content, player, view)
  if not valid(content) then return end
  content.clear()
  -- This bounded view has no compiler ledger and no native catalogue pass. It
  -- presents only the authored terminal explanations selected by exact active
  -- mod and named native-owner facts.
  local active_mods = script and script.active_mods or {}
  local effective_streams = type(effective_configuration) == "table" and effective_configuration.streams or nil
  local rows = availability.rows(active_mods, target, player and player.force, view and view.query, effective_streams)
  if #rows == 0 then
    add(content, {type = "label", name = PREFIX .. "availability_empty", caption = {"mir-browser.availability-empty"}})
    return
  end
  for index, row in ipairs(rows) do
    add(content, {
      type = "label",
      name = PREFIX .. "availability_" .. index,
      caption = {"mir-browser.availability-entry",
        {"technology-name.more-infinite-research." .. row.family},
        {"mir-browser.availability-" .. row.reason}}
    })
  end
end

local function update_help_content(content)
  if not valid(content) then return end
  content.clear()
  add(content, {type = "label", name = PREFIX .. "help_summary", caption = {"mir-browser.help-summary"}})
  add(content, {type = "label", name = PREFIX .. "help_queue", caption = {"mir-browser.native-queue-guidance"}})
end

local function create_frame(player, view)
  local screen = player.gui and player.gui.screen
  if not valid(screen) then return nil end
  local frame = add(screen, {
    type = "frame", name = ROOT, direction = "vertical", caption = {"mir-browser.title"},
    tags = {[ROOT_TAG] = true}
  })
  local resolution, scale = player.display_resolution, player.display_scale
  scale = type(scale) == "number" and scale > 0 and scale or 1
  local width = math.min(1000, math.max(1, (resolution and resolution.width or 1280) / scale - 32))
  local height = math.min(800, math.max(1, (resolution and resolution.height or 720) / scale - 32))
  if frame.style then
    frame.style.width, frame.style.height = width, height
    frame.style.maximal_width = width
  end
  if view.location then frame.location = view.location
  elseif type(frame.auto_center) == "function" then frame.auto_center() end

  local pairs_per_row = width >= 800 and 2 or 1
  local filters = add(frame, {type = "table", name = PREFIX .. "filters", column_count = 2 * pairs_per_row})
  add(filters, {type = "label", name = PREFIX .. "search_label", caption = {"mir-browser.search-label"}})
  add(filters, {type = "textfield", name = PREFIX .. "query", text = view.query})
  add(filters, {type = "label", name = PREFIX .. "family_label", caption = {"mir-browser.filter-scope"}})
  local families = family_values()
  add(filters, {type = "drop-down", name = PREFIX .. "family", items = family_items(families, player),
    selected_index = family_index(families, view.family) or 1})
  add(filters, {type = "label", name = PREFIX .. "visibility_label", caption = {"mir-browser.visibility"}})
  add(filters, {type = "drop-down", name = PREFIX .. "visibility", items = {
    {"mir-browser.visibility-normal"}, {"mir-browser.visibility-hidden"}, {"mir-browser.not-added"}
  }, selected_index = view.visibility})
  add(filters, {type = "label", name = PREFIX .. "mode_label", caption = {"mir-browser.filter-level"}})
  add(filters, {type = "drop-down", name = PREFIX .. "mode", items = {
    {"mir-browser.all"}, {"mir-browser.finite"}, {"mir-browser.infinite"}
  }, selected_index = view.mode})
  add(filters, {type = "label", name = PREFIX .. "status_label", caption = {"mir-browser.filter-status"}})
  add(filters, {type = "drop-down", name = PREFIX .. "status", items = {{"mir-browser.status-all"}, {"mir-browser.status-ready"}, {"mir-browser.status-locked"}, {"mir-browser.status-queued"}}, selected_index = view.status})
  add(filters, {type = "label", name = PREFIX .. "sort_label", caption = {"mir-browser.filter-order"}})
  add(filters, {type = "drop-down", name = PREFIX .. "sort", items = {
    {"mir-browser.order-progression"}, {"mir-browser.order-native"},
    {"mir-browser.order-name-asc"}, {"mir-browser.order-name-desc"}
  }, selected_index = SORT_INDEX[view.sort] or 1})
  for _, field in ipairs({"query", "family", "visibility", "mode", "status", "sort"}) do
    local control = filters[PREFIX .. field]
    if control.style then control.style.width = math.min(280, math.max(100, width / pairs_per_row - 175)) end
  end
  local tabs = add(frame, {type = "tabbed-pane", name = PREFIX .. "tabs"})
  if tabs.style then tabs.style.maximal_width = math.max(1, width - 32) end
  for _, tab_name in ipairs(TABS) do
    local tab = add(tabs, {type = "tab", name = PREFIX .. "tab_" .. tab_name,
      caption = {"mir-browser." .. (tab_name == "queue" and "queue-tab" or tab_name)}})
    local content = add(tabs, {type = "scroll-pane", name = PREFIX .. tab_name .. "_content",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
    if content.style then
      content.style.width = math.max(1, width - 48)
      content.style.maximal_width = math.max(1, width - 48)
      content.style.height = math.max(1, height - (pairs_per_row == 2 and 230 or 350))
    end
    tabs.add_tab(tab, content)
  end
  tabs.selected_tab_index = TAB_INDEX[view.tab] or 1
  return frame
end

-- Dynamic list/detail content is rebuilt under a stable root. In particular,
-- query edits preserve the existing text field, native focus and caret.
local function render(player, view, context, preserve_query)
  if not valid(player) or player.connected ~= true then return nil end
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
  if valid(filters) then filters.visible = view.tab == "research" end
  local query = valid(filters) and filters[PREFIX .. "query"] or nil
  if valid(query) and not preserve_query then query.text = view.query end
  local family = valid(filters) and filters[PREFIX .. "family"] or nil
  local families = family_values()
  local selected_family = family_index(families, view.family)
  if selected_family == nil then
    view.family, selected_family = "mir", family_index(families, "mir") or 1
  end
  if valid(family) then
    family.items = family_items(families, player)
    family.selected_index = selected_family
  end
  local visibility = valid(filters) and filters[PREFIX .. "visibility"] or nil
  if valid(visibility) then visibility.selected_index = view.visibility end
  local mode = valid(filters) and filters[PREFIX .. "mode"] or nil
  if valid(mode) then mode.selected_index = view.mode end
  local status = valid(filters) and filters[PREFIX .. "status"] or nil
  if valid(status) then status.selected_index = view.status end
  local sort = valid(filters) and filters[PREFIX .. "sort"] or nil
  if valid(sort) then sort.selected_index = SORT_INDEX[view.sort] or 1 end
  local tabs = frame[PREFIX .. "tabs"]
  if valid(tabs) then tabs.selected_tab_index = TAB_INDEX[view.tab] or 1 end
  local content = tab_content(frame, view.tab)
  if view.tab == "research" and view.visibility == 3 then
    discard_translation_cache(player.index)
    update_availability_content(content, player, view)
  elseif view.tab == "research" then
    local translations = open_translation_cache(player, view)
    update_research_content(content, player, view, context, translated_labels(translations))
    dispatch_translations(player, translations)
  else
    -- A closed Research tab must not retain a local catalogue or spend more
    -- translation work. Issued IDs stay in the small durable ledger.
    discard_translation_cache(player.index)
    if view.tab == "settings" then
      update_settings_content(content, view, preserve_query)
    elseif view.tab == "queue" then
      update_queue_content(content, player, view)
    else
      update_help_content(content)
    end
  end
  set_shortcut(player, true)
  view.open = true
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
  if not valid(player) or player.connected ~= true or type(player.index) ~= "number" then return nil end
  local existing = named_root(player)
  if valid(existing) and existing ~= owned_root(player) then return nil end
  local view = view_for(player.index)
  options = type(options) == "table" and options or {}
  local reset_page = false
  if options.tab == "availability" then
    view.tab, view.visibility, reset_page = "research", 3, true
  elseif TAB_INDEX[options.tab] then
    view.tab = options.tab
  end
  if options.settings_scope == "research" or options.settings_scope == "options" then
    view.settings_scope, view.setting_selected = options.settings_scope, nil
  end
  if type(options.settings_search) == "string" then
    view.settings_query, view.setting_selected = text(options.settings_search), nil
  end
  if type(options.query) == "string" then
    view.query, reset_page = text(options.query), true
  end
  local family = family_option(options.family)
  if family then
    view.family, reset_page = family, true
  end
  local mode = whole_option(options.mode, 1, 3)
  if mode then view.mode, reset_page = mode, true end
  local status = status_option(options.status)
  if status then view.status, reset_page = status, true end
  local visibility = visibility_option(options.visibility)
  if visibility then view.visibility, reset_page = visibility, true end
  local sort = sort_option(options.sort)
  if sort then
    view.sort, reset_page = sort, true
    if sort == "progression" or sort == "native" then view.stable_sort = sort end
  end
  local selected = technology_id(options.selected)
  if selected and known_technology(player, selected) then
    view.selected, reset_page = selected, true
  end
  if options.hidden ~= nil then
    local hidden = hidden_option(player, options.hidden)
    if hidden then view.hidden, reset_page = hidden, true end
  end
  local page = whole_option(options.page, 1, MAX_PAGE)
  if page then
    -- The current list remains continuous, as the shipped browser's own GUI
    -- did.  Retaining a valid page preserves remote and saved-view semantics.
    view.page = page
  elseif reset_page then
    view.page = 1
  end
  if reset_page then view.scroll = 1 end
  return render(player, view)
end

function M.close(player)
  if not valid(player) or type(player.index) ~= "number" then return end
  if not valid(owned_root(player)) then return end
  local view = view_for(player.index)
  if destroy_frame(player, view) then discard_translation_cache(player.index) end
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
  if not player then return end
  if element.name == PREFIX .. "query" then
    if not owns_element(player, element, {PREFIX .. "query", PREFIX .. "filters", ROOT}) then return end
    local view = view_for(player.index)
    view.query, view.page, view.scroll = text(element.text), 1, 1
    render(player, view, nil, true)
  elseif element.name == PREFIX .. "settings_query" then
    if not owns_element(player, element, {
      PREFIX .. "settings_query", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    view.settings_query, view.setting_selected = text(element.text), nil
    render(player, view, nil, true)
  end
end

function M.on_gui_selected_tab_changed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {PREFIX .. "tabs", ROOT}) then return end
  local tab = TABS[whole_option(element.selected_tab_index, 1, #TABS) or 0]
  if tab == nil then return end
  local view = view_for(player.index)
  if view.tab == tab then return end
  view.tab = tab
  render(player, view)
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
    local family = family_from_index(element.selected_index)
    if family == nil then return end
    view.family = family
    view.page = 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "visibility" then
    if not owns_element(player, element, {
      PREFIX .. "visibility", PREFIX .. "filters", ROOT
    }) then return end
    local visibility = visibility_option(element.selected_index)
    if visibility == nil then return end
    local view = view_for(player.index)
    view.visibility, view.page, view.scroll = visibility, 1, 1
    render(player, view)
  elseif element.name == PREFIX .. "mode" then
    if not owns_element(player, element, {
      PREFIX .. "mode", PREFIX .. "filters", ROOT
    }) then return end
    local mode = whole_option(element.selected_index, 1, 3)
    if mode == nil then return end
    local view = view_for(player.index)
    view.mode, view.page, view.scroll = mode, 1, 1
    render(player, view)
  elseif element.name == PREFIX .. "status" then
    if not owns_element(player, element, {
      PREFIX .. "status", PREFIX .. "filters", ROOT
    }) then return end
    local view = view_for(player.index)
    local status = element.selected_index
    view.status = type(status) == "number" and status >= 1 and status <= 4 and math.floor(status) == status and status or 1
    view.page = 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "sort" then
    if not owns_element(player, element, {
      PREFIX .. "sort", PREFIX .. "filters", ROOT
    }) then return end
    local view = view_for(player.index)
    local sort = sort_from_index(element.selected_index)
    view.sort = sort
    if sort == "progression" or sort == "native" then view.stable_sort = sort end
    view.page = 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "results" then
    if not owns_element(player, element, {
      PREFIX .. "results", PREFIX .. "research_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local context = context_for(player.force)
    local rows = rows_for(player, view, context, translated_labels(translation_caches[player.index]))
    local index = element.selected_index
    local row = type(index) == "number" and rows[index] or nil
    if row then
      view.selected = row.id
      view.scroll = index
      render(player, view, context)
    end
  elseif element.name == PREFIX .. "settings_list" then
    if not owns_element(player, element, {
      PREFIX .. "settings_list", PREFIX .. "settings_dynamic", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    }) then return end
    local groups = setting_catalogue()
    if groups == nil then return end
    local view = view_for(player.index)
    local visible = {}
    for _, group in ipairs(groups) do
      if group.scope == view.settings_scope and setting_search_matches(group, view.settings_query) then
        visible[#visible + 1] = group
      end
    end
    local group = visible[element.selected_index]
    if group == nil then return end
    view.setting_selected = group.key
    render(player, view)
  elseif element.name == PREFIX .. "queue_list" then
    if not owns_element(player, element, {
      PREFIX .. "queue_list", PREFIX .. "queue_content", PREFIX .. "tabs", ROOT
    }) then return end
    local id = queue_entries(player.force)[element.selected_index]
    if id == nil or known_technology(player, id) == nil then return end
    local view = view_for(player.index)
    view.selected, view.tab, view.page, view.scroll = id, "research", 1, 1
    render(player, view)
  end
end

function M.on_gui_click(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event and event.player_index)
  if not player then return end
  if element.name == PREFIX .. "close" then
    if not owns_element(player, element, {
      PREFIX .. "close", PREFIX .. "actions", PREFIX .. "research_content", PREFIX .. "tabs", ROOT
    }) then return end
    M.close(player)
    return
  end
  if element.name == PREFIX .. "settings_research" or element.name == PREFIX .. "settings_options" then
    if not owns_element(player, element, {
      element.name, PREFIX .. "settings_toolbar", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    view.settings_scope = element.name == PREFIX .. "settings_options" and "options" or "research"
    view.setting_selected = nil
    render(player, view)
    return
  end
  if element.name == PREFIX .. "queue_open_native" then
    if not owns_element(player, element, {
      PREFIX .. "queue_open_native", PREFIX .. "queue_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    if destroy_frame(player, view) then discard_translation_cache(player.index) end
    if type(player.open_technology_gui) == "function" then player.open_technology_gui(nil) end
    return
  end
  if element.name ~= PREFIX .. "open_native" then return end
  if not owns_element(player, element, {
    PREFIX .. "open_native", PREFIX .. "actions", PREFIX .. "research_content", PREFIX .. "tabs", ROOT
  }) then return end
  local view = view_for(player.index)
  local selected = technology_id(view.selected)
  if selected == nil then return end
  local technologies = player.force and player.force.technologies
  if technologies == nil then return end
  local ok, technology = pcall(function() return technologies[selected] end)
  if not ok or not valid(technology) then return end
  if destroy_frame(player, view) then discard_translation_cache(player.index) end
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

local function expire_durable_entry(entry, tick)
  local cache = cache_from_pending(entry_pending(entry))
  if cache == nil then return nil, false end
  translation_queue.maintain(cache, cache.scope, tick)
  local pending = translation_queue.export_pending(cache)
  if pending == nil then return nil, false end
  return pending, true
end

local function release_durable_request(entry, request_id)
  local cache = cache_from_pending(entry_pending(entry))
  if cache == nil then return false, nil end
  local result = translation_queue.complete(cache, cache.scope, request_id, nil)
  return result.released == true, translation_queue.export_pending(cache)
end

local function update_durable_entry(bucket, group, index, entry, pending)
  if type(pending) ~= "table" or #pending == 0 then
    bucket[group][index] = nil
  else
    entry.pending = pending
    bucket[group][index] = entry
  end
end

local function invalidate_open_translation(index)
  local record = translation_caches[index]
  if record then discard_translation_cache(index) end
  local player = player_for(index)
  if player and valid(owned_root(player)) then render(player, view_for(index), nil, true) end
end

function M.on_string_translated(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local index, player = event.player_index, player_for(event.player_index)
  local record = translation_caches[index]
  local rooted = player and player.connected == true and valid(owned_root(player))
  if record and not rooted then
    -- The frame can disappear without our close callback. Retain only the
    -- durable issued window; callbacks then release it without a hidden view.
    discard_translation_cache(index)
    record = nil
  end
  if record then
    -- A native locale/force change can be visible before its corresponding
    -- event is delivered. Complete against the live token, never the cached
    -- one, so the old reply releases its ID but cannot label this view.
    local live_scope = scope_for(player, record.scope.generation)
    local scope_matches = live_scope and same_translation_scope(live_scope, record.scope)
    if live_scope == nil then
      live_scope = {
        player_index = record.scope.player_index,
        locale = record.scope.locale,
        force_index = record.scope.force_index,
        generation = record.scope.generation == 0 and 1 or 0
      }
    end
    local label = scope_matches and event.translated == true and type(event.result) == "string"
      and event.result or nil
    local result = translation_queue.complete(record.cache, live_scope, event.id, label)
    if not result.released then return end
    sync_issued_cache(record)
    if result.published and scope_matches and rooted
        and translation_queue.take_refresh(record.cache, record.scope) then
      render(player, view_for(index), nil, true)
    end
    return
  end

  -- With no open local cache a reply is useful only for releasing a durable
  -- request. It never rebuilds a closed view or creates presentation state.
  local state = existing_state()
  local ledger = state and existing_translation_ledger(state) or nil
  if not ledger then return end
  for _, group in ipairs({"active", "retired"}) do
    local entry = ledger[group][index]
    if entry then
      local released, pending = release_durable_request(entry, event.id)
      if released then update_durable_entry(ledger, group, index, entry, pending) end
      return
    end
  end
end

function M.on_player_locale_changed(event)
  if event and whole_number(event.player_index, 1) then invalidate_open_translation(event.player_index) end
end

function M.on_player_changed_force(event)
  if event and whole_number(event.player_index, 1) then invalidate_open_translation(event.player_index) end
end

function M.on_player_joined_game(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local player = player_for(event.player_index)
  local state = existing_state()
  if player and player.connected == true and state and type(state.players[event.player_index]) == "table" and valid(owned_root(player)) then
    -- A deferred native request may now be issued, but only because this
    -- player's tagged Library is actually open and connected.
    render(player, view_for(event.player_index), nil, true)
  end
end

function M.on_player_left_game(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local state = existing_state()
  local index = event and event.player_index
  local view = state and state.players[index]
  if type(view) == "table" then view.open, view.refresh_pending = false, false end
  if index then discard_translation_cache(index) end
end

-- Research callbacks can precede the engine's final queue/level transition.
-- Mark only relevant owned open views and refresh once on the following tick.
function M.on_native_state_changed(event)
  local state = existing_state()
  if not state then return end
  local force = event and (event.force or event.destination or (event.research and event.research.force))
  for index, view in pairs(state.players) do
    if type(view) == "table" and view.open == true then
      local player = player_for(index)
      if not player or player.connected ~= true or not valid(owned_root(player)) then
        view.open, view.refresh_pending = false, false
      elseif force == nil or (player.force and player.force.index == force.index) then
        view.refresh_pending = true
      end
    end
  end
end

function M.on_native_refresh_tick()
  local state = existing_state()
  if not state then return end
  local pending = {}
  for index, view in pairs(state.players) do
    if type(view) == "table" and view.refresh_pending == true then
      view.refresh_pending = false
      if whole_number(index, 1) then pending[#pending + 1] = index else view.open = false end
    end
  end
  -- Rendering may allocate durable translation epochs/native request IDs.
  -- Process only the pending views, in a stable player order on every client.
  table.sort(pending)
  for _, index in ipairs(pending) do
    local view, player = state.players[index], player_for(index)
    if view.open == true and player and player.connected == true and valid(owned_root(player)) then
      render(player, view_for(index), nil, true)
    else
      view.open = false
    end
  end
end

-- The two durable UI flags reconstruct subscriptions without accessing game
-- or changing saved data during on_load. They cache no native research facts.
function M.native_subscription_needs()
  local state = type(storage) == "table" and storage[STORAGE_KEY] or nil
  if type(state) ~= "table" or state.schema ~= SCHEMA or type(state.players) ~= "table" then
    return false, false
  end
  local open, pending = false, false
  for index, view in pairs(state.players) do
    if whole_number(index, 1) and type(view) == "table" and view.open == true then
      open = true
      pending = pending or view.refresh_pending == true
    end
  end
  return open, pending
end

function M.on_player_removed(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local state = existing_state()
  if not state then return end
  local index = event.player_index
  state.players[index] = nil
  discard_translation_cache(index)
  local ledger = existing_translation_ledger(state)
  if not ledger then return end
  local active = ledger.active[index]
  if active ~= nil and ledger.retired[index] == nil then
    -- LuaPlayer indices are reusable after removal. Retain even an unfamiliar
    -- active record rather than assuming it has no engine-issued IDs.
    ledger.retired[index] = active
    ledger.active[index] = nil
  elseif active == nil then
    ledger.active[index] = nil
  end
end

function M.on_translation_maintenance(event)
  local tick = event and event.tick
  if not whole_number(tick, 0) then return end
  local state = existing_state()
  local ledger = state and existing_translation_ledger(state) or nil
  if not ledger then return end

  for _, index in ipairs(ordered_player_indices(ledger.active)) do
    local entry = ledger.active[index]
    local record = translation_caches[index]
    local player = player_for(index)
    local rooted = player and player.connected == true and valid(owned_root(player))
    if record and record.ledger == ledger and rooted then
      translation_queue.maintain(record.cache, record.scope, tick)
      sync_issued_cache(record)
      if translation_queue.take_refresh(record.cache, record.scope) then
        render(player, view_for(index), nil, true)
      else
        dispatch_translations(player, record)
      end
    elseif record and record.ledger == ledger then
      -- A closed, disconnected, or externally destroyed root retains no local
      -- labels/catalogue. Its persisted issued window is expiry-only.
      discard_translation_cache(index)
      local durable = ledger.active[index]
      if durable then
        local pending, handled = expire_durable_entry(durable, tick)
        if handled then update_durable_entry(ledger, "active", index, durable, pending) end
      end
    else
      local pending, handled = expire_durable_entry(entry, tick)
      if handled then update_durable_entry(ledger, "active", index, entry, pending) end
    end
  end
  for _, index in ipairs(ordered_player_indices(ledger.retired)) do
    local entry = ledger.retired[index]
    local pending, handled = expire_durable_entry(entry, tick)
    if handled then update_durable_entry(ledger, "retired", index, entry, pending) end
    -- A reused index receives no new request while its prior lifetime has an
    -- issued ID. Once the retained window has drained, an already open owned
    -- view may resume normally; a closed or disconnected player remains
    -- expiry-only and receives no hidden render or dispatch.
    if ledger.retired[index] == nil and translation_caches[index] == nil then
      local player = player_for(index)
      if player and player.connected == true and valid(owned_root(player)) then
        render(player, view_for(index), nil, true)
      end
    end
  end
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
  reconnect_translation_caches()
  declaration_cache = nil
  local legacy = legacy_browser_state()
  local legacy_players = legacy and legacy.players
  if type(legacy_players) == "table" then
    local candidates = {}
    for index, historical_view in pairs(legacy_players) do
      local normalized_index = player_index(index)
      if normalized_index and type(historical_view) == "table" then
        candidates[#candidates + 1] = {index = normalized_index, view = historical_view}
      end
    end
    if #candidates > 0 then
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
      -- documented by the local 2.1 runtime API.  No player is created here:
      -- a headless native process cannot establish GUI-client evidence.
      for _, candidate in ipairs(candidates) do
        local player = player_for(candidate.index)
        if player then
          local view = local_view(state.players[candidate.index])
          state.players[candidate.index] = view
          rebuild_owned_legacy_root(player, view)
        end
      end
    end
  end

  -- Older views have no subscription flags. Recover them only here, where
  -- native players/GUI are available; a closed or foreign frame stays closed.
  local current = existing_state()
  if current then
    for index, view in pairs(current.players) do
      if type(view) == "table" then
        local player = player_for(index)
        view.open = player ~= nil and player.connected == true and valid(owned_root(player))
        view.refresh_pending = view.open
      end
    end
  end

  -- Configuration may change the compact catalogue. Keep engine-issued IDs,
  -- but give every open view a new caller epoch before it can publish labels.
  local open = ordered_player_indices(translation_caches)
  for _, index in ipairs(open) do invalidate_open_translation(index) end
end

-- Reconnect plain working references only. No saved field, native object,
-- authored catalogue, GUI or request is touched during load/client catch-up.
function M.on_load()
  reconnect_translation_caches()
end

-- Read-only on-load-safe decision. Do not call ensure_state here: malformed or
-- absent private state has no outstanding request this callback can own.
function M.subscription_needs()
  local state = type(storage) == "table" and storage[STORAGE_KEY] or nil
  local ledger = existing_translation_ledger(state)
  if not ledger then return false end
  for _, group in ipairs({ledger.active, ledger.retired}) do
    for _, entry in pairs(group) do
      if entry_pending(entry) then return true end
    end
  end
  return false
end

return M

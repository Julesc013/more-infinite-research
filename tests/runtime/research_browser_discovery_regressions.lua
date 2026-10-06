-- Copied-data and actual-adapter controls for localized recipe/material
-- discovery. LocalisedString composition below is controlled input, not an
-- engine translation, GUI, save, multiplayer or native performance oracle.
return function(core, adapter, check, host_source)
  local key = "discovery-metallurgy"
  local catalogue = {schema = 1, rows = {{key = key, available = true,
    researched = false, queued = false, infinite = false, progression = 1,
    native_order = "metallurgy"}}}
  local names = {[key] = "Metallurgie"}
  local discovery = {[key] = "Fonte raffinee Plaque doree Vapeur enrichie"}
  local view = {mode = 1, status = 1, family = "all", search = "plaque doree"}
  local found = core.query(catalogue, view, nil, names, key, discovery)
  check(found and found.count == 1 and found.rows[1].key == key,
    "localized material discovery retains the technology identity")
  view.search = "fonte raffinee"
  check(core.query_all(catalogue, view, nil, names, key, discovery).count == 1,
    "localized recipe discovery works without a MIR provider")
  view.search = "vapeur enrichie"
  check(core.query(catalogue, view, nil, names, key, discovery).count == 1,
    "localized fluid discovery is separate from the technology caption")
  check(found.rows[1].display_name == names[key],
    "recipe and material labels do not become the displayed technology name")
  view.hidden = {[key] = true}
  check(core.query(catalogue, view, nil, names, key, discovery).count == 0,
    "localized discovery respects the personal hidden set")
  view.hidden = nil
  check(core.query(catalogue, view, nil, names, key, {}).count == 0,
    "one player's localized labels do not become another player's index")
  check(core.query(catalogue, view, nil, names, key, {[key] = {}}).count == 0,
    "malformed discovery text grants no match")
  view.search = key
  check(core.query(catalogue, view, nil, nil, key, nil).count == 1,
    "stable-ID search remains available without a localized index")

  local technology = {name = key, localised_name = {"test.metallurgy"}, prototype = {
    effects = {{type = "unlock-recipe", recipe = "casting"},
      {type = "change-recipe-productivity", recipe = "casting", change = 0.02},
      {type = "nothing"}}}}
  local library = {recipe = {casting = {localised_name = {"test.casting"}, products = {
    {type = "item", name = "gold"}, {type = "fluid", name = "gold"},
    {type = "item", name = "gold"}}}}, item = {
    gold = {localised_name = {"test.gold-item"}}}, fluid = {
    gold = {localised_name = {"test.gold-fluid"}}}}
  local payload, subjects, limited = adapter.translation_request(technology, library)
  check(subjects == 3 and limited == false,
    "actual adapter deduplicates recipes/products and preserves item/fluid namespaces")
  local labels = {["test.metallurgy"] = "Metallurgie", ["test.casting"] = "Fonte raffinee",
    ["test.gold-item"] = "Plaque doree", ["test.gold-fluid"] = "Vapeur enrichie"}
  local function translated(value, depth)
    depth = (depth or 0) + 1
    check(depth <= 20, "composed translation stays within the engine depth contract")
    if type(value) == "string" then return value end
    check(type(value) == "table" and #value <= 21,
      "composed translation stays within the engine parameter contract")
    if value[1] == "?" then return translated(value[2], depth) end
    if value[1] ~= "" then return assert(labels[value[1]], "unexpected controlled locale key") end
    local out = {}
    for index = 2, #value do out[#out + 1] = translated(value[index], depth) end
    return table.concat(out)
  end
  local queue = core.translation_queue
  local cache = queue.new("fr", 1)
  queue.reset_catalogue(cache, {key}, "discovery-world")
  check(queue.dispatch(cache, key, 0, function() return 101 end, subjects, limited),
    "one composed request occupies the existing bounded translation window")
  check(queue.completed(cache, 101, translated(payload)) and cache.values[key] == names[key],
    "callback preserves the technology label separately from discovery text")
  view.search = "plaque doree"
  check(core.query_all(catalogue, view, nil, cache.values, key, cache.search_values).count == 1,
    "actual request/queue/query path realizes localized material discovery")
  check(cache.outstanding == 0 and queue.complete(cache) and not cache.discovery_limited,
    "completed discovery releases its slot without claiming a limited index")
  queue.reset_catalogue(cache, {key}, "new-world")
  check(next(cache.search_values) == nil, "catalogue replacement discards old discovery labels")
  queue.dispatch(cache, key, 0, function() return 102 end, subjects, limited)
  queue.invalidate_locale(cache, "en", 2)
  check(not queue.completed(cache, 102, translated(payload)) and next(cache.search_values) == nil,
    "stale locale callbacks cannot contaminate the current discovery index")
  queue.reset_catalogue(cache, {key}, "malformed-world")
  queue.dispatch(cache, key, 0, function() return 103 end, subjects, limited)
  queue.completed(cache, 103, "invalid composed response")
  check(cache.values[key] == key and cache.search_values[key] == nil and cache.discovery_limited,
    "malformed composition retains raw-ID fallback and an honest index limitation")

  local limited_payload, limited_subjects, is_limited = adapter.translation_request(technology, library, 1)
  check(limited_subjects == 1 and is_limited,
    "the actual adapter reports a subject budget instead of claiming complete discovery")
  queue.reset_catalogue(cache, {key}, "limited-world")
  queue.dispatch(cache, key, 0, function() return 104 end, limited_subjects, is_limited)
  queue.completed(cache, 104, translated(limited_payload))
  check(cache.discovery_limited and cache.values[key] == names[key],
    "a bounded index preserves its technology caption and records the missing coverage")
  queue.reset_catalogue(cache, {key}, "oversized-world")
  queue.dispatch(cache, key, 0, function() return 105 end, subjects, false)
  queue.completed(cache, 105, string.rep("x", queue.discovery_text_limit + 1))
  check(cache.values[key] == key and cache.search_values[key] == nil and cache.discovery_limited,
    "oversized translated input cannot remain in saved discovery state")
  check(core.query(catalogue, view, nil, names, key,
    {[key] = string.rep("x", queue.discovery_text_limit + 1)}).count == 0,
    "the pure query refuses an oversized discovery index")
  local byte_limit = queue.discovery_cache_byte_limit
  queue.discovery_cache_byte_limit = 1
  queue.reset_catalogue(cache, {key}, "byte-budget-world")
  queue.dispatch(cache, key, 0, function() return 106 end, subjects, false)
  queue.completed(cache, 106, translated(payload))
  queue.discovery_cache_byte_limit = byte_limit
  check(cache.discovery_limited and cache.search_bytes == 0 and cache.values[key] == names[key],
    "saved discovery bytes obey their player-local budget without losing the caption")

  queue.reset_catalogue(cache, {key}, "timeout-world")
  queue.dispatch(cache, key, 0, function() return 107 end, subjects, false)
  queue.expire(cache, queue.stale_ticks)
  check(queue.pop(cache) == key and not cache.discovery_limited,
    "a first timeout retains the existing retry without declaring permanent missing coverage")
  queue.dispatch(cache, key, queue.stale_ticks, function() return 108 end, subjects, false)
  queue.expire(cache, queue.stale_ticks * 2)
  check(cache.values[key] == key and cache.outstanding == 0 and cache.discovery_limited,
    "exhausted discovery retries preserve the ID and report incomplete localization")

  queue.reset_catalogue(cache, {key}, "old-catalogue")
  queue.dispatch(cache, key, 0, function() return 109 end, subjects, true)
  queue.reset_catalogue(cache, {key}, "replacement-catalogue")
  check(not queue.completed(cache, 109, translated(payload)) and not cache.discovery_limited
      and next(cache.search_values) == nil,
    "a stale catalogue callback cannot write discovery labels or its limitation flag")

  local crowded = {name = key, localised_name = key, prototype = {effects = {}}}
  local crowded_library = {recipe = {}}
  for index = 1, 129 do
    local name = "recipe-" .. index
    crowded.prototype.effects[index] = {type = "unlock-recipe", recipe = name}
    crowded_library.recipe[name] = {localised_name = name, products = {}}
  end
  local crowded_payload, crowded_subjects, crowded_limited = adapter.translation_request(crowded, crowded_library)
  local bounded_nodes = #crowded_payload <= 21
  for index = 2, #crowded_payload do bounded_nodes = bounded_nodes and #crowded_payload[index] <= 21 end
  check(crowded_subjects == 128 and crowded_limited and bounded_nodes,
    "the full subject boundary respects the composed engine parameter ceiling")
  for index = 1, 1025 do crowded.prototype.effects[index] = {type = "nothing"} end
  local _, empty_subjects, work_limited = adapter.translation_request(crowded, crowded_library)
  check(empty_subjects == 0 and work_limited,
    "irrelevant effects cannot evade the total prototype-work budget")

  local ordered_catalogue = {schema = 1, rows = {catalogue.rows[1], {
    key = "other-metallurgy", available = true, researched = false, queued = false,
    infinite = false, progression = 1, native_order = "other"}}}
  local ordered = core.query_all(ordered_catalogue, {mode = 1, status = 1, family = "all",
    search = "material", sort = "name-asc"}, nil,
    {[key] = "Zulu", ["other-metallurgy"] = "Alpha"}, key,
    {[key] = "Alpha material", ["other-metallurgy"] = "Zulu material"})
  check(ordered.count == 2 and ordered.rows[1].key == "other-metallurgy"
      and ordered.rows[2].key == key,
    "discovery labels cannot replace technology captions in Name ordering")

  check(type(host_source) == "string", "discovery controls receive the actual host source")
  host_source = host_source:gsub("\r\n", "\n")
  local function actual_function(name, environment)
    local first = assert(host_source:find("local function " .. name .. "(", 1, true))
    local last = assert(host_source:find("\nend", first, true)) + 3
    local source = host_source:sub(first, last) .. "\nreturn " .. name
    return assert(load(source, "actual-browser-" .. name, "t", environment))()
  end
  local requested_payload, calls = nil, 0
  local player = {valid = true, connected = true, index = 1, force = {
    technologies = {[key] = technology}}, request_translation = function(request)
      requested_payload, calls = request, calls + 1
      return 201
    end}
  local pump = actual_function("pump_translation_requests", {
    translation_queue = queue, factorio_catalogue = adapter, prototypes = library, game = {tick = 10}})
  queue.reset_catalogue(cache, {key}, "actual-host")
  pump(player, cache)
  check(calls == 1 and cache.outstanding == 1 and cache.pending_by_id[201].discovery_subjects == 3,
    "the actual host forwards subject metadata through the existing dispatch window")
  queue.completed(cache, 201, translated(requested_payload))
  check(core.query_all(catalogue, view, nil, cache.values, key, cache.search_values).count == 1,
    "actual host dispatch reaches the copied-data material query")

  queue.reset_catalogue(cache, {key}, "declined-host")
  player.request_translation = function() error("controlled request transport refusal") end
  pump(player, cache)
  check(cache.outstanding == 0 and cache.values[key] == key and cache.discovery_limited,
    "actual host transport refusal fails to raw IDs without opening an untracked window")

  player.locale, player.gui = cache.locale, {screen = {}}
  local callback = actual_function("translated", {
    core = core, type = type, string = string, translation_queue = queue, ROOT = "mir_research_browser",
    event_player = function() return player end,
    translation_state = function() return {[player.index] = cache}, {} end})
  queue.reset_catalogue(cache, {key}, "actual-composed-callback")
  queue.dispatch(cache, key, 0, function() return 202 end, subjects, false)
  local long_result = names[key] .. "\31" .. string.rep("r", 600) .. "\31"
    .. string.rep("m", 600) .. "\31" .. "Vapeur enrichie"
  callback{player_index = player.index, id = 202, translated = true, result = long_result}
  check(cache.values[key] == names[key] and type(cache.search_values[key]) == "string"
      and #cache.search_values[key] > 1024 and not cache.discovery_limited,
    "the actual callback retains a valid composed result larger than one caption")

  local pending, view_state, clock = {[2] = 4}, {tab = "research", search = "plaque doree"}, {tick = 10}
  local results, subscribed = {valid = true}, 0
  local body = {valid = true, mir_browser_research_results = results}
  player.gui = {screen = {mir_research_browser = {valid = true}}}
  local refresh = actual_function("refresh_translated_view", {
    translation_queue = queue, ROOT = "mir_research_browser", PREFIX = "mir_browser_", game = clock,
    view = function() return view_state end, active_body = function() return body end,
    update_translation_index = function() end,
    state = function() return {pending_search_refresh = pending} end,
    set_search_refresh_subscription = function(active) if active then subscribed = subscribed + 1 end end})
  queue.reset_catalogue(cache, {key, "remaining"}, "partial-host")
  cache.refresh_pending = true
  refresh(player, cache)
  check(pending[1] == 10 and pending[2] == 4 and subscribed == 1,
    "partial translations schedule existing deferred search work without touching a peer")
  clock.tick, cache.refresh_pending = 20, true
  refresh(player, cache)
  check(pending[1] == 10, "later callbacks do not starve an already scheduled search refresh")
end

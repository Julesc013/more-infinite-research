-- Pure, player-local Library translation cache. The caller owns persistence,
-- native LocalisedString lookup, event registration, connected/open gating,
-- and rendering. This component holds only plain data and never reads game,
-- storage, script, or a native catalogue.
local M = {
  schema = 1,
  outstanding_limit = 16,
  dispatch_work_limit = 16,
  refresh_batch = 8,
  retry_limit = 2,
  expiry_ticks = 1800,
  uint32_max = 4294967295,
  -- Lua's string length is a byte length. This limit applies to locale,
  -- catalogue-key, and translated-label byte strings.
  label_limit = 1024,
  translated_name_byte_limit = 16 * 1024 * 1024,
  catalogue_limit = 30000
}

local function finite_integer(value, minimum)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    and value == math.floor(value) and value >= minimum
end

local function copy_scope(scope)
  if type(scope) ~= "table" or not finite_integer(scope.player_index, 1)
      or type(scope.locale) ~= "string" or #scope.locale == 0 or #scope.locale > M.label_limit
      or not finite_integer(scope.force_index, 1)
      or not finite_integer(scope.generation, 0) then
    return nil
  end
  return {
    player_index = scope.player_index,
    locale = scope.locale,
    force_index = scope.force_index,
    generation = scope.generation
  }
end

local function same_scope(left, right)
  return type(left) == "table" and type(right) == "table"
    and left.player_index == right.player_index and left.locale == right.locale
    and left.force_index == right.force_index and left.generation == right.generation
end

local function copy_ids(ids)
  if type(ids) ~= "table" then return nil end
  local count = #ids
  if count > M.catalogue_limit then return nil end
  local copied, seen = {}, {}
  for index = 1, count do
    local id = ids[index]
    if type(id) ~= "string" or #id == 0 or #id > M.label_limit or seen[id] then return nil end
    copied[index], seen[id] = id, true
  end
  return copied
end

local function same_ids(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
  for index = 1, #left do
    if left[index] ~= right[index] then return false end
  end
  return true
end

local function valid_cache(cache)
  return type(cache) == "table" and cache.schema == M.schema and type(cache.scope) == "table"
    and type(cache.ids) == "table" and type(cache.labels) == "table"
    and type(cache.resolved_keys) == "table"
    and type(cache.pending_by_id) == "table" and type(cache.pending_by_key) == "table"
    and type(cache.retry_count) == "table" and type(cache.retry_queue) == "table"
    and type(cache.retry_scheduled) == "table" and finite_integer(cache.generation, 0)
    and finite_integer(cache.cursor, 1) and finite_integer(cache.outstanding, 0)
    and cache.outstanding <= M.outstanding_limit
    and finite_integer(cache.resolved, 0) and finite_integer(cache.catalogue_count, 0)
    and finite_integer(cache.completed_since_refresh, 0) and finite_integer(cache.cached_bytes, 0)
end

local function scope_is_current(cache, scope)
  local copied = copy_scope(scope)
  return copied ~= nil and valid_cache(cache) and same_scope(cache.scope, copied)
end

local function copy_map(value)
  local copied = {}
  for key, item in pairs(value) do copied[key] = item end
  return copied
end

local function queue_key(cache)
  while cache.cursor <= #cache.ids do
    local key = cache.ids[cache.cursor]
    cache.cursor = cache.cursor + 1
    if not cache.resolved_keys[key] and cache.pending_by_key[key] == nil then return key end
  end
  while #cache.retry_queue > 0 do
    local key = table.remove(cache.retry_queue, 1)
    cache.retry_scheduled[key] = nil
    if not cache.resolved_keys[key] and cache.pending_by_key[key] == nil then return key end
  end
  return nil
end

local function mark_refresh(cache)
  if cache.completed_since_refresh >= M.refresh_batch or cache.resolved >= cache.catalogue_count then
    cache.refresh_pending = true
  end
end

local function resolve(cache, key, label)
  if cache.resolved_keys[key] then return false end
  cache.resolved_keys[key] = true
  cache.resolved = cache.resolved + 1
  cache.completed_since_refresh = cache.completed_since_refresh + 1
  if type(label) == "string" and #label > 0 and #label <= M.label_limit
      and cache.cached_bytes + #label <= M.translated_name_byte_limit then
    cache.labels[key] = label
    cache.cached_bytes = cache.cached_bytes + #label
  end
  mark_refresh(cache)
  return true
end

local function schedule_retry(cache, key)
  local retries = (cache.retry_count[key] or 0) + 1
  cache.retry_count[key] = retries
  if retries >= M.retry_limit then
    cache.fallbacks = cache.fallbacks + 1
    resolve(cache, key, nil)
    return "fallback"
  end
  if not cache.retry_scheduled[key] then
    cache.retry_scheduled[key] = true
    cache.retry_queue[#cache.retry_queue + 1] = key
  end
  return "retry"
end

local function valid_request_id(value)
  return finite_integer(value, 0) and value <= M.uint32_max
end

local function valid_tick(value)
  -- MapTick is uint64 in the pinned native API. Lua's finite integral number
  -- boundary is the relevant safe check here; request IDs remain uint32.
  return finite_integer(value, 0)
end

local function valid_key(value)
  return type(value) == "string" and #value > 0 and #value <= M.label_limit
end

local function copy_pending_record(request_id, request)
  if not valid_request_id(request_id) or type(request) ~= "table" or not valid_key(request.key)
      or copy_scope(request.scope) == nil or not finite_integer(request.generation, 0)
      or not valid_tick(request.requested_tick) then
    return nil
  end
  return {
    request_id = request_id,
    key = request.key,
    scope = copy_scope(request.scope),
    cache_generation = request.generation,
    requested_tick = request.requested_tick
  }
end

local function exact_pending_record(record)
  if type(record) ~= "table" then return nil end
  local allowed = {
    request_id = true,
    key = true,
    scope = true,
    cache_generation = true,
    requested_tick = true
  }
  for field in pairs(record) do
    if allowed[field] ~= true then return nil end
  end
  if not valid_request_id(record.request_id) or not valid_key(record.key)
      or copy_scope(record.scope) == nil or not finite_integer(record.cache_generation, 0)
      or not valid_tick(record.requested_tick) then
    return nil
  end
  return {
    request_id = record.request_id,
    key = record.key,
    scope = copy_scope(record.scope),
    cache_generation = record.cache_generation,
    requested_tick = record.requested_tick
  }
end

local function copy_pending_ledger(ledger)
  if type(ledger) ~= "table" or #ledger > M.outstanding_limit then return nil end
  local count, copied, ids, keys = #ledger, {}, {}, {}
  for index, record in pairs(ledger) do
    if not finite_integer(index, 1) or index > count then return nil end
    local value = exact_pending_record(record)
    if value == nil or ids[value.request_id] or keys[value.key] then return nil end
    copied[index], ids[value.request_id], keys[value.key] = value, true, true
  end
  for index = 1, count do
    if copied[index] == nil then return nil end
  end
  return copied
end

local function release(cache, request_id)
  local request = cache.pending_by_id[request_id]
  if type(request) ~= "table" then return nil end
  cache.pending_by_id[request_id] = nil
  if cache.pending_by_key[request.key] == request_id then cache.pending_by_key[request.key] = nil end
  cache.outstanding = math.max(0, cache.outstanding - 1)
  return request
end

function M.new(scope)
  local copied = copy_scope(scope)
  if copied == nil then return nil, "invalid-scope" end
  return {
    schema = M.schema,
    initialized = false,
    scope = copied,
    generation = 0,
    ids = {},
    labels = {},
    resolved_keys = {},
    pending_by_id = {},
    pending_by_key = {},
    retry_count = {},
    retry_queue = {},
    retry_scheduled = {},
    cursor = 1,
    outstanding = 0,
    resolved = 0,
    catalogue_count = 0,
    completed_since_refresh = 0,
    refresh_pending = false,
    cached_bytes = 0,
    fallbacks = 0
  }
end

-- Exports only the bounded issued-request ledger. Labels, catalogue IDs,
-- retry state, and all native objects remain caller-local presentation data.
-- The returned dense array is detached and suitable for a small durable
-- Library-owned ledger. A reopened cache must receive a fresh caller scope
-- epoch before hydration so an old reply cannot publish into the new view.
function M.export_pending(cache)
  if not valid_cache(cache) then return nil end
  local records = {}
  for request_id, request in pairs(cache.pending_by_id) do
    local record = copy_pending_record(request_id, request)
    if record == nil then return nil end
    records[#records + 1] = record
  end
  if #records ~= cache.outstanding or #records > M.outstanding_limit then return nil end
  table.sort(records, function(left, right) return left.request_id < right.request_id end)
  return records
end

-- Hydrates only a previously exported ledger into an otherwise empty local
-- cache. It issues no requests and has no rendering side effects. Current
-- scope records reserve their key; stale records reserve only the shared
-- outstanding window until their callback or expiry releases it.
function M.hydrate_pending(cache, ledger)
  if not valid_cache(cache) then return false, "invalid-cache" end
  if cache.outstanding ~= 0 or next(cache.pending_by_id) ~= nil or next(cache.pending_by_key) ~= nil then
    return false, "cache-not-empty"
  end
  local records = copy_pending_ledger(ledger)
  if records == nil then return false, "invalid-ledger" end
  for _, record in ipairs(records) do
    cache.pending_by_id[record.request_id] = {
      key = record.key,
      scope = copy_scope(record.scope),
      generation = record.cache_generation,
      requested_tick = record.requested_tick
    }
    if same_scope(record.scope, cache.scope) and record.cache_generation == cache.generation then
      cache.pending_by_key[record.key] = record.request_id
    end
  end
  cache.outstanding = #records
  return true
end

-- Replaces only the current catalogue generation. Issued request IDs stay in
-- pending_by_id/outstanding until their callback or expiry, so invalidation
-- cannot create an unbounded parallel request window.
function M.prepare(cache, scope, ordered_ids)
  if not valid_cache(cache) then return false, "invalid-cache" end
  local copied_scope, copied_ids = copy_scope(scope), copy_ids(ordered_ids)
  if copied_scope == nil then return false, "invalid-scope" end
  if copied_ids == nil then return false, "invalid-catalogue" end
  if cache.initialized and same_scope(cache.scope, copied_scope) and same_ids(cache.ids, copied_ids) then
    return false, "unchanged"
  end
  cache.initialized = true
  cache.scope = copied_scope
  cache.generation = cache.generation + 1
  cache.ids = copied_ids
  cache.labels = {}
  cache.resolved_keys = {}
  cache.pending_by_key = {}
  cache.retry_count = {}
  cache.retry_queue = {}
  cache.retry_scheduled = {}
  cache.cursor = 1
  cache.resolved = 0
  cache.catalogue_count = #copied_ids
  cache.completed_since_refresh = 0
  cache.refresh_pending = false
  cache.cached_bytes = 0
  cache.fallbacks = 0
  return true
end

-- Dispatch is intentionally caller-open-only: it never checks a player or
-- renders anything. The caller supplies the native LocalisedString request
-- function and invokes this only for an eligible open Library view.
function M.dispatch(cache, scope, tick, request)
  if not scope_is_current(cache, scope) or not valid_tick(tick) or type(request) ~= "function" then
    return {work = 0, issued = 0, settled = 0}
  end
  local work, issued, settled = 0, 0, 0
  while cache.outstanding < M.outstanding_limit and work < M.dispatch_work_limit do
    local key = queue_key(cache)
    if key == nil then break end
    work = work + 1
    local ok, request_id = pcall(request, key)
    if ok and valid_request_id(request_id) and cache.pending_by_id[request_id] == nil then
      cache.pending_by_id[request_id] = {
        key = key,
        scope = copy_scope(cache.scope),
        generation = cache.generation,
        requested_tick = tick
      }
      cache.pending_by_key[key] = request_id
      cache.outstanding = cache.outstanding + 1
      issued = issued + 1
    else
      if schedule_retry(cache, key) == "fallback" then settled = settled + 1 end
    end
  end
  return {work = work, issued = issued, settled = settled}
end

-- A known request ID always releases a slot. It contributes a label only if
-- the callback and the cache still describe the same complete scope token.
-- The caller advances scope.generation for configuration or catalogue changes.
function M.complete(cache, scope, request_id, label)
  if not valid_cache(cache) or not valid_request_id(request_id) or copy_scope(scope) == nil then
    return {released = false, published = false}
  end
  local request = release(cache, request_id)
  if request == nil then return {released = false, published = false} end
  local current = same_scope(request.scope, cache.scope) and same_scope(cache.scope, scope)
    and request.generation == cache.generation
  if not current then return {released = true, published = false} end
  resolve(cache, request.key, label)
  return {released = true, published = true}
end

-- Closed callers may invoke maintenance to release expired IDs. It never
-- requests translations, initializes state, or produces a render instruction.
function M.maintain(cache, scope, tick)
  if not scope_is_current(cache, scope) or not valid_tick(tick) then return {expired = 0} end
  local expired = {}
  for request_id, request in pairs(cache.pending_by_id) do
    if type(request) == "table" and finite_integer(request.requested_tick, 0)
        and tick - request.requested_tick >= M.expiry_ticks then
      expired[#expired + 1] = request_id
    end
  end
  for _, request_id in ipairs(expired) do
    local request = release(cache, request_id)
    if request and same_scope(request.scope, cache.scope) and request.generation == cache.generation then
      schedule_retry(cache, request.key)
    end
  end
  return {expired = #expired}
end

function M.take_refresh(cache, scope)
  if not scope_is_current(cache, scope) or cache.refresh_pending ~= true then return false end
  cache.refresh_pending = false
  cache.completed_since_refresh = 0
  return true
end

-- Safe for on_load composition: this is a read-only decision and never
-- allocates or repairs a cache. It only reports whether issued IDs remain.
function M.needs_maintenance(cache)
  return valid_cache(cache) and next(cache.pending_by_id) ~= nil
end

-- The Library model treats this map as read-only. Returning the cache-owned
-- labels avoids copying up to 16 MiB on every render; explicit diagnostics use
-- snapshot() below when they need a detached result.
function M.labels(cache, scope)
  if not scope_is_current(cache, scope) then return nil end
  return cache.labels
end

function M.snapshot(cache, scope)
  if not scope_is_current(cache, scope) then return nil end
  return {
    scope = copy_scope(cache.scope),
    labels = copy_map(cache.labels),
    stats = {
      outstanding = cache.outstanding,
      resolved = cache.resolved,
      catalogue_count = cache.catalogue_count,
      cached_bytes = cache.cached_bytes,
      fallbacks = cache.fallbacks,
      refresh_pending = cache.refresh_pending == true
    }
  }
end

return M

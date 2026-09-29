-- Schema-1 portable copied-data research query surface. This module is
-- deliberately Factorio-neutral: adapters own runtime objects and hosts own
-- presentation, navigation, and actions.
local M = {
  schema = 1,
  page_size = 20,
  catalogue_limit = 30000,
  detail_depth_limit = 8,
  detail_node_limit = 256,
  detail_string_limit = 1024,
  detail_key_length = 160,
  enrichment_schema = 2,
  enrichment_kind = "portable-research-enrichment"
}

-- Player-local asynchronous translation window. It owns only presentation
-- labels; research IDs and policy remain in the browser core. Superseded
-- catalogue/locale generations deliberately retain their issued IDs until a
-- callback or timeout releases the shared outstanding window.
local translation_queue = {
  outstanding_limit = 16,
  request_work_limit = 16,
  refresh_batch = 8,
  retry_limit = 2,
  stale_ticks = 60 * 30
}

function translation_queue.new(locale, locale_generation)
  return {
    locale = locale,
    locale_generation = locale_generation,
    catalogue_generation = 0,
    values = {},
    pending_by_id = {},
    pending_by_key = {},
    retry_count = {},
    retry_queue = {},
    retry_scheduled = {},
    queue = {},
    cursor = 1,
    outstanding = 0,
    resolved = 0,
    catalogue_count = 0,
    completed_since_refresh = 0,
    refresh_pending = false,
    priority_token = nil
  }
end

-- Do not clear pending_by_id or outstanding here. Factorio cannot cancel an
-- issued request, so replacing those maps would allow every rapid catalogue
-- or locale change to open a new 16-request window before old callbacks end.
function translation_queue.reset_catalogue(cache, names, token)
  cache.catalogue_generation = cache.catalogue_generation + 1
  cache.catalogue_token = token
  cache.values = {}
  cache.pending_by_key = {}
  cache.retry_count = {}
  cache.retry_queue = {}
  cache.retry_scheduled = {}
  cache.queue = names
  cache.cursor = 1
  cache.resolved = 0
  cache.catalogue_count = #names
  cache.completed_since_refresh = 0
  cache.refresh_pending = false
  cache.priority_token = nil
end

function translation_queue.invalidate_locale(cache, locale, locale_generation)
  cache.locale = locale
  cache.locale_generation = locale_generation
  translation_queue.reset_catalogue(cache, {}, nil)
end

function translation_queue.resolve(cache, key, value)
  if cache.values[key] ~= nil then return false end
  cache.values[key] = value
  cache.resolved = cache.resolved + 1
  cache.completed_since_refresh = cache.completed_since_refresh + 1
  if cache.completed_since_refresh >= translation_queue.refresh_batch
      or cache.resolved >= cache.catalogue_count then
    cache.refresh_pending = true
  end
  return true
end

-- The host consumes this marker after it has patched its existing results
-- container.  Keeping the acknowledgement with the queue makes each bounded
-- batch observable without asking a callback to recreate the whole browser.
function translation_queue.consume_refresh(cache)
  if type(cache) ~= "table" or cache.refresh_pending ~= true then return false end
  cache.refresh_pending = false
  cache.completed_since_refresh = 0
  return true
end

function translation_queue.schedule_retry(cache, key)
  local retries = (cache.retry_count[key] or 0) + 1
  cache.retry_count[key] = retries
  if retries >= translation_queue.retry_limit then
    translation_queue.resolve(cache, key, key)
  elseif not cache.retry_scheduled[key] then
    cache.retry_scheduled[key] = true
    cache.retry_queue[#cache.retry_queue + 1] = key
  end
end

function translation_queue.pop(cache)
  while cache.cursor <= #cache.queue do
    local key = cache.queue[cache.cursor]
    cache.cursor = cache.cursor + 1
    if cache.values[key] == nil and cache.pending_by_key[key] == nil then return key end
  end
  while #cache.retry_queue > 0 do
    local key = table.remove(cache.retry_queue, 1)
    cache.retry_scheduled[key] = nil
    if cache.values[key] == nil and cache.pending_by_key[key] == nil then return key end
  end
  return nil
end

-- Keep the bounded request window and every issued ID intact while allowing
-- the open library's selected and visible rows to enter the unissued portion
-- of a catalogue first.  This only reorders entries at or after cursor; it
-- never revives resolved/pending work or changes the catalogue membership.
function translation_queue.prioritize(cache, keys)
  if type(cache) ~= "table" or type(cache.queue) ~= "table" or type(keys) ~= "table" then return false end
  local start = math.max(1, math.floor(tonumber(cache.cursor) or 1))
  if start > #cache.queue then return false end
  local front, selected_indexes, available_indexes = {}, {}, {}
  for index = start, #cache.queue do
    local key = cache.queue[index]
    if available_indexes[key] == nil and cache.values[key] == nil and cache.pending_by_key[key] == nil then
      available_indexes[key] = index
    end
  end
  for _, key in ipairs(keys) do
    local index = type(key) == "string" and available_indexes[key]
    if index and not selected_indexes[index] then
      selected_indexes[index] = true
      front[#front + 1] = key
    end
  end
  if #front == 0 then return false end
  local reordered = {}
  for index = 1, start - 1 do reordered[index] = cache.queue[index] end
  for _, key in ipairs(front) do reordered[#reordered + 1] = key end
  for index = start, #cache.queue do
    local key = cache.queue[index]
    if not selected_indexes[index] then reordered[#reordered + 1] = key end
  end
  for index = start, #cache.queue do
    if reordered[index] ~= cache.queue[index] then
      cache.queue = reordered
      return true
    end
  end
  return false
end

function translation_queue.can_request(cache)
  return cache.outstanding < translation_queue.outstanding_limit
end

function translation_queue.requested(cache, key, id, tick)
  if not translation_queue.can_request(cache) or type(id) ~= "number" then return false end
  local request = {
    key = key,
    locale_generation = cache.locale_generation,
    catalogue_generation = cache.catalogue_generation,
    requested_tick = tick
  }
  cache.pending_by_id[id] = request
  cache.pending_by_key[key] = id
  cache.outstanding = cache.outstanding + 1
  return true
end

function translation_queue.request_declined(cache, key)
  return translation_queue.resolve(cache, key, key)
end

-- Keep protected request dispatch here so host callers cannot accidentally
-- collapse pcall's success and translation-ID returns through an `and`
-- expression. A numeric Factorio request ID must occupy a pending slot;
-- declined/failed requests resolve immediately to the stable-ID fallback.
function translation_queue.dispatch(cache, key, tick, request)
  local ok, id = pcall(request)
  if ok and translation_queue.requested(cache, key, id, tick) then return true end
  translation_queue.request_declined(cache, key)
  return false
end

-- Returns true only when the result belongs to the current locale/catalogue
-- generation. In every case a known request ID releases its pending slot.
function translation_queue.completed(cache, id, value)
  local request = cache.pending_by_id[id]
  if not request then return false end
  cache.pending_by_id[id] = nil
  if cache.pending_by_key[request.key] == id then cache.pending_by_key[request.key] = nil end
  cache.outstanding = math.max(0, cache.outstanding - 1)
  if request.locale_generation ~= cache.locale_generation
      or request.catalogue_generation ~= cache.catalogue_generation then
    return false
  end
  translation_queue.resolve(cache, request.key, type(value) == "string" and value ~= "" and value or request.key)
  return true
end

-- Expired current requests get one retry then a stable-ID fallback. Expired
-- old-generation requests only release their pending slot; they must never
-- re-enter the current catalogue queue.
function translation_queue.expire(cache, tick)
  local expired = 0
  for id, request in pairs(cache.pending_by_id) do
    if tick - request.requested_tick >= translation_queue.stale_ticks then
      cache.pending_by_id[id] = nil
      if cache.pending_by_key[request.key] == id then cache.pending_by_key[request.key] = nil end
      cache.outstanding = math.max(0, cache.outstanding - 1)
      expired = expired + 1
      if request.locale_generation == cache.locale_generation
          and request.catalogue_generation == cache.catalogue_generation then
        translation_queue.schedule_retry(cache, request.key)
      end
    end
  end
  return expired
end

function translation_queue.unresolved(cache)
  return math.max(0, cache.catalogue_count - cache.resolved)
end

-- A name order may be applied only after the current catalogue generation has
-- a settled label or stable-ID fallback for every row. Pending old-generation
-- IDs deliberately do not delay this current-generation presentation state.
function translation_queue.complete(cache)
  return type(cache) == "table" and type(cache.catalogue_count) == "number"
    and type(cache.resolved) == "number" and cache.resolved >= cache.catalogue_count
end

M.translation_queue = translation_queue

-- Detail payloads are copied only as bounded plain data. Count every emitted
-- table, field key, and scalar so a wide provider value fails closed.
local function copy_plain(value, state, depth)
  local kind = type(value)
  if kind == "string" then
    if #value > M.detail_string_limit then return nil, "enrichment-limit" end
  elseif kind ~= "number" and kind ~= "boolean" and value ~= nil then
    if kind ~= "table" then return nil end
  end
  if kind ~= "table" then
    state.nodes = state.nodes + 1
    if state.nodes > M.detail_node_limit then return nil, "enrichment-limit" end
    return value
  end
  if depth >= M.detail_depth_limit then return nil, "enrichment-limit" end
  state.nodes = state.nodes + 1
  if state.nodes > M.detail_node_limit then return nil, "enrichment-limit" end
  local result = {}
  for key, child in pairs(value) do
    if type(key) == "string" or type(key) == "number" then
      if type(key) == "string" and #key > M.detail_key_length then return nil, "enrichment-limit" end
      local copied, reason = copy_plain(child, state, depth + 1)
      if reason then return nil, reason end
      if copied ~= nil or child == nil then
        state.nodes = state.nodes + 1
        if state.nodes > M.detail_node_limit then return nil, "enrichment-limit" end
        result[key] = copied
      end
    end
  end
  return result
end

local function copy_row(row)
  local progression = type(row.progression) == "number" and row.progression == row.progression
    and row.progression ~= math.huge and row.progression ~= -math.huge
    and row.progression >= 0 and row.progression == math.floor(row.progression) and row.progression or 0
  return {
    key = row.key,
    available = row.available == true,
    researched = row.researched == true,
    queued = row.queued == true,
    infinite = row.infinite == true,
    native_order = type(row.native_order) == "string" and string.sub(row.native_order, 1, M.detail_string_limit) or "",
    progression = progression
  }
end

local function bounded_string(value)
  return type(value) == "string" and value ~= "" and #value <= M.detail_string_limit
end

local function finite_positive(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value > 0
end

local function finite_positive_integer(value)
  return finite_positive(value) and value == math.floor(value)
end

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value >= 0
end

local function finite_nonnegative_integer(value)
  return finite_nonnegative(value) and value == math.floor(value)
end

local function same_scalar(left, right)
  return type(left) == type(right) and left == right
end

local function dense_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for index in pairs(value) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return false end
    count = count + 1
  end
  return #value == count
end

local function only_fields(value, allowed)
  for key in pairs(value) do if not allowed[key] then return false end end
  return true
end

local function sorted_unique_strings(value)
  if not dense_array(value) then return false end
  local previous = nil
  for _, item in ipairs(value) do
    if not bounded_string(item) or (previous and item <= previous) then return false end
    previous = item
  end
  return true
end

local function same_array(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if right[index] ~= value then return false end end
  return true
end

local function valid_setting(value, expected_name, expected_type)
  local values_are_valid = type(value) == "table"
    and type(value.default) == expected_type and type(value.raw_direct) == expected_type
    and type(value.effective) == expected_type
  if values_are_valid and expected_type == "number" then
    values_are_valid = finite_positive_integer(value.default)
      and finite_positive_integer(value.raw_direct) and finite_positive_integer(value.effective)
  end
  return type(value) == "table"
    and only_fields(value, {name = true, default = true, raw_direct = true, effective = true,
      source = true, changed = true, changed_from_default = true, restart_required = true})
    and value.name == expected_name and (value.source == "direct" or value.source == "mirset1")
    and values_are_valid
    and type(value.changed) == "boolean" and type(value.changed_from_default) == "boolean"
    and value.changed == (not same_scalar(value.raw_direct, value.effective))
    and value.changed_from_default == (not same_scalar(value.default, value.effective))
    and value.restart_required == true
end

-- This setting shape deliberately differs from valid_setting(): maximum-level
-- zero is the declared unbounded selection, while ordinary positive settings
-- remain validated by the richer generated-stream detail contract above.
local function valid_runtime_maximum_setting(value, expected_name)
  local values_are_valid = type(value) == "table"
    and finite_nonnegative_integer(value.default)
    and finite_nonnegative_integer(value.raw_direct)
    and finite_nonnegative_integer(value.effective)
  return values_are_valid
    and only_fields(value, {name = true, default = true, raw_direct = true, effective = true,
      source = true, changed = true, changed_from_default = true, restart_required = true})
    and value.name == expected_name and (value.source == "direct" or value.source == "mirset1")
    and type(value.changed) == "boolean" and type(value.changed_from_default) == "boolean"
    and value.changed == (not same_scalar(value.raw_direct, value.effective))
    and value.changed_from_default == (not same_scalar(value.default, value.effective))
    and value.restart_required == true
end

local runtime_binding_sources = {
  ["generated-stream"] = true,
  ["base-continuation"] = true
}

local runtime_binding_transports = {
  ["transported-v3"] = true,
  ["settings-derived-v3"] = true
}

local function valid_runtime_settings_binding(value, key)
  if type(value) ~= "table" or value.schema ~= 1
      or not only_fields(value, {schema = true, source = true, policy_transport = true,
        binding = true, setting = true, selected_effective = true, state = true, blocked_reason = true})
      or not runtime_binding_sources[value.source]
      or not runtime_binding_transports[value.policy_transport]
      or type(value.binding) ~= "table"
      or not only_fields(value.binding, {technology_id = true, declared_key = true, setting_name = true})
      or value.binding.technology_id ~= key
      or not bounded_string(value.binding.declared_key)
      or not bounded_string(value.binding.setting_name)
      or not valid_runtime_maximum_setting(value.setting, value.binding.setting_name) then
    return false
  end
  local selected = value.selected_effective
  local finite, infinite = finite_positive_integer(selected), selected == "infinite"
  if value.state == "finite" then
    return finite and value.blocked_reason == nil and value.setting.effective == selected
  elseif value.state == "infinite" then
    return infinite and value.blocked_reason == nil and value.setting.effective == 0
  elseif value.state == "disabled" then
    return (finite or infinite) and bounded_string(value.blocked_reason)
      and ((finite and value.setting.effective == selected)
        or (infinite and value.setting.effective == 0))
  end
  return false
end

local function exact_map_keys(left, right)
  for key, _ in pairs(left) do if right[key] == nil then return false end end
  for key, _ in pairs(right) do if left[key] == nil then return false end end
  return true
end

-- Schema-2 is the provider contract. It admits the small generic family/action
-- detail or the declared recipe-productivity detail shape, never arbitrary
-- copied fields from an untrusted provider envelope.
local function valid_schema2_detail(detail, key, family, cap)
  if type(detail) ~= "table" or detail.schema ~= 1
    or not bounded_string(detail.family) or not bounded_string(detail.action)
    or (detail.action ~= "emit" and detail.action ~= "adopt" and detail.action ~= "skip")
    or detail.family ~= family then return false end
  local allowed = {schema = true, family = true, action = true, owner = true,
    compiler_disposition = true, final_science = true, effective_cap = true,
    current_level = true, recipe_benefits = true, next_level_eligible = true, next_level_has_effective_benefit = true,
    settings = true}
  if not only_fields(detail, allowed) then return false end
  local rich = detail.owner ~= nil or detail.compiler_disposition ~= nil or detail.final_science ~= nil
    or detail.effective_cap ~= nil or detail.current_level ~= nil or detail.recipe_benefits ~= nil
    or detail.next_level_eligible ~= nil or detail.next_level_has_effective_benefit ~= nil or detail.settings ~= nil
  if not rich then return true, false end
  if type(detail.owner) ~= "table" or not only_fields(detail.owner, {technology_id = true,
      stream_id = true, action = true, reason = true, affected_recipe_ids = true})
    or not bounded_string(detail.owner.technology_id) or not bounded_string(detail.owner.stream_id)
    or not bounded_string(detail.owner.action) or not bounded_string(detail.owner.reason)
    or detail.owner.technology_id ~= key or detail.owner.stream_id ~= family
    or detail.owner.action ~= detail.action or not sorted_unique_strings(detail.owner.affected_recipe_ids) then return false end
  local disposition = detail.compiler_disposition
  if type(disposition) ~= "table" or not only_fields(disposition, {inclusion = true, action = true,
      reason = true, route_exclusions = true}) or not bounded_string(disposition.inclusion)
    or disposition.inclusion ~= "included" or not bounded_string(disposition.action) or not bounded_string(disposition.reason)
    or disposition.action ~= detail.owner.action or disposition.reason ~= detail.owner.reason
    or type(disposition.route_exclusions) ~= "table"
    or not only_fields(disposition.route_exclusions, {state = true, recipe_ids = true})
    or disposition.route_exclusions.state ~= "no-additional-route-exclusions-published-for-current-row"
    or not sorted_unique_strings(disposition.route_exclusions.recipe_ids)
    or #disposition.route_exclusions.recipe_ids ~= 0 then return false end
  local science = detail.final_science
  if type(science) ~= "table" or not only_fields(science, {rationale = true, ingredients = true})
    or not bounded_string(science.rationale) or not dense_array(science.ingredients) then return false end
  for _, ingredient in ipairs(science.ingredients) do
    if type(ingredient) ~= "table" or not only_fields(ingredient, {name = true, amount = true})
      or not bounded_string(ingredient.name) or not finite_positive(ingredient.amount) then return false end
  end
  local capped = cap ~= nil
  if not finite_positive_integer(detail.current_level)
    or type(detail.next_level_has_effective_benefit) ~= "boolean"
    or not dense_array(detail.recipe_benefits) then return false end
  -- Existing finite-cap schema-2 providers derived this from the cap. The
  -- explicit field is needed only where an unbounded technology has no cap
  -- for the portable core to inspect.
  local next_level_eligible = detail.next_level_eligible
  if capped and next_level_eligible == nil then
    next_level_eligible = detail.current_level <= cap
  elseif type(next_level_eligible) ~= "boolean" then
    return false
  end
  if capped then
    if next_level_eligible and detail.current_level > cap then return false end
    local settings = detail.settings
    if not finite_positive_integer(detail.effective_cap) or detail.effective_cap ~= cap
      or type(settings) ~= "table" or not only_fields(settings, {maximum_level = true, enabled = true})
      or not valid_setting(settings.maximum_level, "ips-max-level-" .. family, "number")
      or not valid_setting(settings.enabled, "ips-enable-" .. family, "boolean")
      or settings.maximum_level.effective ~= cap then return false end
  elseif detail.effective_cap ~= nil or detail.settings ~= nil then
    return false
  end
  local benefit_ids, any_effective, previous = {}, false, nil
  for index, benefit in ipairs(detail.recipe_benefits) do
    if type(benefit) ~= "table" or not only_fields(benefit, {recipe_id = true, effect_change = true,
        current_productivity_bonus = true, maximum_productivity = true, next_level_has_effective_benefit = true})
      or not bounded_string(benefit.recipe_id) or not finite_positive(benefit.effect_change)
      or not finite_nonnegative(benefit.current_productivity_bonus) or not finite_nonnegative(benefit.maximum_productivity)
      or benefit.current_productivity_bonus > benefit.maximum_productivity
      or type(benefit.next_level_has_effective_benefit) ~= "boolean"
      or (previous and benefit.recipe_id <= previous) then return false end
    local expected_effective = next_level_eligible
      and benefit.current_productivity_bonus < benefit.maximum_productivity - 0.000000001
    if benefit.next_level_has_effective_benefit ~= expected_effective then return false end
    benefit_ids[index], previous = benefit.recipe_id, benefit.recipe_id
    any_effective = any_effective or benefit.next_level_has_effective_benefit
  end
  local valid = same_array(detail.owner.affected_recipe_ids, benefit_ids)
    and detail.next_level_has_effective_benefit == any_effective
  return valid, true
end

-- Schema-1 enrichment remains accepted solely for portable consumers that
-- supplied the original generic optional DTO. New providers must identify a
-- schema-2 portable envelope; malformed data is ignored, never rendered.
function M.normalize_enrichment(enrichment)
  if enrichment == nil then return nil end
  if type(enrichment) ~= "table" then return nil end
  if enrichment.schema == 1 then return enrichment end
  if not only_fields(enrichment, {schema = true, kind = true, caps = true, families = true, details = true,
      runtime_settings_bindings = true})
    or enrichment.schema ~= M.enrichment_schema or enrichment.kind ~= M.enrichment_kind
    or type(enrichment.caps) ~= "table" or type(enrichment.families) ~= "table"
    or type(enrichment.details) ~= "table" then
    return nil
  end
  local runtime_settings_bindings = enrichment.runtime_settings_bindings
  if runtime_settings_bindings == nil then runtime_settings_bindings = {} end
  if type(runtime_settings_bindings) ~= "table" then return nil end
  if not exact_map_keys(enrichment.families, enrichment.details) then return nil end
  local count = 0
  for key, cap in pairs(enrichment.caps) do
    count = count + 1
    if count > M.catalogue_limit or not bounded_string(key)
      or not finite_positive_integer(cap) then return nil end
  end
  for key, family in pairs(enrichment.families) do
    count = count + 1
    if count > M.catalogue_limit * 2 or not bounded_string(key)
      or not bounded_string(family) then return nil end
  end
  for key, detail in pairs(enrichment.details) do
    count = count + 1
    local valid, rich = valid_schema2_detail(detail, key, enrichment.families[key], enrichment.caps[key])
    if count > M.catalogue_limit * 3 or not bounded_string(key) or not valid
      or (enrichment.caps[key] ~= nil and not rich) then return nil end
  end
  for key, _ in pairs(enrichment.caps) do if enrichment.details[key] == nil then return nil end end
  local runtime_count = 0
  for key, binding in pairs(runtime_settings_bindings) do
    runtime_count = runtime_count + 1
    if runtime_count > M.catalogue_limit or not bounded_string(key)
      or not valid_runtime_settings_binding(binding, key) then return nil end
  end
  return enrichment
end

local function positive_cap(enrichment, key)
  local caps = enrichment and enrichment.caps
  local cap = caps and caps[key]
  return finite_positive_integer(cap) and cap or nil
end

local function family_for(enrichment, key)
  local families = enrichment and enrichment.families
  local family = families and families[key]
  return type(family) == "string" and family or "external"
end

local function ascii_casefold(value)
  -- Displayed-name ordering deliberately has a small, portable contract:
  -- ASCII A-Z folds to a-z and the remaining UTF-8 bytes compare directly.
  -- It does not claim Unicode normalization or locale-aware collation.
  return (string.gsub(value, "%u", function(letter)
    return string.char(string.byte(letter) + 32)
  end))
end

local function searchable_text(value)
  -- Stable IDs are useful while localized names are still arriving. Treat
  -- their separators like spaces so a player can type a displayed phrase.
  local folded = ascii_casefold(value)
  return (string.gsub(folded, "[%s_-]+", " "))
end

local function matches_search(value, search, spaced_search)
  local folded = ascii_casefold(value)
  if string.find(folded, search, 1, true) then return true end
  return spaced_search and string.find(string.gsub(folded, "[%s_-]+", " "), search, 1, true) ~= nil
end

local function normalized_view(view)
  view = type(view) == "table" and view or {}
  local mode = tonumber(view.mode) or 1
  if mode < 1 or mode > 3 or mode ~= math.floor(mode) then mode = 1 end
  local status = tonumber(view.status) or 1
  if status < 1 or status > 4 or status ~= math.floor(status) then status = 1 end
  local page = math.max(1, math.floor(tonumber(view.page) or 1))
  local search = type(view.search) == "string" and string.sub(view.search, 1, 160) or ""
  local family = type(view.family) == "string" and view.family or "all"
  local sort = view.sort == "name-asc" and "name-asc"
    or view.sort == "name-desc" and "name-desc"
    or view.sort == "native" and "native"
    or "progression"
  local fallback_sort = view.fallback_sort == "native" and "native" or "progression"
  local requested_sort = sort
  local name_index_ready = view.name_index_ready ~= false
  if not name_index_ready and (sort == "name-asc" or sort == "name-desc") then sort = fallback_sort end
  search = searchable_text(search):gsub("^ ", ""):gsub(" $", "")
  return {
    mode = mode, status = status, page = page, search = search, family = family,
    spaced_search = string.find(search, " ", 1, true) ~= nil,
    sort = sort, requested_sort = requested_sort, name_index_ready = name_index_ready,
    hidden = type(view.hidden) == "table" and view.hidden or {}
  }
end

-- Translation belongs to a host because it is player- and locale-specific.
-- The portable core receives only an optional bounded plain-text index and
-- continues to fall back to stable technology and family identifiers.
local function localized_search_text(index, key)
  if type(index) ~= "table" then return "" end
  local value = index[key]
  if type(value) ~= "string" or #value > M.detail_string_limit then return "" end
  return value
end

-- The host resolves each row label asynchronously. Until it has a result,
-- the stable technology ID is both the visible fallback and the query/sort
-- value. This prevents a label that arrives later from changing which ID an
-- existing row action addresses.
local function displayed_label(index, key)
  local value = localized_search_text(index, key)
  return value ~= "" and value or key
end

local function status_matches(row, status)
  if status == 1 then return true end
  if status == 2 then return row.available == true end
  if status == 3 then return row.available ~= true and row.researched ~= true end
  return row.queued == true
end

local function family_matches(family, selected)
  return selected == "all" or (selected == "mir" and family ~= "external") or family == selected
end

local function sort_rows(left, right, sort)
  if sort == "name-desc" or sort == "name-asc" then
    if left.display_sort ~= right.display_sort then
      if sort == "name-desc" then return left.display_sort > right.display_sort end
      return left.display_sort < right.display_sort
    end
    return left.key < right.key
  end
  if sort == "native" then
    if left.native_order ~= right.native_order then return left.native_order < right.native_order end
    if left.progression ~= right.progression then return left.progression < right.progression end
  else
    if left.progression ~= right.progression then return left.progression < right.progression end
    if left.native_order ~= right.native_order then return left.native_order < right.native_order end
  end
  return left.key < right.key
end

-- Query only accepts copied, plain catalogue DTOs. It returns a fresh plain
-- page so a consumer cannot retain adapter-owned state.
function M.query(catalogue, view, enrichment, localized_search, selected_key)
  if type(catalogue) ~= "table" or catalogue.schema ~= M.schema or type(catalogue.rows) ~= "table" then return nil, "invalid-catalogue" end
  if #catalogue.rows > M.catalogue_limit then return nil, "catalogue-limit" end
  enrichment = M.normalize_enrichment(enrichment)
  local selected, selected_visible, v = {}, false, normalized_view(view)
  selected_key = type(selected_key) == "string" and selected_key or nil
  for _, source in ipairs(catalogue.rows) do
    if type(source) == "table" and type(source.key) == "string" then
      local key = source.key
      local cap, family = positive_cap(enrichment, key), family_for(enrichment, key)
      local infinite = source.infinite == true and not cap
      local mode_ok = v.mode == 1 or (v.mode == 2 and not infinite) or (v.mode == 3 and infinite)
      if mode_ok and status_matches(source, v.status) and family_matches(family, v.family)
        and not v.hidden[key] then
        local display_name = displayed_label(localized_search, key)
        local search_ok = v.search == "" or matches_search(
          key .. " " .. family .. " " .. display_name, v.search, v.spaced_search)
        if not search_ok and enrichment and enrichment.schema == M.enrichment_schema then
          local detail = enrichment.details[key]
          for _, benefit in ipairs(detail and detail.recipe_benefits or {}) do
            if matches_search(benefit.recipe_id, v.search, v.spaced_search) then
              search_ok = true
              break
            end
          end
        end
        if search_ok then
          local row = copy_row(source)
          row.cap, row.family, row.infinite = cap, family, infinite
          row.display_name = display_name
          row.display_sort = ascii_casefold(display_name)
          selected[#selected + 1] = row
          if key == selected_key then selected_visible = true end
        end
      end
    end
  end
  table.sort(selected, function(left, right)
    if left.key == right.key then return false end
    return sort_rows(left, right, v.sort)
  end)
  local pages = math.max(1, math.ceil(#selected / M.page_size))
  local page = math.min(v.page, pages)
  local rows, first, last = {}, (page - 1) * M.page_size + 1, math.min(page * M.page_size, #selected)
  for index = first, last do
    local row = copy_row(selected[index])
    row.family, row.cap, row.infinite = selected[index].family, selected[index].cap, selected[index].infinite
    row.display_name = selected[index].display_name
    rows[#rows + 1] = row
  end
  return {
    schema = M.schema, rows = rows, count = #selected, pages = pages, page = page,
    page_size = M.page_size, sort = v.sort, requested_sort = v.requested_sort,
    name_index_ready = v.name_index_ready, selected_visible = selected_visible
  }
end

function M.detail(catalogue, key, enrichment)
  if type(catalogue) ~= "table" or catalogue.schema ~= M.schema or type(key) ~= "string" then return nil, "invalid-detail-request" end
  enrichment = M.normalize_enrichment(enrichment)
  for _, source in ipairs(catalogue.rows or {}) do
    if type(source) == "table" and source.key == key then
      local row = copy_row(source)
      row.cap, row.family = positive_cap(enrichment, key), family_for(enrichment, key)
      row.infinite = row.infinite and not row.cap
      local details = enrichment and enrichment.details and enrichment.details[key]
      local copied, runtime_settings_binding, reason
      if type(details) == "table" then
        copied, reason = copy_plain(details, {nodes = 0}, 0)
        if reason then return nil, reason end
      end
      -- Schema-1 is a historical generic envelope. It has no validated
      -- runtime-settings witness, even if an untrusted caller appends a field
      -- named like the schema-2 bridge.
      local binding = enrichment and enrichment.schema == M.enrichment_schema
        and enrichment.kind == M.enrichment_kind and enrichment.runtime_settings_bindings
        and enrichment.runtime_settings_bindings[key]
      if type(binding) == "table" then
        runtime_settings_binding, reason = copy_plain(binding, {nodes = 0}, 0)
        if reason then return nil, reason end
      end
      return {schema = M.schema, technology = row, enrichment = copied,
        runtime_settings_binding = runtime_settings_binding}
    end
  end
  return nil, "unknown-technology"
end

function M.family_names(enrichment)
  enrichment = M.normalize_enrichment(enrichment)
  local known, names = {all = true, external = true}, {"all", "external"}
  local extras = {}
  for _, family in pairs((enrichment and enrichment.families) or {}) do
    if type(family) == "string" and not known[family] then known[family] = true; extras[#extras + 1] = family end
  end
  table.sort(extras)
  if #extras > 0 then table.insert(names, 1, "mir") end
  for _, family in ipairs(extras) do names[#names + 1] = family end
  return names
end

return M

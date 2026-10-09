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
  detail_summary_recipe_limit = 12,
  detail_summary_science_ingredient_limit = 16,
  detail_summary_owner_recipe_limit = 12,
  detail_recipe_benefit_window_limit = 64,
  enrichment_schema = 2,
  enrichment_kind = "portable-research-enrichment"
}

-- Player-local asynchronous translation window. It owns only presentation
-- labels; research IDs and policy remain in the browser core. Superseded
-- catalogue/locale generations deliberately retain their issued IDs until a
-- callback or timeout releases the shared outstanding window.
local translation_queue = {
  discovery_subject_limit = 128,
  discovery_text_limit = 32768,
  discovery_cache_byte_limit = 16 * 1024 * 1024,
  discovery_separator = "\31",
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
    search_values = {},
    search_bytes = 0,
    discovery_limited = false,
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
  cache.search_values = {}
  cache.search_bytes = 0
  cache.discovery_limited = false
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

function translation_queue.schedule_retry(cache, key, discovery)
  local retries = (cache.retry_count[key] or 0) + 1
  cache.retry_count[key] = retries
  if retries >= translation_queue.retry_limit then
    if discovery then cache.discovery_limited = true end
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

function translation_queue.requested(cache, key, id, tick, subjects, limited)
  if not translation_queue.can_request(cache) or type(id) ~= "number" then return false end
  subjects = subjects or 0
  if type(subjects) ~= "number" or subjects < 0 or subjects > translation_queue.discovery_subject_limit
      or subjects ~= math.floor(subjects) then return false end
  local request = {
    key = key,
    locale_generation = cache.locale_generation,
    catalogue_generation = cache.catalogue_generation,
    requested_tick = tick,
    discovery_subjects = subjects,
    discovery_limited = limited == true
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
function translation_queue.dispatch(cache, key, tick, request, subjects, limited)
  local ok, id = pcall(request)
  if ok and translation_queue.requested(cache, key, id, tick, subjects, limited) then return true end
  if (subjects or 0) ~= 0 or limited then cache.discovery_limited = true end
  translation_queue.request_declined(cache, key)
  return false
end

local function decoded_discovery(value, subjects)
  if type(value) ~= "string" or #value > translation_queue.discovery_text_limit then return nil end
  local parts, cursor = {}, 1
  while true do
    local boundary = string.find(value, translation_queue.discovery_separator, cursor, true)
    local part = string.sub(value, cursor, boundary and boundary - 1 or #value)
    if #part == 0 or #part > M.detail_string_limit then return nil end
    parts[#parts + 1] = part
    if #parts > subjects + 1 then return nil end
    if not boundary then break end
    cursor = boundary + 1
  end
  if #parts ~= subjects + 1 then return nil end
  return parts[1], table.concat(parts, " ", 2)
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
  if (request.discovery_subjects or 0) > 0 then
    local name, search = decoded_discovery(value, request.discovery_subjects)
    cache.search_values = cache.search_values or {}
    local retained = (cache.search_bytes or 0) - #(cache.search_values[request.key] or "")
    if search and retained + #search > translation_queue.discovery_cache_byte_limit then
      search, cache.discovery_limited = nil, true
    end
    cache.search_values[request.key] = search
    cache.search_bytes = retained + #(search or "")
    cache.discovery_limited = cache.discovery_limited or request.discovery_limited or name == nil
    translation_queue.resolve(cache, request.key, name or request.key)
  else
    cache.discovery_limited = cache.discovery_limited or request.discovery_limited
    local valid = type(value) == "string" and value ~= "" and #value <= M.detail_string_limit
    translation_queue.resolve(cache, request.key, valid and value or request.key)
  end
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
        translation_queue.schedule_retry(cache, request.key,
          (request.discovery_subjects or 0) > 0 or request.discovery_limited)
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

local function row_progression(row)
  local progression = type(row.progression) == "number" and row.progression == row.progression
    and row.progression ~= math.huge and row.progression ~= -math.huge
    and row.progression >= 0 and row.progression == math.floor(row.progression) and row.progression or 0
  return progression
end

local function copy_row(row)
  return {
    key = row.key,
    available = row.available == true,
    researched = row.researched == true,
    queued = row.queued == true,
    infinite = row.infinite == true,
    native_order = type(row.native_order) == "string" and string.sub(row.native_order, 1, M.detail_string_limit) or "",
    progression = row_progression(row)
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

-- Maximum-level settings use zero to mean an unbounded configured value.
-- A rich finite detail still needs a strictly positive effective cap, but its
-- default and directly configured values must retain that valid zero value.
local function valid_maximum_level_setting(value, expected_name)
  local values_are_valid = type(value) == "table"
    and finite_nonnegative_integer(value.default)
    and finite_nonnegative_integer(value.raw_direct)
    and finite_positive_integer(value.effective)
  return values_are_valid
    and only_fields(value, {name = true, default = true, raw_direct = true, effective = true,
      source = true, changed = true, changed_from_default = true, restart_required = true})
    and value.name == expected_name and (value.source == "direct" or value.source == "mirset1")
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
      or not valid_maximum_level_setting(settings.maximum_level, "ips-max-level-" .. family)
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
      recipe_ids = true,
      runtime_settings_bindings = true})
    or enrichment.schema ~= M.enrichment_schema or enrichment.kind ~= M.enrichment_kind
    or type(enrichment.caps) ~= "table" or type(enrichment.families) ~= "table"
    or type(enrichment.details) ~= "table" then
    return nil
  end
  local runtime_settings_bindings = enrichment.runtime_settings_bindings
  if runtime_settings_bindings == nil then runtime_settings_bindings = {} end
  if type(runtime_settings_bindings) ~= "table" then return nil end
  -- Rich details may be populated for only the selected subject. List facts
  -- stay complete, and every supplied detail must still belong to a family.
  local recipe_ids = enrichment.recipe_ids
  if recipe_ids == nil then recipe_ids = {} end
  if type(recipe_ids) ~= "table" then return nil end
  local count = 0
  for key, cap in pairs(enrichment.caps) do
    count = count + 1
    if count > M.catalogue_limit or not bounded_string(key)
      or not finite_positive_integer(cap) or enrichment.families[key] == nil then return nil end
  end
  for key, family in pairs(enrichment.families) do
    count = count + 1
    if count > M.catalogue_limit * 2 or not bounded_string(key)
      or not bounded_string(family) then return nil end
  end
  for key, detail in pairs(enrichment.details) do
    count = count + 1
    local valid, rich = valid_schema2_detail(detail, key, enrichment.families[key], enrichment.caps[key])
    if count > M.catalogue_limit * 3 or not bounded_string(key)
      or enrichment.families[key] == nil or not valid
      or (enrichment.caps[key] ~= nil and not rich) then return nil end
  end
  local recipe_count = 0
  for key, ids in pairs(recipe_ids) do
    if enrichment.families[key] == nil or not bounded_string(key)
      or not sorted_unique_strings(ids) then return nil end
    recipe_count = recipe_count + #ids
    if recipe_count > M.catalogue_limit * 10 then return nil end
    local detail = enrichment.details[key]
    if detail and detail.owner and not same_array(ids, detail.owner.affected_recipe_ids) then return nil end
    if detail and not detail.owner and #ids ~= 0 then return nil end
  end
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
-- continues to fall back to stable technology and family identifiers. The
-- optional sixth query argument adds a separate plain-text discovery index;
-- it cannot change the technology caption, ordering key or action identity.
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

-- Select and sort once, then let the public query shapes decide whether to
-- expose a bounded legacy page or a lightweight continuous-list record set.
-- Neither shape contains provider detail; rich data remains selected-subject
-- work so a long catalogue cannot turn a filter update into detail copying.
local function selected_rows(catalogue, view, enrichment, localized_search, selected_key, localized_discovery)
  if type(catalogue) ~= "table" or catalogue.schema ~= M.schema or type(catalogue.rows) ~= "table" then return nil, "invalid-catalogue" end
  if #catalogue.rows > M.catalogue_limit then return nil, "catalogue-limit" end
  enrichment = M.normalize_enrichment(enrichment)
  local selected, selected_visible, v = {}, false, normalized_view(view)
  local sort_by_name = v.sort == "name-asc" or v.sort == "name-desc"
  selected_key = type(selected_key) == "string" and selected_key or nil
  for _, source in ipairs(catalogue.rows) do
    if type(source) == "table" and type(source.key) == "string" then
      local key = source.key
      local cap, family = positive_cap(enrichment, key), family_for(enrichment, key)
      local infinite = source.infinite == true and not cap
      local mode_ok = v.mode == 1 or (v.mode == 2 and not infinite) or (v.mode == 3 and infinite)
      if mode_ok and status_matches(source, v.status) and family_matches(family, v.family)
        and not v.hidden[key] then
        local display_name = (sort_by_name or v.search ~= "") and displayed_label(localized_search, key) or nil
        local search_ok = v.search == "" or matches_search(
          key .. " " .. family .. " " .. display_name, v.search, v.spaced_search)
        if not search_ok and type(localized_discovery) == "table" then
          local text = localized_discovery[key]
          if type(text) == "string" and #text <= translation_queue.discovery_text_limit then
            search_ok = matches_search(text, v.search, v.spaced_search)
          end
        end
        if not search_ok and enrichment and enrichment.schema == M.enrichment_schema then
          local detail = enrichment.details[key]
          local ids = enrichment.recipe_ids and enrichment.recipe_ids[key]
          if ids then
            for _, recipe_id in ipairs(ids) do
              if matches_search(recipe_id, v.search, v.spaced_search) then search_ok = true; break end
            end
          else
            for _, benefit in ipairs(detail and detail.recipe_benefits or {}) do
              if matches_search(benefit.recipe_id, v.search, v.spaced_search) then
                search_ok = true
                break
              end
            end
          end
        end
        if search_ok then
          local row = {source = source, key = key, cap = cap, family = family, infinite = infinite}
          if not sort_by_name then
            row.progression = row_progression(source)
            row.native_order = type(source.native_order) == "string"
              and string.sub(source.native_order, 1, M.detail_string_limit) or ""
          end
          row.display_name = display_name
          if sort_by_name then row.display_sort = ascii_casefold(display_name) end
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
  return selected, selected_visible, v
end

local function copied_rows(selected, first, last, localized_search)
  local rows = {}
  for index = first, last do
    local chosen = selected[index]
    local row = copy_row(chosen.source)
    row.family, row.cap, row.infinite = chosen.family, chosen.cap, chosen.infinite
    row.display_name = chosen.display_name or displayed_label(localized_search, row.key)
    rows[#rows + 1] = row
  end
  return rows
end

-- Query only accepts copied, plain catalogue DTOs. It retains the historical
-- fixed-size page contract for developer callers.
function M.query(catalogue, view, enrichment, localized_search, selected_key, localized_discovery)
  local selected, selected_visible, v = selected_rows(catalogue, view, enrichment, localized_search, selected_key, localized_discovery)
  if not selected then return nil, selected_visible end
  local pages = math.max(1, math.ceil(#selected / M.page_size))
  local page = math.min(v.page, pages)
  local first, last = (page - 1) * M.page_size + 1, math.min(page * M.page_size, #selected)
  return {
    schema = M.schema, rows = copied_rows(selected, first, last, localized_search), count = #selected, pages = pages, page = page,
    page_size = M.page_size, sort = v.sort, requested_sort = v.requested_sort,
    name_index_ready = v.name_index_ready, selected_visible = selected_visible
  }
end

-- Continuous player views need one ordered lightweight record collection,
-- not a disguised enormous page size. The host remains responsible for its
-- actual widget budget and can retain or incrementally present these rows.
-- This function deliberately omits pages and page_size so callers do not
-- mistake the returned collection for the legacy paginator contract.
function M.query_all(catalogue, view, enrichment, localized_search, selected_key, localized_discovery)
  local selected, selected_visible, v = selected_rows(catalogue, view, enrichment, localized_search, selected_key, localized_discovery)
  if not selected then return nil, selected_visible end
  return {
    schema = M.schema, rows = copied_rows(selected, 1, #selected, localized_search), count = #selected,
    sort = v.sort, requested_sort = v.requested_sort,
    name_index_ready = v.name_index_ready, selected_visible = selected_visible
  }
end

local function copy_recipe_benefit(benefit)
  return {
    recipe_id = benefit.recipe_id,
    effect_change = benefit.effect_change,
    current_productivity_bonus = benefit.current_productivity_bonus,
    maximum_productivity = benefit.maximum_productivity,
    next_level_has_effective_benefit = benefit.next_level_has_effective_benefit
  }
end

local function copy_science_ingredient(ingredient)
  return {name = ingredient.name, amount = ingredient.amount}
end

local function copied_prefix(values, limit, copier)
  local result = {}
  for index = 1, math.min(#values, limit) do result[index] = copier(values[index]) end
  return result
end

local function copy_string(value)
  return value
end

local function copy_setting(value)
  return {
    name = value.name,
    default = value.default,
    raw_direct = value.raw_direct,
    effective = value.effective,
    source = value.source,
    changed = value.changed,
    changed_from_default = value.changed_from_default,
    restart_required = value.restart_required
  }
end

-- A schema-2 provider can legitimately describe a research that affects far
-- more rows than the generic copied-detail budget. Return a bounded summary
-- in that case and make every omitted collection explicit. The exact recipe
-- facts remain available through detail_recipe_benefits() below; a valid
-- broad research must never make its entire detail panel disappear.
local function copy_schema2_detail_summary(detail)
  if type(detail.owner) ~= "table" then
    return copy_plain(detail, {nodes = 0}, 0)
  end
  local owner_ids = detail.owner.affected_recipe_ids
  local benefits = detail.recipe_benefits
  local ingredients = detail.final_science.ingredients
  local result = {
    schema = detail.schema,
    family = detail.family,
    action = detail.action,
    owner = {
      technology_id = detail.owner.technology_id,
      stream_id = detail.owner.stream_id,
      action = detail.owner.action,
      reason = detail.owner.reason,
      affected_recipe_ids = copied_prefix(owner_ids, M.detail_summary_owner_recipe_limit, copy_string),
      affected_recipe_count = #owner_ids,
      affected_recipe_ids_complete = #owner_ids <= M.detail_summary_owner_recipe_limit
    },
    compiler_disposition = {
      inclusion = detail.compiler_disposition.inclusion,
      action = detail.compiler_disposition.action,
      reason = detail.compiler_disposition.reason,
      route_exclusions = {
        state = detail.compiler_disposition.route_exclusions.state,
        recipe_ids = {}
      }
    },
    final_science = {
      rationale = detail.final_science.rationale,
      ingredients = copied_prefix(ingredients, M.detail_summary_science_ingredient_limit, copy_science_ingredient),
      ingredient_count = #ingredients,
      ingredients_complete = #ingredients <= M.detail_summary_science_ingredient_limit
    },
    current_level = detail.current_level,
    recipe_benefits = copied_prefix(benefits, M.detail_summary_recipe_limit, copy_recipe_benefit),
    recipe_benefit_count = #benefits,
    recipe_benefits_complete = #benefits <= M.detail_summary_recipe_limit,
    next_level_eligible = detail.next_level_eligible,
    next_level_has_effective_benefit = detail.next_level_has_effective_benefit
  }
  if detail.effective_cap ~= nil then result.effective_cap = detail.effective_cap end
  if detail.settings ~= nil then
    result.settings = {
      maximum_level = copy_setting(detail.settings.maximum_level),
      enabled = copy_setting(detail.settings.enabled)
    }
  end
  return result
end

local function find_catalogue_row(catalogue, key)
  if type(catalogue) ~= "table" or catalogue.schema ~= M.schema or type(key) ~= "string" then
    return nil, "invalid-detail-request"
  end
  for _, source in ipairs(catalogue.rows or {}) do
    if type(source) == "table" and source.key == key then return source end
  end
  return nil, "unknown-technology"
end

-- Resolve a schema-2 recipe collection only after the provider envelope has
-- passed its full validation. Keeping this lookup private means the public
-- collection helpers never hand an adapter a provider-owned table.
local function validated_recipe_benefits(catalogue, key, enrichment)
  local source, source_reason = find_catalogue_row(catalogue, key)
  if not source then return nil, nil, source_reason end
  local normalized = M.normalize_enrichment(enrichment)
  local detail = normalized and normalized.schema == M.enrichment_schema
    and normalized.kind == M.enrichment_kind and normalized.details and normalized.details[key]
  local benefits = type(detail) == "table" and detail.recipe_benefits or nil
  return source, type(benefits) == "table" and benefits or nil
end

local function include_summary_range(summary, minimum, maximum, value)
  if summary[minimum] == nil or value < summary[minimum] then summary[minimum] = value end
  if summary[maximum] == nil or value > summary[maximum] then summary[maximum] = value end
end

-- Return the complete lightweight recipe index for one selected research.
-- Native list controls can use the stable IDs as captions (or look up their
-- localized recipe names) without constructing a rich widget tree for every
-- recipe. This is deliberately one validated access per selected detail;
-- callers should not drain detail_recipe_benefits() merely to build a list.
-- The summary lets a detail pane describe the whole collection without
-- inspecting every rich recipe record again.
function M.detail_recipe_index(catalogue, key, enrichment)
  local source, benefits, source_reason = validated_recipe_benefits(catalogue, key, enrichment)
  if not source then return nil, source_reason end
  local ids = {}
  local summary = {
    count = 0,
    effective_recipe_count = 0,
    effect_change_min = nil,
    effect_change_max = nil,
    current_productivity_bonus_min = nil,
    current_productivity_bonus_max = nil,
    maximum_productivity_min = nil,
    maximum_productivity_max = nil
  }
  for index, benefit in ipairs(benefits or {}) do
    ids[index] = benefit.recipe_id
    summary.count = summary.count + 1
    if benefit.next_level_has_effective_benefit then
      summary.effective_recipe_count = summary.effective_recipe_count + 1
    end
    include_summary_range(summary, "effect_change_min", "effect_change_max", benefit.effect_change)
    include_summary_range(summary, "current_productivity_bonus_min", "current_productivity_bonus_max",
      benefit.current_productivity_bonus)
    include_summary_range(summary, "maximum_productivity_min", "maximum_productivity_max",
      benefit.maximum_productivity)
  end
  return {schema = M.schema, technology = source.key, ids = ids, summary = summary}
end

-- Return a bounded, explicitly resumable collection of validated recipe facts.
-- offset is one-based and limit is clamped to the fixed internal work budget.
-- This is a data-access cursor, not a player-facing paginator: hosts may
-- present it in any continuous scrolling form their target can support.
function M.detail_recipe_benefits(catalogue, key, enrichment, offset, limit)
  local source, benefits, source_reason = validated_recipe_benefits(catalogue, key, enrichment)
  if not source then return nil, source_reason end
  if type(benefits) ~= "table" then
    return {schema = M.schema, technology = source.key, count = 0, offset = 1, rows = {}, complete = true}
  end
  local requested_offset = tonumber(offset)
  local start = finite_nonnegative_integer(requested_offset) and requested_offset or 1
  start = math.max(1, math.min(start, #benefits + 1))
  local requested_limit = tonumber(limit)
  local requested = finite_positive_integer(requested_limit) and requested_limit
    or M.detail_recipe_benefit_window_limit
  requested = math.min(requested, M.detail_recipe_benefit_window_limit)
  local last = math.min(#benefits, start + requested - 1)
  local rows = {}
  for index = start, last do rows[#rows + 1] = copy_recipe_benefit(benefits[index]) end
  local complete = last >= #benefits
  local next_offset = nil
  if not complete then next_offset = last + 1 end
  return {
    schema = M.schema,
    technology = source.key,
    count = #benefits,
    offset = start,
    rows = rows,
    complete = complete,
    next_offset = next_offset
  }
end

function M.detail(catalogue, key, enrichment)
  local source, source_reason = find_catalogue_row(catalogue, key)
  if not source then return nil, source_reason end
  enrichment = M.normalize_enrichment(enrichment)
  local row = copy_row(source)
  row.cap, row.family = positive_cap(enrichment, key), family_for(enrichment, key)
  row.infinite = row.infinite and not row.cap
  local details = enrichment and enrichment.details and enrichment.details[key]
  if enrichment and enrichment.schema == M.enrichment_schema
      and enrichment.families[key] and details == nil then return nil, "detail-deferred" end
  local copied, runtime_settings_binding, reason
  if type(details) == "table" then
    if enrichment.schema == M.enrichment_schema and enrichment.kind == M.enrichment_kind then
      copied, reason = copy_schema2_detail_summary(details)
    else
      copied, reason = copy_plain(details, {nodes = 0}, 0)
    end
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

-- Private copied-data view consumed by the existing host, not a stable SDK
-- contract or a prediction of lab throughput. Reject incomplete/invalid rates
-- instead of presenting an unavailable observation as zero.
function M.production_load_check(snapshot)
  local function scalar_name(value)
    return type(value) == "string" and value ~= "" and #value <= M.detail_string_limit
  end
  local function nonnegative(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
  end
  local function positive_index(value)
    return nonnegative(value) and value > 0 and value == math.floor(value)
  end
  if type(snapshot) ~= "table" or snapshot.schema ~= 1 or snapshot.kind ~= "science-production-snapshot"
      or not scalar_name(snapshot.technology_id) or not scalar_name(snapshot.force_name)
      or not scalar_name(snapshot.surface_name) or not positive_index(snapshot.force_index)
      or not positive_index(snapshot.surface_index) or not nonnegative(snapshot.tick)
      or snapshot.tick ~= math.floor(snapshot.tick) or type(snapshot.rows) ~= "table" then return nil end
  local count = 0
  for index in pairs(snapshot.rows) do
    count = count + 1
    if count > M.detail_summary_science_ingredient_limit or not positive_index(index)
        or index > M.detail_summary_science_ingredient_limit then return nil end
  end
  if count == 0 or #snapshot.rows ~= count then return nil end
  local rows, seen = {}, {}
  for index = 1, count do
    local row = snapshot.rows[index]
    if type(row) ~= "table" or not scalar_name(row.name) or seen[row.name] or row.quality ~= "normal"
        or not nonnegative(row.produced) or not nonnegative(row.consumed) then return nil end
    seen[row.name] = true
    rows[index] = {name = row.name, produced = row.produced, consumed = row.consumed,
      balance = row.produced - row.consumed}
  end
  return {technology_id = snapshot.technology_id, force_index = snapshot.force_index,
    force_name = snapshot.force_name, surface_index = snapshot.surface_index,
    surface_name = snapshot.surface_name, tick = snapshot.tick, rows = rows}
end

return M

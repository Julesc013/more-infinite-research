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
  return {key = row.key, available = row.available == true, researched = row.researched == true, queued = row.queued == true, infinite = row.infinite == true}
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
    current_level = true, recipe_benefits = true, next_level_has_effective_benefit = true,
    settings = true}
  if not only_fields(detail, allowed) then return false end
  local rich = detail.owner ~= nil or detail.compiler_disposition ~= nil or detail.final_science ~= nil
    or detail.effective_cap ~= nil or detail.current_level ~= nil or detail.recipe_benefits ~= nil
    or detail.next_level_has_effective_benefit ~= nil or detail.settings ~= nil
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
  if not finite_positive_integer(detail.effective_cap) or detail.effective_cap ~= cap
    or not finite_positive_integer(detail.current_level)
    or type(detail.next_level_has_effective_benefit) ~= "boolean"
    or not dense_array(detail.recipe_benefits) then return false end
  local settings = detail.settings
  if type(settings) ~= "table" or not only_fields(settings, {maximum_level = true, enabled = true})
    or not valid_setting(settings.maximum_level, "ips-max-level-" .. family, "number")
    or not valid_setting(settings.enabled, "ips-enable-" .. family, "boolean")
    or settings.maximum_level.effective ~= cap then return false end
  local benefit_ids, any_effective, previous = {}, false, nil
  for index, benefit in ipairs(detail.recipe_benefits) do
    if type(benefit) ~= "table" or not only_fields(benefit, {recipe_id = true, effect_change = true,
        current_productivity_bonus = true, maximum_productivity = true, next_level_has_effective_benefit = true})
      or not bounded_string(benefit.recipe_id) or not finite_positive(benefit.effect_change)
      or not finite_nonnegative(benefit.current_productivity_bonus) or not finite_nonnegative(benefit.maximum_productivity)
      or benefit.current_productivity_bonus > benefit.maximum_productivity
      or type(benefit.next_level_has_effective_benefit) ~= "boolean"
      or (previous and benefit.recipe_id <= previous) then return false end
    local expected_effective = detail.current_level <= cap
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
  if not only_fields(enrichment, {schema = true, kind = true, caps = true, families = true, details = true})
    or enrichment.schema ~= M.enrichment_schema or enrichment.kind ~= M.enrichment_kind
    or type(enrichment.caps) ~= "table" or type(enrichment.families) ~= "table"
    or type(enrichment.details) ~= "table" then
    return nil
  end
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
  return enrichment
end

local function positive_cap(enrichment, key)
  local caps = enrichment and enrichment.caps
  local cap = caps and caps[key]
  return type(cap) == "number" and cap > 0 and cap or nil
end

local function family_for(enrichment, key)
  local families = enrichment and enrichment.families
  local family = families and families[key]
  return type(family) == "string" and family or "external"
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
  local sort = view.sort == "name-desc" and "name-desc" or "name-asc"
  return {mode = mode, status = status, page = page, search = string.lower(search), family = family, sort = sort, hidden = type(view.hidden) == "table" and view.hidden or {}}
end

local function status_matches(row, status)
  if status == 1 then return true end
  if status == 2 then return row.available end
  if status == 3 then return not row.available and not row.researched end
  return row.queued
end

-- Query only accepts copied, plain catalogue DTOs. It returns a fresh plain
-- page so a consumer cannot retain adapter-owned state.
function M.query(catalogue, view, enrichment)
  if type(catalogue) ~= "table" or catalogue.schema ~= M.schema or type(catalogue.rows) ~= "table" then return nil, "invalid-catalogue" end
  if #catalogue.rows > M.catalogue_limit then return nil, "catalogue-limit" end
  enrichment = M.normalize_enrichment(enrichment)
  local selected, v = {}, normalized_view(view)
  for _, source in ipairs(catalogue.rows) do
    if type(source) == "table" and type(source.key) == "string" then
      local row = copy_row(source)
      local cap, family = positive_cap(enrichment, row.key), family_for(enrichment, row.key)
      row.cap, row.family = cap, family
      row.infinite = row.infinite and not cap
      local mode_ok = v.mode == 1 or (v.mode == 2 and not row.infinite) or (v.mode == 3 and row.infinite)
      local search = string.lower(row.key .. " " .. family)
      local search_ok = v.search == "" or string.find(search, v.search, 1, true) ~= nil
      if mode_ok and status_matches(row, v.status) and (v.family == "all" or family == v.family) and not v.hidden[row.key] and search_ok then selected[#selected + 1] = row end
    end
  end
  table.sort(selected, function(left, right)
    if left.key == right.key then return false end
    return v.sort == "name-desc" and left.key > right.key or left.key < right.key
  end)
  local pages = math.max(1, math.ceil(#selected / M.page_size))
  local page = math.min(v.page, pages)
  local rows, first, last = {}, (page - 1) * M.page_size + 1, math.min(page * M.page_size, #selected)
  for index = first, last do
    local row = copy_row(selected[index])
    row.family, row.cap, row.infinite = selected[index].family, selected[index].cap, selected[index].infinite
    rows[#rows + 1] = row
  end
  return {schema = M.schema, rows = rows, count = #selected, pages = pages, page = page, page_size = M.page_size, sort = v.sort}
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
      local copied, reason
      if type(details) == "table" then
        copied, reason = copy_plain(details, {nodes = 0}, 0)
        if reason then return nil, reason end
      end
      return {schema = M.schema, technology = row, enrichment = copied}
    end
  end
  return nil, "unknown-technology"
end

function M.family_names(enrichment)
  enrichment = M.normalize_enrichment(enrichment)
  local known, names = {all = true, external = true}, {"all", "external"}
  for _, family in pairs((enrichment and enrichment.families) or {}) do
    if type(family) == "string" and not known[family] then known[family] = true; names[#names + 1] = family end
  end
  table.sort(names)
  return names
end

return M

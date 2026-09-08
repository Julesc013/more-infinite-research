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
  detail_key_length = 160
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
  local known, names = {all = true, external = true}, {"all", "external"}
  for _, family in pairs((enrichment and enrichment.families) or {}) do
    if type(family) == "string" and not known[family] then known[family] = true; names[#names + 1] = family end
  end
  table.sort(names)
  return names
end

return M

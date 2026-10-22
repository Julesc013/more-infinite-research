-- Pure, detached Research Library records. The host owns view persistence,
-- native object acquisition, translations, GUI work, and every event.
local M = {view_schema = 3}

local MAX_SEARCH = 160
local MAX_HIDDEN = 128
local MAX_NATIVE_ROWS = 30000
local MAX_PREREQUISITES = 64
local MAX_EFFECTS = 16
local MAX_INGREDIENTS = 16
local MAX_TEXT = 1024
local INFINITE_MAX_LEVEL = 4294967295

local function finite_integer(value)
  return type(value) == "number" and value == value and value > -math.huge
    and value < math.huge and value == math.floor(value)
end

local function bounded_string(value, limit)
  return type(value) == "string" and #value <= limit and value or nil
end

local function native_read(value, key)
  if value == nil then return nil end
  local ok, result = pcall(function() return value[key] end)
  if ok then return result end
  return nil
end

local function ascii_casefold(value)
  return (string.gsub(value, "%u", function(letter)
    return string.char(string.byte(letter) + 32)
  end))
end

local function searchable(value)
  local normalized = string.gsub(ascii_casefold(value), "[%s_-]+", " ")
  return normalized:gsub("^ ", ""):gsub(" $", "")
end

local function matches(value, search)
  if string.find(ascii_casefold(value), search, 1, true) then return true end
  return string.find(searchable(value), search, 1, true) ~= nil
end

local function copy_hidden(value)
  local result, count = {}, 0
  if type(value) ~= "table" then return result end
  for index = 1, math.min(#value, MAX_HIDDEN) do
    local id = bounded_string(value[index], MAX_SEARCH)
    if id and not result[id] then result[id], count = true, count + 1 end
  end
  if count >= MAX_HIDDEN then return result end
  for id, hidden in pairs(value) do
    if count >= MAX_HIDDEN then break end
    if hidden == true and type(id) == "string" and #id <= MAX_SEARCH and not result[id] then
      result[id], count = true, count + 1
    end
  end
  return result
end

local function accepted(value, alternatives, fallback)
  for index = 1, #alternatives do
    if value == alternatives[index] then return value end
  end
  return fallback
end

-- Preserve the shipped schema-3 defaults and portable search/sort enums while
-- copying every retained value away from host-owned player state.
function M.normalize(view)
  view = type(view) == "table" and view or {}
  local mode = tonumber(view.mode)
  if not finite_integer(mode) or mode < 1 or mode > 3 then mode = 1 end
  local status = tonumber(view.status)
  if not finite_integer(status) or status < 1 or status > 4 then status = 1 end
  local page = tonumber(view.page)
  if not finite_integer(page) or page < 1 then page = 1 end
  local search = bounded_string(view.search, MAX_SEARCH) or ""
  local settings_search = bounded_string(view.settings_search, MAX_SEARCH) or ""
  local selected = bounded_string(view.selected, MAX_SEARCH)
  local visibility = tonumber(view.visibility)
  if not finite_integer(visibility) or visibility < 1 or visibility > 3 then visibility = 1 end
  local effect_page = tonumber(view.effect_page)
  local result = {
    schema = M.view_schema,
    mode = mode,
    status = status,
    page = page,
    search = searchable(search),
    tab = accepted(view.tab, {"research", "settings", "queue", "availability", "help"}, "research"),
    settings_scope = accepted(view.settings_scope, {"research", "options"}, "research"),
    effect_page = finite_integer(effect_page) and math.max(1, math.floor(effect_page)) or 1,
    family = accepted(view.family, {"mir", "external", "all", "streams", "native"}, "mir"),
    sort = accepted(view.sort, {"progression", "native", "name-asc", "name-desc"}, "progression"),
    stable_sort = accepted(view.stable_sort, {"progression", "native"}, "progression"),
    settings_search = searchable(settings_search),
    visibility = visibility,
    hidden = copy_hidden(view.hidden)
  }
  if selected then result.selected = selected end
  return result
end

local function copy_declaration(value)
  if type(value) ~= "table" then return nil end
  local id = bounded_string(value.id, MAX_SEARCH)
  if not id then return nil end
  local settings = {}
  if type(value.settings) == "table" then
    for index = 1, #value.settings do
      local setting = bounded_string(value.settings[index], MAX_SEARCH)
      if not setting then return nil end
      settings[#settings + 1] = setting
    end
  end
  return {
    id = id,
    family = bounded_string(value.family, MAX_SEARCH) or "mir",
    progression = finite_integer(value.progression) and math.max(0, value.progression) or 0,
    native_order = bounded_string(value.native_order, MAX_TEXT) or "",
    setting = bounded_string(value.setting, MAX_SEARCH),
    settings = settings,
    cap_setting = bounded_string(value.cap_setting, MAX_SEARCH),
    recipe = bounded_string(value.recipe, MAX_SEARCH),
    locale_key = bounded_string(value.locale_key, MAX_TEXT)
  }
end

local function declarations(catalogue)
  local rows, by_id = {}, {}
  if type(catalogue) ~= "table" then return rows, by_id end
  for index = 1, #catalogue do
    local entry = copy_declaration(catalogue[index])
    if entry and not by_id[entry.id] then
      rows[#rows + 1], by_id[entry.id] = entry, entry
    end
  end
  return rows, by_id
end

local function technology_for(force, id)
  return native_read(native_read(force, "technologies"), id)
end

local function technology_name(technology)
  -- LuaForce.research_queue is an array of TechnologyID, which permits a
  -- technology object or its string prototype name.
  local direct = bounded_string(technology, MAX_SEARCH)
  if direct then return direct end
  return bounded_string(native_read(technology, "name"), MAX_SEARCH)
end

local function queue_facts(force)
  local counts, first, current = {}, {}, technology_name(native_read(force, "current_research"))
  local queue = native_read(force, "research_queue")
  if queue == nil then return counts, first, current end
  local index = 0
  for _, technology in ipairs(queue) do
    index = index + 1
    local id = technology_name(technology)
    if id then
      counts[id] = (counts[id] or 0) + 1
      if first[id] == nil then first[id] = index end
    end
  end
  return counts, first, current
end

-- Runtime ownership state is deliberately injected by the host. LuaForce has
-- no MIR cap member, and this module must not reach into lifecycle storage.
local function cap_fact(context, force, id)
  local provider = type(context) == "table" and context.cap_provider or nil
  if type(provider) ~= "function" then return nil, "unavailable" end
  local ok, caps = pcall(provider, force)
  if not ok or type(caps) ~= "table" then return nil, "unavailable" end
  local cap = caps[id]
  if finite_integer(cap) and cap > 0 then return cap, "finite" end
  return nil, "unlimited"
end

local function prerequisite_facts(technology)
  if technology == nil then return {}, false, true end
  local prerequisites = native_read(technology, "prerequisites")
  local names, ready = {}, native_read(technology, "enabled") ~= false
  if prerequisites == nil then return names, ready, true end
  local complete = true
  local ok = pcall(function()
    for key, prerequisite in pairs(prerequisites) do
      if #names >= MAX_PREREQUISITES then complete = false; return end
      local name = bounded_string(key, MAX_SEARCH) or technology_name(prerequisite)
      if name then names[#names + 1] = name end
      if native_read(prerequisite, "researched") ~= true then ready = false end
    end
  end)
  if not ok then return {}, false, false end
  table.sort(names)
  if not complete then ready = false end
  return names, ready, complete
end

local function native_maximum(technology)
  local prototype = native_read(technology, "prototype")
  local maximum = native_read(prototype, "max_level")
  if finite_integer(maximum) then return maximum, maximum >= INFINITE_MAX_LEVEL end
  return nil, nil
end

local function display_name(translations, declaration, id)
  local translated = type(translations) == "table" and bounded_string(translations[id], MAX_TEXT) or nil
  return translated or id
end

local function copy_settings(settings)
  local result = {}
  for index = 1, #settings do result[index] = settings[index] end
  return result
end

local function row_for(force, declaration, id, technology, queue_count, queue_index, current, translations, context)
  local cap, cap_state = cap_fact(context, force, id)
  local maximum, native_infinite = native_maximum(technology)
  local finite = nil
  if native_infinite ~= nil then finite = not native_infinite end
  if cap then finite = true end
  local prerequisites, ready, prerequisites_complete = prerequisite_facts(technology)
  local queued_count = queue_count[id] or 0
  local is_current = current == id
  local researched = native_read(technology, "researched") == true
  local enabled = native_read(technology, "enabled") == true
  local visible = native_read(technology, "visible_when_disabled") == true
  local native_order = bounded_string(native_read(technology, "order"), MAX_TEXT)
    or (declaration and declaration.native_order) or ""
  local family = declaration and declaration.family or "external"
  local name = display_name(translations, declaration, id)
  local row = {
    id = id,
    name = name,
    family = family,
    progression = declaration and declaration.progression or 0,
    order = native_order,
    native_order = native_order,
    locale_key = declaration and declaration.locale_key or nil,
    setting = declaration and declaration.setting or nil,
    settings = declaration and copy_settings(declaration.settings) or {},
    cap_setting = declaration and declaration.cap_setting or nil,
    recipe = declaration and declaration.recipe or nil,
    finite = finite,
    max_level = maximum,
    cap = cap,
    cap_state = cap_state,
    current_level = native_read(technology, "level"),
    researched = researched,
    enabled = enabled,
    visible = visible,
    queued_count = queued_count,
    queue_index = queue_index[id],
    current = is_current,
    ready = ready,
    prerequisites = prerequisites,
    prerequisites_complete = prerequisites_complete,
    hidden = false
  }
  if technology == nil then row.status = "missing"
  elseif queued_count > 0 or is_current then row.status = "queued"
  elseif ready then row.status = "ready"
  else row.status = "locked" end
  return row
end

local function wants_native_catalogue(family)
  return family == "all" or family == "external" or family == "native"
end

local function family_matches(row, family)
  if family == "all" or family == "native" then return true end
  if family == "mir" then return row.family ~= "external" end
  return row.family == family
end

local function status_matches(row, status)
  if status == 1 then return true end
  if status == 2 then return row.status == "ready" end
  if status == 3 then return row.status == "locked" end
  return row.status == "queued" end

local function mode_matches(row, mode)
  if mode == 1 then return true end
  if mode == 2 then return row.finite == true end
  return row.finite == false
end

local function row_matches(row, view)
  if not family_matches(row, view.family) or not status_matches(row, view.status)
    or not mode_matches(row, view.mode) then return false end
  if view.visibility == 1 and view.hidden[row.id] then return false end
  if view.visibility == 2 and not view.hidden[row.id] then return false end
  if view.search == "" then return true end
  return matches(row.id .. " " .. row.family .. " " .. row.name .. " "
    .. (row.recipe or "") .. " " .. (row.locale_key or ""), view.search)
end

local function ordered(left, right, sort)
  if sort == "name-asc" or sort == "name-desc" then
    local left_name, right_name = ascii_casefold(left.name), ascii_casefold(right.name)
    if left_name ~= right_name then
      return sort == "name-asc" and left_name < right_name or left_name > right_name
    end
  elseif sort == "native" then
    if left.native_order ~= right.native_order then return left.native_order < right.native_order end
    if left.progression ~= right.progression then return left.progression < right.progression end
  else
    if left.progression ~= right.progression then return left.progression < right.progression end
    if left.native_order ~= right.native_order then return left.native_order < right.native_order end
  end
  return left.id < right.id
end

-- Default `mir` builds rows only from authored declarations. Explicit native,
-- external, or all views may enumerate the native catalogue exactly once.
function M.rows(force, catalogue, view, translations, context)
  local normalized = M.normalize(view)
  local declared, by_id = declarations(catalogue)
  local queue_count, queue_index, current = queue_facts(force)
  local candidates = {}
  if wants_native_catalogue(normalized.family) then
    local technologies = native_read(force, "technologies")
    local count = 0
    if technologies ~= nil then
      local ok = pcall(function()
        for name, technology in pairs(technologies) do
          count = count + 1
          if count > MAX_NATIVE_ROWS then error("MIR Library native catalogue limit") end
          local id = bounded_string(name, MAX_SEARCH) or technology_name(technology)
          if id then candidates[id] = technology end
        end
      end)
      if not ok then return {} end
    end
  else
    for index = 1, #declared do
      local id = declared[index].id
      candidates[#candidates + 1] = {id = id, technology = technology_for(force, id)}
    end
  end
  local selected = {}
  if wants_native_catalogue(normalized.family) then
    local native_candidates = candidates
    candidates = {}
    for id, technology in pairs(native_candidates) do
      candidates[#candidates + 1] = {id = id, technology = technology}
    end
  end
  for _, candidate in ipairs(candidates) do
    local id, technology = candidate.id, candidate.technology
    local row = row_for(force, by_id[id], id, technology, queue_count, queue_index, current, translations, context)
    row.hidden = normalized.hidden[id] == true
    if row_matches(row, normalized) then selected[#selected + 1] = row end
  end
  table.sort(selected, function(left, right) return ordered(left, right, normalized.sort) end)
  return selected
end

local function copy_effects(technology)
  local effects = native_read(native_read(technology, "prototype"), "effects")
  local result, complete = {}, true
  if effects == nil then return result, complete end
  local ok = pcall(function()
    for index, effect in ipairs(effects) do
      if index > MAX_EFFECTS then complete = false; break end
      -- TechnologyModifier fields are variant-specific. The declared gear
      -- effect is productivity, so only read that variant's native fields.
      local kind = bounded_string(native_read(effect, "type"), MAX_SEARCH)
      local copied = {type = kind}
      if kind == "change-recipe-productivity" then
        copied.recipe = bounded_string(native_read(effect, "recipe"), MAX_SEARCH)
        copied.change = native_read(effect, "change")
      elseif kind == "unlock-recipe" then
        copied.recipe = bounded_string(native_read(effect, "recipe"), MAX_SEARCH)
      end
      result[#result + 1] = copied
    end
  end)
  return ok and result or {}, ok and complete or false
end

local function copy_cost(technology)
  local result = {
    count = native_read(technology, "research_unit_count"),
    count_formula = native_read(technology, "research_unit_count_formula"),
    energy = native_read(technology, "research_unit_energy"),
    ingredients = {}
  }
  local ingredients = native_read(technology, "research_unit_ingredients")
  if ingredients == nil then return result, true end
  local complete = true
  local ok = pcall(function()
    for index, ingredient in ipairs(ingredients) do
      if index > MAX_INGREDIENTS then complete = false; break end
      result.ingredients[#result.ingredients + 1] = {
        name = bounded_string(native_read(ingredient, "name"), MAX_SEARCH),
        amount = native_read(ingredient, "amount")
      }
    end
  end)
  return result, ok and complete or false
end

-- Detail reads one selected native technology directly. It never builds the
-- full native catalogue or asks Factorio to translate, navigate, or mutate.
function M.detail(force, catalogue, view, translations, context)
  local normalized = M.normalize(view)
  local id = normalized.selected
  if id == nil then return nil, "no_selection" end
  local declared, by_id = declarations(catalogue)
  local queue_count, queue_index, current = queue_facts(force)
  local technology = technology_for(force, id)
  if technology == nil then return nil, "technology_not_found" end
  local row = row_for(force, by_id[id], id, technology, queue_count, queue_index, current, translations, context)
  local effects, effects_complete = copy_effects(technology)
  local cost, ingredients_complete = copy_cost(technology)
  row.effects, row.effects_complete = effects, effects_complete
  row.cost, row.ingredients_complete = cost, ingredients_complete
  return row
end

return M

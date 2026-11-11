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
local MAX_SEARCH_TEXT = 32768
local MAX_RECIPE_TARGETS = 512
local MAX_NATIVE_EFFECT_SCAN = 1024
local INFINITE_MAX_LEVEL = 4294967295
local SEARCH_LABEL_SEPARATOR = "\31"
local PRODUCTIVITY_HEADROOM_EPSILON = 0.000000001

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

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
  return (string.gsub(value, "[A-Z]", function(letter)
    return string.char(string.byte(letter) + 32)
  end))
end

local GERMAN_SEARCH_FOLD = {["Ä"]="ä", ["Ö"]="ö", ["Ü"]="ü", ["ß"]="ss"}

-- Match complete UTF-8 characters. Only matching text is folded; saved input
-- and display text keep their original bytes, and sorting keeps its own policy.
function M.search_casefold(value)
  local folded = ascii_casefold(value)
  return (folded:gsub("\195.", GERMAN_SEARCH_FOLD):gsub("ẞ", "ss"))
end

local function searchable(value)
  local normalized = string.gsub(M.search_casefold(value), "[%s_-]+", " ")
  return normalized:gsub("^ ", ""):gsub(" $", "")
end

local function matches(value, search)
  if string.find(M.search_casefold(value), search, 1, true) then return true end
  return string.find(searchable(value), search, 1, true) ~= nil
end

local function copy_hidden(value)
  local result, visited = {}, 0
  if type(value) ~= "table" then return result end
  -- Bound inputs by entries inspected, rather than only accepted strings.
  -- A hostile map full of invalid keys must not force an unbounded scan.
  for index = 1, #value do
    if visited >= MAX_HIDDEN then return result end
    visited = visited + 1
    local id = bounded_string(value[index], MAX_SEARCH)
    if id then result[id] = true end
  end
  for id, hidden in pairs(value) do
    if visited >= MAX_HIDDEN then break end
    visited = visited + 1
    if hidden == true and type(id) == "string" and #id <= MAX_SEARCH then
      result[id] = true
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
  -- Pages are retained for the published browser bridge even though this
  -- first Library list is continuous.  Keep the historical catalogue ceiling
  -- so an unbounded remote value cannot become durable player state.
  if not finite_integer(page) or page < 1 or page > MAX_NATIVE_ROWS then page = 1 end
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
    tab = accepted(view.tab, {"research", "settings", "queue", "help"}, "research"),
    settings_scope = accepted(view.settings_scope, {"research", "options"}, "research"),
    effect_page = finite_integer(effect_page) and math.max(1, math.floor(effect_page)) or 1,
    -- Family descriptors are authored catalogue metadata.  This pure query
    -- layer preserves any bounded identifier; the runtime host decides which
    -- descriptors are currently published by its bounded declaration list.
    family = bounded_string(view.family, MAX_SEARCH) or "mir",
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

-- The runtime host supplies this compact exact set from its authored
-- catalogue. It intentionally names only MIR's hidden migration-credit
-- holders: foreign hidden technologies remain available to all/external
-- views, and this pure model never imports emission or recovery modules.
local function private_credit(context, id)
  local ids = type(context) == "table" and context.private_credit_ids or nil
  if type(ids) ~= "table" then return false end
  local ok, value = pcall(function() return ids[id] end)
  return ok and value == true
end

local function technology_for(force, id)
  return native_read(native_read(force, "technologies"), id)
end

-- Discovery Tree uses per-force enabled state. The host may additionally
-- supply its last observed discovery state for research MIR itself capped.
-- Personal hidden/show-all filters never override this upstream restriction.
function M.technology_visible(technology, id, context)
  if type(context) ~= "table" or context.discovery_tree ~= true then return true end
  if native_read(technology, "enabled") == true then return true end
  local visible = context.discovery_visibility
  return type(visible) == "table" and visible[id] == true
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
  -- Runtime queues are native player state. Preserve every duplicate and its
  -- native ordering rather than presenting a bounded partial queue; this is
  -- intentionally O(Q) during an explicit Library render/detail request.
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
  local names, ready = {}, native_read(technology, "enabled") == true
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
  local translated = type(translations) == "table" and bounded_string(translations[id], MAX_SEARCH_TEXT) or nil
  if translated then
    local separator = string.find(translated, SEARCH_LABEL_SEPARATOR, 1, true)
    if separator then
      local name = bounded_string(string.sub(translated, 1, separator - 1), MAX_TEXT)
      local search = bounded_string(string.sub(translated, separator + 1), MAX_SEARCH_TEXT)
      return name or id, search or translated
    end
    return bounded_string(translated, MAX_TEXT) or id, translated
  end
  return id, id
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
  local prototype = native_read(technology, "prototype")
  local native_hidden = native_read(prototype, "hidden") == true
  -- Only the host's explicit engine capability admits this modern field.
  -- Historical prototypes must never be probed for research_trigger.
  local triggered = type(context) == "table" and context.research_triggers_supported == true
    and native_read(prototype, "research_trigger") ~= nil
  ready = ready and enabled and not researched and not native_hidden and not triggered
  local visible = native_read(technology, "visible_when_disabled") == true
  local native_order = bounded_string(native_read(technology, "order"), MAX_TEXT)
    or (declaration and declaration.native_order) or ""
  local family = declaration and declaration.family or "external"
  local name, search_text = display_name(translations, declaration, id)
  local row = {
    id = id,
    name = name,
    search_text = search_text,
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
  elseif researched then row.status = "complete"
  elseif not enabled then row.status = "disabled"
  elseif ready then row.status = "ready"
  else row.status = "locked" end
  return row
end

local function copy_recipe_targets(technology)
  local prototype = native_read(technology, "prototype")
  local effects = native_read(prototype, "effects")
  local result, seen, complete = {}, {}, true
  if effects == nil then return result, complete end
  local ok = pcall(function()
    for index, effect in ipairs(effects) do
      if index > MAX_NATIVE_EFFECT_SCAN then complete = false; break end
      local kind = native_read(effect, "type")
      if kind == "unlock-recipe" or kind == "change-recipe-productivity" then
        local id = bounded_string(native_read(effect, "recipe"), MAX_TEXT)
        if id and not seen[id] then
          if #result >= MAX_RECIPE_TARGETS then complete = false; break end
          seen[id] = true
          result[#result + 1] = id
        end
      end
    end
  end)
  return ok and result or {}, ok and complete or false
end

local function wants_native_catalogue(family)
  return family == "all" or family == "external"
end

-- Read only the selected authored research's named productive recipes. Lists
-- never call this helper, and no native object or derived cache is retained.
local function recipe_benefits(force, technology, row, context)
  if type(context) ~= "table" or context.recipe_productivity_supported ~= true then
    return nil, "unsupported"
  end
  local effects = native_read(native_read(technology, "prototype"), "effects")
  local ids, changes, complete, only_productivity = {}, {}, true, true
  local ok = pcall(function()
    for index, effect in ipairs(effects or {}) do
      if index > MAX_NATIVE_EFFECT_SCAN then complete = false; return end
      if native_read(effect, "type") == "change-recipe-productivity" then
        local id = bounded_string(native_read(effect, "recipe"), MAX_TEXT)
        local change = native_read(effect, "change")
        if not id or id == "" or not finite_number(change) then complete = false; return end
        if changes[id] == nil then
          ids[#ids + 1], changes[id] = id, 0
        end
        changes[id] = changes[id] + change
        if not finite_number(changes[id]) then complete = false; return end
      else
        only_productivity = false
      end
    end
  end)
  if not ok or not complete then return nil, "unavailable" end
  if #ids == 0 then return nil, "not-applicable" end

  local eligible = row.enabled and not row.researched
  if eligible then
    if not finite_integer(row.current_level) or row.current_level < 1
        or not finite_integer(row.max_level) or row.max_level < 1 then return nil, "unavailable" end
    eligible = row.current_level <= row.max_level and (row.cap == nil or row.current_level <= row.cap)
  end
  local recipes, result, any_benefit = native_read(force, "recipes"), {}, false
  for _, id in ipairs(ids) do
    local recipe = native_read(recipes, id)
    local current = native_read(recipe, "productivity_bonus")
    local maximum = native_read(native_read(recipe, "prototype"), "maximum_productivity")
    if native_read(recipe, "valid") ~= true or not finite_number(current) or current < 0
        or not finite_number(maximum) or maximum < 0 then return nil, "unavailable" end
    -- Preserve the published headroom boundary; it is not an estimate of
    -- machine throughput, module bonuses or future native queue behavior.
    local useful = eligible and changes[id] > 0 and current < maximum - PRODUCTIVITY_HEADROOM_EPSILON
    result[#result + 1] = {
      recipe_id = id, effect_change = changes[id], current_productivity_bonus = current,
      maximum_productivity = maximum, next_level_has_effective_benefit = useful
    }
    any_benefit = any_benefit or useful
  end
  return result, "available", eligible, any_benefit, only_productivity
end

local function family_matches(row, family)
  if family == "all" then return true end
  if family == "mir" then return row.family ~= "external" end
  return row.family == family
end

local function status_matches(row, status)
  if status == 1 then return true end
  if status == 2 then return row.ready == true end
  if status == 3 then return row.status ~= "missing" and row.ready ~= true and row.researched ~= true end
  return row.status == "queued" end

local function mode_matches(row, mode)
  if mode == 1 then return true end
  if mode == 2 then return row.finite == true end
  return row.finite == false
end

-- Raw affected recipe IDs remain searchable before/without translation.
-- Inspect only this eligible research's finite native array, lazily after a
-- text miss. Detail previews and localized-subject limits must not truncate
-- identity search; no recipe objects or live productivity values are needed.
local function recipe_id_matches(technology, search)
  local effects = native_read(native_read(technology, "prototype"), "effects")
  if effects == nil then return false end
  local ok, matched = pcall(function()
    for index = 1, #effects do
      local effect = effects[index]
      local kind = native_read(effect, "type")
      if kind == "unlock-recipe" or kind == "change-recipe-productivity" then
        local id = bounded_string(native_read(effect, "recipe"), MAX_TEXT)
        if id and matches(id, search) then return true end
      end
    end
    return false
  end)
  return ok and matched == true
end

local function row_matches(row, view, technology)
  if not family_matches(row, view.family) or not status_matches(row, view.status)
    or not mode_matches(row, view.mode) then return false end
  if view.visibility == 1 and view.hidden[row.id] then return false end
  if view.visibility == 2 and not view.hidden[row.id] then return false end
  if view.search == "" then return true end
  return matches(row.id .. " " .. row.family .. " " .. row.name .. " " .. (row.search_text or "")
    .. " " .. (row.recipe or "") .. " " .. (row.locale_key or ""), view.search)
    or recipe_id_matches(technology, view.search)
end

local function ordered(left, right, sort)
  if sort == "name-asc" or sort == "name-desc" then
    local left_name, right_name = ascii_casefold(left.name), ascii_casefold(right.name)
    if left_name ~= right_name then
      if sort == "name-asc" then return left_name < right_name end
      return left_name > right_name
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

-- Default `mir` and explicit authored descriptors build from declarations
-- only. Explicit external or all views may enumerate the native catalogue
-- exactly once.
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
    -- The Library lists research that exists for this force.  A declared
    -- technology can be unavailable on the current platform; that is not a
    -- synthetic "missing" row or an availability state.  Detail still
    -- reports technology_not_found for a direct selection.
    if technology ~= nil and not private_credit(context, id) and M.technology_visible(technology, id, context) then
      local row = row_for(force, by_id[id], id, technology, queue_count, queue_index, current, translations, context)
      row.hidden = normalized.hidden[id] == true
      if row_matches(row, normalized, technology) then selected[#selected + 1] = row end
    end
  end
  table.sort(selected, function(left, right) return ordered(left, right, normalized.sort) end)
  return selected
end

local function copy_effect_description(value, budget, depth)
  if budget.nodes == 0 or depth > 8 then return nil end
  budget.nodes = budget.nodes - 1
  if type(value) == "string" then
    if #value > budget.bytes then return nil end
    budget.bytes = budget.bytes - #value
    return value
  end
  if finite_number(value) then return value end
  if type(value) ~= "table" or #value > 21 then return nil end
  local out = {}
  for index = 1, #value do
    out[index] = copy_effect_description(value[index], budget, depth + 1)
    if out[index] == nil then return nil end
  end
  return out
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
      elseif kind == "nothing" then
        copied.effect_description = copy_effect_description(native_read(effect, "effect_description"),
          {nodes = 128, bytes = 65536}, 0)
        if copied.effect_description == nil then complete = false end
      else
        -- Most native modifier variants expose their signed numeric payload
        -- through `modifier`; retain only that scalar and the few bounded
        -- category identifiers needed to make a selected detail useful.  The
        -- reads are individually protected because TechnologyModifier
        -- variants intentionally do not share every property.
        copied.modifier = native_read(effect, "modifier")
        copied.ammo_category = bounded_string(native_read(effect, "ammo_category"), MAX_SEARCH)
        copied.turret_id = bounded_string(native_read(effect, "turret_id"), MAX_SEARCH)
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
  if private_credit(context, id) then return nil, "technology_not_found" end
  local declared, by_id = declarations(catalogue)
  local queue_count, queue_index, current = queue_facts(force)
  local technology = technology_for(force, id)
  if technology == nil or not M.technology_visible(technology, id, context) then return nil, "technology_not_found" end
  local row = row_for(force, by_id[id], id, technology, queue_count, queue_index, current, translations, context)
  local effects, effects_complete = copy_effects(technology)
  local cost, ingredients_complete = copy_cost(technology)
  row.effects, row.effects_complete = effects, effects_complete
  row.cost, row.ingredients_complete = cost, ingredients_complete
  row.recipe_targets, row.recipe_targets_complete = copy_recipe_targets(technology)
  if by_id[id] ~= nil then
    row.recipe_benefits, row.recipe_benefits_state, row.next_level_eligible,
      row.next_level_has_effective_benefit, row.recipe_benefits_only_effects =
      recipe_benefits(force, technology, row, context)
  end
  return row
end

return M

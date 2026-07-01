local D = {}
local lookup = require("prototypes.lib.prototype-lookup")

local rows = {}
local match_rows = {}
local recipe_to_streams = {}

local function startup_setting(name)
  local s = settings and settings.startup and settings.startup[name]
  if s then return s.value end
  return nil
end

function D.enabled()
  return startup_setting("mir-debug-generation-report") == true
end

function D.recipe_matches_enabled()
  return startup_setting("mir-debug-recipe-matches") == true
end

local function list_names(list)
  local out = {}
  for _, entry in ipairs(list or {}) do
    local name = entry.name or entry[1] or entry
    if name then table.insert(out, tostring(name)) end
  end
  return table.concat(out, ",")
end

local function effect_count(effects)
  local count = 0
  for _, _ in ipairs(effects or {}) do count = count + 1 end
  return count
end

local function icon_hint(spec)
  if spec.icons then return "custom-icons" end
  if spec.icon then return spec.icon end
  if spec.icon_techs then
    for _, name in ipairs(spec.icon_techs) do
      if (data.raw.technology or {})[name] then return "tech:" .. name end
      if lookup.item_prototype(name) then return "item:" .. name end
    end
    return "tech:" .. tostring(spec.icon_techs[1])
  end
  if spec.icon_tech then return "tech:" .. spec.icon_tech end
  if spec.icon_item then return "item:" .. spec.icon_item end
  if spec.items and spec.items[1] then return "item:" .. spec.items[1] end
  return "fallback"
end

local function append(kind, row)
  if not D.enabled() then return end
  row.kind = kind
  table.insert(rows, row)
end

function D.stream(row)
  append("stream", row)
end

function D.extension(row)
  append("extension", row)
end

function D.native_modifier_overlap(row)
  append("native_modifier_overlap", row)
end

function D.recipe_matches(key, buckets)
  if not D.recipe_matches_enabled() then return end
  for _, bucket in ipairs(buckets or {}) do
    table.insert(match_rows, {
      key = key,
      change = tostring(bucket.change or ""),
      recipes = bucket.recipes or {}
    })
  end
end

function D.record_recipe_match(key, recipe_name)
  if not key or not recipe_name then return end
  recipe_to_streams[recipe_name] = recipe_to_streams[recipe_name] or {}

  for _, existing in ipairs(recipe_to_streams[recipe_name]) do
    if existing == key then return end
  end

  table.insert(recipe_to_streams[recipe_name], key)
end

function D.stream_fields(key, spec, status, reason, ingredients, prerequisites, effects, lab_status)
  return {
    key = key,
    status = status,
    reason = reason,
    science = list_names(ingredients),
    prerequisites = list_names(prerequisites),
    effects = tostring(effect_count(effects)),
    lab_status = lab_status or "full",
    icon = icon_hint(spec or {})
  }
end

function D.extension_fields(key, status, reason, ingredients, prerequisites, effects, lab_status)
  return {
    key = key,
    status = status,
    reason = reason,
    science = list_names(ingredients),
    prerequisites = list_names(prerequisites),
    effects = tostring(effect_count(effects)),
    lab_status = lab_status or "full"
  }
end

local function row_sort(a, b)
  if a.kind ~= b.kind then return a.kind < b.kind end
  return tostring(a.key or "") < tostring(b.key or "")
end

function D.flush()
  if D.enabled() and #rows > 0 then
    table.sort(rows, row_sort)
    log("[more-infinite-research] Generation report start (" .. tostring(#rows) .. " rows)")
    for _, row in ipairs(rows) do
      log("[more-infinite-research] report kind=" .. tostring(row.kind)
        .. " key=" .. tostring(row.key or "")
        .. " status=" .. tostring(row.status or "")
        .. " reason=" .. tostring(row.reason or "")
        .. " science=" .. tostring(row.science or "")
        .. " prerequisites=" .. tostring(row.prerequisites or "")
        .. " effects=" .. tostring(row.effects or "")
        .. " lab_status=" .. tostring(row.lab_status or "")
        .. " icon=" .. tostring(row.icon or "")
        .. " effect=" .. tostring(row.effect or "")
        .. " target=" .. tostring(row.target or "")
        .. " owners=" .. tostring(row.owners or ""))
    end
    log("[more-infinite-research] Generation report end")
  end

  if D.recipe_matches_enabled() and #match_rows > 0 then
    table.sort(match_rows, function(a, b)
      if a.key ~= b.key then return tostring(a.key) < tostring(b.key) end
      return tostring(a.change) < tostring(b.change)
    end)
    log("[more-infinite-research] Recipe match report start (" .. tostring(#match_rows) .. " rows)")
    for _, row in ipairs(match_rows) do
      local recipes = {}
      for _, recipe in ipairs(row.recipes or {}) do table.insert(recipes, recipe) end
      table.sort(recipes)
      log("[more-infinite-research] matches key=" .. tostring(row.key or "")
        .. " change=" .. tostring(row.change or "")
        .. " recipes=" .. table.concat(recipes, ","))
    end
    log("[more-infinite-research] Recipe match report end")
  end

  if D.enabled() or D.recipe_matches_enabled() then
    local recipes = {}
    for recipe_name, streams in pairs(recipe_to_streams) do
      if #streams > 1 then table.insert(recipes, recipe_name) end
    end
    table.sort(recipes)
    for _, recipe_name in ipairs(recipes) do
      local streams = recipe_to_streams[recipe_name]
      table.sort(streams)
      log("[more-infinite-research] duplicate recipe match recipe="
        .. recipe_name .. " streams=" .. table.concat(streams, ","))
    end
  end
end

return D

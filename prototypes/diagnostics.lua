local D = {}

local rows = {}

local function startup_setting(name)
  local s = settings and settings.startup and settings.startup[name]
  if s then return s.value end
  return nil
end

function D.enabled()
  return startup_setting("mir-debug-generation-report") == true
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
  if not D.enabled() or #rows == 0 then return end
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
      .. " icon=" .. tostring(row.icon or ""))
  end
  log("[more-infinite-research] Generation report end")
end

return D

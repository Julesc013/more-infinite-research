local D = {}
local icons = require("prototypes.mir.emit.icon_builder")
local schema = require("prototypes.mir.core.schema")
local effective_settings = require("prototypes.mir.settings.effective")
local decision_record = require("prototypes.mir.domain.decisions.decision_record")

local rows = {}
local audit_rows = {}
local match_rows = {}
local recipe_to_streams = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

function D.enabled()
  return startup_setting("mir-debug-generation-report") == true
    or startup_setting("mir-automatic-compiler-mode") == "report"
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
  return icons.icon_source_for_stream(spec or {})
end

local function append(kind, row)
  if not D.enabled() then return end
  row.kind = kind
  table.insert(rows, row)

  local audit_row = {schema = 1, kind = kind}
  for field, value in pairs(row) do
    audit_row[field] = value
  end
  table.insert(audit_rows, audit_row)
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

function D.recipe_owner(row)
  append("recipe_owner", row)
end

function D.compatibility_role(row)
  append("compatibility_role", row)
end

function D.compatibility_plan(row)
  append("compatibility_plan", row)
end

function D.recipe_cap(row)
  append("recipe_cap", row)
end

function D.fact_registry(row)
  append("fact_registry", row)
end

function D.decision(row)
  schema.decision(row)
  local projected = {}
  for field, value in pairs(row) do projected[field] = value end
  projected.confidence = decision_record.format_typed_confidence(row.confidence)
  append("decision", projected)
end

function D.rule_mutation(row)
  append("rule_mutation", row)
end

function D.loop_risk(row)
  append("loop_risk", row)
end

function D.lab_matrix(row)
  append("lab_matrix", row)
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

function D.stream_fields(key, spec, status, reason, ingredients, prerequisites, effects, lab_status, extra)
  local row = {
    key = key,
    status = status,
    reason = reason,
    science = list_names(ingredients),
    prerequisites = list_names(prerequisites),
    effects = tostring(effect_count(effects)),
    lab_status = lab_status or "full",
    icon = icon_hint(spec or {})
  }
  for field, value in pairs(extra or {}) do
    row[field] = value
  end
  return row
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
  if tostring(a.key or "") ~= tostring(b.key or "") then
    return tostring(a.key or "") < tostring(b.key or "")
  end
  if tostring(a.recipe or "") ~= tostring(b.recipe or "") then
    return tostring(a.recipe or "") < tostring(b.recipe or "")
  end
  return tostring(a.key or "") < tostring(b.key or "")
end

local function audit_value(value)
  local text = tostring(value or "")
  text = string.gsub(text, "\\", "\\\\")
  text = string.gsub(text, "\r", "\\r")
  text = string.gsub(text, "\n", "\\n")
  text = string.gsub(text, "\t", "\\t")
  if string.find(text, "%s") then
    text = '"' .. string.gsub(text, '"', '\\"') .. '"'
  end
  return text
end

local function audit_fields(row)
  local fields = {}
  for field, _ in pairs(row or {}) do
    if field ~= "kind" and field ~= "schema" then
      table.insert(fields, field)
    end
  end
  table.sort(fields)
  return fields
end

function D.flush()
  if D.enabled() and #rows > 0 then
    table.sort(rows, row_sort)
    log("[more-infinite-research] Generation report start (" .. tostring(#rows) .. " rows)")
    for _, row in ipairs(rows) do
      log("[more-infinite-research] report kind=" .. tostring(row.kind)
        .. " key=" .. tostring(row.key or "")
        .. " schema=" .. tostring(row.schema or "")
        .. " status=" .. tostring(row.status or "")
        .. " reason=" .. tostring(row.reason or "")
        .. " science=" .. tostring(row.science or "")
        .. " prerequisites=" .. tostring(row.prerequisites or "")
        .. " effects=" .. tostring(row.effects or "")
        .. " lab_status=" .. tostring(row.lab_status or "")
        .. " icon=" .. tostring(row.icon or "")
        .. " effect=" .. tostring(row.effect or "")
        .. " target=" .. tostring(row.target or "")
        .. " owners=" .. tostring(row.owners or "")
        .. " recipe=" .. tostring(row.recipe or "")
        .. " owner_kinds=" .. tostring(row.owner_kinds or "")
        .. " owner_actions=" .. tostring(row.owner_actions or "")
        .. " recipes=" .. tostring(row.recipes or "")
        .. " mod=" .. tostring(row.mod or "")
        .. " role=" .. tostring(row.role or "")
        .. " action=" .. tostring(row.action or "")
        .. " signal=" .. tostring(row.signal or "")
        .. " warning_class=" .. tostring(row.warning_class or "")
        .. " cap_state=" .. tostring(row.cap_state or "")
        .. " maximum_productivity=" .. tostring(row.maximum_productivity or "")
        .. " per_level=" .. tostring(row.per_level or "")
        .. " levels_to_cap=" .. tostring(row.levels_to_cap or "")
        .. " useful_level_estimate=" .. tostring(row.useful_level_estimate or "")
        .. " total=" .. tostring(row.total or "")
        .. " warnings=" .. tostring(row.warnings or "")
        .. " subject_type=" .. tostring(row.subject_type or "")
        .. " subject=" .. tostring(row.subject or "")
        .. " capability=" .. tostring(row.capability or "")
        .. " family=" .. tostring(row.family or "")
        .. " subfamily=" .. tostring(row.subfamily or "")
        .. " confidence=" .. tostring(row.confidence or "")
        .. " source=" .. tostring(row.source or "")
        .. " policy=" .. tostring(row.policy or "")
        .. " decision=" .. tostring(row.decision or "")
        .. " emitted=" .. tostring(row.emitted or "")
        .. " blockers=" .. tostring(row.blockers or "")
        .. " risks=" .. tostring(row.risks or "")
        .. " stable_stream_id=" .. tostring(row.stable_stream_id or "")
        .. " labs=" .. tostring(row.labs or "")
        .. " field=" .. tostring(row.field or "")
        .. " observed_value=" .. tostring(row.observed_value or "")
        .. " expected_baseline=" .. tostring(row.expected_baseline or "")
        .. " likely_mutator_mod=" .. tostring(row.likely_mutator_mod or "")
        .. " technologies=" .. tostring(row.technologies or "")
        .. " machines=" .. tostring(row.machines or "")
        .. " rule_mutations=" .. tostring(row.rule_mutations or "")
        .. " loop_risks=" .. tostring(row.loop_risks or "")
        .. " generated=" .. tostring(row.generated or "")
        .. " rejected=" .. tostring(row.rejected or "")
        .. " unknown=" .. tostring(row.unknown or "")
        .. " missing=" .. tostring(row.missing or "")
        .. " module_slots=" .. tostring(row.module_slots or "")
        .. " allowed_effects=" .. tostring(row.allowed_effects or "")
        .. " shared_inputs_outputs=" .. tostring(row.shared_inputs_outputs or "")
        .. " evidence=" .. tostring(row.evidence or ""))
    end
    log("[more-infinite-research] Generation report end")
  end

  if D.enabled() and #audit_rows > 0 then
    table.sort(audit_rows, row_sort)
    log("[more-infinite-research] Audit report start (" .. tostring(#audit_rows) .. " rows)")
    for _, row in ipairs(audit_rows) do
      local parts = {
        "schema=" .. audit_value(row.schema),
        "kind=" .. audit_value(row.kind)
      }
      for _, field in ipairs(audit_fields(row)) do
        table.insert(parts, field .. "=" .. audit_value(row[field]))
      end
      log("[more-infinite-research] audit " .. table.concat(parts, " "))
    end
    log("[more-infinite-research] Audit report end")
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

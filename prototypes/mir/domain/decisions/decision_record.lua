local schema = require("prototypes.mir.core.schema")

local M = {}

local function required(record, field)
  if record[field] == nil then
    error("DecisionRecord missing required field: " .. field, 3)
  end
end

function M.format_confidence(parts)
  local out = {}
  for _, key in ipairs({"family", "unlock", "science", "lab", "loop_safety", "owner", "cap", "total"}) do
    local value = parts and parts[key]
    if value ~= nil then table.insert(out, key .. "=" .. tostring(value)) end
  end
  return table.concat(out, ",")
end

function M.generated_technology(record)
  required(record, "technology_name")
  required(record, "lab_compatible")
  required(record, "effect_count")
  required(record, "science")
  required(record, "labs")

  local lab_compatible = record.lab_compatible == true
  return schema.decision({
    key = record.technology_name,
    subject_type = "technology",
    subject = record.technology_name,
    family = record.family or "explicit_stream",
    confidence = M.format_confidence({
      family = 1.0,
      science = 1.0,
      lab = lab_compatible and 1.0 or 0.0,
      owner = 1.0,
      loop_safety = 1.0,
      total = lab_compatible and 1.0 or 0.5
    }),
    source = record.source or "compiler:generated-technology",
    policy = record.policy or "explicit_stream",
    decision = lab_compatible and "generate_stream" or "diagnose_only",
    emitted = lab_compatible and "true" or "false",
    reason = lab_compatible and "generated_mir_technology_indexed" or "generated_technology_without_lab",
    effects = tostring(record.effect_count or 0),
    science = record.science,
    labs = record.labs,
    stable_stream_id = record.stable_stream_id or record.technology_name
  })
end

return M

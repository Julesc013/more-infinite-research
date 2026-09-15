local M = {}

local function required(record, field)
  if record[field] == nil then
    error("StreamSpec missing required field: " .. field, 3)
  end
end

function M.from_stream_record(record)
  required(record, "stream_key")
  required(record, "technology_name")
  required(record, "effects")
  required(record, "science")
  required(record, "prerequisites")
  required(record, "count_formula")
  required(record, "research_time")
  required(record, "max_level")

  return {
    schema = 1,
    manifest_id = record.manifest_id or record.stream_key,
    stream_key = record.stream_key,
    technology_name = record.technology_name,
    localised_name = record.localised_name,
    localised_description = record.localised_description,
    icons = record.icons,
    effects = record.effects,
    science = record.science,
    prerequisites = record.prerequisites,
    count_formula = record.count_formula,
    research_time = record.research_time,
    upgrade = record.upgrade ~= false,
    max_level = record.max_level,
    order = record.order,
    level = record.level or 1,
    migration_policy = record.migration_policy or "stable"
  }
end

return M

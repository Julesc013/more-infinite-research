local M = {}

M.sections = {
  main = "a-0",
  compatibility = "a-1",
  prototype_limits = "a-2",
  advanced = "a-7",
  diagnostics = "a-8",
  generated_technologies = "b"
}

function M.global(section, index)
  local prefix = M.sections[section]
  if not prefix then error("Unknown MIR settings section: " .. tostring(section)) end
  return string.format("%s-%03d", prefix, index)
end

function M.technology(bucket, name_slug, kind, key)
  return string.format("%s-%s-%s-%s-%s",
    M.sections.generated_technologies,
    bucket,
    name_slug,
    kind,
    key)
end

return M

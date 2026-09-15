local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local fingerprint = require("prototypes.mir.core.fingerprint")
local graph_snapshot = require("prototypes.mir.graph.snapshot")

local M = {}

local function sorted(values)
  local out = {}
  for _, value in ipairs(values or {}) do table.insert(out, value) end
  table.sort(out)
  return out
end

local function entry_material(entry)
  return {
    schema = entry.schema,
    sequence = entry.sequence,
    source = entry.source,
    old_technology = entry.old_technology,
    replacement_technologies = entry.replacement_technologies,
    old_graph_node_fingerprint = entry.old_graph_node_fingerprint,
    rewired_dependents = entry.rewired_dependents,
    metadata = entry.metadata
  }
end

local function is_sorted(values)
  for index = 2, #(values or {}) do
    if tostring(values[index - 1]) > tostring(values[index]) then return false end
  end
  return true
end

local function validate_entry(entry, sequence)
  if type(entry) ~= "table" or entry.schema ~= 1 or entry.sequence ~= sequence
    or type(entry.source) ~= "string" or entry.source == ""
    or type(entry.old_technology) ~= "string" or entry.old_technology == ""
    or type(entry.replacement_technologies) ~= "table" or #entry.replacement_technologies == 0
    or not is_sorted(entry.replacement_technologies)
    or type(entry.old_graph_node_fingerprint) ~= "string"
    or type(entry.rewired_dependents) ~= "table"
    or type(entry.metadata) ~= "table"
    or type(entry.entry_fingerprint) ~= "string" then
    error("MIR technology replacement journal entry is malformed at sequence " .. tostring(sequence) .. ".", 3)
  end
  local previous
  for _, row in ipairs(entry.rewired_dependents) do
    if type(row) ~= "table" or type(row.technology_name) ~= "string"
      or type(row.before_prerequisites) ~= "table" or not is_sorted(row.before_prerequisites)
      or type(row.after_prerequisites) ~= "table" or not is_sorted(row.after_prerequisites)
      or (previous and previous >= row.technology_name) then
      error("MIR technology replacement journal dependent row is malformed for "
        .. tostring(entry.old_technology) .. ".", 3)
    end
    previous = row.technology_name
  end
  local expected = fingerprint.of(entry_material(entry))
  if entry.entry_fingerprint ~= expected then
    error("MIR technology replacement journal entry fingerprint mismatch for "
      .. tostring(entry.old_technology) .. ".", 3)
  end
end

function M.new_journal()
  return {schema = 1, entries = {}}
end

function M.validate_journal(journal)
  if type(journal) ~= "table" or journal.schema ~= 1 or type(journal.entries) ~= "table" then
    error("MIR technology replacement journal is malformed.", 2)
  end
  local entry_fingerprints, seen = {}, {}
  for sequence, entry in ipairs(journal.entries) do
    validate_entry(entry, sequence)
    if seen[entry.old_technology] then
      error("MIR technology replacement journal replaced one technology more than once: "
        .. entry.old_technology .. ".", 2)
    end
    seen[entry.old_technology] = true
    table.insert(entry_fingerprints, entry.entry_fingerprint)
  end
  local summary = {
    schema = 1,
    entry_count = #journal.entries,
    entry_fingerprints = entry_fingerprints
  }
  summary.journal_fingerprint = fingerprint.of(summary)
  return summary
end

local function normalized_replacements(replacements)
  if type(replacements) == "string" then replacements = { replacements } end
  local out, seen = {}, {}
  for _, name in ipairs(replacements or {}) do
    if name and not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  return out
end

local function replacement_prerequisites(prerequisites, old_name, replacements)
  local out, seen = {}, {}
  for _, name in ipairs(prerequisites or {}) do
    if name == old_name then
      for _, replacement in ipairs(replacements) do
        if not seen[replacement] then
          seen[replacement] = true
          table.insert(out, replacement)
        end
      end
    elseif not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  return out
end

local function proposed_prerequisites(technologies, old_name, replacements)
  local proposed = {}
  for name, technology in pairs(technologies) do
    if name ~= old_name then
      proposed[name] = replacement_prerequisites(technology.prerequisites, old_name, replacements)
    end
  end
  return proposed
end

local function graph_cycle(proposed)
  local complete, visiting = {}, {}
  local function visit(name, path)
    if complete[name] then return nil end
    if visiting[name] then
      local cycle = {}
      for _, value in ipairs(path) do table.insert(cycle, value) end
      table.insert(cycle, name)
      return table.concat(cycle, " -> ")
    end
    if not proposed[name] then return nil end

    visiting[name] = true
    table.insert(path, name)
    for _, prerequisite in ipairs(proposed[name]) do
      local cycle = visit(prerequisite, path)
      if cycle then return cycle end
    end
    table.remove(path)
    visiting[name] = nil
    complete[name] = true
    return nil
  end

  local names = {}
  for name, _ in pairs(proposed) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local cycle = visit(name, {})
    if cycle then return cycle end
  end
  return nil
end

function M.replace_technology(old_name, replacements, options)
  options = options or {}
  local technologies = data_raw.prototypes("technology")
  if not old_name or not technologies[old_name] then return false, "old_technology_missing" end

  local replacement_names = normalized_replacements(replacements)
  if #replacement_names == 0 then return false, "replacement_missing" end
  for _, name in ipairs(replacement_names) do
    if name == old_name then return false, "replacement_is_old_technology" end
    if not technologies[name] then return false, "replacement_technology_missing:" .. tostring(name) end
  end

  local proposed = proposed_prerequisites(technologies, old_name, replacement_names)
  local cycle = graph_cycle(proposed)
  if cycle then return false, "replacement_cycle:" .. cycle end

  local old_snapshot = graph_snapshot.new({[old_name] = technologies[old_name]})
  local rewired_dependents = {}
  local dependent_names = {}
  for name, technology in pairs(technologies) do
    if name ~= old_name then
      for _, prerequisite in ipairs(technology.prerequisites or {}) do
        if prerequisite == old_name then
          table.insert(dependent_names, name)
          break
        end
      end
    end
  end
  table.sort(dependent_names)
  for _, name in ipairs(dependent_names) do
    table.insert(rewired_dependents, {
      technology_name = name,
      before_prerequisites = sorted(technologies[name].prerequisites),
      after_prerequisites = sorted(proposed[name])
    })
  end

  local journal = options.journal
  if journal ~= nil and (type(journal) ~= "table" or journal.schema ~= 1
    or type(journal.entries) ~= "table") then
    error("MIR technology replacement requires a schema-1 replacement journal.", 2)
  end
  local entry = {
    schema = 1,
    sequence = journal and (#journal.entries + 1) or 1,
    source = options.source or "unspecified",
    old_technology = old_name,
    replacement_technologies = sorted(replacement_names),
    old_graph_node_fingerprint = fingerprint.of(old_snapshot.nodes[1]),
    rewired_dependents = rewired_dependents,
    metadata = options.metadata or {}
  }
  entry.entry_fingerprint = fingerprint.of(entry_material(entry))

  for name, prerequisites in pairs(proposed) do
    local technology = technologies[name]
    if technology then
      local referenced_old = false
      for _, prerequisite in ipairs(technology.prerequisites or {}) do
        if prerequisite == old_name then referenced_old = true break end
      end
      if referenced_old then
        technology.prerequisites = #prerequisites > 0 and prerequisites or nil
      end
    end
  end
  technologies[old_name] = nil
  if journal then table.insert(journal.entries, entry) end
  return true, entry
end

function M.remove_technology_if_unreferenced(name)
  local technologies = data_raw.prototypes("technology")
  if not name or not technologies[name] then return false, "technology_missing" end
  for dependent_name, technology in pairs(technologies) do
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if prerequisite == name then
        return false, "technology_is_referenced_by:" .. dependent_name
      end
    end
  end
  technologies[name] = nil
  return true
end

return M

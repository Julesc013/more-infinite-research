local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

M.schema = 1

local REQUIRED_TABLES = {
  "source_kinds", "discovery", "positive_capabilities", "normalization",
  "default_policy", "setting_descriptors", "localization_descriptors",
  "validation_hooks", "emission_adapter", "runtime_handler", "migration",
  "diagnostic_codes", "fixtures", "family_rule"
}

local FORBIDDEN_KEYS = {data = true, data_raw = true, mods = true}

local function assert_data_only(value, path)
  if type(value) == "function" then error("CompilerProvider must be data-only: " .. path, 3) end
  if type(value) ~= "table" then return end
  for key, child in pairs(value) do
    if FORBIDDEN_KEYS[key] then error("CompilerProvider contains forbidden field: " .. path .. "." .. tostring(key), 3) end
    assert_data_only(child, path .. "." .. tostring(key))
  end
end

local function nonempty_list(value)
  return type(value) == "table" and #value > 0
end

function M.validate(provider)
  if type(provider) ~= "table" then error("CompilerProvider must be a table", 2) end
  assert_data_only(provider, "provider")
  if provider.schema_version ~= M.schema then error("CompilerProvider schema must be 1", 2) end
  if type(provider.id) ~= "string" or provider.id == "" then error("CompilerProvider id is required", 2) end
  if type(provider.family) ~= "string" or provider.family == "" then
    error("CompilerProvider family is required: " .. provider.id, 2)
  end
  if provider.semantic_signature ~= nil and type(provider.semantic_signature) ~= "table" then
    error("CompilerProvider semantic_signature must be a descriptor: " .. provider.id, 2)
  end
  for _, field in ipairs(REQUIRED_TABLES) do
    if type(provider[field]) ~= "table" then
      error("CompilerProvider field is required: " .. provider.id .. ":" .. field, 2)
    end
  end
  if not nonempty_list(provider.source_kinds) then error("CompilerProvider source_kinds must not be empty: " .. provider.id, 2) end
  if not nonempty_list(provider.positive_capabilities) then error("CompilerProvider positive_capabilities must not be empty: " .. provider.id, 2) end
  if not nonempty_list(provider.validation_hooks) then error("CompilerProvider validation_hooks must not be empty: " .. provider.id, 2) end
  if not nonempty_list(provider.diagnostic_codes) then error("CompilerProvider diagnostic_codes must not be empty: " .. provider.id, 2) end
  if not nonempty_list(provider.fixtures) then error("CompilerProvider fixtures must not be empty: " .. provider.id, 2) end
  if provider.emission_adapter.mutates_prototypes ~= false then
    error("CompilerProvider emission adapters must be planning-only: " .. provider.id, 2)
  end
  if provider.runtime_handler.required ~= false then
    error("CompilerProvider runtime handlers require a separately registered runtime contract: " .. provider.id, 2)
  end
  if provider.family_rule.provider_id ~= provider.id then
    error("CompilerProvider family_rule provider_id mismatch: " .. provider.id, 2)
  end
  if provider.family_rule.family ~= provider.family then
    error("CompilerProvider family_rule family mismatch: " .. provider.id, 2)
  end
  local cardinality = provider.default_policy.cardinality
  if type(cardinality) ~= "table" then
    error("CompilerProvider cardinality policy is required: " .. provider.id, 2)
  end
  for _, field in ipairs({
    "maximum_candidates", "maximum_attachments", "maximum_review_required",
    "maximum_new_attachments", "maximum_growth_percent", "maximum_progression_span",
    "maximum_semantic_clusters", "maximum_unreviewed"
  }) do
    local value = cardinality[field]
    if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
      error("CompilerProvider cardinality field is invalid: " .. provider.id .. ":" .. field, 2)
    end
  end
  if type(provider.family_rule.cardinality) ~= "table" then
    error("CompilerProvider FamilyRule cardinality policy is missing: " .. provider.id, 2)
  end
  for _, field in ipairs({
    "maximum_candidates", "maximum_attachments", "maximum_review_required",
    "maximum_new_attachments", "maximum_growth_percent", "maximum_progression_span",
    "maximum_semantic_clusters", "maximum_unreviewed"
  }) do
    if provider.family_rule.cardinality[field] ~= cardinality[field] then
      error("CompilerProvider and FamilyRule cardinality policies differ: " .. provider.id .. ":" .. field, 2)
    end
  end
  return deepcopy(provider)
end

function M.validate_all(source)
  if type(source) ~= "table" or source.schema ~= M.schema then
    error("CompilerProvider registry schema must be 1", 2)
  end
  local providers, ids = {}, {}
  for _, raw in ipairs(source.providers or {}) do
    local provider = M.validate(raw)
    if ids[provider.id] then error("Duplicate CompilerProvider id: " .. provider.id, 2) end
    ids[provider.id] = true
    table.insert(providers, provider)
  end
  table.sort(providers, function(a, b) return a.id < b.id end)
  return {schema = M.schema, providers = providers}
end

return M

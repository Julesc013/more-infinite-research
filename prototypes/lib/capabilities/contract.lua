local schema = require("prototypes.lib.mir.schema")

local Contract = {}

-- CapabilityResolver schema: id, schema_version, family, subfamily, source,
-- policy, discover, classify, propose, validate, emit, and diagnose.

local REQUIRED_FIELDS = {
  "id",
  "schema_version",
  "family",
  "subfamily",
  "source",
  "policy",
  "discover",
  "classify",
  "propose",
  "validate",
  "emit",
  "diagnose"
}

local FUNCTION_FIELDS = {
  discover = true,
  classify = true,
  propose = true,
  validate = true,
  emit = true,
  diagnose = true
}

local function fail(message)
  error("Invalid MIR capability resolver: " .. message, 3)
end

function Contract.validate(resolver)
  if type(resolver) ~= "table" then fail("resolver must be a table") end

  for _, field in ipairs(REQUIRED_FIELDS) do
    if resolver[field] == nil then
      fail(tostring(resolver.id or "<missing-id>") .. " missing " .. field)
    end
  end

  if resolver.schema_version ~= schema.capability_resolver then
    fail(tostring(resolver.id) .. " has unsupported schema_version " .. tostring(resolver.schema_version))
  end

  for field, _ in pairs(FUNCTION_FIELDS) do
    if type(resolver[field]) ~= "function" then
      fail(tostring(resolver.id) .. " field " .. field .. " must be a function")
    end
  end

  return resolver
end

function Contract.validate_all(resolvers)
  for _, resolver in ipairs(resolvers or {}) do
    Contract.validate(resolver)
  end
  return resolvers
end

return Contract

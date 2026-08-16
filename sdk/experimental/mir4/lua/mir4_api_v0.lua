-- Generated experimental package-excluded binding.
local M = {}
local kinds = {MIR4HostManifestV0=true,MIR4ExtensionEnvelopeV0=true,MIR4QuerySnapshotV0=true,MIR4ProfileV0=true,MIR4DiagnosticV0=true,MIR4SupportSnapshotV0=true}
local transports = {['build-time-static']=true,['stage-local-read-only']=true,['prototype-stage-read-only']=true,['mod-data-read-only']=true}

local function valid_capability(value)
  if type(value) ~= 'string' or not string.match(value, '^[a-z][a-z0-9%.%-]*$') then return false end
  return not string.match(value, '[%.%-][%.%-]') and not string.match(value, '[%.%-]$')
end

local function valid_namespace(value)
  if type(value) ~= 'string' or not string.find(value, '.', 1, true) then return false end
  local count = 0
  for part in string.gmatch(value, '[^%.]+') do
    count = count + 1
    if not string.match(part, '^[a-z][a-z0-9%-]*$') then return false end
  end
  return count >= 2 and not string.match(value, '%.%.') and not string.match(value, '%.$')
end

function M.validate(v)
  if type(v) ~= 'table' or not kinds[v.kind] then return nil, 'mir4-api-kind' end
  if v.schema ~= 0 or type(v.target) ~= 'table' or type(v.versions) ~= 'table' or type(v.payload) ~= 'table' then return nil, 'mir4-api-schema' end
  if type(v.target.id) ~= 'string' or not string.match(v.target.id, '^f%d%d%d$') or type(v.target.factorio_line) ~= 'string' or not string.match(v.target.factorio_line, '^%d+%.%d+$') or not transports[v.target.transport] then return nil, 'mir4-api-schema' end
  if type(v.versions.source) ~= 'string' or #v.versions.source < 1 or #v.versions.source > 64 or type(v.versions.distribution) ~= 'string' or #v.versions.distribution < 1 or #v.versions.distribution > 64 then return nil, 'mir4-api-schema' end
  if type(v.capabilities) ~= 'table' then return nil, 'mir4-api-schema' end
  if #v.capabilities > 128 then return nil, 'mir4-api-cardinality' end
  local seen = {}
  for _, capability in ipairs(v.capabilities) do
    if not valid_capability(capability) or seen[capability] then return nil, 'mir4-api-schema' end
    seen[capability] = true
  end
  if v.canonicalization ~= 'mir-canonical-json-v0' then return nil, 'mir4-api-canonicalization' end
  if type(v.extensions) ~= 'table' then return nil, 'mir4-api-schema' end
  local extension_count = 0
  for namespace in pairs(v.extensions) do
    extension_count = extension_count + 1
    if not valid_namespace(namespace) then return nil, 'mir4-api-namespace' end
  end
  if extension_count > 32 then return nil, 'mir4-api-cardinality' end
  if type(v.digest) ~= 'string' or not string.match(v.digest, '^sha256:[0-9a-f]+$') or #v.digest ~= 71 then return nil, 'mir4-api-digest' end
  return true
end

function M.build(v)
  local ok, error_code = M.validate(v)
  if not ok then return nil, error_code end
  return v
end
return M
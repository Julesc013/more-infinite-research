-- Generated experimental package-excluded binding.
local M={}
local kinds={MIR4HostManifestV0=true,MIR4ExtensionEnvelopeV0=true,MIR4QuerySnapshotV0=true,MIR4ProfileV0=true,MIR4DiagnosticV0=true,MIR4SupportSnapshotV0=true}
function M.validate(v) if type(v)~='table' or not kinds[v.kind] then return nil,'mir4-api-kind' end if v.schema~=0 then return nil,'mir4-api-schema' end if type(v.capabilities)~='table' or #v.capabilities>128 then return nil,'mir4-api-cardinality' end if v.canonicalization~='mir-canonical-json-v0' then return nil,'mir4-api-canonicalization' end return true end
function M.build(v) local ok,e=M.validate(v);if not ok then return nil,e end;return v end
return M

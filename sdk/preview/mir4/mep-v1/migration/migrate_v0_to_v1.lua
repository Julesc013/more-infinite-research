-- V0 to V1 migration is intentionally structural and data-only.
return function(v0)
  assert(v0.kind == 'MIR4ExtensionEnvelopeV0' and v0.schema == 0, 'mir4-mep-migrate-source')
  return {kind='MIR4ExtensionEnvelopeV1',schema=1,extension_id=v0.extension_id,extension_version='0.0.0-migrated',namespace=v0.extension_id,targets=v0.targets,fragments=v0.fragments,canonicalization='mir-canonical-json/1',digest='RECOMPUTE-WITH-MIR-CANONICAL-JSON-1'}
end
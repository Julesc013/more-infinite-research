local S = {}

S.fact_registry = 1
S.capability_resolver = 1
S.capability_policy = 1
S.decision_record = 1
S.generated_stream_manifest = 1
S.compatibility_claims = 1

function S.with_schema(kind, row)
  row = row or {}
  row.schema = row.schema or S[kind] or 1
  return row
end

function S.decision(row)
  return S.with_schema("decision_record", row)
end

return S

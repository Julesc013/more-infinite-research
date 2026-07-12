local S = {}

S.fact_registry = 2
S.recipe_fact = 2
S.relationship_index = 1
S.family_rule = 1
S.family_decision = 1
S.compatibility_pack = 1
S.capability_resolver = 2
S.capability_policy = 1
S.decision_record = 2
S.generated_stream_manifest = 1
S.compatibility_claims = 1
S.generation_plan = 2

function S.with_schema(kind, row)
  row = row or {}
  row.schema = row.schema or S[kind] or 1
  return row
end

function S.decision(row)
  return S.with_schema("decision_record", row)
end

return S

local S = {}

S.fact_registry = 2
S.recipe_fact = 2
S.relationship_index = 1
S.family_rule = 2
S.family_decision = 2
S.compiler_provider = 1
S.compatibility_pack = 2
S.capability_resolver = 2
S.capability_policy = 1
S.decision_record = 2
S.generated_stream_manifest = 1
S.compatibility_claims = 1
S.generation_plan = 3
S.technology_candidate = 1
S.technology_qualification = 1
S.technology_approval = 1
S.technology_promotion = 1
S.technology_migration = 1
S.technology_catalog = 2
S.technology_quality_assessment = 1
S.technology_promotion_admission = 1
S.target_profile = 2

function S.with_schema(kind, row)
  row = row or {}
  row.schema = row.schema or S[kind] or 1
  return row
end

function S.decision(row)
  return S.with_schema("decision_record", row)
end

return S

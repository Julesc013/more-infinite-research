local tech = data.raw.technology and data.raw.technology["recipe-prod-research_science_pack_productivity-1"]
local found = false

for _, effect in ipairs((tech and tech.effects) or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "mir-fixture-science-pack" then
    found = true
    break
  end
end

if tech then
  if not found then
    error("MIR validation failed: generated science-pack productivity omitted mir-fixture-science-pack.")
  end
else
  -- The custom-lab scenario deliberately has no lab that accepts its complete
  -- science set. Absence is admitted only by the exact planner decision; any
  -- other absence remains a fixture failure.
  local plan_prototype = (data.raw["mod-data"] or {})["more-infinite-research-generation-plan-internal"]
  local science_row
  for _, row in ipairs((plan_prototype and plan_prototype.data and plan_prototype.data.rows) or {}) do
    if row.stream_key == "research_science_pack_productivity" then
      if science_row then
        error("MIR validation failed: duplicate science-pack productivity GenerationPlan row.")
      end
      science_row = row
    end
  end

  local function failed_gate(name)
    local gate = science_row and science_row.gates and science_row.gates[name]
    return gate and gate.passed == false and gate.status == "failed"
      and gate.reason == "no_lab_compatible_science"
  end

  local required = science_row and science_row.diagnostics and science_row.diagnostics.science_phase_required_packs
  local custom_pack_required = type(required) == "string"
    and ("," .. required .. ","):find(",mir-custom-only-science-pack,", 1, true) ~= nil

  if not science_row or science_row.action ~= "skip"
    or science_row.reason ~= "no_lab_compatible_science"
    or not science_row.diagnostics or science_row.diagnostics.lab_status ~= "required-unreachable"
    or not failed_gate("science_compatible") or not failed_gate("lab_compatible")
    or not custom_pack_required then
    error("MIR validation failed: science-pack productivity is absent without the required-unreachable custom-lab admission.")
  end
end

local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_candidate = require("prototypes.mir.domain.technology.technology_candidate")
local technology_qualification = require("prototypes.mir.domain.technology.technology_qualification")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local selection_policy = require("prototypes.mir.planner.technology_selection_policy")
local model = require("prototypes.mir.planner.technology_catalog.model")
local validate = require("prototypes.mir.planner.technology_catalog.validate")

local M = {}

function M.from_preselection_rows(rows, context_material, options)
  options = options or {}
  local candidates, qualifications, alternative_qualifications, by_id = {}, {}, {}, {}
  for _, row in ipairs(rows or {}) do
    if options.phase == "final" then row = model.final_qualification_row(row) end
    local primary_design = row.technology_design or technology_design.from_generation_row(row)
    if options.trusted_designs then technology_design.assert_trusted(primary_design)
    else technology_design.verify_untrusted(primary_design) end
    local diagnostic_design = technology_design.as_diagnostic_alternative(
      primary_design,
      row.reason,
      {
        validated = options.trusted_designs == true,
        source_trusted_verified = options.trusted_designs == true
      }
    )
    local diagnostic_row = model.safe_diagnostic_row(diagnostic_design)
    local designs = {}
    if row.action == "emit" or row.action == "adopt" then
      table.insert(designs, {design = primary_design, row = row, action = row.action, disposition = "materialize"})
    else
      table.insert(designs, {design = primary_design, row = row, action = "reject", disposition = "rejected"})
    end
    table.insert(designs, {design = diagnostic_design, row = diagnostic_row, action = "diagnose", disposition = "safe-diagnostic"})

    local candidate = technology_candidate.from_design(primary_design, row, {
      validated = true,
      trusted_design_verified = true
    })
    if by_id[candidate.candidate_id] then
      error("TechnologyCandidate identity has contradictory preselection rows: " .. candidate.candidate_id, 2)
    end
    candidate.alternatives = {}
    candidate.selection_key = model.selection_key(row)
    by_id[candidate.candidate_id] = candidate
    table.insert(candidates, candidate)

    for _, entry in ipairs(designs) do
      local qualification = technology_qualification.from_design(
        entry.design,
        entry.row,
        {status = "UNMEASURED"},
        {
          validated = true,
          trusted_design_verified = true,
          trusted_gates_verified = options.children_admitted == true,
          trusted_cached_verified = options.children_admitted == true
        }
      )
      local alternative = model.alternative_record(entry.design, qualification, entry.action, entry.disposition)
      table.insert(candidate.alternatives, alternative)
      table.insert(qualifications, qualification)
      table.insert(alternative_qualifications, {
        candidate_id = candidate.candidate_id,
        alternative_id = alternative.alternative_id,
        design_fingerprint = alternative.design_fingerprint,
        qualification_fingerprint = alternative.qualification_fingerprint,
        decision = alternative.qualification_decision
      })
    end
    table.sort(candidate.alternatives, function(left, right) return left.alternative_id < right.alternative_id end)
  end
  table.sort(candidates, function(left, right) return left.candidate_id < right.candidate_id end)
  table.sort(qualifications, function(left, right)
    if left.candidate_id ~= right.candidate_id then return left.candidate_id < right.candidate_id end
    return left.design_fingerprint < right.design_fingerprint
  end)
  table.sort(alternative_qualifications, function(left, right)
    if left.candidate_id ~= right.candidate_id then return left.candidate_id < right.candidate_id end
    return left.alternative_id < right.alternative_id
  end)
  local catalog = {
    schema = model.SCHEMA,
    phase = options.phase or "preselection",
    candidates = candidates,
    qualifications = qualifications,
    alternative_qualifications = alternative_qualifications,
    current_selections = {},
    context_fingerprint = fingerprint.of(context_material or {}),
    mutation_authority = false,
    selection_authority = "deterministic-policy-v2",
    generation_plan_fingerprint = options.generation_plan_fingerprint or "pending",
    compilation_plan_fingerprint = options.compilation_plan_fingerprint or "pending",
    base_candidates = deepcopy(options.base_candidates or {})
  }
  catalog.candidate_catalog_fingerprint = fingerprint.of(model.candidate_catalog_material(candidates))
  catalog.qualification_catalog_fingerprint = fingerprint.of(model.qualification_catalog_material(qualifications))
  catalog.preselection_catalog_fingerprint = fingerprint.of(model.preselection_material(catalog))
  catalog.selection_fingerprint = fingerprint.of(catalog.current_selections)
  catalog.catalog_fingerprint = fingerprint.of(model.catalog_material(catalog))
  if not options.defer_validation then
    validate.assert_owned(catalog)
    model.authority.register(catalog, model.trust_identity(catalog))
  end
  return catalog
end

function M.bind_selections(catalog, rows, options)
  options = options or {}
  if not options.trusted_owned then validate.verify_untrusted(catalog) end
  if not options.trusted_owned then model.authority.count_full_copy() end
  local result = options.trusted_owned and catalog or deepcopy(catalog)
  local selections = selection_policy.select(result, rows)
  result.current_selections = selections
  result.selection_fingerprint = fingerprint.of(selections)
  result.catalog_fingerprint = fingerprint.of(model.catalog_material(result))
  if not options.defer_validation then
    if options.trusted_owned then validate.assert_owned(result)
    else validate.verify_untrusted(result) end
    model.authority.register(result, model.trust_identity(result))
  end
  return result
end

function M.finalize(rows, context_material, compilation_operations, options)
  options = options or {}
  local build_options = {}
  for key, value in pairs(options) do build_options[key] = value end
  build_options.phase = "final"
  build_options.defer_validation = true
  build_options.children_admitted = true
  local catalog = M.from_preselection_rows(rows, context_material, build_options)
  catalog = M.bind_selections(catalog, rows, {trusted_owned = true, defer_validation = true})
  selection_policy.assert_generation_projection(catalog.current_selections, rows)
  selection_policy.assert_compilation_projection(catalog.current_selections, rows, compilation_operations or {})
  validate.assert_newly_constructed(catalog)
  return model.authority.register(catalog, model.trust_identity(catalog))
end

function M.from_generation_rows(rows, context_material, options)
  local build_options = {}
  for key, value in pairs(options or {}) do build_options[key] = value end
  build_options.defer_validation = true
  return M.bind_selections(
    M.from_preselection_rows(rows, context_material, build_options),
    rows,
    {trusted_owned = true}
  )
end

return M

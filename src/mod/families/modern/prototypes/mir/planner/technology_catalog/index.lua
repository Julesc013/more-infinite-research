local M = {}

function M.new()
  return {alternatives = {}, qualifications = {}}
end

function M.add_qualification(index, qualification)
  index.qualifications[qualification.qualification_fingerprint] = qualification
end

function M.alternative_key(candidate_id, alternative_id)
  return candidate_id .. "/" .. alternative_id
end

function M.add_alternative(index, candidate_id, alternative)
  local key = M.alternative_key(candidate_id, alternative.alternative_id)
  if index.alternatives[key] then
    error("TechnologyCatalog alternative is duplicated: " .. key, 2)
  end
  index.alternatives[key] = alternative
end

function M.qualification(index, fingerprint)
  return index.qualifications[fingerprint]
end

function M.alternative(index, candidate_id, alternative_id)
  return index.alternatives[M.alternative_key(candidate_id, alternative_id)]
end

return M

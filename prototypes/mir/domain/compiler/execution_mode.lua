local M = {}

local MODES = {
  SAFE = true,
  PREVIEW = true,
  REVIEWED = true,
  STRICT_CI = true,
  RELEASE = true
}

local ALIASES = {
  safe = "SAFE",
  preview = "PREVIEW",
  reviewed = "REVIEWED",
  ["strict-ci"] = "STRICT_CI",
  strict_ci = "STRICT_CI",
  release = "RELEASE"
}

function M.normalize(value)
  if value == nil or value == "" then return "SAFE" end
  local normalized = ALIASES[tostring(value):lower()] or tostring(value):upper()
  if not MODES[normalized] then
    error("Unknown MIR compiler execution mode: " .. tostring(value), 2)
  end
  return normalized
end

function M.review_is_fatal(mode, review_policy)
  mode = M.normalize(mode)
  review_policy = review_policy or {}
  if mode == "SAFE" or mode == "PREVIEW" then return false end
  if mode == "REVIEWED" then return review_policy.fail_reviewed_mode == true end
  if mode == "STRICT_CI" then return review_policy.allow_unbudgeted_review ~= true end
  return review_policy.allow_release_review ~= true
end

function M.include_full_diagnostics(mode)
  return M.normalize(mode) == "PREVIEW"
end

function M.values()
  return {"SAFE", "PREVIEW", "REVIEWED", "STRICT_CI", "RELEASE"}
end

return M

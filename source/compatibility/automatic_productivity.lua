-- Retained action/legacy-setting bridge for attaching to authored families.
-- This authorizes no new research identities or discovery compiler.
local M = {}

function M.applies(options)
  options = options or {}
  if (options["mir-automatic-productivity-action"] or "apply") ~= "apply" then return false end
  local modern_defaults = options["mir-automatic-create-research"] ~= true
    and options["mir-automatic-require-reviewed-data"] ~= false
  if modern_defaults then
    local legacy = options["mir-automatic-compiler-mode"]
    if legacy == "off" or legacy == "report" then return false end
  end
  return true
end

return M

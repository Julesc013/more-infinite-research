local contract = require("prototypes.mir.settings.automatic_compiler_contract")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

function M.current()
  return contract.resolve({
    action = effective_settings.get(contract.setting_names.action),
    create_research = effective_settings.get(contract.setting_names.create_research),
    require_reviewed_data = effective_settings.get(contract.setting_names.require_reviewed_data),
    legacy_mode = effective_settings.get(contract.setting_names.legacy_mode)
  })
end

function M.generation_decision(reviewed_authorization, creation_maturity)
  return contract.generation_decision(M.current(), reviewed_authorization, creation_maturity)
end

return M

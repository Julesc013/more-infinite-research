local M = {}

function M.apply(stage)
  assert(stage == "source" or stage == "fixed", "unknown public-flag fixture stage")
  local setting = assert(data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-research_material_imersite"],
    "K2SO Imersite maximum setting is absent")
  -- K2SO has its own default cap release; this fixture observes it and never
  -- changes settings while preparing a state-only handoff.
  assert(setting.default_value == 0, "K2SO Imersite maximum default differs")
end

return M

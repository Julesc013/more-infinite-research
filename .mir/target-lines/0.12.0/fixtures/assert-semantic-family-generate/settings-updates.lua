local create_research = data.raw["bool-setting"] and data.raw["bool-setting"]["mir-automatic-create-research"]
local require_reviewed = data.raw["bool-setting"] and data.raw["bool-setting"]["mir-automatic-require-reviewed-data"]
if not create_research or not require_reviewed then error("missing automatic research controls") end
create_research.default_value = true
require_reviewed.default_value = false
for _, key in ipairs({"research_auto_assembling_machine", "research_auto_lab"}) do
  local enabled = data.raw["bool-setting"] and data.raw["bool-setting"]["ips-enable-" .. key]
  if not enabled then error("missing experimental family setting " .. key) end
  enabled.default_value = true
end

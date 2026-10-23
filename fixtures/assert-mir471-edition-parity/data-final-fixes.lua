-- The same observer runs after the exact published predecessor and candidate.
-- It changes no prototypes and never grants a compatibility or production claim.
-- A byte-checked copy of the pure canonical fingerprint helper is prepared
-- beside this observer. Factorio 0.13 cannot import another mod's Lua modules.
local fingerprint = require("mir471_fingerprint")
local count = 0
for name in pairs(data.raw.technology) do
  if name:find("recipe-prod-research_", 1, true) == 1 then count = count + 1 end
end
assert(count >= 5, "Expected existing MIR research is absent")
for _, kind in ipairs({"technology", "recipe", "lab"}) do
  log("[MIR471_PROJECTION] " .. kind .. "=" .. fingerprint.of(data.raw[kind] or {}))
end

-- The same observer runs after the exact published predecessor and candidate.
-- It changes no prototypes and never grants a compatibility or production claim.
local native_require = require
local function require(name)
  if name:sub(1, 11) == "prototypes." then
    return native_require("__more-infinite-research__/" .. name:gsub("%.", "/"))
  end
  return native_require(name)
end
local fingerprint = require("prototypes.mir.core.fingerprint")
local count = 0
for name in pairs(data.raw.technology) do
  if name:find("recipe-prod-research_", 1, true) == 1 then count = count + 1 end
end
assert(count >= 5, "Expected existing MIR research is absent")
for _, kind in ipairs({"technology", "recipe", "lab"}) do
  log("[MIR471_PROJECTION] " .. kind .. "=" .. fingerprint.of(data.raw[kind] or {}))
end
-- The prepared copy appends the existing seven host ownership controls for
-- the destination only, then restores the engine prototype table before return.

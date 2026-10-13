-- This observer must never mutate MIR's startup settings.  The settings-stage
-- Lua state owns the setting prototype; it is discarded before data-final-fixes.
local specification = data.raw["string-setting"] and data.raw["string-setting"]["mir-compiler-profile"]
log("[MIR430-ABLATION] declared-default="..tostring(specification and specification.default_value or "absent"))

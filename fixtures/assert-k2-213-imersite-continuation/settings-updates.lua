-- Bind the diagnostic report explicitly, without inheriting a settings file
-- or requiring the historical private validation-settings archive.
local report = assert(data.raw["bool-setting"]["mir-debug-generation-report"])
report.default_value = true

-- Fixture-only range clamps the saved absolute cap eight to unlimited zero.
local maximum = assert(data.raw["int-setting"]["mir-max-level-worker-robots-speed"])
assert(maximum.minimum_value == 0)
maximum.minimum_value, maximum.maximum_value, maximum.default_value = -1, 0, 0
assert(data.raw["string-setting"]["mir-settings-profile-import"].default_value == "")

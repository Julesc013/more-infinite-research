local maximum = assert(data.raw["int-setting"]["mir-max-level-worker-robots-speed"])
maximum.default_value = 8
local gear = assert(data.raw["int-setting"]["ips-max-level-research_gears"])
gear.default_value = 0
assert(data.raw["string-setting"]["mir-settings-profile-import"].default_value == "")

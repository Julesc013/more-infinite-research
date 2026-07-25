local enabled = data.raw["bool-setting"] and data.raw["bool-setting"]["ips-enable-research_spoilage_preservation"]
local effect = data.raw["double-setting"] and data.raw["double-setting"]["ips-effect-per-level-research_spoilage_preservation"]
local legacy = data.raw["string-setting"] and data.raw["string-setting"]["mir-automatic-compiler-mode"]

if not enabled then error("missing scripted spoilage enable setting") end
if not effect then error("missing scripted spoilage effect setting") end
if not legacy then error("missing legacy automatic compiler setting") end

enabled.default_value = true
effect.default_value = 2
legacy.default_value = "safe-generate"


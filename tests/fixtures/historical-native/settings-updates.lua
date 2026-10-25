-- F013/F014 predate this startup-setting surface.  Their direct probe is
-- accelerated in this fixture's data-final-fixes.lua after its authored shape
-- has been checked; never manufacture modern setting prototypes for them.
local target = require("target")
if target.id == "f013" or target.id == "f014" then return end

-- The additive historical all-policy fixture uses the shipped startup setting
-- only for the three Base lines whose initial red recipe is independently
-- preflighted below. The ordinary historical fixture retains Defaults.
if target.science_policy ~= nil then
  assert(target.science_policy == "all" and (target.id == "f017" or target.id == "f100" or target.id == "f110"),
    "historical all science target differs")
  local policy = assert(data.raw["string-setting"]["mir-science-pack-ingredient-policy"],
    "historical all science setting is absent")
  assert(policy.setting_type == "startup", "historical all science setting type differs")
  local allowed = false
  for _, value in ipairs(policy.allowed_values or {}) do allowed = allowed or value == "all" end
  assert(allowed, "historical all science setting values differ")
  policy.default_value = "all"
end

-- Accelerate only the shared direct probe. F015+ also accelerates its named
-- generated continuation; F013/F014 retain their observed numeric rows as a
-- non-researched finite witness because their delivered settings surface has
-- no base-continuation tuning controls.
local direct = "research_character_mining_speed"
assert(data.raw["bool-setting"]["ips-enable-" .. direct]).default_value = true
assert(data.raw["int-setting"]["ips-cost-base-" .. direct]).default_value = 1
assert(data.raw["int-setting"]["ips-cost-linear-increment-" .. direct]).default_value = 0
assert(data.raw["double-setting"]["ips-cost-growth-" .. direct]).default_value = 1
assert(data.raw["int-setting"]["ips-max-level-" .. direct]).default_value = 1
assert(data.raw["int-setting"]["ips-research-time-" .. direct]).default_value = 1
assert(data.raw["double-setting"]["ips-effect-per-level-" .. direct]).default_value = 10

local base = "inserter-capacity-bonus"
local enabled = data.raw["bool-setting"]["mir-enable-" .. base]
if enabled then
  enabled.default_value = true
  assert(data.raw["int-setting"]["mir-cost-base-" .. base]).default_value = 1
  assert(data.raw["int-setting"]["mir-cost-linear-increment-" .. base]).default_value = 0
  assert(data.raw["double-setting"]["mir-cost-growth-" .. base]).default_value = 1
  assert(data.raw["int-setting"]["mir-max-level-" .. base]).default_value = 8
  assert(data.raw["int-setting"]["mir-research-time-" .. base]).default_value = 1
  assert(data.raw["int-setting"]["mir-effect-per-level-" .. base]).default_value = 1
end

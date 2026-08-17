local function fail(message)
  error("MIR base competitor transaction validation failed: " .. message)
end

local technologies = data.raw.technology or {}
local old_name = "better-worker-robots-storage-infinite"
local new_name = "worker-robots-storage-4"
local dependent = technologies["mir-fixture-base-competitor-dependent"]
if not dependent then fail("dependent technology is missing") end

local prerequisites = {}
for _, name in ipairs(dependent.prerequisites or {}) do prerequisites[name] = true end

local maximum = settings.startup["mir-max-level-worker-robots-storage"]
maximum = maximum and tonumber(maximum.value) or 0
local replacement_should_skip = maximum > 0 and maximum < 4

if replacement_should_skip then
  if not technologies[old_name] then fail("external owner was deleted after MIR skipped generation") end
  local retained = technologies[new_name]
  if not retained then fail("migration-safe MIR continuation was not retained below its first level") end
  if retained.hidden ~= true then fail("migration-safe MIR continuation remained visible below its first level") end
  if retained.max_level ~= "infinite" then fail("migration-safe MIR continuation was not internally infinite") end
  if retained.show_levels_info ~= false then fail("migration-safe MIR continuation exposed an infinity badge") end
  if not prerequisites[old_name] then fail("rollback changed dependent prerequisite") end
else
  if technologies[old_name] then fail("external owner remained after complete MIR replacement") end
  if not technologies[new_name] then fail("MIR replacement was not generated") end
  if prerequisites[old_name] or not prerequisites[new_name] then
    fail("dependent prerequisite was not rewired to MIR replacement")
  end
end

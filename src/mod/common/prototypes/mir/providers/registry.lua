local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local contract = require("prototypes.mir.providers.contract")
local builtins = require("prototypes.mir.providers.builtins")

local M = {}
local canonical = nil

local function build()
  if not canonical then canonical = contract.validate_all(builtins) end
  return canonical
end

function M.validate(source)
  return contract.validate_all(source)
end

function M.snapshot()
  return deepcopy(build())
end

function M.fingerprint()
  return fingerprint.of(build())
end

function M.family_rule_source()
  local rules = {}
  for _, provider in ipairs(build().providers) do table.insert(rules, deepcopy(provider.family_rule)) end
  return {schema = 2, rules = rules}
end

return M

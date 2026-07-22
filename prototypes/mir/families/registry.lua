local deepcopy = require("prototypes.mir.core.deepcopy")
local raw = require("prototypes.mir.families.rules")
local operator_dsl = require("prototypes.mir.families.operator_dsl")

local M = {}
local canonical = nil

local FORBIDDEN_KEYS = {
  data = true,
  data_raw = true,
  mod = true,
  mods = true,
  version = true,
  versions = true
}

local REQUIRED_RISKS = {
  "recycling_loop",
  "catalyst_or_self_return",
  "non_deterministic_output",
  "voiding_or_destruction",
  "matter_or_transmutation",
  "hidden_internal"
}

local function list_contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function assert_data_only(value, path)
  if type(value) == "function" then error("FamilyRule must be data-only: " .. path, 3) end
  if type(value) ~= "table" then return end
  for key, child in pairs(value) do
    if FORBIDDEN_KEYS[key] then error("FamilyRule contains forbidden field: " .. path .. "." .. key, 3) end
    assert_data_only(child, path .. "." .. tostring(key))
  end
end

local function validate(source)
  if source.schema ~= 2 then error("FamilyRule registry schema must be 2", 2) end
  assert_data_only(source, "family_rules")

  local rules, ids = {}, {}
  for _, rule in ipairs(source.rules or {}) do
    if type(rule.id) ~= "string" or rule.id == "" then error("FamilyRule id is required", 2) end
    if ids[rule.id] then error("Duplicate FamilyRule id: " .. rule.id, 2) end
    if rule.schema ~= 2 then error("FamilyRule schema must be 2: " .. rule.id, 2) end
    if type(rule.provider_id) ~= "string" or rule.provider_id == "" then
      error("FamilyRule provider_id is required: " .. rule.id, 2)
    end
    if rule.capability ~= "recipe-productivity" then
      error("Unsupported FamilyRule capability: " .. tostring(rule.capability), 2)
    end
    if type(rule.selector) ~= "table" or type(rule.selector.output_item) ~= "table" then
      error("FamilyRule output-item selector is required: " .. rule.id, 2)
    end
    if type(rule.require) ~= "table" or rule.require.visible_recipe ~= true
      or rule.require.parameter ~= false or rule.require.productivity_supported ~= true
      or rule.require.output_placeable ~= true or rule.require.researchable ~= true
      or rule.require.lab_compatible ~= true
    then
      error("FamilyRule hard evidence requirements are incomplete: " .. rule.id, 2)
    end
    for _, risk in ipairs(REQUIRED_RISKS) do
      if not list_contains(rule.deny_risks, risk) then
        error("FamilyRule required deny risk is missing: " .. rule.id .. ":" .. risk, 2)
      end
    end
    if type(rule.grouping) ~= "table"
      or (rule.grouping.strategy ~= "attach-existing" and rule.grouping.strategy ~= "proposal-only")
    then
      error("FamilyRule grouping strategy is invalid: " .. rule.id, 2)
    end
    if rule.grouping.strategy == "attach-existing" and not rule.grouping.stream then
      error("Attach-existing FamilyRule requires grouping.stream: " .. rule.id, 2)
    end
    if type(rule.effects) ~= "table" or type(rule.effects.default) ~= "number" then
      error("FamilyRule effect policy is required: " .. rule.id, 2)
    end
    if type(rule.cardinality) ~= "table" then
      error("FamilyRule cardinality policy is required: " .. rule.id, 2)
    end
    for _, field in ipairs({"maximum_candidates", "maximum_attachments", "maximum_review_required"}) do
      local value = rule.cardinality[field]
      if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
        error("FamilyRule cardinality field is invalid: " .. rule.id .. ":" .. field, 2)
      end
    end
    if type(rule.ownership) ~= "table" or rule.ownership.strategy ~= "prefer-existing-exact-owner" then
      error("FamilyRule exact-owner policy is required: " .. rule.id, 2)
    end
    if type(rule.targets) ~= "table" or not list_contains(rule.targets.requires_features, "recipe_productivity") then
      error("FamilyRule positive target requirement is missing: " .. rule.id, 2)
    end
    if type(rule.support_claim) ~= "table" or rule.support_claim.public ~= false then
      error("FamilyRule support claim boundary is required: " .. rule.id, 2)
    end
    operator_dsl.validate(rule.operators)
    ids[rule.id] = true
    table.insert(rules, deepcopy(rule))
  end
  table.sort(rules, function(a, b) return a.id < b.id end)
  return {schema = 2, rules = rules}
end

local function build()
  if canonical then return canonical end
  canonical = validate(raw)
  return canonical
end

function M.validate(source)
  if type(source) ~= "table" then error("FamilyRule registry must be a table", 2) end
  return deepcopy(validate(source))
end

function M.snapshot()
  return deepcopy(build())
end

return M

-- Control-stage adapter for the pure authored research catalogue.
-- The catalogue accepts pre-existing foreign continuations as data and never
-- reads Factorio globals itself. Native creation history distinguishes those
-- rows from the continuations MIR emitted during the same prototype stage.
local catalogue = require("research.catalogue")
local target = require("platform.target")
local modern = require("compatibility.modern_catalogue")

local foreign_technology_prototypes
local native_adoptions
local withheld_native_owners
local native_credit_groups
local retirement_facts = {}
if target.id == "f200" or target.id == "f210" then
  local live_technologies
  if prototypes ~= nil and prototypes.technology ~= nil then
    live_technologies = prototypes.technology
  elseif game ~= nil then
    live_technologies = game.technology_prototypes
  end
  if live_technologies ~= nil then
    foreign_technology_prototypes = {}
    for _, name in ipairs(modern.continuation_names(script and script.active_mods)) do
      local existing = live_technologies[name]
      if existing ~= nil then
        local get_history = prototypes and prototypes.get_history
        if type(get_history) ~= "function" then
          error("MIR runtime catalogue requires prototype creation history for " .. name, 2)
        end
        local history = get_history("technology", name)
        if type(history) ~= "table" or type(history.created) ~= "string" or history.created == "" then
          error("MIR runtime catalogue requires prototype creation history for " .. name, 2)
        end
        if history.created ~= "more-infinite-research" then
          -- The exact Muria adapter's ninth level is not one of the six
          -- yieldable shared tails. Unexpected final custody must refuse,
          -- rather than admitting an unowned row to MIR's cap catalogue.
          if name == "weapon-shooting-speed-9" then
            error("MIR runtime catalogue requires MIR creation custody for weapon-shooting-speed-9", 2)
          end
          foreign_technology_prototypes[name] = existing
        end
      end
    end
    if modern.has_secretas(script and script.active_mods)
        and live_technologies["worker-robots-storage-9"] == nil then
      -- Data-stage admission may yield to a qualified earlier infinite stage.
      -- Record the delegated setting identity only when MIR9 is absent: a
      -- later foreign edit must never remove custody of an existing MIR9.
      for level = 4, 8 do
        local foreign = foreign_technology_prototypes["worker-robots-storage-" .. level]
        if foreign ~= nil and foreign.max_level == 4294967295 then
          foreign_technology_prototypes["worker-robots-storage-9"] = true
        end
      end
    end
  end
  local native_data = prototypes and prototypes.mod_data
  local adopted = native_data and native_data["more-infinite-research-native-adoptions"]
  if adopted ~= nil then
    native_adoptions, withheld_native_owners, native_credit_groups = require("research.native_adoption").read(adopted.data,
      modern.native_owners(script and script.active_mods), retirement_facts)
  end
end

local M = {}

function M.native_credit_groups()
  return require("research.native_adoption").credit_groups(native_credit_groups)
end

function M.galore_sulfur_retired()
  return retirement_facts.galore_sulfur_retired == true
end

-- Select and retain the bounded authored rows during control parsing, before
-- Factorio freezes imports for callbacks. Later callers receive detached rows
-- from the pure catalogue's cache.
-- A few host controls inject a minimal declaration stub in place of the
-- shipped module; the real player module always supplies this preparation
-- hook.
if type(catalogue.prepare) == "function" then
  catalogue.prepare(foreign_technology_prototypes, withheld_native_owners)
end

function M.declared()
  local rows = catalogue.declared(foreign_technology_prototypes, withheld_native_owners)
  if native_adoptions == nil or next(native_adoptions) == nil then return rows end
  for _, row in ipairs(rows) do
    local adoption = native_adoptions and native_adoptions[row.id]
    if adoption and row.ownership_kind == "nativeowner" then
      local recipes = {}
      for index, name in ipairs(adoption.recipes) do recipes[index] = name end
      row.native_adoption = {recipes=recipes, effect_change=adoption.effect_change,
        configured_change=adoption.configured_change}
    end
  end
  return rows
end

-- Withholding new settings authority does not erase a proven earlier cap.
-- These at-most-five exact declarations are solely for releasing existing
-- ownership; they never enter the Library or the new-control catalogue.
function M.restoration_only()
  local rows = {}
  if withheld_native_owners == nil or next(withheld_native_owners) == nil then return rows end
  for _, owner in ipairs(modern.native_owners(script and script.active_mods)) do
    if withheld_native_owners[owner.id] ~= nil then
      rows[#rows + 1] = {id=owner.id, family=owner.family, cap_setting=owner.setting,
        ownership_kind="nativeowner", native_owner_identity=owner.id,
        native_admission=owner.admission,
        legacy_binding={source="native-owner", operation="preserve_native_owner"}}
    end
  end
  return rows
end

function M.internal_credit_ids()
  local ids = catalogue.internal_credit_ids()
  for _, row in ipairs(require("research.native_credit_definitions").collected_descriptors(native_credit_groups)) do
    ids[row.positive_id], ids[row.negative_id] = true, true
  end
  return ids
end

function M.externally_supplied_continuation(name)
  return foreign_technology_prototypes ~= nil and foreign_technology_prototypes[name] ~= nil
end

return M

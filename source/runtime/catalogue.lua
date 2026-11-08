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
local finite_research_speed_provider
local worker_storage
local admission_facts = {}
if target.id == "f200" or target.id == "f210" then
  local native_data = prototypes and prototypes.mod_data
  local adopted = native_data and native_data["more-infinite-research-native-adoptions"]
  if adopted ~= nil then
    native_adoptions, withheld_native_owners, native_credit_groups = require("research.native_adoption").read(adopted.data,
      modern.native_owners(script and script.active_mods), admission_facts)
    worker_storage = admission_facts.worker_storage
  end
  local live_technologies
  if prototypes ~= nil and prototypes.technology ~= nil then
    live_technologies = prototypes.technology
  elseif game ~= nil then
    live_technologies = game.technology_prototypes
  end
  if live_technologies ~= nil then
    foreign_technology_prototypes = {}
    local creators = {}
    local names = modern.continuation_names(script and script.active_mods)
    if worker_storage ~= nil then
      local named = {}
      for _, name in ipairs(names) do named[name] = true end
      for _, stage in ipairs(worker_storage.finite) do
        if not named[stage.name] then names[#names + 1], named[stage.name] = stage.name, true end
      end
      if not named[worker_storage.technology] then names[#names + 1] = worker_storage.technology end
    end
    for _, name in ipairs(names) do
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
        creators[name] = history.created
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
    if worker_storage ~= nil then
      for _, stage in ipairs(worker_storage.finite) do
        local technology, provider = live_technologies[stage.name], creators[stage.name]
        if technology == nil or technology.max_level ~= stage.max_level or provider == nil
            or provider == "more-infinite-research" then
          error("MIR worker robot storage: finite creation custody changed for " .. stage.name, 2)
        end
        stage.provider = provider
      end
      local technology, provider = live_technologies[worker_storage.technology], creators[worker_storage.technology]
      if technology == nil or technology.max_level ~= 4294967295 or provider == nil
          or technology.level ~= nil and technology.level ~= worker_storage.level
          or (provider == "more-infinite-research") ~= worker_storage.owned then
        error("MIR worker robot storage: infinite creation custody changed for " .. worker_storage.technology, 2)
      end
      if not worker_storage.owned then worker_storage.provider = provider end
    end
    local seven = live_technologies["research-speed-7"]
    local eight = live_technologies["research-speed-8"]
    if foreign_technology_prototypes["research-speed-7"] ~= nil and seven.max_level == 7
        and (eight == nil or eight.max_level ~= 4294967295) then
      error("MIR finite research-speed route requires its infinite eighth continuation", 2)
    end
    if creators["research-speed-8"] == "more-infinite-research" then
      local provider = creators["research-speed-7"]
      if seven == nil or seven.max_level ~= 7 or eight.max_level ~= 4294967295
          or provider == nil or provider == "more-infinite-research" then
        error("MIR finite research-speed continuation requires foreign finite7 and MIR infinite8 custody", 2)
      end
      finite_research_speed_provider = provider
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
  if worker_storage ~= nil and live_technologies == nil then
    error("MIR worker robot storage: missing admitted technology prototypes", 2)
  end
end

local M = {}

function M.native_credit_groups()
  return require("research.native_adoption").credit_groups(native_credit_groups)
end

function M.galore_sulfur_retired()
  return admission_facts.galore_sulfur_retired == true
end

-- Select and retain the bounded authored rows during control parsing, before
-- Factorio freezes imports for callbacks. Later callers receive detached rows
-- from the pure catalogue's cache.
-- A few host controls inject a minimal declaration stub in place of the
-- shipped module; the real player module always supplies this preparation
-- hook.
if type(catalogue.prepare) == "function" then
  catalogue.prepare(foreign_technology_prototypes, withheld_native_owners, finite_research_speed_provider ~= nil, worker_storage)
end

function M.declared()
  local rows = catalogue.declared(foreign_technology_prototypes, withheld_native_owners, finite_research_speed_provider ~= nil, worker_storage)
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
  if name == "research-speed-7" and finite_research_speed_provider ~= nil then return false end
  if name == "worker-robots-storage-4" and worker_storage ~= nil then return not worker_storage.owned end
  return foreign_technology_prototypes ~= nil and foreign_technology_prototypes[name] ~= nil
end

function M.finite_research_speed_provider()
  return finite_research_speed_provider
end

function M.worker_storage_route()
  if worker_storage == nil then return nil end
  local route = {technology=worker_storage.technology, level=worker_storage.level,
    predecessor=worker_storage.predecessor, owned=worker_storage.owned, provider=worker_storage.provider,
    legacy_compatible=worker_storage.legacy_compatible, finite={}}
  for index, stage in ipairs(worker_storage.finite) do
    route.finite[index] = {name=stage.name, max_level=stage.max_level, provider=stage.provider}
  end
  return route
end

return M

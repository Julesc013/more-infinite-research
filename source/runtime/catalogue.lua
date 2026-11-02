-- Control-stage adapter for the pure authored research catalogue.
-- The catalogue accepts pre-existing foreign continuations as data and never
-- reads Factorio globals itself. Native creation history distinguishes those
-- rows from the continuations MIR emitted during the same prototype stage.
local catalogue = require("research.catalogue")
local target = require("platform.target")
local modern = require("compatibility.modern_catalogue")

local foreign_technology_prototypes
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
          foreign_technology_prototypes[name] = existing
        end
      end
    end
  end
end

local M = {}

-- Select and retain the bounded authored rows during control parsing, before
-- Factorio freezes imports for callbacks. Later callers receive detached rows
-- from the pure catalogue's cache.
-- A few host controls inject a minimal declaration stub in place of the
-- shipped module; the real player module always supplies this preparation
-- hook.
if type(catalogue.prepare) == "function" then
  catalogue.prepare(foreign_technology_prototypes)
end

function M.declared()
  return catalogue.declared(foreign_technology_prototypes)
end

function M.internal_credit_ids()
  return catalogue.internal_credit_ids()
end

function M.externally_supplied_continuation(name)
  return foreign_technology_prototypes ~= nil and foreign_technology_prototypes[name] ~= nil
end

return M

-- Control-stage adapter for the pure authored research catalogue.
-- The catalogue accepts a technology map as data and never reads Factorio
-- globals itself; this module supplies the exact runtime map when available.
local catalogue = require("research.catalogue")
local target = require("platform.target")

local technology_prototypes
if target.id == "f200" or target.id == "f210" then
  if prototypes ~= nil and prototypes.technology ~= nil then
    technology_prototypes = prototypes.technology
  elseif game ~= nil then
    technology_prototypes = game.technology_prototypes
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
  catalogue.prepare(technology_prototypes)
end

function M.declared()
  return catalogue.declared(technology_prototypes)
end

function M.internal_credit_ids()
  return catalogue.internal_credit_ids()
end

return M

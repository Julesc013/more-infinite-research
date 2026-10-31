-- Bounded localized search payloads for the visible Research Library.
-- The host requests one result per technology; the model keeps the first
-- field as the caption and searches the remaining associated recipe/product
-- names without retaining native prototype objects.
local M = {
  separator = "\31",
  subject_limit = 128,
  effect_work_limit = 1024,
  product_work_limit = 1024,
}

local function valid_name(value)
  return type(value) == "string" and value ~= "" and #value <= 1024
end

local function localized_name(prototype, fallback)
  local ok, value = pcall(function() return prototype and prototype.localised_name end)
  if ok and value ~= nil then return {"?", value, fallback} end
  return fallback
end

-- The returned LocalisedString contains the technology name first, followed
-- by a private separator and the bounded recipe/material names used for
-- search. The UI itself still renders native LocalisedStrings for each row.
function M.search_request(technology, collections)
  local technology_name
  local ok = pcall(function() technology_name = technology and technology.name end)
  if not ok or not valid_name(technology_name) then return nil, 0, true end

  local parts = {{"?", technology.localised_name, technology_name}}
  local seen, subjects, work, limited = {}, 0, 0, false
  local recipes = type(collections) == "table" and collections.recipe or nil
  local items = type(collections) == "table" and collections.item or nil
  local fluids = type(collections) == "table" and collections.fluid or nil

  local function append(kind, name, prototype)
    if not valid_name(name) then limited = true; return end
    local identity = kind .. "\0" .. name
    if seen[identity] then return end
    if subjects >= M.subject_limit then limited = true; return end
    seen[identity], subjects = true, subjects + 1
    parts[#parts + 1] = M.separator
    parts[#parts + 1] = localized_name(prototype, name)
  end

  local prototype = technology.prototype
  local effects = prototype and prototype.effects
  if effects ~= nil then
    local effects_ok = pcall(function()
      for _, effect in ipairs(effects) do
        work = work + 1
        if work > M.effect_work_limit or subjects >= M.subject_limit then limited = true; break end
        local kind = effect and effect.type
        if kind == "unlock-recipe" or kind == "change-recipe-productivity" then
          local name = effect.recipe
          local recipe = valid_name(name) and recipes and recipes[name] or nil
          append("recipe", name, recipe)
          local products = recipe and recipe.products
          if products ~= nil then
            local products_ok = pcall(function()
              for _, product in ipairs(products) do
                work = work + 1
                if work > M.product_work_limit or subjects >= M.subject_limit then limited = true; break end
                local product_type, product_name = product and product.type, product and product.name
                if product_type == "item" or product_type == "fluid" then
                  local collection = product_type == "item" and items or fluids
                  append(product_type, product_name, collection and collection[product_name])
                else
                  limited = true
                end
              end
            end)
            if not products_ok then limited = true end
          end
        end
      end
    end)
    if not effects_ok then limited = true end
  end

  if subjects == 0 then return technology.localised_name, 0, limited end

  -- LocalisedString accepts at most twenty parameters per array node. The
  -- outer node contains at most thirteen groups of twenty parts at the subject
  -- cap, so this stays within the engine's nesting/parameter contract.
  local payload = {""}
  for first = 1, #parts, 20 do
    local group = {""}
    for index = first, math.min(first + 19, #parts) do group[#group + 1] = parts[index] end
    payload[#payload + 1] = group
  end
  return payload, subjects, limited
end

return M

-- Complete, named productivity vectors only. No world/recipe discovery or writes.
local M = {}
local TYPE = "change-recipe-productivity"
local function finite(value)
  return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function effects(values)
  if type(values)~="table" then return nil end
  local map, count = {}, 0
  for index, effect in pairs(values) do
    if type(index)~="number" or index<1 or index~=math.floor(index) or index>#values
        or type(effect)~="table" or effect.type~=TYPE or type(effect.recipe)~="string"
        or effect.recipe=="" or effect.recipe:find("\0",1,true) or not finite(effect.change)
        or map[effect.recipe]~=nil then
      -- Observe only this rejected row. Raw fields avoid invoking a malformed
      -- table's missing-field behavior after the predicate has short-circuited.
      local detail={component=index,component_type=type(effect)}
      if type(effect)=="table" then
        detail.recipe=rawget(effect,"recipe")
        detail.effect_type=rawget(effect,"type")
        detail.change=rawget(effect,"change")
      end
      return nil,nil,detail
    end
    map[effect.recipe]=effect.change; count=count+1
  end
  if count~=#values then return nil end
  return map, count
end

-- The external public technology supplies the entire independent recipe basis
-- and relative coefficients. The authored descriptor supplies only its tuning.
-- Each positive coefficient must have the target's exact native representation;
-- each negative coefficient must be its opposite under the existing tolerance.
function M.pair(positive, negative, anchor, reference, change, native_matches, opposite_matches)
  local p, size, positive_shape=effects(positive)
  local n, negative_size, negative_shape=effects(negative)
  local r, reference_size, reference_shape=effects(reference)
  -- Return the first rejected invariant as error-path data. Admission and the
  -- complete-vector comparison remain unchanged; no partial vector is usable.
  local function reject(reason, role, recipe, expected, shape)
    local detail=shape or {recipe=recipe,expected=expected}
    detail.reason=reason;detail.role=role
    if recipe then
      detail.positive=p and p[recipe]
      detail.negative=n and n[recipe]
      detail.reference=r and r[recipe]
      local rows=role=="positive" and positive or role=="negative" and negative or reference
      for index,effect in ipairs(rows) do
        if effect.recipe==recipe then detail.component=index;break end
      end
    end
    return nil,nil,detail
  end
  if not p then return reject("vector-shape","positive",nil,nil,positive_shape) end
  if not n then return reject("vector-shape","negative",nil,nil,negative_shape) end
  if not r then return reject("vector-shape","reference",nil,nil,reference_shape) end
  if size<2 then return reject("vector-not-expanded","positive") end
  if size~=negative_size then return reject("vector-count","negative") end
  if size~=reference_size then return reject("reference-vector-count","reference") end
  if not finite(r[anchor]) or r[anchor]<=0 then
    return reject("reference-anchor","reference",anchor)
  end
  if p[anchor]==nil then return reject("vector-anchor","positive",anchor) end
  local basis={}
  for recipe, coefficient in pairs(r) do
    if coefficient<=0 then return reject("reference-coefficient","reference",recipe) end
    if p[recipe]==nil then return reject("vector-recipe","positive",recipe) end
    if n[recipe]==nil then return reject("vector-recipe","negative",recipe) end
    basis[recipe]=coefficient/r[anchor]
    local expected=change*basis[recipe]
    if not native_matches(p[recipe],expected) then
      return reject("positive-component","positive",recipe,expected)
    end
    if p[recipe]==0 and n[recipe]~=0 or not opposite_matches(n[recipe],-p[recipe]) then
      return reject("negative-component","negative",recipe,-p[recipe])
    end
  end
  return p, basis
end

-- Validate the complete sum per named main, never across independent families.
-- Independent anchors identify each inclusion directly. Coupled anchors admit
-- only the exact all/none cases; other mixtures need a different authored basis.
function M.inclusions(main_effects, rows, matches)
  local main=effects(main_effects)
  if not main then return nil end
  local anchors, all, coupled={}, {}, false
  for index,row in ipairs(rows) do anchors[row.descriptor.recipe]=index end
  for index,row in ipairs(rows) do
    for recipe,change in pairs(row.vector or {[row.descriptor.recipe]=row.scalar}) do
      all[recipe]=(all[recipe] or 0)+change
      if anchors[recipe] and anchors[recipe]~=index then coupled=true end
    end
  end
  local function equal(left,right)
    for recipe,change in pairs(left) do
      if right[recipe]==nil or not matches(change,right[recipe]) then return false end
    end
    for recipe in pairs(right) do if left[recipe]==nil then return false end end
    return true
  end
  local included, expected={},{}
  if coupled then
    local active
    if next(main)==nil then active=false
    elseif equal(main,all) then active=true
    else return nil end
    for index in ipairs(rows) do included[index]=active end
    return included
  end
  for index,row in ipairs(rows) do
    local actual=main[row.descriptor.recipe]
    if actual~=nil and not matches(actual,row.scalar) then return nil end
    included[index]=actual~=nil
    if included[index] then
      for recipe,change in pairs(row.vector or {[row.descriptor.recipe]=row.scalar}) do
        expected[recipe]=(expected[recipe] or 0)+change
      end
    end
  end
  if not equal(main,expected) then return nil end
  return included
end

return M

local PACK = "planetary-data"
local CIRCULAR = "mir473-circular-planetary-owner"
local SEEDED = "mir473-seeded-planetary-owner"

local function reaches(name, wanted, seen)
  if name == wanted then return true end
  if seen[name] then return false end
  seen[name] = true
  for _, prerequisite in ipairs((data.raw.technology[name] or {}).prerequisites or {}) do
    if reaches(prerequisite, wanted, seen) then return true end
  end
  return false
end

local function positive_item_ingredient(row)
  if type(row) ~= "table" or (row.type ~= nil and row.type ~= "item") then return false end
  local name, amount = row.name or row[1], row.amount or row[2]
  return name == PACK and type(amount) == "number" and amount == amount and amount > 0
    and amount < math.huge
end

local retained, effects = 0, 0
for name, technology in pairs(data.raw.technology) do
  if name:find("recipe-prod-research_", 1, true) == 1 then
    for _, ingredient in ipairs((technology.unit or {}).ingredients or {}) do
      if (ingredient.name or ingredient[1]) == PACK then
        assert(positive_item_ingredient(ingredient), "fresh science quantity or item type was lost")
        assert(reaches(name, SEEDED, {}), "the independently seeded foreign gate was lost")
        assert(not reaches(name, CIRCULAR, {}), "a circular foreign gate became required")
        for _, effect in ipairs(technology.effects or {}) do
          if effect.type == "change-recipe-productivity" and type(effect.change) == "number"
            and effect.change > 0 then effects = effects + 1 end
        end
        retained = retained + 1
        break
      end
    end
  end
end

-- Scripted research shares this prefix but legitimately uses `nothing`
-- effects. Preserve the published witness: retained science plus positive
-- productivity somewhere in that retained research, not on every prefix row.
assert(retained > 0 and effects > 0, "fresh science research or positive effects were removed")
local circular = data.raw.technology[CIRCULAR]
assert(circular and circular.unit and circular.unit.ingredients[1][1] == PACK
  and circular.unit.ingredients[1][2] == 1 and #(circular.prerequisites or {}) == 0
  and circular.effects and circular.effects[1].type == "unlock-recipe"
  and circular.effects[1].recipe == "a-mir473-circular-planetary-data",
  "foreign circular research was mutated")
if type(log) == "function" then
  log("[MIR5_FRESH_SCIENCE] retained=" .. retained .. " effects=" .. effects
    .. " selected_owner=" .. SEEDED .. " scope=data-stage-only")
end

local M = {}

local EARLY = "recipe-prod-research_material_imersite-1"
local TAIL = "recipe-prod-research_material_imersite-4"
local HOLDER = "mir-k2-imersite-staged-state-1"
local CARRIER = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"
local FIXTURE = "mir-fixture-mir5-k2-imersite-held-public-flags"

local function effect(row, label)
  local value = row.effects and row.effects[1]
  assert(type(row.effects) == "table" and #row.effects == 1 and type(value) == "table"
      and value.type == "change-recipe-productivity" and value.recipe == POWDER and value.change == 0.02,
    label .. " Imersite effect differs")
end

function M.apply(stage)
  assert(stage == "source" or stage == "fixed", "unknown public-flag fixture stage")
  assert(mods.base == "2.1.23" and mods["elevated-rails"] == "2.1.23"
      and mods.quality == "2.1.23" and mods.recycler == "2.1.23" and mods["space-age"] == "2.1.23"
      and mods.flib == "0.17.2" and mods["k2so-assets"] == "1.0.7" and mods.Krastorio2 == "2.1.4"
      and mods["Krastorio2-spaced-out"] == "2.0.19" and mods.Krastorio2Assets == "2.1.0"
      and mods.Krastorio2MenuSimulations == "2.1.0" and mods["xy-k2so-enhancements-nulls-fork"] == "0.8.3"
      and mods["more-infinite-research"] == "5.0.21000"
      and mods[FIXTURE] == (stage == "source" and "0.1.0" or "0.2.0"),
    "unexpected F210 K2SO Imersite closure")
  local rows = assert(data.raw.technology, "technology prototypes are absent")
  local early, tail = assert(rows[EARLY], "public Imersite early row is absent"),
    assert(rows[TAIL], "public Imersite continuation row is absent")
  assert(early.level == 1 and early.max_level == 3 and early.hidden ~= true, "public Imersite early identity differs")
  assert(tail.level == 4 and (tail.max_level == "infinite" or tail.max_level == 4294967295)
      and tail.hidden ~= true, "public Imersite continuation identity differs")
  effect(early, "public early")
  effect(tail, "public continuation")
  for _, row in ipairs({
    {HOLDER, 1}, {CARRIER, 4},
  }) do
    local carrier = assert(rows[row[1]], "hidden Imersite carrier is absent: " .. row[1])
    assert(carrier.level == row[2] and carrier.hidden == true
        and (carrier.max_level == "infinite" or carrier.max_level == 4294967295),
      "hidden Imersite carrier identity differs: " .. row[1])
    effect(carrier, row[1])
  end
end

return M

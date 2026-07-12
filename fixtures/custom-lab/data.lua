local function deepcopy(value)
  if table.deepcopy then return table.deepcopy(value) end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[copy(k)] = copy(vv) end
    return out
  end
  return copy(value)
end

local base_lab = data.raw.lab and data.raw.lab.lab
if base_lab then
  local target_profile = require("__more-infinite-research__.prototypes.mir.platform.factorio.target_profiles").current()
  local custom = deepcopy(base_lab)
  custom.name = "mir-fixture-custom-lab"
  custom.minable = custom.minable and deepcopy(custom.minable) or nil
  if custom.minable then custom.minable.result = "mir-fixture-custom-lab" end
  custom.inputs = {
    "automation-science-pack",
    "mir-custom-only-science-pack"
  }

  local item = {
    type = "item",
    name = "mir-fixture-custom-lab",
    icon = base_lab.icon or "__base__/graphics/icons/lab.png",
    icon_size = base_lab.icon_size or 64,
    subgroup = "production-machine",
    order = "z[mir-fixture-custom-lab]",
    place_result = "mir-fixture-custom-lab",
    stack_size = 10
  }

  local science_pack_type = target_profile.prototype_shapes.science_pack_prototype_kinds[1]
  local pack = {
    type = science_pack_type,
    name = "mir-custom-only-science-pack",
    icon = "__base__/graphics/icons/logistic-science-pack.png",
    icon_size = 64,
    subgroup = "science-pack",
    order = "z[mir-custom-only-science-pack]",
    stack_size = 200
  }
  if science_pack_type == "tool" then
    pack.durability = 1
    pack.durability_description_key = "description.science-pack-remaining-amount-key"
    pack.factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key"
    pack.durability_description_value = "description.science-pack-remaining-amount-value"
  end

  data:extend({item, pack, custom})
end

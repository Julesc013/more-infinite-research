-- SCI-RESEARCH-01 representative only. The exact reporter provider and
-- package/settings closure remain unknown; this fixture must not be presented
-- as a reproduction of that report.
local foreign_science = "mir5-foreign-astral-insight-pack"
local foreign_prerequisite = "mir5-foreign-astral-theory-17"
local foreign_research = "Space-Lab-Research-61"

data:extend({
  {
    type = "tool",
    name = foreign_science,
    icon = "__base__/graphics/icons/utility-science-pack.png",
    icon_size = 64,
    subgroup = "science-pack",
    order = "z[mir5-foreign-astral-insight-pack]",
    stack_size = 200,
    durability = 1,
    durability_description_key = "description.science-pack-remaining-amount-key",
    factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key",
    durability_description_value = "description.science-pack-remaining-amount-value"
  },
  {
    type = "technology",
    name = foreign_prerequisite,
    icon = "__base__/graphics/technology/research-speed.png",
    icon_size = 256,
    prerequisites = {"chemical-science-pack"},
    unit = {
      count = 17,
      time = 17,
      ingredients = {{"automation-science-pack", 1}, {"chemical-science-pack", 1}, {foreign_science, 1}}
    },
    effects = {{type = "character-running-speed", modifier = 0.01}}
  },
  {
    type = "technology",
    name = foreign_research,
    icon = "__base__/graphics/technology/research-speed.png",
    icon_size = 256,
    prerequisites = {foreign_prerequisite},
    unit = {
      count = 61,
      time = 61,
      ingredients = {{"automation-science-pack", 1}, {"utility-science-pack", 1}, {foreign_science, 1}}
    },
    effects = {{type = "laboratory-speed", modifier = 0.061}},
    max_level = 61,
    upgrade = true
  }
})

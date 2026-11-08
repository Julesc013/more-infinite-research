-- Deliberately independent of MIR's catalogue and both tested versions.
-- This same finite owner is installed for the published baseline, corrected
-- candidate and protected MIR4 predecessor. No runtime state is fabricated.
assert(data.raw.technology["worker-robots-storage-4"] == nil,
  "finite worker fixture requires an unoccupied fourth native level")
data:extend({{
  type = "technology",
  name = "worker-robots-storage-4",
  icon = "__base__/graphics/technology/worker-robots-storage.png",
  icon_size = 256,
  upgrade = true,
  prerequisites = {"worker-robots-storage-3"},
  effects = {{type="worker-robot-storage", modifier=2}},
  unit = {count=1000, time=37, ingredients={
    {"automation-science-pack", 2},
    {"logistic-science-pack", 3},
    {"utility-science-pack", 4},
  }},
}})

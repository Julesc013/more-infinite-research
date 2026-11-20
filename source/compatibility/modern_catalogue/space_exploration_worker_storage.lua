-- One captured worker-storage work contract shared by the F200 non-K2 Space
-- Exploration selector and the established F210 Space Exploration catalogue.
-- It is an authored literal, not a mod-graph or prototype lookup.
return {
  science_key = "science_se_worker_robots_storage",
  science = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "se-rocket-science-pack",
    "se-material-science-pack-1",
    "space-science-pack"
  },
  continuation = {
    science = "science_se_worker_robots_storage",
    prerequisites = {"worker-robots-storage-3"},
    effects = {{type="worker-robot-storage", scale=1, raw=false}}
  }
}

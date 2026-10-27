-- This is a bounded source-fixture contract, not a MIR5 catalogue. MIR 1.0.0
-- declares 31 enable settings; F200 emits only source rows whose original
-- recipe/item predicates resolve on the exact F200 data stage.
return {
  technology_prefix = "recipe-prod-research_",
  technology_suffix = "-1",
  maximum_rows = 31,
  minimum_rows = 2,
  direct = "recipe-prod-research_gears-1",
  unavailable_space_age_setting = "ips-enable-research_breeding",
  source_formula = "8000 * 2^(L-1)",
  source_time = 60,
  source_science = {
    ["automation-science-pack"] = 1,
    ["chemical-science-pack"] = 1,
    ["logistic-science-pack"] = 1,
    ["production-science-pack"] = 1,
  },
  -- Exact F200-effective extras from the published 1.0.0
  -- prototypes/util.lua `EXTRA` map.  Agricultural science is absent on
  -- F200, so the rocket stream retains only its available military extra.
  source_science_extras = {
    belts = {"space-science-pack"},
    inserters = {"space-science-pack"},
    bullets = {"military-science-pack", "space-science-pack"},
    rockets = {"military-science-pack"},
  },
}

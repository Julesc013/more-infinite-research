-- The laboratory is the fixture's only prototype mutation.  It is a clone of
-- Base's laboratory, accepts its original science vector, and has void power.
local facts = require("__mir-fixture-mir5-angelbob-f210-steel__/fixture_facts")
local lab = table.deepcopy(assert(data.raw.lab.lab, "Angel/Bob steel fixture requires the Base lab"))
lab.name = facts.fast_lab
lab.minable = nil
lab.energy_source = {type="void"}
lab.energy_usage = "1W"
lab.researching_speed = facts.fast_lab_speed
data:extend({lab})

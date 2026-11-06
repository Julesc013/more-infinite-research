-- Independent defaults recovered from published8643cc91 producer and Base2.1.23.
-- This observer never changes either research technology or its prerequisites.
local oracle = require("__mir-fixture-native-research-speed-finite__/oracle")
oracle.prototypes(data.raw.technology)
local lab = table.deepcopy(assert(data.raw.lab.lab))
lab.name = "mir-finite-speed-lab"
lab.researching_speed = 10000
lab.module_slots = 0
lab.allowed_effects = {}
data:extend({lab})

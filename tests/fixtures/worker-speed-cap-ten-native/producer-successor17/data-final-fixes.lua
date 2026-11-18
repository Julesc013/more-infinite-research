local fixture = require("__mir-fixture-mir5-worker-speed-cap-ten__/fixture_data_final")
fixture.apply("producer-successor17", function(tuple)
  log("[MIR_ACTIVE_MODS] " .. tuple)
end)

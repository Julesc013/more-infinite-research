local fixture = require("__mir-fixture-mir5-worker-speed-cap-ten__/fixture_control")
fixture.apply("current-observe16", function(text)
  log("[MIR_ACTIVE_MODS] " .. text)
end)

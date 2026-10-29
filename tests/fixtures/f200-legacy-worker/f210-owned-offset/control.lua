local successor = require("fixture_control")
local owner = require("offset-owner")
script.on_configuration_changed(function(event)
  owner.reconcile(storage.mir5_f200_legacy_worker, remote.call("mir-fixture-worker-entry", "get"),
    game, script.active_mods, settings.startup, successor.assert_restored)
  successor.configuration_changed(event, "0.4.0")
end)

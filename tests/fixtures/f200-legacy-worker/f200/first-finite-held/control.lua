local successor = require("fixture_control")
local owner = require("offset-owner")
script.on_configuration_changed(function(event)
  owner.reconcile(storage.mir5_f200_legacy_worker, remote.call("mir-fixture-worker-entry", "get"),
    game, script.active_mods, settings.startup, successor.assert_restored, "hold", successor.assert_held_inventory)
  successor.hold_configuration("0.5.0")
end)

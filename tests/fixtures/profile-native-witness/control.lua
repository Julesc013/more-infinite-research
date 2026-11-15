local witness = require("witness")
remote.add_interface("mir_profile_native_witness", {
  observe = function()
    return witness.runtime(prototypes, script.active_mods.base, settings.startup["profile-native-witness-mode"].value)
  end,
})

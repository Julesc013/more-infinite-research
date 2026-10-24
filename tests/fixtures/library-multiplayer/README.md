# Library multiplayer fixture protocol

Start this fresh F200 world, then connect exactly two real clients whose actual `LuaPlayer.locale` values report `en` and `de`. Initial unchanged locales do not require a locale-change event. Wait for the `rejoin-ready` marker, disconnect and reconnect both clients, then wait for `restart-ready` and the requested `mir5-library-multiplayer-restart` save. Restart the host from that save, reconnect both clients again, and wait for `completed` plus `mir5-native-complete`.

The control requests eight GUI screenshots under `script-output/mir5-library-multiplayer/`: Availability, initial personal view, rejoin and host restart for each client. The initial Availability view contains exactly two terminal Space Age requirement explanations and stays open for 60 ticks before ordinary personal views replace it. Screenshots become rendering evidence only after external PNG readback confirms the files; a headless request is not a rendering result.

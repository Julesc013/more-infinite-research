# Library multiplayer fixture protocol

Start this fresh F200 world, then connect exactly two real clients whose actual
`LuaPlayer.locale` values report `en` and `de`. Initial unchanged locales do
not require a locale-change event. Wait for the `rejoin-ready`
marker, disconnect and reconnect both clients, then wait for `restart-ready`
and the requested `mir5-library-multiplayer-restart` save. Restart the host
from that save, reconnect both clients again, and wait for `completed` plus
`mir5-native-complete`.

The control requests six GUI screenshots under
`script-output/mir5-library-multiplayer/`. They are rendering evidence only
after an external PNG readback confirms the files; a headless request is not a
rendering result.

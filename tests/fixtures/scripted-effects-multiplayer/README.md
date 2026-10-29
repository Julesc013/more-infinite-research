# Scripted-effects multiplayer fixture protocol

The fixture starts a disposable F200 Space Age world and waits for exactly two connected clients named `MIR5English` (`en`) and `MIR5Deutsch` (`de`). It emits `ready`, `rejoin-ready`, `restart-ready`, and `completed` markers. The runner must disconnect/reconnect both clients after `rejoin-ready`, save and restart the host from `mir5-scripted-effects-multiplayer-restart` after `restart-ready`, and reconnect both clients again.

The scenario uses actual accelerated lab completions, native agricultural-tower planting, fixture-only shortened spoil clocks, wall damage and passive repair, and a created/merged offset force. It has no renderer, performance, or general multiplayer-stress claim.

The gameplay runner uses the native low graphics preset and low video-memory usage for both clients. This keeps Space Age texture allocation within the governed process-tree budget; it is not an ordinary-menu or graphical-performance comparison. Pending repair is observed from the first host tick after reload, including repair while the real clients reconnect.

The offset merge follows the F200 `LuaGameScript.merge_forces(source, destination)` contract: the destination retains its technologies and bonuses. The existing native destination-level observation in `spec/mir5/evidence/caps-api-current-native.json` records source level 3 and retained destination level 1. This fixture therefore reads the player target only after source removal, expects its earned level 2 and a `2 * 1.01` spoilage multiplier, and leaves the exact F200 multiplayer confirmation to its native run.

# Override interactions fixture

Private Factorio 2.1.23 witness for one selected nondefault prototype-override policy. It checks native CreateOnly runtime maps and one actual module-productivity craft, then saves and requires two cold reloads when run by the native controller.

The fixture writes `mir5-native-complete.zip`, matching the existing native runner's completion and cold-reload path. The host control derives the expected basename from that runner and checks the actual fixture save call.

The selected cap (`100%`) and recycle chance (`20%`) leave the optional self-recycling classifier inactive: `1 <= 4`. Its deeper safety branch remains covered by the focused host controls. The data-stage receiver value is `1W`; F210 exposes its runtime `energy_usage` as `1 / 60` joules per tick. Exact pipeline extent and receiver ranges are data-stage witnesses because Factorio's F210 runtime API does not expose those properties. Recycling's 20% result is intentionally not asserted as a deterministic physical item count.

The fixture sets only `utility-constants.default.default_pipeline_extent` to `640`, leaves the first chemical-plant fluid-box extent omitted, and retains `320` on every remaining box. At the selected 150% policy the data-stage witness therefore requires first-box inherited `960`, each later explicit `480`, and the unchanged global `640`. Earlier native evidence used the all-explicit 320 input and remains distinct; this changed fixture input requires a new native observation.

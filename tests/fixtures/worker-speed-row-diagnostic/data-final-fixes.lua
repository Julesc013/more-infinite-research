-- Disposable, read-only late-data witness. Stop before prototype validation,
-- map creation or runtime; this never supplies research or cap authority.
local expected = {
  base = "2.0.77", ["more-infinite-research"] = "5.0.20015", ["space-exploration"] = "0.7.57",
  ["aai-containers"] = "0.3.2", ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4",
  ["alien-biomes-graphics"] = "0.7.1", jetpack = "0.4.17", robot_attrition = "0.6.6",
  ["shield-projector"] = "0.2.2", ["space-exploration-graphics"] = "0.7.5",
  ["space-exploration-graphics-2"] = "0.7.2", ["space-exploration-graphics-3"] = "0.7.2",
  ["space-exploration-graphics-4"] = "0.7.2", ["space-exploration-graphics-5"] = "0.7.3",
  ["space-exploration-menu-simulations"] = "0.7.4", ["space-exploration-postprocess"] = "0.7.5",
  informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3",
  ["mir-fixture-mir5-worker-speed-row-diagnostic"] = "0.1.0",
}
local count = 0
for name, version in pairs(mods) do
  if expected[name] ~= version then error("[MIR_SE_WORKER_ROW_DIAGNOSTIC] unexpected mod: " .. name) end
  count = count + 1
end
if count ~= 20 then error("[MIR_SE_WORKER_ROW_DIAGNOSTIC] mod count differs") end
if settings.startup["mir-max-level-worker-robots-speed"].value ~= 0
    or settings.startup["mir-settings-profile-import"].value ~= "" then
  error("[MIR_SE_WORKER_ROW_DIAGNOSTIC] startup controls differ")
end
local snapshot = {kind = "MIRSEWorkerRowsV1", mods = mods, cap = 0, rows = {}}
-- Ten fixed names only. No prototype catalogue or prerequisite traversal.
for level = 6, 15 do
  local name = "worker-robots-speed-" .. level
  local row = data.raw.technology[name]
  snapshot.rows[name] = row and {
    present = true, name = row.name, max_level = row.max_level,
    max_level_type = type(row.max_level), effects = row.effects,
    prerequisites = row.prerequisites, unit = row.unit,
  } or {present = false}
end
log("[MIR_SE_WORKER_ROW_DIAGNOSTIC] SNAPSHOT " .. serpent.line(snapshot, {comment = false, sortkeys = true}))
error("[MIR_SE_WORKER_ROW_DIAGNOSTIC] STOP_AFTER_READ_ONLY_SNAPSHOT", 0)

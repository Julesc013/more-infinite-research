local mir_version = mods and mods["more-infinite-research"] or nil

-- Factorio 2.0 isolates cross-mod Lua module caches. The 2.5 campaign therefore
-- compares exact-archive total load times symmetrically and reads native
-- compiler telemetry from the candidate in data-final-fixes. Keep this fixture
-- fail-closed to the one governed legacy release pair.
if mir_version ~= "2.4.9" and mir_version ~= "2.5.0" then
  error("performance probe does not govern MIR version " .. tostring(mir_version))
end

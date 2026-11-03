-- Observational startup checkpoints. Factorio supplies the timestamps; no
-- timer, persistent state, extra enumeration or prototype mutation lives here.
local M = {}

function M.start(stage)
  local lines, progress_lines = 0, 0
  local writer = rawget(_G, "log")
  if type(writer) ~= "function" then writer = rawget(_G, "print") end
  local function emit(text)
    if lines >= 48 or type(writer) ~= "function" then return end
    lines = lines + 1
    -- A broken diagnostic transport must not change research output. Product
    -- errors remain uncaught in their original callers.
    pcall(writer, "[MIR startup] stage=" .. stage .. " " .. text)
  end
  local trace = {}
  function trace.phase(name, event)
    emit("phase=" .. name .. " event=" .. event)
  end
  -- Called only on the existing recipe pass, with scalar counts. The legacy
  -- per-recipe debug option is separate and keeps its original behavior.
  function trace.progress(recipes, matches, targets, complete)
    if not complete and progress_lines >= 8 then return end
    if not complete then progress_lines = progress_lines + 1 end
    emit("phase=recipe-targets event=work recipes=" .. recipes
      .. " candidate_matches=" .. matches .. " targets=" .. targets
      .. " complete=" .. tostring(complete))
  end
  trace.phase("stage", "begin")
  return trace
end

return M

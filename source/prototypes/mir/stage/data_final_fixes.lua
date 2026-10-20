local M = {}

function M.run(options)
  options = options or {}
  -- Diagnostic settings are context-backed.  Commands resolves this stage-only
  -- request after activating its new Context, before any compilation work.
  -- Generic run_all() remains full by default even when it returns Context.
  return require("prototypes.mir.pipeline.commands").run_stage({
    capture_full_export = options.capture_full_export == true
  })
end

return M

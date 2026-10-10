-- Runtime-only Library services. Resolve engine objects inside callbacks,
-- never while control.lua is being loaded or from persisted state.
local M = {}

function M.prototype_collections()
  return prototypes
end

function M.write_file(path, contents, append, player_index)
  return helpers.write_file(path, contents, append, player_index)
end

return M

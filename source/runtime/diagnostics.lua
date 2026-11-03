-- Latest bounded support report. No history, storage, handlers or engine-log reads.
local output = require("runtime.settings_commands")
local target = require("platform.target")
local M = {filename = "more-infinite-research/mir.log"}
local MAX_BYTES, MAX_MODS, MAX_QUEUE = 65536, 512, 32

local function scalar(value)
  if type(value) == "string" then
    if #value > 256 then return "[text exceeds 256 bytes]" end
    return value:gsub("[%z\1-\31\127]", " ")
  end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  return "unavailable"
end

local function read(object, key)
  local ok, value = pcall(function() return object and object[key] end)
  if ok then return value end
end

local function report(stage, player, selected, profile, profile_file, options)
  local lines, bytes, truncated = {}, 0, false
  local function add(key, value)
    if truncated then return end
    local line = key .. ": " .. scalar(value) .. "\n"
    if bytes + #line > MAX_BYTES - 64 then
      lines[#lines + 1], truncated = "Report truncated at the 64 KiB limit.\n", true
      return
    end
    lines[#lines + 1], bytes = line, bytes + #line
  end
  add("MIR diagnostic report", "latest snapshot; not a complete engine log")
  add("Written after", stage)
  add("MIR", script and script.active_mods and script.active_mods["more-infinite-research"])
  add("Edition", target.id)
  add("Engine", helpers and helpers.game_version)
  add("Sharing", "Metadata/settings exports can include your username. Engine logs may include local paths.")
  add("Full session/startup/crash evidence", "attach factorio-current.log separately; this mod cannot read it")
  local names, versions = {}, script and script.active_mods or {}
  for name in pairs(versions) do
    names[#names + 1] = name
    if #names > MAX_MODS then break end
  end
  if #names > MAX_MODS then
    add("Active mods", "over 512; list omitted at the report bound")
  else
    table.sort(names)
    for _, name in ipairs(names) do add("Mod " .. scalar(name), versions[name]) end
  end
  if player then
    add("Requested by", player.name)
    local force = player.force
    add("Force", read(force, "name"))
    add("Force index", read(force, "index"))
    add("Current research", read(read(force, "current_research"), "name"))
    add("Current research progress", read(force, "research_progress"))
    for _, field in ipairs({"manual_mining_speed_modifier", "laboratory_productivity_bonus",
        "mining_drill_productivity_bonus", "inserter_stack_size_bonus"}) do
      add("Native total " .. field, read(force, field))
    end
    local technologies = read(force, "technologies")
    local technology = type(selected) == "string" and read(technologies, selected) or nil
    add("Selected research", technology and selected)
    for _, field in ipairs({"level", "researched", "enabled", "visible_when_disabled"}) do
      add("Selected " .. field, read(technology, field))
    end
    local queue = read(force, "research_queue")
    if queue then
      for index, entry in ipairs(queue) do
        if index > MAX_QUEUE then add("Queue", "remaining entries omitted after 32"); break end
        add("Queue " .. index, type(entry) == "string" and entry or read(entry, "name"))
      end
    end
  end
  if options and options.report_omissions == true then
    add("Availability scope", "current authored availability explanations; not a complete generation ledger")
    local rows = options.availability_rows
    if type(rows) ~= "table" then
      add("Availability", "unavailable in this context")
    else
      local count = 0
      for index = 1, 251 do
        local row = rows[index]
        if row == nil then break end
        if index > 250 then add("Availability", "remaining entries omitted after 250"); break end
        add("Availability " .. scalar(read(row, "family")), read(row, "reason"))
        count = count + 1
      end
      if count == 0 then add("Availability", "no current authored explanations in this context") end
    end
  end
  if profile then
    add("Effective MIR settings", "full MIRSET1 profile; other mods/map/research are separate")
    add("Settings file", "script-output/" .. profile_file)
    -- The existing exporter retains the complete string in its own file.
    if options and options.report_settings ~= true then
      add("Profile text", "omitted by personal choice; the full settings file is exported separately")
    elseif not truncated and #profile <= 32768 and bytes + #profile < MAX_BYTES - 64 then
      lines[#lines + 1] = "MIRSET1 profile:\n" .. profile .. "\n"
    else
      add("Profile text", "see the complete settings file; omitted here to keep this report bounded")
    end
  end
  return table.concat(lines)
end

-- A snapshot preview never writes files or messages. Unchecked settings avoid
-- building/encoding the full profile merely to open the Help view.
function M.preview(player_index, selected, options)
  local player = player_index and game.get_player(player_index) or nil
  local profile, profile_file
  if options == nil or options.report_settings == true then
    local ok
    ok, profile, profile_file = pcall(output.capture_export, {player_index = player_index})
    if not ok then return nil, tostring(profile) end
    if not profile then return nil, profile_file end
  end
  return report("preview snapshot; no files written", player, selected, profile, profile_file, options)
end

function M.startup(stage)
  local ok, err = output.write_export_file(M.filename, report(stage), 0)
  if not ok then log("[more-infinite-research] MIR diagnostic header failed: " .. tostring(err)) end
end

function M.export(player_index, selected, options)
  local player = player_index and game.get_player(player_index) or nil
  local profile, profile_file = output.export({player_index = player_index})
  if not profile then return nil, profile_file end
  local text = report("explicit export", player, selected, profile, profile_file, options)
  local ok, err = output.write_export_file(M.filename, text, player_index)
  if not ok then
    local message = "MIR diagnostics export failed: " .. tostring(err)
    if player then player.print(message) else log("[more-infinite-research] " .. message) end
    return nil, err
  end
  if player then player.print({"mir-browser.diagnostics-exported", "script-output/" .. M.filename}) end
  return profile, profile_file, text
end

return M

-- Insert archived provider jobs around surviving queue entries. The live queue
-- stays in its current order, including work added while the provider was absent.
local M = {}

function M.merge(live, archived, private_id, ordinary_id, protect_current)
  local positions, insertion_points = {}, {}
  for index, name in ipairs(live.queue) do
    local candidates = positions[name] or {}
    candidates[#candidates+1] = index
    positions[name] = candidates
  end
  -- Match from the tail so completed repetitions at the old head don't take
  -- the same anchor as the repetitions still present in the native queue.
  local boundary = #live.queue + 1
  for index = #archived.queue, 1, -1 do
    local name = archived.queue[index]
    if archived.technologies[name] then
      insertion_points[index] = boundary
    else
      local candidates = positions[name == private_id and ordinary_id or name]
      if candidates and #candidates > 0 then boundary = table.remove(candidates) end
    end
  end
  -- Demoting the live head parks its active progress in the same save slot.
  local head_saved = live.current and live.queued_saved[live.current] or 0
  local keep_head = protect_current and live.current_progress > 0
    or head_saved > 0 and head_saved ~= live.current_progress
  local insert, last = {}, keep_head and 2 or 1
  for index, name in ipairs(archived.queue) do
    if insertion_points[index] then
      -- An intervening reorder can reverse two old anchors. Retain both
      -- queues' internal order by placing subsequent provider jobs no earlier.
      last = math.max(last, insertion_points[index])
      local bucket = insert[last] or {}
      bucket[#bucket+1] = name
      insert[last] = bucket
    end
  end

  local saved, queue, provider_progress = {}, {}, {}
  for name, value in pairs(live.queued_saved) do saved[name] = value end
  for index = 1, #live.queue+1 do
    for _, name in ipairs(insert[index] or {}) do queue[#queue+1] = name end
    if live.queue[index] then queue[#queue+1] = live.queue[index] end
  end
  local current = queue[1]
  if live.current and live.current ~= current then saved[live.current] = live.current_progress end
  if archived.current and archived.technologies[archived.current] and archived.current ~= current
      and archived.technologies[archived.current].saved_progress ~= 0
      and archived.technologies[archived.current].saved_progress ~= archived.current_progress then
    error("MIR provider current and parked progress cannot occupy the same native entry", 2)
  end
  for name, row in pairs(archived.technologies) do
    local progress = row.saved_progress
    if name == archived.current and current ~= name then progress = archived.current_progress end
    provider_progress[name] = progress
  end
  for _, name in ipairs(queue) do
    if archived.technologies[name] then saved[name] = provider_progress[name] end
  end
  local progress = current and saved[current] or 0
  if current == live.current then progress = live.current_progress end
  if archived.technologies[current] and current == archived.current then progress = archived.current_progress end
  return {queue=queue, queued_saved=saved, current=current, current_progress=progress}, provider_progress
end

function M.without_waiting(planned, live, waiting)
  local queue, saved = {}, {}
  for _, name in ipairs(planned.queue) do
    if not waiting[name] then
      queue[#queue+1] = name
      saved[name] = planned.queued_saved[name]
    end
  end
  local current, progress = queue[1], 0
  if current == planned.current then
    progress = planned.current_progress
  elseif current and current == live.current then
    progress = live.current_progress
    saved[current] = live.queued_saved[current]
  elseif current then
    progress = saved[current] or 0
  end
  return {queue=queue, queued_saved=saved, current=current, current_progress=progress}
end

return M


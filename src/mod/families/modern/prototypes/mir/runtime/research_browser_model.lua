local M = {page_size = 20, catalogue_limit = 30000}

function M.is_infinite(technology, cap)
  if type(cap) == "number" and cap > 0 then return false end
  local maximum = technology.prototype.max_level
  return maximum == "infinite" or maximum >= 4294967295
end

function M.available(technology)
  if not technology.enabled or technology.researched or technology.prototype.research_trigger then return false end
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then return false end
  end
  return true
end

function M.page(catalogue, force, view, caps, families)
  local matches, rows = 0, {}
  local page = math.max(1, math.floor(tonumber(view.page) or 1))
  local search = string.lower(string.sub(view.search or "", 1, 160))
  local queued = {}
  for _, tech in ipairs(force.research_queue or {}) do queued[tech.name] = true end
  for _, name in ipairs(catalogue) do
    local tech = force.technologies[name]
    if tech then
      local infinite = M.is_infinite(tech, caps[name])
      local mode_ok = view.mode == 1 or (view.mode == 2 and not infinite) or (view.mode == 3 and infinite)
      local state_ok = view.status == 1 or (view.status == 2 and M.available(tech))
        or (view.status == 3 and not M.available(tech) and not tech.researched)
        or (view.status == 4 and queued[name])
      local family = families[name] or "external"
      local family_ok = not view.family or view.family == "all" or family == view.family
      if mode_ok and state_ok and family_ok and (search == "" or string.find(string.lower(name .. " " .. family), search, 1, true)) then
        matches = matches + 1
        if matches > (page - 1) * M.page_size and #rows < M.page_size then rows[#rows + 1] = name end
      end
    end
  end
  local pages = math.max(1, math.ceil(matches / M.page_size))
  if page > pages then
    local adjusted = {}; for k,v in pairs(view) do adjusted[k] = v end
    adjusted.page = pages
    return M.page(catalogue, force, adjusted, caps, families)
  end
  return {rows = rows, count = matches, pages = pages, page = page}
end

function M.can_enqueue(player, technology, action)
  if not (player and player.valid and technology and technology.valid) then return false end
  if technology.force.index ~= player.force.index or not player.force.research_enabled then return false end
  if player.permission_group and not player.permission_group.allows_action(action) then return false end
  if not M.available(technology) then return false end
  for _, queued in ipairs(player.force.research_queue or {}) do
    if queued.name == technology.name then return false end
  end
  -- F200/F210 expose the native queue unconditionally; enqueue never assigns it.
  return true
end

return M

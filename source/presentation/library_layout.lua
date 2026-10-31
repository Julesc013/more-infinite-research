-- Geometry shared by the Library's research and settings browsers.
-- Kept independent of Factorio GUI objects so sizing decisions stay small
-- and testable without loading a game.
local M = {}

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function integer(value)
  return math.floor(value)
end

local function clamp(value, minimum, maximum)
  if maximum < minimum then minimum = maximum end
  return math.max(minimum, math.min(maximum, value))
end

function M.frame_size(resolution, scale, geometry)
  scale = finite(scale) and scale > 0 and scale or 1
  local screen_width = math.max(1, integer(((resolution and resolution.width) or 1280) / scale))
  local screen_height = math.max(1, integer(((resolution and resolution.height) or 720) / scale))
  local max_width, max_height = math.max(1, screen_width - 24), math.max(1, screen_height - 24)
  local min_width, min_height = math.min(480, max_width), math.min(360, max_height)
  local default_width = clamp(math.max(640, integer(screen_width * 0.5)), math.min(640, max_width), max_width)
  local default_height = clamp(math.max(400, integer(screen_height * 0.75)), math.min(400, max_height), max_height)
  local width = finite(geometry and geometry.width) and geometry.width or default_width
  local height = finite(geometry and geometry.height) and geometry.height or default_height
  return integer(clamp(width, min_width, max_width)), integer(clamp(height, min_height, max_height))
end

function M.filter_layout(width)
  local pairs_per_row = width >= 800 and 2 or 1
  local control_width = math.min(280, math.max(100, width / pairs_per_row - 175))
  return pairs_per_row, integer(control_width)
end

function M.content_height(frame_height, pairs_per_row)
  return math.max(120, frame_height - (pairs_per_row == 2 and 210 or 290))
end

function M.split_sizes(width, height)
  local available_width = math.max(1, width - 24)
  local body_height = math.max(80, height - 36)
  local stacked = available_width < 500
  if stacked then
    local list_height = math.max(76, integer(body_height * 0.30))
    return {
      columns = 1,
      list_width = available_width,
      detail_width = available_width,
      list_height = list_height,
      detail_height = math.max(80, body_height - list_height - 8),
    }
  end
  local gap = 12
  local list_width = integer((available_width - gap) * 0.40)
  return {
    columns = 2,
    list_width = list_width,
    detail_width = available_width - gap - list_width,
    list_height = body_height,
    detail_height = body_height,
  }
end

function M.clamp_location(location, resolution, scale, width, height)
  if type(location) ~= "table" or not finite(location.x) or not finite(location.y) then return nil end
  scale = finite(scale) and scale > 0 and scale or 1
  local screen_width = finite(resolution and resolution.width) and resolution.width or 1280
  local screen_height = finite(resolution and resolution.height) and resolution.height or 720
  return {
    x = clamp(location.x, 0, screen_width - width * scale),
    y = clamp(location.y, 0, screen_height - height * scale),
  }
end

function M.resize(resolution, scale, geometry, delta)
  local width, height = M.frame_size(resolution, scale, geometry)
  local resized_width, resized_height = M.frame_size(resolution, scale,
    {width = width + delta, height = height + delta})
  return {width = resized_width, height = resized_height}
end

return M

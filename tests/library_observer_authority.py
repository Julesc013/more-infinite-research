"""Small host-only authority checks shared by passive Library observers.

The lexical check is a tripwire for named assignments, not a Lua parser.
The Lua proxies reject writes to text/opened during executed observer code,
including writes through aliases and to fields which already have a value.
Engine/setup writes outside observer execution retain their ordinary meaning.
"""
import re


GUI_FIELD_ASSIGNMENT = re.compile(r"\b(?:player|root|query)\.(?:text|opened)\s*=(?!=)")


LUA_GUI_AUTHORITY = r'''
  local observer_running=false
  local function observer_callback(fn)
    return function(...)
      local previous=observer_running
      observer_running=true
      local result=table.pack(pcall(fn,...))
      observer_running=previous
      if not result[1] then error(result[2],0) end
      return table.unpack(result,2,result.n)
    end
  end
  local function gui_state(values,role)
    return setmetatable({}, {
      __index=values,
      __newindex=function(_,field,value)
        if observer_running and (field=="text" or field=="opened") then
          error("observer GUI mutation: "..role.."."..field,0)
        end
        values[field]=value
      end,
      __pairs=function() return next,values,nil end,
    })
  end
'''

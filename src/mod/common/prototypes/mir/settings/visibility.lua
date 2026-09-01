local M = {}

local function has_mod(ctx, name)
  return ctx and ctx.mods and ctx.mods[name] ~= nil
end

local function any_mod(ctx, names)
  for _, name in ipairs(names or {}) do
    if has_mod(ctx, name) then
      return true
    end
  end
  return false
end

local function all_mods(ctx, names)
  for _, name in ipairs(names or {}) do
    if not has_mod(ctx, name) then
      return false
    end
  end
  return true
end

function M.evaluate(spec, ctx)
  local rule = (spec and spec.ui_visibility) or { mode = "always" }
  local mode = rule.mode or "always"

  if mode == "always" then
    return {
      visible = true,
      reason = "always"
    }
  end

  if mode == "hidden" then
    return {
      visible = false,
      reason = rule.hidden_reason or "hidden"
    }
  end

  if mode == "visible-if-mods-any" then
    return {
      visible = any_mod(ctx, rule.mods_any),
      reason = rule.hidden_reason or "missing-provider-mod"
    }
  end

  if mode == "visible-if-mods-all" then
    return {
      visible = all_mods(ctx, rule.mods_all),
      reason = rule.hidden_reason or "missing-required-mod"
    }
  end

  if mode == "visible-if-mods-any-or-always-on-base" then
    if rule.base_visible then
      return {
        visible = true,
        reason = "base-visible"
      }
    end

    return {
      visible = any_mod(ctx, rule.mods_any),
      reason = rule.hidden_reason or "missing-provider-mod"
    }
  end

  return {
    visible = true,
    reason = "unknown-visibility-rule"
  }
end

return M

local M = {}

local authorities = {}

local function snapshot_counts(counts)
  return {
    registrations = counts.registrations,
    untrusted_verifications = counts.untrusted_verifications,
    trusted_assertions = counts.trusted_assertions,
    rejected_assertions = counts.rejected_assertions,
    explicit_snapshots = counts.explicit_snapshots,
    full_copies = counts.full_copies
  }
end

function M.new(kind)
  if type(kind) ~= "string" or kind == "" then
    error("Trusted-record authority requires a record kind.", 2)
  end
  if authorities[kind] then
    error("Trusted-record authority is duplicated: " .. kind, 2)
  end

  local trusted = setmetatable({}, {__mode = "k"})
  local counts = {
    registrations = 0,
    untrusted_verifications = 0,
    trusted_assertions = 0,
    rejected_assertions = 0,
    explicit_snapshots = 0,
    full_copies = 0
  }

  local authority = {}

  function authority.register(record, identity)
    if type(record) ~= "table" then
      error("Cannot trust non-table " .. kind .. " record.", 2)
    end
    trusted[record] = identity or true
    counts.registrations = counts.registrations + 1
    return record
  end

  function authority.verify_untrusted(record, verifier, identity)
    if type(verifier) ~= "function" then
      error("Untrusted " .. kind .. " verification requires a verifier.", 2)
    end
    counts.untrusted_verifications = counts.untrusted_verifications + 1
    verifier(record)
    return authority.register(record, identity)
  end

  function authority.assert_trusted(record, identity_check)
    counts.trusted_assertions = counts.trusted_assertions + 1
    local identity = type(record) == "table" and trusted[record] or nil
    if not identity or (identity_check and not identity_check(record, identity)) then
      counts.rejected_assertions = counts.rejected_assertions + 1
      error("Trusted " .. kind .. " record is required.", 2)
    end
    return true
  end

  function authority.is_trusted(record)
    return type(record) == "table" and trusted[record] ~= nil
  end

  function authority.count_snapshot()
    counts.explicit_snapshots = counts.explicit_snapshots + 1
  end

  function authority.count_full_copy()
    counts.full_copies = counts.full_copies + 1
  end

  function authority.metrics()
    return snapshot_counts(counts)
  end

  function authority.reset_metrics()
    for key in pairs(counts) do counts[key] = 0 end
  end

  authorities[kind] = authority
  return authority
end

function M.metrics()
  local result = {}
  for kind, authority in pairs(authorities) do result[kind] = authority.metrics() end
  return result
end

function M.reset_metrics()
  for _, authority in pairs(authorities) do authority.reset_metrics() end
end

return M

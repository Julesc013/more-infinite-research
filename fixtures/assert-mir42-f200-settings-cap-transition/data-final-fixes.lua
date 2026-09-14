local policy_name = "more-infinite-research-maximum-level-policy"

if data.raw["mod-data"] and data.raw["mod-data"][policy_name] then
  error("[mir42-f200-settings-cap-transition] F200 must exercise settings-derived policy, not V3 mod-data transport")
end

log("[mir42-f200-settings-cap-transition] DATA policy-transport=settings-derived-v3 mod-data=absent")

local P = {}

P.default_mode = "custom"

P.modes = {
  custom = {},
  ["vanilla-respectful"] = {
    streams = {
      research_agricultural_growth_speed = { enabled = false },
      research_cargo_landing_pad_count = { enabled = false },
      research_character_reach = { enabled = false },
      research_spoilage_preservation = { enabled = false }
    },
    base_extensions = {
      ["braking-force"] = { enabled = false },
      ["inserter-capacity-bonus"] = { enabled = false },
      ["laser-shooting-speed"] = { enabled = false },
      ["research-speed"] = { enabled = false },
      ["weapon-shooting-speed"] = { enabled = false },
      ["worker-robots-storage"] = { enabled = false }
    }
  },
  ["megabase-balanced"] = {
    streams = {
      research_agricultural_growth_speed = { enabled = false },
      research_cargo_landing_pad_count = { enabled = false },
      research_character_reach = { enabled = false },
      research_spoilage_preservation = { enabled = false }
    },
    base_extensions = {
      ["inserter-capacity-bonus"] = { enabled = false }
    }
  },
  ["unlimited-sandbox"] = {
    streams = {
      research_agricultural_growth_speed = { enabled = true },
      research_cargo_landing_pad_count = { enabled = true },
      research_character_reach = { enabled = true },
      research_spoilage_preservation = { enabled = true }
    },
    base_extensions = {
      ["braking-force"] = { enabled = true },
      ["inserter-capacity-bonus"] = { enabled = true },
      ["laser-shooting-speed"] = { enabled = true },
      ["research-speed"] = { enabled = true },
      ["weapon-shooting-speed"] = { enabled = true },
      ["worker-robots-storage"] = { enabled = true }
    }
  }
}

return P

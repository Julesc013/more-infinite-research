-- One fixture-owned foreign technology; no existing prototype is changed.
data:extend({{
  type="technology", name="mir5-fixture-foreign-hidden-research",
  localised_name="Fixture foreign hidden research", icon="__base__/graphics/technology/automation-1.png",
  icon_size=256, hidden=true, enabled=true, visible_when_disabled=false,
  effects={}, unit={count=1, time=1, ingredients={{"automation-science-pack", 1}}},
}})

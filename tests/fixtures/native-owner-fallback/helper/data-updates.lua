local t=assert(data.raw.technology["steel-plate-productivity"])
assert(t.unit.count_formula=="1.5^L*1000" and t.unit.time==60 and #t.effects==2)
t.unit.count_formula="1000 + 100 * L^2"
t.effects[3]={type="ammo-damage",ammo_category="bullet",modifier=.07}
mir_fixture_foreign_native_before=serpent.block(t,{comment=false,sortkeys=true})
data:extend({{type="recipe",name="mir-fixture-adopt-steel-plate",enabled=false,categories={"crafting"},main_product="steel-plate",allow_productivity=true,auto_recycle=false,
  ingredients={{type="item",name="iron-plate",amount=5}},results={{type="item",name="steel-plate",amount=1}}}})

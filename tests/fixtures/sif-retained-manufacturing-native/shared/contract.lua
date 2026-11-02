-- Independent published policy: FBBA844D owner_policy ABBB5CA8 and diagnostics
-- DA32D686. Original state oracle is Git blob f110e091, never a current oracle.
return {
  fixture="mir-fixture-mir5-sif-retained-manufacturing", case="sif-retained-manufacturing-f200",
  source="4.7.20003", successor="5.0.20002", foreign="mining-productivity-3",
  rows={
    {key="low_density_structure", recipes={"casting-low-density-structure","low-density-structure","scrap-recycling"}},
    {key="plastic", recipes={"bioplastic","plastic-bar"}},
    {key="processing_unit", recipes={"processing-unit"}},
    {key="rocket_fuel", recipes={"ammonia-rocket-fuel","rocket-fuel","rocket-fuel-from-jelly"}},
    {key="steel", recipes={"casting-steel","steel-plate"}},
  },
}

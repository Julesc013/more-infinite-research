local family="research_steel"
for _,row in ipairs({{"int-setting","ips-cost-base-",2},{"int-setting","ips-cost-linear-increment-",3},
    {"double-setting","ips-cost-growth-",1.25},{"int-setting","ips-research-time-",1},
    {"double-setting","ips-effect-per-level-",17}}) do
  local p=assert(data.raw[row[1]][row[2]..family],"required authored setting absent")
  assert(p.setting_type=="startup","wrong setting category")
  p.default_value=row[3]
end

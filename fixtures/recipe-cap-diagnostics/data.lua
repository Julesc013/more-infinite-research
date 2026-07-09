local recipes = data.raw.recipe or {}

if recipes["iron-gear-wheel"] then
  recipes["iron-gear-wheel"].maximum_productivity = 0.2
end

if recipes["copper-cable"] then
  recipes["copper-cable"].maximum_productivity = 1000
end

if recipes["iron-plate"] then
  recipes["iron-plate"].maximum_productivity = 5
end
